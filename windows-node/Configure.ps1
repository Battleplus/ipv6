param([string]$InterfaceAlias = 'WLAN')
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$private = Join-Path $root 'private'
$logs = Join-Path $root 'logs'
New-Item -ItemType Directory -Force -Path $private, $logs | Out-Null
$exe = Join-Path $root 'bin\sing-box.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw 'sing-box is not installed. Run Install.ps1 first.' }
function Save-Json($Object, $Path) {
    $json = ConvertTo-Json -InputObject $Object -Depth 30
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding $false))
}
$address = Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv6 |
    Where-Object { $_.IPAddress -match '^[23]' -and $_.PrefixLength -eq 64 -and $_.AddressState -eq 'Preferred' } |
    Select-Object -First 1 -ExpandProperty IPAddress
if (-not $address) { throw 'No preferred non-temporary public IPv6 on the selected interface.' }
$settingsPath = Join-Path $private 'settings.json'
if (Test-Path -LiteralPath $settingsPath) {
    $settings = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
    $settings.address = $address
    $settings.interface = $InterfaceAlias
} else {
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $keyBytes = New-Object byte[] 32
    $rng.GetBytes($keyBytes)
    $rng.Dispose()
    do { $port = Get-Random -Minimum 30000 -Maximum 45000 }
    while ((Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue) -or (Get-NetUDPEndpoint -LocalPort $port -ErrorAction SilentlyContinue))
    $settings = [pscustomobject]@{address=$address; interface=$InterfaceAlias; port=$port; method='2022-blake3-aes-256-gcm'; password=[Convert]::ToBase64String($keyBytes)}
}
Save-Json $settings $settingsPath
$server = @{
    log=@{level='warn';timestamp=$true;output=(Join-Path $root 'logs\server.log')}
    dns=@{servers=@(@{type='udp';tag='dns-wlan';server='223.5.5.5';bind_interface=$InterfaceAlias});strategy='ipv4_only'}
    inbounds=@(@{type='shadowsocks';tag='campus-in';listen=$address;listen_port=$settings.port;method=$settings.method;password=$settings.password})
    outbounds=@(@{type='direct';tag='internet';bind_interface=$InterfaceAlias;domain_resolver=@{server='dns-wlan';strategy='ipv4_only'}})
    route=@{rules=@(@{action='resolve';strategy='ipv4_only'},@{ip_is_private=$true;action='reject'},@{ip_cidr=@('100.64.0.0/10','224.0.0.0/4','240.0.0.0/4');action='reject'});final='internet';default_domain_resolver='dns-wlan'}
}
Save-Json $server (Join-Path $private 'server.json')
$server.inbounds[0].listen = '::1'
$server.log.output = Join-Path $root 'logs\selftest-server.log'
Save-Json $server (Join-Path $private 'selftest-server.json')
$proxy = @{type='shadowsocks';tag='campus-node';server=$address;server_port=$settings.port;method=$settings.method;password=$settings.password}
$mobile = @{
    log=@{level='warn';timestamp=$true}
    dns=@{servers=@(@{type='udp';tag='remote-dns';server='223.5.5.5';detour='campus-node'});strategy='ipv4_only'}
    inbounds=@(@{type='tun';tag='tun-in';address=@('172.31.255.1/30','fd00:abcd:1234::1/126');auto_route=$true;strict_route=$true;stack='mixed'})
    outbounds=@($proxy,@{type='direct';tag='direct'})
    route=@{auto_detect_interface=$true;rules=@(@{action='sniff'},@{protocol='dns';action='hijack-dns'},@{ip_is_private=$true;action='route';outbound='direct'});final='campus-node';default_domain_resolver='remote-dns'}
}
Save-Json $mobile (Join-Path $private 'phone-sing-box.json')
$localProxy = @{} + $proxy
$localProxy.server = '::1'
$localClient = @{log=@{level='warn';output=(Join-Path $root 'logs\selftest-client.log')};inbounds=@(@{type='mixed';listen='127.0.0.1';listen_port=17896});outbounds=@($localProxy);route=@{final='campus-node'}}
Save-Json $localClient (Join-Path $private 'selftest-client.json')
$yaml = @"
mixed-port: 7897
allow-lan: false
mode: rule
log-level: warning
ipv6: true
dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  respect-rules: true
  proxy-server-nameserver:
    - 'https://[2400:3200::1]/dns-query'
  nameserver:
    - 'https://223.5.5.5/dns-query'
proxies:
  - name: Campus-IPv6-Node
    type: ss
    server: '$address'
    port: $($settings.port)
    cipher: $($settings.method)
    password: '$($settings.password)'
    udp: true
proxy-groups:
  - name: CAMPUS
    type: select
    proxies: [Campus-IPv6-Node]
rules:
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR6,fc00::/7,DIRECT,no-resolve
  - IP-CIDR6,fe80::/10,DIRECT,no-resolve
  - MATCH,CAMPUS
"@
[IO.File]::WriteAllText((Join-Path $private 'tablet-mihomo.yaml'),$yaml,(New-Object Text.UTF8Encoding $false))
$uri = 'ss://' + [Uri]::EscapeDataString($settings.method) + ':' + [Uri]::EscapeDataString($settings.password) + '@[' + $address + ']:' + $settings.port + '#Campus-IPv6-Node'
[IO.File]::WriteAllText((Join-Path $private 'phone-import.txt'),$uri,(New-Object Text.UTF8Encoding $false))
foreach ($name in @('server.json','selftest-server.json','selftest-client.json','phone-sing-box.json')) {
    & $exe check -c (Join-Path $private $name)
    if ($LASTEXITCODE -ne 0) { throw "Configuration check failed: $name" }
}
Write-Output "Configurations checked. Node port: $($settings.port). Private files saved locally."
