# F5 文档 §7 状态维护后的三文件哈希同步 — 审计报告

- 审计日期：2026-11-15
- 审计类型：只读独立审计（唯一写操作 = 本报告）
- 审计对象：F5 文档 §7 末条状态维护（"待收尾登记审计" → "登记审计已完成"）后，F5 文档 / README / CODEX-HANDOVER 三文件的哈希同步一致性
- 方法：Get-FileHash 独立重算 + raw bytes 逐字节分析（BOM / 行尾 / tab / vt / ff）+ .NET UTF8 读取计数 + read 工具全文核读 + grep 残留扫描

## 声称终值

| 文件 | 声称字节数 | 声称 sha256 | 声称行数 |
|---|---|---|---|
| docs\F5-LAN-SIMULATED-HOST-20261115.md | 9,936B | E860914F02B5296383576AA0F1C5278460E9A32E11CE9785209F5631DA7010C8 | 156 |
| README.md | 106,435B | 9D2ACDEADE46FA5B27094C4260F67BC5F3B58B4D56A9A2EA81B9B8219FD32AC6 | — |
| docs\CODEX-HANDOVER-M0A.md | 33,945B | AC34C398A480BFFE22C6BD5BD7E1E54B2A7EFB24F707D06AC58D8E3BB0798A30 | — |

---

## A. 身份核查 — PASS（附 1 条低级发现 L-1）

| 项 | 结果 |
|---|---|
| F5 文档字节数 9,936B | **PASS**（独立重算精确命中） |
| F5 文档 sha256 = E860914F…7010C8 | **PASS**（Get-FileHash 独立重算精确命中） |
| F5 文档无 BOM / tab / vt / ff = 0 | **PASS**（raw bytes：无 EF BB BF 前缀；tab/vt/ff 字节数均 0） |
| F5 文档 156 行 | **PASS（口径注明）**：按换行符切分段 = 156；按行记录（read 工具 / `ReadAllLines(UTF8)`）= **155**，文件以换行符结尾（EndsWithLF=True）。声称值 156 仅在"按 \n 切分含末尾空段"口径下成立；项目既有口径（前次审计 F5-SINGLEHOST-REGISTRATION-REVIEW.md L35/L78 实测"155 行"）为 155 → **L-1** |
| README 字节数 106,435B | **PASS**（独立重算精确命中） |
| README sha256 = 9D2ACDEA…32AC6 | **PASS**（独立重算精确命中） |
| README 无 BOM / tab / vt / ff = 0 | **PASS**（CRLF 行尾，1256 对 CR+LF） |
| HANDOVER 字节数 33,945B | **PASS**（独立重算精确命中） |
| HANDOVER sha256 = AC34C398…98A30 | **PASS**（独立重算精确命中） |
| HANDOVER 无 BOM / tab / vt / ff = 0 | **PASS**（纯 LF 行尾，141 个 LF） |

## B. F5 文档 §7 末条与 §3.4 — PASS

| 项 | 结果 |
|---|---|
| §7 末条含"登记审计已完成" | **PASS**：L155"登记审计已完成（`docs/F5-SINGLEHOST-REGISTRATION-REVIEW.md`，2026-11-15，PASS）。" |
| §7 末条引用 docs/F5-SINGLEHOST-REGISTRATION-REVIEW.md | **PASS**（引用路径存在且即前次审计报告） |
| §7 审计闭环表述 | **PASS**：L154"F5 文档/脚本/机械证据审计闭环（REVIEW → REVIEW-2）；本小节（§3.4 单机验证）" |
| §3.4 小节完整 | **PASS**：方案 C（用户 m19535 选定）、--sim-lan-listen 0.0.0.0、600s 窗口、fixture-reply-set、房名 CivLink-Test-Room-2222、两次口述确认、"刷新了 / 打开了,刷新之后有" |
| §3.4 证据计数 | **PASS**：requests seen=100 / replied=1 / pages=22 / 失败全 0 / exit 0 / stderr 空；summary sha256 A6892BB026E4A0D124D27616ED81BA4D09CCD080B2B27DE44D0D538B1DACE397；lan-page-01..22.bin 与 fixture 逐字节一致 MISMATCH=0；证据目录 30 文件 30,461B，pid 15692 |
| §3.4 证据路径 | **PASS**：M0A\captures\F5-singlehost-20261115-1235 |
| 无"待收尾登记审计"残留 | **PASS**（F5 文档全文 grep `待收尾|待审计` 0 命中） |
| B 机核验关系如实 | **PASS**：§7 L151-152 双机核验包就绪、待 B 机开机执行（m19249/m19615），未越界宣称完成 |

## C. README v1.22 — PASS

| 项 | 结果 |
|---|---|
| L3 版本行 = 1.22 | **PASS**："版本：**1.22**（2026-11-15）" |
| v1.22 修订记录块①中 F5 文档哈希 = E860914F | **PASS**：L1245"F5 文档补 §3.4（E860914F02B5296383576AA0F1C5278460E9A32E11CE9785209F5631DA7010C8，156 行）"全值引用；旧值 13EA3887 已替换 |
| 旧哈希残留 | **PASS**：README 全文 grep `13EA3887|6BB383F6|48017EAB|472FA16C|105EC490` → **0 命中** |
| 单机验证表述与 F5 文档 §3.4 一致 | **PASS**：方案 C/m19535、--sim-lan-listen 0.0.0.0（600s 窗口、fixture-reply-set、房名 CivLink-Test-Room-2222）、两次口述确认、summary 100/1/22/失败全 0/exit 0、证据目录 30 文件、summary sha256 A6892BB0…、B 机核验包（§4）保留——逐项一致 |
| 无 1.21 版本行残留 | **PASS**：grep `版本：1.21` 0 命中；"1.21" 仅出现在 L4（"详见 v1.21 修订记录"指针）与 L1221（v1.21 历史修订记录块标题），属历史引用非版本行（与先前审计口径一致） |

信息级观察（非缺陷）：L4 状态行指针仍写"详见 v1.21 修订记录"，未随版本升至 v1.22——F5 功能首次登记于 v1.21、§3.4 单机验证登记于 v1.22，指针指向首次登记版本与先前审计模式一致，无实质矛盾。

## D. CODEX-HANDOVER — 有条件 PASS（含 1 条低级发现 L-2）

| 项 | 结果 |
|---|---|
| L123 第 16 项 F5 文档哈希 = E860914F | **PASS**：当前引用已替换为 E860914F02B5296383576AA0F1C5278460E9A32E11CE9785209F5631DA7010C8 全值；旧值 6BB383F6 的**当前哈希引用**已替换 |
| L-2（低，本次更新引入） | **FAIL**：L123 历史注"此前 REVIEW-2 审计对象版本为 6BB383F6"与审计链事实不符。F5-REGISTRATION-REVIEW.md L95(I-3) 明确 **REVIEW-2 审计对象 = 4AA1FF4E/7,701B**；6BB383F6/7,829B 系 **F5-REGISTRATION-REVIEW（v1.21 登记）** 对象。完整链：REVIEW 105EC490/6,545B → REVIEW-2 4AA1FF4E/7,701B → F5-REGISTRATION-REVIEW 6BB383F6/7,829B → F5-SINGLEHOST-REGISTRATION-REVIEW 13EA3887/9,867B → 现 E860914F/9,936B（F5-SINGLEHOST-REGISTRATION-REVIEW.md L8）。"6BB383F6" 字面残留仅存于该历史注 |
| 版本/日期与 README 一致 | **PASS**：L3 更新时间 = 2026-11-15，与 README 1.22（2026-11-15）一致 |
| 第 16 项其余内容 | **PASS**：三类机械证据全 PASS（回环自检 12/12、真实广播 22/22 客户端侧 22 页 24,288B、B 侧探测）、审计闭环（REVIEW.md 有条件通过→必改 4 项→REVIEW-2 通过）、双机核验包 civlink-f5-kit、civinject 版本统一审计、边界声明——均命中且无越界 |
| 其余内容无破坏 | **PASS**：L41-140（项目待办、F0-F4 条目、错误路径、文档权威顺序）未发现本次更新造成的破坏；除 L123 外无其他 F5 文档哈希引用 |

## E. 边界 — PASS

| 文件 | 结果 |
|---|---|
| F5 文档 §5（L128-135）+ §2 | **PASS**：不证明双人真实对局、E2-B 双端注入、62056 数据面、Relay RTT、Fake-IP、Noise、跨网/长稳；不得据此勾掉 E2-A/E2-B/E3；不移动 Gate A/B；Gate A 未批准、M0-B 冻结维持；Agent 永不 bind :62056、永不 SO_REUSEADDR |
| README L4 + v1.22 ④ | **PASS**：NOT 双人真实联机、不勾 E2-A/E2-B/E3；E2-A 部分完成、E2-B/E3 未完成；①②均不构成 M0-B 验收或双人真实联机证据；E2-A/E2-B/E3 仍待 PC-B 在线执行；Gate A 未批准、M0-B 冻结 |
| HANDOVER L123 | **PASS**：不证明双人真实对局/E2-B 双端注入/62056 数据面/Relay RTT/Fake-IP/Noise/跨网长稳；不勾 E2-A/E2-B/E3，不移动 Gate A/B（Gate A 未批准，M0-B 冻结） |
| 越界宣称 | **PASS**：三文件均无"双人真实联机已通过"或"M0-B 已验收"类正面宣称 |

## F. 交叉一致 — PASS

| 项 | 结果 |
|---|---|
| README 引用 F5 哈希 = F5 文档实际哈希 | **PASS**：E860914F02B5296383576AA0F1C5278460E9A32E11CE9785209F5631DA7010C8（README v1.22 ①）= 实测值 |
| HANDOVER 引用 F5 哈希 = F5 文档实际哈希 | **PASS**：E860914F02B5296383576AA0F1C5278460E9A32E11CE9785209F5631DA7010C8（L123）= 实测值 |
| README 无 1.21 版本行残留 | **PASS**（同 C 项） |

---

## 缺陷分级

| 编号 | 级别 | 位置 | 缺陷 |
|---|---|---|---|
| L-1 | 低 | README v1.22 ①（L1245）、HANDOVER L123、本次声称终值 | 行数声称 156 行：按 \n 切分段口径 = 156，按行记录口径（read 工具 / ReadAllLines）= 155。项目既有口径为 155（前次审计 F5-SINGLEHOST-REGISTRATION-REVIEW.md L35/L78 实测 13EA3887 版"155 行"），本次更新将 155 改为 156 未同步口径说明。不影响字节数/哈希身份 |
| L-2 | 低 | HANDOVER L123 历史注（本次更新引入） | "此前 REVIEW-2 审计对象版本为 6BB383F6" 与审计链事实不符：REVIEW-2 审计对象为 4AA1FF4E/7,701B（F5-REGISTRATION-REVIEW.md L95 I-3）；6BB383F6/7,829B 为 F5-REGISTRATION-REVIEW（v1.21 登记）对象 |

## 必改项

1. **（L-2，必改）** HANDOVER L123 历史注更正为"此前 REVIEW-2 审计对象版本为 4AA1FF4E（7,701B）；6BB383F6 为 F5-REGISTRATION-REVIEW（v1.21 登记）版本"或等价准确表述。此为审计链事实错误，后续接手代理依 HANDOVER 追溯审计链时会被误导。
2. **（L-1，建议）** README v1.22 ① 与 HANDOVER L123 行数统一回 **155 行**（与项目既有口径一致），或注明"按换行切分段计 156"以避免口径歧义。

## 最终裁定：**有条件通过（PASS WITH CONDITIONS）**

三文件哈希同步核心事实全部成立：三个 sha256 与字节数独立重算精确命中、无 BOM、无 tab/vt/ff；F5 文档 §7 末条已如实更新为"登记审计已完成（docs/F5-SINGLEHOST-REGISTRATION-REVIEW.md，PASS）"且无"待收尾"残留；§3.4 完整且与 README v1.22 ① 逐项一致；旧哈希（13EA3887/6BB383F6/48017EAB/472FA16C/105EC490）在 README/F5 文档零残留，README 与 HANDOVER 引用的 F5 文档哈希均等于 F5 文档实际哈希；边界声明与越界约束在三文件全部如实维持。

附加条件（修正后闭环）：① 按必改项 1 更正 HANDOVER L123 审计链历史注；② 按建议统一行数口径（155）。两处均为低级文字/口径缺陷，不构成登记事实错误，但系本次更新引入，落地修正后（F5 文档哈希将随之变化）需按项目流程再同步一次引用并复核。
