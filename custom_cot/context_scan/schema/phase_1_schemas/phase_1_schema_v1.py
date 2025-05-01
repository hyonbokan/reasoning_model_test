from __future__ import annotations
from typing import List, Literal, Optional, Dict, Any, Union
from pydantic import BaseModel, Field, model_validator

# --- Primitive Enums and Types ---
_IMP = Literal["high", "medium", "low"]
_LIK = Literal["high", "medium", "low"]
_CONTEXT_SOURCE = Literal[
    "summary", "docs", "invariants", "web_context",
    "static_analysis", "code_comment", "logic_inference", "other", "none",
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

# --- Helper Models ---

# CodeRef for Phase 1 OUTPUT - Uses element name and unique snippet
class CodeRefPhase1(BaseModel):
    """
    Reference to a specific code location identified during Phase 1 analysis.
    Uses element names and unique snippets instead of line numbers.
    """
    file: str = Field(..., description="Filename (e.g., ContractName.sol) from '// File:'.")
    element_name: str = Field(..., description="Primary code element name (function, modifier, variable, etc.) containing the vulnerability.")
    unique_snippet: str = Field(
        ...,
        description=(
            "A short, **uniquely identifying snippet** of code (approx. 1-3 lines, ~50-150 chars) "
            "from *within* the specified 'element_name' that pinpoints the exact location "
            "of the vulnerability. This snippet MUST be unique enough "
            "to distinguish this location from others within the same element or file."
        )
    )
    rationale: str = Field(..., description="Explanation of why this specific code location is relevant to the finding.")

# Reference back to context provided by Phase 0
class ContextEvidenceRef(BaseModel):
    """Reference to a specific piece of context from the Phase 0 summary used as evidence."""
    context_source: _CONTEXT_SOURCE = Field(..., description="The source field from the original ContextRef in Phase 0 input.")
    context_type: _CONTEXT_TYPE = Field(..., description="The context_type field from the original ContextRef in Phase 0 input.")
    details: str = Field(..., description="The specific details/quote from the original ContextRef that supports this finding.")

# --- Core Schema for a Detected Finding ---

class DetectedFinding(BaseModel):
    """Structure representing a single vulnerability identified in Phase 1."""
    finding_id: str = Field(..., description="Unique identifier for this detected finding (e.g., VULN-001).")
    contract_file: str = Field(..., description="The primary contract file where the vulnerability manifests.")

    vulnerability_class: str = Field(
        ...,
        description=(
            "Specific classification of the vulnerability. Aim for granularity reflecting common categories "
            "(e.g., 'State-Integrity / Invariant Violation', 'Accounting / Checkpoint Drift', 'Math & Preconditions - Precision Loss', "
            "'Logic Error - Incorrect State Update', 'Access Control - Missing Check', 'Re-Entrancy')."
        )
    )

    # Location(s) of the vulnerability in the code (using modified CodeRef)
    primary_code_ref: CodeRefPhase1 = Field(..., description="The main code location where the vulnerability occurs.")
    related_code_refs: List[CodeRefPhase1] = Field(
        default_factory=list,
        description="Other relevant code locations involved in the vulnerability (e.g., function called, related state variable declaration)."
    )

    # Detailed explanation
    detailed_description: str = Field(
        ...,
        description=(
            "**Mandatory:** In-depth explanation of the vulnerability. Describe:\n"
            "1. WHAT is the flaw (e.g., state variable not updated, calculation error, missing check)?\n"
            "2. HOW does it occur (trace the logic flow, conditions, inputs)?\n"
            "3. WHY is it a problem (immediate consequence, e.g., state inconsistency, incorrect value, bypass)?\n"
            "Reference specific functions, variables, and logic paths."
        )
    )

    # Evidence linking back to code and context
    supporting_evidence: List[Union[CodeRefPhase1, ContextEvidenceRef]] = Field(
        default_factory=list,
        description="List of specific code references (beyond primary/related) and/or context references (from Phase 0 input) that directly support the existence and explanation of this vulnerability."
    )
    violated_invariants: List[str] = Field(
        default_factory=list,
        description="List the 'details' or descriptions of specific invariants (provided in the Phase 0 context) that are violated by this finding."
    )

    # Exploitability and initial assessment (NOW MANDATORY)
    exploit_scenario: str = Field(
        ..., # Changed from Optional
        description="**Mandatory:** A brief, plausible scenario describing how an attacker could trigger or benefit from this vulnerability. If no direct exploit seems possible, explain why (e.g., 'Requires admin privilege not typically available')."
    )
    initial_impact_estimate: _IMP = Field(
        ..., # Changed from Optional
        description="**Mandatory:** Initial assessment of the potential impact (high, medium, low) based on the analysis in this phase, considering the protocol's assets and goals."
    )
    initial_likelihood_estimate: _LIK = Field(
        ..., # Changed from Optional
        description="**Mandatory:** Initial assessment of the likelihood of exploitation (high, medium, low) based on the analysis in this phase, considering complexity and preconditions."
    )

    # Link back to static analysis if this finding confirms/relates to one
    related_static_analysis_finding_ids: List[str] = Field(
        default_factory=list,
        description="If this finding validates, refutes, or relates to a finding from the static analysis results (provided in Phase 0 context), list the relevant static analysis check_id(s) here."
    )

# --- Top-Level Schema for Phase 1 Output ---

class VulnerabilityDetectionOutput(BaseModel):
    """Schema for the output of Phase 1: Vulnerability Detection."""
    detected_findings: List[DetectedFinding] = Field(
        default_factory=list,
        description="A list of specific vulnerabilities identified during the detailed analysis."
    )

    # Overall summary of the detection phase
    detection_summary_notes: Optional[str] = Field(
        None,
        description="Any high-level notes from the detection model, e.g., areas that were complex, assumptions made, confidence levels."
    )

    @model_validator(mode="after")
    def check_finding_details(cls, v):
        """Basic checks for finding consistency, including mandatory fields."""
        for finding in v.detected_findings:
            if not finding.detailed_description:
                raise ValueError(f"Finding '{finding.finding_id}' must have a detailed_description.")
            if not finding.primary_code_ref:
                raise ValueError(f"Finding '{finding.finding_id}' must have a primary_code_ref.")
            # Check mandatory fields that were previously optional
            if not finding.exploit_scenario:
                raise ValueError(f"Finding '{finding.finding_id}' must have an exploit_scenario.")
            if not finding.initial_impact_estimate:
                raise ValueError(f"Finding '{finding.finding_id}' must have an initial_impact_estimate.")
            if not finding.initial_likelihood_estimate:
                raise ValueError(f"Finding '{finding.finding_id}' must have an initial_likelihood_estimate.")
            # Check CodeRef fields (no lines check needed now)
            if not finding.primary_code_ref.file or not finding.primary_code_ref.element_name or not finding.primary_code_ref.unique_snippet:
                 raise ValueError(f"Primary CodeRef in finding '{finding.finding_id}' is missing required fields (file, element_name, unique_snippet).")
            for ref in finding.related_code_refs:
                 if not ref.file or not ref.element_name or not ref.unique_snippet:
                      raise ValueError(f"Related CodeRef in finding '{finding.finding_id}' is missing required fields.")

        return v