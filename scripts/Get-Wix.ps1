param([string]$Destination = (Join-Path (Split-Path $PSScriptRoot) '.tools\wix-3.14.1'))
. (Join-Path $PSScriptRoot 'Common.ps1')
$url = 'https://github.com/wixtoolset/wix3/releases/download/wix3141rtm/wix314-binaries.zip'
$expected = '6ac824e1642d6f7277d0ed7ea09411a508f6116ba6fae0aa5f2c7daa2ff43d31'
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
$archive = Join-Path $Destination 'wix314-binaries.zip'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive
if ((Get-FileHash -LiteralPath $archive).Hash.ToLowerInvariant() -ne $expected) { throw 'WiX archive SHA256 mismatch.' }
Expand-Archive -LiteralPath $archive -DestinationPath $Destination -Force
Write-Output "WiX 3.14.1 ready: $Destination"
