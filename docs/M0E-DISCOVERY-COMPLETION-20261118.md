# M0-E：发现补全器（Discovery Completion，loopback 重放架构）

> 版本：**v2.0**（2026-11-19，按 `docs\M0E-REVIEW.md` 逐条回写）
> 状态：**已实现 + 单机自检 45/45 / 变异 5/5 全捕获；跨机与真实 Civ6 客户端未验证**
> 冻结二进制：`civlink\civlink-agent.exe` 464,384 B / `15321D49806517028ECE8CC8A3DC8B0ED855C410915295CAF72EBEF4DDF06267`
> 冻结源码：`civlink\agent\src\main.rs` 176,308 B / `E56A30562A94376B1982FCF184C2A81C791CF5B50B15218231712048E59A4276`
> 自检脚本：`civlink\run-m0e-completion-selftest.ps1` 26,268 B / `322CB66CD3CA3D53A9DC6C4E8871AFCD41FBA8B48AFB3CB52612DC1218F9D6C3`
> 变异脚本：`civlink\run-m0e-mutation.ps1` 10,343 B / `ACADBBFF47EF0EC1853C624AA1903FDBC65F882635ED156A61902A08B8507A0A`
> 前置事实来源：`C:\Users\dd\Desktop\injciv6-v0.3.3\局域网发现方案独立研究.md`（46,737 B / 462 行）+ A 机真实游戏实测
> 项目负责人目标（m29860，逐字）：「我最终不希望在客户端看到虚拟的房间，虚拟的房间没有任何的意义，这只是我现阶段调试用的。我最后想实现的是，服务端的Agent绑定99个端口+文明6游戏本身建房之后就固定绑定的62900端口，共计100个端口。无论哪个端口收到客户端发来的请求，都会将服务端创建的真实房间应答回客户端，让客户端可以进入房间，正常游戏。」

## 0. 版本历史与审计状态

| 版本 | 内容 | 状态 |
|---|---|---|
| v1.0（2026-11-18） | 初稿，只有「loopback 重放」机制与 §1-§11 | 被 `docs\M0E-REVIEW.md` 判 **NOT PASS**（2 阻断 / 4 高 / 5 中 / 6 低） |
| v2.0（2026-11-19） | 按审计逐条回写：§5.1/§5.2/§5.3/§5.4 与实现一致、B-1 源地址钉住机制、B-2 去重/预算/墙钟、H-1 校验、§7 反射放大、§8 补齐待测项、§10 证据更新 | docs\M0E-REVIEW-2.md（16,824 B / `5ABAFEBE…`）裁定 **PASS 有条件通过**，B-1/B-2 关闭确认 |
| v2.1（2026-11-19，本版） | 落实 REVIEW-2 三项文档放行条件（不改代码）：N-1 证据路径口径勘误（两处分布）、N-2 不采信轮补记、N-6 冷却窗用户须知 | 本版 |

**v1.0 的两条阻断及本轮处置（详见 §0.1）**：B-1「保证客户端看到的源 = 房主IP:P」是**过度承诺**，v1.0 未采集请求的目的地址、也无从钉住源 IP；B-2「去重 + 总阻塞 ≈ 1×timeout」在 v1.0 的实现里**根本不存在**。

### 0.1 审计发现 → 本轮处置对照

| 编号 | 审计原文要点 | 本轮处置 |
|---|---|---|
| B-1 | 通配 socket 的 `send_to` 不携带源地址，源 IP 由路由决定；本机三地址无单一"房主IP"；loopback 证据结构性掩盖该缺陷 | **已修**：新增 `egress` 模块（`WSARecvMsg`+`IP_PKTINFO` 取目的地址、`WSASendMsg`+`IP_PKTINFO` 钉源地址）。零依赖手写 ws2_32 FFI（`Cargo.toml` 的 `[dependencies]` 保持为空，构建仍 `--offline`）。三接口实证实测见 §4.6 |
| B-2 | 99 次重放灌满单 socket、99s 阻塞主 poll | **已修**：`(client_ip, client_port)` + 冷却窗去重；`--completion-max-replies` 预算；`clear_backlog` 清旧页；墙钟 deadline 硬截止。实测 100 magic → 1 次重放（§4.7） |
| H-1 | 只比 `from.ip()`、任意非零长度都当广告页、`continue` 不推进 deadline | **已修**：严格比 `from == game_addr`（IP+端口）；`Instant` 墙钟 deadline；长度分桶（`odd_page_sizes`） |
| H-2 | §5.1 说"忽略 `--simulate`"实为报错、"强制 reserve"实为必须显式给 | **已修**：§5.1 改为与实现一致的"拒绝"与"必须显式给" |
| H-3 | 反射放大 6,072×，§7 边界未提 | **已修**：§7 新增第 6 条边界明确写出倍数与缘由 |
| H-4 | 62900 默认保护未写入设计 | **已修**：§5.1 明确"必须显式 `--reserve-62900`，否则拒绝启动"，并在 §5.3 说明它为何是硬需求 |
| M/L | 文档与实现不一致、证据支撑超界、测试零覆盖 | **已处理**：§4.5 的"毫秒级"改为实测数字；删除跨机外推；新增 5 类 scenario 覆盖 completion 路径 |

---

## 1. 要解决的问题

Civ6 局域网发现的结构性缺陷（实测确认）：

| 事实 | 数值 | 证据来源 |
|---|---|---|
| 房主建房后监听的发现端口 | **仅 62900**（`0.0.0.0:62900`） | A 机 `Get-NetUDPEndpoint` pid 43872 实测 |
| 客户端"刷新"发出 | 向 `255.255.255.255:62900..62999` 各 1 包（100 包），载荷 4B `8D E8 FC 70` | E2-B / F0 抓包 |
| 房主应答 | 从 `62900` 单播 22 页 × 1104B 到客户端源地址:源端口 | E2-B / B1 §0 取证 |
| 名义冗余 vs 实际冗余 | 发 100 包，只 1 个 socket 在听 → **有效尝试次数 = 1** | 独立研究 A1 |
| 网卡层丢包 | 66~94/100 到达（丢 6%~34%） | E2-B 首轮 |

**结论**：任一次丢包、任一防火墙/VPN 干扰，都直接 1:1 放大成"搜不到房间"。这是**结构性缺陷**，不是环境问题。

## 2. 设计目标（用户目标的可执行化）

1. 房主侧让 **62900..62999 全部 100 个端口**都能"接住"客户端请求。
2. 应答内容必须是**房主真实房间**（不是 fixture、不是虚拟房）。
3. 客户端看到房间后能**正常进入并游戏**（数据面 62056 属 §9，不在本设计范围）。
4. **不注入游戏进程**；不装驱动；尽量不需要管理员。
5. 不破坏"房主能随时重新建房"（m25442 的 62900 冲突）。

## 3. 核心机制：loopback 重放

```
[客户端 B]  广播 magic → 房主 A 的 62900..62999（100 个包）
                              ↓
[agent A]   绑 62901..62999 中的 99 个（62900 留给游戏，绝不绑）
            任一端口 P 收到 magic
                              ↓
            用【转发 socket（绑 0.0.0.0）】把同一个 magic 单播给
            127.0.0.1:62900
                              ↓
[Civ6 A]    以为是本机客户端在找房间 → 从 62900 回 22 页真实广告
            到转发 socket 的源地址:源端口（127.0.0.1:ephemeral）
                              ↓
[agent A]   收齐 22 页 → 用【收到请求的那个监听 socket P】原样转发给
            客户端的真实 (IP, 源端口)，并把出站源地址钉成【客户端探测的那个本机地址】
                              ↓
[客户端 B]  看到应答源 = 房主A_IP:P，内容 = 真实房间 → 列表显示真实房
```

**关键性质**：agent **从不生成任何数据**。它只把请求转达给游戏，再把游戏的真实应答转回去。

- 房名、mod 列表永远真实（游戏自己生成）。
- 不存在"虚拟房"与真实房并存/去重冲突。
- 不需要 hook 注入、不需要缓存、没有冷启动问题。## 4. 实测证据

### 4.1 定向验证：游戏是否对 loopback 重放应答

脚本 `M0A\c3-loopback-replay-probe.py`，A 机真实建房（pid 43872，持有 `0.0.0.0:62900`）：

```
forward socket bound: 0.0.0.0:61758
discovery socket bound 0.0.0.0:62901 OK
replayed magic to 127.0.0.1:62900 from ('0.0.0.0', 61758)
replies received: 22
  page 01..22  len=1104  head=5960699b  from=127.0.0.1:62900
control (192.168.31.60 bound) sendto 127.0.0.1 FAILED: OSError(10049)
```

- **结论 1**：游戏对 loopback 重放**正常应答完整 22 页**。
- **结论 2**：研究警告的"转发 socket 必须绑 `0.0.0.0`"实测成立——绑具体 LAN IP 时 `sendto 127.0.0.1` 报 `WinError 10049`。
- **结论 3**：研究标注的疑点"游戏可能校验探测源必须在本地子网"**被证伪**——源是 `127.0.0.1` 也照常应答。

### 4.2 内容真实性

`page-01.bin` 偏移 24..46 = `dingzihan2022的游戏`（UTF-8），即房主真实房名。

### 4.3 源地址独立性

用两个不同源端口重放两次，逐字节比对：

```
replay A srcport=62456  replay B srcport=62457
byte-identical across different source ports: True
  127.0.0.1 bytes       present in any page: False
  LAN 192.168.31.60     present in any page: False
  srcport A/B           present in any page: False
```

**结论 4**：22 页载荷与探测源地址、源端口**完全无关**。loopback 重放不会把 `127.0.0.1` 泄漏进广告内容。

### 4.4 确定性

两次独立重放 `identical across replays: True` → 应答是无时间戳/无随机数的确定性内容（可安全缓存，但本设计选择不缓存，见 §7）。

### 4.5 全链路（本机）

脚本 `M0A\c3-fullchain-probe.py`：

```
模拟客户端 127.0.0.1:60266 → agent(0.0.0.0:62901) 收到 4B magic ✓
agent → 重放给 127.0.0.1:62900 → 游戏回 22 页 ✓
agent → 22 页转发给客户端 → 客户端收到 22 个包，源 = 127.0.0.1:62901 ✓
```

**注意（审计 M 项纠正）**：v1.0 此处写过"游戏应答在毫秒级"，但 `c3-probe-result-1.txt` 不含任何时间戳，该说法**无实据**。本轮补测的真实数字见 §4.2b：
- 单 magic 直发 62900 → 首包 **1.01 ms**、22 页收齐 **4.11 ms**（证据 `M0A\captures\M0E-B2-probe-20261118-2350\B2-confirmation.txt`）。
- 跨机时为 `房主IP:62901` 是**外推，不是实测**（本机只有 loopback 证据）。

### 4.6 B-1 修复实测：三接口源地址钉住（真实游戏）

证据 `M0A\captures\M0E-B1-egress-20261119-0055`（agent pid 43304，真实 Civ6 pid 43872 建房中）。
探针 `M0A\c3-b1-egress-probe.py`（28,23 B）向指定 `<本机IP>:<端口>` 发 1 个 magic 并收集 2 s 内全部回包：

| 探测地址 | 收到页数 | 回包源（distinct） | pinned | 首包 |
|---|---|---|---|---|
| `192.168.31.60:62901`（WLAN） | 22 | 仅 `192.168.31.60:62901` | true | 38.96 ms |
| `26.74.126.98:62902`（Radmin） | 22 | 仅 `26.74.126.98:62902` | true | 73.33 ms |
| `192.168.191.3:62903`（ZeroTier） | 22 | 仅 `192.168.191.3:62903` | true | 69.26 ms |

**同一 Agent 进程对三个不同本地地址探测，回包源地址都等于被探测地址**——这正是 B-1 要求的性质（此前会统一走路由表选出唯一出口）。

实现路径：`WSARecvMsg` + `IP_PKTINFO`（`IPPROTO_IP`/`19`）读出**请求到达的那个目的地址**，再用 `WSASendMsg` + `IP_PKTINFO` 把每页的源地址钉成它。

### 4.7 B-2 修复实测：一次刷新只重放一次

证据 `M0A\captures\M0E-B2-fixed-20261119-0002`：
一次真实形态的刷新（100 magic 单 socket，41.1 ms 发完）→ summary：

```
requests seen   : 99
replays sent    : 1
pages collected : 22
pages forwarded : 22
duplicate magic : 98
budget exhausted: 0
backlog cleared : 0
```

客户端收到 44 个包 = 游戏自己回的 22（测试脚本直发 62900 造成）+ agent 转发的 22，`distinct page contents = 1`。
对照**修复前**（`M0E-B2-probe-20261118-2350`）：`replays sent 99 / pages collected 2178 / pages forwarded 2178`，客户端只收到 60 包（其余被单 socket 缓冲挤掉）——即审计 B-2 描述的现象，实测比描述更严重。

### 4.8 单机自检与变异

> **不采信轮（复审 N-2 补记，v2.1）**：M0E-completion-20261119-002511-FAILED-setup（残留重复 $sink.Close() 致 setup 失败）与 M0E-completion-20261119-002605（3 场景时代旧版，39/39）均为留档轮，**不采信**；采信轮唯一为 -003732（45/45）。
- 自检 `civlink\run-m0e-completion-selftest.ps1` → **PASS 45/45**，证据 `M0A\captures\M0E-completion-20261119-003732`（42 文件）。
  五个场景：①loopback 活体目标 22 页 + egress 回退语义 ②静默目标 fail-closed ③3 个重复 magic → 1 次重放 ④非 loopback 探测 → 22 页全部从被探测地址发出且 summary 报 `egress pinned 22` ⑤5 条交叉参数规则。
- 变异 `civlink\run-m0e-mutation.ps1` → **PASS 5/5 全捕获**，证据 `M0A\captures\M0E-mutation-20261119-003243`：
  M1 去掉 fail-closed 伪造应答 / M2 改用转发 socket 回包 / M3 重放两次 / **M4 禁止钉源地址（B-1 回归）** / **M5 去掉冷却窗（B-2 回归）**，每条都精确命中对应断言，末尾自动恢复 pristine（源码 sha256 一致 + 自检复跑 PASS）。

## 5. agent 侧实现（与代码一致）

### 5.1 新增 CLI

> **冷却窗用户须知（复审 N-6 补记，v2.1）**：--completion-cooldown-ms（默认 750 ms）按 (客户端IP, 客户端端口) 去重——同一客户端在冷却窗内的重复刷新只重放一次。设为   合法且被解析层接受，但**等效禁用去重**：每次 magic 都会触发一次完整重放，99 个发现端口会把一次刷新放大成 ~99 次重放（回到审计 B-2 描述的 2.41 MB/2178 报文局面）。除调试外不要设 0。
| 参数 | 默认 | 取值 | 说明 |
|---|---|---|---|
| `--discovery-completion` | 关 | flag | 启用补全器：不做 fixture/缓存应答，改为 loopback 重问本机游戏并转发真实应答 |
| `--game-discovery-addr <IP:PORT>` | `127.0.0.1:62900` | 必须是 loopback | 本机游戏的发现监听地址 |
| `--completion-timeout-ms <N>` | `1000` | `1..=60000` | 单轮等游戏应答的超时 |
| `--completion-max-pages <N>` | `22` | `1..=256` | 单轮最多收多少页 |
| `--completion-max-replies <N>` | `1000` | `1..=100000` | 整场最多重放多少次（预算） |
| `--completion-cooldown-ms <N>` | `750` | `0..=60000` | 同一 `(client_ip, client_port)` 的去重窗 |

**约束（与实现一致，审计 H-2 纠正）**：

1. `--discovery-completion` **必须**与 `--sim-lan-listen IP` 一起用，否则**报错拒绝启动**（不是"忽略"）。
2. 与 `--simulate` 一起用 → **报错拒绝**（旧文档写"忽略 `--simulate`"，与实现相反）。
3. 与 `--sim-real-capture` 一起用 → **报错拒绝**（两条应答路径互斥）。
4. **必须显式给 `--reserve-62900`，否则拒绝启动**（旧文档写"无论是否显式都会强制生效"，与实现相反）。理由见 §5.3 第 0 步：绑 62900 会劫持游戏的单播应答（独立研究实测的 `SO_REUSEADDR` 陷阱）。
5. `--game-discovery-addr` 非 loopback → 拒绝启动（`--game-discovery-addr must be a loopback address ...`）。

### 5.2 数据结构（与代码一致）

```rust
struct CompletionState {
    /// 与游戏对话的专用 socket。必须绑 0.0.0.0：绑死某个 LAN IP 后
    /// send_to(127.0.0.1) 会报 WinError 10049（实测）。
    forward: UdpSocket,
    game_addr: SocketAddr,
    max_pages: usize,
    max_replies: u64,
    replies: u64,
    answered: BTreeMap<(u32, u16), Instant>,   // B-2 去重表
    cooldown: Duration,
    read_timeout: Duration,
    stats: CompletionStats,
}

struct CompletionStats {
    requests_intercepted: u64,
    replays_sent: u64,
    replays_failed: u64,
    pages_collected: u64,
    pages_forwarded: u64,
    forwards_failed: u64,
    timeouts: u64,
    empty_replies: u64,
    odd_page_sizes: u64,
    duplicate_magic: u64,      // B-2
    budget_exhausted: u64,     // B-2
    backlog_cleared: u64,      // B-2
    egress_pinned: u64,        // B-1
    egress_unpinned: u64,      // B-1
    egress_available: bool,
    pktinfo_enabled: bool,
    recv_errors: u64,
    last_recv_error: i32,
    probe_addr_seen: u64,
    probe_addr_missing: u64,
    last_probe_addr: String,
}
```

### 5.3 处理流程（与代码一致）

对监听端口 `L` 上收到的 4B magic，`from = client`，`probed = 该包到达的目的地址`（`IP_PKTINFO`）：

0. **预算**：`replies >= max_replies` → 计 `budget_exhausted`，不应答。
1. **去重**：`(client_ip, client_port)` 在冷却窗内 → 计 `duplicate_magic`，不应答。一次刷新 100 包因此塌缩成 1 轮。
2. **清残包**：`clear_backlog` 把转发 socket 里上一轮的残留页读掉并计数（防止串到下一轮）。
3. **重放**：`forward.send_to(MAGIC, game_addr)`；失败 → `replays_failed`，不应答（fail-closed）。
4. **收集**：循环收页直到 `max_pages` 页或**墙钟 deadline**（`Instant` 硬截止，与 `read_timeout` 共同作用，无关流量无法拖长）。
   - 只接受 `from == game_addr`（**IP + 端口**都相等，审计 H-1）。
   - 长度 `!= 1104` 计 `odd_page_sizes` 但仍转发（兼容版本差异）。
   - 超时 → `timeouts`；0 页 → `empty_replies`；**两种情况都不应答**（fail-closed，绝不伪造）。
5. **转发**：逐页 `L.send_to(page, client)`；若 `probed` 是可用 IPv4（非 unspecified、非 loopback）则用 `send_from(L, page, client, probed_ip)` 把源地址钉住，计 `egress_pinned`；失败或不可用则退回 `send_to` 计 `egress_unpinned`。
6. **占位**：attempt 在发页**之前**记入 `answered`，失败也占冷却位（防止重试放大）。

**为什么 loopback 探测时 `egress pinned = 0` 是正确行为**：探测目的地址是 `127.0.0.1`，一个源地址为 `127.0.0.1` 的包不可能离开本机，所以 agent 明确选择退回路由表并计数（自检断言 22 `unpinned` / 0 `pinned`）。

### 5.4 与现有 LanSimState 的关系

`LanSimState` 保留 fixture / real-page 两条旧路径。新增字段 `completion: Option<CompletionState>`；`poll` 的 magic 分支**最前面**插入 completion 分支（借用时用 `take()`/放回规避双重可变借用），命中即 `continue`，优先于旧的两条路径。

## 6. 客户端侧（不变，C2）

`civlink_client.dll` 的 `--iface <IP>`（`IP_UNICAST_IF`）继续负责"让广播从指定网卡出去"。**对 limited broadcast 生效已被独立研究四接口实测**。

## 7. 明确不做的事（边界）

1. **不缓存游戏应答**。实测内容确定性，但缓存会在"改 mod / 换地图 / 重建房"时返回过期内容。**每次现问游戏**。
2. **不伪造任何页**。游戏不应答时（超时/0 页）agent 静默，客户端表现为"这次没搜到"。
3. **不绑定 62900**。必须显式 `--reserve-62900`，避免劫持游戏单播。
4. **不处理 62056 数据面**。发现通了之后客户端"加入"会连 `房主IP:62056`。独立研究 A12 提醒"62056 才是第二道坎"，属 §9。
5. **不注入游戏进程**。房主侧零注入。
6. **反射放大（审计 H-3）**：1 个 4 B 包可换来 22 × 1104 B = **24,288 B（≈6,072×）**。这与旧 fixture 路径倍数相同（不是本轮引入），但 completion 让它**无需 `--simulate`**即可用，门槛更低。风险与缓解：需要与房主同广播域、每轮受 `max_replies`/冷却窗/预算约束；部署建议见 §9 第 4 条。

## 8. 不证明 / 未验证（审计 M 项要求补齐）

1. **跨机真实链路未验证**。全部是本机 loopback 证据（客户端在同一台机器）。跨机时 `from` 是真实 LAN 地址、回包走物理网卡——**必须 PC-B 复测**。
2. **真实 Civ6 客户端是否接受"源端口 = 请求目标端口"的应答**未验证（自写脚本 ≠ 游戏客户端）。
3. **22 页容忍丢 1~2 页**未验证。
4. **真实 Civ6 客户端 + 真实房间的端到端"能看到并进入"** 未验证（数据面 62056 完全未涉及）。
5. **多人（≥3 客户端）同时刷新**的串行化表现未验证（当前是单线程 poll）。
6. **同子网多归属 / 非对称路由 / 双默认网关**下源地址钉住是否都正确，未验证（本机三接口已验证，但其中没有 wifi + USB 以太网同网段的情形）。
7. **反射放大的实际影响**未做压力评估（只做了倍数计算）。
8. **长跑稳定性**未验证（自检最长 10 s）。

## 9. 后续（本设计之外）

1. 跨机验证（PC-B）—— 最高优先。
2. 62056 数据面：若客户端"加入"后卡在连不上，需要数据面转发（独立研究 A12/B3）。
3. 客户端侧是否还需要 `civlink_client.dll`（补全器解决了 100/100 命中后，钉网卡的价值下降，但虚拟网卡抢广播仍是独立问题）。
4. 反射放大的缓解：可考虑「只对最近 N 秒内确实发过广播的子网回包」或「按源 IP 做速率限制」，在 v1.0 之前应当评估。

## 10. 证据清单

| 文件 | 大小 | sha256 |
|---|---|---|
| `M0A\captures\C3-loopback-replay-20261118-2235\c3-probe-result-1.txt` | 4,080 B | `F03DADE4B0262207…` |
| 同上 `page-01.bin` … `page-22.bin` | 各 1,104 B | `DDC8CD34…` … `6F98152D…` |
| 同上 `summary.json` | 2,012 B | `3118D9AF37C95D7E…` |
| `M0A\captures\C3-fullchain-20261118-2240\log.txt` | 554 B | `B5DE376C63AFABDE…` |
| 同上 `summary.json` | 1,938 B | `BB185D192A8BA0A8…` |
| `M0A\captures\M0E-B2-probe-20261118-2350\B2-confirmation.txt`（修复前） | 1,760 B | `E2A4774B6B682C7E…` |
| `M0A\captures\M0E-B2-fixed-20261119-0002\`（修复后） | 目录 | — |
| `M0A\captures\M0E-B1-egress-20261119-0055\probe-wlan.json` / `probe-radmin.json` / `probe-zerotier.json` | 目录 | — |
| `M0A\captures\M0E-completion-20261119-003732\`（自检 45/45，42 文件） | 目录 | `verdict.txt` 555 B `E23B1D88EE5AA1FF…`、`manifest.txt` 2,887 B `195ACE7344CB46AA…`、`summary-run1.txt` 4,069 B `738DC37668CA0067…`、`summary-run4.txt` 4,068 B `9D64FB682277BDC6…` |
| `M0A\captures\M0E-mutation-20261119-003243\`（变异 5/5，13 文件） | 目录 | — |

脚本：`M0A\c3-loopback-replay-probe.py`（3,447 B）、`M0A\c3-capture-pages.py`（1,511 B）、`M0A\c3-fullchain-probe.py`（4,476 B）、`M0A\c3-source-embed-check.py`、`M0A\c3-b1-egress-probe.py`（2,823 B / `C68E57F80B6ED206…`）、`civlink\run-m0e-completion-selftest.ps1`、`civlink\run-m0e-mutation.ps1`。

**证据路径口径（按复审 REVIEW-2 N-1 勘误，v2.1）**：证据分布在**两处**，不能一概而论——① **审计仓库内** `CivLink-M0A-audit\M0A\captures\`：M0E-B2-probe-20261118-2350、M0E-B2-fixed-20261119-0002、M0E-completion-20261119-003732、M0E-mutation-20261119-003243（completion/mutation/B2 四个采信轮实际落在这里）；② **项目根** `C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\`：C3-loopback-replay/C3-fullchain/B1-egress（M0E-B1-egress-20261119-0055）/regress/C1/gui/hook-selftest-recheck 系列。v2.0 曾统一写"相对项目根"，与实际不符，已按 N-1 勘误。

## 11. 结论

- 机制在**真实游戏 + 本机 loopback** 上成立：1 magic → 1 重放 → 22 页真实广告 → 客户端从被探测端口收到。
- 三条审计阻断（B-1 源地址、B-2 去重/阻塞、H-1 校验）已修复并有专门断言与变异覆盖。
- **不得**据此宣称跨机可用、真实 Civ6 客户端可加入、E2-A/E2-B/E3 通过或 Gate A/B 移动。