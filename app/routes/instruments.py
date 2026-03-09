from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models import Instrument
from pydantic import BaseModel
from datetime import datetime
from typing import Optional

router = APIRouter(prefix="/instruments", tags=["Instruments"])

class InstrumentCreate(BaseModel):
    instrument_code: str
    instrument_name: str
    serial_number: Optional[str] = None
    current_condition: str = "Functioning"
    location: Optional[str] = "AMTEC UPLB"

class InstrumentResponse(BaseModel):
    id: int
    instrument_code: str
    instrument_name: str
    serial_number: Optional[str]
    current_condition: str
    status: str
    location: Optional[str]
    last_touch_date: Optional[datetime]
    last_touch_by: Optional[str]
    last_updated: datetime
    scheduled_repair_date: Optional[str] = None
    scheduled_condemn_date: Optional[str] = None
    notes: Optional[str] = None

    class Config:
        from_attributes = True


class InstrumentPatch(BaseModel):
    """Partial update — only fields provided will be updated."""
    current_condition: Optional[str] = None
    location: Optional[str] = None
    scheduled_repair_date: Optional[str] = None   # pass empty string "" to clear
    scheduled_condemn_date: Optional[str] = None  # pass empty string "" to clear
    notes: Optional[str] = None                   # pass empty string "" to clear

@router.get("/", response_model=list[InstrumentResponse])
def get_all_instruments(db: Session = Depends(get_db)):
    return db.query(Instrument).all()

@router.get("/{instrument_code}", response_model=InstrumentResponse)
def get_instrument(instrument_code: str, db: Session = Depends(get_db)):
    instrument = db.query(Instrument).filter(
        Instrument.instrument_code == instrument_code
    ).first()
    if not instrument:
        raise HTTPException(status_code=404, detail="Instrument not found")
    return instrument

@router.post("/", response_model=InstrumentResponse)
def create_instrument(data: InstrumentCreate, db: Session = Depends(get_db)):
    existing = db.query(Instrument).filter(
        Instrument.instrument_code == data.instrument_code
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="Instrument code already exists")
    instrument = Instrument(
        instrument_code=data.instrument_code,
        instrument_name=data.instrument_name,
        serial_number=data.serial_number,
        current_condition=data.current_condition,
        location=data.location
    )
    db.add(instrument)
    db.commit()
    db.refresh(instrument)
    return instrument

@router.put("/{instrument_code}", response_model=InstrumentResponse)
def update_instrument(instrument_code: str, data: InstrumentCreate, db: Session = Depends(get_db)):
    instrument = db.query(Instrument).filter(
        Instrument.instrument_code == instrument_code
    ).first()
    if not instrument:
        raise HTTPException(status_code=404, detail="Instrument not found")
    instrument.instrument_name = data.instrument_name
    instrument.serial_number = data.serial_number
    instrument.current_condition = data.current_condition
    instrument.location = data.location
    instrument.last_updated = datetime.utcnow()
    db.commit()
    db.refresh(instrument)
    return instrument

@router.patch("/{instrument_code}", response_model=InstrumentResponse)
def patch_instrument(
    instrument_code: str,
    data: InstrumentPatch,
    db: Session = Depends(get_db),
):
    """Partial update from the Flutter edit sheet.
    Pass an empty string "" to clear a nullable field (e.g. remove a scheduled date).
    Omit a field entirely to leave it unchanged.
    """
    instrument = db.query(Instrument).filter(
        Instrument.instrument_code == instrument_code
    ).first()
    if not instrument:
        raise HTTPException(status_code=404, detail="Instrument not found")

    if data.current_condition is not None:
        instrument.current_condition = data.current_condition

    if data.location is not None:
        instrument.location = data.location if data.location != "" else None

    if data.scheduled_repair_date is not None:
        instrument.scheduled_repair_date = (
            data.scheduled_repair_date if data.scheduled_repair_date != "" else None
        )

    if data.scheduled_condemn_date is not None:
        instrument.scheduled_condemn_date = (
            data.scheduled_condemn_date if data.scheduled_condemn_date != "" else None
        )

    if data.notes is not None:
        instrument.notes = data.notes if data.notes != "" else None

    instrument.last_updated = datetime.utcnow()
    db.commit()
    db.refresh(instrument)
    return instrument