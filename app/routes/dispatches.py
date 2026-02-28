from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models import Dispatch, DispatchItem, Instrument, User
from app.auth import get_current_user, get_current_admin
from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime

router = APIRouter(prefix="/dispatches", tags=["Dispatches"])


class DispatchItemCreate(BaseModel):
    instrument_code: str
    current_condition: str
    remarks: Optional[str] = None


class DispatchCreate(BaseModel):
    dispatch_no: str
    test_engineer: str
    processed_by_id: int
    date_out: str
    remarks: Optional[str] = None
    items: List[DispatchItemCreate]


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
    processed_by_name: Optional[str] = None
    date_out: str
    date_in: Optional[str] = None
    remarks: Optional[str] = None
    items: List[DispatchItemResponse] = []

    class Config:
        from_attributes = True


def _build_item_list(items, db):
    """Helper to build DispatchItemResponse list from DispatchItem rows."""
    result = []
    for item in items:
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


# ── GET all dispatches (staff + admin) ───────────────────────────────────────

@router.get("/", response_model=List[DispatchResponse])
def get_dispatches(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    dispatches = db.query(Dispatch).order_by(Dispatch.date_out.desc()).all()
    result = []
    for d in dispatches:
        items = db.query(DispatchItem).filter(
            DispatchItem.dispatch_id == d.id
        ).all()
        processed_by_name = None
        if d.processed_by_user:
            processed_by_name = d.processed_by_user.name
        result.append(DispatchResponse(
            id=d.id,
            dispatch_no=d.dispatch_no,
            test_engineer=d.test_engineer,
            processed_by_name=processed_by_name,
            date_out=str(d.date_out),
            date_in=str(d.date_in) if d.date_in else None,
            remarks=d.remarks,
            items=_build_item_list(items, db),
        ))
    return result


# ── POST create dispatch (staff + admin) ─────────────────────────────────────

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

    dispatch = Dispatch(
        dispatch_no=data.dispatch_no,
        test_engineer=data.test_engineer,
        processed_by_id=current_user.id,
        date_out=data.date_out,
        remarks=data.remarks,
    )
    db.add(dispatch)
    db.commit()
    db.refresh(dispatch)

    item_list = []
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
        db.refresh(di)

        item_list.append(DispatchItemResponse(
            id=di.id,
            instrument_code=di.instrument_code,
            instrument_name=di.instrument_name or item.instrument_code,
            current_condition=di.current_condition,
            return_condition=None,
            remarks=di.remarks,
        ))

    db.commit()

    return DispatchResponse(
        id=dispatch.id,
        dispatch_no=dispatch.dispatch_no,
        test_engineer=dispatch.test_engineer,
        processed_by_name=current_user.name,
        date_out=str(dispatch.date_out),
        date_in=None,
        remarks=dispatch.remarks,
        items=item_list,
    )


# ── PUT return dispatch (staff + admin) ──────────────────────────────────────

@router.put("/{dispatch_no}/return")
def return_dispatch(
    dispatch_no: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    dispatch = db.query(Dispatch).filter(
        Dispatch.dispatch_no == dispatch_no
    ).first()
    if not dispatch:
        raise HTTPException(status_code=404, detail="Dispatch not found")

    dispatch.date_in = datetime.utcnow()

    items = db.query(DispatchItem).filter(
        DispatchItem.dispatch_id == dispatch.id
    ).all()
    for item in items:
        instrument = db.query(Instrument).filter(
            Instrument.instrument_code == item.instrument_code
        ).first()
        if instrument:
            instrument.status = "Available"
            instrument.last_touch_date = datetime.utcnow()
            instrument.last_touch_by = current_user.name

    db.commit()
    return {"message": "Dispatch returned successfully"}


# ── GET admin stats (admin only) ─────────────────────────────────────────────

@router.get("/admin/stats")
def get_admin_stats(
    db: Session = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    """Admin only — summary statistics for the dashboard."""
    total_dispatches = db.query(Dispatch).count()
    active_dispatches = db.query(Dispatch).filter(Dispatch.date_in == None).count()
    returned_dispatches = total_dispatches - active_dispatches

    total_instruments = db.query(Instrument).count()
    in_use = db.query(Instrument).filter(Instrument.status == "In Use").count()
    available = db.query(Instrument).filter(Instrument.status == "Available").count()

    # Activity per user — count of dispatches processed
    users = db.query(User).all()
    user_activity = []
    for u in users:
        count = db.query(Dispatch).filter(Dispatch.processed_by_id == u.id).count()
        active_count = db.query(Dispatch).filter(
            Dispatch.processed_by_id == u.id,
            Dispatch.date_in == None
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
        "user_activity": user_activity,
    }