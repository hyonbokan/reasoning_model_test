import numpy as np
from numpy import dot
from numpy.linalg import norm

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
        def cosine_sim(a, b):
            return dot(a, b) / (norm(a) * norm(b) + 1e-10)
        
        results = []
        for doc_id, item in self.index.items():
            sim = cosine_sim(np.array(query_embedding), np.array(item["embedding"]))
            results.append((doc_id, sim, item))
        results.sort(key=lambda x: x[1], reverse=True)
        return results[:top_k]
