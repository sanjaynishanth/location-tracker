from datetime import datetime

from sqlalchemy import Column, DateTime, Float, ForeignKey, Index, Integer, String
from sqlalchemy.orm import relationship

from .database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True)
    device_id = Column(String(64), unique=True, nullable=False, index=True)
    name = Column(String(120), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    pings = relationship("Ping", back_populates="user", cascade="all, delete-orphan")


class Ping(Base):
    __tablename__ = "pings"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    lat = Column(Float, nullable=False)
    lng = Column(Float, nullable=False)
    accuracy = Column(Float, nullable=True)   # metres
    speed = Column(Float, nullable=True)      # m/s
    battery = Column(Integer, nullable=True)  # percent 0-100
    recorded_at = Column(DateTime, nullable=False)  # UTC, set by the phone
    received_at = Column(DateTime, default=datetime.utcnow, nullable=False)  # UTC, set by server

    user = relationship("User", back_populates="pings")

    __table_args__ = (Index("ix_pings_user_recorded", "user_id", "recorded_at"),)
