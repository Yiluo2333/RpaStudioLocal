param(
    [string]$RuntimeBase = (Join-Path $env:LOCALAPPDATA 'RpaStudioLocal'),
    [string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$framework = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue
$versions = @()
$versionsRoot = Join-Path $RuntimeBase 'Versions'
if (Test-Path -LiteralPath $versionsRoot) {
    $versions = @(Get-ChildItem -LiteralPath $versionsRoot -Directory | ForEach-Object {
        $version = $_
        # Public bundle manifests stay embedded in the EXE. Check known static inputs only.
        $commands = @(Get-ChildItem -LiteralPath (Join-Path $version.FullName 'CommandLibs') -Filter '*.dll' -File -Recurse -ErrorAction SilentlyContinue)
        [ordered]@{Id=$version.Name; HostPresent=(Test-Path -LiteralPath (Join-Path $version.FullName 'net461\RpaStudioLocal.exe')); CommandDlls=$commands.Count; VerificationPresent=(Test-Path -LiteralPath (Join-Path $version.FullName 'LocalConfig\verify.ok'))}
    })
}
$result = [ordered]@{
    DotNetRelease=if ($framework) {$framework.Release} else {$null}
    DotNet48Present=($null -ne $framework -and $framework.Release -ge 528040)
    OS64Bit=[Environment]::Is64BitOperatingSystem
    LauncherInstalled=(Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Programs\RpaStudioLocal\RpaStudioLocal.exe'))
    Runtimes=$versions
    IncludesAccountData=$false; IncludesBusinessData=$false; IncludesLogContents=$false
}
$json = $result | ConvertTo-Json -Depth 5
if ($OutputPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),$json,[Text.UTF8Encoding]::new($false)) }
$json
