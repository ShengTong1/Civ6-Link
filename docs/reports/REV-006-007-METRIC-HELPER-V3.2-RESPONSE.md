# metric helper v3.1 → v3.2 —— R-1..R-4、REV-007 修订与验证记录

- 文档编号：REV-006/007-METRIC-HELPER-V3.2-RESPONSE
- 性质：对 `REV-006-REV005-FOLLOWUP-REVIEW.md` 四项风险（R-1..R-4）与 `REV-007-METRIC-HELPER-V3.1-REVIEW.md` §3.2/§3.3 两项阻断的代码级响应
- 日期：2026-11-12
- 门禁：**Gate A 未批准、M0-B 冻结。本文件不构成把 v3.2 用于真实网卡修改的授权。**

## 0. 边界声明（先读这一段）

本文件只记录**离线代码修复 + 只读/拒绝路径验证**。

- 全程未执行任何 `Set-NetIPInterface`，未改动任何网卡状态。
- 所有成功用例都止于 `-DryRun` 计划输出；所有被拒绝用例在触碰网卡前退出。
- 真实网卡 apply/restore **仍被审计拒绝**；v3.2 **不得同步到 PC-B**。
- REV-007 指出的两项阻断（R-3 预检不完整、sidecar 非 fail-closed）已修；本次又自查出两处自身缺陷（D-7 已修、D-8 见 §3）。

## 1. 文件身份

| 项目 | 值 |
|---|---|
| 路径 | `CivLink-M0A-audit\scripts\set-broadcast-path.ps1` |
| 大小 | 36 930 B |
| SHA256 | `94427A66536EEBCFE912EA488FDDBAF2ADA3AC727BEB483DA84B2900B51EC198` |
| 编码 | UTF-8 带 BOM |
| PowerShell AST 解析 | 0 个语法错误 |
| v3.1（REV-007 审阅版） | 31 324 B / `35F1A65595BEAE5ADB36BED51770EC54D4D9B09D15854B884FD7835EAAFCF423` |
| v3 | 31 091 B / `AE27EA4D…` |
| v2（有缺陷，PC-B 在用的那份） | 12 227 B / `76DD95B0…` |

**版本隔离核对**：`M0A\pcb-kit\set-broadcast-path.ps1` 仍为 v2 `76DD95B0…`（12 227 B），本次未改动 —— 符合 REV-007 第 4 项决定。


## 2. R-1..R-4 逐项处置

### R-1 备份名碰撞 + 非排他写入

审计原文风险：秒级时间戳在同一秒内两次 apply 会碰撞；`Set-Content` 直接写路径，无排他语义。

修复：
- 文件名改为 `civlink-metric-<yyyyMMdd-HHmmss>-<guid8>.json`（L405-406）。
- 写入改为 `[IO.File]::Open($tmp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)`（L438）——目标已存在即抛异常，**不存在静默覆盖路径**。
- 先用临时文件 `$bakPath.tmp` 写入，再 `Move-Item` 原子改名到最终名（L451）；`Move-Item` 在目标存在时失败，形成第二道排他。

验证：T8 同秒生成 5 个名字，唯一数 = 5。

### R-2 备份写入 fail-closed —— v3.2 收紧（REV-007 §3.2）

审计原文风险：`$ErrorActionPreference='Continue'`、`Set-Content` 无 `-ErrorAction Stop`、只判断文件存在而不校验内容，部分失败后仍可能继续改网卡。

**v3.1 已做的**：写临时文件（CreateNew + 显式 `Write` + `Flush($true)`）→ `Get-FileHash` → `ConvertFrom-Json` 回读校验 `schema>=3` / `host` / `peerIp` / `changed` 条数 / `keep.ifIndex` → `Move-Item` 原子改名 → 写 sidecar；任一环节失败 `exit 2`，且网卡尚未被触碰。

**REV-007 §3.2 指出的两个缺口，v3.2 的处置**：

1. **JSON 先落盘、sidecar 后写** → sidecar 写失败会残留一个孤立 apply 备份，被"未还原 apply 守卫"当成真实锁。
   → 改为**两阶段提交**：先算临时文件哈希并**暂存** sidecar（`.sha256.tmp` → 回读校验），再 `Move-Item` sidecar 到正式名，最后 `Move-Item` JSON 到正式名；若 JSON 提交失败则**回删 sidecar**；提交后再复核正式 JSON 的哈希等于已验证的临时哈希。失败时 `exit 2` 并**清理全部残留**（JSON + sidecar + 两个 tmp）。
2. **sidecar 缺失只告警，仍继续 restore** → 削弱了"备份身份已验证"的保证。
   → 改为 **schema>=3 必须 fail-closed**：sidecar 不存在 / 为空 / 不是 64 位十六进制 / 与内容哈希不符，**一律 `exit 2`**；只有 schema<3 的旧备份才走告警路径（而 schema<2 已被 `Read-Backup` 直接拒绝）。哈希比较做大小写归一（`.ToUpperInvariant()`）。

历史缺陷补充：v3 首版曾用 `$bakPath | Out-File -FilePath "$bakPath.sha256"`，把**路径**写进了哈希文件。该写法已删除，改为写入哈希本身（ASCII，单行）。

### R-3 restore 主机/现状检查 —— v3.1 未通过；v3.2 重写（REV-007 §3.3）

审计原文风险：未确认备份来自本机；未确认网卡现值仍是那次 apply 的目标值。

**v3.1 的问题（REV-007 §3.3 认定阻断）**：预检只覆盖了它将要写入字段的一部分。

- `changed` 项只比 metric，**没有比 AutomaticMetric**；而 restore 随后会把 `OriginalAuto` 写回。
- `keep` 项只检查"接口存在"，**metric 与 AutomaticMetric 都没检查**；而 apply 会写 keep 的 metric 与 `AutomaticMetric=Disabled`，restore 会写回两者的原值。
- 结论：只比部分字段，等于允许 restore 静默覆盖 apply 之后发生的变化。

**v3.2 的修订**：把规则改成"**任何将被写入的字段，其现值必须落在该项允许集合内，否则拒绝**"。

| 接口类别 | 字段 | apply 实际写了什么 | 允许的现值集合 |
|---|---|---|---|
| changed | Metric | 只会写成 `TargetMetric` | `{OriginalMetric, TargetMetric}`（允许部分 apply 的半完成状态） |
| changed | AutomaticMetric | **不写** | 必须等于 `OriginalAuto` |
| keep | Metric | 写成 `TargetMetric`（= apply 时的现值） | `{OriginalMetric, TargetMetric}` |
| keep | AutomaticMetric | 写成 `Disabled` | `{Disabled, OriginalAuto}` |

其它拒绝条件：接口不存在、`keep` 记录缺失、读取失败，一律在**任何 `Set-NetIPInterface` 之前** `exit 2`。诊断输出改为按字段逐行打印 `interface / field / allowed / now / why`。

**新增拒绝用例（见 §4 P1-P5、R3/R5）**：changed 的 AutomaticMetric 漂移、keep 的 metric 漂移、keep 的 AutomaticMetric 漂移，以及"允许的半完成状态"放行用例。


### R-4 `-Force` 叠加与 restore 语义冲突

审计原文风险：`-Force` 允许在未还原的备份上再叠一次，而 restore 默认只取最新 —— 原始值会被永久丢失。

修复：**删除 `-Force` 参数**（源码内 `$Force` 引用数 = 0），替换为"一台机器同时只允许一笔未还原 apply"：

```
[refused] an unrestored apply-backup already exists: <name>
Only ONE outstanding apply is allowed: a second apply would record
already-changed values as if they were original.
Restore first (-Action restore), then apply again.
```

退出码 `5`。

## 3. 审计未提出、但自查修掉的缺陷

### D-7 dry run 会预测出"实际会被拒绝的 apply"（v3.1 已修，v3.2 保持）

- 现象：v3.1 初版的 `-DryRun` 早退位于 R-4 守卫**之前**（当时的 L371 早于 L384）。当机器上存在未还原备份时，`apply -DryRun` 会打印一份完整计划并 `exit 0`，而真实 apply 会被 `exit 5` 拒绝。
- 危害：dry run 的用途就是"在不改网卡的条件下预测真实行为"。若 dry run 说可以、真跑却拒绝，dry run 就失去意义，且容易让操作者误以为已具备执行条件。
- 修复：把 R-4 守卫整体移到 `-DryRun` 早退之前。顺序变为：**计划生成 → 未还原备份守卫 → DryRun 早退 → 管理员门禁 → 备份写入 → 应用**。

| 用例 | 修复前 | 修复后 |
|---|---|---|
| T10 `apply -DryRun` 且存在未还原备份 | `exit 0`（打印计划，误判可执行） | `exit 5` + `[refused] an unrestored apply-backup already exists` |
| T11 `apply -DryRun` 无未还原备份 | `exit 0` + 计划 | 不变，`exit 0` + 计划 |

### D-8 接口名字比对会误判"换成别的适配器"（v3.2 自查并修）

- 现象：v3.2 增加"接口身份一致"检查时，直接比较备份里记录的名字与 `Get-IfName` 的返回值。但 `Get-NetAdapter` 解析不了回环等接口，`Get-IfName` 会回退成 `(if1)`。于是比对"回环" vs `(if1)` 必然不等，**一个完全正常的备份被判成接口被换掉**。
- 首次复现：用例 P5（keep = 回环，仅 AutomaticMetric 真实漂移）却报了 2 条 drift，其中一条是假的 Name 不符。
- 危害方向是"误拒"而非"误放行"，所以不构成安全缺口；但它会让拒绝理由失真，把真实原因（AutomaticMetric 漂移）淹没在噪声里，也让操作者无法判断该信哪一条。
- 修复：把名字比较降级为**辅助证据** —— 两侧都解析出真实适配器名字时才比较；任一侧是 `(ifN)` 占位就直接跳过该项。
- 复验：R4（keep=回环，状态未漂移）→ 放行；R5（keep=回环，AutomaticMetric 真实漂移）→ 只报那一条 AutomaticMetric，`exit 2`。

## 4. 验证用例

全部用例在 `%TEMP%` 下的独立备份目录运行，`-BackupDir` 指向临时目录，**未触及 `%USERPROFILE%` 下既有备份，也未改动网卡**。

### 4.1 v3.1 阶段的 T1-T12（REV-007 已按执行端报告采信）

| # | 场景 | 触发路径 | 结果 | 退出码 |
|---|---|---|---|---|
| T1 | `status -PeerIp 192.168.31.214` | 只读 | `[OK] predicted broadcast exit (if=10) EQUALS peer path (if=10)` | 0 |
| T2 | `snapshot` | 只读 | 写出 2579 B JSON + 724 B TXT | 0 |
| T3 | restore v2 旧备份 | schema 校验 | `backup has no schema>=2 marker` | 2 |
| T4 | restore 外来主机备份 | 主机校验 | `backup was taken on host 'SOMEONE-ELSE-PC', this machine is 'DESKTOP-E9ERP1I'` | 2 |
| T5 | restore 漂移备份 | 现状校验 | `if=18 Radmin VPN expected~9999 now=1045 (neither target nor original)` | 2 |
| T6 | sidecar 哈希不符 | sidecar | `backup content does not match its sidecar hash` | 2 |
| T7 | sidecar 正确 | sidecar 通过 | `sidecar hash verified` → `safe to restore` → 计划 | 0 |
| T8 | 同秒 5 次命名 | R-1 | 5 个名字，唯一数 5 | - |
| T9 | 有未还原备份 + 非管理员 | R-4 / 门禁 | 被管理员门禁先拦 | 1 |
| T10 | 有未还原备份 + `-DryRun` | R-4 | `[refused] an unrestored apply-backup already exists` | 5（修复前 0） |
| T11 | 无未还原备份 + `-DryRun` | 计划路径 | `skip 1 (loopback)` / `raise 2 to metric 2045` | 0 |
| T12 | `list-backups` | 只读 | 列出 `schema=3 peer=… keepIf=10 changed=1` | 0 |

### 4.2 v3.2 新增：restore 预检字段覆盖（REV-007 §3.3 第 4 条要求的拒绝用例）

PC-A 真实现状：if10 WLAN=45/Disabled、if18 Radmin=1045/Disabled、if1 回环=75/Enabled。

| # | 场景 | 期望 | 实测 |
|---|---|---|---|
| P1 | changed 的 AutomaticMetric 记录 `Enabled`、现值 `Disabled` | 拒 | `exit 2`，`if=18 Radmin VPN AutomaticMetric allowed=Enabled now=Disabled (apply never changes this field on changed adapters)` |
| P2 | changed 的 AutomaticMetric 记录 `Disabled`、现值 `Disabled`（一致） | 放行 | `exit 0`，`safe to restore` |
| P3 | keep 的 metric 记录 45/45、现值 75 | 拒 | `exit 2`（注：该轮同时命中了当时的 Name 误报，见 §3 D-8） |
| P4 | keep 的 AutomaticMetric 记录 `Disabled`、现值 `Disabled` | 放行 | `exit 0`，`safe to restore` |
| P5 | keep 的 AutomaticMetric 记录 `Disabled`、现值 `Enabled` | 拒 | `exit 2`，`if=1 回环 AutomaticMetric allowed=Disabled/Disabled now=Enabled` |
| R4 | keep=回环，名字解析为 `(if1)`，状态未漂移 | 放行（名字不误报） | `exit 0`，`safe to restore` |
| R5 | keep=回环，AutomaticMetric 真实漂移 | 拒，且只报该字段 | `exit 2`，仅 1 条 AutomaticMetric drift |

### 4.3 v3.2 新增：sidecar fail-closed（REV-007 §3.2 要求）

| # | 场景 | 期望 | 实测 |
|---|---|---|---|
| S1 | schema=3 备份无 sidecar | 拒 | `exit 2`，`schema=3 backup has no .sha256 sidecar` / `Content identity cannot be proven` |
| S2 | sidecar 为空 | 拒 | `exit 2`，`sidecar is not a 64-hex SHA256` |
| S3 | sidecar 非十六进制 | 拒 | `exit 2`，`sidecar is not a 64-hex SHA256` |
| S4 | sidecar 内容正确但小写 | 放行（大小写归一） | `exit 0`，`sidecar hash verified` |
| S5 | sidecar 哈希与内容不符 | 拒 | `exit 2`，`backup content does not match its sidecar hash` |

**说明**：S1-S4 中的"无 sidecar 曾被当作告警放行"已不存在。测试过程中我自己写错了辅助函数的类型名（`Text.ASCIIEncoder`），导致 sidecar 未生成，脚本按 fail-closed 直接拒绝 —— 这恰好反向验证了 S1 的行为。

## 5. 仍未做的事（明确披露）

1. **未在真实网卡上执行 apply/restore** —— REV-007 第 2 项明确不授权，本文件也不主张授权。
2. **未验证 apply/restore 成功后 `Test-Row` readback 在真实网卡上的表现** —— 只在代码路径层面确认了 `-ErrorAction Stop` + try/catch + 退出码 3/4 的分支存在。
3. **未验证 sidecar 两阶段提交在真实失败场景下的原子性** —— 只做了代码审查与类型级推演，未注入 I/O 故障（需另设计故障注入点，属下一步）。
4. **未处理 D-6 之外的接口筛选** —— 目前只排除 loopback / 127.x；其它"不承载广播"的接口（如 Teredo 伪接口）未单独排除。
5. **未同步任何副本到 PC-B** —— `M0A\pcb-kit\set-broadcast-path.ps1` 仍为 v2；REV-007 第 4 项明确现在不允许同步。
6. **PC-A 网卡现状未恢复** —— 当前 WLAN=45(Disabled) / Loopback=75(Enabled) / Radmin=1045(Disabled) / ZeroTier=1045(Disabled) / WSL=5000 / DefaultSwitch=5000。按 REV-007 第 3 项，该状态作为 **E2 的已知实验偏差**记录，`REV-006-snapshot-20261112\` 只证明当时现状，**不能作为恢复依据**。

## 6. 退出码表（v3.2）

| 码 | 含义 |
|---|---|
| 0 | 成功（含只读动作、dry run、无可做之事） |
| 1 | 需要管理员 |
| 2 | 参数错误 / 备份不可用（schema、主机、字段漂移、sidecar 缺失或损坏、kind 不符） |
| 3 | restore 后逐项校验失败 |
| 4 | apply 后逐项校验失败 |
| 5 | 拒绝执行（存在未还原 apply 备份） |

## 7. 待审计决断

1. v3.2 代码是否可接受（R-1/R-2 rev/R-3 rev/R-4 + D-7 + D-8）。
2. 若接受，是否授权在**单台机器、可回滚窗口内**做一次真实 apply→restore 往返（这会补上 §5 第 1、2 项）。
3. 故障注入点是否要单独设计（补 §5 第 3 项）。
4. PC-A 网卡现值如何处置：按 REV-007 第 3 项作为 E2 已知偏差记录，还是另行授权恢复。
5. v3.2 何时允许同步到 PC-B（当前明确禁止）。

## 8. 门禁状态

- Gate A：**未批准**
- M0-B：**冻结**
- E2-A 合规重做：审计已批准 PC-B 本机执行，判据为"B 看到 A 的房间"+ host 对 client 刷新的关联响应 + 1104B JSON
- E2-B：原则批准，须在 E2-A 归档后执行
- E4 / H7 / H11：需第三台真实端，当前两机不满足
- E5：需 Win64EOS 构建，当前不存在
