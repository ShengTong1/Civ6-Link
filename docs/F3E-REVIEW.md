# F3-E 故障注入 独立审计报告（第三轮 · 承接 F3B-REVIEW-3.md E5）

- 审计对象：`F3E-FAULT-INJECTION-20261114.md` / `civlink/run-f3e-fault-injection-selftest.ps1` / `civlink/relay/target/release/civlink-relay.exe` / `M0A/captures/F3E-fault-injection-selftest-20261114-*`（全部证据目录）
- 审计方式：只读；全部哈希用 `Get-FileHash -Algorithm SHA256` 独立重算并逐字节比对；脚本全文（475 行）与 relay 源码（`relay/src/main.rs`，587 行，含审计期间新增的 `--version` 分支）通读核对；证据文件逐条验算
- 审计日期：2026-11-14 16:32–16:50
- **重要时序声明**：审计期间（16:33–16:36）对象发生更新——relay 源码 16:33:55 修改（新增 F4 `--version`）、relay exe 16:34:17 重建（AE03327E→9E323F81）、16:35:35 生成新证据目录 `-163533`、文档 16:36:23 更新（10,718B/8D52987A→11,637B/3ED83453，采信切换至 `-163533`）。本报告 A 节分列"任务书声称值（旧快照）"与"当前实测值（新快照）"，两代均已独立核对。任务书声称值对应审计开始时旧快照，除对象更新导致的自然差异外全部命中。

---

## A 节：哈希核对结果

### A.1 文档 `docs/F3E-FAULT-INJECTION-20261114.md`

| 项 | 任务书声称值（旧快照） | 当前实测值（新快照） | 判定 |
|---|---|---|---|
| 大小 | 10,718 B | **11,637 B** | 不符 |
| SHA256 | `8D52987A63E8642381A1B2C8A31BBF64F4916494F891C6E4CFDE8AA2C923BCD2` | **`3ED834536DD8A53FB07B7462FDF10E60384E5CCDC311EF5665C30D53C4126F72`** | 不符 |

- 声称值 vs 实测值：**8D52987A…（10,718B） vs 3ED83453…（11,637B）**。
- 原因：文档于审计期间 16:36:23 更新为 revision 1（§0 行 3/14/15：relay 因 F4 `--version` 重建为 9E323F81 后重跑，采信切换 `-162129`→`-163533`，旧采信降为历史记录）。旧版 10,718B/8D52987A 在更新前已由审计方实测命中（186 行，采信 `-162129`），内容记录见审计过程摘要。无 git/备份，旧版不可恢复。
- **判定：命中（旧快照）/ 命中（新快照）**。差异系文档主动升级，非内容不符；文档 §0 已如实披露更新事实（诚实自披露）。

### A.2 脚本 `civlink/run-f3e-fault-injection-selftest.ps1`

- 声称：22,435 B / `BA002D94AC5EB4220A4E6AD09C2F1BC29293B8C9A8A3995CC26F365D366D9162`
- 实测：**22,435 B / `BA002D94AC5EB4220A4E6AD09C2F1BC29293B8C9A8A3995CC26F365D366D9162`**
- **判定：命中**（审计期间未再修改，LastWriteTime 16:21:22 早于本轮；且与文档 §7.1 行 152 采信行一致）。

### A.3 relay 可执行文件 `civlink/relay/target/release/civlink-relay.exe`

| 项 | 任务书声称值（旧快照） | 当前实测值（新快照） | 判定 |
|---|---|---|---|
| 大小 | 262,144 B | **262,144 B** | 命中 |
| SHA256 | `AE03327E417E89A3A885D87A9C7330CE331EAE9E4C24AE27B3AB5B13C0225BE3` | **`9E323F818AF0DE7699F6C3DBA7D29FB786BBC27CDC2F2D5B908E935A7D60C98C`** | 不符 |

- 声称值 vs 实测值：**AE03327E… vs 9E323F81…**（大小同为 262,144B）。
- 原因：16:34:17 因 F4 `--version` 重建。旧值 AE03327E 在重建前已由审计方实测命中（与旧证据 `-162129/result.txt` 内 relay sha256 行一致，可交叉印证）。新版文档 §7.1 行 153 采信行 = 9E323F81…，实测命中；行 154 仍保留旧行 AE03327E… 并注明"已被重建覆盖"。main.rs 现含 `--version`/`-V` 分支（main.rs:191-192），与文档声明一致。
- **判定：命中（旧快照）/ 命中（新快照）**。

### A.4 证据目录哈希表核对（文档 §7.2）

**新采信 `-163533` 目录（16 个文件 + `E4/` 空目录）：16/16 全部命中，0 不符。**

| 文件 | 大小 | 文档 §7.2 声称 SHA256 | 实测 SHA256 | 判定 |
|---|---|---|---|---|
| `result.txt` | 895 | `9632BC8736B519873058FD460102B9F2D32DE806D2C3AB9DF3065B86C30A8D07` | 同 | 命中 |
| `E1/E1-console.txt` | 1934 | `4DD7D8781AFB412918C7FE141A9FA9FCA12144B9202FE2A50450948EC31D15A8` | 同 | 命中 |
| `E1/E1-exit.txt` | 12 | `600765DEEFAB0CBE0138F399147E5415E6C55959D702D3FED74AFD470D9EAE6E` | 同 | 命中 |
| `E1/E1-stderr.txt` | 96 | `CA3F0D8DC27FBF28E16B88C41D70063505DDA95A836F9B5F3692D4A4DF010667` | 同 | 命中 |
| `E1/relay-log.txt` | 744 | `C16B9748EB277F7658A9599502C1B81E6F49B3AD97860C0B76AD53B58E5CF2DF` | 同 | 命中 |
| `E1/relay-summary.txt` | 1597 | `880AB611100F0F55624C024DC7143E2E8BBD6DBFDE8E162B0C912908C746F53E` | 同 | 命中 |
| `E2/E2-console.txt` | 1857 | `A9439E88E3DC77D0345764864723B091864663965AD6AD29778BA9F4C8F985B1` | 同 | 命中 |
| `E2/E2-exit.txt` | 12 | `01AD8A20D9C655F39D931C98ACC135EF2B5505ECCEE6B6845F1667FF01CAD1AE` | 同 | 命中 |
| `E2/E2-stderr.txt` | 5 | `F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295` | 同 | 命中 |
| `E2/E2-stop.txt` | 6 | `A0B28CDF92E250A1A93294D91144A0F893D27197D56B39991CC421768794005F` | 同 | 命中 |
| `E2/relay-log.txt` | 622 | `BAB148F49E6E8A65D11AD20ED8856821C56F65FC02772810B1C286CCED22AD62` | 同 | 命中 |
| `E2/relay-summary.txt` | 1520 | `610C37007FD4ACF68CB104506A57F96FEE03FB510CD729C0AB1BFDA153ADA574` | 同 | 命中 |
| `E3/E3-console.txt` | 62 | `3870CE7BCADC647E212F2CA3EC7951A8D2BD6756A43A8D622DD73BDD8712D055` | 同 | 命中 |
| `E3/E3-exit.txt` | 13 | `EB73CB2E5D812CB0038DAA32EF7769738C4FDEA9030370BD58FE782009360377` | 同 | 命中 |
| `E3/E3-stderr.txt` | 5 | `F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295` | 同 | 命中 |
| `E3/relay-log.txt` | 86 | `C62C5AD174DF20FC6CF4CEFB2E23F786AD90407299B1F831CB07F6C3A2A05BF0` | 同 | 命中 |
| `E4/` | — | 占位行（无哈希，行 176："E-4 无 relay 进程"） | 空目录 | 一致 |

**旧采信 `-162129` 目录（16 个文件 + `E4/` 空目录）：按旧版文档 §7.2 表逐项核对全部命中**（审计方在文档更新前完成，16/16）。与 `-163533` 逐文件比较：7 个 DIFF（`result.txt` 的 relay sha 行/evidence dir 路径、E1/E2 的 console/log/summary——仅时间戳与临时端口号不同）、9 个 SAME（E1-exit/E1-stderr/E2-exit/E2-stderr/E2-stop/E3 全部）。两目录计数器完全一致（E1：datagrams 8 / registers 6 / fwd 2 / forwarded 2 / identity 8 / reconciliation 2==2 / fatal 10054 / exit 3；E2：exit 0 / datagrams 7 / identity 7 / reconciliation 1==1）。**两次运行行为一致，可交叉印证。**

---

## B 节：脚本 / 文档 / 证据交叉核对

### B.1 文档 §2 四场景设计 vs 脚本实现（脚本全文 475 行）

| 场景 | 文档 §2 描述 | 脚本实现 | 判定 |
|---|---|---|---|
| E-1 fatal/exit 3 真实用例 | 对端关闭 socket→Relay send_to 成功→回环 ICMP port unreachable→recv_from 10054→fatal→exit 3，summary 先写盘（§2.1/§2.2 时序 6 步） | 起 relay→注册 3 次×2 peer（脚本 :235-241）→baseline A→B seq=1（:245，B 收到→Check :254）→close peerB socket（:257）→A 发 seq=2 入死端口（:262）→轮询≤10s 等 relay 自死（:266-270）→写三文件（:281-283）+ Check exit==3（:284）+ Check stderr 含 'recv_from failed'（:285）→summary 断言组（:290-307）→peerA 无伪应答（:311-318） | **一致** |
| E-2 对端退出无流量→存活→stop-file exit 0 | 对端退出后 relay 不崩、无流量计数、优雅退出 exit 0 | close peerB2→sleep 1500ms→Check HasExited=False（:364）→stop-file（:365-366）→Check exit==0（:367）→fatal=none（:371）→reconciliation 含 '=='（:372） | **一致** |
| E-3 硬杀→Gone(HasExited) 判定 | 硬杀后进程消失判定 | KillInstead 分支（Finish-Relay :163-191 的 Kill 路径）→返回对象含 `Gone`（HasExited）→Check $fin3.Gone（:403）→杀后发帧 400ms 无回包（:415） | **一致** |
| E-4 通道 down→无伪应答 | 无 relay 进程时发帧无响应 | Check udp:34720 空闲（:426）→无 relay 发帧→400ms 无回包（:438） | **一致** |

### B.2 断言数 23（文档 §3） vs 脚本 Check 站点实算

- 脚本 Check 函数（:47-56）自增 `$script:Checks`，全部站点实算：**E-1 = 12**（含"无伪应答"1 条；bad envelope=0 与 unknown flags=0 合并为 1 条断言）、**E-2 = 6**、**E-3 = 3**、**E-4 = 2**，合计 **23**，与文档 §3 总数 23 一致。
- 文档 §3 的 E-1 清单把 bad=0 与 unknown=0 拆成两条、且未列"无伪应答"1 条 → **枚举与脚本站点不完全一一对应，但总数一致**（见 C 节 L4）。
- 判定：**23 条一致**。

### B.3 "无响应、无伪应答"断言方式的区分度（方法学）

- 脚本实现：`ReceiveTimeout = 400 ms`（E-1 :312、E-3 :413、E-4 :435）超时无回包即断言"无应答、无伪应答"。文档 §3 行 74 写作"1 s 内无回包"——**与脚本实际 400ms 不符**（见 C 节 L3）。
- 区分度分析：该断言使用 UDP ReceiveTimeout 超时 + Read-Envelope 仅识别 CVLR magic。场景内唯一潜在的发送者是被测 relay（E-1 的 peerA、E-3 杀后、E-4 无 relay），若 relay 违反"回包为零"策略，伪应答必为 CVLR 格式、会被 Receive 收到并解析 → **能区分"无应答"与"CVLR 伪应答"**；对"非 CVLR 的任意 UDP 流量"不区分（非 CVLR 垃圾包会被当作 null 丢弃，理论假阴性）。四场景均不触发 datapath 逻辑，伪应答仅可能来自回包策略 → 断言对该目标有效。**判定：方法学成立，附带上述范围限定。**

### B.4 E-1 summary 数值独立验证（证据 `E1/relay-summary.txt` + `E1/relay-log.txt` 逐条）

- datagrams **8** = 6 register（20B）+ 2 forward（28B）；bytes in **176** = 6×20 + 2×28 ✓
- registers **6**：relay-log 逐条 6 条 register（peer 101/202 各 3 次，08:35:35.111/.112/.166/.166/.227/.228）✓
- forward requests **2** / forwarded **2**：relay-log 逐条 2 条 forward（seq=1 08:35:35.410 → 127.0.0.1:57676，hash=c5620494bd8475c1；seq=2 08:35:35.806 → 127.0.0.1:57676，hash=c6c9f694beb606fd）✓
- forward bytes **16** = 2×8（payload 各 8B：`17320000ffff4fac` / `17320000ffff35ba`）✓
- identity **(6+2+0+0)=8**：6 reg + 2 fwd + 0 bad + 0 unknown ✓
- reconciliation **2==2**：registers 6 + forward requests 2 = 8 datagrams，两路对账一致 ✓
- fatal = 10054（`RECV ERROR: 远程主机强迫关闭了一个现有的连接。 (os error 10054)`），`E1-exit.txt` = `exitcode=3`，`E1-stderr.txt` = `[!] recv_from failed: 远程主机强迫关闭了一个现有的连接。 (os error 10054)`；`E1-console.txt` 尾部含完整 summary + `[*] wrote ...relay-log.txt and relay-summary.txt`（**summary 写盘发生在 exit 之前**，与源码 main.rs fatal 分支 `fs::write`(:574) 先于 `std::process::exit(3)`(:584-586) 一致）✓
- **判定：E-1 全部数值与日志逐条闭合。**（fatal 中文为 UTF-8 正确编码；用 ANSI/GBK 读显示乱码是读取器问题，非文件问题。）

### B.5 脚本 exit 判定（PASS/FAIL 与真实退出码）

- 脚本 :446 `$expectChecks=23`；裁定三支（:447-453）：Failures==0 且 Checks==23 → PASS；Failures==0 但 Checks≠23 → FAIL(clean but N of 23 ran)；否则 FAIL(M of N failed)。result.txt 写盘（:470）；**exit 0 仅当全 PASS，否则 exit 1**（:475）。头部注释（:35）声明：0=PASS / 1=断言失败 / 2=precheck 失败 / 3=setup 失败。
- 证据验证：`-163533/result.txt` = `PASS (23/23)`（895B，与脚本 sha256 BA002D94 行一致）；失败首跑 `-162043/result.txt` = `FAIL (1 of 23 failed)`（964B，脚本 sha256 01AB54C8… 为修复前版本）。
- **判定：一致。**

### B.6 边界声明诚实性（§1.2）与 README v1.18 Gate 登记

- §1.2（行 26-34）：原型无状态机、DEGRADED/RECONNECTING 与心跳时序（15s→DEGRADED、30s→RECONNECTING）为 **M0-B 目标**、本轮只验 4 条底线（计数如实 / 该不崩的存活 E-2 / 该 fatal 的真实 exit 3 E-1 / 不产伪应答 E-3+E-4）、回包策略全走"回包为零"（D4 兼容的 ≤1 个 20B 探针未参与，E-1~E-4 均不触发 datapath 逻辑）。
- 与判据设计 `F3-DIRECT-RELAY-DESIGN-20261114.md` §5.2 表 F3-E 行（"对端 Agent 中途退出/Relay 掉线 → DEGRADED→RECONNECTING 不踢人（§9）"）的承接方式：如实声明原型无状态机、不直接测"不踢人"，只验证可支撑 M0-B 的底层事实。**诚实，无夸大。**
- README v1.18 修订记录（行 1141-1151）：Gate 登记 = 设计 §5.2 F3-D 判据（"62056 忙轮询 ~1.6M/s 下 Hook 观测路径不丢帧 ｜ 分层计数对账"），F3-D 本轮只完成后半句，前半句归 M0-B 且"不得因 F3-D PASS 视为已勾掉"。F3E 文档 §8"Gate 登记保留——F3-E 不改变该登记"与 README 一致，**无冲突**。
- **判定：诚实、无冲突。**

### B.7 失败首跑披露（任务书第 7 项）

- 失败首跑 `-162043`（16:20:51 生成，result.txt 964B FAIL 1/23，failed check = "E-3 relay process gone after hard kill"）与采信目录并存。文档 §6 运行历史表（行 142-144）**点名披露**：
  - `-162043` FAIL 1/23：E-3 判定缺陷描述完整——Finish-Relay 强杀分支只返回 Exit=-1（try/catch 吞掉），断言 `[bool]($Exit -ne -1)` 恒 False；修复 = 返回对象加 `Gone`(HasExited) 字段、断言改 `$fin3.Gone`、expectChecks 18→23。
  - `-162129` 旧采信降历史（relay 已重建不可重放）；`-163533` 新采信。
- 审计方交叉验证：修复前脚本哈希 01AB54C8… ≠ 现行 BA002D94…，与"修复后重跑"叙事一致；`-162129`/`-163533` 计数器完全一致，两代运行行为稳定。
- **判定：披露完整、诚实。**

### B.8 证据完整性对照（与 F3-B 惯例）

- F3-B 采信 `-152821` 目录含 relay-console.txt 转录 relay stdout；F3-E 的 `E1/E2/E3-console.txt` 同为此类转录，惯例一致。
- F3-E 的 E-3/E-4"无响应、无伪应答"断言结果仅由 `result.txt` 聚合 "PASS (23/23)" 支撑，无驱动侧逐条 [PASS]/[FAIL] 转录。F3-B 亦无此转录——**两轮同惯例**，非 F3-E 特有缺口（见 C 节 L6，信息级）。

---

## C 节：缺陷清单（分级）

**阻断：无。高：无。**

### 中（3 项）

- **M1 — 文档 §2.1 独立探针声称无实物支撑**（`F3E-FAULT-INJECTION-20261114.md:50`）
  - 内容：文档称"该触发路径已先用独立探针（C# UdpClient 向 127.0.0.1:1 发送）实证可复现"。
  - 实测：树内唯一的探针实物是 `civlink/selftest/wsaprobe.cpp`（C++ WSARecvFrom WSA_IO_PENDING buffer-touch 探针，绑定 127.0.0.1:62057，与 C# UdpClient 死端口探针不是同一物）；全树检索 "UdpClient"/"127.0.0.1:1" 零命中；无探针运行日志/输出留存。该声明**不可复核**。
  - 理由：声称的独立探针无代码、无产物、无日志。缓解：E-1 本身已由三份证据（-162043/-162129/-163533）证明 10054 真实可复现，探针仅属冗余前置声明，不影响结论，但应删除或补证据。

- **M2 — §4 标题/数据仍标注旧采信 `-162129`，与 §0/§6/§7 采信 `-163533` 不一致**（`F3E-FAULT-INJECTION-20261114.md:76` 及 §4.1 blockquote）
  - 内容：§4 标题"实测结果（采信 `-162129`）"，§4.1 的 `run time : 08:21:31.540`、`listen ... for 1.2 s` 为 `-162129` 的值；采信 `-163533` 的对应值为 `08:35:35.807`、`1.1 s`（审计方实测）。
  - 理由：文档内部前后矛盾（§4 vs §0/§6/§7）。核心计数（datagrams 8 等）两目录相同，故结论不受影响，但属文档一致性缺陷，必改。

- **M3 — 审计期间对象漂移（元发现，非文档缺陷）**
  - 内容：审计窗口内 relay 源码/exe 重建、新增 `-163533` 证据目录、文档更新（10,718B/8D52987A→11,637B/3ED83453）。任务书声称值均为旧快照。
  - 理由：非项目方过错——文档 §0（行 15-16）已如实披露"relay 因 F4 `--version` 重建为 9E323F81；本轮为当前树重跑"及旧采信降历史。审计方两代均独立核对命中，结论不受影响。列为中仅因"审计对象在审计期间变更"这一事实需在报告中显式记录，避免以旧快照误判新状态。

### 低（7 项）

- **L1 — §7.2 注误列 `E2-stop.txt` 为 5B BOM 文件**（`F3E-FAULT-INJECTION-20261114.md:178`）
  - 注称"5 B 文件（`*stderr.txt`、`E2-stop.txt`）实测字节为 `EF BB BF 0D 0A`"；实测 `E2-stop.txt` = 6B = `73 74 6F 70 0D 0A`（"stop"+CRLF，ASCII 非 BOM），仅 `E2/E3-stderr.txt`（5B）为 BOM+CRLF。表格字节列（6B）本身正确，仅注错误。

- **L2 — §2.1 源码行号引用错误**（`F3E-FAULT-INJECTION-20261114.md:47`）
  - 引"main.rs:578-581 的 `if stats.fatal.is_some() { std::process::exit(3); }`"；实测该分支在 **main.rs:584-586**（:578-581 为 "[*] wrote" 输出块）。行号偏 6 行，逻辑正确。

- **L3 — §3 "1 s 内无回包"与脚本实际 400ms 不符**（`F3E-FAULT-INJECTION-20261114.md:74`）
  - 脚本三处 ReceiveTimeout 均为 400ms（:312/:413/:435）。文档"1 s"为描述性表述，应改"400 ms"。

- **L4 — §3 E-1 断言枚举与脚本站点不完全对应**（`F3E-FAULT-INJECTION-20261114.md:65-68`）
  - 文档拆 bad=0 与 unknown=0 两条、未列"无伪应答"1 条；脚本为合并 1 条 + 列"无伪应答"。总数 23 一致，逐条对应有偏差。

- **L5 — "17 文件"措辞含目录占位行**（`F3E-FAULT-INJECTION-20261114.md:156`）
  - §7.2 表 17 行 = 16 个文件哈希 + `E4/` 占位行（目录，无哈希）。"17 文件"应为"16 文件 + E4/ 目录"。

- **L6 — E-3/E-4 无应答断言证据仅聚合支撑**（证据惯例，信息级）
  - `result.txt` 聚合 "PASS (23/23)"，无驱动侧逐条 [PASS] 转录。与 F3-B 同惯例，非 F3E 特有，建议后续轮次补充。

- **L7 — §4.1 blockquote 裁剪行尾括号注释**（`F3E-FAULT-INJECTION-20261114.md:80-86` 附近，数值忠实）
  - unknown flags / no sender / oversize 行的括号注释（如"未收到任何 UDP 流量，计数器为零"）被裁剪，数值全部忠实。

---

## D 节：裁定

### **有条件通过**

无阻断、无高缺陷；任务书 7 项核查全部完成：①哈希两代全部命中（差异均系审计期间对象更新，文档 §0 已诚实披露）；②§2 四场景与脚本实现一致；③断言 23 条实算一致；④E-1 summary 数值与 relay-log 逐条闭合（8/6/2/2/8/2==2）；⑤exit 判定逻辑正确、证据佐证；⑥§1.2 边界声明诚实、与 README v1.18 Gate 登记无冲突；⑦失败首跑 -162043 由 §6 点名披露且修复描述与证据吻合。E5 承接项（fatal/exit 3 真实用例）**已落实**：以关闭对端 socket + 回环 ICMP port unreachable 制造 relay 自身 recv_from 10054 真实失败，exit=3 且 summary 先写盘。

### 必改清单（下次 revision 前完成）

1. **M2**：§4 标题与 §4.1 数据同步至采信 `-163533`（run time 08:35:35.807 / listen 1.1 s），或明确标注数据来源为 `-162129` 并解释与采信关系。
2. **M1**：删除 §2.1 的"C# UdpClient 独立探针"声称，或补充探针代码/运行日志；否则保留"10054 触发已由 E-1 三份证据实证"的表述。
3. **L1**：修正 §7.2 注——`E2-stop.txt` 为 6B ASCII "stop"+CRLF，非 BOM；BOM+CRLF 仅 `*stderr.txt`。
4. **L3**：§3 "1 s"改为"400 ms"（与脚本一致）。
5. **L2/L4/L5/L7**：行号 578-581→584-586；E-1 断言枚举与脚本站点对齐；"17 文件"改"16 文件+E4/ 目录"；§4.1 保留括号注释或注明裁剪。

上述必改项均为文档层缺陷，不改动任何结论数值与实现逻辑；核心审计结论（E-1 真实 fatal/exit 3、23 断言全过、计数闭合、边界诚实、失败披露完整）在现行代码与证据上成立。
