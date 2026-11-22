# CivLink 联机助手（Civ6-Link）

《文明 6》局域网 / VPN 联机辅助工具，解决「双方在同一 WiFi 或 Radmin 等 VPN 里，却互相找不到房间」的问题。

> 版本：**1.48**（2026-11-23） · 首版范围决议见 `docs/PROJECT-SCOPE-WIN-STEAM-2P.md`。
> 完整修订历史（v1.1 – v1.47）与实验手册已移至 `docs/M0A-MANUAL.md`（章节号不变，历史文档中的「README §X」引用仍可落位）。

## 这是什么

CivLink 通过三件事让局域网联机稳定可复现：

1. **注入**——把钩子 DLL 注入游戏进程，把广播 / 探针的出口网卡钉死在你勾选的网卡上（`IP_UNICAST_IF`），根治「广播被 VPN 网卡抢走、房间时有时无」的问题；
2. **节点发现**——60 秒持续广播；一旦发现对端，几秒内就内联探测全部路径并按丢包率推荐最稳的一条（像 ping 一样快）；
3. **发现补全**（服务端可选）——自动检测游戏建房端口（UDP 62900）并启动转发 agent，让房间在客户端可达的网络路径上可见。

## 功能

| 功能 | 说明 |
|------|------|
| 三 tab 界面 | 注入 / 节点发现 / 关于 |
| 注入 | 服务端 / 客户端角色切换；进程白名单（DX12 / DX11 / DX12E）；网卡勾选（含 VPN，附接口名与 metric）；卸载注入 |
| 节点发现 | 勾选网卡 → 60s 广播 → 发现即探测 → 路径表（丢包率 / p50 / p95 / 抖动）+ 推荐路径 |
| 发现补全 | 勾选即全自动：检测 62900 房间 → 启动 agent → 卸载时一并停止 |
| 关于页 | 版本 / 作者 / 项目地址 + 脱敏诊断导出（status + counters + 日志，一键存盘） |

## 快速开始

**服务端（建房方）**

1. 启动《文明 6》→ 「注入」页选择进程（`CivilizationVI_DX12` / `CivilizationVI` / `CivilizationVI_DX11`）→ 勾选要使用的网卡 → 点「执行注入」；
2. 在游戏内创建房间（监听 UDP 62900）；
3. 需要时勾选「启用发现补全」——检测到房间后自动启动，无需手动操作。

**客户端（加入方）**

1. 启动《文明 6》→ 「注入」页选择进程 → 勾选**到服务端可达的网卡**（同 WiFi 选 WLAN，同 VPN 选对应网卡）→ 点「执行注入」；
2. 游戏内局域网列表刷新即可看到真实房间名。

**停止**

游戏内离开房间 → 「卸载注入」（发现补全会自动一并停止）→ 退出游戏。

## 构建

| 产物 | 命令 | 依赖 |
|------|------|------|
| `civlink_hook.dll` / `civlink_client.dll` / `civlink_ctl.exe` | `build-msvc.cmd` | MSVC x64 工具链（vcvars64），`/MT` 静态 CRT，MinHook v1.3.4（submodule） |
| `civlink-agent.exe` | `cargo build --release --features peer-discover --target-dir target-175`（agent 目录） | Rust 1.75 固定工具链 |
| `civlink-gui.exe` | `cd gui-tauri/src-tauri && cargo build --release` | cargo 1.99，Cargo.lock 保持 **v3** |

## 测试

- `run-c2-iface-selftest.ps1` —— C2 记账层全量：**50/50 runner checks + 74 in-process**（场景 A–J，含换网卡重新激活 J）
- `hook_selftest.exe` —— hook 层透传 / 计数闭合自检
- `civlink-agent.exe --peer-discover-selftest` —— core **36/0**；变异 harness **6/0**
- 完整清单见 `docs/M0A-MANUAL.md` §8–§10

## 仓库结构

| 目录 | 内容 |
|------|------|
| `civlink/agent` | 节点发现 / 发现补全 agent（Rust） |
| `civlink/hook` | `civlink_hook.dll`（观测透传，不改写游戏行为） |
| `civlink/client` | `civlink_client.dll`（客户端出口网卡钉死） |
| `civlink/ctl` | `civlink_ctl.exe`（注入 / 卸载 / 状态 / 计数） |
| `civlink/gui-tauri` | `civlink-gui.exe`（Tauri 桌面界面） |
| `docs/` | 实验手册、交接文档、范围决议、审计报告 |

## 文档索引

| 文档 | 内容 |
|------|------|
| `docs/M0A-MANUAL.md` | 实验手册（原 README 全文：章节 0–10 + v1.1–v1.47 修订记录） |
| `docs/CODEX-HANDOVER-M0A.md` | AI 交接 / 登记链 |
| `docs/HANDOVER-TO-NEXT-AI-20261120.md` | 项目交接文档（2026-11-20） |
| `docs/PROJECT-SCOPE-WIN-STEAM-2P.md` | 首版范围决议（Windows + Steam + 双人） |

## 许可

- 代码：MIT（`LICENSE`，Copyright (c) 2026 shengtong）
- 文档：CC BY 4.0（`docs/LICENSE-DOCS.md`）
- 第三方：MinHook v1.3.4（BSD-2，见 `THIRD-PARTY-NOTICES.md`）
