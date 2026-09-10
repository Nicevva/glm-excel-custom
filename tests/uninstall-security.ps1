param([string]$UninstallerPath)
$ErrorActionPreference = 'Stop'
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($UninstallerPath,[ref]$tokens,[ref]$errors)
Assert ($errors.Count -eq 0) 'Uninstaller must parse'
foreach ($f in $ast.FindAll({param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) { . ([ScriptBlock]::Create($f.Extent.Text)) }
Assert ($null -ne (Get-Command Uninstall-AIExcelPackage -ErrorAction SilentlyContinue)) 'Uninstall must validate ownership instead of scanning localhost certificates'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aie-uninstall-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
function Enter-AIExcelInstallLock { return 'test-lock' }
function Exit-AIExcelInstallLock {param($Lock) Assert ($Lock -eq 'test-lock') 'Release uninstall lock'}
$script:thumb=$null; $script:removed=@(); $script:fail=$false
function Get-AIExcelOwnedTrustThumbprint {param($CertificateDirectory) return $script:thumb}
function Remove-OwnedRootCertificates {param($Thumbprints) $script:removed=@($Thumbprints); if ($script:fail) {throw 'injected trust cleanup failure'} }
function Remove-AIExcelRegistration {param($InstallDirectory)}
function Remove-AIExcelShortcuts {param($InstallDirectory)}
function Stop-AIExcelUninstallInstance {param($InstallDirectory)}
$script:StartupRemoved=$false
function Remove-AIExcelAutoStart {param($InstallDirectory) $script:StartupRemoved=$true}
try {
    $dir=Join-Path $temp 'one';New-Item -ItemType Directory -Path $dir | Out-Null
    Uninstall-AIExcelPackage -InstallDirectory $dir
    Assert ($script:removed.Count -eq 1 -and $script:removed[0] -eq '3A61AA2E3A5C7814A23CC9DE41442046F7C99CEC') 'No ownership evidence permits only known shared fingerprint, never a CN scan'
    Assert (-not (Test-Path -LiteralPath $dir)) 'Remove installation on success'
    Assert $script:StartupRemoved 'Uninstall must remove only the application login startup entry'
    $script:thumb='A'*40; $script:fail=$true
    $dir=Join-Path $temp 'two';New-Item -ItemType Directory -Path $dir | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'recovery'), 'keep')
    $failed=$false;try {Uninstall-AIExcelPackage -InstallDirectory $dir} catch {$failed=$true}
    Assert $failed 'Trust cleanup failure cannot report successful uninstall'
    Assert (Test-Path -LiteralPath (Join-Path $dir 'recovery')) 'Retain ownership evidence and uninstaller for retry'
    Assert ($script:removed -contains ('A'*40)) 'Remove matched owned certificate only'
    'UNINSTALL_SECURITY_TESTS_PASSED'
} finally {Remove-Item -LiteralPath $temp -Recurse -Force}
