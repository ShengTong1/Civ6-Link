# Rust 网络库事实核实报告（回应 m33049 用户质疑）

> 日期 2026-11-20，子代理 3c7a351d 核实，只读研究未改产品文件。
> 触发：用户质疑「为什么有零依赖硬约束？用现成 rust 库，若手写的不完善就删掉，以官方开源案例为主」。
> 数据快照：crates.io API / GitHub API / docs.rs / Cargo Book / 项目源码。

## 0. 结论（TL;DR）
1. **「引入 socket2 + if-addrs 就删掉手写 ws2_32 FFI」不成立。** socket2 在 Windows 官方明确不支持 recvmsg（文档原话拒绝支持 WSARecvMsg），且无通用 setsockopt；egress 四件事 ①②③ 完全不能覆盖，④ 仅部分等价且丢回退语义。
2. **「以官方开源案例为主」在这个具体功能点上站不住脚**：socket2 属 rust-lang 官方、windows-sys 属微软官方，确是主流；但针对 IP_PKTINFO 钉源 IP，微软官方示例（rmmc.cpp）恰恰就是手写 WSAIoctl + WSARecvMsg 的 C++ 代码，与项目现有实现同构。
3. `cargo --offline` 无缓存构建：引入任何 crate 后必然失败，除非预置 vendor/ 并配 source replacement（硬事实）。
4. 建议：维持零依赖手写 FFI 是当前硬约束下的合理选择；若确要优化，唯一有收益的是用 if-addrs 替换「网卡枚举」（仍需 vendor），而不是删 egress FFI。

## 1. 各库快照
| 库 | 版本 | MSRV | star | 近月下载 | 出身 |
|---|---|---|---|---|---|
| socket2 | 0.6.5 (2026-07-13) | 1.70 | 881 | 3.95 亿 | rust-lang 官方 |
| if-addrs | 0.15.0 (2026-02-08) | 未声明【需实测】 | 47 | 1039 万 | get_if_addrs 活跃 fork，非官方 |
| network-interface | 2.0.5 (2026-01-03) | 未声明 | 102 | 159 万 | 社区，带 C 编译步骤 |
| quinn | 0.11.12 | 1.85（超 1.75） | — | 1.62 亿 | QUIC 面向连接，不匹配 |
| pnet | 0.35.0（近 2 年未更） | 未声明 | — | 232 万 | 原始报文/嗅探，需驱动 |

## 2. 【关键】egress FFI 四件事 vs socket2
项目 egress 模块（`civlink\agent\src\main.rs` 575-954，核心 FFI 约 35 行）：

| egress 做的事 | socket2 覆盖? | 依据 |
|---|---|---|
| ① WSAIoctl(SIO_GET_EXTENSION_FUNCTION_POINTER) 取 WSARecvMsg/WSASendMsg 指针 | **不能** | 无 WSAIoctl/扩展 GUID API；sendmsg 直接调导出符号无探测回退 |
| ② WSARecvMsg 读 IP_PKTINFO 得探测包目的地址 | **不能（决定性）** | docs.rs 850-856 明确 Windows 不支持 recvmsg，原话 "calling WSARecvMsg is not straight forward on Windows"，指向微软 rmmc.cpp |
| ③ setsockopt(IP_PKTINFO=19 / IP_UNICAST_IF=31) | **不能** | 无公开通用 setsockopt，只有专用方法（set_broadcast 等） |
| ④ WSASendMsg 带 IP_PKTINFO cmsg 钉源 IP | **仅部分、不等价** | sendmsg 在 Win 可用但需自己构造 cmsg；丢掉「扩展缺失回退 send_to + egress_unpinned 计数」语义 |

即使引入 socket2，仍需 `windows-sys::Win32::Networking::WinSock`（WSAIoctl/WSARecvMsg/WSAMSG/IN_PKTINFO/setsockopt）与 `Win32::NetworkManagement::IpHelper`（GetAdaptersAddresses）。**手写 FFI 核心几乎必须原样保留。**

socket2 官方自述："If you don't know how to create a socket using libc/system calls then this crate is not for you"。

## 3. offline 构建
- socket2 依赖 windows-sys >=0.60,<0.62（MSRV 1.71）；if-addrs 依赖 windows-sys ^0.61.2 + libc。Rust 1.75 下传递依赖可编译，if-addrs 本体 MSRV【需实测】。
- **`cargo --offline` 无缓存必然失败**：需先 `cargo vendor` + `.cargo/config.toml` source replacement + 锁 Cargo.lock。会把 windows-sys 约 33 万行生成绑定固化进仓库。

## 4. 权衡
| 维度 | 零依赖手写 FFI | 引 socket2+if-addrs |
|---|---|---|
| 开发速度 | 已写好 | 删不掉核心，只省枚举几十行 |
| 可审计性 | egress 380 行 + FFI 35 行可全文审 | 依赖树数十万行第三方，边界外移 |
| 离线构建 | 天然满足 | 必然需 vendor |
| 供应链 | 零第三方 crate | 引入三方维护者 + crates.io 信任链 |
| 功能完整性 | 四项全覆盖含回退 | ①②③ 无覆盖，④ 不等价 |

## 5. 结论与给用户的选项
手写 FFI 历史上确实踩过 4 个 bug（mem::zeroed 函数指针 abort / GUID 字节序 / WSAMSG.Control 嵌套 / IN_PKTINFO 字段序），但已修复且有 B-1 三接口实测背书。**「库删不掉它」不是我不愿改，是 socket2 在 Windows 官方就不支持 recvmsg。**

- 选项 A（推荐）：维持零依赖，新功能也用纯 std + 手写 GetAdaptersAddresses FFI（与 egress 同构），保留 --offline 无缓存构建。
- 选项 B：放宽约束，引入 if-addrs 只做网卡枚举（vendor），egress FFI 保留。
- 选项 C：用 windows-sys（微软官方绑定）替换手写 extern 声明（类型更安全），egress 逻辑仍手写，仍 vendor。

## 全部来源
- socket2: https://crates.io/crates/socket2 ; https://docs.rs/socket2/0.6.5/socket2/index.html ; https://docs.rs/socket2/0.6.5/socket2/struct.Socket.html ; https://github.com/rust-lang/socket2 ; 微软 rmmc.cpp: https://github.com/microsoft/Windows-classic-samples/blob/master/Samples/Win7Samples/netds/winsock/recvmsg/rmmc.cpp
- if-addrs: https://crates.io/crates/if-addrs ; https://github.com/messense/if-addrs ; https://raw.githubusercontent.com/messense/if-addrs/master/src/windows.rs
- network-interface: https://crates.io/crates/network-interface ; https://github.com/LeoBorai/network-interface
- quinn: https://crates.io/crates/quinn ; pnet: https://crates.io/crates/pnet
- offline: https://doc.rust-lang.org/cargo/reference/source-replacement.html#vendoring-sources
- 项目源码: civlink\agent\src\main.rs:575-954 ; CONTRIBUTING.md:44 ; civlink\build-msvc.cmd
