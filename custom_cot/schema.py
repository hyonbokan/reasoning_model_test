# schema.py
from typing import List, Literal, Union
from pydantic import BaseModel, Field

class CodeRef(BaseModel):
    file: str
    lines: List[int]
    why: str

class QA(BaseModel):
    question_id: str
    answer: str                           # e.g. "yes", "no", "high"
    refs: List[CodeRef] | None = None

class Adjustment(BaseModel):
    index: int                            # finding index from original list
    new_severity: Literal[
        "high", "medium", "low",
        "info", "best practices", "unchanged"
    ]
    should_be_removed: bool
    comments: str | None = None

class FindingReview(BaseModel):
    finding_index: int
    qa_trace: List[QA]                    # ← explicit CoT
    adjustment: Adjustment

class AuditResponse(BaseModel):
    document_id: str
    finding_reviews: List[FindingReview]