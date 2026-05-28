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
      stream_user_ids = []
      settings.each do |setting|
        next unless setting.user
        next if excluded.include?(setting.user.username.to_s.downcase)
        settings_by_mount[normalize_mount(setting.mount)] = setting
        stream_user_ids << setting.user_id
      end

      listener_summaries = ::Streamers::ListenerSession.summary_by_stream_user_ids(stream_user_ids)

      streams = sources.filter_map do |src|
        mount = normalize_mount(src["mount"].to_s)
        next if mount.blank?

        setting = settings_by_mount[mount]
        next unless setting&.user

        user = setting.user

        raw_title = src["title"].presence || src["server_name"]
        safe_title = sanitize_text(raw_title)

        safe_tag = sanitize_text(setting.try(:stream_tag))
        safe_tag = "" if safe_tag.length > 64

        # Per-tag chat channel mapping with global fallback.
        # Note: despite the setting name (historical), this is a Discourse Chat *channel* id.
        stream_chat_topic_id = chat_topic_id_for_tag(safe_tag.presence)

        listener_total = src["listeners"].to_i
        listener_summary = listener_summaries[user.id] || { known_session_count: 0, listeners: [] }
        known_listener_count = listener_summary[:known_session_count].to_i
        known_listeners = listener_total.positive? ? listener_summary[:listeners] : []
        public_listener_count = [listener_total - known_listener_count, 0].max

        {
          user_id: user.id,
          username: user.username,
          name: (user.name.presence || user.username),
          avatar_template: user.avatar_template,
          mount: mount,
          listen_url: safe_authenticated_listen_url(setting),
          listeners: listener_total,
          known_listener_count: known_listener_count,
          public_listener_count: public_listener_count,
          known_listeners: known_listeners,
          bitrate: src["bitrate"].to_i,
          title: safe_title,
          stream_tag: (safe_tag.presence),
          chat_topic_id: stream_chat_topic_id,
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

    def normalize_mount(mount)
      s = mount.to_s.strip.split("?", 2).first.to_s
      return "" if s.blank?

      s.start_with?("/") ? s : "/#{s}"
    end

    # Returns a chat channel id for a given tag (case-insensitive).
    # Falls back to SiteSetting.streamers_chat_topic_id when no match is found.
    def chat_topic_id_for_tag(tag)
      fallback = ::SiteSetting.streamers_chat_topic_id.to_i
      return fallback if tag.blank?

      mapped = tag_chat_topic_map[tag.to_s.strip.downcase]
      mapped_id = mapped.to_i
      mapped_id.positive? ? mapped_id : fallback
    end

    # Parses SiteSetting.streamers_stream_tag_chat_topic_map into a hash:
    #   { "asmr" => 33, "heartbeats" => 44 }
    # Accepted formats per entry:
    #   "ASMR:33" or "ASMR=33"
    def tag_chat_topic_map
      @tag_chat_topic_map ||= begin
        raw = ::SiteSetting.streamers_stream_tag_chat_topic_map
        list = raw.is_a?(Array) ? raw : raw.to_s.split("|")

        map = {}
        list.each do |entry|
          e = entry.to_s.strip
          next if e.blank?

          # Split on first ':' or '='
          parts = e.split(/[:=]/, 2)
          next if parts.length != 2

          tag = parts[0].to_s.strip
          id_str = parts[1].to_s.strip
          next if tag.blank? || id_str.blank?

          id = id_str.to_i
          next unless id.positive?

          map[tag.downcase] = id
        end

        map
      end
    end

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

    # Bouwt de login-protected luister-URL op. Dit is bewust geen user-specifieke token,
    # zodat /streams.json veilig gecachet kan blijven.
    def safe_authenticated_listen_url(setting)
      path = setting.authenticated_listen_path.to_s
      return "" if path.blank?
      return "" unless path.start_with?("/streamers/listen?") || path.start_with?("/streamers/listen.mp3?")

      path
    rescue StandardError
      ""
    end
  end
end
