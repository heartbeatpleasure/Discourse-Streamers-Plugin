# frozen_string_literal: true

# name: discourse-streamers-plugin
# about: Integrate Icecast audio streams with Discourse users (HeartbeatPleasure)
# version: 0.1.0
# authors: Chris

enabled_site_setting :streamers_icecast_status_url

module ::Streamers
  PLUGIN_NAME = "discourse-streamers-plugin"
end

require_relative "lib/streamers/engine"

after_initialize do
  # Mount de plugin-routes
  Discourse::Application.routes.append do
    # Top-level alias voor de streams JSON/HTML endpoint
    get "/streams" => "streamers/streams#index"

    # Icecast URL-auth endpoint en /streamers/* routes via engine
    mount ::Streamers::Engine, at: "/streamers"
  end

  # Controleer of de groep bestaat (alleen een waarschuwing loggen)
  if SiteSetting.streamers_group_name.present?
    group = Group.find_by(name: SiteSetting.streamers_group_name)
    if group.nil?
      Rails.logger.warn(
        "[streamers] No group found with name '#{SiteSetting.streamers_group_name}'. " \
        "Streaming features will be effectively disabled until this is corrected."
      )
    end
  end
end
