# frozen_string_literal: true

module Streamers
  class ListenerBlock < ActiveRecord::Base
    self.table_name = "streamers_listener_blocks"

    belongs_to :stream_user, class_name: "::User"
    belongs_to :blocked_user, class_name: "::User"

    validates :stream_user_id, presence: true
    validates :blocked_user_id, presence: true
    validates :blocked_user_id, uniqueness: { scope: :stream_user_id }
    validate :cannot_block_self

    scope :for_stream_user, ->(user_id) { where(stream_user_id: user_id) }

    def self.manual_blocked?(stream_user_id:, listener_user_id:)
      sid = stream_user_id.to_i
      lid = listener_user_id.to_i
      return false if sid <= 0 || lid <= 0 || sid == lid

      exists?(stream_user_id: sid, blocked_user_id: lid)
    end

    def self.manual_blocked_user_ids_for(stream_user_id)
      sid = stream_user_id.to_i
      return [] if sid <= 0

      for_stream_user(sid).pluck(:blocked_user_id)
    end

    def self.manual_blocked_users_for(stream_user_id)
      ids = manual_blocked_user_ids_for(stream_user_id)
      return [] if ids.blank?

      users = ::User.where(id: ids).to_a.index_by(&:id)
      ids.filter_map do |id|
        user = users[id]
        next unless user

        {
          user_id: user.id,
          username: user.username,
          name: user.name.presence || user.username,
          avatar_template: user.avatar_template
        }
      end
    end

    private

    def cannot_block_self
      return if stream_user_id.blank? || blocked_user_id.blank?
      return unless stream_user_id.to_i == blocked_user_id.to_i

      errors.add(:blocked_user_id, "cannot block yourself")
    end
  end
end
