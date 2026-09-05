$ErrorActionPreference = 'Stop'
$taskName = 'NEU-IPv6-Inbound-Probe'
$probePath = Join-Path $PSScriptRoot 'Test-Inbound.ps1'
$oldUrlPath = Join-Path $PSScriptRoot 'private\campus-test-url.txt'
$oldUrl = if (Test-Path $oldUrlPath) { [IO.File]::ReadAllText($oldUrlPath) } else { '' }
Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {
    $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.Contains('"' + $probePath + '"')
} | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 1
$argument = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $probePath + '" -Minutes 15'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument -WorkingDirectory $PSScriptRoot
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Highest
$options = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 17)
Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $options -Force | Out-Null
Start-ScheduledTask -TaskName $taskName
for ($attempt = 0; $attempt -lt 15; $attempt++) {
    Start-Sleep -Seconds 1
    if ((Test-Path $oldUrlPath) -and [IO.File]::ReadAllText($oldUrlPath) -ne $oldUrl) {
        @{state='restarted';time=(Get-Date -Format o);new_url_generated=$true} | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot 'probe-restart-status.json')
        exit 0
    }
}
@{state='failed';time=(Get-Date -Format o);detail='No new URL generated; inspect inbound-test-status.json'} | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot 'probe-restart-status.json')
exit 1
