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
MODEL = O4_MINI
TASK_PROMPT  = pathlib.Path("utils/mitigation/task_prompt_reasoning.py").read_text()
# RULEBOOK = pathlib.Path("utils/mitigation/mitigation_rulebook_1.md").read_text()
RULEBOOK = pathlib.Path("utils/mitigation/mitigation_rulebook_1.html").read_text()
CHECKLIST = json.loads(pathlib.Path("utils/mitigation/mitigation_checklist_1_1.json").read_text())
FINDINGS = json.loads(pathlib.Path("utils/mitigation/LandManager_findings.json").read_text())
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

start_time = time.time()

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
    fr = parsed.finding_reviews[0]

    all_reviews.append(fr)                      # full object
    all_adjustments.append(fr.adjustment.model_dump())  # just the summary line
    

# ---------- wrap up --------------------------------------------------
final = AuditResponse(
    document_id="audit_run_001",
    finding_reviews=all_reviews,
)

timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
out_dir   = pathlib.Path("logs/mitigation")
out_dir.mkdir(parents=True, exist_ok=True)

base_name = f"cot_schema2_{MODEL}_{timestamp}"

# 1. full reasoning + QA trace
full_path = out_dir / f"{base_name}.json"
full_path.write_text(final.model_dump_json(indent=2))

# 2. flat list of adjustments
adj_path = out_dir / f"{base_name}_adjustments.json"
adj_path.write_text(json.dumps(all_adjustments, indent=2))

# 3. refusals log (if any)
# refusals_path = out_dir / f"{base_name}_refusals.json"
# refusals_path.write_text(json.dumps(refusals, indent=2))

# Compute elapsed time
end_time = time.time()
duration = end_time - start_time

# 4. write the note file
note_path = out_dir / f"{base_name}.txt"
note_path.write_text(f"Script completed in {duration:.2f} seconds\n")

print(f"Done! Reports saved under {out_dir}/")
print(f"Total time: {duration:.2f} seconds (see {note_path.name})")