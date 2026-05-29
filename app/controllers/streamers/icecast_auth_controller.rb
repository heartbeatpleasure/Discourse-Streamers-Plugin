# frozen_string_literal: true

require "rack/utils"
require "base64"

module Streamers
  class IcecastAuthController < ::ActionController::Base
    protect_from_forgery with: :null_session

    def create
      plugin = Discourse.plugins_by_name[::Streamers::PLUGIN_NAME] rescue nil
      if plugin && !plugin.enabled?
        render json: { error: "unauthorized" }, status: 404
        return
      end

      unless SiteSetting.streamers_enabled? && SiteSetting.streamers_icecast_source_auth_enabled
        deny!("disabled")
        return
      end

      mount  = normalize_mount(params[:mount].to_s)
      user_s = (params[:user].presence || params[:username].to_s).to_s
      pass   = (params[:pass].presence || params[:password].to_s).to_s
      client = params[:client].to_s

      if mount.blank? || user_s.blank? || pass.blank?
        deny!("missing_params")
        return
      end

      if client.present? && client != "source"
        deny!("unsupported_client")
        return
      end

      discourse_user = ::User.find_by(username: user_s)
      unless discourse_user
        deny!("unknown_user", user: user_s, mount: mount)
        return
      end

      unless allowed_user?(discourse_user)
        deny!("not_allowed", user_id: discourse_user.id, mount: mount)
        return
      end

      setting = ::Streamers::UserSetting.find_by(user_id: discourse_user.id)
      if !setting || !setting.enabled?
        deny!("streaming_disabled", user_id: discourse_user.id, mount: mount)
        return
      end

      unless setting.valid_stream_key?(pass)
        deny!("invalid_stream_key", user_id: discourse_user.id, mount: mount)
        return
      end

      expected_mount = normalize_mount(setting.public_mount)
      if mount != expected_mount
        deny!("wrong_mount", user_id: discourse_user.id, mount: mount)
        return
      end

      begin
        setting.mark_stream_started!
      rescue => e
        Rails.logger.warn(
          "[streamers] failed to mark stream started for user #{discourse_user.id}: " \
          "#{e.class}: #{e.message}"
        )
      end

      accept!("source")
    end

    def listener_add
      plugin = Discourse.plugins_by_name[::Streamers::PLUGIN_NAME] rescue nil
      if plugin && !plugin.enabled?
        render json: { error: "unauthorized" }, status: 404
        return
      end

      unless SiteSetting.streamers_enabled?
        deny!("disabled")
        return
      end

      unless callback_authenticated?
        deny!("callback_auth_failed")
        return
      end

      raw_mount = params[:mount].to_s
      mount = normalize_mount(raw_mount)

      # Icecast applies URL listener-auth from the default mount to more than audio mounts.
      # Status/UI requests such as /status-json.xsl also pass through listener_add.
      # These must be allowed but never tracked as listeners, otherwise Discourse cannot
      # read Icecast status-json.xsl and the streams page appears empty.
      if system_listener_mount?(mount)
        Rails.logger.info("[streamers] icecast_auth allow reason=system_mount mount=#{mount.inspect}")
        accept!("system_mount")
        return
      end

      setting = stream_setting_for_mount(mount)

      unless setting
        deny!("unknown_mount", mount: mount)
        return
      end

      token = extract_listener_token(raw_mount)
      listener_user = user_from_listener_token(token, mount)
      token_required = listener_token_required?
      token_present = token.present?

      # If a client supplies a token, it must be valid. Do not degrade an expired,
      # tampered or wrong-mount token to a public/unknown listener, otherwise a paused
      # browser audio element can resume with an old URL and reappear as anonymous.
      if token_present && !listener_user
        deny!("listener_token_invalid", mount: mount)
        return
      end

      if token_required && !listener_user
        deny!("listener_token_required", mount: mount)
        return
      end

      if listener_user
        block_reason = ::Streamers::ListenerBlocking.block_reason(
          stream_user_id: setting.user_id,
          listener_user: listener_user
        )

        if block_reason.present?
          deny!("listener_blocked", mount: mount, user_id: listener_user.id, source: block_reason)
          return
        end

        begin
          ::Streamers::ListenerSession.record_add!(
            stream_user_id: setting.user_id,
            mount: mount,
            client_id: listener_client_id,
            user: listener_user,
            request: request
          )
        rescue => e
          Rails.logger.warn(
            "[streamers] failed to record listener_add mount=#{mount.inspect} " \
            "client=#{listener_client_id.inspect}: #{e.class}: #{e.message}"
          )
        end
      end

      accept!(listener_user ? "listener_known" : "listener_public")
    end

    def listener_remove
      unless SiteSetting.streamers_enabled?
        render plain: "OK", status: 200
        return
      end

      unless callback_authenticated?
        deny!("callback_auth_failed")
        return
      end

      mount = normalize_mount(params[:mount].to_s)
      client_id = listener_client_id

      if system_listener_mount?(mount)
        render plain: "OK", status: 200
        return
      end

      begin
        ::Streamers::ListenerSession.record_remove!(
          mount: mount,
          client_id: client_id,
          duration: params[:duration]
        )
      rescue => e
        Rails.logger.warn(
          "[streamers] failed to record listener_remove mount=#{mount.inspect} " \
          "client=#{client_id.inspect}: #{e.class}: #{e.message}"
        )
      end

      render plain: "OK", status: 200
    end

    private

    def normalize_mount(m)
      s = m.to_s.strip.split("?", 2).first.to_s
      return "" if s.blank?
      s.start_with?("/") ? s : "/#{s}"
    end

    def stream_setting_for_mount(mount)
      return nil if mount.blank?

      ::Streamers::UserSetting.enabled.find_each do |setting|
        return setting if normalize_mount(setting.public_mount) == mount
      end

      nil
    end

    def system_listener_mount?(mount)
      normalized = normalize_mount(mount)
      return false if normalized.blank?

      [
        "/status-json.xsl",
        "/status.xsl",
        "/server_version.xsl"
      ].include?(normalized)
    end

    def extract_listener_token(raw_mount)
      direct = (params[:hb_token].presence || params[:token].presence).to_s
      return direct if direct.present?

      query = raw_mount.to_s.split("?", 2)[1].to_s
      return "" if query.blank?

      parsed = ::Rack::Utils.parse_nested_query(query)
      (parsed["hb_token"].presence || parsed["token"].presence).to_s
    rescue StandardError
      ""
    end

    def user_from_listener_token(token, mount)
      payload = ::Streamers::ListenerToken.verify(token)
      return nil unless payload
      return nil unless normalize_mount(payload["mount"].to_s) == mount

      ::User.find_by(id: payload["user_id"].to_i)
    end

    def listener_token_required?
      SiteSetting.streamers_icecast_listener_auth_enabled && !SiteSetting.streamers_public_listen_url_enabled
    end

    def listener_client_id
      (params[:client].presence || params[:client_id].presence || params[:id].presence).to_s
    end

    def callback_authenticated?
      secret = SiteSetting.streamers_icecast_listener_auth_secret.to_s
      return true if secret.blank?

      supplied = (
        params[:secret].presence ||
        request.headers["X-Streamers-Listener-Secret"].presence ||
        basic_auth_password.presence
      ).to_s

      secure_compare(secret, supplied)
    end

    def basic_auth_password
      auth = request.authorization.to_s
      return "" unless auth.start_with?("Basic ")

      decoded = Base64.decode64(auth.split(" ", 2)[1].to_s)
      decoded.split(":", 2)[1].to_s
    rescue StandardError
      ""
    end

    def allowed_user?(user)
      return false if excluded_from_streaming?(user.username)

      group_name = SiteSetting.streamers_group_name.to_s
      return false if group_name.blank?

      group = ::Group.find_by(name: group_name)
      return false if group.blank?

      ::GroupUser.exists?(group_id: group.id, user_id: user.id)
    end

    def excluded_from_streaming?(username)
      raw = SiteSetting.streamers_force_exclude_from_streamers
      list = raw.is_a?(Array) ? raw : raw.to_s.split("|")
      excluded = list.map { |u| u.to_s.strip.downcase }.reject(&:blank?)
      excluded.include?(username.to_s.strip.downcase)
    end

    def accept!(reason)
      response.headers["icecast-auth-user"] = "1"
      response.headers["X-Streamers-IcecastAuth"] = "ok"
      response.headers["X-Streamers-IcecastAuth-Reason"] = reason.to_s
      render plain: "OK", status: 200
    end

    def deny!(reason, context = {})
      Rails.logger.info(
        "[streamers] icecast_auth deny reason=#{reason} ip=#{request.remote_ip} " \
        "ua=#{request.user_agent.inspect} ctx=#{context.inspect}"
      )

      response.headers["X-Streamers-IcecastAuth"] = "deny"
      render json: { error: "unauthorized" }, status: 403
    end

    def secure_compare(a, b)
      return false if a.blank? || b.blank?
      return false unless a.bytesize == b.bytesize

      ActiveSupport::SecurityUtils.secure_compare(a, b)
    end
  end
end
