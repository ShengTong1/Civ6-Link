# M0-B 双机真实验证（E2-B 结案）审计裁定报告

- 审计对象：CivLink-M0A 项目 M0-B Discovery Adapter 方案，E2-B 双机真实验证（结案轮）
- 审计依据：`docs/M0B-DUALMACHINE-AUDIT-BRIEF-20261117.md`（任务书，5 个审计维度）
- 判定口径：`docs/M0B-DUALMACHINE-RUNBOOK-20261117.md` §5
- 审计日期：2026-11-17
- 审计范围：A 机 agent 归档证据（4 文件）、A 机 out-dir 现场取证、B 机用户口述归档、登记链材料（README / HANDOVER / 验证报告 / 计划）
- 审计方法：归档副本独立 SHA256 复核 + out-dir 与归档交叉比对 + 源码时间戳语义核验 + 计数内部自洽性检查 + 判定口径逐条对照
- 审计局限：PC-B 已离线（ping 超时），无法补测；B 侧 civtrace 日志缺失。对缺失项如实登记，不虚构。

---

## 1. 审计裁定

**裁定：有条件通过（Conditional Pass）**

**一句话结论**：M0-B Discovery Adapter 的**发现链路**证据链完整成立（B 机可见 A 机真实房间名、agent 应答路径端到端有效）；但 RUNBOOK §5 全口径 PASS 要求「B 见真实房名 + B 成功加入」两项，其中**「加入 / 数据面直连」从未实际执行**（B 机离线前用户未加入），故不满足全口径 PASS，裁定为**有条件通过**。若将 E2-B 拆分为「发现链路段」与「加入/数据面段」分段登记，则**发现链路段 = 通过**，加入/数据面段 = 待验证。

**理由**：
1. B 见真实房名成立：用户口述 m26254/m26306（逐字引述，见 §3-2）；agent 侧 bind fail=1 的机器事实佐证 A 机游戏持有 62900 端口（即游戏自身应答路径存在）。
2. agent 应答路径端到端有效：m26472（A 无真实房时 B 可见虚拟房 CivLink-Test-Room-2222）+ agent 计数（requests seen 1179 / replied sockets 12 / pages sent 264，内部完全自洽：1179−12=1167 skipped 全为去重，send fail=0 / no endpoint=0 / max reached=0）。
3. 不满足全口径 PASS 的唯一阻塞项 = 「加入」未验证：RUNBOOK §5 PASS 定义要求「B 成功加入」，本轮用户未执行加入（B 机离线），且 B→A 数据面直连（62056）无任何证据。此缺失为**执行未发生**（非失败、非造假），属环境限制。
4. 因此：全口径 PASS 不成立 →「有条件通过」；条件 = 完成加入/数据面验证（PC-B 恢复后），或按分段登记方式将 E2-B 拆分为「发现链路结案 + 加入/数据面待验证」。

---

## 2. 必改 / 建议列表

### 2.1 必改（M-1..M-5，不落实不得宣称 E2-B 全结案）

| # | 必改项 | 理由 |
|---|--------|------|
| M-1 | **加入/数据面验证**：PC-B 恢复后执行「B 加入 A 真实房间 → 数据面 62056 双向通信」验证并归档证据；在此之前，一切登记只能表述为「发现链路通过、加入/数据面待验证」，**不得宣称 E2-B 全结案** | RUNBOOK §5 PASS 需「B 成功加入」；plan §1 结案目标含数据面双向通信；本轮该段无证据 |
| M-2 | **填写验证报告** `docs/M0B-DUALMACHINE-VERIFICATION-20261117.md`：目前仍是模板（「待执行后填写」未填）。须填入执行记录、证据清单、裁定（有条件通过）、边界登记；并**修正文档头过时的 RUNBOOK 哈希引用**（现写 5381B/EE1BCC9F…，实际应为 6561B/76FC2165DE7E…） | 验证报告是结案登记链的核心载体；哈希引用失真会破坏单向引用链的完整性 |
| M-3 | **README v1.32 修订块登记**：登记双机验证执行结果，内容须含：裁定（有条件通过）、证据哈希（见 §4 表）、边界（见 §5），以及「下一步：加入/数据面验证（PC-B 恢复后）」 | README v1.31 修订块仍写「下一步：双机真实验证」，与已执行状态脱节；边界必须同步登记防误读 |
| M-4 | **更新 HANDOVER 第 19 项状态**：从「双机验证待执行」改为「双机验证已执行（2026-11-17，裁定：有条件通过，发现链路通过、加入/数据面待验证）」并引用证据目录/哈希 | HANDOVER 是跨会话交接的唯一事实源，状态失真会导致后续会话重复执行或误判结案 |
| M-5 | **结论来源分级登记**：所有登记材料中明确 B 口述 = D 级口述证据（m26254/m26306/m26472），agent 机械计数（1179/12/264）= 机械证据，**机械证据 ≠ 双人验证**；并登记「A 侧 hook 注入状态未归档」（RUNBOOK §5.5 项 3 缺失，本轮 datagrams=0，无 civlink_ctl status 输出） | 防止把机械计数宣传为双人验证；hook 注入状态缺失影响真实页应答路径的证据完整性 |

### 2.2 建议（S-1..S-6，非阻塞）

| # | 建议项 | 说明 |
|---|--------|------|
| S-1 | `user-observations.txt` 中区分「用户口述（逐字引述）」与「执行者推断（CONCLUSION 段）」 | 当前二者同文件混存；CONCLUSION 段（同源 IP 去重推断）是执行者分析而非用户原话，应标注 |
| S-2 | 归档用户观察的**时间戳**（现仅 message refs，无时刻） | 加强 A 侧时间戳与用户操作时序的独立复核能力 |
| S-3 | 将 B 侧截图 / B 侧 civtrace client log 提升为**必要证据**（RUNBOOK §5.5 现为「可选」） | 本轮 B 侧仅剩口述；加入/数据面验证必须有 B 侧观测证据 |
| S-4 | 记录 m26254 中「即使不需要 Agent，现在 B 依旧可以搜到 A 创建的真实房间了」的观察 | 真实房可见性可能不依赖 agent（游戏自身应答）；agent 增量贡献本轮未量化（无 agent 有无对照），「消除 1/100 窗口」声明不得写入本轮结论 |
| S-5 | README/验证报告注明「run time 12:58:53.930」为 **UTC 退出时刻**（源码 `wallclock_stamp()` 语义），本地窗口为 2026-11-17 20:28:53→20:58:53（UTC+8） | 防止后续审计把 UTC 时刻误读为本地开始时间 |
| S-6 | 未归档的 out-dir 次要产物（frame-log.txt 仅表头、lan-fixture-manifest.txt、lan-page-01..22.bin）在登记材料中注明存在与未归档 | 保持证据完整性可追溯 |

---

## 3. 逐维度审计记录

### 维度 1 — A 证据真实性

**结论：真实、自洽、时序一致。** 无造假迹象。

1. **哈希复核**：归档目录 4 文件 SHA256 全部独立复核，与任务书声明的前 16 位一致（见 §4 表）。out-dir（`C:\Users\dd\Desktop\civlink-f1\m0b-adapter-a-20261117-202853\`，28 文件）中 summary.txt、agent-stderr.txt 哈希与归档副本**完全一致**（忠实拷贝，无篡改）。
2. **requests seen / replied 语义自洽**：requests seen=1179（agent 监听 62900..62999 收到的发现魔法包总数，按 (源IP,源端口) 去重后 replied sockets=12，即 12 个 B 侧不同临时源端口批次）；pages sent=264 = 12×22（每 socket 应答 22 页 fixture）；replies skipped=1167 = 1179−12（全部为去重命中）；send fail=0 / no endpoint=0 / max reached=0 / replied≤budget 20 → 计数内部零矛盾。
3. **bind fail=1 语义**：agent 启动时 0.0.0.0:62900 被 A 机游戏占用（os error 10048），回退绑定 62901。这是**机器事实**，独立证明 A 机游戏在本窗口内持有 62900 发现端口（真实房应答路径存在于游戏自身）。
4. **时间戳一致性**：summary「run time 12:58:53.930」经源码核验（`civlink/agent/src/main.rs` L2006 `run time = wallclock_stamp()`；L1322-1338 `wallclock_stamp()` 用 `SystemTime::now()` → **UTC**）= UTC 退出时刻 = 本地 20:58:53；listen window 1800.2s 与 `--listen-seconds 1800` 一致；out-dir 文件全部 created 20:28:53、summary written 20:58:53 → 窗口 = 20:28:53→20:58:53 本地。agent 窗口覆盖用户刷新操作（replied sockets=12 对应 B 侧多次刷新）。**唯一缺口**：用户观察本身无归档时间戳（仅 message refs），时序一致性依赖执行者记录，建议 S-2。
5. **运行二进制确认**：summary 中「reply source 0.0.0.0:62901 (actual bound socket)」为 S-2 修复后的输出格式（v1.31 二进制 033D7741617828B4…），证实本轮使用 README v1.31 登记的已重编译 agent。

### 维度 2 — B 证据真实性

**结论：口述证据完整、逐字归档；B 侧机器证据缺失为环境限制而非造假。**

1. **口述记录完整性**：`user-observations.txt` 含 3 条逐字引述（m26254 / m26306 / m26472），语义与 A 侧机械证据互相印证（见 §1 理由 2）。
2. **B 侧 civtrace 缺失的处置**：任务背景记载 B 侧 civtrace 曾注入（pid 4880 / 14188），但 **B 机现已离线（ping 超时），无任何 B 侧日志/截图可归档**。审计处置：登记为**环境限制（数据不可得）**，不视为证据造假；同时如实登记「B 侧机器证据缺失」削弱了发现链路证据的独立可复核性（现仅剩口述单源，属 D 级证据）。RUNBOOK §5 的 PASS 判定接受「B 口述」作为判据之一，故发现链路成立不受影响；但加入/数据面段缺 B 侧证据即缺一切证据（M-1）。
3. **区分口述与推断**：文件末尾 CONCLUSION 段为执行者推断（Civ6 LAN 列表按源 IP 去重、虚拟房被真实房隐藏等），**非用户逐字原话**。推断与观察一致且合理，但按证据分级属分析结论，建议 S-1 标注。

### 维度 3 — 判定口径（对照 RUNBOOK §5）

| RUNBOOK §5 判据 | 本轮事实 | 判定 |
|----------------|---------|------|
| B 见真实房名（A 侧 captured≥1/active=yes **或** B 口述） | A 侧 captured=0/active=no；但 B 口述成立（m26254「B 依旧可以搜到 A 创建的真实房间了」、m26306「只能看到一个真实房间」） | ✅ 满足（经口述路径） |
| B 成功加入 | **未执行**（用户未加入，B 机离线） | ❌ 未验证 |
| 加入卡住 → 部分 | 不适用（无加入动作） | — |

- 发现链路段：**通过**（口述 + agent 计数 + bind fail=1 三重印证）。
- 加入/数据面段：**未验证**（执行未发生）。
- 全口径 PASS：**不成立** → 裁定「有条件通过」（§1）。
- 说明：A 侧机械判据 captured≥1/active=yes 本轮不满足（captured=0），但 RUNBOOK §5 设计为「或」关系，B 口述已满足该子项；此点必须在登记材料中如实写明，不得反向宣称「A 侧 captured=22」之类的达标值（验证报告模板中写有 captured=22 的示例性 PASS 条件，本轮未达成）。

### 维度 4 — 边界登记（详见 §5）

### 维度 5 — 登记链

**结论：登记链三处缺口，均需按 M-2/M-3/M-4 补齐。** 登记方式须为**单向引用、不嵌互引哈希**（详见 §6）。

1. 验证报告 `M0B-DUALMACHINE-VERIFICATION-20261117.md` 仍为模板，且文档头 RUNBOOK 哈希引用过时（5381B/EE1BCC9F… vs 实际 6561B/76FC2165DE7E…）。
2. README 版本 1.31（2026-11-17），v1.31 修订块仍写「下一步：双机真实验证」→ 需 v1.32 修订块登记。
3. HANDOVER 第 19 项（L146-152）状态仍为步骤 1-6 完成 + 「双机验证待执行」→ 需更新。

---

## 4. 证据哈希表

证据目录：`M0A\captures\M0B-dualmachine-20261117\`（归档，4 文件）。全部哈希由审计方独立复核，均与任务书声明一致。

| 文件 | 大小 (B) | SHA256（全 64 位） | 前 16 位 | 复核 |
|------|---------|--------------------|----------|------|
| agent-32348-summary.txt | 3,248 | 85E72E63C761F6F561FF3D1A4426D8005B4F615443B5E297E497C3FDC34167CE | 85E72E63C761F6F5 | ✅ 一致 |
| agent-32348-console.txt | 0 | E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855 | E3B0C44298FC1C14 | ✅ 一致（空文件，=标准空输入哈希，与 0 字节一致） |
| agent-32348-stderr.txt | 257 | 4CBDFD55074C01E8AAD35B193B3CF56118BEC10F03D960C7BACD185DC86BEF39 | 4CBDFD55074C01E8 | ✅ 一致（单行：62900 bind 失败 os error 10048，端口回退提示） |
| user-observations.txt | 1,072 | 76BC00FC4E222849C7085D1EC599AA66AA65A6B8502F7A5630F61FD811C92E1D | 76BC00FC4E222849 | ✅ 一致 |

A 侧 out-dir 交叉比对（`civlink-f1\m0b-adapter-a-20261117-202853\`）：
- summary.txt 与 agent-stderr.txt 哈希 == 归档副本（忠实拷贝确认）。
- 文件时间戳全部 2026-11-17 20:28:53，summary 写入 20:58:53（1800.2s 窗口）。
- frame-log.txt 仅表头（无 hook 帧，与 datagrams=0 一致）；无 real-page-*.bin / real-ad-manifest.txt（与 captured=0 一致，源码 main.rs L1928-1960 仅 pages 非空才写）；lan-page-01..22.bin（各 1,104B）+ lan-fixture-manifest.txt（fixture 目录 `civlink-f1\fixture-reply-set`，房名偏移 24..46 匿名化）。

关键 summary 数值（agent-32348-summary.txt）：requests seen=1179 / replied sockets=12 / pages sent=264 / replies fixture=12 / replies skipped=1167 / send fail=0 / no endpoint=0 / max reached=0 / bind fail=1 / captured=0 / rejected=0 / duplicates=0 / noise on disc=0 / replies real=0 / active=no。

---

## 5. 边界登记

以下边界必须随 E2-B 登记材料（README v1.32 / HANDOVER #19 / 验证报告）同步登记，防止越界宣传：

1. **机械证据 ≠ 双人验证**：agent 计数（1179/12/264）与自检 14/14 只证明应答机制正确，不代表「双人成功联机」；双人验证的充分判据是 B 见真实房名 + 成功加入 + 数据面通信（本轮仅完成前半）。
2. **虚拟房间同 IP 去重 = Civ6 客户端行为，非 civlink 缺陷**：B 机 LAN 列表按源 IP 去重，A 机真实房（192.168.31.60:62900）与 agent 虚拟房（同 IP 62901）同源 → 真实房存在时虚拟房被客户端隐藏。本轮观察（m26472：A 有真实房 → B 看不到虚拟房；A 无真实房 → B 可见虚拟房）与该推断一致。此行为登记为客户端行为，与 plan §7/runbook §6 预期（可能两条房间记录）的差异亦应注明（实际=仅一条真实房）。
3. **agent 真实页应答路径本轮未演示**：captured=0 / active=no / replies real=0 → 本轮 12 次应答全为 fixture 广告页（CivLink-Test-Room-2222）；真实房可见性来自**游戏自身应答**（62900 socket，bind fail=1 佐证），不来自 agent 的 captured 路径。真实页应答能力仍依赖 B1 轮证据，不得以本轮声明。
4. **加入 / 数据面直连未验证**：B→A:62056 双向通信无任何证据（M-1）。
5. **不证明**：对局完整性、长稳（本轮仅 1800.2s 单窗口）、跨网（Radmin VPN/WLAN 之外未测）、Noise 加密通道。
6. **agent 增量贡献未量化**：m26254 用户原话含「即使不需要 Agent，现在 B 依旧可以搜到 A 创建的真实房间了」——真实房可见性可能不依赖 agent；本轮无 agent 有无对照，「消除 1/100 窗口」等声明的依据仍在 F5/机制证据，不得写入本轮结论（S-4）。
7. **A 侧 hook 注入状态未登记**：datagrams=0 说明本窗口无 hook 帧，但无 civlink_ctl status 归档（RUNBOOK §5.5 项 3 缺失），无法从证据侧确认注入状态（M-5）。
8. **B 侧机器证据缺失**：civtrace 曾注入（pid 4880/14188）但无归档输出；PC-B 离线属环境限制；B 侧证据仅剩 D 级口述（S-3）。
9. **E2-A / E3 / Gate A 复核另行登记**：本报告只覆盖 E2-B 双机发现链路；E2-A、E3、Gate A 的状态不在本报告结论中，需各自独立登记。
10. **时间戳语义**：summary「run time」为 UTC 退出时刻（非本地开始时刻），本地窗口 2026-11-17 20:28:53→20:58:53（S-5）。

---

## 6. 登记链要求（单向引用，不嵌互引哈希）

- **方向**（一律单向，禁止 A→B 与 B→A 互嵌哈希形成环）：
  - `README.md` v1.32 修订块 → 引用验证报告、本审计报告（REVIEW）、证据目录哈希；
  - `CODEX-HANDOVER-M0A.md` 第 19 项 → 引用验证报告、本审计报告、证据目录哈希；
  - `M0B-DUALMACHINE-VERIFICATION-20261117.md`（填写后）→ 引用本审计报告裁定 + 证据哈希；
  - 证据文件 → 由上述登记材料引用其哈希；证据文件本身不反向引用登记材料。
- **引用内容**：每次引用须含「文件名 + 大小(B) + SHA256 前 16 位」；REVIEW 报告的自身哈希由 README/HANDOVER 引用时记录（本报告 §4 的哈希表仅指向证据文件，不指向登记文档）。
- **防循环规则**：登记文档引用审计报告时写审计报告的哈希；审计报告引用登记文档时**只写文件名与版本**（如 README v1.32），不写其哈希。
- **更新触发**：M-1（加入/数据面验证）完成后，验证报告/README v1.32/HANDOVER 需再开一轮修订块，登记新证据哈希与最终裁定（届时方可宣称 E2-B 全结案）。

---

## 7. 附：审计材料清单（供追溯）

- 任务书：`docs/M0B-DUALMACHINE-AUDIT-BRIEF-20261117.md`
- 判定口径：`docs/M0B-DUALMACHINE-RUNBOOK-20261117.md`（6,561B，SHA256 76FC2165DE7E395DECE72EFC42C63BE8960132CBB314537EFC471001E4415060）
- 计划 v1.1：`docs/M0B-FINAL-PROGRAM-PLAN-20261117.md`（6,269B，SHA256 737D349FC877EC2D2A1BB543F7FCF6FA1812C597728568094BA08E1F45928FE0）
- 前置审计：`docs/M0B-ADAPTER-SELFTEST-REVIEW.md`（裁定：通过，必改 0，建议 S-1..S-5）
- 验证报告（模板，待填）：`docs/M0B-DUALMACHINE-VERIFICATION-20261117.md`（3,319B，SHA256 AB2FF88DBA48D6DA196CA2F86CBCCE01799B79BC7F450FB27DAAA28B11EDB7AE）
- 登记载体：`README.md`（v1.31，2026-11-17）、`docs/CODEX-HANDOVER-M0A.md`（第 19 项）
- 证据目录：`M0A\captures\M0B-dualmachine-20261117\`（4 文件，哈希见 §4）
- A 侧现场：`C:\Users\dd\Desktop\civlink-f1\m0b-adapter-a-20261117-202853\`（28 文件）

---

*审计基于现有证据（PC-B 已离线无法补测）；缺失项（加入/数据面、B 侧 civtrace、A 侧 hook 注入状态）已如实登记，未虚构。本报告未修改任何源文件；仅新增本文档。*
