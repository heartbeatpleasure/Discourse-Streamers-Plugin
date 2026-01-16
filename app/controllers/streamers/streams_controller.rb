# frozen_string_literal: true

module Streamers
  class StreamsController < ::ApplicationController
    before_action :enforce_login_requirement

    def index
      status       = LiveStatus.new
      live_streams = status.live_streams

      respond_to do |format|
        format.json do
          render json: {
            live_streams: live_streams,
            updated_at:   status.updated_at&.iso8601
          }
        end

        format.html do
          # frontend (theme component) pakt deze route en render zelf
          render layout: "application"
        end
      end
    end

    private

    def enforce_login_requirement
      if ::SiteSetting.streamers_streams_page_requires_login && !current_user
        raise Discourse::InvalidAccess.new
      end
    end
  end
end
