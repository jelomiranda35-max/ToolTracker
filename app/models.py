from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Text, Boolean
from sqlalchemy.orm import relationship
from datetime import datetime
from app.database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    username = Column(String, unique=True, nullable=False)
    password_hash = Column(String, nullable=False)
    role = Column(String, default="staff", nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    dispatches = relationship("Dispatch", back_populates="processed_by_user")


class Instrument(Base):
    __tablename__ = "instruments"

    id = Column(Integer, primary_key=True, index=True)
    instrument_code = Column(String, unique=True, nullable=False, index=True)
    instrument_name = Column(String, nullable=False)
    serial_number = Column(String, nullable=True)
    current_condition = Column(String, default="Functioning")
    status = Column(String, default="Available")
    location = Column(String, nullable=True, default="AMTEC UPLB")
    last_touch_date = Column(DateTime, nullable=True)
    last_touch_by = Column(String, nullable=True)
    last_updated = Column(DateTime, default=datetime.utcnow)


class Dispatch(Base):
    __tablename__ = "dispatches"

    id = Column(Integer, primary_key=True, index=True)
    dispatch_no = Column(String, unique=True, nullable=False, index=True)
    test_engineer = Column(String, nullable=False)
    processed_by_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    date_out = Column(DateTime, nullable=False, default=datetime.utcnow)
    date_in = Column(DateTime, nullable=True)
    remarks = Column(Text, nullable=True)
    synced = Column(Boolean, default=False)
    conflict = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    dispatch_type = Column(String, default="regular", nullable=False)
    student_name = Column(String, nullable=True)
    student_id = Column(String, nullable=True)

    processed_by_user = relationship("User", back_populates="dispatches")
    items = relationship("DispatchItem", back_populates="dispatch")


class DispatchItem(Base):
    __tablename__ = "dispatch_items"

    id = Column(Integer, primary_key=True, index=True)
    dispatch_id = Column(Integer, ForeignKey("dispatches.id"), nullable=False)
    # The real DB column is instrument_id (FK to instruments.id)
    # NOT instrument_code — that was the bug causing 0 items to be saved
    instrument_id = Column(Integer, ForeignKey("instruments.id"), nullable=True)
    instrument_name = Column(String, nullable=True)
    current_condition = Column(String, nullable=False, default="Functioning")
    return_condition = Column(String, nullable=True)
    remarks = Column(Text, nullable=True)

    dispatch = relationship("Dispatch", back_populates="items")
    instrument = relationship("Instrument")
