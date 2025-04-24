from openai import OpenAI
from schema.mitigate_schema_2 import AuditResponse
import json, pathlib, os, time
from dotenv import load_dotenv
import datetime

# ---------- GPT models ----------
GPT_4O = "gpt-4o-2024-08-06"
GPT_4_1 = "gpt-4.1-2025-04-14"
O4_MINI = "o4-mini"

# ---------- artefacts ----------
MODEL = GPT_4_1
TASK_PROMPT  = pathlib.Path("utils/mitigation/task_prompt_reasoning.py").read_text()
RULEBOOK = pathlib.Path("utils/mitigation/mitigation_rulebook_1.md").read_text()
CHECKLIST = json.loads(pathlib.Path("utils/mitigation/mitigation_checklist_1_1.json").read_text())
FINDINGS = json.loads(pathlib.Path("utils/mitigation/findings.json").read_text())
CONTRACT = pathlib.Path("utils/mitigation/contract_with_lines.sol").read_text()

def checklist_bullets(items: list[dict]) -> str:
    """Render checklist as numbered bullets for the LLM."""
    return "\n".join(f"{q['id']} [{q['rule']}] {q['text']}" for q in items)

# ---------- client ----------
load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

all_reviews = []       # successful FindingReview objects
all_adjustments = []    # flattened adjustment dicts
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
    
    # Struct from doc:
    # result = client.chat.completions.create(
    #     model=MODEL,
    #     messages=messages,
    #     text={
    #         "format": {
    #             "type": "json_schema",
    #             "schema": AuditResponse.model_json_schema(),
    #             "strict": True
    #         }
    #     }
    # )

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
    fr = parsed.finding_reviews[0]

    all_reviews.append(fr)                      # full object
    all_adjustments.append(fr.adjustment.dict())  # just the summary line
    

# ---------- wrap up --------------------------------------------------
final = AuditResponse(
    document_id="audit_run_001",
    finding_reviews=all_reviews,
)

timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
out_dir   = pathlib.Path("logs/mitigation")
out_dir.mkdir(exist_ok=True)

# 1. full reasoning + QA trace
out_dir.joinpath(
    f"cot_schema2_{MODEL}_hybrid_{timestamp}.json"
).write_text(final.model_dump_json(indent=2))

# 2. flat list of adjustments for quick diff
out_dir.joinpath(
    f"cot_schema2_{MODEL}_hybrid_adjustments_{timestamp}.json"
).write_text(json.dumps(all_adjustments, indent=2))

# 3. refusals log (if any)
# out_dir.joinpath(
#     f"audit_{MODEL}_hybrid_refusals_{timestamp}.json"
# ).write_text(json.dumps(refusals, indent=2))

print("Done! Saved full report, adjustments, and refusals in /logs")