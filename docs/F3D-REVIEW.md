# F3-D（输入压力自检）独立审计报告

审计对象：`CivLink-M0A-audit/`（CivLink 原型，非发布）
本轮范围：**仅 F3-D**。F1 / F2 / F3-A / F3-B / F3-C 只作为对照背景，不作为本轮结论依据。
审计方式：**只读**。全程未运行 `run-f3*.ps1` / `civlink_ctl.exe`，未占用 62056 / 34718 / 34720 / 21348 / 21349，未修改任何被审文件；大文件用 `[IO.File]::ReadLines` 流式处理。唯一写入的文件是本文件。
判定基准：一切以磁盘字节与重算哈希为准，不采信文档的自我声明。

被审交付物（实测）：`docs/F3D-PRESSURE-20261114.md`，**15,421 字节 / 205 行 / SHA-256 `AFD821D9B9A6C733D20E81A37840094E33B99102984CA576CB7F4DD90FDAE169`**（含新增 §1.1）。
被审脚本（实测）：`civlink/run-f3d-pressure-selftest.ps1`，**22,888 字节 / 439 行 / SHA-256 `DF96FD69215535B15A2C7BDAC7CAD6EB75F54C68B5FB301741F5CD553D3AEC8F`**。
被审证据：`M0A/captures/F3D-pressure-selftest-20261114-151218/`，**17 个文件**（不是文档 §3 写的 18 个），无子目录。

---

## 裁定摘要

**裁定：有条件通过（Conditional Pass）。**

- **证据真实性：通过。** 17 个证据文件的字节数与 SHA-256 与文档 §6 表格**逐行吻合，零处不符**；3 个被审产物的指纹也吻合。frame-log / forward-log / relay-log / datapath-log 的行数自洽，并且**逐帧重算**（payload 的 SHA-256、Relay 的 FNV-1a、seq 单调性、两侧成对性）全部吻合，**未发现拼装或伪造迹象**。
- **设计与实现一致性：通过。** `agent/src/main.rs` 与 `relay/src/main.rs` 的计数自增点与文档 §3 的闭合等式**一一对应**，没有"等式在代码里没有自增点"的情形；62056 护栏在 Agent 侧四处、Relay 侧一处，均实测存在。
- **断言强度：不通过（需修正口径）。** 文档声称"运行时 22 条（9+10+3）"，实测为 **20 条 `Check`（Part 1 十条 + Part 2 十条）+ 6 个前置判定点**。并且 20 条里有 **13 条**是"闭合恒等式"或单侧不等式，在"什么都没转发"时同样成立；真正能挡住空转的只有 3 条方向性断言（406 / 407 / 408）。
- **表述边界：部分越界。** §7 的 5 条"证明"中，第 1 条与第 5 条缺对应证据；§3.1 的 6 条"闭合关系"里有 3 条是**同源恒真的算术恒等式**（在 `note_seq` 内由同一来源推导），不能作为"丢帧可见性"的独立证据。
- **覆盖度：文档已自认只覆盖一半判据（§1.1），这一点是加分项，也是本轮不能判"通过"的主因。** 设计 §5.2 的 F3-D 判据是"62056 忙轮询 ~1.6M/s 下 Hook 观测路径不丢帧｜分层计数对账 ==（Agent 事件驱动，不复刻忙轮询）"。本轮只覆盖后半句；前半句（Hook 观测路径在真实忙轮询下不丢帧）**完全未验证**，且不在 F3 授权范围内。

因此：**loopback 侧的证据链是干净且可复现的，但"22 条"这个门面数字是错的、若干"证明"缺证据、设计判据只覆盖一半。按最小转正条件修正后，可作为"分层计数闭合"这一半的有效证据被采信；另一半必须显式登记为未验证项。**

---

## 缺陷分级计数

| 级别 | 数量 | 编号 |
|---|---|---|
| 阻断 | 0 | — |
| 高 | 2 | H-1、H-2 |
| 中 | 4 | M-1、M-2、M-3、M-4 |
| 低 | 6 | L-1 ~ L-6 |
| 合计 | 12 | |

无阻断级缺陷：证据真实、无伪造、代码与文档的闭合关系对应、错误路径不产生假 PASS。

---

## A 证据真实性

### A.1 文件指纹逐行重算

对本轮 17 个证据文件逐个重算长度与 SHA-256，与 `docs/F3D-PRESSURE-20261114.md` §6 第二张表（第 146–162 行）逐行比对：

**结论：17 / 17 全部吻合，零处不符。** 未发现任何"文档写的数不是磁盘上的数"的情形。

三个被审产物的指纹同样吻合：

| 产物 | 字节 | SHA-256 前 16 位 | 结论 |
|---|---|---|---|
| `civlink/run-f3d-pressure-selftest.ps1` | 22,888 | `DF96FD69215535B1` | 吻合 |
| `civlink/civlink-agent.exe` | 382,976 | `A43248B9900920D3` | 吻合 |
| `civlink/relay/target/release/civlink-relay.exe` | 262,144 | `AE03327E417E89A3` | 吻合 |

### A.2 空文件与 5 字节文件的字节真相

任务书要求自行验证"5 字节与 0 字节文件"以及"空内容哈希是否确实是 `E3B0C442…`"。

- `agent-stop`、`relay-stop`：**0 字节**，SHA-256 = `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`，即标准空内容哈希。文档正确。
- `agent-console.txt`、`agent-stderr.txt`、`relay-stderr.txt`：**5 字节**，内容实测为 **`EF BB BF 0D 0A`**（UTF-8 BOM + CRLF），**不是空内容**。其 SHA-256 `F01A374E9C81E3…` 已独立复算吻合。

由此得到 **M-2**：文档第 164 行写"`agent-console.txt` 与 `agent-stderr.txt` 同为 5 字节空输出，故哈希相同（空内容的 SHA-256 即 `F01A374E…`）"，**归因错误**——空内容的哈希是 `E3B0C442…`（就在同一张表的第 154、161 行），`F01A374E…` 是"BOM+CRLF"的哈希。"两个文件哈希相同"这件事成立，但"它们是空输出"与"空内容哈希是 F01A374E"两句都与字节不符。这是全文唯一一处对字节事实的直白误述。

### A.3 日志规模与计数自洽（自己数）

全部用流式逐行计数，未整份读入内存：

| 文件 | 实测行数 | 构成 | 与 8,035 / 13,214 是否吻合 |
|---|---|---|---|
| `frame-log.txt` | **8,037** | 2 行 `#` 注释头 + 8,035 行 frame | 吻合（头部是 2 行注释，任务书的"1 行 header"是近似） |
| `forward-log.txt` | **16,071** | 1 行头 + 8,035 `forward` + 8,035 `peer-recv` | 吻合 |
| `relay-log.txt` | **13,223** | 1 行头 + 8 `register` + 13,214 `forward` | 吻合 |
| `datapath-log.txt` | **8,037** | 1 行头 + 8,035 `datapath src=` + 1 行 `datapath reply sent 20B … local probe only` | 吻合，且 D4 回包全日志只有 1 条 |

### A.4 数字化核对（summary 文件 vs 文档 §3.1 / §3.2）

- Agent 侧：`datagrams 8035`、`bytes 401750`、`received frames 8035 (processed 8035, rejected 0)`、`large datagrams 0`、`frames=8035 first=1 last=39998`、`gaps=6174 missing=31963 duplicates=0 out_of_order=0`、`payload bytes=64280`、`frames seen 8035`(datapath) / `8035`(forward)、`forwarded 8035`、`forward bytes 64280`、`skip not datapath 0` / `skip key table 0` / `skip discovery 0`、`reply sent 1` / `already_sent 8034`、`payloads recv 8035`、`56402`。**与文档 §3.1 表逐格一致。**
- Relay 侧：`datagrams 13222`、`bytes in 423008`、`registers 8`、`control frames 8`、`forward requests 13214`、`forwarded 13214`、`forward bytes 158568`、`no route/self drop/no sender/oversize = 0`、`bad envelope 0`、`unknown flags 0`、`fatal none`、`peers seen 2`。**与文档 §3.2 表逐格一致。**
- 派生数值：31,965 / 40,000 = **79.91%**（文档 79.91% ✔）；26,778 / 40,000 = **66.95%**（文档 66.95% ✔）；`ingestRate 45,979`、`rate 47,541` 与文档 §1 / §7 引用一致。

### A.5 拼装 / 伪造判定（逐帧重算，不抽样）

四类独立交叉核验，全部吻合：

1. **seq 序列跨文件一致**：`frame-log` 的 seq 序列与 `forward-log` 中 8,035 条 `forward` 的 seq 序列**逐索引完全一致（0 处不匹配）**；`forward` 侧 seq 严格单调，distinct = 8,035。
2. **载荷哈希自洽**：`forward-log` 每条 `sha256` 与同行 `payload` 字节的 SHA-256 **8,035 / 8,035 全中**；`peer-recv` 侧同样 8,035 / 8,035 全中；两侧按索引成对（sha、payload、序号）**0 处不符**。这说明"转发出去的字节"与"对端收到的字节"是同一条链，不是各自编造。
3. **独立重算 Agent 的 seq 统计**：只从 `frame-log` 的 seq 列重算，得 distinct 8,035、first 1、last 39,998、gaps 6,174、missing 31,963，且 `8035 + 31963 = 39998 = last - first + 1`——与 `summary.txt` 完全一致，说明 summary 的数字是从日志可复原的，不是另写的。
4. **Relay 载荷形状**：13,214 条 `forward` 的 seq 严格单调，payload 长度恒为 12，**逐条 FNV-1a 64 复算 13,214 / 13,214 全中**（初值 `0xcbf29ce484222325`、乘子 `0x100000001B3`，与 `relay/src/main.rs:61-68` 一致）；`head` 字段为 payload 前 8 字节的小写 hex，13,214 / 13,214 全中；payload 形状 `60..6b` 且第 0 字节 = `(seq-1) & 0xFF`，与驱动 `SendRelay` 的写法则一致。

时间窗也自洽：`frame-log` 07:12:20.637 → 07:12:20.834（0.197 s / 8,035 帧 ≈ 40,787 帧/s，与 45,979 同量级）；`relay-log` forward 段 07:12:23.123 → 07:12:23.337（0.214 s / 13,214 帧 ≈ 61,748 帧/s，与 47,541 同量级）。

**A 节结论：证据真实、自洽、可复原，无伪造或拼装迹象。**（唯一的 A 节缺陷是"18 个文件"这个数目，见 M-1。）

---

## B 断言强度

### B.1 精确统计：20 条运行时断言，不是 22 条

脚本 `run-f3d-pressure-selftest.ps1` 的 `Check` 函数定义在 **33–40 行**；`Check` 调用站点实测 **20 处**：

| 分段 | 行号 | 条数 |
|---|---|---|
| Part 1（Agent） | 208、228、271、273、275、277、280、282、291、294 | **10** |
| Part 2（Relay） | 371、392、395、398、399、401、406、407、408、409 | **10** |

前置判定点在 **48–60 行**：`foreach ($p in @($agentExe, $relayExe))`（2 个可执行文件存在）+ `foreach ($port in @(34718, 21348, 34720, 62056))`（4 个端口空闲）= **6 个判定点**，命中即 `exit 2`。

文档 §4（第 108–114 行）写"运行时 22 条"，构成为"Part 1（9 条）+ Part 2（10 条）+ 3 条前置"。三处都与实测不符：

- Part 1 实为 **10** 条，文档漏掉了 **208 行**那条 `agent does not bind UDP :62056 under load`——这是本测试里**唯一**一条直接检验"Agent 在压力下不碰游戏数据面端口"的断言，恰恰是最不该漏的一条。
- Part 2 的 10 条与实测**逐条对应**（无差异）。
- "3 条前置检查"实为 **6 个判定点**，而且文档括注的"34718/34720 空闲"也漏了 21348 与 62056 两个端口。

**20 + 6 与 22 + 3 不是同一个东西**：把 22 拆开是 20 条运行时断言加 2 条不知从哪来的"额外断言"。这就是 **H-1**。§6.1 的第 172、173 行两处"PASS（22 条）"继承了同一个错误数字。

### B.2 逐条判断：哪些是真断言，哪些空转也成立

按"若什么都没转发/什么都没收到，该断言是否仍成立"来分类：

| 断言（行号） | 类型 | 空转时是否成立 | 说明 |
|---|---|---|---|
| 208 `agent does not bind 62056` | 方向性 | 否（但它只证"没绑"，不证"在转发"） | 真断言，但仅 Agent 侧 |
| 228 / 371 `exited 0 under burst` | 方向性 | 否 | 真断言，挡住崩溃/挂死 |
| 271 `received == processed + rejected` | 闭合恒等式 | **是**（0 = 0 + 0） | 见 B.3，同源 |
| 273 `datagrams >= received` | 单侧不等式 | **是**（0 ≥ 0） | 只挡"凭空多出帧" |
| 275 `frames_seen == received` | 跨阶段等式 | **是**（0 = 0） | 两个量出自同一 decode 循环，独立性弱 |
| 277 `forwarded + skips + fail == frames_seen` | 闭合恒等式 | **是**（0 = 0） | 同源（`ForwardState` 内部） |
| 280 `peer <= forwarded` | 单侧不等式 | **是**（0 ≤ 0） | 空转必过 |
| 282 `frames + missing == last-first+1` | 算术恒等式 | **是**（0 + 0 = 0） | 见 B.3，同源恒真 |
| 291 `gaps/missing 同类` | 同源性质 | **是**（0 ↔ 0，0 ≤ 0） | 同源恒真 |
| 294 `datagrams <= agentSent` | 单侧不等式 | **是**（0 ≤ 40000） | 见 M-3，只证"没多收" |
| 392 `datagrams == regs + req + bad + unknown` | 闭合恒等式 | **是**（0 = 0） | 五个自增点覆盖全部分支，构造上必成立 |
| 395 `fwd + no_route + self + fail + no_sender == req` | 闭合恒等式 | **是**（0 = 0） | 同上 |
| 398 `fatal == none` | 方向性 | 否（读的是 summary 字段，能抓到 fatal） | 真断言 |
| 399 `datagrams <= sent + regs` | 单侧不等式 | **是** | 恒真性极强：环路内不可能多于发送数 |
| 401 `sink <= forwarded` | 单侧不等式 | **是**（0 ≤ 0） | 空转必过 |
| 406 `forwarded > 0` | **方向性** | **否** | 真正挡空转的三条之一 |
| 407 `no_sender == 0` | **方向性** | **否** | 真正挡空转的三条之一 |
| 408 `sink > 0` | **方向性** | **否** | 真正挡空转的三条之一 |
| 409 `(fwd + no_sender + bad) <= datagrams` | 单侧不等式 | **是**（0 ≤ 0） | 空转必过 |

汇总：20 条里，"什么都没转发"时仍成立的 **13 条**（271、273、275、277、280、282、291、294、392、395、399、401、409）；能区分"真的做了事"与"什么都没做"的只有 **7 条**（208、228、371、398、406、407、408）。其中真正针对"转发是否发生"的方向性断言只有 **3 条**（406 `forwarded > 0`、407 `no_sender == 0`、408 `sink > 0`），其余 4 条是进程存活与端口/致命错误检查。

文档 §5.2 第 3 条**已经如实自认**"`datagrams <= sent`、`sink <= forwarded`、`(fwd + no_sender + bad) <= datagrams` 在'什么都没转发'时全部成立"，并说明整改是新增三条方向性断言——这一段与代码一致，是本文件的加分项。问题在于 **§4 与 §7 又把口径拉回去了**（见 D 节）。

### B.3 计数器同源：三条等式是算术恒真，不是独立证据

- `frames + missing == last - first + 1`（282–285 行）：`note_seq`（`agent/src/main.rs:933-953`）用同一条 seq 流同时产出 `seq_gaps`、`seq_missing_frames`（`+= seq - expected`）、`first`、`last`、`duplicates`、`out_of_order`。`missing` 的定义就是"跨度内缺席的序号总数"，`last-first+1` 就是跨度本身，**等式是算术必然**。它无法发现"帧被正确编号却内容丢失"这类问题，也无法发现"计数器与载荷脱钩"。
- `received == processed + rejected`（271 行）：两者在 `main.rs:1312-1325` 同一 `match decode` 分支内二选一自增，构造上必成立。
- `gaps/missing 同类`（291 行）：同一次 `note_seq` 调用内产出，`gaps <= missing` 由"每个 gap 至少跳过 1 个序号"保证，恒真。

这三条作为**回归保护**（防止有人改坏分类）是有价值的，作为**"丢帧可见性"的证据**是无效的。文档 §3.1 把它们与 `forwarded + skips + fail == frames_seen` 并列成"闭合关系逐条成立"，没有区分"跨层对账"与"同源恒真"——这是 **H-2** 与 M-1 之外的实质问题。

### B.4 错误路径：不产生假 PASS

- 前置失败：48–53 行、54–60 行均 `exit 2`，且**不打印任何 `[PASS]` 行**——文档 §4 第 114 行的这句话是对的，实测成立。
- 中途失败：205（agent 未绑 34718）、222（agent 未退出）、231（无 summary.txt）、329（relay 未绑 34720）、364（relay 未退出）、374（无 relay-summary）全部走 `exit 1` / `exit 2`，且都在最后的 `F3D-PRESSURE-SELFTEST: PASS` 打印（434–439 行）**之前**，因此不会出现"exit 1 却打了 PASS"。
- 唯一可读性风险：中途 `exit` 会跳过后续断言，控制台上已经打印的 `[PASS]` 行仍留在屏幕里，读屏的人可能只看到一屏 PASS。这属于"部分 PASS 但整体未完成"，**不是假 PASS**，不计为缺陷，但建议在 `exit` 分支前追加一行 `F3D-PRESSURE-SELFTEST: ABORT`。

---

## C 设计与实现一致性

### C.1 `civlink/agent/src/main.rs`

- `is_discovery_request()`（**82–89 行**）确为 **AND 语义**：`frame.payload_len == DISCOVERY_MAGIC.len() && frame.payload.len() == DISCOVERY_MAGIC.len() && dst_port >= DISCOVERY_FIRST && dst_port <= DISCOVERY_LAST && frame.payload[..4] == DISCOVERY_MAGIC`。上方 78–81 行注释记录了 F3-A 第二轮审计的整改（旧版是 `flag != 0 || port in range`）。**与设计一致，无缺陷。**
- 发现帧跳过分支**确实计入 `frames_seen`**：**1393–1401 行**，`if is_discovery_request(&frame) { fw.stats.frames_seen += 1; fw.stats.skip_discovery += 1; }`；1394–1399 行注释明确写了"否则 discovery 帧会出现在 `skip_discovery` 却缺席 `frames_seen`，令等式不闭合"。**这是"补自增点"的正确做法，不是打补丁掩盖缺陷。**
- 62056 护栏**四处齐全**：`--port`（**1044–1051 行**）、`--forward-to`（**1096–1108 行**）、`--forward-listen`（**1112–1119 行**）、`ForwardListener::new` 的绑定点自检（**813–822 行**，注释自称 "second, unforgeable guard at the bind site itself"）。**四个入口都拒绝，无遗漏。**
- 收包计数点：`datagrams`（**1305**）、`large_datagrams`（**1308**，判据 `len > FRAME_HDR + MAX_PAYLOAD`，`FRAME_HDR = 42`、`MAX_PAYLOAD = 1280`）、`received`（**1312**）、`rejected`（**1317**）、`processed`（**1324**）。**四层单调包含关系在代码里成立。**
- Datapath 侧 `consider`（**565–600 行**）：`frames_seen`（587）→ `frames_on_datapath_port`（588–590）→ `reply_skipped_no_endpoint`（592–596）→ `reply_skipped_not_local`（597–600）。**三个 skip 自增点独立存在**，与 summary 的 `no_endpoint=0 not_local=0 already_sent=8034` 对应。
- Forward 侧 `consider`（**728–745 行**起）：`frames_seen`（729）→ `skip_not_datapath`（731–741）→ `skip_key_table_full`（743–745）→ `forwarded`（**759**）/ `forward_fail`（**779**）。**五路分类全有自增点。**

### C.2 `civlink/relay/src/main.rs`

- `--listen` 的 62056 护栏**在**：**212–219 行**，`if listen.port() == DATAPATH_PORT { eprintln!(...); std::process::exit(1); }`；注释 212–214 行记录了"Relay 此前完全没有这条护栏"的整改。`DATAPATH_PORT = 62056` 定义在 **37 行**。
- `forward_requests` **在 sender 解析之前自增**：**391 行** `stats.forward_requests += 1;`，紧接着 **392 行**才解析 sender；388–390 行注释写明"Every parsed DATA envelope is a forward request, counted before the sender is resolved"。**这是正确的口径**（否则 `no_sender` 的帧会从分母里消失，归因等式失去意义）。
- 未注册来源 **fail-closed 且计 `no_sender`**：**395 行** `stats.no_sender += 1`，日志明写 "unregistered source; envelope src_peer={} not trusted"，然后 `continue`。**成立。**
- `datagrams` 在 **oversize 分支仍自增**：**296–313 行**，`Err(ref e) if is_oversize_error(e) => { stats.datagrams += 1; stats.oversize += 1; stats.bad_envelope += 1; ... }`，注释 298–300 行解释了"否则身份等式会悄悄不再是等式"。正常路径在 **323–324 行**。**两个路径都有自增点。**
- `fatal` **导致 exit 3**：**580–582 行** `if stats.fatal.is_some() { std::process::exit(3); }`，且 summary 先写盘再退出。其他退出码：`--listen` 解析失败 1（182）、`--help` 0（202）、未知参数 1（206）、bind 失败 2（225）、summary 写失败 1（572）。**exit 3 成立。**

### C.3 文档 §3 的闭合等式 vs 代码自增点

| 文档 §3 的等式 | 代码自增点 | 是否一一对应 |
|---|---|---|
| `datagrams >= received`（§3.1） | 1305 / 1312 | 是 |
| `frames_seen == received`（§3.1） | 1312 vs 587+729+1400 | 是（每帧必进一路） |
| `forwarded + skip_not_dp + skip_discovery + skip_key_table + fail == frames_seen` | 729 / 731–741 / 1400 / 743–745 / 759 / 779 | 是，**五路全覆盖** |
| `forward bytes == peer payload bytes` | 759–760 与 relay listener 侧 | 是（但脚本不断言，见 L-6） |
| `frames + missing == last - first + 1` | 933–953 `note_seq` | 有自增点，但**同源**（B.3） |
| `gaps > 0 ⟺ missing > 0 且 gaps ≤ missing` | 945–946 | 有自增点，但**同源** |
| `datagrams == registers + forward_requests + bad + unknown`（§3.2） | 323/301 / 345 / 391 / 329 / 370 | 是，**五路全覆盖** |
| `forwarded + no_route + self + fail + no_sender == forward_requests`（§3.2） | 445–446 / 427 / 412 / 463 / 395 | 是，**五路全覆盖** |

**C 节结论：没有"等式在代码里没有对应自增点"的情形。设计与实现一致。**

---

## D 表述边界

### D.1 §7 五条"证明"逐条查证

| §7 条目 | 是否有对应证据 | 判定 |
|---|---|---|
| 1. 六条闭合关系全部成立，丢帧被如实计入 seq gaps / missing，**没有出现"计数闭合但实际丢包"** | 六条关系本身成立（A 节已验证），但其中 3 条同源恒真；"没有出现计数闭合但实际丢包"**无法被这些等式证伪**——恒真等式对任何输入都成立 | **过强**（H-2） |
| 2. Relay 身份等式与归因等式同时成立、`fatal` 保持 `none` | 等式成立（同源恒真），`fatal none` 有独立证据（`relay-summary.txt` 字段） | **前半过强，后半成立** |
| 3. 丢包由三层分别可见（sent / received / forwarded），三层单调递减 | Agent 侧 `forwarded == received == 8035`（**非严格**递减，语义层没有新增损失）；Relay 侧 40,000 > 13,222 > 13,214 成立 | **成立但需注明 Agent 侧是等号** |
| 4. D4 的"整轮最多 1 个 20B 回包"在 8,035 帧里仍恰好 1 次（`already_sent = 8,034`） | `datapath-log.txt` 中 `reply sent` 实测**只有 1 行**，`summary.txt` `reply sent : 1` | **成立** |
| 5. 62056 在所有压力场景下都没有被 Agent 或 Relay 绑定 | Agent 侧有运行中断言（208 行）；**Relay 侧没有任何运行中断言**——只有启动前 54–60 行的"62056 空闲"检查、脚本硬编码 `--listen 127.0.0.1:34720`、以及 `relay/src/main.rs:212-219` 的代码护栏 | **部分成立**（M-4） |

### D.2 §3.3 对 sink 的解释

**把"接收端限制"与"Relay 丢包"分开这件事做到了**：第 106 行明写"脚本对 sink 只做单侧不等式与 `sinkGot > 0`，从不把 sink 当计数权威……否则会把 sink 的 2,061 误读成'Relay 只转了两千个'"，§7-6 也重申"sink 的接收数字没有计量意义"。这一部分**达标**。

但同节第 104 行有两处越界：

- **"约 0.28 秒"没有出处。** 实测 `relay-log` 的 forward 段窗口是 0.214 s，`relay-summary` 的 `listen … for 1.1 s` 才是整轮时长；0.28 s 与两者都不吻合，来源不明。
- **"内核侧就丢了一大半"是未测量的机制归因。** 脚本记录的是 `sinkGot = 2,061`，没有记录 `SO_RCVBUF`、也没有内核丢包计数；"内核缓冲溢出"是合理推断但未被测量。作为解释可以，作为断言不行。

见 M-4 与 L-2。

### D.3 `frames seen` / 解码帧 / `datagrams` 用词

存在三套名字指两类对象，且有同值掩盖：

- `datagrams`（socket 收到的数据报）：`summary.txt` 里 `8035`，文档 §3.1 第 60 行写"数据报"——用词正确。
- `received frames`（解码成功的帧）：文档 §3.1 第 62 行写"**解码帧** 8,035（processed 8,035，rejected 0）"——"解码帧"对应 `received frames` 是对的。
- `frames seen`：**`summary.txt` 里有两处同名不同义的字段**——datapath 段是"outbound non-discovery frames"（`main.rs:587`），forward 段是"accepted non-discovery frames"（`main.rs:729`+`1400`）。文档 §3.1 第 66、67 行分别引用它们，都写"frames seen 8,035"；两次恰好同值，读者无法从文本判断这是两个计数器。**建议改写为"datapath 阶段入账帧 8,035 / forward 阶段入账帧 8,035"。**

本轮三个数恰好都是 8,035（`datagrams == received == frames_seen`），所以没有数值损害，但这是**用词风险**，在 `datagrams > received`（如历史运行 `-150153`：2,342 vs 2,342、`-151103`：1,831 vs 1,831 也相等，但正常压力下不保证）的场景下会误导。见 L-3。

### D.4 §1 "比稳态高 3–4 个数量级"

按文档自己给的基数，**这个说法成立**：§1 第 11 行明确把基线定为"F3-A 7 帧、F3-B 22 个数据报"，则 45,979 / 7 ≈ 6,568 倍 ≈ **3.8 个数量级**，47,541 / 22 ≈ 2,161 倍 ≈ **3.3 个数量级**，落在"3–4 个数量级"内。

风险在第 13 行的措辞："当输入速率比稳态高 3–4 个数量级时"——紧邻第 11 行引用的 1.6M/s，容易被读成"比 1.6M/s 高 3–4 个数量级"。实际 1.6M / 45,979 ≈ **34.8 倍，只有 1.5 个数量级**，方向还是反的（本轮**低于**真实客户端的忙轮询速率）。见 L-1。

### D.5 "22 条断言"与 PASS 的口径

文档 §4 标题"断言清单（运行时 22 条）"、§6.1 两处"PASS（22 条）"、以及 `script` 自身打印的 `F3D-PRESSURE-SELFTEST: PASS` **都不是按条数计的口径**——脚本只判 `$fail -eq 0`，PASS 行不含条数。因此"22 条"完全是事后在文档里数的，而数错了 2 条。**口径建议：PASS 行改为 `PASS (20 assertions, evidence: …)`，与脚本一致。** 见 H-1。

---

## E 缺陷清单与裁定

### 高

**H-1 断言总数与前置分类错误（文档 §4、§6.1）**
- 声称：运行时 22 条（Part 1 九条 + Part 2 十条 + 3 条前置）。
- 实测：**20 条** `Check`（Part 1 十条：208/228/271/273/275/277/280/282/291/294；Part 2 十条：371/392/395/398/399/401/406/407/408/409）+ **6 个前置判定点**（2 个可执行文件 + 4 个端口）。
- 具体错误：Part 1 漏掉 208 行 `agent does not bind UDP :62056 under load`（本测试唯一检验 Agent 不碰数据面端口的运行时断言）；"3 条前置"漏列 21348 与 62056 两个端口；§6.1 第 172、173 行两处"PASS（22 条）"继承同一错误。
- 影响：复核者按 §4 逐条勾选时会找不到 62056 那条断言，并会以为前置只做了 3 项检查。**这是本文件最容易被复现者发现的口径错误。**

**H-2 §3.1 / §7-1 把同源恒真等式当作"丢帧可见性"的证据**
- `frames + missing == last - first + 1` 由 `note_seq`（`agent/src/main.rs:933-953`）在同一来源内一次推导，是算术必然；`received == processed + rejected`、`gaps ≤ missing` 同理。
- §7-1 由此推出"没有出现'计数闭合但实际丢包'"——**恒真等式不能证伪任何输入**，这条推论不成立。
- 与 §5.2 第 3 条自认"全是不等式、什么都没做也绿"**内在矛盾**：一处承认断言弱，一处又把恒等式写成"证明"。
- 补充：本轮 31,963 个 missing 是**驱动侧单 socket 无节流造成的在途丢弃**（Agent 从未收到），不是 Agent 观测真实游戏帧时的丢帧，因此它连"Agent 的丢帧可见性"都只能部分证明。

### 中

**M-1 证据文件数：§3 写"18 个文件"，实测 17 个**（`Get-ChildItem -Force` 含隐藏项仍为 17，无子目录），§6 表格本身也只列 17 行。文档内部不一致。

**M-2 空内容哈希归因错误（第 164 行）**：`agent-console.txt` / `agent-stderr.txt` / `relay-stderr.txt` 的 5 字节实测为 `EF BB BF 0D 0A`（BOM+CRLF），**不是空输出**；空内容哈希是 `E3B0C442…`（同表第 154、161 行就在用）。"哈希相同"的结论对，归因错。

**M-3 `loss is reported` 断言命名过度（脚本 294 行）**：实际条件是 `datagrams <= agentSent`，只证明"收到的不多于发出的"。若 Agent 静默吞掉 3 万个数据报，该断言照样成立。命名成 "loss is reported" 会让读者以为"丢包被如实报出"已被断言覆盖。

**M-4 §7-5 "62056 未被 Agent 或 Relay 绑定"缺 Relay 侧证据**：脚本只在 Agent 侧做运行中断言（208 行），Relay 侧只依赖启动前端口空闲检查（54–60 行）、硬编码 `--listen 127.0.0.1:34720`、和 `relay/src/main.rs:212-219` 的代码护栏。结论大概率成立，但作为"证明"条目，证据强度不足以与其余四条并列。

### 低

**L-1 §1 第 13 行"3–4 个数量级"未标明基数**：按 §1 自己的基线（F3-A 7 帧 / F3-B 22 数据报）成立（3.8 / 3.3 个数量级）；但紧邻 1.6M/s 的引用，易被读成"比 1.6M/s 高 3–4 个数量级"——实际只有 1.5 个数量级且方向相反。建议显式写"相对于 F3-A/F3-B 的个位数帧率"。

**L-2 §3.3 第 104 行"约 0.28 秒"与"sink 丢包 = 内核缓冲溢出"**：0.28 s 与实测 `relay-log` forward 窗口 0.214 s、`listen … for 1.1 s` 都不吻合且无出处；内核缓冲归因未被测量（脚本无 `SO_RCVBUF` 记录、无内核丢包计数），应降级为推断。

**L-3 `frames seen` 一词双义未区分**：`summary.txt` 内 datapath 段与 forward 段各有一个 `frames seen`（代码里是两个计数器），文档 §3.1 第 66、67 行都以"frames seen 8,035"引用，本轮数值恰好相同掩盖了歧义。

**L-4 §5.2 第 5 条"Relay 的 `datagrams` 还含 5–8 次注册"**：实测 8 次 = sink 侧脚本注册 5 次（`run-f3d-pressure-selftest.ps1:342`）+ 驱动自注册 3 次（`:158-162`），是确定的 8，不是区间。建议写死为"5 + 3 = 8 次"。

**L-5 §6.1 运行历史漏列 `-150046`**：`M0A/captures` 下 F3D 目录实测 5 个（`-150046`、`-150153`、`-151103`、`-151144`、`-151218`），表格只列 4 个。`-150046` 数据：agentFrames 2,000、datagrams 1,974、forwarded 0；relay datagrams 2,005、registers 5、forward requests 0、bad envelope 2,000、forwarded 0、sinkGot 0（即"CVLR 头大端"缺陷那次，见 §5.3 第 6 条，正文提到 `bad = 2000` 却没有对应目录行）。

**L-6 脚本不断言 `forward bytes == peer payload bytes`**：§3.1 第 77 行把这条件列为"闭合关系逐条成立"，并注明"逐帧 sha256 也在 forward-log / peer-recv 两侧对得上"——本轮审计重算确认 **8,035 / 8,035 全中**（事实成立），但这条**不在 20 条运行时断言内**（脚本只 `Grab` 了 `forwarded : (\d+) (payload bytes`，从未比对字节数）。建议在 §4 注明"该项为事后核对，不在断言清单内"。

### 非缺陷（已写明，本轮只核对说清度）

1. **sink 不当计数权威**：§3.3、§7-6 两处写明，到位。仅机制归因见 L-2。
2. **`-150153` / `-151103` 两次"PASS 但空转"**：§6.1 点名作废，且 §5.2 第 3 条给了教训总结，到位。
3. **"不证明 Hook detour 成本 / 长时间稳定性 / 真实两机 / 丢包率即产品表现"**：§7"不证明"六条 + `boundary.txt` 双重声明，到位（`boundary.txt` 独立写明 `Scope: loopback only, no game process, no Hook, no second machine.`）。

### 覆盖差（决定裁定，不计为缺陷）

设计 §5.2 的 F3-D 判据含两半：**（a）62056 忙轮询 ~1.6M/s 下 Hook 观测路径不丢帧**；**（b）分层计数对账闭合**。本轮只覆盖 (b)。

文档 §1.1（第 17–33 行）用一张三行表把这一点写在了最前面，明确"F3-D 本轮只完成'分层计数在高压下闭合'这一半"，"另一半仍是未验证，不能因为本文件 PASS 而视为已勾掉"，并给了做那一半所需的四件套（真实客户端 + CivTrace v0.4.4 注入 + F2/S5 复现流程 + `civlink_ctl counters` 与 Agent `datagrams` 对账）。**这个披露是充分且主动的**，因此不计为缺陷。

但它决定了裁定上限：**F3-D 无法对设计判据给出完整覆盖，只能对 (b) 给出通过、对 (a) 给出"未验证"。** 这也是 F3 五个子项里唯一一个无法在本阶段闭合判据的子项。

### 裁定：**有条件通过**

理由三条：

1. **可信的部分是硬的**：证据 17/17 哈希吻合，四条日志逐帧可复原（seq 单调、sha256 两侧成对、FNV-1a 全中），没有伪造迹象；代码与文档的闭合等式一一对应；错误路径不产生假 PASS。
2. **表述部分不可直接采信**："22 条"是错的；三条闭合关系是同源恒真却被写成"丢帧可见性"的证据；§7 有两条"证明"缺证据。这些都是**文档层**问题，不影响底层证据，但会让 Gate 复核者高估覆盖。
3. **判据只覆盖一半**，且这一半的缺口不是靠改文档能补上的。

因此不给"通过"，也不判"不通过"（底层证据经得起复算）。

---

## 最小转正条件

**必要条件（不改则不能从"有条件通过"转"通过"）：**

1. **改断言口径**：§4 标题与正文由 22 条改为 **20 条**（Part 1 十条 + Part 2 十条）；把 208 行 `agent does not bind UDP :62056 under load` 补进 Part 1 清单；把"3 条前置"改为"**6 个前置判定点**（2 个可执行文件 + 34718 / 21348 / 34720 / 62056 四个端口）"；§6.1 第 172、173 行两处"PASS（22 条）"同步改为"PASS（20 条）"；脚本 PASS 行改为 `PASS (20 assertions, evidence: …)`。（对应 H-1）
2. **改第 164 行哈希归因**：写明三个 5 字节文件的内容是 `EF BB BF 0D 0A`（BOM+CRLF），空内容的 SHA-256 是 `E3B0C442…`（即 `agent-stop` / `relay-stop` 那两行），`F01A374E…` 是"BOM+CRLF"的哈希。（对应 M-2）
3. **给同源等式加标注并从"证明"里撤下**：在 §3.1 把 `frames + missing == last - first + 1`、`received == processed + rejected`、`gaps ≤ missing` 标为"同源恒真，仅作回归保护"；删改 §7-1 中"没有出现'计数闭合但实际丢包'"这一句（恒真等式不能支持它）。（对应 H-2）
4. **§7-5 降级为实测口径**：改为"Agent 侧有运行中断言；Relay 侧由硬编码 `--listen 127.0.0.1:34720` 与 `relay/src/main.rs:212-219` 的 `--listen` 62056 护栏保证，无运行中断言"。（对应 M-4）
5. **§3 证据文件数 18 改 17**；§6.1 表补 `-150046` 行（agentFrames 2,000、relay bad envelope 2,000、forwarded 0）。（对应 M-1、L-5）
6. **§3.3 第 104 行**："约 0.28 秒"改为实测口径（`relay-log` forward 窗口 0.21 s，或 `listen … for 1.1 s`）；"内核侧就丢了一大半"降级为"推断，未测量 `SO_RCVBUF` 与内核丢包计数"。（对应 L-2）
7. **§1 第 13 行给"3–4 个数量级"补基数**："相对于 F3-A（7 帧）/ F3-B（22 个数据报）的个位数帧率"；并注明本轮 45,979 / 47,541 帧/s **仍低于**真实客户端 ~1.6M/s，差距约 1.5 个数量级。（对应 L-1）
8. **覆盖差登记进 Gate 文档**：在 Gate A / M0-B 的状态表里显式登记——"F3-D 覆盖：分层计数闭合 = 已验证；62056 忙轮询 ~1.6M/s 下 Hook 观测路径不丢帧 = **未验证**，留 M0-B 真机项"。**只改 F3-D 自己的文档不够**：如果 Gate 表只写"F3-D PASS"，§1.1 的免责声明会被绕过。（对应裁定 3）

**建议（非阻塞，做了更强）：**

9. `loss is reported` 改名为 `datagrams <= sent (nothing was invented)`，或补一条真正能证明"丢包被报出"的断言（例如把 `sent - datagrams` 与 `missing_frames` 两类损失分别落到显式字段并交叉核对）。（对应 M-3）
10. 把 §3.1 第 77 行的"逐帧 sha256 对得上"升级为脚本内的独立断言（跨 forward-log / peer-recv 按索引比对 sha 与字节数），这样"载荷完整性"就从"事后核对"变成"运行时保护"。这条一旦加上，能实质弥补 H-2 指出的独立证据缺口。（对应 L-6）
11. 统一 `frames seen` 的命名（datapath 阶段 / forward 阶段分开叫），避免同值掩盖歧义。（对应 L-3）
12. 中途 `exit` 前追加 `F3D-PRESSURE-SELFTEST: ABORT`，避免"半屏 PASS + 退出码 1"的可读性风险。

---

审计范围声明：本报告只对上述 17 个证据文件、1 个脚本、1 份记录、2 个 Rust 源文件负责。未运行任何会占用端口或改文件的命令；未评估 F3-D 之外的任何子项；不对"联机可用"作任何背书。
