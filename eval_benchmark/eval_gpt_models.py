from openai import OpenAI
from pydantic import BaseModel, Field
from typing import List, Literal
import pathlib, os
from dotenv import load_dotenv
from prompt.task_prompt import SYSTEM_PROMPT
import json

GPT_4_1 = "gpt-4.1-2025-04-14"
o4_mini = "o4-mini"

# ---------- Pydantic schema for audit findings ----------
class Finding(BaseModel):
    Issue: str = Field(..., description="Short description of the issue")
    Severity: Literal["High", "Medium", "Low", "Info", "Best Practices"]
    Contracts: List[str] = Field(..., description="List of affected contract filenames")
    Ref: List[int] = Field(
        ..., 
        description="Line numbers in the source contract where the issue occurs"
    )
    Description: str = Field(
        ..., 
        description=(
            "Detailed description of the issue, including a markdown-formatted code snippet. "
            "Example:\n```solidity\nfunction vulnerable() { ... }\n```"
        )
    )
    Recommendation: str = Field(..., description="Suggested fix or mitigation")

class AuditResponse(BaseModel):
    findings: List[Finding]

# ---------- Configuration ----------
MODEL = o4_mini
PROMPT_PATH = pathlib.Path("prompts/task_prompt.py")
CONTRACT_PATH = pathlib.Path("tigris_numbered_contracts/Trading.sol")

contract_code = CONTRACT_PATH.read_text()
contract_name = CONTRACT_PATH.stem

# ---------- Initialize OpenAI client ----------
load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

# ---------- Build the chat messages ----------
schema_json = AuditResponse.model_json_schema()
print(json.dumps(schema_json, indent=2)) 

messages = [
    {"role": "system", "content": SYSTEM_PROMPT},
    {"role": "system", "content": f"Use the following JSON schema for structured output, and think step-by-step (chain of thought) before answering:\n{schema_json}"},
    {"role": "user", "content": "Please analyze the Solidity contract below for security vulnerabilities. Output only valid JSON conforming to the schema."},
    {"role": "user", "content": contract_code},
]

# ---------- Send request and parse response ----------
result = client.beta.chat.completions.parse(
    model=MODEL,
    messages=messages,
    response_format=AuditResponse,
)
parsed: AuditResponse = result.choices[0].message

# ---------- Save the audit results ----------
output_json = parsed.model_dump_json(indent=2)
output_path = pathlib.Path("logs")
output_path.mkdir(exist_ok=True)
file_path = output_path / f"audit_findings_{contract_name}_{MODEL}.json"
file_path.write_text(output_json)

print(f"Audit completed. Results saved to: {file_path}")