-- Vitals licenses. One row per key; App Store keys are tied to one purchase
-- (original_transaction_id is UNIQUE, so a purchase can never get two keys).
CREATE TABLE IF NOT EXISTS licenses (
  key                      TEXT PRIMARY KEY,
  source                   TEXT NOT NULL DEFAULT 'appstore',
  original_transaction_id  TEXT UNIQUE,
  environment              TEXT,
  created                  TEXT NOT NULL,
  revoked                  INTEGER NOT NULL DEFAULT 0,
  revoked_at               TEXT,
  revoked_reason           TEXT
);

-- Macs a key is active on (MAX_MACHINES per key, enforced in one INSERT … SELECT).
CREATE TABLE IF NOT EXISTS activations (
  key        TEXT NOT NULL REFERENCES licenses(key),
  machine    TEXT NOT NULL,
  name       TEXT,
  activated  TEXT NOT NULL,
  PRIMARY KEY (key, machine)
);
