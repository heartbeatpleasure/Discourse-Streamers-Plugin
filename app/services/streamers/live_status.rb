# frozen_string_literal: true

module Streamers
  class LiveStatus
    CACHE_KEY = "streamers/live_status"
    CACHE_TTL = 10.seconds

    def self.current
      Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) do
        build_payload
      end
    end

    def self.build_payload
      status = Streamers::IcecastClient.fetch_status
      return { "live_streams" => [], "updated_at" => Time.now.utc } if status.blank?

      icestats = status["icestats"] || {}
      sources = icestats["source"]

      return { "live_streams" => [], "updated_at" => Time.now.utc } if sources.blank?

      sources = [sources] unless sources.is_a?(Array)

      group = resolve_streamers_group
      return { "live_streams" => [], "updated_at" => Time.now.utc } if group.nil?

      live_streams = []

      sources.each do |source|
        mount = extract_mount(source)
        next if mount.blank?

        setting = Streamers::UserSetting.includes(:user).find_by(mount: mount, enabled: true)
        next if setting.nil?

        user = setting.user
        next if user.nil?
        next if force_excluded?(user)
        next unless in_streamers_group?(user, group)

        live_streams << build_stream_hash(user, setting, source)
      end

      {
        "live_streams" => live_streams,
        "updated_at" => Time.now.utc
      }
    end

    def self.extract_mount(source)
      # Probeer eerst een expliciete "mount"-key
      mount = source["mount"] if source.is_a?(Hash)
      return mount if mount.present?

      # Anders parse uit listenurl (bijv. http://stream.heartbeatpleasure.com:8001/u/chris_nl)
      listenurl = source["listenurl"]
      return nil if listenurl.blank?

      begin
        uri = URI.parse(listenurl)
        uri.path
      rescue URI::InvalidURIError
        nil
      end
    end

    def self.build_stream_hash(user, setting, source)
      listeners = source["listeners"].to_i rescue 0
      bitrate = source["bitrate"].to_i rescue nil
      codec = source["server_type"] || source["content_type"]

      {
        "user_id" => user.id,
        "username" => user.username,
        "name" => user.name,
        "avatar_template" => user.avatar_template,
        "mount" => setting.mount,
        "listeners" => listeners,
        "bitrate" => bitrate,
        "codec" => codec,
        "stream_url" => setting.stream_url,
        "chat_url" => chat_url_for(user)
      }
    end

    def self.resolve_streamers_group
      name = SiteSetting.streamers_group_name
      return nil if name.blank?

      Group.find_by(name: name)
    end

    def self.in_streamers_group?(user, group)
      user.group_users.exists?(group_id: group.id)
    end

    def self.force_excluded?(user)
      # user.custom_fields is een hash; we gebruiken een simpele boolean-flag
      user.custom_fields["streamers_force_exclude"].present?
    end

    def self.chat_url_for(_user)
      topic_id = SiteSetting.streamers_chat_topic_id
      return nil if topic_id.to_i <= 0

      # Gebruik Discourse helpers om topic-URL te vormen
      topic = Topic.find_by(id: topic_id)
      return nil if topic.nil?

      "/t/#{topic.slug}/#{topic.id}"
    rescue StandardError
      nil
    end
  end
end
