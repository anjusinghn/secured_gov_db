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
