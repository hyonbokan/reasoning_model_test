from __future__ import annotations

import uuid
from enum   import Enum
from typing import List, Optional, Dict, Tuple
from pydantic import BaseModel, Field, model_validator

# ─────────────────── trimmed enums ──────────────────────────
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
    PROTOCOL   = "protocol_goal"
    ACTOR      = "actor_definition"
    SECURITY   = "security_assumption"
    INVARIANT  = "invariant_rule"
    BESTP      = "best_practice"          # incl. common_vulnerability
    TOOL_NOTE  = "tooling_note"           # compiler warnings, slither, etc.
    OTHER      = "other"

class SeverityEst(str, Enum):
    HIGH = "High"
    MED  = "Medium"
    LOW  = "Low"
    INFO = "Info"
    BP   = "Best Practices"
    UNK  = "Unknown"
    
# ─────────────────── helper objects ─────────────────────────
def _uid() -> str:
    """8-char id for contracts / context refs."""
    return uuid.uuid4().hex[:8]

class CodeRef(BaseModel):
    id: str = Field(default_factory=_uid, description="Internal reference id.")
    file: str = Field(..., description="Contract filename from `// File:` header.")
    element_name: Optional[str] = Field(
        None, description="Function / modifier / variable name (optional).")
    unique_snippet: Optional[str] = Field(
        None, description="1-3 lines (~≤150 chars) that uniquely identify the spot.")
    
class ContextRef(BaseModel):
    id: str = Field(default_factory=_uid)
    source: CtxSource
    context_type: CtxType
    details: str = Field(..., description="quote / note / rule.")

class InvariantRef(BaseModel):
    """Any rule that *must* always hold (economics, access, liveness…)."""
    id: str = Field(default_factory=_uid)
    description: str = Field(..., description="Huamn-readable rule")
    related_code: Optional[str] = None          # CodeRef.id of check site
    
class FlagTracker(BaseModel):
    """
    Tracks state-machine flags whose correct update is critical
    (dirtyTimestamp, paused, nonce, etc.).
    """
    name: str                                   # storage var name
    expected_setters: List[str] = Field(
        default_factory=list,                   # list of function names
        description="Functions that *should* update the flag."
    )
    observed_setters: List[str] = Field(
        default_factory=list,                   # filled by LLM via grep
        description="Functions that actually write the flag."
    )
    note: Optional[str] = None                  # e.g. 'gates reward accrual'

class ConfigParam(BaseModel):
    name: str = Field(
        ...,
        description="Exact constant / state var name.",
    )
    storage_key: str = Field(
        ...,
        description="Enum label used with ConfigStorage.",
    )
    load_site: 'CodeRef' = Field(
        ...,
        description="Where the value is first fetched.",
    )
    downstream_uses: List[str] = Field(
        default_factory=list,
        description=(
            "List **of CodeRef.id** for every place this value is used in: "
            " • arithmetic (divisor/multiplier)\n"
            " • access control checks (>=, <=, ==)\n"
            " • require()/revert messages\n"
        ),
    )
    notes: Optional[str] = Field(
        None,
        description="Hint for the auditor (e.g., 'divisor', 'upper-bound', 'address masquerading as uint').",
    )
    
class StaticFinding(BaseModel):
    id: str = Field(default_factory=_uid)
    tool: str = Field(..., description="Static-analysis tool (e.g., Slither)")
    # tool: str
    check_id: str
    description: str = Field(
        ...,
        description="Verbatim tool message",
    )
    severity: SeverityEst
    code: CodeRef

    # auto-map to ContextRef-compatible record --------------
    def to_ctx(self) -> ContextRef:
        return ContextRef(
            id=self.id,
            source=CtxSource.STATIC_ANALYSIS,
            context_type=CtxType.TOOL_NOTE,
            details=f"{self.tool}:{self.check_id} – {self.description}",
        )

# ───────────────── contract-level summary ───────────────────
class ContractSummary(BaseModel):
    id: str = Field(default_factory=_uid)
    file_name: str

    core_purpose_raw: str
    core_purpose_digest: str = Field(..., description="≤120 chars")

    identified_roles: List[str] = Field(default_factory=list)
    key_state_vars:   List[str] = Field(default_factory=list)
    key_functions:    List[str] = Field(default_factory=list)
    external_dependencies: List[str] = Field(default_factory=list)
    security_notes:        List[str] = Field(default_factory=list)

    static_findings: List[StaticFinding] = Field(default_factory=list)
    config_params: List[ConfigParam] = Field(default_factory=list)
    flag_trackers:   List[FlagTracker]  = Field(default_factory=list)

    # ---- dedupe / lowercase simple lists -----------------
    @model_validator(mode="after")
    def _dedupe(cls, v):
        for fld in ("identified_roles", "key_state_vars",
                    "key_functions", "external_dependencies"):
            setattr(v, fld, sorted(set(getattr(v, fld))))
        return v

# ───────────────── project-level summary ────────────────────
class ProjectContext(BaseModel):
    overall_goal_raw: str
    overall_goal_digest: str = Field(..., description="≤120 chars")

    actors_capabilities: List[str] = Field(default_factory=list)
    core_assets:         List[str] = Field(default_factory=list)
    critical_interactions: List[str] = Field(default_factory=list)

    key_assumptions: List[ContextRef] = Field(default_factory=list)
    invariants:      List[InvariantRef] = Field(default_factory=list) 
    general_security_ctx: List[ContextRef] = Field(default_factory=list)
    static_summary: Optional[str] = None

    @model_validator(mode="after")
    def _dedupe(cls, v):
        v.actors_capabilities = sorted(set(v.actors_capabilities))
        v.core_assets         = sorted(set(v.core_assets))
        return v

# ────────────────── top-level Phase-0 output ─────────────────
class ContextSummaryOutput(BaseModel):
    analyzed_contracts: List[ContractSummary]
    project_context: ProjectContext