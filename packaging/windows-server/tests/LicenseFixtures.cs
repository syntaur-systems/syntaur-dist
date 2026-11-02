using System;
using System.IO;
using System.Reflection;
using System.Security.AccessControl;
using System.Security.Principal;

// Pure parser and owned-directory checks. No consent UI, server, profile,
// registry, installation, signing, or network operation is exercised.
internal static class LicenseFixtures
{
    private static object Call(string name, params object[] args)
    {
        return typeof(ServerLauncher).GetMethod(name, BindingFlags.NonPublic | BindingFlags.Static).Invoke(null, args);
    }
    private static void Expect(bool value, string label)
    {
        if (!value) throw new Exception(label);
        Console.WriteLine("PASS: " + label);
    }
    private static int Main()
    {
        string root = Path.Combine(Path.GetTempPath(), "SyntaurLicenseFixture-" + Guid.NewGuid().ToString("N"));
        string record = "record_format=1\neula_version=1.0\neula_sha256=3e417ea33bc2d6296070222df816a6d145846743c1d98e7e4d20c7c2c8e9a720\neula_url=https://raw.githubusercontent.com/syntaur-systems/syntaur-dist/8811aa006673caa5082a7c9343e83c0b7ac51d16/EULA.md\naccepted_at=2026-11-02T19:00:00Z\nmethod=prompt\ninstaller_version=1.2.3\n";
        try
        {
            Expect((bool)Call("CurrentLicenseRecord", record), "canonical acceptance");
            Expect((bool)Call("CurrentLicenseRecord", record.Replace("method=prompt", "method=flag").Replace("\n", "\r\n")), "existing bootstrap flag record");
            foreach (string bad in new string[] {
                record.Replace("record_format=1", "record_format=2"),
                record.Replace("eula_version=1.0", "eula_version=0.9"),
                record.Replace("3e417ea3", "4e417ea3"),
                record.Replace("raw.githubusercontent.com", "untrusted.invalid"),
                record.Replace("2026-11-02", "2026-02-31"),
                record.Replace("method=prompt", "method=implicit"),
                record.Replace("installer_version=1.2.3", "installer_version=01.2.3"),
                record + "method=flag\n", record.Replace("method=prompt", "unknown=prompt") })
                Expect(!(bool)Call("CurrentLicenseRecord", bad), "invalid or stale acceptance refused");
            DirectorySecurity security = new DirectorySecurity();
            security.SetAccessRuleProtection(true, false);
            using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
            {
                security.SetOwner(identity.User);
                foreach (SecurityIdentifier sid in new SecurityIdentifier[] { identity.User,
                    new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
                    new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null) })
                    security.AddAccessRule(new FileSystemAccessRule(sid, FileSystemRights.FullControl,
                        InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
                        PropagationFlags.None, AccessControlType.Allow));
            }
            Directory.CreateDirectory(root, security);
            string directory = Path.Combine(root, ".syntaur");
            Expect(!(bool)Call("EnsureLicenseAccepted", root, root, true) && !Directory.Exists(directory),
                "background startup without consent creates nothing");
            Call("WriteLicenseRecord", directory, record);
            Expect((bool)Call("ReadLicenseRecord", directory), "owned record persisted and read");
            Expect((bool)Call("EnsureLicenseAccepted", root, root, true), "existing consent permits startup without UI");
            string path = Path.Combine(directory, "eula-accepted");
            Call("WriteLicenseRecord", directory, record.Replace("method=prompt", "method=flag"));
            Expect((bool)Call("ReadLicenseRecord", directory) && Directory.GetFiles(directory).Length == 1,
                "atomic replacement leaves no temporary files");
            string before = File.ReadAllText(path);
            DirectorySecurity otherOwner = Directory.GetAccessControl(directory);
            otherOwner.SetOwner(new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null));
            Directory.SetAccessControl(directory, otherOwner);
            bool wrongOwnerRefused = false;
            try { Call("WriteLicenseRecord", directory, record); }
            catch (TargetInvocationException) { wrongOwnerRefused = true; }
            Expect(wrongOwnerRefused && File.ReadAllText(path) == before, "administrative-owned private root not adopted");
            using (WindowsIdentity identity = WindowsIdentity.GetCurrent()) { otherOwner.SetOwner(identity.User); }
            Directory.SetAccessControl(directory, otherOwner);
            FileSecurity acl = File.GetAccessControl(path);
            acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.WorldSid, null),
                FileSystemRights.WriteData, AccessControlType.Allow));
            File.SetAccessControl(path, acl);
            bool refused = false;
            try { Call("WriteLicenseRecord", directory, record); }
            catch (TargetInvocationException) { refused = true; }
            Expect(refused && File.ReadAllText(path) == before, "untrusted-writer record not read or replaced");
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error); return 1; }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
}
