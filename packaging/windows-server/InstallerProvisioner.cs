// Standard MSI deferred/rollback/commit filesystem actions. No service control,
// process launch, network access, enrollment, or deletion of existing user data.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Web.Script.Serialization;
using Microsoft.Win32.SafeHandles;

internal static class InstallerProvisioner
{
    private const uint Full = 0x1f01ff, Read = 0x120089, Execute = 0x1200a9;
    private const uint ReadControl = 0x20000, WriteDac = 0x40000, WriteOwner = 0x80000;
    private const uint Delete = 0x10000, OpenExisting = 3, CreateNew = 1;
    private const uint NoFollow = 0x200000, DirectoryFlag = 0x2000000;
    private const int MaximumRecord = 65536;
    private static readonly SecurityIdentifier SystemSid = new SecurityIdentifier("S-1-5-18");
    private static readonly SecurityIdentifier AdminSid = new SecurityIdentifier("S-1-5-32-544");
    private static readonly SecurityIdentifier InstallerSid = new SecurityIdentifier(
        "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464");
    private static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = MaximumRecord };
    private static readonly string[] ProgramFiles = { "ServerLauncher.exe", "syntaur.exe", "syntaur-viewer.exe",
        "syntaur-link-tor.exe", "syntaur-link-client-tor.exe", "syntaur-link-probe.exe",
        "syntaur-snowflake-client.exe", "EULA.md" };

    [StructLayout(LayoutKind.Sequential)] private struct SecurityAttributes
    { internal int Length; internal IntPtr Descriptor; internal int Inherit; }
    [StructLayout(LayoutKind.Sequential)] private struct FileInfo
    {
        internal uint Attributes; internal System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
        internal uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }
    [StructLayout(LayoutKind.Sequential)] private struct Disposition { internal byte DeleteFile; }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(string path, uint access, uint share,
        IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateDirectory(string path, ref SecurityAttributes security);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle file, out FileInfo info);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetFileInformationByHandle(SafeFileHandle file, int type, ref Disposition info, uint size);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetFileInformationByHandle(SafeFileHandle file, int type, IntPtr info, uint size);
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern uint GetSecurityInfo(SafeFileHandle handle, uint type, uint information,
        out IntPtr owner, IntPtr group, out IntPtr dacl, IntPtr sacl, out IntPtr descriptor);
    [DllImport("advapi32.dll")] private static extern uint GetSecurityDescriptorLength(IntPtr descriptor);
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool GetSecurityDescriptorOwner(IntPtr descriptor, out IntPtr owner, out bool defaulted);
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool GetSecurityDescriptorDacl(IntPtr descriptor, out bool present, out IntPtr dacl, out bool defaulted);
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern uint SetSecurityInfo(SafeFileHandle handle, uint type, uint information,
        IntPtr owner, IntPtr group, IntPtr dacl, IntPtr sacl);
    [DllImport("kernel32.dll")] private static extern IntPtr LocalFree(IntPtr memory);
    [StructLayout(LayoutKind.Sequential)] private struct TokenPrivilege
    { internal uint Count, Low; internal int High; internal uint Attributes; }
    [DllImport("kernel32.dll")] private static extern IntPtr GetCurrentProcess();
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr process, uint access, out SafeFileHandle token);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool LookupPrivilegeValue(string system, string name, out long luid);
    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool AdjustTokenPrivileges(SafeFileHandle token, bool disableAll,
        ref TokenPrivilege state, uint size, out TokenPrivilege previous, out uint required);

    private sealed class RestorePrivilege : IDisposable
    {
        private SafeFileHandle token;
        private TokenPrivilege previous;
        internal RestorePrivilege()
        {
            long luid;
            if (!OpenProcessToken(GetCurrentProcess(), 0x28, out token)) throw new IOException("open-restore-token");
            try
            {
                if (!LookupPrivilegeValue(null, "SeRestorePrivilege", out luid)) throw new IOException("resolve-restore-privilege");
                TokenPrivilege request = new TokenPrivilege { Count = 1, Low = (uint)luid, High = (int)(luid >> 32), Attributes = 2 };
                uint required;
                if (!AdjustTokenPrivileges(token, false, ref request, (uint)Marshal.SizeOf(typeof(TokenPrivilege)), out previous, out required) ||
                    Marshal.GetLastWin32Error() != 0) throw new IOException("enable-restore-privilege");
            }
            catch { token.Dispose(); throw; }
        }
        public void Dispose()
        {
            TokenPrivilege ignored; uint required;
            try
            {
                if (!AdjustTokenPrivileges(token, false, ref previous, (uint)Marshal.SizeOf(typeof(TokenPrivilege)), out ignored, out required) ||
                    Marshal.GetLastWin32Error() != 0) throw new IOException("restore-token-privilege");
            }
            finally { token.Dispose(); }
        }
    }

    // The only durable temporary state is the normal MSI rollback preimage.
    // It contains fixed paths and file identities, never keys or profile data.
    public sealed class Record
    {
        public string Product, IncomingOwner, ProgramDirectoryIdentity;
        public string Gateway;
        public List<Created> Created = new List<Created>();
    }
    public sealed class Created
    { public string Path, Identity, Hash; public bool Directory; }

    private sealed class Pin : IDisposable
    {
        internal readonly SafeFileHandle Handle;
        internal readonly string Path;
        internal readonly bool Directory;
        internal readonly string Identity;
        private FileStream reader;
        internal Pin(string path, bool directory, uint extra, uint creation = OpenExisting, IntPtr security = default(IntPtr), uint share = 3)
        {
            Path = path; Directory = directory;
            Handle = CreateFile(path, ReadControl | 0x80 | extra, share, security, creation,
                NoFollow | (directory ? DirectoryFlag : 0), IntPtr.Zero);
            if (Handle.IsInvalid)
            {
                int error = Marshal.GetLastWin32Error(); Handle.Dispose();
                if (error == 2 || error == 3) throw new FileNotFoundException("owned-object-absent");
                throw new IOException("open-owned-path");
            }
            try
            {
                FileInfo info;
                if (!GetFileInformationByHandle(Handle, out info) || (info.Attributes & 0x400) != 0 ||
                    ((info.Attributes & 0x10) != 0) != directory || (!directory && info.Links != 1))
                    throw new IOException("path-type-or-reparse");
                Identity = String.Format(CultureInfo.InvariantCulture, "{0:x8}:{1:x8}{2:x8}", info.Volume, info.IndexHigh, info.IndexLow);
            }
            catch { Handle.Dispose(); throw; }
        }
        internal RawSecurityDescriptor Security()
        {
            IntPtr owner, acl, raw;
            uint result = GetSecurityInfo(Handle, 1, 5, out owner, IntPtr.Zero, out acl, IntPtr.Zero, out raw);
            if (result != 0 || raw == IntPtr.Zero) throw new IOException("read-security");
            try
            {
                uint length = GetSecurityDescriptorLength(raw);
                if (length < 20 || length > MaximumRecord) throw new IOException("security-size");
                byte[] bytes = new byte[length]; Marshal.Copy(raw, bytes, 0, bytes.Length);
                return new RawSecurityDescriptor(bytes, 0);
            }
            finally { LocalFree(raw); }
        }
        internal void SetSecurity(string sddl)
        {
            byte[] bytes = new byte[new RawSecurityDescriptor(sddl).BinaryLength];
            new RawSecurityDescriptor(sddl).GetBinaryForm(bytes, 0);
            GCHandle memory = GCHandle.Alloc(bytes, GCHandleType.Pinned);
            try
            {
                IntPtr owner, acl; bool defaulted, present;
                if (!GetSecurityDescriptorOwner(memory.AddrOfPinnedObject(), out owner, out defaulted) || defaulted ||
                    !GetSecurityDescriptorDacl(memory.AddrOfPinnedObject(), out present, out acl, out defaulted) ||
                    !present || defaulted || SetSecurityInfo(Handle, 1, 0x80000005, owner, IntPtr.Zero, acl, IntPtr.Zero) != 0)
                    throw new IOException("set-owned-security");
            }
            finally { memory.Free(); }
        }
        internal byte[] ReadBytes()
        {
            // Keep the stream and its handle alive until Pin.Dispose, including
            // identity/content-checked rollback deletion on the same handle.
            if (reader == null) reader = new FileStream(Handle, FileAccess.Read);
            FileStream stream = reader;
            stream.Position = 0;
            {
                if (stream.Length > MaximumRecord) throw new IOException("record-size");
                byte[] result = new byte[(int)stream.Length]; int count = 0;
                while (count < result.Length) { int n = stream.Read(result, count, result.Length - count); if (n == 0) throw new IOException("short-record"); count += n; }
                if (stream.ReadByte() != -1) throw new IOException("growing-record");
                return result;
            }
        }
        internal void WriteBytes(byte[] bytes)
        {
            WriteContent(delegate(Stream stream) { stream.Write(bytes, 0, bytes.Length); });
        }
        internal void WriteContent(Action<Stream> write)
        {
            if (reader != null) throw new IOException("file-already-read");
            reader = new FileStream(Handle, FileAccess.ReadWrite);
            write(reader); reader.Flush(true);
        }
        internal void RemoveEmpty()
        {
            Disposition disposition = new Disposition { DeleteFile = 1 };
            if (!SetFileInformationByHandle(Handle, 4, ref disposition, 1)) throw new IOException("remove-created-object");
        }
        public void Dispose() { if (reader != null) reader.Dispose(); Handle.Dispose(); }
    }

    private static string Sddl(SecurityIdentifier owner, params string[] entries)
    { return "O:" + owner.Value + "G:SYD:P" + String.Join("", entries); }
    private static string Ace(SecurityIdentifier sid, uint rights, bool directory)
    { return "(A;" + (directory ? "OICI" : "") + ";0x" + rights.ToString("x", CultureInfo.InvariantCulture) + ";;;" + sid.Value + ")"; }
    private static string Admin(SecurityIdentifier service, SecurityIdentifier gateway, bool directory)
    {
        List<string> entries = new List<string> { Ace(SystemSid, Full, directory), Ace(AdminSid, Full, directory),
            Ace(service, directory || gateway != null ? Execute : Read, directory) };
        if (gateway != null) entries.Add(Ace(gateway, Execute, directory));
        return Sddl(SystemSid, entries.ToArray());
    }
    private static string Private(SecurityIdentifier owner, SecurityIdentifier service, bool shared)
    {
        List<string> entries = new List<string> { Ace(owner, Full, true), Ace(SystemSid, Full, true) };
        if (shared) entries.Add(Ace(service, Execute, true));
        return Sddl(owner, entries.ToArray());
    }
    private static string JournalSecurity() { return Sddl(SystemSid, Ace(SystemSid, Full, false), Ace(AdminSid, Full, false)); }
    private static void RequireSecurity(Pin file, string expected, bool allowInheritedFile = false)
    {
        RawSecurityDescriptor actual = file.Security(), required = new RawSecurityDescriptor(expected);
        bool ownerMatches = actual.Owner == required.Owner || (required.Owner == SystemSid && actual.Owner == AdminSid);
        if (!ownerMatches || (!allowInheritedFile && (actual.ControlFlags & ControlFlags.DiscretionaryAclProtected) == 0) ||
            actual.DiscretionaryAcl == null || actual.DiscretionaryAcl.Count != required.DiscretionaryAcl.Count)
            throw new IOException("unexpected-owner-or-acl");
        HashSet<string> entries = new HashSet<string>(StringComparer.Ordinal);
        foreach (GenericAce ace in required.DiscretionaryAcl) entries.Add(AceBytes(ace));
        foreach (GenericAce ace in actual.DiscretionaryAcl)
        {
            GenericAce comparison = ace.Copy();
            if (allowInheritedFile) comparison.AceFlags &= ~AceFlags.Inherited;
            if (!entries.Remove(AceBytes(comparison))) throw new IOException("unexpected-access-entry");
        }
        if (entries.Count != 0) throw new IOException("missing-access-entry");
    }
    private static string AceBytes(GenericAce ace)
    { byte[] bytes = new byte[ace.BinaryLength]; ace.GetBinaryForm(bytes, 0); return Convert.ToBase64String(bytes); }
    private static void RequireAdminControlled(Pin file, bool ancestorOnly = false)
    {
        RawSecurityDescriptor security = file.Security();
        if (security.Owner != SystemSid && security.Owner != AdminSid && security.Owner != InstallerSid)
            throw new IOException("untrusted-installation-owner");
        if (security.DiscretionaryAcl == null) throw new IOException("unrestricted-installation-acl");
        foreach (GenericAce entry in security.DiscretionaryAcl)
        {
            CommonAce ace = entry as CommonAce;
            if (ace == null || ace.AceQualifier != AceQualifier.AccessAllowed) throw new IOException("unsupported-installation-ace");
            if ((ace.AceFlags & AceFlags.InheritOnly) != 0) continue;
            // OS known folders may let users create new children. They must
            // never let users replace this retained directory or its children.
            int mutation = ancestorOnly ? 0x100d0040 : 0x500d0156;
            if ((ace.AccessMask & mutation) != 0 && ace.SecurityIdentifier != SystemSid &&
                ace.SecurityIdentifier != AdminSid && ace.SecurityIdentifier != InstallerSid)
                throw new IOException("untrusted-installation-writer");
        }
    }
    private static string Known(Environment.SpecialFolder folder)
    {
        string path = Environment.GetFolderPath(folder);
        if (path.Length < 3 || path[1] != ':' || path[2] != '\\' || Path.GetFullPath(path) != path)
            throw new IOException("nonlocal-known-folder");
        return path;
    }
    private static SecurityIdentifier Owner(string sid)
    {
        SecurityIdentifier owner = new SecurityIdentifier(sid);
        if (owner.Value != sid || !sid.StartsWith("S-1-5-21-", StringComparison.Ordinal) || sid.Split('-').Length != 8)
            throw new IOException("invalid-server-owner");
        return owner;
    }
    private static void RequireSystem()
    {
        using (WindowsIdentity current = WindowsIdentity.GetCurrent())
            if (current.User != SystemSid) throw new IOException("requires-msi-system-action");
    }
    private static T WithSecurity<T>(string sddl, Func<IntPtr, T> action)
    {
        RawSecurityDescriptor descriptor = new RawSecurityDescriptor(sddl);
        byte[] bytes = new byte[descriptor.BinaryLength]; descriptor.GetBinaryForm(bytes, 0);
        GCHandle buffer = GCHandle.Alloc(bytes, GCHandleType.Pinned);
        IntPtr memory = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(SecurityAttributes)));
        try
        {
            SecurityAttributes attrs = new SecurityAttributes { Length = Marshal.SizeOf(typeof(SecurityAttributes)), Descriptor = buffer.AddrOfPinnedObject() };
            Marshal.StructureToPtr(attrs, memory, false); return action(memory);
        }
        finally { Marshal.FreeHGlobal(memory); buffer.Free(); }
    }
    private static Pin NewFile(string path, string security)
    { return WithSecurity(security, delegate(IntPtr attributes) { return new Pin(path, false, 0xc0000000 | Delete, CreateNew, attributes); }); }
    private sealed class RenameFailure : IOException
    {
        internal readonly int NativeCode;
        internal RenameFailure(int code) : base("publish-owned-file") { NativeCode = code; }
    }
    private static void Rename(Pin file, string path, bool replace)
    {
        byte[] name = Encoding.Unicode.GetBytes(path);
        IntPtr rename = Marshal.AllocHGlobal(24 + name.Length);
        try
        {
            InitializeRenameBuffer(rename, name, replace);
            if (!SetFileInformationByHandle(file.Handle, replace ? 22 : 3, rename, (uint)(24 + name.Length)))
                throw new RenameFailure(Marshal.GetLastWin32Error());
        }
        finally { Marshal.FreeHGlobal(rename); }
    }
    private static void InitializeRenameBuffer(IntPtr rename, byte[] name, bool replace)
    {
        // AllocHGlobal is not zero-filled. Include the trailing WCHAR and
        // padding so Win32 always receives a terminated filename; its byte
        // length still excludes that terminator.
        for (int i = 0; i < 24 + name.Length; i++) Marshal.WriteByte(rename, i, 0);
        // Reuse the HOST's Windows rename contract. Legacy replacement
        // refuses the retained destination handle even with delete sharing;
        // FileRenameInfoEx supplies POSIX replacement for that exact case.
        Marshal.WriteInt32(rename, 0, replace ? 3 : 0);
        Marshal.WriteInt32(rename, 16, name.Length);
        Marshal.Copy(name, 0, IntPtr.Add(rename, 20), name.Length);
    }
    private static void WriteRecord(string path, Record record, bool create)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(Json.Serialize(record));
        if (bytes.Length > MaximumRecord) throw new IOException("rollback-record-size");
        string stage = create ? path : path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        using (Pin file = NewFile(stage, JournalSecurity()))
        {
            bool committed = create;
            try
            {
                RequireSecurity(file, JournalSecurity());
                // Keep this stream alive through handle-bound rename.
                file.WriteBytes(bytes);
                if (!create)
                {
                    using (Pin previous = new Pin(path, false, 0, OpenExisting, IntPtr.Zero, 7))
                    {
                        RequireSecurity(previous, JournalSecurity());
                        Rename(file, path, true); committed = true;
                    }
                }
            }
            finally { if (!committed) file.RemoveEmpty(); }
        }
    }
    private static void MakeDirectory(string path, string security, Record record, string journal, List<Pin> pins)
    {
        bool created = WithSecurity(security, delegate(IntPtr attrs) {
            SecurityAttributes sa = (SecurityAttributes)Marshal.PtrToStructure(attrs, typeof(SecurityAttributes));
            if (CreateDirectory(path, ref sa)) return true;
            if (Marshal.GetLastWin32Error() != 183) throw new IOException("create-directory");
            return false;
        });
        // Existing directories are retained, never rollback-deleted. Requesting
        // DELETE here conflicts with an earlier no-delete-sharing safety pin.
        Pin pin = new Pin(path, true, (created ? Delete : 0) | 0x20); pins.Add(pin);
        RequireSecurity(pin, security);
        if (created)
        {
            Created entry = new Created { Path = path, Identity = pin.Identity, Directory = true };
            record.Created.Add(entry);
            try { WriteRecord(journal, record, false); }
            catch
            {
                record.Created.Remove(entry);
                // A returned journal error must not orphan an unrecorded new
                // directory. Delete only this retained, still-empty object.
                pin.RemoveEmpty(); pin.Dispose(); throw;
            }
        }
    }
    private static void PublishConfig(string path, byte[] bytes, string security, Record record,
        string journal, Action<Stream> write)
    {
        string stage = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        using (Pin pin = NewFile(stage, security))
        {
            bool published = false;
            try
            {
                pin.WriteContent(write);
                if (Hash(pin.ReadBytes()) != Hash(bytes)) throw new IOException("staged-config-content");
                Created entry = new Created { Path = path, Identity = pin.Identity, Hash = Hash(bytes) };
                record.Created.Add(entry);
                try { WriteRecord(journal, record, false); }
                catch { record.Created.Remove(entry); throw; }
                Rename(pin, path, false); published = true;
            }
            finally { if (!published) pin.RemoveEmpty(); }
        }
    }
    private static Dictionary<string, object> Configuration(string data, SecurityIdentifier service, SecurityIdentifier gateway)
    {
        string privateRoot = Path.Combine(data, "SyntaurLinkTor");
        return new Dictionary<string, object> {
            { "schema", 4 }, { "state_dir", Path.Combine(privateRoot, "state") },
            { "cache_dir", Path.Combine(privateRoot, "cache") }, { "status_path", Path.Combine(privateRoot, "state", "status.json") },
            { "control_socket", @"\\.\pipe\Syntaur.Link.host." + gateway.Value },
            { "gateway_pin_path", Path.Combine(data, "Syntaur", "LinkTor", "shared", gateway.Value, "gateway-pin.json") },
            { "service_nickname", "syntaur" }, { "virtual_port", 443 },
            { "gateway_sid", gateway.Value }, { "service_sid", service.Value }, { "bridge_bundle", null }
        };
    }
    private static bool SameConfiguration(Dictionary<string, object> actual, Dictionary<string, object> expected)
    {
        // Existing bridge policy is preserved, never replaced by the installer's
        // initial ordinary-transport default. All identity/path fields are fixed.
        if (actual.Count != expected.Count) return false;
        foreach (KeyValuePair<string, object> pair in expected)
        {
            object value;
            if (!actual.TryGetValue(pair.Key, out value)) return false;
            if (pair.Key == "bridge_bundle") continue;
            if (Convert.ToString(value, CultureInfo.InvariantCulture) != Convert.ToString(pair.Value, CultureInfo.InvariantCulture)) return false;
        }
        return true;
    }
    private static string Hash(byte[] bytes)
    { using (SHA256 sha = SHA256.Create()) return Convert.ToBase64String(sha.ComputeHash(bytes)); }

    // Fixed categories in MSI's existing EXE-exit record. No private exception
    // text, paths, account identities, or configuration. A failed rename may
    // include its bounded public Windows error number, never arbitrary text.
    private enum ProvisioningStep
    {
        Entry, Ancestors, Prepare, ReadJournal, Commit, Rollback, ServiceRole,
        PrivateRoot, ExistingConfig, RecordOwner, ProgramDirectory, ProgramFiles,
        PrivateDirectories, SharedDirectories, PublishConfig
    }
    private static readonly string[] RefusalLabels = {
        "configure-replay", "create-directory", "enable-restore-privilege", "existing-config-binding",
        "file-already-read", "growing-record", "installation-retargeted", "invalid-msi-action",
        "invalid-server-owner", "invalid-service-role", "missing-access-entry", "nonlocal-known-folder",
        "open-owned-path", "open-restore-token", "orphan-private-state", "owned-object-absent",
        "path-type-or-reparse", "read-security", "record-size", "remove-created-object",
        "requires-msi-system-action", "resolve-restore-privilege", "restore-token-privilege", "rollback-binding",
        "rollback-content", "rollback-identity", "rollback-path", "rollback-record-size",
        "rollback-retained-data", "security-size", "set-owned-security", "short-record",
        "staged-config-content", "unexpected-access-entry", "unexpected-owner-or-acl", "unrestricted-installation-acl",
        "unsupported-installation-ace", "untrusted-installation-owner", "untrusted-installation-writer"
    };
    private static int FailureExitCode(Exception error, ProvisioningStep step)
    {
        int phase = (int)step;
        if (phase < 0 || phase > (int)ProvisioningStep.PublishConfig) return 1;
        RenameFailure rename = error as RenameFailure;
        if (rename != null && rename.NativeCode >= 0 && rename.NativeCode <= 65535)
            return (phase + 1) * 65536 + rename.NativeCode;
        int label = error is IOException ? Array.IndexOf(RefusalLabels, error.Message) : -1;
        // Unknown details remain hidden; report only the last fixed step.
        // Cleanup exceptions can inherit that step rather than its exact site.
        return label < 0 ? 1000 + phase * 100 + 99 :
            1000 + phase * 100 + label + 1;
    }

    private static int Main(string[] args)
    {
        RestorePrivilege privilege = null;
        ProvisioningStep step = ProvisioningStep.Entry;
        try
        {
            RequireSystem();
            privilege = new RestorePrivilege();
            if (args.Length != 3) throw new IOException("invalid-msi-action");
            string product = Guid.ParseExact(args[1], "B").ToString("B").ToUpperInvariant();
            string data = Known(Environment.SpecialFolder.CommonApplicationData);
            string programs = Path.Combine(Known(Environment.SpecialFolder.ProgramFiles), "Syntaur");
            string journal = Path.Combine(Known(Environment.SpecialFolder.Windows), "Installer", "Syntaur-" + product + ".json");
            List<Pin> pins = new List<Pin>();
            try
            {
                step = ProvisioningStep.Ancestors;
                foreach (string root in new[] { data, Known(Environment.SpecialFolder.ProgramFiles), Path.GetDirectoryName(journal) })
                { Pin pin = new Pin(root, true, 0x20); pins.Add(pin); RequireAdminControlled(pin, true); }
                if (args[0] == "prepare")
                {
                    step = ProvisioningStep.Prepare;
                    Record fresh = new Record { Product = product, IncomingOwner = Owner(args[2]).Value };
                    if (Directory.Exists(programs))
                    { using (Pin pin = new Pin(programs, true, 0x20)) { RequireAdminControlled(pin); fresh.ProgramDirectoryIdentity = pin.Identity; } }
                    WriteRecord(journal, fresh, true); return 0;
                }
                step = ProvisioningStep.ReadJournal;
                Record record;
                using (Pin pin = new Pin(journal, false, 0x80000000))
                { RequireSecurity(pin, JournalSecurity()); record = Json.Deserialize<Record>(Encoding.UTF8.GetString(pin.ReadBytes())); }
                if (record.Product != product || record.IncomingOwner != Owner(args[2]).Value || record.Created.Count > 16)
                    throw new IOException("rollback-binding");
                if (args[0] == "commit")
                { step = ProvisioningStep.Commit; using (Pin pin = new Pin(journal, false, Delete)) { RequireSecurity(pin, JournalSecurity()); pin.RemoveEmpty(); } return 0; }
                if (args[0] == "rollback")
                {
                    step = ProvisioningStep.Rollback;
                    // No recursive erase, even for objects created by this MSI.
                    // Keys, pins or other nonempty state cause explicit refusal.
                    bool complete = true;
                    for (int i = record.Created.Count - 1; i >= 0; i--)
                    {
                        Created created = record.Created[i];
                        try
                        {
                            string full = Path.GetFullPath(created.Path);
                            if (!full.StartsWith(data + "\\", StringComparison.OrdinalIgnoreCase)) throw new IOException("rollback-path");
                            using (Pin pin = new Pin(full, created.Directory, Delete | (created.Directory ? 0x20U : 0x80000000U)))
                            {
                                if (pin.Identity != created.Identity) throw new IOException("rollback-identity");
                                if (!created.Directory && Hash(pin.ReadBytes()) != created.Hash) throw new IOException("rollback-content");
                                pin.RemoveEmpty();
                            }
                        }
                        catch (FileNotFoundException) { /* Unpublished or already removed; erase nothing. */ }
                        catch { complete = false; }
                    }
                    if (!complete) throw new IOException("rollback-retained-data");
                    using (Pin pin = new Pin(journal, false, Delete)) { RequireSecurity(pin, JournalSecurity()); pin.RemoveEmpty(); }
                    return 0;
                }
                if (args[0] != "configure" || record.Created.Count != 0) throw new IOException("configure-replay");
                step = ProvisioningStep.ServiceRole;
                SecurityIdentifier service = (SecurityIdentifier)new NTAccount("NT SERVICE", "SyntaurLinkTor").Translate(typeof(SecurityIdentifier));
                if (!service.Value.StartsWith("S-1-5-80-", StringComparison.Ordinal) || service.Value.Split('-').Length != 9)
                    throw new IOException("invalid-service-role");
                string privateRoot = Path.Combine(data, "SyntaurLinkTor"), configPath = Path.Combine(privateRoot, "host.json");
                Pin privateParent = new Pin(data, true, 0x20); pins.Add(privateParent);
                SecurityIdentifier gateway = Owner(record.IncomingOwner);
                bool existingConfig = File.Exists(configPath);
                // Never traverse an existing private-root alias to read config.
                step = ProvisioningStep.PrivateRoot;
                if (Directory.Exists(privateRoot))
                { Pin pin = new Pin(privateRoot, true, 0x20); pins.Add(pin); RequireSecurity(pin, Admin(service, null, true)); }
                if (existingConfig)
                {
                    step = ProvisioningStep.ExistingConfig;
                    Dictionary<string, object> actual;
                    using (Pin pin = new Pin(configPath, false, 0x80000000))
                    { RequireSecurity(pin, Admin(service, null, false)); actual = Json.Deserialize<Dictionary<string, object>>(Encoding.UTF8.GetString(pin.ReadBytes())); }
                    gateway = Owner((string)actual["gateway_sid"]);
                    if (!SameConfiguration(actual, Configuration(data, service, gateway))) throw new IOException("existing-config-binding");
                }
                step = ProvisioningStep.RecordOwner;
                record.Gateway = gateway.Value; WriteRecord(journal, record, false);
                step = ProvisioningStep.ProgramDirectory;
                Pin program = new Pin(programs, true, WriteDac | WriteOwner | 0x20); pins.Add(program);
                RequireAdminControlled(program);
                if (record.ProgramDirectoryIdentity != null)
                {
                    if (program.Identity != record.ProgramDirectoryIdentity) throw new IOException("installation-retargeted");
                    RequireSecurity(program, Admin(service, gateway, true));
                }
                else program.SetSecurity(Admin(service, gateway, true));
                step = ProvisioningStep.ProgramFiles;
                foreach (string name in ProgramFiles)
                {
                    using (Pin pin = new Pin(Path.Combine(programs, name), false, WriteDac | WriteOwner))
                    {
                        RequireAdminControlled(pin);
                        // Only files under an originally absent program folder
                        // are newly provisioned. Maintenance preserves admitted
                        // file ACLs, including exact inherited RX entries.
                        if (record.ProgramDirectoryIdentity == null)
                            pin.SetSecurity(Admin(service, gateway, false));
                        RequireSecurity(pin, Admin(service, gateway, false), true);
                    }
                }
                step = ProvisioningStep.PrivateDirectories;
                MakeDirectory(privateRoot, Admin(service, null, true), record, journal, pins);
                foreach (string name in new[] { "state", "cache" })
                {
                    string path = Path.Combine(privateRoot, name);
                    // Existing state without its original config cannot be
                    // adopted by a new installing operator.
                    if (!existingConfig && Directory.Exists(path)) throw new IOException("orphan-private-state");
                    MakeDirectory(path, Private(service, service, false), record, journal, pins);
                }
                step = ProvisioningStep.SharedDirectories;
                string shared = data;
                foreach (string part in new[] { "Syntaur", "LinkTor", "shared" })
                { shared = Path.Combine(shared, part); MakeDirectory(shared, Admin(service, gateway, true), record, journal, pins); }
                MakeDirectory(Path.Combine(shared, gateway.Value), Private(gateway, service, true), record, journal, pins);
                if (!existingConfig)
                {
                    step = ProvisioningStep.PublishConfig;
                    byte[] bytes = Encoding.UTF8.GetBytes(Json.Serialize(Configuration(data, service, gateway)));
                    PublishConfig(configPath, bytes, Admin(service, null, false), record, journal,
                        delegate(Stream stream) { stream.Write(bytes, 0, bytes.Length); });
                }
                Console.WriteLine("Syntaur installer roles and preserved configuration verified.");
                return 0;
            }
            finally { for (int i = pins.Count - 1; i >= 0; i--) pins[i].Dispose(); }
        }
        catch (Exception error)
        {
            // Fixed labels only; no config, profile, account name or secret.
            Console.Error.WriteLine("Syntaur installer provisioning refused: " + error.GetType().Name);
            return FailureExitCode(error, step);
        }
        finally { if (privilege != null) privilege.Dispose(); }
    }
}
