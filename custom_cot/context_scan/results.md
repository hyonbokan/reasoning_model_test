Muchables:
Context Digestion: 5 matches (3 + 2) / 4 matches
AuditAgent o3 zero-shot: 3 matches

Backd:
Context Digestion: 3 matches. S16*
AuditAgent o3 zero-shot: 1 matches (S3)

Tigris:
ICS best: cceed79e-3ce2-4321-98e5-d85bfdc24bcf: 10 (4 + 6) [no critic, no chunk, unfixed messages] 
ICS + CS: c807a38c-76d7-406c-9e77-f9bc3f070ef9: 
- With critics: 12 (4 + 8)?
- Without critics: 12 (8 + 4)

* not detected by AuditAgent entire pipeline


Re-run Validation	Re-run Validation without old justification	No approach	Re-run deduplication & Validation 	Re-run deduplication & Validation with web search	Re-run deduplication (Claude) & validation with o4-mini thinking	Re-run deduplication (Claude) & validation with o4-mini thinking appeal threshold changed (50)

Total Findings	244	244	244	244	244	244	244
Findings - First Validation	100	100	100	100	100	100	100
Approach	94	91	100	71	70	22	25
Matches	7+2	7+4	7+3	8+1	8+2	5+1	5+2
F1 score	11.6	11.8	11.2	16.2	16.2	19.6	18.5
FP	83	79	86	61	60	16	18


consistent:
{"role": "system", "content": f"{SYSTEM_PROMPT_PHASE1}\nPHASE-0 CONTEXT:\n```json\n{phase0_json}\n```"},
{"role": "user",      "content": f"Here are the Solidity sources:\n```solidity\n{raw_code}\n```"},


less consistent, but metter result:
{"role": "system",    "content": SYSTEM_PROMPT_PHASE1},
{"role": "user",      "content": f"Here are the Solidity sources:\n```solidity\n{raw_code}\n```"},