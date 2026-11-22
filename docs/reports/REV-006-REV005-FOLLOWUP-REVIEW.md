# REV-006：REV-005 后续处置复核与 PC-B 执行决断

- 日期：2026-11-12
- 范围：metric helper v3 源码与离线验证记录、E2-A 重做单、E2-B 计划
- 决断：**批准只读 PC-A 当前状态 snapshot；批准准备并执行修订后的 E2-A；E2-B 原则批准，须在 E2-A 证据归档后执行。拒绝当前 v3 在真实网卡上 apply/restore。**

## 1. metric helper v3

### 已确认

- 脚本 `CivLink-M0A-audit/scripts/set-broadcast-path.ps1` 当前 SHA256 为
  `714B41063213704D7A2CD6145AA3CA6049D7B8361C97C566B4FE33837A2B1AF4`；PowerShell AST 解析错误 **0**。
- 源码实现了 schema=2、keep 接口原值、错误计数/readback、snapshot/list-backups，以及 v2 空备份拒绝。报告说明 T1–T13 全部在 DryRun/权限门禁内完成，没有实际调用 `Set-NetIPInterface`。此项作为**执行端离线测试记录**采信；本复核没有重跑 13 个用例。
- `snapshot` 动作只读网络接口并写状态文件，可用于记录**当前**配置；它不是恢复原始配置的凭证。

### 仍需修复后再批准真实 apply/restore

1. **备份名仍可能碰撞并覆盖**：脚本第 393 行时间戳仅精确到秒，第 412–414 行直接对路径调用 `Set-Content` 且没有排他创建/目标已存在检查。对不同 `PeerIp`（或 `-Force`）在同一秒调用，`civlink-metric-<stamp>.json` 可能相同并被覆盖，和“永不覆盖”保证不符。使用 GUID/更高精度唯一名并原子地以 `CreateNew` 写入。
2. **备份写入未严格 fail-closed**：文件顶层 `$ErrorActionPreference='Continue'`；第 413 行 `Set-Content` 未设 `-ErrorAction Stop`，第 414 行只检查文件是否存在，不验证 JSON 完整、schema/字段正确或内容 hash。写入部分失败但文件已创建时仍可能继续改网卡。应写临时文件、解析并验证回读，再原子改名；未验证成功不得执行任何 `Set-NetIPInterface`。
3. **restore 未核对备份主机和 apply 后现值**：`Read-Backup` 检查 JSON/schema，但 restore 前未要求 `$bak.host -eq $env:COMPUTERNAME`；备份来自另一台机器时可能对相同 ifIndex 应用错误值。虽然备份含 `TargetMetric`，restore 也未在修改前确认网卡当前状态仍等于该次 apply 的目标值。增加主机/接口身份检查，以及现值不符时的拒绝或显式差异确认。
4. `-Force` 允许对同一 peer 叠加修改，提示语已警告风险，但 restore 默认只挑最新备份。需明确并实现栈式回滚顺序，或删除 `-Force`，以免把中间状态误当原始状态。

因此：**v3 离线重构有进展，但目前不满足真实网卡 apply/restore 的审批条件。PC-B 仍保持 v2，不同步 v3；E2 执行期间禁止调用 v2/v3 的 apply/restore。**

## 2. E2-A 重做单：角色方向已修正

`REV-005-FOLLOWUP-PLAN.md` §2.2 第 1 步指定 **A 建房、B 刷新**；但第 5 步要求“A 端界面出现 B 的房间条目”，§2.3 成功判据也要求“A 端界面出现 B 的条目”。这把 host/client 方向写反了。

复核时将其修为：B（client）界面应出现 A（host）的房间条目。A 端记录其 host 是否发出与 B 刷新对应的响应；两端 pcapng 保存请求/响应 tuple、载荷长度/JSON（若确有 1104B JSON），并以刷新事件的目标、源、方向交叉确认。不能仅以“出现任意 1104B JSON”判成功，必须确认是本轮 host 对 client 发现请求的关联响应。

其余执行门禁正确：两端每个窗口记录 PID、角色、注入状态和时间；A host 注入并保持房间，B 完全重启后保持原生未注入；两端同时抓包；metric apply/restore 禁止。

已更正 [REV-005-FOLLOWUP-PLAN.md](REV-005-FOLLOWUP-PLAN.md) §2.2/§2.3。**批准 PC-B 本机用户/本机 AI 执行 E2-A**。PC-B 用户本地处理 UAC；不得交换远程桌面或账户凭据。

## 3. E2-B 决断

**E2-B 原则批准，安排在 E2-A 的 PCAPNG、A trace、PID/注入表和响应结论完成归档之后。**E2-B 是 M0-A 中 H6（T_window/T_response）与 H9/H10 生命周期证据，不因已有路由观察而豁免。

执行要求：E2-A 收尾后两端完全退出并重启；A/B 使用新 PID，角色/tag 清晰；B 刷新 10 次；逐轮记录首广播/首响应/closesocket；两端完整抓包；将注入版和原生结果并列，报告差异。

## 4. PC-A snapshot 与 metric 恢复

- **批准先取 PC-A 当前只读 snapshot**（v3 `-Action snapshot` 或等价 `Get-NetIPInterface`/`Get-NetRoute` 导出），保存 snapshot JSON/TXT 的 SHA256。只记录当前 WLAN=45、Radmin/ZeroTier=1045 等状态，不进行改动。
- **不批准把当前 snapshot 当成还原依据**；它记录的是已改后的状态。
- **暂不执行手工恢复**：E0 route 表与操作单对 WLAN metric 有 35/45 差异，且原 AutomaticMetric 状态不完整。先用原始 Windows/E0 证据重建每个接口的原 `InterfaceMetric` 与 `AutomaticMetric`；如无法确认，应由用户决定采用系统自动值，而不能声称精确回滚。
- 旧 v2 backup `entries=[]` 不可用；v3 当前没有真实 apply 形成的可信回滚备份。

## 5. 门禁

批准范围仅为 PC-B 的 M0-A E2-A/E2-B 观测、PC-A 只读 snapshot，以及 metric helper 继续离线修复。**不批准任何真实网卡 metric 修改，不批准 Gate A，不启动 M0-B。**两台真实 Civ6 电脑仍无法满足 v2.1 E4/H7/H11 的三端验收要求。
