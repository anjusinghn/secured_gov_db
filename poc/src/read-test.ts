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
  viewName: string,
  columns: string[],
  idCol: string,
) {
  console.log(`\n━━━ ${tableName} (BASE → ciphertext) ━━━`);
  const colList = [idCol, ...columns].join(', ');
  const baseRows = await prisma.$queryRawUnsafe<AnyRow[]>(`SELECT ${colList} FROM ${tableName}`);
  for (const row of baseRows) {
    console.log(`  ${idCol}=${row[idCol]}`);
    for (const col of columns) {
      console.log(`    ${col.padEnd(24)} = ${trunc(String(row[col] ?? '(null)'))}`);
    }
  }

  console.log(`  ↓ ${viewName} (VIEW → plaintext)`);
  const viewRows = await prisma.$queryRawUnsafe<AnyRow[]>(`SELECT ${colList} FROM ${viewName}`);
  for (const row of viewRows) {
    const vals = columns.map(c => `${c}=${trunc(String(row[c] ?? '(null)'), 40)}`).join('  ');
    console.log(`  ${idCol}=${row[idCol]}  ${vals}`);
  }

  if (baseRows.length === 0) {
    console.log('  ⚠ No rows found');
  }
}
