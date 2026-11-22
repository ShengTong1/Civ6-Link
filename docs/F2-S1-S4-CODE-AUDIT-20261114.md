# F2 S1–S4 源码与证据审计（2026-11-14）

## 审计范围与结论

- 复核对象：当前工作树中的 CivLink Agent、Hook DLL、Fake-IP crate、自检脚本及已归档 F2 机械自检输出。
- 依据：`docs/F2-DATAPATH-REVIEW-20261114.md`、修订设计 `docs/F2-DATAPATH-SIMULATED-PEER-20261114.md`、技术规范 v2.1 §4.2–§4.4、§5。
- 本轮只读审计；**未改源码，未运行测试或网络实验**。
- 工作目录不是 Git 仓库，无法取得可靠的 `git diff`。以下结论针对磁盘当前版本，不能替代缺失的逐文件变更补丁。

**裁定：当前实现不应进入 S5。** S1/S3 的基本原型和 S2 的若干透传路径有机械证据，但 Q2 的关键观测数据没有被实现；D4 探测可被无关 UDP 调用触发；`--bind-ip` 的本机地址限制没有在 Agent 内执行；Q5 负载与失联路径也没有被当前证据覆盖。22/22 是脚本断言数的执行端报告，不等于 S1–S4 全部技术问题闭合。

## 证据核对

下列二进制和 F2 机械证据哈希与交付摘要给出的前缀相符：

| 文件 | SHA-256 | 大小 |
|---|---|---:|
| `civlink_hook.dll` | `9424FC25FB45841FC6A31A0C9CD747067005D3FA32A06A18CD150B0C9CEBC10F` | 119,808 B |
| `civlink_ctl.exe` | `23923DFBAAB310F2BDAA1E1117110B92A74290E2C87396E5CB65EE0E4FEFEA30` | 173,056 B |
| `hook_selftest.exe` | `FE88D38E9D25293E0C2567907FE66E471CB8E0B5E924236608158D5630C2F477` | 148,992 B |
| F2 mechanical `summary.txt` | `C40816A744C8CF1D35AB053BF534EEA35B07E6DAF0896031F897D6B61588BB83` | 2,158 B |
| Hook selftest console | `E0A1FD99CA1466766920B437AF25461B6B743F74BE29AA0B2EF8D716F5787483` | 3,522 B |
| F2 mechanical `frame-log.txt` | `ACBF63659B4FD9F0C599754902983B854B07576C1855F395AE586926CE900E41` | 1,066 B |
| F2 mechanical `datapath-log.txt` | `1E65E067D005DABEAB5BD488E2E028971EEAA2B84392B20F324E23FB932288AD` | 460 B |

证据目录在工作区根目录 `M0A/captures/`，不是 `CivLink-M0A-audit/M0A/captures/`。机械目录包含 Agent summary、Hook console、frame-log 和 datapath-log；**未见保存 22 项逐项输出的 `verify-report.txt` 或机械驱动完整控制台**。所以可复核 Hook 自检输出和 Agent 对账结果，但 22/22 的逐项运行结果仍属执行端报告。

机械 summary 证实：7 个 CVLH2 datagram（6 processed、1 rejected）、序号无缺口；3 个非发现观测帧，其中 2 个目标端口 62056；本机回环样例成功发送一个 20 B probe。它只覆盖小样本、回环和指定输入，不能证明真实 Civ6 的调用顺序、非阻塞设置、负载上限或失联行为。

## 阻断项（P1）

### P1-1：Hook 现有数据不足以回答 Q2

文件：[hook.cpp](../civlink/hook/hook.cpp:403)、[civlink_hook.h](../civlink/common/civlink_hook.h:47)

- `Hook_bind` 只缓存成功 bind 的端口（`hook.cpp:416–424`）；没有保留 bind 的 IP，因此不能判断目标是不是 `0.0.0.0:62056`。
- Hook counters 是累计计数，没有每次调用的 socket ID、QPC 时间戳或单调事件序号；所以不能证明同一 socket 上 `bind → WSARecvFrom → WSASendTo` 的顺序。
- 没有 `ioctlsocket(FIONBIO)` 或 `WSAEventSelect` 观测，也没有记录 `recvfrom`/`WSARecvFrom` 的完整返回类别和错误码。`WSA_IO_PENDING` 计数不能单独证明 socket 的非阻塞配置。

因此，S5 即使运行成功，当前输出也无法支撑设计 §1.1 Q2。应增加仅记录的结构化事件（同一 socket 身份、generation、QPC/序号、bind 地址/端口、调用结果），或把无法观测的子项明确改为“未验证”；不得用汇总计数推断顺序或 wildcard bind。

### P1-2：`--bind-ip` 没有被程序验证为本机地址

文件：[main.rs](../civlink/agent/src/main.rs:436)、[main.rs](../civlink/agent/src/main.rs:447)、[main.rs](../civlink/agent/src/main.rs:495)

`DatapathState::new` 只解析 IPv4 文本并拒绝 `0.0.0.0`/广播地址，注释把“当前主机本地地址”校验交给调用者；它没有枚举本机接口。收到源地址等于参数的 CVLH2 帧后，代码向 `bind_ip:src_port` 发送数据报（`main.rs:506–507`）。因此任意可解析的非本机地址都能作为参数通过构造阶段，代码本身并不保证 D4 的“仅本机”。回环 self-test 只证明 `127.0.0.1` 样例。

修复方式可由 Agent 内部验证，也可由真实运行前的受控启动器验证并归档地址/接口只读输出；如果依赖启动器，S5 必须使用该启动器并把“本机地址核验 PASS”作为硬门槛。不能仅凭 `--bind-ip` 参数名或执行者手工选择认定安全。

### P1-3：D4 回包与目标数据面没有绑定，可能响应无关 UDP

文件：[main.rs](../civlink/agent/src/main.rs:460)、[main.rs](../civlink/agent/src/main.rs:486)、[main.rs](../civlink/agent/src/main.rs:501)

`DatapathState::consider` 会对每个被 Agent 分类为“非发现”的出向帧执行同一套回包判断；它只统计 `dst_port == 62056`，没有要求目标端口为 62056 才允许发送 probe。主接收循环也把所有非发现帧交给该函数（`main.rs:959–973`）。因此本机地址上的其他 UDP 流量可能先消耗唯一回包预算，或者把 20 B 任意数据投递到 Civ6 的非数据面 socket。现有机械样例恰好让前两个来源地址不匹配 `127.0.0.1`，没有覆盖“本机来源 + 非 62056 目标”的反例。

这不证明已经发生远端发送；它是本机错误目标和 S5 结果污染风险。进入 S5 前应把回包条件限制到明确的 62056 测试帧，并增加本机非 62056 目标绝不回包的负向断言。预算应按**尝试次数**锁定，而不是只在 `send_to` 成功后增加：当前 `reply_sent` 只在成功分支递增（`main.rs:507–510`），失败时后续帧会再次尝试，与“无重试”承诺不完全一致。

### P1-4：Hook 将所有非发现发送同步转发，且不校验地址族

文件：[hook.cpp](../civlink/hook/hook.cpp:335)、[hook.cpp](../civlink/hook/hook.cpp:341)、[hook.cpp](../civlink/hook/hook.cpp:368)、[hook.cpp](../civlink/hook/hook.cpp:376)

F2 对任何非发现 `sendto`/`WSASendTo` 都同步调用 `ForwardFrame`，而非仅限数据面相关 socket/62056。`ForwardFrame` 把目的地址直接当 `sockaddr_in` 编码，入口只检查长度，没有检查 `sa_family == AF_INET`。IPv6 地址长度也满足当前长度门槛，可能被错读成 IPv4 并写入 CVLH2；其他无关 UDP 也会增加 Hook 热路径的同步 IPC 次数。

建议按 AF_INET 严格过滤；仅观测目标端口 62056 或已确认绑定到 62056 的 socket，并把不支持的地址族/其他 UDP 单独计数。否则结果混有非游戏数据，且测量本身扩大了游戏发送路径的同步工作。

### P1-5：WSASendTo 的包形态观测不完整

文件：[hook.cpp](../civlink/hook/hook.cpp:366)、[hook.cpp](../civlink/hook/hook.cpp:369)、[hook.cpp](../civlink/hook/hook.cpp:372)、[hook.cpp](../civlink/hook/hook.cpp:376)

- overlapped `WSASendTo` 不转发观测帧；但 `rawWsasendtoCalls` 在进入条件前就递增。因此“raw 调用数”包含了未观察的异步发送，而 Agent 只看到其中部分。
- scatter/gather 发送只把 `bufs[0]` 交给 `ForwardFrame`，后续缓冲区未拼接；`scatterGather` 只计数，frame-log 仍把第一段长度显示成该包的完整长度。
- 观察帧在真实 `sendto`/`WSASendTo` 调用之前发出。若原游戏调用失败，Agent 仍会记下一条“发送观察帧”；当前 CVLH2 frame 没有原调用结果字段。

所以 Q1 可有限回答“detour 看到了调用”，但 Q3 的真实发送长度/首包形态不能只用这些帧宣称已验证。应区分“调用尝试”与“原 API 成功”，把 overlapped/scatter 标为未完整观察，或用不读取异步缓冲区的安全方式仅记录元数据。

### P1-6：Q5 的失联/负载/延迟验证未完成

文件：[hook.cpp](../civlink/hook/hook.cpp:276)、[hook.cpp](../civlink/hook/hook.cpp:306)、[run-f2-mechanical-selftest.ps1](../civlink/run-f2-mechanical-selftest.ps1:1)

`ForwardFrame` 在调用游戏原始发送函数之前同步执行本机 UDP `sendto`。当前机械证据只有个位数帧，没有 1000 帧/秒负载、Agent 未运行时的实测、Hook 每帧 IPC 延迟分布或游戏发送延迟对照。脚本要求 Agent 先成功启动，不包含失联场景。故不能说同步发送的负载与失败行为已验证，也不能由 `sendto` 返回成功推出 Agent 已收。

这与 F2 v0.2 §3.5/§4 S4 的负载缺口报告要求不符。至少需单独补无游戏机械压力/Agent 缺席实验与 QPC 延迟统计；否则将 Q5 标“未验证”，并把 S4 结论收窄为“小样本机械连通性通过”。

## 需要修正的测试/工具问题（P2）

### P2-1：Fake-IP 变异脚本可能假 PASS，且会改变源码 BOM

文件：[run-fakeip-selftest.ps1](../civlink/run-fakeip-selftest.ps1:44)、[run-fakeip-selftest.ps1](../civlink/run-fakeip-selftest.ps1:59)、[run-fakeip-selftest.ps1](../civlink/run-fakeip-selftest.ps1:77)

- 某个变异文本匹配不到时，脚本打印 `SKIPPED` 后 `continue`，没有把 `$allCaught` 设为 false；最终仍可能报告所有 mutation 都捕获。
- 源码恢复不在 `try/finally` 中；Ctrl+C、cargo 异常或进程中止时可能把变异内容留在工作树。
- 实际 `result.txt` 记录的源码 hash `89C7041B…` 与当前文件 hash `4B31484E…` 不同。当前 `lib.rs` 有 UTF-8 BOM；去掉前三个 BOM 字节后 hash 恰好等于记录的 `89C7041B…`。这证实脚本在“恢复”时通过 `[Text.Encoding]::UTF8` 重写源码并添加了 BOM。当前测试逻辑可能有效，但源码身份已被测试脚本改变。

应在 `finally` 中按原始字节恢复；跳过任何 mutation 必须令整次运行失败；恢复后逐字节/hash 与原文件一致再输出 PASS。

### P2-2：Fake-IP 反向端口参数字节序命名不一致

文件：[lib.rs](../civlink/fakeip/src/lib.rs:276)、[lib.rs](../civlink/fakeip/src/lib.rs:329)

reverse map 写入键使用 `peer.addr.port()`（Rust `SocketAddr` 的主机序端口），但 `lookup_reverse` 参数名为 `peer_src_port_be`，测试传入 `53787` 主机序数值。调用者若把 CVLH2 中原始 `sin_port` 数值直接传入，会反向查找失败。统一参数为主机序并改名，或在边界显式转换；补一个字节序反例测试。

### P2-3：反向键不支持同 Peer/会话/源端口对应多个本地 socket

文件：[lib.rs](../civlink/fakeip/src/lib.rs:142)、[lib.rs](../civlink/fakeip/src/lib.rs:276)

正向键含 `logical_socket_id`，反向键只有 `(peer_id, tunnel_session_id, peer_source_port)`。同一远端 source port 若同时对应两个本地游戏 socket，第二条分配会 `ReverseConflict`。冲突是显式的，不是静默覆盖；但现有“同 peer 多 socket”测试用了不同远端 source port，没有覆盖该边界。需把它列为已知限制，或定义可消歧的入向上下文后再声称支持多 socket。

### P2-4：映射错误语义和重复代码

文件：[lib.rs](../civlink/civlink/fakeip/src/lib.rs:343)、[lib.rs](../civlink/civlink/fakeip/src/lib.rs:351)

`set_state` 找不到映射时返回 `TableError::KeyExists(key)`，错误方向相反，会误导后续诊断；应新增 `MappingNotFound`。`release_socket`、`end_session`、`reap_expired` 三处重复正反向删除和归还池逻辑，后续修改容易只改一处；可以抽一个内部删除 helper。`Mutex::lock().unwrap()` 在锁中毒时会 panic，可作为原型限制说明或返回明确错误。

## 计数与冗余项

- `channelDown` 与 `cvlh2Fail` 在当前代码中每次失败同时递增，数值完全重复（`hook.cpp:315–316`）；而一次 UDP send 失败也不能确证 Agent 进程不在。移除重复计数，或将其定义为真实健康探测状态。
- `SockSlot.gen` 被设为常量 1，后续帧编码也硬编码 generation=1（`hook.cpp:140–142`、`hook.cpp:289–290`）。当前逻辑 socket ID 单调递增时此字段冗余；若要依赖 generation 隔离，应由 slot 实际维护并编码。
- `rawWsasendtoCalls` 注释称“non-overlapped”，实现却在筛选 `!ov` 前对所有调用递增（`civlink_hook.h:49`、`hook.cpp:365–369`）。更名/拆分成 `calls_total` 与 `payload_observed`，避免报表把调用数误当成观测数。
- Agent datapath log 按设计应记录 head 16 B，实际只写前 8 B（`main.rs:467–482`）；若这是隐私缩减，应同步修订设计和报告，避免称符合 head16 计划。
- 自检中的“Agent never binds 62056”检查只匹配 summary 里的固定说明文字（`run-f2-mechanical-selftest.ps1` 中对应 Check），不检查 Agent PID 实际拥有的 UDP endpoint。源码静态检查可说明当前实现没有 `bind(:62056)`，但该断言不能作为运行时证明。

## 最终状态与执行建议

1. **暂不启动 Civ6，也暂不执行 S5 点击加入。** 先修 P1-1 到 P1-6；当前 S5 运行会产生不可充分解释的观测，且 D4 probe 可能响应非 62056 流量。
2. P1 修复后，重建 Hook/Agent/selftest，归档完整的逐项 `verify-report.txt`、命令、退出码和二进制哈希；不能只保留 summary。
3. 重跑负向测试：本机来源但目标不是 62056 不回包；非法/非本机 bind-ip 启动失败；WSASendTo scatter/overlapped 被明确标为未观测；Agent 不在和高负载场景分别计数，不把发送成功记作 Agent 收到。
4. S5 仍只在一次手动点击的既有边界内执行；若本机地址/接口需要确认，可以由负责人从中立目录运行只读核验并回传，DSH 不应通过反复改代码绕过环境问题。

Gate A 未批准；正式 M0-B/Gate B 仍冻结。本报告不移动项目 Gate。
