# phase0_driver_chunked.py
from __future__ import annotations
import re, json, pathlib, datetime, time, itertools, os, sys
from typing import List
from dotenv import load_dotenv
from openai import OpenAI
from pydantic import ValidationError
from schema.phase_0_schemas.phase_0_schema_v9 import ContextSummaryOutput

# ───────────────────────── configuration ─────────────────────────
MODEL               = "gpt-4.1-2025-04-14"
PROMPT_FILE_SYSTEM  = "utils/prompts/phase0_v6_tight_sys_prompt.py"
# INPUT_MD            = "utils/inputs/backd_full_context.md"
# INPUT_MD            = "utils/inputs/tigris_full_context.md"
INPUT_MD            = "utils/inputs/vultisig_full_context.md"
OUTPUT_DIR_PHASE0   = "logs/phase0_results/vultisig/schema_v9"
CHUNK_SIZE          = 5                              # contracts per call
TEMPERATURE         = 0
PHASE = "phase0_v9_chunked5"
# ──────────────────────────────────────────────────────────────────

SYSTEM_PROMPT_PHASE0 = pathlib.Path(PROMPT_FILE_SYSTEM).read_text()
FULL_INPUT           = pathlib.Path(INPUT_MD).read_text()

# — split md into “docs part” (before first // File) & Solidity blobs
docs_part, *code_parts = re.split(r"(?=//\s*File:)", FULL_INPUT, maxsplit=1, flags=re.I)
if not code_parts:
    print("❌  No `// File:` markers found – aborting."); sys.exit(1)
solidity_blob = code_parts[0]

# — isolate individual files
FILE_RE = re.compile(r"(//\s*File:[^\n]+\n(?:.|\n)*?)(?=//\s*File:|$)", re.I)
all_files: List[str] = FILE_RE.findall(solidity_blob)
if not all_files:
    print("❌  Could not split contracts – check marker format."); sys.exit(1)

# batch iterator ---------------------------------------------------
batches = [all_files[i:i+CHUNK_SIZE]
           for i in range(0, len(all_files), CHUNK_SIZE)]

# ─────────────────── OpenAI client ────────────────────────────────
load_dotenv(); key = os.getenv("OPENAI_API_KEY")
if not key: print("OPENAI_API_KEY missing"); sys.exit(1)
client = OpenAI(api_key=key)

def run_single_batch(batch_idx:int, files:list[str]) -> ContextSummaryOutput|None:
    """Call the LLM with ≤CHUNK_SIZE contracts and return the parsed JSON."""
    print(f"📄  Batch {batch_idx+1}/{len(batches)}  –  {len(files)} contracts")

    docs_for_this_call = docs_part if batch_idx == 0 else ""       # send docs once
    code_for_this_call = "\n\n".join(files)

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT_PHASE0},
        {"role": "user",   "content": docs_for_this_call},
        {"role": "user",   "content": f"```solidity\n{code_for_this_call}\n```"}
    ]
    
    try:
        resp = client.beta.chat.completions.parse(
            model=MODEL,
            messages=messages,
            response_format=ContextSummaryOutput,
            temperature=TEMPERATURE,
        )
        return resp.choices[0].message.parsed
    except ValidationError as e:
        print("⚠️  Pydantic validation failed – saving raw output")
        raw = client.chat.completions.create(model=MODEL, messages=messages)
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        err = pathlib.Path(OUTPUT_DIR_PHASE0,"errors"); err.mkdir(parents=True, exist_ok=True)
        (err / f"phase0_raw_batch{batch_idx}_{timestamp}.txt").write_text(raw.choices[0].message.content)
        return None

# ────────────── run all batches & collect partials ───────────────
partials: List[ContextSummaryOutput] = []
for i, file_batch in enumerate(batches):
    out = run_single_batch(i, file_batch)
    if out: partials.append(out)
if not partials:
    print("❌  All batches failed."); sys.exit(1)

# ──────────────── merge partial JSONs ─────────────────────────────
merged_contracts = list(itertools.chain.from_iterable(p.analyzed_contracts for p in partials))

# pick the first project_context that isn’t empty
proj_ctx = next((p.project_context for p in partials
                 if p.project_context and p.project_context.overall_goal_raw.strip()), None)

# optional: union invariants / security_ctx across other partials
for p in partials[1:]:
    if p.project_context:
        proj_ctx.invariants.extend(p.project_context.invariants)
        proj_ctx.general_security_ctx.extend(p.project_context.general_security_ctx)

# de-dupe by description/id
seen = set(); proj_ctx.invariants = [inv for inv in proj_ctx.invariants
                                     if (k:=inv.description) not in seen and not seen.add(k)]
seen=set();   proj_ctx.general_security_ctx = [c for c in proj_ctx.general_security_ctx
                                               if (k:=c.details) not in seen and not seen.add(k)]

final = ContextSummaryOutput(analyzed_contracts=merged_contracts,
                             project_context   =proj_ctx)

# ─────────────── save ───────────────
outdir = pathlib.Path(OUTPUT_DIR_PHASE0); outdir.mkdir(parents=True, exist_ok=True)
ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
outfile = outdir / f"{PHASE}_{MODEL}_{ts}.json"
outfile.write_text(final.model_dump_json(indent=2))
print(f"✅  Phase-0 done – summarised {len(merged_contracts)} contracts "
      f"into {outfile}")
