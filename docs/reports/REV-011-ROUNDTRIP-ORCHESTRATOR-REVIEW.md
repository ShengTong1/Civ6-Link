# REV-011：REV-009 往返编排器审查与路由复测决定

- 日期：2026-11-12
- 复核对象：`scripts/rev009-roundtrip.ps1`、`scripts/RUN-REV009-roundtrip.cmd`、当前 v3.3 helper
- 决定：**不批准按当前 `RUN-REV009-roundtrip.cmd` 执行真实 apply→restore。选择真实 PC-B 地址 + 单条 destination-cache 定向清理路线；批准清理及 DryRun 复测，不批准当前编排器进入 Execute。**
- PC-A 自身地址 `26.74.126.98` 不视为 peer，不满足 REV-009 条件⑤。
- REV-009 一次性往返条件授权仍保留，但需修复本报告 §3 的编排器阻断项并由真实 peer DryRun 精确通过后才生效。

## 1. 文件身份与本地静态检查

| 文件 | 大小 | SHA256 | 结果 |
|---|---:|---|---|
| `CivLink-M0A-audit/scripts/set-broadcast-path.ps1` | 53,017 B | `206808649AC0F29AC50523E2B7A358B5CD2F0051B091CE8ACBEDAD8FDAC64CCA` | 与提交一致；AST 0 错误 |
| `CivLink-M0A-audit/scripts/rev009-roundtrip.ps1` | 18,696 B | `B402DB3C7BF6E593149E3450910AFD02C2D5BE2A5EDC659559445B737EFC2055` | AST 0 错误 |
| `CivLink-M0A-audit/scripts/RUN-REV009-roundtrip.cmd` | 1,243 B | `15A1D03BB34253E12F98980715B39C7884CD74E4E11C15EE79390EBB034324DF` | 已静态阅读 |
| 回归输出 `raw-regression.txt` | 14,138 B | `304ED03EDB6B30811D1FFBFE2C65E7D72B85EF3A7BAADEA4E9333DF5311DD310` | 哈希与提交一致，测试结果按执行端报告采信 |

本次未运行编排器、CMD、helper、`netsh` 或 `Set-NetIPInterface`。PC-A destination-cache 内容及 DryRun 输出按执行端提交的原始记录采信，未在本机独立复现。

## 2. peer 与 cache 决定

拒绝把 `26.74.126.98` 当成 peer：这是 PC-A 自己的地址；它选择 if18 只说明本机 `/32` local route，不表示到另一台电脑的 peer path。CMD 当前把该地址作为默认值（`RUN-REV009-roundtrip.cmd:4-5`），必须移除该默认并显式要求真实 peer 地址。

按 REV-010 的既有授权，可以在 PC-A 管理员终端仅清理 WLAN ifIndex 10 上 PC-B 地址 `26.187.101.177` 的单项缓存：

```text
netsh interface ipv4 delete destinationcache interface=10 address=26.187.101.177
```

微软命令文档支持使用 interface 与 address 限定待删 destination-cache 项：[netsh interface](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/netsh-interface)。不要执行不带接口/地址的全表清理，不修改静态或持久路由。删除后立即保存 `show destinationcache`、`GetBestInterface`、`Find-NetRoute` 与真实 peer DryRun 输出。若 DryRun 仍不匹配 REV-009 夹具，停止，不 apply；不得用本机 IP 代替。

## 3. 编排器阻断项

### P1-1 CMD 默认 peer 是本机地址

`RUN-REV009-roundtrip.cmd:4-5` 在未传参数时将 `PEER` 默认设为 `26.74.126.98`；`rev009-roundtrip.ps1:25-26` 的示例也推荐该地址。执行者只需输入 YES 就会以这个本机地址启动 `-Execute`。DryRun 计划在该地址下可以符合 raise 夹具，所以计划匹配并不能证明地址是 peer。

**要求**：CMD 不得提供本机地址默认值；缺少显式 peer 参数时拒绝启动。编排器还必须把 PeerIp 与本机所有 IPv4 地址比较，匹配本机地址时在创建执行阶段前拒绝。

### P1-2 raise 接口断言没有与计划行绑定

`rev009-roundtrip.ps1:239-246` 检查 raise 数量等于 2，然后分别搜索整个 DryRun 输出是否出现 `if=10` 与 `if=15`。这些接口编号也会出现在前面的接口表中，因此当前断言可能在真正 raise 的是其他两个接口时仍通过。

**要求**：解析 `[plan]` 区段中的 raise 明细，逐行断言恰好为 if10 `45→2045` 与 if15 `1045→2045`；keep 行恰好 if18/1045；不得从全输出的接口表满足 raise 断言。

### P1-3 snapshot 子步骤失败未阻断

`rev009-roundtrip.ps1:191-193` 调用 helper snapshot 后只记录退出码，没有在 `$snap.Code -ne 0` 时停止。REV-009 前置条件③要求保存 helper snapshot；snapshot 失败时流程仍可继续到未来的 Execute。

**要求**：snapshot 非零退出立即停止，并把完整输出保存为失败证据；在 snapshot 成功前不得进入 DryRun/Execute 后续步骤。

### P1-4 apply/restore 失败路径会错误声称“没有改动”且缺少现场状态快照

`Stop-Now` 在 `:69-73` 无条件写 “Nothing was changed”。但 apply 已启动后，helper 可能已修改一部分或全部接口，再以非零码返回；调用方在 `:284-287` 直接 Stop-Now，未先保存当前接口状态。restore 非零时 `:333-335` 也直接退出，未归档可能部分恢复后的现状。

**要求**：执行阶段非零退出时不得声称没有改动；立即只读采集并归档当前 `Get-NetIPInterface`/route、备份/sidecar 文件列表与完整输出，再停止并按预设人工恢复决策升级。不得静默继续或启动第二次 apply。

## 4. 其余执行端报告项目

- helper 文本修正哈希和 AST 已本地确认；`raw-regression.txt` 的提交哈希也已重算一致。
- 回归用例和 `-Execute` 无提权拒绝按执行端输出采信，本次未重跑。
- 目前脚本已经确认条件⑤不通过：真实 peer `26.187.101.177` 当前 DryRun 是 WLAN keep + NOTHING TO DO。故没有调用 apply 是正确处置。
- 未执行网卡修改；PC-A 网络值据执行端报告仍为 if10 `45/Disabled`、if15 `1045/Disabled`，备份目录 0 文件。

## 5. 后续审批边界

1. 现在可按第 2 节执行已批准的单条 destination-cache 删除和只读复测。
2. 当前 `RUN-REV009-roundtrip.cmd` 不得用于真实执行；修复 P1-1..P1-4 后提交新哈希与回归输出。
3. 只有真实 PC-B PeerIp 的 DryRun 精确匹配 `keep if18`、raise if10/if15 到 2045、其余接口不变，且独立 BackupDir/snapshot、无游戏/抓包、前态不漂移全部满足时，REV-009 一次性往返授权才生效。
4. `26.74.126.98` 无论 DryRun 计划是否吻合，均不得作为 peer 执行。
5. Gate A 未批准；M0-B 冻结；v3.3 不同步 PC-B。
