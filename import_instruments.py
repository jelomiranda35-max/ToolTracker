import csv
import psycopg2
from io import StringIO
import os

# ── CONFIG ──
DB_HOST = "gondola.proxy.rlwy.net"
DB_PORT = 23903
DB_NAME = "railway"
DB_USER = "postgres"
DB_PASS = "RxcBkQEJxHZkCBfTFQhSjtFCjrLDEsfc"

# ── CSV FILE PATH ──
CSV_FILE = os.path.join(os.path.dirname(__file__), "AMaTS_INSTRUMENTS_csv.csv")

def clean(val):
    if val is None:
        return None
    val = val.strip().replace("\n", " ").replace("\r", "")
    return val if val and val not in ("-", "*-*", "**") else None

def parse_csv(filepath):
    with open(filepath, encoding="utf-8") as f:
        raw = f.read()

    reader = csv.reader(StringIO(raw))
    instruments = []
    in_data = False

    for row in reader:
        if not any(row):
            continue

        if "Instrument Code" in row:
            in_data = True
            continue

        if not in_data:
            continue

        non_empty = [c for c in row if c.strip()]
        if len(non_empty) <= 2:
            continue

        try:
            instrument_name = clean(row[1]) if len(row) > 1 else None
            instrument_code = clean(row[2]) if len(row) > 2 else None
            serial_number   = clean(row[4]) if len(row) > 4 else None
            status_raw      = clean(row[5]) if len(row) > 5 else "Functioning"
            status_notes    = clean(row[6]) if len(row) > 6 else None
            location        = clean(row[7]) if len(row) > 7 else "AMTEC UPLB"
        except IndexError:
            continue

        if not instrument_name or not instrument_code:
            continue

        if status_raw in ("For Repair", "For Condemning", "For Calibration"):
            condition = status_raw
        else:
            condition = "Functioning"

        if not location:
            location = "AMTEC UPLB"

        instruments.append({
            "instrument_name": instrument_name,
            "instrument_code": instrument_code,
            "serial_number": serial_number,
            "current_condition": condition,
            "location": location,
            "status_notes": status_notes,
        })

    return instruments

def main():
    print("Reading CSV...")
    instruments = parse_csv(CSV_FILE)
    print(f"Found {len(instruments)} instruments in CSV\n")

    print("Connecting to PostgreSQL...")
    conn = psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASS,
    )
    cur = conn.cursor()
    print("Connected!\n")

    inserted = 0
    skipped = 0

    for inst in instruments:
        try:
            cur.execute("""
                INSERT INTO instruments 
                    (instrument_code, instrument_name, serial_number,
                     current_condition, status, location, last_updated)
                VALUES (%s, %s, %s, %s, %s, %s, NOW())
                ON CONFLICT (instrument_code) DO UPDATE SET
                    instrument_name   = EXCLUDED.instrument_name,
                    serial_number     = EXCLUDED.serial_number,
                    current_condition = EXCLUDED.current_condition,
                    location          = EXCLUDED.location,
                    last_updated      = NOW()
            """, (
                inst["instrument_code"],
                inst["instrument_name"],
                inst["serial_number"],
                inst["current_condition"],
                "Available",
                inst["location"],
            ))
            conn.commit()
            inserted += 1
            print(f"  ✓ {inst['instrument_code']} — {inst['instrument_name']}")
        except Exception as e:
            conn.rollback()
            print(f"  ✗ ERROR on {inst['instrument_code']}: {e}")
            skipped += 1

    cur.close()
    conn.close()

    print(f"\n{'='*50}")
    print(f"✅ Import complete!")
    print(f"   Inserted/Updated : {inserted}")
    print(f"   Errors skipped   : {skipped}")
    print(f"{'='*50}")
    print(f"\nNext step: Open the app and tap the sync icon")
    print(f"to download all {inserted} instruments to your device.")

if __name__ == "__main__":
    main()