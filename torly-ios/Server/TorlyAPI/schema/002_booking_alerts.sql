CREATE TABLE booking_alerts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id uuid NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
  booking_id uuid NOT NULL UNIQUE REFERENCES calendar_entries(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz
);
CREATE INDEX booking_alerts_business_created ON booking_alerts(business_id, created_at DESC);
