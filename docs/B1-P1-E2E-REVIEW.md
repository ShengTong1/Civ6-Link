# B1-P1-E2E 审计报告：真实广告页捕获 P1（hook 链）端到端验证

- 审计对象：`civlink\hook\hook.cpp`（socket-身份判定改造）＋`civlink\selftest\hook_selftest.cpp`（B1 新增 4 用例）＋端到端证据 `M0A\captures\B1-p1-e2e-20261117-102852\`（= `C:\Users\dd\Desktop\civlink-b1\b1-p1-final-20261117-102852\` 双份）
- 审计者：独立审计子代理（e1f7ebaf）
- 审计时间：2026-11-17 10:29–10:44（本机，Civ6 pid 37528 运行中）
- **裁定：有条件通过**（核心结论成立；必改 1 项：修正 selftest 两处断言预期值并复跑）

---

## 0. 审计方法

1. 代码走读：`hook.cpp` `IsDiscoveryTarget`/`ForwardFrame`/`Hook_sendto`/`Hook_WSASendTo`/`Hook_bind`/槽表锁；`agent\src\main.rs` 帧处理循环与捕获入口；`hook_selftest.cpp` 全部 55 项断言。
2. 证据复核：对终轮证据目录逐文件独立计算 SHA-256，与 `real-ad-manifest.txt`、B1 文档声明哈希交叉比对；对 §0 取证目录（`B1-triggerad-20261117-095336\`）与触发轮目录（`-102311/-102635/-102906`）逐一核查。
3. 机械复现：在 Civ6 运行状态下实跑 `hook_selftest.exe`，复现 8 个 FAIL 并逐项归因；对 `civlink_hook.dll` 实算哈希。
4. 时间线核对：以文件 mtime、帧时间戳（UTC→本地）、触发目录命名时间戳三方交叉验证。

---

## 1. A — 代码正确性　结论：PASS

### 1.1 身份判定在 hook 链上真正生效（非只改签名）　PASS
- `hook.cpp:263-280` `IsDiscoveryTarget(SOCKET s, const sockaddr_in* sin, uint8_t* flagsOut)`：先按目标判定（`INADDR_BROADCAST→LIMITED_BCAST(0x02)`、dst 端口 62900..62999→`DISCOVERY(0x04)`），新增 socket 身份判定（`hook.cpp:271-276`）：`SlotBoundPort(s)`（hook 观察到该 socket 曾 bind 的端口）落在 62900..62999 且尚未标 DISCOVERY → 补标 `CIVLINK_FLAG_DISCOVERY`。
- 两调用点均传入判定结果：`Hook_sendto`（`hook.cpp:350`）、`Hook_WSASendTo`（`hook.cpp:383`，附加 `VIA_WSASENDTO(0x01)`，仅观察非 overlapped）。
- `ForwardFrame`（`hook.cpp:288-334`）成功投递时按 `flags & CIVLINK_FLAG_DISCOVERY` 分类计数：DISCOVERY→`c_sent`、否则→`c_observed`（`hook.cpp:321-325`）。因此身份判定不是"只改签名"——它直接改变帧的 flags 与计数分类，端到端证据（§2.1）证实其真实生效。

### 1.2 纯观测、不吞包　PASS
- `Hook_sendto`（`hook.cpp:337-365`）任何分支最终都以**原始参数**调用 `Real_sendto(s, buf, len, flags, to, tolen)`（`hook.cpp:364`）并返回原结果；`Hook_WSASendTo` 同理（`hook.cpp:398`）。游戏发送从不被改动/吞掉。
- `g_inFlight`/`g_tlsInHook` 递归防护：hook 自身的 IPC 发送走 `Real_sendto`，不会被再观察。
- 转发失败只计数（`c_sendFail`/`c_channelDown`/`c_cvlh2Errno`）不重试（`hook.cpp:326-333`）；oversize 走 `REJECTED_OVERSIZE|NO_PAYLOAD` 通知帧而非静默丢失（`hook.cpp:306-316`）。

### 1.3 SlotBoundPort 在 bind 失败/未 bind 时的语义　PASS（含一处建议）
- `Hook_bind`（`hook.cpp:419-441`）**仅当 `rc==0` 且端口非 0** 时记录 `boundPortBe`；bind 失败或未 bind → `SlotBoundPort` 返回 0 → 身份判定不触发，回落到目标端口/广播判定（语义正确，不会误标）。
- **局限（建议项 S-1）**：身份判定只依赖 hook 观察到的 bind，无 getsockname 回退。若 hook 注入晚于 socket bind（对已建房的运行中 Civ6 附加注入），`SlotBoundPort` 为空 → 单播广告页会被计为 OBSERVED 而非 DISCOVERY。RUNBOOK v3 已声明"必须先注入、后建房（或注入后重进大厅重建 bind）"，E2E 时间线（§5.2）与此约束一致；建议后续增加 `EnsureLocalEndpoint` 缓存（getsockname srcPortBe）作为身份回退，或至少将"注入后须重新触发发现 socket bind"固化为可验证检查。

### 1.4 线程安全（SRWLOCK）　PASS
- 槽表 `g_sockSlots[64]` + SRWLOCK：`SlotSetBoundPort` 排他（`hook.cpp:153-163`）、`SlotBoundPort` 共享（`hook.cpp:166-178`）、`LogicalSocketId` 排他（`hook.cpp:123-150`）、`EnsureLocalEndpoint` 排他（`hook.cpp:199-222`）、`ForgetSocket` 排他。读写路径锁配对正确，无发现路径上持锁做网络调用。

---

## 2. B — 端到端证据真实性　结论：PASS（一处触发侧证据缺口，见 §5）

### 2.1 页面确实经 P1（hook 链）而非 P2 回环　PASS（决定性）
- 终轮以 `--sim-real-capture` 运行且**未启用 `--sim-lan-listen`**：console 启动行仅 `civlink-agent 0.3.0 listening on 127.0.0.1:34718 for 300s`；summary 的 simulated host 块 `requests seen=0 / replied=0 / pages sent=0 / bind fail=0`——无任何 LAN 监听活动，P2 直收路径不可能参与。
- 22 帧为 **CVLH2 帧**（42B 头 + 1104B payload，经 IPC 127.0.0.1:34718 到达）——CVLH2 帧只能由 `civlink_hook.dll` 产生；agent 的 P2 路径收原始数据报并标 `"P2-lan"`（`main.rs:640`），本证据全部为 `"P1-hook"`。
- **身份判定端到端生效的直接证明**：22 帧 dst 端口全部为 **54322**（`dst ports=1 (min 54322, max 54322, in 62900..62999: 0)`），而 agent 捕获入口 A（`main.rs:1797-1810`）要求 `flags & FLAG_DISCOVERY != 0`。dst 54322 不在 62900..62999 内——若仍按旧的目标端口过滤，这些帧会被 hook 标为 OBSERVED(0x20)，**根本不会进捕获**。`discovery_flag=22` ＋ `dst 端口 62900..62999 内:0` 组合只能由 socket-身份判定产生。

### 2.2 stderr 22 行与 manifest 22 页对应　PASS（含上一轮疑点澄清）
- 终轮 `stderr.txt`（1,267B，mtime **10:29:06**，SHA-256 `D6A0CBDC…AEF`）＝22 行 `[+] B1 real advertisement page N/22 captured via P1-hook`；mtime 与帧到达时间 02:29:06.559–06.638 UTC（=本地 10:29:06.559–06.638）吻合，**属本轮而非上一轮**。
- 上一轮（`b1-p1-agent-2-20261117-102557\`）另有自己的 `stderr.txt`（同样 1,267B，mtime 10:26:35）——两轮各捕获 22 页所以行数与字节数相同；两文件独立存在，非复制关系。
- 22 页 `real-page-01..22.bin` 的独立 SHA-256 与 `real-ad-manifest.txt` 比对 **0/22 不匹配**（22 项全对）。

### 2.3 summary 对账自洽　PASS
- `datagrams=22 bytes=25212 received=22 processed=22 rejected=0`，`reconciliation 22==22`；`session frames=22 first_seq=145 last_seq=166 gaps=0 dup=0 out_of_order=0`；`payload_bytes=24288 discovery_magic=0 other_payload=22 via_wsasendto=0 limited_bcast=0 discovery_flag=22 no_payload=0`；`logical sockets=1`；`src endpoints 0.0.0.0:62900 x22`；B1 块 `captured=22 rejected=0 duplicates=0 noise=0 replies real=0 fixture=0 skipped=0 active=yes`。全部闭环。
- `seq=145..166`（非从 1 起）与 hook 注入长时间运行中的 Civ6 后 `g_seq` 持续累积一致，支持"hook 于 10:23–10:26 前注入 pid 37528"的时间线推断（§5.2）。

### 2.4 页面哈希与 §0 取证内容比对　PASS（仅 head 可比）
- §0（run-20261117-095336）只留存页头：`client-received.csv` 每行 8B 头、`ad-sendto-slice.txt` 每行 16B 头（`data=59 60 69 9b 2e 69 04 00 00 00 00 00 03 00 00 00 ...`）——**全页字节级比对无源可比**（取证时未落全页）。
- 可比部分逐字节一致：`real-page-01.bin` 头 16B `59 60 69 9B 2E 69 04 00 00 00 00 00 03 00 00 00` ＝ §0 civtrace sendto data 头。
- **真实内容判定（更强）**：`real-page-01.bin` 偏移 24..45 为 `dingzihan2022`＋`的房间`（`64 69 6e 67 7a 69 68 61 6e 32 30 32 32 e7 9a 84 e6 b8 b8 e6 88 8f`）——即真实房主房名（fixture 的匿名化区域正是同一偏移 24..46，内容为 `CivLink-Test-Room-2222`）；`real-page` 与 `sim-page` 全量 SHA-256 22/22 不同。页面确为真实房主页面而非 fixture 或伪造。
- 发送形态同构：frame `src=0.0.0.0:62900 dst=26.74.126.98:54322 len=1104` 与 §0 `sendto s=0x13f0 bound=0.0.0.0:62900 dst=26.74.126.98:54322 len=1104 ret=1104 caller=CivilizationVI_DX12.exe+0x860552`（09:53:36.595，22 连发）完全同构——E2E 是对真实发送形态的复现（由 Civ6 本体在触发下发出，非重放工具）。

### 2.5 证据双份一致　PASS
- `M0A\captures\B1-p1-e2e-20261117-102852\`（51 文件）与 `C:\Users\dd\Desktop\civlink-b1\b1-p1-final-20261117-102852\` 为一致副本：22 页 real-page 0/22 哈希不匹配；`summary.txt` `4F6279A5…`、`real-ad-manifest.txt` `2C3879F3…`、`frame-log.txt` `81A1EFB1…`、`stderr.txt` `D6A0CBDC…` 双份哈希全等（与 B1 文档 §5.1 声明哈希一致）；`real-page-01` `DDC8CD34…D99E8` 与文档声明一致。
- `civlink_hook.dll`（audit 树，10:18:14 构建，119,808B）实算 SHA-256 ＝ **`0965154ACC92424B957FD77ED6DC7FF497366DCAEC9F7758902E5E47424CE14C`**，与交付声明一致。

---

## 3. C — 登记口径　结论：PASS

- **证明**（B1 doc §5.1 / RUNBOOK v3 / CODEX-HANDOVER #18 口径一致）：真实 Civ6 房主（pid 37528，房间 `dingzihan2022`）的单播广告页（22×1104B，头 `59 60 69 9B`）可经 hook socket-身份判定（`civlink_hook.dll` 0965154A）→ CVLH2 帧 → agent `--sim-real-capture` 捕获并落盘（captured=22 / rejected=0 / duplicates=0 / noise=0 / active=yes、discovery_flag=22）。
- **不证明**（登记声明准确）：双机真实联机、B 机必可见房间、E2-A/E2-B/E3、Relay、Fake-IP、Noise、62056 数据面、双人真实对局；P2 对真实房主不可用（`run-20261117-100824` 实锤：房主占 `0.0.0.0:62900` → bind fail 1 port；且广告页单播到请求者临时端口）。
- CODEX-HANDOVER #18 对 §0 取证、hook 改造、E2E 结果与边界（"不证明双机场景 B 必可见、不勾 E2-A/E2-B/E3、不移动 Gate A/B"）的登记与本次审计结论一致。

---

## 4. D — 脚本与证据完整性　结论：核心证据完整，两处缺口＋一处勘误

### 4.1 frame-log 132B（首轮/次轮空表头）→ 3,454B（终轮）差异解释　PASS
- agent 启动即在 `--out-dir` 创建 frame-log 表头（132B = 2 行表头）；帧记录与 summary/real-page 仅在**干净收尾**（窗口到期或 stop 文件）时落盘。
- `b1-p1-agent-20261117-102150`：10:21:50 启动，触发 10:23:11 时捕获链未就绪（hook 尚未生效/身份未建立）→ 无帧、无 stderr/console/summary（仅表头＋sim 页备份）。
- `b1-p1-agent-2-20261117-102557`：10:25:57 启动（900s 窗口），10:26:35 触发已捕获 22 页（其 stderr 有 22 行），但 agent 被**中断未收尾** → frame-log 仍 132B 空表头、无 summary/real-page；console（123B）含启动行与一条 `[!] rejected datagram len=4 kind=short-frame (only 4 B, need 42)`（4B 裸数据报到达 IPC——来源未登记，疑为触发脚本或探测的杂散包；不影响终轮证据，终轮 rejected=0）。
- `b1-p1-final-20261117-102852`：10:28:52 启动（300s 窗口），10:29:06 触发捕获 22 帧，10:29:11 stop 文件 → 干净收尾 → frame-log 3,454B（表头＋22 帧，seq=145..166 无缺口）、summary.txt、real-page-01..22、manifest、stderr 全部落盘。差异解释成立。

### 4.2 stderr.txt 1,267B 与终轮一致（非上一轮）　PASS
- 见 §2.2：mtime 10:29:06 与终轮帧到达吻合；上一轮 stderr 独立存在于 `b1-p1-agent-2-20261117-102557\`（10:26:35）。

### 4.3 证据缺口（建议项 S-2/S-3）
- **触发侧证据缺失**：`B1-triggerad-20261117-102635\` 与 `-102906\` **空目录**（0 文件）——触发脚本（`run-b1-trigger-ad.ps1`：绑 54322、发 100 magic 广播至 255.255.255.255:62900..62999、收 5s）创建目录后即中止（其 `$ErrorActionPreference='Stop'` 下找不到 civtrace 日志即 `Write-Error` 退出，符合空目录现象），故 E2E 两轮的 `client-received.csv`/报告未落盘。触发时刻由目录名（10:26:35 / 10:29:06）与帧到达时间三方吻合佐证，但客户端直收页缺失，无法与 real-page 做客户端侧全页比对。
- **注入操作无日志**：`civlink_ctl.exe inject` 进 pid 37528 的命令/时间无记录；`seq=145`（非 1）与"10:23 无捕获、10:26 起捕获成功"的时间线支持"hook 于 ~10:23–10:26 注入（或注入后重建发现 bind）"的推断，但无直接日志。尝试实读进程计数（`civlink_ctl.exe counters -x CivilizationVI_DX12 -p 37528`）因 `OpenProcess err=5`（未提升，SeDebugPrivilege 缺失）失败——无法当场确认 hook 仍驻留。
- 勘误：B1 doc §5.1 称证据目录"50 文件"，实为 **51**（22 real + 22 sim + manifest×2 + console + frame-log + stderr + stop + summary）。
- 终轮启动命令未留存：`start-b1-p1-agent.ps1`（600s、无重定向、无 stop）与终轮实况（300s、重定向、stop 文件）不符 → 终轮为手工运行，命令未记录（建议 S-3）。

---

## 5. E — 回归风险　结论：无回归（一处需登记的理论边界）

### 5.1 变更面
- 变更仅限 `hook.cpp` `IsDiscoveryTarget` 的 socket-身份判定（`hook.cpp:271-276`）。行为差异：**发现身份 socket**（曾 bind 62900..62999）向任意目标端口的 sendto，由原 OBSERVED(0x20) 改为 DISCOVERY(0x04)。

### 5.2 F1/F2 既有行为回归评估　PASS
- **F1**：`hook_selftest.exe` 实跑（§6）确认全部 F1 前置断言仍 PASS（`sent==2/3/4`、`sendFail==0`、`rejectOversize==1`、`observedFrames==1/2/3`、`sentNotify==1`、`cvlh2Try/Ok==7`、`rawSendtoCalls==7`、`sockTableOverflow==0`、`srcEndpointUnknown==1` 等）——身份判定不破坏既有计数路径与 §4.4 恒等式。
- **F2/62056 数据面**：Civ6 数据面 socket 绑 `0.0.0.0:62056`（不在 62900..62999）→ 其发送仍按 OBSERVED 转发，**不受影响**。agent 侧无 FLAG_OBSERVED 特判（仅 `FLAG_DISCOVERY=0x04`，`main.rs:52`），OBSERVED 帧仅进通用统计。
- **理论边界（登记项 S-4）**：若发现身份 socket 向 62056 等数据端口发送，该帧将标 DISCOVERY → agent F3-A 直转路径按"发现帧走 F1 路径、排除直转"处理（`main.rs:1826-1829`）。真实 Civ6 中该组合不发生（发现 socket 与数据 socket 分离），但建议在文档中登记该语义，避免 B2 数据面改造误读。

---

## 6. 机械证据：8 个 FAIL 的逐项裁定（实跑复现，2026-11-17 ~10:41）

`hook_selftest.exe`（audit 树，10:18:15 构建）在 Civ6 pid 37528 持 `0.0.0.0:62056` 状态下实跑：**47 PASS / 8 FAIL / 共 55 项**，`HOOK-SELFTEST: FAIL (8 failure(s))`，exit 1。8 个 FAIL 明细与归因：

| # | 断言 | 归因 | 判定 |
|---|---|---|---|
| 1 | `bind 127.0.0.1:62056 returns 0` | Civ6 持 `0.0.0.0:62056` → 127.0.0.1:62056 bind 得 WSAEADDRINUSE | 环境冲突 |
| 2 | `rawBindCalls == 2 (sb 62056 + sdSock 127.0.0.1:0)` | **测试脚本缺陷**：B1 用例 idSock 的 127.0.0.1:62905 bind（`hook_selftest.cpp:217`）未计入预期 → 实际 3 ≠ 2；注释漏算。**无 Civ6 冲突也 FAIL** | 脚本缺陷 |
| 3 | `bind62056Count == 1` | 1 的级联：sb 未绑定成功 → 计数 0 | 环境冲突 |
| 4 | `recvfromOn62056 == 1 (recvfrom path)` | 级联：sb 未绑定 → 62056 socket 判定不命中 | 环境冲突 |
| 5 | `WSARecvFrom → WSA_IO_PENDING` | 级联：未绑定 socket 的 WSARecvFrom 立即返回错误（非 WSA_IO_PENDING） | 环境冲突 |
| 6 | `recvfromOn62056 == 2` | 级联（同 4/5） | 环境冲突 |
| 7 | `wsarecvfromPending == 1` | 级联（同 5） | 环境冲突 |
| 8 | `counters unchanged after shutdown (sent still 3)` | **测试脚本缺陷**：B1 用例 rc9 已使 `sent==4`（`hook_selftest.cpp:228` 实测 PASS），shutdown 块预期仍写死 3（`hook_selftest.cpp:316`），且 L300 的 counters 快照未被用作比较基准。**无 Civ6 冲突也 FAIL** | 脚本缺陷 |

- **产品缺陷：0 项**。6 项确为环境冲突（Civ6 持 62056），2 项为测试脚本预期值缺陷（即使关掉 Civ6 仍 FAIL）。
- **B1 新增 4 用例全 PASS**：`bind 127.0.0.1:62905 (discovery socket identity) returns 0` / `unicast reply from discovery-bound socket to 54322 returns 4` / `sent == 4 (rc9 counted as DISCOVERY by socket identity)` / `observedFrames == 3 (unicast reply NOT observed)` —— socket-身份判定的机械验证成立。
- 注意：CODEX-HANDOVER #18 所述"selftest 新增 4 用例全 PASS"指新增用例本身（属实），但未登记整体 8 FAIL 状态；报告与登记链应补齐该状态说明。

---

## 7. 必改项

1. **（证据工具）修正 `hook_selftest.cpp` 两处断言预期值并复跑**：
   - `hook_selftest.cpp:242` `rawBindCalls == 2` → 预期改为 3（计入 idSock 的 62905 bind），或按"detour 入口计数全部 bind"口径更新注释与期望；
   - `hook_selftest.cpp:316` `sent still 3` → 改为 4，或将 shutdown 前快照（L300 `counters(&c)`）用作对比基准（"counters unchanged"语义应比较快照而非绝对 3）。
   - 复跑目标：在无 Civ6 冲突环境应 **47 PASS（0 FAIL）**；有 Civ6 冲突时应余 **6 项环境冲突 FAIL** 且可复现归因。修复后更新 B1 doc §5 与 CODEX-HANDOVER #18 的状态登记（当前仅登记"4 用例 PASS"，未登记整体 8 FAIL）。

## 8. 建议项

- **S-1**：`IsDiscoveryTarget` 增加 getsockname（`EnsureLocalEndpoint` 缓存的 srcPortBe）身份回退，覆盖"注入晚于 bind"场景；或把 RUNBOOK"先注入后建房/重进大厅重建 bind"约束固化为启动前可执行检查（如 `civlink_ctl status` 后触发一次发现 socket bind 自检）。
- **S-2**：补齐触发侧证据——修复 `run-b1-trigger-ad.ps1`（civtrace 日志缺失时改为可选告警而非 `Write-Error` 中止），使 E2E 轮也落盘 `client-received.csv` 与报告，形成"客户端直收页 ↔ agent 捕获页"全页哈希闭环（本次仅 head 可比）。
- **S-3**：将终轮 agent 手工运行命令固化为可复现脚本（含 `--listen-seconds 300`、stdout/stderr 重定向、stop 文件机制），并登记注入命令（`civlink_ctl.exe inject -x CivilizationVI_DX12.exe -p <pid> -d civlink_hook.dll`）及其时间戳，闭合"注入→建房→触发"证据链。
- **S-4**：在 B1 文档登记"发现身份 socket 向数据端口发送的帧标 DISCOVERY、F3-A 直转排除"语义（`main.rs:1826-1829`），供 B2 数据面改造参考。
- **S-5**：B1 doc §5.1 证据目录文件数勘误：50 → 51。

---

## 9. 证明 / 不证明清单

**证明（本次提交件可支撑）**：
1. 真实 Civ6 房主（房间 `dingzihan2022`）的发现广告页为**单播应答到请求者源地址:源端口**（§0 run-20261117-095336 取证：22 条 `sendto s=0x13f0 bound=0.0.0.0:62900 dst=26.74.126.98:54322 len=1104`）。
2. 新 `civlink_hook.dll`（SHA-256 `0965154ACC92424B957FD77ED6DC7FF497366DCAEC9F7758902E5E47424CE14C`）的 socket-身份判定（`hook.cpp:271-276`）端到端生效：dst=54322（非 62900..62999）的 22 页全部以 `FLAG_DISCOVERY` 帧经 P1 链转发（`discovery_flag=22`、dst 端口 62900..62999 内=0）。
3. agent `--sim-real-capture`（无 `--sim-lan-listen`）捕获真实房主 22 页并落盘：`captured=22/rejected=0/duplicates=0/noise=0/active=yes`，`datagrams=22=received=processed=22`，seq 145..166 无缺口。
4. 捕获页面为真实房主内容：头 16B 与 §0 取证一致；偏移 24..45 为真实房名 `dingzihan2022`（fixture 匿名区同偏移为 `CivLink-Test-Room-2222`）；与 sim-page 22/22 不同。
5. 机械层面：hook_selftest B1 新增 4 用例全 PASS；F1/F2 既有断言无回归（6 项 FAIL 为 Civ6 环境冲突、2 项为测试脚本预期值缺陷、0 项产品缺陷）。
6. hook 保持纯观测（`Real_sendto` 原参返回，不吞包、不改包）。

**不证明（登记口径）**：
1. 不证明**双机真实联机**（B 机刷新可见 A 机真实房间——需 RUNBOOK v3 双机步骤执行，用户操作）。
2. 不证明 **E2-A / E2-B / E3**（联机/E2-B 客户端日志/E3 三机场景）。
3. 不证明 **Relay / Fake-IP / Noise**（§4.5 设计项，B2+ 阶段）。
4. 不证明 **62056 数据面**转发（F2 仅本地探针语义；B1 只捕获/缓存广告页）。
5. 不证明 P2 直收对真实房主可用（实测不可用：房主占 `0.0.0.0:62900`＋单播到临时端口）。
6. 不移动 **Gate A/B**（Gate A 未批准、M0-B 冻结）。
7. 页面**全页字节级**与 §0 客户端直收内容比对不可行（§0 仅存 8B/16B 头），仅 head 与内容特征可比。

---

## 10. 附录

**终轮证据关键哈希**（独立计算，与文档声明一致）：
- `summary.txt`（3,465B）`4F6279A547B583EA7768A5AE7E3AB7B94B9E360991320471FE62B3989237BEA0`
- `real-ad-manifest.txt`（2,266B）`2C3879F38C24D41ADEEB0238564E4BB714AA439356C2434CA4E88E2D2BBA4873`
- `frame-log.txt`（3,454B）`81A1EFB19C51D4FBF1501589B999CB98C130845675D15155C87CAFE829ED3E8E`
- `stderr.txt`（1,267B）`D6A0CBDC622F1ECAFA394C02ECDDB402136CF359623EDE7B52C1323871623AEF`
- `real-page-01.bin` `DDC8CD34D85EB43B218F6A4DB8B6867ECFB9C703623B69C3AAF7A93D8D6D99E8`
- `civlink_hook.dll`（119,808B，10:18:14）`0965154ACC92424B957FD77ED6DC7FF497366DCAEC9F7758902E5E47424CE14C`
- release `civlink-agent.exe`（417,792B，R-2/R-3 后）`DDAF5453B35377493ABA4F464ADFC341A153861CEC1352D97F07FBBE21113D63`
- manifest 22 页独立复核：0/22 不匹配；M0A 与 civlink-b1 双份：22 页 0/22 不匹配、4 个文本文件哈希全等。

**时间线**（2026-11-17）：
- 09:39:10 Civ6 pid 37528 启动（持 `0.0.0.0:62056/62900/62993/64840-64871`）；09:39:51 civtrace 会话（093951，至 09:40:42 止）。
- 09:53:36 §0 触发（run-20261117-095336）：客户端 54322 直收 22 页，结论"单播"。
- 10:18:14–15 新 hook（0965154A）与 `hook_selftest.exe`/`civlink_ctl.exe` 构建。
- 10:21:32/10:21:50 run-1/run-2（102132 空；102150 仅 sim 页＋空表头，无捕获）。
- 10:23:11 触发（目录 1 文件，无报告）。
- 10:25:57 run-3（102557，900s）；10:26:35 触发 → 捕获 22 页（stderr）但被中断未收尾。
- 10:28:52 终轮（102852，300s，sim 页转储）；10:29:06 触发 → 22 帧（seq 145..166）经 P1；10:29:11 stop 文件 → 干净落盘。
- 10:33:06 B1 doc v1.1；10:34:40 RUNBOOK v3；10:36:48 CODEX-HANDOVER #18（登记）。

**审计环境备注**：本机 IPv4 = 26.74.126.98（另 198.18.0.1/192.168.31.60/192.168.191.3/172.23.16.1）；`civlink_ctl counters` 实读 pid 37528 因权限（err=5）不可用；Civ6 全程运行，62056 冲突状态可复现。
