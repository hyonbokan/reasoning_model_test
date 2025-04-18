import re

def chunk_contract(ast, source_code):
    """
    Traverse the AST (which is a dict with a "functions" key) and extract code chunks.
    Uses regex to search for each function in the source based on its name.
    """
    chunks = []
    if "functions" in ast:
        # Iterate over each function in the AST (values from the dictionary)
        for func_name, func_data in ast["functions"].items():
            # Build a regex to match: "function <func_name>("
            pattern = r"function\s+" + re.escape(func_name) + r"\s*\([^)]*\)"
            match = re.search(pattern, source_code)
            if match:
                start = match.start()
                # Look for the next occurrence of a function declaration after current match.
                next_match = re.search(r"\n\s*function\s+", source_code[start + 1:])
                end = start + next_match.start() if next_match else len(source_code)
                chunk_text = source_code[start:end].strip()
            else:
                chunk_text = ""
            chunks.append({
                "name": func_name,
                "type": "function",
                "chunk_text": chunk_text
            })
    else:
        # Fallback if "functions" key is missing
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
    Generate a global summary/invariant for the repository based on function names.
    """
    functions = list(ast.get("functions", {}).keys())
    if not functions:
        functions = ["function_" + str(i) for i in range(3)]
    summary = "This repository contains the following functions: " + ", ".join(functions)
    return summary
