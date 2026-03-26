# Google Sheets Integration Setup Guide

This guide covers the complete setup for live Google Sheets sync with ToolTracker App.

## Overview

The Google Sheets integration works as follows:
- **Client (Flutter App)**: Sends async fire-and-forget sync requests when data changes
- **Backend (Supabase Edge Function)**: Handles Google authentication and writes to Google Sheets
- **Google Sheets**: Receives real-time updates in three tabs (Dispatches, Borrows, Instruments)

**Key Features:**
- ✅ Live updates without blocking app
- ✅ No client-side OAuth (all server-side auth)
- ✅ No credentials exposed in APK
- ✅ Automatic row updates for returns
- ✅ Supports 5 action types: dispatch_created, dispatch_returned, borrow_created, borrow_returned, instrument_updated

---

## Step 1: Google Cloud Project Setup

### 1.1 Create a Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click the **Project** dropdown at top left
3. Click **NEW PROJECT**
4. Name: `ToolTracker` (or your preferred name)
5. Click **CREATE**
6. Wait for project to initialize

### 1.2 Enable Required APIs

1. In the Cloud Console, go to **APIs & Services** → **Library**
2. Search for and enable these APIs:
   - **Google Sheets API** - Click **Enable**
   - **Google Drive API** - Click **Enable**

---

## Step 2: Create Service Account

### 2.1 Create Service Account

1. Go to **APIs & Services** → **Credentials**
2. Click **+ CREATE CREDENTIALS** → **Service Account**
3. Fill in:
   - **Service account name:** `tooltracker-sheets`
   - **Service account ID:** Auto-filled (e.g., `tooltracker-sheets@project-id.iam.gserviceaccount.com`)
   - **Description:** `Google Sheets sync for ToolTracker`
4. Click **CREATE AND CONTINUE**
5. Click **CONTINUE** (skip optional grant roles step)
6. Click **DONE**

### 2.2 Create JSON Key

1. Go to **APIs & Services** → **Credentials**
2. Under **Service Accounts**, click on the `tooltracker-sheets` account
3. Go to the **KEYS** tab
4. Click **ADD KEY** → **Create new key**
5. Choose **JSON**
6. Click **CREATE**
7. A JSON file downloads - **save it securely**

---

## Step 3: Create Google Sheets Spreadsheet

### 3.1 Create Spreadsheet

1. Go to [Google Sheets](https://docs.google.com/spreadsheets/)
2. Click **+ Blank** to create new spreadsheet
3. Rename to: `ToolTracker Live Sync` (or preferred name)

### 3.2 Create Three Tabs and Headers

Delete the default "Sheet1" and create three tabs with headers:

**Tab 1: Dispatches**
```
A: Dispatch No    B: Test Engineer    C: Date Out    D: Date In    E: Status    F: Instruments    G: Processed By
```

**Tab 2: Borrows**
```
A: Dispatch No    B: Borrower Name    C: Student ID    D: Date Out    E: Date In    F: Status    G: Instruments    H: Processed By
```

**Tab 3: Instruments**
```
A: Code    B: Name    C: Serial No    D: Condition    E: Status    F: Location    G: Last Touch By    H: Days Out    I: Scheduled Repair    J: Scheduled Condemn
```

### 3.3 Share with Service Account

1. Note the **Spreadsheet ID** from the URL (the long alphanumeric string)
2. Click **Share** button
3. Enter the Service Account email exactly: `tooltracker-sheets@project-id.iam.gserviceaccount.com` (replace `project-id` with your actual project ID)
4. Grant **Editor** access
5. Uncheck "Notify people" (service account won't receive emails)
6. Click **Share**

---

## Step 4: Configure Supabase Secrets

### 4.1 Get Required Values from JSON Key

Open the downloaded JSON file and note:
- **SHEETS_SPREADSHEET_ID**: The Spreadsheet ID from your Google Sheet URL
- **SHEETS_CLIENT_EMAIL**: The `client_email` from JSON
- **SHEETS_PRIVATE_KEY**: The `private_key` from JSON (entire multi-line value)

### 4.2 Set Supabase Secrets

1. Go to [Supabase Dashboard](https://app.supabase.com/)
2. Select your ToolTracker project
3. Go to **Settings** → **Secrets** (or **Configuration** → **Secrets**)
4. Click **New Secret** and add these three secrets:

**Secret 1: SHEETS_SPREADSHEET_ID**
```
Name: SHEETS_SPREADSHEET_ID
Value: 1234567890abcdefghijklmnop  (your actual spreadsheet ID)
```

**Secret 2: SHEETS_CLIENT_EMAIL**
```
Name: SHEETS_CLIENT_EMAIL
Value: tooltracker-sheets@your-project-id.iam.gserviceaccount.com
```

**Secret 3: SHEETS_PRIVATE_KEY**
```
Name: SHEETS_PRIVATE_KEY
Value: -----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQE...
...rest of the private key...
-----END PRIVATE KEY-----
```

---

## Step 5: Deploy Edge Function

### 5.1 Deploy via Supabase CLI

```bash
# Navigate to backend directory
cd path/to/tooltracker-backend

# Deploy the sheets function
supabase functions deploy sheets

# Or deploy with secrets (Supabase CLI will read from your secrets file)
supabase functions deploy sheets --no-bundling
```

### 5.2 Deploy via Supabase Dashboard (Alternative)

1. Go to **Edge Functions**
2. Click **Create New Function**
3. Name: `sheets`
4. Copy the entire content from `supabase/functions/sheets/index.ts`
5. Paste into the editor
6. Click **Deploy**

### 5.3 Verify Deployment

1. Go to **Edge Functions** in Supabase Dashboard
2. Click on `sheets` function
3. Should show green status and deployment details

---

## Step 6: Update Flutter App Configuration

### 6.1 Verify API Base URL

Open [lib/services/api_service.dart](lib/services/api_service.dart) and check:
```dart
static const String baseUrl = 'YOUR_SUPABASE_EDGE_FUNCTION_URL';
```

Should be something like:
```dart
static const String baseUrl = 'https://your-project.supabase.co/functions/v1';
```

### 6.2 Build and Deploy APK (Optional)

If making changes to Flutter code:
```bash
flutter build apk --release
# APK will be at: build/app/outputs/flutter-app/release/app-release.apk
```

---

## Step 7: Testing

### 7.1 Test Dispatch Creation

1. Open app and create a new dispatch
2. After successful creation, go to Google Sheets → **Dispatches** tab
3. Should see new row with dispatch data

### 7.2 Test Dispatch Return

1. Return a dispatch using the return scanner
2. Go to Google Sheets → **Dispatches** tab
3. Row should update with `Date In` and status changed to "Returned"

### 7.3 Test Borrow Creation

1. Create a new student borrow
2. Go to Google Sheets → **Borrows** tab
3. Should see new row

### 7.4 Test Borrow Return

1. Return instruments from a borrow
2. Go to Google Sheets → **Borrows** tab
3. Row should update with `Date In` and "Returned" status

### 7.5 Test Instrument Update

1. Edit an instrument's condition/schedule in the app
2. Go to Google Sheets → **Instruments** tab
3. Should see updated row

### 7.6 Debug Failed Syncs

Check Edge Function logs:
1. Go to **Edge Functions** in Supabase
2. Click `sheets` function
3. Go to **Logs** tab
4. Search for recent function executions

---

## Troubleshooting

### Issue: Spreadsheet ID not found

**Solution:**
- Copy spreadsheet ID directly from URL: `https://docs.google.com/spreadsheets/d/[ID]/edit`
- Verify it's set in Supabase Secrets

### Issue: Service account can't access sheet

**Solution:**
- Verify sheet was shared with exact service account email (check Sharing settings)
- Ensure service account email has Editor access
- Wait a few moments for permissions to propagate

### Issue: "Permission denied" errors in logs

**Solution:**
- Double-check Google Cloud APIs are enabled (Sheets API + Drive API)
- Verify service account JSON key is valid
- Re-download JSON key and update Supabase Secrets

### Issue: Data not appearing in sheets

**Solution:**
1. Check Edge Function logs for errors
2. Verify row headers match expected columns exactly
3. Test if sheets API calls are working with curl:
```bash
curl -X POST https://your-project.supabase.co/functions/v1/sheets \
  -H "Authorization: Bearer your-anon-key" \
  -H "Content-Type: application/json" \
  -d '{"action":"dispatch_created","data":{"dispatch_no":"TEST123","test_engineer":"Test","date_out":"2025-01-01"}}'
```

### Issue: Sheet tabs are missing

**Solution:**
- Ensure 3 tabs exist: Dispatches, Borrows, Instruments
- Tab names must match exactly (case-sensitive)
- Add tab headers as specified in Step 3.2

---

## Data Reference

### Dispatches Tab Format
```
[Dispatch No] [Test Engineer] [Date Out] [Date In] [Status] [Instruments] [Processed By]
D001          John Doe       2025-01-15  2025-01-16 Returned Inst001, Inst002  Jane Smith
```

### Borrows Tab Format
```
[Dispatch No] [Borrower Name] [Student ID] [Date Out] [Date In] [Status] [Instruments] [Processed By]
B001          Maria Santos   2024-0001    2025-01-15  2025-01-16 Returned Inst003      Admin User
```

### Instruments Tab Format
```
[Code] [Name]       [Serial No] [Condition] [Status] [Location] [Last Touch By] [Days Out] [Scheduled Repair] [Scheduled Condemn]
INST01 Oscilloscope SN12345     Good        In      Lab A      John Doe       0                              2025-04-01
```

---

## Security Notes

**Recommended Practices:**
1. **Never commit secrets** to version control
2. **Rotate keys periodically** - Generate new service account JSON key every 90 days
3. **Monitor access** - Check Edge Function logs for unusual activity
4. **Limit permissions** - Service account should only have Sheets API access
5. **Use environment variables** - Keep secrets in Supabase backend, never in app code

---

## Support & Next Steps

**To verify everything is working:**
1. Deploy Edge Function
2. Create test dispatch, borrow, or instrument
3. Check Google Sheet updates in real-time
4. Review Edge Function logs for any errors

**Common Actions:**
- Update sheet rows → Use `updateRow()` function
- Search for dispatch by number → Use `findRow()` function
- Append new rows → Use `appendRow()` function
- Batch operations → Queue multiple requests (handled by fire-and-forget pattern)

---

## Rollback Instructions

If you need to revert changes:

1. **Disable sheets sync:** Comment out `ApiService.pushToSheets()` calls in Flutter screens
2. **Delete Edge Function:** Go to Edge Functions → Delete `sheets` function
3. **Remove secrets:** Delete the three SHEETS_* secrets from Supabase
4. **Archive Google Sheet:** Keep the sheet but stop sharing with service account

---

**Last Updated:** 2025-01-22  
**Version:** 1.0 - Initial Setup Guide
