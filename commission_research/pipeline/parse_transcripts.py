"""
parse_transcripts.py — Parse all transcript .txt files into structured speaker-tagged segments.

Produces: data/parsed/transcripts.jsonl
  Each line: {"day": 2, "date": "2025-09-18", "speaker": "ADV SELLO SC", "text": "...",
               "page": 3, "line": 50, "line_start": 10, "page_end": 3, "line_end": 15}
"""

import re
import json
from pathlib import Path


TRANSCRIPTS_DIR = Path(__file__).resolve().parents[2] / "madlanga_downloads" / "transcripts_txt"
OUTPUT_DIR     = Path(__file__).resolve().parent.parent / "data" / "parsed"
OUTPUT_FILE    = OUTPUT_DIR / "transcripts.jsonl"


# Matches:  "SPEAKER NAME IN CAPS: rest of line"
SPEAKER_PATTERN = re.compile(
    r"^(?P<speaker>[A-Z][A-Z\s,\.'\-\(\)\/&]{2,60}?):\s+(?P<text>.+)$"
)

# Matches page markers: "Page X of Y" (standalone line)
PAGE_PATTERN = re.compile(r"^Page\s+\d+\s+of\s+\d+\s*$")

# Matches date headers: "18 SEPTEMBER 2025 – DAY 2"
DATE_HEADER = re.compile(
    r"^\d{1,2}\s+(JANUARY|FEBRUARY|MARCH|APRIL|MAY|JUNE|JULY|"
    r"AUGUST|SEPTEMBER|OCTOBER|NOVEMBER|DECEMBER)\s+\d{4}\s*[–\-]\s*DAY\s+\d+"
)

# Lines to skip entirely
SKIP_PATTERNS = [
    re.compile(r"^MADLANGA COMMISSION", re.IGNORECASE),
    re.compile(r"^JUDICIAL COMMISSION", re.IGNORECASE),
    re.compile(r"^(HELD AT|BRIDGET|BRIGITTE)"),
    re.compile(r"^PROCEEDINGS ON"),
    re.compile(r"^\d+\s+(JANUARY|FEBRUARY|MARCH|APRIL|MAY|JUNE|JULY|"
               r"AUGUST|SEPTEMBER|OCTOBER|NOVEMBER|DECEMBER)\s+\d{4}$"),
]


def _page_markers_are_footers(lines: list[str]) -> bool:
    """True when "Page X of Y" lines close a page (footer) rather than open it.

    If any speaker text appears before the first page marker, the marker
    must be a footer, so the lines after "Page X" belong to page X+1.
    """
    for raw_line in lines:
        line = raw_line.strip()
        if PAGE_PATTERN.match(line):
            return False
        if SPEAKER_PATTERN.match(line):
            return True
    return False


def parse_transcript(filepath: Path) -> list[dict]:
    """Parse a single transcript .txt file into structured segments.

    Each segment carries citation data: the page it starts on ("page"),
    the page it ends on ("page_end"), and the line numbers within those
    pages ("line_start", "line_end"), so it can be cited as
    "Day 47, p.23, lines 10-15". "line" keeps the raw file line number.
    """
    text = filepath.read_text(encoding="utf-8")
    lines = text.split("\n")

    # Extract day number and date from filename: "Day_002_2025-09-18.txt"
    day = 0
    date_str = ""
    fname = filepath.stem  # "Day_002_2025-09-18"
    m = re.match(r"Day_(\d+)_(\d{4}-\d{2}-\d{2})", fname)
    if m:
        day = int(m.group(1))
        date_str = m.group(2)

    footers = _page_markers_are_footers(lines)
    segments = []
    current_page = 1 if footers else 0
    page_line = 0          # content lines seen so far on the current page
    current_speaker = None
    speaker_buffer = []
    seg_start = None       # (file_line, page, page_line) of the buffer's first line
    seg_end = None         # (page, page_line) of the buffer's last line

    def flush():
        nonlocal speaker_buffer, seg_start, seg_end
        if current_speaker and speaker_buffer:
            segments.append({
                "day": day,
                "date": date_str,
                "speaker": current_speaker,
                "text": " ".join(speaker_buffer),
                "page": seg_start[1],
                "line": seg_start[0],
                "line_start": seg_start[2],
                "page_end": seg_end[0],
                "line_end": seg_end[1],
            })
        speaker_buffer = []
        seg_start = None
        seg_end = None

    for line_num, raw_line in enumerate(lines, 1):
        line = raw_line.strip()

        # Track page numbers
        if PAGE_PATTERN.match(line):
            number = int(line.split()[1])
            current_page = number + 1 if footers else number
            page_line = 0
            continue

        # Skip header/footer lines
        if any(p.match(line) for p in SKIP_PATTERNS):
            continue

        if DATE_HEADER.match(line):
            continue

        if not line:
            # Empty line: flush speaker buffer
            flush()
            continue

        page_line += 1
        sm = SPEAKER_PATTERN.match(line)
        if sm:
            # Flush previous speaker's buffer
            flush()
            current_speaker = sm.group("speaker").strip()
            speaker_buffer.append(sm.group("text"))
        elif current_speaker:
            # Continuation line for current speaker
            speaker_buffer.append(line)
        else:
            continue

        if seg_start is None:
            seg_start = (line_num, current_page, page_line)
        seg_end = (current_page, page_line)

    # Flush final buffer
    flush()

    return segments


def parse_all_transcripts():
    """Parse all transcript files and write JSONL output."""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    txt_files = sorted(TRANSCRIPTS_DIR.glob("*.txt"))

    if not txt_files:
        print(f"No transcript .txt files found in {TRANSCRIPTS_DIR}")
        return

    total_segments = 0
    with open(OUTPUT_FILE, "w", encoding="utf-8") as out:
        for i, fp in enumerate(txt_files):
            segments = parse_transcript(fp)
            for seg in segments:
                out.write(json.dumps(seg, ensure_ascii=False) + "\n")
            total_segments += len(segments)
            if (i + 1) % 20 == 0 or i == len(txt_files) - 1:
                print(f"  Parsed {i+1}/{len(txt_files)} transcripts  "
                      f"({total_segments} segments so far)")

    print(f"\nDone. {total_segments} segments from {len(txt_files)} transcripts")
    print(f"Output: {OUTPUT_FILE}")


if __name__ == "__main__":
    parse_all_transcripts()
