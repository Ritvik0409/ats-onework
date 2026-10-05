from fastapi import APIRouter
from app.budgets.schemas import BudgetCreate

router = APIRouter(prefix="/budgets", tags=["Budgets"])

@router.get("/{month}")
def get_budget(month: str):
    return {"month": month, "amount": 60000.0}

@router.post("", status_code=201)
def set_budget(budget: BudgetCreate):
    return {"message": "Budget set successfully", "data": budget.dict()}