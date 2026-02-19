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
    created_at = Column(DateTime, default=datetime.utcnow)

    dispatches = relationship("Dispatch", back_populates="processed_by_user")


class Instrument(Base):
    __tablename__ = "instruments"

    id = Column(Integer, primary_key=True, index=True)
    instrument_code = Column(String, unique=True, nullable=False, index=True)
    instrument_name = Column(String, nullable=False)
    current_condition = Column(String, default="Functioning")
    status = Column(String, default="Available")
    last_updated = Column(DateTime, default=datetime.utcnow)

    dispatch_items = relationship("DispatchItem", back_populates="instrument")


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

    processed_by_user = relationship("User", back_populates="dispatches")
    items = relationship("DispatchItem", back_populates="dispatch")


class DispatchItem(Base):
    __tablename__ = "dispatch_items"

    id = Column(Integer, primary_key=True, index=True)
    dispatch_id = Column(Integer, ForeignKey("dispatches.id"), nullable=False)
    instrument_id = Column(Integer, ForeignKey("instruments.id"), nullable=False)
    current_condition = Column(String, nullable=False, default="Functioning")
    remarks = Column(Text, nullable=True)

    dispatch = relationship("Dispatch", back_populates="items")
    instrument = relationship("Instrument", back_populates="dispatch_items")