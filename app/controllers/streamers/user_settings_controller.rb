# frozen_string_literal: true
require "securerandom"

module ::Streamers
  class UserSettingsController < ::ApplicationController
    requires_plugin ::Streamers::PLUGIN_NAME
    before_action :ensure_logged_in

    def show
      unless allowed_to_stream?(current_user)
        render_json_dump(
          allowed: false,
          user_id: current_user.id,
          username: current_user.username
        )
        return
      end

      setting = Streamers::UserSetting.find_or_initialize_by(user_id: current_user.id)

      if setting.new_record?
        setting.mount = "/u/#{current_user.id}"
        setting.enabled = true
        setting.stream_key = SecureRandom.hex(16) # legacy kolom, non-null
        setting.save!
      elsif !setting.enabled?
        setting.update!(enabled: true)
      end

      render_json_dump(
        allowed: true,
        user_id: current_user.id,
        username: current_user.username,
        name: current_user.name,
        mount: setting.public_mount,
        enabled: setting.enabled,
        has_stream_key: setting.stream_key_digest.present?,
        public_listen_url: setting.public_listen_url,
        last_stream_started_at: setting.last_stream_started_at
      )
    end

    def rotate_key
      raise Discourse::InvalidAccess unless allowed_to_stream?(current_user)

      setting = Streamers::UserSetting.find_or_initialize_by(user_id: current_user.id)

      if setting.new_record?
        setting.mount = "/u/#{current_user.id}"
        setting.enabled = true
        setting.stream_key = SecureRandom.hex(16) # legacy kolom, non-null
        setting.save!
      elsif !setting.enabled?
        setting.update!(enabled: true)
      end

      raw_key = setting.rotate_stream_key! # => SecureRandom.hex(32) vanuit model
      render_json_dump(stream_key: raw_key)
    end

    private

    def allowed_to_stream?(user)
      return false unless SiteSetting.streamers_enabled?
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
  end
end
