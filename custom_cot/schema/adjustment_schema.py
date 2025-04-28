from pydantic import BaseModel, Field
from typing import Literal

class Adjustment(BaseModel):
    index: int
    severity: Literal["high","medium","low","info","best practices","unchanged"]
    should_be_removed: bool
    comments: str | None = None

class OneAdjustmentResponse(BaseModel):
    adjustment: Adjustment          # ← single finding

class AdjustmentsResponse(BaseModel):
    document_id: str
    adjustments: list[Adjustment]   # ← many findings