# Windows 原生 IPv6 节点

这套脚本在 Windows 11 上运行 sing-box，把校园设备经 IPv6 发来的连接转发到节点的 IPv4 出口。它会生成随机端口和随机密钥，私人配置只保存在本机的 `private` 目录。

## 使用条件

- 已获得设备所有者和网络管理方授权。
- Windows 节点具有公网 IPv6、IPv4 出口，并允许 IPv6 入站。
- 校园 Wi-Fi 下的客户端具有可用 IPv6。
- 在 Windows PowerShell 5.1 或 PowerShell 7 中运行。

Windows 11 家庭版不需要 Hyper-V；这里直接运行官方 sing-box 二进制文件。

## 安装和本机测试

在 PowerShell 中运行：

```powershell
Set-Location .\windows-node
.\Install.ps1
.\Configure.ps1
.\Test-Local.ps1
```

`Install.ps1` 从 sing-box 官方 GitHub Release 下载固定版本，并校验 SHA-256。`Configure.ps1` 默认使用名为 `WLAN` 的网卡；如果实际网卡名称不同，可执行：

```powershell
.\Configure.ps1 -InterfaceAlias '以太网'
```

本机测试通过只说明程序、加密 TCP/UDP 和 IPv4 出口可用，不代表公网入站可达。

## 公网入站测试

双击 `Test-Inbound.cmd`，允许管理员提示。脚本只为随机高位端口创建临时 TCP 入站规则，最多保留 15 分钟。

打开生成的 `private/campus-test.html`，将其中的地址私下发送给校园 Wi-Fi 下的手机或电脑。客户端应关闭蜂窝数据和已有 VPN，再用浏览器打开地址。显示 `NEU IPv6 inbound OK` 后，确认测试确实来自校园 Wi-Fi。

如果超时，检查 Windows 防火墙、上级路由器 IPv6 防火墙及运营商入站限制。不要关闭整个防火墙。IPv6 通常不需要 IPv4 NAT 端口映射。

## 激活和停止

校园入站测试成功后，在管理员 PowerShell 执行：

```powershell
.\Activate-Node.ps1 -CampusTestConfirmed
```

脚本创建限定于当前 IPv6、指定网卡、指定程序和随机端口的 TCP/UDP 防火墙规则，并注册 `NEU-IPv6-Node` 计划任务。服务在目录所有者登录 Windows 后以普通用户权限启动。

双击 `Stop-Node.cmd` 可停止节点，并删除本方案的计划任务和防火墙规则。私人配置会保留。

## 客户端配置

- sing-box 客户端：导入 `private/phone-sing-box.json`。
- 支持 Shadowsocks 2022 的客户端：导入 `private/phone-import.txt` 中的链接。
- Mihomo / Clash Meta 类客户端：导入 `private/tablet-mihomo.yaml`。

这些文件含完整公网 IPv6 和认证密钥，不要提交到 Git、公开分享或上传到公共订阅服务。

## 地址变化

运营商可能更换 IPv6 前缀。本脚本没有配置 DDNS。地址变化后按以下顺序恢复：停止节点、重新配置、重新测试公网入站、激活节点，并重新导入客户端配置。

系统代理、Clash TUN、EasyConnect 等 VPN 会改变路由或 DNS。排障时应分别测试物理网卡的原生 IPv4/IPv6，并确认节点出站仍绑定到配置的物理网卡。
