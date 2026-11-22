# CivLink M0-C C2 第二轮独立复审报告

- 审计对象：`civlink\client\civlink_client.cpp`、`civlink\ctl\civlink_ctl.cpp`、`civlink\selftest\client_selftest.cpp`、`civlink\run-c2-iface-selftest.ps1`、`civlink\common\civlink_client.h`、`civlink\common\civlink_hook.h`、`civlink\build-msvc.cmd`
- 复审依据：`docs\M0C-C2-REVIEW.md`（第一轮，271 行 / 37,556 B / `4E40F292…`）
- 设计文档：`docs\M0C-C2-DESIGN-20261118.md`（470 行 / 40,665 B / `692BE5CB…`，v2）
- 证据：`M0A\captures\C2-iface-selftest-20261118-0945`（采信轮，39 文件 = 29 根 + 10 `cfg`）、`C2-inject-smoke-20261118-0916`（18 文件）、`C2-inject-smoke-20261118-0940`（3 文件）
- 方法：只读。逐行读源码、逐字节读证据、独立 `Get-FileHash` 复算。**未运行任何被测程序，未反编译，未做跨机实测。**

---

## §1 裁定

**有条件通过。**

修正主体是真实且高质量的：第一轮 3 个阻断中 2 个（B-1、B-2）彻底关闭，4 个高危中 3 个（H-2/H-3/H-4）关闭，7 个中危全部关闭（7/7）；但 **(a) B-3 只关闭了一半，且替换上来的新判别力主张本身不成立**，**(b) H-1 只修了 6 个 detour 中的 4 个**，**(c) 设计 §7.4 与冒烟 §7 记录的采信轮与产物哈希仍是旧值，与 PLAN 及磁盘现状冲突**。这三类问题共 6 项前置条件（见 §6）修完之前，**不得做"C2 完成"登记**。

**逐条关闭统计**（按第一轮编号）：3 阻断 → 关闭 2 / 部分 1；4 高危 → 关闭 3 / 部分 1；7 中危 → 关闭 7；9 低危 → 关闭 2 / 未关闭 7。合计 14 全关闭、2 部分、7 未关闭。

---

## §2 第一轮必改项逐条核对表

### 2.1 阻断项

| 编号 | 第一轮要求 | 本轮实际状态 | 证据（文件:行号 / 命令输出） |
|---|---|---|---|
| **B-1** | 修 `pinned` 位导致的 `sent` 语义分裂；二选一（推荐方案 1，或方案 2 放弃 pinned 位、每包无条件 `setsockopt`、`sent` 重定义为「发现发送次数」） | **已落实**（采用方案 2，且比第一轮要求更彻底） | `civlink_client.cpp:194-199` 注释明写「the per-socket "pinned" bit was removed」；`:200-203` `struct Slot { SOCKET s; uint16_t portBe; }` 已无 `pinned` 字段；`:298-309` `PinSend` 每包调用 `setsockopt(s, IPPROTO_IP, IP_UNICAST_IF, …)`（`:303`），`rc==0 → c_sent++`（`:305-306`）、否则 `c_sendFail++`（`:307-308`）；`:391` `Hook_bind` 的 `portBe != 0` 建槽逻辑保留但只用于 62056 观测，**不再影响 pin 决策**。证据：0945/scenario-c.txt `sent=10 ignored=4 sendFail=0`，C4 断言 `sent == 10 (one per discovery send from a BOUND socket)`。**另：M-6（"只 pin 一次且在 implicit bind 之前"）随之消解**——每包重设，不存在"pin 时机"问题 |
| **B-2** | `PinSend` 内 `setsockopt` 失败会污染 `WSAGetLastError()`；要求保存/恢复，失败分支必须、成功分支建议 | **已落实**（两条路径都恢复） | `civlink_client.cpp:301` `const int savedErr = WSAGetLastError();` → `:303` `setsockopt` → `:304` `WSASetLastError(savedErr);` → `:305-308` 才分支计数。**关键点：`:304` 位于 `rc` 判定之前，成功/失败两条路径都经过它，无提前 `return` 泄漏路径**。唯一在 `setsockopt` 之前 `return` 的分支是 `:300`（`g_mode != Mode::PIN`），它根本没有调用 `setsockopt`，不违反 B-2 |
| **B-3** | 四条：① 标题降级为 `C2-BOOKKEEPING` 并加 `Egress adapter: NOT VERIFIED`；② 删掉"匹配自己打印字符串"的自指断言，改解析机器可读 `counters:` 行；③ §7.3 改逐条 covered/uncovered/contradicted；④ **加一条"能失败"的断言**（如 `setsockopt` 用非法 ifIndex `0x7FFFFFFF` 应失败并计入 `sendFail`） | **部分落实**：①②③ 已落实；④ 未落实，且用来替代它的新判别力主张**不成立** | ① `result.txt:1` `C2-BOOKKEEPING-SELFTEST: PASS (45/45 runner checks, 60 in-process checks)`、`:2` `Egress adapter: NOT VERIFIED`、每个 scenario 尾部 `NOTE: bookkeeping only - the actual egress adapter is NOT verified here`；② `run-c2-iface-selftest.ps1:59-68` `Get-Counters` 解析 `(?m)^counters:\s+(.*)$`，`client_selftest.cpp:100-112` `EmitCounters`，`:173-182` 断言全部改为比对 `$c.sent/$c.ignored/...`；③ `design:381-400` 12 行 covered/uncovered/contradicted 表（`:391` #4 uncovered 是关键缺口、`:392` #5 partial、`:390` #3b contradicted）；④ **未落实**：`client_selftest.cpp:389-392` 场景 H4 改为 `sent + sendFail == 5`（加和式恒真断言），`ps1:212-213` 同；理由登记于 `design:424-427`（"越界索引返回 0 已被实测推翻"）。**替代方案的问题见 §3 H-6**：`result.txt:13` 与 `ps1:25-26` 声称"不做 setsockopt 会 fail both C and I"，对 I 不成立 |

### 2.2 高危项

| 编号 | 第一轮要求 | 本轮实际状态 | 证据（文件:行号） |
|---|---|---|---|
| **H-1** | 四个 detour 的 `Real_*()` 必须在 `g_inFlight` 窗口内；重入分支也要覆盖 | **部分落实**：第一轮点名的 4 个 detour 全部修对；但**同类的 2 个 recv detour 仍是旧写法** | 已修：`Hook_sendto` `:315-319`（重入分支 `const int rc = Real_sendto(...); g_inFlight.fetch_sub(1); return rc;`）与 `:327-331`；`Hook_WSASendTo` `:339-344`/`:355-357`；`Hook_closesocket` `:363-368`/`:371-373`；`Hook_bind` `:379-384`/`:397-398`。**未修**：`Hook_recvfrom` `:406-408` `if (tlsInHook) { g_inFlight.fetch_sub(1, relaxed); return Real_recvfrom(...); }`、`Hook_WSARecvFrom` `:425-427` 同形——重入分支仍是**先递减、后真实调用**。见 §3 H-5 |
| **H-2** | `WSASendTo` 判定去掉 `!ov`，异步重叠发送也要 pin | **已落实**（代码层），**但无任何测试覆盖** | `civlink_client.cpp:348-352` 注释「H-2: no "!ov" exclusion」+ 判定仅 `bufs && count >= 1`。**缺口**：`client_selftest.cpp:133-152` 的 `Burst` 与全部 9 个场景都用同步 `sendto`，没有任何一处传非 NULL `WSASendTo` 的 `ov`，全部 scenario 的 `scatterGather=0`（0945 `scenario-*.txt`）——即"已改但未验证" |
| **H-3** | `CIVLINK_CLIENT_IFACE_FILE` 未文档化 / 静默失效；要求 ctl 打印 `resolved by` + 提示，或降级为仅自测用 | **已落实**（文档化 + 打印 + 时序修正），但**定性自相矛盾**（见 §3 M-9） | `civlink_ctl.cpp:248-256` `PrintConfigPathResolution` 打印路径与 `resolved by: env override (CIVLINK_CLIENT_IFACE_FILE)` / `default (%LOCALAPPDATA%\CivLink)`，并打印「the DLL reads this from the GAME process environment, so an env override set in this shell does NOT reach an injected game」；`design:289-290` 登记变量与限制；证据 `0945/ctl-t2-all.txt` 三行俱全（`client iface config path:` / `resolved by: env override` / note 行）。**额外收获**：`C2-inject-smoke-20261118-0916` 的 A 轮（env override → `sent 0 / ignored 14`）与 B 轮（默认路径 → `sent 10 / ignored 4`）是这条缺陷的**现场复现**，比第一轮的推理更强 |
| **H-4** | ctl `--iface` 不能接受 loopback | **已落实** | `civlink_ctl.cpp:380-385` `if (info.isLoopback) { printf("[!] --iface '%s' resolves to the loopback pseudo interface (%s) - refusing\n", …); printf("    loopback is not a real egress choice; use ALL or a physical/virtual NIC\n"); return 1; }`；证据 `0945/ctl-t1b-loopback.txt`（279 B，`IfIndex=1 IfType=24 metric=75`，exit 1）。**但 DLL 侧不拒 loopback**，见 §3 M-10 |

### 2.3 中危项

| 编号 | 第一轮要求 | 本轮实际状态 | 证据（文件:行号） |
|---|---|---|---|
| **M-1** | 槽表满时 `c_sockOverflow++` 并导出，不许硬编码 0 | **已落实** | `civlink_client.cpp:217-229` `FindOrCreateSlot`（`:227` 满时 `c_sockOverflow.fetch_add(1, relaxed)` 后返回 nullptr）；`:518` 导出 `c_sockOverflow`。证据 `0945/scenario-i.txt` `sockOverflow=16` |
| **M-2** | 补场景 D（显式 ALL）/ E（空文件）/ F（多行） | **已落实** | `client_selftest.cpp:273-293`(D)、`:296-316`(E)、`:318-340`(F)；证据 `scenario-d.txt`（`sent=0 ignored=8 initError=0`）、`scenario-e.txt`（同）、`scenario-f.txt`（`sent=6 ignored=2 initError=0`，F4 断言"pinned mode active, not degraded to ALL"） |
| **M-3** | `initError==12` 无证据，补场景 G | **已落实** | `client_selftest.cpp:342-363`（配置 `192.168.99.99`，`:354-355` 断言 `c.initError == CIVLINK_INITERR_IFACE_UNAVAIL`）；证据 `scenario-g.txt` `initError=12 sent=0`，G1 断言 fail-open（state 仍为 1） |
| **M-4** | 设计 initError 编号表按实现更正 | **已落实** | `design:259` 表 = `civlink_client.cpp:445`(1)/`:456`(3)/`:457-474`(4..9)/`:475`(10)/`:146`+`:154-155`(11)/`:168`+`:187`(12)，逐值为同一对应关系 |
| **M-5** | `scatterGather` 硬编码 0 → 真实计数 | **已落实**（代码层），**无测试覆盖** | `civlink_client.cpp:347` `if (count > 1) c_scatterGather.fetch_add(1, relaxed);`；`:517` 导出。**缺口**：无任何场景发送 `count > 1`，全部 scenario `scatterGather=0` |
| **M-6** | "只 pin 一次且在 implicit bind 之前"的时序未论证 | **已落实**（随 B-1 消解） | 每包重设，见 B-1。`design:262-280` §4.4 流程图已改为每包路径 |
| **M-7** | C4 是"因缺陷而通过"未披露 | **已澄清** | `0945/scenario-c.txt` C4 断言原文 `sent == 10 (one per discovery send from a BOUND socket)`；`client_selftest.cpp:253-254` 与 `MakeBoundSocketOnPort:155-171`（先 `SO_BROADCAST` 再 bind）配合，读者可自证这是"已 bind socket"路径 |

### 2.4 低危项

| 编号 | 第一轮要求 | 本轮实际状态 | 证据（文件:行号） |
|---|---|---|---|
| **L-1** | `WSAStartup` 无 `WSACleanup`，至少注释说明"故意不清理" | **未修、未加注释** | `civlink_client.cpp:545-553` `DllMain` 只有 `CreateThread`+`CloseHandle`，无 `WSACleanup`、无 `MH_Uninitialize`，也无解释性注释 |
| **L-2** | `IsDiscoveryTarget` 口径需在设计 §4.1 写明 | **未修** | 实现为两条规则（`civlink_client.cpp:261-268`：`:265` 端口 62900-62999、`:266` `INADDR_BROADCAST`），且 `:256-260` 注释明确声明"hook.cpp 那套 socket 身份规则在 C2 不需要"；而 `design:211` 仍写三条规则、含"曾 bind 发现端口的 socket 所有发送均视为发现——socket 身份规则"。**文档与实现口径不一致** |
| **L-3** | ALL 模式下 `ignoredNonDiscovery` 语义与文档不符 | **未修** | `design:250` 仍写"未 pin 的发送次数（非发现目标，或 g_state 未就绪）"，未说明 **ALL 模式下发现包也计入 ignored**。证据：`scenario-a.txt`/`scenario-d.txt`/`scenario-e.txt` 均为 `sent=0 ignored=8`（各 5 个发现包 + 3 个普通包），其中 5 个发现包被计为 ignored 正是新语义，文档未覆盖 |
| **L-4** | `state!=1` 期间发送也进 ignored | **已澄清** | `civlink_client.cpp:322-326`，`design:250` 已写"或 g_state 未就绪" |
| **L-5** | 未测 `CivLinkSessionId` | **已落实** | `client_selftest.cpp:202-203` A4 断言两次读取一致；`0945/scenario-a.txt` A4 PASS |
| **L-6** | `WaitReady` 只在 `state==1` 轮询，不因 `initError` 提前失败 | **未修** | `client_selftest.cpp:86-96` 仍为 50ms×100 轮询 `state==1`，未检查 `initError` |
| **L-7** | `CIVLINK_SKIP_CLIENT_DLL` 复用旧 DLL 且跳过导出校验 | **未修** | `build-msvc.cmd:88-91` `if defined CIVLINK_SKIP_CLIENT_DLL ( echo [*] CIVLINK_SKIP_CLIENT_DLL set - reusing the existing civlink_client.dll & goto after_client_dll )`；`:111-120` 的四导出 `dumpbin` 校验在 `:122` `:after_client_dll` 之前，被完全跳过。`design:362` 只写"`CIVLINK_SKIP_DLL` 同样适用"（连变量名都不是 `CIVLINK_SKIP_CLIENT_DLL`），未登记该风险 |
| **L-8** | `CivLinkShutdown` 在 `prev==0` 时不调 `MH_DisableHook` | **未修**（PLAN 已登记为"有意保留"） | `civlink_client.cpp:493` `if (prev == 1) MH_DisableHook(MH_ALL_HOOKS);`——init 失败（`prev==0`）时钩子已 `MH_EnableHook` 过（`:475`）却不回滚。`M0C-DUAL-ROLE-PLAN-20261118.md:190-192` 已列 L-8 为"部分/有意保留，待复审判定" |
| **L-9** | 设计 §5.1 示例代码与实现不一致，应标"示意，非实现" | **未修** | `design:301-323` 示例仍用 `GetEnvironmentVariableA("LOCALAPPDATA")` 硬编码、不含 `CIVLINK_CLIENT_IFACE_FILE` 分支、不含 `IFINDEX:` 分支，也**没有任何"示意、非实现"标注** |

---

## §3 新引入 / 仍未解决的问题

只列本轮修正**新引入**或**仍未解决**的项。严重度按"对 C2 命题与登记的影响"定，不按代码行数。

### 3.1 高危

**H-5（高危，未解决，H-1 的残留）—— `recvfrom` / `WSARecvFrom` 重入分支仍是"先递减、后真实调用"**

- 位置：`civlink\client\civlink_client.cpp:406-408`（`Hook_recvfrom`）与 `:425-427`（`Hook_WSARecvFrom`）。
- 为什么是问题：`CivLinkShutdown` 的安全论证是"`g_inFlight` 归零 ⇒ 没有线程停在计数段内 ⇒ 可以 `MH_DisableHook(MH_ALL_HOOKS)`"（`civlink_client.cpp:493-497`）。这两个重入分支在 `Real_recvfrom` / `Real_WSARecvFrom` 执行**之前**就把计数减掉，于是"归零"可以在一个线程仍在 trampoline 里时成立。第一轮 H-1 判定该机制为高危，理由是**契约层面**（不是"禁用瞬间必然崩"）；这两个 detour 与第一轮被点名的 4 个是**同一机制、同一后果**，只是路径从"发送"换成"接收"。
- 加重情形：`design:279` 把 recvfrom 系列描述为"纯计数器"，正是这种描述让人误以为它们不参与窗口语义；而代码里它们 `:405` `fetch_add` / `:416` `fetch_sub` 确实参与。
- 修法建议：把 `:406-408` 改成 `const int rc = Real_recvfrom(...); g_inFlight.fetch_sub(1, relaxed); return rc;`（照抄 `:414-416` 主路径），`:425-427` 同。或者在 `civlink_client.h` / 设计 §4.4 明确写"排空语义只覆盖 4 个发送类 detour，recv 类不保证"，并解释为何可接受——但目前文档两处（`design:272-277` 全量流程、`:279` "纯计数器"）都没有给出这个限定。

**H-6（高危，新引入）—— 证据自我描述失实：声称存在一条"不做 setsockopt 就会红"的断言，实际不存在**

- 位置：`0945/result.txt:11-15`（以及 `0928`、`0924` 的对应段落）；`run-c2-iface-selftest.ps1:22-26`。
- 原文（0945/result.txt:13）：「A DLL that never called setsockopt would report sent=0 for every scenario and fail both C (sent 10) and I (sockOverflow 16).」
- 为什么是问题：后半句对 **I 根本不成立**。场景 I 只做 `bind`（`client_selftest.cpp:402-438`，80 个 socket 绑 38000..38079），`sockOverflow` 完全由 `Hook_bind:391` → `FindOrCreateSlot:217-229` 决定，**与 `setsockopt` 零关系**。一个完全不调 `setsockopt` 的 DLL 在场景 I 照样得到 `sockOverflow=16`。这就把第一轮 B-3 已经认定"零判别力"的结论，用一句新的、同样不成立的话重新包装了一遍。
- 后果：这正是用户要问的核心诚实性问题（见 §4）。修法见 §6 前置条件 1。

### 3.2 中危

**M-8（中危，未解决）—— 注入失败后 `client-iface.txt` 已落盘，且代码注释的承诺强于实现**

- 位置：`civlink\ctl\civlink_ctl.cpp:398-403` 写配置；`:405-409` 起才有 `OpenProcess` 失败退 2；注入段 `:430/435/442/450/455/466/470/475/489/499/521` 退 1、`:511` 退 4、`:527/532` 退 3、`:552` 退 5——**全部在写配置之后**。
- 代码注释（`:398-400`）自称：「the config is written only after the target is resolved and validated, so a failed injection never leaves a stale iface choice behind that a later run would silently inherit.」——"a failed injection never leaves"这个承诺是假的，它只保证"`ResolveTarget` 失败不留配置"。
- 现场复现：`0945/ctl-t2-all.txt` 与 `ctl-t3-pin.txt` 都是「`[+] client iface config written: …`」在前、「`[!] OpenProcess failed err=5`」在后，`ctl-t2-exit.txt`/`ctl-t3-exit.txt` = 2，而 `0945/cfg/client-iface.txt` = `ALL`、`cfg/client-iface-pin.txt` = `192.168.191.3` —— **一次 exit 2 的失败注入已经把下一轮的定向选择写进了磁盘**。
- 为什么是问题：下一次成功注入会**静默继承**上一次失败尝试的 NIC 选择。这与第一轮 H-3 要解决的"静默失效"是同一类病。
- 修法建议（三选一，按推荐排序）：① 注入成功后（`:546` `return 0` 前）才写配置——最简单且语义正确；② 失败路径删除刚写的文件；③ 保留现时序但把 `:398-400` 注释改成事实描述，并在 `design:327`/`:331` 与附录 B 风险表登记"失败注入会留下配置"。**当前文档把 T2/T3 的"目标存在 → 配置已写 → 注入阶段才失败"当作预期行为登记（`design:327`），既没登记风险，注释又与实现相反。**

**M-9（中危，新引入）—— `CIVLINK_CLIENT_IFACE_FILE` 的定性自相矛盾**

- 位置：`design:289` 标题写「**覆盖变量（正式特性，审计 H-3 登记）**」；同一小节的 `:290` 结论写「因此**正式部署只允许默认路径**，本变量仅作自测/便携用途」。
- 为什么是问题：同一份设计文档在同一条目里，先把它定为"正式特性"，再用现场实证否定它的正式性。§6 的待办（`M0C-C2-INJECT-SMOKE-20261118.md` §6 第 2 项）本意是"把它降级为仅自测用"，但落地时只降级了**结论**、没降级**标题**。
- 技术判断：不能简单说"它没用"——若把该变量设成**用户级/系统级持久环境变量**，它会随进程环境传给游戏进程，确实生效。所以"完全降级为仅自测"会丢掉一个真实可用的便携通道。但"正式特性"这个措辞会让人以为"在 shell 里 set 一下就行"，而那恰恰是不生效的用法（`0916` A 轮实测）。
- 修法建议：措辞统一为「**可选覆盖变量：仅当预设进目标进程的环境（用户/系统级持久变量，或游戏启动器环境）时生效；在 shell 里临时设置不会传给已注入的游戏**」，删掉"正式特性"与"仅作自测/便携用途"这两个互斥说法中的至少一个，并把 `design:290` 的现场实证保留为限制说明。**不需要**改成"仅自测"。

**M-10（中危，新引入，证据链口径不一致）—— ctl 拒绝 loopback，但自检全程用 `127.0.0.1` 作 PIN 目标**

- 位置：`client_selftest.cpp:243` `WriteCfg(cfg, "127.0.0.1\n")`（场景 C）；`:322` 场景 F 首行同为 `127.0.0.1`；场景 H 走 `IFINDEX:`；证据 `0945/cfg/c2-cfg-pinned.txt` = `127.0.0.1`、`c2-cfg-multiline.txt` 首行 = `127.0.0.1`。
- 为什么是问题：DLL 侧 `LoadConfig:122-192` 只校验 `OperStatus == Up`（`:168-187`），**不拒绝 loopback**；而 ctl 侧 `:380-385` 明确拒绝 loopback，理由写在 `:368-370` 注释里：「it is not a deployment target and it made earlier "pinned" evidence look meaningful when it was not」。于是：**C/F 两个"PIN 模式有效"的场景，全部建立在 ctl 明确判定为"不是部署目标"的 loopback 上**。这不影响 `sent` 计数逻辑的正确性（计数发生在 `setsockopt` 返回 0 之后，与目标网卡是否 loopback 无关），但它让"PIN 路径已被验证"这句话只能停留在"记账层"——而这一点 `result.txt:2` 已经声明了，所以**不是造假，是推断成分**：从"C 场景 PIN 生效"推不出"真实网卡 PIN 生效"。
- 修法建议：要么在 `scenario-c.txt`/`scenario-f.txt` 的断言文字里明写"PIN target is loopback; this proves the pin path runs, not that a real NIC egress works"；要么把 C/F 改成用真实的 `192.168.191.3`（`0945` 里可用，T3 已解析出 IfIndex=19）。**不建议**让 DLL 也拒绝 loopback——那会破坏场景 C 的设计意图。

**M-11（中危，未解决）—— 设计 §7.4 与冒烟文档 §7 的采信轮与产物哈希仍是旧值**

- `design:408` 写「证据哈希（采信轮 `C2-iface-selftest-20261118-0928`，29 文件）」，`:409` 写「产物哈希（全量重建后）」但列的是 `DA9844AA…`/`B8640703…`/`C44A8666…`/`5D08DBB0…`。而磁盘现状是 `0BCC4C1D…`/`8B9A9AF8…`/`0AAA32EA…`/`AD14C6C3…`，采信轮是 `0945`。
- `M0C-DUAL-ROLE-PLAN-20261118.md:144` 已写"采信轮 = 0945"，`:162` 已写新产物五值，`:206` 明写"`-0928` 那轮证据对应的二进制已作废，故采信轮已更新为 0945"。
- `M0C-C2-INJECT-SMOKE-20261118.md:131` 仍写产物 `DA9844AA…` / `B8640703…`，而同一文件 `§4.1` 已经证明产物被重建过。
- 为什么是问题：C3 的全部工作就是文档登记。设计与冒烟文档是登记链的上游（`M0C-AUDIT-BRIEF:70` "登记链单向引用"），上游写旧值会让 C3 直接把过期哈希写进对外文档。**这是文档自相矛盾，不是笔误级别。**
- 附带：`design:8` 状态仍写"v2（2026-11-18 09:20）——已实现并通过单机自检（记账层），跨机出接口实测未做"，时间戳停在 09:20 而文件 mtime 是 09:37，可接受但应与修订记录一致。

**M-12（中危，新引入）—— `civlink_hook.h` 里 `sent`/`sendFail`/`ignoredNonDiscovery` 的语义注释与 C2 实现冲突**

- 位置：`civlink\common\civlink_hook.h:37` `unsigned long long sent; // discovery frames successfully handed to the Agent`；`:38` `sendFail; // IPC sendto failed (discovery/notify family)`；`:41` `ignoredNonDiscovery; // sends not forwarded (state off / bad params)`。
- 为什么是问题：C2 复用了同一个 `CivLinkCounters` 结构与同一 magic（`design:210` 明确写"magic 相同 → ctl counters 命令对两个 DLL 原样可用"），但 C2 的 `sent` 含义已是"`setsockopt` 被接受的发现发送次数"（`design:248`），与"C2 没有 Agent、没有 IPC"完全对不上。任何按头文件注释理解 `ctl counters` 输出的人都会读错。这是**跨里程碑复用结构但未重定义语义**留下的陷阱。
- 修法建议：在 `civlink_hook.h` 的注释里分两行写清（hook 侧 / C2 侧）语义，或至少在 `civlink_client.h` 里加一段"字段语义重定义"说明并指向 `design:248-250`。

### 3.3 低危

**L-10（低危，新引入）—— `result.txt` 与 `ps1` 模板写"eight single-process scenarios"，实际九个**

- `run-c2-iface-selftest.ps1:246` 模板行、`0945/result.txt:4-5`。实测场景为 A–I 共 9 个（`ps1:89-97` 场景表 9 行，`client_selftest.cpp:440-485` `case 'A'..'I'`）。因为写在模板里，**每一轮 PASS 都会复制这个错误**。

**L-11（低危，未解决）—— `ps1:224` 断言名与已修正的实现时序相反**

- `Check 'ctl writes ALL before resolving the target'`，条件 `$ctlAllExit -eq 2 -and …`。实现已在 `civlink_ctl.cpp:393-403` 改为"`ResolveTarget` 成功后"写配置，断言名却没改。断言**本身仍会通过**（它是行为断言，不是名字断言），但名字会让后来者以为旧时序是对的——正好是 M-8 那个误区的注脚。

**L-12（低危，未解决）—— `client_selftest.cpp:21-22` 头注释仍宣称 H 是"can actually fail"断言**

- 原文：「B-3 scenario H is the "can actually fail" assertion: an unusable interface index must surface as sendFail > 0. A DLL that never called setsockopt would fail this.」——与同一文件 `:368-372` 处的新结论（H 不能作"能失败"探针，判别力改由 I 承担）**在同一文件内直接矛盾**，也与 `ps1:19` 的 `H impossible ifIndex -> PIN, sent 5, ignored 3, sendFail 0` 矛盾。

**L-13（低危，未解决）—— 设计 §4.4 引用了一个不存在的符号 `ResolveIfIndexForIp`**

- `design:268` 「3. 若 PIN 模式：`ResolveIfIndexForIp` → 0/找不到/down → initError=11/12，降级 g_mode=ALL」。全仓库 grep `ResolveIfIndexForIp` 命中 **0**；实现是 `LoadConfig:122-192` 内联完成（`:143-150` `IFINDEX:` 分支、`:154-187` IPv4→接口解析）。文档虚构函数名会让审阅者找不到对应代码。
- 顺带：该行写的"0/找不到/down → initError=11/12"与实现的对应关系是 `idx==0 → 11`（`:146`）、IP 解析失败 → 11（`:154-155`）、非本地/接口 down → 12（`:187`），文档合并写法模糊但不算错。

**L-14（低危，未解决）—— 残留文件策略被登记为"无需删除逻辑"，未提"配置与注入状态不一致"**

- `design:331`「遗留文件：多次注入覆盖写，无需删除逻辑；改回 ALL 只需重新注入 `--iface ALL`」。这一条与 M-8 是同一个问题的两面：既然承认"覆盖写、无需删除"，就应当承认"失败注入留下的文件会被下次继承"。

**L-15（低危，未解决）—— 设计 §9 估算"`civlink_client.cpp` ~350-400 行"，实际 553 行**

- `design:436`。不影响功能，但会影响后续里程碑的工作量估算。

**L-16（低危，未解决）—— 冒烟文档与 PLAN 的哈希/数值互相不一致**

- `M0C-C2-INJECT-SMOKE-20261118.md` 现为 8,980 B / `EC5838235E3E971CC2FE642DE591DA7D94034269982D5B4793E2A9F06A7A4ECF`，而 `M0C-DUAL-ROLE-PLAN-20261118.md:198` 仍写 `C9CFA8B977EE017AC58B749AEFC0A691C9655874A61DE26E147253C10ECF9BD5`（旧值，因该文件被改过）。
- `PLAN:201` 写「`LoadLibraryW returned 0xfc740000`」，而证据 `0916/inject-pin2.log` 实际是 `0xfc840000`（1,768 B / `D4691CF2…`）。**这是本轮唯一一处"文档数字与证据原文不符"的实质性笔误**，建议改掉——`result.txt`/`PLAN` 里其它数值我都逐个复算过，没有第二处。

**L-17（低危，未解决）—— 本轮自检外壳自身的退出码没有独立证据文件**

- 「exit 0」是从 `0945/result.txt:1` 的 PASS 与 `ps1:238`（`Failures.Count==0 -and Checks==ExpectChecks`）、`:267-270`（PASS→0 / FAIL→1）推出来的，`0945` 目录里没有 runner 自身退出码的落盘文件。**属推断，不是直接证据**。建议下一轮把 `$LASTEXITCODE` 落成 `runner-exit.txt`。

**L-18（低危，未解决）—— 本轮声称的 `HOOK-SELFTEST: PASS (0 failure(s))` 在本轮证据目录中找不到对应日志**

- 全 `M0A\captures` 递归 grep `HOOK-SELFTEST`：只在 `2026-11-14/15` 的 F1/F2 旧目录命中，`0916`/`0940`/`0924`/`0928`/`0945` 五个本轮相关目录**全部 0 命中**。`PLAN:162` 有这句断言，`design:409` 括号里也引用它，但没有可核的 log。→ **未能核实**。要么补一个 `hook_selftest` 的落盘日志，要么在文档里改成"hook 侧 DLL 未改动，回归沿用 11-14 记录"。

---

## §4 证据效力独立评估

不复述任务描述，只给独立结论。

### 4.1 关键追问的直接回答：如果整个 DLL 完全不做 `setsockopt`，自检会不会全绿？

**会全绿——只要计数逻辑还在。**

逐条推演（45 条 runner 断言 = 9 场景 × 3 + 12 条计数器事实 + 6 条 ctl 断言，`ps1:38`）：

| 断言 | 若 DLL 完全不调 `setsockopt` 但仍按规则 `c_sent++` | 若连 `c_sent++` 也不做 |
|---|---|---|
| A 场景（`sent=0 ignored=8`）`ps1:194-195` | 绿 | 绿 |
| B 场景（`initError=11`）`ps1:196-197` | 绿 | 绿 |
| **C 场景（`sent=10 ignored=4`）`ps1:198-200`** | **绿**（`sent` 照样被加 10） | **红** |
| D/E 场景（`sent=0 ignored=8`）`ps1:201-204` | 绿 | 绿 |
| **F 场景（`sent=6 ignored=2`）`ps1:205-206`** | **绿** | **红** |
| G 场景（`initError=12 sent=0`）`ps1:207-208` | 绿 | 绿 |
| H 场景（`sent+sendFail==5`）`ps1:212-214` | 绿（`sent=5` 满足加和） | 绿（`sendFail=0` 时该断言为 `0==5` 假 → 红；但这是巧合，不是设计） |
| **I 场景（`sockOverflow>0`）`ps1:215-217`** | **绿**（`sockOverflow` 由 `Hook_bind` 决定，与 `setsockopt` 无关） | **绿**（同） |
| 9 条"每个 scenario 都有 counters 行"`ps1:189-192` | 绿 | 绿 |
| 6 条 ctl 断言 `ps1:220-235` | 绿（与 DLL 行为无关） | 绿 |

**结论：45 条断言里，没有一条检查 `setsockopt` 是否被真正调用。** 唯一依赖"发现包路径"的是 C4/C5（`sent==10`/`ignored==4`）与 F4/F5（`sent==6`/`ignored==2`），而它们依赖的是**计数器被 +1**，不是"`setsockopt` 真的发出去了"。因此 `result.txt:13` 那句"a DLL that never called setsockopt … would fail both C and I"：

- 对 **I** 是**完全错误**（`sockOverflow` 与 `setsockopt` 无关）；
- 对 **C** 只在"连计数都不做"时才成立，而那不是这句话在说的事。

**这就是第一轮 B-3 `:55`「整个套件在一个只做计数、不做 setsockopt 的 DLL 上同样会全绿」的结论——本轮没有被推翻。** 本轮确实把"重读自己 PASS 文字"改成了"解析机器可读 counters 行"（这是实质进步：删掉了自指断言），但**没有**引入任何独立于 DLL 自报的观测通道。全仓库 `getsockopt` 命中 **0**，`setsockopt` 在 client 侧只有 `civlink_client.cpp:303` 一处，**DLL 从不回读校验该选项是否生效**；`ps1`/`selftest` 也不具备抓包或 `Get-Counter` 能力（`design:373-379` 自己写明 `Get-Counter` 出现 0 次）。

### 4.2 当前证据能证明什么

1. **DLL 能被加载并初始化**：`state==1`、`initError==0`，9 个场景全部成立。
2. **配置解析的三条分支都走通了**：ALL（缺省/显式/空文件）、单行 IPv4、`IFINDEX:<n>`、`ALL` 大小写、多行取首行、非本地 IP → 12。这比第一轮强得多（M-2/M-3 由此关闭）。
3. **计数逻辑与场景预期一致**：`sent`/`ignored`/`sendFail`/`bind62056`/`sockOverflow` 的数值逐场景符合实现推演（我按 `civlink_client.cpp:298-309/:322-326/:391` 手工核算，9 个场景的数值全部对得上）。
4. **槽表溢出不静默**：80 个显式 `bind` vs 64 槽 → `sockOverflow=16`，数字自洽（80−64=16），且 `I4` 断言 `rawBindCalls>=64` 证明确实绑了足够多。
5. **ctl 的三条拒绝路径确实拒绝**：非本地 IP（exit 1）、loopback（exit 1）、目标不存在（exit 2），且有 stdout 原文。
6. **ctl 会打印配置路径来源**：`resolved by: env override` 与 `resolved by: default` 两种都出现过（`0945/ctl-t2-all.txt`、`0916/inject-pin2.log`）。
7. **注入路径真的执行过一次**：`0916/inject-pin2.log` 的 `[+] LoadLibraryW returned 0xfc840000` + `[+] hooks active (CivLinkHookState=1)` + exit 0——这是第一轮"VirtualAllocEx+WriteProcessMemory+远程 LoadLibraryW 从未被执行过"的实质进展。
8. **H-3 的失效机制被现场复现**：A 轮（env override → `sent 0`）vs B 轮（默认路径 → `sent 10`），差值是同一份 DLL 同一个 PIN 目标，只换了配置来源。这比第一轮的推理有力得多。

### 4.3 当前证据不能证明什么

1. **不能证明 `setsockopt(IP_UNICAST_IF)` 被调用，更不能证明它生效。** 理由见 4.1。这是 C2 的核心命题，**一次都没被直接观测过**。
2. **不能证明广播真的从选定网卡发出。** `design:373-379` 自认主判据 `Get-Counter` 未实现；`0916` 冒烟也没做抓包；`scenario-*.txt` 每份尾部都写着 `NOTE: bookkeeping only`。
3. **不能证明能注入真实《文明6》进程。** 宿主是 `powershell.exe`（`M0C-C2-INJECT-SMOKE:5`、`PLAN:196`）。
4. **不能证明长跑稳定**：全场景都是单进程、一次性 burst（`Burst:133-152`，每场景 ≤14 包），没有压力测试，也没有"每包 `setsockopt`"在真实游戏高频发送下的开销数据。
5. **不能证明 62056 数据路径行为**：全部场景 `bind62056=0`，`ctl` 侧也未做。
6. **不能证明异步 `WSASendTo`（`ov != NULL`）路径**：H-2 的代码改对了，但零覆盖（全部场景都是同步 `sendto`）。
7. **不能证明 `scatterGather` 计数正确**：无 `count > 1` 场景，全部为 0。
8. **不能证明 `Hook_recvfrom`/`Hook_WSARecvFrom` 的排空安全**：H-5 未修。
9. **不能证明"45/45 全绿"这一状态本身**：runner 的退出码没有独立落盘（L-17）。

### 4.4 场景 H 与场景 I 的判别力

**场景 H 现在几乎没有判别力。** `client_selftest.cpp:373-397` 配置 `IFINDEX:2147483647`，断言 H1 `state==1`、H2 `initError==0`、H3 8 个包都发出、H4 `sent + sendFail == 5`、H5 `bind62056==0 && okCount==8`、H6 `shutdown==0`。实测 `sent=5 sendFail=0`——即 `setsockopt` 被 Windows **接受**（返回 0）。H4 用加和，因此"`setsockopt` 成功"与"`setsockopt` 失败"两种情况都会 PASS。H 剩下的价值只有：① 证明 `IFINDEX:` 解析路径不崩、不误报 12；② 证明越界索引不会让发送失败。**它不再是"能失败"的探针。**

关于"Windows 对越界 ifIndex 的 `setsockopt` 返回 0 并接受"这个说法：**可信，但不是权威结论**。`design:424-427` 把它登记为"越界索引返回 0 已被实测推翻"，依据就是 `scenario-h.txt` 的 `sent=5/sendFail=0`——这只是**单机单次观测**，不足以成为平台契约。文档已把它列为"不确定项"而非"事实"，这个处理是诚实的；但 `result.txt:13` 又把"能失败"的期望转移到 I 上，那一步不成立。

**场景 I 的 `sockOverflow=16` 是真实的**（80 个显式 `bind` 38000..38079 − 64 槽 = 16，`client_selftest.cpp:414/:421/:435` 与 `civlink_client.cpp:227` 对得上），**但它与 `setsockopt` 完全无关**，因此不能承担"证明 `setsockopt` 存在"的判别力。`result.txt:13` 与 `ps1:25-26` 的错误就在这一句。

### 4.5 `Hook_bind` 只对 `portBe != 0` 建槽——证据链上的推断成分

- 事实：`civlink_client.cpp:391` `if (rc == 0 && portBe != 0) { … FindOrCreateSlot(s); … }`；`client_selftest.cpp:417-419` 注释自认「port 0 is skipped on purpose, so an implicit-bind socket is not assigned a slot」。
- 因此场景 I（`:402-438`）必须用**显式非零端口**（38000..38079）才能撑满槽表——这个约束与真实进程的关系需要分开说：
  - **Civ6 主机侧 bind `0.0.0.0:62900` 是非零端口** → 正常建槽，没有问题。
  - **客户端发现 socket 若走 `sendto` 隐式 bind（端口 0）→ 永远不建槽**。于是"64 槽上限"对真实客户端**可能根本不是压力**：真实游戏客户端同时存在的显式绑定 socket 数量远小于 80，槽表可能永远不溢出。
- 推断成分（必须在文档里标出来）：**场景 I 的溢出是人为构造的 80 个显式绑定 socket**，它证明"满了会被计数而不是静默丢弃"（这条是真的、有价值的），但**不能**推论"真实《文明6》进程里槽表会溢出"或"64 槽够不够"。`design:465-470` 附录 B 的风险表把"槽表 64 满 → 真实计数、场景 I 可观测"列为已覆盖风险，**这一步推论超出了证据**。

### 4.6 关于 `CivLinkShutdown` 安全性论证

`civlink_client.cpp:493-497`：只有 `prev == 1` 才 `MH_DisableHook(MH_ALL_HOOKS)`，然后最多 5 s 等 `g_inFlight == 0`，`left != 0` 返回 2（`design`/`civlink_hook.h:72-76` 契约：调用方必须保持模块映射）。**这个论证对 4 个发送类 detour 成立**（H-1 已修，真实调用在窗口内）；**对 2 个 recv 类 detour 不成立**（H-5，重入分支先递减）。另外 `Prev == 0`（init 未完成）时不 disable——L-8，PLAN 已登记为"有意保留"，我接受这个处置，但建议在 `civlink_client.h` 的 `CivLinkShutdown` 契约注释里写清"init 失败不回滚钩子"。

---

## §5 哈希与时间序核对表

### 5.1 用户点名的四个证据文件（目录 `C2-iface-selftest-20261118-0924`）

**先说一个必须澄清的前提**：`-0924` 在本轮三份文档里**都不是采信轮**。`design:408` 的采信轮是 `-0928`，`PLAN:144` 的是 `-0945`，`M0C-AUDIT-BRIEF:48` 明写「0924/0928 仅供留档，不得作为采信依据」。所以下面这张表里，"文档记录"一栏对 `-0924` 的值**本来就不存在**，一致性只能对 `-0928`（设计）与 `-0945`（PLAN）来做。

| 文件（`-0924`） | 字节 | 独立计算 SHA256 | 设计 §7.4 记录（=`-0928`） | PLAN 记录（=`-0945`） | 与 `-0924` 实际 |
|---|---|---|---|---|---|
| `result.txt` | 1,190 | `B93DE305935CC34ED2FD53CEE207DA939B65C19F148C9DF5C9F57406EDB5ABEA` | `9E8A2E6C…B59B`（0928，1,473 B） | `1CAFEFEA…634B`（0945，1,473 B） | **不一致，且 0924 已被三份文档判为留档** |
| `scenario-c.txt` | 1,019 | `E4E6B9073942362259E5DA52B8771DCA07207FA45937B25D44D9A70171545DB5` | `1C10BC9A…F849` | `9CADB430…9A49` | 不一致（同上） |
| `scenario-i.txt` | 684 | `435B0F9B0799B12534DF3BE6DFA48CD9DBABB0B3F1E60E0354B363C7BAE37A3C` | `5C221117…39D8`（683 B） | `D267280B…8A17`（684 B） | 不一致（同上） |
| `ctl-t1b-loopback.txt` | 279 | `6158FD6C39924F70ACE90D924B72F8B193D953504890D3E7383B7919AAFACEC2` | `6158FD6C…CEC2` | 未单列 | **一致（三者同哈希，内容逐字节相同）** |

`-0924` 的 `result.txt` 里仍写着已被本轮推翻的叙述（"Scenario H is the assertion that can fail … must show up as sendFail > 0"，见 `design:408` 的说明），所以它确实应当留档而不是采信。**这一点文档处理正确。**

### 5.2 采信轮自身的哈希一致性（这一项是关键）

| 文件 | 字节 | 独立计算（`-0945`） | 文档记录 | 是否一致 |
|---|---|---|---|---|
| `result.txt` | 1,473 | `1CAFEFEAF6FF91ECBDC77762A26CA3C33330907A319BB3FB4C2CB5E40848634B` | `PLAN:144` 同值 | **一致** |
| `scenario-c.txt` | 1,019 | `9CADB4305052F1884CA7CDE42E019E5ECF959A400C1EE83A2D235E17ED9F9A49` | `PLAN:144` 同值 | **一致** |
| `scenario-i.txt` | 684 | `D267280B57B9B2769C66BEE9D67C28DDA937D3C7C3690EA403494D2583D38A17` | `PLAN:144` 同值 | **一致** |
| `scenario-h.txt` | 753 | `0C2B680A5048F44EC94AF15A04C88DBB791E53D95EF1143AC0484E24BCF4ED7E` | `PLAN:144` 同值 | **一致** |
| `ctl-t2-all.txt` | 840 | `7F975EB37928E05D092229B25E23A5F1068FDAECF307F988ED4D07B8AD26FB88` | `PLAN:144` 同值 | **一致** |
| `ctl-t3-pin.txt` | 877 | `46439577497697F991E4F2A9FB19CB89A18A6D249CE70505BF921A403B3041F2` | `PLAN:144` 同值 | **一致** |
| 目录文件数 | 39（29 根 + 10 `cfg`） | — | `PLAN:144` 写"29 文件" | **口径差异**：29 是根文件数，含 `cfg` 为 39。`M0C-AUDIT-BRIEF:48` 也写 29。建议统一为"29 根 + 10 cfg" |

**设计 §7.4 的记录整体错位**：它写的是 `-0928`（`design:408`），但那个二进制已被 `PLAN:206` 判为作废。→ 见 M-11。

### 5.3 五个产物的哈希（用户给出的字节数 vs 文档 vs 磁盘）

| 产物 | 字节（用户/磁盘） | 磁盘独立计算 | `design:409` 记录 | `PLAN:162` 记录 | 大小一致？ | 哈希与设计一致？ | 哈希与 PLAN 一致？ |
|---|---|---|---|---|---|---|---|
| `civlink_client.dll` | 149,504 | `0BCC4C1DE6AD8B5E6EC3A13B1F38FDCCD13C9268E651B7B04A73A3051702C6D4` | `DA9844AA0F3997DC68015F68D0074FCC3C4ED9610FB793F4F4382B65D20A538A` | `0BCC4C1D…C6D4` | 是 | **否** | **是** |
| `civlink_ctl.exe` | 188,416 | `8B9A9AF89A652434EC10CA47DFE5DEE34BCE864C3FE539DD737A2B09819ACA22` | `B864070397AEEDDA2FEE7A5A790522820173A75DDB2C9A2567466BCE184F3CD4` | `8B9A9AF8…CA22` | 是 | **否** | **是** |
| `client_selftest.exe` | 181,760 | `0AAA32EA61C9568FC1213C0E5744A9A2D40BBD09B16B41A63F14C588530972BE` | `C44A8666A094C63BBF8A48B4334452497F7D695BC9BE8DA0FDB9CB3B05D24872` | `0AAA32EA…72BE` | 是 | **否** | **是** |
| `civlink_hook.dll` | 119,808 | `AD14C6C3F2E520B8F3559132EA8C9029AC7413FEC6CD53447D9E90FB52957140` | `5D08DBB0829647FAF976BD25FA465FF62AAC074BEE7A04EBB1CF1B0D40445B7B` | `AD14C6C3…7140` | 是 | **否** | **是** |
| `hook_selftest.exe` | 150,016 | `ABF018A20AEF4FC76533ED63F21A511546A0BB9B5AF4224AB1E75B255C44805F` | 未记录（仅括号引 `HOOK-SELFTEST: PASS`） | `ABF018A2…805F` | 是 | 无记录可比 | **是** |

**结论：大小全对，`design:409` 的四个哈希全错（旧二进制），`PLAN:162` 全对。** 设计文档这一处必须重写。

### 5.4 构建序（源码 mtime 早于二进制 mtime）

| 产物 | 产物 mtime | 对应源码 | 源码 mtime | 自洽？ |
|---|---|---|---|---|
| `civlink_client.dll` | 09:21:40.508 | `civlink\client\civlink_client.cpp`（24,334 B / `D617BFC3…`） | 08:58:09.494 | 是 |
| `civlink_ctl.exe` | 09:21:41.439 | `civlink\ctl\civlink_ctl.cpp`（30,658 B / `22EFEF52…`） | 09:21:16.937 | 是 |
| `client_selftest.exe` | 09:21:42.445 | `civlink\selftest\client_selftest.cpp`（20,113 B / `45CF96F5…`） | 09:06:20.786 | 是 |
| `civlink_hook.dll` | 09:21:38.903 | （本轮未改 hook 源码） | — | — |
| `hook_selftest.exe` | 09:21:41.851 | （本轮未改） | — | — |

源码与二进制哈希、`PLAN:162` 记录三方一致；构建序自洽。**唯一的时间序瑕疵**：`design` mtime 09:37:07、`PLAN` mtime 09:37:16 晚于 `0945` 证据轮（09:25:27），但 `design:408-409` 的内容仍停在 `0928` 时代——说明那次修订只改了别处，忘了改 §7.4。

### 5.5 其它文档哈希

| 文档 | 字节/行 | 独立计算 | 文档自身登记 | 一致？ |
|---|---|---|---|---|
| `M0C-C2-REVIEW.md`（第一轮） | 37,556 B / 271 行 | `4E40F2927576CC8214AC2261C288B86256A91782CC1344F4994B3A479856D758` | `design:15`、`M0C-AUDIT-BRIEF:56` 同值 | 是 |
| `M0C-C2-DESIGN-20261118.md` | 40,665 B / 470 行 | `692BE5CB5579BD420D4A54489798A47BB56A5948C4CF0754F926A86023CDA037` | `M0C-AUDIT-BRIEF:55` 同值 | 是 |
| `M0C-DUAL-ROLE-PLAN-20261118.md` | 36,415 B / 260 行 | `D9CAD9EE2676845651620806DC0BE53E80A8FCDCB41AAF91420D9BBC87383F90` | `M0C-AUDIT-BRIEF:54` 同值 | 是 |
| `M0C-C2-INJECT-SMOKE-20261118.md` | 8,980 B / 131 行 | `EC5838235E3E971CC2FE642DE591DA7D94034269982D5B4793E2A9F06A7A4ECF` | `M0C-AUDIT-BRIEF:57` 同值；**`PLAN:198` 仍写 `C9CFA8B9…`（旧）** | 与 BRIEF 一致、与 PLAN 不一致 |
| `M0C-C2-CROSSMACHINE-RUNBOOK-20261118.md` | 8,147 B | `E786058A8C276441B6CD7FB62D0B7C3E08346CDB2E26B1AF508D5CDDEDA2CC27` | `PLAN:210` 同值 | 是 |

---

## §6 进 C3（文档登记）的前置条件

**明确回答：不允许以"C2 已完成"的口径进入 C3 登记。** 允许以"文档订正 + 证据重录"为目的继续，但下列 6 项必须全部落地，否则登记出来的 C2 状态会包含两处失实（H-6/M-11）和一处未修的契约缺口（H-5）。

### 6.1 必须修完才能做 "C2 完成登记"（6 项 = 6 个阻断）

| # | 项 | 具体动作 | 验收 |
|---|---|---|---|
| **1** | 证据自我描述失实（H-6） | 删掉 `run-c2-iface-selftest.ps1:22-26`、`:246-247`（result 模板）里"a DLL that never called setsockopt … would fail both C and I"，改为事实表述：「本套件不观测 `setsockopt` 是否被调用；它只校验计数器与解析路径。C/F 的 `sent` 断言在"计数被 +1"时就通过。」同时把 `:246` 的 `eight` 改成 `nine` | 重跑一轮，新 `result.txt` 里不再出现"would fail both C and I"与"eight" |
| **2** | 设计 §7.4 陈旧（M-11） | `design:408` 采信轮改 `-0945` 并换成六值哈希；`design:409` 产物改四值（+ `hook_selftest.exe` 第五值） | `design` 与 `PLAN:144`/`:162`、磁盘三方一致 |
| **3** | 冒烟 §7 陈旧（M-11 附带） | `M0C-C2-INJECT-SMOKE-20261118.md:131` 产物改新值；`PLAN:198` 的文档哈希改 `EC583823…`；`PLAN:201` 的 `0xfc740000` 改 `0xfc840000` | 三份文档互相一致 |
| **4** | H-5（recv 类排空语义） | 把 `civlink_client.cpp:406-408` 与 `:425-427` 改成 `Real_*` 之后再 `fetch_sub`（照抄 `:414-416`）；若坚持不改，则必须在 `civlink_client.h` 的 `CivLinkShutdown` 契约注释 + `design:272-279` 明确写"排空只覆盖 4 个发送类 detour" | 代码或文档二者之一落地；重跑一轮自检 |
| **5** | 配置残留（M-8） | 三选一：配置写入挪到注入成功之后（推荐）；或失败路径删除；或改写 `civlink_ctl.cpp:398-400` 注释为事实描述，并在 `design:327`/`:331` + 附录 B 登记该风险 | 注释与实现语义一致，或风险已入表 |
| **6** | `CIVLINK_CLIENT_IFACE_FILE` 定性（M-9） | 消解 `design:289`「正式特性」与 `:290`「仅自测/便携用途」的互斥表述，统一为"可选覆盖变量，仅当预设进目标进程环境时生效" | 该小节内不再有互斥措辞 |

**建议同批处理（不阻断，但成本极低、收益明显）**：M-12（`civlink_hook.h:37-41` 语义注释）、M-10（C/F 场景标注 loopback）、L-10/L-11/L-12/L-13（`eight`、断言名、selftest 头注释、`ResolveIfIndexForIp`）、L-16（`0xfc740000`→`0xfc840000`）、L-17（落盘 runner 退出码）、L-18（补 `HOOK-SELFTEST` 日志或改口径）。

### 6.2 必须留到跨机实测（PC-B）阶段解决的

1. **`IP_UNICAST_IF` 是否真的改变出口网卡** —— 唯一能回答的方式是 `docs\M0C-C2-CROSSMACHINE-RUNBOOK-20261118.md` 的三轮对照（`PLAN:212-215`：A 侧 agent 日志看源 IP，Radmin `26.187.101.177` vs WLAN `192.168.31.214`）。这是 C2 的核心命题，**在 PC-B 之前无法关闭**。
2. **`Get-Counter` / `pktmon` 主判据** —— `design:373-379` 自认未实现，「Packets Sent/sec 对虚拟接口不可靠」（第一轮前提 8），需在 PC-B 时换 `Bytes Sent/sec` 或 `pktmon`。
3. **真实《文明6》进程内注入** —— `0916` 只用了 `powershell.exe`；`civlink\run-c2-real-game-check.ps1`（198 行 / `8E83FF8B…`）已写但 **`PLAN:224` 与 `M0C-AUDIT-BRIEF:12-18` 都标注"未执行过"**。
4. **长跑 / 每包 `setsockopt` 开销**（`design:424-427` 已列为不确定项）+ **游戏 socket 跨网卡复用**、**接口索引漂移**（附录 B `:465-470`）。
5. **槽表 64 满在真实进程中是否可达** —— 见 §4.5，这是推断不是结论。
6. **双人联机能力本身** —— `M0C-C2-INJECT-SMOKE:94-107` 自认"没证明"；`PLAN:204` 明写"不得据此勾 E2-A/E2-B/E3"。

### 6.3 允许勾选的项

按现有证据，C2 可以登记为：**「C2-a：单机记账层与配置解析层通过（9 场景 / 60 in-process checks / 45 runner checks）；C2-b：真实出接口与真实进程注入未验证」**。**不得**登记为整体"完成"或"已验证"。

---

## §7 边界提醒

1. **本轮全部证据都是单进程簿记证据。** 每一份 `scenario-*.txt` 尾部都印着 `NOTE: bookkeeping only - the actual egress adapter is NOT verified here`；`result.txt:2` 印着 `Egress adapter: NOT VERIFIED`。这两行不是客套话，它们的含义是：**没有任何一条断言观测到网络出口**。
2. **`setsockopt` 是否存在、是否生效，本轮证据零覆盖。** 详见 §4.1：把 `civlink_client.cpp:303` 整行删掉、只保留 `c_sent++`，45 条断言仍会全绿。因此"PIN 模式已实现"只能说"已写代码并计数"，不能说"已验证生效"。
3. **PIN 场景（C/F）的目标是 loopback `127.0.0.1`**，而 ctl 明确拒绝 loopback 作为部署目标（`civlink_ctl.cpp:380-385`）。这两件事同时成立，说明 C/F 证明的是"pin 路径被执行且被计数"，不是"某块真实网卡被定向"。
4. **注入成功仅有一次宿主为 `powershell.exe` 的冒烟**（`0916`），且该轮暴露了三个环境障碍（`M0C-C2-INJECT-SMOKE:22-32`）。《文明6》进程、反作弊、游戏自身的 socket 行为均未触及。
5. **冒烟轮的 A/B 差异是 H-3 的失效机制**，不是"测试写错"——`M0C-C2-INJECT-SMOKE:53` 与 `PLAN:202` 的解释正确。这一条应当保留为文档资产。
6. **`sockOverflow=16` 来自人为构造的 80 个显式绑定 socket**，不能外推为"真实客户端会溢出"（§4.5）。
7. **场景 H 已不再是"能失败"探针**，`result.txt:13` 关于 I 承担判别力的说法不成立；当前套件对"`setsockopt` 存在性"没有任何判别力。
8. **`-0924` 与 `-0928` 是留档轮**，`-0945` 才是采信轮；引用证据时必须写对目录（`design:408` 现在写错）。`-0915`/`-0920` 两轮 `FAIL (45/41 runner checks)` 未在设计与 PLAN 中登记——**这不是造假，反而说明"45/45 自洽检查"真的能拦住问题**，建议在 PLAN 的时间线里补一笔，作为脚本有效性的证据。
9. **我未运行任何被测程序、未反编译、未做跨机实测。** 所有"通过/失败"的结论都来自读证据文件与读源码，不是复现。

**综合：不得把 C2 表述为"已验证"。** 它可以被表述为「已实现并通过单机记账层自检；出接口生效性、真实进程注入、长跑稳定性三项待 PC-B」，但这三句话必须同时出现，缺一即失实。

---

## §8 复审期间增量裁定（09:16 之后的 3 件事）

### 8.1 `civlink_ctl` 自动探测修复（`M0C-C2-INJECT-SMOKE` §4.1，证据 `C2-inject-smoke-20261118-0940`）

**裁定：接受，且这是本轮最有价值的增量。**

- 发现的问题是真的：`status`/`counters` 未给 `-m` 时按默认 `civlink_hook.dll` 解析本地导出 RVA，对 client 注入的进程报 `cannot resolve CivLinkHookState` exit 1，用户会读成"注入失败"。
- 修复属实：`civlink_ctl.cpp:411-423`（`OpenProcess` 成功后、未显式 `-m` 时，目标未加载 hook 则切 client 并打印 `[*] target has civlink_client.dll loaded - using it (override with -m)`）。
- 复验证据齐全：`0940/status-auto.log` 672 B / `613FADC5…`、`counters-auto.log` 1,928 B / `09A779F2…`、`inject.log` 1,768 B / `92D19408…`，与 `PLAN:203` 记录一致。
- **代价**：修复改了 `civlink_ctl.cpp`（30,658 B / `22EFEF52…`，09:21:16），五个产物全部重建（09:21:38–09:21:42），**`-0928` 那轮证据的配套二进制就此作废**。`PLAN:206` 对此处理正确（采信轮更新为 `-0945`），**但 `design:408-409` 没有跟着更新**——这就是 M-11 的成因，也是它必须作为阻断项的原因。

### 8.2 真实进程注入冒烟（`C2-inject-smoke-20261118-0916` / `-0940`）

**裁定：接受其"证明力"，但必须严格限定在它自己写的范围内。**

- 它关闭了第一轮前提 9 里最关键的一句话：「VirtualAllocEx+WriteProcessMemory+远程 LoadLibraryW 这段从未被执行过」。现在执行过了：`0916/inject-pin2.log` 有 `[+] LoadLibraryW returned 0xfc840000`、`[+] hooks active (CivLinkHookState=1)`、exit 0。
- 它把 H-3 从"推理"升级为"实测"：A 轮 env override → `sent 0 / ignored 14`；B 轮默认路径 → `sent 10 / ignored 4 / raw sendto 14`；C 轮 ALL → `sent 0 / ignored 14`。这是同一 DLL、同一 PIN 目标、只换配置来源的三轮对照，**解释正确**（不是"测试写错"）。
- 宿主差异被如实登记：`M0C-C2-INJECT-SMOKE:5`、`PLAN:196` 都写"用 `powershell.exe` 作宿主代替游戏进程"；`:94-107` 列了 4 条"没证明"。
- **两点瑕疵**（不改变结论）：① 文档原写"19 文件"，实际 18 文件（现版 `:4` 已改为 18，但 `PLAN:198` 的文档哈希因此过期）；② `PLAN:201` 的 `0xfc740000` 与证据 `0xfc840000` 不符。

### 8.3 五产物哈希全变

**裁定：属于正常的重建后果，但登记链没有同步，构成阻断。**

- 原因链清楚：`civlink_ctl.cpp` 修复 → 重建 5 产物 → `-0928` 二进制作废 → 重跑 `-0945`。哈希变化本身**不是异常**。
- 问题在登记：`design:409`（4 个旧哈希）、`M0C-C2-INJECT-SMOKE:131`（2 个旧哈希）仍是旧值，而 `PLAN:162`、`M0C-AUDIT-BRIEF`、磁盘三者已经一致。C3 是文档登记里程碑，**上游写旧哈希会直接把错误数字固化成对外事实**。
- 时间序核验通过：全部源码 mtime 早于对应二进制（§5.4），说明变化不是"改了源码没重编"。

---

## 附录：本报告的独立核对命令（可复现）

```powershell
# 证据哈希
$cap="C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\C2-iface-selftest-20261118-0945"
Get-ChildItem $cap -File | ForEach-Object { "{0} {1} {2}" -f $_.Name,$_.Length,(Get-FileHash $_.FullName -Algorithm SHA256).Hash }

# 产物哈希与构建序
$b="C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit\civlink"
Get-ChildItem $b -Filter *.dll | Get-FileHash -Algorithm SHA256
Get-ChildItem $b -Filter *.exe | Get-FileHash -Algorithm SHA256
Get-ChildItem $b -Recurse -Include *.cpp,*.h,*.cmd,*.ps1 | Select-Object FullName,Length,LastWriteTime

# 关键代码位置
Select-String -Path "$b\client\civlink_client.cpp" -Pattern "fetch_sub|setsockopt|prev == 1|portBe != 0"
Select-String -Path "$b\run-c2-iface-selftest.ps1" -Pattern "would fail|eight|before resolving"
Select-String -Path "$b\..\..\M0A\captures\*\*.txt" -Pattern "HOOK-SELFTEST"
```

*本报告只读完成；除本文件外未修改任何源码、二进制或证据。*
