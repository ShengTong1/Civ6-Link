# M0-C / C2 独立审计报告

- 审计对象：C2 = B 机客户端定向网卡注入物 `civlink_client.dll`
- 审计依据：`docs\M0C-C2-DESIGN-20261118.md`（439 行）、`docs\M0C-DUAL-ROLE-PLAN-20261118.md`（121 行）
- 被审文件：`civlink\client\civlink_client.cpp`(509)、`civlink\common\civlink_client.h`(30)、`civlink\selftest\client_selftest.cpp`(269)、`civlink\ctl\civlink_ctl.cpp`(599)、`civlink\build-msvc.cmd`(167)、`civlink\run-c2-iface-selftest.ps1`(180)
- 证据目录：`M0A\captures\C2-iface-selftest-20261118-0834`（15 个顶层文件 + `cfg\` 4 个文件）
- 审计方式：全文逐行阅读 + 本机 `Get-FileHash` 复算 + 证据文件逐字节阅读 + 实现语义手工推演（未运行被测程序，未修改任何源码）
- 审计日期：2026-11-18

---

## 1. 裁定

**有条件通过。**

理由：只读约束在代码层面确实成立（全文无 `send`/`recv` 伪造、无 `bind 62056`、无 `SO_REUSEADDR`、无复制重发），配置无效 fail-open 到 ALL 的路径成立，`CivLinkShutdown` 符合 B2 契约（不 `MH_Uninitialize`、无复活路径），4 项哈希与时间戳全部一致；但存在三处必须先修的问题：**(a)** `pinned` 标记对"从未 bind 过的 socket"永远写不进去，导致每个发现包都重复 `setsockopt`，`sent` 计数器在"有 bind"与"无 bind"两条路径上语义分裂，C4 判据在真实 Civ6 进程上会失败；**(b)** `setsockopt` 失败会污染 `last error`，违反"同 last error"硬约束；**(c)** 25 项检查中无一条能判别 `IP_UNICAST_IF` 对 255.255.255.255 是否生效，其中 10 条是对子进程自身 stdout 的字符串匹配，且 §7.3 第 3 项要求的 `ignoredNonDiscovery==0` 与实测的 4 直接相反。因此不能按"已验证定向能力"进入下一步，只能按"记账层验证通过"结项。

**⚠ 审计期间的源码漂移（必读）**：本报告第 2–6 节针对的是**审计开始时的快照**（`civlink_client.cpp` 509 行、`client_selftest.cpp` 269 行，二进制与证据为 08:30–08:34 那一批）。审计过程中，工作区源码被第三方改动（`civlink_client.cpp` → 553 行 @08:57:32、`client_selftest.cpp` → 432 行 @08:59:12），其中多条修订明确引用了本报告的编号（文件头新增 `Audit revision (M0C-C2-REVIEW.md, 2026-11-18)` 段）。**但二进制、证据、自检脚本均未重建/重跑/更新**，因此当前处于"源码已改、证据仍是旧版"的状态：下面每一处"已修"都只表示**代码改动能对上我的建议**，**不表示修对了、更不表示验证过**。逐条状态见 **附 A**。

---

## 2. 阻断项（必须修才能进下一步）

### B-1 `pinned` 位对未 bind 的 socket 永远不生效；`sent` 语义分裂，C4 判据在真实场景下必失败

- 位置：`civlink\client\civlink_client.cpp:263-277`（`PinSend`）、`civlink_client.cpp:289-293`（`Hook_sendto` 判定）、`civlink\selftest\client_selftest.cpp:216`（C4 断言）
- 事实链：
  1. 槽位只在 `Hook_bind`（`civlink_client.cpp:334-356`）里创建：`if (rc == 0 && portBe != 0)` 才 `FindOrCreateSlot`。`Hook_sendto` 从不创建槽位。
  2. `PinSend` 里 `SlotIsPinned(s)`（`civlink_client.cpp:268`）对未建槽的 socket 恒返回 `false`；`setsockopt` 成功后 `SlotMarkPinned(s)`（`:272`，实现于 `:214-220`）内部 `if (sl) sl->pinned = true;` —— 找不到槽就**静默不标记**。
  3. 于是：未 bind 的 socket 每发一个发现包，就重新 `setsockopt` 一次并 `c_sent++` 一次。
- 后果：
  - 自测 C 场景只创建**一个** socket（`client_selftest.cpp:207`）发 10 个发现包，`c_sent` 得 10，`c.sent == kDiscovery` 成立（`client_selftest.cpp:216`）——**这是缺陷的产物，不是"每个发现发送都被 pin"的证据**；它与 `civlink_client.cpp:266-267` 的注释（`count only the first pin so sent == sockets pinned`）自相矛盾。
  - 真实 Civ6 的发现 socket 通常会先 `bind`（或隐式绑定后再次 bind）→ 槽位存在 → `pinned` 生效 → 此时 `sent` 恒为 **1**。设计 §7.3 第 3 项（`sent==N`）在真实进程上会**必然失败**，该断言不可用于下一步验证。
  - 每次发现发送多一次 `setsockopt`（幂等、代价小，但属于非必要副作用，且使计数器失去意义）。
- 修法（二选一，推荐 1）：
  1. 在 `Hook_sendto`/`Hook_WSASendTo` 判定为发现目标后先 `FindOrCreateSlot(s)`（或在 `PinSend` 内部做 `find-or-create`），让 `pinned` 位有地方落。同时把 `c_sent` 改成**两个计数器**：`pinnedSockets`（成功 pin 的 socket 数，=1/socket）与 `pinCalls`（`setsockopt` 调用次数）；`CivLinkCounters` 结构版本号 +1。
  2. 或放弃 `pinned` 位，每次发现发送前无条件 `setsockopt`（幂等、约 1µs），把 `c_sent` 明确定义为"发现发送次数"，与 §7.3 第 3 项一致 —— 代价是每包一次系统调用，换来"设置在 implicit bind 之后必然发生"的时序保障（见 M-6）。
- 验证方式：改成 1 之后，用**同一个已 bind 的 socket**再跑一次 C 场景，期望 `pinnedSockets==1`；C4 断言改成 `pinnedSockets==1 && pinCalls==1`。

### B-2 `setsockopt` 失败会覆盖 `last error`，违反"同 last error"硬约束

- 位置：`civlink\client\civlink_client.cpp:269-276`（`PinSend` 内 `setsockopt`），调用点 `:291`、`:312`
- 事实：`PinSend` 在 `Real_sendto`/`Real_WSASendTo` **之前**执行 `setsockopt`。当 `setsockopt` 返回非 0（`sendFail` 路径）时，线程的 Winsock 扩展错误码被改成 `WSAEINVAL`/`WSAENOTSOCK` 等；随后 `Real_sendto` 成功返回 4 —— 应用在成功的 `sendto` 之后调 `WSAGetLastError()` 拿到的是**我们留下的错误码**。未 hook 路径下该错误码保持不变。这是可观测的行为差异。
- 修法：`PinSend` 内先 `const int savedErr = WSAGetLastError();`，`setsockopt` 之后 `WSASetLastError(savedErr);`（`sendFail` 分支必须恢复；成功分支也建议恢复，避免实现依赖"setsockopt 成功时不动错误码"这一未文档化行为）。`Hook_WSARecvFrom:390` 只读不写，无需处理。
- 备注：这是窄但真实的硬约束违反，属于"违反即为必改"。

### B-3 证据效力不足 + 证据表述与判据表冲突，不能支撑"定向能力已验证"

- 位置：`civlink\run-c2-iface-selftest.ps1:140-153`（10 条自指断言）、`:124-137`（真实断言）、`M0A\captures\C2-iface-selftest-20261118-0834\result.txt`、设计 §7.2 `L361-365` / §7.3 `L369-380`
- 事实：
  1. `result.txt` 首行是 `C2-IFACE-SELFTEST: PASS (25 checks)`。这个 25 是 **PS1 自身**的 `Check` 调用数：12 条（每个场景的 exit==0 / `ran==Expect` / `failed==0` / 无 FAIL 行）+ 10 条自指字符串匹配 + 3 条 ctl 断言。DLL 内部另有 24 条断言（8+6+10），只被 `failed==0` 间接覆盖。标题把两种效力完全不同的检查混成一个数字。
  2. 那 10 条（`:140-153`）全部形如 `($scenarioText['A'] -match 'PASS A5 sent == 0')`，即**匹配子进程自己打印的字符串**。它们不能独立证伪任何东西；真正有判别力的是 `:132` 的 `(\d+) checks, (\d+) failed` 解析与 `:133` 的 `failed==0`。
  3. 设计 §7.2 的主判据"逐接口 `Get-Counter "\Network Interface(*)\Packets Sent/sec"` 增量"在脚本里**出现 0 次**；§7.3 第 4 项（PIN 模式目标网卡增量 ≥ N/2、非目标 ≈ 0）与第 5 项（ALL 模式广播仍走 metric 最小接口）**完全未实现**。这两项才是"B 是否生效"的判据。
  4. §7.3 第 3 项要求 `ignoredNonDiscovery==0`，实测 C5 为 **4**（普通发送计入）。即设计断言表与实测结果**直接矛盾**，而报告未标注。
  5. 断言集的性质：全部 24 条 DLL 断言都在检查**内存里的计数器**；没有一条会在"`IP_UNICAST_IF` 完全无效"时失败。整个套件在一个只做计数、不做 `setsockopt` 的 DLL 上同样会全绿（前提是计数器写对）。
- 修法：
  - `result.txt` 标题改为 `C2-BOOKKEEPING-SELFTEST: PASS (24 dll checks / 12 wrapper checks)`，并另起 `Egress adapter: NOT VERIFIED`。
  - `run-c2-iface-selftest.ps1` 中把 10 条自指断言删掉（它们与 `failed==0` 重复且误导），换成正向断言：直接读 `scenario-c.txt` 的 `sent`/`ignoredNonDiscovery` 数值并与期望表比对（从 `PASS C4 sent == 10` 里抠数字仍然自指，应改为让 `client_selftest` 输出 `counters: sent=10 ignored=4` 的机器可读行）。
  - 在 §7.3 表里逐条标注 `covered / uncovered / contradicted`，明确写下"第 4、5 项未实现，第 3 项与实测相反（实际为 4 而不是 0，因语义不同）"。
  - 加一条**能失败**的断言：`setsockopt` 用一个非法 ifIndex（如 `0x7FFFFFFF`）调用应返回失败并计入 `sendFail`，证明"pin 失败可被观测"。

---

## 3. 高危 / 中危 / 低危

### 高危

**H-1 `g_inFlight` 在 4 个 detour 里于真实调用之前就递减，shutdown 的"排空"语义不成立**
`civlink_client.cpp:294-296`（sendto）、`:315-317`（WSASendTo）、`:329-331`（closesocket）、`:353-355`（bind）四处都是 `tlsInHook = false; g_inFlight.fetch_sub(1); return Real_*(...);` —— 真实调用发生在**记账窗口之外**。
`CivLinkShutdown`（`:445-457`）用 `g_inFlight==0` 判定排空完成，并以此决定返回 0（注释写着"2: caller must keep the module mapped"，即返回 0 表示"可以安全卸载/继续"）。由于递减在真实调用之前，返回 0 时仍可能有线程卡在真实调用里——典型场景：阻塞 socket 的 `sendto` 遇上发送缓冲区满（UDP 罕见但可能）、`closesocket` 撞上 `SO_LINGER`（`bind` 本身通常不阻塞，但它在四处里属同一处复制粘贴错误，应一并改）。对照 `Hook_recvfrom:370-373` 与 `Hook_WSARecvFrom:389-393` 是把 `Real_*` 包在窗口内的正确写法，可见这四个是**同一处复制粘贴错误**，而非设计取舍（`CivLinkShutdown:450-453` 的 `// drain up to 5 s` 注释说明意图就是要覆盖真实调用）。
补充一句以免夸大：MinHook 的 `MH_DisableHook` 内部会挂起其余线程再改回原字节，且 trampoline 内存要到 `MH_RemoveHook`/`MH_Uninitialize` 才释放（本 DLL 两者都不调用），所以**不是**"禁用瞬间必然崩溃"。真实风险是**契约层面**的：`shutdown()==0` 被当作"进程内已无本 DLL 的发送活动"的凭据，而它测的是"已离开 detour 记账段"，两者不等价；任何依赖该返回值的后续动作（卸载、关闭 socket、切换配置）都可能与仍在执行的真实调用竞争。
修法：四处统一改为 `const int rc = Real_*(...); tlsInHook = false; g_inFlight.fetch_sub(1); return rc;`（照抄 recvfrom）；`CivLinkShutdown` 的返回值含义在 `civlink_client.h` 与设计文档里写清"只保证已无线程停在计数段内"。

**H-2 overlapped `WSASendTo` 被排除在 pin 之外，且被计成"非发现发送"**
`civlink_client.cpp:310-311` 的判定含 `!ov`。若 Civ6 用 overlapped `WSASendTo` 发发现广播，则永远不会被 pin，而被计入 `ignoredNonDiscovery`。`setsockopt` 与同步/异步无关，`!ov` 没有任何技术理由。
修法：去掉 `!ov`（保留 `bufs && count>=1`）；异步完成计数另设计数器，不要复用 `ignoredNonDiscovery`。

**H-3 `CIVLINK_CLIENT_IFACE_FILE` 未文档化，且 ctl 侧设置不会传递给目标进程**
- 实现：`civlink_client.cpp:78-92` 先读该环境变量；`civlink_ctl.cpp:230` 同样优先读它。设计文档全文 **0 处**提及该变量（只有 `%LOCALAPPDATA%` 与 `civlink_client.h:21`）。
- 后果：用户在 shell 里 `set CIVLINK_CLIENT_IFACE_FILE=...` 后运行 `civlink_ctl inject-client --iface 192.168.1.5`，ctl 把配置写到覆盖路径；但 DLL 运行在**目标游戏进程**里，读的是游戏进程的环境（通常没有这个变量）→ 回落到 `%LOCALAPPDATA%\CivLink\client-iface.txt` → **定向配置静默失效，DLL 以 ALL 模式运行，`initError==0`，看不出任何异常**。除非该变量是系统级设置（则两边一致）。
- 修法：ctl 在写入前打印最终生效路径（已有 `[+] ... -> path`），再打印一行 `resolved by: env override / default`；并在 `inject-client` 提示"若使用环境变量覆盖，请确保目标进程环境同样存在该变量"。更稳的做法：该变量**降级为仅自测用**（自测进程内 `SetEnvironmentVariable` + `LoadLibrary` 已在同一进程，天然一致），正式路径只走 `%LOCALAPPDATA%`；若要保留为便携特性，必须在设计 §5.1 登记。

**H-4 ctl 的 `--iface` 预校验接受 loopback 与任意 up 的 IPv4，不校验接口类型/不提示 metric**
`civlink_ctl.cpp:194-220`：只做 `inet_pton` + `GetAdaptersAddresses` 匹配 + `OperStatus==IfOperStatusUp`。`127.0.0.1` 因此被接受（证据 `ctl-t3-pin.txt` 就是用它），于是**本轮的"定向真实网卡"证据实际上是把广播钉到 loopback 伪接口**。用户若误填 loopback 或其他非联机网卡，会静默产生无效甚至有害的配置。
修法：拒绝 `IfType == IF_TYPE_SOFTWARE_LOOPBACK`；打印所选适配器 `FriendlyName / IfIndex / IfType / metric`；若所选接口不是"非 loopback 且 metric 非最小"，打印警告（`[!] note: <iface> is not the lowest-metric interface; this is the intended behaviour for C2, confirm it is the LAN card`），并支持 `--yes` 跳过。

### 中危

**M-1 槽表 64 满时静默失败，`sockTableOverflow` 恒为 0**
`FindOrCreateSlot:175-186` 满时返回 `nullptr`；`Hook_bind:348` 忽略返回值；`civlink_client.cpp:474` 硬编码 `out->sockTableOverflow = 0;`，而设计 §4.3 L246 把它定义为"槽满次数"。后果：满表后 pin 永不可标记（回到 B-1 的重复 `setsockopt`），且监控不可见。
修法：`FindOrCreateSlot` 满时 `c_sockOverflow++`；导出真实值。

**M-2 `LoadConfig` 的显式 `ALL`、空文件、多行三个分支零覆盖**
场景 A 用"文件不存在"（`client_selftest.cpp:133-134` `DeleteFileA`），场景 B 用 `not-an-ip`。设计 §5.1 L287 声称"缺文件/空文件 → ALL 且 `initError` 保持 0"、L284 声称"多行只取第一行"、`civlink_client.cpp:112` 有 `_stricmp(line,"ALL")==0` 分支 —— 三者都没有任何测试。T2 写了 `ALL` 文件但**从未有进程加载它**。
修法：加场景 D（写 `ALL`，期望 `state==1 && initError==0 && sent==0`）、场景 E（空文件）、场景 F（两行 `ALL\nBAD`，期望取第一行）。

**M-3 `initError==12`（接口不可用）无任何证据**
设计 §7.3 第 7 项明写用 `192.168.99.99` 验证 12；实测只测了 11（`client_selftest.cpp:173`）。`civlink_client.cpp:130`（`GetAdaptersAddresses` 失败）与 `:149`（找不到 up 的匹配地址）两条路径都未被执行。
修法：加场景 G（`192.168.99.99`，期望 `state==1 && initError==12 && sent==0`）—— 注意该地址格式合法、本机不存在，正好命中 `:149`。

**M-4 设计 §4.3 的 `initError` 编号表与实现、与头文件三处不一致**
设计 L252 写"2..7 `MH_CreateHook` 失败 / 8 `MH_Initialize` / 9 `MH_EnableHook`"；实现是 `3 = MH_Initialize`（`civlink_client.cpp:412`）、`4..9 = 六次 CreateHook`（`:413-430`）、`10 = EnableHook`（`:431`）；`civlink_client.h:26` 的"in addition to the civlink_hook.h range 1..10"是对的。**实现与头文件一致，设计文档错**（疑似沿用了含 IPC 的 `hook.cpp` 编号，其 `2` 是 ipcSock）。修法：改设计 L252 为 `1 WSAStartup / 3 MH_Initialize / 4-9 CreateHook / 10 EnableHook / 11 配置无效 / 12 接口不可用`，并注明 `2` 保留未用。

**M-5 `scatterGather` 恒 0，与文档定义不符**
`civlink_client.cpp:473` 硬编码 0；设计 §4.3 L245 定义它为"WSASendTo 多 buffer 次数（保留，通用）"。既然保留了字段就应计数（`Hook_WSASendTo` 里 `if (count > 1) c_scatterGather++`），否则把字段从文档里删掉。

**M-6 "只 pin 一次、且在 implicit bind 之前"这一时序未经论证，与设计自身表述冲突**
设计 §3.2 L124 与 §4.4 L268 都写"**每次发送前**设置"，§3.2 L124 还说"该选项在 bind 前调用时，到 bind 时才检查"。实现是"每 socket 只设一次"（`civlink_client.cpp:266-268`）且发生在 `Real_sendto` **之前**（隐式 bind 尚未发生）。若 MSDN 那句"到 bind 时才检查"成立，则当前实现可能被随后的隐式 bind 抹掉，定向整体失效——而这正是本轮**无法用单机证据排除**的风险。
修法：采用 B-1 的方案 2（发现目标每包 `setsockopt`，幂等、代价可忽略），既消除时序风险，也让 `sent` 语义与 §7.3 第 3 项一致；或明确写下"已验证 bind 不会重置该选项"并给出依据（本轮无依据）。

**M-7 证据生成端"passing for the wrong reason"未披露**
`scenario-c.txt` 的 C4 之所以 PASS 是因为 B-1 的缺陷（未 bind → 每包重设）；报告/证据没有任何地方说明这一点。下一步若有人把 C4 当作"每包都 pin 了"的依据去验收逻辑，会得到错误结论。修法：在证据目录加 `findings.md` 或在 `result.txt` 追加一行 `C4 note: socket is never bound, so the pinned flag cannot be stored; sent counts setsockopt calls, not pinned sockets`。

### 低危

- **L-1** `WSAStartup`（`civlink_client.cpp:401`）无配对 `WSACleanup`。进程级无害（DLL 常驻），但属资源记账不完整；可在 shutdown 里补一次（注意与其他 DLL 的引用计数交互，故建议仅在注释中说明"故意不清理"）。
- **L-2** `IsDiscoveryTarget:235-242` 把"任意发往 `255.255.255.255` 的包"（不限端口）都算发现，而"子网定向广播 `192.168.x.255`"不算。Civ6 用的是前者（有 `civlh2.h:63-65` 与场景实现佐证），但应在设计 §4.1 写明该口径，避免后续误判。
- **L-3** 计数器在 ALL 模式下的语义未说明：`PinSend:265` 在 `g_mode==ALL` 时也 `c_ignoredNonDiscovery++`，因此场景 A 的 A6 期望 8（=5 发现 + 3 普通）。设计 §4.3 L242 把 `ignoredNonDiscovery` 定义为"非发现发送被跳过 pin 的次数"，二者不一致。修法：把该计数器改名为 `notPinnedSends`，或把 ALL 模式的发现发送计入独立计数器。
- **L-4** `state != 1` 期间（初始化窗口、初始化失败、shutdown 后残留钩子）的所有发送都进 `c_ignoredNonDiscovery++`，同样污染语义。
- **L-5** `client_selftest.cpp:66-68` 未 `GetProcAddress("CivLinkSessionId")`，四导出之一没有任何测试触碰（`build-msvc.cmd:111-120` 只验证导出存在）。建议加一条断言。
- **L-6** `client_selftest.cpp:77-87` 的 `WaitReady` 只轮询 `state==1`，不因 `initError` 提前失败，最坏白等 5 秒；无害但降低失败信息量。
- **L-7** `build-msvc.cmd:88-91` 的 `CIVLINK_SKIP_CLIENT_DLL` 会**直接复用旧 dll 且跳过导出校验**，存在"改了源码、忘了清开关、用着旧二进制"的风险。建议 skip 分支至少比较 `civlink_client.dll` 与 `client\civlink_client.cpp` 的时间戳，旧则报警。
- **L-8** `CivLinkShutdown` 在 `prev == 0`（初始化未完成/失败）时不调 `MH_DisableHook`（`civlink_client.cpp:449`），若 `MH_CreateHook` 部分成功后 `EnableHook` 失败，钩子仍以"已创建未启用/部分启用"状态留存且永不清理。当前行为安全（detour 内 `g_state==1` 已为 false，全部透传），但应在注释里写明"init 失败路径不回滚钩子，进程存活期内不可复用"。
- **L-9** 设计 §5.1 L290-312 的示例代码使用 `GetEnvironmentVariableA("LOCALAPPDATA", ...)` 硬编码，与实现（先查 `CIVLINK_CLIENT_IFACE_FILE`）不一致；示例里 `if (idx <= 0) return 12;` 也与实现（`foundUp` 判定）不同。示例应标注"示意，非实现"。

---

## 4. 证据效力评估表

说明：下表"能证明"一栏只写该断言**逻辑上排除**了什么；"不能证明"写它**看起来想证明但实际排除不了**什么。

### 4.1 DLL 内部断言（`client_selftest.cpp`，共 24 条）

| 断言 | 能证明 | 不能证明 |
|---|---|---|
| A1 `state==1` | 6 个 `MH_CreateHook` 与 `MH_EnableHook` **全部成功**（任一失败即 `return 1`、`state` 停在 0，见 `civlink_client.cpp:412-433`）—— 这条比看起来强 | 钩子**行为**是否正确（只证明装上了）；`initError` 是否是 11/12（由 A2 单独覆盖） |
| A2 `initError==0`（文件缺失） | 缺文件不报错、不阻塞 | 若文件存在且内容为 `ALL`，行为相同（未测，M-2） |
| A3 `sessionId!=0` | 会话 id 已生成 | 唯一性（PID<<32^QPC 碰撞概率可忽略，但未验证） |
| A4 8 个发送返回 4 字节 | 钩子没有破坏正常发送 | 报文是否真的出网卡；`sendto` 返回 4 只表示进了协议栈队列 |
| A5 `sent==0`（ALL） | ALL 模式不调用 `setsockopt` | 无（这条是干净的） |
| A6 `ignoredNonDiscovery==8` | 5 发现 + 3 普通在 ALL 模式都被计数 | 与 §4.3 的"非发现发送"定义一致（不一致，L-3） |
| A7 `sendFail==0` | 无失败 | 无（干净） |
| A8 `shutdown()==0` | 排空窗口内 `g_inFlight` 归零 | 真实 sendto 是否仍在执行（H-1：窗口提前关闭） |
| B1 `state==1`（非法配置） | fail-open 不阻塞加载 | 加载后钩子是否真的在工作（未验证发送行为以外的钩子状态） |
| B2 `initError==11` | 非法字符串被识别为配置无效 | 11 与 12 的分支是否正确（12 从未触发，M-3） |
| B3 8 个发送返回 4 字节 | 降级后仍可发包 | 同上 |
| B4 `sent==0` | 降级为 ALL | 无 |
| B5 `ignoredNonDiscovery==8` | 同上 A6 | 同上 |
| B6 `shutdown()==0` | 同上 A8 | 同上 A8 |
| C1 `state==1` | PIN 模式初始化成功 | 无 |
| C2 `initError==0` | `127.0.0.1` 被解析为本地 up 接口 | 该接口是否是**真实**网卡（是 loopback，H-4） |
| C3 14 个发送返回 4 字节 | pin 之后发送路径未被破坏 | 报文是否到达任何地方；pin 是否真的改变了出口 |
| C4 `sent==10` | `setsockopt` 被成功调用了 10 次（返回值 0，说明 ifIndex 格式/取值被协议栈接受） | **"每个发现发送都被 pin 了一次"** —— 实际是"未 bind 的 socket 无法记 pinned 位，故每包重复设置"（B-1）；也不能证明 pin 只发生一次；若换成已 bind 的 socket 该断言会变成 1 而失败 |
| C5 `ignoredNonDiscovery==4` | 4 个非发现发送未被 pin | 无（干净，但见 C4 的语义分裂） |
| C6 `sendFail==0` | 所有 `setsockopt` 都成功 | 若 ifIndex 非法会怎样（未测） |
| C7 非 C2 计数器为 0 | 未启用 ForwardFrame/cvlh2/观察链 | 无（这些字段本来就硬编码 0，故该断言是同义反复） |
| C8 `bind62056Count==0` | 没有 bind 62056 | DLL 是否用别的手段占用了数据端口（无，源码可证） |
| C9 `shutdown()==0` | 排空成功 | 同 A8 |
| C10 二次 `shutdown()==1` | 幂等、无复活 | 无（B2 契约成立，正面结论） |

### 4.2 包装脚本断言（`run-c2-iface-selftest.ps1`，共 25 条 Check）

| 断言 | 能证明 | 不能证明 |
|---|---|---|
| `:127` 场景进程 `exit==0` | 三场景无崩溃、无断言失败 | 无 |
| `:132` `ran==Expected(8/6/10)` | 断言**条数**与设计一致，没有漏跑 | 断言内容是否正确 |
| `:133` `failed==0` | 上述 24 条全部通过 | 通过的断言是否有判别力（多数没有） |
| `:136` 无 `FAIL` 行 | 同上 | 同上 |
| `:140-153` 10 条 `-match 'PASS A5 sent == 0'` | 子进程确实打印了这些字符串 | 任何独立事实 —— **自指**，与 `failed==0` 完全重复；其中 `:148` 的 `PASS C4 sent == 10` 还把 B-1 的缺陷固化成了"预期" |
| `:153` 匹配 `'NOT verified here'` | 免责声明确实被打印 | 声明是否足够（见第 6 节） |
| T1 `--iface 10.255.255.1` → exit 1 + 拒绝文案 | ctl 拒绝非本地地址、且**在写文件之前**拒绝 | 拒绝的是"非本地"还是"不可解析"（两者混在同一分支） |
| T2 `--iface ALL` → 配置写为 `ALL`，exit 2 | 写配置路径可用 | 该配置是否**被 DLL 读过并正确解释成 ALL**（无进程加载它，M-2） |
| T3 `--iface 127.0.0.1` → 配置写为 `127.0.0.1`，exit 2 | 写配置路径可用 | loopback 是否被当作合法目标（被接受了，H-4） |
| 未出现 `Get-Counter` | —— | §7.2 主判据、§7.3 第 4/5 项**完全缺失** |

### 4.3 设计 §7.3 十项断言的实际覆盖（逐条对照 `M0C-C2-DESIGN-20261118.md:369-380`）

| # | 设计断言（原文要点） | 实测覆盖 | 结论 |
|---|---|---|---|
| 1 | 四导出 `GetProcAddress` 均成功 | `client_selftest.cpp:66-68` 只取 **3** 个（state/shutdown/counters），未取 `CivLinkSessionId` | **部分**（L-5） |
| 2 | 加载后 `CivLinkHookState==1` 且 `initError==0` | A1/A2、C1/C2 覆盖 | **覆盖** |
| 3 | PIN 模式 `sent==N`、`sendFail==0`、`ignoredNonDiscovery==0` | C4 `sent==10`、C6 `sendFail==0` 覆盖；C5 实测 **4**，与"`ignoredNonDiscovery==0`"**相反** | **部分且矛盾**（B-1、B-3） |
| 4 | PIN 模式逐接口计数：目标网卡增量 ≥ N/2，非目标 ≈ 0（"B 是否生效的判据"） | 脚本无 `Get-Counter`、无 `pktmon` | **未实现**（B-3） |
| 5 | ALL 模式：`sent==0`、pinned 字段全 0、广播仍走 metric 最小接口（增量 ≥ N/2） | A5/B4 只覆盖"`sent==0`"；"走 metric 最小接口"无任何实现 | **部分**（后半句未实现） |
| 6 | `sendto` 返回值 == 发包长度（无吞包） | A4/B3/C3 覆盖（14/8 包全返回 4 字节） | **覆盖** |
| 7 | 无效接口 `192.168.99.99` → `initError==12` 且 `state==1` | 实测只用 `not-an-ip` 验证了 **11**；**12 从未触发** | **未覆盖**（M-3） |
| 8 | ctl fail-closed：`--iface 192.168.99.99` → 拒绝 `exit 1` | T1 用 `10.255.255.1` 得到 exit 1（同类非本地地址，拒绝路径成立），但**未用设计指定值** | **覆盖（换值）** |
| 9 | 缺文件/空文件 → ALL（`sent==0`） | 场景 A 覆盖"缺文件"；**"空文件"未测**；显式 `ALL` 也未测 | **部分**（M-2） |
| 10 | `CivLinkShutdown==0`（干净退出） | A8/B6/C9/C10 覆盖，含二次调用 `1` | **覆盖（最强项）** |

统计：完整覆盖 4 项（2、6、8、10），部分覆盖 3 项（1、5、9），部分且矛盾 1 项（3），明确未覆盖 2 项（4、7）。即 **设计自己标为"B 是否生效的判据"的第 4 项，一项都没做**。

### 4.4 结论性判断

- 本套证据的**真实效力等级**是：**"记账层 + 不破坏发送层"的单元测试**，不是"定向能力验证"。
- 只要 DLL 的计数器写对，一个**完全不做 `setsockopt`** 的版本也能让这 25 + 24 条全绿（只需把 `sent` 照常自增）。因此它对 C2 的核心命题（广播是否从选定网卡发出）**零判别力**。
- `result.txt` 里"registered as outstanding, not verified"这段免责是**正确的、且是本次证据里最有价值的部分**；问题在于它没有传导到标题与判据表（B-3）。

---

## 5. 哈希核对表

声称值来源：`M0A\captures\C2-iface-selftest-20261118-0834\result.txt`。
实测方法：本机 `Get-FileHash -Algorithm SHA256`，对象为 `CivLink-M0A-audit\civlink\` 下的实际文件。

| 文件 | 大小（实测） | 声称 sha256 | 实测 sha256 | 结论 |
|---|---|---|---|---|
| `civlink_client.dll` | 147,968 B | `41F8AD3E4FB1501D61D931DE3384E4A9C9FF0D19C6C615BF0815C6009F9B89A7` | `41F8AD3E4FB1501D61D931DE3384E4A9C9FF0D19C6C615BF0815C6009F9B89A7` | **一致** |
| `civlink_ctl.exe` | 186,880 B | `F1105435C8D1AFE0EFA941A7E1C1FCAB8648C3277A3CFD871E7491C84BB1611C` | `F1105435C8D1AFE0EFA941A7E1C1FCAB8648C3277A3CFD871E7491C84BB1611C` | **一致** |
| `client_selftest.exe` | 172,544 B | `CCD56C7CB85FA7A3E72840ECBD47E87B19374F4C47779DECF5EC0D96B190E603` | `CCD56C7CB85FA7A3E72840ECBD47E87B19374F4C47779DECF5EC0D96B190E603` | **一致** |
| `run-c2-iface-selftest.ps1` | 9,068 B | `ED45C8EC3D98D623C94A6BFD637A1B2A983EDEB885FDBD1419EB4143271F06CB` | `ED45C8EC3D98D623C94A6BFD637A1B2A983EDEB885FDBD1419EB4143271F06CB` | **一致** |

补充核对：

| 项目 | 结果 |
|---|---|
| 设计文档 `M0C-C2-DESIGN-20261118.md` 的哈希声称 | **不存在**（全文检索 `[0-9A-F]{32,64}` 无命中）→ 无"声称 vs 实测"可核；建议后续把设计文档哈希也写进 `result.txt`，否则"证据 ↔ 设计"的绑定只靠文件名与日期 |
| `civlink_hook.dll`（C1，非本次审计对象，顺带核对） | 119,808 B，`062096A76CE78CEB77E5448AE098A790BCAFEF23335F9349CAFBB0D07E47D54E`，未在 C2 证据中声称，无冲突 |
| 源码 → 二进制时间序 | `civlink_client.cpp` 08:29:44 → `civlink_client.dll` 08:30:33；`client_selftest.cpp` 08:33:31 → `client_selftest.exe` 08:33:44；`civlink_ctl.cpp` 08:30:21 → `civlink_ctl.exe` 08:33:43；`run-c2-iface-selftest.ps1` 08:34:26（晚于全部二进制，符合"最后写脚本"）。**顺序自洽，无"二进制早于源码"的可疑迹象** |
| `cfg\` 内容与场景期望 | `c2-cfg-bad.txt` = `not-an-ip\r\n` ✓；`c2-cfg-pinned.txt` = `127.0.0.1\r\n` ✓；`client-iface.txt` = `ALL\r\n` ✓；`client-iface-pin.txt` = `127.0.0.1\r\n` ✓；`c2-cfg-absent.txt` 不存在 ✓（场景 A 用 `DeleteFileA` 保证） |

置信度说明：哈希一致只能证明"证据里的这四个文件就是被测的那四个文件"，**不能**证明它们由当前工作区源码构建（构建可复现性未验证：`build-msvc.cmd` 无确定性构建标志，`/MT` 下仍受 `__TIME__`/PDB 路径影响）。

---

## 6. 边界声明核查（哪些表述过强）

| 表述 | 出处 | 判定 |
|---|---|---|
| `C2-IFACE-SELFTEST: PASS (25 checks)` | `result.txt` 首行 | **过强**。字面为"模拟接口自测通过"，实际只验证了记账与不破坏发送；且 25 里 10 条是自指字符串匹配。应改为 `BOOKKEEPING PASS` 并分行标注 egress 未验证（B-3） |
| "does NOT prove which adapter the datagram leaves through ... registered as outstanding, not verified" | `result.txt` 第 2-5 行、`scenario-c.txt` NOTE 两行、`run-c2-iface-selftest.ps1:12-14`、`client_selftest.cpp:263-266` | **恰当、且措辞准确**。这是本次交付里最可信的边界声明，四处一致。唯一不足：只出现在附注里，未进入标题与判据表 |
| "机械证据（单机 loopback）≠ 双机验证" | 设计 §8.1 L390、计划 §3.5 L96-99 | **恰当** |
| "未 bind 的 UDP socket 首次 send 会隐式 bind → 在 sendto detour 中每次发送前设置是**安全且必然生效**的时机" | 设计 §3.2 L124 | **过强**。前半句是 Windows 行为事实，后半句"必然生效"未经任何实验支持；§3.3 自己把"对 broadcast 是否生效"列为不确定项，两句互相抵触。且实现并未"每次发送前设置"（只 pin 一次），表述与实现也不符（M-6） |
| "该选项在 bind 前调用时，到 bind 时才检查" | 设计 §3.2 L124 | **未经证实的引用**。若成立，则当前"只设置一次且在隐式 bind 前"的实现有整体失效风险；本轮无任何证据支持或否定 |
| `sent` = "成功 pin（`setsockopt==0`）的发现发送次数" | 设计 §4.3 L241 | **与实现不符**。实现是"每次 `setsockopt` 成功"；在已 bind 的 socket 上是"成功 pin 的 socket 数"，在未 bind 的 socket 上恰好等于"发送次数"。定义需要拆成两个计数器（B-1） |
| "`sockTableOverflow` = 槽满次数（保留）" | 设计 §4.3 L246 | **未实现**（硬编码 0，`civlink_client.cpp:474`） |
| "`scatterGather` = WSASendTo 多 buffer 次数" | 设计 §4.3 L245 | **未实现**（硬编码 0，`:473`） |
| "曾 bind 发现端口的 socket 的所有发送均视为发现（socket 身份规则）" | 设计 §4.1 L204 | **未实现，且实现注释明确宣称不需要**（`:231-234`）。文档与代码直接冲突，需二选一并说明理由 |
| `initError` 编号 2..9 | 设计 §4.3 L252 | **错误**，与实现（3/4-9/10）和头文件（1..10）都不符（M-4） |
| "inject-client 在注入之前写配置" | 设计 §5.2 L316-319 | **与实现一致**（`civlink_ctl.cpp:330-340`：先 `WriteClientIfaceConfig`，再 `ResolveTarget`）。但该顺序本身有副作用风险：目标进程不存在时（exit 2）配置已落盘，真实使用中会留下"上次未生效的定向配置"，直到下次 `--iface` 覆盖（M 级，见第 7 节第 4 条） |
| "只读改造：唯一副作用是 `setsockopt(IP_UNICAST_IF)`" | 任务约束 / 设计 §8.2 L391-394 | **在代码层成立**：全文无 `::socket(`、无 `send`/`WSASend` 伪造、无 `bind` 62056、无 `SO_REUSEADDR`、无 `ForwardFrame`、无复制重发；`WSAStartup` 仅 `:401` 一处。**这是一条正面的、经核实的结论**。唯一例外是 `setsockopt` 失败污染 `last error`（B-2），属于"副作用外泄"而非"额外发包" |
| "配置无效 fail-open 降级到 ALL" | 设计 §4.3 / §5.1 L287 | **成立**（`civlink_client.cpp:96-154` 所有异常分支都返回 0 或 11/12 且 `g_mode` 保持 `ALL`）。但表述不完整：`CreateHook`/`EnableHook` 失败（3..10）同样是 fail-open，却在文档里没有对应的"降级说明"（L-8） |

---

## 7. 进下一步的前提清单

按顺序，前 3 项是硬门槛：

1. **修 B-1**：让发现 socket 能落 `pinned` 位（或在 `PinSend` 内 find-or-create），并把 `sent` 拆成 `pinnedSockets` / `pinCalls` 两个计数器（`CivLinkCounters` 版本 +1）。修完后用**已 bind 的 socket** 重跑场景 C，证明"同一 socket 只 pin 一次"。
2. **修 B-2**：`PinSend` 内保存并在 `setsockopt` 后恢复 `WSAGetLastError()`。
3. **修 B-3**：把 `result.txt` 标题降级为 bookkeeping-only；删除 10 条自指断言，改为机器可读的计数器行比对；在设计 §7.3 表上逐条标注 covered/uncovered/contradicted；明确写下"第 4、5 项未实现"。
4. **修 H-1/H-2**（排空窗口、overlapped 路径）：这两条直接影响"shutdown 干净"与"异步发送也能定向"两个对外承诺。
5. **补测试场景**（M-2、M-3）：新增 D（`ALL` 显式）、E（空文件）、F（多行取首行）、G（`192.168.99.99` → `initError==12`）。补完后 `initError` 的 11/12 两条 fail-open 路径才算都有证据。
6. **修 ctl 侧**（H-3、H-4）：拒绝 loopback；打印所选适配器 `FriendlyName/IfIndex/metric`；打印配置"由 env override 解析"的提示；把写配置挪到 `ResolveTarget` 成功之后，或至少在目标未找到时删除刚写入的配置。
7. **修文档一致性**（M-4、M-5、L-3、L-9 + 第 6 节所有"过强"项）：设计文档与实现必须收敛到一套编号与语义；`CIVLINK_CLIENT_IFACE_FILE` 要么登记进 §5.1 并写清"目标进程环境"的坑，要么降级为仅自测用。
8. **跨机实测（唯一能回答 C2 核心命题的一步，目前完全未做）**：按设计 §3.3 三步法，在 PC-B 上（WLAN metric 45 + Radmin metric 200，且 metric 最小接口 ≠ 定向目标接口）：
   - step 1：本机双接口 `Get-Counter "\Network Interface(*)\Packets Sent/sec"` 增量。注意计划 §3.3 L84 已记录"`Packets Sent/sec` 对虚拟接口（Radmin/ZeroTier）不计数且噪声大"——该主判据**已知不可靠**，需先换指标（如 `\Network Interface(*)\Bytes Sent/sec` + 多次采样取中位数，或用 `pktmon`）。
   - step 2：`pktmon` 逐接口抓包（需管理员）。
   - step 3：若结论为"`IP_UNICAST_IF` 对 limited broadcast 无效"，则**必须做方案 C 的开工/不开工决策**（设计 §3.4 L186-191），不能默认"B 已生效"直接结案。
9. **真实 Civ6 进程内验证**：本轮所有证据都来自 `LoadLibraryA` 加载 DLL 的自测进程（`client_selftest.cpp:61`），**没有任何一次真实注入**。T1 在写配置前就拒绝（exit 1）；T2/T3 都止于 `ResolveTarget` → `target process not found`（exit 2，`civlink_ctl.cpp:339-340`），根本没走到 `OpenProcess`。因此 `VirtualAllocEx` + `WriteProcessMemory` + 远程 `LoadLibraryW`（`civlink_ctl.cpp:393-421`）这一段**从未被执行过**——"能注入进游戏进程"属于未验证项，需在 PC-B 上用真实 Civ6 补一次。同时验证真实游戏的发现 socket 是否先 `bind`（决定 B-1 修复后 `sent` 的期望值是 1 还是 N）。
10. **E2-A / E2-B / E3 不勾**（计划 §3.5 L96-99）：在跨机实测与真实进程验证完成前，不得在任何文档里把 C2 表述为"已验证"。

---

## 附：本次审计未能覆盖的范围（诚实声明）

- 未运行任何被测程序（未构建、未执行 `run-c2-iface-selftest.ps1`），所有行为结论来自源码阅读与证据文件；因此"证据是否可复现"未经我复跑。
- 未在真机多网卡环境下验证 `IP_UNICAST_IF` 对 `255.255.255.255` 的实际效果（这正是 C2 的核心未决项，需 PC-B）。
- 未审计 `hook.cpp`（C1 已完成并被审计），仅在与 C2 共享的 `IsDiscoveryTarget` 语义冲突处引用。
- 未做二进制反编译核对（未验证 `civlink_client.dll` 的机器码与 `civlink_client.cpp` 逐条对应；哈希一致 + 时间序自洽只能作为间接证据）。
