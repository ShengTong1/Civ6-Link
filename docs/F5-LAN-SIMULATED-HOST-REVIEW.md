# F5 LAN 模拟房主（跨机发现路径）独立审计报告 — 2026-11-15

审计方式：独立重算（PowerShell SHA256 / 字节数 / 逐字节比对）、证据文本独立读取、
源码 grep + 精读（main.rs）。只读审计，未改动任何被审文件。

## A. 身份核查 — PASS（4/4 命中，2 项信息级注记）

| 文件 | 声称 sha256 | 实测 sha256 | 声称字节 | 实测字节 | BOM | tab/vt/ff |
|---|---|---|---|---|---|---|
| F5-LAN-SIMULATED-HOST-20261115.md | 105EC4902D953E49AD8B64CE7F3E912817527C535786187ECC9F08146C0A1829 | 命中 | 6545 | 6545 | 无 | 0/0/0 |
| run-f5-b-probe.ps1 | FF4DDF3FE71639E6204A853B8F36FB810158802C1F321670B398FBFAFDFE57D0 | 命中 | 7244 | 7244 | 无 | 0/0/0 |
| run-f5-dualmachine-a.ps1 | 472FA16C1B378AF15766581B49645B76A82A0AD08733AA6C9AD3A51B790997C5 | 命中 | 7796 | 7796 | 无 | 0/0/0 |
| run-f5-lan-selftest.ps1 | 80C0935DE04A2EA7F8A596B9E9B4B045C2EFFB8C671FDEF610FF9AF279BAB41E | 命中 | 8842 | 8842 | 无 | 0/0/0 |

四文件均无 BOM、无 tab/VT/FF，LF 换行（CR=0）。文档声明与实测完全一致。

信息级注记：
- 附 1：§6 声称 main.rs "编译后 2558 行"：Get-Content 实测 2559 行（read 工具显示
  2562 行），行数口径偏差 1~4 行，无实质影响。
- 附 2：§6/§4 声称 civlink-agent.exe = 194E6E8A00080B0F05AF14D8754F38CACE818CFC0FE667BB1E0375400D23DA92
  （404,992B）：civlink\ 与桌面 civlink-f5-kit\ 两处均实测命中；kit 内三个脚本
  及 PC-B-操作单.md（FF6679E9…E96）哈希亦命中；kit fixture 与 civlink fixture
  逐文件哈希一致。

## B. 数字一致性 — §3.1 PASS；§3.2 部分 PASS（2 处不实/不可证）；§3.3 部分 PASS（1 处不可证）

### §3.1（F5-lan-selftest-20261114-192000，52 文件）— 全项 PASS
- result.txt：`F5-LAN-SELFTEST: PASS (12 checks)` —— 12 断言 PASS ✓
- summary.txt：requests seen=200 ✓ / replied sockets=2 ✓ / pages sent=44（== replied×22）✓
  / send fail/no endpoint/max reached/bind fail 全 0 ✓ / listen ip 127.0.0.1 ✓ /
  room 'CivLink-Test-Room-2222' ✓ / reply source 127.0.0.1:62900 ✓
- exit.txt=0 ✓ / agent-stderr.txt=0B ✓
- client-recv-01..22.bin：22 个文件各 1104B ✓，与 lan-page-01..22.bin 逐字节一致
  （差异 0 字节）✓，head=59 60 69 9B ✓，房名 CivLink-Test-Room-2222 位于字节
  24..45 ✓
- 独立交叉验证：lan-page-*.bin 与 fixture-reply-set\reply-*.bin 的 SHA256 不同，
  但逐字节比对确认差异仅限偏移 24..45（21 字节，SIM_NAME_OFFSET=24 /
  SIM_NAME_LEN=22 的房名匿名化字段；fixture 原房名为 "dingzihan2022的游戏"）——
  与代码 anonymize_pages() 及 manifest "anonymized at offset 24..46" 一致，
  属预期行为而非证据伪造。

### §3.2（F5-lan-broadcast-selftest-20261115-b，29 文件）— 核心数字 PASS，2 处问题
- summary.txt：requests seen=100 ✓ / replied sockets=1 ✓ / pages sent=22 ✓ /
  listen ip 0.0.0.0 ✓ / room ✓ / 失败计数全 0 ✓ / exit.txt=0 ✓
- 问题 1（不实）：文档称"应答源 192.168.31.59:62900（WLAN 出口，metric 修复后）"，
  但证据 summary 记录 `reply source : 0.0.0.0:62900`（agent 的绑定地址）。
  192.168.31.59 只能是客户端侧观察值，而 dir-b 无任何客户端侧产物
  （无 client-recv-*.bin、无 result.txt、无客户端控制台）→ 该断言与证据字面
  冲突且无留存支撑。
- 问题 2（注）：文档注"首版自测（-a，默认 64KB 缓冲）出现 3 socket/60 页"，
  但 -a 目录（F5-lan-broadcast-selftest-20261115）的 summary 实测
  `replied sockets : 3 / pages sent : 66`。按 pages==replied×22 恒等式，
  3 socket → 66 页；"60 页"在 -a 证据中无出处（若指客户端实收数，则因
  66×1104=72,864B > 64KB 溢出丢 6 页 → 60 合理，但属推测、无留存证据）。
  同句注中"60 页"与"66 页"并存，自相矛盾。
- 文档称"客户端收到精确 22 页（24,288B == 22×1104）、head、room 正确"：
  数学正确，与 agent 侧 100/1/22 间接吻合，但客户端侧细节无留存证据（同问题 1）。

### §3.3（F5-bprobe-mechanical-20261115，26 文件）— agent 侧 PASS，1 处不可证
- summary.txt：requests seen=100 ✓ / replied sockets=1 ✓ / pages sent=22 ✓
- 不可证：文档称"SENT=100, PAGES=22, RECV=24,288B, HEAD=59 60 69 9B,
  ROOM=CivLink-Test-Room-2222"（B 侧探测客户端数字），但该目录只有 agent 侧
  产物（frame-log / lan-fixture-manifest / lan-page-01..22.bin / STOP-agent /
  summary.txt），无 run-f5-b-probe.ps1 的任何输出（无 probe-console.txt /
  probe-stderr.txt / result.txt / probe-reply-*.bin / firewall-rule.txt）；
  桌面 civlink-f5-b-probe-out 亦不存在。SENT/RECV/HEAD/ROOM 为脚本打印值，
  未留存为证据。

## C. 脚本逻辑 — 基本 PASS，3 项低/信息缺陷

### run-f5-b-probe.ps1（B 侧）— PASS
- 100 个 magic、端口 62900..62999 循环、固定本地端口 54321（默认值）✓
- 自提权（runas，UAC 一次）+ 防火墙规则加/删配对（开头删残留→加；收尾删）✓；
  规则操作失败仅 WARN 不阻断 ✓
- 断言：sent==100 / pages==22（1104B×22）/ head / room（pages>0 时）；exit
  0=PASS / 1=FAIL / 2=SETUP ✓
- 信息：规则删除在断言失败路径（exit 1）之前执行 ✓；规则添加失败时继续运行并
  如实 WARN，不伪造 PASS。

### run-f5-dualmachine-a.ps1（A 侧）— 断言 PASS，1 项低
- 断言正则与实际 summary 标签逐一核对：'requests seen' / 'replied sockets' /
  'pages sent' / 'send fail' / 'no endpoint' / 'max reached' / 'bind fail' 全部
  与 agent 输出标签一致 ✓；语义 requests>0 / replied>=1 / pages==replied×22 /
  失败计数全 0 ✓；-WaitSeconds 180 默认 < -ListenSeconds 240 默认 ✓
- 低：等待循环靠读取 summary.txt 判断提前退出，但 agent 仅在窗口结束时才写
  summary.txt（main.rs:1717-1738）→ 该"提前退出"优化永不生效，总是等满
  WaitSeconds。无正确性影响，仅效率与设计语义不符。

### run-f5-lan-selftest.ps1（12 断言）— PASS，2 项信息
- 12 项断言全部读取 agent 产物（summary/exit/stderr）或实时 socket 收包数据，
  无恒真断言、无"只匹配自身打印"的断言 ✓
- 信息：文件头注释写 "Assertions (8)"，实际 12 项（注释过时）；证据布局注释列出
  bind-check.txt，脚本并不产出该文件（证据目录中亦无）。
- 注：第二轮（b2）的 22 页未落盘（仅 b1 落盘 client-recv-*），b2 的持久证据仅
  脚本打印，但其断言读取的是实时收包数据，非自身打印。

## D. 代码实现 — PASS

main.rs（grep + 精读，行号）：
- LanSimState（517-524）：pages / listeners（每成功绑定端口一个 socket）/
  reply_sock（62900 listener 经 try_clone 兼任应答 socket，549-554）/
  max_replies（默认 20，1206）/ stats / answered: BTreeMap<(u32,u16),bool>
  （注释 (src_ip_be, src_port_be)）✓
- 绑定循环 `for port in DISCOVERY_FIRST..=DISCOVERY_LAST`（544）覆盖全部 100 个
  发现端口；常量（57-58, 281）：DISCOVERY_FIRST=62900 / DISCOVERY_LAST=62999 /
  SIM_REPLY_PORT=62900 / SIM_PAGE_COUNT=22 / SIM_NAME_OFFSET=24 /
  SIM_NAME_LEN=22 ✓
- is_discovery_magic（526-528）：len==4 且 == DISCOVERY_MAGIC [0x8D,0xE8,0xFC,0x70]
  （73）✓
- consider()（636-674）：IPv6 忽略；src_port==0 → no_endpoint+1 并返回 ✓；
  requests_seen+1；key=(ip.to_be(), src_port.to_be()) ✓；answered 命中即返回
  （去重）✓；replied_sockets>=max_replies → max_replies_reached+1 ✓；22 页
  send_to，全量成功才 answered.insert + replied_sockets+1，否则 send_fail+1 ✓
- 62900 绑定失败时回退 listeners[0] 克隆作应答源（570-579）；实测 bind fail=0
  未触发
- 永不 bind :62056：LAN 路径只绑 62900..62999；F2 reply_sock 为临时端口
  （702、1423 注释）；全文件无 62056 绑定（grep 仅常量/注释/测试）✓
- 永不 SO_REUSEADDR：grep set_reuse/reuse_address 全文件 0 命中，仅注释提及
  （28、681、2005）✓
- 互斥：--sim-lan-listen 优先，F1 回环模拟仅在其为 None 时启用（1393-1404）✓；
  --sim-lan-listen 强制要求 --simulate（1411-1413）✓
- 匿名化：load_fixture_pages + anonymize_pages(room)（538-539、345-348）→
  发送页 = fixture 页 + 房名覆写 ✓（与 B 节逐字节比对结论一致）

## E. 边界 — PASS

- §5 明示不证明：双人真实对局、E2-B 双端注入、62056 数据面、Relay RTT、
  Fake-IP、Noise 加密、跨网/长稳 ✓
- §5 明示不得据此勾掉 E2-A/E2-B/E3、不移动 Gate A/B、Gate A 未批准 M0-B 冻结 ✓
- 无任何"联机已验证"式越界宣称：三节均自标为自测/机械验证；result.txt 均注明
  "NOT a real two-machine test / NOT E2-B/E3"；summary notes 同样注明 ✓
- §7 状态如实：双机核验待 B 机执行（桌面无 civlink-f5-a-out /
  civlink-f5-b-probe-out；captures 中 F5-dualmachine-20261114-192100 为 11-14
  一次未完成尝试——仅有 start-cmd/agent-pid/lan-page，无 summary.txt/result.txt，
  无成功证据，与"待执行"不矛盾）✓
- §3.2 注中"本机多路径自测产物"的方向判断（Radmin+WLAN 回环多路径投递致多源键）
  与 -a 证据（replied sockets=3）相符 ✓；"60 页"数字问题见 B 节
- 信息：-a / bindcheck / kit-selftest 三个目录的 summary 头部中文出现乱码
  （"双机发现"→"鍙屾満鍙戠幇"，GBK/UTF-8 捕获差异），属控制台编码捕获产物，
  非内容篡改；审计的三个证据目录中文正常。

## 缺陷分级

| 级别 | 编号 | 内容 |
|---|---|---|
| 中 | D1 | §3.2 "应答源 192.168.31.59:62900"：证据 summary 记录为 0.0.0.0:62900（绑定地址）；192.168.31.59 为无留存的客户端侧观察，且 dir-b 无任何客户端侧产物 |
| 中 | D2 | §3.2/§3.3 客户端侧断言无留存证据：dir-b 无 client-recv/result.txt；bprobe 目录无 probe 任何输出（probe-console/result/probe-reply/firewall-rule 全缺），桌面 probe-out 不存在 |
| 低 | D3 | §3.2 注 "3 socket/60 页"：-a 证据实为 3 socket/66 页；"60 页"无出处且与同句"66 页"矛盾（若为客户端实收数属推测） |
| 低 | D4 | run-f5-dualmachine-a.ps1 提前退出轮询永不生效（agent 仅在窗口结束时写 summary.txt） |
| 信息 | D5 | run-f5-lan-selftest.ps1 头注 "Assertions (8)" 实际 12 项；证据布局注含 bind-check.txt 而脚本不产出 |
| 信息 | D6 | §6 "main.rs 2558 行"：实测 2559（read 显示 2562），行数口径偏差 |
| 信息 | D7 | 部分历史目录（-a/bindcheck/kit-selftest）summary 头部中文乱码（编码捕获差异） |

无阻断级、无高级缺陷。

## 必改项清单

1. （中，D1）§3.2 的"应答源 192.168.31.59:62900"改为与证据一致（agent 记录
   0.0.0.0:62900），或明确标注"客户端侧观察值（未留存）"。
2. （中，D2）为 §3.2/§3.3 补齐客户端侧留存证据（将 run-f5-b-probe.ps1 的
   probe-console.txt / result.txt / probe-reply-*.bin / firewall-rule.txt 一并
   拷入证据目录），或将文档措辞改为"agent 侧确认 100/1/22，客户端侧数字为运行
   观察值、未留存"。
3. （低，D3）§3.2 注的"60 页"修正为"66 页"（或注明 60 为客户端实收推测值）。
4. （低，D4）dualmachine-a 的提前退出轮询改为生效机制（如轮询 agent-console 的
   READY/计数输出），或删除该轮询并注明"固定等待"。
5. （信息，D5）selftest 脚本头注释 8→12、删除 bind-check.txt 提及。

## 最终裁定：有条件通过（Conditional PASS）

身份（A）、§3.1 数字（B）、脚本逻辑（C）、代码实现（D）、边界声明（E）全部
核实无误；§3.2/§3.3 的 agent 侧核心数字（100/1/22）与证据完全一致，无伪造迹象
（含失败的 -a / 191700 历史目录佐证审计诚实性）。但 §3.2 应答源与 §3.2/§3.3
客户端侧数字存在 2 处中级的"无留存证据/与证据字面冲突"（D1/D2），按必改项 1-2
修正措辞或补齐证据后，证据链方可视为闭环。在此之前，文档中的客户端侧数字不可
作为独立可复核证据引用。
