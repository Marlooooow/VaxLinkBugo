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
  let targetGuardianId = guardianId
  if (requestId) {
    const { data, error } = await admin.from('guardian_password_reset_requests')
      .select('id, guardian_id, status')
      .eq('id', requestId).maybeSingle()
    if (error) {
      console.error('guardian password reset: request lookup failed', error)
      return response({
        error: 'The password-reset request could not be loaded.',
        stage: 'request_lookup',
        database_code: error.code ?? null,
        database_message: error.message ?? null,
        database_details: error.details ?? null,
        database_hint: error.hint ?? null,
      }, 500)
    }
    if (!data) return response({ error: 'The password-reset request was not found.' }, 404)
    // A notification screen may still hold a request that was completed from
    // Family Details. Authorized staff may safely repeat the reset so the
    // notification path remains usable and returns a fresh temporary password.
    resetRequest = data
    targetGuardianId = String(data.guardian_id)
  }

  if (!targetGuardianId) return response({ error: 'A reset request or guardian is required.' }, 400)
  const { data: guardianRow, error: guardianError } = await admin.from('guardians')
    .select('id, guardian_code, profile_id, facility_id, first_name, last_name, full_name')
    .eq('id', targetGuardianId).maybeSingle()
  if (guardianError) return response({ error: 'The guardian account could not be loaded.' }, 500)
  guardian = guardianRow as Record<string, unknown> | null
  if (!guardian?.profile_id) return response({ error: 'Guardian account not found.' }, 404)
  if (guardian.facility_id !== staff.facility_id) return response({ error: 'Not authorized.' }, 403)

  const clean = (value: unknown) => String(value ?? '').toLowerCase().replace(/[^a-z0-9]/g, '')
  const username = String(guardian.guardian_code).trim().toLowerCase()
  const base = `${clean(guardian.last_name)}_${clean(guardian.first_name)}`
  const defaultPassword = (base === '_' ? 'guardian' : base).length >= 8
    ? (base === '_' ? 'guardian' : base)
    : `${base === '_' ? 'guardian' : base}123`
  const profileId = String(guardian.profile_id)
  const { data: authAccount, error: authLookupError } = await admin.auth.admin.getUserById(profileId)
  if (authLookupError || !authAccount.user) {
    console.error('guardian password reset: linked Auth account missing', authLookupError)
    return response({ error: 'The guardian login account is not linked correctly. Contact the administrator.' }, 409)
  }

  // Resetting a password must not rewrite the Auth email. Rewriting it can
  // fail for an otherwise valid account when that identity already exists.
  let temporaryPassword = defaultPassword
  let { error: authError } = await admin.auth.admin.updateUserById(profileId, {
    password: temporaryPassword,
  })

  // Some projects enforce upper/lowercase, digit, symbol, or a longer minimum.
  // Preserve the requested name-based format first, then retry with a strong
  // temporary variant only when Supabase rejects that password's strength.
  const passwordRejected = authError && (
    authError.code === 'weak_password' ||
    authError.message.toLowerCase().includes('password')
  )
  if (passwordRejected) {
    temporaryPassword = `${defaultPassword[0].toUpperCase()}${defaultPassword.slice(1)}#${new Date().getUTCFullYear()}`
    const retry = await admin.auth.admin.updateUserById(profileId, {
      password: temporaryPassword,
    })
    authError = retry.error
  }

  if (authError) {
    console.error('guardian password reset: Auth update rejected', {
      code: authError.code,
      message: authError.message,
    })
    return response({ error: 'Supabase Auth rejected the password reset. Check the linked guardian login account.' }, 409)
  }
  const { error: identityError } = await admin.rpc('synchronize_guardian_login_identity', {
    target_guardian_id: guardian.id, resolver_id: actor.user.id, requested_username: username,
  })
  if (identityError) return response({ error: 'Password changed, but the Guardian ID username could not be synchronized.' }, 503)

  // Both entry points must close a pending request. Previously only the
  // notification path called a separate RPC, which made that path fail even
  // though resetting from Family Details succeeded.
  let completion = admin.from('guardian_password_reset_requests')
    .update({
      status: 'completed',
      resolved_by: actor.user.id,
      resolved_at: new Date().toISOString(),
    })
    .eq('status', 'pending')
  completion = resetRequest
    ? completion.eq('id', resetRequest.id)
    : completion.eq('guardian_id', guardian.id)
  const { error: completionError } = await completion
  if (completionError) {
    console.error('guardian password reset: request completion failed', completionError)
    return response({ error: 'Password changed, but the reset request could not be completed.' }, 503)
  }

  const { error: auditError } = await admin.from('audit_logs').insert({
    actor_id: actor.user.id,
    facility_id: guardian.facility_id,
    action: 'guardian_password_reset',
    entity_type: 'guardians',
    entity_id: String(guardian.id),
    new_values: {
      guardian_id: guardian.id,
      profile_id: guardian.profile_id,
      reset_request_id: resetRequest?.id ?? null,
    },
  })
  if (auditError) console.error('guardian password reset: audit insert failed', auditError)

  return response({
    reset: true,
    login_id: String(guardian.guardian_code).trim(),
    temporary_password: temporaryPassword,
  })
})
