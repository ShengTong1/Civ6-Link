# M0-C 双角色联机助手 — 审计任务书

- 生成时间：2026-11-18
- 适用阶段：C1（A 机房主模式整合）+ C2（B 客户端定向网卡）已实施，C3 登记前
- 用途：给独立审计子代理的任务说明。审计方只看本任务书 + 磁盘文件，不采信本会话的任何口述。

---

## 1. 被审对象（全部在磁盘上，按哈希核对）

### 1.1 源码

| 文件 | 字节 | SHA256 | 说明 |
|---|---|---|---|
| `civlink\agent\src\main.rs` | 127,146 | `E556B66F864D492763F944549E5BEC4F001CE3CD85B05D22910C38D374D6C4C2` | C1：`plan_discovery_ports` + `--reserve-62900` + 22 个单测 |
| `civlink\agent\Cargo.toml` | 525 | `6F70562D5CD78FE8356CE8161FBEF730B3A67176EA30A8B17C126A7C187554A5` | version 0.4.6 |
| `civlink\client\civlink_client.cpp` | 24,708 | `CFE7BBEDC083F6B7246F30B031D2AA923C353767F73CD399A1CA088387EBE715` | C2 主体（REVIEW-2 阻断 5：recv 两处 detour 真调用移入 in-flight 窗口） |
| `civlink\common\civlink_client.h` | 1,535 | `4AD103A0400F9F692A8E4C5EDF08F647B93BB6261A9F0A47C86106B0B0C7B96F` | 版本/initError 常量 |
| `civlink\ctl\civlink_ctl.cpp` | 30,658 | `22EFEF52C19EDA8C1352F6B6B20ECEDFADE564D0AD447FAA2FBB032EC5584241` | `inject-client` / `--iface` / `-m` / 自动探测 |
| `civlink\selftest\client_selftest.cpp` | 22,083 | `1EE7AAD46594B9A20FD51F9A10A2D45F24881665E1C2404010B66C234055BA57` | 9 场景 A–I（REVIEW-2 阻断 2：场景 C 加 ifprobe C11/C12） |
| `civlink\run-c2-iface-selftest.ps1` | 15,767 | `2E91B209EA911910DF2CDF4611BFFC43D86BB38B724358C3E4BA2E1CDE8E0DAD` | 47 断言 |
| `civlink\run-c1-reserve-selftest.ps1` | 11,562 | `CA8F6599CD411E4DF1CD784B423F22CBF5FC260491675265173890E150C8C1BE` | 12 断言 |
| `civlink\run-c1-combo-selftest.ps1` | 12,950 | `70D17397FE139D0BC50148C1E249D9D35DC0C5CE2A3C016801E809EABE01B0D9` | 14 断言（标志组合） |
| `civlink\run-c2-real-game-check.ps1` | 8,990 | `8E83FF8B15986D48932146F9135FC151A528E117CF0F545C5E58FA150415639B` | 真实游戏检查（**未执行过**） |
| `civlink\build-msvc.cmd` | 6,105 | `63FBEE7368AB2D479D064074BE20C700C338CA9515D7F5A984E94E10C017EFB0` | 五目标构建 |

### 1.2 产物

| 文件 | 字节 | SHA256 |
|---|---|---|
| `civlink\civlink-agent.exe` | 421,376 | `4390AF9DF56AE9085BB9384E2EDAC0E3C4BAE27CA20B2E92799D895064E7792C` |
| `civlink\civlink_hook.dll` | 119,808 | `33438AD5844208E7689377668FB22381E285532938C8D3851B10D9E3B5B16376` |
| `civlink\civlink_client.dll` | 149,504 | `F3816C5E0E6C5BD5920CDCE8AA2B5378623E6420A5C1966E275D663C1B8385D3` |
| `civlink\civlink_ctl.exe` | 188,416 | `6FCE456E4156873F093732253E0381872F0CDEAAFFF61655D9460ABB73634D26` |
| `civlink\hook_selftest.exe` | 150,016 | `2F1BB08CE5E34D17CE856870F8CB96B9F11C678AD4333DB28403BE6BA8283EB9` |
| `civlink\client_selftest.exe` | 182,272 | `5E4E7B6F763B493261CE8AB9619CA5C704DC1484D34223E7CDBE6428A7B6023A` |

### 1.3 证据目录（`C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\`）

| 目录 | 文件数 | 采信结论 |
|---|---|---|
| `C1-reserve-selftest-20261118-0930` | 53 | `C1-RESERVE-SELFTEST: PASS (12 checks)` exit 0 |
| `C1-combo-selftest-20261118-0930` | 55 | `C1-COMBO-SELFTEST: PASS (14 checks)` exit 0 |
| `C2-iface-selftest-20261118-1015` | 39 | `C2-BOOKKEEPING-SELFTEST: PASS (47/47 runner checks, 62 in-process)` exit 0，`ifprobe: before=0 after=1`；含重跑 hook_selftest PASS（阻断 4）+ mutation-test-note（阻断 2） |
| `mutation-test-20261118-1016` | — | 变异测试：删 setsockopt 只留 c_sent++ → FAIL (47/47)、`ifprobe after=0`、恰 3 条 FAIL（C12 判别力实证） |
| `C2-inject-smoke-20261118-0916` | 18 | 首次真实进程注入（宿主 powershell.exe） |
| `C2-inject-smoke-20261118-0940` | 3 | ctl 自动探测修复复验 |

> `-0924` / `-0928` / `-0945` 三轮 C2 证据是旧二进制 / 旧叙述配套，**仅供留档，不得作为采信依据**（REVIEW-2 阻断 3）。第三轮复审以 `-1015` 为准。

### 1.4 文档

| 文件 | 字节 | SHA256 |
|---|---|---|
| `docs\M0C-DUAL-ROLE-PLAN-20261118.md` | 36,415 | `4F19CDF1B3B52A19C845B5990D99DC229EB52BF8D23A19C436C790043F3FB3F2` |
| `docs\M0C-C2-DESIGN-20261118.md` | 43,685 | `033AAC98A1DE7DCD1A598E8F0FB36D1342C5CF299DE3BC6738A65E673468F952`（v3） |
| `docs\M0C-C2-REVIEW.md`（第一轮审计报告） | 37,556 | `4E40F2927576CC8214AC2261C288B86256A91782CC1344F4994B3A479856D758`（271 行） |
| `docs\M0C-C2-REVIEW-2.md`（第二轮审计报告） | 53,007 | `46D4741A6AFDF7E8BB87BAE1B360A32CF70FF53D5553E1734E00405EE327DDE0`（404 行，6 阻断；第三轮复审对象） |
| `docs\M0C-C2-INJECT-SMOKE-20261118.md` | 9,312 | `64EB40CE4BB47A230C20E43599D9A2352581D8AD8C35A9F40AA6C83C23BAC959` |
| `docs\M0C-C2-CROSSMACHINE-RUNBOOK-20261118.md` | 8,147 | `E786058A8C276441B6CD7FB62D0B7C3E08346CDB2E26B1AF508D5CDDEDA2CC27` |
| `docs\M0C-C1-REVIEW.md`（C1 审计报告） | 10,263 | `83CD5327CEAB01E5942904126E7B658F3686279712164D73C3854EB98651195B` |

---

## 2. 硬约束（违反即为阻断项）

1. **/MT 静态 CRT**；MSVC x64；MinHook pin `deps\MinHook` `--branch v1.3.4`（HEAD `8af6b4ac…`），**不得改库**。
2. **Agent 永不 bind `0.0.0.0:62056`**，永不 `SO_REUSEADDR`；每帧单次、不重传、不篡改载荷。
3. **C2 只读纪律**：`civlink_client.dll` 对游戏流量**唯一**允许的副作用是 `setsockopt(IPPROTO_IP, IP_UNICAST_IF=31, htonl(ifIndex))`，且必须保存/恢复 `WSAGetLastError()`。不得伪造 send/recv、不得复制重发、不得改载荷、不得 bind 62056。
4. **B2 审计运行模式**：`CivLinkShutdown` 不调用 `MH_Uninitialize`、不卸载模块；模块映射至目标进程退出。
5. **证据纪律**：机械证据 ≠ 双人联机验证。不得把单机自检写成"联机已验证"。
6. **登记链单向引用**：README/HANDOVER 引用被审文档哈希；被审文档不反向嵌 README/HANDOVER 哈希（避免循环重算）。

---

## 3. 审计范围与必答问题

### 3.1 C1（A 机房主模式整合）

- [ ] `--reserve-62900` 是否**真的**保证游戏永远能 bind `62900`？给出机制依据（`plan_discovery_ports` 过滤 + `LanSimState::new` 循环），并指出任何能让 62900 仍被占用的路径。
- [ ] `reply_sock` 回退链（62900 成功才 `try_clone`；失败则 `listeners[0].try_clone()`）在 reserve 模式下是否**必然**走到回退？回退后的应答源端口是多少？（证据：`-0930` summary 应为 `127.0.0.1:62901`）
- [ ] `requests seen == 99` 是否被正确解释为"100 减 1"而非丢包？
- [ ] 22 个 `#[test]` 中 3 个新增的是否真的覆盖了 reserve 分支，而不是同义反复？
- [ ] 标志组合脚本（`--reserve-62900 --sim-real-capture --forward-listen … --sim-lan-listen … --simulate`）是否证明了这些标志**互不破坏**？它没证明什么？
- [ ] C1 建议 2/3/8 是否真的关闭？建议 4/5/6/7 呢？

### 3.2 C2（B 客户端定向网卡）

第一轮审计列了 3 阻断 / 4 高危 / 7 中危 / 9 低危，请**逐条**核对 `docs\M0C-C2-REVIEW.md` 的编号，判定：

- [ ] **B-1**（pinned 位失效 / `sent` 语义分裂）→ 现方案"每包幂等 setsockopt + `sent` 重定义为接受次数"是否**真正消除了**语义分裂？还是一个换名字的补丁？
- [ ] **B-2**（setsockopt 覆盖 last error）→ 保存/恢复是否覆盖了**所有**返回路径（含 `g_state != 1` 提前返回、`g_mode != PIN` 提前返回）？
- [ ] **B-3**（证据效力不足）→ 标题是否真的降级？是否仍有断言在"匹配程序自己打印的字符串"？是否仍有"一个完全不做 setsockopt 的 DLL 也能全绿"的路径？
- [ ] **H-1**（`g_inFlight` 在真实调用前递减）→ 4 个 detour 是否全部改为真实调用在窗口内？重入分支呢？
- [ ] **H-2**（overlapped 被排除）→ `!ov` 是否真的去掉？`bufs && count>=1` 的前置是否还合理？
- [ ] **H-3**（配置路径）→ 设计 §5.1 是否登记了 env override 的**限制**？冒烟文档是否给出了"变量不传入目标进程"的实证？ctl 是否打印 `resolved by`？
- [ ] **H-4**（loopback）→ ctl 是否拒绝 `IF_TYPE_SOFTWARE_LOOPBACK`？T3 是否改用了真实适配器？新增 T1b 是否真的执行？
- [ ] **M-1..M-7** → 逐条核对（`sockTableOverflow`/`scatterGather` 真实计数、D/E/F 场景、`initError==12` 证据、initError 编号表、M-6 时序、M-7 披露）。
- [ ] **L-1..L-9** → 哪些仍未修？是否必须在 C3 前关闭？

### 3.3 新增增量（第一轮审计之后产生，必须单独裁定）

- [ ] **ctl 自动模块探测**（`civlink_ctl.cpp`）：未给 `-m` 时先查 `civlink_hook.dll`、查不到再查 `civlink_client.dll`。它是否引入新风险？
      - A 机同时加载了两个 CivLink DLL 时会怎样？
      - 它是否**掩盖了本应报错**的场景（目标根本没加载任何 CivLink 模块）？
      - 探测逻辑是否在 `inject` 分支被意外启用（应当只在 `status`/`counters`/`shutdown` 生效）？
- [ ] **真实进程注入冒烟**（`docs\M0C-C2-INJECT-SMOKE-20261118.md`）：它把"注入路径从未执行"关闭到什么程度？宿主是 `powershell.exe` 不是游戏，这个差别是否被如实登记？三轮计数对照的 A 轮（env override 失效）是否被正确解释为"审计 H-3 的现场复现"而不是"测试写错了"？
- [ ] **`run-c2-real-game-check.ps1`**：脚本**尚未执行过**。它的断言设计是否正确？`Get-CounterValue` 的正则是否匹配 ctl 的真实输出标签（`init error     : 0` 等，注意多空格）？verdict 的边界声明是否足够？在没有真实执行结果的情况下，它能否被登记为"已备好但未验证"？

---

## 4. 明确不在审计范围内（不要出裁定）

- 广播是否真从选定网卡发出 —— 需要第二台机器 + 抓包（`M0C-C2-CROSSMACHINE-RUNBOOK-20261118.md`），PC-B 离线。
- 真实《文明6》进程内表现 —— 脚本已备，未执行。
- 双人对局 / E2-A / E2-B / E3 / Gate A / Gate B。
- `civlink\relay\`、`civlink\fakeip\`、`civtrace\`（属 F3/F4 冻结范围）。
- M0-D 开源产品规划的 7 个决策点（等用户拍板）。

---

## 5. 输出要求

写到 `CivLink-M0A-audit\docs\M0C-C3-AUDIT-<日期>.md`，必须包含：

1. **裁定**：`通过` / `有条件通过` / `不通过`，一句话理由。
2. **逐条关闭表**：C1 建议、C2 的 B/H/M/L 全部编号，每行 `已关闭 / 部分 / 未关闭` + 证据位置（文件:行号）。
3. **增量裁定**：§3.3 每项的独立判断。
4. **新发现**：审计方自己发现的问题（编号 `N-1..N-n`，标注 阻断/高/中/低）。
5. **是否允许进入 C3 登记**：明确 yes/no。若 no，列出必须先做的最小集合。
6. **证据一致性核对**：抽查 ≥6 个哈希，报告实测值。
7. **不得采信的口述**：本任务书之外任何"已经通过"的说法都不作为依据。

---

## 6. 已知的、无需重复发现的事项

- 工作区内派生进程 `OpenProcess` 恒 `err=5`、写 `%LOCALAPPDATA%` 恒 `errno=13` —— **DSH 文件沙箱限制，非 CivLink 缺陷**（已两次独立验证，见冒烟文档 §2）。
- Windows 上 `setsockopt(IP_UNICAST_IF)` 对**越界接口索引返回 0 并接受** —— 已实测，场景 H 因此无法充当"能失败断言"；"判别力由场景 I 承担"的说法**已被第二轮审计推翻**（I 只 bind 不 send，溢出与 pin 无关）。真正的判别断言是场景 C 的 `ifprobe`（C11/C12，`getsockopt(IP_UNICAST_IF)` 前后快照）+ 变异测试实证，见 §1.3 `-1015` / `-1016`。
- `CivLinkCounters` 字段名是 `rawBindCalls`（不是 `rawBindCount`）。
- **第二轮审计（REVIEW-2）6 阻断的代码/文档侧已修 5 项**：阻断 5 = recv 两处 detour 真调用移入 in-flight 窗口；阻断 2 = ifprobe(C11/C12)+变异实证；阻断 1 = ps1/result 叙述改正；阻断 3 = 哈希同步 `-1015`；阻断 4 = hook_selftest 重跑归入 `-1015`。第三轮复审应逐条关闭 REVIEW-2 的 6 阻断，并裁定**阻断 6（真实游戏注入 + 跨机出口，需用户环境）允许以"未验证"登记而不阻塞 C3 文档登记**。
- `-0924` / `-0928` 证据对应旧二进制，不得采信。
