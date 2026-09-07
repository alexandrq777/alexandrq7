# Torly: native app and server

## Topology

```mermaid
flowchart LR
    App[iPhone / SwiftUI] -->|HTTPS REST| Proxy[Caddy :443]
    App -->|HTTPS event stream| Proxy
    Proxy --> API[Node.js API :3100]
    API --> DB[(PostgreSQL 17)]
    DB -->|LISTEN / NOTIFY| API
    Mac[Developer Mac] -->|SSH :22| Host[Hetzner]
    DB --> Jobs[Notification jobs: disabled until providers connected]
```

One server is enough for the prototype architecture. Database and API ports are not
published. Caddy terminates TLS. The app never receives database or SSH credentials.
This is a single-host deployment, not a highly available cluster.

## Implemented in this change

- PostgreSQL schema and versioned, transactional migrations.
- Self-service email/password accounts, salted scrypt password hashes, expiring/revocable
  opaque sessions; the iPhone stores session tokens in Keychain.
- Ownership checks on every private route. Public profiles expose an explicit
  field allowlist, and new businesses start unpublished.
- Expandable category table, business timezone/currency/locale/country, separate
  employee hours, inactive services until price and duration are provided.
- Availability uses Luxon/IANA zones and UTC instants, including DST changes.
- Appointments snapshot price, duration and service name. Database exclusion
  constraint prevents overlaps with bookings, breaks and leave. Intervals are [start,end).
- Booking creation is idempotent per request UUID. Optimistic revision checks
  protect confirmation, cancellation and rescheduling against stale edits.
- Client cards are stored per business. No-show increments are transactional.
- PostgreSQL notifications are emitted at commit. Authenticated SSE streams tell
  active iPhones to refetch. Reconnection also refetches missed changes.
- SwiftUI-only live owner flow: empty registration, business setup, calendar,
  clients, service/staff creation, individual hours, breaks/leave and rescheduling.
  Demo screens and bundled demo models have been removed. Day totals use real entries.
- Native publication toggle and sharing. Same-host public client page uses only
  allowlisted published business data, active services and free slots. Public and
  owner bookings share one transactional booking implementation and overlap constraint.
  Public submissions cannot overwrite an existing client's name.
- Notification outbox schema with due date, delivery status and micro-USD cost.
  Jobs stay `disabled`: no messages or fictional delivery confirmations are sent.
- Docker Compose, Caddy HTTPS config and a PostgreSQL backup command with a daily systemd timer.

The main plan is 3900 ILS minor units per month. Billing is not enabled.

## Not yet connected

- Email verification, Apple/Google login and password recovery.
- Client authentication and self-service cancellation/rescheduling,
  profile photo storage and onboarding photo upload.
- WhatsApp templates, consent, credentials, provider webhooks, quota reservations,
  retry worker, waitlist notifications, push/APNs and calendar integrations.
- Reviews, forms, reports, payment collection and subscription enforcement.
- Automatic off-server backup rotation and external uptime monitoring.

No tax receipts, accounting or fiscal inventory are part of this stage.

## WhatsApp next step

Keep provider credentials server-side. Add consent records and approved utility
templates per language. A worker claims due jobs with `FOR UPDATE SKIP LOCKED`,
rechecks booking state/revision and quota, then records the provider message ID.
Verify webhook signatures and deduplicate delivery events. Record actual charged
cost by recipient market and category; do not assume Israeli prices worldwide.
Add worker network egress only when the provider is connected. The API currently
runs on an internal-only Docker network and cannot send external requests.

## Prototype deployment gates

1. Verify SSH access to the newly created server, then inspect existing services.
2. Install Docker/Compose, allow SSH/HTTP/HTTPS and preserve current SSH access.
3. Point a controlled domain at the server and set `.env` locally on that server.
4. Build containers, migrate the database, register an empty owner account.
5. Verify HTTPS health, auth, booking persistence, real concurrent conflict handling
   and SSE on actual PostgreSQL; test from two app sessions.
6. Take a backup and restore it into a separate test database.
7. Install a signed iPhone build using the owner's Apple development team.

Local tests use PGlite (PostgreSQL WASM with btree_gist) to execute the real schema
and HTTP API. `TORLY_VERIFY_PG=1` runs the same suite on an isolated `torly_verify`
PostgreSQL database and additionally checks simultaneous requests and SSE delivery.

## Deployment verified 2026-09-06

- HTTPS API at `https://torly.cybermemo.dev`, using a dedicated DNS record in Cloudflare.
- PostgreSQL/API/Caddy running on the user's Hetzner server. The domain root is unchanged.
- Existing owner account retained; seeded business removed after backup at the
  user's explicit request. New accounts and business service lists start empty.
- Five tests passed on actual PostgreSQL, including concurrent overlap rejection and SSE.
- Daily backup timer active at 03:00 UTC. Initial backup restored into a separate database.
- Signed physical iPhone build and simulator build succeeded.

The hostname serves the API and public booking pages at /book/:slug.
Businesses start unpublished; the owner explicitly enables sharing. Owner login details are in a separate
local private file, never embedded in the app or committed to GitHub.

## Public Booking Limits

Public booking requests require no owner account; they start pending, not confirmed.
Phone ownership is not verified. The current IP/phone throttling is a prototype
abuse limit, not a replacement for OTP or production bot protection.
Public availability is limited to the next 180 days. Prices/duration are always
read from the database. Tests cover unpublished/private access, duplicates,
simultaneous public bookings and notifications to the owner's event stream.
