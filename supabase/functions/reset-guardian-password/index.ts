import { createClient } from 'jsr:@supabase/supabase-js@2'

const headers = {
  'Content-Type': 'application/json',
  'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const response = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), { status, headers })

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers })
  if (request.method !== 'POST') return response({ error: 'Method not allowed.' }, 405)
  const url = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const token = request.headers.get('Authorization')?.replace(/^Bearer\s+/i, '')
  if (!url || !serviceKey || !token) return response({ error: 'Unauthorized.' }, 401)

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
  const { data: actor } = await admin.auth.getUser(token)
  if (!actor.user) return response({ error: 'Unauthorized.' }, 401)
  const { data: staff } = await admin.from('profiles').select('facility_id, role, active')
    .eq('id', actor.user.id).maybeSingle()
  if (!staff?.active || !['health_worker', 'administrator'].includes(staff.role)) {
    return response({ error: 'Only active health workers can reset passwords.' }, 403)
  }
  let body: Record<string, unknown>
  try { body = await request.json() } catch { return response({ error: 'Invalid request.' }, 400) }
  const requestId = typeof body.request_id === 'string' ? body.request_id : ''
  const guardianId = typeof body.guardian_id === 'string' ? body.guardian_id : ''
  let resetRequest: any = null
  let guardian: Record<string, unknown> | null = null
  if (requestId) {
    const result = await admin.from('guardian_password_reset_requests')
      .select('id, guardian_id, status, guardians(id, profile_id, facility_id, first_name, last_name, full_name)')
      .eq('id', requestId).eq('status', 'pending').maybeSingle()
    resetRequest = result.data
    guardian = resetRequest?.guardians as Record<string, unknown> | null
  } else if (guardianId) {
    const result = await admin.from('guardians')
      .select('id, guardian_code, profile_id, facility_id, first_name, last_name, full_name')
      .eq('id', guardianId).maybeSingle()
    guardian = result.data as Record<string, unknown> | null
  }
  if (!guardian?.profile_id) return response({ error: 'Guardian account not found.' }, 404)
  if (guardian.facility_id !== staff.facility_id) return response({ error: 'Not authorized.' }, 403)

  const clean = (value: unknown) => String(value ?? '').toLowerCase().replace(/[^a-z0-9]/g, '')
  const username = String(guardian.guardian_code).trim().toLowerCase()
  const base = `${clean(guardian.last_name)}_${clean(guardian.first_name)}`
  const temporaryPassword = (base === '_' ? 'guardian' : base).length >= 8
    ? (base === '_' ? 'guardian' : base)
    : `${base === '_' ? 'guardian' : base}123`
  const profileId = String(guardian.profile_id)
  const { error: authError } = await admin.auth.admin.updateUserById(profileId, {
    email: `${username}@auth.vaxlink-bugo.local`,
    email_confirm: true,
    password: temporaryPassword,
  })
  if (authError) return response({ error: 'The guardian password could not be reset.' }, 409)
  const { error: identityError } = await admin.rpc('synchronize_guardian_login_identity', {
    target_guardian_id: guardian.id, resolver_id: actor.user.id, requested_username: username,
  })
  if (identityError) return response({ error: 'Password changed, but the Guardian ID username could not be synchronized.' }, 503)
  if (resetRequest) {
    const { error: finalizeError } = await admin.rpc('complete_guardian_password_reset', {
      target_request_id: resetRequest.id, resolver_id: actor.user.id,
    })
    if (finalizeError) return response({ error: 'Password changed, but the reset request could not be finalized.' }, 503)
  }
  return response({ reset: true, temporary_password: temporaryPassword })
})
