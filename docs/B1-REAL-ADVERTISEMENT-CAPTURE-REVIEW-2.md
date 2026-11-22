# B1 真实广告页捕获 · 复审审计报告（REVIEW-2）

- 复审子代理 id：cfc28fc4-3282-46a2-b15d-82184f008352（复审前首轮审计 f8918c50）。审计对象：`docs/B1-REAL-ADVERTISEMENT-CAPTURE-20261117.md`（v1.1，12,915B，sha256 `902FA2761BB32AB65F62D578CB86C67E96AB1F3D014CC89B2A131B6541FAF293`）及其修正（R-1/R-2/R-3）、新证据 `docs\reports\b1\run-20261117-012424`（PASS 17/17）
- 审计性质：复审（只读；仅针对「首轮必改 3 项是否落实 + 新证据是否成立 + 登记链是否一致」，不重复首轮已通过的机制审查）
- 审计员：复审子代理（父会话 session-6fe30d79-1c95-4c67-8f32-5859eb18dabd 委派；权限只读，唯一写入为本报告）
- 日期：2026-11-17
- 首轮裁定（参照）：`docs/B1-REAL-ADVERTISEMENT-CAPTURE-REVIEW.md`（146 行，审计员 f8918c50）——**有条件通过**，必改 R-1（高）/R-2（中）/R-3（中）

---

## 裁定：**通过**（无阻断/高/中必改项；低 severity 建议 2 项，见 §6）

首轮必改 3 项（R-1 高 / R-2 中 / R-3 中）全部确认落实；新采信轮证据 `run-20261117-012424` PASS 17/17 内部自洽、语义正确、判别力真实；登记链单向引用一致、无残留旧哈希、无越界宣称。仅发现 2 项低 severity 的**描述性尺寸字段陈旧**（哈希全部正确，不影响登记链绑定效力），列作建议修正项。

---

## 1. A 代码修正落实（main.rs，2,836 行，121,851B，UTF-8 无 BOM——首 3 字节 2F 2F 20 = `// `）

| # | 要求 | 证据（main.rs 行号） | 结果 |
|---|---|---|---|
| A-1 | `RealAdStats` 含 `replies_skipped: u64` | L736-753：字段齐全（captured/rejected/duplicates/noise_on_discovery_port/replies_used_real/replies_used_fixture/**replies_skipped**），注释明示「去重跳过、src port 0、max replies、缺 socket、发送失败，**NOT a fixture reply**」 | **PASS** |
| A-2 | `enum CaptureOutcome { Captured, Duplicate, FullRejected, NotAPage }` | L757-762 | **PASS** |
| A-3 | `enum ReplyOutcome { Real, Fixture, Skipped }` | L766-770 | **PASS** |
| A-4 | try_capture 返回 CaptureOutcome；仅 NotAPage 计 noise；rejected 仅计「满 22 页后的新不同页」 | L800-832（合法页 1104B+`59 60 69 9B`：已存在→Duplicate；`pages.len()>=22`→FullRejected；否则 Captured；其它→NotAPage）；`LanSimState::poll` L613-666 非 magic 分支 `match c.try_capture(...)`：**NotAPage→`noise_on_discovery_port+=1`**，其它分支仅当 `pages.len()==SIM_PAGE_COUNT` 置 `active` | **PASS**（R-2 落实） |
| A-5 | poll 的 magic 分支 match ReplyOutcome 分别计 real/fixture/skipped；非 magic 分支 NotAPage 计 noise、其它满集置 active | L613-666：magic 分支 `consider(&from, real_pages)` 后 `match outcome {Real→replies_used_real+=1, Fixture→replies_used_fixture+=1, Skipped→replies_skipped+=1}` | **PASS**（R-3/S-4 落实） |
| A-6 | consider 返回 ReplyOutcome；IPv6 / src port 0 / 去重 / max replies / 无 socket / 发送失败全部 Skipped | L674-723：IPv6→Skipped；`from.port()==0`→`no_endpoint+=1`+Skipped；key 已答→Skipped；`replied_sockets>=max_replies`→`max_replies_reached+=1`+Skipped；`reply_sock None`→Skipped；逐页 send_to 任一失败→`send_fail+=1`、ok=false→**Skipped**；全成功→`answered.insert`+`replied_sockets+=1`，`real_pages.is_some()`→Real 否则 Fixture | **PASS**（S-5 落实：发送失败不误计 real） |
| A-7 | 入口 A（P1 hook 帧）match 语法：NotAPage 忽略、其它满集置 active | L1797-1810：`if flags & (REJECTED_OVERSIZE|NO_PAYLOAD)==0 && flags & FLAG_DISCOVERY != 0 { match cache.try_capture(&frame.payload, "P1-hook") { CaptureOutcome::NotAPage => {}, _ => { if pages.len()==SIM_PAGE_COUNT { active=true } } } }` | **PASS** |
| A-8 | summarize B1 块含 `replies skipped` 行 | L2138-2169：captured/rejected/duplicates/noise on disc/replies real/**replies fixture/replies skipped**/active/files | **PASS** |

结论：三态/枚举返回（S-4）与拆分计数（S-1 恒等式的数据基础）在源码层落实，无「拒绝也置 active」「发送失败计 real」的旧缺陷路径。

## 2. B 机械证据（run-20261117-012424）

| # | 要求 | 实测 | 结果 |
|---|---|---|---|
| B-1 | result.txt = `B1-REALCAP-SELFTEST: PASS (17 checks, 0 failures)` | 54B，内容逐字吻合 | **PASS** |
| B-2 | summary 关键值 | requests seen=**100** / replied sockets=**1** / pages sent=**22** / captured=**22** / rejected=**0** / duplicates=**1** / noise on disc=**2** / replies real=**1** / replies fixture=**0** / replies skipped=**99** / active=**yes**（full 22-page set captured）——全部与断言值一致 | **PASS** |
| B-3 | real-page-01..22.bin 各 1104B 存在；manifest 22 页 | 22 文件 × 1104B；`real-ad-manifest.txt` 22 行 `page NN: sha256=… bytes=1104`；manifest 页哈希与文件抽查重算一致（page-01 `DDC8CD34…`、page-22 `6F98152D…`）；**real-page-01..22 == `civlink\fixture-reply-set\reply-01..22.bin` 22/22 逐字节一致**（C1 发送源） | **PASS** |
| B-4 | evidence-sha256.txt 49 条（不含自身与 stop）；目录共 51 文件 | 清单 49 行（frame-log/lan-fixture-manifest/lan-page-01..22/real-ad-manifest/real-page-01..22/summary/result），不含 evidence-sha256.txt 自身与 stop；目录 = 顶层 3 + agent 48 = 51（S-3/L-4 闭合）；证据内 5 个抽查文件哈希与清单重算全吻合 | **PASS** |
| B-5 | 语义正确性：rejected=0（C4 噪声按 R-2 计 noise=2）；replies fixture=0（100 magic 同源 54322 去重跳过，R-3 三态） | summary `noise on disc=2`（=C4 两负向：64B 噪声 + 1104B 全零 wrong magic），`rejected=0`（rejected 仅计满集后新不同页）；`replies real=1`（第一个 54322 请求答真实页）、`replies skipped=99`（同源去重）、`replies fixture=0`（无匿名兜底外发）；A14 恒等式 real+fixture+skipped==requests seen==100 | **PASS** |
| B-6 | 断言 A0-A14c 共 17 项 | 脚本 `civlink\run-b1-realcap-selftest.ps1`（366 行）断言段：A0/L238、A1/L240、A2/L245、A3/L259（逐字节）、A4/L265、A5/L271、A6/L287（**S-2：C3 应答==捕获页 22/22 逐字节**）、A7/L293（R-2：rejected==0）、A8/L297（R-2：noise==2）、A9/L302（S-1 捕获恒等）、A10/L310（manifest sha256==文件）、A11/L314、A12/L319（P1/P2 去重）、A13/L305（**S-1 恒等式 captured+rejected+duplicates+noise==25**）、A14/L330（三态恒等式）、A14b/L331（real==1）、A14c/L332（fixture==0）= 17 项 | **PASS** |
| B-7 | A6 判别力真实 | real-page-01.bin 房名字段（字节 24..45）= `dingzihan2022`（真实房名，非匿名 `CivLink-Test-Room-2222`）→ 应答==捕获集不可能由匿名 fixture 兜底伪造 | **PASS** |
| B-8 | 场景与留痕对应 | frame-log.txt（275B）单帧 `17:24:29.064 dir=0 af=2 seq=1 session=0x1 sock=1 gen=1 dst=255.255.255.255:62900 len=1104 flags=0x04 src=127.0.0.1:62000 head=5960699B2E690400` = C2 手工 CVLH2 帧（脚本 L120-160 编码逻辑与之一致）；C1 广播 reply 页 120ms 间隔（L107-118）、C4 两负向（L162-181）、C3 54322 绑端口 100×4B magic（L183-220）全部与 summary/frame-log 对应；stop 文件 4B `stop` | **PASS** |
| B-9 | 脚本稳定性修复 | 现行脚本 L100-101 `ReadToEndAsync` + L227-229 `Task.Result`（崩溃修复在），`result.txt` 正常生成 | **PASS** |

结论：新采信轮证据成立——17 项断言全部落地且与产物逐项对账，R-2/R-3 修正后的语义（rejected=0 / fixture=0 / skipped=99）在 summary、脚本断言、文档三处一致。

## 3. C 代码身份（实测 Get-FileHash）

| 文件 | 实测大小 | 实测 sha256（小写） | 任务/文档断言 | 结果 |
|---|---|---|---|---|
| `civlink\agent\src\main.rs` | 121,851B | `2687401cecdf2d5679f037ddca6e4434685efabf6a4ff94a6e9dbcabe8a419e7` | `2687401CECDF2D5679F037DDCA6E4434685EFABF6A4FF94A6E9DBCABE8A419E7` | **PASS**（精确一致） |
| `civlink\agent\target\debug\civlink-agent.exe` | 868,352B | `69cd012e24ac6758550348d4eb5d46c5ea6cb86e667d205f454416be1187d2ac` | `69CD012E24AC6758550348D4EB5D46C5EA6CB86E667D205F454416BE1187D2AC` | **PASS**（精确一致） |
| `civlink\agent\target\release\civlink-agent.exe` | 417,792B | `ddaf5453b35377493aba4f464adfc341a153861cec1352d97f07fbbe21113d63` | `DDAF5453B35377493ABA4F464ADFC341A153861CEC1352D97F07FBBE21113D63` | **PASS**（精确一致） |

旧身份（main.rs 119,618B/`3F9A7549…`、release 417,280B/`78D71DE7…`）在 README v1.26 与 HANDOVER 第 17 项均已标注作废，全仓无残留旧哈希引用。

## 4. D 文档与登记链

| # | 要求 | 实测 | 结果 |
|---|---|---|---|
| D-1 | §3 P1 含「覆盖范围限定（审计 R-1）」 | L40-43 原文：`hook.cpp IsDiscoveryTarget（L257-268）只对目标端口 62900..62999 或 255.255.255.255 广播命中（FLAG_DISCOVERY/FLAG_LIMITED_BCAST）；单播到请求者临时端口（如 54322）flags=0、不转发——P1 只覆盖「发现窗口期内目标为发现端口或广播」的广告页，不是确定性全覆盖`；hook.cpp L257-268 实测 `IsDiscoveryTarget` 定义与行号吻合 | **PASS**（R-1 降级落实） |
| D-2 | §3 P2 含「发送形态待实测（审计 R-1 前置）」 | L58-61 原文：`发送形态待实测（审计 R-1 前置）：…须在双机验证前用注入 civtrace 观测 A 机主机的实际 sendto 目标取证；在此之前如实声明：P1/P2 只覆盖发现窗口期/广播目标，单播不可捕获，B1 的机械证据（本机广播回环）不代表真实 A 机 Civ6 一定可达该路径` | **PASS**（R-1 前置声明保留） |
| D-3 | §5 标题 run-20261117-012424 PASS 17/17；断言 A0-A14c；语义说明 R-2/R-3；文件数 51；代码身份三哈希 | L85-126：标题、A0-A14c、恒等式（A13==25）、51 文件（顶层 3+agent 48，evidence-sha256 49 条不含自身与 stop）、summary 关键值、rejected/fixture 语义说明、三哈希（含旧 release 作废注）全部齐备且与实测一致 | **PASS** |
| D-4 | §6 登记链为版本号/项号引用（不嵌 README/HANDOVER 哈希） | L137/L146-147：`登记链引用不含本文件哈希，避免循环依赖；两文档的当前 sha256 以各自文件实测为准`；README 以 **v1.26 修订记录块**、HANDOVER 以**第 17 项**引用 | **PASS** |
| D-5 | 全文档无残留哈希（E80366CE / 45C46F23 / F13F9AA5 / EBE4D066 / D2F7BA2E） | 全仓 grep **0 命中** | **PASS** |
| D-6 | B1 文档实测 sha256 == `902FA2761BB32AB65F62D578CB86C67E96AB1F3D014CC89B2A131B6541FAF293` | 实测 12,915B / `902fa2761bb32ab65f62d578cb86c67e96ab1f3d014cc89b2a131b6541faf293` —— **与断言完全一致，无偏差** | **PASS** |
| D-7 | README v1.26 修订块引用 B1 文档哈希；实测 sha256 记为登记值 | README L3「版本 1.26」、L1346「v1.26 修订记录」、L1365 含 `902FA2761BB32AB65F62D578CB86C67E96AB1F3D014CC89B2A131B6541FAF293` 字面量；README 实测 117,433B / **`b183c60ad8969b705113b29351bfdd5b4cc8ad93838db8d552c262b833ef90fd`**（登记值） | **PASS** |
| D-8 | HANDOVER 第 17 项引用 B1 文档哈希；实测 sha256 记为登记值 | L125 第 17 项含 `902FA2761BB32AB65F62D578CB86C67E96AB1F3D014CC89B2A131B6541FAF293` 字面量（另含 012424 PASS 17/17 数值、三哈希、边界声明）；HANDOVER 实测 39,890B / **`b5e551621e7990fc4fe14d4d6a9669937ed26daeb990f4e8af7fbb1fa1718b02`**（登记值） | **PASS** |
| D-9 | 单向引用一致性 | README/HANDOVER 引用 B1 文档当前哈希（字面量 902FA276）；B1 文档不嵌 README/HANDOVER 哈希（避免循环依赖）——单向链成立 | **PASS** |
| D-10 | RUNBOOK 重写（R-1 落实的一部分） | `docs/B1-DUALMACHINE-RUNBOOK-20261117.md`（v2，89 行）实测存在：§0 发送形态取证前置（L31-54）、覆盖范围限定（L25-29，含「P1 不是确定性全覆盖」）、判定口径用三态语义（L72-74）、边界登记（L84-89，含「机械证据不代表真实 A 机 Civ6 一定可达」） | **PASS** |

**低 severity 发现（描述性尺寸字段陈旧，哈希均正确）：**
- **L-1（低）**：README L1365 与 HANDOVER L125 均称 B1 文档「定稿 12,933B」，实测 12,915B（哈希 `902FA276…` 正确）——尺寸字段陈旧 18B。
- **L-2（低）**：B1 文档 §5 L87 称自检脚本「18,431B，366 行」，实测 19,592B、366 行（行数正确；脚本 mtime 01:24:04 早于运行 01:24:29 与文档 01:33:42，写作时即与实盘不符）。

## 5. E 边界

| # | 要求 | 实测 | 结果 |
|---|---|---|---|
| E-1 | 不得宣称「双人真实联机已验证」 | 全仓 grep：`双人真实联机已通过/已验证` 等正面表述 **0 命中**；仅否定/禁令形式出现（README L791「不得标"双人真实联机已通过"」、L1344-1345 边界声明等） | **PASS** |
| E-2 | 不得宣称 E2-B/E3 完成 | 无正面「E2-B 完成 / E3 完成」；README L4/L1368-1369、B1 文档 L24、HANDOVER 第 17 项尾部均维持「不勾 E2-A/E2-B/E3」 | **PASS** |
| E-3 | 不得宣称 Gate A 批准 / M0-B 解除冻结 | 无正面表述；三处登记文档均维持「Gate A 未批准、M0-B 冻结」 | **PASS** |
| E-4 | 012424 机械证据（本机回环+合成帧）不得表述为真实 A 机 Civ6 一定可达 P1/P2 | B1 文档 L61、RUNBOOK L89 均明确否定（「不代表真实 A 机 Civ6 一定可达该路径」）；文档 L43/RUNBOOK L27「不是确定性全覆盖」 | **PASS**（R-1 降级后表述完整保留） |

## 6. 必改项清单

- **无阻断/高/中必改项**（首轮 R-1 高、R-2 中、R-3 中全部闭合）。
- **建议修正（低，非阻断）**：
  1. **L-1**：README v1.26 块与 HANDOVER 第 17 项的 B1 文档尺寸由 12,933B 改为实测 12,915B（哈希 902FA276 不变）。修改后 README / HANDOVER 自身的 sha256 将变化，需按新实测值重新登记。
  2. **L-2**：B1 文档 §5 脚本尺寸由 18,431B 改为实测 19,592B（366 行不变）。修改后 B1 文档哈希将变化，需同步更新 README / HANDOVER 的引用哈希并重测三文档。

## 7. 实测哈希总表

| 文件 | 大小 | sha256（实测，小写） | 说明 |
|---|---|---|---|
| civlink\agent\src\main.rs | 121,851 | `2687401cecdf2d5679f037ddca6e4434685efabf6a4ff94a6e9dbcabe8a419e7` | 与任务/文档断言精确一致 |
| civlink\agent\target\debug\civlink-agent.exe | 868,352 | `69cd012e24ac6758550348d4eb5d46c5ea6cb86e667d205f454416be1187d2ac` | 与任务/文档断言精确一致 |
| civlink\agent\target\release\civlink-agent.exe | 417,792 | `ddaf5453b35377493aba4f464adfc341a153861cec1352d97f07fbbe21113d63` | 与任务/文档断言精确一致 |
| docs\B1-REAL-ADVERTISEMENT-CAPTURE-20261117.md | 12,915 | `902fa2761bb32ab65f62d578cb86c67e96ab1f3d014cc89b2a131b6541faf293` | 与任务/README/HANDOVER 断言一致（README/HANDOVER 的 12,933B 尺寸字段陈旧，见 L-1） |
| README.md（v1.26） | 117,433 | `b183c60ad8969b705113b29351bfdd5b4cc8ad93838db8d552c262b833ef90fd` | 登记值（本次实测） |
| docs\CODEX-HANDOVER-M0A.md | 39,890 | `b5e551621e7990fc4fe14d4d6a9669937ed26daeb990f4e8af7fbb1fa1718b02` | 登记值（本次实测） |
| docs\reports\b1\run-20261117-012424\result.txt | 54 | `dbf12e88b8e204d667d6928bd76e93f7dc6aa72aac04c54d995ff2d9d56ee4f5` | PASS (17 checks, 0 failures) |
| docs\reports\b1\run-20261117-012424\agent\summary.txt | 3,562 | `ae56ebb0b51c5303492cb152e4057a0d90e21d5b4a472b8538eeabcaeb269f38` | 关键值全对账 |
| docs\reports\b1\run-20261117-012424\agent\real-ad-manifest.txt | 2,266 | `821f78e9d0b277e714c6a6f75f87673ea9309fa61ed8b40249c6423846c002fe` | 22 页 |
| docs\reports\b1\run-20261117-012424\agent\real-page-01.bin | 1,104 | `ddc8cd34d85eb43b218f6a4db8b6867ecfb9c703623b69c3aaf7a93d8d6d99e8` | 房名字段 `dingzihan2022`（A6 判别力） |
| docs\reports\b1\run-20261117-012424\agent\real-page-22.bin | 1,104 | `6f98152dfe665a778b21a64c5033bc41ec48a914e81a39f6ad420ff0c4647fd9` | 与 manifest/evidence 一致 |

（证据目录其余文件哈希以 `evidence-sha256.txt` 为准，本次抽查 5 项全部与清单重算吻合。）

## 8. 结论

1. **修正落实**：R-1（P1 单播覆盖高估）以「文档降级 + RUNBOOK v2 重写 + 双机验证前置实测发送形态」方式闭合，§3 P1/P2 表述保留降级后口径；R-2/R-3（语义错标）以 `CaptureOutcome`/`ReplyOutcome` 三态枚举 + 拆分计数在源码层闭合，`replies_skipped` 与「发送失败→Skipped」路径均落实（S-4/S-5）。
2. **新证据成立**：012424 的 result/summary/清单/页文件/帧日志逐项对账一致；rejected=0、fixture=0、skipped=99 的语义与修正后的代码路径吻合；A6 因真实房名与匿名房名字节差异而具备真实判别力。
3. **登记链一致**：README（v1.26）/HANDOVER（第 17 项）单向引用 B1 文档当前哈希（902FA276 字面量一致），B1 文档不嵌引用方哈希避免循环依赖；残留旧哈希 0 命中；三哈希代码身份精确匹配。
4. **边界完整**：无任何越界宣称，机械证据的真实可达性限定表述在文档与 RUNBOOK 中完整保留。
5. 遗留仅为 2 项低 severity 尺寸字段陈旧（L-1/L-2），建议修正并同步重测三文档哈希后归档。
