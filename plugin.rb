# frozen_string_literal: true

# name: Discourse-Streamers-Plugin
# about: Integrate Icecast audio streams with Discourse users (HeartbeatPleasure)
# version: 0.1.0
# authors: Chris
# url: https://github.com/heartbeatpleasure/Discourse-Streamers-Plugin

# Master switch voor de plugin; Discourse koppelt hiermee de site settings
# aan deze plugin en toont o.a. de Settings-knop op de pluginspagina.
enabled_site_setting :streamers_enabled

module ::Streamers
  PLUGIN_NAME = "Discourse-Streamers-Plugin"
end

# Laadt de Rails-engine (controllers, models, routes binnen /streamers, etc.)
require_relative "lib/streamers/engine"

after_initialize do
  #
  # Extra globale routes buiten de engine om
  # (/streams en /streams.json voor de overzichtspagina + API).
  #
  Discourse::Application.routes.append do
    # HTML + JSON endpoint voor de lijst met live streams
    get "/streams" => "streamers/streams#index"

    # Mount de engine onder /streamers (voor o.a. Icecast auth endpoint)
    mount ::Streamers::Engine, at: "/streamers"
  end

  #
  # Eventuele extra Ruby-logica (listeners, helpers, etc.) kan hier later bij.
  # Voor nu houden we het minimalistisch zodat alles stabiel draait.
  #
end
