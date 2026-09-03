import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2'

// Activation precedes sign-in. The one-time invitation is the credential;
// neither a submitted guardian ID nor a submitted role is ever trusted.
const headers = {
  'Content-Type': 'application/json',
  'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const uncertain = 'Activation could not be confirmed. Try signing in before trying again.'
const unavailable = 'Activation is temporarily unavailable. Please try again.'
const invalidCode = 'Activation code is invalid or no longer available.'
const activated = (username: string, temporaryPassword: string) => new Response(JSON.stringify({
  activated: true, username, temporary_password: temporaryPassword,
}), { status: 200, headers })
const failure = (error: string, status: number) => new Response(JSON.stringify({ error }), { status, headers })

export function createActivationHandler(getAdmin: () => SupabaseClient | null) {
  return async (request: Request): Promise<Response> => {
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers })
    if (request.method !== 'POST') return failure('Method not allowed.', 405)
    let body: Record<string, unknown>
    try {
      body = await readBody(request)
    } catch {
      return failure('Enter a valid activation request.', 400)
    }
    const code = typeof body.activation_code === 'string' ? body.activation_code.trim().toUpperCase() : ''
    if (!/^ACT-[0-9A-F]{32}$/.test(code)) return failure(invalidCode, 400)

    let accountCreationStarted = false
    try {
      const admin = getAdmin()
      if (!admin) return failure('Server is not configured.', 503)
      const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(code))
      const hash = Array.from(new Uint8Array(digest)).map(b => b.toString(16).padStart(2, '0')).join('')
      const { data: invitation, error: invitationError } = await admin.from('guardian_invitations')
        .select('id, guardian_id, expires_at, status').eq('activation_code_hash', hash).maybeSingle()
      if (invitationError) return failure(unavailable, 503)
      if (!invitation || invitation.status !== 'pending' ||
          !Number.isFinite(Date.parse(invitation.expires_at)) || Date.parse(invitation.expires_at) <= Date.now()) {
        return failure(invalidCode, 400)
      }
      const { data: guardian, error: guardianError } = await admin.from('guardians')
        .select('profile_id, access_status, facility_id, guardian_code, first_name, last_name, full_name').eq('id', invitation.guardian_id).maybeSingle()
      if (guardianError) return failure(unavailable, 503)
      if (!guardian || guardian.profile_id || guardian.access_status !== 'invitation_pending') return failure(invalidCode, 400)
      const { data: facility, error: facilityError } = await admin.from('facilities')
        .select('active').eq('id', guardian.facility_id).maybeSingle()
      if (facilityError) return failure(unavailable, 503)
      if (!facility?.active) return failure(invalidCode, 400)
      const username = String(guardian.guardian_code).trim().toLowerCase()
      const temporaryPassword = temporaryPasswordFor(guardian.last_name, guardian.first_name, guardian.full_name)
      const { data: existingProfile, error: profileError } = await admin.from('profiles')
        .select('id').eq('username', username).maybeSingle()
      if (profileError) return failure(unavailable, 503)
      if (existingProfile) return failure('That username is already in use.', 409)

      accountCreationStarted = true
      const { data: created, error: createError } = await admin.auth.admin.createUser({
        email: `${username}@auth.vaxlink-bugo.local`, password: temporaryPassword, email_confirm: true,
        user_metadata: { username },
      })
      if (createError || !created.user) return failure('Online access could not be created. Try signing in or contact the health center.', 409)
      const userId = created.user.id
      const { error: linkError } = await admin.rpc('activate_guardian_profile', {
        invitation_id: invitation.id, auth_user_id: userId, requested_username: username,
      })
      if (!linkError) return activated(username, temporaryPassword)

      // A transport error is not evidence that PostgreSQL rolled back. Check
      // for a committed link and never delete an account on an uncertain result.
      const { data: linked, error: checkError } = await admin.from('guardians')
        .select('profile_id').eq('id', invitation.guardian_id).maybeSingle()
      if (checkError) return failure(uncertain, 503)
      if (linked?.profile_id === userId) return activated(username, temporaryPassword)
      const confirmedRollback = /^[0-9A-Z]{5}$/.test(linkError.code ?? '')
      if (!confirmedRollback) return failure(uncertain, 503)
      // Only the account made by this request is eligible for cleanup, and
      // only after a database SQLSTATE confirms a rolled-back transaction.
      const { error: cleanupError } = await admin.auth.admin.deleteUser(userId)
      if (cleanupError) return failure(uncertain, 503)
      return failure('The invitation is no longer available. Ask the health center for a new code.', 409)
    } catch {
      return failure(accountCreationStarted ? uncertain : unavailable, 503)
    }
  }
}

function temporaryPasswordFor(lastName: unknown, firstName: unknown, fullName: unknown): string {
  const clean = (value: unknown) => String(value ?? '').toLowerCase().replace(/[^a-z0-9]/g, '')
  const parts = `${clean(lastName)}_${clean(firstName)}`
  const fallback = clean(fullName) || 'guardian'
  return (parts === '_' ? fallback : parts).length >= 8
    ? (parts === '_' ? fallback : parts)
    : `${parts === '_' ? fallback : parts}123`
}

async function readBody(request: Request): Promise<Record<string, unknown>> {
  const reader = request.body?.getReader()
  if (!reader) throw new Error('Missing request')
  const chunks: Uint8Array[] = []
  let size = 0
  try {
    for (;;) {
      const { value, done } = await reader.read()
      if (done) break
      size += value.byteLength
      if (size > 4096) { await reader.cancel(); throw new Error('Request too large') }
      chunks.push(value)
    }
  } finally { reader.releaseLock() }
  const bytes = new Uint8Array(size)
  let offset = 0
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength }
  const body = JSON.parse(new TextDecoder().decode(bytes))
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error('Invalid request')
  return body
}
