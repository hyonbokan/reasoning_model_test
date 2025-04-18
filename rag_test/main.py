import time
from preprocessing.loader import load_ast, load_source
from chunking.chunker import chunk_contract, generate_global_invariant
from embedding.embedder import index_chunks
from utils.mock_lancedb import LanceDBCollection
from retrieval.retriever import iterative_retrieval
from analysis.auditor import analyze_vulnerabilities
from report.reporter import generate_report
from utils.models import GPT_4o_MINI, o3_mini

def main():
    # Stage 1: Input & Preprocessing
    ast = load_ast("ast.json")           # your JSON AST file
    source_code = load_source("TestContract.sol")  # your Solidity source file
    model = o3_mini

    # Stage 2: Chunking & Global Invariant Generation
    chunks = chunk_contract(ast, source_code)
    global_summary = generate_global_invariant(ast)
    print("Global Summary:")
    print(global_summary)
    print("\nExtracted Chunks:")
    for chunk in chunks:
        print(f"Function {chunk['name']} (length: {len(chunk['chunk_text'])} chars)")
    
    # Stage 3: Embedding & Indexing
    lance_collection = LanceDBCollection()
    index_chunks(chunks, lance_collection)
    
    # Stage 4: RAG-Based Retrieval & Iterative Analysis
    vulnerability_query = "Identify potential reentrancy vulnerabilities and missing access controls"
    retrieved = iterative_retrieval(vulnerability_query, lance_collection, max_iterations=2)
    
    # Stage 5: LLM-Based Vulnerability Analysis
    analysis_text = analyze_vulnerabilities(model, retrieved, global_summary)
    print("\nLLM Vulnerability Analysis:")
    print(analysis_text)
    
    # Stage 6: Report Generation
    report = generate_report(analysis_text)
    with open(f"vulnerability_audit_report_{model}.md", "w") as f:
        f.write(report)
    print("\nAudit report generated: vulnerability_audit_report.md")

if __name__ == "__main__":
    main()
