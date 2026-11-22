# M0-B 准备材料审计报告（复审）：DLL 注入稳定性观察 + GUI 编译

- 审计性质：首轮审计（`M0B-PREP-DLL-STABILITY-REVIEW.md`，11,210B）的**必改项复审**；只读，未修改任何被审对象
- 复审对象：`M0B-PREP-DLL-STABILITY-20261115.md`（§5.2/§5.3 措辞修正）、`civlink\ctl\civlink_ctl_gui.cs`（头注释修正）、已部署产物 `civlink-gui\civlink_ctl_gui.exe`（应未重编译）、证据目录 `M0A\captures\M0B-prep-stability-20261115\`
- 复审日期：2026-11-15
- 裁定：**通过**（首轮 3 项低危必改 D-1/D-2/D-3 全部落地；无新增缺陷；§4 无回归）

---

## A 身份核查 —— PASS（逐项命中）

| 对象 | 声称 | 独立实测 | 判定 |
|------|------|----------|------|
| `CivLink-M0A-audit\docs\M0B-PREP-DLL-STABILITY-20261115.md` | 4,467B / ED439B2D56F32C5D466161CB4AD4D8F413050E7AB5DEDCA1E5A1ECE06EEF6A5A | 4,467B / ED439B2D…（完全一致） | PASS |
| `CivLink-M0A-audit\civlink\ctl\civlink_ctl_gui.cs` | 6,450B / 593090765532E10015274B261842AA776BA87BA1345C9A431824C8139E53AF3D | 6,450B / 593090765532E10015274B261842AA776BA87BA1345C9A431824C8139E53AF3D（完全一致） | PASS |
| `civlink-gui\civlink_ctl_gui.exe` | 8,704B / A0EB830BF26D4AFBAEF2AD719748660409ECAE4647BD1527B1649E838FD3B894（未重编译） | 8,704B / A0EB830B…（与首轮实测值相同，未变化） | PASS |
| `…\M0B-prep-stability-20261115\samples.csv` | 520B / BDDB8A18… | 520B / BDDB8A1813DF44E588A6654D18B1B3D4AED543A955E0A9944BB86ED08B187F30 | PASS |
| `…\M0B-prep-stability-20261115\inject-hook.txt` | 1,547B / AD8B7A91… | 1,547B / AD8B7A912152763668F30B17B99E216366C9EF70188959DA0F81261CE73E75ED | PASS |
| 文档字符卫生 | 无 BOM、无 tab/vt/ff | NO-BOM（首 3 字节 `23 20 4D` = "# M"）；tab=0、vt=0、ff=0、CR=0、LF=71（纯 LF 行尾） | PASS |
| 源码字符卫生 | （首轮为 NO-BOM） | civlink_ctl_gui.cs NO-BOM；tab=0、vt=0、ff=0 | PASS |

补充：
- 文档 §7 身份表所列 `civlink_hook.dll` 119,808B/9424FC25… 与 `civlink_ctl.exe` 173,056B/23923DFB… 经实测一致（civlink-gui 目录）；证据 `inject.txt` 922B/3EA96332… 亦一致。
- 文档较首轮 4,225B → 4,467B（+242B），与 §5.2/§5.3 措辞修正的体量吻合；源码较首轮 6,426B → 6,450B（+24B），与单行头注释修正的体量吻合。

## B D-1 修正 —— PASS

首轮必改 D-1：§5.2 曾称 8 项计数"全程为 0"，但后 4 项（sock overflow/cvlh2 fail/cvlh2 errno/channel down）未纳入采样列，仅注入时点快照为 0。

现 §5.2 新措辞（逐字）：
> 采样期间 send fail / reject oversize / sent notify / ignored **全程为 0（samples.csv 已采样列）**；sock overflow / cvlh2 fail / cvlh2 errno / channel down **未纳入采样列，注入时点快照为 0**（见 inject-hook.txt counters 段）。

- 采样列 4 项"全程为 0"限定句成立：samples.csv 的 sendfail/rejectoversize/sentnotify/ignored 四列在 5 个采样点均为 0，且"全程为 0"明确括注"已采样列"。
- 未采样 4 项正确表述为"注入时点快照为 0"：samples.csv 表头确无 sockoverflow/cvlh2fail/cvlh2errno/channeldown 列；inject-hook.txt counters 段该 4 项（sock overflow: 0、cvlh2 fail: 0、cvlh2 errno: 0、channel down: 0）均快照为 0。
- 全文检索"全程"：唯一出现处即上述限定句；**不再存在把未采样项说成"全程为 0"的表述**。

## C D-2 修正 —— PASS

首轮必改 D-2：§5.3 曾断言"与 F2 S5 ≈1.6M/s 一致"，实为推断（60s 粒度仅支撑平均 ≥64,749 次/s，峰值未复测）。

现 §5.3 新措辞（逐字）：
> 60s 采样粒度支撑**平均 ≥64,749 次/s（3,884,931/60）**，与 F2 S5 观察（客户端忙轮询 WSARecvFrom ≈1.6M/s）**为量级一致的推断（峰值未复测）**；Hook 在该忙轮询压力下稳定。

- 必备元素齐备："≥64,749 次/s（3,884,931/60）"（3,884,931/60=64,748.85，≥64,749 计算正确）与"量级一致的推断（峰值未复测）"逐字命中。
- 全文检索"1.6M"：唯一出现处是括注中的背景值，其后的结论谓语是"为量级一致的推断（峰值未复测）"；**不再出现"与 ≈1.6M/s 一致"式断言**。

## D D-3 修正 —— PASS

首轮必改 D-3：GUI 源码头注释曾称"非管理员启动时自提权"，但 Main() 无提权代码。

- 头注释第 4 行已改为（逐字）：`// 运行需管理员（注入需要 SeDebugPrivilege）；本版未实现自提权，请以管理员身份启动。` —— 与必改要求一致；旧表述"非管理员启动时自提权"已删除（源码全文检索，提权相关仅此一行）。
- 实现核对：`Main()` 仅有 `Application.EnableVisualStyles()` / `SetCompatibleTextRenderingDefault(false)` / `Application.Run(new MainForm())`，无 runas/ShellExecute/SelfElevation/manifest 提权代码；注释与实现现已相符。
- 产物未重编译：`civlink_ctl_gui.exe` 8,704B / A0EB830B… 与首轮实测完全相同（注释非编译内容，不影响产物）；二进制检索确认产物内既不含新注释文本、也不含旧表述文本。
- 四子命令封装不变：源码 `RunCtl("inject","-d",dllBox.Text)` / `RunCtl("status")` / `RunCtl("counters")` / `RunCtl("shutdown")` 与首轮一致；产物 UTF-16 字符串含 inject/status/counters/shutdown、`civlink_ctl.exe`、`civlink_hook.dll`、"CivLink 控制端 GUI"——源码字面量与产物对应。源码 +24B 的差异与注释单行修改一致（无 git 历史/存档旧版可做逐字节 diff，但产物哈希未变 + 字面量核对已构成充分证据）。

## E 边界声明 —— PASS

- 顶部"性质声明（必读）"完整：本文档是 **M0-B 的准备材料（tool-level evidence）**，不是 M0-B 验收，不勾除 Gate A/B，不代表"双人真实联机已验证"；正式 M0-B 仍冻结；Gate A 未批准；结论边界为单次会话、单进程、约 5 分钟窗口。
- §6 不证明清单仍完整（11 项）：双人真实联机、E2-A/E2-B/E3、对局稳定性、长时间（小时级）运行、多会话、跨进程、62056 数据面转发正确性（只观察了忙轮询收包，未观察转发）、Relay RTT、Fake-IP、Noise、跨网；并保留"本次 agent 未运行，Hook 计数反映的是截获+封装成功，不涉及转发投递"的说明。
- 全文检索"验收/已验证/勾除/Gate"：仅出现在性质声明（否定式）与"正式 M0-B 验收仍需按 README v1.21 §4/§5 执行 E2-A/E2-B/E3 双机流程"的正向指引中；**无越界结论**。

## F 数据一致性 —— PASS（附一条信息性说明）

- samples.csv 未变（520B / BDDB8A18…，与首轮同哈希），证据库无意外变动。
- §4 表格 5 行 × 展示列与 samples.csv 逐列逐行一致（程序化比对，千分位 3,884,931 = CSV 3884931）：sent 100→100→500→500→500、send fail/reject oversize/ignored 恒 0、raw sendto 100→100→500→500→500、raw bind 0→0→4→5→5、recv on 62056 0→0→3,884,931→3,884,931→3,884,931、bind 62056 0→0→2→2→2、cvlh2 try/ok 100→100→500→500→500、state queries 恒 3、内存 1659.8→4270.8→3708.2→3707.9→3707.5 —— 全部命中。本次确未改动 §4，无意外破坏。
- 信息性说明（非缺陷、非本轮回归）：§4 展示列"raw recvfrom"取值为 3,884,931，对应 CSV 的 **rawwsarecvfrom**（WSARecvFrom 路径计数——Civ6 DX12 实际收包路径）；CSV 另有 rawrecvfrom=0 列未在 §4 展示。该列名与 CSV 原始列名存在"raw recvfrom ↔ rawwsarecvfrom"的对应关系，与首轮裁定（首轮即以该取值判"全等"，且 §5.3 将 3.88M 收包明确归因于"客户端忙轮询 WSARecvFrom"）一致，本轮 §4 未改动，不构成缺陷。

---

## 缺陷分级

| 级别 | 编号 | 位置 | 描述 |
|------|------|------|------|
| 阻断 | — | — | 无 |
| 高 | — | — | 无 |
| 低（必改） | — | — | 无（首轮 D-1/D-2/D-3 三项均已关闭） |
| 信息 | I-1 | 文档 §5.4（遗留） | "12:50→12:51 的增长为游戏加载地图，非 DLL 所致"仍为解释性归因（无"推断"标注）；首轮定为信息建议非必改，本轮未要求处理，不阻断 |
| 信息 | I-2 | GUI 源码 `RunCtl`（遗留） | `-d` 参数未加引号、`Quote()` 对 `"` 用 `\"` 转义；当前部署路径无空格可工作；首轮定为信息建议非必改，不阻断 |

## 必改项复核结论

| 必改项 | 要求 | 实测 | 状态 |
|--------|------|------|------|
| D-1 | §5.2 区分"采样列 4 项全程为 0"与"未采样 4 项注入时点快照 0"；不再把未采样项说成全程为 0 | 措辞逐字命中；全文无越粒度表述 | ✅ 已关闭 |
| D-2 | §5.3 含"≥64,749 次/s（3,884,931/60）"与"量级一致的推断（峰值未复测）"；不再断言"与 ≈1.6M/s 一致" | 措辞逐字命中；计算正确；无裸断言 | ✅ 已关闭 |
| D-3 | 头注释改为"本版未实现自提权，请以管理员身份启动"；产物 A0EB830B 未变；四子命令封装不变 | 注释逐字命中；Main() 确无提权代码；产物哈希与首轮一致且不含新/旧注释文本；四子命令封装与字面量核对一致 | ✅ 已关闭 |

## 最终裁定

**通过。**

- 身份（A）：文档/源码/产物/证据的字节数与 SHA-256 独立重算全部命中声称值；文档与源码均无 BOM、无 tab/vt/ff；§7 引用二进制身份复验一致 —— 通过。
- D-1（B）、D-2（C）、D-3（D）：三项低危必改修正全部如实落地，措辞与实现一一对应，无残留旧表述 —— 通过。
- 边界（E）：性质声明与 §6 不证明清单完整，无越界结论 —— 通过。
- 数据（F）：samples.csv 与 §4 逐列逐行一致，本轮无意外破坏 —— 通过。

材料真实、证据链完整、修正到位，无新增缺陷。该准备材料可作为 M0-B 的前置工具级证据使用；其结论边界（不勾 Gate A/B、不证明双人真实联机/62056 转发正确性）维持不变。
