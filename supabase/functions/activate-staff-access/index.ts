import { createClient } from 'jsr:@supabase/supabase-js@2'

const headers = {
  'Content-Type': 'application/json',
  'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const response = (body: Record<string, unknown>, status: number) =>
  new Response(JSON.stringify(body), { status, headers })

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers })
  if (request.method !== 'POST') return response({ error: 'Method not allowed.' }, 405)

  const url = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!url || !serviceKey) return response({ error: 'Staff activation is temporarily unavailable.' }, 503)

  let body: Record<string, unknown>
  try {
    body = await request.json()
  } catch {
    return response({ error: 'Enter a valid activation request.' }, 400)
  }

  const code = typeof body.activation_code === 'string'
    ? body.activation_code.trim().toUpperCase()
    : ''
  if (!/^STF-ACT-[0-9A-F]{32}$/.test(code)) {
    return response({ error: 'Staff activation code is invalid or no longer available.' }, 400)
  }

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(code))
  const hash = Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('')

  const { data: invitation, error: invitationError } = await admin
    .from('staff_invitations')
    .select('id, staff_member_id, expires_at, status')
    .eq('activation_code_hash', hash)
    .maybeSingle()
  if (invitationError) return response({ error: 'Staff activation is temporarily unavailable.' }, 503)
  if (!invitation ||
      invitation.status !== 'pending' ||
      !Number.isFinite(Date.parse(invitation.expires_at)) ||
      Date.parse(invitation.expires_at) <= Date.now()) {
    return response({ error: 'Staff activation code is invalid or no longer available.' }, 400)
  }

  const { data: staff, error: staffError } = await admin
    .from('staff_members')
    .select('id, staff_code, profile_id, facility_id, status, first_name, last_name, full_name')
    .eq('id', invitation.staff_member_id)
    .maybeSingle()
  if (staffError) return response({ error: 'Staff activation is temporarily unavailable.' }, 503)
  if (!staff || staff.profile_id || staff.status !== 'invitation_pending') {
    return response({ error: 'Staff activation code is invalid or no longer available.' }, 400)
  }

  const { data: facility, error: facilityError } = await admin
    .from('facilities')
    .select('active')
    .eq('id', staff.facility_id)
    .maybeSingle()
  if (facilityError) return response({ error: 'Staff activation is temporarily unavailable.' }, 503)
  if (!facility?.active) {
    return response({ error: 'Staff activation code is invalid or no longer available.' }, 400)
  }

  const username = String(staff.staff_code).trim().toLowerCase()
  const temporaryPassword = passwordFor(staff.last_name, staff.first_name, staff.full_name)
  const { data: existingProfile, error: profileError } = await admin
    .from('profiles')
    .select('id')
    .eq('username', username)
    .maybeSingle()
  if (profileError) return response({ error: 'Staff activation is temporarily unavailable.' }, 503)
  if (existingProfile) return response({ error: 'That Staff ID is already active.' }, 409)

  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email: `${username}@auth.vaxlink-bugo.local`,
    password: temporaryPassword,
    email_confirm: true,
    user_metadata: { username },
  })
  if (createError || !created.user) {
    return response({ error: 'Staff access could not be created. Contact the administrator.' }, 409)
  }

  const userId = created.user.id
  const { error: linkError } = await admin.rpc('activate_staff_profile', {
    invitation_id: invitation.id,
    auth_user_id: userId,
    requested_username: username,
  })
  if (!linkError) {
    return response({
      activated: true,
      username,
      temporary_password: temporaryPassword,
    }, 200)
  }

  const { data: linked, error: checkError } = await admin
    .from('staff_members')
    .select('profile_id')
    .eq('id', staff.id)
    .maybeSingle()
  if (checkError) {
    return response({ error: 'Activation could not be confirmed. Try signing in before trying again.' }, 503)
  }
  if (linked?.profile_id === userId) {
    return response({
      activated: true,
      username,
      temporary_password: temporaryPassword,
    }, 200)
  }

  const confirmedRollback = /^[0-9A-Z]{5}$/.test(linkError.code ?? '')
  if (!confirmedRollback) {
    return response({ error: 'Activation could not be confirmed. Try signing in before trying again.' }, 503)
  }
  const { error: cleanupError } = await admin.auth.admin.deleteUser(userId)
  if (cleanupError) {
    return response({ error: 'Activation could not be confirmed. Contact the administrator.' }, 503)
  }
  return response({ error: 'The invitation is no longer available. Ask the administrator for a new code.' }, 409)
})

function passwordFor(lastName: unknown, firstName: unknown, fullName: unknown): string {
  const clean = (value: unknown) => String(value ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '')
  const named = `${clean(lastName)}_${clean(firstName)}`
  const base = named === '_' ? clean(fullName) || 'healthworker' : named
  return base.length >= 8 ? base : `${base}123`
}
