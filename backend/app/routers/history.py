from fastapi import APIRouter
from app.services.mortgage_service import MortgageService
router = APIRouter()
@router.get("/history")
def history(limit: int = 50):
    with MortgageService() as s: return {"items": s.history(limit)}
