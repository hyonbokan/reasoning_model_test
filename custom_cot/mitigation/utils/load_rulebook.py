import re, pathlib

def load_rulebook_md(path="/Users/michaelkan/Desktop/reasoning_model_test/custom_cot/utils/mitigation/mitigation_rulebook_1.md"):
    chunks = {}
    tag = None
    buf = []
    for line in pathlib.Path(path).read_text().splitlines():
        m = re.match(r"#### \[(.+?)\]", line)
        if m:
            if tag: chunks[tag] = "\n".join(buf).strip()
            tag = m.group(1)          # e.g. "overflow"
            buf = [line]              # keep heading in chunk
        elif tag:
            buf.append(line)
    if tag: chunks[tag] = "\n".join(buf).strip()
    return chunks  # {'overflow': '#### [overflow] ...', ...}



def load_rulebook_html(path="/Users/michaelkan/Desktop/reasoning_model_test/custom_cot/utils/mitigation/mitigation_rulebook_1.html"):
    text = pathlib.Path(path).read_text()
    pattern = r"<!-- RULE:(.+?) -->(.*?)<!-- END -->"
    return {tag.strip(): chunk.strip() for tag, chunk in re.findall(pattern, text, flags=re.S)}
