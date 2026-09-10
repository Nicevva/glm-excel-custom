# Per-user localhost certificate lifecycle. Dot-sourcing has no side effects.
# The PFX password is a file-format compatibility value, not a security boundary.

# Installation and removal share one per-user lock, including across sessions.
function Enter-AIExcelInstallLock {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $security = [Security.AccessControl.MutexSecurity]::new()
    $security.SetAccessRuleProtection($true, $false)
    foreach ($identity in @($sid, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
        $security.AddAccessRule([Security.AccessControl.MutexAccessRule]::new($identity, 'FullControl', 'Allow'))
    }
    $created = $false
    $mutex = [Threading.Mutex]::new($false, ('Global\AIExcelCustom-Install-' + $sid.Value), [ref]$created, $security)
    try {
        try { $acquired = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) { throw 'Another AI in Excel installation or removal is in progress.' }
        return $mutex
    } catch { $mutex.Dispose(); throw }
}

function Exit-AIExcelInstallLock($Lock) {
    if ($null -ne $Lock) { try { $Lock.ReleaseMutex() } finally { $Lock.Dispose() } }
}

function New-PrivateDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $full) { throw "Refusing to overwrite existing directory: $full" }
    $parent = [IO.DirectoryInfo]([IO.Path]::GetDirectoryName($full))
    while ($null -ne $parent) {
        if ($parent.Exists -and ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Private directory cannot be beneath a reparse point: $full"
        }
        $parent = $parent.Parent
    }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $system = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetOwner($sid)
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($identity in @($sid, $system)) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    # Supply the DACL when creating the directory, before any private files exist.
    [IO.Directory]::CreateDirectory($full, $acl) | Out-Null
    $actual = Get-Acl -LiteralPath $full -ErrorAction Stop
    if (-not $actual.AreAccessRulesProtected) { throw 'Private directory ACL inheritance is not disabled.' }
    foreach ($rule in $actual.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
        if ($rule.IdentityReference.Value -notin @($sid.Value, $system.Value)) {
            throw 'Private directory grants access to an unexpected identity.'
        }
    }
}

function Get-OwnedCertificateThumbprint {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$CertificateDirectory, [switch]$RequireValidEvidence)
    $thumbPath = Join-Path $CertificateDirectory 'cert.thumbprint'
    $crtPath = Join-Path $CertificateDirectory 'localhost.crt'
    $hasThumb = Test-Path -LiteralPath $thumbPath
    $hasCrt = Test-Path -LiteralPath $crtPath
    $hasPfx = Test-Path -LiteralPath (Join-Path $CertificateDirectory 'localhost.pfx')
    if (-not $hasThumb -or -not $hasCrt) {
        if ($RequireValidEvidence -and ($hasThumb -or $hasCrt -or $hasPfx)) { throw "Incomplete certificate ownership evidence; keep $CertificateDirectory for recovery." }
        return $null
    }
    $cert = $null
    try {
        $thumb = [IO.File]::ReadAllText($thumbPath).Trim().ToUpperInvariant()
        if ($thumb -notmatch '^[A-F0-9]{40}$') { throw 'Invalid certificate fingerprint record.' }
        $cert = [Security.Cryptography.X509Certificates.X509Certificate2]::new($crtPath)
        if ($cert.Thumbprint -ne $thumb) { throw 'Certificate and fingerprint record do not match.' }
        return $thumb
    } catch {
        if ($RequireValidEvidence) { throw }
        Write-Warning ('Cannot verify ownership of certificate in {0}: {1}' -f $CertificateDirectory, $_.Exception.Message)
        return $null
    } finally { if ($null -ne $cert) { $cert.Dispose() } }
}

function Set-AIExcelTrustOwnership {
    param([string]$CertificateDirectory, [string]$Thumbprint, [bool]$Owned)
    $actual = Get-OwnedCertificateThumbprint -CertificateDirectory $CertificateDirectory -RequireValidEvidence
    if (-not $actual -or $actual -ne $Thumbprint) { throw 'Cannot record ownership for an unverified certificate.' }
    $record = @{ Thumbprint = $actual; Owned = $Owned }
    [IO.File]::WriteAllText((Join-Path $CertificateDirectory 'trust-owner.json'), ($record | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
}

function Get-AIExcelOwnedTrustThumbprint {
    [CmdletBinding()]
    param([string]$CertificateDirectory)
    $thumb = Get-OwnedCertificateThumbprint -CertificateDirectory $CertificateDirectory -RequireValidEvidence
    if (-not $thumb) { return $null }
    $path = Join-Path $CertificateDirectory 'trust-owner.json'
    if (-not (Test-Path -LiteralPath $path)) { return $thumb }
    $record = [IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop
    if ($record.Thumbprint -ne $thumb -or $record.Owned -isnot [bool]) { throw 'Invalid certificate trust ownership record; preserve files for recovery.' }
    if ($record.Owned) { return $thumb }
    return $null
}

function Test-LocalhostCertificateFiles {
    [CmdletBinding()]
    param([string]$CertificateDirectory, [string]$ExpectedThumbprint)
    $public = $null
    $private = $null
    try {
        $public = [Security.Cryptography.X509Certificates.X509Certificate2]::new((Join-Path $CertificateDirectory 'localhost.crt'))
        $flags = [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
        $private = [Security.Cryptography.X509Certificates.X509Certificate2]::new((Join-Path $CertificateDirectory 'localhost.pfx'), 'localdev', $flags)
        if (-not $private.HasPrivateKey -or $private.Thumbprint -ne $public.Thumbprint -or $public.Thumbprint -ne $ExpectedThumbprint) {
            throw 'Generated PFX and public certificate do not match.'
        }
        if ($public.NotBefore -gt (Get-Date) -or $public.NotAfter -le (Get-Date)) { throw 'Generated certificate is not currently valid.' }
        $san = @($public.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.17' })
        if ($san.Count -ne 1 -or -not [string]::Equals($public.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::DnsFromAlternativeName, $false), 'localhost', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Localhost certificate must have localhost as its DNS subject alternative name.'
        }
        $basic = @($public.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.19' })
        $usage = @($public.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.15' })
        $eku = @($public.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.37' })
        if ($basic.Count -ne 1 -or $basic[0].CertificateAuthority -or -not $basic[0].Critical) { throw 'Localhost certificate must explicitly be a non-CA certificate.' }
        if ($usage.Count -ne 1 -or ($usage[0].KeyUsages -band ([Security.Cryptography.X509Certificates.X509KeyUsageFlags]::KeyCertSign -bor [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::CrlSign))) { throw 'Localhost certificate must not sign certificates or revocation lists.' }
        if ($eku.Count -ne 1 -or @($eku[0].EnhancedKeyUsages | Where-Object { $_.Value -eq '1.3.6.1.5.5.7.3.1' }).Count -ne 1) { throw 'Localhost certificate must have server authentication usage.' }
        return $true
    } finally {
        if ($null -ne $private) { $private.Dispose() }
        if ($null -ne $public) { $public.Dispose() }
    }
}

function New-LocalhostCertificate {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$OutputDirectory)
    $cert = $null
    $created = $false
    $complete = $false
    try {
        New-PrivateDirectory -Path $OutputDirectory
        $created = $true
        $extensions = @('2.5.29.19={critical}{text}ca=0', '2.5.29.37={text}1.3.6.1.5.5.7.3.1', '2.5.29.17={text}DNS=localhost&IPAddress=127.0.0.1&IPAddress=::1')
        $cert = New-SelfSignedCertificate -Type Custom -Subject 'CN=localhost' -FriendlyName 'AI in Excel local HTTPS' `
            -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter (Get-Date).AddYears(2) `
            -KeyExportPolicy Exportable -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 `
            -KeyUsage DigitalSignature,KeyEncipherment -TextExtension $extensions -ErrorAction Stop
        [IO.File]::WriteAllText((Join-Path $OutputDirectory 'cert.thumbprint'), $cert.Thumbprint, [Text.Encoding]::ASCII)
        $password = ConvertTo-SecureString -String 'localdev' -AsPlainText -Force
        $pfx = Join-Path $OutputDirectory 'localhost.pfx'
        $crt = Join-Path $OutputDirectory 'localhost.crt'
        Export-PfxCertificate -Cert $cert -FilePath $pfx -Password $password -ChainOption EndEntityCertOnly -NoProperties -ErrorAction Stop | Out-Null
        Export-Certificate -Cert $cert -FilePath $crt -ErrorAction Stop | Out-Null
        if (-not (Test-LocalhostCertificateFiles -CertificateDirectory $OutputDirectory -ExpectedThumbprint $cert.Thumbprint)) { throw 'Certificate verification failed.' }
        $complete = $true
        return [pscustomobject]@{ Thumbprint = $cert.Thumbprint; CertificatePath = $crt; PfxPath = $pfx }
    } finally {
        try {
            if ($null -ne $cert) {
                # Delete only the temporary certificate/key generated by this call.
                Remove-Item -LiteralPath ('Cert:\CurrentUser\My\' + $cert.Thumbprint) -DeleteKey -Force -ErrorAction Stop
            }
        } catch {
            # Keep restricted evidence if Windows refuses to remove the temporary key.
            $complete = $true
            $failure = [InvalidOperationException]::new(('Temporary My certificate/key cleanup failed for {0}; preserve {1}. {2}' -f $cert.Thumbprint, $OutputDirectory, $_.Exception.Message), $_.Exception)
            $failure.Data['CertificateRecoveryDirectory'] = $OutputDirectory
            throw $failure
        } finally {
            if ($created -and -not $complete -and (Test-Path -LiteralPath $OutputDirectory)) {
                Remove-Item -LiteralPath $OutputDirectory -Recurse -Force -ErrorAction Stop
            }
        }
    }
}

# Used only after the installer's explicit shared-private-key acknowledgement.
# This does not import trust or generate any key; it validates the packaged pair.
function Copy-SharedLocalhostCertificate {
    [CmdletBinding()]
    param([string]$SourceDirectory, [string]$OutputDirectory)
    $files = @{'shared-localhost.pfx' = 'localhost.pfx'; 'shared-localhost.crt' = 'localhost.crt'; 'shared-cert.thumbprint' = 'cert.thumbprint'}
    foreach ($name in $files.Keys) {
        $path = Join-Path $SourceDirectory $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing shared certificate input: $name" }
        $file = Get-Item -LiteralPath $path
        if ($file.Length -eq 0 -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Invalid shared certificate input: $name" }
    }
    $created = $false
    try {
        New-PrivateDirectory -Path $OutputDirectory
        $created = $true
        foreach ($name in $files.Keys) { Copy-Item -LiteralPath (Join-Path $SourceDirectory $name) -Destination (Join-Path $OutputDirectory $files[$name]) -ErrorAction Stop }
        $thumb = Get-OwnedCertificateThumbprint -CertificateDirectory $OutputDirectory -RequireValidEvidence
        if (-not $thumb -or -not (Test-LocalhostCertificateFiles -CertificateDirectory $OutputDirectory -ExpectedThumbprint $thumb)) { throw 'Shared certificate verification failed.' }
        return [pscustomobject]@{ Thumbprint = $thumb; CertificatePath = (Join-Path $OutputDirectory 'localhost.crt'); PfxPath = (Join-Path $OutputDirectory 'localhost.pfx') }
    } catch {
        if ($created -and (Test-Path -LiteralPath $OutputDirectory)) { Remove-Item -LiteralPath $OutputDirectory -Recurse -Force -ErrorAction Stop }
        throw
    }
}

function Test-AIExcelRootTrusted {
    param([string]$Thumbprint)
    if ($Thumbprint -notmatch '^[A-Fa-f0-9]{40}$') { throw 'Invalid certificate fingerprint.' }
    return Test-Path -LiteralPath ('Cert:\CurrentUser\Root\' + $Thumbprint.ToUpperInvariant())
}

function Remove-OwnedRootCertificates {
    [CmdletBinding()]
    param([string[]]$Thumbprints)
    $targets = @($Thumbprints | Where-Object { $_ } | ForEach-Object { $_.Trim().ToUpperInvariant() } | Select-Object -Unique)
    foreach ($thumb in $targets) {
        if ($thumb -notmatch '^[A-F0-9]{40}$') { throw 'Refusing to remove a certificate without an exact fingerprint.' }
    }
    foreach ($thumb in $targets) {
        $path = 'Cert:\CurrentUser\Root\' + $thumb
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
    }
}
