# OpenStreetMap-derived data

`aktobe_osm.json` is derived from OpenStreetMap, © OpenStreetMap contributors,
made available under the Open Database License (ODbL) 1.0:
https://opendatacommons.org/licenses/odbl/1-0/
https://www.openstreetmap.org/copyright

Retain this attribution and licence information when redistributing the data. This
notice covers the OSM-derived dataset, not a relicensing of unrelated application code.

Source relations:
- https://www.openstreetmap.org/relation/7836092
- https://www.openstreetmap.org/relation/8477889
- https://www.openstreetmap.org/relation/19859667

Discovery: Overpass, fixed Aktobe bounding box (50.18,57.05,50.40,57.40).
Geometry and stop download: official OSM API `/api/0.6/relation/{id}/full.json`.
Transformation: ordered PTv2 stop nodes with entry/exit flags; way geometry retained
as separate polylines, not artificially joined across gaps. Names and address tags
are preserved when supplied. Platform geometry may supply a representative centre.
No timetable, price, availability or accessibility guarantee is added. `fetchedAt`
records retrieval time, not date of a carrier verification. Coverage is partial.
