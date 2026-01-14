# frozen_string_literal: true

module Streamers
  class IcecastAuthController < ::ApplicationController
    requires_plugin ::Streamers::PLUGIN_NAME

    # Dit endpoint wordt aangeroepen door Icecast, niet door browsers
    skip_before_action :verify_authenticity_token
    skip_before_action :redirect_to_login_if_required

    def create
      unless SiteSetting.streamers_icecast_source_auth_enabled
        render plain: "auth disabled", status: 403
        return
      end

      mount = params[:mount].to_s
      password = params[:pass].to_s
      action = params[:action].to_s # Icecast gebruikt ook action=stream_auth

      if mount.blank? || password.blank?
        Rails.logger.warn("[streamers] Icecast auth: missing mount or pass")
        return deny!("missing mount or pass")
      end

      # Optioneel: shared secret / extra validatie kan hier toegevoegd worden

      setting = Streamers::UserSetting.includes(:user).find_by(mount: mount, enabled: true)

      if setting.nil?
        Rails.logger.warn("[streamers] Icecast auth: no setting for mount #{mount}")
        return deny!("unknown mount")
      end

      user = setting.user
      if user.nil?
        Rails.logger.warn("[streamers] Icecast auth: no user for mount #{mount}")
        return deny!("no user")
      end

      if force_excluded?(user)
        Rails.logger.warn("[streamers] Icecast auth: user #{user.id} is force-excluded")
        return deny!("force excluded")
      end

      group = Streamers::LiveStatus.resolve_streamers_group
      if group.nil?
        Rails.logger.warn("[streamers] Icecast auth: streamers group not found")
        return deny!("group missing")
      end

      unless Streamers::LiveStatus.in_streamers_group?(user, group)
        Rails.logger.warn("[streamers] Icecast auth: user #{user.id} not in streamers group")
        return deny!("not in group")
      end

      if setting.stream_key != password
        Rails.logger.warn("[streamers] Icecast auth: invalid key for user #{user.id}")
        return deny!("invalid key")
      end

      # Actie type kan bv. "stream_auth" zijn; voor nu negeren we het.
      now = Time.now.utc
      setting.update_columns(
        last_stream_started_at: now,
        last_seen_live_at: now,
        updated_at: now
      )

      accept!
    rescue StandardError => e
      Rails.logger.warn("[streamers] Icecast auth error: #{e.class} - #{e.message}")
      deny!("internal error")
    end

    private

    def deny!(message)
      # Geen gevoelige info in body of headers.
      response.headers["Icecast-Auth-Message"] = "Access denied"
      render plain: "denied", status: 403
    end

    def accept!
      # Dit is wat Icecast verwacht om de bron te accepteren
      response.headers["icecast-auth-user"] = "1"
      render plain: "ok", status: 200
    end

    def force_excluded?(user)
      user.custom_fields["streamers_force_exclude"].present?
    end
  end
end
