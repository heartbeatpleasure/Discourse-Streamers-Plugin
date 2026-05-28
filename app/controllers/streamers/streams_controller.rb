# frozen_string_literal: true

require "uri"
require "rack/utils"
require "cgi"

module Streamers
  class StreamsController < ::ApplicationController
    before_action :enforce_login_requirement, except: [:listen]

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
      ::Rails.logger.warn(
        "[streamers] listen entered user_id=#{current_user&.id.inspect} " \
        "params=#{safe_params_for_log.inspect} fullpath=#{request.fullpath.inspect} " \
        "format=#{request.format.to_s.inspect}"
      )

      return deny_listen!("not_logged_in") unless current_user

      mount = normalize_mount(listen_mount_param)
      return deny_listen!("missing_mount") if mount.blank?

      setting = setting_for_mount(mount)
      return deny_listen!("unknown_or_disabled_mount", mount: mount) unless setting

      listen_url = setting.direct_listen_url.to_s
      return deny_listen!("blank_listen_url", mount: mount, user_id: setting.user_id) if listen_url.blank?

      token = ::Streamers::ListenerToken.generate(user: current_user, mount: mount)
      redirect_url = append_query_params(listen_url, hb_token: token)

      ::Rails.logger.warn(
        "[streamers] listen redirect user_id=#{current_user&.id} mount=#{mount.inspect} " \
        "to=#{redacted_url(redirect_url).inspect}"
      )

      redirect_to_external_url(redirect_url)
    rescue URI::InvalidURIError => e
      deny_listen!("invalid_listen_url", error: e.message)
    rescue StandardError => e
      ::Rails.logger.warn("[streamers] listen error #{e.class}: #{e.message}")
      raise
    end

    private

    def enforce_login_requirement
      if ::SiteSetting.streamers_streams_page_requires_login && !current_user
        raise Discourse::InvalidAccess.new
      end
    end

    # Discourse/Rails route handling can sometimes expose the original URL through params[:path]
    # instead of normal query params. Be deliberately tolerant so the player keeps working with
    # both encoded and unencoded mounts:
    #   /streamers/listen?mount=%2Fu%2F3
    #   /streamers/listen?mount=/u/3
    def listen_mount_param
      candidates = []
      candidates << params[:mount]
      candidates << request.query_parameters["mount"]

      begin
        candidates << request.GET["mount"]
      rescue StandardError
        # ignore Rack parse edge cases
      end

      candidates << parsed_mount_from_query(request.query_string)
      candidates << parsed_mount_from_query(request.fullpath)
      candidates << parsed_mount_from_query(params[:path].to_s)

      candidates.each do |candidate|
        mount = decode_mount_candidate(candidate)
        return mount if mount.present?
      end

      ""
    end

    def parsed_mount_from_query(value)
      s = value.to_s
      return "" if s.blank?

      query = s.include?("?") ? s.split("?", 2)[1].to_s : s
      return "" if query.blank?

      parsed = ::Rack::Utils.parse_nested_query(query)
      parsed["mount"].to_s.presence || query[/[?&]?mount=([^&]+)/, 1].to_s
    rescue StandardError
      s[/[?&]mount=([^&]+)/, 1].to_s
    end

    def decode_mount_candidate(value)
      s = value.to_s.strip
      return "" if s.blank?

      2.times do
        decoded = ::CGI.unescape(s)
        break if decoded == s
        s = decoded
      end

      s
    rescue StandardError
      value.to_s.strip
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

    def redacted_url(url)
      uri = URI.parse(url.to_s)
      params = ::Rack::Utils.parse_nested_query(uri.query.to_s)
      params["hb_token"] = "[redacted]" if params.key?("hb_token")
      uri.query = params.present? ? params.to_query : nil
      uri.to_s
    rescue StandardError
      "[invalid_url]"
    end


    def redirect_to_external_url(url)
      begin
        redirect_to url, allow_other_host: true
      rescue ArgumentError
        redirect_to url
      end
    end

    def safe_params_for_log
      params.to_unsafe_h.except("hb_token", "secret", "password", "pass")
    rescue StandardError
      {}
    end

    def deny_listen!(reason, context = {})
      ::Rails.logger.warn(
        "[streamers] listen denied reason=#{reason} user_id=#{current_user&.id.inspect} " \
        "params=#{params.to_unsafe_h.inspect} fullpath=#{request.fullpath.inspect} ctx=#{context.inspect}"
      )

      respond_to do |format|
        format.json { render json: { error: reason }, status: 404 }
        format.any  { render plain: "Stream not available", status: 404 }
      end
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
