# M0D — CivLink 开源发布骨架「修复轮」独立复审（COMPLIANCE-REVIEW-2）

- 审计对象：`CivLink-M0A-audit` 开源发布骨架修复轮（上轮裁定后的项目侧修复）
- 上轮报告：`docs/M0D-OPENSOURCE-COMPLIANCE-REVIEW-20261118.md`（20,955 B / 133 行 / SHA-256 `47c65d86…f50b5d`，含项目侧 2026-11-18 19:36 追加的 §6 修复记录）
- 本轮被审文件（8）：`LICENSE`、`docs/LICENSE-DOCS.md`、`THIRD-PARTY-NOTICES.md`、`CONTRIBUTING.md`、`SECURITY.md`、`README.md`、`docs/CODEX-HANDOVER-M0A.md`、上轮合规报告自身；并核验 `docs/M0D-RELEASE-READINESS-20261118.md` 与 `docs/M0D-OPENSOURCE-PLAN-20261118.md` §9.1/§7.2
- 审计方式：全部结论来自磁盘实读与实算（每个哈希自行重算）；未采信任何口述或文档自述

---

## 1. 裁定

**PASS**（就「修复是否真实、正确、无新增阻断问题」这一轮的审计对象而言）。

一句话结论：项目侧所声明的修复**全部真实存在且逐位可复算**——N-1 的 HDE32/HDE64 的 Patkov 署名已正确载入且行号指向经实读吻合，N-3/N-4 的 README 编码瑕疵已消除并复算吻合，未关闭项（N-2 与修正项 3/4）均**如实标注为未关闭**、没有伪装成已解决；因此**「开源发布骨架就绪」可以宣布（yes）**，但「首次公开发布」仍不成立（`NOT READY`），须先补齐 `SECURITY.md` 联系渠道、落盘署名裁定、统一白名单对外口径、订正断链结论。

裁定维度拆解（两维度不可混淆）：

| 维度 | 裁定 | 说明 |
|---|---|---|
| 开源发布**骨架**就绪 | **yes** | 5 个合规文件 + 第三方声明 + 边界语齐备，N-1（唯一曾「阻断公开发布」项）已关闭 |
| 首次**公开发布**就绪 | **no**（`NOT READY`） | 与 `docs/M0D-RELEASE-READINESS-20261118.md` §1/§3 一致：重打包、SECURITY 渠道、P0/C4 未结案均未完成 |
| 把机械证据当双人联机验证 | **禁止** | Gate A 未批准、`双人真实联机未验证` 前提保留，本轮 6 个被审文件全部保留该边界语 |

`allow_open_source_skeleton_ready = true`（维持上轮取值，本轮独立复核后确认取值成立）。

---

## 2. 逐条关闭表（N-1..N-4 + 修正项 1..6）

| 编号 | 上轮定性 | 本轮实测状态 | 证据（全部自算/实读） |
|---|---|---|---|
| **N-1** | 低-中，`THIRD-PARTY-NOTICES.md` 漏 HDE32/HDE64 的 Patkov 署名；**阻断公开发布**、不阻断骨架就绪 | **已关闭** | `THIRD-PARTY-NOTICES.md:15-20` 已新增 `Bundled HDE32/HDE64 portion: Portions Copyright (c) 2008-2009, Vyacheslav Patkov`，并指向 `deps/MinHook/LICENSE.txt:27-59`、`src/hde/hde32.c:3`、`hde64.c:3`；`:13` 已把 License 行收窄为 `BSD 2-Clause ("Simplified BSD License") for the core library`，`:14` 保留 `(c) 2009-2017, Tsuda Kageyu`；文件由 49 行增至 55 行，2,536 B → 3,012 B |
| **N-2** | 低，证据路径在父项目根而非 audit 快照根 | **未关闭（如实标注）** | `M0A\captures\gui-fix-20261118-1852\gui-selftest-fixed.txt` 在父项目真实存在（97 B / `259206473068A1A8AE1203852E68AB1122AFD9632181C64740A13C6C125342E6`），在 `CivLink-M0A-audit\M0A\captures\` 下**仍不存在**（该目录只有 F3B/F3E/M0B/E2B/_probe 等旧目录）。上轮报告 §6 修正项 4 写「未关闭（发布时处理）」、`RELEASE-READINESS` §4.1 单列口径段，**与实测一致，未伪装已解决** |
| **N-3** | 低，README L1442 byte offset 127187 孤立 bare CR | **已关闭** | 逐字节扫描 README：bareCR = **0**、CRLF = 1,485、bareLF = **0**；原 `agent summary <CR>eply source` 现为 `agent summary reply source`（`README.md:1442` 实读确认）；全文 `summary reply` 命中 1、`summaryeply` 命中 0 |
| **N-4** | 低，README L4 `****P1 GUI` 强调标记 4 开 2 闭不配对 | **已关闭** | README 全文 `****` 计数 = **0**；`L4` 内 `**` run 全部成对（`**P1 GUI（…）实现完成…` 为 2 开，句末 `……详见 v1.35 修订记录。**` 为 2 闭） |
| **修正项 1**（补 HDE 署名，发布前必须） | 阻断公开发布 | **已关闭** | 同 N-1。另核：`docs/M0D-OPENSOURCE-PLAN-20261118.md:279` 的 §7.2 表确已登记「HDE 部分 Copyright (c) 2008-2009 Vyacheslav Patkov」，故 NOTICES 引「required by plan §7.2」**有据**，非自创要求 |
| **修正项 2**（署名定稿） | 非阻断 | **已关闭**（附引用链瑕疵 N2-2） | `LICENSE:3` = `Copyright (c) 2026 shengtong`；`docs/LICENSE-DOCS.md:30-33`、`README.md:1486`、`docs/CODEX-HANDOVER-M0A.md:175` 四处一致；全仓 `CivLink Contributors` 仅剩 2 处，均在上轮报告 `:92`/`:101`（历史审计记录），**当前署名语境 0 残留** |
| **修正项 3**（SECURITY 联系渠道） | 非阻断 | **未关闭（如实标注）** | `SECURITY.md:30-33` 仍为 `Contact channel will be filled in before publication (project has no public channel yet)`；上轮报告 §6 与 `RELEASE-READINESS` §3.2、§4 均写「仍未关闭，发布前必须补齐」，与实测一致 |
| **修正项 4**（N-2 证据路径） | 非阻断 | **未关闭（如实标注）** | 同 N-2；`RELEASE-READINESS` §4.1 已单列口径段（须写全父项目根路径，或随包附副本并登记新哈希） |
| **修正项 5**（README bare CR + `****P1`） | 非阻断 | **已关闭** | 同 N-3/N-4；修后 README = **138,140 B / `DAB3F0D7AC12F317F3DCE9F0EDD1FD302190F47D8404EC3D9FB348D8AD24379B` / BOM=False / CRLF=1,485 / bareLF=0 / bareCR=0**，与上轮报告 §6 表声明值**逐位一致** |
| **修正项 6**（保持边界语与哈希登记链） | 持续强制 | **已满足（持续项）** | 6 个合规/GUI 文件中的 `已验证/已通过/已批准/verified two-player/Gate A 已通过` 全部为**否定式边界语**（`CONTRIBUTING.md:16`、`SECURITY.md:67`、`README.md:286/307/533/707/791/1140`、`RELEASE-READINESS:63/92` 等），无一处越界；哈希登记链在上轮报告 §6 与 `RELEASE-READINESS` §4 双层保留 |

**结论**：上轮 4 项新发现中 3 项已实关（N-1/N-3/N-4）、1 项保留（N-2）；6 项修正项中 3 项已实关（1/2/5）、2 项保留（3/4）、1 项持续满足（6）。**无一项被伪称关闭**。

---

## 3. 必答问题 Q1..Q8 逐条作答

### Q1：N-1 关闭是否成立？行号指引是否经实读吻合？许可证性质表述是否准确？

**结论：关闭成立；署名载入正确；三处行号指引中两处完全吻合、`LICENSE.txt:27-59` 起点正确但终点偏早（见 N2-1）；性质表述准确、无过度声明也无遗漏。**

实读 `deps/MinHook/LICENSE.txt`（81 行，4,446 B / `4F21F857550D7BE854DA6EA5F2DA4E6775CA4E3FBB535E4F3D961C47D0BF3335`）：

- `L27` = `====…`、`L28` = `Portions of this software are Copyright (c) 2008-2009, Vyacheslav Patkov.`、`L29` = `====…`
- `L30` `Hacker Disassembler Engine 32 C` / `L31` 版权 / `L32` `All rights reserved.` / `L34-42` 两条 numbered clause / `L44-54` 免责声明
- `L56` `-----…`、`L57` `Hacker Disassembler Engine 64 C`、`L58` 版权、`L59` `All rights reserved.`
- `L61-69` HDE64 的两条 clause、`L71-81` HDE64 免责声明

实读源码头部（`deps/MinHook/src/hde/hde32.c`，493 行、17,203 B；`hde64.c`，538 行、19,297 B）：`L1 /*` / `L2  * Hacker Disassembler Engine 32|64 C` / **`L3  * Copyright (c) 2008-2009, Vyacheslav Patkov.`** / `L4  * All rights reserved.` → NOTICES 写的 `hde32.c:3`、`hde64.c:3` **逐行吻合**。

区间 `27-59` 的准确判定：**起点 27 正确**、覆盖 HDE32 全条款；但终点 59 停在 HDE64 的版权声明行，**未覆盖 `L61-81` 的 HDE64 再分发条款与免责声明**。读者若只用该区间取证，会读到「HDE64 存在且已署名」但读不到 HDE64 的许可条件。因 NOTICES 同段另写明「the full license text is bundled in `deps/MinHook/LICENSE.txt`」，指向层面不失真，故不阻断，登记为 **N2-1（低）**，建议区间改为 `27-81`。

性质表述准确性：MinHook 核心 `LICENSE.txt:1-25` 只有两条 numbered clause → `BSD 2-Clause` 表述正确，`L13` 加 `for the core library` 已把范围限定在核心库，避免了把 HDE 也一并贴上 2-Clause 的过度声明；HDE 部分用 `BSD-style terms` 而非硬贴 `BSD-3-Clause` —— 实测 HDE 两段也只有 2 条 numbered clause（`L34-42`、`L61-69`），与标准 3-Clause 的差异仅在免责声明主体写作 `THE REGENTS OR CONTRIBUTORS`（`L47`、`L74`），写法保守**更准确**。上轮报告 N-1 曾用「BSD-3 条款部分」措辞，本轮 NOTICES **未沿用**该措辞，属改进。无遗漏（`Portions of this software are Copyright` 首行原文、两处 HDE 组件名、"All rights reserved" 均在 NOTICES 中被覆盖）。

### Q2：署名定稿是否一致？全仓是否还有 "CivLink Contributors" / "待确认" 残留？

**结论：一致，定稿为 `shengtong`；当前署名语境零残留。**

| 落点 | 实读内容 | 判定 |
|---|---|---|
| `LICENSE:3` | `Copyright (c) 2026 shengtong` | ✓ 已同步（全文 29 行，MIT 正文 `L5-21` 完整，`L23-29` scope 段指向 LICENSE-DOCS / THIRD-PARTY-NOTICES） |
| `docs/LICENSE-DOCS.md:30-33` | `**Attribution hint:** "CivLink documentation, (c) 2026 shengtong, licensed under CC BY 4.0." The copyright holder was confirmed by the project owner on 2026-11-18 (see docs/M0D-OPENSOURCE-PLAN-20261118.md, Decision Point §9.1).` | ✓ 已同步（但 §9.1 引用不成立 → N2-2） |
| `README.md` v1.35 记录块 `L1486` | `> 开源发布骨架：根 LICENSE（MIT，署名 2026 shengtong（负责人 2026-11-18 确认））…` | ✓ 已同步（在 `L1481-1486` 连续 blockquote 记录块内） |
| `docs/CODEX-HANDOVER-M0A.md` 第 22 项 `L175` | `… LICENSE（MIT，署名 shengtong，负责人 2026-11-18 确认）、… THIRD-PARTY-NOTICES.md（MinHook v1.3.4 BSD-2 + 内嵌 HDE32/HDE64 的 Patkov 署名）…` | ✓ 已同步（第 22 项标题 `L167` = `## 22. P1 GUI 产品级实现（2026-11-18，两轮审计闭环）`） |

全仓 grep 证明（范围：161 个 `.md` + 全部 `.txt`，含 `deps/`、排除 `dist/`）：

- `CivLink Contributors`：**命中 2 处，全部在上轮合规报告自身**（`docs/M0D-OPENSOURCE-COMPLIANCE-REVIEW-20261118.md:92` 描述「审计当时」状态、`:101` 是修正项 2 原文）。**不是任何当前文件的署名**。另 `THIRD-PARTY-NOTICES.md:30` 的 `THE COPYRIGHT HOLDERS AND CONTRIBUTORS` 是 BSD 免责声明模板原文，非署名。
- `待确认`：命中 4 处且全部与署名无关 —— `docs/F3-DIRECT-RELAY-DESIGN-20261114.md:114`（章节标题）、`docs/M0D-GUI-DESIGN-20261118.md:422`（GUI 设计细节）、`docs/M0D-GUI-IMPL-REVIEW-20261118.md:38`（引 GUI 报告）、上轮报告 `:92`（历史记录）。署名语境 **0 残留**。
- `provisional|placeholder|TBD`：命中 2 处 —— `docs/F5-REAL-DUALMACHINE-REGISTRATION-REVIEW.md:23`（审计方法论引用关键词）、上轮报告 `:92`。署名语境 **0 残留**。
- `shengtong`：命中 5 处 —— `docs/CODEX-HANDOVER-M0A.md:175`、`docs/LICENSE-DOCS.md:30`、上轮报告 `:116`、`docs/M0D-RELEASE-READINESS-20261118.md:54`、`README.md:1486`。

⚠ 但 `docs/M0D-OPENSOURCE-PLAN-20261118.md` 内 `shengtong` 命中 **0**（见 N2-2）。

### Q3：N-3/N-4 关闭是否成立？README 实算值是否与报告 §6 表一致？

**结论：成立，且逐位一致。**

README.md 实算（2026-11-18 19:5x，逐字节）：**138,140 B**，SHA-256 `DAB3F0D7AC12F317F3DCE9F0EDD1FD302190F47D8404EC3D9FB348D8AD24379B`，BOM = False，CRLF = **1,485**，bareLF = **0**，bareCR = **0**，共 1,486 行。

| 项目 | 上轮报告 §6 表声明 | 本轮实测 | 一致 |
|---|---|---|---|
| 字节数 | 138,140 | 138,140 | ✓ |
| SHA-256 | `dab3f0d7ac12f317f3dce9f0edd1fd302190f47d8404ec3d9fb348d8ad24379b` | 同上（全 64 位逐字符相同） | ✓ |
| BOM | False | False | ✓ |
| CRLF | 1,485 | 1,485 | ✓ |
| bareLF | 0 | 0 | ✓ |
| bareCR | 0 | 0 | ✓ |

补充：README 末字节为 `0x82`（UTF-8 续字节），即**末行无尾随换行**；`docs/CODEX-HANDOVER-M0A.md` 同为 175 行 / 174 个 CRLF（亦无尾随换行）。两者口径自洽，属既有书写惯例，非缺陷（见 Q7）。

### Q4：§6「当前值」表与 §2「审计基线」表并存是否造成误引？该处理是否可接受？

**结论：处理方式本身可接受（追加式、不改既有结论、明示基线快照），但存在两处真实误引风险，须订正（N2-5）。**

可接受的理由：① 审计报告应当**不可变**，事后改写结论会摧毁审计链；② 项目侧在 §6 顶部（`:111`）明确声明「不修改审计员的任何既有结论行」，并把 §2 值定义为「审计基线快照值，不得当作当前值」；③ §6（`:121-131`）给出完整 7 行当前值表（字节 + 全量 SHA-256 + BOM/CRLF/bareLF/bareCR），不是只给「已改」三字；④ 本轮已另有 REVIEW-2（本文件）承接最新裁定，历史报告自然退化为快照。

但有两处真误引风险：

1. **章节号错指**（硬错误）：哈希基线表在上轮报告的 **§3（`L44-57`「八项文件哈希与编码实测表」）**，而 §6 三处写成「§2 表」——`:111`「§2 表中 `README.md` 的 138,142 B」、`:121`「取代 §2 表」、`:133`「§2 表中的 LICENSE 1,598 B…」。§2（`L29-40`）实际是「必答问题逐条关闭表」，读者按 §2 找不到任何哈希。应改为「§3 表」。
2. **顶段裁定未随修复更新**：§1（`L11-25`）仍写「有条件通过…首次公开推送前须补 N-1」，§4/§5 仍把 N-1 列为阻断公开发布项。只读 §1 的外部读者会得到「N-1 仍开放」的过期印象，必须读到 `L109` 之后的 §6 才知道已关闭。

更严谨的做法（建议，非阻断）：① 把三处「§2 表」改为「§3 表」；② 在上轮报告 §1 或 §3 表上方加一行「**本报告为 2026-11-18 19:36 基线快照；最新裁定见 `docs/M0D-OPENSOURCE-COMPLIANCE-REVIEW-2-20261118.md`**」；③ 长期做法是把「当前哈希」从审计报告里剥离，单独维护 `MANIFEST.md` / `SHA256SUMS`（发布包本来就要生成 MANIFEST），审计报告只引用基线快照 + 指向 MANIFEST，避免每轮都要在审计报告里追加「当前值」表。

### Q5：三个未关闭项是否被如实标注？

**结论：三项全部如实标注为「未关闭」，无一处写成已解决。**

- **SECURITY.md 联系渠道**：`docs/M0D-RELEASE-READINESS-20261118.md` §3.2（`L52`）写「第 3 项（`SECURITY.md` 漏洞联系渠道）**仍未关闭，发布前必须补齐**」；§4（`L70-76`）在「已就绪部分」里仍带一句「`SECURITY.md` 联系渠道仍待补」。实测 `SECURITY.md:30-33` 确实仍是 `will be filled in before publication`。标注**准确且未淡化**（同一份文档既列入阻塞项 §3、又在「已就绪」段作了保留说明，没有把 5 文件说成全部就绪）。
- **证据路径在父项目根（N-2）**：§3.2 写「N-2（证据路径口径）属发布时处理」；§4.1（`L80-85`）单列整节给出实体路径 `C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\`，并明确「不得让读者按 audit 根拼接出不存在的路径」。实测 audit 根下确无该目录 → 描述属实。
- **A 房主默认流程待拍板**：§3.3（`L58-60`）写「普通 A 房主默认流程：**仍待拍板**——需先向负责人解释『只注入 hook』与『注入并自动启 agent（含 `--sim-lan-listen` 模拟层）』两种默认流程的差异，再由负责人选定」。未见任何「已解决/已定稿」措辞。

补充（观察，不计入未关闭项）：代码侧其实**已有**「普通 A 只注入 hook、不启 sim agent」的默认实现——`civlink/gui/civlink_tray.cs:403 ApplyRoleDefaults()`，自检断言在 `:633-635`：`Check(!agNormal.Contains("--sim-lan-listen") && !agNormal.Contains("--reserve-62900") && !agNormal.Contains("--simulate"), "normal A host starts no sim agent (N-B)")`。因此准确说法是「**实现已按保守默认落地、对外口径待负责人拍板**」，而非「完全未定」。这可能是有意保留（实现先行、口径待批），但建议文档补一句区分，否则读者会以为连默认行为都没有。

### Q6：`docs/M0D-RELEASE-READINESS-20261118.md` 的事实准确性

**结论：dist 陈旧结论与所列哈希全部属实；「三项产品裁定二项已拍板」与代码/署名一致，但其落盘证据链不足（指向 plan §9.1 不成立，实际只自引 m29480）。**

（1）dist 陈旧判定——**属实**。实读 `dist\civlink-beta-20261114\` 全部 8 个文件，与 §2 表逐项吻合：

| 文件 | 实测字节 | 实测 SHA-256 前 12 位 | §2 表声明 |
|---|---|---|---|
| `civlink-agent.exe` | 382,464 | `93F1751620C2` | 一致 |
| `civlink-relay.exe` | 262,144 | `9E323F818AF0` | 一致 |
| `civlink_ctl.exe` | 173,056 | `23923DFBAAB3` | 一致 |
| `civlink_hook.dll` | 119,808 | `9424FC25FB45` | 一致 |
| `check-f4-package.ps1` | 3,966 | `BE45A5FE1AD6` | 一致 |
| `run-f4-beta.ps1` | 14,079 | `F7B5643903FA` | 一致 |
| `KNOWN-LIMITATIONS.md` | 4,555 | `E007C115C369` | 一致 |
| `VERSIONS.txt` | 152 | `62CDC2D5A341` | 一致 |

dist 内所有文件 mtime 均为 **2026-11-14**；`VERSIONS.txt` 内容为 `civlink-agent 0.3.0` / `civlink-relay 0.1.0` / `civlink_ctl v0.2.0-f2`，而当前 `civlink\` 产物为 agent 0.4.6 等新版本 → 「旧 beta、与当前产物脱节」**结论成立**。

（2）与当前产物脱节——**属实**。`civlink\` 实测：`civlink-agent.exe` 421,376 B / `4390AF9DF56A`（mtime 2026-11-18 08:45）、`civlink_hook.dll` 119,808 B / `33438AD58442`、`civlink_client.dll` 149,504 B / `F3816C5E0E6C`、`civlink_ctl.exe` 188,416 B / `6FCE456E4156`、`civlink_tray.exe` 26,112 B / `9B480FE0C818`（mtime 2026-11-18 18:52）。dist 的 agent 382,464 B ≠ 当前 421,376 B，hook 哈希亦不同 → 发布前必须重打包，§3.1 成立。另注意 `civlink\` 内还残留旧 GUI `civlink_ctl_gui.exe`（8,704 B / `A0EB830BF26D`，2026-11-15）与 `relay-civlink-relay.exe`（262,144 B，与 dist 内 relay 同哈希），重打包时应明确取舍，避免误入包。

（3）「三项产品裁定二项已拍板」——**与代码和署名状态一致，但证据链薄弱**：
- 版权署名 `shengtong`：四处落点确实同步（见 Q2），本轮任务书亦确认「负责人定为 shengtong」→ 事实成立。
- GUI 白名单三进程：`civlink/gui/civlink_tray.cs:20` 实读 `internal static readonly string[] Names = { "CivilizationVI_DX12", "CivilizationVI", "CivilizationVI_DX11" };` → **与 §3.3「已定三个」一致**。
- 普通 A 房主默认流程待拍板：见 Q5，标注成立（但实现已存在）。
- **问题**：§3.3 把三项裁定的来源写为「用户 2026-11-18 **m29480**」，而全仓 `m29480` 命中仅此 1 处（无第二份落地记录）；`docs/M0D-OPENSOURCE-PLAN-20261118.md` §9.1（`L344-356`）是项目自定的「负责人裁定记录（2026-11-18，用户 **m28114**）」，只记 d1..d7 七个决策点（d1 不内嵌仅文档引导 / d2 组网方案**挂起**、纯用户自建 / d3 仅 Steam Win64 / d4 首版 2 人可验证闭环 / d5 完全不上报 / d6 完全无日志 / d7 仅个人免费引导），**不含署名、不含白名单、不含 A 房主默认流程**。→ 见 N2-2。

（4）§5 发布口径——**保留了强制边界**（`L89-92`：所有证据为工具级/headless/单机/探针级；「真实游戏跨机对局待验证」；Gate A 未批准；不得写「双人真实联机已通过」）。**未越界**。

（5）§3.2 引「`885ef6ac` 裁定有条件通过、`allow_open_source_skeleton_ready = true`」——与上轮报告 §1 一致，**引用属实**。

### Q7：本轮改动是否引入新问题（编码/断链/决策冲突/越界表述）？

**结论：编码与越界表述维度**未引入新问题**；断链维度**新增了一处结论性不实陈述**（N2-4）；决策口径维度**新增两处不一致**（N2-2、N2-3）。

（a）编码——**无新问题**。8 个被审文件全部 **UTF-8 无 BOM**；`LICENSE`、`docs/LICENSE-DOCS.md`、`THIRD-PARTY-NOTICES.md`、`CONTRIBUTING.md`、`SECURITY.md`、上轮报告、`RELEASE-READINESS` 为**纯 LF**；`README.md`、`docs/CODEX-HANDOVER-M0A.md` 为**纯 CRLF**；**无 BOM/CRLF/LF 混用**、无孤立 CR。该分工与 `CONTRIBUTING.md:55-56` 的约定（UTF-8 无 BOM、README 用 CRLF）一致。

（b）断链——**本轮写入的新结论不实**（N2-4）。逐行 fence 感知统计（159 个 `.md`，排除 `dist/` 与 `deps/`；剥除 `:行号` 后缀）：
- 宽松口径 `\]\(([^)]+)\)`：191 个链接 / 43 个相对链接；严格口径 `\]\(([^)\s]+)\)`：188 / 40。
- **fence 外真死链 2 处，均在 `docs/F2-S1-S4-CODE-AUDIT-20261114.md:110`**：`文件：[lib.rs](../civlink/civlink/fakeip/src/lib.rs:343)、[lib.rs](../civlink/civlink/fakeip/src/lib.rs:351)` —— 路径多一层 `civlink`（`CivLink-M0A-audit\civlink\civlink` 实测不存在），正确应为 `../civlink/fakeip/src/lib.rs`（该文件实测存在，792 行）。
- 其余 4 处「死链」确为行内反引号代码误报（`docs/F3A-REVIEW-2.md:448` 的 `$i+1`；`docs/F3B-REVIEW-2.md:128`、`docs/F3E-FAULT-INJECTION-20261114.md:146`、`docs/F3E-REVIEW.md:117` 的 `[bool]($Exit -ne -1)` 之类）。
- 故 `RELEASE-READINESS` §4（`L77-78`）写「全仓 159 个 Markdown、42 个相对链接，4 处死链均为 PowerShell 代码块内误报，**实际 0 个真死链**」，其中「159 个 Markdown」与实测吻合、「42 个相对链接」只对应宽松口径（严格口径 40）、「0 个真死链」**与实测 2 处真死链不符**。该死链属 F2 旧报告既有问题、**非本轮 8 文件改动引入**，但「0 个真死链」这句是本轮新写的 → 属本轮新增的不实陈述。

（c）与 §9.1 决策冲突的措辞——**两处**（N2-2 署名 §9.1 引用不成立；N2-3 白名单「已定 vs 待确认」互斥）。均属**文档内部口径**问题，未与本轮 d1..d7 七个决策点本身冲突（例如 `CONTRIBUTING.md:11-14` 引 d1/d5/d6/d7、`README.md:1476` 引 7 决策点，均与 §9.1 一致）。

（d）「待验证 → 已验证」越界——**未发现**。对 8 个被审文件做 `已验证|已通过|已批准|verified two-player|Gate A 已|E2-A 通过|双人验证通过` 全量扫描，命中全部是否定/限定式（`CONTRIBUTING.md:16` "never to be described as verified two-player online play. Gate A remains"、`SECURITY.md:67` "does not mean verified two-player"、`README.md:307` "不能称作 Relay RTT 已验证或 H6/E2-B 已通过"、`README.md:533` "不允许的表述：「联机已验证」"、`README.md:791` "不得标『双人真实联机已通过』"、`RELEASE-READINESS:63/92` 等）。`README.md:98` 的「路 A（本机首选，已验证）」指本机构建脚本可用，属既有表述、非联机结论，无越界。

（e）其他：`RELEASE-READINESS` §3.2 有一处笔误「其实验室 4 项新发现中」（应为「其 4 项新发现中」），语义无歧义，可随手修。

### Q8：哈希抽查（≥8 个引用点、跨 ≥4 个文件）

见 §5 表（14 个引用点、跨 10 个引用文件 + 11 个被引用文件）。**结论：14/14 全部一致，不一致项 0 个。**

---

## 4. 新发现（N2-1..N2-7）

| 编号 | 严重度 | 发现 | 证据 | 阻断公开发布 | 阻断骨架就绪 |
|---|---|---|---|---|---|
| **N2-1** | 低 | `THIRD-PARTY-NOTICES.md:17` 的行号区间 `deps/MinHook/LICENSE.txt:27-59` 终点偏早，未覆盖 HDE64 的再分发条款与免责声明（`L61-81`） | 实读 `deps/MinHook/LICENSE.txt`（81 行）：`L56-59` 仅 HDE64 组件名+版权+All rights reserved；`L61-69` 才是 HDE64 两条款、`L71-81` 免责声明。起点 27 正确、HDE32 覆盖完整 | 否 | 否 |
| **N2-2** | **中** | 署名的权威依据引用不成立：`docs/LICENSE-DOCS.md:32-33` 写 "The copyright holder was confirmed by the project owner on 2026-11-18 (see `docs/M0D-OPENSOURCE-PLAN-20261118.md`, Decision Point §9.1)"，但 plan **§9.1 只记 d1..d7 七个决策点，无署名条目**（plan 全文 `shengtong` 命中 0） | plan §9.1 = `L344-356`（标题「负责人裁定记录（2026-11-18，用户 m28114）」）；`shengtong` 全仓 5 处命中，**无一处 plan**；署名决定的实际落盘仅 `RELEASE-READINESS:54` 自引「m29480」（全仓唯一 1 处）。结论：署名**决定本身成立**（负责人已定，本轮任务书亦确认），但**可核查性**不成立——外部审计按该指引查证会落空 | 否（建议发布前修） | 否 |
| **N2-3** | **中** | 白名单对外口径自相矛盾：README 同一记录块内 L1483 说白名单进程名已定为三进程、L1485 又说「白名单最终清单…待负责人确认」；HANDOVER `L171` 与 `RELEASE-READINESS` §3.3 均写「已定/已确认」 | `README.md:1483`（`白名单进程名（CivilizationVI_DX12/CivilizationVI/CivilizationVI_DX11）不接受手动 PID`）vs `README.md:1485`（`…白名单最终清单与普通 A 房主默认流程待负责人确认。`）；`docs/CODEX-HANDOVER-M0A.md:171`（`…，负责人 2026-11-18 确认`）；`RELEASE-READINESS:56-57`（`已定` 三项）。代码侧与「已定」一致（`civlink_tray.cs:20`）。偏差方向为**更保守**（README 保守、HANDOVER 乐观），无过度声明风险，但对外两份文件给出互斥答案 | 否（建议发布前统一） | 否 |
| **N2-4** | 低-中 | `RELEASE-READINESS` §4 的文档链接统计与**实测不符**：声明「42 个相对链接、4 处死链均为代码块内误报、实际 0 个真死链」，实测存在 **2 处 fence 外真死链** | `docs/M0D-RELEASE-READINESS-20261118.md:77-78` vs 实测：严格口径 40 / 宽松口径 43 个相对链接；真死链 `docs/F2-S1-S4-CODE-AUDIT-20261114.md:110` 两条（`../civlink/civlink/fakeip/src/lib.rs:343`、`:351`），`CivLink-M0A-audit\civlink\civlink` 不存在、`civlink\fakeip\src\lib.rs` 存在。该死链为 F2 旧报告既有问题，**非本轮引入**，但「0 个真死链」为本轮新写 | 否（建议订正结论并顺手修 2 处链接） | 否 |
| **N2-5** | 低 | 上轮报告 §6 三处把哈希基线表误引为「§2 表」，实为 **§3**；且 §1/§4/§5 的「N-1 仍开放」裁定未随修复更新，只读 §1 会得到过期结论 | 上轮报告标题：`L29 ## 2. 必答问题逐条关闭表`、`L44 ## 3. 八项文件哈希与编码实测表`；误引在 `:111`「§2 表中 README.md 的 138,142 B」、`:121`「取代 §2 表」、`:133`「§2 表中的 LICENSE 1,598 B…」。§1（`L11-25`）仍写「须补 N-1」 | 否 | 否 |
| **N2-6** | 低 | `docs/M0D-OPENSOURCE-PLAN-20261118.md` §7.2 组件表与实测不一致：列 `Serilog | Apache-2.0 | ✅`、`.NET / WPF | MIT | ✅`、`Rust std + cargo 依赖（serde/clap/tokio 等）| 待 cargo-deny`，但代码零 Serilog、GUI 为 WinForms/.NET Framework 4.x（`csc /target:winexe`，无 WPF 依赖）、三个 Rust crate 的 `[dependencies]` 全为空 | plan `L277-282`；实测：全仓无 `Serilog`/无 `packages.config`/无 `.csproj`；`civlink/{agent,fakeip,relay}/Cargo.toml` 的 `[dependencies]` 段全空（agent 0.4.6 / fakeip 0.1.0 / relay 0.1.0，license 均 MIT）；`civlink/gui/build-gui.ps1:5` 编译 `civlink/ctl/civlink_ctl_gui.cs`。plan 本轮未改（mtime 10:27），但本轮 NOTICES 已成为权威清单，两张表并列易被误引 | 否 | 否 |
| **N2-7** | 低 | `THIRD-PARTY-NOTICES.md:27-30` 的许可证摘录把 BSD 两条款合并成一句、并截断免责声明（只到 `"AS IS".`），未标注为「摘录/excerpt」 | 原文 `L34-42` 是「1. 源码保留 / 2. 二进制复制」两条独立条件，NOTICES `L27-29` 合并为「provided that the copyright notice, this list of conditions and the disclaimer are retained…」；`L30` 免责声明只保留首句。同段已指向全文，故不构成误述 | 否 | 否 |

**新增阻断项合计：阻断公开发布 0 项、阻断骨架就绪 0 项。** 其中 N2-2、N2-3、N2-4 建议在**首次公开发布前**一并修订（均为纯文档改动，成本极低）。

---

## 5. 哈希抽查表

抽查 14 个引用点，跨 7 个**引用文件**（`RELEASE-READINESS`、上轮报告 §6、`README.md`、`docs/CODEX-HANDOVER-M0A.md`、`docs/M0D-GUI-IMPL-REVIEW-2-20261118.md` 引用链、`NOTICES`、`LICENSE-DOCS`）与 11 个**被引用文件**。全部自行重算。

| # | 文件 | 声明值（前 12 位 / 字节） | 实测值（前 12 位 / 字节） | 一致 |
|---|---|---|---|---|
| 1 | `LICENSE` | `A5A3E2CE01FE` / 1,587（上轮报告 §6、`RELEASE-READINESS:73`） | `A5A3E2CE01FE` / 1,587 | ✓ |
| 2 | `docs/LICENSE-DOCS.md` | `032DF19F345C` / 1,792（§6、`RELEASE-READINESS:74`） | `032DF19F345C` / 1,792 | ✓ |
| 3 | `THIRD-PARTY-NOTICES.md` | `B1A4B6037641` / 3,012（§6、`RELEASE-READINESS:75`） | `B1A4B6037641` / 3,012 | ✓ |
| 4 | `CONTRIBUTING.md` | `93DB49C281AC` / 3,316（§6、`RELEASE-READINESS:75`） | `93DB49C281AC` / 3,316 | ✓ |
| 5 | `SECURITY.md` | `CB223D7810B1` / 3,149（§6、`RELEASE-READINESS:76`） | `CB223D7810B1` / 3,149 | ✓ |
| 6 | `README.md` | `DAB3F0D7AC12` / 138,140（上轮报告 §6 `:130`） | `DAB3F0D7AC12` / 138,140 | ✓ |
| 7 | `docs/CODEX-HANDOVER-M0A.md` | `1DFAAF440C68` / 52,823（上轮报告 §6 `:131`） | `1DFAAF440C68` / 52,823 | ✓ |
| 8 | `docs/M0D-GUI-IMPL-REVIEW-2-20261118.md` | `F9623EBD6AF6` / 13,666（`README.md:1484`、`HANDOVER:169`、`RELEASE-READINESS:67`） | `F9623EBD6AF6` / 13,666 | ✓ |
| 9 | `docs/M0D-GUI-IMPL-REVIEW-20261118.md` | `60C1512835D5` / 19,788（`README.md:1484`、`HANDOVER:169`） | `60C1512835D5` / 19,788 | ✓ |
| 10 | `docs/M0D-GUI-IMPL-20261118.md` | `561B8EEFB035` / 9,375（`README.md:1483`） | `561B8EEFB035` / 9,375 | ✓ |
| 11 | `docs/M0D-GUI-DESIGN-20261118.md` | `698E413CA0DC` / 55,952（`README.md:1482`） | `698E413CA0DC` / 55,952 | ✓ |
| 12 | `civlink/gui/civlink_tray.cs` | `2DFFBFAA50CC` / 35,707（`README.md:1484`） | `2DFFBFAA50CC` / 35,707 | ✓ |
| 13 | `civlink/gui/civlink_tray.exe` | `9B480FE0C818` / 26,112（`README.md:1484`） | `9B480FE0C818` / 26,112 | ✓ |
| 14 | `M0A\captures\gui-fix-20261118-1852\gui-selftest-fixed.txt` | 97 B / `259206473068…`（`README.md:1484` 路径、上轮报告 §2 Q6 哈希） | 97 B / `259206473068A1A8AE1203852E68AB1122AFD9632181C64740A13C6C125342E6` | ✓ |

**附加（无声明值、供参考，不计入抽查）**：`deps/MinHook/LICENSE.txt` 4,446 B / `4F21F857550D7BE854DA6EA5F2DA4E6775CA4E3FBB535E4F3D961C47D0BF3335`；`deps/MinHook/src/hde/hde32.c` 17,203 B / `2DD2E2ED9C76E65DAA0C2F6023BC38DC80BC5C62448CFDC65A098BE8339A8BDE`；`hde64.c` 19,297 B / `A49AF94BAD8E43242828A08E5F9F2182A9ACD4F8DBC6846847A296F796975512`；`docs/M0D-OPENSOURCE-PLAN-20261118.md` 42,544 B / `B89C7994B02ABC824DCDB757B5909B130FD6A3D3C92CDFBBE9859D8C07FA3804`；`docs/M0D-RELEASE-READINESS-20261118.md` 5,464 B / `25D633CD9891DC4A3F2752368991FF9E87A7C9D995C1B000FD886DEC3004E80F`；上轮报告 20,955 B / `47C65D86F0EE840726ABA7ADA859CEB8D2964F265C37EF01D19CDEF976F50B5D`。

**不一致项：0 个。**

---

## 6. 是否允许宣布「开源发布骨架就绪」

**yes。**

允许宣布，条件与口径如下：

1. **允许的表述**：CivLink 开源发布**骨架**（`LICENSE` MIT / `docs/LICENSE-DOCS.md` CC BY 4.0 / `THIRD-PARTY-NOTICES.md` / `CONTRIBUTING.md` / `SECURITY.md` 五件套 + 第三方声明含 MinHook BSD-2 与内嵌 HDE32/HDE64 的 Patkov 署名）**已就绪**；独立复审裁定 **PASS**。
2. **必须并列的保留项**（不得省略）：
   - `SECURITY.md` 漏洞联系渠道**仍未填**（`will be filled in before publication`）；
   - 证据路径实体在**父项目根**，不在 audit 快照根（N-2 / N2-2 类口径）；
   - 普通 A 房主默认流程的**对外口径仍待负责人拍板**（实现已按保守默认落地）；白名单对外表述需统一（N2-3）；
   - 署名裁定的落盘依据需补（N2-2）；
   - `RELEASE-READINESS` §4 的「0 个真死链」结论需订正（N2-4）。
3. **绝对不得**据此宣布：首次公开发布完成、`dist\civlink-beta-20261114\` 可发布（它是 2026-11-14 旧 beta，与当前产物脱节，须重打包）、`E2-A/E2-B/E3` 通过、双人真实联机已验证、Gate A 已批准。
4. **本裁定不覆盖**：真实游戏注入端到端、双人真实联机、跨机对局、M0-B/Gate B；本轮全程未启动游戏、未做任何网络/联机操作。

---

## 7. 审计声明

1. **只读**：本次复审未修改、未移动、未删除任何被审文件（`LICENSE`、`docs/LICENSE-DOCS.md`、`THIRD-PARTY-NOTICES.md`、`CONTRIBUTING.md`、`SECURITY.md`、`README.md`、`docs/CODEX-HANDOVER-M0A.md`、上轮合规报告、`docs/M0D-RELEASE-READINESS-20261118.md`、`docs/M0D-OPENSOURCE-PLAN-20261118.md`、`deps/MinHook/*`、`civlink/*`、`dist/*`）。唯一写入为本审计报告自身；临时文件仅在本机 `%TEMP%` 下。
2. **未采信口述**：所有结论来自磁盘实读与实算。表内每个字节数、SHA-256 及 BOM/CRLF/bareLF/bareCR 计数均在本轮现场重新计算，未从任何文档、任务书或项目侧声明中复制数值；对项目侧 §6 表与 `RELEASE-READINESS` 所载数值一律先复算再比对。
3. **未做游戏/网络操作**：未启动《文明6》、未注入任何进程、未进行网络或联机操作、未改动 `dist/` 目录内容（仅只读枚举与哈希）。
4. **未批准任何 Gate**：Gate A 未批准这一前提在本报告中全程保留；本轮证据均为文档与文件系统层面的机械对账，**不构成**任何运行时、联机或端到端验证。
5. **独立性**：未参与被审文件的编写或修复；未接受项目侧任何「已修复」结论作为前提，N-1/N-3/N-4 与修正项 1/2/5 的关闭均逐项独立复算后确认。
6. **本文件自身哈希未在文内登记**（自指不可行）；如需登记，请由发布流程在写入后另存到 `MANIFEST` / `SHA256SUMS`。

**审计员签署**：独立审计员（CivLink M0D 修复轮复审）。

裁定：**PASS**；`allow_open_source_skeleton_ready = true`；新发现 7 项（N2-1..N2-7，最高严重度「中」2 项：N2-2、N2-3），**阻断骨架就绪 0 项、阻断公开发布 0 项**（N2-2/N2-3/N2-4 建议首次公开发布前修订）。
