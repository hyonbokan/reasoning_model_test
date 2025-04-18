import time
from dotenv import load_dotenv
import os
from openai import OpenAI

load_dotenv(verbose=True)
client = OpenAI()
client.api_key = os.getenv("OPENAI_API_KEY")

def get_embedding(text, model="text-embedding-3-large"):
    """Call OpenAI's API to get the embedding of the text."""
    response = client.embeddings.create(input=[text], model=model)
    embedding = response.data[0].embedding
    return embedding

def index_chunks(chunks, lance_collection):
    """For each code chunk, generate an embedding and add it to the LanceDB index."""
    for idx, chunk in enumerate(chunks):
        embedding = get_embedding(chunk["chunk_text"])
        chunk["embedding"] = embedding
        doc_id = f"{chunk.get('name', 'chunk')}-{idx}"
        metadata = {"name": chunk.get("name"), "type": chunk.get("type")}
        lance_collection.add(doc_id, chunk["chunk_text"], embedding, metadata)
        time.sleep(0.2)  # Pause to avoid hitting rate limits
    print(f"Indexed {len(chunks)} chunks.")
