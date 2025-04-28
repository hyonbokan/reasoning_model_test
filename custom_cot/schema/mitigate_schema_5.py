from typing import List, Literal
from pydantic import BaseModel, Field

# --- primitive enums -------------------------------------------------
_YN  = Literal["yes", "no"]
_IMP = Literal["high", "medium", "low"]
_LIK = _IMP
_SEV = Literal["high", "medium", "low", "info", "best practices"]

# --- evidence helper -------------------------------------------------
class CodeRef(BaseModel):
    file: str
    lines: List[int]
    why:  str | None = None

class CheckedYN(BaseModel):
    answer: _YN
    refs:   List[CodeRef] | None = None

# --- strategy (= custom CoT) ----------------------------------------
class MitigationChecklist(BaseModel):
    # ---------- Overflow / Under-flow -----------------------------------------
    O_1: CheckedYN = Field(
        ...,
        description=(
            "Is the finding explicitly about arithmetic overflow / under-flow?\n"
            "- yes : numeric wrap is the bug’s core\n"
            "- no  : overflow is incidental / not raised\n"
            "Edge: signed→unsigned cast counts as overflow."
        ),
    )
    O_2: CheckedYN = Field(
        ...,
        description=(
            "Is the contract compiled with Solidity ≥ 0.8.0?\n"
            "Rule: ≥0.8 auto-reverts on arithmetic but **not** on casts."
        ),
    )
    O_3: CheckedYN = Field(
        ...,
        description="Does the vulnerable arithmetic lie inside an `unchecked {}` block?",
    )
    O_4: CheckedYN = Field(
        ...,
        description="Is there a business requirement to handle overflow differently than revert?",
    )
    O_5: CheckedYN = Field(
        ...,
        description="Is this overflow part of a larger exploit chain?",
    )

    # ---------- Re-entrancy ----------------------------------------------------
    R_1: CheckedYN = Field(
        ...,
        description="Does the function call an external *untrusted* contract?",
    )
    R_2: CheckedYN = Field(
        ...,
        description="Are state changes executed *after* that external call?",
    )
    R_3: CheckedYN = Field(
        ...,
        description="Is **no** re-entrancy guard (`nonReentrant`, etc.) present?",
    )
    R_4: CheckedYN = Field(
        ...,
        description="Is the CEI (Checks-Effects-Interactions) pattern **NOT** followed?",
    )
    R_5: CheckedYN = Field(
        ...,
        description="Is the call internal (same contract) rather than external?",
    )

    # ---------- Access control -------------------------------------------------
    A_1: CheckedYN = Field(
        ...,
        description="Can an un-privileged user call the privileged function?",
    )
    A_2: CheckedYN = Field(
        ...,
        description="Does this violate decentralisation / timelock assumptions?",
    )
    A_3: CheckedYN = Field(
        ...,
        description="Does the issue enable critical protocol manipulation?",
    )

    # ---------- False-positive filters ----------------------------------------
    F_1: CheckedYN = Field(
        ...,
        description="Is the finding duplicated elsewhere in the report?",
    )
    F_2: CheckedYN = Field(
        ...,
        description="Is the behaviour clearly documented or intended by design?",
    )
    F_3: CheckedYN = Field(
        ...,
        description="Is the issue purely theoretical with no practical exploit path?",
    )
    F_4: CheckedYN = Field(
        ...,
        description="Overflow case: Solidity ≥0.8 **and** no `unchecked` block present?",
    )
    F_5: CheckedYN = Field(
        ...,
        description="Re-entrancy case: proper guard or CEI pattern present?",
    )

    removal_reason: Literal[
        "duplicate", "design_intent", "auto_checked", "guarded", "none"
    ] = Field(
        default="none",
        description=(
            "If the finding should be removed, indicate why:\n"
            "- duplicate        : same issue elsewhere\n"
            "- design_intent    : behaviour is intentional\n"
            "- auto_checked     : overflow auto-reverted (≥0.8, no unchecked)\n"
            "- guarded          : re-entrancy guard / CEI in place\n"
            "- none             : keep the finding"
        ),
    )

    # ---------- Severity derivation -------------------------------------------
    impact:      _IMP = Field(..., description="Impact category (high/medium/low)")
    likelihood:  _LIK = Field(..., description="Likelihood category (high/medium/low)")
    matrix_severity: _SEV = Field(
        ...,
        description=(
            "Severity derived from matrix:\n"
            "impact\\likelihood  high  medium  low\n"
            "high                high  medium  medium\n"
            "medium              high  medium  low\n"
            "low                 medium low    low"
        ),
    )

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