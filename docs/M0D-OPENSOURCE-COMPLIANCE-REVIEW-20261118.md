# M0D — 开源发布合规性独立审计（OPENSOURCE-COMPLIANCE-REVIEW）

- 审计日期：2026-11-18
- 审计对象：CivLink 开源发布骨架 8 项新增/修改文件 + 参考基线（项目根 `CivLink-M0A-audit`）
- 审计员：独立审计员（CivLink M0D），只读审计；未修改任何被审文件
- 方法：`Get-FileHash -Algorithm SHA256` / `Get-Item .Length` / 逐字节编码扫描 / `ReadAllText(UTF8)` 逐行实读；**所有结论来自磁盘实读，不采信 brief 未附证据的断言**
- 约束遵守：未启动真实游戏、未做网络/联机操作（PC-B 对局期不干扰）；未执行任何被审构建脚本

---

## 1. 裁定

**裁定：有条件通过（CONDITIONAL PASS）。**

**是否允许宣布「开源发布骨架就绪」：允许（`allow = true`）。**

依据：

1. 8 项必答问题中 7 项完全通过，第 2 项「第三方声明真实性」核心声明（MinHook 版本/许可/Copyright、Rust 零外部依赖、MSVC/.NET 不捆绑、无其他需声明第三方）**全部属实**，仅 `THIRD-PARTY-NOTICES.md` 对 MinHook 内嵌 HDE32/64 的 Patkov 版权署名有**一处遗漏**（N-1），属文本补全项而非虚假声明。
2. 复审报告 `docs/M0D-GUI-IMPL-REVIEW-2-20261118.md` 本体 13,666 B / `F9623EBD…FA4CD0F` / UTF-8 无 BOM / 110 行 / 纯 LF，与 brief 期望**逐字节一致**；README v1.35 与 HANDOVER 第 22 项的登记链哈希（复审报告 / 实现报告 / 源码 / exe / 自检输出）全部实算吻合，无孤立或陈旧哈希当「当前值」。
3. 四项新发现（N-1..N-4）严重度均为**低**（其中 N-1 为低-中），**无一阻断「骨架就绪」**；但 N-1 是公开推送/正式发布前**必须补齐**的署名项（plan §7.2 `docs/M0D-OPENSOURCE-PLAN-20261118.md:279` 已明确要求）。

**「有条件」的精确含义**：可以对外宣布开源发布骨架就绪；在**首次公开推送/发布**之前须完成 N-1（`THIRD-PARTY-NOTICES.md` 补 HDE 署名），并建议同时处理 N-3、N-4 两处 README 文本瑕疵与 N-2 的路径说明。上述条件不改变 §2 的逐题裁定，也不回退骨架就绪结论。

**边界（强制保留，随本裁定传递）**：本裁定仅覆盖开源发布骨架的许可/声明/登记/编码合规性；`gate=双人验证未完成（Gate A 未批准）` 仍为真。headless 自检 33/33 与窗口冒烟 PASS 均不是真实游戏注入端到端，更不是双人真实联机；不得写成 E2-A/E2-B/E3 通过，不得越界宣称 Gate A 已批准。

---

## 2. 必答问题逐条关闭表

| # | 问题 | 裁定 | 路径:行号证据（磁盘实读） |
|---|---|---|---|
| 1 | License 逻辑一致性 | **通过** | 三文件互引闭环：`LICENSE:23-29` scope 段明指 `docs/LICENSE-DOCS.md` 与 `THIRD-PARTY-NOTICES.md`；`docs/LICENSE-DOCS.md:1-7` 回指根 MIT；`THIRD-PARTY-NOTICES.md:8-49` 独立第三方声明。MIT 正文完整标准文本：`LICENSE:5-13` 授权与条件 + `LICENSE:15-21` `THE SOFTWARE IS PROVIDED "AS IS"` 免责声明齐全。CC BY 4.0 摘要准确：`docs/LICENSE-DOCS.md:13` Share、`:14-15` Adapt、`:19-22` Attribution（含「不得暗示背书」）、`:23-25` No additional restrictions、`:27-28` legalcode 链接、`:35-39` as-is 与边界声明。无矛盾。 |
| 2 | 第三方声明真实性 | **需修正（低，见 N-1）** | 属实部分：MinHook v1.3.4 / BSD-2 / `(c) 2009-2017 Tsuda Kageyu` 与 `deps/MinHook/LICENSE.txt:1-12` 一致（`THIRD-PARTY-NOTICES.md:10-19`）；Rust 零外部依赖属实（`civlink/agent/Cargo.toml`、`civlink/fakeip/Cargo.toml`、`civlink/relay/Cargo.toml` 的 `[dependencies]` 均为空，三份 `Cargo.lock` 各只含 crate 自身）；不捆绑 MSVC/.NET 属实（`civlink/build-msvc.cmd:2,6,31,37` `/MT` + pin v1.3.4；`civlink/gui/build-gui.ps1:14-25,35` 用系统 Roslyn csc 与 `C:\Windows\Microsoft.NET\Framework64\v4.0.30319` 程序集，无 SDK 包）。无其他需声明第三方：`deps/` 仅 `MinHook` 一个目录、唯一 LICENSE 为 `deps/MinHook/LICENSE.txt`；`civtrace/` 为自研 C++（复用同一 MinHook pin）。**遗漏**：`THIRD-PARTY-NOTICES.md` 全文无 `HDE`/`Patkov` 字样，而 `deps/MinHook/LICENSE.txt:28,31,58` 与 `deps/MinHook/src/hde/hde64.c:3`、`hde32.c:3` 载有 `Portions Copyright (c) 2008-2009, Vyacheslav Patkov`，且 plan `docs/M0D-OPENSOURCE-PLAN-20261118.md:279` 已要求登记。 |
| 3 | §9.1 决策口径 | **通过** | 基线 `docs/M0D-OPENSOURCE-PLAN-20261118.md:348-358`：d1 不内嵌仅文档引导、d2 挂起（纯用户自建）、d3 仅 Steam Win64、d4 首版 2 人闭环、d5 完全不上报、d6 完全无日志、d7 个人免费。一致证据：`SECURITY.md:15-20`（Steam Win64 / 两人 / 无公共 relay / no telemetry / no log upload / no crash reporting）、`:66-68`（无匿名统计/公共 relay/全球匹配）；`CONTRIBUTING.md:9-14`（Windows x64 Steam Win64 两人 + no telemetry/no logs/no auto-update/no bundled VPN，引 §9.1 d1/d5/d6/d7）；`README.md:4,1485`（不内嵌第三方组网、零遥测/零日志/无持久化、双人边界）；`docs/CODEX-HANDOVER-M0A.md:171,175`；`THIRD-PARTY-NOTICES.md:45-49`（个人免费、非官方）。「telemetry」用词清楚：`SECURITY.md:19-20` 用 `No official public relay, no telemetry, no log upload` 明确表「没有」，无歧义；GUI 源码零遥测 grep（`HttpWebRequest`/`WebClient`/`HttpClient`/`Sentry`/`TcpClient`/`UdpClient`/`WebRequest`/`WriteAllBytes` 全 0）。无与决策冲突措辞。 |
| 4 | 登记链一致性 | **通过** | 全链实算吻合：复审报告 `F9623EBD6AF6D166C1F41A86C6443206824565DBDE7B03E9D3270EBEEFA4CD0F`（README `L4,L1484` 写缩写 `F9623EBD…`；HANDOVER `L169` 写完整 64 位，符合要求）；实现报告 `561B8EEF…`（README `L1483`、HANDOVER `L173`）；源码 `2DFFBFAA…`（README `L1484`、HANDOVER `L173`，实算一致）；exe `9B480FE0…`（同上，本轮修复后值）；自检 `25920647…`（HANDOVER `L173`）。陈旧值扫描：`73D24F50` 与 `0DC34A3F` 在 README/HANDOVER 中**各 0 命中**；`60C15128` 各 1 命中，均在「首轮 NOT PASS」语境（README `L1484`、HANDOVER `L169`），非当前值。编码：README 无 BOM、CRLF=1485、bareLF=0（符合 brief「README CRLF/bareLF=0」）；HANDOVER 无 BOM、CRLF=174、bareLF=0、bareCR=0。唯一瑕疵为 README 1 个孤立 bare CR（N-3）。 |
| 5 | 边界语强制保留 | **通过** | README `L4` 尾部 P1 GUI 句含「机械证据≠双人验证，不勾 E2-A/E2-B/E3」；`L1485` 含「headless 自检与窗口冒烟不是真实游戏注入端到端、更不是双人真实联机，不得写成 E2-A/E2-B/E3 通过；Gate A 仍未批准」。HANDOVER `L175` 含「机械/headless/窗口证据≠双人真实联机；不勾 E2-A/E2-B/E3；Gate A 未批准」。复审报告 `L22,L108-110` 同样保留。无过度承诺；「实现完成/两轮审计通过」限定在 GUI 产品级实现与机械证据范围，未升级为双人或 Gate A 结论。 |
| 6 | .gui 证据真实存在 | **通过** | 自检输出 `C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\gui-fix-20261118-1852\gui-selftest-fixed.txt` 实存，97 B / `259206473068A1A8AE1203852E68AB1122AFD9632181C64740A13C6C125342E6`，实读 3 行：`CivLink GUI SELFTEST PASS` / `checks=33 failed=0` / `gate=双人验证未完成（Gate A 未批准）` → PASS 33/33 属实。源码 `civlink/gui/civlink_tray.cs` 35,707 B / `2DFFBFAA…`、exe 26,112 B / `9B480FE0…` 均实算吻合，是修复后值而非旧 `73D24F50`。exe 按 `source_sha256 + 26112 字节 + exit=0` 口径验收（`docs/M0D-GUI-IMPL-REVIEW-2-20261118.md:57`、`civlink/gui/build-manifest.txt` note 行），本机哈希波动不判缺陷。路径解析差异见 N-2。 |
| 7 | 贡献/安全政策可执行性 | **通过** | `CONTRIBUTING.md:23-34` 构建命令与实存脚本一致：`civlink/build-msvc.cmd`（`/MT` + pin v1.3.4）、`civlink/gui/build-gui.ps1`、`cargo +1.75.0 --offline`、从 repo 外目录跑注入测试；`:29-30` 验收口径「stable source hash + 9,216/23,552/26,112-byte size + exit 0，**not** output SHA-256」与 `build-manifest.txt` note（T1 9,216 → T2 23,552 → 本轮 26,112 的历史演进）及 `SECURITY.md:53-58` 一致；`:41-45` 禁 bind 62056 / SO_REUSEADDR 与 `REVIEW-2:100` 一致；`:55-59` UTF-8 无 BOM / README CRLF 与实际编码一致。`SECURITY.md:30-33` 明确写 `Contact channel will be filled in before publication`，诚实标为待补而非虚构。重大安全项未遗漏：`SECURITY.md:63-65` 如实声明 CVLH2/发现帧明文。 |
| 8 | 新发现 | **需修正（4 项，全低severity，不阻断）** | 见 §4：N-1（低-中，NOTICES 漏 HDE/Patkov 署名）、N-2（低，证据目录相对路径在 audit 快照根下不解析）、N-3（低，README L1442 单个 bare CR）、N-4（低，README L4 `****P1 GUI` 强调标记不配对）。 |

---

## 3. 八项文件哈希与编码实测表

全部磁盘实算；`BOM` 指 UTF-8 BOM（EF BB BF）；换行计数为逐字节扫描（CRLF / bareLF / bareCR）。

| # | 文件 | 字节 | SHA-256（实算） | BOM | CRLF | bareLF | bareCR | 结论 |
|---|---|---|---|---|---|---|---|---|
| 1 | `LICENSE` | 1,598 | `F8301978DAE0EDDA574073B093020A0D0A30B4F5EDF74B33E0F96EDF096946B6` | 无 | 0 | 29 | 0 | ✓ 纯 LF，MIT 正文完整 |
| 2 | `docs/LICENSE-DOCS.md` | 1,815 | `BEF8D9FBDBE8961A6F14F91995488E08A524770E10C5B4696AC8E226FA675F6B` | 无 | 0 | 39 | 0 | ✓ 纯 LF |
| 3 | `THIRD-PARTY-NOTICES.md` | 2,536 | `305278ADDB67286BB42CC5066FDE5B84210E6BD76B05FCA312DA110408A4A69E` | 无 | 0 | 49 | 0 | ✓ 纯 LF；内容见 N-1 |
| 4 | `CONTRIBUTING.md` | 3,316 | `93DB49C281ACAEE6542E4E151CFB0304676ADEA4748AAA237F678CEAA882D5A9` | 无 | 0 | 65 | 0 | ✓ 纯 LF |
| 5 | `SECURITY.md` | 3,149 | `CB223D7810B19BE51EE09322A737E5739E1730702B7788A2835AD17597A78AA7` | 无 | 0 | 68 | 0 | ✓ 纯 LF |
| 6 | `README.md` | 138,142 | `504A9F92BE6FDE487F2D3B4A84CBF0FE6E53F80A0ADB708D8E02E5201D0F5A2A` | 无 | 1,485 | 0 | **1** | ⚠ N-3（bareCR 1，byte offset 127187，L1442）；CRLF/bareLF 符合要求 |
| 7 | `docs/CODEX-HANDOVER-M0A.md` | 52,712 | `7215CF29889C73AA8CF0A3DA1BD5203340E5B33E9C36E23B3BA553AF234010A1` | 无 | 174 | 0 | 0 | ✓ CRLF 一致 |
| 8 | `docs/M0D-GUI-IMPL-REVIEW-2-20261118.md` | 13,666 | `F9623EBD6AF6D166C1F41A86C6443206824565DBDE7B03E9D3270EBEEFA4CD0F` | 无 | 0 | 109 | 0 | ✓ 与 brief 期望逐项一致；110 行（末行无 LF） |

**≥10 项附加哈希/行号抽查（全部磁盘实读，非采信 brief）**

| 抽查项 | 实算值 / 行号 | 与登记关系 |
|---|---|---|
| `civlink/gui/civlink_tray.cs` | 35,707 B / `2DFFBFAA50CC73045AD9F1224EC098AD738EBCD105B3061693CBE8ABFF9C774A` | 与 README/HANDOVER/REVIEW-2 一致 |
| `civlink/gui/civlink_tray.exe` | 26,112 B / `9B480FE0C8183B8D523E8B749111EDC403962F31F832381CE50C75378DD52B46` | 与登记一致，修复后值 |
| `docs/M0D-GUI-IMPL-20261118.md` | 9,375 B / `561B8EEFB035219964A69A843722976544F18F845DF0CD3AD036197E50158654` | 实现报告登记正确 |
| `.../gui-fix-20261118-1852/gui-selftest-fixed.txt` | 97 B / `259206473068A1A8AE1203852E68AB1122AFD9632181C64740A13C6C125342E6` | PASS 33/33 属实 |
| `deps/MinHook/LICENSE.txt` | 4,446 B / `4F21F857550D7BE854DA6EA5F2DA4E6775CA4E3FBB535E4F3D961C47D0BF3335`，有 BOM，CRLF=81 | L2 Tsuda Kageyu 2009-2017；L28/31/58 Patkov |
| `civlink/agent/Cargo.lock` | 157 B / `6584D23FC75653AC665E54D85CA152CD04D0F13DB5CC7A12D12387DD4FFEAFD4` | 仅含 crate 自身 |
| `civlink/fakeip/Cargo.lock` | 158 B / `6DCC0FB19C64FF36F6F063FC303CFBA846C44D8A9747300FFDAF5B6697A5452A` | 仅含 crate 自身 |
| `civlink/relay/Cargo.lock` | 157 B / `7D0A9FF02069C31C8037C451AE118B12EE15760B92FDADCD40F34C1F3915C53F` | 仅含 crate 自身 |
| `civlink/gui/build-gui.ps1` | 4,005 B / `21E3EDC868A761BB1EABBC3B87C87A76923FCBA078826D4F07D393CA922754A0` | L13 指向 `gui/civlink_tray.cs`；L14-25 系统程序集 |
| `civlink/gui/build-manifest.txt` | 2,740 B / `5670FE3D90E7D1BA29533ED65F6FB362861A9AC6EB3AE31AD8A92E38D07C2332` | source_sha256/output_bytes/output_sha256 与实算一致 |
| `LICENSE:15-21` | `THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND…` | MIT 免责声明完整 |
| `README.md:1442` | bare CR @ byte 127187，`agent summary <CR>eply source` | N-3 定位 |
| `docs/CODEX-HANDOVER-M0A.md:167,169,173,175` | 第 22 项状态/证据/边界 | 完整 64 位 F9623EBD |
| `docs/M0D-OPENSOURCE-PLAN-20261118.md:279` | `MinHook v1.3.4（含 HDE32/64）… HDE 部分 Copyright (c) 2008-2009 Vyacheslav Patkov` | N-1 的基线要求 |
| `docs/M0D-GUI-IMPL-REVIEW-2-20261118.md:57` | exe 哈希口径声明（22 字节 PE/MVID 波动不算篡改） | 与 build-manifest note 一致 |

---

## 4. 新发现表

| 编号 | 严重度 | 发现 | 性质 / 证据 | 阻断骨架就绪 | 阻断公开发布 |
|---|---|---|---|---|---|
| N-1 | **低-中** | `THIRD-PARTY-NOTICES.md` 遗漏 MinHook 内嵌 HDE32/64 的 `Portions Copyright (c) 2008-2009, Vyacheslav Patkov` 署名（BSD-3 条款部分），全文无 `HDE`/`Patkov` 字样 | 与 `deps/MinHook/LICENSE.txt:28,31,58`、`deps/MinHook/src/hde/hde64.c:3`、`hde32.c:3` 及 plan `docs/M0D-OPENSOURCE-PLAN-20261118.md:279` 不一致。**缓解**：完整许可证文本随 `deps/MinHook/LICENSE.txt` 捆绑，NOTICE `L17-19` 明确指向该文件，BSD 条件（署名/条件/免责声明保留）在分发层面仍满足；属清单摘要缺项而非版权违约。 | **否** | **是（发布前必须补）** |
| N-2 | 低 | 登记的相对证据路径 `M0A\captures\gui-fix-20261118-1852\gui-selftest-fixed.txt` 在 audit 快照根 `CivLink-M0A-audit` 下不存在；实体在父项目根 `C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\...` | 审计快照与父项目目录布局差异。证据本体实存且哈希/内容吻合（§2 Q6），非证据伪造。README `L1484`/HANDOVER `L173`/REVIEW-2 `L49` 均用同一相对路径。建议在发布说明中注明证据位于父项目 M0A 捕获目录，或随发布包附副本。 | 否 | 否（建议项） |
| N-3 | 低 | `README.md` L1442（byte offset 127187）有 1 个孤立 bare CR（0x0D），位于 `agent summary <CR>eply source` 处；其余 1,485 处换行均为 CRLF，bareLF=0 | 编码瑕疵，不影响 UTF-8 有效性或内容语义；brief 的「README CRLF/bareLF=0」口径在 bareLF 维度满足，仅多 1 个孤立 CR。 | 否 | 否（建议项） |
| N-4 | 低 | `README.md` L4 状态行尾部出现 `****P1 GUI（…）…详见 v1.35 修订记录。**`，强调标记 4 开 2 闭不配对 | Markdown 渲染瑕疵（可能显示为字面 `**` 或整句斜体加粗）；内容本身正确、边界语完整，不影响合规结论。疑为 v1.35 追加时前句 `**...**` 闭合并与新句 `**...**` 开启相邻所致。 | 否 | 否（建议项） |

**明确排除的假象（非缺陷）**：① GUI exe `output_sha256` 波动——按 `source_sha256 + 26112 字节 + exit=0` 验收，属本机缺官方 .NET Framework reference assemblies 的 22 字节 PE/MVID 差异，不判篡改；② 控制台重编译 gate 行乱码——GBK 显示层假象，原始 outfile 为 UTF-8 无 BOM 且中文正常；③ `60C15128`/`0DC34A3F`/`73D24F50` 在 README/HANDOVER 中不作为「当前值」出现。

**署名待补（非缺陷，已诚实标注）**：`LICENSE:3` 与 `docs/LICENSE-DOCS.md:30-33`、`README.md:1486`、`docs/CODEX-HANDOVER-M0A.md:175` 均将 `2026 CivLink Contributors` 标为 provisional / 待确认，未虚构最终权利人；`SECURITY.md:30-33` 的 Vuln 联系渠道同样诚实标为待补。两者应由负责人在发布前定稿，但不构成本轮合规缺陷。

---

## 5. 下一步（修正项与责任人）

| 序 | 修正项 | 责任人 | 时点 | 阻断项 |
|---|---|---|---|---|
| 1 | 在 `THIRD-PARTY-NOTICES.md` 第 1 节补一行：`Portions Copyright (c) 2008-2009, Vyacheslav Patkov (HDE32/HDE64, BSD-3-Clause)`，并保留对 `deps/MinHook/LICENSE.txt` 全文的指向；补后重算该文件 SHA-256 并按需更新引用 | 文档维护者（负责人复核） | **首次公开推送/发布前必须** | N-1（阻断公开发布，不阻断骨架就绪） |
| 2 | 定稿版权署名：确认 `2026 CivLink Contributors` 或替换为真实权利人，同步 `LICENSE:3`、`docs/LICENSE-DOCS.md:30-33`、`README.md:1486`、`docs/CODEX-HANDOVER-M0A.md:175` | 负责人 | 发布前 | 非阻断（已诚实标注待确认） |
| 3 | 定稿 `SECURITY.md:30-33` 的漏洞联系渠道（启用 GitHub Security Advisory 或给出实邮箱），替换 `will be filled in before publication` | 负责人 | 发布前 | 非阻断（已诚实标注待补） |
| 4 | 在发布说明/证据索引中注明 `M0A\captures\gui-fix-20261118-1852\` 位于父项目根而非 audit 快照根，或将自检输出随发布包附副本并登记新哈希 | 构建/发布负责人 | 发布时（建议） | N-2，非阻断 |
| 5 | 修正 `README.md:1442` 的孤立 bare CR（改回标准 CRLF），并将 `README.md:4` 的 `****P1 GUI` 改为 `**P1 GUI`（4 开 2 闭 → 2 开 2 闭）；改后重算 README SHA-256 并核对是否有下游登记引用 | 文档维护者 | 下轮维护（建议） | N-3/N-4，非阻断 |
| 6 | 保持边界语与哈希登记链不变；后续任何 GUI 源码/产物变更须按 `source_sha256 + 字节数 + exit=0` 口径重新验收，并重跑独立审计 | 全体 | 持续 | 强制约束 |

**审计员签署**：独立审计员（CivLink M0D）。所有证据经磁盘实读与实算，未采信口述；未修改任何被审文件；未启动真实游戏、未做网络/联机操作。裁定：**有条件通过**；`allow_open_source_skeleton_ready = true`；新发现 **4** 项（N-1..N-4），其中阻断公开发布 1 项（N-1）、阻断骨架就绪 0 项。

## 6. 修复记录（项目侧执行，2026-11-18 19:36，非审计员改动）

> 本段由项目侧在审计员交付后追加，仅记录对 §5 修正项的执行情况；**不修改审计员的任何既有结论行**，因此 §2 表中 `README.md` 的 138,142 B / `504A9F92…` 保留为**审计基线快照值**（审计当时实读值），不得当作当前值。

| 修正项 | 状态 | 证据 |
|---|---|---|
| 1（N-1 HDE 署名） | **已关闭** | `THIRD-PARTY-NOTICES.md` 第 1 节新增 `Bundled HDE32/HDE64 portion: Portions Copyright (c) 2008-2009, Vyacheslav Patkov …`，并保留对 `deps/MinHook/LICENSE.txt:27-59` 与 `src/hde/hde32.c:3`、`hde64.c:3` 的指向；`License` 行收窄为 "for the core library" |
| 2（署名定稿） | **已关闭** | 负责人 2026-11-18 决定署名 **shengtong**：`LICENSE:3` = `Copyright (c) 2026 shengtong`；`docs/LICENSE-DOCS.md:30-33` 同步并标注 "confirmed by the project owner on 2026-11-18"；`README.md` v1.35 记录块同步 |
| 5（N-3/N-4 编码瑕疵） | **已关闭** | `README.md` 的 1 个孤立 bare CR（`agent summary <CR>eply source`）改为 `agent summary reply source`；L4 尾部 `****P1 GUI` → `**P1 GUI`。修后实测 **138,140 B / `dab3f0d7ac12f317f3dce9f0edd1fd302190f47d8404ec3d9fb348d8ad24379b` / BOM=False / CRLF=1485 / bareLF=0 / bareCR=0** |
| 3（SECURITY 联系渠道） | **未关闭（非阻断）** | `SECURITY.md` 仍为 `will be filled in before publication`；发布前须由负责人给出 GitHub Security Advisory 或邮箱 |
| 4（N-2 证据路径） | **未关闭（发布时处理）** | `docs/M0D-RELEASE-READINESS-20261118.md` 已记录该路径口径（证据在父项目根 `C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\`）；发布包须附副本或索引说明 |

**修复后全部被审文件的当前值（2026-11-18 19:39 实算，取代 §2 表）**：

| 文件 | 字节 | SHA-256 | BOM | CRLF | bareLF | bareCR |
|---|---|---|---|---|---|---|
| `LICENSE` | 1587 | `a5a3e2ce01fe2af49aa1824abc792819ae8118156c5bab35245fb6e0af59ba52` | False | 0 | 29 | 0 |
| `docs\LICENSE-DOCS.md` | 1792 | `032df19f345c543cebd4a934ebf42b78a25fe5930c253aff08a23d36518bfc34` | False | 0 | 39 | 0 |
| `THIRD-PARTY-NOTICES.md` | 3012 | `b1a4b6037641ded65bb92183c3b5d4c82f023090e558958a95671a84574e26c1` | False | 0 | 55 | 0 |
| `CONTRIBUTING.md` | 3316 | `93db49c281acaee6542e4e151cfb0304676adea4748aaa237f678ceaa882d5a9` | False | 0 | 65 | 0 |
| `SECURITY.md` | 3149 | `cb223d7810b19be51ee09322a737e5739e1730702b7788a2835ad17597a78aa7` | False | 0 | 68 | 0 |
| `README.md` | 138140 | `dab3f0d7ac12f317f3dce9f0edd1fd302190f47d8404ec3d9fb348d8ad24379b` | False | 1485 | 0 | 0 |
| `docs\CODEX-HANDOVER-M0A.md` | 52823 | `1dfaaf440c68f2aea668f862dbbd7050d93387ebd2d987d0aae3c4874063c9d4` | False | 174 | 0 | 0 |

> §2 表中的 LICENSE 1,598 B/F8301978…、docs/LICENSE-DOCS.md 1,815 B/BEF8D9FB…、THIRD-PARTY-NOTICES.md 2,536 B/305278AD…、README.md 138,142 B/504A9F92…、docs/CODEX-HANDOVER-M0A.md 52,712 B/7215CF29… 一律视为**审计当时基线快照**，不得当作当前值引用。
