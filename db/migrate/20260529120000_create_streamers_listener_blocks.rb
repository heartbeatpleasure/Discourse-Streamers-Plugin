# frozen_string_literal: true

class CreateStreamersListenerBlocks < ActiveRecord::Migration[7.0]
  def up
    return if table_exists?(:streamers_listener_blocks)

    create_table :streamers_listener_blocks do |t|
      t.integer :stream_user_id, null: false
      t.integer :blocked_user_id, null: false

      t.timestamps
    end

    add_index :streamers_listener_blocks,
              [:stream_user_id, :blocked_user_id],
              unique: true,
              name: "idx_streamers_listener_blocks_unique"
    add_index :streamers_listener_blocks,
              :blocked_user_id,
              name: "idx_streamers_listener_blocks_blocked_user"
  end

  def down
    drop_table :streamers_listener_blocks if table_exists?(:streamers_listener_blocks)
  end
end
