# frozen_string_literal: true

require "uri"
require "rack/utils"

module Streamers
  class StreamsController < ::ApplicationController
    before_action :enforce_login_requirement, except: [:listen]
    before_action :ensure_logged_in, only: [:listen]

    def index
      payload = cached_streams_payload

      respond_to do |format|
        format.json do
          render json: {
            live_streams: live_streams_for_response(payload[:live_streams]),
            updated_at:   payload[:updated_at],

            # Optional shared chat/discussion topic for the streams page.
            # 0 disables the chat button in the UI.
            chat_topic_id: ::SiteSetting.streamers_chat_topic_id.to_i
          }
        end

        format.html do
          # frontend (theme component) pakt deze route en render zelf
          render layout: "application"
        end
      end
    end

    # Lightweight endpoint for menu indicator
    # Returns only live boolean + count
    def status
      payload = cached_status_payload

      render json: {
        live: payload[:live],
        count: payload[:count],
        updated_at: payload[:updated_at]
      }
    end

    # Compatibility endpoint. The player no longer depends on this route because Discourse's
    # client-side router can intercept custom HTML routes in some setups. /streams.json now
    # receives a signed direct Icecast URL instead.
    def listen
      mount = normalize_mount(params[:mount].to_s)
      raise Discourse::InvalidAccess if mount.blank?

      setting = setting_for_mount(mount)
      raise Discourse::InvalidAccess unless setting

      listen_url = signed_or_public_listen_url(setting, current_user)
      raise Discourse::InvalidAccess if listen_url.blank?

      begin
        redirect_to listen_url, allow_other_host: true
      rescue ArgumentError
        redirect_to listen_url
      end
    end

    private

    def enforce_login_requirement
      if ::SiteSetting.streamers_streams_page_requires_login && !current_user
        raise Discourse::InvalidAccess.new
      end
    end

    def live_streams_for_response(streams)
      Array(streams).map do |stream|
        item = stream.respond_to?(:deep_dup) ? stream.deep_dup : stream.dup
        mount = normalize_mount(item[:mount] || item["mount"])
        setting = setting_for_mount(mount)

        item[:listen_url] = setting ? signed_or_public_listen_url(setting, current_user) : ""
        item
      end
    end

    def signed_or_public_listen_url(setting, user)
      direct_url = setting.direct_listen_url.to_s
      return "" if direct_url.blank?

      if user
        token = ::Streamers::ListenerToken.generate(user: user, mount: setting.public_mount)
        return append_query_params(direct_url, hb_token: token)
      end

      ::SiteSetting.streamers_public_listen_url_enabled ? direct_url : ""
    rescue StandardError => e
      ::Rails.logger.warn(
        "[streamers] failed to build listen_url setting_id=#{setting&.id.inspect} " \
        "user_id=#{user&.id.inspect}: #{e.class}: #{e.message}"
      )
      ""
    end

    def normalize_mount(mount)
      s = mount.to_s.strip.split("?", 2).first.to_s
      return "" if s.blank?

      s.start_with?("/") ? s : "/#{s}"
    end

    def setting_for_mount(mount)
      return nil if mount.blank?

      ::Streamers::UserSetting.enabled.find_each do |setting|
        return setting if normalize_mount(setting.public_mount) == mount
      end

      nil
    end

    def append_query_params(url, params_hash)
      uri = URI.parse(url)
      raise URI::InvalidURIError unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

      current = ::Rack::Utils.parse_nested_query(uri.query.to_s)
      params_hash.each { |key, value| current[key.to_s] = value }
      uri.query = current.to_query
      uri.to_s
    end

    # Cached payload used by /streams.json.
    # The cached payload intentionally does not contain user-specific listen tokens.
    def cached_streams_payload
      ttl = ::SiteSetting.streamers_streams_cache_seconds.to_i
      key = cache_key("streams_payload_v4")

      return compute_streams_payload if ttl <= 0

      ::Rails.cache.fetch(key, expires_in: ttl.seconds) do
        compute_streams_payload
      end
    end

    # Cached payload used by /streams/status.json (smaller TTL by default)
    def cached_status_payload
      ttl = ::SiteSetting.streamers_streams_status_cache_seconds.to_i
      key = cache_key("streams_status_payload_v4")

      return compute_status_payload if ttl <= 0

      ::Rails.cache.fetch(key, expires_in: ttl.seconds) do
        compute_status_payload
      end
    end

    def compute_streams_payload
      status       = LiveStatus.new
      live_streams = status.live_streams

      {
        live_streams: live_streams,
        updated_at: status.updated_at&.iso8601
      }
    end

    def compute_status_payload
      streams_payload = compute_streams_payload
      streams = streams_payload[:live_streams]
      count = streams.is_a?(Array) ? streams.length : 0

      {
        live: count.positive?,
        count: count,
        updated_at: streams_payload[:updated_at]
      }
    end

    def cache_key(suffix)
      db =
        if defined?(::RailsMultisite::ConnectionManagement) &&
             ::RailsMultisite::ConnectionManagement.respond_to?(:current_db)
          ::RailsMultisite::ConnectionManagement.current_db
        else
          "default"
        end

      "streamers:#{suffix}:#{db}"
    end
  end
end
