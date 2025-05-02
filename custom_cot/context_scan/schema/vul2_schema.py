from __future__ import annotations
from typing import List, Literal, Optional, Union, Dict
from pydantic import BaseModel, Field, model_validator

# ────────────── Primitive Enums ──────────────
_IMP = Literal["high", "medium", "low"]
_LIK = Literal["high", "medium", "low"]
_SEVERITY = Literal["high", "medium", "low"]

VulnClass = Literal[
    "state_update_error",
    "state_initialization_fault",
    "math_precision_or_overflow",
    "logic_edge_case",
    "access_control_missing_or_bypass",
    "reentrancy",
    "invariant_violation",
    "stale_oracle_or_state",
    "dos_gas_loop",
    "other",
]

_CONTEXT_SOURCE = Literal[
    "summary", "docs", "invariants", "web_context",
    "static_analysis", "code_comment", "logic_inference",
    "other", "none",
]
_CONTEXT_TYPE = Literal[
    "protocol_goal", "actor_definition", "asset_description",
    "function_purpose", "interaction_flow", "security_assumption",
    "invariant_rule", "best_practice", "common_vulnerability",
    "compiler_warning", "eip_standard", "access_control_rule",
    "state_variable_meaning", "configuration_setting",
    "external_dependency_info", "static_analysis_finding",
    "other_detail",
]

# ────────────── Helper Models ──────────────
class CodeRef(BaseModel):
    file: str = Field(..., description="Filename from the `// File:` header.")
    element_name: str = Field(..., description="Function / modifier / variable that contains the bug.")
    unique_snippet: str = Field(
        ...,
        description="Uniquely identifying the vulnerable spot."
    )
    rationale: str = Field(..., description="Why this snippet pinpoints the issue.")

class ContextEvidenceRef(BaseModel):
    context_source: _CONTEXT_SOURCE
    context_type:  _CONTEXT_TYPE
    details:       str

# ────────────── Polymorphic “specifics” blocks ──────────────
class _BaseSpecifics(BaseModel):
    issue_type: str = Field(..., description="Discriminator – one literal value below.")

class StateUpdateIssue(_BaseSpecifics):
    issue_type: Literal["state_update_error"]
    missing_or_incorrect: str
    consequences: str

class StateInitIssue(_BaseSpecifics):
    issue_type: Literal["state_initialization_fault"]
    uninitialised_var: str
    read_context: str

class MathIssue(_BaseSpecifics):
    issue_type: Literal["math_precision_or_overflow"]
    operation: str
    risk: str

class AccessControlIssue(_BaseSpecifics):
    issue_type: Literal["access_control_missing_or_bypass"]
    actor: str
    privilege_gained: str

class ReentrancyIssue(_BaseSpecifics):
    issue_type: Literal["reentrancy"]
    external_call: str
    state_updated_after: bool

class LogicEdgeIssue(_BaseSpecifics):
    issue_type: Literal["logic_edge_case"]
    edge_condition: str
    faulty_branch: str

class InvariantIssue(_BaseSpecifics):
    issue_type: Literal["invariant_violation"]
    invariant_text: str
    breach_explanation: str

class StaleStateIssue(_BaseSpecifics):
    issue_type: Literal["stale_oracle_or_state"]
    stale_field: str
    impact_window: str

class DoSLoopIssue(_BaseSpecifics):
    issue_type: Literal["dos_gas_loop"]
    loop_description: str
    unbounded_factor: str

class OtherIssue(_BaseSpecifics):
    issue_type: Literal["other"]
    summary: str

IssueSpecifics = Union[
    StateUpdateIssue, StateInitIssue, MathIssue, AccessControlIssue,
    ReentrancyIssue, LogicEdgeIssue, InvariantIssue, StaleStateIssue,
    DoSLoopIssue, OtherIssue,
]

# ────────────── Main finding model ──────────────
class VulnerabilityReasoningFacts(BaseModel):
    finding_id: str = Field(..., description="Unique id like VULN-001.")
    contract_file: str = Field(..., description="File where the bug manifests.")
    vulnerability_class: VulnClass

    primary_code_location: CodeRef
    related_code_locations: List[CodeRef] = Field(
        default_factory=list, description="Other relevant spots (may be empty)."
    )

    specifics: IssueSpecifics

    detailed_description: str
    exploit_scenario: str
    impact: _IMP
    likelihood: _LIK
    severity: Optional[_SEVERITY] = Field(
        None,
        description="Auto-derived. Omit in input."
    )

    supporting_evidence: List[Union[CodeRef, ContextEvidenceRef]] = Field(
        default_factory=list, description="Additional proof (may be empty)."
    )
    violated_invariants: List[str] = Field(
        default_factory=list, description="Invariant texts violated (may be empty)."
    )
    related_static_analysis_finding_ids: List[str] = Field(
        default_factory=list, description="Static analysis IDs (may be empty)."
    )

    # ───── Matrix-based severity derivation / validation ─────
    @model_validator(mode="after")
    def derive_or_validate_severity(cls, v: "VulnerabilityReasoningFacts"):
        matrix: Dict[tuple[str, str], str] = {
            ("high",   "high"):   "high",
            ("high",   "medium"): "high",
            ("high",   "low"):    "medium",
            ("medium", "high"):   "high",
            ("medium", "medium"): "medium",
            ("medium", "low"):    "low",
            ("low",    "high"):   "medium",
            ("low",    "medium"): "low",
            ("low",    "low"):    "low",
        }
        computed = matrix[(v.impact, v.likelihood)]
        if v.severity is None:
            object.__setattr__(v, "severity", computed)
        elif v.severity != computed:
            raise ValueError("Severity does not match impact/likelihood matrix.")
        return v

# ────────────── Output container ──────────────
class VulnerabilityDetectionOutput(BaseModel):
    detected_findings: List[VulnerabilityReasoningFacts] = Field(
        default_factory=list, description="List of findings (must have ≥1)."
    )
    detection_summary_notes: Optional[str] = Field(
        None, description="Optional meta-notes."
    )

    @model_validator(mode="after")
    def require_findings(cls, v):
        if not v.detected_findings:
            raise ValueError("No findings reported.")
        return v