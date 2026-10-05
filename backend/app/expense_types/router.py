from fastapi import APIRouter
from app.expense_types.schemas import ExpenseTypeCreate

router = APIRouter(prefix="/expense_types", tags=["Expense Types"])

@router.get("")
def get_expense_types():
    return []

@router.post("", status_code=201)
def create_expense_type(expense_type: ExpenseTypeCreate):
    return {"message": "Expense type added successfully", "data": expense_type.dict()}