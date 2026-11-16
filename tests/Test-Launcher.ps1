. (Join-Path (Split-Path $PSScriptRoot) 'scripts\Common.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$repo = Split-Path $PSScriptRoot
$test = Join-Path $repo ('build\launcher-test-' + [Guid]::NewGuid().ToString('N'))
$payload = Join-Path $test 'payload'
New-Item -ItemType Directory -Force -Path (Join-Path $payload 'net461') | Out-Null
function Assert([bool]$Condition, [string]$Message) { if (!$Condition) { throw $Message } }
$stub = Join-Path $test 'Stub.cs'
Write-Utf8 $stub @'
using System; using System.IO; using System.Linq; using System.Text;
internal static class Stub {
    public static int Main(string[] args) {
        File.WriteAllLines(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"args.txt"), args.Select(x=>Convert.ToBase64String(Encoding.UTF8.GetBytes(x))));
        return 0;
    }
}
'@
Invoke-Csc @('/nologo','/target:winexe','/platform:x86','/reference:System.Core.dll',('/out:' + (Join-Path $payload 'net461\RpaStudioLocal.exe')),$stub)
Write-Utf8 (Join-Path $payload 'component.dat') 'component bytes for restoration test'
$manifest = Get-ChildItem -LiteralPath $payload -Recurse -File | ForEach-Object {
    (Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant() + '  ' + $_.FullName.Substring($payload.Length + 1).Replace('\','/')
}
[IO.File]::WriteAllLines((Join-Path $payload 'bundle.sha256'),[string[]]$manifest,[Text.UTF8Encoding]::new($false))
$zip = Join-Path $test 'runtime.zip'
New-PortableZip $payload $zip
function Build-TestLauncher([string]$Zip, [string]$Exe) {
    Invoke-Csc @('/nologo','/target:winexe','/platform:x86','/reference:System.Core.dll','/reference:System.Windows.Forms.dll','/reference:System.IO.Compression.dll',('/resource:' + $Zip + ',runtime.zip'),('/out:' + $Exe),(Join-Path $repo 'src\Launcher\BundleLauncher.cs'))
}
# Call the launcher directly; it performs the additional quoting when starting Host.
function Invoke-Launcher([string]$Exe) {
    $start = [Diagnostics.ProcessStartInfo]::new($Exe, '--verify "中文 路径.proj" "quote\"inside" "C:\trailing slash\\"')
    $start.UseShellExecute = $false
    $process = [Diagnostics.Process]::Start($start)
    if (!$process.WaitForExit(60000)) { $process.Kill(); throw 'Launcher timed out.' }
    if ($process.ExitCode -ne 0) { throw "Launcher returned $($process.ExitCode)" }
}
$exe = Join-Path $test 'Launcher.exe'
Build-TestLauncher $zip $exe
$savedRuntime = $env:RPA_LOCAL_RUNTIME
try {
    $env:RPA_LOCAL_RUNTIME = Join-Path $test '用户 测试环境'
    Invoke-Launcher $exe
    $check = Get-Content -LiteralPath (Join-Path $env:RPA_LOCAL_RUNTIME 'last-check.txt')
    Assert ($check -contains 'VerifiedFiles=2') 'Unexpected manifest count.'
    Assert ($check -contains 'RestoredFiles=2') 'First extraction failed.'
    $root = ($check | Where-Object {$_ -like 'Runtime=*'}).Substring(8)
    $actual = @(Get-Content -LiteralPath (Join-Path $root 'net461\args.txt') | ForEach-Object {[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_))})
    $expected = @('--verify','中文 路径.proj','quote"inside','C:\trailing slash\')
    Assert ($actual.Count -eq $expected.Count) 'Argument count changed.'
    for ($i=0; $i -lt $expected.Count; $i++) { Assert ($actual[$i] -ceq $expected[$i]) "Argument $i changed." }
    Write-Utf8 (Join-Path $root 'Scripts\keep-project.txt') 'user project marker'
    Write-Utf8 (Join-Path $root 'component.dat') 'corrupted'
    Invoke-Launcher $exe
    $check = Get-Content -LiteralPath (Join-Path $env:RPA_LOCAL_RUNTIME 'last-check.txt')
    Assert ($check -contains 'RestoredFiles=1') 'Corrupt component was not restored.'
    Assert ((Get-Content -LiteralPath (Join-Path $root 'Scripts\keep-project.txt') -Raw) -ceq 'user project marker') 'User project was changed.'
    Remove-Item -LiteralPath (Join-Path $root 'component.dat')
    Invoke-Launcher $exe
    Assert ((Get-Content -LiteralPath (Join-Path $env:RPA_LOCAL_RUNTIME 'last-check.txt')) -contains 'RestoredFiles=1') 'Missing component was not restored.'
    Invoke-Launcher $exe
    Assert ((Get-Content -LiteralPath (Join-Path $env:RPA_LOCAL_RUNTIME 'last-check.txt')) -contains 'RestoredFiles=0') 'Unchanged files should not be replaced.'
    $badPayload = Join-Path $test 'bad-payload'
    New-Item -ItemType Directory -Force -Path $badPayload | Out-Null
    Write-Utf8 (Join-Path $badPayload 'bundle.sha256') (('0' * 64) + '  ../outside.txt')
    $badZip = Join-Path $test 'bad.zip'
    New-PortableZip $badPayload $badZip
    $badExe = Join-Path $test 'BadLauncher.exe'
    Build-TestLauncher $badZip $badExe
    $start = [Diagnostics.ProcessStartInfo]::new($badExe, '--verify')
    $start.UseShellExecute = $false
    $process = [Diagnostics.Process]::Start($start)
    if (!$process.WaitForExit(60000)) { $process.Kill(); throw 'Invalid bundle test timed out.' }
    Assert ($process.ExitCode -ne 0) 'Path traversal was not rejected.'
    Assert (!(Test-Path -LiteralPath (Join-Path $env:RPA_LOCAL_RUNTIME 'Versions\outside.txt'))) 'Path traversal wrote outside runtime.'
    Write-Output 'PASS: extraction, Unicode/quoted arguments, corruption and missing-file repair, unchanged files, project preservation, path traversal rejection.'
} finally { $env:RPA_LOCAL_RUNTIME = $savedRuntime }
