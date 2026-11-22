# F0 固定模拟房主夹具 · 交付与真实回归记录（2026-11-13 交付 / 2026-11-14 真机回归）

> 依据：`REV-016-SIMULATED-PEER-FAST-TRACK.md` §3 的 **F0** 阶段。
> 本文先记录机器可验证部分的交付，再记录**真机 20 次刷新回归**的实测结果；
> 两部分证据等级不同，引用时必须分开。

---

## 0. 一句话结论

F0 **两个部分都已完成**：①机器可验证部分（模拟房主脚本、证据校验器、校验器自身的变异测试、
无 Civ6 的端到端自检）已交付并实跑全绿；②**人力部分（真实 Civ6 客户端 20 次刷新）已于
2026-11-14 00:04–00:08 执行完毕**，模拟房主收到并响应了全部 **20 次**刷新，证据目录
`M0A\captures\F0-run-20261114-000141` 通过校验器 **ALL PASS（0 failures, 0 warnings）**。

> 该结论的边界：**"20 次刷新里 20 次都发出了请求、都得到了完整 22 页响应"是机器测得的**；
> "每次都在列表里看到房间"是操作者口述的，两者不是同一件事——本轮操作者观察到的是
> **"有时看得到、有时看不到"**。差异原因未裁决，见 §2.5。

---

## 1. 交付物与文件身份

目录：`CivLink-M0A-audit\scripts\F0\`

| 文件 | sha256 | 字节 | 职责 |
|---|---|---|---|
| `F0-run.cmd` | `18BBE233B71DE77239CBF6FCD49568B767E4D929534DEC6DD1B8D3A01291426D` | 5 367 | **唯一启动入口**：拉起 responder（预算 20 / 突发窗口 3 s / 监听 1 800 s），等 UDP 62900 就绪后打印 `READY <pid>`，随后等 `summary.txt` 落盘并自动调用校验器 |
| `F0-verify.ps1` | `1B24AD557A9959452DE61063959B4024CCE5CAB0320610B6C06D0837B1DC3DF1` | 16 424 | 8 节机器校验，退出码 0/1/2，写 `verify-report.txt` |
| `test-f0-verify.ps1` | `453F552A43F9240F6764B6D4BE07AFF0A58F1A83D0C1B80149B7FD23E15F2F3E` | 8 049 | 变异测试，8 组 17 条断言，证明校验器不是橡皮图章 |
| `F0-selftest.cmd` | `C3D3295F86921B4135A7D53E2DAD2DD8AE59EF0F024658705DBE3122A8A6A935` | 4 469 | 无 Civ6 端到端自检（纯环回，向 62957 而非 62900 发请求以证明全区间绑定） |

> 哈希按本文记录时点计算。任何文件一改即失效；复核方以自己重算为准，不要引用本表的旧值。

配套（未改动）：`CivLink-M0A-audit\scripts\synthetic-host-responder.ps1` v2.3
（sha256=`FDE71D31EAD82B3667793A7DAF4FCE98F75ED8CE4EF81E68F37B186F0EFCF244`/25 647 B）。

---

## 2. 机器部分实测结果（可复现）

### 2.1 无 Civ6 端到端自检（`F0-selftest.cmd`）

```
profile : range 62900..62999, budget 5, burst window 3000 ms, listen 20 s
responder pid=40336 bound_ports=100
SELFTEST-NET: replies=22/22 from_probe_port=22 wrong_length=0
SELFTEST-NET: responder exited naturally, code=0
...
MACHINE CHECKS: ALL PASS (0 failures, 0 warnings)
F0-SELFTEST: PASS (fixture + evidence chain verified)
```

证据目录：`M0A\captures\F0-selftest-20261113-234121\`

要点：
- **`bound_ports=100`**——全区间绑定成功（此前只绑 62900 的结构性漏包缺陷已不复发）。
- **`from_probe_port=22`**——22 个回复全部从收到请求的那个 socket 回发（源端口 = 请求目标端口）。
- **`replies=22/22`、`wrong_length=0`**——页数与页长均正确。
- **`exited naturally, code=0`**——responder 自行收尾（不是被强杀），因此 `summary.txt` 是完整落盘的；这正是上一版手工 `Stop-Process` 造成 summary 缺口的原因。

### 2.2 校验器变异测试（`test-f0-verify.ps1`）

种子：`M0A\captures\E2B-synthetic-v22-real-20261113-122548`
（当前最完整的真实运行证据：2 次响应、99 端口绑定、`receive errors 0 unexpected`）。

```
cases: 17   failures: 0
verdict: ALL ASSERTIONS PASS
```

| 组 | 变异 | 断言结果 |
|---|---|---|
| A | 原样健康证据 | 退出 0 + `MACHINE CHECKS: ALL PASS` + 报告落盘 |
| B | 清空 `requests.log`、summary 改 0 | 退出 1 + `FAIL requests.log contains no RESPONSE block` |
| C | 删除 `precheck.txt` | 退出 2 + 报文点名该文件 |
| D | `sent-reply-05.bin[500] ^= 0xFF` | 退出 1 + `manifest sent digest ... != file digest` |
| E | `sent-reply-07.bin[160] = 0x63` | 退出 1 + `page index field 99 != 6` |
| F | `receive-errors.log` 写成 BOM-only | 退出 1 + `only a UTF-8 BOM` |
| G | 追加第 3 个 RESPONSE 且 budget 降为 2 | 退出 1 + `exceed the budget` |
| H | 删除 `sent-reply-11.bin` | 退出 2 + 报文点名该文件 |

**这一步的意义**：一个只在好输入上通过的校验器等于没有。上面每一组都证明校验器会**真的**报错，
而不是把问题静默放过。

### 2.3 启动器退出码路径（实跑验证）

- 端口已被占用 / responder 20 s 内没绑上 → 打印 `NOT-READY` 并以 **退出码 3** 中止，
  不强制杀进程、不复用端口。实测：用短窗口变体复现过一次 `NOT-READY` → `F0-RUN: ABORT` → `EXIT=3`。
- responder 正常收尾 → 自动跑校验器 → 以**校验器退出码**退出（实测 `EXIT=1`，对应"本次无响应"的
  `FAIL requests.log contains no RESPONSE block`）。

### 2.4 真机 20 次刷新回归（2026-11-14，`F0-run-20261114-000141`）

环境：真实 Civ6 `CivilizationVI_DX12` pid=40152 停在**局域网列表（客户端角色）**，未建房；
responder pid=29900（`-MaxResponses 20 -BurstWindowMs 3000 -ListenSeconds 1800 -PostResponseSec 30`）；
`precheck.txt` 记录绑定前该端口段占用为 0。

```
run time        : 2026-11-14 00:08:58 (window 436 s)
bound ports     : 62900..62999 (100 bound, skipped none)
responses sent  : 20 (budget 20)
pages per resp  : 22 (each once, per-page SHA256 in requests.log)
request ports   : 62900..62999   ← 100 个端口全部出现过
requests logged : 480            post-response datagrams: 2680
receive errors  : 0 unexpected, 0 expected(would-block)
select errors   : 0 unexpected, 0 expected(abort)
```

首次响应 `00:04:19.896`、末次 `00:08:28.332`；20 个请求全部来自 `26.74.126.98`
（Radmin VPN 网卡，`iface=21`），仅最前两次 `iface=0`。

`F0-verify.ps1`（sha256=`1B24AD55…`）对该目录结论：

```
MACHINE CHECKS: ALL PASS (0 failures, 0 warnings)
```

- 第 5 节逐个断言了 **20 个 RESPONSE 块**：每块 22 页、顺序 01..22、每页 1 104 B、
  源端口 62900、摘要与 `sent-reply-NN.bin` 一致。
- 第 6 节：`receive-errors.log` 为 0 字节且两个 unexpected 计数为 0——**没有异常被吞掉**。
- 第 4 节：summary 的六项与 `requests.log` 一致，未超预算。

报告落盘：`M0A\captures\F0-run-20261114-000141\verify-report.txt`。

### 2.5 本轮的两个新观察（F1 必须用）

**观察 A：客户端不只是"点刷新才发"，还会自己补发整组突发。**

把 `post-response-traffic.log`（2 680 行）按 500 ms 间隔聚类，得到 **27 组突发**，
每组 99 或 100 个数据报、跨度 82–112 ms：

```
00:04:19.955(99) 00:04:26.115(99) 00:04:30.103(99) 00:04:33.509(99)
00:04:35.907(100) 00:04:40.067(99) 00:04:43.547(99) 00:04:46.036(100)
00:04:48.719(99) 00:04:51.288(100) 00:04:54.696(99) 00:05:07.391(99)
00:05:13.043(99) 00:05:19.519(99) 00:05:27.480(99) 00:05:29.960(100)
00:05:45.557(99) 00:05:48.445(100) 00:05:53.836(99) 00:05:59.470(99)
00:06:02.086(100) 00:07:57.745(99) 00:08:05.433(99) 00:08:14.438(99)
00:08:23.745(99) 00:08:28.369(99) 00:08:32.501(100)
```

**逐组对账（可以精确校验，不是估计）**：

| 类型 | 组数 | 每组包数 | 说明 |
|---|---|---|---|
| 触发了响应的突发 | 20 | 99 | 触发包停在 `62900` 记入 `requests.log`，其余 99 包记入 post-response |
| 未触发响应的突发 | 7 | 100 | 全部包都在 post-response 内 |

20×99 + 7×100 = 1 980 + 700 = **2 680**，与 summary 的 `post-response datagrams: 2680` 完全吻合。

7 组未触发突发的间隔（相对前一组）：**2.40 / 2.49 / 2.57 / 2.48 / 2.89 / 2.62 / 4.13 s**。
前 6 组落在 `-BurstWindowMs 3000` 内 → 记为 `coalesced, no extra reply`（共 2 481 条）；
第 7 组（`00:08:32.501`，间隔 4.13 s）到达时预算已用尽 → 记为
`MATCH but budget exhausted (20 reached); passively recorded only`（共 199 条）。

2 481 + 199 = 2 680，第二层对账也吻合。

**对 F1 的含义**：
1. Hook 侧**不能**假设"每点一次刷新只有一组突发"，也**不能**假设两次刷新之间没有流量；
   计数闭合必须按"每次突发"对齐，不能按"每次用户操作"对齐。
2. 出现 6 次"约 2.5 s 后补发一整组"的现象，与"客户端没拿到/没接受上一轮的公告就会重试"
   这一常见模式相符——**但本轮数据不足以区分**"客户端重试"与"用户连点了两次"，
   不得写成结论。F1 接上 Hook 后可用"发送方线程/调用点 + 与用户输入时刻对齐"来判定。

**观察 B：机器侧 20/20 全收到并全回，但操作者口述"有时看得到、有时看不到"。**

这两个事实不冲突，但也不能用前者否定后者——机器只能证明"请求被收到、22 页被发出"，
**无法证明客户端是否把该公告画进列表**。结合观察 A（客户端自身有周期性重发与合并），
一个待验证的假设是：客户端对同一房间公告的处理/去重带有时序敏感性，而不是模拟房主漏回。
**该假设未验证，不得写成结论**；F1 接上 Hook 后应同时记录"客户端收包时刻"与
"列表项出现/消失时刻"，才能把两者对齐。

---

## 3. 校验器实际检查的 8 节

1. **必需文件**：6 个证据文件 + 22 张 `sent-reply-NN.bin`；缺任一 → 退出码 2 并打印完整报告。
2. **页镜像**：每页 1 104 B、magic `59-60-69-9B`、`[156]`=22、`[160]`=自身 0 基页索引、
   `[1102..1103]`=`00-00` 零尾标。
3. **`fixture-hashes.txt`**：22 行格式正确；每页 sent 摘要与磁盘重算一致；变更偏移必须落在
   `24..45`（房间名字段）。**不断言偏移个数 = 22**——匿名名可能与原名共享字节，真实证据实测为 21 个。
4. **`summary.txt`**：responses/budget/bound/requests/receive errors/select errors 六项；
   缺 `select errors` 行只 WARN（v2.3 以前的历史证据），但"声明有错 + 日志为空"是 FAIL。
5. **`requests.log`**：每个 `RESPONSE #N (from dstPort P)` 块必须 22 行 page 行、顺序 01..22、
   每条 1 104 B、源端口等于该块 `dstPort`、摘要与 `sent-reply` 一致；超预算或与 summary 不一致即 FAIL。
6. **`receive-errors.log`**：0 字节 且两个 unexpected 计数为 0；只有 3 字节 BOM 会被判 FAIL。
7. **`precheck.txt`**：回显绑定前的端口占用决策。
8. **F0 退出条件**：机器部分逐条指向上面的小节；**人力部分只能由人确认**。

---

## 4. 人力部分：已执行（2026-11-14 00:04–00:08）

```bash
scripts\F0\F0-run.cmd          →  等 READY <pid>
Civ6 → 多人 → 局域网（客户端）  →  刷新 20 次，约 6 s 一次
每次记：是否看到 CivLink-Test-Room-2222 / 是否超时 / 有无报错
关掉游戏后回到该窗口          →  自动校验并打印 --- F0 result ---
回传：证据目录路径 + verify-report.txt + 逐次刷新记录
```

本轮结果：

| 项 | 结果 |
|---|---|
| 刷新次数 | 20（预算刚好用尽） |
| 模拟房主收到请求 | **20 / 20**（每块 22 页全部发出，摘要可校验） |
| 机器校验 | **ALL PASS（0 failures, 0 warnings）** |
| 操作者观察 | **"有时看得到、有时看不到"**——逐次是否显示未逐条记录 |
| 证据目录 | `M0A\captures\F0-run-20261114-000141\` |

- **不要自己建房**：房主大厅会占用 UDP 62900 及整个 62900..62999 段，responder 会拒绝绑定并以退出码 3 中止。
- 每次刷新游戏只发 100 个发现包；预算 20 次响应刚好覆盖 20 次刷新。
- 刷新间隔约 6 s：落在 3 s 突发窗口内的重复请求会被当作合并请求，不再回复。

**未满足的部分（必须如实保留）**：F0 的退出条件里"20 次刷新每次都在大厅看到房间"这一条
**没有达成逐次确认**。已达成的是"20/20 请求被接收并完整响应、证据链可机器校验"。
因此 F0 只能记为"**夹具与证据链通过，客户端可见性仍未逐次确认**"。

---

## 5. 边界（引用时必须照抄）

- F0 通过 = **"模拟房主按设计工作、公告页逐页可校验、真机 20 次刷新全部被接收并完整响应"**。
- **不是**两台真实 Civ6 对局；**不是** E2-B；**不是** M0-B；**不是**多人联机验证；**不移动任何 Gate**。
- 允许表述：「本构建客户端在本机合成响应条件下接受该公告并显示列表项」（仅在确实观察到列表项时）。
- 允许表述：「模拟房主在真机回归中收到并响应了 20/20 次刷新，证据链通过机器校验」。
- **不允许**表述：「20 次刷新每次都看到了房间」——本轮操作者观察到的是"有时看得到、有时看不到"，
  逐次可见性未记录。
- 不允许表述：「联机已验证」「Relay 可用」「M0-B 通过」。
- 旧 M0-A 真实双机证据（E2-A/E2-B/E3）仍为"待验证"，模拟测试**不能**勾掉它们。

---

## 6. 本轮修掉的问题（留作教训）

1. **`F0-verify.ps1` 首次跑真实证据时 FAIL（1 failure, 22 warnings）**：一是断言"每页变更偏移恰好 22 个"，
   而实测为 21 个（匿名名与原名共享若干字节）；二是把"旧证据缺 `select errors` 行"当成失败。
   → 改为只校验偏移范围，并区分"缺该行（WARN）"与"声明有错但日志为空（FAIL）"。
   **教训：新校验器必须先跑真实历史证据再跑变异测试**——真实数据会暴露"合理但过严"的断言。
2. **缺文件时只打印一行摘要、不打印报告** → 变异用例 C/H 抓出；早期退出分支改为先输出整份报告再退出 2。
3. **预算越界用例打不到目标分支**（只追加 RESPONSE、summary budget 未改，触发的是"与 summary 不一致"分支）
   → 用例同时把 summary 改成 `responses sent : 3 (budget 2)`。
4. **`F0-run.cmd` 首版手工 `Stop-Process` 收尾** → `summary.txt` 不落盘、证据不完整。
   → 改为等 responder 自然收尾（轮询 `summary.txt`），超时 1830 s 才退出 4。
5. **`F0-selftest.cmd` 首版用 `%date%` 生成目录名** → 中文环境的星期缩写进了路径
   （`F0-selftest-周五202611-233212`）。→ 改用 `powershell -Command "Get-Date -Format yyyyMMdd-HHmmss"`。
6. **cmd 的 `#` 注释头** → 被 `cmd` 当命令执行（`'#' is not recognized`）。→ 全部改成 `REM`。
7. **`echo ... ^(%WAITED% s^)` 在 `( ... )` 块内** → 出现 `for was unexpected at this time`。
   → 改为写在同一行、不用括号转义。

---

## 7. 下一步（按 REV-016 §3）

1. F0 真机回归已执行（§2.4），**结论记为"夹具与证据链通过、客户端可见性未逐次确认"**（§4、§5）；
   若要把可见性也变成机器证据，需要 F1 的 Hook 侧同时记录客户端收包与列表刷新时刻。
2. 进入 **F1：DLL + Agent 发现链路**（单真实 Civ6 客户端 + 模拟房主），
   判据见 `REV-016` §3 F1：Hook 命中正确 API、返回值/错误码/最后错误/socket 生命周期正确、
   不阻塞不静默丢包、本机通道计数闭合、关掉 Agent/DLL 行为可解释可恢复。
3. 仍不需要第二台电脑。
