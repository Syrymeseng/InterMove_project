# InterMove API 0.6

JSON objects over HTTPS; loopback HTTP is allowed only for local development.
Protected endpoints require `Authorization: Bearer TOKEN`. Error body: `error`, optional `field`.
Tokens live 24h, logout revokes the current token. Times are Unix UTC seconds; UI displays UTC+05.
Money is integer tiyn (`fareCents`, `priceCents`, `totalCents`); 100 tiyn = 1 KZT.

| Method/path | Body / access / output |
|---|---|
| GET /health | Public status |
| POST /auth/register | name,email,password; always creates passenger |
| POST /auth/login | email,password → account,token |
| POST /auth/logout | {} → ok |
| GET /me | Own account |
| PATCH /me | name,preferences; no role/id/email takeover |
| GET /catalog | Public stops/operators/demoDeparture/display rates |
| POST /search | Public query → options (top 100) |
| POST /holds | ids,query,fingerprint,traveller,email,requestKey,optional replace → hold or reconfirm/new quote |
| POST /holds/release | holdId; owns current hold; idempotent release |
| POST /payment | holdId,outcome → approved + booking or failed outcome; never real charge |
| GET /bookings | Own bookings |
| POST /booking | bookingId; owner/admin only |
| POST /cancellation/quote | bookingId → eligible/reason/cents/legs |
| POST /cancellation | bookingId,confirmed=true,expectedCents,reason; owner/admin; no duplicate refunds |
| POST /alternatives | bookingId → search options using original needs; explicit replacement required |
| GET /notifications | Own notifications |
| POST /notifications/read | id; only own record updated |
| GET /drivers | Synthetic drivers, favourite, rating average/count |
| POST /favourite | driverId,saved boolean |
| POST /rating | bookingId,legId,score; owner, completed taxi leg, once |
| GET /parcels | Own parcels; admin sees simulator jobs |
| POST /parcels | See parcel form; confirmed=false → quote; true → idempotent request |
| POST /parcels/advance | id,status; admin only; defined transitions |
| GET /manage/services | Operator's own services; admin all |
| POST /manage/service | service object; ownership and validation; recheck bookings |
| GET /manage/catalog | Admin: operators/drivers/stops/accounts/audit |
| POST /manage/operator | id,name,accountId; admin, assigned account must be operator |
| POST /manage/account | id,role; admin; cannot change own role; revokes target sessions |
| POST /manage/driver | driver object including vehicle; admin; recheck affected bookings |
| POST /manage/stop | stop object with access/transfer minimum/walk time; admin; recheck |
| POST /manage/advance | bookingId; admin test event advances next leg |
| GET /admin/summary | Admin account/audit count |

Query: origin/destination integer stop IDs, future departure number, passengers 1–4,
buffer 15/30, modes list of city_bus/intercity_bus/train/taxi, sort fare/duration, needs object.
Needs: stepFree, boardingAssistance booleans; wheelchair none/folded/seated; pets boolean,
petType cat/dog/small_pet, petSize small/medium/large, carrier boolean; gender any/woman/man;
optional driverId. Pet requests reset gender to any per requested product behaviour.
Unknown requested access attributes exclude a service. Unknown/unavailable stops do not relax constraints.

Preferences are independent of booked snapshots: access fields plus locale en/ru/kk,
currency KZT/USD/EUR, avatar plain/blue/gold and marker pin/circle/flag. Empty object removes saved preferences.

Checkout requests: preserve requestKey and full request body on uncertain network outcome.
A repeated key with a different body gets 409. Reconfirmation happens before creating the hold.
Payment outcomes: approved, declined, timeout, approved_then_failed (explicit failure-injection scenario).
Payment retry returns the existing outcome for that hold regardless of repeated taps.

Service schema is exemplified by journeys.seed and /manage/services. Attribute map keys:
stepFree, folded, seated, boardingAssistance. true=supported, false=unsupported, absent=unknown.
Animal policy: pets boolean, petSizes list, carrierRequired boolean. Stop transfer time is
max(passenger buffer, stop minimum) + walkMinutes; only identical transfer IDs connect.
Taxi allocations block overlapping slots of a vehicle, including distinct service IDs.

Parcel fields: sender,senderContact,recipient,recipientContact,origin,destination,size,
dimensions [cm,cm,cm], weight kg, requestKey,confirmed. Sizes S=30×20×20/5kg,
M=50×40×40/10kg,L=80×60×60/20kg. Rotation of the parcel dimensions is allowed.
Configured flat demo base quote: S 1000 KZT, M 1500 KZT, L 2000 KZT; surcharge 0.

Schema extends 0.5 without dropping accounts. Transactions use BEGIN IMMEDIATE for
reservation/payment/cancellation/management. Cleanup runs every 15 seconds in the server
process and on API booking operations. No API deletes audit events or resets the database.
Source files contain no test account passwords. Create staff interactively via server CLI.

## 0.7 extensions

All taxi endpoints require a session and are scoped to its account; `/manage/*` below
requires administrator role. No real driver messages or reservations are sent by them.

- GET `/taxi/history`: `{trips,drivers,demo}`. Only taxi legs of this account's bookings,
  plus explicitly saved demo orders. Drivers include online, favourite and requestStatus.
- POST `/taxi/demo-order`: requestKey (8–100 chars), driverId, origin, destination,
  passengers 1–4, meters, optional wheelchair/pets. Saves labelled demo order after
  vehicle compatibility checks; price 70 tiyn/metre. Same account/key returns same id.
- POST `/taxi/request`: driverId from own history/favourites. Returns waiting/notified;
  retries while pending reuse current state. No booking is created.
- POST `/taxi/request/cancel`: driverId; removes only current account's request.
- POST `/manage/presence`: driverId, online boolean. Offline→online transition notifies
  favourites and pending requests once. Presence is separate from scheduled availability.
- GET `/manage/taxi-requests`: administrator simulator inbox.
- POST `/manage/taxi-response`: accountId, driverId, status accepted/rejected. Responds
  once to a pending request; subsequent retries return the same terminal result.
- GET `/catalog` now includes availableModes. Optional modes metro, tram, lrt supported
  through ordinary search/hold/payment validation, only where dataset has services.
- Quote legs include originStop and destinationStop snapshots for map and station labels.
- Notifications with booking_id `driver:<id>` target taxi history, not `/booking`.

The demo simulator is an explicit fallback for FR42, not a driver-facing client.

## 0.8 OSM reference endpoints (public, read-only)

- GET `/transit/osm`: source/license/fetchedAt/stale/warning and OSM lines with stops,
  separate geometry segments, route relation IDs and source URLs. Partial Aktobe coverage.
- POST `/transit/osm/plan`: `{from:[lat,lon],to:[lat,lon],needs:{...}}`. Returns directed
  topology options, up to two transit legs, boarding/alighting stops and straight-line
  walking distances. Unknown mandatory accessibility excludes results.

These results are not timed itineraries, do not create seats or holds and cannot be
purchased. Network requests occur outside booking database transactions. Shared cache
refresh is bounded; a packaged OSM-derived snapshot remains available on provider failure.
