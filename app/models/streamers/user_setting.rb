# frozen_string_literal: true

module Streamers
  class UserSetting < ActiveRecord::Base
    self.table_name = "streamers_user_settings"

    STREAM_KEY_BYTES = 32

    belongs_to :user

    # Handige scope als we ergens snel alle actieve streamers willen ophalen
    scope :enabled, -> { where(enabled: true) }

    # Berekent de standaard mount voor een gebruiker, bijv. /u/3
    def self.default_mount_for(user)
      "/u/#{user.id}"
    end

    # Bool helper
    def enabled?
      enabled
    end

    # Zorgt dat er een key is, maar geeft hem niet terug
    def ensure_stream_key!
      return if stream_key_digest.present?

      rotate_stream_key!
    end

    # Genereert een nieuwe stream key, slaat alleen de hash op
    # en geeft de raw key terug (om éénmalig aan de user te tonen).
    def rotate_stream_key!
      raw_key = generate_random_key

      self.stream_key_digest = digest(raw_key)
      save!

      raw_key
    end

    # Verwijder de key (bijvoorbeeld als iemand stopt met streamen)
    def clear_stream_key!
      update!(stream_key_digest: nil)
    end

    def has_stream_key?
      stream_key_digest.present?
    end

    # Controleer een plaintext key tegen de opgeslagen hash
    def valid_stream_key?(raw_key)
      return false if raw_key.blank? || stream_key_digest.blank?

      ActiveSupport::SecurityUtils.secure_compare(digest(raw_key), stream_key_digest)
    end

    # Wordt aangeroepen als een stream succesvol start (via Icecast auth)
    def mark_stream_started!
      update!(last_stream_started_at: Time.zone.now)
    end

    # De mount die we verwachten voor deze user.
    # Nu nog: gebruik de bestaande mount als die gezet is,
    # anders val terug op een simpel patroon /u/:id
    def public_mount
      mount.presence || "/u/#{user_id}"
    end

    # Publieke luister-URL voor deze user.
    # We leiden dit af van de status-URL, bijvoorbeeld:
    #   https://stream.heartbeatpleasure.com/radio/status-json.xsl
    # -> https://stream.heartbeatpleasure.com/radio + public_mount
    def public_listen_url
      status_url = SiteSetting.streamers_icecast_status_url.to_s
      return "" if status_url.blank?

      base = status_url.sub(%r{/[^/]+$}, "")
      "#{base}#{public_mount}"
    end

    private

    def generate_random_key
      # 32 bytes hex = 64 tekens, ruim voldoende
      SecureRandom.hex(STREAM_KEY_BYTES)
    end

    def digest(raw_key)
      Digest::SHA256.hexdigest(raw_key)
    end
  end
end
