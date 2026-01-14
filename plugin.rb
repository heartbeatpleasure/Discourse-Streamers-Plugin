# frozen_string_literal: true

# name: Discourse-Streamers-Plugin
# about: Integrate Icecast audio streams with Discourse users (HeartbeatPleasure)
# version: 0.1.0
# authors: Chris
# url: https://github.com/heartbeatpleasure/Discourse-Streamers-Plugin

module ::Streamers
  # Gebruik dezelfde naam als hierboven, zodat requires_plugin klopt
  PLUGIN_NAME = "Discourse-Streamers-Plugin"
end

require_relative "lib/streamers/engine"

after_initialize do
  #
  # Routes toevoegen
  #
  Discourse::Application.routes.append do
    # Alias: /streams → live streams JSON (en later HTML via frontend)
    get "/streams" => "streamers/streams#index"

    # Mount de engine voor /streamers/*
    mount ::Streamers::Engine, at: "/streamers"
  end

  #
  # BELANGRIJK:
  # Geen directe calls naar SiteSetting.* hier, zodat bootstrap niet faalt
  # als settings nog niet zijn geregistreerd.
  #
end
