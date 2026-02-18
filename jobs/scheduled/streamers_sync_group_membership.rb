# frozen_string_literal: true

module ::Jobs
  class StreamersSyncGroupMembership < ::Jobs::Scheduled
    every 1.hour

    def execute(args)
      return unless SiteSetting.streamers_enabled?

      ::Streamers::GroupMembership.sync_all!
    end
  end
end
