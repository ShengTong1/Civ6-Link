# CivLink 开源版重修项目规划（M0D）

> **文档身份**：M0D-OPENSOURCE-PLAN-20261118
> **版本**：v0.1.0（首版，供项目负责人决策）
> **日期**：2026-11-18
> **类型**：规划/决策文档（非验收证据）
> **作者**：技术审查子代理（session-6fe30d79-1c95-4c67-8f32-5859eb18dabd）
> **输入**：5 份技术调研报告（`docs/survey-*20261118.md`）+ M0-C 双角色计划（`docs/M0C-DUAL-ROLE-PLAN-20261118.md`）+ README v1.32 + 工程现状核验
> **输出要求**：本文件为「开源版重修项目规划」，供负责人拍板决策；不改变 F/M 系列证据等级，不构成任何"双人真实联机已验证"的宣称依据。

---

## 0. 摘要（TL;DR）

- **目标**：把 CivLink（文明6 局域网联机助手）产品化并开源，供所有游戏爱好者使用，质量达到"企业级"（稳定、兼容、安全、可维护）。
- **推荐架构**：**方案 D（混合路线）** = 自研应用层"广播→单播改写"（CivLink 现有路线：agent 模拟房主应答 100 发现端口 + C2 定向网卡 + 62056 数据面转发，全部自有代码 MIT）+ **文档引导**用户自装 ZeroTier/EasyTier 作 L2 广播直通可选加速 + **自建 relay 兜底**（civlink-relay 扩展 / 文档引导 coturn/frp）。**v1.0 不内嵌任何第三方组网内核**（驱动签名、License、维护三重负担）。
- **路线本质**：CivLink 走的是中文社区两代验证过的"广播→单播改写"（xchens 2021 抓包重发 → xaxys 2024 injciv6 hook），我们是第三代（hook 观测 + agent 模拟房主应答），且是生态中**唯一带明确开源许可、有 GUI、有完整证据纪律**的实现——这是差异化卖点。
- **里程碑**：P0 基础完善（M-1 双机加入/数据面 + C2 跨机实测 + E2/E3 结案）→ P1 GUI（WPF 托盘）→ P2 跨网通道（62056 转发 + relay + UPnP + 组网引导）→ P3 企业级质量（CI/签名/安装器/日志/崩溃转储/供应链/安全）→ P4 开源发布。
- **License**：主代码 MIT + 文档 CC-BY-4.0 + THIRD-PARTY-NOTICES；GPL 组件（WireGuard/OpenVPN/n2n/WinIPBroadcast）一律**只文档推荐、不内嵌**；ZeroTier 核心 MPL-2.0 可动态链接但 Controller 商业限制明确，v1.0 只文档推荐。
- **必须由负责人拍板的决策**：见 §9（第三方组网是否内嵌 / 是否自建公共 relay / 最小 Civ6 版本范围 / 三人以上是否进 v1.0 / 公共中继带宽与日志承诺等 7 项）。

---

## 1. 背景与目标

项目负责人（用户，m26724 要求原文要点）：「我最后想开源出去，供所有游戏爱好者共同使用，所以请做 GUI 界面，并确保稳定、兼容性、安全性等等符合企业级开发。基于当前现有项目并再次检索各种 GitHub 和中文社区上各种游戏联机 mod、局域网软件、P2P、内网穿透、mesh VPN、NAT 穿透、relay 等等各种技术，是否有更好方案？仅仅供文明6 这一个软件使用就可以。可以给出多种方案，然后由子代理审查对比，重修优化整个项目规划。」

据此本规划回答三件事：

1. **有没有更好的方案**（对比 4 个候选架构，给出推荐）；
2. **怎么重修**（P0→P4 里程碑 + GUI 设计 + 企业级质量清单）；
3. **开源合规与边界**（License 策略、表述纪律、决策点）。

### 1.1 证据纪律（全文通用）

- 本文区分两类结论：
  - **【调研结论】**：第三方证据（社区实测、GitHub 生态、厂商宣传），**含时效标注**；一律不可当作 CivLink 自身验证。
  - **【CivLink 自身结论】**：本项目实测（F/M 系列文档、README 登记链、M0A/captures 证据）；其中又分"机械/模拟证据"与"真实双人验证"，**机械证据 ≠ 双人验证**。
- 任何第三方来源的"成功联机/稳定不掉线"（包括 yllhwa 8 人 4 小时、chenxi65535 代理实测、xchens 抓包重发）都是**社区机械证据或个人经验**，无任何来源提供"两名真实玩家异地全程实测"的正式验证；CivLink 对外文档的"验证"表述必须以**自己真实双人联机测试**（M-1/E2-A/E2-B/E3 + Gate A 复核）为依据。
- 反爬/时效声明：zhihu/CSDN 部分来源仅摘要或关键句（见 survey-zh-community 边界纪律）；游侠收费（2023）、浩方关闭（2026-03-07）等有时间点的事件引用注明时间；厂商宣传数字（KatoLan 40ms/丢包 0%、蒲公英 <30ms、EasyTier NAT4-NAT4）是营销口径，不可作为验收基准。

---

## 2. 输入证据清单

| 输入 | 内容 | 结论性质 |
|---|---|---|
| `docs/survey-civ6-mods-20261118.md` | 文明6 联机 mod 生态（injciv6/civrip/civ6-multiplay/WinIPBroadcast/RakNet） | 调研结论（GitHub API 核实，2026-11-18） |
| `docs/survey-p2p-meshvpn-20261118.md` | P2P/Mesh VPN 13 方案（ZeroTier/Tailscale/n2n/EasyTier/Nebula 等） | 调研结论（数据截至 2026-11-17/18） |
| `docs/survey-nat-relay-20261118.md` | NAT 穿透/Relay（UPnP→打洞→TURN；62056 数据面；RakNet 可靠传输） | 调研结论（2026-11-18） |
| `docs/survey-gui-quality-20261118.md` | GUI/企业级质量（WPF、CI、签名、安装器、SBOM、安全） | 调研结论（2026-11-18） |
| `docs/survey-zh-community-20261118.md` | 中文社区（两代"广播→单播改写"先例；第一痛点；竞品；市场空档） | 调研结论（检索 2026-11-18） |
| `docs/M0C-DUAL-ROLE-PLAN-20261118.md` | C1 已完成 / C2 设计中 / C3、C4 待做 | CivLink 自身（规划+实测） |
| `README.md` v1.32 | F0-F5 全链条、M0-B 双机验证状态、修订记录链 | CivLink 自身（实测登记） |

### 2.1 调研结论核心（含时效）

**文明6 联机机制（多源一致：yllhwa 博客 2023-02、Peaboss 博客园 2023-01、injciv6 README、Steam 指南 id=3773983709、知乎/CSDN 多篇）**

- 房间发现 = 客户端向 `255.255.255.255` 发 UDP 广播，目的端口 **62900→62999 共 100 个**（每端口 1 个 4B 探测包）；服务器通常绑 62900，回**约 1104B JSON 公告页**（多包，本项目实测 22 页）；客户端在自己发包端口监听回复。
- 数据面 = **62056 端口 UDP 单播**（本机先 bind 0.0.0.0:62056 → WSARecvFrom → WSASendTo，非阻塞+轮询）。
- 官方 Internet 模式走 Steam P2P（Steamworks NAT 打洞）；**游戏无"填服务器 IP"入口**，一切修复只能在发现层/数据面做手脚；无官方 Dedicated Server、无 Pitboss、无掉线重连（社区无解，仅 PBEM/PBC）。
- **Windows 只在"首选上网网卡"发全局 IP 广播**（多源 + 本项目 E1 实测佐证：300 包中 299 个经 Radmin 接口）。

**生态与先例（GitHub API / 中文社区，2021-2026）**

- "广播→单播改写"两代先例：**xchens 2021-10-24**（gopacket/pcap 抓包重发，Go 源码，作者明确"UDP 无连接，可手动构造来源端口与目的地址"）；**xaxys/injciv6 2024-03**（hook 形式产品化，207★，**无 License**，停更，已知 3 人以上同时加入兼容问题，Defender 误报远程线程注入）。
- **chenxi65535/civ6-multiplay 2024-10**（MIT，Python UDP 代理：收广播→经 VPN 转发给房主→回包转回，62056 同样代理；需一台常开代理设备与房主同网，**博客园实测成功**）——"数据面 62056 必须一并转发"的直接先例。
- WinIPBroadcast 309★ GPL-3.0（2018，广播跨网卡转发通用工具）；lirunan22/Civ6-Virtual-LAN-Helper MIT 2026-11 活跃；Frwere/civ6-l3-discovery-helper MIT 2026-05（专治 L3 组网刷不出房）。
- **"搜不到房间"是中文社区第一痛点**（知乎 2026-09-04、B站 opus 等）。
- P2P/Mesh（p2p 报告总表）：ZeroTier（核心 MPL-2.0，L2 广播可承载、游戏零改动，但国内对称 NAT 不稳需自建 moon，**Controller 自 v1.16.0（2025-08-21）转 Source-Available 仅非商业**）；Tailscale（BSD-3，L3 无广播、国内无加速节点、Funnel 不支持 UDP）；n2n（GPL-3.0，L2，先 supernode 中转后打洞，-S2 强制中转是中文社区事实标准兜底）；EasyTier（**许可口径两报告冲突**：p2p 报告标 LGPL-3.0、zh 报告标 Apache-2.0，需澄清；L3 TUN，宣传 NAT4-NAT4 直通 + 免费公共中继 + 中文社区活跃）；Nebula（MIT，L3 lighthouse，集成源码最优许可但 PKI 门槛）；Radmin VPN/Hamachi 闭源（Radmin metric=1 抢广播为本项目实测教训）。
- NAT/Relay（nat-relay 报告）：UPnP/PCP/NAT-PMP（零服务器成本第一优先，家用路由器成功率高，CGNAT/校园网无效）→ UDP 打洞（对称 NAT 失败率高，社区 yllhwa 实测"不是非常稳定可靠"）→ TURN 兜底（coturn BSD-3）→ 应用层广播→单播（本项目路线）→ 可选 GameNetworkingSockets（BSD-3，FakeIP 思路参考）。RakNet 自带可靠传输 → **CivLink 只需透明原样转发 UDP，不引入可靠层**。
- 市场空档（zh 报告）：游侠 2023 起收费（仍是质量天花板）、浩方 2026-03-07 关闭；免费主力 Radmin LAN/KatoLan/EasyN2N 闭源或半开源；**"开源 + 免费 + GUI + 文明6 专用 + 明确许可"无强竞争者**。

### 2.2 CivLink 自身结论核心（工程现状，2026-11-17/18）

**已完成并审计闭环**

- F0-F5 机械/模拟测试闭环：F5 = agent `--sim-lan-listen` 绑 62900..62999 模拟房主，**真实双机核验 PASS**（2026-11-16 真实物理机 WLAN 路径：B 侧 `F5-B-PROBE: PASS (4 checks)`，22/22 页逐字节一致，B 机真实 Civ6 大厅显示 `CivLink-Test-Room-2222`，用户口述确认 D 级）——这是**模拟房主→真实客户端跨机发现链路**，**不是双人真实对局**。
- M0-B 双机验证（2026-11-17，审计"有条件通过"）：发现链路段**通过**（B 见真实房名，agent requests seen=1179 / replied sockets=12 / pages sent=264 / replies fixture=12 / captured=0）；**加入/数据面段未验证（M-1，PC-B 离线前未加入）**。
- C1（`agent --reserve-62900` 让出 62900 避免阻塞建房）已审计修正，两组自检 PASS 12/12（证据 `M0A\captures\C1-reserve-selftest-20261118-0111`、`C1-f5-regression-20261118-0115`）。
- 关键实测输入（README 登记链）：发现 socket 序列全程无 bind、每次刷新全新 socket（会话表以刷新为单位）、首帧 src=0.0.0.0:0 属预期、数据面出向 8B 小载荷 + 指数退避（0.5s×2ⁿ）、62056 忙轮询 ~1.6M 次/秒、回复窗口约 2s、广告页=单播应答到请求者源地址:源端口（非广播，P2 直收对真实房主无效，P1 hook socket-身份捕获有效）。

**组件清单（已核验工作区）**

| 组件 | 说明 | 状态 |
|---|---|---|
| `civlink\agent`（Rust，main.rs 124,937B） | 127.0.0.1:34718 IPC；`--sim-lan-listen` / `--sim-real-capture` / `--reserve-62900` / `--simulate` | v0.4.6，已审计 |
| `civlink\hook\hook.cpp`（civlink_hook.dll） | C++/MinHook v1.3.4，6 detour 全透传 + ForwardFrame→agent（CVLH2 帧） | v0.2.0-f2+，已审计 |
| `civlink\ctl`（civlink_ctl.exe） | inject / status / counters / shutdown | 已审计 |
| `civlink\ctl\civlink_ctl_gui.cs`（WinForms 雏形，6,450B） | 封装 ctl 四命令 + 进程探测 | v0.1.0-gui |
| `civlink\client\civlink_client.cpp`（19,895B，**2026-11-18 01:32 存在**） | C2 定向网卡 DLL（IP_UNICAST_IF=31 + `--iface` 三态 + 方案 C 兜底）；导出契约 `common\civlink_client.h` v0.1.0-c2（initError 11/12，fail-open 降级 ALL） | **实施中**（文件已生成，跨机实测与审计未完成） |
| `civlink\fakeip`（civlink-fakeip crate v0.1.0） | FakeEndpoint 双向映射（127.0.127.1..100 纯内存） | 单测+变异全 PASS |
| `civlink\relay`（civlink-relay.exe v0.1.0） | 20B CVLR 信封 + fnv1a64 三方对账 + fail-closed | F3 五子项审计闭环（loopback 原型） |
| `civtrace\`（civtrace.dll + civinject.exe） | 观测面 31 Hook，仅供审计，**禁止随正式版分发** | v0.4.5，日志限流闭环 |
| `deps\MinHook` | v1.3.4 完整源码（含 HDE32/64），BSD-2 | 已核实 LICENSE |
| `dist\civlink-beta-20261114\` | F4 发布候选（标"模拟对端/发现助手测试版"） | NOT 双人验证 |

**硬约束（不可变）**

- `/MT` 静态 CRT；MinHook pin v1.3.4；Agent **永不 bind 0.0.0.0:62056**、永不 SO_REUSEADDR（D4/F3 护栏）。
- 机械/模拟证据不得宣传为双人验证；civtrace 审计工具不随正式版分发；Low IL 陷阱（从中立目录运行）。
- C2 是进程级定向，不动系统 InterfaceMetric；不勾 E2-A/E2-B/E3；不证明跨网/Relay/加密。

---

## 3. 多方案对比结论

针对"文明6 跨网联机"，给出 4 个候选产品架构。打分维度：**License 兼容 / 稳定性 / 维护成本 / 用户安装复杂度 / 国内可用性**（每维 1-5 分，5 最优）。打分是规划级判断，依据见 §2.1/§2.2。

### 3.1 方案定义

| 方案 | 定义 | 典型代表 |
|---|---|---|
| **A. 纯自研全栈** | hook + agent + relay + 自研打洞/信令，不依赖任何第三方组网 | 现状的激进版（自研 UDP 打洞 + TURN 式 relay） |
| **B. 核心 + 内嵌成熟组网** | CivLink 核心（hook/agent/GUI）+ 内嵌 EasyTier/Nebula 等组网内核 | 集成第三方 TUN/虚拟网卡 |
| **C. 广播→单播改写纯应用层** | 零虚拟网卡，应用层把广播改单播（injciv6 路线 / CivLink 现状） | injciv6、civ6-multiplay、CivLink agent |
| **D. 混合** | C（自研应用层）+ **文档引导**第三方 L2 组网（ZeroTier 等）可选加速 + 自建 relay 兜底 | 推荐方案 |

### 3.2 打分表

| 维度 | A 纯自研全栈 | B 内嵌组网 | C 纯应用层 | D 混合 |
|---|---|---|---|---|
| License 兼容 | 5（全自有代码 MIT） | 2（EasyTier 许可口径冲突未清；ZeroTier Controller 非商业；驱动内嵌传染面） | 5（零第三方） | 4（自研全 MIT，第三方只文档引导） |
| 稳定性 | 3（自研 P2P/打洞未经验证，社区共识"自研投入远超成熟方案"） | 4（成熟组网引擎稳定，但驱动/版本/系统兼容面大） | 3（双端都装工具；62056 数据面需自补转发） | 4（多路径分级：L2 直通→应用层→relay 兜底） |
| 维护成本 | 2（要维护打洞/信令/中继全栈） | 2（跟随第三方引擎升级 + 驱动签名 + 平台适配） | 4（代码面小，协议固定（100 端口/62056）） | 4（自研面=C 的代码；第三方只写文档与引导脚本） |
| 用户安装复杂度 | 3（需装工具+可能需公网服务器） | 3（需装虚拟网卡驱动/管理员权限/自建节点） | 4（注入即用，无驱动无管理员，但需对端也装） | 4（默认注入即用；ZeroTier 可选用） |
| 国内可用性 | 3（自建 relay 可控但打洞受对称 NAT 限制） | 2（ZeroTier 官方 moon 在国外；Tailscale 无国内节点；EasyTier 有国内社区但需实测） | 4（无国外依赖，纯单播；对称 NAT 走 relay） | 4（国内 relay 可自建/公共；ZeroTier 可选不依赖） |
| **加权合计（等权 25 分制）** | **16** | **13** | **20** | **20** |

### 3.3 逐项评述与排序

**排序：🥇 D（混合）≈ C（纯应用层）→ 🥈 A（纯自研）→ 🥉 B（内嵌组网）。**

- **C 是 D 的基石**：CivLink 现状就是 C 家族（agent 绑 100 端口应答 = 应用层广播→单播转换形态；社区两代先例验证过方向）。C 的 License 最干净、安装最简（无虚拟网卡/无管理员）、国内无国外依赖。短板：需对端同装工具，62056 数据面跨网必须自补转发通道（civ6-multiplay 先例证明可行）。
- **D 在 C 之上加两层**：①文档引导用户自装 ZeroTier/EasyTier 走 L2 广播直通（游戏原生发现、零改动），解决"不装工具的对端"场景与"更接近真实局域网"的体验；②自建/自托管 relay（civlink-relay 扩展或文档引导 coturn/frp）兜底对称 NAT。**分层路径 = UPnP 自动映射（零服务器成本）→ L2 组网直通（可选）→ 应用层单播直连 → UDP 打洞（远期）→ relay 兜底**，对标业界 ICE 分级（RFC 8445）与 N2N"先中转后打洞"。
- **A 不建议**：自研 UDP 打洞/信令的投入远超成熟方案（p2p 报告结论），且国内对称 NAT 打洞成功率不稳定（yllhwa 实测）。A 只保留其中"relay/信令"一小块（见 D），P2P 打洞留给成熟工具或远期。
- **B 不建议在 v1.0 内嵌**：三重负担——①License（EasyTier 许可两报告口径冲突 LGPL-3.0/Apache-2.0 需先澄清；ZeroTier Controller Source-Available 非商业；n2n/OpenVPN/WireGuard GPL 直接排除内嵌）；②驱动签名与系统兼容（TUN/虚拟网卡驱动需签名认证，企业级门槛）；③维护（跟随第三方引擎升级 + Defender 误报面扩大）。**集成选项（Nebula MIT 若并入源码许可最优）留作远期实验分支**，需负责人决策（§9 决策点 1）。

### 3.4 推荐方案（D）的组件职责

| 组件 | 职责 | 来源 |
|---|---|---|
| civlink_hook.dll | 游戏进程内观测/透传（发现帧 + 62056 观测），socket-身份判定 | 自有 MIT |
| civlink_client.dll（C2） | B 机进程级定向网卡（`--iface <IP>/ALL`），IP_UNICAST_IF，方案 C 兜底 | 自有 MIT，实施中 |
| agent | 模拟房主应答 100 发现端口（`--reserve-62900`）、真实广告页捕获（`--sim-real-capture`）、62056 数据面转发（P2 里程碑扩展） | 自有 MIT |
| civlink-relay（扩展） | 跨网数据面兜底：发现应答 + 62056 双向转发；房间码机制；无状态转发、可靠性与打洞逻辑放客户端（抄 SDR 作业） | 自有 MIT（F3 原型扩展） |
| GUI（WPF） | 托盘 + 注入向导 + 状态/计数/设置/诊断 | 自有 MIT |
| ZeroTier/EasyTier（可选） | 用户自装的 L2 广播直通加速通道 | **文档引导，不内嵌不依赖** |
| coturn/frp（可选） | 用户自部署 TURN/中继（docker-compose 一键） | **文档引导**（BSD-3/Apache-2.0） |

---

## 4. 开源版里程碑规划（P0 → P4）

> 阶段边界以验收标准为准；每个工作项完成后沿现有"文档 + 审计子代理 + 登记链"机制闭环（C3 文档登记、子代理审计、复审）。

### P0 基础完善（从当前状态 → 可稳定双机）

**目标**：把"模拟房主链路"升级为"真实双人可用"，收掉 M0-C 剩余项。

| 工作项 | 依赖 | 验收标准 |
|---|---|---|
| M-1：加入/数据面段双机验证（PC-B 恢复后第一优先级） | PC-B 在线 | B 机加入 A 机真实房间，62056 数据面双向可达，进对局 2-3 分钟包速率/方向记录（E3 要素） |
| C2 收尾：civlink_client.dll 跨机实测（`--iface` 三态） | PC-B 在线；C2 代码已完成（文件已生成） | 按 C2 设计 §3.3 三步法：定向网卡出接口被 pin（IP_UNICAST_IF 实测）、ALL 纯透传、方案 C 兜底按需启用；审计闭环 |
| C3 文档登记 | C2 实测 | README v1.33+ 状态行/修订块；CODEX-HANDOVER 第 20 项；M0-C 审计任务书+子代理审计+复审 |
| C4 结案：E2-A 补正 / E2-B / E3 + Gate A 复核 | PC-B 在线 | E2-A 双机补正（H4 样本复核）、E2-B 双端注入 10 次刷新 T_window/T_response 分布、E3 双人 Steam 局 H3/H8/H10 审计；Gate A 逐项复核 |
| 真实双人稳定性基线 | 上述完成 | 双人同 WLAN 对局 30 分钟以上无掉线（用户操作 + 日志证据），首次形成"真实双人验证"表述资格 |

### P1 GUI（WPF 主界面）

**目标**：图形化全流程，替代手工 ctl 命令，产品形态成立。详见 §5。

| 工作项 | 依赖 | 验收标准 |
|---|---|---|
| WPF 工程搭建（civlink\gui\） | P0 稳定双机 | 托盘程序 + agent 子进程模型；asInvoker 无管理员运行 |
| 注入向导（角色 A 房主 / B 客户端） | 复用 ctl 逻辑 | 一键注入 civlink_hook.dll / civlink_client.dll，`--iface` 选择、`--reserve-62900` 开关；防重复注入提示 |
| 状态/计数页（agent summary 实时） | agent 0.4.6+ | requests seen / replied sockets / pages sent / 62056 计数实时展示；进程健康（PID/Responding） |
| 设置页 + 诊断页 | P2 部分能力（NAT 检测）可后补 | 日志目录、listen-seconds、fixture 路径、开机自启、更新检查；诊断 = NAT 类型检测 + 对端 PING + 日志导出打包 |
| GUI 自动化测试 | GUI 稳定 | UI 自动化（WinAppDriver/ FlaUI）冒烟脚本入 CI |

### P2 跨网通道（跨 NAT 联机）

**目标**：不同局域网/不同 NAT 下双人可联机，这是开源版的核心卖点。

| 工作项 | 依赖 | 验收标准 |
|---|---|---|
| 62056 数据面双向转发（agent 扩展，对标 civ6-multiplay 双端口代理；或 civlink-client 注入态转发） | P0 双机数据面基线 | 跨网真实双机经转发完成发现+加入+进对局（**双人实测**，非机械证据） |
| civlink-relay 扩展：协调/信令 + 房间码 + 62056 转发 + 无状态 | F3 原型 | 对称 NAT（含 NAT4/移动网）双人经 relay 联机实测通过；首包 0.5s 窗口响应（S5 退避输入） |
| UPnP/PCP/NAT-PMP 自动端口映射（第一优先，零服务器成本；miniupnpc 思路参考 RakNet） | 独立 | 家用路由器场景免 relay 直连成功率实测（机械证据：映射建立 + 公网端口可达） |
| 文档引导：ZeroTier/EasyTier 安装与 metric 教程 + "广播→单播改写"原理说明 | 文档 | 用户按文档 15 分钟内完成 L2 组网并看到房间（社区先例路径，非本项目验收） |
| 国内 relay 节点选型（若决策自建公共 relay，见 §9 决策点 2） | 负责人决策 | 节点带宽/分布承诺明确；SLA 与日志策略成文。**§9.1 更新**：决策点 2 挂起、v1.0 按纯用户自建起步，官方公共节点本版不部署；本行降级为"用户自建指引"，无带宽/SLA 承诺 |

### P3 企业级质量

**目标**：可开源发布的质量底线。详见 §6 逐项清单。

| 工作项 | 依赖 | 验收标准 |
|---|---|---|
| CI 全链条（GitHub Actions windows-latest） | 仓库就绪 | cargo test + clippy -D warnings + cargo-deny + cargo audit + GoogleTest/CTest + cppcheck + MSVC /W4 /analyze 全绿门禁 |
| 结构化日志 + 崩溃转储 | agent/GUI | agent tracing + GUI Serilog（JSON、轮转、脱敏）；WER LocalDumps + 自捕 minidump 可回收 |
| 代码签名 + 更新签名校验 | 证书 | 所有发布二进制 Authenticode 签名；Velopack 更新包签名校验 |
| 安装器 + 自动更新 | 签名 | Inno Setup → WiX MSI；防火墙规则安装期一次写入（产品前缀命名，卸载删除）；Velopack 后台更新 |
| 供应链门禁 | CI | Cargo.lock 提交；cargo-deny/audit；SBOM（syft）+ sha256sums + THIRD-PARTY-NOTICES |
| 安全硬化 | 全部组件 | 注入白名单（进程名+全路径+可选签名校验）、无通用"注入任意 PID"接口、IPC DACL 仅当前用户、配置 DPAPI、无硬编码密钥 |

### P4 开源发布

| 工作项 | 依赖 | 验收标准 |
|---|---|---|
| License 定稿（MIT + CC-BY-4.0 + NOTICES） | P3 | 仓库根 LICENSE、THIRD-PARTY-NOTICES、CONTRIBUTING |
| 仓库整理：产品代码与审计痕迹分离 | 全部 | civtrace/M0A 审计证据归档至独立目录或独立仓库（禁止随正式版分发）；README 开源版重写（含验证表述纪律章节） |
| v1.0 Release | P0-P3 | 源码 + 签名二进制 + SBOM + 校验和 + **双人真实验收报告**（跨网 relay 场景） |
| 社区运营准备 | 发布 | 中文话术直击"搜不到房间"；QQ 群/B站/知乎 物料；贡献指南 |

---

## 5. GUI 设计（基于 survey-gui-quality 的 WPF 结论）

### 5.1 结论依据

- **主选 WPF（C#/.NET，MIT）**：目标平台仅 Windows；20 年成熟度；与现有 `civlink_ctl_gui.cs`（WinForms 雏形 6,450B）同语言，控制器调用逻辑 1:1 复用；企业级配套最齐（Serilog/Velopack/WiX/UI 自动化）；License 干净。
- 备选 Avalonia（未来跨平台）、WinUI 3（官方新方向）、Tauri（Rust 单栈但 Web 前端供应链是额外责任面）；排除 Qt（LGPL 双轨合规成本）、Slint（GPLv3 冲突）、Dear ImGui/egui（中文输入短板）。

### 5.2 进程模式

- **托盘主进程（CivLinkTray，asInvoker 普通权限）+ agent 子进程**（GUI 启停 agent，`127.0.0.1:34718` 回环 IPC）。**不需要 Windows 服务**（服务无桌面交互、SCM 权限面大）。
- 托盘图标三态：绿=agent 运行中 / 黄=游戏已注入 / 红=错误（agent 未启动、注入失败）。
- 唯一管理员操作 = 防火墙规则写入，放在**安装器阶段一次完成**；运行时全普通权限。

### 5.3 主界面布局（单窗口多页）

| 页签 | 内容 | 对应现有 ctl 命令 |
|---|---|---|
| **注入** | 角色选择（A 房主=模拟房主应答 / B 客户端=定向网卡）；`--iface` 下拉（本机接口列表 + ALL）；`--reserve-62900` 开关；注入按钮 + 目标进程检测（仅 Civilization VI 白名单）；重复注入/重启提示 | `civlink_ctl inject [--hook|--client] [--iface <IP>]`（C2 新增子命令） |
| **状态** | agent summary 实时：requests seen / replied sockets / pages sent / reply source / captured / replies fixture / 62056 计数；agent 进程 PID/Responding/版本；房间名 | `civlink_ctl status` |
| **计数** | 分层计数器表格（hook.sent / observed / processed / rejected / seq gaps / duplicates / 62056 raw_* / channelDown） | `civlink_ctl counters` |
| **设置** | `--listen-seconds`、fixture 目录（默认 fixture-reply-set）、`--sim-real-capture`、日志目录（%LOCALAPPDATA%\CivLink\logs）、开机自启（HKCU Run 开关）、更新检查（--check-update） | 写 agent 参数 / 读配置 |
| **诊断** | NAT 类型检测（17nas.com 类方法内置）、对端 PING、日志导出打包（含 minidump）、一键生成诊断包；显示"机械证据≠双人验证"提示 | `civlink_ctl status/counters` + 新打包命令 |

- **数据绑定**：v1.0 GUI 直接进程调用 `civlink_ctl.exe`（1:1 复用已验证逻辑，避免重复实现 IPC 协议）；后续再评估 agent 直连（命名管道 DACL 硬化后）。
- 布局参照：KatoLan"无需注册填房间名即加入 12MB"的小白友好与 EasyN2N 内置 NAT 类型检测/PING 的排查门槛——CivLink 对齐"三步即用"（选角色→点注入→开游戏）+ 自带诊断。

---

## 6. 企业级质量清单（逐项落实路径）

依据 survey-gui-quality 的 Top5 + 供应链/安全，落实到本工程：

| # | 项 | 落实路径 | 验收判据 |
|---|---|---|---|
| 1 | **CI** | GitHub Actions `windows-latest`（VS2022 MSVC + rustup）：构建（复用 build-msvc.cmd）→ 测试（cargo test + hook_selftest + run-*.ps1 机械自检）→ 静态分析（clippy -D warnings / cppcheck / MSVC /W4 /analyze）→ cargo-deny + cargo audit → 打包 → 签名（secrets/Azure Trusted Signing）→ 发布 Release + SBOM | 任一环节非绿不发版；CI 产物=发布物 |
| 2 | **结构化日志 + 崩溃转储** | agent 用 tracing（tracing-subscriber + rolling file，JSON）；GUI 用 Serilog（按天/大小轮转多 sink）；**脱敏**（不记录机器名/用户名/路径）；可配 `--log-dir`；崩溃转储 = WER LocalDumps（HKCU，DumpFolder/DumpCount/DumpType=2）+ agent/hook 内 `MiniDumpWriteDump`/`SetUnhandledExceptionFilter` 自捕 | 无 GUI 现场时日志+minidump 可完整还原故障 |
| 3 | **代码签名 + 更新签名校验** | Azure Trusted Signing（CI 自动，开源免费额度）> OV（~100-200 美元/年）> EV；**所有发布二进制全签**（GUI exe / ctl / hook.dll / client.dll / agent / relay / 安装器 / 更新包）；更新下载 Authenticode WinVerifyTrust + HTTPS 拒绝无签名 | 全新 Windows 无 SmartScreen 大警告；更新包验签 |
| 4 | **安装器 + 自动更新** | 短期 Inno Setup（免费，32/64 位）→ 企业化 WiX v4/v5 MSI（组策略静默）；Velopack（vpk + delta 差分包 + 自更新）；安装器 UAC 提权一次写防火墙规则（netsh advfirewall 按程序路径、规则名带产品前缀、卸载删除）+ .NET 运行时前置 + HKCU Run 自启（可关） | 一键安装 / 静默升级 / 卸载干净（防火墙规则清理） |
| 5 | **供应链门禁** | 提交 Cargo.lock；MinHook pin v1.3.4 vendor（已满足）；cargo-deny（banned/advisories/license）+ cargo audit（RustSec）入 CI 门禁；C++ 侧避免新增第三方依赖或全部 vendor+记录版本；发布物附 SBOM（syft）+ sha256sums + THIRD-PARTY-NOTICES | CI 卡不兼容许可与高危 CVE；发布包校验和可复现 |
| 6 | **注入安全** | 注入器仅白名单进程（进程名 + 全路径匹配，默认仅 Civilization VI 相关）；**绝不提供"注入任意 PID"通用接口**；目标签名校验可选开关（WinVerifyTrust）；hook DLL 功能克制（只做白名单函数 patch/协议转发，patch 前校验原字节模式防版本不符崩溃）；不实现键盘钩子/截图/敏感文件读写 | 恶意 fork 无法复用为通用注入器；版本不符不崩溃 |
| 7 | **IPC 硬化** | agent 与 GUI 命名管道/事件 DACL 仅限当前用户；agent 本地监听 127.0.0.1（现状即满足）；网络/游戏输入按不可信处理（协议解析全部校验） | 无跨用户/跨进程权限泄漏 |
| 8 | **密钥管理** | 签名私钥永不进仓库与 CI 明文（GitHub Actions secrets + Azure Trusted Signing）；本地敏感配置 DPAPI（CryptProtectData）；无硬编码密钥 | 泄露面收敛到证书机构 |
| 9 | **测试体系** | C++ GoogleTest + CTest；Rust cargo test（fixture-reply-set 复用）；机械自检脚本（run-*.ps1）全量进 CI；GUI UI 自动化冒烟；**真实双人验证只作为发布前人工验收项**（不可自动化替代） | 回归全覆盖 + 双人人工验收 |

---

## 7. License 策略与第三方组件清单

### 7.1 总策略

- **主代码 MIT**（agent / hook / client / ctl / GUI / relay / fakeip 全部自研）；**文档 CC-BY-4.0**；仓库根 LICENSE + THIRD-PARTY-NOTICES + CONTRIBUTING。
- 理由（survey-gui-quality）：MIT 最宽松，游戏爱好者社区人人能用，不劝退贡献者与公司用户；Apache-2.0 次选（专利授权）暂不采用，保持单一许可简单性。
- **GPL 组件边界（明确）**：WireGuard（内核 GPLv2 / 用户态混合）、OpenVPN GPL-2.0、n2n GPL-3.0、WinIPBroadcast GPL-3.0、EasyN2N GPL-3.0 —— **一律不内嵌、不依赖、不复制代码，仅文档推荐 + 外链**（独立进程分发无碍，集成传染整个作品）。
- **ZeroTier 边界**：核心 MPL-2.0（文件级 copyleft，动态链接兼容），**Controller 自 v1.16.0（2025-08-21）转 Source-Available 仅非商业**（商用自建 Controller 须付费）——v1.0 **不内嵌、只文档推荐**；未来商业化时在 License 策略中单独评估。
- **EasyTier 许可口径冲突（需先澄清）**：p2p 报告标 LGPL-3.0，zh 报告标 Apache-2.0（官方 easytier.cn）。若未来评估内嵌，必须先以官方 LICENSE 为准核实（动态链接 LGPL 兼容、Apache-2.0 更宽松）。
- 两报告口径差异备注：ZeroTier（MPL vs 部分 BSL）、WinIPBroadcast（GPL-3.0 vs MIT）、EasyTier（LGPL vs Apache）——主文档以"官方 LICENSE 核实为准"，调研报告仅作线索。

### 7.2 第三方组件清单（发布物附 THIRD-PARTY-NOTICES）

| 组件 | License | 状态 | 备注 |
|---|---|---|---|
| MinHook v1.3.4（含 HDE32/64） | BSD 2-Clause | ✅ 已直接核实 `deps/MinHook/LICENSE.txt` | pin v1.3.4 vendor 随仓库；HDE 部分 Copyright (c) 2008-2009 Vyacheslav Patkov |
| Rust std + cargo 依赖（serde/clap/tokio 等） | MIT / Apache-2.0 / BSD | 待 cargo-deny + cargo about 自动生成清单 | 逐项审计入 CI |
| .NET / WPF | MIT | ✅ | |
| Serilog | Apache-2.0 | ✅ | |
| Velopack | MIT（核心开源） | ✅ | 安装器+更新 |
| Inno Setup | 免费但非 OSI 开源（专有） | ⚠️ 列入 NOTICE | 仅打包工具不随分发 |
| WiX | MS-RL（宽松） | ✅ | 企业化 MSI |
| GoogleTest | BSD-3 | ✅ | C++ 测试 |
| Sentry SDK（可选错误上报） | MIT | ✅ | **§9.1 更新：决策点 5 裁定"完全不上报"，v1.0 不引入此依赖，本行仅保留为未来可选评估项** |
| coturn / frp / rathole（文档引导，不内嵌） | BSD-3 / Apache-2.0 | ✅ 文档推荐 | docker-compose 一键部署 |
| GameNetworkingSockets / KCP（参考/远期） | BSD-3 / MIT | ✅ 架构参考不内嵌 | FakeIP 思路借鉴 |
| ZeroTier / Tailscale / EasyTier / Nebula / n2n / WinIPBroadcast | 见 §7.1 | ⚠️ 仅文档推荐（或远期集成评估） | 决策点 1 |
| injciv6（机制参考） | **无 License** | ⚠️ 只借鉴机制**不复制代码** | 生态公案来源 |

**合规流程**：CI cargo-deny 卡不兼容许可；Release 附 SBOM（syft）+ 校验和 + THIRD-PARTY-NOTICES。

---

## 8. 风险与边界

### 8.1 表述纪律（对外文档硬性要求）

- **机械证据 ≠ 双人验证**。CivLink 一切对外"验证/联机可用"表述必须以**自己真实双人联机测试**为依据：
  - ✅ 允许："模拟房主→真实客户端跨机发现链路 PASS（F5，22/22 页逐字节一致）"；"发现链路段双机通过（M0-B，B 见真实房名）"。
  - ❌ 禁止："联机已验证"、"双人真实联机已通过"、"跨网联机可用"——除非 M-1/E2-A/E2-B/E3 + Gate A 复核完成并登记。
- 调研结论（§2.1）不得直接用作验收证据；社区机械证据（yllhwa/chenxi65535/xchens）只作"机制可行性论据"，须标注"社区实测，非 CivLink 验证"。

### 8.2 PC-B 恢复后必须执行的验证项（清单）

1. **M-1 加入/数据面段**：B 机加入 A 机真实房间，62056 双向数据面、进对局（E3 要素：包速率/包长/方向分布，H3/H8/H10 审计）。
2. **C2 跨机实测**：`civlink_client.dll` `--iface <IP>/ALL` 三态（IP_UNICAST_IF 出接口效果，C2 设计 §3.3 三步法）；方案 C 兜底按需启用。
3. **E2-A 双机补正**（H4 样本复核）+ **E2-B 双端注入**（10 次刷新 T_window/T_response 分布，analyze-h6-window.ps1）+ **E3 双人 Steam 局**。
4. **Gate A 复核**（PC-B E0 基线回传，哈希核对 REV-012 §1.5）。
5. **P2 跨网验收**：对称 NAT 场景经 relay 双人实测（这是开源版核心卖点，必须真实双机）。
6. **三人及以上加入兼容性实测**（生态公案：3 人以上同时加入是 injciv6 已知 bug；解决即是卖点，属多人版）。

### 8.3 其他风险

- **Defender 误报**：远程线程注入历来触发 Defender/SmartScreen（injciv6 先例）。缓解：代码签名 + 注入白名单 + 发布前实测拦截情况；civtrace 审计工具明确禁止随正式版分发。
- **Low IL 陷阱**：项目目录树带 Low Mandatory Label 会降权（F1 实测教训）——正式版安装到 Program Files/%LOCALAPPDATA% 后不复现，但开发期从中立目录运行。
- **62056 忙轮询性能**：F3-D 前半句（Hook detour 在真实游戏进程内每秒百万次 WSARecvFrom 下不丢帧）**仍未验证**，归 M0-B 前后真机工作。
- **真实广告页捕获的 P1/P2 边界**：P2（绑发现端口直收）对真实房主无效（广告页是单播应答）；P1（hook socket-身份判定）有效但仅覆盖发现窗口期；双机前置须实测 A 机主机广告页发送形态（B1 R-1 已登记）。
- **公共 relay 承诺**（若决策自建）：带宽、节点分布、流量日志策略必须成文（对标 N2N 免费服务器/KatoLan 自建节点；不承诺 SLA 只承诺尽力）。**§9.1 更新**：决策点 2 挂起/6 裁定完全无日志，v1.0 无官方公共节点、无流量日志承诺，本条仅适用于"用户自行搭建 relay"的自愿场景。

### 8.4 与现有 F/M 文档体系的衔接

- M0D 是**规划文档**，不改变 F/M 系列证据等级；P0-P4 各阶段验收沿用现有机制：完成报告 → 更新 README 修订记录链（v1.33+）→ 子代理审计 → 复审 → 登记链登记（CODEX-HANDOVER 更新）。
- C3 文档登记项（README 状态行/修订块、CODEX-HANDOVER 第 20 项、M0-C 审计任务书）在 P0 完成。
- 发布时**审计痕迹与产品代码分离**：M0A/captures、civtrace/civinject、审计报告归档独立目录或独立仓库；产品仓库只保留 F/M 文档中"产品可复现"部分（README 的验证表述纪律章节保留）。
- 证据等级沿用：机械/模拟证据（F0-F5 系列）与真实双人验证（E2/M-1 系列）分层表述，禁止跨层引用。

---

## 9. 决策点（需负责人拍板）

| # | 决策 | 选项 | 本规划倾向 | 影响 |
|---|---|---|---|---|
| 1 | **第三方组网是否内嵌**（EasyTier/Nebula 作为可选组网内核） | ① v1.0 不内嵌只文档引导（推荐）② 远期集成 Nebula（MIT 最优）③ 集成 EasyTier（需先澄清 LGPL/Apache 口径） | ①（v1.0）；② 留作远期分支 | License/驱动签名/维护成本；决定方案 B 是否进入路线图 |
| 2 | **是否自建公共 relay 节点**（官方免费 relay + 协调服务器 vs 纯用户自建 coturn/frp vs 混合） | ① 纯用户自建（零运营成本，起步最简）② 官方公共 relay（对标 N2N 免费服务器，国内可用性好，需带宽承诺）③ 混合（官方信令 + 用户可自建） | ③（先信令托管，relay 自建为主，视用户量再评估公共节点） | 运营成本/国内可用性/公共节点带宽与日志承诺 |
| 3 | **最小支持的 Civ6 版本与平台范围** | ① Steam Win64 首版（现状）② + Win64EOS（Epic）③ + Win7 兼容 | ①（E5 延期结论维持；Epic 验证不属首版 Gate） | 兼容性测试范围；E5 是否回卷 |
| 4 | **三人及以上是否进 v1.0** | ① 首版 2 人（现状 Gate）② 多人版一并做（生态公案，需 H7/E4 三人实测） | ①（E4/H7 延期多人版；H11 三人加入兼容性问题作为卖点储备） | 首版范围/测试复杂度 |
| 5 | **崩溃上报与遥测** | ① 不上报（纯离线，隐私最简）② Sentry opt-in（匿名 ID 脱敏） | ②（opt-in，默认关） | 错误回收效率 vs 隐私承诺 |
| 6 | **公共 relay 的流量日志策略**（若做公共节点） | ① 无日志（隐私最强）② 匿名化统计（保留流量量级） | ②（仅匿名统计，不保留载荷） | 合规/成本 |
| 7 | **ZeroTier Controller 商业限制预案** | ① 仅个人免费使用引导（现状）② 预留商业化评估 | ①（v1.0 纯开源免费不受影响；未来商业化时重新评估） | License 策略长期性 |

### 9.1 负责人裁定记录（2026-11-18，用户 m28114）

> 本节是**历史登记**：记录负责人对上述 7 个决策点的答复。它是规划输入，不是新的执行指令；实施仍按 REV-016 / M0-C / C3 登记链推进。

| # | 负责人裁定 | 与规划倾向的关系 | 落地含义 |
|---|---|---|---|
| 1 | **① v1.0 不内嵌，仅文档引导** | 一致（倾向①） | 方案 B 不进 v1.0 路线图；Nebula 远期分支仅保留评估，不排期 |
| 2 | **挂起**（负责人表示不理解，经解释"公共 relay = 官方免费中继节点 vs 纯用户自建"后，因决策点 1 已选不内嵌，首版按"纯用户自建"起步） | 首版等价于选项①（规划倾向③的低成本起点） | v1.0 不部署官方公共 relay；`civlink\relay\` 保持工具级，用户可自行搭建。带宽/SLA/日志承诺在 v1.0 无需定义 |
| 3 | **① 仅 Steam Win64** | 一致（倾向①） | 不做 Epic/Win7 兼容；E5 延期结论维持 |
| 4 | **方案 A：首版定位 2 人可验证闭环**；多人 capability 待 ≥3 机实测后再评估 | 一致（倾向①） | 负责人经解释"CivLink 只做发现 + 62056 数据面，房间人数由《文明6》本体决定"后确认：首版按 2 人闭环验证，不把多人写进 v1.0 卖点；H11 三人加入问题保留为后续卖点储备 |
| 5 | **① 完全不上报**（比规划倾向②"Sentry opt-in"更保守） | **不同于倾向②** | 无遥测、无 Sentry、无匿名 ID；隐私承诺取最强档，错误回收效率让位于隐私 |
| 6 | **① 完全无日志**（比规划倾向②"匿名统计"更保守；且决策点 2 已按纯用户自建起步，v1.0 无官方公共节点） | **不同于倾向②** | 不保留任何流量统计；公共节点相关的日志策略在 v1.0 不适用 |
| 7 | **① 仅个人免费引导** | 一致（倾向①） | ZeroTier 文档只写个人免费场景；未来商业化时重新评估 Controller 许可 |

**综合影响**：v1.0 收敛为**纯自研发现 + 文档引导第三方组网 + 用户自建 relay 兜底 + 零遥测 + 零日志 + Steam Win64 双人闭环**（即推荐方案 D 的最小实现面）。P2/P3 里程碑中的"公共 relay、匿名统计、Sentry"相关子项相应降级为可选/删除，须在 C3 登记与后续 M0-D 规划修订中同步更正，避免文档仍写"倾向②"造成口径冲突。

---

## 附录 A：关键端口与协议速查（工程事实）

- 发现广播：`255.255.255.255` UDP，目的端口 62900-62999（100 个），4B magic `8d e8 fc 70`（E1 实测）。
- 公告页：约 1104B，magic `59 60 69 9B`，22 页/房，房名在页内偏移 24..45（fixture 与真实页差异即在此）。
- 数据面：UDP 62056；出向首帧 8B（前 6 字节 `17 32 00 00 FF FF` 固定），指数退避 0.5s×2ⁿ（S5 实测）。
- Agent IPC：`127.0.0.1:34718`（CVLH2 42B 头 + 载荷）；Relay 信封：20B CVLR + fnv1a64 三方对账。
- 硬约束：agent 永不 bind 0.0.0.0:62056、永不 SO_REUSEADDR；C1 `--reserve-62900` 让 62900 给游戏建房 socket。

## 附录 B：术语

- **L2/L3**：二层（虚拟以太网，可承载广播）vs 三层（IP 层，无广播）。
- **广播→单播改写**：把发现广播改为向指定 IP 单播（injciv6/xchens 路线）。
- **机械证据**：脚本/抓包/计数器验证；**双人验证**：两名真实玩家异地全程实测（CivLink 唯一可对外宣称的等级）。
- **M-1**：M0-B 审计裁定的必改项（加入/数据面段验证）。
- **Source-Available**：源码可得但限制用途（如非商业）的许可模式（ZeroTier Controller）。
