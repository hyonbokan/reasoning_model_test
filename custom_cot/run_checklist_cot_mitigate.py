from openai import OpenAI
from schema.mitigate_schema import AuditResponse
import json, pathlib, os, time
from dotenv import load_dotenv

# ---------- GPT models ----------
GPT_4O = "gpt-4o-2024-08-06"
GPT_4_1 = "gpt-4.1-2025-04-14"

# ---------- artefacts ----------
MODEL = GPT_4_1
TASK_PROMPT  = pathlib.Path("utils/task_prompt.py").read_text()
CHECKLIST    = json.loads(pathlib.Path("checklists/mitigate_checklist_1.1.json").read_text())
FINDINGS     = json.loads(pathlib.Path("utils/findings.json").read_text())
CODE         = pathlib.Path("utils/contract_with_lines.sol").read_text()

def checklist_as_bullets(items):       # unchanged
    return "\n".join(f"{q['id']}. {q['text']}" for q in items)

# ---------- client ----------
load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

all_reviews = []       # successful FindingReview objects
refusals     = []      # bookkeeping for refusals

for idx, finding in enumerate(FINDINGS):
    msgs = [
        {"role": "system", "content": TASK_PROMPT},
        {"role": "user",   "content": CODE},
        {"role": "user",   "content": f"Finding {idx}: {json.dumps(finding)}"},
        {"role": "user",   "content": (
            "Answer the checklist **in order** using the AuditResponse schema."
        )},
        {"role": "user",   "content": checklist_as_bullets(CHECKLIST)},
    ]

    result = client.beta.chat.completions.parse(
        model=MODEL,
        response_format=AuditResponse,
        messages=msgs,
    )

    message = result.choices[0].message

    # ----- refusal branch --------------------------------------------
    if message.refusal:
        refusals.append({
            "finding_index": idx,
            "reason": message.refusal,
        })
        print(f"Model refused on finding {idx}: {message.refusal}")
        continue

    # ----- success branch --------------------------------------------
    parsed: AuditResponse = message.parsed
    all_reviews.append(parsed.finding_reviews[0])

# ---------- wrap up --------------------------------------------------
final = AuditResponse(
    document_id="audit_run_001",
    finding_reviews=all_reviews,
)

pathlib.Path(f"logs/audit_{MODEL}_response.json").write_text(
    final.model_dump_json(indent=2)
)
pathlib.Path(f"logs/audit_{MODEL}_refusals.json").write_text(
    json.dumps(refusals, indent=2)
)

print("Done → audit_response.json  |  refusals → audit_refusals.json")
