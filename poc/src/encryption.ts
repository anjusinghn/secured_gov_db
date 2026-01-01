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
  const authTag = cipher.getAuthTag();
  return `${PREFIX}${iv.toString('hex')}:${authTag.toString('hex')}:${encrypted.toString('hex')}`;
}

function decrypt(ciphertext: string): string {
  if (typeof ciphertext !== 'string') return ciphertext;

  if (ciphertext.startsWith(PREFIX)) {
    const parts = ciphertext.slice(PREFIX.length).split(':');
    if (parts.length !== 3) return ciphertext;
    const [ivHex, authTagHex, encHex] = parts;
    const key = getKey();
    const decipher = createDecipheriv(ALGORITHM, key, Buffer.from(ivHex, 'hex'), { authTagLength: AUTH_TAG_LENGTH });
    decipher.setAuthTag(Buffer.from(authTagHex, 'hex'));
    return decipher.update(Buffer.from(encHex, 'hex')).toString('utf8') + decipher.final('utf8');
  }

  if (ciphertext.startsWith(LEGACY_PREFIX)) {
    const parts = ciphertext.slice(LEGACY_PREFIX.length).split(':');
    if (parts.length !== 3) return ciphertext;
    const [ivHex, authTagHex, encHex] = parts;
    const key = getKey();
    const decipher = createDecipheriv('aes-256-gcm', key, Buffer.from(ivHex, 'hex'));
    decipher.setAuthTag(Buffer.from(authTagHex, 'hex'));
    return decipher.update(Buffer.from(encHex, 'hex')).toString('utf8') + decipher.final('utf8');
  }

  return ciphertext;
}

// Parses `/// @encrypted` annotations from the Prisma schema file.
// Uses a simple state machine: track current model, flag when annotation is seen, capture next field name.
function parseEncryptedFields(): Map<string, Set<string>> {
  const schemaPath = join(__dirname, '..', 'prisma', 'schema.prisma');
  const schema = readFileSync(schemaPath, 'utf8');
  const map = new Map<string, Set<string>>();
  let currentModel: string | null = null;
  let nextFieldEncrypted = false;

  for (const line of schema.split('\n')) {
    const trimmed = line.trim();

    const modelMatch = trimmed.match(/^model\s+(\w+)\s*\{/);
    if (modelMatch) {
      currentModel = modelMatch[1];
      nextFieldEncrypted = false;
      continue;
    }

    if (trimmed === '}') {
      currentModel = null;
      nextFieldEncrypted = false;
      continue;
    }

    if (trimmed === '/// @encrypted') {
      nextFieldEncrypted = true;
      continue;
    }

    if (nextFieldEncrypted && currentModel) {
      const fieldMatch = trimmed.match(/^(\w+)\s+/);
      if (fieldMatch) {
        if (!map.has(currentModel)) map.set(currentModel, new Set());
        map.get(currentModel)!.add(fieldMatch[1]);
      }
      nextFieldEncrypted = false;
    } else {
      nextFieldEncrypted = false;
    }
  }

  return map;
}

function encryptFields(data: unknown, encryptedFieldSet: Set<string>): unknown {
  if (data === null || data === undefined) return data;

  if (Array.isArray(data)) {
    return data.map((item) => encryptFields(item, encryptedFieldSet));
  }

  if (typeof data === 'object') {
    const result: Record<string, unknown> = { ...(data as Record<string, unknown>) };
    for (const field of encryptedFieldSet) {
      if (field in result && typeof result[field] === 'string') {
        result[field] = encrypt(result[field] as string);
      }
    }
    return result;
  }

  return data;
}

function decryptFields(result: unknown, encryptedFieldSet: Set<string>): unknown {
  if (result === null || result === undefined) return result;

  if (Array.isArray(result)) {
    return result.map((item) => decryptFields(item, encryptedFieldSet));
  }

  if (typeof result === 'object') {
    const obj = result as Record<string, unknown>;
    for (const field of encryptedFieldSet) {
      if (field in obj && typeof obj[field] === 'string') {
        obj[field] = decrypt(obj[field] as string);
      }
    }
    return obj;
  }

  return result;
}

function createEncryptionExtension() {
  const encryptedFieldsMap = parseEncryptedFields();

  console.log('[encryption] Loaded encrypted field map:');
  for (const [model, fields] of encryptedFieldsMap) {
    console.log(`  ${model}: ${[...fields].join(', ')}`);
  }

  return Prisma.defineExtension({
    name: 'chacha20-poly1305-encryption',
    query: {
      $allModels: {
