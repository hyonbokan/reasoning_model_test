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
    rationale: Optional[str] = Field(None, description="Optional: Brief explanation why this location is relevant.")

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

# ═══════════════════════════════════════════════════════════════════════════
# Enhanced Reasoning Stage 1: Vulnerability Characterization & Fact Finding
# ═══════════════════════════════════════════════════════════════════════════
class VulnerabilityReasoningFacts(BaseModel):
    """
    Reasoning Step 1: Establish facts and analyze characteristics of the potential vulnerability.
    Fill *only* the checks relevant to the specific finding being analyzed.
    """
    primary_code_location: CodeRefReasoning = Field(..., description="Pinpoint the main code location (file, element, snippet) for *this specific potential finding*.")
    hypothesized_vulnerability_class: str = Field(..., description="Initial classification (e.g., 'State Update Error', 'Logic Error - Edge Case', 'Calculation Error - Overflow'). Be specific.")

    # --- Deeper Analysis Checks ---

    # State Management Focus
    state_update_analysis: Optional[CheckedAssessment] = Field(None, description="Check State Updates: Is a required state variable update missing (e.g., forgetting to update plotId, dirty flag)? Is an update incorrect (wrong value assigned)? Is the update order problematic (e.g., before checks, after external calls)?")
    state_initialization_analysis: Optional[CheckedAssessment] = Field(None, description="Check Initialization: Is state read or used (e.g., plotMetadata, tax rates) before it's guaranteed to be initialized by required functions (like triggerPlotMetadata)?")
    state_reset_analysis: Optional[CheckedAssessment] = Field(None, description="Check State Reset: When an entity is removed or action completed (e.g., unstake, transfer), are ALL associated state variables correctly cleared or reset to default values?")
    stale_state_analysis: Optional[CheckedAssessment] = Field(None, description="Check Stale State: Does the logic rely on a timestamp or value (e.g., lastUpdated, plot count derived from PRICE_PER_PLOT) that might be outdated relative to other actions or the current block time, leading to incorrect calculations or logic paths?")

    # Logic Flow Focus
    conditional_logic_analysis: Optional[CheckedAssessment] = Field(None, description="Check Conditionals: Examine `if`/`require` statements. Are boundary conditions (e.g., index 0, count == limit, value == 0) handled correctly? Are comparisons (< vs <=) accurate?")
    loop_logic_analysis: Optional[CheckedAssessment] = Field(None, description="Check Loops: Examine `for`/`while` loops. Are loop bounds safe? Can they lead to excessive gas usage (DoS)? Is iteration logic correct?")
    edge_case_analysis: Optional[CheckedAssessment] = Field(None, description="Check Edge Cases: Consider non-standard scenarios mentioned or implied in context (e.g., plot count decreasing via config change, zero locked value, specific timing attacks). Does the code handle these correctly?")
    function_interaction_analysis: Optional[CheckedAssessment] = Field(None, description="Check Interactions: How does this function interact with others (e.g., modifiers like forceFarmPlots)? Could interactions lead to unexpected states or bypass checks?")

    # Calculation Focus
    numerical_calculation_analysis: Optional[CheckedAssessment] = Field(None, description="Check Calculations: Analyze arithmetic operations. Is there risk of overflow/underflow (consider Solc >=0.8 and `unchecked`)? Is there precision loss from division/scaling? Is division by zero possible? Are signed/unsigned conversions safe?")
    intermediate_value_analysis: Optional[CheckedAssessment] = Field(None, description="Check Intermediate Values: In complex calculations, could an intermediate result become negative before a uint cast, or unexpectedly large/small, affecting subsequent steps?")

    # Access Control Focus
    access_control_analysis: Optional[CheckedAssessment] = Field(None, description="Check Access Control: Is the necessary authorization (modifier, require) present and correctly implemented? Could it be bypassed? Does it rely on potentially stale approvals?")

    # Re-entrancy Focus
    reentrancy_analysis: Optional[CheckedAssessment] = Field(None, description="Check Re-entrancy: Is there an external call before state updates without adequate protection (guard, CEI pattern)?")

    # Invariant Focus
    invariant_violation_analysis: Optional[CheckedAssessment] = Field(None, description="Check Invariants: Does this finding directly violate any explicit invariants provided? Does it violate implicit protocol rules derived from the summary/docs?")

    # Contextual Relevance
    contextual_relevance_factors: List[ContextEvidenceRef] = Field(default_factory=list, description="List key context points explaining *why* this behavior is problematic in *this specific protocol* (e.g., breaks game mechanic, economic exploit).")

    # Static Analysis Correlation
    related_static_analysis: Optional[CheckedAssessment] = Field(None, description="Optional Check: Does this potential finding correlate with any static analysis results provided?")

# ═══════════════════════════════════════════════════════════════════════════
# Stage 2: Severity Assessment
# ═══════════════════════════════════════════════════════════════════════════
class SeverityAssessmentReasoning(BaseModel):
    """Reasoning Step 2 (was 3): Assess severity based on Impact and Likelihood."""
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
        if not all(hasattr(v, attr) for attr in ['derived_severity', 'assessed_impact', 'assessed_likelihood']): raise ValueError("Missing required fields for severity validation.")
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

# ═══════════════════════════════════════════════════════════════════════════
# Top-Level Schema for the Reasoning Strategy Output (for one finding)
# ═══════════════════════════════════════════════════════════════════════════
class FindingReasoningStrategy(BaseModel):
    """
    Represents the complete structured reasoning process for analyzing
    a single potential vulnerability. Assumes FP check is handled elsewhere.
    """
    finding_candidate_id: str = Field(..., description="Identifier for the potential finding being analyzed.")
    # Renamed for clarity
    reasoning_analysis_facts: VulnerabilityReasoningFacts = Field(..., description="Detailed facts and analysis of the vulnerability's characteristics.")
    # Severity assessment is now mandatory
    reasoning_severity_assessment: SeverityAssessmentReasoning = Field(..., description="Severity assessment.")

    # Optional: Add a field for the final synthesized description if needed here
    # synthesized_description_preview: Optional[str] = Field(None, description="Optional preview of the final description based on reasoning.")

    @model_validator(mode="after")
    def check_severity_presence(cls, v: 'FindingReasoningStrategy'):
        """Ensures severity stage is present."""
        if not hasattr(v, 'reasoning_severity_assessment') or v.reasoning_severity_assessment is None:
            raise ValueError(f"Severity assessment must be provided for finding candidate '{v.finding_candidate_id}'.")
        return v

# Optional: Wrapper if the LLM processes multiple candidates internally
class ReasoningOutput(BaseModel):
   reasoning_results: List[FindingReasoningStrategy]
   overall_notes: Optional[str] = Field(None, description="General notes about the reasoning process.")