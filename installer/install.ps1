# AI in Excel - per-user installation with locally generated HTTPS keys.
$ErrorActionPreference = 'Stop'

function Log($text) {
    ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $text) | Out-File -FilePath $script:LogPath -Append -Encoding UTF8
}

function Stop-AIExcelInstance($InstallDirectory) {
    $exe = Join-Path $InstallDirectory 'AIExcelCustom.exe'
    Get-CimInstance Win32_Process -Filter "Name='AIExcelCustom.exe'" -ErrorAction Stop |
        Where-Object { $_.ExecutablePath -and $_.ExecutablePath -eq $exe } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop }
    Start-Sleep -Milliseconds 500
}

function Get-AIExcelPort($InstallDirectory) {
    $exe = Join-Path $InstallDirectory 'AIExcelCustom.exe'
    $ours = @(Get-CimInstance Win32_Process -Filter "Name='AIExcelCustom.exe'" -ErrorAction Stop |
        Where-Object { $_.ExecutablePath -eq $exe })
    $oldPort = 0
    $portFile = Join-Path $InstallDirectory 'port.txt'
    if (Test-Path -LiteralPath $portFile) { [int]::TryParse([IO.File]::ReadAllText($portFile).Trim(), [ref]$oldPort) | Out-Null }
    $ports = @()
    if ($oldPort -ge 3000 -and $oldPort -le 3099) { $ports += $oldPort }
    $ports += 3000..3099
    foreach ($port in ($ports | Select-Object -Unique)) {
        if ($port -eq $oldPort -and $ours.Count) {
            $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
            if ($listeners.Count -gt 0 -and @($listeners | Where-Object { $_.OwningProcess -notin $ours.ProcessId }).Count -eq 0) { return $port }
        }
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $port)
        try { $listener.Start(); return $port } catch { } finally { $listener.Stop() }
    }
    throw 'Ports 3000-3099 are unavailable. Close the conflicting program and retry.'
}

function Get-AIExcelRegistration($InstallDirectory) {
    $path = 'HKCU:\Software\Microsoft\Office\16.0\WEF\Developer'
    $name = Join-Path $InstallDirectory 'manifest.xml'
    $item = Get-ItemProperty -LiteralPath $path -ErrorAction SilentlyContinue
    $property = if ($null -ne $item) { $item.PSObject.Properties[$name] } else { $null }
    return @{ Exists = ($null -ne $property); Value = $(if ($property) { $property.Value } else { $null }) }
}

function Set-AIExcelRegistration($InstallDirectory) {
    $path = 'HKCU:\Software\Microsoft\Office\16.0\WEF\Developer'
    $name = Join-Path $InstallDirectory 'manifest.xml'
    New-Item -Path $path -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -LiteralPath $path -Name $name -Value $name -PropertyType String -Force -ErrorAction Stop | Out-Null
}

function Restore-AIExcelRegistration($InstallDirectory, $Previous) {
    $path = 'HKCU:\Software\Microsoft\Office\16.0\WEF\Developer'
    $name = Join-Path $InstallDirectory 'manifest.xml'
    if ($Previous.Exists) {
        New-ItemProperty -LiteralPath $path -Name $name -Value $Previous.Value -PropertyType String -Force -ErrorAction Stop | Out-Null
    } elseif (Test-Path -LiteralPath $path) {
        Remove-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue
    }
}

function Get-AIExcelShortcutPaths {
    return @((Join-Path ([Environment]::GetFolderPath('Desktop')) '启动 AI in Excel.lnk'),
        (Join-Path ([Environment]::GetFolderPath('Programs')) 'AI in Excel\卸载 AI in Excel.lnk'))
}

function Save-AIExcelShortcuts($InstallDirectory) {
    $paths = @(Get-AIExcelShortcutPaths)
    $shell = New-Object -ComObject WScript.Shell
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($paths[1])) -Force | Out-Null
    $launch = $shell.CreateShortcut($paths[0])
    $launch.TargetPath = "$env:WINDIR\System32\wscript.exe"
    $launch.Arguments = '"' + (Join-Path $InstallDirectory 'launch.vbs') + '"'
    $launch.WorkingDirectory = $InstallDirectory
    $launch.IconLocation = (Join-Path $InstallDirectory 'app.ico') + ',0'
    $launch.Description = '启动 AI in Excel (Custom)'
    $launch.Save()
    $uninstall = $shell.CreateShortcut($paths[1])
    $uninstall.TargetPath = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $uninstall.Arguments = '-ExecutionPolicy Bypass -File "' + (Join-Path $InstallDirectory 'uninstall.ps1') + '"'
    $uninstall.WorkingDirectory = $InstallDirectory
    $uninstall.IconLocation = $launch.IconLocation
    $uninstall.Save()
}

function Install-AIExcelPackage {
    [CmdletBinding()]
    param([string]$SourceDirectory, [string]$InstallDirectory)
    $lock = Enter-AIExcelInstallLock
    try { return Install-AIExcelPackageCore -SourceDirectory $SourceDirectory -InstallDirectory $InstallDirectory }
    finally { Exit-AIExcelInstallLock $lock }
}

function Install-AIExcelPackageCore {
    [CmdletBinding()]
    param([string]$SourceDirectory, [string]$InstallDirectory)
    $files = @('AIExcelCustom.exe', 'launch.vbs', 'uninstall.ps1', 'manifest.template.xml', 'app.ico', 'certificate.ps1')
    foreach ($name in $files) {
        if (-not (Test-Path -LiteralPath (Join-Path $SourceDirectory $name) -PathType Leaf)) { throw "Missing installation input: $name" }
    }
    if ((Test-Path -LiteralPath $InstallDirectory) -and ((Get-Item -LiteralPath $InstallDirectory).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Refusing to replace an installation directory that is a reparse point.'
    }
    $oldThumb = Get-OwnedCertificateThumbprint -CertificateDirectory (Join-Path $InstallDirectory 'certs') -RequireValidEvidence
    $previousRegistration = Get-AIExcelRegistration -InstallDirectory $InstallDirectory
    $shortcuts = @{}
    foreach ($path in @(Get-AIExcelShortcutPaths)) {
        $shortcuts[$path] = if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllBytes($path) } else { $null }
    }
    $port = Get-AIExcelPort -InstallDirectory $InstallDirectory
    $stage = Join-Path ([IO.Path]::GetDirectoryName($InstallDirectory)) ('.AIExcelCustom-install-' + [guid]::NewGuid().ToString('N'))
    $fresh = Join-Path $stage 'app'
    $backup = Join-Path $stage 'previous'
    $newCert = $null
    $trustAttempted = $false
    $oldMoved = $false
    $newMoved = $false
    $registrationAttempted = $false
    $shortcutsAttempted = $false
    $preserveStage = $false
    New-PrivateDirectory -Path $stage
    try {
        New-PrivateDirectory -Path $fresh
        foreach ($name in $files) { Copy-Item -LiteralPath (Join-Path $SourceDirectory $name) -Destination (Join-Path $fresh $name) -ErrorAction Stop }
        $newCert = New-LocalhostCertificate -OutputDirectory (Join-Path $fresh 'certs')
        # Public-only recovery proof survives removal of the newly installed files.
        $proof = Join-Path $stage 'new-trust'
        New-PrivateDirectory -Path $proof
        Copy-Item -LiteralPath $newCert.CertificatePath -Destination (Join-Path $proof 'localhost.crt') -ErrorAction Stop
        [IO.File]::WriteAllText((Join-Path $proof 'cert.thumbprint'), $newCert.Thumbprint, [Text.Encoding]::ASCII)
        $template = [IO.File]::ReadAllText((Join-Path $fresh 'manifest.template.xml'))
        if (-not $template.Contains('__PORT__')) { throw 'Invalid installation manifest template.' }
        [IO.File]::WriteAllText((Join-Path $fresh 'manifest.xml'), $template.Replace('__PORT__', [string]$port), [Text.UTF8Encoding]::new($true))
        [IO.File]::WriteAllText((Join-Path $fresh 'port.txt'), [string]$port, [Text.Encoding]::ASCII)
        # Import only the newly generated public certificate; old trust remains until commit.
        $trustAttempted = $true
        $trusted = @(Import-Certificate -FilePath $newCert.CertificatePath -CertStoreLocation 'Cert:\CurrentUser\Root' -ErrorAction Stop)
        if (@($trusted | Where-Object { $_.Thumbprint -eq $newCert.Thumbprint }).Count -ne 1) { throw 'New certificate trust was not confirmed.' }
        Stop-AIExcelInstance -InstallDirectory $InstallDirectory
        if (Test-Path -LiteralPath $InstallDirectory) {
            Move-Item -LiteralPath $InstallDirectory -Destination $backup -ErrorAction Stop
            $oldMoved = $true
        }
        Move-Item -LiteralPath $fresh -Destination $InstallDirectory -ErrorAction Stop
        $newMoved = $true
        $registrationAttempted = $true
        Set-AIExcelRegistration -InstallDirectory $InstallDirectory
        $shortcutsAttempted = $true
        Save-AIExcelShortcuts -InstallDirectory $InstallDirectory
    } catch {
        $failure = $_
        if ($failure.Exception.Data['CertificateRecoveryDirectory']) {
            $preserveStage = $true
            Write-Warning ('Private-key cleanup requires recovery; preserve ' + $failure.Exception.Data['CertificateRecoveryDirectory'])
        }
        $filesRestored = -not $newMoved
        try {
            if ($newMoved) {
                Stop-AIExcelInstance -InstallDirectory $InstallDirectory
                Remove-Item -LiteralPath $InstallDirectory -Recurse -Force -ErrorAction Stop
                $filesRestored = $true
            }
            if ($oldMoved) { Move-Item -LiteralPath $backup -Destination $InstallDirectory -ErrorAction Stop }
        } catch {
            $preserveStage = $true
            Write-Warning ("File rollback needs manual recovery; backup retained at {0}: {1}" -f $stage, $_.Exception.Message)
        }
        if ($registrationAttempted) {
            try { Restore-AIExcelRegistration -InstallDirectory $InstallDirectory -Previous $previousRegistration }
            catch { $preserveStage = $true; Write-Warning ('Registration rollback failed: ' + $_.Exception.Message) }
        }
        if ($shortcutsAttempted) {
            foreach ($path in $shortcuts.Keys) {
                try {
                    if ($null -eq $shortcuts[$path]) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop } }
                    else { [IO.File]::WriteAllBytes($path, [byte[]]$shortcuts[$path]) }
                } catch { $preserveStage = $true; Write-Warning ('Shortcut rollback failed: ' + $_.Exception.Message) }
            }
        }
        if (-not $filesRestored -and $null -ne $newCert) {
            Write-Warning ('New trust retained because its installation files could not be removed: ' + $newCert.Thumbprint)
        }
        if ($filesRestored -and $trustAttempted -and $null -ne $newCert) {
            try { Remove-OwnedRootCertificates -Thumbprints @($newCert.Thumbprint) }
            catch { $preserveStage = $true; Write-Warning ("Could not retract new certificate {0}: {1}" -f $newCert.Thumbprint, $_.Exception.Message) }
        }
        if (-not $preserveStage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction Stop }
        else {
            $recoveryError = [InvalidOperationException]::new(($failure.Exception.Message + ' Recovery files retained at: ' + $stage), $failure.Exception)
            throw $recoveryError
        }
        throw $failure
    }
    # These are the only historical certificates this installer is allowed to retire.
    $obsolete = @($oldThumb, '3A61AA2E3A5C7814A23CC9DE41442046F7C99CEC') | Where-Object { $_ -and $_ -ne $newCert.Thumbprint }
    $cleanupWarning = $null
    try {
        Remove-OwnedRootCertificates -Thumbprints $obsolete
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction Stop
    } catch {
        $cleanupWarning = "旧证书清理未完成；请保留备份目录 $stage。指纹：$($obsolete -join ', ')。$($_.Exception.Message)"
        Write-Warning $cleanupWarning
    }
    return [pscustomobject]@{ Port = $port; Thumbprint = $newCert.Thumbprint; CleanupWarning = $cleanupWarning }
}

# No certificate-store changes occur until the user runs the installer.
if ($MyInvocation.InvocationName -ne '.') {
    Add-Type -AssemblyName System.Windows.Forms | Out-Null
    $script:LogPath = Join-Path $env:TEMP 'AIExcelCustom-install.log'
    try {
        '===== AI in Excel install =====' | Out-File -FilePath $script:LogPath -Encoding UTF8
        if (-not [Type]::GetTypeFromProgID('Excel.Application')) { throw '未检测到 Microsoft Excel，请先安装 Office 桌面版。' }
        . (Join-Path $PSScriptRoot 'certificate.ps1')
        $result = Install-AIExcelPackage -SourceDirectory $PSScriptRoot -InstallDirectory (Join-Path $env:LOCALAPPDATA 'AIExcelCustom')
        Log ('DONE OK; port=' + $result.Port)
        $message = "安装完成（端口 $($result.Port)）。`n本机已生成独立的 HTTPS 证书。`n`n请双击桌面【启动 AI in Excel】，然后重新打开 Excel。"
        if ($result.CleanupWarning) { $message += "`n`n注意：" + $result.CleanupWarning; Log $result.CleanupWarning }
        [System.Windows.Forms.MessageBox]::Show($message, 'AI in Excel 安装') | Out-Null
    } catch {
        Log ($_ | Out-String)
        [System.Windows.Forms.MessageBox]::Show("安装失败：$($_.Exception.Message)`n日志：$script:LogPath", 'AI in Excel 安装出错') | Out-Null
        exit 1
    }
}
