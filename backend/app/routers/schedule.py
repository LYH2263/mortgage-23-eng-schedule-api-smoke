from fastapi import APIRouter
from app.schemas.schedule import ScheduleRequest
from app.services.mortgage_service import MortgageService
router = APIRouter()
@router.post("/schedule")
def post_schedule(body: ScheduleRequest):
    with MortgageService() as s:
        return s.schedule(body.principal, body.annual_rate, body.months, body.loan_id, body.persist, body.preview_rows)
