# frozen_string_literal: true

Streamers::Engine.routes.draw do
  # /streamers/streams
  get "/streams" => "streams#index"

  # /streamers/icecast/auth
  post "/icecast/auth" => "icecast_auth#create"
end
