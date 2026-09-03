import { createClient } from 'jsr:@supabase/supabase-js@2'
import { createActivationHandler } from './handler.ts'

Deno.serve(createActivationHandler(() => {
  const url = Deno.env.get('SUPABASE_URL')
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!url || !key) return null
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
}))
