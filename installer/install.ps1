# AI in Excel (Custom) - per-user installer (no admin / no UAC).
# MUST be saved as UTF-8 with BOM for Chinese strings to render in PS 5.1.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms | Out-Null

$AppName    = "AIExcelCustom"
$InstallDir = Join-Path $env:LOCALAPPDATA $AppName
$Src        = $PSScriptRoot   # IExpress extracts everything flat here
$Log        = Join-Path $env:TEMP "AIExcelCustom-install.log"

function Show-Msg($text, $title = "AI in Excel 安装") {
  [System.Windows.Forms.MessageBox]::Show($text, $title) | Out-Null
}
function Log($text) {
  ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $text) | Out-File -FilePath $Log -Append -Encoding UTF8
}

try {
  "===== AI in Excel install $(Get-Date) =====" | Out-File -FilePath $Log -Encoding UTF8
  Log ("Src=" + $Src)
  Log ("InstallDir=" + $InstallDir)

  # (1) environment check: Excel present?
  $hasExcel = $false
  try { if ([Type]::GetTypeFromProgID("Excel.Application")) { $hasExcel = $true } } catch {}
  if (-not $hasExcel) {
    $root = Get-ChildItem "HKCU:\Software\Microsoft\Office" -EA SilentlyContinue |
            Where-Object { Test-Path "$($_.PSPath)\Excel" }
    if ($root) { $hasExcel = $true }
  }
  Log ("hasExcel=" + $hasExcel)
  if (-not $hasExcel) { Show-Msg "未检测到 Microsoft Excel。请先安装 Office 桌面版后再运行本安装程序。"; exit 1 }

  # (2) pick a free port 3000..3099
  function Test-Port($p) {
    try {
      $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $p)
      $l.Start(); $l.Stop(); return $true
    } catch { return $false }
  }
  $port = 0
  foreach ($p in 3000..3099) { if (Test-Port $p) { $port = $p; break } }
  Log ("port=" + $port)
  if ($port -eq 0) { Show-Msg "端口 3000-3099 全部被占用，请关闭占用程序后重试。"; exit 1 }

  # (3) copy files
  Log "copying files..."
  # stop any running instance so we can overwrite the exe (upgrade / re-install)
  Get-Process -Name "AIExcelCustom" -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
  Start-Sleep -Milliseconds 700
  Log "stopped running instances (if any)"
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $InstallDir "certs") | Out-Null
  Copy-Item (Join-Path $Src "AIExcelCustom.exe")          $InstallDir -Force
  Copy-Item (Join-Path $Src "launch.vbs")             $InstallDir -Force
  Copy-Item (Join-Path $Src "uninstall.ps1")          $InstallDir -Force
  Copy-Item (Join-Path $Src "manifest.template.xml")  $InstallDir -Force
  Copy-Item (Join-Path $Src "app.ico")            $InstallDir -Force
  Copy-Item (Join-Path $Src "localhost.pfx")          (Join-Path $InstallDir "certs") -Force
  Copy-Item (Join-Path $Src "localhost.crt")          (Join-Path $InstallDir "certs") -Force
  Copy-Item (Join-Path $Src "cert.thumbprint")        (Join-Path $InstallDir "certs") -Force
  Log "files copied"

  # (4) render manifest with chosen port + persist port
  (Get-Content (Join-Path $InstallDir "manifest.template.xml") -Raw) -replace "__PORT__", "$port" |
    Set-Content (Join-Path $InstallDir "manifest.xml") -Encoding UTF8
  Set-Content (Join-Path $InstallDir "port.txt") "$port" -Encoding Ascii -NoNewline
  Log "manifest rendered"

  # (5) install cert into current-user Trusted Root (no admin)
  Import-Certificate -FilePath (Join-Path $InstallDir "certs\localhost.crt") `
    -CertStoreLocation Cert:\CurrentUser\Root | Out-Null
  Log "cert imported into CurrentUser\Root"

  # (6) register sideload (HKCU WEF Developer)
  $manifestPath = Join-Path $InstallDir "manifest.xml"
  $dev = "HKCU:\Software\Microsoft\Office\16.0\WEF\Developer"
  New-Item -Path $dev -Force | Out-Null
  New-ItemProperty -Path $dev -Name $manifestPath -Value $manifestPath -PropertyType String -Force | Out-Null
  Log "sideload registered"

  # (7) desktop shortcut
  $ws = New-Object -ComObject WScript.Shell
  $desktop = [Environment]::GetFolderPath("Desktop")
  $lnk = $ws.CreateShortcut((Join-Path $desktop "启动 AI in Excel.lnk"))
  $lnk.TargetPath       = "$env:WINDIR\System32\wscript.exe"
  $lnk.Arguments        = "`"$InstallDir\launch.vbs`""
  $lnk.WorkingDirectory = $InstallDir
  $lnk.IconLocation     = "$InstallDir\app.ico,0"
  $lnk.Description       = "启动 AI in Excel (Custom)"
  $lnk.Save()

  # start-menu uninstall shortcut
  $startMenu = Join-Path ([Environment]::GetFolderPath("Programs")) "AI in Excel"
  New-Item -ItemType Directory -Force -Path $startMenu | Out-Null
  $ulnk = $ws.CreateShortcut((Join-Path $startMenu "卸载 AI in Excel.lnk"))
  $ulnk.TargetPath       = "powershell.exe"
  $ulnk.Arguments        = "-ExecutionPolicy Bypass -File `"$InstallDir\uninstall.ps1`""
  $ulnk.WorkingDirectory = $InstallDir
  $ulnk.IconLocation     = "$InstallDir\app.ico,0"
  $ulnk.Save()
  Log "shortcuts created"

  Log "DONE OK"
  Show-Msg "✅ 安装完成（端口 $port）！`n`n1) 双击桌面【启动 AI in Excel】`n2) 打开 Excel，在「开始」选项卡找到 AI in Excel`n`n如按钮未出现，请重启 Excel。"
}
catch {
  $detail = ($_ | Out-String)
  Log ("ERROR: " + $detail)
  Show-Msg ("安装失败，已记录日志：`n" + $Log + "`n`n错误：" + $_.Exception.Message + "`n`n位置：" + $_.InvocationInfo.PositionMessage) "AI in Excel 安装出错"
  exit 1
}
