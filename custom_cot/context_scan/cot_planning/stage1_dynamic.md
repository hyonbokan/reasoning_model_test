# Phase 0: Context Structuring & Candidate Identification (LLM Call 0)
Input: Raw prompt (all code, all context).
Task: "Analyze the provided Solidity code and extensive context (summary, docs, invariants, web findings). Structure the key contextual elements (actors, core functions, external interactions, key security constraints mentioned). Then, identify potential vulnerability candidates (FindingCandidate list) by correlating code patterns with the context. For each candidate, specify the suspected class and code references."
Output Schema: A Pydantic model containing StructuredContextSummary and List[FindingCandidate].

# Phase 1: Fact Finding (LLM Call 1 per candidate)
Input: StructuredContextSummary, one FindingCandidate from Phase 0.
Task: "Analyze FindingCandidate ID {id}... Fill FactFindingStage..." (as before)
Output Schema: FactFindingStage.

# Phase 2: False Positive Filtering (LLM Call 2 per candidate)
Input: FactFindingStage from Phase 1.
Task: "Based on the provided facts, determine if this is likely an FP... Fill FalsePositiveFilteringStage..." (as before)
Output Schema: FalsePositiveFilteringStage.

# Phase 3: Severity Assessment (LLM Call 3 per candidate - Conditional)
Input: FactFindingStage, FalsePositiveFilteringStage, relevant context summary snippet, severity matrix rules.
Task: "Assess Impact and Likelihood... Determine Severity using the matrix... Fill SeverityAssessmentStage..." (as before)
Output Schema: SeverityAssessmentStage.

# Phase 4: Report Assembly (Application Logic)
