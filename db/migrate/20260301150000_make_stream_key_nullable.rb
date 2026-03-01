# frozen_string_literal: true

class MakeStreamKeyNullable < ActiveRecord::Migration[7.0]
  def up
    change_column_null :streamers_user_settings, :stream_key, true
  end

  def down
    # Als je ooit terug wilt naar NOT NULL: eerst NULLs vullen.
    execute <<~SQL
      UPDATE streamers_user_settings
      SET stream_key = md5(random()::text || clock_timestamp()::text || id::text)
      WHERE stream_key IS NULL;
    SQL

    change_column_null :streamers_user_settings, :stream_key, false
  end
end