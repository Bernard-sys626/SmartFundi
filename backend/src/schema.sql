CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE IF NOT EXISTS regions(id serial PRIMARY KEY, name text UNIQUE NOT NULL, active boolean DEFAULT false);
CREATE TABLE IF NOT EXISTS districts(id serial PRIMARY KEY, region_id int REFERENCES regions(id) ON DELETE CASCADE, name text NOT NULL, active boolean DEFAULT false, UNIQUE(region_id,name));
CREATE TABLE IF NOT EXISTS wards(id serial PRIMARY KEY, district_id int REFERENCES districts(id) ON DELETE CASCADE, name text NOT NULL, UNIQUE(district_id,name));
CREATE TABLE IF NOT EXISTS files(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), owner_id uuid, name text, mime text, data bytea NOT NULL, created_at timestamptz DEFAULT now());
CREATE TABLE IF NOT EXISTS users(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  role text NOT NULL DEFAULT 'client' CHECK (role IN ('client','fundi','admin')),
  is_main_admin boolean DEFAULT false,
  name text, phone text UNIQUE, email text UNIQUE,
  language text DEFAULT 'sw',
  region_id int, district_id int, ward_id int,
  photo_file_id uuid, fcm_token text,
  fundi_type text CHECK (fundi_type IN ('technician','company')),
  company_name text,
  fundi_status text CHECK (fundi_status IN ('incomplete','pending','approved','rejected','suspended')),
  reject_reason text,
  created_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS services(id serial PRIMARY KEY, trade text DEFAULT 'electrical', key text UNIQUE, name_sw text, name_en text, name_fr text, active boolean DEFAULT true, sort int DEFAULT 0);
CREATE TABLE IF NOT EXISTS fundi_services(user_id uuid REFERENCES users(id) ON DELETE CASCADE, service_id int REFERENCES services(id) ON DELETE CASCADE, PRIMARY KEY(user_id,service_id));
CREATE TABLE IF NOT EXISTS fundi_areas(id serial PRIMARY KEY, user_id uuid REFERENCES users(id) ON DELETE CASCADE, region_id int, district_id int, ward_id int);
CREATE TABLE IF NOT EXISTS fundi_documents(id serial PRIMARY KEY, user_id uuid REFERENCES users(id) ON DELETE CASCADE, kind text, name text, file_id uuid, created_at timestamptz DEFAULT now());
CREATE TABLE IF NOT EXISTS admin_regions(user_id uuid REFERENCES users(id) ON DELETE CASCADE, region_id int REFERENCES regions(id) ON DELETE CASCADE, PRIMARY KEY(user_id,region_id));
CREATE SEQUENCE IF NOT EXISTS job_code_seq START 1001;
CREATE TABLE IF NOT EXISTS jobs(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text UNIQUE NOT NULL DEFAULT ('SF-' || nextval('job_code_seq')),
  client_id uuid REFERENCES users(id), fundi_id uuid REFERENCES users(id),
  service_id int REFERENCES services(id),
  preference text DEFAULT 'technician' CHECK (preference IN ('technician','company')),
  description text NOT NULL, notes text,
  region_id int, district_id int, ward_id int,
  lat double precision, lng double precision, address text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','on_the_way','arrived','in_progress','completed','cancelled')),
  nauli_due boolean DEFAULT false, cancel_reason text, cancelled_by text,
  accepted_at timestamptz, on_the_way_at timestamptz, arrived_at timestamptz,
  arrived_lat double precision, arrived_lng double precision,
  started_at timestamptz, completed_at timestamptz, cancelled_at timestamptz,
  created_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS job_photos(job_id uuid REFERENCES jobs(id) ON DELETE CASCADE, file_id uuid, PRIMARY KEY(job_id,file_id));
CREATE TABLE IF NOT EXISTS quotations(job_id uuid PRIMARY KEY REFERENCES jobs(id) ON DELETE CASCADE, amount numeric(14,2) NOT NULL, includes_transport boolean DEFAULT false, note text, file_ids uuid[] DEFAULT '{}', updated_at timestamptz DEFAULT now());
CREATE TABLE IF NOT EXISTS payments(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id uuid REFERENCES jobs(id), client_id uuid REFERENCES users(id),
  amount numeric(14,2) NOT NULL, method text, phone text,
  status text DEFAULT 'pending' CHECK (status IN ('pending','success','failed')),
  reference text,
  commission_percent numeric(5,2), platform_amount numeric(14,2), fundi_amount numeric(14,2),
  created_at timestamptz DEFAULT now(), confirmed_at timestamptz
);
CREATE TABLE IF NOT EXISTS messages(id bigserial PRIMARY KEY, job_id uuid REFERENCES jobs(id) ON DELETE CASCADE, sender_id uuid REFERENCES users(id), body text NOT NULL, created_at timestamptz DEFAULT now());
CREATE TABLE IF NOT EXISTS ratings(job_id uuid PRIMARY KEY REFERENCES jobs(id) ON DELETE CASCADE, rating int CHECK (rating BETWEEN 1 AND 5), comment text, created_at timestamptz DEFAULT now());
CREATE TABLE IF NOT EXISTS notifications(id bigserial PRIMARY KEY, user_id uuid REFERENCES users(id) ON DELETE CASCADE, title text, body text, job_id uuid, read boolean DEFAULT false, created_at timestamptz DEFAULT now());
CREATE TABLE IF NOT EXISTS settings(key text PRIMARY KEY, value jsonb);
CREATE TABLE IF NOT EXISTS otps(identifier text PRIMARY KEY, code_hash text, expires_at timestamptz, attempts int DEFAULT 0);
CREATE INDEX IF NOT EXISTS jobs_status_idx ON jobs(status);
CREATE INDEX IF NOT EXISTS jobs_district_idx ON jobs(district_id);
CREATE INDEX IF NOT EXISTS jobs_client_idx ON jobs(client_id);
CREATE INDEX IF NOT EXISTS jobs_fundi_idx ON jobs(fundi_id);
CREATE INDEX IF NOT EXISTS msg_job_idx ON messages(job_id);
CREATE INDEX IF NOT EXISTS notif_user_idx ON notifications(user_id);

ALTER TABLE users ADD COLUMN IF NOT EXISTS blocked boolean DEFAULT false;
