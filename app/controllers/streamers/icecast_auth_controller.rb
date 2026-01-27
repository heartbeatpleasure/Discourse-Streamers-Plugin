# frozen_string_literal: true

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

      response.headers["icecast-auth-user"] = "1"
      response.headers["X-Streamers-IcecastAuth"] = "ok"
      render plain: "OK", status: 200
    end

    private

    def normalize_mount(m)
      s = m.to_s.strip
      return "" if s.blank?
      s.start_with?("/") ? s : "/#{s}"
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

    def deny!(reason, context = {})
      Rails.logger.info(
        "[streamers] icecast_auth deny reason=#{reason} ip=#{request.remote_ip} " \
        "ua=#{request.user_agent.inspect} ctx=#{context.inspect}"
      )

      response.headers["X-Streamers-IcecastAuth"] = "deny"
      render json: { error: "unauthorized" }, status: 403
    end
  end
end
