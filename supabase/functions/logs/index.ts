import { supabase } from '../_shared/db.ts'
import { getUser, cors } from '../_shared/auth.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors() })

  const token = req.headers.get('Authorization')?.replace('Bearer ', '')
  const user = token ? await getUser(token) : null
  if (!user) return new Response('Unauthorized', { status: 401, headers: cors() })

  const url = new URL(req.url)
  const path = url.pathname

  // ACTIVITY LOG
  if (path.includes('/activity')) {
    if (req.method === 'POST') {
      const body = await req.json()
      const { data } = await supabase.from('activity_log').insert(body).select().single()
      return new Response(JSON.stringify(data), { headers: cors() })
    }
    if (req.method === 'GET') {
      const { data } = await supabase.from('activity_log')
        .select('*').order('timestamp', { ascending: false })
      return new Response(JSON.stringify(data), { headers: cors() })
    }
  }

  // INSTRUMENT HISTORY
  if (path.includes('/history')) {
    if (req.method === 'POST') {
      const body = await req.json()
      const { data } = await supabase.from('instrument_history').insert(body).select().single()
      return new Response(JSON.stringify(data), { headers: cors() })
    }
    if (req.method === 'GET') {
      const { data } = await supabase.from('instrument_history')
        .select('*').order('timestamp', { ascending: false })
      return new Response(JSON.stringify(data), { headers: cors() })
    }
  }

  // REVERT REQUESTS
  if (path.includes('/revert-requests')) {
    if (req.method === 'POST' && !path.includes('/respond') && !path.includes('/decision')) {
      const body = await req.json()
      const { data } = await supabase.from('revert_requests').insert(body).select().single()
      return new Response(JSON.stringify(data), { headers: cors() })
    }
    if (req.method === 'GET' && !path.includes('/decision')) {
      const { data } = await supabase.from('revert_requests')
        .select('*').order('requested_at', { ascending: false })
      return new Response(JSON.stringify(data), { headers: cors() })
    }
    if (req.method === 'POST' && path.includes('/respond')) {
      const code = path.split('/').slice(-2)[0]
      const body = await req.json()
      const { data } = await supabase.from('revert_requests')
        .update({ status: body.status, responded_at: new Date().toISOString() })
        .eq('instrument_code', code).select().single()
      return new Response(JSON.stringify(data), { headers: cors() })
    }
    if (req.method === 'GET' && path.includes('/decision')) {
      const code = path.split('/').slice(-2)[0]
      const { data } = await supabase.from('revert_requests')
        .select('*').eq('instrument_code', code)
        .order('requested_at', { ascending: false }).limit(1).single()
      return new Response(JSON.stringify(data), { headers: cors() })
    }
  }

  return new Response('Not found', { status: 404, headers: cors() })
})