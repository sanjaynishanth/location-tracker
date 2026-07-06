import os
from datetime import datetime, timedelta, timezone
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from . import models
from .database import Base, engine, get_db
from .schemas import PingBatch

API_KEY = os.getenv("API_KEY", "change-me-please")
STATIC_DIR = Path(__file__).resolve().parent.parent / "static"

Base.metadata.create_all(bind=engine)

app = FastAPI(title="Field Tracker API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def require_api_key(x_api_key: str = Header(default="")):
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid or missing X-API-Key")


def to_utc_naive(dt: datetime) -> datetime:
    """Normalise any incoming datetime to naive UTC for storage."""
    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt


def iso_z(dt: datetime) -> str:
    return dt.replace(microsecond=0).isoformat() + "Z"


@app.get("/api/v1/health")
def health():
    return {"status": "ok"}


@app.post("/api/v1/pings", dependencies=[Depends(require_api_key)])
def receive_pings(batch: PingBatch, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.device_id == batch.device_id).first()
    if user is None:
        user = models.User(device_id=batch.device_id, name=batch.name)
        db.add(user)
        db.flush()
    elif user.name != batch.name:
        user.name = batch.name

    for p in batch.pings:
        db.add(
            models.Ping(
                user_id=user.id,
                lat=p.lat,
                lng=p.lng,
                accuracy=p.accuracy,
                speed=p.speed,
                battery=p.battery,
                recorded_at=to_utc_naive(p.recorded_at),
            )
        )
    db.commit()
    return {"saved": len(batch.pings)}


@app.get("/api/v1/users", dependencies=[Depends(require_api_key)])
def list_users(db: Session = Depends(get_db)):
    result = []
    for user in db.query(models.User).all():
        last = (
            db.query(models.Ping)
            .filter(models.Ping.user_id == user.id)
            .order_by(models.Ping.recorded_at.desc())
            .first()
        )
        if last is None:
            continue
        result.append(
            {
                "device_id": user.device_id,
                "name": user.name,
                "lat": last.lat,
                "lng": last.lng,
                "accuracy": last.accuracy,
                "speed": last.speed,
                "battery": last.battery,
                "last_seen": iso_z(last.recorded_at),
            }
        )
    return result


@app.get("/api/v1/users/{device_id}/history", dependencies=[Depends(require_api_key)])
def user_history(
    device_id: str,
    hours: int = Query(default=12, ge=1, le=168),
    db: Session = Depends(get_db),
):
    user = db.query(models.User).filter(models.User.device_id == device_id).first()
    if user is None:
        raise HTTPException(status_code=404, detail="Unknown device_id")

    since = datetime.utcnow() - timedelta(hours=hours)
    points = (
        db.query(models.Ping)
        .filter(models.Ping.user_id == user.id, models.Ping.recorded_at >= since)
        .order_by(models.Ping.recorded_at.asc())
        .limit(20000)
        .all()
    )
    return {
        "device_id": user.device_id,
        "name": user.name,
        "points": [
            {
                "lat": p.lat,
                "lng": p.lng,
                "speed": p.speed,
                "accuracy": p.accuracy,
                "battery": p.battery,
                "recorded_at": iso_z(p.recorded_at),
            }
            for p in points
        ],
    }


@app.get("/")
def dashboard():
    return FileResponse(STATIC_DIR / "index.html")
