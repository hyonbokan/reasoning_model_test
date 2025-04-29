

import json, pathlib, datetime, time, os
from textwrap import dedent
from dotenv import load_dotenv
from openai import OpenAI

from schema.mitigate_schema_6 import AuditResponse, FindingResponse

# ------------ models & paths -------------------------------------------------
GPT_4O   = "gpt-4o-2024-08-06"
GPT_4_1  = "gpt-4.1-2025-04-14"
O4_MINI  = "o4-mini"
# ───────────────────────── configuration ─────────────────────────
MODEL = GPT_4_1
PROMPT_FILE = "utils/prompts/task_prompt_reasoning_2.py"
CONTRACT_FILE = "utils/contracts/LandManagerWithLines.sol"
FINDINGS_FILE = "utils/findings/LandManager_findings.json"

TASK_PROMPT = pathlib.Path(PROMPT_FILE).read_text()
CONTRACT = pathlib.Path(CONTRACT_FILE).read_text()
FINDINGS = json.loads(pathlib.Path(FINDINGS_FILE).read_text())
# BATCH_SIZE = len(FINDINGS)
BATCH_SIZE = 20
SCHEMA = "schema_8"
# ───────────────────────── OpenAI client ─────────────────────────
load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

# ───────────────────────── helper function ───────────────────────
def analyse_batch(batch: list[dict], start_index: int) -> list[FindingResponse]:
    """Return FindingResponse list for `batch` (offset keeps original indices)."""
    findings_block = "\n".join(
        f"Finding {start_index+i} JSON:\n```json\n{json.dumps(f)}\n```"
        for i, f in enumerate(batch)
    )
    
    messages = [
        {"role": "system", "content": TASK_PROMPT},
        {"role": "user",   "content": CONTRACT},
        {"role": "user",   "content":
            "For each finding below, populate `strategy`, `reasoning_summary`, and `adjustment`. "
            "Return JSON conforming to AuditResponse schema (list of finding responses)."},
        {"role": "user",   "content": findings_block},
    ]

    completion = client.beta.chat.completions.parse(
        model=MODEL,
        messages=messages,
        response_format=AuditResponse,
        # temperature=0,
    )

    return completion.choices[0].message.parsed.findings

# ───────────────────────── main loop ─────────────────────────────
all_findings: list[FindingResponse] = []
start_ts = time.time()

for start_idx in range(0, len(FINDINGS), BATCH_SIZE):
    batch = FINDINGS[start_idx : start_idx + BATCH_SIZE]
    print(f"Analyzing batch {start_idx}…{start_idx+len(batch)-1} (size {len(batch)})")
    all_findings.extend(analyse_batch(batch, start_idx))
    print("Done.")

# flatten adjustments
all_adj = [fr.adjustment.model_dump() for fr in all_findings]

# ───────────────────────── save outputs ──────────────────────────
report = AuditResponse(
    document_id=SCHEMA,
    findings=all_findings
)

ts = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
out_dir = pathlib.Path("logs")
out_dir.mkdir(parents=True, exist_ok=True)

(out_dir / f"LandManager_{MODEL}_{SCHEMA}_batch.json").write_text(report.model_dump_json(indent=2))
(out_dir / f"LandManager_{MODEL}_{SCHEMA}_adjustments_batch.json").write_text(json.dumps(all_adj, indent=2))

print(f"\n✅  Finished {len(all_findings)} findings in {round(time.time()-start_ts,1)} s")
print(f"Results saved to {out_dir}")