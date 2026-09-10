param([string]$StartupPath)
$ErrorActionPreference = 'Stop'
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Assert-Throws([scriptblock]$Action, [string]$Pattern) {
    $caught = $null
    try { & $Action } catch { $caught = $_ }
    Assert ($null -ne $caught) ('Expected operation to fail: ' + $Action + ' fixture=' + ($command | ConvertTo-Json -Compress))
    Assert ($caught.Exception.Message -match $Pattern) ('Unexpected error: ' + $caught)
}

# The entire Registry provider boundary is in memory. Never write HKCU in tests.
$script:RunPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$script:Values = @{}
$script:KeyExists = $true
$script:Calls = 0
$script:FailWrite = $false
$script:FailRead = $false
function Assert-RunPath($Path) { Assert ($Path -ceq $script:RunPath) ('Unexpected registry path: ' + $Path) }
function Test-Path { param($LiteralPath, $Path, $ErrorAction)
    $script:Calls++
    if ($null -ne $LiteralPath) { Assert-RunPath $LiteralPath } else { Assert-RunPath $Path }
    return $script:KeyExists
}
function Get-Item { param($LiteralPath, $Path, $ErrorAction)
    $script:Calls++
    if ($null -ne $LiteralPath) { Assert-RunPath $LiteralPath } else { Assert-RunPath $Path }
    if ($script:FailRead) { throw 'injected read denial' }
    Assert $script:KeyExists 'Cannot open an absent Run key'
    $key = [pscustomobject]@{}
    $key | Add-Member ScriptMethod GetValueNames { return [string[]]@($script:Values.Keys) }
    $key | Add-Member ScriptMethod GetValue {
        param($Name, $Default, $Options)
        Assert ($Name -ceq 'AIExcelCustom') 'Read only the owned named value'
        Assert ($Options -eq [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) 'Read raw expand-string data for rollback'
        return ,$script:Values[$Name].Value
    }
    $key | Add-Member ScriptMethod GetValueKind { param($Name) return $script:Values[$Name].Kind }
    $key | Add-Member ScriptMethod Close { }
    return $key
}
function New-Item { param($Path, [switch]$Force, $ErrorAction)
    $script:Calls++; Assert-RunPath $Path
    Assert $Force 'Key creation must preserve existing values'
    $script:KeyExists = $true
}
function New-ItemProperty { param($LiteralPath, $Path, $Name, $Value, $PropertyType, [switch]$Force, $ErrorAction)
    $script:Calls++
    if ($null -ne $LiteralPath) { Assert-RunPath $LiteralPath } else { Assert-RunPath $Path }
    Assert ($Name -ceq 'AIExcelCustom') 'Write only AIExcelCustom'
    Assert $script:KeyExists 'Run key must exist before setting the value'
    Assert $Force 'Existing value replacement must be explicit'
    if ($script:FailWrite) { throw 'injected write denial' }
    $script:Values[$Name] = @{ Value = $Value; Kind = [Microsoft.Win32.RegistryValueKind]$PropertyType }
}
function Remove-ItemProperty { param($LiteralPath, $Path, $Name, $ErrorAction)
    $script:Calls++
    if ($null -ne $LiteralPath) { Assert-RunPath $LiteralPath } else { Assert-RunPath $Path }
    Assert ($Name -ceq 'AIExcelCustom') 'Remove only AIExcelCustom, never the Run key or other values'
    if ($script:FailWrite) { throw 'injected delete denial' }
    $script:Values.Remove($Name)
}
function Remove-Item { throw 'Deleting a Registry key is forbidden' }
function Set-ItemProperty { throw 'Use typed registry writes to preserve REG_SZ and rollback kinds' }
function Get-ChildItem { throw 'Scanning other startup entries is forbidden' }

Assert ([IO.File]::Exists($StartupPath)) 'startup.ps1 must provide the auto-start API'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($StartupPath, [ref]$tokens, [ref]$errors)
Assert ($errors.Count -eq 0) 'startup.ps1 must parse in Windows PowerShell 5.1'
foreach ($statement in $ast.EndBlock.Statements) {
    Assert ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) 'Dot-source library may only define functions'
}
# Evaluate the complete library (not just extracted functions) without changing execution policy.
$before = $script:Calls
. ([scriptblock]::Create([IO.File]::ReadAllText($StartupPath)))
Assert ($script:Calls -eq $before) 'Dot-sourcing must have no provider access or side effects'
$passed = 1
$dir = 'C:\Fixture Space\AI Excel'
$expected = 'wscript.exe //B "C:\Fixture Space\AI Excel\launch.vbs" --autostart'
Assert ((Get-AIExcelAutoStartCommand -InstallDirectory $dir) -ceq $expected) 'Command must quote a spaced script path, use batch WSH and pass autostart'
Assert ((Get-AIExcelAutoStartCommand -InstallDirectory 'C:/Fixture Space/AI Excel/../AI Excel/') -ceq $expected) 'Normalize absolute install paths without requiring the directory to exist'
Assert ($script:Calls -eq $before) 'Command construction is pure'
$passed++
foreach ($badPath in @('', 'relative\install', 'C:\bad"path', "C:\bad`npath")) {
    Assert-Throws { Get-AIExcelAutoStartCommand -InstallDirectory $badPath } '.'
}
$passed++
$script:KeyExists = $false
$absent = Get-AIExcelAutoStartState
Assert (-not $absent.Exists -and $null -eq $absent.Value -and $null -eq $absent.Kind) 'Missing Run key is an absent state'
Set-AIExcelAutoStart -InstallDirectory $dir -Enabled $false
Remove-AIExcelAutoStart -InstallDirectory $dir
Restore-AIExcelAutoStartState -Previous $absent
Assert (-not $script:KeyExists) 'Off and absent rollback must not create a Run key'
$passed++
Set-AIExcelAutoStart -InstallDirectory $dir -Enabled $true
$enabled = Get-AIExcelAutoStartState
Assert ($enabled.Exists -and $enabled.Value -ceq $expected -and $enabled.Kind -eq [Microsoft.Win32.RegistryValueKind]::String) 'Enabling creates exactly the canonical REG_SZ command'
$passed++
$script:Values['OtherApp'] = @{ Value = 'keep me'; Kind = [Microsoft.Win32.RegistryValueKind]::String }
Set-AIExcelAutoStart -InstallDirectory $dir -Enabled $true
Assert ($script:Values.Count -eq 2) 'Repeated enable is idempotent and keeps unrelated values'
Set-AIExcelAutoStart -InstallDirectory $dir.ToUpperInvariant() -Enabled $false
Assert (-not (Get-AIExcelAutoStartState).Exists) 'Disabling recognizes case-insensitive Windows paths'
Assert ($script:Values['OtherApp'].Value -ceq 'keep me') 'Disabling preserves unrelated values'
$passed++
Set-AIExcelAutoStart -InstallDirectory $dir -Enabled $true
Restore-AIExcelAutoStartState -Previous $absent
Assert (-not (Get-AIExcelAutoStartState).Exists -and $script:Values.ContainsKey('OtherApp')) 'Rollback of a newly added value removes only that value'
$passed++

$previousValues = @(
    @{ Value = ''; Kind = [Microsoft.Win32.RegistryValueKind]::String },
    @{ Value = 'wscript.exe "C:\Old\launch.vbs"'; Kind = [Microsoft.Win32.RegistryValueKind]::String },
    @{ Value = '%LOCALAPPDATA%\original.exe'; Kind = [Microsoft.Win32.RegistryValueKind]::ExpandString },
    @{ Value = [int]0; Kind = [Microsoft.Win32.RegistryValueKind]::DWord },
    @{ Value = [long]9223372036854775806; Kind = [Microsoft.Win32.RegistryValueKind]::QWord },
    @{ Value = [byte[]]@(0, 127, 255); Kind = [Microsoft.Win32.RegistryValueKind]::Binary },
    @{ Value = [byte[]]@(); Kind = [Microsoft.Win32.RegistryValueKind]::None },
    @{ Value = [string[]]@('first', 'second'); Kind = [Microsoft.Win32.RegistryValueKind]::MultiString }
)
foreach ($entry in $previousValues) {
    $script:Values['AIExcelCustom'] = $entry.Clone()
    $snapshot = Get-AIExcelAutoStartState
    Assert $snapshot.Exists 'Empty, zero and non-string data are still existing values'
    Set-AIExcelAutoStart -InstallDirectory $dir -Enabled $true
    Restore-AIExcelAutoStartState -Previous $snapshot
    $restored = Get-AIExcelAutoStartState
    Assert ($restored.Kind -eq $entry.Kind) 'Rollback must restore the exact RegistryValueKind'
    Assert (($restored.Value | ConvertTo-Json -Compress) -ceq ($entry.Value | ConvertTo-Json -Compress)) 'Rollback must restore raw data, including empty values and arrays'
    Assert ($restored.Value.GetType() -eq $entry.Value.GetType()) 'Rollback must not coerce non-string values'
    $passed++
}
foreach ($command in @('wscript.exe //B "C:\Other\launch.vbs" --autostart', ($expected + ' --changed'), $expected.Replace('wscript.exe', 'evil.exe'), '"C:\Fixture Space\AI Excel\launch.vbs"', '')) {
    $script:Values['AIExcelCustom'] = @{ Value = $command; Kind = [Microsoft.Win32.RegistryValueKind]::String }
    foreach ($operation in @({ Set-AIExcelAutoStart -InstallDirectory $dir -Enabled $false }, { Remove-AIExcelAutoStart -InstallDirectory $dir })) {
        Assert-Throws $operation 'AIExcelCustom.*(match|belong|different|不匹配|不属于)'
        Assert ($script:Values['AIExcelCustom'].Value -ceq $command) 'Mismatching or altered commands must be preserved'
        Assert ($script:Values['OtherApp'].Value -ceq 'keep me') 'Conflict never changes unrelated startup values'
    }
    $passed++
}
$script:Values['AIExcelCustom'] = @{ Value = [int]12; Kind = [Microsoft.Win32.RegistryValueKind]::DWord }
Assert-Throws { Remove-AIExcelAutoStart -InstallDirectory $dir } 'AIExcelCustom.*(match|belong|different|不匹配|不属于)'
Assert ($script:Values['AIExcelCustom'].Value -eq 12) 'Never coerce a foreign value to a command for ownership'
$passed++
Set-AIExcelAutoStart -InstallDirectory $dir -Enabled $true
Remove-AIExcelAutoStart -InstallDirectory $dir
Assert (-not (Get-AIExcelAutoStartState).Exists -and $script:Values.ContainsKey('OtherApp')) 'Uninstall removes only a verified matching command'
$passed++
$script:FailWrite = $true
Assert-Throws { Set-AIExcelAutoStart -InstallDirectory $dir -Enabled $true } 'injected write denial'
$script:FailWrite = $false
$script:FailRead = $true
Assert-Throws { Get-AIExcelAutoStartState } 'injected read denial'
$script:FailRead = $false
$passed++
"STARTUP_TESTS_PASSED: $passed"
