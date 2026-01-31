# frozen_string_literal: true

class AddStreamTagToStreamersUserSettings < ActiveRecord::Migration[7.0]
  def up
    # Optional label/category users can select for their live stream (e.g. ASMR)
    unless column_exists?(:streamers_user_settings, :stream_tag)
      add_column :streamers_user_settings, :stream_tag, :string
    end
  end

  def down
    if column_exists?(:streamers_user_settings, :stream_tag)
      remove_column :streamers_user_settings, :stream_tag
    end
  end
end
