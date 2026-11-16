param([string]$OutputDirectory)
. (Join-Path $PSScriptRoot 'Common.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$repo = Split-Path $PSScriptRoot
if (!$OutputDirectory) { $OutputDirectory = Join-Path $repo 'artifacts' }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$version = (Get-Content -LiteralPath (Join-Path $repo 'VERSION') -Raw).Trim()
$stage = Join-Path $repo ('build\public-source-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $stage | Out-Null
$roots = @('.github','src','scripts','tests','installer','docs')
$extensions = @('.cs','.csproj','.ps1','.md','.json','.yml','.wxs','.rtf','.ico')
foreach ($root in $roots) {
    Get-ChildItem -LiteralPath (Join-Path $repo $root) -Recurse -File | Where-Object {
        $_.FullName -notmatch '\\(bin|obj)\\' -and $_.Extension -in $extensions
    } | ForEach-Object { Copy-StaticFile $_.FullName (Join-Path $stage $_.FullName.Substring($repo.Length + 1)) }
}
foreach ($file in @('.gitignore','.gitattributes','VERSION','README.md','LICENSE.md','THIRD-PARTY.md','CHANGELOG.md','Build.ps1','RpaStudioLocal.sln')) {
    Copy-StaticFile (Join-Path $repo $file) (Join-Path $stage $file)
}
$files = @(Get-ChildItem -LiteralPath $stage -Recurse -File)
$forbidden = @($files | Where-Object {$_.Extension -in @('.dll','.exe','.msi','.db','.log','.pdb','.proj','.flow','.script','.pfx','.key')})
if ($forbidden.Count -ne 0) { throw 'Public source contains a forbidden private/binary file.' }
$manifest = $files | Sort-Object FullName | ForEach-Object {(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant() + '  ' + $_.FullName.Substring($stage.Length + 1).Replace('\','/')}
[IO.File]::WriteAllLines((Join-Path $stage 'SOURCE-SHA256.txt'),[string[]]$manifest,[Text.UTF8Encoding]::new($false))
$zip = Join-Path $OutputDirectory ('RpaStudioLocal-' + $version + '-github-source.zip')
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip }
New-PortableZip $stage $zip
Write-Output "Public source: $zip ($($files.Count) files plus manifest; no vendor binaries or business projects)."
