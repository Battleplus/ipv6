$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'bin\sing-box.exe'
$serverProcess = $null
$clientProcess = $null
try {
    if (Get-NetTCPConnection -State Listen -LocalPort 17896 -ErrorAction SilentlyContinue) { throw 'Local test port 17896 is already in use.' }
    $serverProcess = Start-Process -FilePath $exe -ArgumentList @('run','-c',('"' + (Join-Path $PSScriptRoot 'private\selftest-server.json') + '"')) -WindowStyle Hidden -PassThru
    $clientProcess = Start-Process -FilePath $exe -ArgumentList @('run','-c',('"' + (Join-Path $PSScriptRoot 'private\selftest-client.json') + '"')) -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 2
    if ($serverProcess.HasExited -or $clientProcess.HasExited) { throw 'Test process exited. See selftest logs.' }
    $result = & curl.exe --noproxy 'localhost,127.0.0.1,::1' --proxy 'socks5h://127.0.0.1:17896' --connect-timeout 10 --max-time 20 -sS -o NUL -w '%{http_code}' 'https://www.baidu.com'
    if ($LASTEXITCODE -ne 0 -or $result -ne '200') { throw "Encrypted proxy test failed (HTTP $result)." }
    $control = [Net.Sockets.TcpClient]::new('127.0.0.1',17896)
    $udp = [Net.Sockets.UdpClient]::new(0)
    try {
        $stream = $control.GetStream()
        $stream.ReadTimeout = 5000
        function Read-Exactly([int]$Length) {
            $bytes = New-Object byte[] $Length
            $offset = 0
            while ($offset -lt $Length) {
                $n = $stream.Read($bytes,$offset,$Length-$offset)
                if ($n -eq 0) { throw 'Unexpected SOCKS response EOF' }
                $offset += $n
            }
            return ,$bytes
        }
        $greeting = [byte[]]@(5,1,0)
        $stream.Write($greeting,0,$greeting.Length)
        $reply = Read-Exactly 2
        if ($reply[0] -ne 5 -or $reply[1] -ne 0) { throw 'SOCKS negotiation failed' }
        $associate = [byte[]]@(5,3,0,1,0,0,0,0,0,0)
        $stream.Write($associate,0,$associate.Length)
        $header = Read-Exactly 4
        if ($header[1] -ne 0 -or $header[3] -ne 1) { throw 'SOCKS UDP associate failed or unexpected address family' }
        $bound = Read-Exactly 6
        $udpPort = [int]$bound[4]*256 + [int]$bound[5]
        $dns = [byte[]]@(0x6e,0x75,1,0,0,1,0,0,0,0,0,0,7,101,120,97,109,112,108,101,3,99,111,109,0,0,1,0,1)
        $packet = [byte[]](@(0,0,0,1,223,5,5,5,0,53) + $dns)
        $udp.Client.ReceiveTimeout = 7000
        $udp.Connect('127.0.0.1',$udpPort)
        [void]$udp.Send($packet,$packet.Length)
        $peer = [Net.IPEndPoint]::new([Net.IPAddress]::Any,0)
        $response = $udp.Receive([ref]$peer)
        if ($response.Length -lt 22 -or $response[3] -ne 1 -or $response[10] -ne 0x6e -or $response[11] -ne 0x75 -or ($response[12] -band 128) -eq 0 -or ($response[13] -band 15) -ne 0) { throw 'Encrypted UDP DNS test failed' }
    } finally { $udp.Dispose(); $control.Dispose() }
    [pscustomobject]@{time=(Get-Date -Format o);test='IPv6 loopback -> Shadowsocks 2022 -> WLAN IPv4 HTTPS and UDP DNS';http_status=200;udp_dns='passed';external_inbound_verified=$false} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'local-test-result.json') -Encoding UTF8
    Write-Output 'PASS: IPv6 encrypted TCP + UDP proxy, WLAN IPv4 HTTPS (HTTP 200) and UDP DNS. External inbound still requires a campus test.'
} finally {
    foreach ($process in @($clientProcess,$serverProcess)) {
        if ($null -ne $process -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    }
}
