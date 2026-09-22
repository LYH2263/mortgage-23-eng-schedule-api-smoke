from fastapi import APIRouter
from app.routers import dashboard, history, loans, schedule, settings
api = APIRouter(prefix="/api")
for r in (dashboard, loans, schedule, history, settings): api.include_router(r.router)
