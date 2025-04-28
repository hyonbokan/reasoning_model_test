from __future__ import annotations

import json, pathlib, os, time, datetime
from dotenv import load_dotenv
from openai import OpenAI
from schema.mitigate_schema_4 import AuditResponse          # <- new schema
from utils.mitigation.load_rulebook import load_rulebook_html

# ------------ models & paths -------------------------------------------------
GPT_4O   = "gpt-4o-2024-08-06"
GPT_4_1  = "gpt-4.1-2025-04-14"
O4_MINI  = "o4-mini"

# ---------- artefacts ----------
MODEL = GPT_4_1
TASK_PROMPT = pathlib.Path(
    "utils/mitigation/task_prompt_reasoning.py"
).read_text()

RULE_CHUNKS = load_rulebook_html("utils/mitigation/mitigation_rulebook_1.html")
CHECKLIST   = json.loads(
    pathlib.Path("utils/mitigation/mitigation_checklist_1_1.json").read_text()
)
FINDINGS = json.loads(
    pathlib.Path("utils/mitigation/LandManager_findings.json").read_text()
)
CONTRACT = pathlib.Path(
    "utils/mitigation/contract_with_lines.sol"
).read_text()

# ------------ helper ---------------------------------------------------------
def checklist_bullets(items: list[dict]) -> str:
    return "\n".join(f"{q['id']} [{q['rule']}] {q['text']}" for q in items)

def build_rule_context(checklist, chunks):
    needed = {q["rule"] for q in checklist}
    missing = needed - chunks.keys()
    if missing:
        raise RuntimeError(f"Missing rule sections for: {', '.join(missing)}")
    return "\n\n".join(chunks[tag] for tag in needed)

RULE_CONTEXT = build_rule_context(CHECKLIST, RULE_CHUNKS)

# ------------ OpenAI client --------------------------------------------------
load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

all_reviews: list[AuditResponse.FindingReview] = []
all_adjustments, refusals = [], []

start_ts = time.time()

for idx, finding in enumerate(FINDINGS):
    print(RULE_CONTEXT)
    messages = [
        {"role": "system", "content": TASK_PROMPT},
        {"role": "user",   "content": RULE_CONTEXT},
        {"role": "user",   "content": CONTRACT},
        {"role": "user",   "content": f"Finding {idx}: {json.dumps(finding)}"},
        {"role": "user",   "content":
            "Return JSON that matches the AuditResponse schema exactly. "
            "Populate `strategy` first, then `reasoning_summary`, then `adjustment`."
        }
    ]

    # --------- official Structured-Output call -----------------------
    completion = client.beta.chat.completions.parse(
        model=MODEL,
        messages=messages,
        # temperature=0.1, # gpt 4.1 only accepts default 1
        response_format=AuditResponse,
    )

    raw = completion.choices[0].message

    # ------------- refusal branch -----------------------------------
    if getattr(raw, "refusal", None):
        refusals.append({"finding_index": idx, "reason": raw.refusal})
        print(f"Model refused on finding {idx}: {raw.refusal}")
        continue

    # ------------- success branch -----------------------------------
    fr = raw.parsed.findings[0]     # validated object

    all_reviews.append(fr)
    all_adjustments.append(fr.adjustment.model_dump())

# ------------ wrap up --------------------------------------------------------
final_report = AuditResponse(
    document_id="audit_run_004",
    findings=all_reviews
)

now = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
out_dir = pathlib.Path("logs/mitigation")
out_dir.mkdir(parents=True, exist_ok=True)

base = f"schema4_{MODEL}_{now}"
(out_dir / f"{base}.json").write_text(final_report.model_dump_json(indent=2))
(out_dir / f"{base}_adjustments.json").write_text(json.dumps(all_adjustments, indent=2))
if refusals:
    (out_dir / f"{base}_refusals.json").write_text(json.dumps(refusals, indent=2))

elapsed = time.time() - start_ts
print(f"✅  Done!  Reports saved to {out_dir} (elapsed {elapsed:.1f}s)")
