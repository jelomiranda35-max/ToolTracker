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

    class Config:
        from_attributes = True

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