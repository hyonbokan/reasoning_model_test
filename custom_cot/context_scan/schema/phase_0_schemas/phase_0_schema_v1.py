# Key Sub-Models:
# ContractAnalysis: Focuses on summarizing one contract file structurally.
# ProjectContextAnalysis: Focuses on summarizing all non-code context semantically.
# FindingCandidate: Represents one specific point of interest requiring further analysis.
# CodeRef: Crucially, this identifies a code location without line numbers. It relies on:
    # file: Which contract file.
    # element_name: The function, modifier, variable, etc.
    # unique_snippet: A short piece of code within that element that should uniquely pinpoint the exact spot. This is the key locator used instead of line numbers.
# ContextRef: Links a piece of information back to its origin and meaning:
    # source: Where in the input document structure it came from (e.g., summary, docs, web_context).
    # context_type: What kind of information it is (e.g., security_assumption, best_practice, common_vulnerability). This adds semantic understanding.
    # details: The actual text or quote.

# This schema provides a solid foundation for the first LLM call, capturing the necessary structured information to feed into the subsequent, more focused analysis phases for each identified candidates

from __future__ import annotations
from typing import List, Literal, Optional, Dict, Any, Union
from pydantic import BaseModel, Field, model_validator

# --- Primitive Enums and Types ---
_CONTEXT_SOURCE = Literal[
    "summary",
    "docs",
    "invariants",
    "web_context", # Refers to the specific section if present
    "code_comment",
    "logic_inference", # Deduced from code flow/logic
    "other", # If it doesn't fit structured sections
    "none", # If no specific source applies
]

# What kind of information it is (Semantic Type)
_CONTEXT_TYPE = Literal[
    "protocol_goal",
    "actor_definition",
    "asset_description",
    "function_purpose",
    "interaction_flow",
    "security_assumption",
    "invariant_rule",
    "best_practice",        # e.g., CEI pattern, use of SafeMath
    "common_vulnerability", # e.g., Reentrancy description, overflow risk
    "compiler_warning",     # e.g., Notes about transient storage, EVM version
    "eip_standard",         # e.g., ERC-721 compliance detail
    "access_control_rule",
    "state_variable_meaning",
    "configuration_setting",
    "external_dependency_info",
    "other_detail", # General detail not fitting specific types
]


# --- Helper Models ---

class CodeRef(BaseModel):
    """Reference using element names and unique snippets."""
    file: str = Field(..., description="Filename (e.g., ContractName.sol) from '// File:'.")
    element_name: str = Field(..., description="Primary code element name (function, modifier, variable, etc.).")
    unique_snippet: str = Field(..., description="Short, uniquely identifying code snippet (1-3 lines, ~50-150 chars) within the element.")
    rationale: Optional[str] = Field(None, description="Optional brief explanation why this location is relevant.")

class ContextRef(BaseModel):
    """Reference to a piece of contextual information, classified by source and type."""
    source: _CONTEXT_SOURCE = Field(
        ...,
        description="Where in the input document structure was this information found?"
    )
    context_type: _CONTEXT_TYPE = Field(
        ...,
        description="What is the semantic type of this piece of information?"
    )
    details: str = Field(
        ...,
        description="Specific quote, rule, observation, or referenced point supporting an assessment."
    )

# --- Core Schema Components for Phase 0 ---

class ContractAnalysis(BaseModel):
    """Summarizes key security-relevant aspects of a single contract file."""
    file_name: str = Field(..., description="Contract filename from '// File:'.")
    core_purpose: str = Field(..., description="Main role/functionality based on code and context.")
    identified_roles: List[str] = Field(default_factory=list, description="Specific roles interacting (owner, admin, user, etc.).")
    key_state_variables_security: List[str] = Field(default_factory=list, description="Critical state variable names.")
    key_functions_security: List[str] = Field(default_factory=list, description="Primary external/public function names relevant to security.")
    external_dependencies: List[str] = Field(default_factory=list, description="Interfaces, contract types, or addresses interacted with.")
    security_notes_from_code: List[str] = Field(default_factory=list, description="Direct observations (e.g., 'Uses delegatecall', 'Inherits Ownable').")

class ProjectContextAnalysis(BaseModel):
    """Structured summary of the overall project context relevant to security."""
    overall_protocol_goal: str = Field(..., description="Main objective/value proposition.")
    system_actors_and_capabilities: List[str] = Field(default_factory=list, description="Primary actors/roles across the system and their capabilities.")
    core_assets_managed: List[str] = Field(default_factory=list, description="Primary assets/value managed (tokens, NFTs, points, etc.).")
    critical_cross_contract_interactions: List[str] = Field(default_factory=list, description="Key interactions *between* contracts or with external systems.")
    # Uses the enhanced ContextRef
    key_security_assumptions_or_invariants: List[ContextRef] = Field(
        default_factory=list,
        description="List explicit/implicit security assumptions or invariants mentioned, classified by source and type."
    )
    # Uses the enhanced ContextRef
    applicable_general_security_context: List[ContextRef] = Field(
        default_factory=list,
        description="List key security principles, warnings, best practices, compiler issues, etc., from *any* context source (web, docs, etc.) deemed relevant to this project, classified by source and type."
    )

class FindingCandidate(BaseModel):
    """Represents a potential vulnerability identified for deeper analysis."""
    candidate_id: str = Field(..., description="Unique identifier (e.g., CAND-001).")
    contract_file: str = Field(..., description="Specific contract filename.")
    # Uses CodeRef without line numbers
    code_refs: List[CodeRef] = Field(..., description="Specific code locations (element name + unique snippet).")
    hypothesized_vuln_class: str = Field(..., description="Initial hypothesis for the vulnerability class.")
    observation_reasoning: str = Field(..., description="Why this is considered a candidate, referencing code/context.")
    # Optional: Link relevant context directly to the candidate
    supporting_context_refs: List[ContextRef] = Field(
        default_factory=list,
        description="Optionally list specific ContextRefs that directly support *this specific* candidate."
    )


# --- Top-Level Schema for Phase 0 Output ---

class InitialAnalysisPhaseOutput(BaseModel):
    """
    Schema for Phase 0 output. Uses enhanced ContextRef with semantic typing.
    """
    analyzed_contracts_summary: List[ContractAnalysis] = Field(..., description="Structured summary for each contract file.")
    project_context_summary: ProjectContextAnalysis = Field(..., description="Consolidated summary of project security context.")
    identified_finding_candidates: List[FindingCandidate] = Field(..., description="List of potential vulnerability candidates.")

    # Validator remains mostly the same, just ensures ContextRef fields are populated
    @model_validator(mode="after")
    def check_references_consistency(cls, v):
        # ... (previous checks for contract files and CodeRefs) ...

        # Check ContextRefs within ProjectContextAnalysis
        for ref in v.project_context_summary.key_security_assumptions_or_invariants:
            if not ref.source or not ref.context_type or not ref.details:
                 raise ValueError("ContextRef in key_security_assumptions_or_invariants is missing required fields.")
        for ref in v.project_context_summary.applicable_general_security_context:
             if not ref.source or not ref.context_type or not ref.details:
                 raise ValueError("ContextRef in applicable_general_security_context is missing required fields.")

        # Check ContextRefs within FindingCandidates (if used)
        for candidate in v.identified_finding_candidates:
            for ref in candidate.supporting_context_refs:
                 if not ref.source or not ref.context_type or not ref.details:
                      raise ValueError(f"ContextRef in supporting_context_refs for candidate '{candidate.candidate_id}' is missing required fields.")
        return v