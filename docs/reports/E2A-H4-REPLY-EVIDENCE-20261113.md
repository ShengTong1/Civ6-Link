# E2-A / H4 证据报告：房主发现回复的完整结构与载荷解码

- **报告编号**：E2A-H4-REPLY-EVIDENCE-20261113（v2，2026-11-13 00:47 重写）
- **实验归属**：M0-A / E2-A 补正（REV-012-REVIEW 请求项②）
- **证据等级**：**单机自收（同一进程既建房又监听）**，不是双机验收，不构成 Gate A 通过依据
- **门禁状态**：Gate A 未批准、M0-B 冻结

---

## §0 两个结论级更正（相对 v1 与本项目此前所有报告）

### 更正 1：E2-A 那次抓包里**本来就有房主回复**，此前"0 回复"是工具盲区

此前所有报告（E1、E2-A、REV-005 提交）都写"未观察到任何发现回复"。原因不在协议，而在**分析脚本的选择器**：

```
analyze-pcapng-datagrams.ps1 的筛选条件 = dstPort ∈ 62900..62999
房主回复的实际特征            = srcPort = 62900 → dstPort = 客户端临时端口(53787)
```

方向相反，因此**结构性永远选不到**。重新用两遍分类（先认 REQ，再认"目的地命中 REQ 源端口"的包）解析同一份 `A-pcapng-20261112_174753.pcapng`，得到 **1 个请求 + 22 个回复身份**。

### 更正 2：一个请求换回的是**22 个内容各不相同的分页**，不是 22 份副本

此前把"22 个身份 × 4 副本"记作"pktmon 多捕获点重复采样"。**重复采样是真的（4 个捕获点），但 22 个身份本身内容互不相同**：它们是一份 20 636 字节公告被切成 22 页、每页 1104 字节。sha256 序列在三次独立请求中完全一致，可复现。

---

## §1 提取方法

| 阶段 | 方法 | 结果 |
|---|---|---|
| 抓包 | `pktmon start --capture --pkt-size 128`（截断到 128 B） | 231 205 EPB / 181.885 s |
| v1 分类 | 只筛 dstPort 62900-62999 | **0 个回复**（错误） |
| v2 分类 | 两遍：REQ 按 dstPort+magic；REP 按 srcPort 区间 **且** dstPort 命中实际 REQ 源端口 **且** 目的非组播/广播 | **1 REQ + 22 REP** |
| 去重 | 键 = (Kind, SrcIp, DstIp, SrcPort, DstPort, IpId) | 88 条原始记录 → 22 个身份 |
| 补全载荷 | 单机自收：本机同进程建房后向 `255.255.255.255:62900..62999` 发 1 个 4 B 请求，用 `ReceiveMessageFrom` 收全 22 个完整 1104 B | 22 × 1104 B 完整落盘 |

> **踩坑记录（写入教训库）**：两遍分类首版把 SSDP 回复 `172.27.112.1:62984 → 239.255.255.250:2200`（载荷以 `RESPONSE` 开头）误判为发现回复，因源端口 62984 落在区间内 → 混入 36 个 SSDP 身份、T_response 被算成 **−60 485 ms**。修正后正常。**端口区间是弱判据，必须结合方向与关联性。**

---

## §2 分页结构（22 页全部逐字节验证）

### §2.1 单页布局（1104 B，所有整数小端）

| 偏移 | 长度 | 字段 | 实测值 |
|---|---|---|---|
| 0 | 4 | magic | `0x9B696059`（字节序 `59 60 69 9B`） |
| 4 | 4 | appid | **289070**（Civ6 Steam AppID） |
| 8 | 4 | — | 0 |
| 12 | 4 | — | 3 |
| 16 | 4 | — | 1 |
| 20 | 4 | — | 6 |
| 24 | 22 | 房间/玩家名（UTF-8，零填充） | `dingzihan2022的游戏` |
| 46 | 106 | 零填充 | 全 0 |
| 152 | 4 | **记录数** | **13** |
| 156 | 4 | **总页数** | **22** |
| 160 | 4 | **页索引** | **0..21** |
| 164 | **938** | 内容 | 见 §3 |
| 1102 | 2 | 零尾标 | `00 00` |

> 字段 8/12/16/20 在本轮抓包中为常量，**语义未裁决**，不得当作已知协议字段引用。

### §2.2 全 22 页断言（全部通过）

```
pages found: 22
page indexes : 0,1,...,21
indexes are exactly 0..N-1 : True
header bytes [0..151] identical in every page : True
footer bytes [1102..1103] zero in every page  : True
page count field (156) == actual page count   : True
```

### §2.3 ★ 关键修正：内容区是 938 B，不是 940 B

v1 的分析器假设 `1104 = 164 header + 940 content`，导致**每条记录声明的长度都比实测短 2 字节的整数倍**（EnabledMods 声明 17984 / 实测 18022，差 38 = 19 对 × 2），并按 940 切分时把每页末尾的 2 字节零填充带进内容流，插在 JSON 中间 → 四个 JSON 全部报 `Invalid object passed in, ':' or '}' expected.`。

**根因：每页末尾有 2 字节零尾标（offset 1102..1103），真实内容 938 B。** 按 938 切分后：

```
content length = 20636 B (22 x 938)
records decoded   : 13
framing exact     : True
consumed          : 19990 / 20636 B
trailing bytes    : 646 B  all zero = True
header recordCnt (13) matches decoded count : True
JSON blobs valid  : 4   invalid : 0
```

> **之前那条"38 个 NUL 嵌在 chunk 相对偏移 774/775"的判断是错的**——那是把页内绝对偏移 1102/1103 减 164 再对 940 取模算出来的假位置。正确位置就是每页最后两个字节。

---

## §3 记录流（13 条，顺序即发送顺序）

| # | 名称 | 长度 | 值 |
|---|---|---|---|
| 0 | `EnabledGameModeNames` | 0 | （空） |
| 1 | `EnabledMods` | 17 984 | JSON，**45 个 mod** |
| 2 | `GameSpeed` | 11 | `-1649545904` |
| 3 | `GameSpeedName` | 488 | JSON `LOC_GAMESPEED_ONLINE_NAME`（在线速度） |
| 4 | `GameStarted` | 1 | `0` |
| 5 | `GameVersion` | 18 | `1.0.12.54 (951533)` |
| 6 | `Initialized` | 1 | `1` |
| 7 | `MapDisplayName` | 482 | JSON `LOC_MAP_PANGAEA`（12 语言本地化） |
| 8 | `MapName` | 11 | `Pangaea.lua` |
| 9 | `MapSize` | 11 | `-1837222328` |
| 10 | `RuleSet` | 19 | `RULESET_EXPANSION_2` |
| 11 | `RuleSetName` | 718 | JSON `LOC_EXPANSION2_NAME` |
| 12 | `SavedGame` | 1 | `0` |

**4 个 JSON 字段全部通过 `ConvertFrom-Json`**：`EnabledMods`（45 个 mod 条目，含 `modid`/`version`/`title`/`subscriptionid`，title 内嵌多语言 locale）、`GameSpeedName`、`MapDisplayName`、`RuleSetName`。

`EnabledMods` 内容举例（45 条中的一部分）：`02A8BDDE…`(LOC_AZTEC_MONTEZUMA)、`City Roads`(1284907124)、`Denser Vegetation`(2115981252)、`113D9459…`(Teddy Roosevelt Persona Pack)、`Real Era Tracker`(1699006932)、`YnAMP`(871861883)、`Extended Diplomacy Ribbon`(1360462633)、`Quick Deals`(2460661464)、`Better Report Screen`(1312585482)、`Sukritact's Simple UI Adjustments`(939149009)、`Cheat Map Editor`(1651487987) 等，另含 Ethiopia / Babylon / Byzantium+Gaul / Vietnam+Kublai / Portugal / Maya+Gran Colombia 等资料片条目。

---

## §4 ★ H4 当前样本裁决：载荷未发现房主 IP，抓包观察到回复源 IP

对重组后的全部 20 636 字节做严格 dotted-quad 扫描：

```
dotted-quad strings found: 1
  offset 18607 : 1.0.12.54        <- GameVersion 文本，非地址
```

- 定向搜索 `192.168.31.59`（房主 WLAN）、`26.74.126.98`、`255.255.255.255` 的**正序与反序字节**：全部 NOT FOUND；
- UTF-8 文本区内无任何 dotted-quad 形式的地址字符串。

**结论（限定样本）**：在本次完整公告样本中未发现房主 IPv4 字段；本次抓包中的回复源 IP 是观测到的房主地址通道。字节扫描本身不能证明客户端“只能”使用源地址，也不外推到其他构建或配置。正式裁定见 `REV-013-REVIEW.md`。

> 方法学声明：在 UTF-8 文本区域里"任意 4 字节都像一个 IPv4"，因此二进制定宽扫描没有判别力，本报告只采用 dotted-quad 形态的文本扫描。此前 v1 报的 27 个 `10.32.32.32` 是 JSON 缩进（`0x0A 0x20 0x20 0x20`）被误读，已弃用。

### 对产品设计（M0-B）的含义

| 设计 | 影响 |
|---|---|
| Fake-IP 改写 | 可先实验验证仅映射 `sendto` 目标与回复源地址、保持公告载荷不变的方案；端到端地址语义仍未验证 |
| 单播中继 | 转发时应测试并记录客户端看到的源地址语义；当前样本不足以要求特定伪造/NAT 实现 |
| 载荷级处理 | 当前样本未发现房主地址/端口字段；其他构建与配置未验证 |

---

## §5 时间与规模（同一抓包时钟，来自 pcapng）

| 指标 | 值 |
|---|---|
| 请求 → 首个回复 | **T_response = 10.003 ms** |
| 22 页突发跨度 | **1.820 ms** |
| 单机自收（同进程） | 首包 +47.3 ms，末包 +94.9 ms（约 47 ms 发完 22 页） |
| 公告总长 | **20 636 B**（22 × 938），线上 22 × 1104 = 24 288 B |
| 每页副本数 | 4（pktmon 4 个捕获点）；内容 sha256 序列三轮一致 |

---

## §6 证据清单（`M0A\captures\E2A-H4-reply-20261113\`）

| 文件 | 大小 | SHA256 前 16 |
|---|---|---|
| `reply-set\reply-01.bin` … `reply-22.bin` | 各 1104 B | 见 `replies.csv` |
| `reply-set\room-advert-content.bin` | 20 636 B | `C24148769D28D623…` |
| `reply-set\json\EnabledMods.json` | 17 984 B | `FFD47DD2D40E5FA8…` |
| `reply-set\json\GameSpeedName.json` | 488 B | `07B73716D2FF5A6B…` |
| `reply-set\json\MapDisplayName.json` | 482 B | `C59FCEDEFB8C84EF…` |
| `reply-set\json\RuleSetName.json` | 718 B | `2E2406396153EC5C…` |
| `room-advert-analysis-v2.txt` | 3 440 B | `60BC8D3EB1A4C34C…` |
| `reply-shape-1req.txt` | 12 532 B | `DA04E1B7259AAE5E…` |
| `selfhost-full-payload.txt` | 17 624 B | `39B7C133434C58E2…` |
| `handshake-identities.csv` | 8 541 B | `0755AAB6ECDCF723…` |
| `analyzer-output.txt` | 3 222 B | `04341ED000C90A30…` |

**脚本**

| 脚本 | 大小 | SHA256 |
|---|---|---|
| `scripts\analyze-room-advert.ps1`（v2） | 9 590 B | `D94A79F7A0D109C50BB5A6792DE4B5271F6FE6B673D6340611EDB1D37E926DEE` |
| `scripts\analyze-discovery-handshake.ps1` | 13 187 B | `A01EEFB69AFB96A7B6445BF77CD730E920B0A9A12EA3D3F492D91F1B089D99F2` |
| `scripts\probe-capture-replies.ps1` | 5 201 B | — |
| `scripts\probe-reply-shape.ps1` | 3 531 B | — |
| `scripts\pcapng-capture-full.ps1` | 5 155 B | `CE0775C2E6CCDF75CF3EDBC9843E97D694DFF47C3370596D42E87A296C6A8D5B` |

---

## §7 证据等级与仍未做的事

**可以陈述**
- 在本机、本构建（`1.0.12.54 (951533)`）、本房间配置下，一个 4 字节发现请求换来一份 **20 636 B、22 页、每页 1104 B** 的房间公告；
- 公告的页头/记录流/JSON 结构如上，13 条记录、4 个 JSON 全部解析成功；
- 本次已分析载荷未发现房主 IP；本次抓包观察到回复源 IP；
- T_response ≈ 10 ms、突发 ≈ 1.8 ms（同抓包时钟）。

**不可以陈述**
- ❌ 不能说"E2-A 已通过"——本证据是**单机自收**，没有第二台机器参与，E2-A 的双机要求仍未满足；
- ❌ 不能说"字段 8/12/16/20 的含义"——只是本轮常量；
- ❌ 不能说"H4 已通过 Gate A 判据"——H4 问的是"地址来源"，本轮回答了它，但 Gate A 还差 E2-B、E3 与 PC-B 原件；
- ❌ 不能把本报告的 22 页结构当成"协议规范"，它只是**一个构建版本的经验观测**。

**仍未做**
1. 页头字段 8/12/16/20 的语义（需多房间/多地图/多 mod 组合对照）；
2. 不同房间（不同 mod 集、不同地图大小）导致页数变化的规律——本样本 45 个 mod → 22 页；
3. 客户端如何用这 22 页建立房间列表条目（是否有排序/去重/超时）；
4. 双机 E2-A 补正 + E2-B + E3。

---

## §8 修复建议（供后续脚本）

`analyze-room-advert.ps1` v2 已按上述结构重写并验证（`parse_errors=0`，22 页全断言通过，4/4 JSON 有效）。若后续还有"多个 1104 B 包"的抓包，**直接用它**，不要再用 v1 的 940 切分。

`analyze-discovery-handshake.ps1` 的 REP 分类已加"目的地必须命中实际 REQ 源端口"约束，可避免 SSDP 误判。
