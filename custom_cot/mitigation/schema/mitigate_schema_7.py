"""
Schema-7  – Three-stage custom CoT
-----------------------------------
• Stage-1  facts      : overflow / re-entrancy / access booleans (+ refs)
• Stage-2  fp         : false-positive gate derived from facts
• Stage-3  severity   : impact × likelihood → matrix
• adjustment          : single final decision
"""
from __future__ import annotations
from typing    import List, Literal
from pydantic  import BaseModel, Field, model_validator


# --- primitive enums -------------------------------------------------
_YN  = Literal["yes", "no"]
_IMP = Literal["high", "medium", "low"]
_LIK = _IMP
_SEV = Literal["high", "medium", "low", "info", "best practices"]


# ───────────────── evidence helper ────────────────────────────────
class CodeRef(BaseModel):
    file : str                           
    lines: List[int]                    # 1-based
    why  : str | None = None            # ≤ 40 chars

class CheckedYN(BaseModel):
    answer: _YN
    # refs  : List[CodeRef] | None = None

# ═══════════════════════════════════════════════════════════════════════════
# Stage-1 facts
# ═══════════════════════════════════════════════════════════════════════════
class FactChecklist(BaseModel):
# ---------- Overflow / Under-flow  -----------------------------------------
    # STEP 1 ───────── Identify scope
    O_1: CheckedYN = Field(
        ...,
        description=(
            "STEP 1 — Is the *core* of this finding arithmetic overflow / under-flow?\n"
            "- yes : the bug relies on wrapping / truncation.\n"
            "- no  : overflow is incidental or not in scope.\n"
            "Note: losing bits via signed→unsigned *or* via narrowing cast counts as overflow."
        ),
    )

    # STEP 2 ───────── Compiler auto-checks
    O_2: CheckedYN = Field(
        ...,
        description=(
            "STEP 2 — Is the contract compiled with Solidity ≥ 0.8.0?\n"
            "Rule: ≥0.8 auto-reverts on **all** arithmetic *except*:\n"
            "  • type-casts (e.g. uint256→uint128)\n"
            "  • inline assembly or low-level `add`, `sub`.\n"
            "If unknown, assume the pragma shown at the top of the file."
        ),
    )

    # STEP 3 ───────── Bypass mechanisms
    O_3: CheckedYN = Field(
        ...,
        description=(
            "STEP 3 — Is there **any** bypass of auto-checks?\n"
            "  - `unchecked {}` block around the math, **or**\n"
            "  - explicit assembly / `unsafeMath` / `addmod`, **or**\n"
            "  - narrowing cast that can wrap (e.g. uint256→uint8).\n"
            "yes : at least one bypass is present.\n"
            "no  : none of the above."
        ),
    )

    # STEP 4 ───────── Business intent
    O_4: CheckedYN = Field(
        ...,
        description=(
            "STEP 4 — Is there a documented business requirement to *allow* wrapping\n"
            "instead of reverting? Examples: counter roll-over, ring-buffer index.\n"
            "yes : spec, comment, or unit test proves intentional wrap.\n"
            "no  : no such evidence."
        ),
    )

    # STEP 5 ───────── Exploit chain
    O_5: CheckedYN = Field(
        ...,
        description=(
            "STEP 5 — Does this overflow feed a *larger* exploit chain\n"
            "(e.g. price manipulation, privilege escalation)?\n"
            "yes : overflow is one link in a multi-step attack.\n"
            "no  : standalone wrap only."
        ),
    )

    # ---------- Re-entrancy ----------------------------------------------------
    # STEP 1 ───────── External control transfer?
    R_1: CheckedYN = Field(
        ...,
        description=(
            "STEP 1 — Does the function transfer control to **un-trusted code**?\n"
            "Count any of the following as **yes**:\n"
            "  • Interface / library call to a contract held in storage or calldata\n"
            "  • `call`, `delegatecall`, `staticcall`, `.send`, `.transfer`\n"
            "  • ERC-20 / ERC-721 hooks (tokenFallback, onERC721Received)\n"
            "Ignore:\n"
            "  • `view`/`pure` targets that cannot execute user code\n"
            "  • Calls to contracts explicitly whitelisted in storage (e.g. router = address(0x123…))."
        ),
    )

    # STEP 2 ───────── Effects after interaction?
    R_2: CheckedYN = Field(
        ...,
        description=(
            "STEP 2 — Are there **ANY** contract-storage writes *after* the external call on the same execution path?\n"
            "- yes : at least one `SSTORE`, mapping update, array push, etc. appears **below** the call\n"
            "- no  : *all* writes occur beforehand, and therefore CEI respected"
        ),
    )

    # STEP 3 ───────── Guard present?
    R_3: CheckedYN = Field(
        ...,
        description=(
            "STEP 3 — Is **no** re-entrancy guard present?\n"
            "'Guard' means:\n"
            "  • OpenZeppelin `nonReentrant` **or**\n"
            "  • A custom mutex (bool lock; require(!lock); lock=true; …; lock=false)\n"
            "Answer **yes** only if NONE of the above exist."
        ),
    )

    # STEP 4 ───────── CEI status (derived)
    R_4: CheckedYN = Field(
        ...,
        description=(
            "STEP 4 — Is the CEI pattern **broken**?\n"
            "Rule: answer **yes** iff R_1 = yes *and* R_2 = yes.\n"
            "Otherwise answer **no**. (This field can be auto-derived)."
        ),
    )

    # STEP 5 ───────── Internal-only call?
    R_5: CheckedYN = Field(
        ...,
        description=(
            "STEP 5 — Is the call internal-only (same contract, no `delegatecall`)?\n"
            "- yes : Solidity `internal` / `private` function without low-level external call\n"
            "- no  : any external address involved.\n"
            "If R_5 = yes the issue is automatically a false-positive."
        ),
    )

    # ---------- Access control -------------------------------------------------
    # STEP 1 ── Un-authorised reachability
    A_1: CheckedYN = Field(
        ...,
        description=(
            "STEP 1 — Can an **un-privileged** account *directly or indirectly* call the target "
            "function?\n"
            "• yes : no `onlyOwner`, `onlyRole`, governor-only or msg.sender check prevents it\n"
            "• no  : proper access check present on every entry-point"
        ),
    )

    # STEP 2 ── Centralisation / role quality
    A_2: CheckedYN = Field(
        ...,
        description=(
            "STEP 2 — Is the privileged role **centralised** in a single EOA or small multisig "
            "without delay?\n"
            "• yes : single EOA owner, 2-of-2 multisig, upgrade controlled by dev key, etc.\n"
            "• no  : DAO vote, >=3-of-5 multisig, or time-lock ≥ 24 h."
        ),
    )

    # STEP 3 ── Mitigations present?
    A_3: CheckedYN = Field(
        ...,
        description=(
            "STEP 3 — Are mitigation controls **missing**?\n"
            "Mitigations include: Timelock, multisig ≥ 3-of-n, role revocation, pause guardian.\n"
            "• yes : none of the above in place for the risky function.\n"
            "• no  : at least one mitigation applies."
        ),
    )

    # STEP 4 ── Critical impact?
    A_4: CheckedYN = Field(
        ...,
        description=(
            "STEP 4 — Does the ability enable **critical protocol manipulation**?\n"
            "Examples: mint/burn tokens, upgrade core contracts, drain reserves, freeze user funds."
        ),
    )


# ═══════════════════════════════════════════════════════════════════════════
#  Stage-2  FALSE-POSITIVE decision -- enriched with descriptions & refs
# ═══════════════════════════════════════════════════════════════════════════
class FPDecision(BaseModel):
    duplicate     : CheckedYN = Field(
        ...,
        description="Another finding covers the same root cause (>70 % text overlap or identical code refs)."
    )
    design_intent : CheckedYN = Field(
        ...,
        description="Behaviour is clearly specified or commented as intentional (e.g. overflow counter)."
    )
    auto_checked  : CheckedYN = Field(
        ...,
        description="Overflow auto-reverted (≥0.8 and no bypass) **or** vulnerable math is never reachable by external users."
    )
    guarded       : CheckedYN = Field(
        ...,
        description="Re-entrancy properly protected (nonReentrant, mutex) **or** CEI fully respected."
    )

    # derived field ----------------------------------------------------------
    removal_reason : Literal[
        "duplicate", "design_intent", "auto_checked", "guarded", "none"
    ] = Field(
        default="none",
        description="Resolver: choose first true flag in order duplicate › design_intent › auto_checked › guarded; else 'none'."
    )

    @model_validator(mode="after")
    def _derive_reason(cls, v):
        mapping = [
            ("duplicate",     v.duplicate.answer),
            ("design_intent", v.design_intent.answer),
            ("auto_checked",  v.auto_checked.answer),
            ("guarded",       v.guarded.answer),
        ]
        for tag, flag in mapping:
            if flag == "yes":
                v.removal_reason = tag
                break
        return v

# ═══════════════════════════════════════════════════════════════════════════
#  Stage-3  SEVERITY decision -- descriptions + matrix check
# ═══════════════════════════════════════════════════════════════════════════
class SeverityDecision(BaseModel):
    impact: _IMP = Field(
        ...,
        description="High: protocol-wide loss / control.  Medium: significant but recoverable.  Low: nuisance."
    )
    likelihood : _LIK = Field(
        ...,
        description="High: trivial or already exploitable.  Medium: feasible.  Low: highly unlikely."
    )
    matrix: _SEV = Field(
        ...,
        description=(
            "Lookup from impact×likelihood matrix.  If torn between two, pick the lower."
        )
    )

    @model_validator(mode="after")
    def _validate(cls, v):
        tbl = {("high","high"):"high", ("high","medium"):"medium",
               ("high","low"):"medium", ("medium","high"):"high",
               ("medium","medium"):"medium", ("medium","low"):"low",
               ("low","high"):"medium", ("low","medium"):"low",
               ("low","low"):"low"}
        expected = tbl[(v.impact, v.likelihood)]
        if v.matrix != expected:
            v.matrix = expected
        return v


# ═══════════════════════════════════════════════════════════════════════════
#  Bundle   (facts  → fp  → severity)
# ═══════════════════════════════════════════════════════════════════════════

class FindingStrategy(BaseModel):
    facts    : FactChecklist
    fp       : FPDecision
    severity : SeverityDecision | None = None

# ---------------------------------------------------------------------------
class Adjustment(BaseModel):
    index             : int
    final_severity    : _SEV | Literal["unchanged"]
    should_be_removed : bool
    comments          : str | None = None

class FindingResponse(BaseModel):
    strategy: FindingStrategy = Field(
        ...,
        description="Three-stage reasoning pipeline: facts → false-positive gate → severity."
    )
    reasoning_summary : str = Field(
        ...,
        description=(
        "Mention one pivotal fact, the FP decision (or why not removed), and the final severity."
        "Example: \"Overflow auto-checked (O_2 yes, O_3 no) so removal_reason=auto_checked;"
        "finding removed.\""
        ),
    )
    adjustment: Adjustment = Field(
        ...,
        description=(
            "The final corrective action:\n"
            "• index             : original finding index\n"
            "• final_severity    : new severity or 'unchanged'\n"
            "• should_be_removed : true if the finding is to be dropped\n"
            "• comments          : any free-form rationale or notes"
        ),
    )

class AuditResponse(BaseModel):
    document_id : str
    findings    : List[FindingResponse]