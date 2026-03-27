const fetch = require('node-fetch');

const url = 'https://gdxnkwuarlltxhefizmw.supabase.co/functions/v1/sheets';
const token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdkeG5rd3VhcmxsdHhoZWZpem13Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM2MjQ2ODYsImV4cCI6MjA4OTIwMDY4Nn0.LXbagrO68jEWKZ939jPcGlZrh8XMNv-_Mg9VZVeZrjg';

const payload = {
  action: 'dispatch_created',
  data: {
    dispatch_no: 'VERIFY-999',
    test_engineer: 'Antigravity Verification',
    date_out: new Date().toISOString(),
    instruments: ['VER-001', 'VER-002'],
    processed_by: 'Antigravity Agent'
  }
};

(async () => {
  try {
    console.log('--- SENDING TEST EVENT TO SHEETS ---');
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify(payload)
    });
    const result = await res.json();
    console.log('Status:', res.status);
    console.log('Response:', JSON.stringify(result, null, 2));
    if (res.ok) {
        console.log('✓ Google Sheets Sync Successful!');
    } else {
        console.log('✗ Failed to sync with Google Sheets');
    }
  } catch (err) {
    console.error('Error testing sheets:', err.message);
  }
})();
