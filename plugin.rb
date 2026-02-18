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
require_relative "lib/streamers/group_membership"

after_initialize do
  # Ensure our scheduled job constant is loaded (needed when saving site settings).
  load File.expand_path("jobs/scheduled/streamers_sync_group_membership.rb", __dir__)

  Discourse::Application.routes.append do
    get "/streams" => "streamers/streams#index"
    get "/streams.json" => "streamers/streams#index", defaults: { format: :json }

    # NEW: lightweight status endpoint for menu indicator
    get "/streams/status.json" => "streamers/streams#status", defaults: { format: :json }

    get  "/streamers/me"            => "streamers/user_settings#show"
    get  "/streamers/me.json"       => "streamers/user_settings#show", defaults: { format: :json }
    post "/streamers/me/rotate_key" => "streamers/user_settings#rotate_key", defaults: { format: :json }

    # Update the user's selected stream tag (single select)
    post "/streamers/me/stream_tag" => "streamers/user_settings#update_stream_tag", defaults: { format: :json }

    mount ::Streamers::Engine, at: "/streamers"
  end

  # Keep Streamers::UserSetting in sync with group membership.
  # Group membership itself is optionally auto-managed in Streamers::GroupMembership.

  DiscourseEvent.on(:user_added_to_group) do |user, group|
    next unless SiteSetting.streamers_enabled?
    next unless ::Streamers::GroupMembership.streamers_group_match?(group)

    # Force-exclude wins always
    if ::Streamers::GroupMembership.excluded_usernames.include?(user.username.to_s.downcase)
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
    next unless ::Streamers::GroupMembership.streamers_group_match?(group)

    if (setting = ::Streamers::UserSetting.find_by(user_id: user.id))
      setting.update!(enabled: false)
    end
  end

  # --- Automatic group management (Step 1) ---

  DiscourseEvent.on(:user_promoted) do |user, *_|
    ::Streamers::GroupMembership.ensure_membership_safely(user)
  end

  # Some Discourse versions use a different event name for trust-level changes.
  DiscourseEvent.on(:user_trust_level_changed) do |user, *_|
    ::Streamers::GroupMembership.ensure_membership_safely(user)
  end

  # When settings change, enqueue a sync to cover existing users.
  DiscourseEvent.on(:site_setting_changed) do |name, *_|
    next unless SiteSetting.streamers_enabled?
    next unless ::Streamers::GroupMembership.settings_affect_group_membership?(name)

    Jobs.enqueue(:streamers_sync_group_membership)
  end
end
