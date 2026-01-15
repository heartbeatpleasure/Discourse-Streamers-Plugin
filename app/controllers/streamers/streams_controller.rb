# frozen_string_literal: true

module Streamers
  class StreamsController < ::ApplicationController
    requires_plugin ::Streamers::PLUGIN_NAME

    before_action :ensure_enabled!
    before_action :ensure_configured!

    def index
      status = Streamers::LiveStatus.current

      render_json_dump(
        live_streams: status[:streams],
        updated_at: status[:updated_at]
      )
    rescue => e
      Rails.logger.error("[streamers] /streams failed: #{e.class}: #{e.message}")
      raise Discourse::NotFound
    end

    private

    def ensure_enabled!
      raise Discourse::NotFound unless SiteSetting.streamers_enabled
    end

    def ensure_configured!
      # Minimaal: een Icecast status URL moet zijn ingesteld
      raise Discourse::NotFound if SiteSetting.streamers_icecast_status_url.blank?
    end
  end
end
