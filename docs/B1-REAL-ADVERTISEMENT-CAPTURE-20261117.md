# B1：真实广告页捕获（方案 B 第一阶段）

版本：v1.1（2026-11-17）
状态：**已实现 + 机械证据 PASS 13/13（run-20261117-005925）**；子代理审计进行中（f8918c50，
→ `docs/B1-REAL-ADVERTISEMENT-CAPTURE-REVIEW.md`）；**尚未双机验证**，不构成联机验证。

## 1. 背景与目标

用户选择「方案 B：直接推进 civlink 数据面方案」。方案 B 的最终形态（技术设计规范 v2.1 §4.5）是
B 机的发现请求经 Hook 链 → Agent → Relay → A 机，A 机的广告页应答经同路径回传，从而让 A→B 的
发现走**确定性通道**，不依赖 Windows 广播选路（Radmin metric=1 抢占）、接口 metric 或入站防火墙规则
（E2B-firstround 归档的失败根因，b467/b471）。

F5（REV-016 双机发现）已证明：agent 绑 `0.0.0.0:62900..62999` 全 100 个发现端口 + 对 magic 请求
**单播回发** 22 页应答，跨机可达（真实双机 384 请求 / 4 socket / 88 页全发出，PASS 4/4，b443）。
但 F5 应答内容是 **fixture**（匿名房名 CivLink-Test-Room-2222），不是 A 机真实房间。

**B1 的目标**：让 agent 的应答内容从 fixture 升级为 **A 机 Civ6 发出的真实广告页**（真实房间名、
Mod 列表、规则集等，即 F5 fixture 被匿名化前的原始内容），使得 B 机刷新时看到的是 A 机的真实房间。

**B1 的边界**（如实声明，本阶段只做捕获与缓存）：
- 只捕获/缓存广告页；**不修改**任何游戏进程行为（无注入、无帧篡改）。
- 不实现 §4.5 的 Fake-IP 注入、不实现 Relay 中继、不实现 62056 数据面转发（属 B2+ 阶段）。
- 不证明双人对局、不证明 E2-B/E3、不移动 Gate A/B；Gate A 未批准、M0-B 冻结。
- 双机验证仍需要用户操作（B 机刷新、回传证据）。

## 2. 广告页识别

- 广告页 = Civ6 主机（或模拟房主）发出的**发现应答**，每页 **1104 字节**（SIM_PAGE_SIZE），
  一房间 **22 页**（SIM_PAGE_COUNT），页头 4 字节固定为 `59 60 69 9b`（SIM_MAGIC，即
  `0x5960699b`，与 fixture reply-01.bin 的 head 一致）。
- 识别规则（判定一帧/一数据报为「广告页」）：
  1. `len == 1104`
  2. `buf[0..4] == 59 60 69 9b`
- 该规则与客户端 4B magic（`8d e8 fc 70`，DISCOVERY_MAGIC）天然互斥（长度不同），无歧义。

## 3. 捕获路径（双路径，任一可用即捕获）

### 路径 P1：Hook 链转发（A 机 Civ6 注入 civlink_hook.dll 时）
- A 机 Civ6 建房后应答发现请求，`sendto`/`WSASendTo` 发出广告页。**socket-身份判定（v0.2.1-hook，B1 §0 取证驱动）**：
  `hook.cpp` `IsDiscoveryTarget(SOCKET s, const sockaddr_in* sin, uint8_t* flagsOut)`（L257-268）在原有
  「目标端口 62900..62999 或 `255.255.255.255` 广播」判定之上，**新增：socket 曾 bind 62900..62999
  （发现 socket，`SlotBoundPort(s)`）→ 其所有 sendto 无论目标端口都置 `FLAG_DISCOVERY` 转发**。
- **驱动依据（§0 取证，2026-11-17）**：真实房主广告页是**单播应答到请求者源地址:源端口**（触发实验
  run-20261117-095336：22 条 `sendto s=0x13f0 bound=0.0.0.0:62900 dst=26.74.126.98:54322 len=1104`，
  头 `59 60 69 9b`）——目标端口是请求者临时端口（54322），按目标端口判定会漏，故改按 socket 身份。
- 命中后 `ForwardFrame`（L276-322）把**完整 payload** 经 CVLH2 帧发到 agent（127.0.0.1:34718）。
  1104B ≤ MAX_PAYLOAD(1280)，不会走 oversize 拒绝路径。
- agent 主循环 `decode` 后帧的 `frame.payload` 即完整广告页；`frame.flags & FLAG_DISCOVERY != 0`。
- **★P1 端到端已验证（2026-11-17，run-20261117-102852）**：真实 A 机 Civ6 房主 + 注入新 hook
  （0965154A）+ agent `--sim-real-capture` → trigger 触发 → **22 页全部经 P1 捕获落盘**
  （captured=22/rejected=0/duplicates=0/noise=0/active=yes、discovery_flag=22），
  证据 `M0A\captures\B1-p1-e2e-20261117-102852\`；详见 §5.1。

### 路径 P2：LAN 监听直收（无注入；本机广播回环）
- 本机广播回环已实测验证（2026-11-17 00:19 机制验证）：绑 `0.0.0.0:62900` 的 socket 能收到
  本机发出的 `255.255.255.255:62900` 广播（来源显示为发出接口的地址，本例为 Radmin 26.74.126.98，
  因 metric=1 优先，但回环仍送达绑定 socket）。
- **但真实 A 机 P2 不可用（run-20261117-100824 实锤）**：① Civ6 房主占 `0.0.0.0:62900` → agent 绑
  100 发现端口 `bind fail: 1 port`（C1 回环全丢）；② 广告页形态已实测为**单播应答到请求者临时端口**
  （§0 取证），目标端口非 62900..62999、非广播 → P2 直收路径对真实房主无效。
- **P2 结论**：B1 真实部署只能走 **P1（hook 链，socket-身份判定）**；P2 仅在本机模拟/无房主竞争
  场景有效（F5 fixture 模式仍走 P2，不受影响）。

## 4. agent 改动点（实现范围）

`civlink\agent\src\main.rs`：

1. **新状态** `RealAdCache`（或并入 LanSimState/SimState）：
   - `pages: Vec<Vec<u8>>`（捕获到的真实页，按到达顺序；每页先校验 §2 规则）
   - `saw_magic: bool`（是否已见 `59 60 69 9b` 头，防噪声帧污染）
   - `stats: { captured: u64, rejected: u64, first_at: Option<Instant>, last_at: Option<Instant> }`
2. **捕获入口 A（Hook 链帧）**：主循环 `decode` 成功后、`sim_state.consider` 之前：
   - 若 `frame.flags & FLAG_DISCOVERY != 0` 且 `payload_len == 1104` 且 `payload[0..4] == SIM_MAGIC` → 缓存。
3. **捕获入口 B（LAN 监听数据报）**：`LanSimState::poll` 的非 magic 分支：
   - 命中 §2 规则 → 缓存（存到与 lan_sim 关联的 cache）。
4. **应答策略**：`consider()`（L636-674）发送时：
   - 若 cache 已有 ≥1 页 → 用真实页（当前捕获集）应答；
   - 否则退回 fixture 页（现状行为，作为兜底并计入 `stats.used_fixture`）。
   - 页面数：若已捕获满 22 页 → 发 22 页；若不足 → 发已捕获页数 + 剩余用 fixture 补齐？
     （**待审计讨论**：补齐会混入匿名房名，建议不足时全用 fixture 并标注，避免半真实半匿名。）
5. **CLI**：新增 `--sim-real-capture`（开关，与 `--sim-lan-listen`/`--simulate` 组合）：
   - 启用后允许捕获；未启用时行为与现状完全一致（默认关闭 = 零回归风险）。
6. **落盘**：`--out-dir` 下写 `real-page-01..NN.bin`（NN 为捕获页数）+ `real-ad-manifest.txt`
   （捕获时间、来源路径 P1/P2、页数、每页 sha256）+ 摘要行 `real_ad_captured=N rejected=M used_fixture=K`。

## 5. 机械证据（已执行：run-20261117-012424，PASS 17/17）

### 5.1 ★P1 端到端验证（run-20261117-102852，决定性）

**场景**：真实 A 机 Civ6 房主（pid 37528，房间名 `dingzihan2022`）+ 注入新 hook
`civlink_hook.dll`（sha256 `0965154ACC92424B957FD77ED6DC7FF497366DCAEC9F7758902E5E47424CE14C`）
+ agent `--sim-real-capture`（无 `--sim-lan-listen`，P2 被房主占 62900 排除）→ 本机模拟客户端
（54322 发 100 magic 广播）触发房主单播应答 → hook socket-身份判定捕获 → CVLH2 转发 → agent 落盘。

**结果（summary.txt 实测）**：`datagrams=22 / received frames=22（processed 22, rejected 0）/
reconciliation 22==22 / seq gaps=0 missing=0 duplicates=0 out_of_order=0 / discovery_flag=22（全经 P1）/
captured=22 / rejected=0 / duplicates=0 / noise on disc=0 / replies real=0 / replies fixture=0 /
replies skipped=0 / active=yes（full 22-page set captured）`。

**独立复核**：
- 22 页 `real-page-01..22.bin`（各 1104B）独立 Get-FileHash 与 `real-ad-manifest.txt` **0/22 不匹配**；
- `real-page-01` ≠ `sim-page-01`（fixture 备份）→ 真实页非 fixture；
- `real-page-01` 头 16B `59 60 69 9B 2E 69 04 00 00 00 00 00 03 00 00 00` 与 §0 取证
  （run-20261117-095336，civtrace `sendto s=0x13f0 bound=0.0.0.0:62900 dst=26.74.126.98:54322 len=1104`）
  data 头**逐字节一致**；
- 房间名区域（偏移 24..45）含 `dingzihan2022…`（真实房主名）→ 确认真实捕获。

**证据目录** `M0A\captures\B1-p1-e2e-20261117-102852\`（51 文件，含 sim-page 备份）：
summary.txt 3,465B / `4F6279A547B583EA7768A5AE7E3AB7B94B9E360991320471FE62B3989237BEA0`；
real-ad-manifest.txt 2,266B / `2C3879F38C24D41ADEEB0238564E4BB714AA439356C2434CA4E88E2D2BBA4873`；
frame-log.txt 3,454B / `81A1EFB19C51D4FBF1501589B999CB98C130845675D15155C87CAFE829ED3E8E`；
stderr.txt 1,267B / `D6A0CBDC622F1ECAFA394C02ECDDB402136CF359623EDE7B52C1323871623AEF`（22 行
`[+] B1 real advertisement page N/22 captured via P1-hook`）；real-page-01 `DDC8CD34…D99E8`；
real-page-22 `6F98152D…4647FD9`。

**边界**：证明「真实 Civ6 房主单播广告页可经 hook socket-身份判定捕获并落盘」；**不证明**
双机真实联机/E2-B/E3/Relay/Fake-IP/Noise；P2 对真实房主不可用（§3）。

**审计**：`docs/B1-P1-E2E-REVIEW.md`（子代理 e1f7ebaf）**裁定「有条件通过」**：
A 代码正确性 PASS（socket-身份判定真正生效，纯观测不吞包，SlotBoundPort 仅 rc==0 且端口非 0 记录）；
B 证据真实性 PASS（决定性：终轮无 `--sim-lan-listen`、`requests seen=0`、22 帧全 `flags=0x04` 且
dst 端口全 54322——旧版按目标端口过滤必不捕获，证明身份判定经 P1 链端到端生效）；
C 登记口径 PASS；D 证据完整（132B 空表头→3454B 差异解释成立；E2E 触发侧目录为空属建议项）；
E 回归无（仅改 L271-276，F1/F2 断言全 PASS；62056 数据面 socket 不在发现范围仍 OBSERVED）。
**必改项已落实**：`hook_selftest.cpp` 两处断言预期值修正（L242 `rawBindCalls` 2→3 补计 idSock 62905
bind；L316 `sent` 3→4 补计 B1 身份用例 rc9）；修复后重跑 = **6 FAIL 全部为 62056 环境冲突级联**
（Civ6 pid 37528 持 `0.0.0.0:62056` → bind 失败 → 连锁计数），**0 项产品缺陷、0 项脚本缺陷**；
**Civ6 关闭后复跑 = 55 项全绿（HOOK-SELFTEST: PASS, 0 failure）——本机全测试闭环**；
B1 新增 4 用例与 F1/F2 断言全 PASS。新身份：`hook_selftest.exe` 150,016B/`33B56AE7…`、
`civlink_hook.dll` 119,808B/`39D6735D…`、`civlink_ctl.exe` 173,056B/`D4D0D330…`。
**建议项登记**：S-1 getsockname 回退（覆盖注入晚于 bind）、S-2 trigger 脚本落盘 client-received
全页哈希、S-3 命令固化可复现、S-4 DISCOVERY 帧 F3-A 直转排除语义（main.rs:1826-1829）供 B2 参考、
S-5 证据目录 51 文件勘误（非 50）。

### 5.2 机械证据（run-20261117-012424，PASS 17/17）

自检脚本 `civlink\run-b1-realcap-selftest.ps1`（19,592B，366 行；不需 UAC）：
- **用例 C1（P2 回环捕获）**：起 agent（`--sim-lan-listen 0.0.0.0 --simulate fixture
  --sim-real-capture --sim-room-name CivLink-Test-Room-2222`，45s 窗口）；用真实 fixture 页
  （`civlink\fixture-reply-set\reply-01..22.bin`，head 即 `59 60 69 9b`）模拟「A 机 Civ6 广播
  广告页」向 `255.255.255.255:62900` 逐页广播（间隔 120ms）；断言捕获 22 页且与发送源**逐字节一致**。
- **用例 C2（P1 Hook 链帧捕获）**：向 agent IPC（127.0.0.1:34718）发送手工编码的 CVLH2 v2 帧
  （flags=DISCOVERY 0x04、payload=page1 的 1104B）模拟 Hook 转发；断言该页作为**重复页**
  （P1/P2 双重投递）计 `duplicates` 而非第 23 页。
- **用例 C3（应答升级）**：捕获完成后，从 54322 发 100 个 4B magic（模拟 B 机刷新）→ 断言应答页
  == 捕获页（`replies real` 计数，而非 fixture）。
- **负向用例 C4**：64B 噪声 + 1104B 全零（wrong magic）广播 → 断言计 `noise`（R-2 语义：
  非页数据报计 noise 不计 rejected）、不缓存。
- **断言 A0-A14c 共 17 项**（A6 全 22 页逐字节比对 S-2；A13 恒等式
  `captured+rejected+duplicates+noise == 25` S-1；A14/A14b/A14c replies 三态恒等式 R-3）。

**结果（采信轮，R-1/R-2/R-3 修正后重跑）**：`B1-REALCAP-SELFTEST: PASS (17 checks, 0 failures)`，exit 0。
- summary 关键值：`requests seen=100 / replied sockets=1 / pages sent=22 / captured=22 /
  rejected=0 / duplicates=1 / noise on disc=2 / replies real=1 / replies fixture=0 /
  replies skipped=99 / active=yes（full 22-page set captured）`
- **语义说明（审计 R-2/R-3 修正）**：`rejected=0` = C4 两噪声按 R-2 语义计 `noise=2`
  而非 rejected（rejected 仅计「满 22 页后的新不同页」）；`replies fixture=0` = 无 fixture 兜底
  外发，100 个 magic 同源 54322，第一个答真实页（replies real=1）、其余 99 个去重跳过
  （replies skipped=99，R-3 三态）。
- 证据目录 `docs\reports\b1\run-20261117-012424\`（51 文件：顶层 3 + agent 48；evidence-sha256.txt
  列 49 条不含自身与 stop，L-4 已核对）：result.txt 54B；agent\summary.txt 3,562B；
  agent\real-ad-manifest.txt 2,266B；agent\real-page-01..22.bin（各 1104B）；agent\frame-log.txt
  275B（单帧 `dir=0 seq=1 dst=255.255.255.255:62900 len=1104 flags=0x04 src=127.0.0.1:62000
  head=5960699B2E690400` = C2 帧）。
- **代码身份（R-2/R-3 修正后重编译实测）**：`civlink\agent\src\main.rs` 121,851B / sha256
  `2687401CECDF2D5679F037DDCA6E4434685EFABF6A4FF94A6E9DBCABE8A419E7`；`civlink\agent\target\debug\
  civlink-agent.exe` 868,352B / sha256 `69CD012E24AC6758550348D4EB5D46C5EA6CB86E667D205F454416BE1187D2AC`
  （debug 构建，R-2/R-3 后）。release 版 `civlink\agent\target\release\civlink-agent.exe` 417,792B /
  sha256 `DDAF5453B35377493ABA4F464ADFC341A153861CEC1352D97F07FBBE21113D63`（R-2/R-3 修正后重编；
  旧 417,280B/`78D71DE7…` 作废）。
  证据目录全部文件哈希见 `evidence-sha256.txt`。

**脚本稳定性修复（重要）**：早期版本用 `BeginOutputReadLine` 事件处理器收集 agent 输出，
事件 scriptblock 在 PS 5.1 后台线程执行，作用域解析问题导致未捕获线程异常 → **powershell.exe
进程级崩溃**（exit 2，顶层 catch 抓不到；曾多次随机崩溃于 C3/C4 之间）。修复为 .NET Task
`ReadToEndAsync` + `Task.Result`（WaitForExit/Kill 后收集），崩溃消失。

## 6. 文档与登记（审计闭环）

- **子代理审计（f8918c50）裁定「有条件通过」**：报告 `docs/B1-REAL-ADVERTISEMENT-CAPTURE-REVIEW.md`（146 行）。
  A 机制正确；B 证据两处语义错标（R-2 noise/rejected、R-3 replies fixture/skipped）已修正；C 边界四登记
  全部正确；D 脚本无自指断言、A6 判别力真实；E 代码生产路径无 unwrap/panic、单线程无竞态。
- **必改 3 项已落实**：R-1（高）P1 单播覆盖高估 → §3 已降级 + RUNBOOK 重写 + §0 取证实测发送形态
  （单播应答到请求者临时端口）→ **hook 按 socket 身份判定改造 + P1 端到端验证成功（§5.1）**；
  R-2/R-3（中）语义错标 → 代码三态返回 + 重跑 run-20261117-012424 PASS 17/17。
- **复审（cfc28fc4）裁定「通过」**：报告 `docs/B1-REAL-ADVERTISEMENT-CAPTURE-REVIEW-2.md`（无必改项，
  2 低建议 L-1/L-2 已落实）。
- **P1 端到端审计（e1f7ebaf）**：`docs/B1-P1-E2E-REVIEW.md`（A 代码/B 证据/C 登记/D 完整性/E 回归）。
- **登记链**：README **v1.26 修订记录块**与 CODEX-HANDOVER **第 17 项**已登记 B1
  （v0.4.5 最终 + B1 新采信轮），见 §7 与两文档的修订记录（登记链引用不含本文件哈希，
  避免循环依赖；两文档的当前 sha256 以各自文件实测为准）。
- 双机验证（B 机刷新看到 A 真实房间）在机械证据通过后另行执行（需用户操作）。

## 7. 关系

- F5 文档：`docs/F5-LAN-SIMULATED-HOST-20261115.md`（fixture 应答的既有验证）。
- E2B 首轮失败：`M0A\captures\E2B-firstround-20261116\`（Radmin 选路 + 防火墙根因）。
- 技术设计规范 v2.1 §4.5（Discovery Adapter 完整双向路径，B1 只做其中「捕获真实页」一步）。
- 登记：`README.md` **v1.26 修订记录块**与 `docs/CODEX-HANDOVER-M0A.md` **第 17 项**
  （登记链按版本号/项号引用，避免哈希循环依赖；两文档当前 sha256 以各自文件实测为准）。

## 8. 下一步

1. ~~实现 §4 改动（agent，Rust `cargo +1.75.0 --offline`）~~ **已完成**（main.rs RealAdCache +
   `--sim-real-capture` + 捕获入口 A/B + 应答策略 + 落盘；cargo build 通过）。
2. ~~机械证据脚本 + 运行（§5 六用例）~~ **已完成**（run-20261117-012424 PASS 17/17，R-2/R-3 修正后）。
3. ~~子代理审计（f8918c50）~~ **已完成**（有条件通过，必改 R-1/R-2/R-3 已落实）→ ~~复审~~
   **已完成**（cfc28fc4 通过，L-1/L-2 落实）。
4. ~~双机验证前置：实测 A 机主机广告页发送形态（§0 取证）~~ **已完成**（run-20261117-095336：
   单播应答到请求者临时端口）→ **hook socket-身份判定改造 + P1 端到端验证**（§5.1，
   run-20261117-102852 捕获 22 页）→ P1 审计（e1f7ebaf）待返回。
5. 双机验证（用户操作 B 机；A 机 Civ6 建房 + 注入 hook → agent `--sim-real-capture` 捕获真实页 →
   B 机刷新看到真实房间名而非匿名 fixture）。
6. ~~登记 README/CODEX-HANDOVER~~ **已完成**（v1.26 / 第 17 项，v0.4.5 最终 + B1）。
