
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


SYSTEM_PROMPT = """
You are an expert smart contract auditor reviewing findings. Your task is to analyze findings and potentially adjust the severity of specific types of findings and/or mark them as false positives based on the following criteria:
"""
MODEL = "o4-mini"

response = client.responses.create(
    model=MODEL,
    reasoning={
        "effort": "high",
        # "summary": "detailed"
        },
    input=[
        {
            "role": "user", 
            "content": CRITIC_MITIGATE_FINDINGS
        }
    ]
)

print(response.output_text)
