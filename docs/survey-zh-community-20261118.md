# 中文社区游戏联机技术调研报告（CivLink 项目 M0A 阶段）

- 调研人：M0A 调研子代理
- 日期：2026-11-18
- 范围：中文社区（B站/知乎/CSDN/博客/少数派/百度百科/厂商官网等）关于游戏局域网联机、NAT 穿透、文明6 联机、Mesh VPN/P2P 组网的中文方案与经验
- 目标：为 CivLink（文明6 局域网联机助手，开源产品化）收集中文社区可借鉴的工程经验、竞品格局与社区痛点
- 说明：本报告所有来源均为中文社区公开网页/视频/官方文档，检索时间 2026-11-18；"实测"类结论均为来源作者个人经验或厂商宣传口径，未经本报告复现验证（见"边界纪律"章）。

---

## 一、调研概览与方法

检索手段：web_search 多关键词查询（Bing/Exa/Tavily 等引擎）、B站视频页直抓（简介含关键信息）、博客页直抓、research 工具摘取反爬页面 snippet 与正文。

反爬处理经验（供后续调研复用）：
- zhihu 专栏/问答直抓一律 403，Bing 摘要 + research 工具可摘到部分正文与关键句；`site:` 限定对 zhihu/v2ex/nga 效果差（返回泛结果），普通中文关键词效果更好。
- CSDN 博客直抓 403，research 可摘到关键句（如文明6 联机原理句即由此获得）。
- B站视频页可直抓（简介即核心信息）；B站专栏 opus 页偶发验证码反爬（本次 opus/993912143071936516 返回验证码页，其关键句已由 research snippet 获得）。
- 厂商官网（EasyTier、EasyN2N/bugxia、KatoLan、蒲公英、贝锐）可直抓全文。

---

## 二、方向一：游戏局域网联机/局域网游戏互通的软件方案与实测

中文社区主流的"异地局域网联机"方案谱系（按社区声量排序）：

### 1. 对战平台类（传统模式，正在衰退）
- **游侠对战平台**：B站 UP 主 CyberRacer_KAI 视频「游侠收费了，隧道太麻烦，还有哪些免费软件可以游戏联机？」(2023-01-15，17.5 万播放) 明确：**游侠对战平台已于 2023 年起收费**；视频结论「在国内，游侠对战平台依旧是不可替代的，这是国内连接质量最高的平台」——即收费后仍是社区公认的国内连接质量天花板。
  - https://www.bilibili.com/video/BV18D4y1W7dS
- **浩方对战平台**：2026-03-07 宣布正式关闭（今日头条资讯），陪伴中国玩家 24 年停运。传统"游戏大厅中转"模式落幕的重要市场信号。
  - https://www.toutiao.com/article/7614183010455257640
- **GameRanger / vlan(ipve.com)**：同视频评价——GameRanger 适合国际联机但延迟高、有几率不成功；vlan 连上后延迟低但有几率不成功。均为"连上很爽、连不上抓狂"的典型。

### 2. 虚拟局域网/VPN 组网工具类（当前主力）
- **Radmin LAN**（商业免费）：B站 27 万播放教程「电脑联机软件Radmin LAN简易教程」(Space-5, 2024-04-11)。简单上手、只能电脑；UP 合集另含 natpierce(皎月连) 不限人数不限速免费联机（支持手机电脑互连）、Gamelan 联机助手、FRP+Tshock 泰拉服务器等。
  - https://www.bilibili.com/video/BV1RA4m1F7TW
- **KatoLan（好朋友联机工具）**（lan.katomegumi.net，2026 仍在更新）：支持 P2P 与中转的免费虚拟局域网游戏联机工具；无需注册、填房间名即加入；P2P 自动打洞；支持自建服务器节点；官方宣传"延迟 40ms、丢包 0%、综合提升 70%"；10K+ 活跃用户；客户端仅 12MB（v1.4.0）。B站有 2026 年小白向推荐视频（BV1STwszrE4Y），CSDN 有官方教程（m0_71727150）。官方 B站「樱桃花下的小猫」。
  - https://lan.katomegumi.net / https://www.bilibili.com/video/BV1STwszrE4Y / https://blog.csdn.net/m0_71727150/article/details/146715712
- **EasyN2N（小黄鸭）**（bugxia.com/357.html，v3.3）：虚拟局域网组建工具，专为远程联机游戏设计；集成 PING 与 NAT 类型检测；内置免费服务器；v3.3 新增手动指定虚拟网卡、跃点数修改、虚拟IP合法性校验开关；仅支持 Win11/Win10/Win Server 2012 R2；正版/学习版（盗版）都能联机；Windows Defender 可能误报（易受杀软干扰）。B站官方教程视频 11.5 万播放（BV1Kh4y1o7A1）。
  - https://bugxia.com/357.html / https://www.bilibili.com/video/BV1Kh4y1o7A1
- **Hamachi（蛤蟆吃）**：虚拟局域网开拓者，Alex Pankratov 2004 年打造，基于 P2P 技术的虚拟局域网软件，UDP/TCP 穿透防火墙、NAT、VPN 限制（百度百科）。中文社区历史教程极多，但近年因免费版功能收缩、不稳定，社区声量已让位于国内工具。
  - https://baike.baidu.com/item/hamachi/389794 / https://langame.cn/articles/hamachi-the-pioneer-of-virtual-lan/
- **蒲公英（贝锐）游戏版**：贝锐官方「文明6能联机吗？异地组网开黑，蒲公英游戏版一键搞定」——输入房间号加入虚拟局域网即可联机。知乎问答（368384542）中贴吧方法即"下载蒲公英路由器/软件组网，很稳不掉线"。免费版限制（官方 2026 年 FAQ）：每个账号 3 个组网免费授权，转发带宽 2Mbps/节点，P2P 直连时不限速；蒲公英优先尝试 P2P 打洞直连，失败回退中转服务器。
  - https://pgy.oray.com/news/55131.html / https://pgy.oray.com/news/57168.html / https://pgy.oray.com/news/56417.html / https://www.zhihu.com/question/368384542

### 3. 串流/远程控制类（覆盖联机的旁路方案）
- **Parsec**：低延迟跨平台远程控制软件，建立 P2P 连接，同路由器 WiFi 下低延迟（知乎专栏）。中文教程多为"傻瓜式安装注册"（cnblogs 2025-06-30 全文）。严格说是远程桌面串流而非虚拟网卡组网，但社区常把它列为联机手段。
  - https://zhuanlan.zhihu.com/p/557637085 / https://www.cnblogs.com/legendundery/p/18956985

### 4. 公网直连/单播替代广播类（本项目同源路线）
- **injciv6（我是xa / xaxys）**：见方向三详述——这是 CivLink 上游作者 xaxys 的中文社区发布，是"hook UDP + 公网单播替代广播发现"路线的社区验证者。
- **IPv6 公网直连**：B站「通过IPV6实现公网联机 适用所有游戏」(BV1UY4y1E7Np) 等视频——有公网 IPv6 条件时直接公网联机。

---

## 三、方向二：NAT 穿透/内网穿透在游戏联机中的实践

### 1. 国内 NAT 现实：对称 NAT 打洞失败是普遍痛点
- CSDN 技术盘点文（2026-09-04，已抓全文）核心结论：
  - **ZeroTier**：国内复杂 NAT（对称型）UDP 打洞成功率不稳定，不配 Moon 跨运营商速度堪忧；官方 moon 中转服务器在国外，国内客户端延迟大甚至访问不了（与博客 ubirdy 实测一致，见方向四）。
  - **Tailscale**：依赖 Google/Amazon 协调服务器，国内无加速节点，NAT 遍历易受防火墙干扰。
  - **FRP**：支持 STUN 打洞尝试 P2P 直连、失败回退服务器中转；支持 TCP/UDP/HTTP/HTTPS/KCP；是自建中转的主流选型。
  - **花生壳**：长连接反向代理 + 智能 BGP 链路调度，RSA+AES，国内平均延迟 <30ms，UDP 仅限特定场景（游戏联机不适合）。
  - **Ngrok**：免费版 40 并发限制、海外节点 150ms+ 丢包，国内不适用。
  - https://www.csdn.net/article/2026-09-04/164367623
- NAT 类型检测工具：17nas.com/nat-test.php（多地区 STUN 节点评估端口映射稳定性）、natchecker.com/zh（RFC 3489 分类）——社区用它们判断自家 NAT 是否支持 P2P 直连。

### 2. 社区普遍采用的策略："先中转、再打洞" + 兜底
- **N2N 底层逻辑**（bugxia.com/n2n_version_intro，已抓全文）：先走 supernode 中转，过程中尝试打洞直连，直连失败继续中转；附加参数 -S2 强制中转。这就是中文社区事实上的标准兜底模型。
  - N2N v2/v3 为当前常用版（github.com/ntop/n2n），v1/v2s 已淘汰；小组名 = 虚拟网身份牌；服务端默认分配 IP 段 10.128.255.0-10.255.255.0/24 约 3 万+ IP；lucktu/n2n 收集全平台编译版；hin2n（switch-iot）安卓版免 root 支持全版本协议。
  - https://bugxia.com/n2n_version_intro
- **樱花映射（NATfrp）+ N2N 组合**（B站 7.8 万播放，T-home-fox, 2024-02-06）：免费穿透 + N2N 组网；实测经验：延迟速度与节点有关；关闭防火墙连接更快；客户端连接慢时建议先启动客户端再启动服务端。
  - https://www.bilibili.com/video/BV1R7421N7Ph / https://www.natfrp.com
- **蒲公英模式**（官方）：优先 P2P 直连、失败走中转，免费中转 2Mbps/节点——同为"先打洞后兜底"产品化。

### 3. 免费穿透服务在游戏联机中的局限
- 国内免费内网穿透服务多面向 Web/远程桌面场景，UDP 支持与带宽受限；游戏联机社区主流做法是自建 FRP/rathole 中转（有云服务器时）或直接上虚拟组网工具，而非依赖免费穿透端口转发。

---

## 四、方向三：文明6 联机中文讨论（本项目直接相关）

### 1. 文明6 联机机制（社区确认的工程事实）
- **原理**：文明6 联机由主机在局域网建立房间，其他主机通过 255.255.255.255 本地广播搜索房间（服务器），检索到即加载房间列表（CSDN「文明6 建立（虚拟）局域网联机踩坑」，research 摘得）。
  - https://blog.csdn.net/qq_40151332/article/details/128023224
- **网络特性**：文明6 对网络波动敏感、对带宽延迟不敏感（知乎「文明6联机 方法与实践」摘要），传统组网即可稳定联机。
  - https://zhuanlan.zhihu.com/p/609271806

### 2. 社区核心痛点：搜不到房间
- 知乎专栏「文明6 局域网 联机 教程：从同房开黑到异地组网，一篇讲透」(2026-09-04)：**"搜不到房间才是真正噩梦"**——搭好 VPN 后广播发现失败是最高频问题。
  - https://zhuanlan.zhihu.com/p/2079144722287929131
- B站专栏「文明6虚拟局域网联机教程（搜不到房间的解决办法）」(opus/993912143071936516)：搭好 VPN 后启动游戏**仍可能搜不到房间**，需额外处理。
  - https://www.bilibili.com/opus/993912143071936516
- **根因分析（关键来源，已抓全文）**：xchens「如何异地组网来玩局域网游戏 - 文明6」(2021-10-24)：
  - 文明6 服务发现依赖发往 **255.255.255.255 的 UDP 广播包**；WireGuard 等 VPN 的虚拟网卡导致广播包路由到物理网卡，对端收不到 → 搜不到房间（"关掉网卡，我连不上你；开启网卡，我找不到你"）。
  - 两条解决路线：
    - ①「路线纠正」：修改路由表让 255.255.255.255 广播包走虚拟网卡（作者认为易触发未知 bug，不推荐）；
    - ②「明确目标」：**抓包重发**——用 gopacket/pcap 抓 UDP 广播包，把目的地址改成对端 IP 直接单播发出，来源端口保持游戏进程端口；对端收到发现请求后会主动回房间信息，联机成立。作者给出完整 Go 源码（BPF "udp"，过滤 DNS 53/mDNS 5353）。
  - 作者评论"抓包重发后为什么能成功：UDP 无连接，可手动构造来源端口与目的地址，包自然能被投递"。
  - https://xchens.cn/posts/1d434264/
- 结论：**"广播→单播改写"路线在中文社区 2021 年已被独立验证（抓包重发），2024 年 injciv6 以 hook 形式产品化**——与本项目 CivLink 思路同源。

### 3. 文明6 异地联机社区主流解法排序
按社区声量：蒲公英（贴吧方法，稳）→ ZeroTier/EasyN2N/N2N（免费组网）→ injciv6（hook 单播，零虚拟网卡）→ WireGuard 自建 + 路由/抓包处理 → 游侠等平台。

### 4. injciv6（xaxys/我是xa）的中文社区发声（本项目上游）
- **BV1qV411X7FP**「文明6自研全新联机工具，公网上IPv6 UDP单播稳定联机，不再需要n2n虚拟组网」(我是xa, 2024-01-18, **7.7 万播放**)。简介原文："文明6联机-基于IP的游戏发现 (IPv4/IPv6) 公网 UDP 单播联机，不再需要虚拟局域网！利用 **Hook 技术，拦截游戏对 UDP 的发送、接收等操作**，实现基于 IP 的游戏发现和联机。" Github：github.com/xaxys/injciv6。
  - https://www.bilibili.com/video/BV1qV411X7FP
- **BV1R6421g76H**「公网联机工具 injciv6 上新了，轻松 IPv6 联机」(我是xa, 2024-02-01, 2.6 万播放)：0.3.x 版本上新，**新增 GUI 界面**；QQ 群 954084231；压缩包内附 Readme.txt。
  - https://www.bilibili.com/video/BV1R6421g76H
- 意义：本项目（CivLink）原始出处 xaxys 在中文社区有官方视频、播放量可观、用户经 QQ 群互动；其"hook UDP + 单播替代广播"的机制方向在中文社区有真实用户验证。

---

## 五、方向四：Mesh VPN/P2P 中文实践

- **ZeroTier 中文实测**（cnblogs ubirdy, 2025-02-18，已抓全文）：官方 moon 中转服务器在国外，**国内客户端延迟大甚至访问不了**——需自建 moon（要求静态公网 IP）；给出 zerotier-cli join/orbit 完整命令流程；免费。
  - https://www.cnblogs.com/ubirdy/p/18721780
- **Tailscale 中文教程**（知乎 2025-01-12）：基于 WireGuard 协议零配置 VPN，无需公网 IP 快速实现内网穿透；但国内无加速节点、依赖海外协调服务器（CSDN 盘点文的负面结论）。
  - https://zhuanlan.zhihu.com/p/17920510031
- **EasyTier（中文原生开源，重点竞品）**（easytier.cn，已抓全文）：
  - Rust+Tokio，**Apache License 2.0**；去中心化（无客户端/服务端区分）；跨平台 Win/Mac/Linux/FreeBSD/Android、X86/ARM/MIPS、ESP 嵌入式；
  - 支持 UDP/IPv6 穿透、**可打通 NAT4-NAT4**（社区宣传卖点）；子网代理；智能路由延迟优先；支持 TCP/UDP/WS/WSS/WG/QUIC/FakeTCP 协议；**KCP/QUIC 代理抗 UDP 丢包**（高丢包环境优化延迟带宽）；
  - B站大量推荐视频：BV1bUXnYLEvJ（"开源免费比 zerotier/tailscale/蒲公英更好用的组网软件 easytier"，15.1 万播放）、BV1fHuEzpENp（"Easytier--最简单的虚拟局域网游戏联机软件"）、BV1sZ6RBYE5P（以撒联机）。
  - https://www.easytier.cn / https://www.bilibili.com/video/BV1bUXnYLEvJ
- **ZeroTier vs Tailscale 评测**（B站 31.7 万播放，Rrex_here, 2022-04-10）：免费/靠谱/低延迟虚拟局域网组网工具推荐。
  - https://www.bilibili.com/video/BV1HA4y1978W
- **通用 Steam 联机工具**（B站 70 万播放「实现用 Steam 联机所有游戏 通用型联机工具」BV1p92HBUEST）：面向"所有游戏"的通用方案存在社区需求，但通用性往往伴随配置复杂度。

---

## 六、中文社区方案对比表

| 方案 | 类型 | License/授权 | 免费性 | 稳定性实测（社区口碑，非本报告复现） | 来源 |
|---|---|---|---|---|---|
| injciv6 | Hook UDP 单播替代广播发现 | GitHub 无 License（xaxys/injciv6） | 免费 | 7.7 万播放官方视频；IPv6/IPv4 公网单播；零虚拟网卡，无"搜不到房间"问题 | BV1qV411X7FP、BV1R6421g76H |
| ZeroTier | P2P Mesh VPN | MPL-2.0 | 免费 | 国内对称 NAT 打洞成功率不稳定；官方 moon 在海外延迟大，需自建 moon（静态公网 IP） | cnblogs.com/ubirdy/p/18721780、CSDN 164367623、BV1HA4y1978W |
| Tailscale | WireGuard Mesh VPN | BSD-3-Clause | 免费 | 国内无加速节点，依赖 Google/Amazon 协调服务器，NAT 遍历易受防火墙干扰 | zhuanlan.zhihu.com/p/17920510031、CSDN 164367623 |
| EasyTier | 去中心化 Mesh（Rust） | Apache-2.0 | 免费 | 宣传可打通 NAT4-NAT4；KCP/QUIC 抗丢包；中文原生社区活跃（B站 15.1 万播放推荐） | easytier.cn、BV1bUXnYLEvJ |
| N2N / EasyN2N | 虚拟局域网（supernode 中转+打洞） | GPL-3.0（ntop/n2n）；EasyN2N 免费工具 | 免费（内置免费服务器） | 先中转后打洞模型成熟；v3.3 支持手动指定虚拟网卡/跃点数；Defender 可能误报；仅 Win10/11 | bugxia.com/357.html、n2n_version_intro、BV1Kh4y1o7A1 |
| Radmin LAN | 虚拟局域网 | 商业免费（非开源） | 免费 | B站 27 万播放教程；简单上手；仅电脑端 | BV1RA4m1F7TW |
| KatoLan | P2P+中转虚拟局域网 | 免费闭源 | 免费 | 宣传延迟 40ms/丢包 0%；10K+ 活跃用户；无需注册三步即用；2026 年仍有推荐视频 | lan.katomegumi.net、BV1STwszrE4Y、CSDN 146715712 |
| 蒲公英（贝锐） | SD-WAN 虚拟组网 | 商业（免费档） | 免费 3 授权/账号；转发 2Mbps/节点，P2P 不限速 | 贴吧/知乎口碑"很稳不掉线"；P2P 失败自动中转 | pgy.oray.com/news/55131、57168、56417；zhihu.com/question/368384542 |
| Parsec | 串流/远程桌面 | 免费个人版 | 免费 | P2P 低延迟；同网 WiFi 最佳；非真正虚拟网卡 | zhuanlan.zhihu.com/p/557637085、cnblogs.com/legendundery/p/18956985 |
| Hamachi | P2P 虚拟局域网（元老） | 商业免费（闭源） | 免费（功能收缩） | 历史地位高；近年不稳定、社区声量下降 | baike.baidu.com/item/hamachi/389794、langame.cn |
| 游侠对战平台 | 对战平台/大厅 | 商业 | **2023 起收费** | 社区公认国内连接质量最高；收费后仍有"不可替代"口碑 | BV18D4y1W7dS |
| 浩方对战平台 | 对战平台/大厅 | 商业 | 免费（历史） | **2026 年正式关闭**，24 年运营落幕 | toutiao.com/article/7614183010455257640 |
| 樱花映射+N2N | 免费穿透+组网 | 免费服务 | 免费 | 延迟随节点；关防火墙更快；先启客户端再启服务端更稳 | BV1R7421N7Ph、natfrp.com |
| FRP | 自建中转（STUN 打洞+回退） | Apache-2.0 | 免费（自建） | 支持 TCP/UDP/KCP；有云服务器玩家的首选中转 | CSDN 164367623、BV1RA4m1F7TW |
| WireGuard+抓包重发（自研） | 自建 VPN + UDP 单播改写 | 开源/自研 | 免费（自建） | xchens 2021 实测成功：抓包重发后联机成立；改路由表方案被弃（怕未知 bug） | xchens.cn/posts/1d434264/ |

注：License 列以官方仓库/官网标注为准；"免费性"为中文社区普遍认知；"稳定性实测"均为来源作者个人经验或厂商宣传，见边界纪律。

---

## 七、对 CivLink 的可借鉴点

CivLink 现状（父项目背景）：agent 绑定 62900-62999 端口模拟房主 + `--reserve-62900` + 即将实现的 civlink_client.dll 定向网卡；上游为 xaxys/injciv6（hook UDP 思路）。以下按可操作性排序：

1. **"广播→单播改写"是中文社区验证过的成熟方向，且有两代先例**：
   - xchens 2021 抓包重发（Go/gopacket，改目的地址+保留来源端口）与 xaxys 2024 hook UDP（injciv6）独立验证了同一条路线；CivLink 的 agent 绑 62900-62999 模拟房主本质就是"把游戏的服务发现流量定向到本地 agent 端口"，属于同一家族。可作为对外文档的机制合法性论据（但见边界纪律：论据≠双人验证）。
2. **"搜不到房间"是社区第一痛点，产品话术应直击它**：
   - 知乎/B站/CSDN 三处独立提及"搭好 VPN 仍搜不到房间"；根因是虚拟网卡干扰 255.255.255.255 广播路由。CivLink 的 civlink_client.dll 定向网卡方案直接对症（把 Civ6 UDP 流量定向到指定网卡/端口，规避虚拟网卡路由干扰）——对标 EasyN2N v3.3 已产品化的"手动指定虚拟网卡、跃点数修改"功能，说明该交互有真实需求。
3. **对称 NAT 打洞失败是现实，必须设计中转兜底**：
   - 中文社区普遍结论：ZeroTier/Tailscale 在国内对称 NAT 下不可靠；N2N 的"先中转后打洞、失败持续中转"（-S2 强制中转）是标准答案；EasyTier 的 NAT4-NAT4 打通与 KCP/QUIC 抗丢包是加分项。CivLink 若提供自建 relay/节点选项，可对标 N2N 与 KatoLan 的"支持自建服务器节点"；若走公共节点，需明确带宽/节点分布承诺。
4. **GUI 与易用性是免费工具的生命线**：
   - injciv6 0.3.x 才补上 GUI（作者在 B站上新视频中重点宣传）；KatoLan"无需注册、填房间名即加入、12MB 客户端"是社区公认的小白友好标杆；EasyN2N 内置 NAT 类型检测/PING 降低排查门槛。CivLink 开源+GUI+企业级质量的定位，应在"三步即用"与"自带诊断（NAT 类型检测、延迟/PING、日志导出）"上对齐社区预期。
5. **国内节点缺失是 ZeroTier/Tailscale 的公认短板，也是差异化机会**：
   - 中文社区反复出现"官方 moon 在国外延迟大/访问不了，需自建 moon"；CivLink 若内置国内 relay 节点或提供一键自建节点（对标蒲公英 2Mbps 免费档、N2N 免费服务器），即直接解决社区高频抱怨。
6. **商业格局印证产品空档**：
   - 游侠 2023 起收费（仍是质量天花板）、浩方 2026 停运；免费主力是 Radmin LAN/KatoLan/EasyN2N（闭源/半开源）；**开源+免费+GUI 的文明6 专用联机工具在中文社区没有强竞争者**（injciv6 无 License 且无产品化运营）。CivLink 开源化+企业级质量有明确市场空档。
7. **文档与话术可直接引用的社区证据**：
   - 文明6 联机机制（255.255.255.255 广播、对波动敏感）有 CSDN/知乎多处独立描述；injciv6 官方视频简介是"hook UDP 拦截收发"的最权威中文表述（作者本人）。

---

## 八、边界纪律

1. **机械证据 ≠ 双人验证**：本报告引用的所有"成功联机/稳定不掉线"结论，均来自来源作者的抓包、路由分析等机械证据或个人经验描述（如 xchens 的抓包重发源码、蒲公英官方 FAQ），**没有任何来源提供"两名真实玩家异地全程实测"的正式验证**。CivLink 项目不得以本报告或任何来源的机械证据，宣称等价于双人实测验证；对外文档、验收标准中的"验证"表述，必须以 CivLink 自己的真实双人联机测试为依据。
2. **厂商宣传数字不可采信为基准**：KatoLan"40ms/丢包0%"、蒲公英"<30ms"、EasyTier"NAT4-NAT4 可打通"均为营销口径或特定环境结果，不能作为产品性能基线。
3. **时效性风险**：游侠收费、浩方关闭、Hamachi 衰退等结论有明确时间点（2023-2026），引用时需注明时间；免费服务的免费档规则（如蒲公英 3 授权/2Mbps）可能随时变更。
4. **反爬限制声明**：zhihu/CSDN 部分页面仅获得摘要或关键句（已在来源条目中注明），未获全文；B站专栏一篇仅获 snippet。引用时以本报告标注的获取程度为准。
5. **本报告是调研输入，不是验收证据**：它服务于 CivLink 的产品定位、文档话术与工程选型；任何涉及"联机成功"的验收结论需回到 F/M 系列的实测文档体系。

---

## 来源清单（31 项，均含 URL）

**文明6 联机讨论**（8）：
1. 知乎专栏「文明6联机 方法与实践」 https://zhuanlan.zhihu.com/p/609271806
2. 知乎专栏「文明6 局域网 联机 教程：从同房开黑到异地组网，一篇讲透」 https://zhuanlan.zhihu.com/p/2079144722287929131
3. 知乎问答「请问下大伙们怎么稳定的联机文明六啊」 https://www.zhihu.com/question/368384542
4. CSDN「文明6 建立（虚拟）局域网联机踩坑」 https://blog.csdn.net/qq_40151332/article/details/128023224
5. CSDN「文明6 联机教程2025最简单稳定 保姆级」（KatoLan 官方） https://blog.csdn.net/m0_71727150/article/details/146715712
6. xchens「如何异地组网来玩局域网游戏 - 文明6」（抓包重发全文+源码） https://xchens.cn/posts/1d434264/
7. B站专栏「文明6虚拟局域网联机教程（搜不到房间的解决办法）」 https://www.bilibili.com/opus/993912143071936516
8. B站 injciv6 官方视频×2 https://www.bilibili.com/video/BV1qV411X7FP 、 https://www.bilibili.com/video/BV1R6421g76H

**B站联机方案视频**（7）：
9. EasyN2N 官方教程 https://www.bilibili.com/video/BV1Kh4y1o7A1
10. N2N-樱花映射 免费联机教程 https://www.bilibili.com/video/BV1R7421N7Ph
11. ZeroTier/Tailscale 组网评测（31.7万） https://www.bilibili.com/video/BV1HA4y1978W
12. Radmin LAN 教程（27万） https://www.bilibili.com/video/BV1RA4m1F7TW
13. 游侠收费了，还有哪些免费软件（17.5万） https://www.bilibili.com/video/BV18D4y1W7dS
14. EasyTier 推荐（15.1万）/EasyTier 游戏联机/以撒联机 https://www.bilibili.com/video/BV1bUXnYLEvJ 、 https://www.bilibili.com/video/BV1fHuEzpENp 、 https://www.bilibili.com/video/BV1sZ6RBYE5P
15. KatoLan 2026 推荐/通用 Steam 联机工具 https://www.bilibili.com/video/BV1STwszrE4Y 、 https://www.bilibili.com/video/BV1p92HBUEST

**虚拟局域网/组网官方文档**（7）：
16. KatoLan 官网 https://lan.katomegumi.net
17. EasyTier 中文官网 https://www.easytier.cn
18. EasyN2N v3.3 https://bugxia.com/357.html
19. N2N 版本选择介绍 https://bugxia.com/n2n_version_intro
20. ZeroTier 异地组网中文实测 https://www.cnblogs.com/ubirdy/p/18721780
21. Parsec 中文教程 https://www.cnblogs.com/legendundery/p/18956985
22. Tailscale 安装指南 https://zhuanlan.zhihu.com/p/17920510031

**NAT/内网穿透/厂商**（5）：
23. CSDN 主流内网穿透方案技术盘点（FRP/ZeroTier/Ngrok/花生壳） https://www.csdn.net/article/2026-09-04/164367623
24. 蒲公英「文明6能联机吗」 https://pgy.oray.com/news/55131.html
25. 蒲公英免费版限制 FAQ https://pgy.oray.com/news/57168.html
26. 蒲公英 P2P vs 转发带宽 https://pgy.oray.com/news/56417.html
27. NAT 类型检测工具 https://17nas.com/nat-test.php 、 https://natchecker.com/zh

**市场/历史**（4）：
28. 浩方对战平台关闭 https://www.toutiao.com/article/7614183010455257640
29. Hamachi 百度百科 https://baike.baidu.com/item/hamachi/389794
30. Hamachi 编年史 https://langame.cn/articles/hamachi-the-pioneer-of-virtual-lan/
31. Parsec 知乎介绍 https://zhuanlan.zhihu.com/p/557637085
