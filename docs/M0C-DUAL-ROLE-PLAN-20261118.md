# M0-C 双角色联机助手（v0.4.6）— 计划与实施记录

- 版本：**1.0**（2026-11-18）
- 需求来源：用户 m26492（逐字）：「是否可以让这个联机工具同时具备两个功能：选择为客户端（A机器，房主）注入时，使其可以监听所有网卡下62900-62999共计100个端口，请一定注意62900是否会冲突的问题，请在最新版本修订。然后选择为客户端（B机器）注入时，可以定向选择使用的网卡，或者也可以使用全网卡？是否可行，给出完整建议及规划」
- 用户确认 m26578（逐字）：「1接受，2是的，3我是指由于建新房间会固定62900端口，注入的dll应该避免和62900端口冲突，使得出现注入后无法重新创建房间的状况」
- 项目：CivLink-M0A-audit（文明6局域网联机助手）；工作模式 m16220/m16222（每完成一步立即启子代理审计、并行下一步）

## 1. 需求分解

| 确认点 | 需求 | 对应改动 |
|---|---|---|
| 1（接受） | B 机（客户端/非房主）独立注入物 | C2：新建 `civlink_client.dll` |
| 2（是的） | 定向网卡 `--iface <IP>` 与全网卡 ALL 都要 | C2：`--iface` 三态（<IP> 严格定向 / ALL 不干预） |
| 3（澄清） | 62900 冲突 = 注入物不得阻塞游戏重新建房 | C1：agent `--reserve-62900`（已完成，见 §2） |

## 2. C1（A 机房主模式整合）— 已完成

### 2.1 根因（历史 bug m25442）

Civ6 局域网房主的发现 socket 固定 bind `0.0.0.0:62900`（DISCOVERY_FIRST）。若 Agent 先启动并绑满全部 100 个发现端口（62900..62999），游戏 bind 62900 失败（WSAEADDRINUSE），建房卡住。旧缓解=操作单人工保证顺序（先注入→再建房→后启动 agent），但「注入后无法重新创建房间」仍可能发生（用户 m26578 第 3 点）。

### 2.2 方案（--reserve-62900）

agent 新增 CLI 标志 `--reserve-62900`：

- 绑定循环跳过 `SIM_REPLY_PORT`（62900），把 62900 **永久留给游戏的房主 socket**；
- 应答源回退到第一个成功绑定的端口（62901..），summary 以 `reply source` 记录实际端口（S-2 既有机制）；
- 发现应答能力不损：客户端一次刷新=每个发现端口各 1 个 4B magic，agent 按 `(src ip, src port)` 去重，只需 99 个剩余副本中的任意 1 个到达即可应答 22 页；
- summary 新增状态行 `port 62900 : reserved, not bound`；
- stderr 在跳过时打印一条提示（`[!] LAN simulated host: <ip>:62900 reserved for the game host (--reserve-62900), not bound by the Agent`）。

### 2.3 代码改动（agent/src/main.rs，2921 行）

- `Args` 新增字段 `reserve_62900: bool`（含文档注释）；
- `parse_args`：默认 false + `--reserve-62900 => true`；
- **新增纯函数 `plan_discovery_ports(reserve_62900: bool) -> Vec<u16>`**（C1 审计建议 2 落实）：`(DISCOVERY_FIRST..=DISCOVERY_LAST).filter(|p| !(reserve_62900 && *p == SIM_REPLY_PORT))`，把"绑定哪些端口"从 `new()` 里抽出来，使该规则可被 `cargo test` 覆盖而不必占用 100 个真实端口；
- `LanSimState::new` 新增参数 `reserve_62900: bool`：进入循环前打一条 stderr 提示（`port 62900 reserved for the game host`），循环改为 `for port in plan_discovery_ports(reserve_62900)`；
- `LanSimState::new` 调用点传 `args.reserve_62900`；
- `summarize` LAN 块新增 `port 62900` 状态行；
- `--help` 文本新增说明段。

新增 3 个单元测试（`mod tests`，共 22 个 `#[test]`，`cargo +1.75.0 test --offline` 全绿）：

- `discovery_port_plan_binds_all_100_by_default`：不带 flag → 100 个端口、含 62900；
- `reserve_62900_leaves_the_game_host_port_free`：带 flag → 99 个端口、不含 62900、首端口 62901；
- `reserve_62900_only_drops_the_one_port`：两次计划的差集恰好是 `[62900]`。

### 2.4 验证（三组证据 + 22 个单元测试）

| 运行 | 结果 | 证据目录 |
|---|---|---|
| `cargo +1.75.0 test --offline` | **22 passed / 0 failed**（新增 3 项覆盖 reserve 端口计划） | 无产物（控制台） |
| `run-c1-reserve-selftest.ps1`（12 断言） | **PASS 12/12**（exit 0） | `M0A\captures\C1-reserve-selftest-20261118-0848-v2`（本轮采信；0111 为 `plan_discovery_ports` 抽取前版本，已被取代） |
| `run-c1-combo-selftest.ps1`（新脚本，14 断言，审计建议 3 落实） | **PASS 14/14**（exit 0） | `M0A\captures\C1-combo-selftest-20261118-0848` |
| `run-f5-lan-selftest.ps1`（回归，12 断言） | **PASS 12/12**（exit 0） | `M0A\captures\C1-f5-regression-20261118-0115`（默认行为无回归） |

C1 reserve 证据关键值（0848-v2 采信轮）：

- `port 62900 : reserved, not bound`；
- **`requests seen : 99`**（62900 那一包无监听者被内核丢弃，正是留给游戏的槽位）；
- `replied sockets : 1` / `pages sent : 22`（去重后一次 22 页应答）；
- **`reply source : 127.0.0.1:62901`**（回退端口，非 62900）；
- `send fail / no endpoint / max reached / bind fail 全 0`；
- **`bind 127.0.0.1:62900 SUCCEEDED`（agent 运行时游戏槽位仍可绑定 = 建房永不阻塞，第 11 项断言）**；
- 客户端收到 22 页 1104B，magic `59 60 69 9B`，房名 `CivLink-Test-Room-2222`。

C1 组合证据关键值（combo 轮，14 断言，证明各模式可叠加）：

- 同一进程同时启用 `--reserve-62900 --sim-real-capture --forward-listen 21397 --sim-lan-listen 127.0.0.1 --simulate`，**exit 0**，stderr 只有一行 reserve 提示；
- 发现仍被应答：`seen 99 / replied 1 / pages 22`，客户端收 22 页、房名 `CivLink-Combo-2222`；
- B1 捕获段 `captured 0 / active: no`（只有一次发现突发，不会凭空造出真实广告页）；
- F3-A 转发监听段 `listen port 21397 / payloads recv 0`（开了监听但无转发目标，未动任何数据）；
- `send fail / no endpoint / max reached / bind fail 全 0`，62900 仍可被测试自身绑定；
- **`Get-NetUDPEndpoint` 实测 agent 进程在 62056 上 0 个端点**（第 12 项断言，运行中检查而非读日志）；
- `lan-page-01..22.bin` 全部落盘、`forward-log.txt` 已创建。

脚本第 2 项断言只允许 stderr 含 reserve 提示一行；客户端 `Receive` 已捕获 WSAECONNRESET 10054（测试自己关闭 62900 探测 socket 后，突发的 ICMP port-unreachable 会在 Windows 客户端 socket 上冒出来——测试假象，非 agent 缺陷，已 try/catch 跳过）。组合脚本另修正一处测试侧缺陷：房名字段是 22 字节定长且**尾部补空格**，必须 `.Trim()` 后再比对（首跑 FAIL 7 即此原因，非产品问题）。

### 2.5 文件身份（审计建议 2/3 落实后终值，2026-11-18 08:48）

- civlink\agent\src\main.rs：**2,921 行 / 127,146 B / sha256=E556B66F864D492763F944549E5BEC4F001CE3CD85B05D22910C38D374D6C4C2**
- civlink\agent\Cargo.toml：525 B / 版本 **0.4.6** / **sha256=6F70562D5CD78FE8356CE8161FBEF730B3A67176EA30A8B17C126A7C187554A5**（C1-MUST-1 版本号一致修正：注释/--help/Cargo/二进制统一 0.4.6）
- civlink\run-c1-reserve-selftest.ps1：11,562 B / **sha256=CA8F6599CD411E4DF1CD784B423F22CBF5FC260491675265173890E150C8C1BE**（审计 S-1/S-5/S-6/S-7 修正后；本轮未改动）
- civlink\run-c1-combo-selftest.ps1（新）：12,950 B / **sha256=70D17397FE139D0BC50148C1E249D9D35DC0C5CE2A3C016801E809EABE01B0D9**（审计建议 3 落实）
- civlink\civlink-agent.exe（release，已同步）：**421,376 B / sha256=4390AF9DF56AE9085BB9384E2EDAC0E3C4BAE27CA20B2E92799D895064E7792C**，`--version` 输出 `civlink-agent 0.4.6`
- 审计修正记录（C1 审计 35286c89 裁定=有条件通过，必改 C1-MUST-1 + 建议 S-1/S-4/S-5/S-6/S-7/S-8 已落实）：Cargo.toml 0.3.0→0.4.6；脚本 5 处 edit（Assertions 10→12、StandardOutputEncoding×2=UTF8、bind probe 移至 burst 后（S-7）、10054 双级 ErrorCode 检查（S-1）、L18 注释更正）；main.rs 2 处（--help 注 reserve 仅 --sim-lan-listen（S-4）、summary L2155 注释补 reserve 触发条件（S-8））。**S-2（单元测试）与 S-3（组合验证）本轮已落实**（见 §2.3/§2.4），仅 S-8 的"文案精度"作为余项保留。
- 证据（采信轮）：`M0A\captures\C1-reserve-selftest-20261118-0848-v2`（PASS 12/12，exit 0，summary 2,893 B / `23350588A54A2ACC1E16C13E08E0C47F6B21508654B65B2A6CA32A643A63DB58`，result 550 B / `6E2CC74C8ECCBE5CC59E4F2E433BD05D9B0446729C2FBEC94A9E0B26208DB427`，port-62900-bind-check 66 B / `51DCBCEB227A82DC6637C5752C60A609D66CA879156145DCF68B9465A5AD7EF6`，agent-stderr 109 B / `C92E6AA834798D2F7E862A995F13C134EE604C0138AA061D76CD42A130E2C39C`）；`M0A\captures\C1-combo-selftest-20261118-0848`（PASS 14/14，exit 0，summary 3,565 B / `675B26BA7D5E1231C75EC881886AE9B234C1C293A53FFDB4CE8CF5456F92203E`，result 860 B / `DC0FC3F67094E2F0B80BA2D743AA4981899F8CE6144DB1E9879C131737D1A148`，port-62056-check 41 B / `A49A8C964EA8DD4FF231D2599E6DA071DEBF1D120645726287D2107E0A11F18A`，forward-log 96 B / `8339125E9A226A271C701A85D5A4E43F47BBD292759DCC3E2F6FEAFDFCFEFC4C`）；回归 `M0A\captures\C1-f5-regression-20261118-0115`（PASS 12/12，port 62900 bound by Agent/seen=200/replied=2/pages=44/send fail=0/bind fail=0/exit=0）。
- 两份 result.txt 均已注明 loopback only、NOT real two-machine，且列出不证明的范围（真实 Civ6/真实对端/E2-B/E3/Gate A/C2 跨机）。

## 3. C2（B 客户端定向网卡）— 已实施（单机自检通过，跨机未验证，审计中）

### 3.1 需求（m26578 第 1、2 点）

- B 机（非房主）注入独立 DLL `civlink_client.dll`；
- `--iface` 三态：`<IP>` 严格定向到指定网卡 / `ALL` 全网卡不干预（默认）。

### 3.2 背景（m26492 现场事实）

B 的 255.255.255.255 发现广播由 Windows 按 InterfaceMetric 最小接口发出：B 机 Radmin=1（已调 200，WLAN 靠前）→ 调 metric 前广播走 Radmin 26.187.101.177，A 机在 WLAN 收不到；调后 WLAN=40 靠前。但 metric 是**系统级**设置，需要管理员权限且影响全局。C2 提供**进程级（注入物内）**定向：不动系统 metric，让 B 游戏进程的发现广播从指定网卡发出。

### 3.3 技术方案（方案 B + C 兜底）

- **方案 B（主）**：对发现目标（dst 端口 62900..62999 或 255.255.255.255）的 `sendto/WSASendTo`，在调用原始函数前对 socket 设置 `IP_UNICAST_IF`（setsockopt 第 **31** 项（IP_UNICAST_IF，ws2ipdef.h；25 是 IP_RECVDSTADDR，C2 设计 f1d5a016 勘误），参数=接口索引 IPv4 字节序），使广播从指定网卡发出；`--iface ALL` 时不做任何干预（纯透传）；
- **方案 C（兜底）**：当定向网卡与目标广播出口不一致、且探测到广播无法到达对端时，把原广播数据包复制后从定向网卡再发一份（转发兜底，不篡改原包）。设计文档先写明机制边界，是否实现取决于 B+C 组合是否足够（先实现 B，实测后再定 C）。
- **最小实测结论（2026-11-18，本机无管理员+PC-B 离线）**：Windows 本机广播不回环到绑 0.0.0.0 的 socket（agent --sim-lan-listen 0.0.0.0 收本机 255.255.255.255:62900 广播 seen=0，单播 127.0.0.1 seen=100）；计数器法（Packets Sent/sec）对虚拟接口（Radmin/ZeroTier）不计数且噪声大；pktmon 需管理员（当前非提权不可用）。IP_UNICAST_IF 的实际出接口效果**待 PC-B 恢复后按 C2 设计 §3.3 三步法跨机实测**，DLL 实现按 IP_UNICAST_IF+运行时无效则降级（方案 C 兜底）。
- **配置传递**：注入物在游戏进程内，无法接收命令行参数 → 由注入器（civlink_ctl 新子命令或 civinject 改造）把 `--iface` 值写入一个配置文件（如 `%LOCALAPPDATA%\CivLink\client-iface.txt`），`civlink_client.dll` 的 InitThread 读入全局。

### 3.4 C2 改动清单（预计）

1. 新建 `civlink\client\civlink_client.cpp`（复用 hook.cpp 的 detour 骨架：sendto/WSASendTo + 发现目标判定；**不含** ForwardFrame/IPC/62056 数据面逻辑——客户端注入物只做网卡定向）；
2. 复用 `common\civlink_hook.h` 导出命名（CivLinkHookState/CivLinkShutdown/CivLinkGetCounters/CivLinkSessionId 同构，避免工具链混淆）；
3. 配置文件读取 + `--iface` 解析（IP 或 ALL）；
4. `civlink_ctl` 新增子命令 `inject-client`（或扩展 inject 带 `--iface`）写配置+注入；
5. 自检脚本：双网卡模拟（loopback + 本机另一接口）验证广播出接口被定向；
6. 文档+审计闭环（C3）。

### 3.5 边界（写入最终文档）

- C2 是**进程级定向**，不动系统 InterfaceMetric（m26146 已调 metric 属独立操作，恢复方式见网络环境脚本备份）；
- 机械证据 ≠ 双人验证；不勾 E2-A/E2-B/E3；不证明跨网/Relay/加密。

### 3.6 实施结果（2026-11-18，单机；已按第一轮审计修正）

改动清单第 1-6 项全部落地。**第一轮审计（`docs\M0C-C2-REVIEW.md`，271 行 / 37,556 B，"有条件通过"）要求修正的 3 阻断 + 4 高危 + 7 中危及若干低危已全部处理**，详见 §3.8 修正对照表。

1. `civlink\client\civlink_client.cpp`：复用 hook.cpp 的 detour 骨架，保留全部 6 个 detour（sendto/WSASendTo/closesocket/bind/recvfrom/WSARecvFrom）**只对发现目标做 `setsockopt(IP_UNICAST_IF)`，其余全部纯透传**；不含 ForwardFrame/IPC/cvlh2/EnsureLocalEndpoint。修正后关键语义（审计 B-1/M-6）：
   - **不再缓存"已 pin"标记**：原设计在 `Hook_bind` 建槽、只 pin 一次；实测证明未 bind 的 socket 永远建不了槽（`FindOrCreateSlot` 只在 bind 里调），导致 `sent` 语义分裂。现改为**每个发现发送都幂等设置一次**（~1µs/包），彻底消除"隐式 bind 是否清除该选项"的时序不确定性；
   - `sent` 重定义为「`setsockopt` 被接受的发现发送次数」，`sendFail` = 设置失败次数（仍透传），`ignoredNonDiscovery` = 未尝试 pin 的发送次数（非发现目标或 state 未就绪）；
   - **`WSAGetLastError` 在设置前后保存并恢复**（审计 B-2，成功/失败两条路径都恢复），保证不污染应用可见的 last error；
   - `scatterGather`（多 buffer 的 WSASendTo 次数）与 `sockTableOverflow`（槽表 64 满次数）改为**真实计数**（审计 M-1/M-5），不再硬编码 0；
   - 4 个 detour 的原始调用移入 `g_inFlight` 窗口内（审计 H-1），shutdown 的 5 秒排空保护才真正有效；
   - `WSASendTo` 不再排除 overlapped 调用（审计 H-2）；
   - 新增诊断配置 token `IFINDEX:<n>`（按裸接口索引定向，仅自测/支持用）。
2. `civlink\common\civlink_client.h`：复用 `CivLinkHookState/CivLinkShutdown/CivLinkGetCounters/CivLinkSessionId` 四个导出名与 `CivLinkCounters`（magic/version 不变，ABI 未动），另定义 `CIVLINK_CLIENT_VERSION "0.1.0-c2"`、`CIVLINK_INITERR_CONFIG_INVALID 11`、`CIVLINK_INITERR_IFACE_UNAVAIL 12`（两者都**非致命**：fail-open 降级 ALL，DLL 照常加载）。
3. 配置读取：`%LOCALAPPDATA%\CivLink\client-iface.txt` 单行 ASCII（`ALL` / IPv4 / 诊断 token `IFINDEX:<n>`）；可用环境变量 `CIVLINK_CLIENT_IFACE_FILE` 覆盖为绝对路径（正式特性，见 §3.7）；`ResolveIfIndexForIp` 用 `GetAdaptersAddresses(AF_INET)` 15 KB×3 重试 + `OperStatus == IfOperStatusUp` 过滤 + `inet_pton` 精确比对。
4. `civlink_ctl` 新增 `inject-client` 子命令 + `-m <dllname>` + `--iface <IP|ALL>`（默认 ALL）。修正（审计 H-3/H-4）：
   - 非本地 IP / 接口 down → **fail-closed 拒绝，exit 1**；
   - **loopback（`IF_TYPE_SOFTWARE_LOOPBACK`）也拒绝**，并提示 `loopback is not a real egress choice; use ALL or a physical/virtual NIC`——第一轮的"定向真实网卡"证据实际钉在 loopback 上，已更正；
   - 解析成功打印 `[+] interface selected: <FriendlyName> (IfIndex=N IfType=N metric=N)`；
   - 写配置**挪到 `ResolveTarget` 成功之后**（目标不存在时不留半配置），写前打印 `[*] resolved by: env override / default` 并提醒"shell 里的覆盖变量不会传进已注入的游戏进程"。
5. `civlink\selftest\client_selftest.cpp`：**一进程一场景**（argv[3] = A|B|C|D|E|F|G|H|I，共 9 场景）。这不是风格选择而是硬约束——DLL 一旦 `CivLinkShutdown` 就不能在本进程复活（MinHook 保持初始化的 B2 审计运行模式契约）。新增机器可读输出 `counters: sent=.. ignored=.. sendFail=.. initError=.. bind62056=.. sockOverflow=.. scatterGather=.. session=..`，供外层脚本断言（审计 B-3 要求，替代原来"匹配自己打印的 PASS 串"的零判别力断言）。
6. `civlink\run-c2-iface-selftest.ps1`：标题改为 **`C2-BOOKKEEPING-SELFTEST`** 并在头尾明写 `Egress adapter: NOT VERIFIED`；断言数 45 条。

**自检证据（采信轮）**：**`M0A\captures\C2-iface-selftest-20261118-0945`（29 文件，采信轮；`-0928`/`-0924` 为 ctl 自动探测修复前的旧二进制配套证据，仅留档），`C2-BOOKKEEPING-SELFTEST: PASS (45/45 runner checks, 60 in-process)`，exit 0**。`result.txt` 1,473 B / `1CAFEFEAF6FF91ECBDC77762A26CA3C33330907A319BB3FB4C2CB5E40848634B`；`scenario-c.txt` 1,019 B / `9CADB4305052F1884CA7CDE42E019E5ECF959A400C1EE83A2D235E17ED9F9A49`；`scenario-i.txt` 684 B / `D267280B57B9B2769C66BEE9D67C28DDA937D3C7C3690EA403494D2583D38A17`；`scenario-h.txt` 753 B / `0C2B680A5048F44EC94AF15A04C88DBB791E53D95EF1143AC0484E24BCF4ED7E`；`ctl-t2-all.txt` 840 B / `7F975EB37928E05D092229B25E23A5F1068FDAECF307F988ED4D07B8AD26FB88`；`ctl-t3-pin.txt` 877 B / `46439577497697F991E4F2A9FB19CB89A18A6D249CE70505BF921A403B3041F2`。

| 场景 | 断言 | 关键实测值 |
|---|---|---|
| A 无配置（默认 ALL） | 9 | `state 1` / `initError 0` / `sent 0` / `ignored 8` / `sendFail 0` / `shutdown 0` |
| B 无效配置 | 6 | `state 1`（仍加载）/ **`initError 11`** / `sent 0` |
| C PIN（从**已 bind** socket） | 10 | `initError 0` / 14 次发送全返回 4 / **`sent 10`** / `ignored 4` / `sendFail 0` / 非 C2 计数器全 0 / **`bind62056 0`** / `shutdown 0` / 二次 `shutdown 1` |
| D 显式 `ALL` | 6 | 同 A（零干预） |
| E 空配置文件 | 6 | 同 A（缺失/空 = ALL） |
| F 多行取首行 | 7 | `sent 6` / `ignored 2` |
| G `192.168.99.99` | 5 | **`initError 12`**（非本地 IP，fail-open） |
| H `IFINDEX:2147483647` | 6 | `sent 5` / `ignored 3` / **`sendFail 0`**（见下方"推翻的假设"） |
| I 槽表溢出（80 个已 bind socket） | 5 | **`sockOverflow 16`**（64 槽 → 16 次溢出被真实计数） |

`ctl` 用例：T1 非本地 IP `10.255.255.1` → 拒绝 exit 1；**T1b loopback `127.0.0.1` → 拒绝 exit 1**（审计 H-4）；T2 `--iface ALL` → 配置写 `ALL`；T3 真实非 loopback 适配器（实测选中 **192.168.191.3**）→ 配置写该 IP。

**★ 本轮推翻的一条审计建议（记录在案）**：审计要求加一条"能失败"的断言（用非法 ifIndex `0x7FFFFFFF` 期望 `sendFail>0`）。实测 Windows 上 `setsockopt(IP_UNICAST_IF)` 对越界索引**返回 0 并接受**，广播照常发出 → 场景 H 得 `sent=5 / sendFail=0`，该断言不成立。判别力改由**场景 I（槽表溢出，`sockOverflow=16`）**承担：这是当前唯一"如果实现错了就会红"的断言。

**产物身份（当前磁盘，全量重建后）**：`civlink_client.dll` 149,504 B / `0BCC4C1DE6AD8B5E6EC3A13B1F38FDCCD13C9268E651B7B04A73A3051702C6D4`、`civlink_ctl.exe` 188,416 B / `8B9A9AF89A652434EC10CA47DFE5DEE34BCE864C3FE539DD737A2B09819ACA22`、`client_selftest.exe` 181,760 B / `0AAA32EA61C9568FC1213C0E5744A9A2D40BBD09B16B41A63F14C588530972BE`、`civlink_hook.dll` 119,808 B / `AD14C6C3F2E520B8F3559132EA8C9029AC7413FEC6CD53447D9E90FB52957140`、`hook_selftest.exe` 150,016 B / `ABF018A20AEF4FC76533ED63F21A511546A0BB9B5AF4224AB1E75B255C44805F`。**hook 侧回归**：`hook_selftest.exe` → `HOOK-SELFTEST: PASS (0 failure(s))`，exit 0。**源码身份（本轮修正后）**：`civlink\ctl\civlink_ctl.cpp` 30,658 B / `22EFEF52C19EDA8C1352F6B6B20ECEDFADE564D0AD447FAA2FBB032EC5584241`（09:21:16，含 §3.9 的自动探测修复）、`civlink\client\civlink_client.cpp` 24,334 B / `D617BFC3DAC183FDBE921E73A45F2831B1B6B8685A7FB6A082670645406E6CE7`（08:58:09）、`civlink\selftest\client_selftest.cpp` 20,113 B / `45CF96F539556504412D5BD9E1E0297B32A329A35B55FC52655CB73AA0487DC7`（09:06:20）、`civlink\run-c2-iface-selftest.ps1` 14,568 B / `EBD727E4A3B7888F59EBC07975A6516449853460C7DB43D630B79455C73753F3`（09:13:38）、`civlink\common\civlink_client.h` 1,535 B / `4AD103A0400F9F692A8E4C5EDF08F647B93BB6261A9F0A47C86106B0B0C7B96F`（01:30:20，未改）、`civlink\build-msvc.cmd` 6,105 B / `63FBEE7368AB2D479D064074BE20C700C338CA9515D7F5A984E94E10C017EFB0`（08:32:39，未改）。**构建序自洽**：产物 mtime（09:22 段）均晚于对应源码（08:58:09 / 09:06:20 / 09:21:16）。

**本轮自检证明了什么 / 没证明什么**（已同步写进 `result.txt`、每个场景尾部、设计文档 §7.3/§8）：
- **证明**：计数器语义自洽；ALL 模式零干预；PIN 模式只对发现目标设置 `IP_UNICAST_IF` 且不做其它改动；无效配置 fail-open 不阻断；配置缺失/空/显式 ALL/多行/非本地 IP 五条分支行为正确；clean drain 且二次 shutdown 幂等；槽表溢出被真实计数；全程不碰 62056；sendto 返回值未被吞。
- **没证明（关键）**：**实际出口网卡是否被改变**。本机 Windows 广播不回环（agent 观测 seen=0）、`Get-Counter` 的 `Packets Sent/sec` 对虚拟接口不可靠、pktmon 需管理员。设计文档 §7.3 第 4 项仍标 **uncovered**。**因此 C2 不得表述为"已验证"**；该命题只能由 PC-B 恢复后的跨机抓包回答，且真实 Civ6 进程内注入路径至今**一次都没成功执行过**（ctl 用例只到"目标进程不存在"分支）。

### 3.7 实施中发现的既有问题（非 C2 缺陷，但已固化为正式特性）

`civlink_ctl.exe` 在**工作区路径下**运行并写 `%LOCALAPPDATA%\CivLink\client-iface.txt` 时恒失败（`errno=13 / lastError=5`）；把**同一个文件**拷贝到 `%TEMP%` 或桌面目录运行即成功；一个最小 C 探针在工作区内写工作区文件成功、写 `%TEMP%` 与 `%LOCALAPPDATA%` 均 `errno=13`。这是 DSH 文件沙箱对"工作区内派生进程 → 工作区外写入"的限制，不是 CivLink 的缺陷（exe 属性、备用数据流 `:$DATA`、哈希均一致）。

因此把路径覆盖做成了**正式能力**：`CIVLINK_CLIENT_IFACE_FILE` 环境变量（绝对路径）优先，缺失时回落 `%LOCALAPPDATA%\CivLink\client-iface.txt`。注入器与 DLL 两侧共用同一变量，所以配置读写永远落在同一处。**真实部署下用户无需设置该变量**；自检脚本用它把配置关进证据目录。**注意（审计 H-3）**：DLL 在游戏进程内读配置，从 shell 设置的覆盖变量不会传入已注入的游戏，所以正式路径仍然是 `%LOCALAPPDATA%`；ctl 每次都会打印 `resolved by: env override / default` 以免误判。

### 3.8 第一轮审计修正对照表（B-1..B-3 / H-1..H-4 / M / L）

| 编号 | 第一轮问题 | 本轮处理 |
|---|---|---|
| B-1 | `pinned` 位对未 bind 的 socket 永不生效，`sent` 语义分裂 | **已修**：删除 pinned 位与 `SlotIsPinned`/`SlotMarkPinned`，改为每包幂等 setsockopt；`sent` 重定义并在设计 §4.3 登记理由（M-6 时序风险） |
| B-2 | setsockopt 覆盖 `last error`，违反"同 last error"硬约束 | **已修**：`WSAGetLastError()` 保存 + `WSASetLastError()` 恢复（成功/失败两路径） |
| B-3 | 证据效力不足（10 条自指断言、主判据未实现、§7.3 第 3 项与实测矛盾） | **已修**：标题降级 `C2-BOOKKEEPING-SELFTEST`、删自指断言改解析 `counters:` 行、§7.3 改 covered/uncovered/contradicted 逐条标注、`ignoredNonDiscovery==0` 更正为 `==4` |
| H-1 | 4 个 detour 在真实调用前递减 `g_inFlight`，shutdown 排空保护失效 | **已修**：真实调用移入窗口内，重入分支同样覆盖 |
| H-2 | overlapped `WSASendTo` 被排除在 pin 外 | **已修**：去掉 `!ov` |
| H-3 | `CIVLINK_CLIENT_IFACE_FILE` 未登记 / ctl 侧不传递 / 写配置时序 | **已修**：设计 §5.1 登记为正式特性并写限制；ctl 打印 `resolved by`；写配置挪到 `ResolveTarget` 之后 |
| H-4 | ctl 预校验接受 loopback | **已修**：拒绝 `IF_TYPE_SOFTWARE_LOOPBACK`；T3 改用真实适配器 192.168.191.3；新增 T1b 用例 |
| M-1 | 槽表 64 满静默失败、`sockTableOverflow` 硬编码 0 | **已修**：`FindOrCreateSlot` 满表 `c_sockOverflow++`，场景 I 实测 16 |
| M-2 | `LoadConfig` 的 ALL/空/多行三分支零覆盖 | **已修**：场景 D/E/F |
| M-3 | `initError==12` 无证据 | **已修**：场景 G 实测 12 |
| M-4 | 设计 §4.3 initError 编号表错 | **已修**：按 `civlink_client.h` 更正为 0/1/2保留/3=MH_Initialize/4..9=CreateHook/10=EnableHook/11/12 |
| M-5 | `scatterGather` 硬编码 0 | **已修**：`count>1` 时真实累加 |
| M-6 | "只 pin 一次"时序未论证 | **已修**：改每包设置，风险消除（写入设计 §8 不确定项） |
| M-7 | 证据"passing for the wrong reason"未披露 | **已修**：`result.txt`/设计 §7.3/§8 明写只到记账层 |
| L-1..L-9 | 无 WSACleanup、子网定向广播未识别、ALL 模式 ignored 语义、`CivLinkSessionId` 无测试、`WaitReady` 不早失败、`CIVLINK_SKIP_CLIENT_DLL` 复用旧 dll、`prev==0` 不调 MH_DisableHook、§5.1 示例与实现不符 | **部分/有意保留**：L-5 已由场景 A4 覆盖；L-3 已在设计 §4.3 登记（`ignoredNonDiscovery` = "未尝试 pin 的发送"，ALL 模式下也累加）；`§5.1` 示例已按实现重写；其余（L-1/L-2/L-4/L-6/L-7/L-8/L-9）**未修，待复审判定是否必须在 C3 前关闭** |

### 3.9 真实进程内注入冒烟（2026-11-18 09:16–09:23，首次成功）

第一轮自检与被审计的 45 条断言**全部在"测试进程自己加载 DLL"的环境里跑**，`civlink_ctl` 的三个用例又都止于 `target process not found` exit 2 —— 也就是说**整条注入路径一次都没被真正执行过**。本轮补上，宿主用 `powershell.exe` 代替游戏进程。

详情见 **`docs\M0C-C2-INJECT-SMOKE-20261118.md`**（131 行 / 9,312 B / `64EB40CE4BB47A230C20E43599D9A2352581D8AD8C35A9F40AA6C83C23BAC959`）。要点：

1. **两个非产品障碍**：工作区内派生进程 `OpenProcess` 恒 `err=5`（与 errno=13 同类，DSH 沙箱限制；同文件复制到 `%TEMP%\c2inject\` 即成功）；Win11 记事本进程名是 `Notepad` 而非 `notepad.exe`。
2. **注入成功**：`LoadLibraryW returned 0xfc840000` / `hooks active (CivLinkHookState=1)` / exit 0。
3. **三轮计数对照（决定性）**：A 轮 shell 设 `CIVLINK_CLIENT_IFACE_FILE` + PIN → `sent=0 / ignored=14 / initError=0`（**H-3 现场复现**：变量不传入目标进程，DLL 回落默认路径读到 `ALL`，看似成功实则定向未生效）；B 轮默认路径 + PIN → **`sent=10 / ignored=4 / raw sendto=14 / sendFail=0`**；C 轮默认路径 + ALL → `sent=0 / ignored=14`。
4. **发现并修复的产品缺陷（中）**：`status`/`counters` 未给 `-m` 时用默认 `civlink_hook.dll` 解析本地导出 RVA，对 client 注入的进程报 `cannot resolve CivLinkHookState` exit 1，用户会读成"注入失败"。**已修**：`OpenProcess` 后自动探测目标加载的 CivLink 模块（hook 查不到再查 client），命中则切换并打印 `[*] target has civlink_client.dll loaded - using it (override with -m)`；复验 `status`/`counters` 均无需 `-m`、exit 0、`sent 10 / ignored 4`（证据 `C2-inject-smoke-20261118-0940`：`status-auto.log` 672 B/`613FADC5…`、`counters-auto.log` 1,928 B/`09A779F2…`、`inject.log` 1,768 B/`92D19408…`）。
5. **仍没证明**：广播是否真从选定网卡发出（本机不回环）、能否注入真实《文明6》进程、长跑与共存。**不得据此勾 E2-A/E2-B/E3，不得把 C2 表述为已验证。**

> 因 4 的修复改了 `civlink_ctl.cpp`，五个产物全部重建，`-0928` 那轮证据对应的二进制已作废，故 §3.6 的采信轮已更新为 `C2-iface-selftest-20261118-0945`（同为 PASS 45/45）。

## 4. C2 跨机实测（唯一能回答核心命题的一步）— 待执行

操作单已写：`docs\M0C-C2-CROSSMACHINE-RUNBOOK-20261118.md`（8,147 B / `E786058A8C276441B6CD7FB62D0B7C3E08346CDB2E26B1AF508D5CDDEDA2CC27`，145 行）。

**判据设计要点**（不依赖计数器或抓包）：把他机发现广播**钉到非默认接口**（B 的 Radmin，metric 200 > WLAN 40），然后在 A 侧 agent 的发现日志里看**源 IP**——
- 源 `26.187.101.177`（Radmin）= `IP_UNICAST_IF` **生效**，方案 B 成立，不需要方案 C；
- 源 `192.168.31.214`（WLAN，与不干预时相同）= **不生效**，触发方案 C（广播复制转发）。
三轮对照：轮 1 `ALL`（基线）/ 轮 2 pin Radmin（关键）/ 轮 3 pin WLAN（反向，证明无副作用）；每轮之间必须重启游戏进程（配置只在 DLL 初始化时读一次）。

**当前阻塞**：PC-B 于 2026-11-18 09:15 实测离线（`Test-Connection 192.168.31.214` → False）。另外真实《文明6》进程内的 `civlink_client.dll` 注入路径**至今一次都没成功执行过**（ctl 三个用例止于"目标进程不存在"或 `OpenProcess failed err=5`），连"能否注入进游戏"都未验证。这两项完成前 C2 **不得**表述为"已验证"，也不得据此关闭 E2-A/E2-B/E3。

## 5. C3（文档登记）— 待做（前置：C2 复审通过）

- README 版本行 + 状态行 + 修订记录块（v1.33 或按版本链）；
- CODEX-HANDOVER 第 20 项（或并入第 19 项）；
- M0-C 审计任务书 + 子代理审计 + 复审。**任务书已写**：`docs\M0C-AUDIT-BRIEF-20261118.md`（139 行；按登记链单向引用纪律，本文只按文件名引用、不嵌其哈希，哈希由任务书自身与审计报告记录），含 11 个源码 + 6 个产物 + 6 个文档的实测哈希（**写入前全部逐条复核过 `OK`**）、硬约束 6 条、C1 六问 / C2 逐条关闭表 / 增量三问、明确排除项、输出格式要求（裁定 + 逐条表 + 增量裁定 + 新发现 + 是否允许进 C3 + ≥6 哈希抽查）、已知无需重复发现的 4 条。
- **前置脚本已备（2026-11-18 09:30 新增，尚未执行过）**：`civlink\run-c2-real-game-check.ps1`（198 行 / 8,990 B / `8E83FF8B15986D48932146F9135FC151A528E117CF0F545C5E58FA150415639B`）——真实《文明6》进程内注入检查。自动找 `CivilizationVI_DX12`/`CivilizationVI` 进程 → 把二进制复制到 `%TEMP%\civlink-realcheck\` 运行（工作区内 `OpenProcess` 恒 err=5）→ 注入 → `status`/`counters` → 解析断言 → 写 `game-state.txt`/`verdict.txt`。**取舍**：它只证明"能注入真实游戏进程且计数可读"，**不证明**广播出接口、不证明建房/加入仍可用、不证明长跑；verdict 里写死了这条边界。语法已校验、无游戏时的前置分支实测 exit 1。**待游戏运行时由用户执行一次。**

## 6. C4（结案）— 待做

- E2-A/E2-B/E3 结案 + Gate A 复核（PC-B 恢复后）。

## 7. 审计状态

- **C1 审计（35286c89）已返回：有条件通过**，必改 C1-MUST-1 已关闭（Cargo/--help/二进制统一 0.4.6），建议 S-1/S-4/S-5/S-6/S-7/S-8 已落实，S-2/S-3 本轮落实（§2.3/§2.4）；→ `docs\M0C-C1-REVIEW.md`（10,263 B / `83CD5327…`）；
- **M0-B 登记链复核（37cd845b）已返回：有条件通过**，唯一必改 M-必改-1（HANDOVER L151 过时哈希）实测已自愈；→ `docs\M0B-REGISTRATION-REVIEW-20261118.md`（16,433 B / `7C499CEA…`）；
- **C2 第一轮审计（`60210208-077f-4474-9904-63d81c72b2c3`）已返回：有条件通过** → `docs\M0C-C2-REVIEW.md`（271 行 / 37,556 B / `4E40F292…`）。列 3 阻断（B-1 语义分裂 / B-2 污染 last error / B-3 证据效力不足）、4 高危（H-1 排空窗口 / H-2 overlapped 漏 pin / H-3 配置路径 / H-4 loopback）、7 中危、9 低危。**已全部按 §3.8 处理（低危部分保留）**；
- **C2 复审（`2fbcb7f2-f68b-47b7-8edc-3c94cc2f34e6`）运行中** → `docs\M0C-C2-REVIEW-2.md`。**复审通过前不得宣布 C2 验收通过，也不得进入 C3 登记。**
- **复审必须覆盖的增量（09:16 之后产生）**：①`civlink_ctl.cpp` 的自动模块探测（§3.9 第 4 点），它改了产物哈希，故采信轮由 `-0928` 更新为 `-0945`；②真实进程注入冒烟（`docs\M0C-C2-INJECT-SMOKE-20261118.md`），它把"注入路径从未执行"这一缺口关闭到"powershell.exe 宿主层面"，但仍**不含真实 Civ6 进程**；③设计文档 v2 更正（`M0C-C2-DESIGN-20261118.md` 470 行 / 40,649 B / `94219C2B…`）；④真实游戏检查脚本（§5 末条）。**增量已用 send_message 通知复审子代理，它需在报告里逐条给出裁定。**

## 8. 执行记录

| 时间 | 动作 | 结果 |
|---|---|---|
| 2026-11-18 00:54-00:58 | C1 代码改动 + 构建 + 两组自检 | PASS 12/12 + PASS 12/12 |
| 2026-11-18 01:0x | C1 审计子代理派出→返回 | 有条件通过（MUST-1 已关闭） |
| 2026-11-18 08:34 | C2 单机自检（A/B/C 三场景 + ctl 三用例） | PASS 25/25 exit 0 |
| 2026-11-18 08:48 | C1 建议 2（`plan_discovery_ports` + 3 单测）/ 建议 3（combo 脚本）落实 | cargo test 22 passed；combo PASS 14/14；reserve 重跑 PASS 12/12 |
| 2026-11-18 08:54 | C2 第一轮审计返回 | 有条件通过（3 阻断 / 4 高 / 7 中 / 9 低，`M0C-C2-REVIEW.md`） |
| 2026-11-18 08:57-09:07 | 按审计修正代码（client.cpp 8 处 / ctl.cpp 5 处 / selftest 重写 9 场景 / ps1 重写 45 断言）+ 全量重建 | 构建成功；hook 侧回归 PASS |
| 2026-11-18 09:07 | C2 自检重跑 | `C2-BOOKKEEPING-SELFTEST: PASS (45/45 runner, 60 in-process)`，exit 0，证据 `C2-iface-selftest-20261118-0924` |
| 2026-11-18 09:11 | 设计文档更正（§0修订记录/§4.3 initError 与计数器/§5.1 覆盖变量/§5.2 写时序/§6.1 流程/§7.2-7.4 判据表/§8 边界/附录） | 469 行 / 39,266 B / `9BA40F94…` |
| 2026-11-18 09:13 | 修正 ps1 中「H 是能失败断言」的过时叙述（实测 Windows 接受越界 ifIndex），改为 I 承担并重跑 | `C2-BOOKKEEPING-SELFTEST: PASS (45/45)`，exit 0，证据 `C2-iface-selftest-20261118-0928` |
| 2026-11-18 09:13 | C2 复审子代理派出 | 运行中 |
| 2026-11-18 09:16-09:20 | **首次真实进程内注入冒烟**（宿主 powershell.exe，三轮计数对照） | 注入成功；H-3 现场复现；发现 status/counters 默认模块缺陷，证据 `C2-inject-smoke-20261118-0916` |
| 2026-11-18 09:21 | 修 ctl 自动探测（未给 `-m` 时按目标实际加载的 CivLink 模块选 RVA）+ 全量重建 | 五个产物哈希全变 |
| 2026-11-18 09:23 | 复验自动探测 + 设计文档 §5.1/§6.2 同步 | `status`/`counters` 均免 `-m`、exit 0、`sent 10 / ignored 4`，证据 `C2-inject-smoke-20261118-0940` |
| 2026-11-18 09:24 | 对重建后二进制重跑 C2 自检 + hook 回归 | `PASS (45/45)` exit 0（`C2-iface-selftest-20261118-0945`）；`HOOK-SELFTEST: PASS` exit 0 |
| 2026-11-18 09:25 | 冒烟文档写 §4.1 修复复验 + 待办 1 关闭；计划 §3.6/§3.9/§7/§8 同步 | 冒烟文档 131 行 / 9,312 B / `64EB40CE…` |
| 2026-11-18 09:30 | C1 两组回归重跑（reserve + combo，对重建后 agent） | `PASS (12 checks)` / `PASS (14 checks)` 均 exit 0，证据 `C1-*-selftest-20261118-0930` |
| 2026-11-18 09:30 | 新写真实游戏检查脚本 `run-c2-real-game-check.ps1` + 语法校验 + 无游戏前置分支实测 | SYNTAX OK；无游戏 exit 1（符合设计）；**脚本本身尚未在有游戏的条件下执行** |
| 2026-11-18 09:31 | 写 M0-C 审计任务书 `M0C-AUDIT-BRIEF-20261118.md`（15 项哈希全部逐条复核 OK） | 139 行；哈希见任务书自身与审计报告（本文不嵌，避免循环引用） |
| 2026-11-18 09:32 | 用 send_message 把 09:16 之后的 3 项增量推给复审子代理 | 已送达，要求逐条给裁定 |
