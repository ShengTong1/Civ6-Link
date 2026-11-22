# M0-E Discovery Completion — 第二轮复审报告（REVIEW-2）

- 审计员：独立复审代理（重派轮，前次运行 37fcf3f4 三次失败无产出，本轮从头执行）
- 日期：2026-11-19
- 任务书：docs\M0E-REVIEW-2-BRIEF-20261119.md（7,046 B / SHA-256 AFF58DD838253F3022C00B40458E51C9506A5E7582CA114A32E1F2FF2A6E8614，实算一致）
- 上轮报告：docs\M0E-REVIEW.md（41,207 B / SHA-256 158A3C35…，实算一致，裁定 NOT PASS：阻断 2 / 高 4 / 中 5 / 低 6）
- 被审对象：civlink\src\main.rs（SHA-256 E56A3056…，与任务书/变异轮 pristine 一致）、civlink\agent\Cargo.toml、设计文档 M0E-DISCOVERY-COMPLETION-20261118.md v2.0（21,021 B / B8626DE5…）
- 本报告性质：只读审计产物；审计过程未修改除本文件外的任何文件。

---

## 1. 裁定

**裁定：PASS（有条件通过）。**

- 上轮两条阻断（B-1 源 IP 过度承诺、B-2 去重缺失）均已在实现侧修复，且修复证据齐备、可复算、与设计 v2.0 回写内容一致（见 §2、§4）。
- 硬约束逐条核验通过：agent 永不 bind 0.0.0.0:62056（自检 45/45 含该项；C1-reserve 12/12、C1-combo 14/14）；f a i l-closed 语义成立（空页→GameSilent 拒绝转发）；civlink\agent\Cargo.toml [dependencies] 为空（15 行文件实读确认）；构建 --offline 与零依赖自洽。
- 新发现无阻断级、无高危级：2 项中危（均为文档口径，见 N-1/N-2）、4 项低危（N-3~N-6）。不影响 M0-E 代码与证据的技术有效性。
- "有条件"指：§6 所列 3 项放行条件（其中条件①为 N-1 证据目录口径的限期文字修正）须在下一次文档回写时关闭；不要求改代码。

关键数字：13/13 必读文件哈希实算一致；自检 45/45 PASS；变异 5/5 caught；B2 修复复测 replays sent 1 / duplicate magic 98 / forwarded 22；三接口 pinned=true 全部成立；nightly 8 文件 + zip 哈希全对。

---

## 2. 上轮发现逐条关闭核验（A 组，7 项）

| # | 上轮发现 | 严重度(上轮) | 关闭证据 | 本轮核验结论 |
|---|---------|------------|---------|------------|
| A-1 | B-1 源 IP 过度承诺：设计宣称回包"保证=房主 IP"，但源 IP 由路由决定 | 阻断 | main.rs mod egress（行 576-968）：WSARecvMsg/WSASendMsg + IP_PKTINFO（IPPROTO_IP=0、IP_PKTINFO=19，GUID 字节手写正确）；send_from 以被探测目的地址反查 IN_PKTINFO 并钉 if_index；pin 失败回退 send_to 并计 egress_unpinned。设计 v2.0 §0.1/§5.3 已改口为"按被探测目的地址钉源 + 回退计数"，不再承诺保证 | **关闭。** 设计语义已修正；三接口实测证据 M0E-B1-egress-20261119-0055（wlan 192.168.31.60 / radmin 26.74.126.98 / zerotier 192.168.191.3）均 pinned=true、pinned_port_ok=true、distinct_sources 单一。残留风险（钉源失败回退）已由设计 §8.6 如实登记为未验证项，见本轮 B-4 |
| A-2 | B-2 去重宣称存在但实现没有：99 magic × 22 页 = 2.41 MB 灌入 64 KB 缓冲 | 阻断 | CompletionState.answered: BTreeMap<(u32,u16),Instant>（main.rs 1081-1138）；handle 中预算检查（1178 replies>=max_replies→BudgetExhausted）→ 去重（1188/1192）→ clear_backlog（1143-1154）→ 单次重放 → 收集循环以 from==game_addr 严格相等过滤（1230）+ 墙钟 deadline（1224）。修复复测 M0E-B2-fixed-20261119-0002：requests seen 99 / replays sent 1 / duplicate magic 98 / pages collected 22 / forwarded 22；修复前对照 M0E-B2-probe-20261118-2350（replays 99 / pages 2178 / forwarded 2178），B2-confirmation.txt 1,760 B / SHA-256 E2A4774B6B682C7E… 与设计 §10 一致 | **关闭。** 机制存在、行为可测、修复前后对照数字自洽（99→1/98dup、2178→22） |
| A-3 | H-1 game-discovery-addr 校验缺失 | 高 | validate_game_discovery_addr（main.rs 2606-2616）强制 loopback；CompletionState 构造再次校验（1112-1116） | **关闭。** 双重校验，非 loopback 拒绝启动 |
| A-4 | H-2 参数语义/默认值未定义 | 高 | parse_args：--completion-cooldown-ms 0..=60000 默认 750（2460-2464）；--completion-max-pages 1..=256；--completion-max-replies 1..=100000 默认 1000；交叉规则（2568-2600）：completion 需 --sim-lan-listen、拒 --simulate、互斥 --sim-real-capture、强制 --reserve-62900。设计 §5.1 六参数表与实现一致 | **关闭。** 边界值语义见本轮 B-6（cooldown=0 合法但需文档标注） |
| A-5 | H-3 反射放大风险未评估 | 高 | 设计 §0.1/§7 登记 6072× 反射放大边界（22 页 × 276 字节答复 vs 1104 字节探测，同接口 loopback 语义下成立）；实现侧 max_replies 预算 + cooldown + 单次重放限制放大面 | **关闭（含边界声明）。** 放大仅在 Agent 自有端口/loopback 游戏场景成立，设计已如实声明 |
| A-6 | H-4 --reserve-62900 强制缺失 | 高 | 交叉规则 2591-2596：completion 模式缺 --reserve-62900 拒绝启动；C1-reserve-20261119-0041 PASS 12 checks、C1-combo PASS 14 checks（verdict 含脚本/agent sha 自证） | **关闭。** GUI 供建 235 行始终拼 --reserve-62900，组合一致（本轮 C-4） |
| A-7 | 中/低项（M·L）：可见性、文档回写、GUI 组合、nightly 登记 | 中/低 | 设计 v2.0 §0.1 处置对照表逐条登记；summary 输出含 duplicate/budget/backlog/egress_pinned/egress_unpinned/recv_errors 计数行（B2-fixed summary 实证格式存在）；nightly dist\civlink-20261119-nightly 8 文件 + zip 哈希全与 MANIFEST.txt 一致 | **关闭（C 组细项见 §3/§8）。** 其中 stale 轮标注一项部分满足（N-2） |

---

## 3. 新发现（N-x）

**N-1（中，文档口径）：证据目录口径矛盾 — 采信轮证据不在任务书/设计宣称的"项目根 M0A\captures"。**
设计 §10 与任务书称证据主目录为项目根 `injciv6-v0.3.3\M0A\captures\`；实际 20261119 采信轮（completion / mutation / B2-fixed / B2-probe）全部位于审计仓库内 `CivLink-M0A-audit\M0A\captures\`，项目根 M0A\captures\ 仅含 B1-egress / regress / C1 / gui 系列。两个目录都存在且都有效，但登记口径与实际存放位置不一致，第三方按设计 §10 索引会找不到 completion/mutation/B2 证据。不阻断（哈希本身已逐一实算一致，证据真实性不受影响），要求按 §6 条件①限期修正设计 §10 的路径表述。

**N-2（中低，流程标注）：stale 自检轮未做文字标注。**
M0E-completion-20261119-002511-FAILED-setup（33/39，failed=1）与 -002605（39/39，修复前代码轮）目录仍保留，目录名含 `-FAILED-setup` 信号、verdict 无"不采信/SUPERSeded"文字标注；设计/上轮 REVIEW 亦未明确点名这两轮为 stale。39-check 轮被 45-check 版本自然取代，风险低，但审计追溯时需靠目录名推断。要求在 verdict 或设计 §10 补一行"不采信"标注（§6 条件③）。

**N-3（低，任务书侧笔误）：两 selftest exe 路径。**
任务书必读清单写 `civlink\selftest\hook_selftest.exe` / `client_selftest.exe`；实际在 `civlink\` 根（150,016 B / SHA-256 15482B7D…DEF1137；182,272 B / 50B69B27…77EAECB，均实算一致），`civlink\selftest\` 目录仅含 .cpp 源。哈希无差异，属任务书路径笔误，登记备查。

**N-4（低，数字口径）：自检证据文件数 42 vs 30。**
任务书/设计称自检证据 42 文件，实测 M0E-completion-20261119-003732 目录 30 文件。差额与 run1-4 子目录展开计数方式吻合（按文件计 30、按"文件+目录内条目"计可达 42），不影响 verdict 45/45 的有效性；建议统一计数口径（§6 条件③一并处理）。

**N-5（低，编码瑕疵）：GUI selftest 输出 gate 行 mojibake。**
gui-m0e-20261119-0052 的 selftest 输出中 gate 行出现"锟斤拷"双序列，系控制台编码（GBK/UTF-8 混用），不影响断言计数与 PASS 判定。建议脚本统一 `[Console]::OutputEncoding`。

**N-6（低，行为提示缺口，与 B-2/B-3 合并观察）：冷却窗内二次请求无应答且无面向用户的文档说明。**
见 §5 B-2/B-3。行为本身正确（summary 有 duplicate_magic 计数，可见性达标），缺的是设计层面对用户的说明文字。

---

## 4. 证据核验（实算明细）

本轮 SHA-256 实算 ≥30 次，覆盖任务书 13 必读文件全部 + 证据抽查。要点：

1. **必读 13 文件**：13/13 哈希与任务书一致（设计 v2.0 B8626DE5…、main.rs E56A3056…、agent exe 15321D49…、REVIEW.md 158A3C35…、4 个审计脚本、GUI 说明 5,091 B/A63D143F…、NIGHTLY 说明 2,850 B/8F01E954…、两 selftest exe 15482B7D…/50B69B27…）。两 exe 路径笔误见 N-3。
2. **自检 M0E-completion-20261119-003732**：verdict 45/45 PASS（5 场景 × 9 断言）；manifest 抽查 4 项实算全对（verdict.txt E23B1D88…、summary-run1 738DC376…、summary-run4 9D64FB68…、client-recv-01 11AF1983…）。文件数口径见 N-4。
3. **变异 M0E-mutation-20261119-003243**：5/5 caught（M1 破坏 fail-closed / M2 换转发 socket / M3 重放两次 / M4 禁用钉源 / M5 去掉冷却窗），每条附变异源哈希；pristine main.rs sha 与 E56A3056… 一致；变异后 restored selftest 复跑 PASS（还原完整性成立）。
4. **B2 前后对照**：M0E-B2-probe-20261118-2350（修复前 replays 99 / pages 2178 / forwarded 2178）↔ M0E-B2-fixed-20261119-0002（replays 1 / dup 98 / pages 22 / forwarded 22 / budget 0 / backlog 0）；B2-confirmation.txt 1,760 B / E2A4774B6B682C7E… 与设计 §10 一致（实算）。
5. **B1 钉源 M0E-B1-egress-20261119-0055**：wlan/radmin/zerotier 三 JSON 均 pages=22、distinct_sources 单一、pinned=true、pinned_port_ok=true，首包 38.96/73.33/69.26 ms，与设计 §4.6 表逐项一致。
6. **回归与约束**：regress-20261119-0055 TRIAGE——hook_selftest 6 失败定位为游戏占用 62056 的环境冲突（需游戏关闭复跑），client_selftest exit=2 为调用方式（argv[1]=DLL 目录），九场景三参全 PASS，结论"无产品回归"自洽；C1-reserve 12/12、C1-combo 14/14。
7. **GUI 与 nightly**：civlink_tray.cs 39,608 B / SHA-256 F1A4B7E46D017DFE60F09DA57985CA772DEA207A70DF0AE361F72EFEE0FC5979（实算）；gui-m0e selftest 40/40、mutation M6 3 FAIL 恰中 real-room 三断言；nightly dist\civlink-20261119-nightly 8 文件（agent/hook/client/ctl/tray/relay/MANIFEST/VERSIONS）+ zip 哈希全对；fixture-reply-set 29 文件 88,156 B 一致。

---

## 5. 主动风险（B 组，8 项）

**B-1（clear_backlog 竞态）— 结论：安全，有轻微丢页面。**
backlog drain（1143-1154，非阻塞循环）发生在重放之前；forward socket 为全局单例，backlog 中可能残留另一客户端上一轮的页。drain 只丢弃、不转发 → 不会误转给错误客户端（安全方向正确）；代价是极端并发下另一客户端的页被丢、需其自身下一轮 magic 触发补全。多客户端并发补全未在证据中覆盖（设计 §8 未验证项已登记），M0 阶段单房主场景可接受。

**B-2（750ms 冷却窗）— 结论：行为正确，可见性达标，文档说明缺失。**
elapsed<cooldown→Duplicate（1192-1196），重放失败也先占冷却位（1216-1217，防重放风暴，设计正确）。第二次刷新间隔 <750ms 时客户端收不到任何应答且无提示；summary 有 duplicate_magic 计数（运行侧可见），但设计未向最终用户说明"750ms 内重复发现请求静默忽略"。与 N-6 合并，要求文档补一句（§6 条件②）。

**B-3（max_replies 可见性）— 结论：通过。**
预算耗尽计 BudgetExhausted 且 summary 有 budget exhausted 行（B2-fixed summary 格式实证）；--completion-max-replies 默认 1000 足够覆盖单房主 99 magic 场景。

**B-4（钉源失败回退的源 IP 去重风险）— 结论：设计如实登记，M0 可接受。**
send_from 失败回退 send_to（1292-1311，计 egress_unpinned）时回包源 IP 由路由决定，可能不等于被探测目的地址。但本轮去重键是 (client_ip, client_port)（客户端侧），收集过滤键是 from==game_addr（游戏侧 loopback），均不依赖回包源 IP → 不会因回退产生错误去重或漏收。真正的残留风险是"客户端收到的源 IP 不是房主 IP"的语义问题，设计 §5.3/§8.6 已登记为未验证项（egress_unpinned 计数可观测），M0 接受。

**B-5（--completion-cooldown-ms 0 边界）— 结论：合法但等效关闭去重，需文档标注。**
0 合法（范围 0..=60000，2460-2464）；elapsed<0 恒 false → 每条 magic 都重放，100 包=100 轮重放，BudgetExhausted 兜底（默认 1000）防失控。无死锁/无 panic，fail-closed 语义不受影响。属"用户可自伤"配置，设计未标注，与 §6 条件②一并补一句"cooldown=0 将禁用去重"。

**B-6（场景 4 判别力）— 结论：有判别力。**
场景 4（真实房间补全）断言依赖钉源/去重/过滤链路；M4（禁钉源）与 M3（重放两次）变异均被 caught，证明断言对实现输出敏感、非同义反复。判别力成立。

**B-7（recv_with_dst 路径耦合）— 结论：无问题。**
completion 分支专用 egress::recv_with_dst（poll 1481-1597；recv_errors/last_recv_error 可观测，10035→Ok(None) 容错正确）；非 completion 路径仍走 recv_from，无耦合。

**B-8（GUI 组合与 agent 约束一致性）— 结论：一致。**
civlink_tray.cs BuildArgs（行 225）：realRoom→拼 --discovery-completion 且不拼 --simulate（236-244），始终拼 --reserve-62900（235）；自检断言 678-693 覆盖互斥/wildcard/普通路径；gui-m0e mutation M6 3 FAIL 恰中 real-room 三断言，证明 GUI 侧约束有效。

---

## 6. 放行条件（PASS 的前置义务，均不改代码）

1. **①（N-1，限期）**：设计文档 §10 证据路径表述修正为"采信轮证据以审计仓库 `CivLink-M0A-audit\M0A\captures\` 为准，项目根 M0A\captures\ 为 B1/regress/C1/gui 系列"，或统一迁移到单一目录并同步哈希清单。
2. **②（B-2/B-5/N-6）**：设计 §5.1 增补两句：cooldown 窗口内重复请求静默忽略（客户端无感知，计数见 summary）；--completion-cooldown-ms 0 将等效禁用去重，不建议生产使用。
3. **③（N-2/N-4）**：对 002511-FAILED-setup 与 002605 两轮在 verdict 或设计 §10 补"不采信"标注；统一自检证据文件计数口径（30 文件 vs 42 条目）。

三项均为文档/标注义务；完成后无需复审代码，可在下一次常规回写中销项。

---

## 7. 边界声明

1. **机械/模拟证据 ≠ 双人真实联机验证。** 本轮全部采信证据为 loopback 自检、变异测试、GUI 自检、脚本复算与哈希对账；设计 §11 已明确不宣称跨机、真实客户端、E2、Gate。三接口 pinned=true 为同机多接口回环实测，不构成跨网段证明。**真实双人联机（房主+客户端跨机）仍是未验证边界，由设计 §8 登记，属 M1 范畴。**
2. **审计员只读。** 本轮仅写入本报告文件；未运行被审程序（除只读哈希/文本读取），未修改 civlink\ 下任何文件。regress 轮 hook_selftest 6 失败的环境复跑（游戏关闭后）未由审计员执行，依赖 TRIAGE 的自洽性论证。
3. **哈希对账范围。** 设计 §10 哈希带省略号（前 8 后 8），本轮以任务书 64 位全哈希为准实算；凡任务书未给全哈希的证据文件（如 B2-fixed summary 等）以 manifest/内部自证哈希抽查方式核验，未逐文件全量复算 —— 这属于证据清单完整性层面的常规抽查，不构成对抽查外文件的背书。
4. **单机多接口 ≠ 多机。** B1 证据中 radmin 26.x / ZeroTier 192.168.191.x 为本机虚拟接口；钉源结论在这些接口上成立，不外推到任意路由环境。

---

## 8. 建议（不阻断）

1. 将 egress_unpinned / recv_errors / last_recv_error 计入 summary 固定输出行（当前在 counters 可见），降低现场排障成本。
2. clear_backlog 丢页面：在 M1 多客户端设计时考虑按 (client_ip, client_port) 分桶的 backlog 语义，或至少在文档登记"并发多客户端补全可能互相丢页"。
3. 统一所有证据目录的 manifest 计数口径（文件 vs 条目），避免 N-4 类偏差再次出现。
4. GUI selftest 脚本统一设置 `[Console]::OutputEncoding = UTF8`，消除 N-5 mojibake。
5. 下次回写设计文档时同步销项 §6 三条件，并把本报告（M0E-REVIEW-2.md）哈希补入证据清单。

---

*报告完。审计员仅负责本文件；哈希与本报告自身 SHA-256 由回传消息给出。*
