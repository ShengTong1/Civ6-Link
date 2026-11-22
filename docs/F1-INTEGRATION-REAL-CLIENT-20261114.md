# F1 集成链路：模拟房主经 DLL→Agent 链路被真实文明6 客户端显示（PASS）

- 日期：2026-11-14
- 阶段：REV-016 §3 **F1（DLL + Agent 发现链路）—— 集成链路子项**
- 证据目录：`M0A\captures\F1-integration-20261114-104235`（第一轮 PASS）、
  `M0A\captures\F1-integration-20261114-104534`（第二轮，void）、
  `M0A\captures\F1-integration-20261114-104723`（第三轮，void）、
  `M0A\captures\F1-integration-20261114-105026`（第四轮 PASS）
- 状态：**PASS（两轮 9/9 全绿 + 操作者两轮口述确认房间显示）**；2026-11-14 codex 复核为
  **「限定通过」**（`docs/F1-INTEGRATION-REVIEW-20261114.md`），并批准开始 F2 非发布原型。

---

## 0. 一句话结论

在**单台真实 Civilization VI (DX12) 客户端**（pid 44832）注入 `civlink_hook.dll`、
运行带 `--simulate` 的 `civlink-agent.exe` 后，操作者点击局域网**刷新**：

> **DLL 捕获 Civ6 的发现请求并经本机 CVLH2 通道（127.0.0.1:34718）交给模拟房主 Agent；
> Agent 从本次选定的地址 `26.74.126.98:62900` 向游戏临时端口单播 fixture 公告；
> 真实客户端列表显示 `CivLink-Test-Room-2222`；第一轮 3 个刷新 socket 各 22 页（66 页）、
> 第四轮 7 个刷新 socket 各 22 页（154 页），Hook/Agent/模拟器计数闭合，机器检查 9/9 PASS，
> 操作者两轮口述均确认房间可见。**

这是 F1 集成链路子项的**首个通过**：请求方向走"游戏 sendto → Hook → CVLH2 帧 → Agent
（模拟房主）"的产品形链路（与 F3 Relay 路径同形）；**回复方向是模拟 Agent 直接向游戏
临时端口单播**，不经 Hook 回送，也不是远端 Peer / Relay / 真实房主。

> **表述边界（强制）**：这是**模拟房主 → 真实 Civ6 客户端**的单机证据。
> 不回答真实双机联机（E2-B/E3）、不移动任何 Gate、不是 M0-B 最小可行原型。
> 源地址 `26.74.126.98` 是本次运行配置，不证明 WLAN、Radmin 隧道或任意虚拟 LAN 的远端可达性。
> 详细边界见 §7。

---

## 1. 执行环境

| 项 | 值 |
|---|---|
| 游戏 | `CivilizationVI_DX12.exe`，pid 44832（2026-11-14 10:37:34 启动，重启后新进程）|
| 游戏路径 | `E:\SteamLibrary\steamapps\common\Sid Meier's Civilization VI\Base\Binaries\Win64Steam\CivilizationVI_DX12.exe` |
| Hook | `civlink_hook.dll`（dll base `0x7ff9a3510000`，一次注入，四轮复用同一映射）|
| Agent | `civlink-agent.exe` 0.2.0（`--simulate`，模拟房主）|
| 模拟房主 | 房间名 `CivLink-Test-Room-2222`（fixture 页 offset 24..46 匿名化替换），回复源 `26.74.126.98:62900` |
| fixture | `M0A\captures\E2A-H4-reply-20261113\reply-set`（reply-01..22.bin，22 页 × 1104 B）|
| 驱动 | `run-f1-integration.ps1`（sha256 `BA6A216FA42EFDBBFCC69C7EC092B3AD405DF1DDABE657B1B5A16D3657E047A2`）|
| 运行位置 | 中立目录 `C:\Users\dd\Desktop\civlink-f1\`（项目树 Low IL 陷阱，见 README §3B.5）|

## 2. 第一轮：PASS（9/9）—— `F1-integration-20261114-104235`

- 窗口 150 s；操作者点击 **3 次刷新**（hook sent 在 t=72/76/80 s 处 0→100→200→300）。
- **Hook 侧**：`sent=300`、`fail=0`、`oversize=0`、`ignored=0` 全程。
- **Agent 侧（0.2.0，listen 153.3 s）**：
  - `datagrams=300`，`received frames : 300 (processed 300, rejected 0)`，
    `reconciliation ==`，`large 0`、`notify 0`。
  - 会话 1 个：`frames=300`、`first_seq=1`、`last_seq=300`、`seq gaps=0`、
    `duplicates=0`、`out_of_order=0`、`discovery_magic=300`、`via_wsasendto=0`、
    `limited_bcast=300`、`discovery_flag=300`。
  - **`logical sockets=3`**（每次刷新一个 socket：`0.0.0.0:50433×99`、
    `0.0.0.0:63852×99`、`0.0.0.0:65485×99`，外加每 socket 首帧 `0.0.0.0:0×3`）；
    `dst ports=100`（62900–62999 全覆盖）。
- **模拟房主侧**：`requests seen=300`、`replied sockets=3`、`pages sent=66（==3×22）`、
  `send fail=0`、`no endpoint=3`（每 socket 首帧未绑定）、`max reached=0`、`bind fail=0`；
  回复源 `26.74.126.98:62900`（驱动自动探测的出口接口 IP）。
- **机器断言 9/9 PASS**：`sentDelta 300 == processed 300`、`rejected 0`、`seen 300`、
  `replied 3`、`pages 66`、`sendFail 0`、`bindFail 0`、`max 0`。
- 操作者口述（m14428）：「我已经点击了三次，可以看到房间」。

## 3. 第二轮 / 第三轮：void（0 点击）—— 如实记录

| 轮次 | 证据目录 | 窗口 | 原因 | sent 全程 |
|---|---|---|---|---|
| 2 | `F1-integration-20261114-104534` | 90 s（10:45:36→10:47:06）| 点击指令 10:47:09 发出，晚于窗口 | 300（无增量）|
| 3 | `F1-integration-20261114-104723` | 150 s（10:47:23→10:49:53）| 点击指令 10:49:59 发出，晚于窗口 | 300（无增量）|

两轮 Agent 均收到 0 帧（`datagrams=0`、`rejected 0`），驱动对 3 项计数断言报 FAIL
（`delta=0`/`seen=0`/`replied=0`，其余 6 项因零计数恒真）。

**归因 = 操作者时序（指令送达晚于监听窗口），非产品故障**：Hook 计数保持基线 300
（无任何新 sendto 发生，说明操作者并未在窗口内点击）；第二轮 90 s 窗口对本场景太短，
第三轮 150 s 仍被中间轮次（上下文压缩等）占用了送达时间。教训：窗口必须覆盖
"指令发出 + 操作者响应"的完整延迟，第四轮改用 300 s 窗口即成功。

## 4. 第四轮：PASS（9/9）—— `F1-integration-20261114-105026`

- 窗口 300 s；操作者实际点击 **7 次刷新**（hook sent 300→400→500→600→700→800→900→1000，
  每次 +100；t=174/182/186/190/192/194/216 s）。
- **Hook 侧**：`sent` 终值 1000（增量 700）、`fail=0`、`oversize=0`、`ignored=0` 全程。
- **Agent 侧（0.2.0，listen 305.1 s）**：
  - `datagrams=700`，`received frames : 700 (processed 700, rejected 0)`，
    `reconciliation ==`，`large 0`、`notify 0`。
  - 会话 1 个：`frames=700`、`first_seq=301`、`last_seq=1000`（承接第一轮会话计数，
    同进程内 seq 连续）、`seq gaps=0`、`duplicates=0`、`out_of_order=0`、
    `discovery_magic=700`、`via_wsasendto=0`、`limited_bcast=700`、`discovery_flag=700`。
  - **`logical sockets=7`**（`0.0.0.0:53588×99`、`0.0.0.0:54699×99`、
    `0.0.0.0:54700×99`、`0.0.0.0:54701×99` 等，每 socket 99 条 + 首帧无端点 7 条）；
    `dst ports=100` 全覆盖。
- **模拟房主侧**：`requests seen=700`、`replied sockets=7`、`pages sent=154（==7×22）`、
  `send fail=0`、`no endpoint=7`、`max reached=0`、`bind fail=0`。
- **机器断言 9/9 PASS**。
- 操作者口述（m14466）：「第一轮和第四轮，我实际操作的时候都显示」。

## 5. 对账汇总（两轮 PASS）

| 项 | 第一轮 | 第四轮 |
|---|---|---|
| 刷新次数（操作者） | 3 | 7 |
| hook 捕获 sendto 增量 | 300 | 700 |
| agent 收到帧（processed） | 300 | 700 |
| 对账 | 300 == 300 | 700 == 700 |
| rejected / gaps / dup / reorder | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| 逻辑 socket（=刷新次数） | 3 | 7 |
| sim 回复 socket | 3 | 7 |
| 发送页数（=回复×22） | 66 | 154 |
| send fail / bind fail / max reached | 0 / 0 / 0 | 0 / 0 / 0 |
| 目标端口覆盖 | 100/100 | 100/100 |
| 操作者口述房间可见 | ✅ | ✅ |
| 驱动结论 | PASS（9/9）| PASS（9/9）|

## 6. 与 F1-live（观测子项）的关系

- F1-live（`F1-LIVE-REAL-CLIENT-20261114.md`，复核「观测子项通过」）只证明
  "真实客户端的发现发送经过这些 API 且帧闭合"——Agent 只观测不转发。
- 本轮补齐 REV-016 对 F1 的另一个要求：**模拟房主接入 DLL/Agent 链路并由真实客户端
  显示模拟房间**。两条证据合起来，F1 的两个子项均已有机器 + 操作者证据。
- 仍**不**等于"文明6 发现已被接管"：Hook 至今只做**观测 + 本机 CVLH2 上行**（发现请求
  经 Hook→Agent），回复由 Agent **直接单播**给游戏临时端口，从未改包、从未向远端发送、
  从未跨进程转发。

## 7. 边界（强制）

**允许**：
- "本构建下，模拟房主（房间名 CivLink-Test-Room-2222）经 DLL→Agent 本机链路
  （CVLH2 127.0.0.1:34718）被单台真实 Civ6 客户端收到并显示在房间列表，
  第一轮 3/3、第四轮 7/7 回复，操作者口述确认"。
- "Hook→Agent 计数闭合、无失败/无超限/无缺口/无重复/无乱序"。

**不允许**：
- "文明6 发现已被接管 / 已能联机 / M0-B 可行 / Gate A 通过"；
- "真实双机发现已验证（E2-B/E3 未做）"；
- "模拟房主 = 真实房主"（fixture 是 2026-11-13 单机样本的匿名化重放；回复是 Agent
  从本机地址 `26.74.126.98:62900` 单播给游戏临时端口，不经 Hook 回送，不是远端 Peer/
  Relay/真实房主）；
- "源地址 26.74.126.98 证明 WLAN/Radmin 隧道/虚拟 LAN 远端可达"（只证明本次运行配置）。

第二轮/第三轮 void 必须如实引用（操作者时序，非产品故障），不得合并进"稳定性样本"。

## 8. 文件身份（本报告引用）

| 文件 | sha256 |
|---|---|
| `run-f1-integration.ps1` | `BA6A216FA42EFDBBFCC69C7EC092B3AD405DF1DDABE657B1B5A16D3657E047A2` |
| `civlink-agent.exe`（0.2.0，--simulate）| `3F02E66602582D247CF618ADCF023D4F9F6769A1375113C59F5D08174CD4F27B` |
| `agent/src/main.rs` | `7E3C62D7167782DE415748A6A31FE76F0F7DB2303F86F3A24A600B93CCF59553` |
| 第一轮 summary.txt | 见证据目录 `F1-integration-20261114-104235` |
| 第四轮 summary.txt | 见证据目录 `F1-integration-20261114-105026` |

## 9. 复核裁定与下一步

- **2026-11-14 codex 复核：限定通过**（`docs/F1-INTEGRATION-REVIEW-20261114.md`）——
  REV-016 F1 两个子项（观测、集成）现可记为「限定通过」；**批准开始 F2 非发布原型的设计与实现**，
  继续使用模拟 Peer，不要求第二台 Civ6 电脑；Gate A 未批准、正式 M0-B/Gate B 仍冻结。
- 按 REV-016 进入 **F2（Fake-IP + 62056 游戏数据面）**；F2 设计输入已确认（会话以刷新为单位、
  首帧 `0.0.0.0:0` 不得建映射、`sendto` 结论限本窗口、队列满/Agent 未运行/高负载时序影响须验证）。
- **F2 切换前置**：游戏进程（pid 44832）仍持有 hook 映射（B2 审计运行模式）；
  修改/重链 Hook DLL 前应**正常退出 Civ6 并确认进程结束**，再构建并启动新测试进程。
