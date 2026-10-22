# Transport data strategy (0.7)

The executable fallback is a small versioned synthetic timetable, stored on the shared
backend. Search uses departure times, directed stop connections, availability and transfer
buffers; it does not derive train or bus schedules from road-routing results.

`backend/v7.py` adds Oral, Astana and an explicitly fictional metro/tram scenario once.
Existing tickets retain their snapshots. No feed was scraped and no carrier integration is claimed.
Dates start tomorrow at the first migration and are retained; a fresh demonstration uses a
new `--db` path as explained in START_V07.md.

For later real transport data the appropriate interchange format is **GTFS Schedule**:
`stops.txt` supplies stops, `routes.txt` modes, `trips.txt` trips, `stop_times.txt` schedules,
`calendar.txt` / `calendar_dates.txt` service dates and `shapes.txt` optional geometry.
An importer is NOT included in this release. Before importing, verify permissions, timezone,
service dates, station coordinates and accessible transfer attributes. Missing accessibility
must remain unknown and exclude mandatory needs. Do not replace stored bookings when importing.

Official reference: https://gtfs.org/documentation/schedule/reference/
Astana naming reference (LRT): https://www.akorda.kz/ru/glava-gosudarstva-prinyal-uchastie-v-zapuske-lrt-164655

Current maps render straight connections labelled schematic. Real shape geometry, verified
station entrances/addresses and walking access from arbitrary user coordinates are not supplied
by this dataset. All dates/fares/capacity in it are for demonstration only.


0.8 adds a separate read-only OSM city-route reference with a bundled snapshot. It does
not upgrade the demonstration timetable into a live timetable. `urban_osm.py` parses
PTv2 order, entry/exit roles and disconnected way geometry without inventing links.
https://wiki.openstreetmap.org/wiki/Public_transport
https://wiki.openstreetmap.org/wiki/Overpass_API
