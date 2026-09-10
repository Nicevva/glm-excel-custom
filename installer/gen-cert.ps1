# Developer-only certificate generation; public builds never call this script.
[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'certs'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'certificate.ps1')
$certificate = New-LocalhostCertificate -OutputDirectory $OutputDirectory
Write-Host ('Generated a machine-local HTTPS certificate in {0} (expires in two years).' -f $OutputDirectory)
Write-Host 'The public certificate has not been added to Trusted Root. Trust it explicitly only for local development.'
Write-Output $certificate
