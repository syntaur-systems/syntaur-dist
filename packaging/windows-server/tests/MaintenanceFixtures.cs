using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Threading;

// New maintenance-entry cases only. The Gateway is an owned synthetic process;
// no health listener, product profile, Viewer, service, provider or Tor is used.
internal static class MaintenanceFixtures
{
    private static string DataRoot;
    [StructLayout(LayoutKind.Sequential)] private struct Time { internal uint Low, High; }
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetProcessTimes(IntPtr process, out Time creation, out Time exit, out Time kernel, out Time user);
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool SetKernelObjectSecurity(IntPtr handle, uint information, byte[] descriptor);
    private static void Require(bool condition) { if (!condition) throw new InvalidOperationException("fixture-failed"); }
    private static string Installation { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Syntaur"); } }
    private static string Gateway { get { return Path.Combine(Installation, "syntaur.exe"); } }
    private static string Launcher { get { return Path.Combine(Installation, "ServerLauncher.exe"); } }
    private static void RecordChild(string role, Process child)
    {
        Time created, exit, kernel, user;
        Require(GetProcessTimes(child.Handle, out created, out exit, out kernel, out user));
        File.AppendAllText(Path.Combine(DataRoot, "owners.tsv"), String.Format(CultureInfo.InvariantCulture,
            "{0}\t{1}\t{2:x8}{3:x8}\n", role, child.Id, created.High, created.Low));
    }
    private static EventWaitHandle NewEvent(string name, bool badAcl = false)
    {
        EventWaitHandleSecurity security = new EventWaitHandleSecurity();
        security.SetAccessRuleProtection(true, false);
        EventWaitHandleRights rights = EventWaitHandleRights.Modify | EventWaitHandleRights.ReadPermissions | EventWaitHandleRights.Synchronize;
        using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
        {
            security.SetOwner(identity.User);
            security.AddAccessRule(new EventWaitHandleAccessRule(identity.User, rights, AccessControlType.Allow));
            security.AddAccessRule(new EventWaitHandleAccessRule(new SecurityIdentifier("S-1-5-18"), rights, AccessControlType.Allow));
        }
        if (badAcl) security.AddAccessRule(new EventWaitHandleAccessRule(new SecurityIdentifier("S-1-5-32-545"),
            EventWaitHandleRights.ReadPermissions, AccessControlType.Allow));
        bool created;
        EventWaitHandle result = new EventWaitHandle(false, EventResetMode.ManualReset, name, out created, security);
        if (!created) { result.Dispose(); throw new InvalidOperationException("fixture-event-exists"); }
        return result;
    }
    private static string EventName(string kind, string nonce) { return @"Local\Syntaur.MsiFixture." + kind + "." + nonce; }
    private static int Fake(string mode, string root, string nonce)
    {
        using (EventWaitHandle go = EventWaitHandle.OpenExisting(EventName("go", nonce)))
        using (EventWaitHandle stop = EventWaitHandle.OpenExisting(EventName("stop", nonce)))
        using (Process current = Process.GetCurrentProcess())
        {
            if (!go.WaitOne(10000)) return 90;
            Time creation, exit, kernel, user;
            if (!GetProcessTimes(current.Handle, out creation, out exit, out kernel, out user)) return 91;
            ulong started = ((ulong)creation.High << 32) | creation.Low;
            string activation = String.Format(CultureInfo.InvariantCulture, @"Local\Syntaur.Setup.{0}.{1:x16}", current.Id, started);
            using (EventWaitHandle notification = NewEvent(activation, mode == "bad-acl"))
            {
                if (mode == "inaccessible")
                {
                    using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
                    {
                        // Parent retains its original child handle before go.
                        // New limited-query/synchronize opens must be refused.
                        RawSecurityDescriptor descriptor = new RawSecurityDescriptor("D:P(D;;0x101000;;;" +
                            identity.User.Value + ")(A;;0x1fffff;;;SY)");
                        byte[] bytes = new byte[descriptor.BinaryLength]; descriptor.GetBinaryForm(bytes, 0);
                        if (!SetKernelObjectSecurity(current.Handle, 0x80000004, bytes)) return 92;
                    }
                }
                File.WriteAllText(Path.Combine(root, nonce + ".ready"), "ready");
                int result = WaitHandle.WaitAny(new WaitHandle[] { notification, stop }, 30000);
                if (result == WaitHandle.WaitTimeout) return 93;
                if (result == 1) return 0;
                File.WriteAllText(Path.Combine(root, nonce + ".signalled"), "once");
                return mode == "nonzero" ? 75 : 0;
            }
        }
    }
    private static int StopEntry(EventWaitHandle fakeStop = null)
    {
        ProcessStartInfo info = new ProcessStartInfo(Launcher, "--installer-stop");
        info.UseShellExecute = false; info.CreateNoWindow = true;
        using (Process child = Process.Start(info))
        {
            Require(child != null);
            bool timedOut = false, forced = false;
            try
            {
                IntPtr retained = child.Handle;
                RecordChild("maintenance-helper", child);
                Require(retained != IntPtr.Zero);
                if (!child.WaitForExit(15000)) { timedOut = true; throw new InvalidOperationException("helper-deadline"); }
                return child.ExitCode;
            }
            finally
            {
                // Settle the original helper even on a failed assertion. First
                // release our fake so its pending graceful wait can complete.
                if (!child.HasExited)
                {
                    if (fakeStop != null) fakeStop.Set();
                    if (!child.WaitForExit(80000)) { forced = true; child.Kill(); Require(child.WaitForExit(5000)); }
                }
                Require(!timedOut && !forced);
            }
        }
    }
    private static void Case(string root, string mode, int helperExit, bool mustRemainAlive)
    {
        string nonce = Guid.NewGuid().ToString("N");
        string invocations = Path.Combine(root, "invocations.txt");
        int before = File.Exists(invocations) ? File.ReadAllLines(invocations).Length : 0;
        using (EventWaitHandle go = NewEvent(EventName("go", nonce)))
        using (EventWaitHandle stop = NewEvent(EventName("stop", nonce)))
        {
            ProcessStartInfo info = new ProcessStartInfo(Gateway, "--fake " + mode + " \"" + root + "\" " + nonce);
            info.UseShellExecute = false; info.CreateNoWindow = true;
            using (Process fake = Process.Start(info))
            {
                bool forced = false;
                try
                {
                    Require(fake != null); IntPtr retained = fake.Handle; Require(retained != IntPtr.Zero);
                    RecordChild("fake-Gateway", fake);
                    go.Set(); Stopwatch ready = Stopwatch.StartNew();
                    while (!File.Exists(Path.Combine(root, nonce + ".ready")) && !fake.HasExited && ready.ElapsedMilliseconds < 5000) Thread.Sleep(20);
                    Require(File.Exists(Path.Combine(root, nonce + ".ready")) && !fake.HasExited);
                    int code = StopEntry(stop); Require(code == helperExit);
                    if (mustRemainAlive)
                    {
                        Require(!fake.HasExited && !File.Exists(Path.Combine(root, nonce + ".signalled")));
                        stop.Set(); Require(fake.WaitForExit(5000) && fake.ExitCode == 0);
                    }
                    else
                        Require(fake.WaitForExit(5000) && fake.ExitCode == (mode == "nonzero" ? 75 : 0) &&
                            File.ReadAllText(Path.Combine(root, nonce + ".signalled")) == "once");
                    Require(Process.GetProcessesByName("syntaur").Length == 0);
                    Require(File.ReadAllLines(invocations).Length == before + 1);
                }
                finally
                {
                    if (fake != null && !fake.HasExited)
                    {
                        stop.Set();
                        if (!fake.WaitForExit(5000)) { forced = true; fake.Kill(); Require(fake.WaitForExit(5000)); }
                    }
                    Require(!forced);
                }
            }
        }
    }
    private static int Main(string[] args)
    {
        try
        {
            if (String.Equals(Path.GetFileNameWithoutExtension(Process.GetCurrentProcess().MainModule.FileName), "syntaur", StringComparison.OrdinalIgnoreCase))
            {
                string logRoot = Environment.GetEnvironmentVariable("SYNTAUR_MSI_FIXTURE_ROOT");
                Require(!String.IsNullOrEmpty(logRoot));
                File.AppendAllText(Path.Combine(logRoot, "invocations.txt"), Process.GetCurrentProcess().Id.ToString(CultureInfo.InvariantCulture) + "\n");
            }
            if (args.Length == 4 && args[0] == "--fake") return Fake(args[1], args[2], args[3]);
            using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
                Require(identity.User != null && identity.User.Value.StartsWith("S-1-5-21-", StringComparison.Ordinal) &&
                    !new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator));
            Require(args.Length == 2 && Directory.Exists(args[1]));
            DataRoot = args[1];
            Environment.SetEnvironmentVariable("SYNTAUR_MSI_FIXTURE_ROOT", args[1]);
            if (args[0] == "--missing")
            {
                Require(!File.Exists(Gateway) && Process.GetProcessesByName("syntaur").Length == 0);
                Require(StopEntry() == 0 && !File.Exists(Gateway) && Process.GetProcessesByName("syntaur").Length == 0);
                Console.WriteLine("PASS maintenance-missing-Gateway-repair-no-launch"); return 0;
            }
            Require(args[0] == "--clean" || args[0] == "--nonzero" || args[0] == "--bad-acl" || args[0] == "--inaccessible");
            string mode = args[0].Substring(2);
            Case(args[1], mode, mode == "clean" ? 0 : 1, mode == "bad-acl" || mode == "inaccessible");
            Console.WriteLine("PASS maintenance-" + mode + "-no-replacement-or-forced-kill");
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine("FAIL maintenance " + error.GetType().Name); return 1; }
    }
}
