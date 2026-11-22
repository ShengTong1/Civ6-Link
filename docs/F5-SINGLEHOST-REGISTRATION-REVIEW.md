# F5 单机真实客户端验证登记审计报告（F5-SINGLEHOST-REGISTRATION-REVIEW）

- **审计时间**：2026-11-15（Asia/Shanghai）
- **审计角色**：civlink 项目独立审计官（子代理）
- **审计方式**：只读审计。PowerShell 独立重算（SHA256 / 字节数 / BOM / 控制字符），独立核对磁盘目录与文件存在性，独立全文比对三文件关键块，独立逐字节比对 22 页 lan-page 与 fixture reply；除本报告外未修改任何被审文件。
- **工作目录**：`C:\Users\dd\Desktop\injciv6-v0.3.3`
- **审计对象**：F5 文档 §3.4/§7（v1.22 时代）、README 版本行与 v1.22 修订记录块、证据目录 `M0A\captures\F5-singlehost-20261115-1235\`（30 文件）
- **审计链**：本报告为 F5 收尾登记审计（对应 §7"本小节待收尾登记审计"）；前序为 F5-LAN-SIMULATED-HOST-REVIEW.md（有条件通过→必改 4 项）→ REVIEW-2（通过）→ F5-REGISTRATION-REVIEW.md（v1.21 时代登记，当时 F5 文档 7,829B/6BB383F6…，README v1.21/104,697B）→ 本次（F5 文档已扩至 9,867B/13EA3887… 增加 §3.4，README v1.22/106,384B）。

---

## 0. 身份实测（独立重算，不引用声称值）

| 文件 | 声称 sha256 | 实测 sha256 | 声称字节 | 实测字节 | BOM | tab/vt/ff | 结论 |
|---|---|---|---|---|---|---|---|
| `CivLink-M0A-audit\docs\F5-LAN-SIMULATED-HOST-20261115.md` | `13EA3887BA1A053BF072E3395B6BEEA325655956EF64A5FD531FB30A44B5A96D` | **完全命中** | 9,867 | 9,867 | 无 | 0/0/0 | 命中 |
| `CivLink-M0A-audit\README.md` | `9D7BAC6EA48D5A8A24A3FB556449A83FD92931B3E049637C12F5C9B33942B714` | **完全命中** | 106,384 | 106,384 | 无 | 0/0/0 | 命中 |
| `M0A\captures\F5-singlehost-20261115-1235\summary.txt` | `A6892BB026E4A0D124D27616ED81BA4D09CCD080B2B27DE44D0D538B1DACE397` | **完全命中** | 2,685 | 2,685 | — | — | 命中 |
| `...\agent-console.txt` | `C2E6EC3E…` | `C2E6EC3EAFE459861448125B18B90D195C91BA7EA7D7725BD42936F52304159E` | 3,070 | 3,070 | — | — | 命中（前缀） |
| `...\agent-stderr.txt` | 0B | 0B（sha256=E3B0C4… 空文件） | 0 | 0 | — | — | 命中 |
| `...\exit.txt` | `AF96489E…` | `AF96489E52BEF678F3FA7B0A0C23A4BC445386413F3107498E8A982EE10BA3D6` | 10 | 10 | — | — | 命中（前缀） |
| 证据目录 | 30 文件 30,461B | **30 文件 30,461B**（22×1104=24,288 + 9 小文件=6,173，合计 30,461） | — | — | — | — | 命中 |

---

## A. 身份 — **PASS（6/6）**

| 检查项 | 结果 |
|---|---|
| 两文档 sha256/字节独立重算命中声称值 | **PASS**（见 §0 表，逐字节相同） |
| 两文档无 BOM | **PASS**（首字节均非 EF BB BF） |
| 两文档无控制字符 tab/vt/ff | **PASS**（实测 0/0/0） |
| README 版本行 = 1.22 | **PASS**（L3 `版本：**1.22**（2026-11-15）`） |
| README 无「版本：**1.21**」残留 | **PASS**（grep `版本：1.21` 0 命中；文中"1.21"仅出现在历史块标题"v1.21 修订记录"及他文引用，属历史记录非版本行） |
| F5 文档行数 | **PASS**（实测 155 行，与 README v1.22 ①"155 行"一致） |

---

## B. §3.4 内容与证据一致性 — **PASS（全部子项）**

| 检查项 | 声称 | 独立实测 | 结果 |
|---|---|---|---|
| summary.txt | sha256 A6892BB0… / 2,685B | 完全命中（见 §0） | **PASS** |
| requests seen | 100 | summary L17 `requests seen : 100` | **PASS** |
| replied sockets | 1 | L18 `replied sockets : 1` | **PASS** |
| pages sent | 22（== replied×22） | L19 `pages sent : 22 (== replied * 22)` | **PASS** |
| send fail / no endpoint / max reached / bind fail | 全 0 | L20–23 各 0 | **PASS** |
| exit code | 0 | exit.txt 10B 内容 `exitcode=0`；agent-stderr.txt 0B（空） | **PASS** |
| 干净收尾（STOP 触发） | STOP 触发 | STOP-agent 6B `stop\r\n` 存在；agent-console L2 `stop file … found - finishing the window cleanly`；console 末尾 `[*] wrote …frame-log.txt and …summary.txt` | **PASS** |
| lan-page-01..22.bin | 22×1104B | 实测 22 文件各 1104B | **PASS** |
| 与 fixture reply 逐字节一致（除房名偏移 24..45） | MISMATCH=0（除偏移 24..45） | 22 页逐字节比对：差异仅索引 24,26..45（每页 21 字节），**全部落在声明区间 [24,45] 内**；偏移 25 及区间外零差异 | **PASS** |
| 房名字段 | CivLink-Test-Room-2222 | page[24..45] ASCII `CivLink-Test-Room-2222`（22 字符）；fixture reply[24..45] 为原文房名 `dingzihan2022…`（已匿名化替换），与 lan-fixture-manifest `anonymized at offset 24..46`（半开区间 [24,46)）一致 | **PASS** |
| head magic | 59 60 69 9B（§3.2/3.3 口径） | page[0..3] = 59 60 69 9B | **PASS**（支撑） |
| agent-console / agent-stderr / exit.txt | 3,070B/C2E6EC3E…、0B、10B/AF96489E… | 全部命中（见 §0） | **PASS** |
| STOP-agent / frame-log / lan-fixture-manifest / agent-pid | 存在 | STOP-agent 6B、frame-log.txt 132B（仅表头无帧行，与观测口 datagrams=0 一致）、lan-fixture-manifest.txt 263B（fixture 目录/房名/监听口径与 §3.4 一致）、agent-pid.txt 7B `15692`——均存在，哈希见下 | **PASS** |
| 证据目录身份 | 30 文件 30,461B，pid 15692 | 30 文件 30,461B；agent-pid.txt=15692 | **PASS** |

补充哈希（目录内自洽，§3.4 未声称这三者哈希，无参照冲突）：STOP-agent=A0B28CDF92E250A1A93294D91144A0F893D27197D56B39991CC421768794005F；frame-log.txt=9BD9FD25BB4FC1DB5DB81E68655A1F2F7CB57D3A9CDE65DFB3FC3EF13BD7B0B9；lan-fixture-manifest.txt=A85905BFF50F615E951F9466A3BDF5195415F5BDDC7D651C0DCC169A0730AAB2；agent-pid.txt=8DE1703853FDC7FA0E51B1678A8C4C8446E2AF9960951C99B3D40067EB50857E。

---

## C. 文档叙述真实性 — **PASS（附 2 项信息级建议）**

| 检查项 | 结果 |
|---|---|
| 口述确认如实标注 | **PASS**：§3.4 原文 `用户两次口述确认看到房间（"刷新了 / 打开了,刷新之后有"）`——房间可见性明确归因于用户口述（引述原话），未写成机械断言；§3.4 的 PASS 由 agent 侧机械计数（独立复核 100/1/22/全 0）+ 用户口述可见性共同支撑。信息建议①：标题 `PASS（真实 Civ6 大厅看到模拟房间）` 可加"（口述确认）"限定词，避免与 §3.1–3.3 纯机械 PASS 并排时被误读为同等证据等级（不阻塞）。 |
| 启动方式教训两条如实 | **PASS**：§3.4 注如实描述两条教训（直接重定向流且会话结束 → summary 未写盘；嵌套 Start-Job 会话结束 job 被清理 → 孤儿进程）与正解（持久后台 job + 持有输出流 + WaitForExit 后落盘 console/stderr/exit）；本窗口证据（STOP 触发、console 完整、summary/frame-log 落盘）与"正解已落实"一致。历史失败过程无法独立复核，但表述为教训而非 PASS 依据，如实。 |
| 单机≠双机关系表述 | **PASS**：§3.4 末条 `B 机核验包（§4）仍保留，用于最终双机确认；本小节为**单机**真实客户端路径证据（模拟房主 → 真实客户端，同一台机器）`——单机验证与双机核验包区分恰当，未声称跨机完成。 |

信息观察②（非缺陷）：summary/console 中 `run time : 04:33:56.780` 实为 `wallclock_stamp()`（main.rs:1159–1168，UTC HH:MM:SS.mmm 墙钟戳），即 04:33:56 UTC = 12:33:56 UTC+8，与证据目录时间戳 12:35 吻合；字段名"run time"易被误读为运行时长，实际窗口时长由 `listen window … for 33.7 s` 给出。建议后续版本字段更名或加注释（不影响本次登记，无数据不一致）。

---

## D. README v1.22 块 — **PASS（全部一致，无越界）**

| 检查项 | 结果 |
|---|---|
| ①F5 单机验证条目（L1240–1245）与 F5 文档 §3.4 一致 | **PASS**：方案 C/m19535、`--sim-lan-listen 0.0.0.0`、600s 窗口、fixture-reply-set、房名 CivLink-Test-Room-2222、两次口述确认、summary 计数 100/1/22/失败全 0/exit 0、证据目录 30 文件、summary sha256 A6892BB0…、F5 文档补 §3.4（13EA3887BA…/155 行，实测命中）、B 机核验包保留——逐项与 F5 文档一致。 |
| ②M0B 准备材料条目（L1246–1251）与 M0B-PREP-DLL-STABILITY-20261115.md 一致 | **PASS**：pid 12420、60s×5 采样、sent 100→500、cvlh2 ok==try、失败计数 0、62056 忙轮询 3,884,931≈3.88M、内存 12:52 后 3.70–3.71GB、性质声明"非验收、不勾 Gate A/B"——与 M0B-PREP 文档 §2/§4/§0 逐项一致；证据目录 `M0A\captures\M0B-prep-stability-20261115\` 存在（inject-hook.txt 1,547B、samples.csv 520B、另含 inject.txt）。 |
| ③GUI 条目（L1252–1254） | **PASS**：`civlink_ctl_gui.cs` 存在（6,426B）；`civlink_ctl_gui.exe` 实测 8,704B / sha256=A0EB830BF26D4AFBAEF2AD719748660409ECAE4647BD1527B1649E838FD3B894（前缀 A0EB830B 命中）；部署目录 `C:\Users\dd\Desktop\civlink-gui\` 存在，其中 civlink_ctl_gui.exe 与源码树副本哈希逐字节一致，且含 ctl/hook/使用说明（与"同目录部署、提权运行"一致）。信息观察③：README 路径表述 `civlink\ctl\civlink_ctl_gui.cs → civlink_ctl_gui.exe` 中 exe 实际位于 `civlink\` 根（`ctl\` 下为 .cs 源）；部署副本哈希一致，不构成缺陷，可作信息级说明。 |
| ④边界（L1255–1256）完整 | **PASS**：①②均不构成 M0-B 验收或双人真实联机证据；E2-A/E2-B/E3 仍待 PC-B 在线执行；Gate A 未批准、M0-B 冻结维持。 |
| 无越界宣称 | **PASS**：v1.22 块未宣称双人真实联机 / M0-B 验收 / 跨机验证完成。 |
| 旧哈希残留 | **PASS**：README 全文 grep `48017EAB|472FA16C|105EC490` 0 命中。 |

---

## E. 边界 — **PASS**

| 文件 | 维持边界 | 结果 |
|---|---|---|
| F5 文档 §5（L128–135） | 不证明双人真实对局、E2-B 双端注入、62056 数据面、Relay RTT、Fake-IP、Noise 加密、跨网/长稳；不得据此勾掉 E2-A/E2-B/E3；不移动 Gate A/B；Gate A 未批准、M0-B 冻结 | **PASS** |
| F5 文档 §3.4 / §7 | 单机真实客户端验证（方案 C）+ 双机核验包待 B 机执行（m19249 指示），无跨机验证完成宣称 | **PASS** |
| README L4 状态行 + v1.22 ④ | F5 `NOT 双人真实联机、不勾 E2-A/E2-B/E3`；v1.22 边界完整 | **PASS** |
| M0B-PREP 文档 §0/§6 | 非验收、不勾 Gate A/B、不证明双人联机/62056 转发正确性；正式 M0-B 冻结 | **PASS** |

---

## 缺陷分级汇总

- **阻断**：0
- **高**：0
- **中**：0
- **低**：0
- **信息**：3
  1. §3.4/§7 的 PASS 状态建议补注"（口述确认）"证据等级限定（房间可见性为用户口述，agent 侧计数为机械证据），防与 §3.1–3.3 机械 PASS 混淆。
  2. summary 字段 `run time` 实为 UTC 墙钟戳（main.rs `wallclock_stamp()`），命名易误读为时长；值本身与 12:35 时间窗一致，无数据错误。
  3. README v1.22 ③ 路径表述"civlink\ctl\civlink_ctl_gui.cs → civlink_ctl_gui.exe"中 exe 位于 civlink\ 根而非 ctl\；两处副本哈希一致（A0EB830B…/8,704B），无实质影响。

## 必改项清单

**无（0 项）。** 三项信息级建议均不影响登记事实正确性，可由文档维护者按需处理（建议在收尾登记时一并考虑）。

## 最终裁定

**通过（PASS）**。F5 单机真实客户端验证的正式登记（F5 文档 §3.4/§7 + README v1.22 修订记录 + 证据目录 30 文件）身份全部命中、证据计数与逐字节比对独立复核一致、口述确认如实标注、单机≠双机与全部边界声明如实维持、无旧哈希残留、无越界宣称；README v1.22 与 F5 文档、M0B-PREP 文档、GUI 条目三方一致。登记事实成立，可进入收尾（§7 末条"待收尾登记审计"应更新为本报告已完成）。
