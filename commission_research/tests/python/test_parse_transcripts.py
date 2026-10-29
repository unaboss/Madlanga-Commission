from parse_transcripts import parse_transcript

FOOTER_TRANSCRIPT = """MADLANGA COMMISSION
17 SEPTEMBER 2025 – DAY 1
CHAIRPERSON: Good morning.
ADV SELLO SC: Did Crime Intelligence receive R5 million
from Carnilinx in 2024?

LT GEN MKHWANAZI: Yes, I confirm it.
Page 1 of 2
ADV SELLO SC: Who instructed you?
LT GEN MKHWANAZI: The Minister instructed me
in writing.
Page 2 of 2
"""

HEADER_TRANSCRIPT = """Page 1 of 2
CHAIRPERSON: Good morning.
ADV SELLO SC: First question.
Page 2 of 2
LT GEN KHUMALO: I deny that.
"""


def write(tmp_path, text, name="Day_001_2025-09-17.txt"):
    path = tmp_path / name
    path.write_text(text, encoding="utf-8")
    return path


def test_day_and_date_come_from_filename(tmp_path):
    segs = parse_transcript(write(tmp_path, FOOTER_TRANSCRIPT, "Day_047_2026-02-03.txt"))
    assert {(s["day"], s["date"]) for s in segs} == {(47, "2026-02-03")}


def test_speakers_and_continuation_lines(tmp_path):
    segs = parse_transcript(write(tmp_path, FOOTER_TRANSCRIPT))
    assert [s["speaker"] for s in segs] == [
        "CHAIRPERSON", "ADV SELLO SC", "LT GEN MKHWANAZI", "ADV SELLO SC", "LT GEN MKHWANAZI",
    ]
    assert segs[1]["text"] == "Did Crime Intelligence receive R5 million from Carnilinx in 2024?"


def test_footer_page_markers_close_the_page(tmp_path):
    segs = parse_transcript(write(tmp_path, FOOTER_TRANSCRIPT))
    # Everything before "Page 1 of 2" is on page 1, everything after is page 2
    assert [s["page"] for s in segs] == [1, 1, 1, 2, 2]


def test_line_numbers_restart_on_each_page(tmp_path):
    segs = parse_transcript(write(tmp_path, FOOTER_TRANSCRIPT))
    sello = segs[1]
    assert (sello["line_start"], sello["line_end"]) == (2, 3)
    mkhwanazi_p2 = segs[4]
    assert (mkhwanazi_p2["page"], mkhwanazi_p2["line_start"], mkhwanazi_p2["line_end"]) == (2, 2, 3)


def test_header_page_markers_open_the_page(tmp_path):
    segs = parse_transcript(write(tmp_path, HEADER_TRANSCRIPT))
    assert [(s["page"], s["line_start"]) for s in segs] == [(1, 1), (1, 2), (2, 1)]


def test_segment_crossing_a_page_break(tmp_path):
    text = "Page 1 of 2\nLT GEN KHUMALO: I was not\nPage 2 of 2\ninvolved at all.\n"
    segs = parse_transcript(write(tmp_path, text))
    assert len(segs) == 1
    seg = segs[0]
    assert (seg["page"], seg["line_start"], seg["page_end"], seg["line_end"]) == (1, 1, 2, 1)
    assert seg["text"] == "I was not involved at all."
