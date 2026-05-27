# frozen_string_literal: true

module ::Jobs
  class StreamersCleanupListenerSessions < ::Jobs::Scheduled
    every 10.minutes

    def execute(args)
      return unless SiteSetting.streamers_enabled?

      minutes = SiteSetting.streamers_listener_session_stale_minutes.to_i
      minutes = 720 if minutes <= 0

      ::Streamers::ListenerSession.end_stale!(older_than: minutes.minutes.ago)
    end
  end
end
