# frozen_string_literal: true

class AddStreamKeyToStreamersUserSettings < ActiveRecord::Migration[7.0]
  def up
    # Voeg digest-kolom toe als hij nog niet bestaat
    unless column_exists?(:streamers_user_settings, :stream_key_digest)
      add_column :streamers_user_settings, :stream_key_digest, :string
    end

    # Voeg last_stream_started_at toe ALS hij nog niet bestaat
    unless column_exists?(:streamers_user_settings, :last_stream_started_at)
      add_column :streamers_user_settings, :last_stream_started_at, :datetime
    end
  end

  def down
    # Alleen de kolom die we 100% zeker via deze migratie toevoegen weer weghalen.
    if column_exists?(:streamers_user_settings, :stream_key_digest)
      remove_column :streamers_user_settings, :stream_key_digest
    end

    # last_stream_started_at laten we met rust, omdat die bij jou al bestond
  end
end