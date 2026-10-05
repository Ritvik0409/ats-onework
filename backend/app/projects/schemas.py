from pydantic import BaseModel
from typing import List, Optional

class ProjectCreate(BaseModel):
    name: str
    budget: float
    assignedEmails: List[str] = []
    isActive: Optional[bool] = True

class ProjectUpdate(BaseModel):
    budget: Optional[float] = None
    isActive: Optional[bool] = None

class ProjectMembersUpdate(BaseModel):
    employeeIds: Optional[List[str]] = None
    email: Optional[str] = None