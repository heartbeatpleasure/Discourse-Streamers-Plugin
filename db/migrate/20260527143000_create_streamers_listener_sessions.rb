# frozen_string_literal: true

class CreateStreamersListenerSessions < ActiveRecord::Migration[7.0]
  def change
    create_table :streamers_listener_sessions do |t|
      t.integer :user_id
      t.integer :stream_user_id, null: false
      t.string :mount, null: false
      t.string :client_id, null: false
      t.datetime :started_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :ended_at
      t.integer :duration
      t.string :user_agent_hash
      t.string :ip_hash
      t.timestamps
    end

    add_index :streamers_listener_sessions, :user_id, name: "idx_streamers_listener_user"
    add_index :streamers_listener_sessions, [:stream_user_id, :ended_at], name: "idx_streamers_listener_stream_active"
    add_index :streamers_listener_sessions, [:mount, :client_id, :ended_at], name: "idx_streamers_listener_client_active"
  end
end
