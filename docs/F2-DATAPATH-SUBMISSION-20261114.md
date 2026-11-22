# F2 数据面模拟验证（非发布原型）— 设计提交件

> 版本：1.0（2026-11-14）
> 提交人：DSH（CivLink 协作模式：codex 出审计 MD，DSH 编辑执行）
> 性质：REV-016 F2 阶段**非发布原型**设计，请求 codex 复核裁定后实施
> 关联裁定：`docs/F1-INTEGRATION-REVIEW-20261114.md`（第 ⑤/⑥/⑦ 项批准 F2 并给出设计必纳入项）

---

## 1. 设计文档身份

| 文件 | sha256 | 字节 | 行 |
|------|--------|------|----|
| `docs/F2-DATAPATH-SIMULATED-PEER-20261114.md`（设计草案） | `29865AEDA2CF4A75B3ED791D42614E63BBFD7465BC246B93CE340DDEB830CE33` | 10,489 | 126 |
| `docs/F1-INTEGRATION-REVIEW-20261114.md`（裁定依据，codex） | `ABF6BC4548B7D8DE99FE09560CC65FA477E202E168A58110A39377344E4DCF98` | 4,093 | 47 |

编码：UTF-8 无 BOM、LF、控制字符 0（U+0009/000B/000D 扫描通过）。

## 2. 设计要点（提交摘要）

**目标**：在"单台真实 Civ6 + 模拟 Peer"夹具下回答五个问题：
- Q1 数据面是否 UDP 62056、API 是否 WSASendTo/WSARecvFrom（与发现段 sendto/recvfrom/select 不同套）；
- Q2 62056 socket 是否 bind 通配 0.0.0.0:62056、非阻塞、调用顺序 bind→先 WSARecvFrom→再 WSASendTo；
- Q3 加入流程首包形态与模拟房主应答后客户端行为；
- Q4 FakeEndpoint 五元组映射（§4.3）在模拟 Peer 下分配/查表/生命周期；
- Q5 队列满/Agent 不在/高负载下 Hook 侧同步发送延迟与失败行为（五计数对账，不静默丢包）。

**边界（明确不做）**：Design I 绑定矩阵+≥1000 次投递压测（M0-B R1）、H1-A/B/C、H2、H8（均 M0-B）；双机真实联机（E2-A/E2-B/E3 仍待验证）；不注入远端流量、不拦截/改写真实游戏数据包、不改网卡/防火墙/metric、不冻结 wire format；不移动任何 Gate。

**方案四件**：
1. Agent 增加 `--simulate-datapath`：bind 出口 IP:62056（同 F1 自动探测）、记录每个数据报（len+head16B hex 匿名化）、对每个新 src:port 回 1 个 20B 固定应答（不伪造游戏协议，只验证通路）、budget 每 socket 1 次；七计数器。
2. Hook DLL 新增 recvfrom/WSARecvFrom/bind detour（**纯观测，不吞包不改包**——Design I 吞包属 M0-B）；新增 bind_calls/bind_62056_count/recvfrom_calls/datapath_sent/datapath_send_to_62056 等计数；发现段判定维持 `dst_port∈62900..62999 && payload==8DE8FC70`，其余归"数据面/其它"。
3. FakeEndpoint 映射原型 = 独立 Rust crate `civlink-fakeip`（不注入游戏）：`FakeEndpoint{fake_ip,fake_port}` + 键 `(socket_id, FakeEndpoint)` → `PeerEndpoint`；候选段 127.0.127.1..100（F7 实证段；198.18.0.0/15 属 H1 不在此裁决）；发现期空闲 10min 回收、IN_ROOM/IN_GAME 固定保留（§5）、重启重建；Mutex+HashMap+计数；单测+变异测试。
4. Q5：本原型保持同步 UDP（Agent 只观测），R11 共享内存有界队列留 M0-B；Hook 加 `channel_down` 计数使投递失败可观测；高负载模拟测试断言对账缺口显式报告。

**实施步骤 S1-S6**（S1 Agent 62056 模式 / S2 Hook 新 detour / S3 fakeip crate / S4 机械自检 / S5 真机验证 / S6 报告文档）。

## 3. 请求裁定项（D1-D5）

| # | 请求 | 说明 |
|---|------|------|
| D1 | **批准设计边界**：F2 只做模拟验证，Design I 矩阵/H1/H2/H8 明确留 M0-B，不因"先做了 62056 观测"而提前裁决或跳过 R1 | 防止范围蔓延；边界照抄裁定第 ④ 项"明确不证明"列表 |
| D2 | **批准 S1-S4 先行**（不需游戏进程）：Agent --simulate-datapath、Hook 新 detour、civlink-fakeip crate、机械自检 | 与 F1 先例一致：无游戏的部分先做先验 |
| D3 | **批准 S5 真机场景**：真实 Civ6 点击"加入"模拟房间（非仅刷新观察），记录 62056 数据面行为；若游戏进入加载/连接失败等异常行为，**如实记录不修游戏不伪造** | 这是新增操作（点击加入），超出 F1 集成"刷新显示房间"的授权动作范围，需单独批准；同时声明加入对局依赖真实房主协议，模拟房主不保证对局建立 |
| D4 | **批准 62056 应答策略**：每新 src:port 回 1 个 20B 固定字节应答（不模仿真实房主协议、不伪造游戏协议） | 延续 REV-013"有界合成响应"授权精神：只回本机、预算 1 次/socket、不向远端发 |
| D5 | **批准 FakeEndpoint 候选段取 127.0.127.x（F7 实证段）**，198.18.0.0/15 明确挂起为 H1 变量 | §4.3/P0-1 双候选对照属 M0-B 裁决，F2 原型选实证段做映射机制验证即可 |

## 4. 已知风险（如实披露）

1. 游戏点击加入后可能根本不向模拟房主发 62056 包（加入判定依赖真实房主二次握手）→ 本轮记录"未见数据面流量"，Q1 未观察到、原因未裁决，不判产品失败。
2. 62056 可能被其它进程占用（vivoesService 等，F0 曾见 62984 被占）→ datapath bind 失败计数+显式报告。
3. Hook 新 detour（bind/recvfrom）若影响游戏行为 → 必须先过机械自检（返回值/last error 原样透传断言），真机只做一轮试探，异常即停。
4. 用户点击加入可能进入加载界面需 Esc 退出，或该轮作废。

## 5. 请求的复核输出

请裁定 D1-D5；如需调整 S5 场景（如改为"仅注入后刷新+计数观测，不点击加入"）请指明替代场景。裁定后 DSH 按 §4 实施步骤执行，每步产物哈希如实记录。

---

*（本提交件不冻结 wire format、不改变 Gate 状态、不扩大 F1 裁定范围；任何裁定结果均不构成 Gate A/B 批准。）*
