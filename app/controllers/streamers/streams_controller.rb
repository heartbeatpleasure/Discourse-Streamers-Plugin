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
            updated_at:   payload[:updated_at],

            # Optional shared chat/discussion topic for the streams page.
            # 0 disables the chat button in the UI.
            chat_topic_id: ::SiteSetting.streamers_chat_topic_id.to_i
          }
        end

        format.html do
          # frontend (theme component) pakt deze route en render zelf
          render layout: "application"
        end
      end
    end

    # NEW: lightweight endpoint for menu indicator
    # Returns only live boolean + count
    def status
      payload = cached_status_payload

      render json: {
        live: payload[:live],
        count: payload[:count],
        updated_at: payload[:updated_at]
      }
    end

    private

    def enforce_login_requirement
      if ::SiteSetting.streamers_streams_page_requires_login && !current_user
        raise Discourse::InvalidAccess.new
      end
    end

    # Cached payload used by /streams.json
    def cached_streams_payload
      ttl = ::SiteSetting.streamers_streams_cache_seconds.to_i
      key = cache_key("streams_payload_v1")

      return compute_streams_payload if ttl <= 0

      ::Rails.cache.fetch(key, expires_in: ttl.seconds) do
        compute_streams_payload
      end
    end

    # Cached payload used by /streams/status.json (smaller TTL by default)
    def cached_status_payload
      ttl = ::SiteSetting.streamers_streams_status_cache_seconds.to_i
      key = cache_key("streams_status_payload_v1")

      return compute_status_payload if ttl <= 0

      ::Rails.cache.fetch(key, expires_in: ttl.seconds) do
        compute_status_payload
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

    def compute_status_payload
      streams_payload = compute_streams_payload
      streams = streams_payload[:live_streams]
      count = streams.is_a?(Array) ? streams.length : 0

      {
        live: count.positive?,
        count: count,
        updated_at: streams_payload[:updated_at]
      }
    end

    def cache_key(suffix)
      db =
        if defined?(::RailsMultisite::ConnectionManagement) &&
             ::RailsMultisite::ConnectionManagement.respond_to?(:current_db)
          ::RailsMultisite::ConnectionManagement.current_db
        else
          "default"
        end

      "streamers:#{suffix}:#{db}"
    end
  end
end
