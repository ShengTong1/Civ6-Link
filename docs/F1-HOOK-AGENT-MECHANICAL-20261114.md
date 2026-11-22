# F1 机械证据：Hook + Agent 本机发现链路（2026-11-14）

## 0 一句话结论

F1 的**机械可验证部分已完成**：`civlink_hook.dll` 在真实进程内挂住 `sendto` / `WSASendTo` /
`closesocket` 三个 API，**原调用返回值与最后一次错误原样透传**（不吞包、不改参数），
把命中发现端口的载荷按 CVLH2 帧经 `127.0.0.1:34718` 送到独立 Agent，
Hook 侧计数与 Agent 侧计数**逐项闭合**。

**这还不是"真实客户端已验证"**：本节所有数字来自自检程序（`hook_selftest.exe`）构造的调用，
不是文明6 客户端。真实客户端的注入观测见 §7（以实际执行情况为准）。

## 1 交付物与身份

| 文件 | 字节 | SHA256 |
|---|---|---|
| `civlink\civlink_hook.dll` | 118 272 | `71C240377449CF0AB14BE64C4BCD0E4D8CCAC024B629B285CCED47585CFED41D` |
| `civlink\civlink_ctl.exe` | 172 032 | `64C39027A14590FE6CBEBCCE026B1D5FB121C81181462639F22E1DF9E2499CBA` |
| `civlink\civlink-agent.exe` | 296 960 | `0EA74B4D3A7DB52E9B7A46F1A70DAD86B352A3D392C9ACF5584634EE5B4C0A9E` |
| `civlink\hook_selftest.exe` | 145 408 | `24BC12982B39B848A47BBB14BC799A912054CF91E9AC037FB8082ED463B861EB` |

源码（`civlink\` 下，均无外部依赖）：

| 文件 | 字节 | SHA256 |
|---|---|---|
| `common\cvlh2.h` | 7 421 | `D41D0EFB1186361F1596C9009E0B4AE940117EEE57F8C692F34136C18D0DEE34` |
| `common\civlink_hook.h` | 3 289 | `6292411C30C2555FA416412470E40284681D569104AF0EEFB8E7CE53C53E1D75` |
| `hook\hook.cpp` | 16 938 | `483D4F6EAE3683B30C575BAC165BB2E5EBE90D0E4E41C7E708180186C8590A7C` |
| `ctl\civlink_ctl.cpp` | 20 325 | `F054EF621816AB8EC20D0E61DB0892AC3A1EF33C68CA8A36B943118A974BF626` |
| `selftest\hook_selftest.cpp` | 7 269 | `FB2A605DC478F8494AED9F4AF23579E3B7F87FE83F01F125565AA4A6BB432BE5` |
| `agent\src\main.rs` | 28 305 | `28EB194871CE5E5CB2852356AC43A796EFB8D48E7113FC5F905D0A20EB4CC0D5` |
| `agent\Cargo.toml` | 448 | `59D9BA97B14DE531A508807307E80123CDCBCE10E1EE0AD1BFB2C88E1743D718` |
| `build-msvc.cmd` | 3 741 | `BA6E5330DC2F3E8718D0D950EF5149BD7922DE9CF9AE475D03EDBC3E8A56093D` |
| `run-f1-selftest.ps1` | 6 157 | `401AB04FFEF4700454EA9DA691CB750C304D7614CC3412652AD20C69CF3A17F3` |
| `run-f1-live.ps1` | 9 081 | `A90CB029265D1E01A10C59EB1ED22B3C1CB2B03B4977F2227A8A9FC7C9B8B553` |

构建：`build-msvc.cmd`（`/MT` 静态 CRT，MinHook v1.3.4 pin，x64 only）。
Agent：`cargo +1.75.0 build --release --offline`，零外部依赖。

## 2 本机 IPC 帧（CVLH2，42 字节头 + 载荷）

| 偏移 | 宽度 | 字段 |
|---|---|---|
| 0 | 4 | magic `'C','V','L','H'` |
| 4 | 1 | version = 2 |
| 5 | 1 | dir（0 = hook→agent，1 = agent→hook） |
| 6 | 4 | seq（u32 LE；回环 UDP 传输必须带序号才能检测缺口） |
| 10 | 8 | session_id（u64 LE） |
| 18 | 4 | logical_socket_id（**不用 SOCKET 句柄值**，句柄会被复用） |
| 22 | 4 | socket_generation（同一逻辑 socket 复用时 +1） |
| 26 | 1 | address family = 2 |
| 27 | 4 | src ipv4（`sin_addr` 原始网络序字节） |
| 31 | 2 | src port（`sin_port` 原样，大端） |
| 33 | 4 | dst ipv4 |
| 37 | 2 | dst port |
| 39 | 1 | flags |
| 40 | 2 | payload_len（u16 LE，上限 1280） |
| 42 | n | payload |

flags 位：`0x01 VIA_WSASENDTO`、`0x02 LIMITED_BCAST`、`0x04 DISCOVERY`、
`0x08 REJECTED_OVERSIZE`、`0x10 NO_PAYLOAD`。

**超长载荷不静默截断**：`cvlh_encode` 返回 0，Hook 改发一条带
`REJECTED_OVERSIZE|NO_PAYLOAD` 的空载荷帧通知 Agent（计入 `sentNotify` 与 `rejectOversize`），
Agent 侧计入 `rejected` 而不是 `processed`，两侧可对账。

## 3 Hook 侧行为约定

- 三个 detour 的**第一行**都是 `g_inFlight.fetch_add(1, relaxed)`，出口对称 `fetch_sub`。
- 递归保护：`thread_local g_tlsInHook`，命中即 `fetch_sub` 后直接透传原函数。
- **不吞包**：观测完成后一律 `return Real_xxx(原参数)`；返回值、`WSAGetLastError`
  均由真实实现产生，测试逐项断言"返回值与原值一致"。
- 只对"目标为 `INADDR_BROADCAST`"或"目标端口落在 62900–62999"的 `sendto` / `WSASendTo` 出帧；
  其余计入 `ignoredNonDiscovery`。
- 源端点用 `getsockname` 缓存（`getsockname` 未挂 hook，无递归）；
  未绑定的 UDP socket 返回 `0.0.0.0:0`，**该值不作为已知端点缓存**，留待下一帧重试。
- `closesocket` 摘除槽位；64 槽满时计 `sockTableOverflow` 并继续透传。
- 初始化失败按步骤写 `initError`（1..7），不抛异常、不阻塞游戏线程。
- `CivLinkShutdown`：置状态 -1 → `MH_DisableHook(MH_ALL_HOOKS)` → 最多 5 s 等 `g_inFlight` 归零；
  返回 0 干净排空 / 1 已关闭 / 2 仍有在途。**不 teardown、不 `MH_Uninitialize`、不 `FreeLibrary`**
  （B2 审计运行模式，模块保留到目标进程退出）。

## 4 自检覆盖的 23 项断言（`hook_selftest.exe`）

初始化：state==1、initError==0、sessionId!=0。

观测与透传（5 次发送：广播 62905、环回 62907、非发现端口 50999、超长 1400 B、关闭后 62908）：
- 四次发送返回值分别原样为 `4 / 4 / 4 / 1400`；
- `sent == 2`（广播 + 环回发现各一帧）、`sendFail == 0`；
- `rejectOversize == 1`、`sentNotify == 1`、`ignoredNonDiscovery == 1`；
- `sockTableOverflow == 0`、`srcEndpointUnknown == 1`（未绑定 socket 的第一帧必然未知）；
- `sent + sendFail + rejectOversize == 3` 次计数（第 4 次超限走 notify 路径，不重复计 sent）。

生命周期：`closesocket` 后再发送返回 4 且 `sent == 3`；`CivLinkShutdown` 返回 0；
state==-1；二次 shutdown 返回 1；shutdown 后发送仍返回 4 但计数不再增长（仍 3）。

## 5 Agent 侧覆盖与对账（Rust，零依赖）

- 绑定 `127.0.0.1:34718`，`set_read_timeout(250ms)`，`WouldBlock`/`TimedOut` 视为正常。
- 解码按序校验：长度 → magic → version → `payload_len <= 1280` → 截断 → dir → `af == 2`；
  失败按稳定键计数（`short-frame`/`bad-magic`/`bad-version`/`payload-too-large`/`truncated`/
  `wrong-direction`/`bad-address-family`）。
- 逐会话统计：`first_seq`/`last_seq`/缺口数/缺失帧数/重复/乱序、载荷字节、
  发现 magic 命中数、逻辑 socket 表、目标端口分布、源端点分布。
- 输出 `frame-log.txt`（每帧一行）与 `summary.txt`（含与会话无关的总计与三条对账说明）。
- 单测 6 项全绿（`cargo +1.75.0 test --offline` → 6 passed），覆盖合法帧解码、
  坏 magic/版本/短帧、超长与截断、错误方向、错误地址族、序号缺口/重复/乱序。
- `cargo +1.75.0 fmt --all -- --check` exit 0；`build --release --offline` 无 warning。

## 6 实测结果

### 6.1 自检（可重复，不需游戏）

命令：`powershell -NoProfile -ExecutionPolicy Bypass -File .\run-f1-selftest.ps1`

最近一次证据目录：`M0A\captures\F1-selftest-20261114-003638`

- `hook_selftest.exe` → `HOOK-SELFTEST: PASS (0 failure(s))`，23/23 项 PASS；
- Agent `summary.txt`：

```text
datagrams       : 4
bytes           : 180
received frames : 4 (processed 3, rejected 1)
reconciliation  : processed + rejected = 4 == received = 4
reject kinds    : hook-rejected-oversize=1
oversize notify : 1 frame(s) (in `received`, outside `processed`)
sessions        : 1
  frames=4 first_seq=Some(1) last_seq=Some(4)
  seq gaps=0 missing_frames=0 duplicates=0 out_of_order=0
  payload bytes=12 discovery_magic=3 other_payload=0
  via_wsasendto=0 limited_bcast=1 discovery_flag=4 no_payload=1 rejected_oversize=1
  logical sockets=2
  dst ports=3 (min 62905, max 62908, in 62900..62999: 3)
```

- 驱动侧 11 项断言全 PASS，其中：`hook.sent (3) == agent.processed (3)`、
  `processed + rejected == received`、`frame-log 4 lines`、
  `dst = 255.255.255.255,127.0.0.1,127.0.0.1,127.0.0.1`、
  `ports = 62905,62907,62907,62908`；
- 最终 `F1-SELFTEST: PASS (hook and agent reconciled; F1 mechanical evidence only)`，exit 0。

### 6.2 首跑失败与修复（保留为记录）

首次运行（`F1-selftest-20261114-003232`）为 `FAIL (2 failed check(s))`，两处都是真缺陷：

1. **`srcEndpointUnknown` 期望 0、实测 1**：未绑定 UDP socket 的 `getsockname` 返回
   `0.0.0.0:0`，Hook 曾把"端口 0"当作有效端点缓存 → 三帧都带 `0.0.0.0:0`。
   修复：`EnsureLocalEndpoint` 中 `if (local.sin_port == 0) return;`，未绑定不算已知，
   下一帧重试。断言改为 `== 1`（第一帧未知是必然，第二帧起必须已知）。
2. **端口序列断言漏掉广播帧**：驱动正则写死 `dst=127\.0\.0\.1:(\d+)`，
   而第一帧目标是 `255.255.255.255:62905`，被过滤后只剩 3 个端口。
   修复：正则改 `dst=([\d.]+):(\d+)`，并**新增一条断言**明确要求首帧为广播地址。

## 7 真实客户端观测（F1-live）

`run-f1-live.ps1`：启动 Agent（`--listen-seconds 0 --stop-file`）→ 注入真实 Civ6 →
轮询 `counters` → 提示操作者在局域网列表点刷新 → 结束后读 `counters` 与 Agent `summary.txt` 对账。

断言：Hook 捕获到至少一次发现发送、`hook.sent` 增量 == `agent.processed`、
Agent 至少收到一帧、`sendFail == 0`、所有目标端口落在 62900–62999、且出现多于一个端口。

**状态：本轮未执行**（执行时无文明6 进程）。执行记录另附，见执行端回报。
该实验只回答"真实客户端的发现发送是否经过这些 API、帧是否闭合"，
**不**回答联机、不回答 E2-B、不移动任何 Gate。

## 8 边界（强制）

**允许表述**：
- "Hook 在自检进程中挂住 `sendto`/`WSASendTo`/`closesocket` 并原样透传返回值"；
- "发现端口的载荷按 CVLH2 逐帧到达本机 Agent，两侧计数闭合、序号无缺口"；
- "超长载荷被拒绝并计数，未静默截断"。

**不允许表述**：
- "文明6 的发现已被 Hook 接管"（自检是构造调用，不是游戏行为）；
- "已实现发现转发 / 已能联机 / M0-B 可行 / Gate A 通过"；
- "Agent 已参与联机"——本阶段 Agent **只观测不转发**，不向任何远端发送。

## 9 已知限制

- 只挂 `sendto` / `WSASendTo` / `closesocket`；`WSASend`（scatter/gather）**未挂**，
  目前只保留 `scatterGather` 计数字段（恒 0）。真实客户端若走 `WSASend` 将不可见，
  F1-live 的 `hook.sent` 会为 0——这正是需要真实客户端验证的原因。
- 源端点依赖 `getsockname` 缓存；若游戏在 send 之前从未绑定（不可能，sendto 前内核已隐式绑定），
  首帧源端点可能为 `0.0.0.0:0`。
- 逻辑 socket 表 64 槽，超出即计 `sockTableOverflow` 且不再新增（仍透传，不丢包）。
- Agent 不做持久化重放、不做去重合并、不做转发；这些都是 F2/F3 的内容。
- 自检不证明 Hook 在游戏的多线程/异步/Overlapped 场景下无竞态——那需要 F1-live 与后续阶段。

## 10 下一步

1. 在真实 Civ6 局域网列表执行 `run-f1-live.ps1`，取得第一份"真实客户端"帧证据；
2. 若 `hook.sent` 为 0：说明客户端走的是未挂的 API（`WSASend` 或其它），
   按证据扩 Hook 面，而不是猜；
3. F2：Fake-IP 与游戏数据面（62056）——DLL 侧开始承担映射，Agent 开始真正转发。
