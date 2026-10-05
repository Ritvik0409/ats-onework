from pydantic import BaseModel

class ExpenseTypeCreate(BaseModel):
    name: str