from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import get_db
from app.models_OLD import User
from app.auth import verify_password, get_password_hash, create_access_token, get_current_admin
from pydantic import BaseModel
from typing import List
from datetime import datetime

router = APIRouter(prefix="/auth", tags=["Auth"])


class UserCreate(BaseModel):
    name: str
    username: str
    password: str
    role: str = "staff"  # 'staff' or 'admin'


class LoginRequest(BaseModel):
    username: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str
    user_id: int
    name: str
    username: str
    role: str


class UserResponse(BaseModel):
    id: int
    name: str
    username: str
    role: str
    created_at: str

    class Config:
        from_attributes = True


# ── Public endpoints ──────────────────────────────────────────────────────────

@router.post("/login", response_model=TokenResponse)
def login(data: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.username == data.username).first()
    if not user or not verify_password(data.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid username or password")

    token = create_access_token(data={"sub": user.username})

    return TokenResponse(
        access_token=token,
        token_type="bearer",
        user_id=user.id,
        name=user.name,
        username=user.username,
        role=user.role,
    )


# ── Admin-only endpoints ──────────────────────────────────────────────────────

@router.get("/users", response_model=List[UserResponse])
def get_all_users(
    db: Session = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    """Admin only — list all user accounts."""
    users = db.query(User).order_by(User.created_at).all()
    return [
        UserResponse(
            id=u.id,
            name=u.name,
            username=u.username,
            role=u.role,
            created_at=str(u.created_at),
        )
        for u in users
    ]


@router.post("/users", response_model=UserResponse)
def create_user(
    data: UserCreate,
    db: Session = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    """Admin only — create a new user account."""
    existing = db.query(User).filter(User.username == data.username).first()
    if existing:
        raise HTTPException(status_code=400, detail="Username already exists")

    if data.role not in ("staff", "admin"):
        raise HTTPException(status_code=400, detail="Role must be 'staff' or 'admin'")

    user = User(
        name=data.name,
        username=data.username,
        password_hash=get_password_hash(data.password),
        role=data.role,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    return UserResponse(
        id=user.id,
        name=user.name,
        username=user.username,
        role=user.role,
        created_at=str(user.created_at),
    )


@router.delete("/users/{user_id}")
def delete_user(
    user_id: int,
    db: Session = Depends(get_db),
    admin: User = Depends(get_current_admin),
):
    """Admin only — delete a user account. Cannot delete yourself."""
    if user_id == admin.id:
        raise HTTPException(status_code=400, detail="Cannot delete your own account")

    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    db.delete(user)
    db.commit()
    return {"message": f"User '{user.username}' deleted successfully"}