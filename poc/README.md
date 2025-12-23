# FSA Encrypted POC

Application-layer ChaCha20-Poly1305 encryption for PII columns in the FSA Road Safety Database, using Prisma ORM with a custom client extension.

## What This Demonstrates

- **Transparent encryption**: PII fields (names, emails, phone numbers, addresses) are encrypted before writing to PostgreSQL and decrypted on read — all through a Prisma Client Extension.
- **Ciphertext in DB**: When viewed directly (via DbGate, pgAdmin, or raw SQL), encrypted columns show `enc:chacha20:v1:<iv>:<authTag>:<ciphertext>`.
- **Plaintext through app**: The application reads decrypted values transparently.
- **Non-PII untouched**: IDs, codes, booleans, timestamps, and FK columns remain plaintext for indexing and joins.
- **Password hashing preserved**: `pwd` and `admin_pwd` use DB-level bcrypt triggers — NOT application encryption.

## Prerequisites

- Node.js 18+
- Docker (for PostgreSQL and DbGate)
- PostgreSQL running at `localhost:55432` with database `fsa_encrypted_poc`

## Setup

```bash
npm install
npx prisma generate
```

## Run

```bash
# Seed sample data (encrypted on write)
npx tsx src/seed.ts

# Verify encryption: shows decrypted vs encrypted reads
npx tsx src/read-test.ts
```

## View in DbGate

```bash
docker compose -f docker-compose.dbgate.yml up -d
```

Open http://localhost:3100 — browse `fsa_user_table`, `fsa_admin_table`, etc. to see encrypted ciphertext in PII columns.

## Encrypted Fields

| Table | Encrypted Columns |
|-------|------------------|
| `fsa_user_table` | email, rep_name, designation, department, phone_no, state_name, district_name, police_station |
| `fsa_admin_table` | admin_email, admin_name, phone_no, state_name, district_name, created_by |
| `gen_details` | police_station |
| `fsa_onspot` | highway_no, junction_name, landmark_name, name_of_stretch |
| `intervention` | admin_name, admin_email |
| `remarks_by_engg` | admin_name, admin_email |
| `stages_table` | admin_name, admin_email |
| `status_*` tables | admin_name, admin_email |

## Encryption Format

```
enc:chacha20:v1:<iv_hex>:<authTag_hex>:<ciphertext_hex>
```

- Algorithm: ChaCha20-Poly1305
- Nonce: 12 bytes (random per field per write)
- Auth Tag: 16 bytes (integrity verification via Poly1305)
- Key: 32 bytes from `ENCRYPTION_KEY` env var (hex-encoded)
- Legacy `enc:v1:` (AES-256-GCM) ciphertext is transparently decrypted for backward compatibility
