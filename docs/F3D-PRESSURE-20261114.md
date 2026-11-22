# F3-D 输入压力自检记录（2026-11-14）

状态：**原型自检通过（loopback only）**。本文件只记录"分层计数在远超稳态的输入下是否仍然闭合、丢包是否仍然可见"这一件事，不构成任何联机结论。

前置文件：`docs/F3-DIRECT-RELAY-DESIGN-20261114.md` v0.3（§5.2 测试计划 F3-D 一行）、`docs/F2-S5-JOIN-REAL-CLIENT-20261114.md`（真实客户端 ~1.6M `WSARecvFrom`/s 的忙轮询实测，是本测试的输入量级来源）。

---

## §1 这个自检回答什么

F2/S5 在真实 Civ6 客户端里量到 `raw wsarecvfrom = 110,496,364`（约 1.6M 次/秒，70 秒窗口），说明游戏会以远超"每秒几十帧"的速率敲数据面 socket。F3-A / F3-B 两个原型的计数器都是在"每秒个位数帧"的场景下验证的（F3-A 7 帧、F3-B 22 个数据报）。于是有一个没有被回答的问题：

> 当输入速率比稳态高 3–4 个数量级时，Agent / Relay 的分层计数是否还闭得起来？丢包是否还被如实计数、而不是被计成一个"看起来正常"的数字？

本自检只回答这个。它**不**回答：Hook detour 在真实进程内的成本（那是 F2/S4 机械验证与 M0-B）、长时间稳定性（每个进程只跑一次、几秒级）、真实两机、游戏协议、加密。

### §1.1 本轮与设计 §5.2 判据的差异（必须先读）

设计 `docs/F3-DIRECT-RELAY-DESIGN-20261114.md` §5.2 给 F3-D 写的判据是：

> 62056 忙轮询 ~1.6M/s 下 Hook 观测路径不丢帧｜分层计数对账 ==（Agent 事件驱动，不复刻忙轮询）

这句话里有两个可分离的部分，本轮的覆盖并不对等：

| 设计判据的组成部分 | 本轮是否覆盖 | 原因 |
|---|---|---|
| Agent / Relay **分层计数对账闭合**（事件驱动侧）| **是**，见 §3 | 可用 loopback 直接压；不接游戏 |
| Agent / Relay 在远超稳态速率下的**丢帧可见性** | **是**，见 §3.1 的 seq gaps / missing | 同上 |
| 62056 忙轮询 ~1.6M/s 下 **Hook detour 观测路径不丢帧** | **否** | 要在真实游戏进程内注入 CivTrace，并让游戏自己产生 ~1.6M/s 的 `WSARecvFrom`。这属于游戏进程内注入，F3 授权范围明确排除（"本阶段注入测试 socket，游戏进程内注入留 M0-B"）。本机没有第二台机、也不在 F3 授权内重跑真机注入。 |

因此：**F3-D 本轮只完成"分层计数在高压下闭合"这一半**，另一半（Hook 观测路径在真实忙轮询下不丢帧）仍是**未验证**，不能因为本文件 PASS 而视为已勾掉。真要做那一半，需要：真实 Civ6 客户端 + CivTrace v0.4.4 注入 + F2/S5 复现的加入流程 + `civlink_ctl counters` 侧的 `civlh2Try/Ok/Fail` 与 Agent 侧 `datagrams` 对账。那属于 M0-B 前后的真机工作，且受 REV-016"模拟测试不勾掉 E2-A/E2-B/E3"约束。

这一点必须写在最前面，否则本文件很容易被读成"F3-D 全过"。

## §2 测试设计

脚本：`civlink/run-f3d-pressure-selftest.ps1`（`-AgentFrames` / `-RelayFrames`，默认各 40,000）。

发送端是脚本内嵌的 C# 类 `CivLinkBurst`，不是 PowerShell 循环——PowerShell 自身的循环每帧几十微秒，压不到 socket 的瓶颈，会让"压力测试"变成"计时测试"。

### §2.1 Part 1 —— Agent 转发路径

`civlink-agent.exe --forward-to 127.0.0.1:21348 --forward-listen 21348 --simulate-datapath --bind-ip 127.0.0.1 --loopback-selftest --listen-seconds 120`，C# 端向 `127.0.0.1:34718`（Agent 的 CVLH2 通道）连发 40,000 个合法 CVLH2 帧，每帧 8 字节载荷，**帧头的 dst 端口是 62056、发送的线缆端口是 34718**——这两个端口必须分开，否则帧全部落进 `skip not datapath`，压力根本不会经过转发路径（这正是第一版脚本的缺陷，见 §5.1）。

### §2.2 Part 2 —— Relay 转发路径

`civlink-relay.exe --listen 127.0.0.1:34720`，接收端（sink，`UdpClient(21349)`）先以 `dst_peer=777` 注册，然后 C# 端用**同一个 socket** 先注册自己为 `src_peer=101`、再连发 40,000 个 `dst_peer=777` 的 CVLR 信封（12 字节载荷）。

这里必须补一次自身注册：Relay 按"数据报源地址"反查发送者，未注册来源一律 fail-closed 丢弃（F3-B 审计 M-1 的整改）。第一版驱动只注册了 sink，于是 40,000 帧全部落进 `no sender`，转发路径一次都没被压到——而脚本当时全是不等式断言，所以照样打印 PASS。§5.2 记录了这次修正。

## §3 结果

证据目录：`M0A/captures/F3D-pressure-selftest-20261114-151218/`（17 个文件）。

### §3.1 Agent（Part 1，40,000 帧）

| 项 | 值 |
|---|---|
| 发送 | 40,000 数据报（驱动侧）|
| socket 实际收到 | 8,035 数据报 / 401,750 字节 |
| 丢在途 | 31,965（79.91%）|
| 解码帧 | 8,035（processed 8,035，rejected 0）|
| reconciliation | processed + rejected = 8,035 == received = 8,035 |
| seq 范围 | first=1 last=39998，gaps=6,174，missing=31,963，duplicates=0，out_of_order=0 |
| large datagrams / oversize notify | 0 / 0 |
| datapath 观测 | frames seen 8,035，on 62056 8,035，D4 reply sent 1（already_sent 8,034）|
| 转发 | frames seen 8,035，forwarded 8,035，forward bytes 64,280，fail 0 |
| 跳过 | not datapath 0，key table 0，discovery 0 |
| 映射 | mappings created 1（单一 socket 键）|
| 对端接收 | payloads recv 8,035 / 64,280 字节，first&last sender 均 `127.0.0.1:56402` |
| 吞吐 | 发送 228,896/s；解码+转发 45,979 帧/s |

闭合关系逐条成立：
- `datagrams ≥ received`（收到的不比解出来的少）
- `frames_seen == received`（每个解码帧都进了转发阶段）
- `forwarded + skip_not_dp + skip_discovery + skip_key_table + fail == frames_seen`
- `forward bytes == peer payload bytes`（64,280 == 64,280，逐帧 sha256 也在 forward-log / peer-recv 两侧对得上）
- `frames + missing == last - first + 1`
- `gaps > 0 ⟺ missing > 0 且 gaps ≤ missing`

### §3.2 Relay（Part 2，40,000 信封）

| 项 | 值 |
|---|---|
| 发送 | 40,000 信封（驱动侧）|
| 收到 | 13,222 数据报 / 423,008 字节 |
| 丢在途 | 26,778（66.95%）|
| registers / control frames | 8 / 8 |
| forward requests | 13,214 |
| forwarded | 13,214（forward bytes 158,568，fail 0）|
| no route / self drop / no sender / oversize | 0 / 0 / 0 / 0 |
| bad envelope / unknown flags | 0 / 0 |
| fatal | none |
| peers seen | 2 |
| 身份等式 | `datagrams == registers + forward_requests + bad + unknown` → 8 + 13,214 + 0 + 0 = 13,222 |
| 归因等式 | `forwarded + no_route + self_drop + forward_fail + no_sender == forward_requests` → 13,214 = 13,214 |
| 吞吐 | 转发 47,541 帧/s |

### §3.3 关于 sink 的数字

`sinkGot = 2,061`（65,952 字节），明显小于 `forwarded = 13,214`。这是**接收端自身**的限制，不是 Relay 丢包：

- sink 是 PowerShell 里一个阻塞 `UdpClient`，`ReceiveTimeout = 200ms`，排空循环遇到第一次超时就 `break`；
- 13,214 个数据报在约 0.28 秒内涌进单个未扩容的接收缓冲，内核侧就丢了一大半（0.28 秒的涌进时长与"内核丢包"是本文件的**推断**：脚本没有观测内核缓冲区水位，唯一可测的事实是 sink 在 200ms 超时处 break，且 `sinkGot` 远小于 `forwarded`）。

因此脚本对 sink 只做**单侧不等式**（`sinkGot ≤ forwarded`）与 `sinkGot > 0`，从不把 sink 当计数权威。Relay 自己的计数器才是被审对象。这条限制必须在读本文件时记住，否则会把 sink 的 2,061 误读成"Relay 只转了两千个"。

## §4 断言清单（运行时 20 条）

Part 1（10 条）：`agent does not bind UDP :62056 under load`（脚本 L208，本测试唯一检验 Agent 不碰数据面端口的断言）、`agent exited 0 under burst`、`received == processed + rejected`、`datagrams ≥ received`、`frames_seen == received`、`forwarded + skips + fail == frames_seen`、`peer ≤ forwarded`、`frames + missing == last - first + 1`、`gaps 与 missing 同类`、`loss is reported`。

Part 2（10 条）：`relay exited 0 under burst`、`datagrams == registers + requests + bad + unknown`、`forwarded + no_route + self + fail + no_sender == requests`、`fatal == none`、`datagrams ≤ sent + registers`、`sink ≤ forwarded`、`forwarded > 0`、`no sender == 0`、`sink > 0`、`loss is reported honestly`。

另有 6 个前置判定点（Agent/Relay 可执行文件存在 ×2、34718/34720 空闲 ×2、62056 未被占用 ×2）。**这些前置失败时脚本直接 `exit 2`，不打印任何 PASS。**

## §5 自检暴露的缺陷（按修掉的顺序）

### §5.1 产品/驱动侧

1. **帧头 dst 端口 == 线缆端口**：第一版 `SendCvlh2` 只接受一个端口参数，既当发送目标又写进帧头，于是 Agent 判定 `dst port != 62056` → 40,000 帧全部 `skip not datapath`、`forwarded = 0`。修法：`SendCvlh2(count, dstIp, wirePort, hdrDstPort, payloadLen, startSeq)`，调用时 `wirePort=34718`、`hdrDstPort=62056`。
2. **驱动没有注册自己**：Relay 按源地址反查发送者并 fail-closed。第一版只注册了 sink，40,000 帧全落 `no sender`。修法：`SendRelay` 在 burst 前用同一个 socket 发 3 次 REGISTER（`src_peer`），并把 `no sender == 0` 变成断言。

### §5.2 断言强度侧

3. **全是不等式**：`datagrams <= sent`、`sink <= forwarded`、`(fwd + no_sender + bad) <= datagrams` —— 这三条在"什么都没转发"时全部成立。§5.1 的两个缺陷就是靠这个躲过第一轮冒烟的。修法：新增 `forwarded > 0`、`no sender == 0`、`sink > 0` 三条**方向性**断言。
4. **`gaps == missing` 是错的**：一个突发丢掉 24 个连续帧 = 1 个 gap + 24 个 missing，两者本来就不等。修法：改判"0 gaps ⟺ 0 missing，且 gaps ≤ missing"。
5. **`datagrams <= sent` 是错的**：Relay 的 `datagrams` 还含 5–8 次注册（注册不来自 burst）。修法：`datagrams <= sent + registers`。

### §5.3 脚本自身

6. **CVLR 头 `payload_len` 写成了大端**：脚本用 `WriteBe16`，而协议是**小端**，Relay 读出一个巨大的长度，把整个 burst 判成 `payload-too-large`（`bad = 2000`）。修法：改小端。
7. **PowerShell 注释用了 `//`**：PS 只认 `#`，`//` 导致 ParserError（`Unexpected token 'is'`），整个脚本一行都没跑起来。

## §6 文件身份

| 文件 | 字节 | SHA-256 |
|---|---|---|
| `civlink/run-f3d-pressure-selftest.ps1` | 22,888 | `DF96FD69215535B15A2C7BDAC7CAD6EB75F54C68B5FB301741F5CD553D3AEC8F` |
| `civlink/civlink-agent.exe` | 382,976 | `A43248B9900920D3A0C2A80DE17FD96D15AFAD7C01B3B56DCC54AE5EA0A9AA7E` |
| `civlink/relay/target/release/civlink-relay.exe` | 262,144 | `AE03327E417E89A3A885D87A9C7330CE331EAE9E4C24AE27B3AB5B13C0225BE3` |

证据目录 `M0A/captures/F3D-pressure-selftest-20261114-151218/`：

| 文件 | 字节 | SHA-256 |
|---|---|---|
| `summary.txt` | 3,753 | `DA3B69597480CF4A8874803A668649527331869E4292BA3F07BA122AFA4FBD5D` |
| `frame-log.txt` | 1,104,720 | `AE11046A2BC7AC0D02CF05AB2807846FB561F4BD981C2557811614AC58428C1E` |
| `forward-log.txt` | 2,726,647 | `46D41B3D697C6A8A14BFF0F31D5FF8D65B6BABA96FDF1168A21E9AEF2252B9AD` |
| `datapath-log.txt` | 811,720 | `A6C7025270247C24112A0E72E91959A241976F3F93371AE7389CAC763878A2F7` |
| `agent-console.txt` | 5 | `F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295` |
| `agent-stderr.txt` | 5 | `F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295` |
| `agent-exit.txt` | 50 | `78B2702012B81240C518A082F7E13B12ADB7B814AD3BC64ACA99F0FD31121842` |
| `agent-pressure.txt` | 114 | `278D906EF1F381F6B500DC5EBDF2E0CABD8A62A3289FAAC8CF0ADFCA45CC6B15` |
| `agent-stop` | 0 | `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855` |
| `relay-console.txt` | 1,838 | `D1174704283B6B60E1FBA98664645461BB55CE3C32BF6D4BA79D80BBF8A63D92` |
| `relay-stderr.txt` | 5 | `F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295` |
| `relay-exit.txt` | 57 | `1C456D44318997942F0859587DF95AEDFDB1337966D5CE7A21046608F84E6C4B` |
| `relay-pressure.txt` | 95 | `F1FFD135B80221F3CF3EDF337FDE70BF8F872DCD4D739238BB7CB383D488A60B` |
| `relay-log.txt` | 1,672,071 | `67DCCEE1820CB7A4FF433B2F70C438FF376B99E66EF008BB8420F784BA0B3943` |
| `relay-summary.txt` | 1,556 | `69177D57A4170CA64BC2F8C31074553A3B0DFE901A62819DF762DDB0DE9C6E06` |
| `relay-stop` | 0 | `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855` |
| `boundary.txt` | 666 | `9119C69AED4689BED8716406AE4A7B3CCC380AC048B4A5820AC9E886E8E75853` |

`agent-console.txt` 与 `agent-stderr.txt` 同为 5 字节且内容相同（实测字节 `EF BB BF 0D 0A` = UTF-8 BOM + CRLF，是 PowerShell 重定向空输出时写出的固定序列），故哈希相同（`F01A374E…`），不是复制错误。注意这不是"空内容的 SHA-256"——空内容的 SHA-256 是 `E3B0C44298FC1C…`，本证据目录的 `agent-stop` / `relay-stop` 才是 0 字节空文件。

### §6.1 运行历史

| 目录后缀 | 帧数 | 结果 | 说明 |
|---|---|---|---|
| `-150046` | 40,000 | 未记录 | 本轮采信 `-151218` 之前的另一次 40,000 帧运行；当时未在文档点名，本节只登记目录存在（`F3D-pressure-selftest-20261114-150046`），不作结论依据 |
| `-150153` | 3,000 | PASS（旧断言集）| 转发路径未被压到（`forwarded = 0`），Relay 全落 `no sender`。**结论作废** |
| `-151103` | 3,000 | PASS（旧断言集）| 同上，仍是"绿但空转"。**结论作废** |
| `-151218` | 40,000 | **PASS（20 条，采信）** | 本文件记录的那一次 |

`-150153` / `-151103` 两次"PASS"是断言强度的直接教训：**全不等式断言下，什么都没做也是绿的**。

## §7 证明与不证明

**证明**（限 loopback、单进程、几秒窗口）：

1. Agent 在 45,979 帧/s 的解码+转发吞吐下，六条闭合关系全部成立，丢帧被如实计入 `seq gaps / missing`。注意：`frames + missing == last - first + 1` 这条在 agent 里与 `seq gaps / missing` 同源于 `note_seq`（`agent/src/main.rs:933-953` 的一次推导），是算术必然、不能证伪任何输入，**不能**据此推论"没有计数闭合但实际丢包"——本文件不保留该推论（第三轮审计 F3D-REVIEW.md H-2）。
2. Relay 在 47,541 帧/s 的转发吞吐下，身份等式与归因等式同时成立，`fatal` 保持 `none`。
3. 两个原型的丢包都由**三层**分别可见：驱动侧 sent / socket 侧 received（datagrams）/ 语义侧 forwarded，且三层单调递减、差值有解释。
4. D4 的"整轮最多 1 个 20B 回包"在 8,035 帧里仍然恰好 1 次（`already_sent = 8,034`），说明该约束不随输入量放大。
5. Agent 在压力场景下没有绑定 62056（`bind-check.txt` 有运行期断言；注意该断言只覆盖 Agent 侧，Relay 侧"不绑定 62056"由 F3-B 的 `--listen 62056` 负向用例覆盖，本 F3-D 运行本身不包含 Relay 侧 62056 断言——见 §7 不证明第 7 条）。

**不证明**：

1. 不证明 Hook detour 在真实游戏进程内、每秒百万次 `WSARecvFrom` 下的成本——那是 F2/S4 的机械验证与 M0-B 的范围。
2. 不证明长时间稳定性：每个进程只跑一次 burst，窗口 1–3 秒；没有内存泄漏、句柄泄漏、计数器回绕的观测。
3. 不证明真实两机、跨网、Relay 真实部署、游戏侧收包。
4. 不证明丢包率代表产品表现：79.91% / 66.95% 是本驱动（单 socket 无节流、接收端 200ms 超时即退出）的属性，**不是**产品在正常输入下的丢包率。
5. 不证明加密、身份、H1/H2/H8/R1、Fake-IP 选段、wire format 冻结。
6. 不证明 `sink` 的接收数字有计量意义（见 §3.3）。

## §8 与其它文件的关系

- 设计依据：`docs/F3-DIRECT-RELAY-DESIGN-20261114.md` v0.3 §5.2 F3-D 行。
- 同族记录：`docs/F3A-DIRECT-FORWARD-20261114.md`（F3-A v3）、`docs/F3B-RELAY-FORWARD-20261114.md`（F3-B 第二版）、`docs/F3C-BACKOFF-20261114.md`（F3-C）。
- 输入量级来源：`docs/F2-S5-JOIN-REAL-CLIENT-20261114.md` §3.2。
- 本轮是 REV-016 四阶段中 **F3（直连与 Relay 路径）** 的第 4 个子项；Gate A / M0-B / Gate B 状态不受影响。

## §9 下一步

F3-E 故障注入：对端提前退出、Relay 掉线、CVLH2 通道 down、乱序/重复/缺口、超长帧、FakeEndpoint 缺失、映射池耗尽；要求在每种情况下进程给出**真实退出码**（不伪装成 0）、计数器可解释、且不产生伪协议应答。
