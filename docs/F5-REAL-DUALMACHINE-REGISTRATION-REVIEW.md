# F5 真实双机核验登记 — 独立审计报告

- **审计对象**：2026-11-16 16:58:23「真实双机核验」（B 机＝真实第二台物理机 + 真实 Civ6 客户端口述可见）
- **审计性质**：只读独立审计。**未修改任何被审计文件**；全部数值由审计人用 PowerShell/.NET 重算，不引用文档声称值。
- **审计时间**：2026-11-16
- **行数口径**：`[System.IO.File]::ReadAllLines()` 行数 = LF 计数（F5 文档与 HANDOVER 为纯 LF，CRLF=0，故行数=LF 数）；README 为全 CRLF（LF=1306 且 CRLF=1306），行数=CRLF 数=1306。
- **字节口径**：`(Get-Item).Length`；哈希 `Get-FileHash -Algorithm SHA256`。
- **编码口径**：BOM 检测取首 3 字节是否 EF BB BF；控制字符扫描 ASCII 0x00–0x1F（排除 CR/LF）中 TAB(0x09)/VT(0x0B)/FF(0x0C) 及其余 C0。
- **结论摘要**：**有条件通过**。三文件身份、A/B 两侧计数、22 页逐字节对账、MANIFEST 24/24 全部实测命中，无一处数值虚报；唯「A 侧 exit code 0」与「agent PID 37828」两项断言在证据目录内**无任何工件支撑**（本轮 A 侧为手工起进程，未走会写 exit.txt 的编排脚本），另有一处流程描述与实际执行不符。属可局部修补登记文本的缺陷，不触及本轮结论的实证基础。

---

## A. 身份（哈希 / 字节数 / 行数 / 编码）

| # | 文件 | 声称 | 实测 | 判定 |
|---|---|---|---|---|
| A1 | `CivLink-M0A-audit\docs\F5-LAN-SIMULATED-HOST-20261115.md` | 15,600B / `965271E8…51EF75` / 228 行 / 无 BOM / 无控制字符 | 15,600B / `965271E8277A039EFE71CCDF0E9B70A9EBFDDEF6F159DE9DEC17185C3B51EF75` / LF=228、CRLF=0、CR=0 / BOM=False / TAB=0、VT=0、FF=0、其余 C0=0、NUL=0 / 末字节 0x0A | **PASS** |
| A2 | `CivLink-M0A-audit\README.md` | 110,913B / `F478FB7C…54D0B` / 1306 行 / 版本行 1.24 / 含 v1.24 块 / 无「版本：1.23」残留 | 110,913B / `F478FB7CAC351D6873EB22D44A43067CD0DE94B64DA4DA0CAD185CF43F754D0B` / LF=1306、CRLF=1306 / BOM=False / TAB/VT/FF/其余C0=0 | **PASS** |
| A3 | `CivLink-M0A-audit\docs\CODEX-HANDOVER-M0A.md` | 35,776B / `187AE67F…F81E` / 141 行 / 第 16 项含真实双机信息 | 35,776B / `187AE67FD74522D9B420E5ED0CDFC246B7DA7C2F7FD7F2DB11E9805B0F74F81E` / LF=141、CRLF=0 / BOM=False / TAB/VT/FF/其余C0=0 | **PASS** |

余下三项：

- **A4 §3.6 存在且无未完成占位**：PASS。标题位于 `F5-LAN-SIMULATED-HOST-20261115.md:129`「### 3.6 真实双机核验（B 侧真实物理机 + 真实客户端可见）— PASS」，正文 L131–168 完整。对全文（228 行）扫描 `待.*追加 / 待补 / TODO / TBD / placeholder / 占位 / 【待 / FIXME` **零命中**——不存在「待 17:22:52 窗口到期后追加」之类的未完成占位。文件 mtime `2026-11-16 17:23:51`，晚于 summary 写盘时刻 17:22:53，与「到期后补写登记」的时间顺序自洽。
- **A5 README 版本行**：PASS。全文「版本：」仅 1 处（L3，1.24）；「1.23」仅出现 2 处，均为正常历史引用（L1249「详见 v1.23 修订记录」、L1262「v1.23 修订记录」标题），**无「版本：1.23」残留**。v1.24 修订记录块位于 L1278–1306，①–⑦ 七条齐全。
- **A6 HANDOVER 第 16 项**：PASS。L123 含「★真实双机核验 PASS（2026-11-16 16:58:23，真实第二台物理机 + 真实客户端可见）」整段，含应答源、22/22 逐字节、口述确认、A 侧计数、通道无关性、证据路径、当前哈希 228 行。

---

## B. 数字一致性（重点）

### B1 A 侧 `summary.txt` 独立复算

文件：`M0A\captures\F5-dualmachine-20261116-realmachine\summary.txt`，实测 **2,687B / `B6D00F8E1E776B16175C7CCB8C373CE7A3649747326381E7EA2EA09579B2DD33**（与声称一致）。

| 字段 | 声称 | 实测原文 | 判定 |
|---|---|---|---|
| requests seen | 384 | `requests seen   : 384` | PASS |
| replied sockets | 4 | `replied sockets : 4` | PASS |
| pages sent | 88 | `pages sent      : 88 (== replied * 22)` | PASS |
| 恒等式 | 88 == 4×22 | 4×22=88，成立 | PASS |
| send fail | 0 | `send fail       : 0` | PASS |
| no endpoint | 0 | `no endpoint     : 0 (datagram with source port 0)` | PASS |
| max reached | 0 | `max reached     : 0` | PASS |
| bind fail | 0 port(s) | `bind fail       : 0 port(s)` | PASS |
| listen ip | 0.0.0.0 on 62900..62999 | `listen ip       : 0.0.0.0 on 62900..62999 (Agent owns the discovery ports; ...)` | PASS |
| room | CivLink-Test-Room-2222 | `room            : 'CivLink-Test-Room-2222'` | PASS |
| 窗口时长 | ≈1800s | `listen window   : 127.0.0.1:34718 for 1800.2 s` | PASS |
| CVLH2 datagrams | 0 | `datagrams       : 0`、`received frames : 0 (processed 0, rejected 0)`、`sessions : 0` | PASS |

**补充核验（审计人自算，非文档声称）**：
- 窗口 1800.2s 与 `start-cmd.txt` 的 `--listen-seconds 1800` 一致；`summary.txt` 文件 mtime = `2026-11-16 17:22:53`，而 16:52:52 + 1800.2s = 17:22:52.2 —— **mtime 落在自然到期点**，可独立佐证「窗口自然到期并写盘」。此点比文档自身的措辞更强，建议登记时直接引用 mtime 佐证（见 E 节 D1）。
- `run time : 09:22:53.177` 是**主机 uptime 口径**（与 60+ 份历史 agent summary 横比：同日单调递增，与各自窗口长度无关，如 `F5-singlehost-20261115-1235`=04:33:56、`F4-beta-20261114-174214`=09:46:20、`F1-live-20261114-092257`=01:26:03）。**不是本轮窗口时长**，故不与「1800.2s 窗口」矛盾，不得据此项判为不符。
- `reply budget : 20 socket(s)` 与 `max reached=0` 自洽（replied 4 ≤ budget 20）。

### B2 B 侧 `result.txt` 独立复算

文件：`...\b-side-probe-out-real\result.txt`，实测 **576B / `416D8F60A7A100F311128DFE9F5AC1198D7588603D3B641157A8056E1AAE6762`**。

| 声称 | 实测原文 | 判定 |
|---|---|---|
| `F5-B-PROBE: PASS (4 checks)` | 首行 `F5-B-PROBE: PASS (4 checks)` | PASS |
| time 2026-11-16 16:58:23 | `time       : 2026-11-16 16:58:23` | PASS |
| reply 22 pages / 24288 bytes | `reply      : 22 pages / 24288 bytes, source 192.168.31.60:62900` | PASS |
| source 192.168.31.60:62900 | 同上 | PASS |
| local port 54321 | `local port : 54321` | PASS |
| burst 100 magic | `burst sent : 100 magic datagrams to 255.255.255.255:62900..62999` | PASS |
| 临时防火墙规则加/删 | `firewall   : allow rule added for UDP 54321 ; rule removed` | PASS |
| 边界句 | 含 `Simulated-host evidence only: NOT a two-real-hosts multiplayer result, NOT E2-B/E3.` | PASS |

**交叉佐证**：B 机回传副本 `C:\Users\dd\Desktop\civlink-f5-kit\civlink-f5-b-probe-out\civlink-f5-b-probe-out\result.txt` 与证据目录内 `result.txt` **字节完全相同**（同 576B / 同 `416D8F60…` / 同 mtime 16:58:22），排除事后改写。

**机械自洽性**：24288 = 22 × 1104 ✓；`4 checks` 与正文四项（sent/pages/head/room）对应 ✓；16:58:23 落在 A 侧 16:52:52–17:22:52 窗口之内 ✓。

### B3 逐字节对账

| 对比 | 结果 |
|---|---|
| B 侧 `probe-reply-01..22.bin` vs A 侧 `lan-page-01..22.bin` | **22/22 完全一致**，每页 1104B，22 个 sha256 逐对相等，mismatch=0 → PASS |
| A 侧 `lan-page-01..22.bin` vs kit `fixture-reply-set\reply-01..22.bin` | **每页 21 字节差异，全轮合计 462B**（22×21）→ PASS |

差异偏移集合（审计人自算，并集）：`{24, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45}` —— 共 **21 个偏移，全部落在 24..45**，最小值 24、最大值 45，越界 0 处，与文档「每页仅 21 字节差异，全部落在 24..45（房名匿名化）」**完全吻合**。

原因已实证，非推测：`lan-page-01` 偏移 24..45 的 22 字节为 ASCII `CivLink-Test-Room-2222`（房名恰 22 字节）；kit `reply-01` 同区间为 `dingzihan2022?????????`。**偏移 25 两处同为字符 `i`，故 22 字节中只有 21 字节不同**——这正是「21 字节而非 22 字节」差异的来源。`lan-fixture-manifest.txt` 写「anonymized at offset 24..46」为半开区间记法，与 24..45 同义，不构成矛盾。

### B4 `MANIFEST-sha256.txt` 逐条重算

- 清单文件实测 **2,483B / `A754E4179A9CF9825AEE55B45F642CF002A95CB950607CF0ADEE16D630BEFABE`**（与文档声称一致）。
- 审计人对清单所列 24 条逐条重算哈希**并**核对字节数：**24/24 全对，BAD=0**，无一条「清单写 A、实际为 B」。
- 清单头声明 `count: 24` / `total_bytes: 24909`，实测 24909 = 22×1104（24,288）+ 45（`firewall-rule.txt`）+ 576（`result.txt`）✓，且**不含清单自身**（口径明确）。
- 目录实际文件数：`b-side-probe-out-real\` 共 **25 个文件 / 27,392B** = 24,909 + 2,483 ✓。

### B5 README v1.24 块 / HANDOVER 第 16 项引用的数值

| 引用点 | 引用值 | 实测 | 判定 |
|---|---|---|---|
| README L1288 `summary.txt` B6D00F8E… | 2,687B | 2,687B / `B6D00F8E…2DD33` | PASS |
| README L1286 / L1298 oral AE39FA9A… | 1,671B | 1,671B / `AE39FA9AA4637D01763A965C8E70D4411365EF8234C2FC3593103EAF14944D30` | PASS |
| README L1298 MANIFEST A754E417… | — | `A754E417…BEFABE` / 2,483B | PASS |
| README L1299 `frame-log.txt` 9BD9FD25… | — | 132B / `9BD9FD25BB4FC1DB5DB81E68655A1F2F7CB57D3A9CDE65DFB3FC3EF13BD7B0B9` | PASS |
| README L1301 / HANDOVER L123 文档哈希 965271E8…、228 行 | — | `965271E8…51EF75` / 228 行 | PASS |
| README L1289–1291 384/4/88/全 0 | — | 同 B1 | PASS |
| F5 文档 §3.6 L163 result.txt 416D8F60…/576B | — | 一致 | PASS |
| F5 文档 §4 表 exe `194E6E8A…D23DA92`/404,992B | — | 404,992B / `194E6E8A00080B0F05AF14D8754F38CACE818CFC0FE667BB1E0375400D23DA92` | PASS |
| F5 文档 §4 表 `run-f5-b-probe.ps1` FF4DDF3F…57D0 | — | 7,244B / `FF4DDF3FE71639E6204A853B8F36FB810158802C1F321670B398FBFAFDFE57D0`（末 4 位 57D0 ✓） | PASS |
| F5 文档 §4 表 `run-f5-dualmachine-a.ps1` D909D16F…B444B | — | 7,926B / `D909D16F034F006B167285C33FFB83DCFBC411EBE9582B27E3A7CF14A22B444B` | PASS |
| F5 文档 §4 表 `run-f5-lan-selftest.ps1` 80C0935D…B41E | — | 8,842B / `80C0935DE04A2EA7F8A596B9E9B4B045C2EFFB8C671FDEF610FF9AF279BAB41E` | PASS |
| F5 文档 §4 表 `PC-B-操作单.md` FF6679E9…E96 | — | 3,187B / `FF6679E94BD20A1CD11AEB8D391F749CA3BC23F28D95F03E1B3DEC3B9BA56E96` | PASS |

### B6 F5 文档 §6 附带数值（代码行数）

- §6 L203 声称：`civlink\agent\src\main.rs`「编译后 **2559 行**」。
- 实测：**2562 行**（bytes=107,672，LF=2562，尾随换行 1 个，`ReadAllLines`=2562），文件 mtime `2026-11-14 19:18:52`，release exe mtime `2026-11-14 19:19:52`（404,992B / `194E6E8A…`，与文档一致）。
- 结论：**偏差 3 行**。因 main.rs 自 11-14 构建后未曾改动（mtime 早于文档两次修订），这不是「登记后代码又变了」的时滞问题，而是**行数计数口径错误**；且该句与「fmt/test 19 通过」并列，属代码清单附带信息，不影响登记结论（见 D13）。

**B 节判定：PASS（附 D13 一例行数偏差）**。登记相关数值与实测**零偏差**（含哈希全部 64 位）；唯 §6 的 `main.rs` 行数声称 2559 与实测 2562 不符（3 行），属代码清单附带信息，不触及本轮登记结论。另有两处口径性瑕疵（不改变数值正确性），见 G 节 D5、D6。

---

## C. 引用链与版本演进

C1 **当前哈希引用一致性**：PASS。全库仅两处引用 `965271E8…51EF75`——`README.md:1301` 与 `CODEX-HANDOVER-M0A.md:123`，均指向当前版本（228 行），**无第三处冲突值**，无任何位置把旧哈希当当前值使用。

C2 **历史哈希语义**：PASS（附低缺陷 D7）。
- `1EFC4751…784FE`（§3.5 后 181 行）：在 HANDOVER L123 标注最完整——「（历史版本，已由 §3.6 版本取代；当前版本见本项末尾 965271E8…，228 行）」，**语义无歧义**。
- `E860914F…010C8`（§3.4 后 155 行）：出现在「2026-11-15 补 §3.4 … 后 sha256 E860914F…，155 行；」的顺列叙述中，**未单独加「历史」标签**；但整句处于「补 §3.4 → 补 §3.5 → 当前 §3.6」的时序链内，且紧随其后即标明当前值，误读风险低。
- `6BB383F6`、`4AA1FF4E`：仅见于 HANDOVER L123「此前 F5-REGISTRATION-REVIEW（v1.21 登记）审计对象版本为 6BB383F6，REVIEW-2 审计对象版本为 4AA1FF4E」，靠「此前 / 审计对象版本」限定为非当前；**无显式「历史」字样**。README 中二者完全不出现，无扩散。
- 历史行数（155 / 181）**无法复算**：项目内不存在 F5 文档的旧版本副本（全库仅当前一份 + 两份 REVIEW 文件），属不可复算的历史声称（信息级，不判缺陷）。
- F5 文档自身**不含自引用哈希表**（§6 仅列 exe 与脚本哈希），故不存在「文档写自己的哈希」这类循环引用冲突。

**C 节判定：PASS**，无「旧哈希被当作当前值」的歧义；建议按 D7 统一加标签。

---

## D. 边界口径（不得越界）

逐项核查结论：**PASS**，未发现任何越界宣称。

D1 **本轮定位**：三文件一律表述为「模拟房主 → 真实客户端**跨机发现链路**」+「客户端可见（口述确认）」。F5 文档 §3.6 L165–168、§5 L192–199、README L1302–1306、HANDOVER L123 末段四处边界段落文字一致、无冲突。

D2 **禁止性宣称扫描**（`双人真实对局已通过 / E2-B 完成 / Gate A 已批准 / M0-B 已验收` 等）：全库 **0 命中**。反向证据充分——实际存在的同类词组**全部是否定式**：
- `README.md:307`「不能称作 Relay RTT 已验证或 H6/E2-B 已通过」
- `README.md:533`「不允许的表述：「联机已验证」「Relay 可用」「M0-B 通过」」
- `README.md:791`「不得标"双人真实联机已通过"」
- `README.md:978`「**非** Gate A 通过，M0-B 仍冻结」
- `HANDOVER:51`「Gate A 通过后才正式启动 M0-B」
- `HANDOVER:67`「F1/F2 原型不等于正式 M0-B 验收或 Gate B 放行」
- `HANDOVER:121`「不得标"双人真实联机已通过"」

D3 **口述证据的等级标注**：PASS，且标注强度高于最低要求。F5 文档 L148–152 明写「**真实客户端可见（用户口述确认）**」「等级=**口述确认**（无截图、无客户端抓包、无游戏日志），与 §3.4 同级；机械探测证据独立成立，不依赖本条」。`real-client-visibility-oral.txt`（1,671B）自身另含 4 段边界声明与「记录人：DSH agent（记录用户原话，未做技术验证）」的免责标注，并原文引用用户话「B房间，可以看到这个房间不需要再次探测了」。「与 §3.4 同级」的类比经核对**准确**：§3.4 L89 亦为「用户两次口述确认看到房间」。

D4 **E2-A/E2-B/E3 与 Gate 的未勾状态**：PASS。F5 文档 L166「不勾 E2-A/E2-B/E3」、L198「不得据此勾掉 E2-A/E2-B/E3；不移动 Gate A/B；Gate A 未批准，M0-B 冻结」；README L1305–1306 同义；HANDOVER L123 末段同义。三处均在，未被本轮 PASS 冲掉。

D5 **D4 约束的如实交代**：PASS。文档 L167–168 说明「模拟房主有意不响应"检索创建人信息"（F5 D4 约束），故 B 机点入房间会停在检索页，不进入对局，属预期」，避免把「看得到房间」读成「进得去对局」。

D6 **summary 内建边界句**：PASS。`summary.txt` 自身 notes 含「It is a SIMULATED HOST seen by a real client - evidence for the cross-machine discovery path, NOT a two-real-hosts multiplayer result and NOT E2-B/E3.」——边界声明随证据文件一起流转，不依赖外部文档。

---

## E. 证据存在性

| # | 被引用对象 | 存在性 | 字节 | 判定 |
|---|---|---|---|---|
| E1 | `realmachine\summary.txt` | 存在 | 2,687B ✓ | PASS（本轮应有，**已补齐 §3.5 的缺口**） |
| E2 | `b-side-probe-out-real\probe-reply-01..22.bin` | 22/22 存在 | 各 1,104B ✓ | PASS |
| E3 | `b-side-probe-out-real\result.txt` | 存在 | 576B ✓ | PASS |
| E4 | `b-side-probe-out-real\firewall-rule.txt` | 存在 | 45B ✓ | PASS |
| E5 | `b-side-probe-out-real\MANIFEST-sha256.txt` | 存在 | 2,483B ✓ | PASS（24/24 校验通过） |
| E6 | `real-client-visibility-oral.txt` | 存在 | 1,671B ✓ | PASS |
| E7 | `frame-log.txt` | 存在 | 132B ✓ | PASS（但 0 数据行，见 D10） |
| E8 | `lan-page-01..22.bin` | 22/22 存在 | 各 1,104B ✓ | PASS |
| E9 | `lan-fixture-manifest.txt` | 存在 | 237B ✓ | PASS |
| E10 | `start-cmd.txt` | 存在 | 248B ✓ | PASS（含 UTF-8 BOM，内容为本轮命令行） |

**E 节判定：FAIL（高）**——存在两项「被文档当作实测值陈述、但证据目录内无对应工件」的断言：

**D1（高）`exit code 0` 无工件。**
- 声称位置：`F5-LAN-SIMULATED-HOST-20261115.md:153`「1800.2s 窗口自然到期、**exit code 0**、summary 正常写盘」；`README.md:1288`「1800.2s 窗口自然到期 **exit 0**」；`HANDOVER:123`「窗口 1800.2s 自然到期 **exit 0**」。
- 实测：本轮目录**无 `exit.txt`**；对 `C:\Users\dd\Desktop` 全量按 mtime 16:00–18:00 检索 `exit.txt / agent-pid.txt / *console* / *stderr* / agent-report*`，**零命中**。
- 关键复核：`summary.txt` 全文**不含 exit code 字段**（已逐行核对，`exit|stderr|pid` 零匹配），故 exit 0 **无法由 summary 反推**。
- 成因已定位（非证据造假，而是流程偏离）：`run-f5-dualmachine-a.ps1:104` 会写 `exit.txt`（`[IO.File]::WriteAllText((Join-Path $OutRoot 'exit.txt'), "$agentExit")`），而本轮 `start-cmd.txt` 是一行**手工命令**（`--listen-seconds 1800 --out-dir … --sim-lan-listen 0.0.0.0 --simulate … --sim-room-name CivLink-Test-Room-2222`），**未走该编排脚本**，因此 exit.txt 与其报告文件均未产生。
- 影响评估：**不推翻结论**。「自然到期 + summary 正常写盘」有独立强证据（summary mtime 17:22:53 = 16:52:52+1800.2s，且 summary 是 agent 走到收尾路径才写的文件）；未证实的只是**进程退出码**这一附加属性。
- 对照：上一轮 §3.5 目录有 `agent-pid.txt`、`exit.txt`（40B）、`STOP-agent`，但**无 summary.txt**（Test-Path=False，已确认）——两轮各缺一半，本轮属「补了 summary、退了 exit/pid」。

**D2（高）`agent PID 37828` 无工件。**
- 声称位置：`F5-LAN-SIMULATED-HOST-20261115.md:132`「（agent PID 37828，…）」；`real-client-visibility-oral.txt` 场景段亦写 PID 37828。
- 实测：无 `agent-pid.txt`、无 `Get-Process` 输出留存。PID 37828 **仅出现在 F5 文档与 oral.txt 两个同源文本中**，构成「文档 ↔ 口述记录」互证，而非独立证据。
- 影响评估：PID 属过程性标识，对本轮结论无实质影响；但它被写成实测值且无法复算，违反本项目「每项数值须有可复算工件」的既有纪律。

**E 节其他说明（信息级，不判缺陷）**：
- `frame-log.txt` 仅两行表头、**0 数据行**，与 `datagrams=0 / received frames=0` 一致；它只能支持「本轮无 CVLH2 帧经过」这一负面事实，不能作为帧级正面证据。文档未把它当正面证据使用（仅 README L1299 列入证据清单），可接受。
- A 侧无 firewall 工件；文档 L145「规则已随 exe 路径放行」为该括号内的溯源说明，本轮未单独取证（见 D8）。
- `summary.txt` 只打印 `bind fail : 0 port(s)`，未打印成功绑定总数；「100/100 端口绑定」（F5 L134、README L1291）系由 bind fail=0 推断（见 D9）。

---

## F. 通道无关性声明

**F 节判定：PASS（附限定条件）**。声明「agent 在 0.0.0.0 绑定全部 100 个发现端口、按观测源地址单播回发，故不依赖 InterfaceMetric」在**本轮证据范围内成立**，且**未被过度外推到数据面**；但有一处方向性措辞错误（D4）与一处适用域需限定（D12）。

**F1 机制层（读码核实）**：
- `civlink\agent\src\main.rs:544-556`：`for port in DISCOVERY_FIRST..=DISCOVERY_LAST { UdpSocket::bind(SocketAddr::from((ip, port))) }` —— 0.0.0.0 时**每端口一个全接口 socket**，故广播从 WLAN 或 Radmin 任一接口到达都落入同一 socket。不依赖「哪块网卡抢到广播出口」这一原生广播选路问题，成立。
- `main.rs:636-674`：`consider(from)` 以 `(ip.to_be(), src_port.to_be())` 去重，`reply_sock.send_to(page, from)` **单播回发到观测源 sockaddr**（非广播、非固定目标）。故「按观测到的源地址单播回发」**有代码支撑**，不是文档措辞。
- `main.rs:1873-1877`：summary 的 `reply source` 由 `args.sim_lan_listen` + `SIM_REPLY_PORT` 格式化而来，打印的是 **listen ip（绑定地址）**，因此本轮 `reply source : 0.0.0.0:62900` 是绑定地址而非实际出口——文档 §3.2 L60 已明写此点（「agent 自身 summary 记录 reply source : 0.0.0.0:62900（绑定地址，非实际出口）」），口径自洽。

**F2 结果层（实测环境值，只读读取，未修改）**：
- A 机当前：Radmin VPN ifIndex 22 / `26.74.126.98` / **InterfaceMetric=1**；WLAN ifIndex 10 / `192.168.31.60` / **InterfaceMetric=45**；以太网 `192.168.2.4` metric 25；ZeroTier `192.168.191.3` metric 1045。
- 因此文档 L141「Radmin metric=1（全机最低）」**正确**（1 确为全机最小 → 优先级最高）。
- B 侧 `result.txt` 记录应答源 `192.168.31.60:62900` —— 即 metric=1 的 Radmin 接口（26.74.126.98）**没有**参与，实际出口是 metric=45 的 WLAN。这是「发现面不依赖 metric」的**直接结果级证据**。
- 备份工件 `CivLink-M0A-audit\scripts\network-env\pc-a-radmin-metric-backup.txt` 记 `InterfaceMetricRegValue=1`、`AutomaticMetric=Disabled`；`pc-a-radmin-metric-fix-result.txt` 记「OK metric=200 2026-11-14 18:59:04」（历史一次改为 200，当前实测已回到 1）——与「metric 反复但 F5 均可通」的叙事相容。

**F3 过度外推检查**：**未发现越界**。
- 文档 §5 L196 明确排除「62056 数据面」，HANDOVER L123 亦列「不证明 … 62056 数据面」→ **没有**任何一处暗示「数据面/62056 也不依赖 metric」。数据面反向约束（`main.rs:681` 注释「Agent never binds :62056, never sets SO_REUSEADDR」）本身也与该外推不相容。
- 「不依赖手工防火墙放行」有**行为级支持**：A 侧本窗口收到 384 个入站 magic，说明入站 UDP 已实际可达（无论规则来源）；B 侧 54321 规则由 probe 自加自删（`firewall-rule.txt` 45B 佐证），未依赖 A 侧人工放行。括号内「规则已随 exe 路径放行」的**规则来源**本轮无工件（D8），属溯源细节而非结论依赖。

**F4 需限定的适用域（D12，信息级）**：B 与 A 同处 `192.168.31.0/24`，属**同网段 on-link 路由**——该拓扑下 metric 本就不参与选路。故本轮证据严格支持的命题是「**本拓扑下 F5 发现面不依赖 InterfaceMetric**」；不宜外推为「任意跨网段 / 中继 / 多宿主拓扑亦不依赖」。文档未做该外推（§3.6 仅就本机 WLAN 场景陈述），建议在 §3.6 L141–145 补半句限定「（本拓扑为同网段 on-link，metric 本不参与选路；跨网段场景未验证）」，以免后续被当作普遍结论引用。

---

## G. 缺陷清单（按严重度）

| 编号 | 等级 | 位置 | 缺陷 | 实测依据 | 影响 |
|---|---|---|---|---|---|
| D1 | **高** | F5 文档 L153；README L1288；HANDOVER L123 | 「exit code 0 / exit 0」被陈述为实测值，但无 exit.txt、无 console/stderr、summary 亦无该字段 | Desktop 全量 16:00–18:00 检索零命中；本轮为手工起进程（`start-cmd.txt`），未走 `run-f5-dualmachine-a.ps1`（该脚本 L104 才写 exit.txt） | 不可复算断言；不推翻结论（自然到期另有 mtime 强证据） |
| D2 | **高** | F5 文档 L132；`real-client-visibility-oral.txt` | 「agent PID 37828」无 pid 工件 | 无 `agent-pid.txt`；PID 仅见于两份同源文本 | 过程性标识不可复算 |
| D3 | **中** | F5 文档 §4 L183–185 | 流程描述为「`run-f5-dualmachine-a.ps1 -WaitSeconds 180` → 起 agent（240s 窗口）」，与实际执行（手工命令行、1800s 窗口）不符 | `start-cmd.txt` 实为 `--listen-seconds 1800 …` 手工命令；才导致 D1/D2 的工件缺失 | 读者会误以为有 exit.txt/pid 工件，是 D1/D2 的根因 |
| D4 | **低** | F5 文档 L141 | 「A 机 Radmin metric=1（全机最低，**> WLAN 45**）」方向写反，自相矛盾 | 实测 metric 1 < 45（1 优先）；同义句在 README L1293 写作「全机最低」是对的 | 易被误读为 metric 1 高于 45 |
| D5 | **低** | F5 文档 L162–164；README L1297；HANDOVER L123 | 「`b-side-probe-out-real\` 24 文件」与目录实际 25 个文件不符；且 §3.5 与 §3.6 同名「24 文件」含义不同（前者实际 24，后者 24 受清单覆盖 + 清单自身） | 实测该目录 25 文件 / 27,392B；清单自身声明 count:24 且不含自身 | 计数口径歧义，非造假 |
| D6 | **低** | F5 文档 L158–159；README L1289 | 「384 = 100×3 + 84」「末轮未满 100 包」被表述为事实 | 证据仅给总数 384；分解方式不唯一（4×96 亦可整除），且「哪一轮未满」不可由总数判定 | 应标为推断 |
| D7 | **低** | HANDOVER L123 | `E860914F`（155 行）、`6BB383F6`、`4AA1FF4E` 未获显式「（历史）」标签 | 仅 `1EFC4751` 有「历史版本，已由 §3.6 版本取代」 | 语义靠上下文推断，误读风险低 |
| D8 | 信息 | F5 文档 L145 | 「规则已随 exe 路径放行」无 A 侧防火墙工件 | 本轮 A 侧无 firewall 文件；但 384 入站请求证明入站可达 | 仅溯源细节 |
| D9 | 信息 | F5 文档 L134；README L1291 | 「100/100 端口绑定」系由 `bind fail=0` 推断，summary 未打印绑定总数 | summary 仅 `listen ip : 0.0.0.0 on 62900..62999` + `bind fail : 0 port(s)` | 推断合理，建议措辞区分 |
| D10 | 信息 | README L1299 | `frame-log.txt` 被列入证据清单，但文件仅表头、0 数据行 | 实测 132B、0 数据行 | 只支持负面事实 |
| D11 | 信息 | F5 文档 L226–228 | §7 审计状态段止于 §3.4 登记审计，未提 §3.6（无占位符） | 全文无 TODO/待补 | 本轮即首次审计，非缺陷 |
| D12 | 信息 | F5 文档 L141–145 | 「不依赖 InterfaceMetric」未限定拓扑（同网段 on-link） | B/A 同在 192.168.31.0/24；on-link 下 metric 不参与选路 | 建议补适用域，防外推 |
| D13 | **低** | F5 文档 §6 L203 | `main.rs`「编译后 2559 行」与实测 2562 行不符 | main.rs bytes=107,672 / LF=2562 / mtime 2026-11-14 19:18:52（早于文档修订，非时滞） | 唯一一处数值偏差，属代码清单附带项 |

**数值失配汇总：1 处（D13）。** 与登记结论直接相关的全部对比——3 个文件哈希/字节/行数、5 个证据文件哈希/字节、11 个文档引用值、22 页逐字节、24 条清单哈希——**全部一致**；唯一偏差为 F5 文档 §6 代码清单中的 `main.rs` 行数（2559 vs 2562，差 3 行），不参与登记结论。其余缺陷均为**口径 / 溯源 / 措辞**问题。

---

## H. 必改项清单

**必改（MUST，完成后方可视为登记闭环）**

1. **[D1-高] 处理 exit code 0**。二选一：
   (a) 补证：下一次运行改用 `run-f5-dualmachine-a.ps1`（其 L104 自动写 `exit.txt`），或在手工启动后追加 `WriteAllText(...,"$((Get-Process -Id $p.Id).ExitCode)")` 落盘；或
   (b) 改写：F5 文档 L153、README L1288、HANDOVER L123 统一改为「1800.2s 窗口自然到期（`summary.txt` mtime 17:22:53 = 16:52:52+1800.2s 佐证）、summary 正常写盘；**本轮未留存 exit.txt，进程退出码未取证**」。
2. **[D2-高] 处理 PID 37828**。补 `agent-pid.txt` 或从 F5 文档 L132 与 `real-client-visibility-oral.txt` 删除 PID，改为「手工起 agent（命令行见 `start-cmd.txt`）」。
3. **[D3-中] 修正 §4 流程描述**：在 §4 L183–185 或 §3.6 增一句「§3.6 本轮 A 侧为手工命令行启动（`start-cmd.txt`，`--listen-seconds 1800`），未使用 `run-f5-dualmachine-a.ps1`，故 `b-side-probe-out-real` 同级目录下**无 exit.txt / agent-pid.txt**」，使读者不再预期这两件工件。
4. **[D4-低] 修正 L141 措辞**：改为「A 机 Radmin metric=1（全机最低，**1 < WLAN 的 45，即优先级高于 WLAN**）」。
5. **[D5-低] 统一文件计数口径**：三处统一写为「`b-side-probe-out-real\` 共 **25 个文件**（22 页 + result.txt + firewall-rule.txt + MANIFEST-sha256.txt），其中 MANIFEST 覆盖 24 项」，并同步修正 §3.5「24 文件」与 §3.6 的语义差异说明。
6. **[D6-低] 标注推断**：`384 = 100×3 + 84` 后加「（**推断**：证据仅给总数 384；分解方式不唯一）」。
7. **[D7-低] 补历史标签**：HANDOVER L123 为 `E860914F`、`6BB383F6`、`4AA1FF4E` 各加「（历史）」或「（已被取代）」。
8. **[D13-低] 修正代码行数**：§6 L203 改为「2562 行」（实测 bytes=107,672 / LF=2562，与 mtime 2026-11-14 19:18:52 的源码一致），或删去行数、只保留 exe 哈希。

**建议（SHOULD）**

9. **[D8-信息]** L145 括号改为「（入站已实测可达：本窗口收到 384 个入站 magic；A 侧防火墙规则来源未单独取证）」。
10. **[D9-信息]** 「100/100 端口绑定」改为「100 次 bind 零失败（`bind fail=0`），即 100/100 端口绑定成功」。
11. **[D12-信息]** §3.6 L141–145 增半句：「本拓扑 A/B 同处 192.168.31.0/24（on-link），metric 本不参与选路；跨网段/中继拓扑未验证」。

**无需整改**：D10（frame-log 0 行，与 datagrams=0 一致，未被当正面证据）、D11（§7 未提 §3.6，本轮审计即补上闭环）。

---

## I. 最终裁定

### 裁定：**有条件通过**

**通过的依据（全部经独立重算，非引用）**

1. **登记身份真实且精确**：三文件字节 / 哈希 / 行数 / 编码与声称**逐项零偏差**；§3.6 完整存在，无未完成占位，时间顺序（窗口 17:22:52 到期 → 文档 17:23:51 更新）自洽。
2. **核心证据链闭合且可复算**：B 侧 `result.txt`（PASS 4 checks / 16:58:23 / 22 页 24,288B / 源 192.168.31.60:62900 / 本地 54321 / burst 100）+ A 侧 `summary.txt`（384 / 4 / 88，88==4×22，全 0，0.0.0.0 on 62900..62999，1800.2s）**两侧独立、互相咬合**；`summary.txt` mtime 落在自然到期点，`result.txt` 与 B 机回传副本字节相同（不可事后改写）。
3. **逐字节对账成立**：B 侧 22 页 vs A 侧 22 页 **22/22 全等**；vs kit fixture **每页 21 字节（合计 462B）差异，偏移全落 24..45**，且「21 而非 22」的原因已被实证（偏移 25 同为 `i`）——文档描述与实际差异结构**精确吻合**。
4. **哈希清单可信**：`MANIFEST-sha256.txt` 24/24 逐条重算通过，`total_bytes 24909` 与目录构成可精确还原。
5. **边界纪律未被破坏**：不存在「双人真实对局已通过 / E2-B 完成 / Gate A 已批准 / M0-B 已验收」；口述证据被如实降级标注（无截图/无抓包/无日志），「不勾 E2-A/E2-B/E3、不移动 Gate」三处齐备；D4 约束（停在检索页）有交代。**这是本轮最值得肯定之处**——比 §3.5 更弱的口述证据被更明确地标为口述级。
6. **通道无关性有机制 + 结果双重支撑**：读码确认「每端口全接口 bind + 按观测源单播回发」；结果层 Radmin metric=1（26.74.126.98）被绕过、实际出口为 WLAN 192.168.31.60。且**未外推到 62056 数据面**。
7. **补上了 §3.5 的实质缺口**：上轮「无 summary.txt、只能以 B 侧为准」，本轮首次拿到 A 侧完整跨机计数（384/4/88），登记质量确有提升。

**附条件（必改项 1–7 完成后转「通过」）**

- 两项**高**级缺陷（D1 exit code 0、D2 PID 37828）均为「无工件的断言」，根因是 A 侧手工启动、未走会写 `exit.txt` 的编排脚本（D3 中）。它们不推翻本轮结论——「自然到期 + summary 写盘」另有 mtime 强证据——但违反本项目「数值必有可复算工件」的登记纪律，且与 §3.5 的工件配置形成倒挂（上轮有 exit.txt 无 summary，本轮有 summary 无 exit.txt）。**任选补证或改写，二者皆可**。
- 其余为中/低/信息级口径与措辞问题（D4–D12），不影响裁定成立，但应在同一修订中一并清理，避免下轮审计重复记账。

**不予通过的情形（未触发）**：若出现下列任一，应改判「不通过」——本轮 22 页与 A 侧不完全一致；summary/result 数值与声称存在偏差；清单哈希有任一条不符；出现「双人对局已通过 / E2-B 完成 / Gate 已批准」类越界表述；口述证据被升格为机械证据。**上述五项均未发生。**

---

## 附. 审计复算要点（可复现）

- 身份：`Get-Item.Length`、`Get-FileHash -Algorithm SHA256`、`[IO.File]::ReadAllLines()` 计数、首 3 字节判 BOM、逐字节扫 0x00–0x1F。
- 证据：`[IO.File]::ReadAllBytes()` 后 `for` 比对 22×1104 页；差异偏移用逐字节 XOR 非零集合并集（21 个偏移 / 462B）。
- 清单：解析 `MANIFEST-sha256.txt` 的 `name  size  sha256` 三段式，逐条重算并与行内容比对，统计 BAD 计数（结果 0）。
- 环境：`Get-NetIPInterface -AddressFamily IPv4` 只读读取各接口 metric（**未做任何修改**）。
- 代码：`civlink\agent\src\main.rs` L510–675（LAN 模拟房主收/去重/单播回发）、L1865–1880（summary 打印来源）。
- 注：`run-f5-dualmachine-a.ps1:104` 为「exit.txt 由编排脚本产出」的直接依据，是 D1/D3 根因定位的关键读码点。

---

*本报告仅就 2026-11-16 16:58:23 真实双机核验登记作独立核验；不构成对 civlink 功能、Gate A/B 或 M0-B 的任何验收意见。*
