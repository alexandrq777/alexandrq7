# Torly API 0.2

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
- `POST /v1/session`: `{email,password}` -> `{token}`; expires after seven days.
- `DELETE /v1/session`: revoke the current session.
- `GET /v1/categories`: extensible business categories, Hebrew/English.
- `GET /v1/public/:slug`: published business profile, no private client fields.
- `GET /v1/owner`: owned businesses, services, staff, working hours.
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

Errors: 400 validation, 401 session, 404 inaccessible resource, 409 conflict,
429 login throttling, 500 unavailable. Unauthenticated writes and arbitrary
owner IDs from callers are not supported. All SQL parameters are bound.

## Deploy and limits

Follow `DEPLOY.md` and `../../Docs/server-architecture.md`. Real accounts are
created with `provision.js`, using a local ignored `*.private.json` file.

The prototype supports provisioned owners only. Self-service sign-up, public
booking writes, provider logins, payments, WhatsApp/APNs delivery, waitlist,
reviews and forms are not yet connected. Notification jobs are explicitly disabled.
The plan metadata is ILS 39/month; subscription collection is not active.

`nginx-torly-api.conf` and `torly-api.service` belong to the old in-memory starter.
Use Compose/Caddy for this version; do not install both configurations.
