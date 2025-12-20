import { createCipheriv, createDecipheriv, randomBytes } from 'crypto';
import { readFileSync } from 'fs';
import { join } from 'path';
import { PrismaClient, Prisma } from '@prisma/client';
import { Pool } from 'pg';
import { PrismaPg } from '@prisma/adapter-pg';

const ALGORITHM = 'chacha20-poly1305';
const IV_LENGTH = 12; // ChaCha20-Poly1305 uses a 12-byte nonce
const AUTH_TAG_LENGTH = 16;
const PREFIX = 'enc:chacha20:v1:';
const LEGACY_PREFIX = 'enc:v1:'; // AES-256-GCM legacy ciphertext (read-only compat)

function getKey(): Buffer {
  const hex = process.env.ENCRYPTION_KEY;
  if (!hex || hex.length !== 64) {
    throw new Error('ENCRYPTION_KEY must be a 64-character hex string (32 bytes for ChaCha20-Poly1305)');
  }
  return Buffer.from(hex, 'hex');
}

function encrypt(plaintext: string): string {
  const key = getKey();
  const iv = randomBytes(IV_LENGTH);
  const cipher = createCipheriv(ALGORITHM, key, iv, { authTagLength: AUTH_TAG_LENGTH });
  const encrypted = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
