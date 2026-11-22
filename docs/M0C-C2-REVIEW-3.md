# CivLink M0-C C2 第三轮独立审计报告（REVIEW-3）

审计对象：B 客户端定向网卡 `civlink_client.dll`（C2）
审计日期：2026-11-18
审计依据：`docs\M0C-AUDIT-BRIEF-20261118.md`（任务书）；`docs\M0C-C2-REVIEW.md`（第一轮）、`docs\M0C-C2-REVIEW-2.md`（第二轮，sha256 `46D4741A6AFDF7E8BB87BAE1B360A32CF70FF53D5553E1734E00405EE327DDE0`）；`docs\M0C-C2-DESIGN-20261118.md` v3（sha256 `033AAC98A1DE7DCD1A598E8F0FB36D1342C5CF299DE3BC6738A65E673468F952`）。
证据纪律：仅采信磁盘文件实测；任何"已经通过"的口述一律不采信。所有路径相对 `C:\Users\dd\Desktop\injciv6-v0.3.3\`。

---

## ① 裁定

**有条件通过** —— REVIEW-2 的 6 个阻断中 4 个已彻底关闭、1 个（阻断 6）按用户裁定以"未验证"如实登记、1 个（阻断 3）仅部分关闭（设计文档已同步 `-1015`，但配套的 `M0C-C2-INJECT-SMOKE-20261118.md:131` 与 `M0C-DUAL-ROLE-PLAN-20261118.md:198/:201` 仍留有旧哈希/旧地址，属 REVIEW-2 §6 前置条件 3 未落地），故不允许以"C2 已完整验证"口径登记，只允许以拆分口径（C2-a 记账层通过 / C2-b 真实出口与进程注入未验证）进入 C3 文档登记。

---

## ② REVIEW-2 六阻断逐条关闭表

| # | 阻断项 | 状态 | 文件:行号举证 | 说明 |
|---|---|---|---|---|
| 1 | B-3 叙述残留（"I 是 setsockopt 判别器"） | **已关闭** | `civlink\run-c2-iface-selftest.ps1:3`（`THIS IS A BOOKKEEPING SELF-TEST, NOT AN EGRESS PROOF`）、`:23-30`（明写 I 不是判别器、真判别力在 C ifprobe）、`:204-205`、`:209-211`（C11/C12 检查）、result 模板 `:264-270`；`M0A\captures\C2-iface-selftest-20261118-1015\result.txt:1-2` | 全仓检索已无"would fail both C and I"。唯一残留是 `:257` 与 `result.txt:4` 的 "eight"（实为 9 场景 A–I），记为 N-4，不影响核心叙述关闭。 |
| 2 | 套件零判别力（ifprobe + 变异实证） | **已关闭** | `civlink\selftest\client_selftest.cpp:175-187`（`ReadIfIndex`：`getsockopt(s, IPPROTO_IP, IP_UNICAST_IF, (char*)&idx, &len)`，失败返回 `0xFFFFFFFF`，注释 `:179` 实测 `htonl(19)` 读回 19 = 主机字节序）、`:202-219`（`RunBurstWithIfProbe` 前后快照）、`:286-308`（场景 C：C11 `ifBefore==0` `:306`、C12 `ifAfter!=0 && !=0xFFFFFFFF` `:307-308`）；`ps1:209-211`；变异证据 `M0A\captures\mutation-test-20261118-1016\result.txt`（sha256 `2E66CCA497879632F56FCCE957C90D0A623B8CD517F860B2658901D8E0E0C1F2`，`FAIL`），同目录 `scenario-c.txt:5`（`ifprobe: before=0 after=0`）、`:15`（`FAIL C12`）、`:16`（`failed=1`）；`-1015\mutation-test-note.txt:1-12`（恰 3 条 FAIL：7/9/34）；`-1015\scenario-c.txt:5`（`before=0 after=1`）、`:15`（PASS C12） | 删 `setsockopt` 仅留 `c_sent++` 的变异体被 C12 抓住（3 条 FAIL），黄金轮 `after=1` 通过。判据可靠性：在本 Windows 构建上 `IP_UNICAST_IF` 设置后读回即所设主机序 index，黄金轮 before=0/after=1、变异轮 after=0，未见"设了读回 0"或"没设读回非 0"的假阳/假阴实证；恢复备份 `M0A\captures\mutation-backup-20261118-1016\` 全 6 文件与在盘逐字节一致。 |
| 3 | 哈希过期矛盾（设计 §7.3/§7.4） | **部分** | 已修：`docs\M0C-C2-DESIGN-20261118.md:384-404`（§7.3）、`:406-412`（§7.4）采信轮全部为 `-1015`，`result.txt 6EDFEC5B…`、scenario-c `28C2742A…`、scenario-i `438A84C7…`、scenario-h `071CD536…`、ctl-t1b `6158FD6C…`、mutation-note `D61A3D3F…` 均实测一致，`:410` 明写 `-0924/-0928/-0945` 已弃用。**未修**：`docs\M0C-C2-INJECT-SMOKE-20261118.md:131`（产物仍为旧 `DA9844AA…`/`B8640703…`，当前应为 `F3816C5E…`/`6FCE456E…`）；`docs\M0C-DUAL-ROLE-PLAN-20261118.md:198`（冒烟文档哈希仍写 `C9CFA8B9…`，实测 `EC583823…`）、`:201`（仍写 `0xfc740000`，实测 `0xfc840000`） | 设计文档侧完全同步、无 `-0928/-0945` 被当作采信；但 REVIEW-2 §6 前置条件 3 要求"三份文档互相一致"未落地，故判"部分"。详见 N-1。 |
| 4 | hook_selftest 零支撑 | **已关闭** | `M0A\captures\C2-iface-selftest-20261118-1015\hook-selftest.log`（3,825 B，sha256 `003CBABD9C66595EABE505B043520E29C8AF45B5143B4DFC8F7016B4B7E85764`，`:60` `HOOK-SELFTEST: PASS (0 failure(s))`）、同目录 `hook-selftest-exit.txt`（1 B，`5FECEB66…` = exit 0）；`docs\M0C-C2-DESIGN-20261118.md:410` 明写"归入本轮以支撑审计 REVIEW-2 阻断 4" | 重跑证据确在 `-1015` 采信目录内，哈希与任务书 §1.3 一致。 |
| 5 | recv detour 真 bug（in-flight 窗口） | **已关闭** | `civlink\client\civlink_client.cpp`：`Hook_recvfrom` 重入 `:406-412`（`:407-409` 注记 REVIEW-2 H-1，先 `Real_recvfrom(...)` 后 `g_inFlight.fetch_sub(1)`）、主路径 `:418-420`；`Hook_WSARecvFrom` 重入 `:429-434`（`:430` 注记）、主路径 `:439-443`；另四个 detour 同形：`Hook_sendto :315-319/:329-331`、`Hook_WSASendTo :340-344/:355-357`、`Hook_closesocket :364-368/:371-373`、`Hook_bind :380-384/:398` | **6 个 detour 的重入分支与主分支全部为 `const int rc = Real_*(); g_inFlight.fetch_sub(1); return rc;`**，真实调用位于 in-flight 窗口内，语义一致正确；`design:276-278` 已更新。 |
| 6 | 真实游戏 + 跨机（需用户环境） | **未关闭（按裁定如实登记，不阻塞 C3 文档登记）** | PC-B 离线、《文明6》未运行；`docs\M0C-C2-DESIGN-20261118.md:8`/`:16`/`:418`（登记 uncovered、不得表述"已验证"、不得勾 E2-A/E2-B/E3）；`civlink\run-c2-iface-selftest.ps1:3-8`/`:255`（`Egress adapter: NOT VERIFIED`）；`M0C-AUDIT-BRIEF-20261118.md:116`（范围排除） | 裁定：允许以"未验证"登记。前提成立——文档未宣称 C2 已完整验证、未勾 E2-A/E2-B/E3。该项不阻塞 C3 **文档登记**，但真实出口命题在 PC-B 之前无法关闭。 |

---

## ③ 第一轮 B/H/M/L 全部编号关闭表

证据位置主要引自 REVIEW-2 §2（已复核磁盘一致性）与本轮实测。

| 编号 | 状态 | 证据 / 说明 |
|---|---|---|
| **B-1** | 已关闭 | `civlink\client\civlink_client.cpp:194-203`（无 pinned 位，`struct Slot { SOCKET s; uint16_t portBe; }`）、`:298-309`（每包 `setsockopt` `:303`，`rc==0→c_sent++ :305-306`）。 |
| **B-2** | 已关闭 | `civlink_client.cpp:301`（`savedErr`）、`:303`（setsockopt）、`:304`（`WSASetLastError(savedErr)` 在 rc 分支前，成功/失败路径均恢复，无提前 return 泄漏）。 |
| **B-3** | 已关闭（本轮补齐第④项） | ①标题降级+`Egress adapter: NOT VERIFIED`（`-1015\result.txt:1-2`）；②解析机器可读 `counters:` 行（`ps1:59-68`、`client_selftest.cpp:100-112`）；③§7.3 covered/uncovered/contradicted（`design:384-404`）；④真判别力本轮由 ifprobe C11/C12 + 变异测试实证补上（见阻断 2）。REVIEW-2 判"部分"的第④项至此关闭。 |
| **H-1** | 已关闭（本轮 6/6） | 四个发送类 detour 见 REVIEW-2 §2.2 `:35`；两处 recv detour 本轮已修，见阻断 5。 |
| **H-2** | 已关闭（代码层，测试覆盖仍缺） | `civlink_client.cpp:348-352`（无 `!ov`，判定仅 `bufs && count>=1`）。缺口：9 场景均用同步 `sendto`，`scatterGather=0`，属"已改未验证"，记为低风险观察，不改变编号关闭结论。 |
| **H-3** | 已关闭 | `civlink\ctl\civlink_ctl.cpp:248-256`（`PrintConfigPathResolution` 打印 `resolved by` + 进程环境提示）；`design:289-291`（定性已收敛）；现场复现见 `C2-inject-smoke-20261118-0916`。 |
| **H-4** | 已关闭 | `civlink_ctl.cpp:380-385`（拒绝 loopback）；`-1015\ctl-t1b-loopback.txt`（279 B，`6158FD6C…`）；DLL 侧 M-10 仍在。 |
| **M-1** | 已关闭 | `civlink_client.cpp:217-229`（`:227` 满表 `c_sockOverflow.fetch_add`）、`:518` 导出；`-1015\scenario-i.txt`。 |
| **M-2** | 已关闭 | `client_selftest.cpp:273-340`（场景 D/E/F）；`-1015\scenario-d/e/f.txt`。 |
| **M-3** | 已关闭 | `client_selftest.cpp:342-363`（场景 G，`initError=12`）；`-1015\scenario-g.txt`。 |
| **M-4** | 已关闭 | `design:259` 表与 `civlink_client.cpp` 实现逐值一致。 |
| **M-5** | 已关闭（代码层，测试覆盖仍缺） | `civlink_client.cpp:347`（`count>1→c_scatterGather`）、`:517` 导出；无 `count>1` 场景，同 H-2 观察。 |
| **M-6** | 已关闭（随 B-1 消解） | 每包重设 pin，无"pin 时机"问题；`design:262-280`。 |
| **M-7** | 已关闭 | `-1015\scenario-c.txt` C4 原文 `sent == 10 (one per discovery send from a BOUND socket)`；`client_selftest.cpp:155-171`（`MakeBoundSocketOnPort` 先 `SO_BROADCAST` 再 bind）。 |
| **L-1** | 未关闭（低） | `civlink_client.cpp:551-559`（`DllMain` 仅 `CreateThread`+`CloseHandle`，无 `WSACleanup` 及解释注释）。 |
| **L-2** | 未关闭（低） | `civlink_client.cpp:259-268`（两规则）与 `design:211`（仍三规则）口径不一致。 |
| **L-3** | 未关闭（低） | `design:250` 未说明 ALL 模式下发现包也计入 ignored。 |
| **L-4** | 已关闭（已澄清） | `civlink_client.cpp:322-326`、`design:250` 已写"或 g_state 未就绪"。 |
| **L-5** | 已关闭（已落实） | `client_selftest.cpp:202-203`（A4 两次读取 `CivLinkSessionId` 一致）。 |
| **L-6** | 未关闭（低） | `client_selftest.cpp:86-96`（`WaitReady` 仍只轮询 `state==1`，不因 `initError` 提前失败）。 |
| **L-7** | 未关闭（低） | `civlink\build-msvc.cmd:88-91`（`CIVLINK_SKIP_CLIENT_DLL` 直接复用旧 dll、跳过 `:111-120` 导出校验），风险未入表。 |
| **L-8** | 未关闭（低，PLAN 已登记为有意保留） | `civlink_client.cpp:499`（`if (prev == 1) MH_DisableHook`，`prev==0` 不回滚）。 |
| **L-9** | 未关闭（低） | `design:301-323`（示例仍硬编码 `GetEnvironmentVariableA("LOCALAPPDATA")`、无 `CIVLINK_CLIENT_IFACE_FILE`/`IFINDEX:` 分支、无"示意，非实现"标注）。 |

第二轮新增项处置（供完整性）：H-6 已关闭（叙述改正，见阻断 1）；H-5 已关闭（见阻断 5）；M-8 **部分未关闭**（见 N-2）；M-9 已关闭（`design:290-291` 收敛）；M-10 未关闭（C/F 用 127.0.0.1 作 PIN 目标，低）；M-11 **部分未关闭**（见 N-1）；M-12 未关闭（`civlink_hook.h:37-41` 计数器语义注释，低）；L-10..L-18 见 N-3/N-4/N-5 及上表。

---

## ④ §3.3 三项增量裁定

| 增量 | 裁定 | 依据 |
|---|---|---|
| 1. `civlink_ctl` 自动模块探测 | **接受** | 代码 `civlink\ctl\civlink_ctl.cpp:411-423` 已实现；`design:353-355` 已登记；`-0940` 证据目录可核。属机械能力增强，叙述诚实，无越界副作用。 |
| 2. 真实进程注入冒烟 | **接受（须如实标注为"宿主进程冒烟"，非真实《文明6》）** | `M0A\captures\C2-inject-smoke-20261118-0916\inject-pin2.log:11`（`LoadLibraryW returned 0xfc840000`，哈希 `D4691CF2…` 实测一致）；`design:291` 把 A 轮 env-override 失败如实登记为 H-3 现场复现（非测试错误）。宿主为 `powershell.exe`，**不得表述为游戏进程内验证**。 |
| 3. `run-c2-real-game-check.ps1` 登记 | **接受（登记为"已准备、未执行"）** | 脚本 8,990 B，sha256 `8E83FF8B…` 实测一致；任务书/PLAN 均标"未执行过"。本轮核验其 `Get-CounterValue`（`run-c2-real-game-check.ps1:125-136`）构造正则 `^\s*<label>\s*:\s*(\d+)\s*$`，对 ctl 真实输出 `init error     : 0` 实测匹配、取值 0——脚本解析逻辑与产物格式兼容，但**未执行 ≠ 已验证**，只可按"已准备"登记。 |

---

## ⑤ 新发现（N-1..N-6）

- **N-1（中）｜REVIEW-2 §6 前置条件 3 未落地，三份文档未收敛。** `M0C-C2-INJECT-SMOKE-20261118.md:131` 产物哈希仍是旧值 `DA9844AA0F3997DC68015F68D0074FCC3C4ED9610FB793F4F4382B65D20A538A` / `B864070397AEEDDA2FEE7A5A790522820173A75DDB2C9A2567466BCE184F3CD4`（当前应为 `F3816C5E…` / `6FCE456E…`）；`M0C-DUAL-ROLE-PLAN-20261118.md:198` 把冒烟文档哈希写为 `C9CFA8B977EE017AC58B749AEFC0A691C9655874A61DE26E147253C10ECF9BD5`（实测 `EC583823…`）、`:201` 写 `0xfc740000`（实测 `0xfc840000`）。注意：该文档 `:4` 冒烟文档 §7 的四个证据文件哈希（`:126-129`）实测均正确，说明仅"产物哈希/文档哈希/地址"三处过期。
- **N-2（中）｜M-8 残留：`civlink_ctl.cpp:398-403` 注释与实现语义相反。** 注释称配置"only after the target is resolved and validated, so a failed injection never leaves a stale iface choice behind"，但 `WriteClientIfaceConfig(ifaceChosen)` 在 `:402` 执行，早于 `EnableDebugPrivilege()` `:405`、`OpenProcess()` `:407` 及后续注入——注入失败时配置已落盘，会被后续运行继承。REVIEW-2 §6 前置条件 5 三选一修法均未落地。
- **N-3（低）｜`client_selftest.cpp:21-22` 头注释仍留失实主张。** 仍写"scenario H is the 'can actually fail' assertion … A DLL that never called setsockopt would fail this"，与 `design:400`（§7.3 #11：越界索引被接受、场景 I 非判别器）及 `ps1:23-30`/`:268-270`（H 故意非 must-fail）直接冲突。属 REVIEW-2 L-11 残留。
- **N-4（低）｜"eight"叙述残留。** `ps1:257` 与 `-1015\result.txt:4` 仍写 "exercised in eight single-process scenarios"，实为 9 场景（A–I；`ps1:42` 已正确写 9）。属 REVIEW-2 §6 前置条件 1 的"eight→nine"未完全落地。
- **N-5（低）｜设计文档旧叙述残留。** `design:136-147` 仍留 per-socket `pinned` 位代码示例（与 B-1 实现冲突）；`design:153`/`:269`/`:319` 引用不存在的符号 `ResolveIfIndexForIp`；`design:304-323` 示例仍硬编码 `GetEnvironmentVariableA("LOCALAPPDATA")` 且无"示意，非实现"标注。属 REVIEW-2 L-9/L-12/L-13 残留。
- **N-6（低）｜证据文件计数口径不一致。** `design:410` 与任务书 §1.3 记 `-1015` 为"39 文件"，实测递归 42（顶层 32 + `cfg\` 10）。可能为统计口径差异，不影响哈希与断言结论，但建议统一。

---

## ⑥ 是否允许进入 C3 登记

**yes（有条件）** —— 允许进入 C3 文档登记，但**仅限**以拆分口径登记：「C2-a 单机记账层与配置解析层通过（9 场景 / 47 runner checks / 62 in-process checks，含 ifprobe 变异实证）；C2-b 真实出接口与真实《文明6》进程注入未验证」。严禁表述为"C2 已完整验证/已完成"，严禁勾选 E2-A / E2-B / E3。阻断 6 的"未验证"登记不阻塞本次文档登记。

**登记前最小必做集合（2 项，均为文档订正，不涉及重跑/重编）：**
1. 修 N-1：同步 `M0C-C2-INJECT-SMOKE-20261118.md:131` 两个产物哈希为 `F3816C5E…` / `6FCE456E…`，并把 `M0C-DUAL-ROLE-PLAN-20261118.md:198` 的冒烟文档哈希改为 `EC583823…`、`:201` 的 `0xfc740000` 改为 `0xfc840000`，使三份文档互相一致（REVIEW-2 §6 前置条件 3）。
2. 修 N-2：在 `civlink_ctl.cpp:398-403` 把失实注释改为事实描述，或在 `design` + PLAN 附录登记"注入失败会残留配置"风险（REVIEW-2 §6 前置条件 5）。

上述 2 项落地后，C2 可以"C2-a 通过 / C2-b 未验证"口径完成 C3 文档登记；N-3/N-4/N-5 建议在同批顺手订正（成本低），但不作为登记硬门槛。

---

## ⑦ 证据一致性核对（15 项实测，全部一致）

所有值由 `Get-FileHash -Algorithm SHA256` 实测；短写为前 8 位，完整值见括号。

| # | 文件 | 实测字节 | 实测 sha256（前8位 / 完整） | 与任务书一致 |
|---|---|---|---|---|
| 1 | `CivLink-M0A-audit\civlink\client\civlink_client.cpp` | 24,708 | `CFE7BBED`（`CFE7BBEDC083F6B7246F30B031D2AA923C353767F73CD399A1CA088387EBE715`） | ✅ |
| 2 | `CivLink-M0A-audit\civlink\ctl\civlink_ctl.cpp` | 30,658 | `22EFEF52`（`22EFEF52C19EDA8C1352F6B6B20ECEDFADE564D0AD447FAA2FBB032EC5584241`） | ✅ |
| 3 | `CivLink-M0A-audit\civlink\selftest\client_selftest.cpp` | 22,083 | `1EE7AAD4`（`1EE7AAD46594B9A20FD51F9A10A2D45F24881665E1C2404010B66C234055BA57`） | ✅ |
| 4 | `CivLink-M0A-audit\civlink\run-c2-iface-selftest.ps1` | 15,767 | `2E91B209`（`2E91B209EA911910DF2CDF4611BFFC43D86BB38B724358C3E4BA2E1CDE8E0DAD`） | ✅ |
| 5 | `CivLink-M0A-audit\civlink\agent\src\main.rs` | 127,146 | `E556B66F`（`E556B66F864D492763F944549E5BEC4F001CE3CD85B05D22910C38D374D6C4C2`） | ✅ |
| 6 | `CivLink-M0A-audit\civlink\run-c2-real-game-check.ps1` | 8,990 | `8E83FF8B`（`8E83FF8B15986D48932146F9135FC151A528E117CF0F545C5E58FA150415639B`） | ✅ |
| 7 | `CivLink-M0A-audit\civlink\build-msvc.cmd` | 6,105 | `63FBEE73`（`63FBEE7368AB2D479D064074BE20C700C338CA9515D7F5A984E94E10C017EFB0`） | ✅ |
| 8 | `CivLink-M0A-audit\civlink\client\civlink_client.dll` | 149,504 | `F3816C5E`（`F3816C5E0E6C5BD5920CDCE8AA2B5378623E6420A5C1966E275D663C1B8385D3`） | ✅ |
| 9 | `CivLink-M0A-audit\civlink\ctl\civlink_ctl.exe` | 188,416 | `6FCE456E`（`6FCE456E4156873F093732253E0381872F0CDEAAFFF61655D9460ABB73634D26`） | ✅ |
| 10 | `M0A\captures\C2-iface-selftest-20261118-1015\result.txt` | 1,626 | `6EDFEC5B`（`6EDFEC5B6FA88A47DA025747D3703BDB7980C543885B7BF85E97656E6523CC65`） | ✅ |
| 11 | `M0A\captures\mutation-test-20261118-1016\result.txt` | 1,626 | `2E66CCA4`（`2E66CCA497879632F56FCCE957C90D0A623B8CD517F860B2658901D8E0E0C1F2`） | ✅ |
| 12 | `M0A\captures\C2-iface-selftest-20261118-1015\scenario-c.txt` | 1,199 | `28C2742A`（`28C2742ABE42264508B6772018F3EC19AE54689D184A3BFC7DF449F4EA3984F0`） | ✅ |
| 13 | `M0A\captures\C2-iface-selftest-20261118-1015\hook-selftest.log` | 3,825 | `003CBABD`（`003CBABD9C66595EABE505B043520E29C8AF45B5143B4DFC8F7016B4B7E85764`） | ✅ |
| 14 | `M0A\captures\C2-iface-selftest-20261118-1015\mutation-test-note.txt` | 867 | `D61A3D3F`（`D61A3D3FFC6636D3086B48757522AA64AB90A980C8141B31D4C3B7F88F64D9C4`） | ✅ |
| 15 | `CivLink-M0A-audit\docs\M0C-C2-DESIGN-20261118.md` | 43,685 | `033AAC98`（`033AAC98A1DE7DCD1A598E8F0FB36D1342C5CF299DE3BC6738A65E673468F952`） | ✅ |

补充实测（一致性参照）：`M0C-C2-REVIEW.md` 37,556 B `4E40F292…`、`M0C-C2-REVIEW-2.md` 53,007 B `46D4741A…`、`M0C-DUAL-ROLE-PLAN-20261118.md` 36,415 B `D9CAD9EE…`、`M0C-C2-INJECT-SMOKE-20261118.md` 8,980 B `EC583823…`、`civlink_hook.dll` 119,808 B `33438AD5…`、`hook_selftest.exe` 150,016 B `2F1BB08C…`、`client_selftest.exe` 182,272 B `5E4E7B6F…`、`civlink-agent.exe` 421,376 B `4390AF9D…`、`-1015\scenario-i.txt` 684 B `438A84C7…`、`-1015\scenario-h.txt` 753 B `071CD536…`、`-1015\ctl-t1b-loopback.txt` 279 B `6158FD6C…`、`-1015\hook-selftest-exit.txt` 1 B `5FECEB66…`、`0916\inject-pin2.log` 1,768 B `D4691CF2…` —— 均与任务书/设计文档记载一致。

**不一致项（非采信证据自身，而是文档引用）：** `M0C-C2-INJECT-SMOKE-20261118.md:131` 与 `M0C-DUAL-ROLE-PLAN-20261118.md:198/:201` 的旧哈希/旧地址（见 N-1）。`M0A\captures\mutation-test-20261118-1016\scenario-c.txt` 实测 1,199 B `3801EDF5…`，与黄金轮 `28C2742A…` 不同属预期（变异体读回 0），设计/任务书未引用该值，不构成不一致。

---

## 附：审计方法说明

本轮为独立复审：逐文件读取源码/脚本/文档并用 `Get-FileHash` 实测哈希，逐行核对 REVIEW-2 六阻断与第一轮 B/H/M/L 全部编号，独立核验变异测试证据链（变异体 → 3 FAIL → 备份恢复逐字节一致）、ifprobe 判据可靠性、6 个 detour 的 in-flight 语义、§3.3 三项增量与 `Get-CounterValue` 正则兼容性。未采信任何"已通过"口述；PC-B/《文明6》未运行的部分一律登记为未验证。
