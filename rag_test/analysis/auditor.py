from openai import OpenAI
import os
from dotenv import load_dotenv
from utils.models import GPT_4o_MINI, o3_mini


load_dotenv(verbose=True)
client = OpenAI()
client.api_key = os.getenv("OPENAI_API_KEY")

def analyze_vulnerabilities(model, retrieved_chunks, global_summary):
    """
    Compose a prompt with the global invariant and retrieved code snippets,
    then call the ChatCompletion API to analyze for vulnerabilities.
    """
    prompt = ("You are a security auditor for Solidity smart contracts. "
              "Given the overall repository summary and the following code snippets, "
              "identify any potential vulnerabilities (e.g., reentrancy, unchecked external calls, "
              "integer overflow, or access control issues) and explain your reasoning.\n\n")
    prompt += "Global Repository Summary:\n" + global_summary + "\n\n"
    prompt += "Code Snippets:\n"
    for idx, chunk in enumerate(retrieved_chunks):
        prompt += f"Snippet {idx+1} (Function: {chunk['metadata']['name']}):\n"
        prompt += chunk["document"] + "\n\n"
    prompt += "Provide a list of identified vulnerabilities with brief explanations."
    
    kwargs = {}
    if "o3-mini" in model:
        kwargs["reasoning_effort"] = "high"
    else:
        kwargs["temperature"] = 0.2

    response = client.chat.completions.create(
        model=model,
        messages=[
            {"role": "system", "content": "You are an expert Solidity security auditor."},
            {"role": "user", "content": prompt}
        ],
        **kwargs
    )
    return str(response.choices[0].message.content)
