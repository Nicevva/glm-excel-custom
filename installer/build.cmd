@echo off
REM Offline public-input build; see build.mjs --help for options.
setlocal
cd /d "%~dp0.." || exit /b 1
node "%~dp0build.mjs" %*
exit /b %errorlevel%
