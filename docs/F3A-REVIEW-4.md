# F3-A 直连转发原型 · 第四轮独立审计（F3A-REVIEW-4）

- 审计对象：`CivLink-M0A-audit\docs\F3A-DIRECT-FORWARD-20261114.md`（v4，19,802B）及其代码、脚本、证据（`M0A\captures\F3A-forward-selftest-20261114-155041\`）
- 依据：第三轮 `docs\F3A-REVIEW-3.md`（不通过，E.3 节列出"转有条件通过最少 6 项 + 转通过追加 9 项"）
- 方法：read 全文 + pwsh 只读重算哈希/字节数/断言计数，未执行自检脚本、未绑定 62056、未改动任何被审文件
- 日期：2026-11-14

## 0. 裁定摘要

**有条件通过。** 第三轮 E.3 的六项最小转正条件（R3-H1、R3-H2、R3-H3 主口径、R3-H4、R3-M1–M5、现状声明）与追加 9 项中的 M6 / M7 / M5 / L3 / L4 / L5 / L8 / R3-L2 均已实质修复，且经"文档 + 代码 + 证据/产物"三层独立核实；15 项身份哈希全部重算一致，31 站点 / 35 次执行口径精确、无零信息量断言残留。剩余缺陷全部为低级别措辞/计数问题（R3-L1 断言名未修、"12 个哈希"口误、§6 的 37 归因残留、§2 分组措辞、L1/L7 未并入不证明清单、M7 文档表述弱于实现），不影响证据真实性，修完即可转"通过"。

## 1. 缺陷分级计数

| 级别 | 第三轮 | 本轮 |
|------|--------|------|
| 阻断 | 0 | **0** |
| 高 | 4 | **0** |
| 中 | 5 | **0** |
| 低 | 8 | **6** |

高、中缺陷全部清零；残留 6 项低缺陷全部为文档/脚本措辞级，无需重建证据。

## A 节 · 证据真实性

**哈希与字节数逐项重算（pwsh Get-FileHash 实测，15/15 与 §4 逐字一致）：**

| 文件 | 字节数 | SHA-256（独立重算） | 与 §4 |
|------|--------|----------------------|-------|
| agent\src\main.rs | 95,778 | `6415954CBC888DA00EA40B0B46FB7E2D347B51C76E8F84C641E80C40F26E93ED` | ✔ |
| agent\Cargo.toml | 525 | `0CC694BBE083E20FCE2AF416C3F32AF84705130485239A5AA18E966081F22017` | ✔ |
| civlink-agent.exe | 382,464 | `2E9BFCB53A3A253CAFECAF046C6B986EDD3126819D01A6DE859762739C2514F6` | ✔ |
| run-f3a-forward-selftest.ps1 | 22,385 | `1D8DA92D7193E2A1E127F2CAFA1C6434A9D41B05403DBEE0313E5A0C409FD68A` | ✔ |
| summary.txt | 3,946 | `1C3664F2CC594E17F237D122229B090B04C83D3992F5B04BE9E25688C94260AC` | ✔ |
| forward-log.txt | 1,548 | `6CD8857B1396C969192B7FA31FF4269E8647EAB7F3229428EB40513C69A09507` | ✔ |
| frame-log.txt | 1,040 | `A6310C20AA81D6E1814AD860C226A18925F3436B31A832E337E08454415F2738` | ✔ |
| datapath-log.txt | 769 | `BFD736279E4955FD0CF1ACE55F1E710BF1F27C12A71BF0DBDD02EF7DD6B10EFF` | ✔ |
| bind-check.txt | 48 | `01BA8326F3E8C87CCAAA6D513DE8BF11A01C1C7E7A495F00B87D5DE640ADA6D2` | ✔ |
| negative-cases.txt | 387 | `3FB5A8B2D1126227D56B8940E34CFC6ECF5EDCEA933B98157A4A9123F93621E8` | ✔ |
| selftest-console.txt | 3,193 | `CC4C07CA4B6AFA571DDE2138CAEB6CBF22F3E4D8A4C34DD63FD7F89E187B5417` | ✔ |
| exit.txt | 17 | `81DDBAF9EED6926436F584FADECA0FBBE6DF4B4E6A47F318AF3A728A6574385A` | ✔ |
| agent-console.txt | 5 | `F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295` | ✔ |
| agent-stderr.txt | 5 | `F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295` | ✔ |
| stop | 0 | `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855` | ✔ |

补充核实：
- **5B 文件字节**实测为 `EF BB BF 0D 0A`（UTF-8 BOM + CRLF），非空内容，与 §4 第 89 行说明一致；0B 文件 stop 哈希恰为 SHA-256 空输入值，与"空文件"表述一致。
- **载荷摘要独立重算**（.NET SHA256，与 forward-log 逐字一致）：p1(17 32 00 00 FF FF 4F AC)→`5a36d008…`；p2(…35 BA)→`c793bc05…`；p3(1..120 递增)→`1ea7bb62…`；discovery(8D E8 FC 70)→`c003d207…`。
- **构建可复现降级坐实**：`agent\target\release\civlink-agent.exe` 实测与交付 `civlink-agent.exe` 同哈希（2E9BFCB5…）、同字节（382,464B），"交付副本 = 构建目录产物逐字节拷贝"在产物层成立。
- **无拼装论证**：证据目录内 11 个文件全部为本次 run 的自然产物，交叉锚点闭合——转录头 `Start time 20261114155041` 与目录名 `-155041` 匹配；bind-check `agent pid=36612` 与 summary `agent pid` 一致；帧时间 07:50:43.979–982、summary run time 07:50:45.556、转录结束 20261114155045，时序自洽。
- **目录级说明**：`M0A\captures` 下共 10 个 F3A 目录（141849/141904/141929/142008 各 9 文件；144051/144121/150809/150855/150906 各 10 文件；155041 11 文件），与 §6 运行历史逐一对应；无 `-154749` 目录（该 run 脚本语法错误未启动 agent，与 §6 描述一致）。`.bak-154748` 存在（18,967B）。
- **一处口径提醒**：证据目录实为 **11 个文件**（任务书写的"12 文件"有误；v4 §4 的 11 行证据表本身正确）。

## B 节 · 断言强度

**31 站点 / 35 次执行核实成立**：脚本 grep 实测 31 行 `Check ` 调用（29 个单次站点 + 2 个循环内站点 × 负向 3 次 = 6 次执行 → 总 35 次）；selftest-console 转录实测 35 行 `[PASS]`、0 行 `[FAIL]`，与文档 §3 完全一致。

| 分类 | 站点 | 评价 |
|------|------|------|
| 强 | 负向 3 用例（独立进程 exit=1 + stderr 各自匹配 want 文案）；M6 全文件 `seq=3` 缺席；M7 跨文件 peer-recv `from=` 对照；7 帧载荷摘要按 seq 三元比对（含 120B 全字节）；`forward-log never targets :62056`；peer-recv 8B 载荷头 ×2 | 独立、可证伪、有信息量 |
| 同源（同一份 summary 不同字段） | 计数 7 连发（frames seen/forwarded/forward bytes/fail/skip not datapath/skip discovery/skip rejected）、闭合恒等式（含 rejected 项）、mappings==1、peerRecv==4、peerBytes==140、listenPort==21346、target、boundary | 相互咬合、可交叉验证，恒等式使同源字段彼此约束 |
| 弱 | `agent does not bind UDP :62056`（Get-NetUDPEndpoint 观测，真实但只证明运行期未绑）；`peer first sender is the forwarder socket (port match)`（同文件 summary 两字段，同源弱检查） | 有观测依据，价值有限但不虚假 |
| 恒真/零信息量 | 无 | M5 的 `skip key table` 恒真断言已删（脚本 L284-287 注释说明） |

新增站点溯源：v3 备份脚本 `.bak-154748` 实测 30 个 `Check` 调用（`^\s*Check ` 30 行），v4 为 31 站点（净 +1 = 新增跨文件身份 M7 站点），口径演进可解释。

## C 节 · 设计与实现一致性（第三轮 E.3 逐项打勾）

| 编号 | 内容 | 判定 | 核实依据 |
|------|------|------|----------|
| R3-H1 | 回包策略更正（D4 兼容 reply sent 1 / bytes 20） | ✔ 已修 | v4 §7 明写 D4 兼容分支；summary L24-27 `reply sent 1 / reply bytes 20 / already_sent 5`；datapath-log 第 3 行实测 `datapath reply sent 20B to 127.0.0.1:21345 (ephemeral src port 57598) - local probe only` |
| R3-H2 | 构建可复现降级 | ✔ 已修 | v4 §4 第 91 行改为"交付副本=构建目录产物逐字节拷贝"，不再声明可复现；产物层实测 `target\release\civlink-agent.exe` 与交付 exe 同哈希 |
| R3-H3 | 断言数口径（37 归因） | ◐ 主口径已修 / 残留 | 全文统一为 31 站点/35 次执行；但 §6 144121 行仍写"37 为当时脚本内 Check 站点数"，与其后"站点数不可复原"自相矛盾（见 E-3） |
| R3-H4 | summary `frames seen` 标签诚实化 | ✔ 已修 | main.rs:1682-1685 标签含"discovery included; counted under `skip discovery`"；summary L33 实测同文案；脚本 Grab 模式（L249-263）与新标签匹配 |
| R3-M1 | 同哈希成因（EF BB BF 0D 0A） | ✔ 已修 | v4 §4 第 89 行写明 PS Out-File utf8 写 BOM+CRLF；字节实测一致 |
| R3-M2 | 六次→五次运行 | ✔ 已修 | v4 §7 第 144 行写五次（142008/144051/144121/150809/150906） |
| R3-M3 | 全仓 19→agent 19+fakeip 17 | ✔ 已修 | fakeip\src\lib.rs 实测 17 个 `#[test]`，agent main.rs 实测 19 个，合计 36 与 §7 一致 |
| R3-M4 | 幽灵端口 21347 | ✔ 已修 | v4 §7 第 145 行声明删除；脚本全文无 21347 |
| R3-M5 | §5.5 悬空引用 | ✔ 已修 | §7 第 146 行声明 §5.5→§5.1 第 5 条 |
| R3-L1 | 断言名 50399-like→50999 | ✖ 未修 | 脚本 L319 与转录 L46 仍为"50399-like"（见 E-1） |
| R3-L2 | transcript + .bak | ✔ 已修 | 脚本 L30-36 Start-Transcript 落 selftest-console.txt；转录实测存在 3,193B；.bak-154748 实测存在 |
| R3-L3 | 分组措辞（边界声明计入 summary 计数） | ◐ 部分 | 总数 31/35 精确无误；§2 分组"对端身份 2"列 3 项计 2、边界声明归属不明（见 E-4） |
| M6 | 全文件 seq=3 不出现 | ✔ 已修 | 脚本 L325-327 `-not ($logged -match '\bseq=3\b')` 作用于全部 forward-log 行；forward-log 实测 11 行（4 forward seq1/2/5/6 + 4 peer-recv + 2 skip）无 seq=3 |
| M7 | 跨文件 sender 对照 | ✔ 已修（实现）/ 文档表述弱 | 脚本 L335-353 解析 peer-recv `from=([\d.]+):(\d+)`，比端口==fwSockPort、≠62056、IP ∈ {127.0.0.1, fwSockIp}；日志 4 行 from=127.0.0.1:57599 全部一致（见 E-6） |
| M5 | 删 :271 恒真断言或加 >64 键用例 | ✔ 已修 | 脚本 L284-287 删 skip key table 恒真断言（恒等式仍含 skipKey 项）；main.rs:2247 单测 `forward_key_table_full_refuses_to_forward`（MAX_FORWARD_KEYS=64, L673） |
| L3 | stop 后 break 前 drain | ✔ 已修 | main.rs:1300-1310 stop_seen 时先 L1306-1309 最终 drain 再 break |
| L4 | forward FAILED 行含 target | ✔ 已修 | main.rs:789 `forward FAILED -> {target} (send_to failed; see forward fail counter)` |
| L5 | rejected 计数入恒等式 | ✔ 已修 | main.rs:664 `skip_rejected_flags` 字段、L1415-1417 分派递增、L1705-1708 渲染；脚本 L288 `$acct` 含 skipRej 项，L289-291 Check 恒等式；summary L41 `skip rejected: 0` |
| L8 | 负向分用例匹配 + $code 于 Kill 前取 | ✔ 已修 | 脚本 L100-103 三用例各自 want（`port must not be 62056`/`forward-listen must not be 62056`/`forward-to must not target port 62056`）；L123 在 L124 Kill() 前取 ExitCode；negative-cases.txt 实测三行文案互异、各 exit=1 |
| L1 | 缓冲 2048 截断 | 声明不修 | §5.3 声明；main.rs:1282 `vec![0u8;2048]`（42B 头+≤1280B 载荷=1322B<2048，回环夹具不触发） |
| L2 | ForwardState::new 绑 0.0.0.0:0 | 声明不修 | §5.3 声明 + §3 不证明清单已列入；main.rs:695 现状 |
| L7 | bind-check/SO_REUSEADDR | 声明不修 | §5.3 声明 SO_REUSEADDR 仅源码静态审查佐证、bind-check 只按 OwningProcess 观测（见 E-5） |

## D 节 · 表述边界

**已声明到位：**
- 回包策略更正：§7 明写"D4 兼容分支（回包 1 次 20B；already_sent 5）"，与 datapath-log 实测吻合，不再称"回包为零"。
- 构建可复现降级：§4 明写"交付副本=构建目录产物逐字节拷贝；未声明构建可复现"，产物层同哈希坐实。
- L2（转发 socket 源 IP 语义/绑 0.0.0.0:0）已列入 §3 不证明清单。
- "不证明"清单共 9 项（真实 Peer 可达性、真实双机、注入与绑定共存 H2/R1、跨网/Relay RTT、加密与密钥协商、长稳与高负载、未命中映射路径产品语义、多 Peer 并发与重排、转发 socket 源 IP 语义），全文自限于回环/本地探针，**无把模拟证据写成真实联机验证之嫌**。

**未声明或说错：**
1. L1（2048B 缓冲截断）与 L7（SO_REUSEADDR 仅静态审查）只在 §5.3 声明"不修"，**未并入 §3 不证明清单**（E.3 第 6 项要求三者都补，L2 已补、L1/L7 未补）。
2. §7"12 个哈希"口误：§4 实为 15 行身份表 / **14 个去重哈希**（agent-console 与 agent-stderr 同哈希 F01A…）；v3 的"13 个哈希"（14 行 − 1 去重）反而是对的，v4 改错了。
3. §6 144121 行"37 为当时脚本内 Check 站点数"与"站点数不可复原"自相矛盾；.bak-154748（v3 脚本）实测 30 站点，证明不了 37，37 仍是无来源归因。
4. M7 文档称"比端口+IP"，实现为 `fromIp ∈ {127.0.0.1, fwSockIp}`：回环下 127.0.0.1 恒过，IP 比较实际不约束，端口才是绑定项——文档表述弱于实现。
5. §2 分组"对端身份 2（监听端口、目标、首个发送者端口匹配）"列出 3 项却计数 2；边界声明站点归属不明（与 R3-L3 同族）。

## E 节 · 缺陷清单与裁定

| # | 级别 | 缺陷 | 最小转正条件 |
|---|------|------|--------------|
| E-1 | 低 | **R3-L1 未修**：脚本 L319 与转录 L46 断言名仍"50399-like"（应 50999） | 断言名改 50999，随下次 run 转录同步 |
| E-2 | 低 | **§7"12 个哈希"口误**（§4 实为 15 行/14 去重哈希；证据文件 11 个） | §7 改"15 行身份 / 14 去重哈希 / 11 个证据文件" |
| E-3 | 低 | **§6 144121 行 37 归因残留**（E.3 ③ 要求删 37 归因；与"站点数不可复原"自相矛盾） | 删"37 为当时脚本内 Check 站点数"，只留"站点数不可复原，仅作历史" |
| E-4 | 低 | **§2 断言分组措辞**：对端身份列 3 计 2；边界声明归属不明（R3-L3 族） | 分组改为实际站点清单（含边界声明归属），计数与 31/35 对齐 |
| E-5 | 低 | **L1/L7 未并入 §3 不证明清单**（E.3 ⑥ 部分完成） | §3 不证明清单补两条：2048B 缓冲可截断、SO_REUSEADDR 仅源码静态审查佐证 |
| E-6 | 低 | **M7 文档表述弱于实现**（IP 项 127.0.0.1 恒过） | 文档如实写 `fromIp ∈ {127.0.0.1, fwSockIp}`，或加"IP 绑定以端口为准"说明 |

**裁定**：满足第三轮 E.3 全部 6 项最小转正条件（R3-H1/H2/H4/M1–M5 已修；R3-H3 主口径已修；现状声明主体完成，仅 L1/L7 清单位置问题），**转"有条件通过"**。转"通过"最小条件：修 E-1 至 E-6（全部为文档/脚本措辞级修改，无需重跑证据；其中 E-1 断言名可在下一次 run 中自然生效）。本轮无需做的既定项（L2 绑回环、L7 断言名改写）维持不修声明。

---

本报告为只读审计产物。除本文件外，本轮未修改任何被审文件。
