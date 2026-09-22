from fastapi import APIRouter
from app.services.mortgage_service import MortgageService
router = APIRouter()
@router.get("/settings")
def settings():
    with MortgageService() as s: return s.settings()
