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

      setting = ensure_user_setting_exists_and_enabled!(current_user)

      render_json_dump(
        allowed: true,
        user_id: current_user.id,
        username: current_user.username,
        name: current_user.name,
        mount: setting.public_mount,
        enabled: setting.enabled,
        has_stream_key: setting.stream_key_digest.present?,
        public_listen_url: setting.public_listen_url,
        last_stream_started_at: setting.last_stream_started_at,
        stream_tag: setting.try(:stream_tag),
        stream_tag_options: stream_tag_options
      )
    end

    def rotate_key
      raise Discourse::InvalidAccess unless allowed_to_stream?(current_user)

      setting = ensure_user_setting_exists_and_enabled!(current_user)

      raw_key = setting.rotate_stream_key! # => SecureRandom.hex(32) vanuit model
      render_json_dump(stream_key: raw_key)
    end

    # POST /streamers/me/stream_tag
    # Params:
    #   stream_tag: "ASMR" (or "" / nil to clear)
    #
    # Stores the selected tag (single select) on the user's Streamers::UserSetting.
    def update_stream_tag
      raise Discourse::InvalidAccess unless allowed_to_stream?(current_user)

      requested = params[:stream_tag].to_s.strip
      requested = "" if requested.blank?

      if requested.present?
        canonical = canonical_stream_tag(requested)
        if canonical.blank?
          render json: { errors: ["invalid_stream_tag"] }, status: 422
          return
        end
        requested = canonical
      end

      # Prevent accidentally storing unbounded strings (also protects UI pill rendering)
      if requested.present? && requested.length > 64
        render json: { errors: ["stream_tag_too_long"] }, status: 422
        return
      end

      setting = ensure_user_setting_exists_and_enabled!(current_user)
      unless setting.respond_to?(:stream_tag=)
        render json: { errors: ["stream_tag_not_supported"] }, status: 501
        return
      end

      setting.update!(stream_tag: requested.presence)

      render_json_dump(stream_tag: setting.stream_tag)
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

    def ensure_user_setting_exists_and_enabled!(user)
      setting = Streamers::UserSetting.find_or_initialize_by(user_id: user.id)

      if setting.new_record?
        setting.mount = "/u/#{user.id}"
        setting.enabled = true
        setting.stream_key = SecureRandom.hex(16) # legacy kolom, non-null
        setting.save!
      elsif !setting.enabled?
        setting.update!(enabled: true)
      end

      setting
    end

    def stream_tag_options
      raw = SiteSetting.streamers_stream_tag_options
      list = raw.is_a?(Array) ? raw : raw.to_s.split("|")
      list.map { |t| t.to_s.strip }.reject(&:blank?)
    end

    # Returns the canonical tag label from the configured options.
    # Matching is case-insensitive, so sending "asmr" will map to "ASMR".
    def canonical_stream_tag(input)
      normalized = input.to_s.strip
      return "" if normalized.blank?

      options = stream_tag_options
      return "" if options.blank?

      lookup = options.index_by { |t| t.downcase }
      lookup[normalized.downcase].to_s
    end
  end
end
