import os
import json
import re
import time
from openai import OpenAI
from dotenv import load_dotenv

# Load environment variables
load_dotenv(verbose=True)
client = OpenAI()
client.api_key = os.getenv("OPENAI_API_KEY")

# Hypothetical LanceDB client (replace with your actual LanceDB client)
class LanceDBCollection:
    def __init__(self):
        self.index = {}
    
    def add(self, doc_id, document, embedding, metadata):
        self.index[doc_id] = {
            "document": document,
            "embedding": embedding,
            "metadata": metadata
        }
    
    def query(self, query_embedding, top_k=3):
        from numpy import dot
        from numpy.linalg import norm
        import numpy as np
        
        def cosine_sim(a, b):
            return dot(a, b) / (norm(a) * norm(b) + 1e-10)
        
        results = []
        for doc_id, item in self.index.items():
            sim = cosine_sim(np.array(query_embedding), np.array(item["embedding"]))
            results.append((doc_id, sim, item))
        results.sort(key=lambda x: x[1], reverse=True)
        return results[:top_k]

# Instantiate a simple in-memory LanceDB collection
lance_collection = LanceDBCollection()

##############################
# Stage 1: Input & Preprocessing
##############################

def load_ast(ast_file_path):
    """Load the JSON AST from file."""
    with open(ast_file_path, "r") as f:
        ast = json.load(f)
    return ast

def load_source(source_file_path):
    """Load the Solidity contract source code."""
    with open(source_file_path, "r") as f:
        code = f.read()
    return code

##############################
# Stage 2: Chunking & Invariant Generation
##############################

def chunk_contract(ast, source_code):
    """
    Traverse the AST and extract code chunks from a Solidity contract.
    
    Since our AST is a dictionary with a 'functions' key mapping function
    names to metadata (without source location), we use a regex search in the
    source code to locate each function declaration.
    """
    chunks = []
    if "functions" in ast:
        # Iterate over each function in the AST (using values from the dictionary)
        for func_name, func_data in ast["functions"].items():
            # Build a regex that matches "function <func_name>(" with optional whitespace.
            # This assumes that function definitions use the keyword 'function'
            pattern = r"function\s+" + re.escape(func_name) + r"\s*\([^)]*\)"
            match = re.search(pattern, source_code)
            if match:
                # Start from the match and extend until we find the start of the next function or end of file.
                start = match.start()
                # Look for the next occurrence of "function " starting after current match
                next_match = re.search(r"\n\s*function\s+", source_code[start + 1:])
                if next_match:
                    end = start + next_match.start()
                else:
                    end = len(source_code)
                chunk_text = source_code[start:end].strip()
            else:
                # Fallback: if no exact match is found, assign an empty chunk.
                chunk_text = ""
            chunks.append({
                "name": func_name,
                "type": "function",
                "chunk_text": chunk_text
            })
    else:
        # Fallback method if 'functions' key is missing:
        lines = source_code.splitlines()
        current_chunk = ""
        current_name = "unknown_function"
        for line in lines:
            if "function " in line:
                if current_chunk:
                    chunks.append({
                        "name": current_name,
                        "type": "function",
                        "chunk_text": current_chunk
                    })
                    current_chunk = ""
                parts = line.split("function ")
                if len(parts) > 1:
                    current_name = parts[1].split("(")[0].strip()
            current_chunk += line + "\n"
        if current_chunk:
            chunks.append({
                "name": current_name,
                "type": "function",
                "chunk_text": current_chunk
            })
    return chunks

def generate_global_invariant(ast):
    """
    Generate a global invariant/summary for the entire codebase.
    For demonstration, we create a summary that lists all function names.
    """
    functions = list(ast.get("functions", {}).keys())
    if not functions:
        functions = ["function_" + str(i) for i in range(3)]
    summary = "This repository contains the following functions: " + ", ".join(functions)
    return summary

##############################
# Stage 3: Embedding & Indexing
##############################

def get_embedding(text, model="text-embedding-3-large"):
    """Call OpenAI's API to get the embedding of the text."""
    response = client.embeddings.create(input=[text], model=model)
    embedding = response.data[0].embedding
    return embedding

def index_chunks(chunks):
    """Generate embeddings for each chunk and index them in LanceDB."""
    for idx, chunk in enumerate(chunks):
        embedding = get_embedding(chunk["chunk_text"])
        chunk["embedding"] = embedding
        doc_id = f"{chunk.get('name', 'chunk')}-{idx}"
        metadata = {
            "name": chunk.get("name"),
            "type": chunk.get("type")
        }
        lance_collection.add(doc_id, chunk["chunk_text"], embedding, metadata)
        time.sleep(0.2)  # Pause to avoid rate limits
    print(f"Indexed {len(chunks)} chunks.")

##############################
# Stage 4: RAG-Based Retrieval & Iterative Analysis
##############################

def query_chunks(query_text, top_k=5):
    """Retrieve code chunks relevant to the query using semantic search."""
    query_embedding = get_embedding(query_text)
    results = lance_collection.query(query_embedding, top_k=top_k)
    retrieved_chunks = []
    for doc_id, score, item in results:
        retrieved_chunks.append({
            "doc_id": doc_id,
            "score": score,
            "document": item["document"],
            "metadata": item["metadata"]
        })
    return retrieved_chunks

def iterative_retrieval(vulnerability_query, max_iterations=3):
    """
    Iteratively query the index until the retrieval seems comprehensive.
    For demonstration, we perform a fixed number of iterations.
    """
    all_retrieved = []
    for i in range(max_iterations):
        query = vulnerability_query + f" (iteration {i+1})"
        results = query_chunks(query, top_k=3)
        for r in results:
            if r not in all_retrieved:
                all_retrieved.append(r)
        time.sleep(0.5)
    return all_retrieved

##############################
# Stage 5: LLM-Based Vulnerability Analysis
##############################

def analyze_vulnerabilities(retrieved_chunks, global_summary):
    """
    Call an LLM to analyze the retrieved code chunks along with the global invariant.
    The prompt is constructed to ask for vulnerability detection.
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
    prompt += "Provide a list of identified vulnerabilities with a brief explanation for each."
    
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[
            {"role": "system", "content": "You are an expert Solidity security auditor."},
            {"role": "user", "content": prompt}
        ],
        temperature=0.2
    )
    analysis = response.choices[0].message.content
    return str(analysis)

##############################
# Stage 6: Report Generation
##############################

def generate_report(analysis_text):
    """
    Format the vulnerability analysis into a structured report.
    For demonstration, return the analysis as a markdown string.
    """
    report = "# Solidity Contract Vulnerability Audit Report\n\n"
    report += analysis_text
    return report

##############################
# Main Execution
##############################

def main():
    # Stage 1: Load input data
    ast = load_ast("ast.json")           # JSON AST file (your provided format)
    source_code = load_source("TestContract.sol")  # Solidity source file

    # Stage 2: Chunking & Global Invariant Generation
    chunks = chunk_contract(ast, source_code)
    global_summary = generate_global_invariant(ast)
    print("Global Summary:\n", global_summary)

    # Stage 3: Embedding & Indexing
    index_chunks(chunks)

    # Stage 4: RAG-Based Retrieval & Iterative Analysis
    vulnerability_query = "Identify potential reentrancy vulnerabilities and missing access controls"
    retrieved = iterative_retrieval(vulnerability_query, max_iterations=2)
    print("Retrieved Chunks:")
    for item in retrieved:
        print(f"DocID: {item['doc_id']} - Score: {item['score']:.3f}")

    # Stage 5: LLM-Based Vulnerability Analysis
    analysis_text = analyze_vulnerabilities(retrieved, global_summary)
    print("LLM Vulnerability Analysis:\n", analysis_text)

    # Stage 6: Report Generation
    report = generate_report(analysis_text)
    with open("vulnerability_audit_report.md", "w") as f:
        f.write(report)
    print("Audit report generated: vulnerability_audit_report.md")

if __name__ == "__main__":
    main()
