# M0B-ADAPTER-SELFTEST 审计报告：Discovery Adapter 双路应答本机机械自检与双机操作单

- 审计对象：`civlink-b1\run-m0b-adapter-selftest.ps1`（本机机械自检脚本）＋证据目录 `M0A\captures\M0B-adapter-selftest-20261117-131441\`（= `C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\M0B-adapter-selftest-20261117-131441\`）＋`docs\M0B-DUALMACHINE-RUNBOOK-20261117.md`（双机操作单）＋`docs\M0B-FINAL-PROGRAM-PLAN-20261117.md`（计划 v1.1）＋`civlink\agent\src\main.rs`（LanSimState 代码）
- 审计者：独立审计子代理（session-6fe30d79）
- 审计时间：2026-11-17 13:19–13:30（本机，静态证据复核＋代码走读，未实跑双机）
- **裁定：通过**（核心结论成立；必改 0 项，建议 5 项，全部为文档/断言强度级修正）

---

## 0. 审计方法

1. 证据复核：对终轮证据目录 `M0B-adapter-selftest-20261117-131441\` 全部文件独立计算 SHA-256 与字节数，与 README v1.30 声明哈希、任务声明哈希交叉比对；对 22 页 `lan-page-*.bin` 与 fixture `reply-*.bin` 做逐字节比对。
2. 脚本走读：`run-m0b-adapter-selftest.ps1` 全 107 行，逐条断言与证据目录对应验证。
3. 代码走读：`civlink\agent\src\main.rs` LanSimState 相关路径（bind 循环、reply_sock 回退、poll/consider、主循环、摘要打印），确认机制与文档描述一致。
4. 文档一致性：计划 v1.1 ↔ 操作单 v1.0 ↔ README v1.29/v1.30 授权与边界块互查；对 `civlink-b1` 三件交付物（agent exe、hook dll、ctl exe）实算哈希核对操作单声明。
5. 边界检查：README v1.29 授权块范围、v1.30 记录块、操作单 §6 边界声明逐条核对，确认无越权勾选。

---

## 1. A — 自检脚本真实性与证据一致性　结论：PASS

### 1.1 证据目录内容与哈希　PASS
- 证据目录实际位置为 `C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\M0B-adapter-selftest-20261117-131441\`（顶层 `M0A`，不在 `CivLink-M0A-audit` 审计树内——审计树 `M0A\captures` 无 M0B/B1 证据目录，README 相对路径 `M0A\captures\...` 实际锚定 injciv6-v0.3.3 根，见建议 S-5）。
- 目录共 **30 文件**＝22 页 `lan-page-*.bin`＋8 附属（`summary.txt`、`selftest-report.txt`、`agent-stderr.txt`、`agent-console.txt`、`client-received.csv`、`frame-log.txt`、`lan-fixture-manifest.txt`、`stop`）。README v1.30 称「28 文件+22 页」——与实际 30 文件不符，勘误（建议 S-1）。
- 五项关键文件哈希独立复核全部吻合：

| 文件 | 字节 | SHA-256（复核值，与声明一致） |
|---|---|---|
| summary.txt | 3,173 | 738E5FD0DBB74FAADE77DFE6E96166DA3D897742D94354F684FF71CEF5CA0E5C |
| selftest-report.txt | 3,825 | 87FC8C5B728A75299AA9C7D73F13DA1DE2CE0CB0EE7AC2782435A36C257D2873 |
| agent-stderr.txt | 257 | 4CBDFD55074C01E8AAD35B193B3CF56118BEC10F03D960C7BACD185DC86BEF39 |
| agent-console.txt | 3,442 | 9C54DB3D9A49BD231F27A828A3A9962F722D9998E110A28E8473E9D378ACE0D3 |
| client-received.csv | 655 | 43B35D6202B4DE27DA6DDB6EEC0E5BC3FD31B1A25257CF5E166274C95253E9A2 |

### 1.2 summary 关键值自洽　PASS
- `summary.txt`/`agent-console.txt`/`selftest-report.txt` 前三段同文（CVLH2 摘要），report 追加 10 行 PASS（L63-72）。
- 关键值：run time 05:16:42.489；listen window `127.0.0.1:34718 for 120.1s`（=`--listen-seconds 120`＋收尾）；`datagrams 0`（无 hook 链、无真实页捕获，符合预期）；LAN 块 `listen ip 0.0.0.0 on 62900..62999`、`room 'CivLink-Test-Room-2222'`、`reply budget 20`、**`requests seen 99`、`replied sockets 1`、`pages sent 22 (== replied*22)`、`send fail 0`、`no endpoint 0`、`max reached 0`、`bind fail 1 port(s)`**；B1 块 `captured 0`、`rejected 0`、`duplicates 0`、`noise 0`、`replies real 0`、**`replies fixture 1`、`replies skipped 98`、`active no`**。
- 机制闭环验证：客户端 100 包同源端口 54322（`UdpClient(54322)`）→ 62900 包被游戏模拟 socket（纯 UdpClient 持端口不应答）收走 → agent 收 99 请求（62901..62999）；dedup 按 `(src_ip, src_port)` 单键 → 仅 1 个应答集从 62901 发 22 页 → 98 skipped。与 summary 99/1/22/98/1 完全一致。
- `agent-stderr.txt` 单行（257B）精确匹配 `main.rs:559-561` eprintln 模板：`[!] LAN simulated host: cannot bind 0.0.0.0:62900: 通常每个套接字地址(协议/网络地址/端口)只允许使用一次。 (os error 10048) (port skipped; ...)`。

### 1.3 10/10 PASS 逐条核对　PASS（两项实时断言不可事后复核，不构成问题）
- PASS1 game-occupies-62900：`selftest-report.txt:63` 断言游戏 socket 绑 `0.0.0.0:62900`；与 `bind fail 1`、stderr 10048、应答源 62901 三证交叉一致。
- PASS2 agent-running pid=30352：实时断言，事后无法独立复核（证据为脚本输出）——仅作记录。
- PASS3 client-sent-100：`sent 400/400 bytes`＝100 包×4B magic，与脚本 `SendTo` 循环一致。
- PASS4 client-received-22-pages：`ad pages 22/22, total pkts 22`——`client-received.csv` 655B＝表头＋22 行，**22 行全 `Len=1104`、全 `From=26.74.126.98:62901`**。
- PASS5 reply-source-in-62901-62999：`26.74.126.98:62901`。注意脚本实现为**负向断言**（断言无源匹配 `:(62900|62056)$`），非正向 62901..62999 区间检查——结果正确，断言强度可提升（建议 S-4）。
- PASS6 bind-fail-1 / PASS7 replied-sockets-gte1 / PASS8 pages-sent-22：与 summary 1/1/22 一致。
- PASS9 exit-0：agent ExitCode 0；实时断言，与 10/10、脚本自身 exit 0 一致。
- PASS10 no-bind-62056：运行时 `bind 0.0.0.0:62056` 探测成功＝agent 不占数据面端口；与代码（reply socket 回退 62901、Datapath 62056 拒绝、无 SO_REUSEADDR）一致。
- `frame-log.txt`（132B＝仅表头）证实无 hook 链——`captured 0` 正确归因。

### 1.4 22 页与 fixture 逐字节比对　PASS（决定性）
- 22 页 `lan-page-01..22.bin` 各 1,104B，页头 `59 60 69 9B`，偏移 24..46 房名字段＝`CivLink-Test-Room-2222`＋NUL。
- 与 fixture `reply-01..22.bin` 逐字节比对：**除偏移 24..46 外 22/22 全等**；fixture 同区为真实房名 `dingzihan2022的游戏`（`64 69 6E 67 7A 69 68 61 6E 32 30 32 32 E7 9A 84 E6 B8 B8 E6 88 8F`）→ 实证 agent 应答＝fixture 页仅做房名匿名化（`--sim-room-name`），`replies fixture 1` 成立，`replies real 0` 与 `captured 0` 一致。
- `lan-fixture-manifest.txt` 与 `--simulate fixture-reply-set` 参数对应。

### 1.5 脚本断言与证据一致　PASS
- `run-m0b-adapter-selftest.ps1`（5,353B/107 行）：L8 OutDir；L27 清残留 agent；L31-33 模拟游戏占 62900；L36-49 agent 参数（`--listen-seconds 120 --out-dir --sim-lan-listen 0.0.0.0 --simulate <fixture> --sim-real-capture --sim-room-name CivLink-Test-Room-2222`）；L52-56 客户端 100 包；L59-74 收 8s 断言 22；L75 CSV；L77-85 stop 文件优雅退出；L88-98 断言 bind fail 1/replied≥1/pages 22/exit 0/62056 探测；L101-107 写 report、fail>0 则 exit 1。10 项断言全部有证据支持。

---

## 2. B — 操作单与计划一致性　结论：PASS

### 2.1 双路应答机制描述一致　PASS
- 操作单 §2（`M0B-DUALMACHINE-RUNBOOK-20261117.md` L10-22）与计划 v1.1 §7（`M0B-FINAL-PROGRAM-PLAN-20261117.md`）对机制描述一致：A 机 agent 绑 62900..62999 → 游戏占 62900 → `bind fail 1` → 实际 62901..62999（计划引 `main.rs:541-560`，操作单引实测 10/10 PASS）；双路应答（62900 包→游戏 socket 真实页、其余 99 包→agent 真实页优先/fixture 兜底）；命中率 1/100→~99/100。
- 数据面直连描述一致：广告页无 IP/端口字段 → B 向应答源 IP:62056 发 join → A 机 Civ6 62056 socket；agent 转发（Game Data Adapter）为备选。与计划决策 2（A 路线 UDP 直连）一致。

### 2.2 A 机启动脚本与操作单一致　PASS
- `start-m0b-adapter-a.ps1`（1,681B）实读：封装 `--listen-seconds 1800 --sim-lan-listen 0.0.0.0 --simulate fixture-reply-set --sim-real-capture --sim-room-name CivLink-Test-Room-2222`（另带 `--out-dir --quiet`），与操作单 §3 描述逐项一致。
- 操作单 §3 注入步骤（先注入后建房）：`civlink_ctl.exe inject -x CivilizationVI_DX12.exe -d civlink_hook.dll`；`civlink-b1` 三件交付物实算哈希吻合操作单声明：agent exe 417,792B `DDAF5453B35377493ABA4F464ADFC341A153861CEC1352D97F07FBBE21113D63`、hook dll 119,808B `39D6735D34520724ED790811D8862275D996C50BC321564F1F5C785C268E3411`（操作单 `39D6735D…` 吻合）、ctl exe 173,056B `D4D0D330F1AB3C9368BD0EEFC6A38F8BEEE44CFEF39F26FBF684E4F444D58FC7`。
- 文档哈希：计划 6,269B `4866784B7EA2E2435CF3D1AD2B912415C06512E2FD785E3AC900F0805B9A06AF`、操作单 4,448B `A41FB73F4D1C7C1D220A042DB1C3BA3E4F1869A969D5CE9C6289308B14BA9A83`，与 README v1.30 声明一致。

### 2.3 计划行号引用轻微漂移（建议 S-3）
- 计划 §7 引 `LanSimState::new main.rs:541-560`——实际 bind 循环 L544-563、bind_fail 计数 L557-562；`reply_sock 回退 567-576`——实际 L570-579；`run() 1562-1587`——实际 LanSimState::new 调用 L1579-1590。机制结论不受影响，建议刷新行号（S-3）。

---

## 3. C — 边界检查　结论：PASS

- **授权范围**（README v1.29 块）：负责人 m24348 授权「忽略各种冻结…直接开始最终程序的编写」，Gate B/M0-B 冻结解除；范围＝Discovery Adapter（A 机 Agent 绑全 100 发现端口＋真实广告页应答）与 Game Data Adapter（62056 双向转发）编写与双机真实联机验证。本轮自检与操作单均在范围内。
- **如实声明机械证据≠双人验证**：README v1.29/v1.30 均声明「工具级/模拟证据仍不得宣传为双人真实联机验证、双人结论以 E2-A/E2-B/E3 真实双机为准」；操作单 §6 明确「机械证据（10/10 PASS）不得宣传为双人真实联机验证」。PASS。
- **不勾 E2-A/E2-B/E3**：README v1.30 记录「下一步＝双机真实验证（E2-A/E2-B/E3 结案）」——E2 各证为**待办**非已完成；操作单 §6 边界声明本轮＝真实双机发现＋加入链路（E2-B 结案目标），对局完整性/长稳/跨网/加密不在本轮；v1.28 边界块（历史）明确 B1「不勾 E2-A/E2-B/E3、不移动 Gate A/B」。无越权勾选。PASS。
- **边界登记完整**：双路应答可能双条房间记录（计划 §7 新增边界、操作单 §6、README v1.30 三方一致）；Agent 永不 bind 0.0.0.0:62056、永不 SO_REUSEADDR、每帧单次不重传不篡改（操作单 §6）——与代码一致（见 §4）。PASS。

---

## 4. D — 代码事实核验　结论：PASS

### 4.1 bind 循环与 bind_fail（main.rs:544-563）　PASS
- `LanSimState::new` 逐端口 bind `62900..62999`：Ok→push listener，`port == SIM_REPLY_PORT(62900)` 时 clone 为 `reply_sock`（L552-554）；Err→`bind_fail += 1`＋eprintln（L557-562，模板与 agent-stderr.txt 单行精确吻合）。
- 游戏占 0.0.0.0:62900 → 62900 bind 失败 → 实际监听 62901..62999（99 端口）——与证据 `requests seen 99`、`bind fail 1`、`From 26.74.126.98:62901` 一致。

### 4.2 reply_sock 回退（main.rs:570-579）　PASS
- `reply_sock` 为 None（62900 失败）时 clone `listeners[0]`（第一个成功绑定 socket＝62901）——与证据应答源 62901 一致；**agent 不因回退触碰 62056**（回退候选全部 ∈ 62901..62999）。

### 4.3 poll/consider：双路应答与真实/fixture 选择（main.rs:613-666, 674-723）　PASS
- poll 排空全部 listener；magic（len==4 且==DISCOVERY_MAGIC）→ `consider`，`real_pages if cache.active`（L620-632）；非 magic 且 cache 存在→`try_capture`（L634-649）。
- consider：V6 直接 Skipped；src_port==0→no_endpoint；`requests_seen += 1`；按 `(ip,src_port)` 去重（answered 键）；`replied_sockets >= max_replies`（默认 20，L1369）→max_reached；`pages = real_pages 非空则用否则 fixture`（L698-701）→ 逐页 `reply_sock.send_to`（Ok==len→pages_sent++ 否则 send_fail++）→ 全成功 `answered.insert + replied_sockets += 1`、`real_pages.is_some()`→Real 否则 Fixture；否则 Skipped。
- 与证据 99/1/22/98/1（real 0、fixture 1、skipped 98）完全闭环；`--sim-real-capture`（RealAdCache L1665-1672）未激活时真实页优先逻辑不触发、fixture 兜底——与 `active no` 一致。

### 4.4 主循环与捕获入口（main.rs:1579-1590, 1665-1672, 1679-1691, 1718-1721, 1797-1810）　PASS
- `run()`：`--sim-lan-listen` 分支调 `LanSimState::new`（L1579-1590）；stop 文件检查（L1679-1691）；主循环每轮 `lan_sim.poll`（L1718-1721）；P1 帧捕获入口（L1797-1810，flags DISCOVERY 且非 rejected→try_capture，22 页满 flip active）——本自检无 hook 链故 captured 0，符合预期。
- 数据面隔离：全文件无 `SO_REUSEADDR` 调用（仅注释「never sets SO_REUSEADDR」L28/L2279）；测试 L2586-2588 断言 reply socket 必须 ephemeral 且非 62056；L2702-2710 `ForwardListener::new(62056)` 被拒。**Agent 永不 bind 0.0.0.0:62056** 成立。

### 4.5 摘要打印 nit（建议 S-2）
- `main.rs:2115-2119` 打印 `reply source: {sim_lan_listen}:{SIM_REPLY_PORT}`＝配置值 `0.0.0.0:62900`，而回退后实际应答源为 62901（证据 `client-received.csv`、PASS5 均已记录实际值）——summary 该行是配置值非实际值，不影响结论，建议打印 `reply_sock.local_addr()`（S-2）。

---

## 5. 裁定

**裁定：通过**（核心结论成立——自检脚本真实、证据与断言 10/10 一致、操作单与计划及代码机制一致、边界声明如实；必改 0 项）。

### 必改项
- 无。

### 建议项（不影响通过，全部为文档/断言强度级）
- **S-1**：README v1.30「证据目录（28 文件+22 页）」勘误——实际 30 文件（22 页＋8 附属）。
- **S-2**：`civlink\agent\src\main.rs:2115-2119` summary 的 `reply source` 打印配置值 `0.0.0.0:62900` 而非实际回退端口 62901；建议打印 `reply_sock.local_addr()`（避免后续阅读摘要时误读）。
- **S-3**：计划 `M0B-FINAL-PROGRAM-PLAN-20261117.md` §7 行号引用刷新：`541-560→544-563`、`567-576→570-579`、`1562-1587→1579-1590`。
- **S-4**：`run-m0b-adapter-selftest.ps1` PASS5 由负向断言（无源匹配 62900/62056）改为正向断言（源端口 ∈ 62901..62999），并对 `requests seen==99 / replied==1 / skipped==98 / fixture==1` 增加精确断言（当前仅 `>=1`），提升回归强度。
- **S-5**：README 证据路径 `M0A\captures\...` 实际解析到 `C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\`（injciv6-v0.3.3 根）而非 `CivLink-M0A-audit` 审计树内（审计树 `M0A\captures` 无 M0B/B1 目录）；建议在 README 中注明证据目录锚点，避免后续审计者路径解析歧义。

### 范围界定（登记，非缺陷）
- 本自检仅验证双路应答的 **agent 侧**（62901..62999 收 99 请求、fixture 页 22 连发、不占 62056）；**游戏侧**应答（62900 包→游戏 socket 发真实页）依赖既有取证（run-20261117-095336 civtrace 22 条 sendto、B1-p1-e2e 捕获），本自检未覆盖。README/操作单已如实表述（机械证据≠双人验证），符合登记口径。
- `pid=30352`（PASS2）与 exit code（PASS9）为实时断言，事后无法独立复核；不构成证据问题（有 summary/report 及 22 页落盘佐证）。
