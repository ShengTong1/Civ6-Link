# REV-009：metric helper v3.3 独立复核与一次性往返审批

- 日期：2026-11-12
- 复核对象：v3.3 `set-broadcast-path.ps1`、REV-008 响应、selftest/restore 原始输出
- 决定：**v3.3 的 REV-008 核心修复通过静态审查；批准一次受控 PC-A apply→restore 验证，限本报告 §5 条件。此批准不等于产品/常态使用批准。**
- E2-A：维持 REV-006 已批准，现可由 PC-B 本地用户/AI 按计划继续。metric 验证须与 E2-A/E2-B 捕获窗口分开。
- PC-B：不批准同步 v3.3。Gate A 未批准，M0-B 冻结。

## 1. 检查方法与证据等级

本次只读检查了完整脚本、响应文档、selftest 与 restore 原始输出，重算文件哈希并解析 PowerShell AST；未运行脚本、未执行任何 `Set-NetIPInterface`，未改网卡。

- **源码确认 / 本地只读验证**：当前工作区文件、哈希、AST 和行号。
- **执行端报告采信**：归档的 selftest/restore 输出；本次没有独立重跑这些用例。
- **外部官方依据**：Microsoft Learn 说明设置 `-InterfaceMetric` 会自动禁用 `AutomaticMetric`。
- **推断/限制**：根据脚本的路由选择与当前接口状态计算一次性测试预期。

## 2. 文件身份与归档核验

| 项目 | 大小 | 本地 SHA256 | 结果 |
|---|---:|---|---|
| `CivLink-M0A-audit/scripts/set-broadcast-path.ps1` | 52,374 B | `860106F782267DB8F4D4BDE01085921C119EC38C57EC71C35647654DB458FD95` | 与提交一致 |
| `REV-008-METRIC-HELPER-V3.3-RESPONSE.md` | 11,202 B | `F2BE5651E741B3BC28569890D68D253F318E3D523D5A78C0CE8FD1ED5CDA9201` | 与提交一致 |
| `raw-selftest-output.txt` | 4,822 B | `03BB7286C3279D04AB5B5EFFCAB3878ECDA16EFB81449998B978C2011E326984` | 与提交一致 |
| `raw-restore-cases.txt` | 10,371 B | `A9F61D35EFDDF14D39C4621168569CEF9C7DC83CCB734F1ABFB8249EF79E4C0C` | 与提交一致 |

脚本本地 PowerShell AST 解析错误数为 **0**，行数 1,019，UTF-8 BOM 单个、纯 LF、内部 BOM 字符为 0。响应文档写 1,020 行；本地行计数是 1,019 行，字节数和 SHA256 与提交一致。PC-B 工具包仍为 v2，12,227 B，SHA256 `76DD95B067C36AC6CEA268300807FB642BC5B62F6E122A5443016D6DABC86AF2`。

## 3. REV-008 修复审查

### 3.1 R-3b 字段允许集合 —— 源码确认通过

`set-broadcast-path.ps1:387-438` 的纯函数 `Get-PrecheckDrift` 对 restore 将写入的接口字段做预检：

- changed metric 在 `{OriginalMetric, TargetMetric}`；
- changed AutomaticMetric 在 `{OriginalAuto, Disabled}`；
- keep metric 在 `{OriginalMetric, TargetMetric}`；
- keep AutomaticMetric 在 `{Disabled, OriginalAuto}`。

允许集与 `Set-NetIPInterface -InterfaceMetric` 会自动禁用 `AutomaticMetric` 的行为相符。[Microsoft Learn：Set-NetIPInterface](https://learn.microsoft.com/en-us/powershell/module/nettcpip/set-netipinterface?view=windowsserver2025-ps)

### 3.2 apply/restore readback —— 源码确认通过

- apply 对 changed 和 keep 项以 `auto='Disabled'` 做 readback（`:795-799`），不会再跳过自动度量状态。
- restore 对 `OriginalAuto=Enabled` 的接口跳过数值 metric 比较、严格核对 Auto 状态（`:979-988`），符合 Windows 重新启用自动 metric 后按链路速度重算数值的语义。

### 3.3 事务写入、自测与残留披露 —— 源码确认通过，测试按执行端报告采信

- 文件操作经 `$script:TxOps` 注入表，`Invoke-BackupTx` 明确描述为有序文件操作，不声称跨文件原子提交（`:267-383`）。失败时会执行清理并枚举残留；异常清理失败会向调用方报告 residual。
- `tx-selftest` 覆盖 9 个失败阶段及成功路径（`:441-572`）。归档输出显示前 8 个故障阶段无正式 JSON/有效 sidecar/残留；cleanup 故障如实报告 1 个无效 sidecar；成功路径通过。
- 进程强杀/断电会跳过 catch/finally 的限制已在源注释及响应文档披露。selftest 不证明断电/强杀语义，也不需要把它描述成跨文件事务原子性。

### 3.4 未还原守卫与备份退休 —— 源码确认通过

- Apply 的未还原备份守卫在 DryRun 与无动作集返回之前（`:691-721`），可避免“dry-run 返回成功、真实 apply 被拒”的已知缺陷。
- restore 完成 readback 后把备份改名为 `.restored.json`，sidecar 一并归档（`:1005-1018`）；`Get-BackupList` 默认排除 restored 文件（`:228-243`），修复成功 restore 后永久锁住后续 apply 的问题。

## 4. 现场诊断文本待更正

源码 restore 成功分支 `:935-938` 当前打印：

`changed: ... AutomaticMetric == orig`

但实际预检规则是 `{OriginalAuto, Disabled}`。对于 `OriginalAuto=Enabled` 且已 apply 的接口，正确状态通常是 Disabled。该行属于**过时且错误的摘要文本**，不是预检逻辑错误；不过现场操作员可能据此误读审查结果。

进入实际往返前，须把该摘要改成类似“AutomaticMetric in `{orig,Disabled}`”，并同步 UTF-8/行数/哈希记录。另一个低优先级文本问题：运行 banner 仍显示 `(v3)`（`:575-580`），不影响执行；建议在归档产物中明确脚本实际 SHA，避免操作记录只写模糊版本名。

## 5. 一次性 PC-A 真实往返授权及严格条件

### 授权范围

**仅批准 PC-A 一次 apply→restore 往返**，目的是验证 v3.3 的真实 `Set-NetIPInterface`、readback、restore readback 与备份退休路径。不得据此宣传 helper 已适用于常态使用或产品已解决联机问题。批准在下面全部前置条件满足后生效：

1. 先更正 §4 过时的 restore 摘要文本；重新提交脚本哈希与 AST=0 结果。
2. 选择与 E2-A/E2-B 完全分离的窗口；Civilization VI 已退出，双端不抓包、不进行联机测试，PC-A 不承载需保持的网络会话。
3. 在 PC-A 使用独立 BackupDir；先保存 apply 前的 `Get-NetIPInterface`、相关路由、`snapshot` 和 SHA256。该基线仅代表**测试开始前当前状态**，不是 E0 原始基线。
4. 先执行只读状态/`-DryRun` 检查。当前 `-PeerIp 192.168.31.214` 会选择 WLAN ifIndex 10；当前 WLAN metric=45，其他可改接口 metric 更高，因此改动集为空，apply 将 `NOTHING TO DO`，不能作为真实往返。不要把该 no-op 算成验证通过。
5. 现有归档记录 PC-B Radmin 地址为 `26.187.101.177`。可把它作为候选 `PeerIp`，但必须由本次 DryRun 在 PC-A 实际确认 `keep=if18 Radmin VPN`，且计划**恰为**：目标 metric 2045；changed 为 if10 WLAN `45→2045`、if15 ZeroTier `1045→2045`；if1 loopback、if58 WSL、if25 Default Switch 不变。若 route/接口/任一数值不符，停止，不执行 apply。
6. Apply 前重新读取实际状态，必须与本节下方的前置状态表一致；`apply` 后必须检查 exit code、schema=4 备份/sidecar、全部目标字段 readback。随后使用刚生成的**明确备份文件路径**执行 restore，确认 readback、`.restored.json`/sidecar 归档成功，并再次采集快照与哈希。
7. 任何 apply/restore 非零退出、readback 不符、备份/sidecar 残留或接口漂移：立即停止实验，不进行第二次 apply、不手工猜测恢复值；保存现场输出并提交复核。

### 本次测试前置状态与预期恢复状态

取自 REV-006 snapshot，已在当前工作区核验其文件哈希。它不是 E0 还原基线。

| 接口 | 测试前预期 | apply 预期（仅 DryRun 精确匹配后） | restore 后预期 |
|---|---|---|---|
| if10 WLAN | 45 / Disabled | 2045 / Disabled | 45 / Disabled |
| if1 Loopback | 75 / Enabled | 不变 | 75 / Enabled |
| if18 Radmin VPN | 1045 / Disabled | keep 1045 / Disabled | 1045 / Disabled |
| if15 ZeroTier | 1045 / Disabled | 2045 / Disabled | 1045 / Disabled |
| if58 WSL | 5000 / Disabled | 不变 | 5000 / Disabled |
| if25 Default Switch | 5000 / Disabled | 不变 | 5000 / Disabled |

这些数值是审批测试夹具。若测试时当前接口状态不同，以停止条件处理，不自行套用表格覆盖现值。E0 中 WLAN `35/Enabled` 与此处 `45/Disabled` 的差异仍未解决；本次验证只证明恢复到测试开始前状态，不恢复也不认证 E0 原始状态。

## 6. 其他决定与门禁

- **v3.3 代码状态**：通过一次性受控验证前的静态审查；真实适用性仍待该往返证据。
- **PC-A 原状态**：本次测试后回到测试开始时现状，不主张恢复至 E0。另行恢复 E0 必须先重建可信原值与 AutomaticMetric 证据并另行审批。
- **PC-B 同步**：不批准。待 PC-A 往返归档、复核通过后再单独决定。
- **E2-A**：无需等待 metric 测试，可按 REV-006 已批准计划继续；metric 真实往返不得与其捕获窗口重叠。
- Gate A 未批准；M0-B 冻结。E4/H7/H11 仍缺第三台真实机器，E5 仍缺 Win64EOS 构建。
