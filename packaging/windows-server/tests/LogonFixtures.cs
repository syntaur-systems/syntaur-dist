using System;
using System.Collections.Generic;
using System.Reflection;
using System.Security.AccessControl;
using System.Security.Principal;

// Pure role-policy cases. No profile, service, registry, process or network action.
internal static class LogonFixtures
{
    private const string Gateway = "S-1-5-21-11-22-33-1001";
    private const string Service = "S-1-5-80-1-2-3-4-5";
    private static readonly BindingFlags Hidden = BindingFlags.Static | BindingFlags.NonPublic;
    private static void Require(bool condition) { if (!condition) throw new InvalidOperationException("fixture-failed"); }
    private static string Ace(string sid, string rights)
    { return "(A;OICI;" + rights + ";;;" + sid + ")"; }
    private static void Check(string sddl, bool leaf, bool accepted)
    {
        bool passed = false;
        try
        {
            typeof(ServerLauncher).GetMethod("ValidateLogonSecurity", Hidden).Invoke(null,
                new object[] { new RawSecurityDescriptor(sddl), new SecurityIdentifier(Service),
                    new SecurityIdentifier(Gateway), leaf });
            passed = true;
        }
        catch (TargetInvocationException error)
        { Require(error.InnerException != null && error.InnerException.GetType().Name == "LaunchFailure"); }
        Require(passed == accepted);
    }
    private static int Main()
    {
        try
        {
            string parent = "O:SYG:SYD:P" + Ace("SY", "FA") + Ace("BA", "FA") +
                Ace(Service, "0x1200a9") + Ace(Gateway, "0x1200a9");
            string leaf = "O:" + Gateway + "G:SYD:P" + Ace("SY", "FA") +
                Ace(Service, "0x1200a9") + Ace(Gateway, "FA");
            Check(parent, false, true); Check(leaf, true, true);
            Console.WriteLine("PASS logon-original-private-parent-and-leaf");
            Check(parent + Ace("BU", "0x1200a9"), false, false);
            Check(leaf + Ace("BU", "0x1200a9"), true, false);
            Console.WriteLine("PASS logon-private-users-access-refused");
            Check(parent.Replace("0x1200a9", "0x1200ab"), false, false);
            Check(leaf.Replace("O:" + Gateway, "O:SY"), true, false);
            Console.WriteLine("PASS logon-writer-and-wrong-owner-refused");
            Check(parent.Replace("D:P", "D:"), false, false);
            Check(parent + Ace(Service, "0x1200a9"), false, false);
            Console.WriteLine("PASS logon-unprotected-and-duplicate-refused");
            string code = (string)typeof(InstallerProvisioner).GetMethod("CodeSecurity", Hidden).Invoke(null,
                new object[] { new SecurityIdentifier(Service), new SecurityIdentifier(Gateway), true });
            RawSecurityDescriptor descriptor = new RawSecurityDescriptor(code);
            Require(descriptor.DiscretionaryAcl.Count == 5 && descriptor.Owner.IsWellKnown(WellKnownSidType.LocalSystemSid));
            int users = 0;
            foreach (GenericAce entry in descriptor.DiscretionaryAcl)
            {
                CommonAce ace = entry as CommonAce; Require(ace != null);
                if (ace.SecurityIdentifier.IsWellKnown(WellKnownSidType.BuiltinUsersSid))
                { Require(ace.AccessMask == 0x1200a9); users++; }
            }
            Require(users == 1);
            Console.WriteLine("PASS public-code-users-exact-read-execute");
            string privateParent = (string)typeof(InstallerProvisioner).GetMethod("Admin", Hidden).Invoke(null,
                new object[] { new SecurityIdentifier(Service), new SecurityIdentifier(Gateway), true });
            Check(privateParent, false, true);
            Require(new RawSecurityDescriptor(privateParent).DiscretionaryAcl.Count == 4);
            Console.WriteLine("PASS provisioner-private-policy-unchanged");
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine("FAIL logon-policy " + error.GetType().Name); return 1; }
    }
}
