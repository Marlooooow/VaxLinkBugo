import { createClient } from 'jsr:@supabase/supabase-js@2'

const headers = { 'Content-Type': 'application/json' }

Deno.serve(async (request) => {
  if (request.method !== 'POST') return response({ error: 'Method not allowed.' }, 405)
  const url = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const geminiKey = Deno.env.get('GEMINI_API_KEY')
  if (!url || !anonKey || !serviceKey || !geminiKey) {
    return response({ error: 'Server advisory configuration is incomplete.' }, 500)
  }

  const authorization = request.headers.get('Authorization') ?? ''
  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  })
  const { data: userData } = await caller.auth.getUser()
  if (!userData.user) return response({ error: 'Authentication required.' }, 401)

  const admin = createClient(url, serviceKey, { auth: { persistSession: false } })
  const { data: profile } = await admin
    .from('profiles')
    .select('facility_id, role, active')
    .eq('id', userData.user.id)
    .maybeSingle()
  if (!profile?.active || !['health_worker', 'administrator'].includes(profile.role)) {
    return response({ error: 'Health-worker access required.' }, 403)
  }

  const [reminders, appointments, inventory] = await Promise.all([
    admin.from('reminders')
      .select('status, vaccine_id, children!inner(facility_id)')
      .eq('children.facility_id', profile.facility_id)
      .in('status', ['due_today', 'overdue', 'upcoming']),
    admin.from('appointments').select('status, vaccine_id').eq('facility_id', profile.facility_id),
    admin.from('vaccine_inventory').select(
      'vaccine_id, reorder_level, vaccine_definitions(name), '
      + 'vaccine_batches(quantity, safety_status, expiry_date, packaging_intact, cold_chain_verified, vvm_status)',
    ).eq('facility_id', profile.facility_id),
  ])
  if (reminders.error || appointments.error || inventory.error) {
    return response({ error: 'Facility statistics could not be loaded.' }, 500)
  }

  const reminderCounts = countBy(reminders.data ?? [], 'status')
  const waitlisted = (appointments.data ?? []).filter((item) => item.status === 'waitlisted').length
  const today = new Date().toISOString().slice(0, 10)
  const stock = (inventory.data ?? []).map((item) => ({
    vaccine_id: item.vaccine_id,
    vaccine_name: Array.isArray(item.vaccine_definitions)
      ? item.vaccine_definitions[0]?.name
      : item.vaccine_definitions?.name,
    usable_doses: (item.vaccine_batches ?? [])
      .filter((batch: Record<string, unknown>) =>
        batch.safety_status === 'usable' &&
        batch.packaging_intact === true &&
        batch.cold_chain_verified === true &&
        ['acceptable', 'not_applicable'].includes(String(batch.vvm_status ?? '')) &&
        String(batch.expiry_date ?? '') >= today)
      .reduce((sum: number, batch: Record<string, unknown>) => sum + Number(batch.quantity ?? 0), 0),
    reorder_level: item.reorder_level,
  }))
  const snapshot = { reminder_counts: reminderCounts, waitlisted_appointments: waitlisted, stock }

  const prompt = `You produce non-clinical operational advisories for a Philippine barangay vaccination facility.
Use only the aggregate JSON below. Never diagnose, determine vaccine eligibility, alter PNIP dates, or claim clinical authority.
Return a JSON array of at most 5 items. Each item must contain: type (delayed_vaccination, stock_risk, or waitlist_pressure), severity (low, medium, or high), title, summary, rationale, recommended_action, and optional vaccine_id. Be factual and concise.
AGGREGATES: ${JSON.stringify(snapshot)}`

  const gemini = await fetch(
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': geminiKey },
      body: JSON.stringify({
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
        generationConfig: { responseMimeType: 'application/json', temperature: 0.2 },
      }),
    },
  )
  if (!gemini.ok) return response({ error: 'The advisory provider is unavailable.' }, 502)
  const body = await gemini.json()
  const text = body?.candidates?.[0]?.content?.parts?.[0]?.text
  let generated: Array<Record<string, unknown>>
  try {
    generated = JSON.parse(text ?? '[]')
  } catch {
    return response({ error: 'The advisory response was invalid.' }, 502)
  }

  const now = new Date().toISOString()
  const rows = generated.slice(0, 5).map((item, index) => ({
    insight_code: `AI-${Date.now()}-${index + 1}`,
    facility_id: profile.facility_id,
    type: allowed(item.type, ['delayed_vaccination', 'stock_risk', 'waitlist_pressure'], 'delayed_vaccination'),
    severity: allowed(item.severity, ['low', 'medium', 'high'], 'low'),
    title: String(item.title ?? 'Operational advisory').slice(0, 120),
    summary: String(item.summary ?? '').slice(0, 500),
    rationale: String(item.rationale ?? '').slice(0, 700),
    recommended_action: String(item.recommended_action ?? '').slice(0, 500),
    vaccine_id: stock.some((entry) => entry.vaccine_id === item.vaccine_id) ? item.vaccine_id : null,
    source_snapshot: snapshot,
    analysis_provider: 'google-gemini',
    analysis_version: 'gemini-2.5-flash-v1',
    generated_at: now,
  }))
  const { data: saved, error: saveError } = await admin.from('advisory_insights').insert(rows).select('id')
  if (saveError) return response({ error: 'Advisories could not be saved.' }, 500)

  await admin.from('audit_logs').insert({
    actor_id: userData.user.id,
    action: 'generate_advisory_insights',
    entity_type: 'facility',
    entity_id: profile.facility_id,
    new_values: { insight_count: saved.length, provider: 'google-gemini' },
  })
  return response({ generated: saved.length }, 200)
})

function response(body: Record<string, unknown>, status: number) {
  return new Response(JSON.stringify(body), { status, headers })
}

function countBy(rows: Array<Record<string, unknown>>, key: string) {
  return rows.reduce<Record<string, number>>((counts, row) => {
    const value = String(row[key] ?? 'unknown')
    counts[value] = (counts[value] ?? 0) + 1
    return counts
  }, {})
}

function allowed(value: unknown, values: string[], fallback: string) {
  const normalized = String(value ?? '')
  return values.includes(normalized) ? normalized : fallback
}
