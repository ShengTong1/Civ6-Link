# REV-007：metric helper v3.1 独立复核与审批决定

- 日期：2026-11-12
- 复核对象：`CivLink-M0A-audit/scripts/set-broadcast-path.ps1` v3.1、执行端响应、PC-A snapshot
- 决定：**不批准 v3.1 用于真实网卡 apply/restore；不授权真实往返；不允许同步至 PC-B。PC-A 当前配置作为已知偏差记录，暂不更改。**
- Gate A：未批准。M0-B：冻结。

## 1. 复核方法与证据等级

本次检查了 v3.1 完整脚本、REV-006 后续复核及 v3.1 响应文档，并对脚本运行 PowerShell AST 解析、重新计算 SHA256、读取 snapshot 文件及重新计算其哈希。**未执行 apply、restore 或 `Set-NetIPInterface`，未操作网络接口；未重跑 T1-T12。**

以下标记区分证据来源：

- **源码确认**：由当前工作区文件内容直接确认。
- **本地只读验证**：本次在当前工作区执行的解析、哈希和文件读取。
- **执行端测试报告**：响应文档记录的测试结果；本次未独立复现。
- **推断**：基于源码行为推导出的风险。
- **未验证**：当前证据不能得出结论。

## 2. 总结

R-1 唯一命名/排他临时创建、R-2 写入回读校验、R-4 禁止叠加 apply、D-7 DryRun 顺序修正均已在源码中体现。脚本 SHA256 与提交值一致：

`35F1A65595BEAE5ADB36BED51770EC54D4D9B09D15854B884FD7835EAAFCF423`

本地 AST 解析错误数为 0。执行端提供的 T1-T12 结果目前只按**执行端报告采信**，不能视为本次独立复测。

但 R-3 的 restore 预检仍不完整：它没有验证被恢复接口的 AutomaticMetric，也没有验证 keep 接口的当前 metric/AutomaticMetric 是否仍处于本次 apply 允许的状态。restore 因而可能在用户或 VPN/系统组件已改变这些值后，静默覆盖该变化。此项是**真实配置变更的阻断问题**。

此外，schema=3 备份缺少 sidecar 时仅告警并继续；这削弱了“备份身份已验证”的保证。它不是本次拒绝真实往返的唯一理由，但应收敛为 fail-closed。

## 3. 逐项复核

### 3.1 R-1：备份唯一性与排他写入 —— 源码确认通过

- `set-broadcast-path.ps1:408-409` 文件名包含时间戳与 GUID8。
- `:438` 使用 `FileMode.CreateNew` 写临时文件，已存在时会失败。
- `:451` 将临时文件移动至最终备份名，并使用 `-ErrorAction Stop`。

源码具备避免秒级同名覆盖的措施。T8“同秒五个唯一名”仅有执行端报告，本次未重跑。

### 3.2 R-2：备份写入 fail-closed —— 部分通过，需收紧 sidecar

源码确认：`:433-448` 生成临时 JSON、落盘 flush、回读解析并核对 schema/host/peer/changed 数/keepIf；`:451-468` 在备份验证失败时退出，尚未执行网卡修改。

但 `:451-454` 是先把 JSON 移到正式路径，再写 sidecar。若 sidecar 写入失败，代码会在 `:460-468` 以 exit 2 结束，网卡不会被触碰；不过正式 JSON 会残留。**推断**：残留的 apply 备份会被 `:379-388` 识别为未还原备份，进而拒绝后续 apply，形成需人工处理的孤立锁。

更关键的是 restore 的 `:537-550` 在 sidecar 不存在时只打印警告并继续；对 schema=3 新格式也不例外。因此不能把“sidecar 已验证”当成所有 restore 的前置条件。建议 schema=3 必须要求 sidecar 存在、可读且为 64 位十六进制 SHA256；缺失/空值/格式错误/不匹配均拒绝。sidecar 创建失败时，应安全清理正式 JSON，或明确将其标为不可恢复、不可参与未还原 apply 守卫的事务失败记录。

### 3.3 R-3：restore 主机/现状检查 —— 未通过（阻断）

主机名检查已存在：`set-broadcast-path.ps1:237-243`。但现状预检不覆盖全部会被写入的状态：

- **被改接口**：`:569-575` 只比较 `$now.Metric` 与 `TargetMetric` / `OriginalMetric`，没有比较 `$now.Auto`。restore 随后在 `:612` 把 `OriginalAuto` 写回。若 AutomaticMetric 在 apply 后被用户或系统改动，预检仍可能放行并覆盖。
- **keep 接口**：`:576-579` 只检查接口存在，没有检查其 metric 或 Auto。apply 在 `:477-480` 会对 keep 接口执行 `Set-Metric`（metric 写为当前值并将 AutomaticMetric 设为 Disabled）；restore 在 `:617` 会写回 `OriginalMetric` 和 `OriginalAuto`。若 keep 接口的任一值后来发生漂移，当前预检仍然可能报告“safe to restore”。

这与报告声称的“逐接口比对现值，既非 target 也非 original 判 drifted”不一致：源码仅对 `changed` 的 metric 做了该比较，且未检查 keep 的值。恢复动作会写回多项配置，所以预检必须覆盖每一项将被写入的字段。

**修订要求**：

1. `changed` 项至少核对 metric 在原值/目标值集合内，并核对 AutomaticMetric 仍等于其原值（apply 对这些接口不应修改该字段）。
2. `keep` 项核对 metric 等于记录的 `TargetMetric`/原值，并核对 AutomaticMetric 等于 apply 后目标 `Disabled` 或记录的 `OriginalAuto`。
3. 任意字段超出允许集合、接口身份不一致或读取失败时，在任何 `Set-NetIPInterface` 调用前拒绝 restore。
4. 增加拒绝用例覆盖 keep metric 漂移、keep AutomaticMetric 漂移、changed AutomaticMetric 漂移，以及允许的部分 apply 状态。提交对应原始输出。

### 3.4 R-4 与 D-7 —— 源码确认通过

- `:371-389` 在 DryRun 早退之前阻止已有未还原 apply；`-Force` 不在参数表中（`:65-74`），源码中也无 `$Force` 引用。
- `:391-395` 随后才处理 apply DryRun。

此顺序修复了“DryRun 报可执行、真实 apply 却拒绝”的不一致。T10/T11 结果来自执行端报告，本次未复测。

## 4. snapshot 复核

用户所述 snapshot 位于仓库根目录的 `M0A/captures/REV-006-snapshot-20261112/`，不在 `CivLink-M0A-audit` 子目录下。本次已找到并重算完整哈希：

| 文件 | 大小 | 本地 SHA256 | 与提交前缀 |
|---|---:|---|---|
| `civlink-state-20261112-194636.json` | 2579 B | `0C2260760F95494992006C29CA102B508A0BE8A46D7F88FEB8F4C9656AFFED23` | 一致 |
| `civlink-state-20261112-194636.txt` | 724 B | `8B26AF178236CB9C13F2F5E403DCEC7DA7CEBCC56FFB783F86537C8B392A70C2` | 一致 |
| `raw-Get-NetIPInterface.txt` | 1057 B | `73843FAD18BCA38727C6205F3E86DF0060A7227C7601E505898D6D1D02DA8384` | 一致 |
| `raw-Get-NetRoute.txt` | 3131 B | `24B27E215B4E684FB6BD82633DB96FDA34B4982C3BB5F19AB9CFD7AAE717C00B` | 一致 |

TXT 记录当时 WLAN metric=45 / AutomaticMetric=Disabled，Radmin 与 ZeroTier metric=1045 / AutomaticMetric=Disabled，loopback=75 / Enabled，WSL 与 Default Switch=5000 / Disabled。该 snapshot 确认的是**当时现状**，不提供原始值证据，不能据此恢复。

## 5. 四项审批决定

1. **v3.1 是否接受**：接受其离线整改方向和 R-1/R-2/R-4/D-7 已实现部分；**不接受为真实网卡变更就绪版本**，R-3 仍阻断，R-2 sidecar 也需 fail-closed 收敛。
2. **是否授权真实 apply→restore 往返**：**不授权**。在 restore 预检完整覆盖所有将被写入字段、sidecar fail-closed，并有拒绝路径证据前，不进行真实网卡往返。
3. **PC-A 当前 metric 如何处理**：**暂不恢复、不再修改**。E2 报告把该快照状态列为已知实验偏差/环境状态，避免称其为原始基线。恢复依据仍须来自 E0/Windows 原始证据；若无法重建，另行提出明确方案后审批。snapshot 不可充当回滚依据。
4. **何时同步到 PC-B**：**现在不允许同步 v3.1**。PC-B 按已批准的 E2-A/E2-B 计划继续观测，但期间不调用 v2/v3.1 的 apply/restore；待 R-3 与 sidecar 修订复核通过后，再决定是否另行批准同步。工具级审查通过本身不批准 Gate A 或启动 M0-B。

## 6. 状态边界

- E2-A/E2-B 可按 REV-006 已批准计划，在不改 metric 的前提下继续。
- E4/H7/H11 仍缺第三台真实机器；E5 仍缺 Win64EOS 构建。
- Gate A 未批准；M0-B 冻结。
- 当前结论只针对本次审阅的文件版本和证据，未对真实网卡应用行为作背书。
