"""
Phase-0  Context-Digestion  –  Schema v6-tight  
──────────────────────────────────────────────
*All instructional text sits inside the schema →  
the system-prompt only needs to say “return one JSON object that matches
ContextSummaryOutput”.*
"""

from __future__ import annotations
import uuid
from enum   import Enum
from typing import List, Optional
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
    notes: Optional[str] = Field(
        None,
        description="classify rôle: ‘divisor’, ‘upper-bound’, ‘ERC-20 address masquerade’, …"
    )

class StaticFinding(BaseModel):
    id: str = Field(default_factory=_uid)
    tool: str = Field(..., description="e.g. Slither")
    check_id: str = Field(..., description="Tool-specific rule identifier")
    description: str = Field(..., description="**Verbatim** message from the tool output")
    severity: SeverityEst
    code: CodeRef

    # helper to create a context quotation if Phase-1 needs it
    def to_ctx(self) -> ContextRef:
        return ContextRef(
            id=self.id,
            source=CtxSource.STATIC_ANALYSIS,
            context_type=CtxType.TOOL_NOTE,
            details=f"{self.tool}:{self.check_id} – {self.description}",
        )

# ════════════════════════════════════════════════════════════════
#  CONTRACT-LEVEL SUMMARY
# ════════════════════════════════════════════════════════════════
class ContractSummary(BaseModel):
    id: str = Field(default_factory=_uid)
    file_name: str                                     # from // File:

    core_purpose_raw: str                              # copy longest relevant paragraph
    core_purpose_digest: str = Field(..., description="≤120-char human summary")

    upgradeability_pattern: Optional[str] = Field(
        None, description="‘UUPS’, ‘Transparent’, ‘Beacon’, or None")
    consumed_interfaces: List[str] = Field(default_factory=list)
    compiler_version: Optional[str] = None

    identified_roles:   List[str] = Field(default_factory=list)
    key_state_vars:     List[str] = Field(default_factory=list)
    key_functions:      List[str] = Field(default_factory=list)
    external_dependencies: List[str] = Field(default_factory=list)
    security_notes:        List[str] = Field(default_factory=list)

    static_findings: List[StaticFinding] = Field(default_factory=list)
    config_params:  List[ConfigParam]  = Field(default_factory=list)
    flag_trackers:  List[FlagTracker]  = Field(default_factory=list)

    # ── light normalisation ──────────────────────────────
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