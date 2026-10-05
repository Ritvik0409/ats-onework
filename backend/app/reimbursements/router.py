from fastapi import APIRouter
from app.reimbursements.schemas import ReimbursementCreate, ReimbursementUpdate

router = APIRouter(prefix="/reimbursements", tags=["Reimbursements"])

@router.get("")
def get_reimbursements():
    return []

@router.post("", status_code=201)
def create_reimbursement(reimb: ReimbursementCreate):
    return {"message": "Reimbursement created successfully", "data": reimb.dict()}

@router.patch("/{reimb_id}")
def update_reimbursement(reimb_id: str, payload: ReimbursementUpdate):
    return {"message": f"Reimbursement {reimb_id} updated successfully"}