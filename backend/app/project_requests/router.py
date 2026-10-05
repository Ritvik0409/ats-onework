from fastapi import APIRouter
from typing import List, Dict, Any
from app.project_requests.schemas import ProjectRequestCreate, ProjectRequestApprove

router = APIRouter(prefix="/project_requests", tags=["Project Requests"])

@router.get("")
def get_project_requests():
    return []

@router.post("", status_code=201)
def create_project_request(req: ProjectRequestCreate):
    return {"message": "Project request submitted successfully", "data": req.dict()}

@router.post("/approve")
def approve_project_request(approval: ProjectRequestApprove):
    return {"message": "Project access approved successfully"}