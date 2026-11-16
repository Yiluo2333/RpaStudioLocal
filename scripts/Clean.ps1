param(
    [switch]$All
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$build = Join-Path $repo 'build'
if (!(Test-Path -LiteralPath $build)) {
    Write-Output "Build directory is already clean."
    return
}
$keep = $null
if (!$All -and (Test-Path -LiteralPath (Join-Path $repo 'artifacts\build-location.txt'))) {
    $keep = (Get-Content -LiteralPath (Join-Path $repo 'artifacts\build-location.txt') -Raw).Trim()
}
$removed = 0
$freedBytes = 0
Get-ChildItem -LiteralPath $build -Directory | ForEach-Object {
    if (!$All -and $keep -and $_.FullName -eq $keep) {
        Write-Output "Retaining current staging build: $($_.Name)"
        return
    }
    $size = (Get-ChildItem -LiteralPath $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    $removed++
    $freedBytes += $size
}
$freedMb = [math]::Round($freedBytes / 1MB, 2)
Write-Output "Cleaned $removed directories from $build ($freedMb MB freed)."
