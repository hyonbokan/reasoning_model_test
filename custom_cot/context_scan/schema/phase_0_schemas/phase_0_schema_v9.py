from __future__ import annotations
import uuid
from enum   import Enum
from typing import List, Optional, Literal
from pydantic import BaseModel, Field, model_validator

# ════════════════════════════════════════════════════════════════
#  ENUMS  –  single source of truth for every literal the LLM may emit
# ════════════════════════════════════════════════════════════════

class CtxSource(str, Enum):
    SUMMARY          = "summary"
    DOCS             = "docs"
    INVARIANTS       = "invariants"
    WEB_CTX          = "web_context"
    STATIC_ANALYSIS  = "static_analysis"
    CODE_COMMENT     = "code_comment"
    LOGIC_INFERENCE  = "logic_inference"
    OTHER            = "other"

class CtxType(str, Enum):
    PROTOCOL   = "protocol_goal"       # “why does this protocol exist”
    ACTOR      = "actor_definition"    # user, admin, keeper …
    SECURITY   = "security_assumption" # any “we assume …” statement
    INVARIANT  = "invariant_rule"      # must always hold in prod
    BESTP      = "best_practice"       # Solidity / DeFi guidance
    TOOL_NOTE  = "tooling_note"        # Slither, compiler warnings …
    OTHER      = "other"

class SeverityEst(str, Enum):
    HIGH = "High"; MED = "Medium"; LOW = "Low"
    INFO = "Info"; BP  = "Best Practices"; UNK = "Unknown"

# ════════════════════════════════════════════════════════════════
#  HELPERS
# ════════════════════════════════════════════════════════════════
def _uid() -> str:               # 8-char primary key
    return uuid.uuid4().hex[:8]

class CodeRef(BaseModel):
    """
    Pin-points **one exact location** in the code base.
    The ID can be cross-referenced by other objects
    (downstream_uses, related_code, …).
    """
    id: str = Field(default_factory=_uid)
    file: str = Field(..., description="`ContractName.sol` exactly as in // File:")
    element_name: Optional[str] = Field(
        None, description="Function / modifier / variable (omit if obvious from snippet)")
    unique_snippet: Optional[str] = Field(
        None, description="≤150 chars, escape newlines with \\n; MUST uniquely identify the line(s)")

class ContextRef(BaseModel):
    """
    Any *quotable* fact, rule, or note extracted from the input.
    """
    id: str = Field(default_factory=_uid)
    source: CtxSource
    context_type: CtxType
    details: str = Field(..., description="Exact phrase / sentence copied from input (no paraphrase)")

class InvariantRef(BaseModel):
    """
    Rule that the business logic **must never break**.
    Examples: ‘one NFT per plot’, ‘munchablesStaked.length ≤ 10’.
    """
    id: str = Field(default_factory=_uid)
    description: str
    related_code: List[str] = Field(
        default_factory=list,
        description="List of CodeRef.id where the invariant is enforced or checked"
    )
    origin: Literal["doc", "check", "assumption"] = Field(
        "doc",
        description=(
            "Source of this invariant:\n"
            "- **doc**        : stated explicitly in documentation or markdown\n"
            "- **check**      : enforced in code via `require`/`assert` or similar\n"
            "- **assumption** : implied by design or contextual knowledge, not literally documented or checked"
        )
    )

class FlagTracker(BaseModel):
    """
    Used to catch bugs like S4/S5 (dirty flags not toggled).
    """
    name: str                                   # storage var, e.g. dirtyTimestamp
    expected_setters: List[str] = Field(
        default_factory=list,
        description="Functions that SHOULD write the flag (derived from docs / invariants)"
    )
    observed_setters: List[str] = Field(
        default_factory=list,
        description="Functions that ACTUALLY write the flag (grep result)"
    )
    note: Optional[str] = Field(
        None, description="Semantic hint (e.g. ‘blocks reward accrual when 0’)")
    
    # convenience ---------------------------------------------------
    def missing(self) -> List[str]:
        "return all expected setters that were NOT observed in code"
        return sorted(set(self.expected_setters) - set(self.observed_setters))

class ConfigParam(BaseModel):
    """
    Every value fetched from ConfigStorage / upgradeable mapping.
    Serves Phase-1 for mis-configuration & divisor-zero checks.
    """
    name: str
    storage_key: str = Field(..., description="Enum constant used in getUint/getAddress")
    load_site: CodeRef
    downstream_uses: List[str] = Field(
        default_factory=list,
        description="CodeRef.id where the param is used in math / require / access checks"
    )
    
    role: Literal[
        "divisor",            # risk = div-by-zero / precision
        "multiplier",         # risk = overflow
        "upper_bound",        # risk = insufficient clamp
        "lower_bound",
        "address_key",        # risk = type-mix-up
        "misc"
    ] = Field(
        "misc",
        description=(
            "Categorizes this parameter’s role in logic:"
            "- 'divisor'     : used as denominator, risk of division-by-zero or precision loss"
            "- 'multiplier'  : used as factor, risk of overflow"
            "- 'upper_bound' : defines an upper limit, risk of insufficient clamp"
            "- 'lower_bound' : defines a lower limit, risk of underflow or unmet minimum"
            "- 'address_key' : used for address lookup, risk of type mismatch or unauthorized access"
            "- 'misc'        : none of the above"
        )
    )
class ArithHint(BaseModel):
    """
    Numeric hints Phase-1 needs for precision / div-by-zero checks.
    """
    var: str                  # "taxRate"  OR "PRICE_PER_PLOT"
    role: Literal["divisor", "multiplier", "scale"] = "scale"
    scale_or_default: Optional[int] = None   # 1e18 etc.
    comment: Optional[str] = None

class SyncGuard(BaseModel):
    name: str                 # storage var *or* checker fn
    guard_type: Literal["total", "delay"]
    detail: str               # "must ++ on deposit", "≥ 1 day between calls"


# ════════════════════════════════════════════════════════════════
#  CONTRACT-LEVEL SUMMARY
# ════════════════════════════════════════════════════════════════
class ContractSummary(BaseModel):
    id: str = Field(default_factory=_uid)
    file_name: str                                     # from “// File: …”

    # ────── intent ───────────────────────────────────────────────
    core_purpose_raw: str                              # copy longest relevant paragraph
    core_purpose_digest: str = Field(..., description="≤120-char human summary")

    upgradeability_pattern: Optional[str] = Field(
        None, description="‘UUPS’, ‘Transparent’, ‘Beacon’, or None")
    consumed_interfaces: List[str] = Field(default_factory=list)
    compiler_version: Optional[str] = None

    # ────── quick-index lists ───────────────────────────────────
    identified_roles:        List[str] = Field(default_factory=list)
    key_state_vars:          List[str] = Field(default_factory=list)
    key_functions:           List[str] = Field(default_factory=list)
    external_dependencies:   List[str] = Field(default_factory=list)
    security_notes:          List[str] = Field(default_factory=list)

    # ────── structured pointers / hints for Phase-1 ─────────────
    config_params:   List[ConfigParam]  = Field(default_factory=list)
    flag_trackers:   List[FlagTracker]  = Field(default_factory=list)

    # ⬇️  **merged**: replaces math_scale_hints, aggregate_trackers, delay_guards
    arith_hints:  List[ArithHint]  = Field(default_factory=list)   # precision & div-by-zero
    sync_guards:  List[SyncGuard]  = Field(default_factory=list)   # totals & min-delay rules

    # ────── normalisation ───────────────────────────────────────
    @model_validator(mode="after")
    def _dedupe(cls, v):
        for fld in ("identified_roles", "key_state_vars",
                    "key_functions", "external_dependencies"):
            setattr(v, fld, sorted(set(getattr(v, fld))))
        return v
# ════════════════════════════════════════════════════════════════
#  PROJECT-LEVEL SUMMARY
# ════════════════════════════════════════════════════════════════
class ProjectContext(BaseModel):
    overall_goal_raw: str
    overall_goal_digest: str = Field(..., description="≤120 chars")

    actors_capabilities: List[str] = Field(default_factory=list)
    core_assets:         List[str] = Field(default_factory=list)
    critical_interactions: List[str] = Field(default_factory=list)

    key_assumptions: List[ContextRef] = Field(default_factory=list)
    invariants:      List[InvariantRef] = Field(default_factory=list)
    general_security_ctx: List[ContextRef] = Field(default_factory=list)
    static_summary: Optional[str] = Field(
        None,
        description="One-paragraph theme of static-analysis results"
    )

    @model_validator(mode="after")
    def _dedupe(cls, v):
        v.actors_capabilities = sorted(set(v.actors_capabilities))
        v.core_assets         = sorted(set(v.core_assets))
        return v

# ════════════════════════════════════════════════════════════════
#  ROOT OBJECT
# ════════════════════════════════════════════════════════════════
class ContextSummaryOutput(BaseModel):
    analyzed_contracts: List[ContractSummary]
    project_context:    ProjectContext