# metric 环境观测记录（2026-11-13）

状态：**只读观测记录，不是本项目待办，不需要授权动作。**
**Gate A 仍未批准，M0-B 仍冻结。**

采集时间：2026-11-13 21:53–21:55（本机时间，Asia/Shanghai）
主机：`DESKTOP-E9ERP1I`（PC-A）
执行者：DSH（只读）

> **本文原名"metric 作为真实实验前置条件"，2026-11-13 修订。**
> 修订原因：把"环境状态发生了变化"错误地升级成了"任务被阻断、需要拿到授权去修复"。
> metric 如何取值是本项目的**外部环境**，不归本项目改动；当前没有任何在办工作依赖它
> （S1 Phase 0 完全离线）。本文保留为**事实记录 + 将来实验窗口的注意事项**。

---

## 1. 机制：为什么 metric 会影响发现广播

文明6 的局域网发现是**向 `255.255.255.255:62900..62999` 的一次性 100 包广播**
（M0-A E1 已实测：每端口 1 个 4 字节 `8D-E8-FC-70`）。Windows 为 `255.255.255.255/32`
在**每块网卡**上都保留一条本地路由：

```
Protocol=Local  RouteMetric=256  InterfaceMetric=<该网卡>
```

选路规则是取 `InterfaceMetric` **最小**的那条。因此只要有一块度量比 WLAN 更小的虚拟网卡
（Radmin / ZeroTier / Hyper-V / WSL）处于 Up，广播就从它出去，真实对端收不到——
这正是 M0-A 早期"同一 WLAN 下时灵时不灵"的机制。

本机实测（`Get-NetRoute`，只读）：

| ifIndex | 网卡 | Protocol | RouteMetric | InterfaceMetric |
|---|---|---|---|---|
| 21 | Radmin VPN | Local | 256 | **1** |
| 23 | 本地连接* 10 | Local | 256 | 25（Disconnected） |
| 25 | 本地连接* 4 | Local | 256 | 25（Disconnected） |
| 11 | WLAN | Local | 256 | 45 |
| 1 | Loopback | Local | 256 | 75 |
| 16 | ZeroTier One | Local | 256 | 1045 |
| 58 | vEthernet (WSL) | Local | 256 | 5000 |
| 18 | vEthernet (Default Switch) | Local | 256 | 5000 |

按上述规则，`255.255.255.255` 的预测出口 = **if21 Radmin VPN（metric 1）**，
而到对端 `192.168.31.214` 的路径是 **if11 WLAN**。两者不一致。

---

## 2. 当前状态（2026-11-13 21:53 快照）

`set-broadcast-path.ps1 -Action snapshot -PeerIp 192.168.31.214` 输出：

```
CivLink state snapshot  2026-11-13T21:53:44  host=DESKTOP-E9ERP1I  peer=192.168.31.214
broadcast exit (predicted) : if=21 Radmin VPN srcIp=26.74.126.98
peer path                  : if=11 WLAN srcIp=192.168.31.59 nextHop=

ifIndex  metric  auto      ipv4                    name
21       1       Disabled  26.74.126.98/8          Radmin VPN
11       45      Disabled  192.168.31.59/24        WLAN
1        75      Enabled   127.0.0.1/8             (if1)
16       1045    Disabled  192.168.191.3/24        ZeroTier One [8c9a79add3f00d10]
58       5000    Disabled  172.19.240.1/20         vEthernet (WSL (Hyper-V firewall))
18       5000    Disabled  172.30.112.1/20         vEthernet (Default Switch)
```

`status` 动作的判定：`[FIX WOULD BE NEEDED] predicted broadcast exit if=21 but peer is
reachable via if=11`。

注意：这只是**检测能力正常工作的证明**——工具正确地指出了路径不一致。
它不代表任务被阻断。

快照产物（只读，未改任何设置）：

- `M0A\captures\metric-precondition-20261113\civlink-state-20261113-215344.json`（2,581 B，`kind=snapshot`）
- `M0A\captures\metric-precondition-20261113\civlink-state-20261113-215344.txt`（729 B）

---

## 3. 与历史记录的差异（事实，不作因果推断）

| 项目 | 2026-11-12 21:09 快照 | 2026-11-13 21:53 实测 | 变化 |
|---|---|---|---|
| WLAN | if10 / 45 / Disabled | **if11** / 45 / Disabled | 索引 +1 |
| Radmin VPN | if18 / **1045** / Disabled | **if21** / **1** / Disabled | 索引 +3，**metric 1045 → 1** |
| ZeroTier | if15 / 1045 / Disabled | **if16** / 1045 / Disabled | 索引 +1 |
| Default Switch | if25 / 5000 | **if18** / 5000 | 索引重排 |
| 预测广播出口 | if10 WLAN | **if21 Radmin** | 由 WLAN 变为 Radmin |

本机 `LastBootUpTime = 2026-11-13 19:03:03`（采集时 uptime 2h06m），索引变化与这次重启
一致。但**metric 从 1045 变成 1 不能用重启解释**：

- 注册表 `HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{CED510FD-6575-4880-B03D-7ADD9D1E4C8D}\InterfaceMetric = 1`
  是**持久值**，说明这次修改被写进了系统配置，不是临时运行态。
- `C:\Users\dd\civlink-metric-backups\` 里**只有 `kind=snapshot` 的记录，没有任何
  `apply` 备份**（apply 会写 `keep`/`changed` 字段）。→ **本项目的 helper 从未在本机
  执行过 apply**。
- 因此 metric=1 来自**本项目之外**的改动（Radmin VPN 自身安装/更新、或人工设置），
  具体来源未确认，**也不由本项目追查**。

唯一可取的推论是窄的：metric 与 ifIndex 都是**运行时观测值**，跨重启或软件更新会变；
历史文档里写死的 `if10`/`if18` 不能当作常量引用。这不构成任何"必须修复"的要求。

---

## 4. 与已完成的验证的关系（不要误读为需要重做）

2026-11-12 完成的 metric 调整与双机验证**结论仍然成立**，不需要重做：

- 2026-11-12 21:09 快照：PC-A 的 `WLAN=if10/45`、`Radmin=if18/1045` → 当时 WLAN 已是最高优先级；
- 同期 PC-B 完成修复：`WLAN 35→10`、`Radmin 1→5000`；
- 因此那段时间**两台机器的发现广播都走 WLAN**；用户 m08332 的验证
  （"A/B 各自建房、对方刷新都能稳定看到房间"）是在这个配置下成立的 **D 级口述证据**。

那条证据证明的是"广播路径正确时，双方刷新能互相看到房间"，**它不因 metric 后来变化而失效**。
它的边界只是不含协议级数值与 socket 生命周期数据，而那是 E2-B 的内容；
**E2-B 当前受阻的原因是 PC-B 不在线，不是 metric。**

---

## 5. 将来做真实双机实验时，实验窗口内需要满足什么

本节只在**真正要跑 E2-B / E3** 时生效，且约束的是"实验窗口内"，不是"系统长期状态"。
四项条件：

| # | 条件 | 当前（2026-11-13 21:53） | 验证方式 |
|---|---|---|---|
| W-1 | 广播**实际**出口 == 到对端的接口 | 未测 | 发探测包 + `Get-NetAdapterStatistics` 增量比对（`lanprobe.ps1`），**权威判据是真实发包，不是路由预测** |
| W-2 | 对端可达（ARP 有真实 MAC） | ❌ `Unreachable` / `00-00-00-00-00-00` | `Get-NetNeighbor -IPAddress <peer>` |
| W-3 | 双端 v0.4.4 工具、记录角色/PID/tag | 未做 | 见 `E2B-EXECUTION-PACK.md` §1 |
| W-4 | 路由预测与实测一致（作为交叉检查） | ❌ if21 vs if11 | `set-broadcast-path.ps1 -Action status -PeerIp <peer>` |

**W-1 优先于 W-4**：路由预测在本机已被反证两次（PC-A、PC-B），预测不一致只说明需要实测确认，
不能代替实测，也不能单独作为"实验不可做"的结论。

满足 W-1 有多个不依赖 `Set-NetIPInterface` 的途径，见 §6。

---

## 6. 若实验窗口内路径确实不对，可以怎么做（都不由本项目改网卡）

这些是**环境侧操作**，由负责人执行或选择；本项目不出手改 metric：

- **(a) 负责人手工处理**：在 Radmin VPN 适配器属性里取消自动度量并设为高于 WLAN 的值，
  或临时禁用该适配器。DSH 只做只读复核（`status` 前后各一次）。
- **(b) 探测/实验工具绑定源地址**：E1 已实测 `bind 192.168.31.59` → 100/100 走 WLAN。
  对 `lanprobe.ps1` 这类我方工具，绑定源地址即可绕开路由选择，完全不动系统配置。
- **(c) 负责人执行 DSH 输出的命令并回传**：命令与期望输出见附录 §7。

明确**不建议**的路径：让 DSH 用 helper 执行 `apply`。理由是
REV-008 的 R-3b 仍未解决（`Set-NetIPInterface -InterfaceMetric` 会自动把
`AutomaticMetric` 置 Disabled，`OriginalAuto=Enabled` 的网卡在 restore 时会被判漂移），
且 `apply` 路径从未被验证过。用一次未验证的写操作去解决一个可以用只读手段绕开的问题，
风险不成比例。

---

## 7. 附录：只读复核命令（任何人可复现本文）

```powershell
# 1) 当前接口 metric（按 metric 排序）
Get-NetIPInterface -AddressFamily IPv4 |
  Sort-Object InterfaceMetric |
  Select-Object ifIndex, InterfaceAlias, InterfaceMetric, AutomaticMetric, ConnectionState

# 2) 255.255.255.255 的每条 /32 本地路由
Get-NetRoute -AddressFamily IPv4 |
  Where-Object DestinationPrefix -eq '255.255.255.255/32' |
  Select-Object ifIndex, InterfaceAlias, Protocol, RouteMetric, InterfaceMetric |
  Sort-Object InterfaceMetric

# 3) 预测出口与到对端路径（只读，不改设置）
.\set-broadcast-path.ps1 -Action status -PeerIp 192.168.31.214    # CivLink-M0A-audit\scripts

# 4) 写一份只读快照（不改设置）
.\set-broadcast-path.ps1 -Action snapshot -PeerIp 192.168.31.214 `
  -BackupDir <证据目录>

# 5) 检查是否存在本项目写下的 apply 备份（若有，说明 helper 被跑过）
Get-ChildItem "$env:USERPROFILE\civlink-metric-backups" -Filter *.json |
  ForEach-Object { "{0} kind={1}" -f $_.Name, (Get-Content $_ -Raw | ConvertFrom-Json).kind }
```

---

## 8. 边界

- 本文只记录**只读观测**。没有修改 metric、没有改路由、没有改防火墙、没有改 ACL。
- metric 数字与 ifIndex **都是运行时观测值，跨重启不可当作常量**；引用须带采集时间。
- "预测出口与对端接口不一致"**不是**任务阻断条件，**不是**需要审批的事项；
  它是一条环境事实，在真正要做双机实验时用真实发包确认。
- 即使 W-1…W-4 全部满足，也只说明"发现广播的路径正确"，**不等于** E2-A/E2-B/E3
  通过，更不等于 Gate A 通过。

---

## 9. 产品视角：这个能力属于 S1，不属于工程待办

`civlink-diag` 能指出"你的广播会从 Radmin 出去、到对端要走 WLAN"，这是 REV-014 批准给
S1 非发布原型的合法输出形态之一：**只读诊断 + 修正建议**。

因此 metric 这件事在产品上的正确落点是**一条诊断规则**（检测 → 告知用户 → 给建议），
而不是产品替用户修改网卡配置。这也与 REV-014 对 S1 的边界一致
（不调 `Set-NetIPInterface`、不发真实广播、不注入）。
