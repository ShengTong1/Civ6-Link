# B1 真实广告页捕获 — 独立审计报告

- 审计对象版本：`docs/B1-REAL-ADVERTISEMENT-CAPTURE-20261117.md`（v1.1，2026-11-17）
- 审计员：独立子代理（f8918c50 对应本报告）
- 审计时间：2026-11-17
- 裁定：**有条件通过**（必改项 R-1/R-2/R-3 非空；机制本身正确，机械证据 PASS 13/13 成立，但统计口径两处错标、P1 路径对单播场景的覆盖被文档高估）

---

## 1. 审计范围

只读审计，未修改任何项目文件（唯一写入为本报告）。

| 对象 | 路径 | 备注 |
|---|---|---|
| 设计文档 | `docs/B1-REAL-ADVERTISEMENT-CAPTURE-20261117.md` | v1.1，133 行 |
| 实现代码 | `civlink/agent/src/main.rs` | 119,618 B，sha256 `3F9A754950ECCFDFE82F5598523A5EA61DB13F6DA1DFA56F2355C118B321B75F`（Get-FileHash 实测，与文档 §5 一致） |
| 相关代码 | `civlink/hook/hook.cpp`（IsDiscoveryTarget L257-268、ForwardFrame L276-322、Hook_sendto L325-353、Hook_WSASendTo L355-384） | P1 可达性佐证 |
| 测试脚本 | `civlink/run-b1-realcap-selftest.ps1` | 348 行 |
| 机械证据 | `docs/reports/b1/run-20261117-005925/`（51 文件：顶层 3 + `agent/` 48） | result.txt、summary.txt、real-page-01..22.bin、real-ad-manifest.txt、lan-page-01..22.bin、frame-log.txt、evidence-sha256.txt |
| 对比证据 | `docs/reports/b1/` 其余 12 个运行目录（manual-repro、probe-agent、003327/003718/004054/004343/004453/005600/010000 等） | 用于交叉验证计数规律 |
| 登记文档 | `README.md` L1333-1345、`docs/CODEX-HANDOVER-M0A.md` item 17 L125、`docs/B1-DUALMACHINE-RUNBOOK-20261117.md`（59 行） | 边界表述核查 |

验证手段：逐行读码；对证据文件做 sha256 与逐字节比对；在临时目录（$env:TEMP）运行 100-socket 广播回环探针（不写入项目）；核对全部 13 次运行的历史 summary 以确认计数规律。

---

## 2. 逐维度结论

### A. 机制正确性 — 通过（含 2 处统计口径缺陷与 1 处 P1 覆盖缺陷，见 §3）

- **识别规则**（main.rs:763）：`data.len() == SIM_PAGE_SIZE(1104) && data[..4] == SIM_MAGIC(59 60 69 9B)`，与文档 §2 完全一致；与 4B 客户端 magic（8D E8 FC 70）长度互斥，无歧义。✓
- **去重逻辑**（main.rs:764-775）：字节相同的既有页计 `duplicates`，不 push、不膨胀 `captured`，与文档 §4 及 README "重复页计 duplicates 不膨胀集合" 一致。✓
- **超 22 页不同页**（main.rs:776-782）：集合已满时新的不同页计 `rejected` 并关闭集合，符合文档契约。✓
- **捕获入口 A（P1，main.rs:1762-1769）**：要求 `flags & (REJECTED_OVERSIZE|NO_PAYLOAD)==0 && flags & FLAG_DISCOVERY != 0` 后进入 `try_capture`。**机械可达性已验证**：C2 手工编码 DISCOVERY 帧（seq=1/session=1，payload=page1）到达 IPC（summary `datagrams=1`、frame-log 单帧 `head=5960699B…`），并作为重复页计 `duplicates=1`（A12 成立）。✓
- **捕获入口 B（P2，main.rs:634-642）**：非 magic 数据报进入 `try_capture`，`--sim-real-capture` 开启时可达；C1 22 页广播全部经 P2 捕获（`captured=22`）。✓ 100-socket 回环探针证实无跨端口泄漏、无重复投递（62900 恰好收到 2 个数据报，其余 99 端口为 0），排除"双倍送达"假说。
- **应答策略**（main.rs:620-632 + 664-707）：`cache.active`（满 22 页）时 `real_pages` 为 Some → 用真实页；否则 fixture 兜底。C3 中首次请求（唯一一个 socket 54322）以真实页应答（A6 逐字节 == real-page-01.bin），`pages sent=22`。✓
- **fixture 兜底**：`consider` 在 real_pages 为 None 时回退 `self.pages`（加载时按 `--sim-room-name` 匿名化）。机械证据中从未触发真实 fixture 外发（见 R-3），该路径由既有 F5 跨机证据覆盖。✓（覆盖缺口见 §3 信息级 I-2）
- **CLI/落盘**：`--sim-real-capture`（main.rs:1405）默认关（:1338），零回归承诺成立；落盘 `real-page-*.bin` + `real-ad-manifest.txt`（main.rs:1882-1914）+ summary real-ad 块（:2097-2124）均实现。✓

### B. 证据一致性 — 有条件通过（数值自洽，两处语义错标）

数值核对（以 summary.txt、evidence-sha256.txt、manifest、real-page 文件、frame-log 交叉验证）：

| 项 | summary 值 | 独立核实 | 结论 |
|---|---|---|---|
| captured | 22 | real-page 文件 22 个；manifest 22 行；sha256 与 evidence-sha256 全对；**22/22 与发送源 fixture 文件逐字节一致**（SequenceEqual，如 real-page-01 == fixture reply-01，sha256 `ddc8cd34…`） | ✓ 自洽 |
| rejected | 2 | = C4 两个负向数据报（64B 噪声、1104B 全零）各 reject 一次 | ✓ 自洽 |
| duplicates | 1 | = C2 的 P1 帧（page1 已由 P1/P2 双路径投递，去重正确） | ✓ 自洽 |
| noise on disc | 23 | **语义错标**：仅 2 个是真实噪声，21 个是合法页（第 1..21 页捕获时 `try_capture` 返回 false，poll 计入 noise）——见 R-2 | ✗ 标签错误 |
| replies real | 1 | 唯一 socket 54322 的首次请求以真实页应答（A6 逐字节） | ✓ |
| replies fixture | 99 | **语义错标**：99 = 去重跳过的重复请求（`consider` 对已应答 key 返回 false），**本运行实际 0 次 fixture 外发**——见 R-3 | ✗ 标签错误 |
| requests seen / replied sockets / pages sent | 100 / 1 / 22 | 与脚本 C3（100 magic 单 socket）+ 应答逻辑吻合 | ✓ |
| active | yes | captured=22 == SIM_PAGE_COUNT | ✓ |
| listen window | 6.5s | stop 文件提前结束 45s 窗口，机制正常 | ✓ |

证据目录文件数：文档 §5 称"50 文件"，实测 **51**（顶层 3 + agent 48；evidence-sha256.txt 列出 49 条，不含自身与 stop 文件）——L-4。

### C. 边界表述 — 通过（一处 P1 覆盖高估除外，见 H-1）

四处登记口径全部正确，无任何越界宣称：
- 设计文档 §1 L21-25：只捕获/缓存；不修改游戏进程；不实现 Fake-IP/Relay/62056（B2+）；不证明双人对局、不证明 E2-B/E3、不移动 Gate A/B；Gate A 未批准、M0-B 冻结；双机验证需用户操作。✓
- README L1344-1345：**"B1 只证明'agent 能捕获真实广告页并用其应答'，不证明双人真实联机、不勾 E2-A/E2-B/E3、不移动 Gate A/B（Gate A 未批准、M0-B 冻结）"**。✓ 通过前不宣称「捕获能力已验收」。✓
- CODEX-HANDOVER item 17 L125：同口径。✓
- RUNBOOK L56-59：双机验证 = 捕获 + 应答可见性，不证明真实对局/62056 数据面。✓

全文未发现"双人真实联机已通过""E2-B/E3 已通过""Gate A/B 已批准"等字样。

### D. 脚本质量 — 有条件通过（断言真实有效，无自指断言；A8 语义在 R-2 修复后需加严）

- **断言真实性**：A3（captured==sent 22/22 逐字节）、A6（C3 首应答页 == real-page-01.bin，因捕获页含真实房名 `dingzihan2022` 而 fixture 兜底页含 `CivLink-Test-Room-2222`，字节必不同——A6 有真实判别力）、A7（rejected>=2 来自 C4）、A10（manifest sha256 == 文件 sha256）、A11（replied sockets>=1）、A12（duplicates>=1）均为跨源比对，**无自指断言**。✓
- **崩溃修复合理性**：`BeginOutputReadLine` 事件 scriptblock 在 PS 5.1 后台线程作用域解析问题导致 powershell.exe 进程级崩溃（exit 2，顶层 catch 抓不到，004054~010000 五次无 result.txt）→ 改为 .NET Task `ReadToEndAsync`+`Task.Result`（L83-87 注释说明），修复后 005925 单次即 PASS、exit 0、result.txt 54B 落盘。修复方向正确且与证据吻合。✓
- **缺陷**：A8（noise>=2）在噪声计数器被合法页污染时必然成立（manual-repro 无 C4 时 noise=21 仍满足），未真正验证 C4 负向效果——修复 R-2 后应改为 `noise == 2` 或补"非 magic 帧总数 == captured+rejected+duplicates+noise"恒等式断言（原 11 断言设计的 L91 恒等在此版本中已丢失）。见 S-1。
- **缺陷**：A6 仅逐字节校验首应答页，其余 21 页只计数。见 S-2。

### E. 代码质量 — 通过

- **健壮性**：生产代码路径无 `unwrap()/expect()/panic!`（grep 14 处全部位于 `#[cfg(test)]` 测试模块，L2319+）；`try_capture` 用 `unwrap_or(0)` 安全取值（L771）；poll 的 recv 循环处理 WouldBlock/TimedOut（L647-653）。✓
- **无竞态**：单线程事件循环，`RealAdCache` 由 run() 独占并借出（`&mut`），无共享可变状态。✓
- **可维护性**：B1 区块（L710-798）注释详实（识别规则、去重动机、full-set 语义均有说明）；统计字段逐项文档化（L720-732）；manifest/summary 输出结构化。✓
- **小瑕疵**：`try_capture` 对"第 23 个不同页"返回 true（L781），poll 据此置 `active=true`——语义上"拒绝一页却激活应答集"，虽因集合已满而实际无害，但接口返回值语义不纯（L-5）；`consider` L706 无条件返回 `real_pages.is_some()`，即使发送失败也计"使用了真实页"（L-6）。

---

## 3. 缺陷清单

### 阻断（0 项）
无。机制、证据、边界均未出现推翻 B1 主张的问题。

### 高（1 项）
| # | 位置 | 缺陷 | 影响 |
|---|---|---|---|
| H-1 | 设计文档 §3 L39-44、L56；RUNBOOK L22-23、L48-52；hook.cpp IsDiscoveryTarget L257-268；main.rs:1764 | **P1 对"单播到请求者"场景的覆盖被文档高估**。文档将"单播到请求者源地址"列为 P1 的合法目标并称 P1 为"确定性捕获路径"，但 `IsDiscoveryTarget` 仅对目标端口 ∈ 62900..62999（DISCOVERY）或目标地址 == 255.255.255.255（LIMITED_BCAST）返回命中；**单播到请求者临时端口（如 54322）时 flags=0，hook 根本不转发**；agent 入口 A（main.rs:1764）又强制要求 FLAG_DISCOVERY。因此若真实 A 机 Civ6 只把广告页单播给 B 机（E2-B 首轮 pcapng 未见主机广播广告页，RUNBOOK L48 自述），P1、P2 两条路径**均收不到页**，RUNBOOK 的"改用 P1"预案对单播场景无效 | 真实双机验证（RUNBOOK 执行）可能按失效预案失败；B1 目标（捕获 A 机真实页）在单播主机场景不可达 |

### 中（2 项）
| # | 位置 | 缺陷 | 影响 |
|---|---|---|---|
| M-1 | main.rs:638-641 + try_capture L790-796；summary L2105-2108 | **`noise_on_discovery_port` 语义错标**：`try_capture` 对合法页但在集合未满（第 1..21 页）时返回 false，poll 把 false 一律计为 noise。005925 的 noise=23 实为 21 个合法页 + 2 个真实噪声；summary 标签"(non-page datagrams on discovery ports)"与事实不符，且该错误数值被文档 §5、README L1340 原样转载 | 证据数值失真；下游读者会误判"广播端口存在 21 个噪声源" |
| M-2 | main.rs:677-679 + 630（poll 计数）+ 706；文档 §5 L105-106；RUNBOOK L43 | **`replies_used_fixture` 语义错标**：`consider` 对已应答 key 的去重跳过请求返回 false，poll 计为 `replies_used_fixture`。005925 的 99 全部是去重跳过，**本运行从未发出任何 fixture 页**；文档 L105-106"replies fixture=99 为 lan_sim 内部应答计数（fixture 兜底路径）"的定性是错的；RUNBOOK 判定"部分：replies fixture>0 → 走了 fixture 兜底"不可靠（真实页全部在用时该值仍 >0） | 统计与判定口径失真；无法区分"fixture 兜底应答"与"静默丢弃/去重跳过" |

### 低（2 项）
| # | 位置 | 缺陷 |
|---|---|---|
| L-3 | 脚本 C3/A6（首应答页比对） | A6 只对收到的第一个应答页做逐字节断言，其余 21 页仅计数（首包一致 + 22 页计数成立已足以证伪 fixture 兜底，但严格性可提升） |
| L-4 | 文档 §5 L99 | 称证据目录"50 文件"，实测 51（顶层 3 + agent 48；evidence-sha256 列 49 条不含自身与 stop） |

### 信息（3 项）
| # | 说明 |
|---|---|
| I-1 | C1 使用的"真实页"源即 `fixture-reply-set/reply-01..22.bin`，其房名字段本就是真实捕获的 `dingzihan2022`（fixture 文件在盘上未匿名化；agent 仅在加载应答时按 `--sim-room-name` 匿名化）。故 C1/C3 的"模拟真实页"与真实捕获产物字节同构，A3/A6 判别有效；脚本注释"fixture 与真实主机仅房名差异"表述不精确（磁盘文件未匿名化） |
| I-2 | fixture 兜底**外发**路径在全部 13 次 B1 运行中均未被触发（replies fixture 计数实为去重跳过）；该路径由既有 F5 跨机证据覆盖，B1 无需重复证明，但可视为机械覆盖空白 |
| I-3 | 13 次运行中仅 005925 为 PASS（13 checks/0 failures）且为采信轮；其余 FAIL/崩溃均属旧版二进制或脚本崩溃，与 ReadToEndAsync 修复因果吻合 |

---

## 4. 必改项清单

| 编号 | 级别 | 要求 |
|---|---|---|
| **R-1** | 高 | **消除 P1 单播覆盖的文档高估与预案失效**。二选一：(a) 代码扩展（推荐）：hook 的 `IsDiscoveryTarget`/转发逻辑对"1104B 且页头 magic"的 sendto 无条件转发（或按页形状识别），agent 入口 A 去掉 FLAG_DISCOVERY 硬依赖、改为"非 reject 帧 + 载荷命中 §2 识别规则即捕获"（main.rs:1762-1769 与 hook.cpp L257-268 同步改），使单播到请求者端口的真实页也可经 P1 捕获；(b) 若维持现状，必须修正设计文档 §3（删去"单播到请求者源地址"为 P1 合法目标、删去"P1 为确定性捕获路径"的表述，改为如实声明"P1/P2 仅覆盖目标端口在发现窗口或广播地址的发送；单播场景不可捕获"）并重写 RUNBOOK 故障排查（"改用 P1"对单播页无效），且应在双机验证前用 A 机真实 Civ6 建房 + 注入实测确认主机实际发送形态（广播 vs 单播）。 |
| **R-2** | 中 | **修正 `noise_on_discovery_port` 语义**：`try_capture` 改为对"合法页已处理"（含捕获、重复、满集拒绝）一律返回 true，仅对非页数据报返回 false（或 poll 改为按返回值三态区分）；相应修正 summary 标签（L2105-2108）与文档 §5、README L1340 转载值；修复后**重跑机械证据**，noise 应为 2（C4 两噪声），并加严 A8 为 `noise == 2` 或补恒等式"非 magic 帧总数 == captured+rejected+duplicates+noise"。 |
| **R-3** | 中 | **修正 `replies_used_fixture` 语义**：将 `consider` 的返回值改为三态（真实应答 / fixture 应答 / 未应答）或拆出独立计数 `replies_skipped`（去重跳过、src_port=0、max_replies、发送失败），`replies_used_fixture` 仅在真实外发 fixture 页时 +1；修正文档 §5 L105-106 的定性（99 非 fixture 兜底路径）与 RUNBOOK L43 判定口径（"replies fixture>0"不能作为"走了 fixture 兜底"的判据，需改为检查 `replies_skipped` 或日志）；修复后重跑并更新转载值。 |

> 说明：R-1 若不改代码而仅改文档，B1 的机械主张（"agent 能捕获真实广告页并用其应答"）仍成立，但双机验证的可用性取决于主机实际发送形态，须在 RUNBOOK 执行前实测确认；R-2/R-3 修复后建议重跑 `run-b1-realcap-selftest.ps1` 产生新的采信轮并同步 README/HANDOVER 转载值。

---

## 5. 可选建议

| 编号 | 建议 |
|---|---|
| S-1 | 恢复原 11 断言设计中的恒等式断言（captured+rejected+duplicates+noise == 非 magic 帧总数），作为统计自检护栏（本次两处错标若存在该断言即可暴露） |
| S-2 | A6 扩展为对全部 22 个应答页逐字节比对（脚本已有发送侧字节，成本低） |
| S-3 | 证据目录文件数声明改为动态生成或注明"51（49 条清单 + 自身 + stop）"（L-4） |
| S-4 | `try_capture` 返回值语义改为枚举（Captured/Duplicate/FullRejected/NotAPage），消除"拒绝也置 active"的隐晦（L-5） |
| S-5 | `consider` 成功判定细化：发送失败时不返回 `real_pages.is_some()` 的真值，避免"失败也计真实应答"（L-6）；并考虑在文档 §4 补充实现与设计字段差异（设计稿含 `saw_magic/first_at/last_at`，实现为 `duplicates/noise/replies_used_*`） |

---

## 6. 裁定

**有条件通过。**

理由：B1 的核心机制（识别规则、双路径捕获、去重、满集激活、真实页应答、fixture 兜底、CLI 默认关、落盘）实现正确且与设计一致；机械证据 PASS 13/13（run-20261117-005925）的关键断言（captured=22 与发送源逐字节一致、C2 去重、C3 应答升级 A6 判别、C4 负向 rejected=2、manifest/文件/哈希自洽）全部真实成立；边界表述（README/HANDOVER/RUNBOOK/设计文档 §1）准确，无任何越界宣称，B1 只证明"agent 能捕获真实广告页并用其应答"。

但存在必改项：R-1（P1 单播覆盖文档高估 + RUNBOOK 预案失效，高）、R-2（noise 计数错标，中）、R-3（replies fixture 计数错标，中）。R-2/R-3 使 summary 的两个统计标签失真并被文档原样转载，R-1 使双机验证预案存在失效风险。按审计规则，必改项非空 → **有条件通过**：上述三项修正 + 重跑机械证据 + 更新转载值后，可复审为通过。
