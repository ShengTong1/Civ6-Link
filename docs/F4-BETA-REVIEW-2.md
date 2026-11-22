# F4-BETA-REVIEW-2 · CivLink F4 审计 H1 修正复核 · 独立复审报告

- 审计对象（父代理修正后文件）：
  - `CivLink-M0A-audit\docs\F4-BETA-ACCEPTANCE-20261114.md`（声称 8,513B / SHA256 F02E28AFEC10EC649A1BCBD0379FD995CEB3A11CDC303A7AFA832152693BFE01）
  - `CivLink-M0A-audit\README.md`（声称 102,585B / SHA256 9B53793B012EB74A263109BDDC16CFF5ACB4F338E6A96F7A43143EC229094060）
- 证据真值来源：`M0A\captures\F4-beta-20261114-174214\counters-after.txt`（970B / 6FFCA304…）、`counters-before.txt`（943B / 5DD78B43…）、`summary.txt`、`shutdown.txt`
- 原审计报告：`CivLink-M0A-audit\docs\F4-BETA-REVIEW.md`（16,201B / SHA256 3678417D7810AD2F681960255E90C654F413EA8A0C14946E611552AA650DB36E，裁定有条件通过、必改 1 项 H1）
- 审计方式：只读。除本报告外未修改/写入任何文件。
- 审计时间：2026-11-14（修正复核，与原审计同日）。

## 0 结论摘要

**最终裁定：通过（PASS）。** 必改项 H1 已如实、彻底修正；无新增缺陷。
- 修正后两文件 SHA-256 与字节数用 `Get-FileHash -Algorithm SHA256` 独立重算，与声称值逐字一致（大写、无尾随空格）；均无 UTF-8 BOM、无 tab/vertical-tab/form-feed 控制字符；
- 验收文档 §5 `raw bind=1`、`state queries=3` 与 counters-after.txt 逐字一致；4/2 错误值全文无残留（含 §3/§4/§8/§10 全文档排查）；
- README §3D F4 条目与 v1.20 修订记录③已按审计意见改写；精确串"待排期"/"待审计返回"全文 0 命中；版本行仍为 1.20；
- 边界表述（NOT 双人真实联机 / 不勾 E2-A/E2-B/E3 / 不移动 Gate A/B）两文档均维持，无新增越界宣称；
- 验收文档 §6 39 文件身份表与证据目录 39 文件逐项一致；两文档无互相矛盾的新内容。

**F4 审计 H1 修正复核通过，F4 登记通过约束维持。**

## A 节 身份核实（独立重算）

| 项 | 判定 | 核实结果 |
|---|---|---|
| A1 验收文档哈希/字节 | **PASS** | 独立重算 SHA256 = F02E28AFEC10EC649A1BCBD0379FD995CEB3A11CDC303A7AFA832152693BFE01、8,513B，与声称值逐字一致 |
| A2 README 哈希/字节 | **PASS** | 独立重算 SHA256 = 9B53793B012EB74A263109BDDC16CFF5ACB4F338E6A96F7A43143EC229094060、102,585B，与声称值逐字一致 |
| A3 验收文档 BOM/控制字符 | **PASS** | 首 3 字节 `23 20 46`（"# F"）→ 无 BOM；U+0009/000B/000C 计数 0/0/0；CR=0、LF=124（LF 行尾，无孤立 CR） |
| A4 README BOM/控制字符 | **PASS** | 无 BOM；tab/vertical-tab/form-feed = 0/0/0；CR=1,219 == LF=1,219（CRLF 配对，行尾正常） |
| A5 原审计报告身份 | **PASS** | 重算 = 3678417D7810AD2F681960255E90C654F413EA8A0C14946E611552AA650DB36E、16,201B，与声称一致（复核基准） |

## B 节 H1 数值修正核查（对 counters-after.txt 原文逐字复核）

| 项 | 判定 | 结果 |
|---|---|---|
| B1 raw bind | **PASS** | §5（L59）`raw bind=1` 与 counters-after.txt L22 `raw bind       : 1` 逐字一致；首跑 `F4-beta-20261114-173307\counters-after.txt` 实测 `raw bind : 4`（observed frames=8）→ 确认原 4 系首跑跨轮次串行值，现已更正为 1 |
| B2 state queries | **PASS** | §5（L58）`state queries=3` 与 counters-after.txt L18 `state queries  : 3` 逐字一致；counters-before.txt L18 `state queries  : 2` → 确认原 2 系 before 文件值，现已更正为 3 |
| B3 错误值无残留 | **PASS** | 验收文档全文 grep `raw bind|state queries` 仅 2 命中且均为正确值；无任何 `raw bind=4` / `state queries=2` 残留（§3/§4/§6/§8/§10 亦无）；README 中"4→1、2→3"仅为 v1.20 ③修正说明（历史描述），非残留错误值 |
| B4 §5 其余数值与 counters-after 全表一致 | **PASS** | running=0 / shutdown=1(in-flight=0) / init error=0；sent=300 / send fail=0 / reject oversize=0 / sent notify=0 / ignored=0；scatter-gather=9 / sock overflow=0 / src unknown=3；observed frames=9 / raw sendto=300 / raw wsasendto=9 / raw recvfrom=66；bind 62056=1 / wsarecv pending=0 / cvlh2 try=309 / cvlh2 ok=309 / cvlh2 fail=0 / channel down=0；accounted=300(sent+sendFail+rejectOversize) —— 与 counters-after.txt 33 行逐一吻合（除 I3 注明的 2 项未转录外，无任何不符） |
| B5 §5 shutdown 行 | **PASS** | shutdown.txt 原文含 `CivLinkShutdown returned 0 (clean drain)` 与 `module intentionally LEFT MAPPED until target exit (B2 audit-run mode)`，与 §5 末行一致 |
| B6 §3/§4 联动复核 | **PASS** | §3 断言 9 行（delta=300、300+9==309、received=309、seen=300 replied=3、66==22×3、sendFail=0、exit=0、datapath=9、frames=309/discovery=300/62056=9）与 §4 summary 值在 summary.txt/counters 证据上独立成立，与修正后文档无矛盾 |

## C 节 README 修正核查

| 项 | 判定 | 结果 |
|---|---|---|
| C1 §3D F4 条目（L787-791） | **PASS** | 已改写为"**单机模拟房主验收已通过（2026-11-14，F4-BETA PASS 9/9，证据 `M0A\captures\F4-beta-20261114-174214`，`docs/F4-BETA-ACCEPTANCE-20261114.md`）**，产出只能标'模拟对端/发现助手测试版'，不得标'双人真实联机已通过'"——不再写"待排期" |
| C2 v1.20 修订记录③（L1216-1219） | **PASS** | 已改写为审计闭环说明：必改 1 项 H1=验收文档 §5 两值转录错位（raw bind 4→1、state queries 2→3，值 4/2 出自首跑与 before 文件）**已修正**；独立重算 A1-A4/B1-B6/C1-C3/D1-D3 全 PASS（39/39 文件全 64 位哈希逐项吻合、300+9==309 成立、无双人真实联机正面宣称）；报告引用 `docs/F4-BETA-REVIEW.md` —— 不再含"待审计返回后按必改项补记"占位 |
| C3 占位串 grep | **PASS** | 全文 grep `待排期`、`待审计返回`、`待审计` → **0 命中**（精确串要求满足；L1196"待用户排期"系 v1.19 历史修订记录原文，见 I2） |
| C4 版本行 | **PASS** | L3 仍为 `版本：**1.20**（2026-11-14）`，未升级/回退 |

## D 节 边界表述核查

| 项 | 判定 | 结果 |
|---|---|---|
| D1 验收文档边界 | **PASS** | L5 "**NOT 双人真实联机**，不得据此勾掉 E2-A/E2-B/E3，不移动 Gate A/B"；L13 不证明清单（双机发现/加入/对局、H2/R1 绑定语义、Noise 加密、长稳、跨网）；L14 Gate A 未批准、正式 M0-B/Gate B 冻结；L112 不证明第 6 条明确排除"双人真实联机已通过"表述 |
| D2 README 边界 | **PASS** | L4 "**NOT 双人真实联机**…E2-A 部分完成，E2-B/E3 未完成；Gate A 未批准，M0-B 冻结"；L791 产出只能标"模拟对端/发现助手测试版"；L1200 ⑤Gate A 未批准、M0-B/Gate B 冻结、F3/F4 不得宣传为联机验证；v1.20 记录②（L1213-1215）同口径 |
| D3 无新增越界宣称 | **PASS** | 两文档无任何"双人真实联机已通过/已验证"类正面宣称；无 H2/R1 绑定语义、Relay RTT、Noise、跨网验证宣称；E2-A 仅"部分完成"、E2-B/E3 未完成，均未勾选 |

## E 节 一致性核查

| 项 | 判定 | 结果 |
|---|---|---|
| E1 §6 39 文件身份表 vs 证据目录 | **PASS** | 证据目录实际 39 文件；13 个独立文件 + 22×sim-page.bin + agent-console/relay-console/STOP-agent/STOP-relay = 39，字节数与全 64 位 SHA-256 独立重算逐项一致（22 项 sim-page 均 1,104B；空文件 E3B0C442…）；counters-after/before 哈希 6FFCA304…/5DD78B43… 与 §6 钉死值及本审计独立重算一致 |
| E2 脚本身份联动 | **PASS** | run-f4-beta.ps1 双副本（civlink-f4 与 dist）均为 14,079B / F7B56439… / UTF-8 BOM（EF BB BF）；check-f4-package.ps1 双副本 3,966B / BE45A5FE…，与 §2/原审计 A2/I1 一致 |
| E3 两文档互查 | **PASS** | README（L4/L790/L1212）与验收文档（L3 状态 PASS 9/9、采信 -174214）口径一致；修正后无互相矛盾的新内容；README v1.20 ③"已修正"声明与验收文档实际内容（B1/B2）一致 |

## 缺陷分级

**阻断（Blocker）：0 项**

**高（High，必改）：0 项**（原 H1 已如实、彻底修正，见 B1/B2/B3）

**中（Medium）：0 项**

**低（Low）：0 项**

**信息级（Info）：4 项**
- **I1** 验收文档 §10 修订记录仍仅"2026-11-14 初版"，未补记 H1 修正条目（README v1.20 ③已声明"已修正"）。修正内容本身正确完整，不属 H1 必改范围；建议后续版本补记修订条目以保完整溯源。
- **I2** README v1.19 修订记录③（L1196）仍含历史语句"单机验收（需真实 Civ6 点刷新）待用户排期"——系 v1.19 历史记录原文，非当前状态；当前 §3D 条目（L787-791）与 v1.20 记录均已改写为通过状态。精确串"待排期"全文 0 命中（C3 字面要求满足）。
- **I3** §5 未转录 counters-after 中 `raw wsarecvfrom=225086652` 与 `recv on 62056=225086652`（计数器溢出值，counters-before 对应值为 0）。§5 系"关键值"摘要，未列此项为转录选择而非错误；该值不参与任何断言。
- **I4** shutdown.txt 为 UTF-16LE（FF FE 头，816B，哈希与 §6 一致）；counters-*.txt 带 UTF-8 BOM（PS 5.1 重定向产物）。均属证据文件原始编码，身份表已验证，非缺陷。

## 必改清单（Must-Fix）

无。

## 最终裁定

**裁定：通过（PASS）——F4 审计 H1 修正复核通过，F4 登记通过约束维持。**

- 依据：A1-A5、B1-B6、C1-C4、D1-D3、E1-E3 全部 PASS；无阻断/高/中/低缺陷，仅 4 项信息级备注（均不构成必改）。
- 原 F4-BETA-REVIEW 有条件通过所附登记约束（随 README v1.20 既有口径）继续维持：本验收仅为单机模拟对端/发现助手测试版；**NOT 双人真实联机**；不证明双机发现/加入/对局、Relay RTT、H2/R1 绑定语义、Noise 加密、跨网、长稳；不得据此勾掉 E2-A/E2-B/E3；不移动 Gate A/B。
