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
  await prisma.$executeRaw`DELETE FROM remarks_by_engg`;
  await prisma.$executeRaw`DELETE FROM intervention`;
  await prisma.$executeRaw`DELETE FROM stages_table`;
  await prisma.$executeRaw`DELETE FROM fsa_ped_cross`;
  await prisma.$executeRaw`DELETE FROM fsa_state_district_table`;
  await prisma.$executeRaw`DELETE FROM fsa_light`;
  await prisma.$executeRaw`DELETE FROM fsa_traff_status`;
  await prisma.$executeRaw`DELETE FROM fsa_visible`;
  await prisma.$executeRaw`DELETE FROM fsa_roadcnd`;
  await prisma.$executeRaw`DELETE FROM fsa_acc`;
  await prisma.$executeRaw`DELETE FROM fsa_onspot`;
  await prisma.$executeRaw`DELETE FROM gen_details`;
  await prisma.$executeRaw`DELETE FROM fsa_admin_table`;
  await prisma.$executeRaw`DELETE FROM fsa_user_table`;
  await prisma.$executeRaw`DELETE FROM state_district_master_table`;
  await prisma.$executeRaw`DELETE FROM fsa_user_roles`;
  console.log('✓ Cleaned existing data');

  // 1. Seed user roles
  await prisma.fsa_user_roles.createMany({
    data: [
      { user_type: 'SE', user_role: 'State Engineer' },
      { user_type: 'AE', user_role: 'Assistant Engineer' },
      { user_type: 'JE', user_role: 'Junior Engineer' },
      { user_type: 'PO', user_role: 'Police Officer' },
    ],
    skipDuplicates: true,
