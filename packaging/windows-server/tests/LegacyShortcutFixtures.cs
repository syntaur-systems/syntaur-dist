using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;

// Disposable shortcut files only: no server, port, installed aliases or profile.
internal static class LegacyShortcutFixtures
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateHardLink(string path, string existing, IntPtr security);
    private static object Call(string method, params object[] arguments)
    {
        return typeof(ServerLauncher).GetMethod(method, BindingFlags.Static | BindingFlags.NonPublic).Invoke(null, arguments);
    }
    private static void Require(bool condition) { if (!condition) throw new Exception("fixture-failed"); }
    private static void Refuses(Action action)
    {
        bool refused = false;
        try { action(); } catch (TargetInvocationException) { refused = true; }
        Require(refused);
    }
    private static void Link(string path, string target, string arguments, string directory)
    {
        object shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell"));
        object link = null;
        try
        {
            link = shell.GetType().InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { path });
            foreach (object[] field in new[] { new object[] { "TargetPath", target }, new object[] { "Arguments", arguments },
                new object[] { "WorkingDirectory", directory } })
                link.GetType().InvokeMember((string)field[0], BindingFlags.SetProperty, null, link, new object[] { field[1] });
            link.GetType().InvokeMember("Save", BindingFlags.InvokeMethod, null, link, new object[0]);
        }
        finally
        {
            if (link != null) Marshal.FinalReleaseComObject(link);
            Marshal.FinalReleaseComObject(shell);
        }
    }
    [STAThread]
    private static int Main()
    {
        string root = Path.Combine(Path.GetTempPath(), "syntaur-legacy-fixture-" + Guid.NewGuid().ToString("N"));
        try
        {
            Call("EnsurePrivateDirectory", root);
            string profile = Path.Combine(root, "profile"), privateRoot = Path.Combine(profile, ".syntaur");
            Call("EnsurePrivateDirectory", profile); Call("EnsurePrivateDirectory", privateRoot);
            string directory = Path.Combine(root, "legacy"); Call("EnsurePrivateDirectory", directory);
            string gateway = Path.Combine(directory, "syntaur.exe"), viewer = Path.Combine(directory, "syntaur-viewer.exe");
            File.WriteAllText(gateway, "fixture"); File.WriteAllText(viewer, "fixture");
            string startup = Path.Combine(root, "startup.lnk"), app = Path.Combine(root, "app.lnk");
            Link(startup, gateway, "", directory); Link(app, viewer, "--local-owner", directory);
            object proof = Call("InspectLegacyShortcut", startup, "startup.lnk", directory, true);
            Require(proof != null && Call("InspectLegacyShortcut", app, "programs.lnk", directory, false) != null);
            Console.WriteLine("PASS exact-raw-shell-fields");
            Link(app, viewer, "--remote-client", directory);
            Require(Call("InspectLegacyShortcut", app, "programs.lnk", directory, false) == null);
            Require(Call("InspectLegacyShortcut", Path.Combine(root, "absent.lnk"), "absent.lnk", directory, false) == null);
            Console.WriteLine("PASS custom-and-absent-untouched");
            byte[] original = File.ReadAllBytes(startup);
            Call("RetireLegacyShortcut", proof, profile);
            string backup = Path.Combine(privateRoot, "legacy-server-shortcuts", "startup.lnk");
            Require(!File.Exists(startup) && Convert.ToBase64String(File.ReadAllBytes(backup)) == Convert.ToBase64String(original));
            Require(!Directory.Exists(Path.Combine(root, "Startup")));
            Console.WriteLine("PASS retained-original-outside-startup");
            Link(startup, gateway, "", directory);
            proof = Call("InspectLegacyShortcut", startup, "startup.lnk", directory, true);
            object collision = proof;
            Refuses(delegate { Call("RetireLegacyShortcut", collision, profile); });
            Require(File.Exists(startup) && Convert.ToBase64String(File.ReadAllBytes(backup)) == Convert.ToBase64String(original));
            Console.WriteLine("PASS backup-collision-preserves-both");
            proof = Call("InspectLegacyShortcut", startup, "changed.lnk", directory, true);
            File.AppendAllText(startup, "changed"); object changed = proof;
            Refuses(delegate { Call("RetireLegacyShortcut", changed, profile); });
            Require(File.Exists(startup) && !File.Exists(Path.Combine(Path.GetDirectoryName(backup), "changed.lnk")));
            Console.WriteLine("PASS changed-source-refused");
            string hard = Path.Combine(root, "hard.lnk"); Require(CreateHardLink(hard, startup, IntPtr.Zero));
            Refuses(delegate { Call("InspectLegacyShortcut", hard, "hard.lnk", directory, true); });
            Console.WriteLine("PASS hardlink-refused");
            return 0;
        }
        catch (Exception error)
        {
            while (error is TargetInvocationException && error.InnerException != null) error = error.InnerException;
            System.ComponentModel.Win32Exception native = error as System.ComponentModel.Win32Exception;
            Console.WriteLine("FAIL " + error.GetType().Name + (native == null ? "" : " native=" + native.NativeErrorCode));
            return 1;
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
}
