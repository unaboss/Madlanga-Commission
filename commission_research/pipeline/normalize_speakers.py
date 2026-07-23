"""
normalize_speakers.py — Map transcript speaker-label variants to canonical names.

Reads transcripts.jsonl, applies normalization rules, writes back with
a `speaker_canonical` field.
"""

import json
import re
from pathlib import Path


DATA_DIR   = Path(__file__).resolve().parent.parent / "data"
INPUT_FILE  = DATA_DIR / "parsed" / "transcripts.jsonl"
OUTPUT_FILE = DATA_DIR / "parsed" / "transcripts_normalized.jsonl"


# ── Normalization rules ─────────────────────────────────────────────
# Each entry: (regex_pattern, canonical_name, role)
#   role: "commissioner" | "evidence_leader" | "witness" | "witness_protected" | "other"
#   Patterns are checked in order; first match wins.

ROLE_RULES = [
    # Commissioners
    (r"^CHAIRPERSON$",                             "Justice Mbuyiseli Madlanga", "commissioner"),
    (r"^COMMISSIONER\s+MKHWANAZI$",                 "Adv Mkhwanazi SC",          "commissioner"),
    (r"^COMMISSIONER\s+SPIES$",                     "Commissioner Spies",        "commissioner"),
    (r"^COMMISSIONER\s+BOLHUIS$",                   "Commissioner Bolhuis",      "commissioner"),
    (r"^COMMISSIONER\s+FARO$",                      "Commissioner Faro",         "commissioner"),

    # Evidence leaders (lawyers presenting evidence)
    (r"^ADV\s+SELLO\b.*",                           "Adv Sello SC",              "evidence_leader"),
    (r"^ADV\s+KHUMALO\b.*",                         "Adv Khumalo SC",            "evidence_leader"),
    (r"^ADV\s+CHASKALSON\b.*",                      "Adv Chaskalson SC",         "evidence_leader"),
    (r"^ADV\s+BALOYI[\-\s]?MERE\b.*",               "Adv Baloyi-Mere SC",        "evidence_leader"),
    (r"^ADV\s+BALOYI\b.*",                          "Adv Baloyi SC",             "evidence_leader"),
    (r"^ADV\s+HASSIM\b.*",                          "Adv Hassim SC",             "evidence_leader"),
    (r"^ADV\s+(LEE\s+)?SEGEELS.NCUBE\b.*",          "Adv Segeels-Ncube",         "evidence_leader"),
    (r"^MS\s+SEGEELS.NCUBE\b.*",                    "Adv Segeels-Ncube",         "evidence_leader"),
    (r"^ADV\s+POOE\b.*",                            "Adv Pooe",                  "evidence_leader"),
    (r"^ADV\s+MOSIKILI\b.*",                        "Adv Mosikili",              "evidence_leader"),
    (r"^ADV\s+SIKHAKHANE\b.*",                      "Adv Sikhakhane",            "evidence_leader"),
    (r"^ADV\s+MOTLHASEDI\b.*",                      "Adv Motlhasedi",            "evidence_leader"),
    (r"^ADV\s+MOHLASEDI\b.*",                       "Adv Motlhasedi",            "evidence_leader"),
    (r"^ADV\s+MOTAU\b.*",                           "Adv Motau SC",              "evidence_leader"),
    (r"^ADV\s+PREMHID\b.*",                         "Adv Premhid",               "evidence_leader"),
    (r"^ADV\s+JOHNSON\b.*",                         "Adv Johnson",               "evidence_leader"),
    (r"^ADV\s+BEHARI\b.*",                          "Adv Behari",                "evidence_leader"),
    (r"^ADV\s+HARRISON\b.*",                        "Adv Harrison",              "evidence_leader"),
    (r"^ADV\s+MPOFU\b.*",                           "Adv Mpofu SC",              "evidence_leader"),
    (r"^ADV\s+MOHOMANE\b.*",                        "Adv Mohomane",              "evidence_leader"),
    (r"^ADV\s+VAN\s+DEN\s+HEEVER\b.*",              "Adv van den Heever",        "other"),
    (r"^ADV\s+NGCUKAITOBI\b.*",                     "Adv Ngcukaitobi SC",        "evidence_leader"),

    # Military / Police witnesses (standardize rank abbreviations)
    (r"^LT.?GEN(?:ERAL)?\s+MKHWANAZI\b.*",          "Lt Gen Nhlanhla Mkhwanazi",  "witness"),
    (r"^LT.?GEN(?:ERAL)?\s+SIBIYA\b.*",             "Lt Gen Sibiya",              "witness"),
    (r"^LT.?GEN(?:ERAL)?\s+SHIBIRI\b.*",            "Lt Gen Shibiri",             "witness"),
    (r"^LT.?GEN(?:ERAL)?\s+KHUMALO\b.*",            "Lt Gen Khumalo",             "witness"),
    (r"^LT.?GEN(?:ERAL)?\s+MASEMOLA\b.*",           "Lt Gen Masemola",            "witness"),
    (r"^LT.?GEN(?:ERAL)?\s+SENTHUMULE\b.*",         "Lt Gen Senthumule",          "witness"),
    (r"^LT.?GEN(?:ERAL)?\s+MBOTHO\b.*",             "Lt Gen Mbotho",              "witness"),
    (r"^MAJ.?GEN(?:ERAL)?\s+SENONA\b.*",            "Maj Gen Senona",             "witness"),
    (r"^MAJ.?GEN(?:ERAL)?\s+FLYNN\b.*",             "Maj Gen Flynn",              "witness"),
    (r"^MAJ.?GEN(?:ERAL)?\s+SHIBIRI\b.*",           "Lt Gen Shibiri",             "witness"),
    (r"^MAJ.?GEN(?:ERAL)?\s+MOTSEPE\b.*",           "Maj Gen Motsepe",            "witness"),
    (r"^MAJ.?GEN(?:ERAL)?\s+GOPAUL\b.*",            "Maj Gen Gopaul",             "witness"),
    (r"^BRIG(?:ADIER)?\s+MATJENG\b.*",              "Brigadier Matjeng",          "witness"),
    (r"^BRIG(?:ADIER)?\s+NYUSWA\b.*",               "Brigadier Nyuswa",           "witness"),
    (r"^BRIG(?:ADIER)?\s+NKHWASHU\b.*",             "Brigadier Nkhwashu",         "witness"),
    (r"^BRIG(?:ADIER)?\s+MKHABELA\b.*",             "Brigadier Mkhabhela",        "witness"),
    (r"^BRIG(?:ADIER)?\s+MOKOENA\b.*",              "Brigadier Mokoena",          "witness"),
    (r"^COLONEL\s+JACOB\b.*",                       "Colonel Jacob",              "witness"),
    (r"^COLONEL\s+PADAYACHEE\b.*",                  "Colonel Padayachee",         "witness"),
    (r"^COLONEL\s+STEYN\b.*",                       "Colonel Steyn",              "witness"),
    (r"^LT.?COL(?:ONEL)?\s+SEBOLA\b.*",             "Lt Col Sebola",              "witness"),
    (r"^LT.?COL(?:ONEL)?\s+SIBIYA\b.*",             "Lt Col Sibiya",              "witness"),
    (r"^LT.?COL(?:ONEL)?\s+PRINSLOO\b.*",           "Lt Col Prinsloo",            "witness"),
    (r"^LT.?COL(?:ONEL)?\s+DUMA\b.*",               "Lt Col Duma",                "witness"),
    (r"^LT.?COL(?:ONEL)?\s+KHUMALO\b.*",            "Lt Col Khumalo",             "witness"),
    (r"^LT.?COL(?:ONEL)?\s+THEPA\b.*",              "Lt Col Thepa",               "witness"),
    (r"^CAPTAIN\s+KRUGER\b.*",                      "Captain Kruger",             "witness"),
    (r"^CAPTAIN\s+WANDA\b.*",                       "Captain Wanda",              "witness"),
    (r"^CAPTAIN\s+MODISANE\b.*",                    "Captain Modisane",           "witness"),
    (r"^CAPTAIN\s+MKHATSHWA\b.*",                   "Captain Mkhatshwa",          "witness"),
    (r"^CAPTAIN\s+MAKGOTLOE\b.*",                   "Captain Makgotloe",          "witness"),
    (r"^MAJOR\s+PHIRI\b.*",                         "Major Phiri",                "witness"),
    (r"^SERGEANT\s+NKOSI\b.*",                      "Sergeant Nkosi",             "witness"),
    (r"^WO(?:FFICER)?\s+SANDER\b.*",                "WO Sander",                  "witness"),
    (r"^WO(?:FFICER)?\s+MAGANE\b.*",                "WO Magane",                  "witness"),
    (r"^WO(?:FFICER)?\s+PHAKULA\b.*",               "WO Phakula",                 "witness"),
    (r"^WO(?:FFICER)?\s+MPANGASE\b.*",              "WO Mpangase",                "witness"),
    (r"^WO(?:FFICER)?\s+NKOSI\b.*",                 "WO Nkosi",                   "witness"),
    (r"^WO(?:FFICER)?\s+SETSHEDI\b.*",              "WO Setshedi",                "witness"),
    (r"^WO(?:FFICER)?\s+RADEBE\b.*",                "WO Radebe",                  "witness"),
    (r"^GENERAL\s+KHUMALO\b.*",                     "Lt Gen Khumalo",             "witness"),

    # Protected witnesses (letter-coded)
    (r"^WITNESS\s+([A-K])\b",                       lambda m: f"Witness {m.group(1)} (protected)", "witness_protected"),

    # Civilians / others
    (r"^MR\s+MNISI\b.*",                            "Mr Mnisi",                   "witness"),
    (r"^MR\s+MOGOTSI\b.*",                          "Mr Mogotsi",                 "witness"),
    (r"^MR\s+NCIZA\b.*",                            "Mr Nciza",                   "witness"),
    (r"^MR\s+NKU\b.*",                              "Mr Nku",                     "witness"),
    (r"^MR\s+CARRIM\b.*",                           "Mr Carrim",                  "witness"),
    (r"^MR\s+MAGAGULA\b.*",                         "Mr Magagula",                "witness"),
    (r"^MR\s+NGOATO\b.*",                           "Mr Ngoato",                  "witness"),
    (r"^MR\s+NKOSI\b.*",                            "Mr Nkosi",                   "witness"),
    (r"^MR\s+SHIRINDZI\b.*",                        "Mr Shirindzi",               "witness"),
    (r"^MR\s+MATLALA\b.*",                          "Mr Matlala",                 "witness"),
    (r"^MR\s+O'?SULLIVAN\b.*",                      "Mr O'Sullivan",              "witness"),
    (r"^MR\s+KEEFELAKAE\b.*",                       "Mr Keefelakae",              "witness"),
    (r"^MS\s+GXASHEKA\b.*",                         "Ms Gxasheka",                "witness"),
    (r"^MS\s+MASUKU\b.*",                           "Ms Masuku",                  "witness"),
    (r"^DR\s+MASHAZI\b.*",                          "Dr Mashazi",                 "witness"),
    (r"^MINISTER\s+MCHUNU\b.*",                     "Minister Mchunu",            "witness"),
    (r"^CHIEF\s+MASHABA\b.*",                       "Chief Mashaba",              "witness"),
    (r"^CHIEF\s+MAPIYEYE\b.*",                      "Chief Mapiyeye",             "witness"),
    (r"^DEPUTY\s+CHIEF\s+DHLAMINI\b.*",             "Deputy Chief Dhlamini",      "witness"),
    (r"^DIRECTOR\s+MALATJI\b.*",                    "Director Malatji",           "witness"),
    (r"^ASSISTANT\s+DIRECTOR\s+MAPHOSHO\b.*",       "Asst Dir Maphosho",          "witness"),
]


def normalize_speaker(raw_speaker: str) -> tuple[str, str]:
    """Return (canonical_name, role) for a raw speaker label."""
    raw = raw_speaker.strip().upper()

    for rule in ROLE_RULES:
        pattern = rule[0]
        match = re.match(pattern, raw, re.IGNORECASE)
        if match:
            canonical = rule[1]
            role = rule[2]
            if callable(canonical):
                canonical = canonical(match)
            return (canonical, role)

    # Unknown speaker — clean up but keep as-is
    clean = re.sub(r"\s+", " ", raw_speaker.strip()).title()
    return (clean, "other")


def normalize_all():
    """Read transcripts.jsonl, normalize speakers, write output."""
    print("Normalizing speakers...")
    if not INPUT_FILE.exists():
        print(f"Input file not found: {INPUT_FILE}")
        print("Run parse_transcripts.py first.")
        return

    seen = set()
    roles_ct = {}
    with open(INPUT_FILE, encoding="utf-8") as fin, \
         open(OUTPUT_FILE, "w", encoding="utf-8") as fout:
        for line in fin:
            line = line.strip()
            if not line:
                continue
            seg = json.loads(line)
            raw = seg["speaker"]
            canonical, role = normalize_speaker(raw)

            seg["speaker_canonical"] = canonical
            seg["speaker_role"] = role

            fout.write(json.dumps(seg, ensure_ascii=False) + "\n")

            if raw not in seen:
                seen.add(raw)
                roles_ct[role] = roles_ct.get(role, 0) + 1

    print(f"  {len(seen)} unique raw speaker labels mapped")
    print(f"  Roles: {dict(roles_ct)}")
    print(f"Output: {OUTPUT_FILE}")


if __name__ == "__main__":
    normalize_all()
