# Generates a 10-year self-signed localhost cert using the built-in Windows
# certificate engine (no third-party packages). Outputs:
#   dist/certs/localhost.pfx  (key+cert, passphrase "localdev" - server uses this)
#   dist/certs/localhost.crt  (public cert, DER - installed into Trusted Root)
# CN=localhost, SAN: localhost + 127.0.0.1, serverAuth EKU.
$ErrorActionPreference = "Stop"
$out = Join-Path $PSScriptRoot "dist\certs"
New-Item -ItemType Directory -Force -Path $out | Out-Null

$cert = New-SelfSignedCertificate `
  -Subject "CN=localhost" `
  -DnsName "localhost", "127.0.0.1" `
  -CertStoreLocation "Cert:\CurrentUser\My" `
  -NotAfter (Get-Date).AddYears(10) `
  -KeyExportPolicy Exportable `
  -KeyAlgorithm RSA -KeyLength 2048 `
  -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.1")   # EKU: serverAuth

$pw = ConvertTo-SecureString -String "localdev" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath (Join-Path $out "localhost.pfx") -Password $pw | Out-Null
Export-Certificate    -Cert $cert -FilePath (Join-Path $out "localhost.crt") | Out-Null

# we only needed the My-store entry to export; remove it to stay clean
Remove-Item $cert.PSPath -Force

Set-Content (Join-Path $out "cert.thumbprint") $cert.Thumbprint -Encoding Ascii -NoNewline
Write-Host ("wrote {0} (localhost.pfx + localhost.crt), thumbprint {1}" -f $out, $cert.Thumbprint)
