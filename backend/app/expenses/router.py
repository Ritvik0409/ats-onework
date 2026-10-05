from fastapi import APIRouter
from app.expenses.schemas import ExpenseCreate, ExpenseUpdate

router = APIRouter(prefix="/expenses", tags=["Expenses"])

@router.get("")
def get_expenses():
    return []

@router.post("", status_code=201)
def create_expense(expense: ExpenseCreate):
    return {"message": "Expense created successfully", "data": expense.dict()}

@router.patch("/{expense_id}")
def update_expense(expense_id: str, update_data: ExpenseUpdate):
    return {"message": f"Expense {expense_id} updated successfully"}