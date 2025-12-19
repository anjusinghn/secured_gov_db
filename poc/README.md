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
