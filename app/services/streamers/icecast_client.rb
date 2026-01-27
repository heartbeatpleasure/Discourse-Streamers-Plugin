# frozen_string_literal: true

module Streamers
  class IcecastClient
    require "net/http"
    require "uri"
    require "json"

    # Haal en normaliseer alle Icecast sources
    # Retourneert een array van hashes, elk met minimaal key "mount"
    def self.fetch_sources
      status_url        = ::SiteSetting.streamers_icecast_status_url
      basic_auth_user   = ::SiteSetting.streamers_icecast_basic_auth_user
      basic_auth_pass   = ::SiteSetting.streamers_icecast_basic_auth_password

      new(status_url, basic_auth_user, basic_auth_pass).fetch_sources
    end

    def initialize(status_url, basic_auth_user, basic_auth_password)
      @status_url        = status_url
      @basic_auth_user   = basic_auth_user
      @basic_auth_pass   = basic_auth_password
    end

    def fetch_sources
      return [] if @status_url.blank?

      uri  = URI.parse(@status_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 5

      request = Net::HTTP::Get.new(uri.request_uri)

      if @basic_auth_user.present? && @basic_auth_pass.present?
        request.basic_auth(@basic_auth_user, @basic_auth_pass)
      end

      response = http.request(request)
      unless response.is_a?(Net::HTTPSuccess)
        ::Rails.logger.warn("[streamers] Icecast status HTTP #{response.code}")
        return []
      end

      json     = JSON.parse(response.body)
      icestats = json["icestats"] || {}
      raw      = icestats["source"]

      # Icecast geeft bij 1 stream een object, bij meerdere een array
      sources =
        case raw
        when Array
          raw
        when Hash
          [raw]
        else
          []
        end

      sources.map do |src|
        listenurl = src["listenurl"].to_s

        mount = begin
          URI.parse(listenurl).path
        rescue URI::InvalidURIError
          nil
        end

        src.merge("mount" => mount)
      end
    rescue StandardError => e
      ::Rails.logger.warn("[streamers] IcecastClient error: #{e.class}: #{e.message}")
      []
    end
  end
end
