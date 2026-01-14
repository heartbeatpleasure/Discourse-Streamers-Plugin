# frozen_string_literal: true

module Streamers
  class UserSetting < ::ActiveRecord::Base
    self.table_name = "streamers_user_settings"

    belongs_to :user

    validates :user_id, presence: true, uniqueness: true
    validates :mount, presence: true, uniqueness: true
    validates :stream_key, presence: true, uniqueness: true
    validates :enabled, inclusion: { in: [true, false] }

    before_validation :ensure_defaults

    def ensure_defaults
      self.enabled = true if enabled.nil?

      if user && mount.blank?
        self.mount = "/u/#{user.username_lower}"
      end

      self.stream_key ||= SecureRandom.hex(32) # 64 chars
    end

    def stream_url
      "https://stream.heartbeatpleasure.com/radio#{mount}"
    end
  end
end
