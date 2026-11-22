# M0-C / C2 跨机出口验证报告 —— 独立审计报告

- 审计日期：2026-11-18
- 被审对象：`docs/M0C-C2-EGRESS-20261118.md`（C2-b ② 跨机出口机制层验证报告，2026-11-18 17:07）
- 审计方式：只认磁盘文件，不采信任何口述替代证据；所有实测哈希由 `Get-FileHash -Algorithm SHA256` 现场重算
- 审计人角色：独立审计子代理（不参与该轮实验执行）

---

## 裁定摘要（置顶）

| 项 | 结论 |
|----|------|
| **总裁定** | **有条件通过（Conditional Pass）** |
| **阻断项数** | **4**（N-1、N-2、N-3、N-4 必须在登记前修正） |
| 非阻断记录项 | 1（N-5） |
| 核心机制层结论 | **成立**：三组 `replySrc` 随 B 侧 pin 切换，与 agent 源码 `send_to(page, from)` 行为一致，机制层跨机出口可采信 |
| 是否允许升级 C2-b 口径 | **修正后允许**（详见 §7） |
| 是否允许登记 README/HANDOVER | **修正后允许**，且必须限定为"机制层跨机验证完成（探针级）；真实游戏跨机对局待验证" |
| 是否允许进 C3 升级登记 | **完成 N-1..N-4 修正后允许；修正前不允许** |

阻断性质说明：4 项阻断均为**报告/证据文件的精度与自洽问题**，不推翻"IP_UNICAST_IF 定向在探针级跨机生效"这一核心结论。故裁定为有条件通过而非不通过。

---

## 一、逐条必答问题裁定表

| # | 必答问题 | 裁定 | 一句话依据 |
|---|----------|------|-----------|
| 1 | 证据一致性（哈希 / summary 对 §3 / probe-both-sides 自洽） | **需修正** | 11 文件哈希全对、summary 三数与 §3 全对；但 `probe-both-sides.txt` 第 11 行 `wlan firstLen=8` 与权威原始结果 `c2-egress-v3-results.txt`（`firstLen=1104`）及 §3"22 页 1104B"冲突 |
| 2 | 判据有效性（`replySrc` 反推 B 出口、源码 `send_to` 确认、证据缺口） | **需修正**（机制成立、措辞收紧） | `main.rs:731 reply_sock.send_to(page, from)` 确证回发到广播来源 IP，`replySrc` 可作 B 出口 IP 的代理量；但属 A 侧路由反推的间接证据，"铁证/一一对应"过强，无 B 侧线上抓包 |
| 3 | 实验缺陷纠正链（marker bug 发现/推翻是否诚实、是否影响采信轮） | **PASS** | v1 脚本仍在盘（`c2-b-send1.ps1:24/34-36` 尾字节 0x70/0x71/0x72 复现 bug），v2/v3 已统一 0x70；报告 §2 明确写"不是 Radmin 不达""现予推翻"，不影响 v3 采信轮 |
| 4 | 结论边界（§4.5 严谨性、§5 四条是否足够、有无越界） | **需修正** | §4.5"对局能否联机不取决于通道选择"、§4.1"铁证"超出探针级证据；§5 四条边界基本足够，建议补"replySrc 是 A 侧接收网卡 IP" |
| 5 | 字节序（set htonl / get 主机序 与产品实现是否一致、谁 bug） | **需修正** | set/get 机制与代码一致且正确；但 `ReadIfIndex` 只在 selftest 不在产品 DLL（报告归属 bug，非产品 bug）；"实测 ret=-1 err=10049"无盘上证据 |
| 6 | 丢包数字（wlan 8/10=20% 与历史 6–34%） | **PASS** | 历史 6~34% 见 `M0B-FINAL-PROGRAM-PLAN-20261117.md:10/58` 与 `E2B-CLIENT-LOG-ANALYSIS-20261116.md:41`（66/91/74/73/78/94 / 100），20% 在范围内；分母不同已在下文记录 |
| 7 | 采纳判定（可作采信依据、是否升级口径、是否登记） | **有条件通过** | 核心链自洽可采信；须先修 N-1..N-4，再按限定口径升级并登记 |

---

## 二、逐条依据

### Q1 证据一致性 —— 需修正

**（a）哈希一致性：PASS。** 现场重算证据目录全部文件，`MANIFEST-sha256.txt` 所列 11 个 artifacts 的 SHA-256 与实测逐字节一致（详见 §三）。MANIFEST 自身（1009 B / `FE36D2FB0823711A9355965BA6FF29283F0321A8B16366A7A1DD24BCC2C75BEB`）不在其自身清单内，属正常。目录实际为 12 个文件（11 artifacts + 1 MANIFEST），与任务书"11 文件"口径相符（11 指被列管 artifacts）。

**（b）三组 summary 与报告 §3 表格：PASS。**

| 组 | summary `requests seen` | `replied sockets` | `pages sent` | §3 表 seen / 页 | 一致？ |
|----|------------------------|-------------------|--------------|----------------|--------|
| baseline（`baseline-summary.txt:17-19`） | 10 | 1 | 22 | 10 / 22 页 | ✅ |
| radmin（`radmin-summary.txt:17-19`） | 10 | 1 | 22 | 10 / 22 页 | ✅ |
| wlan（`wlan-summary.txt:17-19`） | 8 | 1 | 22 | 8 / 22 页 | ✅ |

三组 `pages sent=22 == replied*22`，`send fail=0`、`no endpoint=0`、`bind fail=0`，自洽。

**（c）`probe-both-sides.txt` 自洽性：FAIL（需修正）。** 该第 7–12 行三组记录中：

- baseline 第 7 行、radmin 第 9 行 `firstLen=1104`；
- **wlan 第 11 行 `firstLen=8`**。

而权威原始结果文件 `M0A\c2-egress-v3-results.txt` 第 3 行明确写 wlan `firstLen=1104`（三组均 1104）；报告 §3/§4 据此称三组均"22 页 (1104B)"。`probe-both-sides.txt` 是手写汇总件、非工具原始输出，其 `firstLen=8` 疑为把 wlan 的 `seen=8` 误抄进 `firstLen`（巧合值 8）。后果：读者打开报告所采信的证据文件时看到 wlan `firstLen=8`，与报告的"1104B"直接冲突，破坏证据自洽。

- 报告 §3 表格本身未列 `firstLen` 列，故表格数字（22 页）未被**字面**证伪；
- 但"1104B"这一断言在采信证据文件内得不到支持，必须处理。

修正要求（N-1）：将 `probe-both-sides.txt:11` 的 `firstLen=8` 改为 `firstLen=1104` 并注明依据 `c2-egress-v3-results.txt`；文件改动后其 SHA-256 变化，须同步更新 `MANIFEST-sha256.txt` 第 4 行与报告 §6 第 59 行的哈希。**或**保留原文件、在报告中显式声明"probe-both-sides.txt 第 11 行为笔误，权威值为 c2-egress-v3-results.txt 的 1104"。二者择一，不可沉默略过。

### Q2 判据有效性 —— 需修正（机制成立）

**源码确证 `send_to(page, from)`：成立。** `civlink\agent\src\main.rs`：

- `LanSimState::consider`（`:701-750`）：`:712 stats.requests_seen += 1` 在去重之前；`:713` 去重键为 `(ip.to_be(), src_port.to_be())`；`:731 reply_sock.send_to(page, from)` 逐页回发；`:732 pages_sent += 1`。
- `poll`（`:640-693`）：`:645-652 recv_from` 得到 `from`，仅在 `is_discovery_magic` 精确匹配（`:528-530 data.len()==4 && data==DISCOVERY_MAGIC`）时调用 `consider`。
- `reply_sock` 是 62900 监听 socket（`:521` 注释"the 62900 listener doubles as the reply socket"），回发源 IP 由 A 机路由到 `from`（B 广播源 IP）决定。

**推理链：** B 广播源 IP（受 `IP_UNICAST_IF` pin 决定）→ A 回发该 IP 时按路由选源 IP → `replySrc`。因 A 双网卡分别位于 WLAN 192.168.31.x 与 Radmin 26.x 子网，路由对称，`replySrc` 与 B 出口 IP 具有一一对应——三组 `replySrc` 严格随 pin 切换（WLAN→192.168.31.60、Radmin→26.74.126.98、baseline→WLAN），内部强自洽。

**证据缺口（须在报告中如实收紧）：**

1. `replySrc` 是 **A 侧接收/回发网卡的 IP**，不是 B 侧线上抓包；从 `replySrc` 反推"B 广播出口网卡"依赖对称路由假设，无 B 侧 pktmon/Wireshark 直接证明广播离开 B 的 pin 网卡。报告 §5 已部分披露"非直接抓包……属间接证据"，但 §4.1 用"**铁证**"、§3 用"一一对应"，措辞强度超过证据性质。
2. 三组来源端口递增（58182/58183/58184）说明是三个独立 socket，良好；但 `wlan seen=8` 与 `replies=22` 并存说明 22 页全部送达 B，仅 2 个请求未在 A 计入 seen（去重/丢包），报告未解释这一 seen 与 replies 的口径差异（非错误，但读者易混淆）。
3. pktmon 直证路径被放弃（§5：A 无管理员 exit 5；B 有 pktmon 但 etl2txt 中文乱码、过滤 62900 无有效行），这恰是最直接的缺口来源，应保留在边界中。

修正要求：§4.1"铁证"改为"机制层强证据（间接判据）"；§5 第 3 条补明"`replySrc` 是 A 侧按发往 B 广播源 IP 的路由所选的本地回发 IP，反推 B 出口依赖对称路由假设，非 B 侧线上抓包"。

### Q3 实验缺陷纠正链 —— PASS

- **bug 真实存在且可复现于盘**：`M0A\c2-b-send1.ps1:24` `var payload = new byte[]{0x8d,0xe8,0xfc,(byte)marker};`，配合 `:34-36` baseline=`0x70`、radmin=`0x71`、wlan=`0x72`。agent 只认精确 magic `8D-E8-FC-70`（`main.rs:528-530`），故 0x71/0x72 组必被判噪声、seen=0。报告 §2.1 的因果链与源码一致，诚实。
- **纠正可查**：`M0A\c2-b-send1-v2.ps1:24-25` 三组统一 `0x8d,0xe8,0xfc,0x70`；v3（`:19-24`）在 v2 基础上加 setsockopt pin 与应答源 IP 抓取。
- **历史结论已明确推翻**：§2.1 第 23–24 行"不是 Radmin 通道不达……现予推翻"，§4.3"'Radmin 不送达'结论作废"。读者不会被误导为旧结论仍有效。PASS。
- **记录性注意（不构成阻断）**：v1 `seen=0` / v2 `seen=10` 两轮的原始运行日志未归档进证据目录（目录只有 v3 的 11 文件 + M0A 根 `c2-egress-v3-results.txt`）。marker bug 的"发现与推翻"叙事建立在仍存活的 v1/v2 脚本源码 + 报告自述之上。因该历史链只涉及被弃用的轮次、不影响 v3 采信轮，接受；但按"结论落磁盘"原则列为 N-5 记录项。§2.2 的两处 C# 编译错误修复（ReceiveFrom 须 `ref EndPoint`、LocalEndPoint 在首包后读）与 v3 源码一致（`:31` `EndPoint from`、`:27` 发送循环后读 LocalEndPoint），属合理叙事，无独立日志。

### Q4 结论边界 —— 需修正

- **§4.5 第一句"无法回答刚才那局走哪条通道"：严谨。** §1 第 12–16 行进程已重启、对局期未抓包、A/B 无发现端点，静态数据不足——支持"无法回答"。
- **§4.5 后半"当前两通道都可用，故对局能否联机不取决于通道选择（Radmin 与 WLAN 都能完成发现闭环）"：需收紧。** 实验证明的是"探针级发现闭环在两通道均可完成"，**没有**验证真实《文明6》加入/数据面，不能推出真实对局联机不取决于通道。此处越界到游戏层，应改为"本探针所测的发现闭环在两通道均可完成；真实对局联机是否受通道影响未在本轮验证"。
- **§4.1"铁证"：需收紧**（见 Q2）。
- **§5 四条边界：足够但可增强。** 第 1 条（探针非注入 DLL、组合两半=机制层）、第 2 条（禁称真实双人/禁勾 E2/Gate）、第 3 条（replySrc 间接）、第 4 条（pktmon 不可用）均已覆盖关键越界路径。建议第 3 条补"replySrc 是 A 侧接收网卡 IP"以消除歧义。
- **未发现越界宣称**：报告通篇标注"机制层跨机验证完成；不等于真实游戏跨机对局验证"（§1 第 6 行、§5），§7 亦写明"真实游戏跨机对局待验证"。硬约束（不勾 E2-A/E2-B/E3、不勾 Gate、/MT、MinHook v1.3.4）未被突破。唯一需收紧的是 §4.5 的因果外推与 §4.1 的强度词。

### Q5 字节序 —— 需修正

**机制本身与产品代码一致（PASS）：**

- 探针 v3 `c2-b-send1-v3.ps1:19` `BitConverter.GetBytes(IPAddress.HostToNetworkOrder(ifindex))` 写 setsockopt——网络序；`:20-21` getsockopt 后 `BitConverter.ToInt32(b,0)` 读回——主机序 7/17。与报告 §4.2 前半一致。
- 产品 `civlink\client\civlink_client.cpp:99` `unsigned long g_pinIfIndex = 0; // host-order`；`PinSend` `:301` 保存 last error、`:302 DWORD beIdx = htonl(g_pinIfIndex);`、`:303 setsockopt(...IP_UNICAST_IF...)`、`:304 WSASetLastError(savedErr)`。**产品 set 用 htonl 正确**。
- 设计文档 `M0C-C2-DESIGN-20261118.md:125/128/140` 明确要求 network byte order（MSDN 语义），与实现一致。

**报告 bug（非产品 bug）：**

1. `ReadIfIndex` 归属错误。报告 §4.2"产品 `PinSend` 用 `htonl(...)`、`ReadIfIndex` 读主机序——实现正确"把 `ReadIfIndex` 说成产品实现；实际 `ReadIfIndex` 只在自测 `civlink\selftest\client_selftest.cpp:180-187`（注释 `:179` "Verified on this host: set htonl(19) -> getsockopt returns 19 (host order)"）。产品 DLL 中**无** getsockopt/ReadIfIndex（grep 仅命中注释与 setsockopt）。这是报告措辞 bug，不是产品缺陷；产品实现本身正确。
2. "此前 host-order 直传实测 `ret=-1 err=10049`（失败）"**无盘上证据**。全项目 grep `10049` 仅命中本报告第 45 行（其余均为日志行号巧合，如 `#010049`）。该数值未出现在任何证据/日志/脚本中。按"不采信口述、结论落磁盘"原则，此经验断言不可采信。10049=WSAEADDRNOTAVAIL，host-order 7 会被当作 IP 7.0.0.0 而可能失败——机制上合理（设计文档可支持"须用网络序"的推断），但不能以"实测"名义写出。

修正要求（N-2、N-3）：删除"实测 ret=-1 err=10049"或降级为"依 MSDN/设计文档，host-order 会被误判为 IP，故须 htonl（推断，非本轮实测）"；把 `ReadIfIndex` 明确标为"自测探针 `client_selftest.cpp` 中的读回函数"，不要归入产品 DLL。

### Q6 丢包数字 —— PASS

- wlan 组 A `requests seen=8/10` → 20% 丢包，报告 §4.4 表述准确。
- 历史区间有据：`docs/M0B-FINAL-PROGRAM-PLAN-20261117.md:10/58`"广播丢包 6~34%"；`docs/E2B-CLIENT-LOG-ANALYSIS-20261116.md:41` A 实收 66/91/74/73/78/94（每 100 包）→ 丢包 34%/9%/26%/27%/22%/6%。20% 落在 6–34% 内。
- 记录性差异（非错误）：历史为 100 包/轮的 Civ6 客户端广播，本轮为 10 包探针，分母与条件不同；报告"一致"为宽松比较，可接受，但严格说两组成因需分别归因（本轮 2 个请求未计入 seen 但 22 页仍全达 B，见 Q2-2）。

### Q7 采纳判定 —— 有条件通过

**能否作采信依据：能（在完成 N-1..N-4 修正后）。** 核心证据链落在磁盘且自洽：

- 11 文件哈希实测与 MANIFEST 一致（§三）；
- 三组 summary 数字与 §3 表一致；
- agent `send_to(page, from)` 由源码确证；
- 三组 `replySrc` 随 pin 严格切换，`pinret=0 get=7/17` 证明 setsockopt 生效且字节序正确；
- C2-b 半①（真实游戏注入+发现识别）证据 `M0A\captures\C2-real-game-20261118-1104\counters.log` 独立存在（题设为既定事实 raw sendto=200/ignored=200/ALL/sent=0）。

**是否允许升级 C2-b 口径：修正后允许。** 可从"跨机出口未验证"升级为"**机制层跨机验证完成（探针级）；真实游戏跨机对局待验证**"。不得据此宣称真实双人对局、不得勾 E2-A/E2-B/E3 或任何 Gate。

**是否允许登记 README/HANDOVER：修正后允许。** 当前 `CivLink-M0A-audit\README.md:4` 仍写"C2-b 真实出口与真实《文明6》进程注入未验证"，升级尚未登记；登记时必须保留"真实游戏跨机对局未验证"限定语，并同步更新 C2 审计状态描述。

**明确写：允许进 C3 升级登记——但以完成 N-1..N-4 修正为前提；修正前不允许。**

---

## 三、证据文件哈希实测值（SHA-256）

现场用 `Get-FileHash -Algorithm SHA256` 重算，目录 `C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\C2-egress-v3-20261118-1707`。下表 ≥6 项（列全 11 + MANIFEST + 外部对照）：

| 文件 | 字节 | 实测 SHA-256 | 与 MANIFEST |
|------|------|--------------|-------------|
| baseline-agent-console.txt | 0 | `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855` | ✅ |
| baseline-agent-stderr.txt | 0 | `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855` | ✅ |
| baseline-summary.txt | 2750 | `46FF24444B44C5FB9C850C538002A8DEACC335D5EA231E8225C983317CE74195` | ✅ |
| probe-both-sides.txt | 1285 | `99E44825E2D6BC9AF5ADC2DD36DA27F10374E33F1A286C54A2B6F6E78B129886` | ✅（内容自洽性另见 N-1） |
| probe-b-send1-v3.ps1 | 2685 | `3278A6FEE528D286B2B68C6DC18AC14BFA0BA417C175A803906548F7A9AEC0D2` | ✅ |
| radmin-agent-console.txt | 0 | `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855` | ✅ |
| radmin-agent-stderr.txt | 0 | `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855` | ✅ |
| radmin-summary.txt | 2750 | `9500D72EF25DFA47B7BD2A77D2D21EC27A09302BFA3F7F6B333C9FB18AAA1612` | ✅ |
| wlan-agent-console.txt | 0 | `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855` | ✅ |
| wlan-agent-stderr.txt | 0 | `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855` | ✅ |
| wlan-summary.txt | 2749 | `8DC2116863E3CEBA941A706C09813FDC0482B8C1CCBFE2550DDA3934A96D603B` | ✅ |
| MANIFEST-sha256.txt（清单本身，不在其内） | 1009 | `FE36D2FB0823711A9355965BA6FF29283F0321A8B16366A7A1DD24BCC2C75BEB` | — |
| 对照：A 侧 agent `C:\Users\dd\Desktop\civlink-f1\civlink-agent.exe` | 418816 | `033D7741617828B4CF34F1812DD94AF48AE9E3E644BBC0DB9AEBAC3A6B35BFB7` | 与所声明前缀 033D7741 一致 |
| 对照：M0A 根 `c2-b-send1-v3.ps1` | 2685 | `3278A6FEE528D286B2B68C6DC18AC14BFA0BA417C175A803906548F7A9AEC0D2` | 与目录内副本一致 |

零字节文件为 agent 的 console/stderr 重定向空文件（三组各两个），符合"agent 全程后台监听、无 stdout/stderr 输出"的运行形态；它们的哈希等于 SHA-256 空串常量，正常。

---

## 四、新发现问题清单

**N-1（阻断）｜证据文件内部矛盾：wlan `firstLen`。** `probe-both-sides.txt:11` 写 `firstLen=8`，而权威原始 `M0A\c2-egress-v3-results.txt:3` 写 wlan `firstLen=1104`，报告 §3/§4 据此称"22 页 1104B"。手写汇总件与原始结果不一致，疑为把 `seen=8` 误抄。修正后须同步更新 MANIFEST 与报告 §6 哈希，或在报告中显式声明笔误及权威值。

**N-2（阻断）｜无盘证据的经验断言。** §4.2"此前 host-order 直传实测 `ret=-1 err=10049`"全项目无对应记录（grep `10049` 仅命中该行）。删除或降级为依 MSDN/设计文档的推断，不得以"实测"名义写出。

**N-3（阻断）｜`ReadIfIndex` 归属错误。** §4.2 将其归入"产品"实现；实际仅存在于 `civlink\selftest\client_selftest.cpp:180-187`，产品 DLL 无 getsockopt。属报告 bug 非产品 bug；改文即可。

**N-4（阻断）｜结论强度越界。** §4.1"铁证"、§4.5"对局能否联机不取决于通道选择（Radmin 与 WLAN 都能完成发现闭环）"超出探针级证据，应收紧为"探针所测发现闭环两通道均可完成；真实对局联机是否受通道影响未验证"。§5 第 3 条补"replySrc 是 A 侧接收网卡 IP；反推 B 出口依赖对称路由假设"。

**N-5（记录，非阻断）｜历史轮次原始日志未归档。** v1 `seen=0` / v2 `seen=10` 及两处 C# 编译错误历史的原始日志未进证据目录；marker bug 链依赖仍在盘的 v1/v2 脚本源码 + 报告自述。仅涉及被弃用轮次，不影响 v3 采信轮，故不阻断；但按"落磁盘"原则在此记录。

---

## 五、采信结论（给 C3 升级登记用）

- **核心结论：采信。** C2-b ② 跨机出口在**探针级/机制层**完成验证：三组独立发包，`setsockopt(IPPROTO_IP, 31, htonl(ifidx))` 在各组 `pinret=0`、`getsockopt` 读回 7/17，B 收 22 页应答，`replySrc` 随 pin 切换且与 agent 源码 `send_to(page, from)` 一致。
- **证据完整性：修正后采信。** 哈希链、summary 数字、源码链均通过；N-1..N-4 为精度问题，须先修正。
- **边界（强制保留）：** 这是模拟主机（F5 `--sim-lan-listen`）+ 独立 UdpClient 探针，不是注入真实《文明6》的跨机发包，更不是真实双人对局；不得称 E2-A/E2-B/E3 通过，不得勾任何 Gate；/MT 静态 CRT 与 MinHook v1.3.4 约束未被本报告触及、保持原状。

---

## 六、最终裁定

**有条件通过（4 项阻断）。允许进入 C3 升级登记——前提是完成 N-1、N-2、N-3、N-4 修正；修正前不允许。** 修正后按"机制层跨机验证完成（探针级）；真实游戏跨机对局待验证"口径升级 C2-b 并登记 README/HANDOVER，保留全部边界语。

（本报告全部结论依据磁盘文件；未采信任何口述替代证据。）
