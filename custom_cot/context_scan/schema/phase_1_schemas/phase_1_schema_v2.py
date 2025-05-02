from __future__ import annotations
from typing import List, Literal, Optional, Dict, Any, Union
from pydantic import BaseModel, Field, model_validator, ValidationError

# --- Primitive Enums and Types ---
_YN = Literal["yes", "no", "n/a"]
_IMP = Literal["high", "medium", "low"]
_LIK = Literal["high", "medium", "low"]
_SEV = Literal["High", "Medium", "Low", "Info", "Best Practices"]
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
class CodeRefReasoning(BaseModel):
    """Reference using element names and unique snippets for reasoning steps."""
    file: str = Field(description="Filename (e.g., ContractName.sol) from '// File:'.")
    element_name: str = Field(description="Primary code element name (function, modifier, variable, etc.).")
    unique_snippet: str = Field(description="Short, uniquely identifying code snippet (1-3 lines, ~50-150 chars) within the element.")
    rationale: Optional[str] = Field(None, description="Optional brief explanation why this location is relevant.")

class ContextEvidenceRef(BaseModel):
    """Reference to a specific piece of context from the Phase 0 summary used as evidence."""
    context_source: _CONTEXT_SOURCE = Field(description="Where in the input document structure was this information found?")
    context_type: _CONTEXT_TYPE = Field(description="What is the semantic type of this piece of information?")
    details: str = Field(description="Specific quote, rule, observation, or referenced point.")

class CheckedAssessment(BaseModel):
    """Represents a checked answer (yes/no/n/a) with supporting evidence for reasoning steps."""
    answer: _YN = Field(description="The assessment answer ('yes', 'no', or 'n/a') for this reasoning step.")
    evidence_refs: List[Union[CodeRefReasoning, ContextEvidenceRef]] = Field(
        default_factory=list,
        description="List of code or context references justifying the answer. Provide at least one reference if possible.",
    )
    reasoning: Optional[str] = Field(None, description="Brief justification (1-2 sentences) if evidence refs aren't self-explanatory.")

# --- Enhanced Reasoning Stage (Replaces Old FactChecklistReasoning) ---

class VulnerabilityReasoning(BaseModel):
    """
    Internal Reasoning Step: Establish facts, analyze logic, and assess characteristics
    of the *specific vulnerability being reported*. Focus on detail and context.
    """
    primary_code_location: CodeRefReasoning = Field(..., description="Pinpoint the main code location (file, element, snippet) for *this specific finding*.")
    vulnerability_category_hypothesis: str = Field(..., description="Initial classification (e.g., 'State Update Error', 'Calculation Error', 'Access Control Bypass').")

    # --- Detailed Analysis Checks (Fill relevant sections) ---

    # State Management Analysis
    state_variable_involved: Optional[str] = Field(None, description="Name the primary state variable(s) whose integrity is compromised.")
    state_update_issue_type: Optional[Literal["omitted", "incorrect_value", "wrong_order", "condition_bypass", "other"]] = Field(None, description="Optional: If state update is flawed, classify the type of error.")
    state_update_analysis: Optional[CheckedAssessment] = Field(None, description="Optional: Detailed check: Is a required state update missing, incorrect, or performed at the wrong time relative to other operations (like external calls or checks)?")

    # Logic Flow Analysis
    control_flow_issue_type: Optional[Literal["conditional_error", "loop_error", "function_interaction", "edge_case_unhandled", "other"]] = Field(None, description="Optional: If logic flow is flawed, classify the type of error.")
    logic_flow_analysis: Optional[CheckedAssessment] = Field(None, description="Optional: Detailed check: Does the finding stem from flawed conditional logic (e.g., off-by-one, incorrect boundary), loop termination/iteration issues, unexpected function interactions, or unhandled edge cases?")

    # Calculation & Numerical Analysis
    calculation_issue_type: Optional[Literal["overflow", "underflow", "precision_loss", "division_by_zero", "signed_unsigned_conversion", "incorrect_formula", "other"]] = Field(None, description="Optional: If calculation is flawed, classify the type of error.")
    numerical_analysis: Optional[CheckedAssessment] = Field(None, description="Optional: Detailed check: Does the finding involve potential arithmetic errors (overflow/underflow - consider Solidity version & unchecked blocks), precision loss from division/scaling, division-by-zero risks, or incorrect formula implementation?")

    # Access Control Analysis
    access_control_issue_type: Optional[Literal["missing_modifier", "incorrect_modifier_logic", "public_function_exposure", "role_check_bypass", "other"]] = Field(None, description="Optional: If access control is flawed, classify the type of error.")
    access_control_analysis: Optional[CheckedAssessment] = Field(None, description="Optional: Detailed check: Is a required access control modifier/check missing, implemented incorrectly, or bypassable? Does it expose sensitive functionality?")

    # Re-entrancy Analysis
    reentrancy_analysis: Optional[CheckedAssessment] = Field(None, description="Optional: Detailed check: Does the finding involve an external call before critical state updates without adequate protection (guard, CEI pattern)?")

    # Invariant Violation Analysis
    invariant_violation_analysis: Optional[CheckedAssessment] = Field(None, description="Optional: Detailed check: Does this finding directly violate any explicit invariants provided in the context? Specify which one(s).")

    # Contextual Relevance
    contextual_factors: List[ContextEvidenceRef] = Field(default_factory=list, description="List key context points (from Phase 0 summary) that explain *why* this behavior is problematic in *this specific protocol*. E.g., how does it break game mechanics or economic assumptions?")

    # Static Analysis Correlation
    related_static_analysis: Optional[CheckedAssessment] = Field(None, description="Optional: Does this finding correlate with, validate, or refute any findings from the static analysis results provided in the context?")

# --- Severity Assessment Reasoning (Same as before) ---

class SeverityAssessmentReasoning(BaseModel):
    """Internal Reasoning Step: Assess severity based on Impact and Likelihood."""
    assessed_impact: _IMP = Field(..., description="Assess potential impact (High/Medium/Low).")
    impact_reasoning: str = Field(..., description="Justify the impact rating.")
    assessed_likelihood: _LIK = Field(..., description="Assess likelihood of exploit (High/Medium/Low).")
    likelihood_reasoning: str = Field(..., description="Justify the likelihood rating.")
    _SEVERITY_MATRIX: Dict[tuple[_IMP, _LIK], _SEV] = {
        ("high", "high"): "High", ("high", "medium"): "Medium", ("high", "low"): "Medium",
        ("medium", "high"): "High", ("medium", "medium"): "Medium", ("medium", "low"): "Low",
        ("low", "high"): "Medium", ("low", "medium"): "Low", ("low", "low"): "Low",
    }
    derived_severity: _SEV = Field(..., description="Final severity level derived *strictly* from the Impact/Likelihood matrix (pick lower if torn). Use 'Info'/'Best Practices' only if explicitly justified.")

    @model_validator(mode="after")
    def validate_severity_calculation(cls, v: 'SeverityAssessmentReasoning'):
        # (Validator logic remains the same - uses local table and .get())
        if not all(hasattr(v, attr) for attr in ['derived_severity', 'assessed_impact', 'assessed_likelihood']):
            raise ValueError("Missing required fields for severity validation.")
        if v.derived_severity in ["Info", "Best Practices"]: return v
        severity_lookup_table: Dict[tuple[_IMP, _LIK], _SEV] = {
            ("high", "high"): "High", ("high", "medium"): "Medium", ("high", "low"): "Medium",
            ("medium", "high"): "High", ("medium", "medium"): "Medium", ("medium", "low"): "Low",
            ("low", "high"): "Medium", ("low", "medium"): "Low", ("low", "low"): "Low",
        }
        impact = v.assessed_impact; likelihood = v.assessed_likelihood; matrix_key = (impact, likelihood)
        expected_severity = severity_lookup_table.get(matrix_key)
        if expected_severity is None: raise ValueError(f"Invalid impact/likelihood combination: {impact}/{likelihood}")
        if v.derived_severity != expected_severity:
            print(f"Warning/Correction: Derived severity '{v.derived_severity}' adjusted to matrix result '{expected_severity}'.")
            v.derived_severity = expected_severity
        return v

# --- Combined Structure for One Finding (FP Check Removed) ---

class ProcessedFinding(BaseModel):
    """
    Represents a single finding identified and processed through internal reasoning stages.
    False Positive checks are assumed to be handled in a separate phase.
    """
    finding_id: str = Field(..., description="Unique identifier for this finding (e.g., VULN-001).")
    # Enhanced reasoning section
    reasoning_analysis: VulnerabilityReasoning = Field(..., description="Detailed reasoning and fact-finding specific to this vulnerability.")
    # Severity assessment is now mandatory as FP check is removed
    reasoning_severity: SeverityAssessmentReasoning = Field(..., description="Severity assessment for this finding.")

    # --- Final Output Fields (Derived from Reasoning) ---
    Issue: str = Field(..., description="Final concise title for the report (approx 50-80 chars).")
    Severity: _SEV = Field(..., description="Final severity level for the report, derived from reasoning_severity.derived_severity.")
    Contracts: List[str] = Field(..., description="List of affected contract filenames ending in .sol, derived from reasoning_analysis.primary_code_location.file. Must contain at least one entry.")
    Description: str = Field(..., description="Final detailed description for the report, including JSON-escaped code snippets. Ensure sufficient detail (recommend min 50 chars).")
    Recommendation: Literal[""] = Field(description="Must always be an empty string.")

    @model_validator(mode="after")
    def validate_final_output_consistency(cls, v: 'ProcessedFinding'):
        # Ensure reasoning stages exist before accessing them
        if not hasattr(v, 'reasoning_analysis') or not hasattr(v, 'reasoning_severity'):
             raise ValueError(f"Missing reasoning_analysis or reasoning_severity for finding '{v.finding_id}'.")

        # Ensure final Severity matches derived severity from reasoning
        if not hasattr(v.reasoning_severity, 'derived_severity'):
             raise ValueError(f"Missing derived_severity in reasoning for finding '{v.finding_id}'.")
        if not hasattr(v, 'Severity'):
             raise ValueError(f"Missing final Severity field for finding '{v.finding_id}'.")
        if v.Severity != v.reasoning_severity.derived_severity:
            print(f"Warning/Correction: Final Severity for '{v.finding_id}' ('{v.Severity}') corrected to match reasoning ('{v.reasoning_severity.derived_severity}').")
            v.Severity = v.reasoning_severity.derived_severity

        # Ensure Contracts list is derived correctly
        if not hasattr(v.reasoning_analysis, 'primary_code_location') or not hasattr(v.reasoning_analysis.primary_code_location, 'file'):
            raise ValueError(f"Missing primary finding location data for finding '{v.finding_id}'.")
        expected_contract = v.reasoning_analysis.primary_code_location.file
        if not hasattr(v, 'Contracts') or not v.Contracts:
            print(f"Warning/Correction: Contracts list for '{v.finding_id}' initialized from primary file '{expected_contract}'.")
            v.Contracts = [expected_contract]
        elif v.Contracts[0] != expected_contract:
             print(f"Warning/Correction: Contracts list for '{v.finding_id}' corrected to match primary file '{expected_contract}'.")
             v.Contracts = [expected_contract]
        for contract_name in v.Contracts:
             if not isinstance(contract_name, str) or not contract_name.endswith('.sol'):
                  raise ValueError(f"Invalid contract name format in finding '{v.finding_id}': '{contract_name}'")

        # Ensure Recommendation is empty
        if not hasattr(v, 'Recommendation') or v.Recommendation != "":
             v.Recommendation = "" # Force empty

        # Basic checks on Description
        if not hasattr(v, 'Description') or len(v.Description.strip()) < 50:
             raise ValueError(f"Final Description for finding '{v.finding_id}' seems too short or is missing.")
        # if '```solidity' not in v.Description: print(f"Warning: Final Description for finding '{v.finding_id}' might be missing snippet.")

        return v


# --- Top-Level Schema for Phase 1 Output ---

class VulnerabilityAnalysisOutput(BaseModel):
    """Schema for the output of the combined Phase 1 (Detection + Enhanced Reasoning + Formatting)."""
    findings: List[ProcessedFinding] = Field(..., description="List of processed vulnerability findings.")
    analysis_summary_notes: Optional[str] = Field(None, description="High-level notes from the analysis model about the overall process.")