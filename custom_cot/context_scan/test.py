import json
import pathlib
import datetime
import time
import os
import sys
from dotenv import load_dotenv
from openai import OpenAI
from schema.phase_1_schemas.phase_1_schema_free import FinalAuditReport

# ------------ models & paths -------------------------------------------------
GPT_4O   = "gpt-4o-2024-08-06"
GPT_4_1  = "gpt-4.1-2025-04-14"
O4_MINI  = "o4-mini"
O3 = "o3-2025-04-16"
# ───────────────────────── Configuration ─────────────────────────
MODEL = O3
PROMPT_FILE_SYSTEM = "utils/prompts/munch_org_system_prompt.md"
# INPUT_FILE_FULL_CONTEXT = "utils/inputs/phase0_full_context.md"
PHASE = "org_test_retry"

OUTPUT_DIR_PHASE1 = "logs/test"

try:
    SYSTEM_PROMPT = pathlib.Path(PROMPT_FILE_SYSTEM).read_text()
    if not SYSTEM_PROMPT.strip():
        raise ValueError("System prompt file is empty.")
except Exception as e:
    print(f"Error loading system prompt: {e}")
    print(f"Please ensure the file exists at: {PROMPT_FILE_SYSTEM}")
    sys.exit(1)
    
# ───────────────────────── OpenAI Client ─────────────────────────
load_dotenv()
openai_api_key = os.getenv("OPENAI_API_KEY")
if not openai_api_key:
    print("Error: OPENAI_API_KEY not found in environment variables.")
    exit(1)
client = OpenAI(api_key=openai_api_key)

# ───────────────── Function for Phase 1 Analysis ─────────────────
def perform_phase1_analysis():
    """
    Performs the Phase 1 vulnerability detection using the reasoning model,
    structured context from Phase 0, and raw code.
    """
    print(f"Starting Phase 1 analysis using model: {MODEL}...")
    start_time = time.time()

    # Construct the messages for the API call
    messages = [
        {"role": "user",    "content": SYSTEM_PROMPT},
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
    phase1_result = perform_phase1_analysis()

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