from fastapi import FastAPI
from app.routes import dispatches, instruments, auth
from app.database import engine
from sqlalchemy import text

app = FastAPI(title="AMTEC Tool Tracker API", version="1.3.0")

# Run migrations on startup
with engine.connect() as conn:
    conn.execute(text("ALTER TABLE instruments ADD COLUMN IF NOT EXISTS scheduled_repair_date VARCHAR"))
    conn.execute(text("ALTER TABLE instruments ADD COLUMN IF NOT EXISTS scheduled_condemn_date VARCHAR"))
    conn.execute(text("ALTER TABLE instruments ADD COLUMN IF NOT EXISTS notes TEXT"))
    conn.commit()

app.include_router(auth.router)
app.include_router(instruments.router)
app.include_router(dispatches.router)


@app.get("/")
def root():
    return {"message": "AMTEC Tool Tracker API is running"}


@app.get("/health")
def health():
    return {"status": "ok"} 