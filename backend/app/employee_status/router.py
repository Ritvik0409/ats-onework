from fastapi import APIRouter
from app.employee_status.schemas import EmployeeStatusCreate

router = APIRouter(prefix="/employee_status", tags=["Employee Status"])

@router.get("")
def get_employee_statuses():
    return []

@router.post("", status_code=201)
def set_employee_status(status_data: EmployeeStatusCreate):
    return {"message": "Employee status updated successfully", "data": status_data.dict()}