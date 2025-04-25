from pathlib import Path
import textwrap

src = Path("contract.sol").read_text().splitlines()
numbered = [
    f"{str(i+1).rjust(5)} | {line}"  # 1‑based, padded left
    for i, line in enumerate(src)
]
Path("contract_with_lines.sol").write_text("\n".join(numbered))