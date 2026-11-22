# F3-C 指数退避语义 · 第二轮独立审计（F3C-REVIEW-2）

> 审计对象：`docs\F3C-BACKOFF-20261114.md`（v2，229 行，14,584B，SHA256 8524E9C9…）
> 证据：`M0A\captures\F3C-backoff-selftest-20261114-151943\`（11 文件）
> 代码：`civlink\agent\src\main.rs`、`civlink\agent\Cargo.toml`、`civlink\agent\target\release\civlink-agent.exe`
> 脚本：`civlink\run-f3c-backoff-selftest.ps1`（v2，19,158B）
> 审计方式：只读。全部哈希、字节数、行号、时间戳差值为本轮在磁盘上独立重算/重数；未执行任何命令改写被审对象；未运行自检脚本（占用端口且 255 秒），未绑定 62056。

## 0. 裁定摘要

**裁定：不通过（FAIL）**

证据本身是真的：11/11 身份哈希逐字相符、13 载荷 sha256 独立重算全部咬合、9 个退避间隔可重算、负向对照与 D4 断言在证据中真实可见——**这不是拼装证据**；且第一轮 2 阻断、4 高、7 中已实质修复（哈希改实测、负向对照、夹具差异表、618→50B、D4 断言、去 [bool] 强转均落地）。

但存在 **1 项阻断级链条断裂**：证据捕获（15:19–15:24）与文档定稿（15:25:48）**之后**，`main.rs` 与 `civlink-agent.exe` 均被改动/重建（15:46:58 / 15:47:53）。产生证据的 382,976B / A43248B9… 二进制已不在仓库；当前树是 381,440B / 02A31FF0… 与 95,778B / 6415954C…，与文档 §7 身份表不符；且当前源码的 `frames seen` 标签已改（main.rs:1683），脚本 Grab 正则（脚本 :235）仍锚定旧标签——**用当前树重跑本脚本，Check#3 必红**。证据既不能由当前树重放，也不能与当前源码对应。第一轮 R-02（"证据由已不在仓库的二进制产生"）以相同形态复发。

| 维度 | 结果 |
|------|------|
| A 证据真实性 | **通过**（11/11 哈希逐字相符；算术全闭合；载荷 sha256、间隔、负向、D4 全部独立重算咬合；5B 文件字节实查 [EF BB BF 0D 0A]） |
| B 断言强度 | **基本通过**（26 条 Check 计数精确；去 [bool] 强转；切片规避重复 seq=10；负向 4 条 + D4 2 条新断言真鉴别力；最强断言 #25 sha256 三方独立互证） |
| C 设计与实现一致性 | **通过**（单次 send_to、D4 只回 1 次、5 字段映射键、note_seq 语义、peer-recv 无去重，均与当前源码及证据咬合） |
| D 表述边界 | **通过（附 1 处小漂移）**（§5 夹具差异表、§6 证明/不证明、50B 封装更正、无联机暗示均诚实；唯"main.rs:757"行号对当前源码偏 6 行，实为 :763） |
| E 缺陷与裁定 | **不通过**（阻断 1：代码与证据的链条在文档定稿后断裂） |

## 1. 缺陷分级计数

| 级别 | 数量 | 编号 |
|------|------|------|
| 阻断 | 1 | R2-B1 证据产生后 main.rs/exe 被改动，产生证据的二进制已不在仓库，当前树不可重放 |
| 高 | 0 | — |
| 中 | 2 | R2-M1 脚本 Grab 锚定旧标签，与当前源码不兼容（重跑必红的可复现性缺陷）；R2-M2 断言 13 仍只比端口尾数（文档已收窄措辞，故降为"遗留未修"而非高） |
| 低 | 4 | R2-L1 main.rs:757 行号漂移（实为 :763）；R2-L2 断言 1 bind 检查仍单次采样；R2-L3 证据目录两套编码并存（BOM 不统一）；R2-L4 断言 26 容差 650ms 对 0.5s 对无分辨力 |

第一轮缺陷关闭情况：2 阻断中 R-01（哈希改实测）✔ 关闭、R-02（exe 重建）◐ 复发为 R2-B1；4 高全部 ✔ 关闭（R-03 措辞收窄、R-04 负向+标签、R-05/R-06 三帧负向、其中 R-03 的脚本层"只比端口"遗留为 R2-M2）；7 中全部 ✔ 关闭（R-07/R-08/R-09 部分/R-10/R-11/R-12/R-13）；6 低中 R-14 ✔（去 [bool]）、R-15/R-16/R-18 未修（低）、R-17 ✔（统一 258.4s）、R-19 ✔（编造 src 已声明）。

## A 节 · 证据真实性

### A.1 身份哈希逐项重算（Get-FileHash + Length，全在磁盘实测）

证据目录 `M0A\captures\F3C-backoff-selftest-20261114-151943\`：

| 文件 | 文档 §7 | 本轮实测 | 比对 |
|------|---------|----------|------|
| summary.txt | 3,706B D71A6F5C… | 3,706B D71A6F5CC25F54FFBA37A25B53289C50D4C4EE91761C251D1D2BB74B55C555A2 | ✔ 一致 |
| forward-log.txt | 4,433B FAAFEF5D… | 4,433B FAAFEF5D939D395C0B69FC18883C7F70D865ECB6C20C08F9E1CBA04C36829DAD | ✔ 一致 |
| frame-log.txt | 1,878B 80D2F444… | 1,878B 80D2F444550141F4F4C1522867FE9884178EAC51B473356487B43EBD95679771 | ✔ 一致 |
| datapath-log.txt | 1,498B B2EF0583… | 1,498B B2EF05832D461C66C807BCCDEB5D17745176554A8337D66FB2D34819F6744588 | ✔ 一致 |
| send-schedule.txt | 449B D604B557… | 449B D604B557A8DC41C98806381074BC9B9D8AAB6ECCD484E0D463D7076A020170E4 | ✔ 一致 |
| negative-controls.txt | 103B 8C89D7BA… | 103B 8C89D7BAAAB7FC31D8C53E88855C28F707473507F932BBCF382B0BD1C8780707 | ✔ 一致 |
| bind-check.txt | 48B 1641B6BC… | 48B 1641B6BCD4EAEBC0C080282B42C7D9C33F074921C738478216CD9E730E43730C | ✔ 一致 |
| exit.txt | 17B 81DDBAF9… | 17B 81DDBAF9EED6926436F584FADECA0FBBE6DF4B4E6A47F318AF3A728A6574385A | ✔ 一致 |
| agent-console.txt | 5B F01A374E… | 5B F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295 | ✔ 一致 |
| agent-stderr.txt | 5B F01A374E… | 5B F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295 | ✔ 一致 |
| stop | 0B E3B0C442… | 0B E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855 | ✔ 一致 |

**11/11 逐字一致。** 代码/脚本侧：Cargo.toml 525B 0CC694BB… ✔ 一致；脚本 19,158B 73085FE6… ✔ 一致；**main.rs 文档 94,058B / 198C7770… vs 磁盘 95,778B / 6415954C… —— 不符**；**exe 文档 382,976B / A43248B9… vs 磁盘 381,440B / 02A31FF0… —— 不符**（详见 E 节 R2-B1）。

### A.2 5B 文件字节实查（任务指定项）

`agent-console.txt` 与 `agent-stderr.txt` 实测字节为 `[EF BB BF 0D 0A]`（UTF-8 BOM + CRLF），**非空文件**；两文件同哈希是预期现象（PS 重定向空输出即写 BOM+CRLF），非复制错误——文档 §7 注释（:197-199）所述正确。`stop` 0B / E3B0C442… 才是真空。文档未把 5B 文件写成"空内容"，表述边界无错。

### A.3 内部一致性独立复算（不依赖文档数字）

- **payload sha256 三方对账**：13 个载荷（17320000FFFF + 4FAC/51A1/558A/5D5A/6CFA/8C3A/CABA/47BA/41BA/35BA/35BA/7E42/9F37）用 .NET SHA256 独立重算，与 forward-log 每行 `sha256=` 逐字一致（如 4FAC→5a36d008…、35BA→c793bc05…、7E42→42b47981…、9F37→457e4040…），与 Agent 手写 Rust sha256_hex 交叉验证通过。
- **9 个退避间隔**（forward-log 时间戳差值，UTC）：+0.520 / +1.010 / +2.016 / +4.010 / +8.016 / +16.005 / +32.003 / +64.002 / +128.006 s，与文档 §4 完全一致（本轮独立复算，非转抄）。偏差最大 20ms（0.5s 对）。
- **负向对照三帧**：F11 seq=10 重复（07:24:00.438，与 seq=10 同 sha256 c793bc05…，即 payload 也同）→ duplicates=1；F12 seq=12（07:24:00.571）→ seq gaps=1、missing_frames=1；F13 seq=13（07:24:00.695，4-tuple 与 seq=1 相同、payload 故意不同）→ mappings created 仍 1。与 negative-controls.txt 三行记录（437/570/695，比到达早 1ms，因脚本先记后睡 120ms）咬合。三帧间隔实测 133ms/124ms（设计 120ms）。
- **D4 回包**：datapath-log 仅 1 行 "datapath reply sent 20B to 127.0.0.1:21345 (ephemeral src port 63195) - local probe only"（首帧触发，63195≠转发 socket 63196）；summary 显示 reply sent=1、already_sent=12 → 13 帧只回 1 次探针，其余 12 帧记账 already_sent。断言 #18/#19 成立。
- **主序列完整性**：frame-log 13 行 seq=1,2,…,10,10,12,13；datapath-log 13 行；forward-log 13 forward 行 + 13 peer-recv 行；summary frames=13、first_seq=1、last_seq=13、datagrams=13、bytes=650（=13×50B，42B 帧头+8B 载荷）；reconciliation 13==13；payload bytes=104（=13×8B）三方一致。算术全闭合。
- **编码**：summary/forward-log/frame-log/datapath-log 为无 BOM + LF；send-schedule/negative-controls/bind-check/exit 为 UTF-8 BOM + CRLF（R2-L3）。
- **时间线咬合**：证据目录 mtime 15:19:44–15:24:02；send-schedule 10 行 15:19:44.843→15:24:00.430；summary run time 07:24:02.532（UTC，=15:24:02.532 本地）；listen window 258.4s → 全链路真实运行约 258s（非压缩窗口，TimeScale 1.0），与文档 §2 一致。

**A 节结论：证据真实、自洽、可重算，无拼装迹象。**

## B 节 · 断言强度

脚本 `run-f3c-backoff-selftest.ps1`（v2）恰有 **26 处 Check 调用**（:138 / :220 / :254-265 十个 / :273-274 / :282-286 四个 / :292-293 两个 / :294 / :295 / :302 / :303 / :325 / :355 / :381），文档 §3"26 项断言"计数精确。

### B.1 26 条 Check 分类表

| # | 断言 | 来源 | 强度 | 说明 |
|---|------|------|------|------|
| 1 | bind-check owned by agent==0 | bind-check.txt（启动后一次采样） | 弱 | 单次瞬时采样，区分不了"未绑"与"无人绑"；但有 PID 过滤（OwningProcess==$proc.Id），比第一轮强 |
| 2 | exit==0 | exit.txt | 弱 | 必要但弱 |
| 3 | frames seen==13 | summary 前向段 | 强 | 对端收包总数；与 #22 同源但可交叉 |
| 4 | forwarded==13 | summary | 强 | 转发总数 |
| 5 | forward bytes==104 | summary | 中 | 派生值（13×8B） |
| 6 | forward fail==0 | summary | 弱 | 零值，无负向可对照 |
| 7 | skip not datapath==0 | summary | 弱 | 零值（域内恒 0，13 帧全走 62056） |
| 8 | skip key table==0 | summary | 弱 | 零值（1 键 vs 上限 64，无鉴别力） |
| 9 | mappings created==1 | summary | 强 | 单键夹具；与负向 F13 配对后有效 |
| 10 | payloads recv==13 | summary | 强 | 对端收包；与 #23 交叉 |
| 11 | payload bytes==104 | summary | 强 | 与 #5 不同字段（peer 侧） |
| 12 | listen port==21347 | summary | 强 | 跨字段独立 |
| 13 | forward sock 端口==first sender 端口 | summary | 弱 | 仍只比 :(\d+)$ 尾数，不比 IP 不查 PID（R-03 未修）；文档已收窄措辞 |
| 14 | duplicates==1 | summary | **强** | 负向 F11 真触发，计数器可见工作 |
| 15 | seq gaps==1 | summary | **强** | 负向 F12 真触发 |
| 16 | missing_frames==1 | summary | **强** | 负向 F12 真触发（12-11=1） |
| 17 | out_of_order==0 | summary | 弱 | 零值；与 #14 同源 |
| 18 | reply sent==1 | summary datapath 段 | **强** | D4 断言（第一轮 R-11 已修） |
| 19 | already_sent==12 | summary | **强** | D4 断言 |
| 20 | forwarded==peer received | summary 同段同源 | 恒真 | 同源比较，无独立鉴别力；文档已声明"不独立证明不重传" |
| 21 | summary 含 'LOOPBACK PROTOTYPE' | summary | 恒真 | 自证文案（代码固定输出） |
| 22 | forward seq= 行数==13 | forward-log | 强 | 与 #4 交叉 |
| 23 | peer-recv n= 行数==13 | forward-log | 强 | 与 #10 交叉 |
| 24 | 主序列 seq 严格 1..10 | forward-log 切片 | 强 | 逐位比对（用 -First 10 切片规避 F11 重复 seq=10） |
| 25 | 每 seq：fwdLine 唯一 + sha256 三方 + peerLine 唯一 | forward-log + .NET SHA256 | **最强** | 独立实现（.NET）vs Agent 手写 Rust sha256_hex 交叉验证；切片保证 F11 不歧义 |
| 26 | 9 对间隔 |≤ 650ms 容差 | forward-log 时间戳 | 强 | 数学可重算；但容差对 0.5s 对无分辨力（R2-L4） |

强/真鉴别力：**13 条**（#3/4/9/10/11/12/14/15/16/18/19/22/23/24/25/26——其中 #14-16、#18-19、#24-26 为第一轮缺失、本轮新增或显著加强）；弱：8 条（#1/2/6/7/8/13/17/5）；恒真/同源：2 条（#20/21）。真正独立实现互证的最强断言仍为 **#25**（.NET SHA256 vs Rust 手写实现）。

### B.2 与第一轮缺口对比

| 第一轮要求 | 状态 |
|-----------|------|
| F11 duplicate seq=10 / F12 gap seq=12 / F13 同键异载荷 三负向帧 | ✔ 已实现（脚本 :160-201，证据 negative-controls.txt + summary 1/1/1） |
| duplicates/gaps/missing 断言 | ✔ 已实现（#14/15/16） |
| reply sent==1 / already_sent==12 断言 | ✔ 已实现（#18/19；第一轮建议 already_sent==9，实为 12 帧，已按实际改） |
| Check 去 [bool] 强转 | ✔ 已实现（Check 函数 :28-43：字符串参数直接 FAIL） |
| 切片规避 F11 重复 seq=10 歧义 | ✔ 已实现（:308-310 Select-Object -First 10 / Skip 10；#24/#25 均在切片内工作） |
| 断言 13 升级 PID/IP 或收窄措辞 | ◐ 措辞已收窄（文档 §3 效力自述诚实），脚本层仍只比端口（R2-M2） |

**B 节结论：断言质量较第一轮实质提升，负向对照与 D4 守护断言为真鉴别力；"26/26 通过"与脚本 Check 结构精确对应。**

## C 节 · 设计与实现一致性

以当前源码（main.rs，95,778B / 6415954C…）为参照，文档 v2 声称的行为与代码实际一致（**注意：当前源码与产生证据的 94,058B 版存在 1,720B 差异，差异内容未知——见 R2-B1；以下一致性以"当前源码仍保留全部 F3-C 相关路径"为限**）：

- **单次 send_to、无重传**：`ForwardState::consider`（main.rs:734）每帧仅一次 `sock.send_to(&frame.payload, self.target)`（**实际行号 :763**，文档引 :757 偏 6 行，R2-L1）；无重试循环、无重传计数器。文档 §6"机制证据=代码单次 send_to"成立。
- **D4 回包**：`DatapathState::consider`（:565）——src_port_be==0→no_endpoint；src_ip_be==0 或非本机→not_local；reply_sent>=1→already_sent；否则 20B 探针（:609）。与 summary reply sent=1/already_sent=12 完全咬合。
- **映射键**：`ensure_mapping`（:708）线性查重 5 字段（session/logical_socket/gen/dst_ip/dst_port），13 帧同一 4-tuple → mappings created=1，F13 同键异载荷不新增 → 断言 #9 有真语义（区分"正确分键"vs"全局单键"仍不能，但负向 F13 证明"同键只建一次"）。
- **note_seq 语义**：seq==last→duplicates；seq>last+1→gaps+missing；seq<first→ooo（:940）。输入 1..10,10,12,13 → duplicates=1、gaps=1、missing=1、ooo=0，与 summary 逐项一致。
- **peer-recv 无去重**：`ForwardListener::drain`（:841）无 seq 跟踪，received 逐包计数——文档 §6"不证明不重传"由此成立，诚实。
- **帧格式**：FRAME_HDR=42（:45）、载荷 8B → 50B/帧，13×50=650B 与 datagrams bytes 咬合；文档"CVLH2 封装 42B+8B=50B"更正了 v1 的 618 错误。
- **62056 护栏**：parse_args 三处 + ForwardListener::new 拒绝（:821-828）fail-closed；bind-check owned by agent=0（pid 42124）与该设计一致。

**C 节结论：设计-实现-证据三方一致；唯一保留项是"证据对应的具体源码快照已不可得"（R2-B1）。**

## D 节 · 表述边界

- **已声明到位**（全部诚实）：
  - §5 夹具差异表：src 0.0.0.0:62056→127.0.0.1:21345（脚本编造值，$sender 从未 bind）、session_id 0xaf8a2794b6d7→0x1、seq 101..110→1..13；忠实保留载荷 8B 逐字节/dst/flags=0x21/10 间隔（R-07 关闭）。
  - §6 证明 7 条 + 不证明 7 条：不证明真实双机/跨网/NAT/Relay、游戏侧行为（Hook 仅 M0-A）、退避来源语义与放弃点、时延、长稳 258.4s、并发、重传检测能力——**"不证明重传检测"已补上（第一轮最重要缺口）**。
  - 断言 13/20 效力自述（§3 :102-109）：只比端口、forwarded==peer received 不独立证明不重传 → 收窄到位。
  - §7.1 运行历史 + "v1/v2 数字不可跨版本比较"（23→26、10→13）。
  - §7 5B 文件注释（BOM+CRLF 非空、同哈希是预期）。
  - 全篇无把回环写成联机验证的越界措辞；状态行明确"仅本机回环原型，不移动 Gate A/B"。
- **未声明或说错**：
  - **R2-B1（阻断）**：文档定稿后代码被改动未在任何地方披露（§7 身份表写的是写表时刻的真值，但仓库随后被改，且无修订记录/无 git）。
  - **R2-M1（中）**：脚本与源码标签不兼容未声明（Grab 锚旧标签，当前源码已换新标签）。
  - **R2-L1（低）**："main.rs:757"对当前源码不成立（send_to 实为 :763；:757 是 skip_key_table_full 的 writeln 行）。

**D 节结论：表述边界总体诚实，第一轮 D 节缺陷全部修复；新增 2 处"未声明"（R2-B1/R2-M1）均因代码在文档定稿后被改动。**

## E 节 · 缺陷清单与裁定

### E.1 缺陷清单

| # | 级别 | 描述 | 最小转正条件 |
|---|------|------|-------------|
| **R2-B1** | **阻断** | 证据捕获（15:19–15:24）与文档定稿（15:25:48）**之后**，main.rs 于 15:47:53 改为 95,778B / 6415954C…，exe 于 15:46:58 重建为 381,440B / 02A31FF0…。文档 §7 声称的 94,058B / 198C7770… 与 382,976B / A43248B9… 均已不在仓库（全仓检索无）；产生证据的二进制不可恢复。第一轮 R-02 以同形态复发。 | 任选其一：① 恢复/固定 F3C 运行时的源码快照与 382,976B 二进制（放入仓库并给哈希），或 ② 用当前树重跑 selftest 产出新证据并同步更新文档与脚本（见 R2-M1），且此后任何改动走版本记录；同时文档 §7 身份表改为"证据对应快照"，并把 15:46/15:47 的重建记录为显式事件。 |
| R2-M1 | 中 | 脚本 Grab（:235）正则锚定旧标签 "`frames seen ... (accepted non-discovery`"，当前源码 :1683 已改新标签（含 discovery 计数，F3A-REVIEW-3 R3-H4 修复）→ **用当前树重建 exe 重跑本脚本，Check#3 必红**。证据可复现性在标签层面断裂。 | 脚本正则改匹配新标签（或改为不锚标签前缀），与 main.rs:1683 对齐后重跑一次验证。 |
| R2-M2 | 中 | 断言 13 仍只比端口尾数（:(\d+)$），不比 IP、不查 PID；回环任意进程可伪造源端口。文档已收窄措辞，故不升为高。 | 用 `Get-NetUDPEndpoint -LocalPort` 反查 OwningProcess==Agent pid，或至少断言 first sender 的 IP 为 127.0.0.1 且端口≠62056。 |
| R2-L1 | 低 | 文档 §3/§6 引 "main.rs:757 每帧一次 send_to"：当前源码 send_to 在 :763（:757 为 skip 分支 writeln）。 | 行号改为 :763（或引用函数名 `ForwardState::consider` 代替行号）。 |
| R2-L2 | 低 | 断言 1 仍为启动后单次采样（第一轮 R-09/R-15 未修）；bind-check.txt 只记瞬时快照。 | 运行中周期性采样或对端口占用保持监控记录。 |
| R2-L3 | 低 | 证据目录编码不统一：4 文件无 BOM+LF，4 文件 BOM+CRLF（第一轮 R-16 未修；不影响断言）。 | 统一编码并重新哈希。 |
| R2-L4 | 低 | 断言 26 容差 400×scale+250=650ms > 0.5s 最小间隔，对 0.5s 对无分辨力（实测 520ms 偏差 20ms 通过，但若观测 0.9s 也会误收）。 | 容差改为按间隔比例（如 ±10%）或至少 250ms，保证 0.5s 对有鉴别力。 |

### E.2 裁定

**不通过（FAIL）**。理由一句话：**证据真实、断言增强、表述诚实，但证据对应的代码与二进制在文档定稿后被改动且已不可得，当前树既无法重放证据也无法让脚本通过（R2-B1 + R2-M1），链条断裂——第一轮 R-02 的教训未在流程上解决（v2 只修了"文档哈希写实测值"，没有修"仓库状态漂移"这一根因）。**

转正条件（最小集）：R2-B1 的 ① 或 ② + R2-M1 脚本对齐并重跑 + R2-L1 行号修正。R2-M2/L2/L3/L4 可随之下轮处理。

---

本报告为只读审计产物。除本文件外，本轮未修改任何被审文件（未运行自检脚本、未绑定 62056、未重建二进制）。
