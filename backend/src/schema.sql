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
ALTER TABLE users ADD COLUMN IF NOT EXISTS username text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash text;
CREATE UNIQUE INDEX IF NOT EXISTS users_username_idx ON users(lower(username));
ALTER TABLE users ADD COLUMN IF NOT EXISTS must_change_password boolean DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS reset_requested_at timestamptz;

-- ===================== v2: categories, multi-service jobs, directory, BOQ, media, content =====================
-- A client phone number may be shared by several clients (someone can use another person's phone). Only staff accounts keep unique phones.
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_phone_key;
CREATE UNIQUE INDEX IF NOT EXISTS users_phone_staff_idx ON users(phone) WHERE role <> 'client';
CREATE INDEX IF NOT EXISTS users_phone_idx ON users(phone);

CREATE TABLE IF NOT EXISTS categories(
  id serial PRIMARY KEY, key text UNIQUE, name_sw text, name_en text, name_fr text,
  icon text DEFAULT 'build', active boolean DEFAULT true, sort int DEFAULT 0);
ALTER TABLE services ADD COLUMN IF NOT EXISTS category_id int REFERENCES categories(id);
CREATE TABLE IF NOT EXISTS fundi_categories(user_id uuid REFERENCES users(id) ON DELETE CASCADE, category_id int REFERENCES categories(id) ON DELETE CASCADE, PRIMARY KEY(user_id,category_id));
ALTER TABLE users ADD COLUMN IF NOT EXISTS experience text;
ALTER TABLE users ADD COLUMN IF NOT EXISTS admin_rating numeric(2,1);

ALTER TABLE jobs DROP CONSTRAINT IF EXISTS jobs_preference_check;
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS category_id int REFERENCES categories(id);
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS other_service text;
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS ward_text text;
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS target_fundi_id uuid REFERENCES users(id);
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS client_hidden boolean DEFAULT false;
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS resent_at timestamptz;
ALTER TABLE jobs ALTER COLUMN description DROP NOT NULL;
ALTER TABLE jobs ALTER COLUMN lat DROP NOT NULL;
CREATE TABLE IF NOT EXISTS job_services(job_id uuid REFERENCES jobs(id) ON DELETE CASCADE, service_id int REFERENCES services(id), PRIMARY KEY(job_id,service_id));
CREATE INDEX IF NOT EXISTS jobs_target_idx ON jobs(target_fundi_id);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS txn_ref text;

CREATE TABLE IF NOT EXISTS media(
  id serial PRIMARY KEY, placement text NOT NULL DEFAULT 'home', kind text NOT NULL DEFAULT 'image',
  file_id uuid, title text, sort int DEFAULT 0, active boolean DEFAULT true, created_at timestamptz DEFAULT now());

-- BOQ: the master list is edited by Admin (changes for everybody); every Fundi/Company can keep own prices
CREATE TABLE IF NOT EXISTS boq_items(
  id serial PRIMARY KEY, kind text NOT NULL DEFAULT 'item' CHECK (kind IN ('section','group','item','sub')),
  description text NOT NULL, unit text, rate numeric(16,2), sort int NOT NULL DEFAULT 0, active boolean DEFAULT true);
CREATE TABLE IF NOT EXISTS boq_user_rates(user_id uuid REFERENCES users(id) ON DELETE CASCADE, item_id int REFERENCES boq_items(id) ON DELETE CASCADE, rate numeric(16,2) NOT NULL, PRIMARY KEY(user_id,item_id));
CREATE TABLE IF NOT EXISTS boqs(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid REFERENCES users(id) ON DELETE CASCADE, job_id uuid REFERENCES jobs(id) ON DELETE SET NULL,
  title text, client_name text, client_contact text, location text, tin text, installer_name text, installer_phone text,
  lines jsonb NOT NULL DEFAULT '[]', total numeric(16,2) DEFAULT 0,
  created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now());
CREATE INDEX IF NOT EXISTS boqs_owner_idx ON boqs(owner_id);
CREATE INDEX IF NOT EXISTS boqs_job_idx ON boqs(job_id);
CREATE INDEX IF NOT EXISTS fundi_areas_user_idx ON fundi_areas(user_id);
CREATE INDEX IF NOT EXISTS fundi_areas_district_idx ON fundi_areas(district_id);
CREATE INDEX IF NOT EXISTS payments_job_idx ON payments(job_id);
CREATE INDEX IF NOT EXISTS ratings_job_idx ON ratings(job_id);
