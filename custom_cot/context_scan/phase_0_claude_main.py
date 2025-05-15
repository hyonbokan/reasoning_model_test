from __future__ import annotations
import os, sys, re, json, time, datetime, itertools, pathlib
from typing import List

from dotenv import load_dotenv
from pydantic import ValidationError
from schema.phase_0_schemas.phase_0_schema_v8 import ContextSummaryOutput

# ────────────────────────────── CONFIG ───────────────────────────
MODEL_FAMILY        = "anthropic"
# MODEL_FAMILY        = "openai"

CLAUDE_MODEL        = "claude-3-7-sonnet-20250219"
# CLAUDE_MODEL        = "claude-3-5-haiku-20241022"
GPT_MODEL           = "gpt-4.1-2025-04-14"

PROMPT_FILE_SYSTEM  = "utils/prompts/phase0_v6_tight_sys_prompt.py"
INPUT_MD            = "utils/inputs/vultisig_full_context.md"
OUTPUT_DIR_PHASE0   = "logs/phase0_results/vultisig/schema_v8"
CHUNK_SIZE          = 5                 # contracts per call
TEMPERATURE         = 0
PHASE               = f"{MODEL_FAMILY}_phase0_v8_chunked"

# ────────────────────────── PREP INPUT ───────────────────────────
SYSTEM_PROMPT = pathlib.Path(PROMPT_FILE_SYSTEM).read_text()
FULL_INPUT    = pathlib.Path(INPUT_MD).read_text()

docs_part, *code_parts = re.split(r"(?=//\s*File:)", FULL_INPUT, maxsplit=1, flags=re.I)
if not code_parts:
    print("❌  No `// File:` markers found."); sys.exit(1)
solidity_blob = code_parts[0]

FILE_RE = re.compile(r"(//\s*File:[^\n]+\n(?:.|\n)*?)(?=//\s*File:|$)", re.I)
all_files: List[str] = FILE_RE.findall(solidity_blob)
if not all_files:
    print("❌  Could not split contracts."); sys.exit(1)

batches = [all_files[i:i + CHUNK_SIZE] for i in range(0, len(all_files), CHUNK_SIZE)]

# ───────────────────── LLM CLIENT FACTORY ────────────────────────
load_dotenv()
if MODEL_FAMILY == "openai":
    from openai import OpenAI
    client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))
    MODEL = GPT_MODEL

    def llm_call(messages, pydantic_schema):
        # OpenAI beta `parse` endpoint
        return client.beta.chat.completions.parse(
            model=MODEL,
            messages=messages,
            response_format=pydantic_schema,
            temperature=TEMPERATURE,
        ).choices[0].message.parsed

elif MODEL_FAMILY == "anthropic":
    import asyncio
    from anthropic import AsyncAnthropic, AnthropicError
    # bring in your prod helper
    from utils import get_claude_client  
    MODEL = CLAUDE_MODEL

    def llm_call(
        messages: list[dict[str,str]],
        response_model: type[ContextSummaryOutput]|None = None,
    ):
        claude_client = get_claude_client()
        max_tokens = 40000 if "3-7" in MODEL else 8192

        api_params = {
            "model": MODEL,
            "messages": messages,
            "max_tokens": max_tokens,
        }
        if response_model:
            api_params["response_model"] = response_model
        
        # respect your global TEMPERATURE / thinking flags
        if "3-7" in MODEL:
            api_params["thinking"] = {"type": "enabled", "budget_tokens": 30000}
        else:
            api_params["temperature"] = TEMPERATURE

        try:
            resp =  asyncio.run(claude_client.completions.create(**api_params))
            if response_model:
                # structured output is available as .parsed
                return resp
            else:
                # fallback to raw text
                return resp.content[0].text
        except AnthropicError as e:
            print(f"Anthropic API error: {e}", exc_info=True)
            raise print("Anthropic API error", {"error": str(e)}) from e

else:
    print("Unsupported MODEL_FAMILY"); sys.exit(1)

# ──────────────────── CHUNKED INGESTION LOOP ─────────────────────
def run_batch(idx: int, files: List[str]) -> ContextSummaryOutput | None:
    print(f"📄  Batch {idx+1}/{len(batches)}  – {len(files)} contract(s)")
    docs  = docs_part if idx == 0 else ""
    code  = "\n\n".join(files)

    if MODEL_FAMILY == "anthropic":
        # Claude: everything in one *user* turn
        merged = f"""{SYSTEM_PROMPT}
        {docs}
        ```solidity
        {code}
        ``"""
        messages = [{"role": "user", "content": merged}]
    else:
        # OpenAI: regular system / user split
        messages = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user",   "content": docs},
            {"role": "user",   "content": f"```solidity\n{code}\n```"},
        ]
    try:
        return llm_call(messages, ContextSummaryOutput)
    except ValidationError as ve:
        print("⚠️  Pydantic validation failed.")
        raw_out = llm_call(messages, None)  # get plain text for debugging
        ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        err_dir = pathlib.Path(OUTPUT_DIR_PHASE0, "errors"); err_dir.mkdir(parents=True, exist_ok=True)
        (err_dir / f"batch{idx}_{ts}.txt").write_text(str(raw_out))
        return None

partials: List[ContextSummaryOutput] = []
for i, chunk in enumerate(batches):
    out = run_batch(i, chunk)
    if out: partials.append(out)

if not partials:
    print("❌  All batches failed."); sys.exit(1)

# ───────────── MERGE PARTIAL SUMMARIES (same as before) ──────────
merged_contracts = list(itertools.chain.from_iterable(p.analyzed_contracts for p in partials))
proj_ctx = next((p.project_context for p in partials
                 if p.project_context and p.project_context.overall_goal_raw.strip()), partials[0].project_context)

for p in partials[1:]:
    proj_ctx.invariants            += p.project_context.invariants
    proj_ctx.general_security_ctx  += p.project_context.general_security_ctx

dedup = lambda seq, key: list({key(x): x for x in seq}.values())
proj_ctx.invariants           = dedup(proj_ctx.invariants,          lambda x: x.description)
proj_ctx.general_security_ctx = dedup(proj_ctx.general_security_ctx,lambda x: x.details)

final = ContextSummaryOutput(analyzed_contracts=merged_contracts,
                             project_context   = proj_ctx)

outdir = pathlib.Path(OUTPUT_DIR_PHASE0); outdir.mkdir(parents=True, exist_ok=True)
ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
outfile = outdir / f"{PHASE}_{MODEL}_{ts}.json"
outfile.write_text(final.model_dump_json(indent=2))
print(f"✅  Phase-0 finished – {len(merged_contracts)} contracts summarised → {outfile}")
