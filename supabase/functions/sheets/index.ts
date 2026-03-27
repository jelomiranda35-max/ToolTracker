// sheets/index.ts — Google Sheets live sync for AMTEC Tool Tracker
// Handles: dispatch_created, dispatch_returned, borrow_created, borrow_returned, instrument_updated

import { cors } from '../_shared/auth.ts'

const SPREADSHEET_ID = Deno.env.get('SHEETS_SPREADSHEET_ID')!
const SERVICE_EMAIL  = Deno.env.get('SHEETS_CLIENT_EMAIL')!
const PRIVATE_KEY    = Deno.env.get('SHEETS_PRIVATE_KEY')!.replace(/\\n/g, '\n')

// ── Google JWT Auth (RS256, no external library) ─────────────────────────────

function pemToDer(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----[^-]+-----/g, '').replace(/\s/g, '')
  const bin = atob(b64)
  const buf = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i)
  return buf.buffer
}

function b64url(str: string): string {
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header  = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const payload = b64url(JSON.stringify({
    iss: SERVICE_EMAIL,
    scope: 'https://www.googleapis.com/auth/spreadsheets',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now,
  }))

  const keyData = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(PRIVATE_KEY),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  )

  const sigBuf = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    keyData,
    new TextEncoder().encode(`${header}.${payload}`)
  )
  const sig = b64url(String.fromCharCode(...new Uint8Array(sigBuf)))
  const jwt = `${header}.${payload}.${sig}`

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })
  const json = await res.json()
  if (!json.access_token) {
    throw new Error(`Google auth failed: ${JSON.stringify(json)}`)
  }
  return json.access_token
}

// ── Sheets API helpers ────────────────────────────────────────────────────────

async function appendRow(token: string, sheet: string, values: string[]): Promise<void> {
  const range = encodeURIComponent(`${sheet}!A1`)
  const url = `https://sheets.googleapis.com/v4/spreadsheets/${SPREADSHEET_ID}/values/${range}:append?valueInputOption=RAW&insertDataOption=INSERT_ROWS`
  const res = await fetch(url, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ values: [values] }),
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`appendRow failed (${res.status}): ${text}`)
  }
}

async function findRowIndex(token: string, sheet: string, searchVal: string): Promise<number> {
  const range = encodeURIComponent(`${sheet}!A:A`)
  const url = `https://sheets.googleapis.com/v4/spreadsheets/${SPREADSHEET_ID}/values/${range}`
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } })
  if (!res.ok) return -1
  const { values } = await res.json()
  if (!values) return -1
  for (let i = 0; i < values.length; i++) {
    if (values[i][0] === searchVal) return i + 1  // 1-indexed row number
  }
  return -1
}

async function updateRow(token: string, sheet: string, rowIndex: number, values: string[]): Promise<void> {
  const lastCol = String.fromCharCode(64 + values.length)  // e.g. 8 cols → 'H'
  const range = encodeURIComponent(`${sheet}!A${rowIndex}:${lastCol}${rowIndex}`)
  const url = `https://sheets.googleapis.com/v4/spreadsheets/${SPREADSHEET_ID}/values/${range}?valueInputOption=RAW`
  const res = await fetch(url, {
    method: 'PUT',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ values: [values] }),
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`updateRow failed (${res.status}): ${text}`)
  }
}

// ── Helper ────────────────────────────────────────────────────────────────────

function fmtDate(iso: string | undefined | null): string {
  if (!iso) return ''
  try {
    return new Date(iso).toLocaleString('en-PH', {
      timeZone: 'Asia/Manila',
      year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', hour12: true,
    })
  } catch { return iso }
}

// ── Main handler ──────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors() })

  try {
    const { action, data } = await req.json()
    const token = await getAccessToken()

    // ── dispatch_created ────────────────────────────────────────────────────
    if (action === 'dispatch_created') {
      await appendRow(token, 'Dispatches', [
        data.dispatch_no ?? '',
        data.test_engineer ?? '',
        fmtDate(data.date_out),
        '',                                        // Date In — empty until returned
        'Out',
        Array.isArray(data.instruments) ? data.instruments.join(', ') : (data.instruments ?? ''),
        data.processed_by ?? '',
      ])
    }

    // ── dispatch_returned ───────────────────────────────────────────────────
    else if (action === 'dispatch_returned') {
      const row = await findRowIndex(token, 'Dispatches', data.dispatch_no)
      const rowValues = [
        data.dispatch_no ?? '',
        data.test_engineer ?? '',
        fmtDate(data.date_out),
        fmtDate(data.date_in),
        'Returned',
        Array.isArray(data.instruments) ? data.instruments.join(', ') : (data.instruments ?? ''),
        data.processed_by ?? '',
      ]
      if (row > 0) {
        await updateRow(token, 'Dispatches', row, rowValues)
      } else {
        // Row not found (e.g. dispatch was created while offline) — append it
        await appendRow(token, 'Dispatches', rowValues)
      }
    }

    // ── borrow_created ──────────────────────────────────────────────────────
    else if (action === 'borrow_created') {
      await appendRow(token, 'Borrows', [
        data.dispatch_no ?? '',
        data.borrower_name ?? '',
        data.student_id ?? '',
        fmtDate(data.date_out),
        '',                                        // Date In — empty until returned
        'Out',
        Array.isArray(data.instruments) ? data.instruments.join(', ') : (data.instruments ?? ''),
        data.processed_by ?? '',
      ])
    }

    // ── borrow_returned ─────────────────────────────────────────────────────
    else if (action === 'borrow_returned') {
      const row = await findRowIndex(token, 'Borrows', data.dispatch_no)
      const rowValues = [
        data.dispatch_no ?? '',
        data.borrower_name ?? '',
        data.student_id ?? '',
        fmtDate(data.date_out),
        fmtDate(data.date_in),
        'Returned',
        Array.isArray(data.instruments) ? data.instruments.join(', ') : (data.instruments ?? ''),
        data.processed_by ?? '',
      ]
      if (row > 0) {
        await updateRow(token, 'Borrows', row, rowValues)
      } else {
        await appendRow(token, 'Borrows', rowValues)
      }
    }

    // ── instrument_updated ──────────────────────────────────────────────────
    else if (action === 'instrument_updated') {
      const row = await findRowIndex(token, 'Instruments', data.instrument_code)
      const rowValues = [
        data.instrument_code ?? '',
        data.instrument_name ?? '',
        data.old_condition ?? '',
        data.new_condition ?? '',
        data.status ?? '',
        data.location ?? '',
        data.repair_date ?? '',
        data.condemn_date ?? '',
        data.notes ?? '',
        data.updated_by ?? '',
        fmtDate(new Date().toISOString()), // Last Updated
      ]
      if (row > 0) {
        await updateRow(token, 'Instruments', row, rowValues)
      } else {
        await appendRow(token, 'Instruments', rowValues)
      }
    }

    else {
      return new Response(
        JSON.stringify({ ok: false, error: `Unknown action: ${action}` }),
        { status: 400, headers: cors() }
      )
    }

    return new Response(JSON.stringify({ ok: true }), { headers: cors() })

  } catch (err) {
    console.error('[sheets] Error:', err)
    return new Response(
      JSON.stringify({ ok: false, error: String(err) }),
      { status: 500, headers: cors() }
    )
  }
})
