param([string]$Version = '1.14.0')
$ErrorActionPreference = 'Stop'
$knownSha256 = @{
    '1.14.0' = '3ffb56267da14e287be48bd10cf7e6505260125bad940b75101fbb4d5d58e5d6'
}
if (-not $knownSha256.ContainsKey($Version)) {
    throw "No trusted checksum is bundled for sing-box $Version. Review and add the official SHA-256 before using it."
}
$root = $PSScriptRoot
$downloadDir = Join-Path $root 'downloads'
$binDir = Join-Path $root 'bin'
$archive = Join-Path $downloadDir "sing-box-$Version-windows-amd64.zip"
$extractDir = Join-Path $downloadDir "sing-box-$Version-extracted"
$url = "https://github.com/SagerNet/sing-box/releases/download/v$Version/sing-box-$Version-windows-amd64.zip"
New-Item -ItemType Directory -Force -Path $downloadDir, $binDir | Out-Null
Invoke-WebRequest -Uri $url -OutFile $archive
$actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $knownSha256[$Version]) {
    throw "Checksum mismatch for $archive. Expected $($knownSha256[$Version]), got $actual."
}
if (Test-Path -LiteralPath $extractDir) {
    Remove-Item -LiteralPath $extractDir -Recurse -Force
}
Expand-Archive -LiteralPath $archive -DestinationPath $extractDir
$packageDir = Join-Path $extractDir "sing-box-$Version-windows-amd64"
Copy-Item -LiteralPath (Join-Path $packageDir 'sing-box.exe') -Destination (Join-Path $binDir 'sing-box.exe') -Force
foreach ($name in @('libcronet.dll', 'LICENSE')) {
    $source = Join-Path $packageDir $name
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $binDir $name) -Force
    }
}
& (Join-Path $binDir 'sing-box.exe') version
Write-Output "Installed official sing-box $Version in $binDir"
