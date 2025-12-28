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

async function main() {
  const prisma = createClient();
  await prisma.$executeRawUnsafe(`SET app.encryption_key = '${ENCRYPTION_KEY}'`);

  console.log('╔═══════════════════════════════════════════════════════════════════════╗');
  console.log('║  DB-Side Encryption: All 18 Encrypted Tables — Base vs Decrypted View  ║');
  console.log('╚═══════════════════════════════════════════════════════════════════════╝');

  await compareTable(prisma, 'fsa_user_table', 'v_fsa_user_table_decrypted',
    ['email', 'email_hash', 'rep_name', 'phone_no', 'designation', 'department', 'state_name', 'district_name', 'police_station', 'last_login', 'user_file'], 'userid');

  await compareTable(prisma, 'fsa_admin_table', 'v_fsa_admin_table_decrypted',
    ['admin_email', 'admin_name', 'phone_no', 'state_name', 'district_name', 'created_by', 'last_login', 'admin_role'], 'admin_id');

  await compareTable(prisma, 'gen_details', 'v_gen_details_decrypted',
    ['rep_name', 'designation', 'department', 'phone_no', 'email', 'state', 'district', 'police_station', 'state_code', 'district_code'], 'detail_id');

  await compareTable(prisma, 'fsa_onspot', 'v_fsa_onspot_decrypted',
    ['adjoining_or_junction_no', 'junction_name', 'landmark_name', 'landmark_dist', 'name_of_stretch', 'lat', 'long', 'onspot_images'], 'onspot_id');

  await compareTable(prisma, 'fsa_acc', 'v_fsa_acc_decrypted',
    ['nearest_hosp', 'acc_pattern_onspot', 'no_of_injuries', 'no_of_deaths', 'age_range', 'time_frame_acc'], 'acc_id');

  await compareTable(prisma, 'fsa_ped_cross', 'v_fsa_ped_cross_decrypted',
    ['remarks'], 'ped_self_park_t_rash_id');

  await compareTable(prisma, 'fsa_state_district_table', 'v_fsa_state_district_table_decrypted',
    ['state_admin_name', 'district_admin_name', 'state_roa_name', 'district_roa_name'], 'state_code');

  await compareTable(prisma, 'stages_table', 'v_stages_table_decrypted',
    ['remarks_by_engg', 'admin_name', 'admin_email', 'upload_docs_intervention', 'upload_docs_estimation', 'admin_role'], 'detail_id');

  await compareTable(prisma, 'intervention', 'v_intervention_decrypted',
    ['admin_name', 'admin_email', 'uploaded_docs', 'admin_role'], 'id');

  await compareTable(prisma, 'remarks_by_engg', 'v_remarks_by_engg_decrypted',
    ['admin_name', 'admin_email', 'admin_role'], 'id');

  await compareTable(prisma, 'status_field_inspection', 'v_status_field_inspection_decrypted',
    ['admin_name', 'admin_email', 'admin_role'], 'id');

  await compareTable(prisma, 'status_of_approval', 'v_status_of_approval_decrypted',
    ['admin_name', 'admin_email', 'admin_role'], 'id');

  await compareTable(prisma, 'status_of_estimate', 'v_status_of_estimate_decrypted',
    ['admin_name', 'admin_email', 'uploaded_docs', 'admin_role'], 'id');

  await compareTable(prisma, 'status_of_implementation', 'v_status_of_implementation_decrypted',
    ['admin_name', 'admin_email', 'admin_role'], 'id');
