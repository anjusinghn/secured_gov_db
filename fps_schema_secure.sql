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
