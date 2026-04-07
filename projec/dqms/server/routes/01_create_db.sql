-- =============================================================================
--  STEP 1 of 2 — Run this as the postgres superuser
--  Command:  psql -U postgres -f 01_create_db.sql
--
--  This script:
--    • Creates the "meru-dqms" database (skips if it already exists)
--    • Creates the "dqms_app" application role (skips if it already exists)
--    • Sets the role password
-- =============================================================================

-- Create the application role if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dqms_app') THEN
    CREATE ROLE dqms_app LOGIN PASSWORD 'dqms_secure_2024';
    RAISE NOTICE 'Role dqms_app created.';
  ELSE
    RAISE NOTICE 'Role dqms_app already exists — skipping.';
  END IF;
END
$$;

-- Create the database if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'meru-dqms') THEN
    RAISE NOTICE 'Creating database meru-dqms ...';
  ELSE
    RAISE NOTICE 'Database meru-dqms already exists — skipping.';
  END IF;
END
$$;

-- CREATE DATABASE cannot run inside a transaction / DO block, so we use
-- a shell-friendly approach: the command below is wrapped in a DO that
-- only prints a message; the actual CREATE DATABASE is outside any block.
-- psql will skip it gracefully if it already exists via the \gexec trick below.
SELECT 'CREATE DATABASE "meru-dqms" OWNER dqms_app ENCODING ''UTF8'''
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'meru-dqms')
\gexec

-- Grant connect privilege
GRANT CONNECT ON DATABASE "meru-dqms" TO dqms_app;

\echo '✅  Step 1 complete. Now run:  psql -U haron -d meru-dqms -f 02_schema.sql'
