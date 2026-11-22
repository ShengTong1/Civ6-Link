# F4-BETA-REVIEW · CivLink F4 发布候选单机模拟房主验收 · 独立审计报告

- 审计对象：F4-BETA-ACCEPTANCE-20261114.md（8,513B / 0B48336A…）+ 证据目录 F4-beta-20261114-174214（39 文件）+ run-f4-beta.ps1（14,079B / F7B56439… / UTF-8 BOM）+ check-f4-package.ps1
- 审计方式：只读。除本报告外未修改/写入任何文件；未执行可写脚本（check-f4-package.ps1 会向包目录写 VERSIONS.txt，故仅静态审阅）。
- 审计时间：2026-11-14（与验收同日）。

## 0 结论摘要

**最终裁定：有条件通过（Conditional PASS）。** 必改 1 项（H1）；阻断 0 项。
- 9/9 断言全部在证据上独立成立（本报告独立重算，非引用文档结论）；
- 证据身份 39/39 与文档 §6 逐项吻合（含 22 项 sim-page 全 64 位哈希）；
- 数值对账、脚本-文档一致性、表述边界（A/B/C/D 节）全部通过；
- 唯一必改为：验收文档 §5 两处数值转录错误（raw bind、state queries），不影响断言结论，但验收文档必须与其 §6 钉死的证据一致。
- 登记约束维持：NOT 双人真实联机、不勾 E2-A/E2-B/E3、不移动 Gate A/B（README v1.20 已按此登记）。

## A 节 身份核实

| 项 | 判定 | 核实结果 |
|---|---|---|
| A1 验收文档身份 | **PASS** | 重算 8,513B / SHA256 0B48336A724548E20BBECF4913ADC9DFC40880E04D42C327180D2FB75CDA3CE0，与声称值完全一致；首 3 字节 `23 20 46`（"# F"）→ 无 BOM；U+0009/000B/000C 控制字符计数 0/0/0 |
| A2 编排脚本身份 | **PASS** | 重算 14,079B / SHA256 F7B5643903FA270F41953855BE0F11E505FDB960C4289B4D602A1D7BCE163258，与声称值完全一致；首 3 字节 `EF BB BF` → UTF-8 BOM 确认 |
| A3 证据目录 39 文件身份 | **PASS** | 39 文件字节数与全 64 位 SHA-256 全部重算，与文档 §6 身份表逐项吻合（含 22 项 sim-page：表内前 8 位缩写与独立重算的全 64 位哈希逐一匹配，无冲突；空文件哨兵 E3B0C442… 一致）。完整表见附录 |
| A4 VERSIONS.txt | **PASS** | 内容 = `civlink-agent: civlink-agent 0.3.0` / `civlink-relay: civlink-relay 0.1.0` / `civlink_ctl  : civlink_ctl v0.2.0-f2 - CivLink F1 discovery hook controller` |
| 补充 §2 二进制身份 | **PASS** | civlink-f4 与 dist 双副本核对：agent 382,464B / 93F17516…、relay 262,144B / 9E323F81…、ctl 173,056B / 23923DFB…、hook dll 119,808B / 9424FC25… 全部与 §2 一致；两副本 6 个文件（4 二进制 + 2 脚本）SHA-256 两两相同（含 run-f4-beta.ps1 F7B56439…、check-f4-package BE45A5FE…） |
| 补充 sim-page 匿名化 | **PASS** | 证据 sim-page-01..22.bin 与 fixture reply-01..22.bin 仅偏移 24..45（22B 房名段）不同：证据页承载 "CivLink-Beta-Room-2222"，fixture 承载真实房名 "dingzihan2022…"，其余字节逐位相同 → 与 §2"（22B，偏移 24..46 匿名化）"及 sim-fixture-manifest.txt 声明一致 |

## B 节 数值核对（对 summary.txt / counters-after.txt / frame-log.txt 实际内容独立复核）

| 项 | 判定 | 结果 |
|---|---|---|
| B1 agent summary 关键值 | **PASS** | datagrams 309 / received frames 309（processed 309, rejected 0）/ session 0xbea5e077da87 / frames=309 first_seq=1 last_seq=309 / seq gaps=0 missing=0 duplicates=0 out_of_order=0 / discovery_magic=300 other_payload=9 / via_wsasendto=9 limited_bcast=300 / logical sockets=4 / dst ports=101（min 62056, max 62999, in 62900..62999: 100）/ src endpoints 0.0.0.0:50600×99、59851×99、59852×99、62056×9 —— 与文档 §4 逐项一致；附校验 payload bytes=1272 == 300×4 + 9×8，自洽 |
| B2 sim 段 | **PASS** | requests seen=300 / replied sockets=3 / pages sent=66（== 22×3）/ send fail=0 / no endpoint=3 / max reached=0 / bind fail=0 |
| B3 datapath 段 | **PASS** | frames seen=9 / frames on 62056=9 / reply sent=0 / reply skipped no_endpoint=0 not_local=9 already_sent=0 / send fail=0 / reply bytes=0 |
| B4 counters-after | **FAIL（2 项不符）** | sent=300 ✓ / observed frames=9 ✓ / raw sendto=300 ✓ / raw wsasendto=9 ✓ / **raw bind=1（文档 §5 与任务书均写 4，实为 1）✗** / bind 62056=1 ✓ / cvlh2 try=309 ✓ / cvlh2 ok=309 ✓ / cvlh2 fail=0 ✓ / accounted=300 ✓ / shutdown=1（in-flight=0）✓ / **state queries=3（文档 §5 写 2，实为 3）✗**。注：raw bind=4 出自首跑 -173307 的 counters-after，state queries=2 出自 counters-before —— 系文档转录错位（缺陷 H1） |
| B5 对账恒等式 | **PASS** | 独立验证：hook.sent delta = 300 − 0 = 300（before: sent=0）；observed delta = 9 − 0 = 9（before: observed frames=0）；agent.processed=309；300 + 9 == 309 ✓ |
| B6 frame-log 端口分布 | **PASS** | 309 行数据帧；dst 端口独立统计：62900..62999 共 300（100 端口 × 每端口恰 3 次 = 3 次刷新各 100 帧）、62056 共 9、其它 0；seq=1..309 唯一且连续（无缺/无重/无乱序）。发现帧 3 簇：09:42:58.264 / 09:43:00.849 / 09:43:03.937（各 100 帧）；数据面 9 帧呈 D4 指数退避（09:43:07.152 起 +0.5/1/2/4/8/16/32/64s，与 datapath-log.txt 逐行一致） |

## C 节 脚本与文档一致性

| 项 | 判定 | 结果 |
|---|---|---|
| C1 断言实现 ↔ §3 表 | **PASS** | run-f4-beta.ps1 8 个 Check + 2 个 info 与文档 §3 九行逐项对应：`processed (\d+), rejected`（L231）、`received frames : (\d+)`（L232）、`requests seen\s*:\s*(\d+)`（L233）、`replied sockets\s*:\s*(\d+)`（L234）、`pages sent\s*:\s*(\d+)`（L235）、`frames seen\s*:\s*(\d+)`（L236）、`reply sent\s*:\s*(\d+)`（L237）、observed 前后差值（L239–248）、dst 端口分类 62056/62900..62999/其它（L261–274）；§3 第 8 行在脚本中为信息行（L258），与"info："标注一致 |
| C2 §8 边界 ↔ README §3D | **PASS** | 文档 §8 证明 5 条/不证明 6 条与 README §3D（L760–790）边界声明一致、无矛盾：不证明双机发现/加入/对局、Relay 路径/直连转发/Fake-IP 绑定语义（H2/R1 留 M0-B）、Noise 加密、长稳（240s 单窗口）、广播出口选路（本机回环）、"双人真实联机已通过"；"模拟对端/发现助手测试版"、Gate A 未批准、M0-B/Gate B 冻结。README v1.20（L4、L1201–1215）已登记 F4-BETA PASS 9/9 且维持同一边界。附注：§3D F4 条目（L789）仍写"单机验收…待排期"，与 v1.20 登记存在状态陈旧（见缺陷 L4，README 内部问题，不属本验收文档缺陷） |
| C3 §7 首跑 FAIL 披露 | **PASS** | 首跑目录 F4-beta-20261114-173307 存在（39 文件，结构与采信轮一致，pid=39220）；shutdown.txt 显示 "CivLinkShutdown returned 0 (clean drain)"；首跑数据（processed=308、observed=8、62056 帧 8、raw bind=4、session 0x99889a8a0f9a）与 §7 披露的 4 项根因自洽：正则不匹配→2 FAIL、缺 observed 对账项→sent300+obs8≠processed308→1 FAIL、dst 未区分 62056→1 FAIL（恰 4 项）。旧版脚本未留存，FAIL 项数无法逐字复算（见信息级 I4） |

## D 节 表述边界

| 项 | 判定 | 结果 |
|---|---|---|
| D1 无双人真实联机正面宣称 | **PASS** | 全文无"双人真实联机已通过"类正面宣称；否定句齐备：文档 L5 "NOT 双人真实联机，不得据此勾掉 E2-A/E2-B/E3，不移动 Gate A/B"、L112 明确排除该类表述；脚本 L286；README L4/L1212 同口径 |
| D2 无越界验证宣称 | **PASS** | 无 H2/R1 绑定语义、Noise 加密、Relay RTT、跨网路径已验证的宣称；§1 边界（L13）与 §8 不证明（L107–112）明确排除；summary.txt notes（L50–60）亦自限"NOT a multiplayer, E2-B or Gate A result" |
| D3 label 编码缺陷说明 | **PASS** | §7（L95）已如实说明：首跑脚本无 UTF-8 BOM 致 PS 5.1 stdout 重定向按 OEM 代码页输出中文乱码（展示层，不影响判定）；现脚本（A2 验证）已带 BOM |

## 缺陷清单

**阻断（Blocker）：0 项**

**高（High，必改）：1 项**
- **H1** 验收文档 §5 两处数值与采信证据（counters-after.txt，文档 §6 钉哈希 6FFCA304BD30D511C056B747D51C7F6C9FD0EAA65941205919A7017858AE0FD5）不符：
  - §5 写 "raw bind=4"，实际 = **1**（值 4 出自首跑 -173307 的 counters-after，串行错位）；
  - §5 写 "state queries=2"，实际 = **3**（2 为 counters-before 的值）。
  - 影响：§5 自称"counters-after 关键值"，却与其 §6 钉死的证据文件矛盾；不参与 9 项断言（断言结论不受影响），但验收文档必须与证据一致，否则证据链出现可质疑的转录错误。
  - 必改动作：按 counters-after.txt 实际值更正为 raw bind=1、state queries=3，并核验全文无其它跨轮次串行值。

**中（Medium）：0 项**

**低（Low）：4 项**
- **L1** §2"窗口 240s（AutoStopSeconds），t=42s/44s/46s 三次刷新各 100 帧"：三簇各 100 帧已由 frame-log 结构证实；但 "t=42/44/46" 为操作者记录时刻，留存证据中无等待循环起点记录可严格复核（frame-log 簇时刻 09:42:58.264/09:43:00.849/09:43:03.937 与 agent listen 起点推算的 t≈62/65/68s 不一致，仅与"等待循环相对时刻"口径相容）。建议补充记录口径或标注为操作者记录。
- **L2** §1 发布包路径 "dist\civlink-beta-20261114\" 实际位于 `CivLink-M0A-audit\dist\civlink-beta-20261114\`（审计仓库根下，非 injciv6-v0.3.3\dist）；该目录存在且与中立目录 civlink-f4 双副本一致（二进制/脚本 SHA-256 两两相同）。建议 §1/§9 写明相对仓库根，避免歧义。
- **L3** §7/README v1.20 "首跑 FAIL 4 项"：目录与数据自洽（见 C3），但旧版脚本未留存，FAIL 项数只能重建推定、无法逐字复算。
- **L4** README §3D F4 条目（L789）仍写"单机验收…待排期"，与 README v1.20（L4/L1201–1215）的 F4-BETA PASS 9/9 登记状态陈旧不一致（README 内部问题；README v1.20 ③已预告按本审计意见补记）。

**信息级（Info）：4 项**
- **I1** check-f4-package.ps1（3,966B / BE45A5FE… / 无 BOM）静态审阅：14 项检查（存在性 5、版本 3、62056 负向护栏 3、非平凡体积 2、VERSIONS 写入 1）与 README v1.19"自检全 PASS"一致；审计员按只读约束未重跑（该脚本会向包目录写 VERSIONS.txt，属写入操作）。
- **I2** §6 注明"sim-page 22 项完整哈希见本轮采集记录"，该记录不在 39 文件之列；审计员已独立重算 22 项全 64 位哈希并逐项匹配表内前 8 位（无冲突），此注记不影响审计结论。
- **I3** §3 第 7 行"exit=0（clean drain）"证据形式为 shutdown.txt 文本 "CivLinkShutdown returned 0"；脚本断言接受退出码 ∈ {0,1,2}，与证据不矛盾；控制台输出未随证据留存。
- **I4** 首跑 -173307 的旧脚本与 console 输出未留存，仅能通过其证据文件重建断言失败（见 L3/C3）。

## 必改清单（Must-Fix）

1. **H1**：验收文档 §5 更正 raw bind=4→**1**、state queries=2→**3**（并全文档排查跨轮次串行值）。

## 最终裁定

**裁定：有条件通过（Conditional PASS）——F4 验收结论（PASS 9/9、证据采信 -174214）成立，可在完成必改项 H1 后登记为通过。**

- 依据：A1/A2/A3/A4、B1/B2/B3/B5/B6、C1/C2/C3、D1/D2/D3 全部 PASS；B4 仅文档转录值不符（缺陷 H1），断言所依赖的数值全部在证据上独立成立。
- 登记约束（随 README v1.20 既有口径）：本验收仅为单机模拟对端/发现助手测试版；**NOT 双人真实联机**；不证明双机发现/加入/对局、Relay RTT、H2/R1 绑定语义、Noise 加密、跨网、长稳；不得据此勾掉 E2-A/E2-B/E3；不移动 Gate A/B。

## 附录 · 证据目录 39 文件身份表（审计重算，全 64 位）

| 文件 | 字节 | 重算 SHA-256 | 对 §6 |
|---|---|---|---|
| summary.txt | 2,986 | 4AE128563F3AF73840A00D87A7D39469F46030E45244FBE2E1CB942958A4E088 | MATCH |
| frame-log.txt | 44,217 | 8F5671D23CCE358EEF2E9C89EE71EBB337A7D3C580D1F2DD59603F129861BD4A | MATCH |
| counters-after.txt | 970 | 6FFCA304BD30D511C056B747D51C7F6C9FD0EAA65941205919A7017858AE0FD5 | MATCH |
| counters-before.txt | 943 | 5DD78B43B335B5DA0F1962147BE1D9B7423B60FFC8F9CFA01511F81D6C70E075 | MATCH |
| inject.txt | 940 | 0D8E415DBB3E2A8EE9DAF3B4DC6DCBE9FA9FD72071975348CD272E2DC8491AFA | MATCH |
| shutdown.txt | 816 | FEFEC900FA4E87C85046348B5EF21B3E6B4F5E5CD26B09089CD716F3C19D2E94 | MATCH |
| path-state-before.txt | 318 | 834441171664245218EB1F14FE851E0CDDBE1AA0DCBC1C19804A9B69FAAE1E6D | MATCH |
| path-state-after.txt | 321 | 47B8037AD99BCEABEA91193AAE5AD9E24D418E1555B584BC258425B777F40659 | MATCH |
| relay-summary.txt | 1,520 | BD97077DE36832034C17952F5F119B9F97BE662332234B916F26F3B77D42DC7E | MATCH |
| relay-log.txt | 86 | C62C5AD174DF20FC6CF4CEFB2E23F786AD90407299B1F831CB07F6C3A2A05BF0 | MATCH |
| datapath-log.txt | 974 | 4E119A2271A72232FB946DE911204453AF93126385ACD90DB82D73628BD23426 | MATCH |
| sim-fixture-manifest.txt | 228 | EDD762B6807BB47648B5E6417E51E37143D567FB482B9699AAC056A4DCD5AB17 | MATCH |
| VERSIONS.txt | 152 | 62CDC2D5A341F04BDF30A896B27D78F460EB6B3720AF222FBEE92FB786021101 | MATCH |
| sim-page-01.bin | 1,104 | 38CF963441A9101932FC29CCCD588B1C885544B2DC3BD8C487291B0034AA4FAF | MATCH |
| sim-page-02.bin | 1,104 | 7E2DD92EC98F412973DCF85EB012863D1A9BB5A08BD679F6984A44265A281EB9 | MATCH |
| sim-page-03.bin | 1,104 | AF9F91C5AD23A1EC6E58E945D09C41D3BEC29AE93C42B7C0080E364256571805 | MATCH |
| sim-page-04.bin | 1,104 | 3DBCBC7D8ECF7DD5C6D1475F5E58081A307473656DA85E4FCC3DFC44055C031E | MATCH |
| sim-page-05.bin | 1,104 | 7D9C575AB49E9A42FCCA1B66D8E4AD10ED56020DEDC467A6218EC4227E9ACD17 | MATCH |
| sim-page-06.bin | 1,104 | 03B8EAAEB0DBF106F703C649EDFBA3A143A7C7C266E0C670513677E7874E01D4 | MATCH |
| sim-page-07.bin | 1,104 | F47577C2D538BA75BE9DA4039B5D176CBBE9ECE565B6191E032F50FDE2E1B449 | MATCH |
| sim-page-08.bin | 1,104 | 6D78C4D99AEA140D8022B9EB060CE2308B2B867271E2337B68AFFD9EAACBC391 | MATCH |
| sim-page-09.bin | 1,104 | FE49AB4A938BA59620C17600B1A30EC6352FBB0870908198B60E7D25246DFFF7 | MATCH |
| sim-page-10.bin | 1,104 | 8519F29CB09B2124F37CD3756F7BF978A3A9F7233462D5D2E18B5B4B16C26F36 | MATCH |
| sim-page-11.bin | 1,104 | 53F3A509E75A1FA42852112F03483A06663DB771E4B062FBF97E21D731D9E668 | MATCH |
| sim-page-12.bin | 1,104 | E75EFD692969398D59FCFC4BFBEB9B3280EF407ACC8F12E838FF6736E44BFDEA | MATCH |
| sim-page-13.bin | 1,104 | FE47B2AF1B73496FBC71235E63AC9AB2C79C4D00AFB4F1F323E0102076213640 | MATCH |
| sim-page-14.bin | 1,104 | EB0EE9616E92975DDCD50BAF2557340A4C3C3A722B4E3EF105691E8036AA11D5 | MATCH |
| sim-page-15.bin | 1,104 | D35F29EEB042A6719F8CC1EAA0B7C0F72AFFC51D6ED6B53A8D1F613DC17F9A0B | MATCH |
| sim-page-16.bin | 1,104 | 1137F753123D3352D2950CB8061E504D20C8AE22490054D0F4739A6368109295 | MATCH |
| sim-page-17.bin | 1,104 | E1025775CFA4F1A700461980F1E6A9695486BA052E3DE67B7A83D57F8E76C634 | MATCH |
| sim-page-18.bin | 1,104 | B46BCBF1D2F68518DCCB6CEEE5E99759F4DECD4CBC39A93DEB3AE3B3CD07F582 | MATCH |
| sim-page-19.bin | 1,104 | 331C52CF0D48E96227C7D45DAEFC8DC54CD4169434D6F6B6ED33725E46C46A7E | MATCH |
| sim-page-20.bin | 1,104 | 4C7E1ABBBD00506A0F65861232C7C630AF8DDB628816EA61EAEFAD012C9BC5B6 | MATCH |
| sim-page-21.bin | 1,104 | BB2EF26F8F6E20884C434D64AB69CAD8EFA30DD842EB0CC0848FBE442720F4AA | MATCH |
| sim-page-22.bin | 1,104 | A8C79AED4FC26C7356EA7B06860A517FC4D8E95AD123F39FCAE56E845F1286CC | MATCH |
| agent-console.txt | 0 | E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855 | MATCH（空，--quiet） |
| relay-console.txt | 0 | E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855 | MATCH（空，--quiet） |
| STOP-agent | 0 | E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855 | MATCH（空哨兵） |
| STOP-relay | 0 | E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855 | MATCH（空哨兵） |

（39/39 全部 MATCH。附带验证：civlink-f4 与 dist 双副本 4 二进制 + 2 脚本 SHA-256 两两相同；证据 sim-page 与 fixture 仅偏移 24..45 房名段差异，为文档声明的匿名化替换。）