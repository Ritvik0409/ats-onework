from pydantic import BaseModel
from typing import Optional

class EmployeeStatusCreate(BaseModel):
    email: str
    isActive: bool
    updatedBy: Optional[str] = None