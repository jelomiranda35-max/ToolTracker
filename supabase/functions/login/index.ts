import { supabase } from '../_shared/db.ts'
import { createToken, cors } from '../_shared/auth.ts'
import bcrypt from 'npm:bcryptjs@2.4.3'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors() })

  try {
    const { username, password } = await req.json()
    console.log('[login] user:', username)

    const { data: user, error } = await supabase
      .from('users').select('*').eq('username', username).single()

    if (error || !user) {
      console.log('[login] not found')
      return new Response(JSON.stringify({ error: 'Invalid credentials' }),
        { status: 401, headers: cors() })
    }

    const valid = bcrypt.compareSync(password, user.password_hash)
    console.log('[login] valid:', valid)

    if (!valid) {
      return new Response(JSON.stringify({ error: 'Invalid credentials' }),
        { status: 401, headers: cors() })
    }

    const token = await createToken(user.username)
    return new Response(JSON.stringify({
      access_token: token,
      token_type: 'bearer',
      user_id: user.id,
      name: user.name,
      username: user.username,
      role: user.role,
    }), { headers: cors() })
  } catch (e) {
    console.error('[login] error:', e)
    return new Response(JSON.stringify({ error: String(e) }),
      { status: 500, headers: cors() })
  }
})