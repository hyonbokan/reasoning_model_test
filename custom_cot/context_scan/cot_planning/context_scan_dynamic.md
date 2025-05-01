# Phase 0 - v1
## Phase 0: Context Structuring & Candidate Identification (LLM Call 0)
Input: Raw prompt (all code, all context).
Task: "Analyze the provided Solidity code and extensive context (summary, docs, invariants, web findings). Structure the key contextual elements (actors, core functions, external interactions, key security constraints mentioned). Then, identify potential vulnerability candidates (FindingCandidate list) by correlating code patterns with the context. For each candidate, specify the suspected class and code references."
Output Schema: A Pydantic model containing StructuredContextSummary and List[FindingCandidate].


* o3 got closer to a High severity finding by flagging the exact calculation location in _farmPlots.

* gpt demonstrated a more structured and broad understanding of general security concerns related to dependencies and configuration.


## Phase 1: Fact Finding (LLM Call 1 per candidate)
Input: StructuredContextSummary, one FindingCandidate from Phase 0.
Task: "Analyze FindingCandidate ID {id}... Fill FactFindingStage..." (as before)
Output Schema: FactFindingStage.


