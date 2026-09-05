$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run rollback as administrator.' }
Stop-ScheduledTask -TaskName 'NEU-IPv6-Node' -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'NEU-IPv6-Node' -Confirm:$false -ErrorAction SilentlyContinue
$exe = Join-Path $PSScriptRoot 'bin\sing-box.exe'
Get-Process -Name 'sing-box' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe } | Stop-Process
foreach ($name in @('NEU-IPv6-Node-TCP','NEU-IPv6-Node-UDP','NEU-IPv6-Temporary-Probe')) {
    Remove-NetFirewallRule -Name $name -ErrorAction SilentlyContinue
}
@{time=(Get-Date -Format o);state='stopped'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'activation-status.json') -Encoding UTF8
Write-Output 'Node stopped; this setup''s task and firewall rules removed. Private configurations retained.'
