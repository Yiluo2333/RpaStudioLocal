. (Join-Path $PSScriptRoot 'Common.ps1')
$repo = Split-Path $PSScriptRoot
$release = Join-Path $repo 'artifacts'
$version = (Get-Content -LiteralPath (Join-Path $repo 'VERSION') -Raw).Trim()
foreach ($file in @('RpaStudioLocal.exe',('RpaStudioLocal-' + $version + '-x86.msi'),'build-report.json')) {
    if (!(Test-Path -LiteralPath (Join-Path $release $file))) { throw "Build required artifact first: $file" }
}
Copy-Item -LiteralPath (Join-Path $repo 'docs\USER-GUIDE.md') -Destination (Join-Path $release 'USER-GUIDE.md') -Force
Copy-Item -LiteralPath (Join-Path $repo 'THIRD-PARTY.md') -Destination (Join-Path $release 'THIRD-PARTY.md') -Force
& (Join-Path $PSScriptRoot 'Export-Source.ps1')
$stage = Join-Path $repo ('build\portable-release-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $stage | Out-Null
foreach ($file in @('RpaStudioLocal.exe','USER-GUIDE.md','THIRD-PARTY.md','build-report.json','components.sha256','host-verification.json','msi-verification.json','legacy-verification.txt')) {
    $source = Join-Path $release $file
    if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination (Join-Path $stage $file) }
}
$portable = Join-Path $release ('RpaStudioLocal-' + $version + '-portable.zip')
if (Test-Path -LiteralPath $portable) { Remove-Item -LiteralPath $portable }
New-PortableZip $stage $portable
$hashes = @('RpaStudioLocal.exe',('RpaStudioLocal-' + $version + '-x86.msi'),('RpaStudioLocal-' + $version + '-portable.zip'),('RpaStudioLocal-' + $version + '-github-source.zip')) | ForEach-Object {
    (Get-FileHash -LiteralPath (Join-Path $release $_)).Hash.ToLowerInvariant() + '  ' + $_
}
[IO.File]::WriteAllLines((Join-Path $release 'SHA256SUMS.txt'),[string[]]$hashes,[Text.UTF8Encoding]::new($false))
Write-Output "Release packages and SHA256SUMS.txt ready in $release"
