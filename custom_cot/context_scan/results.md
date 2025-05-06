Muchables:
Context Digestion: 5 matches (3 + 2) / 4 matches
AuditAgent o3 zero-shot: 3 matches

Backd:
Context Digestion: 3 matches. S16*
AuditAgent o3 zero-shot: 1 matches (S3)

Tigris:
Context Digestion: 2 matches. (s18*, s28)
AuditAgent o3 zero-shot: 2 matches


* not detected by AuditAgent entire pipeline



consistent:
{"role": "system", "content": f"{SYSTEM_PROMPT_PHASE1}\nPHASE-0 CONTEXT:\n```json\n{phase0_json}\n```"},
{"role": "user",      "content": f"Here are the Solidity sources:\n```solidity\n{raw_code}\n```"},


less consistent:
{"role": "system",    "content": SYSTEM_PROMPT_PHASE1},
{"role": "user",      "content": f"Here are the Solidity sources:\n```solidity\n{raw_code}\n```"},