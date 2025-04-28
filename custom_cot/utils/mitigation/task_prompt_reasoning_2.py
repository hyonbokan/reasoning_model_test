from textwrap import dedent

TASK_PROMPT = dedent("""
    You are an expert smart-contract mitigation critic.

    1. Read the rule book snippets that follow.
    2. Analyse the Solidity code and the finding JSON.
    3. Populate the `strategy` object field-by-field, using the descriptions
       in the JSON schema.
    4. Write a ≤3-sentence `reasoning_summary`.
    5. Fill `adjustment`.  
       • `final_severity` **must** equal the matrix result  
       • If `strategy.removal_reason != "none"`, set `should_be_removed = true`.
    6. Return JSON that matches the AuditResponse schema exactly—no extra keys,
       no commentary outside the JSON.
""")