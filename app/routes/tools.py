from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models_OLD import Tool
from pydantic import BaseModel
from datetime import datetime

router = APIRouter(prefix="/tools", tags=["Tools"])

class ToolCreate(BaseModel):
    barcode: str
    tool_name: str

class ToolResponse(BaseModel):
    id: int
    barcode: str
    tool_name: str
    status: str
    last_updated: datetime

    class Config:
        from_attributes = True

@router.get("/", response_model=list[ToolResponse])
def get_all_tools(db: Session = Depends(get_db)):
    return db.query(Tool).all()

@router.get("/{barcode}", response_model=ToolResponse)
def get_tool_by_barcode(barcode: str, db: Session = Depends(get_db)):
    tool = db.query(Tool).filter(Tool.barcode == barcode).first()
    if not tool:
        raise HTTPException(status_code=404, detail="Tool not found")
    return tool

@router.post("/", response_model=ToolResponse)
def create_tool(tool: ToolCreate, db: Session = Depends(get_db)):
    existing = db.query(Tool).filter(Tool.barcode == tool.barcode).first()
    if existing:
        raise HTTPException(status_code=400, detail="Barcode already exists")
    new_tool = Tool(barcode=tool.barcode, tool_name=tool.tool_name)
    db.add(new_tool)
    db.commit()
    db.refresh(new_tool)
    return new_tool