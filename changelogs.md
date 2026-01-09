# changelogs

## fps_schema_secure.sql — security hardening of fsa road safety db

base file: `fps_schema.sql`  
hardened file: `fps_schema_secure.sql`  
db: postgresql 16

---

### 1. removed non-standard commands

`\restrict` and `\unrestrict` on lines 5 and 1721 are not valid postgresql or psql commands. they likely came from a custom internal pg_dump wrapper. left as-is they would break the script on any standard install.

#### before
```sql
\restrict IwEwdQqfDDfkz2F9uQas9IkfWR64M3A7cuaWN3weNs4NKVeUpsgFbcqWnGKwJlD
-- ... (line 1721)
\unrestrict IwEwdQqfDDfkz2F9uQas9IkfWR64M3A7cuaWN3weNs4NKVeUpsgFbcqWnGKwJlD
```

#### after
both lines removed. no replacement.

---

### 2. added pgcrypto extension

needed for bcrypt password hashing. without it none of the password security in changes 4 onwards is possible.

#### before
no extensions loaded.

#### after
```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

---

### 3. role separation

everything was owned by `postgres` (the superuser). a compromised app connection meant full db access — read, write, drop, anything.

three dedicated roles replace this:

| role | used by | privileges |
|------|---------|------------|
| `fsa_admin` | dbas only | owns all tables, bypasses RLS, full access |
| `fsa_app` | backend application | SELECT/INSERT/UPDATE/DELETE on operational tables |
| `fsa_readonly` | dashboards, reports | SELECT only |

#### before
```sql
ALTER TABLE public.fsa_user_table OWNER TO postgres;
ALTER TABLE public.gen_details     OWNER TO postgres;
-- every table: OWNER TO postgres
```

#### after
```sql
DO $$ BEGIN
    CREATE ROLE fsa_admin WITH LOGIN NOINHERIT BYPASSRLS;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE ROLE fsa_app WITH LOGIN NOINHERIT;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
    CREATE ROLE fsa_readonly WITH LOGIN NOINHERIT;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE public.fsa_user_table OWNER TO fsa_admin;
ALTER TABLE public.gen_details     OWNER TO fsa_admin;
-- every table: OWNER TO fsa_admin
```

the `DO $$ ... EXCEPTION` block makes creation idempotent — running the script twice won't fail if the role already exists.

---

### 4. password hashing

passwords were stored as plain `character varying`. anyone with read access to the db could see every password directly.

three layers of protection added: a CHECK constraint, a helper function pair, and an auto-hash trigger.

#### before
```sql
CREATE TABLE public.fsa_user_table (
    pwd character varying NOT NULL,
    ...
);

CREATE TABLE public.fsa_admin_table (
    admin_pwd character varying,
    ...
);
```

#### after — columns get a CHECK constraint
```sql
CREATE TABLE public.fsa_user_table (
    pwd character varying NOT NULL
        CONSTRAINT pwd_must_be_bcrypt CHECK (pwd LIKE '$2%'),
    ...
);

CREATE TABLE public.fsa_admin_table (
    admin_pwd character varying
        CONSTRAINT admin_pwd_must_be_bcrypt CHECK (admin_pwd LIKE '$2%'),
    ...
);
```

#### after — helper functions
```sql
-- hash a plaintext password (bcrypt, cost 10)
CREATE OR REPLACE FUNCTION public.hash_password(plaintext text)
RETURNS text LANGUAGE sql STRICT SECURITY DEFINER AS $$
    SELECT crypt(plaintext, gen_salt('bf', 10));
$$;

-- check password at login time
CREATE OR REPLACE FUNCTION public.verify_password(plaintext text, hashed text)
RETURNS boolean LANGUAGE sql STRICT SECURITY DEFINER AS $$
    SELECT crypt(plaintext, hashed) = hashed;
$$;
```

#### after — auto-hash triggers
```sql
CREATE OR REPLACE FUNCTION public.trg_hash_user_password()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    -- only hash if value doesn't already look like a bcrypt hash ($2a$, $2b$, $2y$)
    IF NEW.pwd IS NOT NULL AND NEW.pwd NOT LIKE '$2%' THEN
        NEW.pwd := public.hash_password(NEW.pwd);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_hash_user_pwd
    BEFORE INSERT OR UPDATE OF pwd ON public.fsa_user_table
    FOR EACH ROW EXECUTE FUNCTION public.trg_hash_user_password();

-- same pattern for fsa_admin_table.admin_pwd via trg_hash_admin_password()
CREATE TRIGGER trg_hash_admin_pwd
    BEFORE INSERT OR UPDATE OF admin_pwd ON public.fsa_admin_table
    FOR EACH ROW EXECUTE FUNCTION public.trg_hash_admin_password();
```

even if the app sends plaintext on INSERT or UPDATE, the trigger intercepts and stores the bcrypt hash. the CHECK constraint is a second layer — any value not starting with `$2` is rejected outright.

at login time the app now does:
```sql
SELECT userid FROM fsa_user_table
WHERE email = 'user@example.com'
  AND verify_password('submitted_password', pwd) = true;
```

---

### 5. removed fsa_user_table_bak

a backup copy of `fsa_user_table` with no constraints, no primary key, and plaintext passwords. it had no production value and was a direct security liability.

#### before
```sql
CREATE TABLE public.fsa_user_table_bak (
    pwd          character varying,  -- plaintext, no constraint
    email        character varying,  -- no UNIQUE constraint
    userid       bigint,             -- no PRIMARY KEY
    ...
);
ALTER TABLE public.fsa_user_table_bak OWNER TO postgres;
```

#### after
table removed entirely. if historical data from it is needed, import through the secure `fsa_user_table` after hashing passwords with `hash_password()`.

---

### 6. created_at and updated_at timestamps

no timestamps existed on any operational table. there was no way to know when a record was created or last modified.

`created_at` and `updated_at` columns added to all 22 public schema tables, plus a trigger that keeps `updated_at` current automatically.

#### before — example: fsa_acc
```sql
CREATE TABLE public.fsa_acc (
    detail_id          bigint            NOT NULL,
    acc_pattern_onspot character varying,
    no_of_injuries     integer,
    no_of_deaths       integer,
    no_of_accidents    character varying,
    nearest_hosp       character varying,
    acc_id             character varying NOT NULL,
    start_age_range    integer,
    end_age_range      integer,
    age_range          character varying,
    time_frame_acc     character varying,
    edited             boolean DEFAULT false
);
```

#### after
```sql
CREATE TABLE public.fsa_acc (
    detail_id          bigint            NOT NULL,
    acc_pattern_onspot character varying,
    no_of_injuries     integer,
    no_of_deaths       integer,
    no_of_accidents    character varying,
    nearest_hosp       character varying,
    acc_id             character varying NOT NULL,
    start_age_range    integer,
    end_age_range      integer,
    age_range          character varying,
    time_frame_acc     character varying,
    edited             boolean DEFAULT false,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now()
);
```

#### after — auto-update trigger
```sql
CREATE OR REPLACE FUNCTION public.update_timestamp()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ts_fsa_acc
    BEFORE UPDATE ON public.fsa_acc
    FOR EACH ROW EXECUTE FUNCTION public.update_timestamp();
```

applied to all 22 tables: `fsa_user_table`, `fsa_admin_table`, `gen_details`, `fsa_acc`, `fsa_onspot`, `fsa_light`, `fsa_ped_cross`, `fsa_roadcnd`, `fsa_traff_status`, `fsa_traffic_condt`, `fsa_violations`, `fsa_visible`, `fsa_wrngway`, `fsa_state_district_table`, `fsa_user_roles`, `intervention`, `remarks_by_engg`, `stages_table`, `state_district_master_table`, `status_field_inspection`, `status_of_approval`, `status_of_estimate`, `status_of_implementation`.

---

### 7. audit logging

no record of who changed what. if an admin deleted a field inspection record, there was no trace of it anywhere.

a dedicated `audit` schema added with a `change_log` table. triggers on all 21 operational tables capture every INSERT, UPDATE, and DELETE as jsonb snapshots.

#### before
nothing. no audit schema, no audit table, no triggers.

#### after — audit schema and table
```sql
CREATE SCHEMA IF NOT EXISTS audit;

CREATE TABLE audit.change_log (
    id          bigserial    NOT NULL,
    table_name  text         NOT NULL,
    operation   text         NOT NULL CHECK (operation IN ('INSERT','UPDATE','DELETE')),
    row_id      text,
    old_data    jsonb,                          -- full row before change (null for INSERT)
    new_data    jsonb,                          -- full row after change (null for DELETE)
    changed_by  text         NOT NULL DEFAULT current_user,
    changed_at  timestamptz  NOT NULL DEFAULT now(),
    app_user_id text         DEFAULT current_setting('app.current_user_id', true),
    CONSTRAINT change_log_pkey PRIMARY KEY (id)
);
```

#### after — trigger function
```sql
CREATE OR REPLACE FUNCTION audit.log_changes()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_row_id text;
BEGIN
    v_row_id := row_to_json(COALESCE(NEW, OLD))::jsonb ->> 'detail_id';
    IF v_row_id IS NULL THEN
        v_row_id := row_to_json(COALESCE(NEW, OLD))::jsonb ->> 'id';
    END IF;

    INSERT INTO audit.change_log (table_name, operation, row_id, old_data, new_data, app_user_id)
    VALUES (
        TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
        TG_OP,
        v_row_id,
        CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) ELSE NULL END,
        CASE WHEN TG_OP IN ('UPDATE','INSERT') THEN to_jsonb(NEW) ELSE NULL END,
        current_setting('app.current_user_id', true)
    );

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;
```

#### after — attached to all 21 operational tables
```sql
CREATE TRIGGER audit_gen_details
    AFTER INSERT OR UPDATE OR DELETE ON public.gen_details
    FOR EACH ROW EXECUTE FUNCTION audit.log_changes();

-- same for: fsa_acc, fsa_onspot, fsa_light, fsa_ped_cross, fsa_roadcnd,
-- fsa_traff_status, fsa_traffic_condt, fsa_violations, fsa_visible,
-- fsa_wrngway, fsa_user_table, fsa_admin_table, stages_table,
-- intervention, remarks_by_engg, status_field_inspection,
-- status_of_approval, status_of_estimate, status_of_implementation,
-- fsa_state_district_table
```

a row in `audit.change_log` after an UPDATE looks like:
```
table_name  | public.gen_details
operation   | UPDATE
row_id      | 55
old_data    | {"detail_id": 55, "district_code": {"0": "05"}, ...}
new_data    | {"detail_id": 55, "district_code": {"0": "08"}, ...}
changed_by  | fsa_app
changed_at  | 2026-03-07 04:30:00+05:30
app_user_id | 42
```

`fsa_app` can INSERT into `audit.change_log` (the trigger needs it) but cannot SELECT from it — so the app cannot read or tamper with the audit trail. only `fsa_admin` and `fsa_readonly` can read it.

---

### 8. row level security (rls)

`SET row_security = off` was at the top of the original file, meaning any connected user could query any row in any table. a state admin in maharashtra could freely read odisha's data.

rls enabled on 12 tables with state/district-scoped policies. the filter is driven by session variables the app sets at the start of every transaction.

#### before
```sql
SET row_security = off;
-- no ALTER TABLE ENABLE ROW LEVEL SECURITY anywhere
-- no policies
```

#### after — gen_details (root table)
```sql
SET row_security = on;

ALTER TABLE public.gen_details ENABLE ROW LEVEL SECURITY;

CREATE POLICY gen_details_app_policy ON public.gen_details
    AS PERMISSIVE FOR ALL TO fsa_app
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
    AS PERMISSIVE FOR SELECT TO fsa_readonly
    USING (
        (state_code->>'0') = current_setting('app.current_state_code', true)
        AND (
            current_setting('app.current_district_code', true) = ''
            OR (district_code->>'0') = current_setting('app.current_district_code', true)
        )
    );
```

#### after — child tables (policy checks via the fk chain)
```sql
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
    );

-- same pattern for: fsa_onspot, fsa_light, fsa_ped_cross, fsa_roadcnd,
-- fsa_traff_status, fsa_traffic_condt, fsa_violations, fsa_visible,
-- fsa_wrngway, stages_table
```

app usage:
```sql
BEGIN;
  SET LOCAL app.current_state_code    = '21';   -- odisha
  SET LOCAL app.current_district_code = '05';   -- khurda
  SET LOCAL app.current_user_id       = '42';

  SELECT * FROM gen_details;
  -- returns only khurda rows. other states/districts are invisible.
COMMIT;
-- SET LOCAL values are cleared automatically on commit
```

`fsa_admin` has `BYPASSRLS` so admin operations skip all policies.

---

### 9. foreign key enforcement

every fk in the original schema was marked `NOT VALID`. this means postgresql accepted the constraint definition but did not enforce it on existing data. additionally 7 tables had a `detail_id` column with no fk constraint at all.

#### before — all fks had NOT VALID
```sql
ALTER TABLE ONLY public.fsa_acc
    ADD CONSTRAINT detail_id
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id) NOT VALID;

ALTER TABLE ONLY public.fsa_light
    ADD CONSTRAINT fsa_light_detail_id_fkey
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id) NOT VALID;

-- all 10 FKs: NOT VALID
```

#### before — these tables had no fk at all despite having a detail_id column  
`stages_table`, `intervention`, `remarks_by_engg`, `status_field_inspection`, `status_of_approval`, `status_of_estimate`, `status_of_implementation`

#### after — NOT VALID removed everywhere
```sql
ALTER TABLE ONLY public.fsa_acc
    ADD CONSTRAINT detail_id
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);

ALTER TABLE ONLY public.fsa_light
    ADD CONSTRAINT fsa_light_detail_id_fkey
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);
```

#### after — 7 missing fks added
```sql
ALTER TABLE ONLY public.stages_table
    ADD CONSTRAINT stages_table_detail_id_fkey
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);

ALTER TABLE ONLY public.intervention
    ADD CONSTRAINT intervention_detail_id_fkey
        FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id);

-- same for remaining 5 tables
```

---

### 10. indexes on fk columns

no indexes existed anywhere. every join the app does (e.g. `gen_details JOIN fsa_acc`) was a full table scan.

#### before
no indexes.

#### after — 18 fk column indexes
```sql
CREATE INDEX idx_fsa_acc_detail_id           ON public.fsa_acc           (detail_id);
CREATE INDEX idx_fsa_light_detail_id         ON public.fsa_light         (detail_id);
CREATE INDEX idx_fsa_onspot_detail_id        ON public.fsa_onspot        (detail_id);
