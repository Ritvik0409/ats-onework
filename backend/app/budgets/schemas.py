from pydantic import BaseModel

class BudgetCreate(BaseModel):
    month: str
    amount: float
    setByEmail: str
    setByName: str