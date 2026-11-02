using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Threading.Tasks;

// Compile with the actual launcher source and /main:HostBindingFixtures.
// No Gateway, Viewer, service command, provider or network request is made.
internal static class HostBindingFixtures
{
    private static readonly string[] Names = {
        "SYNTAUR_LINK_TOR_SERVICE_SID", "SYNTAUR_LINK_TOR_SOCKET",
        "SYNTAUR_LINK_TOR_GATEWAY_PIN"
    };
    private static readonly MethodInfo Bind = typeof(ServerLauncher).GetMethod(
        "SetHostEnvironment", BindingFlags.Static | BindingFlags.NonPublic);
    private static SecurityIdentifier user;
    private static SecurityIdentifier service;
    private static string data;

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private static void Apply(ProcessStartInfo child, string root,
        SecurityIdentifier owner, SecurityIdentifier host)
    {
        Bind.Invoke(null, new object[] { child, root, owner, host });
    }

    private static void Expected(ProcessStartInfo child)
    {
        Require(child.EnvironmentVariables[Names[0]] == service.Value, "service binding differs");
        Require(child.EnvironmentVariables[Names[1]] == @"\\.\pipe\Syntaur.Link.host." + user.Value,
            "pipe binding differs");
        Require(child.EnvironmentVariables[Names[2]] == Path.Combine(data, "Syntaur", "LinkTor",
            "shared", user.Value, "gateway-pin.json"), "pin binding differs");
    }

    private static void Refused(string root, SecurityIdentifier owner, SecurityIdentifier host)
    {
        ProcessStartInfo child = new ProcessStartInfo();
        foreach (string name in Names) child.EnvironmentVariables[name] = "unchanged";
        bool rejected = false;
        try { Apply(child, root, owner, host); }
        catch (TargetInvocationException error)
        {
            Require(error.InnerException.GetType().Name == "LaunchFailure", "unexpected refusal");
            rejected = true;
        }
        Require(rejected, "unsafe binding was accepted");
        foreach (string name in Names)
            Require(child.EnvironmentVariables[name] == "unchanged", "partial child mutation");
    }

    private static void ChildInheritance()
    {
        string[] before = new string[Names.Length];
        for (int i = 0; i < Names.Length; i++)
        {
            before[i] = Environment.GetEnvironmentVariable(Names[i]);
            Environment.SetEnvironmentVariable(Names[i], "poisoned-parent");
        }
        try
        {
            ProcessStartInfo child = new ProcessStartInfo(
                Assembly.GetExecutingAssembly().Location, "--child");
            child.UseShellExecute = false;
            child.CreateNoWindow = true;
            child.RedirectStandardOutput = true;
            child.RedirectStandardError = true;
            Apply(child, data, user, service);
            Expected(child);
            // A separate future Viewer still inherits the unchanged parent.
            ProcessStartInfo viewer = new ProcessStartInfo();
            foreach (string name in Names)
            {
                Require(Environment.GetEnvironmentVariable(name) == "poisoned-parent",
                    "parent environment changed");
                Require(viewer.EnvironmentVariables[name] == "poisoned-parent",
                    "other child environment changed");
            }
            using (Process process = Process.Start(child))
            {
                Require(process != null, "owned child was not created");
                Task<string> output = null;
                Task<string> error = null;
                bool forced = false;
                try
                {
                    output = process.StandardOutput.ReadToEndAsync();
                    error = process.StandardError.ReadToEndAsync();
                    if (!process.WaitForExit(10000))
                        forced = true;
                }
                finally
                {
                    try
                    {
                        if (!process.HasExited)
                        {
                            forced = true;
                            process.Kill();
                            Require(process.WaitForExit(5000), "owned child cleanup unconfirmed");
                        }
                    }
                    finally
                    {
                        if (process.HasExited)
                        {
                            bool outputDone = Settle(output);
                            bool errorDone = Settle(error);
                            Require(outputDone && errorDone, "owned output drain unconfirmed");
                        }
                    }
                }
                Require(!forced && process.ExitCode == 0, "owned child failed or timed out");
                Require(output.Result.Trim() == "CHILD_BINDINGS_PASS" && error.Result.Length == 0,
                    "actual child did not receive the bindings");
            }
        }
        finally
        {
            for (int i = 0; i < Names.Length; i++)
                Environment.SetEnvironmentVariable(Names[i], before[i]);
        }
    }

    private static bool Settle(Task<string> task)
    {
        if (task == null) return true;
        try { return task.Wait(5000); }
        catch (AggregateException) { return false; }
    }

    internal static int Main(string[] args)
    {
        try
        {
            using (WindowsIdentity current = WindowsIdentity.GetCurrent()) user = current.User;
            service = (SecurityIdentifier)new NTAccount(@"NT SERVICE\SyntaurLinkTor")
                .Translate(typeof(SecurityIdentifier));
            data = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
            if (args.Length == 1 && args[0] == "--child")
            {
                ProcessStartInfo inherited = new ProcessStartInfo();
                Expected(inherited);
                Console.WriteLine("CHILD_BINDINGS_PASS");
                return 0;
            }
            Require(args.Length == 0, "unsupported fixture request");
            typeof(ServerLauncher).GetMethod("ValidateCurrentUser",
                BindingFlags.Static | BindingFlags.NonPublic).Invoke(null, null);
            ChildInheritance();
            Console.WriteLine("PASS actual-child-bindings-parent-and-Viewer-unchanged");
            foreach (string root in new string[] { null, "", " ", "relative", "C:relative", @"\\server\share" })
                Refused(root, user, service);
            Console.WriteLine("PASS six-invalid-roots-no-partial-mutation");
            Refused(data, null, service);
            Refused(data, user, null);
            Refused(data, user, user);
            Refused(data, user, new SecurityIdentifier("S-1-5-18"));
            Refused(data, user, new SecurityIdentifier("S-1-5-80-0"));
            Console.WriteLine("PASS five-invalid-identities-no-partial-mutation");
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine("FAIL " + error.GetType().Name);
            return 1;
        }
    }
}
