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

    # ---------- False-positive filters  ------------------------------------------
    # STEP 0  – de-duplication
    F_1: CheckedYN = Field(
        ...,
        description=(
            "STEP 0 — Duplicate?  Does another finding already cover the *same* root cause?\n"
            "yes : remove and set removal_reason = 'duplicate'."
        ),
    )

    # STEP 1  – design intent / spec
    F_2: CheckedYN = Field(
        ...,
        description=(
            "STEP 1 — Is the behaviour **explicitly intended** and documented "
            "(spec comment, README, audit notes)?\n"
            "yes : set removal_reason = 'design_intent'."
        ),
    )

    # STEP 2  – purely theoretical
    F_3: CheckedYN = Field(
        ...,
        description=(
            "STEP 2 — Purely theoretical (no feasible exploit path, requires impossible pre-conditions)?\n"
            "yes : downgrade to 'Info' or set removal_reason = 'none' and severity = Info."
        ),
    )

    # STEP 3a – overflow auto-checked
    F_4: CheckedYN = Field(
        ...,
        description=(
            "STEP 3.a — Overflow FP: Solidity ≥ 0.8 **AND** no bypass (no `unchecked`, no narrowing cast, "
            "no inline assembly math).\n"
            "yes : set removal_reason = 'auto_checked'."
        ),
    )

    # STEP 3b – internal-only overflow
    F_6: CheckedYN = Field(
        ...,
        description=(
            "STEP 3.b — Overflow in an **internal / private** function that is never called by "
            "external / public code?\n"
            "yes : set removal_reason = 'auto_checked' (cannot be exploited)."
        ),
    )

    # STEP 4a – re-entrancy correctly guarded
    F_5: CheckedYN = Field(
        ...,
        description=(
            "STEP 4.a — Re-entrancy FP: Proper guard (`nonReentrant` or mutex) "
            "OR CEI fully respected.\n"
            "yes : set removal_reason = 'guarded'."
        ),
    )

    # STEP 4b – internal-only external-call wrapper
    F_7: CheckedYN = Field(
        ...,
        description=(
            "STEP 4.b — Re-entrancy: call is internal-only wrapper with no user-controlled delegatecall.\n"
            "yes : set removal_reason = 'guarded'."
        ),
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
    impact: _IMP = Field(
        ...,
        description=(
            "Impact category:\n"
            "- high   : protocol-wide loss, permanent funds theft, or critical control loss\n"
            "- medium : significant financial or functional loss, but recoverable\n"
            "- low    : limited scope or value; nuisance not critical\n"
            "**Pick one: high / medium / low.**"
        ),
    )

    likelihood: _LIK = Field(
        ...,
        description=(
            "Likelihood category (how easy to exploit):\n"
            "- high   : trivial or already exploitable in prod\n"
            "- medium : feasible with moderate effort / conditions\n"
            "- low    : highly unlikely, requires extreme conditions\n"
            "**Pick one: high / medium / low.**"
        ),
    )

    matrix_severity: _SEV = Field(
        ...,
        description=(
            "Final severity derived from the 3×3 matrix below.\n"
            "│ Impact/Likelihood │  High  │  Medium │  Low  │\n"
            "├───────────────────┼────────┼─────────┼───────┤\n"
            "│ High likelihood   │  High  │  Medium │ Medium│\n"
            "│ Medium likelihood │  High  │  Medium │  Low  │\n"
            "│ Low likelihood    │ Medium │   Low   │  Low  │\n\n"
            "Derivation steps:\n"
            "1. Choose *impact* then *likelihood*.\n"
            "2. Read the intersection cell for the preliminary severity.\n"
            "3. If torn between two severities, **pick the lower one** (principle of conservatism).\n"
            "4. Use only these labels: High, Medium, Low, Info, Best Practices.\n"
            "   – ‘Info’ / ‘Best Practices’ are reserved for non-issues or stylistic notes."
        ),
    )

class Adjustment(BaseModel):
    index: int
    new_severity: _SEV | Literal["unchanged"]
    should_be_removed: bool
    comments: str | None = None

class FindingResponse(BaseModel):
    strategy: MitigationChecklist = Field(
        ...,
        description="Fill every checklist field first; this is the structured chain-of-thought."
    )
    reasoning_summary: str = Field(
        ...,
        description="≤ 3-sentence human-readable rationale that stitches strategy to adjustment."
    )
    adjustment: Adjustment = Field(
        ...,
        description="Final decision (index, final_severity, should_be_removed, comments)."
    )

class AuditResponse(BaseModel):
    document_id: str
    findings: List[FindingResponse]