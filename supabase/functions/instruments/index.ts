import { supabase } from '../_shared/db.ts'
import { getUser, cors } from '../_shared/auth.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors() })
  const token = req.headers.get('Authorization')?.replace('Bearer ', '')
  const user = token ? await getUser(token) : null
  if (!user) return new Response('Unauthorized', { status: 401, headers: cors() })

  const url = new URL(req.url)
  const code = url.pathname.split('/').pop()

  if (req.method === 'GET') {
    const { data } = await supabase.from('instruments').select('*')
    return new Response(JSON.stringify(data), { headers: cors() })
  }
  if (req.method === 'POST') {
    const body = await req.json()
    const { data, error } = await supabase.from('instruments').insert(body).select().single()
    if (error) return new Response(JSON.stringify({ error: error.message }),
      { status: 400, headers: cors() })
    await supabase.from('new_instrument_alerts').insert({
      instrument_code: data.instrument_code,
      instrument_name: data.instrument_name,
      serial_number: data.serial_number,
      added_at: new Date().toISOString(),
    })
    return new Response(JSON.stringify(data), { headers: cors() })
  }
  if (req.method === 'PATCH') {
    const body = await req.json()
    const { data } = await supabase.from('instruments')
      .update({ ...body, last_updated: new Date().toISOString() })
      .eq('instrument_code', code).select().single()
    return new Response(JSON.stringify(data), { headers: cors() })
  }
  if (req.method === 'DELETE') {
    await supabase.from('instruments').delete().eq('instrument_code', code)
    return new Response(JSON.stringify({ message: 'deleted' }), { headers: cors() })
  }
  return new Response('Not found', { status: 404, headers: cors() })
})