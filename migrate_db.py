import psycopg2
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

conn = psycopg2.connect(
    host="gondola.proxy.rlwy.net",
    port=23903,
    dbname="railway",
    user="postgres",
    password="RxcBkQEJxHZkCBfTFQhSjtFCjrLDEsfc"
)
cur = conn.cursor()

print("Running migrations...")

# ── 1. Add role column to users ───────────────────────────────────────────────
try:
    cur.execute("ALTER TABLE users ADD COLUMN role VARCHAR DEFAULT 'staff' NOT NULL")
    conn.commit()
    print("✓ Added 'role' column to users")
except Exception as e:
    conn.rollback()
    print(f"  Skipped 'role' column (probably already exists): {e}")

# ── 2. Add instrument_name to dispatch_items ──────────────────────────────────
try:
    cur.execute("ALTER TABLE dispatch_items ADD COLUMN instrument_name VARCHAR")
    conn.commit()
    print("✓ Added 'instrument_name' column to dispatch_items")
except Exception as e:
    conn.rollback()
    print(f"  Skipped 'instrument_name' column (probably already exists): {e}")

# ── 3. Add return_condition to dispatch_items ─────────────────────────────────
try:
    cur.execute("ALTER TABLE dispatch_items ADD COLUMN return_condition VARCHAR")
    conn.commit()
    print("✓ Added 'return_condition' column to dispatch_items")
except Exception as e:
    conn.rollback()
    print(f"  Skipped 'return_condition' column (probably already exists): {e}")

# ── 4. Backfill instrument_name from instruments table ────────────────────────
try:
    cur.execute("""
        UPDATE dispatch_items di
        SET instrument_name = i.instrument_name
        FROM instruments i
        WHERE di.instrument_code = i.instrument_code
        AND di.instrument_name IS NULL
    """)
    conn.commit()
    print("✓ Backfilled instrument_name in dispatch_items")
except Exception as e:
    conn.rollback()
    print(f"  Skipped backfill: {e}")

# ── 5. Create admin account ───────────────────────────────────────────────────
admin_name = "Admin"
admin_username = "admin"
admin_password = "amtec2026"  # Change this after first login!

try:
    cur.execute("SELECT id FROM users WHERE username = %s", (admin_username,))
    existing = cur.fetchone()
    if existing:
        # Just upgrade existing admin user's role
        cur.execute(
            "UPDATE users SET role = 'admin' WHERE username = %s",
            (admin_username,)
        )
        conn.commit()
        print(f"✓ Upgraded '{admin_username}' to admin role")
    else:
        hashed = pwd_context.hash(admin_password)
        cur.execute(
            "INSERT INTO users (name, username, password_hash, role) VALUES (%s, %s, %s, %s)",
            (admin_name, admin_username, hashed, "admin")
        )
        conn.commit()
        print(f"✓ Created admin account — username: '{admin_username}', password: '{admin_password}'")
        print("  ⚠️  CHANGE THE PASSWORD after first login!")
except Exception as e:
    conn.rollback()
    print(f"  Failed to create admin: {e}")

cur.close()
conn.close()
print("\nMigration complete!")
