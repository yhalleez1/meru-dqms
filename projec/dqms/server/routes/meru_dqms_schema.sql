-- =============================================================================
--  MERU DIGITAL QUEUE MANAGEMENT SYSTEM (DQMS)
--  PostgreSQL Schema — Full Production Setup
--  Database: meru-dqms
-- =============================================================================
--  Tables:
--    1. offices          — service offices/counters
--    2. staff            — staff accounts (linked to offices)
--    3. queue_tickets    — every ticket ever issued
--    4. current_serving  — one row per office: who is currently being served
--    5. ticket_counters  — atomic per-office ticket number generator
--    6. elapsed_log      — per-ticket service duration records
--    7. admin_users      — admin accounts (separate from staff)
--    8. audit_log        — change history for compliance
--
--  Real-time: pg_notify() triggers fire on every key state change
--             so your Node.js server can LISTEN and push to WebSocket clients.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 0.  CREATE DATABASE  (run this as a superuser OUTSIDE a transaction block)
-- ---------------------------------------------------------------------------
-- If the database already exists this is a no-op.
SELECT pg_catalog.set_config('search_path', '', false);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_database WHERE datname = 'meru-dqms'
  ) THEN
    PERFORM dblink_exec(
      'dbname=postgres',
      'CREATE DATABASE "meru-dqms" WITH ENCODING ''UTF8'' LC_COLLATE ''en_US.UTF-8'' LC_CTYPE ''en_US.UTF-8'' TEMPLATE template0'
    );
    RAISE NOTICE 'Database "meru-dqms" created.';
  ELSE
    RAISE NOTICE 'Database "meru-dqms" already exists — skipping creation.';
  END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- NOTE: Connect to the target database before running the rest.
--       In psql:  \c "meru-dqms"
--       In a script / Node migration runner, switch your connection string
--       to  postgresql://user:pass@host/meru-dqms  before executing below.
-- ---------------------------------------------------------------------------

-- Enable the dblink extension used above (only needed in postgres db)
-- Also enable pgcrypto for password hashing support at DB level
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- =============================================================================
-- 1.  OFFICES
-- =============================================================================
CREATE TABLE IF NOT EXISTS offices (
    id          UUID            PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        VARCHAR(120)    NOT NULL,
    status      VARCHAR(20)     NOT NULL DEFAULT 'active'
                                CHECK (status IN ('active', 'inactive', 'closed')),
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  offices            IS 'Service desks / counters in the queue system';
COMMENT ON COLUMN offices.status     IS 'active | inactive | closed';

-- Index: filter active offices quickly
CREATE INDEX IF NOT EXISTS idx_offices_status ON offices (status);


-- =============================================================================
-- 2.  ADMIN USERS
--     Separate from staff — admins manage the whole system.
--     Passwords are stored as bcrypt hashes (handled in application layer).
-- =============================================================================
CREATE TABLE IF NOT EXISTS admin_users (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    username        VARCHAR(80) NOT NULL UNIQUE,
    password_hash   TEXT        NOT NULL,
    full_name       VARCHAR(120),
    email           VARCHAR(200) UNIQUE,
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE admin_users IS 'System administrators (separate from office staff)';

-- Seed the default admin if it does not already exist
-- Password "admin123" — change immediately in production!
INSERT INTO admin_users (username, password_hash, full_name)
VALUES (
    'admin',
    crypt('admin123', gen_salt('bf', 10)),
    'System Administrator'
)
ON CONFLICT (username) DO NOTHING;


-- =============================================================================
-- 3.  STAFF
--     Each staff member belongs to one office.
-- =============================================================================
CREATE TABLE IF NOT EXISTS staff (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            VARCHAR(120) NOT NULL,
    username        VARCHAR(80)  NOT NULL UNIQUE,
    password_hash   TEXT         NOT NULL,
    office_id       UUID         REFERENCES offices (id) ON DELETE SET NULL,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  staff           IS 'Staff who operate the queue at each office';
COMMENT ON COLUMN staff.office_id IS 'NULL means not yet assigned to an office';

-- Indexes
CREATE INDEX IF NOT EXISTS idx_staff_office_id ON staff (office_id);
CREATE INDEX IF NOT EXISTS idx_staff_username  ON staff (username);
CREATE INDEX IF NOT EXISTS idx_staff_active    ON staff (is_active);


-- =============================================================================
-- 4.  TICKET COUNTERS
--     One row per office — auto-increments to generate sequential ticket numbers.
--     Resets daily.  Uses SELECT … FOR UPDATE inside a transaction for safety.
-- =============================================================================
CREATE TABLE IF NOT EXISTS ticket_counters (
    office_id       UUID        PRIMARY KEY REFERENCES offices (id) ON DELETE CASCADE,
    next_ticket     INTEGER     NOT NULL DEFAULT 1,
    reset_date      DATE        NOT NULL DEFAULT CURRENT_DATE
);

COMMENT ON TABLE ticket_counters IS
    'Atomic per-office ticket counter; resets to 1 each new day';


-- =============================================================================
-- 5.  QUEUE TICKETS
--     Core fact table — one row per ticket ever issued.
-- =============================================================================
CREATE TABLE IF NOT EXISTS queue_tickets (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Ticket identity
    ticket_number   INTEGER     NOT NULL,
    office_id       UUID        NOT NULL REFERENCES offices (id) ON DELETE RESTRICT,

    -- Lifecycle status
    status          VARCHAR(20) NOT NULL DEFAULT 'waiting'
                                CHECK (status IN ('waiting', 'called', 'served', 'skipped', 'cancelled')),

    -- Timestamps
    issued_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),   -- when customer pressed button
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),   -- server insert time
    called_at       TIMESTAMPTZ,                          -- when staff clicked "Call Next"
    serve_ended_at  TIMESTAMPTZ,                          -- when ticket closed (served/skipped)
    skipped_at      TIMESTAMPTZ,                          -- set if ticket was skipped

    -- Derived / cached metrics (updated by trigger)
    wait_seconds    INTEGER     GENERATED ALWAYS AS (
                        CASE
                          WHEN called_at IS NOT NULL
                          THEN EXTRACT(EPOCH FROM (called_at - issued_at))::INTEGER
                          ELSE NULL
                        END
                    ) STORED,

    serve_seconds   INTEGER     GENERATED ALWAYS AS (
                        CASE
                          WHEN called_at IS NOT NULL AND serve_ended_at IS NOT NULL
                          THEN EXTRACT(EPOCH FROM (serve_ended_at - called_at))::INTEGER
                          ELSE NULL
                        END
                    ) STORED,

    -- Unique per office per day (ticket_number resets daily)
    UNIQUE (office_id, ticket_number, issued_at::DATE)
);

COMMENT ON TABLE  queue_tickets              IS 'Every ticket ever issued in the queue system';
COMMENT ON COLUMN queue_tickets.wait_seconds IS 'Computed: issued_at → called_at in seconds';
COMMENT ON COLUMN queue_tickets.serve_seconds IS 'Computed: called_at → serve_ended_at in seconds';

-- Indexes — optimised for the most common query patterns
CREATE INDEX IF NOT EXISTS idx_qt_office_status
    ON queue_tickets (office_id, status);

CREATE INDEX IF NOT EXISTS idx_qt_office_status_created
    ON queue_tickets (office_id, status, created_at);

CREATE INDEX IF NOT EXISTS idx_qt_status
    ON queue_tickets (status);

CREATE INDEX IF NOT EXISTS idx_qt_issued_at
    ON queue_tickets (issued_at);

CREATE INDEX IF NOT EXISTS idx_qt_called_at
    ON queue_tickets (called_at)
    WHERE called_at IS NOT NULL;

-- Partial index: fast lookup of the waiting queue per office
CREATE INDEX IF NOT EXISTS idx_qt_waiting_per_office
    ON queue_tickets (office_id, created_at)
    WHERE status = 'waiting';

-- Partial index: analytics — only fully-served tickets
CREATE INDEX IF NOT EXISTS idx_qt_served_analytics
    ON queue_tickets (office_id, issued_at)
    WHERE status = 'served';


-- =============================================================================
-- 6.  CURRENT SERVING
--     One row per office — the ticket currently being served.
--     Upserted (INSERT … ON CONFLICT DO UPDATE) by the application.
-- =============================================================================
CREATE TABLE IF NOT EXISTS current_serving (
    office_id       UUID        PRIMARY KEY REFERENCES offices (id) ON DELETE CASCADE,
    ticket_id       UUID        REFERENCES queue_tickets (id) ON DELETE SET NULL,
    ticket_number   INTEGER,    -- denormalised for fast display reads
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE current_serving IS
    'One row per office tracking the ticket currently being served';


-- =============================================================================
-- 7.  ELAPSED LOG
--     Staff-side elapsed time recorded each time "Call Next" is pressed.
--     This mirrors the Firebase elapsedLog collection.
-- =============================================================================
CREATE TABLE IF NOT EXISTS elapsed_log (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    ticket_id       UUID        NOT NULL REFERENCES queue_tickets (id) ON DELETE CASCADE,
    ticket_number   INTEGER     NOT NULL,
    office_id       UUID        NOT NULL REFERENCES offices (id) ON DELETE CASCADE,
    elapsed_seconds INTEGER     NOT NULL CHECK (elapsed_seconds >= 0),
    log_date        DATE        NOT NULL DEFAULT CURRENT_DATE,
    saved_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE elapsed_log IS
    'Per-ticket elapsed (service) seconds as recorded by staff dashboard';

CREATE INDEX IF NOT EXISTS idx_elapsed_log_date     ON elapsed_log (log_date);
CREATE INDEX IF NOT EXISTS idx_elapsed_log_office   ON elapsed_log (office_id, log_date);
CREATE INDEX IF NOT EXISTS idx_elapsed_log_ticket   ON elapsed_log (ticket_id);


-- =============================================================================
-- 8.  AUDIT LOG
--     Immutable record of important state changes.
-- =============================================================================
CREATE TABLE IF NOT EXISTS audit_log (
    id          BIGSERIAL   PRIMARY KEY,
    entity      VARCHAR(50) NOT NULL,   -- 'ticket' | 'staff' | 'office' | 'admin'
    entity_id   TEXT        NOT NULL,   -- UUID of changed record
    action      VARCHAR(30) NOT NULL,   -- 'create' | 'update' | 'delete' | 'login'
    old_data    JSONB,
    new_data    JSONB,
    changed_by  TEXT,                   -- staff/admin id or 'system'
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE audit_log IS 'Immutable audit trail for all significant changes';

CREATE INDEX IF NOT EXISTS idx_audit_entity    ON audit_log (entity, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_changed_at ON audit_log (changed_at);


-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

-- ---------------------------------------------------------------------------
-- fn_set_updated_at()
--   Generic trigger function — sets updated_at = NOW() before every UPDATE.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- Attach to every table that has updated_at
DO $$
DECLARE
    tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY ARRAY['offices','staff','admin_users']
    LOOP
        EXECUTE format(
            'DROP TRIGGER IF EXISTS trg_set_updated_at ON %I;
             CREATE TRIGGER trg_set_updated_at
             BEFORE UPDATE ON %I
             FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();',
            tbl, tbl
        );
    END LOOP;
END;
$$;


-- ---------------------------------------------------------------------------
-- fn_get_next_ticket_number(p_office_id UUID) → INTEGER
--   Atomically returns the next ticket number for an office, resetting daily.
--   Must be called inside a BEGIN … COMMIT block.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_get_next_ticket_number(p_office_id UUID)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
    v_next  INTEGER;
    v_today DATE := CURRENT_DATE;
BEGIN
    -- Upsert a counter row for this office if it doesn't exist yet
    INSERT INTO ticket_counters (office_id, next_ticket, reset_date)
    VALUES (p_office_id, 1, v_today)
    ON CONFLICT (office_id) DO NOTHING;

    -- Lock the row and check if it needs a daily reset
    SELECT next_ticket, reset_date
    INTO   v_next, v_today            -- reuse v_today to read reset_date
    FROM   ticket_counters
    WHERE  office_id = p_office_id
    FOR UPDATE;

    -- Reset counter if we've crossed into a new day
    IF (SELECT reset_date FROM ticket_counters WHERE office_id = p_office_id) < CURRENT_DATE THEN
        UPDATE ticket_counters
        SET    next_ticket = 2,
               reset_date  = CURRENT_DATE
        WHERE  office_id   = p_office_id;
        RETURN 1;
    END IF;

    -- Normal increment
    UPDATE ticket_counters
    SET    next_ticket = next_ticket + 1
    WHERE  office_id   = p_office_id;

    RETURN v_next;
END;
$$;


-- =============================================================================
-- REAL-TIME NOTIFY TRIGGERS
--   PostgreSQL NOTIFY fires a lightweight event on a named channel.
--   Your Node.js server uses `pg` client.query('LISTEN <channel>') to receive
--   them and forward to WebSocket / SSE clients instantly — zero polling.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Channel: queue_updates
--   Fires when a ticket's status changes or current_serving changes.
--   Payload: JSON with officeId, ticketNumber, status, timestamp.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_notify_queue_update()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    -- Only fire on status changes or new inserts
    IF (TG_OP = 'INSERT') OR
       (TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status) THEN
        PERFORM pg_notify(
            'queue_updates',
            json_build_object(
                'event',         TG_OP,
                'officeId',      NEW.office_id,
                'ticketId',      NEW.id,
                'ticketNumber',  NEW.ticket_number,
                'status',        NEW.status,
                'issuedAt',      NEW.issued_at,
                'calledAt',      NEW.called_at,
                'serveEndedAt',  NEW.serve_ended_at,
                'waitSeconds',   NEW.wait_seconds,
                'ts',            EXTRACT(EPOCH FROM NOW())
            )::TEXT
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_queue_update ON queue_tickets;
CREATE TRIGGER trg_notify_queue_update
AFTER INSERT OR UPDATE ON queue_tickets
FOR EACH ROW EXECUTE FUNCTION fn_notify_queue_update();


-- ---------------------------------------------------------------------------
-- Channel: current_serving_updates
--   Fires when the currently-served ticket for any office changes.
--   Display boards and simulators listen on this channel.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_notify_current_serving()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_notify(
        'current_serving_updates',
        json_build_object(
            'officeId',     NEW.office_id,
            'ticketNumber', NEW.ticket_number,
            'ticketId',     NEW.ticket_id,
            'updatedAt',    EXTRACT(EPOCH FROM NOW())
        )::TEXT
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_current_serving ON current_serving;
CREATE TRIGGER trg_notify_current_serving
AFTER INSERT OR UPDATE ON current_serving
FOR EACH ROW EXECUTE FUNCTION fn_notify_current_serving();


-- ---------------------------------------------------------------------------
-- Channel: office_updates
--   Fires when an office is created, updated, or deleted.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_notify_office_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_row offices%ROWTYPE;
BEGIN
    v_row := COALESCE(NEW, OLD);
    PERFORM pg_notify(
        'office_updates',
        json_build_object(
            'event',    TG_OP,
            'officeId', v_row.id,
            'name',     v_row.name,
            'status',   v_row.status,
            'ts',       EXTRACT(EPOCH FROM NOW())
        )::TEXT
    );
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_office_change ON offices;
CREATE TRIGGER trg_notify_office_change
AFTER INSERT OR UPDATE OR DELETE ON offices
FOR EACH ROW EXECUTE FUNCTION fn_notify_office_change();


-- =============================================================================
-- AUDIT LOG TRIGGERS
--   Automatically record before/after JSONB snapshots for tickets, staff, offices.
-- =============================================================================
CREATE OR REPLACE FUNCTION fn_audit_log()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO audit_log (entity, entity_id, action, old_data, new_data, changed_by)
    VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id::TEXT, OLD.id::TEXT),
        TG_OP,
        CASE WHEN TG_OP != 'INSERT' THEN to_jsonb(OLD) ELSE NULL END,
        CASE WHEN TG_OP != 'DELETE' THEN to_jsonb(NEW) ELSE NULL END,
        current_setting('app.current_user_id', TRUE)  -- set via SET LOCAL in app
    );
    RETURN COALESCE(NEW, OLD);
END;
$$;

-- Attach audit triggers
DO $$
DECLARE
    tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY ARRAY['queue_tickets', 'staff', 'offices', 'admin_users']
    LOOP
        EXECUTE format(
            'DROP TRIGGER IF EXISTS trg_audit ON %I;
             CREATE TRIGGER trg_audit
             AFTER INSERT OR UPDATE OR DELETE ON %I
             FOR EACH ROW EXECUTE FUNCTION fn_audit_log();',
            tbl, tbl
        );
    END LOOP;
END;
$$;


-- =============================================================================
-- ANALYTICS VIEWS
--   Pre-built views mirror the Firebase analytics queries used in admin.html.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- view_daily_stats — one row per office per day
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW view_daily_stats AS
SELECT
    qt.office_id,
    o.name                                  AS office_name,
    qt.issued_at::DATE                      AS stat_date,
    TO_CHAR(qt.issued_at, 'Day')            AS day_name,
    COUNT(*)                                AS tickets_issued,
    COUNT(*) FILTER (WHERE qt.status = 'served')    AS tickets_served,
    COUNT(*) FILTER (WHERE qt.status = 'skipped')   AS tickets_skipped,
    COUNT(*) FILTER (WHERE qt.called_at IS NOT NULL) AS tickets_called,
    ROUND(AVG(qt.wait_seconds)  FILTER (WHERE qt.wait_seconds  IS NOT NULL) / 60.0, 2)
                                            AS avg_wait_minutes,
    ROUND(AVG(qt.serve_seconds) FILTER (WHERE qt.serve_seconds IS NOT NULL) / 60.0, 2)
                                            AS avg_serve_minutes,
    ROUND(SUM(qt.serve_seconds) FILTER (WHERE qt.serve_seconds IS NOT NULL) / 60.0, 2)
                                            AS total_serve_minutes
FROM queue_tickets qt
JOIN offices o ON o.id = qt.office_id
GROUP BY qt.office_id, o.name, qt.issued_at::DATE;

COMMENT ON VIEW view_daily_stats IS
    'Daily ticket statistics per office — used by Admin analytics and reports pages';


-- ---------------------------------------------------------------------------
-- view_weekly_summary — last 7 days (all offices combined)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW view_weekly_summary AS
SELECT
    stat_date,
    day_name,
    SUM(tickets_issued)   AS tickets_issued,
    SUM(tickets_served)   AS tickets_served,
    ROUND(AVG(avg_wait_minutes),  2) AS avg_wait_minutes,
    ROUND(AVG(avg_serve_minutes), 2) AS avg_serve_minutes,
    ROUND(SUM(total_serve_minutes), 2) AS total_serve_minutes
FROM view_daily_stats
WHERE stat_date >= CURRENT_DATE - INTERVAL '6 days'
GROUP BY stat_date, day_name
ORDER BY stat_date DESC;

COMMENT ON VIEW view_weekly_summary IS
    'Last 7 days rolled up across all offices — powers the Weekly Analytics tab';


-- ---------------------------------------------------------------------------
-- view_peak_hours — busiest service hours across the last 7 days
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW view_peak_hours AS
SELECT
    EXTRACT(HOUR FROM called_at)::INTEGER   AS hour_of_day,
    COUNT(*)                                AS ticket_count
FROM queue_tickets
WHERE called_at IS NOT NULL
  AND called_at >= NOW() - INTERVAL '7 days'
GROUP BY 1
ORDER BY 1;

COMMENT ON VIEW view_peak_hours IS
    'Ticket call counts by hour for the last 7 days — used for peak-hour bar chart';


-- ---------------------------------------------------------------------------
-- view_waiting_queue — live waiting list per office
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW view_waiting_queue AS
SELECT
    qt.office_id,
    o.name              AS office_name,
    qt.id               AS ticket_id,
    qt.ticket_number,
    qt.issued_at,
    EXTRACT(EPOCH FROM (NOW() - qt.issued_at))::INTEGER AS waiting_seconds,
    ROW_NUMBER() OVER (PARTITION BY qt.office_id ORDER BY qt.created_at) AS queue_position
FROM queue_tickets qt
JOIN offices o ON o.id = qt.office_id
WHERE qt.status = 'waiting'
ORDER BY qt.office_id, qt.created_at;

COMMENT ON VIEW view_waiting_queue IS
    'Live waiting queue with position and seconds already waited — for staff dashboard';


-- ---------------------------------------------------------------------------
-- view_office_leaderboard — ranked by avg wait time today
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW view_office_leaderboard AS
SELECT
    ds.office_id,
    ds.office_name,
    ds.tickets_served,
    ds.avg_wait_minutes,
    ds.avg_serve_minutes,
    (SELECT COUNT(*) FROM queue_tickets qt
     WHERE qt.office_id = ds.office_id AND qt.status = 'waiting') AS currently_waiting
FROM view_daily_stats ds
WHERE ds.stat_date = CURRENT_DATE
ORDER BY ds.avg_wait_minutes ASC NULLS LAST;

COMMENT ON VIEW view_office_leaderboard IS
    'Today\'s office performance ranked by wait time — for admin dashboard';


-- =============================================================================
-- STORED PROCEDURES  (callable from Node.js with pool.query('CALL …'))
-- =============================================================================

-- ---------------------------------------------------------------------------
-- sp_register_ticket — issue a new ticket for an office
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_register_ticket(
    IN  p_office_id     UUID,
    IN  p_issued_at     TIMESTAMPTZ DEFAULT NOW(),
    OUT p_ticket_id     UUID,
    OUT p_ticket_number INTEGER
)
LANGUAGE plpgsql AS $$
BEGIN
    p_ticket_number := fn_get_next_ticket_number(p_office_id);

    INSERT INTO queue_tickets (ticket_number, office_id, issued_at, status)
    VALUES (p_ticket_number, p_office_id, COALESCE(p_issued_at, NOW()), 'waiting')
    RETURNING id INTO p_ticket_id;
END;
$$;


-- ---------------------------------------------------------------------------
-- sp_call_next — staff calls the next waiting ticket for their office
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_call_next(
    IN  p_office_id     UUID,
    OUT p_ticket_id     UUID,
    OUT p_ticket_number INTEGER,
    OUT p_found         BOOLEAN
)
LANGUAGE plpgsql AS $$
DECLARE
    v_ticket queue_tickets%ROWTYPE;
BEGIN
    -- Get the oldest waiting ticket for this office (lock it)
    SELECT * INTO v_ticket
    FROM   queue_tickets
    WHERE  office_id = p_office_id
      AND  status    = 'waiting'
    ORDER  BY created_at
    LIMIT  1
    FOR UPDATE SKIP LOCKED;

    IF NOT FOUND THEN
        p_found := FALSE;
        p_ticket_id     := NULL;
        p_ticket_number := NULL;
        RETURN;
    END IF;

    -- Mark as called
    UPDATE queue_tickets
    SET    status    = 'called',
           called_at = NOW()
    WHERE  id = v_ticket.id;

    -- Upsert current_serving for this office
    INSERT INTO current_serving (office_id, ticket_id, ticket_number, updated_at)
    VALUES (p_office_id, v_ticket.id, v_ticket.ticket_number, NOW())
    ON CONFLICT (office_id) DO UPDATE
        SET ticket_id    = EXCLUDED.ticket_id,
            ticket_number = EXCLUDED.ticket_number,
            updated_at   = NOW();

    p_found         := TRUE;
    p_ticket_id     := v_ticket.id;
    p_ticket_number := v_ticket.ticket_number;
END;
$$;


-- ---------------------------------------------------------------------------
-- sp_skip_ticket — skip current ticket and auto-call the next one
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_skip_ticket(
    IN  p_ticket_number INTEGER,
    IN  p_office_id     UUID,
    OUT p_next_ticket_number INTEGER,
    OUT p_next_ticket_id     UUID
)
LANGUAGE plpgsql AS $$
DECLARE
    v_next queue_tickets%ROWTYPE;
BEGIN
    -- Mark skipped ticket as 'waiting' again (sent to back of queue) and record skip time
    UPDATE queue_tickets
    SET    status         = 'waiting',
           skipped_at     = NOW(),
           serve_ended_at = NOW()
    WHERE  ticket_number  = p_ticket_number
      AND  office_id      = p_office_id
      AND  status         = 'called';

    -- Call the next waiting ticket
    SELECT * INTO v_next
    FROM   queue_tickets
    WHERE  office_id = p_office_id
      AND  status    = 'waiting'
    ORDER  BY created_at
    LIMIT  1
    FOR UPDATE SKIP LOCKED;

    IF NOT FOUND THEN
        -- No more waiting — clear current_serving
        INSERT INTO current_serving (office_id, ticket_id, ticket_number, updated_at)
        VALUES (p_office_id, NULL, NULL, NOW())
        ON CONFLICT (office_id) DO UPDATE
            SET ticket_id     = NULL,
                ticket_number = NULL,
                updated_at    = NOW();
        p_next_ticket_number := NULL;
        p_next_ticket_id     := NULL;
        RETURN;
    END IF;

    UPDATE queue_tickets
    SET    status    = 'called',
           called_at = NOW()
    WHERE  id = v_next.id;

    INSERT INTO current_serving (office_id, ticket_id, ticket_number, updated_at)
    VALUES (p_office_id, v_next.id, v_next.ticket_number, NOW())
    ON CONFLICT (office_id) DO UPDATE
        SET ticket_id     = EXCLUDED.ticket_id,
            ticket_number = EXCLUDED.ticket_number,
            updated_at    = NOW();

    p_next_ticket_number := v_next.ticket_number;
    p_next_ticket_id     := v_next.id;
END;
$$;


-- ---------------------------------------------------------------------------
-- sp_mark_served — close out a served ticket and save elapsed seconds
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_mark_served(
    IN p_ticket_number   INTEGER,
    IN p_office_id       UUID,
    IN p_elapsed_seconds INTEGER DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_ticket_id UUID;
BEGIN
    UPDATE queue_tickets
    SET    status         = 'served',
           serve_ended_at = NOW()
    WHERE  ticket_number  = p_ticket_number
      AND  office_id      = p_office_id
    RETURNING id INTO v_ticket_id;

    -- Optionally log elapsed seconds
    IF p_elapsed_seconds IS NOT NULL AND v_ticket_id IS NOT NULL THEN
        INSERT INTO elapsed_log (ticket_id, ticket_number, office_id, elapsed_seconds)
        VALUES (v_ticket_id, p_ticket_number, p_office_id, p_elapsed_seconds);
    END IF;
END;
$$;


-- ---------------------------------------------------------------------------
-- sp_staff_login — verify staff credentials, return safe profile
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_staff_login(
    p_username TEXT,
    p_password TEXT
)
RETURNS TABLE (
    id          UUID,
    name        TEXT,
    username    TEXT,
    office_id   UUID,
    office_name TEXT,
    success     BOOLEAN,
    message     TEXT
) LANGUAGE plpgsql AS $$
DECLARE
    v_staff staff%ROWTYPE;
    v_office_name TEXT := NULL;
BEGIN
    SELECT * INTO v_staff FROM staff WHERE staff.username = p_username AND is_active = TRUE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT NULL::UUID, NULL::TEXT, NULL::TEXT,
                            NULL::UUID, NULL::TEXT, FALSE, 'Invalid credentials';
        RETURN;
    END IF;

    IF v_staff.password_hash <> crypt(p_password, v_staff.password_hash) THEN
        RETURN QUERY SELECT NULL::UUID, NULL::TEXT, NULL::TEXT,
                            NULL::UUID, NULL::TEXT, FALSE, 'Invalid credentials';
        RETURN;
    END IF;

    -- Update last_login_at
    UPDATE staff SET last_login_at = NOW() WHERE id = v_staff.id;

    -- Get office name
    IF v_staff.office_id IS NOT NULL THEN
        SELECT o.name INTO v_office_name FROM offices o WHERE o.id = v_staff.office_id;
    END IF;

    RETURN QUERY SELECT v_staff.id, v_staff.name::TEXT, v_staff.username::TEXT,
                        v_staff.office_id, v_office_name, TRUE, 'OK';
END;
$$;


-- =============================================================================
-- ROW-LEVEL SECURITY (RLS)
--   Optional but recommended for multi-tenant deployments.
--   Uncomment and configure roles if you add a separate DB user per office.
-- =============================================================================
-- ALTER TABLE queue_tickets ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY rls_office_isolation ON queue_tickets
--     USING (office_id = current_setting('app.office_id')::UUID);


-- =============================================================================
-- GRANTS  (adjust role names to match your deployment)
-- =============================================================================
-- Replace 'dqms_app' with your application's PostgreSQL role
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dqms_app') THEN
    CREATE ROLE dqms_app LOGIN PASSWORD 'change_me_in_production';
  END IF;
END
$$;

GRANT CONNECT ON DATABASE "meru-dqms" TO dqms_app;
GRANT USAGE   ON SCHEMA public TO dqms_app;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
    offices, staff, queue_tickets, current_serving,
    ticket_counters, elapsed_log, audit_log
TO dqms_app;

GRANT SELECT ON TABLE admin_users TO dqms_app;   -- app reads but never writes raw hashes
GRANT UPDATE (last_login_at, password_hash) ON TABLE admin_users TO dqms_app;
GRANT UPDATE (last_login_at)                ON TABLE staff        TO dqms_app;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO dqms_app; -- covers views
GRANT USAGE, SELECT ON SEQUENCE audit_log_id_seq TO dqms_app;

GRANT EXECUTE ON FUNCTION
    fn_get_next_ticket_number(UUID),
    fn_staff_login(TEXT, TEXT),
    fn_notify_queue_update(),
    fn_notify_current_serving(),
    fn_notify_office_change(),
    fn_audit_log(),
    fn_set_updated_at()
TO dqms_app;

GRANT EXECUTE ON PROCEDURE
    sp_register_ticket(UUID, TIMESTAMPTZ, UUID, INTEGER),
    sp_call_next(UUID, UUID, INTEGER, BOOLEAN),
    sp_skip_ticket(INTEGER, UUID, INTEGER, UUID),
    sp_mark_served(INTEGER, UUID, INTEGER)
TO dqms_app;


-- =============================================================================
-- VERIFICATION QUERIES
--   Run these after applying the schema to confirm everything is in place.
-- =============================================================================
DO $$
DECLARE
    v_table_count   INT;
    v_view_count    INT;
    v_trigger_count INT;
    v_func_count    INT;
BEGIN
    SELECT COUNT(*) INTO v_table_count
    FROM   information_schema.tables
    WHERE  table_schema = 'public' AND table_type = 'BASE TABLE';

    SELECT COUNT(*) INTO v_view_count
    FROM   information_schema.views
    WHERE  table_schema = 'public';

    SELECT COUNT(*) INTO v_trigger_count
    FROM   information_schema.triggers
    WHERE  trigger_schema = 'public';

    SELECT COUNT(*) INTO v_func_count
    FROM   information_schema.routines
    WHERE  routine_schema = 'public';

    RAISE NOTICE '=== Meru DQMS Schema Applied Successfully ===';
    RAISE NOTICE 'Tables   : %', v_table_count;
    RAISE NOTICE 'Views    : %', v_view_count;
    RAISE NOTICE 'Triggers : %', v_trigger_count;
    RAISE NOTICE 'Functions: %', v_func_count;
    RAISE NOTICE '=============================================';
END;
$$;

-- =============================================================================
-- END OF SCHEMA
-- =============================================================================
