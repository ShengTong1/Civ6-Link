# F2 数据面模拟验证（非发布原型）— 设计与实施计划

> 版本：0.2（修订版，2026-11-14）
> 状态：**已按 `docs/F2-DATAPATH-REVIEW-20261114.md` 裁定修订**，S1–S4 可开始
> 裁定依据：codex 复核 `F2-DATAPATH-REVIEW-20261114.md`（sha256 见 §8）+ F1 裁定第 ⑤/⑥/⑦ 项
> 定位：REV-016 F2 阶段**非发布原型**，继续使用模拟 Peer，**不需第二台 Civ6**

---

## 0. 修订记录（v0.1 → v0.2，落实复核 §2 五项约束）

| 复核项 | v0.1 问题 | v0.2 修订 |
|--------|----------|----------|
| §2.1 | 用 `Find-NetRoute 255.255.255.255` 推导监听地址，失败静默回退 127.0.0.1 | **显式 `--bind-ip`**（仅接受本机本地地址），启动日志记录地址+接口别名；未指定或绑定失败 **fail-closed** 停止数据面模拟；纯回环自检用显式 `--loopback-selftest`，不当真机结果 |
| §2.2 | Agent 同机 bind `:62056` 应答 → 偷带 H2/R1 | **Agent 一律不 bind `:62056`、不设 SO_REUSEADDR、不用 bind/投递结果推断 H2**；经 CVLH2 收 Hook 观测的真实出向请求，用**独立临时 UDP socket** 做受限回包；回包只探测客户端接收/API 行为，不代表真实 Peer 源端口或协议 |
| §2.3 | 映射键只有 `(socket_id, FakeEndpoint)`，无代次/会话 | 键 = **`(session_id, logical_socket_id, socket_generation, FakeEndpoint)`**；远端值 = **`(peer_id, tunnel_session_id, peer_endpoint)`**；正反向查询唯一性/冲突/过期双向删除/池耗尽均定义 |
| §2.4 | 未明确 WSARecvFrom 同步/重叠边界 | **WSA_IO_PENDING/失败只记状态，不读 WSABUF/来源/字节数**；仅同步成功且 bytesReceived 有效才读缓冲区摘要；保持原调用/返回值/WSAGetLastError/WSASetLastError 语义；观测路径无阻塞 IPC/文件 I/O/等待 |
| §2.5 | 把 sendto 成功当"Agent 已收到"、称 UDP buffer 为队列 | **分层计数**（Hook 原始调用 / CVLH2 尝试·成功·失败·错误码 / Agent 实收帧 / 数据面 socket 实收 / 测试负载发送）；只有明确相同报文集合才相等对账；"Agent 进程存活"独立健康探测；不称 buffer 为队列、不写"无同步错误=零丢包" |

---

## 1. 目标与授权边界

### 1.1 本阶段要回答的问题（仅限本构建、本机模拟 Peer 条件）

| # | 问题 | 对应规范项 |
|---|------|-----------|
| Q1 | 真实 Civ6 客户端在"点击房间加入"后，数据面是否确实走 **UDP 62056**、API 是否 **WSASendTo / WSARecvFrom**（与发现段 sendto/recvfrom/select 不同套） | F3/F4/F5 |
| Q2 | 客户端 62056 socket 是否 **bind 通配 0.0.0.0:62056**、是否**非阻塞**、调用顺序是否 **bind → 先 WSARecvFrom → 再 WSASendTo** | F4/F6 |
| Q3 | 加入流程首包形态（长度/频率/方向）与本机单次探测后客户端行为 | F3 |
| Q4 | **FakeEndpoint 映射（含代次/会话隔离）**在纯内存模拟下分配/查表/生命周期/冲突/回收 | §4.3、§5 |
| Q5 | Hook 观察层各计数分层与对账（可观测性底线，不静默丢包） | §4.4、R11 |

### 1.2 明确不回答（边界，禁止越界表述）

- ❌ 不做 Design I 绑定矩阵 + ≥1000 次投递确定性压测（**M0-B 核心阻断项 R1**）。
- ❌ 不裁决 H1-A/B/C（198.18.0.0/15 过滤）、H2（SO_REUSEADDR 共存投递归属）、H8（62056 socket 选项矩阵）——均 M0-B。
- ❌ **Agent 不 bind `:62056`、不设 SO_REUSEADDR、不用本实验任何 bind/投递结果推断 H2/R1**（复核 §2.2）。
- ❌ 不做双机真实联机（E2-A/E2-B/E3 仍待验证）；模拟测试**不能勾掉**它们。
- ❌ 不注入任何远端流量、不拦截/改写真实游戏数据包、不改网卡/防火墙/路由 metric、不冻结 wire format。
- ❌ `127.0.127.x` 仅纯内存候选池，**不得配置本机地址、真实 bind/发送该段**（D5）。
- ❌ 不移动任何 Gate（Gate A 未批准、正式 M0-B/Gate B 冻结）。

### 1.3 结论表述模板（复核 §4，只能这样说）

- 成功："在本构建和本机模拟条件下，观察到 Civ6 的相关 Winsock 调用及本机单次测试数据报行为；FakeEndpoint 内存映射单测通过。实验未验证远端 Peer、真实协议兼容、H2/R1 绑定投递、双机加入或游戏开局。"
- "调用顺序 bind→先 WSARecvFrom→再 WSASendTo"只能从**同一 socket、同一进程、结构化单调序号/QPC 时间记录**判定；非阻塞属性须用 `ioctlsocket(FIONBIO)`/`WSAEventSelect` 等可见证据或标"**未观察**"。
- 失败："本轮未观察到 X，原因未裁决。"

---

## 2. 前置条件（F2 切换前置，F1 裁定第 ⑥ 项）

1. Civ6 已退出、进程已确认消失（2026-11-14 11:11 实测：无 CivilizationVI* 进程，34718/62900-62999 全部 free）✅
2. 修改/重链 Hook DLL 前已确认无进程映射旧 DLL ✅
3. 改 DLL 后必须从中立目录 `C:\Users\dd\Desktop\civlink-f1\` 注入（项目树 Low IL 陷阱，README §3B.5）

---

## 3. 设计

### 3.1 拓扑（复核 §2.2 后）

```
真实 Civ6 客户端 ──sendto/WSASendTo(发现 62900-62999)──→ [Hook 观测→CVLH2] → Agent(发现段模拟房主)
真实 Civ6 客户端 ──sendto/WSASendTo(数据面 62056)───→ [Hook 观测→CVLH2] → Agent(数据面观测+受限回包)
Agent 数据面回包 ──独立临时 UDP socket（不 bind 62056）──→ 游戏客户端（本机单次探测）
```

- **Agent 不 bind `:62056`**；数据面观测完全经 CVLH2 帧（Hook 转发观测帧，不吞包不改包）。
- 回包目标 = 游戏出向帧的源端点（仅当源 IP 确认本机且源端口非零）；回包源 = Agent 临时端口。

### 3.2 Agent `--simulate-datapath` 模式（对应 Q1-Q3，S1）

**参数（fail-closed）**：
- `--bind-ip <addr>`：仅接受当前主机本地地址（启动时枚举 `Get-NetIPConfiguration` 校验）；未指定或非法 → **退出并报错，不静默回退**。启动日志记录地址+接口别名。
- `--loopback-selftest`：显式纯回环自检开关（只用于机械自检，结果标注"回环自检，非真机"）。
- `--datapath-max-replies 1`：固定 1（D4 全程最多 1 个 20B 响应）。

**行为**：
- 经 CVLH2 帧识别数据面出向请求（dst_port ∈ 62056 或非发现段且非本 Agent 通道），记录 `src:port / dst:port / len / head 16B hex` 到 `datapath-log.txt`（匿名化：不记 payload 全文）。
- **受限回包（D4 一次性替代）**：整个运行**总计最多 1 个 20B 固定数据报**，仅当：
  - 源 IP 经确认是本机地址（与 `--bind-ip` 或本机地址表比对），且
  - 源端口非零；
  - 源为 `0.0.0.0:0`、非本机、端点不完整或无法确认 → **只记录不回**。
  - 回包用独立临时 UDP socket（源端口系统分配），不 bind 62056；载荷固定 20B、无重试、不带真实玩家/网络信息。
- 计数器：`datapath_frames_seen / datapath_reply_sent / datapath_reply_skipped_no_endpoint / datapath_reply_skipped_not_local / datapath_reply_already_sent / datapath_send_fail / datapath_bytes`（分层，不跨层对账）。
- summary.txt 增加 `datapath:` 小节，措辞："本机单次任意数据报探测，非游戏协议应答 / 非 Relay RTT / 非真实房主模拟"。

### 3.3 Hook DLL 扩展（纯观测，不吞包不改包；对应 Q1/Q2，S2）

F1 已有 detour：sendto / WSASendTo / closesocket。F2 新增：
- **`bind`**：记录参数类别（SOCKADDR_IN 地址/端口）、返回值、`WSAGetLastError`；**不拦截、不改参数**；保持原调用语义。
- **`recvfrom`**：记录句柄、来源地址、返回值、错误码；同步成功才读数据摘要；失败只记状态。
- **`WSARecvFrom`**（复核 §2.4）：
  - 同步成功且 `bytesReceived` 有效 → 可读缓冲区摘要（len+head）；
  - 返回 `SOCKET_ERROR/WSA_IO_PENDING` 或失败 → **只记状态（调用类别/句柄/目标端口/返回值/立即错误码），不读 WSABUF、不读来源地址、不读完成字节数**；
  - 本阶段不增加完成通知 Hook（overlapped 完成经 IOCP/事件后不再观测）；
  - detour 必须调用原函数，保持调用参数、返回值、`WSAGetLastError`/`WSASetLastError` 可观察语义；
  - 观测路径**不得阻塞 IPC/文件 I/O/等待**。
- **出向转发扩展**：sendto/WSASendTo 判定保持发现段逻辑（`dst_port∈62900..62999 && payload==8DE8FC70` → DISCOVERY 帧）；其余出向（含 62056）转发**观测帧**（新 flag 或 dir 标记，仍走 CVLH2），不吞包。
- 新计数（分层，复核 §2.5）：`raw_sendto_calls / raw_wsasendto_calls / raw_bind_calls / raw_recvfrom_calls / raw_wsarecvfrom_calls / bind_62056_count / recvfrom_on_62056 / cvlh2_try / cvlh2_ok / cvlh2_fail / cvlh2_errno / channel_down`；Agent 侧对应 `frames_received`——**只有明确同一报文集合的层才相等对账**（如 raw 发现出向数 vs Agent 发现帧数）。

### 3.4 FakeEndpoint 映射原型（Q4，独立 crate `civlink-fakeip`，纯内存，S3）

复核 §2.3 后的类型与规则：

- `FakeEndpoint { fake_ip: Ipv4Addr, fake_port: u16 }`
- `PeerEndpoint { peer_id: u32, tunnel_session_id: u64, addr: SocketAddr }`
- **键 = `(session_id: u64, logical_socket_id: u32, socket_generation: u32, FakeEndpoint)`**
- 正向查询：`(session, sock, gen, fake) → PeerEndpoint`；反向查询：`(peer_id, tunnel_session_id, 原始源端口) → FakeEndpoint`。
- 唯一性：同键唯一；冲突（同 fake 端口被不同键占用）→ 分配失败显式错误，不静默覆盖。
- 生命周期：发现期空闲 TTL 10min 回收；IN_ROOM/IN_GAME 固定保留（§5 规则）；socket 关闭/会话结束 → **正反向双向删除**；池耗尽 → 显式 `PoolExhausted`。
- 候选池：`127.0.127.1..=127.0.127.100` **纯内存**（D5 限定批准；不配置网卡、不真实 bind/发送）；`198.18.0.0/15` 保留为 H1 对照项（不删除）。
- 并发：`std::sync::Mutex<HashMap>` + 每操作计数；**本 crate 是数据结构原型，不得声称已实现可用于 DLL 的生命周期联动**（复核 §2.3）。
- 测试：单元测试覆盖分配顺序/满池/回收/双向删除/重启重建/同 peer 多 socket 独立映射/代次隔离（同 socket_id 新代次不命中旧映射）/会话隔离；+ 变异测试（校验器先跑真实证据再跑变异，F0 教训）。

### 3.5 Q5 可观测性（复核 §2.5）

- 只报告可直接计数的事实：Hook 原始调用数、CVLH2 尝试/成功/失败/错误码、Agent 实收 CVLH2 帧数、数据面 socket 实收数、测试负载发送数——**分层，不跨层宣称相等**。
- "Agent 进程存活" = 独立健康探测（测试脚本 `Test-NetConnection 127.0.0.1 -Port 34718` 或进程存在检查）；**没有健康握手时不得把 sendto 成功宣称为 Agent 已收到**。
- 不称 UDP send buffer 为应用队列；"没有同步错误"不写成零丢包；`channel_down`（CVLH2 sendto 失败/ECONNREFUSED）计数，投递失败可观测。
- 高负载模拟：构造 ≥1000 帧/秒级负载，断言 Hook `raw_*` 与 Agent `frames_received` 缺口**显式报告**（不静默）。

---

## 4. 实施步骤（复核 §5 顺序）

| 步 | 内容 | 产物 |
|----|------|------|
| S1 | Agent `--simulate-datapath`（§3.2，fail-closed --bind-ip）+ 单测 + 回环自检 | main.rs 扩展、`run-f2-datapath-selftest.ps1` |
| S2 | Hook DLL 新增 bind/recvfrom/WSARecvFrom detour（§3.3 纯观测）+ 出向观测帧 + 分层计数；构建导出断言 | hook.cpp、civlink_hook.h、build-msvc.cmd |
| S3 | `civlink-fakeip` crate（§3.4）+ 单测 + 变异测试 | `civlink\fakeip\` |
| S4 | 机械自检（无游戏）：hook_selftest 扩展覆盖新 detour（含构造 WSA_IO_PENDING 路径验证不碰缓冲区）；Agent datapath 回环自检；分层对账断言 | `run-f2-mechanical-selftest.ps1` + 证据目录 |
| S5 | 真机验证（D3 一次授权 + D4 回包）：重启 Civ6 → 注入 → 刷新 → **一次手动点击加入** → 观察 62056 数据面 → 异常即停不重试 | `run-f2-live.ps1` + 证据目录 |
| S6 | 报告 + 提交件 + README 更新 | `docs/F2-DATAPATH-REAL-CLIENT-20261114.md`、README v1.17、CODEX-HANDOVER 第 13 项 |

每步报告：源文件差异、命令、退出码、原始输出、哈希（复核 §5.2 要求）。

## 5. 真机验证场景（S5，D3 有条件批准一次）

1. Civ6 重启 → 中立目录注入 civlink_hook.dll（F2 版，进程确认退出后重链）。
2. Agent `--simulate --simulate-datapath --bind-ip <本机地址>`（**不 bind 62056**）。
3. 用户：进入局域网列表 → 刷新 → 房间出现 → **手动点击加入一次**。
4. 观测：游戏点击加入后是否在 62056 发包（Hook raw/datapath 计数 / Agent datapath_frames_seen）；D4 条件下 Agent 最多回 1 个 20B（仅当源确认本机且端口非零）；游戏行为（继续发/报错/卡住）如实记录。
5. **异常（崩溃/卡死/系统错误/加载异常）→ 立即停止本轮并保留证据；不重试、不修游戏、不伪造成功**（D3）。
6. 表述：本机单次探测；不代表真实加入或联机；不代表真实 Peer 源端口/协议（D4）。

## 6. 风险与已知失败模式

1. 游戏点击加入后可能根本不发 62056 包（加入判定依赖真实房主二次握手）→ 记录"未见数据面流量"，Q1 未观察到、原因未裁决。
2. 源端点 `0.0.0.0:0` 或非本机 → D4 回包被跳过（只记录），符合裁定。
3. Hook 新 detour（bind/recvfrom/WSARecvFrom）影响游戏行为 → 先过机械自检（返回值/last error 原样透传断言），真机只做一轮试探，异常即停。
4. 用户点击加入进入加载界面 → Esc 退出或该轮作废，不重试。
5. 无法避免 bind 62056 时 → **停在 S4，提交问题，不执行 S5**（复核 §5.4）。

## 7. 文档与证据要求

- 全部 UTF-8 无 BOM、LF；中文 MD 编辑后扫 U+0009/000B/000D（README 事故教训）。
- 每轮证据目录含：agent summary.txt、datapath-log.txt、counters-before/after.txt、verify-report.txt、fixture 哈希。
- 哈希表逐文件 SHA256；二进制重建哈希必变（PE 时间戳），如实记录。

## 8. 文件身份

| 文件 | sha256 |
|------|--------|
| `docs/F2-DATAPATH-REVIEW-20261114.md`（裁定，codex） | `4EBBC452213DAAC4E3DDE01B6A264462AC6267E7F3DD52166DEDE526E8D10D17` |
| `docs/F2-DATAPATH-SIMULATED-PEER-20261114.md`（本草案 v0.2） | `22D5DA9D4D02EBCC2BEA86AC2694B42E3FAE80CC37AFB62CC3AEC023A0B3161F`（2026-11-14 子代理审计复核时实测快照） |

*注：本文件自身的哈希随每一次修订变化（自引用），§8 此行为审计复核时点快照；文件身份以 `F2-DATAPATH-COMPLETION-20261114.md` §5 的 Get-FileHash 实测值为权威。*

---

*（v0.2 已落实复核 §2 全部五项约束；按复核 §5.1 属设计更正，直接进入 S1–S4，不需另等范围裁定。）*
