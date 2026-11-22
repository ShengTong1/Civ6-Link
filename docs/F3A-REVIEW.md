# F3-A 直连转发原型（本机回环）审计报告

> 审计对象：REV-016「模拟对端快速路线」F3 阶段 **F3-A**
> 审计角色：独立代码/证据审计官（**只读**：未修改任何被审文件、未运行游戏、未运行网络实验、未重跑驱动脚本）
> 审计基准：`docs\F3-DIRECT-RELAY-DESIGN-20261114.md` v0.3 定稿 §3.2 / §3.3 / §3.4 / §4.1 / §4.2 / §5.1 / §5.2 / §5.3 / §6
> 审计时间：2026-11-14
> 结论：**有条件通过（CONDITIONAL PASS）**——机制与证据成立，但"原样载荷"证据链偏弱、`--port 62056` 红线未在实现层闭环、`no_mapping` 语义与记录引用不符；进入 F3-B 前须补齐 §7 的 7 项。

---

## 0. 审计方法与边界

**实际做的**

1. 用 `Get-FileHash -Algorithm SHA256` 重算 4 个源码/二进制 + 证据目录全部 9 个文件的哈希与字节数，逐项对照完成记录 §4。
2. 逐行读 `docs\F3A-DIRECT-FORWARD-20261114.md`（75 行）、`civlink\run-f3a-forward-selftest.ps1`（219 行）、`civlink\agent\src\main.rs` 中 F3-A 全部相关实现（约 534–710、864–980、1065–1135、1218–1235、1441–1533 行）、`civlink\common\cvlh2.h`、`civlink\fakeip\src\lib.rs`。
3. 逐行读证据目录 6 个文本证据（summary / forward-log / frame-log / datapath-log / bind-check / exit），做算术与时间戳自洽性核对。
4. 对驱动脚本 18 处 `Check` 调用逐条判定"是否会恒真/是否能被错误实现通过"。

**没有做的（因此本报告不覆盖）**

- 未运行 `run-f3a-forward-selftest.ps1`，未运行 `cargo test`，未运行游戏或任何网络实验——所有代码结论为静态阅读结论。
- 未反编译 `civlink-agent.exe`，**无法证明该 exe 由被审 `main.rs` 编译而来**（见 §2.3）。
- 仓库内**没有 E1–E7 七条前置条件的逐条定义文本**（`grep` 全仓 `*.md` 未找到枚举）。`docs\F2-DATAPATH-COMPLETION-20261114.md` §6 只写"C1–C5、E1–E7 已全部落实"。故本报告**不能**逐条验收 E1–E7，只能验证"设计文档 v0.3 是否把对应约束落到 §3.2/§4.2/§5.2/§5.3 并用代码实现"。

**红线框架（本报告的判定尺子）**

F3 全部为本机回环（127.0.0.1）纯转发原型；不得游戏进程内注入；不得做 H1/H2/H8/R1 判定；不得冻结 wire format 或身份密钥协议；不得声称真实双机联机；工具级/模拟证据不得宣传为联机验证；**不得把"没有错误"写成"零丢包"**。

---

## 1. 裁定摘要

| 维度 | 判定 | 一句话理由 |
|------|------|-----------|
| A 证据真实性 | **通过** | 9/9 哈希与记录 §4 逐项一致；summary 与 forward-log/frame-log/datapath-log 在条数、字节、时间戳上完全自洽，无一处算术矛盾 |
| B 代码与设计一致性 | **基本一致（有 2 处偏离）** | `dst==62056` 单目标转发、发现帧排除、单次投递不重传、映射键形状、`--forward-listen` 拒 62056 均成立；偏离为 `no_mapping` 语义、`--port` 无 62056 护栏 |
| C 表述边界 | **基本合规（3 处需收紧）** | 未宣称联机、未宣称零丢包、未暗示 H2/R1 已测；但"对端确实收到同样的载荷"强于证据、"单进程自环"未声明、`no_mapping` 引用错条款 |
| D 断言强度 | **偏弱** | 18 项断言中 1 项恒真（硬编码字符串）、1 项可空集恒真、3 项为弱断言（长度/前缀）；全字节比对、seq 对账、发送方身份、负向用例均缺 |
| E 缺陷清单 | 5 中 13 低，0 高 | 见 §6，无"高"级缺陷（无造假、无越界、无默认路径违规） |
| F 裁定 | **有条件通过** | 可承认 F3-A 机制原型成立；F3-B 开工前须补齐 §7 的 7 项 |

**关键判断（给裁定的直接依据）**：本步的证据足以支撑"**dst 端口 == 62056 的已接收帧，其载荷被原样（不改写）以单次 UDP 发往唯一配置目标，且发现帧与非 62056 帧未进入该路径**"这一机制性命题；**不足以支撑**"端到端字节级原样"这一更强命题（只验证了长度与前 8 字节），也**不足以支撑**"对端 Agent 收到"中的"对端"是独立 Agent（实际是同进程双角色自环）。

---

## 2. A. 证据真实性

### 2.1 哈希复算（全部实测，非引用）

| 文件 | 记录字节 | 实测字节 | 记录 SHA-256（前 16） | 实测 SHA-256 | 结论 |
|------|---------:|---------:|----------------------|--------------|------|
| `civlink\agent\src\main.rs` | 76,311 | 76,311 | `225FF75254D8F732` | `225FF75254D8F732…A242ED9C` | ✅ 一致 |
| `civlink\agent\Cargo.toml` | 525 | 525 | `0CC694BBE083E20F` | `0CC694BBE083E20F…81F22017` | ✅ 一致 |
| `civlink\civlink-agent.exe` | 372,224 | 372,224 | `AF6B4568DDC85E50` | `AF6B4568DDC85E50…3192BBEC` | ✅ 一致 |
| `civlink\run-f3a-forward-selftest.ps1` | 10,198 | 10,198 | `0151270D2B4A64CB` | `0151270D2B4A64CB…9EA294A45` | ✅ 一致 |
| 证据 `summary.txt` | 3,058 | 3,058 | `EE52C6E1617986D4` | `EE52C6E1617986D4…F62D8DDFE` | ✅ 一致 |
| 证据 `forward-log.txt` | 733 | 733 | `65C5BF6D48E934F3` | `65C5BF6D48E934F3…392DD60F0` | ✅ 一致 |
| 证据 `frame-log.txt` | 788 | 788 | `D7175B1AE41B26B2` | `D7175B1AE41B26B2…AFE92C3873` | ✅ 一致 |
| 证据 `datapath-log.txt` | 583 | 583 | `C91FCF0155492CFD` | `C91FCF0155492CFD…4DDB2A976` | ✅ 一致 |
| 证据 `bind-check.txt` | 48 | 48 | `8AA463B61AFA4529` | `8AA463B61AFA4529…E1DF6CB03D` | ✅ 一致 |

**结论**：记录 §4 的 9 行**逐项一致，无一处出入**。哈希级证据完整性成立。

**但覆盖不全**（低severity，见 §6-L6）：证据目录实有 **9 个文件**，§4 表只登记 5 个，以下 4 个未登记：

| 未登记文件 | 字节 | 实测 SHA-256 |
|-----------|-----:|--------------|
| `agent-console.txt` | 5 | `F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295` |
| `agent-stderr.txt` | 5 | 同上（同一空行，证明 stderr 为空） |
| `exit.txt` | 17 | `81DDBAF9EED6926436F584FADECA0FBBE6DF4B4E6A47F318AF3A728A6574385A` |
| `stop` | 0 | `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`（空文件的标准哈希） |

其中 `exit.txt` 承载着"`agent exit=0`"这一**被断言依赖的关键值**，却未进文件身份表——这是证据表设计上的一处缺口，应补。

### 2.2 summary.txt 与逐行日志的自洽性（逐项核对）

| 核对项 | summary.txt | 逐行日志 | 结论 |
|--------|-------------|---------|------|
| 收到的 UDP 报文 | `datagrams: 5`（行 4） | frame-log 5 行 | ✅ |
| 字节总数 | `bytes: 354`（行 5） | 5×(42B 头) + (8+8+4+4+120) = 210+144 = **354** | ✅ 算术自洽 |
| 接受帧 | `received frames: 5 (processed 5, rejected 0)` | frame-log 5 行 | ✅ |
| 对账等式 | `processed + rejected = 5 == received = 5` | — | ✅ |
| seq 连续 | `frames=5 first_seq=1 last_seq=5`、`seq gaps=0 missing_frames=0 duplicates=0 out_of_order=0` | frame-log seq=1,2,3,4,5 | ✅ |
| 载荷总字节 | `payload bytes=144` | 8+8+4+4+120 = **144** | ✅ |
| 发现帧统计 | `discovery_magic=1 other_payload=4` | seq3 head=`8DE8FC70` 恰 1 条 | ✅ |
| 标志位统计 | `via_wsasendto=3 limited_bcast=1 discovery_flag=1` | flags `0x21`×3 / `0x06`×1 / `0x20`×1 | ✅（0x21=0x20\|0x01，0x06=0x04\|0x02） |
| dst 端口分布 | `dst ports=3 (min 50999, max 62905, in 62900..62999: 1)` | 62056,62056,62905,50999,62056 → 3 种；区间内 1 条 | ✅ |
| 源端点 | `src endpoints: 127.0.0.1:21345 x5` | frame-log 5 行全部 `src=127.0.0.1:21345` | ✅ |
| 转发帧数 | `forwarded: 3`（行 33） | forward-log 恰 3 条 `forward seq=` | ✅ |
| 转发字节 | `forward bytes: 136`（行 34） | 8+8+120 = **136** | ✅ |
| 转发失败 | `forward fail: 0` | 无 `forward FAILED` 行 | ✅ |
| 未转发计数 | `no mapping: 1`（行 36） | 恰 1 条 `forward skip dst_port=50999` | ✅ |
| 映射创建 | `mappings created: 1`（行 37） | 3 条 62056 帧共用 1 个键（session/sock/gen/dst 全同） | ✅ |
| 对端接收数 | `payloads recv: 3`（行 41） | 恰 3 条 `peer-recv n=1/2/3` | ✅ |
| 对端字节 | `payload bytes: 136`（行 42） | 8+8+120 = 136 | ✅ |
| 对端监听 | `listen port: 21346`（行 40） | 驱动脚本 `--forward-listen 21346` | ✅ |
| 对端最后发送者 | `last sender: 127.0.0.1:53458` | peer-recv 三条均 `from=127.0.0.1:53458` | ✅ |
| 时间戳单调 | — | forward-log `06:20:09.936 → .939`；summary `run time 06:20:11.505` 晚于全部日志 | ✅ |
| 发现端口被转发？ | — | forward-log **无任何** `dst=…:62905` 行；peer-recv 只有 len=8/8/120（无 4B） | ✅ |

**结论**：**未发现任何数字层面的自相矛盾**。三个日志（frame / forward / datapath）与 summary 在条数、字节、端口、时间戳上互相咬合，证据是同时刻同一次运行产生的，非拼装。

### 2.3 证据链的两处固有局限（不影响 A 通过，但必须记录）

1. **exe 的来源无法证明。** 哈希一致只证明"文件就是这一个文件"。`civlink-agent.exe`（372,224 B）与 `main.rs` 之间没有可核对的构建元数据（无 build log、无嵌入源哈希、无 `--version` 输出留档）。**间接佐证**是字符串级一一对应：`forward-log.txt` 第 1 行 `# civlink-agent 0.3.0 - F3-A forward prototype (loopback only, verbatim payload, no retransmit)` 与 `main.rs:1096` 的字面量完全相同；`summary.txt:30` `direct forward prototype (F3-A)` 与 `main.rs:1472` 相同；`forward-log.txt` 的 `forward skip dst_port=50999 (not the 62056 datapath)` 与 `main.rs:615` 相同。这足以说明"该 exe 含本步代码"，但不是可验的构建对应关系。**建议**：以后在证据目录落一份 `agent-version.txt`（`civlink-agent --version` 输出 + `cargo build` 时间戳）。severity 低，但这是"文件哈希 ≠ 来源证明"的一般性方法问题，值得写进项目惯例。

2. **`bind-check.txt` 的语义边界。** 内容是 `agent pid=31472 udp:62056 owned by agent: 0`，脚本用 `Get-NetUDPEndpoint -LocalPort 62056 | Where-Object { $_.OwningProcess -eq $proc.Id }` 过滤后计数（脚本 120–124 行）。**该断言只证明"该 Agent 进程未持有 62056"**，不证明"Agent 在游戏运行时也不会持有"，也不证明"游戏持有过 62056"。审计时该机 `Get-NetUDPEndpoint -LocalPort 62056` 返回空（无人绑定），因此"计数为 0"在"没有任何进程绑 62056"的环境下同样成立——好在脚本过滤了 `OwningProcess`，语义未被污染。这条**应当**在完成记录里写明其证明边界（现在记录 §3 只写"Agent 未占数据面端口"，方向正确但未点明"未覆盖游戏共存场景"）。

### 2.4 未披露的 3 次失败运行（过程披露缺口）

`M0A\captures\` 下存在 4 个同名前缀目录：

| 目录 | `exit.txt` | 字节 | 说明 |
|------|-----------|-----:|------|
| `F3A-forward-selftest-20261114-141849` | `agent exit=`（空值） | 16 | 断言必失败 |
| `F3A-forward-selftest-20261114-141904` | `agent exit=`（空值） | 16 | 断言必失败 |
| `F3A-forward-selftest-20261114-141929` | `agent exit=`（空值） | 16 | 断言必失败 |
| `F3A-forward-selftest-20261114-142008` | `agent exit=0` | 17 | **被引用为证据的最终运行** |

前三轮的 summary/forward-log 数字与最终轮**一致**（即转发机制本身一次就通，失败的只是 `ExitCode` 读取）。这与记录 §5 坑 1/2/3 的描述吻合，说明"坑"是真实踩到并修复的，不是事后补写。**但记录正文从未提及这三轮**。建议在 §5 末尾补一句："前三轮（141849/141904/141929）因 `ExitCode` 不可读，不满足断言前置，未计入证据；其 summary 数字与本轮一致，说明转发机制首次即通。"——这是**提升**可信度的披露，不披露反而是风险。

---

## 3. B. 代码与设计一致性

### 3.1 逐条核对

| 设计要求 | 实现位置 | 判定 | 说明 |
|---------|---------|------|------|
| §3.2 只转发 dst 端口 == 62056 的帧 | `main.rs:609-620` `if dst_port != DATAPATH_PORT { no_mapping+=1; …; return; }` | ✅ **成立** | `DATAPATH_PORT=62056`（`main.rs:61`）；非 62056 一律 return，无旁路 |
| §3.2 规则3 发现帧不进入转发 | `main.rs:1225-1228` `is_discovery = flags & FLAG_DISCOVERY != 0 \|\| (62900..=62999)` → `if !is_discovery { fw.consider(…) }` | ✅ **成立** | 调用点前置排除，`consider()` 根本看不到发现帧。且即使看到，`dst_port != 62056` 分支也会拦下（纵深防御偶然成立） |
| §3.2 只发往**唯一目标**（对端 Agent 转发接收端口，非 62056、非游戏 socket） | `main.rs:562-582` `target: SocketAddr` 单值；`main.rs:623` `send_to(&frame.payload, self.target)` | ✅ **成立** | 结构上只有一个目标地址，无列表、无多播 |
| §4.2 载荷 100% 原样、不解密、不改写 | `main.rs:623` 直接 `&frame.payload`；`main.rs:712-755` `decode` 中 `payload: buf[42..42+payload_len].to_vec()` | ✅ **代码层成立** | 从解码到发送之间无任何字节变换；无加密/压缩/填充 |
| §4.2 一次一帧、不重传 | `main.rs:607-656` 单次 `send_to`，无循环无重试 | ✅ **成立** | 失败只计数 `forward_fail`（`main.rs:643-654`），不重发 |
| §3.2 映射键 (session_id, logical_socket_id, socket_generation, dst) | `main.rs:554-560` `ForwardMapKey{session_id, logical_socket_id, socket_generation, dst_ip_be, dst_port_be}` | ✅ **形状一致** | `dst` 拆成 ip+port 两字段，语义等价于 crate 的 `FakeEndpoint`（`fakeip\src\lib.rs:71-76`）。**未复用 crate 类型**（原型自建 `Vec` 线性表，见 `main.rs:566` 注释），记录已声明"原型分配器、crate 仍是参考实现"，表述可接受 |
| §3.2 第 2 步"未命中则不转发并计数 no_mapping" | `main.rs:584-603` `ensure_mapping()` **首次流量即分配**并恒返回 `true`；`main.rs:622` 忽略返回值 | ⚠️ **语义偏离** | 数据面帧**永远不会"未命中"**——凡 dst==62056 必然被转发。`no_mapping` 实际统计的是"dst 端口 != 62056"。见 §6-M2 |
| §5.3 Agent 不得与游戏共存绑定 62056 | `main.rs:944-948` `--forward-listen` 拒绝 62056 ✅；**但 `main.rs:890` `--port` 无任何校验** | ⚠️ **未闭环** | 默认路径安全（默认 34718，绑 127.0.0.1）；但 `civlink-agent --port 62056` 会被接受并 `bind(127.0.0.1:62056)`（`main.rs:984`）。见 §6-M1 |
| §5.3 不得设 SO_REUSEADDR | 全文 `grep` 仅两处**注释**（`main.rs:28`、`main.rs:412`）提到，无任何 `set_reuse_address` 调用 | ✅ **成立** | 全部 5 处 `UdpSocket::bind`（312/447/574/676/985）均无 reuse 相关调用 |
| §3.4 本阶段只注入"测试接收 socket"，非游戏进程内 | `main.rs:668-709` `ForwardListener` 只 `recv_from` + 记账，不 `send_to`、不 `inject` | ✅ **成立（且比允许范围更窄）** | §3.4 允许"注入到测试接收 socket"，本步只做到"接收并记录"，未做注入。属**收窄**，不越界 |
| §5.2 回包策略二选一（≤1 个 20B 或 不回包） | F3-A 路径自身无任何回包代码；`datapath-log.txt` 的 1 条 20B 来自 F2 D4（`main.rs:1441-1470` 段） | ⚠️ **未声明选择** | 行为等价于"策略②不回包"，但完成记录未写明选的是哪一条，而这是 §5.2 的**显式判据项**。见 §6-L13 |

### 3.2 `consider()` 的完整行为模型（静态推演，与被审证据对照）

```
consider(frame):
  frames_seen += 1
  dst_port = port_from_be16(frame.dst_port_be)          // :609，BE→host
  if dst_port != 62056:                                  // :610
      no_mapping += 1;  log "forward skip dst_port=…"; return
  ensure_mapping(frame)                                  // :622，返回值丢弃
  n = sock.send_to(&frame.payload, self.target)          // :623
  if n == payload.len(): forwarded+=1; bytes+=n; log "forward seq=… dst=host:port len=… payload=<前8B> -> target"
  else:                  forward_fail+=1; log "forward FAILED seq=… len=…"
```

用被审证据代入：seq1(62056,8B)→forwarded；seq2(62056,8B)→forwarded；seq3(62905)→**不进入**（调用点已排除）；seq4(50999)→no_mapping；seq5(62056,120B)→forwarded。得 `frames_seen=4 / forwarded=3 / bytes=136 / no_mapping=1 / mappings_created=1`，与 `summary.txt:32-37` **逐字段吻合**。静态模型与运行证据一致，说明代码执行的确实是设计描述的那条路径。

### 3.3 三处实现细节（均非缺陷，但影响"本机回环"标签的纯度）

1. **`ForwardState::new` 绑 `0.0.0.0:0`**（`main.rs:574`）而非 `127.0.0.1:0`。用于发送的套接字绑通配地址可收发任意网卡流量。不违反 D2 字面（未绑 62056、未设 reuse），也与"本机回环原型"不冲突（目标地址是 127.0.0.1），但**审计视角下会产生"为什么转发套接字是通配的"疑问**，且为 F3-B/F3-C 的多机场景留下无意的对外可达面。建议改 `127.0.0.1:0`。
2. **`ForwardListener::drain` 的 2048 B 缓冲**（`main.rs:1130` 每轮 `let mut pbuf = [0u8; 2048]`）。UDP 报文最大 65507 B；超过 2048 的载荷会被内核**截断**，而 `stats.bytes += len`（`main.rs:691`）计的是**截断后**长度，日志 `len=` 同样是截断后值——即"静默少计"。当前不触发：转发侧上游受 `MAX_PAYLOAD=1280`（`main.rs:46`）约束，最大帧 42+1280=1322 < 2048。**属潜在缺陷，不是本轮证据缺陷**。建议缓冲改 65535 或 42+MAX_PAYLOAD 并注释上限来源。
3. **`stop_seen` 的 break 在 drain 之前**（`main.rs:1123-1132`）。写 stop 文件后主循环直接 break，当轮不再 drain，尾部刚到达的 payload 可能丢。本轮不触发（3 条 peer-recv 全记录，且 stop 是在 sleep 1.5 s 后写的）。建议 break 前补一次 drain。

---

## 4. C. 表述边界

### 4.1 合规的部分（应予以确认）

- 记录首部（第 3–5 行）明确："机械自检通过"、"证据标签：模拟数据面对端（本机回环 127.0.0.1）"、"**不是真实双机、不是游戏进程内注入、不是联机验证**"。这是本项目要求的标准句式，**做到了**。
- 记录 §3"不证明"清单（第 50 行）6 项：真实 Peer 可达性、真实双机加入/对局、游戏进程内注入与绑定共存（H2/R1）、跨网/Relay RTT、加密与密钥协商、长稳与高负载。**与设计 §5.1 的不承诺清单逐项对应，无遗漏、无反向暗示**。
- 记录 §2 第 3 步强调"**运行中**"检查端口占用，§5 坑 3 强调"把实际值写进证据文件"——这是对"断言不能靠推断"的正确实践。
- 全文**没有**出现"零丢包""联机成功""验证了 H2""R1 可用"等越界措辞。`summary.txt` 的 notes（行 45–63）把 LOOPBACK PROTOTYPE、no retransmit、不注入游戏、不声明 H2/R1/Relay RTT/加密全部写进**产物本身**（而非只写在文档里），这一点做得比一般项目好。
- 记录**没有**把"`forward fail: 0`"写成"零丢包"——`main.rs:1486` 的字段名是 `forward fail`，`summary.txt:35` 同名字段，语义是"本端 `send_to` 失败次数"，不是丢包统计。措辞安全。

### 4.2 需要收紧的 3 处

**C-1（中）"对端确实收到同样的载荷"强于证据。**

> 记录第 48 行：「按唯一目标原样转发，**对端确实收到同样的载荷（字节数与载荷头一致）**」

括号里的限定"字节数与载荷头一致"其实是**诚实的自我降级**，但主句"同样的载荷"仍会被读成"全字节比对通过"。实际证据是：
- 长度一致（136 = 136）✅
- 每个载荷的**前 8 字节**一致 ✅（`forward-log` 与 `peer-recv` 行的 `payload=` 字段都是 `.min(8)`，见 `main.rs:638`、`main.rs:701`）
- 120 B 载荷的**后 112 字节从未被任何一方记录或比对** ❌

建议改为："对端收到的长度与载荷前 8 字节与发送端一致；**未做全字节比对**（日志只记录前 8 字节，全字节一致性靠 `send_to(&frame.payload)` 的代码路径保证，非独立证据）。"

**C-2（中）"单 Agent 自环"未声明，"对端 Agent"一词有歧义。**

驱动脚本把 `--forward-to 127.0.0.1:21346` 与 `--forward-listen 21346` 传给**同一个进程**（脚本 86–87 行），即发送侧与接收侧是**同一个 Agent 进程的两个套接字**（`main.rs:1071-1073` 注释也承认 "may be combined in one process for a loopback self-test"）。而设计 §5.2 的 F3-A 判据语境是"对端 Agent 收到并确认转发"，读起来像两个 Agent。

证据里可区分：`forward-log` 的 `peer-recv … from=127.0.0.1:53458` 与 F2 的 `reply sent … (ephemeral src port 53457)` 是两个不同端口，说明转发套接字确实是独立于 F2 回包套接字的新套接字——但**它属于同一进程**。

建议在记录 §2 或 §3 加一句："本步为**单进程双角色自环**（一个 Agent 同时扮演发送侧与接收侧），验证的是**线路与转发逻辑**，不是两个独立 Agent 之间的通信；双 Agent 形态由 F3-B 覆盖。"

**C-3（中低）`no_mapping` 引用了错误的条款。**

> 记录第 15 行：「非 62056 帧 → 计入 `no_mapping`，不转发 → **对应设计 §3.2 第 2 步"未命中则不转发并计数"**」

设计 §3.2 第 2 步的"未命中"指的是**数据面帧查映射表未命中**（即 dst==62056 但键不在表中）。代码里这条路**不存在**（`ensure_mapping` 首次即建，恒返回 true，`main.rs:584-603`），因此该条款**从未被执行**，也就谈不上"对应"。`no_mapping` 实际统计的是"不是数据面帧"，是另一件事。这是一处**引用错误**，会让读者以为"未命中不转发"这条设计规则已被验证。

建议：要么（a）改实现，让 `ensure_mapping` 真正返回 bool 且 `consider` 在 `false` 时不发（此时 5 帧里 seq1 会因"首帧无映射"被拒，需要先有建表动作或允许首帧建表——语义要重新定义）；要么（b）**保留实现、改文案**：把计数器改名或至少把记录引用改为设计 §4.3（"首次流量分配"生命周期规则），并在 §3"不证明"里加一条"映射未命中路径未实现/未测试"。**（b）成本更低且更符合原型阶段定位，推荐 (b)。**

---

## 5. D. 断言强度

驱动脚本 `civlink\run-f3a-forward-selftest.ps1` 实际有 **18 处 `Check` 调用**（`grep '^\s*Check '` 计数=18），不是记录宣称的 17 项。

### 5.1 逐条判定

| # | 行号 | 断言 | 强度 | 判定 |
|---|-----:|------|------|------|
| 1 | 124 | `agent does not bind UDP :62056` | 强 | ✅ 但只覆盖默认 `--port 34718` 路径；`--port 62056` 违例路径无负向用例 |
| 2 | 159 | `agent exit code 0` | 强 | ✅ |
| 3 | 187 | `frames seen == 4` | 强 | ✅ |
| 4 | 188 | `forwarded == 3` | 强 | ✅ |
| 5 | 189 | `forward bytes == 136` | 强 | ✅（但"字节数"本身不构成"原样"证据） |
| 6 | 190 | `forward fail == 0` | 强 | ✅（`send_to` 本端失败数，非丢包） |
| 7 | 191 | `no mapping == 1` | 中 | ⚠️ 测的是"非 62056 被跳过"，非"62056 无映射"（语义见 §4.2 C-3） |
| 8 | 192 | `mappings created == 1` | 强 | ✅ 反向证明 3 帧共用 1 键 |
| 9 | 193 | `peer payloads recv == 3 (… no retransmit)` | **弱** | ⚠️ 条数相等不能排除"某帧被投两次 + 另一帧丢失"的巧合；peer 侧无 seq/哈希，无法由条数推出"不重传" |
| 10 | 194 | `peer payload bytes == 136 (verbatim, no rewrite)` | **弱** | ⚠️ 长度和相等 ≠ 字节相同；"verbatim" 这个词超出该断言能力 |
| 11 | 195 | `peer listen port == 21346` | 强 | ✅ 实际比文档写的 "`!=62056`" 更强 |
| 12 | 196 | `target == 127.0.0.1:21346` | 中 | ⚠️ 只校验 summary 里的**字符串**；代码真的用它发送由 #17 的 `-> 127.0.0.1:21346` 日志旁证 |
| 13 | 197 | `summary -match 'LOOPBACK PROTOTYPE'` | **恒真** | ❌ 该字符串是 `main.rs:1524` 的**硬编码常量**，且 `notes` 块（`main.rs:1510-1530`）在 `if let Some(fw)` / `if let Some(p)` 两个条件块**之外**、无条件写入 summary —— 即只要 summary 非空就必含此串，与是否加 `--forward-to`、是否转发成功**完全无关**。它测的是"这份代码含免责声明"，不是"行为被限制在回环" |
| 14 | 205 | `forward-log has 3 forward lines` | 强 | ✅ |
| 15 | 206 | `forward-log has 3 peer-recv lines` | 强 | ✅ |
| 16 | 207 | `forward-log has 1 skip line` | 强 | ✅ |
| 17 | 208 | `never forwards a discovery port` | **可空集恒真** | ⚠️ `$fwdLines` 为空数组时 `-not ($empty -match …)` 为 `$true` → 恒真。**但**同轮 #14（Count==3）会先失败兜住，故实际不可被利用；且它只扫 `forward` 行不扫 `peer-recv` 行。另：若发现帧被误转发，`forward` 行会带 `dst=127.0.0.1:62905`，正则 `6290\d\|629[0-9]\d` 覆盖 62900–62999，**能捕获** |
| 18 | 209–211 | `peer-recv shows the 8B payload head 17320000`（`-ge 2`） | **弱** | ❌ 只验**前 4 字节**；`-ge 2` 允许 3 条中任 2 条命中（漏 1 条不报）；120 B 载荷的 112 字节完全未验。脚本手里明明有 `$p1/$p2/$p3` 原值（127–130 行）却未逐字节比对 |

### 5.2 关于"是否真的存在恒真断言"

**存在 1 项真恒真 + 1 项条件恒真：**

- **真恒真：#13**（`LOOPBACK PROTOTYPE` 硬编码字符串）。它的存在不危害证据，因为其余 17 项都测行为；但它占据了"17 项断言"里的一个名额，使"全项通过"的含金量被高估一档。**建议**：要么删掉，要么升级为对行为的检查（例如断言 `summary` 中 `target` 的 IP 属于 127.0.0.0/8、且 `listen port` 属于 127.0.0.1 且 ≠ 62056）。
- **条件恒真：#17**（空数组）。被 #14 兜住，实际不可利用。**建议**：改为 `@($fwdLines | Where-Object { $_ -match ':62(9\d\d)' }).Count -eq 0` 正着数，去掉 `-not` 的空集语义。

**其余 16 项无恒真问题**——都是"取值 → 与期望值比较"，且 `Grab`（脚本 168–172 行）在未命中时返回空串，空串 `-eq '3'` 为假，**不会**因为"没抓到"而误通过（这一点设计得对；对比之下若用 `-notmatch` 就会翻车）。

### 5.3 该断而未断的边界（D 节的实质性缺口）

| 缺口 | 现状 | 风险 | 建议 |
|------|------|------|------|
| **D-1 全字节内容未验** | 只验长度与前 4/8 字节 | "原样"这一核心命题只有代码路径保证 + 弱日志证据；若 `decode` 或 `hex4` 有截断/偏移 bug，本轮**不会**发现 | 两侧日志都记录 `payload_sha256=<hex>`（对本端收到的字节算），驱动断言 `sha256($p1/$p2/$p3)` 与之逐条相等。**这是最高优先级的断言升级** |
| **D-2 seq 维度对账缺失** | peer 侧日志无 seq（只有 n=1/2/3 序号） | 无法证明"帧→投递"是 1:1 映射；设计 §5.2 判据"seq 无缺口"只在 Agent 侧 summary 验证，未在对端侧验证 | CVLH2 的 seq 在 42 B 头里（`cvlh2.h` offset 6），转发的是**载荷**，对端看不到 seq。**用内容哈希替代 seq 做对账**：p1≠p2≠p3，哈希可区分帧 → "每个哈希恰好到达一次"即等价于"无重复、无丢失" |
| **D-3 发送方身份未绑定** | #9 只证"某回环临时端口送了 3 个载荷"；`peer-recv from=127.0.0.1:53458` 与转发套接字的关系**无断言** | 理论上第三方本机进程注入同长度载荷也能通过 | summary 增加 `forward sock local : <ip:port>` 行；断言 `peer-recv` 的 `from` 端口 == 该值 |
| **D-4 `--forward-listen 62056` 拒绝无负向用例** | 代码存在（`main.rs:944-948`），零覆盖 | 若日后重构丢失该 guard，测试不会报警 | 加一次 `civlink-agent --forward-listen 62056` 期望非零退出码 + stderr 含 `must not be 62056` |
| **D-5 `--port 62056` 无校验且无负向用例** | `main.rs:890` 裸 parse；`:984` 直接 bind | **D2 红线的实现层缺口**（默认路径安全，但违例路径可用） | 加 guard（见 M1）+ 负向用例 |
| **D-6 `--forward-to` 指向 62056 无拒绝** | `main.rs:935-938` 只 parse | 记录 §1 声称"不转发到 :62056"，但配置层可指定 | 加 `if port == DATAPATH_PORT { Err }` |
| **D-7 无 `ForwardState`/`ForwardListener` 单测** | `main.rs:1551` `mod tests` 共 13 个 `#[test]`，**0 个**覆盖 F3-A 类型 | `consider`/`ensure_mapping`/`drain`/拒 62056 全靠一个端到端脚本；改一行没人拦 | 至少 4 个单测（见 M7） |
| **D-8 无"发现帧标志但 dst==62056"用例** | 只有"dst==62905 且 flags 含 0x04"一种发现形态 | `is_discovery` 的 `\|\|` 两分支只测了右侧（准确说 seq3 同时满足两侧：flags 0x06 含 0x04，dst 也在区间内）→ **左侧 `flags & FLAG_DISCOVERY` 分支未被独立验证** | 加一帧 dst=62056 + flags=0x04，断言不被转发且计入 skipped |
| **D-9 oversized/rejected 帧进入转发路径无计数** | `main.rs:1224` 跳过 `FLAG_REJECTED_OVERSIZE\|FLAG_NO_PAYLOAD` 时**不计任何数** | 无观测性：这类帧既不计 `forwarded` 也不计 `no_mapping`，静默消失 | 加 `skipped_flags` 计数器 |
| **D-10 真正"失败路径"未被验** | `forward fail == 0` 通过只说明没出错；无"目标不可达时 `forward_fail` 会 +1"的正向验证 | "失败也计数"这一属性未被证 | 加一次目标指向关闭端口的用例（期望 fail≥1），但这属 F3-E 范畴，可延后 |

---

## 6. E. 缺陷与风险清单（按严重度）

> 无"高"级缺陷：未发现伪造证据、未发现越界宣称、未发现默认运行路径违反红线。以下按"中 / 低"排序。
> 编号 M = Medium（进 F3-B 前应修），L = Low（可进待办）。

### M1（中）`--port 62056` 无护栏——D2 红线在实现层未闭环

- **位置**：`civlink\agent\src\main.rs:890`（`--port` 仅 `v.parse()`）、`main.rs:984`（`bind_addr = 127.0.0.1:args.port` 直接 bind）
- **问题**：`--forward-listen 62056` 有显式拒绝（`main.rs:944-948`），但主监听端口 `--port` 没有。`civlink-agent --port 62056` 会被接受；若游戏未运行，`bind` 会成功，Agent 即占用数据面端口。设计 §5.3 / F2 裁定 D2 要求"Agent 不得与游戏共存绑定 62056"，这条约束目前只靠"用户不会这么传参"。
- **修复**：
  ```rust
  // main.rs, "--port" 分支
  args.port = v.parse().map_err(|_| format!("bad port: {v}"))?;
  if args.port == DATAPATH_PORT {
      return Err(format!(
          "--port must not be {DATAPATH_PORT}: the Agent never binds the game's data-plane port"
      ));
  }
  ```
  并补负向用例（见 D-5）。

### M2（中）`no_mapping` 语义与设计 §3.2 第 2 步不符，记录引用了未执行的条款

- **位置**：`main.rs:584-603`（`ensure_mapping` 恒返 `true`）、`main.rs:622`（返回值丢弃）、`main.rs:610`（`no_mapping` 实际在此递增）、记录 `docs\F3A-DIRECT-FORWARD-20261114.md:15`
- **问题**：设计 §3.2 第 2 步要求"数据面帧查表未命中 → 不转发并计数 no_mapping"，但实现是"首次流量即分配"，所以**数据面帧永不未命中**，该分支不可达。`no_mapping` 计的是"非数据面帧"。记录把这两件事写成"对应"。
- **修复（推荐低成本方案 b）**：
  1. `main.rs:549` 注释与 `:1488` 文案保留（已写 "dst port != 62056"，是诚实的）；
  2. 记录第 15 行的"对应设计 §3.2 第 2 步"改为"对应设计 §4.3 首次流量分配规则；§3.2 第 2 步的'未命中不转发'路径本步**未实现**，留 F3-B/映射表替换时处理"；
  3. 记录 §3"不证明"追加一条：**"映射未命中路径"未实现、未验证**。
- **备选（成本高）**：让 `ensure_mapping` 返回 `bool` 且 `consider` 在 `false` 时走 `no_mapping`，但需先定义"谁来建表"，会触及映射生命周期语义，不适合在 F3-A 补。

### M3（中）"原样载荷"仅有长度 + 前 8 字节证据

- **位置**：`main.rs:638`（`hex4(&frame.payload[..len.min(8)])`）、`main.rs:701`（peer 侧 `hex4(&buf[..len.min(8)])`）、`run-f3a-forward-selftest.ps1:209-211`
- **问题**：见 D-1。核心命题（§4.2 "100% 原样"）的证据强度低于命题强度；120 B 载荷的 112 字节无任何记录。
- **修复**：
  1. `main.rs`：对 `frame.payload` 与 peer 收到的 `buf[..len]` 各算 `sha256`（可用 `sha2` crate；若不想加依赖，用 `crc32fast` 或自写 FNV-1a-64，但**哈希位数要够**，建议 ≥64 bit 且日志给全 hex），日志加 `sha=<hex>`；
  2. 驱动：算 `$p1/$p2/$p3` 的同一哈希，逐条断言 `forward sha == peer sha == 期望`；
  3. 保留 `payload=<前8B>` 供人工目视。

### M4（中）对端"收到"的发送方身份未绑定到转发套接字

- **位置**：`main.rs:1493-1509`（peer 段无"本端转发套接字地址"）、`main.rs:686-709`（`drain` 只记 `from`）
- **问题**：`peer-recv from=127.0.0.1:53458` 与转发套接字的关系无断言。证据只能说明"某个回环端口按序送来 3 个长度正确的载荷"。
- **修复**：summary 的 `direct forward prototype (F3-A)` 段加一行 `forward sock : <local_addr>`；驱动断言 peer 的 `from` 端口与该值相等。

### M5（中）F3-A 相关类型零单测

- **位置**：`main.rs:1551` `mod tests`（13 个 `#[test]`，无一个触及 `ForwardState`/`ForwardListener`）
- **问题**：`consider`/`ensure_mapping`/`drain`/`--forward-listen` 拒绝全部只由端到端脚本覆盖；重构风险直接落到唯一一条证据链上。
- **修复（4 个即可）**：
  1. `consider` 对 dst=62056 帧：`forwarded==1`，目标收到的字节等于 `frame.payload`；
  2. `consider` 对 dst=50999 帧：`no_mapping==1`、`forwarded==0`；
  3. `consider` 对 dst=62905 帧（直接调用 `consider`，绕过调用点）：`no_mapping==1`（证明纵深防御成立）；
  4. `ForwardListener::new(62056)` 返回 `Err`；`ForwardListener::drain` 收到 1 个 1600 B 载荷时 `bytes` 计 1600 而非 2048（配合 L1 或至少断言截断行为有明确记录）。

### L1（低）`ForwardListener` 2048 B 缓冲会静默截断长载荷并少计字节

- **位置**：`main.rs:1130`（`let mut pbuf = [0u8; 2048]`）、`main.rs:691`（`stats.bytes += len`）、`main.rs:700`（`len` 写日志）
- **问题**：UDP 上限 65507 > 2048；截断后 `len` 与 `bytes` 都是坏值，且无告警。当前被 `MAX_PAYLOAD=1280` 挡住（最大帧 1322 B），不触发。
- **修复**：`let mut pbuf = [0u8; 65535];`（或 `FRAME_HDR + MAX_PAYLOAD`）并把上限来源写成注释；截断时单独计数 `truncated`。

### L2（低）`ForwardState` 转发套接字绑通配地址

- **位置**：`main.rs:574` `UdpSocket::bind("0.0.0.0:0")`
- **问题**：①与"本机回环原型"标签不完全一致；②为多机阶段留无意可达面。不违反 D2 字面。
- **修复**：`UdpSocket::bind("127.0.0.1:0")`。若担心 F3-B 需要非回环目标，改为"按 `target.is_loopback()` 选择绑定地址"。

### L3（低）`stop_seen` 的 break 早于 drain，尾部载荷可能丢

- **位置**：`main.rs:1123-1132`
- **修复**：`break` 前补一次 `pl.drain(...)`；或在 break 前把 `stop_seen` 置位后再跑一轮。

### L4（低）oversized / no-payload 帧进入转发路径时无任何计数

- **位置**：`main.rs:1224`（`if frame.flags & (FLAG_REJECTED_OVERSIZE | FLAG_NO_PAYLOAD) == 0` 的 else 分支为空）
- **修复**：`ForwardStats` 加 `skipped_flags: u64`，summary 加一行。

### L5（低）`--forward-to` 接受 62056 / 发现段 / 非回环地址

- **位置**：`main.rs:935-938`
- **问题**：记录 §1 第 13 行写"不转发到 :62056"，但配置层可指定；写"本机回环"，但接受任意 `SocketAddr`。
- **修复**：拒绝 `DATAPATH_PORT`（必做）；F3 阶段可选 `if !addr.ip().is_loopback() { Err("F3 prototype is loopback-only") }`（若为 F3-B 预留则加 `--allow-non-loopback` 显式开关）。

### L6（低）完成记录 §4 文件身份表覆盖不全

- **位置**：`docs\F3A-DIRECT-FORWARD-20261114.md:54-64`（9 行）vs 证据目录实有 9 文件（表内只含 5 个证据文件）
- **修复**：补 `exit.txt`、`agent-console.txt`、`agent-stderr.txt` 三行哈希；`stop` 可注明"控制产物（0 B），不计入身份表"。

### L7（低）3 次失败运行未披露

- **位置**：记录全文；`M0A\captures\F3A-forward-selftest-20261114-141849 / -141904 / -141929`
- **修复**：§5 末尾加一段披露（见 §2.4 的建议原文）。

### L8（低）"断言 17 项 / 17/17 通过"与实际 18 处 `Check` 不符

- **位置**：记录 `:37`（"断言 17 项"）、`:41`（"17/17 断言通过"）；脚本实测 18 处 `Check`
- **说明**：记录第 37 行把 `forward-log 3 条 forward + 3 条 peer-recv + 1 条 skip` 写成一个条目，逐项数只有 **16** 条，宣称 17 条，实际 18 条——三个数字互不相同。
- **修复**：改为"断言 18 项"，并把 205/206/207 拆成三条列。

### L9（低）记录把 `listen port` 断言写弱了

- **位置**：记录 `:37` 写 "`listen port!=62056`"；脚本 `:195` 实际是 `$listenPort -eq "$peerPort"`（即 ==21346）
- **说明**：代码断言比文档描述更强，属文档滞后。改文档即可。

### L10（低）`listen window: … for 2.3 s` 与 `--listen-seconds 30` 的差异未解释

- **位置**：`summary.txt:3`；脚本 `:83`（`--listen-seconds 30`）、`:140-141`（1.5 s 后写 stop）
- **说明**：2.3 s 是"实际存活时长"（stop 文件提前结束），不是缺陷，但读者会疑惑"为什么设 30 s 只跑了 2.3 s"。
- **修复**：记录 §2 加一句"`--listen-seconds 30` 只是上界，脚本 1.5 s 后写 stop 提前干净退出，故 summary 显示 2.3 s"。

### L11（低）`forward FAILED` 日志缺目标地址

- **位置**：`main.rs:646-652`
- **修复**：加 `-> {}`，便于 F3-E 故障注入时定位是哪个目标失败。

### L12（低）`is_discovery` 判定在 `run()` 里重复实现两遍

- **位置**：`main.rs:1206-1217`（F2 datapath 分支）与 `main.rs:1225-1228`（F3-A 转发分支）
- **风险**：两处将来若改一处漏一处，会出现"F2 认为是发现帧、F3-A 认为是数据面帧"的错位。
- **修复**：抽 `fn is_discovery_frame(frame: &Frame) -> bool` 并加单测。

### L13（低）§5.2 的回包策略未被显式声明选哪一条

- **位置**：`docs\F3A-DIRECT-FORWARD-20261114.md` 全文（未出现"回包策略"字样）；`datapath-log.txt` 第 2 行（20 B `reply sent`）
- **问题**：设计 §5.2 把"回包策略二选一（≤1 个 20 B **或** 不回包）"列为 F3-A 的**显式判据项**。本步实际行为是"F3-A 路径不回包"（`main.rs:1223-1235` 只调 `consider`，无任何回写），`datapath-log` 里唯一的 20 B 是 F2 D4 遗留（`main.rs:1441-1470` 段，`summary.txt:24-27`）。但完成记录**没有一句话说明"我们选了策略②：不回包"**，读者会看到一条 20 B 回包日志而无法判断它属于哪一阶段、是否违反 F3-A 的回包约束。
- **修复**：记录 §3 加一句："F3-A 采用设计 §5.2 的策略②（**不回包**）；`datapath-log.txt` 中的 1 条 20 B `reply sent` 属 F2 的 D4 本地探测，与本步无关，未新增任何回包。" 并在 §1 能力表补一行"回包：无"。

---

## 7. F. 裁定建议

### 7.1 结论：**有条件通过（CONDITIONAL PASS）**

**通过的理由（可以承认的部分）**

1. **证据是真的、且自洽**：9/9 哈希与记录一致；summary 与三份逐行日志在条数（5/3/3/1）、字节（354/144/136/136）、端口（62056×3、62905×1、50999×1）、时间戳上完全咬合，未发现任何算术矛盾或拼装痕迹（§2.1–§2.3）。
2. **机制符合设计**：`dst==62056` 单目标转发、发现帧在 `consider()` 之前被排除、单次 `send_to` 不重传、载荷零改写、映射键形状与 crate 一致、`--forward-listen` 拒绝 62056、无 `SO_REUSEADDR`、默认路径不绑 62056——八项核心约束全部成立（§3.1）。
3. **未越界**：未宣称联机、未宣称零丢包、未暗示 H2/R1 已测；"不证明"清单逐项对应设计 §5.1；边界声明写进了产物本身（`summary.txt` notes）而不只是文档（§4.1）。
4. **红线未被触碰**：无游戏进程内注入、无 wire format / 密钥冻结、无真实双机主张。

**不能直接判"通过"的理由（有条件的原因）**

1. 核心命题"载荷原样"的证据链只有**长度 + 前 8 字节**，120 B 用例的 112 字节无证据（M3）。
2. D2 红线「Agent 不得绑定 62056」在实现层**只堵了一半**（`--forward-listen` 堵了，`--port` 没堵），且无负向用例（M1）。
3. 记录对 `no_mapping` 的引用了设计里**从未被执行**的条款，构成"规则已被验证"的误导（M2 / C-3）。
4. "对端"是同进程自环，"对端 Agent"一词会让读者误以为是两个 Agent（C-2）。
5. F3-A 类型零单测，唯一证据链靠一条端到端脚本承载（M5）。

上述 5 条**都不表明本步造假或无效**，而是表明：**当前证据支持的命题窄于记录声称的命题**。因此判"有条件通过"，条件是补齐下列事项。

### 7.2 进入 F3-B 前必须补齐（7 项，按优先级）

| 序 | 事项 | 对应缺陷 | 验收方式 |
|---:|------|---------|---------|
| 1 | **载荷哈希对账**：`forward` 与 `peer-recv` 行各加 `sha=<hex>`（对本端实际字节计算）；驱动对 `$p1/$p2/$p3` 逐条断言三方一致，替换现在只验前 4 字节的 #18 | M3 / D-1 / D-2 | 新证据目录中 3 条载荷哈希全部匹配，含 120 B 的**全部 120 字节** |
| 2 | **`--port 62056` 护栏** + 负向用例（`--port 62056` / `--forward-listen 62056` / `--forward-to …:62056` 三者均须非零退出并给出明确 stderr） | M1 / L5 / D-4 / D-5 / D-6 | 三个负向用例全部 PASS，且落 `exit.txt` 与 stderr 证据 |
| 3 | **`no_mapping` 语义与文案对齐**：改记录 §1 的条款引用为 §4.3；在 §3"不证明"补"映射未命中路径未实现/未验证"；或改名计数器 | M2 / C-3 | 记录文本改毕，且与 `main.rs:549`、`:1488` 的注释一致 |
| 4 | **发送方身份绑定**：summary 增 `forward sock : <local>`，断言 peer `from` 端口等于它 | M4 / D-3 | 新证据中 peer-recv 的 `from` 与 summary 的 `forward sock` 一致 |
| 5 | **F3-A 单测 4 个**：`consider`(62056 转发 / 50999 skip / 62905 skip)、`ForwardListener::new(62056)` 返回 Err | M5 / D-7 | `cargo test` 全绿，测试名可读 |
| 6 | **记录表述收紧 3 处**：①"同样的载荷"→"长度与前 8 字节一致，未做全字节比对"；②补"单进程双角色自环，验证线路非双 Agent 通信"；③`17 项`→`18 项`并拆分 205/206/207 | C-1 / C-2 / L8 / L9 | 记录文本改毕 |
| 7 | **过程与文件身份补全**：披露 3 次失败运行；§4 表补 `exit.txt`/`agent-console.txt`/`agent-stderr.txt`；说明 `2.3 s` 的由来；声明 F3-A 采用 §5.2 的"不回包"策略（20 B 属 F2 D4） | L6 / L7 / L10 / L13 | 记录文本改毕 |

### 7.3 可进待办、不阻塞 F3-B（建议排入 F3-B/F3-C 同批）

- L1 缓冲 65535 + 截断计数
- L2 转发套接字改 `127.0.0.1:0`
- L3 break 前补 drain
- L4 `skipped_flags` 计数
- L11 `forward FAILED` 加目标
- L12 抽 `is_discovery_frame()` 并加单测
- D-8 补"flags 含 DISCOVERY 但 dst==62056"用例
- D-10 "目标不可达 → `forward_fail+1`"正向失败用例（归 F3-E）

### 7.4 给裁定审计的一句话

> F3-A 的**机制**成立、**证据**真实、**边界**基本守住；但"原样载荷"与"不重传"两个判据目前的证据强度只到"长度 + 前 8 字节 + 条数"，`--port 62056` 护栏缺失使 D2 红线在实现层留了一个可用缺口。建议裁定为**有条件通过**，把 §7.2 的 7 项作为 F3-B 的**开工前置**（其中第 1、2 项为硬性，其余为文案与覆盖度补齐）。

---

## 附录 A：本次审计使用的只读命令（可复现）

```powershell
# 哈希（对 9 个证据文件与 4 个源码/二进制，逐项）
Get-FileHash -Algorithm SHA256 -Path <file> | Format-List
Get-Item <file> | Select-Object Length

# 断言计数
Select-String -Path .\civlink\run-f3a-forward-selftest.ps1 -Pattern '^\s*Check ' | Measure-Object

# 62056 相关全部代码位置
Select-String -Path .\civlink\agent\src\main.rs -Pattern 'DATAPATH_PORT'

# 是否存在 SO_REUSEADDR
Select-String -Path .\civlink\agent\src\main.rs -Pattern 'reuse|REUSE|set_broadcast|linger'

# 全部 bind 调用点
Select-String -Path .\civlink\agent\src\main.rs -Pattern 'UdpSocket::bind'

# 环境核对（证明 bind-check 的"0"不代表"有人绑过"）
Get-NetUDPEndpoint -LocalPort 62056 -ErrorAction SilentlyContinue
```

## 附录 B：本报告未覆盖的内容（供后续审计接力）

1. E1–E7 七条前置条件的**逐条**落实（仓库内无定义文本，无法枚举——需裁定审计提供原始文本）。
2. `civlink_hook.dll` 侧的出向抓取正确性（F2 已有证据，本步默认其可靠；`summary.txt:48-50` 的 Hook 对账说明本轮未做，因为没进游戏）。
3. `civlink-agent.exe` 与 `main.rs` 的构建对应关系（需 reproducible build 或构建留痕）。
4. F3-B（Relay 多 Agent）、F3-C（退避语义）、F3-D（忙轮询压力）、F3-E（故障注入）——均未开始，不在本次范围。
