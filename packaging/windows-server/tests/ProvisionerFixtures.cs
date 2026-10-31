using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Web.Script.Serialization;

// Kernel filesystem cases in one explicit disposable SYSTEM-owned fixture root.
// No installer registration, service, account, profile, Tor or Gateway call.
internal static class ProvisionerFixtures
{
    private static readonly Type Subject = typeof(InstallerProvisioner);
    private static readonly Type PinType = Subject.GetNestedType("Pin", BindingFlags.NonPublic);
    private static readonly BindingFlags Static = BindingFlags.Static | BindingFlags.NonPublic;
    private static object Call(string name, params object[] args)
    {
        try { return Subject.GetMethod(name, Static).Invoke(null, args); }
        catch (TargetInvocationException error) { throw error.InnerException; }
    }
    private static object Pin(string path, bool directory, uint access = 0)
    { return Activator.CreateInstance(PinType, BindingFlags.Instance | BindingFlags.NonPublic, null,
        new object[] { path, directory, access, 3U, IntPtr.Zero, 3U }, null); }
    private static object Member(object pin, string name, params object[] args)
    {
        try { return PinType.GetMethod(name, BindingFlags.Instance | BindingFlags.NonPublic).Invoke(pin, args); }
        catch (TargetInvocationException error) { throw error.InnerException; }
    }
    private static void Require(bool value) { if (!value) throw new InvalidOperationException("fixture-failed"); }
    private static void Refuses(Action action)
    { try { action(); } catch (IOException) { return; } throw new InvalidOperationException("expected-refusal"); }
    private static void WithPins(Action<object> action)
    {
        object list = Activator.CreateInstance(typeof(List<>).MakeGenericType(PinType));
        try { action(list); }
        finally { foreach (IDisposable pin in (IEnumerable)list) pin.Dispose(); }
    }
    private static int ExistingRootMaintenance(string root)
    {
        if (Directory.Exists(root)) throw new InvalidOperationException("new-maintenance-fixture-required");
        Call("RequireSystem");
        Directory.CreateDirectory(root);
        using (IDisposable rootPin = (IDisposable)Pin(root, true, 0xc0000))
            Member(rootPin, "SetSecurity", Call("JournalSecurity"));
        string target = Path.Combine(root, "existing-private-root"), journal = Path.Combine(root, "rollback.json");
        var record = new InstallerProvisioner.Record { Product = Guid.NewGuid().ToString("B"),
            IncomingOwner = "S-1-5-21-111-222-333-1001" };
        var service = new SecurityIdentifier("S-1-5-80-111-222-333-444-555");
        string expected = (string)Call("Admin", service, null, true);
        Call("WriteRecord", journal, record, true);
        WithPins(delegate(object pins) { Call("MakeDirectory", target, expected, record, journal, pins); });
        string sentinel = Path.Combine(target, "retained.txt"); File.WriteAllText(sentinel, "retained");
        string before = Directory.GetAccessControl(target).GetSecurityDescriptorSddlForm(AccessControlSections.All);
        byte[] oldJournal = File.ReadAllBytes(journal); int oldCount = record.Created.Count;
        using (IDisposable retained = (IDisposable)Pin(target, true, 0x20))
        {
            Call("RequireSecurity", retained, expected, false);
            WithPins(delegate(object pins) { Call("MakeDirectory", target, expected, record, journal, pins); });
        }
        Require(record.Created.Count == oldCount && File.ReadAllText(sentinel) == "retained" &&
            Convert.ToBase64String(oldJournal) == Convert.ToBase64String(File.ReadAllBytes(journal)) &&
            before == Directory.GetAccessControl(target).GetSecurityDescriptorSddlForm(AccessControlSections.All));
        Console.WriteLine("PASS pinned-existing-private-root-maintenance-preserves-data-ACL-and-journal");
        string incompatible = (string)Call("Private", service, service, false);
        using (IDisposable retained = (IDisposable)Pin(target, true, 0x20))
            WithPins(delegate(object pins) {
                Refuses(delegate { Call("MakeDirectory", target, incompatible, record, journal, pins); });
            });
        Require(record.Created.Count == oldCount && File.ReadAllText(sentinel) == "retained" &&
            before == Directory.GetAccessControl(target).GetSecurityDescriptorSddlForm(AccessControlSections.All));
        Console.WriteLine("PASS pinned-existing-root-incompatible-security-still-refused-without-mutation");
        return 0;
    }
    private static int RenameBufferCases()
    {
        byte[] name = Encoding.Unicode.GetBytes("C:\\fixture\\snowman-\u2603-\ud83d\ude42.json");
        foreach (bool replace in new[] { false, true })
        {
            int length = 24 + name.Length;
            IntPtr buffer = Marshal.AllocHGlobal(length);
            try
            {
                for (int i = 0; i < length; i++) Marshal.WriteByte(buffer, i, 0x41);
                Call("InitializeRenameBuffer", buffer, name, replace);
                Require(Marshal.ReadInt32(buffer) == (replace ? 3 : 0) &&
                    Marshal.ReadIntPtr(buffer, 8) == IntPtr.Zero &&
                    Marshal.ReadInt32(buffer, 16) == name.Length);
                for (int i = 0; i < name.Length; i++) Require(Marshal.ReadByte(buffer, 20 + i) == name[i]);
                Require(Marshal.ReadInt16(buffer, 20 + name.Length) == 0 &&
                    Marshal.ReadInt16(buffer, 22 + name.Length) == 0);
            }
            finally { Marshal.FreeHGlobal(buffer); }
        }
        Console.WriteLine("PASS rename-buffer-terminates-Unicode-name-without-counting-tail-in-length");
        return 0;
    }
    private static int RenameNativeCases()
    {
        Type stepType = Subject.GetNestedType("ProvisioningStep", BindingFlags.NonPublic);
        Type errorType = Subject.GetNestedType("RenameFailure", BindingFlags.NonPublic);
        object step = Enum.Parse(stepType, "RecordOwner");
        foreach (int native in new[] { 0, 1, 5, 65535, -1, 65536 })
        {
            var error = (Exception)Activator.CreateInstance(errorType, BindingFlags.Instance | BindingFlags.NonPublic,
                null, new object[] { native }, null);
            Require(error is IOException && error.Message == "publish-owned-file");
            int code = (int)Call("FailureExitCode", error, step);
            Require(code == (native >= 0 && native <= 65535 ? 655360 + native : 1999));
        }
        Require((int)Call("FailureExitCode", new IOException("publish-owned-file"), step) == 1999 &&
            (int)Call("FailureExitCode", new System.ComponentModel.Win32Exception(32, "publish-owned-file"), step) == 1999);
        Console.WriteLine("PASS source-owned-native-rename-errors-are-bounded-disjoint-and-content-free");
        return 0;
    }
    private static int RefusalCodeCases()
    {
        Type stepType = Subject.GetNestedType("ProvisioningStep", BindingFlags.NonPublic);
        string[] labels = (string[])Subject.GetField("RefusalLabels", Static).GetValue(null);
        var seen = new HashSet<int>();
        foreach (object step in Enum.GetValues(stepType))
            foreach (string label in labels)
            {
                int code = (int)Call("FailureExitCode", new IOException(label), step);
                Require(code >= 1000 && code <= 2499 && seen.Add(code) &&
                    code == (int)Call("FailureExitCode", new IOException(label), step));
            }
        Console.WriteLine("PASS fixed-source-refusal-codes-are-deterministic-bounded-and-nonzero");
        object first = Enum.ToObject(stepType, 0), invalid = Enum.ToObject(stepType, 99);
        Require((int)Call("FailureExitCode", new IOException("private-looking-unmapped-example"), first) == 1099 &&
            (int)Call("FailureExitCode", new FormatException(labels[0]), first) == 1099 &&
            (int)Call("FailureExitCode", new IOException(labels[0]), invalid) == 1);
        object files = Enum.Parse(stepType, "ProgramFiles");
        Require((int)Call("FailureExitCode", new IOException("private-looking-unmapped-example"), files) == 2199 &&
            (int)Call("FailureExitCode", new FormatException("different-private-looking-example"), files) == 2199 &&
            !seen.Contains(1099) && !seen.Contains(2199));
        Console.WriteLine("PASS unknown-details-report-only-last-fixed-phase-including-entry");
        return 0;
    }
    private static int Main(string[] args)
    {
        try
        {
            if (args.Length == 1 && args[0] == "--rename-buffer")
                return RenameBufferCases();
            if (args.Length == 1 && args[0] == "--rename-native")
                return RenameNativeCases();
            if (args.Length == 1 && args[0] == "--refusal-codes")
                return RefusalCodeCases();
            if (args.Length == 2 && args[0] == "--maintenance-root")
                return ExistingRootMaintenance(args[1]);
            bool continuation = args.Length == 2 && args[0] == "--continue";
            if ((!continuation && args.Length != 1) ||
                Directory.Exists(args[continuation ? 1 : 0]) != continuation)
                throw new InvalidOperationException("owned-fixture-required");
            Call("RequireSystem");
            using (IDisposable privilege = (IDisposable)Activator.CreateInstance(
                Subject.GetNestedType("RestorePrivilege", BindingFlags.NonPublic), true))
            {
                string root = Path.GetFullPath(args[continuation ? 1 : 0]);
                if (!continuation)
                {
                    Directory.CreateDirectory(root);
                    using (IDisposable rootPin = (IDisposable)Pin(root, true, 0xc0000))
                        Member(rootPin, "SetSecurity", Call("JournalSecurity"));
                }
                else
                    using (IDisposable rootPin = (IDisposable)Pin(root, true))
                        Call("RequireAdminControlled", rootPin, false);
                string journal = Path.Combine(root, "rollback.json");
                InstallerProvisioner.Record record = new InstallerProvisioner.Record {
                    Product = Guid.NewGuid().ToString("B"), IncomingOwner = "S-1-5-21-111-222-333-1001" };
                if (continuation)
                    record = new JavaScriptSerializer().Deserialize<InstallerProvisioner.Record>(File.ReadAllText(journal));
                SecurityIdentifier service = new SecurityIdentifier("S-1-5-80-111-222-333-444-555");
                SecurityIdentifier gateway = new SecurityIdentifier(record.IncomingOwner);
                string privateAcl = (string)Call("Private", service, service, false);
                string sharedAcl = (string)Call("Private", gateway, service, true);
                string serviceRoot = Path.Combine(root, "state"), sharedRoot = Path.Combine(root, "shared");
                string sentinel = Path.Combine(sharedRoot, "preserved.txt");
                if (!continuation)
                {
                Call("WriteRecord", journal, record, true);
                WithPins(delegate(object pins) {
                    Call("MakeDirectory", serviceRoot, privateAcl, record, journal, pins);
                    Call("MakeDirectory", sharedRoot, sharedAcl, record, journal, pins);
                });
                Require(record.Created.Count == 2);
                using (IDisposable pin = (IDisposable)Pin(serviceRoot, true)) Call("RequireSecurity", pin, privateAcl, false);
                using (IDisposable pin = (IDisposable)Pin(sharedRoot, true)) Call("RequireSecurity", pin, sharedAcl, false);
                Console.WriteLine("PASS actual-service-and-Gateway-owner-private-ACLs");

                File.WriteAllText(sentinel, "retain");
                string before = Directory.GetAccessControl(sharedRoot).GetSecurityDescriptorSddlForm(AccessControlSections.All);
                WithPins(delegate(object pins) { Call("MakeDirectory", sharedRoot, sharedAcl, record, journal, pins); });
                Require(record.Created.Count == 2 && File.ReadAllText(sentinel) == "retain" &&
                    before == Directory.GetAccessControl(sharedRoot).GetSecurityDescriptorSddlForm(AccessControlSections.All));
                Console.WriteLine("PASS existing-private-data-and-security-preserved");

                WithPins(delegate(object pins) { Refuses(delegate { Call("MakeDirectory", sharedRoot, privateAcl, record, journal, pins); }); });
                Require(before == Directory.GetAccessControl(sharedRoot).GetSecurityDescriptorSddlForm(AccessControlSections.All));
                Console.WriteLine("PASS incompatible-existing-owner-refused-without-reACL");
                }
                else
                {
                    Require(record.Created.Count == 2 && record.IncomingOwner == "S-1-5-21-111-222-333-1001" &&
                        record.Created[0].Path == serviceRoot && record.Created[1].Path == sharedRoot &&
                        File.ReadAllText(sentinel) == "retain");
                    foreach (InstallerProvisioner.Created item in record.Created)
                        using (IDisposable pin = (IDisposable)Pin(item.Path, true))
                            Require((string)PinType.GetField("Identity", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(pin) == item.Identity);
                    Console.WriteLine("RETAINED first-three-passed-cases-not-repeated");
                }

                // A retained no-delete-sharing handle forces rename failure.
                // The last durable rollback record must remain byte-for-byte.
                byte[] original = File.ReadAllBytes(journal);
                using (IDisposable locked = (IDisposable)Pin(journal, false, 0x80000000))
                    Refuses(delegate { record.Gateway = gateway.Value; Call("WriteRecord", journal, record, false); });
                Require(Convert.ToBase64String(original) == Convert.ToBase64String(File.ReadAllBytes(journal)));
                Call("WriteRecord", journal, record, false);
                Require(File.ReadAllText(journal).Contains(gateway.Value) && Directory.GetFiles(root, "*.tmp").Length == 0);
                Console.WriteLine("PASS atomic-rollback-record-preserves-last-valid-preimage");

                int recorded = record.Created.Count;
                string failedDirectory = Path.Combine(root, "journal-failed-new-directory");
                using (IDisposable locked = (IDisposable)Pin(journal, false, 0x80000000))
                    WithPins(delegate(object pins) {
                        Refuses(delegate { Call("MakeDirectory", failedDirectory, privateAcl, record, journal, pins); });
                    });
                Require(!Directory.Exists(failedDirectory) && record.Created.Count == recorded);
                Console.WriteLine("PASS failed-journal-update-removes-only-new-empty-directory");

                string configTarget = Path.Combine(root, "new-host.json");
                byte[] configBytes = Encoding.UTF8.GetBytes("complete-config");
                Action<Stream> failedWrite = delegate(Stream stream) {
                    stream.Write(configBytes, 0, 3); throw new IOException("synthetic-write-failure");
                };
                Refuses(delegate { Call("PublishConfig", configTarget, configBytes,
                    Call("JournalSecurity"), record, journal, failedWrite); });
                Require(!File.Exists(configTarget) && Directory.GetFiles(root, "*.tmp").Length == 0 && record.Created.Count == recorded);
                Action<Stream> completeWrite = delegate(Stream stream) { stream.Write(configBytes, 0, configBytes.Length); };
                Call("PublishConfig", configTarget, configBytes, Call("JournalSecurity"), record, journal, completeWrite);
                Require(File.ReadAllText(configTarget) == "complete-config" && record.Created.Count == recorded + 1);
                Console.WriteLine("PASS failed-config-write-leaves-no-partial-final-file");

                var expected = (Dictionary<string, object>)Call("Configuration", root, service, gateway);
                var actual = new Dictionary<string, object>(expected);
                actual["bridge_bundle"] = new Dictionary<string, object> { { "existing", "retained" } };
                Require((bool)Call("SameConfiguration", actual, expected));
                actual["gateway_sid"] = "S-1-5-21-111-222-333-1002";
                Require(!(bool)Call("SameConfiguration", actual, expected));
                Console.WriteLine("PASS existing-bridge-policy-preserved-and-owner-rebind-refused");

                string executableAcl = (string)Call("Admin", service, gateway, false);
                string configAcl = (string)Call("Admin", service, null, false);
                RawSecurityDescriptor exec = new RawSecurityDescriptor(executableAcl), config = new RawSecurityDescriptor(configAcl);
                int execMask = 0, configMask = 0;
                foreach (CommonAce ace in exec.DiscretionaryAcl) if (ace.SecurityIdentifier == service) execMask = ace.AccessMask;
                foreach (CommonAce ace in config.DiscretionaryAcl) if (ace.SecurityIdentifier == service) configMask = ace.AccessMask;
                Require(execMask == 0x1200a9 && configMask == 0x120089);
                Console.WriteLine("PASS executable-RX-separated-from-config-read-only");

                // Content checking must retain the same open handle for deletion.
                string disposable = Path.Combine(root, "created-empty.json");
                using (IDisposable pin = (IDisposable)Call("NewFile", disposable, Call("JournalSecurity")))
                {
                    Member(pin, "WriteBytes", Encoding.UTF8.GetBytes("created"));
                }
                using (IDisposable pin = (IDisposable)Pin(disposable, false, 0x80010000))
                { Require(Encoding.UTF8.GetString((byte[])Member(pin, "ReadBytes")) == "created"); Member(pin, "RemoveEmpty"); }
                Require(!File.Exists(disposable));
                using (IDisposable pin = (IDisposable)Pin(sharedRoot, true, 0x10000))
                    Refuses(delegate { Member(pin, "RemoveEmpty"); });
                Require(File.ReadAllText(sentinel) == "retain");
                Console.WriteLine("PASS same-handle-file-removal-and-nonempty-state-retention");
            }
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine("FAIL " + error.GetType().Name); return 1; }
    }
}
