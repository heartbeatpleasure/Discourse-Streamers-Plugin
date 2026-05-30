# frozen_string_literal: true

require "base64"
require "json"
require "openssl"
require "securerandom"

module Streamers
  class ListenerToken
    PURPOSE = "streamers-listen-v1"

    def self.generate(user:, mount:)
      raise ArgumentError, "missing user" unless user&.id

      payload = {
        "user_id" => user.id,
        "mount" => normalize_mount(mount),
        "expires_at" => (Time.zone.now + ttl_seconds.seconds).to_i,
        "nonce" => SecureRandom.hex(12)
      }

      data = Base64.urlsafe_encode64(payload.to_json, padding: false)
      signature = sign(data)
      "#{data}.#{signature}"
    end

    def self.verify(token)
      data, supplied_signature = token.to_s.split(".", 2)
      return nil if data.blank? || supplied_signature.blank?

      expected_signature = sign(data)
      return nil unless secure_compare(expected_signature, supplied_signature)

      payload = JSON.parse(Base64.urlsafe_decode64(pad_base64(data)))
      return nil unless payload.is_a?(Hash)
      return nil if payload["expires_at"].to_i < Time.zone.now.to_i

      payload
    rescue JSON::ParserError, ArgumentError, StandardError
      nil
    end

    def self.fingerprint(token)
      value = token.to_s
      return nil if value.blank?

      OpenSSL::HMAC.hexdigest("SHA256", signing_secret, "fingerprint:#{value}")
    rescue StandardError
      nil
    end

    def self.ttl_seconds
      ttl = ::SiteSetting.streamers_listener_token_ttl_seconds.to_i
      ttl = 300 if ttl <= 0
      ttl.clamp(30, 3600)
    end

    def self.sign(data)
      OpenSSL::HMAC.hexdigest("SHA256", signing_secret, data.to_s)
    end
    private_class_method :sign

    def self.signing_secret
      secret = ::SiteSetting.streamers_icecast_listener_auth_secret.to_s
      return secret if secret.present?

      ::Rails.application.key_generator.generate_key(PURPOSE, 64)
    rescue StandardError
      # Last-resort deterministic fallback for very early boot/test contexts.
      # In production the listener auth secret should be configured.
      "#{PURPOSE}:#{Rails.root}"
    end
    private_class_method :signing_secret

    def self.secure_compare(expected, supplied)
      return false if expected.blank? || supplied.blank?
      return false unless expected.bytesize == supplied.bytesize

      ActiveSupport::SecurityUtils.secure_compare(expected, supplied)
    end
    private_class_method :secure_compare

    def self.pad_base64(value)
      s = value.to_s
      padding = (4 - (s.length % 4)) % 4
      "#{s}#{"=" * padding}"
    end
    private_class_method :pad_base64

    def self.normalize_mount(mount)
      s = mount.to_s.strip.split("?", 2).first.to_s
      return "" if s.blank?

      s.start_with?("/") ? s : "/#{s}"
    end
    private_class_method :normalize_mount
  end
end
