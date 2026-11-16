param(
    [Parameter(Mandatory=$true)][string]$Original,
    [switch]$Msi,
    [string]$WixDirectory
)
. (Join-Path $PSScriptRoot 'scripts\Common.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$originalRoot = (Resolve-Path -LiteralPath $Original).Path.TrimEnd('\')
foreach ($required in @('net461\RpaStudio.exe','net461\RpaService.dll','net461\RpaStudioUI.dll','CommandLibs\RpaFlowCommand','Version\version.json')) {
    if (!(Test-Path -LiteralPath (Join-Path $originalRoot $required))) { throw "Original installation is incomplete: $required" }
}
$version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
$originalVersion = (Get-Content -LiteralPath (Join-Path $originalRoot 'Version\version.json') -Raw | ConvertFrom-Json).StudioVersion
if ($originalVersion -ne '6.0.20230616.77') { throw "Unsupported original version: $originalVersion. Tested version: 6.0.20230616.77." }
$build = Join-Path $PSScriptRoot ('build\' + [Guid]::NewGuid().ToString('N'))
$payload = Join-Path $build 'payload'
$release = Join-Path $PSScriptRoot 'artifacts'
New-Item -ItemType Directory -Force -Path $payload,$release | Out-Null
$binaryExtensions = @('.dll','.exe','.config','.ico','.xls')
$assetExtensions = @('.bat','.json','.js','.html','.css','.png','.crx')
$privateExtensions = @('.db','.log','.pdb','.proj','.flow','.script','.zip','.nupkg')
foreach ($folder in @('net461','CommandLibs','Plugins','Languages','Resource','ThirdPart','Version')) {
    $source = Join-Path $originalRoot $folder
    if (!(Test-Path -LiteralPath $source)) { continue }
    Get-ChildItem -LiteralPath $source -File -Recurse | Where-Object {
        $_.FullName -notmatch '\\(log|logs|temp)\\' -and $_.Extension -notin $privateExtensions -and
        ($_.Extension -in $binaryExtensions -or
         ($folder -eq 'Plugins' -and $_.Extension -in $assetExtensions) -or
         $folder -in @('Languages','Resource','Version'))
    } | ForEach-Object {
        Copy-StaticFile $_.FullName (Join-Path $payload $_.FullName.Substring($originalRoot.Length + 1))
    }
}
Get-ChildItem -LiteralPath $originalRoot -File -Filter '*.dll' | ForEach-Object { Copy-StaticFile $_.FullName (Join-Path $payload $_.Name) }
& (Join-Path $PSScriptRoot 'scripts\Build-Host.ps1') -Runtime $payload
$staticFiles = @(Get-ChildItem -LiteralPath $payload -File -Recurse | Sort-Object FullName)
$manifest = $staticFiles | ForEach-Object {
    (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $_.FullName.Substring($payload.Length + 1).Replace('\','/')
}
[IO.File]::WriteAllLines((Join-Path $payload 'bundle.sha256'), [string[]]$manifest, [Text.UTF8Encoding]::new($false))
$zip = Join-Path $build 'runtime.zip'
New-PortableZip $payload $zip
$exe = Join-Path $release 'RpaStudioLocal.exe'
$icon = Join-Path $PSScriptRoot 'src\Shared\app.ico'
$iconArg = if (Test-Path -LiteralPath $icon) { @('/win32icon:' + $icon) } else { @() }
Invoke-Csc (@('/nologo','/target:winexe','/platform:x86','/optimize+','/reference:System.Core.dll','/reference:System.Windows.Forms.dll','/reference:System.IO.Compression.dll',('/resource:' + $zip + ',runtime.zip'),('/out:' + $exe)) + $iconArg + @((Join-Path $PSScriptRoot 'src\Launcher\BundleLauncher.cs'),(Join-Path $PSScriptRoot 'src\Shared\AssemblyInfo.cs')))
# Every distributed vendor DLL must match its source; also require all command DLLs.
$dlls = @(Get-ChildItem -LiteralPath $payload -Recurse -File -Filter '*.dll')
foreach ($file in $dlls) {
    $source = Join-Path $originalRoot $file.FullName.Substring($payload.Length + 1)
    if (!(Test-Path -LiteralPath $source) -or (Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $file.FullName).Hash) { throw "Vendor DLL mismatch: $($file.Name)" }
}
foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $originalRoot 'CommandLibs') -Recurse -File -Filter '*.dll')) {
    if (!(Test-Path -LiteralPath (Join-Path $payload $file.FullName.Substring($originalRoot.Length + 1)))) { throw "Missing command DLL: $($file.Name)" }
}
$originalFiles = @(Get-ChildItem -LiteralPath $originalRoot -Recurse -File)
$excluded = @($originalFiles | Where-Object { !(Test-Path -LiteralPath (Join-Path $payload $_.FullName.Substring($originalRoot.Length + 1))) })
$report = [ordered]@{
    Version=$version; OriginalVersion=$originalVersion
    OriginalFiles=$originalFiles.Count; OriginalBytes=($originalFiles | Measure-Object Length -Sum).Sum
    BundledFiles=$staticFiles.Count; PayloadBytes=(Get-ChildItem -LiteralPath $payload -Recurse -File | Measure-Object Length -Sum).Sum
    PayloadZipBytes=(Get-Item -LiteralPath $zip).Length
    ExecutableBytes=(Get-Item -LiteralPath $exe).Length; ExecutableSHA256=(Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant()
    OriginalDlls=$dlls.Count; ChangedOriginalDlls=0
    PluginAssets=@($staticFiles | Where-Object {$_.FullName -like '*\Plugins\*' -and $_.Extension -in $assetExtensions}).Count
    ExcludedFiles=$excluded.Count; ExcludedBytes=($excluded | Measure-Object Length -Sum).Sum
    ExcludedByExtension=@($excluded | Group-Object Extension | ForEach-Object { [ordered]@{Extension=$_.Name; Count=$_.Count; Bytes=($_.Group | Measure-Object Length -Sum).Sum} })
    PublicSourceContainsVendorBinaries=$false
}
Write-Utf8 (Join-Path $release 'build-report.json') ($report | ConvertTo-Json -Depth 5)
Copy-Item -LiteralPath (Join-Path $payload 'bundle.sha256') -Destination (Join-Path $release 'components.sha256') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'docs\USER-GUIDE.md') -Destination (Join-Path $release 'USER-GUIDE.md') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'THIRD-PARTY.md') -Destination (Join-Path $release 'THIRD-PARTY.md') -Force
if (Test-Path -LiteralPath $icon) { Copy-Item -LiteralPath $icon -Destination (Join-Path $release 'app.ico') -Force }
Write-Utf8 (Join-Path $release 'build-location.txt') $build
if ($Msi) { & (Join-Path $PSScriptRoot 'scripts\Build-Msi.ps1') -WixDirectory $WixDirectory }
Write-Output "Built $exe ($($report.ExecutableBytes) bytes); private staging: $build"
