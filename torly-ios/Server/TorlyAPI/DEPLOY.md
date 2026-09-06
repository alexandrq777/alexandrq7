# Deploy to a fresh Ubuntu server

Use SSH with a verified host key. Do not overwrite an existing deployment or clear
the server without inspecting it. Install Docker Engine and Compose via the
official Ubuntu instructions. Caddy, not the legacy nginx/systemd example, is the
deployment path for version 0.2.

Copy the API source to `/opt/torly`, excluding `.env`, `*.private.json`, `node_modules`
and backups. The server owns runtime secrets. Open inbound 22, 80 and 443, keeping
the existing SSH session open while changing firewall rules.

Create `.env` from `.env.example` and set a 64-character random hex DB password,
domain. The domain's A record must point at the
server. Do not add an AAAA record unless IPv6 routing is also verified.

```sh
docker compose build
docker compose up -d
docker compose ps
curl --fail https://YOUR_DOMAIN/health
```

Provision a test business using an operator-created `account.private.json`, based
on `provision.example.json`. Keep it mode 600 and out of Git. Services start with
unknown price/duration and must be configured in the app before booking.

```sh
docker compose run --rm -v "$PWD/account.private.json:/run/account.json:ro" --user 0 api node provision.js /run/account.json
sh backup.sh
```

Provisioning intentionally refuses duplicate emails/slugs; it never resets a
password or overwrites a live business. Create the account only once.

The backup file is PostgreSQL custom format. Verify a restore into a separate empty
database using `pg_restore --exit-on-error --no-owner`; never restore on top of the
live database. Backups on the same server are not disaster recovery. Configure
encrypted off-server copies and a schedule before real customer use.

For later releases, take a backup, update source, rebuild images and recreate the
one-shot migration service before recreating API. Do not use `down -v`.

```sh
sh backup.sh
docker compose build
docker compose run --rm migrate
docker compose up -d --force-recreate api proxy
```

Verify on the deployed PostgreSQL: two simultaneous overlapping bookings yield one
success and one conflict, calendar changes reach a second app through SSE, expired
sessions cannot receive private data, and records survive API/database restarts.

Keep current SSH access until a dedicated deployment user and its key are tested.
Only then consider disabling password-based SSH. Never change SSH authentication
before verifying a second successful key-based session.
