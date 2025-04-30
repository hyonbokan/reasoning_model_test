from typing import List, Literal
from pydantic import BaseModel, Field

# -------------------- Final decision ------------------------
class Adjustment(BaseModel):
    index: int = Field(..., description="Original finding index")
    new_severity: Literal[
        "high", "medium", "low", "info", "best practices", "unchanged"
    ] = Field(..., description="Revised severity after checklist reasoning")
    should_be_removed: bool = Field(..., description="True = confirmed false‑positive")
    comments: str | None = Field(
        None, description="Optional clarification (≤ 120 chars)"
    )

# -------------------- Checklist answers --------------------
# Helper enums
_YN = Literal["yes", "no"]
_Impact = Literal["high", "medium", "low"]
_Likelihood = Literal["high", "medium", "low"]
_FinalSeverity = Literal["high", "medium", "low", "info", "best practices"]

class MitigationChecklist(BaseModel):
    # Overflow / Under‑flow
    O_1: _YN
    O_2: _YN
    O_3: _YN
    O_4: _YN
    O_5: _YN

    # Re‑entrancy
    R_1: _YN
    R_2: _YN
    R_3: _YN
    R_4: _YN
    R_5: _YN

    # Access control
    A_1: _YN
    A_2: _YN
    A_3: _YN

    # False‑positive filter
    F_1: _YN
    F_2: _YN
    F_3: _YN
    F_4: _YN
    F_5: _YN
    F_6: _YN  # final decision to remove

    # Severity rating
    S_1: _Impact
    S_2: _Likelihood
    S_3: _FinalSeverity

class FindingReview(BaseModel):
    finding_index: int = Field(..., description="Index of the analysed finding")
    checklist: MitigationChecklist = Field(..., description="Structured chain‑of‑thought answers")
    reasoning_summary: str = Field(..., description="≤ 3 sentence human‑readable rationale")
    adjustment: Adjustment

class AuditResponse(BaseModel):
    document_id: str
    finding_reviews: List[FindingReview]
