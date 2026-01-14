# frozen_string_literal: true

module ::Streamers
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace Streamers
  end
end

Streamers::Engine.routes.draw do
  # JSON/HTML endpoint voor live streams (via /streamers/streams en /streams alias)
  get "/streams" => "streams#index"

  # Icecast URL-auth endpoint: Icecast POST hiernaar bij een nieuwe source-verbinding
  post "/icecast/auth" => "icecast_auth#create"
end
