# F3-B Relay 转发原型（第二版）· 第二轮独立审计报告

## 0. 审计元信息与局限

| 项 | 值 |
|---|---|
| 审计对象 | `docs\F3B-RELAY-FORWARD-20261114.md`（第二版，207 行，15,389 B，`52FEE699320241519DAF3DCD566EF2C13EFA315DFD30F01DB0EEA2C4EF99A7B1`，mtime 14:51:30） |
| 被审实现 | `civlink\relay\src\main.rs`（583 行，22,246 B）、`civlink\relay\Cargo.toml`（479 B）、`civlink\relay\target\release\civlink-relay.exe`（262,144 B） |
| 被审自检 | `civlink\run-f3b-relay-selftest.ps1`（535 行，28,979 B）、`civlink\run-f3b-relay-selftest.ps1.bak-16630`（395 行，19,041 B） |
| 采信证据 | `M0A\captures\F3B-relay-selftest-20261114-145026\`（10 文件） |
| 审计时间 | 2026-11-14 14:51–15:22（UTC+8，`China Standard Time`） |
| 审计方式 | **只读**：仅 `Get-FileHash`、`[IO.File]::ReadAllLines`、`Select-String`、`Get-ChildItem` 等读操作；**未修改**任何源码/脚本/证据，**未重新运行**自检脚本（避免覆盖证据目录），**未启动**任何 Relay 实例 |
| 上一轮报告 | `docs\F3B-REVIEW.md`（571 行，52,332 B，`8E102B9AC082E762EAAF698C9BB6BDBC5A96EE45A69C302BC24BC798A2E11D57`），结论 0 阻断 / 1 高 / 4 中 / 6 低，裁定"有条件通过"，提出 12 项必改 |
| 设计依据 | `docs\F3-DIRECT-RELAY-DESIGN-20261114.md`（v0.3，127 行，11,532 B，`998F9A1E5F76CAF097E71883F208E55F5FFD6EAAB1F7B883401D68B3F7430469`） |

### 审计局限（必须随结论一起阅读）

1. **未反编译 exe**。`civlink-relay.exe` 与被审 `main.rs` 之间只有 `target\release\civlink-relay.d`（180 B，仅一条 `src\main.rs` 依赖记录）作为构建关联的间接旁证，**不是**可复现构建证明。本轮不能排除"exe 由另一份源码编译"的可能。
2. **未重跑自检**。全部结论基于磁盘上既存证据的静态核对；脚本可重跑性（同一机器二次运行是否仍 67/67）未验证。
3. **未做行为探测**。所有关于运行时行为的判断来自源码阅读 + 既存日志，不含本轮实测。
4. **仓库不是 git**，无法做 diff/时间线取证，版本关系只能靠 mtime 与哈希推断。
5. **E1–E7 在仓库内没有逐条定义文本**（`docs\F3A-REVIEW.md:24`、`:466` 已确认，全仓 grep 只找到"前置条件 E1-E7 落实后启动"这类引用），因此设计 v0.3 所述"E1-E7 落实后启动 F3"这一前提**无法逐条验收**。
6. 本报告对"证明"的判定标准是：**该断言存在独立于被测对象自述的证据**（外部输入、独立观测、可复算的常量），而不是"脚本打印 PASS"。

---

## A. 证据真实性（重算哈希）

### A.1 15 项哈希逐项重算：全部一致，零偏差

`Get-FileHash -Algorithm SHA256` 逐项重算，与文档 §6 `:164-170`（代码脚本 5 行）与 `:178-187`（证据 10 行）比对：

| # | 文件 | 实测字节 | 实测 SHA-256 | 文档值 | 结论 |
|---:|---|---:|---|---|---|
| 1 | `civlink\relay\src\main.rs` | 22,246 | `AAB64B53186BB661428C5000E1629EDE8BE3A77E98FB336613B961FA00EAA472` | 同 | 一致 |
| 2 | `civlink\relay\Cargo.toml` | 479 | `93C7D4DA43D523693C83644234CBE95FBDD43EF120489031D50491E21B9614D1` | 同 | 一致（第一轮的 583 B 偏差已修正） |
| 3 | `civlink\relay\target\release\civlink-relay.exe` | 262,144 | `AE03327E417E89A3A885D87A9C7330CE331EAE9E4C24AE27B3AB5B13C0225BE3` | 同 | 一致 |
| 4 | `civlink\run-f3b-relay-selftest.ps1`（rev 2） | 28,979 | `574FFEC8B607DE27D1AAE020C032E43F147300B9CC3BDC0AFCA20A7E6758F1C8` | 同 | 一致 |
| 5 | `civlink\run-f3b-relay-selftest.ps1.bak-16630`（rev 1） | 19,041 | `2D4A9E1E556DAA911301CB62179E72DD0FD348DAB40434825E4D3F17B3CB95F7` | 同 | 一致 |
| 6 | `relay-summary.txt` | 1,528 | `76C0963D0DF46DA6FBA9C02ED7FCD572730BAC53FD56071D4EF275D3492B6205` | 同 | 一致 |
| 7 | `relay-log.txt` | 1,718 | `EFDC12EAA5EB2B8029983736E1C484B56E216BE35E009880C346442553A4FB62` | 同 | 一致 |
| 8 | `result.txt` | 950 | `52EF0FCD36726CF8CE39290F650180B4F50A43E4A1EC9343EAF154A977E6CCC9` | 同 | 一致 |
| 9 | `bind-check.txt` | 24 | `D386A4E1EE3A12F7BAFF08FAC8CD1172A461C8FADFF7D6E1AEA5453785DCBF18` | 同 | 一致 |
| 10 | `exit.txt` | 12 | `01AD8A20D9C655F39D931C98ACC135EF2B5505ECCEE6B6845F1667FF01CAD1AE` | 同 | 一致 |
| 11 | `relay-console.txt` | 1,839 | `4B4AAA78C4BF3494CD302899ABA5C1D7BE925DC0C75FEBDF8906D5F9FB8ED50A` | 同 | 一致 |
| 12 | `relay-stderr.txt` | 5 | `F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295` | 同 | 一致 |
| 13 | `negative-62056-console.txt` | 5 | `F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295` | 同 | 一致（与 #12 同哈希，见 L-6） |
| 14 | `negative-62056-stderr.txt` | 106 | `6B54E7DBD747DA2F9AC003D0B3F978546CDDCFA6ABF944E53C5470426B6FD1CC` | 同 | 一致 |
| 15 | `stop.txt` | 6 | `A0B28CDF92E250A1A93294D91144A0F893D27197D56B39991CC421768794005F` | 同 | 一致（第一版缺失已补齐） |

**结论：15/15 一致，0 偏差。** 第一轮 A 节的两项事实错误（Cargo.toml 字节数、stop.txt 缺失、console/stderr 未拆行）在第二版全部修正。

### A.2 §5 声称的算术：逐条咬合

`relay-summary.txt` 全文 30 行实读，与文档 §5 `:146`、§1 `:33` 的两条恒等式对照：

| 文档声称 | summary 实际行 | 复算 | 结论 |
|---|---|---|---|
| `22 = 10 + 5 + 6 + 1` | `datagrams: 22`、`registers: 10`、`forward requests: 5`、`bad envelope: 6`、`unknown flags: 1` | 10+5+6+1 = 22 | 成立 |
| `forwarded+no_route+self_drop+forward_fail+no_sender = forward_requests = 5` | `forwarded 3`、`no route 1`、`self drop 1`、`forward fail 0`、`no sender 0` | 3+1+1+0+0 = 5 | 成立 |
| `forwarded = 3` | `forwarded : 3` | — | 成立 |
| `forward bytes = 136` | `forward bytes : 136` | 8+120+8 = 136（`relay-log` 三条 forward 的 len=8 / len=120 / len=8） | 成立 |
| `unknown flags = 1` | `unknown flags : 1` | 日志 `reject unknown-flags=0x02` 恰 1 条 | 成立 |
| `bad envelope = 6` | `bad envelope : 6` | 五类 reject 各 1 + 5000B 1 = 6 | 成立 |
| `oversize = 0` | `oversize : 0` | — | 成立（且是"未触发"，见 B.4） |
| `fatal = none` | `fatal : none` | — | 成立 |

`relay-log.txt` 全文 23 行逐行核对，register 计数为 **10**：`:2,3,4` peer=101、`:5,6,7` peer=202、`:8,9` peer=101、`:21,22` peer=202——与 `registers: 10`、`result.txt` 的 `registrations sent: 10` 三方一致。转发行 3 条（`:10` seq=1、`:13` seq=4、`:23` seq=5），拒绝行 6 条（`:14-18` 五类 + `:20` 5000B），另 `:11` no-route、`:12` self-drop、`:19` unknown-flags。**行数与 summary 各项之和完全对应，无隐藏行、无多余行。**

### A.3 目录完备性：没有"列了但不存在"，但存在"存在但未列"

- 文档 `:174` 声称证据目录"共 10 个文件"；实测该目录**恰为 10 个文件**，且文档 `:178-187` 的 10 行与实测文件名、字节数**一一对应**，无缺项、无幽灵项。
- 但 `M0A\captures\` 下另有 **2 个未被文档点名的目录**：`_probe-f3b`（14:26:47）与 `_probe-f3b2`（14:27:04），各含 `relay-log.txt`（224 B）、`relay-summary.txt`（1,011 B）、`stop.txt`（6 B），其 summary 为**旧 schema**（无 `unknown flags` / `no sender` / `oversize` / `fatal` / `datagram identity` 行，reconciliation 仅四项）。这两个目录不是本文采信证据，但它们是"同一 exe 的早期探测运行"，未在 §4.4 的运行历史表中出现（§4.4 列 8 行，`M0A\captures` 实有 8 个 `F3B-relay-selftest-*` + 2 个 `_probe-*`）。属完整性瑕疵，见 **L-4**。

### A.4 历史失败运行：目录真实存在，但一处归类与证据不符

§4.4 `:127-134` 点名的 6 个目录 + `142718` 全部真实存在，`result.txt` 首行实测：

| 目录 | 实测首行 | 文档 §4.4 | 结论 |
|---|---|---|---|
| `-142256` | `FAIL (3 of 40 failed)` | FAIL 3/40 | 一致 |
| `-142419` | `FAIL (6 of 41 failed)` | FAIL 6/41 | 一致 |
| `-142718` | `PASS (41/41)` | PASS 41/41 | 一致 |
| `-142803` | `PASS (43/43)` | PASS 43/43 ×3 | 一致 |
| `-142813` | `PASS (43/43)` | 同上 | 一致 |
| `-142818` | `PASS (43/43)` | 同上 | 一致 |
| `-144934` | `FAIL (4 of 67 failed)` | FAIL 4/67 | 一致 |
| `-145026` | `PASS (67/67)` | **PASS 67/67（采信）** | 一致 |

抽查 3 个的内容级核对（不止首行）：

1. **`-142419`（抽查一）**：失败项实测为 `frame 1 src_peer filled by relay = 101`、`datagrams = 8`、`registers = 2`、`no route = 1`、`self drop = 1`、`log records self-drop for seq=3`；其 summary 为 `datagrams 7 / registers 1 / peers seen 1`。**证实回环确实会丢注册**（A 注册丢失导致 B 侧无路由）。文档 §4.2 `:104-105` 的"第一次运行真丢 1 个数据报"与这一目录互证，可信。
2. **`-142256`（抽查二）**：`FAIL (3 of 40 failed)`，失败项 `log seq=1 hash matches sender`、`log seq=4 hash matches sender`、`log records bad-magic rejection`；`payload1 fnv1a64 : 0000320000005415`（错值，第一版 BigInteger 精度 bug 的实证）。与 §4.2 第 1 条互证。
3. **`-144934`（抽查三）**：`FAIL (4 of 67 failed)`，失败项**实测**为：
   - `unknown flags = 1`
   - `no sender = 0`
   - `oversize = 0 (65535 buffer cannot overflow on IPv4 UDP)`
   - `log records bad-magic rejection`

   而文档 §4.4 `:133` 的说明是"计数正则行尾锚点 **3 项**、5,000 字节全零包被误判 **1 项**"。**归类与证据不符**：前三项确属同族（都是计数正则未锚定的连带失败），但第 4 项 `log records bad-magic rejection` 的成因是 5000B 全零数据报**不带 `CVLR` 魔数**，被 `parse()` 判为 `bad-magic` 而非 `payload-too-large`（该目录 `relay-log` 第 20 行实测为 `reject len=5000 kind=bad-magic`），导致 bad-magic 计数变成 2、断言期望 1 而失败。这属**用例构造错误**，不是"正则锚点"问题。文档把两类根因合并成一句"3 项正则 + 1 项 5000B 误判"，读者无法从这句话还原真实失败原因。见 **M-3**。
   - 另需注意：`-144934` 与 `-145026` 的 **relay sha256 完全相同**（`AE03327E…0225BE3`），script sha256 不同（`472003C1…E40B21BDA` vs `574FFEC8…6758F1C8`）。这说明两次运行**产品侧代码未变，只改了脚本**，产品计数在两版脚本下逐字相同（22/5620/6/11/1/10/5/3/136/0/1/1/0/0/none）。这是证据链的强项，值得在文档中明确写出（当前未写）。

### A.5 A 节小结

证据**真实、可复算、内部自洽**。哈希零偏差、算术零缺口、文件数与文档声明一致。唯一实质问题是 §4.4 对 `-144934` 失败根因的归类不准确（M-3），以及两个探测目录未入档（L-4）。**A 节不构成阻断。**

---

## B. 断言强度

### B.1 精确计数：67 = 67，文档声称属实

- `Select-String -Pattern "^\s*Check '"` 命中 **67** 次；`Select-String -Pattern "Check '"` 亦为 **67** 次（无注释内伪命中）。
- `result.txt` 首行 `F3B-RELAY-SELFTEST: PASS (67/67)`，且判词分母在 `:506` 为 `$script:Checks/$script:Checks`（见 M-2），只有"实际执行 67 条且全过"才会打印 `67/67`。
- **文档 `:3`、`:83` 声称的 67 项与脚本实际 `Check` 调用数完全一致，无虚报。**

### B.2 逐类排查：(a) 恒真 / (b) 自洽恒等式 / (c) 放宽不等式 / (d) 弱比较

**(a) 参数为字面 `$true` 的恒真断言：0 条。**
全文 `$true` 仅出现于 `:155`、`:156`、`:157`、`:189`、`:190`、`:191`（`ProcessStartInfo` 属性赋值）与 `:202` `$ready = $true`。第一轮 `:139/:140` 两条恒真断言**已删除**。

**(b) `$a -eq $a` 形式的自洽恒等式：0 条。**
第一轮 M-4 点名的 `:310` 自洽恒等式已消失。

**(c) 用 `-ge`/`-le` 放宽设计值的断言：1 条（另 1 条为合理容差）。**

- `:424` `Check 'registers counted <= sent' ($rCount -le $script:RegistrationsSent)` —— **唯一放宽项**。方向是"计数不超过发送"，即**只在下界不设防**：注册丢 1～10 个都不会 FAIL。
- `:444` `Check 'summary runtime agrees with wall clock (+-3s)' ([bool]($reported -ge 0 -and [math]::Abs($reported - $measured) -le 3))` —— 容差型，合理。
- 其余 `-ge` 全部出现在**守卫**而非断言中：`:201`、`:340`、`:348`、`:358`、`:463`、`:473`，以及 `New-Envelope` 的 `:84`、`:86`、`:95`。守卫本身不改变判词，但会改变"执行了多少条"（见 M-2 的分母问题）。

**(d) 只比长度或前 N 字节的弱断言：0 条真正弱的比较，但有 3 条"自己匹配自己"。**

- `:345`、`:352`、`:363` 用 `Compare-Object -SyncWindow 0` 做**逐字节全量**比较（8B / 120B / 8B），不是前缀比较。
- `:346`、`:353`、`:467`、`:477`、`:484` 的 FNV 比对是**接收侧实测值 vs 发送侧基准值**，属真比对。
- 但 `:426` `Check 'datagram identity line present and =='`、`:437` `Check 'reconciliation =='`、`:438` `Check 'summary states plaintext'` 三条，判据分别是 `$summaryText -match '(?m)^datagram identity\s*:\s*datagrams =='`、`...reconciliation\s*:.*\s==\s`、`...-match 'sees PLAINTEXT'` —— **匹配的是被测程序自己打印的字符串**。只要 `main.rs` 打印了 `==` 字样就通过，即使等式两边数字不等（数字不等时程序会打印 `!=`，但这条正则只认 `==`，所以它其实在断言"打印了 `==`"，**间接**约束了等式成立）。判定：**弱**，且不是独立证据（独立证据应是脚本自己用 `:413-418` 取出的数字复算）。见 **M-5**。

### B.3 第一轮 M-4 是否解决：**部分解决**

| 第一轮问题 | 第二版状态 | 判定 |
|---|---|---|
| `:310` 自洽恒等式 | 已删除 | 已解决 |
| `:311` `registers >= 5` 掩盖丢包 | 改为 `:424` `-le` 上界 + `:425`/`:427` 用变量 `$rCount` | **未解决，换了形式** |
| 计数用 `>=` 放宽 | `:421-423`、`:428-436` 全部改为精确 `-eq` 期望常量（`:404-410` 定义 `$expectForwardRequests=5` 等 7 个常量） | 已解决 |

关键残留：`:425` `Check 'datagrams = registers + 5 + 6 + 1' ($dCount -eq ($rCount + $expectForwardRequests + $expectBadEnvelope + $expectUnknownFlags))` 与 `:427` `Check 'control frames = registers + 1' ((Get-Counter ...) -eq ($rCount + 1))`，**两式的基准都是运行时读出的 `$rCount` 而非常量 10**。因此"注册是否真的到了 10 条"**没有任何断言**，只有 `:419` 一句 `Write-Host "[info] registrations sent {0}, counted {1}, lost {2}"` 打印。

缓解事实（必须同时写上，否则会高估严重度）：`-142419` 证明丢注册会**连带**触发 `:428/:429/:432` 等精确计数 FAIL（该目录正是这样挂的 6 项），所以不是完全无防护。真正的盲区是：**只丢一次、且不影响本轮被断言的方向**的注册丢失。故定级 **中**（M-2），不是高。

### B.4 五条拒绝路径是否真的各走不同 parser 分支：**是，构造正确**

`civlink\relay\src\main.rs:100-124` 的判定顺序：`len<20 → too-short`；`buf[0..4]!=MAGIC → bad-magic`；`buf[4]!=VER → bad-version`；`payload_len>1280 → payload-too-large`；`buf.len()<20+payload_len → truncated`。

| 用例 | 脚本构造 | 实走分支 | 是否可能落到别的分支 |
|---|---|---|---|
| too-short | `:286` `New-Object byte[] 12`（全零） | `len<20` | 否 |
| bad-magic | `:283-284` `$badMagic = New-Object byte[] 24; $badMagic[4] = 1` | `buf[0..4]` 全 0 ≠ `CVLR` | 否。magic 先于 version 判定，`[4]=1` 只是绕开"全零恰好被当 too-short"的直觉，实际由 magic 命中 |
| bad-version | `:288` `-Version 2 -TotalBytes 24` | `buf[4]=2 ≠ 1` | 否。`payload_len` 字段为 0（无 payload），不会落 truncated |
| payload-too-large | `:289` `-DeclaredPayloadLen 1281 -TotalBytes 24` | `1281 > 1280` | 否 |
| truncated | `:290` `-DeclaredPayloadLen 100 -TotalBytes 60` | `60 < 20+100` | 否 |

`relay-log.txt` 实测五条 kind 各 1 条（`:14` too-short len=12 / `:15` bad-magic len=24 / `:16` bad-version len=24 / `:17` payload-too-large len=24 / `:18` truncated len=60），与构造一一对应。**第一轮"声称 bad-magic 实际被解析成 DATA"的缺陷已彻底修复**，且脚本 `:280-282` 注释主动记录了这个历史坑。

### B.5 5,000 字节用例：文档表述**已如实**，不再暗示验证了超长缓冲

- 脚本 `:309` `New-Envelope -Flags 0x00 -DstPeer 0 -DeclaredPayloadLen 1281 -TotalBytes 5000` → 走 `payload-too-large`，不是缓冲溢出。
- 脚本注释 `:304-308` 明写"the point of the check is that the Relay is still serving afterwards. With RECV_BUF = 65535 an IPv4 UDP payload cannot exceed the buffer, so the WSAEMSGSIZE branch stays a guard rather than a reachable path."
- 文档 §1 `:44-46`："收包缓冲 65,535 字节，因此 IPv4 UDP 的有效载荷（最多 65,507 字节）**无法**撑破缓冲；`WSAEMSGSIZE`（10040）分支是**守卫生效**，不是可达路径，正常审计不应把它当成'超长包已被拒绝'的证据。"
- 文档 §5 `:155-156`："**不证明 >65,535 字节的输入已被处理**：该分支是守卫，IPv4 UDP 到不了；`oversize = 0` 是'未触发'，不是'已验证超长被正确丢弃'。"

**判定：表述到位，无可指摘。** 这是第二版相对第一版最扎实的一处改进。唯一可加强的是把 `:76` 的"被 parser 判 `payload-too-large`"与"仍在服务"两件事分开描述得更醒目，但目前不构成缺陷。

### B.6 反向帧 `seq=5` 是否构成"第二个方向"的证据：**构成双向路由证据，但不构成状态隔离证据**

事实：
- 脚本 `:315-317` 先 `Send-Register -Client $peerB -PeerId $peerIdB -Times 2`，再由 `$peerB` 发 `seq=5` dst=101；`:360-363` 断言 A 收到、`dst=101`、`src=202`、逐字节一致。
- 日志 `:23` 实测 `forward seq=5 src_peer=202 dst_peer=101 len=8 hash=c6c9f694beb606fd head=17320000ffff35ba -> 127.0.0.1:62712`。
- **两个 peer 是同一个 PowerShell 进程内的两个 `UdpClient`（`peerA` `:220`、`peerB` `:222`），不是两个进程、不是两台机器、不是两个 Relay。**

因此：
- 它**证明**了 Relay 能按 `dst_peer=101` 反向查到 A 的地址并投递，且 `src_peer` 被正确填成 202 —— 这是真实的方向对称性证据，第一轮的缺口确实被补上了。
- 它**不证明**两个方向的状态互相独立：`peers` 表、单线程循环、`stats` 全部共享，反向帧的通过可能依赖正向帧建立的注册状态（事实上 `:315` 的补注册就是为了这个）。文档 §5 `:144`"载荷在两个方向上都逐字节不变"这句话**字面成立**，但读者容易顺势理解成"双向通道互相独立"，而 §5 的"不证明"清单里**没有**这一条。见 **M-4**。

---

## C. 与设计 v0.3 的一致性

逐条核对 `docs\F3-DIRECT-RELAY-DESIGN-20261114.md`：

### C.1 §6 `:42`：Relay 只做身份验证 / 按 dstPeer 转发 / 限速 / 统计

| 设计要求 | 实现状态 | 结论 |
|---|---|---|
| 按 dstPeer 转发 | `main.rs:424-440` 查 `peers` 表 `send_to` | 符合 |
| 统计 | `:483-563` 完整 summary + 两条恒等式 + 日志 | 符合 |
| 身份验证 | 无凭证、无签名（`main.rs` 无任何 auth 代码）；文档 §2 `:54` 自认"谁注册谁就是那个 `peer_id`" | **未实现，但文档如实声明**；设计 §4.1 `:74` 明确"F3 原型阶段不实现加密，身份绑定属 M0-B" → 属设计允许的原型裁剪 |
| **限速** | **完全没有**（无令牌桶、无速率计数） | 文档 §2 `:54` 自认"无限速"。与设计 §6 的能力清单有**落差**，但原型裁量范围内；建议在"不证明"中显式列出（当前未列，见 D.3） |

### C.2 §6 `:42` / §4.3 `:78`：62056 载荷原样透明转发、不擅自重传（RFC 8085, P0-3）

- **载荷原样：符合。** `encode()` `:126-136`：`out[HDR..HDR + payload.len()].copy_from_slice(payload)`，长度与内容均不改。三轮逐字节比对（`:345` 8B、`:352` 120B、`:363` 8B）+ FNV 一致，可信。
- **不重传：符合。** `:442-474` 每次收到 DATA 只 `send_to` 一次，`Ok(sent) if sent == n` 记 `forwarded`，否则记 `forward_fail`，无重试循环、无队列、无重排缓冲。
- **一进一出：符合。** 单线程顺序处理，无 fan-out 代码。

### C.3 **偏离项（新发现）：Relay 重写了 20 字节头部**

`encode()` `:126-136` 逐字段重写整个头部：

```
out[0..4]  = MAGIC
out[4]     = VER
out[5]     = 0                                   // flags 强制清零
out[6..10] = dst_peer
out[10..14]= src_peer                            // 由「已认证的发送者地址反查值」覆盖
out[14..18]= seq                                 // 原样回显
out[18..20]= payload.len()
```

- `flags` 清零对 DATA 帧**实际是空操作**（`:368` 已把 `flags != 0` 的帧全部走 `unknown flags` 分支丢弃，能到发送路径的帧 `flags` 必为 0）。
- `src_peer` 被**覆盖**：信封里的 `src_peer` **不被信任**（这正是第一轮 M-1 要的 fail-closed），日志 `:453` 打印的也是 `sender` 而非 `env.src_peer`。这是**安全上正确**的行为，但它意味着 **Relay 输出的头部与输入的头部不相同**。
- 后果：文档 §1 `:32` 与 §5 `:144` 所称的"**头部 8 字节十六进制**…三方一致"，若按字面理解（对头部做三方比对），**在存在 `src_peer` 覆盖的情况下不可能成立**；而实际被记录和比对的是**载荷**的前 8 字节。见 **H-1**。
- 同时，设计 §6 的"载荷 100% 透明"说的是**载荷**，头部改写不违背该条；但文档从未声明"头部会被改写"，而是一再以"头部"命名被比对的对象 —— 这是 C 节要指出的"文档声称符合但表述与代码相反"。

### C.4 §4.1 `:74` 加密范围声明

设计明确"F3 原型阶段不实现加密，以明文 CVLH2 验证转发语义"。文档 §2 `:50-51` 完整复述，summary `notes` 第 1 条（`:557`）也打印 `This Relay sees PLAINTEXT`，且脚本 `:438` 有断言。**符合，且三处互证。**

### C.5 §5.2 `:100` 回包策略（禁伪协议应答）

设计允许二选一：D4 兼容（每运行 ≤1 个 20B 探测）或**不回包**。原型 `main.rs` **完全没有应答逻辑**（唯一 `send_to` 在转发路径），属"不回包"选项。**符合，且是更保守的一侧。**

### C.6 §5.3 `:112` H2 门槛（不得与游戏共存绑定 62056、不得设 SO_REUSEADDR）

- 62056 护栏：`main.rs:215-220` 在 `:221 UdpSocket::bind(listen)` **之前**判定，命中即 `eprintln!` + `exit(1)`。代码位置正确，无法绕过。
- SO_REUSEADDR：`Cargo.toml` 的 `[dependencies]` 为空（零依赖），`main.rs` 全文无 `setsockopt`、无 `socket2`、无 `SO_REUSEADDR` 字样（`Select-String` 仅命中注释性文本）。**符合。**
- 运行期实测：`bind-check.txt` = `udp:62056 endpoints: 0`，脚本 `:216` 断言运行中也不占用。**符合。**

### C.7 C 节小结

**载荷透明、不重传、无加密、无伪应答、H2 门槛、零依赖 —— 六项核心一致性全部成立。** 两处落差：限速未实现（文档已自认）、头部被改写（文档未声明且用了错误的词汇描述，H-1）。**无"代码违反设计"的硬伤，但有一处"文档描述与代码相反"的事实错误。**

---

## D. 表述边界

### D.1 §5 五条"证明"逐条查证

| 编号 | 原文（节选） | 对应证据 | 判定 |
|---|---|---|---|
| 1 | `:140-141` "五类畸形输入 + 未知 `flags` + 超长输入，都能被拒绝并**继续服务**（≤65,535 字节任意输入不会让 Relay 停止；更大情形走 `fatal` + 退出码 3）" | 五类 reject 各 1 条（日志 `:14-18`）；unknown-flags 1 条（`:19`）；5000B 1 条（`:20`）；`:312` 断言进程未退出 | **前半句成立**。后半句"更大情形走 fatal + 退出码 3"**无任何用例**（见 M-1），且放在"证明"节里语气过强 |
| 2 | `:142-143` "`dst_peer` 路由、发送者 fail-closed 反查、自投递丢弃、目的未知不发送、未注册来源丢弃，五条路径都按设计工作，**各有独立用例**" | 路由 seq=1/4 ✓；自投递 seq=3 ✓；目的未知 seq=999 ✓；**未注册来源：无用例**（`no sender = 0`，日志 `unregistered` 命中 0 次） | **不成立**。"各有独立用例"对第五条是假的 → **H-2** |
| 3 | `:144` "载荷在**两个方向**上都逐字节不变（A→B 的 8B 与 120B、B→A 的 8B；**头部十六进制**与 FNV-1a 64 三方一致）" | 载荷部分：`:345`/`:352`/`:363` 三处 `Compare-Object` + 三处 FNV ✓；"头部十六进制"：日志 `head=` 实为**载荷前 8 字节**，且头部被 `encode()` 改写 | **载荷部分成立，"头部"部分为事实错误 → H-1**；方向独立性未声明（M-4） |
| 4 | `:145` "Relay 全程未占用 62056，并且**二进制本身**拒绝绑定 62056（不只是脚本前置）" | `bind-check.txt` + `:216` 断言 + `main.rs:215-220` + `negative-62056-stderr.txt` 106 B | **成立**（exit code 1 的实测在 `:170` 断言中） |
| 5 | `:146` "分类恒等式与对账两行都闭合：`22 = 10 + 5 + 6 + 1`、`forwarded+no_route+self_drop+forward_fail+no_sender = 5`" | `relay-summary.txt:19-20` 原文 + 本轮独立复算（A.2） | **成立** |

**结论：五条"证明"中，2 条完全成立、1 条部分成立（第 3 条）、1 条包含伪陈述（第 2 条）、1 条前半成立后半无证据（第 1 条）。** 第一轮判定"此项不通过"，第二版有实质改善但仍未达"每条证明都有证据"。

### D.2 第一轮 4 项越界表述是否消除

| 第一轮越界表述 | 第二版处理 | 判定 |
|---|---|---|
| "两个方向都逐字节不变"却只有 A→B 证据 | `:77-78` 补 B→A `seq=5`；`:118` 说明；`:144` 保留该措辞 | **已消除**（证据已补，措辞可成立） |
| "符合 H2 门槛"（实际只有脚本前置） | `:119` 改为"代码级护栏 + 运行期实测未占用"；`:145` 同步 | **已消除** |
| "一个坏包不会让 Relay 停止" | `:120-121` 限定为"≤65,535 的畸形数据报"；`:141` 同步 | **已消除** |
| `no_mapping` 分支暗示已实现（实际不可达） | `:122-123` 改为"本版该分支真实可达**并有用例**" | **形式上改写，实质上以新的不实陈述替代**——分支确实可达（代码路径存在），但"有用例"是假的。见 H-2 |

前 3 项真正消除；第 4 项**换成了另一种越界**，这是本轮最需要记录的"改进失败"。

### D.3 "不证明"清单：第一轮 4 项已补齐，但仍有 6 项新漏

文档 §5 `:150-158` 现有 8 条。第一轮点名的 4 项漏项核对：

| 第一轮要求补的漏项 | 第二版是否列出 |
|---|---|
| 反向路径 | 已不再需要列（已证明）；但"状态隔离"未列 → 见下 |
| >4096B / 越界输入 | `:155-156` 已列 ✓ |
| 三类未测拒绝路径 | 五类全部构造并断言，不再是漏项 ✓ |
| 多 Peer 并发与重排 | `:157` 已列 ✓ |

**仍应补充的 6 项（新出现或此前遗漏）：**

1. **不证明头部保持原样**：`encode()` 会清零 `flags`、用已认证发送者覆盖 `src_peer`；文档却称比对"头部 8 字节"。应明确写"Relay 输出头部不等于输入头部（`src_peer` 被覆盖），只保证载荷字节与 `seq` 不变"。
2. **不证明 `fatal` / 退出码 3 路径**：无用例。
3. **不证明 `no sender` 分支**：采信运行中未触发（当前反而被写成"已证明"，必须先撤销该声称再列入此清单）。
4. **不证明两个方向的状态独立**：同一 Relay 进程、同一 `peers` 表、同一 PowerShell 进程内的两个 `UdpClient`（`seq=5` 还依赖 `:315` 的补注册）。
5. **不证明限速**：设计 §6 列为 Relay 职责，原型无实现（§2 已自认"无限速"，但"不证明"节未列）。
6. **不证明 exe 与被审 `main.rs` 的可复现构建关系**：只有 `civlink-relay.d` 一条依赖记录。
7. （可选）**不证明注册不丢**：脚本只打印 `[info] ... lost N`，无断言；`-142419` 已实证回环会丢注册。
8. （可选）**不证明时间戳时区**：`run time : 06:50:34.314` 是 UTC 当日秒，本地为 14:50，文档未标注（第一轮 G 节建议过"时区标注 +08:00"，未采纳）。

### D.4 是否把"本机回环原型"误写成联机/跨网/游戏侧验证

**没有。** 证据充分且多处一致：

- 文档 `:1` 标题即"（本机回环，非发布）"；`:4`"本文只描述本机回环原型，不构成任何联机验证，也不移动 Gate A/B"；`:52-53`"没有接游戏…所有收发都在本机回环的测试 socket 之间"；`:150-151` 不证明双机/游戏侧；`:207`"模拟证据不得写成'双人真实联机已通过'"。
- `result.txt` 自带两行 evidence label：`simulated data-plane peer on loopback; NOT a real two-machine test, NOT injection into a game process, NOT a multiplayer validation.`
- 证据目录 `negative-62056-stderr.txt` 与 `bind-check.txt` 也支持"未碰 62056"。

**此项（第一轮判"通过"的一项）在第二版依然通过，且边界更清晰。**

---

## E. 缺陷清单与裁定

### E.1 全部发现（0 阻断 / 2 高 / 5 中 / 9 低）

#### 阻断（0 项）

无。证据真实、哈希零偏差、算术闭合、五类拒绝构造正确、载荷透明可验证。主结论"本机回环 Relay 按设计转发、67 项断言通过"**没有被推翻**。

#### 高（2 项）

**H-1｜文档把"载荷前 8 字节"称为"头部 8 字节"，并据此宣称"头部三方一致"**

- 位置：`docs\F3B-RELAY-FORWARD-20261114.md:32`（能力表"三方比对"行）、`:144`（§5 证明第 3 条）
- 证据：
  - `:32` 原文："每条转发行记录载荷 **FNV-1a 64** 与**头部 8 字节十六进制**，与发送方、接收方逐字节比对"
  - `civlink\relay\src\main.rs:450-458` 日志实参：`hex_head(env.payload, 8)`；`hex_head` 定义 `:84-90` 为 `data.iter().take(max)` —— **取的是载荷前 8 字节**
  - 实测印证：`relay-log.txt:10` `forward seq=1 ... head=17320000ffff4fac`，而 `payload1 = [0x17,0x32,0x00,0x00,0xFF,0xFF,0x4F,0xAC]`（脚本 `:254`）→ `head` 正是 `payload1` 的十六进制，与头部无关
  - 进一步：`encode()` `:126-136` 重写头部（`out[5]=0`、`out[10..14]` 被 `src_peer` 覆盖），**若真按"头部"比对，`src_peer` 字段必然不一致**
- 为什么是问题：这是**对"验证了什么"的事实性错误陈述**。读者会以为头部完整性被三方验证过，实际既未记录头部、也无从一致。它与 C.3 的头部改写叠加后，成为"文档与代码相反"的典型。
- 修法：`head=` 是"载荷前 8 字节十六进制"。把 `:32`/`:144` 两处"头部"改为"载荷首 8 字节"，并在 §1 或"不证明"中补一句"Relay 输出头部与输入头部不同（`src_peer` 被替换、`flags` 被清零），只保证载荷字节与 `seq` 原样"。
- 最小实验（若坚持保留"头部"措辞）：在脚本里另取日志被转发帧的**原始接收字节前 8 字节**与**发送方原始头前 8 字节**独立比对。但注意 `src_peer` 在 8 字节内（偏移 10-13）不会冲突，可以比对成功——只是这需要对接收原始缓冲做记录，当前不存在。

**H-2｜文档声称 `no sender` 分支"有用例"，但采信运行中该分支从未触发**

- 位置：`docs\F3B-RELAY-FORWARD-20261114.md:122-123`（§4.3 第 4 条）、`:142-143`（§5 证明第 2 条）
- 证据：
  - 文档 `:122-123` 原文："`no sender` 的第一版表述暗示'未命中映射不转发'分支已实现；实际第一版该分支不可达 → 本版该分支真实可达并**有用例**（`seq=999` → `no route`，未注册 socket → `no sender`）"
  - `relay-summary.txt` 第 16 行：`no sender : 0 (unregistered source, dropped - src_peer not trusted)`
  - `relay-log.txt` 全文 23 行，`Select-String -Pattern 'unregistered'` **命中 0 次**
  - 脚本：全文只有 `$peerA`（`:220`）与 `$peerB`（`:222`）两个 `UdpClient`，两者都注册过；**不存在"未注册 socket"夹具**。唯一涉及 `no sender` 的断言是 `:434` `Check 'no sender = 0'`，即**断言它没有发生**
- 为什么是问题：把一个"未发生的分支"写成"有独立用例"，属于**证据不支持的断言**，且它出现在"§5 证明"节，直接抬高读者对覆盖面的判断。第一轮点名的正是这类问题（`no_mapping` 分支越界），第二版把它从"暗示"升级成"明确声明"，是**退化**而非改进。
- 修法（二选一）：
  - (a) 删掉"并有用例"，改为"本版该分支可达（`main.rs:392-409`），但**本轮未构造用例**（`no sender = 0`）；`seq=999` 只证明 `no route` 路径"；
  - (b) 补用例：在脚本中新建第三个 `UdpClient`（不注册），发一帧 `dst_peer=202`，然后断言 `no sender = 1`、`forwarded` 仍为 3、日志出现 `unregistered source`。**推荐 (b)，成本约 10 行**，同时能把 67 项变成 68～69 项。

#### 中（5 项）

**M-1｜`fatal` / 退出码 3 路径零用例，却在三处（含"证明"节）以已实现的口吻描述**

- 位置：`docs\...:34`（§1 能力表）、`:121`（§4.3）、`:141`（§5 证明第 1 条，后半句）
- 代码：`main.rs:315-321` `stats.fatal = Some(...)` + break；`:568-577` 先写 summary；`:580-582` `if stats.fatal.is_some() { std::process::exit(3) }` —— **实现是完整的**
- 证据缺口：脚本 67 条 Check 中，只有 `:379` `Check 'relay exited 0 on stop-file' ($exitCode -eq 0)` 与 `:436` `Check 'fatal = none'`；`Select-String 'exitcode|fatal|-eq 3'` 全文仅命中 `:165/:355/:371/:375/:379/:436/:454`，**没有任何一处构造 fatal、也没有任何一处断言退出码 3**
- 为什么是问题：`exit 3` 是 H-1 修法的核心承诺（"不再以 0 退出掩盖"），而它恰好是**唯一完全没有被自检覆盖的承诺**。`fatal = none` 只证明"这次没触发"，不证明"触发时会 exit 3"。
- 修法：加一个最小用例——用一个已 `close()` 的接收路径或注入一个可控的 OS 错误（最省事：给二进制加一个 `--inject-fatal` 调试开关，仅测试用），断言 `exitcode=3` 且 `relay-summary.txt` 已落盘且含 `fatal: <非 none>`。若不愿改二进制，则必须把 `:34`/`:121`/`:141` 三处语气降为"设计如此，本轮未验证"。

**M-2｜注册计数无绝对断言 + 判词分母自指**

- 位置：`civlink\run-f3b-relay-selftest.ps1:424`、`:425`、`:427`、`:506`
- 证据：
  - `:424` `Check 'registers counted <= sent' ($rCount -le $script:RegistrationsSent)` —— 只有上界
  - `:425` `Check 'datagrams = registers + 5 + 6 + 1' ($dCount -eq ($rCount + ...))` —— 基准是运行时 `$rCount`
  - `:427` `Check 'control frames = registers + 1' (... -eq ($rCount + 1))` —— 同上
  - 无任何 `$rCount -eq 10`；`script:RegistrationsSent` 在 `result.txt` 里被打印为 10，但只用于 `-le` 的上界与一句 `[info]`
  - `:506` PASS 分支：`"F3B-RELAY-SELFTEST: PASS ($script:Checks/$script:Checks)"` —— **分母不是常量 67**
- 为什么是问题：(a) 注册丢包时若恰好不破坏被断言的方向，67 项仍可全绿；(b) 分母自指意味着将来任何守卫跳过（`:412 if ($summaryOk)`、`:451 if ($logOk)`、`:340/:348/:358/:463/:473` 的 `-ge` 守卫）都会打印 `PASS (N/N)` 并 exit 0，**断言总数缩水永远发现不了**。本次 `67/67` 说明实际执行了 67 条，但机制不可维护。
- 修法：加 `Check 'registers = 10' ($rCount -eq 10)`；把判词改为 `PASS ($script:Checks/67)`（或断言 `$script:Checks -eq 67`），并在守卫跳过路径上显式记一条 FAIL。

**M-3｜§4.4 对 `-144934` 四项失败的归类与 `result.txt` 不符**

- 位置：`docs\...:133`
- 证据：文档称"计数正则行尾锚点 3 项、5,000 字节全零包被误判 1 项"；`-144934\result.txt` 实际四项为 `unknown flags = 1`、`no sender = 0`、`oversize = 0 (...)`、`log records bad-magic rejection`
- 为什么是问题：前 3 项确属"正则未锚定"同族，但第 4 项的根因是**用例构造错误**（5000B 全零包不带 `CVLR`，被 `parse()` 判 `bad-magic` 而非 `payload-too-large`，见该目录 `relay-log` 第 20 行 `reject len=5000 kind=bad-magic`），导致 bad-magic 计数=2 而断言期望 1。把两类根因合并成一句"3 项正则 + 1 项 5000B 误判"，无法让读者还原真实失败原因，也掩盖了"第一版 5000B 用例构造错误"这个有价值的教训（该教训其实已写在 §4.2 第 5 条，但 §4.4 又给了不同的解释，两处互相矛盾）。
- 修法：§4.4 改为"3 项计数正则未锚定的连带失败（`unknown flags`/`no sender`/`oversize`）+ 1 项 5000B 全零数据报被 `bad-magic` 提前拦截导致 `bad-magic` 计数=2"。并补一句"两次运行的 relay sha256 相同、summary 计数逐字相同，仅脚本断言口径变化"。

**M-4｜"两个方向"未声明状态隔离缺失**

- 位置：`docs\...:144`；对应"不证明"清单缺失
- 证据：`peerA`/`peerB` 是同一 PowerShell 进程内的两个 `UdpClient`（脚本 `:220`、`:222`）；同一 Relay 进程、同一 `peers` 表、同一单线程循环；`seq=5` 前还有 `:315` 的补注册依赖
- 为什么是问题：不构成虚假陈述（`:144` 字面属实），但缺一句限定，读者会自然会把它读成"双向通道独立可用"。而设计 §6 的响应路径对称（`:80`）恰恰是需要"独立状态"才能支撑的更强主张。
- 修法：`:144` 句末加"（同一 Relay 进程、同一注册表；不是双进程/双机）"，并将第 4 项列入"不证明"。

**M-5｜三条断言是"匹配程序自己打印的字符串"**

- 位置：`civlink\run-f3b-relay-selftest.ps1:426`、`:437`、`:438`
- 证据：`:426` `($summaryText -match '(?m)^datagram identity\s*:\s*datagrams ==')`；`:437` `($summaryText -match '(?m)^reconciliation\s*:.*\s==\s')`；`:438` `($summaryText -match 'sees PLAINTEXT')`
- 为什么是问题：这三条不独立复算任何数，只检查"被测程序打印了 `==`"。其中 `:426`/`:437` 间接约束了等式（不等时程序打印 `!=`），但脚本自己已经在 `:413-418` 取出了全部数字，完全可以自己算。`:438` 更是纯字符串匹配。
- 修法：`:426` 改为用 `$dCount -eq $rCount + $fReq + $bEnv + $uFlags` 直接复算；`:437` 改为 `($fwd + $nr + $sd + $ff + $ns) -eq $fReq`；`:438` 保留（它确实在验证 summary 文案包含免责声明，可接受）。

#### 低（9 项）

**L-1｜`parse()` 无"尾部多余字节"校验**（第一轮 L-5 未修）
`main.rs:114` 只查 `buf.len() < HDR + payload_len`，**不查 `>`**。声明 8 B、实发 200 B 时，末尾 172 字节被静默丢弃，且不计入任何统计、不产生拒绝日志。修法：加 `if buf.len() > HDR + payload_len { return Err("trailing-bytes"); }`，并把该分支纳入五类→六类拒绝。

**L-2｜`--listen-seconds` 静默容错**（第一轮 L-6 未修）
`main.rs:187` `listen_seconds = it.next().unwrap_or_default().parse().unwrap_or(60);` —— 非法值静默变 60，而相邻的 `--listen`（`:178-184`）遇到非法值直接 `exit(1)`。同一份参数解析里两种容错风格，属一致性瑕疵。修法：与 `--listen` 同构，非法即 `eprintln!` + `exit(1)`。

**L-3｜时间戳是 UTC 当日秒，无时区标注**（第一轮 G 节建议"标注 +08:00"，未采纳）
`main.rs:43-57` `wallclock_stamp()` 计算 `secs = (total_ms / 1000) % 86_400`，输出 `06:50:34.314`；本地实际是 14:50。文档从未说明这一点，读者极易当成当地时间。修法：改用 `%H:%M:%S` 的 UTC 并在格式串后加 `Z`，或在文档 §3 标注"时间戳为 UTC 当日秒"。

**L-4｜两个探测目录未入档**
`M0A\captures\_probe-f3b`（14:26:47）与 `_probe-f3b2`（14:27:04），各 3 个文件（`relay-log.txt` 224 B、`relay-summary.txt` 1,011 B、`stop.txt` 6 B），summary 为旧 schema。文档 §4.4 列了 8 个目录，未提这两个。修法：在 §4.4 加一行"另有两次早期探测运行（旧 schema，未采信）"，或删除目录。

**L-5｜§4.2 第 3 条与当前源码不自洽**
文档 `:108-109`："测试前必须确认父目录存在。Relay 用 `<out-dir>/relay-log.txt` 拼路径；out-dir 不存在时直接报 `拒绝访问 (os error 5)` 退出。" 而 `main.rs:235` 有 `fs::create_dir_all(dir)`（失败才 `exit(1)`），**out-dir 不存在会被自动创建**。该条描述的是**第一版行为**，改写后依然与当前源码不符。修法：改为"out-dir 不存在时自动创建；创建或写日志失败时 exit 1（os error 5 是其中一种）"。

**L-6｜§6 `:189` 对 5 字节文件的描述不精确**
"两者都是 5 字节（内容为 CRLF 空行）" —— 实测两文件字节均为 `EF BB BF 0D 0A`，即 **UTF-8 BOM + CRLF**（BOM 使长度变为 5 而非 2）。这是 PowerShell 5.1 `-Encoding UTF8` 必然写 BOM 所致。修法：改为"内容为 UTF-8 BOM + CRLF"。不构成实质性错误（哈希相同这一结论仍成立）。

**L-7｜§7 的 F3-C 引用在写作时刻是悬空的，且其证据不可核验**
文档 `:199-200` 引用 `docs\F3C-BACKOFF-20261114.md`；该文件 mtime 为 **14:58:48**，晚于本文 14:51:30 → **写作时确实不存在**，现存在（9,089 B，`2407FFBC7F3EDD36B2CD8562BD8AA35AAB421C131A0797D557FE4E24E4C4439B`）。更严重的是：F3-C 文档声称的两个证据目录（`F3C-backoff-selftest-20261114-143128` / `-145343`）及 `PASS (23/23)` 的 `result.txt` 在 `M0A\captures` 下**完全不存在**（该目录只有 `_probe-f3b`、`_probe-f3b2`、`E2B-synthetic-selftest2` 与 8 个 `F3B-relay-selftest-*`；全仓递归 `*f3c*` 只找到 `civlink\run-f3c-backoff-selftest.ps1` 与文档本身）。修法：§7 删掉对 F3-C 的"已单独完成"背书，或待 F3-C 补证据后再引用。**这条不在 F3-B 的责任范围内，但它污染了 F3-B 文档的引用链，必须记一笔。**

**L-8｜§3 无法导出 `registers = 10`**
§3 步骤 3 只说"A、B 各注册（每注册发 3 次）"，即 6 次；实际脚本还有 A 在发帧前补 2 次（`:261`）与 B 在反向帧前补 2 次（`:315`），合计 10。§3 未提这两次补发，读者无法从 §3 复算出 `registers = 10`，而这正是被断言的常量之一。修法：§3 步骤 3 补一句"发帧前 A、B 各补发 2 次，共 10 次"。

**L-9｜`send_to` 短写分支实际不可达**
`main.rs:443-474` 的 `Ok(sent) if sent == n` / `_ => forward_fail` 两分支，在 UDP + 单播 + `n ≤ 1300 B` 的场景下 `_` 分支不可能命中（UDP 不会短写）。`forward fail: 0` 因此是恒真性质的观测。属"无害但会计数失真"的瑕疵，建议在 §1 注明或保留（影响极小）。

### E.2 第一轮 12 项必改：逐项打勾

| # | 第一轮条目 | 状态 | 依据 / 差在哪 |
|---:|---|---|---|
| 1 | H-1：超长数据报停服 ⇒ 缓冲 65,535 + 分类错误处理 + fatal/exit 3 | **已落实（代码）** | `main.rs:41` `RECV_BUF=65535`；`:296-314` oversize 分支；`:315-321` fatal；`:580-582` exit 3。但配套断言只覆盖"仍在服务"（`:312`）与"fatal = none"（`:436`），**未覆盖 exit 3 本身** → 另立 M-1 |
| 2 | 表述：删"一个坏包不会让 Relay 停止" | **已落实** | `:120-121` 限定为"≤65,535 字节"；`:141` 同步 |
| 3 | 表述："两个方向"补 B→A 证据 | **已落实** | 脚本 `:315-317`；`:360-363`；日志 `:23`；`:118` 说明。局限见 M-4 |
| 4 | M-1：`src_peer` 回退改 fail-closed | **已落实** | `main.rs:392-409` 反查来源地址，未命中即 `no_sender` 丢弃，无 `unwrap_or(env.src_peer)`。**但该分支无用例 → H-2** |
| 5 | M-2：62056 代码级护栏 | **已落实** | `main.rs:215-220`，在 `:221 bind` 之前，exit 1。第一轮建议 exit 2，代码用 1，文档 `:31` 按 1 写 → **自洽，可接受** |
| 6 | M-3："符合 H2 门槛"改写 | **已落实** | `:119`、`:145` 改为"代码级护栏 + 运行期实测未占用" |
| 7 | M-4：断言恒真 / 自洽恒等式 / `>=5` | **部分** | 恒真 0 条 ✓、恒等式 0 条 ✓、7 个精确期望常量 ✓；但 `:424` 仍 `-le`、`:425`/`:427` 仍以变量 `$rCount` 为基准、判词分母自指（`:506`）→ **M-2** |
| 8 | A/L-1：Cargo.toml 479 B + 哈希 | **已落实** | §6 `:167` 479 B 与实测一致 |
| 9 | A/L-2：补 stop.txt、拆 console/stderr | **已落实** | §6 `:184-187` 四行齐备；`:189-190` 有说明（措辞见 L-6） |
| 10 | A：三个未点名目录入档 | **已落实** | §4.4 `:129-134` 已列 142256/142419/142718/142803/142813/142818 六行（含 41→43 的说明）。但仍有 `_probe-f3b*` 未列 → L-4 |
| 11 | L-3：out-dir 叙事改写 | **未落实** | `:108-109` 改写后仍称"out-dir 不存在时直接报 os error 5 退出"，与 `main.rs:235` 的 `fs::create_dir_all` 矛盾 → **L-5** |
| 12 | L-4：§3.2 标注 | **已落实** | §7 `:194` 已注明属 Agent 侧 / F3-A |

**计分：10 项已落实、1 项部分（#7）、1 项未落实（#11）。**

### E.3 裁定：**有条件通过**

理由：
- **支持通过的部分**：15 项哈希零偏差；算术逐条咬合；五类拒绝各走独立 parser 分支（第一轮的严重缺陷已真正修复）；载荷透明、不重传、无加密、无伪应答、62056 双保险、零依赖——六项设计一致性全部成立；"本机回环而非联机"的边界表述扎实且有多处互证；12 项必改落实 10 项、部分 1 项。
- **不支持"通过"的部分**：§5 五条"证明"里有 2 条站不住（H-1 头部误标、H-2 no_sender 伪用例），而 §5 正是全文档的结论核心；`exit 3` 这个 H-1 修法的招牌承诺完全无用例（M-1）；判词分母自指使断言总数缩水无法被发现（M-2）。
- **不定"不通过"的理由**：以上问题**全部属于"验证声明超前于证据"，而非"证据造假"或"产品行为错误"**。哈希、日志、summary、脚本构造全部经得起复算，产品侧代码未发现新的可触发缺陷（唯一的 `parse()` 尾部无校验是第一轮遗留的 L-5，且不导致停服）。修法都是文案修正 + 两三个小用例，不需要重构。

**进入 F3-D 的前提（按优先级）：**

1. **必修 H-1**：把 `:32`/`:144` 的"头部"改为"载荷首 8 字节"，并在 §1 补一句"Relay 会重写输出头部（`src_peer` 覆盖、`flags` 清零），只保证载荷与 `seq` 原样"。
2. **必修 H-2**：二选一 —— 删掉"并有用例"并列入"不证明"；或补第三个未注册 `UdpClient` 的用例（推荐，约 10 行，67 → 68/69 项）。
3. **必修 M-2**：加 `Check 'registers = 10'`；判词分母改为常量；守卫跳过时记 FAIL。
4. **必修 M-1（或降级文案）**：补 exit 3 用例；若暂不做，`:34`/`:121`/`:141` 三处必须改为"设计如此，本轮未验证"。
5. **建议修 M-3 / M-4 / M-5 / L-5 / L-7**（都是低成本文案与断言修正）。
6. **跨文档**：F3-C 的证据目录必须先补齐，否则 §7 对"F3-C 已单独完成"的背书应删除。

在上述 1–4 完成后，F3-B 可作为 F3-D（忙轮询压力）的转发基线被引用；在此之前，**F3-D 不得以"F3-B 已验证头部不变/已验证 no_sender/fatal 路径"为前提做设计**。

### E.4 断言数精确计数

- 脚本 `Check` 调用：**67**（`^\s*Check '` 与 `Check '` 两种模式均为 67，无注释伪命中）。
- `result.txt` 打印：`PASS (67/67)`。
- 文档声称：`67`（`:3`、`:83`）。
- **三者一致，无虚报。** 但判词的分母是 `$script:Checks`（`:506`），将来若守卫跳过断言，`N/N` 仍会打印 —— 建议一并改为常量 67。

---

## 附录 A：本轮核对到的文件哈希（审计基准）

| 文件 | 字节 | SHA-256 |
|---|---:|---|
| `docs\F3B-RELAY-FORWARD-20261114.md` | 15,389 | `52FEE699320241519DAF3DCD566EF2C13EFA315DFD30F01DB0EEA2C4EF99A7B1` |
| `docs\F3B-REVIEW.md`（第一轮） | 52,332 | `8E102B9AC082E762EAAF698C9BB6BDBC5A96EE45A69C302BC24BC798A2E11D57` |
| `docs\F3-DIRECT-RELAY-DESIGN-20261114.md` | 11,532 | `998F9A1E5F76CAF097E71883F208E55F5FFD6EAAB1F7B883401D68B3F7430469` |
| `docs\F3A-REVIEW.md` | 45,746 | `68F590B76148E3E8BAF7ECDEBCF2F862E7DE354E0E12DB235F141365AC65409A` |
| `docs\F3A-REVIEW-2.md` | 51,646 | `89E22A862836430AD38EF72263CD86AE4AF534E8B05D18F465FA129269E5BB94` |
| `docs\F3C-BACKOFF-20261114.md` | 9,089 | `2407FFBC7F3EDD36B2CD8562BD8AA35AAB421C131A0797D557FE4E24E4C4439B` |
| `docs\F3A-DIRECT-FORWARD-20261114.md` | 14,107 | `A409F357C9B98C3EAE2D042D50E997242A9E32EC0C0321B1E2EB322ACB161EE5` |

`docs` 目录 mtime 序（用于判断引用悬空）：F3-DESIGN 14:07:00 → F3A-REVIEW 14:33:14 → F3B-REVIEW 14:40:49 → **F3B-RELAY-FORWARD 14:51:30** → F3C-BACKOFF 14:58:48 → F3A-REVIEW-2 15:02:34 → F3A-DIRECT-FORWARD 15:09:47 → F3D-PRESSURE 15:14:06。

> 注：本文 §7 `:199-200` 写"F3-D（忙轮询压力）… 仍未开始"，而 `docs\F3D-PRESSURE-20261114.md` 于 15:14:06 落盘（晚于本文 22 分钟）。写作时刻该句为真，审计时刻已过时——记录在案，不计入缺陷。

## 附录 B：A 节哈希清单的可复算命令

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath <path>
[IO.File]::ReadAllLines(<path>)          # UTF-8 中文文档必须用这个，不要用默认 Get-Content
Select-String -LiteralPath <script> -Pattern "^\s*Check '"
```

---

**报告结束。** 本报告为只读审计产物，未修改任何被审文件。
