import json

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
