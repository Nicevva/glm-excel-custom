param([string]$HelperPath)
$ErrorActionPreference = 'Stop'
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
Assert (Test-Path $HelperPath) 'Certificate helper must exist'
. ([ScriptBlock]::Create([IO.File]::ReadAllText($HelperPath)))
$Temp = Join-Path ([IO.Path]::GetTempPath()) ('aie-certificate-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Temp | Out-Null
# Exercise actual certificate parsing with in-memory keys, without any Windows store.
$validateFiles = ${function:Test-LocalhostCertificateFiles}
$realThumb = ${function:Get-OwnedCertificateThumbprint}
$script:Removed = @()
$script:Created = 0
$script:FailExport = $false
$script:FailKeyCleanup = $false
$script:FakeThumb = ('A' * 40)
$RealRemove = 'Microsoft.PowerShell.Management\Remove-Item'
function New-SelfSignedCertificate {
    param($Type, $Subject, $FriendlyName, $CertStoreLocation, $NotAfter, $KeyExportPolicy, $KeyAlgorithm, $KeyLength, $HashAlgorithm, $KeyUsage, $TextExtension)
    Assert ($CertStoreLocation -eq 'Cert:\CurrentUser\My') 'Temporary key must use CurrentUser My only'
    Assert ($Type -eq 'Custom' -and $KeyAlgorithm -eq 'RSA' -and $KeyLength -ge 2048) 'Explicit non-CA TLS key parameters required'
    Assert ($HashAlgorithm -eq 'SHA256') 'SHA256 certificate required'
    Assert ($TextExtension -contains '2.5.29.19={critical}{text}ca=0') 'CA=false must be explicit'
    Assert (($TextExtension -join '|').Contains('IPAddress=127.0.0.1')) 'IP address must use an IP SAN'
    Assert (-not (($KeyUsage -join ',') -match 'CertSign|CRLSign')) 'Key cannot sign certificates'
    $acl = Get-Acl -LiteralPath $script:Output
    Assert $acl.AreAccessRulesProtected 'Private output must be protected before key generation'
    $script:Created++
    $thumb = if ($script:Created % 2) { 'A' * 40 } else { 'B' * 40 }
    [pscustomobject]@{ Thumbprint = $thumb; PSPath = ('Cert:\CurrentUser\My\' + $thumb) }
}
function Export-PfxCertificate {
    param($Cert, $FilePath, $Password, $ChainOption, [switch]$NoProperties)
    if ($script:FailExport) { throw 'injected export failure' }
    Assert ($ChainOption -eq 'EndEntityCertOnly') 'Do not export unrelated certificate chains'
    [IO.File]::WriteAllText($FilePath, 'FAKE-PFX-NO-KEY')
}
function Export-Certificate { param($Cert, $FilePath) [IO.File]::WriteAllText($FilePath, 'FAKE-PUBLIC-CERT') }
function Test-LocalhostCertificateFiles { param($CertificateDirectory, $ExpectedThumbprint) return $true }
function Remove-Item {
    param($LiteralPath, $Path, [switch]$DeleteKey, [switch]$Force, [switch]$Recurse, $ErrorAction)
    $target = if ($LiteralPath) { $LiteralPath } else { $Path }
    if ($target -like 'Cert:*' -and $DeleteKey -and $script:FailKeyCleanup) { throw 'injected private-key cleanup failure' }
    if ($target -like 'Cert:*') { $script:Removed += [pscustomobject]@{ Path = $target; DeleteKey = [bool]$DeleteKey }; return }
    & $RealRemove -LiteralPath $target -Force:$Force -Recurse:$Recurse -ErrorAction Stop
}
try {
    $script:Output = Join-Path $Temp 'first'
    $first = New-LocalhostCertificate -OutputDirectory $script:Output
    Assert ($first.Thumbprint -eq ('A' * 40)) 'Return the generated certificate fingerprint'
    Assert (Test-Path $first.PfxPath) 'PFX should be exported'
    $acl = Get-Acl -LiteralPath $script:Output
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
        Assert ($rule.IdentityReference.Value -in @($sid, 'S-1-5-18')) 'Private directory grants access to an unrelated identity'
    }
    Assert ($script:Removed.Count -eq 1 -and $script:Removed[0].DeleteKey) 'Temporary My entry and private key must be cleaned'
    $script:Output = Join-Path $Temp 'second'
    $second = New-LocalhostCertificate -OutputDirectory $script:Output
    Assert ($second.Thumbprint -ne $first.Thumbprint -and $script:Created -eq 2) 'Each install invokes fresh key generation'
    $script:Output = Join-Path $Temp 'failure'
    $script:FailExport = $true
    $failed = $false
    try { New-LocalhostCertificate -OutputDirectory $script:Output } catch { $failed = $_.Exception.Message -match 'injected export failure' }
    Assert $failed 'Export failure must propagate'
    Assert (-not (Test-Path $script:Output)) 'Failed private staging output must be removed'
    Assert ($script:Removed.Count -eq 3 -and $script:Removed[2].DeleteKey) 'Failure must delete the temporary private key'
    $script:FailExport = $false
    $script:FailKeyCleanup = $true
    $script:Output = Join-Path $Temp 'cleanup-failure'
    $recovery = $null
    try { New-LocalhostCertificate -OutputDirectory $script:Output } catch { $recovery = $_.Exception.Data['CertificateRecoveryDirectory'] }
    Assert ($recovery -eq $script:Output) 'Private-key cleanup failure must propagate an explicit recovery directory'
    Assert (Test-Path (Join-Path $recovery 'cert.thumbprint')) 'Keep precise recovery evidence when My key cleanup fails'
    $script:FailKeyCleanup = $false
    $script:Output = Join-Path $Temp 'first'
    $failed = $false
    try { New-LocalhostCertificate -OutputDirectory $script:Output } catch { $failed = $true }
    Assert $failed 'Existing key directory must never be overwritten'
    $script:Removed = @()
    $bad = $false
    try { Remove-OwnedRootCertificates -Thumbprints @('..\Other') } catch { $bad = $true }
    Assert ($bad -and $script:Removed.Count -eq 0) 'Reject non-fingerprint deletion targets'
    function Test-Path { param($LiteralPath, $Path) if (($LiteralPath + $Path) -like 'Cert:*') { return $true }; Microsoft.PowerShell.Management\Test-Path -LiteralPath ($LiteralPath + $Path) }
    Remove-OwnedRootCertificates -Thumbprints @($first.Thumbprint, $first.Thumbprint, $second.Thumbprint)
    Assert ($script:Removed.Count -eq 2) 'Only distinct exact owned certificates should be removed'
    Assert (@($script:Removed | Where-Object { $_.Path -notmatch '^Cert:\\CurrentUser\\Root\\[A-F0-9]{40}$' -or $_.DeleteKey }).Count -eq 0) 'Root cleanup must use exact current-user public certificate paths'
    Remove-Item Function:\Test-Path
    $proof = Join-Path $Temp 'proof'
    New-Item -ItemType Directory -Path $proof | Out-Null
    [IO.File]::WriteAllText((Join-Path $proof 'cert.thumbprint'), 'not-a-fingerprint')
    [IO.File]::WriteAllText((Join-Path $proof 'localhost.crt'), 'invalid')
    $failed = $false
    try { Get-OwnedCertificateThumbprint -CertificateDirectory $proof -RequireValidEvidence } catch { $failed = $true }
    Assert $failed 'Existing invalid evidence must stop destructive upgrade/uninstall'
    Assert ($null -eq (Get-OwnedCertificateThumbprint -CertificateDirectory $proof -WarningAction SilentlyContinue)) 'Invalid ownership evidence must not authorize removal'
    # CertificateRequest generates test-only, ephemeral RSA keys, never a store entry.
    $fingerprints = @()
    foreach ($ca in @($false, $true, $false)) {
        $rsa = [Security.Cryptography.RSA]::Create(2048)
        $cert = $null
        try {
            $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=localhost', $rsa, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($ca, $false, 0, $true))
            $usage = [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature -bor [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyEncipherment
            $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new($usage, $true))
            $oids = [Security.Cryptography.OidCollection]::new(); $oids.Add([Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.1')) | Out-Null
            $request.CertificateExtensions.Add([Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($oids, $false))
            $san = [Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
            $san.AddDnsName('localhost'); $san.AddIpAddress([Net.IPAddress]::Loopback); $san.AddIpAddress([Net.IPAddress]::IPv6Loopback)
            $request.CertificateExtensions.Add($san.Build())
            $cert = $request.CreateSelfSigned([DateTimeOffset]::UtcNow.AddMinutes(-1), [DateTimeOffset]::UtcNow.AddDays(1))
            $dir = Join-Path $Temp ('real-' + [guid]::NewGuid().ToString('N'))
            New-PrivateDirectory -Path $dir
            [IO.File]::WriteAllBytes((Join-Path $dir 'localhost.pfx'), $cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pfx, 'localdev'))
            [IO.File]::WriteAllBytes((Join-Path $dir 'localhost.crt'), $cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert))
            [IO.File]::WriteAllText((Join-Path $dir 'cert.thumbprint'), $cert.Thumbprint)
            Assert ((& $realThumb -CertificateDirectory $dir) -eq $cert.Thumbprint) 'Ownership must compare real DER fingerprint'
            if ($ca) {
                $failed = $false
                try { & $validateFiles -CertificateDirectory $dir -ExpectedThumbprint $cert.Thumbprint } catch { $failed = $true }
                Assert $failed 'Actual certificate validation must reject a CA certificate'
            } else {
                Assert (& $validateFiles -CertificateDirectory $dir -ExpectedThumbprint $cert.Thumbprint) 'Valid independent non-CA certificate must validate'
                $fingerprints += $cert.Thumbprint
            }
            [IO.File]::WriteAllText((Join-Path $dir 'cert.thumbprint'), ('C' * 40))
            Assert ($null -eq (& $realThumb -CertificateDirectory $dir -WarningAction SilentlyContinue)) 'Mismatched real CRT must not authorize trust cleanup'
        } finally { if ($cert) { $cert.Dispose() }; $rsa.Dispose() }
    }
    Assert ($fingerprints.Count -eq 2 -and $fingerprints[0] -ne $fingerprints[1]) 'Independent ephemeral keys must not share a certificate'
    $lock = Enter-AIExcelInstallLock
    try {
        $helperQuoted = $HelperPath.Replace("'", "''")
        $command = ". ([ScriptBlock]::Create([IO.File]::ReadAllText('$helperQuoted'))); try { `$l=Enter-AIExcelInstallLock; Exit-AIExcelInstallLock `$l; exit 1 } catch { exit 0 }"
        & powershell.exe -NoProfile -NonInteractive -Command $command
        Assert ($LASTEXITCODE -eq 0) 'A different process must not enter an ongoing install/uninstall transaction'
    } finally { Exit-AIExcelInstallLock $lock }
    $lock = Enter-AIExcelInstallLock; Exit-AIExcelInstallLock $lock
    'CERTIFICATE_SECURITY_TESTS_PASSED'
} finally {
    & $RealRemove -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
}
