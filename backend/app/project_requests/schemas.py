from pydantic import BaseModel
from typing import Optional

class ProjectRequestCreate(BaseModel):
    email: str
    name: str
    status: Optional[str] = "Pending Assignment"

class ProjectRequestApprove(BaseModel):
    email: str
    projectId: str