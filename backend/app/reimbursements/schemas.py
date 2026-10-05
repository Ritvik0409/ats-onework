from pydantic import BaseModel
from typing import Optional

class ReimbursementCreate(BaseModel):
    expenseId: str
    amount: float
    employeeEmail: str

class ReimbursementUpdate(BaseModel):
    status: Optional[str] = None