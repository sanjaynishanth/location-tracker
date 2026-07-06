from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field


class PingIn(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    accuracy: Optional[float] = None
    speed: Optional[float] = None
    battery: Optional[int] = Field(default=None, ge=0, le=100)
    recorded_at: datetime


class PingBatch(BaseModel):
    device_id: str = Field(min_length=1, max_length=64)
    name: str = Field(min_length=1, max_length=120)
    pings: List[PingIn] = Field(min_length=1, max_length=1000)
