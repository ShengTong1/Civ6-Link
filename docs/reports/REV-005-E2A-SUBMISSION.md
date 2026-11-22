# REV-005 提交：E2-A 双机广播发现实验（供审计决断）

> **REV-012 更正提示**：本提交 §6 的“Radmin VPN 隧道实际不通 / 必须中继”仅是当时端点与客户端状态下的探测记录，不能证明在线 Radmin 隧道不可达或产品必须中继。项目负责人确认两端客户端均离线；该泛化结论已撤回。按历史提交保留原文，现行裁定见 `REV-012-REVIEW.md`。

> 提交方：执行端 A（CivLink M0-A）
> 提交日期：2026-11-12
> 提交内容：E2-A 完整证据归档 + 三项待决断项 + 建议下一步
> 前置状态：Gate A 未批准、M0-B 冻结；本提交不改变该状态。

---

## §1 实验概况

| 项 | 值 |
|---|---|
| 实验 | E2-A（双机·A 建房注入观测·B 原生不注入） |
| 时间 | 2026-11-12 16:41 – 17:59（Asia/Shanghai） |
| 执行端 | PC-A（DESKTOP-E9ERP1I，Win11 26100.4946，Steam Build 26407122） / PC-B（UTOPIA，Steam 版文明6 + DLC 齐） |
| 工具 | civtrace.dll v0.4.4（19196FF7…）/ civinject.exe v0.4.4（4DCC9557…） |
| 模式 | 双端独立观测交叉验证（A 注入 civtrace 观测，B 全程未注入、civinject 从未使用） |
| 框架 | REV-004 审计决断：未运行 6/7-broadcast-apply/restore、未手工改 metric、未改二进制、未伪造 pcapng |

---

## §2 三条结论（与 PC-B 端独立复核一致）

- **C-1**：B 侧发现广播 99.8% 从 Radmin VPN 发出，WLAN 方向几乎为空。
  500 包实测 Radmin 499 / WLAN 1；首轮 800 包全 Radmin；`lanprobe`（socket 层）+ `pktmon` pcapng（驱动层）+ `netpath`（路由表）三层独立来源互证。
- **C-2**：WLAN 广播链路双向可用，非链路故障。
  B→A：A 端 pcapng 收到 B 的 1 个 WLAN 包，**跨机三字段全等**（dstport=62900 / srcip=192.168.31.214 / srcport=53787 随机源端口，双端独立观测到同一值）；A→B：B 收到 A 的 5 轮广播共 496 包，全部 if=17(WLAN)。
- **C-3**：`InterfaceMetric` 是广播出口唯一决定因素，也是唯一障碍。
  `255.255.255.255/32` 每网卡一条等价路由（RouteMetric 均 256），Windows 选 InterfaceMetric 最小者；B 侧 Radmin=1(Disabled) < WLAN=35(Enabled) → Radmin 恒被选中。
  **首包机制（B 端发现，"房间时有时无"的物理机制）**：ARP 邻居缓存为空时首包按最长前缀走 WLAN（192.168.31.0/24），缓存建立后第 2–100 包粘 Radmin——只有首包有机会穿过 WLAN，是否到达取决于当时缓存状态。

---

## §3 决定性证据：跨机确证（同一数据报，非时间戳对齐）

| 端 | 记录 |
|---|---|
| B 端 lanprobe（socket 层） | 17:49:11.656 if=17(WLAN) dstport=62900 src=192.168.31.214:53787 data=8d e8 fc 70 |
| A 端 pcapng（驱动层） | dstport=62900 srcip=192.168.31.214 srcport=53787 IPID=12255，5 副本帧 SHA256 一致，跨度 7µs |

- 源端口 53787 为 OS 随机临时端口，两台机器独立观测到同一值，概率上无法巧合 → 同一数据报的跨机确证，强于时间戳对齐。
- A 端 pcapng：SHA256 `E746BF780B5B992FD559645D60EABCD1B5211A0B324E605281BA3E3D306D638E`（31,211,148 B）；**A 端 Radmin 包数 = 0**。
- ⚠️ 时钟偏差：B 17:49:11.656 vs A 17:49:13.000 = +1.344s，局域网 RTT 仅 4–6ms → 系统时钟不同步（NTP 未校准），非网络延迟。

---

## §4 证据文件与哈希（完整性已核）

### A 端归档（`M0A\captures\E2-A-20261112\`）
| 文件 | SHA256（前 16） |
|---|---|
| A-pcapng-20261112_174753.pcapng（31,211,148 B） | E746BF780B5B992F |
| A-20261112_174753.etl（5,758,415 B） | 3975FEB08D334BEE |
| A-174753-datagrams.csv（311 B） | 8D28B719A0AA6BCA |
| A-side-evidence-final.md（3,469 B） | 6FFD1EE5B3CD14B8 |
| A-pcapng-20261112_172558.pcapng（第一轮，时序失败空窗，保留标注） | 7221F967C72325F4 |
| A-20261112_172558.etl | A7601914B05A56AA |

### B 端回传（`M0A\captures\E2-A-20261112\PC-B-回传\`，ZIP SHA256 3FA0E85E3E99672F…，24 项 SHA256SUMS 全部 mismatch=0）
关键文件：`pcapng-20261112_170908.pcapng`（5E2369481FA12995，800 包全 Radmin）、`lanprobe-round3-refresh.log`（7230F4268A69400A）、`PC-B-report-E2A.txt`（E00AD677F297F696）、`E2A-B-datagrams.csv`（4D746E507042AF96）、`E0-B-20261112_164219` 基线 21 文件。

### 文档
| 文档 | SHA256 |
|---|---|
| M0-A-协议行为报告-E2A-20261112.md（132 行） | 289F608067A46BDDE6C1FACA4F1388D11B421CD78575C9559DD497C57FF6A68F |
| README.md v1.7（48153 B） | BCEED13F61AF5498C80953C2400AD99F8428647003FB7CD767AF72409A7975B9 |
| AUDIT-SUMMARY-ONEPAGER.md（B 端，6490 B） | 见 B 端 SHA256SUMS |

---

## §5 结论边界（勿扩大解读）

| ✅ 本次已验证 | ❌ 本次**未**验证 |
|---|---|
| B 侧 99.8% 发现包从 Radmin 发出（metric 唯一障碍） | **改 metric 后 Civ6 能否真实联机**（只到房间列表，从未尝试加入游戏） |
| WLAN 广播链路双向可用（跨机确证 srcport=53787） | 改 metric 的**副作用**（路由表变化对其他应用的影响） |
| A 侧 metric 已调好，A→B 方向正常 | `6-broadcast-apply.cmd` 的**回滚可靠性**（REV-004 冻结原因） |
| metric 是 B 侧广播出口的唯一决定因素 | Radmin 房间内二层广播中继（A 端 0 Radmin 包已证不通，需产品第 2 层方案） |

**准确表述**：改 metric 可使 B 侧发现广播回到 WLAN 链路（该链路已验可用）；但 Civ6 实际联机成功、以及 metric 工具的安全回滚，均尚未验证。

**方法学教训（本次最重要）**：**G2 通过 ≠ Civ6 能发现**——G2 是用 PowerShell 显式 bind WLAN 发包，Civ6 不 bind（实测 100% 走 Radmin）。操作单修订建议：G2 若用作 Civ6 可比判据，必须由游戏本体发包。

---

## §6 附带发现（独立于 metric，需单独立项）

**Radmin VPN 隧道实际不通（B 端实测）**：ping -S 100% 丢包 / ARP Incomplete / tracert 绕公网（192.168.31.1→192.168.2.1→113.225.0.1→218.25.3.77），流量未走 Radmin 二层；A 端抓包 0 个 Radmin 包双向印证。→ **Radmin 房间方案不能靠改 metric 解决，需要中继**（产品第 2 层，v2.1 规范 Lobby+Relay）。

---

## §7 合规性声明与异常

REV-004 约束 7 项全部 ✅（未运行 6/7-cmd、未手工改 metric、B 端未用 civinject、二进制哈希与 MANIFEST 一致、pcapng 全真实、无静默降级）。

异常 4 条如实记录：
1. 第三轮实际点击 5 次刷新（协议要求 3 次）；
2. 前两轮补证时序失败 0 记录（已归档，标注"协议时序失败非网络证据"）；
3. PC-B 工具自发包 89/100 丢包（测试工具侧缓冲丢弃，与 Civ6 无关；Civ6 自身 24 轮中 20 轮完整 100/100）；
4. PC-B 工作区 Windows 文件权限异常（SetNamedSecurityInfoW Win32 5）已修复，未影响取证。

---

## §8 提交审计决断的三项

1. **E2-B 是否执行**：建议暂缓（根因已锁定，注入污染基线风险 > 价值）；若坚持，须用全新游戏进程 + lanprobe 独立对照。
2. **metric 工具脚本修复**（备份防覆盖 + restore 核验）——REV-004 已指出缺陷，本次实验未触碰，是否批准实施修复。
3. **PC-A metric 手工恢复**——当前 Radmin/ZeroTier=1045（备份 entries 空，脚本不能恢复），还原依据 = E0 归档（`M0A\baseline\E0-A-20261111_205343\routes.txt`：Radmin=1、ZeroTier=35），是否批准手工恢复。
   （另附：G2 判据修订建议——须游戏本体发包。）

---

## §9 仍关闭项

- **Gate A 未批准、M0-B 冻结**（本实验为 M0-A 观测，不构成 Gate A 通过、不构成联机验证、不构成 M0-B 依据）。
- E4/H7/H11 需第三台真实 Civ6 端（当前仅两台 → 现行 v2.1 验收范围不满足）；E5 需 Win64EOS 构建 → 未验证。
- E3（62056 socket 归属、H3 五分类）需真实对局，未启动。
- 不得把单机/VM/双机广播证据宣传为联机验证。
