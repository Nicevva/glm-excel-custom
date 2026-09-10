param([string]$HelperPath)
$ErrorActionPreference = 'Stop'
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
. ([ScriptBlock]::Create([IO.File]::ReadAllText($HelperPath)))
$temp = Join-Path ([IO.Path]::GetTempPath()) ('aie-options-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $options = Get-AIExcelInstallOptions -InstallDirectory $temp
    Assert ($options.CertificateMode -eq 'independent' -and -not $options.AutoStart -and -not $options.AcceptSharedRisk) 'Fresh defaults must be independent, not automatic startup or shared consent'
    [IO.File]::WriteAllText((Join-Path $temp 'install-options.json'), '{"CertificateMode":"shared","AutoStart":true,"AcceptSharedRisk":true}')
    $options = Get-AIExcelInstallOptions -InstallDirectory $temp
    Assert ($options.CertificateMode -eq 'independent' -and $options.AutoStart -and -not $options.AcceptSharedRisk) 'Upgrade preserves startup preference but never reuses shared certificate consent'
    [IO.File]::WriteAllText((Join-Path $temp 'install-options.json'), '{"AutoStart":"false"}')
    Assert (-not (Get-AIExcelInstallOptions -InstallDirectory $temp).AutoStart) 'String false cannot enable auto start'
    [IO.File]::WriteAllText((Join-Path $temp 'install-options.json'), 'broken json')
    Assert (-not (Get-AIExcelInstallOptions -InstallDirectory $temp -WarningAction SilentlyContinue).AutoStart) 'Corrupt options must default to opt-out'
    Assert (-not (Test-AIExcelSharedCertificateAvailable -SourceDirectory $temp)) 'Missing shared files should disable the compatibility option'
    foreach ($name in @('shared-localhost.pfx','shared-localhost.crt','shared-cert.thumbprint')) { [IO.File]::WriteAllText((Join-Path $temp $name), 'fixture') }
    Assert (Test-AIExcelSharedCertificateAvailable -SourceDirectory $temp) 'Complete shared payload enables explicit choice'
    $rejected = $false
    try { Assert-AIExcelCertificateChoice -CertificateMode shared -AcceptSharedRisk $false -SourceDirectory $temp } catch { $rejected = $true }
    Assert $rejected 'Shared key use requires explicit risk acceptance at backend boundary'
    Assert-AIExcelCertificateChoice -CertificateMode shared -AcceptSharedRisk $true -SourceDirectory $temp
    Assert-AIExcelCertificateChoice -CertificateMode independent -AcceptSharedRisk $false -SourceDirectory $temp
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-AIExcelInstallOptionsDialog -AutoStart $true -SharedAvailable $true
    try {
        Assert ($dialog.Independent.Checked -and $dialog.AutoStart.Checked -and -not $dialog.AcceptRisk.Checked) 'Dialog must show independent default and preserve auto start'
        Assert $dialog.Install.Enabled 'Default install choice is enabled'
        $dialog.Shared.Checked = $true
        Assert (-not $dialog.Install.Enabled -and $dialog.AcceptRisk.Enabled) 'Selecting shared blocks install until acknowledged'
        $dialog.AcceptRisk.Checked = $true
        Assert $dialog.Install.Enabled 'Acknowledgement unlocks shared install'
        $dialog.Independent.Checked = $true
        $dialog.Shared.Checked = $true
        Assert (-not $dialog.AcceptRisk.Checked -and -not $dialog.Install.Enabled) 'Switching modes resets shared acknowledgement'
        Assert ($dialog.Cancel.DialogResult -eq [Windows.Forms.DialogResult]::Cancel) 'Cancel must not install'
    } finally { $dialog.Form.Dispose() }
    $dialog = New-AIExcelInstallOptionsDialog -AutoStart $false -SharedAvailable $false
    try { Assert (-not $dialog.Shared.Enabled -and $dialog.Independent.Checked -and $dialog.Install.Enabled) 'Package without shared payload still installs independent certificates' }
    finally { $dialog.Form.Dispose() }
    'INSTALL_OPTIONS_TESTS_PASSED'
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }
