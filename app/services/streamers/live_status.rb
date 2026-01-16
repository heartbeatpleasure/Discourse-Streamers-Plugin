# frozen_string_literal: true

module Streamers
  class LiveStatus
    attr_reader :updated_at

    def initialize
      @updated_at = nil
    end

    # Retourneert:
    # - array van stream-hashes als er streams zijn
    # - nil als er geen geldige streams zijn
    def live_streams
      sources = IcecastClient.fetch_sources
      return nil if sources.blank?

      settings = UserSetting.includes(:user).where(enabled: true)
      return nil if settings.blank?

      # Map mount => user_setting
      settings_by_mount = {}
      settings.each do |setting|
        settings_by_mount[setting.mount] = setting
      end

      streams = sources.filter_map do |src|
        mount = src["mount"]
        next if mount.blank?

        setting = settings_by_mount[mount]
        next unless setting

        user = setting.user
        next unless user

        {
          user_id:          user.id,
          username:         user.username,
          name:             (user.name.presence || user.username),
          avatar_template:  user.avatar_template,
          mount:            mount,
          listeners:        src["listeners"].to_i,
          bitrate:          src["bitrate"].to_i,
          title:            (src["title"].presence || src["server_name"]),
          stream_started_at: src["stream_start_iso8601"] || src["stream_start"]
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
  end
end
