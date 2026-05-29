# frozen_string_literal: true

module Streamers
  class ListenerBlocking
    BLOCK_SOURCE_CUSTOM_ONLY = "custom_only"
    BLOCK_SOURCE_CUSTOM_AND_IGNORED = "custom_and_ignored"

    def self.blocked?(stream_user_id:, listener_user:)
      block_reason(stream_user_id: stream_user_id, listener_user: listener_user).present?
    end

    def self.block_reason(stream_user_id:, listener_user:)
      sid = stream_user_id.to_i
      user = listener_user
      return nil if sid <= 0 || !user&.id
      return nil if sid == user.id.to_i
      return nil if staff_bypass?(user)

      return "manual" if ::Streamers::ListenerBlock.manual_blocked?(stream_user_id: sid, listener_user_id: user.id)
      return "ignored" if ignored_blocking_enabled? && ignored_by_streamer?(stream_user_id: sid, listener_user_id: user.id)

      nil
    end

    def self.ignored_blocking_enabled?
      block_source == BLOCK_SOURCE_CUSTOM_AND_IGNORED
    end

    def self.block_source
      value = ::SiteSetting.streamers_listener_block_source.to_s.strip.downcase
      return BLOCK_SOURCE_CUSTOM_AND_IGNORED if value == BLOCK_SOURCE_CUSTOM_AND_IGNORED

      BLOCK_SOURCE_CUSTOM_ONLY
    end

    def self.staff_bypass?(user)
      ::SiteSetting.streamers_staff_bypass_listener_blocks && user&.staff?
    end

    def self.ignored_by_streamer?(stream_user_id:, listener_user_id:)
      sid = stream_user_id.to_i
      lid = listener_user_id.to_i
      return false if sid <= 0 || lid <= 0 || sid == lid
      return false unless defined?(::IgnoredUser)

      scope = ::IgnoredUser.where(user_id: sid, ignored_user_id: lid)
      if ::IgnoredUser.respond_to?(:column_names) && ::IgnoredUser.column_names.include?("expiring_at")
        scope = scope.where("expiring_at IS NULL OR expiring_at >= ?", Time.zone.now)
      end

      scope.exists?
    rescue StandardError => e
      ::Rails.logger.warn(
        "[streamers] failed to check ignored listener block " \
        "stream_user_id=#{stream_user_id.inspect} listener_user_id=#{listener_user_id.inspect}: " \
        "#{e.class}: #{e.message}"
      )
      false
    end

    def self.ignored_blocked_user_ids_for(stream_user_id)
      sid = stream_user_id.to_i
      return [] if sid <= 0
      return [] unless ignored_blocking_enabled?
      return [] unless defined?(::IgnoredUser)

      scope = ::IgnoredUser.where(user_id: sid)
      if ::IgnoredUser.respond_to?(:column_names) && ::IgnoredUser.column_names.include?("expiring_at")
        scope = scope.where("expiring_at IS NULL OR expiring_at >= ?", Time.zone.now)
      end

      scope.pluck(:ignored_user_id).map(&:to_i).select(&:positive?).uniq
    rescue StandardError => e
      ::Rails.logger.warn(
        "[streamers] failed to load ignored listener blocks stream_user_id=#{stream_user_id.inspect}: " \
        "#{e.class}: #{e.message}"
      )
      []
    end

    def self.ignored_blocked_count_for(stream_user_id)
      ignored_ids = ignored_blocked_user_ids_for(stream_user_id)
      return 0 if ignored_ids.blank?

      manual_ids = ::Streamers::ListenerBlock.manual_blocked_user_ids_for(stream_user_id)
      (ignored_ids - manual_ids).length
    end
  end
end
