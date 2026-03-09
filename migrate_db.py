"""
migrate_db.py
Run this ONCE on the Railway server after deploying the updated models.py.
It adds the three new columns to the dispatches table without touching existing data.

Usage:
    python migrate_db.py
"""

from app.database import engine
from sqlalchemy import text


def migrate():
    with engine.connect() as conn:
        migrations = [
            # dispatch_type — 'regular' or 'student', default 'regular' for all existing rows
            """
            ALTER TABLE dispatches
            ADD COLUMN IF NOT EXISTS dispatch_type VARCHAR DEFAULT 'regular' NOT NULL
            """,
            # student_name — null for regular dispatches
            """
            ALTER TABLE dispatches
            ADD COLUMN IF NOT EXISTS student_name VARCHAR NULL
            """,
            # student_id — null for regular dispatches
            """
            ALTER TABLE dispatches
            ADD COLUMN IF NOT EXISTS student_id VARCHAR NULL
            """,
        ]

        for sql in migrations:
            try:
                conn.execute(text(sql.strip()))
                print(f"✅  Ran: {sql.strip()[:60]}...")
            except Exception as e:
                print(f"⚠️   Skipped (may already exist): {e}")

        conn.commit()
        print("\n✅  Migration complete.")


if __name__ == "__main__":
    migrate()