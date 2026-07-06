from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, EmailStr, Field


class RegisterIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    email: EmailStr
    password: str = Field(min_length=4, max_length=128)


class LoginIn(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class PingIn(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    accuracy: Optional[float] = None
    speed: Optional[float] = None
    battery: Optional[int] = Field(default=None, ge=0, le=100)
    recorded_at: datetime


class PingBatch(BaseModel):
    device_id: Optional[str] = Field(default=None, max_length=64)
    pings: List[PingIn] = Field(min_length=1, max_length=1000)


class EventIn(BaseModel):
    type: str = Field(min_length=1, max_length=40)
    detail: Optional[str] = Field(default=None, max_length=255)
    recorded_at: datetime
