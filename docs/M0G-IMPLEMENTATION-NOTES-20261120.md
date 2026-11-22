# M0-G 实现备注：依赖 API 勘察（编码输入，非送审件）

> 2026-11-20 08:53，从 `%TEMP%\civlink-vendor-probe\vendor\` 实读。
> 用途： `--peer-discover` 编码时的精确 API 速查，避免猜字段名踩坑。

## if-addrs 0.15.0
```rust
if_addrs::get_if_addrs() -> io::Result<Vec<Interface>>
pub struct Interface {
    pub name: String,                 // 适配器名（Windows: "WLAN"/"Radmin VPN"...）
    pub addr: IfAddr,                 // IfAddr::V4(Ifv4Addr) | V6(...)
    pub index: Option<u32>,           // ifIndex
    pub oper_status: IfOperStatus,    // Up=1 / Down / Testing / Unknown / Dormant ...
    pub is_p2p: bool,
    #[cfg(windows)] pub adapter_name: String,  // GUID 串 "{XXXX...}"，永久唯一
}
pub struct Ifv4Addr {
    pub ip: Ipv4Addr,
    pub netmask: Ipv4Addr,
    pub prefixlen: u8,
    pub broadcast: Option<Ipv4Addr>,  // 可能已有定向广播地址——优先用，缺则自算
}
Ifv4Addr::is_loopback() -> bool
```
- **定向广播**：优先 `a.broadcast`，缺则逐字节 `out[i] = ip[i] | (255 & !netmask[i])`（**逐字节**！PowerShell 整体位运算踩过字节序坑）。
- **VPN 识别（M4）**：`name` + `adapter_name` + IP 段（Radmin 26.0.0.0/8）三重判据；`oper_status != Up` 跳过；loopback 跳过；"不确定"=默认排除。

## socket2 0.6.5（feature "all"）
```rust
Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP)) -> io::Result<Socket>
socket.bind(&SockAddr::from(SocketAddrV4::new(ip, port))) -> io::Result<()>
socket.set_broadcast(true) -> io::Result<()>      // = setsockopt SO_BROADCAST
socket.set_nonblocking(true) -> io::Result<()>
socket.set_read_timeout(Some(Duration)) -> io::Result<()>
socket.set_reuse_address(false) -> io::Result<()> // 默认即 false
socket.into_raw_socket() -> RawSocket             // → unsafe UdpSocket::from_raw_socket
```
- **SO_EXCLUSIVEADDRUSE（M5/B5 强制）**：socket2 **无**该具名方法 → 用手写 FFI（与 egress 同款）：`setsockopt(raw, SOL_SOCKET=1, SO_EXCLUSIVEADDRUSE=-5, &1, 4)`（Winsock 常量 SO_EXCLUSIVEADDRUSE = -5i32；Windows 要求绑定端独占，防抢 63010）。**绝不设 SO_REUSEADDR**。
- socket2 **无通用 setsockopt、Windows 无 recvmsg** → egress FFI 保留（已在 design 说明）。

## IP_UNICAST_IF 兜底（B1 建议，feature 内）
- `setsockopt(raw, IPPROTO_IP=0, IP_UNICAST_IF=31, &u32::from_be(if_index), 4)`——**网络字节序**（设计核实报告：C2 实现用 `htonl(ifIndex)`）。
- 该兜底只在"定向广播实测不通"时启用，仍 feature-gated。

## 单调时钟（M3）
- `let t0 = Instant::now();` 进程启动时取；`fn now_ns() -> u64 { t0.elapsed().as_nanos() as u64 }`
- 线上时戳写 `now_ns()`（u64, LE/BE 需在设计定，建议 BE 与 seq 一致）；收包解析后算 RTT：
  `rtt_ns = (T4prime - T1) - (T3 - T2)`（u64 减法，注意 T4prime>T1 且 (T3-T2)>0，用 i128 中间防下溢）
- 阈值比较统一转 ms：`ms = ns as f64 / 1_000_000.0`。100ms 阈值 = 100_000_000ns，150ms = 150_000_000ns。
- 抖动 J 以 ns 累加（RFC3550 A.8），显示/评分时转 ms。

## 多网卡收包架构（M1）
- 每块启用网卡一个 `bind(该卡IP:63010)` 的 socket（`set_nonblocking(true)`），存进 `Vec<(IfAddr, UdpSocket)>`；
- 主循环里逐个 `recv_from`（非阻塞，WouldBlock 跳过）→ 用对应 IfAddr 的子网过滤源 IP；
- 发包用另一组 `bind(该卡IP:0)` 的 socket，`set_broadcast(true)`，向 `broadcast:63010` 发 24B 发现包；
- **不用**统一 0.0.0.0 通配 socket（否则过滤无落地对象）。

## M5 两条警告文案（编码阶段须同步落到 GUI 常量 + README）
> 实测当前 README（148,262B）**尚无**"无鉴权/信任网络"字样 → 编码阶段必须补，否则 §10 自检⑪ FAIL。
- 警告①（常驻）：`无鉴权：任何同款助手/同广播域成员都能发现你并看到你的网卡与 IP，仅限信任网络使用。`
- 警告②（勾选 VPN 网卡时即时显示）：`警告：VPN（如 Radmin/ZeroTier）是二层广播域，同房间其他成员也会收到你的发现包（本机 VM 实验已证实 Radmin 广播跨机可达）；仅在信任的房间内勾选。`
- README 插入点：新增 `--peer-discover` 小节，放在现有 GUI/联机说明之后；两条警告须逐字出现在正文（自检⑪按 Contains 断言）。
- GUI 插入点：Tauri "助手发现"页（后续 GUI 任务，非本 agent 编码），页面常量区定义这两条字符串常量。

## 编译与 vendor 落地纪律
```
cd civlink\agent
cargo vendor vendor > .cargo\config.toml 2> vendor.err      # 联网，一次
cargo +1.75.0 generate-lockfile --offline                    # 生成 v3 lock（关键！）
cargo +1.75.0 build --offline                                # 默认：零依赖
cargo +1.75.0 build --offline --features peer-discover       # 新功能
```
- 防呆：构建脚本读 `Cargo.lock` 第三行必须是 `version = 3`。
- 禁止 stable `cargo generate-lockfile`（会升 v4，1.75 不认）。
