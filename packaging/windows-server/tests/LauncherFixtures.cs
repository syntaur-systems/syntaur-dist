using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Runtime.InteropServices;
using System.Reflection;
using System.Text;
using System.Threading;
using Microsoft.Win32.SafeHandles;

internal static class LauncherFixtures
{
    private const int Port = 18789;
    private static readonly string Base = Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
    private static readonly List<Process> Children = new List<Process>();
    private static readonly List<Evidence> Fakes = new List<Evidence>();
    private static readonly Stopwatch SuiteClock = new Stopwatch();
    private static bool failed;
    private enum ProcessState { Alive, Exited, Unknown }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(SafeProcessHandle handle, uint milliseconds);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool TerminateProcess(SafeProcessHandle handle, uint exitCode);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetProcessTimes(
        SafeProcessHandle process, out FileTime creation, out FileTime exit,
        out FileTime kernel, out FileTime user);

    [StructLayout(LayoutKind.Sequential)]
    private struct FileTime
    {
        internal uint Low;
        internal uint High;
    }

    private sealed class Evidence
    {
        internal int Pid;
        internal DateTime Started;
        internal string Image;
        internal Process Process;
        internal SafeProcessHandle Handle;
    }

    private sealed class Launch
    {
        internal int ExitCode = -1;
        internal long Milliseconds;
        internal bool TimedOut;
        internal Evidence Gateway;
    }

    private static int Main(string[] args)
    {
        try
        {
            string role = Path.GetFileName(Process.GetCurrentProcess().MainModule.FileName);
            Guard(role);
            if (role.Equals("syntaur-viewer.exe", StringComparison.OrdinalIgnoreCase))
            {
                File.WriteAllText(Path.Combine(Base, "viewer-args.txt"), String.Join("\n", args));
                File.WriteAllText(Path.Combine(Base, "viewer-fixture.pid"),
                    Process.GetCurrentProcess().Id.ToString());
                Thread.Sleep(2000);
                return 0;
            }
            if (role.Equals("LauncherFixtures.exe", StringComparison.OrdinalIgnoreCase))
            {
                if (args.Length == 1 && args[0] == "--activation-only")
                    return ActivationDriver();
                if (args.Length == 0)
                    return Driver();
                return 2;
            }
            if (role.Equals("syntaur.exe", StringComparison.OrdinalIgnoreCase) ||
                role.Equals("foreign-fixture.exe", StringComparison.OrdinalIgnoreCase))
                return Gateway(role);
            return 2;
        }
        catch
        {
            return 2;
        }
    }

    private static void Guard(string role)
    {
        using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
        {
            if (identity.User == null || identity.User.IsWellKnown(WellKnownSidType.LocalSystemSid) ||
                new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))
                throw new InvalidOperationException("A standard, unelevated user is required.");
            DirectoryInfo directory = new DirectoryInfo(Base);
            if (directory.Parent == null || (directory.Attributes & FileAttributes.ReparsePoint) != 0 ||
                !directory.Exists || Base.StartsWith(@"\\", StringComparison.Ordinal))
                throw new InvalidOperationException("Unexpected fixture directory.");
            DirectorySecurity security = directory.GetAccessControl();
            if (security.GetOwner(typeof(SecurityIdentifier)) as SecurityIdentifier != identity.User)
                throw new InvalidOperationException("Fixture directory must be user-owned.");
            foreach (FileSystemAccessRule rule in security.GetAccessRules(true, true, typeof(SecurityIdentifier)))
            {
                if (rule.AccessControlType != AccessControlType.Allow ||
                    (rule.FileSystemRights & (FileSystemRights.Write | FileSystemRights.Delete |
                     FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership)) == 0)
                    continue;
                SecurityIdentifier sid = rule.IdentityReference as SecurityIdentifier;
                if (sid != identity.User && !sid.IsWellKnown(WellKnownSidType.LocalSystemSid) &&
                    !sid.IsWellKnown(WellKnownSidType.BuiltinAdministratorsSid))
                    throw new InvalidOperationException("Unexpected fixture directory ACL.");
            }
        }
        string[] files = { "LauncherFixtures.exe", "ServerLauncher.exe", "syntaur.exe",
            "syntaur-viewer.exe", "foreign-fixture.exe", "fixture-mode.txt" };
        foreach (string file in files)
            if (!File.Exists(Path.Combine(Base, file)))
                throw new InvalidOperationException("Incomplete fixture directory.");
        if (!File.Exists(Path.Combine(Base, role)))
            throw new InvalidOperationException("Unexpected fixture role.");
    }

    private static int Gateway(string role)
    {
        string prefix = role.Equals("syntaur.exe", StringComparison.OrdinalIgnoreCase) ? "gateway" : "foreign";
        string pidPath = Path.Combine(Base, prefix + "-fixture.pid");
        string logPath = Path.Combine(Base, prefix + "-fixture.log");
        string invocationPath = Path.Combine(Base, prefix + "-invocation.marker");
        string uiFlagPath = Path.Combine(Base, prefix + "-launcher-ui-flag.txt");
        int pid = Process.GetCurrentProcess().Id;
        int requests = 0;
        string mode = File.ReadAllText(Path.Combine(Base, "fixture-mode.txt")).Trim();
        bool replacement = File.Exists(invocationPath);
        File.WriteAllText(invocationPath, pid.ToString());
        File.AppendAllText(Path.Combine(Base, prefix + "-invocations.log"), pid + "\n");
        File.WriteAllText(uiFlagPath, Environment.GetEnvironmentVariable("SYNTAUR_LAUNCHER_OWNS_UI") ?? "");
        File.WriteAllText(pidPath, pid.ToString());
        File.WriteAllText(logPath, "pid=" + pid + "\nrequests=0\n");
        if (prefix == "gateway" && mode.StartsWith("activation-", StringComparison.Ordinal) && !replacement)
            return ActivationGateway(mode, pid);
        TcpListener listener = new TcpListener(IPAddress.Loopback, Port);
        listener.Start();
        Stopwatch life = Stopwatch.StartNew();
        listener.Server.ReceiveTimeout = 250;
        try
        {
            if (mode == "early-exit")
            {
                Thread.Sleep(250);
                return 0;
            }
            while (life.ElapsedMilliseconds < 45000)
            {
                if (mode == "delayed-ready" && life.ElapsedMilliseconds < 2500)
                {
                    Thread.Sleep(25);
                    continue;
                }
                if (!listener.Pending())
                {
                    Thread.Sleep(25);
                    continue;
                }
                TcpClient client;
                try { client = listener.AcceptTcpClient(); }
                catch (SocketException) { continue; }
                catch (InvalidOperationException) { break; }
                using (client)
                {
                    try
                    {
                        client.ReceiveTimeout = 3000;
                        client.SendTimeout = 3000;
                        NetworkStream stream = client.GetStream();
                        string request = ReadHeaders(stream, life);
                        if (request.Contains(" HTTP/"))
                        {
                            requests++;
                            File.WriteAllText(logPath, "pid=" + pid + "\nrequests=" + requests + "\n");
                        }
                        if (request.StartsWith("GET /health HTTP/", StringComparison.Ordinal))
                            Respond(stream, mode, life);
                    }
                    catch (IOException) { }
                    catch (SocketException) { }
                    catch (ObjectDisposedException) { }
                }
            }
        }
        finally { listener.Stop(); }
        return 0;
    }

    private static int ActivationGateway(string mode, int pid)
    {
        ulong creation;
        using (Process current = Process.GetCurrentProcess())
        {
            FileTime created;
            FileTime exit;
            FileTime kernel;
            FileTime user;
            if (!GetProcessTimes(current.SafeHandle, out created, out exit, out kernel, out user))
                return 2;
            creation = ((ulong)created.High << 32) | created.Low;
        }
        string creationText = creation.ToString("x16", CultureInfo.InvariantCulture);
        File.WriteAllText(Path.Combine(Base, "gateway-creation.txt"), creationText);
        string name = String.Format(CultureInfo.InvariantCulture,
            @"Local\Syntaur.Setup.{0}.{1}", pid, creationText);
        if (mode == "activation-wrong-type")
        {
            using (Mutex wrongType = new Mutex(false, name))
            {
                File.WriteAllText(Path.Combine(Base, "gateway-activation-ready.marker"), "ready");
                Thread.Sleep(90000);
            }
            return 0;
        }

        EventWaitHandleSecurity security = new EventWaitHandleSecurity();
        security.SetAccessRuleProtection(true, false);
        EventWaitHandleRights rights = EventWaitHandleRights.Modify |
            EventWaitHandleRights.ReadPermissions | EventWaitHandleRights.Synchronize;
        using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
        {
            security.AddAccessRule(new EventWaitHandleAccessRule(
                identity.User, rights, AccessControlType.Allow));
            security.AddAccessRule(new EventWaitHandleAccessRule(
                new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
                rights, AccessControlType.Allow));
        }
        bool createdNew;
        using (EventWaitHandle activation = new EventWaitHandle(
            false, EventResetMode.ManualReset, name, out createdNew, security))
        {
            if (!createdNew)
                return 2;
            File.WriteAllText(Path.Combine(Base, "gateway-activation-ready.marker"), "ready");
            if (mode == "activation-timeout")
            {
                Thread.Sleep(90000);
                return 0;
            }
            if (!activation.WaitOne(45000))
                return 8;
            if (mode == "activation-nonzero")
                return 75;
            return 0;
        }
    }

    private static string ReadHeaders(Stream stream, Stopwatch life)
    {
        MemoryStream data = new MemoryStream();
        byte[] one = new byte[1];
        while (data.Length < 8192)
        {
            long remaining = 45000 - life.ElapsedMilliseconds;
            if (remaining <= 0) break;
            stream.ReadTimeout = (int)Math.Min(3000, remaining);
            int count = stream.Read(one, 0, 1);
            if (life.ElapsedMilliseconds >= 45000 || count == 0) break;
            data.WriteByte(one[0]);
            if (data.Length >= 4)
            {
                byte[] bytes = data.GetBuffer();
                long n = data.Length;
                if (bytes[n - 4] == 13 && bytes[n - 3] == 10 && bytes[n - 2] == 13 && bytes[n - 1] == 10)
                    break;
            }
        }
        return Encoding.ASCII.GetString(data.ToArray());
    }

    private static void Respond(Stream stream, string mode, Stopwatch life)
    {
        if (mode == "redirect")
        {
            Write(stream, "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:18789/other\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
            return;
        }
        if (mode == "trickle")
        {
            Write(stream, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n");
            while (life.ElapsedMilliseconds < 45000)
            {
                stream.WriteByte((byte)' ');
                stream.Flush();
                Thread.Sleep(500);
            }
        }
        byte[] body = Encoding.ASCII.GetBytes("{\"status\":\"ok\"}");
        if (mode == "oversized") body = new byte[65537];
        Write(stream, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " +
            body.Length + "\r\nConnection: close\r\n\r\n");
        stream.Write(body, 0, body.Length);
    }

    private static void Write(Stream stream, string text)
    {
        byte[] bytes = Encoding.ASCII.GetBytes(text);
        stream.Write(bytes, 0, bytes.Length);
    }

    private static int Driver()
    {
        SuiteClock.Start();
        TcpListener probe = new TcpListener(IPAddress.Loopback, Port);
        try { probe.Start(); }
        catch { Console.WriteLine("{\"name\":\"preflight\",\"status\":\"FAIL\",\"detail\":\"port 18789 already bound\"}"); return 2; }
        finally { probe.Stop(); }
        Evidence reused = null;
        try
        {
            SetMode("healthy");
            ClearEvidence("gateway");
            Launch first = null;
            Case("fresh-background", delegate
            {
                first = RunLauncher(true);
                Require(first.ExitCode == 0 && first.Gateway != null && Alive(first.Gateway), "gateway did not start cleanly");
                Require(File.ReadAllText(Path.Combine(Base, "gateway-launcher-ui-flag.txt")) == "1",
                    "launcher UI ownership flag was not propagated");
                reused = first.Gateway;
                return Detail(first);
            });
            Case("reuse-same-pid", delegate
            {
                Require(reused != null, "fresh case prerequisite failed");
                Launch second = RunLauncher(true);
                Require(second.ExitCode == 0 && Alive(reused) && second.Gateway != null &&
                    second.Gateway.Pid == reused.Pid, "gateway PID was not reused");
                return Detail(second);
            });
            Case("foreground-viewer", delegate
            {
                Require(reused != null && Alive(reused), "reuse case prerequisite failed");
                Delete("viewer-args.txt"); Delete("viewer-fixture.pid");
                Launch foreground = RunLauncher(false);
                Evidence viewer = WaitForFake("viewer", "syntaur-viewer.exe", 5000);
                Require(foreground.ExitCode == 0 && viewer != null &&
                    File.ReadAllText(Path.Combine(Base, "viewer-args.txt")) == "--local-owner" &&
                    Alive(reused), "viewer arguments or gateway lifetime incorrect");
                return Detail(foreground) + ",viewerPid=" + viewer.Pid;
            });
            Cleanup();
            SetMode("delayed-ready"); ClearEvidence("gateway");
            Case("delayed-http-readiness", delegate
            {
                Launch delayed = RunLauncher(true);
                Require(delayed.ExitCode == 0 && delayed.Gateway != null && Alive(delayed.Gateway) &&
                    delayed.Milliseconds >= 2000 && delayed.Milliseconds < 30000 &&
                    Requests("gateway") >= 2, "delayed HTTP readiness or retry observation incorrect");
                return Detail(delayed) + ",requests=" + Requests("gateway");
            });
            Cleanup();
            SetMode("healthy"); ClearEvidence("foreign"); ClearEvidence("gateway");
            Case("foreign-listener-refusal", delegate
            {
                Process foreign = Start(Path.Combine(Base, "foreign-fixture.exe"), "");
                Evidence listener = WaitForFake("foreign", "foreign-fixture.exe", 5000);
                Require(listener != null && Alive(listener), "foreign fixture did not bind");
                Launch refused = RunLauncher(true);
                Require(refused.ExitCode == 1 && refused.Gateway == null && Requests("foreign") == 0 &&
                    !File.Exists(Path.Combine(Base, "gateway-invocation.marker")) &&
                    !File.Exists(Path.Combine(Base, "gateway-fixture.pid")), "foreign listener was not refused safely");
                Keep(foreign);
                return Detail(refused) + ",foreignRequests=0";
            });
            Cleanup();
            SetMode("early-exit"); ClearEvidence("gateway");
            Case("early-exit-refusal", delegate
            {
                Launch early = RunLauncher(true);
                Require(early.ExitCode == 1 && early.Gateway != null && !Alive(early.Gateway), "early exit was not fenced");
                return Detail(early);
            });
            Cleanup();
            RunNewFailureCase("redirect", "redirect-refusal", 40000, false);
            RunNewFailureCase("oversized", "oversized-health-refusal", 40000, false);
            RunNewFailureCase("trickle", "trickle-hard-deadline", 40000, true);
        }
        catch (Exception error)
        {
            failed = true;
            Console.WriteLine(Json("driver", "FAIL", error.Message));
        }
        finally { Cleanup(); }
        Console.WriteLine(Json("summary", failed ? "FAIL" : "PASS", "elapsedMs=" + SuiteClock.ElapsedMilliseconds));
        return failed ? 1 : 0;
    }

    private static int ActivationDriver()
    {
        SuiteClock.Start();
        try
        {
            SetMode("activation-clean"); ClearEvidence("gateway"); Delete("viewer-fixture.pid");
            Case("activation-clean-drain-one-background-replacement", delegate
            {
                Evidence previous = StartActivationFake();
                Launch launch = RunActivationLauncher(previous.Pid, ActivationCreation());
                Evidence replacement = TryFake("gateway", "syntaur.exe");
                Require(launch.ExitCode == 0 && !Alive(previous) && replacement != null &&
                    Alive(replacement) && replacement.Pid != previous.Pid && ActivationInvocations() == 2 &&
                    File.ReadAllText(Path.Combine(Base, "gateway-launcher-ui-flag.txt")) == "1" &&
                    !File.Exists(Path.Combine(Base, "viewer-fixture.pid")),
                    "clean activation did not produce exactly one background replacement");
                return Detail(launch) + ",replacementPid=" + replacement.Pid + ",viewer=none";
            });
            Cleanup();

            SetMode("activation-nonzero"); ClearEvidence("gateway"); Delete("viewer-fixture.pid");
            Case("activation-nonzero-drain-has-no-replacement", delegate
            {
                Evidence previous = StartActivationFake();
                Launch launch = RunActivationLauncher(previous.Pid, ActivationCreation());
                Require(launch.ExitCode == 1 && !Alive(previous) && ActivationInvocations() == 1 &&
                    !File.Exists(Path.Combine(Base, "viewer-fixture.pid")),
                    "nonzero drain started a replacement or Viewer");
                return Detail(launch) + ",invocations=1,viewer=none";
            });
            Cleanup();

            SetMode("activation-timeout"); ClearEvidence("gateway"); Delete("viewer-fixture.pid");
            Case("activation-timed-out-drain-has-no-replacement", delegate
            {
                Evidence previous = StartActivationFake();
                Launch launch = RunActivationLauncher(previous.Pid, ActivationCreation());
                Require(launch.ExitCode == 1 && Alive(previous) && ActivationInvocations() == 1 &&
                    launch.Milliseconds >= 70000 && launch.Milliseconds <= 85000 &&
                    !File.Exists(Path.Combine(Base, "viewer-fixture.pid")),
                    "timed-out drain started a replacement or Viewer");
                return Detail(launch) + ",invocations=1,viewer=none";
            });
            Cleanup();

            SetMode("activation-clean"); ClearEvidence("gateway"); Delete("viewer-fixture.pid");
            Case("activation-pid-and-start-mismatch-are-refused", delegate
            {
                Evidence previous = StartActivationFake();
                string creation = ActivationCreation();
                Launch wrongPid = RunActivationLauncher(previous.Pid + 1, creation);
                ulong changed = UInt64.Parse(creation, NumberStyles.AllowHexSpecifier,
                    CultureInfo.InvariantCulture) ^ 1UL;
                Launch wrongStart = RunActivationLauncher(previous.Pid,
                    changed.ToString("x16", CultureInfo.InvariantCulture));
                Require(wrongPid.ExitCode == 1 && wrongStart.ExitCode == 1 && Alive(previous) &&
                    ActivationInvocations() == 1 && !File.Exists(Path.Combine(Base, "viewer-fixture.pid")),
                    "PID/start mismatch reached activation");
                return "pidMismatchExit=" + wrongPid.ExitCode + ",startMismatchExit=" + wrongStart.ExitCode;
            });
            Cleanup();

            SetMode("activation-wrong-type"); ClearEvidence("gateway"); Delete("viewer-fixture.pid");
            Case("activation-wrong-type-event-is-refused", delegate
            {
                Evidence previous = StartActivationFake();
                Launch launch = RunActivationLauncher(previous.Pid, ActivationCreation());
                Require(launch.ExitCode == 1 && Alive(previous) && ActivationInvocations() == 1 &&
                    !File.Exists(Path.Combine(Base, "viewer-fixture.pid")),
                    "wrong-type named object was accepted");
                return Detail(launch) + ",invocations=1,viewer=none";
            });
            Cleanup();
        }
        catch (Exception error)
        {
            failed = true;
            Console.WriteLine(Json("activation-driver", "FAIL", error.Message));
        }
        finally { Cleanup(); }
        Console.WriteLine(Json("activation-summary", failed ? "FAIL" : "PASS",
            "elapsedMs=" + SuiteClock.ElapsedMilliseconds));
        return failed ? 1 : 0;
    }

    private static Evidence StartActivationFake()
    {
        Start(Path.Combine(Base, "syntaur.exe"), "");
        Evidence previous = WaitForFake("gateway", "syntaur.exe", 5000);
        Require(previous != null && Alive(previous), "activation fixture did not start");
        Stopwatch clock = Stopwatch.StartNew();
        while (!File.Exists(Path.Combine(Base, "gateway-activation-ready.marker")) && clock.ElapsedMilliseconds < 5000)
            Thread.Sleep(25);
        Require(File.Exists(Path.Combine(Base, "gateway-activation-ready.marker")) &&
            File.Exists(Path.Combine(Base, "gateway-creation.txt")), "activation object was not ready");
        return previous;
    }

    private static string ActivationCreation()
    {
        return File.ReadAllText(Path.Combine(Base, "gateway-creation.txt")).Trim();
    }

    private static int ActivationInvocations()
    {
        return File.ReadAllLines(Path.Combine(Base, "gateway-invocations.log")).Length;
    }

    private static Launch RunActivationLauncher(int pid, string creation)
    {
        Launch result = new Launch();
        Stopwatch clock = Stopwatch.StartNew();
        Process process = Start(Path.Combine(Base, "ServerLauncher.exe"),
            "--after-setup " + pid.ToString(CultureInfo.InvariantCulture) + " " + creation);
        while (!process.WaitForExit(25))
        {
            if (result.Gateway == null) result.Gateway = TryFake("gateway", "syntaur.exe");
            if (clock.ElapsedMilliseconds >= 130000)
            {
                result.TimedOut = true;
                Stop(process.SafeHandle);
                break;
            }
        }
        if (result.Gateway == null) result.Gateway = TryFake("gateway", "syntaur.exe");
        result.ExitCode = result.TimedOut ? -1 : process.ExitCode;
        result.Milliseconds = clock.ElapsedMilliseconds;
        return result;
    }

    private static void RunNewFailureCase(string mode, string name, int bound, bool trickle)
    {
        SetMode(mode); ClearEvidence("gateway");
        Case(name, delegate
        {
            Launch launch = RunLauncher(true);
            Require(launch.ExitCode == 1 && launch.Gateway != null && !Alive(launch.Gateway) &&
                Requests("gateway") == 1, "refusal, request, or child termination incorrect");
            Require(!trickle || (launch.Milliseconds >= 27000 && launch.Milliseconds <= 32000),
                "trickle deadline outside 27-32 seconds");
            return Detail(launch) + ",requests=1";
        });
        Cleanup();
    }

    private static Launch RunLauncher(bool background)
    {
        Launch result = new Launch();
        Stopwatch clock = Stopwatch.StartNew();
        Process process = Start(Path.Combine(Base, "ServerLauncher.exe"), background ? "--background" : "");
        int allowance = (int)Math.Min(40000, Math.Max(1, 150000 - SuiteClock.ElapsedMilliseconds));
        while (!process.WaitForExit(25))
        {
            if (result.Gateway == null) result.Gateway = TryFake("gateway", "syntaur.exe");
            if (clock.ElapsedMilliseconds >= allowance)
            {
                result.TimedOut = true;
                Stop(process.SafeHandle);
                break;
            }
        }
        if (result.Gateway == null) result.Gateway = TryFake("gateway", "syntaur.exe");
        result.ExitCode = result.TimedOut ? -1 : process.ExitCode;
        result.Milliseconds = clock.ElapsedMilliseconds;
        return result;
    }

    private static Process Start(string path, string arguments)
    {
        ProcessStartInfo info = new ProcessStartInfo(path, arguments);
        info.WorkingDirectory = Base;
        info.UseShellExecute = false;
        info.CreateNoWindow = true;
        Process process = Process.Start(info);
        if (process == null) throw new InvalidOperationException("Process.Start returned null.");
        Children.Add(process);
        return process;
    }

    private static Evidence WaitForFake(string prefix, string image, int timeout)
    {
        Stopwatch clock = Stopwatch.StartNew();
        while (clock.ElapsedMilliseconds < timeout && SuiteClock.ElapsedMilliseconds < 150000)
        {
            Evidence evidence = TryFake(prefix, image);
            if (evidence != null) return evidence;
            Thread.Sleep(25);
        }
        return null;
    }

    private static Evidence TryFake(string prefix, string image)
    {
        string path = Path.Combine(Base, prefix + "-fixture.pid");
        int pid;
        Process process = null;
        bool added = false;
        try
        {
            if (!File.Exists(path) || !Int32.TryParse(File.ReadAllText(path).Trim(), out pid)) return null;
            foreach (Evidence known in Fakes)
                if (known.Pid == pid && known.Image.Equals(Path.Combine(Base, image), StringComparison.OrdinalIgnoreCase))
                    return known;
            process = Process.GetProcessById(pid);
            Evidence evidence = new Evidence();
            evidence.Process = process;
            evidence.Handle = process.SafeHandle;
            evidence.Pid = pid;
            string actual = Path.GetFullPath(process.MainModule.FileName);
            DateTime started = process.StartTime;
            string expected = Path.GetFullPath(Path.Combine(Base, image));
            if (!actual.Equals(expected, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Fixture PID image mismatch; refusing to control it.");
            evidence.Started = started;
            evidence.Image = actual;
            Fakes.Add(evidence);
            added = true;
            return evidence;
        }
        catch (InvalidOperationException) { throw; }
        catch { return null; }
        finally
        {
            if (!added && process != null) process.Dispose();
        }
    }

    private static ProcessState State(SafeProcessHandle handle)
    {
        uint result = WaitForSingleObject(handle, 0);
        if (result == 0x102) return ProcessState.Alive;
        if (result == 0) return ProcessState.Exited;
        return ProcessState.Unknown;
    }

    private static bool Alive(Evidence evidence)
    {
        if (evidence == null) return false;
        ProcessState state = State(evidence.Handle);
        if (state == ProcessState.Unknown) throw new InvalidOperationException("Fixture lifetime unknown.");
        return state == ProcessState.Alive;
    }

    private static int Requests(string prefix)
    {
        string[] lines = File.ReadAllLines(Path.Combine(Base, prefix + "-fixture.log"));
        foreach (string line in lines)
            if (line.StartsWith("requests=", StringComparison.Ordinal)) return Int32.Parse(line.Substring(9));
        throw new InvalidOperationException("Missing request count.");
    }

    private static void Case(string name, Func<string> test)
    {
        try
        {
            string detail = test();
            Console.WriteLine(Json(name, "PASS", detail));
        }
        catch (Exception error)
        {
            failed = true;
            Console.WriteLine(Json(name, "FAIL", error.Message));
        }
    }

    private static string Detail(Launch launch)
    {
        return "exit=" + launch.ExitCode + ",elapsedMs=" + launch.Milliseconds +
            (launch.Gateway == null ? "" : ",gatewayPid=" + launch.Gateway.Pid +
            ",gatewayImageVerified=true,gatewayExited=" + !Alive(launch.Gateway));
    }

    private static void Cleanup()
    {
        bool unconfirmed = false;
        foreach (Evidence fake in Fakes)
        {
            try { Stop(fake.Handle); }
            catch { unconfirmed = true; }
        }
        foreach (Process child in Children)
        {
            try { Stop(child.SafeHandle); }
            catch { unconfirmed = true; }
        }
        foreach (Evidence fake in Fakes)
        {
            try { fake.Process.Dispose(); }
            catch { unconfirmed = true; }
        }
        foreach (Process child in Children)
        {
            try { child.Dispose(); }
            catch { unconfirmed = true; }
        }
        Fakes.Clear(); Children.Clear();
        if (unconfirmed)
        {
            failed = true;
            Console.WriteLine(Json("cleanup", "FAIL", "leftovers unconfirmed"));
        }
    }

    private static void Stop(SafeProcessHandle handle)
    {
        ProcessState state = State(handle);
        if (state == ProcessState.Exited) return;
        if (state == ProcessState.Unknown || !TerminateProcess(handle, 1) ||
            WaitForSingleObject(handle, 5000) != 0)
            throw new InvalidOperationException("Child exit unconfirmed.");
    }

    private static void Keep(Process process)
    {
        if (State(process.SafeHandle) != ProcessState.Alive)
            throw new InvalidOperationException("Foreign fixture not confirmed alive.");
    }

    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private static void SetMode(string mode) { File.WriteAllText(Path.Combine(Base, "fixture-mode.txt"), mode); }
    private static void Delete(string file) { string path = Path.Combine(Base, file); if (File.Exists(path)) File.Delete(path); }
    private static void ClearEvidence(string prefix) { Delete(prefix + "-fixture.pid"); Delete(prefix + "-fixture.log"); Delete(prefix + "-invocation.marker"); Delete(prefix + "-launcher-ui-flag.txt"); Delete(prefix + "-invocations.log"); Delete(prefix + "-creation.txt"); Delete(prefix + "-activation-ready.marker"); }

    private static string Json(string name, string status, string detail)
    {
        return "{\"name\":\"" + Escape(name) + "\",\"status\":\"" + status +
            "\",\"detail\":\"" + Escape(detail) + "\"}";
    }

    private static string Escape(string value)
    {
        return value.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n");
    }
}
