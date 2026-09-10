# AI in Excel - per-user uninstaller, exact owned certificate cleanup only.
$ErrorActionPreference = 'Stop'

function Stop-AIExcelUninstallInstance($InstallDirectory) {
    $exe = Join-Path $InstallDirectory 'AIExcelCustom.exe'
    Get-CimInstance Win32_Process -Filter "Name='AIExcelCustom.exe'" -ErrorAction Stop |
        Where-Object { $_.ExecutablePath -and $_.ExecutablePath -eq $exe } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop }
    Start-Sleep -Milliseconds 500
}

function Remove-AIExcelRegistration($InstallDirectory) {
    $path = 'HKCU:\Software\Microsoft\Office\16.0\WEF\Developer'
    if (Test-Path -LiteralPath $path) {
        Remove-ItemProperty -LiteralPath $path -Name (Join-Path $InstallDirectory 'manifest.xml') -ErrorAction SilentlyContinue
    }
}

function Remove-AIExcelShortcuts($InstallDirectory) {
    $paths = @((Join-Path ([Environment]::GetFolderPath('Desktop')) '启动 AI in Excel.lnk'),
        (Join-Path ([Environment]::GetFolderPath('Programs')) 'AI in Excel\卸载 AI in Excel.lnk'))
    $shell = New-Object -ComObject WScript.Shell
    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path) {
            $shortcut = $shell.CreateShortcut($path)
            if ($shortcut.WorkingDirectory -eq $InstallDirectory) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
        }
    }
    $folder = [IO.Path]::GetDirectoryName($paths[1])
    if ((Test-Path -LiteralPath $folder) -and @(Get-ChildItem -LiteralPath $folder -Force).Count -eq 0) {
        Remove-Item -LiteralPath $folder -ErrorAction Stop
    }
}

function Uninstall-AIExcelPackage {
    [CmdletBinding()]
    param([string]$InstallDirectory)
    $lock = Enter-AIExcelInstallLock
    try { Uninstall-AIExcelPackageCore -InstallDirectory $InstallDirectory }
    finally { Exit-AIExcelInstallLock $lock }
}

function Uninstall-AIExcelPackageCore {
    [CmdletBinding()]
    param([string]$InstallDirectory)
    if ((Test-Path -LiteralPath $InstallDirectory) -and ((Get-Item -LiteralPath $InstallDirectory).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Refusing to uninstall through a reparse point.'
    }
    $thumb = Get-OwnedCertificateThumbprint -CertificateDirectory (Join-Path $InstallDirectory 'certs') -RequireValidEvidence
    $targets = @($thumb, '3A61AA2E3A5C7814A23CC9DE41442046F7C99CEC') | Where-Object { $_ } | Select-Object -Unique
    # If cleanup is denied, keep the files and ownership evidence for a retry.
    Remove-OwnedRootCertificates -Thumbprints $targets
    Stop-AIExcelUninstallInstance -InstallDirectory $InstallDirectory
    Remove-AIExcelRegistration -InstallDirectory $InstallDirectory
    Remove-AIExcelShortcuts -InstallDirectory $InstallDirectory
    if (Test-Path -LiteralPath $InstallDirectory) { Remove-Item -LiteralPath $InstallDirectory -Recurse -Force -ErrorAction Stop }
}

if ($MyInvocation.InvocationName -ne '.') {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    try {
        . (Join-Path $PSScriptRoot 'certificate.ps1')
        Uninstall-AIExcelPackage -InstallDirectory (Join-Path $env:LOCALAPPDATA 'AIExcelCustom')
        [System.Windows.Forms.MessageBox]::Show('AI in Excel 已卸载。', 'AI in Excel') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("卸载未完成，已保留必要文件供重试。`n$($_.Exception.Message)", 'AI in Excel') | Out-Null
        exit 1
    }
}
