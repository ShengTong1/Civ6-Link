# F3-B Relay 转发原型 · 第三轮独立审计（F3B-REVIEW-3）

- 审计对象：`docs\F3B-RELAY-FORWARD-20261114.md`（v3，303 行，声称 PASS 68/68）
- 代码：`civlink\relay\src\main.rs`、`civlink\relay\Cargo.toml`、`civlink\relay\target\release\civlink-relay.exe`
- 证据：`M0A\captures\F3B-relay-selftest-20261114-152821\`（10 文件）
- 自检脚本：`civlink\run-f3b-relay-selftest.ps1`（rev3）
- 审计方法：read 读全文 + pwsh Get-FileHash/Get-ChildItem 独立重算 + 目录树核对；**全程只读**，未运行自检脚本、未绑定 62056、未改动任何被审文件。

---

## 0. 裁定摘要

**通过。**

第二轮 2 项高缺陷（H-1「头部」vs「载荷前 8 字节」措辞、H-2 no sender 分支零命中）与 5 项中缺陷（M-1 fatal/exit 3 已实现口吻、M-2 注册丢包断言放宽+判词分母自指、M-3 -144934 归类错误、M-4 方向≠状态隔离未声明、M-5 三条自证断言）已全部实质修复，且文档 §4.5 打勾表、代码行为、证据文件三方咬合；68 项断言经本轮独立重算成立。剩余 5 项低瑕疵均不推翻结论；唯一未验证承诺（fatal/退出码 3）已如实降级为「不证明」，并写入 §8 作为 F3-E 的强制承接项。

---

## 1. 缺陷分级计数

| 等级 | 本轮 | 第二轮 | 第一轮 |
|---|---|---|---|
| 阻断 | 0 | 0 | 0 |
| 高 | 0 | 2（H-1、H-2） | 1（H-1） |
| 中 | 0 | 5（M-1…M-5） | 4 |
| 低 | 5（另有 §6.1 已自认的 5 项代码级遗留，非本轮新增） | 9 | 6 |

本轮缺陷清单见 E 节（E1–E5），最小转正条件见 E 节末。

---

## A 节 · 证据真实性

### A.1 哈希与字节数独立重算（15/15 零偏差）

产物与脚本（与文档 §6 身份表逐项比对）：

| 文件 | 实测字节 | 实测 SHA-256 | 文档 §6 | 结果 |
|---|---|---|---|---|
| relay\src\main.rs | 22,246 | AAB64B53186BB661428C5000E1629EDE8BE3A77E98FB336613B961FA00EAA472 | 22,246 / 同哈希 | 一致 |
| relay\Cargo.toml | 479 | 93C7D4DA43D523693C83644234CBE95FBDD43EF120489031D50491E21B9614D1 | 479 / 同哈希 | 一致 |
| relay\target\release\civlink-relay.exe | 262,144 | AE03327E417E89A3A885D87A9C7330CE331EAE9E4C24AE27B3AB5B13C0225BE3 | 262,144 / 同哈希 | 一致 |
| run-f3b-relay-selftest.ps1（rev3） | 31,710 | 785D6E39FB151CA7F9342FC0FCC41F67E8CAEA3F80B31B4DF7FE53E2F45E266A | 31,710 / 同哈希 | 一致 |
| run-f3b-relay-selftest.ps1.bak-16630（rev1） | 19,041 | 2D4A9E1E556DAA911301CB62179E72DD0FD348DAB40434825E4D3F17B3CB95F7 | 19,041 / 同哈希 | 一致 |

证据目录 10 文件（与文档 §6 行 263–272 逐项比对）：

| 文件 | 实测字节 | 实测 SHA-256 | 结果 |
|---|---|---|---|
| relay-summary.txt | 1,528 | 609FE0B4FE98A4467E55309B04533CA44B37D7E8918886B944AA41C26FC7DA0D | 一致 |
| relay-log.txt | 1,827 | 27186002EBF0180C250213058B00E054682F4793477801A03B362724F54B8D16 | 一致 |
| result.txt | 950 | ADB84AD2DC0559D196428888782D0F09D32803787B8C369B0EAC6F1E7B11B36D | 一致 |
| bind-check.txt | 24 | D386A4E1EE3A12F7BAFF08FAC8CD1172A461C8FADFF7D6E1AEA5453785DCBF18 | 一致 |
| exit.txt | 12 | 01AD8A20D9C655F39D931C98ACC135EF2B5505ECCEE6B6845F1667FF01CAD1AE | 一致 |
| relay-console.txt | 1,839 | A47175405381FA4999C6DE784940DA4E161BC46EB03DCF856FFCE16824F5A395 | 一致 |
| relay-stderr.txt | 5 | F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295 | 一致 |
| negative-62056-console.txt | 5 | F01A374E9C81E3DB89B3A42940C4D6A5447684986A1296E42BF13F196EED6295 | 一致（与 relay-stderr 同哈希，§6 已解释） |
| negative-62056-stderr.txt | 106 | 6B54E7DBD747DA2F9AC003D0B3F978546CDDCFA6ABF944E53C5470426B6FD1CC | 一致 |
| stop.txt | 6 | A0B28CDF92E250A1A93294D91144A0F893D27197D56B39991CC421768794005F | 一致 |

补充记录：v3 主文档自身实测 23,076 B、SHA-256 2651104C3BC1024FD382CE06CC6B8FF92D17F62D2C3E6243347CFAC62724F84E（文档 §6 未列自身，本轮补记，供后续轮次比对）。两个 5B 文件实测字节 EF-BB-BF-0D-0A（BOM+CRLF），与 §6 行 274–276 的解释逐字吻合。

### A.2 无拼装论证（证据链独立性）

1. **哈希内嵌闭环**：result.txt 内嵌 relay exe 与脚本的 SHA-256（AE03327E…、785D6E39…），与磁盘实测、文档 §6 三方一致。伪造证据需同时伪造「证据文件 + result.txt 自述 + 磁盘产物」，且文档 §6 独立记录。
2. **FNV-1a 64 独立复算**：payload1 `c5620494bd8475c1`、payload2 `b80f7e942a2daa55`、payload3 `c6c9f694beb606fd` 用 BigInteger 从零复算（offset 14695981039346656037、prime 1099511628211、模 2^64、截低 16 位），与 result.txt、relay-log 三条 forward 行的 hash 字段三方一致——载荷哈希链无法靠改一两个文件伪造。
3. **同二进制跨轮复现**：-145026（PASS 67/67）、-152749（FAIL）、-152821（PASS 68/68）三份 result.txt 中 relay sha256 均为 AE03327E…/262,144 B，registrations sent: 10 与三个 payload FNV 逐字相同；PASS/FAIL 差异完全由脚本版本（574FFEC8→61EC05E7→785D6E39）决定。其中 -152749 的 `FAIL (clean but 68 of 0 checks ran)` 是「新分母检查确实生效」的实证：68 条断言全部执行且通过、仅因 `$expectChecks` 中间版本未填入而判 FAIL——若 68/68 是静态拼装的文本，不可能出现这种中间态。产品代码未变、计数矩阵可复现，采信轮与非采信轮互为对照。
4. **内部计数咬合**：relay-log 23 条记录（10 注册 + 3 转发 + 1 no-route + 1 self-drop + 6 拒绝 + 1 unknown-flags + 1 未注册 drop）== summary datagrams 23；relay-console 为 stdout 逐字副本（banner「listening on 127.0.0.1:34720 for 40s」+ 完整 summary + wrote 行）；exit.txt=`exitcode=0`、bind-check.txt=`udp:62056 endpoints: 0`、negative-62056-stderr.txt 106 B 内容与断言文本逐字一致；stop.txt 与「stop 文件干净退出」叙事一致。文档 §4.6 运行历史表与 captures 目录实测逐行吻合（142256 FAIL 3/40、142419 FAIL 6/41、142718 PASS 41/41、142803/142813/142818 PASS 43/43×3、144934 FAIL 4/67、145026 PASS 67/67、152749 FAIL、152821 PASS 68/68）。

---

## B 节 · 断言强度

### B.1 断言计数三方一致

Check 调用点逐一核对 = **68** = `$expectChecks = 68`（脚本 :540 字面量）= result.txt `PASS (68/68)`。运行时无守卫块跳过（一旦跳过将触发 `FAIL (clean but N of 68 checks ran)`，-152749 已实证该机制真实生效）。

### B.2 断言分类

| 类别 | 数量 | 说明 | 代表位置 |
|---|---|---|---|
| 强断言（行为级） | ≈60 | 负向 62056 三件套（$npExited && exit 1、stderr 含 must not use port 62056、Get-NetUDPEndpoint 62056==0）；relay 绑定 34720 / 未占用 62056；5000B 后进程仍存活；B 侧 count==2 + seq/dst/src + 8B Compare-Object 逐字节 + FNV 真比对；A 侧 count==1 + seq/dst/src + 逐字节；无越权投递（无 seq2/3/90）；退出三件套（exit 0、stdout banner、stderr 空）；summary 精确计数 16 条（registers==10、no sender==1、forwarded==3、forward bytes==136、no route==1、self drop==1、oversize==0、fatal none 等）；**attribution closes 独立复算**（fwd+nr+sd+ff+ns==fReq，:463-470）；relay-log 行断言（seq1 hash/len/head/src_peer、seq4 hash/len、seq5 src/dst/hash、五类 reject 各 1、payload-too-large==2、unknown-flags==1、无 forward seq 2/3/90）；runtime ±3s | :170–173, :206, :216, :312, :356–380, :396–398, :445–460, :470, :476, :486–530 |
| 弱断言（自证） | 3 | 与第二轮 M-5 相同的三条：`datagram identity 行 ==`、`reconciliation ==`、`sees PLAINTEXT`——匹配程序自打印字符串，无独立真值来源；**数值侧由 :450（datagrams==rCount+6+6+1）与 :470 独立复算承担**，且文档 §5 不证明第 10 条已如实声明 | :451, :461, :462 |
| 恒真 | 0 | 第二轮已清零，本轮维持 | — |
| 同源（基准取自 summary 的 $rCount） | 2 | :450/:452 以 $rCount 为基准，但 $rCount 被 :449 `registers counted = 10 (exact)` 精确锚定，等价于绝对断言，不构成放宽 | :450, :452 |

### B.3 与第二轮对比

- 唯一放宽项「registers counted <= sent」→ 改为精确 `== 10`，丢包可见（:449，注释 loses are visible, not tolerated）。
- 判词分母自指 `$Checks/$Checks`（守卫跳过仍打印 N/N exit 0）→ 常量 `$expectChecks=68` 三态判词（:541-547）+ 退出双条件 `Failures==0 && Checks==68`（:573）。
- M-5 三条自证断言保留但已在 §4.5 标「部分（保留并声明）」、§5 不证明第 10 条声明。
- 五类拒绝构造、5000B 用例、peerX 未注册用例（:327-335，src_peer=303、seq=91、从不注册）均正确；`no sender == 1` 由 summary 计数 + relay-log drop 行 + 断言三处互证。
- 本轮断言质量相较第二轮**实质性提升，无一项退回**。

---

## C 节 · 设计与实现一致性

### C.1 能力表 ↔ 代码逐项核对（v3 无虚构陈述）

| 文档 §1 声称 | 代码实现 | 核验 |
|---|---|---|
| 五类拒绝 too-short/bad-magic/bad-version/payload-too-large/truncated | parse() :100-124（len<20、magic、version、payload_len>1280、len<20+plen 顺序判断） | 一致，构造用例与 relay-log 五条 kind 一一对应 |
| unknown flags 拒绝不转发并计数 | :368-381（control_frames+unknown_flags+日志） | 一致，日志第 19 行 flags=0x02 |
| 发送者 fail-closed 反查，查不到丢弃计 no sender，绝不回退信封 src_peer | :391-408（forward_requests 先行计数；sender 按来源地址反查；None → no_sender+drop 日志，**无 unwrap_or 回退**） | 一致；M-1 修复实质成立 |
| self drop / no route | :411-423 / :424-440 | 一致，日志第 11/12 行 |
| 载荷原样只拷贝 payload | encode() :126-136 尾部 `out[HDR..HDR+plen]=payload` | 一致 |
| 62056 在 bind 前报错 exit 1 | :215-220（port==62056 → eprintln+exit(1)），位于 :221 bind 之前 | 一致；负向证据 exit 1 + stderr 106 B |
| fatal：summary 先落盘再 exit 3 | :565-577 fs::write summary（失败 exit 1）→ :580-582 exit(3) | 顺序保证成立；**该分支零用例，文档已如实降级（见 D）** |
| 三方比对 = 载荷 FNV-1a 64 + 载荷前 8 字节 hex | :456 fnv1a64(env.payload)、:457 hex_head(env.payload,8)；hex_head 定义 :84-90 取 data.iter().take(8) | 一致；H-1 措辞修复成立 |
| 信封头转发时被重写（flags 清零、src_peer 覆盖） | encode() :129 out[5]=0、:131 out[10..14]=src_peer | 一致；接收侧断言（B 收 src_peer=101、A 收 src_peer=202）验证了重写后语义 |
| 注册别名仅限 src_peer 非 0 且 !=dst | :352-354 | 一致；M-5 产品侧修复 |
| 两条恒等式 | :527-537（datagram identity）、:538-553（reconciliation） | 一致；summary 打印 (10+6+6+1)=23 与 6==6 |

### C.2 计数矩阵逐项复算

- datagrams 23 == 10+6+6+1（registers 10 + forward_requests 6 + bad_envelope 6 + unknown_flags 1）✓
- reconciliation 3+1+1+0+1 == 6 == forward_requests ✓（forwarded 3 + no_route 1 + self_drop 1 + forward_fail 0 + no_sender 1）
- forward bytes 136 == 8+120+8 ✓；control frames 11 == 10 注册 + 1 unknown-flag ✓
- relay-log 23 条记录与 summary 各计数逐项对应 ✓；§3.1 表与 summary 打印零出入 ✓

### C.3 与第二轮 C 节核心结论的延续

透明转发、不重传不重排、无加密（sees PLAINTEXT 声明）、无伪协议应答、62056 代码级+运行级双保险、零依赖（Cargo.toml [dependencies] 为空）六项核心结论均维持成立；本轮未发现新的行为-文档偏离。

---

## D 节 · 表述边界

### D.1 已声明到位（对照第二轮 D.3 清单，全部落实）

1. 不构成联机验证：result.txt evidence label + 文档行 4 + §5 不证明第 1 条（真实双机/部署/跨网/NAT）✓
2. 无加密 / 无身份鉴权（注册表「最后一个注册者 wins」、冒用不报错、只保证未注册 socket 不能借信封 src_peer 冒充）/ 非产品 Relay（§2 三连）✓
3. 62056 表述为「代码级护栏 + 运行期实测未占用」双保险（§4.4 第 2 条）✓
4. 抗超长限定为「任意 ≤65,535 字节畸形数据报不会让 Relay 停止」；>65,535 情形由 fatal exit 3 明确报告但本轮无用例，属设计如此未验证（§4.4 第 3 条 + §5 不证明第 6 条）✓
5. 「头部三方一致」明确不成立（encode 重写 flags/src_peer），v3 全文改为「载荷前 8 字节」（§1 行 40 + §4.4 第 4 条）——H-1 修复到位 ✓
6. fatal/退出码 3 零用例：能力表标注「该分支本轮没有用例」、§5 移入不证明第 7 条（需制造真实收包失败方可证明）——M-1 修复到位 ✓
7. 方向 ≠ 状态隔离：A→B 与 B→A 同一 Relay 进程、同一 peers 表、同一 PowerShell 进程三个 socket，无重启无清表；只证明同一实例双向路由（§4.4 第 1 条 + §5 不证明第 9 条）——M-4 修复到位 ✓
8. 三条格式断言（reconciliation==、datagram identity==、sees PLAINTEXT）自证性质声明（§5 不证明第 10 条）——M-5 修复（声明版）到位 ✓
9. 日志时间戳 UTC 且无时区标记（§6.1 L-3，本轮日志 07:28:29 对应本地 15:28:29）✓

### D.2 未声明或说错的 3 处（均低）

1. **脚本内版本注释陈旧**：run-f3b-relay-selftest.ps1 头部注释（:3）与横幅（:142）仍写 `revision 2`，而文档与 §6 身份表称其为 revision 3；注释内「Revision 2 answers the F3-B audit」的变更清单未同步 v3 内容（peerX、expectChecks、registers==10 均未在注释中出现）。**E1**
2. **§7 证据引用路径歧义（两棵 M0A\captures 树）**：F3-B 证据位于 `CivLink-M0A-audit\M0A\captures\`；全树实测 F3-C/F3-D 证据（F3C-backoff-selftest-20261114-151943、F3D-pressure-selftest-20261114-151218 等）位于**项目根** `C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\`，两棵树并存。v3 §4.5 L-7 标「已关闭」、§7 引用「证据 -151943 / -151218」均未给完整路径，按 F3-B 自身证据目录约定解析时 Test-Path=False（这正是第二轮 L-7 判「不存在」的原因）。存在性上 v3 声称成立，但**可核性打折**。**E2**
3. **§3 步骤 2「前置：34720 与 62056 都必须空闲」措辞不精确**：脚本实际仅把 34720 空闲作为 exit-2 前置（:176-180）；62056 空闲是靠负向测试**之后**的断言强制（:172-173 Get-NetUDPEndpoint==0 与 :214-216 bind-check）。行为等效（62056 被占 → 断言 FAIL），但「前置」一词与实现不符。**E3**

### D.3 第二轮其余低项承接核对

L-5（out-dir 叙事，§4.3 第 3 条：create_dir_all + New-Item -Force）✓ 关闭；L-6（5B 文件 BOM+CRLF，§6 说明）✓ 关闭；L-8（registers=10 可导出，§3 步骤 3 写明 3+3+2+2）✓ 关闭；L-1/L-2/L-3/L-4/L-9 未修，已在 §6.1 如实列出并标注，非本轮新增。

---

## E 节 · 缺陷清单与裁定

### 缺陷清单

| 编号 | 等级 | 描述 | 依据 | 处置建议 |
|---|---|---|---|---|
| E1 | 低 | 脚本头部注释与横幅版本号仍为 revision 2，与文档「revision 3」不一致，v3 变更内容未写入注释 | :3 / :142 实测 | 下轮同步注释（不涉及行为） |
| E2 | 低 | §7 引用 F3-C/F3-D 证据未给完整路径，证据实际位于项目根 M0A 树而 F3-B 自身证据在 audit 子目录树，两棵树布局未声明；L-7「已关闭」以存在性成立但可核性打折 | 全树目录实测；Test-Path 在 audit 树=False | 下轮补全路径并声明两棵树布局 |
| E3 | 低 | §3 步骤 2「前置 62056 空闲」实为负向测试后断言强制而非 exit-2 前置 | :172-173 / :176-180 | 措辞改为「负向用例后断言 62056 无端点」 |
| E4 | 低 | M-5 三条自证断言（:451/:461/:462）保留 | 已声明（§4.5 部分、§5 不证明第 10 条）；数值侧由 :450/:470 独立复算 | 维持现状可接受；如需严格化可删除并在 result.txt 记「格式断言已由数值断言承担」 |
| E5 | 低 | fatal/退出码 3 仍无真实用例（唯一未验证承诺） | 已如实降级（§1 行 42、§5 不证明第 7 条）；**§8 已强制承接：F3-E 必须包含 fatal/退出码 3 的真实用例** | 由 F3-E 落地时补真实收包失败用例并回填 §5 证明 |

另有 §6.1 已自认的代码级遗留（非本轮新增，不计入本轮缺陷数）：L-1 parse() 无 len>20 尾部校验；L-2 --listen-seconds 缺省 60 静默容错；L-3 wallclock_stamp UTC 无时区标注；L-4 _probe-f3b/_probe-f3b2 未入证据表；L-9 send_to 短写分支 UDP 不可达。

### 裁定

**通过**：第二轮 2 高 5 中全部实质修复（H-1 措辞改正且代码侧本就正确、H-2 补 peerX 用例且 no sender=1 三方互证、M-2 精确断言+常量分母+双条件退出、M-3 归类改正、M-4 状态隔离声明、M-5 声明化）；证据真实性 15/15 零偏差并有跨轮同二进制复现对照；断言 68 条三方一致、无恒真、无放宽项。E1–E5 均为低瑕疵且不推翻结论。

### 最小转正条件（将「通过」升级为无可指摘采信）

1. E1：脚本注释版本号 revision 2 → 3，横幅与变更清单同步；
2. E2：§7 引用补完整路径（项目根 `M0A\captures\`）并声明两棵 M0A 树的布局差异；
3. E5：F3-E 按 §8 要求补 fatal/退出码 3 真实用例（制造真实收包失败，如运行期关闭 socket），并在 F3-B 后续版本回填 §5 证明；
4. E4 可选：删除三条自证断言或在 result.txt 记录其数值侧替代。

---

本报告为只读审计产物。除本文件外，本轮未修改任何被审文件。
