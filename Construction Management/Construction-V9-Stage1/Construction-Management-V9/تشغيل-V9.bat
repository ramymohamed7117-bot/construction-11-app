@echo off
cd /d "%~dp0"
echo Starting Customer and Projects Registration V9 on http://localhost:8010
start "" http://localhost:8010
py -m http.server 8010
pause
