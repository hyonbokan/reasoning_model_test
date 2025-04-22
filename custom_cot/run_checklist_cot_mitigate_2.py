from openai import OpenAI
from schema.mitigate_schema_2 import AuditResponse
import json, pathlib, os, time
from dotenv import load_dotenv
import datetime

# ---------- GPT models ----------
GPT_4O = "gpt-4o-2024-08-06"
GPT_4_1 = "gpt-4.1-2025-04-14"

# ---------- artefacts ----------
MODEL = GPT_4_1
TASK_PROMPT  = pathlib.Path("utils/prompts/task_prompt_free_reasoning.py").read_text()
RULEBOOK = pathlib.Path("utils/prompts/mitigate_rulebook_1.md").read_text()
CHECKLIST = json.loads(pathlib.Path("checklists/mitigate_checklist_1.1.json").read_text())
FINDINGS = json.loads(pathlib.Path("utils/findings.json").read_text())
CONTRACT = pathlib.Path("utils/contract_with_lines.sol").read_text()

def checklist_bullets(items: list[dict]) -> str:
    """Render checklist as numbered bullets for the LLM."""
    return "\n".join(f"{q['id']} [{q['rule']}] {q['text']}" for q in items)

# ---------- client ----------
load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

all_reviews = []       # successful FindingReview objects
refusals = []      # bookkeeping for refusals

for idx, finding in enumerate(FINDINGS):
    messages = [
        # static context (identical for all iterations) -----------------
        {"role": "system", "content": TASK_PROMPT},
        {"role": "user",   "content": RULEBOOK},
        {"role": "user",   "content": CONTRACT},

        # dynamic per‑finding ------------------------------------------
        {"role": "user", "content": f"Finding {idx}: {json.dumps(finding)}"},
        {"role": "user", "content":
            "Answer the checklist **in order** using the AuditResponse schema.\n"},
        {"role": "user", "content": checklist_bullets(CHECKLIST)},
    ]

    result = client.beta.chat.completions.parse(
        model=MODEL,
        response_format=AuditResponse,
        messages=messages,
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

timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")

pathlib.Path(f"logs/audit_{MODEL}_hybrid_{timestamp}.json").write_text(
    final.model_dump_json(indent=2)
)
pathlib.Path(f"logs/audit_{MODEL}_hybrid_refusals_{timestamp}.json").write_text(
    json.dumps(refusals, indent=2)
)

print("Done!")
