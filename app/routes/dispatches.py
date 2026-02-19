from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models import Dispatch, DispatchItem, Instrument
from pydantic import BaseModel
from datetime import datetime
from typing import Optional

router = APIRouter(prefix="/dispatches", tags=["Dispatches"])

class DispatchItemCreate(BaseModel):
    instrument_code: str
    current_condition: str = "Functioning"
    remarks: Optional[str] = None

class DispatchCreate(BaseModel):
    dispatch_no: str
    test_engineer: str
    processed_by_id: int
    date_out: datetime
    remarks: Optional[str] = None
    items: list[DispatchItemCreate]

class DispatchItemResponse(BaseModel):
    id: int
    instrument_code: str
    instrument_name: str
    current_condition: str
    remarks: Optional[str]

    class Config:
        from_attributes = True

class DispatchResponse(BaseModel):
    id: int
    dispatch_no: str
    test_engineer: str
    date_out: datetime
    date_in: Optional[datetime]
    remarks: Optional[str]
    items: list[DispatchItemResponse]

    class Config:
        from_attributes = True

@router.get("/", response_model=list[DispatchResponse])
def get_all_dispatches(db: Session = Depends(get_db)):
    dispatches = db.query(Dispatch).all()
    result = []
    for d in dispatches:
        items = []
        for item in d.items:
            instrument = db.query(Instrument).filter(
                Instrument.id == item.instrument_id
            ).first()
            items.append(DispatchItemResponse(
                id=item.id,
                instrument_code=instrument.instrument_code,
                instrument_name=instrument.instrument_name,
                current_condition=item.current_condition,
                remarks=item.remarks
            ))
        result.append(DispatchResponse(
            id=d.id,
            dispatch_no=d.dispatch_no,
            test_engineer=d.test_engineer,
            date_out=d.date_out,
            date_in=d.date_in,
            remarks=d.remarks,
            items=items
        ))
    return result

@router.post("/", response_model=DispatchResponse)
def create_dispatch(data: DispatchCreate, db: Session = Depends(get_db)):
    existing = db.query(Dispatch).filter(
        Dispatch.dispatch_no == data.dispatch_no
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="Dispatch number already exists")

    dispatch = Dispatch(
        dispatch_no=data.dispatch_no,
        test_engineer=data.test_engineer,
        processed_by_id=data.processed_by_id,
        date_out=data.date_out,
        remarks=data.remarks
    )
    db.add(dispatch)
    db.flush()

    items = []
    for item_data in data.items:
        instrument = db.query(Instrument).filter(
            Instrument.instrument_code == item_data.instrument_code
        ).first()
        if not instrument:
            raise HTTPException(
                status_code=404,
                detail=f"Instrument code {item_data.instrument_code} not found"
            )
        if instrument.status == "In Use":
            raise HTTPException(
                status_code=400,
                detail=f"{instrument.instrument_name} is currently In Use"
            )
        instrument.status = "In Use"
        instrument.current_condition = item_data.current_condition

        dispatch_item = DispatchItem(
            dispatch_id=dispatch.id,
            instrument_id=instrument.id,
            current_condition=item_data.current_condition,
            remarks=item_data.remarks
        )
        db.add(dispatch_item)
        db.flush()
        items.append(DispatchItemResponse(
            id=dispatch_item.id,
            instrument_code=instrument.instrument_code,
            instrument_name=instrument.instrument_name,
            current_condition=item_data.current_condition,
            remarks=item_data.remarks
        ))

    db.commit()
    return DispatchResponse(
        id=dispatch.id,
        dispatch_no=dispatch.dispatch_no,
        test_engineer=dispatch.test_engineer,
        date_out=dispatch.date_out,
        date_in=dispatch.date_in,
        remarks=dispatch.remarks,
        items=items
    )

@router.put("/{dispatch_no}/return")
def return_dispatch(dispatch_no: str, db: Session = Depends(get_db)):
    dispatch = db.query(Dispatch).filter(
        Dispatch.dispatch_no == dispatch_no
    ).first()
    if not dispatch:
        raise HTTPException(status_code=404, detail="Dispatch not found")
    if dispatch.date_in:
        raise HTTPException(status_code=400, detail="Dispatch already returned")

    dispatch.date_in = datetime.utcnow()

    for item in dispatch.items:
        instrument = db.query(Instrument).filter(
            Instrument.id == item.instrument_id
        ).first()
        if instrument:
            instrument.status = "Available"
            instrument.last_updated = datetime.utcnow()

    db.commit()
    return {"message": f"Dispatch {dispatch_no} returned successfully"}