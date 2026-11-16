$ErrorActionPreference = 'Stop'
function Write-Utf8([string]$Path, [string]$Content) {
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}
function Get-Csc {
    $path = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
    if (!(Test-Path -LiteralPath $path)) { throw '.NET Framework C# compiler was not found. Install .NET Framework 4.8.' }
    return $path
}
function Invoke-Csc([string[]]$Arguments) {
    & (Get-Csc) @Arguments
    if ($LASTEXITCODE -ne 0) { throw "C# compilation failed ($LASTEXITCODE)." }
}
function Copy-StaticFile([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Destination) | Out-Null
    # Do not inherit per-file download zone metadata into locally built components.
    [IO.File]::WriteAllBytes($Destination, [IO.File]::ReadAllBytes($Source))
}
function New-PortableZip([string]$SourceDirectory, [string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $sourceRoot = [IO.Path]::GetFullPath($SourceDirectory).TrimEnd('\')
    $stream = [IO.File]::Open($Destination,[IO.FileMode]::CreateNew)
    try {
        $archive = [IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
        try {
            foreach ($file in (Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | Sort-Object FullName)) {
                # .NET Framework's CreateFromDirectory uses backslashes, unlike modern .NET.
                $name = $file.FullName.Substring($sourceRoot.Length + 1).Replace('\','/')
                $entry = $archive.CreateEntry($name,[IO.Compression.CompressionLevel]::Optimal)
                $inputStream = [IO.File]::OpenRead($file.FullName)
                $outputStream = $entry.Open()
                try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose(); $inputStream.Dispose() }
            }
        } finally { $archive.Dispose() }
    } finally { $stream.Dispose() }
}
