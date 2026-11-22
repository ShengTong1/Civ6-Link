 M0-G GUI「节点发现」页 — UI 修订与缺陷修复记录（2026-11-20）

## 1. 用户裁定第一轮（m34135，逐条）
1. 「注入向导」改名「注入」，去掉右侧滑动条。
2. 「目标进程」改名「进程」，并与「角色」互换位置。
3. 删除「回真实房间」勾选 —— 真实房间应答是核心能力，不做开关。
4. 日志去掉双层文本框，只留一层，并给日志单独加滚动。
5. 「助手发现」改名（首轮定名「伙伴发现」）。
6. 删除全部黄色底警告块（太占地方）。
7. 「参与发现的网卡」命名调整。
8. 网卡列表改为可折叠、默认不勾选，每项显示「网卡名称 + IP」。
9. 下方日志同样单层 + 独立滚动。

## 2. 用户裁定第二轮（m34203，逐条）
1. 注入页日志累积后整页出现右侧滚动条 → 改为只有日志栏内部滚动；节点发现页同样。
2. 上方「连接设置」压缩，让下方日志更大。
3. 「伙伴发现」名字仍不好，要更专业。
4. 「选择网卡」按钮点击无效，且不点也罗列全部网卡。
5. 网卡列表要实时刷新当前机器网卡状态（手动刷新键 + 自动刷新，两者结合）。
6. 每块网卡后方显示当前优先级，默认由高到低排序。

## 3. 实现

### 3.1 页面与命名（第一、二轮）
- tab 六页：`注入` / `节点发现` / `状态` / `计数` / `设置` / `诊断`。
  第二轮把「伙伴发现」定名为**「节点发现」**——工具发现的是对端**进程/节点**，
  既不是游戏房间，也不是"伙伴"这种口语称呼。
- 注入页改为行式布局：进程 + 刷新 / 角色 / 发送网卡 / 监听网卡 / 执行注入 + 卸载注入。
- 删除 `#realroom` 复选框：真实房间应答（`--discovery-completion`）是核心能力，不做开关。

### 3.2 布局契约（窗口永不滚动）
- `html,body{height:100%}`、`body{display:flex;flex-direction:column;overflow:hidden}`。
- `main{flex:1 1 auto;min-height:0}`；`.card{flex:0 0 auto}`（设置区按内容收缩）。
- `.logcard{flex:1 1 auto;min-height:0;display:flex;overflow:hidden}`
  + `.logcard > pre{flex:1 1 auto;height:100%;overflow-y:auto}` —— 日志吃满剩余高度、**只在栏内滚动**。
- `.hidden{display:none !important}`。此前 `.hidden` 在前、`.pd-ifaces{display:flex}` 在后，
  层叠覆盖导致折叠容器恒可见（用户 m34203 第 4 条的直因），加 `!important` 修复。
- `main.js` 的 `log()` 追加后 `p.scrollTop = p.scrollHeight`，日志自动滚到底。

### 3.3 网卡列表（第二轮第 5、6 条）
- 后端 `list_ifaces_named() -> Vec<IfaceNamed{ip,name,metric}>`：
  `Get-NetIPInterface -AddressFamily IPv4` 建 index→metric 映射，`Get-NetIPAddress` 取地址，
  拼 `ip|name|metric` 返回；Rust 侧 `out.sort_by_key(|i| i.metric)` —— **metric 越小优先级越高，排在前面**。
- 前端 `refreshPdIfaces(verbose)`：渲染 `复选框 + 网卡名 + IP + 优先级 N` 药丸；
  `pdChecked` 为 Set，跨刷新保留用户勾选；消失的 IP 自动剔除。
- 刷新入口三条：`#pd-refresh` 手动刷新（写日志时间戳）、`#pd-autorefresh` 自动刷新（5s 定时，
  **仅当「节点发现」页处于激活状态时**才真正请求）、点开折叠面板时刷新一次、切 tab 到节点发现时刷新一次。
- 列表默认折叠且**默认全不勾选**（用户 m34135 第 8 条）。

### 3.4 勾选必须真正生效（缺陷修复）
- 修复前：GUI 只把勾选的 IP 用来判断是否加 `--include-vpn`，**从不传给 agent**；
  agent 仍按自己枚举的全部网卡广播 —— 与"勾选才参与"的承诺不符，双警告（隐私）也名不副实。
- 修复：`main.rs` 新增 `--ifaces <逗号分隔 IPv4>`；`peer_discover_net.rs` 的
  `enumerate(include_vpn, ifaces_filter)` 先构造允许列表，循环内不命中即 `continue`；
  空值或 `ALL` 视为不过滤。GUI 传 `["--ifaces", ips.join(",")]`。
- 实测语义：`--ifaces 26.74.126.98` → 仅 Radmin；`--ifaces 192.168.31.60` → 仅 WLAN；
  `--ifaces ALL` → 四块网卡全参与；`--include-vpn` + `--ifaces <WLAN>` 仍只出 WLAN（过滤优先于 include-vpn）。

## 4. ★两处 cross-machine 缺陷（本轮实测暴露并已修）

### 4.1 探针阶段无人应答 → 永远 `RECOMMENDED: none`
反射原本只在主循环内做，而 `probe_paths` 在**主循环退出后**才运行。
两机监听窗相同 → 几乎同时进入探针阶段 → 双方反射器都已停 → 各自测到静默对端 → 全路径 100% 丢包。
修复：`probe_paths` 增加 `reflector: Option<&UdpSocket>` 参数，在自身探测的等待间隙调用
`reflect_pending(...)` 应答对方请求；两侧同时启动实测双向 PASS（A `recv=98 loss=2%`、B `recv=100 loss=0%`，
各自给出 `RECOMMENDED: WLAN(...)`）。证据 `M0A\captures\m0g-reflector-fix-20261120\`。

### 4.2 错开启动 → 后启动侧全 100% 丢包
两人不可能同时按「开始发现」。先启动的一侧探针阶段结束后立即退出，
后启动一侧开始探测时对端已不存在。
修复：新增 `PEER_GRACE_MS = 30_000` 与 `grace_answer(sock, abort, budget_ms, start)`，
在自身探针阶段结束后继续应答 30 秒，墙钟受限且可被 abort 中断；
`reflect_pending` 改为返回应答计数并累加进 `stats.probe_reflected`。
错开 2 秒实测：A `p50=11.0ms loss=0.00%`、B `p50=4.1ms loss=0.00%`，两侧均 `RECOMMENDED: WLAN`。
证据 `M0A\captures\m0g-grace-20261120\`（含 README、双侧 summary、peers.jsonl）。

### 4.3 监听窗与宽限窗的协调
GUI 原传 `--listen-seconds 120`，加 30 秒宽限后全程可达 150 秒以上，用户会以为卡死。
现改为 `--listen-seconds 60`，界面提示"监听 60s + 30s 应答宽限（约 95 秒全程，请勿关闭窗口）"。

## 5. ★M5 双警告的处置（审计项不得丢失）
此前 GUI 以黄色卡片常驻展示两条警告（无鉴权 / VPN 即二层广播域），是 M5 可验收项。
用户要求删除黄色块后，警告改为**点击「开始发现」时逐行写入日志区**（`main.js` `PD_WARNINGS` 常量 → `log("pd-log", ...)`），
即：**警告仍在 GUI 内逐字可见，只是不再常驻占版面**。README v1.41 修订块的逐字双警告不受影响。
若后续审计要求"打开页面即见"，应回到常驻形态而非删除。

## 6. ★发现结果面板（m35241：设备端直接显示在页面，不只看日志）

### 6.1 需求与设计取舍
用户 m35241 逐字：「请你修改源码，让它在开始发现的页面中可以直接显示发现的设备端，以及它的基础信息，而不只是通过日志」。
面板数据**不复用日志文本**，而是由 agent 结构化落盘、GUI 轮询渲染：
- agent 每 500ms 整体重写 `<--peers-dir>/peers-live.json`（小文件整体重写，避免 GUI 读到半截 JSON）；
- GUI 每 700ms `invoke("peer_live")` 取该文件，`raw === pdLastJson` 时**不动 DOM**（防抖动）；
- 日志卡保留在最下方（用户要求是"不只是通过日志"，不是"去掉日志"）。

### 6.2 字段契约（peers-live.json）
`self{uuid,short}`（本机节点标识，`short` = uuid 前 8 位十六进制）、
`phase`（`listening`/`probing`/`done`）、`elapsed_s`、
`peers[{uuid,short,addrs[],probe_port,last_seen_s}]`、
`paths[{iface,local_ip,peer,sent,recv,p50_ms,p95_ms,jitter_ms,loss_pct,score,ok}]`。
- **`last_seen_s` 语义 = 距今多久**（`saturating_duration_since`），
  早期实现写成"第几秒见到的"会随运行时间单调增大、误导用户，已修正。
- `short` 便于人读，但**不是稳定设备名**；发现协议包仅 24B、无名称字段，显示机器名需扩协议（本轮未做，登记为后续项）。

### 6.3 面板构成
「发现结果」卡片：`#pd-phase` 阶段药丸 + `#pd-self`「本机 <8hex>」+ `#pd-count`「设备 N · 路径 M」+「清空」；
`#pd-devices` 设备列表（绿点 / 对端设备 short / uuid / 地址 / 距今秒，空态给出「双方都点开始发现」提示）；
`#pd-paths` 路径表（路径 / 收发 / p50 / p95 / 抖动 / 丢包·评分，可推荐绿底、不可推荐红底）；
`#pd-rec` 推荐行。所有对端字符串经 `escapeHtml()` 输出（对端内容来自网络，属不可信输入）。

### 6.4 双机实测（A 先起 1 秒，单网卡过滤，`--listen-seconds 40`）
| 侧 | phase | elapsed_s | 本机 short | 对端 short | 对端地址 | last_seen_s |
|---|---|---|---|---|---|---|
| A | done | 72 | 5479f084 | 5a06fda8 | 192.168.31.214:63344 | 33 |
| B | done | 86 | 5a06fda8 | 5479f084 | 192.168.31.60:63732 / 26.74.126.98:63734 | 48 |

路径：A `WLAN 192.168.31.60 → 192.168.31.214:63011` 100/100、p50 12.02ms、p95 21.18ms、抖动 4.34ms、丢包 0.00%、评分 0.1690、可推荐；
B `WLAN 192.168.31.214 → 192.168.31.60:63011` 100/100、p50 5.84ms、p95 20.25ms、抖动 1.31ms、丢包 0.00%、评分 0.0795、可推荐；
B `→ 26.74.126.98:63011`（Radmin）100/0、丢包 100.00%、评分 10.0500、不可推荐——**两端 Radmin 未同房间，属预期**，推荐行正确选 WLAN。
证据目录 `M0A\captures\m0g-peers-live-panel-20261120\`（README + A 侧 live/summary/peers + B 侧 base64 回传三件）。

## 7. 产物
- `civlink-agent.exe`（`--features peer-discover`）**614,912 B**
  SHA256 `C51C4FA3EA201B2A5A811B584A03A148C613B9506FC76EB968B622A0AA43FE62`
  （A 部署目录 `C:\Users\dd\Desktop\civlink-gui\` 与 B 机 `D:\Desktop\` 同哈希）
- `civlink-gui.exe` **11,395,072 B**
  SHA256 `907CF7523D8B73D3892F71ED28BAD96325E6614F79F881128E60DA7A6740F129`
- 构建：agent `cargo +1.75.0 build --release --offline --features peer-discover` exit 0；
  GUI `cargo build --release`（**必须用 stable**：`cargo +1.75.0` 不认 `gui-tauri\src-tauri\Cargo.lock` v4）exit 0；
  `node --check main.js` exit 0。
- 自检：`civlink\run-peer-discover-selftest.ps1` → `PD-SELFTEST: 6 checks, 0 failed` +
  `PD-SELFTEST: PASS - all mutations caught by core selftest`。

## 8. 边界
本页为 UI 与发现质量探测层改动，不改变 agent 的 62056 数据面约束、不改变注入语义。
节点发现仍是同广播域 P2P 发现工具：**不构成双人对局验证，不勾 E2-A/E2-B/E3，不移动 Gate A**。
30 秒宽限是使用约定而非协议保证：若后启动侧晚于 30 秒才开始探测，仍会测到静默对端。

## 9. 布局契约根因（D-6，2026-11-21 补登记）

「发现结果」卡片 .pd-result{flex:1 1 auto;min-height:120px;overflow:hidden} 内部同时容纳设备列表（#pd-devices）与路径表（#pd-paths）：当两者内容总高超出卡片被分配的高度（flex 空间不足时收缩卡片），超出部分被 overflow:hidden 裁切且**无内部滚动**，用户看不到靠后的设备/路径行。根因：.pd-result 是 flex 子项且 flex:1 1 auto 允许收缩，overflow:hidden 又禁止溢出可见；单对端单路径场景高度足够，未暴露。本轮（v1.45）**未改布局**，登记为已知限制与后续项；如修复：可给设备/路径容器加 overflow-y:auto，或把 .pd-result 改 flex:0 0 auto 并权衡页面整体高度。机械证据≠双人验证，不勾 E2-A/E2-B/E3，不移动 Gate A/B。
