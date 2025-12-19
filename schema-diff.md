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
