# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Check that docs/alr-month-precedence.html embeds seeds/mssp_file_parameters.csv.

The page decides which file governs each month from its own copy of the seed
rows, in the <script type="application/json" id="mssp-file-parameters"> block.
This fails (exit 1) when that copy differs from the seed, so the page cannot
drift from the connector.

    uv run --script scripts/check_precedence_doc.py           # check (CI)
    uv run --script scripts/check_precedence_doc.py --write   # rewrite the block from the seed
"""

from __future__ import annotations

import csv
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SEED = REPO_ROOT / "seeds" / "mssp_file_parameters.csv"
PAGE = REPO_ROOT / "docs" / "alr-month-precedence.html"

# Integer columns are embedded as JSON numbers; the rest as strings.
INT_COLUMNS = {"performance_year", "report_year", "priority"}

BLOCK = re.compile(
    r'(<script type="application/json" id="mssp-file-parameters">\n)(.*?)(\n</script>)',
    re.DOTALL,
)


def seed_rows() -> list[dict[str, str]]:
    with SEED.open(newline="") as f:
        return list(csv.DictReader(f))


def render_block(rows: list[dict[str, str]]) -> str:
    def value(column: str, text: str) -> int | str:
        return int(text) if column in INT_COLUMNS else text

    lines = [json.dumps({c: value(c, v) for c, v in row.items()}) for row in rows]
    return "[\n" + ",\n".join(lines) + "\n]"


def main() -> int:
    html = PAGE.read_text()
    blocks = BLOCK.findall(html)
    if len(blocks) != 1:
        print(f"::error file={PAGE.relative_to(REPO_ROOT)}::expected one mssp-file-parameters JSON block, found {len(blocks)}")
        return 1

    rows = seed_rows()
    if "--write" in sys.argv[1:]:
        PAGE.write_text(BLOCK.sub(lambda m: m.group(1) + render_block(rows) + m.group(3), html))
        print(f"Wrote {len(rows)} mssp_file_parameters rows into {PAGE.relative_to(REPO_ROOT)}")
        return 0

    try:
        embedded = json.loads(blocks[0][1])
    except json.JSONDecodeError as e:
        print(f"::error file={PAGE.relative_to(REPO_ROOT)}::mssp-file-parameters block is not valid JSON: {e}")
        return 1

    # Compare as text, column by column, in the seed's row order.
    seed = [dict(row) for row in rows]
    page = [{c: str(v) for c, v in row.items()} for row in embedded]
    if page == seed:
        print(f"OK: {PAGE.relative_to(REPO_ROOT)} embeds all {len(seed)} rows of {SEED.relative_to(REPO_ROOT)}")
        return 0

    print(f"::error file={PAGE.relative_to(REPO_ROOT)}::embedded mssp_file_parameters rows differ from {SEED.relative_to(REPO_ROOT)}")
    for i in range(max(len(seed), len(page))):
        s = seed[i] if i < len(seed) else None
        p = page[i] if i < len(page) else None
        if s != p:
            print(f"  row {i + 1}: seed {s}")
            print(f"  row {i + 1}: page {p}")
    print("Update the page with: uv run --script scripts/check_precedence_doc.py --write")
    return 1


if __name__ == "__main__":
    sys.exit(main())
