@echo off
REM ===============================================
REM   Commission Research Tool — Launch Dashboard
REM ===============================================
set PATH=C:\Program Files\R\R-4.6.1\bin;%PATH%

cd /d "%~dp0app"

echo.
echo   +---------------------------------------+
echo   |  COMMISSION RESEARCH TOOL             |
echo   |  Madlanga Commission of Inquiry       |
echo   +---------------------------------------+
echo.
echo   Database: ..\data\commission_research.db
echo.
echo   Opening dashboard in your browser...
echo   Press Ctrl+C to stop.
echo.

Rscript -e "shiny::runApp(launch.browser=TRUE)"

pause
