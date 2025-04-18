import time
from embedding.embedder import get_embedding

def query_chunks(query_text, lance_collection, top_k=5):
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

def iterative_retrieval(vulnerability_query, lance_collection, max_iterations=3):
    """
    Iteratively query the index until retrieval is comprehensive.
    This function prints the results of each iteration.
    """
    all_retrieved = []
    for i in range(max_iterations):
        query = vulnerability_query + f" (iteration {i+1})"
        print(f"Iteration {i+1}: querying with: {query}")
        results = query_chunks(query, lance_collection, top_k=3)
        for r in results:
            if r not in all_retrieved:
                all_retrieved.append(r)
        # Print out the retrieved document IDs and scores for this iteration.
        print(f"Iteration {i+1} results:")
        for r in results:
            print(f"  DocID: {r['doc_id']} - Score: {r['score']:.3f}")
        time.sleep(0.5)
    return all_retrieved
