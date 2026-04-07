--
-- PostgreSQL database dump
--

-- Dumped from database version 17.4 (Debian 17.4-2)
-- Dumped by pg_dump version 17.4 (Debian 17.4-2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: fn_audit_log(); Type: FUNCTION; Schema: public; Owner: haron
--

CREATE FUNCTION public.fn_audit_log() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO audit_log (entity, entity_id, action, old_data, new_data, changed_by)
    VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id::TEXT, OLD.id::TEXT),
        TG_OP,
        CASE WHEN TG_OP != 'INSERT' THEN to_jsonb(OLD) ELSE NULL END,
        CASE WHEN TG_OP != 'DELETE' THEN to_jsonb(NEW) ELSE NULL END,
        current_setting('app.current_user_id', TRUE)
    );
    RETURN COALESCE(NEW, OLD);
END;
$$;


ALTER FUNCTION public.fn_audit_log() OWNER TO haron;

--
-- Name: fn_calc_ticket_times(); Type: FUNCTION; Schema: public; Owner: haron
--

CREATE FUNCTION public.fn_calc_ticket_times() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- wait_seconds: issued_at → called_at
    IF NEW.called_at IS NOT NULL AND NEW.issued_at IS NOT NULL THEN
        NEW.wait_seconds = EXTRACT(EPOCH FROM (NEW.called_at - NEW.issued_at))::INTEGER;
    ELSE
        NEW.wait_seconds = NULL;
    END IF;

    -- serve_seconds: called_at → serve_ended_at
    IF NEW.called_at IS NOT NULL AND NEW.serve_ended_at IS NOT NULL THEN
        NEW.serve_seconds = EXTRACT(EPOCH FROM (NEW.serve_ended_at - NEW.called_at))::INTEGER;
    ELSE
        NEW.serve_seconds = NULL;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_calc_ticket_times() OWNER TO haron;

--
-- Name: fn_get_next_ticket_number(uuid); Type: FUNCTION; Schema: public; Owner: haron
--

CREATE FUNCTION public.fn_get_next_ticket_number(p_office_id uuid) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_next       INTEGER;
    v_reset_date DATE;
BEGIN
    -- Ensure a counter row exists for this office
    INSERT INTO ticket_counters (office_id, next_ticket, reset_date)
    VALUES (p_office_id, 1, CURRENT_DATE)
    ON CONFLICT (office_id) DO NOTHING;

    -- Lock and read
    SELECT next_ticket, reset_date
    INTO   v_next, v_reset_date
    FROM   ticket_counters
    WHERE  office_id = p_office_id
    FOR UPDATE;

    -- Daily reset
    IF v_reset_date < CURRENT_DATE THEN
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


ALTER FUNCTION public.fn_get_next_ticket_number(p_office_id uuid) OWNER TO haron;

--
-- Name: fn_notify_current_serving(); Type: FUNCTION; Schema: public; Owner: haron
--

CREATE FUNCTION public.fn_notify_current_serving() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


ALTER FUNCTION public.fn_notify_current_serving() OWNER TO haron;

--
-- Name: fn_notify_office_change(); Type: FUNCTION; Schema: public; Owner: haron
--

CREATE FUNCTION public.fn_notify_office_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


ALTER FUNCTION public.fn_notify_office_change() OWNER TO haron;

--
-- Name: fn_notify_queue_update(); Type: FUNCTION; Schema: public; Owner: haron
--

CREATE FUNCTION public.fn_notify_queue_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF (TG_OP = 'INSERT') OR
       (TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status) THEN
        PERFORM pg_notify(
            'queue_updates',
            json_build_object(
                'event',        TG_OP,
                'officeId',     NEW.office_id,
                'ticketId',     NEW.id,
                'ticketNumber', NEW.ticket_number,
                'status',       NEW.status,
                'issuedAt',     NEW.issued_at,
                'calledAt',     NEW.called_at,
                'serveEndedAt', NEW.serve_ended_at,
                'waitSeconds',  NEW.wait_seconds,
                'ts',           EXTRACT(EPOCH FROM NOW())
            )::TEXT
        );
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_notify_queue_update() OWNER TO haron;

--
-- Name: fn_set_updated_at(); Type: FUNCTION; Schema: public; Owner: haron
--

CREATE FUNCTION public.fn_set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_set_updated_at() OWNER TO haron;

--
-- Name: fn_staff_login(text, text); Type: FUNCTION; Schema: public; Owner: haron
--

CREATE FUNCTION public.fn_staff_login(p_username text, p_password text) RETURNS TABLE(id uuid, name text, username text, office_id uuid, office_name text, success boolean, message text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_staff staff%ROWTYPE;
    v_office_name TEXT := NULL;
BEGIN
    SELECT * INTO v_staff
    FROM   staff
    WHERE  staff.username = p_username
      AND  is_active = TRUE;

    IF NOT FOUND THEN
        RETURN QUERY SELECT
            NULL::UUID, NULL::TEXT, NULL::TEXT,
            NULL::UUID, NULL::TEXT, FALSE, 'Invalid credentials'::TEXT;
        RETURN;
    END IF;

    IF v_staff.password_hash != crypt(p_password, v_staff.password_hash) THEN
        RETURN QUERY SELECT
            NULL::UUID, NULL::TEXT, NULL::TEXT,
            NULL::UUID, NULL::TEXT, FALSE, 'Invalid credentials'::TEXT;
        RETURN;
    END IF;

    UPDATE staff SET last_login_at = NOW() WHERE id = v_staff.id;

    IF v_staff.office_id IS NOT NULL THEN
        SELECT o.name INTO v_office_name
        FROM offices o WHERE o.id = v_staff.office_id;
    END IF;

    RETURN QUERY SELECT
        v_staff.id,
        v_staff.name::TEXT,
        v_staff.username::TEXT,
        v_staff.office_id,
        v_office_name,
        TRUE,
        'OK'::TEXT;
END;
$$;


ALTER FUNCTION public.fn_staff_login(p_username text, p_password text) OWNER TO haron;

--
-- Name: sp_call_next(uuid); Type: PROCEDURE; Schema: public; Owner: haron
--

CREATE PROCEDURE public.sp_call_next(IN p_office_id uuid, OUT p_ticket_id uuid, OUT p_ticket_number integer, OUT p_found boolean)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id            UUID;
    v_ticket_number INTEGER;
BEGIN
    -- Grab oldest waiting ticket (skip locked = non-blocking)
    SELECT id, ticket_number
    INTO   v_id, v_ticket_number
    FROM   queue_tickets
    WHERE  office_id = p_office_id
      AND  status    = 'waiting'
    ORDER  BY created_at
    LIMIT  1
    FOR UPDATE SKIP LOCKED;

    IF NOT FOUND THEN
        p_found         := FALSE;
        p_ticket_id     := NULL;
        p_ticket_number := NULL;
        RETURN;
    END IF;

    -- Mark as called
    UPDATE queue_tickets
    SET    status    = 'called',
           called_at = NOW()
    WHERE  id = v_id;

    -- Upsert current_serving
    INSERT INTO current_serving (office_id, ticket_id, ticket_number, updated_at)
    VALUES (p_office_id, v_id, v_ticket_number, NOW())
    ON CONFLICT (office_id) DO UPDATE
        SET ticket_id     = EXCLUDED.ticket_id,
            ticket_number = EXCLUDED.ticket_number,
            updated_at    = NOW();

    p_found         := TRUE;
    p_ticket_id     := v_id;
    p_ticket_number := v_ticket_number;
END;
$$;


ALTER PROCEDURE public.sp_call_next(IN p_office_id uuid, OUT p_ticket_id uuid, OUT p_ticket_number integer, OUT p_found boolean) OWNER TO haron;

--
-- Name: sp_mark_served(integer, uuid, integer); Type: PROCEDURE; Schema: public; Owner: haron
--

CREATE PROCEDURE public.sp_mark_served(IN p_ticket_number integer, IN p_office_id uuid, IN p_elapsed_seconds integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_ticket_id UUID;
BEGIN
    UPDATE queue_tickets
    SET    status         = 'served',
           serve_ended_at = NOW()
    WHERE  ticket_number  = p_ticket_number
      AND  office_id      = p_office_id
    RETURNING id INTO v_ticket_id;

    IF p_elapsed_seconds IS NOT NULL AND v_ticket_id IS NOT NULL THEN
        INSERT INTO elapsed_log (ticket_id, ticket_number, office_id, elapsed_seconds)
        VALUES (v_ticket_id, p_ticket_number, p_office_id, p_elapsed_seconds);
    END IF;
END;
$$;


ALTER PROCEDURE public.sp_mark_served(IN p_ticket_number integer, IN p_office_id uuid, IN p_elapsed_seconds integer) OWNER TO haron;

--
-- Name: sp_register_ticket(uuid, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: haron
--

CREATE PROCEDURE public.sp_register_ticket(IN p_office_id uuid, IN p_issued_at timestamp with time zone, OUT p_ticket_id uuid, OUT p_ticket_number integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    p_ticket_number := fn_get_next_ticket_number(p_office_id);

    INSERT INTO queue_tickets (ticket_number, office_id, issued_at, status)
    VALUES (p_ticket_number, p_office_id, COALESCE(p_issued_at, NOW()), 'waiting')
    RETURNING id INTO p_ticket_id;
END;
$$;


ALTER PROCEDURE public.sp_register_ticket(IN p_office_id uuid, IN p_issued_at timestamp with time zone, OUT p_ticket_id uuid, OUT p_ticket_number integer) OWNER TO haron;

--
-- Name: sp_skip_ticket(integer, uuid); Type: PROCEDURE; Schema: public; Owner: haron
--

CREATE PROCEDURE public.sp_skip_ticket(IN p_ticket_number integer, IN p_office_id uuid, OUT p_next_ticket_number integer, OUT p_next_ticket_id uuid)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_next_id     UUID;
    v_next_number INTEGER;
BEGIN
    -- Send skipped ticket back to waiting
    UPDATE queue_tickets
    SET    status         = 'waiting',
           skipped_at     = NOW(),
           serve_ended_at = NOW()
    WHERE  ticket_number  = p_ticket_number
      AND  office_id      = p_office_id
      AND  status         = 'called';

    -- Find next waiting ticket
    SELECT id, ticket_number
    INTO   v_next_id, v_next_number
    FROM   queue_tickets
    WHERE  office_id = p_office_id
      AND  status    = 'waiting'
    ORDER  BY created_at
    LIMIT  1
    FOR UPDATE SKIP LOCKED;

    IF NOT FOUND THEN
        -- Queue empty — clear current serving
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
    WHERE  id = v_next_id;

    INSERT INTO current_serving (office_id, ticket_id, ticket_number, updated_at)
    VALUES (p_office_id, v_next_id, v_next_number, NOW())
    ON CONFLICT (office_id) DO UPDATE
        SET ticket_id     = EXCLUDED.ticket_id,
            ticket_number = EXCLUDED.ticket_number,
            updated_at    = NOW();

    p_next_ticket_number := v_next_number;
    p_next_ticket_id     := v_next_id;
END;
$$;


ALTER PROCEDURE public.sp_skip_ticket(IN p_ticket_number integer, IN p_office_id uuid, OUT p_next_ticket_number integer, OUT p_next_ticket_id uuid) OWNER TO haron;

--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: haron
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_updated_at_column() OWNER TO haron;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: admin_users; Type: TABLE; Schema: public; Owner: haron
--

CREATE TABLE public.admin_users (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    username character varying(80) NOT NULL,
    password_hash text NOT NULL,
    full_name character varying(120),
    email character varying(200),
    is_active boolean DEFAULT true NOT NULL,
    last_login_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.admin_users OWNER TO haron;

--
-- Name: TABLE admin_users; Type: COMMENT; Schema: public; Owner: haron
--

COMMENT ON TABLE public.admin_users IS 'System administrators';


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: haron
--

CREATE TABLE public.audit_log (
    id bigint NOT NULL,
    entity character varying(50) NOT NULL,
    entity_id text NOT NULL,
    action character varying(30) NOT NULL,
    old_data jsonb,
    new_data jsonb,
    changed_by text,
    changed_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.audit_log OWNER TO haron;

--
-- Name: TABLE audit_log; Type: COMMENT; Schema: public; Owner: haron
--

COMMENT ON TABLE public.audit_log IS 'Immutable audit trail';


--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: haron
--

CREATE SEQUENCE public.audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.audit_log_id_seq OWNER TO haron;

--
-- Name: audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: haron
--

ALTER SEQUENCE public.audit_log_id_seq OWNED BY public.audit_log.id;


--
-- Name: current_serving; Type: TABLE; Schema: public; Owner: haron
--

CREATE TABLE public.current_serving (
    ticket_id uuid,
    ticket_number integer,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    office_id integer NOT NULL
);


ALTER TABLE public.current_serving OWNER TO haron;

--
-- Name: TABLE current_serving; Type: COMMENT; Schema: public; Owner: haron
--

COMMENT ON TABLE public.current_serving IS 'Currently-served ticket per office';


--
-- Name: dqms_records; Type: TABLE; Schema: public; Owner: haron
--

CREATE TABLE public.dqms_records (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    dqms_number character varying(50) NOT NULL,
    ticket_number integer,
    ticket_sent boolean DEFAULT false,
    ticket_sent_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    student_id uuid,
    office_id integer
);


ALTER TABLE public.dqms_records OWNER TO haron;

--
-- Name: TABLE dqms_records; Type: COMMENT; Schema: public; Owner: haron
--

COMMENT ON TABLE public.dqms_records IS 'DQMS device registration linked to students and offices';


--
-- Name: COLUMN dqms_records.dqms_number; Type: COMMENT; Schema: public; Owner: haron
--

COMMENT ON COLUMN public.dqms_records.dqms_number IS 'Unique DQMS device identifier';


--
-- Name: COLUMN dqms_records.ticket_number; Type: COMMENT; Schema: public; Owner: haron
--

COMMENT ON COLUMN public.dqms_records.ticket_number IS 'Generated ticket number for the student';


--
-- Name: COLUMN dqms_records.ticket_sent; Type: COMMENT; Schema: public; Owner: haron
--

COMMENT ON COLUMN public.dqms_records.ticket_sent IS 'Whether SMS notification was sent';


--
-- Name: COLUMN dqms_records.student_id; Type: COMMENT; Schema: public; Owner: haron
--

COMMENT ON COLUMN public.dqms_records.student_id IS 'Foreign key to students table';


--
-- Name: COLUMN dqms_records.office_id; Type: COMMENT; Schema: public; Owner: haron
--

COMMENT ON COLUMN public.dqms_records.office_id IS 'Foreign key to offices table';


--
-- Name: elapsed_log; Type: TABLE; Schema: public; Owner: haron
--

CREATE TABLE public.elapsed_log (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    ticket_id uuid NOT NULL,
    ticket_number integer NOT NULL,
    elapsed_seconds integer NOT NULL,
    log_date date DEFAULT CURRENT_DATE NOT NULL,
    saved_at timestamp with time zone DEFAULT now() NOT NULL,
    office_id integer,
    CONSTRAINT elapsed_log_elapsed_seconds_check CHECK ((elapsed_seconds >= 0))
);


ALTER TABLE public.elapsed_log OWNER TO haron;

--
-- Name: TABLE elapsed_log; Type: COMMENT; Schema: public; Owner: haron
--

COMMENT ON TABLE public.elapsed_log IS 'Per-ticket elapsed service seconds from staff dashboard';


--
-- Name: offices_id_seq; Type: SEQUENCE; Schema: public; Owner: haron
--

CREATE SEQUENCE public.offices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.offices_id_seq OWNER TO haron;

--
-- Name: offices; Type: TABLE; Schema: public; Owner: haron
--

CREATE TABLE public.offices (
    name character varying(120) NOT NULL,
    status character varying(20) DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    id integer DEFAULT nextval('public.offices_id_seq'::regclass) NOT NULL,
    CONSTRAINT offices_status_check CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'inactive'::character varying, 'closed'::character varying])::text[])))
);


ALTER TABLE public.offices OWNER TO haron;

--
-- Name: TABLE offices; Type: COMMENT; Schema: public; Owner: haron
--

COMMENT ON TABLE public.offices IS 'Service desks / counters';


--
-- Name: offices_temp_id_seq; Type: SEQUENCE; Schema: public; Owner: haron
--

CREATE SEQUENCE public.offices_temp_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.offices_temp_id_seq OWNER TO haron;

--
-- Name: offices_temp_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: haron
--

ALTER SEQUENCE public.offices_temp_id_seq OWNED BY public.offices.id;


--
-- Name: queue_tickets; Type: TABLE; Schema: public; Owner: haron
--

CREATE TABLE public.queue_tickets (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    ticket_number integer NOT NULL,
    status character varying(20) DEFAULT 'waiting'::character varying NOT NULL,
    issued_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    called_at timestamp with time zone,
    serve_ended_at timestamp with time zone,
    skipped_at timestamp with time zone,
    wait_seconds integer,
    serve_seconds integer,
    dqms_number character varying(50),
    office_id integer,
    CONSTRAINT queue_tickets_status_check CHECK (((status)::text = ANY ((ARRAY['waiting'::character varying, 'called'::character varying, 'served'::character varying, 'skipped'::character varying, 'cancelled'::character varying])::text[])))
);


ALTER TABLE public.queue_tickets OWNER TO haron;

--
-- Name: TABLE queue_tickets; Type: COMMENT; Schema: public; Owner: haron
--

COMMENT ON TABLE public.queue_tickets IS 'Every ticket ever issued';


--
-- Name: staff; Type: TABLE; Schema: public; Owner: haron
--

CREATE TABLE public.staff (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name character varying(120) NOT NULL,
    username character varying(80) NOT NULL,
    password_hash text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    last_login_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    office_id integer
);


ALTER TABLE public.staff OWNER TO haron;

--
-- Name: TABLE staff; Type: COMMENT; Schema: public; Owner: haron
--

COMMENT ON TABLE public.staff IS 'Staff who operate queue counters';


--
-- Name: students; Type: TABLE; Schema: public; Owner: haron
--

CREATE TABLE public.students (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    dqms_number character varying(50) NOT NULL,
    phone_number character varying(20) NOT NULL,
    student_name character varying(100),
    registration_number character varying(50),
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.students OWNER TO haron;

--
-- Name: TABLE students; Type: COMMENT; Schema: public; Owner: haron
--

COMMENT ON TABLE public.students IS 'Student records linked to DQMS devices';


--
-- Name: COLUMN students.dqms_number; Type: COMMENT; Schema: public; Owner: haron
--

COMMENT ON COLUMN public.students.dqms_number IS 'Unique DQMS device identifier';


--
-- Name: COLUMN students.phone_number; Type: COMMENT; Schema: public; Owner: haron
--

COMMENT ON COLUMN public.students.phone_number IS 'Phone number for SMS notifications (+254...)';


--
-- Name: COLUMN students.registration_number; Type: COMMENT; Schema: public; Owner: haron
--

COMMENT ON COLUMN public.students.registration_number IS 'National ID or student ID';


--
-- Name: ticket_counters; Type: TABLE; Schema: public; Owner: haron
--

CREATE TABLE public.ticket_counters (
    next_ticket integer DEFAULT 1 NOT NULL,
    reset_date date DEFAULT CURRENT_DATE NOT NULL,
    office_id integer NOT NULL
);


ALTER TABLE public.ticket_counters OWNER TO haron;

--
-- Name: TABLE ticket_counters; Type: COMMENT; Schema: public; Owner: haron
--

COMMENT ON TABLE public.ticket_counters IS 'Atomic per-office ticket counter, resets daily';


--
-- Name: view_peak_hours; Type: VIEW; Schema: public; Owner: haron
--

CREATE VIEW public.view_peak_hours AS
 SELECT (EXTRACT(hour FROM called_at))::integer AS hour_of_day,
    (count(*))::integer AS ticket_count
   FROM public.queue_tickets
  WHERE ((called_at IS NOT NULL) AND (called_at >= (now() - '7 days'::interval)))
  GROUP BY ((EXTRACT(hour FROM called_at))::integer)
  ORDER BY ((EXTRACT(hour FROM called_at))::integer);


ALTER VIEW public.view_peak_hours OWNER TO haron;

--
-- Name: audit_log id; Type: DEFAULT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.audit_log ALTER COLUMN id SET DEFAULT nextval('public.audit_log_id_seq'::regclass);


--
-- Name: admin_users admin_users_email_key; Type: CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT admin_users_email_key UNIQUE (email);


--
-- Name: admin_users admin_users_pkey; Type: CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT admin_users_pkey PRIMARY KEY (id);


--
-- Name: admin_users admin_users_username_key; Type: CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT admin_users_username_key UNIQUE (username);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: current_serving current_serving_pkey; Type: CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.current_serving
    ADD CONSTRAINT current_serving_pkey PRIMARY KEY (office_id);


--
-- Name: dqms_records dqms_records_dqms_number_key; Type: CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.dqms_records
    ADD CONSTRAINT dqms_records_dqms_number_key UNIQUE (dqms_number);


--
-- Name: dqms_records dqms_records_dqms_number_unique; Type: CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.dqms_records
    ADD CONSTRAINT dqms_records_dqms_number_unique UNIQUE (dqms_number);


--
-- Name: dqms_records dqms_records_pkey; Type: CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.dqms_records
    ADD CONSTRAINT dqms_records_pkey PRIMARY KEY (id);


--
-- Name: elapsed_log elapsed_log_pkey; Type: CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.elapsed_log
    ADD CONSTRAINT elapsed_log_pkey PRIMARY KEY (id);


--
-- Name: offices offices_pkey; Type: CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.offices
    ADD CONSTRAINT offices_pkey PRIMARY KEY (id);


--
-- Name: queue_tickets queue_tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.queue_tickets
    ADD CONSTRAINT queue_tickets_pkey PRIMARY KEY (id);


--
-- Name: staff staff_pkey; Type: CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_pkey PRIMARY KEY (id);


--
-- Name: staff staff_username_key; Type: CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_username_key UNIQUE (username);


--
-- Name: students students_dqms_number_key; Type: CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_dqms_number_key UNIQUE (dqms_number);


--
-- Name: students students_pkey; Type: CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.students
    ADD CONSTRAINT students_pkey PRIMARY KEY (id);


--
-- Name: ticket_counters ticket_counters_pkey; Type: CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.ticket_counters
    ADD CONSTRAINT ticket_counters_pkey PRIMARY KEY (office_id);


--
-- Name: idx_audit_changed_at; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_audit_changed_at ON public.audit_log USING btree (changed_at);


--
-- Name: idx_audit_entity; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_audit_entity ON public.audit_log USING btree (entity, entity_id);


--
-- Name: idx_dqms_dqms_number; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_dqms_dqms_number ON public.dqms_records USING btree (dqms_number);


--
-- Name: idx_dqms_office_id; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_dqms_office_id ON public.dqms_records USING btree (office_id);


--
-- Name: idx_dqms_records_dqms_number; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_dqms_records_dqms_number ON public.dqms_records USING btree (dqms_number);


--
-- Name: idx_dqms_records_office_id; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_dqms_records_office_id ON public.dqms_records USING btree (office_id);


--
-- Name: idx_dqms_records_student_id; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_dqms_records_student_id ON public.dqms_records USING btree (student_id);


--
-- Name: idx_dqms_records_ticket_sent; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_dqms_records_ticket_sent ON public.dqms_records USING btree (ticket_sent);


--
-- Name: idx_dqms_ticket_number; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_dqms_ticket_number ON public.dqms_records USING btree (ticket_number);


--
-- Name: idx_elapsed_log_date; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_elapsed_log_date ON public.elapsed_log USING btree (log_date);


--
-- Name: idx_elapsed_log_office; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_elapsed_log_office ON public.elapsed_log USING btree (office_id, log_date);


--
-- Name: idx_elapsed_log_ticket; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_elapsed_log_ticket ON public.elapsed_log USING btree (ticket_id);


--
-- Name: idx_offices_status; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_offices_status ON public.offices USING btree (status);


--
-- Name: idx_qt_called_at; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_qt_called_at ON public.queue_tickets USING btree (called_at) WHERE (called_at IS NOT NULL);


--
-- Name: idx_qt_issued_at; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_qt_issued_at ON public.queue_tickets USING btree (issued_at);


--
-- Name: idx_queue_tickets_dqms_number; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_queue_tickets_dqms_number ON public.queue_tickets USING btree (dqms_number);


--
-- Name: idx_queue_tickets_office_status; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_queue_tickets_office_status ON public.queue_tickets USING btree (office_id, status);


--
-- Name: idx_staff_active; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_staff_active ON public.staff USING btree (is_active);


--
-- Name: idx_staff_office_id; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_staff_office_id ON public.staff USING btree (office_id);


--
-- Name: idx_staff_username; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_staff_username ON public.staff USING btree (username);


--
-- Name: idx_students_active; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_students_active ON public.students USING btree (is_active);


--
-- Name: idx_students_dqms_number; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_students_dqms_number ON public.students USING btree (dqms_number);


--
-- Name: idx_students_phone; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_students_phone ON public.students USING btree (phone_number);


--
-- Name: idx_students_phone_number; Type: INDEX; Schema: public; Owner: haron
--

CREATE INDEX idx_students_phone_number ON public.students USING btree (phone_number);


--
-- Name: admin_users trg_audit; Type: TRIGGER; Schema: public; Owner: haron
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON public.admin_users FOR EACH ROW EXECUTE FUNCTION public.fn_audit_log();


--
-- Name: offices trg_audit; Type: TRIGGER; Schema: public; Owner: haron
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON public.offices FOR EACH ROW EXECUTE FUNCTION public.fn_audit_log();


--
-- Name: queue_tickets trg_audit; Type: TRIGGER; Schema: public; Owner: haron
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON public.queue_tickets FOR EACH ROW EXECUTE FUNCTION public.fn_audit_log();


--
-- Name: staff trg_audit; Type: TRIGGER; Schema: public; Owner: haron
--

CREATE TRIGGER trg_audit AFTER INSERT OR DELETE OR UPDATE ON public.staff FOR EACH ROW EXECUTE FUNCTION public.fn_audit_log();


--
-- Name: queue_tickets trg_calc_ticket_times; Type: TRIGGER; Schema: public; Owner: haron
--

CREATE TRIGGER trg_calc_ticket_times BEFORE INSERT OR UPDATE ON public.queue_tickets FOR EACH ROW EXECUTE FUNCTION public.fn_calc_ticket_times();


--
-- Name: current_serving trg_notify_current_serving; Type: TRIGGER; Schema: public; Owner: haron
--

CREATE TRIGGER trg_notify_current_serving AFTER INSERT OR UPDATE ON public.current_serving FOR EACH ROW EXECUTE FUNCTION public.fn_notify_current_serving();


--
-- Name: offices trg_notify_office_change; Type: TRIGGER; Schema: public; Owner: haron
--

CREATE TRIGGER trg_notify_office_change AFTER INSERT OR DELETE OR UPDATE ON public.offices FOR EACH ROW EXECUTE FUNCTION public.fn_notify_office_change();


--
-- Name: queue_tickets trg_notify_queue_update; Type: TRIGGER; Schema: public; Owner: haron
--

CREATE TRIGGER trg_notify_queue_update AFTER INSERT OR UPDATE ON public.queue_tickets FOR EACH ROW EXECUTE FUNCTION public.fn_notify_queue_update();


--
-- Name: admin_users trg_set_updated_at; Type: TRIGGER; Schema: public; Owner: haron
--

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.admin_users FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();


--
-- Name: offices trg_set_updated_at; Type: TRIGGER; Schema: public; Owner: haron
--

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.offices FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();


--
-- Name: staff trg_set_updated_at; Type: TRIGGER; Schema: public; Owner: haron
--

CREATE TRIGGER trg_set_updated_at BEFORE UPDATE ON public.staff FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();


--
-- Name: dqms_records update_dqms_records_updated_at; Type: TRIGGER; Schema: public; Owner: haron
--

CREATE TRIGGER update_dqms_records_updated_at BEFORE UPDATE ON public.dqms_records FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: students update_students_updated_at; Type: TRIGGER; Schema: public; Owner: haron
--

CREATE TRIGGER update_students_updated_at BEFORE UPDATE ON public.students FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: current_serving current_serving_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.current_serving
    ADD CONSTRAINT current_serving_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES public.queue_tickets(id) ON DELETE SET NULL;


--
-- Name: dqms_records dqms_records_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.dqms_records
    ADD CONSTRAINT dqms_records_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id) ON DELETE SET NULL;


--
-- Name: elapsed_log elapsed_log_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.elapsed_log
    ADD CONSTRAINT elapsed_log_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES public.queue_tickets(id) ON DELETE CASCADE;


--
-- Name: current_serving fk_current_serving_office; Type: FK CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.current_serving
    ADD CONSTRAINT fk_current_serving_office FOREIGN KEY (office_id) REFERENCES public.offices(id) ON DELETE CASCADE;


--
-- Name: dqms_records fk_dqms_records_office; Type: FK CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.dqms_records
    ADD CONSTRAINT fk_dqms_records_office FOREIGN KEY (office_id) REFERENCES public.offices(id) ON DELETE SET NULL;


--
-- Name: elapsed_log fk_elapsed_log_office; Type: FK CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.elapsed_log
    ADD CONSTRAINT fk_elapsed_log_office FOREIGN KEY (office_id) REFERENCES public.offices(id) ON DELETE CASCADE;


--
-- Name: queue_tickets fk_queue_tickets_dqms_number; Type: FK CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.queue_tickets
    ADD CONSTRAINT fk_queue_tickets_dqms_number FOREIGN KEY (dqms_number) REFERENCES public.dqms_records(dqms_number) ON DELETE SET NULL;


--
-- Name: queue_tickets fk_queue_tickets_office; Type: FK CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.queue_tickets
    ADD CONSTRAINT fk_queue_tickets_office FOREIGN KEY (office_id) REFERENCES public.offices(id) ON DELETE RESTRICT;


--
-- Name: staff fk_staff_office; Type: FK CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT fk_staff_office FOREIGN KEY (office_id) REFERENCES public.offices(id) ON DELETE SET NULL;


--
-- Name: ticket_counters fk_ticket_counters_office; Type: FK CONSTRAINT; Schema: public; Owner: haron
--

ALTER TABLE ONLY public.ticket_counters
    ADD CONSTRAINT fk_ticket_counters_office FOREIGN KEY (office_id) REFERENCES public.offices(id) ON DELETE CASCADE;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO dqms_app;


--
-- Name: FUNCTION fn_audit_log(); Type: ACL; Schema: public; Owner: haron
--

GRANT ALL ON FUNCTION public.fn_audit_log() TO dqms_app;


--
-- Name: FUNCTION fn_calc_ticket_times(); Type: ACL; Schema: public; Owner: haron
--

GRANT ALL ON FUNCTION public.fn_calc_ticket_times() TO dqms_app;


--
-- Name: FUNCTION fn_get_next_ticket_number(p_office_id uuid); Type: ACL; Schema: public; Owner: haron
--

GRANT ALL ON FUNCTION public.fn_get_next_ticket_number(p_office_id uuid) TO dqms_app;


--
-- Name: FUNCTION fn_notify_current_serving(); Type: ACL; Schema: public; Owner: haron
--

GRANT ALL ON FUNCTION public.fn_notify_current_serving() TO dqms_app;


--
-- Name: FUNCTION fn_notify_office_change(); Type: ACL; Schema: public; Owner: haron
--

GRANT ALL ON FUNCTION public.fn_notify_office_change() TO dqms_app;


--
-- Name: FUNCTION fn_notify_queue_update(); Type: ACL; Schema: public; Owner: haron
--

GRANT ALL ON FUNCTION public.fn_notify_queue_update() TO dqms_app;


--
-- Name: FUNCTION fn_set_updated_at(); Type: ACL; Schema: public; Owner: haron
--

GRANT ALL ON FUNCTION public.fn_set_updated_at() TO dqms_app;


--
-- Name: FUNCTION fn_staff_login(p_username text, p_password text); Type: ACL; Schema: public; Owner: haron
--

GRANT ALL ON FUNCTION public.fn_staff_login(p_username text, p_password text) TO dqms_app;


--
-- Name: PROCEDURE sp_call_next(IN p_office_id uuid, OUT p_ticket_id uuid, OUT p_ticket_number integer, OUT p_found boolean); Type: ACL; Schema: public; Owner: haron
--

GRANT ALL ON PROCEDURE public.sp_call_next(IN p_office_id uuid, OUT p_ticket_id uuid, OUT p_ticket_number integer, OUT p_found boolean) TO dqms_app;


--
-- Name: PROCEDURE sp_mark_served(IN p_ticket_number integer, IN p_office_id uuid, IN p_elapsed_seconds integer); Type: ACL; Schema: public; Owner: haron
--

GRANT ALL ON PROCEDURE public.sp_mark_served(IN p_ticket_number integer, IN p_office_id uuid, IN p_elapsed_seconds integer) TO dqms_app;


--
-- Name: PROCEDURE sp_register_ticket(IN p_office_id uuid, IN p_issued_at timestamp with time zone, OUT p_ticket_id uuid, OUT p_ticket_number integer); Type: ACL; Schema: public; Owner: haron
--

GRANT ALL ON PROCEDURE public.sp_register_ticket(IN p_office_id uuid, IN p_issued_at timestamp with time zone, OUT p_ticket_id uuid, OUT p_ticket_number integer) TO dqms_app;


--
-- Name: PROCEDURE sp_skip_ticket(IN p_ticket_number integer, IN p_office_id uuid, OUT p_next_ticket_number integer, OUT p_next_ticket_id uuid); Type: ACL; Schema: public; Owner: haron
--

GRANT ALL ON PROCEDURE public.sp_skip_ticket(IN p_ticket_number integer, IN p_office_id uuid, OUT p_next_ticket_number integer, OUT p_next_ticket_id uuid) TO dqms_app;


--
-- Name: TABLE admin_users; Type: ACL; Schema: public; Owner: haron
--

GRANT SELECT ON TABLE public.admin_users TO dqms_app;


--
-- Name: COLUMN admin_users.password_hash; Type: ACL; Schema: public; Owner: haron
--

GRANT UPDATE(password_hash) ON TABLE public.admin_users TO dqms_app;


--
-- Name: COLUMN admin_users.last_login_at; Type: ACL; Schema: public; Owner: haron
--

GRANT UPDATE(last_login_at) ON TABLE public.admin_users TO dqms_app;


--
-- Name: TABLE audit_log; Type: ACL; Schema: public; Owner: haron
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.audit_log TO dqms_app;


--
-- Name: SEQUENCE audit_log_id_seq; Type: ACL; Schema: public; Owner: haron
--

GRANT SELECT,USAGE ON SEQUENCE public.audit_log_id_seq TO dqms_app;


--
-- Name: TABLE current_serving; Type: ACL; Schema: public; Owner: haron
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.current_serving TO dqms_app;


--
-- Name: TABLE elapsed_log; Type: ACL; Schema: public; Owner: haron
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.elapsed_log TO dqms_app;


--
-- Name: TABLE offices; Type: ACL; Schema: public; Owner: haron
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.offices TO dqms_app;


--
-- Name: TABLE queue_tickets; Type: ACL; Schema: public; Owner: haron
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.queue_tickets TO dqms_app;


--
-- Name: TABLE staff; Type: ACL; Schema: public; Owner: haron
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.staff TO dqms_app;


--
-- Name: TABLE ticket_counters; Type: ACL; Schema: public; Owner: haron
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.ticket_counters TO dqms_app;


--
-- PostgreSQL database dump complete
--

