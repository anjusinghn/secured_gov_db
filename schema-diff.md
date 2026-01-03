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
     - `fps_schema.sql:858` vs `fps_schema_secure.sql:1151`
   - this is where the storage model changes most clearly:
     - `integer -> character varying`
     - `double precision -> character varying`

4. Encrypted operational/workflow tables
   - markdown:
     - `schema-diff.md:183` for survey tables
     - `schema-diff.md:194` for admin/workflow tables
   - focus on which columns are encrypted vs unchanged

5. Integrity and performance
   - markdown:
     - `schema-diff.md:280` for constraints/indexes/security
   - SQL refs:
     - FKs: `fps_schema.sql:1633` vs `fps_schema_secure.sql:1776`
     - indexes: `fps_schema_secure.sql:1864`

6. Runtime security behavior
   - SQL refs:
     - password triggers: `fps_schema_secure.sql:1905`
     - field encryption triggers: `fps_schema_secure.sql:1916`
     - timestamp triggers: `fps_schema_secure.sql:1992`
     - audit triggers: `fps_schema_secure.sql:2112`
     - RLS: `fps_schema_secure.sql:2204`

7. Read path / decrypted access
   - markdown: `schema-diff.md:355`
   - SQL refs:
     - decrypted views section: `fps_schema_secure.sql:2634`
     - first view: `fps_schema_secure.sql:2650`
   - use this last so you first understand how data is stored, then how it is read back

## Global Diff

### New in `fps_schema_secure.sql`

- refs:
  - `pgcrypto`: `fps_schema_secure.sql:145`
  - `audit` schema: `fps_schema_secure.sql:185`
  - `audit.change_log`: `fps_schema_secure.sql:956`
  - `hash_password()`: `fps_schema_secure.sql:199`
  - `encrypt_text_value()`: `fps_schema_secure.sql:295`
  - `decrypt_text_value()`: `fps_schema_secure.sql:318`
  - `trg_encrypt_sensitive_fields()`: `fps_schema_secure.sql:383`
  - `trg_hash_admin_pwd`: `fps_schema_secure.sql:1905`
  - `trg_encrypt_fsa_user_table`: `fps_schema_secure.sql:1922`
  - RLS start: `fps_schema_secure.sql:2204`
  - decrypted views start: `fps_schema_secure.sql:2634`

- `pgcrypto` extension
- roles: `fsa_admin`, `fsa_app`, `fsa_readonly`
- schema: `audit`
- table: `audit.change_log`
- hashing functions for `pwd` and `admin_pwd`
- AES-256 encryption/decryption helper functions
- timestamp trigger function
- audit logging trigger function
- password hashing triggers
- field encryption triggers
- audit triggers
- RLS policies
- decrypted views `v_*_decrypted`
- FK indexes and RLS-supporting indexes

### Removed from `fps_schema_secure.sql`

- refs:
  - `fsa_user_table_bak`: `fps_schema.sql:1084`
  - `\restrict`: `fps_schema.sql:5`
  - `\unrestrict`: `fps_schema.sql:1721`

- `fsa_user_table_bak`
- psql-only meta commands `\restrict` and `\unrestrict`

### Changed Everywhere

- ownership moved from `postgres` to `fsa_admin`
- many public operational tables add `created_at` and `updated_at`
- foreign keys are enforced directly instead of `NOT VALID`

## Table-by-Table Diff

### Authentication Tables

#### `fsa_user_table`

- refs:
  - original: `fps_schema.sql:1053`
  - secure: `fps_schema_secure.sql:1015`

- new column: `email_hash`
- `pwd` now has bcrypt format `CHECK`
- new columns: `created_at`, `updated_at`
- encrypted columns:
  - `email`
  - `rep_name`
  - `designation`
  - `department`
  - `phone_no`
  - `state_name`
  - `district_name`
  - `police_station`
  - `last_login`
  - `user_file`
- unchanged business columns:
  - `userid`, `user_type`, `user_role`, `terms_cond`, `admin_id`, `user_status`, `state_code`, `district_code`, `ps_code`

#### `fsa_admin_table`

- refs:
  - original: `fps_schema.sql:801`
  - secure: `fps_schema_secure.sql:1060`

- new column: `admin_email_hash`
- `admin_pwd` now has bcrypt format `CHECK`
- new columns: `created_at`, `updated_at`
- encrypted columns:
  - `admin_email`
  - `admin_role`
  - `admin_name`
  - `last_login`
  - `state_name`
  - `district_name`
  - `created_by`
  - `phone_no`
- not encrypted:
  - `admin_pwd` (bcrypt only)

### Core Data Tables

#### `gen_details`

- refs:
  - original: `fps_schema.sql:1186`
  - secure: `fps_schema_secure.sql:1089`

- new columns: `created_at`, `updated_at`
- encrypted columns:
  - `rep_name`
  - `designation`
  - `department`
  - `phone_no`
  - `email`
  - `state`
  - `district`
  - `state_code`
  - `district_code`
  - `police_station`

#### `fsa_acc`

- refs:
  - original: `fps_schema.sql:779`
  - secure: `fps_schema_secure.sql:1124`

- `no_of_injuries`: `integer -> character varying`
- `no_of_deaths`: `integer -> character varying`
- new columns: `created_at`, `updated_at`
- encrypted columns:
  - `acc_pattern_onspot`
  - `nearest_hosp`
  - `age_range`
  - `time_frame_acc`
  - `no_of_injuries`
  - `no_of_deaths`

