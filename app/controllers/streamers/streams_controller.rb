# frozen_string_literal: true

require "uri"
require "rack/utils"

module Streamers
  class StreamsController < ::ApplicationController
    before_action :enforce_login_requirement

    def index
      payload = cached_streams_payload

      respond_to do |format|
        format.json do
          render json: {
            live_streams: live_streams_for_response(payload[:live_streams]),
            updated_at: payload[:updated_at],

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

    private

    def enforce_login_requirement
      if ::SiteSetting.streamers_streams_page_requires_login && !current_user
        raise Discourse::InvalidAccess.new
      end
    end

    def live_streams_for_response(streams)
      Array(streams).map do |stream|
        item = stream.respond_to?(:deep_dup) ? stream.deep_dup : stream.dup
        mount = normalize_mount(stream_value(item, :mount))
        setting = setting_for_mount(mount)
        block_reason = listener_block_reason(setting)

        listen_url = if setting && block_reason.blank?
          signed_or_public_listen_url(setting, current_user)
        else
          ""
        end

        write_stream_value(item, :listen_url, listen_url)
        write_stream_value(item, :listener_blocked, block_reason.present?)
        write_stream_value(item, :listener_blocked_reason, block_reason)
        apply_listener_details_visibility!(item)

        item
      end
    end

    def listener_block_reason(setting)
      return nil unless setting && current_user

      ::Streamers::ListenerBlocking.block_reason(stream_user_id: setting.user_id, listener_user: current_user)
    end

    def apply_listener_details_visibility!(item)
      stream_user_id = stream_value(item, :user_id).to_i
      visible = listener_details_visible_for?(current_user, stream_user_id)

      write_stream_value(item, :listener_details_visible, visible)
      return item if visible

      # Keep the total Icecast listener count visible, but do not expose whether listeners
      # are known/logged-in or who they are when the viewer is not allowed to see details.
      total_listeners = stream_value(item, :listeners).to_i
      write_stream_value(item, :known_listener_count, 0)
      write_stream_value(item, :known_listeners, [])
      write_stream_value(item, :public_listener_count, total_listeners)

      item
    end

    def listener_details_visible_for?(viewer, stream_user_id)
      return false unless viewer

      mode = ::SiteSetting.streamers_listener_details_visibility.to_s.strip.downcase

      case mode
      when "everyone"
        true
      when "streamer"
        viewer.staff? || viewer.id.to_i == stream_user_id.to_i
      when "staff"
        viewer.staff?
      else
        # Fail closed for typos/invalid setting values.
        viewer.staff?
      end
    end

    def stream_value(item, key)
      string_key = key.to_s
      symbol_key = key.to_sym

      return item[symbol_key] if item.respond_to?(:key?) && item.key?(symbol_key)
      return item[string_key] if item.respond_to?(:key?) && item.key?(string_key)

      nil
    end

    def write_stream_value(item, key, value)
      string_key = key.to_s
      symbol_key = key.to_sym

      if item.respond_to?(:key?) && item.key?(string_key)
        item[string_key] = value
      else
        item[symbol_key] = value
      end
    end

    def signed_or_public_listen_url(setting, user)
      direct_url = setting.direct_listen_url.to_s
      return "" if direct_url.blank?

      # Prefer a signed Icecast URL for every logged-in listener when listener tracking is
      # configured. Public listen URLs may still be allowed as a fallback, but the normal
      # Discourse player should carry hb_token so listener_add can map the Icecast client
      # back to the Discourse user.
      if user && listener_tracking_configured?
        token = ::Streamers::ListenerToken.generate(user: user, mount: setting.public_mount)
        return append_query_params(direct_url, hb_token: token)
      end

      return direct_url if ::SiteSetting.streamers_public_listen_url_enabled
      return direct_url unless ::SiteSetting.streamers_icecast_listener_auth_enabled

      ""
    rescue StandardError => e
      ::Rails.logger.warn(
        "[streamers] failed to build signed listen_url setting_id=#{setting&.id.inspect} " \
        "mount=#{setting&.public_mount.inspect} user_id=#{user&.id.inspect}: #{e.class}: #{e.message}"
      )

      direct_url = setting&.direct_listen_url.to_s
      if direct_url.present? && ::SiteSetting.streamers_public_listen_url_enabled
        ::Rails.logger.warn(
          "[streamers] falling back to public listen_url setting_id=#{setting&.id.inspect} " \
          "user_id=#{user&.id.inspect}"
        )
        return direct_url
      end

      ""
    end

    def listener_tracking_configured?
      ::SiteSetting.streamers_icecast_listener_auth_enabled ||
        ::SiteSetting.streamers_icecast_listener_auth_secret.to_s.present?
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
      key = cache_key("streams_payload_v6")

      return compute_streams_payload if ttl <= 0

      ::Rails.cache.fetch(key, expires_in: ttl.seconds) do
        compute_streams_payload
      end
    end

    # Cached payload used by /streams/status.json (smaller TTL by default)
    def cached_status_payload
      ttl = ::SiteSetting.streamers_streams_status_cache_seconds.to_i
      key = cache_key("streams_status_payload_v6")

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
