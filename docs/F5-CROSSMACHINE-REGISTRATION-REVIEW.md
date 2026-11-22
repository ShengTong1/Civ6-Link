# F5 跨机核验登记文档一致性审计报告（独立审计官）

- 审计时间：2026-11-16 01:1x（Asia/Shanghai）
- 审计类型：只读（未修改任何被审计文件）
- 审计对象：
  1. `CivLink-M0A-audit\docs\F5-LAN-SIMULATED-HOST-20261115.md`
  2. `CivLink-M0A-audit\README.md`
  3. `CivLink-M0A-audit\docs\CODEX-HANDOVER-M0A.md`
  4. 证据目录 `M0A\captures\F5-dualmachine-20261115-pcb3\`（含 `b-side-probe-out\`）
- 方法：PowerShell 独立重算全部哈希/字节数/行数/编码属性（不引用任何声称值）；22 页二进制逐字节比对；关键数值与原始证据文件逐项核对。

---

## A. 身份核验 — PASS（4/4）

| 项目 | 声称 | 实测（独立重算） | 判定 |
|---|---|---|---|
| F5 文档字节数 | 11,797 B | 11,797 B | PASS |
| F5 文档 SHA-256 | 1EFC475193013A5AA10369838632AD2734C5E3275152463F85D03058567784FE | 完全相同 | PASS |
| README 字节数 | 108,318 B | 108,318 B | PASS |
| README SHA-256 | 86243FE0929C11EB8A033A1653385E891D7854E5B4750995231DBF0CDDD39CA3 | 完全相同 | PASS |
| CODEX 字节数 | 34,509 B | 34,509 B | PASS |
| CODEX SHA-256 | 774B498A4F8E59A8F0D3BD5B94CD2670406388C06DDF0AC9B92263C555739201 | 完全相同 | PASS |
| BOM | 无 | 三文件均无（首 3 字节非 EF BB BF） | PASS |
| 控制字符（tab/vt/ff/其他 C0） | 无 | 三文件均为 0 | PASS |
| F5 文档 §3.5 小节 | 存在 | 存在（L106–L127，"跨机核验（B 侧真实执行）— PASS（4 checks，Radmin VPN 通道）"） | PASS |
| F5 文档行数 | 181 行 | 按 LF 分割 = 181 段（含尾部空串）；文件以 `\n` 结尾，LF 计数 = 180 | PASS* |

\* 行数计数口径说明（信息级）：文件以单个 LF（无 CRLF）结尾，`wc -l` 语义下为 180，按行分割语义（含尾部空段）为 181。README v1.22/v1.23 块与 CODEX-HANDOVER L123 均引用"181 行"，三处互一致，与"再补 §3.5 后"的登记版本吻合，故一致性判定 PASS。

---

## B. 数字一致性 — PASS（6/6）

1. **§3.5 声称值 vs `result.txt` 独立重读（全文重读，575 B）** — PASS
   - `F5-B-PROBE: PASS (4 checks)` == 声称 PASS (4 checks) ✓
   - `time : 2026-11-15 23:33:06` == 声称 23:33:06 ✓
   - `burst sent : 100 magic datagrams to 255.255.255.255:62900..62999` == 声称 100 个 magic ✓
   - `reply : 22 pages / 24288 bytes, source 26.74.126.98:62900` == 声称 22 页 × 1104 B = 24,288 B / 应答源 26.74.126.98:62900 ✓（1104×22 = 24,288 数学闭合）
   - `firewall : allow rule added for UDP 54321 ; rule removed` == 声称 UAC 一次加/删 54321 入站规则 ✓
   - `result.txt` 独立重算 SHA-256 = `EBAB78330EA1F077FD3BB7CD8DE9002DAF653B92268564E4F6F1982989F33B91` == §3.5 引用的全值 ✓

2. **22 页 probe-reply vs A 侧 lan-page 逐字节比对（22 对，全部 1,104 B）** — PASS
   - 逐字节差异计数（0 起索引比对全部 1,104 字节）：`0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0`——**22 页全部 IDENTICAL（0 差异）**，与 §3.5"22 页与 A 机 lan-page 逐字节一致"完全吻合。

3. **probe-reply vs fixture `reply-01..22.bin`（`C:\Users\dd\Desktop\civlink-f5-kit\fixture-reply-set\`）** — PASS
   - 每页 21 个差异字节，差异偏移范围全部落在 **24..45**（第 1 页实测差异偏移：24,26,27,…,45；min=24 max=45 count=21）。
   - 偏移 25 无差异原因：房名替换后第 2 字节 'i'（0x69）在两房名中巧合相同（`CivLink-Test-Room-2222` vs `dingzihan2022的游戏`）。
   - fixture 房名实测为 UTF-8 `dingzihan2022的游戏`（13 ASCII + 9 UTF-8 = 22 字节），与任务预期一致。
   - 结论：差异全部落在预期房名匿名化区（24..45），无预期外差异 → §3.5"与 fixture 的 unexpected diffs=0"成立。文档的"24..45"表述**正确**。

4. **README v1.23 修订块（L1262–L1276）与 §3.5 数值一致** — PASS
   - 23:33 / `F5-B-PROBE: PASS (4 checks)` / burst 100 sent / 22 pages × 1104 B / head 59 60 69 9B / room `CivLink-Test-Room-2222` / 应答源 26.74.126.98:62900 / 证据 24 文件 / result.txt EBAB7833…（缩写，合法）——全部与 §3.5 及 result.txt 实测一致。

5. **CODEX-HANDOVER 第 16 项（L123）跨机信息与 README 一致** — PASS
   - 2026-11-15 23:33 / PASS (4 checks) / 26.74.126.98:62900 / 24 文件 / VMware 桥接不通 / Radmin 可用——与 README v1.23 块及 F5 §3.5 完全一致。

6. **三文件关于"跨机核验 PASS / Radmin 通道可用 / VMware 桥接不通"表述一致** — PASS（F5 §3.5、README v1.22 块 L1249 + v1.23 块②、CODEX L123 三方同口径）。

---

## C. 引用链 — PASS（5/5）

1. README v1.23 块（L1269）引用 F5 文档哈希全值 `1EFC475193013A5AA10369838632AD2734C5E3275152463F85D03058567784FE`（181 行）== 实测文档哈希 ✓（v1.22 块 L1246 同值亦为全值 ✓）
2. CODEX-HANDOVER L123 引用新哈希全值 `1EFC475193013A5AA10369838632AD2734C5E3275152463F85D03058567784FE`（181 行）== 实测文档哈希 ✓
3. 旧哈希语义正确（均作历史记录，未作"当前"）：
   - `E860914F02B5296383576AA0F1C5278460E9A32E11CE9785209F5631DA7010C8`：README v1.22 块 L1245 与 CODEX L123 均标注为"2026-11-15 补 §3.4 后（155 行）"的历史版本 ✓
   - `6BB383F6`：CODEX L123 标注"F5-REGISTRATION-REVIEW（v1.21 登记）审计对象版本" ✓
   - `4AA1FF4E`：CODEX L123 标注"REVIEW-2 审计对象版本" ✓
4. README 中 6BB383F6 / 4AA1FF4E **零出现**（无旧审计哈希残留）；无"版本：1.22"任何残留（版本行 L3 为 `版本：**1.23**（2026-11-16）`；"v1.22"仅作为修订记录标题出现，语义正确）✓
5. README 其余 64-hex 哈希（18BBE233/1B24AD55/453F552A/C3D3295F/674E0AFD）经上下文核对均为 F0/E2 脚本哈希，与 F5 文档无关，不构成引用冲突 ✓

---

## D. 边界 — PASS（3/3）

1. **无违规正面宣称**：对三文件 + result.txt 全文扫描"双人真实联机已验证 / 双人联机已通过 / 双人真实对局已验证 / E2-B 已完成 / Gate A 已批准 / M0-B 已验收 / 验收通过 / 真实双机联机完成"等禁止表述：
   - F5 文档：0 命中 ✓
   - result.txt：0 命中（自带 `Simulated-host evidence only: NOT a two-real-hosts multiplayer result, NOT E2-B/E3`）✓
   - README：1 处"验收通过"——上下文为"**v1.20 修订记录（2026-11-14，F4 单机模拟房主验收通过）**…F4-BETA PASS（9/9 断言）…不得宣传为联机验证"，指 F4 **单机**模拟房主验收且紧邻 NOT 声明，语义合法 ✓
   - CODEX：1 处命中为否定句"也不宣称真实双机联机完成" ✓
2. **口径维持**：三文件均维持"不勾 E2-A/E2-B/E3、Gate A 未批准、M0-B 冻结、模拟房主→真实客户端发现链路"表述（F5 §3.5 L126-127 + §5、README L4 + v1.23 块④、CODEX L7/L35/L51/L76/L101/L104/L113/L123）✓
3. **A 侧 summary 缺口如实披露**：F5 §3.5 L122-123（"本窗口 agent 未写 summary…用户 m20220 决定不修复，以 B 侧证据为准"）与 README v1.23 块③同口径；证据目录实测**无 summary.txt**，与披露一致 ✓

---

## E. 证据存在性 — PASS（4/4）

1. `b-side-probe-out\` 共 **24 文件**（22×`probe-reply-01..22.bin` 各 1,104 B + `result.txt` 575 B + `firewall-rule.txt` 45 B）== §3.5/README/CODEX 三方声称 ✓
2. 22 个 probe-reply 字节数全部 1,104 B ✓
3. `result.txt` 内容与 §3.5 引用逐项一致（见 B1）✓
4. A 侧文件全部存在：`lan-page-01..22.bin`（22 个，各 1,104 B）+ `start-cmd.txt`（263 B）+ `agent-pid.txt`（20 B）+ `exit.txt`（40 B）+ `frame-log.txt`（132 B）+ `lan-fixture-manifest.txt`（237 B）+ `STOP-agent`（6 B）✓；`summary.txt` 不存在（已披露缺口）✓

---

## 缺陷清单（按分级）

| 级别 | 编号 | 位置 | 描述 |
|---|---|---|---|
| 阻断 | — | — | 无 |
| 高 | — | — | 无 |
| 中 | — | — | 无 |
| 低 | L-1 | `F5-dualmachine-20261115-pcb3\lan-fixture-manifest.txt`（L4 注释） | 注释写"room name … (anonymized at offset **24..46**)"，实测差异范围为 **24..45**（偏移 46 处无差异；三份文档均写 24..45 且正确）。属证据目录辅助文件的一处注释偏差，不影响文档一致性，建议顺手修正为 24..45。 |
| 信息 | I-1 | F5 文档行数口径 | 声称 181 行：按 LF 分割 = 181（含尾部空段），`wc -l` 语义 = 180（文件以 `\n` 结尾）。README/CODEX 引用同为"181 行"，互一致，无需修改，仅注明口径。 |
| 信息 | I-2 | A 侧 `exit.txt` vs B 侧 `result.txt` 时序 | `exit.txt`：`AGENT_EXITED_AT=2026-11-15 23:30:36`，早于 `result.txt` 的 23:33:06 约 2.5 分钟。文档已披露 agent 主 socket 提前退出路径与 A 侧缺 summary，但未对两时间戳先后作出解释。§3.5 全部数值均直接取自 result.txt 且实测一致，故不构成数值不一致；建议在文档补一句时序说明（如：probe 在 agent 存活期内完成、exit 时间为 agent 收尾记录），避免读者误读。 |

---

## 必改项清单

**无**（无阻断/高/中缺陷）。L-1 与 I-1/I-2 均为建议项，不影响登记有效性：
- 建议 1（低）：修正 `lan-fixture-manifest.txt` 匿名化偏移注释 24..46 → 24..45。
- 建议 2（信息）：F5 文档可注明 181 行按含尾部空段计。
- 建议 3（信息）：F5 文档 §3.5 补一句 exit.txt（23:30:36）与 result.txt（23:33:06）的时序说明。

---

## 最终裁定：**通过**

- 三文件哈希/字节数/编码属性全部与声称值精确一致（独立重算，零偏差）；
- §3.5 声称值与 B 侧 `result.txt` 原始证据逐项吻合；22 页 probe-reply 与 A 侧 lan-page 逐字节一致（0 差异），与 fixture 的差异仅落在房名匿名化区 24..45（unexpected diffs=0 成立，fixture 房名 `dingzihan2022的游戏` 确认）；
- 引用链闭合：当前哈希 1EFC4751… 全值引用正确，旧哈希 E860914F/6BB383F6/4AA1FF4E 均以历史语义出现，无"版本：1.22"残留；
- 边界口径全部维持：无任何"双人真实联机已验证 / E2-B 完成 / Gate A 批准 / M0-B 验收"违规宣称；不勾 E2-A/E2-B/E3、Gate A 未批准、M0-B 冻结、模拟房主→真实客户端发现链路口径一致；A 侧 summary 缺口如实披露；
- 证据存在性完整：b-side-probe-out 24 文件、A 侧 22 页 lan-page 及相关文件全部在位。

登记可作为"跨机核验（F5 §3.5，B 侧 Radmin VPN 通道）已完成并登记"的正式依据继续推进；三项建议项不阻塞。
