// CivLink P1 product GUI (T2-T5). Single-file WinForms, net40, compiled by gui/build-gui.ps1.
// Design: docs/M0D-GUI-DESIGN-20261118.md (audit M0D-GUI-DESIGN-REVIEW-20261118.md, N-1..N-7 closed).
// Discipline: zero telemetry / zero logging / asInvoker / whitelist-only injection / ctl as subprocess.
// NOTE: mechanical evidence != verified two-player online. Gate A not approved.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace CivLink.Tray
{
    // ---------------- Whitelist (no arbitrary PID injection) ----------------
    internal static class Whitelist
    {
        // Names verified against README v1.34 / design §2.2. Final list pending owner confirmation.
        internal static readonly string[] Names = { "CivilizationVI_DX12", "CivilizationVI", "CivilizationVI_DX11" };

        internal static bool Contains(string name)
        {
            if (string.IsNullOrEmpty(name)) return false;
            foreach (string n in Names)
                if (string.Equals(n, name, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }
    }

    // ---------------- ctl exit code -> honest message ----------------
    internal static class ExitCodeMapper
    {
        internal static string Describe(int code)
        {
            switch (code)
            {
                case 0: return "操作成功（仅表示机械动作完成，不代表已联机）";
                case 1: return "用法错误：命令或参数不合法";
                case 2: return "未找到目标进程（或目标不唯一）";
                case 3: return "目标进程未加载 CivLink 模块";
                case 4: return "远程调用失败（计数数据不可信，已隐藏）";
                case 5: return "模块状态未在等待时间内就绪";
                default: return "未知退出码 " + code + "（请导出诊断包）";
            }
        }
    }

    // ---------------- Redactor (N-1: unconditional, never trust agent anonymization) ----------------
    internal static class Redactor
    {
        // Masks room= / room name / sim_room_name in ANY line incl. "LAN simulated host" section.
        // NEVER trust agent-side anonymization (main.rs prints args.sim_room_name verbatim, N-1).
        // Rule order matters for selftest discriminators (N-C/N-D), see SelfTest section 3.
        internal static string Redact(string input)
        {
            if (string.IsNullOrEmpty(input)) return input ?? string.Empty;
            string s = input;
            // (1) room[:=] <value> on any line.
            s = Regex.Replace(s, @"(?im)^(.*\b(room|room[_ ]?name|sim_room_name)\b.*[:=]\s*).+$", "$1<redacted>", RegexOptions.Compiled);
            // (2) N-C: mask the ENTIRE "simulated host" line regardless of which tokens it carries.
            //     This is the only rule that catches a sensitive token on that line when it has no
            //     "room" keyword - deleting it must make the N-C selftest sample leak (mutation M2).
            s = Regex.Replace(s, @"(?im)^.*simulated host.*$", "<redacted simulated-host line>", RegexOptions.Compiled);
            // (3) N-D: in-sentence room ("the room is X here") has no [:=], caught by this fallback.
            s = Regex.Replace(s, @"(?i)\b(room(?:[_ ]?name)?|sim_room_name)\b[^\r\n]{0,80}", "$1=<redacted>", RegexOptions.Compiled);
            // (4) Scrub local usernames / home paths that may leak via ctl error text.
            s = Regex.Replace(s, @"(?i)([A-Z]:\\Users\\)[^\\\r\n]+", "$1<user>", RegexOptions.Compiled);
            // (5) N-D: CIVTRACE_TAG value may contain spaces; mask to end of line, not one token.
            s = Regex.Replace(s, @"(?i)(CIVTRACE_TAG\s*=\s*)[^\r\n]+", "$1<redacted>", RegexOptions.Compiled);
            return s;
        }
    }

    // ---------------- Timeouts (N-4: GUI >= ctl internal fixed waits + margin) ----------------
    internal static class Timeouts
    {
        internal const int Inject = 20000;   // ctl LoadLibrary/RemoteCallInt 15s + margin
        internal const int Status = 20000;
        internal const int Counters = 15000; // ctl counters 10s + margin
        internal const int Shutdown = 15000;

        internal static int For(string ctlCommand)
        {
            switch (ctlCommand)
            {
                case "counters": return Counters;
                case "shutdown": return Shutdown;
                case "inject":
                case "inject-client": return Inject;
                default: return Status;
            }
        }
    }

    // ---------------- Boundary wording (single source of truth) ----------------
    internal static class Boundary
    {
        internal const string State = "双人验证未完成（Gate A 未批准）";
        internal const string Mechanical = "机械动作完成 ≠ 双人真实联机";
    }

    // ---------------- ctl subprocess runner ----------------
    internal sealed class CtlResult
    {
        internal int ExitCode;
        internal string StdOut;
        internal string StdErr;
        internal bool TimedOut;
        internal string Arguments;
    }

    internal static class CtlRunner
    {
        internal static string CtlPath()
        {
            return Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "civlink_ctl.exe");
        }

        // Dotted-quad with each octet in 0..255 (N-F: guards 999.999.999.999 at the GUI layer;
        // ctl ResolveIface remains fail-closed as the backstop).
        private static readonly string Octet = @"(25[0-5]|2[0-4]\d|1?\d?\d)";
        internal static bool IsDottedQuad(string v)
        {
            return !string.IsNullOrEmpty(v)
                && Regex.IsMatch(v, @"^" + Octet + @"(\." + Octet + @"){3}$");
        }

        // Builds argument string from VALIDATED parts only. cmd is one of the five known subcommands.
        // N-A fix: ALL five subcommands resolve a target via ctl ResolveTarget(), so every one of
        // them needs -x <whitelist process>. Previously only inject/inject-client got -x, making
        // status/counters/shutdown always return exit 2 ("target process not found").
        internal static string BuildArgs(string cmd, string processName, string module, string iface)
        {
            var a = new StringBuilder();
            a.Append(cmd);
            bool needsTarget = cmd == "inject" || cmd == "inject-client"
                            || cmd == "status" || cmd == "counters" || cmd == "shutdown";
            if (needsTarget)
            {
                if (!Whitelist.Contains(processName))
                    throw new ArgumentException("process name not in whitelist: " + processName);
                a.Append(" -x \"").Append(processName).Append("\"");
            }
            if (cmd == "inject" || cmd == "inject-client")
            {
                if (cmd == "inject-client")
                {
                    string ifaceVal = string.IsNullOrEmpty(iface) ? "ALL" : iface;
                    // ALL or a validated dotted-quad only; no free text (parameter-injection guard).
                    if (!string.Equals(ifaceVal, "ALL", StringComparison.OrdinalIgnoreCase)
                        && !IsDottedQuad(ifaceVal))
                        throw new ArgumentException("invalid --iface value");
                    a.Append(" --iface ").Append(ifaceVal);
                }
                if (!string.IsNullOrEmpty(module))
                {
                    // module is a file name, no path/space allowed.
                    if (!Regex.IsMatch(module, @"^[A-Za-z0-9_\-\.]+\.dll$"))
                        throw new ArgumentException("invalid module name");
                    a.Append(" -m ").Append(module);
                }
            }
            return a.ToString();
        }

        internal static CtlResult Run(string cmd, string args, int timeoutMs)
        {
            var psi = new ProcessStartInfo();
            psi.FileName = CtlPath();
            psi.Arguments = args;               // PS5.1/.NET4: use .Arguments (no ArgumentList)
            psi.UseShellExecute = false;        // asInvoker, no shell elevation / path injection
            psi.RedirectStandardOutput = true;
            psi.RedirectStandardError = true;
            psi.CreateNoWindow = true;
            psi.WorkingDirectory = AppDomain.CurrentDomain.BaseDirectory;

            var r = new CtlResult();
            r.Arguments = args;
            var p = new Process();
            p.StartInfo = psi;
            p.Start();
            System.Threading.Tasks.Task<string> so = p.StandardOutput.ReadToEndAsync();
            System.Threading.Tasks.Task<string> se = p.StandardError.ReadToEndAsync();
            bool exited = p.WaitForExit(timeoutMs);
            r.TimedOut = !exited;
            if (!exited)
            {
                // N-E: query state first, then a short grace wait, and only kill if still alive.
                // (A process can exit between WaitForExit(timeout) returning false and here.)
                try { if (p.HasExited) exited = true; } catch (Exception) { }
                if (!exited)
                {
                    try { exited = p.WaitForExit(2000); } catch (Exception) { }
                }
                r.TimedOut = !exited; // clear the flag if the process actually finished in the grace window
                if (!exited)
                {
                    try { p.Kill(); } catch (Exception) { }
                    p.WaitForExit();
                }
            }
            r.StdOut = so.Result ?? string.Empty;
            r.StdErr = se.Result ?? string.Empty;
            r.ExitCode = p.ExitCode;
            return r;
        }
    }

    // ---------------- Agent supervisor (stop-file discipline, 34718 detect) ----------------
    internal sealed class AgentSupervisor
    {
        internal string OutDir;
        internal string StopFile;
        internal int Pid;

        // Builds host-simulation args. reserve-62900 ONLY with --sim-lan-listen (design §2.6).
        // N-B fix: agent main.rs:1627-1637 requires --sim-lan-listen to be paired with --simulate
        // (fixture directory). Without it the advanced LAN agent exits immediately. The caller
        // passes the deployed fixture-reply-set directory; we validate it is non-empty here.
        // M0-E real-room mode: the Agent owns discovery ports 62901..62999 and replays every
        // client magic to the locally running game, then forwards the game's own 22-page advert
        // back to the client. The client sees the REAL room, not a simulated one, so no
        // fixture directory is involved and --simulate must NOT be passed (the Agent rejects it).
        internal static string BuildArgs(string listenIp, string outDir, string stopFile, string fixtureDir, bool realRoom)
        {
            var a = new StringBuilder();
            a.Append("--listen-seconds 0");
            a.Append(" --out-dir \"").Append(outDir).Append("\"");
            if (!string.IsNullOrEmpty(listenIp))
            {
                if (!CtlRunner.IsDottedQuad(listenIp))
                    throw new ArgumentException("invalid LAN IP");
                a.Append(" --sim-lan-listen ").Append(listenIp);
                a.Append(" --reserve-62900"); // only meaningful together with --sim-lan-listen
                if (realRoom)
                {
                    a.Append(" --discovery-completion");
                }
                else
                {
                    if (string.IsNullOrEmpty(fixtureDir))
                        throw new ArgumentException("--simulate fixture directory is required with --sim-lan-listen");
                    a.Append(" --simulate \"").Append(fixtureDir).Append("\"");
                }
            }
            a.Append(" --quiet");
            a.Append(" --stop-file \"").Append(stopFile).Append("\"");
            return a.ToString();
        }

        internal static bool Port34718InUse()
        {
            // 34718 is the hook->agent IPC port; refuse two agents. Keep detection non-fatal here.
            try
            {
                var lines = ReadNetstatUdp();
                foreach (string ln in lines)
                    if (ln.IndexOf(":34718", StringComparison.Ordinal) >= 0) return true;
            }
            catch (Exception) { }
            return false;
        }

        private static string[] ReadNetstatUdp()
        {
            var psi = new ProcessStartInfo("netstat.exe", "-ano -p UDP");
            psi.UseShellExecute = false;
            psi.RedirectStandardOutput = true;
            psi.CreateNoWindow = true;
            var p = Process.Start(psi);
            string s = p.StandardOutput.ReadToEnd();
            p.WaitForExit();
            return s.Split(new char[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
        }

        internal void Stop()
        {
            if (Pid <= 0) return;
            try
            {
                File.WriteAllText(StopFile, "stop", new ASCIIEncoding());
                var proc = Process.GetProcessById(Pid);
                if (!proc.WaitForExit(20000))
                {
                    // Only kill after stop-file grace period elapsed.
                    try { proc.Kill(); } catch (Exception) { }
                }
            }
            catch (Exception) { }
            Pid = 0;
        }
    }

    // ---------------- Modern theme (P1-GUI-v2, minimal dark) ----------------
    // Palette v3 (2026-11-19, user feedback: previous dark theme unreadable).
    // Reference points: DarkUI (RobinPerris), KeePass ModernTheme plugin, AcrylicUI -
    // all use a softer near-black background, larger type, and brighter primary text.
    internal static class Theme
    {
        internal static readonly Color Bg        = ColorTranslator.FromHtml("#1B1F24"); // window
        internal static readonly Color Card      = ColorTranslator.FromHtml("#242930"); // panels
        internal static readonly Color CardEdge  = ColorTranslator.FromHtml("#303640");
        internal static readonly Color Accent    = ColorTranslator.FromHtml("#4FC3F7");
        internal static readonly Color AccentDim = ColorTranslator.FromHtml("#256D8F");
        internal static readonly Color Ok        = ColorTranslator.FromHtml("#7BD88F");
        internal static readonly Color Warn      = ColorTranslator.FromHtml("#FFB74D");
        internal static readonly Color TextHi    = ColorTranslator.FromHtml("#FFFFFF"); // primary: pure white
        internal static readonly Color TextMid   = ColorTranslator.FromHtml("#C9CDD2"); // secondary: high readability
        internal static readonly Color Field     = ColorTranslator.FromHtml("#2A303A");
        internal static readonly Font H1    = new Font("Microsoft YaHei UI", 15F, FontStyle.Bold);
        internal static readonly Font Body  = new Font("Microsoft YaHei UI", 10.5F, FontStyle.Regular);
        internal static readonly Font Mono  = new Font("Consolas", 10.5F, FontStyle.Regular);
        internal static readonly Font Btn   = new Font("Microsoft YaHei UI", 10.5F, FontStyle.Regular);
        internal static readonly Font Small = new Font("Microsoft YaHei UI", 9.5F, FontStyle.Regular);
    }

    // ---------------- Main form: five tabs + tray ----------------
    internal sealed class MainForm : Form
    {
        private TabControl tabs;
        private NotifyIcon tray;
        private ComboBox roleBox, procBox, dllBox, ifaceBox, lanIpBox;
        private CheckBox realRoomChk;
        private TextBox logBox, statusBox, countersBox, diagBox;
        private Button btnInject, btnRefresh, btnStatus, btnCounters, btnDiag, btnAgentStart, btnAgentStop;
        private readonly AgentSupervisor agent = new AgentSupervisor();

        internal MainForm()
        {
            Text = "CivLink 联机助手";
            Size = new Size(820, 600);
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            BackColor = Theme.Bg;
            Font = Theme.Body;
            DoubleBuffered = true;

            tabs = new TabControl();
            tabs.Dock = DockStyle.Fill;
            tabs.Font = Theme.Body;
            StyleTabs();
            tabs.TabPages.Add(BuildInjectPage());
            tabs.TabPages.Add(BuildStatusPage());
            tabs.TabPages.Add(BuildCountersPage());
            tabs.TabPages.Add(BuildSettingsPage());
            tabs.TabPages.Add(BuildDiagnosticsPage());
            Controls.Add(tabs);

            tray = new NotifyIcon();
            tray.Icon = SystemIcons.Application;
            tray.Text = "CivLink · " + Boundary.State;
            tray.Visible = true;
            tray.DoubleClick += delegate { Show(); WindowState = FormWindowState.Normal; };

            RefreshProcesses();
        }

        // Flat dark tabs: owner-drawn header + flat content area (no 3D borders).
        private void StyleTabs()
        {
            tabs.DrawMode = TabDrawMode.OwnerDrawFixed;
            tabs.SizeMode = TabSizeMode.Normal;
            tabs.ItemSize = new Size(132, 36);
            tabs.Padding = new Point(14, 6);
            tabs.DrawItem += delegate(object s, DrawItemEventArgs e)
            {
                var tp = tabs.TabPages[e.Index];
                bool sel = tabs.SelectedIndex == e.Index;
                using (var bg = new SolidBrush(sel ? Theme.Card : Theme.Bg))
                    e.Graphics.FillRectangle(bg, e.Bounds);
                Color c = sel ? Theme.Accent : Theme.TextMid;
                using (var f = new SolidBrush(c))
                {
                    var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
                    e.Graphics.DrawString(tp.Text, sel ? Theme.H1 : Theme.Body, f,
                        new RectangleF(e.Bounds.X, e.Bounds.Y, e.Bounds.Width, e.Bounds.Height), sf);
                }
                if (sel)
                    using (var bar = new SolidBrush(Theme.Accent))
                        e.Graphics.FillRectangle(bar, e.Bounds.X + 10, e.Bounds.Bottom - 3, e.Bounds.Width - 20, 3);
            };
        }

        private Panel Card(int x, int y, int w, int h)
        {
            var p = new Panel();
            p.SetBounds(x, y, w, h);
            p.BackColor = Theme.Card;
            p.Padding = new Padding(14, 10, 14, 10);
            return p;
        }

        private Label H(string text, int x, int y)
        {
            var l = new Label(); l.Text = text; l.SetBounds(x, y, 700, 34);
            l.Font = Theme.H1; l.ForeColor = Theme.TextHi; l.AutoSize = false; return l;
        }

        private Label Note(string text, int x, int y)
        {
            var l = new Label(); l.Text = text; l.SetBounds(x, y, 720, 24);
            l.Font = Theme.Small; l.ForeColor = Theme.TextMid; l.AutoSize = false; return l;
        }

        private TextBox LogArea(int x, int y, int w, int h)
        {
            var t = new TextBox();
            t.Multiline = true; t.ReadOnly = true; t.ScrollBars = ScrollBars.Vertical;
            t.SetBounds(x, y, w, h);
            t.BackColor = Theme.Field; t.ForeColor = Theme.TextHi;
            t.BorderStyle = BorderStyle.None; t.Font = Theme.Mono;
            return t;
        }

        private TabPage BuildInjectPage()
        {
            var page = new TabPage("注入向导");
            page.BackColor = Theme.Bg;
            int y = 16;
            page.Controls.Add(H("连接设置", 20, y)); y += 40;
            page.Controls.Add(FieldLabel("角色", 20, y));
            roleBox = Combo(); roleBox.SetBounds(110, y - 2, 300, 26);
            roleBox.Items.AddRange(new object[] { "A 房主（发现主机）", "B 客户端（加入房间）" });
            roleBox.SelectedIndex = 0;
            roleBox.SelectedIndexChanged += delegate { ApplyRoleDefaults(); };
            page.Controls.Add(roleBox); y += 40;

            page.Controls.Add(FieldLabel("目标进程（白名单，只读 PID）", 20, y));
            procBox = Combo(); procBox.SetBounds(240, y - 2, 480, 26); page.Controls.Add(procBox); y += 40;

            page.Controls.Add(FieldLabel("模块", 20, y));
            dllBox = Combo(); dllBox.SetBounds(110, y - 2, 300, 26); page.Controls.Add(dllBox); y += 40;

            page.Controls.Add(FieldLabel("客户端网卡 (--iface)", 20, y));
            ifaceBox = Combo(); ifaceBox.SetBounds(240, y - 2, 240, 26);
            ifaceBox.Items.Add("ALL"); foreach (string ip in LocalIPv4()) ifaceBox.Items.Add(ip);
            ifaceBox.SelectedIndex = 0;
            page.Controls.Add(ifaceBox); y += 40;

            page.Controls.Add(FieldLabel("房主发现补全 LAN IP", 20, y));
            lanIpBox = Combo(); lanIpBox.SetBounds(240, y - 2, 240, 26);
            // 0.0.0.0 first: in real-room mode the Agent learns the probed local address from
            // IP_PKTINFO and pins each reply to it, so one wildcard bind serves every NIC
            // (WLAN, Radmin, ZeroTier) instead of forcing the user to pick one.
            lanIpBox.Items.Add("(不启用)");
            lanIpBox.Items.Add("0.0.0.0");
            foreach (string ip in LocalIPv4()) lanIpBox.Items.Add(ip);
            lanIpBox.SelectedIndex = 0;
            page.Controls.Add(lanIpBox);

            realRoomChk = new CheckBox();
            realRoomChk.Text = "回真实房间（M0-E）";
            realRoomChk.Checked = true;
            realRoomChk.AutoSize = true;
            realRoomChk.ForeColor = Theme.TextHi;
            realRoomChk.Font = Theme.Body;
            realRoomChk.SetBounds(500, y, 220, 26);
            realRoomChk.CheckedChanged += delegate { ApplyRoleDefaults(); OnRealRoomToggled(); };
            page.Controls.Add(realRoomChk); y += 44;

            btnRefresh = Button("刷新进程", 20, y); btnRefresh.Click += delegate { RefreshProcesses(); }; page.Controls.Add(btnRefresh);
            btnInject = Button("执行注入", 210, y); btnInject.Click += delegate { DoInject(); }; page.Controls.Add(btnInject); y += 48;

            page.Controls.Add(Note(Boundary.State + " · " + Boundary.Mechanical, 20, y)); y += 26;
            logBox = LogArea(20, y, 764, 240);
            page.Controls.Add(logBox);
            return page;
        }

        private TabPage BuildStatusPage()
        {
            var page = new TabPage("状态");
            page.BackColor = Theme.Bg;
            btnStatus = Button("查询状态", 20, 18); btnStatus.Click += delegate { DoCtl("status", Timeouts.Status); }; page.Controls.Add(btnStatus);
            statusBox = LogArea(20, 62, 764, 450); statusBox.Text = Boundary.State; page.Controls.Add(statusBox);
            return page;
        }

        private TabPage BuildCountersPage()
        {
            var page = new TabPage("计数");
            page.BackColor = Theme.Bg;
            btnCounters = Button("读取计数", 20, 18); btnCounters.Click += delegate { DoCtl("counters", Timeouts.Counters); }; page.Controls.Add(btnCounters);
            countersBox = LogArea(20, 62, 764, 450); page.Controls.Add(countersBox);
            return page;
        }

        private TabPage BuildSettingsPage()
        {
            var page = new TabPage("设置");
            page.BackColor = Theme.Bg;
            int y = 24;
            page.Controls.Add(H("隐私与行为", 20, y)); y += 44;
            page.Controls.Add(SettingLine("零遥测 · 零日志 · 无配置持久化", 20, y)); y += 30;
            page.Controls.Add(Note("不收集崩溃数据、不上传统计、不写任何日志文件。", 20, y)); y += 28;
            page.Controls.Add(Note("注入仅限白名单进程，asInvoker 运行，不请求管理员提权。", 20, y)); y += 28;
            page.Controls.Add(Note("普通 A 房主默认只注入 hook、不启 agent；模拟房主在下方高级项。", 20, y)); y += 40;
            btnAgentStart = Button("启动模拟 agent（高级）", 20, y); btnAgentStart.Click += delegate { StartAgent(); }; page.Controls.Add(btnAgentStart);
            btnAgentStop = Button("停止 agent", 210, y); btnAgentStop.Click += delegate { agent.Stop(); Log("agent 已按 stop-file 纪律停止。"); }; page.Controls.Add(btnAgentStop); y += 48;
            page.Controls.Add(Note(Boundary.State, 20, y));
            return page;
        }

        private TabPage BuildDiagnosticsPage()
        {
            var page = new TabPage("诊断");
            page.BackColor = Theme.Bg;
            diagBox = LogArea(20, 18, 764, 410); page.Controls.Add(diagBox);
            btnDiag = Button("生成脱敏诊断（内存预览）", 20, 440);
            btnDiag.Click += delegate { DoDiagnostics(); };
            page.Controls.Add(btnDiag);
            page.Controls.Add(Note("导出为 UTF-8 无 BOM .txt；room 字段无条件脱敏（不信任 agent 匿名化）。", 20, 482));
            return page;
        }

        private Label FieldLabel(string text, int x, int y)
        {
            var l = new Label(); l.Text = text; l.SetBounds(x, y, 720, 22);
            l.Font = Theme.Small; l.ForeColor = Theme.TextMid; l.AutoSize = false; return l;
        }

        private Label SettingLine(string text, int x, int y)
        {
            var l = new Label(); l.Text = text; l.SetBounds(x, y, 720, 24);
            l.Font = Theme.Body; l.ForeColor = Theme.Ok; l.AutoSize = false; return l;
        }

        private ComboBox Combo()
        {
            var c = new ComboBox();
            c.DropDownStyle = ComboBoxStyle.DropDownList;
            c.FlatStyle = FlatStyle.Flat;
            c.BackColor = Theme.Field;
            c.ForeColor = Theme.TextHi;
            c.Font = Theme.Body;
            return c;
        }

        // Real-room mode is the product default: telling the user to pick one NIC would
        // quietly break every other subnet (Radmin/ZeroTier). Wildcard + IP_PKTINFO pinning
        // is correct for all of them, so preselect 0.0.0.0 when the mode is switched on.
        private void OnRealRoomToggled()
        {
            if (lanIpBox == null) return;
            if (realRoomChk.Checked && lanIpBox.SelectedIndex <= 0)
                lanIpBox.SelectedIndex = 1; // "0.0.0.0"
        }

        private void ApplyRoleDefaults()
        {
            bool host = roleBox.SelectedIndex == 0;
            dllBox.Items.Clear();
            dllBox.Items.Add(host ? "civlink_hook.dll" : "civlink_client.dll");
            dllBox.SelectedIndex = 0;
            ifaceBox.Enabled = !host;
            lanIpBox.Enabled = host;
            if (realRoomChk != null) realRoomChk.Enabled = host;
            if (btnAgentStart != null)
                btnAgentStart.Text = host && realRoomChk != null && realRoomChk.Checked
                    ? "启动发现补全 agent（回真实房间）"
                    : "启动模拟 agent（高级）";
            Log(host ? "A 房主：选 LAN IP 后可启动发现补全 agent，让客户端看到真实房间。" : "B 客户端：选择 --iface（ALL 或本机 IPv4）。");
        }

        private void RefreshProcesses()
        {
            string prev = procBox.SelectedItem as string;
            procBox.Items.Clear();
            var seen = new HashSet<string>();
            foreach (string name in Whitelist.Names)
            {
                foreach (Process p in Process.GetProcessesByName(name))
                {
                    string entry = p.ProcessName + "  (PID " + p.Id + ")";
                    if (seen.Add(entry)) procBox.Items.Add(entry);
                }
            }
            if (procBox.Items.Count > 0) procBox.SelectedIndex = 0;
            else procBox.Items.Add("(未发现白名单进程，请先启动《文明6》Steam Win64)");
            if (prev != null && procBox.Items.Contains(prev)) procBox.SelectedItem = prev;
        }

        // Extracts bare process name from "Name  (PID n)" display.
        private string SelectedProcName()
        {
            string s = procBox.SelectedItem as string;
            if (string.IsNullOrEmpty(s)) return null;
            int i = s.IndexOf("  (PID");
            return i > 0 ? s.Substring(0, i) : s;
        }

        private void DoInject()
        {
            string proc = SelectedProcName();
            if (!Whitelist.Contains(proc)) { Log("[!] 请选择白名单进程，不接受手动 PID。"); return; }
            bool host = roleBox.SelectedIndex == 0;
            string cmd = host ? "inject" : "inject-client";
            string dll = dllBox.SelectedItem as string;
            string iface = (ifaceBox.SelectedItem as string) ?? "ALL";
            try
            {
                string args = CtlRunner.BuildArgs(cmd, proc, dll, iface);
                Log("> civlink_ctl.exe " + args);
                CtlResult r = CtlRunner.Run(cmd, args, Timeouts.For(cmd));
                Log(r.StdOut);
                if (!string.IsNullOrEmpty(r.StdErr)) Log("[err] " + r.StdErr);
                Log("[exit code:" + r.ExitCode + "] " + ExitCodeMapper.Describe(r.ExitCode)
                    + (r.TimedOut ? "  （超时，远程线程状态未知，请导出诊断包）" : ""));
                RefreshTrayState(r.ExitCode);
            }
            catch (Exception ex) { Log("[!] " + ex.Message); }
        }

        private void DoCtl(string cmd, int timeout)
        {
            try
            {
                // N-A: status/counters/shutdown also need -x <whitelist process>, otherwise ctl
                // ResolveTarget() returns exit 2 and these pages always show "target not found".
                string proc = SelectedProcName();
                string args = CtlRunner.BuildArgs(cmd, proc, null, null); // whitelist-validated, throws on bad name
                Log("> civlink_ctl.exe " + args);
                CtlResult r = CtlRunner.Run(cmd, args, timeout);
                string outp = r.StdOut;
                if (cmd == "counters" && r.ExitCode == 4) outp = "(计数数据不可信，已隐藏 — exit 4)";
                if (cmd == "status") statusBox.Text = Redactor.Redact(outp) + "\r\n[exit code:" + r.ExitCode + "] " + ExitCodeMapper.Describe(r.ExitCode);
                else countersBox.Text = Redactor.Redact(outp) + "\r\n[exit code:" + r.ExitCode + "] " + ExitCodeMapper.Describe(r.ExitCode);
                Log("[" + cmd + " exit " + r.ExitCode + "] " + (r.TimedOut ? "超时" : "完成"));
                RefreshTrayState(r.ExitCode);
            }
            catch (Exception ex) { Log("[!] " + ex.Message); }
        }

        private void DoDiagnostics()
        {
            var sb = new StringBuilder();
            sb.AppendLine("CivLink 脱敏诊断包（内存预览，零遥测/零日志）");
            sb.AppendLine("边界：" + Boundary.State + " / " + Boundary.Mechanical);
            sb.AppendLine("--- status ---");
            sb.AppendLine(Redactor.Redact(statusBox.Text));
            sb.AppendLine("--- counters ---");
            sb.AppendLine(Redactor.Redact(countersBox.Text));
            sb.AppendLine("--- operation log ---");
            sb.AppendLine(Redactor.Redact(logBox.Text));
            diagBox.Text = sb.ToString();
            // Actual export: Redactor output only, UTF-8 no BOM, to a user-chosen path (wired in T6).
        }

        private void StartAgent()
        {
            string ip = lanIpBox.SelectedItem as string;
            if (string.IsNullOrEmpty(ip) || ip == "(不启用)") { Log("[!] 模拟 agent 需选择 LAN IP；普通 A 房主无需启动 agent。"); return; }
            if (AgentSupervisor.Port34718InUse()) { Log("[!] IPC 端口 34718 已被占用，拒绝启动第二个 agent。"); return; }
            try
            {
                string exe = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "civlink-agent.exe");
                string od = Path.Combine(Path.GetTempPath(), "civlink-agent-" + Guid.NewGuid().ToString("N").Substring(0, 8));
                Directory.CreateDirectory(od);
                string sf = Path.Combine(od, "stop");
                bool realRoom = realRoomChk != null && realRoomChk.Checked;
                string fixture = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "fixture-reply-set");
                if (!realRoom && !Directory.Exists(fixture))
                {
                    Log("[!] 未找到 fixture-reply-set 目录，无法启动模拟 agent（高级 LAN 模式）。");
                    return;
                }
                string args = AgentSupervisor.BuildArgs(ip, od, sf, realRoom ? null : fixture, realRoom);
                var psi = new ProcessStartInfo(exe, args);
                psi.UseShellExecute = false; psi.CreateNoWindow = true;
                psi.WorkingDirectory = AppDomain.CurrentDomain.BaseDirectory;
                var p = Process.Start(psi);
                agent.OutDir = od; agent.StopFile = sf; agent.Pid = p.Id;
                Log("> civlink-agent.exe " + args + "  (pid " + p.Id + ")");
                Log(realRoom
                    ? "发现补全模式：只应答本机游戏的真实房间；请在游戏里先建房。停止将写入 ASCII stop 文件并等待 20s。"
                    : "模拟模式，非真实对局。停止将写入 ASCII stop 文件并等待 20s。");
            }
            catch (Exception ex) { Log("[!] " + ex.Message); }
        }

        private void RefreshTrayState(int exitCode)
        {
            if (exitCode == 0) { tray.Icon = SystemIcons.Application; tray.Text = "CivLink · 机械动作完成 · " + Boundary.State; }
            else { tray.Icon = SystemIcons.Warning; tray.Text = "CivLink · 操作异常(exit " + exitCode + ") · " + Boundary.State; }
        }

        private void Log(string line)
        {
            logBox.AppendText("[" + DateTime.Now.ToString("HH:mm:ss") + "] " + line + "\r\n");
        }

        private static Label Label(string text, int x, int y)
        {
            var l = new Label(); l.Text = text; l.SetBounds(x, y, 700, 22); l.AutoSize = false; return l;
        }

        // Flat accent button: dark card body, accent tint, no 3D border. Hover/pressed
        // tones are set in-place (FlatAppearance) to keep a single constructor helper.
        private static Button Button(string text, int x, int y)
        {
            var b = new System.Windows.Forms.Button();
            b.Text = text;
            b.SetBounds(x, y, 190, 40);
            b.FlatStyle = FlatStyle.Flat;
            b.FlatAppearance.BorderSize = 1;
            b.FlatAppearance.BorderColor = Theme.Accent;
            b.FlatAppearance.MouseOverBackColor = Theme.AccentDim;
            b.FlatAppearance.MouseDownBackColor = Theme.AccentDim;
            b.BackColor = Theme.Card;
            b.ForeColor = Theme.TextHi;
            b.Font = Theme.Btn;
            b.Cursor = Cursors.Hand;
            return b;
        }

        private static string[] LocalIPv4()
        {
            var list = new List<string>(); list.Add("ALL");
            try
            {
                foreach (var ni in System.Net.NetworkInformation.NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (ni.OperationalStatus != System.Net.NetworkInformation.OperationalStatus.Up) continue;
                    foreach (var ua in ni.GetIPProperties().UnicastAddresses)
                        if (ua.Address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork
                            && !list.Contains(ua.Address.ToString())) list.Add(ua.Address.ToString());
                }
            }
            catch (Exception) { }
            return list.ToArray();
        }
    }

    // ---------------- Headless self-test (T6, no display/game needed) ----------------
    internal static class SelfTest
    {
        private static int checks, failed;
        private static void Check(bool ok, string name)
        {
            checks++; if (!ok) { failed++; Console.WriteLine("FAIL " + name); }
        }

        internal static int Run(string outFile)
        {
            var sb = new StringBuilder();
            // 1. Whitelist
            Check(Whitelist.Contains("CivilizationVI_DX12"), "whitelist dx12");
            Check(!Whitelist.Contains("notepad"), "whitelist rejects notepad");
            Check(!Whitelist.Contains(""), "whitelist rejects empty");
            // 2. Exit code mapping (N-4/T3: exit 4 hides data)
            Check(ExitCodeMapper.Describe(0).Contains("机械"), "exit0 honest");
            Check(ExitCodeMapper.Describe(2).Contains("目标"), "exit2");
            Check(ExitCodeMapper.Describe(4).Contains("不可信"), "exit4 hidden");
            Check(ExitCodeMapper.Describe(99).Contains("未知"), "unknown exit");
            // 3. Redactor (N-1/N-C/N-D): normal room, LAN-only room (no [:=] after "room"),
            //    in-sentence room, username path, and multi-token tag value.
            string sample = "room name : MyPrivateRoom_XYZ\r\n"
                          + "LAN simulated host endpoint=HiddenTokenXYZ\r\n"             // N-C: token has NO "room" keyword -> only the whole-line simulated-host rule (2) masks it
                          + "LAN simulated host room=SecretHostABC\r\n"
                          + "In the sentence the room is SentenceRoomValue here\r\n"      // N-D: in-sentence room
                          + "path C:\\Users\\alice\\x\r\n"
                          + "CIVTRACE_TAG=host value with spaces";                          // N-D: multi-token tag
            string red = Redactor.Redact(sample);
            Check(!red.Contains("MyPrivateRoom_XYZ"), "redact normal room");
            Check(!red.Contains("HiddenTokenXYZ"), "redact LAN-only token (N-C mutation discriminator: only rule (2) catches it)");
            Check(!red.Contains("SecretHostABC"), "redact LAN room (N-1)");
            Check(!red.Contains("SentenceRoomValue"), "redact in-sentence room (N-D)");
            Check(!red.Contains("alice"), "redact username path");
            Check(!red.Contains("with spaces"), "redact multi-token tag (N-D)");
            Check(red.Contains("CIVTRACE_TAG=<redacted>"), "redact tag value");
            // 4. CtlRunner args: A role / B role / guards
            string a = CtlRunner.BuildArgs("inject", "CivilizationVI_DX12", "civlink_hook.dll", null);
            Check(a.StartsWith("inject") && a.Contains("-x \"CivilizationVI_DX12\"") && a.Contains("-m civlink_hook.dll"), "A role args");
            Check(!a.Contains("--reserve-62900"), "reserve is agent-side not ctl");
            string b = CtlRunner.BuildArgs("inject-client", "CivilizationVI", "civlink_client.dll", "192.168.31.214");
            Check(b.Contains("inject-client") && b.Contains("--iface 192.168.31.214"), "B role iface args");
            string ball = CtlRunner.BuildArgs("inject-client", "CivilizationVI", "civlink_client.dll", "ALL");
            Check(ball.Contains("--iface ALL"), "B role ALL");
            // N-A discriminator: ALL five subcommands must carry -x <whitelist proc>.
            string st = CtlRunner.BuildArgs("status", "CivilizationVI_DX12", null, null);
            string co = CtlRunner.BuildArgs("counters", "CivilizationVI_DX12", null, null);
            string sd = CtlRunner.BuildArgs("shutdown", "CivilizationVI_DX12", null, null);
            Check(st.StartsWith("status") && st.Contains("-x \"CivilizationVI_DX12\""), "status carries -x (N-A)");
            Check(co.StartsWith("counters") && co.Contains("-x \"CivilizationVI_DX12\""), "counters carries -x (N-A)");
            Check(sd.StartsWith("shutdown") && sd.Contains("-x \"CivilizationVI_DX12\""), "shutdown carries -x (N-A)");
            bool threw = false; try { CtlRunner.BuildArgs("inject", "notepad", "civlink_hook.dll", null); } catch (Exception) { threw = true; }
            Check(threw, "reject non-whitelist");
            threw = false; try { CtlRunner.BuildArgs("inject-client", "CivilizationVI", "civlink_client.dll", "8.8.8.8;evil"); } catch (Exception) { threw = true; }
            Check(threw, "reject iface injection");
            // N-F: octets > 255 rejected at GUI layer.
            threw = false; try { CtlRunner.BuildArgs("inject-client", "CivilizationVI", "civlink_client.dll", "999.999.999.999"); } catch (Exception) { threw = true; }
            Check(threw, "reject iface octet >255 (N-F)");
            Check(CtlRunner.IsDottedQuad("192.168.31.60") && !CtlRunner.IsDottedQuad("999.1.1.1"), "dotted-quad range check (N-F)");
            // 5. Agent args (N-5/N-2/N-B): advanced LAN path needs --simulate; reserve only with LAN; no 62056.
            string ag = AgentSupervisor.BuildArgs("192.168.31.60", "C:\\od", "C:\\od\\stop", "C:\\fixture-reply-set", false);
            Check(ag.Contains("--sim-lan-listen 192.168.31.60") && ag.Contains("--reserve-62900"), "agent reserve with lan");
            Check(ag.Contains("--simulate \"C:\\fixture-reply-set\""), "agent LAN path carries --simulate (N-B)");
            Check(ag.Contains("--stop-file"), "agent stop-file discipline");
            Check(!ag.Contains("62056"), "agent never binds 62056");
            // M0-E real-room mode: --discovery-completion replaces --simulate (the Agent
            // rejects them together) and never binds 62056.
            string agReal = AgentSupervisor.BuildArgs("192.168.31.60", "C:\\od", "C:\\od\\stop", null, true);
            Check(agReal.Contains("--discovery-completion"), "real-room agent uses --discovery-completion");
            Check(!agReal.Contains("--simulate"), "real-room agent must not pass --simulate (M0-E rejects it)");
            Check(agReal.Contains("--sim-lan-listen 192.168.31.60") && agReal.Contains("--reserve-62900"), "real-room agent reserves 62900");
            Check(!agReal.Contains("62056"), "real-room agent never binds 62056");
            // Wildcard is the real-room default: one bind serves every NIC because the Agent
            // pins each reply to the probed local address (IP_PKTINFO), so the GUI must accept
            // 0.0.0.0 as a valid listen value.
            Check(CtlRunner.IsDottedQuad("0.0.0.0"), "wildcard listen IP accepted");
            string agWild = AgentSupervisor.BuildArgs("0.0.0.0", "C:\\od", "C:\\od\\stop", null, true);
            Check(agWild.Contains("--sim-lan-listen 0.0.0.0") && agWild.Contains("--discovery-completion"), "real-room wildcard listen");
            threw = false; try { AgentSupervisor.BuildArgs(null, "C:\\od", "C:\\od\\stop", null, true); } catch (Exception) { threw = true; }
            Check(!threw, "real-room flag without LAN IP stays a plain agent start");

            // Normal A host path (no LAN IP) must NOT carry sim-lan-listen/reserve/simulate.
            string agNormal = AgentSupervisor.BuildArgs(null, "C:\\od", "C:\\od\\stop", null, false);
            Check(!agNormal.Contains("--sim-lan-listen") && !agNormal.Contains("--reserve-62900") && !agNormal.Contains("--simulate"), "normal A host starts no sim agent (N-B)");
            // 6. Timeouts (N-4): GUI >= ctl internal waits
            Check(Timeouts.Inject >= 20000 && Timeouts.Counters >= 15000 && Timeouts.Shutdown >= 15000, "timeouts >= ctl waits");
            Check(Timeouts.For("counters") == Timeouts.Counters && Timeouts.For("inject") == Timeouts.Inject, "timeout mapping");
            // 7. Boundary wording present
            Check(Boundary.State.Contains("Gate A") && Boundary.Mechanical.Contains("联机"), "boundary wording");
            // 8. Build args use .Arguments not ArgumentList (source-level guard done by compiler on net40)

            sb.AppendLine("CivLink GUI SELFTEST " + (failed == 0 ? "PASS" : "FAIL"));
            sb.AppendLine("checks=" + checks + " failed=" + failed);
            sb.AppendLine("gate=" + Boundary.State);
            if (!string.IsNullOrEmpty(outFile))
            {
                try { File.WriteAllText(outFile, sb.ToString(), new UTF8Encoding(false)); } catch (Exception) { }
            }
            Console.Write(sb.ToString());
            return failed == 0 ? 0 : 1;
        }
    }

    internal static class Program
    {
        [STAThread]
        internal static int Main(string[] args)
        {
            // Headless selftest mode: --selftest <outfile>
            for (int i = 0; i < args.Length; i++)
            {
                if (string.Equals(args[i], "--selftest", StringComparison.OrdinalIgnoreCase))
                {
                    string outFile = (i + 1 < args.Length) ? args[i + 1] : null;
                    return SelfTest.Run(outFile);
                }
            }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
            return 0;
        }
    }
}
