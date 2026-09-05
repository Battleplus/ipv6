$ErrorActionPreference = 'Stop'
$dir = Join-Path $PSScriptRoot 'private'
$log = Join-Path $dir 'capture-control.txt'
$settings = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'private\settings.json') | ConvertFrom-Json
$filter = 'NEU-Probe-' + $settings.port
$started = $false
$added = $false
try {
    & pktmon.exe status 2>&1 | Out-File $log
    & pktmon.exe filter list 2>&1 | Out-File $log -Append
    & pktmon.exe filter add $filter -d IPv6 -t TCP -p $settings.port 2>&1 | Out-File $log -Append
    if ($LASTEXITCODE -ne 0) { throw 'Cannot add diagnostic filter' }
    $added = $true
    & pktmon.exe start --capture --comp nics --pkt-size 80 --file-size 8 --file-name (Join-Path $dir 'probe-packets.etl') 2>&1 | Out-File $log -Append
    if ($LASTEXITCODE -ne 0) { throw 'Cannot start capture; another capture may already be active' }
    $started = $true
    @{state='capturing';start=(Get-Date -Format o);seconds=90} | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot 'capture-status.json')
    Start-Sleep -Seconds 90
} finally {
    if ($started) {
        & pktmon.exe stop 2>&1 | Out-File $log -Append
        & pktmon.exe etl2txt (Join-Path $dir 'probe-packets.etl') --out (Join-Path $dir 'probe-packets.txt') --brief 2>&1 | Out-File $log -Append
    }
    if ($added) { & pktmon.exe filter remove $filter 2>&1 | Out-File $log -Append }
    @{state='finished';time=(Get-Date -Format o)} | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot 'capture-status.json')
}
