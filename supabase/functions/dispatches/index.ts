import { supabase } from '../_shared/db.ts'
import { getUser, cors } from '../_shared/auth.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors() })

  const token = req.headers.get('Authorization')?.replace('Bearer ', '')
  const user = token ? await getUser(token) : null
  if (!user) return new Response('Unauthorized', { status: 401, headers: cors() })

  const url = new URL(req.url)
  const path = url.pathname

  // GET /dispatches
  if (req.method === 'GET' && !path.includes('/return')) {
    const { data } = await supabase
      .from('dispatches').select('*, dispatch_items(*)').order('date_out', { ascending: false })
    return new Response(JSON.stringify(data), { headers: cors() })
  }

  // POST /dispatches
  if (req.method === 'POST') {
    const body = await req.json()
    const { data: dispatch, error } = await supabase
      .from('dispatches').insert({
        dispatch_no: body.dispatch_no,
        test_engineer: body.test_engineer,
        processed_by_id: user.id,
        processed_by_name: user.name,
        date_out: body.date_out,
        remarks: body.remarks,
        dispatch_type: body.dispatch_type || 'regular',
        student_name: body.student_name,
        student_id: body.student_id,
      }).select().single()
    if (error) return new Response(JSON.stringify({ error: error.message }),
      { status: 400, headers: cors() })

    for (const item of (body.items || [])) {
      await supabase.from('dispatch_items').insert({
        dispatch_id: dispatch.id,
        instrument_code: item.instrument_code,
        instrument_name: item.instrument_name || item.instrument_code,
        current_condition: item.current_condition,
        remarks: item.remarks,
      })
      await supabase.from('instruments')
        .update({ status: 'In Use', last_touch_date: new Date().toISOString(),
                   last_touch_by: body.test_engineer })
        .eq('instrument_code', item.instrument_code)
    }
    return new Response(JSON.stringify(dispatch), { headers: cors() })
  }

  // PUT /dispatches/{dispatch_no}/return
  if (req.method === 'PUT' && path.includes('/return')) {
    const dispatch_no = path.split('/').slice(-2)[0]
    const body = await req.json().catch(() => ({}))

    const { data: dispatch } = await supabase
      .from('dispatches').select('id').eq('dispatch_no', dispatch_no).single()
    if (!dispatch) return new Response('Not found', { status: 404, headers: cors() })

    await supabase.from('dispatches')
      .update({ date_in: new Date().toISOString() })
      .eq('dispatch_no', dispatch_no)

    const { data: items } = await supabase
      .from('dispatch_items').select('*').eq('dispatch_id', dispatch.id)

    for (const item of (items || [])) {
      const cond = (body.item_conditions || [])
        .find((c: any) => c.instrument_code === item.instrument_code)
      if (cond?.return_condition) {
        await supabase.from('dispatch_items')
          .update({ return_condition: cond.return_condition })
          .eq('id', item.id)
      }
      await supabase.from('instruments')
        .update({ status: 'Available', last_touch_date: new Date().toISOString(),
                   last_touch_by: user.name })
        .eq('instrument_code', item.instrument_code)
    }
    return new Response(JSON.stringify({ message: 'returned' }), { headers: cors() })
  }

  return new Response('Not found', { status: 404, headers: cors() })
})