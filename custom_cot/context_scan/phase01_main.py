import json
import pathlib
import datetime
import time
import os
from dotenv import load_dotenv
from openai import OpenAI
from schema.phase01_schemas.phase_01_schema_v1 import ContextSummaryOutput
from pydantic import ValidationError

# ------------ models & paths -------------------------------------------------
GPT_4O   = "gpt-4o-2024-08-06"
GPT_4_1  = "gpt-4.1-2025-04-14"
O4_MINI  = "o4-mini"
O3 = "o3-2025-04-16"
# ───────────────────────── Configuration ─────────────────────────
MODEL = O3
PROMPT_FILE_SYSTEM = "utils/prompts/phase01_v1_sys_prompt.py"
INPUT_FILE_FULL_CONTEXT = "utils/inputs/phase0_full_context.md"
PHASE = "phase01_v1"
OUTPUT_DIR_PHASE0 = "logs/phase01_results"

# --- Load prompts and input ---
try:
    SYSTEM_PROMPT_PHASE0 = pathlib.Path(PROMPT_FILE_SYSTEM).read_text()
    FULL_USER_INPUT = pathlib.Path(INPUT_FILE_FULL_CONTEXT).read_text()
except FileNotFoundError as e:
    print(f"Error loading input files: {e}")
    print("Please ensure prompts/system_prompt_phase0.txt and inputs/full_context_and_code.txt exist.")
    exit(1)

# ───────────────────────── OpenAI Client ─────────────────────────
load_dotenv()
openai_api_key = os.getenv("OPENAI_API_KEY")
if not openai_api_key:
    print("Error: OPENAI_API_KEY not found in environment variables.")
    exit(1)
client = OpenAI(api_key=openai_api_key)

# ───────────────── Function for Phase 0 Analysis ─────────────────
def perform_phase0_analysis() -> ContextSummaryOutput | None:
    print(f"Starting {PHASE} analysis using model: {MODEL}...")
    start_time = time.time()

    # Construct the messages for the API call
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT_PHASE0},
        {"role": "user", "content": FULL_USER_INPUT},
    ]

    try:
        completion = client.beta.chat.completions.parse(
            model=MODEL,
            messages=messages,
            response_format=ContextSummaryOutput,
            # temperature=0
        )

        # Access the parsed Pydantic object
        parsed_output: ContextSummaryOutput = completion.choices[0].message.parsed
        analysis_time = time.time() - start_time
        print(f"Phase 0 analysis completed successfully in {analysis_time:.2f} seconds.")
        return parsed_output

    except ValidationError as e:
        print(f"\n--- Pydantic Validation Error ---")
        print(e)
        try:
            # Fallback to standard completion call to get raw text for debugging
            raw_completion = client.chat.completions.create(
                 model=MODEL,
                 messages=messages,
            )
            raw_text = raw_completion.choices[0].message.content
            print("\n--- Raw LLM Output (Failed Validation) ---")
            print(raw_text)
            # Save raw output for debugging
            ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            error_dir = pathlib.Path(OUTPUT_DIR_PHASE0) / "errors"
            error_dir.mkdir(parents=True, exist_ok=True)
            error_file = error_dir / f"phase0_error_{MODEL}_{ts}.txt"
            error_file.write_text(f"Pydantic Validation Error:\n{e}\n\nRaw Output:\n{raw_text}")
            print(f"\nRaw output saved to {error_file}")
        except Exception as raw_e:
            print(f"\nError retrieving raw LLM output: {raw_e}")
        return None

    except Exception as e:
        print(f"\n--- API Call Error ---")
        print(f"An error occurred during the API call: {e}")
        analysis_time = time.time() - start_time
        print(f"Analysis failed after {analysis_time:.2f} seconds.")
        return None

# ───────────────────────── Main Execution ──────────────────────────
if __name__ == "__main__":
    phase0_result = perform_phase0_analysis()

    if phase0_result:
        output_path = pathlib.Path(OUTPUT_DIR_PHASE0)
        output_path.mkdir(parents=True, exist_ok=True)

        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        output_filename = output_path / f"{PHASE}_{MODEL}_{timestamp}.json"

        try:
            with open(output_filename, "w", encoding="utf-8") as f:
                # Use model_dump_json for Pydantic v2+
                f.write(phase0_result.model_dump_json(indent=2))
            print(f"\n✅ Successfully saved {PHASE} output to: {output_filename}")
            print(f"   - Contracts Summarized: {len(phase0_result.analyzed_contracts)}")
            print(f"   - Candidates Identified: {len(phase0_result.seed_findings)}")
        except Exception as e:
            print(f"\nError saving output JSON: {e}")
    else:
        print("\nPhase 0 analysis did not complete successfully. No output saved.")