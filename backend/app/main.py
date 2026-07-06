import os
from datetime import datetime, timedelta, timezone
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from sqlalchemy import inspect
from sqlalchemy.orm import Session as OrmSession

from . import models
from .database import Base, engine, get_db
from .schemas import EventIn, LoginIn, PingBatch, RegisterIn
from .security import hash_password, new_token, verify_password

API_KEY = os.getenv("API_KEY", "change-me-please")
ADMIN_EMAIL = os.getenv("ADMIN_EMAIL", "").strip().lower()
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "")
STATIC_DIR = Path(__file__).resolve().parent.parent / "static"

# How long without a ping before we consider a device offline (minutes).
OFFLINE_AFTER_MIN = 15


def run_migrations():
    """Create tables. If an old pre-auth `users` table exists (no email
    column), drop everything once and recreate with the new schema.
    Only test data exists at this stage, so this is safe."""
    insp = inspect(engine)
    if "users" in insp.get_table_names():
        cols = [c["name"] for c in insp.get_columns("users")]
        if "email" not in cols:
            Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)


def seed_admin():
    if not ADMIN_EMAIL or not ADMIN_PASSWORD:
        return
    db = next(get_db())
    try:
        admin = db.query(models.User).filter(models.User.email == ADMIN_EMAIL).first()
        if admin is None:
            db.add(
                models.User(
                    email=ADMIN_EMAIL,
                    password_hash=hash_password(ADMIN_PASSWORD),
                    name="Admin",
                    role="admin",
                )
            )
        else:
            admin.role = "admin"
            admin.password_hash = hash_password(ADMIN_PASSWORD)
        db.commit()
    finally:
        db.close()


run_migrations()
seed_admin()

app = FastAPI(title="Field Tracker API", version="0.2.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ----------------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------------
def to_utc_naive(dt: datetime) -> datetime:
    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt


def iso_z(dt: datetime) -> str:
    return dt.replace(microsecond=0).isoformat() + "Z"


def _token_from(authorization: str) -> str:
    if authorization.lower().startswith("bearer "):
        return authorization[7:].strip()
    return authorization.strip()


def current_user(
    authorization: str = Header(default=""),
    db: OrmSession = Depends(get_db),
) -> models.User:
    token = _token_from(authorization)
    if not token:
        raise HTTPException(status_code=401, detail="Not logged in")
    sess = db.query(models.Session).filter(models.Session.token == token).first()
    if sess is None:
        raise HTTPException(status_code=401, detail="Session expired, log in again")
    return sess.user


def require_admin(
    x_api_key: str = Header(default=""),
    authorization: str = Header(default=""),
    db: OrmSession = Depends(get_db),
) -> None:
    # Master key (used by the deploy owner / scripts).
    if x_api_key and x_api_key == API_KEY:
        return
    # Or an admin account token.
    token = _token_from(authorization)
    if token:
        sess = db.query(models.Session).filter(models.Session.token == token).first()
        if sess and sess.user.role == "admin":
            return
    raise HTTPException(status_code=401, detail="Admin login required")


def issue_session(db: OrmSession, user: models.User) -> str:
    token = new_token()
    db.add(models.Session(token=token, user_id=user.id))
    db.commit()
    return token


# ----------------------------------------------------------------------------
# auth
# ----------------------------------------------------------------------------
@app.get("/api/v1/health")
def health():
    return {"status": "ok"}


@app.post("/api/v1/auth/register")
def register(body: RegisterIn, db: OrmSession = Depends(get_db)):
    email = body.email.lower()
    existing = db.query(models.User).filter(models.User.email == email).first()
    if existing is not None:
        raise HTTPException(status_code=409, detail="An account with this email already exists. Log in instead.")
    user = models.User(
        email=email,
        password_hash=hash_password(body.password),
        name=body.name.strip(),
        role="staff",
    )
    db.add(user)
    db.commit()
    token = issue_session(db, user)
    return {"token": token, "name": user.name, "email": user.email, "role": user.role}


@app.post("/api/v1/auth/login")
def login(body: LoginIn, db: OrmSession = Depends(get_db)):
    email = body.email.lower()
    user = db.query(models.User).filter(models.User.email == email).first()
    if user is None or not verify_password(body.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Wrong email or password")
    token = issue_session(db, user)
    return {"token": token, "name": user.name, "email": user.email, "role": user.role}


# ----------------------------------------------------------------------------
# device -> server
# ----------------------------------------------------------------------------
@app.post("/api/v1/pings")
def receive_pings(
    batch: PingBatch,
    db: OrmSession = Depends(get_db),
    user: models.User = Depends(current_user),
):
    if batch.device_id:
        user.device_id = batch.device_id
    user.tracking_enabled = True  # pings are arriving, so tracking is on
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


@app.post("/api/v1/events")
def receive_event(
    body: EventIn,
    db: OrmSession = Depends(get_db),
    user: models.User = Depends(current_user),
):
    db.add(
        models.Event(
            user_id=user.id,
            type=body.type,
            detail=body.detail,
            recorded_at=to_utc_naive(body.recorded_at),
        )
    )
    if body.type == "tracking_off":
        user.tracking_enabled = False
    elif body.type == "tracking_on":
        user.tracking_enabled = True
    db.commit()
    return {"ok": True}


# ----------------------------------------------------------------------------
# dashboard (admin)
# ----------------------------------------------------------------------------
@app.get("/api/v1/users", dependencies=[Depends(require_admin)])
def list_users(db: OrmSession = Depends(get_db)):
    result = []
    for user in db.query(models.User).filter(models.User.role == "staff").all():
        last = (
            db.query(models.Ping)
            .filter(models.Ping.user_id == user.id)
            .order_by(models.Ping.recorded_at.desc())
            .first()
        )
        last_event = (
            db.query(models.Event)
            .filter(models.Event.user_id == user.id)
            .order_by(models.Event.recorded_at.desc())
            .first()
        )
        result.append(
            {
                "id": user.id,
                "email": user.email,
                "name": user.name,
                "tracking_enabled": user.tracking_enabled,
                "lat": last.lat if last else None,
                "lng": last.lng if last else None,
                "accuracy": last.accuracy if last else None,
                "speed": last.speed if last else None,
                "battery": last.battery if last else None,
                "last_seen": iso_z(last.recorded_at) if last else None,
                "last_event": (
                    {"type": last_event.type, "at": iso_z(last_event.recorded_at)}
                    if last_event
                    else None
                ),
            }
        )
    return result


@app.get("/api/v1/users/{user_id}/history", dependencies=[Depends(require_admin)])
def user_history(
    user_id: int,
    hours: int = Query(default=12, ge=1, le=168),
    db: OrmSession = Depends(get_db),
):
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=404, detail="Unknown user")

    since = datetime.utcnow() - timedelta(hours=hours)
    points = (
        db.query(models.Ping)
        .filter(models.Ping.user_id == user.id, models.Ping.recorded_at >= since)
        .order_by(models.Ping.recorded_at.asc())
        .limit(20000)
        .all()
    )
    return {
        "id": user.id,
        "name": user.name,
        "points": [
            {
                "lat": p.lat,
                "lng": p.lng,
                "speed": p.speed,
                "battery": p.battery,
                "recorded_at": iso_z(p.recorded_at),
            }
            for p in points
        ],
    }


@app.get("/api/v1/events", dependencies=[Depends(require_admin)])
def list_events(
    hours: int = Query(default=24, ge=1, le=336),
    db: OrmSession = Depends(get_db),
):
    since = datetime.utcnow() - timedelta(hours=hours)
    rows = (
        db.query(models.Event)
        .filter(models.Event.recorded_at >= since)
        .order_by(models.Event.recorded_at.desc())
        .limit(500)
        .all()
    )
    out = []
    for e in rows:
        out.append(
            {
                "user_id": e.user_id,
                "name": e.user.name,
                "type": e.type,
                "detail": e.detail,
                "at": iso_z(e.recorded_at),
            }
        )
    return out


@app.get("/")
def dashboard():
    return FileResponse(STATIC_DIR / "index.html")
