// Photon does not require an API key on its public demo endpoint.
const photonBaseUrl = 'https://photon.komoot.io';
// Set later through Settings (kept in memory), or with --dart-define.
// Never commit your real key to GitHub.
const routingApiKey = String.fromEnvironment('ORS_API_KEY', defaultValue: '');
const routingBaseUrl = 'https://api.heigit.org/openrouteservice/v2';
const overpassUrl = 'https://overpass-api.de/api/interpreter';
