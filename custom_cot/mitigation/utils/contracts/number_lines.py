from pathlib import Path

src = Path("Trading.sol").read_text().splitlines()
numbered = [
    f"{str(i+1).rjust(5)} | {line}"  # 1‑based, padded left
    for i, line in enumerate(src)
]
Path("TradingWithLines.sol").write_text("\n".join(numbered))