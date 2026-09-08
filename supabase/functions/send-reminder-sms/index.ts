import { createClient } from 'jsr:@supabase/supabase-js@2'
import { groupedReminderMessage, maskMobile, normalizePhilippineMobile, providerResult } from './sms_utils.ts'

const headers = {
  'Content-Type': 'application/json',
  'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers })

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers })
  if (request.method !== 'POST') return json({ error: 'Method not allowed.' }, 405)

  const url = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const semaphoreKey = Deno.env.get('SEMAPHORE_API_KEY')
  const senderName = Deno.env.get('SEMAPHORE_SENDER_NAME')?.trim() ?? ''
  if (!url || !serviceKey || !semaphoreKey) {
    return json({ error: 'SMS delivery is not configured.' }, 503)
  }

  const authorization = request.headers.get('Authorization') ?? ''
  const token = authorization.match(/^Bearer\s+(.+)$/i)?.[1]
  if (!token) return json({ error: 'Please sign in again.' }, 401)

  let body: Record<string, unknown>
  try {
    const parsed = await request.json()
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error()
    body = parsed as Record<string, unknown>
  } catch {
    return json({ error: 'Enter a valid SMS reminder request.' }, 400)
  }
  const submitted = Array.isArray(body.reminder_ids) ? body.reminder_ids : []
  const reminderIds = [...new Set(submitted.filter((id): id is string =>
    typeof id === 'string' && /^[0-9a-f-]{36}$/i.test(id)))]
  if (reminderIds.length === 0 || reminderIds.length !== submitted.length) {
    return json({ error: 'Choose valid reminders.' }, 400)
  }
  if (reminderIds.length > 20) {
    return json({ error: 'Send at most 20 SMS reminders at a time.' }, 400)
  }

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: identity, error: identityError } = await admin.auth.getUser(token)
  if (identityError || !identity.user) return json({ error: 'Please sign in again.' }, 401)
  const { data: actor, error: actorError } = await admin.from('profiles')
    .select('id, facility_id, role, active').eq('id', identity.user.id).maybeSingle()
  if (actorError || !actor || actor.active !== true ||
      !['health_worker', 'administrator'].includes(actor.role)) {
    return json({ error: 'Health-worker access is required.' }, 403)
  }

  const { data: reminders, error: reminderError } = await admin.from('reminders').select(
    'id, guardian_id, child_id, vaccine_id, dose_number, due_on, status, ' +
    'guardians!inner(id, facility_id, phone, reminder_preferences(sms_enabled)), ' +
    'children!inner(full_name), vaccine_definitions!inner(name)',
  ).in('id', reminderIds)
  if (reminderError) return json({ error: 'SMS reminders could not be prepared.' }, 503)
  if (!reminders || reminders.length !== reminderIds.length) {
    return json({ error: 'Some reminders are no longer available. Refresh and try again.' }, 409)
  }

  const targets: Array<{
    reminder: Record<string, unknown>
    phone: string
    masked: string
    childName: string
    vaccineName: string
  }> = []
  for (const raw of reminders) {
    const reminder = raw as Record<string, unknown>
    const guardian = reminder.guardians as Record<string, unknown>
    const child = reminder.children as Record<string, unknown>
    const vaccine = reminder.vaccine_definitions as Record<string, unknown>
    const preferenceRaw = guardian.reminder_preferences
    const preference = Array.isArray(preferenceRaw) ? preferenceRaw[0] : preferenceRaw
    const smsEnabled = preference && typeof preference === 'object' &&
      (preference as Record<string, unknown>).sms_enabled === true
    if (guardian.facility_id !== actor.facility_id) {
      return json({ error: 'Some reminders are outside your assigned facility.' }, 403)
    }
    if (!['upcoming', 'due_today', 'overdue'].includes(String(reminder.status))) {
      return json({ error: 'Only active vaccination reminders can be sent.' }, 409)
    }
    if (!smsEnabled) {
      return json({ error: 'SMS reminders are disabled for one or more selected guardians.' }, 409)
    }
    const phone = normalizePhilippineMobile(String(guardian.phone ?? ''))
    if (!phone) {
      return json({ error: 'A selected guardian does not have a valid Philippine mobile number.' }, 409)
    }
    targets.push({
      reminder,
      phone,
      masked: maskMobile(phone),
      childName: String(child.full_name),
      vaccineName: String(vaccine.name),
    })
  }

  const cutoff = new Date(Date.now() - 10 * 60 * 1000).toISOString()
  const { data: recent, error: recentError } = await admin.from('reminder_sms_deliveries')
    .select('reminder_id').in('reminder_id', reminderIds)
    .in('status', ['sending', 'accepted']).gte('created_at', cutoff)
  if (recentError) return json({ error: 'SMS delivery history could not be checked.' }, 503)
  if (recent && recent.length > 0) {
    return json({ error: 'A selected reminder was already sent or started within the last 10 minutes.' }, 409)
  }

  const groupedTargets = new Map<string, typeof targets>()
  for (const target of targets) {
    const key = `${target.reminder.guardian_id}:${target.reminder.child_id}`
    const group = groupedTargets.get(key) ?? []
    group.push(target)
    groupedTargets.set(key, group)
  }

  const requestId = crypto.randomUUID()
  const followUps: Record<string, unknown>[] = []
  let accepted = 0
  let failed = 0
  let messagesSent = 0
  for (const group of groupedTargets.values()) {
    const first = group[0]
    const message = groupedReminderMessage({
      childName: first.childName,
      reminders: group.map((target) => ({
        vaccineName: target.vaccineName,
        doseNumber: Number(target.reminder.dose_number),
        dueOn: String(target.reminder.due_on),
        status: String(target.reminder.status),
      })),
    })
    const deliveryRows = group.map((target, index) => ({
      delivery_code: `SMS-${Date.now()}-${crypto.randomUUID().replaceAll('-', '').substring(0, 12).toUpperCase()}-${index + 1}`,
      facility_id: actor.facility_id,
      reminder_id: target.reminder.id,
      guardian_id: target.reminder.guardian_id,
      child_id: target.reminder.child_id,
      requested_by: actor.id,
      recipient_masked: target.masked,
      status: 'sending',
      request_id: requestId,
    }))
    const { data: deliveries, error: deliveryError } = await admin
      .from('reminder_sms_deliveries').insert(deliveryRows).select('id, reminder_id')
    if (deliveryError || !deliveries || deliveries.length !== group.length) {
      failed += group.length
      continue
    }

    let result = {
      accepted: false,
      messageId: null as string | null,
      providerStatus: 'uncertain',
      failureCode: 'NETWORK_UNCERTAIN' as string | null,
    }
    let deliveryStatus = 'uncertain'
    try {
      const form = new URLSearchParams({
        apikey: semaphoreKey,
        number: first.phone,
        message,
      })
      if (senderName) form.set('sendername', senderName)
      const response = await fetch('https://api.semaphore.co/api/v4/messages', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: form,
        signal: AbortSignal.timeout(15_000),
      })
      let payload: unknown = null
      try { payload = await response.json() } catch { /* generic failure below */ }
      result = providerResult(response.status, payload)
      deliveryStatus = result.accepted ? 'accepted' : 'failed'
    } catch {
      // Do not retry automatically: the provider may have accepted the request
      // before the connection failed. Staff can verify Semaphore history first.
    }

    await admin.from('reminder_sms_deliveries').update({
      provider_message_id: result.messageId,
      provider_status: result.providerStatus,
      failure_code: result.failureCode,
      status: deliveryStatus,
    }).in('id', deliveries.map((delivery) => delivery.id))

    const outcome = result.accepted ? 'provider_accepted' : 'delivery_failed'
    const notes = result.accepted
      ? 'SMS request accepted by Semaphore. This does not confirm handset delivery.'
      : deliveryStatus === 'uncertain'
      ? 'SMS provider response was uncertain. Verify Semaphore history before retrying.'
      : 'Semaphore rejected the SMS request. Review provider status and contact information.'
    const followUpRows = group.map((target) => ({
      follow_up_code: `FUP-SMS-${Date.now()}-${crypto.randomUUID().replaceAll('-', '').substring(0, 12).toUpperCase()}`,
      reminder_id: target.reminder.id,
      child_id: target.reminder.child_id,
      action: 'sms',
      outcome,
      notes,
      performed_by: actor.id,
    }))
    const { data: savedFollowUps } = await admin
      .from('reminder_follow_ups').insert(followUpRows).select()
    if (savedFollowUps) followUps.push(...savedFollowUps)
    if (result.accepted) {
      accepted += group.length
      messagesSent++
      await admin.from('reminders').update({
        last_contacted_at: new Date().toISOString(),
        delivery_channel: 'sms',
        updated_at: new Date().toISOString(),
      }).in('id', group.map((target) => target.reminder.id))
    } else {
      failed += group.length
    }
  }

  return json({
    requested: targets.length,
    accepted,
    failed,
    messages_sent: messagesSent,
    follow_ups: followUps,
  })
})
