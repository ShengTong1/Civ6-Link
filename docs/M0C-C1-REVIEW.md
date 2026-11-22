# M0-C C1 审计报告 — agent `--reserve-62900` 改造

- 审计员：独立子代理（C1 审计任务书）
- 审计时间：2026-11-18
- 审计对象：
  - 代码：`civlink\agent\src\main.rs`（2871 行 / 124,700 B / sha256=11774041A2B8AFE0EC3C1DF4D8E639FEBB4871E1F69213093B6CB97F3CA347C0）
  - 脚本：`civlink\run-c1-reserve-selftest.ps1`（10,999 B / sha256=25738CFA8F3CBEF23C8542651FDC4FD9D00573357532498352A9DDDE9C18C89D）
  - 二进制：`civlink\civlink-agent.exe`（419,840 B / sha256=44DE339B6C885C69CD67330202EF40A764C3238AD7B69D9B216610AE81A33E17）
  - 证据：`M0A\captures\C1-reserve-selftest-20261118-0002\`、`M0A\captures\C1-f5-regression-20261118-0001\`
  - 计划：`docs\M0C-DUAL-ROLE-PLAN-20261118.md`（v1.0，8263 B）

---

## 一、裁定：**有条件通过**

C1 的机制、实现、证据与纪律全部成立：`--reserve-62900` 确实把 62900 留给游戏房主 socket（agent 运行时该槽位可绑定）、应答源正确回退到 62901、发现应答能力不损（99 包中任意 1 包到达即应答 22 页）、不加标志时 F5 默认行为完全不变、机械证据未被宣传为双人验证。唯一必改项为**版本号标识不一致**（见 C1-MUST-1，低严重级，不影响功能，但属可验证的 help 文本失实）。

---

## 二、必改项

### C1-MUST-1 — 版本号标识不一致（严重级：低）

- **依据**：`civlink\agent\Cargo.toml:3` `version = "0.3.0"`；二进制自报 `civlink-agent 0.3.0`（证据 `C1-reserve-selftest-20261118-0002\agent-console.txt:1`、`frame-log.txt:1`）；而 `main.rs:1369` 注释与 `main.rs:1529` `--help` 文本声称 `M0-C C1, v0.4.6`（计划文档标题亦为 v0.4.6）。
- **事实**：`civlink-agent --version` 输出 0.3.0，但 help 声称该特性属 v0.4.6；用户可见信息不一致。
- **修正**：二选一——Cargo.toml 版本升到 0.4.6 后重建并同步 exe 哈希链；或把注释/help 的 `v0.4.6` 改为 `0.3.0`。需同步更新 `docs\M0C-DUAL-ROLE-PLAN-20261118.md` 标题中的版本号。

---

## 三、建议项

按优先级排序：

1. **（中）10054 捕获逻辑脆弱**：`run-c1-reserve-selftest.ps1:144` 仅检查 `$_.Exception.InnerException.ErrorCode -eq 10054`。.NET 直接抛 `SocketException` 时 `ErrorCode` 位于 `$_.Exception.ErrorCode`（`InnerException` 为 null），该检查会失效并走 `throw`。此外，未 connect 的 UDP socket 在 Windows 上默认不报告 WSAECONNRESET（需 `SIO_UDP_CONNRESET`），此分支很可能从未触发（证据通过支持此判断）。建议改为 `$_.Exception.ErrorCode -eq 10054 -or $_.Exception.InnerException.ErrorCode -eq 10054`。注：该缺陷方向安全（最坏导致脚本失败/崩溃，不会产生假 PASS）。

2. **（中）C1 无单元测试覆盖**：`main.rs` 的 18 个 `#[test]`（L2386-2844）无任何 `LanSimState`（F5）测试。reserve 跳过分支（L548-555）、应答回退（L582-591）、按 `(src ip, src port)` 去重一次应答（L700-728）仅靠 selftest 脚本集成验证。建议新增 cargo 单元测试覆盖 reserve 分支与回退逻辑。

3. **（中）标志组合无脚本验证**：`--reserve-62900` 与 `--sim-real-capture`（B1 路径 P2 与 reserve 共用同一 poll/监听循环）、`--simulate-datapath`、`--forward-to/--forward-listen` 的组合未在 selftest 中覆盖。代码静态分析无冲突（B1 缓存独立、datapath 用 ephemeral socket `0.0.0.0:0`（L2625）、forward 独立 socket），但建议补一次组合 run 留证据。

4. **（低）reserve 仅对 F5 生效、help 未说明**：`--reserve-62900` 只作用于 `LanSimState`（`--sim-lan-listen` 路径，main.rs:1614-1623）；若只给 `--simulate`（F1 loopback）加该标志，`SimState::new` 仍 bind `127.0.0.1:62900`（main.rs:413），reserve 静默无效。help（L1529-1534）未注明此限定。建议 help 注明"仅对 --sim-lan-listen 生效"或在该组合下 fail-closed 报错。

5. **（低）agent-console.txt 证据中文乱码**：证据 `C1-reserve-selftest-20261118-0002\agent-console.txt` 中 `REV-016 双机发现` 显示为 `REV-016 鍙屾満鍙戠幇`（UTF-8 字节被按 ANSI/GBK 解码的 mojibake）。来源：脚本 ps1:88-96 未设 `StandardOutputEncoding`，.NET 按系统 ANSI 代码页解码 agent 的 UTF-8 stdout。`summary.txt`（agent 直写，UTF-8）干净，全部数值证据不受影响。建议 `$psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8`。

6. **（低）脚本头注释与断言数不符**：`run-c1-reserve-selftest.ps1:18` 写 "Assertions (10)"，实际 12 个 `Check`（L183-212）；L19-30 注释列表把 "LAN section" 与 "listen ip" 合并为一项。建议改为 12。

7. **（低）断言 11 存在慢启动竞态窗口**：probe（ps1:104-120）在 agent 启动后固定 1.5s 执行，若 agent 尚未完成绑定会假 PASS；断言 6（requests seen=99）可兜底（旧行为会 seen=100）。建议把 probe 移到 burst 之后（burst 成功本身证明 99 端口已绑）或增加绑定完成同步。

8. **（低）summary 文案精度**：main.rs:2155 注释 `falls back from 62900 when the game owns it` 未提及 reserve 也是回退触发条件（reserve 时必然回退且非因游戏占有）。不影响数据，建议文案补充。

---

## 四、复核维度清单

| # | 维度 | 结论 | 证据 |
|---|---|---|---|
| 1 | 逻辑正确性：skip 62900 后 reply_sock 回退 | PASS | main.rs:548-555 reserve 时 `continue` → reply_sock 恒为 None → L582-591 必走 `listeners[0].try_clone()`（62901，若可绑）；L592 记录实际 `reply_addr`。证据 summary：`reply source : 127.0.0.1:62901` |
| 2 | 逻辑正确性：requests seen = 99 | PASS | 客户端 100 包（每端口 1 个 4B magic，ps1:125-127）；62900 无监听被内核丢弃 → 99 包到达 99 监听端口；`consider()` L700 在去重前计数 → 99。证据 summary：`requests seen : 99` |
| 3 | 逻辑正确性：去重保证 1 包到达即应答 22 页 | PASS | 去重键 `(src_ip_be, src_port_be)`（L701）；99 包同源 → 首个到达触发 `for page in pages` 循环发 22 页（L716-726），其余 `answered.contains_key` 跳过（L702-704）。证据：`replied sockets : 1` / `pages sent : 22` / `send fail : 0` |
| 4 | 回归风险：默认行为不变 | PASS | `reserve_62900: false` 默认（L1399）；false 时 L548 分支完全跳过，62900 照绑并成为 reply sock（L561-566）。回归证据 `C1-f5-regression-20261118-0001`：requests seen=200 / replied=2 / pages=44 / `port 62900 : bound by Agent` / reply source=127.0.0.1:62900 / bind fail=0 / exit=0 / PASS 12/12，agent sha256 与 C1 轮同一 exe（44DE339…） |
| 5 | 边界：reserve × sim-real-capture / simulate-datapath / forward 组合 | PASS | 静态分析无冲突：B1 缓存（L1700-1707）与 reserve 共用 poll 循环但独立状态；datapath 用 ephemeral `0.0.0.0:0`（L2625），永不绑 62900；forward 独立。F1+reserve 限定问题见建议 4 |
| 6 | help 文本准确性 | FAIL | 结构、语义准确（L1514 usage 含 `[--reserve-62900]`；L1529-1534 说明段与实现一致），但版本号 `v0.4.6`（L1529）与二进制实际 0.3.0 不符 → 必改项 C1-MUST-1 |
| 7 | 中文注释编码 | PASS | main.rs 无 BOM、纯 UTF-8（roundtrip 校验一致），注释中文正常；证据 summary.txt（UTF-8）中文正常。agent-console.txt 乱码属脚本解码管道（建议 5），非源码问题 |
| 8 | 证据一致性 | PASS | 哈希链全对：main.rs / selftest / exe sha256 与任务给定值及证据 `result.txt` 记录逐一相符；`client-recv-01..22.bin` 与 `lan-page-01..22.bin` 哈希 22/22 一致（1104 B）；exit.txt=0；port-62900-bind-check.txt=`bind 127.0.0.1:62900 SUCCEEDED`；agent-stderr.txt 仅 reserve 提示一行；文件 mtime 00:57:49-00:58:06 落在计划 §7 执行窗口（00:54-00:58），确为现场生成 |
| 9 | 机械证据 vs 双人验证 | PASS | `result.txt` 明确声明 "Evidence: loopback only (127.0.0.1). NOT a real two-machine test; the client is a UDP script, not a real Civ6 process"；summary notes 含 "NOT a two-real-hosts multiplayer result and NOT E2-B/E3"。未越界宣传 |
| 10 | 安全/纪律：永不 bind 62056、永不 SO_REUSEADDR | PASS | 全文件无 `bind` 62056 代码（`DATAPATH_PORT=62056` 仅作常量/校验/测试数据，L61/L1415-1418/L1484-1488/L1495-1500 fail-closed）；`SO_REUSEADDR` 仅出现在注释与总结文本（L28/L854/L2317），无任何 setsockopt 调用；reply socket 为 ephemeral（L2625 测试断言 port≠62056）；F5 绑定范围恒为 DISCOVERY_FIRST..LAST=62900..62999 |
| 11 | 自检脚本质量（12 断言） | PASS | 12 项断言均具判别力且非自指：断言 2 stderr 单行（L184-187）、断言 6 =99（L195，旧行为会得 100）、断言 9/11 双认证（bind 检查 + 99 兜底）、断言 12 页数/magic/房名三查（L212）；10054 捕获见建议 1；脚本 exit 码 0/1/2 约定清晰（L31-32） |
| 12 | 计划文档与代码一致性 | PASS | §2.2 方案、§2.3 改动清单（7 处 reserve_62900 全部定位）、§2.4 证据表、§2.5 文件身份（2871 行/124,700 B/10,999 B/哈希）与实测全部一致；§2.4 的 `requests seen 99`、`reply source 127.0.0.1:62901`、`bind SUCCEEDED` 描述与证据逐字吻合。唯一出入为 v0.4.6 版本号引用（必改项 C1-MUST-1） |

---

## 五、审计方法说明

- 逐一核对 `reserve_62900` 全部 7 处出现（L539 签名 / L548 跳过 / L1378 字段 / L1399 默认 / L1467 解析 / L1622 传参 / L2151 summary 状态行），另核查 help（L1514、L1529-1534）与常量定义（L57-58 DISCOVERY_FIRST/LAST、L281 SIM_REPLY_PORT=62900 与 DISCOVERY_FIRST 一致）。
- 独立复算证据数值：99=100-1（62900 槽位）、22=1 次应答×22 页、200=100×2 次刷新（回归）；哈希复算 5 个文件（3 个审计对象 + 回归脚本 + 计划文档）与 `result.txt` 记录比对。
- 版本/时间/编码交叉验证：二进制自报版本 vs Cargo.toml vs 注释/help；证据 mtime vs 计划执行记录；agent-console 乱码的 UTF-8→GBK 机理定位。

**复核结论**：除 C1-MUST-1 外无阻塞项，建议项 1-8 可按 C3 文档登记轮次一并处理。
