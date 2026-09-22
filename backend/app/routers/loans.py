from fastapi import APIRouter, HTTPException
from app.services.mortgage_service import MortgageService
router = APIRouter()
@router.get("/loans")
def list_loans():
    with MortgageService() as s: return {"items": s.list_loans()}
@router.get("/loans/{loan_id}")
def get_loan(loan_id: int):
    with MortgageService() as s:
        row = s.loan(loan_id)
        if not row: raise HTTPException(404)
        return row
