# REV-005 后续事项处置计划（提交审计）

> **历史计划，已被项目负责人范围决议取代。** 本文按旧的完整 v2.1 Gate 范围安排 E4/H7/H11、E5 和 metric 工具；首版现限定 Windows + Steam + 双人。不要把本文中的三机/EOS/metric 前置项当作首版阻断。当前交接见 `../CODEX-HANDOVER-M0A.md`，范围与 Gate 见 `../PROJECT-SCOPE-WIN-STEAM-2P.md`。

> 依据：`REV-005-E2A-REVIEW.md` 四项决断 + Gate 状态
> 提交方：执行端 A　提交日期：2026-11-12
> **Gate A 未批准、M0-B 继续冻结** —— 本文不改变该状态。

---

## §1 审计四项决断 → 当前处置状态

| # | 审计决断 | 我的处置 | 状态 |
|---|---|---|---|
| ① | 先补一轮**合规 E2-A**（角色/PID/注入状态/刷新时序明确；被动抓取房主响应与 1104B JSON） | 已设计执行单（见 §2），待 PC-B 就位 | **待执行** |
| ② | **E2-B 仍需执行**（H6 T_window/T_response、H9/H10），不得以"根因已锁定"取消 | 已接受，撤回原"建议暂缓"（见 §3） | **已接受，待执行** |
| ③ | metric helper **允许离线修复 + 代码复核**，不授权实际应用 | 已完成 v3 修复与离线验证（见 §4） | **已完成** |
| ④ | PC-A metric 恢复**暂缓**（E0 与操作单 WLAN metric 35/45 不一致；备份 entries=[] 不可作凭证） | 未执行任何恢复；已备 `snapshot` 读取工具 | **暂缓，未动** |

**另需回应**：C-3 不通过（P1）—— 我已撤回因果结论，见 §5。

---

## §2 合规 E2-A 重做执行单（对应决断 ①）

### 2.1 与上次的关键差别

| 项 | 上次（不满足） | 本次（必须做到） |
|---|---|---|
| A 端注入状态 | 提交称注入，实际该轮**未注入**，无 civtrace session log | **每个窗口必须记录 `注入=是/否` + civtrace 日志文件路径 + 注入时刻**；未注入的窗口不得标为"注入观测" |
| PID | 未逐窗口记录 | **逐窗口记录两端 Civ6 PID**（进程重启即换号，必须现记） |
| 角色 | 只在开头声明 | **每次刷新标注 host / client** |
| 握手 | 前两轮时序失败、无独立时间戳 | 单窗口、双端同时开始、B 端回报 `点击时刻` + `pktmon 窗口` |
| 目标物 | 0 个房主响应、0 个 1104B JSON | **明确以"房主响应/1104B JSON"为判据**；拿不到就是"本轮未获得房主响应"，如实归档 |

### 2.2 执行顺序

1. **A 端**：完全退出 Civ6 → 重启 → 进"局域网"界面 → **建立房间**（停留，不退出）。
2. **A 端注入**（中立目录）：`C:\Users\dd\Desktop\civlink-run\civinject.exe -x CivilizationVI_DX12.exe`
   - 记录：注入时刻、目标 PID、`civtrace_2026..._pid<NNNNN>.log` 路径、会话头 6 行是否完整。
3. **双端同时抓包**（各自 `pcapng-capture.cmd` 右键管理员；A 端 `$dur` 已调 180s）。
4. **B 端**：完全退出 Civ6 → 重启（**不注入**）→ 进局域网界面 → **点刷新 ≥3 次**，每次回报点击时刻。
5. **B 端观察**：记录 B（client）界面是否出现 A（host）的房间条目；记录出现时刻。A 端记录本轮是否发出与 B 刷新对应的房主响应。
6. **收尾**：双端 `-u` 停用；收集两端 civtrace/pcapng/日志；逐文件 SHA256。

### 2.3 判据

- **成功**：A 端 civtrace 日志或双端 pcapng 证明 A（host）发出了与 B（client）本轮刷新请求相关的房主响应；如载荷为 JSON，保存原始载荷并确认其长度/字段（预期 1104B）；且 B 端房间列表出现 A 的条目。
- **失败**：1 个刷新窗口内两端均无房主响应 → 如实归档"本轮未获得房主响应"，**不得**用广播可达性替代。
- **无论成败**都必须记录：两端 PID、注入状态、角色、刷新时刻、窗口起止。

---

## §3 E2-B 执行计划（对应决断 ②）

**已撤回**此前"建议暂缓 E2-B"的建议。理由更正：v2.1 §11.1 要求的是 **H6（T_window/T_response 分布）** 与 **H9/H10（连接生命周期素材）**，这些是独立验收项，不能用"根因已锁定"替代。

| 项 | 计划 |
|---|---|
| 前置 | 双端**全新进程**（E2-A 结束后完全退出重启），避免污染基线 |
| A 端 | 注入，`CIVTRACE_TAG=host` |
| B 端 | 注入，`CIVTRACE_TAG=client` |
| 动作 | B 端连续刷新 10 次（间隔 2–3s），每次记录时刻 |
| 产出 | 每轮 `T_window = t_closesocket − t_first_send`；`T_response`（若有响应）；两端 civtrace 日志 + pcapng |
| 跨机约束 | **只用 pcapng 时间戳做跨机比较**，不直接比 QPC/墙钟；若需跨机时序，先做 NTP 校准并记录 |
| 注入改变行为 | 若注入版与原生版的包序列/T_window 有差异，**如实报告差异，不得丢弃** |

---

## §4 metric helper v3（对应决断 ③）—— 已完成

- 脚本：`CivLink-M0A-audit\scripts\set-broadcast-path.ps1`
- 大小/哈希：**25,744 B，SHA256 `714B41063213704D7A2CD6145AA3CA6049D7B8361C97C566B4FE33837A2B1AF4`**，UTF-8 BOM，`parse_errors=0`
- 验证记录：`CivLink-M0A-audit\docs\reports\REV-005-METRIC-HELPER-V3-VERIFICATION.md`（5671 B，SHA256 `93894CCC238BB67A34A1E6BA602959E6260CC4912C240E31D6287921CA58FF55`）

修复的 6 项（对照审计指出的 D-1…D-4，另加 v3 自查 D-5/D-6）：

| 编号 | 问题 | 修复 |
|---|---|---|
| D-1 | apply 覆盖备份，第二次改动集为空时写成 `entries: []` | 每次 apply 写**新时间戳文件**，永不覆盖；空改动集**退出且不写备份** |
| D-2 | keep 接口原始 metric/Auto **未保存**但被钉住 | 备份含 `keep.OriginalMetric / OriginalAuto / TargetMetric` |
| D-3 | restore 全 `SilentlyContinue`，失败静默 | `Set-Metric` 用 `-ErrorAction Stop` + try/catch，失败计数 |
| D-4 | restore 校验 `| Out-Null` 丢弃，失败也报成功 | `Test-Row` 逐项 readback；不一致 → restore exit 3 / apply exit 4 |
| D-5 | 无法零改动留下可信状态表 | 新增 `snapshot`（JSON+TXT，只读） |
| D-6 | 抬高计划会把**回环**也抬 | `Test-IfExcluded` 排除 loopback/127.x，计划单独列 "skip" |

附加：`schema=2` 备份格式；restore 拒绝 v2 旧备份与空 `changed`；`-DryRun` 与权限门禁解耦（dry run 保持只读）；新增 `list-backups`；退出码 0/1/2/3/4/5 语义化。

**13 个用例全部通过**（T1–T13，详见验证记录）。**所有 apply/restore 测试止于 DryRun 或权限门禁，未对任何网卡执行 `Set-NetIPInterface`。**

**未做**：未在真实网卡应用；未改动 PC-A 当前 metric；未同步到 PC-B 副本（PC-B 仍持 v2 `76DD95B0…`，批准前不应替换）。

---

## §5 C-3 撤回与更正（P1）

接受审计意见，撤回以下表述：

| 撤回 | 改为 |
|---|---|
| "InterfaceMetric 是广播出口的**唯一**决定因素/唯一障碍" | "本次观测中，Radmin 接口 metric 较低与多数广播呈现 Radmin 源**同时出现**；怀疑出口路由选择问题。**因果关系未经控制变量实验验证。**" |
| "ARP 邻居缓存为空 → 首包走 WLAN（最长前缀）" | 撤回。limited broadcast 无需 ARP 解析对端；该现象应记为"**未解释的源地址/接口变化**"（同一轮首包 WLAN、后续 99 包 Radmin）。 |
| "netpath 证明实际出口" | `netpath` 是**路由表预测**，不是实测出口；实测须靠发包+接收端归属（lanprobe/pktmon）。 |
| "Radmin 隧道不通 → 必须中继" | "**本次两端未验证出彼此 Radmin 虚拟网络可达性**（ping/ARP/tracert 均不支持）。"不等于 Radmin VPN 整体不可用，也非"必须中继"的普遍结论。 |

保留（有证据支撑）：本次 PC-B 配置与窗口内，发现签名报文大部分呈现 Radmin 源；两方向各有 ≥1 个 WLAN 源广播到达对端。

---

## §6 明确未完成项

- **E2-A/H4**：未验收，需按 §2 重做。
- **E2-B/H6/H9/H10**：未执行。
- **H3/E3**（62056 归属）：未启动，需真实对局。
- **E4/H7/H11**：需第三台真实 Civ6 端；当前仅两台 → 现行 v2.1 范围不满足。
- **E5/EOS**：无 Win64EOS 构建 → 未验证。
- **PC-A metric**：仍是被改过的状态（WLAN=45 Disabled / Radmin=1045 / ZeroTier=1045），未恢复，等审计批准恢复方案。
- **G2 判据修订**：操作单/交接文档里 G2 仍写"lanprobe 收到 100 包即通过"，应改为"**必须由游戏本体发包**"。修订稿待提交。

---

## §7 Gate 状态

**Gate A 不批准。M0-B 继续冻结。** 本文全部内容属 M0-A 观测与工具整改，不构成联机验证，也不构成 M0-B 依据。
