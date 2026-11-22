# M0-C / C2 跨机出口验证报告 —— 第二轮独立复审报告

- 复审日期：2026-11-18
- 复审对象：`docs/M0C-C2-EGRESS-20261118.md`（8,619 B / SHA-256 `0403AFBA09A6C6A316DFF8B4AD712A725E9C9CA71D12FDDCAC919F51B46B7926` / 无 BOM）
- 复审参照：`docs/M0C-C2-EGRESS-REVIEW-20261118.md`（第一轮审计，有条件通过 + 4 阻断 N-1..N-4 + 记录项 N-5）
- 证据目录：`C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\captures\C2-egress-v3-20261118-1707`（12 文件 = 11 artifacts + MANIFEST）
- 权威原始结果：`C:\Users\dd\Desktop\injciv6-v0.3.3\M0A\c2-egress-v3-results.txt`（552 B，wlan `firstLen=1104`）
- 复审方式：只认磁盘文件；所有 SHA-256 与字节数由 `Get-FileHash -Algorithm SHA256` / `Get-Item.Length` 现场重算；中文内容以 `[System.IO.File]::ReadAllText(path, UTF8)` 精确读取，避免编码误判
- 复审人角色：独立复审子代理（未参与该轮实验执行，未参与报告修正）

---

## 裁定摘要（置顶）

| 项 | 结论 |
|----|------|
| **总裁定** | **通过（PASS）——第一轮 4 项阻断全部关闭，无新增阻断** |
| **N-1**（probe firstLen/哈希/MANIFEST） | **PASS** |
| **N-2**（10049 经验断言清除） | **PASS** |
| **N-3**（ReadIfIndex 归属） | **PASS** |
| **N-4**（结论强度与边界收紧） | **PASS** |
| 记录项 N-5 | 维持记录（非阻断，未要求本轮处理） |
| §8 修正记录表 | **PASS**（与 N-1..N-5 逐条对应、内容属实） |
| 边界保持 | **PASS**（未宣称真实双人对局，未勾 E2-A/E2-B/E3/Gate） |
| **是否允许进 C3 升级登记（README/HANDOVER 口径升级）** | **允许**——以"机制层跨机验证完成（探针级）；真实游戏跨机对局待验证"口径升级并登记，保留全部边界语 |
| 新增阻断 | 无（未发现 N-6） |

裁定说明：第一轮 4 项阻断均为报告/证据文件的精度与自洽问题，本轮逐条核验均已在磁盘上真实修正，且修正引发了预期的哈希变更（探针文件与 MANIFEST）并已同步到所有声明位置。核心"IP_UNICAST_IF 定向在探针级跨机生效"结论未被推翻，瑕疵关闭后由"有条件通过"转为"通过"。

---

## 一、逐条必答裁定

### N-1｜PASS —— 证据一致性全部对齐

| 核验点 | 磁盘实测 | 结论 |
|--------|----------|------|
| `probe-both-sides.txt:11` wlan firstLen | `firstLen=1104`（不再为 8） | ✅ 已从 8 改为 1104 |
| CORRECTION 说明 | 第 19 行：`CORRECTION (2026-11-18, audit N-1): wlan firstLen was mis-transcribed as 8 (copied from seen=8); authoritative value is 1104 per M0A\c2-egress-v3-results.txt. Now corrected.` | ✅ 已追加，且指明权威来源 |
| `probe-both-sides.txt` 重算哈希 / 字节 | 1,463 B / `0E0D4A9EFA44856E46EA67329E1D913EAF9A58D1A0C3954E2C2624E9A79D1F8D` | ✅ 与题设、报告 §6、MANIFEST 第 4 行三方一致 |
| `MANIFEST-sha256.txt` 第 4 行 | `probe-both-sides.txt  1463  0E0D4A9E…79D1F8D` | ✅ 与实测逐字节一致 |
| 报告 §6 第 59 行 | `probe-both-sides.txt` 1,463 B / `0E0D4A9E…79D1F8D`（并注明"审计 N-1 修正后"） | ✅ 已同步 |
| 权威原始值交叉核对 | `M0A\c2-egress-v3-results.txt:3` wlan 组 `firstLen=1104` | ✅ 三组合规（baseline/radmin/wlan 均 1104） |
| MANIFEST 全 11 行 | 逐行程序化比对：11/11 行文件名、字节数、SHA-256 全部与实测一致（`ALL_OK=True`） | ✅ 无漂移 |

附带观察（非阻断）：MANIFEST 自身因第 4 行变更，其自哈希由第一轮记录的 `FE36D2FB…C75BEB` 变为 `61A733E4AEFA8D9BF46CA5DE6958C2E1F600AE776A3FE53148985940886230B9`（1,009 B），属预期连锁变化；当前报告 §6 未引用清单自哈希，无陈旧值残留。目录实际 12 文件与题设"11 artifacts + MANIFEST"一致。

**N-1 裁定：PASS。**

### N-2｜PASS —— 无据经验断言已清除

- 报告 §4 第 2 点现文：`依 MSDN IP_UNICAST_IF 语义与设计文档 M0C-C2-DESIGN-20261118.md:125/128/140，host-order 会被误判为 IP 地址，故须 htonl——此为文档支持的推断，本轮未实测 host-order 失败，不声称任何具体错误码数值（审计 N-2）。`
- 以 UTF-8 精确扫描全文：`10049` 仅出现 1 次，位于 §8 修正记录表第 76 行 `| N-2 | 删除无据的 err=10049 实测断言 | … |`，属**修正记录的历史引用**，不是经验断言；正文（§1–§7）无任何 `10049`、`ret=-1`、`WSAEADDRNOTAVAIL` 断言。
- `实测 ret`、`铁证` 等旧表述正文均无残留。

**N-2 裁定：PASS。**

### N-3｜PASS —— ReadIfIndex 归属更正

- 报告 §4 第 2 点现文：`读回函数 ReadIfIndex 仅存在于自测探针 civlink\selftest\client_selftest.cpp:180-187，产品 DLL 无 getsockopt/ReadIfIndex（审计 N-3，报告归属更正，非产品缺陷）。`
- 与第一轮审计结论一致：不再把 `ReadIfIndex` 归入产品实现；产品 `PinSend`（`civlink\client\civlink_client.cpp:301-304`）仅 setsockopt、无 getsockopt。

**N-3 裁定：PASS。**

### N-4｜PASS —— 结论强度与边界全面收紧

| 位置 | 修正后措辞 | 结论 |
|------|-----------|------|
| §4 第 1 点（原 §4.1） | `IP_UNICAST_IF 定向跨机生效（机制层强证据，间接判据）`，并补 `replySrc 是 A 侧接收/回发网卡的 IP，非 B 侧线上抓包，反推 B 出口依赖对称路由假设` | ✅ "铁证"已废止 |
| §4 第 5 点（原 §4.5） | `本实验只证明探针级发现闭环在当前环境的两条通道上均可完成（Radmin 与 WLAN 都能送达 22 页应答）；真实对局联机是否受通道影响未在本轮验证` | ✅ "对局能否联机不取决于通道选择"已删除，"一一对应"不再出现 |
| §5 第 3 条 | `replySrc 是 A 侧按发往 B 广播源 IP 的路由所选的本地回发 IP，反推「B 广播出口网卡」依赖对称路由假设，非 B 侧线上抓包；结论链自洽但属间接证据（审计 N-4）` | ✅ 三要素齐备（A 侧回发 IP / 对称路由假设 / 非 B 侧线上抓包） |

**N-4 裁定：PASS。**

### §8 修正记录表｜PASS

表内 N-1..N-5 五行与第一轮阻断逐条对应，内容经磁盘核验属实：

- N-1 行所述"改 1104 + 追加 CORRECTION + 重算 0E0D4A9E…/1,463 B + MANIFEST 第 4 行与 §6 同步"——全部实测成立。
- N-2 行所述"§4 第 2 点删除具体错误码，改为推断且本轮未实测"——成立。
- N-3 行所述"§4 第 2 点标注 client_selftest.cpp:180-187，产品 DLL 无 getsockopt"——成立。
- N-4 行所述三处收紧——成立。
- N-5 行维持记录项定位（不影响 v3 采信轮），无夸大。

**§8 裁定：PASS。**

### 边界保持｜PASS

- 报告状态行（第 6 行）：`状态：机制层跨机验证完成；不等于真实游戏跨机对局验证`——保留。
- §5 边界段完整保留"独立探针 UdpClient 非注入真实 Civ6""组合两半可称机制层跨机验证完成""不得宣称真实双人对局已验证 / E2-A/E2-B/E3 已通过 / 勾任何 Gate""pktmon 缺口"等全部限定语。
- §4 第 5 点对"`刚才那局走哪条通道`"仍回答"无法回答"，未越界归因。
- 全文无"真实双人对局已验证""E2 已通过""Gate 已勾"类宣称；/MT、MinHook v1.3.4 约束未被触及。
- 报告 §7 明确登记动作"复审通过后执行"；截至本次复审，`README.md` 第 4 行与 `docs/CODEX-HANDOVER-M0A.md` 第 156/160 行仍记 C2-b 为"未验证"——与本轮"通过后才登记"的时序一致，非遗漏。

**边界保持裁定：PASS。**

---

## 二、实测哈希与字节数依据

现场重算（SHA-256，大写），覆盖证据目录全部 12 文件 + 报告 + 权威原始结果，满足"至少重算 4 个文件"要求：

| 文件 | 实测字节 | 实测 SHA-256 | 对照 |
|------|---------|--------------|------|
| `probe-both-sides.txt`（证据目录） | 1,463 | `0E0D4A9EFA44856E46EA67329E1D913EAF9A58D1A0C3954E2C2624E9A79D1F8D` | = MANIFEST:4 = 报告 §6 = 题设 ✅ |
| `MANIFEST-sha256.txt` | 1,009 | `61A733E4AEFA8D9BF46CA5DE6958C2E1F600AE776A3FE53148985940886230B9` | 清单自身，不在其 11 行清单内（预期） |
| `baseline-summary.txt` | 2,750 | `46FF24444B44C5FB9C850C538002A8DEACC335D5EA231E8225C983317CE74195` | = MANIFEST:3 = 报告 §6 ✅ |
| `radmin-summary.txt` | 2,750 | `9500D72EF25DFA47B7BD2A77D2D21EC27A09302BFA3F7F6B333C9FB18AAA1612` | = MANIFEST:8 = 报告 §6 ✅ |
| `wlan-summary.txt` | 2,749 | `8DC2116863E3CEBA941A706C09813FDC0482B8C1CCBFE2550DDA3934A96D603B` | = MANIFEST:11 = 报告 §6 ✅ |
| `probe-b-send1-v3.ps1` | 2,685 | `3278A6FEE528D286B2B68C6DC18AC14BFA0BA417C175A803906548F7A9AEC0D2` | = MANIFEST:5 ✅ |
| baseline/radmin/wlan `*-agent-console.txt`、`*-stderr.txt`（6 文件） | 0 ×6 | `E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855`（空串常量）×6 | = MANIFEST:1/2/6/7/9/10 ✅ |
| `M0C-C2-EGRESS-20261118.md`（被复审报告） | 8,619 | `0403AFBA09A6C6A316DFF8B4AD712A725E9C9CA71D12FDDCAC919F51B46B7926` | = 题设值，BOM=False ✅ |
| `M0C-C2-EGRESS-REVIEW-20261118.md`（第一轮审计） | 20,209 | `EBF717AAADB3DFFC86D011E492FC1F3C06F81054E6126CB8D1B403F282091664` | 参照件，BOM=False |
| `M0A\c2-egress-v3-results.txt`（权威原始） | 552 | `E2638E1FD89308D11201210D68BA5637DA3291A3CA84126451E5235AD0AEF2A7` | 第 3 行 wlan `firstLen=1104`，BOM=False ✅ |

MANIFEST 全 11 行按"文件名 + 字节数 + SHA-256"三元组逐行程序化比对结果：**11/11 全部一致（`ALL_OK=True`）**。

---

## 三、采信结论（给 C3 升级登记用）

- **核心结论：采信（探针级 / 机制层）。** 三组独立发包、`setsockopt(IPPROTO_IP, 31, htonl(ifidx))` 各组 `pinret=0`、`getsockopt` 读回 7/17、B 收 22 页应答、`replySrc` 随 pin 严格切换且与 agent 源码 `send_to(page, from)` 一致。
- **证据完整性：采信。** 哈希链、summary 数字、源码链均通过；第一轮 4 项精度阻断已全部在磁盘上关闭。
- **是否允许进 C3 升级登记（README/HANDOVER 口径升级）：允许。** 按报告 §7 既定动作，把 C2-b 口径从"跨机出口未验证"升级为"**机制层跨机验证完成（探针级）；真实游戏跨机对局待验证**"，并同步 README（当前 L4/L1474）与 `docs/CODEX-HANDOVER-M0A.md`（当前 L156/L160）的 C2-b 状态描述。
- **强制保留边界：** 不得据此宣称真实双人对局、不得勾 E2-A/E2-B/E3 或任何 Gate；/MT 静态 CRT 与 MinHook v1.3.4 约束保持原状；`replySrc` 判据的间接性（A 侧回发 IP / 对称路由假设 / 非 B 侧线上抓包）须随口径一并保留。

---

## 四、最终裁定

**通过（PASS）。** 第一轮 4 项阻断 N-1..N-4 全部关闭，§8 修正记录属实，边界保持完好，未发现新增阻断（无 N-6）。

**允许进入 C3 升级登记（README/HANDOVER 口径升级）**——以"机制层跨机验证完成（探针级）；真实游戏跨机对局待验证"限定口径执行，并保留全部边界语。

（本报告全部结论依据磁盘文件现场重算与 UTF-8 精确读取；未采信任何口述替代证据。）
