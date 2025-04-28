from openai import OpenAI
from schema.adjustment_schema import OneAdjustmentResponse, AdjustmentsResponse
import json, pathlib, os, time, datetime
from dotenv import load_dotenv

# ------------ models & paths -------------------------------------------------
O4_MINI  = "o4-mini"

# ---------- artefacts ----------
MODEL = O4_MINI
LARGE_TASK_PROMPT  = pathlib.Path("utils/mitigation/task_prompt_large.py").read_text()
FINDINGS = json.loads(pathlib.Path("utils/mitigation/LandManager_findings.json").read_text())
CONTRACT = pathlib.Path("utils/mitigation/contract_with_lines.sol").read_text()

def checklist_bullets(items: list[dict]) -> str:
    """Render checklist as numbered bullets for the LLM."""
    return "\n".join(f"{q['id']} [{q['rule']}] {q['text']}" for q in items)

# ---------- client ----------
load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

all_adjustments = []
start = time.time()

for idx, finding in enumerate(FINDINGS):
    messages = [
        {"role": "system", "content": LARGE_TASK_PROMPT},
        {"role": "user",   "content": CONTRACT},
        {"role": "user",   "content":
            "For the finding below decide the final severity and whether it must "
            "be removed. Return JSON that matches the AdjustmentsResponse schema, "
            "no extra keys, no reasoning."},
        {"role": "user",   "content": json.dumps(finding, indent=2)},
    ]

    completion = client.beta.chat.completions.parse(
        model=MODEL,
        messages=messages,
        response_format=OneAdjustmentResponse,
    )

    resp: OneAdjustmentResponse = completion.choices[0].message.parsed
    all_adjustments.append(resp.adjustment)


now = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
out_dir = pathlib.Path("logs/mitigation")
out_dir.mkdir(parents=True, exist_ok=True)

base = f"schema4_{MODEL}_{now}"
(out_dir / f"{base}_adjustments.json").write_text(json.dumps(all_adjustments, indent=2))
    
print("✅  Done! Saved to", out_dir, "in", round(time.time() - start, 1), "s")