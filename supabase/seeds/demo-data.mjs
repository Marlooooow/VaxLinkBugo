// Explicit, opt-in synthetic fixtures. Not an automatic migration or app fallback.
import { createHash } from 'node:crypto';

export const PROJECT_REF = 'oytdqiavxqowrzqpowvr';
export const SEED_ID = 'vaxlink-demo-v1';
export const ACCOUNT_SPECS = [
  { key: 'admin', username: 'demo.admin', password: 'admin123', name: 'Bugo Demo Administrator', role: 'administrator' },
  { key: 'staff', username: 'demo.healthworker', password: 'healthworkeradmin123', name: 'Maria Reyes (Demo)', role: 'health_worker' },
  { key: 'maria', username: 'demo.maria', password: 'maria123', name: 'Maria Santos (Demo)', role: 'guardian' },
  { key: 'paolo', username: 'demo.paolo', password: 'paolo123', name: 'Paolo Mendoza (Demo)', role: 'guardian' },
  { key: 'grace', username: 'demo.grace', password: 'grace123', name: 'Grace Villanueva (Demo)', role: 'guardian' },
];
export function demoId(key) {
  const b = createHash('sha256').update(`${SEED_ID}:${key}`).digest().subarray(0, 16);
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  const h = b.toString('hex');
  return `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`;
}
export const FACILITY_ID = demoId('facility');
const iso = d => d.toISOString().slice(0, 10);
export const addDays = (date, days) => iso(new Date(Date.parse(`${date}T00:00:00Z`) + days * 86400000));
export function addMonths(date, months) {
  const d = new Date(`${date}T00:00:00Z`);
  const target = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + months, 1));
  const last = new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)).getUTCDate();
  target.setUTCDate(Math.min(d.getUTCDate(), last));
  return iso(target);
}
const at = (date, hour = '09:00') => `${date}T${hour}:00+08:00`;
export function definitions(birthDate) {
  return [
    { vaccine: 'bcg', dose: 1, date: birthDate },
    { vaccine: 'hepatitis_b', dose: 1, date: birthDate },
    ...[1,2,3].flatMap(dose => ['pentavalent','opv','pcv'].map(vaccine => ({
      vaccine, dose, date: addDays(birthDate, [0,42,70,98][dose]),
    }))),
    { vaccine: 'ipv', dose: 1, date: addDays(birthDate, 98) },
    { vaccine: 'ipv', dose: 2, date: addMonths(birthDate, 9) },
    { vaccine: 'mmr', dose: 1, date: addMonths(birthDate, 9) },
    { vaccine: 'mmr', dose: 2, date: addMonths(birthDate, 12) },
  ];
}

export function buildDemoData(accounts, anchorDate) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(anchorDate) || iso(new Date(`${anchorDate}T00:00:00Z`)) !== anchorDate) {
    throw new Error('Use a valid YYYY-MM-DD anchor date.');
  }
  for (const spec of ACCOUNT_SPECS) {
    if (!/^[\da-f]{8}(-[\da-f]{4}){3}-[\da-f]{12}$/i.test(accounts[spec.key] ?? '')) {
      throw new Error(`Missing Auth UUID for ${spec.key}.`);
    }
  }
  const data = {};
  const add = (table, row) => (data[table] ??= []).push(row);
  const staff = accounts.staff;
  const stamp = at(anchorDate, '08:00');
  add('facilities', { id: FACILITY_ID, facility_code: 'FAC-BUGO-DEMO-V1', name: 'Barangay Bugo Health Center (Demo)', barangay: 'Bugo', city: 'Cagayan de Oro City' });
  for (const spec of ACCOUNT_SPECS) add('profiles', {
    id: accounts[spec.key], facility_id: FACILITY_ID, username: spec.username, full_name: spec.name, role: spec.role,
  });
  for (const [key, name, sex, age] of [
    ['maria','Maria Santos','female',32], ['paolo','Paolo Mendoza','male',30],
    ['grace','Grace Villanueva','female',29], ['elena','Elena Dela Cruz','female',35],
  ]) {
    add('guardians', { id: demoId(key), guardian_code: `DEMO-G-${key.toUpperCase()}`, profile_id: accounts[key] ?? null,
      registered_by: staff, facility_id: FACILITY_ID, full_name: `${name} (Demo)`, sex,
      birth_date: addMonths(anchorDate, -age * 12), phone: null, email: null,
      address: 'Synthetic demo household — no real address', access_status: accounts[key] ? 'active' : 'offline' });
    add('reminder_preferences', { guardian_id: demoId(key), in_app_enabled: !!accounts[key], sms_enabled: false, email_enabled: false, advance_notice_days: 3 });
  }
  const vaccines = [
    ['bcg','BCG','BCG',4], ['hepatitis_b','HEPB','Hepatitis B',1], ['pentavalent','PENTA','Pentavalent',30],
    ['opv','OPV','OPV',30], ['pcv','PCV','PCV',20], ['ipv','IPV','IPV',3], ['mmr','MMR','MMR',6],
  ];
  for (const [vaccine, code, name, quantity] of vaccines) {
    add('vaccine_definitions', { id: vaccine, vaccine_code: `VAC-${code}`, name });
    add('vaccine_inventory', { id: demoId(`stock:${vaccine}`), facility_id: FACILITY_ID, vaccine_id: vaccine, reorder_level: 5 });
    add('vaccine_batches', { id: demoId(`batch:${vaccine}`), inventory_id: demoId(`stock:${vaccine}`),
      lot_number: `DEMO-${code}-001`, batch_code: `DEMO-BAT-${code}`, expiry_date: addMonths(anchorDate,12),
      quantity_received: quantity, quantity, manufacturer: 'Synthetic demo supplier', delivery_reference: `DEMO-DEL-${code}`,
      received_by: staff, packaging_intact: true, cold_chain_verified: true, vvm_status: 'acceptable',
      safety_status: 'usable', safety_notes: 'Synthetic safety assessment; not evidence of actual vaccine handling.',
      safety_reviewed_by: staff, safety_reviewed_at: stamp, received_at: stamp });
    add('inventory_transactions', { id: demoId(`receipt:${vaccine}`), transaction_code: `DEMO-ITXN-${code}`,
      inventory_id: demoId(`stock:${vaccine}`), batch_id: demoId(`batch:${vaccine}`), transaction_type: 'received',
      quantity_delta: quantity, balance_before: 0, balance_after: quantity,
      reason: 'Synthetic opening stock for database workflow testing', reference_number: `DEMO-DEL-${code}`, performed_by: staff, created_at: stamp });
  }
  const children = [
    ['sofia','Sofia Santos','female','maria','mother',addMonths(anchorDate,-11),2],
    ['princess','Princess Santos','female','maria','mother',addMonths(anchorDate,-20),15],
    ['mateo','Mateo Santos','male','maria','mother',addMonths(anchorDate,-4),8],
    ['miguel','Miguel Reyes','male','maria','aunt',addMonths(anchorDate,-6),12],
    ['ana','Ana Cruz','female','maria','aunt',addMonths(anchorDate,-2),5],
    ['lia','Lia Mendoza','female','paolo','father',addDays(anchorDate,-42),2],
    ['noah','Noah Villanueva','male','grace','mother',addDays(anchorDate,-16),2],
    ['carlo','Carlo Dela Cruz','male','elena','mother',addMonths(anchorDate,-18),15],
  ];
  for (const [key,name,sex,guardian,relationship,birthDate,completedCount] of children) {
    const childId = demoId(key);
    add('children', { id: childId, child_code: `DEMO-CH-${key.toUpperCase()}`, facility_id: FACILITY_ID,
      registered_by: staff, full_name: `${name} (Demo)`, sex, birth_date: birthDate,
      address: 'Synthetic demo household — no real address', birth_place: 'Demo facility' });
    add('guardian_child_links', { id: demoId(`link:${key}`), guardian_id: demoId(guardian), child_id: childId,
      relationship, is_primary: true, status: 'approved', requested_by: accounts[guardian] ?? staff,
      reviewed_by: staff, reviewed_at: stamp });
    add('first_visit_reviews', { id: demoId(`review:${key}`), review_code: `DEMO-FVR-${key.toUpperCase()}`,
      child_id: childId, has_documented_previous_vaccinations: true, reviewed_by: staff, reviewed_at: stamp });
    const schedule = definitions(birthDate);
    const done = new Map();
    for (const dose of schedule.slice(0, completedCount)) {
      if (dose.date > anchorDate) throw new Error('A demo history record cannot be future-dated.');
      done.set(`${dose.vaccine}:${dose.dose}`, dose.date);
      add('vaccination_records', { id: demoId(`record:${key}:${dose.vaccine}:${dose.dose}`),
        vaccination_code: `DEMO-VAX-${key.toUpperCase()}-${dose.vaccine.toUpperCase()}-${dose.dose}`,
        child_id: childId, vaccine_id: dose.vaccine, dose_number: dose.dose, administered_on: dose.date,
        external_facility_name: 'Demonstration previous facility', external_health_worker_name: 'Demonstration clinician',
        evidence_type: 'synthetic_demo', source: 'previous_record', status: 'recorded',
        notes: 'Synthetic vaccination history for testing only; not a clinical record. No local inventory consumed.', recorded_by: staff, recorded_at: stamp });
    }
    for (const dose of schedule) {
      const completed = done.has(`${dose.vaccine}:${dose.dose}`);
      const previous = done.get(`${dose.vaccine}:${dose.dose - 1}`);
      if (!completed && dose.dose > 1 && !previous) continue;
      const interval = previous ? (dose.vaccine === 'ipv' ? addMonths(previous,4) : addDays(previous,28)) : dose.date;
      const due = interval > dose.date ? interval : dose.date;
      add('reminders', { id: demoId(`reminder:${key}:${dose.vaccine}:${dose.dose}`),
        reminder_code: `DEMO-REM-${key.toUpperCase()}-${dose.vaccine.toUpperCase()}-${dose.dose}`,
        guardian_id: demoId(guardian), child_id: childId, vaccine_id: dose.vaccine, dose_number: dose.dose, due_on: due,
        status: completed ? 'completed' : due < anchorDate ? 'overdue' : due === anchorDate ? 'due_today' : 'upcoming',
        delivery_channel: 'in_app', is_read: completed, created_at: stamp });
    }
  }
  for (const [key,vaccine,days,status] of [
    ['sofia','mmr',14,'scheduled'], ['mateo','ipv',7,'waitlisted'],
    ['lia','pentavalent',0,'scheduled'], ['noah','pentavalent',26,'scheduled'],
  ]) {
    const reminder = data.reminders.find(r => r.child_id === demoId(key) && r.vaccine_id === vaccine && r.dose_number === 1);
    if (!reminder || reminder.status === 'completed') throw new Error('Appointment must link to an incomplete reminder.');
    add('appointments', { id: demoId(`appointment:${key}`), appointment_code: `DEMO-APT-${key.toUpperCase()}`,
      guardian_id: reminder.guardian_id, reminder_id: reminder.id, child_id: reminder.child_id, vaccine_id: vaccine,
      dose_number: 1, facility_id: FACILITY_ID, scheduled_for: at(addDays(anchorDate,days)), pnip_due_date: reminder.due_on,
      priority: reminder.due_on < anchorDate ? 'catch_up' : 'routine', status, source: 'health_worker',
      reason: status === 'waitlisted' ? 'DEMO: awaiting clinic session allocation; no dose reserved.' : 'Synthetic appointment for workflow testing; not a real booking.', created_by: staff, created_at: stamp });
    // Added only after appointments exist, to satisfy the circular foreign key.
    reminder.appointment_id = demoId(`appointment:${key}`);
  }
  add('appointment_offers', { id: demoId('offer:sofia'), appointment_id: demoId('appointment:sofia'), offer_code: 'DEMO-OFFER-SOFIA',
    offered_for: at(addDays(anchorDate,2)), expires_at: at(addDays(anchorDate,1),'18:00'), status: 'pending', created_at: stamp });
  add('child_link_requests', { id: demoId('request:maria'), request_code: 'DEMO-CLR-MARIA', guardian_id: demoId('maria'),
    child_name: 'Demo Child Link Review', birth_date: addDays(anchorDate,-28), sex: 'female', relationship: 'mother', status: 'pending', created_at: stamp });
  const overdue = data.reminders.filter(r => r.child_id === demoId('sofia') && r.status === 'overdue');
  add('advisory_insights', { id: demoId('insight:sofia'), insight_code: 'DEMO-AI-SOFIA', facility_id: FACILITY_ID,
    type: 'delayed_vaccination', severity: 'high', title: 'Demo: overdue follow-up',
    summary: `Sofia Santos (Demo) has ${overdue.length} overdue first-dose reminders in this synthetic scenario.`,
    rationale: 'Synthetic fixture based on the application schedule; not generated by an AI provider and not clinical advice.',
    recommended_action: 'Review the child record and eligibility before contacting the guardian.', child_id: demoId('sofia'),
    source_entity_ids: overdue.map(r => r.id), source_snapshot: { synthetic: true, anchor_date: anchorDate, overdue_count: overdue.length },
    analysis_provider: 'synthetic_seed', analysis_version: SEED_ID, status: 'new_insight', generated_at: stamp });
  return data;
}

const literal = value => value === null ? 'null' : typeof value === 'boolean' || typeof value === 'number'
  ? String(value) : `'${(typeof value === 'object' ? JSON.stringify(value) : value).replaceAll("'", "''")}'`;
const insert = (table, row, suffix = '') => `insert into public.${table} (${Object.keys(row).join(',')}) values (${Object.values(row).map(literal).join(',')})${suffix};`;
export function buildDemoSeed(accounts, anchorDate) {
  const data = buildDemoData(accounts, anchorDate);
  const counts = Object.fromEntries(Object.entries(data).map(([table,rows]) => [table,rows.length]));
  const order = ['facilities','profiles','guardians','reminder_preferences','vaccine_definitions','vaccine_inventory','vaccine_batches',
    'inventory_transactions','children','guardian_child_links','first_visit_reviews','vaccination_records','reminders','appointments',
    'appointment_offers','child_link_requests','advisory_insights'];
  const lines = [];
  for (const table of order) for (const row of data[table] ?? []) {
    const copy = { ...row };
    if (table === 'reminders') delete copy.appointment_id;
    lines.push(insert(table,copy,table === 'vaccine_definitions' ? ' on conflict (id) do nothing' : ''));
  }
  for (const reminder of data.reminders.filter(r => r.appointment_id)) {
    lines.push(`update public.reminders set appointment_id=${literal(reminder.appointment_id)} where id=${literal(reminder.id)};`);
  }
  lines.push(insert('audit_logs', { actor_id: accounts.staff, facility_id: FACILITY_ID, action: 'demo_seed_initialized',
    entity_type: 'demo_seed', entity_id: SEED_ID, new_values: { synthetic: true, anchor_date: anchorDate, counts } }));
  const sql = `-- Synthetic demo only; no password or API key belongs in this file.
begin;
select pg_advisory_xact_lock(hashtextextended('${SEED_ID}',0));
do $demo_seed$
begin
  if exists (select 1 from public.audit_logs where entity_type='demo_seed' and entity_id='${SEED_ID}' and action='demo_seed_initialized') then
    return; -- Never reset edits, inventory, reminders, or dates on a repeat run.
  end if;
  ${lines.join('\n  ')}
end;
$demo_seed$;
commit;`;
  return { sql, data, counts, anchorDate };
}
