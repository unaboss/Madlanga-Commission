@echo off
echo Commission Research Dashboard — PDF Auto-Watcher
echo ================================================
echo.
echo This watches all .md files in the project and
echo regenerates PDFs whenever a markdown file changes.
echo.
echo Press Ctrl+C to stop.
echo.
python "%~dp0tools\md_to_pdf_watcher.py" --mode=watch
pause
