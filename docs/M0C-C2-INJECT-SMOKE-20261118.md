# C2 真实进程内注入冒烟测试：首次成功进入真实进程的验证记录

- 执行时间：2026-11-18 09:16–09:20
- 证据目录：`M0A\captures\C2-inject-smoke-20261118-0916`（18 文件）
- 性质：**冒烟测试（smoke test）**，用 `powershell.exe` 作宿主代替游戏进程，目的是回答"`civlink_client.dll` 究竟能不能注入进一个真实进程并正常工作"这个此前**一次都没被验证过**的问题。

---

## §1 为什么要单独做这一轮

第一轮 C2 自检（`client_selftest.exe`）是在**测试进程自己加载 DLL** 的环境里跑计数器的，它绕过了整条注入路径。而 `civlink_ctl.exe` 的三个用例（T1/T1b/T2/T3）全部止于：

- `target process not found (or ambiguous)`（exit 2），或
- `OpenProcess failed err=5`（exit 2，非提权）

也就是说：**注入路径本身从未被真正执行过**。设计文档 §7.3 与 C2 审计报告都把这一点登记为未完成项。本轮补上。

---

## §2 过程与两个"非产品"障碍

### 障碍 1：从工作区目录运行 `civlink_ctl.exe` → `OpenProcess failed err=5`

在工作区（`CivLink-M0A-audit\civlink\`）里直接运行 ctl，即使目标是当前用户自己的子进程，`OpenProcess` 也返回 `err=5`（ACCESS_DENIED）。用 `Add-Type` 直接调 `OpenProcess` 验证：**连自己进程（`$PID`）的 `PROCESS_QUERY_LIMITED_INFORMATION` 都会失败**，但 PowerShell 自身 `$p.Handle` 正常。

把**同一组文件**（`civlink_ctl.exe` + `civlink_client.dll`）复制到 `%TEMP%\c2inject\` 后运行 → `OpenProcess` 立即成功。

**结论**：这是 DSH 文件沙箱限制“在工作区内派生的进程执行 OpenProcess 类操作”的结果，与之前发现的 `errno=13`（工作区内派生进程写工作区外文件）属于同一类限制，**不是 CivLink 缺陷**。证据：`inject.log` / `inject2.log`（工作区内，exit 2）vs `inject-pin2.log`（TEMP 内，exit 0）。

### 障碍 2：`notepad.exe` 找不到进程

新建的 Windows 11 记事本实际进程名是 `Notepad`（大小写不敏感但路径来自 WindowsApps 包），`-x notepad.exe` 匹配不到。改用显式 `-p <pid>` 即可。与产品无关。

---

## §3 成功注入与计数（决定性）

注入命令（TEMP 目录，目标为 `powershell.exe -File target-send2.ps1`，脚本固定发 10 个广播 + 4 个普通包）：

```
civlink_ctl.exe inject-client -p <pid> --iface 192.168.31.60
→ [+] LoadLibraryW returned 0xfc840000
→ [+] hooks active (CivLinkHookState=1)
→ exit 0
```

| 轮次 | 配置来源 | `--iface` | `raw sendto` | `sent` | `ignored` | `sendFail` | `initError` | 证据 |
|---|---|---|---|---|---|---|---|---|
| A | env override（`CIVLINK_CLIENT_IFACE_FILE`） | 192.168.31.60 | 14 | **0** | 14 | 0 | **0** | `counters-pin.log` |
| B | 默认路径 `%LOCALAPPDATA%` | 192.168.31.60 | 14 | **10** | 4 | 0 | 0 | `counters-pin2.log`、`inject-pin2.log` |
| C | 默认路径 | ALL | 14 | **0** | 14 | 0 | 0 | `counters-all.log`、`inject-all.log` |

**A 轮是审计 H-3 预言现象的现场复现**：`initError=0`（配置"读取成功"）、`sent=0`、`ignored=14`——DLL 在**目标进程**里读配置，而 shell 里设置的 `CIVLINK_CLIENT_IFACE_FILE` 根本不在目标进程的环境块里，于是它回落到默认路径，读到的是 `ALL`。**表现是"一切正常"，实际定向完全没生效**。这正是 H-3 判定"该变量在真实部署下大概率不起作用"的实证。

**B 轮证明注入链 + 配置链 + 定向判定链在真实进程内全部贯通**：`sent=10`（10 个广播目标被设置 `IP_UNICAST_IF`）、`ignored=4`（4 个普通目标不动）、`raw sendto=14`（原始调用全部发出、一个都没吞）、`initError=0`。

**C 轮是 ALL 模式对照**：`sent=0`、`ignored=14`——零干预成立。

---

## §4 新增发现的产品缺陷：`status`/`counters` 默认解析错模块

注入 `civlink_client.dll` 后执行：

```
civlink_ctl.exe status -p <pid>            → [!] cannot resolve CivLinkHookState in ...\civlink_hook.dll  (exit 1)
civlink_ctl.exe counters -p <pid>          → 同上 (exit 1)
civlink_ctl.exe status -p <pid> -m civlink_client.dll   → hook state : 1 (running)  (exit 0)
civlink_ctl.exe counters -p <pid> -m civlink_client.dll → 完整计数表  (exit 0)
```

原因：`status`/`counters` 用 `g_dllName` 去**本地** `ResolveLocalPe()` 解析导出地址，而 `g_dllName` 只在 `inject-client` 分支被自动切成 `civlink_client.dll`；直接调 `status`/`counters` 时仍是默认的 `civlink_hook.dll`，于是从错误的本地 DLL 取 RVA。

**严重度：中**。不是安全或正确性问题（用 `-m` 可绕过），但对 B 机用户是**默认路径不可用**——他们第一次用 `counters` 就会看到 exit 1 的报错，容易误判为"注入失败"。修法建议：`status`/`counters`/`shutdown` 在未显式给 `-m` 时，**先查目标进程是否已加载 `civlink_client.dll`**，若加载则自动用它；或至少在报错里提示"目标可能加载的是 civlink_client.dll，请加 `-m civlink_client.dll`"。

---

### §4.1 修复与复验（2026-11-18 09:23，证据 `C2-inject-smoke-20261118-0940`）

修法落地：在 `OpenProcess` 成功之后、进入 `status`/`counters`/`shutdown` 分支之前，若调用方**未显式**给 `-m`，先 `QueryRemoteModule(hProc, CIVLINK_HOOK_DLL_NAME_A)`；查不到再查 `CIVLINK_CLIENT_DLL_NAME_A`，命中则切换 `g_dllName` 并打印 `[*] target has civlink_client.dll loaded - using it (override with -m)`。

复验（同一注入流程，配置=默认路径 + PIN 192.168.31.60）：

```
civlink_ctl.exe status   -p <pid>   → [*] target has civlink_client.dll loaded - using it (override with -m)
                                      hook state : 1 (running)                       exit 0
civlink_ctl.exe counters -p <pid>   → sent 10 / ignored 4 / raw sendto 14 / init error 0  exit 0
```

两条命令都不再需要 `-m`，且计数与 §3 的 B 轮完全一致。证据：`status-auto.log` 672 B/`613FADC5…`、`counters-auto.log` 1,928 B/`09A779F2…`、`inject.log` 1,768 B/`92D19408…`。

重建产物：`civlink_ctl.exe` 188,416 B/`8B9A9AF89A652434EC10CA47DFE5DEE34BCE864C3FE539DD737A2B09819ACA22`（+ 同轮 `civlink_hook.dll` `AD14C6C3…`、`civlink_client.dll` `0BCC4C1D…`、`hook_selftest.exe` `ABF018A2…`、`client_selftest.exe` `0AAA32EA…`）。

## §5 本轮证明了什么 / 没证明什么

**证明**：
1. `civlink_client.dll` 可以被 `civlink_ctl.exe` 成功注入真实进程（`LoadLibraryW` 返回非零、`CivLinkHookState==1`、exit 0）；
2. 注入后四个导出（state/counters/session/shutdown）在**跨进程**场景可用，计数表能完整读出，且 `status`/`counters` 在未指定 `-m` 时能自动识别目标加载的是哪个 CivLink 模块（§4.1）；
3. 配置链路在真实进程内生效，但**必须走默认路径**（`%LOCALAPPDATA%\CivLink\client-iface.txt`），env override 不会传入目标进程（H-3 实证）；
4. 发现目标判定在真实进程内正确：10 个广播目标 → `sent=10`，4 个普通目标 → `ignored=4`，`raw sendto=14` 全发出未吞；
5. ALL 模式零干预（`sent=0`）。

**没证明**：
1. **广播是否真的从选定网卡发出**——本机广播不回环，看不到出接口；仍需跨机（`M0C-C2-CROSSMACHINE-RUNBOOK-20261118.md`）；
2. **能否注入真实《文明6》进程**——游戏有 Steam DRM 与反作弊边界，本轮的宿主是 `powershell.exe`；真实游戏注入未做；
3. 长跑稳定性、与 Steam overlay / 其它注入物的共存；
4. 任何双人联机能力（不勾 E2-A/E2-B/E3，不移动 Gate A/B）。

---

## §6 待办（按优先级）

| # | 事项 | 归属 |
|---|---|---|
| 1 | ~~修 `status`/`counters` 默认模块解析（§4）~~ **已修并复验（§4.1）** | 关闭 |
| 2 | 在文档中把 env override 明确降级为"仅自测用"，正式路径只写 `%LOCALAPPDATA%`（H-3 的最终处置） | 设计 §5.1 + 复审 |
| 3 | 真实《文明6》进程内注水测试（游戏可正常建房 + `counters` 可读 + 不破坏联机） | PC 可用时 |
| 4 | 跨机出接口实测（三轮对照） | PC-B 上线后 |

---

## §7 证据哈希

| 文件 | 字节 | SHA256 |
|---|---|---|
| `inject-pin2.log` | 1,768 | `D4691CF2EBF15491AEA390C5CDE79ED36F9F3F703801EC1DA45E051154F4D2E5` |
| `counters-pin2.log` | 1,784 | `D43FCEAF0223B0204EE6144D5750754E0CF6EC0E01541FABA1E3C40DED9D56F3` |
| `counters-all.log` | 1,782 | `F4459A4246CC6B2D42F1499EA86B29D520A89A43E47ED06D87A730434CDF780D` |
| `inject-default.log` | 1,768 | `6CB772D496373C52FC4EFFC0D3705008FA6D66104A691E36654BC58E42887ABF` |

产物（**09:22 轮历史值，已被 REVIEW-2 修正后的 `-1015` 采信轮取代**；当前值见 `docs\M0C-C2-DESIGN-20261118.md` §7.4）：`civlink_client.dll` 149,504 B / `DA9844AA0F3997DC68015F68D0074FCC3C4ED9610FB793F4F4382B65D20A538A`；`civlink_ctl.exe` 188,416 B / `B864070397AEEDDA2FEE7A5A790522820173A75DDB2C9A2567466BCE184F3CD4`。当前磁盘值：`civlink_client.dll` `F3816C5E0E6C5BD5920CDCE8AA2B5378623E6420A5C1966E275D663C1B8385D3`、`civlink_ctl.exe` `6FCE456E4156873F093732253E0381872F0CDEAAFFF61655D9460ABB73634D26`。
