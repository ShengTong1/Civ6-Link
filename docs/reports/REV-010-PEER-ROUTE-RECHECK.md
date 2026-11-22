# REV-010：REV-009 往返前置条件⑤复核决定

- 日期：2026-11-12
- 对象：v3.3 文本修正、PC-A 两个候选 PeerIp 的 DryRun 与 destination cache 异常
- 决定：**不接受本机 Radmin 地址 `26.74.126.98` 作为 peer；批准在 PC-A 只删除 WLAN ifIndex 10 上 `26.187.101.177` 的单条 IPv4 destination-cache 项，然后重做只读路由/DryRun 核对。当前不执行 apply。**
- REV-009 的一次性 apply→restore 条件授权保留，但只有 DryRun 精确满足条件⑤、执行前 snapshot/独立备份目录完成且其它前置条件仍成立后才生效。

## 1. 文件与证据核对

当前脚本 SHA256：

`206808649AC0F29AC50523E2B7A358B5CD2F0051B091CE8ACBEDAD8FDAC64CCA`

本地重新计算一致；PowerShell AST 解析错误数为 0。`M0A/captures/REV-009-textfix-20261112/raw-regression.txt` 为 14,138 B，本地 SHA256：

`304ED03EDB6B30811D1FFBFE2C65E7D72B85EF3A7BAADEA4E9333DF5311DD310`

提交方提供的 destination cache、GetBestInterface 和路由表观测尚未由本次独立执行验证，按执行端报告采信。

## 2. Peer 选择决定

`26.74.126.98` 是 PC-A 自己的 Radmin 地址。它命中本机 `/32` local route 并使脚本选择 if18，只证明“本机地址对应 Radmin 接口”，不代表“到另一台机器的 peer path”。因此不满足 REV-009 条件⑤的语义，**不得用它触发真实 apply**。

`26.187.101.177` 是归档中记录的 PC-B Radmin 地址；执行端报告当前 WLAN destination cache 对该地址保留经 WLAN 网关的陈旧项。该具体地址是应优先复测的真实 peer 候选。

## 3. 允许的 cache 操作与停止条件

Microsoft Learn 文档列出 `netsh interface ipv4 delete destinationcache [interface=]<string> [address=]<IP address>`，并说明指定 interface 与 address 时仅删除该目的地址的缓存项。[Microsoft Learn：netsh interface](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/netsh-interface)

在 PC-A 的管理员终端，仅允许执行这一条定向删除：

```text
netsh interface ipv4 delete destinationcache interface=10 address=26.187.101.177
```

随后保存删除前后针对该接口/地址的 destination-cache 输出，并重做 `GetBestInterface`、`Find-NetRoute` 和 v3.3 `apply -DryRun -PeerIp 26.187.101.177`。不批准不带 interface/address 的全表清理，不批准修改静态/持久路由。

**停止条件：**若复测仍选 WLAN、Radmin 地址/索引变化，或 DryRun 的 keep/raise/目标值和 REV-009 §5 表格任一项不一致，停止；不再清理更大范围缓存，不执行 apply，并提交新证据复核。

## 4. 条件授权如何生效

若上述真实 peer DryRun 精确显示：keep=if18 Radmin、目标 2045、changed 仅 if10 WLAN `45→2045` 和 if15 ZeroTier `1045→2045`，且 if1/if58/if25 不变，则 REV-009 的条件⑤通过。之后仍须在 apply 前完成：

1. 确认 Civilization VI 关闭、没有抓包或 E2 测试窗口，也没有需保持的网络会话；
2. 使用独立 BackupDir，重新采集接口、路由和 snapshot 并计算哈希；核对状态与 REV-009 §5 前置表一致；
3. 使用刚才核验的 v3.3 SHA，仅执行一次 apply，并按 REV-009 的明确备份路径执行 restore；
4. 核对所有接口恢复到**往返开始前的现状**，核对 `.restored.json` 与 sidecar 归档及哈希；保存完整 stdout/stderr、exit code、前后状态表与哈希。

若条件不成立，条件授权不生效。PC-A 当前 45/Disabled 状态仍不是 E0 的 35/Enabled 原始基线；该往返只验证工具能恢复本次测试前状态，不构成原始配置恢复。

Gate A 未批准；M0-B 冻结；不授权同步 v3.3 到 PC-B。
