# Torly API 0.4

Node.js 22 + PostgreSQL 17 + Caddy. Native iPhone client in `../../TorBooking`.
Replaces the earlier in-memory demonstration API. No legacy `/api/*` endpoint
is exposed without authentication.

## Development

```sh
pnpm install --frozen-lockfile
pnpm test
```

Tests execute the real schema and HTTP routes using PGlite with btree_gist. A real
PostgreSQL server is still required to verify concurrent connections and SSE.
For a local PostgreSQL instance set `DATABASE_URL`, then run `pnpm migrate` and
`pnpm start`. The API listens on localhost:3100 outside Compose.

## HTTP contract

All private requests use `Authorization: Bearer <session token>`.
JSON uses snake_case in database responses and camelCase in mutation inputs.

- `GET /health`: database readiness.
- `POST /v1/accounts`: email/password (12+ characters); returns session, creates no business.
- `POST /v1/session`: `{email,password}` -> `{token}`; expires after seven days.
- `DELETE /v1/session`: revoke the current session.
- `GET /v1/categories`: extensible business categories, Hebrew/English.
- `GET /v1/public/:slug`: published business profile, no private client fields.
- `GET /book/:slug`: responsive client page; no owner app installation required.
- Booking pages also support HEAD and optional trailing slashes. Slug lookup is
  case-insensitive to preserve links created by older iPhone UUIDs.
- `GET /v1/public/:slug/availability?staffId=UUID&serviceId=UUID&date=YYYY-MM-DD`.
- `POST /v1/public/:slug/bookings`: serviceId, staffId, startsAt, clientName,
  clientPhone, requestKey; business is resolved from the published slug.
- `PUT /v1/businesses/:id/publishing`: owner-only {published}; requires an
  active service and configured working hours to publish.
- `GET /v1/owner`: owned businesses, services, staff, working hours.
- `POST /v1/businesses`: contact/region/category fields, staffName, hours and requestKey.
  Creates an unpublished business with one staff member and no services or client data.
- `PUT /v1/businesses/:id`: update contact/region/category fields.
- `POST /v1/services`: businessId, name, priceMinor, minutes and requestKey.
- `DELETE /v1/services/:id`: archive; historical appointments are preserved.
- `POST /v1/staff`: businessId, name, hours and requestKey.
- `POST /v1/blocks`: staffId, startsAt, endsAt, kind (break/time_off) and requestKey.
- `GET /v1/clients?businessId=UUID`: real client cards and completed visits.
- `PUT /v1/clients/:id`: update note (up to 2000 characters).
- `GET /v1/bookings?businessId=UUID&from=ISO&to=ISO`: up to 32 days.
- `GET /v1/availability?businessId=UUID&staffId=UUID&serviceId=UUID&date=YYYY-MM-DD`:
  free start instants in UTC, calculated in the business timezone.
- `POST /v1/bookings`: `{businessId,staffId,serviceId,startsAt,clientName,clientPhone,requestKey}`.
  `requestKey` is a UUID retained across retries of the same request.
- `PATCH /v1/bookings/:id`: `{revision,status}` or `{revision,startsAt}`.
- `PUT /v1/services/:id`: `{name,priceMinor,minutes}`; activates a configured service.
- `PUT /v1/staff/:id/hours`: array of `{weekday,opensAt,closesAt}`; 0=Sunday.
  Omitted days are closed. Changes affect future availability; existing appointments remain.
- `GET /v1/events`: authenticated SSE; calendar events trigger a client refetch.
  A separate `online-booking` event is emitted after a new public booking commits,
  only to the owner's business-scoped streams. It contains no client data and is
  not emitted for idempotent retries, owner-created appointments or service edits.
  This live signal is not durable background push; APNs delivery remains pending.
- `GET /v1/alerts`: owner-scoped inbox, up to 100 entries with unread entries first.
  Contains identifiers, booking start and creation/read times, no client contact data.
- `POST /v1/alerts/read`: {ids}, 1-100 UUIDs; marks only the authenticated owner's
  entries read. Migration 002 stores one alert per new public booking in the booking
  transaction. Retries and rejected overlaps cannot create duplicates. Older
  bookings are not backfilled. Native foreground polling/reconnect uses this inbox;
  it does not provide delivery while iOS has suspended the app.

Errors: 400 validation, 401 session, 404 inaccessible resource, 409 conflict,
429 login throttling, 500 unavailable. Unauthenticated writes and arbitrary
owner IDs from callers are not supported. All SQL parameters are bound.

## Deploy and limits

Follow `DEPLOY.md` and `../../Docs/server-architecture.md`. Accounts are created
through the native registration form. `provision.js` is an optional operator/test
tool, not a startup seed. Never run test fixtures against the primary database.

The prototype supports self-service owners and public booking requests.
Email verification/recovery, provider logins, payments, WhatsApp/APNs delivery, waitlist,
reviews and forms are not yet connected. Notification jobs are explicitly disabled.
The plan metadata is ILS 39/month; subscription collection is not active.

Auth throttling is process-local. Compose isolates the API from direct internet
access and Caddy overwrites X-Real-IP; TRUST_PROXY must only be enabled behind
that trusted proxy. Multi-instance deployment needs shared throttling.

Optional browser QA: `node test/browser-check.js` with Playwright available.
PLAYWRIGHT_MODULE may point to its module, and BROWSER_CHANNEL=chrome uses local
Chrome. Fixtures exist only in memory. Public phone numbers are not OTP-verified;
add production bot protection/verification before a broad commercial launch.

Business and client-page locales: he, en, es, ru. Native Localizable.strings
coverage and format-argument consistency are checked by localization.test.js on macOS.

`nginx-torly-api.conf` and `torly-api.service` belong to the old in-memory starter.
Use Compose/Caddy for this version; do not install both configurations.
