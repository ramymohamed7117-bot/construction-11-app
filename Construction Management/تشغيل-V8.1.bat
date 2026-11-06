@echo off
cd /d "%~dp0"
echo Starting Construction Management V8.1 on http://localhost:8010
start "" http://localhost:8010
py -m http.server 8010
pause
