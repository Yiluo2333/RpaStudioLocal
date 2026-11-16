param([string]$Msi)
. (Join-Path (Split-Path $PSScriptRoot) 'scripts\Common.ps1')
$repo = Split-Path $PSScriptRoot
if (!$Msi) { $Msi = Join-Path $repo ('artifacts\RpaStudioLocal-' + (Get-Content (Join-Path $repo 'VERSION') -Raw).Trim() + '-x86.msi') }
$Msi = (Resolve-Path -LiteralPath $Msi).Path
function Assert([bool]$Condition, [string]$Message) { if (!$Condition) { throw $Message } }
# This test installs and uninstalls the package for the current user. Never replace an existing installation.
$existing = @(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName -eq 'RPA 本地版'})
$menu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\RPA 本地版\RPA 本地版.lnk'
$desktop = Join-Path ([Environment]::GetFolderPath('Desktop')) 'RPA 本地版.lnk'
if ($existing.Count -gt 0 -or (Test-Path -LiteralPath $menu) -or (Test-Path -LiteralPath $desktop)) { throw 'Use a clean test account: an existing RPA Local installation or shortcut was found.' }
$test = Join-Path $repo ('build\msi-test-' + [Guid]::NewGuid().ToString('N'))
$install = Join-Path $test 'installed app'
$runtime = Join-Path $test 'runtime'
New-Item -ItemType Directory -Force -Path $test | Out-Null
$installer = New-Object -ComObject WindowsInstaller.Installer
$database = $installer.OpenDatabase($Msi,0)
$view = $database.OpenView('SELECT `Value` FROM `Property` WHERE `Property` = ''ProductCode''')
$view.Execute()
$record = $view.Fetch()
$productCode = $record.StringData(1)
$view.Close()
function Invoke-Msi([string]$Arguments, [string]$LogName) {
    $start = [Diagnostics.ProcessStartInfo]::new((Join-Path $env:WINDIR 'System32\msiexec.exe'), ($Arguments + ' /qn /norestart /l*v "' + (Join-Path $test $LogName) + '"'))
    $start.UseShellExecute = $false
    $process = [Diagnostics.Process]::Start($start)
    if (!$process.WaitForExit(60000)) { throw "MSI operation exceeded 60 seconds; inspect $test before proceeding." }
    if ($process.ExitCode -notin @(0,3010)) { throw "MSI returned $($process.ExitCode). See $test\$LogName" }
}
$installedByTest = $false
$savedRuntime = $env:RPA_LOCAL_RUNTIME
try {
    Invoke-Msi ('/i "' + $Msi + '" INSTALLFOLDER="' + $install + '"') 'install.log'
    $installedByTest = $true
    $exe = Join-Path $install 'RpaStudioLocal.exe'
    Assert (Test-Path -LiteralPath $exe) 'Installed launcher is missing.'
    Assert ((Get-FileHash -LiteralPath $exe).Hash -eq (Get-FileHash -LiteralPath (Join-Path $repo 'artifacts\RpaStudioLocal.exe')).Hash) 'Installed launcher bytes differ.'
    Assert ((Test-Path -LiteralPath $menu) -and (Test-Path -LiteralPath $desktop)) 'Shortcuts are missing.'
    $shell = New-Object -ComObject WScript.Shell
    Assert ($shell.CreateShortcut($menu).TargetPath -eq $exe) 'Menu shortcut target is incorrect.'
    Assert ($shell.CreateShortcut($desktop).TargetPath -eq $exe) 'Desktop shortcut target is incorrect.'
    $env:RPA_LOCAL_RUNTIME = $runtime
    $start = [Diagnostics.ProcessStartInfo]::new($exe,'--verify')
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($start)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (!$process.WaitForExit(60000)) { $process.Kill(); throw 'Installed launcher verification timed out.' }
    Write-Utf8 (Join-Path $test 'launcher.stdout.txt') $stdout.Result
    Write-Utf8 (Join-Path $test 'launcher.stderr.txt') $stderr.Result
    Assert ($process.ExitCode -eq 0) 'Installed launcher did not load the original components.'
    $check = Get-Content -LiteralPath (Join-Path $runtime 'last-check.txt')
    $runtimeRoot = ($check | Where-Object {$_ -like 'Runtime=*'}).Substring(8)
    $marker = Join-Path $runtimeRoot 'Scripts\uninstall-preservation.txt'
    Write-Utf8 $marker 'user project preservation marker'
    # Only remove the single launcher installed inside this test's validated folder.
    Assert ([IO.Path]::GetFullPath($exe).StartsWith([IO.Path]::GetFullPath($test) + '\',[StringComparison]::OrdinalIgnoreCase)) 'Unsafe repair-test path.'
    Remove-Item -LiteralPath $exe
    Invoke-Msi ('/fa ' + $productCode) 'repair.log'
    Assert (Test-Path -LiteralPath $exe) 'MSI repair did not restore the launcher.'
    Invoke-Msi ('/x ' + $productCode) 'uninstall.log'
    $installedByTest = $false
    Assert (!(Test-Path -LiteralPath $exe)) 'Uninstall left the installed launcher.'
    Assert (!(Test-Path -LiteralPath $menu) -and !(Test-Path -LiteralPath $desktop)) 'Uninstall left shortcuts.'
    Assert ((Get-Content -LiteralPath $marker -Raw) -eq 'user project preservation marker') 'Uninstall removed runtime project data.'
    $result = [ordered]@{Install='PASS'; InstalledComponentLoad='PASS'; DesktopAndMenuShortcuts='PASS'; Repair='PASS'; Uninstall='PASS'; RuntimeProjectPreserved=$true; ComponentCheck=@($check | Where-Object {$_ -notlike 'Runtime=*'}); MSI_SHA256=(Get-FileHash -LiteralPath $Msi).Hash.ToLowerInvariant(); ProductCode=$productCode}
    Write-Utf8 (Join-Path $repo 'artifacts\msi-verification.json') ($result | ConvertTo-Json -Depth 4)
    $result | ConvertTo-Json -Depth 4
} finally {
    $env:RPA_LOCAL_RUNTIME = $savedRuntime
    if ($installedByTest) { Invoke-Msi ('/x ' + $productCode) 'cleanup-uninstall.log' }
}
