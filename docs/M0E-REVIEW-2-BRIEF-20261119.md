# M0-E 复审任务书（第二轮，2026-11-19）

你是独立审计员。只依据磁盘上的文件与证据做出裁定，不采信任何口头描述。

## 被审对象

上一轮设计审计 `docs\M0E-REVIEW.md`（41,207 B / sha256 见文件本体）裁定 NOT PASS（阻断 2 / 高 4 / 中 5 / 低 6）。之后实现侧完成了修复。本轮复审核验修复是否成立，并主动找新风险。

## 必读文件（全部相对项目根 `C:\Users\dd\Desktop\injciv6-v0.3.3\CivLink-M0A-audit\`）

| 文件 | 大小 | sha256 |
|---|---|---|
| docs\M0E-DISCOVERY-COMPLETION-20261118.md（设计 v2.0） | 21,021 B | B8626DE555B435E68988F18B15B9172470281E43EE9FD8ECF3AE17AC8C13A516 |
| docs\M0E-REVIEW.md（上轮审计） | 41,207 B | 见文件 |
| civlink\agent\src\main.rs（实现） | 176,308 B | E56A30562A94376B1982FCF184C2A81C791CF5B50B15218231712048E59A4276 |
| civlink\civlink-agent.exe（release 产物） | 464,384 B | 15321D49806517028ECE8CC8A3DC8B0ED855C410915295CAF72EBEF4DDF06267 |
| civlink\run-m0e-completion-selftest.ps1 | 26,268 B | 322CB66CD3CA3D53A9DC6C4E8871AFCD41FBA8B48AFB3CB52612DC1218F9D6C3 |
| civlink\run-m0e-mutation.ps1 | 10,343 B | ACADBBFF47EF0EC1853C624AA1903FDBC65F882635ED156A61902A08B8507A0A |
| civlink\run-c1-reserve-selftest.ps1（live-game 修正后） | 12,262 B | C0336CDAE4DD39F165B940882980D70FD347333DC16F2338D1F669439B49FBED |
| civlink\run-c1-combo-selftest.ps1（live-game 修正后） | 13,328 B | 70D78D5BE2D9B6EF76CF805CCC5E109F63F95C05F7FB6A1BCE4CD18702B04EF3 |
| civlink\selftest\hook_selftest.cpp（加 62056 前置守卫） | 17,500 B | E9B7EB694A3D7BBABF10ED7EC06DF6A8D00D1D407EF49110379BA468987CDA0B |
| civlink\selftest\hook_selftest.exe | 150,016 B | 15482B7D8D97597CDF2B617D6288DDD53362BD3EF046F9D8BD6C3C9B6DEF1137 |
| civlink\selftest\client_selftest.exe | 182,272 B | 50B69B2754F6E44AA6BD567BEE5102D8394F4DB2439C9DAB5F4DC36BA77EAECB |
| docs\M0E-GUI-INTEGRATION-20261119.md | 5,091 B | A63D143F5A72C950585807BB48A7F6BF243293DF1C5BD7C1BC7D218599834721 |
| docs\NIGHTLY-PACKAGE-20261119.md | 2,850 B | 8F01E954A1496F2204F783EBCAE3D831A1A52C25DE2DC309BB255B41809BE515 |

证据目录（在**项目根** `C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\`，不在审计仓库内——这是登记口径 N-2）：
- `M0E-completion-20261119-003732`（42 文件，自检采信轮，PASS 45/45）
- `M0E-mutation-20261119-003243`（13 文件，变异采信轮，5/5 caught）
- `M0E-B1-egress-20261119-0055`（三接口 pin 实证：WLAN/Radmin/ZeroTier 全 pinned=true）
- `M0E-B2-probe-20261118-2350`（B-2 修复前实测确认）与 `M0E-B2-fixed-20261119-0002`（修复后）
- `C1-reserve-selftest-20261119-0041`（PASS 12/12）与 `C1-combo-selftest-20261119-0041`（PASS 14/14）
- `regress-20261119-0055`（回归 triage：hook_selftest 6 失败=游戏占 62056 的环境冲突；client_selftest exit=2=调用方式错；九场景三参全 PASS；TRIAGE.txt 1,857 B/CCFAF851…）
- `gui-m0e-20261119-0052`（GUI 接入真实房间模式自检 40/40 + 变异 M6 3 FAIL）
- dist\civlink-20261119-nightly\（nightly 打包 + MANIFEST/VERSIONS）

## 必答问题

### A. 上轮阻断/高风险逐条关闭核验
1. **B-1（源 IP 过度承诺）**：设计 §5.3 是否已把"保证源=房主IP:P"改为"按被探测目的地址钉源（IP_PKTINFO）+ 明确回退语义"？实现 `mod egress` 是否真的在发页时用 WSASendMsg+IP_PKTINFO 钉源？三接口证据是否支撑？
2. **B-2（无去重）**：实现是否有 `(client_ip, client_port)` 去重 + `max_replies` 预算 + `clear_backlog`？99 magic 复测是否 `replays sent 1 / duplicate 98`？
3. **H-1（来源不校验端口/长度）**：收页循环是否严格 `from != game_addr`（IP+端口）？deadline 是否墙钟硬截止？
4. **H-2（文档与实现相反）**：§5.1 六参数与五约束是否与 `parse_args` 逐字一致（必须 --sim-lan-listen / 拒绝 --simulate / 拒绝 --sim-real-capture / 必须显式 --reserve-62900 / 非 loopback 拒绝）？
5. **H-3（反射放大）**：§7 是否登记 4B→24,288B≈6,072×？
6. **H-4**：62900 默认保护是否写入设计？
7. **中/低风险与 L-3（冻结流程）**：§0/§0.1 处置对照表是否逐条落实？文档是否写明实现冻结哈希？

### B. 主动找新风险（重点）
1. `clear_backlog` 会不会把**另一个客户端**的页吃掉（多客户端并发）？冷却窗 750 ms 内的第二次刷新（不同源端口）会被 `Duplicate` 拒绝——用户连续两次刷新间隔 <750 ms 时第二次拿不到应答，这个行为在设计/文档里是否可见、是否可配置（`--completion-cooldown-ms` 0 是否等价关闭）？
2. `max_replies`（默认 1000）耗尽后 summary 是否可见（`budget exhausted` 行）？会不会静默失效很久？
3. 钉源失败回退 `listener.send_to`（unpinned）时，客户端会看到路由决定的源 IP——与游戏自己的 22 页（源=房主 62900）不同源地址时，Civ6 按源 IP 去重会不会把 agent 的页判成第二个房间？设计 §8 是否如实登记？
4. 场景 4（非 loopback 探测）是否真的有判别力（pinned=22 vs unpinned=22 的断言是否独立于实现自身输出）？
5. `--completion-cooldown-ms 0` 边界：0 是否合法（0..=60000）？0 时去重还有效吗（elapsed<0 恒 false → 每次 magic 都重放）？
6. `egress::recv_with_dst` 在非 completion 路径不会被调用——是否有不必要的耦合？
7. GUI 真实房间模式：`--discovery-completion` + `0.0.0.0` 组合是否与 agent 侧约束一致（不拼 --simulate、拼 --reserve-62900）？
8. nightly 包：MANIFEST/VERSIONS 是否与实际文件一致？

### C. 文档与证据
1. §0.1 处置表逐条属实性；实算抽查 ≥6 个哈希（设计/自检/变异/证据文件）。
2. stale 数据扫描（旧轮 -002511/-002605 是否被正确标注为不采信）。
3. §7/§8/§11 完整性；结论是否仍过度宣称（跨机/真实客户端/E2/Gate 必须仍未验证）。
4. C1 两脚本 live-game 修正与 triage 结论是否自洽。

## 输出要求

- 写 `docs\M0E-REVIEW-2.md`（UTF-8 无 BOM）。
- 8 节：①裁定（PASS / 有条件通过 / NOT PASS）②上轮发现逐条关闭表 ③新发现（N-x 分级）④证据核验（≥6 哈希实算）⑤主动风险结论 ⑥放行条件（若非 PASS）⑦边界声明（本审计只覆盖 M0-E 机制与文档，不覆盖跨机/真实客户端）⑧建议。
- 完成后 send_message 回传：一行裁定 + 关键数字 + 报告哈希。

## 硬约束（违反即 NOT PASS）

- Agent 永不 bind 0.0.0.0:62056、永不 SO_REUSEADDR 到已占端口。
- 不伪造协议应答内容（fail-closed）。
- 机械/模拟证据 ≠ 双人真实联机验证。
- `civlink/agent/Cargo.toml` `[dependencies]` 为空，构建必须 `cargo +1.75.0 --offline`（B-1 手写 ws2_32 的理由——若你建议引入依赖，必须显式论证取舍）。
- 你是只读审计员：除 `docs\M0E-REVIEW-2.md` 外不得修改任何文件。
