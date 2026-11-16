param([string]$BuildDirectory)
. (Join-Path (Split-Path $PSScriptRoot) 'scripts\Common.ps1')
$repo = Split-Path $PSScriptRoot
if (!$BuildDirectory) { $BuildDirectory = Get-Content -LiteralPath (Join-Path $repo 'artifacts\build-location.txt') -Raw }
$payload = Join-Path $BuildDirectory 'payload'
if (!(Test-Path -LiteralPath (Join-Path $payload 'bundle.sha256'))) { throw 'Run Build.ps1 with the original installation first.' }
$test = Join-Path $repo ('build\host-test-' + [Guid]::NewGuid().ToString('N'))
$runtime = Join-Path $test 'runtime'
New-Item -ItemType Directory -Force -Path $runtime | Out-Null
Copy-Item -Path (Join-Path $payload '*') -Destination $runtime -Recurse -Force
& (Join-Path $repo 'scripts\Build-Host.ps1') -Runtime $runtime -Validation
$exe = Join-Path $runtime 'net461\RpaStudioLocal.Test.exe'
foreach ($mode in @('--verify','--verify-new','--verify-engine')) {
    $start = [Diagnostics.ProcessStartInfo]::new($exe,('--verify ' + $mode))
    $start.UseShellExecute = $false
    $start.WorkingDirectory = Split-Path $exe
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (!$process.WaitForExit(60000)) { $process.Kill(); throw "Host test timed out: $mode" }
    Write-Utf8 (Join-Path $test ($mode.TrimStart('-') + '.stdout.txt')) $stdout.Result
    Write-Utf8 (Join-Path $test ($mode.TrimStart('-') + '.stderr.txt')) $stderr.Result
    if ($process.ExitCode -ne 0) { throw "Host test failed: $mode. See $runtime\LocalConfig\host.log" }
}
$result = [ordered]@{
    ComponentLoad=(Get-Content -LiteralPath (Join-Path $runtime 'LocalConfig\verify.ok') -Raw)
    NewProject=(Get-Content -LiteralPath (Join-Path $runtime 'LocalConfig\new-project-verification.txt') -Raw).Trim()
    BasicEngine=(Get-Content -LiteralPath (Join-Path $runtime 'LocalConfig\engine-verification.txt') -Raw).Trim()
    BusinessProjectExecuted=$false
}
Write-Utf8 (Join-Path $repo 'artifacts\host-verification.json') ($result | ConvertTo-Json)
$result | ConvertTo-Json
