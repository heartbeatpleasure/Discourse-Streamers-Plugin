# frozen_string_literal: true

Streamers::Engine.routes.draw do
  # /streamers/streams
  get "/streams" => "streams#index"

  # /streamers/icecast/auth
  post "/icecast/auth" => "icecast_auth#create"
  post "/icecast/listener_add" => "icecast_auth#listener_add"
  post "/icecast/listener_remove" => "icecast_auth#listener_remove"

  # /streamers/me/listener_blocks
  get "/me/listener_block_candidates" => "user_settings#listener_block_candidates"
  post "/me/listener_blocks" => "user_settings#add_listener_block"
  delete "/me/listener_blocks/:user_id" => "user_settings#remove_listener_block"
end
