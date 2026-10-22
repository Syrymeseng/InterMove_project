# Version log

0.6 — requested by the user after successful local testing of 0.5.
- Added journey data/service, planner, reservations, payments, tickets, management,
  disruptions, notifications, replacement, ratings/favourites and parcel simulator.
- Retained map-first screen, Photon click addresses, local accounts and optional road routing.
- New timetable categories replace the old tram/metro label with trains; metro remains W.
- New passenger booking pages use English by default; main labels support RU/KK.
- Vehicle preference is reset for pets and omitted for parcels per user instruction.
- Seeded vehicle fares/attributes are demonstration data. Direct taxi example is 100 km / 70,000 KZT;
  road-map quotes retain 0.70 KZT/m. Parcel quote is an explicit separate fixed demo policy.
- Added a website source, HTTPS setup guide, API description and requirement/evidence matrix.

No requirement IDs were renumbered. No priorities were silently promoted to Must.
No manager sign-off, participant study or platform acceptance is claimed.
Remaining translation and acceptance work is recorded in REQUIREMENTS_STATUS.md.


## 0.7 — 2026-10-22

User requested separate transit map/results, taxi history/favourites/presence and top notifications.
Added optional metro/tram/LRT scope without making a real feed claim. Backend migration is additive;
existing booked snapshots remain. Added v7.py and transit_map.dart; all lib/backend files must be updated.
No new dependencies. 26 backend tests; Dart syntax only. Flutter/device acceptance remains pending.


## 0.8 — 2026-10-22

Fix hidden settings and divergent launch modes; add persistent server configuration
and desktop loopback default. Simplify search/checkout with progressive disclosure.
Add read-only OSM reference and direct/one-transfer topology search using a licensed
real snapshot; no live timetable or real booking claim. All prior backend tests and
seven OSM tests pass (33 total). Flutter and device checks remain unrun.
