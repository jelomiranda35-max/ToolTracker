from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session, joinedload
from app.database import get_db
from app.models_OLD import Dispatch, DispatchItem, Instrument, User
from app.auth import get_current_user, get_current_admin
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime

router = APIRouter(prefix="/dispatches", tags=["Dispatches"])


# ── Schemas ───────────────────────────────────────────────────────────────────

class DispatchItemCreate(BaseModel):
    instrument_code: str
    current_condition: str
    remarks: Optional[str] = None


class ReturnItemCondition(BaseModel):
    instrument_code: str
    return_condition: str


class DispatchCreate(BaseModel):
    dispatch_no: str
    test_engineer: str
    processed_by_id: int
    date_out: str
    remarks: Optional[str] = None
    items: List[DispatchItemCreate]
    dispatch_type: Optional[str] = "regular"
    student_name: Optional[str] = None
    student_id: Optional[str] = None


class ReturnDispatchRequest(BaseModel):
    item_conditions: Optional[List[ReturnItemCondition]] = None


class DispatchItemResponse(BaseModel):
    id: int
    instrument_code: str
    instrument_name: str
    current_condition: str
    return_condition: Optional[str] = None
    remarks: Optional[str] = None

    class Config:
        from_attributes = True


class DispatchResponse(BaseModel):
    id: int
    dispatch_no: str
    test_engineer: str
    processed_by_id: int
    processed_by_name: Optional[str] = None
    date_out: str
    date_in: Optional[str] = None
    remarks: Optional[str] = None
    dispatch_type: str = "regular"
    student_name: Optional[str] = None
    student_id: Optional[str] = None
    items: List[DispatchItemResponse] = []

    class Config:
        from_attributes = True


# ── Helpers ───────────────────────────────────────────────────────────────────

def _build_item_list(items, db):
    result = []
    for item in items:
        # Try to get the latest instrument name from the instruments table
        instrument = db.query(Instrument).filter(
            Instrument.instrument_code == item.instrument_code
        ).first()
        result.append(DispatchItemResponse(
            id=item.id,
            instrument_code=item.instrument_code,
            instrument_name=(
                item.instrument_name or
                (instrument.instrument_name if instrument else item.instrument_code)
            ),
            current_condition=item.current_condition,
            return_condition=item.return_condition,
            remarks=item.remarks,
        ))
    return result


def _serialize_dispatch(d: Dispatch, db: Session) -> DispatchResponse:
    # Always query items fresh — do not rely on lazy-loaded relationship
    items = db.query(DispatchItem).filter(
        DispatchItem.dispatch_id == d.id
    ).all()

    # Safely get processed_by_name
    processed_by_name = None
    if d.processed_by_user:
        processed_by_name = d.processed_by_user.name
    else:
        # Fallback: look up user directly in case relationship didn't load
        user = db.query(User).filter(User.id == d.processed_by_id).first()
        if user:
            processed_by_name = user.name

    return DispatchResponse(
        id=d.id,
        dispatch_no=d.dispatch_no,
        test_engineer=d.test_engineer,
        processed_by_id=d.processed_by_id,
        processed_by_name=processed_by_name,
        date_out=str(d.date_out),
        date_in=str(d.date_in) if d.date_in else None,
        remarks=d.remarks,
        dispatch_type=d.dispatch_type or "regular",
        student_name=d.student_name,
        student_id=d.student_id,
        items=_build_item_list(items, db),
    )


# ── GET all dispatches ────────────────────────────────────────────────────────

@router.get("/", response_model=List[DispatchResponse])
def get_dispatches(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Returns ALL dispatches for ALL users — not filtered by the caller's account.
    This is intentional: every device (staff or admin) needs to see the full picture
    so that instrument statuses and active dispatch counts are accurate everywhere.
    """
    dispatches = (
        db.query(Dispatch)
        .options(joinedload(Dispatch.processed_by_user))
        .order_by(Dispatch.date_out.desc())
        .all()
    )
    return [_serialize_dispatch(d, db) for d in dispatches]


# ── POST create dispatch ──────────────────────────────────────────────────────

@router.post("/", response_model=DispatchResponse)
def create_dispatch(
    data: DispatchCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    existing = db.query(Dispatch).filter(
        Dispatch.dispatch_no == data.dispatch_no
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="Dispatch number already exists")

    dispatch_type = data.dispatch_type or "regular"
    if dispatch_type not in ("regular", "student"):
        dispatch_type = "regular"

    dispatch = Dispatch(
        dispatch_no=data.dispatch_no,
        test_engineer=data.test_engineer,
        # Always use the authenticated user's ID, not the one sent from the device
        # This prevents a device sending a wrong processed_by_id
        processed_by_id=current_user.id,
        date_out=data.date_out,
        remarks=data.remarks,
        dispatch_type=dispatch_type,
        student_name=data.student_name if dispatch_type == "student" else None,
        student_id=data.student_id if dispatch_type == "student" else None,
    )
    db.add(dispatch)
    db.commit()
    db.refresh(dispatch)

    for item in data.items:
        instrument = db.query(Instrument).filter(
            Instrument.instrument_code == item.instrument_code
        ).first()
        if instrument:
            instrument.status = "In Use"
            instrument.last_touch_date = datetime.utcnow()
            instrument.last_touch_by = data.test_engineer

        di = DispatchItem(
            dispatch_id=dispatch.id,
            instrument_code=item.instrument_code,
            instrument_name=instrument.instrument_name if instrument else item.instrument_code,
            current_condition=item.current_condition,
            remarks=item.remarks,
        )
        db.add(di)

    db.commit()
    db.refresh(dispatch)
    return _serialize_dispatch(dispatch, db)


# ── PUT return dispatch ───────────────────────────────────────────────────────

@router.put("/{dispatch_no}/return")
def return_dispatch(
    dispatch_no: str,
    body: Optional[ReturnDispatchRequest] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    dispatch = db.query(Dispatch).filter(
        Dispatch.dispatch_no == dispatch_no
    ).first()
    if not dispatch:
        raise HTTPException(status_code=404, detail="Dispatch not found")

    if dispatch.date_in is not None:
        return {"message": "Dispatch already returned"}

    dispatch.date_in = datetime.utcnow()

    items = db.query(DispatchItem).filter(
        DispatchItem.dispatch_id == dispatch.id
    ).all()

    # Build condition lookup from body if provided
    condition_map: dict = {}
    if body and body.item_conditions:
        for ic in body.item_conditions:
            condition_map[ic.instrument_code] = ic.return_condition

    for item in items:
        instrument = db.query(Instrument).filter(
            Instrument.instrument_code == item.instrument_code
        ).first()
        if instrument:
            instrument.status = "Available"
            instrument.last_touch_date = datetime.utcnow()
            instrument.last_touch_by = current_user.name

            if item.instrument_code in condition_map:
                new_cond = condition_map[item.instrument_code]
                instrument.current_condition = new_cond
                item.return_condition = new_cond

    db.commit()
    return {"message": "Dispatch returned successfully"}


# ── GET admin stats ───────────────────────────────────────────────────────────

@router.get("/admin/stats")
def get_admin_stats(
    db: Session = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    total_dispatches = db.query(Dispatch).count()
    active_dispatches = db.query(Dispatch).filter(
        Dispatch.date_in == None
    ).count()
    returned_dispatches = total_dispatches - active_dispatches

    total_instruments = db.query(Instrument).count()
    in_use = db.query(Instrument).filter(
        Instrument.status == "In Use"
    ).count()
    available = db.query(Instrument).filter(
        Instrument.status == "Available"
    ).count()

    student_total = db.query(Dispatch).filter(
        Dispatch.dispatch_type == "student"
    ).count()
    student_active = db.query(Dispatch).filter(
        Dispatch.dispatch_type == "student",
        Dispatch.date_in == None,
    ).count()

    users = db.query(User).all()
    user_activity = []
    for u in users:
        count = db.query(Dispatch).filter(
            Dispatch.processed_by_id == u.id
        ).count()
        active_count = db.query(Dispatch).filter(
            Dispatch.processed_by_id == u.id,
            Dispatch.date_in == None,
        ).count()
        user_activity.append({
            "user_id": u.id,
            "name": u.name,
            "username": u.username,
            "role": u.role,
            "total_dispatches": count,
            "active_dispatches": active_count,
        })

    return {
        "total_dispatches": total_dispatches,
        "active_dispatches": active_dispatches,
        "returned_dispatches": returned_dispatches,
        "total_instruments": total_instruments,
        "instruments_in_use": in_use,
        "instruments_available": available,
        "student_dispatches_total": student_total,
        "student_dispatches_active": student_active,
        "user_activity": user_activity,
    }