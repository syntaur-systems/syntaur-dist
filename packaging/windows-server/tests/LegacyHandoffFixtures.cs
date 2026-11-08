using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Threading;

// New compatibility handoff only. Refuses an occupied port before creating an
// isolated synthetic Gateway; never opens an installed server or user profile.
internal static class LegacyHandoffFixtures
{
    [StructLayout(LayoutKind.Sequential)] private struct Time { internal uint Low, High; }
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetProcessTimes(IntPtr process, out Time creation, out Time exit, out Time kernel, out Time user);
    private static object Call(string method, params object[] arguments)
    { return typeof(ServerLauncher).GetMethod(method, BindingFlags.Static | BindingFlags.NonPublic).Invoke(null, arguments); }
    private static void Require(bool condition) { if (!condition) throw new Exception("fixture-failed"); }
    private static EventWaitHandle NewEvent(string name, bool bad)
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
        if (bad) security.AddAccessRule(new EventWaitHandleAccessRule(new SecurityIdentifier("S-1-5-32-545"),
            EventWaitHandleRights.ReadPermissions, AccessControlType.Allow));
        bool created;
        EventWaitHandle result = new EventWaitHandle(false, EventResetMode.ManualReset, name, out created, security);
        Require(created); return result;
    }
    private static int Fake(string root, string nonce, bool bad)
    {
        using (Process current = Process.GetCurrentProcess())
        using (EventWaitHandle stop = EventWaitHandle.OpenExisting(@"Local\Syntaur.LegacyFixture.Stop." + nonce))
        {
            Time creation, exit, kernel, user;
            Require(GetProcessTimes(current.Handle, out creation, out exit, out kernel, out user));
            string activation = String.Format(CultureInfo.InvariantCulture, @"Local\Syntaur.Setup.{0}.{1:x16}",
                current.Id, ((ulong)creation.High << 32) | creation.Low);
            TcpListener listener = new TcpListener(IPAddress.Loopback, 18789);
            using (EventWaitHandle notification = NewEvent(activation, bad))
            {
                listener.Start();
                try
                {
                    File.WriteAllText(Path.Combine(root, "ready"), "ready");
                    int reason = WaitHandle.WaitAny(new WaitHandle[] { notification, stop }, 20000);
                    if (reason == 0) File.WriteAllText(Path.Combine(root, "signalled"), "once");
                    return reason == WaitHandle.WaitTimeout ? 90 : 0;
                }
                finally { listener.Stop(); }
            }
        }
    }
    private static void Case(bool bad)
    {
        Require(!(bool)Call("HasAnyPortListener"));
        string root = Path.Combine(Path.GetTempPath(), "syntaur-legacy-handoff-" + Guid.NewGuid().ToString("N"));
        Call("EnsurePrivateDirectory", root);
        Console.WriteLine("OWNED_ROOT " + root);
        string gateway = Path.Combine(root, "syntaur.exe"), shortcut = Path.Combine(root, "startup.lnk");
        string nonce = Guid.NewGuid().ToString("N");
        Process child = null;
        using (EventWaitHandle stop = NewEvent(@"Local\Syntaur.LegacyFixture.Stop." + nonce, false))
        {
            try
            {
                File.Copy(Assembly.GetExecutingAssembly().Location, gateway);
                typeof(LegacyShortcutFixtures).GetMethod("Link", BindingFlags.Static | BindingFlags.NonPublic)
                    .Invoke(null, new object[] { shortcut, gateway, "", root });
                ProcessStartInfo info = new ProcessStartInfo(gateway, "fake \"" + root + "\" " + nonce + " " + (bad ? "bad" : "normal"));
                info.UseShellExecute = false; info.CreateNoWindow = true;
                child = Process.Start(info); Require(child != null);
                Time creation, exit, kernel, user;
                Require(GetProcessTimes(child.Handle, out creation, out exit, out kernel, out user));
                Console.WriteLine(String.Format(CultureInfo.InvariantCulture, "OWNER {0} {1:x8}{2:x8}", child.Id, creation.High, creation.Low));
                Stopwatch wait = Stopwatch.StartNew();
                while (!File.Exists(Path.Combine(root, "ready")) && !child.HasExited && wait.ElapsedMilliseconds < 5000) Thread.Sleep(25);
                Require(File.Exists(Path.Combine(root, "ready")) && !child.HasExited);
                object proof = Call("InspectLegacyShortcut", shortcut, "startup.lnk", root, true);
                Require(proof != null);
                IList proofs = (IList)Activator.CreateInstance(typeof(List<>).MakeGenericType(proof.GetType())); proofs.Add(proof);
                bool refused = false;
                try { Call("DrainLegacyServer", proofs, Stopwatch.StartNew()); }
                catch (TargetInvocationException error)
                {
                    Exception inner = error.InnerException;
                    refused = inner != null && inner.GetType().Name == "LaunchFailure" &&
                        inner.Message == "Syntaur activation notification has unexpected access entries.";
                    if (!refused) throw;
                }
                if (bad) Require(refused && !child.HasExited && !File.Exists(Path.Combine(root, "signalled")));
                else Require(!refused && child.WaitForExit(5000) && child.ExitCode == 0 && File.Exists(Path.Combine(root, "signalled")));
                Console.WriteLine(bad ? "PASS bad-event-acl-refused-no-signal" : "PASS exact-owned-listener-gracefully-drained");
            }
            finally
            {
                bool exited = child == null;
                int code = 0;
                try
                {
                    stop.Set();
                    if (child != null) { exited = child.WaitForExit(5000); if (exited) code = child.ExitCode; }
                }
                finally
                {
                    if (child != null) child.Dispose();
                    if (exited) Directory.Delete(root, true);
                }
                Console.WriteLine("CLEANUP exited=" + exited + " code=" + code + " root_absent=" + !Directory.Exists(root));
                Require(exited && code == 0);
            }
        }
    }
    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            if (args.Length == 4 && args[0] == "fake") return Fake(args[1], args[2], args[3] == "bad");
            Require(args.Length == 0); Case(false); Case(true); return 0;
        }
        catch (Exception error) { Console.WriteLine("FAIL " + error.GetType().Name); return 1; }
    }
}
