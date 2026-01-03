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
