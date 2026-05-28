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
            live_streams: payload[:live_streams],
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

    # Login-protected listen endpoint.
    # The audio element points here, we issue a short signed token and then redirect to Icecast.
    def listen
      mount = listen_mount_param
      return deny_listen!("missing_mount", raw_params: safe_listen_params) if mount.blank?

      setting = setting_for_mount(mount)
      return deny_listen!("unknown_mount", mount: mount, raw_params: safe_listen_params) unless setting

      listen_url = setting.direct_listen_url.to_s
      return deny_listen!("missing_listen_url", mount: mount, setting_id: setting.id) if listen_url.blank?

      token = ::Streamers::ListenerToken.generate(user: current_user, mount: mount)
      redirect_url = append_query_params(listen_url, hb_token: token)

      Rails.logger.info(
        "[streamers] listen redirect user_id=#{current_user&.id} mount=#{mount.inspect} "         "target=#{listen_url.inspect}"
      )

      begin
        redirect_to redirect_url, allow_other_host: true
      rescue ArgumentError
        redirect_to redirect_url
      end
    end

    private

    def enforce_login_requirement
      if ::SiteSetting.streamers_streams_page_requires_login && !current_user
        raise Discourse::InvalidAccess.new
      end
    end

    def normalize_mount(mount)
      s = mount.to_s.strip.split("?", 2).first.to_s
      return "" if s.blank?

      s.start_with?("/") ? s : "/#{s}"
    end

    # Some Discourse/Rails route fallbacks can place the full request path in params[:path]
    # instead of exposing query params normally. The audio player uses an encoded mount,
    # while manual browser tests often use /u/3 unencoded; accept both forms defensively.
    def listen_mount_param
      raw = params[:mount].presence || request.query_parameters["mount"].presence

      if raw.blank?
        raw = ::Rack::Utils.parse_nested_query(request.query_string.to_s)["mount"].presence
      end

      if raw.blank? && params[:path].present?
        raw = params[:path].to_s[/[?&]mount=([^&]+)/, 1]
      end

      if raw.blank?
        raw = request.fullpath.to_s[/[?&]mount=([^&]+)/, 1]
      end

      raw = URI.decode_www_form_component(raw.to_s) if raw.present?
      normalize_mount(raw)
    rescue StandardError => e
      Rails.logger.warn("[streamers] listen mount parse failed: #{e.class}: #{e.message}")
      ""
    end

    def safe_listen_params
      {
        mount: params[:mount].to_s.presence,
        path: params[:path].to_s.presence,
        query_string: request.query_string.to_s.presence
      }.compact
    end

    def deny_listen!(reason, context = {})
      Rails.logger.warn("[streamers] listen deny reason=#{reason} user_id=#{current_user&.id} ctx=#{context.inspect}")
      raise Discourse::InvalidAccess
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

    # Cached payload used by /streams.json
    def cached_streams_payload
      ttl = ::SiteSetting.streamers_streams_cache_seconds.to_i
      key = cache_key("streams_payload_v2")

      return compute_streams_payload if ttl <= 0

      ::Rails.cache.fetch(key, expires_in: ttl.seconds) do
        compute_streams_payload
      end
    end

    # Cached payload used by /streams/status.json (smaller TTL by default)
    def cached_status_payload
      ttl = ::SiteSetting.streamers_streams_status_cache_seconds.to_i
      key = cache_key("streams_status_payload_v2")

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
