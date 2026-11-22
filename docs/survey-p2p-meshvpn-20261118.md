# 跨局域网/跨 NAT 组网方案技术调研报告
### —— 文明6局域网联机助手开源化（P2P / Mesh VPN 选型）

- **报告日期**：2026-11-18
- **检索方式**：web_search（多引擎）、platform_search（GitHub/Reddit）、GitHub REST API（star / last push / license）、仓库 README 与 LICENSE 原文抓取
- **数据截至**：2026-11-17 ~ 2026-11-18（GitHub API 为准）

---

## 1. 背景与评估目标

「文明6局域网联机助手」计划开源，供所有游戏爱好者跨局域网/跨 NAT 联机。项目现有技术栈：

- agent 绑定 **62900–62999** 发现端口、模拟房主（fake host）实现发现；
- **DLL 注入**游戏进程实现定向/劫持；
- 已实测并解决一个关键坑：Windows 的 `255.255.255.255` 广播**按 InterfaceMetric 最小接口发出**，Radmin VPN（metric=1）会抢走广播导致另一台机收不到——已通过**改 metric + 进程级定向**解决。

评估核心问题：**与其自研 P2P/组网，是否可以直接采用/集成现有成熟的开源组网方案**，让游戏"以为"自己在同一局域网里。License 兼容性是首要约束（项目要开源，集成进仓库的代码其 License 必须与项目自身 License 兼容；以独立进程/文档推荐方式使用的则约束放宽）。

> 注：文明6联机本质上需要的是 **发现（UDP 广播/组播，255.255.255.255）** + **联机数据通道（游戏实际是点对点 UDP/TCP 直连）**。因此"能否承载 L2 广播"是判断方案直接可用的关键分水岭：**二层(L2)虚拟网络**可让游戏原生发现机制无改动直接工作；**三层(L3)虚拟网络**则发现必须由 agent 辅助（本项目已有进程级定向 + 端口模拟能力，正好可补这一环）。

---

## 2. 方案对比总表

> 活跃度 = 最近 push（2026-11 查询）；「广播承载」指 255.255.255.255 广播报文能否跨节点送达；「免费商用」指无需付费即可用于商业项目。

| # | 方案 | 仓库 | star/活跃度 | License | 协议类型 | 免费商用 | NAT 穿透 | 广播/组播 | Win 客户端 | 部署难度 | 对游戏 UDP 广播适用性 |
|---|------|------|------------|---------|---------|----------|----------|-----------|-----------|----------|----------------------|
| 1 | **ZeroTier** | [zerotier/ZeroTierOne](https://github.com/zerotier/ZeroTierOne) | 17,266★ / 2026-09 | 核心 **MPL-2.0** + `nonfree/` Controller **Source-Available（仅非商业）** | 二层以太网虚拟化 (L2) | ⚠️ 部分：Agent 组件可；Controller 商用需付费授权 | ✅ 强（Planet/Root + NAT 穿透 + 中继） | ✅ **支持**（虚拟以太网，广播帧全网可达，组播受限但发现包够用） | ✅ 原生 GUI | 低（装客户端 + Central 建网） | ⭐⭐⭐⭐⭐ 原生承载 255.255.255.255，游戏零改动 |
| 2 | **Tailscale** | [tailscale/tailscale](https://github.com/tailscale/tailscale) | 39,235★ / 2026-11 | **BSD-3-Clause** | 三层 (L3, WireGuard) | ✅（客户端代码；服务商用付费） | ✅ 强（DERP 中继 + 打洞） | ❌ 不支持（L3，无 L2 广播/组播） | ✅ 原生 GUI | 低（账号体系） | ⭐⭐ 需 agent 辅助发现；但需依赖 Tailscale 账号/控制平面 |
| 3 | **n2n** | [ntop/n2n](https://github.com/ntop/n2n) | 7,058★ / 2026-10 | **GPL-3.0** | 二层 P2P（supernode+edge） | ✅（GPL 允许，但商用集成须遵守 copyleft） | ✅ 强（edge 间 UDP 直连，失败走 supernode 中继） | ✅ 广播支持（L2 转发）；⚠️ 组播支持不完整（社区长期议题，需实测） | ✅ 第三方二进制 [lucktu/n2n](https://github.com/lucktu/n2n)（GUI: HappyNet） | 中（需公网 supernode，VPS 单端口） | ⭐⭐⭐⭐ 广播可承载；组播需实测；自建 supernode 有运维成本 |
| 4 | **Radmin VPN** | 闭源（[radmin-lan.cn](https://www.radmin-lan.cn/)） | — | **专有（免费）** | L2 虚拟网卡 | ✅ 免费但闭源 | ✅ | ✅ 支持 | ✅ | 低 | ⚠️ **本项目实测教训**：metric=1 抢广播；不可集成（闭源） |
| 5 | **Hamachi** | 闭源（[hamachi-app/hamachi-download](https://github.com/hamachi-app/hamachi-download) 仅托管安装包） | v2.4.0.79 (2026-10) | **专有（免费版受限）** | L2 虚拟网卡 | 免费版 5 台/网（商用要付） | ✅ 中继式 | ✅ 支持 | ✅ | 低 | ⭐⭐⭐ 可用但免费版容量小、闭源不可集成、服务商风险 |
| 6 | **WireGuard** | [wireguard/wireguard-windows](https://github.com/wireguard/wireguard-windows) | 2,908★ / 2026-09 | **MIT**（Windows 客户端；内核模块 GPLv2，wireguard-go MIT） | 三层 (L3) | ✅ | ❌ 无内置穿透（需公网端点或辅助打洞） | ❌ 不支持 | ✅ 原生 | 中 | ⭐ 纯 L3 单跳，不适合无公网端点的游戏场景（可作为加密传输底层） |
| 7 | **Yggdrasil** | [yggdrasil-network/yggdrasil-go](https://github.com/yggdrasil-network/yggdrasil-go) | 5,585★ / 2026-10 | **LGPLv3 + 链接例外** | L3 IPv6 自愈 mesh 隧道 | ✅ | ✅ 强（对等点直连 + 自动路由） | ❌ 不支持（纯 IPv6 L3） | ✅ | 中（配置对等点） | ⭐ 无 IPv4/L2 广播；不适用游戏原生发现，需 agent 全权代理发现+转发 |
| 8 | **Nebula** | [slackhq/nebula](https://github.com/slackhq/nebula) | 18,538★ / 2026-11 | **MIT** | 三层 (L3) | ✅ | ✅ 中（lighthouse 打洞 + 中继） | ❌ 不支持 | ✅ 原生 | 中-高（证书体系 + lighthouse 服务器） | ⭐⭐ 需 agent 辅助发现；部署门槛高于 ZeroTier/Tailscale |
| 9a | **OpenVPN** | [OpenVPN/openvpn](https://github.com/OpenVPN/openvpn) | 13,2xx★ / 2026-10 | **GPL-2.0** | L2(TAP)/L3(TUN)，中心服务器模式 | ✅（GPL） | 弱（TCP/UDP 单隧道，无自动打洞；常配端口复用） | TAP 模式 ✅ 支持 L2 广播 | ✅ | 高（中心服务器 + 证书 PKI） | ⭐⭐ 可承载广播但架构是"中心辐射"，跨 NAT 需公网服务器，非 P2P |
| 9b | **Tinc** | [gsliepen/tinc](https://github.com/gsliepen/tinc) | 2,3xx★ / 2026-08 | **GPL-2.0** | L2(switch)/L3，mesh | ✅（GPL） | 中（mesh 多跳，需至少一个公网可达节点） | switch 模式 ✅ 支持 L2 | ✅ | 中-高 | ⭐⭐⭐ 传统但可行；维护节奏慢，配置较硬核 |
| 10a | **NetBird** | [netbirdio/netbird](https://github.com/netbirdio/netbird) | 31,063★ / 2026-11 | **BSD-3**（客户端；management/signal/relay 目录 **AGPL-3.0**） | L3 (WireGuard) | ⚠️ 客户端 BSD 可；服务端 AGPL，商用自托管须开源衍生 | ✅ 强（打洞 + 中继） | ❌ 不支持 | ✅ 原生 | 中（自托管需管理/信号/中继三件套） | ⭐⭐ 需 agent 辅助；服务端 AGPL 是商用注意点 |
| 10b | **Innernet** | [tonarino/innernet](https://github.com/tonarino/innernet) | 5,586★ / 2026-11 | **MIT** | L3 (WireGuard) | ✅ | ⚠️ 弱（依赖中心服务器公开端点，打洞有限） | ❌ 不支持 | ✅ | 中（自建服务器 + 客户端） | ⭐⭐ 需 agent 辅助；无内置打洞中继，跨 NAT 能力弱 |
| 10c | **Headscale** | [juanfont/headscale](https://github.com/juanfont/headscale) | 45,806★ / 2026-11 | **BSD-3-Clause** | L3（Tailscale 控制平面自托管） | ✅ | 继承 Tailscale 的打洞/DERP | ❌ 不支持 | 搭配 Tailscale 客户端 | 中-高（自托管控制面 + DERP） | ⭐⭐ 需 agent 辅助；自托管 Tailscale 的替代，比官方省账号依赖 |
| 10d | **EasyTier** | [EasyTier/EasyTier](https://github.com/EasyTier/EasyTier) | 14,811★ / 2026-11 | **LGPL-3.0** | L3 (TUN 虚拟 IP) 去中心化 mesh | ✅（LGPL，动态链接兼容友好） | ✅ 强（UDP/IPv6，支持 NAT4-NAT4，P2P 失败走共享公共节点免费中继） | ❌ 不支持（L3 设计，无 L2 广播） | ✅ 原生 GUI（easytier-gui） | 低（零配置 + Web 控制台；共享公共节点免费） | ⭐⭐⭐ 需 agent 辅助发现；无中心服务器、社区中文活跃、部署最省心 |
| 10e | **Tailscale Funnel** | Tailscale 功能 | — | 属 Tailscale 商业服务 | 公网暴露（HTTP/HTTPS/TCP） | ❌ 属付费服务范畴 | — | ❌ 不支持 UDP | — | — | ❌ **不适用**：Funnel 只支持 HTTP/HTTPS/TCP，不支持游戏 UDP 流量 |

---

## 3. 关键方案逐项分析

### 3.1 ZeroTier —— 首选（L2 原生承载广播 + MPL 友好）
- **原理**：虚拟以太网（L2），每节点一块虚拟网卡，表现为"一个局域网"；数据面 P2P（UDP 打洞），控制面经 Planet/Root 节点。
- **广播能力**：**支持**。255.255.255.255 广播帧会被转发到网络内全部节点——这正是它"behaves like a LAN"卖点的核心，游戏原生发现机制（Civ6 的局域网广播）可直接工作，**本项目 DLL/端口模拟逻辑甚至可以不启动**（但保留作为兜底更稳）。
- **License（重点）**：自 **v1.16.0（2025-08-21）** 起发生重大变更——
  - 核心代码（`node/`、`include/`、`service/`、`osdep/`）= **MPL-2.0**（可商用、可集成，MPL 是文件级 copyleft，动态/静态链接进闭源也可）；
  - **Controller（`nonfree/` 目录）= 专有 "ZeroTier SOURCE-AVAILABLE LICENSE v1.0"，仅限非商业**（个人/教育/≤30 天评估），商用自建 Controller 须联系 sales@zerotier.com 付费；无专利授权。
  - 对**本开源项目**：集成 Agent 组件（MPL）没问题；**商用**该组网服务时 Controller 是付费点。GitHub issue #2206「License contradictions」记录了这一表述混乱。
- **NAT 穿透**：强（全球 Planet 根节点 + 打洞 + 中继），家庭 NAT 场景可靠。
- **部署**：低。官方 Central 免费建网（约 25 节点免费），各平台一键装客户端。

### 3.2 Tailscale —— 体验最好但 L3 且依赖账号体系
- **原理**：基于 WireGuard 的三层 mesh；控制面走官方协调服务器（也可用 Headscale 自托管）。
- **广播能力**：**不支持**。L3 网络不承载 L2 广播/组播，Civ6 原生发现不会出现在 tailnet 上——需 agent 辅助：由 agent 把游戏发现包经 tailnet IP 定向转发（本项目已有进程级定向能力，可低成本实现）。
- **License**：客户端/仓库 **BSD-3-Clause**（宽松，可集成）；但**官方控制面是商业服务**，免费版个人约 100 设备、商用要订阅——作为开源项目"内置依赖"不现实，更适合文档推荐用户自装。
- **Funnel**：只暴露 HTTP/HTTPS/TCP，**不支持 UDP**，对游戏流量完全不适用。

### 3.3 n2n —— 最"正统"的 L2 P2P，但组播存疑 + GPL
- **原理**：二层 P2P，supernode（公网可达，可自建 VPS 单端口）+ edge 节点；edge 间尽量 UDP 直连，穿透失败经 supernode 中继；community 名 + 密钥加密。
- **广播**：L2 转发，广播可跨网段；**组播**：社区长期议题，支持不完整，**需实测**（Civ6 发现用的是广播而非组播，故影响有限）。
- **License**：**GPL-3.0**。集成进仓库则整个作品受 GPL 传染；以独立进程/文档推荐方式使用则无碍。
- **部署**：中。Windows 无官方安装包（第三方 lucktu/n2n 收集二进制、HappyNet GUI），且需要**自建 supernode**——这恰恰是开源项目可提供的公共价值点，但也意味着项目方要长期运维公网节点。

### 3.4 Radmin VPN / Hamachi —— 闭源，只做文档反例
- **Radmin VPN**：免费闭源专有。**本项目已实测其 metric=1 会抢走 255.255.255.255 广播**——这正是"闭源虚拟网卡不可控"的典型教训。可继续作为"用户自选方案"文档推荐（改 metric 教程），**绝不可集成**。
- **Hamachi**：LogMeIn→GoTo 体系，未停服（2026-10 仍发 v2.4.0.79），免费版 5 台/网，闭源专有。功能可用但容量小、有厂商存续风险；不集成，仅文档提及。

### 3.5 WireGuard / Yggdrasil / Nebula —— 优质 L3，但都不承载广播
- **WireGuard**（Windows 客户端 MIT，内核 GPLv2）：加密极佳、性能最好，但**无内置 NAT 穿透**（需公网端点或 wg 打洞辅助），单跳架构，不解决"双方都在 NAT 后"的游戏场景。更适合作为**其他方案的加密底层**（EasyTier/NetBird/Tailscale 都基于/兼容 WG 生态）。
- **Yggdrasil**（LGPLv3+链接例外）：自愈 mesh、纯 IPv6，无 IPv4/L2 广播 → 游戏原生发现无法工作，需 agent 全权代理发现并转发（复杂，不推荐）。
- **Nebula**（MIT）：Slack 出品，证书体系 + lighthouse 打洞，质量高、License 最宽松（MIT 可直接集成源码）；但部署门槛（PKI + lighthouse 服务器）高于 ZeroTier/EasyTier，且 L3 无广播 → 需 agent 辅助发现。**MIT 是集成进项目源码的最佳 License**，适合愿意投入运维的场景。

### 3.6 传统方案：OpenVPN / Tinc
- **OpenVPN**（GPL-2.0）：TAP 模式可承载 L2 广播，但**中心辐射架构**，跨 NAT 需公网服务器，非 P2P、多玩家时带宽集中，不推荐作为联机组网主方案。
- **Tinc**（GPL-2.0）：mesh 架构，switch 模式支持 L2 广播，但需至少一个公网节点、配置硬核、维护节奏慢。可用但"过时感"明显。

### 3.7 新兴方案：NetBird / Innernet / Headscale / EasyTier
- **NetBird**（客户端 BSD-3，服务端四目录 AGPL-3.0）：体验好、打洞强，但自托管要 management/signal/relay 三件套，AGPL 服务端对商用自托管是约束。L3 无广播。
- **Innernet**（MIT）：Rust 写得好、License 好，但**无内置打洞中继**，跨 NAT 能力弱——恰恰击中本项目痛点，不推荐作主方案。
- **Headscale**（BSD-3）：Tailscale 控制面自托管，成熟度最高（45.8k★），可让用户摆脱官方账号依赖；但 L3 无广播 + 部署运维成本高。适合文档推荐给"高级用户"。
- **EasyTier**（LGPL-3.0）：**最值得关注的新兴方案**。去中心化（无中心服务器，节点等权）、NAT4-NAT4 直通（含 IPv6）、P2P 失败自动经**共享公共节点免费中继**（项目方零运维）、零配置 + Web 控制台 + Windows GUI、中文社区活跃。L3 设计无 L2 广播 → 需 agent 辅助发现，但本项目 agent 正好具备端口模拟 + 进程级定向，实现成本低。LGPL-3.0 动态链接兼容友好。

---

## 4. License 兼容性矩阵（集成 vs 独立使用）

> 结论先行：**集成进开源仓库源码**只推荐 MIT / BSD / Apache / MPL / LGPL；GPL 系集成需整个作品转 GPL；Source-Available / 专有一律只可独立使用或文档推荐。

| License | 集成进仓库源码 | 作为独立进程随项目分发 | 文档推荐用户自装 | 备注 |
|---------|--------------|----------------------|----------------|------|
| **MIT**（Nebula / Innernet） | ✅ 最宽松 | ✅ | ✅ | 可直接拷贝/链接源码，无任何义务 |
| **BSD-3**（Tailscale / Headscale / NetBird 客户端） | ✅ | ✅ | ✅ | 保留版权声明即可 |
| **Apache-2.0**（SoftEther） | ✅ | ✅ | ✅ | 含专利授权 |
| **MPL-2.0**（ZeroTier Agent 核心） | ✅ | ✅ | ✅ | 文件级 copyleft，动态链接进闭源亦可 |
| **LGPL-3.0**（EasyTier / Yggdrasil） | ✅（动态链接） | ✅ | ✅ | 静态链接需提供重链接能力 |
| **GPL-2.0/3.0**（n2n / OpenVPN / Tinc / WireGuard 内核） | ⚠️ 传染，整个作品须 GPL | ✅（独立进程无传染） | ✅ | 集成源码需项目整体转 GPL |
| **Source-Available 非商业**（ZeroTier Controller） | ❌ 不可商用集成 | ⚠️ 仅非商业 | ✅ | 商用自建 Controller 须付费授权 |
| **专有闭源**（Radmin VPN / Hamachi） | ❌ | ❌ | ✅ | 只作文档推荐（含 metric 改法） |

---

## 5. 综合建议

### 5.1 架构判断
本项目**已有 agent 的端口模拟（62900-62999）+ DLL 进程级定向**，这决定了两条路线都可行：

- **路线 A（零代码改动，推荐主力）**：采用 **L2 方案（ZeroTier 为首）**，游戏原生广播直接跨网段送达，agent 仅作"装没装、通没通"的检测与引导。用户体验最好，任何游戏（不止 Civ6）通用。
- **路线 B（agent 辅助发现）**：采用 **L3 方案（EasyTier / Tailscale / Nebula）**，由 agent 把发现流量定向到对方虚拟 IP（复用现有进程级定向能力），广播照旧只在真实 LAN 上走。适合不想依赖 L2 虚拟网卡的用户，但每款游戏都要适配一次。

### 5.2 推荐分工（开源项目如何落地）
1. **内置集成**：把 **EasyTier**（LGPL-3.0，动态链接）或 **Nebula**（MIT，最宽松）作为可选"组网内核"随项目分发；两者均为独立进程/动态链接，不污染项目自身 License。ZeroTier 的 Agent（MPL）也可内置，但 Controller 商用付费要写清楚。
2. **文档推荐（主推）**：把 **ZeroTier**、**Tailscale** 作为"用户自装即可"的一键指引（各平台客户端 + 建网步骤），**并附本项目已有的"改 InterfaceMetric + 进程级定向"教程**——这正是文档推荐闭源方案（Radmin/Hamachi）时的配套。
3. **不建议自研 P2P**：成熟方案在打洞、中继、跨平台、加密上的投入远超自研；自研仅当需要"完全离线/无任何第三方依赖"时才考虑。

---

## 6. 推荐与不推荐清单

### ✅ 推荐（可集成进开源项目）
| 优先级 | 方案 | License | 理由 |
|--------|------|---------|------|
| 🥇 **1. ZeroTier** | 核心 **MPL-2.0**（Controller 非商业 Source-Available） | L2 原生承载 255.255.255.255 广播，**游戏零改动**；NAT 穿透与中继最成熟；部署最低；MPL 集成友好。**唯一注意：商用自建 Controller 需付费** |
| 🥈 **2. EasyTier** | **LGPL-3.0** | 去中心化零服务器、NAT4-NAT4 直通、失败自动免费公共中继（项目方零运维）、Windows GUI、中文社区活跃；L3 无广播但项目 agent 恰好有进程级定向可补发现 |
| 🥉 **3. Nebula** | **MIT**（全项目最宽松） | 若想把组网代码**真正并入仓库源码**，MIT 是最优 License；lighthouse 架构稳定、Slack 出品质量高；代价是部署门槛（PKI）与 L3 无广播 |

### ⚠️ 有条件推荐（文档推荐 / 用户自装 / 混合）
- **Tailscale（BSD-3）**：文档推荐首选——体验最好，但依赖官方账号/控制面，免费版限个人规模；不内置。**Funnel 不支持 UDP，明确排除**。
- **n2n（GPL-3.0）**：L2 且广播可承载，但组播需实测、Windows 无官方包、**需自建 supernode 长期运维**；若项目方愿意运营公共 supernode 可作为备选；集成则整体转 GPL。
- **Headscale（BSD-3）**：文档推荐给"不想用官方账号的高级用户"自托管；需运维控制面 + DERP。
- **SoftEther（Apache-2.0）**：多协议 + EtherIP 可做 L2，License 好；但中心服务器架构，非 P2P，仅边缘场景。
- **Radmin VPN / Hamachi**：继续文档推荐（免费、好用、L2），**必须附本项目改 metric 教程**（Radmin metric=1 抢广播的实测教训）；闭源不可集成。

### ❌ 不推荐
- **WireGuard 单独使用**：无 NAT 穿透、需公网端点，不解决双 NAT 游戏场景（只作加密底层）。
- **Yggdrasil**：纯 IPv6 L3，无 IPv4/L2 广播，agent 全权代理发现复杂度过高，收益低。
- **Innernet**：License 好但无内置打洞中继，跨 NAT 能力弱，正中本项目痛点反面。
- **NetBird（作为集成目标）**：服务端 AGPL 商用自托管受限；客户端 BSD 可但需三件套服务。
- **Tailscale Funnel**：不支持 UDP，与游戏流量无关。
- **自研 P2P/组网**：不划算，除非要求完全无第三方依赖。

---

## 7. 结论

1. **首选 ZeroTier（MPL-2.0 核心）**：唯一"装完即 LAN"的成熟方案，Civ6 原生广播直通，本项目 DLL/端口模拟逻辑从"必需"降级为"兜底"，开源集成 License 无大碍（仅商用自建 Controller 付费）。
2. **次选 EasyTier（LGPL-3.0）**：无中心服务器、免费公共中继、部署最省心的新兴方案，与本项目 agent 的进程级定向能力互补，实现 L3 辅助发现成本低；中文社区活跃。
3. **集成源码首选 Nebula（MIT）**：License 最干净；适合把组网能力真正并入仓库。
4. **文档推荐闭源方案（Radmin VPN/Hamachi）时务必附 metric 教程**——这是本项目踩过的坑，是开源项目的差异化价值点。
5. **结论**：成熟方案完全可替代自研；推荐"内置 EasyTier/Nebula + 文档主推 ZeroTier/Tailscale"的双轨策略。

---

### 附：数据来源
- GitHub 仓库：ZeroTierOne / tailscale / n2n / yggdrasil-go / nebula / netbird / innernet / headscale / EasyTier / wireguard-windows / SoftEtherVPN（star、last push、license 均为 2026-11-17/18 API 查询）
- License 原文：ZeroTierOne `nonfree/LICENSE.md`（Source-Available v1.0）与 v1.16.0 RELEASE-NOTES；EasyTier `LICENSE`（LGPLv3）与 README；NetBird `LICENSE`（BSD-3 + 四目录 AGPLv3）；yggdrasil-go `LICENSE`（LGPLv3 + 链接例外）；wireguard-windows `COPYING`（MIT）
- 行为类结论（广播/组播、NAT 穿透强度）部分基于官方文档/README，部分基于业界通识与社区议题，报告中已标注不确定项（如 n2n 组播）
