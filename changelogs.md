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
