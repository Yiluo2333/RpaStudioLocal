param([string]$WixDirectory)
. (Join-Path $PSScriptRoot 'Common.ps1')
$repo = Split-Path $PSScriptRoot
if (!$WixDirectory) { $WixDirectory = Join-Path $repo '.tools\wix-3.14.1' }
foreach ($tool in @('candle.exe','light.exe','WixUIExtension.dll')) {
    if (!(Test-Path -LiteralPath (Join-Path $WixDirectory $tool))) { throw 'WiX 3.14.1 is required. Run scripts\Get-Wix.ps1 or pass -WixDirectory.' }
}
$release = Join-Path $repo 'artifacts'
if (!(Test-Path -LiteralPath (Join-Path $release 'RpaStudioLocal.exe'))) { throw 'Run Build.ps1 -Original <installation> first.' }
$version = (Get-Content -LiteralPath (Join-Path $repo 'VERSION') -Raw).Trim()
$build = Join-Path $repo ('build\msi-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $build | Out-Null
$object = Join-Path $build 'Product.wixobj'
& (Join-Path $WixDirectory 'candle.exe') -nologo -arch x86 ('-dProductVersion=' + $version) ('-dReleaseDir=' + $release) ('-dLicenseRtf=' + (Join-Path $repo 'installer\Notice.rtf')) -out $object (Join-Path $repo 'installer\Product.wxs')
if ($LASTEXITCODE -ne 0) { throw 'WiX compilation failed.' }
$msi = Join-Path $release ('RpaStudioLocal-' + $version + '-x86.msi')
# ICE91 and ICE64 describe intentional per-user and shared Programs folder locations.
& (Join-Path $WixDirectory 'light.exe') -nologo -wx -sice:ICE91 -sice:ICE64 -ext (Join-Path $WixDirectory 'WixUIExtension.dll') -cultures:zh-cn -out $msi $object
if ($LASTEXITCODE -ne 0) { throw 'WiX linking or MSI validation failed.' }
Write-Output "Built $msi"
