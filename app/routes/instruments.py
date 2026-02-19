from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models import Instrument
from pydantic import BaseModel
from datetime import datetime

router = APIRouter(prefix="/instruments", tags=["Instruments"])

class InstrumentCreate(BaseModel):
    instrument_code: str
    instrument_name: str
    current_condition: str = "Functioning"

class InstrumentResponse(BaseModel):
    id: int
    instrument_code: str
    instrument_name: str
    current_condition: str
    status: str
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
        current_condition=data.current_condition
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
    instrument.current_condition = data.current_condition
    instrument.last_updated = datetime.utcnow()
    db.commit()
    db.refresh(instrument)
    return instrument