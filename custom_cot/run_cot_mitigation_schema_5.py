
import json, pathlib, datetime, time, os
from textwrap import dedent
from dotenv import load_dotenv
from openai import OpenAI

from schema.mitigate_schema_5 import AuditResponse, FindingResponse

# ------------ models & paths -------------------------------------------------
GPT_4O   = "gpt-4o-2024-08-06"
GPT_4_1  = "gpt-4.1-2025-04-14"
O4_MINI  = "o4-mini"

# ───────────────────────── configuration ─────────────────────────
MODEL = O4_MINI
PROMPT_FILE = "utils/mitigation/task_prompt_reasoning_2.py"
CONTRACT_FILE = "utils/mitigation/contract_with_lines.sol"
FINDINGS_FILE = "utils/mitigation/LandManager_findings.json"

TASK_PROMPT = pathlib.Path(PROMPT_FILE).read_text()
CONTRACT    = pathlib.Path(CONTRACT_FILE).read_text()
FINDINGS    = json.loads(pathlib.Path(FINDINGS_FILE).read_text())

# ───────────────────────── OpenAI client ─────────────────────────
load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

# ───────────────────────── helper function ───────────────────────
def analyse_finding(idx: int, finding_json: dict) -> FindingResponse:
    """Call OpenAI once, return validated FindingResponse."""
    messages = [
        {"role": "system", "content": TASK_PROMPT},
        {"role": "user",   "content": CONTRACT},
        {"role": "user",   "content":
            "Populate `strategy` (all fields), then `reasoning_summary` (≤3 sentences), "
            "then `adjustment`. Return JSON conforming to AuditResponse schema."},
        {"role": "user",   "content": f"Finding {idx} JSON:\n```json\n{json.dumps(finding_json)}\n```"},
    ]

    completion = client.beta.chat.completions.parse(
        model=MODEL,
        messages=messages,
        response_format=AuditResponse,
        # temperature=0
    )

    return completion.choices[0].message.parsed.findings[0]

# ───────────────────────── main loop ─────────────────────────────
all_findings: list[FindingResponse] = []
all_adj      : list[dict] = []

start = time.time()

for idx, finding in enumerate(FINDINGS):
    print(f"Analyzing finding #{idx} …")
    try:
        fr = analyse_finding(idx, finding)
    except Exception as e:
        print(f"Error on #{idx}: {e}")
        continue

    all_findings.append(fr)
    all_adj.append(fr.adjustment.model_dump())
    print("Done.")

# ───────────────────────── save outputs ──────────────────────────
report = AuditResponse(
    document_id="audit_run_schema5",
    findings=all_findings
)

ts = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
out_dir = pathlib.Path("logs/mitigation")
out_dir.mkdir(parents=True, exist_ok=True)

(out_dir / f"audit_{MODEL}_{ts}.json").write_text(report.model_dump_json(indent=2))
(out_dir / f"audit_{MODEL}_{ts}_adjustments.json").write_text(json.dumps(all_adj, indent=2))

print(f"\n✅  Finished {len(all_findings)} findings in {round(time.time()-start,1)} s")
print(f"Results saved to {out_dir}")