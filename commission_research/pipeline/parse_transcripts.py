"""
parse_transcripts.py — Parse all transcript .txt files into structured speaker-tagged segments.

Produces: data/parsed/transcripts.jsonl
  Each line: {"day": 2, "date": "2025-09-18", "speaker": "ADV SELLO SC", "text": "...", "page": 3, "line": 50}
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


def parse_transcript(filepath: Path) -> list[dict]:
    """Parse a single transcript .txt file into structured segments."""
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

    segments = []
    current_page = 0
    current_speaker = None
    speaker_buffer = []

    for line_num, raw_line in enumerate(lines, 1):
        line = raw_line.strip()

        # Track page numbers
        pm = PAGE_PATTERN.match(line)
        if pm:
            parts = line.split()
            current_page = int(parts[1])
            continue

        # Skip header/footer lines
        if any(p.match(line) for p in SKIP_PATTERNS):
            continue

        if DATE_HEADER.match(line):
            continue

        if not line:
            # Empty line: flush speaker buffer
            if current_speaker and speaker_buffer:
                full_text = " ".join(speaker_buffer)
                segments.append({
                    "day": day,
                    "date": date_str,
                    "speaker": current_speaker,
                    "text": full_text,
                    "page": current_page,
                    "line": line_num - len(speaker_buffer),
                })
                speaker_buffer = []
            continue

        # Check for speaker label
        sm = SPEAKER_PATTERN.match(line)
        if sm:
            # Flush previous speaker's buffer
            if current_speaker and speaker_buffer:
                full_text = " ".join(speaker_buffer)
                segments.append({
                    "day": day,
                    "date": date_str,
                    "speaker": current_speaker,
                    "text": full_text,
                    "page": current_page,
                    "line": line_num - len(speaker_buffer),
                })
                speaker_buffer = []

            current_speaker = sm.group("speaker").strip()
            speaker_buffer.append(sm.group("text"))
        else:
            # Continuation line for current speaker
            if current_speaker:
                speaker_buffer.append(line)

    # Flush final buffer
    if current_speaker and speaker_buffer:
        full_text = " ".join(speaker_buffer)
        segments.append({
            "day": day,
            "date": date_str,
            "speaker": current_speaker,
            "text": full_text,
            "page": current_page,
            "line": len(lines) - len(speaker_buffer),
        })

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
