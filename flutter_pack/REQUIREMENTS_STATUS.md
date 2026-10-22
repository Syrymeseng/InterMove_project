# Requirement traceability — v0.8

**Implemented** means code exists, not that device acceptance is complete. Backend tests
were actually run; Flutter tests were authored but could not run in this environment.
No usability study, certification, Windows/Android pass or assessor approval is claimed.

## Functional requirements

| ID | Implementation / evidence | Remaining acceptance |
|---|---|---|
| FR01 | Unique normalized email, name/password validation; test_server registration/duplicate test | Field errors are shown in a page message; inline field placement still needs UI refinement |
| FR02 | Sign-in/out, token revocation/expiry; session tests | Device UI logout/expiry test |
| FR03 | Own name/preferences edit, explicit save/delete; ownership/persistence tests | Email is displayed, not editable; saved needs snapshot is separate from bookings |
| FR04 S | EN/RU/KK selector, main navigation/control translations and retained locale | **Partial:** complete remaining passenger messages and legacy map translations |
| FR05 S | Fixed KZT/USD/EUR estimates; authoritative checkout in KZT | Device formatting check |
| FR06 | Endpoints, UTC departure, count 1–4; invalid/no-match tests | Date input is a basic text field |
| FR07 | City/intercity bus, train, taxi; operator, fare, schedule, duration, capacity/access | Seeded records only; real feeds excluded |
| FR08 | Connected ≤3 legs, same transfer stop, buffers; multimodal/impossible connection tests | User walkthrough |
| FR09 | Mode/needs filters, fare/duration ordering, capacity checks; search tests | Device filter walkthrough |
| FR10 | Each leg, waits, itemized fare, total duration; textual itinerary | Visual layout polish |
| FR11 | Explicit no match; needs retained; unknown-access/pet-size tests | Screen-reader announcement on device |
| FR12 S | Stop sequence and labelled simulated origin/midpoint/destination indicator; manual endpoints | Schematic, not live tracking; no GPS permission requested |
| FR13 | Traveller/contact/count/needs, quote/cancellation terms | Field-error placement and keyboard walkthrough |
| FR14 | Numbered seats, city capacity, taxi slots; last-seat race test | No visual seat-picker (automatic allocation is allowed) |
| FR15 | Revalidation, 300s hold, changed-offer reconfirmation; price-change test | Flutter countdown/reconfirmation walkthrough |
| FR16 | Approved/declined/timeout without cards; failure-release tests | Device checkout |
| FR17 | Atomic all-leg confirmation, simulated reversal, no partial persisted booking; failure tests | Storage outage/device recovery exercise |
| FR18 | Unique IM reference, per-leg DEMO ticket with seats/details; booking tests | Export is copy-to-clipboard, not legally valid ticket/PDF |
| FR19 | Per-account request keys and per-hold payment outcome; replay/race tests | Flutter double tap/network restart walkthrough |
| FR20 | Own history/upcoming/details, account-bound lookup; privacy/restart tests | Device screen workflow |
| FR21 | Quote, explicit cancellation, release, per-leg refund; refund test | Device confirmation |
| FR22 | Ineligible reason, repeat refund protection; repeated cancel/completed-leg tests | Device message |
| FR23 S | Linked replacement, old booking survives failure, atomic success/refund; replacement test | User workflow |
| FR24 | Persistent unread notifications linked to booking; read/ownership tests | Refresh-based; no OS push promised |
| FR25 | Step-free/assistance/folded/seated independent fields | User comprehension evaluation |
| FR26 | All-leg vehicle/stop/transfer checks; unknown data excludes; access-change tests | No real vehicle certification |
| FR27 | Per-leg support/policies and immutable booked snapshots | Human-friendly presentation of all attribute combinations needs polish |
| FR28 | No-match retains required needs; only explicit edits relax | Screen reader / usability |
| FR29 S | max(15/30 min, stop minimum) + stop walk time | Dataset currently same-stop transfers; custom stop walk times supported |
| FR30 S | Synthetic driver filter and no-match; avatar denotes record gender | Pet trips intentionally reset gender per user instruction; delivery has no gender control |
| FR31 S | Pet type/size/carrier, per-leg declared policy, livestock rejected | Dataset supports cats/dogs/small pets; no real carrier guarantees |
| FR32 S | Favourite save/remove and driver-specific search with all other constraints | Driver menu walkthrough |
| FR33 S | One score 1–5 per completed taxi leg; valid average/count; rating test | UI success feedback |
| FR34 | Operator-owned service CRUD; fares/capacity/access; admin drivers/vehicles/operators | Management uses basic field forms and IDs; improve labels/layout |
| FR35 | Server roles, assigned-operator boundary, private booking lookup; authorization tests | Android/Windows hidden-screen attempts |
| FR36 | Delay/cancel/unavailable updates search/current booking info; original snapshot retained; notifications | Clients refresh rather than realtime push |
| FR37 | Connection/access recheck after service/driver/stop edits; disruption/refund; disruption tests | More manual mixed completed/in-progress scenarios |
| FR38 | Admin reference lookup, same cancellation quote/rules, audit reason/actor/time | Admin UI walkthrough |
| FR39 | Persistent audit for edits, confirmations, cancellations/refunds; no deletion API | Admin audit UI only shows latest 200 |
| FR40 S | Compatible alternatives query, replacement workflow, explicit absence | Replacements are only before first leg starts under BR07; later disruption uses refunds |
| FR41 C | Parcel contacts/endpoints/dimensions/weight, S/M/L limits, itemized quote and status; parcel tests | Flat configured test quote, not live courier quote |
| FR42 C | Authorized admin simulator advances taxi journeys and accepts/rejects/progresses parcels | Separate driver application intentionally omitted, as permitted by fallback in requirement |
| FR43 C | Saved avatar frame and map marker shape, labels retained | Device readability check |
| FR44 S | website/index.html describes prototype/platforms/limits | Installers not yet built/released; download buttons intentionally disabled until real files exist |

## Non-functional requirements

| ID | Evidence / current limit |
|---|---|
| NFR01 | performance.py: 30 backend searches with 1,000 departures/100 drivers; result JSON includes timings. Not full end-to-end Windows/Android measurement. Loading indicator is coded, 0.5s target not device-measured. |
| NFR02 | SQLite transactions, final-seat race and overlapping-vehicle test; reopened store retains records. Device process-restart still needs demonstration. |
| NFR03 | Persisted checkout payload/key/hold for resume, idempotent API. Real background-worker check released expired allocation in ~15 seconds (expiry_result.json). Flutter crash/resume test still required. |
| NFR04 | Standard focusable Material controls. Full keyboard workflow and no-trap test NOT executed. |
| NFR05 | Scrollable layouts, enlarged category cards, textual status, minimum control sizes. Full contrast inventory and 200% device test NOT executed; widget test included but unrun. |
| NFR06 | Tooltips/labels, live error semantics, 48px button theme. Android TalkBack test NOT executed. |
| NFR07 | scrypt + random salts; hash-only session tokens; five failures in rolling 15 minutes restrict retries; tests run. |
| NFR08 | TLS server support; local HTTPS test validates certificate. Team tunnel/device TLS not deployed or tested. Loopback --local-dev is explicitly an unencrypted development exception. |
| NFR09 | Only contacts/preferences; explicit save/delete; preference whitelist; synthetic profiles. No cards/diagnoses or credentials logged. |
| NFR10 | Windows/Android builds and 1366×768 / 360×800 acceptance remain UNVERIFIED. macOS is a development convenience, not substituted for Android evidence. |
| NFR11 | Seeded text/schematic does not require map APIs. Network errors preserve forms and never generate confirmation client-side. Device loss/recovery exercise still required. |
| NFR12 | API.md, seed/reset guide, tests/results, this matrix, version log and source manifest included. Team must commit and rehearse setup. |
| NFR13 S | 6/7 participant study NOT conducted. Do not mark passed or invent results. |

## Objectives

O1–O4 have code and backend scenarios: multimodal journey, booking lifecycle, access
no-match, disruptions. O5 still requires platform and user evaluation. O6 has repeatable
seed/fixtures and test mapping; not all Must acceptance evidence exists yet.

Livestock, real payments/tickets/dispatch, app-store publication and live video remain excluded.
User-requested scope change on 2026-10-22 adds OPTIONAL metro/tram/LRT data-driven modes.
No real metro, tram or LRT schedules are claimed.


## v0.7 additions and evidence

- FR07/08/10/12: separate mode entry, 62/38 desktop map/panel, selected schematic and checkout map;
  Oral/Astana and optional demo metro/tram/LRT fixtures. Server route/transfer tests pass.
  Map/device layout remains unverified; real geometry/addresses/nearest-stop walking are absent.
- FR24: top notifications, unread count inside hub, departure information, 15-second in-app polling;
  driver events link to taxi history, booking events to booking. No background OS push.
- FR32/42: account-scoped taxi history, favourites, admin-controlled presence and request inbox,
  idempotent accepted/rejected responses. Main-map DEMO order is explicitly not a confirmed booking.
- 26 backend tests pass (test_results.txt), including additive v0.6 migration and privacy tests.
- Flutter analyzer, widget tests and platform builds remain UNRUN. No new device acceptance claimed.


## v0.8 update

- Settings are always visible; runtime server address, public health check, persistent
  preference, desktop loopback default. Switching endpoint clears account/session and
  rejects in-flight replies from the previous endpoint. Flutter tests authored but unrun.
- Checkout uses a compact summary with expandable passenger/details/policies/test cases.
  Required price and cancellation summary remain visible; device UX remains unverified.
- OSM city reference: three real route relations, provenance/licence and retrieval time;
  whole-line geometry, directional direct/one-transfer topology candidates. It is NOT
  live transit scheduling, walking routing, capacity or booking. Real train/intercity
  data and full city coverage remain absent. Timed demonstration booking stays separate.
- 33 backend tests passed including seven OSM tests. Overpass relation discovery succeeded;
  geometry requests failed, so included geometry was retrieved from the official OSM API.
  Automatic future Overpass refresh has unit-tested fallback but was not proven live here.
- No Flutter builds or device acceptance claimed; keyboard/TalkBack/contrast/complete
  translations remain outstanding as in previous versions.
