using System;
using System.Reflection;

public static class LegacyShortcutPolicyFixtures
{
    private static int _passed = 0;
    private static int _failed = 0;

    public static int Main(string[] args)
    {
        MethodInfo method = typeof(ServerLauncher).GetMethod(
            "MatchesLegacyServerShortcut",
            BindingFlags.Static | BindingFlags.NonPublic);

        if (method == null)
        {
            Console.WriteLine("FAIL: MatchesLegacyServerShortcut method not found on ServerLauncher");
            return 1;
        }

        string legacyDir = @"C:\Users\User\AppData\Local\Syntaur";

        // Positive tests
        AssertMatch(method, "POS_STARTUP_NORMAL", true, legacyDir + @"\syntaur.exe", "", legacyDir, legacyDir, true);
        AssertMatch(method, "POS_STARTUP_CASE", true, legacyDir + @"\SYNTAUR.EXE", null, legacyDir, legacyDir, true);
        AssertMatch(method, "POS_STARTUP_TRAILING_SLASH", true, legacyDir + @"\syntaur.exe", "", legacyDir + @"\", legacyDir, true);
        AssertMatch(method, "POS_OTHER_NORMAL", true, legacyDir + @"\syntaur-viewer.exe", "--local-owner", legacyDir, legacyDir, false);
        AssertMatch(method, "POS_OTHER_TRAILING_SLASH", true, legacyDir + @"\syntaur-viewer.exe", "--local-owner", legacyDir + @"\", legacyDir, false);
        AssertMatch(method, "POS_LEGACYDIR_TRAILING_SLASH", true, legacyDir + @"\syntaur.exe", "", legacyDir, legacyDir + @"\", true);
        AssertMatch(method, "POS_CASE_FOLDING_ALL", true, @"c:\users\user\appdata\local\syntaur\SYNTAUR.EXE", "", @"C:\USERS\USER\APPDATA\LOCAL\SYNTAUR\", @"c:\Users\User\AppData\Local\Syntaur", true);

        // Negative tests
        AssertMatch(method, "NEG_TARGET_DOUBLE_SEPARATOR", false, legacyDir + @"\\syntaur.exe", "", legacyDir, legacyDir, true);
        AssertMatch(method, "NEG_CUSTOM_TARGET", false, legacyDir + @"\other.exe", "", legacyDir, legacyDir, true);
        AssertMatch(method, "NEG_REMOTE_CLIENT_ARGS", false, legacyDir + @"\syntaur-viewer.exe", "--remote-client", legacyDir, legacyDir, false);
        AssertMatch(method, "NEG_EXTRA_ARGS_STARTUP", false, legacyDir + @"\syntaur.exe", "--extra", legacyDir, legacyDir, true);
        AssertMatch(method, "NEG_EXTRA_ARGS_OTHER", false, legacyDir + @"\syntaur-viewer.exe", "--local-owner --extra", legacyDir, legacyDir, false);
        AssertMatch(method, "NEG_OTHER_WORKING_DIR", false, legacyDir + @"\syntaur.exe", "", @"C:\Other\Dir", legacyDir, true);
        AssertMatch(method, "NEG_RELATIVE_TARGET", false, @"syntaur.exe", "", legacyDir, legacyDir, true);
        AssertMatch(method, "NEG_UNC_TARGET", false, @"\\server\share\syntaur.exe", "", legacyDir, legacyDir, true);
        AssertMatch(method, "NEG_TRAVERSAL_DIR", false, legacyDir + @"\..\Syntaur\syntaur.exe", "", legacyDir, legacyDir, true);
        AssertMatch(method, "NEG_MALFORMED_DIR", false, @"invalid_path", "", legacyDir, legacyDir, true);
        AssertMatch(method, "NEG_NULL_TARGET", false, null, "", legacyDir, legacyDir, true);
        AssertMatch(method, "NEG_NULL_WORKDIR", false, legacyDir + @"\syntaur.exe", "", null, legacyDir, true);

        // Rejection fixtures with malformed legacyDirectory
        AssertMatch(method, "NEG_LEGACYDIR_SINGLE_DOT", false, @"C:\Dir\.\Sub\syntaur.exe", "", @"C:\Dir\.\Sub", @"C:\Dir\.\Sub", true);
        AssertMatch(method, "NEG_LEGACYDIR_REPEATED_SEPARATORS", false, @"C:\Dir\\Sub\syntaur.exe", "", @"C:\Dir\\Sub", @"C:\Dir\\Sub", true);
        AssertMatch(method, "NEG_LEGACYDIR_MULTIPLE_TRAILING_SLASHES", false, @"C:\Dir\Sub\syntaur.exe", "", @"C:\Dir\Sub\\", @"C:\Dir\Sub\\", true);
        AssertMatch(method, "NEG_LEGACYDIR_INVALID_COLON", false, @"C:\Dir:Sub\syntaur.exe", "", @"C:\Dir:Sub", @"C:\Dir:Sub", true);
        AssertMatch(method, "NEG_LEGACYDIR_ENV_VARS", false, @"C:\%APPDATA%\syntaur.exe", "", @"C:\%APPDATA%", @"C:\%APPDATA%", true);
        AssertMatch(method, "NEG_LEGACYDIR_CONTROL_CHARS", false, "C:\\Dir\tSub\\syntaur.exe", "", "C:\\Dir\tSub", "C:\\Dir\tSub", true);
        AssertMatch(method, "NEG_LEGACYDIR_TRAILING_SPACE_DOT", false, @"C:\Dir\Sub \syntaur.exe", "", @"C:\Dir\Sub ", @"C:\Dir\Sub ", true);
        AssertMatch(method, "NEG_LEGACYDIR_DEVICE_UNC", false, @"\\.\C:\Dir\syntaur.exe", "", @"\\.\C:\Dir", @"\\.\C:\Dir", true);
        AssertMatch(method, "NEG_TARGET_TRAILING_SLASH", false, legacyDir + @"\syntaur.exe\", "", legacyDir, legacyDir, true);

        Console.WriteLine(string.Format("Finished fixtures. Passed: {0}, Failed: {1}", _passed, _failed));
        return _failed == 0 ? 0 : 1;
    }

    private static void AssertMatch(MethodInfo method, string label, bool expected, string target, string arguments, string workingDirectory, string legacyDirectory, bool startup)
    {
        object resultObj = method.Invoke(null, new object[] { target, arguments, workingDirectory, legacyDirectory, startup });
        bool actual = (bool)resultObj;
        if (actual == expected)
        {
            Console.WriteLine(string.Format("[PASS] {0}", label));
            _passed++;
        }
        else
        {
            Console.WriteLine(string.Format("[FAIL] {0}: expected {1}, got {2}", label, expected, actual));
            _failed++;
        }
    }
}
