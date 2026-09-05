# 项目调研

以下数据为 2026-09-03 调研快照，星标、提交和 Issue 数量只用于观察项目历史，不能替代现场验证。

| 项目 | 定位 | 调研观察 | 建议 |
|---|---|---|---|
| [SkYFly2233/NEU-campus-free](https://github.com/SkYFly2233/NEU-campus-free) | 双栈服务器配合 sing-box，将校园 IPv4 访问承载在 IPv6 链路上 | 新替代方案；调研时 8 次提交、5 个 Issue、4 个 Fork。缺少独立计费 A/B 数据和大规模用户证据 | 可作为实验候选，可信度中等；先验证计费和可达性 |
| [SkYFly2233/NEU-ipv6-proxy](https://github.com/SkYFly2233/NEU-ipv6-proxy) | 旧版 DigitalOcean/Hysteria2 方案 | 调研时 247 Stars、6 Forks、12 次提交；仓库已明确说明过时并指向新项目 | 不建议新部署 |
| [Neboer/ipgw-py-manager](https://github.com/Neboer/ipgw-py-manager) | 校园网登录、退出、状态与多账号管理 | 调研时 84 Stars、12 Forks、108 次提交；文档记录 2026-03-08 发布 v3.3 | 可作为登录工具候选，不是 IPv6 转发或免流方案 |
| [neucn/ipgw](https://github.com/neucn/ipgw) | Go 编写的跨平台 IPGW 登录客户端 | 调研时 186 Stars、35 Forks、20 次提交；有历史使用基础，也有登录失效反馈 | 现场验证后使用 |
| [DoraTiger/NEU_IPGW](https://github.com/DoraTiger/NEU_IPGW) | 针对登录失败场景的 Go 重写 | 调研时 17 Stars、2 Forks、43 次提交 | 可作为第二登录候选；默认内置公开密钥不等于强加密 |

## 搜索结论

以“i东北大学 ipv6”为精确关键词，没有发现名称和用途都明确对应的独立仓库。实际相关内容主要集中在 NEU、IPGW、IPv6 proxy 等关键词下。

## 同类院校方案

- [SYSU-Network-Solution](https://github.com/RenAhsAcme/SYSU-Network-Solution)
- [华南理工 Padavan 指南](https://github.com/hanwckf/scut_padavan_guide/blob/master/guide.md)

这些项目说明“校园 IPv6 + 校外双栈出口”是一类通用架构，但不同学校的认证、路由、出口和计费规则不同，不能用其他学校的成功案例证明东北大学当前一定可用。

## 证据强度判断

目前能确认的是技术原理和公开项目说明；尚不能仅凭仓库内容确认：

- 东北大学当前是否对目标 IPv6 流量计费；
- 高峰期的延迟、丢包和带宽；
- 所有校区、SSID 和终端是否采用相同策略；
- 方案能否长期稳定运行。

因此应把项目视为实验起点，而不是效果保证。
