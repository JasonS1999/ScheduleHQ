# Shift Manager CSV Auto-Import Setup Guide

This guide explains how to set up automated daily imports of Shift Manager Summary CSV files into ScheduleHQ.

## Architecture Overview

```
Power Automate          Local Folder              Python Script           Firebase Storage
(downloads CSV)  ──►  (C:\Users\jenno\...)  ──►  (daily 8am)  ──►  shift_manager_imports/
                                                                              │
                                                                              ▼
                                                                    Cloud Function
                                                                    (auto-triggers)
                                                                              │
                                                                              ▼
                                                                      Firestore
                                                              /managers/{uid}/shiftManagerReports/
```

---

## Prerequisites

- Python 3.10 or later installed
- Firebase project: `schedulehq-cf87f`
- Power Automate flow that saves CSV files to:
  `C:\Users\jenno\OneDrive\Desktop\Shift Manager Summary\`
- Manager's `storeNsn` must be set in the ScheduleHQ Desktop app (Settings → Store Number)

---

## Step 1: Download Firebase Service Account Credentials

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select project **schedulehq-cf87f**
3. Click **Project Settings** (gear icon)
4. Go to **Service Accounts** tab
5. Click **Generate new private key**
6. Save the downloaded JSON file as:
   ```
   E:\ScheduleHQ\scripts\firebase-service-account.json
   ```

⚠️ **IMPORTANT:** Never commit this file to Git. It's already in `.gitignore`.

---

## Step 2: Set Up Python Environment

Open PowerShell and run:

```powershell
cd E:\ScheduleHQ\scripts

# Create virtual environment
python -m venv venv

# Activate it
.\venv\Scripts\Activate

# Install dependencies
pip install -r requirements.txt
```

---

## Step 3: Test the Upload Script

With the virtual environment activated:

```powershell
# Make sure there's a CSV file in the watch folder first
python shift_manager_uploader.py
```

Check:
- Console shows "Firebase initialized successfully"
- CSV files are uploaded and deleted
- `shift_manager_upload.log` contains the activity log

---

## Step 4: Set Up Scheduled Task (Daily 8am)

Run as Administrator:

```powershell
cd E:\ScheduleHQ\scripts
.\setup_shift_manager_task.bat
```

This creates a Windows Task Scheduler task that:
- Runs daily at 8:00 AM
- Executes `python shift_manager_uploader.py`
- Logs output to `shift_manager_upload.log`

### Manual Task Management

```powershell
# Run task immediately
schtasks /run /tn "ScheduleHQ Shift Manager Upload"

# View task status
schtasks /query /tn "ScheduleHQ Shift Manager Upload"

# Delete task
schtasks /delete /tn "ScheduleHQ Shift Manager Upload" /f
```

---

## Step 5: Deploy Cloud Function

```powershell
cd E:\ScheduleHQ\ScheduleHQ_Desktop\functions

# Install dependencies
npm install

# Deploy to Firebase
npm run deploy
```

The Cloud Function `processShiftManagerCSV` will automatically:
1. Trigger when a CSV is uploaded to `shift_manager_imports/`
2. Parse the CSV data
3. Look up the manager by matching the CSV's `Loc` column to `storeNsn` in `managerSettings`
4. Match manager names to employees (case-insensitive)
5. Save matched data to Firestore under the correct manager
6. Delete the CSV from Storage

### Multi-Store Support

The system automatically routes CSV data to the correct manager based on the store number:
- The `Loc` column in the CSV is matched against `storeNsn` in each manager's settings
- No code changes needed when adding new stores - just ensure the manager has the correct `storeNsn` set

---

## CSV File Formats

The Cloud Function automatically detects the CSV format based on column headers and processes accordingly.

### Format 1: Hourly Summary (Recommended)

| Column | Description | Aggregation |
|--------|-------------|-------------|
| Loc | Store location number | - |
| End Time | Hour end time (5:00, 6:00... 25:00) | - |
| All Net Sales | Net sales amount | SUM |
| STW GC | Guest count | SUM |
| OEPE | Order entry to payment end | AVG |
| KVS Time Per Item | KVS time per item | AVG |
| KVS Healthy Usage | KVS healthy usage metric | AVG |
| DT Pull Forward % | Drive-thru pulled forward % | AVG |
| Punch Labor | Punch labor percentage | AVG |
| TPPH | Transactions per person hour | AVG |
| R2P | Ready to pay metric | SUM |

**How it works:**
- Hourly data is aggregated into shift type buckets based on `shiftTypes` configured in manager settings
- Each shift type has `rangeStart` and `rangeEnd` times (e.g., Open: 04:30-11:00)
- The `employeeId` is assigned from `shiftRunners/{date}_{shiftType}` (e.g., `2026-02-03_open`)
- Total rows and all-zero rows are automatically skipped
- Hours past midnight (25:00, 26:00) are normalized by subtracting 24

### Format 2: Manager Summary (Legacy)

| Column | Description |
|--------|-------------|
| Loc | Store location number |
| Time Slice | Time period (Breakfast, Lunch, etc.) |
| Manager Name | Format: "LastName, FirstName" |
| All Net Sales | Net sales amount |
| # of Shifts | Number of shifts |
| GC | Guest count |
| DT Pulled Forward % | Drive-thru pulled forward percentage |
| KVS Healthy Usage | KVS healthy usage metric |
| OEPE | Order entry to payment end time |
| Punch Labor % | Punch labor percentage |
| DT GC | Drive-thru guest count |
| TPPH | Transactions per person hour |
| Average Check | Average check amount |
| Act vs Need | Actual vs needed ratio |
| R2P | Ready to pay metric |

---

## File Naming Convention

For best results, name CSV files as:
```
ShiftManager_17495_2026-02-03.csv
```

Format: `ShiftManager_{StoreNumber}_{YYYY-MM-DD}.csv`

The Cloud Function extracts the date from the filename. If no date is found, it uses the current date.

---

## Firestore Data Structure

Data is saved to `managers/{managerUid}/shiftManagerReports/{YYYY-MM-DD}`:

### Hourly Format (aggregated by shift type)
```
├── importedAt: timestamp
├── fileName: string
├── location: string
├── reportDate: string
├── format: "hourly"
├── totalEntries: number
└── entries: [
    {
      employeeId: number,        // From shiftRunner, -1 if unassigned
      runnerName: string,        // From shiftRunner or "Unassigned"
      shiftType: string,         // Shift key (e.g., "open", "lunch")
      shiftLabel: string,        // Shift label (e.g., "Open", "Lunch")
      allNetSales: number,       // SUM of hours in shift range
      stwGc: number,             // SUM
      oepe: number,              // AVG
      kvsTimePerItem: number,    // AVG
      kvsHealthyUsage: number,   // AVG
      dtPullForwardPct: number,  // AVG
      punchLaborPct: number,     // AVG
      tpph: number,              // AVG
      r2p: number                // SUM
    }
]
```

### Manager Format (per-manager entries)
```
├── importedAt: timestamp
├── fileName: string
├── location: string
├── reportDate: string
├── format: "manager"
├── totalEntries: number
├── unmatchedEntries: number
└── entries: [
    {
      employeeId: number,
      managerName: string,
      timeSlice: string,
      allNetSales: number,
      numberOfShifts: number,
      gc: number,
      dtPulledForwardPct: number,
      kvsHealthyUsage: number,
      oepe: number,
      punchLaborPct: number,
      dtGc: number,
      tpph: number,
      averageCheck: number,
      actVsNeed: number,
      r2p: number
    }
]
```

---

## Troubleshooting

### Python script fails to run

1. Check that `firebase-service-account.json` exists in the scripts folder
2. Ensure Python virtual environment is activated
3. Check `shift_manager_upload.log` for error messages

### Files not uploading

1. Verify CSV files exist in `C:\Users\jenno\OneDrive\Desktop\Shift Manager Summary\`
2. Check that files have `.csv` extension
3. Ensure Firebase Storage bucket is correct: `schedulehq-cf87f.firebasestorage.app`

### Manager names not matching

The Cloud Function matches names by:
1. Converting CSV "LastName, FirstName" → "FirstName LastName" format
2. Looking up employee by `name` field (case-insensitive)

**Example:** CSV has "Sjogren, Jason" → Normalized to "Jason Sjogren" → Matches employee with `name: "Jason Sjogren"`

If names aren't matching:
1. Ensure employees have their `name` set correctly in the Desktop app Roster
2. Check that CSV names match exactly (spelling)
3. View Cloud Function logs in Firebase Console to see the exact matching attempts

### Store not found (No manager mapping)

If you see "No manager found with storeNsn: XXXXX" in the logs:
1. Open ScheduleHQ Desktop app
2. Go to **Settings**
3. Ensure **Store Number** is set to the exact value in the CSV's `Loc` column (e.g., "17495")
4. The setting syncs to Firestore at `managerSettings/{managerUid}/storeNsn`

### View Cloud Function Logs

```powershell
cd E:\ScheduleHQ\ScheduleHQ_Desktop\functions
npm run logs
```

Or view in [Firebase Console](https://console.firebase.google.com/) > Functions > Logs

---

## Power Automate Setup (Reference)

Your Power Automate flow should:

1. **Trigger:** Schedule - Daily at desired time
2. **Action:** Download CSV from MyQSRSoft
3. **Action:** Create file in OneDrive
   - Folder: `Desktop/Shift Manager Summary`
   - File name: `concat('ShiftManager_17495_', formatDateTime(utcNow(), 'yyyy-MM-dd'), '.csv')`
   - Content: CSV data from step 2

The Python script will then pick up the file at 8am and upload it.
