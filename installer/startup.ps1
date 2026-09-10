# Auto-start helpers. Dot-sourcing this file only defines functions.
function Get-AIExcelAutoStartCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$InstallDirectory)

    if ($InstallDirectory -match '["\x00-\x1f]' -or
        $InstallDirectory -notmatch '^(?:[a-zA-Z]:[\\/]|\\\\[^\\/]+[\\/][^\\/]+(?:[\\/]|$))') {
        throw 'InstallDirectory must be an absolute Windows path without quotes or control characters.'
    }
    $directory = [IO.Path]::GetFullPath($InstallDirectory)
    $launcher = [IO.Path]::Combine($directory, 'launch.vbs')
    return ('wscript.exe //B "{0}" --autostart' -f $launcher)
}

function Get-AIExcelAutoStartState {
    [CmdletBinding()]
    param()

    $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $absent = @{ Exists = $false; Value = $null; Kind = $null }
    if (-not (Test-Path -LiteralPath $path -ErrorAction Stop)) { return $absent }
    $key = Get-Item -LiteralPath $path -ErrorAction Stop
    try {
        if ($key.GetValueNames() -notcontains 'AIExcelCustom') { return $absent }
        # Keep raw data and type, including empty strings, arrays and REG_EXPAND_SZ.
        return @{
            Exists = $true
            Value = $key.GetValue('AIExcelCustom', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            Kind = $key.GetValueKind('AIExcelCustom')
        }
    } finally {
        $key.Close()
    }
}

function Restore-AIExcelAutoStartState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Previous)

    $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if ($Previous.Exists -isnot [bool]) { throw 'Previous must be an AIExcelCustom auto-start state.' }
    if ($Previous.Exists) {
        if ($null -eq $Previous.Kind) { throw 'Previous must retain the registry value kind.' }
        if (-not (Test-Path -LiteralPath $path -ErrorAction Stop)) {
            New-Item -Path $path -Force -ErrorAction Stop | Out-Null
        }
        New-ItemProperty -LiteralPath $path -Name 'AIExcelCustom' -Value $Previous.Value `
            -PropertyType ([Microsoft.Win32.RegistryValueKind]$Previous.Kind) -Force -ErrorAction Stop | Out-Null
    } elseif ((Get-AIExcelAutoStartState).Exists) {
        Remove-ItemProperty -LiteralPath $path -Name 'AIExcelCustom' -ErrorAction Stop
    }
}

function Set-AIExcelAutoStart {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstallDirectory,
        [Parameter(Mandatory = $true)][bool]$Enabled
    )

    if (-not $Enabled) {
        Remove-AIExcelAutoStart -InstallDirectory $InstallDirectory
        return
    }
    $command = Get-AIExcelAutoStartCommand -InstallDirectory $InstallDirectory
    Restore-AIExcelAutoStartState -Previous @{
        Exists = $true; Value = $command; Kind = [Microsoft.Win32.RegistryValueKind]::String
    }
}

function Remove-AIExcelAutoStart {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$InstallDirectory)

    $expected = Get-AIExcelAutoStartCommand -InstallDirectory $InstallDirectory
    $current = Get-AIExcelAutoStartState
    if (-not $current.Exists) { return }
    # Match the whole generated command, not a substring or just the filename.
    if ($current.Kind -ne [Microsoft.Win32.RegistryValueKind]::String -or
        $current.Value -isnot [string] -or
        -not [string]::Equals($current.Value, $expected, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'AIExcelCustom auto-start does not match this installation; the existing value was left unchanged.'
    }
    Remove-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' `
        -Name 'AIExcelCustom' -ErrorAction Stop
}
