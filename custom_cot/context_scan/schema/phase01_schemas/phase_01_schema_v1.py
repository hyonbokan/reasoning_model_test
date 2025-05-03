from __future__ import annotations
import uuid
from enum import Enum
from typing import List, Literal, Optional
from pydantic import BaseModel, Field, model_validator


# ── helpers & enums ─────────────────────────────────────────────────────────
def _uid() -> str:                       # 8-char primary key
    return uuid.uuid4().hex[:8]

class Severity(str, Enum):               # reused by Phase-1
    HIGH = "High"; MED = "Medium"; LOW = "Low"
    INFO = "Info"; BP = "Best Practices"

class CtxSource(str, Enum):
    SUMMARY = "summary"; DOCS = "docs"; INVARIANTS = "invariants"
    WEB_CTX = "web_context"; STATIC = "static_analysis"
    COMMENT = "code_comment"; INFER = "logic_inference"; OTHER = "other"

class CtxType(str, Enum):
    PROTOCOL = "protocol_goal"; ACTOR = "actor_definition"
    SECURITY = "security_assumption"; INVARIANT = "invariant_rule"
    BESTP = "best_practice"; TOOL = "tooling_note"; OTHER = "other"

class StaticSeverity(str, Enum):
    HIGH = "High"; MED = "Medium"; LOW = "Low"
    INFO = "Info"; BP = "Best Practices"; UNK = "Unknown"


# ── low-level reference objects ─────────────────────────────────────────────
class CodeRef(BaseModel):
    id: str = Field(default_factory=_uid)
    file: str = Field(..., description="Contract filename from // File:")
    element_name: Optional[str] = Field(None, description="Func / var / modifier")
    unique_snippet: Optional[str] = Field(None, description="1-3 lines (~≤150 chars)")
    lines: Optional[List[int]] = Field(None, description="1-based line numbers")

class ContextRef(BaseModel):
    id: str = Field(default_factory=_uid)
    source: CtxSource
    context_type: CtxType
    details: str
    related_code: Optional[str] = Field(None, description="CodeRef.id if linked")


# ── static-analysis record (Slither / MythX / etc.) ─────────────────────────
class StaticFinding(BaseModel):
    id: str = Field(default_factory=_uid)
    tool: str
    check_id: str
    description: str
    severity: StaticSeverity
    code: CodeRef

    def to_ctx(self) -> ContextRef:
        return ContextRef(
            id=self.id,
            source=CtxSource.STATIC,
            context_type=CtxType.TOOL,
            details=f"{self.tool}:{self.check_id} – {self.description}",
            related_code=self.code.id,
        )


# ── contract-level digest ───────────────────────────────────────────────────
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

    @model_validator(mode="after")
    def _dedupe_lists(cls, v:'ContractSummary'):
        for attr in ("identified_roles", "key_state_vars",
                     "key_functions", "external_dependencies"):
            lst = getattr(v, attr, [])
            setattr(v, attr, sorted(set(i.lower() for i in lst)))
        return v


# ── project-level digest ────────────────────────────────────────────────────
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
    def _dedupe(cls, v:'ProjectContext'):
        v.actors_capabilities = sorted(set(a.lower() for a in v.actors_capabilities))
        v.core_assets         = sorted(set(a.lower() for a in v.core_assets))
        return v


# ── NEW: rich SeedFinding mirroring Phase-1 structure ───────────────────────
class SeedFinding(BaseModel):
    """
    Phase-0 vulnerability candidate – already shaped like Phase-1 `FindingOutput`
    so the next stage can promote it with minimal rewriting.
    """
    id: str = Field(default_factory=_uid, description="Internal FK for Phase-1")

    Issue: str  = Field(...,
        description="Short title of the vulnerability"
        )
    Severity: Severity
    Contracts: List[str] = Field(...,
        description="Affected *.sol files – must match ContractSummary.file_name")
    # Affected: Optional[List[CodeRef]] = Field(
    #     None, description="Precise code locations (optional but recommended)")
    Description: str = Field(...,
        description="Concise WHAT/HOW/WHY (≥50 chars) – JSON-escaped snippet required")
    Recommendation: Literal[""] = Field(
        ..., description="Always empty (kept for downstream compatibility)")

    # quick consistency
    @model_validator(mode="after")
    def _basic_checks(cls, v:'SeedFinding'):
        for c in v.Contracts:
            if not c.endswith(".sol"):
                raise ValueError(f"Contract name '{c}' missing .sol suffix")
        # if v.Affected:
        #     bad = [ref.file for ref in v.Affected if ref.file not in v.Contracts]
        #     if bad:
        #         raise ValueError(f"Affected.file not in Contracts list: {bad}")
        if "```" not in v.Description:
            print(f"⚠︎  Description of seed '{v.Issue}' has no code block.")
        return v


# ── top-level Phase-0 output ────────────────────────────────────────────────
class ContextSummaryOutput(BaseModel):
    analyzed_contracts: List[ContractSummary]
    project_context:    ProjectContext
    seed_findings:      List[SeedFinding] = Field(
        default_factory=list,
        description="List of all validated and formatted vulnerability findings"
    )

    @model_validator(mode="after")
    def _cross_checks(cls, v:'ContextSummaryOutput'):
        contract_files = {c.file_name for c in v.analyzed_contracts}

        # every ContextRef.related_code must link to a known CodeRef
        all_code_ids = {ref.code.id
                        for c in v.analyzed_contracts
                        for ref in c.static_findings}
        for ctx_list in (v.project_context.key_assumptions,
                         v.project_context.general_security_ctx):
            for ctx in ctx_list:
                if ctx.related_code and ctx.related_code not in all_code_ids:
                    raise ValueError(f"ContextRef {ctx.id} links to unknown CodeRef {ctx.related_code}")

        # every SeedFinding must reference existing contract file
        for sf in v.seed_findings:
            for f in sf.Contracts:
                if f not in contract_files:
                    raise ValueError(f"SeedFinding {sf.id} points to unknown file '{f}'")
        return v
