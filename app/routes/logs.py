from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import text
from app.database import get_db
from typing import List
from pydantic import BaseModel

router = APIRouter(prefix="/logs", tags=["logs"])


class ActivityLogEntry(BaseModel):
    event_type: str
    event_detail: str | None = None
    actor: str | None = None
    device_info: str | None = None
    timestamp: str


class InstrumentHistoryEntry(BaseModel):
    instrument_code: str
    event_type: str
    event_detail: str | None = None
    actor: str | None = None
    timestamp: str


@router.post("/activity")
def post_activity_logs(entries: List[ActivityLogEntry], db: Session = Depends(get_db)):
    for entry in entries:
        db.execute(text("""
            INSERT INTO activity_log (event_type, event_detail, actor, device_info, timestamp)
            VALUES (:event_type, :event_detail, :actor, :device_info, :timestamp)
        """), {
            "event_type": entry.event_type,
            "event_detail": entry.event_detail,
            "actor": entry.actor,
            "device_info": entry.device_info,
            "timestamp": entry.timestamp,
        })
    db.commit()
    return {"inserted": len(entries)}


@router.get("/activity")
def get_activity_logs(limit: int = 100, db: Session = Depends(get_db)):
    result = db.execute(text("""
        SELECT id, event_type, event_detail, actor, device_info, timestamp
        FROM activity_log
        ORDER BY timestamp DESC
        LIMIT :limit
    """), {"limit": limit})
    rows = result.fetchall()
    return [dict(row._mapping) for row in rows]


@router.post("/history")
def post_instrument_history(entries: List[InstrumentHistoryEntry], db: Session = Depends(get_db)):
    for entry in entries:
        db.execute(text("""
            INSERT INTO instrument_history (instrument_code, event_type, event_detail, actor, timestamp)
            VALUES (:instrument_code, :event_type, :event_detail, :actor, :timestamp)
        """), {
            "instrument_code": entry.instrument_code,
            "event_type": entry.event_type,
            "event_detail": entry.event_detail,
            "actor": entry.actor,
            "timestamp": entry.timestamp,
        })
    db.commit()
    return {"inserted": len(entries)}


@router.get("/history")
def get_instrument_history(actor: str | None = None, limit: int = 100, db: Session = Depends(get_db)):
    if actor:
        result = db.execute(text("""
            SELECT id, instrument_code, event_type, event_detail, actor, timestamp
            FROM instrument_history
            WHERE actor = :actor
            ORDER BY timestamp DESC
            LIMIT :limit
        """), {"actor": actor, "limit": limit})
    else:
        result = db.execute(text("""
            SELECT id, instrument_code, event_type, event_detail, actor, timestamp
            FROM instrument_history
            ORDER BY timestamp DESC
            LIMIT :limit
        """), {"limit": limit})
    rows = result.fetchall()
    return [dict(row._mapping) for row in rows]
