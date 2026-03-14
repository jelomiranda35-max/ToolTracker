from fastapi import FastAPI
from app.routes import dispatches, instruments, auth, logs
from app.routes import messages as messages_router
from app.database import engine
from sqlalchemy import text

app = FastAPI(title="AMTEC Tool Tracker API", version="1.3.0")

# Run migrations on startup
with engine.connect() as conn:
    conn.execute(text("ALTER TABLE instruments ADD COLUMN IF NOT EXISTS scheduled_repair_date VARCHAR"))
    conn.execute(text("ALTER TABLE instruments ADD COLUMN IF NOT EXISTS scheduled_condemn_date VARCHAR"))
    conn.execute(text("ALTER TABLE instruments ADD COLUMN IF NOT EXISTS notes TEXT"))
    conn.execute(text("ALTER TABLE instruments ADD COLUMN IF NOT EXISTS last_calibrated_date VARCHAR"))
    conn.execute(text("ALTER TABLE instruments ADD COLUMN IF NOT EXISTS calibration_notes TEXT"))
    conn.execute(text("""
        CREATE TABLE IF NOT EXISTS activity_log (
            id SERIAL PRIMARY KEY,
            event_type VARCHAR NOT NULL,
            event_detail TEXT,
            actor VARCHAR,
            device_info VARCHAR,
            timestamp VARCHAR NOT NULL
        )
    """))
    conn.execute(text("""
        CREATE TABLE IF NOT EXISTS instrument_history (
            id SERIAL PRIMARY KEY,
            instrument_code VARCHAR NOT NULL,
            event_type VARCHAR NOT NULL,
            event_detail TEXT,
            actor VARCHAR,
            timestamp VARCHAR NOT NULL
        )
    """))
    conn.execute(text("""
        CREATE TABLE IF NOT EXISTS revert_requests (
            id SERIAL PRIMARY KEY,
            instrument_code VARCHAR NOT NULL,
            instrument_name VARCHAR,
            requested_condition VARCHAR NOT NULL,
            reason TEXT NOT NULL,
            requested_by VARCHAR,
            status VARCHAR NOT NULL DEFAULT 'pending',
            requested_at VARCHAR NOT NULL,
            responded_at VARCHAR
        )
    """))
    conn.execute(text("""
        CREATE TABLE IF NOT EXISTS admin_messages (
            id SERIAL PRIMARY KEY,
            from_admin_id INTEGER NOT NULL,
            from_admin_name VARCHAR,
            to_user_id INTEGER NOT NULL,
            to_user_name VARCHAR,
            message TEXT NOT NULL,
            created_at VARCHAR NOT NULL,
            read_at VARCHAR
        )
    """))
    conn.execute(text("""
        CREATE TABLE IF NOT EXISTS new_instrument_alerts (
            id SERIAL PRIMARY KEY,
            instrument_code VARCHAR NOT NULL,
            instrument_name VARCHAR NOT NULL,
            serial_number VARCHAR,
            added_at VARCHAR NOT NULL
        )
    """))
    conn.commit()

app.include_router(auth.router)
app.include_router(instruments.router)
app.include_router(dispatches.router)
app.include_router(logs.router)
app.include_router(messages_router.router)


@app.get("/")
def root():
    return {"message": "AMTEC Tool Tracker API is running"}


@app.get("/health")
def health():
    return {"status": "ok"}