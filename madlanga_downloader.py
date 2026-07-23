#!/usr/bin/env python3
"""
Madlanga Commission Downloader
================================
Downloads all public records from the Judicial Commission of Inquiry into
Criminality, Political Interference and Corruption in the Criminal Justice System
(the Madlanga Commission).

Source: https://criminaljusticecommission.org.za/
Data via: Supabase public REST API (anon key extracted from the public website)

What this downloads:
  - All hearing metadata (144+ hearing days from Sep 2025 - Jul 2026)
  - All hearing materials: transcripts (PDF), statements, audio, video links
  - All documents: rulings, proclamations, applications, media statements (53+ docs)
  - Extracted text from transcript PDFs for analysis

Output structure:
  downloads/
    metadata/          JSON files with all record data
    hearings/          Organized by day with all materials
    documents/         Organized by category (rulings, applications, etc.)
    transcripts_txt/   Plain text extracted from transcript PDFs
"""

import os
import sys
import json
import time
import argparse
from pathlib import Path

# --- Configuration ---
SUPABASE_URL   = "https://kygcssfahsvxmdvynbge.supabase.co"
ANON_KEY       = "sb_publishable_SyZh-y7K_XNAObUzSdLfxg_iAeGEyVq"
REST_URL       = f"{SUPABASE_URL}/rest/v1"
STORAGE_BUCKETS = {"hearing-media", "documents"}

HEADERS = {
    "apikey":        ANON_KEY,
    "Authorization": f"Bearer {ANON_KEY}",
}

# --- Dependency checks ---
try:
    import requests
except ImportError:
    print("ERROR: 'requests' is required. Install with:  pip install requests")
    sys.exit(1)


def get_all_paginated(session, table, select="*", order=None, ascending=True):
    """Fetch all records from a Supabase table using offset pagination."""
    records = []
    offset = 0
    limit  = 1000
    page   = 1

    while True:
        url = f"{REST_URL}/{table}?select={select}&limit={limit}&offset={offset}"
        if order:
            url += f"&order={order}.{'asc' if ascending else 'desc'}"

        resp = session.get(url, timeout=60)
        if resp.status_code != 200:
            print(f"  API error on {table} page {page}: HTTP {resp.status_code}")
            print(f"    {resp.text[:300]}")
            break

        data = resp.json()
        if not data:
            break

        records.extend(data)
        sys.stdout.write(f"\r  {table}: fetched {len(records)} records...")
        sys.stdout.flush()

        if len(data) < limit:
            break
        offset += limit
        page   += 1

    print(f"\r  {table}: {len(records)} records total.   ")
    return records


def create_signed_url(session, bucket, file_path, expires_in=86400):
    """Get a signed download URL from Supabase storage."""
    url = f"{SUPABASE_URL}/storage/v1/object/sign/{bucket}/{file_path}"
    try:
        resp = session.post(url, json={"expiresIn": expires_in}, timeout=30)
    except requests.RequestException:
        return None

    if resp.status_code != 200:
        return None

    try:
        data = resp.json()
        signed = data.get("signedURL", data.get("signedUrl", ""))
        if signed:
            if signed.startswith("http"):
                return signed
            if signed.startswith("/"):
                url = f"{SUPABASE_URL}{signed}"
            else:
                url = f"{SUPABASE_URL}/{signed}"
            # Newer Supabase returns /object/sign/... but the working path
            # is /storage/v1/object/sign/...  Fix if needed.
            if "/storage/v1" not in url:
                url = url.replace("/object/sign/", "/storage/v1/object/sign/")
            return url
    except ValueError:
        pass
    return None


def download_file(session, url, dest, skip_existing=True, max_retries=3, desc=""):
    """Download a file with retry logic."""
    dest = Path(dest)

    if skip_existing and dest.exists() and dest.stat().st_size > 0:
        print(f"    [skip] already exists: {desc}")
        return True

    dest.parent.mkdir(parents=True, exist_ok=True)

    for attempt in range(1, max_retries + 1):
        try:
            resp = session.get(url, timeout=300)
            if resp.status_code == 200:
                dest.write_bytes(resp.content)
                mb = len(resp.content) / (1024 * 1024)
                print(f"    [ok] {desc}  ({mb:.1f} MB)")
                return True
            else:
                print(f"    [HTTP {resp.status_code}] {desc}  (attempt {attempt})")
        except requests.RequestException as e:
            print(f"    [err] {desc}: {e}  (attempt {attempt})")

        if attempt < max_retries:
            time.sleep(2 * attempt)

    return False


def sanitize(s, max_len=90):
    """Remove characters unsafe for filenames."""
    allowed = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-.,()")
    s = "".join(c if c in allowed else "_" for c in s)
    return s[:max_len].strip()


# =============================================================================
#  Download functions
# =============================================================================

def fetch_metadata(session, output_dir):
    """Fetch all metadata records and save as JSON."""
    print("\n" + "="*60)
    print("  STEP 1: Fetching metadata")
    print("="*60)

    meta_dir = output_dir / "metadata"
    meta_dir.mkdir(parents=True, exist_ok=True)

    hearings = get_all_paginated(session, "hearings",
                                 select="*",
                                 order="hearing_date",
                                 ascending=True)
    (meta_dir / "hearings.json").write_text(
        json.dumps(hearings, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    media = get_all_paginated(session, "hearing_media", select="*")
    (meta_dir / "hearing_media.json").write_text(
        json.dumps(media, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    docs = get_all_paginated(session, "documents", select="*")
    (meta_dir / "documents.json").write_text(
        json.dumps(docs, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    return hearings, media, docs


def download_hearing_materials(session, output_dir, hearings, media, kinds, skip_existing):
    """Download all hearing materials organized by day."""
    print("\n" + "="*60)
    print("  STEP 2: Downloading hearing materials")
    print("="*60)

    # Index media by hearing_id
    media_by_hearing = {}
    for m in media:
        hid = m.get("hearing_id", "")
        media_by_hearing.setdefault(hid, []).append(m)

    total = len(hearings)
    success = 0
    failed  = 0
    skipped = 0

    for i, hearing in enumerate(hearings):
        hid  = hearing["id"]
        day  = hearing.get("day_number", 0)
        date = (hearing.get("hearing_date") or "unknown")[:10]

        dir_name = f"Day_{int(day):03d}_{date}"
        day_dir  = output_dir / "hearings" / dir_name
        prefix   = f"[{i+1:03d}/{total}]"

        sys.stdout.write(f"\r{prefix} {dir_name}...")
        sys.stdout.flush()

        items = media_by_hearing.get(hid, [])

        if not items:
            sys.stdout.write(f"\r{prefix} {dir_name}  (no materials available)\n")
            continue

        sys.stdout.write(f"\r{prefix} {dir_name}  ({len(items)} materials)\n")

        for m in items:
            kind = m.get("kind", "other")
            if kinds and kind not in kinds:
                continue

            title       = m.get("title", "untitled")
            file_path   = m.get("file_path")
            external_url = m.get("external_url")

            if external_url:
                note_path = day_dir / f"{kind}_external_link.txt"
                note_path.parent.mkdir(parents=True, exist_ok=True)
                note_path.write_text(
                    f"Title: {title}\nKind: {kind}\nURL: {external_url}\n",
                    encoding="utf-8"
                )
                print(f"    [link] {kind}: {title}  -> {external_url}")
                skipped += 1
                continue

            if not file_path:
                continue

            ext  = file_path.rsplit(".", 1)[-1] if "." in file_path else "bin"
            name = sanitize(f"{kind}_{title}")
            dest = day_dir / f"{name}.{ext}"

            signed = create_signed_url(session, "hearing-media", file_path)
            if signed:
                ok = download_file(session, signed, dest, skip_existing, desc=f"[{kind}] {title}")
                if ok:
                    success += 1
                else:
                    failed += 1
            else:
                print(f"    [err] could not sign URL for: {title}")
                failed += 1

        # Save hearing summary
        info = {
            "day_number":   hearing.get("day_number"),
            "hearing_date": hearing.get("hearing_date"),
            "title":        hearing.get("title") or "",
            "summary":      hearing.get("summary") or "",
            "video_url":    hearing.get("video_url") or "",
        }
        day_dir.mkdir(parents=True, exist_ok=True)
        (day_dir / "info.json").write_text(
            json.dumps(info, indent=2, ensure_ascii=False), encoding="utf-8"
        )

    print(f"\n  Hearing downloads: {success} ok, {failed} failed, {skipped} external links\n")
    return success, failed


def download_documents(session, output_dir, docs, categories, skip_existing):
    """Download all documents (rulings, proclamations, etc.) organized by category."""
    print("\n" + "="*60)
    print("  STEP 3: Downloading documents")
    print("="*60)

    # Count by category
    cat_counts = {}
    for d in docs:
        cat = d.get("category", "other")
        cat_counts[cat] = cat_counts.get(cat, 0) + 1
    print("  Categories:", ", ".join(f"{k} ({v})" for k, v in sorted(cat_counts.items())))

    total   = len(docs)
    success = 0
    failed  = 0

    for i, doc in enumerate(docs):
        cat = doc.get("category", "other")
        if categories and cat not in categories:
            continue

        title        = doc.get("title", "untitled")
        file_path    = doc.get("file_path")
        external_url = doc.get("external_url")
        doc_date     = (doc.get("document_date") or "unknown")[:10]

        prefix = f"[{i+1:03d}/{total}]"

        if external_url:
            note_dir = output_dir / "documents" / cat
            note_dir.mkdir(parents=True, exist_ok=True)
            note_file = note_dir / sanitize(f"{doc_date}_{title}_external.txt")
            note_file.write_text(
                f"Title: {title}\nCategory: {cat}\nDate: {doc_date}\nURL: {external_url}\n",
                encoding="utf-8"
            )
            print(f"{prefix} [link] [{cat}] {title}")
            continue

        if not file_path:
            continue

        ext  = file_path.rsplit(".", 1)[-1] if "." in file_path else "bin"
        name = sanitize(f"{doc_date}_{title}")
        dest = output_dir / "documents" / cat / f"{name}.{ext}"
        dest.parent.mkdir(parents=True, exist_ok=True)

        signed = create_signed_url(session, "documents", file_path)
        if signed:
            ok = download_file(session, signed, dest, skip_existing, desc=f"[{cat}] {title}")
            if ok:
                success += 1
            else:
                failed += 1
        else:
            print(f"{prefix} [err] [{cat}] could not sign URL: {title}")
            failed += 1

    print(f"\n  Document downloads: {success} ok, {failed} failed\n")
    return success, failed


def extract_transcript_texts(output_dir):
    """Extract plain text from all downloaded transcript PDFs."""
    print("\n" + "="*60)
    print("  STEP 4: Extracting text from transcript PDFs")
    print("="*60)

    try:
        import pdfplumber
    except ImportError:
        print("  pdfplumber not installed. Install with: pip install pdfplumber")
        print("  Skipping text extraction.")
        return

    hearings_dir = output_dir / "hearings"
    if not hearings_dir.exists():
        print("  No hearings directory found. Run download first.")
        return

    txt_dir = output_dir / "transcripts_txt"
    txt_dir.mkdir(parents=True, exist_ok=True)

    patterns = ["transcript*.pdf", "audio_transcript*.pdf"]
    transcript_files = []
    for pat in patterns:
        transcript_files.extend(hearings_dir.glob(f"**/{pat}"))

    if not transcript_files:
        print("  No transcript PDFs found.")
        return

    total   = len(transcript_files)
    success = 0

    for i, pdf_path in enumerate(transcript_files):
        day_dir = pdf_path.parent.name
        txt_path = txt_dir / f"{day_dir}.txt"

        if txt_path.exists() and txt_path.stat().st_size > 100:
            print(f"  [{i+1}/{total}] Already exists: {day_dir}")
            success += 1
            continue

        try:
            with pdfplumber.open(pdf_path) as pdf:
                pages = []
                for page in pdf.pages:
                    text = page.extract_text()
                    if text:
                        pages.append(text)
                full_text = "\n\n".join(pages)
            txt_path.write_text(full_text, encoding="utf-8")
            lines = full_text.count("\n") + 1
            print(f"  [{i+1}/{total}] Extracted: {day_dir}  ({lines} lines)")
            success += 1
        except Exception as e:
            print(f"  [{i+1}/{total}] Failed: {day_dir}  ({e})")

    print(f"\n  Text extraction: {success}/{total} succeeded\n")


# =============================================================================
#  Main
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Madlanga Commission Public Records Downloader",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python madlanga_downloader.py                           # Download transcripts, statements, docs (skips audio)
  python madlanga_downloader.py --include-audio           # Also download audio recordings
  python madlanga_downloader.py --metadata-only           # Only save metadata JSON
  python madlanga_downloader.py --kinds transcript        # Only download transcripts
  python madlanga_downloader.py --kinds transcript statement  # Transcripts + statements
  python madlanga_downloader.py --categories ruling       # Only download rulings
  python madlanga_downloader.py --skip-hearings           # Skip hearings, get docs only
  python madlanga_downloader.py --skip-documents          # Skip documents, get hearings only
  python madlanga_downloader.py --no-extract              # Don't extract text from PDFs
  python madlanga_downloader.py --overwrite               # Re-download existing files
  python madlanga_downloader.py -o ./my_output_dir        # Custom output directory
        """
    )

    parser.add_argument(
        "-o", "--output", default="./madlanga_downloads",
        help="Output directory (default: ./madlanga_downloads)"
    )
    parser.add_argument(
        "--metadata-only", action="store_true",
        help="Only fetch and save metadata JSON (no file downloads)"
    )
    parser.add_argument(
        "--skip-hearings", action="store_true",
        help="Skip downloading hearing materials"
    )
    parser.add_argument(
        "--skip-documents", action="store_true",
        help="Skip downloading documents/rulings"
    )
    parser.add_argument(
        "--no-extract", action="store_true",
        help="Skip extracting text from PDF transcripts"
    )
    parser.add_argument(
        "--overwrite", action="store_true",
        help="Overwrite existing files instead of skipping them"
    )
    parser.add_argument(
        "--kinds", nargs="+",
        choices=["transcript", "audio", "video", "statement", "image"],
        help="Only download specific hearing media kinds "
             "(default: transcript, statement, image, video - audio excluded)"
    )
    parser.add_argument(
        "--include-audio", action="store_true",
        help="Also download audio recordings (they are recordings of hearings, "
             "same content as transcripts -- excluded by default)"
    )
    parser.add_argument(
        "--categories", nargs="+",
        choices=["ruling", "application", "media", "media_statement", "statement"],
        help="Only download specific document categories (default: all)"
    )

    args = parser.parse_args()

    output_dir = Path(args.output).resolve()

    print("=" * 60)
    print("  MADLANGA COMMISSION PUBLIC RECORDS DOWNLOADER")
    print("=" * 60)
    print(f"  Output directory: {output_dir}")
    print(f"  Overwrite files:  {'yes' if args.overwrite else 'no (skip existing)'}")

    # Determine which hearing media kinds to download
    if args.kinds:
        kinds = set(args.kinds)
    else:
        kinds = {"transcript", "statement", "video", "image"}
        if args.include_audio:
            kinds.add("audio")
    print(f"  Hearing media:    {', '.join(sorted(kinds))}")

    if args.categories:
        print(f"  Doc categories:   {', '.join(args.categories)}")
    else:
        print(f"  Doc categories:   all categories")

    session = requests.Session()
    session.headers.update(HEADERS)

    # Step 1: Fetch metadata (always done)
    hearings, media, docs = fetch_metadata(session, output_dir)

    if args.metadata_only:
        print("\n  Metadata saved. Use without --metadata-only to download files.")
        print(f"  {output_dir / 'metadata'}")
        return

    # Step 2: Download hearing materials
    if not args.skip_hearings:
        download_hearing_materials(
            session, output_dir, hearings, media,
            kinds=kinds,
            skip_existing=not args.overwrite
        )

    # Step 3: Download documents
    if not args.skip_documents:
        download_documents(
            session, output_dir, docs,
            categories=set(args.categories) if args.categories else None,
            skip_existing=not args.overwrite
        )

    # Step 4: Extract transcript texts
    if not args.no_extract and not args.skip_hearings:
        extract_transcript_texts(output_dir)

    print("=" * 60)
    print(f"  DONE. All files saved to: {output_dir}")
    print("=" * 60)


if __name__ == "__main__":
    main()
