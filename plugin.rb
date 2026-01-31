# frozen_string_literal: true

# name: Discourse-Streamers-Plugin
# about: Integrate Icecast audio streams with Discourse users (HeartbeatPleasure)
# version: 0.1.0
# authors: Chris
# url: https://github.com/heartbeatpleasure/Discourse-Streamers-Plugin

enabled_site_setting :streamers_enabled

module ::Streamers
  PLUGIN_NAME = "Discourse-Streamers-Plugin"
end

require_relative "lib/streamers/engine"

after_initialize do
  Discourse::Application.routes.append do
    get "/streams" => "streamers/streams#index"
    get "/streams.json" => "streamers/streams#index", defaults: { format: :json }
    get "/streams/status.json" => "streamers/streams#status", defaults: { format: :json }

    get  "/streamers/me"            => "streamers/user_settings#show"
    get  "/streamers/me.json"       => "streamers/user_settings#show", defaults: { format: :json }
    post "/streamers/me/rotate_key" => "streamers/user_settings#rotate_key", defaults: { format: :json }

    # Update the user's selected stream tag (single select)
    post "/streamers/me/stream_tag" => "streamers/user_settings#update_stream_tag", defaults: { format: :json }

    mount ::Streamers::Engine, at: "/streamers"
  end

  def excluded_streamers_usernames
    raw = SiteSetting.streamers_force_exclude_from_streamers
    list = raw.is_a?(Array) ? raw : raw.to_s.split("|")
    list.map { |u| u.to_s.strip.downcase }.reject(&:blank?)
  end

  DiscourseEvent.on(:user_added_to_group) do |user, group|
    next unless SiteSetting.streamers_enabled?

    group_name = SiteSetting.streamers_group_name.presence
    next if group_name.blank?
    next unless group.name == group_name

    # Force-exclude wins always
    if excluded_streamers_usernames.include?(user.username.to_s.downcase)
      if (setting = ::Streamers::UserSetting.find_by(user_id: user.id))
        setting.update!(enabled: false)
      end
      next
    end

    setting = ::Streamers::UserSetting.find_or_initialize_by(user_id: user.id)
    setting.mount ||= "/u/#{user.id}"
    setting.enabled = true
    setting.save!
  end

  DiscourseEvent.on(:user_removed_from_group) do |user, group|
    next unless SiteSetting.streamers_enabled?

    group_name = SiteSetting.streamers_group_name.presence
    next if group_name.blank?
    next unless group.name == group_name

    if (setting = ::Streamers::UserSetting.find_by(user_id: user.id))
      setting.update!(enabled: false)
    end
  end
end
