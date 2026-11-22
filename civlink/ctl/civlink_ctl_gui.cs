// civlink_ctl_gui.cs — CivLink 控制端图形界面（v0.1.0-gui）
// 封装 civlink_ctl.exe 的 inject/status/counters/shutdown 四个子命令。
// 编译：csc.exe /target:winexe /r:System.Windows.Forms.dll /r:System.Drawing.dll civlink_ctl_gui.cs
// 运行需管理员（注入需要 SeDebugPrivilege）；本版未实现自提权，请以管理员身份启动。

using System;
using System.Drawing;
using System.Windows.Forms;
using System.Diagnostics;
using System.Text;
using System.IO;

namespace CivLinkCtlGui
{
    public class MainForm : Form
    {
        private TextBox exeBox;      // 目标进程名
        private TextBox pidBox;      // 目标 pid（留空自动探测）
        private TextBox dllBox;      // 注入 DLL 路径
        private Button btnInject, btnStatus, btnCounters, btnShutdown, btnRefresh;
        private TextBox logBox;      // 输出区
        private Label exeLabel, pidLabel, dllLabel;

        public MainForm()
        {
            Text = "CivLink 控制端 GUI v0.1.0-gui";
            Width = 760; Height = 620; StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Consolas", 9.5f);

            exeLabel = new Label { Text = "目标进程:", Location = new Point(12, 14), AutoSize = true };
            exeBox = new TextBox { Text = "CivilizationVI_DX12.exe", Location = new Point(90, 12), Width = 190 };
            pidLabel = new Label { Text = "PID:", Location = new Point(300, 14), AutoSize = true };
            pidBox = new TextBox { Location = new Point(335, 12), Width = 70 };
            btnRefresh = new Button { Text = "探测进程", Location = new Point(415, 10), Width = 80 };
            dllLabel = new Label { Text = "DLL:", Location = new Point(12, 44), AutoSize = true };
            dllBox = new TextBox { Location = new Point(90, 42), Width = 470 };
            dllBox.Text = Path.Combine(Path.GetDirectoryName(Application.ExecutablePath), "civlink_hook.dll");

            btnInject = new Button { Text = "注入 (inject)", Location = new Point(12, 76), Width = 110, Height = 30 };
            btnStatus = new Button { Text = "状态 (status)", Location = new Point(130, 76), Width = 110, Height = 30 };
            btnCounters = new Button { Text = "计数 (counters)", Location = new Point(248, 76), Width = 110, Height = 30 };
            btnShutdown = new Button { Text = "停止 (shutdown)", Location = new Point(366, 76), Width = 130, Height = 30 };

            logBox = new TextBox { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical,
                Location = new Point(12, 116), Width = 720, Height = 450, AcceptsReturn = true };

            Controls.AddRange(new Control[] { exeLabel, exeBox, pidLabel, pidBox, btnRefresh,
                dllLabel, dllBox, btnInject, btnStatus, btnCounters, btnShutdown, logBox });

            btnInject.Click += (s, e) => RunCtl("inject", "-d", dllBox.Text);
            btnStatus.Click += (s, e) => RunCtl("status");
            btnCounters.Click += (s, e) => RunCtl("counters");
            btnShutdown.Click += (s, e) => RunCtl("shutdown");
            btnRefresh.Click += (s, e) => ProbeProcess();
        }

        private string TargetArgs()
        {
            StringBuilder sb = new StringBuilder();
            sb.Append("-x ").Append(Quote(exeBox.Text.Trim()));
            if (!string.IsNullOrEmpty(pidBox.Text.Trim()))
                sb.Append(" -p ").Append(pidBox.Text.Trim());
            return sb.ToString();
        }

        private static string Quote(string s)
        {
            return "\"" + s.Replace("\"", "\\\"") + "\"";
        }

        private void RunCtl(string cmd, params string[] extra)
        {
            string ctlPath = Path.Combine(Path.GetDirectoryName(Application.ExecutablePath), "civlink_ctl.exe");
            if (!File.Exists(ctlPath))
            {
                AppendLog("[!] civlink_ctl.exe 不在本目录: " + ctlPath);
                return;
            }
            StringBuilder args = new StringBuilder();
            args.Append(cmd).Append(' ').Append(TargetArgs());
            foreach (string a in extra) args.Append(' ').Append(a);

            AppendLog(">>> civlink_ctl.exe " + args.ToString());
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(ctlPath, args.ToString());
                psi.UseShellExecute = false;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                psi.CreateNoWindow = true;
                using (Process p = Process.Start(psi))
                {
                    string stdout = p.StandardOutput.ReadToEnd();
                    string stderr = p.StandardError.ReadToEnd();
                    p.WaitForExit();
                    AppendLog(stdout);
                    if (!string.IsNullOrEmpty(stderr)) AppendLog("[stderr] " + stderr);
                    AppendLog("[exit code: " + p.ExitCode + "]");
                }
            }
            catch (Exception ex)
            {
                AppendLog("[!] " + ex.Message);
            }
        }

        private void ProbeProcess()
        {
            string name = exeBox.Text.Trim();
            if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
                name = name.Substring(0, name.Length - 4);
            Process[] procs = Process.GetProcessesByName(name);
            if (procs.Length == 0)
            {
                AppendLog("[!] 未找到进程: " + name);
                pidBox.Text = "";
                return;
            }
            StringBuilder sb = new StringBuilder();
            foreach (Process p in procs)
                sb.AppendLine(p.Id + " | WS " + Math.Round(p.WorkingSet64 / 1048576.0, 1) + "MB | 启动 " + p.StartTime.ToString("HH:mm:ss"));
            pidBox.Text = procs[0].Id.ToString();
            AppendLog("[*] 找到 " + procs.Length + " 个进程:\n" + sb.ToString().TrimEnd());
        }

        private void AppendLog(string text)
        {
            logBox.AppendText(text);
            if (!text.EndsWith("\n")) logBox.AppendText("\n");
        }
    }

    public static class Program
    {
        [STAThread]
        public static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }
}
