# F5 LAN 模拟房主（跨机发现路径）— 2026-11-15

## 1. 目的与背景

用户 m19072 指示：**通过 civlink 程序使 A/B 两机相互搜到房间并正常游戏，
即使不改变 metric 网络优先级**。背景事实：

- PC-A 的 Windows 广播选路曾因 Radmin 接口 metric=1 < WLAN 45 而走 Radmin（b183
  根因，历史结论）；metric 已调至 200 后广播出口为 WLAN（192.168.31.59）。
- 原生 Civ6 双向广播在 A/B 之间**本应可用**（用户证实 A 建房 B 可搜到并加入），
  但 PowerShell 监听器收不到跨机广播（防火墙按程序拦入站 UDP）。
- civlink 的意义 = **不依赖原生广播选路 / 接口 metric / 防火墙手工放行**的确定性
  发现通道：Agent 直接持有全部发现端口（62900..62999），从 `<ip>:62900` 应答
  22 页 fixture。

F5 = REV-016 双机发现路径验证：**LAN 模拟房主（A 机）→ 真实 Civ6 客户端
（B 机）**的跨机广播发现。

## 2. 实现（civlink-agent，--sim-lan-listen）

`civlink\agent\src\main.rs` 新增：

- `--sim-lan-listen IP`：绑定 IP（0.0.0.0 = 所有接口）上的全部发现端口
  62900..62999 各 1 个 UDP socket，直接接收 Civ6 客户端发现广播
  （4 字节 magic 8D-E8-FC-70），从 `<ip>:62900` 应答 22 页 fixture
  （reply-01..22.bin，1104B 各）。
- 按 `(src_ip_be, src_port_be)` 键去重：一次刷新 = 客户端向每端口各发 1 个
  magic 共 100 包、一个临时源端口 → 只应答一次（22 页）。
- 与 F0 responder 同构（F0 已证真实 Civ6 客户端 20/20 收到应答）。
- 与 F1 的 loopback 模拟房主互斥（两者都绑 127.0.0.1:62900，F5 优先）。
- 计数：requests seen / replied sockets / pages sent / send fail /
  no endpoint（源端口 0）/ max reached / bind fail。
- summary 新增 `LAN simulated host (F5)` 小节；notes 明确边界（模拟房主证据，
  非双人真实联机、非 E2-B/E3；Agent 永不 bind :62056、永不 SO_REUSEADDR）。

## 3. 证据（六类：三类机械 + 单机真实客户端 + 跨机 Radmin + 真实双机 WLAN）

### 3.1 回环自检 — PASS 12/12

`civlink\run-f5-lan-selftest.ps1`（脚本 sha256 80C0935DE04A2EA7F8A596B9E9B4B045C2EFFB8C671FDEF610FF9AF279BAB41E）：
- 起 agent `--sim-lan-listen 127.0.0.1`，向 127.0.0.1:62900..62999 发两轮
  Civ6 式 magic 突发（各 100 包、独立源 socket）。
- 断言 12 项：exit 0 / stderr 空 / LAN 段存在 / listen ip / requests seen=200 /
  replied sockets=2 / pages sent=44 / 失败计数全 0 / 每轮客户端收 22 页×1104B /
  head magic 59 60 69 9B / room `CivLink-Test-Room-2222`。
- 证据：`M0A\captures\F5-lan-selftest-20261114-192000`（52 文件）。

### 3.2 真实广播自测 — PASS（22/22 页，客户端侧证据留存）

- agent `--sim-lan-listen 0.0.0.0`，客户端向 `255.255.255.255:62900..62999`
  发 100 个 magic（真实广播，SO_BROADCAST），1MB 接收缓冲。
- 结果（agent 侧）：requests seen=100 / replied sockets=1 / pages sent=22；
  客户端侧独立观察：收到精确 22 页（24,288B == 22×1104），head=59 60 69 9B，
  room 正确。
- 应答源：本机回环自测中客户端观察到的应答源**不稳定**——`-b` 轮为
  `192.168.31.59:62900`（WLAN 回环路径，客户端侧未留存，见 §3.2 证据注），
  `-c` 轮为 `26.74.126.98:62900`
  （Radmin 回环路径，客户端侧证据已留存）。这是本机广播多路径投递的固有现象：agent 绑 0.0.0.0
  会在 WLAN 与 Radmin 两条回环路径上都收到广播，应答源随先到的路径而定；
  agent 自身 summary 记录 `reply source : 0.0.0.0:62900`（绑定地址，非实际
  出口）。**跨机场景（B 机广播经 WLAN 到达 A 机）只有一条路径，应答应经
  WLAN 出口**，故应答源不定性不适用于跨机。
- 证据：`M0A\captures\F5-lan-broadcast-selftest-20261115-b`（agent 侧）与
  `M0A\captures\F5-lan-broadcast-selftest-20261115-c`（**客户端侧**
  `client-observed.txt` SENT=100/PAGES=22/RECV_BYTES=24288/HEAD/ROOM +
  `client-recv-01..22.bin`）。
- 注：首版自测（`-a`，默认 64KB 缓冲）出现 3 socket/66 页 —— 本机广播多路径
  投递（Radmin+WLAN 回环）致 66 页溢出 64KB 缓冲，属自测人工产物；跨机只有
  一个源 IP，不会发生。

### 3.3 B 侧探测机械验证 — PASS（A 机回环模拟）

- `civlink\run-f5-b-probe.ps1`（B 机一键探测）：向 255.255.255.255 发 100 个
  magic（固定本地端口 54321），收 22 页应答；自提权加/删 54321 入站 UDP
  防火墙规则（UAC 一次）；断言 sent=100 / pages=22 / head / room。
- A 机回环端到端实测（agent 侧）：PASS（requests seen=100/replied sockets=1/
  pages sent=22）；客户端侧独立观察与 §3.2 `-c` 轮相同（SENT=100, PAGES=22,
  RECV=24,288B, HEAD=59 60 69 9B, ROOM=CivLink-Test-Room-2222，见
  `client-observed.txt`）。
- 证据：`M0A\captures\F5-bprobe-mechanical-20261115`（agent 侧）；
  客户端侧观察以 §3.2 `-c` 轮的 `client-observed.txt`/`client-recv-01..22.bin`
  为独立证据（probe 逻辑与 -c 客户端代码路径相同：同广播报文、同收页逻辑）。

### 3.4 单机真实客户端验证 — PASS（真实 Civ6 大厅看到模拟房间）

- **方案 C（用户 m19535 选定）**：A 机启动 agent `--sim-lan-listen 0.0.0.0`
  （600s 窗口、fixture-reply-set、房名 CivLink-Test-Room-2222），同一台机器的
  真实 Civ6 大厅点刷新 —— 本机广播由本机 agent 直接持有端口接收并应答，
  无需 B 机。用户两次口述确认看到房间（"刷新了 / 打开了,刷新之后有"）。
- agent 侧 summary（`M0A\captures\F5-singlehost-20261115-1235\summary.txt`，
  sha256 A6892BB026E4A0D124D27616ED81BA4D09CCD080B2B27DE44D0D538B1DACE397）：
  requests seen=**100** / replied sockets=**1** / pages sent=**22**
  （== replied×22）/ send fail=0 / no endpoint=0 / max reached=0 / bind fail=0 /
  exit code=0 / stderr 空 / 干净收尾（STOP 触发）。
  - 轮次限定（审计 F-4）：此处 `exit code=0` 属**单机轮（§3.4）**，有 `exit.txt`
    10B/AF96489E… 实物支撑；与 §3.6 双机轮（手工启动、无 `exit.txt`、不宣称退出码）
    不是同一情形，勿混用。
- lan-page-01..22.bin 除房名偏移 24..45 外与 fixture reply-01..22.bin
  逐字节一致（MISMATCH=0）；agent-console 3,070B/C2E6EC3E…、agent-stderr 0B、
  exit.txt 10B/AF96489E…。
- 证据目录：`M0A\captures\F5-singlehost-20261115-1235`（30 文件 30,461B，
  pid 15692）。
- 注（启动方式教训）：直接重定向流且会话结束 → agent 收尾时 summary 未写盘；
  嵌套 Start-Job 会话结束时 job 被清理 → 孤儿进程。正解 = 持久后台 job 内启动
  agent + 持有输出流 + WaitForExit 后落盘 console/stderr/exit。
- 本验证与 B 机核验的关系：B 机核验包（§4）仍保留，用于最终双机确认；本小节
  为**单机**真实客户端路径证据（模拟房主 → 真实客户端，同一台机器）。

### 3.5 跨机核验（B 侧真实执行）— PASS（4 checks，Radmin VPN 通道）

- 时间：2026-11-15 23:33:06（B 侧 result.txt）。
- **通道**：A 机 agent 绑 `0.0.0.0:62900-62999`（模拟房主）；B 侧（VM 内装
  Radmin VPN，与 A 机同一房间）跑 `run-f5-b-probe.ps1` 向
  `255.255.255.255:62900..62999` 发 100 个 magic 并收应答。
- **结果**：`F5-B-PROBE: PASS (4 checks)`——①burst sent 100 ②reply received
  22 pages × 1104 B（24,288 B）③head magic 59 60 69 9B ④room
  `CivLink-Test-Room-2222`。
- **应答源**：`26.74.126.98:62900` = A 机 **Radmin VPN 接口 IP**——跨机（非本机
  回环）的直接证据；Radmin VPN 虚拟网卡支持广播转发，通道可用。
- **B 侧证据**：`M0A\captures\F5-dualmachine-20261115-pcb3\b-side-probe-out\`
  （24 文件：22×probe-reply-01..22.bin 全 1104B + result.txt
  EBAB78330EA1F077FD3BB7CD8DE9002DAF653B92268564E4F6F1982989F33B91 +
  firewall-rule.txt）。22 页与 A 机 lan-page 逐字节一致（唯一差异=房名 24..45
  匿名化），与 fixture 的 unexpected diffs=0。
- **A 侧计数**：本窗口 agent 未写 summary（捕获脚本缺陷 + agent 主 socket 提前
  退出路径，与 2126/2130 同症状；用户 m20220 决定不修复，以 B 侧证据为准）。
- **替代通道结论**：VMware 桥接 255.255.255.255 广播双向不转发（VM 不可作第二
  台机器）；Radmin VPN 同房间通道可用（本小节验证通过）。
- 边界：模拟房主 → 真实客户端**跨机发现链路**；不证明双人真实对局/E2-B/62056/
  Relay RTT/Fake-IP/Noise/跨网长稳；不勾 E2-A/E2-B/E3；不移动 Gate A/B。

### 3.6 真实双机核验（B 侧真实物理机 + 真实客户端可见）— PASS

- 时间：2026-11-16 16:58:23（B 侧 result.txt）。
- 环境：A 机 WLAN `192.168.31.60`（agent 以
  `--sim-lan-listen 0.0.0.0 --simulate fixture-reply-set
  --sim-room-name CivLink-Test-Room-2222 --listen-seconds 1800` 手工启动，
  窗口 16:52:52 起、17:22:53 止）；B 机为**真实第二台物理机**
  （非虚拟机），运行真实文明6 客户端。
  - 注（工件缺口，审计 R-1/R-2）：本轮为**手工启动**，未走
    `run-f5-dualmachine-a.ps1`，故**未留存 `exit.txt` / `agent-pid.txt`**
    （该脚本在 `:104` 才写 exit.txt）。因此本节**不宣称退出码、不宣称 PID**；
    「窗口自然到期」由 `summary.txt` 的 mtime `2026-11-16 17:22:53` 与 summary 内
    `listen window … for 1800.2 s` 共同佐证——精确算式：summary 内部
    `run time 09:22:53.177 UTC` = 17:22:53.177 +08:00，起点 16:52:52.977 + 1800.2 s
    （故"17:22:53"为向下取整到秒，差 0.177 s，不影响结论）。
  - 相应证据工件：`real-client-visibility-oral.txt` 亦已删除无工件支撑的 PID，
    并在该文件内留「更正（审计 F-1）」注，避免「文档不宣称 PID / 援引工件仍宣称」的自相矛盾。
- 结果：`F5-B-PROBE: PASS (4 checks)`——①burst sent 100 ②reply received
  22 pages × 1104 B（24,288 B）③head magic 59 60 69 9B ④room
  `CivLink-Test-Room-2222`。
- **应答源**：`192.168.31.60:62900` = A 机 **WLAN 接口 IP**。本次走的是**真实同一
  WLAN 的局域网广播路径**（§3.5 走的是 Radmin 隧道），更贴近"同 WLAN 双机"目标。
- **通道无关性（对原始问题的回答；适用域见末句）**：A 机 `Radmin VPN` metric=1、
  `WLAN` metric=45（1 < 45，故 Radmin 优先级**高于** WLAN），但本路径不受影响——
  agent 在每个发现端口上都做**全接口 bind**（`main.rs:544-556`），客户端广播从
  **任一**接口（WLAN 或 Radmin）到达都能收到；应答按观测到的 `(ip, port)`
  `send_to(page, from)` **单播**回发（`main.rs:636-674`）。故 F5 不依赖"哪块网卡
  抢到广播出口"，即不依赖 InterfaceMetric。
  - **适用域限定（审计 R-F 建议）**：本轮 A/B 处于**同一 on-link 网段**
    （192.168.31.0/24），metric 本不参与该路径选路，故本条只是"结果级支持"，
    而非"跨路由拓扑下同样成立"的证明；入站可达性本轮由 B 侧实际收到 22 页证实，
    但**防火墙规则的来源未逐条取证**（不宣称"规则已随 exe 放行"为已核实事实）。
- **逐字节对账**：B 侧 22 页 vs A 机 `lan-page-01..22.bin` → **22/22 完全一致**；
  vs fixture 每页仅 21 字节差异，全部落在 24..45（房名匿名化，预期内）。
- **真实客户端可见（用户口述确认）**：B 机真实 Civ6 客户端 多人 → 局域网 → 刷新，
  大厅中出现 `CivLink-Test-Room-2222`。记录
  `real-client-visibility-oral.txt`（F6658EF6…/2,167B），等级=**口述确认**
  （无截图、无客户端抓包、无游戏日志），与 §3.4 同级；机械探测证据独立成立，
  不依赖本条。
- **A 侧计数（首次拿到完整跨机计数）**：1800.2s 窗口到期、summary 正常写盘
  （`summary.txt` B6D00F8E…/2,687B）——
  `requests seen`=**384**、`replied sockets`=**4**、`pages sent`=**88**
  （恒等式 `88 == 4 × 22` 成立）、`send fail`=0、`no endpoint`=0、
  `max reached`=0、`bind fail`=0（即**无端口绑定失败**，据此**推断** 100/100
  端口均绑定成功；本轮未单独留存绑定清单）。
  - 分解 `384 = 100×3 + 84` 属**推断**（证据只有总数 384 与 4 个应答源端口；
    推测 B 机机械探测 1 轮 + 文明6 大厅刷新若干轮，末轮不足 100 包）。计数
    如实记录，未做选择性剔除。
  - CVLH2 主窗口 `datagrams`=0（LAN 广播不走 CVLH2 帧通道，符合 F5 设计：
    该模式绕过 Hook 链，直接持有发现端口）。
- B 侧证据：`M0A\captures\F5-dualmachine-20261116-realmachine\b-side-probe-out-real\`
  （**25 文件** = 24 个探针产物 + `MANIFEST-sha256.txt` 自身；`result.txt`
  416D8F60…/576B；清单 A754E417…/2,483B 覆盖那 24 个，`total_bytes`=24,909
  可精确还原。注：§3.5 的"24 文件"不含清单，口径不同，勿混比）。
- 边界：同 §3.5——模拟房主 → 真实客户端**跨机发现链路**；不证明双人真实对局/
  E2-B/62056 数据面/Relay RTT/Fake-IP/Noise/跨网长稳；不勾 E2-A/E2-B/E3；
  不移动 Gate A/B。模拟房主有意不响应"检索创建人信息"（F5 D4 约束），
  故 B 机点入房间会停在检索页，不进入对局，属预期。

## 4. 双机核验包（已执行：§3.5 Radmin 通道 + §3.6 真实双机）

`C:\Users\dd\Desktop\civlink-f5-kit\`（可拷 U 盘）：

| 文件 | sha256 | 用途 |
|---|---|---|
| civlink-agent.exe | 194E6E8A…D23DA92（404,992B） | A 机模拟房主 |
| run-f5-dualmachine-a.ps1 | D909D16F…B444B（7,926B） | A 侧编排（起 agent→等 B→断言→报告） |
| run-f5-b-probe.ps1 | FF4DDF3F…57D0 | B 侧一键探测（UAC 一次） |
| run-f5-lan-selftest.ps1 | 80C0935D…B41E | 回环自检 |
| fixture-reply-set\ | （25 文件，哈希见目录） | 22 页 fixture |
| PC-B-操作单.md | FF6679E9…E96 | 操作步骤（约 3 分钟） |

A 侧流程（脚本路径，240s 窗口）：`run-f5-dualmachine-a.ps1 -WaitSeconds 180` →
起 agent（240s 窗口）→ 打印 READY → B 机跑 probe（或 Civ6 LAN 点刷新）→ agent
收尾 → 断言（requests seen>0 / replied≥1 / pages==replied×22 / 失败计数全 0）
→ PASS/FAIL，并在 `:104` 写 `exit.txt`。

> **流程差异说明（审计 R-3）**：§3.5 与 §3.6 两轮都**不是**用上述脚本编排的，
> 而是 A 侧手工起 agent（§3.5 30 分钟、§3.6 1800s）+ B 侧跑 `run-f5-b-probe.ps1`。
> 因此两轮都**没有 `exit.txt`**；§3.6 另因手工启动亦无 `agent-pid.txt`。
> 需要 exit/pid 工件的正式运行，必须走 `run-f5-dualmachine-a.ps1`。

B 侧方式 A（机械探测，~1 分钟）：跑 `run-f5-b-probe.ps1`，期望
`F5-B-PROBE: PASS`，证据在 B 桌面 `civlink-f5-b-probe-out\`。
B 侧方式 B（真实客户端，~2 分钟）：Civ6 → 多人 → 局域网 → 刷新，看
`CivLink-Test-Room-2222` 是否出现，截图回传。

## 5. 边界（不可越界宣称）

- 本验证覆盖：**模拟房主 → 真实客户端**发现链路（跨机广播到达、Agent 应答、
  客户端收到 22 页）。方式 B 通过 = 真实 Civ6 客户端看到模拟房间。
- **不证明**：双人真实对局、E2-B 双端注入、62056 数据面、Relay RTT、Fake-IP、
  Noise 加密、跨网/长稳。
- 不得据此勾掉 E2-A/E2-B/E3；不移动 Gate A/B；Gate A 未批准，M0-B 冻结。
- 若方式 A PASS 而方式 B 看不到：属 Civ6 客户端去重/时序，按现象记录，不算失败。

## 6. 代码与产物哈希

- `civlink\agent\src\main.rs`：**2,562 行**（107,672 B，LF=2562，mtime
  2026-11-14 19:18:52；此前记为 2559 行有误，已按实测更正）——`cargo +1.75.0
  fmt/test 19 通过 / build --release --offline 全 0`
- `civlink-agent.exe`：194E6E8A00080B0F05AF14D8754F38CACE818CFC0FE667BB1E0375400D23DA92（404,992B）
  ——已同步 civlink\、civlink-f1\、civlink-f5-kit\（civlink-f4 保留 F4 发布构建 E276ECA3…）
- 自检脚本：run-f5-lan-selftest.ps1 80C0935D…；run-f5-b-probe.ps1 FF4DDF3F…；
  run-f5-dualmachine-a.ps1 D909D16F…

## 7. 状态

- 代码实现 + 三类机械证据完成（A 机独立闭环）。
- **单机真实客户端验证完成**（方案 C，用户 m19535 选定，2026-11-15 12:35 起）：
  真实 Civ6 大厅在本机看到模拟房间，证据 `F5-singlehost-20261115-1235`（§3.4）。
- **跨机核验完成（§3.5）**：2026-11-15 23:33，B 侧（VM + Radmin VPN 同房间）
  跑 run-f5-b-probe.ps1 → `F5-B-PROBE: PASS (4 checks)`，应答源
  26.74.126.98:62900（A 机 Radmin 接口）——模拟房主 → 跨机客户端发现链路验证
  通过；证据 `F5-dualmachine-20261115-pcb3\b-side-probe-out\`（24 文件）。
- **真实双机核验完成（§3.6）**：2026-11-16 16:58，B 机为**真实第二台物理机**
  （非 VM），跑 run-f5-b-probe.ps1 → `F5-B-PROBE: PASS (4 checks)`，应答源
  `192.168.31.60:62900`（A 机 **WLAN** 接口）——走真实同 WLAN 广播路径；22 页与
  A 机 lan-page 逐字节 22/22 一致；**B 机真实 Civ6 客户端大厅看到
  `CivLink-Test-Room-2222`（用户口述确认）**；证据
  `F5-dualmachine-20261116-realmachine\`（**层级说明**：子目录
  `b-side-probe-out-real\` 25 文件 = 24 个探针产物 + **该子目录内**的
  MANIFEST-sha256.txt 自身；父目录另有 `real-client-visibility-oral.txt`
  F6658EF6…/2,167B、`summary.txt` B6D00F8E…、`frame-log.txt`）。
- 文档审计（按工作模式 m16220/m16222：每完成一步立即起子代理审计）。
  F5 文档/脚本/机械证据审计闭环（REVIEW → REVIEW-2）；本小节（§3.4 单机验证）
  登记审计已完成（`docs/F5-SINGLEHOST-REGISTRATION-REVIEW.md`，2026-11-15，PASS）。
  本小节（§3.6 真实双机）登记审计链：`docs/F5-REAL-DUALMACHINE-REGISTRATION-REVIEW.md`
  → `-REVIEW-2.md` → `-REVIEW-3.md`（三轮均"有条件通过"；必改项 R3-1/R3-2/R3-3 已全部落实）。
