from fastapi import APIRouter
from app.services.mortgage_service import MortgageService
router = APIRouter()
@router.get("/dashboard")
def dashboard():
    with MortgageService() as s: return s.dashboard()
