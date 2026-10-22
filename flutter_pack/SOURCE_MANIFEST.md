# Data and asset provenance

| Item | Origin / use | Transformations and limits |
|---|---|---|
| Timetables, fares, operators, drivers, vehicles, access attributes | Original synthetic records in backend/journeys.py, created for this student prototype | Seven future demo days at creation; not a real carrier feed; no real people/vehicles implied |
| Stops | Team-requested Aktobe setting and synthetic transfer locations | Coordinates approximate demonstration points; not verified accessible facilities |
| Test accounts | Created temporarily by tests or interactively by team | Fictitious .test emails; no seeded shared passwords |
| OSM map tiles | Existing OpenStreetMap endpoint and attribution in main.dart | External availability and provider terms apply; no tiles bundled; https://www.openstreetmap.org/copyright |
| Address search | Photon public demo / OpenStreetMap-derived results | Approximate nearest result within 50m; no building containment guarantee; https://github.com/komoot/photon |
| Road routing | Existing openrouteservice/HeiGIT client | Separate optional key; no current traffic/dispatch; https://openrouteservice.org/ |
| Legacy Overpass module | Existing source retained for compatibility | New booking searches use the bundled synthetic dataset; no dependence on live Overpass coverage |
| Icons/avatars | Flutter Material icons and OS-rendered emoji | No downloaded portraits, celebrity likenesses or external image files |
| Website styling/text | Original HTML/CSS written for this prototype | No claimed app-store release or published installers |
| Dependencies | Flutter, flutter_map, latlong2, url_launcher, http, path, path_provider, cryptography, sqlite3 | Declared in pubspec.example.yaml; retain upstream licence notices in distributed builds; lock actual resolved versions in your project |

No external GTFS, carrier contracts or passenger research data were imported.
Retain this manifest when adding licensed datasets/images; record source, permission,
transformation and limitations for each new item.


0.7: Oral/Astana terminal coordinates, timetable and metro/tram demo are team-created
synthetic fixtures, not official carrier data or verified station entrances. Straight
map connections are labelled schematic. GTFS documentation was consulted for future
data architecture only; no GTFS dataset/importer is shipped. See TRANSPORT_DATA.md.


0.8: backend/data/aktobe_osm.json contains real OSM-derived data (ODbL 1.0), separate
from synthetic booking stops. See backend/data/OSM_LICENSE.md for source relations and
transformations. Retrieved geometry/stop counts: relation 7836092 (21 stops), 8477889
(18 stops), 19859667 (7 stops). This is partial, not verified current carrier operation.
