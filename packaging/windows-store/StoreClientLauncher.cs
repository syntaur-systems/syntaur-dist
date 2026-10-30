// Pipeline scope: compatibility-channels — native Store layout guard and launcher.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Forms;

internal static class StoreClientLauncher
{
    private static readonly Guid LocalAppDataGuid = new Guid("F1B32785-6FBA-4FCF-9D55-7B8E7F157091");
    private static readonly Guid RoamingAppDataGuid = new Guid("3EB685DB-65F9-4CF6-A03A-E3EF65729F3D");
    private static readonly Guid ProgramsGuid = new Guid("A77F5D77-2E2B-44C3-A6A2-ABA601054A51");
    private static readonly SecurityIdentifier SystemSid = new SecurityIdentifier("S-1-5-18");
    private static readonly SecurityIdentifier AdministratorsSid = new SecurityIdentifier("S-1-5-32-544");
    private static readonly SecurityIdentifier TrustedInstallerSid = new SecurityIdentifier(
        "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464");
    private const FileSystemRights MutatingRights =
        FileSystemRights.WriteData | FileSystemRights.AppendData |
        FileSystemRights.WriteExtendedAttributes | FileSystemRights.WriteAttributes |
        FileSystemRights.DeleteSubdirectoriesAndFiles | FileSystemRights.Delete |
        FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership;
    private const FileSystemRights AncestorMutatingRights =
        FileSystemRights.DeleteSubdirectoriesAndFiles | FileSystemRights.Delete |
        FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership;

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
    private static extern int SHGetKnownFolderPath(ref Guid id, uint flags, IntPtr token, out IntPtr path);

    private static string KnownFolder(Guid id)
    {
        IntPtr buffer;
        int result = SHGetKnownFolderPath(ref id, 0, IntPtr.Zero, out buffer);
        if (result != 0) throw new InvalidOperationException("A required Windows known folder is unavailable.");
        try { return Marshal.PtrToStringUni(buffer); }
        finally { Marshal.FreeCoTaskMem(buffer); }
    }

    private static string Full(string parent, string child)
    {
        return Path.GetFullPath(Path.Combine(parent, child));
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private static WindowsIdentity SupportedIdentity()
    {
        WindowsIdentity identity = WindowsIdentity.GetCurrent();
        Require(identity != null && identity.User != null && identity.Owner != null &&
            identity.User.Value == identity.Owner.Value,
            "A supported non-elevated standard-user token is required.");
        return identity;
    }

    private static bool TrustedOwner(SecurityIdentifier owner, SecurityIdentifier user, bool privateEntry)
    {
        return owner.Equals(user) || (!privateEntry &&
            (owner.Equals(SystemSid) || owner.Equals(AdministratorsSid)));
    }

    private static void ValidateDacl(FileSystemSecurity security, SecurityIdentifier user, bool includeChildren)
    {
        foreach (FileSystemAccessRule rule in security.GetAccessRules(true, true, typeof(SecurityIdentifier)))
        {
            if (rule.AccessControlType != AccessControlType.Allow) continue;
            if (!includeChildren && (rule.PropagationFlags & PropagationFlags.InheritOnly) != 0) continue;
            if ((rule.FileSystemRights & MutatingRights) == 0) continue;
            SecurityIdentifier sid;
            try { sid = (SecurityIdentifier)rule.IdentityReference.Translate(typeof(SecurityIdentifier)); }
            catch { throw new InvalidOperationException("An access-control identity cannot be validated."); }
            Require(sid.Equals(user) || sid.Equals(SystemSid) || sid.Equals(AdministratorsSid),
                "An untrusted principal can modify Syntaur Store files.");
        }
    }

    private static bool EntryExists(string path)
    {
        try { File.GetAttributes(path); return true; }
        catch (FileNotFoundException) { return false; }
        catch (DirectoryNotFoundException) { return false; }
    }

    private static void ValidateEntry(string path, bool directory, bool privateEntry, SecurityIdentifier user)
    {
        FileAttributes attributes = File.GetAttributes(path);
        Require((attributes & FileAttributes.ReparsePoint) == 0, "Reparse points are not accepted: " + path);
        Require(directory == ((attributes & FileAttributes.Directory) != 0),
            "Unexpected file-system entry type: " + path);
        FileSystemSecurity security = directory
            ? (FileSystemSecurity)new DirectoryInfo(path).GetAccessControl()
            : new FileInfo(path).GetAccessControl();
        SecurityIdentifier owner = (SecurityIdentifier)security.GetOwner(typeof(SecurityIdentifier));
        Require(TrustedOwner(owner, user, privateEntry), "Unexpected owner: " + path);
        ValidateDacl(security, user, directory);
    }

    private static void ValidateIfPresent(string path, bool directory, bool privateEntry, SecurityIdentifier user)
    {
        if (EntryExists(path)) ValidateEntry(path, directory, privateEntry, user);
    }

    private static bool TrustedAncestor(SecurityIdentifier sid, SecurityIdentifier user)
    {
        return sid.Equals(user) || sid.Equals(SystemSid) || sid.Equals(AdministratorsSid) ||
            sid.Equals(TrustedInstallerSid);
    }

    private static void ValidateKnownFolderAncestors(string knownFolder, SecurityIdentifier user)
    {
        DirectoryInfo current = new DirectoryInfo(knownFolder);
        while (current != null)
        {
            FileAttributes attributes = File.GetAttributes(current.FullName);
            Require((attributes & FileAttributes.Directory) != 0 &&
                (attributes & FileAttributes.ReparsePoint) == 0,
                "A known-folder ancestor is inaccessible, linked, or not a directory: " + current.FullName);
            DirectorySecurity security = current.GetAccessControl();
            SecurityIdentifier owner = (SecurityIdentifier)security.GetOwner(typeof(SecurityIdentifier));
            Require(TrustedAncestor(owner, user), "Unexpected known-folder ancestor owner: " + current.FullName);
            foreach (FileSystemAccessRule rule in security.GetAccessRules(true, true, typeof(SecurityIdentifier)))
            {
                if (rule.AccessControlType != AccessControlType.Allow ||
                    (rule.PropagationFlags & PropagationFlags.InheritOnly) != 0 ||
                    (rule.FileSystemRights & AncestorMutatingRights) == 0) continue;
                SecurityIdentifier sid;
                try { sid = (SecurityIdentifier)rule.IdentityReference.Translate(typeof(SecurityIdentifier)); }
                catch { throw new InvalidOperationException("An ancestor access-control identity cannot be validated."); }
                Require(TrustedAncestor(sid, user),
                    "An untrusted principal can replace or control a known-folder ancestor: " + current.FullName);
            }
            current = current.Parent;
        }
    }

    private sealed class Layout
    {
        internal string Local, SharedRoot, Container, DataRoot, Bin, Roaming, RoamingRoot;
        internal string Tor, State, Cache, Config, Profile, Viewer, Template, Launcher;
        internal string Programs, Shortcut;
        internal Layout()
        {
            Local = KnownFolder(LocalAppDataGuid);
            SharedRoot = Full(Local, "Syntaur");
            Container = Full(SharedRoot, "Store");
            DataRoot = Full(Container, "Syntaur");
            Bin = Full(DataRoot, "bin");
            Roaming = Full(Container, "Roaming");
            RoamingRoot = Full(Roaming, "Syntaur");
            Tor = Full(DataRoot, "link-tor");
            State = Full(Tor, "state");
            Cache = Full(Tor, "cache");
            Config = Full(Tor, "client.json");
            Profile = Full(RoamingRoot, "link-profile.json");
            Viewer = Full(Bin, "syntaur-viewer.exe");
            Template = Full(Bin, "store-client-template.json");
            Launcher = Full(Bin, "SyntaurConnect.exe");
            Programs = KnownFolder(ProgramsGuid);
            Shortcut = Full(Programs, "Syntaur Connect.lnk");
        }
        internal string[] ProgramFiles()
        {
            return new[] { Launcher, Viewer, Full(Bin, "syntaur-link-client-tor.exe"),
                Full(Bin, "syntaur-link-probe.exe"), Full(Bin, "syntaur-snowflake-client.exe"),
                Template, Full(Bin, "EULA.md") };
        }
    }

    private static void ValidateLayout(Layout layout, SecurityIdentifier user)
    {
        ValidateKnownFolderAncestors(layout.Local, user);
        ValidateKnownFolderAncestors(layout.Programs, user);
        ValidateEntry(layout.Local, true, false, user);
        ValidateEntry(layout.Programs, true, true, user);
        ValidateIfPresent(layout.Shortcut, false, true, user);
        ValidateIfPresent(layout.SharedRoot, true, false, user);
        foreach (string path in new[] { layout.Container, layout.DataRoot, layout.Bin,
            layout.Roaming, layout.RoamingRoot, layout.Tor, layout.State, layout.Cache })
            ValidateIfPresent(path, true, true, user);
        foreach (string path in layout.ProgramFiles()) ValidateIfPresent(path, false, true, user);
        ValidateIfPresent(layout.Config, false, true, user);
        ValidateIfPresent(layout.Profile, false, true, user);
    }

    private static void EnsureDirectory(string path, SecurityIdentifier user)
    {
        if (!EntryExists(path)) Directory.CreateDirectory(path);
        ValidateEntry(path, true, true, user);
    }

    private static void ValidateConfigFile(string path, SecurityIdentifier user)
    {
        ValidateEntry(path, false, true, user);
        FileInfo file = new FileInfo(path);
        Require(file.Length > 0 && file.Length <= 65536, "The existing Store configuration exceeds its bounds.");
    }

    private static void Initialize(Layout layout, SecurityIdentifier user)
    {
        ValidateLayout(layout, user);
        ValidateEntry(layout.Bin, true, true, user);
        ValidateEntry(layout.Viewer, false, true, user);
        ValidateEntry(layout.Template, false, true, user);
        ValidateEntry(Full(layout.Bin, "syntaur-snowflake-client.exe"), false, true, user);
        if (EntryExists(layout.Config)) ValidateConfigFile(layout.Config, user);

        EnsureDirectory(layout.Container, user);
        EnsureDirectory(layout.DataRoot, user);
        EnsureDirectory(layout.Roaming, user);
        EnsureDirectory(layout.RoamingRoot, user);
        EnsureDirectory(layout.Tor, user);
        EnsureDirectory(layout.State, user);
        EnsureDirectory(layout.Cache, user);
        if (EntryExists(layout.Config))
        {
            ValidateConfigFile(layout.Config, user);
            return;
        }

        JavaScriptSerializer serializer = new JavaScriptSerializer();
        FileInfo templateFile = new FileInfo(layout.Template);
        Require(templateFile.Length > 0 && templateFile.Length <= 65536,
            "Store configuration template exceeds its bounds.");
        Dictionary<string, object> configuration =
            serializer.Deserialize<Dictionary<string, object>>(File.ReadAllText(layout.Template, Encoding.UTF8));
        Require(configuration != null && configuration.ContainsKey("bridge_bundle"), "Invalid Store configuration template.");
        configuration["state_dir"] = layout.State;
        configuration["cache_dir"] = layout.Cache;
        configuration["transport_binary"] = Full(layout.Bin, "syntaur-snowflake-client.exe");
        configuration["bundled_transport"] = true;
        byte[] bytes = new UTF8Encoding(false).GetBytes(serializer.Serialize(configuration));
        Require(bytes.Length > 0 && bytes.Length <= 65536, "Generated Store configuration exceeds its bounds.");
        string temporary = Full(layout.Tor, ".client.json." + Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            File.WriteAllBytes(temporary, bytes);
            try { File.Move(temporary, layout.Config); }
            catch (IOException)
            {
                if (!EntryExists(layout.Config)) throw;
            }
            ValidateConfigFile(layout.Config, user);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    private static int Run(string[] args)
    {
        SecurityIdentifier user = SupportedIdentity().User;
        Layout layout = new Layout();
        if (args.Length == 2 && args[0] == "--preflight")
        {
            string requestedFolder = Path.GetFullPath(args[1]).TrimEnd(
                Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            Require(string.Equals(requestedFolder, layout.Bin,
                StringComparison.OrdinalIgnoreCase), "INSTALLFOLDER does not match the fixed Store location.");
            ValidateLayout(layout, user);
            return 0;
        }
        Require(args.Length == 0 || (args.Length == 1 && args[0] == "--initialize-only"),
            "Supported arguments are --preflight INSTALLFOLDER and --initialize-only.");
        string ownPath = Path.GetFullPath(Process.GetCurrentProcess().MainModule.FileName);
        Require(string.Equals(ownPath, layout.Launcher, StringComparison.OrdinalIgnoreCase),
            "The launcher must run from its fixed Store directory.");
        Initialize(layout, user);
        if (args.Length == 1) return 0;

        ProcessStartInfo start = new ProcessStartInfo();
        start.FileName = layout.Viewer;
        start.WorkingDirectory = layout.Bin;
        start.UseShellExecute = false;
        start.Arguments = "";
        start.EnvironmentVariables["LOCALAPPDATA"] = layout.Container;
        start.EnvironmentVariables["APPDATA"] = layout.Roaming;
        Process.Start(start);
        return 0;
    }

    [STAThread]
    private static int Main(string[] args)
    {
        bool silent = args.Length > 0 &&
            (args[0] == "--preflight" || args[0] == "--initialize-only");
        try { return Run(args); }
        catch (Exception error)
        {
            if (!silent) MessageBox.Show(error.Message, "Syntaur Connect",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
