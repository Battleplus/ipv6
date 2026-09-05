param([switch]$CampusTestConfirmed)
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run activation as administrator.' }
if (-not $CampusTestConfirmed -or -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'inbound-evidence.json'))) { throw 'Complete the external probe and confirm campus Wi-Fi before activating.' }
& (Join-Path $PSScriptRoot 'Configure.ps1')
$settings = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'private\settings.json') | ConvertFrom-Json
$exe = Join-Path $PSScriptRoot 'bin\sing-box.exe'
$account = (Get-Acl -LiteralPath $PSScriptRoot).Owner
$taskName = 'NEU-IPv6-Node'
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) { throw 'Node task already exists. Use Stop-Node.ps1 before reactivation.' }
if (Get-NetFirewallRule -Name 'NEU-IPv6-Node-*' -ErrorAction SilentlyContinue) { throw 'Node firewall rules already exist. Use Stop-Node.ps1 before reactivation.' }
$added = @()
try {
    foreach ($protocol in @('TCP','UDP')) {
        $name = 'NEU-IPv6-Node-' + $protocol
        New-NetFirewallRule -Name $name -DisplayName ('NEU IPv6 node ' + $protocol) -Direction Inbound -Action Allow -Protocol $protocol -LocalPort $settings.port -LocalAddress $settings.address -RemoteAddress '2000::/3' -InterfaceAlias $settings.interface -Program $exe -Profile Any | Out-Null
        $added += $name
    }
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $PSScriptRoot 'Run-Node.ps1') + '"') -WorkingDirectory $PSScriptRoot
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $account
    $principal = New-ScheduledTaskPrincipal -UserId $account -LogonType Interactive -RunLevel Limited
    $options = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $options -Description 'Personal IPv6 node; starts after the owner logs in, with ordinary user privileges.' | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Start-Sleep -Seconds 5
    if (-not (Get-NetTCPConnection -State Listen -LocalAddress $settings.address -LocalPort $settings.port -ErrorAction SilentlyContinue)) { throw 'Node failed to start; see logs.' }
    @{time=(Get-Date -Format o);state='active';port=$settings.port;startup='owner-logon';campus_probe_confirmed=$true} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'activation-status.json') -Encoding UTF8
    Write-Output 'Node activated. Starts on owner logon, not before login. Import the private client configuration on the campus device.'
} catch {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Get-Process -Name 'sing-box' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe } | Stop-Process -ErrorAction SilentlyContinue
    foreach ($name in $added) { Remove-NetFirewallRule -Name $name -ErrorAction SilentlyContinue }
    throw
}
