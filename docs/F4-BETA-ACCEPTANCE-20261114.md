# F4 发布候选 · 单机模拟房主验收（F4-BETA）

状态：**PASS（9/9 断言）**，采信证据 `M0A\captures\F4-beta-20261114-174214`，2026-11-14。

> 本验收是 REV-016 §F4 的**单机模拟对端/发现助手测试版**验收：一台真实 Steam Civ6 客户端 + 本机模拟房主（Agent --simulate）完成发现/公告/数据面观测重复回归。**NOT 双人真实联机**，不得据此勾掉 E2-A/E2-B/E3，不移动 Gate A/B。

## 1 目的与边界

- 目的：验证发布包（`dist\civlink-beta-20261114\`，中立目录副本 `C:\Users\dd\Desktop\civlink-f4\`）在真实游戏进程上的端到端行为：注入 → Hook 捕获发现广播 → Agent 模拟房主应答 22 页公告 → 客户端列表可见模拟房间；数据面（62056 join 尝试）被观测但不修改；干净收尾（B2 审计运行模式 DLL 保持映射）。
- 边界（如实声明，全部证据仅为 F4 单机模拟验收）：
  - 模拟房主通过 127.0.0.1 回环应答，不涉及任何远端 Peer、Relay RTT、跨网路径；
  - 数据面仅"观测"（9 个 62056 出向帧被记录），Agent 不 bind 62056、不回复（D4 reply sent=0）；
  - 不证明：双机发现/加入/对局、H2/R1 绑定语义、加密身份（Noise）、长稳、跨网；
  - Gate A 未批准、正式 M0-B/Gate B 冻结（README v1.19 §3D 登记）。

## 2 运行环境与版本

| 项 | 值 |
|---|---|
| 游戏进程 | pid=48664，`CivilizationVI_DX12.exe`（E:\SteamLibrary\…\Win64Steam\） |
| Agent | civlink-agent 0.3.0（382,464B，sha256 93F17516…） |
| Relay | civlink-relay 0.1.0（262,144B，sha256 9E323F81…） |
| ctl | civlink_ctl v0.2.0-f2（173,056B，sha256 23923DFB…） |
| hook dll | civlink_hook.dll（119,808B，sha256 9424FC25…） |
| 编排脚本 | run-f4-beta.ps1（civlink-f4 副本，14,079B，sha256 F7B56439…，UTF-8 BOM） |
| 模拟房间 | CivLink-Beta-Room-2222（22B，偏移 24..46 匿名化） |
| 窗口 | 240s（AutoStopSeconds），t=42s/44s/46s 三次刷新各 100 帧 |

## 3 断言结果（9/9 PASS）

| # | 断言 | 实测 |
|---|---|---|
| 1 | hook 至少捕获一次发现发送 | delta=300 |
| 2 | hook.sent delta + observed delta == agent.processed | 300 + 9 == 309 |
| 3 | agent 至少收到一帧 | received=309 |
| 4 | 模拟房主看到请求并回复 | seen=300 replied=3 |
| 5 | 页面数 == 22 × 回复 socket 数 | 66 == 22×3 |
| 6 | hook 发送失败为 0 | sendFail=0 |
| 7 | shutdown 退出码 ∈ {0,1,2} | exit=0（clean drain） |
| 8 | info：数据面观测 9（join 尝试的 62056 帧） | datapath observed=9 |
| 9 | 发现目标全部 ∈ 62900..62999（62056=数据面 join 帧） | frames=309 discovery=300 datapath62056=9 |

## 4 agent summary 关键值（session 0xbea5e077da87）

- run time 09:46:20.743 / listen 127.0.0.1:34718 245.0s / datagrams 309 / bytes 14250
- received frames 309（processed 309, rejected 0），reconciliation ==
- frames=309，first_seq=1 last_seq=309，seq gaps=0 missing=0 duplicates=0 out_of_order=0
- discovery_magic=300，other_payload=9，via_wsasendto=9，limited_bcast=300，discovery_flag=300
- logical sockets=4；dst ports=101（min 62056，max 62999，in 62900..62999: 100）
- src endpoints：0.0.0.0:50600×99、0.0.0.0:59851×99、0.0.0.0:59852×99、0.0.0.0:62056×9
- sim 段：requests seen=300 / replied sockets=3 / pages sent=66（== replied×22）/ send fail=0 / no endpoint=3 / max reached=0 / bind fail=0
- datapath 段：frames seen=9 / frames on 62056=9 / reply sent=0（D4）/ reply skipped no_endpoint=0 not_local=9 / send fail=0 / reply bytes=0

## 5 counters-after 关键值

- running=0 / shutdown=1（in-flight=0）/ init error=0
- sent=300 / send fail=0 / reject oversize=0 / sent notify=0 / ignored=0
- scatter-gather=9 / sock overflow=0 / src unknown=3 / state queries=3
- observed frames=9 / raw sendto=300 / raw wsasendto=9 / raw bind=1 / raw recvfrom=66
- bind 62056=1 / wsarecv pending=0 / cvlh2 try=309 / cvlh2 ok=309 / cvlh2 fail=0 / channel down=0
- accounted=300（sent+sendFail+rejectOversize）
- shutdown.txt：`CivLinkShutdown returned 0 (clean drain)`、module LEFT MAPPED until target exit

## 6 证据文件身份（`M0A\captures\F4-beta-20261114-174214`，39 文件）

| 文件 | 字节 | SHA-256 |
|---|---|---|
| summary.txt | 2,986 | 4AE128563F3AF73840A00D87A7D39469F46030E45244FBE2E1CB942958A4E088 |
| frame-log.txt | 44,217 | 8F5671D23CCE358EEF2E9C89EE71EBB337A7D3C580D1F2DD59603F129861BD4A |
| counters-after.txt | 970 | 6FFCA304BD30D511C056B747D51C7F6C9FD0EAA65941205919A7017858AE0FD5 |
| counters-before.txt | 943 | 5DD78B43B335B5DA0F1962147BE1D9B7423B60FFC8F9CFA01511F81D6C70E075 |
| inject.txt | 940 | 0D8E415DBB3E2A8EE9DAF3B4DC6DCBE9FA9FD72071975348CD272E2DC8491AFA |
| shutdown.txt | 816 | FEFEC900FA4E87C85046348B5EF21B3E6B4F5E5CD26B09089CD716F3C19D2E94 |
| path-state-before.txt | 318 | 834441171664245218EB1F14FE851E0CDDBE1AA0DCBC1C19804A9B69FAAE1E6D |
| path-state-after.txt | 321 | 47B8037AD99BCEABEA91193AAE5AD9E24D418E1555B584BC258425B777F40659 |
| relay-summary.txt | 1,520 | BD97077DE36832034C17952F5F119B9F97BE662332234B916F26F3B77D42DC7E |
| relay-log.txt | 86 | C62C5AD174DF20FC6CF4CEFB2E23F786AD90407299B1F831CB07F6C3A2A05BF0 |
| datapath-log.txt | 974 | 4E119A2271A72232FB946DE911204453AF93126385ACD90DB82D73628BD23426 |
| sim-fixture-manifest.txt | 228 | EDD762B6807BB47648B5E6417E51E37143D567FB482B9699AAC056A4DCD5AB17 |
| VERSIONS.txt | 152 | 62CDC2D5A341F04BDF30A896B27D78F460EB6B3720AF222FBEE92FB786021101 |
| sim-page-01..22.bin | 22×1,104 | 38CF9634…/7E2DD92E…/AF9F91C5…/3DBCBC7D…/7D9C575A…/03B8EAAE…/F47577C2…/6D78C4D9…/FE49AB4A…/8519F29C…/53F3A509…/E75EFD69…/FE47B2AF…/EB0EE961…/D35F29EE…/1137F753…/E1025775…/B46BCBF1…/331C52CF…/4C7E1ABB…/BB2EF26F…/A8C79AED… |
| agent-console.txt | 0 | E3B0C442…（空，--quiet） |
| relay-console.txt | 0 | E3B0C442…（空，--quiet） |
| STOP-agent / STOP-relay | 0 | E3B0C442…（空文件哨兵） |

（sim-page 22 项完整哈希见本轮采集记录；表内为前 8 位，审计按全 64 位重算。）

## 7 运行历史

| 时间戳 | 结果 | 说明 |
|---|---|---|
| F4-beta-20261114-173307 | FAIL 4 项 | 脚本缺陷（正则锚旧标签/缺 observed 对账项/62056 误判），产品行为正确，修复 run-f4-beta.ps1 |
| **F4-beta-20261114-174214** | **PASS 9/9** | 采信；脚本修复后重跑（游戏进程已重启，pid 48664） |

首跑 FAIL 四项根因（已修）：sim/datapath 正则与 summary 实际标签不符（`requests seen`/`replied sockets`/`pages sent`/`frames seen`/`reply sent`）；对账缺 observed 项（应为 sent+observed==processed）；dst 断言未区分数据面 62056；脚本无 UTF-8 BOM 致 label 中文乱码（PS 5.1 stdout 重定向按 OEM 代码页输出，信息行不影响判定，本版文档如实说明）。

## 8 证明 5 条 + 不证明 6 条

证明：
1. 真实 Civ6 客户端（DX12）在局域网大厅的发现广播（每次刷新 100 帧）被 Hook 完整捕获并经 CVLH2 通道送抵 Agent（300/300，seq 连续无缺口）；
2. Agent 模拟房主按 D4 预算应答 3 个刷新 socket、每 socket 22 页公告（66 页，页大小 1104B 与 fixture 一致）；
3. 数据面 join 尝试（9 个 dst=62056 的 WSASendTo 帧）被观测且不被修改（Agent 不 bind 62056、D4 reply sent=0）；
4. 干净收尾：CivLinkShutdown 返回 0、计数排空、B2 审计运行模式 DLL 保持映射直到游戏退出；
5. 分层计数对账闭合：hook.sent 300 + observed 9 == agent.processed 309。

不证明：
1. 双机真实发现/加入/对局（无第二台机器）；
2. Relay 路径、直连转发、Fake-IP 绑定语义（H2/R1 留 M0-B）；
3. 加密身份/Noise 隧道；
4. 长稳（240s 单窗口）；
5. 广播出口选路（本机回环 127.0.0.1，未触真实网卡广播路径）；
6. 任何"双人真实联机已通过"表述（本验收仅"模拟对端/发现助手测试版"）。

## 9 关系

- REV-016 §F4（发布候选定义与验收口径）
- README v1.19 §3D（F3 五子项审计闭环 + F4 发布候选 + Gate 登记）
- F2 设计 §5.2（D4 回包策略）、F1 集成（sim 模拟房主模式）
- run-f4-beta.ps1（编排脚本，civlink-f4 副本 UTF-8 BOM）
- 下一步：F4 审计（本文件 + 证据 + 发布包自检）；之后按 REV-016 剩余项（E2-A/E2-B/E3 真实双机仍待验证）。

## 10 修订记录

- 2026-11-14 初版（PASS 9/9，采信 -174214）。
