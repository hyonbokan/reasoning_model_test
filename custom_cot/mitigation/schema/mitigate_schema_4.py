# schema_5.py
from typing import List, Literal
from pydantic import BaseModel, Field

# helper aliases
_YN  = Literal["yes", "no"]
_IMP = Literal["high", "medium", "low"]
_LIK = Literal["high", "medium", "low"]
_SEV = Literal["high", "medium", "low", "info", "best practices"]

class MitigationChecklist(BaseModel):
    # Overflow
    O_1: _YN = Field(..., description="Is the finding explicitly about arithmetic overflow / under-flow?")
    O_2: _YN = Field(..., description="Is the contract compiled with Solidity ≥ 0.8.0 (auto-checks enabled)?")
    O_3: _YN = Field(..., description="Does the arithmetic lie inside an `unchecked {}` block?")
    O_4: _YN = Field(..., description="Is there a business requirement to handle overflow differently than revert?")
    O_5: _YN = Field(..., description="Is the overflow part of a larger exploit chain?")
    # Reentrancy
    R_1: _YN = Field(..., description="Does the function call an external *untrusted* contract?")
    R_2: _YN = Field(..., description="Are state changes executed *after* that external call?")
    R_3: _YN = Field(..., description="Is **no** reentrancy guard present?")
    R_4: _YN = Field(..., description="Is the CEI pattern **not** followed?")
    R_5: _YN = Field(..., description="Is the call internal (same contract) rather than external?")
    # Access control
    A_1: _YN = Field(..., description="Can an un-privileged user call the privileged function?")
    A_2: _YN = Field(..., description="Does this violate decentralisation / timelock assumptions?")
    A_3: _YN = Field(..., description="Does the issue enable critical protocol manipulation?")
    # False-positive tests
    F_1: _YN = Field(..., description="Is the finding duplicated elsewhere?")
    F_2: _YN = Field(..., description="Is the behaviour clearly documented or intended by design?")
    F_3: _YN = Field(..., description="Is the issue purely theoretical with no exploit?")
    F_4: _YN = Field(..., description="Overflow case: ≥0.8 **and** no `unchecked`?")
    F_5: _YN = Field(..., description="Reentrancy case: proper guards or CEI present?")
    F_6: _YN = Field(..., description="Should this finding be marked a false positive and removed?")
    # Severity
    S_1: _IMP = Field(..., description="Impact category")
    S_2: _LIK = Field(..., description="Likelihood category")
    S_3: _SEV = Field(..., description="Matrix-derived severity")

class Adjustment(BaseModel):
    index: int
    new_severity: _SEV | Literal["unchanged"]
    should_be_removed: bool
    comments: str | None = None

class FindingResponse(BaseModel):
    strategy: MitigationChecklist
    reasoning_summary: str
    adjustment: Adjustment

class AuditResponse(BaseModel):
    document_id: str
    findings: List[FindingResponse]