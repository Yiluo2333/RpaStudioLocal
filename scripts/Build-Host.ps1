param(
    [Parameter(Mandatory=$true)][string]$Runtime,
    [switch]$Validation
)
. (Join-Path $PSScriptRoot 'Common.ps1')
$repo = Split-Path $PSScriptRoot
$bin = Join-Path $Runtime 'net461'
$refs = @('RpaService','RpaModel','RpaResource','RpaStudioShare','RpaStudioUI','RpaUI') | ForEach-Object { '/reference:' + (Join-Path $bin ($_ + '.dll')) }
$wpf = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\WPF'
$refs += @('PresentationFramework','PresentationCore','WindowsBase') | ForEach-Object { '/reference:' + (Join-Path $wpf ($_ + '.dll')) }
$sources = @((Join-Path $repo 'src\Host\LocalHost.cs'), (Join-Path $repo 'src\Shared\AssemblyInfo.cs'))
$options = @()
$name = 'RpaStudioLocal.exe'
if ($Validation) {
    $name = 'RpaStudioLocal.Test.exe'
    $sources += Join-Path $repo 'tests\LocalVerification.cs'
    $refs += @('RpaUtil','Newtonsoft.Json') | ForEach-Object { '/reference:' + (Join-Path $bin ($_ + '.dll')) }
    $options += '/define:VALIDATION'
}
Invoke-Csc (@('/nologo','/target:winexe','/platform:x86','/optimize+','/reference:System.Core.dll','/reference:System.Xaml.dll',('/out:' + (Join-Path $bin $name))) + $refs + $options + $sources)
Copy-Item -LiteralPath (Join-Path $bin 'RpaStudio.exe.config') -Destination (Join-Path $bin ($name + '.config')) -Force
