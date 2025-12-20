import 'dotenv/config';
import { PrismaClient } from '@prisma/client';
import { Pool } from 'pg';
import { PrismaPg } from '@prisma/adapter-pg';

const ENCRYPTION_KEY = process.env.ENCRYPTION_KEY!;

function createClient() {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) throw new Error('DATABASE_URL env var is required');
  const pool = new Pool({ connectionString });
  const adapter = new PrismaPg(pool);
  return new PrismaClient({ adapter });
}

function trunc(val: string | null | undefined, len = 55): string {
  if (!val) return '(null)';
  return val.length > len ? val.substring(0, len) + '...' : val;
}

type AnyRow = Record<string, unknown>;

async function compareTable(
  prisma: PrismaClient,
  tableName: string,
