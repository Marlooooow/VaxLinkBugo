import { createClient } from 'jsr:@supabase/supabase-js@2'
import {
  maskMobile,
  normalizePhilippineMobile,
  providerResult,
} from '../send-reminder-sms/sms_utils.ts'

const headers = {
  'Content-Type': 'application/json',
  'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers })

const sha256 = async (value: string) => {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return [...new Uint8Array(bytes)].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

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
    return json({ error: 'Enter a valid activation delivery request.' }, 400)
  }
  const guardianId = typeof body.guardian_id === 'string' ? body.guardian_id : ''
  const invitationId = typeof body.invitation_id === 'string' ? body.invitation_id : ''
  const activationCode = typeof body.activation_code === 'string'
    ? body.activation_code.trim().toUpperCase()
    : ''
  if (!guardianId || !invitationId || !activationCode) {
    return json({ error: 'Activation delivery details are incomplete.' }, 400)
  }

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: identity, error: identityError } = await admin.auth.getUser(token)
  if (identityError || !identity.user) return json({ error: 'Please sign in again.' }, 401)
  const { data: actor } = await admin.from('profiles')
    .select('id, facility_id, role, active').eq('id', identity.user.id).maybeSingle()
  if (!actor || actor.active !== true ||
      !['health_worker', 'administrator'].includes(actor.role)) {
    return json({ error: 'Health-worker access is required.' }, 403)
  }

  const { data: invitation } = await admin.from('guardian_invitations').select(
    'id, guardian_id, activation_code_hash, expires_at, status, ' +
    'guardians!inner(id, guardian_code, full_name, facility_id, phone)',
  ).eq('id', invitationId).eq('guardian_id', guardianId).maybeSingle()
  if (!invitation) return json({ error: 'The activation invitation was not found.' }, 404)
  const guardian = invitation.guardians as Record<string, unknown>
  if (guardian.facility_id !== actor.facility_id) {
    return json({ error: 'This guardian is outside your assigned facility.' }, 403)
  }
  if (invitation.status !== 'pending' ||
      new Date(String(invitation.expires_at)).getTime() <= Date.now() ||
      await sha256(activationCode) !== invitation.activation_code_hash) {
    return json({ error: 'The activation invitation is no longer available.' }, 409)
  }
  const phone = normalizePhilippineMobile(String(guardian.phone ?? ''))
  if (!phone) return json({ error: 'The guardian does not have a valid Philippine mobile number.' }, 409)

  const expiry = new Date(String(invitation.expires_at)).toLocaleDateString('en-PH', {
    month: 'short', day: 'numeric', year: 'numeric', timeZone: 'Asia/Manila',
  })
  const message = `VaxLink activation for ${String(guardian.full_name)}. Guardian ID: ${String(guardian.guardian_code)}. Activation code: ${activationCode}. Expires ${expiry}. Keep this code private.`
  let result = {
    accepted: false,
    messageId: null as string | null,
    providerStatus: 'uncertain',
    failureCode: 'NETWORK_UNCERTAIN' as string | null,
  }
  let deliveryStatus = 'uncertain'
  try {
    const form = new URLSearchParams({ apikey: semaphoreKey, number: phone, message })
    if (senderName) form.set('sendername', senderName)
    const response = await fetch('https://api.semaphore.co/api/v4/messages', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: form,
      signal: AbortSignal.timeout(15_000),
    })
    let payload: unknown = null
    try { payload = await response.json() } catch { /* handled by providerResult */ }
    result = providerResult(response.status, payload)
    deliveryStatus = result.accepted ? 'accepted' : 'failed'
  } catch {
    // Never retry automatically because the provider may already have accepted it.
  }

  const masked = maskMobile(phone)
  await admin.from('guardian_invitations').update({
    delivery_channel: 'sms',
    delivery_status: deliveryStatus,
    destination_masked: masked,
    delivered_at: result.accepted ? new Date().toISOString() : null,
    provider_message_id: result.messageId,
    provider_status: result.providerStatus,
    delivery_failure_code: result.failureCode,
  }).eq('id', invitationId)

  await admin.from('audit_logs').insert({
    actor_id: actor.id,
    facility_id: actor.facility_id,
    action: 'guardian_activation_sms_requested',
    entity_type: 'guardian_invitations',
    entity_id: invitationId,
    new_values: {
      guardian_id: guardianId,
      recipient_masked: masked,
      delivery_status: deliveryStatus,
      provider_message_id: result.messageId,
    },
  })

  return json({
    accepted: result.accepted,
    recipient_masked: masked,
    provider_status: result.providerStatus,
  }, result.accepted ? 200 : 502)
})
