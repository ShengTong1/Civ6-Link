# A-6 SO_BROADCAST 决定性实验证据（2026-11-11）

对应 REV-002-E1-REVIEW.md 复核意见第 1 条（核查 Hook_setsockopt 读 optval 安全性 + 游戏日志 SO_BROADCAST 矛盾）。

## 结论
游戏日志 'setsockopt SO_BROADCAST val=0 ret=0' 后 100x sendto 成功，是 **civtrace 读值守卫的展示性误读**：
Hook_setsockopt（trace_dll.cpp:820-821）仅当 optlen >= sizeof(int) 才读 optval（防越界，安全），
游戏以 optlen<4（很可能 1）+ 字节值 1 调用 -> Windows 按 optlen 真实字节开启 SO_BROADCAST，
civtrace 显示守卫后默认 val=0。**游戏实际设置了 SO_BROADCAST=1**。

**限定**（按 REV-002-E1-FOLLOWUP-REVIEW）：
- 游戏**具体传入的 optlen 无直接证据**：civtrace 当前日志格式不打印 optlen 字段，无法从
  已有游戏会话日志（civtrace_20261111_151008_pid42256.log）直接读出游戏的 optlen/字节值。
  "游戏以 optlen<4 + 字节值 1 调用"是**推断**（基于 c6 复现的日志模式与 sendto 成功这一必要条件）；
  直接证实需 v0.4.5 给 setsockopt Hook 增加 optlen 打印（采样格式变更，须另行批准）。
- 归档证据含运行输出/编译记录/哈希（见下方证据文件），可独立复现复核。

## 实验链
1. sobroadcast_c.c / c2：注入 civtrace 的闭环（set0 -> FAIL 10013、set1 -> OK；civtrace 记录与程序行为一致 -> 读值准确）
2. sobroadcast_c3.c：尝试 WSASetSockOpt（ws2_32 无此导出，dumpbin /exports 196 项验证，LNK2019+GetProcAddress 均失败）
3. sobroadcast_c4.c：矩阵（SO_BROADCAST=0 时 255.255.255.255 有限广播必 FAIL 10013；
   接口定向广播 26.255.255.255 / 192.168.31.255 反而 OK——Windows 11 26100 反直觉行为）
4. sobroadcast_c5.c：optlen={1,2,4} x val={1,0} -> optlen<4 + val=1 也能开启广播且 sendto OK
5. sobroadcast_c6.c：注入 civtrace 后 optlen=1 val=1 -> civtrace 日志显示 val=0 ret=0、sendto ret=4
   （与游戏日志模式逐字节一致，决定性证据；2026-11-11 16:31:15 复现，pid=53584）

## 复现
cl /nologo /O2 /MT sobroadcast_c6.c /link ws2_32.lib；先起 c6（argv: optlen val pre-wait-ms），再 civinject -x sobroadcast_c6.exe

## 证据文件（本目录）
| 文件 | 内容 |
|------|------|
| `build-commands.txt` | 编译命令与注入命令（vcvars64.bat + cl /MT + civinject 无动作参数） |
| `run-output-20261111.txt` | c5/c6 运行输出 + 注入器输出 + civtrace 日志关键行 |
| `sha256.txt` | c5/c6 源码/可执行/civtrace 日志哈希（前 16 位） |
| `sobroadcast_c5.c/.exe`、`sobroadcast_c6.c/.exe` | 可复现的可执行实验 |
