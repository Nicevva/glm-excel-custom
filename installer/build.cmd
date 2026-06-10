@echo off
REM One-shot build: front-end patch -> icons -> cert -> sea exe -> collect -> iexpress.
setlocal
cd /d "%~dp0\.."

echo [1/7] patch front-end (same-origin proxy)...
python patch.py || goto :err

echo [2/7] build icons + app.ico...
python make-icons.py || goto :err

echo [3/7] generate 10y localhost cert (Windows built-in)...
cd installer
powershell -NoProfile -ExecutionPolicy Bypass -File gen-cert.ps1 || goto :err

echo [4/7] sea-config + build AIExcelCustom.exe...
node gen-sea-config.mjs || goto :err
node --experimental-sea-config build\sea-config.json || goto :err
node -e "require('fs').copyFileSync(process.execPath,'dist/AIExcelCustom.exe')" || goto :err
call npx --yes postject dist\AIExcelCustom.exe NODE_SEA_BLOB build\sea-prep.blob --sentinel-fuse NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2 || goto :err

echo [5/7] render manifest template...
cd ..
powershell -NoProfile -Command "(Get-Content manifest\manifest.xml -Raw) -replace 'localhost:3000','localhost:__PORT__' | Set-Content installer\manifest.template.xml -Encoding UTF8"
cd installer

echo [6/7] collect package files into dist\...
copy /y install.ps1 dist\ >nul
copy /y uninstall.ps1 dist\ >nul
copy /y launch.vbs dist\ >nul
copy /y manifest.template.xml dist\ >nul
copy /y app.ico dist\ >nul
copy /y dist\certs\localhost.pfx dist\ >nul
copy /y dist\certs\localhost.crt dist\ >nul
copy /y dist\certs\cert.thumbprint dist\ >nul
del /q dist\port.txt dist\run.log 2>nul

echo [7/7] iexpress single-exe...
iexpress /N /Q app.sed || goto :err

echo.
echo DONE -^> installer\dist\AI-Excel-Setup.exe
goto :eof
:err
echo BUILD FAILED
exit /b 1
