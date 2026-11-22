# CivLink 开源版：NAT 穿透 / 中继技术选型调研报告

- **调研日期**：2026-11-18
- **项目背景**：文明6 局域网联机助手开源化，目标让两个不在同一局域网的玩家也能联机。
- **文明6 网络特征**（社区实测，见 §6）：
  - 发现阶段：UDP 广播到 `255.255.255.255:62900-62999`（同时是二层+三层广播包）
  - 数据面：加入房间后切换为 UDP `62056` 点对点
  - 底层传输：RakNet（UDP，自带可靠传输/分片/有序）
  - 游戏本身不提供「填写服务器 IP 直连」的入口
- **现状**：项目已实现 agent（发现端口模拟房主应答广播）+ hook DLL（观测游戏 socket）。
- **调研方法**：web_search / platform_search（github / stackoverflow / reddit）+ 关键页面全文抓取（GitHub LICENSE 文件、Steamworks 官方文档、RakNet 源码、社区实测博客等），全部来源附 URL。

---

## 1. UDP NAT 穿透技术全景

### 1.1 标准体系（RFC 3489/5389 家族）

| RFC | 内容 | 状态 |
|---|---|---|
| [RFC 3489](https://www.rfc-editor.org/rfc/rfc3489)（2003） | 原始 STUN（Session Traversal Utilities for NAT） | 已被 RFC 5389 取代（历史） |
| [RFC 5389](https://www.rfc-editor.org/rfc/rfc5389)（2008） | 现行 STUN：NAT 行为探测，让客户端发现自己的公网映射地址 | 现行 |
| [RFC 5766](https://www.rfc-editor.org/rfc/rfc5766)（2010） | TURN（Traversal Using Relays around NAT）：打洞失败时的**中继兜底** | 现行 |
| [RFC 5128](https://www.rfc-editor.org/rfc/rfc5128)（2008） | NAT 穿透技术现状综述（state of affairs） | 综述 |
| [RFC 6886](https://www.rfc-editor.org/rfc/rfc6886)（2013） | NAT-PMP（Apple 的端口映射协议） | 现行 |
| [RFC 6887](https://www.rfc-editor.org/rfc/rfc6887)（2013） | PCP（Port Control Protocol，NAT-PMP 的继任者） | 现行 |
| UPnP IGD | 家用路由器自动端口映射（[UPnP 论坛协议](https://www.rfc-editor.org/rfc/rfc6970)，厂商实现不统一） | 广泛部署于家用路由器 |

### 1.2 四种 NAT 类型（RFC 3489 分类）

NAT 类型判定直接影响打洞成功率（参考 NAT Checker 等工具按 RFC 3489 分类的做法：https://natchecker.com/zh）：

1. **Full Cone**（全锥）：内网地址一旦建立映射，任何外部主机都能访问——打洞最易成功。
2. **Restricted Cone**（限制锥）：只允许来自「曾向其发包」的 IP 的数据进入。
3. **Port Restricted Cone**（端口限制锥）：进一步限制端口——经典 UDP 打洞的目标场景。
4. **Symmetric**（对称型）：每个目标地址/端口分配独立映射端口，**UDP 打洞基本失败**，必须靠 TURN 中继或端口预测（RakNet 的 `MAX_PREDICTIVE_PORT_RANGE` 就是为此设计）。

> 国内网络环境（尤其移动网络/校园网 NAT4/对称 NAT）对称型比例较高，社区实测认为 P2P 打洞「不是一种非常稳定可靠的方式」（来源见 §6 yllhwa 博客）。**结论：打洞必须配 TURN 中继兜底**。

### 1.3 UDP 打洞（Hole Punching）原理

- 双方都先连接一台**公网协调服务器（facilitator / rendezvous）**（可以是 STUN 服务器或自定义信令服务器），各自报告自己被 NAT 映射出的 `公网IP:端口`。
- 双方**同时**向对方的公网映射地址发送 UDP 数据包；第一个包被对方 NAT 丢弃，但已在双方 NAT 上留下映射记录（"打洞"），后续包即可双向通行。
- 对称 NAT 场景可用**端口预测**（预测 NAT 下次分配的端口，RakNet 用 `FindRouterPortStride()` 探测步长）提高成功率。

### 1.4 STUN / TURN / coturn

- **STUN**：免费、无状态，只做「探测映射地址」，不转发流量，带宽成本≈0，部署成本极低。
- **TURN**：转发所有数据流量，中继带宽成本 ≈ 玩家流量的**双倍**（进+出），带宽需求随玩家数线性增长；需要静态公网 IP、开放 UDP/TCP 端口、TLS 证书（可选）。
- **coturn**（https://github.com/coturn/coturn，14.6k stars）是事实标准的开源 STUN/TURN 服务器，**BSD-3-Clause**（已从官方 LICENSE 文件确认），可内嵌/商用，是 WebRTC 生态的默认选择（博客园部署教程：https://www.cnblogs.com/NyanKoSenSei/p/19501123）。

### 1.5 UPnP/IGD、NAT-PMP、PCP 端口映射

- 原理：客户端直接向家用路由器请求「把公网某端口转发到我的内网 IP:端口」，成功后**不依赖打洞**，等于把玩家变成"公网主机"。
- 优点：成功率对普通家用路由器非常高；无需服务器带宽；PCP/NAT-PMP 比 UPnP 更规范（Apple 生态默认）。
- 缺点：受限于「玩家有自己的路由器且开启了 UPnP」（主流家用路由器默认开）；公共 WiFi/校园网/CGNAT 场景无效；RakNet 时代的老代码支持较差，但 RakNet 的 `NatPunchthroughClient::GetUPNPPortMappings()` 已内置对 miniupnpc 的对接（见 §3.3 源码证据）。
- 对 CivLink 的价值：**UPnP 自动映射可作为「第一优先」尝试**，成本极低、不依赖任何服务器。

### 1.6 TCP 打洞的可行性

- TCP 打洞（TCP hole punching）理论可行（NAT 同样会为 TCP 连接建立映射），但要求双方近乎同时发起 SYN，且需处理半开连接；游戏数据面是 UDP（62056），**本项目不需要 TCP 打洞**，仅在信令通道（与协调服务器的 TCP/WebSocket 连接）上有意义——而信令服务器是公网的，无需打洞。
- StackOverflow 上 TCP 打洞 Java 实现讨论见 https://stackoverflow.com/questions/27427171/tcp-hole-punching-java-example。

### 1.7 游戏场景（RakNet / Steam P2P）通常怎么解决

- RakNet 自带 `NatPunchthroughClient`/`NatPunchthroughServer`（UDP 打洞，见 §3.3）。
- Steam 的做法是 **Steam Datagram Relay（SDR）**：不依赖打洞成功与否，直接走 Valve 全球中继骨干网（见 §3.2）。
- 业界通用套路（WebRTC/游戏一致）：**ICE 流程 = 优先直连/打洞，失败降级 TURN 中继**（https://www.rfc-editor.org/rfc/rfc8445 是 WebRTC ICE 的现行 RFC，其分级思想可直接借鉴）。

---

## 2. 开源 Relay / 中继实现（含 License）

### 2.1 逐项清单

| 项目 | 用途 | License（已核对官方 LICENSE 文件） | 特点 |
|---|---|---|---|
| [coturn/coturn](https://github.com/coturn/coturn) | STUN+TURN 服务器（UDP/TCP/TLS/DTLS） | **BSD-3-Clause** | WebRTC 默认 TURN；协议是标准 TURN（RFC 5766），客户端需 TURN 客户端库 |
| [fatedier/frp](https://github.com/fatedier/frp) | 内网穿透（TCP/UDP/HTTP/KCP/STCP 等） | **Apache-2.0**（官方 LICENSE 已确认） | Go 实现；frps 服务端 + frpc 客户端；支持 STUN 打洞尝试 P2P 直连，失败回退服务器中转（来源：CSDN 技术盘点 https://www.csdn.net/article/2026-09-04/164367623）；文档 https://gofrp.org/zh-cn/docs/ |
| [rathole-org/rathole](https://github.com/rathole-org/rathole) | 轻量级 TCP/UDP 内网穿透 | **Apache-2.0**（官方 LICENSE 已确认） | Rust 实现；高吞吐低占用，高并发优于 frp（来源：https://www.appinn.com/rathole/） |
| [jpillora/chisel](https://github.com/jpillora/chisel) | TCP/HTTP 隧道 | **MIT**（官方 LICENSE 已确认） | Go 实现；单二进制；主要面向 TCP/HTTP，UDP 支持有限 |
| [ngrok](https://ngrok.com) | 托管隧道服务 | **核心闭源**（仅 agent 开源） | 免费版 40 并发连接限制、海外节点国内延迟 150ms+（来源：CSDN 盘点同上），不适合游戏 |
| [WireGuard](https://www.wireguard.com) | 内核态 VPN 隧道 | **GPL-2.0**（https://github.com/WireGuard） | 仅三层（IP 层），**默认不转发广播**（详见 §4）；协议经 UDP 承载 |
| [ValveSoftware/GameNetworkingSockets](https://github.com/ValveSoftware/GameNetworkingSockets) | 游戏网络库：可靠/不可靠 UDP、分片、**P2P NAT 穿越、中继客户端** | **BSD-3-Clause**（官方 LICENSE 已确认，Valve 2018） | 最贴近本项目需求的现成库！开源版**不含** Valve 中继网络访问权，但含完整 NAT 穿越与中继客户端逻辑（见 §3.2/§5.2） |
| [skywind3000/kcp](https://github.com/skywind3000/kcp) | 可靠 UDP 协议（ARQ） | **MIT**（官方 LICENSE 已确认） | 比 TCP 浪费 10-20% 带宽换 30-40% 平均延迟降低（来源：官方 README） |
| [ntop/n2n](https://github.com/ntop/n2n) | 二层 P2P VPN（edge+supernode） | GPL-3.0（来源：https://github.com/ntop/n2n） | 二层承载广播；supernode 是打洞协调者 |
| [ZeroTier](https://www.zerotier.com) | 二层 SDN 组网（虚拟以太网交换机） | **核心 BSL（Business Source License）**，SDK 部分开源（来源：https://github.com/zerotier/ZeroTierOne） | 二层转发广播（见 §4）；免费版设备数充足；对称 NAT 打洞成功率不稳定（来源：CSDN 盘点） |
| [dechamps/WinIPBroadcast](https://github.com/dechamps/WinIPBroadcast) | Windows 广播跨网卡转发 | MIT（来源：仓库） | 解决「Windows 只在主网卡广播」问题（见 §4/§6） |

### 2.2 部署成本对比（自建中继）

| 方案 | 需要公网服务器 | 带宽需求 | 最低成本 | 说明 |
|---|---|---|---|---|
| STUN-only（coturn 只开 STUN） | 一台低配 VPS | ≈0（无数据流量） | 几十元/月 VPS | 只做协调与映射探测 |
| TURN 中继（coturn 全功能） | 一台有公网 IP 的 VPS/轻量云 | 玩家总流量的 2 倍（进+出） | 视带宽，建议 ≥5-10 Mbps/玩家 | 文明6 回合制流量不大，1-2 Mbps/玩家可能够用 |
| frp/rathole 自建中转 | 一台 VPS | 同上（转发模式） | 同上 | 无需客户端改协议，端口/协议直接映射 |
| 托管服务（ngrok/花生壳） | 无（用厂商节点） | 受免费版限制 | 免费版限制多 | 国内延迟/并发受限，不推荐游戏场景 |

> 社区实测参考：yllhwa 用腾讯云北京 8 Mbps 跑 OpenVPN，武汉客户端 ping 42ms、游戏内 80ms+，8 人联机 4 小时稳定（§6）。这给出了「一台 8Mbps VPS 足以支撑小型文明6 局」的实证。

---

## 3. 游戏联机专用的穿透方案

### 3.1 国内商业加速器（UU / 奇游等）原理

- 官方表述（奇游官方技术博客 https://bestqiyou.com/zh-hans/blogs/qiyoujiasuqidegongzuoyuanlishishenmemianfeibanbenzaisuduyuwendingxingfangmianyouhexianzhi）：接入其全球节点网络 → 按地理位置与目标服务器**动态选路** → 「近端落地、远端穿透」双向加速 → 流量切分、优先级调度、异常路由快速切换。即**多节点中转 + 智能路由 + 专线优化**。
- 网易 UU（https://uu.163.com/）：本质同类——通过自建边缘节点把玩家与游戏服务器间的流量「截获并中转」，绕开运营商劣质路由，降低延迟与丢包；**不是打洞**，而是全程中继的 SD-WAN。
- 对 CivLink 的启示：商业加速器证明「**全程中继**（即使不打洞）也能带来可用体验」，其代价是运营节点网络（商用成本高，开源项目不适合自建节点网，但**单点自建 TURN/frp 中继**思路一致）。

### 3.2 Steam 的 NAT 穿透：Steam Datagram Relay（SDR）

- **官方文档**（Steamworks，中文版已全文抓取）：https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay
- 要点：
  - SDR 是 Valve 的**虚拟私有游戏网络**：游戏流量走 Valve 专用骨干网 + 全球中继网络；流量**验证、加密、限速**；对 P2P 与专用服务器均可用；可**改善 ping**（官方公告：https://steamcommunity.com/groups/steamworks/announcements/detail/1791775741704351698）。
  - 中继流量使服务器/玩家 IP 不暴露，天然防 DoS。
  - P2P 场景用 `CreateListenSocketP2P` / `ConnectP2P`，Steam 自动处理打洞与中继路由。
  - **开源版本 GameNetworkingSockets**（BSD-3）："开源代码不支持访问中继网络"，但提供完整 UDP 传输 + NAT 穿越逻辑；跨平台（非 Steam 平台）可经 **Custom Signaling** 自定义信令服务器实现 P2P（`ConnectP2PCustomSignaling`）。
  - FakeIP 机制：给 P2P 会话分配"看起来像公网 IPv4"的保留地址，让旧代码（按 IP 寻址的游戏）几乎无改动运行——**这对 CivLink 很有借鉴价值**（详见 §7）。
- **SDR 路由/中继协议公开资料**：协议定义在 Valve 开源库与社区反编译中可查（如 https://github.com/mariotaku/steamlink.py 的 `steamdatagram_messages_sdr.proto`）；`GameNetworkingSockets` 的 `README_P2P.md`（https://github.com/ValveSoftware/GameNetworkingSockets/blob/master/README_P2P.md）说明 P2P 支持的实现方式。

### 3.3 RakNet 自带 NAT 穿透：`RakNet::NatPunchthroughClient`

- 官方手册：https://www.raknet.net/raknet/manual/natpunchthrough.html（要点：需一台**不在 NAT 后面的用户托管服务器**运行 `NatPunchthroughServer` 插件，客户端连上它后，服务器获知双方外部地址，指令双方同时互连）。
- 源码证据（facebookarchive/RakNet，BSD 风格许可，Oculus VR 版权：https://github.com/facebookarchive/RakNet，`Source/NatPunchthroughClient.h` 已抓取）：
  - `PunchthroughConfiguration` 时序参数：`TIME_BETWEEN_PUNCH_ATTEMPTS_INTERNAL=15ms`、`UDP_SENDS_PER_PORT_EXTERNAL=8`、`MAX_PREDICTIVE_PORT_RANGE=2`（预测端口）、`EXTERNAL_IP_WAIT_BETWEEN_PORTS=200ms`；官方注释给出 8 人场景总耗时约 **8 秒**。
  - 打洞策略：先试内部 IP（同 LAN 直连优先），再外部 IP 多端口扫描；`FindRouterPortStride()` 探测对称 NAT 的端口步长（注释列出 Trendnet/D-Link/Buffalo/Netgear 等多型号路由器的实测兼容记录）。
  - `GetUPNPPortMappings()`：内置 miniupnpc 对接，可自动请求 UPnP 端口映射。
  - 失败码：`ID_NAT_PUNCHTHROUGH_FAILED` / `ID_NAT_TARGET_UNRESPONSIVE` 等；`retryOnFailure=true` 时失败自动重试。
- **关键结论**：文明6 底层就是 RakNet，但 CivLink 是**旁观/代理**（hook DLL 观测、agent 应答），不是要改游戏内部协议；因此 RakNet 的打洞插件对 CivLink 的意义是**架构参考**（协调服务器 + 同时发包 + 端口预测 + UPnP 辅助），而非直接复用。

---

## 4. 广播跨网方案：如何在非局域网模拟 255.255.255.255 广播

文明6 发现阶段发**二层+三层广播包**到 62900-62999（社区抓包实证，§6）。跨网只有两条路：

### 4.1 方案 A：二层 VPN 承载广播（虚拟以太网）

- **原理**：让玩家获得同一虚拟二层网段（如 OpenVPN TAP 模式、ZeroTier、n2n），广播包在虚拟网内被转发。
- **可行性**：ZeroTier/n2n/OpenVPN TAP 均可承载广播；社区实测（yllhwa：https://blog.yllhwa.com/blog/civilization-6-multiplayer/）OpenVPN TAP 组网可稳定 8 人联机 4 小时。
- **两大坑**（社区实测）：
  1. **Windows 只在「主网卡」发广播**：即使组网成功、能 ping 通，Windows 也不把广播发到虚拟网卡——需用 [WinIPBroadcast](https://github.com/dechamps/WinIPBroadcast) 把各网卡广播互相转发（yllhwa 博客明确指出）。
  2. **部分组网工具不转发广播**：蒲公英（商业）对广播包不转发，导致"ping 通但搜不到房"（chenxi65535 博客实证，§6）。
- **License 注意**：OpenVPN（GPL-2.0）、WireGuard（GPL-2.0）、n2n（GPL-3.0）均为强 copyleft，**不适合直接内嵌进开源项目**，只适合作为「用户自行部署的外部工具」在文档中引导。

### 4.2 方案 B：应用层把广播变成定向单播（CivLink 现状，推荐）

- **原理**：客户端本要发广播 62900-62999；CivLink agent 拦截/代理该流量，改发**定向 UDP** 到房主（经穿透后的地址），房主 agent 再把包"注入"本机游戏（模拟收到广播）。反向亦然。
- **本项目已实现**：agent 直接绑 100 端口应答广播请求（模拟房主）——正是"应用层广播→单播转换"的形态。
- **社区先例**：
  - [chenxi65535/civ6-multiplay](https://github.com/chenxi65535/civ6-multiplay)（博客 https://www.cnblogs.com/chenxi65535/p/18515726）：Python UDP 代理，先代理 62900-62999（房间发现），再加入房间时**还要代理 62056**（数据面），实测成功；该方案需要第三台"代理机"与房主同网。
  - yllhwa 博客同款思路："房主有公网 IP（或 IPv6）时，可在每台 PC 上写程序把广播包目的 IP 改成服务端"。
- **结论**：方案 B 正是 CivLink 的既有架构，且比方案 A 更干净：**广播只在应用层出现，底层是普通单播 UDP，天然兼容 NAT 穿透/TURN 中继**。需要补的是：数据面 62056 的流量也要走同样的穿透/中继通道（不能只代理发现端口）。

---

## 5. 可靠性：UDP 丢包 / 重传 / 乱序

### 5.1 文明6 数据面已有可靠层吗？

- **有**。文明6 底层是 RakNet，而 RakNet 在 UDP 之上自带**可靠消息、分片重组、有序、ACK/重传**（Minecraft Wiki 对 RakNet 的说明：https://minecraft.wiki/w/RakNet；RakNet 官方：https://github.com/facebookarchive/RakNet）。
- 因此：**CivLink 不需要为"游戏数据本身"引入可靠 UDP 库**——RakNet 自己处理。CivLink 的 agent/hook 是**透明旁路转发**，只需尽量原样转发 UDP 包（含重传语义），丢包重传由游戏内 RakNet 完成。

### 5.2 若中继/隧道自身需要可靠传输（例如跨不稳定的公网信道）

| 方案 | License | 特点 | 是否建议 |
|---|---|---|---|
| [KCP](https://github.com/skywind3000/kcp) | MIT | ARQ 快速重传；官方数据：多花 10-20% 带宽，平均延迟降 30-40%、最大延迟降 3 倍（来源：官方 README）；中文详解 https://zhuanlan.zhihu.com/p/112442341 | 可选（若中继链路丢包率高） |
| [QUIC](https://www.rfc-editor.org/rfc/rfc9000) | IETF 标准 | 连接迁移（WiFi↔4G 不断连，来源：https://zhuanlan.zhihu.com/p/655070575）；TLS1.3 内建；头开销低 | 重，对 CivLink 过度设计 |
| UDT/UDT4 | v4 为 BSD（伊利诺伊大学版权；来源：https://en.wikipedia.org/wiki/UDP-based_Data_Transfer_Protocol 及 Oracle 文档页） | 面向大数据量可靠传输，拥塞控制重 | 不适合游戏实时性 |
| Valve GameNetworkingSockets | BSD-3 | 可靠+不可靠消息、分片重组、P2P/NAT 穿越、加密——**一站式** | **最推荐**（若需要自研传输层） |

### 5.3 企业级中继怎么做可靠性

- Steam SDR / GameNetworkingSockets：库层提供可靠消息管道 + 加密（SDR 官方文档：流量"经过验证、加密并受到速率限制"），中继只转发，可靠性在端点处理——**这正是 CivLink 应该抄的作业：中继节点保持无状态转发，可靠性与打洞逻辑放在客户端**。
- frp/rathole：UDP 转发模式下也是尽力转发（frp 的 KCP 选项可用于其隧道自身）。

---

## 6. 文明6 跨网联机社区实测（一手证据）

| 来源 | 结论 | URL |
|---|---|---|
| yllhwa《文明6 联机方法与实践》(2023-02-24) | 广播到 62900-62999（二+三层广播）；Windows 只在主网卡广播 → 需 WinIPBroadcast；ZeroTier/N2N 二层可承载广播；Tailscale/WireGuard 三层默认不行；P2P 打洞（ZeroTier/Tailscale）不稳定（尤其 NAT4/教育网），4-8 人局被淘汰；**OpenVPN TAP 最稳**：腾讯云北京 8Mbps，8 人联机 4 小时无问题 | https://blog.yllhwa.com/blog/civilization-6-multiplayer/ |
| chenxi65535《文明6虚拟局域网联机教程》(2024-10-30) | 蒲公英不转发广播 → 搜不到房；代理 62900-62999 解决发现，**加入房间需再代理 62056**；python 代理（civ6-multiplay 开源）实测成功 | https://www.cnblogs.com/chenxi65535/p/18515726 / https://github.com/chenxi65535/civ6-multiplay |
| Reddit/其他 | 未检索到专门针对 civ6 的开源穿透项目；此细分领域基本被商业 VPN 组网（Radmin/Hamachi/蒲公英）与上述自制代理覆盖 | — |

---

## 7. 对 CivLink 开源版的建议（重点）

### 7.1 推荐的穿透/中继技术栈（分层）

```
玩家 A (NAT)               玩家 B (NAT)
   │                            │
   ├─① UPnP/PCP/NAT-PMP 自动端口映射（第一优先，零服务器成本）
   ├─② UDP 打洞（自建轻量 facilitator / 信令服务器，RakNet 式时序）
   └─③ TURN 中继兜底（coturn，BSD-3，公网 VPS）
        │                            │
        └──── 信令通道（TCP/WebSocket，公网协调服务器）────┘
```

1. **UPnP 自动端口映射**（第一优先）：客户端先尝试向自家路由器请求 62900-62999 或 62056 的映射（可用 miniupnpc 思路，参考 RakNet `GetUPNPPortMappings()`）。成本≈0，家用路由器命中率高。
2. **UDP 打洞 + 轻量协调服务器**：自建一个极简公网信令服务（等价于 RakNet NatPunchthroughServer / STUN）：交换双方公网映射、指令同时发包；对称 NAT 做端口预测。**不必引入完整 ICE**。
3. **TURN 兜底（coturn，BSD-3-Clause）**：打洞失败的场景（对称 NAT/CGNAT/校园网）自动降级中继。License 完全兼容开源。
4. **应用层广播→单播**（已实现，保持）：发现阶段 agent 把广播改为定向单播；**补齐数据面 62056 的转发通道**——数据包也要能走上述穿透/中继路径。
5. **可选：引入 GameNetworkingSockets（BSD-3）** 作为传输层（可靠 UDP + NAT 穿越 + 加密），如果希望"传输层也开源自研"；否则用现成 UDP socket + TURN 客户端库（如 libnice / pion / coturn 配套客户端）更省事。

### 7.2 不建议引入

- **ngrok / 商业托管隧道**：免费版并发/延迟限制，游戏场景不适用。
- **WireGuard / OpenVPN / n2n / ZeroTier 内嵌**：强 copyleft（GPL/BSL）与闭源核心与开源化目标冲突；且三层 VPN 不解决广播问题（仍需应用层转换）。**可以作为文档中"给玩家推荐的外部组网工具"提及，但不要内嵌代码**。
- **KCP/QUIC/UDT 作为游戏数据可靠层**：RakNet 已自带可靠传输，重复引入反而破坏游戏协议语义；仅当**中继隧道自身**丢包严重时，才考虑 KCP（MIT，最轻）。

### 7.3 License 兼容性一览（与开源化直接相关）

| 组件 | License | 可内嵌/链接 | 备注 |
|---|---|---|---|
| coturn（TURN 服务器） | BSD-3-Clause | ✅ | 作为独立服务端部署即可 |
| frp / rathole | Apache-2.0 | ✅ | 若走"隧道中继"路线可选 |
| chisel | MIT | ✅ | UDP 支持有限，谨慎 |
| GameNetworkingSockets | BSD-3-Clause | ✅ | 最贴合游戏传输需求 |
| KCP | MIT | ✅ | 可选 |
| RakNet 源码（参考） | BSD 风格（Oculus 版权） | ✅（参考/引用） | 文明6 内嵌的 RakNet 属游戏厂商侧，CivLink 只作参考 |
| WireGuard / OpenVPN / n2n | GPL-2.0/3.0 | ❌ 内嵌 | 仅文档推荐外部工具 |
| ZeroTier | BSL / 部分开源 | ⚠️ | 商用限制，不建议依赖 |

### 7.4 需要澄清/待决策的问题（留给主流程）

1. CivLink 的目标形态：**自带轻量中继服务端**（用户自部署 coturn/frp）还是**纯客户端 + 第三方中继**？建议前者（提供官方示例 docker-compose）。
2. 协调服务器是否开源托管（类似公共 STUN 服务器，如 stun.cloudflare.com 之类公共服务可作为默认配置）——可默认内置公共 STUN，TURN 留给用户自建。
3. 62056 数据面转发当前是**旁观转发**还是**注入**？（hook DLL 观测 + agent 应答已覆盖发现面；数据面若需跨网，agent 需代理/注入 62056 双向流量，与 civ6-multiplay 的做法一致。）
4. FakeIP 思路（Steam SDR）：是否给"虚拟房主"分配一个保留网段地址，让游戏 socket 层无感？（高级选项，仅当 hook 层能做到地址替换时。）

---

## 8. 结论：3 条最重要结论 + 推荐技术栈

### 三条最重要结论

1. **文明6 的跨网联机已被社区证明可行，且两条路都已验证**：二层 VPN 承载广播（OpenVPN TAP + WinIPBroadcast，8 人 4 小时稳定）或应用层广播→单播代理（civ6-multiplay 先例，62900-62999 + 62056 双端口代理）。CivLink 的 agent 架构正好落在后者——**方向正确**，但必须补齐**数据面 62056** 的转发，不能只代理发现端口。
2. **穿透必须「打洞 + 中继」双保险**：国内对称 NAT（NAT4/教育网/CGNAT）比例高，纯 UDP 打洞不稳定（社区实测淘汰 P2P 打洞方案）；标准答案是 ICE 式分级——直连 → 打洞 → TURN 中继兜底。开源组件齐全且 License 友好（coturn BSD-3、frp/rathole Apache-2.0）。
3. **可靠性不需要自造轮子**：文明6 底层 RakNet 自带可靠传输/分片/重传，CivLink 只需透明转发 UDP；若中继隧道自身要可靠化，最轻量是 KCP（MIT），最完整是 Valve GameNetworkingSockets（BSD-3，含 NAT 穿越+加密）。强 copyleft 组件（WireGuard/OpenVPN/n2n GPL）只能作为文档推荐的外部工具，不可内嵌。

### 推荐穿透/中继技术栈

> **分层：UPnP/PCP 自动映射（首选）→ 自建轻量打洞协调服务器（RakNet 式时序 + 端口预测）→ coturn TURN 中继兜底（BSD-3，公网 VPS 自部署）→ 应用层广播→单播转换（已有 agent，补 62056 数据面）**

- 服务端：coturn（BSD-3）+ 可选 frp/rathole（Apache-2.0）作为隧道替代
- 客户端：现有 agent/hook + miniupnpc（UPnP）+ TURN 客户端库；可选 GameNetworkingSockets（BSD-3）统一传输层
- 许可证状态：全套可商用、可内嵌、可开源（无 GPL/BSL 依赖）
- 部署成本：一台几十元/月的低配公网 VPS 即可；STUN 免费，TURN 带宽按 8Mbps 实测可支撑 8 人局

---

## 附录：参考 URL 汇总

**协议标准**：RFC 3489 / 5389 / 5766 / 5128 / 6886 / 6887 / 8445（rfc-editor.org）；NAT 类型检测 natchecker.com/zh
**开源组件**：coturn/coturn（BSD-3）· fatedier/frp（Apache-2.0）· rathole-org/rathole（Apache-2.0）· jpillora/chisel（MIT）· ValveSoftware/GameNetworkingSockets（BSD-3）· skywind3000/kcp（MIT）· ntop/n2n（GPL-3.0）· zerotier/ZeroTierOne（BSL）· dechamps/WinIPBroadcast（MIT）· facebookarchive/RakNet（BSD 风格）
**Steam SDR**：官方文档（中文）partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay · 官方公告 steamcommunity.com/groups/steamworks/announcements/detail/1791775741704351698 · README_P2P.md
**RakNet 打洞**：手册 raknet.net/raknet/manual/natpunchthrough.html · NatPunchthroughClient.h 源码
**社区实测**：yllhwa 博客 blog.yllhwa.com/blog/civilization-6-multiplayer/ · chenxi65535 博客 www.cnblogs.com/chenxi65535/p/18515726 · civ6-multiplay 仓库
**商业加速器**：UU uu.163.com · 奇游原理 bestqiyou.com/zh-hans/blogs/qiyoujiasuqidegongzuoyuanlishishenmemianfeibanbenzaisuduyuwendingxingfangmianyouhexianzhi
**盘点文**：CSDN《主流内网穿透方案技术盘点》www.csdn.net/article/2026-09-04/164367623 · appinn rathole 介绍
