from __future__ import annotations
from typing import List, Literal, Optional, Dict, Any, Union
from pydantic import BaseModel, Field, model_validator

# --- Primitive Enums and Types ---
_CONTEXT_SOURCE = Literal[
    "summary", "docs", "invariants", "web_context",
    "static_analysis",
    "code_comment", "logic_inference", "other", "none",
]
_CONTEXT_TYPE = Literal[
    "protocol_goal", "actor_definition", "asset_description",
    "function_purpose", "interaction_flow", "security_assumption",
    "invariant_rule", "best_practice", "common_vulnerability",
    "compiler_warning", "eip_standard", "access_control_rule",
    "state_variable_meaning", "configuration_setting",
    "external_dependency_info",
    "static_analysis_finding",
    "other_detail",
]
_SEVERITY_ESTIMATE = Literal["High", "Medium", "Low", "Info", "Best Practices", "Unknown"] # Used for static analysis severity

# --- Helper Models ---

class CodeRef(BaseModel):
    """Reference using element names and unique snippets."""
    file: str = Field(..., description="Filename (e.g., ContractName.sol) from '// File:'.")
    element_name: Optional[str] = Field(None, description="Primary code element name (function, modifier, variable, etc.). Optional if ref is general to file.")
    unique_snippet: Optional[str] = Field(None, description="Short, uniquely identifying code snippet (1-3 lines, ~50-150 chars) within the element. Optional if ref is general.")
    # Add line numbers if available from static analysis tools
    lines: Optional[List[int]] = Field(None, description="Optional: List of relevant 1-based line numbers if available (e.g., from static analysis).")

class ContextRef(BaseModel):
    """Reference to a piece of contextual information, classified by source and type."""
    source: _CONTEXT_SOURCE = Field(..., description="Where in the input document structure was this information found?")
    context_type: _CONTEXT_TYPE = Field(..., description="What is the semantic type of this piece of information?")
    details: str = Field(..., description="Specific quote, rule, observation, or referenced point.")
    # Optional: Link code for context points that refer to specific code elements
    related_code_ref: Optional[CodeRef] = Field(None, description="Optional code reference if this context point relates to specific code.")

class StaticAnalysisFindingRef(BaseModel):
    """Structured representation of a finding from a static analysis tool."""
    tool_name: str = Field(..., description="Name of the static analysis tool (e.g., Slither).")
    check_id: str = Field(..., description="The specific check or rule ID from the tool (e.g., 'reentrancy-eth', 'uninitialized-state').")
    description: str = Field(..., description="The description of the finding provided by the tool.")
    severity: _SEVERITY_ESTIMATE = Field(..., description="Severity level assigned by the tool (or 'Unknown').")
    code_ref: CodeRef = Field(..., description="Code location identified by the tool.")

# --- Core Schema Components for Phase 0 ---

class ContractAnalysis(BaseModel):
    """Summarizes key security-relevant aspects of a single contract file."""
    file_name: str = Field(..., description="Contract filename from '// File:'.")
    core_purpose: str = Field(..., description="Main role/functionality based on code and context.")
    identified_roles: List[str] = Field(default_factory=list, description="Specific roles interacting.")
    key_state_variables_security: List[str] = Field(default_factory=list, description="Critical state variable names.")
    key_functions_security: List[str] = Field(default_factory=list, description="Primary function names relevant to security.")
    external_dependencies: List[str] = Field(default_factory=list, description="Interfaces, contracts, addresses interacted with.")
    security_notes_from_code: List[str] = Field(default_factory=list, description="Direct observations (e.g., 'Uses delegatecall').")
    static_analysis_findings: List[StaticAnalysisFindingRef] = Field(
        default_factory=list,
        description="List of structured findings from static analysis tools pertaining *only* to this contract file."
    )

class ProjectContextAnalysis(BaseModel):
    """Structured summary of the overall project context relevant to security."""
    overall_protocol_goal: str = Field(..., description="Main objective/value proposition.")
    system_actors_and_capabilities: List[str] = Field(default_factory=list, description="Primary actors/roles and capabilities.")
    core_assets_managed: List[str] = Field(default_factory=list, description="Primary assets/value managed.")
    critical_cross_contract_interactions: List[str] = Field(default_factory=list, description="Key interactions *between* contracts or external systems.")
    key_security_assumptions_or_invariants: List[ContextRef] = Field(default_factory=list, description="Explicit/implicit assumptions or invariants mentioned, classified.")
    applicable_general_security_context: List[ContextRef] = Field(default_factory=list, description="Key security principles, warnings, best practices from *any* source deemed relevant, classified.")
    overall_static_analysis_summary: Optional[str] = Field(None, description="High-level summary of static analysis themes.")


# --- Top-Level Schema for Phase 0 Output ---

class ContextSummaryOutput(BaseModel):
    """
    Schema for the output of Phase 0: Comprehensive Context Summarization.
    Focuses on structuring all provided context, including static analysis,
    without identifying vulnerability candidates itself.
    """
    analyzed_contracts_summary: List[ContractAnalysis] = Field(..., description="Structured summary for each contract file, including its static analysis findings.")
    project_context_summary: ProjectContextAnalysis = Field(..., description="Consolidated summary of the project's security-relevant context.")

    # Basic validation
    @model_validator(mode="after")
    def check_consistency(cls, v):
        if not v.analyzed_contracts_summary:
             print("Warning: No contracts were summarized.")
        # Add more checks if needed, e.g., ensuring static analysis refs are valid
        return v

