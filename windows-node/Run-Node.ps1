$ErrorActionPreference = 'Stop'
$mutex = [Threading.Mutex]::new($false, 'Local\NEU-IPv6-Windows-Node')
if (-not $mutex.WaitOne(0)) { $mutex.Dispose(); exit 0 }
$exe = Join-Path $PSScriptRoot 'bin\sing-box.exe'
$process = $null
try {
    & (Join-Path $PSScriptRoot 'Configure.ps1')
    $settings = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'private\settings.json') | ConvertFrom-Json
    $process = Start-Process -FilePath $exe -ArgumentList @('run','-c',('"' + (Join-Path $PSScriptRoot 'private\server.json') + '"')) -WindowStyle Hidden -PassThru
    @{pid=$process.Id;started=(Get-Date -Format o)} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'node-process.json') -Encoding UTF8
    while (-not $process.WaitForExit(30000)) {
        $stillPresent = Get-NetIPAddress -InterfaceAlias $settings.interface -AddressFamily IPv6 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -eq $settings.address -and $_.AddressState -eq 'Preferred' }
        if (-not $stillPresent) { throw 'Public IPv6 changed or WLAN disconnected. Reconfigure firewall/client address and restart the node.' }
    }
    if ($process.ExitCode -ne 0) { throw "sing-box exited with code $($process.ExitCode)" }
} catch {
    @{time=(Get-Date -Format o);error=$_.Exception.Message} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'node-error.json') -Encoding UTF8
    exit 1
} finally {
    if ($null -ne $process -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
