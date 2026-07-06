from datetime import datetime

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
)
from sqlalchemy.orm import relationship

from .database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True)
    email = Column(String(200), unique=True, nullable=False, index=True)
    password_hash = Column(String(256), nullable=False)
    name = Column(String(120), nullable=False)
    role = Column(String(20), nullable=False, default="staff")  # staff | admin
    device_id = Column(String(64), nullable=True)  # last phone that logged in
    tracking_enabled = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    pings = relationship("Ping", back_populates="user", cascade="all, delete-orphan")
    events = relationship("Event", back_populates="user", cascade="all, delete-orphan")


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
    received_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    user = relationship("User", back_populates="pings")

    __table_args__ = (Index("ix_pings_user_recorded", "user_id", "recorded_at"),)


class Event(Base):
    """Tamper / lifecycle events reported by the app."""

    __tablename__ = "events"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    type = Column(String(40), nullable=False)  # tracking_on | tracking_off | admin_removed | login
    detail = Column(String(255), nullable=True)
    recorded_at = Column(DateTime, nullable=False)
    received_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    user = relationship("User", back_populates="events")

    __table_args__ = (Index("ix_events_user_recorded", "user_id", "recorded_at"),)


class Session(Base):
    __tablename__ = "sessions"

    token = Column(String(64), primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    user = relationship("User")
