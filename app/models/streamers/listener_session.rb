# frozen_string_literal: true

require "digest"

module Streamers
  class ListenerSession < ActiveRecord::Base
    self.table_name = "streamers_listener_sessions"

    belongs_to :user, class_name: "::User", optional: true
    belongs_to :stream_user, class_name: "::User", optional: true

    scope :active, -> { where(ended_at: nil) }

    def self.record_add!(stream_user_id:, mount:, client_id:, user: nil, request: nil)
      now = Time.zone.now
      normalized_mount = normalize_mount(mount)
      normalized_client_id = client_id.to_s.presence || "missing-#{SecureRandom.hex(12)}"

      session = active.where(mount: normalized_mount, client_id: normalized_client_id).order(started_at: :desc).first
      session ||= new(mount: normalized_mount, client_id: normalized_client_id, started_at: now)

      session.stream_user_id = stream_user_id
      session.user_id = user&.id
      session.last_seen_at = now
      session.user_agent_hash = digest_value(request&.user_agent)
      session.ip_hash = digest_value(request&.remote_ip)
      session.save!
      session
    end

    def self.record_remove!(mount:, client_id:, duration: nil)
      normalized_mount = normalize_mount(mount)
      normalized_client_id = client_id.to_s
      return nil if normalized_mount.blank? || normalized_client_id.blank?

      session = active.where(mount: normalized_mount, client_id: normalized_client_id).order(started_at: :desc).first
      return nil unless session

      session.update!(ended_at: Time.zone.now, duration: duration.to_i.positive? ? duration.to_i : session.duration)
      session
    end

    def self.end_stale!(older_than:)
      active.where("started_at < ?", older_than).update_all(ended_at: Time.zone.now, updated_at: Time.zone.now)
    end

    def self.summary_by_stream_user_ids(stream_user_ids)
      ids = Array(stream_user_ids).map(&:to_i).select(&:positive?).uniq
      return {} if ids.blank?

      grouped = Hash.new { |h, k| h[k] = { known_session_count: 0, listeners: {} } }

      active.where(stream_user_id: ids).includes(:user).find_each do |session|
        summary = grouped[session.stream_user_id]
        next unless session.user
        next if ::Streamers::ListenerBlocking.blocked?(
          stream_user_id: session.stream_user_id,
          listener_user: session.user
        )

        summary[:known_session_count] += 1
        listener = summary[:listeners][session.user_id] ||= {
          user_id: session.user.id,
          username: session.user.username,
          name: session.user.name.presence || session.user.username,
          avatar_template: session.user.avatar_template,
          session_count: 0,
          started_at: session.started_at
        }

        listener[:session_count] += 1
        listener[:started_at] = [listener[:started_at], session.started_at].compact.min
      end

      grouped.transform_values do |summary|
        listeners = summary[:listeners].values.sort_by do |listener|
          [listener[:name].to_s.downcase, listener[:username].to_s.downcase]
        end

        {
          known_session_count: summary[:known_session_count],
          listeners: listeners.map do |listener|
            listener.merge(
              has_multiple_sessions: listener[:session_count].to_i > 1,
              started_at: listener[:started_at]&.iso8601
            )
          end
        }
      end
    end

    def self.normalize_mount(mount)
      s = mount.to_s.strip.split("?", 2).first.to_s
      return "" if s.blank?

      s.start_with?("/") ? s : "/#{s}"
    end

    def self.digest_value(value)
      v = value.to_s
      return nil if v.blank?

      secret = if ::Rails.application.respond_to?(:secret_key_base)
        ::Rails.application.secret_key_base
      else
        ::Rails.application.key_generator.generate_key("streamers-listener-session")
      end

      Digest::SHA256.hexdigest("#{secret}:#{v}")
    rescue StandardError
      nil
    end
  end
end
