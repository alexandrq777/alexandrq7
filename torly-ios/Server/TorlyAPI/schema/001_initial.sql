CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE,
  password_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE sessions (
  token_hash text PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  expires_at timestamptz NOT NULL
);
CREATE TABLE categories (id text PRIMARY KEY, name_en text NOT NULL, name_he text NOT NULL);
INSERT INTO categories VALUES
 ('nails','Nails','ציפורניים'), ('barber','Barber','ברבר'),
 ('lashes','Lashes','ריסים'), ('brows','Brows','גבות'),
 ('hair-styling','Hair styling','עיצוב שיער'), ('skin-care','Skin care','טיפוח העור'),
 ('hair-removal','Hair removal','הסרת שיער'), ('makeup','Makeup','איפור'),
 ('tanning','Tanning','שיזוף'), ('tattoo-piercing','Tattoo and piercing','קעקועים ופירסינג'),
 ('injections-fillers','Injections and fillers','הזרקות ומילוי'), ('massage','Massage','עיסוי'),
 ('dentistry','Dentistry','רפואת שיניים'), ('veterinary','Veterinary','וטרינריה'),
 ('fitness','Fitness','כושר'), ('consulting-holistic','Consulting and holistic therapy','ייעוץ וטיפול הוליסטי'),
 ('optics','Optics','אופטיקה'), ('other','Other','אחר');

CREATE TABLE businesses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES accounts(id),
  slug text NOT NULL UNIQUE,
  name text NOT NULL,
  phone text NOT NULL,
  address text NOT NULL,
  category_id text NOT NULL REFERENCES categories(id),
  timezone text NOT NULL DEFAULT 'Asia/Jerusalem',
  currency text NOT NULL DEFAULT 'ILS',
  locale text NOT NULL DEFAULT 'he',
  country text NOT NULL DEFAULT 'IL',
  published boolean NOT NULL DEFAULT false,
  plan_price_minor integer NOT NULL DEFAULT 3900,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX businesses_owner ON businesses(owner_id);
CREATE TABLE staff (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL REFERENCES businesses(id),
  name text NOT NULL,
  UNIQUE (id, business_id)
);
CREATE TABLE working_hours (
  staff_id uuid NOT NULL REFERENCES staff(id),
  weekday integer NOT NULL CHECK (weekday BETWEEN 0 AND 6),
  opens_at time NOT NULL,
  closes_at time NOT NULL,
  PRIMARY KEY (staff_id, weekday),
  CHECK (opens_at < closes_at)
);
CREATE TABLE services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL REFERENCES businesses(id),
  name text NOT NULL,
  price_minor integer CHECK (price_minor >= 0),
  minutes integer CHECK (minutes BETWEEN 5 AND 480),
  active boolean NOT NULL DEFAULT false,
  CHECK (NOT active OR (price_minor IS NOT NULL AND minutes IS NOT NULL)),
  UNIQUE (id, business_id)
);
CREATE TABLE clients (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL REFERENCES businesses(id),
  name text NOT NULL,
  phone text NOT NULL,
  note text NOT NULL DEFAULT '',
  no_show_count integer NOT NULL DEFAULT 0,
  UNIQUE (business_id, phone),
  UNIQUE (id, business_id)
);
-- One occupancy table makes appointments, breaks and holidays mutually exclusive.
CREATE TABLE calendar_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL REFERENCES businesses(id),
  staff_id uuid NOT NULL,
  service_id uuid,
  client_id uuid,
  kind text NOT NULL CHECK (kind IN ('booking','break','time_off')),
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','confirmed','cancelled','completed','no_show')),
  service_name text,
  price_minor integer,
  currency text NOT NULL,
  revision integer NOT NULL DEFAULT 1,
  request_key uuid NOT NULL UNIQUE,
  request_hash text NOT NULL,
  CHECK (starts_at < ends_at),
  CHECK (kind <> 'booking' OR (service_id IS NOT NULL AND client_id IS NOT NULL)),
  FOREIGN KEY (staff_id, business_id) REFERENCES staff(id, business_id),
  FOREIGN KEY (service_id, business_id) REFERENCES services(id, business_id),
  FOREIGN KEY (client_id, business_id) REFERENCES clients(id, business_id),
  EXCLUDE USING gist (staff_id WITH =, tstzrange(starts_at, ends_at, '[)') WITH &&)
    WHERE (status <> 'cancelled')
);
CREATE INDEX calendar_business_time ON calendar_entries(business_id, starts_at);
CREATE TABLE notification_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL REFERENCES calendar_entries(id),
  channel text NOT NULL CHECK (channel IN ('whatsapp','push')),
  run_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'disabled' CHECK (status IN ('disabled','pending','processing','sent','failed','cancelled')),
  attempts integer NOT NULL DEFAULT 0,
  provider_id text,
  delivered_at timestamptz,
  cost_microusd bigint,
  UNIQUE (booking_id, channel)
);
CREATE INDEX notification_due ON notification_jobs(run_at) WHERE status = 'pending';
