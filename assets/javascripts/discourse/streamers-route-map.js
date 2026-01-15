// assets/javascripts/discourse/streamers-route-map.js

/**
 * Route map for the Streamers plugin.
 *
 * Dit registreert de pagina /streams in de Ember router.
 * De daadwerkelijke route-logica en template leveren we vanuit
 * de theme component (routes/streams.js + templates/streams.hbs).
 */
export default function streamers() {
  // URL: /streams
  // Route name: "streams"
  this.route("streams", { path: "/streams" });
}
