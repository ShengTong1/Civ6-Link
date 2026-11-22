# M0-G Peer Discover（助手互发现 + 多路径质量探测）实现设计 v1.3

> 日期 2026-11-20。前置：`docs/PEER-DISCOVERY-RESEARCH-20261120.md` v1.2 + 审计 `docs/PEER-DISCOVERY-RESEARCH-REVIEW.md`（有条件通过）+ 事实核实 `docs/RUST-NETLIB-FACTCHECK-20261120.md`。
> 用户决策链：m32997（四点需求）→ m33009/m33032（独立模式/两阶段/私有 UDP/按钮触发/无口令/默认物理网卡）→ m33073（新功能用库 + 旧 FFI 保留 + cargo vendor）。
> 本设计送子代理审计后再写代码。标注：【事实】/【推断】/【需实测】/【决策】。
> **v1.3（2026-11-20 12:40）**：跨机实测（A 物理机 ↔ VM 192.168.31.176，证据 `M0A/captures/m0g-dual-20261120-*`）推翻并修订三处实现层设计——§2 收包策略改**通配+IP_PKTINFO+跨子网兜底**（M1 原方案逐卡 bind 单播 IP 的 socket 在 Windows 收不到远程定向广播，实测仅收本机回环）、§2 发包策略改**双 socket**（pinned 发 directed + 默认路由发 limited；绑源 IP+pin 后 limited 广播不出机器）、新增 §4.1 响应 magic（encode_discovery_resp/CLPR，响应误用 CLPD 会被请求端拒收致对端地址学不到）；探测期必须落在对端监听窗内（反射循环在主循环内）。
> **v1.2（2026-11-20 08:57）**：关闭复审 `docs/M0G-DESIGN-REVIEW-2-20261120.md`（21b416f5，NOT PASS）三处必改——N1 自检④ RTT 硬编码 80ms→**130ms**（130_000_000ns）、N2 抖动 r/s 明确同为发起端时钟域（T4′/T1）且全程 ns 仅显示÷1e6、M5 §10 增 README 双警告可验收项；M1/M4/M6 与六建议真关闭不重做。
> **v1.1（2026-11-20 08:50）**：关闭审计 `docs/M0G-DESIGN-REVIEW-20261120.md`（4407c6aa，NOT PASS）6 项必改——M1 收包 socket 逐卡绑定、M2 t4 符号表、M3 单调时钟纳秒换算、M4 VPN 实名枚举+保守排除、M5 GUI/README 双警告、M6 feature gate 收拢依赖；建议项 B1/B2/B3/B5/D1/D2 一并采纳。

## 1. 目标与非目标

**目标**（对应用户四点需求）：
1. 用户点「开始扫描」后，agent 从本机**每一块启用的物理网卡**（默认排除 VPN，可勾选）用 `bind(该卡IP:0)` + `set_broadcast(true)` 向**定向子网广播地址**（如 WiFi 192.168.31.255 / Radmin 26.255.255.255）发发现包；不依赖默认路由。
2. 另一台运行同款助手的机器在任一广播域收到 → 解析 → 在界面/日志列出对端（实例 UUID + 版本 + 各网卡 IP）。
3. 发现后对每对（本端网卡, 对端网卡）发单播 UDP 探测包，测 RTT（p50/p95）、抖动（RFC3550 A.8）、丢包率，输出**推荐路径**（只展示，不自动切换）。
4. 支持同 WiFi / Radmin（二层 VPN 已实测）/ ZeroTier（【需实测】，默认不启用）；IPv4 MVP，IPv6 不在本设计。

**非目标**：不改游戏发现端口（62900-62999）、不碰 62056 数据面、不注入、不伪造 Civ6 广告、不自动切换路径、不做鉴权（仅魔数+版本，UI/README 声明仅限信任环境）、不宣称双机对局可用、不动 Gate A/B。

## 2. 工作模式与 CLI

新增 agent 模式 `--peer-discover`，与现有 `--sim-lan-listen` / `--simulate` / `--discovery-completion` / F1/F2 **互斥**（解析阶段拒绝组合）。
```
civlink-agent.exe --peer-discover
    [--discover-interval-ms 3000]      # 发现广播周期，默认 3000（下限 1000）
    [--discover-port 63010]            # 发现端口
    [--probe-port 63011]               # 探测端口
    [--include-vpn]                    # 是否纳入 VPN 网卡（默认 false=只物理）
    [--peers-dir PATH]                 # 对端列表/探测结果落盘目录（默认 <out-dir>\peers）
    [--out-dir PATH]                   # 复用现有日志目录参数
    [--stop-file PATH]                 # 复用现有优雅停止
```
约束【决策】：Discovery/Probe 端口与现有任何端口不冲突（63010/63011）。所有输出**只写文件+stdout**，不弹 console。

**监听地址策略（M1 必改，v1.3 按跨机实测修订）**：~~逐网卡 `bind(该卡IP:discover_port)`~~ **【实测推翻】Windows 上绑单播 IP 的 socket 收不到远程定向广播（仅收本机回环）；对端 limited 广播经 Radmin 二层到达时源 IP 是对端最低 metric 网卡（如 26.x），不在本地子网**。实现为：**单通配 socket `bind(0.0.0.0:discover_port)` + `IP_PKTINFO`**（复用 egress::recv_with_dst 学目的地址→匹配本机 NIC bcast）+ **跨子网兜底接受**（pktinfo 不中且 src 不在本地子网→接受并计 cross_subnet_recv，源=对端 Radmin 出口地址）+ 全部 socket `SO_EXCLUSIVEADDRUSE`（手写 setsockopt，socket2 无具名方法）。发包 socket 逐卡 `bind(该卡IP:0)` 后按 v1.3 双 socket 策略发（见下）。探测 socket 每路径 `bind(local_ip:0)`，**不 pin**（实测 pinned socket 连收都不收；单播走路由表即可）。

**发包策略（v1.3 跨机实测修订）**：**双 socket**——①pinned socket（bind 源 IP + `IP_UNICAST_IF=31` setsockopt if_index.to_be()）发**定向广播**（如 192.168.31.255）；②**不 pin 的默认路由 socket**（bind 0.0.0.0:0 + SO_BROADCAST）发**limited 广播 255.255.255.255**。【实测】绑源 IP+pin 的 socket 发 limited 广播 send_to 返回 Ok 但包不出机器；裸 UdpClient（不绑源不 pin）发的 limited 能跨机到达。

**响应策略（v1.3 新增 §4.1）**：响应包用 **`encode_discovery_resp`（CLPR magic）**，从 per-NIC socket 发（源 IP=该卡 IP，请求端才能学到对端每个网卡地址）。【实测教训】响应误用 CLPD（与发现包同 magic）会被请求端 resp handler 的 CLPR 校验全部拒收，对端真实网卡地址永远学不到（m0g-dual-1310 轮实证：收到 10 条响应但 0 条入表）。core selftest 3 断言：resp-magic/resp-decode/resp-not-disc。

**时序约束（v1.3 新增）**：探测期（PROBES_PER_PATH=100 × 120ms 超时 × 路径数）必须落在**对端监听窗内**——反射循环在主循环内，对端进入自身探测阶段后无人反射。【实测】B listen 16s + A 探测在 25-49s → recv=0；B listen 60s 覆盖 A 探测期 → recv=100。

## 3. 依赖与离线构建（M1 裁决落地）

- 新增依赖放在 **Cargo feature gate `peer-discover` 内（默认关闭，M6 必改）**：
  ```toml
  [features]
  peer-discover = ["dep:if-addrs", "dep:socket2"]
  [dependencies]
  if-addrs = { version = "0.15.0", optional = true }
  socket2   = { version = "0.6.5", optional = true, features = ["all"] }
  ```
  普通 `cargo +1.75.0 build --offline`（无 features）**仍是零依赖**，旧 F1/F2/M0-E 构建路径完全不变；只有 `cargo +1.75.0 build --offline --features peer-discover` 才需要 vendor 依赖。`--peer-discover` CLI 模式在没有该 feature 编译时给清晰错误"peer-discover feature not compiled in"。**不删** `mod egress` 手写 FFI（socket2 在 Windows 不支持 recvmsg，删不掉）。
- **cargo vendor**：联网执行一次 `cargo vendor`，生成 `civlink/agent/vendor/` + `.cargo/config.toml`（source replacement）+ 提交 `Cargo.lock`。**关键实测（probe job pwsh-471e6333ee4643a9，2026-11-20 08:44）**：
  - `cargo vendor` 成功（5 个依赖目录）；`cargo build --offline`（stable 1.99）成功；
  - **stable cargo 默认生成 lockfile v4 → `cargo +1.75.0 build --offline` 报 "lock file version 4 not understood"（1.83+ 才支持 v4）**；
  - **解法：用 `cargo +1.75.0 generate-lockfile --offline` 生成 v3 lockfile → `cargo +1.75.0 build --offline` 成功**（socket2 0.6.5 / if-addrs 0.15.0 / windows-sys 0.61.2 / windows-link 0.2.1 全部在 Rust 1.75 下编译通过）。→ **1.75 MSRV 约束保住了**。
  - 落地纪律：vendor 后必须跑一次 `cargo +1.75.0 generate-lockfile --offline` 锁定 v3；之后所有构建用 `cargo +1.75.0 build --offline`，**禁止用 stable cargo 重新 generate lockfile**（会升 v4 破坏 1.75）。**防呆（采纳 D1 建议）**：构建脚本自检 `Cargo.lock` 第三行 `version = 3`，若为 4 则报错退出并提示用 1.75 重新 generate。
- 旧有 F1/F2/M0-E 构建路径**不受影响**：默认 feature 下 agent 仍是零依赖；vendor + `--features peer-discover` 才引入新 crate，且仍 `--offline` + 1.75 兼容。

## 4. 数据结构

```
PeerId = 16B UUID（进程启动时随机生成，存内存+落盘，重启更换）
IfAddr = { if_index: u32, ip: Ipv4Addr, prefix: u8, kind: Physical|Vpn, subnet_bcast: Ipv4Addr }
-- subnet_bcast = ip | (!mask)（定向广播地址）
DiscoveredPeer = { uuid, version, last_seen: Instant, addrs: Vec<Ipv4Addr>, via_if: u32, rtt_hint }
PathId = (local_if_index, local_ip, src_port, peer_ip, peer_port)  -- RFC6812 风格
ProbeStats = { path: PathId, sent, received, lost, p50_ms, p95_ms, jitter_ms, loss_pct, samples, same_link_suspect: bool }
```

## 5. 发现包格式（私有 UDP，魔数+版本，≤512B）

Discovery（发 63010，定向广播）：
```
offset 0..4   magic  = 0x43 0x4C 0x50 0x44 ("CLPD")
offset 4      version= 1
offset 5..21  uuid   = 16B 实例标识
offset 21..23 port   = 本机探测端口 (63011) u16 BE
offset 23..24 flags  = bit0 include_vpn 能力位（仅声明，不强制）
total 24B
```
响应（对端收到后从 63010 单播回给来源 IP:port，非反射放大，对等量）：
```
offset 0..4 magic "CLPR"; 4 version; 5..21 uuid; 21..23 probe_port; 23..24 flags
total 24B
```
过滤【决策，v1.3 修订】：~~源 IP 必须落在接收 socket 绑定网卡的子网内~~ → **pktinfo 目的地址匹配本机 NIC bcast → 否则 src 落本地子网 → 否则跨子网兜底接受**（三级过滤，v1.3 实测：对端 limited 广播源 IP=对端最低 metric 网卡如 26.x，不在本地子网，若硬卡子网过滤会全部静默丢弃）；仅魔数+版本匹配；每源 3s 去重。**无鉴权**，UI/README 明文声明"任何同款助手/同广播域成员都能看到你，仅限信任网络"。

## 6. 探测包格式（TWAMP Light 简化，64B）

```
offset 0..4   magic "CLPP"
offset 4      version
offset 5..7   seq u16 BE（每路径独立，回绕取模 65536，采纳 B2 建议）
offset 7..8   flags（bit0 = 这是响应包）
offset 8..16  T1 = 发起端发出请求戳（ns，单调）
offset 16..24 T2 = 反射端收到请求戳（ns，单调；请求填 0）
offset 24..32 T3 = 反射端发出响应戳（ns，单调；请求填 0）
offset 32..40 reserved（0）—— 不在线上放"本地收包戳"（M2 必改：那是本地时钟域，不能塞进跨端报文）
offset 40..64 reserved（0）
```
**符号表（M2 必改，明确时钟域）**：
- `T1` = 发起端单调时钟，发请求时戳（线上字段 offset 8）。
- `T2` = 反射端单调时钟，收到请求时戳（线上 offset 16）。
- `T3` = 反射端单调时钟，发出响应时戳（线上 offset 24）。
- `T4′` = **发起端单调时钟，收到响应时戳（仅本地内存，不进线上报文）**。
- **RTT【事实，RFC5357 附录 I】** = `(T4′ − T1) − (T3 − T2)`，单位 ns；跨端差值 `T3−T2` 消掉反射端时钟偏移，免时钟同步。
- 反射端无状态：seq 原样拷回、flags 置响应位、填 T2/T3，不改 T1【事实，TWAMP Light 强制】。
- **时钟换算原语（M3 必改）**：线上所有时戳统一 **ns（u64, monotonic）**。实现用 `std::time::Instant`（单调）相对进程起点 `start.elapsed().as_nanos() as u64`，**不用 QueryPerformanceCounter 原始 ticks 直接当 ns**（QPC 需 `QueryPerformanceFrequency` 换算：ns = ticks × 1_000_000_000 / freq；本设计选 Instant 直接拿 ns 更简单且与主线程同源）。所有阈值（J/10ms、p50/100ms、p95/150ms）除以 `1_000_000.0` 得到 ms 后再比较——若漏换算会让 100ms 阈值变成 100ns，全部评分失效。
- 抖动【事实，RFC3550 A.8】：`D=(r_j−r_i)−(s_j−s_i); J=J+(|D|−J)/16`。**时钟域（N2 修正）**：s=发送时戳序列 **= T1（发起端单调时钟）**，r=接收时戳序列 **= T4′（同一发起端单调时钟）**——r 与 s **同属发起端时钟域**，绝不混入反射端的 T2/T3。**单位（N2 修正）**：全程以 **ns** 计算 D 与 J（J 的单位即 ns，初值 J=0）；仅在**显示与评分**时转 ms（`J_ms = J/1_000_000.0`），与 §7 评分式 `J/10ms` 对齐时即 `J/10_000_000.0`。禁止"差值 ns 转 ms 再入 J"——那会让 J 单位混乱且阈值失效。
- 丢包：序号间隙 + 结算窗口（2s，迟到计入，超窗计丢失）+ **乱序缓存**（采纳 B3：收到 seq>N 时先入暂存，窗口结算时对缺失序号二次核对，避免乱序误判丢包）【推断】。
- 速率【推断/需实测】：20 pkt/s × 5s = 100 包/路径，±10% 抖动间隔。
- 每路径独立 socket（bind local_ip:0），序号空间独立；`ipTTL` 用 setsockopt IP_TTL=64 读回包 TTL【需实测】。

## 7. 评分与推荐（MVP 只展示）

```
score = 0.45·p50_norm + 0.20·p95_norm + 0.20·(J/10ms) + 0.10·(loss/1%) + 0.05·stability_penalty
【推断/项目自创，归一化基准需实测冻结】
p50_norm = p50_ms / 100ms（基准 100ms【推断】）
p95_norm = p95_ms / 150ms（基准 150ms【推断】）
stability_penalty = 1 if 样本<80 or 同链路疑似 else 0
```
硬门槛【推断】：loss>3% 或 p95>150ms 或 samples<80 ⇒ 标"不推荐"。
同链路疑似【推断/需实测，阈值未冻结】：两路径 observed_ttl 相同、出口源 IP 同段、RTT 序列 Pearson>0.8 ⇒ 合并标注"疑似同一物理链路"。
迟滞【推断】：MVP 不实际切换，仅在 UI 显示"建议路径"，不执行任何切换动作。

## 8. 输出与界面

- 文件：`peers/peers.jsonl`（每行一个发现的实例+时间戳）、`peers/probe-results.json`（每路径统计+推荐）、`peers/summary.txt`（人读：发现 N 台 / 路径 M 条 / 推荐 X）。
- stdout 摘要行：`PEERDISCOVER: discovered=N paths=M recommended=<ifIndex:ip>`。
- GUI（后续任务）：新标签页"助手发现"——「开始扫描/停止」按钮、**逐网卡勾选列表（默认只勾物理网卡，VPN 网卡默认不勾且标黄）**、对端列表（UUID 短前缀+IP+最后看到时间）、路径表（本地网卡→对端IP / RTT p50/p95 / 抖动 / 丢包 / 推荐标记）。
- **GUI 双重警告（M5 必改，安全裁决#4 落地）**：①页面常驻"无鉴权：任何同款助手都能看到你，仅限信任网络"；②**当用户勾选任一 VPN 网卡时即时显示"警告：VPN（如 Radmin）是二层广播域，同房间其他成员也会收到你的发现包（本机 VM 实验已证实）；仅在信任的房间内勾选"**。README 同步这两条。本设计不含 GUI 代码，但 GUI 实现必须包含这两条警告，否则安全裁决#4（默认排除 VPN 防泄露）落空。

## 9. 生命周期与资源（v1.3 按实现修订）

- 扫描线程：每 interval 遍历启用网卡，**双 socket 发**（pinned→directed + 默认路由→limited，见 §2）；**收包单通配 socket 0.0.0.0:discover_port + IP_PKTINFO + 跨子网兜底**（M1 原逐卡 bind 方案实测推翻，见 §2 v1.3 修订）。
- 停止：--stop-file 存在 → 置 stop（`Arc<AtomicBool>`，主循环与探测循环共用；**探测期有独立 probe_stop 防主循环到期误杀探测**——【实测】probe 复用主 stop 导致 listen-seconds 到期后 sent=0）→ 收包线程退出 → 写 summary → exit 0。
- 所有 socket 非阻塞 + 轮询，20ms sleep 防 busy-spin；无 busy-spin。
- **rustc 1.75 约束【事实】**：`UdpSocket::try_recv_from` 不可用（E0599，更晚 stable）→ 用 `try_clone()` + `set_nonblocking(true)` + `recv_from()`（WouldBlock break）轮询。
- **VPN 网卡识别（M4 必改，多重判据 + 保守策略）**：不只用名字关键字。判据按优先级：①`if-addrs` 返回的 `Interface`/adapter 名匹配已知 VPN 关键字（Radmin/ZeroTier/Tailscale/WireGuard/TAP-Windows/vEthernet/Ngrok 等）；②IP 落在已知 VPN 网段（Radmin 26.0.0.0/8、ZeroTier 常用 10.x/172.x 但需结合实际）；③【需实测】本机实名枚举——实现前在本机跑一次枚举，把实际适配器名+IP+ifIndex 冻结进测试的"已知 VPN 清单"。**保守策略**：任何判为 VPN 或"不确定"的网卡默认**不启用**，需在 GUI 逐卡显式勾选或 CLI `--include-vpn`（含具体 IP 白名单更优）才启用——误判方向必须是"漏发"而非"泄露"。M4 的判别力测试：构造一块模拟 VPN 网卡（名字不含关键字但 IP 在 26./8），验证默认被排除。

## 10. 自检与验收判据（v1.3 实测状态更新）

1. **单元/机械自检**（新脚本 `run-peer-discover-selftest.ps1`）：①包格式编解码 round-trip ②定向广播地址计算（逐字节公式，192.168.31.60/24→192.168.31.255；26.74.126.98/8→26.255.255.255；172.16.5.7/12→172.31.255.255）③VPN 排除/纳入（含"名字无关键字但 IP 在 26./8"的模拟卡，M4 判别）④TWAMP RTT 公式（合成 T1/T2/T3/T4′ → 硬编码期望 rtt，例 T1=1_000_000_000ns/T2=1_100_000_000/T3=1_150_000_000/T4′=1_180_000_000 → rtt=(1_180_000_000−1_000_000_000)−(1_150_000_000−1_100_000_000)=180_000_000−50_000_000=**130_000_000ns=130ms**；N1 修正：旧稿写 80ms 算错）⑤时钟换算（ Instant ns → ms 除以 1e6，M3：造 100ms 时戳验证阈值不失效）⑥RFC3550 抖动（合成序列→硬编码期望 J）⑦丢包序号间隙+乱序缓存 ⑧评分排序（合成 3 路径→硬编码推荐结果）⑨互斥 CLI 参数拒绝 ⑩stop-file 优雅退出+落盘 ⑪无鉴权 + VPN 双警告文案存在（**M5 修正，可验收项**：逐字核对 ①GUI 页面常量与 ②README.md 均含两条警告——"无鉴权仅限信任网络"与"VPN 二层广播域同房间成员可见（Radmin VM 实验已证）"；缺任一即 FAIL）⑫feature gate（默认编译无 peer-discover 时 CLI 报错；有 feature 时可用）⑬响应 magic 三断言（v1.3 新增：resp-magic/resp-decode/resp-not-disc）。
2. **变异测试**（期望值全部**硬编码**，禁止从被测代码导出自指断言，采纳 D2）：5 条变异全部被核心自检捕获【v1.3 实测 PASS 6/6】——M1 RTT 公式 130→80ms、M2 响应 magic CLPR→CLPD、M3 反射时延修正置 0、M4 VPN 关键词过滤移除、M5 丢包恒 0。**判别力陷阱（实测教训）**：变异必须改动被 selftest 断言覆盖的逻辑且不能破坏断言本身（M4 首版全局替换 IfClass::Vpn 把 selftest 断言一起改了→变异自我隐藏）。
3. **VM 双端实测**【v1.3 已完成，PASS】：A 物理机 ↔ VM 192.168.31.176（Radmin+WLAN 双网），证据 `M0A/captures/m0g-dual-20261120-{1015,1040,1052,1100,1115,1122,1131,1136,1142,1148,1211,1218,1223,1228,1232,1235,1325,1332}`。最终轮：A `RECOMMENDED: WLAN(192.168.31.60) -> 192.168.31.176:63011 (score 0.0777)`、2×WLAN 路径 `sent=100 recv=100 / p50=11.3ms / p95=12.4-12.5ms / J=0.52-0.90ms / loss=0.00% / recommendable=true`；B 同样 discovered=1 paths=6；A peers.jsonl 双地址（26.197.96.55 + 192.168.31.176）。**边界**：这是"助手间发现+探测"实测，不是双人对局；不勾 E2-A/E2-B/E3、不动 Gate。
4. **不宣称**：无真实 Civ6 客户端加入、无 62056 数据面、无公网跨网。

## 11. 风险与开放项（送审计关注）

- R1✅【已实测关闭】：if-addrs 0.15 / socket2 0.6.5 / windows-sys 0.61 在 Rust 1.75 下编译通过；须用 `cargo +1.75.0 generate-lockfile --offline` 生成 v3 lock（stable 的 v4 lock 不兼容 1.75）。
- R2【需实测】：定向广播在 Radmin 26.255.255.255 / ZeroTier 的实际转发（Radmin 已证 magic 广播通，但定向广播需单独验）。**兜底（采纳 B1 建议）**：若定向广播实测失效，用既有的手写 `IP_UNICAST_IF` FFI（egress 模块同款，setsockopt IPPROTO_IP=0/opt 31）钉出口网卡后改发全局广播——该兜底同样在 peer-discover feature 内，且必须实测判别。
- R3【推断】：同链路疑似阈值（TTL/RTT 相关性）未冻结，评分归一化基准未冻结——实现给初值并标注待实测。
- R4【事实】：无鉴权——同广播域任何成员可发现/伪造，UI/README 必须诚实声明（含 VPN 勾选双警告，M5）。
- R5【事实→强制】：本机多进程/多实例抢 63010 端口 → **SO_EXCLUSIVEADDRUSE 提为强制**（采纳 B5），启动失败给清晰错误，绝不用 SO_REUSEADDR 抢绑定。
- R6【决策】：MVP 探测包仅 IPv4；IPv6 不在本设计。

## 12. 结论（v1.3）

v1.1 关闭审计 4407c6aa 全部 6 项必改 + 6 项建议；v1.2 关闭复审 21b416f5 三处必改；**v1.3 依跨机实测（18 轮证据目录）修订实现层三处设计**（收包=通配+pktinfo+跨子网兜底、发包=双 socket、响应=CLPR per-NIC 源）并新增时序约束与 §4.1 响应 magic。**实现与自检全部完成**：core selftest 31 checks（含 resp 3 断言）、`run-peer-discover-selftest.ps1` 变异 5/5 捕获、VM 双机端到端 PASS（双向互发现+双向评分推荐）。**编译与机械自检通过 ≠ 双人联机可用**（措辞限定）：本功能是"助手间发现+路径探测"，不是双人对局；不勾 E2-A/E2-B/E3、不动 Gate。剩余：GUI「助手发现」页（双警告必含）、README 双警告落地、登记。
