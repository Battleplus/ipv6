# 校园服务器 + WARP 部署记录（2026-09-07）

## 当前结论

已在一台校园 Linux 服务器上打通以下链路：

```text
校园手机／平板代理客户端
    → 校园 IPv6
    → 校园 Linux 服务器上的 sing-box
    → 服务器本机 WARP SOCKS5
    → WARP 通过校园 IPv6 连接 Cloudflare
    → Cloudflare IPv4 出口
    → IPv4 互联网
```

手机通过节点访问 IPv4 地址查询服务时，返回了 Cloudflare 的 IPv4 出口地址。服务器同时观察到 WARP 的活动套接字以校园全球单播 IPv6 为源地址、Cloudflare IPv6 为目标地址。这两项证据共同证明本次测试请求经过了预期链路。

该结果只证明技术链路成立，不证明学校当前或未来一定不计费。校园账户计费仍需按 [验收清单](acceptance-checklist.md) 做受控 A/B 测试。

## 2026-09-08 复测更新

当前已恢复并保留本页记录的原始安全配置：Shadowsocks 仅监听 TCP，所有代理业务出站继续指向 WARP 本地 SOCKS5。复测期间增加过的 UDP、备用端口、临时 HTTP 测试服务和健康检查均已撤销。

本次复测得到以下新结论：

- 校园 Android 设备曾从校园全球单播 IPv6 成功连接服务器并取得 Cloudflare IPv4 出口，证明 TCP 链路可用。
- 校园无线网段到服务器网段的 IPv6 可达性存在间歇性：故障时服务器服务、监听端口、WARP 和系统防火墙均正常，但服务端没有收到客户端连接或临时 HTTP 测试请求。
- WARP 本地 SOCKS5 对 SOCKS5 UDP Associate 返回回复码 `7`（Command not supported），因此不能通过现有 `127.0.0.1:40000` 出站承载 UDP。
- 曾分别测试 WARP `warp` 和 `tunnel_only` 全隧道模式。即使保留校园 IPv4 私网与校园 IPv6 前缀的排除路由，切换后 SSH 和代理入站仍会中断。
- 尝试启用 WARP 的本地网络访问覆盖时，消费版客户端返回 `Operation not authorized in this context`。两次全隧道测试均已回退到 WARP 本地代理模式。
- 仅在 sing-box 中开放 UDP 并使用 `direct` 出站，会让 UDP 使用服务器的普通校园出口，违反“代理业务不能回退到校园 IPv4”的约束，因此未保留该配置。

因此，当前服务器方案的边界已经明确：它适合浏览器、下载等 TCP 流量验证，不适合作为 UU 远程、游戏、语音视频等全 TCP/UDP 场景的最终方案。

## 已部署组件

| 组件 | 版本／模式 | 作用 |
| --- | --- | --- |
| Ubuntu | 22.04 LTS，x86-64 | 校园服务器操作系统 |
| Cloudflare WARP | 2026.7.1377.0，MASQUE，本地代理模式 | 在 `127.0.0.1:40000` 提供 SOCKS5；到 Cloudflare 的外层连接使用 IPv6 |
| sing-box | 1.14.0 | 接收校园设备的 Shadowsocks TCP 连接，并把出站转交给 WARP SOCKS5 |
| systemd | 开机自启 | `warp-svc` 与 `sing-box` 均设置为 enabled、active |

公开文档不记录服务器登录地址、用户名、密码、完整公网 IPv6、代理密钥或可直接导入的客户端 URI。实际密钥只保存在服务器的受限配置文件和用户私有客户端中。

## 服务端数据流

sing-box 的入站使用 Shadowsocks `aes-128-gcm`，当前仅启用 TCP。其出站不是 `direct`，而是服务器本机的 WARP SOCKS5：

```json
{
  "inbounds": [
    {
      "type": "shadowsocks",
      "listen": "::",
      "listen_port": 38443,
      "network": "tcp",
      "method": "aes-128-gcm",
      "password": "<private>"
    }
  ],
  "outbounds": [
    {
      "type": "socks",
      "server": "127.0.0.1",
      "server_port": 40000,
      "version": "5"
    }
  ]
}
```

示例省略了标签、日志和路由等字段，不能直接替换生产配置。关键约束是所有代理业务出站必须指向 WARP SOCKS5，不能回退到校园 IPv4 默认路由。

## 已完成验证

- 服务器拥有可用的校园全球单播 IPv6和 IPv6 默认路由。
- 服务器系统防火墙未阻止测试端口，sing-box 正常监听 TCP 38443。
- WARP 状态为 Connected、Network healthy，协议为 MASQUE over UDP。
- WARP 活动连接的源和目标均为 IPv6；未使用服务器的校园私网 IPv4建立该隧道。
- 通过 WARP SOCKS5 访问纯 IPv4 地址查询服务成功。
- 通过临时 sing-box 客户端完成 `Shadowsocks → WARP SOCKS5 → IPv4` 端到端测试。
- 校园 Android 手机导入节点后访问地址查询服务，得到与服务器端测试一致的 Cloudflare IPv4 出口。

## 尚未完成

- 校园账户计费 A/B 验证；这是判断当前计费效果的唯一有效依据。
- UDP/QUIC、游戏和语音流量验证。服务端目前只开放 TCP。
- Android 客户端全局/TUN 模式下的流量泄漏检查。
- iOS 客户端实机验证。
- IPv6 前缀或接口标识变化后的自动更新。
- 重启后的外部实机回归、长时间稳定性和吞吐测试。

## 全流量后续规划

优先在 Android 设备上直接测试 Cloudflare 官方 `1.1.1.1 + WARP`，不与 Shadowrocket 同时运行：

1. 使用 WARP 的 Traffic and DNS 模式，使设备 TCP、UDP 和 DNS 都进入 WARP。
2. 关闭移动数据，只保留校园 Wi-Fi，并确认手机仍获得校园 IPv6。
3. 检查 Cloudflare trace 中的 `warp=on`，同时从连接信息或抓包确认手机到 Cloudflare 的外层连接实际使用 IPv6。
4. 检查客户端的排除应用列表，确保 UU 远程等目标应用没有被排除。
5. 按验收清单分别测试网页下载和高 UDP 占比应用，记录校园账户前后流量。
6. 若外层回退 IPv4、校园账户仍按量扣费或连接不稳定，则停止该路线。

如果必须保留“Shadowrocket → 自建服务器”的结构，则需更换为能够稳定接收入站 IPv6、并提供原生 TCP/UDP 隧道出口的双栈节点。不能继续依赖当前 WARP 本地 SOCKS5 来实现 UDP。

## 手机端使用边界

客户端必须连接校园 Wi-Fi，导入私人 Shadowsocks 配置，并选择全局或 TUN/VPN 路由模式。浏览器显示 Cloudflare IPv4 出口只能证明该次请求经过代理；其他应用是否经过代理取决于客户端路由规则。测试计费时应关闭移动数据，记录测试前后的校园账户数据并等待计费系统刷新。

## 运维检查

服务端可使用以下命令检查状态：

```bash
systemctl is-active warp-svc sing-box
warp-cli --accept-tos status
warp-cli --accept-tos tunnel stats
ss -lnt | grep ':38443'
```

配置更新后应先检查语法，再重启服务：

```bash
sudo sing-box check -c /etc/sing-box/config.json
sudo systemctl restart sing-box
```

若 `warp-cli tunnel stats` 不再显示 IPv6 端点，或活动连接回退到 IPv4，应停止计费实验并排查 WARP 连接路径。

## 资料

- [Cloudflare WARP Linux 客户端](https://developers.cloudflare.com/warp-client/get-started/linux/)
- [Cloudflare WARP 模式](https://developers.cloudflare.com/warp-client/warp-modes/)
- [sing-box Shadowsocks 入站](https://sing-box.sagernet.org/configuration/inbound/shadowsocks/)
- [sing-box SOCKS 出站](https://sing-box.sagernet.org/configuration/outbound/socks/)
