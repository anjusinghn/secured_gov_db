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
      state_code: '21',
      district_code: '06',
      state_name: 'Odisha',
      district_name: 'Cuttack',
      ps_code: 'PS002',
      police_station: 'Cuttack Sadar PS',
      login_status: false,
      last_login: new Date().toISOString(),
      user_file: { '0': '/uploads/id_card_002.pdf' },
    },
  });
  console.log(`✓ Seeded user: userid=${user2.userid}`);

  // 4. Seed admin
  // - admin_pwd: plaintext → trigger bcrypt-hashes
  // - admin_email, admin_name, etc.: plaintext → trigger encrypts
  // - admin_email_hash: pass empty string → trigger computes SHA-256 hash
  await prisma.fsa_admin_table.create({
    data: {
      admin_email: 'admin@fsaroadindia.gov.in',
      admin_email_hash: '', // trigger overwrites
      admin_name: 'Suresh Patel',
      admin_pwd: 'AdminPass789!',
      admin_role_id: BigInt(1),
      admin_role: 'Super Admin',
      login_status: false,
      user_status: true,
      state_name: 'Odisha',
      district_name: 'Khurda',
      state_code: '21',
      district_code: '05',
      created_by: 'System',
      phone_no: '+91-9000000001',
      last_login: new Date().toISOString(),
    },
  });
  console.log('✓ Seeded fsa_admin_table');

  // 5. Seed gen_details
  // jsonb fields (rep_name, designation, etc.) are encrypted by trigger
  const detail = await prisma.gen_details.create({
    data: {
      userid: user1.userid,
      rep_name: { '0': 'Rajesh Kumar' },
      designation: { '0': 'Assistant Engineer' },
      department: { '0': 'Public Works Department' },
      phone_no: { '0': '+91-9876543210' },
      email: { '0': 'rajesh.kumar@gov.in' },
      state: { '0': 'Odisha' },
      district: { '0': 'Khurda' },
      state_code: { '0': '21' },
      district_code: { '0': '05' },
      edited: false,
      start_date: '2025-01-15',
      end_date: '2025-03-15',
      delete_status: false,
      police_station: 'Chandrasekharpur PS',
      ps_code: 'PS001',
    },
  });
  console.log(`✓ Seeded gen_details: detail_id=${detail.detail_id}`);

  // 6. Seed fsa_onspot
  await prisma.fsa_onspot.create({
    data: {
      detail_id: detail.detail_id,
      onspot_id: `ONSPOT-${detail.detail_id}-001`,
      lat: '20.2961',
      long: '85.8245',
      highway_no: 'NH-16',
      land_use_pattern: 'Urban',
      hotspot_type: 'Black Spot',
      junction_type: 'T-Junction',
      junction_name: 'Rasulgarh Square',
      junction_formation: 'Signalized',
      stretch_type: 'Straight',
      stretch_shape: 'Flat',
      no_of_lanes: '4',
      median_presence: 'Yes',
      median_opening: 'Yes',
      speed_of_all_vehicles: '50-60 km/h',
      adjoining_or_junction_no: 'JN-16-A',
      landmark_name: 'Rasulgarh Bus Stand',
      landmark_type: 'Bus Stop',
      landmark_dist: '200m',
      name_of_stretch: 'Rasulgarh to Vani Vihar',
      onspot_images: { '0': '/images/onspot_001.jpg', '1': '/images/onspot_002.jpg' },
      edited: false,
      delete_status: false,
    },
  });
  console.log('✓ Seeded fsa_onspot');

  // 7. Seed fsa_acc
  await prisma.fsa_acc.create({
    data: {
      detail_id: detail.detail_id,
      acc_id: `ACC-${detail.detail_id}-001`,
      acc_pattern_onspot: 'Head-on collision',
      no_of_injuries: '3',
      no_of_deaths: '1',
      no_of_accidents: '5',
      nearest_hosp: 'Capital Hospital, Bhubaneswar',
      start_age_range: 20,
      end_age_range: 40,
      age_range: '20-40',
      time_frame_acc: '18:00-21:00',
      edited: false,
    },
  });
  console.log('✓ Seeded fsa_acc');

  const detailId = Number(detail.detail_id);

  await prisma.fsa_ped_cross.create({
    data: {
      ped_self_park_t_rash_id: `PED-${detailId}-001`,
      detail_id: detail.detail_id,
      ped_animal_cross_lead_acc: 'Yes',
      ped_animal_cross_spot_reason: 'No zebra crossing',
      road_eng_sol_ped_ani: 'Install pedestrian crossing',
      rash_drivers: 'Yes',
      remarks: 'High pedestrian traffic area near bus stand, needs immediate attention',
      edited: false,
      delete_status: false,
    },
  });
  console.log('✓ Seeded fsa_ped_cross');

  // 9. Seed fsa_light (Prisma client — has @id)
  await prisma.fsa_light.create({
    data: {
      light_id: `LIGHT-${detailId}-001`,
      detail_id: detail.detail_id,
      light_avail: 'Yes',
      switch_type: 'Automatic Timer',
      non_avail_light: null,
      light_photos: { '0': '/images/light_001.jpg', '1': '/images/light_002.jpg' },
      edited: false,
      delete_status: false,
    },
  });
  console.log('✓ Seeded fsa_light');

  // 10. Seed fsa_traff_status (Prisma client — has @id)
  await prisma.fsa_traff_status.create({
    data: {
      traff_status_id: `TRAFF-${detailId}-001`,
      detail_id: detail.detail_id,
      signal_avail: 'Yes',
      signal_visible: 'Partially',
      signal_working: 'Yes',
      signal_timer_work: 'Yes',
      signal_need: 'No',
      signal_photos: { '0': '/images/signal_001.jpg' },
      signboards_avail: 'Yes',
      signboards_visible: 'Yes',
      signboards_photos: { '0': '/images/signboard_001.jpg', '1': '/images/signboard_002.jpg' },
      road_markings_avail: 'Partial',
      road_markings_photos: { '0': '/images/road_marking_001.jpg' },
      edited: false,
      delete_status: false,
    },
  });
  console.log('✓ Seeded fsa_traff_status');

  // 11. Seed fsa_visible (Prisma client — has @id)
  await prisma.fsa_visible.create({
    data: {
      visible_id: `VIS-${detailId}-001`,
      detail_id: detail.detail_id,
      visib_obstruct_by_objs: 'Trees and Billboards',
      atspot_accident_cause: 'Limited sight distance',
      road_eng_sol: 'Remove obstructions, install mirrors',
      visib_photos: { '0': '/images/visibility_001.jpg', '1': '/images/visibility_002.jpg' },
      is_visib_obstructed: 'Yes',
      delete_status: false,
    },
  });
  console.log('✓ Seeded fsa_visible');

  // 12. Seed fsa_roadcnd (@@ignore — raw SQL required)
  await prisma.$executeRaw`
    INSERT INTO fsa_roadcnd
      (roadcnd_id, detail_id, road_issue, road_defects, road_photos, road_eng_sol_roadcnd, delete_status)
    VALUES
      (${`ROAD-${detailId}-001`}, ${detailId}, 'Pothole cluster', 'Surface cracks and potholes',
       ${JSON.stringify({ '0': '/images/road_damage_001.jpg', '1': '/images/road_damage_002.jpg' })}::jsonb,
       'Patch repair and resurfacing', false)
  `;
  console.log('✓ Seeded fsa_roadcnd');

  // @@ignore tables — raw SQL required
  await prisma.$executeRaw`
    INSERT INTO fsa_state_district_table
      (state_admin_id, state_admin_name, state_code, district_admin_id, district_admin_name, district_code,
       state_roa_id, state_roa_name, roa_state_code, roa_district_code, district_roa_id, district_roa_name, multiple_districts)
    VALUES
      (1, 'Suresh Patel', '21', 1, 'Amit Verma', '05',
       1, 'Road Safety Officer Odisha', ARRAY['21'], ARRAY['05','06'], 1, 'Khurda RO', ARRAY['Khurda','Cuttack'])
  `;
  console.log('✓ Seeded fsa_state_district_table');

  await prisma.stages_table.create({
    data: {
      detail_id: detail.detail_id,
      status_field_inspection: 'Completed',
      intervention: 'In Progress',
      status_of_estimate: 'Pending',
      status_of_approval: 'Pending',
      status_of_implementation: 'Not Started',
      remarks_by_engg: 'Site inspection completed, intervention measures identified',
      time_updated: new Date().toISOString(),
      admin_name: 'Suresh Patel',
      admin_role: 'Super Admin',
      admin_email: 'admin@fsaroadindia.gov.in',
      admin_id: '1',
      upload_docs_intervention: '/docs/intervention_report_001.pdf',
      upload_docs_estimation: '/docs/estimation_draft_001.pdf',
    },
  });
  console.log('✓ Seeded stages_table');

  await prisma.$executeRaw`
    INSERT INTO intervention (detail_id, time_updated, admin_name, admin_role, admin_email, admin_id, uploaded_docs)
    VALUES (${detailId}, ${new Date().toISOString()}, 'Suresh Patel', 'Super Admin', 'admin@fsaroadindia.gov.in', '1', '/docs/intervention_photo_001.jpg')
  `;
  console.log('✓ Seeded intervention');

  await prisma.$executeRaw`
    INSERT INTO remarks_by_engg (detail_id, time_updated, admin_name, admin_role, admin_email, admin_id)
    VALUES (${detailId}, ${new Date().toISOString()}, 'Amit Verma', 'District Engineer', 'amit.verma@gov.in', '2')
  `;
  console.log('✓ Seeded remarks_by_engg');

  await prisma.$executeRaw`
    INSERT INTO status_field_inspection (detail_id, time_updated, admin_name, admin_role, admin_email, admin_id)
    VALUES (${detailId}, ${new Date().toISOString()}, 'Suresh Patel', 'Super Admin', 'admin@fsaroadindia.gov.in', '1')
  `;
  console.log('✓ Seeded status_field_inspection');

  await prisma.$executeRaw`
