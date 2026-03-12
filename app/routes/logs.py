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


@router.post("/revert-requests")
def post_revert_requests(entries: List[dict], db: Session = Depends(get_db)):
    for e in entries:
        existing = db.execute(text(
            "SELECT id FROM revert_requests WHERE instrument_code = :code AND requested_at = :ts"
        ), {"code": e.get("instrument_code"), "ts": e.get("requested_at")}).first()
        if not existing:
            db.execute(text("""
                INSERT INTO revert_requests
                    (instrument_code, instrument_name, requested_condition, reason,
                     requested_by, status, requested_at)
                VALUES
                    (:code, :name, :cond, :reason, :by, 'pending', :ts)
            """), {
                "code": e.get("instrument_code"),
                "name": e.get("instrument_name"),
                "cond": e.get("requested_condition"),
                "reason": e.get("reason"),
                "by": e.get("requested_by"),
                "ts": e.get("requested_at"),
            })
    db.commit()
    return {"message": "ok"}


@router.get("/revert-requests")
def get_revert_requests(db: Session = Depends(get_db)):
    rows = db.execute(text(
        "SELECT * FROM revert_requests WHERE status = 'pending' ORDER BY requested_at DESC"
    )).mappings().all()
    return [dict(r) for r in rows]


@router.post("/revert-requests/{instrument_code}/respond")
def respond_revert_request(instrument_code: str, body: dict, db: Session = Depends(get_db)):
    from fastapi import HTTPException
    from datetime import datetime
    status = body.get("status")
    if status not in ("approved", "denied"):
        raise HTTPException(status_code=400, detail="status must be 'approved' or 'denied'")
    db.execute(text("""
        UPDATE revert_requests
        SET status = :status, responded_at = :now
        WHERE instrument_code = :code AND status = 'pending'
    """), {"status": status, "now": datetime.utcnow().isoformat(), "code": instrument_code})
    db.commit()
    return {"message": "ok"}


@router.get("/revert-requests/{instrument_code}/decision")
def get_revert_decision(instrument_code: str, db: Session = Depends(get_db)):
    row = db.execute(text("""
        SELECT status, responded_at FROM revert_requests
        WHERE instrument_code = :code
        ORDER BY requested_at DESC LIMIT 1
    """), {"code": instrument_code}).mappings().first()
    if not row:
        return {"status": "none"}
    return dict(row)
