# F5 LAN 模拟房主复审报告（REVIEW-2）— 2026-11-15

审计方式：独立重算（PowerShell SHA256 / 字节数 / 逐字节比对 / 全字节哈希比对）、
证据文本独立读取、PowerShell Parser 语法检查、源码精读。**只读审计，未改动任何被审文件**。
被审范围：第一轮审计（abf9bf5f，F5-LAN-SIMULATED-HOST-REVIEW.md）裁定"有条件通过"
时给出的 4 项必改（①§3.2 应答源 ②客户端侧证据 ③"60 页"→"66 页" ④dualmachine-a
轮询修正）逐项落地核实 + 复审对象 1–5 全项独立复核。

---

## A. 身份核查 — PASS（全部命中）

| 文件 | 要求 sha256 | 实测 sha256 | 要求字节 | 实测字节 | BOM | tab/vt/ff | 解析 |
|---|---|---|---|---|---|---|---|
| docs\F5-LAN-SIMULATED-HOST-20261115.md | 4AA1FF4E2AE749D412C907091D9E64CB261D709EDD7761072164CBD88FD5A582 | **命中** | 7701 | 7701 | 无（首字节 23 20 46） | 0/0/0 | — |
| civlink\run-f5-dualmachine-a.ps1 | D909D16F034F006B167285C33FFB83DCFBC411EBE9582B27E3A7CF14A22B444B | **命中** | 7926 | 7926 | 无 | 0/0/0 | PowerShell Parser **0 errors** |

两文件均无 BOM、无 tab/VT/FF、LF 换行。文档与脚本的身份声明与实测完全一致。

---

## B. 必改 ① ② ③（文档 §3.2/§3.3）— PASS（3/3 落地）

### ① §3.2 应答源改与证据一致 — 落地（1 项低优先级注记）
- 标题（L48）：`### 3.2 真实广播自测 — PASS（22/22 页，客户端侧证据留存）` ✓
- 应答源改为**多路径不定性解释**（L55-61），与要求逐字对应：
  - `-b` 轮 `192.168.31.59:62900`（WLAN 回环路径）✓（文中已明确标为"客户端观察到的应答源"）
  - `-c` 轮 `26.74.126.98:62900`（Radmin 回环路径）✓ —— 与 -c 目录 `client-observed.txt`
    的 `REPLY_SRC=26.74.126.98:62900` **逐字一致**，有留存证据支撑 ✓
  - agent summary 记录 `reply source : 0.0.0.0:62900` 为**绑定地址、非实际出口** ✓
    （第一轮 D1 的"与证据字面冲突"已消解：文档不再把 192.168.31.59 说成 agent 记录值）
  - 跨机场景只有 WLAN 一条路径，应答应经 WLAN 出口，**不定性不适用于跨机** ✓
- `3 socket/66 页`（L66-67）✓ —— 与无后缀目录 `F5-lan-broadcast-selftest-20261115`
  （即 -a 轮）summary 实测 `replied sockets : 3 / pages sent : 66` **一致**
- 注记（低，P3-2）：`-b` 轮值 `192.168.31.59:62900` 在全部 captures 中**无任何留存的
  客户端侧产物**（整个证据树唯一一份 client-observed.txt 在 -c，值为 26.74.126.98）。
  文档将其表述为"客户端观察值"并置于多路径不定性框架内，已消除与 agent 证据的冲突；
  但按第一轮 D1 的"或标注客户端侧未留存"分支，建议对 `-b` 轮补一句
  "（-b 轮观察值，客户端侧未留存）"以完全闭环。

### ② 客户端侧证据 — 落地（补证据 + 措辞双管齐下）
- 新增客户端侧证据目录 `M0A\captures\F5-lan-broadcast-selftest-20261115-c`（51 文件）：
  `client-observed.txt` + `client-recv-01..22.bin`（+ lan-page-01..22.bin 等）✓
- §3.2 证据段（L62-65）明列 `-c` 为**客户端侧**独立证据：
  `client-observed.txt`（SENT=100/PAGES=22/RECV_BYTES=24288/HEAD/ROOM）+
  `client-recv-01..22.bin` ✓
- §3.3（L76-81）客户端侧数字不再自证，改为**显式引用 §3.2 `-c` 轮的
  `client-observed.txt`/`client-recv-01..22.bin` 为独立证据**，并说明 probe 与 -c
  客户端为同一代码路径（同广播报文、同收页逻辑）✓ —— 满足第一轮 D2 的
  "补证据或改措辞"分支
- `F5-bprobe-mechanical-20261115` 目录 summary 实测 requests seen=100 /
  replied sockets=1 / pages sent=22，与 §3.3 agent 侧数字一致 ✓

### ③ "60 页" → "66 页" — 落地
- 全文档 grep：`60 页` 0 命中；L66 注记实测为 `3 socket/66 页` ✓
- 旧哈希 `105EC4902D` 0 命中 ✓

---

## C. 必改 ④（run-f5-dualmachine-a.ps1 轮询修正）— PASS（落地）

- 轮询段（L87-95）已改为**固定等待**，注释含 `NOTE (F5 audit D4)`：
  ```powershell
  $deadline = (Get-Date).AddSeconds($WaitSeconds)
  while ((Get-Date) -lt $deadline) {
      Start-Sleep -Seconds 3
      if ($proc.HasExited) { break }
  }
  ```
  ✓ 与要求的 `while ((Get-Date) -lt $deadline) { Start-Sleep 3; if ($proc.HasExited) { break } }`
  语义一致（-Seconds 为同一开关的显式写法）
- 全文 grep：`sawRequests` 0 命中，原"提前退出轮询"已删除 ✓
- 注释（L87-89）说明修正理由：agent 仅在窗口结束（listen-seconds 到期或 stop-file）
  才写 summary.txt，故固定等待是正确语义 ✓
- 断言标签与 agent summary 实际标签逐一核对，7 个正则键全部命中且一致：
  `requests seen` / `replied sockets` / `pages sent` / `send fail` / `no endpoint` /
  `max reached` / `bind fail` ✓（L114-127）
- 新脚本字节 7926B = 旧脚本（7796B，472FA16C…997C5）≈ +130B，与新增注释块量级吻合 ✓

---

## D. 客户端证据一致性（-c 目录，51 文件）— PASS

| 检查项 | 实测 | 结论 |
|---|---|---|
| 文件数 | 51（22 recv + 22 page + client-observed + summary + agent-console + agent-stderr(0B) + frame-log + lan-fixture-manifest + STOP-agent） | ✓ |
| client-recv-01..22.bin | 22 个，各 1104B | ✓ |
| lan-page-01..22.bin | 22 个，各 1104B | ✓ |
| recv 与 page 逐字节一致 | 22/22 对 SHA256 完全相同（0 不匹配） | ✓ |
| client-observed.txt | SENT=100 / PAGES=22 / RECV_BYTES=24288（=22×1104） / HEAD=59 60 69 9B / ROOM=CivLink-Test-Room-2222 / REPLY_SRC=26.74.126.98:62900 —— 六行逐字命中要求 | ✓ |
| summary.txt（LAN 段） | requests seen=100 / replied sockets=1 / pages sent=22（==replied×22）/ reply source=0.0.0.0:62900 / send fail=0 / no endpoint=0 / max reached=0 / bind fail=0 | ✓ |
| 22 页 head magic | 22/22 首 4 字节 = 59 60 69 9B | ✓ |
| 房名匿名化 | client-recv-01.bin 字节（0-indexed）24..45 = `CivLink-Test-Room-2222`（22 字节，与代码常量 SIM_NAME_OFFSET=24 / SIM_NAME_LEN=22 及任务"字节 24..45"同一 0-indexed 口径） | ✓ |
| 与 fixture 差异范围 | 22 页全部：与 fixture-reply-set\reply-NN.bin 差异**仅限**偏移 24..45（22 字节房名字段，n=21——偏移 25 因两房名均含 'i' 恰好同字节；原始房名 `dingzihan2022的游戏` 已被替换） | ✓ |
| 佐证 | -a 轮目录（无后缀）实测 3 socket/66 页（64KB 缓冲溢出的 64KB 自测产物，与文档注记一致）；F5-bprobe-mechanical 目录 100/1/22 与 §3.3 一致 | ✓ |

结论：客户端侧证据链完整、自洽，无伪造迹象（含失败的 -a 轮历史目录佐证诚实性）。

---

## E. kit 一致性（C:\Users\dd\Desktop\civlink-f5-kit\）— PASS（2 项低/信息注记）

| 文件 | 要求 | 实测 | 结论 |
|---|---|---|---|
| run-f5-dualmachine-a.ps1 | 与文档树版本一致（D909D16F…） | D909D16F034F006B167285C33FFB83DCFBC411EBE9582B27E3A7CF14A22B444B / 7926B | ✓ 两处同版本 |
| civlink-agent.exe | 194E6E8A… / 404,992B | 194E6E8A00080B0F05AF14D8754F38CACE818CFC0FE667BB1E0375400D23DA92 / 404,992B | ✓ |
| run-f5-b-probe.ps1 | FF4DDF3F… / 7244B | FF4DDF3FE71639E6204A853B8F36FB810158802C1F321670B398FBFAFDFE57D0 / 7244B | ✓ |
| run-f5-lan-selftest.ps1 | 80C0935D… / 8842B | 80C0935DE04A2EA7F8A596B9E9B4B045C2EFFB8C671FDEF610FF9AF279BAB41E / 8842B | ✓ |
| PC-B-操作单.md | FF6679E9…E96 | FF6679E94BD20A1CD11AEB8D391F749CA3BC23F28D95F03E1B3DEC3B9BA56E96 / 3187B（与文档树 civlink\PC-B-F5-核验操作单-20261115.md 逐字节一致） | ✓ |
| fixture-reply-set | 完整（22 页） | 22 个 reply-*.bin（各 1104B）+ replies.csv + room-advert-content/stream + json\（4 文件），与文档树 fixture **逐文件哈希一致**（25 顶层文件全 SAME） | ✓ |
| 旁检 | run-f5-lan-selftest.ps1 断言数 | 12 项 Check（与 §3.1"断言 12 项"一致）；run-f5-b-probe.ps1 4 项 Check（与 §3.3 一致）；两者 Parser 0 errors | ✓ |

注记：
- （低，P3-1）**新旧哈希冲突**：文档 §4 表（L90）与 §6（L121）仍引用
  `run-f5-dualmachine-a.ps1 = 472FA16C…997C5`（旧脚本 7796B 的哈希），而实际产物
  （文档树 + kit）均为 D909D16F…B444B / 7926B。④落地更新了产物却未同步文档自身的
  哈希引用 → 按文档 §4 核对 kit 会出现不匹配。注：当前文档哈希 4AA1FF4E… 即含该旧引用
  的版本（复审清单给定的目标哈希即命中此版本），修正需重算文档哈希并由协调方重新认可。
- （信息，P4-4）文档 §6"已同步 civlink-f4"：实测 civlink-f4\civlink-agent.exe 为
  E276ECA3… / 402,944B（≠ 当前 194E6E8A… / 404,992B）；civlink\、civlink-f1\、
  civlink-f5-kit\ 三处均与当前版本一致。f4 目录持 F4 阶段构建，属历史快照，但与
  "已同步"表述不符。

---

## F. 边界（§5）— PASS

- §5 明示**不证明**：双人真实对局、E2-B 双端注入、62056 数据面、Relay RTT、Fake-IP、
  Noise 加密、跨网/长稳 ✓（L109-110）
- 明示不得据此勾掉 E2-A/E2-B/E3、不移动 Gate A/B、Gate A 未批准、M0-B 冻结 ✓（L111）
- 全文档 grep：无 `联机已验证`/`已验证`/`已通过` 等越界宣称；三节均自标为自测/机械验证；
  §7 状态如实（双机核验**待 B 机执行**，captures 无 civlink-f5-a-out/b-probe-out 成功产物）✓
- 无残留 `60 页`、无旧哈希 `105EC4902D` ✓
- §4 A 侧流程描述与修正后脚本（固定等待 + 断言 requests>0/replied≥1/pages==replied×22/
  失败计数全 0）一致 ✓

---

## 缺陷分级

| 级别 | 编号 | 内容 |
|---|---|---|
| 低 | P3-1 | 文档 §4 表 / §6 的 run-f5-dualmachine-a.ps1 哈希仍是旧值 472FA16C…997C5（7796B），实际产物为 D909D16F…B444B（7926B）；④落地后文档自身哈希引用未同步（修正将改变文档哈希 4AA1FF4E…，需协调方认可） |
| 低 | P3-2 | §3.2 `-b` 轮应答源 192.168.31.59:62900 无任何留存的客户端侧产物（全部 captures 仅 -c 有一份 client-observed.txt）；建议标注"（-b 轮观察值，客户端侧未留存）" |
| 信息 | P4-1 | （第一轮 D5，未列入复审必改范围，仍残留）run-f5-lan-selftest.ps1 头注 `Assertions (8)` 实为 12 项；头注提及 bind-check.txt 而脚本不产出 |
| 信息 | P4-2 | （第一轮 D6）§6"main.rs 2558 行"实测 2559 行，行数口径偏差 1 |
| 信息 | P4-3 | （第一轮 D7 同类）-c summary.txt 头部中文乱码（"双机发现"→"鍙屾満鍙戠幇"，控制台编码捕获差异），非内容篡改 |
| 信息 | P4-4 | §6"已同步 civlink-f4"不符：civlink-f4\civlink-agent.exe 为 E276ECA3…/402,944B（历史 F4 构建），非当前 194E6E8A…/404,992B |

无中、高级、无阻断级缺陷。

## 必改项

**无**（第一轮 4 项必改全部落地；本轮无新必改项。P3-1/P3-2 为低优先级建议，P4-* 为信息级注记）

## 最终裁定：通过（PASS）

身份（A）、必改 ①②③（B）、必改 ④（C）、客户端证据一致性（D）、kit 一致性（E）、
边界（F）全部核实无误：
- 文档 sha256/字节/BOM/控制字符与声明完全一致；§3.2 标题、多路径不定性应答源解释、
  agent 绑定地址说明、跨机单路径不适用、3 socket/66 页、§3.3 客户端侧独立证据引用
  均按要求落地；
- 脚本哈希/字节/Parser 0 错误；固定等待轮询（F5 audit D4 注释）替换了永不生效的
  提前退出轮询；7 个断言标签与 agent summary 标签全部一致；
- -c 客户端证据 51 文件：22 对 recv/page 逐字节一致、六项观察值与 summary 数字全部
  命中、22 页 head 正确、房名匿名化与 fixture 差异仅限房名字段；
- kit 全部哈希命中且与文档树版本一致，fixture 完整；
- §5 边界与无越界宣称、无旧数字/旧哈希残留全部确认。

第一轮"有条件通过"的两处中级缺陷（D1 应答源冲突、D2 客户端侧无留存证据）均已
通过"证据补齐（-c 客户端侧产物）+ 措辞重构（多路径不定性、绑定地址说明、§3.3
显式引用 -c 证据）"闭环，证据链现可独立复核。P3-1/P3-2 两项低优先级建议与
P4-* 信息注记不影响本次通过裁定，建议在后续迭代顺带修正。
