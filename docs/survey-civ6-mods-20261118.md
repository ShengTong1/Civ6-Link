# 文明6局域网联机助手开源化 —— 技术生态调研报告

- **调研日期**：2026-11-18
- **调研范围**：GitHub 开源项目（License/star/活跃度经 GitHub API 核实）、官方联机机制、Steam 创意工坊、同类游戏（Civ5/Humankind/Old World）、中文社区经验
- **检索手段**：web_search（多引擎）、platform_search（github/reddit/youtube/bilibili/steam 相关）、GitHub REST API（api.github.com）、网页全文抓取（injciv6 README、博客等）
- **数据时效**：star 数、最后提交时间均为 2026-11-18 抓取快照

---

## 1. 调研结论速览（TL;DR）

1. **Civ6「局域网」联机的本质**：房间发现 = 客户端向 `255.255.255.255`（二层 `ff:ff:ff:ff:ff:ff`）发 UDP 广播，端口 **62900→62999 共 100 个端口**；数据面 = **62056 端口** UDP 单播。官方 Internet 多人模式走 **Steam P2P**（Steamworks NAT 打洞）。**游戏没有任何"填服务器 IP"的入口**——所有修复方案都必须在发现层做手脚（Hook/代理/组网）。
2. **官方服务空白**：无官方 Dedicated Server、无 Pitboss（Civ4/5 有，Civ6 只有 Play By Cloud 云存档异步回合）、无掉线重连。官方 Internet 模式对国内玩家极不稳定（国际链路 + 防火墙）。
3. **开源生态小而分散**：Civ6 联机领域最大项目是 **xaxys/injciv6（207★，无 License，2024-03 停更）**；其余多为 2024-2026 年新出现的 MIT/GPL-3.0 小工具。没有带明确 License 的"现代"实现 —— 这正是一个开源空位。
4. **中文社区痛点高度一致**：绝大多数"搜不到房间"的根源是 **Windows 只在首选网卡上发全局 IP 广播**（虚拟组网后 ping 通但列表为空），以及官方 Internet 模式不稳。组网软件中 ZeroTier/N2N/蒲公英（二层）可行，Tailscale/WireGuard/蒲公英免费版（三层）默认不转发广播。

---

## 2. 文明6 官方联机机制现状

### 2.1 房间发现（来源：injciv6 README 原文 + yllhwa/Peaboss/chenxi65535 博客交叉验证）

- 客户端点击「刷新」后，向 `eth.dst=ff:ff:ff:ff:ff:ff && ip.dst=255.255.255.255` 发送 **UDP 广播包，端口 62900 → 62999 共 100 个包**（逐端口探测防占用），每包约 4 字节。
- 服务器通常在 **62900** 端口监听，收到广播后回复**多个约 1104 字节的 UDP 单播包**，内容为 JSON 格式房间信息。
- 客户端在自己发送包的端口上监听回复，收完（或超时）后短暂关闭该 socket。
- 已知坑（多源一致）：**Windows 只在「首选上网网卡」上发送全局 IP 广播**（yllhwa、Peaboss 博客均指出），所以虚拟组网（Tailscale/WireGuard 等 L3 网卡）后即使 ping 通也搜不到房；Linux 客户端在无默认路由的静态 IP 网络上也可能不知道往哪个接口发广播（Steam 官方指南 id=3773983709「Linux: Fix Missing LAN Lobbies」）。

### 2.2 数据面（来源：injciv6 README 原文）

- 发现完成后，客户端在 **62056** 端口打开监听，并向服务器 IP 的 **62056** 端口发送 UDP 单播首包（约 120 字节），服务器回包后联机建立。
- **关键细节**：联机阶段用的是 **WSASendTo / WSARecvFrom**（不是 sendto/recvfrom）；流程是先 bind `0.0.0.0:62056` → 再 WSARecvFrom → 再 WSASendTo；socket 是非阻塞 + 轮询 WSARecvFrom（若替换 socket 成阻塞会导致游戏卡死）。
- 游戏二进制位于 `Base\Binaries\Win64Steam` 与 `Win64EOS` 两个目录（injciv6 README）。

### 2.3 Internet 模式与官方服务

- 官方 Internet 多人模式使用 **Steam 自带的 P2P 网络**（Steamworks NAT 打洞），无官方中继/专用服务器（Steam 官方讨论帖 [Multiplayer Disconnection inquiries](https://steamcommunity.com/app/289070/discussions/4/1489992713711433835)；CivFanatics 论坛 2016 年帖 [Will multiplayer be integrated this time?](https://forums.civfanatics.com/threads/will-multiplayer-be-integrated-this-time.567155/)：「Civ has never used servers, it's always been a P2P game」）。
- **无官方 Dedicated Server**：玩家多次在 Steam 讨论区询问「Pitboss Server?」均无官方回应；社区结论为不存在。
- **Pitboss 现状**：Civ6 **没有官方 Pitboss**（Civ4/5 有）。官方提供的异步模式是 **Play By Cloud**（2K 云存档异步回合）；硬核社群用 **PBEM**（邮箱传档，realmsbeyond.net 论坛 2024 年仍在运行）。
- 2020-01-20 Steam App 更新曾改动 P2P 代码导致联机不稳定（cpl.gg 公告 2020-02-13）。

### 2.4 结论：本项目的技术定位

Civ6 联机 = 「UDP 广播发现（62900-62999）+ RakNet/Steam P2P 数据面」。没有 IP 直连入口、没有官方服务器 → 任何第三方方案（Hook 改单播、广播代理、虚拟组网、模拟房主应答）都必须**在发现层和 62056 数据面**上做文章。本项目已实现的「agent 绑定 62900-62999 全发现端口应答广告页」正是这个生态缺口的最优解位置。

---

## 3. GitHub 开源项目清单（License 已核实）

> star 数截至 2026-11-18；「无 License」= GitHub API license 字段为 null，**未经授权不得复制代码**（只可借鉴机制）。

### 3.1 联机发现 / 修复核心项目（直接相关）

| 项目 | star | 语言 | License | 活跃度 | 解决的问题 |
|---|---|---|---|---|---|
| [xaxys/injciv6](https://github.com/xaxys/injciv6) | 207 | C++ (+Go GUI) | **无 License** | 2024-03 停更 | 注入 DLL Hook sendto，把广播改单播，支持 IPv4/IPv6（FakeIP） |
| [MXWXZ/civrip](https://github.com/MXWXZ/civrip) | 6 | C++ | **GPL-3.0** | 2025-05 | 「文明6及老游戏联机组网」100% 开源 GUI（虚拟网络 GUI） |
| [lqcx12321/Civilization6_Multiplayer-ipv4](https://github.com/lqcx12321/Civilization6_Multiplayer-ipv4) | 2 | C++ | 无 License | 2026-06 | 基于 injciv6 精简的 IPv4 联机 GUI |
| [lirunan22/Civ6---Virtual-LAN-Helper](https://github.com/lirunan22/Civ6---Virtual-LAN-Helper) | 1 | Python | **MIT** | 2026-11 活跃 | 跨平台，解决 ZeroTier/Tailscale 下 UDP 广播与发现 |
| [chenxi65535/civ6-multiplay](https://github.com/chenxi65535/civ6-multiplay) | 3 | Python | **MIT** | 2024-10 | 文明6联机解决方案：UDP 代理（广播经代理转发到服务器） |
| [Frwere/civ6-l3-discovery-helper](https://github.com/Frwere/civ6-l3-discovery-helper) | 4 | Python | **MIT** | 2026-05 | 「Civ6 三层局域网房间发现助手」，专治蒲公英/ZeroTier/WireGuard 组网刷不出房 |
| [drake127/civ6-no-tos](https://github.com/drake127/civ6-no-tos) | 0 | Lua | **GPL-3.0** | 2026-10 | 抑制 2K ToS 弹窗且不破坏局域网/多人连接 |
| [dechamps/WinIPBroadcast](https://github.com/dechamps/WinIPBroadcast) | 309 | C | **GPL-3.0** | 2018-01（停更但可用） | Windows 把 IP 广播自动转发到所有网卡（通用工具，非 Civ6 专用） |

**重点项目细节**：

- **xaxys/injciv6**（207★，无 License）：本领域最大项目，**2024-03 已停止维护**，8 个 fork 全部 0★ 且无 License。技术栈：MinGW-w64（i686+x86_64）+ MinHook + Go GUI；仅 Windows。实现原理（README 全文抓取）：
  - Hook `sendto`：客户端广播 → 单播到指定服务器 IP（端口不变）；建立 **Socket 替换表**，新建同端口 IPv4/IPv6 socket。
  - Hook `recvfrom`/`select`：把替换表中端口的接收/等待切到新 socket；IPv6 回包时建立 **FakeIP 表**（IPv6 → `127.0.127.1~127.0.127.100`，同 Clash FakeIP 原理）。
  - IPv6 联机阶段额外 Hook `WSASendTo`/`WSARecvFrom`/`bind`（IPv4 直接沿用原联机机制）；IPv6 需服务端也注入（填 `::0`）。
  - 已知 bug：**3 人及以上同时加入有兼容问题**（IPv4 无解；IPv6 需服务端 GUI ≥v0.3.3 + 客户端 ≤v0.3.2 组合缓解）；Windows Defender 报毒（远程线程注入）。
  - 改自 gitcode.net/PeaZomboss/miscellaneous（PeaZomboss 的 Hook 注入框架）。
- **MXWXZ/civrip**（GPL-3.0）：虚拟组网 GUI，目标游戏含文明6及老游戏；GPL-3.0 传染性需注意。
- **chenxi65535/civ6-multiplay**（MIT）：**代理思路**——在房主 LAN 内跑一个代理设备，收广播→经 VPN 转发给房主→回包再转回，切 62056 数据面时同样代理；实测成功。与 Hook 思路互补（无注入、无 Defender 误报，但需要一台常开代理设备）。
- **Frwere/civ6-l3-discovery-helper**（MIT）：最新（2026-05）出现，专治 **L3 组网**（蒲公英/ZeroTier/WireGuard 组网后 ping 通但刷不出房）——与本项目痛点直接重叠。
- **dechamps/WinIPBroadcast**（GPL-3.0，309★）：通用广播转发工具，被中文博客广泛推荐为 Civ6 组网搜房方案之一。

### 3.2 多人体验 / 辅助类 mod

| 项目 | star | 语言 | License | 说明 |
|---|---|---|---|---|
| [d-jackthenarrator/Civ6-MPH](https://github.com/d-jackthenarrator/Civ6-MPH) | 6 | Lua | **Apache-2.0** | Steam 创意工坊「Multiplayer Helper (MPH)」的 GitHub 源码版（回合计时、游戏信息等） |
| [code-for-coffee/civ6-team-multiplayer-mod](https://github.com/code-for-coffee/civ6-team-multiplayer-mod) | 2 | Lua | **MIT** | 组队多人 mod（2016 停更） |
| [pfink/Civ6-BetterMultiplayerTurnModes](https://github.com/pfink/Civ6-BetterMultiplayerTurnModes) | 1 | Lua | 无 License | 多人回合模式改进（2023-06） |
| [badwolf-vitalii/Civ6SmartTurnTimer](https://github.com/badwolf-vitalii/Civ6SmartTurnTimer) | 0 | Lua | **MIT** | 智能回合计时（2026-10） |
| [fekfekfek/Civ6ModVersionChecker](https://github.com/fekfekfek/Civ6ModVersionChecker) | 0 | Lua | 无 License | 检查房内各玩家 mod 版本不一致（2021-09） |
| [alex-stout/civ6-mac-updater](https://github.com/alex-stout/civ6-mac-updater) | 12 | Rust | 无 License | 修 mac/Windows 版本号不一致导致的 "version mismatch host" 错误（2026-10 仍活跃） |
| [lcorning12/civ6ai](https://github.com/lcorning12/civ6ai) / [unendev/Civ6-LLM-Leader](https://github.com/unendev/Civ6-LLM-Leader) | 0 | Python | 无 License / **MIT** | AI 打多人的实验项目（参考价值低） |

### 3.3 底层网络库（非 Civ6 专用）

| 项目 | star | 语言 | License | 说明 |
|---|---|---|---|---|
| [facebookarchive/RakNet](https://github.com/facebookarchive/RakNet) | — | C++ | **modified BSD**（Meta 官方博客 2014-07-07 确认 Oculus 收购后开源） | RakNet 官方源码（Civ6 数据面所用可靠 UDP 协议的参考实现） |
| [openmultiplayer/RakNet](https://github.com/openmultiplayer/RakNet) | 27 | C++ | 无独立 License（沿用原 RakNet 许可） | open.mp（SA-MP 开源替代）维护的 RakNet 修改版，2026-04 仍更新 |
| [b23r0/rust-raknet](https://github.com/b23r0/rust-raknet) | **300** | Rust | **MIT** | 高性能 Reliable UDP 异步库（tokio），2026-11 仍活跃；话题含 gfw/加速器 |

### 3.4 文明5（同类修复参考）

| 项目 | star | 语言 | License | 说明 |
|---|---|---|---|---|
| [Lymia/MPPatch](https://github.com/Lymia/MPPatch) | 55 | Scala | **MIT** | Civ5 允许 **modded multiplayer** 的 patch（2026-11 仍在开发，24 open issues） |
| [OBLASTWAR/reload-fix](https://github.com/OBLASTWAR/reload-fix) | 1 | Lua | 无 License | HellBlazer 的 Civ5 reload fix：多人存档重载不再需要 hotjoin（掉线重连相关思路） |
| [LoneGazebo/Community-Patch-DLL](https://github.com/LoneGazebo/Community-Patch-DLL) | 452 | C++ | Other（NOASSERTION 自定义） | Civ5 SDK + Vox Populi 社区补丁（DLL 级 mod 的先例） |
| [Serpens66/MP_MODSPACK_v20_EUI129a](https://github.com/Serpens66/MP_MODSPACK_v20_EUI129a) | 0 | Lua | 无 License | Civ5 多人 modpack 打包先例 |

### 3.5 Pitboss 生态（Civ4 参考）

- [civ4-mp/pbmod](https://github.com/civ4-mp/pbmod)（3★，C++，**GPL-2.0**，2025-02 更新）：Civ4 Pitboss mods 集合。
- [civ4-mp/pbspy](https://github.com/civ4-mp/pbspy)（0★，Python，无 License，2026-05 更新）：Pitboss 游戏管理网站——若未来做「异步房间管理」可参考产品形态。

### 3.6 其他相关（非仓库）

- Steam 指南 [Linux: Fix Missing LAN Lobbies](https://steamcommunity.com/sharedfiles/filedetails/?id=3773983709)（id=3773983709）：确认广播为 `255.255.255.255` 有限广播，Linux 需显式路由。
- Reddit r/PiratedGames [Steamworks fix broken?](https://www.reddit.com/r/PiratedGames/)（2023-04-30）：破解版用 spacewar Steamworks fix 联机失效——「Steamworks fix/online fix」社区属于灰色地带，**不纳入可借鉴清单**（合法合规起见）。

---

## 4. 创意工坊 / 社区联机相关 mod

1. **Multiplayer Helper (MPH)**：[创意工坊 id=2357532056](https://steamcommunity.com/sharedfiles/filedetails/?id=2357532056)（[v1.8.0 id=3307282026](https://steamcommunity.com/sharedfiles/filedetails/?id=3307282026)、[BBG BBS MPH id=2887805556](https://steamcommunity.com/sharedfiles/filedetails/?id=2887805556)）—— Civ6 多人玩家事实标配：回合计时、游戏信息、自动跳过等；源码见 [d-jackthenarrator/Civ6-MPH（Apache-2.0）](https://github.com/d-jackthenarrator/Civ6-MPH)。
2. **[CIV 6 Multiplayer Desync/Lag Free UI+QOL](https://steamcommunity.com/sharedfiles/filedetails/?id=3393196331)**（id=3393196331）：多人掉线/卡顿优化 UI 包。
3. Steam 指南 **[Multiplayer Desync Fix](https://steamcommunity.com/sharedfiles/filedetails/?id=3772297309)**（id=3772297309）：desync 通常源于「禁用 mod 后文件仍激活」，需手动清理。
4. **掉线重连现状**：官方无重连机制；多人局掉线=该玩家被踢或整局崩。社区兜底方案只有 Play By Cloud / PBEM 异步模式。Civ5 的 reload-fix（3.4）提供「重载存档免 hotjoin」思路，Civ6 未见等价项目 —— 值得关注。
5. Civ6 官方支持多人 mod：游戏内创建房间时可勾选 mod（[pcgamesn 2016 指南](https://www.pcgamesn.com/civilization-vi/civ-6-multiplayer-guide)），且 mod 版本不一致是多人 desync/拒绝加入的常见原因（对应 Civ6ModVersionChecker）。

---

## 5. 同类游戏联机方案

| 游戏 | 联机方式 | 现状与修复 |
|---|---|---|
| **文明5** | Steam P2P + 局域网（需 Steam 登录）；官方 Pitboss 模式（buggy） | 修复集中在 modded-multiplayer 补丁（Lymia/MPPatch，MIT，活跃）、reload-fix、modpack（Serpens66）。局域网/Steam P2P 结构同 Civ6，**其修复工具是 Civ6 生态最好的方法论参考** |
| **Humankind** | Steam P2P 官方联机（2023-09 官方百科仍运营） | 未见显著开源修复项目；联机体验口碑一般（知乎 2022-09 讨论） |
| **Old World** | 基本无多人 | Mohawk Games（Soren Johnson），仅「Barbarian Horde」场景支持 co-op（Epic 新闻 2021-01）；无常规 PVP 联机，**不存在局域网问题** |

共性结论：4X 游戏联机普遍是 **P2P + 广播/平台发现**，官方不做专用服务器；第三方修复一律落在「发现层（广播→单播/代理/组网）」与「数据面（UDP 转发/打洞）」。本项目的 Hook/代理/模拟房主路线与生态一致。

---

## 6. 中文社区经验帖要点（贴吧 / NGA / 知乎 / B站 / 博客）

> 注：贴吧/NGA 部分帖子经搜索引擎可检索到但未逐条抓取；以下要点以已抓取的博客、B站、知乎、游民星空、V2EX 为主，均含链接。

1. **广播只走首选网卡**（核心共识）：[yllhwa《文明 6 联机方法与实践》](https://blog.yllhwa.com/blog/civilization-6-multiplayer/)（2023-02，WireShark 证实广播机制；推荐 WinIPBroadcast 转发广播、OpenVPN 组网最稳，实测 8 人 4 小时不掉线）；[Peaboss《使用Hook拦截socket函数解决…找不到房间…以文明6为例》](https://www.cnblogs.com/Peaboss/p/17059052.html)（2023-01，Hook 思路与 injciv6 同源）；[CSDN《文明6 建立（虚拟）局域网联机 踩坑》](https://blog.csdn.net/qq_40151332/article/details/128023224)；[游民星空《文明6局域网游戏找不到房间解决办法》](https://www.gamersky.com/)（2020-07：禁用多余网卡）；[V2EX 帖](https://www.v2ex.com/t/1213524)（2026-05：手机端文明6 用 WireGuard/EasyTier/Tailscale 均因无法广播 IP 而刷不出房）。
2. **L3 组网不转发广播 → 需要代理/Hook**：[chenxi65535 博客园《文明6虚拟局域网联机教程（搜不到房间的解决办法）》](https://www.cnblogs.com/chenxi65535/p/18515726.html)（2024-10，蒲公英免费版不转发广播，解法=一台代理设备跑 Python 代理，含 62056 数据面转发；配套 [civ6-multiplay 仓库（MIT）](https://github.com/chenxi65535/civ6-multiplay) 与 [B站专栏](https://www.bilibili.com/opus/993912143071936516)）；[B站专栏《文明6等游戏虚拟局域网联机搜不到房间的解决办法》](https://www.bilibili.com/opus/609896741991801995)（2021-12，ZeroTier Moon 组网后 ping 通但搜不到房）。
3. **官方 Internet 模式国内不稳**（知乎多帖共识）：官方服务器挂加速器/直连均不稳定；[Maple《Explore the best networking technology for Civilization 6 - WireGuard + udp2raw》](https://maple.xlog.app/civ6-multiplayer-connect)（2025-01）推荐 WireGuard+udp2raw 抗国际链路劣化。
4. **B站教程视频**：「手把手教你文明6最简单联机教程」[av116390023531311](https://www.bilibili.com/video/av116390023531311)、「文明6 PVP 联机掉线 终极 解决方法！！！」[av628579784](https://www.bilibili.com/video/av628579784)、「2026文明6联机终极教程」[av117138136241836](https://www.bilibili.com/video/av117138136241836)、「【文明6】联机小技巧」[av935613068](https://www.bilibili.com/video/av935613068)、「【中字】文明6多人联机第一课」[av112918951626774](https://www.bilibili.com/video/av112918951626774)、「文明6双人联机体验」[av907071470](https://www.bilibili.com/video/av907071470)。
5. **WireGuard 虚拟网卡干扰**：[xchens.cn《如何异地组网来玩局域网游戏 - 文明6》](https://xchens.cn/)：关掉多余网卡避免干扰互寻。
6. **英文社区对应痛点**：Reddit r/CivVI [《A Guide on Playing with CIV VI's horrible multiplayer servers and de-sync issues》](https://www.reddit.com/r/CivVI/)（2023-05）；Steam 指南 Linux LAN 修复（见 3.6）。

---

## 7. 可借鉴清单（License 兼容性）

> 用户项目定位为「开源给所有游戏爱好者」，故优先选宽松许可、可安全引用的项目；无 License 项目只借鉴机制。

### 7.1 可直接借鉴/引用代码（宽松许可）

| 项目 | License | 可借鉴内容 |
|---|---|---|
| [chenxi65535/civ6-multiplay](https://github.com/chenxi65535/civ6-multiplay) | **MIT** | UDP 广播代理 + 62056 数据面转发的最小实现（Python，可直接抄） |
| [Frwere/civ6-l3-discovery-helper](https://github.com/Frwere/civ6-l3-discovery-helper) | **MIT** | L3 组网房间发现助手（与本项目痛点完全重叠，2026-05，很新） |
| [lirunan22/Civ6---Virtual-LAN-Helper](https://github.com/lirunan22/Civ6---Virtual-LAN-Helper) | **MIT** | 跨平台广播/发现解决思路 |
| [d-jackthenarrator/Civ6-MPH](https://github.com/d-jackthenarrator/Civ6-MPH) | **Apache-2.0** | 多人辅助 mod 的 Lua 源码（如需做房内工具可引） |
| [b23r0/rust-raknet](https://github.com/b23r0/rust-raknet) | **MIT** | Reliable UDP 实现参考（若本项目要自己实现 RakNet 风格可靠传输/模拟服务端） |
| [Lymia/MPPatch](https://github.com/Lymia/MPPatch) | **MIT** | Civ5 modded-multiplayer 补丁的 patch 方法论（活跃，2026-11 仍提交） |
| [badwolf-vitalii/Civ6SmartTurnTimer](https://github.com/badwolf-vitalii/Civ6SmartTurnTimer)、[unendev/Civ6-LLM-Leader](https://github.com/unendev/Civ6-LLM-Leader)、[code-for-coffee/civ6-team-multiplayer-mod](https://github.com/code-for-coffee/civ6-team-multiplayer-mod) | MIT | Lua mod 侧参考 |

### 7.2 可借鉴机制、引用代码需注意（Copyleft / 无 License）

| 项目 | License | 说明 |
|---|---|---|
| [xaxys/injciv6](https://github.com/xaxys/injciv6) | **无 License** | 机制最全的参考（Socket 替换表、FakeIP、WSASendTo/WSARecvFrom Hook、3人 bug）；**不复制代码**（用户背景已明确只借鉴机制）。它是停更项目 → 我们做「带 License 的现代实现」天然合理 |
| [MXWXZ/civrip](https://github.com/MXWXZ/civrip) | **GPL-3.0** | 借鉴虚拟组网 GUI 思路；引代码则本项目需 GPL-3.0 |
| [drake127/civ6-no-tos](https://github.com/drake127/civ6-no-tos) | **GPL-3.0** | 机制参考（不影响多人连接地绕开 2K ToS 弹窗） |
| [dechamps/WinIPBroadcast](https://github.com/dechamps/WinIPBroadcast) | **GPL-3.0** | 广播转发机制参考；本项目已有 100 端口模拟房主，未必需要 |
| [facebookarchive/RakNet](https://github.com/facebookarchive/RakNet) / openmultiplayer/RakNet | **modified BSD** / 沿用原许可 | 协议文档级参考（若需逆向/模拟 RakNet 语义）；BSD 系许可宽松，但注意保留版权声明 |
| [alex-stout/civ6-mac-updater](https://github.com/alex-stout/civ6-mac-updater) | 无 License | 跨平台版本一致性经验 |
| [OBLASTWAR/reload-fix](https://github.com/OBLASTWAR/reload-fix) | 无 License | 「重载免 hotjoin」机制参考（未来掉线重连功能） |
| [LoneGazebo/Community-Patch-DLL](https://github.com/LoneGazebo/Community-Patch-DLL) | Other | DLL 级 mod 与 SDK 用法先例（非直接相关） |
| [civ4-mp/pbmod](https://github.com/civ4-mp/pbmod) | **GPL-2.0** | Pitboss 产品形态参考（若未来做异步托管） |

### 7.3 对本项目的具体技术借鉴点（结合已实现功能）

1. **发现层**：injciv6 的「广播→单播」Socket 替换表思想 + civ6-multiplay 的「无注入代理」思路 + l3-discovery-helper 的 L3 组网视角——三者覆盖了「Hook、代理、组网」三条路线，本项目「模拟房主应答 100 发现端口」走的是第四条（不依赖真实房主在局域网），**生态中无 License 障碍的同类实现**。
2. **数据面**：62056 的 WSARecvFrom/WSASendTo 细节（injciv6 README 已给出）是 civlink_client.dll 与代理实现的事实依据；注意非阻塞 socket 替换。
3. **IPv6/FakeIP**：若未来支持 IPv6 公网直连，injciv6 的 FakeIP（127.0.127.1~100）与 0.0.0.0→[::0] 重定向是现成机制参考。
4. **多人稳定性**：3 人以上同时加入是生态公案（injciv6 未解决）；若本项目解决，是显著卖点。
5. **协作机会**：civ6-multiplay（MIT，2024-10）、Virtual-LAN-Helper（MIT，2026-11）、l3-discovery-helper（MIT，2026-05）都是活跃小项目，License 兼容，可作为上游/被引用方共建；injciv6 作者已停更，fork 均无 License——开源化后本项目有机会成为**该生态唯一带明确许可的现代实现**。

---

## 8. 参考链接汇总（正文已列，此处为完整 URL）

- injciv6 README：https://github.com/xaxys/injciv6/blob/master/Readme.md
- PeaZomboss 原框架：https://gitcode.net/PeaZomboss/miscellaneous
- yllhwa 博客：https://blog.yllhwa.com/blog/civilization-6-multiplayer/
- chenxi65535 博客园：https://www.cnblogs.com/chenxi65535/p/18515726.html （B站专栏：https://www.bilibili.com/opus/993912143071936516）
- Peaboss 博客园：https://www.cnblogs.com/Peaboss/p/17059052.html
- CSDN 踩坑帖：https://blog.csdn.net/qq_40151332/article/details/128023224
- V2EX 帖：https://www.v2ex.com/t/1213524
- B站专栏（ZeroTier）：https://www.bilibili.com/opus/609896741991801995
- Maple xlog：https://maple.xlog.app/civ6-multiplayer-connect
- Steam 讨论帖（Steam P2P）：https://steamcommunity.com/app/289070/discussions/4/1489992713711433835
- Steam 指南（Linux LAN）：https://steamcommunity.com/sharedfiles/filedetails/?id=3773983709
- Steam 指南（Desync Fix）：https://steamcommunity.com/sharedfiles/filedetails/?id=3772297309
- 创意工坊 MPH：https://steamcommunity.com/sharedfiles/filedetails/?id=2357532056 （v1.8.0: id=3307282026；BBG BBS MPH: id=2887805556）
- 创意工坊 Desync/Lag Free：https://steamcommunity.com/sharedfiles/filedetails/?id=3393196331
- CivFanatics（P2P 无服务器）：https://forums.civfanatics.com/threads/will-multiplayer-be-integrated-this-time.567155/
- pcgamesn（Civ6 多人 mod 支持）：https://www.pcgamesn.com/civilization-vi/civ-6-multiplayer-guide
- Meta 博客（RakNet modified BSD 开源）：https://www.meta.com/blog/announcing-oculus-connect-raknet-open-source-and-e3-2014-awards/
- RakNet Wikipedia：https://en.wikipedia.org/wiki/Raknet

---

*报告完。数据均为 2026-11-18 检索快照；License 以 GitHub API license 字段为准。*
