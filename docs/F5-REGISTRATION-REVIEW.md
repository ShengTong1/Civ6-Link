# F5 收尾登记一致性审计报告（F5-REGISTRATION-REVIEW）

- **审计时间**：2026-11-15（Asia/Shanghai）
- **审计角色**：civlink 项目独立审计官（子代理）
- **审计方式**：只读审计。用 PowerShell 独立重算（SHA256 / 字节数 / BOM / 控制字符），独立核对磁盘目录与文件存在性，独立全文比对三文件关键块；除本报告外未修改任何被审文件。
- **工作目录**：`C:\Users\dd\Desktop\injciv6-v0.3.3`

---

## 0. 审计对象与身份实测（独立重算，不引用声称值）

| 文件 | 声称 sha256 | 实测 sha256 | 声称字节 | 实测字节 | BOM | tab/vt/ff | 结论 |
|---|---|---|---|---|---|---|---|
| `CivLink-M0A-audit\README.md` | `25295F4432B8ACD1F9D076B1268B8AC13048A62AD9006B597660F209A4B3B539` | **完全相同** | 104,697 | 104,697 | 无 | 0/0/0 | 命中 |
| `CivLink-M0A-audit\docs\CODEX-HANDOVER-M0A.md` | `2DD825D637DFA7C5C2A113FCD1717654DEF1FD621459900952506FD81042198C` | **完全相同** | 33,834 | 33,834 | 无 | 0/0/0 | 命中 |
| `CivLink-M0A-audit\docs\F5-LAN-SIMULATED-HOST-20261115.md` | `6BB383F64394856A28887368339B35CC2588F641388492C047240955505C5472` | **完全相同** | 7,829 | 7,829 | 无 | 0/0/0 | 命中 |

对照基准（历史登记，实测仅供参考）：`F5-LAN-SIMULATED-HOST-REVIEW-2.md` = 12,485B / `CE191F51…FD9DD`；`CIVINJECT-UNIFY-REVIEW.md` = 6,608B / `1D40B37F…D89F7`；`F4-BETA-REVIEW.md` = 16,201B / `3678417D…DB36E`。

---

## A. 身份 — **PASS（6/6）**

| 检查项 | 结果 |
|---|---|
| 三文件 sha256/字节独立重算命中声称值 | **PASS**（见 §0 表，逐字节相同） |
| 三文件无 BOM | **PASS**（首字节非 EF BB BF） |
| 三文件无控制字符 tab/vt/ff | **PASS**（实测 0/0/0；无其他 C0 控制字符） |
| README 无「版本：1.20」残留 | **PASS**（grep `版本：1\.20` 0 命中；L3 版本行为 **1.21**（2026-11-15）） |
| README 无旧哈希 `48017EAB` 残留 | **PASS**（grep 0 命中） |
| CODEX-HANDOVER 更新时间行已是 2026-11-15 | **PASS**（L3「更新时间：2026-11-15」） |

---

## B. README v1.21 修订记录块（L1221–1237） — **PASS（4/4，附 2 项信息说明）**

**① F5 条目（L1222–1228）— PASS**
- `--sim-lan-listen IP` 机制描述与 F5 文档 §2 逐字一致：绑定 0.0.0.0 全部发现端口 62900..62999、直接接收 Civ6 客户端发现广播（magic 8D-E8-FC-70）、从 `<ip>:62900` 应答 22 页 fixture、不依赖原生广播选路/接口 metric/防火墙手工放行 ✓
- 三类证据目录名与磁盘真实目录名一致且全部存在（位于仓库根 `M0A\captures\`，与 F4/E2A 历史证据同一约定）：
  - `F5-lan-selftest-20261114-192000`（实测 52 文件，与 F5 文档 §3.1 声称一致）✓
  - `F5-lan-broadcast-selftest-20261115-b`（29 文件，agent 侧）✓
  - `F5-lan-broadcast-selftest-20261115-c`（51 文件，客户端侧，与 REVIEW-2 D 节实测一致）✓
  - `F5-bprobe-mechanical-20261115`（26 文件）✓
- 文档名 `docs/F5-LAN-SIMULATED-HOST-20261115.md` 存在 ✓
- 审计闭环表述「F5-LAN-SIMULATED-HOST-REVIEW.md 有条件通过→必改 4 项修正→REVIEW-2 复审通过」与两份审计报告一致：REVIEW.md L169 裁定**有条件通过**；REVIEW-2 L156 裁定**通过（PASS）**、必改项**无** ✓

**② 双机核验包条目（L1229–1231）— PASS**
`C:\Users\dd\Desktop\civlink-f5-kit\` 存在，实测哈希全部命中声称前缀：
- `civlink-agent.exe`：`194E6E8A00080B0F05AF14D8754F38CACE818CFC0FE667BB1E0375400D23DA92` / 404,992B ✓（kit、`civlink\`、`civlink-f1\`、`agent\target\release\` 四处完全一致）
- `run-f5-b-probe.ps1`：`FF4DDF3FE71639E6204A853B8F36FB810158802C1F321670B398FBFAFDFE57D0` / 7,244B ✓
- `run-f5-dualmachine-a.ps1`：`D909D16F034F006B167285C33FFB83DCFBC411EBE9582B27E3A7CF14A22B444B` / 7,926B ✓
- `PC-B-操作单.md`：存在（3,187B；哈希 `FF6679E9…E96` 与 F5 文档 §4 表一致）✓
- B 机一次性核验描述（UAC 一次机械探测或 Civ6 局域网刷新看 `CivLink-Test-Room-2222`）与 F5 文档 §4 一致 ✓

**③ civinject 条目（L1232–1234）— PASS**
- 引用文档 `docs/CIVINJECT-UNIFY-REVIEW.md` 存在，其最终裁定为**通过（PASS）**、必改项 0 ✓
- 三处 `civinject.exe`（`CivLink-M0A-audit\civtrace\`、`C:\Users\dd\Desktop\civlink-run\`、`M0A\pcb-kit\`）实测全部 = `54627EABB15E203DE6112C8908B74E0714F0B8FA04567E2298B395534A700DF6` / 171,520B ✓
- 备份两处实测存在且一致：`civlink-run\civinject.exe.bak-4DCC9557` 与 `M0A\pcb-kit\civinject.exe.bak-4DCC9557` 均 = `4DCC9557…` / 171,520B ✓
- 「字节级差分证明新旧版仅 COFF 构建时间戳不同」与 UNIFY-REVIEW 追加核验一致（全文件仅 6 字节不同 = PE 头 0xF8 与文件偏移 0x24194 各一次的时间戳低 3 字节）✓

**④ 边界声明（L1235–1237）— PASS**
- 覆盖声明「模拟房主→真实客户端跨机发现链路」与 F5 文档 §5 一致 ✓
- 不证明清单（双人真实对局、E2-B 双端注入、62056 数据面、Relay RTT、Fake-IP、Noise、跨网/长稳）与 F5 文档 §5、HANDOVER L123 一致 ✓
- 不勾 E2-A/E2-B/E3、不移动 Gate A/B（Gate A 未批准，M0-B 冻结）与 L4 状态行、F5 文档 §5 一致 ✓

信息说明（不影响 PASS）：
- **I-1**：README kit 条目未列举 `run-f5-lan-selftest.ps1 80C0935D…` 与 `fixture-reply-set\`（HANDOVER 与 F5 文档 §4 表已列）。kit 中两件均实测存在（selftest 8,842B/`80C0935D…`；fixture-reply-set 顶层 25 文件，与 F5 文档「25 文件」一致）。README 为枚举子集，无冲突。
- **I-2**：README v1.21 以**文档名**引用 F5 文档而未附其哈希（`6BB383F6…` 仅 CODEX-HANDOVER L123 引用全值）。无任何矛盾哈希，属引用粒度差异。

---

## C. CODEX-HANDOVER 第 16 项 F5（L123） — **PASS（4/4）**

| 检查项 | 结果 |
|---|---|
| 插入位置：第 15 项 F4（L121）之后、`## 5`（L125）之前 | **PASS**（F5 项独占 L123，与上下文无穿插） |
| 编号连续（13→14→15→16） | **PASS**（L104/13、L113/14、L121/15、L123/16） |
| 内容与 README v1.21 一致性：`194E6E8A…`（全值 `/404,992B`）、`FF4DDF3F…`、`D909D16F…` 两处一致 | **PASS**（README L1229-1230 与 HANDOVER L123 相同前缀/尺寸；全值经实测命中，见 §B②） |
| F5 文档哈希 `6BB383F6…` 与真实文档一致 | **PASS**（HANDOVER L123 载全值 `6BB383F643…C5472` = 实测值；README 未附该哈希，见 I-2） |
| 边界声明与 README 一致 | **PASS**（不证明 7 项清单、不勾 E2-A/E2-B/E3、不移动 Gate A/B、Gate A 未批准 M0-B 冻结，两处逐项同口径） |

---

## D. 交叉一致性 — **PASS（5/5，附 1 项信息说明）**

| 检查项 | 结果 |
|---|---|
| README/HANDOVER 引用的 F5 文档哈希 `6BB383F6…` = 真实 F5 文档哈希 | **PASS**（HANDOVER 全值 = 实测 `6BB383F64394856A28887368339B35CC2588F641388492C047240955505C5472`） |
| F5 文档内不再含旧哈希 `472FA16C` / `105EC490` | **PASS**（grep 0 命中；亦无 `4AA1FF4E`/`48017EAB`/`60 页` 残留） |
| REVIEW-2 结论（**通过 PASS**、必改项**无**，L152-156）与 README/HANDOVER「复审通过」表述一致 | **PASS** |
| F5 文档 §6「已同步 civlink\、civlink-f1\、civlink-f5-kit\（civlink-f4 保留 F4 构建 E276ECA3…）」属实 | **PASS**（`civlink\`、`civlink-f1\`、kit 三处 agent 均 `194E6E8A…`/404,992B；`C:\Users\dd\Desktop\civlink-f4\civlink-agent.exe` 实测 `E276ECA307F9…F7660`/402,944B，与文档注一致） |
| F5 文档 §3.1 证据目录文件数（52）与 §3.2 客户端侧证据（-c 51 文件、22 页 24,288B）与磁盘一致 | **PASS**（52/51 文件实测命中；24,288 = 22×1104 成立，REVIEW-2 D 节已逐字节核验） |

信息说明：
- **I-3**：现 F5 文档 `6BB383F6`/7,829B 比 REVIEW-2 审计对象 `4AA1FF4E`/7,701B 新（+128B）。该修订即落地 REVIEW-2 的低/信息级建议：P3-1（§4/§6 旧哈希 `472FA16C`→`D909D16F`）、P3-2（-b 轮加注「客户端侧未留存」）、P4-2（2558→2559 行）、P4-4（f4 保留 `E276ECA3` 注）。REVIEW-2 明示上述项「不影响本次通过裁定，建议后续顺带修正」，实测新版已全部落地且无旧引用残留，复审通过结论对新版仍成立。另：REVIEW.md 必改项清单载 **5** 条目（第 5 项为信息级 D5：selftest 脚本头注 8→12），REVIEW-2 及 README/HANDOVER 按 **4 项必改**口径（仅计中/低级 D1-D4）；D5 未落地（REVIEW-2 P4-1 注明仍残留），属信息级口径差异，不影响通过。

---

## E. 边界 — **PASS（3/3）**

| 检查项 | 结果 |
|---|---|
| 三文件无「双人真实联机已验证 / F5 即 E2 完成 / Gate 已移动」式越界宣称 | **PASS**（全文 grep：所有「双人真实/勾掉」均出现在否定边界句；无任何正面宣称） |
| 维持「Gate A 未批准，M0-B 冻结」 | **PASS**（README L4/L1237、HANDOVER L123、F5 文档 §5 L112 三处一致维持） |
| F5 完成度表述如实 | **PASS**（README「双机核验包就绪」、F5 文档 §7「待 B 机开机执行」；证据全部标为 A 机机械/回环，B 机核验未宣称已完成） |

---

## 缺陷分级

| 级别 | 编号 | 内容 |
|---|---|---|
| 阻断 | — | 无 |
| 高 | — | 无 |
| 中 | — | 无 |
| 低 | — | 无 |
| 信息 | I-1 | README v1.21 kit 条目未列举 `run-f5-lan-selftest.ps1` 与 `fixture-reply-set\`（HANDOVER/F5 文档已列；两件实测存在），属枚举子集 |
| 信息 | I-2 | F5 文档哈希 `6BB383F6…` 仅 CODEX-HANDOVER 引用，README v1.21 以文档名引用未附哈希，无冲突 |
| 信息 | I-3 | 现 F5 文档为 REVIEW-2 审计对象（4AA1FF4E）之后的修订版，修订内容 = REVIEW-2 低/信息建议（P3-1/P3-2/P4-2/P4-4）全部落地；「必改 4 项」为 REVIEW-2 口径，REVIEW.md 清单另含信息级 D5（仍未落地，REVIEW-2 P4-1 已注明） |

## 必改项清单

**无（0 项）**。三处登记（README v1.21、CODEX-HANDOVER 第 16 项、F5 文档）哈希/字节/内容/边界全部如实、自洽、无越界宣称；REVIEW-2 遗留低/信息项已在 F5 文档新版顺带落地。

## 最终裁定：**通过（PASS）**

- A 身份 6/6、B v1.21 修订记录 4/4、C HANDOVER 第 16 项 4/4、D 交叉一致性 5/5、E 边界 3/3，全部 PASS；
- 无阻断/高/中/低缺陷，必改项为空；3 条信息说明（I-1/I-2/I-3）均不影响通过裁定；
- 三文件登记与其背后的磁盘证据（证据目录、kit、civinject 三处+备份两处）完全一致，无任何哈希或数值出入。

（审计官注：全部结论由本次会话独立重算得出；审计过程只读，除本报告外未改动任何文件。）
