# REV-004：Metric 实验与 E2 双机阶段审计决断

- 日期：2026-11-12（Asia/Shanghai）
- 审计范围：执行端提供的 M0-A 状态总结、`M0A/pcb-kit`、E2 预检归档、当前 PC-A 网络接口/metric 状态、v2.1 §11
- 决断性质：批准 M0-A 后续取证范围；**不批准 Gate A，不授权 M0-B**

## 1. 决断摘要

| 提问 | 决断 |
|---|---|
| Metric 一键修复是否正式纳入产品第 0 层 | **暂不纳入产品承诺。**可保留为实验性、需管理员权限的网络诊断/临时规避方案；先补齐 Civ6 双机端到端证据、回滚设计与不同适配器拓扑验证。 |
| PC-B 如何执行 E2 | **PC-B 本机用户/本机 AI 执行，用户在 PC-B 本地处理 UAC。**PC-A/PC-B 共享实验编号和操作时序，各自产生原始证据；不交换账户或远程桌面凭据。 |
| 桥接 Wi-Fi、不同路由器是否可称同广播域 | **当前证据只允许称“预检拓扑下观察到广播回声可达”（且本仓库缺少接收端原始证据，暂未独立采信）。**ARP/合成 UDP 到达不等于 Civ6 发现和加入成功，也不能泛化为所有桥接拓扑。 |
| PC-A metric 是否还原 | **建议恢复原始配置，但当前备份不充分，禁止直接运行现有 restore 脚本并声称已恢复。**先重建并核验原始值，再受控恢复；或将现状明确登记为实验处理组，不得称为原生默认基线。 |
| E4 缺第三台机器 | **不变更现行 v2.1 验收范围。**两台可做 E2/E3；E4/H7/H11 保持未验证，Gate A 不通过。只有项目负责人提出正式范围变更后才另行审议。 |

## 2. 磁盘证据复核

### 已直接核实

1. `M0A/pcb-kit/MANIFEST-sha256.txt` 所列文件哈希与实际文件逐一比对，**0 项不匹配**；注入器/DLL 与 v0.4.4 交付哈希相符。
2. `M0A/captures/E2-precheck-20261112/pcA-sender-rounds.log` 证明 PC-A 对 VM 发出了 6 轮、每轮 100 个广播，日志显示每轮 `sent=100/100`。
3. 当前 E2 预检目录只有该 PC-A sender 日志；没有 VM 接收端 `lanprobe` 日志、接收端 pcapng、接收接口清单或 300 包的 SHA256 绑定记录。因此“received=300”当前属于**执行端报告、未由仓库原始证据验证**。
4. 当前 PC-A 的只读接口状态为：WLAN ifIndex 10 metric=45/AutomaticMetric Disabled；Radmin ifIndex 18 metric=1045/Disabled；ZeroTier ifIndex 15 metric=1045/Disabled；Hyper-V 接口 metric=5000。`civlink-metric-backup.json` 记录 `keepIf=10`、`pinnedKeep=true`，但 `entries` 为空。
5. E0-A（2026-11-11 20:53）记录的接口/路由 metric 为 WLAN 35、Radmin 1、ZeroTier 35；PC-B 操作单另列 WLAN 45、Radmin 1、ZeroTier 35。二者对 WLAN metric 不一致，且 E0 文件未记录完整 `AutomaticMetric` 状态，不能单独作为精确回滚快照。
6. 只读运行 `set-broadcast-path.ps1 -Action status -PeerIp 192.168.31.176` 未修改系统，但显示“广播出口 if=18 Radmin、对端路径 if=10 WLAN”；这与“当前仅看最小 InterfaceMetric 即可确定出口”的简化解释不一致。路由查询不是实际 UDP 出口证据，应以两端实际抓包/接收接口日志裁决。

### 技术推断与未验证事项

- 六轮发送日志证明发送端调用成功，不证明另一台 VM 收到了包；只有 PC-B/VM 接收端日志或 pcapng 才能证明接收。
- 即便补齐 300 包跨机器接收，也只验证该次拓扑下 UDP 广播穿越，不证明 Civ6 的发现响应、JSON 地址、入局或游戏数据面可用。
- 不同路由器但处于桥接/AP 模式可能转发同一二层广播；是否如此取决于实际桥接/VLAN/客户端隔离配置。当前没有足够的接收端证据判定“同一广播域”。

## 3. Metric 工具的回滚风险（阻断继续使用其 apply/restore 功能）

`M0A/pcb-kit/set-broadcast-path.ps1` 的 `apply` 分支（约 196–215 行）只把 `$raise` 接口写入备份 `entries`，随后还会把 `keepIf` 的 `AutomaticMetric` 固定为 Disabled，但没有把 keep 接口原来的 metric/Auto 值写入备份。每次 `apply` 又直接覆盖同一个 backup 文件。

`restore` 分支（约 248–260 行）只恢复 `entries` 中的值；当 `pinnedKeep` 为真且 keep 接口不在 entries 时，代码无条件把 keep 接口 `AutomaticMetric` 设为 Enabled。它不会核验所有 metric 修改已回滚，却无条件输出 `[done] original values restored.`。

本机当前备份 `entries=[]`，当前 Radmin/ZeroTier 仍为 1045，故该备份不能把它们还原到 E0 记录的 1/35。当前备份也未保存 WLAN 原来的 AutomaticMetric 状态。**不要运行 `7-broadcast-restore.cmd` 后将其结果当作完整回滚。**先修复工具：备份所有被改变接口的原始 metric/Auto 状态（包括 keep 接口），禁止覆盖未恢复的备份；restore 后逐项读回并在任一不匹配时返回失败。之后再由用户本地提权执行。

同理，在工具回滚得到修复并复核前，PC-B 操作单中的 metric `apply` 步骤只可作为待审脚本，不应让 PC-B AI按单自主执行。PC-B 可以先做只读 E0、接口/路由记录、完整抓包能力检查和无需改配置的 G2 预检。

## 4. 产品方案边界

Metric 方法目前仅有执行端报告的 Windows metric 对照和 VM 合成广播测试；没有归档的跨机接收原始证据，也没有 Civ6 双机真实发现/加入对照。它还需要管理员权限、改变多块网卡的 metric/AutomaticMetric，并可能影响其他应用的路由选择。

所以可以把它登记为“候选的零注入环境诊断/临时 workaround”，但不能称为已验收产品层、跨机器可靠修复或 Radmin/ZeroTier 通用方案。下一步 E2 应区分并记录**未改 metric 的原始环境**与**明确标记的 metric 调整环境**，不得混成同一基线。

## 5. 双机执行许可与前置步骤

**许可：可以开始 PC-B 的 M0-A 双机预检；完成门禁后可以执行 E2-A/E2-B 和 E3。**不需等待 metric 产品决策，也不需先完成 E4。执行范围保持被动观察，不做包改写、转发或实现。

建议次序：

1. PC-A、PC-B 分别做 E0，记录 Build ID、DLC、Windows build、接口 ifIndex/名称/IP/MAC/metric/Auto、活动路由、防火墙和时区；PC-B 本地用户完成任何 UAC 操作。
2. 两端先启动完整、无捕获过滤器的抓包，再跑一次 G2。若本次没有接收端日志和原始 pcapng，则 G2 标“未验证”，不得继续声称桥接广播已跨机到达。
3. 若 G2=0，**停止并提交两端路由/接口/抓包证据**。在 metric 工具回滚缺陷修复前，不执行其 apply；先决定是否用可人工核验的临时实验配置，并保存修改前完整快照。
4. 若 G2 正向通过，执行 E2-A（A host 注入、B 原生）并保存两端抓包、A trace、响应载荷/JSON、哈希。E2-A 结束，两端完全退出游戏，再新进程执行 E2-B。
5. E3 再把游戏侧 API 调用按 socket handle、bind 端口和调用模块归属到 62056；H3 未经此归属前仍未裁决。

## 6. Gate 状态

E2/E3 双机许可是**继续收集 M0-A 证据**，不等于 Gate A 批准。v2.1 §11.1 明确要求 E4 三端方向矩阵及三人原生/注入对照（H7/H11）；两台 Civ6 电脑无法满足这两项。当前维持：**Gate A 未批准，M0-B 冻结**。
