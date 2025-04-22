from typing import List, Literal, Union
from pydantic import BaseModel, Field

class CodeRef(BaseModel):
    file: str
    lines: list[int]
    why: str

class QA(BaseModel):
    question_id: str
    answer: str
    refs: list[CodeRef] | None = None

class Adjustment(BaseModel):
    index: int
    new_severity: Literal["high","medium","low","info","best practices","unchanged"]
    should_be_removed: bool
    comments: str | None = None

class FindingReview(BaseModel):
    finding_index: int
    step_by_step_analysis: str               # ← free‑form CoT
    reasoning_summary: str                   # ← 1‑3 sentences max
    qa_trace: list[QA]                       # ← structured gates
    adjustment: Adjustment

class AuditResponse(BaseModel):
    document_id: str
    finding_reviews: list[FindingReview]
