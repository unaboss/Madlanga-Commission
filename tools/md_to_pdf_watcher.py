"""
md_to_pdf_watcher.py — Auto-convert Markdown files to professionally styled PDFs.

Converts tracked .md → .pdf via pandoc → wkhtmltopdf with a professional
stylesheet (tools/pdf_style.css). Regenerates automatically on file change.

Requirements:
  pip install watchdog
  pandoc.exe — C:\\Users\\mabek\\AppData\\Local\\Pandoc\\pandoc.exe
  wkhtmltopdf.exe — C:\\Program Files\\wkhtmltopdf\\bin\\wkhtmltopdf.exe

Usage:
  python tools/md_to_pdf_watcher.py          # Watch mode (continuous)
  python tools/md_to_pdf_watcher.py --once   # Convert all tracked .md files and exit
  python tools/md_to_pdf_watcher.py --watch  # Same as default (watch mode)
  python tools/md_to_pdf_watcher.py --file path/to/doc.md  # Convert a single file
"""

import os
import sys
import time
import shutil
import subprocess
import tempfile
import argparse
from pathlib import Path
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

PANDOC = Path(r"C:\Users\mabek\AppData\Local\Pandoc\pandoc.exe")
WKPDF = Path(r"C:\Program Files\wkhtmltopdf\bin\wkhtmltopdf.exe")
PROJECT_ROOT = Path(__file__).resolve().parent.parent
STYLE_PATH = PROJECT_ROOT / "tools" / "pdf_style.css"

EXCLUDE_DIRS = {".git", "__pycache__", "node_modules", ".opencode", "dist",
                ".oxlint", "madlanga_downloads", ".~lock.", "openeye-analyst"}

INCLUDE_GLOBS = ("*.md",)

# Extra copy destinations: source (relative to root) -> list of dest dirs
EXTRA_COPIES = {
    "commission_research/research/Student Research Brief - Commission Workflow.md": ["."],
    "business/Business Setup Roadmap.md": ["."],
    "business/Daily Maverick Story Package Pitch.md": ["."],
    "business/Media Collaboration - Video Series & News Partnerships.md": ["."],
    "business/Outreach Tracker - Commission Research Dashboard.md": ["."],
    "business/Commission Research Intelligence Dashboard - Business Pitch.md": ["."],
    "business/Value Analysis - Utility vs Current Cost.md": ["."],
    "business/Investigative Story Package - How It Works.md": ["."],
}

# ── ToC placement marker ────────────────────────────────────
# Pandoc can insert a table of contents via --toc. For docs that
# explicitly need one, add "<!-- toc -->" at the desired location.
TOC_MARKER = "<!-- toc -->"


def convert_md_to_pdf(md_path):
    """Convert a single .md file to PDF via pandoc → wkhtmltopdf."""

    if not md_path.exists():
        print(f"  [SKIP] File not found: {md_path}")
        return False

    pdf_path = md_path.with_suffix(".pdf")
    css_text = STYLE_PATH.read_text(encoding="utf-8") if STYLE_PATH.exists() else ""

    try:
        cmd = [str(PANDOC), str(md_path), "--to", "html5", "--standalone",
               "--metadata", f"title={md_path.stem}", "-o", "-"]

        result = subprocess.run(cmd, check=True, capture_output=True,
                                encoding="utf-8", cwd=str(md_path.parent))
        html = result.stdout

    except subprocess.CalledProcessError as e:
        print(f"  [ERR] {md_path.name}: pandoc failed: {e.stderr[:200]}")
        return False
    except Exception as e:
        print(f"  [ERR] {md_path.name}: {e}")
        return False

    # ── Inject CSS ───────────────────────────────────────────
    if css_text:
        css_tag = f"<style>\n{css_text}\n</style>"
        html = html.replace("</head>", f"{css_tag}\n</head>", 1)

    # ── Write temp HTML to temp dir (avoid spaces in project path) ─
    tmp_name = f"pdf_{md_path.stem.replace(' ', '_')}_{os.getpid()}.html"
    html_path = Path(tempfile.gettempdir()) / tmp_name
    try:
        html_path.write_text(html, encoding="utf-8")
    except Exception as e:
        print(f"  [ERR] {md_path.name}: write temp HTML failed: {e}")
        return False

    # ── Render PDF via wkhtmltopdf ───────────────────────────
    try:
        wk_cmd = [str(WKPDF),
                  "--enable-local-file-access",
                  "--margin-top", "25mm",
                  "--margin-bottom", "30mm",
                  "--margin-left", "22mm",
                  "--margin-right", "22mm",
                  "--footer-center", "— [page] —",
                  "--footer-font-size", "8",
                  str(html_path),
                  str(pdf_path)]

        subprocess.run(wk_cmd, check=True, capture_output=True,
                       timeout=60)
        print(f"  [OK] {md_path.name} -> {pdf_path.name}")
        return True

    except subprocess.TimeoutExpired:
        print(f"  [ERR] {md_path.name}: wkhtmltopdf timed out")
        return False
    except subprocess.CalledProcessError as e:
        print(f"  [ERR] {md_path.name}: wkhtmltopdf failed: {e.stderr[:200] if e.stderr else 'check output'}")
        return False
    except Exception as e:
        print(f"  [ERR] {md_path.name}: PDF render failed: {e}")
        return False
    finally:
        if html_path.exists():
            html_path.unlink()


def handle_extra_copies(md_rel_path):
    """Copy generated PDF to extra locations if configured."""
    pdf_name = Path(md_rel_path).with_suffix(".pdf").name
    for src_pattern, dest_dirs in EXTRA_COPIES.items():
        if md_rel_path == src_pattern.replace("\\", "/"):
            src_pdf = PROJECT_ROOT / Path(md_rel_path).with_suffix(".pdf")
            if not src_pdf.exists():
                continue
            for dest_rel in dest_dirs:
                dest_dir = PROJECT_ROOT / dest_rel
                dest_dir.mkdir(parents=True, exist_ok=True)
                dest_path = dest_dir / pdf_name
                try:
                    shutil.copy2(src_pdf, dest_path)
                    print(f"  [CP] {pdf_name} -> {dest_rel}/")
                except Exception as e:
                    print(f"  [ERR] Copy to {dest_rel}/: {e}")
            break


def find_tracked_md_files():
    """Find all .md files in the project that should be tracked."""
    files = []
    seen_basenames = set()
    for pattern in INCLUDE_GLOBS:
        for md_path in PROJECT_ROOT.rglob(pattern):
            rel = md_path.relative_to(PROJECT_ROOT)
            parts = rel.parts
            if any(p in EXCLUDE_DIRS for p in parts):
                continue
            if len(parts) == 1 and md_path.stem.upper() in ("README", "CHANGELOG", "LICENSE"):
                continue
            if md_path.name.lower() in seen_basenames:
                continue
            seen_basenames.add(md_path.name.lower())
            files.append(md_path)
    return sorted(files)


def convert_all():
    """Convert all tracked .md files to PDF."""
    files = find_tracked_md_files()
    print(f"Converting {len(files)} markdown files...")
    success = 0
    for md_path in files:
        if convert_md_to_pdf(md_path):
            success += 1
        rel = md_path.relative_to(PROJECT_ROOT).as_posix()
        handle_extra_copies(rel)
    print(f"Done. {success}/{len(files)} converted successfully.")
    return success == len(files)


class MdFileHandler(FileSystemEventHandler):
    def on_modified(self, event):
        if event.is_directory:
            return
        src_path = Path(event.src_path)
        if src_path.suffix.lower() != ".md":
            return
        rel = src_path.relative_to(PROJECT_ROOT).as_posix()
        if any(p in EXCLUDE_DIRS for p in src_path.relative_to(PROJECT_ROOT).parts):
            return
        print(f"\n[CHANGE] {rel}")
        if convert_md_to_pdf(src_path):
            handle_extra_copies(rel)


def start_watching():
    """Start the file watcher."""
    observer = Observer()
    handler = MdFileHandler()
    observer.schedule(handler, str(PROJECT_ROOT), recursive=True)
    print(f"Watching for .md changes in: {PROJECT_ROOT}")
    print("Press Ctrl+C to stop.\n")
    observer.start()
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nStopping watcher...")
        observer.stop()
    observer.join()


def main():
    parser = argparse.ArgumentParser(
        description="Auto-convert Markdown files to professionally styled PDFs."
    )
    parser.add_argument("--mode", "-m", choices=["watch", "once"],
                        default="watch",
                        help="watch = continuous monitoring (default), once = convert all and exit")
    parser.add_argument("--file", "-f", type=str, default=None,
                        help="Convert a single file (relative to project root)")

    args = parser.parse_args()

    if not PANDOC.exists():
        print(f"ERROR: Pandoc not found at {PANDOC}")
        print("Install from: https://pandoc.org/installing.html")
        sys.exit(1)

    if args.file:
        md_path = (PROJECT_ROOT / args.file).resolve()
        if not md_path.exists():
            print(f"File not found: {md_path}")
            sys.exit(1)
        print(f"Converting: {md_path.name}")
        convert_md_to_pdf(md_path)
        rel = md_path.relative_to(PROJECT_ROOT).as_posix()
        handle_extra_copies(rel)
        return

    if args.mode == "once":
        convert_all()
    else:
        convert_all()
        print("\n" + "=" * 50)
        start_watching()


if __name__ == "__main__":
    main()
