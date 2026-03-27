import { supabase } from './db.ts'
import { create, verify } from 'https://deno.land/x/djwt@v3.0.1/mod.ts'

const SECRET = 'amtec-tooltracker-secret-2026'
const key = await crypto.subtle.importKey(
  'raw', new TextEncoder().encode(SECRET),
  { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']
)

export async function createToken(username: string): Promise<string> {
  const exp = Math.floor(Date.now() / 1000) + 60 * 60 * 24
  return create({ alg: 'HS256', typ: 'JWT' }, { sub: username, exp }, key)
}

export async function verifyToken(token: string): Promise<string | null> {
  try {
    const payload = await verify(token, key)
    return payload.sub as string
  } catch { return null }
}

export async function getUser(token: string) {
  const username = await verifyToken(token)
  if (!username) return null
  const { data } = await supabase
    .from('users').select('*').eq('username', username).single()
  return data
}

export function cors() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, content-type',
    'Content-Type': 'application/json',
  }
}