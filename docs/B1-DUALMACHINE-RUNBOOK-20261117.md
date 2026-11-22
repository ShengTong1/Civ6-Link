# B1 双机验证操作单（v4，判定口径修正版）

> 前置：B1 机械证据 PASS 17/17（run-20261117-012424）；B1 审计 f8918c50 有条件通过、
> 必改 R-1/R-2/R-3 已落实、复审 cfc28fc4 通过；**§0 发送形态取证已完成
> （run-20261117-095336）**：广告页为**单播应答到请求者源地址:源端口**（如 54322），非广播。
> **★P1 端到端已验证（run-20261117-102852）**：hook socket-身份判定（civlink_hook.dll
> `0965154A…`）捕获真实房主单播广告页 22 页（captured=22/active=yes，证据
> `M0A\captures\B1-p1-e2e-20261117-102852\`）。**双机验证因此固定走 P1（hook 链）**，
> P2 对真实房主不可用（房主占 0.0.0.0:62900 + 广告页单播到临时端口）。

## 目的

验证 **A 机 Civ6 真实房主 + 注入 hook（socket-身份判定）** 的双机发现链路：B 机大厅
刷新后看到的是 **A 机的真实房间名**（而非 fixture 匿名房名 CivLink-Test-Room-2222）；
同时 agent 经 **P1 hook 链捕获真实广告页**（`captured=22 / active=yes`）作为观测证据。

> **判定口径修正（v4，2026-11-17）**：本方案 agent 以 `--sim-real-capture`（**无
> `--sim-lan-listen`**）运行，agent 不绑定发现端口、不参与应答——`replies real /
> replies fixture / replies skipped` 与 LAN 块 `requests seen / replied sockets` 仅在
> `--sim-lan-listen` 时由 `LanSimState::poll/consider` 递增，无该参数时恒 0；F1 块同名
> `requests seen / replied sockets` 仅对 hook 帧中的 4 字节 discovery magic 递增
> （`SimState::consider`，main.rs:2091-2092），双机场景 A 机 Civ6 只收不发 magic，同样
> 恒 0（run-102852 实测 `discovery_magic=0`）。B 机看到房间靠 **A 机 Civ6
> 房主自身的单播应答**（B 广播 magic → A 房主 socket 0.0.0.0:62900 收 → 房主单播应答
> 22 页到 B 的源地址:源端口，§0 取证形态），agent 纯观测。判定只依据：
> `captured=22 / active=yes`（A 侧捕获证据）+ B 机大厅可见真实房名（用户口述）。

## 拓扑与角色

- A 机（房主）：`CivLink-M0A-audit\civlink\agent\target\release\civlink-agent.exe`
  （含 R-2/R-3 修正，sha256 `DDAF5453…`）以 `--sim-real-capture`（**无 `--sim-lan-listen`**，
  见 §捕获路径）运行；A 机 Civ6 建真实局域网房间；**注入 civlink_hook.dll
  （sha256 `39D6735D…`，socket-身份判定版，审计必改落实后的最新构建）**。
- B 机（客户端）：真实 Civ6 客户端，大厅刷新搜索房间。

## 捕获路径（固定走 P1 Hook 链）

- **P1（唯一真实可用路径）**：A 机 Civ6 注入 `civlink_hook.dll` 后，发现 socket
  （曾 bind 62900..62999）发出的**所有 sendto 无论目标端口**都经 CVLH2 帧到 agent
  （socket-身份判定，hook.cpp `IsDiscoveryTarget(SOCKET s, sin, flagsOut)`）。
- **P2 不可用（run-20261117-100824 实锤）**：① A 机 Civ6 房主占 `0.0.0.0:62900` →
  agent `--sim-lan-listen` 绑 100 发现端口 `bind fail: 1 port`；② 广告页单播到请求者
  临时端口（§0 取证），目标端口非 62900-62999 也非广播。
- agent 以 `--sim-real-capture` 运行即监听 127.0.0.1:34718 收 hook 帧（默认）；
  **不要加 `--sim-lan-listen`**（避免 bind fail 与 P2 误报）。

## 步骤（A 机）

1. 启动 agent（P1 模式，无 --sim-lan-listen）：
   `& "<release agent.exe>" --listen-seconds 600 --out-dir "<outDir>" --simulate "<fixture>" --sim-real-capture --sim-room-name CivLink-Test-Room-2222`
   （600s 窗口足够 A 建房 + B 刷新两轮；agent 仅监听 127.0.0.1:34718 + 127.0.0.1:62900）。
2. 注入 hook：`civlink_ctl.exe inject -x CivilizationVI_DX12.exe -p <pid> -d civlink_hook.dll`（39D6735D）。
   - 注意：**必须先注入、后建房**（发现 socket 的 bind 在建房时发生，hook 需在 bind 前就位
     才能记录 SlotBoundPort）；若游戏已建房，请先建房后退出再重进大厅触发新 bind，或
     在注入后重新建一次房。
3. A 机 Civ6 主菜单 → 多人游戏 → 建局域网房间（真实房名，如 "dingzihan2022的游戏"）。
4. 等待 5-10s，确认 agent 目录出现 `real-page-01..22.bin` 与 summary real-ad 块
   `captured=22 / active=yes`（若 30s 无捕获 → 见故障排查）。
   - 无 B 机刷新时可用 `run-b1-trigger-ad.ps1`（本机模拟客户端 54322 发 100 magic）
     触发房主应答，验证捕获链。

## 步骤（B 机，用户操作）

5. B 机 Civ6 主菜单 → 多人游戏 → 局域网 → 刷新。
6. 记录：列表是否出现 **A 机真实房名**（非 CivLink-Test-Room-2222）；口述给负责人。

## 判定（v4 口径：见「目的」修正说明）

- **PASS**：B 大厅列表显示 A 机真实房间名（非 CivLink-Test-Room-2222），**且** A 机
  summary `captured=22 / active=yes`（真实广告页经 P1 hook 链捕获完整）。不要求
  `replies real>=1`（agent 无 LAN 监听时恒为 0，属预期）。
- **部分**：B 看到房名但 A 侧 `captured<22` 或 `active=no`（真实页捕获不全/未满集）
  → 归因捕获路径（注入时序、建房时机、触发窗口）。
- **FAIL**：B 看不到房间 → 先查 agent 是否在跑、hook 是否注入成功（`civlink_ctl status`
  返回 hooks active）、建房是否在注入之后；再查 A 机防火墙是否放行 **Civ6.exe**（游戏）
  UDP 入站（B→A 的 magic 到达靠游戏自身 socket，非 agent）。

## 故障排查

- A 机 agent 无 real-page：先查 hook 是否注入成功（`civlink_ctl status` 返回 hooks active）、
  建房是否在注入**之后**；再查 agent stderr 是否出现 `[+] B1 real advertisement page N/22 captured`。
- B 机看不到：确认 A/B 同 WLAN 网段（192.168.31.x）；确认 **A 机 Civ6.exe**（游戏进程）
  的入站 UDP 规则放行（B→A 的 magic 广播到达靠游戏 socket，agent 不参与应答，无需放行
  agent.exe）；参考 F5 双机经验（F5 时 agent 是应答方需放行 agent.exe，本 B1 双机场景
  应答方是游戏本身）。若 A 侧 `captured=0`，再查注入/建房时序（见上）。

## 边界（登记口径）

- B1 双机验证 = agent 捕获真实广告页 + 应答可见性；**不证明双人真实对局/62056 数据面**；
  **不勾 E2-A/E2-B/E3；不移动 Gate A/B**（Gate A 未批准，M0-B 冻结）。
- **P1 端到端已验证（run-20261117-102852）**：真实房主单播广告页可经 socket-身份判定
  hook 捕获；**不证明**双机场景下 B 机必能看到房间（尚需本操作单双机验证）。
