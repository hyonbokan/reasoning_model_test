from __future__ import annotations
from typing import List, Literal, Optional
from pydantic import BaseModel, Field

# --- Primitive Enums and Types ---
_SEV = Literal["High", "Medium", "Low", "Info", "Best Practices"]

# --- Schema for a Single Finding in the Final Report ---

class FindingOutput(BaseModel):
    """Represents a single formatted finding in the final audit report."""
    Issue: str = Field(..., description="Short, descriptive title of the vulnerability (max ~80 chars recommended).")
    Severity: _SEV = Field(..., description="Final severity level (High, Medium, Low, Info, Best Practices).")
    Contracts: List[str] = Field(..., description="List of affected contract filenames ending in .sol (e.g., ['ContractName.sol']). Must contain at least one entry.")
    Description: str = Field(..., description="Detailed explanation, and JSON-escaped ```solidity code snippets```. Ensure sufficient detail.")
    Recommendation: Literal[""] = Field(description="Must always be an empty string.")

# --- Top-Level Schema for the Final Audit Report ---

class FinalAuditReport(BaseModel):
    """Represents the root structure of the final JSON audit report."""
    results: List[FindingOutput] = Field(..., description="List of all validated and formatted vulnerability findings.")