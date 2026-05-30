# frozen_string_literal: true

class AddTokenFingerprintToStreamersListenerSessions < ActiveRecord::Migration[7.0]
  def change
    unless column_exists?(:streamers_listener_sessions, :token_fingerprint)
      add_column :streamers_listener_sessions, :token_fingerprint, :string
    end

    unless index_exists?(
      :streamers_listener_sessions,
      [:stream_user_id, :token_fingerprint, :ended_at],
      name: "idx_streamers_listener_token_active"
    )
      add_index(
        :streamers_listener_sessions,
        [:stream_user_id, :token_fingerprint, :ended_at],
        name: "idx_streamers_listener_token_active"
      )
    end
  end
end
