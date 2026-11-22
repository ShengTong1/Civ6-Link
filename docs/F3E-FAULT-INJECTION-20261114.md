# F3-E 故障注入自检报告（F3 子项 E）

**状态：PASS 23/23，采信证据 `F3E-fault-injection-selftest-20261114-163533`（revision 1，relay 含 F4 `--version` 重建后重跑）**

F3 五子项（A 直连转发 / B Relay 转发 / C 退避语义 / D 压力 / E 故障注入）中 E 为最后一环。
本报告对应 `docs/F3-DIRECT-RELAY-DESIGN-20261114.md` §5.2 表的 F3-E 判据。

---

## §0 版本与状态

- 审计：`docs/F3E-REVIEW.md`（第一轮，子代理 494998db，**有条件通过**：无阻断/高，中 3 项 M1/M2/M3 + 低 7 项 L1..L7，全部文档层）→ 修订落地 → `docs/F3E-REVIEW-2.md`（第二轮独立复审，子代理 4a56f23d，**通过** 11/11 PASS 无残余项，复审报告已落盘）
- 本报告 §0.1 已按第一轮审计必改清单修订（M2 §4 采信值与 -163533 同步 / M1 探针声称改为一次性冒烟无留存 / L1 §7.2 注 E2-stop.txt 6B / L3 400ms / L2 行号 584-586 / L4 枚举合并 bad+unk / L5 16 文件 / L7 转录注释声明）
- 脚本：`civlink/run-f3e-fault-injection-selftest.ps1` revision 1，22,435 B
  sha256=`BA002D94AC5EB4220A4E6AD09C2F1BC29293B8C9A8A3995CC26F365D366D9162`
- **采信运行**：`M0A/captures/F3E-fault-injection-selftest-20261114-163533` → **PASS 23/23**，exit 0
  （2026-11-14 16:35 重跑：relay 因 F4 新增 `--version` 重建为 9E323F81…；本轮为当前树重跑，证据树可重放）
- 旧采信（relay AE03327E… 时代）：`M0A/captures/F3E-fault-injection-selftest-20261114-162129` → PASS 23/23，exit 0
  （证据有效但对应二进制已被重建覆盖，仅作历史记录，见 §6）
- 失败首跑（同版本脚本修复前）：`M0A/captures/F3E-fault-injection-selftest-20261114-162043` → FAIL 1/23（见 §6 运行历史）

## §1 目的与边界

### 1.1 判据来源（设计 v0.3 §5.2）

> F3-E：对端 Agent 中途退出 / Relay 掉线 → DEGRADED→RECONNECTING 不踢人（§9）

### 1.2 边界声明（如实，不越界）

- **F3 原型（Agent/Relay）没有状态机实现**。设计 §9 的 DISCONNECTED→CONNECTING→CONNECTED→IN_ROOM→IN_GAME 与 DEGRADED/RECONNECTING 状态机、Relay 心跳 15 s→DEGRADED 30 s→RECONNECTING 的时序，均为 **M0-B 规范目标**，本阶段不实现、不声称。
- 因此本阶段对"不踢人"语义不直接测量，只验证故障下的可观察行为底线：
  1. 计数如实（故障可见，不静默吞掉）；
  2. 该不崩时进程存活（E-2）；
  3. 该 fatal 时**真实退出码**（E-1 = exit 3，不伪装 0）；
  4. **不产生伪协议应答**（对端/通道故障时不得编造成功响应）。
- 每项测试的回包策略：全部走"回包为零"分支（D4 兼容的 ≤1 个 20 B 探针未参与本报告任何场景；E-1/E-2/E-3/E-4 均不触发 datapath 逻辑）。

## §2 测试设计（四场景）

| 场景 | 模拟故障 | 预期 |
|---|---|---|
| E-1 | 对端 Agent 中途退出，Relay 转发进死端口 → 回环 ICMP port unreachable → recv_from 10054 | Relay 如实 fatal → **exit 3**，summary 先写盘，计数闭合 |
| E-2 | 对端 Agent 退出后不再推流 | Relay 存活（-not HasExited）→ stop-file 干净退出 exit 0，fatal=none |
| E-3 | Relay 被硬杀（掉线） | 进程消失（Gone=HasExited），杀后发帧无响应、无伪应答 |
| E-4 | Relay 未运行（通道 down） | 发送成功（UDP 语义）、无响应、无伪应答；端口空闲断言 |

### 2.1 E-1 是 F3-B 第三轮审计（F3B-REVIEW-3.md）E5 承接项

Relay `relay/src/main.rs:584-586` 的 `if stats.fatal.is_some() { std::process::exit(3); }` 在 F3-B 全部轮次中零用例。
E-1 构造真实触发路径：IPv4 UDP 载荷最大 65507 B，永远进不了 oversize 分支（65535 B 缓冲），
所以 fatal 唯一外部可控路径是 Windows UDP 收到 ICMP port unreachable 后 recv_from 返回 WSAECONNRESET(10054)。
该触发路径的可行性由 E-1 运行本身实证（E1-stderr.txt 与 relay-summary.txt 的 fatal 行，均为 10054 的真实记录；
构建前另用一次性 PowerShell Add-Type UdpClient 探针做过冒烟确认，探针无留存物，不作为证据引用）。

### 2.2 时序（E-1）

1. 起 relay（`--listen 127.0.0.1:34720 --listen-seconds 40 --out-dir --stop-file`）
2. peerA(101)/peerB(202) 各注册 3 次（40 ms 间隔；回环下注册帧可能丢单包，多注册是 F3-B 经验）
3. 基线：A→B seq=1（payload1 8 B），B 收到 → 证明链路通
4. 关闭 peerB socket（模拟对端退出）
5. A 发 seq=2 到死端口（payload2）→ Relay `send_to` 成功（UDP 语义）→ 回环 ICMP port unreachable
   → Relay 自身 recv_from 返回 10054 → fatal → **exit 3**
6. 脚本轮询 ≤10 s 等 relay 自死；死时读 StdoutTask/StderrTask 落 E1-console/E1-stderr/E1-exit；
   没死则 stop-file 收尾并断言失败

## §3 断言清单（23 条）

- E-1（12）：relay bound 127.0.0.1:34720（bind Check，命名瑕疵 `E-E1` 无害）/ baseline seq=1 到达 B / relay 自行退出 exit=3 /
  stderr 含 fatal recv_from 失败（`[!] recv_from failed: ... (os error 10054)`）/ relay-summary.txt 存在（fatal 退出前写盘）/
  summary fatal 行 ≠ "none" / datagram identity 闭合（8 = 6+2+0+0）/ forward requests=2 / forwarded=2（UDP 语义下两次 send_to 都成功）/
  bad envelope=0 / unknown flags=0（合并为一条 Check）/ reconciliation 行存在 / **无伪协议应答**（对端 A 收不到任何编造帧）
- E-2（6）：relay bound / baseline seq=1 到达 B / peer 退出无流量后 relay 仍存活（HasExited=False）/ stop-file 退出 exit=0 /
  summary fatal=none / reconciliation 闭合
- E-3（3）：relay bound / **hard kill 后进程消失（Gone=True）** / kill 后发帧无响应、无伪应答
- E-4（2）：udp:34720 空闲（所有 relay 已退出）/ 通道 down 时发送成功、无响应、无伪应答

「无响应、无伪应答」的断言方式：驱动向 34720 发帧后 400 ms（ReceiveTimeout）内无任何回包到达（UDP 收到才算）——与 F3-A/B/C/D 的负向用例同一模式；对收到的包再做 CVLR-magic 识别，能区分"无应答"与"CVLR 伪应答"。

## §4 实测结果（采信 `-163533`）

### 4.1 E-1（fatal/exit 3 真实用例）

- stderr 实测：`[!] recv_from failed: 远程主机强迫关闭了一个现有的连接。 (os error 10054)`
- exit 实测：`3`
- relay-summary.txt 实测（E-1 子目录，`-163533` 采信）：

```
civlink-relay 0.1.0 - F3-B relay summary
run time          : 08:35:35.807
listen            : 127.0.0.1:34720 for 1.1 s
datagrams         : 8
bytes in          : 176
bad envelope      : 0
control frames    : 6
unknown flags     : 0
registers         : 6
forward requests  : 2
forwarded         : 2
forward bytes     : 16
forward fail      : 0
no route          : 0
self drop         : 0
no sender         : 0
oversize          : 0
fatal             : RECV ERROR: 远程主机强迫关闭了一个现有的连接。 (os error 10054)
datagram identity : datagrams == registers + forward_requests + bad_envelope + unknown_flags (6 + 2 + 0 + 0) = 8
reconciliation    : forwarded + no_route + self_drop + forward_fail + no_sender = 2 == forward_requests = 2
peers seen        : 2
```
（上表数值与 `-163533` 采信文件一致；部分行的括号注释（如 oversize/no sender 的说明文字）在转录时省略，数值忠实。）

### 4.2 E-2

- exit=0，fatal=none，relay 在 peer 退出后存活至 stop-file（HasExited=False 断言通过）

### 4.3 E-3

- hard kill 后 `Gone=True`、exit=-1（强杀后 ExitCode 不可读是预期，如实记录，不用 -1 做判定）

### 4.4 E-4

- 无 relay 时发送成功（UDP 语义）、400 ms 无回包、无伪应答

## §5 证明 / 不证明

### 5.1 证明

1. **fatal/exit 3 真实用例存在且通过**：Relay 收到 ICMP 10054 后如实写 summary（含 fatal 行）并 exit 3，不伪装 0。
2. 故障可见性：E-1 的 fatal 行 + stderr、E-3/E-4 的"发送后无响应"都在驱动侧留下可核对的痕迹。
3. 对端退出但不推流时 Relay 保持存活且可被 stop-file 干净收尾（E-2）。
4. 计数恒等式在故障路径下依然闭合（E-1 datagram identity 8=6+2+0+0、reconciliation 2==2）。
5. 四个场景均无伪协议应答。

### 5.2 不证明

1. **DEGRADED/RECONNECTING 状态机与"不踢人"语义**——原型无状态机，属 M0-B 目标（边界声明见 §1.2）。
2. Relay 心跳（15 s 无包→DEGRADED 30 s→RECONNECTING）时序。
3. 真实两机网络下 ICMP/丢包行为（本报告全在回环）。
4. Hook 观测路径在故障下的行为（Hook 侧全部归 M0-B）。
5. 对端 Agent 在 Windows 真实游戏进程内的退出行为（E-1 用关闭 UDP socket 模拟）。

## §6 运行历史

| 证据目录 | 结果 | 说明 |
|---|---|---|
| `-162043` | FAIL 1/23 | revision 1 首跑：E-3 "relay process gone after hard kill (exit=-1)"——Finish-Relay 强杀分支只返回 Exit=-1（try/catch 吞掉），断言 `[bool]($Exit -ne -1)` 恒 False。修复=返回对象加 `Gone`（HasExited）字段、断言改 `$fin3.Gone`、expectChecks 18→23 |
| `-162129` | PASS 23/23 | 旧采信（relay AE03327E… 时代，exit 0）。证据有效但 relay 已因 F4 `--version` 重建（AE03327E→9E323F81），二进制不可重放，降为历史记录 |
| `-163533` | **PASS 23/23** | **采信**（当前树重跑：relay 9E323F81…/262,144 B，exit 0）。E-1/E-2/E-3/E-4 四场景断言全过，与旧采信行为一致 |

## §7 文件身份

### 7.1 代码

| 文件 | 字节 | sha256 |
|---|---|---|
| `civlink/run-f3e-fault-injection-selftest.ps1` | 22,435 | `BA002D94AC5EB4220A4E6AD09C2F1BC29293B8C9A8A3995CC26F365D366D9162` |
| `civlink/relay/target/release/civlink-relay.exe`（采信 -163533） | 262,144 | `9E323F818AF0DE7699F6C3DBA7D29FB786BBC27CDC2F2D5B908E935A7D60C98C` |
| `civlink/relay/target/release/civlink-relay.exe`（旧 -162129） | 262,144 | `AE03327E417E89A3A885D87A9C7330CE331EAE9E4C24AE27B3AB5B13C0225BE3`（已被重建覆盖） |

### 7.2 证据（采信 `-163533`，16 文件 + `E4/` 空目录）

| 文件 | 字节 | sha256 |
|---|---|---|
| `result.txt` | 895 | `9632BC8736B519873058FD460102B9F2D32DE806D2C3AB9DF3065B86C30A8D07` |
| `E1/E1-console.txt` | 1,934 | `4DD7D8781AFB412918C7FE141A9FA9FCA12144B9202FE2A50450948EC31D15A8` |
| `E1/E1-exit.txt` | 12 | `600765DEEFAB0CBE0138F399147E5415E6C55959D702D3FED74AFD470D9EAE6E` |
| `E1/E1-stderr.txt` | 96 | `CA3F0D8DC27FBF28E16B88C41D70063505DDA95A836F9B5F3692D4A4DF010667` |
| `E1/relay-log.txt` | 744 | `C16B9748EB277F7658A9599502C1B81E6F49B3AD97860C0B76AD53B58E5CF2DF` |
| `E1/relay-summary.txt` | 1,597 | `880AB611100F0F55624C024DC7143E2E8BBD6DBFDE8E162B0C912908C746F53E` |
| `E2/E2-console.txt` | 1,857 | `A9439E88E3DC77D0345764864723B091864663965AD6AD29778BA9F4C8F985B1` |
| `E2/E2-exit.txt` | 12 | `01AD8A20D9C655F39D931C98ACC135EF2B5505ECCEE6B6845F1667FF01CAD1AE` |
| `E2/E2-stderr.txt` | 5 | `F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295` |
| `E2/E2-stop.txt` | 6 | `A0B28CDF92E250A1A93294D91144A0F893D27197D56B39991CC421768794005F` |
| `E2/relay-log.txt` | 622 | `BAB148F49E6E8A65D11AD20ED8856821C56F65FC02772810B1C286CCED22AD62` |
| `E2/relay-summary.txt` | 1,520 | `610C37007FD4ACF68CB104506A57F96FEE03FB510CD729C0AB1BFDA153ADA574` |
| `E3/E3-console.txt` | 62 | `3870CE7BCADC647E212F2CA3EC7951A8D2BD6756A43A8D622DD73BDD8712D055` |
| `E3/E3-exit.txt` | 13 | `EB73CB2E5D812CB0038DAA32EF7769738C4FDEA9030370BD58FE782009360377` |
| `E3/E3-stderr.txt` | 5 | `F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295` |
| `E3/relay-log.txt` | 86 | `C62C5AD174DF20FC6CF4CEFB2E23F786AD90407299B1F831CB07F6C3A2A05BF0` |
| `E4/`（无子目录） | — | E-4 无 relay 进程，只有全局 result.txt 与脚本转录 |

注：5 B 文件（`*stderr.txt`）实测字节为 `EF BB BF 0D 0A`（UTF-8 BOM+CRLF），非空内容；空内容哈希是 `E3B0C442…`。
`E2-stop.txt` 是 6 B（`73 74 6F 70 0D 0A` = "stop"+CRLF），不是 BOM 文件。

## §8 关系

- 设计：`docs/F3-DIRECT-RELAY-DESIGN-20261114.md`（v0.3 定稿）§5.2 表 F3-E 判据、§9 状态机（M0-B 目标）
- 审计：`docs/F3E-REVIEW.md`（第一轮有条件通过；必改清单见 §0.1）
- F3-B 第三轮审计：`docs/F3B-REVIEW-3.md` E5 承接项 → 本报告 §2.1
- F3-A 第五轮审计通过（F3A-REVIEW-5.md）、F3-B v3 第三轮通过（F3B-REVIEW-3.md）、F3-C v3 第三轮通过（F3C-REVIEW-3.md）、F3-D 审计修正已落地（F3D-REVIEW.md）
- Gate 登记：README v1.18「F3-D 判据后半句（Hook 观测路径）未验证」保留——F3-E 不改变该登记

## §9 下一步

- **F3-E 状态：审计通过（F3E-REVIEW-2.md，11/11）**——F3 五子项（A/B/C/D/E）全部完成
- F4 发布候选（REV-016 四阶段最后一环；模拟证据不得写成"双人真实联机已通过"）
- E2-A/E2-B/E3 真实双机仍待验证（PC-B 离线）
