from __future__ import annotations
import os, sys, re, json, datetime, pathlib
from typing import List

from dotenv import load_dotenv
from pydantic import ValidationError
from schema.phase_0_schemas.phase_0_schema_v9 import (
    ContextSummaryOutput,
    ProjectContext,
    ContractsContext,
)
from utils import get_claude_client

# ────────────────────────────── CONFIG ───────────────────────────
# MODEL_FAMILY       = "anthropic"
MODEL_FAMILY       = "openai"
CLAUDE_MODEL       = "claude-3-5-haiku-20241022"
GPT_MODEL          = "gpt-4.1-2025-04-14"
PROMPT_FILE_SYSTEM = "utils/prompts/phase0_v6_tight_sys_prompt.py"
INPUT_MD           = "utils/inputs/tigris_full_context.md"
OUTPUT_DIR_PHASE0  = "logs/phase0_results/tigris/schema_v9"
TEMPERATURE        = 0

# ────────────────────────── PREP INPUT ───────────────────────────
SYSTEM_PROMPT = pathlib.Path(PROMPT_FILE_SYSTEM).read_text()
FULL_INPUT    = pathlib.Path(INPUT_MD).read_text()

# ───────────────────── LLM CLIENT FACTORY ────────────────────────
load_dotenv()
if MODEL_FAMILY == "openai":
    from openai import OpenAI
    client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))
    MODEL = GPT_MODEL

    def llm_call(messages, schema):
        return client.beta.chat.completions.parse(
            model=MODEL,
            messages=messages,
            response_format=schema,
            temperature=TEMPERATURE,
        ).choices[0].message.parsed

elif MODEL_FAMILY == "anthropic":
    import asyncio
    from anthropic import AnthropicError

    MODEL = CLAUDE_MODEL

    def llm_call(messages, schema):
        claude = get_claude_client()
        max_tokens = 40000 if "3-7" in MODEL else 8192

        api_params = {
            "model": MODEL,
            "messages": messages,
            "max_tokens": max_tokens,
            "response_model": schema,
        }
        if "3-7" in MODEL:
            api_params["thinking"] = {"type": "enabled", "budget_tokens": 30000}
        else:
            api_params["temperature"] = TEMPERATURE

        try:
            resp = asyncio.run(claude.completions.create(**api_params))
            return resp
        except AnthropicError as e:
            print(f"Anthropic API error: {e}", exc_info=True)
            raise print("Anthropic API error", {"error": str(e)}) from e

else:
    print("Unsupported MODEL_FAMILY"); sys.exit(1)


# ──────────────────── PHASE-0 ANALYSIS ──────────────────────────

# 1) Project context only
print("🔍 Generating project context…")
messages = [
    {"role": "system", "content": SYSTEM_PROMPT},
    {"role": "user",   "content": FULL_INPUT},
]
project_context: ProjectContext = llm_call(messages, ProjectContext)

# 2) Contract summaries only
print("🔍 Generating contract context…")
contracts_out: ContractsContext = llm_call(messages, ContractsContext)
analyzed_contracts = contracts_out.analyzed_contracts

# 3) Pack into final schema and save
final = ContextSummaryOutput(
    project_context=project_context,
    analyzed_contracts=ContractsContext(analyzed_contracts=analyzed_contracts)
)
outdir = pathlib.Path(OUTPUT_DIR_PHASE0)
outdir.mkdir(parents=True, exist_ok=True)
ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
outfile = outdir / f"phase0_{MODEL}_{ts}.json"
outfile.write_text(final.model_dump_json(indent=2))

print(f"✅ Phase-0 complete – {len(analyzed_contracts)} contracts saved to {outfile}")