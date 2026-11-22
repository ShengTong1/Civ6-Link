# M0-E 双机预检（Preflight）— 设计与证据

> 版本：**v2.0**（2026-11-19，v3 定版脚本）
> 关联：`docs\M0E-DISCOVERY-COMPLETION-20261118.md`（v2.1，22505 B / `7AF86CB4…`）、`docs\M0E-DUALMACHINE-RUNBOOK-20261119.md`（v1.1，6696 B / `6C3BA55C…`，v1.2 待协调更新）、`docs\M0E-RUNBOOK-REVIEW-20261119.md`（8021 B / `190DEF2C…`）
> **定版脚本**：`civlink\run-m0e-preflight.v3.ps1`（24,386 B / `0224B23190FEA918BB59C2AA624DB109EF5669F9E0DFA52FEF88899A627709F8`）、`civlink\fix-m0e-preflight.v3.ps1`（10,242 B / `6387CBAA98EB6E02B85C8743B327B9D920CC08400C4B9C5635E7C006A785BB63`）
> 历史件（保留不删、勿再引用为现行）：`run-m0e-preflight.ps1` v1（`F60DE777…`，送审快照）、`.v2-candidate.ps1`（`0F469F41…`）、`fix-` 同名 v1（`2D000B7E…`）/ v2 候选（`27E044CC…`）。

## 0. 版本历史与审计说明（重要）

v1.0 曾把送审脚本（`F60DE777…`）当作定版。**独立审计子代理派发三次全部失败**：92c682bf 无产物、4cec1d46 只留下 1,297 B 的 18 个「待填」骨架，均无裁定报告。停止重派，改为**自查主导定版**。

自查发现 P-1~P-15（逐条实测记录见 `docs\M0E-PREFLIGHT-SELF-AUDIT-NOTES.md`，39,445 B / `2D5AC016…`），全部并入 v3。v3 通过一轮精简机械复核（报告 `docs\M0E-PREFLIGHT-REVIEW-3-20261119.md`，见 §5）。**审计未完成本身登记为发布阻断备注**，不得把"脚本自检通过"表述为"独立审计通过"。

## 1. 为什么做这个

双机验证历史上**两次失败都不是产品缺陷**：

| 轮次 | 现场症状 | 真实原因 |
|---|---|---|
| 2026-11-17 首轮 | B 刷新，A agent `requests seen=0` | `civlink-f1` 的 Allow 规则只有 Public，而 WLAN 是 Private → 入站包被丢 |
| 2026-11-17 次轮 | B 只看到虚拟房，真实房不可见 | 游戏 `CivilizationVI_DX12.exe` 的 Allow 只有 Public，WLAN=Private |
| 2026-11-18（另一次） | "创建房间点了没反应" | 残留 agent 占满 62901–62999，游戏 bind 62900 失败 |
| M0-B 多次 | 广播出不了 WLAN | `InterfaceMetric` 让 Radmin(1) 压过 WLAN(45) |

这些都不是代码问题，但每一次都要花掉一整轮真机操作才发现。**Windows 防火墙按程序绝对路径 + 入站网卡所属 Profile 双重匹配**，而发布包会把 exe 放在新目录（`dist\civlink-20261119-nightly\`），历史规则一条都不匹配——这是可预见的、必然复发的坑。本脚本把上述四类环境前提变成一次性检查。

## 2. 检查项（v3 定版）

| 编号 | 检查 | PASS / 输出判据 |
|---|---|---|
| C1.1 | agent 身份 | 文件存在 **且**文件名精确为 `civlink-agent.exe` **且** PE 头两字节为 `MZ`（P-14：v1/v2 对任意叶子文件假 PASS） |
| C1.2 | 完整性 | 与同目录 `MANIFEST.txt` 对应行哈希一致；**包布局**（同目录有 `VERSIONS.txt`）下缺失/未列该文件 = FAIL（P-11），包外仍 WARN |
| C2.1 | 游戏进程 | `CivilizationVI_DX12` / `CivilizationVI`，未运行仅 WARN |
| C2.2 | 发现端口 | 游戏持有 `62900`；**未运行时也输出 `NOT verified` WARN**（P-1，不再静默跳过） |
| C2.3 | 数据面端口 | 游戏持有 `62056`，缺失仅 WARN；同 P-1 恒有输出 |
| C3.1 | 残留 agent | 无 `civlink-agent` 进程 |
| C4.0 | 防火墙可读 | `netsh` 解析出规则条数 |
| C4.1 | **agent 入站规则** | `Enabled=Yes`、`Action=Allow`、`Program` **精确等于**将要运行的 agent 绝对路径，覆盖本机**全部在用 Profile**；无规则时打印 ZERO-UAC REMEDY |
| C5.x | 游戏入站规则 | 同上，作用于两个 DX 版本 exe；**仅对在运行的版本按 FAIL 判**，另一版本降 WARN |
| C6.1 | 网卡清单 | 打印 interface / IP / Profile / metric 全表 |
| C7.2 | **metric 竞争** | 最低 metric 网卡（limited broadcast 唯一出口）是否被虚拟网卡占据；按角色给结论（§3） |

**检查数（P-15 更正）**：agent 身份成立时 **12 项**；C1.1 失败时 C1.2 不适用，**总数 11 项**。v2 头注释曾写"CONSTANT 12"，已被边界探针证伪并在 v3 更正。

**verdict 三分支**：有 FAIL → `PREFLIGHT: ACTION NEEDED`（exit 2）；无 FAIL 但有 caveat（游戏端口未验 / 完整性未验）→ `PREFLIGHT: READY WITH CAVEATS`（exit 0，逐条列 `CAVEAT:` 并明写 *A caveat is not a pass*）；全验过 → `PREFLIGHT: READY`（exit 0）。

## 3. C7 为什么是 WARN 而不是 FAIL（角色相关）

`255.255.255.255` 只在**唯一出口**发出（每接口一条 /32 等价路由，取 InterfaceMetric 最小者）。两个方向影响不同：

- **客户端角色**：致命。刷新广播从 Radmin 出去，LAN 房主收不到 → 搜不到房。
- **房主角色（跑 M0-E Agent）**：可容忍。Agent 绑 `0.0.0.0:62901–62999`，任何网卡到达都收得到；回包按客户端源地址单播由路由决定。metric 只影响游戏自己的公告广播，不影响 M0-E 路径。

故给 WARN 并写明两种角色，避免"为消警告去改 metric"这种无必要提权（metric 改动曾被用户限制授权）。

## 4. C4.1 的零 UAC 兜底

实测：`dist\civlink-20261119-nightly\civlink-agent.exe`（`15321D49…`）无任何规则，但 `civlink\agent\target\release\civlink-agent.exe` 与它**字节完全相同**且已有 Private+Public Allow。Windows 按路径匹配不认内容 → 从已覆盖路径运行同一二进制即可零提权。脚本在 FAIL 行末尾打印 `ZERO-UAC REMEDY: ...` 列出该路径。

`fix-m0e-preflight.v3.ps1` 是**正规部署**的另一条路（自提权 → 加两条 `profile=any` 入站规则 + 可选调 metric，原值写备份，`try/catch` 回落只读介质；头注释列撤销命令）。优先用零 UAC 兜底。v3 的 `[ValidateRange(1,9999)]` 修掉了 v1 `-VirtualMetric 99999/-5` 直接崩（exit -1）的问题。

## 5. 证据

**v3 定版采信**（`CivLink-M0A-audit\M0A\captures\M0E-preflight-v3-selftest-20261119-1156\`，12 文件，含 `MANIFEST.txt` + `MUTATION-RECORD.txt` + 两脚本源码副本）：

| 用例 | exit | headline | 关键点 |
|---|---|---|---|
| `v3-t1-baseline-dev.txt` | 0 | READY WITH CAVEATS / 6 WARN / 12 checks | 开发布局；C2.2/C2.3 恒输出 WARN |
| `v3-t2-agentpath-ps1.txt` | 2 | ACTION NEEDED / 2 FAIL / **11 checks** | `-AgentPath` 指 .ps1 → `FAIL C1.1 … civlink-agent.exe expected`（P-14 假 PASS 消除） |
| `v3-t3-agentpath-dir.txt` | 2 | ACTION NEEDED / 2 FAIL / 11 checks | 指目录 → 可读 FAIL（P-3） |
| `v3-t4-game-alive.txt` | 0 | READY WITH CAVEATS / 3 WARN / 12 checks | 假游戏占 62900/62056 → C2.1/2.2/2.3 全 PASS，game caveat 消失 |
| `v3m-baseline / -m3 / -m4 / -control-no-manifest` | 0/0/0/2 | 见 `MUTATION-RECORD.txt` | caveat 层变异在覆盖路径下证明有判别力 |

**历史证据**（`…\M0E-preflight-selftest-20261119-1110\` 与 `…\M0E-preflight-v2-selftest-20261119-1125\`、`…\M0E-preflight-v2-mutation-20261119-1135\`）：保留供追溯，**其结论对应 v1/v2 快照，不代表 v3**。

**变异判别力诚实口径**：v3 的 M3/M4 是**断言层**捕获（headline 文案 / caveat 列表 / FAIL→WARN），**非退出码层**（baseline 与 mutant 均 exit 0）；退出码层由 control（exit 0→2）与 v1 M1 覆盖。禁止笼统写"变异被捕获"。详见 `MUTATION-RECORD.txt`（2,412 B / `E9FE4280…`）。

## 6. 边界（不得越界引用）

- **操作员就绪性检查**，不是联机验证证据，不勾 E2-A/E2-B/E3，不移动 Gate A/B。
- 不检查第二台机器是否可达；不检查游戏是否应答 loopback 重放；不检查 62056 跨机可达性。
- `READY` / `READY WITH CAVEATS` 只意味着"本机机械前提核对结果"，**不等于**发现链路或加入成功。caveat 点名的事项没有证据支撑。
- 脚本只读（`fix-` 除外，且改动面在脚本头逐条列出并可撤销）。
- 独立审计三次失败、v3 由自查主导定版，是**发布阻断备注**；对外发布前仍需补一次独立审计或明确以"未经独立审计"标注。

## 7. 与操作单的关系

顺序固定：`run-m0e-preflight.v3.ps1` → `READY`（完整，非 HOST-ONLY/CAVEATS）→ 按 `M0E-DUALMACHINE-RUNBOOK-20261119.md` 执行（**先建房、后启 agent**）。操作单将升 v1.2，把预检作为 §3 步骤 0 正式纳入（补丁草案 `docs\M0E-RUNBOOK-v1.2-PATCH-DRAFT.md` 3,018 B / `42A5AEE3…`）。