# frozen_string_literal: true

module Streamers
  class StreamsController < ::ApplicationController
    before_action :enforce_login_requirement

    def index
      payload = cached_streams_payload

      respond_to do |format|
        format.json do
          render json: {
            live_streams: payload[:live_streams],
            updated_at:   payload[:updated_at]
          }
        end

        format.html do
          # frontend (theme component) pakt deze route en render zelf
          render layout: "application"
        end
      end
    end

    # Lightweight endpoint for UI indicators (e.g. menu badge)
    # Returns only whether anyone is live and how many streams are live.
    def status
      payload = cached_streams_payload
      streams = payload[:live_streams]
      count = streams.is_a?(Array) ? streams.length : 0

      render json: {
        live: count.positive?,
        count: count,
        updated_at: payload[:updated_at]
      }
    end

    private

    def enforce_login_requirement
      if ::SiteSetting.streamers_streams_page_requires_login && !current_user
        raise Discourse::InvalidAccess.new
      end
    end

    def cached_streams_payload
      ttl = ::SiteSetting.streamers_live_status_cache_seconds.to_i

      return compute_streams_payload if ttl <= 0

      ::Rails.cache.fetch(cache_key, expires_in: ttl.seconds) do
        compute_streams_payload
      end
    end

    def compute_streams_payload
      status       = LiveStatus.new
      live_streams = status.live_streams

      {
        live_streams: live_streams,
        updated_at: status.updated_at&.iso8601
      }
    end

    # Cache key is site-specific (multi-site safe) and versioned.
    # We intentionally keep it stable and rely on short TTL for freshness.
    def cache_key
      db = if defined?(::RailsMultisite::ConnectionManagement) &&
              ::RailsMultisite::ConnectionManagement.respond_to?(:current_db)
             ::RailsMultisite::ConnectionManagement.current_db
           else
             "default"
           end

      "streamers:streams_payload:v1:#{db}"
    end
  end
end
