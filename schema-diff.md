# FSA Schema Diff

This document compares:

- `fps_schema.sql` - original schema dump
- `fps_schema_secure.sql` - latest encrypted and security-hardened schema

## Quick Checklist

Use this when reviewing the two files side by side.

- [ ] `fps_schema_secure.sql` adds `pgcrypto`
- [ ] `fps_schema_secure.sql` adds roles `fsa_admin`, `fsa_app`, `fsa_readonly`
- [ ] `fps_schema_secure.sql` adds `audit` schema and `audit.change_log`
- [ ] `fsa_user_table_bak` exists only in `fps_schema.sql`
- [ ] `fsa_user_table` adds `email_hash`, bcrypt `CHECK`, and timestamps
- [ ] `fsa_admin_table` adds `admin_email_hash`, bcrypt `CHECK`, and timestamps
- [ ] `fsa_acc.no_of_injuries` changes from `integer` to `character varying`
- [ ] `fsa_acc.no_of_deaths` changes from `integer` to `character varying`
- [ ] `fsa_onspot.lat` changes from `double precision` to `character varying`
- [ ] `fsa_onspot.long` changes from `double precision` to `character varying`
- [ ] public operational tables gain `created_at` and `updated_at`
- [ ] encrypted-field trigger exists only in `fps_schema_secure.sql`
- [ ] audit triggers exist only in `fps_schema_secure.sql`
- [ ] RLS policies exist only in `fps_schema_secure.sql`
- [ ] decrypted views `v_*_decrypted` exist only in `fps_schema_secure.sql`
- [ ] foreign keys are fully enforced in `fps_schema_secure.sql` (`NOT VALID` removed)
- [ ] indexes exist only in `fps_schema_secure.sql`

## Review in This Order

If you want the fastest review path, use this order instead of reading top to bottom.

1. Security foundation
   - markdown: `schema-diff.md:30`
   - SQL refs:
     - `fps_schema_secure.sql:145` for `pgcrypto`
     - `fps_schema_secure.sql:185` for `audit` schema
     - `fps_schema_secure.sql:199` for password hashing
     - `fps_schema_secure.sql:295` for encryption helpers
     - `fps_schema_secure.sql:383` for the master encryption trigger function

2. Authentication tables
   - markdown:
     - `schema-diff.md:82` for `fsa_user_table`
     - `schema-diff.md:105` for `fsa_admin_table`
   - SQL refs:
     - `fps_schema.sql:1053` vs `fps_schema_secure.sql:1015`
     - `fps_schema.sql:801` vs `fps_schema_secure.sql:1060`

3. Core type-changed tables
   - markdown:
     - `schema-diff.md:147` for `fsa_acc`
     - `schema-diff.md:164` for `fsa_onspot`
   - SQL refs:
     - `fps_schema.sql:779` vs `fps_schema_secure.sql:1124`
