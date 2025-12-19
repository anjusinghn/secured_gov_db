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

async function main() {
  const prisma = createClient();

  // Set encryption key for this session — DB triggers use this to encrypt fields
  await prisma.$executeRawUnsafe(`SET app.encryption_key = '${ENCRYPTION_KEY}'`);
  console.log('✓ Set app.encryption_key for session');

  // 0. Clean existing data (reverse FK order — children before parents)
  await prisma.$executeRaw`DELETE FROM status_of_implementation`;
  await prisma.$executeRaw`DELETE FROM status_of_estimate`;
  await prisma.$executeRaw`DELETE FROM status_of_approval`;
  await prisma.$executeRaw`DELETE FROM status_field_inspection`;
