# frozen_string_literal: true

Streamers::Engine.routes.draw do
  # /streamers/streams
  get "/streams" => "streams#index"

  # /streamers/listen
  get "/listen" => "streams#listen"

  # /streamers/icecast/auth
  post "/icecast/auth" => "icecast_auth#create"
  post "/icecast/listener_add" => "icecast_auth#listener_add"
  post "/icecast/listener_remove" => "icecast_auth#listener_remove"
end
