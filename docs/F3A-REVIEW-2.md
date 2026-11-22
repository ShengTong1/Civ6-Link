# F3-A 直连转发原型 · 第二轮复审（整改后）报告

> 审计对象：`civlink\agent\src\main.rs`、`civlink\run-f3a-forward-selftest.ps1`、`M0A\captures\F3A-forward-selftest-*`、`civlink\civlink-agent.exe`
> 审计依据：`docs\F3-DIRECT-RELAY-DESIGN-20261114.md` v0.3 §3.2 / §4.1 / §4.2 / §4.3 / §5.1 / §5.2 / §5.3
> 上一轮：`docs\F3A-REVIEW.md`（有条件通过，7 项必改）
> 审计日期：2026-11-14 14:41–14:58（本机 UTC+8）
> 审计性质：**只读**。除本文件外未创建/修改任何文件。

---

## 0. 总评

### **不通过（FAIL）**

**一句话理由**：代码与证据相对上一轮有实质改进（①②④ 三项硬性必改确实做到了，且证据可被独立复算），但**交付记录 `docs\F3A-DIRECT-FORWARD-20261114.md` 一个字节都没改**——它仍以整改前的运行 `F3A-forward-selftest-20261114-142008` 和整改前的 9 个旧哈希自称 "PASS / 17/17"，而那个旧运行用**现行**判据离线重放会有 6 条不成立；⑥⑦ 两项必改因此整项未关闭，⑤ 仅部分关闭，"整改完成"这一主张不成立。

**分项计数**

| 严重度 | 数量 |
|---|---:|
| 阻断 | 1 |
| 高 | 2 |
| 中 | 9 |
| 低 | 8 |
| **合计** | **20** |

**第一轮 7 项必改关闭情况**：关闭 3 项（①、②、④）｜未关闭 4 项（③、⑤、⑥、⑦；其中 ⑤ 为"部分完成"）。

**如果只看代码与证据**：F3-A 的机制成立、载荷原样首次有真正证据、D2 入口三处 fail-closed、exe↔main.rs 的对应关系本轮已能给出强论证。**F3-A 本身可以判通过**；不通过的是"整改交付物"——记录未回写、两个测试缺口未补、三处表述未收紧。补齐本报告 §6 的 B1/H1/H2 + M2/M3 即可转为"通过"（纯文本 + 两个单测，工作量很小）。

---

## 1. 审计方法与边界

| 项 | 说明 |
|---|---|
| 读取 | 全量读 `main.rs`（2174 行）、`run-f3a-forward-selftest.ps1`（313 行）、设计 v0.3（127 行）、记录（75 行）、一审报告（469 行）、6 个证据目录全部文件 |
| 复算 | `Get-FileHash -Algorithm SHA256` 逐文件；`[System.Security.Cryptography.SHA256]` 独立复算 3 个载荷摘要 |
| 断言重放 | 按脚本现行 27 个 `Check` 站点、23 条**数据类**断言，对 3 个证据目录做离线重放（不重跑脚本，避免写盘） |
| 行为验证 | 直接运行交付 `civlink-agent.exe` 的 `--help` 与 3 个 62056 负向用例（不写 `--out-dir`，无落盘） |
| 构建对照 | 用 `rust-version = "1.75"`（`cargo +1.75.0`）与默认 1.99.1 两套工具链在 `%TEMP%\f3a-audit-build175` 重建，与交付 exe 做**逐字节 + 逐 PE 段 + 字符串表**对照。重建输出未写入被审仓库：审计结束时 `civlink\agent\target\release\civlink-agent.exe` 仍是 `563122E2…` / mtime 14:40:44，与交付 exe 同一哈希 |
| 未做 | 不反编译、不动游戏进程、不注入、不做真实双机、不评审 F3-B/C/D/E |

**关于"exe 与 main.rs 对应关系"的方法学说明**：Rust 默认构建不可逐字节复现（PDB 路径、时间戳进入产物），因此本轮**不以"重建哈希相等"为证据**，改用三重合证：①字符串表全等；②PE 段级差异定位到唯一原因（PDB 路径长度差）；③行为级（三个负向用例的 stderr 文案逐一命中源码字面量）。结论见 §2.4。

---

## 2. A. 证据真实性

### 2.1 PASS 运行 `F3A-forward-selftest-20261114-144121`（主证据，10 个文件）

| 文件 | 字节 | SHA-256（本轮 `Get-FileHash` 实测） |
|---|---:|---|
| `summary.txt` | 3,227 | `F707CD107447C6C1B967E43EDD3FE20034C03C722C2DEC791EFE8B086052172D` |
| `forward-log.txt` | 1,165 | `1F1F387505D701638D70A59D180970914CC524DA1BDE5B872FC9D633A958522B` |
| `frame-log.txt` | 788 | `C72A1BF6782227DB40E095C9A42469ECCA1655098FB943C83E5EAD16A3F594C1` |
| `datapath-log.txt` | 583 | `288D98379FBF9B75B99F80325F7E46ECE7A57EAF7E0AA09F34762D5CB5516A58` |
| `bind-check.txt` | 48 | `D956588DA05DA4158BA6FEC0B42D0762AD56EA0987156342C5AFEEACCD8CC76A` |
| `negative-cases.txt` | 387 | `3FB5A8B2D1126227D56B8940E34CFC6ECF5EDCEA933B98157A4A9123F93621E8` |
| `exit.txt` | 17 | `81DDBAF9EED6926436F584FADECA0FBBE6DF4B4E6A47F318AF3A728A6574385A` |
| `agent-console.txt` | 5 | `F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295` |
| `agent-stderr.txt` | 5 | `F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295` |
| `stop` | 0 | `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855` |

- `agent-console.txt` / `agent-stderr.txt` 的 5 字节实测为 `EF BB BF 0D 0A`（BOM + 空行），与脚本 `--quiet` 启动方式一致，不是"输出被吞"。
- **记录中没有任何一处引用这 10 个哈希**（见 §2.5）。

### 2.2 失败运行 `F3A-forward-selftest-20261114-144051`（必须披露，本轮已审）

| 文件 | 字节 | SHA-256 |
|---|---:|---|
| `summary.txt` | 3,227 | `A74984162A15C48ED069C023EC36DA2CFBCFA482FB1B4EF11AAEB0E0DBE09496` |
| `forward-log.txt` | 1,165 | `D6049176802B4C70ED084F903B9037DAD77B07491CF7FA53DCD078FF48E1A05C` |
| `frame-log.txt` | 788 | `14B78ACF322CD92FBDA98983D8A928B39476C792FF3FF321ED38A0060AD7FC21` |
| `datapath-log.txt` | 583 | `99E7054D44F5D1552F550451F41D141013E155C175FC12C80462BA7A6226FCCA` |
| `bind-check.txt` | 48 | `CCDB8FE88268FC2C1212963E885DFAAB70CCA2AFC22BF9A9401EABA1A26D29EC` |
| `negative-cases.txt` | 387 | `3FB5A8B2D1126227D56B8940E34CFC6ECF5EDCEA933B98157A4A9123F93621E8`（与 PASS 运行**字节相同**） |
| `exit.txt` | 17 | `81DDBAF9EED6926436F584FADECA0FBBE6DF4B4E6A47F318AF3A728A6574385A`（内容 `agent exit=0`） |
| `agent-console.txt` / `agent-stderr.txt` | 5 | `F01A374E9C81E3DB…`（与 PASS 运行同） |
| `stop` | 0 | `E3B0C442…` |

**对 144051 的如实结论（三条，缺一不可）**：

1. **Agent 侧完全成功**：`exit.txt` = `agent exit=0`；`summary.txt` 与 144121 的差异**只有** `run time`（06:40:55.070 vs 06:41:25.074）、`listen window … 2.4 s` vs `2.3 s`、`forward sock 0.0.0.0:58298` vs `0.0.0.0:51286`、`first/last sender` 对应端口、pid（35364 vs 30056）、F2 探测临时端口（58297 vs 51285）以及日志时间戳。**所有业务计数逐字相同**（`datagrams 5` / `forwarded 3` / `forward bytes 136` / `skip not datapath 1` / `skip key table 0` / `mappings created 1` / `payloads recv 3` / `payload bytes 136`）。
2. **失败只可能发生在驱动脚本的某条断言上**，而**脚本自身 stdout 从不落盘**（无 `Tee-Object`、无 `Start-Transcript`、无 `selftest-console.txt`），证据目录里只有 Agent 的 10 个产物 → **失败原因无法从证据复原**。
3. **本轮离线重放：144051 在现行 23 条数据断言下 0 失败**（与 144121 同为 23/23）。原因是**脚本在两次运行之间被改过**：`run-f3a-forward-selftest.ps1` 的 mtime 是 **14:41:15**，恰好落在 144051 目录创建（14:40:55）与 144121 目录创建（14:41:25）之间；仓库内只有这一份脚本（`civlink\` 下无 `run-f3a*.bak-*`，对比 F3-B 存在 `run-f3b-relay-selftest.ps1.bak-16630`）→ **改前版本未留档，那次失败的"修法"不可见、不可复核**。

> 结论：144051 是一条**真实存在但不可审计**的失败运行。把它写进记录是义务，但仅"披露"不足以消除它带来的证据链断点——必须同时说明"改了什么、为什么改"。

### 2.3 summary / forward-log / frame-log / negative-cases 的内部一致性（逐项核算）

| 核对项 | 计算 | 结论 |
|---|---|---|
| 输入帧数 | `frame-log.txt` 5 行（seq 1..5） | ✓ |
| `datagrams 5` == `received frames 5` == `processed 5 + rejected 0` | 5 = 5 = 5+0 | ✓ 满足 §4.3 reconciliation |
| `payload bytes 144` | 8+8+4+4+120 = 144 | ✓ |
| `forward frames seen 4` | 5 帧 − 1 发现帧（seq3 dst=62905）= 4 | ✓（但发现帧计入哪个计数器见 M9） |
| `forwarded 3` / `forward bytes 136` | 8+8+120 = 136；frame-log 中 dst=62056 的帧恰为 seq1/2/5 | ✓ |
| `skip not datapath 1` | frame-log 中非 62056 且非发现 = seq4（50999） | ✓ |
| `skip key table 0` / `mappings created 1` | 3 个 62056 帧共享同一 `(session, sock, gen, dst)` | ✓ |
| `payloads recv 3` / `payload bytes 136` | forward-log 3 条 `peer-recv` | ✓ 一帧一投，无重传 |
| `forward fail 0` | 3 条 forward 行均成功 | ✓ |
| `target 127.0.0.1:21346` 且非 62056 | 3 条 forward 行 `-> 127.0.0.1:21346` | ✓ D2 红线 |
| 发现帧未转发 | forward-log 无 `seq=3`，且无任何 `dst=…:62905` 目标 | ✓ |
| `bind-check` 48B | `agent pid=30056 udp:62056 owned by agent: 0` | ✓（强度见 §3 表 `:165`） |
| `negative-cases.txt` 3 行 | 三行 `exit=1`，三句 stderr **互不相同**，含 `must not be 62056` / `must not be 62056` / `must not target port 62056` | ✓ |
| 时间戳序号 | forward/peer-recv 行严格递增，无倒序 | ✓ |

**未发现任何算术矛盾、拼装痕迹或二次编辑痕迹。** 证据是真实的。

### 2.4 `civlink-agent.exe` 与 `main.rs` 的对应关系（本轮新增的强论证）

| 检查 | 结果 |
|---|---|
| 交付 exe 身份 | **381,440 B**，`563122E2AC8C6C8966AEBAFB0831FDC734E98955A21F46F3D4FEC7269E5D1C0C`，mtime 14:40:44 —— **与任务书给的目标值完全一致** |
| `main.rs` 身份 | **88,703 B**，`2596BADE8B2C2DF403580B6146B06E8344157EB41460B56AE19CB64E2DC98FDE`，2174 行，mtime 14:39:44（**早于 exe 60 秒**，时序自洽） |
| 仓库内构建产物 | `civlink\agent\target\release\civlink-agent.exe` 与 `deps\civlink_agent.exe` **同为 `563122E2…` / 381,440 B / 14:40:44** → 交付 exe 就是该树内构建产物，不是外来文件 |
| 依赖清单 | `target\release\civlink-agent.d` 只列 **`…\agent\src\main.rs`** 一个源文件 → 产物由该文件直接编译 |
| **1.75.0 重建**（`Cargo.toml` 声明 `rust-version = "1.75"`） | 381,440 B / `91528BBFCCC6252952CC84F375BED3C7220BA7C15BAE2A68E4286A14A4A6505B` —— **字节数与交付 exe 完全相同** |
| 1.99.1 重建 | 375,296 B / `D27C3F55…`（工具链不同，尺寸不同，无关） |
| 1.75.0 重建 vs 交付 exe 的段级差异 | `.text` **6 B**（0x04393D/0x04393E/0x043944/0x043945/0x04398D/0x043994，均为 1–2 B 立即数/RIP 位移）· `.rdata` 23,694 B · `.data` **0** · `.pdata` 931 B · `.reloc` **0** · PE 头 4 B |
| 差异归因 | ①字符串表**两边都是 1,093 条、逐条相同，唯一差异是内嵌 PDB 路径**：`…\AppData\Local\Temp\f3a-audit-build175\release\deps\civlink_agent.pdb` vs `…\civlink\agent\target\release\deps\civlink_agent.pdb`（长度差 25 字符）②`.pdata` 853/854 条 `BeginAddress` **位移全为 0**，`UnwindInfo` 指针**一致 +0x18**（24 字节）→ 与 PDB 路径变长导致的 `.rdata` 后移一致 ③PE `TimeDateStamp` 差 0x21A = 538 秒（约 9 分钟，符合"先构建再审计"）④`.text` 的 6 字节差异正好是引用该 `.rdata` 段的 RIP 位移 |
| 行为级 | 实跑交付 exe：`--port 62056` → exit=1，stderr `[!] --port must not be 62056: the Agent never binds the game's data-plane port`；`--forward-listen 62056` → exit=1 同形；`--forward-to 127.0.0.1:62056` → exit=1，`[!] --forward-to must not target port 62056: the Agent never sends to the game's data-plane port`。三句与 `main.rs:1017-1021` / `1085-1089` / `1074-1078` 的 `format!` 逐字对应 |
| 字符串级 | exe 内可检出 `forward sock`、`skip key table`、`skip not datapath`、`first sender`、`peer-recv n=`、`forward seq=`、`sha256=`、`no mapping: key table full`、`forward FAILED`、`sender identity the peer sees`、`mappings created`、`not the 62056 datapath`、`--port must not be `、`--forward-listen must not be `、`--forward-to must not target port `、`the Agent never binds the game`、`the Agent never sends to the game` |

**判定：exe ↔ main.rs 对应关系成立，且强度高于上一轮。** 1.75.0 重建与交付 exe 只差"构建目录路径"这一个变量，`.data`/`.reloc` 零差异、字符串表全等、`.text` 仅 6 字节 RIP 位移。

**但必须写明的限制**：这仍是**同机重建+归因**，不是 reproducible build 证明；记录里**没有任何构建命令、工具链版本、目标目录**留痕（`docs\F3A-DIRECT-FORWARD-20261114.md` §4 只有 9 行哈希）。上一轮附录 B 第 3 条提的"需 reproducible build 或构建留痕"，本轮**仍未做**。

### 2.5 记录文档的身份：**没有跟上整改**

| 检查 | 实测 |
|---|---|
| `docs\F3A-DIRECT-FORWARD-20261114.md` mtime | **14:20:33** —— 早于 `main.rs`(14:39:44)、exe(14:40:44)、ps1(14:41:15)、两个新证据目录(14:40/14:41) |
| grep 新值 | `563122E2` / `381,440` / `2596BADE` / `88,703` / `15393` / `59F2390A` 在 `docs\*.md` 中 **0 命中** |
| §4 文件身份表（`:56-64`） | 9 行**全为整改前旧值**：main.rs 76,311 / `225FF752…`；exe 372,224 / `AF6B4568…`；ps1 10,198 / `0151270D…`；summary 3,058 / `EE52C6E1…`；forward-log 733 / `65C5BF6D…`；frame-log 788 / `D7175B1A…`；datapath-log 583 / `C91FCF01…`；bind-check 48 / `8AA463B6…` |
| 这 9 个哈希指向谁 | **逐个命中 `F3A-forward-selftest-20261114-142008`**（3,058B / `EE52C6E1…`；733B / `65C5BF6D…`；788B / `D7175B1A…`；583B / `C91FCF01…`；48B / `8AA463B6…`）→ 记录描述的是**整改前的产物** |
| §3 证据目录（`:43`） | 明写 `F3A-forward-selftest-20261114-142008` |
| 用现行断言重放 142008 | **6 条不成立**：`skip not datapath == 1`（旧产物无该字段，只有 `no mapping 1`）、`skip key table == 0`（无该字段）、identity binding（无 `forward sock` / `first sender`）、`forward-log 有 3 条 sha256`、`peer-recv 有 3 条 sha256`、`peer 摘要集合 == 期望集合` |
| §4 缺失的过程文件 | 无 `exit.txt`、`agent-console.txt`、`agent-stderr.txt`、`negative-cases.txt`、`stop` 五行（上一轮 L6 明确要求补） |

> **A 节结论**：**证据真实性：通过（10/10 哈希实测一致，且内部自洽、可独立复算 payload 摘要在内）**。
> **但"记录 ↔ 证据"的绑定：不成立**——记录引用的是一份在现行判据下达不到标的历史产物。

---

## 3. B. 断言强度

### 3.1 断言计数：三个数字互不相同，且都不对

| 出处 | 声称 |
|---|---|
| 任务书 | "37 条断言" |
| 记录 `docs\F3A-DIRECT-FORWARD-20261114.md:37` / `:41` | "断言 17 项" / "17/17 断言通过" |
| 脚本实际 | `Select-String '^\s*Check '` = **27 个站点**；其中 `:117`/`:118` 在 `foreach ($case in $negCases)`（3 个用例）内 → **运行时执行 31 次** |

`grep docs\*.md '37'` **0 命中**——"37"在仓库里没有来源，属任务书侧的口径错误；记录的"17"是整改前的数；脚本本身没写数量。**三个数字没有一个是 31。**

### 3.2 逐条强度评级（27 站点 / 31 次执行）

图例：**强** = 断言语义可被反例推翻且绑定到具体数值/字面；**中** = 可推翻但存在取值时机或比较口径的松口；**弱** = 可推翻但几乎不携带信息；**恒真** = 在固定命令/固定拓扑下**不可证伪**。

| # | 行 | 断言 | 评级 | 理由 |
|---:|---|---|---|---|
| 1 | `:117`×3 | 负向用例 `exit 1` | 中 | 值绑定；但 `$code = $np.ExitCode` 在 `:115` 取，而 `:114` 可能刚 `Kill()` 过，超时路径下取值不可靠 |
| 2 | `:118`×3 | `$npErr -match '62056'` | **弱** | 只匹配"62056"这几个字符。`--port 62056` 的参数回显、任何含该数字的其他报错都能通过。应改为 `-match 'must not be 62056'` / `-match 'must not target port 62056'`，并按用例分别匹配 |
| 3 | `:165` | agent 不持有 UDP 62056 | **弱（近恒真）** | 见 §3.3 |
| 4 | `:213` | `exit 0` | 强 | |
| 5 | `:244` | `frames seen == 4` | 强 | |
| 6 | `:245` | `forwarded == 3` | 强 | |
| 7 | `:246` | `forward bytes == 136` | 强 | 8+8+120，能抓"少字节/多字节" |
| 8 | `:247` | `forward fail == 0` | 中 | 0 是默认值；但代码只在失败时 `+1`，故仍是"未失败"的可用证据 |
| 9 | `:248` | `skip not datapath == 1` | 强 | |
| 10 | `:249` | `skip key table == 0` | **恒真/零信息** | 见 §3.4 |
| 11 | `:250` | `mappings created == 1` | 强 | |
| 12 | `:251` | `payloads recv == 3` | 强 | |
| 13 | `:252` | `payload bytes == 136` | 强 | |
| 14 | `:253` | `listen port == 21346` | 强 | |
| 15 | `:254` | `target == 127.0.0.1:21346` | 强 | |
| 16 | `:255` | `summary -match 'LOOPBACK PROTOTYPE'` | **弱** | 只要出现这一个词就过。应同时匹配 `NOT a real-machine result`、`no real player join`、`never binds :62056` 等 §5.1 边界语中的至少两条 |
| 17 | `:264` | peer `first sender` 端口 == `forward sock` 端口 | **弱（同源自证）** | 见 §3.5 |
| 18 | `:275` | forward-log 3 条 forward 行 | 强 | |
| 19 | `:276` | 3 条 peer-recv 行 | 强 | |
| 20 | `:277` | 1 条 skip 行 | 强 | |
| 21 | `:278` | `$fwdLines` 不含 `dst=…:629xx` | **恒真（空域）** | 见 §3.6 |
| 22 | `:279` | `$fwdLines` 不含 `-> …:62056` | **强** | 这是真正的 D2 红线断言；若转发目标写成 62056，立刻失败 |
| 23 | `:294` | 3 条 forward 摘要 | 强 | |
| 24 | `:295` | 3 条 peer 摘要 | 强 | |
| 25 | `:296` | forward 摘要集合 == peer 摘要集合 | 中强 | 排序后比**集合**，不比**配对**：seq1 与 seq2 的摘要互换（串包）仍会通过。应改为按 seq 逐条配对 |
| 26 | `:300` | peer 摘要集合 == 脚本自算的期望集合 | **最强** | 唯一真正的外部锚点：`.NET SHA256` 独立计算，120 B 全覆盖。**上一轮 M3 的实质修复就靠这一条** |
| 27 | `:303` | `len=8` 且 `payload=17320000` 的行有 2 条 | 弱 | 只查前 4 字节；在已有 #26 之后属冗余 |

**计数**：强 **17**、中强/中 **3**（#1/#8/#25，另 #26 为"最强"归入强）、弱 **5**（#2/#3/#16/#17/#27）、恒真 **2**（#10/#21）。

### 3.3 `:165`「agent 不持有 UDP 62056」为什么接近恒真

- 脚本用**固定命令行**启动 Agent：`--port` 未给（默认 34718）、`--forward-listen 21346`、`--bind-ip 127.0.0.1`。在这组参数下，代码里 5 个 `UdpSocket::bind` 点（`main.rs:398`、`533`、`669`、`795`、`1126`）**没有一条能落到 62056**：主 listen 用 `127.0.0.1:34718`（`main.rs:1126`），listener 用 `127.0.0.1:21346`（`main.rs:795`），转发/回包用 `0.0.0.0:0`（`main.rs:533`/`669`）。
- 因此这条断言实际只在复述"默认端口是 34718"，**不是**在检验 D2 红线的实现。
- **且完全不检验 §5.3 的后半句"不得设 SO_REUSEADDR"**——脚本层没有任何手段查 `SO_REUSEADDR`（它是 socket 创建参数，不体现在 `Get-NetUDPEndpoint` 输出里）。目前该约束只有源码侧证据：`main.rs` 全文无 `reuse` 调用（只有 `:28`、`:498` 两条注释提到 "never sets SO_REUSEADDR"）。
- 环境事实：本轮实测本机 **`CivilizationVI_DX12` 正在运行（pid 44828）但 `Get-NetUDPEndpoint -LocalPort 62056` 返回 0 个端点** —— 即游戏未处于联机局，62056 无人占用。这使 `:165` 在任何情况下都会通过。

### 3.4 `:249`「skip key table == 0」为什么是零信息量

断言全名是 `'skip key table == 0 (the mapping existed before the cap)'`，但脚本只造 **1 个** 映射键（3 个 62056 帧共享 `(session=1, sock=1, gen=1, dst=127.0.0.1:62056)`），而 `MAX_FORWARD_KEYS = 64`（`main.rs:647`）。**表满分支在该拓扑下永不可能触发**，所以这条断言永远为 0，它证明不了任何一个设计分支的"存在性"。

诚实的做法二选一：①在脚本里加一段高基数用例（>64 个不同 `(sock,gen,dst)` 的 62056 帧，断言 `skip key table == N-64` 且 `forwarded` 不再增长）；②删除该断言，并在记录里写明"表满分支由单测 `forward_key_table_full_refuses_to_forward` 覆盖"。

（该分支的**单测**是真实有效的，见 §4 `:2120-2142`；差的是端到端侧的同名断言。）

### 3.5 `:264` identity binding 为什么是同源自证

```powershell
$fwSockPort  <- Grab $summary 'forward sock\s+:\s+(\S+) \(sender identity'
$seenPort    <- Grab $summary 'first sender\s+:\s+(\S+)'
Check 'peer first sender is the forwarder socket (port match)' ($fwSockPort -eq $seenPort)
```

三重削弱：

1. **只比端口，不比 IP**。实测 `forward sock = 0.0.0.0:51286`、`first sender = 127.0.0.1:51286`，IP 本来就不同（`0.0.0.0` 是绑定地址，`127.0.0.1` 是路由选择后的源地址），所以"比 IP"确实不能比——但这一事实**恰好说明这条断言只在不重叠的维度上做了配对**。
2. **两个字段来自同一份 `summary.txt`、由同一个 Agent 进程、在同一次 `run()` 里写出**。若转发根本没发生、而 listener 从环回任何地方收到一个端口号巧合相同的报文，这条断言照样通过。
3. **真正的外部锚点在 `forward-log.txt`**：`peer-recv n=1 from=127.0.0.1:51286` 是**对端 socket 收到的字节**（`main.rs:805-818` 用 `recv_from` 的 `from` 直接写入），它与 `summary` 的 `forward sock` 分属两个不同的数据来源。**脚本没有做这个跨文件比对**；本轮我手工核对了 144121：`forward sock 0.0.0.0:51286` ↔ `peer-recv from=127.0.0.1:51286`，**端口一致**（结论成立，只是断言没写）。

### 3.6 `:278` 为什么是空域恒真

```powershell
$fwdLines = @($logged | Where-Object { $_ -match ' forward seq=' })
Check 'forward-log never forwards a discovery port' (-not ($fwdLines -match 'dst=[\d.]+:629\d\d'))
```

`forward seq=` 这一行**只可能由 `dst_port == 62056` 的帧产生**——`main.rs:711` 在任何 `dst != 62056` 的帧上先 `return`，`:744` 的日志行根本到不了。所以 `$fwdLines` 的定义域里**不存在** 629xx，断言恒真。

它检验的是"forward 行的文本里没有出现 629xx"，而**不是**"发现帧没有被转发"。要测后者，应断言"`forward-log.txt` 的全部行（含 `peer-recv`）中不存在 `seq=3`"，或"peer-recv 的行数 == forwarded 的数 == 3"（后者已有 #19，所以 #21 实际是 #19 的弱化重复）。

### 3.7 断言"能失败"的反向验证（本轮新增）

为排除"整组断言是否只是摆设"，我用**现行 23 条数据断言**对三个目录做了离线重放：

| 目录 | 结果 |
|---|---|
| `…-144121`（PASS 运行） | **23/23 通过，0 失败** |
| `…-144051`（失败运行） | **23/23 通过，0 失败**（→ 见 §2.2 第 3 点） |
| `…-142008`（记录引用的旧运行） | **6 条失败**：`skip not datapath==1`、`skip key table==0`、identity（无 `forward sock`）、`forward 摘要数 3`、`peer 摘要数 3`、`peer 摘要集合==期望集合` |

**这是好消息**：断言组不是恒真的摆设，旧产物确实会被判 FAIL；**这也是坏消息**：记录拿的正是那个会被判 FAIL 的旧产物当 PASS 证据（§2.5）。

### 3.8 B 节结论

**断言强度：中偏弱，但"关键三条"是真的。**

- 真正撑住 F3-A 命题的是 **`:300`（摘要三向对账）+ `:279`（转发目标非 62056）+ `:246`/`:252`（字节数）** 这一组，它们确实可被反例推翻。
- **1 条恒真（`:278`）、1 条零信息（`:249`）、1 条近恒真（`:165`）、3 条弱（`:118`/`:255`/`:303`）、1 条同源自证（`:264`）**——与上一轮相比：上一轮的"#18 只验前 4 字节"已被 `:300` 实质替代（这是真改进），但**恒真/弱断言的数量没有减少**（上一轮一审数出 1 恒真 + 1 空集恒真 + 3 弱，本轮为 2 恒真 + 6 弱/零信息），只是换了一批位置。

---

## 4. C. 代码与设计一致性

### 4.1 `sha256_hex` 的 FIPS 180-4 正确性（`main.rs:81-159`）

逐项核对，**实现正确**：

| 检查项 | 结果 |
|---|---|
| K 表 64 个常量 | 与 FIPS 180-4 §4.2.2 逐值一致 |
| 初始哈希 h0..h7 | `6a09e667` `bb67ae85` `3c6ef372` `a54ff53a` `510e527f` `9b05688c` `1f83d9ab` `5be0cd19` ✓ |
| 填充 | `push(0x80)` + 补 0 至 `len % 64 == 56` + `(len*8).to_be_bytes()` ✓ |
| `Σ0` / `Σ1` | `ror(2)^ror(13)^ror(22)` / `ror(6)^ror(11)^ror(25)` ✓ |
| `σ0` / `σ1` | `w[i-15].ror(7)^ror(18)^(>>3)` / `w[i-2].ror(17)^ror(19)^(>>10)` ✓ |
| `Ch` / `Maj` | `(e&f)^((!e)&g)` / `(a&b)^(a&c)^(b&c)` ✓ |
| 溢出 | 全部 `wrapping_add` ✓ |
| 输出 | `format!("{v:08x}")` × 8 → 64 位小写 hex ✓（与证据中 `sha256=` 的小写一致） |
| 独立复算交叉验证 | `.NET SHA256` 复算 `p1`/`p2`/`p3` 得 `5a36d008…951f` / `c793bc05…a515` / `1ea7bb62…10fe`，与 144121 `forward-log.txt` 三行**逐字相同** → 手写实现在 8B 与 120B 两条路径上都正确 |

唯一非缺陷的瑕疵：`let mut msg = data.to_vec()` 每次调用复制整段（载荷上限 `MAX_PAYLOAD = 1280`，成本可忽略）。

### 4.2 逐条对照设计 §3.2 / §5.3

| 设计条款（v0.3 原文） | 代码位置 | 判定 |
|---|---|---|
| §3.2 步1：`WSASendTo(房主:62056)` → Hook → CVLH2 → Agent | `main.rs:1281` `decode` → `:1283` `received += 1` | **一致** |
| §3.2 步2：键 `(session_id, logical_socket_id, socket_generation, dst)` | `main.rs:649-655` `ForwardMapKey { session_id: u64, logical_socket_id: u32, socket_generation: u32, dst_ip_be: u32, dst_port_be: u16 }` | **等价一致**（把 `dst` 拆成 ip+port 两字段，语义相同，且与 `civlink-fakeip` 的 crate 形状可对映） |
| §3.2 步2：命中 → 向**唯一目标**（对端 Agent 转发端口，**不是**房主 62056）发原始载荷 | `main.rs:737` `self.sock.send_to(&frame.payload, self.target)`，`target` 来自 `--forward-to`，且 `:1074-1078` 拒绝 62056 | **一致** |
| §3.2 步2：未命中 → 不转发并计数（`no_mapping`） | `main.rs:682-704` `ensure_mapping` → bool；`:723-734` `skip_key_table_full` | **语义偏离（仍偏离）**。原型用"首次流量即分配"（`:702`）替代"预配置映射"，所以"无映射"**只在键表满（64）时**才出现。`main.rs:643-647` 的注释自己承认："The cap is what makes the … branch … reachable at all"。这是**用容量上限模拟一个设计分支**，不是实现该分支。 |
| §3.2 步3：发现期例外 = dst ∈ 62900..62999 **且** magic 8DE8FC70 | `main.rs:1366-1368`（F3-A）与 `:1349-1351`（F2）：`flags & FLAG_DISCOVERY != 0 \|\| (dst in 62900..=62999)` | **偏离（更宽，且条件放错）**：①是 **OR** 不是 **AND**；②完全不看 magic；③与同文件 `:440-445`（`SimState::consider` 的 `is_req`，那里是 `flag && 端口段 && len==4 && magic`，**AND**）自相矛盾。后果：**一个 `dst==62056` 但带 `FLAG_DISCOVERY` 的真数据面帧会被判为发现帧而静默漏转**，且不落入任何 F3-A 计数器。详见 M1。 |
| §3.2 步3：数据面帧（dst==62056）无映射即不转发 | 同上 | **一致**（在表满时） |
| §4.2：62056 载荷 **100% 原样** | `main.rs:737` 直接把 `frame.payload` 交给 `send_to`，零拷贝改写；`:744`/`:818` 两侧各自对**本端实际字节**算 sha256 | **一致，且本轮首次拥有真正证据**（120 B 全字节三向对账） |
| §4.1：F3 原型不实现加密 | 无加密/密钥代码 | **一致**（且 `main.rs:1689-1694` notes 明写 `no … encryption is claimed`） |
| §4.3：分层计数 + reconciliation | `summary` 的 `datagrams 5` / `received frames 5 (processed 5, rejected 0)` / `reconciliation 5==5` | **一致（F1/F2 层面）**；**但 F3-A 层面缺 `skip_discovery`**——发现帧在 `consider()` 之前就被过滤（`:1364-1376`），`ForwardStats` 里没有任何字段记录它，所以 `frames seen 4` 无法与"输入 5 帧"对账（详见 M9） |
| §5.2：回包策略二选一（D4 兼容 / 不回包），且每项测试注明 | 同一次 run 同时开 `--simulate-datapath`（F2，发 1 个 20 B 探针，`datapath-log: reply sent 20B`）与 `--forward-to`（F3-A） | **未声明（C 节偏离）**：实际选了"D4 兼容"分支，但记录与 summary **都没有选边**。上一轮 L13 未修。 |
| §5.3：Agent **不得与游戏共存 bind 62056** | `:1017-1021`（`--port`）、`:1074-1078`（`--forward-to`）、`:1085-1089`（`--forward-listen`）三处 fail-closed，`main()` `:1699-1706` 转 exit 1 + `[!]` 前缀；默认端口 34718 | **一致（入口层）**；**但护栏不在使用点**（M2） |
| §5.3：**不得设 SO_REUSEADDR** | `main.rs` 全文无 `reuse` / `SO_REUSEADDR` / `set_reuse_address` 调用（仅 `:28`、`:498` 两条注释） | **一致（静态证据）**；脚本层无验证手段（L7） |

### 4.3 4 个新单测的实际内容（`main.rs:2092-2173`）

`cargo test` 实测 **17 passed / 0 failed**（`#[test]` 共 17 个）。

| 测试 | 行 | 实际断言 | 评价 |
|---|---|---|---|
| `sha256_matches_known_vectors` | `:2092-2106` | 空串 `e3b0c4…b855`（FIPS 向量）✓；`"abc"` `ba7816…15ad`（FIPS 向量）✓；`120×0xAB` 仅 `assert_eq!(sha256_hex(&long).len(), 64)` | **前两条强**；**第三条弱**——只保证"长度对、不 panic"，padding 路径无向量覆盖。应断言 `3442eea54f994b0d41c1da867e8347d69fa1a40e2d8a437dcde54dae74504922`（本轮独立算出） |
| `forward_skips_non_datapath_frames_by_reason` | `:2108-2117` | 只发 **50999**；断言 `skip_not_datapath==1`、`forwarded==0`、`mappings_created==0`、`skip_key_table_full==0` | **强但覆盖不全**：一审点名要 `62905`（发现帧端口段）与"带 DISCOVERY flag 的 62056 帧"两种，**都没有**。且 `mk_forward_frame` `:2074-2090` 把 `flags` 硬编码为 `0`、`seq` 硬编码为 `1`，**在这套 helper 下无法构造带 `FLAG_DISCOVERY` 的帧** → 该分支至今**零测试** |
| `forward_key_table_full_refuses_to_forward` | `:2119-2142` | 填满 64 键 → `mappings_created==64`；第 65 个新键 → `skip_key_table_full==1` 且 `forwarded` 不增；已映射键重发 → `forwarded+1` | **强（本轮最好的一个测试）**，真正证明了 `skip_key_table_full` 分支可达 |
| `forward_delivers_payload_verbatim_and_peer_records_sender` | `:2144-2173` | 真 UDP：`ForwardListener::new(21398)` + `ForwardState::new("127.0.0.1:21398")`，120 B `(0..120u8)`；`forwarded==1`、`bytes==120`；`drain` 后 `received==1`、`bytes==120`、`assert_eq!(&buf[..120], &payload[..])`（**全字节**）；`seen.port()==fw.sock.local_addr().port()`、`seen.ip().is_loopback()`、`first_from==last_from` | **强**（全字节 + 身份端口绑定 + 真 socket）。瑕疵：`std::thread::sleep(Duration::from_millis(120))` 是时间竞态，慢机/CI 会 flaky；应改为最多 1 s 的重试轮询 |

**缺失的两个测试（一审明确点名）**：

1. **`consider(62905) → skip`**：不存在（`:2112` 只测 50999）。
2. **`ForwardListener::new(62056) → Err`**：**不存在，而且今天不可能通过**——`ForwardListener::new`（`main.rs:792-803`）**根本不检查 62056**，它只会 `UdpSocket::bind(127.0.0.1:62056)` 并在端口空闲时**成功**。这不是"测试没写"，而是"函数不支持"。

---

## 5. D. 表述边界

### 5.1 做得好的部分（应当确认）

- **产物自带边界声明**（不只是文档）：`summary.txt:48-66` 的 notes 明写 `LOOPBACK PROTOTYPE`、`no retransmit, no rewrite`、`nothing is injected into a game process (Design I/II is M0-B)`、`no real player join, H2/R1 bind semantics, Relay RTT or encryption is claimed`、`the crate remains the reference implementation`。
- **F3-A 段落明确写出"唯一目标"排他性**：`target : 127.0.0.1:21346 (peer Agent port - NOT the game socket, NOT :62056)`（`main.rs:1629-1631`）。
- **F2 的 D4 探针单独标注**：`reply sent : 1 (D4: at most ONE 20B local probe per run)`、`datapath-log` 里 `- local probe only`。
- 未出现"联机/双机/零丢包/真实房主应答"等越界主张。

### 5.2 必须收紧/纠正的部分

| # | 问题 | 位置 | 说明 |
|---|---|---|---|
| D1 | **summary 的 F1 注记与 F3-A 注记自相矛盾** | `main.rs:1682-1685`（渲染为 `summary.txt:54-57`） | 该行是无条件输出的字面量：`It never forwards to a peer and never modifies game traffic. F1 evidence only`。但本次运行**开着 `--forward-to`**，同一份 summary 下方 `:61-66` 就在说"payloads are forwarded verbatim"。**产物在描述自己时出现了假话。** 修法：该句改为受 `args.forward_to.is_none()` 条件约束，或改写成"F1 路径本身不转发；F3-A 路径见下节"。 |
| D2 | 记录仍写"**同样的载荷**（字节数与载荷头一致）" | `docs\F3A-DIRECT-FORWARD-20261114.md:48` | 一审必改⑥第①条要求降级为"长度与前 8 字节一致，未做全字节比对"。**本轮已具备全字节证据，该句应升级而不是降级**——但要重写成"120 B 全字节 SHA-256 三向一致（forward-log / peer-recv / 驱动脚本独立计算）"，而不是含糊的"同样的载荷"。 |
| D3 | 记录仍用旧字段名 `no_mapping`，且仍把它挂到 §3.2 第 2 步 | `docs\F3A-DIRECT-FORWARD-20261114.md:15`、`:18`、`:37`、`:44` | 代码已改名为 `skip not datapath` / `skip key table`，记录完全没有跟上。 |
| D4 | 记录把"发现帧判定"诚实地写成 **`62900..62999 或 FLAG_DISCOVERY`**（OR） | `docs\F3A-DIRECT-FORWARD-20261114.md:14` | 记录写的是**实现**（OR），设计写的是 **AND**。写实话是对的，但**必须同时指出与 §3.2 的差异**——现在读起来像"实现与设计一致"。 |
| D5 | 缺"单进程双角色自环"声明 | 记录全文 | 一审必改⑥第②条。当前 `--forward-to 127.0.0.1:21346` 与 `--forward-listen 21346` 在**同一个 Agent 进程**内完成发送与接收，"对端 Agent"一词会让读者以为是两个进程。 |
| D6 | 缺"断言数"的诚实表述 | `:37`、`:41` | "17 项 / 17/17" 与当前 27 站点/31 次执行不符。 |
| D7 | 未解释 `listen window … for 2.3 s` 与 `--listen-seconds 30` 的差异 | `:35`、`:37`（脚本 `:124` 传 30） | 一审 L10 未修。真实原因：脚本 1.5 s 后写 stop（`run-f3a-forward-selftest.ps1:194-195`），Agent 见 stop 即 `break`（`main.rs:1264-1266`），故实际窗口 ≈ 2.3 s。一句话即可说清。 |
| D8 | 未声明 §5.2 的回包策略选哪一条 | 记录全文 + summary notes | 一审 L13 未修。实际是"D4 兼容"（1 个 20 B 探针），应明写。 |
| D9 | `frames seen` 字段名在 F2 与 F3-A 两处同名同值不同义 | `main.rs:1598`（F2）与 `:1632`（F3-A） | 两者都渲染成 `frames seen     : 4`，在 summary 里上下相邻。虽然语义都是"non-discovery 帧数"，但同名易被误读成同一个计数器。建议 F3-A 侧改名为 `frames considered`。 |

### 5.3 D 节结论

**表述边界：产物层（summary/日志）基本守住，但有一处自相矛盾（D1）；记录层（`F3A-DIRECT-FORWARD-20261114.md`）整体失效（D2–D8 全部未改）。**

---

## 6. E. 缺陷清单

### 6.1 阻断（1）

#### B1（阻断）交付记录完全未回写，且其 PASS 主张所引证据在现行判据下达不到标

- **位置**：`docs\F3A-DIRECT-FORWARD-20261114.md:3`（状态行）、`:37`（17 项）、`:41`（17/17）、`:43`（证据目录指向 `…-142008`）、`:44`（`no mapping 1`）、`:48`（"同样的载荷"）、`:56-64`（9 行旧哈希）
- **事实**：文件 mtime **14:20:33**，早于本次整改的全部产物（`main.rs` 14:39:44 / exe 14:40:44 / ps1 14:41:15 / 两个新证据目录 14:40、14:41）。`grep` 新哈希/新尺寸在 `docs\*.md` 中 **0 命中**。§4 的 9 个哈希**逐个命中 `…-142008`** 这一整改前产物。用现行 23 条数据断言离线重放 142008，**6 条失败**（无 sha256 字段、无 `forward sock`、无 `skip not datapath`）。
- **影响**：任何只读记录的读者会得到"旧哈希 + 旧证据 + 17/17 通过 + `no_mapping`"的错误认知；本次整改在交付层面**不可见**。这正是上一轮⑦要防的失败模式，且更严重——因为记录现在主张的 PASS 与其自身引用的证据不再匹配。
- **修法**：按本轮实测值重写 §2/§3/§4：断言数写 `27 站点 / 31 次执行`；证据目录改 `F3A-forward-selftest-20261114-144121`；§4 全表换成 §2.1 的 10 个哈希 + main.rs(88,703 / `2596BADE…`) + ps1(15,393 / `59F2390A…`) + exe(381,440 / `563122E2…`)；补 `exit.txt` / `agent-console.txt` / `agent-stderr.txt` / `negative-cases.txt` / `stop` 五行；补构建命令与工具链（`cargo +1.75.0 build --release`）留痕。

### 6.2 高（2）

#### H1（高）⑥ 记录表述收紧三处，一处未做、两处未做

- **位置**：`docs\F3A-DIRECT-FORWARD-20261114.md:48`（"同样的载荷"）、`:37`/`:41`（17 项/17/17）、全文（无自环声明）
- **修法**：见 D2 / D6 / D5。

#### H2（高）⑦ 过程披露未做，且"失败运行"已变为不可审计

- **位置**：记录 §2/§3 全文；`run-f3a-forward-selftest.ps1:146-147`（stdout 被异步读走但脚本自身无 transcript）
- **事实**：①`M0A\captures` 下 F3A 共 **6 个**运行目录，其中 **4 个非最终运行**（141849 / 141904 / 141929 / 144051）记录**一个都没提**（只提了 142008）；②144051 的失败原因不可复原：Agent 侧 `exit=0` 且 23 条数据断言全过，脚本在两次运行之间（14:41:15）被改过而无备份；③`2.3 s` vs `--listen-seconds 30` 未解释；④§5.2 回包策略未选边。
- **修法**：①披露 4 个非最终运行（含各自 `summary.txt` 哈希与一句话结论）；②给脚本加 `Start-Transcript` 或 `Tee-Object` 落 `selftest-console.txt`（F1/F2/F3-B 的脚本都有此机制，F3-A 是退化）；③写清 2.3 s 的成因；④显式声明"F3-A 采用 §5.2 的 D4 兼容分支（每 run 1 个 20 B 本机探针，F2 侧）"。

### 6.3 中（9）

| # | 缺陷 | 位置 | 修法 |
|---|---|---|---|
| M1 | `is_discovery` 用 **OR**（flag 或端口段），设计 §3.2 步3 要求 **AND**（端口段且 magic）；且与 `SimState::consider` 的 AND 语义（`:440-445`）自相矛盾；两处重复实现 | `main.rs:1366-1368`（F3-A）、`:1349-1351`（F2） | 抽出 `fn is_discovery_exception(frame: &Frame) -> bool`，按设计语义实现（端口段 && `payload_len==4` && `payload==DISCOVERY_MAGIC`），两处共用；补单测：`(dst=62056, flags=0x04)` 必须**被转发**、`(dst=62905, payload=0xDEADBEEF)` 按新语义处理 |
| M2 | D2 护栏只在参数解析层，**不在使用点**：`ForwardListener::new(62056)` 与 `ForwardState::new("…:62056")` 都不校验，可成功 bind；因此一审要求的 `new(62056)=Err` 单测**今天不可能通过** | `main.rs:792-803`、`:665-677` | 在两个 `new` 里加 `if port == DATAPATH_PORT { return Err(...) }`（fail-closed），再补该单测 |
| M3 | ⑤ 未完全关闭：缺 `consider(62905) → skip` 单测；缺 `new(62056)=Err` 单测 | `main.rs:2108-2117` | 见 M2；`mk_forward_frame` 增加 `flags` 参数（`:2074-2090` 硬编码 `flags: 0`，导致发现帧无法构造） |
| M4 | `sha256_matches_known_vectors` 的 120 B 分支是弱断言（只断 `.len()==64`），padding 路径无向量 | `main.rs:2104-2105` | 断言 `3442eea54f994b0d41c1da867e8347d69fa1a40e2d8a437dcde54dae74504922`；再加一条 55/56/64 字节的边界向量 |
| M5 | 断言 `:249 skip key table == 0` 在当前拓扑下不可证伪（1 键 vs 上限 64），零信息量 | `run-f3a-forward-selftest.ps1:249` | 加高基数用例（>64 键）断言 `skip key table == 超出的键数`；或删掉并注明由单测覆盖 |
| M6 | 断言 `:278` 空域恒真（`$fwdLines` 的定义域里不可能出现 629xx） | `run-f3a-forward-selftest.ps1:278` | 改为对 `forward-log.txt` **全部**行断言 `seq=3` 不出现；或断言 `peerLines.Count == 3` 且其中无 `len=4` |
| M7 | identity binding 断言同源自证（两个字段来自同一份 summary、同一进程）、只比端口、未跨文件对照 | `run-f3a-forward-selftest.ps1:260-266` | 改为读 `forward-log.txt` 的 `peer-recv … from=<ip:port>`，与 summary 的 `forward sock` 比端口**并与 `forward-log` 的 forward 行目标比 IP**；断言 `from` 的端口 ≠ 62056 且等于 `forward sock` 的端口 |
| M8 | summary notes 里 F1 段无条件声称 `It never forwards to a peer`，与本次运行的 F3-A 段直接矛盾 | `main.rs:1682-1685`（`summary.txt:54-57`） | 该句受 `if args.forward_to.is_none()` 约束，或改写为"F1 通道不转发；F3-A 见下" |
| M9 | F3-A 计数域完全看不到发现帧：`ForwardStats` 无 `skip_discovery`，`frames_seen` 只在 `consider()` 里 `+1`；`frames seen 4` 无法与"输入 5 帧"对账 | `main.rs:630-641`、`:1364-1376` | 在 `:1369` 的 `else` 分支加 `skip_discovery` 计数并写进 summary，使 `frames_seen + skip_discovery == received`（补上 §4.3 的分层对账） |

### 6.4 低（8）

| # | 缺陷 | 位置 | 修法 |
|---|---|---|---|
| L1 | `drain` 用调用方的 `[0u8; 2048]`，>2048 B 会被静默截断且 `len` 记成截断值 | `main.rs:1271`、`:805-832` | 缓冲区改 `65535`；`if len == buf.len() { truncations += 1 }` |
| L2 | 转发套接字绑 `0.0.0.0:0` | `main.rs:669` | 本机回环原型应绑 `127.0.0.1:0`（真实双机时再放开，并在记录里说明） |
| L3 | `stop_seen` 的 `break` 早于 `drain`，最后一批已到达载荷丢失且不计入 peer 统计 | `main.rs:1264-1266` vs `:1270-1273` | `break` 前先 `drain` 一轮 |
| L4 | `forward FAILED` 日志仍缺目标地址 / dst / sock / gen | `main.rs:763` | 补 `-> {target}` 与 `dst=…`（一审 L11 未修） |
| L5 | oversized / no-payload 帧完全不进 F3-A 计数（`:1365` 直接跳过） | `main.rs:1364-1376` | D5：`skip_rejected_flags` 计数 |
| L6 | "17 / 31 / 37" 三个断言数互不一致，且脚本自身无 transcript | `:37`、`:41`、脚本全文 | 统一为 `27 站点 / 31 次`；加 transcript |
| L7 | `bind-check` 不覆盖 §5.3 的 `SO_REUSEADDR`，且在固定命令行下不可证伪 | `run-f3a-forward-selftest.ps1:161-165` | 脚本无法查，须在记录里显式声明"该约束仅由源码静态审查（无 `reuse` 调用）佐证"；并把 `:165` 的断言名改成诚实表述 |
| L8 | 负向用例断言 `-match '62056'` 弱；`$code` 在 `Kill()` 之后取 | `run-f3a-forward-selftest.ps1:114-118` | 按用例分别匹配 `must not be 62056` / `must not target port 62056`；`$code` 移到 `Kill` 之前或在超时分支显式判 FAIL |

---

## 7. 第一轮 7 项必改：逐项判定

| # | 必改项 | 判定 | 证据位置 |
|---:|--------|:---:|---|
| ① | 载荷 sha256 双向对账（含 120 B 全字节） | **✔ 关闭** | 发送侧 `main.rs:736` `sha256_hex(&frame.payload)` → `:744` 日志；接收侧 `:818` `sha256_hex(&buf[..len])`（对**收到的字节**重算）→ `peer-recv` 日志。驱动侧 `run-f3a-forward-selftest.ps1:177-186` 用 `.NET SHA256` 独立算 `$expectDigest`，`:294-302` 三条断言（每侧 3 条摘要、两侧集合相等、与期望集合相等）。证据 `…-144121\forward-log.txt` 3 条 forward + 3 条 peer-recv 各带 `sha256=`，120 B 全覆盖。**本轮用 .NET SHA256 独立复算 3 个载荷，与日志逐字相同。**（残留：集合比较非配对比较，见 §3.2 #25） |
| ② | `--port 62056` 护栏 + 3 个负向用例 | **✔ 关闭** | `main.rs:1017-1021`（`--port`）、`1074-1078`（`--forward-to`）、`1085-1089`（`--forward-listen`），三者 `return Err(...)` → `main()` `:1702-1705` `eprintln!("[!] {e}")` + `ExitCode::from(1)`。证据 `negative-cases.txt` 三行均 `exit=1` 且三句 stderr 互不相同（含 `must not be 62056` ×2、`must not target port 62056` ×1）。**本轮实跑交付 exe 三次，逐字复核。**（残留：断言 `:118` 只 `-match '62056'`，弱） |
| ③ | `no_mapping` 文案/语义对齐 | **✖ 未关闭** | 代码侧**做了**：`ForwardStats.skip_not_datapath`（`main.rs:637`）+ `skip_key_table_full`（`:638`），注释 `:635-636` 自认旧计数器的语义错误，summary 文案改为 `skip not datapath (dst port != 62056)` / `skip key table (no mapping: key table full …)`（`:1642`、`:1646`）。**但**：①summary `:1646` 仍把"键表满"这个**原型自造**的分支挂到 `design v0.3 §3.2 step 2`——设计里没有"容量上限"这回事；②记录 `:15` 仍写"非 62056 帧 → 计入 `no_mapping`，对应设计 §3.2 第 2 步"，`:18`/`:37`/`:44` 仍用旧名。**语义在代码里被诚实披露，在记录里仍是错的。** |
| ④ | summary 增 `forward sock` 并断言 peer `from` 匹配 | **✔ 关闭** | `main.rs:1628` `forward sock : {} (sender identity the peer sees)`，值取自 `:1439-1443` `f.sock.local_addr()`；`first sender` `:1660`。脚本 `:239-240` 抓取、`:260-266` 断言。证据 `…-144121\summary.txt:32` `forward sock 0.0.0.0:51286` ↔ `:45` `first sender 127.0.0.1:51286`；**跨文件**：`forward-log.txt` `peer-recv n=1 from=127.0.0.1:51286` 亦一致（本轮手工核对）。（残留：断言只比端口、且同源自证，见 §3.5） |
| ⑤ | 补 4 个单测（含 62905 skip、`ForwardListener::new(62056)=Err`） | **✖ 未完全关闭（部分）** | 4 个测试**存在**且 `cargo test` 17 passed：`sha256_matches_known_vectors`(`:2092`)、`forward_skips_non_datapath_frames_by_reason`(`:2108`)、`forward_key_table_full_refuses_to_forward`(`:2119`)、`forward_delivers_payload_verbatim_and_peer_records_sender`(`:2144`)。**但**：①**无 62905 用例**（`:2112` 只有 50999）；②**无 `new(62056)=Err`**，且该函数不校验 62056，测试无法通过；③sha256 的 120 B 分支弱断言；④`mk_forward_frame`（`:2074-2090`）硬编码 `flags: 0`，发现帧无法构造。 |
| ⑥ | 记录表述收紧 3 处（"同样的载荷"、自环声明、17→18 项并拆分） | **✖ 未关闭** | 记录 mtime 14:20:33 未动。`:48` 仍"对端确实收到同样的载荷（字节数与载荷头一致）"；全文无"单进程双角色自环"；`:37` 仍"断言 17 项"、`:41` 仍"17/17 断言通过"（且正确值也不是 18，而是 27 站点/31 次）。 |
| ⑦ | 过程与文件身份补全（披露失败运行、补 exit/console/stderr 哈希、说明 2.3 s、声明不回包） | **✖ 未关闭** | 记录 §4 仍 9 行、全旧值、缺 5 个过程文件；4 个非最终运行（141849/141904/141929/144051）无一披露；`2.3 s` 未解释；§5.2 回包策略未选边（实际用了 D4 兼容分支）。 |

**汇总**：✔ 3 项（① ② ④）｜✖ 4 项（③ ⑤ ⑥ ⑦，其中 ⑤ 为部分完成）。
**与上一轮的对照**：三项**硬性**必改（①②④，即一审 §7.4 所说的"第 1、2 项为硬性 + 身份绑定"）全部关闭且证据可独立复算——这是实打实的进步；**未关闭的四项全部是"记录与覆盖度"类**，其中 ⑥⑦ 是纯文本工作。

---

## 8. 仍然薄弱、但不阻断进入下一步的地方

1. **本机自环的证据上限**：`--forward-to 127.0.0.1:21346` 与 `--forward-listen 21346` 在**同一个 Agent 进程**内成环。它证明"帧 → `consider()` → `send_to` → `recv_from` → 字节一致"，但**不证明**跨进程/跨机的 UDP 行为、MTU 分片、乱序、丢包、NAT。这是设计 §5.1 已声明的范围，**不阻断**，但记录必须补自环声明（D5/⑥）。
2. **映射机制是"首次流量即分配"而非"预配置映射"**：`ensure_mapping`（`main.rs:682-704`）在首次见到键时就建表并转发，所以"未命中不转发"只在容量上限处可达。这与设计 §3.2 步2 的字面语义**不同**。在原型阶段可接受（`main.rs:643-647` 已诚实注释），但 F3-B 引入真实 Relay/对端状态时**必须换成真正的映射表**，否则"无映射即不转发"这条安全语义永远不可测。
3. **`is_discovery` 的 OR 语义（M1）**：真实场景下 62056 帧带 `FLAG_DISCOVERY` 的概率很低，所以**当前风险小**；但它是一个**静默漏转**通道，且与设计 AND 不符、与 `SimState` 不一致。应在 F3-B 之前修（M1），不必阻断本步。
4. **exe 的可复现性**：本轮已把"差 24,635 字节"归因到"构建目录路径长度"，可说清；但**没有任何构建留痕**（命令、工具链、`RUSTFLAGS`）。下一轮若换机器/换工具链，就无法再做这种归因。建议在 `civlink\build-agent.ps1`（或记录 §4）里固化 `cargo +1.75.0 build --release` 与 `--remap-path-prefix`。
5. **`SO_REUSEADDR` 只能靠静态审查**：脚本/运行态都查不到。当前结论"未设置"来自 `main.rs` 全文无 `reuse` 调用 —— 这是**必要不充分**证据（依赖标准库 `UdpSocket::bind` 不设该选项这一行为）。可接受，但应在记录里如实标注证据类型。
6. **单测的时间竞态**：`forward_delivers_…` 用固定 `sleep(120ms)`（`main.rs:2157`）。本机快，CI/慢机上 flaky 风险真实存在。改重试轮询即可。
7. **断言集合的"配对性"**：`:296` 比集合不比配对（串包检测不到）。当前 3 条载荷中两条 8 B 内容不同、一条 120 B，串包概率极低，但这是"证据强度"而非"证据正确性"问题。
8. **`skip key table` 的端到端从未为真**：该计数在所有 6 次运行里恒为 0。分支可达性只有单测撑（单测是真的），端到端从未走出这条路。

---

## 9. 复现命令（只读，供下一轮复用）

```powershell
# 文件身份
Get-FileHash -Algorithm SHA256 civlink\agent\src\main.rs, civlink\civlink-agent.exe, civlink\run-f3a-forward-selftest.ps1
Get-Item civlink\civlink-agent.exe | Select-Object Length, LastWriteTime

# 证据哈希（10 个文件 × 6 个目录）
Get-ChildItem M0A\captures\F3A-forward-selftest-* -File | Get-FileHash -Algorithm SHA256

# 断言站点计数（应为 27，运行时 31）
Select-String -Path civlink\run-f3a-forward-selftest.ps1 -Pattern '^\s*Check ' | Measure-Object

# 62056 全部落点与 SO_REUSEADDR
Select-String -Path civlink\agent\src\main.rs -Pattern 'DATAPATH_PORT|62056'
Select-String -Path civlink\agent\src\main.rs -Pattern 'reuse|REUSE'
Select-String -Path civlink\agent\src\main.rs -Pattern 'UdpSocket::bind'

# 负向用例（只跑参数解析，不会 bind）
.\civlink\civlink-agent.exe --port 62056            # exit 1
.\civlink\civlink-agent.exe --forward-listen 62056  # exit 1
.\civlink\civlink-agent.exe --forward-to 127.0.0.1:62056  # exit 1

# 独立复算载荷摘要（与 forward-log 比对）
$sha=[Security.Cryptography.SHA256]::Create()
$p3=[byte[]]::new(120); for($i=0;$i -lt 120;$i++){ $p3[$i]=[byte]($i+1) }
([BitConverter]::ToString($sha.ComputeHash($p3)) -replace '-','').ToLowerInvariant()

# 构建归因（输出到临时目录，勿污染仓库 target）
$env:CARGO_TARGET_DIR="$env:TEMP\f3a-audit-build175"
cargo +1.75.0 build --release --offline
```

---

## 10. 本报告未覆盖

1. `civlink_hook.dll` 侧的出向抓取正确性（F2 证据默认可靠，本步不进游戏）。
2. 真实双机 / H2·R1 共存绑定 / Relay RTT / 加密（设计 §5.1 明确不作为 F3-A 判据）。
3. F3-B（Relay 多 Agent）、F3-C（退避）、F3-D（忙轮询）、F3-E（故障注入）。
4. 裁定审计 E1–E7 七条前置条件的逐条文本（仓库内无该定义文本，无法枚举）。
5. `civlink-fakeip` crate 的键实现细节（本步只核对 `ForwardMapKey` 与之形状对应）。
