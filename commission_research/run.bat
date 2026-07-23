@echo off
cd /d "%~dp0"
set PATH=C:\Program Files\R\R-4.6.1\bin;%PATH%
echo.
echo =============================================
echo   Commission Research Tool - Launching...
echo =============================================
echo.
echo   Database: ..\data\commission_research.db
echo.
Rscript -e "shiny::runApp('app', launch.browser=TRUE)"
echo.
pause
