# F3-B「Relay 转发原型」独立审计报告

> 审计对象：`docs\F3B-RELAY-FORWARD-20261114.md` 及其源码/脚本/证据
> 审计依据：`docs\F3-DIRECT-RELAY-DESIGN-20261114.md` v0.3 定稿（权威）
> 审计日期：2026-11-14
> 审计性质：**只读审计**。除本文件外未修改任何文件；为验证行为，另启动过若干次 `civlink-relay.exe` 的一次性实例（均使用 34771/34781 等非证据端口，未写入 `M0A\captures`，不影响任何既有证据）。
> 审计执行者：独立审计员（子代理）

---

## 0. 总结论

**总结论：有条件通过**

F3-B 的核心交付在**本机回环、非发布**这一自我限定范围内是真实的：证据目录文件哈希与文档 §6 逐项吻合，`Relay 按 dst_peer 路由 + 载荷字节原样 + 一次输入最多一个输出 + 不重传 + 无加密` 这几条在源码里是可逐行验证的，且 43 条断言中绝大多数是真正的机器检查（三方 FNV-1a 比对是其中最有价值的部分）。

但存在**三处必须在下一步之前修掉**的问题：

1. **§5「一个坏包不会让 Relay 停止」这条"证明"是可证伪的。** 我实测：向 Relay 发一个 5000 字节的数据报，`recv_from` 返回 `WSAEMSGSIZE (os error 10040)`，代码走进 `break`（`main.rs:261-264`），进程**提前退出且退出码为 0**，`relay-summary.txt` 仍以 `datagrams: 0` 正常落盘。这既是代码缺陷（一个越界报文即可停服），也是表述缺陷（把不成立的事写进了"证明"）。
2. **文档 §1「不信任信封里的 `src_peer`」与源码 `main.rs:322-326` 直接矛盾**：来源地址未注册时，代码回退为 `unwrap_or(env.src_peer)`，即**恰恰信任了信封里的 `src_peer`**。我实测确认：未注册的发送者 C 以 `src_peer=777` 发数据，B 侧收到的帧 `src_peer=777`。
3. **H2 门槛（不 bind 62056）只有脚本前置条件在守，二进制本身零防护。** `main.rs:186` 对 `--listen` 不做任何端口校验；我实测 `--listen 127.0.0.1:62056` **成功绑定**并继续服务（`Get-NetUDPEndpoint` 显示 `127.0.0.1:62056 pid=39372`）。同门类的 F3-A Agent 是 fail-closed 拒绝 `PORT == 62056`，此处没有对齐。

另有 2 条断言是恒真式、1 条对账恒等式对丢包是"盲"的（详见 B 节），以及 1 处哈希表字节数与实测不符（Cargo.toml 583 vs 479）。

这些都不推翻 F3-B 的主结论（"按 dst_peer 透明转发 + 载荷原样"已被真实可复现地演示过），故不判"不通过"；但表述层面已出现被实测证伪的句子，故不能判"通过"。

| 审计项 | 结论 |
|---|---|
| A. 证据真实性 | **有条件通过**（9/9 引用哈希一致；Cargo.toml 字节数不一致、2 处表格缺项） |
| B. 断言强度 | **有条件通过**（2 条恒真、1 条对账对丢包失明、覆盖面称 5 实 2） |
| C. 代码与设计一致性 | **有条件通过**（§4 载荷/不重传/一进一出/§4.1 无加密成立；`src_peer` 回退、62056 无防护是偏差） |
| D. 表述边界 | **不通过**（"一个坏包不会让 Relay 停止"与"两个方向"均被证伪/不成立） |
| E. 缺陷清单 | 见 §E（0 阻断 / 1 高 / 4 中 / 6 低） |

---

## A. 证据真实性

### A.1 方法

对文档 §6 表格中的每个文件，用 `Get-FileHash -Algorithm SHA256` 重算哈希、用 `(Get-Item).Length` 取字节数，逐项与文档值做字符串比对（大小写不敏感，报告内按实测原样大小写）。同时单独重算三个产物（`civlink-relay.exe`、`src\main.rs`、`run-f3b-relay-selftest.ps1`）。

### A.2 证据目录 `M0A\captures\F3B-relay-selftest-20261114-142803\`

| 文件 | 文档字节 | 实测字节 | 文档 SHA-256 | 实测 SHA-256 | 判定 |
|---|---:|---:|---|---|---|
| `relay-summary.txt` | 1,015 | 1015 | `2E5CB887…0BFEA57` | `2E5CB88757333709CEB24E94EAB4681FE4A0B8C20B99A580ED8F8AACA0BFEA57` | 一致 |
| `relay-log.txt` | 1,126 | 1126 | `A11AD18E…12C3176` | `A11AD18EF8519FFC93CDB05311DDED218AAFE5E48CEE63AD83FDBC7A212C3176` | 一致 |
| `bind-check.txt` | 24 | 24 | `D386A4E1…85DCBF18` | `D386A4E1EE3A12F7BAFF08FAC8CD1172A461C8FADFF7D6E1AEA5453785DCBF18` | 一致 |
| `result.txt` | 515 | 515 | `C02AF8C8…EE075C078` | `C02AF8C8CBEF783DB4D49248B01773F70AB7235C3E1CF57ACD5A130EE075C078` | 一致 |
| `exit.txt` | 12 | 12 | `01AD8A20…F01CAD1AE` | `01AD8A20D9C655F39D931C98ACC135EF2B5505ECCEE6B6845F1667FF01CAD1AE` | 一致 |
| `relay-console.txt` | 5 | 5 | `F01A374E…96EED6295` | `F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295` | 一致 |
| `relay-stderr.txt` | 5 | 5 | `F01A374E…96EED6295` | `F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295` | 一致 |

结论：**文档 §6 引用的 7 行（6 个文件 + 1 组合行）哈希与字节数全部一致，零偏差。**

两项**表格缺项**（不影响哈希真实性，但影响完整性）：

- 目录中实际有 **8 个文件**，`stop.txt`（6 字节，`A0B28CDF92E250A1A93294D91144A0F893D27197D56B39991CC421768794005F`）未列入 §6 表格。
- `relay-console.txt` 与 `relay-stderr.txt` 被合并为一行并共用一份哈希。两者内容确实相同（均为 `ef bb bf 0d 0a`，即 UTF-8 BOM + CRLF，**实质为空输出**），因此共用哈希不算错，但"5 / 5"单行双文件的写法降低了可核性——建议拆成两行、各给哈希。

补充事实（不构成问题，供读者理解证据）：`relay-console.txt` 为 5 字节空内容，是因为脚本以 `--quiet` 启动 Relay（`run-f3b-relay-selftest.ps1:145`），因此 `main.rs:445-447` 的 `if !quiet { print!("{s}") }` 这条打印路径在本次自检中**未被覆盖**，summary 只经文件通道产出。

### A.3 三个产物的哈希

| 文件 | 文档字节 | 实测字节 | 文档 SHA-256 | 实测 SHA-256 | 判定 |
|---|---:|---:|---|---|---|
| `civlink\relay\src\main.rs` | 15,579 | 15579 | `C2337406…D8CFF2B6` | `C2337406370E0489E7DAFC6371D88A3CA53EF128579991C918C27AD9D8CFF2B6` | 一致 |
| `civlink\relay\target\release\civlink-relay.exe` | 253,952 | 253952 | `88AAB644…67A0DA87` | `88AAB6444C6C55311F3FDE80E38ACAF47EAE5FDD1DC1CE17FDB6498C67A0DA87` | 一致 |
| `civlink\run-f3b-relay-selftest.ps1` | 19,041 | 19041 | `2D4A9E1E…B95F7` | `2D4A9E1E556DAA911301CB62179E72DD0FD348DAB40434825E4D3F17B3CB95F7` | 一致 |
| `civlink\relay\Cargo.toml` | **583** | **479** | 见 cargo 构建输出（**无哈希**） | `93C7D4DA43D523693C83644234CBE95FBDD43EF120489031D50491E21B9614D1` | **不一致 + 缺哈希** |

**不一致项 1（必须指出）**：`docs\F3B-RELAY-FORWARD-20261114.md:100` 声称 `civlink\relay\Cargo.toml` 为 **583 字节**，实测 **479 字节**，差 104 字节。文件 mtime 为 14:21:07（早于 `main.rs` 的 14:21:29 与 exe 的 14:22:05），说明该文件在构建前被改过而文档表格未同步。同一行还以"见 cargo 构建输出"代替哈希——cargo 构建输出**不产生**依赖清单的 SHA-256，这条引用无可核对象，属填表缺陷。

**交叉验证（加分项，说明 exe 哈希不是孤证）**：`result.txt` 内由脚本自己写下的 `relay sha256 : 88AAB644…67A0DA87` 与我对 exe 的实测值一致；`target\release\deps\civlink_relay.exe` 亦为同一哈希（`88AAB644…`），说明产物未被事后替换。

### A.4 三次 PASS 目录与未披露的失败轮次

`142803` / `142813` / `142818` 三个目录**全部为 `PASS (43/43)`**（`result.txt` 首行逐一确认）。`142813`、`142818` 的 `relay-summary.txt` 与 `142803` 的差异**仅 `run time` 与耗时**（3.5s / 3.6s），全部计数字段逐字相同；`relay-log.txt` 的差异仅时间戳与临时端口（55659/55660 → 62691/62692）。**同一二进制、同一脚本、三次独立运行给出完全相同的计数矩阵**，这是本次审计中可信度最高的部分。

但证据树中还有 **3 个文档未点名的目录**：

| 目录 | result.txt 首行 | 说明 |
|---|---|---|
| `F3B-relay-selftest-20261114-142256` | `FAIL (3 of 40 failed)` | 文档 §4 第 1 条所述 FNV/PowerShell uint64 问题（`payload1 fnv1a64 : 0000320000005415` 明显是错误哈希） |
| `F3B-relay-selftest-20261114-142419` | `FAIL (6 of 41 failed)` | 文档 §4 第 2 条所述真实丢包（`registers: 1`、`peers seen: 1`、`self drop: 0`，`seq=3` 落到 `no-route`） |
| `F3B-relay-selftest-20261114-142718` | `PASS (41/41)` | 中间态 PASS（脚本当时只有 41 条断言） |

评估：**保留失败证据是良好实践**，且文档 §4 确实叙述了这两个问题，**不构成隐瞒**。但：

- §4 只描述现象、**未给出对应证据目录名**，读者无法定位到 `142256`/`142419`；建议补目录名与 `result.txt` 首行。
- §6 说"三次连续 PASS"是**准确的**（末三次确实连续 PASS），但同一句与"三次"并列会让读者误以为总共只跑了三次；建议改为"共 6 轮，前 3 轮中 2 轮 FAIL、后 3 轮连续 PASS"。
- `142718` 为 `41/41`、`142803` 为 `43/43`，说明脚本在 `14:27:56`（mtime）又被改过一次（增加了 2 条断言）。文档未说明这 2 条是什么；从 `142718` 的 `result.txt` 无失败项、`142803` 多出的两条与 `142419` 的失败项（`datagrams = 8` / `registers = 2` 这类固定数字）完全对应来看，应是将固定数字断言改为自洽关系的那次修改。**这一处应在文档中写明，否则"43/43"与"41/41"的差异来源不明。**

### A.5 A 节结论

**有条件通过。** 所有被引用的哈希与字节数（除 Cargo.toml）**完全一致，无篡改迹象**；三次 PASS 可复现且计数逐字相同；失败证据保留完整。需修正的是：Cargo.toml 字节数 583→479 并补哈希、补 `stop.txt` 行、拆分 console/stderr 两行、把 `142256`/`142419`/`142718` 三个目录写进文档并说明 41→43 的两条断言是什么。

---

## B. 断言强度

### B.1 方法与总览

脚本共 **43 次 `Check` 调用**（`Select-String -Pattern '^\s*Check '` 计数 = 43，与 `result.txt` 的 `43/43` 一致）。逐条按"是否真的在验证设计条款"分为四类：

| 类别 | 条数 | 行号 |
|---|---:|---|
| ① 真行为验证（观察进程/网络/文件的真实状态） | 32 | 163,173,256,259,260,261,262,263,267,268,269,272,286,313,314,315,316,317,318,319,320,332,345,346,347,354,355,361,362,363,364,365 |
| ② 弱/自洽（恒等式或上界，不能独立发现错误） | 5 | 310,311,312,321,322 |
| ③ 恒真（无条件 `$true`，永不失败） | 2 | 139,140 |
| ④ 存在性（有意义但极弱） | 4 | 291,327,343,352 |

32 + 5 + 2 + 4 = 43 ✔

### B.2 站得住的部分（真正在验证设计条款）

- **`262`、`263`、`269`、`345`、`354` —— 三方载荷比对，这是本自检最有价值的设计。** 发送方本地算 FNV-1a 64、Relay 在自己的日志里算一遍、接收方对收到的字节再算一遍，三值相等才算过；`347` 还额外比了 `head=17320000ffff4fac` 十六进制。这比"比较长度"强得多，确实能抓住"长度对但内容被改"的情形。FNV 不是密码学哈希，但对**演示原型**足够，且脚本注释（`:53-54`）与 summary 注释（`main.rs:440-441`）都明确声明"不是安全哈希"，未夸大。
- **`314`/`315`/`316`/`318`/`319`/`320`（`forward requests=4`、`forwarded=2`、`forward bytes=128`、`no route=1`、`self drop=1`、`bad envelope=2`）是精确期望值**，不是上界。这几个数字互相独立（128 = 8 + 120；2 = 两条 dst=202；1+1+2 = 4 的前向请求分解），任何一个跑偏都会失败。`142419` 就是这样抓住丢包的。**这几个数字应保留，不要为了"抗抖动"弱化。**
- **`272`（no-route/self 未被投递）配合 `256`（B 恰好收到 2 帧）构成对"一次输入最多一个输出"的有效旁证**：若 Relay 重复发送，B 会收到 3+ 帧，`256` 直接失败。这条设计得好。
- **`173`（Relay 未占用 62056）虽弱但有意义**：它用 `Get-NetUDPEndpoint` 查系统真实绑定表，不是读程序自报的字串。

### B.3 站不住的部分

**(1) 两条恒真断言（`139`、`140`）—— 应直接修掉。**

```powershell
139: Check 'precheck port 34720 free' $true
140: Check 'precheck port 62056 free (H2)' $true
```

`Check` 的第二个参数恒为 `$true`，无论实际情况如何都会 PASS。真正的门是上面 `134-138` 的 `exit 2`：**如果预检失败，脚本根本不会执行到 `139`；如果执行到了 `139`，则必然通过。** 所以这两条**永远不可能失败**，纯属把 `43` 这个数字做大。它们不验证任何东西，却出现在"43 项断言"的宣传里，属于典型的水分。修法：把预检结果存入变量（`$portA0Free`、`$port62056Free`），失败时**不要 `exit 2`**，而是走完 `Check` 再 `exit 2`；或干脆删掉这两条并把总数改为 41。

**(2) `310` 的对账恒等式对"真丢包"是失明的 —— 这正是审计要求 B 特别要问的点。**

```powershell
310: Check 'datagrams = registers + forward requests + bad envelope' (($rCount + $fReq + $bEnv) -eq $dCount)
```

`datagrams` 是 Relay **收到的**报文总数；右边三项是**同一个进程自己分类计数**的结果。一个数据报如果在到达 Relay**之前**就在回环上丢了，它既不进 `dCount` 也不进任何右项——**等式两边同时减小，恒等式依然成立。**

也就是说：文档 §4 第 2 条说"把注册条数这类计数断言改成 `datagrams == registers + forward requests + bad envelope` 这种自洽关系，避免用固定数字掩盖丢包"——**这个改法确实消除了偶发 FAIL，但同时把"丢了几个"这件事彻底藏了起来。** 真正的丢包只由 `311` 的 `registers >= 5` 兜底：

```powershell
311: Check 'registers >= 5 (both peers, at least one refresh)' ($rCount -ge 5)
```

设计意图是 **8 条**注册（3 + 3 + 2 刷新，见 `196-203`、`217`）。`>= 5` 意味着**丢掉 1~3 条注册，43 条断言全绿**。`142419` 当初丢 1 条就 FAIL 了 6 项，修完之后丢 1 条**不会再有任何断言报警**。这不是"容忍不确定性"，而是"把不确定性变成了静默"。

审计要求 B 明确问"是否把不确定性藏起来了"——**答案是：是，部分藏起来了。** 建议的修法不是退回固定数字（会回归抖动），而是**双轨**：
- 保留自洽恒等式，但额外把**发送侧自己数出来的数量**写进证据并断言：脚本知道自己发了多少（8 注册 + 4 数据 + 2 畸形 = 14），断言 `datagrams == 14`，这样丢包**必然**体现在 `dCount` 上；抖动风险与现在一样（`142803/142813/142818` 三次都是 14，可复现），但对丢包敏感。
- 或者至少把 `311` 改成 `registers -eq 8`，并配"允许重试"的说明；若真要容忍，就必须在 `result.txt` 里**显式打印"设计 8 / 实收 N / 丢失 8-N"**，让读者看见损失，而不是让它消失。

**(3) `312` 是定义上的恒真。** `control frames = registers`：源码里 `stats.registers += 1` 与 `stats.control_frames += 1` 在**同一个分支的相邻两行**（`main.rs:288-289`），任何输入下都相等。这条断言只能抓住"有人改了计数器"这种代码回归，抓不住行为错误。

**(4) `321`、`322` 是字符串存在性检查。**

- `321`（`reconciliation … ==`）匹配的是 `main.rs:422-433` 自己拼出来的那行字。只要代码里那个 `if` 没被改坏就恒成立；它与"计数是否正确"无关（`!=` 分支从不被触发）。
- `322`（`summary states plaintext`）grep 的是 `main.rs:437` 里硬编码的字面量 `sees PLAINTEXT`。**它验证的是"源码里写了这句话"，而不是"程序没有加密"。** 后者只能靠代码审读（本审计 C 节已做），不能靠 grep 自己的输出。

**(5) 覆盖面与文档声明不符（断言层面）。** `docs\F3B-RELAY-FORWARD-20261114.md:82` 称"信封解析对**五类**畸形输入都能拒绝"。源码确有五类（`main.rs:90` `too-short`、`:93` `bad-magic`、`:96` `bad-version`、`:100` `payload-too-large`、`:103` `truncated`），但脚本只发了两类：

```powershell
233-238: 12B 全零 -> too-short；24B 且 [4]=1、magic=0 -> bad-magic
363-364: 只断言 'kind=too-short' 与 'kind=bad-magic' 各一条
```

`bad-version`、`payload-too-large`、`truncated` **一条都没有测**。这是"称五实二"。

**(6) 接收循环的上限 4 偏紧但可用。** `244: for ($i = 0; $i -lt 4; $i++)` 最多收 4 帧；正常只该来 2 帧。若 Relay 重复发送 3~4 帧，`256`（count==2）能抓住；若重复 5 次以上也只收到 4 帧，仍会 FAIL。**结论：可用，无漏洞**，但把上限提到 6 会让失败信息更完整（能报出"实际收到 N"而不是"截断在 4"）。

### B.4 B 节结论

**有条件通过。** 32/43 是真正的机器检查，三方哈希链（`262/263/269/345/354`）与六个精确计数（`314-320`）构成了有说服力的核心；`272`+`256` 的组合能抓住重复投递。必须修正的是：删/改 `139`、`140` 两条恒真断言；`310` 的对账恒等式不能作为"不丢包"的证据（`311` 的 `>=5` 相对设计值 8 掩盖了最多 3 条注册的丢失）；`312`/`321`/`322` 是自证式检查，不应计入"验证设计条款"的计数；五类拒绝只测了两类。

---

## C. 代码与设计一致性

### C.1 §4「Relay 透明转发铁律」逐条核对

设计原文（`F3-DIRECT-RELAY-DESIGN-20261114.md:76-81`）：

> - **62056 载荷 100% 原样**，Relay 不解密 L2、不改载荷、不重传。
> - 出向 8B 帧到达 Relay → 按 dstPeer 转对端 Agent；对端 Agent 注入游戏（Design I/II）。
> - 响应路径对称。

| 设计条款 | 代码依据 | 判定 |
|---|---|---|
| **不解密** | 全文件无任何加解密、无 `noise`/`aead`/`crypto` 依赖；`Cargo.toml` 的 `[dependencies]` 为空段。relay 只见明文。 | **通过** |
| **不改（载）荷** | `main.rs:110` 载荷切片 `&buf[HDR..HDR + payload_len]`；`:122` `out[HDR..HDR + payload.len()].copy_from_slice(payload)`；**载荷字节只在两处被读一次、写一次，中间无任何变换**。`forward_bytes` 累加用 `env.payload.len()`（`:364`），与实际拷贝长度同源。 | **通过**（但注意下方的头部改写） |
| **不重传** | `main.rs:361-392`：`send_to` 一次，成功计数 `forwarded`，失败计数 `forward_fail`（`:381`），**无循环、无重试、无定时器**。summary 亦自述"does not … retransmit"（`:438`）。 | **通过** |
| **不重排** | 单线程 `loop`：`recv_from`（`:254`）→ 处理 → `send_to`（`:361`），**同一线程内串行**，后到的帧不可能先发。结构上不可能重排。 | **通过** |
| **一次输入最多一个输出** | 每轮循环最多一次 `send_to`，且在 `continue` 分支（`:283`、`:303`、`:317`、`:340`、`:356`）均不发送。**结构上成立。** | **通过** |
| **载荷 100% 原样** | 见上。8B/120B 两长度已实测逐字节相同（`262/263/269` 及我复算的 `17320000ffff4fac` / `030a11181f262d34`）。 | **通过** |
| **响应路径对称** | 代码层面无所谓"响应"——路由只看 `dst_peer`，反向只需对端也注册。**但自检完全没测反向**（见 D 节）。 | **有条件通过**（代码对称、证据不对称） |

**偏差 C-1（中）：头部被改写，且 `src_peer` 被丢弃重填。** `main.rs:114-124` 的 `encode()` 会重写 magic/version/flags/dst/src/seq/len 全部 20 字节头部，其中：

- `:117` `out[5] = 0;` —— **转发帧的 flags 恒为 0**。若发送方用 `flags=0x02`（未来语义）发数据，会先在 `:306-318` 被当作 "unknown-flags" 计数丢弃，永远不会进转发路径。这不是当前 bug，但**是一个未声明的策略**：Relay 只能转发 `flags==0` 的帧。
- `:119` `out[10..14] = src_peer.to_le_bytes()` —— 发送方的 `src_peer` 被**无条件丢弃并覆盖**。设计 §4.2 说的是"载荷 100% 原样"，头部不在其列，因此**不算违反铁律**；但文档 §1 第 21 行"载荷原样"与 §2.2 §3.2 的映射键语境下，读者容易误以为"整帧透明"。建议在文档里明确写"**载荷透明、头部重写（Relay 是端点语义不是穿通语义）**"。

**偏差 C-2（中，与文档直接冲突）：未注册来源时回退信任信封 `src_peer`。**

```rust
// main.rs:322-326
let sender = peers
    .iter()
    .find(|(_, a)| **a == from)
    .map(|(p, _)| *p)
    .unwrap_or(env.src_peer);          // <-- 这里
```

`docs\F3B-RELAY-FORWARD-20261114.md:20` 写的是"**不信任信封里的 `src_peer`**；转发时重写为自己算出的发送者"。**当来源地址未注册时，代码信任的恰恰就是信封里的 `src_peer`。**

我的实测（临时端口 34781，非证据端口）：

```
TEST1 unregistered sender spoof: B got seq=11 src_peer=777 (envelope claimed 777) dst=202
      -> relay TRUSTED src_peer=True
```

未注册的第三个 socket C 直接以 `src_peer=777` 发数据，B 侧收到的帧 `src_peer=777`。也就是说"发送者归属"这条能力**只对已注册来源成立**。这与文档 §2「没有身份与鉴权，谁注册谁就是那个 peer_id」是一致的（所以不是安全新洞），但**与 §1 那句话是直接矛盾**，必须改一处（改代码 fail-closed，或改文档措辞）。

**偏差 C-3（低→中）：`peers` 反查是按值遍历 HashMap，一址多号时结果不确定。**

```rust
// main.rs:290-292
peers.insert(env.src_peer.max(env.dst_peer), from);   // 无注释的别名行
peers.insert(env.dst_peer, from);
```

`:290` 的 `max()` 会额外插入一个**发送方从未声明的 peer id**。若一个地址先后发 `REGISTER dst=303 src=500`，就会在同一 `from` 上挂 **500 和 303 两个 id**；此时 `:322-326` 的 `.find(|(_, a)| **a == from)` 在 `HashMap` 上迭代，**返回哪个 id 取决于哈希遍历顺序**（`std::collections::HashMap` 无插入序保证）。这使"发送者归属"在 NAT/多租户共享地址场景下不可确定。`:291` 的注释只解释了 `:292`，`:290` 这行**没有任何注释**，属遗留/死逻辑嫌疑。建议删掉 `:290`，或改为 `BTreeMap` + 显式"一址一号"校验并计数冲突。

### C.2 §4.1「加密范围声明」核对

设计原文（`:74`）：L1/L2 Noise E2EE 是最终目标，**F3 原型不实现加密**，明文 CVLH2 验证转发语义，不冻结 wire format。

| 核对项 | 依据 | 判定 |
|---|---|---|
| 无加密实现 | `Cargo.toml` 零依赖；`main.rs` 无 crypto 调用；exe 内 ASCII 串确认无 crypto 痕迹 | **通过** |
| 明文被**声明**而非被隐瞒 | summary 固定输出 `- This Relay sees PLAINTEXT: the F3 prototype has no encryption (design section 4.1).`（`main.rs:437`），实测落盘于 `relay-summary.txt` | **通过** |
| 不冻结 wire format | 文档 §2 明说"一律不实现、不冻结 wire format"；`CVLR` 是原型私有 magic，与游戏侧 `17 32 00 00 FF FF` 载荷分层 | **通过** |
| 未冒充"已加密" | 文档 §5 不证明清单含"不证明加密、身份、抗重放" | **通过** |

**这一节是本提交件做得最干净的部分**：设计 v0.3 审计项⑤（加密范围声明）在代码、文档、运行输出三处一致落地，无夸大。**通过。**

### C.3 §3.2「出向键」核对

设计原文（`:56`）：Agent 按 **`(session_id, logical_socket_id, socket_generation, dst)`** 查出向映射；未命中计数 `no_mapping`。

| 核对项 | 事实 | 判定 |
|---|---|---|
| Relay 是否实现该四元键 | **否**。`main.rs` 只有 `HashMap<u32 /*peer*/, SocketAddr>`（`:234`），路由键是 `dst_peer`（`:342`） | 与 §4.2 一致，**不构成偏差** |
| 文档是否误标 | `docs\F3B-…md:121-122` 把"§3.2 出向键"列为本文设计依据 | **措辞不当**（见下） |

说明：§3.2 描述的是 **Agent 侧**的出向映射（F3-A 的范围，`docs\F3A-DIRECT-FORWARD-20261114.md:16` 已实现四元键），Relay 侧按设计 §4.2 就是 `dstPeer` 路由。因此**代码没有偏离设计**，但 `F3B` 文档 §7 把 §3.2 列为本篇依据会让人以为 Relay 也实现了四元键。**低severity 措辞问题，建议改为"§4.2（按 dstPeer 转发）；§3.2 属 F3-A/Agent 侧，本篇不涉及"。**

### C.4 §5.3「H2 门槛」核对

设计原文（`:112`）：

> **Agent 继续经 CVLH2 观测 + 临时端口回包路线，不得与游戏共存绑定 62056、不得设 SO_REUSEADDR**，直至 M0-B 裁决 H2。

| 核对项 | 依据 | 判定 |
|---|---|---|
| 不设 `SO_REUSEADDR` | 全文件无 `setsockopt`/`socket2`/`winapi`/`libc`（`Select-String` 命中 0 条）；`UdpSocket::bind`（`:186`）是 std 默认，Rust std 在 Windows 上不主动设该选项 | **通过** |
| 不 bind 62056（行为） | 默认 `127.0.0.1:34720`（`:142`）；自检实跑未绑 62056（`bind-check.txt` = `udp:62056 endpoints: 0`，实测 24 字节哈希一致） | **通过（就本次运行而言）** |
| 不 bind 62056（**代码强制**） | **无任何校验。** `main.rs` 全文 `Select-String '62056'` 命中 **0 条**；`--listen` 直接 `v.parse()` 后赋给 `listen`（`:153-159`），`bind(listen)` 照单全收 | **不通过（偏差 C-4）** |

**偏差 C-4（中）：H2 门槛无代码防护，`--listen 127.0.0.1:62056` 会成功绑上游戏端口。**

我的实测（临时端口探测，62056 当时空闲）：

```
RUN B: --listen 127.0.0.1:62056 -> endpoints on 62056 = 1; still running = True
RUN B: relay DID bind 62056: 127.0.0.1:62056 pid=39372
```

对照同项目 F3-A 的 Agent：`civlink\agent\src\main.rs:17` 明确"**拒绝** `PORT == 62056`（fail-closed）"，`:27` 注释"NEVER binds :62056"，`:669` 注释"sock: bound to 127.0.0.1:<--forward-listen>, **never :62056**"。**同一数据面的两个组件，一个 fail-closed、一个零校验，属实现不一致。**

这直接影响 `docs\F3B-…md:85` 的"证明"："Relay 全程未占用 62056，符合 H2 门槛"——**这句话只在"以默认/合法参数启动"的前提下为真；二进制本身并不保证它**，保证它的是脚本 `134-138` 的前置检查（要求 62056 空闲）。而 62056 空闲恰恰使"未占用"成为**必然**，因此这条"证明"在逻辑上是**由前置条件推出、而非由被测对象推出**的同义反复。

### C.5 额外发现（代码行为）

**偏差 C-5（高）：单个超长数据报即可让 Relay 停服，且以退出码 0 静默收场。**

```rust
// main.rs:239
let mut buf = vec![0u8; 4096];
// main.rs:254-265
let (len, from) = match sock.recv_from(&mut buf) {
    Ok(v) => v,
    Err(ref e) if e.kind() == io::ErrorKind::WouldBlock || e.kind() == io::ErrorKind::TimedOut => continue,
    Err(e) => { eprintln!("[!] recv_from failed: {e}"); break; }   // <-- 任何其它错误都停机
};
```

Windows 上 `recv_from` 遇到大于接收缓冲区的数据报会返回 `WSAEMSGSIZE (10040)`，**该错误不是 `WouldBlock`/`TimedOut`，直接命中 `break`**。实测（临时端口 34771，`--listen-seconds 8`）：

```
RUN A: oversized 5000B datagram -> relay HasExited within 0.4s = True (elapsed 426 ms)
RUN A: exit code = 0
RUN A stderr: [!] recv_from failed: 一个在数据报套接字上发送的消息大于内部消息缓冲区或其他一些网络限制，
             或该用户用于接收数据报的缓冲区比数据报小。 (os error 10040)
RUN A stdout head: ... listening on 127.0.0.1:34771 for 8s | ... run time : 06:33:15.610 |
                   listen : 127.0.0.1:34771 for 0.8 s | datagrams : 0 | bytes in : 0
```

三点都值得记：

1. **服务在 1 个报文后停止**（8 秒预算、0.8 秒退出），`recv_from` 的致命错误被降级成"正常收尾"，因为 `break` 之后照常写 summary 并走完 `main`（`main.rs:395-457`），**退出码 0**（`main.rs:452` 只在写 summary 失败时才 `exit 1`）。
2. 因此 `docs\F3B-…md:82` 的"信封解析对五类畸形输入都能拒绝并**继续服务**（一个坏包不会让 Relay 停止）"**在 >4096 字节输入下不成立**。
3. 更糟的是**证据自证了这一点却无人看见**：summary 里 `listen … for 0.8 s` 明显短于请求的 `--listen-seconds`，但脚本没有任何"运行时长 ≈ 请求时长"的断言。

修法（三选一，建议全做）：`buf` 提到 65535（UDP 上限，`main.rs:239`）；或在 `:261` 之前加一个 `e.kind() == io::ErrorKind::Other && raw_os_error() == Some(10040)` 的分支，计入新计数器 `oversize` 并 `continue`（与 `bad_envelope` 并列，summary 同步加一行）；**并且**把致命 `recv_from` 错误改为 `std::process::exit(3)`，不让它伪装成正常退出。

**偏差 C-6（低）：`payload_len` 与实际长度不等时静默丢弃尾部。** `parse()` 只检查 `buf.len() < HDR + payload_len`（`:102`），**不检查 `buf.len() > HDR + payload_len`**。若发送方声明 `payload_len=8` 却发了 200 字节，多出的 172 字节被**静默丢弃**且无计数。对"载荷 100% 原样"是安全的（转发的是声明的那 8 字节），但会掩盖发送方的帧边界错误。建议加 `if buf.len() != HDR + payload_len { return Err("length-mismatch") }` 并归入 `bad_envelope`。

**偏差 C-7（低）：`--listen-seconds` 的解析失败静默退化为 60。** `:162` `it.next().unwrap_or_default().parse().unwrap_or(60)`——`--listen-seconds abc` 会安静地变成 60 秒，与 `--listen` 的严格处理（`:153-159` 解析失败即 `exit 1`）不一致。

**偏差 C-8（低）：日志时间戳是 UTC 当日秒，但无时区标注。** `:37-51` `wallclock_stamp()` 用 `SystemTime::now().duration_since(UNIX_EPOCH) % 86_400`，输出 `06:28:07.110`，而证据目录名与机器本地时间是 `14:28:07`（Asia/Shanghai）。**同一份证据里两套时钟并存且无一处标注**，读者极易把 `06:28` 误读为本地时间、进而怀疑时间线造假。建议改为本地时间或加 `Z` 后缀并在 summary 的 notes 里注明。

**偏差 C-9（低）：文档 §4 第 3 条与源码不符，属叙事陈旧。** `docs\F3B-…md:75-76` 说"Relay 用 `<out-dir>/relay-log.txt` 拼路径；out-dir 不存在时直接报 `拒绝访问 (os error 5)` 退出。脚本用 `New-Item -Force` 先建目录即可"。但**当前 `main.rs:200` 已经有 `fs::create_dir_all(dir)`**，out-dir 不存在时 Relay 自己会建，不会报 os error 5。也就是说：这条"踩坑记录"描述的**不是本提交件的行为**——要么 Relay 后来自己补了 `create_dir_all`（则文档该说的是"已修进产品侧"），要么当时确实靠脚本兜、后来代码又改了没回头更新文档。无论哪种，**该条与交付源码不自洽**，应改写。

**偏差 C-10（极低）：`send_to` 的 `sent != n` 分支实际不可达。** UDP 不产生短写，`:362` 的 `Ok(sent) if sent == n` 与 `_ =>` 里的短写情形在 UDP 上不会出现；当前把"短写"与"真失败"合并进 `forward_fail`（`:381`）无实际问题，仅提示。

### C.6 C 节结论

**有条件通过。** §4 的六条铁律中，**不解密、不改载荷、不重传、不重排、一进最多一出**五条在代码里是**结构性成立**（不是靠测试兜出来的），§4.1 加密范围声明在代码/文档/运行输出三处一致——这是本提交件最扎实的部分。§5.3 的 `SO_REUSEADDR` 也未设置。偏差集中在两处：**`src_peer` 回退（与文档 §1 矛盾）** 与 **62056 无代码防护（与 F3-A 的 fail-closed 不一致）**；另有一个被实测证伪的**超长报文停服**问题（C-5，高）。§3.2 未被 Relay 实现，但与 §4.2 一致，仅文档标注需修正。

---

## D. 表述边界

### D.1 「证明」清单逐句核验（`docs\F3B-RELAY-FORWARD-20261114.md:80-85`）

| 文档原句 | 核验结果 | 判定 |
|---|---|---|
| "信封解析对**五类**畸形输入都能拒绝并继续服务（**一个坏包不会让 Relay 停止**）" | ① 五类只测了两类（`too-short`、`bad-magic`）；② **"一个坏包不会让 Relay 停止"被实测证伪**——5000B 数据报使进程 0.4s 内退出（见 C-5） | **不通过（夸大且已证伪）** |
| "`dst_peer` 路由、发送者反查重写、自投递丢弃、目的未知不发送，四条路径都按设计工作" | 四条路径确有证据（`forward seq=1/4`、`src_peer=101`、`self-drop seq=3`、`no-route seq=2`）。但"发送者反查重写"只在**已注册来源**下成立（C-2），措辞应加限定 | **有条件通过** |
| "载荷在**两个方向**上都**逐字节**不变（8B 与 120B 两种长度，头部十六进制与 FNV-1a 64 三方一致）" | **"两个方向"不成立。** 全部 4 个数据帧都从 `peerA` 发出（脚本 `:219-228`），`peerB` **一次都没有发送过任何帧**（`$peerB` 只用于 `Receive`）。证据里不存在 B→A 方向的任何一条记录。"逐字节"本身成立（FNV 三方比对），但只在**单方向**成立 | **不通过（方向性夸大）** |
| "Relay 全程未占用 62056，符合 H2 门槛" | 本次运行确实未占用（`bind-check.txt`）。但"符合 H2 门槛"是由**前置条件**（脚本要求 62056 空闲，`134-138`）推出，而非由代码保证（C-4）；二进制可被要求绑 62056 | **有条件通过（归因不当）** |

### D.2 「不证明」清单评估（`:87-93`）

现有 5 条（真实双机/部署/跨网/NAT；游戏侧行为；加密/身份/抗重放；时延；长稳）**方向正确、措辞克制**，尤其是"不证明时延：回环 RTT 与 0.5s 首窗预算无关"和"不证明长稳：单次运行约 3.5 秒"，这两条切中要害，说明作者清楚回环原型的边界。**予以肯定。**

**但有 4 项遗漏**，且遗漏的恰好是本提交件最薄弱的四处：

1. **不证明反向路径（房主→客户端）。** 这是设计 §4.2 第三句"响应路径对称"的直接对应项，而自检完全未覆盖。应当在"不证明"里显式写为"不证明响应/回程方向（本次只验证 A→B 单向转发）"，而不是在"证明"里写成"两个方向"。
2. **不证明超过 4096 字节或超过 1280 载荷上限的输入行为。** 这恰恰是 C-5 崩溃的所在。诚实的写法是"不证明超大报文/越界输入的行为（已知：>4096B 会使原型停机）"，而不是宣称"一个坏包不会让 Relay 停止"。
3. **不证明 `bad-version`、`payload-too-large`、`truncated` 三类拒绝路径**（只测了 `too-short`/`bad-magic`）。
4. **不证明多 Peer（≥3）并发、不证明同一地址多身份、不证明重排/乱序**。当前是 2 个 peer、2 条数据帧、70ms 间隔串行发送，**没有任何并发或乱序压力**。

### D.3 是否把本机回环写成联机验证？

**没有。** 这是本提交件在表述上最值得肯定的地方，证据充分：

- 标题 `# F3-B — Relay 转发原型（本机回环，非发布）`（`:1`）。
- 第 3 行"本文只描述本机回环原型，**不构成任何联机验证**，也不移动 Gate A/B"。
- `:41-42` "**没有接游戏。** 不注入 Civ6、不 bind 62056、不碰游戏 socket；所有收发都在本机回环的测试 socket 之间"。
- `:89-90` "不证明真实双机、真实 Relay 部署、跨网、公网 NAT 下的行为""**没有任何字节进入 Civ6 进程**"。
- `:44-45` "不是产品 Relay。单线程阻塞收包，无 Keepalive、无 DEGRADED/RECONNECTING 状态机、无跨网 RTT 数据"。
- `:49` "用两个普通 UDP socket **冒充**两个 Agent"。

**逐条核对设计 §5.1 的"本阶段不承诺"五条**（`:90-96`）：不证明真实双机 ✔、不证明 H2/R1（注入方式留 M0-B）✔、不冻结 wire format ✔、D4 探测模板语（本文未做 D4，故不涉及）✔、127.0.127.x 地址段（未涉及）✔。**未越界承诺，未移动 Gate。**

`docs\F3A-DIRECT-FORWARD-20261114.md` 作为上游参考，其边界写法（`:5` 证据标签"模拟数据面对端（本机回环）"、"不是真实双机、不是游戏进程内注入、不是联机验证"）**比 F3-B 更规范**——F3-B 缺少这类**醒目的证据标签行**，边界信息散落在正文与 §5，建议在文首补一行与 F3-A 对齐的标签。

### D.4 D 节结论

**不通过。** 原因不是"把回环写成联机"（这一点做得很好），而是**"证明"清单里有两句经不起核验**：①"一个坏包不会让 Relay 停止"——我实测 5000 字节即停服且退出码 0；②"载荷在**两个方向**上都逐字节不变"——证据里只有一个方向，`peerB` 从未发送。另有"五类畸形"称五实二、"符合 H2 门槛"归因于前置条件而非代码。这三处属于**把没做过的验证写成已做**，与"不证明"清单的克制形成明显反差，必须修。同时建议补齐 4 项遗漏的"不证明"，并在文首加证据标签行（对齐 F3-A）。

---

## E. 缺陷清单

严重度定义：**阻断**=推翻主结论或证据不可信；**高**=核心承诺被证伪/存在可被触发的停服缺陷；**中**=与设计或文档直接冲突、需在下一步之前处理；**低**=措辞、一致性、健壮性瑕疵。

### 阻断（0 项）

无。证据哈希链完整、三次 PASS 可复现、核心转发行为成立。

### 高（1 项）

**H-1｜超长数据报使 Relay 停服，且以退出码 0 静默收场**
- 位置：`civlink\relay\src\main.rs:239`（`buf` 4096）、`:254-265`（`break`）、`:395-457`（照常写 summary）、`:452`（仅写盘失败才 `exit 1`）
- 证据：实测 5000B 数据报 → `recv_from failed: … (os error 10040)` → 0.8s（请求 8s）后退出，`exit=0`，summary `datagrams: 0`
- 影响：使 `docs\F3B-…md:82` 的"一个坏包不会让 Relay 停止"**不成立**；且失败被伪装成正常收尾，任何上层监控都无法感知
- 修法：
  1. `buf` 改 `vec![0u8; 65_535]`（`:239`）；
  2. `:261` 前插入 `WSAEMSGSIZE` 分支，新增 `oversize` 计数并 `continue`，summary（`:411-421`）与 notes 同步加一行；
  3. 致命 `recv_from` 错误改为 `std::process::exit(3)`，不落 summary 或被落 summary 前先标记 `fatal=1`；
  4. 自检补 1 条断言：运行时长与 `--listen-seconds` 偏差 < 20%，以及 1 条"发送 5000B 后 Relay 仍在服务"。

### 中（4 项）

**M-1｜未注册来源时回退信任信封 `src_peer`，与文档 §1 直接矛盾**
- 位置：`civlink\relay\src\main.rs:322-326`（`unwrap_or(env.src_peer)`）vs `docs\F3B-RELAY-FORWARD-20261114.md:20`
- 证据：实测未注册的 C 以 `src_peer=777` 发帧，B 收到 `src_peer=777`
- 修法（二选一，必须做其一）：
  - 代码侧：未注册来源一律 `stats.no_sender += 1; continue;`（fail-closed，与 F3-A 风格一致），并同步 summary/对账恒等式；
  - 文档侧：把 `:20` 改为"**已注册来源按其地址反查**；**未注册来源回退到信封 `src_peer` 并在 summary 中以 `no_sender` 计数**"。
  - 推荐代码侧修正，因为 §4.2 的透明度承诺要求 Relay 不得替攻击者伪造发送者身份。

**M-2｜H2 门槛（不 bind 62056）无代码防护，且与 F3-A 的 fail-closed 不一致**
- 位置：`civlink\relay\src\main.rs:142`（默认值）、`:151-160`（`--listen` 无校验）、`:186`（直接 bind）
- 证据：实测 `--listen 127.0.0.1:62056` 成功绑定（`127.0.0.1:62056 pid=39372`）；源码中 `62056` 字面量命中 0 条
- 对照：`civlink\agent\src\main.rs:17`/`:27`/`:669` 为 fail-closed 拒绝
- 修法：`:186` 前插入
  ```rust
  if listen.port() == 62056 { eprintln!("[!] refusing to bind game data port 62056 (H2 rule)"); std::process::exit(2); }
  ```
  并在自检里加 1 条断言：以 `--listen 127.0.0.1:62056` 启动必须 `exit 2` 且未占用端口（负向测试）。若坚持不改代码，则必须把 `docs\F3B-…md:85` 改为"由脚本前置条件保证，二进制不校验"。

**M-3｜"载荷在两个方向上都逐字节不变"不成立（单方向证据）**
- 位置：`docs\F3B-RELAY-FORWARD-20261114.md:84`；对应脚本 `civlink\run-f3b-relay-selftest.ps1:219-228`（四帧全由 `$peerA` 发出）
- 证据：`$peerB` 全程只 `Receive`，无任何 `Send`；日志中 4 条 `forward` 全部 `src_peer=101`
- 修法：要么把 `:84` 改为"**A→B 单方向**逐字节不变"，要么在脚本里补一对 B→A 的往返帧（B 先 `REGISTER 202`，再向 `dst=101` 发 1 帧，A 侧断言收到且哈希一致），断言数 +3~4。推荐补测试——设计 §4.2 第三句"响应路径对称"目前**零覆盖**。

**M-4｜两条断言恒真、对账恒等式对丢包失明**
- 位置：`civlink\run-f3b-relay-selftest.ps1:139-140`（`Check … $true`）、`:310`（自洽恒等式）、`:311`（`registers >= 5`，设计值 8）
- 证据：`142419` 丢 1 条注册时 FAIL 6 项；改造后丢 1~3 条注册将全部 PASS
- 修法：
  1. `139/140`：把预检结果存变量后传入 `Check`，预检失败不 `exit 2` 而是先落 FAIL 再退；或删除这两条并把总数改写为 41；
  2. `310`：保留恒等式（它确实能抓计数器回归），**追加**一条对"发送侧已知总数"的断言（脚本自己发了 14 个报文：8 注册 + 4 数据 + 2 畸形），断言 `datagrams == 14`；
  3. `311`：改为 `registers -eq 8`，或在 `result.txt` 中显式打印"设计 8 / 实收 N / 丢失 8-N"，让损失可见。

### 低（6 项）

**L-1｜`Cargo.toml` 字节数错误且缺哈希**
- 位置：`docs\F3B-RELAY-FORWARD-20261114.md:100`
- 实测：文档 583 / 实际 479（差 104）；哈希栏为"见 cargo 构建输出"（cargo 不产出该哈希）
- 修法：改为 `479`，补 `93C7D4DA43D523693C83644234CBE95FBDD43EF120489031D50491E21B9614D1`

**L-2｜证据表缺 `stop.txt`，且 console/stderr 合并成一行**
- 位置：`docs\F3B-…md:107-114`（7 行 vs 目录 8 个文件）
- 修法：补 `stop.txt | 6 | A0B28CDF92E250A1A93294D91144A0F893D27197D56B39991CC421768794005F`；把 `relay-console.txt` 与 `relay-stderr.txt` 拆为两行各给哈希（两者内容相同，均为 BOM+CRLF 空输出，可在备注说明）

**L-3｜`§4 第 3 条`叙事与源码不自洽（out-dir 创建）**
- 位置：`docs\F3B-…md:75-76` vs `civlink\relay\src\main.rs:200`（`fs::create_dir_all`）
- 修法：改写为"Relay 侧已 `create_dir_all`（`main.rs:200`）；脚本仍保留 `New-Item -Force`（`:121`）作为双保险"

**L-4｜§7 把 `§3.2 出向键` 列为本文依据，易误解**
- 位置：`docs\F3B-…md:121-122`
- 修法：改为"§4.2（按 dstPeer 转发）；§3.2 四元组出向键属 Agent 侧（F3-A），本篇不涉及"

**L-5｜`parse()` 不校验 `payload_len` 与实际长度是否相等**
- 位置：`civlink\relay\src\main.rs:102`
- 影响：尾部多余字节被静默丢弃、无计数
- 修法：`if buf.len() != HDR + payload_len { return Err("length-mismatch"); }`

**L-6｜日志时间戳为 UTC 无标注；`peers` 一址多号反查不确定；`--listen-seconds` 容错不一致**
- 位置：`main.rs:37-51`（UTC 秒 % 86400，实测 `06:28` vs 本地 `14:28`）、`:290`（`max()` 别名行无注释，可造一址多号 → `:322-326` 的 HashMap 遍历顺序不确定）、`:162`（`parse().unwrap_or(60)` 静默容错，与 `:153-159` 严格处理不一致）
- 修法：日志改本地时间或加 `Z` 并在 notes 注明时区；删除 `:290` 或改 `BTreeMap` + 显式冲突计数；`:162` 解析失败即 `exit 1`

---

## F. 必须修正项（编号）

> 下列各项应在 F3-C 启动前完成；其中 1、2、3、4 与"表述真实性"直接相关，建议最先修。

1. **【H-1】** 修复超长数据报停服：`main.rs:239` 缓冲区提到 65535；`:261` 前加 `WSAEMSGSIZE` 分支计 `oversize` 并 `continue`；致命 `recv_from` 错误改 `exit 3`，禁止以 `exit 0` 伪装正常收尾；自检补"发送 5000B 后仍在服务"与"运行时长符合 `--listen-seconds`"两条断言。
2. **【D/表述】** 修改 `docs\F3B-…md:82`：删除"一个坏包不会让 Relay 停止"，或限定为"**header 合法的 ≤4096B 畸形包**"；并把"五类"改为"本轮实测 2 类（`too-short`/`bad-magic`），另 3 类未测"。
3. **【D/表述】** 修改 `docs\F3B-…md:84`：把"两个方向"改为"**A→B 单方向**"；或在脚本中补 B→A 往返测试后再说"双向"。
4. **【M-1】** 消除 `src_peer` 回退与文档 §1 的矛盾：推荐代码改为未注册来源 `no_sender` 计数并丢弃（`main.rs:322-326`），fail-closed。
5. **【M-2】** 给 62056 加代码级防护：`main.rs:186` 前拒绝 `listen.port() == 62056` 并 `exit 2`，与 F3-A 对齐；自检补负向断言。
6. **【M-3】** 把 `docs\F3B-…md:85`"符合 H2 门槛"改为"本次运行未占用 62056；代码级防护见 M-2 修正后"。
7. **【M-4】** 修断言：`run-f3b-relay-selftest.ps1:139-140` 去掉恒真；`:310` 追加"发送侧已知总数 == datagrams"；`:311` 改精确期望 8 或在 `result.txt` 显式打印丢失数。
8. **【A/L-1】** `docs\F3B-…md:100`：`Cargo.toml` 字节数 583→479，并补 SHA-256。
9. **【A/L-2】** `docs\F3B-…md:107-114`：补 `stop.txt` 行，拆分 console/stderr 为两行。
10. **【A】** `docs\F3B-…md:104-117`：把 `142256`/`142419`/`142718` 三个未点名目录写入文档，注明前两轮 FAIL 的 `result.txt` 首行，并说明 41→43 新增的 2 条断言是什么。
11. **【L-3】** `docs\F3B-…md:75-76` 关于 out-dir 的叙事与 `main.rs:200` 不自洽，改写。
12. **【L-4】** `docs\F3B-…md:121-122` 的 `§3.2 出向键` 标注改为"属 Agent 侧/F3-A"。

## G. 建议改进项（非必须）

1. **补三类未测的拒绝路径**：`bad-version`（`buf[4]=2`）、`payload-too-large`（`payload_len=1281`）、`truncated`（`payload_len=100` 但只发 60 字节）。三类各 1 发 1 断言，断言数 +3~6，可把"五类"做实。
2. **补 `unknown-flags` 路径**：发 `flags=0x02` 的 24B 帧，断言计入 `control frames` 且不出现在 `forward` 行。注意此举会让 `:310` 的恒等式失效（该帧只进 `control_frames`、不进 `forward requests`/`bad_envelope`），需同步把恒等式扩为 `datagrams == registers + forward requests + bad_envelope + other_control`。**这本身说明 `:310` 的恒等式是被测试输入"喂"出来的，不是普遍成立的关系——建议在文档里承认这一点。**
3. **补多 Peer 与并发**：3 个 peer、peer 间互发 10 帧、无 `Start-Sleep` 连续发送，断言各 peer 只收到属于自己的帧、总数对账、无重复。这能覆盖 `:290` 的 `max()` 别名隐患与 `:322-326` 的一址多号不确定性问题。
4. **120B 载荷补逐字节 `Compare-Object`**：现在只有 `len`（`:268`）+ FNV（`:269`），FNV 足够但"逐字节"声明（`docs\F3B-…md:84`）最好有直接比对支撑。
5. **接收上限从 4 提到 6**（`:244`），让"实际收到 N"在重复投递时完整可见。
6. **把 `--quiet` 路径与 stdout 打印路径都覆盖一次**：现在 `relay-console.txt` 是空文件（`--quiet`），`main.rs:445-447` 的 `print!` 分支未被任何断言覆盖。
7. **去掉或改造 `:290` 的 `max()` 别名行**：它无注释、无文档、产生一址多号，收益不明。
8. **给 summary 增加 `fatal` / `stop_reason` 字段**（`normal` / `stop-file` / `deadline` / `recv-error`），让"为什么退出"成为可断言的事实，而不是靠 `listen … for 3.5 s` 反推。
9. **文首补证据标签行**（对齐 F3-A `:5`）：`> 证据标签：模拟数据面对端（本机回环 127.0.0.1）；不是真实双机、不是游戏进程内注入、不是联机验证。`
10. **时区标注**：日志与 summary 的时间统一为本地时间并加 `+08:00`，或在 notes 注明"日志时间戳为 UTC"。

---

## 附录 A：复现命令与关键输出

### A.1 哈希重算

```powershell
Get-ChildItem -LiteralPath 'M0A\captures\F3B-relay-selftest-20261114-142803' -File |
  ForEach-Object { "{0,-20} {1,6}  {2}" -f $_.Name, $_.Length, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
```

```
bind-check.txt           24  D386A4E1EE3A12F7BAFF08FAC8CD1172A461C8FADFF7D6E1AEA5453785DCBF18
exit.txt                 12  01AD8A20D9C655F39D931C98ACC135EF2B5505ECCEE6B6845F1667FF01CAD1AE
relay-console.txt         5  F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295
relay-log.txt          1126  A11AD18EF8519FFC93CDB05311DDED218AAFE5E48CEE63AD83FDBC7A212C3176
relay-stderr.txt          5  F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295
relay-summary.txt      1015  2E5CB88757333709CEB24E94EAB4681FE4A0B8C20B99A580ED8F8AACA0BFEA57
result.txt              515  C02AF8C8CBEF783DB4D49248B01773F70AB7235C3E1CF57ACD5A130EE075C078
stop.txt                  6  A0B28CDF92E250A1A93294D91144A0F893D27197D56B39991CC421768794005F
```

### A.2 断言计数

```powershell
(Select-String -LiteralPath 'civlink\run-f3b-relay-selftest.ps1' -Pattern '^\s*Check ').Count
# => 43
```

### A.3 超长报文停服（H-1 复现）

```powershell
$exe = (Resolve-Path 'civlink\relay\target\release\civlink-relay.exe').Path
# 以 --listen 127.0.0.1:34771 --listen-seconds 8 启动，再发 5000B UDP 数据报
```

```
RUN A: oversized 5000B datagram -> relay HasExited within 0.4s = True (elapsed 426 ms)
RUN A: exit code = 0
RUN A stderr: [!] recv_from failed: 一个在数据报套接字上发送的消息大于内部消息缓冲区或其他一些网络限制，
             或该用户用于接收数据报的缓冲区比数据报小。 (os error 10040)
RUN A stdout: listen : 127.0.0.1:34771 for 0.8 s / datagrams : 0 / bytes in : 0
```

### A.4 62056 无防护（M-2 复现）

```powershell
# 62056 空闲确认：0 个端点
# 以 --listen 127.0.0.1:62056 --listen-seconds 3 启动
```

```
RUN B: --listen 127.0.0.1:62056 -> endpoints on 62056 = 1; still running = True
RUN B: relay DID bind 62056: 127.0.0.1:62056 pid=39372
```

### A.5 `src_peer` 回退（M-1 复现）

```
三个 socket：A 注册 101、B 注册 202、C **未注册**
C 以 CVLR 头 src_peer=777 dst=202 seq=11 发 8B 数据

TEST1 unregistered sender spoof: B got seq=11 src_peer=777 (envelope claimed 777) dst=202
      -> relay TRUSTED src_peer=True
```

### A.6 三次 PASS 的计数一致性

```
Compare-Object 142803/relay-summary.txt  142813/relay-summary.txt
  -> 仅 "run time : 06:28:07.110" / "listen … for 3.5 s" 两行差异，其余全部计数逐字相同
```

---

## 附录 B：审计范围与限制

- **未修改任何文件**（除本报告 `docs\F3B-REVIEW.md`）。为验证行为启动的 Relay 实例全部使用 34771/34781 等临时端口，均未写入 `M0A\captures`，不产生新证据目录。
- **未重新编译**。`D:\rustup\toolchains\1.75.0-x86_64-pc-windows-msvc\bin\rustc.exe` 存在，`target\.rustc_info.json` 记录 `rustc 1.75.0 (82e1608df 2023-12-21) x86_64-pc-windows-msvc`，与文档"可 `cargo +1.75.0 build --release --offline` 构建"一致；`target\release\civlink-relay.d` 表明产物仅依赖 `src\main.rs`。**未做从源码到 exe 的可复现构建比对**（审计只读约束），因此"exe 由该 main.rs 编译而来"是**强旁证**（`.d` 依赖表 + 字符串表 + 哈希与 `result.txt` 自记值一致），非**密码学证明**。
- 该目录**不是 git 仓库**（`Test-Path .git` = False），因此无提交历史可核，provenance 完全依赖哈希与 mtime。mtime 序列自洽：`Cargo.toml 14:21:07` → `main.rs 14:21:29` → `exe 14:22:05` → `脚本 14:27:56` → `首次 PASS 证据 14:28:03`。
- 未审计 F3-C/D/E（文档 §8 自述均未开始），未审计 `civlink\agent` 侧的 F3-A 实现细节（仅在 C-4 中引用其 62056 fail-closed 作为一致性对照）。
- 未运行 `run-f3b-relay-selftest.ps1` 全量（会写入 `M0A\captures` 并产生新证据目录，违反只读约束）。对其结论的采信依据是：脚本源码逐行审读 + 三次既有 PASS 证据的哈希与内容复核 + 对同一 exe 的独立行为探测（A.3/A.4/A.5）。三者相互印证，未发现证据与脚本行为不符之处。
