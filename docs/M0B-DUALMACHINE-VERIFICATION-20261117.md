# M0-B 双机真实验证报告（E2-B 结案）—— 已执行（2026-11-17）

> 状态：**已执行（2026-11-17，审计裁定：有条件通过）**——发现链路段通过、加入/数据面段待验证（M-1）。
> 依据：README v1.31；M0B-DUALMACHINE-RUNBOOK-20261117.md（6561B/76FC2165DE7E）；
> M0B-FINAL-PROGRAM-PLAN-20261117.md v1.1（6269B/737D349F…）；
> 审计报告：M0B-DUALMACHINE-REVIEW.md（17975B/E024B832D1970E99）。

## 1. 目的
按用户 m24348 授权（Gate B/M0-B 冻结解除）完成 M0-B 最终程序的**双机真实联机验证**（E2-B 结案）：
验证 A（房主）/B（加入者）在相同 WLAN 下经 Discovery Adapter（agent 全端口监听+真实广告页应答）
实现「B 稳定发现 A 的房间并可加入、数据面直连」，消除原生 1/100 窗口与广播丢包问题。

## 2. 机制（预期行为，来自步骤 1-6 已证）
- A 机 Civ6 建房：bind 0.0.0.0:62900（游戏占）；agent 绑 62901-62999（bind fail=1 跳过 62900）。
- B 机刷新：广播 100 包 4B magic（源固定临时端口，目标 255.255.255.255:62900..62999）。
- 双路应答：62900 那包 → 游戏 socket 收 → 游戏真实应答；其余 99 包 → agent 收 → agent 应答
  （真实广告页优先，fixture 兜底）。任意一路成功 B 即看到房间。
- B 加入：向「应答源 IP:62056」发 join（广告页无 IP 字段 → 用应答源 IP）→ 落到 A 机 Civ6 62056 socket
  → 数据面直连（Game Data Adapter 转发为备选，直连失败才启用）。

## 3. 执行记录（2026-11-17 实测）
| 步骤 | 操作 | 结果 |
|------|------|------|
| 1 | A 机启动 agent（start-m0b-adapter-a.ps1，--listen-seconds 1800） | **pid 32348**，out-dir `civlink-f1\m0b-adapter-a-20261117-202853`；窗口 2026-11-17 20:28:53→20:58:53（本地；summary「run time 12:58:53.930」=UTC 退出时刻） |
| 2 | A 机注入 hook（civlink_ctl inject, hook 39D6735D） | 历史注入成功（游戏 pid 42180）；本窗口 **datagrams=0（无 hook 帧）**，A 侧注入状态无 civlink_ctl status 归档（M-5 登记） |
| 3 | A 机 Civ6 建局域网房 | **成功**（游戏持 0.0.0.0:62900 + 0.0.0.0:62056；agent bind fail=1 佐证 62900 被游戏占） |
| 4 | B 机 Civ6 局域网刷新 | **B 见真实房名**（用户口述 m26254/m26306，D 级证据）；B 侧 civtrace 未归档（PC-B 离线，环境限制） |
| 5 | B 机加入房间 | **未执行**（PC-B 离线前用户未加入）→ M-1 待补验证 |
| 6 | 数据面观察（B 侧 civtrace 可选助手） | **未验证**（B→A:62056 双向通信无证据）→ M-1 |

## 4. 证据（归档 M0A\captures\M0B-dualmachine-20261117\，4 文件）
- agent-32348-summary.txt（3,248B / 85E72E63C761F6F561FF3D1A4426D8005B4F615443B5E297E497C3FDC34167CE）
- agent-32348-console.txt（0B / E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855，空文件）
- agent-32348-stderr.txt（257B / 4CBDFD55074C01E8AAD35B193B3CF56118BEC10F03D960C7BACD185DC86BEF39，单行：62900 bind 失败 os error 10048 端口回退提示）
- user-observations.txt（1,072B / 76BC00FC4E222849C7085D1EC599AA66AA65A6B8502F7A5630F61FD811C92E1D，含 m26254/m26306/m26472 逐字引述）
- 关键 summary 数值：requests seen=1179 / replied sockets=12 / pages sent=264（12×22）/ replies fixture=12 / replies skipped=1167 / send fail=0 / no endpoint=0 / max reached=0 / bind fail=1 / captured=0 / rejected=0 / duplicates=0 / noise on disc=0 / replies real=0 / active=no
- A 侧现场：`C:\Users\dd\Desktop\civlink-f1\m0b-adapter-a-20261117-202853\`（28 文件，summary/stderr 与归档哈希一致；frame-log 仅表头；lan-page-01..22.bin 各 1104B）

## 5. 判定（RUNBOOK v4 修正口径，审计复核后分段登记）
- **发现链路段：通过**——B 见真实房名（D 级口述 m26254「B依旧可以搜到A创建的真实房间」/m26306「B只能看到一个真实房间」）+ agent 计数 1179/12/264 内部自洽 + bind fail=1 佐证游戏持 62900；真实房可见性来自**游戏自身应答**（62900 socket），agent 本轮 12 次应答全为 fixture 页（captured=0，真实页应答未演示）。
- **加入/数据面段：未验证**（M-1）——RUNBOOK §5 全口径 PASS 需「B 见真实房名+成功加入」两项，加入从未执行 → 全口径不成立，**不得宣称 E2-B 全结案**。
- FAIL 排查链（本轮未触发）：agent 存活 → hook 注入（civlink_ctl status）→ A 机 Civ6.exe 防火墙 UDP 入站。

## 6. 边界（登记口径，随 README v1.32/HANDOVER #19 同步）
1. 机械证据 ≠ 双人验证：agent 计数与自检 14/14 只证明应答机制，不代表「双人成功联机」。
2. 虚拟房间同 IP 去重 = Civ6 客户端行为（m26472：A 有真实房→B 看不到虚拟房；A 无真实房→可见），非 civlink 缺陷；与 plan §7/runbook §6 预期「可能两条房间记录」的差异（实际=仅一条真实房）已注明。
3. agent 真实页应答路径本轮未演示（captured=0/replies real=0）；真实页能力依赖 B1 轮证据。
4. 加入/数据面直连未验证（M-1）。
5. 不证明：对局完整性、长稳（本轮仅 1800.2s 单窗口）、跨网（Radmin VPN/WLAN 之外未测）、Noise 加密通道。
6. agent 增量贡献未量化（m26254 含「即使不需要 Agent，B 依旧可以搜到 A 创建的真实房间」）；「消除 1/100 窗口」依据仍在 F5/机制证据，不得写入本轮结论。
7. A 侧 hook 注入状态未登记（datagrams=0 但无 civlink_ctl status 归档）。
8. B 侧机器证据缺失（civtrace 无归档输出；PC-B 离线=环境限制，B 侧证据仅 D 级口述）。
9. E2-A/E3/Gate A 复核另行登记。
10. 时间戳语义：summary「run time」=UTC 退出时刻；本地窗口 20:28:53→20:58:53。

## 7. 审计与登记（已完成）
- 子代理审计：**M0B-DUALMACHINE-REVIEW.md**（17,975B / E024B832D1970E994151752CD1B8E43EA65AF37FB92EE01396D737C9B8812248），裁定**有条件通过**（发现链路段通过、加入段待验证），必改 M-1~M-5（M-1 待 PC-B 恢复）。
- README/HANDOVER 登记：v1.32 修订块 + HANDOVER 第 19 项状态更新（见各自文档）。
- 登记链：单向引用不嵌互引哈希；本报告引用 REVIEW 裁定与证据哈希；REVIEW 引用本报告只写文件名与版本。
- 结案条件：完成 M-1（加入+数据面 62056 验证，PC-B 恢复后）→ 开新一轮修订块 → 方可宣称 E2-B 全结案。
