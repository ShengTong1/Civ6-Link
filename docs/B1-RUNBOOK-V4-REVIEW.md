# B1 双机验证操作单 v4 判定口径修正 · 审计报告

- 审计对象：`docs/B1-DUALMACHINE-RUNBOOK-20261117.md`（v4，判定口径修正版，90 行）
- 审计依据：`civlink/agent/src/main.rs`（LanSimState/SimState 计数逻辑）、`README.md` v1.28 修订记录、
  `docs/CODEX-HANDOVER-M0A.md` 第 18 项、`docs/B1-REAL-ADVERTISEMENT-CAPTURE-20261117.md`（B1 设计文档）、
  `M0A\captures\B1-p1-e2e-20261117-102852\` 与 `docs\reports\b1\run-20261117-100824\` 实测证据
- 审计方式：独立只读复核（文件内容 + 代码路径 + 制品哈希 + 实测 summary 交叉验证）
- 日期：2026-11-17

## 裁定：有条件通过

v3 判定口径的自相矛盾**属实且被代码与实测双重确认**；v4 修正方向正确、判定段与捕获路径段一致、
故障排查段与「agent 不参与应答」一致、hook 引用与最新构建一致、登记链哈希一致、无旧哈希残留。
仅存 1 项**低严重度必改项（R-1，机制事实表述不完整）**与 3 项建议项，均不影响操作执行与判定有效性。

---

## 必改项

### R-1（低）｜「计数恒为 0」的机制事实声明不完整，遗漏 F1 块同名计数的另一条递增路径

- **位置**：`docs/B1-DUALMACHINE-RUNBOOK-20261117.md` L20-21（「目的」段 v4 修正说明）；
  同源表述 `README.md` L1401（v1.28 修订记录 ①）。
- **现状**：操作单声明「`requests seen / replied sockets / replies real / replies fixture` 计数在双机场景
  恒为 0（代码事实：`LanSimState::poll` 仅在 `--sim-lan-listen` 绑定的 62900..62999 listener 上收 magic
  后才递增这些计数；无 listener 时 `consider()` 路径不触发）」。
- **代码事实（实测 main.rs）**：
  1. `replies real/fixture/skipped`（`RealAdCache.stats`）**仅在** `LanSimState::poll` 的 magic 分支递增
     （main.rs:628-630），而 `LanSimState` 仅在 `--sim-lan-listen` 时创建（main.rs:1579-1590）→ 无该参数时
     恒 0。**此半句如实**。
  2. `requests seen / replied sockets` 在 summary 中**有两处同名实例**：
     - LAN 块（main.rs:2124-2125 `ls.requests_seen/ls.replied_sockets`）：仅经 `LanSimState::consider`
       （main.rs:685/714，由 `poll` L625 调用）→ 无 `--sim-lan-listen` 时恒 0。**如实**。
     - **F1 块**（main.rs:2091-2092 `sim.requests_seen/sim.replied_sockets`）：由 `SimState::consider`
       （main.rs:465/500）递增，而该 `consider` 对**每个 accepted hook 帧都会调用**（main.rs:1786-1789），
       仅当帧为 4 字节 discovery magic 时递增计数。**操作单的机制声明未覆盖此路径**；
       且「无 listener 时 `consider()` 路径不触发」对 `SimState::consider` 不成立（它每帧触发，仅对
       非 magic 帧早退返回）。
- **为什么结论仍成立**：双机场景中 A 机 Civ6 只**收** magic（B→A），从不通过 sendto **发** magic，
  hook 链只转发 sendto，故无 magic 帧到达 agent。run-20261117-102852 实测确认
  `discovery_magic=0`、F1 块 `requests seen: 0 / replied sockets: 0`。即**结果（恒 0）如实**，仅机制表述
  不完整。
- **风险**：若未来出现「hook 帧携带 4B magic」的场景（如 B2 变体、触发脚本形态变化），F1 块同名计数会
  非 0，「恒为 0」的代码事实声明即被证伪；操作单作为可执行文档，其权威引用应精确。
- **建议改写**（runbook L20-21 与 README L1401 同步）：
  「`replies real/fixture/skipped` 与 LAN 块 `requests seen/replied sockets` 仅在 `--sim-lan-listen` 时由
  `LanSimState::poll/consider` 递增，无该参数时恒 0；F1 块同名 `requests seen/replied sockets` 仅对
  hook 帧中的 4 字节 discovery magic 递增（`SimState::consider`），双机场景 A 机 Civ6 只收不发 magic，
  同样恒 0（run-102852 实测 discovery_magic=0）。」

---

## 建议项

### S-1（低）｜证据目录文件数 50 与 51 不一致
`README.md` L1380、`docs/CODEX-HANDOVER-M0A.md` #18 ③、设计文档 §5.1 L109 均写「50 文件」，
而设计文档 S-5（L134）已勘误为「51 文件（非 50）」，实测 `M0A\captures\B1-p1-e2e-20261117-102852\`
为 51 个文件。建议登记链统一为 51。

### S-2（低）｜39D6735D 构建缺构建日志
`civlink/civlink_hook.dll`（119,808B，10:51:10，sha256 39D6735D34520724…）为当前注入制品，
与 README/设计文档/操作单一致，但 `civlink/build-hook*.txt` 日志止于 10:18:16（0965154A），
10:51 重建无日志，可追溯性缺口。建议补记该次构建。

### S-3（低）｜复审审计员 id 链不完整
操作单 L3-4 引用「复审 cfc28fc4 通过」，但 `docs/B1-REAL-ADVERTISEMENT-CAPTURE-REVIEW-2.md` 仅引用
首轮审计员 f8918c50，未记录复审 id。建议在 REVIEW-2 或登记链中补记复审子代理 id，保持 id 链完整。

---

## 逐项核查记录

### 1. 判定段 vs 捕获路径段（一致 ✓）
- 捕获路径（L34-43）固定走 P1（hook 链），agent 以 `--sim-real-capture`（无 `--sim-lan-listen`）纯观测，
  P2 不可用（run-100824 实锤）。
- 判定（L65-74）：PASS = B 见真实房名 + A 侧 `captured=22/active=yes`；明确「不要求 `replies real>=1`
  （agent 无 LAN 监听时恒为 0，属预期）」；部分/FAIL 归因均不引用恒 0 计数。**口径自洽，v3 自相矛盾已消除**。
- 实测佐证（run-102852 summary.txt，哈希 4F6279A5… 与登记一致）：`requests seen: 0 / replied sockets: 0 /
  replies real: 0 / replies fixture: 0 / replies skipped: 0 / captured: 22 / active: yes`，且无 LAN 块
  （确认无 `--sim-lan-listen`）。**v3 口径（requests seen>0 / replied sockets>=1 / replies real>=1）在该
  模式必然 FAIL，v4 修正正确。**

### 2. 目的段 v4 修正说明（准确，无新矛盾 ✓，唯一例外见 R-1）
- 「agent 不绑定发现端口、不参与应答」「B 机看到房间靠 A 机 Civ6 房主自身的单播应答（§0 取证形态）」
  与代码（无 `--sim-lan-listen` 时 LanSimState 不存在）+ 证据（run-102852、§0 run-095336 单播取证）一致。

### 3. 故障排查段防火墙检查对象（与「agent 不参与应答」一致 ✓）
- L80-82：检查 **A 机 Civ6.exe（游戏进程）** UDP 入站，「B→A 的 magic 广播到达靠游戏 socket，
  agent 不参与应答，无需放行 agent.exe」；并给出 F5 对照（F5 时 agent 是应答方需放行 agent.exe）。
  判定 FAIL 段（L72-74）同口径。**无矛盾**。

### 4. hook 引用 vs 最新构建（一致 ✓）
- 注入用 `39D6735D…`（L31/L50）= 当前磁盘制品 `civlink/civlink_hook.dll`（119,808B，10:51:10，
  实测 sha256 `39D6735D34520724ED790811D8862275D996C50BC321564F1F5C785C268E3411`），与 README v1.28 ②③、
  设计文档 §5.1「新身份」（L130-131）一致。
- run-102852 历史 `0965154A…`（L7）= 设计文档 §5.1 L92（`0965154ACC92424B…`）+ build-hook4-out.txt
  （10:18:16）一致。两个引用均与制品/日志对齐，无「把历史当最新」的错位。
- 相关制品：release `civlink-agent.exe` 417,792B/`DDAF5453…`（L29）实测一致；`civlink_ctl.exe`
  173,056B/`D4D0D330…` 与设计文档一致。

### 5. 登记链一致性（一致 ✓）
- RUNBOOK v4：实测 6,510B / sha256 `745FDE446AD019912660408CB38538CB6405B3933A948A0C42D8E9A707B77CF5`，
  与 README v1.28 ①（L1398）及 CODEX-HANDOVER #18 ④ 登记完全一致。
- B1 设计文档（`docs/B1-REAL-ADVERTISEMENT-CAPTURE-20261117.md`）：实测 17,531B / sha256
  `1A03D8A18384A619…`，与 README v1.28 ②（L1406）及 CODEX-HANDOVER #18 ④ 登记完全一致。
- 无 E1435032/B041757C 残留：两旧哈希仅出现于 README v1.27 历史块（L1389/L1391），且 v1.28 L1406
  明确标注「保留为历史」；runbook v4、CODEX-HANDOVER #18、设计文档均 0 命中。

### 6. 其他交叉验证
- run-20261117-100824（P2 实锤证据，`docs\reports\b1\run-20261117-100824\agent\summary.txt`）：
  LAN 块 `bind fail: 1 port(s)`、`captured: 1 / active: no`、`noise on disc: 0` → 操作单 L39-41 的
  「P2 不可用」两条理由（房主占 0.0.0.0:62900 + 广告页单播）成立。
- 操作单 L49「agent 仅监听 127.0.0.1:34718 + 127.0.0.1:62900」：run-102852 实测 F1 块
  `reply source: 127.0.0.1:62900`、`bind fail: 0`（与 Civ6 的 0.0.0.0:62900 共存无冲突）——经验证实。
- 操作单 L3-4 首轮审计链（f8918c50 有条件通过、R-1 高/R-2/R-3 中、复审通过）与
  REVIEW.md/REVIEW-2.md（裁定「通过」）一致（复审 id 缺失见 S-3）。

---

## 结论

v4 判定口径修正**真实修复了 v3 的自相矛盾**：v3 的三条计数 PASS 条件在「无 `--sim-lan-listen` 纯观测」
模式下全部恒 0（代码事实成立，run-102852 实测即为全 0 + captured=22/active=yes），原口径必然不可达；
v4 改为「captured=22/active=yes + B 机可见真实房名」，与捕获路径、故障排查、边界声明、登记链全部自洽。
按本仓审计标准裁定**有条件通过**：必改 R-1（低，机制表述精确化，一处小改写），建议 S-1/S-2/S-3；
R-1 落实后即可执行双机验证操作。
