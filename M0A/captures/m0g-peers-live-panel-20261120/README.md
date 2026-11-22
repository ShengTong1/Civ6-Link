# m0g-peers-live-panel-20261120 — 节点发现页「发现结果」面板设备证据

## 1. 目的

用户要求（m35241）："让它在开始发现的页面中可以直接显示发现的设备端，以及它的基础信息，而不只是通过日志"。

本目录是**面板数据源**的机械证据：agent 在运行期写出 `peers-live.json`（GUI 每 700ms 轮询渲染），
证明面板所需的每一项字段（本机标识、对端标识、对端地址、探测端口、距今时间、路径质量、推荐行）
都由 agent 真实产生，而不是前端伪造。

## 2. 实现摘要

- agent（`civlink\agent\src\peer_discover_net.rs`）：新增 `fn write_live(self_uuid, dir, peers, start, phase, paths)`，
  向 `--peers-dir` 目录整体重写 `peers-live.json`；主循环每 500ms 写一次 `phase="listening"`，
  进入探针阶段前写一次 `phase="probing"`，探针与宽限结束后写一次 `phase="done"`（含 paths）。
- `last_seen_s` 语义 = **距今多久**（`Instant::now().saturating_duration_since(*seen)`），
  不是"第几秒见到的"——后者会随运行时间单调增大而误导用户。
- GUI 后端（`civlink\gui-tauri\src-tauri\src\lib.rs`）：`#[tauri::command] fn peer_live() -> String`
  读取 `LAST_PEER_OUT` 目录下的 `peers-live.json`，无文件返回空串。
- GUI 前端（`src\main.js`）：`refreshPdLive()` 700ms 轮询、`raw === pdLastJson` 时不动 DOM（防抖动）、
  所有对端字符串经 `escapeHtml()` 输出。
- 日志卡保留（用户要求"不只是通过日志"，不是"去掉日志"）。

## 3. 本轮双机实测（A 先起 1 秒，B 后起）

两端均为 `--peer-discover --listen-seconds 40 --discover-port 63010 --probe-port 63011`
+ 单网卡过滤（A `--ifaces 192.168.31.60`，B `--ifaces 192.168.31.214`）。

| 侧 | phase | elapsed_s | 本机 short | 对端 short | 对端地址 | last_seen_s |
|---|---|---|---|---|---|---|
| A | done | 72 | 5479f084 | 5a06fda8 | 192.168.31.214:63344 | 33 |
| B | done | 86 | 5a06fda8 | 5479f084 | 192.168.31.60:63732 / 26.74.126.98:63734 | 48 |

路径质量（面板"路径"表数据源）：

| 侧 | 路径 | sent/recv | p50 | p95 | 抖动 | 丢包 | 评分 | 可推荐 |
|---|---|---|---|---|---|---|---|---|
| A | WLAN 192.168.31.60 → 192.168.31.214:63011 | 100/100 | 12.02ms | 21.18ms | 4.34ms | 0.00% | 0.1690 | 是 |
| B | WLAN 192.168.31.214 → 192.168.31.60:63011 | 100/100 | 5.84ms | 20.25ms | 1.31ms | 0.00% | 0.0795 | 是 |
| B | WLAN 192.168.31.214 → 26.74.126.98:63011（Radmin） | 100/0 | — | — | — | 100.00% | 10.0500 | 否 |

推荐行：A `RECOMMENDED: WLAN(192.168.31.60) -> 192.168.31.214:63011`；
B `RECOMMENDED: WLAN(192.168.31.214) -> 192.168.31.60:63011`。

Radmin 路径 100% 丢包是**预期结果**：两端 Radmin VPN 未加入同一虚拟房间，
不是缺陷（该路径会被判为不可推荐，推荐行正确选 WLAN）。

## 4. 文件清单

- `a\peers-live.json`（437B）— A 侧本轮最终 live 文件（phase=done，含 paths）
- `a\summary.txt`（866B）— A 侧 summary（发现/应答/反射计数 + 路径质量 + 两条警告）
- `a\peers.jsonl`（113B）— A 侧持久对端记录
- `a\out.txt` / `a\err.txt` — A 侧 stdout/stderr
- `B-side-peers-live.json`（639B）— B 侧最终 live 文件
- `B-side-summary.txt`（1,008B）— B 侧 summary
- `B-side-peers.jsonl`（133B）— B 侧持久对端记录（学到 A 双地址）

B 侧文件经 SSH base64 回传落盘（B 机 `D:\Desktop\pd-out-b2\`）。

## 5. 边界（不得外推）

- 本证据只证明**发现面板的数据链路**（agent 写 live → GUI 可读），
  不证明双人对局、不证明 62056 数据面、不证明 E2-B/E3，不勾 Gate A/B。
- 本轮为命令行双机验证；GUI 端"用户点开始发现 → 面板出现设备卡"的目视确认由用户另行验收。
- 面板显示的 `short` 是 uuid 前 8 位十六进制，**不是稳定的设备名**；
  当前发现协议包（24B）不含名称字段，如需显示机器名必须扩协议，本轮未做。
- Radmin 路径 100% 丢包不代表 Radmin 不可用，只代表本轮两端未在同一 Radmin 房间。

## 6. 产物身份

- agent `civlink-agent.exe`：614,912 B /
  `C51C4FA3EA201B2A5A811B584A03A148C613B9506FC76EB968B622A0AA43FE62`
- GUI `civlink-gui.exe`：11,395,072 B /
  `907CF7523D8B73D3892F71ED28BAD96325E6614F79F881128E60DA7A6740F129`
