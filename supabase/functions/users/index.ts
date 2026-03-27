import { supabase } from '../_shared/db.ts'
import { getUser, cors } from '../_shared/auth.ts'
import bcrypt from 'npm:bcryptjs@2.4.3'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors() })

  const token = req.headers.get('Authorization')?.replace('Bearer ', '')
  const user = token ? await getUser(token) : null
  if (!user) return new Response('Unauthorized', { status: 401, headers: cors() })

  const url = new URL(req.url)
  const path = url.pathname
  const id = path.split('/').pop()

  // GET /users
  if (req.method === 'GET') {
    const { data } = await supabase.from('users')
      .select('id, name, username, role, created_at')
      .order('created_at', { ascending: false })
    return new Response(JSON.stringify(data), { headers: cors() })
  }

  // POST /users
  if (req.method === 'POST') {
    const body = await req.json()
    const hash = bcrypt.hashSync(body.password, 12)
    const { data, error } = await supabase.from('users').insert({
      name: body.name,
      username: body.username,
      password_hash: hash,
      role: body.role || 'staff',
    }).select('id, name, username, role, created_at').single()
    if (error) return new Response(JSON.stringify({ error: error.message }),
      { status: 400, headers: cors() })
    return new Response(JSON.stringify(data), { headers: cors() })
  }

  // DELETE /users/{id}
  if (req.method === 'DELETE') {
    await supabase.from('users').delete().eq('id', id)
    return new Response(JSON.stringify({ message: 'deleted' }), { headers: cors() })
  }

  return new Response('Not found', { status: 404, headers: cors() })
})