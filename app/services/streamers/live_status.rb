# frozen_string_literal: true
require "uri"

module Streamers
  class LiveStatus
    attr_reader :updated_at

    def initialize
      @updated_at = nil
    end

    def live_streams
      sources = IcecastClient.fetch_sources
      return nil if sources.blank?

      group = allowed_group
      return nil if group.blank?

      excluded = excluded_usernames
      allowed_user_ids = ::GroupUser.where(group_id: group.id).pluck(:user_id)
      return nil if allowed_user_ids.blank?

      settings = UserSetting.includes(:user).where(enabled: true, user_id: allowed_user_ids)
      return nil if settings.blank?

      settings_by_mount = {}
      settings.each do |setting|
        next unless setting.user
        next if excluded.include?(setting.user.username.to_s.downcase)
        settings_by_mount[setting.mount] = setting
      end

      streams = sources.filter_map do |src|
        mount = src["mount"].to_s
        next if mount.blank?

        setting = settings_by_mount[mount]
        next unless setting&.user

        user = setting.user

        raw_title = src["title"].presence || src["server_name"]
        safe_title = sanitize_text(raw_title)

        safe_tag = sanitize_text(setting.try(:stream_tag))
        safe_tag = "" if safe_tag.length > 64

        {
          user_id: user.id,
          username: user.username,
          name: (user.name.presence || user.username),
          avatar_template: user.avatar_template,
          mount: mount,
          listen_url: safe_listen_url(setting),
          listeners: src["listeners"].to_i,
          bitrate: src["bitrate"].to_i,
          title: safe_title,
          stream_tag: (safe_tag.presence),
          stream_started_at: (src["stream_start_iso8601"] || src["stream_start"])
        }
      end

      if streams.any?
        @updated_at = Time.zone.now
        streams
      else
        nil
      end
    rescue StandardError => e
      ::Rails.logger.warn("[streamers] LiveStatus error: #{e.class}: #{e.message}")
      nil
    end

    private

    def allowed_group
      group_name = SiteSetting.streamers_group_name.to_s
      return nil if group_name.blank?
      ::Group.find_by(name: group_name)
    end

    def excluded_usernames
      raw = SiteSetting.streamers_force_exclude_from_streamers
      list = raw.is_a?(Array) ? raw : raw.to_s.split("|")
      list.map { |u| u.to_s.strip.downcase }.reject(&:blank?)
    end

    def sanitize_text(value)
      s = value.to_s
      s = s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      s = ::ActionController::Base.helpers.strip_tags(s)
      s = s.gsub(/[\u0000-\u001f\u007f]/, "")
      s.strip
    end

    # Bouwt de publieke luister-URL op via de bestaande plugin-logica:
    # UserSetting#public_listen_url (afgeleid van streamers_icecast_status_url)
    #
    # We laten alleen http/https door om ellende te voorkomen.
    def safe_listen_url(setting)
      url = setting.public_listen_url.to_s
      return "" if url.blank?

      uri = URI.parse(url)
      return "" unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

      url
    rescue URI::InvalidURIError
      ""
    end
  end
end
