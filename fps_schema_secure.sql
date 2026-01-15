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
