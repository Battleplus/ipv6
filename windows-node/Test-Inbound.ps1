param([ValidateRange(1,30)][int]$Minutes = 15)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this connectivity test as administrator.' }
$settings = Get-Content -Raw -LiteralPath (Join-Path $root 'private\settings.json') | ConvertFrom-Json
$ruleName = 'NEU-IPv6-Temporary-Probe'
$statusPath = Join-Path $root 'inbound-test-status.json'
$token = [Guid]::NewGuid().ToString('N')
$listener = $null
$ruleCreated = $false
function Save-Status($State, $Detail) {
    @{time=(Get-Date -Format o);state=$State;detail=$Detail;port=$settings.port} | ConvertTo-Json |
        Set-Content -LiteralPath $statusPath -Encoding UTF8
}
try {
    if (Get-NetTCPConnection -State Listen -LocalPort $settings.port -ErrorAction SilentlyContinue) { throw 'The test port is already listening; do not start another probe.' }
    if (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue) { Remove-NetFirewallRule -Name $ruleName }
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Parse($settings.address), [int]$settings.port)
    $listener.Server.DualMode = $false
    $listener.Start(8)
    New-NetFirewallRule -Name $ruleName -DisplayName 'NEU IPv6 temporary connectivity test' -Direction Inbound -Action Allow -Protocol TCP -LocalPort $settings.port -LocalAddress $settings.address -RemoteAddress '2000::/3' -InterfaceAlias $settings.interface -Program (Get-Process -Id $PID).Path -Profile Any | Out-Null
    $ruleCreated = $true
    $url = 'http://[' + $settings.address + ']:' + $settings.port + '/' + $token
    [IO.File]::WriteAllText((Join-Path $root 'private\campus-test-url.txt'),$url)
    $html = '<!doctype html><html lang="zh-CN"><meta charset="UTF-8"><title>校园 IPv6 入站测试</title><body style="font-family:system-ui;max-width:800px;margin:50px auto;padding:20px"><h1>校园 IPv6 入站测试</h1><p>将下面的地址私下发送到校园 Wi-Fi 下的手机，在浏览器中打开。请临时关闭手机现有 VPN，并关闭蜂窝数据，确保通过校园 Wi-Fi 测试。</p><p>这个地址只能验证连通性，不包含代理密码；15 分钟后失效。请勿公开发布。</p><p style="overflow-wrap:anywhere"><a href="' + $url + '">' + $url + '</a></p><p>成功时页面显示 NEU IPv6 inbound OK。不要用这台节点电脑自己打开来代替校园测试。</p></body></html>'
    [IO.File]::WriteAllText((Join-Path $root 'private\campus-test.html'),$html,(New-Object Text.UTF8Encoding $false))
    Save-Status 'listening' 'Waiting for a browser request from campus Wi-Fi; expires automatically.'
    $deadline = (Get-Date).AddMinutes($Minutes)
    $hit = $false
    while ((Get-Date) -lt $deadline -and -not $hit) {
        if (-not $listener.Pending()) { Start-Sleep -Milliseconds 200; continue }
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $stream.ReadTimeout = 2000
            $stream.WriteTimeout = 2000
            $buffer = New-Object byte[] 4096
            $count = $stream.Read($buffer,0,$buffer.Length)
            $request = [Text.Encoding]::ASCII.GetString($buffer,0,$count)
            if ($request.StartsWith('GET /' + $token + ' HTTP/')) {
                $remote = $client.Client.RemoteEndPoint.Address.ToString()
                $localAddresses = @(Get-NetIPAddress -AddressFamily IPv6 | Select-Object -ExpandProperty IPAddress)
                $samePrefix = ($remote.Split(':')[0..3] -join ':') -eq ($settings.address.Split(':')[0..3] -join ':')
                $externalCandidate = $remote -match '^[23]' -and $remote -notin $localAddresses -and -not $samePrefix
                $body = if ($externalCandidate) { 'NEU IPv6 inbound OK. Please confirm this test used campus Wi-Fi.' } else { 'Connection OK, but this appears local. Please retry from campus Wi-Fi.' }
                $response = "HTTP/1.1 200 OK`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $([Text.Encoding]::UTF8.GetByteCount($body))`r`nConnection: close`r`n`r`n$body"
                $bytes = [Text.Encoding]::UTF8.GetBytes($response)
                $stream.Write($bytes,0,$bytes.Length)
                if ($externalCandidate) {
                    $evidence = @{time=(Get-Date -Format o);state='external_request_received';campus_confirmed=$false;source_prefix=(($remote.Split(':')[0..2] -join ':') + ':…');port=$settings.port}
                    $evidence | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'inbound-evidence.json') -Encoding UTF8
                    $hit = $true
                }
            }
        } catch { } finally { $client.Dispose() }
    }
    if ($hit) { Save-Status 'external_request_received' 'External request received. Confirm campus Wi-Fi before activating the node.' }
    else { Save-Status 'expired' 'No qualifying external request received before timeout.' }
} catch {
    Save-Status 'failed' $_.Exception.Message
    throw
} finally {
    if ($null -ne $listener) { $listener.Stop() }
    if ($ruleCreated) { Remove-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue }
}
