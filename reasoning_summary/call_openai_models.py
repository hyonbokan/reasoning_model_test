
import os
import json
import datetime
from openai import OpenAI
from dotenv import load_dotenv
from utils.critics_prompt.mitigate_findings import CRITIC_MITIGATE_FINDINGS
from utils.critics_prompt.enrich_findings import CRITIC_ENRICH_FINDINGS

load_dotenv(verbose=True)
client = OpenAI()
client.api_key = os.getenv("OPENAI_API_KEY")

# MODEL = "o4-mini"
MODEL  = "gpt-4.1-2025-04-14"
messages = [
        {"role": "user", "content": f"Detect false positives in the findings below:\n```json\n{CRITIC_MITIGATE_FINDINGS}\n```"},
    ]

response = client.beta.chat.completions.parse(
            model=MODEL,
            messages=messages,
            temperature=0,
            # response_format=FinalAuditReport,
            # reasoning_effort="high", # added
            logprobs=True,
        )

timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
filename = f"response_log_{MODEL}_{timestamp}.json"
log_dir = "logs"
os.makedirs(log_dir, exist_ok=True)

with open(os.path.join(log_dir, filename), "w", encoding="utf-8") as f:
    json.dump(response.model_dump(), f, ensure_ascii=False, indent=2)

print(response)