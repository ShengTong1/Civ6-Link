# F3-B — Relay 转发原型（本机回环，非发布）

状态：**已完成并自检通过（`F3B-RELAY-SELFTEST: PASS (68/68)`，脚本 revision 3）**。
本文只描述本机回环原型，不构成任何联机验证，也不移动 Gate A/B。

日期：2026-11-14

**版本历史与本文件的效力**

| 版本 | 断言 | 证据 | 状态 |
|---|---:|---|---|
| v1 | 43 | `-142718`/`-142803`/`-142813`/`-142818` | 作废（第一轮审计 12 项必改） |
| v2 | 67 | `-145026` | 作废（第二轮审计 H-1/H-2/M-1/M-2） |
| **v3** | **68** | **`-152821`** | **本文采信** |

三轮审计报告：`docs\F3B-REVIEW.md`（第一轮，有条件通过，0 阻断 / 1 高 / 4 中 / 6 低）、
`docs\F3B-REVIEW-2.md`（第二轮，有条件通过，**0 阻断 / 2 高 / 5 中 / 9 低**）。v3 逐条处理
第二轮的两条高与五条中，并在 §4.5 逐项打勾。

---

## 1. 做了什么

新增独立 crate `civlink\relay`（`civlink-relay 0.1.0`，**零依赖**、edition 2021、
`rust-version = 1.75`，可 `cargo +1.75.0 build --release --offline` 构建）。

它按 F3 设计 v0.3 §4 的 Relay 路径做**纯路由**：

| 能力 | 实现方式 |
|---|---|
| 按目的地转发 | 信封 `dst_peer` 查注册表 → 目标 `SocketAddr` |
| 发送者归属（fail-closed） | 按数据报**来源地址**反查注册表。查不到就丢弃并计 `no sender`，日志写明"未注册来源；信封 `src_peer` 不可信"——绝不回退去信任信封里的 `src_peer` |
| 载荷原样 | 只拷贝 `payload` 字节，长度与内容一律不改；一次输入最多产生一个输出数据报 |
| 不重传不重排 | 转发失败只计数（`forward fail`），不做应用层重试 |
| 拒绝畸形帧 | `too-short` / `bad-magic` / `bad-version` / `payload-too-large` / `truncated` 五类，逐条记日志并计数 |
| 不认识的合法控制帧 | 头合法但 `flags` 不是 REGISTER/DATA → 记 `unknown flags` 并拒绝，不转发 |
| 自投递丢弃 | `dst_peer == sender` 记 `self drop`，不发送 |
| 目的未知 | `no route`，不发送 |
| 端口纪律 | `--listen` 端口若为 62056（游戏数据面），**在 bind 之前**就报错退出（退出码 1），不是只靠脚本前置检查 |
| 三方比对 | 每条转发行记录载荷 **FNV-1a 64** 与**载荷前 8 字节**的十六进制，与发送方、接收方逐字节比对。注意：这是**载荷**的前 8 字节（`main.rs` 的 `hex_head(env.payload, 8)`），不是信封头；信封头在转发时会被重写（`flags` 清零、`src_peer` 覆盖为已认证 sender），所以"头部三方一致"是不成立的说法，v3 已改正 |
| 对账 | ①`forwarded + no_route + self_drop + forward_fail + no_sender == forward_requests`；②`datagrams == registers + forward_requests + bad_envelope + unknown_flags`（分类恒等式，用 `==`/`!=` 打印） |
| 致命错误不伪装 | 收包失败（除超时/WouldBlock/超长）记 `fatal`，summary 先落盘，然后进程以退出码 3 结束——不再以 0 退出掩盖。**该分支本轮没有用例**（见 §5"不证明"） |

信封（20 字节头 + 载荷 ≤1280，全部小端）：

```
0-3   magic 'CVLR'        4   version 1        5   flags (0x01 REGISTER, 0x00 DATA)
6-9   dst_peer u32       10-13 src_peer u32   14-17 seq u32 (回显，不改)
18-19 payload_len u16    20..  payload (原样)
```

收包缓冲 65,535 字节，因此 IPv4 UDP 的有效载荷（最多 65,507 字节）**无法**撑破缓冲；
`WSAEMSGSIZE`（10040）分支是**守卫生效**，不是可达路径，正常审计不应把它当成"超长包已被拒绝"的证据
（见 §5"不证明"）。

## 2. 明确没有做（与 F3 设计 v0.3 §4.1 一致）

- **没有加密。** Relay 看到的是明文。L1 Agent↔Relay、L2 Agent↔Agent 的 Noise_XX/AEAD、
  身份绑定、Nonce 计数与重放窗口都属 M0-B，本原型一律不实现、不冻结 wire format。
- **没有接游戏。** 不注入 Civ6、不 bind 62056、不碰游戏 socket；所有收发都在本机回环的
  测试 socket 之间。游戏进程内注入方式（Design I/II/III）、绑定矩阵、H1/H2/H8 仍是 M0-B。
- **没有身份与鉴权。** 谁注册谁就是那个 `peer_id`，无凭证、无签名、无限速。注册表是
  "最后一个注册的 socket 就是该 `peer_id`"，同一 `peer_id` 被多个 socket 冒用不会报错。
  （fail-closed 只保证"没注册过的 socket 不能借信封里的 `src_peer` 冒充别人"，不保证
  "注册过的 socket 不能被冒用"。）
- **不是产品 Relay。** 单线程阻塞收包，无 Keepalive、无 DEGRADED/RECONNECTING 状态机、
  无跨网 RTT 数据、无多 Peer 并发与重排处理。

## 3. 自检（`civlink\run-f3b-relay-selftest.ps1`，revision 3）

用三个普通 UDP socket 冒充 Agent 与一个未注册来源，跑真实的 `civlink-relay.exe`：

1. **62056 负向用例（先跑）**：`--listen 127.0.0.1:62056` 必须退出码 1、stderr 含
   `must not use port 62056`，随后 `Get-NetUDPEndpoint -LocalPort 62056` 必须为 0。
2. 前置：34720 必须空闲（`relayListen`，失败即 `exit 2`）；62056 的"空闲"不是 exit-2 前置，而是**负向用例之后**的断言强制（脚本 L172-173：`--listen 62056` 拒绝后复查 62056 无任何绑定）——文档 v3.1 按第三轮审计 E3 更正此措辞。
3. 注册：peer 101（A）、peer 202（B）各注册 3 次，随后 A 再补 2 次、B 再补 2 次
   ——**共 10 次**，与真实 Agent 的周期重注册同形。10 是无条件期望值（v2 只断言 `<=`，
   丢注册也会绿，v3 改成精确值）。
4. A 发四帧：`seq=1` dst=202 8B、`seq=2` dst=999（无人）、`seq=3` dst=101（自投）、`seq=4` dst=202 120B。
5. **五类拒绝路径**，逐条构造：
   - 12B → `too-short`
   - 24B 头 + 第 4 字节改为 1 → `bad-magic`（必须手工构造，正常构造器永远写合法 magic）
   - version=2 → `bad-version`
   - 声明 `payload_len=1281` → `payload-too-large`
   - 声明 100 实际只发 60 字节 → `truncated`
6. **未知 flags**：`flags=0x02` 的合法帧 → 记 `unknown flags`，不转发。
7. **超长输入**：5,000 字节、头合法但声明 `payload_len=1281` 的数据报 → 被 parser 判
   `payload-too-large`；断言 Relay **仍在服务**（进程未退出）。
8. **反向方向**（B→A）：B 先补发 2 次注册，再发 `seq=5` dst=101 8B，断言 A 收到、`src_peer=202`、
   逐字节一致。
9. **未注册来源**（v3 新增，第二轮审计 H-2）：一个**从不注册**的第三个 socket 发 `seq=91`
   dst=202，信封里故意写 `src_peer=303`。fail-closed 实现必须丢弃并计 `no sender`；
   若 Relay 天真信任信封 `src_peer`，它会登记 303→该 socket 并把帧成功路由给 B。
   这条用例的存在与否决定 `no sender` 是真能触发的分支还是文档里的空话。
10. 写 stop 文件让 Relay 干净退出（退出码 0）。
11. 读 summary 与 relay-log 做断言：计数用**精确期望**而非 `>=`，并要求 summary 里运行时长
    与墙钟相差 ±3 s、判词分母用常量 `$expectChecks = 68`（v2 用 `$Checks/$Checks` 自指，
    守卫块被跳过时仍打印 `N/N`，v3 已改）。

**68 项断言全部通过**（`Check` 站点与运行时调用均为 68，无守卫块跳过）。

### 3.1 本轮实测计数

| 计数器 | 值 | 说明 |
|---|---:|---|
| `datagrams` | 23 | = 10 + 6 + 6 + 1 |
| `registers` | 10 | 精确等于发送数 |
| `forward requests` | 6 | A 四帧 + B 一帧 + 未注册一帧 |
| `bad envelope` | 6 | 五类拒绝 + 5,000B |
| `unknown flags` | 1 | |
| `control frames` | 11 | = registers + 1 |
| `forwarded` | 3 | seq 1 / 4 / 5 |
| `forward bytes` | 136 | 8 + 120 + 8 |
| `no route` | 1 | seq=2 dst=999 |
| `self drop` | 1 | seq=3 dst=self |
| `no sender` | 1 | seq=91 未注册来源 |
| `oversize` | 0 | 守卫分支，不可达 |
| `fatal` | none | |

两条恒等式：`23 == 10 + 6 + 6 + 1`；`3 + 1 + 1 + 0 + 1 == 6`。

## 4. 自检过程中暴露并修掉的问题

### 4.1 产品侧（第一轮审计发现，v2 已修）

| 编号 | 问题 | 修法 |
|---|---|---|
| H-1 | 5,000 字节数据报触发 `recv_from` 10040 → 循环 `break` → 进程 0.8 s 退出**且退出码 0**，summary 照写 `datagrams: 0`，失败被伪装成正常收尾 | 缓冲改 65,535；超长/WouldBlock/超时分别处理；其它错误记 `fatal` 并以退出码 3 结束；summary 先落盘 |
| M-1 | 文档称"不信任信封 `src_peer`"，代码却是 `unwrap_or(env.src_peer)` | 改为 fail-closed：查不到来源就 `no sender` 丢弃，不再回退 |
| M-2 | `--listen 127.0.0.1:62056` 能成功绑定（实测 pid 39372），H2 门槛只靠脚本守 | 二进制级护栏：bind 前检查端口，命中 62056 直接 exit 1 |
| M-5 | 注册表用 `max(src_peer, dst_peer)` 做别名，一址多号时反查有歧义 | 只插 `dst_peer`；`src_peer` 非 0 且不等于 `dst_peer` 时才额外插入 |
| — | 未知 `flags` 的合法帧既不计入计数也不拒绝，只是"没有转发" | 新增 `unknown flags` 计数 + 日志 + 分类恒等式 |

### 4.2 产品侧（第二轮审计发现，v3 已修）

| 编号 | 问题 | 修法 |
|---|---|---|
| H-2 | v2 文档称 `no sender` 分支"真实可达并有用例"，但 `no sender : 0`、日志里 `unregistered` 命中 0 次、夹具只有两个**都已注册**的 socket——把第一轮的"暗示"升级成了"明确声明"，属退化 | 夹具增加第三个从不注册的 socket（`seq=91`、信封写 `src_peer=303`）；断言 `no sender == 1`；实测日志 `drop seq=91 from=127.0.0.1:62574 (unregistered source; envelope src_peer=303 not trusted) len=4` |
| M-2 | 注册丢包只断言 `<=`，且判词分母自指（`$Checks/$Checks`），守卫块被跳过时仍打印 `N/N` 并 exit 0 | `registers == 10` 精确断言；`$expectChecks = 68` 常量分母；`exit` 条件同时要求 `Checks == expectChecks` |

### 4.3 测试侧（不是产品缺陷，但会误判）

1. **PowerShell 的 uint64 乘法会走 double。** FNV-1a 累加器用 `[uint64]` 直接相乘，结果被悄悄
   转成双精度。改用 `System.Numerics.BigInteger` 每次取模 2^64；并且 `'{0:x16}'` 对 BigInteger
   会多打一个符号位（17 个字符），改为格式化后截取低 16 位。
2. **第一次运行真的丢了一个数据报。** 单发 A 的 REGISTER 没到达 Relay，于是 Relay 把发送者当成
   未知（`src_peer=0`），`seq=3` 的 dst=101 就落到 `no_route` 而不是 `self drop`。这不是计数误差，
   是回环上真实的一次丢包。处理方式：夹具改为周期性重注册（现为 10 次），并把注册条数改成
   精确断言——**丢一条就红**，而不是用不等式掩盖。
3. **out-dir 必须先存在吗？** v1 说"不存在直接报 `拒绝访问 (os error 5)`"，这条说法对
   `civlink-relay.exe` 是**错的**：`main.rs` 用 `fs::create_dir_all` 先建目录，真正会撞
   os error 5 的是**脚本侧**的 `Set-Content`（在跑之前写前置文件时）。v3 已改正：脚本自己
   `New-Item -ItemType Directory -Force` 建目录，Relay 不会因 out-dir 不存在而失败。
4. **计数正则不能用行尾锚点。** summary 里 `no sender : 1 (unregistered source…)`、`oversize`、
   `unknown flags` 三行数字后面还有说明，`\d+\s*$` 一律读成 -1，首跑因此报 3 项假 FAIL。改为只
   要求"行首名字 + 冒号 + 数字"。
5. **"超长包"用全零字节构造会考错路径。** 5,000 字节全零没有 `CVLR`，parser 判 `bad-magic` 而不是
   `payload-too-large`，日志计数错位。改用合法头 + 超长声明构造。**这条也修正了 v2 对 `-144934`
   失败根因的归类**：那 4 项 FAIL 是「3 项正则行尾锚点 + 1 项 5,000B 全零被判 bad-magic」，
   不是 v2 写的"4 项全由正则引起"。

### 4.4 表述边界修正

- 第一版写"两个方向都逐字节不变"，但夹具四帧全由 A 发、B 只收 → 本版补 B→A 的 `seq=5`，表述成立。
  **但方向≠状态隔离**：A→B 与 B→A 是在**同一个 Relay 进程、同一张 peers 表、同一个 PowerShell
  进程内的三个 socket** 上完成的，没有重启、没有清表。所以它证明的是"同一实例能双向路由"，
  不证明"跨实例/跨会话的状态隔离"。
- 第一版写"符合 H2 门槛"，实际只有脚本前置在守 → 本版是"代码级护栏 + 运行期实测未占用"。
- 第一版写"一个坏包不会让 Relay 停止"，在 5,000 字节场景下**是错的** → 本版限定为"任意 ≤65,535 字节
  的畸形数据报都不会让 Relay 停止；超过缓冲的情形由 `fatal` 以退出码 3 明确报告，但该分支
  本轮**没有用例**，属于'设计如此、未验证'"。
- **"头部三方一致"不成立**（第二轮审计 H-1）：v2 把"载荷前 8 字节"称为"头部 8 字节"。信封头
  在转发时被 `encode()` 重写（`flags` 清零、`src_peer` 覆盖），若真按"头部"比对，`src_peer`
  必然不一致。v3 全文改为"载荷前 8 字节"，并说明头部的定向改写是设计行为。
- `fatal` / 退出码 3（第二轮审计 M-1）：v2 在 §1 能力表、§4.3、§5"证明"三处以**已实现口吻**
  描述，但 67 条断言里没有一条构造 fatal 或断言 exit 3。v3 在能力表标注"该分支本轮没有用例"，
  在 §5 移出"证明"清单，移入"不证明"。

### 4.5 第二轮审计必改项逐项打勾

| 项 | 内容 | 状态 | 依据 |
|---|---|---|---|
| H-1 | "头部 8 字节"→"载荷前 8 字节"，删除"头部三方一致" | 已关闭 | §1 三方比对行、§4.4 第三条 |
| H-2 | `no sender` 分支无用例却声称可达 | 已关闭 | §3 步骤 9、§3.1 `no sender = 1`、§4.2 H-2 |
| M-1 | `fatal`/`exit 3` 零用例却以已实现口吻描述 | 已关闭（降级文案） | §1 能力表末行、§4.4 末条、§5"不证明" |
| M-2 | 注册丢包无绝对断言、判词分母自指 | 已关闭 | §3 步骤 3、§4.2 M-2、`$expectChecks = 68` |
| M-3 | `-144934` 四项失败根因归类错误 | 已关闭 | §4.3 第 5 条 |
| M-4 | "两个方向"未声明状态隔离缺失 | 已关闭 | §4.4 第一条 |
| M-5 | 三条断言只匹配程序自己打印的字符串 | 部分（保留并声明） | §5"不证明"末条：`reconciliation ==`、`datagram identity ==`、`sees PLAINTEXT` 三条是**格式断言**，不是行为断言；行为由 §3.1 的精确计数与 §3 步骤 9 的丢弃日志共同支撑 |
| L-1 | `parse()` 无 `len > 20` 校验 | 未修（列缺陷） | §6.1 |
| L-2 | `--listen-seconds` 默认静默 60 | 未修（原型行为） | §6.1 |
| L-3 | `wallclock_stamp()` 打 UTC 无标注 | 未修（列缺陷） | §6.1；本文所有日志时间戳均为 **UTC**，本地时间 = UTC+8 |
| L-4 | `_probe-f3b`/`_probe-f3b2` 未入档 | 未修（早期探测目录，非本文证据） | §6.1 |
| L-5 | out-dir 叙事与 `create_dir_all` 矛盾 | 已关闭 | §4.3 第 3 条 |
| L-6 | 5 字节文件实为 BOM+CRLF | 已关闭 | §6 说明 |
| L-7 | §7 引用 F3-C 且其证据目录"不存在" | 已关闭 | §7：F3-C 已落盘（`docs\F3C-BACKOFF-20261114.md`，v2，证据 `M0A\captures\F3C-backoff-selftest-20261114-151943`） |
| L-8 | §3 无法导出 `registers = 10` | 已关闭 | §3 步骤 3 写明 3+3+2+2 |
| L-9 | `send_to` 短写分支不可达 | 未修（列缺陷） | §6.1 |

### 4.6 运行历史（含失败，全部点名）

| 证据目录（`CivLink-M0A-audit\M0A\captures\`） | 结果 | 说明 |
|---|---|---|
| `F3B-relay-selftest-20261114-142256` | FAIL 3/40 | 第一版脚本首次运行：uint64 精度、丢包、out-dir 三个问题 |
| `F3B-relay-selftest-20261114-142419` | FAIL 6/41 | 第一版脚本：bad-magic 用例构造错误（被解析成 DATA） |
| `F3B-relay-selftest-20261114-142718` | PASS 41/41 | 第一版脚本稳定后 |
| `F3B-relay-selftest-20261114-142803` / `-142813` / `-142818` | PASS 43/43 ×3 | 第一版脚本三次连跑（**已被取代**） |
| `F3B-relay-selftest-20261114-144934` | FAIL 4/67 | revision 2 首跑：3 项正则行尾锚点 + 1 项 5,000B 全零被判 bad-magic |
| `F3B-relay-selftest-20261114-145026` | PASS 67/67 | v2 采信值（**已被 v3 取代**：无 `no sender` 用例、判词分母自指） |
| `F3B-relay-selftest-20261114-152749` | FAIL（判词） | v3 首次跑：68 条断言全 PASS，但 `$expectChecks` 尚未填（打印 `68 of 0`），判词 FAIL——说明新的分母检查确实生效 |
| `F3B-relay-selftest-20261114-152821` | **PASS 68/68** | **v3 采信证据** |

## 5. 结果：证明什么、不证明什么

**证明（本机回环，限本原型实现）**

- 五类畸形输入 + 未知 `flags` + 超长输入，都能被拒绝并**继续服务**（≤65,535 字节任意输入不会让
  Relay 停止）。
- `dst_peer` 路由、发送者 fail-closed 反查、自投递丢弃、目的未知不发送、**未注册来源丢弃**，
  五条路径都按设计工作，各有独立用例（最后一条是本轮新增）。
- 载荷在**两个方向**上都逐字节不变（A→B 的 8B 与 120B、B→A 的 8B；载荷前 8 字节十六进制与
  FNV-1a 64 三方一致）。
- Relay 全程未占用 62056，并且**二进制本身**拒绝绑定 62056（不只是脚本前置）。
- 分类恒等式与对账两行都闭合：`23 = 10 + 6 + 6 + 1`、`3 + 1 + 1 + 0 + 1 = 6`。
- 注册条数精确为 10（不靠不等式容忍丢包）。

**不证明**

- 不证明真实双机、真实 Relay 部署、跨网、公网 NAT 下的行为。
- 不证明游戏侧任何行为：没有任何字节进入 Civ6 进程。
- 不证明加密、身份、抗重放（F3 原型按设计不实现）；也不证明"注册过的 peer_id 不能被冒用"。
- 不证明时延：回环 RTT 与 0.5s 首窗预算无关；跨网 RTT 仍需 M0-B。
- 不证明长稳：单次运行约 6.9 秒。
- **不证明 >65,535 字节的输入已被处理**：该分支是守卫，IPv4 UDP 到不了；`oversize = 0` 是
  "未触发"，不是"已验证超长被正确丢弃"。
- **不证明 `fatal` / 退出码 3**：本轮没有构造该分支的用例，只有代码阅读与"summary 先落盘"的
  顺序保证。要证明需要制造真实的收包失败（例如运行期关闭 socket）。
- **不证明多 Peer 并发、乱序、重排**：夹具三个 socket、全部串行发送。
- **不证明跨实例/跨会话状态隔离**：所有方向共用同一 Relay 实例与同一 peers 表。
- **不证明三条格式断言的行为含义**：`reconciliation ==`、`datagram identity ==`、`sees PLAINTEXT`
  只匹配程序自己打印的字符串；它们证明"summary 写了这些行"，不证明"数值因此正确"。
  数值正确性由 §3.1 与第 3.1 节的精确计数断言承担。

## 6. 文件身份（SHA-256，实测）

代码与脚本：

| 文件 | 字节 | SHA-256 |
|---|---:|---|
| `civlink\relay\src\main.rs` | 22,246 | `AAB64B53186BB661428C5000E1629EDE8BE3A77E98FB336613B961FA00EAA472` |
| `civlink\relay\Cargo.toml` | 479 | `93C7D4DA43D523693C83644234CBE95FBDD43EF120489031D50491E21B9614D1` |
| `civlink\relay\target\release\civlink-relay.exe` | 262,144 | `AE03327E417E89A3A885D87A9C7330CE331EAE9E4C24AE27B3AB5B13C0225BE3` |
| `civlink\run-f3b-relay-selftest.ps1`（revision 3） | 31,710 | `785D6E39FB151CA7F9342FC0FCC41F67E8CAEA3F80B31B4DF7FE53E2F45E266A` |
| `civlink\run-f3b-relay-selftest.ps1.bak-16630`（revision 1 备份） | 19,041 | `2D4A9E1E556DAA911301CB62179E72DD0FD348DAB40434825E4D3F17B3CB95F7` |

第一版（已作废）的身份：`main.rs` 15,579 B `C2337406…`、exe 253,952 B `88AAB644…`。
v2 的脚本身份（已作废）：28,979 B `574FFEC8…`。

证据目录（`CivLink-M0A-audit\M0A\captures\F3B-relay-selftest-20261114-152821\`，共 10 个文件）：

| 文件 | 字节 | SHA-256 |
|---|---:|---|
| `relay-summary.txt` | 1,528 | `609FE0B4FE98A4467E55309B04533CA44B37D7E8918886B944AA41C26FC7DA0D` |
| `relay-log.txt` | 1,827 | `27186002EBF0180C250213058B00E054682F4793477801A03B362724F54B8D16` |
| `result.txt` | 950 | `ADB84AD2DC0559D196428888782D0F09D32803787B8C369B0EAC6F1E7B11B36D` |
| `bind-check.txt` | 24 | `D386A4E1EE3A12F7BAFF08FAC8CD1172A461C8FADFF7D6E1AEA5453785DCBF18` |
| `exit.txt` | 12 | `01AD8A20D9C655F39D931C98ACC135EF2B5505ECCEE6B6845F1667FF01CAD1AE` |
| `relay-console.txt` | 1,839 | `A47175405381FA4999C6DE784940DA4E161BC46EB03DCF856FFCE16824F5A395` |
| `relay-stderr.txt`（干净运行，空） | 5 | `F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295` |
| `negative-62056-console.txt`（空） | 5 | `F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295` |
| `negative-62056-stderr.txt` | 106 | `6B54E7DBD747DA2F9AC003D0B3F978546CDDCFA6ABF944E53C5470426B6FD1CC` |
| `stop.txt` | 6 | `A0B28CDF92E250A1A93294D91144A0F893D27197D56B39991CC421768794005F` |

说明：`relay-stderr.txt` 与 `negative-62056-console.txt` 都是 5 字节且同哈希，实际内容为
`EF BB BF 0D 0A`（PowerShell `Set-Content -Encoding UTF8` 写入的 BOM + CRLF），不是"纯 CRLF 空文件"。
前者是"干净运行 stderr 为空"，后者是"拒绝绑定 62056 时没有 stdout 输出"，同哈希属预期。

### 6.1 已知未修缺陷（代码层，不影响上述断言的成立）

- `parse()` 没有 `len > 20` 之外的下界校验细节（L-1）：短包走 `too-short`，但没有对
  `payload_len == 0` 的空载荷做专门断言。
- `--listen-seconds` 缺省为 60，参数缺失时静默采用而非报错（L-2）。
- `wallclock_stamp()` 输出 UTC 且不带时区标记（L-3）；本轮日志 `07:28:29` 对应本地 `15:28:29`。
- `send_to` 的短写分支（`Ok(n) if n != len`）在 UDP 上不可达，未加用例（L-9）。
- 早期探测目录 `_probe-f3b`、`_probe-f3b2` 未纳入本文证据表（L-4），它们是脚本调试期产物。

## 7. 与其它文书的关系

- 设计依据：`docs\F3-DIRECT-RELAY-DESIGN-20261114.md` v0.3（§3.2 出向键属 **Agent 侧 / F3-A**、
  §4 Relay 透明转发、§4.1 加密范围声明、§5.2 模拟对端回包策略、§5.3 H2 门槛）。
- 上游：F3-A（`docs\F3A-DIRECT-FORWARD-20261114.md`）验证了 Agent 侧直连转发；
  本文验证 Relay 侧按 `dst_peer` 路由。两者都还缺同一块：**游戏进程内注入**（M0-B）。
- 审计：`docs\F3B-REVIEW.md`（第一轮，43 项）、`docs\F3B-REVIEW-2.md`（第二轮，67 项）、`docs\F3B-REVIEW-3.md`（第三轮，68 项，**通过**，0 阻断/0 高/0 中/5 低）。
- 同族已完成：F3-C（`docs\F3C-BACKOFF-20261114.md`，退避语义，v2 26 项，证据 `-151943`）、
  F3-D（`docs\F3D-PRESSURE-20261114.md`，40,000 帧压力，证据 `-151218`）。
- **证据目录布局（第三轮审计 E2）**：F3-B 自身证据在审计树 `CivLink-M0A-audit\M0A\captures\`（本文件 §6），
  F3-A / F3-C / F3-D 证据在**项目根** `C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\`——两棵 `M0A` 树并存，
  按审计树解析 F3-C/F3-D 路径会得到 `Test-Path=False`（第二轮 L-7"不存在"即因此误报）。
- 下游未完成：F3-E（故障注入）。

## 8. 下一步

1. F3-E：对端退出、Relay 掉线、通道 down、乱序/重复/缺口、超长帧、FakeEndpoint 缺失、池耗尽，
   逐项断言计数与状态，不引入伪协议应答。**F3-E 必须包含 `fatal` / 退出码 3 的真实用例**
   （本轮的缺口），否则"致命错误不伪装"始终只是代码阅读结论。
2. F3-E 之后按 REV-016 进入 F4（发布候选），并在 F4 明确：模拟证据不得写成"双人真实联机已通过"。
