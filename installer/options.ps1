# Installation choices. Loading this file does not alter certificates or startup.
function Get-AIExcelInstallOptions {
    [CmdletBinding()]
    param([string]$InstallDirectory)
    $autoStart = $false
    $path = Join-Path $InstallDirectory 'install-options.json'
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try {
            $saved = [IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop
            $autoStart = $saved.AutoStart -is [bool] -and $saved.AutoStart
        } catch { Write-Warning 'Cannot read previous installation options; login startup remains disabled.' }
    }
    # A previous shared choice is never permission to trust a shared key again.
    return [pscustomobject]@{ CertificateMode = 'independent'; AutoStart = [bool]$autoStart; AcceptSharedRisk = $false }
}

function Test-AIExcelSharedCertificateAvailable {
    param([string]$SourceDirectory)
    foreach ($name in @('shared-localhost.pfx', 'shared-localhost.crt', 'shared-cert.thumbprint')) {
        $path = Join-Path $SourceDirectory $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
        $file = Get-Item -LiteralPath $path
        if ($file.Length -eq 0 -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $false }
    }
    return $true
}

function Assert-AIExcelCertificateChoice {
    param([ValidateSet('independent', 'shared')][string]$CertificateMode = 'independent', [bool]$AcceptSharedRisk = $false, [string]$SourceDirectory)
    if ($CertificateMode -eq 'shared') {
        if (-not $AcceptSharedRisk) { throw '必须明确勾选接受共用私钥风险后，才能使用内置共用证书。' }
        if (-not (Test-AIExcelSharedCertificateAvailable -SourceDirectory $SourceDirectory)) { throw '此安装包没有完整的内置共用证书，请选择生成本机独立证书。' }
    }
}

function New-AIExcelInstallOptionsDialog {
    param([bool]$AutoStart = $false, [bool]$SharedAvailable = $false)
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object Windows.Forms.Form
    $form.Text = 'AI in Excel 安装选项'
    $form.ClientSize = [Drawing.Size]::new(550, 390)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Font = [Drawing.Font]::new('Microsoft YaHei UI', 9)
    $form.AutoScaleMode = 'Dpi'
    $certificates = New-Object Windows.Forms.GroupBox
    $certificates.Text = 'HTTPS 证书'
    $certificates.SetBounds(20, 16, 510, 224)
    $form.Controls.Add($certificates)
    $independent = New-Object Windows.Forms.RadioButton
    $independent.Text = '自动生成本机独立证书（推荐）'
    $independent.SetBounds(18, 30, 470, 26)
    $independent.Checked = $true
    $certificates.Controls.Add($independent)
    $shared = New-Object Windows.Forms.RadioButton
    $shared.Text = '使用内置共用证书（兼容模式）'
    $shared.SetBounds(18, 66, 470, 26)
    $shared.Enabled = $SharedAvailable
    $certificates.Controls.Add($shared)
    $warning = New-Object Windows.Forms.Label
    $warning.SetBounds(38, 103, 450, 60)
    $warning.Text = if ($SharedAvailable) { '警告：共用私钥可被任何安装包持有者提取。使用共用证书的安全性低于独立证书，风险确认不会使私钥保密。' } else { '此安装包未包含共用证书，仅提供本机独立证书模式。' }
    $warning.ForeColor = [Drawing.Color]::DarkRed
    $certificates.Controls.Add($warning)
    $accept = New-Object Windows.Forms.CheckBox
    $accept.Text = '我已了解并接受共用私钥风险'
    $accept.SetBounds(38, 178, 450, 28)
    $accept.Enabled = $false
    $certificates.Controls.Add($accept)
    $startup = New-Object Windows.Forms.CheckBox
    $startup.Text = '登录 Windows 后自动启动后台服务'
    $startup.SetBounds(28, 259, 490, 26)
    $startup.Checked = $AutoStart
    $form.Controls.Add($startup)
    $note = New-Object Windows.Forms.Label
    $note.Text = '自启仅运行后台服务，不弹窗口、不自动打开 Excel。'
    $note.SetBounds(46, 291, 480, 28)
    $form.Controls.Add($note)
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = '取消'
    $cancel.SetBounds(320, 338, 94, 32)
    $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancel)
    $install = New-Object Windows.Forms.Button
    $install.Text = '安装'
    $install.SetBounds(430, 338, 94, 32)
    $install.DialogResult = [Windows.Forms.DialogResult]::OK
    $form.Controls.Add($install)
    $form.AcceptButton = $install
    $form.CancelButton = $cancel
    $shared.Add_CheckedChanged({ $accept.Checked = $false; $accept.Enabled = $shared.Checked; $install.Enabled = -not $shared.Checked }.GetNewClosure())
    $accept.Add_CheckedChanged({ $install.Enabled = -not $shared.Checked -or $accept.Checked }.GetNewClosure())
    return [pscustomobject]@{ Form = $form; Independent = $independent; Shared = $shared; AcceptRisk = $accept; AutoStart = $startup; Install = $install; Cancel = $cancel }
}

function Show-AIExcelInstallOptions {
    param([string]$InstallDirectory, [string]$SourceDirectory)
    $previous = Get-AIExcelInstallOptions -InstallDirectory $InstallDirectory
    $dialog = New-AIExcelInstallOptionsDialog -AutoStart $previous.AutoStart -SharedAvailable (Test-AIExcelSharedCertificateAvailable -SourceDirectory $SourceDirectory)
    try {
        if ($dialog.Form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return $null }
        $mode = if ($dialog.Shared.Checked) { 'shared' } else { 'independent' }
        Assert-AIExcelCertificateChoice -CertificateMode $mode -AcceptSharedRisk $dialog.AcceptRisk.Checked -SourceDirectory $SourceDirectory
        return [pscustomobject]@{ CertificateMode = $mode; AutoStart = $dialog.AutoStart.Checked; AcceptSharedRisk = $dialog.AcceptRisk.Checked }
    } finally { $dialog.Form.Dispose() }
}
