# M0-E 回真实房间模式接入 GUI（2026-11-19）

> 版本：v1.0（2026-11-19）
> 状态：实现完成 + 自检 40/40 + 变异 3/3 命中；**M0-E 设计复审（`docs/M0E-REVIEW-2.md`）尚未返回，本文件不构成通过结论。**
> 范围：只描述 GUI 如何调用 `--discovery-completion`。M0-E 的机制、证据与边界见 `docs/M0E-DISCOVERY-COMPLETION-20261118.md`。

## 1. 为什么改 GUI

用户 m29860 定下的最终形态是「不要虚拟房间」：房主的 Agent 绑 62901–62999，游戏自己占 62900，任一端口收到客户端 magic 都回**本机游戏的真实房间**。M0-E 在命令行上已经打通，但此前 GUI 只能启动"模拟房主 agent"（`--simulate <fixture>`），也就是用户明确说要淘汰的调试形态。本次把真实房间模式做成 GUI 的默认路径。

## 2. 改了什么

| 位置 | 改动 |
| --- | --- |
| `civlink/gui/civlink_tray.cs` `AgentSupervisor.BuildArgs` | 增加第 5 参 `realRoom`。为 true 时拼 `--discovery-completion` 并**不拼** `--simulate`（agent 侧两者互斥，同时给会拒绝启动）；为 false 时保留原有 `--simulate` 路径与"fixture 目录必需"的校验。 |
| 注入向导页 | 新增复选框「回真实房间（M0-E）」，默认勾选；LAN IP 下拉框新增 `0.0.0.0` 选项。 |
| `OnRealRoomToggled` | 勾选真实房间且 LAN IP 仍是 `(不启用)` 时，自动选中 `0.0.0.0`。 |
| `ApplyRoleDefaults` | A 房主角色下启用该复选框；按钮文字随模式变（「启动发现补全 agent（回真实房间）」/「启动模拟 agent（高级）」）；角色提示语改成"让客户端看到真实房间"。 |
| `StartAgent` | 真实房间模式**不再要求** GUI 同目录有 `fixture-reply-set`（该目录只服务模拟模式）；日志明确写"发现补全模式：只应答本机游戏的真实房间；请在游戏里先建房"。 |
| 自检 | 新增 5 条：`real-room agent uses --discovery-completion`、`real-room agent must not pass --simulate`、`real-room agent reserves 62900`、`real-room agent never binds 62056`、`real-room flag without LAN IP stays a plain agent start`；另加 2 条通配断言 `wildcard listen IP accepted` 与 `real-room wildcard listen`。 |

为什么默认 `0.0.0.0`：M0-E 的 B-1 修复用 `IP_PKTINFO` 学出**客户端探测的是哪个本机地址**，再把每一页的源地址钉成该地址（`docs/M0E-DISCOVERY-COMPLETION-20261118.md` §4.6 三接口实测）。因此一个通配 bind 就能同时正确服务 WLAN / Radmin / ZeroTier；若让用户在 GUI 里挑一张网卡，等于把"其他子网静默失效"重新引回来。

## 3. 自检与变异

自检（`civlink_tray.exe --selftest`）：

```
CivLink GUI SELFTEST PASS
checks=40 failed=0
```

变异 M6（把真实房间分支换成 `--simulate x`，模拟"写错分支"的退化）：自检 `checks=40 failed=3`，恰为 `real-room agent uses --discovery-completion` / `real-room agent must not pass --simulate` / `real-room wildcard listen`。证明新增断言真的能抓住"真实房间模式退化成模拟模式"。

## 4. 证据

`M0A\captures\gui-m0e-20261119-0052\`（4 文件）：

| 文件 | 字节 | sha256 |
| --- | --- | --- |
| `civlink_tray.exe` | 27,648 | `F49CE00632DBD15B06E41927B99F140A2F5A0DEE51FB3ACE2E406A2768C15582` |
| `civlink_tray.cs` | 39,608 | `F1A4B7E46D017DFE60F09DA57985CA772DEA207A70DF0AE361F72EFEE0FC5979` |
| `gui-selftest.txt` | 106 | `82FA6827870EC2EF9C8BC334ACEF53ADE39504EF13F72E06509F7681A011B84A` |
| `mutation-real-room.txt` | 446 | `BFB1A1BE1825418A24F777DC3EA68D026FBF947369786F10D9E1F24F3CD17EBE` |
| `build-manifest.txt` | 2,740 | `61BC0769485F9BAE6F85DE793D82BA5480F01D17ACCC3AE637A6A9CB9A4DD156` |

GUI 产物哈希不可跨机构复现（csc 内嵌 MVID），验收以源码 sha256 + 字节数 + 自检 exit 0 为准。

## 5. 相关身份

| 对象 | 字节 | sha256 |
| --- | --- | --- |
| `civlink/gui/civlink_tray.cs` | 39,608 | `F1A4B7E46D017DFE60F09DA57985CA772DEA207A70DF0AE361F72EFEE0FC5979` |
| `civlink/civlink-agent.exe` | 464,384 | `15321D49806517028ECE8CC8A3DC8B0ED855C410915295CAF72EBEF4DDF06267` |
| `civlink/agent/src/main.rs` | 176,308 | `E56A30562A94376B1982FCF184C2A81C791CF5B50B15218231712048E59A4276` |

## 6. 没证明什么

1. **没做真实双机**：PC-B 于 2026-11-19 00:44 探测仍离线（`Test-Connection 192.168.31.214` False）。客户端是否真的在局域网列表里看到并进入这间真实房间，未验证。
2. **没做 GUI 点击验证**：本次只验证了 `BuildArgs` 产出的命令行与自检断言；「点按钮 → agent 真跑起来 → 客户端看到房间」这条人工链路未执行。
3. **不改变 M0-E 的既有边界**：不证明跨机、不证明真实 Civ6 客户端接受 22 页、不证明端到端加入、不证明多人并发。不得据此勾 E2-A/E2-B/E3，不得移动 Gate A/B。
4. **建房顺序仍是前提**：agent 必须先让游戏建房（游戏 bind 62900），再由 agent 绑 62901–62999。GUI 日志已提示，但 GUI 未强制检查游戏是否已建房。
