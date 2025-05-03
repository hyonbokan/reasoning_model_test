"""
Phase-0  Context Digestion  – v2
────────────────────────────────
• One compact, self-validated schema that turns *all* background material
  (docs, invariants, static-analysis output, etc.) into a machine-readable
  summary for Phase-1 vulnerability detection.

Design tweaks
────────────────────
1.  Trimmed enums  →  easier for the LLM to pick the right label  
2.  Auto-generated 8-char IDs  →  Phase-1 can reference items concisely  
3.  De-duplicated / lower-cased list fields  
4.  `*_raw` + `*_digest` pairs for long passages  
5.  Lightweight root-validators to catch broken links early
"""

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
        None, description="Function / modifier / var name (optional).")
    unique_snippet: Optional[str] = Field(
        None, description="1-3 lines (~≤150 chars) that uniquely identify the spot.")
    lines: Optional[List[int]] = Field(
        None, description="1-based line numbers if available.")

class ContextRef(BaseModel):
    id: str = Field(default_factory=_uid)
    source: CtxSource
    context_type: CtxType
    details: str = Field(..., description="Exact quote / note / rule.")
    related_code: Optional[str] = Field(
        None, description="`CodeRef.id` if this context item maps to code.")

class StaticFinding(BaseModel):
    id: str = Field(default_factory=_uid)
    tool: str = Field(..., description="e.g. Slither")
    check_id: str
    description: str
    severity: SeverityEst
    code: CodeRef

    # auto-map to ContextRef-compatible record --------------
    def to_ctx(self) -> ContextRef:
        return ContextRef(
            id=self.id,
            source=CtxSource.STATIC_ANALYSIS,
            context_type=CtxType.TOOL_NOTE,
            details=f"{self.tool}:{self.check_id} – {self.description}",
            related_code=self.code.id,
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

    # ---- dedupe / lowercase simple lists -----------------
    @model_validator(mode="after")
    def _normalise_lists(cls, v: 'ContractSummary'):
        for attr in ("identified_roles", "key_state_vars",
                     "key_functions", "external_dependencies"):
            lst = getattr(v, attr, [])
            setattr(v, attr, sorted(set(i.lower() for i in lst)))
        return v

# ───────────────── project-level summary ────────────────────
class ProjectContext(BaseModel):
    overall_goal_raw: str
    overall_goal_digest: str = Field(..., description="≤120 chars")

    actors_capabilities: List[str] = Field(default_factory=list)
    core_assets:         List[str] = Field(default_factory=list)
    critical_interactions: List[str] = Field(default_factory=list)

    key_assumptions: List[ContextRef] = Field(default_factory=list)
    general_security_ctx: List[ContextRef] = Field(default_factory=list)

    static_summary: Optional[str] = None

    @model_validator(mode="after")
    def _normalise(cls, v: 'ProjectContext'):
        v.actors_capabilities = sorted(set(a.lower() for a in v.actors_capabilities))
        v.core_assets         = sorted(set(a.lower() for a in v.core_assets))
        return v

# ────────────────── top-level Phase-0 output ─────────────────
class ContextSummaryOutput(BaseModel):
    analyzed_contracts: List[ContractSummary]
    project_context: ProjectContext

    # -------- cross-checks ----------------------------------
    @model_validator(mode="after")
    def _link_checks(cls, v: 'ContextSummaryOutput'):
        contract_ids = {c.id for c in v.analyzed_contracts}
        # every ContextRef.related_code must exist
        for ctx_list in (v.project_context.key_assumptions,
                         v.project_context.general_security_ctx):
            for ctx in ctx_list:
                if ctx.related_code and ctx.related_code not in contract_ids:
                    raise ValueError(
                        f"ContextRef {ctx.id} links to unknown CodeRef id {ctx.related_code}"
                    )
        return v