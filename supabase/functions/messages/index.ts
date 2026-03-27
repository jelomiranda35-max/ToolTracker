import { supabase } from '../_shared/db.ts'
import { getUser, cors } from '../_shared/auth.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors() })

  const token = req.headers.get('Authorization')?.replace('Bearer ', '')
  const user = token ? await getUser(token) : null
  if (!user) return new Response('Unauthorized', { status: 401, headers: cors() })

  const url = new URL(req.url)
  const path = url.pathname

  // POST /messages
  if (req.method === 'POST' && !path.includes('/read')) {
    const body = await req.json()
    const { data } = await supabase.from('admin_messages').insert({
      from_admin_id: user.id,
      from_admin_name: user.name,
      to_user_id: body.to_user_id,
      to_user_name: body.to_user_name,
      message: body.message,
    }).select().single()
    return new Response(JSON.stringify(data), { headers: cors() })
  }

  // GET /messages/unread
  if (req.method === 'GET' && path.includes('/unread')) {
    const { data } = await supabase.from('admin_messages')
      .select('*').eq('to_user_id', user.id).is('read_at', null)
      .order('created_at', { ascending: false })
    return new Response(JSON.stringify(data), { headers: cors() })
  }

  // PATCH /messages/{id}/read
  if (req.method === 'PATCH' && path.includes('/read')) {
    const id = path.split('/').slice(-2)[0]
    const { data } = await supabase.from('admin_messages')
      .update({ read_at: new Date().toISOString() })
      .eq('id', id).select().single()
    return new Response(JSON.stringify(data), { headers: cors() })
  }

  // GET /messages/admin/status
  if (req.method === 'GET' && path.includes('/admin/status')) {
    const { data } = await supabase.from('admin_messages')
      .select('*').order('created_at', { ascending: false })
    return new Response(JSON.stringify(data), { headers: cors() })
  }

  return new Response('Not found', { status: 404, headers: cors() })
})