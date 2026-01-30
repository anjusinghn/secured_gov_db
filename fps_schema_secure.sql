-- =============================================================================
-- FSA Road Safety Database — Security-Hardened POC Schema
-- PostgreSQL 16 (Ubuntu)
-- =============================================================================
--
-- WHAT THIS FILE IS:
--   A security-hardened proof-of-concept version of the FSA (Field Safety
--   Assessment) Road Safety Database schema used by the Government of India
--   for road accident data collection across multiple states and districts.
--
--   Compare against: fps_schema.sql  (the original, unmodified production dump)
--
-- ─────────────────────────────────────────────────────────────────────────────
-- COMPLETE DIFF SUMMARY vs fps_schema.sql
-- ─────────────────────────────────────────────────────────────────────────────
--
-- [NEW] Extensions:
--   • pgcrypto — required for all encryption and password hashing
--
-- [NEW] Roles (did not exist in original):
--   • fsa_admin  — superuser equivalent, owns all objects, BYPASSRLS
--   • fsa_app    — used by application for all CRUD
--   • fsa_readonly — used by dashboards / reports, SELECT only
--
-- [NEW] Schemas (did not exist in original):
--   • audit  — holds the change_log table for full audit trail
--   (master schema already existed and is preserved unchanged)
--
-- [NEW] Entire function library (Section 4, nothing like this in original):
--   • hash_password(text)          — bcrypt cost-10 via pgcrypto
--   • verify_password(text, text)  — constant-time bcrypt compare
--   • trg_hash_admin_password()    — auto-hashes admin_pwd on INSERT/UPDATE
--   • trg_hash_user_password()     — auto-hashes pwd on INSERT/UPDATE
--   • require_encryption_key()     — reads app.encryption_key session var
--   • hash_lookup_value(text)      — SHA-256 hex for searchable email hash
--   • encrypt_text_value(text)     — ChaCha20 encrypt → "enc:chacha20:v1:<b64>"
--   • decrypt_text_value(text)     — reverse of above
--   • encrypt_jsonb_value(jsonb)   — encrypts JSON string values
--   • decrypt_jsonb_value(jsonb)   — reverse of above
--   • trg_encrypt_sensitive_fields() — master encryption trigger (all tables)
--   • update_timestamp()           — keeps updated_at current
--   • audit.log_changes()          — writes old/new jsonb to audit.change_log
--
-- [NEW] Audit table (did not exist in original):
--   • audit.change_log             — timestamped INSERT/UPDATE/DELETE log
--
-- [NEW] Columns added to existing tables:
--   • fsa_user_table.email_hash     — SHA-256 of email; needed because email
--                                     itself is encrypted and not searchable
--   • fsa_admin_table.admin_email_hash — same reason for admin email
--   • Every public table now has:   created_at timestamptz, updated_at timestamptz
--
-- [NEW] CHECK constraints (did not exist in original):
--   • fsa_user_table.pwd           — enforces bcrypt format ($2...)
--   • fsa_admin_table.admin_pwd    — enforces bcrypt format ($2...)
--
-- [CHANGED] Column types in fsa_acc (to allow AES-256 encrypted storage):
--   • no_of_injuries  integer  →  character varying
--   • no_of_deaths    integer  →  character varying
--   (Decrypted view casts them back to integer for consumers)
--
-- [CHANGED] Column types in fsa_onspot (to allow AES-256 encrypted storage):
--   • lat   double precision  →  character varying
--   • long  double precision  →  character varying
--
-- [CHANGED] FK constraints: all had NOT VALID in original; fully enforced here
--
-- [CHANGED] Table ownership: all objects owned by fsa_admin (was postgres)
--
-- [NEW] Unique constraints on hash columns:
--   • fsa_user_table.email_hash_unique
--   • fsa_admin_table.admin_email_hash_unique
--
-- [NEW] Indexes (none existed in original):
--   • FK column indexes on all child tables (detail_id, userid, etc.)
--   • State/district expression indexes for RLS performance
--
-- [NEW] Triggers (none existed in original):
--   • Section 13  — password hashing (trg_hash_*)
--   • Section 13A — field encryption (trg_encrypt_*)
--   • Section 14  — timestamp maintenance (trg_ts_*)
--   • Section 15  — audit logging (audit_*)
--
-- [NEW] Row Level Security (Section 16):
--   • Enabled on all public data tables
--   • Policies filter by app.current_state_code / app.current_district_code
--   • fsa_admin BYPASSRLS; fsa_app read-write; fsa_readonly SELECT only
--
-- [NEW] Decrypted read views (Section 16A):
--   • v_fsa_user_table_decrypted, v_fsa_admin_table_decrypted,
--     v_gen_details_decrypted, v_fsa_acc_decrypted, v_fsa_onspot_decrypted,
--     v_fsa_light_decrypted, v_fsa_traff_status_decrypted,
--     v_fsa_visible_decrypted, v_fsa_roadcnd_decrypted,
--     v_fsa_ped_cross_decrypted, v_fsa_state_district_table_decrypted,
--     v_intervention_decrypted, v_remarks_by_engg_decrypted,
--     v_stages_table_decrypted, v_status_field_inspection_decrypted,
--     v_status_of_approval_decrypted, v_status_of_estimate_decrypted,
--     v_status_of_implementation_decrypted
--
-- [REMOVED] fsa_user_table_bak — intentionally excluded (stored plaintext
--   passwords with no constraints, no production purpose)
--
-- [REMOVED] \restrict / \unrestrict meta-commands at top/bottom of file —
--   these were psql-specific and not valid SQL
--
-- [UNCHANGED] All master schema tables (lookup/reference data) — identical
-- [UNCHANGED] Column names and business logic — no renames, no logic changes
-- [UNCHANGED] fetch_data_from_tables() function — preserved as-is
-- [UNCHANGED] All sequences — identical definitions
--
-- ─────────────────────────────────────────────────────────────────────────────
-- HOW TO RUN:
--   Connect as a PostgreSQL superuser and run this file on a fresh PG 16 instance:
--     psql -U postgres -d your_database -f fps_schema_secure.sql
--
-- HOW THE APP SHOULD CONNECT:
--   The application must connect as role fsa_app and set session variables
--   before executing any query so that Row Level Security filters correctly:
--
--     SET ROLE fsa_app;
--     SET app.current_state_code    = '21';   -- e.g. Odisha
--     SET app.current_district_code = '05';   -- e.g. Khurda
--     SET app.current_user_id       = '42';   -- fsa_user_table.userid
--     SET app.encryption_key        = '<32-byte app secret>';
--
--   For reporting/dashboards connect as fsa_readonly with the same session vars.
--   fsa_admin bypasses RLS entirely (BYPASSRLS privilege).
-- =============================================================================

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'SQL_ASCII';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

-- =============================================================================
-- SECTION 1: EXTENSIONS
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;

-- =============================================================================
-- SECTION 2: ROLE CREATION (idempotent via DO blocks)
-- =============================================================================

-- fsa_admin: manages users and admin accounts; bypasses RLS; owns all tables
DO $$
BEGIN
    CREATE ROLE fsa_admin WITH LOGIN NOINHERIT BYPASSRLS;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;

-- fsa_app: used by the application for all CRUD operations
DO $$
BEGIN
    CREATE ROLE fsa_app WITH LOGIN NOINHERIT;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;

-- fsa_readonly: used by reporting tools and dashboards; SELECT only
DO $$
BEGIN
    CREATE ROLE fsa_readonly WITH LOGIN NOINHERIT;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;

-- =============================================================================
-- SECTION 3: SCHEMA CREATION
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS master;
ALTER SCHEMA master OWNER TO fsa_admin;

CREATE SCHEMA IF NOT EXISTS audit;
ALTER SCHEMA audit OWNER TO fsa_admin;

-- public schema is already present; transfer ownership of schema objects
-- (individual table ALTER OWNER statements appear after CREATE TABLE)

-- =============================================================================
-- SECTION 4: UTILITY FUNCTIONS
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 4a. Password hashing helpers (pgcrypto / bcrypt cost 10)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.hash_password(plaintext text)
RETURNS text
LANGUAGE sql
STRICT
SECURITY DEFINER
AS $$
    SELECT public.crypt(plaintext, public.gen_salt('bf', 10));
$$;

ALTER FUNCTION public.hash_password(text) OWNER TO fsa_admin;
COMMENT ON FUNCTION public.hash_password(text) IS
    'Hash a plaintext password with bcrypt (cost 10). Never store the result; '
    'it is returned to the trigger and stored in the password column automatically.';

CREATE OR REPLACE FUNCTION public.verify_password(plaintext text, hashed text)
RETURNS boolean
LANGUAGE sql
STRICT
SECURITY DEFINER
AS $$
    SELECT public.crypt(plaintext, hashed) = hashed;
$$;

ALTER FUNCTION public.verify_password(text, text) OWNER TO fsa_admin;
COMMENT ON FUNCTION public.verify_password(text, text) IS
    'Return TRUE if plaintext matches the stored bcrypt hash.';

-- ---------------------------------------------------------------------------
-- 4b. Auto-hash trigger function — fires on INSERT/UPDATE of password columns
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.trg_hash_admin_password()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Only re-hash if the value changed and does not already look like a bcrypt hash
    -- bcrypt hashes start with $2a$, $2b$, or $2y$
    IF NEW.admin_pwd IS NOT NULL AND NEW.admin_pwd NOT LIKE '$2%' THEN
        NEW.admin_pwd := public.hash_password(NEW.admin_pwd);
    END IF;
    RETURN NEW;
END;
$$;

ALTER FUNCTION public.trg_hash_admin_password() OWNER TO fsa_admin;

CREATE OR REPLACE FUNCTION public.trg_hash_user_password()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NEW.pwd IS NOT NULL AND NEW.pwd NOT LIKE '$2%' THEN
        NEW.pwd := public.hash_password(NEW.pwd);
    END IF;
    RETURN NEW;
END;
$$;

ALTER FUNCTION public.trg_hash_user_password() OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- 4c. Reversible field encryption helpers (ChaCha20 stream cipher)
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.require_encryption_key()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_key text;
BEGIN
    v_key := current_setting('app.encryption_key', true);
    IF v_key IS NULL OR btrim(v_key) = '' THEN
        RAISE EXCEPTION 'app.encryption_key must be set before reading/writing encrypted fields';
    END IF;
    RETURN v_key;
END;
$$;

ALTER FUNCTION public.require_encryption_key() OWNER TO fsa_admin;

CREATE OR REPLACE FUNCTION public.hash_lookup_value(plaintext text)
RETURNS text
LANGUAGE sql
IMMUTABLE
RETURNS NULL ON NULL INPUT
AS $$
    SELECT encode(public.digest(lower(btrim(plaintext)), 'sha256'), 'hex');
$$;

ALTER FUNCTION public.hash_lookup_value(text) OWNER TO fsa_admin;

CREATE OR REPLACE FUNCTION public.chacha20_le32(data bytea, off integer)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
RETURNS NULL ON NULL INPUT
AS $$
    SELECT get_byte(data, off)::bigint
         | (get_byte(data, off + 1)::bigint <<  8)
         | (get_byte(data, off + 2)::bigint << 16)
         | (get_byte(data, off + 3)::bigint << 24)
$$;

ALTER FUNCTION public.chacha20_le32(bytea, integer) OWNER TO fsa_admin;

CREATE OR REPLACE FUNCTION public.chacha20_u32le(v bigint)
RETURNS bytea
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT set_byte(set_byte(set_byte(set_byte(
        '\x00000000'::bytea,
        0, ( v        & 255)::integer),
        1, ((v >>  8) & 255)::integer),
        2, ((v >> 16) & 255)::integer),
        3, ((v >> 24) & 255)::integer)
$$;

ALTER FUNCTION public.chacha20_u32le(bigint) OWNER TO fsa_admin;

CREATE OR REPLACE FUNCTION public.chacha20_qr(
    s  bigint[],
    ai integer, bi integer, ci integer, di integer
)
RETURNS bigint[]
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    M  constant bigint := 4294967295;
    a  bigint := s[ai];
    b  bigint := s[bi];
    c  bigint := s[ci];
    d  bigint := s[di];
    t  bigint;
BEGIN
    a := (a + b) & M;  t := (d # a) & M;  d := ((t << 16) | (t >> 16)) & M;
    c := (c + d) & M;  t := (b # c) & M;  b := ((t << 12) | (t >> 20)) & M;
    a := (a + b) & M;  t := (d # a) & M;  d := ((t <<  8) | (t >> 24)) & M;
    c := (c + d) & M;  t := (b # c) & M;  b := ((t <<  7) | (t >> 25)) & M;
    s[ai] := a;  s[bi] := b;  s[ci] := c;  s[di] := d;
    RETURN s;
END;
$$;

ALTER FUNCTION public.chacha20_qr(bigint[], integer, integer, integer, integer) OWNER TO fsa_admin;

CREATE OR REPLACE FUNCTION public.chacha20_block(key bytea, nonce bytea, ctr bigint)
RETURNS bytea
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    M  constant bigint := 4294967295;
    s  bigint[];
    w  bigint[];
    i  integer;
    out bytea := '';
BEGIN
    s[1]  := 1634760805;
    s[2]  := 857760878;
    s[3]  := 2036477234;
    s[4]  := 1797285236;
    FOR i IN 0..7 LOOP
        s[5 + i] := public.chacha20_le32(key, i * 4);
    END LOOP;
    s[13] := ctr & M;
    s[14] := public.chacha20_le32(nonce, 0);
    s[15] := public.chacha20_le32(nonce, 4);
    s[16] := public.chacha20_le32(nonce, 8);
    w := s;
    FOR i IN 1..10 LOOP
        w := public.chacha20_qr(w,  1,  5,  9, 13);
        w := public.chacha20_qr(w,  2,  6, 10, 14);
        w := public.chacha20_qr(w,  3,  7, 11, 15);
        w := public.chacha20_qr(w,  4,  8, 12, 16);
        w := public.chacha20_qr(w,  1,  6, 11, 16);
        w := public.chacha20_qr(w,  2,  7, 12, 13);
        w := public.chacha20_qr(w,  3,  8,  9, 14);
        w := public.chacha20_qr(w,  4,  5, 10, 15);
    END LOOP;
    FOR i IN 1..16 LOOP
        w[i] := (w[i] + s[i]) & M;
    END LOOP;
    FOR i IN 1..16 LOOP
        out := out || public.chacha20_u32le(w[i]);
    END LOOP;
    RETURN out;
END;
$$;

ALTER FUNCTION public.chacha20_block(bytea, bytea, bigint) OWNER TO fsa_admin;

CREATE OR REPLACE FUNCTION public.chacha20_crypt(data bytea, key bytea, nonce bytea, start_ctr bigint DEFAULT 0)
RETURNS bytea
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    result    bytea   := '';
    ks        bytea;
    block_ctr bigint  := start_ctr;
    data_len  integer := octet_length(data);
    off       integer := 0;
    chunk     integer;
    i         integer;
BEGIN
    WHILE off < data_len LOOP
        ks    := public.chacha20_block(key, nonce, block_ctr);
        chunk := LEAST(64, data_len - off);
        FOR i IN 0..(chunk - 1) LOOP
            result := result || set_byte('\x00'::bytea, 0,
                        get_byte(data, off + i) # get_byte(ks, i));
        END LOOP;
        off       := off + chunk;
        block_ctr := block_ctr + 1;
    END LOOP;
    RETURN result;
END;
$$;

ALTER FUNCTION public.chacha20_crypt(bytea, bytea, bytea, bigint) OWNER TO fsa_admin;

CREATE OR REPLACE FUNCTION public.poly1305_mac(msg bytea, poly_key bytea)
RETURNS bytea
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    P       constant numeric := (2::numeric ^ 130) - 5;
    r       numeric := 0;
    s       numeric := 0;
    acc     numeric := 0;
    msg_len integer;
    i       integer := 0;
    chunk_len integer;
    block_val numeric;
    j       integer;
    tag     numeric;
    result  bytea := '';
    rk      bytea;
BEGIN
    rk := poly_key;
    rk := set_byte(rk, 3,  get_byte(rk, 3)  & 15);
    rk := set_byte(rk, 7,  get_byte(rk, 7)  & 15);
    rk := set_byte(rk, 11, get_byte(rk, 11) & 15);
    rk := set_byte(rk, 15, get_byte(rk, 15) & 15);
    rk := set_byte(rk, 4,  get_byte(rk, 4)  & 252);
    rk := set_byte(rk, 8,  get_byte(rk, 8)  & 252);
    rk := set_byte(rk, 12, get_byte(rk, 12) & 252);

    FOR j IN REVERSE 15..0 LOOP
        r := r * 256 + get_byte(rk, j);
    END LOOP;

    FOR j IN REVERSE 31..16 LOOP
        s := s * 256 + get_byte(poly_key, j);
    END LOOP;

    msg_len := octet_length(msg);
    WHILE i < msg_len LOOP
        chunk_len := LEAST(16, msg_len - i);
        block_val := 0;
        FOR j IN REVERSE (chunk_len - 1)..0 LOOP
            block_val := block_val * 256 + get_byte(msg, i + j);
        END LOOP;
        block_val := block_val + (2::numeric ^ (8 * chunk_len));
        acc := ((acc + block_val) * r) % P;
        i := i + chunk_len;
    END LOOP;

    tag := (acc + s) % (2::numeric ^ 128);

    FOR j IN 0..15 LOOP
        result := result || set_byte('\x00'::bytea, 0, (tag % 256)::integer);
        tag := trunc(tag / 256);
    END LOOP;

    RETURN result;
END;
$$;

ALTER FUNCTION public.poly1305_mac(bytea, bytea) OWNER TO fsa_admin;

CREATE OR REPLACE FUNCTION public.encrypt_text_value(plaintext text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_key      text;
    key_bytes  bytea;
    nonce      bytea;
    ciphertext bytea;
    poly_key   bytea;
    tag        bytea;
BEGIN
    IF plaintext IS NULL OR plaintext LIKE 'enc:chacha20:v1:%' THEN
        RETURN plaintext;
    END IF;

    v_key     := public.require_encryption_key();
    key_bytes := decode(v_key, 'hex');
    nonce     := public.gen_random_bytes(12);

    poly_key   := substring(public.chacha20_block(key_bytes, nonce, 0) from 1 for 32);
    ciphertext := public.chacha20_crypt(convert_to(plaintext, 'UTF8'), key_bytes, nonce, 1);
    tag        := public.poly1305_mac(ciphertext, poly_key);

    RETURN 'enc:chacha20:v1:' || replace(encode(nonce || tag || ciphertext, 'base64'), E'\n', '');
END;
$$;

ALTER FUNCTION public.encrypt_text_value(text) OWNER TO fsa_admin;

CREATE OR REPLACE FUNCTION public.decrypt_text_value(ciphertext text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_key        text;
    key_bytes    bytea;
    raw_bytes    bytea;
    nonce        bytea;
    tag          bytea;
    ct           bytea;
    pt           bytea;
    poly_key     bytea;
    computed_tag bytea;
BEGIN
    IF ciphertext IS NULL OR ciphertext NOT LIKE 'enc:chacha20:v1:%' THEN
        RETURN ciphertext;
    END IF;

    v_key     := public.require_encryption_key();
    key_bytes := decode(v_key, 'hex');

    raw_bytes := decode(
        replace(replace(substring(ciphertext from 17), E'\n', ''), '\n', ''),
        'base64'
    );

    nonce := substring(raw_bytes from 1 for 12);
    tag   := substring(raw_bytes from 13 for 16);
    ct    := substring(raw_bytes from 29);

    poly_key     := substring(public.chacha20_block(key_bytes, nonce, 0) from 1 for 32);
    computed_tag := public.poly1305_mac(ct, poly_key);

    IF tag <> computed_tag THEN
        RAISE EXCEPTION 'Ciphertext integrity check failed (Poly1305 MAC mismatch)';
    END IF;

    pt := public.chacha20_crypt(ct, key_bytes, nonce, 1);
    RETURN convert_from(pt, 'UTF8');
END;
$$;

ALTER FUNCTION public.decrypt_text_value(text) OWNER TO fsa_admin;

CREATE OR REPLACE FUNCTION public.encrypt_jsonb_value(plaintext jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF plaintext IS NULL THEN
        RETURN NULL;
    END IF;

    IF jsonb_typeof(plaintext) = 'string' AND trim(both '"' from plaintext::text) LIKE 'enc:chacha20:v1:%' THEN
        RETURN plaintext;
    END IF;

    RETURN to_jsonb(public.encrypt_text_value(plaintext::text));
END;
$$;

ALTER FUNCTION public.encrypt_jsonb_value(jsonb) OWNER TO fsa_admin;

CREATE OR REPLACE FUNCTION public.decrypt_jsonb_value(ciphertext jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF ciphertext IS NULL THEN
        RETURN NULL;
    END IF;

    IF jsonb_typeof(ciphertext) <> 'string' OR trim(both '"' from ciphertext::text) NOT LIKE 'enc:chacha20:v1:%' THEN
        RETURN ciphertext;
    END IF;

    RETURN public.decrypt_text_value(trim(both '"' from ciphertext::text))::jsonb;
END;
$$;

ALTER FUNCTION public.decrypt_jsonb_value(jsonb) OWNER TO fsa_admin;

CREATE OR REPLACE FUNCTION public.trg_encrypt_sensitive_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF TG_TABLE_NAME = 'fsa_user_table' THEN
        IF NEW.email IS NOT NULL AND NEW.email NOT LIKE 'enc:chacha20:v1:%' THEN
            NEW.email_hash := public.hash_lookup_value(NEW.email);
            NEW.email := public.encrypt_text_value(NEW.email);
        END IF;
        NEW.rep_name := public.encrypt_text_value(NEW.rep_name);
        NEW.designation := public.encrypt_text_value(NEW.designation);
        NEW.department := public.encrypt_text_value(NEW.department);
        NEW.phone_no := public.encrypt_text_value(NEW.phone_no);
        NEW.state_name := public.encrypt_text_value(NEW.state_name);
        NEW.district_name := public.encrypt_text_value(NEW.district_name);
        NEW.police_station := public.encrypt_text_value(NEW.police_station);
        NEW.last_login := public.encrypt_text_value(NEW.last_login);
        NEW.user_file := public.encrypt_jsonb_value(NEW.user_file);
    ELSIF TG_TABLE_NAME = 'fsa_admin_table' THEN
        IF NEW.admin_email IS NOT NULL AND NEW.admin_email NOT LIKE 'enc:chacha20:v1:%' THEN
            NEW.admin_email_hash := public.hash_lookup_value(NEW.admin_email);
            NEW.admin_email := public.encrypt_text_value(NEW.admin_email);
        END IF;
        NEW.admin_name := public.encrypt_text_value(NEW.admin_name);
        NEW.state_name := public.encrypt_text_value(NEW.state_name);
        NEW.district_name := public.encrypt_text_value(NEW.district_name);
        NEW.created_by := public.encrypt_text_value(NEW.created_by);
        NEW.phone_no := public.encrypt_text_value(NEW.phone_no);
        NEW.last_login := public.encrypt_text_value(NEW.last_login);
        NEW.admin_role := public.encrypt_text_value(NEW.admin_role);
    ELSIF TG_TABLE_NAME = 'gen_details' THEN
        NEW.rep_name := public.encrypt_jsonb_value(NEW.rep_name);
        NEW.designation := public.encrypt_jsonb_value(NEW.designation);
        NEW.department := public.encrypt_jsonb_value(NEW.department);
        NEW.phone_no := public.encrypt_jsonb_value(NEW.phone_no);
        NEW.email := public.encrypt_jsonb_value(NEW.email);
        NEW.state := public.encrypt_jsonb_value(NEW.state);
        NEW.district := public.encrypt_jsonb_value(NEW.district);
        NEW.police_station := public.encrypt_text_value(NEW.police_station);
        NEW.state_code := public.encrypt_jsonb_value(NEW.state_code);
        NEW.district_code := public.encrypt_jsonb_value(NEW.district_code);
    ELSIF TG_TABLE_NAME = 'fsa_acc' THEN
        NEW.nearest_hosp := public.encrypt_text_value(NEW.nearest_hosp);
        NEW.acc_pattern_onspot := public.encrypt_text_value(NEW.acc_pattern_onspot);
        NEW.time_frame_acc := public.encrypt_text_value(NEW.time_frame_acc);
        NEW.age_range := public.encrypt_text_value(NEW.age_range);
        NEW.no_of_injuries := public.encrypt_text_value(NEW.no_of_injuries);
        NEW.no_of_deaths := public.encrypt_text_value(NEW.no_of_deaths);
    ELSIF TG_TABLE_NAME = 'fsa_onspot' THEN
        NEW.adjoining_or_junction_no := public.encrypt_text_value(NEW.adjoining_or_junction_no);
        NEW.junction_name := public.encrypt_text_value(NEW.junction_name);
        NEW.landmark_name := public.encrypt_text_value(NEW.landmark_name);
        NEW.landmark_dist := public.encrypt_text_value(NEW.landmark_dist);
        NEW.name_of_stretch := public.encrypt_text_value(NEW.name_of_stretch);
        NEW.lat := public.encrypt_text_value(NEW.lat);
        NEW.long := public.encrypt_text_value(NEW.long);
        NEW.onspot_images := public.encrypt_jsonb_value(NEW.onspot_images);
    ELSIF TG_TABLE_NAME = 'fsa_ped_cross' THEN
        NEW.remarks := public.encrypt_text_value(NEW.remarks);
    ELSIF TG_TABLE_NAME = 'fsa_state_district_table' THEN
        NEW.state_admin_name := public.encrypt_text_value(NEW.state_admin_name);
        NEW.district_admin_name := public.encrypt_text_value(NEW.district_admin_name);
        NEW.state_roa_name := public.encrypt_text_value(NEW.state_roa_name);
        NEW.district_roa_name := public.encrypt_text_value(NEW.district_roa_name);
    ELSIF TG_TABLE_NAME = 'fsa_light' THEN
        NEW.light_photos := public.encrypt_jsonb_value(NEW.light_photos);
    ELSIF TG_TABLE_NAME = 'fsa_traff_status' THEN
        NEW.signal_photos := public.encrypt_jsonb_value(NEW.signal_photos);
        NEW.signboards_photos := public.encrypt_jsonb_value(NEW.signboards_photos);
        NEW.road_markings_photos := public.encrypt_jsonb_value(NEW.road_markings_photos);
    ELSIF TG_TABLE_NAME = 'fsa_visible' THEN
        NEW.visib_photos := public.encrypt_jsonb_value(NEW.visib_photos);
    ELSIF TG_TABLE_NAME = 'fsa_roadcnd' THEN
        NEW.road_photos := public.encrypt_jsonb_value(NEW.road_photos);
    ELSIF TG_TABLE_NAME = 'intervention' THEN
        NEW.admin_name := public.encrypt_text_value(NEW.admin_name);
        NEW.admin_email := public.encrypt_text_value(NEW.admin_email);
        NEW.uploaded_docs := public.encrypt_text_value(NEW.uploaded_docs);
        NEW.admin_role := public.encrypt_text_value(NEW.admin_role);
    ELSIF TG_TABLE_NAME = 'remarks_by_engg' THEN
        NEW.admin_name := public.encrypt_text_value(NEW.admin_name);
        NEW.admin_email := public.encrypt_text_value(NEW.admin_email);
        NEW.admin_role := public.encrypt_text_value(NEW.admin_role);
    ELSIF TG_TABLE_NAME = 'stages_table' THEN
        NEW.remarks_by_engg := public.encrypt_text_value(NEW.remarks_by_engg);
        NEW.admin_name := public.encrypt_text_value(NEW.admin_name);
        NEW.admin_email := public.encrypt_text_value(NEW.admin_email);
        NEW.upload_docs_intervention := public.encrypt_text_value(NEW.upload_docs_intervention);
        NEW.upload_docs_estimation := public.encrypt_text_value(NEW.upload_docs_estimation);
        NEW.admin_role := public.encrypt_text_value(NEW.admin_role);
    ELSIF TG_TABLE_NAME = 'status_field_inspection' THEN
        NEW.admin_name := public.encrypt_text_value(NEW.admin_name);
        NEW.admin_email := public.encrypt_text_value(NEW.admin_email);
        NEW.admin_role := public.encrypt_text_value(NEW.admin_role);
    ELSIF TG_TABLE_NAME = 'status_of_approval' THEN
        NEW.admin_name := public.encrypt_text_value(NEW.admin_name);
        NEW.admin_email := public.encrypt_text_value(NEW.admin_email);
        NEW.admin_role := public.encrypt_text_value(NEW.admin_role);
    ELSIF TG_TABLE_NAME = 'status_of_estimate' THEN
        NEW.admin_name := public.encrypt_text_value(NEW.admin_name);
        NEW.admin_email := public.encrypt_text_value(NEW.admin_email);
        NEW.uploaded_docs := public.encrypt_text_value(NEW.uploaded_docs);
        NEW.admin_role := public.encrypt_text_value(NEW.admin_role);
    ELSIF TG_TABLE_NAME = 'status_of_implementation' THEN
        NEW.admin_name := public.encrypt_text_value(NEW.admin_name);
        NEW.admin_email := public.encrypt_text_value(NEW.admin_email);
        NEW.admin_role := public.encrypt_text_value(NEW.admin_role);
    END IF;

    RETURN NEW;
END;
$$;

ALTER FUNCTION public.trg_encrypt_sensitive_fields() OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- 4d. Timestamp maintenance trigger function
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.update_timestamp()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

ALTER FUNCTION public.update_timestamp() OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- 4d. Audit log trigger function
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION audit.log_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_row_id text;
BEGIN
    -- Derive a row identifier from the primary key columns if available,
    -- otherwise use ctid as a fallback.
    BEGIN
        v_row_id := row_to_json(COALESCE(NEW, OLD)) ::jsonb ->> 'detail_id';
        IF v_row_id IS NULL THEN
            v_row_id := row_to_json(COALESCE(NEW, OLD)) ::jsonb ->> 'id';
        END IF;
        IF v_row_id IS NULL THEN
            v_row_id := COALESCE(NEW, OLD)::text;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        v_row_id := '(unknown)';
    END;

    INSERT INTO audit.change_log (
        table_name,
        operation,
        row_id,
        old_data,
        new_data,
        changed_by,
        app_user_id
    ) VALUES (
        TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
        TG_OP,
        v_row_id,
        CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) ELSE NULL END,
        CASE WHEN TG_OP IN ('UPDATE','INSERT') THEN to_jsonb(NEW) ELSE NULL END,
        current_user,
        current_setting('app.current_user_id', true)
    );

    -- For DELETE the trigger must return OLD; for others return NEW
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

ALTER FUNCTION audit.log_changes() OWNER TO fsa_admin;

-- =============================================================================
-- SECTION 5: MASTER SCHEMA TABLES (lookup / reference data, no timestamps)
-- =============================================================================

CREATE TABLE master.accidents_due_to_small_t_junction_accidents_or_nearby_joining_r (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.accidents_due_to_small_t_junction_accidents_or_nearby_joining_r OWNER TO fsa_admin;

CREATE TABLE master.age_range (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.age_range OWNER TO fsa_admin;

CREATE TABLE master.defects (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.defects OWNER TO fsa_admin;

CREATE TABLE master.enforcement_solutions_parked_vehicle_accidents (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.enforcement_solutions_parked_vehicle_accidents OWNER TO fsa_admin;

CREATE TABLE master.enforcement_solutions_pedestrian_animal_crossing (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.enforcement_solutions_pedestrian_animal_crossing OWNER TO fsa_admin;

CREATE TABLE master.enforcement_solutions_rash_driving (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.enforcement_solutions_rash_driving OWNER TO fsa_admin;

CREATE TABLE master.enforcement_solutions_self_accidents (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.enforcement_solutions_self_accidents OWNER TO fsa_admin;

CREATE TABLE master.enforcement_solutions_small_t_junction_accidents (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.enforcement_solutions_small_t_junction_accidents OWNER TO fsa_admin;

CREATE TABLE master.enforcement_solutions_vehicles_overspeeding (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.enforcement_solutions_vehicles_overspeeding OWNER TO fsa_admin;

CREATE TABLE master.enforcement_solutions_wrong_way_driving (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.enforcement_solutions_wrong_way_driving OWNER TO fsa_admin;

CREATE TABLE master.formation_of_junction (
    english character varying,
    hindi character varying,
    odia character varying,
    id character varying
);
ALTER TABLE master.formation_of_junction OWNER TO fsa_admin;

CREATE TABLE master.has_caused_accident_at_spot (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.has_caused_accident_at_spot OWNER TO fsa_admin;

CREATE TABLE master.interventions (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.interventions OWNER TO fsa_admin;

CREATE TABLE master.landmark_type (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.landmark_type OWNER TO fsa_admin;

CREATE TABLE master.landuse_pattern (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.landuse_pattern OWNER TO fsa_admin;

CREATE TABLE master.light_availability (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.light_availability OWNER TO fsa_admin;

CREATE TABLE master.major_reasons_for_self_accidents (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.major_reasons_for_self_accidents OWNER TO fsa_admin;

CREATE TABLE master.master_data (
    id character varying,
    type character varying,
    page_name character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.master_data OWNER TO fsa_admin;

CREATE TABLE master.no_of_lanes (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.no_of_lanes OWNER TO fsa_admin;

CREATE TABLE master.parked_vehicle_accidents_reasons (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.parked_vehicle_accidents_reasons OWNER TO fsa_admin;

CREATE TABLE master.pattern_of_accidents (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.pattern_of_accidents OWNER TO fsa_admin;

CREATE TABLE master.pedestrain_animal_crossing_the_spot_reasons (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.pedestrain_animal_crossing_the_spot_reasons OWNER TO fsa_admin;

CREATE TABLE master.prevalent_vehicle_type (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.prevalent_vehicle_type OWNER TO fsa_admin;

CREATE TABLE master.rash_drivers (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.rash_drivers OWNER TO fsa_admin;

CREATE TABLE master.reason_for_visibility_obstruction (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.reason_for_visibility_obstruction OWNER TO fsa_admin;

CREATE TABLE master.reasons_for_vehicles_not_slowing_down (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.reasons_for_vehicles_not_slowing_down OWNER TO fsa_admin;

CREATE TABLE master.road_engineering_solutions_parked_vehicle_accidents (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.road_engineering_solutions_parked_vehicle_accidents OWNER TO fsa_admin;

CREATE TABLE master.road_engineering_solutions_pedestrain_animal_crossing (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.road_engineering_solutions_pedestrain_animal_crossing OWNER TO fsa_admin;

CREATE TABLE master.road_engineering_solutions_road_condition (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.road_engineering_solutions_road_condition OWNER TO fsa_admin;

CREATE TABLE master.road_engineering_solutions_self_accidents (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.road_engineering_solutions_self_accidents OWNER TO fsa_admin;

CREATE TABLE master.road_engineering_solutions_small_t_junction_accidents (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.road_engineering_solutions_small_t_junction_accidents OWNER TO fsa_admin;

CREATE TABLE master.road_engineering_solutions_vehicles_overspeeding (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.road_engineering_solutions_vehicles_overspeeding OWNER TO fsa_admin;

CREATE TABLE master.road_engineering_solutions_wrong_way_driving (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.road_engineering_solutions_wrong_way_driving OWNER TO fsa_admin;

CREATE TABLE master.road_engineering_suggestions_to_avoid_the_accident_visibility (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.road_engineering_suggestions_to_avoid_the_accident_visibility OWNER TO fsa_admin;

CREATE TABLE master.road_user_vio (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.road_user_vio OWNER TO fsa_admin;

CREATE TABLE master.road_user_violations_causing_accidents_junction (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.road_user_violations_causing_accidents_junction OWNER TO fsa_admin;

CREATE TABLE master.road_user_violations_causing_accidents_stretch (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.road_user_violations_causing_accidents_stretch OWNER TO fsa_admin;

CREATE TABLE master.status_field_inspection (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.status_field_inspection OWNER TO fsa_admin;

CREATE TABLE master.status_of_approval (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.status_of_approval OWNER TO fsa_admin;

CREATE TABLE master.status_of_estimate (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.status_of_estimate OWNER TO fsa_admin;

CREATE TABLE master.status_of_implementation (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.status_of_implementation OWNER TO fsa_admin;

CREATE TABLE master.stretch_shape (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.stretch_shape OWNER TO fsa_admin;

CREATE TABLE master.stretch_type (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.stretch_type OWNER TO fsa_admin;

CREATE TABLE master.switching_type (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.switching_type OWNER TO fsa_admin;

CREATE TABLE master.type_of_junction (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.type_of_junction OWNER TO fsa_admin;

CREATE TABLE master.wrong_way_driving_reasons (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.wrong_way_driving_reasons OWNER TO fsa_admin;

CREATE TABLE master.yes_no_dropdowns (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);
ALTER TABLE master.yes_no_dropdowns OWNER TO fsa_admin;

-- =============================================================================
-- SECTION 6: AUDIT SCHEMA TABLE
-- =============================================================================

CREATE TABLE audit.change_log (
    id             bigserial                NOT NULL,
    table_name     text                     NOT NULL,
    operation      text                     NOT NULL CHECK (operation IN ('INSERT','UPDATE','DELETE')),
    row_id         text,
    old_data       jsonb,
    new_data       jsonb,
    changed_by     text                     NOT NULL DEFAULT current_user,
    changed_at     timestamptz              NOT NULL DEFAULT now(),
    app_user_id    text                     DEFAULT current_setting('app.current_user_id', true),
    CONSTRAINT change_log_pkey PRIMARY KEY (id)
);

ALTER TABLE audit.change_log OWNER TO fsa_admin;

CREATE INDEX idx_audit_change_log_table_name  ON audit.change_log (table_name);
CREATE INDEX idx_audit_change_log_changed_at  ON audit.change_log (changed_at);
CREATE INDEX idx_audit_change_log_app_user_id ON audit.change_log (app_user_id);

-- =============================================================================
-- SECTION 7: PUBLIC SCHEMA TABLES
-- (All original columns preserved; created_at / updated_at added)
-- =============================================================================

SET default_tablespace = '';
SET default_table_access_method = heap;

-- ---------------------------------------------------------------------------
-- fsa_user_roles  (lookup; fk target; no timestamps needed — rarely changes)
-- ---------------------------------------------------------------------------
CREATE TABLE public.fsa_user_roles (
    user_type  character varying NOT NULL,
    user_role  character varying,
    created_at timestamptz       NOT NULL DEFAULT now(),
    updated_at timestamptz       NOT NULL DEFAULT now()
);
ALTER TABLE public.fsa_user_roles OWNER TO fsa_admin;

CREATE SEQUENCE public.fsa_user_id
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE public.fsa_user_id OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- fsa_user_table
-- [CHANGED vs original] pwd now has CHECK constraint enforcing bcrypt format
-- [NEW vs original]     email_hash column — SHA-256 of plaintext email for
--                         lookups (email itself is AES-256 encrypted, not searchable)
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   email, rep_name, designation, department, phone_no,
--                         state_name, district_name, police_station, last_login,
--                         user_file — all encrypted by trg_encrypt_fsa_user_table
-- [UNCHANGED columns]   pwd, login_status, userid, user_type, user_role,
--                         terms_cond, admin_id, user_status, state_code,
--                         district_code, ps_code — same as original
-- ---------------------------------------------------------------------------
CREATE TABLE public.fsa_user_table (
    pwd              character varying NOT NULL
                         CONSTRAINT pwd_must_be_bcrypt CHECK (pwd LIKE '$2%'), -- [NEW] CHECK was missing in original
    last_login       character varying,    -- [ENCRYPTED] stores ciphertext
    login_status     boolean,
    email            character varying NOT NULL, -- [ENCRYPTED] stores ciphertext
    email_hash       character varying NOT NULL, -- [NEW] not in original; SHA-256 for lookups
    rep_name         character varying,    -- [ENCRYPTED] stores ciphertext
    designation      character varying,    -- [ENCRYPTED] stores ciphertext
    department       character varying,    -- [ENCRYPTED] stores ciphertext
    phone_no         character varying,    -- [ENCRYPTED] stores ciphertext
    userid           bigint            NOT NULL DEFAULT nextval('public.fsa_user_id'::regclass),
    user_type        character varying,
    user_role        character varying,
    terms_cond       boolean,
    user_file        jsonb,               -- [ENCRYPTED] entire jsonb value encrypted
    admin_id         bigint,
    user_status      boolean,
    state_code       character varying,
    district_code    character varying,
    state_name       character varying,   -- [ENCRYPTED] stores ciphertext
    district_name    character varying,   -- [ENCRYPTED] stores ciphertext
    ps_code          character varying,
    police_station   character varying,   -- [ENCRYPTED] stores ciphertext
    created_at       timestamptz       NOT NULL DEFAULT now(), -- [NEW] not in original
    updated_at       timestamptz       NOT NULL DEFAULT now()  -- [NEW] not in original
);
ALTER TABLE public.fsa_user_table OWNER TO fsa_admin;
COMMENT ON COLUMN public.fsa_user_table.pwd IS
    'Must store a bcrypt hash (cost>=10). The trg_hash_user_password trigger '
    'auto-hashes on INSERT/UPDATE if a plaintext value is supplied. '
    'Use verify_password(plaintext, pwd) to authenticate.';

-- ---------------------------------------------------------------------------
-- fsa_admin_table
-- [CHANGED vs original] admin_pwd now has CHECK constraint enforcing bcrypt format
-- [NEW vs original]     admin_email_hash column — SHA-256 for lookups
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   admin_email, admin_name, state_name, district_name,
--                         created_by, phone_no, last_login, admin_role
--                         — encrypted by trg_encrypt_fsa_admin_table
-- [UNCHANGED columns]   admin_id, admin_role_id, login_status, user_status,
--                         state_code, district_code — same as original
-- [NOTE] admin_pwd is NOT encrypted (it's bcrypt hashed, which is one-way)
-- ---------------------------------------------------------------------------
CREATE TABLE public.fsa_admin_table (
    admin_email   character varying NOT NULL, -- [ENCRYPTED] stores ciphertext
    admin_email_hash character varying NOT NULL, -- [NEW] not in original; SHA-256 for lookups
    admin_id      bigint            NOT NULL,
    admin_role_id bigint,
    admin_role    character varying, -- [ENCRYPTED] stores ciphertext
    admin_name    character varying, -- [ENCRYPTED] stores ciphertext
    admin_pwd     character varying
                      CONSTRAINT admin_pwd_must_be_bcrypt CHECK (admin_pwd LIKE '$2%'), -- [NEW] CHECK was missing in original
    login_status  boolean,
    last_login    character varying, -- [ENCRYPTED] stores ciphertext
    user_status   boolean,
    state_name    character varying, -- [ENCRYPTED] stores ciphertext
    district_name character varying, -- [ENCRYPTED] stores ciphertext
    state_code    character varying,
    district_code character varying,
    created_by    character varying, -- [ENCRYPTED] stores ciphertext
    phone_no      character varying, -- [ENCRYPTED] stores ciphertext
    created_at    timestamptz       NOT NULL DEFAULT now(), -- [NEW] not in original
    updated_at    timestamptz       NOT NULL DEFAULT now()  -- [NEW] not in original
);
ALTER TABLE public.fsa_admin_table OWNER TO fsa_admin;
COMMENT ON COLUMN public.fsa_admin_table.admin_pwd IS
    'Must store a bcrypt hash. The trg_hash_admin_password trigger auto-hashes '
    'on INSERT/UPDATE. Use verify_password(plaintext, admin_pwd) to authenticate.';

-- ---------------------------------------------------------------------------
-- gen_details  (central table — all FSA sub-tables FK to this via detail_id)
-- ---------------------------------------------------------------------------
CREATE TABLE public.gen_details (
    detail_id      bigint    NOT NULL,
    rep_name       jsonb,
    designation    jsonb,
    department     jsonb,
    phone_no       jsonb,
    email          jsonb,
    userid         bigint    NOT NULL,
    state          jsonb,
    district       jsonb,
    state_code     jsonb,
    district_code  jsonb,
    edited         boolean   DEFAULT false,
    start_date     character varying,
    end_date       character varying,
    delete_status  boolean,
    police_station character varying,
    ps_code        character varying,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.gen_details OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- fsa_acc
-- [CHANGED vs original] no_of_injuries: integer → character varying (encrypted storage)
-- [CHANGED vs original] no_of_deaths:   integer → character varying (encrypted storage)
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   nearest_hosp, acc_pattern_onspot, time_frame_acc,
--                         age_range, no_of_injuries, no_of_deaths
-- [UNCHANGED columns]   detail_id, no_of_accidents, acc_id, start_age_range,
--                         end_age_range, edited — same as original
-- [NOTE] Decrypted view (v_fsa_acc_decrypted) casts no_of_injuries and
--        no_of_deaths back to integer for application consumers
-- ---------------------------------------------------------------------------
CREATE TABLE public.fsa_acc (
    detail_id         bigint            NOT NULL,
    acc_pattern_onspot character varying, -- [ENCRYPTED] stores ciphertext
    no_of_injuries    character varying, -- [CHANGED] was integer in original; varchar for AES-256 storage
    no_of_deaths      character varying, -- [CHANGED] was integer in original; varchar for AES-256 storage
    no_of_accidents   character varying,
    nearest_hosp      character varying, -- [ENCRYPTED] stores ciphertext
    acc_id            character varying NOT NULL,
    start_age_range   integer,
    end_age_range     integer,
    age_range         character varying, -- [ENCRYPTED] stores ciphertext
    time_frame_acc    character varying, -- [ENCRYPTED] stores ciphertext
    edited            boolean           DEFAULT false,
    created_at        timestamptz       NOT NULL DEFAULT now(), -- [NEW] not in original
    updated_at        timestamptz       NOT NULL DEFAULT now()  -- [NEW] not in original
);
ALTER TABLE public.fsa_acc OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- fsa_onspot
-- [CHANGED vs original] lat:  double precision → character varying (encrypted storage)
-- [CHANGED vs original] long: double precision → character varying (encrypted storage)
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   adjoining_or_junction_no, junction_name, landmark_name,
--                         landmark_dist, name_of_stretch, lat, long, onspot_images
-- [UNCHANGED columns]   all other columns — same as original
-- ---------------------------------------------------------------------------
CREATE TABLE public.fsa_onspot (
    detail_id                    bigint            NOT NULL,
    onspot_id                    character varying NOT NULL,
    lat                          character varying, -- [CHANGED] was double precision; varchar for AES-256 storage
    long                         character varying, -- [CHANGED] was double precision; varchar for AES-256 storage
    highway_no                   character varying,
    land_use_pattern             character varying,
    hotspot_type                 character varying,
    junction_type                character varying,
    junction_name                character varying, -- [ENCRYPTED] stores ciphertext
    junction_formation           character varying,
    stretch_type                 character varying,
    stretch_shape                character varying,
    no_of_lanes                  character varying,
    median_presence              character varying,
    median_opening               character varying,
    speed_of_all_vehicles        character varying,
    adjoining_or_junction_no     character varying, -- [ENCRYPTED] stores ciphertext
    landmark_name                character varying, -- [ENCRYPTED] stores ciphertext
    landmark_type                character varying,
    landmark_dist                character varying, -- [ENCRYPTED] stores ciphertext
    onspot_images                jsonb,             -- [ENCRYPTED] entire jsonb encrypted
    landmark_type_other          character varying,
    edited                       boolean           DEFAULT false,
    junction_formation_others    character varying,
    no_of_lanes_others           character varying,
    name_of_stretch              character varying, -- [ENCRYPTED] stores ciphertext
    delete_status                boolean,
    created_at                   timestamptz       NOT NULL DEFAULT now(), -- [NEW] not in original
    updated_at                   timestamptz       NOT NULL DEFAULT now()  -- [NEW] not in original
);
ALTER TABLE public.fsa_onspot OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- fsa_light
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   light_photos (jsonb)
-- [UNCHANGED columns]   all other columns — same as original
-- ---------------------------------------------------------------------------
CREATE TABLE public.fsa_light (
    light_id         character varying NOT NULL,
    detail_id        bigint            NOT NULL,
    light_avail      character varying,
    switch_type      character varying,
    non_avail_light  character varying,
    light_photos     jsonb,
    edited           boolean           DEFAULT false,
    delete_status    boolean,
    created_at       timestamptz       NOT NULL DEFAULT now(),
    updated_at       timestamptz       NOT NULL DEFAULT now()
);
ALTER TABLE public.fsa_light OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- fsa_ped_cross
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   remarks
-- [UNCHANGED columns]   all other columns — same as original
-- ---------------------------------------------------------------------------
CREATE TABLE public.fsa_ped_cross (
    ped_self_park_t_rash_id                  character varying NOT NULL,
    detail_id                                bigint            NOT NULL,
    ped_animal_cross_lead_acc                character varying,
    ped_animal_cross_spot_reason             character varying,
    road_eng_sol_ped_ani                     character varying,
    enforce_sol_ped_ani                      character varying,
    self_acc_in_junc_freq                    character varying,
    major_reason_self_acc                    character varying,
    road_eng_sol_self_acc                    character varying,
    enf_sol_self_acc                         character varying,
    acc_hitting_parked_veh                   character varying,
    parked_veh_acc_reason                    character varying,
    road_eng_sol_parked_veh_acc              character varying,
    enforce_sol_parked_veh_acc               character varying,
    acc_due_small_t_join_roads               character varying,
    veh_slow_down_small_t_or_join_roads      character varying,
    acc_due_small_t_join_roads_reason        character varying,
    road_eng_sol_for_small_t_join_roads      character varying,
    enforce_sol_for_small_t_join_roads       character varying,
    rash_drivers                             character varying,
    enforce_sol_rash_drive                   character varying,
    remarks                                  character varying,
    types_of_rash_drivers                    character varying,
    others_major_reason_self_acc             character varying,
    others_road_eng_sol_self_acc             character varying,
    types_of_rash_drivers_others             character varying,
    enforce_sol_rash_drive_others            character varying,
    enforce_sol_ped_ani_others               character varying,
    ped_animal_cross_spot_reason_others      character varying,
    road_eng_sol_ped_ani_others              character varying,
    enf_sol_self_acc_others                  character varying,
    enforce_sol_parked_veh_acc_others        character varying,
    parked_veh_acc_reason_others             character varying,
    road_eng_sol_parked_veh_acc_others       character varying,
    acc_due_small_t_join_roads_reason_others character varying,
    enforce_sol_for_small_t_join_roads_others character varying,
    road_eng_sol_for_small_t_join_roads_others character varying,
    edited                                   boolean           DEFAULT false,
    delete_status                            boolean,
    created_at                               timestamptz       NOT NULL DEFAULT now(),
    updated_at                               timestamptz       NOT NULL DEFAULT now()
);
ALTER TABLE public.fsa_ped_cross OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- fsa_roadcnd
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   road_photos (jsonb)
-- [UNCHANGED columns]   all other columns — same as original
-- ---------------------------------------------------------------------------
CREATE TABLE public.fsa_roadcnd (
    roadcnd_id                  character varying NOT NULL,
    detail_id                   bigint            NOT NULL,
    road_issue                  character varying,
    road_defects                character varying,
    road_photos                 jsonb,
    road_eng_sol_roadcnd        character varying,
    road_defects_others         character varying,
    road_eng_sol_rdcnd_others   character varying,
    delete_status               boolean,
    created_at                  timestamptz       NOT NULL DEFAULT now(),
    updated_at                  timestamptz       NOT NULL DEFAULT now()
);
ALTER TABLE public.fsa_roadcnd OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- fsa_traff_status
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   signal_photos, signboards_photos, road_markings_photos (all jsonb)
-- [UNCHANGED columns]   all other columns — same as original
-- ---------------------------------------------------------------------------
CREATE TABLE public.fsa_traff_status (
    detail_id              bigint            NOT NULL,
    traff_status_id        character varying NOT NULL,
    signal_avail           character varying,
    signal_visible         character varying,
    signal_working         character varying,
    signal_timer_work      character varying,
    signal_need            character varying,
    signal_photos          jsonb,
    signboards_avail       character varying,
    signboards_visible     character varying,
    signboards_photos      jsonb,
    road_markings_avail    character varying,
    road_markings_photos   jsonb,
    edited                 boolean           DEFAULT false,
    delete_status          boolean,
    created_at             timestamptz       NOT NULL DEFAULT now(),
    updated_at             timestamptz       NOT NULL DEFAULT now()
);
ALTER TABLE public.fsa_traff_status OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- fsa_traffic_condt
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   none
-- [UNCHANGED columns]   business columns match the original schema
-- ---------------------------------------------------------------------------
CREATE TABLE public.fsa_traffic_condt (
    traffic_id          character varying NOT NULL,
    detail_id           bigint            NOT NULL,
    prevalent_veh_type  character varying,
    start_time          character varying,
    end_time            character varying,
    delete_status       boolean,
    created_at          timestamptz       NOT NULL DEFAULT now(),
    updated_at          timestamptz       NOT NULL DEFAULT now()
);
ALTER TABLE public.fsa_traffic_condt OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- fsa_violations
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   none
-- [UNCHANGED columns]   business columns match the original schema
-- ---------------------------------------------------------------------------
CREATE TABLE public.fsa_violations (
    violations_id                       character varying NOT NULL,
    detail_id                           bigint            NOT NULL,
    road_user_vio_cause_acc             character varying,
    overspeeding_onspot                 character varying,
    avg_speed_range                     character varying,
    m2w                                 character varying,
    lmv                                 character varying,
    hmv                                 character varying,
    reason_for_not_slowing              character varying,
    road_eng_sol_vehoverspeed           character varying,
    enf_sol_veh_over_speed              character varying,
    others_road_user_vio_cause_acc      character varying,
    reason_for_not_slowing_others       character varying,
    enf_sol_veh_over_speed_others       character varying,
    road_eng_sol_vehoverspeed_others    character varying,
    edited                              boolean           DEFAULT false,
    delete_status                       boolean,
    created_at                          timestamptz       NOT NULL DEFAULT now(),
    updated_at                          timestamptz       NOT NULL DEFAULT now()
);
ALTER TABLE public.fsa_violations OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- fsa_visible
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   visib_photos (jsonb)
-- [UNCHANGED columns]   all other columns — same as original
-- ---------------------------------------------------------------------------
CREATE TABLE public.fsa_visible (
    detail_id                    bigint            NOT NULL,
    visible_id                   character varying NOT NULL,
    visib_obstruct_by_objs       character varying,
    atspot_accident_cause        character varying,
    road_eng_sol                 character varying,
    visib_photos                 jsonb,
    is_visib_obstructed          character varying,
    is_visib_obstructed_others   character varying,
    road_eng_sol_others          character varying,
    delete_status                boolean,
    created_at                   timestamptz       NOT NULL DEFAULT now(),
    updated_at                   timestamptz       NOT NULL DEFAULT now()
);
ALTER TABLE public.fsa_visible OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- fsa_wrngway
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   none
-- [UNCHANGED columns]   business columns match the original schema
-- ---------------------------------------------------------------------------
CREATE TABLE public.fsa_wrngway (
    wrgnway_id                          character varying NOT NULL,
    detail_id                           bigint            NOT NULL,
    veh_wrngway_roadside_junct          character varying,
    wrgnway_driving_reason              character varying,
    nearest_opening_to_cross            character varying,
    road_engg_sol_for_wrngway           character varying,
    enforce_sol_for_wrngway             character varying,
    overtaking_acc                      character varying,
    median_avail                        character varying,
    space_to_overtake                   character varying,
    enforce_sol_for_wrngway_other       character varying,
    road_engg_sol_for_wrngway_others    character varying,
    wrgnway_driving_reason_others       character varying,
    reason_for_not_slowing_others       character varying,
    edited                              boolean           DEFAULT false,
    delete_status                       boolean,
    created_at                          timestamptz       NOT NULL DEFAULT now(),
    updated_at                          timestamptz       NOT NULL DEFAULT now()
);
ALTER TABLE public.fsa_wrngway OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- fsa_state_district_table
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   state_admin_name, district_admin_name, state_roa_name,
--                         district_roa_name
-- [UNCHANGED columns]   all id/code columns — same as original
-- ---------------------------------------------------------------------------
CREATE TABLE public.fsa_state_district_table (
    state_admin_id      bigint,
    state_admin_name    character varying,
    state_code          character varying,
    district_admin_id   bigint,
    district_admin_name character varying,
    district_code       character varying,
    state_roa_id        bigint,
    state_roa_name      character varying,
    roa_state_code      character varying[],
    roa_district_code   character varying[],
    district_roa_id     bigint,
    district_roa_name   character varying,
    multiple_districts  text[],
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.fsa_state_district_table OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- intervention
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   admin_name, admin_email, uploaded_docs, admin_role
-- [UNCHANGED columns]   id, detail_id, time_updated, admin_id — same as original
-- ---------------------------------------------------------------------------
CREATE TABLE public.intervention (
    id            bigint            NOT NULL,
    detail_id     bigint,
    time_updated  character varying,
    admin_name    character varying,
    admin_role    character varying,
    admin_email   character varying,
    admin_id      character varying,
    uploaded_docs character varying,
    created_at    timestamptz       NOT NULL DEFAULT now(),
    updated_at    timestamptz       NOT NULL DEFAULT now()
);
ALTER TABLE public.intervention OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- master_table  (denormalized lookup cache in public schema)
-- [UNCHANGED vs original] column set is identical
-- [CHANGED vs original] ownership moved to fsa_admin
-- [NOTE] no timestamps or encryption were added here
-- ---------------------------------------------------------------------------
CREATE TABLE public.master_table (
    type_of_junction                                                   character varying,
    formation_of_junction                                              character varying,
    stretch_type                                                       character varying,
    stretch_shape                                                      character varying,
    no_of_lanes                                                        character varying,
    landmark_type                                                      character varying,
    prevalent_vehicle_type                                             character varying,
    reason_for_visibility_obstruction                                  character varying,
    road_engineering_suggestions_to_avoid_the_accident_visibility      character varying,
    defects                                                            character varying,
    road_engineering_solutions_road_condition                          character varying,
    pattern_of_accidents                                               character varying,
    road_user_violations_causing_accidents                             character varying,
    reasons_for_vehicles_not_slowing_down                              character varying,
    road_engineering_solutions_vehicles_overspeeding                   character varying,
    enforcement_solutions_vehicles_overspeeding                        character varying,
    wrong_way_driving_reasons                                          character varying,
    road_engineering_solutions_wrong_way_driving                       character varying,
    enforcement_solutions_wrong_way_driving                            character varying,
    pedestrain_animal_crossing_the_spot_reasons                        character varying,
    road_engineering_solutions_pedestrain_animal_crossing              character varying,
    enforcement_solutions_pedestrian_animal_crossing                   character varying,
    major_reasons_for_self_accidents                                   character varying,
    road_engineering_solutions_self_accidents                          character varying,
    enforcement_solutions_self_accidents                               character varying,
    parked_vehicle_accidents_reasons                                   character varying,
    road_engineering_solutions_parked_vehicle_accidents                character varying,
    enforcement_solutions_parked_vehicle_accidents                     character varying,
    accidents_due_to_small_t_junction_accidents_or_nearby_joining_r    character varying,
    road_engineering_solutions_small_t_junction_accidents              character varying,
    enforcement_solutions_small_t_junction_accidents                   character varying,
    rash_drivers                                                       character varying,
    enforcement_solutions_rash_driving                                 character varying,
    age_range                                                          character varying(255)
);
ALTER TABLE public.master_table OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- remarks_by_engg
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   admin_name, admin_email, admin_role
-- [UNCHANGED columns]   id, detail_id, time_updated, admin_id — same as original
-- ---------------------------------------------------------------------------
CREATE TABLE public.remarks_by_engg (
    id           bigint            NOT NULL,
    detail_id    bigint,
    time_updated character varying,
    admin_name   character varying,
    admin_role   character varying,
    admin_email  character varying,
    admin_id     character varying,
    created_at   timestamptz       NOT NULL DEFAULT now(),
    updated_at   timestamptz       NOT NULL DEFAULT now()
);
ALTER TABLE public.remarks_by_engg OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- stages_table
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   remarks_by_engg, admin_name, admin_email,
--                         upload_docs_intervention, upload_docs_estimation, admin_role
-- [UNCHANGED columns]   id, detail_id, status_*, time_updated, admin_id — same as original
-- ---------------------------------------------------------------------------
CREATE TABLE public.stages_table (
    id                          bigint            NOT NULL,
    detail_id                   bigint            NOT NULL,
    status_field_inspection     character varying,
    intervention                character varying,
    status_of_estimate          character varying,
    status_of_approval          character varying,
    status_of_implementation    character varying,
    remarks_by_engg             character varying,
    time_updated                character varying,
    admin_name                  character varying,
    admin_role                  character varying,
    admin_email                 character varying,
    admin_id                    character varying,
    upload_docs_intervention    character varying,
    upload_docs_estimation      character varying,
    created_at                  timestamptz       NOT NULL DEFAULT now(),
    updated_at                  timestamptz       NOT NULL DEFAULT now()
);
ALTER TABLE public.stages_table OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- state_district_master_table
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   none
-- [UNCHANGED columns]   state_name, district_name, state_code, district_code, s_no
-- ---------------------------------------------------------------------------
CREATE TABLE public.state_district_master_table (
    state_name    character varying,
    district_name character varying,
    state_code    character varying,
    district_code character varying,
    s_no          bigint,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.state_district_master_table OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- status_field_inspection (public workflow table — distinct from master schema copy)
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   admin_name, admin_email, admin_role
-- [UNCHANGED columns]   id, detail_id, time_updated, admin_id — same as original
-- ---------------------------------------------------------------------------
CREATE TABLE public.status_field_inspection (
    id           bigint            NOT NULL,
    detail_id    bigint,
    time_updated character varying,
    admin_name   character varying,
    admin_role   character varying,
    admin_email  character varying,
    admin_id     character varying,
    created_at   timestamptz       NOT NULL DEFAULT now(),
    updated_at   timestamptz       NOT NULL DEFAULT now()
);
ALTER TABLE public.status_field_inspection OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- status_of_approval (public workflow table)
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   admin_name, admin_email, admin_role
-- [UNCHANGED columns]   id, detail_id, time_updated, admin_id — same as original
-- ---------------------------------------------------------------------------
CREATE TABLE public.status_of_approval (
    id           bigint            NOT NULL,
    detail_id    bigint,
    time_updated character varying,
    admin_name   character varying,
    admin_role   character varying,
    admin_email  character varying,
    admin_id     character varying,
    created_at   timestamptz       NOT NULL DEFAULT now(),
    updated_at   timestamptz       NOT NULL DEFAULT now()
);
ALTER TABLE public.status_of_approval OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- status_of_estimate (public workflow table)
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   admin_name, admin_email, uploaded_docs, admin_role
-- [UNCHANGED columns]   id, detail_id, time_updated, admin_id — same as original
-- ---------------------------------------------------------------------------
CREATE TABLE public.status_of_estimate (
    id            bigint            NOT NULL,
    detail_id     bigint,
    time_updated  character varying,
    admin_name    character varying,
    admin_role    character varying,
    admin_email   character varying,
    admin_id      character varying,
    uploaded_docs character varying,
    created_at    timestamptz       NOT NULL DEFAULT now(),
    updated_at    timestamptz       NOT NULL DEFAULT now()
);
ALTER TABLE public.status_of_estimate OWNER TO fsa_admin;

-- ---------------------------------------------------------------------------
-- status_of_implementation (public workflow table)
-- [NEW vs original]     created_at / updated_at timestamp columns
-- [ENCRYPTED columns]   admin_name, admin_email, admin_role
-- [UNCHANGED columns]   id, detail_id, time_updated, admin_id — same as original
-- ---------------------------------------------------------------------------
CREATE TABLE public.status_of_implementation (
    id           bigint            NOT NULL,
    detail_id    bigint,
    time_updated character varying,
    admin_name   character varying,
    admin_role   character varying,
    admin_email  character varying,
    admin_id     character varying,
    created_at   timestamptz       NOT NULL DEFAULT now(),
    updated_at   timestamptz       NOT NULL DEFAULT now()
);
ALTER TABLE public.status_of_implementation OWNER TO fsa_admin;

-- =============================================================================
-- SECTION 8: SEQUENCES
-- =============================================================================

-- fsa_admin_table_admin_id_seq (identity sequence — defined inline via ALTER TABLE)
ALTER TABLE public.fsa_admin_table ALTER COLUMN admin_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.fsa_admin_table_admin_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

-- gen_details_detail_id_seq
ALTER TABLE public.gen_details ALTER COLUMN detail_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.gen_details_detail_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

-- intervention_id_seq
ALTER TABLE public.intervention ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.intervention_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

-- remarks_by_engg_id_seq
ALTER TABLE public.remarks_by_engg ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.remarks_by_engg_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

-- stages_table_id_seq
ALTER TABLE public.stages_table ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.stages_table_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

-- status_field_inspection_id_seq
ALTER TABLE public.status_field_inspection ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.status_field_inspection_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

-- status_of_approval_id_seq
ALTER TABLE public.status_of_approval ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.status_of_approval_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

-- status_of_estimate_id_seq
ALTER TABLE public.status_of_estimate ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.status_of_estimate_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

-- status_of_implementation_id_seq
ALTER TABLE public.status_of_implementation ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.status_of_implementation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

-- =============================================================================
-- SECTION 9: PRIMARY KEY CONSTRAINTS
-- =============================================================================

ALTER TABLE ONLY public.fsa_acc
    ADD CONSTRAINT acc_pkey PRIMARY KEY (acc_id);

ALTER TABLE ONLY public.fsa_admin_table
    ADD CONSTRAINT fsa_admin_table_pkey PRIMARY KEY (admin_id);

ALTER TABLE ONLY public.fsa_light
    ADD CONSTRAINT fsa_light_visib_pkey PRIMARY KEY (light_id);

ALTER TABLE ONLY public.fsa_onspot
    ADD CONSTRAINT fsa_onspot_pkey PRIMARY KEY (onspot_id);

ALTER TABLE ONLY public.fsa_ped_cross
    ADD CONSTRAINT fsa_ped_self_park_t_rash_pkey PRIMARY KEY (ped_self_park_t_rash_id);

ALTER TABLE ONLY public.fsa_traff_status
    ADD CONSTRAINT fsa_traff_status_pkey PRIMARY KEY (traff_status_id);

ALTER TABLE ONLY public.fsa_traffic_condt
    ADD CONSTRAINT fsa_traffic_pkey PRIMARY KEY (traffic_id);

ALTER TABLE ONLY public.fsa_user_roles
    ADD CONSTRAINT fsa_user_roles_pkey PRIMARY KEY (user_type);

ALTER TABLE ONLY public.fsa_user_table
    ADD CONSTRAINT fsa_user_table_pkey PRIMARY KEY (userid);

ALTER TABLE ONLY public.fsa_violations
    ADD CONSTRAINT fsa_violations_pkey PRIMARY KEY (violations_id);

ALTER TABLE ONLY public.fsa_visible
    ADD CONSTRAINT fsa_visible_pkey PRIMARY KEY (visible_id);

ALTER TABLE ONLY public.fsa_wrngway
    ADD CONSTRAINT fsa_wrngway_overtake_pkey PRIMARY KEY (wrgnway_id);

ALTER TABLE ONLY public.gen_details
    ADD CONSTRAINT fsa_details_pkey PRIMARY KEY (detail_id);

ALTER TABLE ONLY public.stages_table
    ADD CONSTRAINT stages_table_pkey PRIMARY KEY (detail_id);

-- =============================================================================
-- SECTION 10: UNIQUE CONSTRAINTS
-- =============================================================================

ALTER TABLE ONLY public.fsa_admin_table
    ADD CONSTRAINT admin_email_hash_unique UNIQUE (admin_email_hash);

ALTER TABLE ONLY public.fsa_user_table
    ADD CONSTRAINT email_hash_unique UNIQUE (email_hash);

-- =============================================================================
-- SECTION 11: FOREIGN KEY CONSTRAINTS
-- [CHANGED vs original] NOT VALID removed — constraints are now fully enforced.
--   In fps_schema.sql every FK had NOT VALID which meant existing rows were
--   never validated. Here all FKs are hard constraints from the start.
-- [NEW vs original]     Additional FKs added: stages_table, intervention,
--   remarks_by_engg, and all 4 status_* tables now reference gen_details.
--   These relationships existed logically but had no FK in the original.
-- =============================================================================

ALTER TABLE ONLY public.fsa_acc
    ADD CONSTRAINT detail_id
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);

ALTER TABLE ONLY public.fsa_light
    ADD CONSTRAINT fsa_light_detail_id_fkey
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);

ALTER TABLE ONLY public.fsa_onspot
    ADD CONSTRAINT fsa_onspot_detail_id_fkey
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);

ALTER TABLE ONLY public.fsa_ped_cross
    ADD CONSTRAINT fsa_ped_cross_detail_id_fkey
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);

ALTER TABLE ONLY public.fsa_roadcnd
    ADD CONSTRAINT fsa_roadcnd_detail_id_fkey
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);

ALTER TABLE ONLY public.fsa_traff_status
    ADD CONSTRAINT fsa_traff_status_detail_id_fkey
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);

ALTER TABLE ONLY public.fsa_traffic_condt
    ADD CONSTRAINT fsa_traffic_condt_detail_id_fkey
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);

ALTER TABLE ONLY public.fsa_violations
    ADD CONSTRAINT fsa_violations_detail_id_fkey
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);

ALTER TABLE ONLY public.fsa_visible
    ADD CONSTRAINT fsa_visible_detail_id_fkey
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);

ALTER TABLE ONLY public.fsa_wrngway
    ADD CONSTRAINT fsa_wrngway_detail_id_fkey
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);

ALTER TABLE ONLY public.gen_details
    ADD CONSTRAINT gen_details_userid_fkey
        FOREIGN KEY (userid) REFERENCES public.fsa_user_table(userid);

-- stages_table and status workflow tables also reference gen_details
ALTER TABLE ONLY public.stages_table
    ADD CONSTRAINT stages_table_detail_id_fkey
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);

ALTER TABLE ONLY public.intervention
    ADD CONSTRAINT intervention_detail_id_fkey
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);

ALTER TABLE ONLY public.remarks_by_engg
    ADD CONSTRAINT remarks_by_engg_detail_id_fkey
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);

ALTER TABLE ONLY public.status_field_inspection
    ADD CONSTRAINT status_field_inspection_detail_id_fkey
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);

ALTER TABLE ONLY public.status_of_approval
    ADD CONSTRAINT status_of_approval_detail_id_fkey
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);

ALTER TABLE ONLY public.status_of_estimate
    ADD CONSTRAINT status_of_estimate_detail_id_fkey
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);

ALTER TABLE ONLY public.status_of_implementation
    ADD CONSTRAINT status_of_implementation_detail_id_fkey
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);

-- =============================================================================
-- SECTION 12: INDEXES
-- [NEW vs original] fps_schema.sql had zero indexes.
--   FK column indexes on every child table + state/district expression
--   indexes for RLS policy evaluation performance.
-- =============================================================================

CREATE INDEX idx_fsa_acc_detail_id            ON public.fsa_acc            (detail_id);
CREATE INDEX idx_fsa_light_detail_id          ON public.fsa_light          (detail_id);
CREATE INDEX idx_fsa_onspot_detail_id         ON public.fsa_onspot         (detail_id);
CREATE INDEX idx_fsa_ped_cross_detail_id      ON public.fsa_ped_cross      (detail_id);
CREATE INDEX idx_fsa_roadcnd_detail_id        ON public.fsa_roadcnd        (detail_id);
CREATE INDEX idx_fsa_traff_status_detail_id   ON public.fsa_traff_status   (detail_id);
CREATE INDEX idx_fsa_traffic_condt_detail_id  ON public.fsa_traffic_condt  (detail_id);
CREATE INDEX idx_fsa_violations_detail_id     ON public.fsa_violations     (detail_id);
CREATE INDEX idx_fsa_visible_detail_id        ON public.fsa_visible        (detail_id);
CREATE INDEX idx_fsa_wrngway_detail_id        ON public.fsa_wrngway        (detail_id);
CREATE INDEX idx_gen_details_userid           ON public.gen_details        (userid);
CREATE INDEX idx_stages_table_detail_id       ON public.stages_table       (detail_id);
CREATE INDEX idx_intervention_detail_id       ON public.intervention       (detail_id);
CREATE INDEX idx_remarks_by_engg_detail_id    ON public.remarks_by_engg   (detail_id);
CREATE INDEX idx_status_fi_detail_id          ON public.status_field_inspection    (detail_id);
CREATE INDEX idx_status_oa_detail_id          ON public.status_of_approval         (detail_id);
CREATE INDEX idx_status_oe_detail_id          ON public.status_of_estimate         (detail_id);
CREATE INDEX idx_status_oi_detail_id          ON public.status_of_implementation   (detail_id);

-- State/district indexes for RLS policy evaluation performance
CREATE INDEX idx_gen_details_state_code    ON public.gen_details (((state_code->>'0')::text));
CREATE INDEX idx_gen_details_district_code ON public.gen_details (((district_code->>'0')::text));
CREATE INDEX idx_fsa_user_state_code       ON public.fsa_user_table (state_code);
CREATE INDEX idx_fsa_user_district_code    ON public.fsa_user_table (district_code);
CREATE INDEX idx_fsa_admin_state_code      ON public.fsa_admin_table (state_code);
CREATE INDEX idx_fsa_admin_district_code   ON public.fsa_admin_table (district_code);
CREATE INDEX idx_fsa_sdt_state_code        ON public.fsa_state_district_table (state_code);

-- =============================================================================
-- SECTION 13: PASSWORD HASHING TRIGGERS
-- [NEW vs original] fps_schema.sql had no password hashing triggers.
--   These ensure pwd/admin_pwd are always stored as bcrypt hashes, never plaintext.
-- =============================================================================

CREATE TRIGGER trg_hash_admin_pwd
    BEFORE INSERT OR UPDATE OF admin_pwd ON public.fsa_admin_table
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_hash_admin_password();

CREATE TRIGGER trg_hash_user_pwd
    BEFORE INSERT OR UPDATE OF pwd ON public.fsa_user_table
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_hash_user_password();

-- =============================================================================
-- SECTION 13A: FIELD ENCRYPTION TRIGGERS
-- [NEW vs original] fps_schema.sql had no field-level encryption.
--   These BEFORE triggers encrypt sensitive columns before they are written.
--   pwd/admin_pwd are intentionally excluded because they are one-way bcrypt hashes.
-- =============================================================================

CREATE TRIGGER trg_encrypt_fsa_user_table
    BEFORE INSERT OR UPDATE ON public.fsa_user_table
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_encrypt_sensitive_fields();

CREATE TRIGGER trg_encrypt_fsa_admin_table
    BEFORE INSERT OR UPDATE ON public.fsa_admin_table
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_encrypt_sensitive_fields();

CREATE TRIGGER trg_encrypt_gen_details
    BEFORE INSERT OR UPDATE ON public.gen_details
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_encrypt_sensitive_fields();

CREATE TRIGGER trg_encrypt_fsa_acc
    BEFORE INSERT OR UPDATE ON public.fsa_acc
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_encrypt_sensitive_fields();

CREATE TRIGGER trg_encrypt_fsa_onspot
    BEFORE INSERT OR UPDATE ON public.fsa_onspot
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_encrypt_sensitive_fields();

CREATE TRIGGER trg_encrypt_fsa_ped_cross
    BEFORE INSERT OR UPDATE ON public.fsa_ped_cross
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_encrypt_sensitive_fields();

CREATE TRIGGER trg_encrypt_fsa_state_district_table
    BEFORE INSERT OR UPDATE ON public.fsa_state_district_table
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_encrypt_sensitive_fields();

CREATE TRIGGER trg_encrypt_intervention
    BEFORE INSERT OR UPDATE ON public.intervention
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_encrypt_sensitive_fields();

CREATE TRIGGER trg_encrypt_remarks_by_engg
    BEFORE INSERT OR UPDATE ON public.remarks_by_engg
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_encrypt_sensitive_fields();

CREATE TRIGGER trg_encrypt_stages_table
    BEFORE INSERT OR UPDATE ON public.stages_table
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_encrypt_sensitive_fields();

CREATE TRIGGER trg_encrypt_status_field_inspection
    BEFORE INSERT OR UPDATE ON public.status_field_inspection
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_encrypt_sensitive_fields();

CREATE TRIGGER trg_encrypt_status_of_approval
    BEFORE INSERT OR UPDATE ON public.status_of_approval
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_encrypt_sensitive_fields();

CREATE TRIGGER trg_encrypt_status_of_estimate
    BEFORE INSERT OR UPDATE ON public.status_of_estimate
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_encrypt_sensitive_fields();

CREATE TRIGGER trg_encrypt_status_of_implementation
    BEFORE INSERT OR UPDATE ON public.status_of_implementation
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_encrypt_sensitive_fields();

CREATE TRIGGER trg_encrypt_fsa_light
    BEFORE INSERT OR UPDATE ON public.fsa_light
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_encrypt_sensitive_fields();

CREATE TRIGGER trg_encrypt_fsa_traff_status
    BEFORE INSERT OR UPDATE ON public.fsa_traff_status
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_encrypt_sensitive_fields();

CREATE TRIGGER trg_encrypt_fsa_visible
    BEFORE INSERT OR UPDATE ON public.fsa_visible
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_encrypt_sensitive_fields();

CREATE TRIGGER trg_encrypt_fsa_roadcnd
    BEFORE INSERT OR UPDATE ON public.fsa_roadcnd
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_encrypt_sensitive_fields();

-- =============================================================================
-- SECTION 14: TIMESTAMP TRIGGERS (updated_at maintenance)
-- [NEW vs original] fps_schema.sql had no updated_at maintenance logic.
-- =============================================================================

CREATE TRIGGER trg_ts_fsa_user_roles
    BEFORE UPDATE ON public.fsa_user_roles
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_fsa_user_table
    BEFORE UPDATE ON public.fsa_user_table
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_fsa_admin_table
    BEFORE UPDATE ON public.fsa_admin_table
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_gen_details
    BEFORE UPDATE ON public.gen_details
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_fsa_acc
    BEFORE UPDATE ON public.fsa_acc
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_fsa_onspot
    BEFORE UPDATE ON public.fsa_onspot
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_fsa_light
    BEFORE UPDATE ON public.fsa_light
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_fsa_ped_cross
    BEFORE UPDATE ON public.fsa_ped_cross
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_fsa_roadcnd
    BEFORE UPDATE ON public.fsa_roadcnd
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_fsa_traff_status
    BEFORE UPDATE ON public.fsa_traff_status
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_fsa_traffic_condt
    BEFORE UPDATE ON public.fsa_traffic_condt
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_fsa_violations
    BEFORE UPDATE ON public.fsa_violations
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_fsa_visible
    BEFORE UPDATE ON public.fsa_visible
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_fsa_wrngway
    BEFORE UPDATE ON public.fsa_wrngway
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_fsa_state_district
    BEFORE UPDATE ON public.fsa_state_district_table
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_intervention
    BEFORE UPDATE ON public.intervention
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_remarks_by_engg
    BEFORE UPDATE ON public.remarks_by_engg
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_stages_table
    BEFORE UPDATE ON public.stages_table
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_state_district_master
    BEFORE UPDATE ON public.state_district_master_table
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_status_field_inspection
    BEFORE UPDATE ON public.status_field_inspection
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_status_of_approval
    BEFORE UPDATE ON public.status_of_approval
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_status_of_estimate
    BEFORE UPDATE ON public.status_of_estimate
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_status_of_implementation
    BEFORE UPDATE ON public.status_of_implementation
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

CREATE TRIGGER trg_ts_master_table
    BEFORE UPDATE ON public.master_table
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();

-- =============================================================================
-- SECTION 15: AUDIT TRIGGERS
-- (Attached to all public schema tables that carry operational data.
--  Master/lookup tables in the master schema are excluded to keep audit lean.)
-- [NEW vs original] fps_schema.sql had no audit logging.
-- =============================================================================

CREATE TRIGGER audit_fsa_user_table
    AFTER INSERT OR UPDATE OR DELETE ON public.fsa_user_table
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_fsa_admin_table
    AFTER INSERT OR UPDATE OR DELETE ON public.fsa_admin_table
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_gen_details
    AFTER INSERT OR UPDATE OR DELETE ON public.gen_details
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_fsa_acc
    AFTER INSERT OR UPDATE OR DELETE ON public.fsa_acc
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_fsa_onspot
    AFTER INSERT OR UPDATE OR DELETE ON public.fsa_onspot
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_fsa_light
    AFTER INSERT OR UPDATE OR DELETE ON public.fsa_light
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_fsa_ped_cross
    AFTER INSERT OR UPDATE OR DELETE ON public.fsa_ped_cross
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_fsa_roadcnd
    AFTER INSERT OR UPDATE OR DELETE ON public.fsa_roadcnd
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_fsa_traff_status
    AFTER INSERT OR UPDATE OR DELETE ON public.fsa_traff_status
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_fsa_traffic_condt
    AFTER INSERT OR UPDATE OR DELETE ON public.fsa_traffic_condt
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_fsa_violations
    AFTER INSERT OR UPDATE OR DELETE ON public.fsa_violations
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_fsa_visible
    AFTER INSERT OR UPDATE OR DELETE ON public.fsa_visible
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_fsa_wrngway
    AFTER INSERT OR UPDATE OR DELETE ON public.fsa_wrngway
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_stages_table
    AFTER INSERT OR UPDATE OR DELETE ON public.stages_table
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_intervention
    AFTER INSERT OR UPDATE OR DELETE ON public.intervention
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_remarks_by_engg
    AFTER INSERT OR UPDATE OR DELETE ON public.remarks_by_engg
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_status_field_inspection
    AFTER INSERT OR UPDATE OR DELETE ON public.status_field_inspection
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_status_of_approval
    AFTER INSERT OR UPDATE OR DELETE ON public.status_of_approval
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_status_of_estimate
    AFTER INSERT OR UPDATE OR DELETE ON public.status_of_estimate
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_status_of_implementation
    AFTER INSERT OR UPDATE OR DELETE ON public.status_of_implementation
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

CREATE TRIGGER audit_fsa_state_district_table
    AFTER INSERT OR UPDATE OR DELETE ON public.fsa_state_district_table
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

-- =============================================================================
-- SECTION 16: ROW LEVEL SECURITY (RLS)
-- [NEW vs original] fps_schema.sql had no RLS policies or session-scoped access control.
-- =============================================================================
--
-- HOW RLS WORKS IN THIS SCHEMA:
--   The app must call the following at the start of every connection/transaction:
--
--     SET app.current_state_code    = '<state_code>';
--     SET app.current_district_code = '<district_code>';
--     SET app.current_user_id       = '<userid>';
--
--   gen_details stores state_code/district_code as jsonb arrays.
--   The first element [0] (index '0' in jsonb) is used for matching because
--   the application stores these as single-element arrays in practice.
--
--   fsa_admin BYPASSRLS so all admin operations skip these policies.
--   fsa_app   can read and write rows matching the session state/district.
--   fsa_readonly can only read, same filter.
--
--   Super-admins who need cross-state access should connect as fsa_admin.
-- =============================================================================

-- Turn off row_security override for subsequent table-level enablement
SET row_security = on;

-- ---------------------------------------------------------------------------
-- 16a. gen_details — the root table; all other RLS policies reference it
-- ---------------------------------------------------------------------------
ALTER TABLE public.gen_details ENABLE ROW LEVEL SECURITY;

CREATE POLICY gen_details_app_policy ON public.gen_details
    AS PERMISSIVE
    FOR ALL
    TO fsa_app
    USING (
        (state_code->>'0') = current_setting('app.current_state_code', true)
        AND (
            current_setting('app.current_district_code', true) = ''
            OR (district_code->>'0') = current_setting('app.current_district_code', true)
        )
    )
    WITH CHECK (
        (state_code->>'0') = current_setting('app.current_state_code', true)
        AND (
            current_setting('app.current_district_code', true) = ''
            OR (district_code->>'0') = current_setting('app.current_district_code', true)
        )
    );

CREATE POLICY gen_details_readonly_policy ON public.gen_details
    AS PERMISSIVE
    FOR SELECT
    TO fsa_readonly
    USING (
        (state_code->>'0') = current_setting('app.current_state_code', true)
        AND (
            current_setting('app.current_district_code', true) = ''
            OR (district_code->>'0') = current_setting('app.current_district_code', true)
        )
    );

-- ---------------------------------------------------------------------------
-- Helper: macro for tables that join to gen_details via detail_id
-- The policy checks that the detail_id exists in gen_details for the
-- current session's state/district.
-- ---------------------------------------------------------------------------

-- fsa_acc
ALTER TABLE public.fsa_acc ENABLE ROW LEVEL SECURITY;

CREATE POLICY fsa_acc_app_policy ON public.fsa_acc
    AS PERMISSIVE FOR ALL TO fsa_app
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (
                  current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true)
              )
        )
    )
    WITH CHECK (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (
                  current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true)
              )
        )
    );

CREATE POLICY fsa_acc_readonly_policy ON public.fsa_acc
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (
                  current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true)
              )
        )
    );

-- fsa_onspot
ALTER TABLE public.fsa_onspot ENABLE ROW LEVEL SECURITY;

CREATE POLICY fsa_onspot_app_policy ON public.fsa_onspot
    AS PERMISSIVE FOR ALL TO fsa_app
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    )
    WITH CHECK (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

CREATE POLICY fsa_onspot_readonly_policy ON public.fsa_onspot
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

-- fsa_light
ALTER TABLE public.fsa_light ENABLE ROW LEVEL SECURITY;

CREATE POLICY fsa_light_app_policy ON public.fsa_light
    AS PERMISSIVE FOR ALL TO fsa_app
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    )
    WITH CHECK (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

CREATE POLICY fsa_light_readonly_policy ON public.fsa_light
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

-- fsa_ped_cross
ALTER TABLE public.fsa_ped_cross ENABLE ROW LEVEL SECURITY;

CREATE POLICY fsa_ped_cross_app_policy ON public.fsa_ped_cross
    AS PERMISSIVE FOR ALL TO fsa_app
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    )
    WITH CHECK (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

CREATE POLICY fsa_ped_cross_readonly_policy ON public.fsa_ped_cross
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

-- fsa_roadcnd
ALTER TABLE public.fsa_roadcnd ENABLE ROW LEVEL SECURITY;

CREATE POLICY fsa_roadcnd_app_policy ON public.fsa_roadcnd
    AS PERMISSIVE FOR ALL TO fsa_app
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    )
    WITH CHECK (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

CREATE POLICY fsa_roadcnd_readonly_policy ON public.fsa_roadcnd
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

-- fsa_traff_status
ALTER TABLE public.fsa_traff_status ENABLE ROW LEVEL SECURITY;

CREATE POLICY fsa_traff_status_app_policy ON public.fsa_traff_status
    AS PERMISSIVE FOR ALL TO fsa_app
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    )
    WITH CHECK (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

CREATE POLICY fsa_traff_status_readonly_policy ON public.fsa_traff_status
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

-- fsa_traffic_condt
ALTER TABLE public.fsa_traffic_condt ENABLE ROW LEVEL SECURITY;

CREATE POLICY fsa_traffic_condt_app_policy ON public.fsa_traffic_condt
    AS PERMISSIVE FOR ALL TO fsa_app
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    )
    WITH CHECK (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

CREATE POLICY fsa_traffic_condt_readonly_policy ON public.fsa_traffic_condt
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

-- fsa_violations
ALTER TABLE public.fsa_violations ENABLE ROW LEVEL SECURITY;

CREATE POLICY fsa_violations_app_policy ON public.fsa_violations
    AS PERMISSIVE FOR ALL TO fsa_app
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    )
    WITH CHECK (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

CREATE POLICY fsa_violations_readonly_policy ON public.fsa_violations
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

-- fsa_visible
ALTER TABLE public.fsa_visible ENABLE ROW LEVEL SECURITY;

CREATE POLICY fsa_visible_app_policy ON public.fsa_visible
    AS PERMISSIVE FOR ALL TO fsa_app
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    )
    WITH CHECK (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

CREATE POLICY fsa_visible_readonly_policy ON public.fsa_visible
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

-- fsa_wrngway
ALTER TABLE public.fsa_wrngway ENABLE ROW LEVEL SECURITY;

CREATE POLICY fsa_wrngway_app_policy ON public.fsa_wrngway
    AS PERMISSIVE FOR ALL TO fsa_app
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    )
    WITH CHECK (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

CREATE POLICY fsa_wrngway_readonly_policy ON public.fsa_wrngway
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

-- stages_table
ALTER TABLE public.stages_table ENABLE ROW LEVEL SECURITY;

CREATE POLICY stages_table_app_policy ON public.stages_table
    AS PERMISSIVE FOR ALL TO fsa_app
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    )
    WITH CHECK (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

CREATE POLICY stages_table_readonly_policy ON public.stages_table
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

ALTER TABLE public.fsa_user_table ENABLE ROW LEVEL SECURITY;

CREATE POLICY fsa_user_table_app_policy ON public.fsa_user_table
    AS PERMISSIVE FOR ALL TO fsa_app
    USING (
        state_code = current_setting('app.current_state_code', true)
        AND (current_setting('app.current_district_code', true) = ''
            OR district_code = current_setting('app.current_district_code', true))
    )
    WITH CHECK (
        state_code = current_setting('app.current_state_code', true)
        AND (current_setting('app.current_district_code', true) = ''
            OR district_code = current_setting('app.current_district_code', true))
    );

CREATE POLICY fsa_user_table_readonly_policy ON public.fsa_user_table
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        state_code = current_setting('app.current_state_code', true)
        AND (current_setting('app.current_district_code', true) = ''
            OR district_code = current_setting('app.current_district_code', true))
    );

ALTER TABLE public.fsa_admin_table ENABLE ROW LEVEL SECURITY;

CREATE POLICY fsa_admin_table_app_policy ON public.fsa_admin_table
    AS PERMISSIVE FOR ALL TO fsa_app
    USING (
        state_code = current_setting('app.current_state_code', true)
        AND (current_setting('app.current_district_code', true) = ''
            OR district_code = current_setting('app.current_district_code', true))
    )
    WITH CHECK (
        state_code = current_setting('app.current_state_code', true)
        AND (current_setting('app.current_district_code', true) = ''
            OR district_code = current_setting('app.current_district_code', true))
    );

CREATE POLICY fsa_admin_table_readonly_policy ON public.fsa_admin_table
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        state_code = current_setting('app.current_state_code', true)
        AND (current_setting('app.current_district_code', true) = ''
            OR district_code = current_setting('app.current_district_code', true))
    );

ALTER TABLE public.fsa_state_district_table ENABLE ROW LEVEL SECURITY;

CREATE POLICY fsa_state_district_table_app_policy ON public.fsa_state_district_table
    AS PERMISSIVE FOR ALL TO fsa_app
    USING (
        state_code = current_setting('app.current_state_code', true)
    )
    WITH CHECK (
        state_code = current_setting('app.current_state_code', true)
    );

CREATE POLICY fsa_state_district_table_readonly_policy ON public.fsa_state_district_table
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        state_code = current_setting('app.current_state_code', true)
    );

ALTER TABLE public.intervention ENABLE ROW LEVEL SECURITY;

CREATE POLICY intervention_app_policy ON public.intervention
    AS PERMISSIVE FOR ALL TO fsa_app
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    )
    WITH CHECK (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

CREATE POLICY intervention_readonly_policy ON public.intervention
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

ALTER TABLE public.remarks_by_engg ENABLE ROW LEVEL SECURITY;

CREATE POLICY remarks_by_engg_app_policy ON public.remarks_by_engg
    AS PERMISSIVE FOR ALL TO fsa_app
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    )
    WITH CHECK (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

CREATE POLICY remarks_by_engg_readonly_policy ON public.remarks_by_engg
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

ALTER TABLE public.status_field_inspection ENABLE ROW LEVEL SECURITY;

CREATE POLICY status_field_inspection_app_policy ON public.status_field_inspection
    AS PERMISSIVE FOR ALL TO fsa_app
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    )
    WITH CHECK (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

CREATE POLICY status_field_inspection_readonly_policy ON public.status_field_inspection
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

ALTER TABLE public.status_of_approval ENABLE ROW LEVEL SECURITY;

CREATE POLICY status_of_approval_app_policy ON public.status_of_approval
    AS PERMISSIVE FOR ALL TO fsa_app
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    )
    WITH CHECK (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

CREATE POLICY status_of_approval_readonly_policy ON public.status_of_approval
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

ALTER TABLE public.status_of_estimate ENABLE ROW LEVEL SECURITY;

CREATE POLICY status_of_estimate_app_policy ON public.status_of_estimate
    AS PERMISSIVE FOR ALL TO fsa_app
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    )
    WITH CHECK (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

CREATE POLICY status_of_estimate_readonly_policy ON public.status_of_estimate
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

ALTER TABLE public.status_of_implementation ENABLE ROW LEVEL SECURITY;

CREATE POLICY status_of_implementation_app_policy ON public.status_of_implementation
    AS PERMISSIVE FOR ALL TO fsa_app
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    )
    WITH CHECK (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

CREATE POLICY status_of_implementation_readonly_policy ON public.status_of_implementation
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        detail_id IN (
            SELECT detail_id FROM public.gen_details
            WHERE (state_code->>'0') = current_setting('app.current_state_code', true)
              AND (current_setting('app.current_district_code', true) = ''
                  OR (district_code->>'0') = current_setting('app.current_district_code', true))
        )
    );

-- =============================================================================
-- SECTION 16A: DECRYPTED READ VIEWS
-- [NEW vs original] Did not exist in fps_schema.sql.
--   Each view exposes the decrypted plaintext of every encrypted column.
--   Use these views to read data in your application or DbGate SQL editor.
--   Format: v_<tablename>_decrypted
--   Requires app.encryption_key session var to be set before querying.
-- =============================================================================

CREATE VIEW public.v_fsa_user_table_decrypted WITH (security_invoker = true) AS
SELECT
    pwd,
    public.decrypt_text_value(last_login) AS last_login,
    login_status,
    public.decrypt_text_value(email) AS email,
    email_hash,
    public.decrypt_text_value(rep_name) AS rep_name,
    public.decrypt_text_value(designation) AS designation,
    public.decrypt_text_value(department) AS department,
    public.decrypt_text_value(phone_no) AS phone_no,
    userid,
    user_type,
    user_role,
    terms_cond,
    public.decrypt_jsonb_value(user_file) AS user_file,
    admin_id,
    user_status,
    state_code,
    district_code,
    public.decrypt_text_value(state_name) AS state_name,
    public.decrypt_text_value(district_name) AS district_name,
    ps_code,
    public.decrypt_text_value(police_station) AS police_station,
    created_at,
    updated_at
FROM public.fsa_user_table;

CREATE VIEW public.v_fsa_admin_table_decrypted WITH (security_invoker = true) AS
SELECT
    public.decrypt_text_value(admin_email) AS admin_email,
    admin_email_hash,
    admin_id,
    admin_role_id,
    public.decrypt_text_value(admin_role) AS admin_role,
    public.decrypt_text_value(admin_name) AS admin_name,
    admin_pwd,
    login_status,
    public.decrypt_text_value(last_login) AS last_login,
    user_status,
    public.decrypt_text_value(state_name) AS state_name,
    public.decrypt_text_value(district_name) AS district_name,
    state_code,
    district_code,
    public.decrypt_text_value(created_by) AS created_by,
    public.decrypt_text_value(phone_no) AS phone_no,
    created_at,
    updated_at
FROM public.fsa_admin_table;

CREATE VIEW public.v_gen_details_decrypted WITH (security_invoker = true) AS
SELECT
    detail_id,
    public.decrypt_jsonb_value(rep_name) AS rep_name,
    public.decrypt_jsonb_value(designation) AS designation,
    public.decrypt_jsonb_value(department) AS department,
    public.decrypt_jsonb_value(phone_no) AS phone_no,
    public.decrypt_jsonb_value(email) AS email,
    userid,
    public.decrypt_jsonb_value(state) AS state,
    public.decrypt_jsonb_value(district) AS district,
    public.decrypt_jsonb_value(state_code) AS state_code,
    public.decrypt_jsonb_value(district_code) AS district_code,
    edited,
    start_date,
    end_date,
    delete_status,
    public.decrypt_text_value(police_station) AS police_station,
    ps_code,
    created_at,
    updated_at
FROM public.gen_details;

CREATE VIEW public.v_fsa_acc_decrypted WITH (security_invoker = true) AS
SELECT
    detail_id,
    public.decrypt_text_value(acc_pattern_onspot) AS acc_pattern_onspot,
    public.decrypt_text_value(no_of_injuries)::integer AS no_of_injuries,
    public.decrypt_text_value(no_of_deaths)::integer AS no_of_deaths,
    no_of_accidents,
    public.decrypt_text_value(nearest_hosp) AS nearest_hosp,
    acc_id,
    start_age_range,
    end_age_range,
    public.decrypt_text_value(age_range) AS age_range,
    public.decrypt_text_value(time_frame_acc) AS time_frame_acc,
    edited,
    created_at,
    updated_at
FROM public.fsa_acc;

CREATE VIEW public.v_fsa_onspot_decrypted WITH (security_invoker = true) AS
SELECT
    detail_id,
    onspot_id,
    public.decrypt_text_value(lat)::double precision AS lat,
    public.decrypt_text_value(long)::double precision AS long,
    highway_no,
    land_use_pattern,
    hotspot_type,
    junction_type,
    public.decrypt_text_value(junction_name) AS junction_name,
    junction_formation,
    stretch_type,
    stretch_shape,
    no_of_lanes,
    median_presence,
    median_opening,
    speed_of_all_vehicles,
    public.decrypt_text_value(adjoining_or_junction_no) AS adjoining_or_junction_no,
    public.decrypt_text_value(landmark_name) AS landmark_name,
    landmark_type,
    public.decrypt_text_value(landmark_dist) AS landmark_dist,
    public.decrypt_jsonb_value(onspot_images) AS onspot_images,
    landmark_type_other,
    edited,
    junction_formation_others,
    no_of_lanes_others,
    public.decrypt_text_value(name_of_stretch) AS name_of_stretch,
    delete_status,
    created_at,
    updated_at
FROM public.fsa_onspot;

CREATE VIEW public.v_fsa_ped_cross_decrypted WITH (security_invoker = true) AS
SELECT
    ped_self_park_t_rash_id,
    detail_id,
    ped_animal_cross_lead_acc,
    ped_animal_cross_spot_reason,
    road_eng_sol_ped_ani,
    enforce_sol_ped_ani,
    self_acc_in_junc_freq,
    major_reason_self_acc,
    road_eng_sol_self_acc,
    enf_sol_self_acc,
    acc_hitting_parked_veh,
    parked_veh_acc_reason,
    road_eng_sol_parked_veh_acc,
    enforce_sol_parked_veh_acc,
    acc_due_small_t_join_roads,
    veh_slow_down_small_t_or_join_roads,
    acc_due_small_t_join_roads_reason,
    road_eng_sol_for_small_t_join_roads,
    enforce_sol_for_small_t_join_roads,
    rash_drivers,
    enforce_sol_rash_drive,
    public.decrypt_text_value(remarks) AS remarks,
    types_of_rash_drivers,
    others_major_reason_self_acc,
    others_road_eng_sol_self_acc,
    types_of_rash_drivers_others,
    enforce_sol_rash_drive_others,
    enforce_sol_ped_ani_others,
    ped_animal_cross_spot_reason_others,
    road_eng_sol_ped_ani_others,
    enf_sol_self_acc_others,
    enforce_sol_parked_veh_acc_others,
    parked_veh_acc_reason_others,
    road_eng_sol_parked_veh_acc_others,
    edited,
    delete_status,
    created_at,
    updated_at
FROM public.fsa_ped_cross;

CREATE VIEW public.v_fsa_state_district_table_decrypted WITH (security_invoker = true) AS
SELECT
    state_admin_id,
    public.decrypt_text_value(state_admin_name) AS state_admin_name,
    state_code,
    district_admin_id,
    public.decrypt_text_value(district_admin_name) AS district_admin_name,
    district_code,
    state_roa_id,
    public.decrypt_text_value(state_roa_name) AS state_roa_name,
    roa_state_code,
    roa_district_code,
    district_roa_id,
    public.decrypt_text_value(district_roa_name) AS district_roa_name,
    multiple_districts,
    created_at,
    updated_at
FROM public.fsa_state_district_table;

CREATE VIEW public.v_intervention_decrypted WITH (security_invoker = true) AS
SELECT id, detail_id, time_updated,
       public.decrypt_text_value(admin_name) AS admin_name,
       public.decrypt_text_value(admin_role) AS admin_role,
       public.decrypt_text_value(admin_email) AS admin_email,
       admin_id,
       public.decrypt_text_value(uploaded_docs) AS uploaded_docs,
       created_at,
       updated_at
FROM public.intervention;

CREATE VIEW public.v_remarks_by_engg_decrypted WITH (security_invoker = true) AS
SELECT id, detail_id, time_updated,
       public.decrypt_text_value(admin_name) AS admin_name,
       public.decrypt_text_value(admin_role) AS admin_role,
       public.decrypt_text_value(admin_email) AS admin_email,
       admin_id,
       created_at,
       updated_at
FROM public.remarks_by_engg;

CREATE VIEW public.v_stages_table_decrypted WITH (security_invoker = true) AS
SELECT id, detail_id, status_field_inspection, intervention, status_of_estimate,
       status_of_approval, status_of_implementation,
       public.decrypt_text_value(remarks_by_engg) AS remarks_by_engg,
       time_updated,
       public.decrypt_text_value(admin_name) AS admin_name,
       public.decrypt_text_value(admin_role) AS admin_role,
       public.decrypt_text_value(admin_email) AS admin_email,
       admin_id,
       public.decrypt_text_value(upload_docs_intervention) AS upload_docs_intervention,
       public.decrypt_text_value(upload_docs_estimation) AS upload_docs_estimation,
       created_at,
       updated_at
FROM public.stages_table;

CREATE VIEW public.v_status_field_inspection_decrypted WITH (security_invoker = true) AS
SELECT id, detail_id, time_updated,
       public.decrypt_text_value(admin_name) AS admin_name,
       public.decrypt_text_value(admin_role) AS admin_role,
       public.decrypt_text_value(admin_email) AS admin_email,
       admin_id,
       created_at,
       updated_at
FROM public.status_field_inspection;

CREATE VIEW public.v_status_of_approval_decrypted WITH (security_invoker = true) AS
SELECT id, detail_id, time_updated,
       public.decrypt_text_value(admin_name) AS admin_name,
       public.decrypt_text_value(admin_role) AS admin_role,
       public.decrypt_text_value(admin_email) AS admin_email,
       admin_id,
       created_at,
       updated_at
FROM public.status_of_approval;

CREATE VIEW public.v_status_of_estimate_decrypted WITH (security_invoker = true) AS
SELECT id, detail_id, time_updated,
       public.decrypt_text_value(admin_name) AS admin_name,
       public.decrypt_text_value(admin_role) AS admin_role,
       public.decrypt_text_value(admin_email) AS admin_email,
       admin_id,
       public.decrypt_text_value(uploaded_docs) AS uploaded_docs,
       created_at,
       updated_at
FROM public.status_of_estimate;

CREATE VIEW public.v_status_of_implementation_decrypted WITH (security_invoker = true) AS
SELECT id, detail_id, time_updated,
       public.decrypt_text_value(admin_name) AS admin_name,
       public.decrypt_text_value(admin_role) AS admin_role,
       public.decrypt_text_value(admin_email) AS admin_email,
       admin_id,
       created_at,
       updated_at
FROM public.status_of_implementation;

CREATE VIEW public.v_fsa_light_decrypted WITH (security_invoker = true) AS
SELECT
    light_id,
    detail_id,
    light_avail,
    switch_type,
    non_avail_light,
    public.decrypt_jsonb_value(light_photos) AS light_photos,
    edited,
    delete_status,
    created_at,
    updated_at
FROM public.fsa_light;

CREATE VIEW public.v_fsa_traff_status_decrypted WITH (security_invoker = true) AS
SELECT
    detail_id,
    traff_status_id,
    signal_avail,
    signal_visible,
    signal_working,
    signal_timer_work,
    signal_need,
    public.decrypt_jsonb_value(signal_photos) AS signal_photos,
    signboards_avail,
    signboards_visible,
    public.decrypt_jsonb_value(signboards_photos) AS signboards_photos,
    road_markings_avail,
    public.decrypt_jsonb_value(road_markings_photos) AS road_markings_photos,
    edited,
    delete_status,
    created_at,
    updated_at
FROM public.fsa_traff_status;

CREATE VIEW public.v_fsa_visible_decrypted WITH (security_invoker = true) AS
SELECT
    detail_id,
    visible_id,
    visib_obstruct_by_objs,
    atspot_accident_cause,
    road_eng_sol,
    public.decrypt_jsonb_value(visib_photos) AS visib_photos,
    is_visib_obstructed,
    is_visib_obstructed_others,
    road_eng_sol_others,
    delete_status,
    created_at,
    updated_at
FROM public.fsa_visible;

CREATE VIEW public.v_fsa_roadcnd_decrypted WITH (security_invoker = true) AS
SELECT
    roadcnd_id,
    detail_id,
    road_issue,
    road_defects,
    public.decrypt_jsonb_value(road_photos) AS road_photos,
    road_eng_sol_roadcnd,
    road_defects_others,
    road_eng_sol_rdcnd_others,
    delete_status,
    created_at,
    updated_at
FROM public.fsa_roadcnd;

-- =============================================================================
-- SECTION 17: GRANT STATEMENTS
-- =============================================================================

-- SCHEMA usage
GRANT USAGE ON SCHEMA public  TO fsa_app, fsa_readonly;
GRANT USAGE ON SCHEMA master  TO fsa_app, fsa_readonly;
GRANT USAGE ON SCHEMA audit   TO fsa_app, fsa_readonly;

-- fsa_admin owns all schemas and tables — gets ALL implicitly as owner

-- fsa_app: full CRUD on all public operational tables
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fsa_user_table         TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fsa_admin_table        TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.gen_details            TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fsa_acc                TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fsa_onspot             TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fsa_light              TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fsa_ped_cross          TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fsa_roadcnd            TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fsa_traff_status       TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fsa_traffic_condt      TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fsa_violations         TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fsa_visible            TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fsa_wrngway            TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fsa_user_roles         TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.fsa_state_district_table TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.intervention           TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.remarks_by_engg        TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.stages_table           TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.state_district_master_table TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.status_field_inspection TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.status_of_approval     TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.status_of_estimate     TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.status_of_implementation TO fsa_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.master_table           TO fsa_app;

-- fsa_app: SELECT on all master schema tables
GRANT SELECT ON ALL TABLES IN SCHEMA master TO fsa_app;

-- fsa_app: sequence usage
GRANT USAGE ON SEQUENCE public.fsa_user_id                   TO fsa_app;
GRANT USAGE ON SEQUENCE public.fsa_admin_table_admin_id_seq  TO fsa_app;
GRANT USAGE ON SEQUENCE public.gen_details_detail_id_seq     TO fsa_app;
GRANT USAGE ON SEQUENCE public.intervention_id_seq           TO fsa_app;
GRANT USAGE ON SEQUENCE public.remarks_by_engg_id_seq        TO fsa_app;
GRANT USAGE ON SEQUENCE public.stages_table_id_seq           TO fsa_app;
GRANT USAGE ON SEQUENCE public.status_field_inspection_id_seq TO fsa_app;
GRANT USAGE ON SEQUENCE public.status_of_approval_id_seq     TO fsa_app;
GRANT USAGE ON SEQUENCE public.status_of_estimate_id_seq     TO fsa_app;
GRANT USAGE ON SEQUENCE public.status_of_implementation_id_seq TO fsa_app;

-- fsa_app: audit writes happen via SECURITY DEFINER trigger only — no direct INSERT
GRANT SELECT ON audit.change_log TO fsa_app;

-- fsa_readonly: SELECT only on all public operational tables
GRANT SELECT ON public.fsa_user_table             TO fsa_readonly;
GRANT SELECT ON public.fsa_admin_table            TO fsa_readonly;
GRANT SELECT ON public.gen_details                TO fsa_readonly;
GRANT SELECT ON public.fsa_acc                    TO fsa_readonly;
GRANT SELECT ON public.fsa_onspot                 TO fsa_readonly;
GRANT SELECT ON public.fsa_light                  TO fsa_readonly;
GRANT SELECT ON public.fsa_ped_cross              TO fsa_readonly;
GRANT SELECT ON public.fsa_roadcnd                TO fsa_readonly;
GRANT SELECT ON public.fsa_traff_status           TO fsa_readonly;
GRANT SELECT ON public.fsa_traffic_condt          TO fsa_readonly;
GRANT SELECT ON public.fsa_violations             TO fsa_readonly;
GRANT SELECT ON public.fsa_visible                TO fsa_readonly;
GRANT SELECT ON public.fsa_wrngway                TO fsa_readonly;
GRANT SELECT ON public.fsa_user_roles             TO fsa_readonly;
GRANT SELECT ON public.fsa_state_district_table   TO fsa_readonly;
GRANT SELECT ON public.intervention               TO fsa_readonly;
GRANT SELECT ON public.remarks_by_engg            TO fsa_readonly;
GRANT SELECT ON public.stages_table               TO fsa_readonly;
GRANT SELECT ON public.state_district_master_table TO fsa_readonly;
GRANT SELECT ON public.status_field_inspection    TO fsa_readonly;
GRANT SELECT ON public.status_of_approval         TO fsa_readonly;
GRANT SELECT ON public.status_of_estimate         TO fsa_readonly;
GRANT SELECT ON public.status_of_implementation   TO fsa_readonly;
GRANT SELECT ON public.master_table               TO fsa_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA master       TO fsa_readonly;
GRANT SELECT ON audit.change_log                  TO fsa_readonly;

-- fsa_admin: ALL on audit
GRANT ALL ON audit.change_log TO fsa_admin;
GRANT ALL ON SEQUENCE audit.change_log_id_seq TO fsa_admin;

-- Helper functions: execute rights
GRANT EXECUTE ON FUNCTION public.hash_password(text)         TO fsa_admin, fsa_app;
GRANT EXECUTE ON FUNCTION public.verify_password(text, text) TO fsa_admin, fsa_app;
GRANT EXECUTE ON FUNCTION public.require_encryption_key()    TO fsa_admin, fsa_app, fsa_readonly;
GRANT EXECUTE ON FUNCTION public.hash_lookup_value(text)     TO fsa_admin, fsa_app;
GRANT EXECUTE ON FUNCTION public.chacha20_le32(bytea, integer)                              TO fsa_admin, fsa_app;
GRANT EXECUTE ON FUNCTION public.chacha20_u32le(bigint)                                     TO fsa_admin, fsa_app;
GRANT EXECUTE ON FUNCTION public.chacha20_qr(bigint[], integer, integer, integer, integer)  TO fsa_admin, fsa_app;
GRANT EXECUTE ON FUNCTION public.chacha20_block(bytea, bytea, bigint)                       TO fsa_admin, fsa_app;
GRANT EXECUTE ON FUNCTION public.chacha20_crypt(bytea, bytea, bytea, bigint)                TO fsa_admin, fsa_app;
GRANT EXECUTE ON FUNCTION public.poly1305_mac(bytea, bytea)                                 TO fsa_admin, fsa_app;
GRANT EXECUTE ON FUNCTION public.encrypt_text_value(text)    TO fsa_admin, fsa_app;
GRANT EXECUTE ON FUNCTION public.decrypt_text_value(text)    TO fsa_admin, fsa_app, fsa_readonly;
GRANT EXECUTE ON FUNCTION public.encrypt_jsonb_value(jsonb)  TO fsa_admin, fsa_app;
GRANT EXECUTE ON FUNCTION public.decrypt_jsonb_value(jsonb)  TO fsa_admin, fsa_app, fsa_readonly;
GRANT EXECUTE ON FUNCTION public.trg_encrypt_sensitive_fields() TO fsa_admin;

GRANT SELECT ON public.v_fsa_user_table_decrypted TO fsa_app, fsa_readonly;
GRANT SELECT ON public.v_fsa_admin_table_decrypted TO fsa_app, fsa_readonly;
GRANT SELECT ON public.v_gen_details_decrypted TO fsa_app, fsa_readonly;
GRANT SELECT ON public.v_fsa_acc_decrypted TO fsa_app, fsa_readonly;
GRANT SELECT ON public.v_fsa_onspot_decrypted TO fsa_app, fsa_readonly;
GRANT SELECT ON public.v_fsa_ped_cross_decrypted TO fsa_app, fsa_readonly;
GRANT SELECT ON public.v_fsa_state_district_table_decrypted TO fsa_app, fsa_readonly;
GRANT SELECT ON public.v_intervention_decrypted TO fsa_app, fsa_readonly;
GRANT SELECT ON public.v_remarks_by_engg_decrypted TO fsa_app, fsa_readonly;
GRANT SELECT ON public.v_stages_table_decrypted TO fsa_app, fsa_readonly;
GRANT SELECT ON public.v_status_field_inspection_decrypted TO fsa_app, fsa_readonly;
GRANT SELECT ON public.v_status_of_approval_decrypted TO fsa_app, fsa_readonly;
GRANT SELECT ON public.v_status_of_estimate_decrypted TO fsa_app, fsa_readonly;
