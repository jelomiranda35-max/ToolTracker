@echo off
set "CLI=C:\Users\ACER\Downloads\supabase\supabase.exe"
set "REF=gdxnkwuarlltxhefizmw"

echo --- CONFIGURING GOOGLE SHEETS SYNC SECRETS ---

echo [1/3] Setting Spreadsheet ID...
"%CLI%" secrets set SHEETS_SPREADSHEET_ID="1lwR7ZIFFMDNj5TN3cng2Wk_pnWcSvF4k_R5fnf6TprU" --project-ref %REF%

echo [2/3] Setting Client Email...
"%CLI%" secrets set SHEETS_CLIENT_EMAIL="tooltracker-service@amtec-tooltracker.iam.gserviceaccount.com" --project-ref %REF%

echo [3/3] Setting Private Key...
"%CLI%" secrets set SHEETS_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDiIVLWyA8Uirzo\nlKtS1NBC8yvquRmfl0YItLUe0Pnekio78X6PIxv2CS42CaqYlnIOlfQYEriOHkKN\nHw+GCPboVyUHgf1f56JDFG1+tFeJ6R73ajOWWOzNirdrSoAeXQEEjv0HLD0O1/Fn\nd88itILre0694pldOgfQZYbAoGpSiECVILKlyfP2lwYfaanh3o7rJq995huqzKRy\n5lBtrA762DAO+ynKTF/WrZUrCsZ0iJ/C0Jw+RBSgM0cioeZu8PY5URKoHGA2LIdG\nQdQUvTPM/8ORdYpFuX8P4ZU4Xz5lqHOZqjg8ec23gDoFhCugBaRDsmVhpu7SEj+v\nIl0F3nDBAgMBAAECggEAZcS2iegOdWG9A/VIp2YUdlUHKkN0pzDG+YsOSlilY4gn\njsOwAA4+eruF+xbdmn92xF6zNJRUT82JiQZ2D44ARO9XQGo9lEhka8kJQDE8hloO\nsC2xGtRZemWYB6bHQyL7HsiVUoGT1xbTU4wFgip4Ey9y8B1HhT/lHWJbw1xOjWZh\nCLRUknz96Y8R6S3dv/wQow8zYeS5TCepX8ONMSydQIlmvxgHUjnh9Q6A46B+pVzo\n9YvZFArfSXsF8q+NcTu0SZ9E1lalrx7oWQ5s6wEyiVKN9zrciMk8SNgMyPe8wXph\ncQJmlaY5lUKZh+y9PhDoDzRlDcwmPmYmV0ApezkjGwKBgQDzxd8M4nSpb7mNssKn\n9gEVRkRl0DKVBIrZl359ovAagkMiCgXVvN/g9BADGUsxc4HVuBDE/1uxLtMGfLx0\n10f8Ljal4qOtTX8/pV4XI863LH60kEcLxJ/gK8Y2fry53whyGpNmU+V6hV/R8xI9\naDYonAVZ3K/yiPfRoYBQyCBurwKBgQDteOnBcZwoDRLGvhPWS3JCcfdwwe2Zc1I7\nNeiB3sXPr4XOflgg926sMXPYDTtNhSsaEFT/lcYClZa/d8yKdzOUsYDdtHE4oOro\n0loofqwri+THutA6LEkBmVM2ndsKodxBgUcbplsW/FQ1RkpKF9VmwyN4qdsIU/vp\nD6n7uHhzjwKBgQC61TvnzyRkvDl1rb1dJ8GawZkog1JRPgMBVAfhWOE3IAE99HqW\nX0UjT0t6ZIdp5kJrP8Cyi5iGCwI3paB22IzWbcD6kOKrr4rIiAC+MXZ8k4Ck+TNK\nhK+YC1TGbYpN1u/NLCsusTxfFBvleKvRHq7rnvDG98puU6XEKEiFIW0iBwKBgD50\nUmYBzyPpbErAqs7tQLug5YbOOgLlhXb1EpU1VajtbK+GIv9ok77Nsr3bnQEiSNet\n++zMIyuC1Aa/JxgziWlN1ap5Tl2qVJ2u1O9ZgUZioGS3CRSDmR/Gh1AR7A27zAWe\nTmlDMym0ayEnv1oFMqa4I5gUc/qYu+PrrrT5KxSZAoGBAKkSdZGxHmVckCstoPFA\nYZWGIdr2Z4aC/h2VoUFHILeEj9HpK0U/np4vjmdtlVQJV19jGom50GL7HyAorpr8\nZhlylgr9Hvb7HFxjtMDMAjsHOnQNw219xr/WjA2IakC1a+5ycqrMBtuQrob6kpOR\nEZ70wM+nJVJIWkRpk8EE+L27\n-----END PRIVATE KEY-----\n" --project-ref %REF%

echo --- ALL SECRETS SET! ---
pause
