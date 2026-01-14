# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Streamers
  class IcecastClient
    class Error < StandardError; end

    def self.fetch_status
      url = SiteSetting.streamers_icecast_status_url
      return nil if url.blank?

      uri = URI.parse(url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"

      request = Net::HTTP::Get.new(uri.request_uri)

      user = SiteSetting.streamers_icecast_basic_auth_user
      pass = SiteSetting.streamers_icecast_basic_auth_password

      if user.present? && pass.present?
        request.basic_auth(user, pass)
      end

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[streamers] Icecast status request failed: HTTP #{response.code}")
        return nil
      end

      begin
        json = ::JSON.parse(response.body)
      rescue JSON::ParserError => e
        Rails.logger.warn("[streamers] Failed to parse Icecast JSON status: #{e.message}")
        return nil
      end

      json
    rescue StandardError => e
      # Bewust geen secrets loggen. Alleen fouttype en message.
      Rails.logger.warn("[streamers] Icecast status request error: #{e.class} - #{e.message}")
      nil
    end
  end
end
