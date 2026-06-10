# AI in Excel - per-user uninstaller. UTF-8 with BOM.
$ErrorActionPreference = "SilentlyContinue"
Add-Type -AssemblyName System.Windows.Forms | Out-Null

$InstallDir   = Join-Path $env:LOCALAPPDATA "AIExcelCustom"
$manifestPath = Join-Path $InstallDir "manifest.xml"
$thumbFile    = Join-Path $InstallDir "certs\cert.thumbprint"

# (1) remove sideload registry value
$dev = "HKCU:\Software\Microsoft\Office\16.0\WEF\Developer"
Remove-ItemProperty -Path $dev -Name $manifestPath -EA SilentlyContinue

# (2) remove our cert from current-user Trusted Root.
# Prefer exact thumbprint match (recorded at build); fall back to CN=localhost self-signed.
$thumb = $null
if (Test-Path $thumbFile) { $thumb = (Get-Content $thumbFile -Raw).Trim() }
if ($thumb) {
  Remove-Item ("Cert:\CurrentUser\Root\" + $thumb) -Force -EA SilentlyContinue
} else {
  Get-ChildItem Cert:\CurrentUser\Root |
    Where-Object { $_.Subject -eq "CN=localhost" -and $_.Issuer -eq "CN=localhost" } |
    ForEach-Object { Remove-Item $_.PSPath -Force -EA SilentlyContinue }
}

# (3) shortcuts
Remove-Item (Join-Path ([Environment]::GetFolderPath("Desktop")) "启动 AI in Excel.lnk") -Force -EA SilentlyContinue
Remove-Item (Join-Path ([Environment]::GetFolderPath("Programs")) "AI in Excel") -Recurse -Force -EA SilentlyContinue

# (4) files
Remove-Item $InstallDir -Recurse -Force -EA SilentlyContinue

[System.Windows.Forms.MessageBox]::Show("AI in Excel 已卸载。", "AI in Excel") | Out-Null
