# frozen_string_literal: true

module ::Streamers
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace Streamers
  end
end
