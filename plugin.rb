# frozen_string_literal: true

# name: discourse-streamers-plugin
# about: Integrate Icecast audio streams with Discourse users (HeartbeatPleasure)
# version: 0.1.0
# authors: Chris
# url: https://github.com/heartbeatpleasure/Discourse-Streamers-Plugin

module ::Streamers
  PLUGIN_NAME = "discourse-streamers-plugin"
end

require_relative "lib/streamers/engine"

after_initialize do
  # Globale routes toevoegen
  Discourse::Application.routes.append do
    # Alias: /streams → Streamers::StreamsController#index
    get "/streams" => "streamers/streams#index"

    # Engine mount voor /streamers/*
    mount ::Streamers::Engine, at: "/streamers"
  end
end
