"""
parse_statements.py — Extract text from all witness statement / media statement PDFs.

Produces: data/parsed/statements.jsonl
  Each line: {"title": "...", "type": "witness/media/legal/annexure",
              "hearing_day": 3, "date": "2025-09-19", "author": "...",
              "full_text": "...", "file_path": "..."}
"""

import re
import json
from pathlib import Path

import pdfplumber


HEARINGS_DIR  = Path(__file__).resolve().parents[2] / "madlanga_downloads" / "hearings"
OUTPUT_DIR    = Path(__file__).resolve().parent.parent / "data" / "parsed"
OUTPUT_FILE   = OUTPUT_DIR / "statements.jsonl"

# Classify statement by filename patterns
TYPE_PATTERNS = [
    (re.compile(r"(?i)media|spokesperson|press release"), "media_statement"),
    (re.compile(r"(?i)opening address"), "legal_team"),
    (re.compile(r"(?i)witness statement|statement of"), "witness_statement"),
    (re.compile(r"(?i)annexure|bundle|index"), "annexure"),
]


def classify_statement(filename: str) -> str:
    for pat, kind in TYPE_PATTERNS:
        if pat.search(filename):
            return kind
    return "other"


def extract_author(text: str, statement_type: str) -> str:
    """Try to extract author name from statement header."""
    lines = text.split("\n")[:30]
    for i, line in enumerate(lines):
        line = line.strip()
        if not line:
            continue
        # "STATEMENT BY JEREMY MICHAELS, SPOKESPERSON..."
        m = re.search(r"(?:STATEMENT|WITNESS STATEMENT)\s+(?:BY|OF)\s+(.+)", line, re.IGNORECASE)
        if m:
            return m.group(1).strip().rstrip(",")
        # "WITNESS STATEMENT OF\nNHLANHLA SIBUSISO MKHWANAZI"
        if "WITNESS STATEMENT" in line.upper():
            next_line = lines[i + 1].strip() if i + 1 < len(lines) else ""
            if next_line and not next_line.startswith("_"):
                return next_line.strip()
    return ""


def extract_text_from_pdf(pdf_path: Path) -> str:
    """Extract full text from a PDF file."""
    try:
        with pdfplumber.open(pdf_path) as pdf:
            pages = []
            for page in pdf.pages:
                txt = page.extract_text()
                if txt:
                    pages.append(txt)
            return "\n\n".join(pages)
    except Exception as e:
        print(f"    WARNING: Failed to extract {pdf_path.name}: {e}")
        return ""


def parse_all_statements():
    """Extract text from all statement PDFs and write JSONL output."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    pdf_files = sorted(HEARINGS_DIR.glob("**/statement*.pdf"))
    if not pdf_files:
        print(f"No statement PDFs found in {HEARINGS_DIR}")
        return

    print(f"Found {len(pdf_files)} statement PDFs")

    total = 0
    with open(OUTPUT_FILE, "w", encoding="utf-8") as out:
        for i, pdf_path in enumerate(pdf_files):
            day_dir = pdf_path.parent.name  # "Day_003_2025-09-19"
            day_match = re.match(r"Day_(\d+)_(\d{4}-\d{2}-\d{2})", day_dir)
            hearing_day = int(day_match.group(1)) if day_match else 0
            hearing_date = day_match.group(2) if day_match else ""

            stype = classify_statement(pdf_path.name)
            text = extract_text_from_pdf(pdf_path)

            if not text:
                continue

            author = extract_author(text, stype)
            title = pdf_path.stem[:120]

            record = {
                "title": title,
                "type": stype,
                "hearing_day": hearing_day,
                "hearing_date": hearing_date,
                "author": author,
                "full_text": text,
                "file_path": str(pdf_path.relative_to(HEARINGS_DIR.parent)),
            }
            out.write(json.dumps(record, ensure_ascii=False) + "\n")
            total += 1

            chars = len(text)
            print(f"  [{i+1}/{len(pdf_files)}] [{stype:20s}] {pdf_path.name[:60]}... "
                  f"({chars:,} chars)")

    print(f"\nDone. {total} statements extracted.")
    print(f"Output: {OUTPUT_FILE}")


if __name__ == "__main__":
    parse_all_statements()
