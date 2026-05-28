# frozen_string_literal: true

require "json"
require "openssl"
require "securerandom"

module Streamers
  class ListenerToken
    PURPOSE = "streamers-listen-v1"

    def self.generate(user:, mount:)
      raise ArgumentError, "missing user" unless user&.id

      verifier.generate(
        "user_id" => user.id,
        "mount" => normalize_mount(mount),
        "expires_at" => (Time.zone.now + ttl_seconds.seconds).to_i,
        "nonce" => SecureRandom.hex(12)
      )
    end

    def self.verify(token)
      return nil if token.blank?

      payload = verifier.verify(token.to_s)
      return nil unless payload.is_a?(Hash)
      return nil if payload["expires_at"].to_i < Time.zone.now.to_i

      payload
    rescue ActiveSupport::MessageVerifier::InvalidSignature, StandardError
      nil
    end

    def self.ttl_seconds
      ttl = ::SiteSetting.streamers_listener_token_ttl_seconds.to_i
      ttl = 300 if ttl <= 0
      ttl.clamp(30, 3600)
    end

    def self.verifier
      @verifier ||= build_verifier
    end
    private_class_method :verifier

    def self.build_verifier
      secret = verifier_secret

      begin
        ActiveSupport::MessageVerifier.new(secret, digest: "SHA256", serializer: JSON)
      rescue ArgumentError
        # Compatibility fallback for older/newer ActiveSupport signatures.
        ActiveSupport::MessageVerifier.new(secret)
      end
    end
    private_class_method :build_verifier

    def self.verifier_secret
      base_secret =
        if ::Rails.application.respond_to?(:secret_key_base)
          ::Rails.application.secret_key_base
        else
          nil
        end

      base_secret = ::Rails.application.key_generator.generate_key(PURPOSE, 64) if base_secret.blank?
      OpenSSL::HMAC.hexdigest("SHA256", base_secret, PURPOSE)
    end
    private_class_method :verifier_secret

    def self.normalize_mount(mount)
      s = mount.to_s.strip.split("?", 2).first.to_s
      return "" if s.blank?

      s.start_with?("/") ? s : "/#{s}"
    end
    private_class_method :normalize_mount
  end
end
