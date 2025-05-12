import json
import pathlib
import datetime
import time
import os
import sys
from dotenv import load_dotenv
from openai import OpenAI
from schema.phase_0_schemas.phase_0_schema_v8 import ContextSummaryOutput
from schema.phase_1_schemas.phase_1_schema_free import FinalAuditReport
from pydantic import ValidationError, BaseModel

# ------------ models & paths -------------------------------------------------
GPT_4O   = "gpt-4o-2024-08-06"
GPT_4_1  = "gpt-4.1-2025-04-14"
O4_MINI  = "o4-mini"
O3 = "o3-2025-04-16"
# ───────────────────────── Configuration ─────────────────────────
MODEL = O3
PROMPT_FILE_SYSTEM = "utils/prompts/phase1_free_sys_prompt.py"
# INPUT_FILE_FULL_CONTEXT = "utils/inputs/phase0_full_context.md"
PHASE = "highR_phase0v8_2"

OUTPUT_DIR_PHASE1 = "logs/phase1_results/backd"

# INPUT_PHASE0_OUTPUT_FILE = "logs/phase0_results/tigris/schema_v8/phase0_v8_gpt-4.1_cont10.json"
INPUT_PHASE0_OUTPUT_FILE = "logs/phase0_results/backd/schema_v7/phase0_v7_gpt-4.1-2025-04-14_20250505_130142.json"
# INPUT_PHASE0_OUTPUT_FILE = "logs/phase0_results/munch/schema_v7/phase0_v7_2_gpt-4.1-2025-04-14_20250505_144954.json"
INPUT_RAW_CODE_FILE = "utils/contracts/Backed.sol"
# INPUT_RAW_CODE_FILE = "utils/contracts/Tigris.sol"
# INPUT_RAW_CODE_FILE = "utils/contracts/LandManager.sol"

# --- Load prompts and input ---
try:
    RAW_CONTRACT_CODE = pathlib.Path(INPUT_RAW_CODE_FILE).read_text()
    if not RAW_CONTRACT_CODE.strip():
        raise ValueError("Raw code file is empty.")
except Exception as e:
    print(f"Error loading raw Solidity code: {e}")
    print(f"Please ensure the file exists at: {INPUT_RAW_CODE_FILE}")
    sys.exit(1)

try:
    SYSTEM_PROMPT_PHASE1 = pathlib.Path(PROMPT_FILE_SYSTEM).read_text()
    if not SYSTEM_PROMPT_PHASE1.strip():
        raise ValueError("System prompt file is empty.")
except Exception as e:
    print(f"Error loading system prompt: {e}")
    print(f"Please ensure the file exists at: {PROMPT_FILE_SYSTEM}")
    sys.exit(1)
    
# --- Load Phase 0 Results ---
try:
    with open(INPUT_PHASE0_OUTPUT_FILE, 'r', encoding='utf-8') as f:
        phase0_data = json.load(f)
        # Validate and parse the loaded data using the Phase 0 schema
        phase0_summary: ContextSummaryOutput = ContextSummaryOutput.model_validate(phase0_data)
    print(f"Successfully loaded and validated Phase 0 output from: {INPUT_PHASE0_OUTPUT_FILE}")
except FileNotFoundError:
    print(f"Error: Phase 0 output file not found at {INPUT_PHASE0_OUTPUT_FILE}")
    print("Please ensure the Phase 0 script ran successfully and update the path.")
    sys.exit(1)
except json.JSONDecodeError:
    print(f"Error: Could not decode JSON from {INPUT_PHASE0_OUTPUT_FILE}")
    sys.exit(1)
except ValidationError as e:
    print(f"Error: Phase 0 output file does not match ContextSummaryOutput schema:")
    print(e)
    sys.exit(1)
except Exception as e:
    print(f"An unexpected error occurred loading Phase 0 output: {e}")
    sys.exit(1)
    
# ───────────────────────── OpenAI Client ─────────────────────────
load_dotenv()
openai_api_key = os.getenv("OPENAI_API_KEY")
if not openai_api_key:
    print("Error: OPENAI_API_KEY not found in environment variables.")
    exit(1)
client = OpenAI(api_key=openai_api_key)

# ───────────────── Function for Phase 1 Analysis ─────────────────
def perform_phase1_analysis(
    phase0_context: ContextSummaryOutput,
    raw_code: str
) -> FinalAuditReport | None:
    """
    Performs the Phase 1 vulnerability detection using the reasoning model,
    structured context from Phase 0, and raw code.
    """
    print(f"Starting Phase 1 analysis using model: {MODEL}...")
    start_time = time.time()

    phase0_json = phase0_context.model_dump_json(indent=2)

    # Construct the messages for the API call
    messages = [
        # {"role": "system",    "content": SYSTEM_PROMPT_PHASE1},
        {"role": "system", "content": f"{SYSTEM_PROMPT_PHASE1}\nContextSummaryOutput CONTEXT:\n```json\n{phase0_json}\n```"},
        # {"role": "system", "content": f"{SYSTEM_PROMPT_PHASE1}\nContextSummaryOutput CONTEXT:\n```json\n{phase0_json}\n```\nHere are the Solidity sources:\n```solidity\n{raw_code}\n```"},
        # {"role": "user", "content": f"ContextSummaryOutput CONTEXT:\n```json\n{phase0_json}\n```\nHere are the Solidity sources:\n```solidity\n{raw_code}\n```"},
        # user query with the code base
        {"role": "user", "content": f"Here are the Solidity sources:\n```solidity\n{raw_code}\n```"},
    ]

    try:
        # Use the 'parse' method with the Phase 1 schema
        completion = client.beta.chat.completions.parse(
            model=MODEL,
            messages=messages,
            response_format=FinalAuditReport,
            reasoning_effort="high" # added
        )

        # Access the parsed Pydantic object
        parsed_output: FinalAuditReport = completion.choices[0].message.parsed
        analysis_time = time.time() - start_time
        print(f"Phase 1 analysis completed successfully in {analysis_time:.2f} seconds.")
        return parsed_output

    except Exception as e:
        print(f"\n--- API Call Error (Phase 1) ---")
        print(f"An error occurred during the API call: {e}")
        analysis_time = time.time() - start_time
        print(f"Analysis failed after {analysis_time:.2f} seconds.")
        return None

# ───────────────────────── Main Execution ──────────────────────────
if __name__ == "__main__":
    phase1_result = perform_phase1_analysis(phase0_summary, RAW_CONTRACT_CODE)

    # Save the structured output if successful
    if phase1_result:
        # Create the output directory if it doesn't exist
        output_path = pathlib.Path(OUTPUT_DIR_PHASE1)
        output_path.mkdir(parents=True, exist_ok=True)

        # Generate timestamp for the output file
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        output_filename = output_path / f"{PHASE}_{MODEL}_{timestamp}.json"

        # Save the Pydantic model as JSON
        try:
            with open(output_filename, "w", encoding="utf-8") as f:
                # Use model_dump_json for Pydantic v2+
                f.write(phase1_result.model_dump_json(indent=2))
            print(f"\n✅ Successfully saved Phase 1 output to: {output_filename}")
            print(f"   - Vulnerabilities Detected: {len(phase1_result.results)}")
        except Exception as e:
            print(f"\nError saving Phase 1 output JSON: {e}")
    else:
        print("\nPhase 1 analysis did not complete successfully. No output saved.")