# REV-015 归档复审报告（第二轮，修正后文档只读复审）

- 审计日期：2026-11-14
- 审计方式：只读复审。全部数值独立实测（PowerShell `Get-FileHash -Algorithm SHA256`、`[System.IO.File]::ReadAllBytes`、逐字节控制字符扫描、`Select-String`/`Get-Content` 全文检索），不照抄任务书声称值。未改动任何被审文件。
- 审计人：独立审计子代理（本轮）
- 前置：上一轮审计（子代理 38af7a75）对 README v1.19 裁定不通过，FAIL 三项（F3E-REVIEW-2.md 缺失、§3D 引用无正文、check-f4 "PASS 10/10" 计数不符）。本轮核查修正闭环情况。

## 一、审计对象（修正后）

| # | 文件 | 实测字节数 | 实测 SHA256 | 实测 mtime | BOM/控制字符 |
|---|------|-----------|-------------|-----------|--------------|
| 1 | `README.md` | 100,511 B | `9F113BF210D61446A51907C0CCC6733794729A3B187EBBBE402DC1013E8A6C94` | 2026-11-14 17:21:39 | 无 BOM（首字节 23 20 43 69 = "# Ci"），无 CR/LF/TAB 之外的控制字符 |
| 2 | `docs\CODEX-HANDOVER-M0A.md` | 31,661 B | `ABEC0170A05BA49A9A7B36C691C7787760321F00BA3B6D126879816B4CF1EAAF` | 2026-11-14 17:22:01 | 无 BOM，无控制字符 |
| 3 | `docs\F3E-REVIEW-2.md`（FAIL①闭环件） | 10,166 B | `36DDACE5E8113ECFFE63691F327E3D2AAD78DCA190974D891E81271CBDF57958` | 2026-11-14 17:23:41 | 无 BOM，无控制字符 |

- README 全文 1,199 行；CODEX-HANDOVER 全文 139 行。
- 复审期间对两份审计对象与闭环件二次重算，哈希/字节数/mtime 均稳定，无漂移。

## 二、逐项核查表（含实测证据）

### 核查项 1：哈希与字节数 — ✅ 通过

- README：100,511 B / `9F113BF2…E8A6C94`，与声称值逐字符一致；无 BOM；逐字节扫描无 CR/LF/TAB 之外控制字符。
- CODEX-HANDOVER：31,661 B / `ABEC0170…B4CF1EAAF`，一致；无 BOM；无控制字符。
- 闭环件 F3E-REVIEW-2.md：10,166 B / `36DDACE5…CBDF57958`，一致；无 BOM/控制字符。

### 核查项 2：FAIL① 闭环（F3E-REVIEW-2.md 存在且表述一致）— ✅ 通过

- `docs\F3E-REVIEW-2.md` 现存在（10,166 B，mtime 17:23:41）。
- 其实际裁定：**通过（PASS，11/11，无残余项）**——核查表 11 行全 PASS（M2 §4 采信 -163533、M1 探针改一次性冒烟、L1 E2-stop.txt 6B、L3 400ms、L2 main.rs:584-586、L4 枚举合并 bad+unk、L5 16 文件+E4/、L7 转录注释声明、§0、无旧值残留、哈希/字节一致）；无阻断/高/中/低残余，仅 2 条信息级观察（O1 结果预设式表述、O2 探针陈述不可复核但已声明不引证）。
- README 引用一致性：
  - 修订记录①（L1184-1199 区）："F3E 第一轮有条件通过 10 项必改 → 修订落地 → F3E-REVIEW-2 复核通过"——与闭环件实际裁定一致，无夸大。
  - §3D（L780-784）：F3-E 23/23、采信 `F3E-fault-injection-selftest-20261114-163533`、E-1 fatal/exit 3 真实用例/E-2/E-3/E-4、F3E-REVIEW.md 第一轮有条件通过 + F3E-REVIEW-2.md 修订复核通过——与闭环件一致。
- 结论：FAIL① 闭环成立。

### 核查项 3：FAIL② 闭环（§3D 正文存在且状态行有对应）— ✅ 通过

- README L760 存在 `### §3D F3 直连与 Relay 路径（模拟数据面对端，2026-11-14 五子项审计闭环）`。
- 内容齐备（实测行号）：
  - L762-765：范围声明——loopback 模拟对端、明文无 Noise 无状态机、不得宣传为联机验证、Gate A 未批准、v1.18 Gate 登记。
  - L767-770：F3-A 31 站点/35 次执行，采信 `F3A-forward-selftest-20261114-155041`，F3A-REVIEW-5 通过（前置 F3A-REVIEW-4 有条件通过 6 项低已落地）。
  - L771-773：F3-B revision 3 68/68，采信 `F3B-relay-selftest-20261114-152821`，F3B-REVIEW-3 通过。
  - L774-776：F3-C 26/26，采信 `F3C-backoff-selftest-20261114-160454`(v3)，F3C-REVIEW-3 通过。
  - L777-779：F3-D 40,000×2 帧，Agent 8,035==8,035、Relay 13,214==13,214，采信 `F3D-pressure-selftest-20261114-151218`，F3D-REVIEW 有条件通过 12 项、8 项转正条件全落地（含 Gate 登记）。
  - L780-784：F3-E 23/23（见核查项 2）。
  - L785-786：REV-015 归档（`docs/REV-015-ARCHIVE-20261114.md`，D1-D6，codex 未逐条裁定）。
  - L787-790：F4 发布候选——`dist\civlink-beta-20261114\` 已复制中立目录 `C:\Users\dd\Desktop\civlink-f4\`，agent 0.3.0/relay 0.1.0 均支持 `--version`，check-f4-package.ps1 自检全 PASS，单机验收待排期；产出只能标"模拟对端/发现助手测试版"，不得标"双人真实联机已通过"。
- 状态行（L4）"F3 五子项全部完成且审计闭环，详见 §3D" 与正文 L760 对应成立。
- F3 审计文档裁定交叉核对（支撑 §3D 数值）：
  - F3A-REVIEW-5.md（9,509 B）：裁定"通过"，"31 站点/35 次执行"与脚本 31 行 Check 对齐（29 单次 + 2 负向×3 = 35 次执行）。
  - F3B-REVIEW-3.md（17,749 B）：裁定"通过"，68 项断言三方一致，result PASS (68/68)。
  - F3C-REVIEW-3.md（17,868 B）：裁定"通过（PASS）"，26 处 Check 计数与 26/26 一致。
  - F3D-REVIEW.md（35,627 B）：裁定"有条件通过"，缺陷清单 高2(H-1/H-2)+中4(M-1..M-4)+低6(L-1..L-6)=12 项（即"12 项"来源），最小转正条件=必要条件 8 项（对应"8 项转正条件"）+建议 4 项；覆盖差=判据(a) 62056 忙轮询 Hook 不丢帧未验证归 M0-B（已 Gate 登记）vs (b) 分层计数闭合已验证。F3D 数值（frame-log 8,037 行/8,035 帧、forward-log 16,071、relay-log 13,223/13,214 forward、missing 31,963/40,000=79.91%、26,778/40,000=66.95%）与 README §3D 声称一致。
- 结论：FAIL② 闭环成立。

### 核查项 4：check-f4 计数（"PASS 10/10" 残留）— ✅ 通过

- README 修订记录③ 与 CODEX-HANDOVER 第 15 项均已表述为"**全 PASS（14 项检查，含版本检测/62056 负向护栏/哈希/非平凡体积）**"（或等价），全文两文件 "10/10" 与 "PASS 10/10" 零命中。
- 实测 `check-f4-package.ps1`（3,966 B，dist 与中立目录 civlink-f4 两处同大小同哈希）：恰好 **14 个 Check() 调用**——4×present + fixture reply-01..22 + agent `--version` exit 0 + relay `--version` exit 0 + ctl usage 含 v0.2.0-f2 + relay 拒 `--listen :62056` + relay stderr 点名红线 + agent 拒 `--port 62056` + ctl/dll 非平凡（≥100KB）+ VERSIONS.txt written；另有 4 行 info 哈希打印（非检查）。$fail=0 时输出 `CHECK-F4-PACKAGE: PASS` 并 exit 0。
- 结论："14 项检查"声称与脚本实测一致，残余观察闭环。

### 核查项 5：CODEX-HANDOVER 一致性 — ✅ 通过

- 第 14 项（L113-119）：F3-E 行（L118）="审计闭环（F3E-REVIEW.md 第一轮有条件通过 10 项必改 → 修订落地 → F3E-REVIEW-2.md 复核通过）"——无旧"第二轮审计通过（11/11）"表述，全文档无 "11/11" 命中。
- 第 15 项（L121）与 dist 包事实一致（实测命中）：
  - civlink-agent.exe 382,464 B / `93F1751620C2B83D413AADACD9DA1EB167F4D6ECDCCFECA447AC0D7245E92132`
  - civlink-relay.exe 262,144 B / `9E323F818AF0DE7699F6C3DBA7D29FB786BBC27CDC2F2D5B908E935A7D60C98C`
  - （另实测：civlink_ctl.exe 173,056 B / `23923DFB…FEFEA30`，civlink_hook.dll 119,808 B / `9424FC25…C9CEBC10F`；VERSIONS.txt = agent 0.3.0 / relay 0.1.0 / ctl v0.2.0-f2；实跑 `--version`：agent→"civlink-agent 0.3.0" exit 0，relay→"civlink-relay 0.1.0" exit 0；dist 与中立目录 civlink-f4 四件二进制逐字节一致）
- 结论：第 14/15 项表述合规且与事实一致。

### 核查项 6：表述边界 — ✅ 通过

- 两文件全文无"双人真实联机已通过""联机已验证"式**正面**宣称。
- "双人真实联机已通过"仅出现在否定边界句（README L790、CODEX L121 的"不得标…"）。
- "联机已验证"仅出现在 README L533 禁止表述清单（"不允许的表述：「联机已验证」「Relay 可用」「M0-B 通过」"）。
- 其余"联机验证"命中均为"不得宣传为联机验证"否定句（README L763/L1042/L1172/L1183/L1199、CODEX L113）。
- F3 部分始终标注为模拟/loopback 证据（§3D 范围声明 + v1.19 修订记录⑤）。
- 结论：表述边界合规。

### 核查项 7：版本号一致性 — ✅ 通过

- README L3：版本 1.19（2026-11-14），无 1.18 或更低残留为当前版本。
- "1.18"仅出现在 v1.18 历史修订记录标题与 Gate 登记引用（L765/L779/L1173-L1183/L1187），属历史记录语义。
- 状态行（L4）内容与 v1.19 修订记录一致（F3 五子项闭环、F4 发布候选模拟对端/单机验收待排期、E2-A 部分完成/E2-B/E3 未完成、Gate A 未批准、M0-B 冻结）。
- 结论：版本号一致性成立。

## 三、信息级观察（不构成缺陷，供后续审计参考）

- **I1（对象漂移，需向母代理披露）**：`docs\F3E-FAULT-INJECTION-20261114.md` 在本轮审计开始时 docs 列表显示 12,966 B；现测 **13,002 B**，sha256=`C7D265DD244B37D74D7FB51DFE14F49410431C7910BDAD5681E18DCAE8CFE503`，mtime **2026-11-14 17:24:48**（晚于 F3E-REVIEW-2.md 落盘 17:23:41）。即 F3E-REVIEW-2.md 第 11 项当时验证的 12,966 B/`5A1DF8C6…` 已不对应当前文件（+36 B）。当前文档 §0 L12 与 §9 L195 已预先书写"F3E-REVIEW-2.md（第二轮独立复审，通过 11/11 PASS）"结论。README/CODEX 未引用该文档哈希，故**不影响**两份审计对象的声称，但 F3E-REVIEW-2.md 的哈希核查对当前文件不再成立。建议母代理确认该 36 B 变更来源（疑为审计链事后补写复审结论）。
- **I2**：上一轮审计报告 `docs\REV-015-ARCHIVE-REVIEW.md`（任务书称子代理 38af7a75 产出）在审计树全递归搜索中不存在（docs 目录列表亦无），无法交叉核对上轮 FAIL 清单原文，本轮依据任务书描述复核。
- **I3（口径说明）**：README L783/L1188 与 CODEX L118 的"10 项必改"口径 = F3E-REVIEW.md C 节缺陷清单 10 行（中3+低7，含 M3 元发现非必改、L6 信息级）；F3E-REVIEW.md D 节严格必改实为 8 项。三文档口径一致，且 F3E-REVIEW-2.md（11/11 PASS）为权威闭环记录，不影响结论。

## 四、最终裁定

**✅ 通过（PASS）**

分级清单：
- 阻断级：0
- 高级：0
- 中级：0
- 低级：0
- 信息级观察：3 条（I1 对象漂移 +36 B / mtime 17:24:48；I2 上轮报告文件缺失；I3 "10 项必改"口径说明）

任务书 7 项核查全部闭环；两份审计对象哈希/字节数/BOM/控制字符全部命中声称值；FAIL①、FAIL② 及 check-f4 计数三项旧 FAIL 均已修正落地；表述边界与版本号一致。本报告为只读复审，未改动任何文件。
