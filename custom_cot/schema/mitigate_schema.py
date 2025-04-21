from typing import List, Literal, Union
from pydantic import BaseModel, Field

class CodeRef(BaseModel):
    file: str
    lines: List[int]
    why: str


# ---------- answer variants ----------
class YesNoQA(BaseModel):
    question_id: str  # e.g. "O-1"
    answer: Literal["yes", "no"]
    refs: List[CodeRef] | None = None
    confidence: float | None = Field(
        None, ge=0.0, le=1.0,
        description="0‑10 subjective confidence score"
    )

class ImpactQA(BaseModel):
    question_id: Literal["S-1"]
    answer: Literal["high", "medium", "low"]
    refs: List[CodeRef] | None = None
    confidence: float | None = None

class LikelihoodQA(BaseModel):
    question_id: Literal["S-2"]
    answer: Literal["high", "medium", "low"]
    refs: List[CodeRef] | None = None
    confidence: float | None = None

class SeverityQA(BaseModel):
    question_id: Literal["S-3"]
    answer: Literal["high", "medium", "low", "info", "best practices"]
    refs: List[CodeRef] | None = None
    confidence: float | None = None

QA = Union[YesNoQA, ImpactQA, LikelihoodQA, SeverityQA]

# ---------- summary decision ----------
class Adjustment(BaseModel):
    index: int
    new_severity: Literal[
        "high", "medium", "low", "info", "best practices", "unchanged"
    ]
    should_be_removed: bool
    comments: str | None = None

class FindingReview(BaseModel):
    finding_index: int
    qa_trace: List[QA]          # explicit custom CoT
    adjustment: Adjustment

class AuditResponse(BaseModel):
    document_id: str
    finding_reviews: List[FindingReview]