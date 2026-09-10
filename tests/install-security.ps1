param([string]$InstallerPath)
$ErrorActionPreference = 'Stop'
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
# Extract real functions without executing the installer entrypoint or touching stores.
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($InstallerPath, [ref]$tokens, [ref]$errors)
Assert ($errors.Count -eq 0) 'Installer must parse'
$functions = $ast.FindAll({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)
foreach ($f in $functions) { . ([ScriptBlock]::Create($f.Extent.Text)) }
Assert ($null -ne (Get-Command Install-AIExcelPackage -ErrorAction SilentlyContinue)) 'Installer must generate each installation certificate before committing files'
function Enter-AIExcelInstallLock { return 'test-lock' }
function Exit-AIExcelInstallLock { param($Lock) Assert ($Lock -eq 'test-lock') 'Release install lock' }
$script:Imported = @(); $script:Removed = @(); $script:FailRegistration = $false; $script:FailTrust = $false
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path (Split-Path $InstallerPath) 'options.ps1'))))
$script:AutoStart = $false; $script:AutoFail = $false; $script:ExistingSharedTrust = $false
function Get-AIExcelAutoStartState { return @{ Exists=$true; Value=$script:AutoStart; Kind='String' } }
function Set-AIExcelAutoStart { param($InstallDirectory, [bool]$Enabled) $script:AutoStart=$Enabled; if ($script:AutoFail) { throw 'startup write failed' } }
function Restore-AIExcelAutoStartState { param($Previous) $script:AutoStart=$Previous.Value }
function Test-AIExcelRootTrusted { param($Thumbprint) return $script:ExistingSharedTrust }
function New-PrivateDirectory { param($Path) New-Item -ItemType Directory -Path $Path -ErrorAction Stop | Out-Null }
function New-LocalhostCertificate {
    param($OutputDirectory)
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'localhost.pfx'), 'new-local-private')
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'localhost.crt'), 'new-local-public')
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'cert.thumbprint'), ('B' * 40))
    [pscustomobject]@{ Thumbprint = ('B' * 40); CertificatePath = (Join-Path $OutputDirectory 'localhost.crt'); PfxPath = (Join-Path $OutputDirectory 'localhost.pfx') }
}
function Copy-SharedLocalhostCertificate {
    param($SourceDirectory, $OutputDirectory)
    $value = New-LocalhostCertificate -OutputDirectory $OutputDirectory
    [IO.File]::WriteAllText($value.PfxPath, 'shared-explicit-key')
    $script:SharedCopies++
    return $value
}
function Get-OwnedCertificateThumbprint { param($CertificateDirectory) if (Test-Path (Join-Path $CertificateDirectory 'cert.thumbprint')) { return [IO.File]::ReadAllText((Join-Path $CertificateDirectory 'cert.thumbprint')).Trim() }; return $null }
$script:OldTrustOwned = $true; $script:LastRecordedOwnership = $null
function Get-AIExcelOwnedTrustThumbprint { param($CertificateDirectory) if ($script:OldTrustOwned) { return Get-OwnedCertificateThumbprint -CertificateDirectory $CertificateDirectory }; return $null }
function Set-AIExcelTrustOwnership { param($CertificateDirectory, $Thumbprint, [bool]$Owned) $script:LastRecordedOwnership=$Owned }
function Import-Certificate { param($FilePath, $CertStoreLocation, $ErrorAction) Assert ($CertStoreLocation -eq 'Cert:\CurrentUser\Root') 'Only current-user public trust allowed'; $script:Imported += 'B' * 40; if ($script:FailTrust) { throw 'trust refused' }; [pscustomobject]@{ Thumbprint = ('B' * 40) } }
function Remove-OwnedRootCertificates { param($Thumbprints) $script:Removed += $Thumbprints }
function Stop-AIExcelInstance { param($InstallDirectory) }
function Get-AIExcelPort { param($InstallDirectory) return 3010 }
function Get-AIExcelRegistration { param($InstallDirectory) return @{ Exists = $true; Value = 'old-registration' } }
function Set-AIExcelRegistration { param($InstallDirectory) if ($script:FailRegistration) { throw 'registration refused' } }
function Restore-AIExcelRegistration { param($InstallDirectory, $Previous) $script:RegistrationRestored = $true }
function Save-AIExcelShortcuts { param($InstallDirectory) }
function Log { param($text) }
$temp = Join-Path ([IO.Path]::GetTempPath()) ('aie-install-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
function Get-AIExcelShortcutPaths { return @((Join-Path $temp 'desktop.lnk'), (Join-Path $temp 'uninstall.lnk')) }
$source = Join-Path $temp 'source'; New-Item -ItemType Directory -Path $source | Out-Null
foreach ($name in @('AIExcelCustom.exe', 'launch.vbs', 'uninstall.ps1', 'app.ico', 'certificate.ps1', 'startup.ps1', 'options.ps1')) { [IO.File]::WriteAllText((Join-Path $source $name), 'new ' + $name) }
[IO.File]::WriteAllText((Join-Path $source 'manifest.template.xml'), '<OfficeApp><Url>https://localhost:__PORT__/taskpane.html</Url></OfficeApp>')
# A stale packaged private key must never be installed, even if source is polluted.
[IO.File]::WriteAllText((Join-Path $source 'localhost.pfx'), 'SHARED-DO-NOT-INSTALL')
function Seed-Old($dir) {
    New-Item -ItemType Directory -Path (Join-Path $dir 'certs') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'AIExcelCustom.exe'), 'old-exe')
    [IO.File]::WriteAllText((Join-Path $dir 'certs/localhost.pfx'), 'old-private')
    [IO.File]::WriteAllText((Join-Path $dir 'certs/cert.thumbprint'), ('A' * 40))
    [IO.File]::WriteAllText((Join-Path $dir 'port.txt'), '3010')
}
try {
    $dir = Join-Path $temp 'installed'; Seed-Old $dir
    $result = Install-AIExcelPackage -SourceDirectory $source -InstallDirectory $dir
    Assert ([IO.File]::ReadAllText((Join-Path $dir 'certs/localhost.pfx')) -eq 'new-local-private') 'Install must use locally generated private material'
    Assert ([IO.File]::ReadAllText((Join-Path $dir 'AIExcelCustom.exe')) -eq 'new AIExcelCustom.exe') 'New files must be committed'
    Assert ($script:Removed -contains ('A' * 40)) 'Remove verified old certificate after commit'
    Assert ($script:Removed -contains '3A61AA2E3A5C7814A23CC9DE41442046F7C99CEC') 'Rotate the known old shared certificate'
    Assert ($script:Removed -notcontains ('B' * 40)) 'Never remove the newly committed certificate'
    $script:SharedCopies = 0
    foreach ($name in @('shared-localhost.pfx','shared-localhost.crt','shared-cert.thumbprint')) { [IO.File]::WriteAllText((Join-Path $source $name), 'explicit-shared-fixture') }
    $sharedDir = Join-Path $temp 'shared'; Seed-Old $sharedDir
    $failed = $false
    try { Install-AIExcelPackage -SourceDirectory $source -InstallDirectory $sharedDir -CertificateMode shared } catch { $failed = $true }
    Assert ($failed -and $script:SharedCopies -eq 0) 'Shared mode cannot skip explicit consent via backend invocation'
    $result = Install-AIExcelPackage -SourceDirectory $source -InstallDirectory $sharedDir -CertificateMode shared -AcceptSharedRisk $true -AutoStart $true
    Assert ($script:SharedCopies -eq 1 -and $script:AutoStart) 'Explicit shared choice and login startup must be committed'
    $saved = [IO.File]::ReadAllText((Join-Path $sharedDir 'install-options.json')) | ConvertFrom-Json
    Assert ($saved.CertificateMode -eq 'shared' -and $saved.AutoStart -and -not $saved.PSObject.Properties['AcceptSharedRisk']) 'Save mode and startup preference but never shared-risk acceptance'
    $script:ExistingSharedTrust = $true; $script:OldTrustOwned = $false
    $externalDir = Join-Path $temp 'pretrusted-shared'
    Install-AIExcelPackage -SourceDirectory $source -InstallDirectory $externalDir -CertificateMode shared -AcceptSharedRisk $true -AutoStart $false | Out-Null
    Assert ($script:LastRecordedOwnership -eq $false) 'Pre-existing external shared trust must not become installation-owned'
    $script:Removed = @()
    Install-AIExcelPackage -SourceDirectory $source -InstallDirectory $externalDir -AutoStart $false | Out-Null
    Assert ($script:Removed -notcontains ('B' * 40)) 'Switching to independent mode must preserve prior externally-owned trust'
    $script:OldTrustOwned = $true
    $script:AutoFail = $true; $script:AutoStart = $true; $script:ExistingSharedTrust = $true; $script:Removed = @()
    $failed = $false
    try { Install-AIExcelPackage -SourceDirectory $source -InstallDirectory $sharedDir -CertificateMode shared -AcceptSharedRisk $true -AutoStart $false } catch { $failed = $true }
    Assert ($failed -and $script:AutoStart) 'Startup failure must restore the previous startup choice'
    Assert ($script:Removed -notcontains ('B' * 40)) 'Shared upgrade rollback must not revoke already-existing trusted certificate'
    $script:AutoFail = $false; $script:ExistingSharedTrust = $false
    foreach ($case in @('registration', 'trust')) {
        $dir = Join-Path $temp $case; Seed-Old $dir
        $script:Imported = @(); $script:Removed = @(); $script:RegistrationRestored = $false
        $script:FailRegistration = $case -eq 'registration'; $script:FailTrust = $case -eq 'trust'
        $failed = $false
        try { Install-AIExcelPackage -SourceDirectory $source -InstallDirectory $dir } catch { $failed = $true }
        Assert $failed 'Commit failure must propagate'
        Assert ([IO.File]::ReadAllText((Join-Path $dir 'AIExcelCustom.exe')) -eq 'old-exe') 'Failed upgrade must restore old executable'
        Assert ([IO.File]::ReadAllText((Join-Path $dir 'certs/localhost.pfx')) -eq 'old-private') 'Failed upgrade must retain old private key'
        Assert ($script:Removed -notcontains ('A' * 40)) 'Failure must preserve old trusted certificate'
        Assert ($script:Removed -contains ('B' * 40)) 'Failure must retract any partially imported new trust'
        if ($case -eq 'registration') { Assert $script:RegistrationRestored 'Restore registration after a failed commit' }
    }
    # A rollback file lock must not prevent registration/shortcut recovery.
    $script:FailRegistration = $true; $script:FailTrust = $false
    $script:Removed = @(); $script:RegistrationRestored = $false
    $dir = Join-Path $temp 'locked-rollback'; Seed-Old $dir
    $realRemove = 'Microsoft.PowerShell.Management\Remove-Item'
    function Remove-Item { param($LiteralPath, [switch]$Recurse, [switch]$Force, $ErrorAction)
        if ($LiteralPath -eq $dir) { throw 'injected rollback directory lock' }
        & $realRemove -LiteralPath $LiteralPath -Recurse:$Recurse -Force:$Force -ErrorAction Stop
    }
    $failed = $false
    try { Install-AIExcelPackage -SourceDirectory $source -InstallDirectory $dir -WarningAction SilentlyContinue } catch { $failed = $true }
    Assert ($failed -and $script:RegistrationRestored) 'File rollback failure must not skip independent registration recovery'
    Assert ($script:Removed -notcontains ('B' * 40)) 'Do not revoke active new trust if its files cannot be rolled back'
    & $realRemove -LiteralPath Function:\Remove-Item
    $script:FailRegistration = $false
    # If trust rollback fails after deleting the new files, retain public ownership proof.
    function Remove-OwnedRootCertificates { param($Thumbprints) throw 'injected Root removal failure' }
    $script:FailRegistration = $true
    $dir = Join-Path $temp 'root-recovery'; Seed-Old $dir
    $beforeProofs = @(Get-ChildItem -LiteralPath $temp -Filter 'new-trust' -Directory -Recurse | ForEach-Object { $_.FullName })
    try { Install-AIExcelPackage -SourceDirectory $source -InstallDirectory $dir -WarningAction SilentlyContinue } catch { }
    $proofs = @(Get-ChildItem -LiteralPath $temp -Filter 'new-trust' -Directory -Recurse | Where-Object { $_.FullName -notin $beforeProofs })
    Assert ($proofs.Count -eq 1) 'Retain this transaction public ownership proof when Root rollback is denied'
    $proof = $proofs[0].FullName
    Assert ([IO.File]::ReadAllText((Join-Path $proof 'cert.thumbprint')) -eq ('B' * 40)) 'Recovery proof must identify the exact new Root certificate'
    Assert (Test-Path -LiteralPath (Join-Path $proof 'localhost.crt')) 'Keep public CRT proof for retry'
    Assert (-not (Test-Path -LiteralPath (Join-Path $proof 'localhost.pfx'))) 'Trust cleanup evidence must not copy a private key'
    $script:FailRegistration = $false
    # A failed My key cleanup carries recovery metadata through the installer.
    function New-LocalhostCertificate { param($OutputDirectory)
        New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
        [IO.File]::WriteAllText((Join-Path $OutputDirectory 'cert.thumbprint'), ('D' * 40))
        $exception = [InvalidOperationException]::new('injected key cleanup failure')
        $exception.Data['CertificateRecoveryDirectory'] = $OutputDirectory
        $script:RecoveryPath = $OutputDirectory
        throw $exception
    }
    $dir = Join-Path $temp 'key-recovery'; Seed-Old $dir
    try { Install-AIExcelPackage -SourceDirectory $source -InstallDirectory $dir -WarningAction SilentlyContinue } catch { }
    Assert (Test-Path -LiteralPath (Join-Path $script:RecoveryPath 'cert.thumbprint')) 'Installer must not delete a failed My key cleanup record'
    'INSTALL_SECURITY_TESTS_PASSED'
} finally { Microsoft.PowerShell.Management\Remove-Item -LiteralPath $temp -Recurse -Force }
