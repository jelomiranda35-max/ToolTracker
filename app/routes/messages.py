from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text
from app.database import get_db
from app.auth import get_current_user, get_current_admin
from app.models import User
from datetime import datetime
from typing import List

router = APIRouter(prefix="/messages", tags=["messages"])


@router.post("/")
def send_message(
    body: dict,
    db: Session = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    to_user_id = body.get("to_user_id")
    message = body.get("message", "").strip()
    to_user_name = body.get("to_user_name", "")
    if not to_user_id or not message:
        raise HTTPException(status_code=400, detail="to_user_id and message are required")
    db.execute(text("""
        INSERT INTO admin_messages
            (from_admin_id, from_admin_name, to_user_id, to_user_name, message, created_at)
        VALUES
            (:from_id, :from_name, :to_id, :to_name, :msg, :now)
    """), {
        "from_id": admin.id,
        "from_name": admin.name,
        "to_id": to_user_id,
        "to_name": to_user_name,
        "msg": message,
        "now": datetime.utcnow().isoformat(),
    })
    db.commit()
    return {"message": "sent"}


@router.get("/unread")
def get_unread_messages(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    rows = db.execute(text("""
        SELECT id, from_admin_id, from_admin_name, to_user_id, to_user_name,
               message, created_at, read_at
        FROM admin_messages
        WHERE to_user_id = :uid AND read_at IS NULL
        ORDER BY created_at DESC
    """), {"uid": current_user.id}).mappings().all()
    return [dict(r) for r in rows]



@router.get("/admin/status")
def get_message_status(
    db: Session = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    rows = db.execute(text("""
        SELECT id, to_user_name, message, created_at, read_at
        FROM admin_messages
        WHERE from_admin_id = :aid
        ORDER BY created_at DESC
        LIMIT 100
    """), {"aid": admin.id}).mappings().all()
    return [dict(r) for r in rows]


@router.get("/alerts/new-instruments")
def get_new_instrument_alerts(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    rows = db.execute(text("""
        SELECT id, instrument_code, instrument_name, serial_number, added_at
        FROM new_instrument_alerts
        ORDER BY added_at DESC
        LIMIT 50
    """)).mappings().all()
    return [dict(r) for r in rows]


@router.get("/")
def get_messages_for_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    rows = db.execute(text("""
        SELECT id, from_admin_id, from_admin_name, to_user_id, to_user_name,
               message, created_at, read_at
        FROM admin_messages
        WHERE to_user_id = :uid
        ORDER BY created_at DESC
    """), {"uid": user_id}).mappings().all()
    return [dict(r) for r in rows]


@router.patch("/{message_id}/read")
def mark_message_read(
    message_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    db.execute(text("""
        UPDATE admin_messages
        SET read_at = :now
        WHERE id = :id AND to_user_id = :uid AND read_at IS NULL
    """), {
        "now": datetime.utcnow().isoformat(),
        "id": message_id,
        "uid": current_user.id,
    })
    db.commit()
    return {"message": "marked as read"}
