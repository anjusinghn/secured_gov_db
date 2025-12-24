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
  });
  console.log('✓ Seeded fsa_user_roles');

  // 2. Seed state_district_master_table (no PK → Prisma marks @@ignore → raw SQL)
  await prisma.$executeRaw`
    INSERT INTO state_district_master_table (state_name, district_name, state_code, district_code, s_no)
    VALUES ('Odisha', 'Khurda', '21', '05', 1), ('Odisha', 'Cuttack', '21', '06', 2)
    ON CONFLICT DO NOTHING
  `;
  console.log('✓ Seeded state_district_master_table');

  // 3. Seed users
  // - pwd: plaintext → DB trigger `trg_hash_user_pwd` bcrypt-hashes it
  // - email, rep_name, etc.: plaintext → DB trigger `trg_encrypt_fsa_user_table` encrypts them
  // - email_hash: pass empty string → DB trigger computes SHA-256 hash from email
  const user1 = await prisma.fsa_user_table.create({
    data: {
      pwd: 'SecurePass123!',
      email: 'rajesh.kumar@gov.in',
      email_hash: '', // trigger overwrites with SHA-256 hash
      rep_name: 'Rajesh Kumar',
      designation: 'Assistant Engineer',
      department: 'Public Works Department',
      phone_no: '+91-9876543210',
      user_type: 'AE',
      user_role: 'Assistant Engineer',
      terms_cond: true,
      user_status: true,
      state_code: '21',
      district_code: '05',
      state_name: 'Odisha',
      district_name: 'Khurda',
      ps_code: 'PS001',
      police_station: 'Chandrasekharpur PS',
      login_status: false,
      last_login: new Date().toISOString(),
      user_file: { '0': '/uploads/id_card_001.pdf' },
    },
  });
  console.log(`✓ Seeded user: userid=${user1.userid}`);

  const user2 = await prisma.fsa_user_table.create({
    data: {
      pwd: 'AnotherPass456!',
      email: 'priya.sharma@gov.in',
      email_hash: '', // trigger overwrites
      rep_name: 'Priya Sharma',
      designation: 'Junior Engineer',
      department: 'Road Transport',
      phone_no: '+91-9123456780',
      user_type: 'JE',
      user_role: 'Junior Engineer',
      terms_cond: true,
      user_status: true,
