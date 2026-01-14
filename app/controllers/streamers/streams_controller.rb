# frozen_string_literal: true

module Streamers
  class StreamsController < ::ApplicationController
    requires_plugin ::Streamers::PLUGIN_NAME

    before_action :ensure_can_view_streams

    def index
      payload = Streamers::LiveStatus.current

      respond_to do |format|
        format.json { render json: payload }
        format.html do
          # Voor nu: eenvoudige JSON-dump. Frontend (Ember) kan later een mooie UI maken.
          render json: payload
        end
      end
    end

    private

    def ensure_can_view_streams
      if SiteSetting.streamers_streams_page_requires_login && !current_user
        raise Discourse::NotFound
      end
    end
  end
end
