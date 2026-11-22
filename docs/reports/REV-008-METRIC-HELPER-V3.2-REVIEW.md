# REV-008：metric helper v3.2 独立复核与审批决定

- 日期：2026-11-12
- 复核对象：`CivLink-M0A-audit/scripts/set-broadcast-path.ps1` v3.2 与 `REV-006-007-METRIC-HELPER-V3.2-RESPONSE.md`
- 决定：**R-3 的覆盖范围修复和 schema≥3 sidecar fail-closed 已落实；但发现新的 R-3 阻断缺陷，v3.2 暂不批准真实 apply/restore。真实 apply→restore 往返不授权，v3.2 不同步 PC-B。**
- E2-A：**可按 REV-006 已批准的双机执行单继续**，不依赖 metric helper；本次不需要等待 v3.2 复核完成。
- Gate A：未批准。M0-B：冻结。

## 1. 复核范围与证据等级

本次读取 v3.2 脚本与响应文档，复核关键源代码行，重新计算两份文件 SHA256，并解析 PowerShell AST。没有执行 apply/restore，没有调用 `Set-NetIPInterface`，没有改动 PC-A 网卡，也没有复跑执行端的 P1-P5、R4/R5、S1-S5 用例。

- **源码确认**：由当前工作区文件直接确认。
- **本地只读验证**：本次本地 SHA256/AST 结果。
- **执行端报告**：响应文档提供的用例结果，本次未独立复现。
- **外部官方依据**：Microsoft Learn 对 `Set-NetIPInterface -InterfaceMetric` 的参数行为说明。
- **推断**：基于源码和官方参数说明推导出的恢复风险。

## 2. 文件身份与本地验证

| 文件 | 大小 | 本地 SHA256 | 提交值 |
|---|---:|---|---|
| `CivLink-M0A-audit/scripts/set-broadcast-path.ps1` | 36,930 B | `94427A66536EEBCFE912EA488FDDBAF2ADA3AC727BEB483DA84B2900B51EC198` | 一致 |
| `CivLink-M0A-audit/docs/reports/REV-006-007-METRIC-HELPER-V3.2-RESPONSE.md` | 14,723 B | `F0DC02C3336CE66912FDD15C7AAF680CA44958AF97F2BD39ED163C1A1683DF47` | 一致 |

v3.2 PowerShell AST 解析错误数为 **0**。`M0A/pcb-kit/set-broadcast-path.ps1` 按执行端报告仍为 v2；本次没有修改或复制该文件。

## 3. REV-007 两项整改复核

### 3.1 restore 预检字段覆盖：目标已实现，但状态模型仍有缺陷

源码 `set-broadcast-path.ps1:602-675` 现在逐字段检查：changed 的 metric、changed 的 AutomaticMetric、keep 的 metric、keep 的 AutomaticMetric，并在漂移时于网卡写入前 exit 2。keep 记录缺失和接口读取失败也会被拒绝。字段级诊断和 D-8 名称占位回退逻辑在 `:620-628`。

执行端报告中的 P1-P5/R4/R5 是报告级测试证据，本次没有独立复跑。源码结构与其所述预期相符，但其中 changed AutomaticMetric 的允许集合是错误的，详见 §4。

### 3.2 schema≥3 sidecar fail-closed：源码确认通过

- Apply 阶段 `:457-481` 暂存 sidecar、回读校验后提交，再提交 JSON；出现普通 PowerShell 异常时进入清理路径。
- Restore 阶段 `:562-585` 对 schema≥3 拒绝缺失、空值、非 64 位十六进制和哈希不符的 sidecar，并对大小写归一。

S1-S5 仅按执行端响应文档采信。源码中两文件是有序的文件系统操作，并非跨文件系统原子事务：进程被强制终止或断电时，`finally/catch` 清理不会运行。按当前顺序，sidecar 单独残留不匹配 apply-backup JSON 守卫，且网卡修改发生在两者提交后；这属于需要故障注入验证的事务边界，不是本次发现的新的网卡状态覆盖路径。报告不得把“两个文件共同原子提交”当作已经证明的事实。

## 4. 新阻断项 R-3b：设置 InterfaceMetric 会自动关闭 AutomaticMetric

v3.2 在 `set-broadcast-path.ps1:609-612` 假定 changed 接口的 apply 只更改 Metric、不会更改 AutomaticMetric；相应 restore 预检 `:643-645` 要求当前 Auto 必须仍等于 `OriginalAuto`。但 changed 接口在 apply 时调用 `Set-Metric -auto ''`（`:493-495`），而 `Set-Metric` 的 `:192` 执行：

`Set-NetIPInterface ... -InterfaceMetric $metric`

Microsoft Learn 对 `-InterfaceMetric` 明确说明：**设置该参数值时，AutomaticMetric 参数会自动禁用**。[Microsoft Learn：Set-NetIPInterface](https://learn.microsoft.com/en-us/powershell/module/nettcpip/set-netipinterface?view=windowsserver2025-ps)

因此当 changed 接口的 `OriginalAuto=Enabled` 时，apply 设置 metric 后系统会将 Auto 变为 Disabled；restore 预检却只允许 Auto=Enabled。**推断：正常成功的 apply 会被 restore 当作漂移拒绝，导致无法按该备份恢复 AutomaticMetric。**即使当前 PC-A 的被改接口碰巧原本 Disabled，也不能据此证明工具在一般支持状态下安全。

该问题同时暴露 apply readback 不完整：`set-broadcast-path.ps1:484` 对 changed 项调用 `Test-Row -auto ''`，`:207-208` 因空 `$auto` 而跳过 AutomaticMetric 检查。因此脚本没有确认设置 metric 后 Auto 是否如官方文档所述被关闭，也没有把真实 apply 状态与备份允许集合闭环验证。

**修订要求：**

1. changed 的 AutomaticMetric 允许值应反映真实 setter 行为：至少考虑 `OriginalAuto` 与因 `-InterfaceMetric` 自动禁用产生的 `Disabled`；若改用明确保持 Auto 的操作，须用官方行为和只读/拒绝路径证据证明。
2. apply readback 应核对 changed 项的 AutomaticMetric，并在备份/日志中明确记录实际目标状态。
3. 增加 `OriginalAuto=Enabled` 的模拟 apply→restore 预检用例，证明成功应用后 restore 会放行；同时保留真正外部漂移拒绝用例。
4. 对 keep 项和部分 apply 情况保留现有允许集合约束，不能为了放行而把任意 Auto 值加入集合。

## 5. 三项审批决断

1. **v3.2 是否可接受**：接受 REV-007 两项整改的实现方向；D-8 是误拒修复。**整体不批准为真实网卡变更就绪版本**，因为 R-3b 使 `OriginalAuto=Enabled` 的 changed 接口存在不可恢复路径。
2. **是否授权一次真实 apply→restore 往返**：**不授权**。先修复 R-3b，再复核脚本和 apply readback。
3. **是否单独设计两阶段提交故障注入**：**需要**。在隔离临时目录、通过可注入文件操作/故障点覆盖 sidecar 写入、sidecar 回读、sidecar 提交、JSON 提交及清理失败；断言失败时没有正式 apply JSON/有效 sidecar、没有调用任何网卡修改，并记录每个失败点的残留状态。该验证只针对文件事务，不接触真实网卡。

完成 R-3b 修订及离线文件故障注入后，再进行代码复核并决定是否授权一次受控的真实 apply→restore。真实往返仍需要单独的明确批准。

## 6. E2-A 与阶段门禁

E2-A 已由 REV-006 批准，执行步骤和判据见 `REV-005-FOLLOWUP-PLAN.md:22-48`。它不依赖 metric helper，因此**可以现在由 PC-B 本地用户/本地 AI 按执行单继续**：A 建房并注入，B 重启后保持原生未注入、刷新并记录 PID/角色/点击时间；双端抓包，判据仍是 B 看到 A 房间以及与刷新相关联的房主响应/1104B JSON。实验期间不调用 v2/v3.2 的 apply/restore，也不把广播可达性替代协议响应判据。

本次复核不操作 PC-B，也不通过本地工作区声称 E2-A 已执行。E2-A 结果归档后再依计划评估 E2-B。E4/H7/H11 仍需第三台真实机器；E5 仍需 Win64EOS 构建。**Gate A 未批准，M0-B 继续冻结。**
