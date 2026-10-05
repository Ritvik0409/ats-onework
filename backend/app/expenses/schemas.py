from pydantic import BaseModel
from typing import Optional

class ExpenseCreate(BaseModel):
    employeeId: str
    employeeName: str
    email: str
    type: str
    amount: float
    date: str
    description: str
    status: Optional[str] = "Pending Verification"
    receiptBase64: Optional[str] = None
    projectName: Optional[str] = None
    uploaderRole: Optional[str] = "employee"

class ExpenseUpdate(BaseModel):
    status: Optional[str] = None
    rejectionReason: Optional[str] = None
    processedBy: Optional[str] = None
    transactionId: Optional[str] = None
    paymentReceiptUrl: Optional[str] = None