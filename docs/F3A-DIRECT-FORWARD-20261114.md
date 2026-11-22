# F3-A 直连转发原型（本机回环）完成记录

> 状态：**机械自检通过（F3A-FORWARD-SELFTEST: PASS，31 个 Check 站点 / 35 次运行期执行，全部通过）**，2026-11-14，整改后第四轮运行（`-155041`）。
> 依据：`docs/F3-DIRECT-RELAY-DESIGN-20261114.md` v0.3 定稿 §3.2/§3.4/§5.2（F3-A），裁定审计 a6a23515 D/E 节限定范围。
> 证据标签：**"模拟数据面对端"（本机回环 127.0.0.1）**。不是真实双机、不是游戏进程内注入、不是联机验证。
>
> **文档版本**：v4。v1（`142008`、17 项断言）、v2、v3（`150906`、34 项）的结论**不再有效**：断言口径与证据目录均已更换，数字不能跨版本比较（见 §7）。本版对应复审 `docs/F3A-REVIEW-3.md`（第三轮，不通过）整改后的产物；第四轮复审 `docs/F3A-REVIEW-4.md`（f2195d8a）**有条件通过**（0/0/0/6 低），其 6 项低缺陷（E-1..E-6：断言名 50399→50999、§7 哈希口径、§6 37 归因、§2 分组、§3 不证明清单补 L1/L7、M7 表述）已全部修正，脚本终值 22,801B/`7AB1A9E7…`；**第五轮复审 `docs/F3A-REVIEW-5.md`（3c311e41）裁定通过**（0/0/0/0，E-1..E-6 逐项核实落地，15/15 哈希独立重算一致），F3-A 登记**通过**。

## 1. 本步做了什么

在 `civlink-agent` 上实现 F3-A 直连转发原型，只做**纯转发**：

| 能力 | 实现 | 边界 |
|------|------|------|
| 出向转发 | `--forward-to IP:PORT`：把 dst 端口 == 62056 的已接收帧载荷**原样**转发到**唯一目标**（对端 Agent 的转发接收端口） | 不转发到游戏 socket、不转发到 :62056、不重传、不改写载荷 |
| 发现帧判定 | **AND 语义**（设计 §3.2 规则 3 / §4.5）：dst 端口 ∈ 62900..62999 **且** 载荷恰为 4 字节 `8D E8 FC 70`。只有这样的帧交给 F1 模拟房主通道，不进入 F3-A 路径，并计入 `skip discovery` | 发现面与数据面路由分离；**单看 flag 或单看端口都不算发现帧**（见 §5 的 M1） |
| 非 62056 帧 | 计入 `skip not datapath`，**不转发** | 对应设计 §3.2 第 2 步"未命中则不转发并计数" |
| Hook 拒载帧 | `REJECTED_OVERSIZE | NO_PAYLOAD` 帧（Hook 没能携带载荷）计入 `skip rejected`，**不转发** | 第三轮 L5：此前这类帧完全不进转发阶段计数，闭合恒等式只对"被看见的帧"成立 |
| 映射键 | `(session_id, logical_socket_id, socket_generation, dst_ip_be, dst_port_be)`，首次流量分配（§4.3 生命周期规则） | 原型用容量 64 的线性表；`civlink-fakeip` crate 仍是 M0-B 的参考实现。**容量上限是原型自造的限制，不是设计规则**，见 §3 的 `skip key table` 说明 |
| 对端侧 | `--forward-listen PORT`：非阻塞接收并**逐条带时间戳 + SHA-256 记录**实际到达的载荷，同时记录首个发送者地址 | 只绑 127.0.0.1；**两处独立护栏**拒绝 `PORT == 62056`（`parse_args` 与 `ForwardListener::new` 各自 fail-closed） |
| 计数闭合 | `frames seen = forwarded + skip not datapath + skip discovery + skip key table + skip rejected + forward fail` | 恒等式被驱动脚本逐次断言，不是文档声称（第三轮 L5 后恒等式含 rejected 项） |
| 载荷身份 | 发送侧与接收侧各自算 SHA-256（零依赖手写实现），驱动脚本用 .NET 自算第三份做三方比对 | 覆盖 120B 载荷**全部字节**，不是只比前缀 |
| 二进制护栏 | `--port` / `--forward-listen` / `--forward-to` 三条路径都拒绝 62056 | 三条负向用例在脚本里逐条实跑，断言 exit=1 且 stderr 点名各自端口文案（第三轮 L8：三条用例分别匹配自己的拒绝文本，不再共用 `-match '62056'`） |

**没有实现**（按裁定审计 D 节必须留 M0-B）：游戏进程内注入方式（Design I/II/III 选择、绑定矩阵、R1）、H1/H2/H8、Fake-IP 产品选段、wire format 与身份密钥协议冻结、加密（L1/L2 Noise E2EE）。

## 2. 自检设计

驱动脚本 `civlink\run-f3a-forward-selftest.ps1`（不进游戏、不需管理员）：

1. 前置：`34718`、`21346` 端口空闲；`civlink-agent.exe` 存在。输出目录先建，随后 `Start-Transcript` 落 `selftest-console.txt`（第三轮 R3-L2：脚本终于有了可审计的完整控制台记录；`.bak-154748` 已留底）。
2. **三条负向用例先行**（任何一条不 fail-closed 就整体判失败）：`--port 62056`（期望 stderr `--port must not be 62056`）、`--forward-listen 62056`（期望 `--forward-listen must not be 62056`）、`--forward-to 127.0.0.1:62056`（期望 `--forward-to must not target port 62056`），各断言 exit=1。**退出码在 `Kill()` 之前读取**（第三轮 L8：Kill 之后 ExitCode 不可靠）。结果写 `negative-cases.txt`。
3. 启动 Agent：`--forward-to 127.0.0.1:21346 --forward-listen 21346 --simulate-datapath --bind-ip 127.0.0.1 --loopback-selftest --stop-file ... --quiet`。
4. **运行中**用 `Get-NetUDPEndpoint -LocalPort 62056` 检查 Agent 未占用数据面端口，结果落 `bind-check.txt`。
5. 发 7 个 CVLH2 帧（编码同 F2 驱动）：

   | seq | dst 端口 | 载荷 | flags | 期望分类 | 用意 |
   |-----|---------|------|-------|---------|------|
   | 1 | 62056 | 8B `17 32 00 00 FF FF 4F AC` | 0x21 | forwarded | S5 实测形态 |
   | 2 | 62056 | 8B `17 32 00 00 FF FF 35 BA` | 0x21 | forwarded | S5 实测形态（第二帧，载荷不同） |
   | 3 | 62905 | 4B `8D E8 FC 70` | 0x06 | skip discovery | 唯一真发现帧 |
   | 4 | 50999 | 4B `DE AD BE EF` | 0x20 | skip not datapath | 非数据面 |
   | 5 | 62056 | 120B 递增 | 0x21 | forwarded | 任意长度原样转发 |
   | 6 | **62056** | 4B `8D E8 FC 70` | **0x04** | **forwarded** | **真数据面帧带发现 flag**：OR 语义下会被静默吞掉（见 §5 M1） |
   | 7 | **62905** | 4B `DE AD BE EF` | **0x04** | **skip not datapath** | **发现端口但载荷不是 magic**：OR 语义下会被误判为发现帧 |

6. 写 stop 文件 → 等干净退出（不 `Kill`，否则丢 summary；**stop 后 break 前先最终 drain 一轮**——第三轮 L3，避免 stop 时刻末批载荷丢失）→ 解析 `summary.txt`、`forward-log.txt` 断言。

**断言 31 个 Check 站点 / 35 次运行期执行**（3 条负向用例 ×2 站点 = 6 次 + 29 个单次站点 = 35），分组：负向 6；运行期 2（不绑 62056、退出码 0）；summary 计数 12（逐帧分类 7、闭合恒等式 1、对端接收量 3、边界声明 1，含 `skip rejected`）；对端身份 3（对端监听端口、forward 目标、首个发送者端口匹配）；**跨文件身份 1**（第三轮 M7：peer-recv `from=` 与 summary `forward sock` 比端口 + 比 IP + from 端口 ≠ 62056）；**发现帧全文件缺席 1**（第三轮 M6：seq=3 不出现在 forward-log 任何一行）；日志结构 4；载荷身份 6（三方 sha256 集合相等 + **按 seq 配对** + 8B 载荷头）。

## 3. 结果

`F3A-FORWARD-SELFTEST: PASS`，**31 站点 / 35 次执行全部通过**，退出码 0。

- 证据目录：`M0A\captures\F3A-forward-selftest-20261114-155041`（本记录采信）
- `summary.txt` 关键段：`frames seen 7` / `forwarded 4` / `forward bytes 140` / `forward fail 0` / `skip not datapath 2` / `skip discovery 1` / `skip key table 0` / **`skip rejected 0`** / `mappings created 1` / 对端 `payloads recv 4` / `payload bytes 140` / `listen port 21346` / `forward sock 0.0.0.0:57599` / `first sender 127.0.0.1:57599`。
- **`frames seen` 标签已改为诚实表述**（第三轮 R3-H4）：`7 (accepted frames that reached the forward stage, discovery included; the discovery ones are then counted under skip discovery)`——值含 1 个发现帧，标签不再自称 non-discovery。F2 段的 `frames seen 6` 才是 outbound non-discovery。
- `forward-log.txt`：4 条 `forward seq=1/2/5/6`（len 8/8/120/4，各带 sha256）、4 条 `peer-recv`（同 sha256，`from=127.0.0.1:57599`）、2 条 `forward skip`（seq 4 与 seq 7）。seq=3 全文件缺席。
- `bind-check.txt`：`agent pid=<pid> udp:62056 owned by agent: 0`。
- 算术闭合：`4 + 2 + 1 + 0 + 0 + 0 = 7`。
- `selftest-console.txt`（3193B）：完整运行转录，35 行 `[PASS]`，0 行 `[FAIL]`。

**`skip key table` 这一行必须按原文理解**：本原型把映射表容量固定为 64 键，超出后的新键不转发。设计 v0.3 §3.2 **没有容量上限**（`civlink-fakeip` crate 的池是参考实现），所以这个计数器是为了让"未命中即不转发"这条分支**可达、可测**，不描述任何产品行为。该分支由单测 `forward_key_table_full_refuses_to_forward` 覆盖（第三轮 M5：脚本里对应的恒真断言已删除，计数保留在闭合恒等式里）。

**这一组数字证明的**：62056 数据面载荷经 CVLH2 进入 Agent 后，按唯一目标原样转发（120B 全字节 sha256 三方相等、按 seq 配对无误），对端确实收到同样的载荷且发送者可追溯到 Agent 的转发 socket（跨文件对照：peer-recv `from=127.0.0.1:57599` == summary `forward sock 0.0.0.0:57599` 的端口；IP 项按 M7 实现为 `fromIp ∈ {127.0.0.1, fwSockIp}`，回环下 127.0.0.1 恒过，**绑定项是端口**，回环下 0.0.0.0 以 127.0.0.1 呈现），发现帧按 AND 语义被正确识别且不进入转发路径，非数据面帧被计数不转发，Hook 拒载帧被计数不转发，一帧一投不重传，Agent 未占数据面端口，三条参数路径都在 bind 前 fail-closed。

**不证明**：真实 Peer 可达性、真实双机加入/对局、游戏进程内注入与绑定共存（H2/R1）、跨网/Relay RTT、加密与密钥协商、长稳与高负载（F3-D/F3-E 另行）、**未命中映射路径的产品语义**（原型表满分支是自造限制）、多 Peer 并发与重排、**转发 socket 的源 IP 语义**（L2：绑 `0.0.0.0:0`，对端实际看到的源地址由操作系统选路决定，本测试仅回环）、**listener 收包缓冲 2048B 可截断**（L1：回环载荷 ≤1280B 不触发，真实超限载荷可能截断，F3-E 前不修）、**`SO_REUSEADDR` 仅源码静态审查佐证**（L7：bind-check 只按 OwningProcess 观测运行期绑定，不证明代码路径里没有该调用）。

## 4. 文件身份

| 文件 | 字节 | SHA-256 |
|------|------|---------|
| `civlink\agent\src\main.rs` | 95,778 | `6415954CBC888DA00EA40B0B46FB7E2D347B51C76E8F84C641E80C40F26E93ED` |
| `civlink\agent\Cargo.toml` | 525 | `0CC694BBE083E20FCE2AF416C3F32AF84705130485239A5AA18E966081F22017` |
| `civlink\civlink-agent.exe` | 382,464 | `2E9BFCB53A3A253CAFECAF046C6B986EDD3126819D01A6DE859762739C2514F6` |
| `civlink\run-f3a-forward-selftest.ps1` | 22,801 | `7AB1A9E705F5FED65CCAB6E5E420102023AE42B827170613583168A9636DCCFC` |
| 证据 `summary.txt` | 3,946 | `1C3664F2CC594E17F237D122229B090B04C83D3992F5B04BE9E25688C94260AC` |
| 证据 `forward-log.txt` | 1,548 | `6CD8857B1396C969192B7FA31FF4269E8647EAB7F3229428EB40513C69A09507` |
| 证据 `frame-log.txt` | 1,040 | `A6310C20AA81D6E1814AD860C226A18925F3436B31A832E337E08454415F2738` |
| 证据 `datapath-log.txt` | 769 | `BFD736279E4955FD0CF1ACE55F1E710BF1F27C12A71BF0DBDD02EF7DD6B10EFF` |
| 证据 `bind-check.txt` | 48 | `01BA8326F3E8C87CCAAA6D513DE8BF11A01C1C7E7A495F00B87D5DE640ADA6D2` |
| 证据 `negative-cases.txt` | 387 | `3FB5A8B2D1126227D56B8940E34CFC6ECF5EDCEA933B98157A4A9123F93621E8` |
| 证据 `selftest-console.txt` | 3,193 | `CC4C07CA4B6AFA571DDE2138CAEB6CBF22F3E4D8A4C34DD63FD7F89E187B5417` |
| 证据 `exit.txt` | 17 | `81DDBAF9EED6926436F584FADECA0FBBE6DF4B4E6A47F318AF3A728A6574385A` |
| 证据 `agent-console.txt` | 5 | `F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295` |
| 证据 `agent-stderr.txt` | 5 | `F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295` |
| 证据 `stop` | 0 | `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855` |

`agent-console.txt` 与 `agent-stderr.txt` 同哈希：两文件都是 5 字节（`EF BB BF 0D 0A` = UTF-8 BOM + CRLF，`--quiet` 模式的无输出被 PowerShell 落盘成 BOM+换行），**不是空内容**——空内容的 SHA-256 是 `E3B0C442…`（本表 `stop` 才是真 0 字节）。同哈希属预期（第三轮 M-2 已核实）。

**exe 与源码的对应关系**（第三轮 R3-H2 已降级表述）：交付副本 `civlink\civlink-agent.exe` 是 `agent\target\release\civlink-agent.exe`（该构建目录）产物的**逐字节拷贝**——本轮从哈希 `6415954C…` 源码用 pinned `cargo +1.75.0 build --release --offline` 构建后复制，两者 SHA-256 一致。**不声明构建可复现**：第三轮审计实测三次独立 clean build 哈希互不相同（`.pdb` 绝对路径嵌入 exe 所致），"同哈希 = 可复现"的因果不成立。

**脚本哈希与证据时序（第四轮 E-1）**：证据 `-155041` 由脚本修订版（22,385B/`1D8DA92D…`）运行生成，其转录第 46 行断言名为 `50399-like`；第四轮审计后该断言名更正为 `50999-like`（22,801B/`7AB1A9E7…`，本表所引）。此为**纯文案级修改**（断言逻辑、站点数 31/35、判定结果均不变），按审计 E-1 约定"断言名改 50999，随下次 run 转录同步"——下次 F3-A 相关运行起转录即显示新文案，本证据有效性不受影响。

## 5. 本轮修掉的缺陷（复审 `F3A-REVIEW-3.md` 对应项）

### 5.1 产品侧（第三轮新增）

1. **R3-H4 `frames seen` 标签语义错误**：summary 的 F3-A `frames seen` 值含 1 个发现帧却标称 `non-discovery`。已改为"accepted frames that reached the forward stage, discovery included; the discovery ones are then counted under `skip discovery`"（`main.rs` summary 打印处），并重跑留证。
2. **L3 stop 后不再丢末批**：`stop_seen` 的 `break` 之前先最终 drain 一轮对端 listener，否则 stop 时刻已落在缓冲里的载荷永久丢失且不计入 peer 统计（`main.rs` 主循环）。
3. **L4 `forward FAILED` 补目标**：失败行现在带 `-> <target> (send_to failed; see forward fail counter)`（`main.rs` 失败分支）。
4. **L5 Hook 拒载帧进计数**：新增 `skip_rejected_flags` 计数器，`REJECTED_OVERSIZE | NO_PAYLOAD` 帧在转发分派处先 `frames_seen += 1` 再 `skip_rejected_flags += 1`，闭合恒等式扩为含 rejected 项（`main.rs` 转发分派重构为三段：rejected / discovery / consider，注释标 rounds 2 and 3）。

### 5.2 测试侧（第三轮新增）

5. **M6 发现帧全文件缺席断言**：原断言只查"629xx+magic 未被转发"，现改为 seq=3 **不出现在 forward-log 任何一行**（不转发、也不作为 skip 行出现）——发现路径整体绕过转发阶段，全文件缺席才是诚实检查。
6. **M7 跨文件身份对照**：原"首个发送者"只与 summary 自己的 `forward sock` 行比端口（同一文件，两行一起错也会通过）。现在逐条读 peer-recv 的 `from=`，与 summary `forward sock` 对照：端口必须相等且 ≠ 62056；IP 项按实现为 `fromIp ∈ {127.0.0.1, fwSockIp}`——回环下 127.0.0.1 恒过，**绑定项是端口而非 IP**（第四轮 E-6 已如实写明，不再宣称"比 IP"）。
7. **M5 删恒真断言**：`skip key table == 0` 是夹具不触发的恒真检查，已删除（计数保留在恒等式里），由单测 `forward_key_table_full_refuses_to_forward` 覆盖。
8. **L8 负向断言分用例**：三条负向用例分别匹配各自的拒绝文案（`port must not be 62056` / `forward-listen must not be 62056` / `forward-to must not target port 62056`），`$code` 在 `Kill()` 前读取。
9. **R3-L2 transcript + .bak**：`Start-Transcript` 落 `selftest-console.txt`；脚本留 `run-f3a-forward-selftest.ps1.bak-154748`（对齐 F3-B 的 `.bak` 惯例）。

### 5.3 已声明但不修（第三轮明确"不必本轮做"）

10. **L2 转发 socket 绑 `0.0.0.0:0`**：真实双机前需放开，留到 F3-D/F3-E。
11. **L7 bind-check 只按 OwningProcess 观测**：`bind-check` 只证明运行期该进程没绑 62056；`SO_REUSEADDR` 仅由源码静态审查佐证（本原型无此调用），断言名如实反映观测范围。
12. **L1 listener 收包缓冲 2048B 可截断**：回环转发载荷 ≤1280B（CVLH2 上限）不触发；真实载荷超限时可能截断，属原型已知限制，F3-E 前不修。

### 5.4 PowerShell 环境（继续沿用）

13. **`Start-Process -RedirectStandardOutput` 在 Windows PowerShell 5.1 下拿不到 `ExitCode`**——`HasExited` 为真、`WaitForExit()` 之后仍是空。用 `cmd /c exit 3` 复现确认与 Agent 无关。改为 `System.Diagnostics.ProcessStartInfo` + `StandardOutput.ReadToEndAsync()`。
14. **`WaitForExit(ms)` 只保证"已退出"，不保证退出码可读**；用 `HasExited` 轮询，随后无参 `WaitForExit()` 再读 `ExitCode`。
15. 断言里不要用 `$proc.ExitCode` 直接进 `"$()"`（空值静默变空串使比较恒假）。
16. 字符串插值里 `$ip:$port` 会被当成驱动器限定变量——必须写 `${ip}:${port}`。

## 6. 运行历史（含失败，全部点名）

| 时间戳目录 | 结果 | 说明 |
|-----------|------|------|
| `F3A-forward-selftest-20261114-142008` | PASS 17/17 | **v1 记录所引证据，已作废**：按现行判据离线重放有 6 条不成立（只比前缀/只比长度/无配对/无负向用例等），且 120B 后 112 字节无证据 |
| `-141849` / `-141904` / `-141929` | 未完成 | 整改过程中的中途运行（端口/夹具调整），**未用于任何结论** |
| `-144051` | PASS（Agent 侧） | 脚本在两次运行之间被修改且无备份，**不可审计**，不采信 |
| `-144121` | PASS 37/37 | 整改后首轮（"37"的来源不可复原——`-150906` 的 v3 脚本实测 30 个 Check 站点、`-155041` 的 v4 脚本 31 个，均证明不了 37；**该行仅作历史点名，不采信其数字**） |
| `-150809` | **FAIL 2/34** | rev3 首跑，闭合恒等式抓到"发现帧不进 frames_seen"缺陷（§5.1 第 5 条），已修 |
| `-150855` / `-150906` | PASS 34/34 | **v3 记录采信，现已随 v4 作废**（断言口径更换为 31 站点/35 次，`frames seen` 标签已改） |
| `-154749` | **FAIL（脚本语法错误）** | v4 脚本首跑：`from=$fromIp:$fromPort` 被 PS 解析为驱动器限定变量，ParserError 提前终止；已修（第 16 条教训） |
| **`-155041`** | **PASS 31 站点/35 次执行** | **本记录采信**；§4 身份表所引 |

## 7. 本记录与前三版的差异（不是同一命题）

- v1 写"17 项断言 / `142008` / 9 个旧哈希"，v3 是"34 项断言 / `150906` / 13 个哈希"，v4 是"**31 站点 / 35 次执行** / `155041` / §4 身份表 15 行、14 个去重哈希（agent-console 与 agent-stderr 同哈希）、11 个证据文件"。**数字不能跨版本比较**，`142008`/`150906` 的 PASS 在现行判据下不成立。
- 断言口径（第三轮 R3-H3）：**31 个 `Check` 站点 / 35 次运行期执行**（3 条负向用例循环内 2 站点 × 3 次 = 6 次 + 其余 29 站点各 1 次）。任何"37"的表述都已删除，`144121` 那行只作历史点名。
- **回包策略（第三轮 R3-H1，v3 说反已更正）**：本步实跑的是设计 §5.2 的"**D4 兼容**"分支——`--simulate-datapath` 模式下每 run 发出 **1 个 20B 本机探针**（`reply sent 1` / `reply bytes 20` / `already_sent 5`，见 `datapath-log.txt`）。**不是** v3 声称的"回包为零"。该 20B 探针是**本机单次探测**，不代表真实 Peer 源端口，不代表游戏协议应答。F3-A 转发路径本身与它正交：转发发生在 Agent 之间，探针是 Agent→发送方 socket 的本机回环包。
- **构建可复现（第三轮 R3-H2，v3 的因果已删除）**：不声明"逐字节同哈希 = 可复现"。交付副本是构建目录产物的逐字节拷贝；三次 clean build 哈希互不相同（.pdb 绝对路径嵌入 exe）。
- 自环声明：`--forward-to` 与 `--forward-listen` 同为 `127.0.0.1:21346`，即**同进程双角色自环**。这是有意的（不需要第二台机），但必须写明——v1 没写，容易让人误读成"两个 Agent 之间"。
- 全仓单测口径（第三轮 R3-M3）：**agent 19 + fakeip 17 = 36**，不是"全仓 19"。本记录只陈述 agent 侧 19。
- 运行次数口径（第三轮 R3-M2）：§3 的"六次运行"实为**五次**（142008 / 144051 / 144121 / 150809 / 150906，`141849` 等 3 个未完成不计）。本记录以 §6 表为准。
- 幽灵端口（第三轮 R3-M4）：v3 §2 步骤 1 的 `21347` 端口不存在（自检只用 34718 + 21346），已删。
- 引用修正（第三轮 R3-M5）：§5 的"（§5.5）"实为"§5.1 第 5 条"。

## 8. 下一步

- F3-A 审计链：第四轮 `F3A-REVIEW-4.md`（子代理 f2195d8a）**有条件通过**（0/0/0/6 低），6 项低（E-1..E-6）已全部修正（断言名 50999、§7 哈希口径 15 行/14 去重/11 证据、§6 37 归因、§2 分组 31/35、§3 不证明清单补 L1/L7、M7 表述 IP 项恒过）；脚本终值 22,801B/`7AB1A9E7…`（本表所引）。**第五轮 `F3A-REVIEW-5.md`（3c311e41）裁定通过**（0/0/0/0），F3-A 登记通过。
- F3-B Relay 转发原型：已完成（见 `docs/F3B-RELAY-FORWARD-20261114.md`，v3，68/68，证据 `F3B-relay-selftest-20261114-152821`）；第三轮审计 `F3B-REVIEW-3.md` **通过**。
- F3-C 退避语义：已完成（见 `docs/F3C-BACKOFF-20261114.md`，v2，26/26，证据 `F3C-backoff-selftest-20261114-151943`）；第二轮审计 `F3C-REVIEW-2.md` 阻断 R2-B1（证据树被 F3-A 重建覆盖）——已用当前树重跑转正（证据 `F3C-backoff-selftest-20261114-160401` 快速验证 26/26，全时序采信运行进行中）。
- F3-D 忙轮询压力：已完成（见 `docs/F3D-PRESSURE-20261114.md`）；审计 `F3D-REVIEW.md` 的 8 项有条件通过修正已全部落地（20 条断言口径、EF BB BF 0D 0A 归因、同源恒真标注、§7-5 降级、17 文件、0.28s 降级、基数标注、Gate 登记）；**"Hook 观测路径未验证"已登记进 README v1.18 Gate 段**。
- F3-E 故障注入（对端退出 / Relay 掉线 → DEGRADED→RECONNECTING 不踢人语义断言；**必须含 fatal/exit 3 真实用例**）：进行中。
