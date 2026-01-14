# frozen_string_literal: true

class CreateStreamersUserSettings < ActiveRecord::Migration[6.1]
  def change
    create_table :streamers_user_settings do |t|
      t.integer :user_id, null: false
      t.string :mount, null: false
      t.string :stream_key, null: false
      t.boolean :enabled, null: false, default: true
      t.datetime :last_stream_started_at
      t.datetime :last_seen_live_at

      t.timestamps
    end

    add_index :streamers_user_settings, :user_id, unique: true
    add_index :streamers_user_settings, :mount, unique: true
    add_index :streamers_user_settings, :stream_key, unique: true
  end
end
