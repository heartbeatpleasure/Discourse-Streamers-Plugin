# frozen_string_literal: true

module Streamers
  class ListenerToken
    PURPOSE = "streamers-listen-v1"

    def self.generate(user:, mount:)
      verifier.generate(
        "user_id" => user.id,
        "mount" => normalize_mount(mount),
        "expires_at" => ttl_seconds.seconds.from_now.to_i,
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
      @verifier ||=
        if ::Rails.application.respond_to?(:message_verifier)
          ::Rails.application.message_verifier(PURPOSE)
        else
          secret = ::Rails.application.key_generator.generate_key(PURPOSE)
          ActiveSupport::MessageVerifier.new(secret)
        end
    end
    private_class_method :verifier

    def self.normalize_mount(mount)
      s = mount.to_s.strip.split("?", 2).first.to_s
      return "" if s.blank?

      s.start_with?("/") ? s : "/#{s}"
    end
    private_class_method :normalize_mount
  end
end
