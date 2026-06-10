@echo off
REM Starts the local HTTPS server for the custom AI-in-Excel add-in.
REM Keep this window open while you use the add-in in Excel.
cd /d "%~dp0"
echo Starting AI in Excel local server (auto port from port.txt, default 3000) ...
node server.cjs
pause
