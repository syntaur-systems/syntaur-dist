using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32.SafeHandles;

internal static class ServerLauncher
{
    private const int Port = 18789;
    private const int OverallTimeoutMs = 30000;
    private const int ActivationOverallTimeoutMs = 120000;
    private const int ActivationDrainTimeoutMs = 75000;
    private const int PollMs = 250;
    private const int MaximumHealthBytes = 64 * 1024;
    private const int CleanupExitCode = 3;
    private const uint ProcessQueryLimitedInformation = 0x1000;
    private const uint Synchronize = 0x00100000;
    private const uint TokenQuery = 0x0008;
    private const uint WaitObject0 = 0;
    private const uint WaitTimeout = 0x102;
    private const uint WaitFailed = 0xffffffff;
    private const uint ErrorInsufficientBuffer = 122;
    private const uint NoError = 0;
    private const uint AfInet = 2;
    private const uint TcpTableOwnerPidListener = 3; // SDK TCP_TABLE_OWNER_PID_LISTENER
    private const uint EventModifyState = 0x0002;
    private const uint ReadControl = 0x00020000;
    private const uint EventAccess = EventModifyState | Synchronize | ReadControl;
    private const uint OwnerSecurityInformation = 0x00000001;
    private const uint DaclSecurityInformation = 0x00000004;
    private const uint SeKernelObject = 6;
    private const ushort SeDaclProtected = 0x1000;
    private static readonly SecurityIdentifier CreatorOwner = new SecurityIdentifier("S-1-3-0");
    private static readonly SecurityIdentifier TrustedInstaller = new SecurityIdentifier(
        "S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464");
    private static readonly long MutationRights = (long)(uint)(
        FileSystemRights.WriteData | FileSystemRights.AppendData |
        FileSystemRights.DeleteSubdirectoriesAndFiles | FileSystemRights.Delete |
        FileSystemRights.WriteExtendedAttributes | FileSystemRights.WriteAttributes |
        FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership) |
        0x40000000L | 0x10000000L; // GENERIC_WRITE | GENERIC_ALL
    private static readonly long AncestorMutationRights = (long)(uint)(
        FileSystemRights.DeleteSubdirectoriesAndFiles | FileSystemRights.Delete |
        FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership) |
        0x10000000L; // GENERIC_ALL

    [DllImport("iphlpapi.dll", SetLastError = true)]
    private static extern uint GetExtendedTcpTable(
        IntPtr table, ref uint size, bool sort, uint addressFamily, uint tableClass, uint reserved);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint desiredAccess, bool inheritHandle, int processId);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool QueryFullProcessImageName(
        SafeProcessHandle processHandle, uint flags, StringBuilder imageName, ref uint size);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(SafeProcessHandle handle, uint milliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(SafeWaitHandle handle, uint milliseconds);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetProcessTimes(
        SafeProcessHandle process, out FileTime creation, out FileTime exit,
        out FileTime kernel, out FileTime user);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetExitCodeProcess(SafeProcessHandle process, out uint exitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool ProcessIdToSessionId(int processId, out uint sessionId);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr OpenEvent(uint desiredAccess, bool inheritHandle, string name);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetEvent(SafeWaitHandle eventHandle);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern uint GetSecurityInfo(
        SafeWaitHandle handle, uint objectType, uint securityInformation,
        out IntPtr owner, IntPtr group, out IntPtr dacl, IntPtr sacl, out IntPtr descriptor);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool GetSecurityDescriptorControl(
        IntPtr descriptor, out ushort control, out uint revision);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool GetAce(IntPtr dacl, uint index, out IntPtr ace);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool EqualSid(IntPtr first, IntPtr second);

    [DllImport("kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr memory);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool TerminateProcess(SafeProcessHandle handle, uint exitCode);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(SafeProcessHandle processHandle, uint desiredAccess, out IntPtr tokenHandle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    [StructLayout(LayoutKind.Sequential)]
    private struct FileTime
    {
        internal uint Low;
        internal uint High;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct TcpRowOwnerPid
    {
        internal uint State;
        internal uint LocalAddress;
        internal uint LocalPort;
        internal uint RemoteAddress;
        internal uint RemotePort;
        internal uint OwningPid;
    }

    private enum ProcessState { Alive, Exited, Unknown }

    private sealed class GatewayProcess : IDisposable
    {
        private Process child;
        internal readonly SafeProcessHandle Handle;
        internal readonly int Id;
        internal readonly bool NewlyStarted;

        internal GatewayProcess(int existingId)
        {
            IntPtr handle = OpenProcess(ProcessQueryLimitedInformation | Synchronize, false, existingId);
            if (handle == IntPtr.Zero)
                throw new InvalidOperationException();
            Id = existingId;
            Handle = new SafeProcessHandle(handle, true);
        }

        internal GatewayProcess(Process startedChild)
        {
            child = startedChild;
            Id = startedChild.Id;
            Handle = new SafeProcessHandle(startedChild.Handle, false);
            NewlyStarted = true;
        }

        internal ProcessState State()
        {
            uint result = WaitForSingleObject(Handle, 0);
            if (result == WaitTimeout)
                return ProcessState.Alive;
            if (result == WaitObject0)
                return ProcessState.Exited;
            return ProcessState.Unknown;
        }

        internal void RequireAlive()
        {
            if (State() != ProcessState.Alive)
                throw new LaunchFailure("The Syntaur server exited or its lifetime could not be verified.");
        }

        public void Dispose()
        {
            Handle.Dispose();
            if (child != null)
                child.Dispose();
            child = null;
        }
    }

    private sealed class LaunchFailure : Exception
    {
        internal LaunchFailure(string message) : base(message) { }
    }

    /// The existing 30-second startup allowance, capped by the original
    /// activation operation when this is a saved-setup handoff.
    private sealed class StartupDeadline
    {
        private readonly Stopwatch startup = Stopwatch.StartNew();
        private readonly Stopwatch activation;
        internal StartupDeadline(Stopwatch activation) { this.activation = activation; }
        internal int RemainingMilliseconds
        {
            get
            {
                long remaining = OverallTimeoutMs - startup.ElapsedMilliseconds;
                if (activation != null)
                    remaining = Math.Min(remaining, ActivationOverallTimeoutMs - activation.ElapsedMilliseconds);
                return (int)Math.Max(0, remaining);
            }
        }
    }

    [STAThread]
    private static int Main(string[] args)
    {
        bool background = args.Length == 1 && args[0] == "--background";
        bool logon = args.Length == 1 && args[0] == "--logon";
        bool installerStop = args.Length == 1 && args[0] == "--installer-stop";
        int activationPid;
        ulong activationCreation;
        bool afterSetup = TryParseActivationArguments(args, out activationPid, out activationCreation);
        if (args.Length != 0 && !background && !logon && !afterSetup && !installerStop)
        {
            ShowFailure("Syntaur received an unsupported launch request.", false);
            return 2;
        }

        GatewayProcess startedGateway = null;
        try
        {
            // A machine Startup shortcut is evaluated at every login. No
            // process, profile or private file is created for another owner.
            if (logon && !HasLogonOwner()) return 0;
            if (installerStop)
                RunInstallerStop();
            else if (afterSetup)
                RunAfterSetup(activationPid, activationCreation, ref startedGateway);
            else
                Run(background || logon, ref startedGateway);
            return 0;
        }
        catch (LaunchFailure error)
        {
            if (!StopNewGateway(startedGateway))
            {
                ShowFailure("Syntaur startup failed, and server cleanup could not be confirmed.", background || logon || afterSetup || installerStop);
                return CleanupExitCode;
            }
            ShowFailure(error.Message, background || logon || afterSetup || installerStop);
            return 1;
        }
        catch
        {
            if (!StopNewGateway(startedGateway))
            {
                ShowFailure("Syntaur startup failed, and server cleanup could not be confirmed.", background || logon || afterSetup || installerStop);
                return CleanupExitCode;
            }
            ShowFailure("Syntaur could not start the local server.", background || logon || afterSetup || installerStop);
            return 1;
        }
    }

    private static bool HasLogonOwner()
    {
        ValidateCurrentUser();
        try
        {
            using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
            {
                string data = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
                if (String.IsNullOrEmpty(data) || data.Length < 3 || data[1] != ':' || data[2] != '\\' ||
                    !String.Equals(Path.GetFullPath(data), data, StringComparison.OrdinalIgnoreCase))
                    throw new LaunchFailure("Syntaur could not verify its installed owner scope.");
                string shared = Path.Combine(data, "Syntaur", "LinkTor", "shared");
                string leaf = Path.Combine(shared, identity.User.Value);
                if (!Directory.Exists(leaf)) return false;
                ValidateProgramDirectoryChain(leaf);
                SecurityIdentifier service = (SecurityIdentifier)new NTAccount("NT SERVICE", "SyntaurLinkTor")
                    .Translate(typeof(SecurityIdentifier));
                string parent = data;
                foreach (string part in new[] { "Syntaur", "LinkTor", "shared" })
                {
                    parent = Path.Combine(parent, part);
                    ValidateLogonSecurity(new RawSecurityDescriptor(
                        Directory.GetAccessControl(parent).GetSecurityDescriptorBinaryForm(), 0),
                        service, identity.User, false);
                }
                ValidateLogonSecurity(new RawSecurityDescriptor(
                    Directory.GetAccessControl(leaf).GetSecurityDescriptorBinaryForm(), 0),
                    service, identity.User, true);
                return true;
            }
        }
        catch (UnauthorizedAccessException) { return false; }
        catch (DirectoryNotFoundException) { return false; }
        catch (IdentityNotMappedException) { return false; }
    }

    // Admission is a startup preference, not enrollment or service authority.
    // Gateway/HOST still perform their retained-handle path and role checks.
    private static void ValidateLogonSecurity(RawSecurityDescriptor descriptor,
        SecurityIdentifier service, SecurityIdentifier gateway, bool leaf)
    {
        SecurityIdentifier system = new SecurityIdentifier("S-1-5-18");
        SecurityIdentifier administrators = new SecurityIdentifier("S-1-5-32-544");
        if (descriptor.DiscretionaryAcl == null ||
            (descriptor.ControlFlags & ControlFlags.DiscretionaryAclProtected) == 0 ||
            (leaf ? descriptor.Owner != gateway : descriptor.Owner != system && descriptor.Owner != administrators))
            throw new LaunchFailure("Syntaur's installed owner scope has unexpected protection.");
        Dictionary<SecurityIdentifier, int> expected = new Dictionary<SecurityIdentifier, int>();
        expected.Add(system, 0x1f01ff);
        expected.Add(gateway, leaf ? 0x1f01ff : 0x1200a9);
        expected.Add(service, 0x1200a9);
        if (!leaf) expected.Add(administrators, 0x1f01ff);
        if (descriptor.DiscretionaryAcl.Count != expected.Count)
            throw new LaunchFailure("Syntaur's installed owner scope has unexpected access.");
        foreach (GenericAce entry in descriptor.DiscretionaryAcl)
        {
            CommonAce ace = entry as CommonAce;
            int mask;
            if (ace == null || ace.IsCallback || ace.AceQualifier != AceQualifier.AccessAllowed ||
                ace.AceFlags != (AceFlags.ObjectInherit | AceFlags.ContainerInherit) ||
                !expected.TryGetValue(ace.SecurityIdentifier, out mask) || ace.AccessMask != mask)
                throw new LaunchFailure("Syntaur's installed owner scope has unexpected access.");
            expected.Remove(ace.SecurityIdentifier);
        }
    }

    // MSI's immediate impersonated preflight runs in the installing user's
    // session. Never bridge SYSTEM/another session, launch a replacement, or
    // kill a process to make maintenance succeed. Later MSI cancellation can
    // leave this server stopped; Windows Installer does not restore its run state.
    private static void RunInstallerStop()
    {
        using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
        {
            if (identity.User == null || !identity.User.Value.StartsWith("S-1-5-21-", StringComparison.Ordinal))
                throw new LaunchFailure("Close Syntaur in its original Windows session before continuing setup.");
        }
        string programs = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        if (String.IsNullOrEmpty(programs) || programs.Length < 3 || programs[1] != ':' || programs[2] != '\\')
            throw new LaunchFailure("Syntaur could not verify its installed program location.");
        string directory = Path.Combine(programs, "Syntaur");
        string gatewayPath = Path.GetFullPath(Path.Combine(directory, "syntaur.exe"));
        using (GatewayProcess previous = FindOwnedGateway(gatewayPath, true))
        {
            if (previous == null) return;
            ValidateProgramDirectoryChain(directory);
            RequireProgramFile(directory, "syntaur.exe");
            ulong creation = ProcessCreation(previous.Handle);
            VerifyActivationProcess(previous, gatewayPath, creation);
            IntPtr raw = OpenEvent(EventModifyState | ReadControl, false,
                String.Format(CultureInfo.InvariantCulture, @"Local\Syntaur.Setup.{0}.{1:x16}", previous.Id, creation));
            if (raw == IntPtr.Zero)
                throw new LaunchFailure("Close Syntaur in its original Windows session before continuing setup.");
            using (SafeWaitHandle notification = new SafeWaitHandle(raw, true))
            {
                VerifyActivationEvent(notification);
                VerifyActivationProcess(previous, gatewayPath, creation);
                if (!SetEvent(notification) || WaitForSingleObject(previous.Handle, ActivationDrainTimeoutMs) != WaitObject0)
                    throw new LaunchFailure("Syntaur did not finish closing before maintenance.");
                uint exit;
                if (!GetExitCodeProcess(previous.Handle, out exit) || exit != 0)
                    throw new LaunchFailure("Syntaur did not finish closing before maintenance.");
            }
        }
    }

    private static bool TryParseActivationArguments(string[] args, out int pid, out ulong creation)
    {
        pid = 0;
        creation = 0;
        if (args.Length != 3 || args[0] != "--after-setup" ||
            !Int32.TryParse(args[1], NumberStyles.None, CultureInfo.InvariantCulture, out pid) || pid <= 0 ||
            args[2].Length != 16 ||
            !UInt64.TryParse(args[2], NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out creation))
            return false;
        return args[2] == creation.ToString("x16", CultureInfo.InvariantCulture);
    }

    private static void RunAfterSetup(int pid, ulong expectedCreation, ref GatewayProcess startedGateway)
    {
        Stopwatch operation = Stopwatch.StartNew();
        ValidateCurrentUser();
        string baseDirectory = Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
        ValidateProgramDirectoryChain(baseDirectory);
        string gatewayPath = RequireProgramFile(baseDirectory, "syntaur.exe");

        using (GatewayProcess previous = new GatewayProcess(pid))
        {
            VerifyActivationProcess(previous, gatewayPath, expectedCreation);
            string eventName = String.Format(CultureInfo.InvariantCulture,
                @"Local\Syntaur.Setup.{0}.{1:x16}", pid, expectedCreation);
            IntPtr rawEvent = OpenEvent(EventModifyState | ReadControl, false, eventName);
            if (rawEvent == IntPtr.Zero)
                throw new LaunchFailure("Syntaur could not open the saved-setup activation notification.");
            using (SafeWaitHandle activation = new SafeWaitHandle(rawEvent, true))
            {
                VerifyActivationEvent(activation);
                VerifyActivationProcess(previous, gatewayPath, expectedCreation);
                if (operation.ElapsedMilliseconds >= ActivationOverallTimeoutMs)
                    throw new LaunchFailure("Syntaur setup activation exceeded its deadline.");
                if (!SetEvent(activation))
                    throw new LaunchFailure("Syntaur could not request saved-setup activation.");

                long remaining = Math.Min(ActivationDrainTimeoutMs,
                    ActivationOverallTimeoutMs - operation.ElapsedMilliseconds);
                if (remaining <= 0)
                    throw new LaunchFailure("Syntaur setup activation exceeded its deadline.");
                uint waited = WaitForSingleObject(previous.Handle, (uint)remaining);
                if (waited != WaitObject0)
                    throw new LaunchFailure("Syntaur did not finish the saved-setup shutdown cleanly.");
                uint exitCode;
                if (!GetExitCodeProcess(previous.Handle, out exitCode) || exitCode != 0)
                    throw new LaunchFailure("Syntaur did not finish the saved-setup shutdown cleanly.");
            }
        }

        if (operation.ElapsedMilliseconds >= ActivationOverallTimeoutMs)
            throw new LaunchFailure("Syntaur setup activation exceeded its deadline.");
        Run(true, ref startedGateway, operation);
    }

    private static void VerifyActivationProcess(
        GatewayProcess process, string gatewayPath, ulong expectedCreation)
    {
        process.RequireAlive();
        string processPath;
        if (!TryQueryImagePath(process.Handle, out processPath) ||
            !String.Equals(processPath, gatewayPath, StringComparison.OrdinalIgnoreCase) ||
            !ProcessHasCurrentUserSid(process.Handle) || ProcessCreation(process.Handle) != expectedCreation)
            throw new LaunchFailure("Syntaur could not verify the saved-setup server identity.");
        uint processSession;
        uint currentSession;
        if (!ProcessIdToSessionId(process.Id, out processSession) ||
            !ProcessIdToSessionId(Process.GetCurrentProcess().Id, out currentSession) ||
            !SameActivationSession(processSession, currentSession))
            throw new LaunchFailure("Syntaur could not verify the saved-setup server session.");
    }

    private static bool SameActivationSession(uint processSession, uint currentSession)
    {
        return processSession == currentSession;
    }

    private static ulong ProcessCreation(SafeProcessHandle process)
    {
        FileTime creation;
        FileTime exit;
        FileTime kernel;
        FileTime user;
        if (!GetProcessTimes(process, out creation, out exit, out kernel, out user))
            throw new LaunchFailure("Syntaur could not verify the saved-setup server start time.");
        return ((ulong)creation.High << 32) | creation.Low;
    }

    private static void VerifyActivationEvent(SafeWaitHandle activation)
    {
        IntPtr owner = IntPtr.Zero;
        IntPtr dacl = IntPtr.Zero;
        IntPtr descriptor = IntPtr.Zero;
        IntPtr currentSid = IntPtr.Zero;
        IntPtr systemSid = IntPtr.Zero;
        try
        {
            uint status = GetSecurityInfo(activation, SeKernelObject,
                OwnerSecurityInformation | DaclSecurityInformation,
                out owner, IntPtr.Zero, out dacl, IntPtr.Zero, out descriptor);
            if (status != NoError || descriptor == IntPtr.Zero || owner == IntPtr.Zero || dacl == IntPtr.Zero)
                throw new LaunchFailure("Syntaur could not verify the activation notification security.");
            ushort control;
            uint revision;
            if (!GetSecurityDescriptorControl(descriptor, out control, out revision) ||
                (control & SeDaclProtected) == 0)
                throw new LaunchFailure("Syntaur activation notification inherits unsafe security.");

            using (WindowsIdentity current = WindowsIdentity.GetCurrent())
            {
                if (current.User == null)
                    throw new LaunchFailure("Syntaur could not verify the activation notification owner.");
                currentSid = SidPointer(current.User);
                systemSid = SidPointer(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null));
                if (!EqualSid(owner, currentSid))
                    throw new LaunchFailure("Syntaur activation notification has another owner.");
                int aclBytes = unchecked((ushort)Marshal.ReadInt16(dacl, 2));
                // ACL layout is Revision/Sbz1/Size/Count/Sbz2. Size is at 2;
                // the unsigned ACE count is at 4, never the size field.
                if (Marshal.ReadByte(dacl, 0) != 2 || aclBytes < 8 ||
                    unchecked((ushort)Marshal.ReadInt16(dacl, 4)) != 2)
                    throw new LaunchFailure("Syntaur activation notification has unexpected access entries.");
                bool sawUser = false;
                bool sawSystem = false;
                for (uint index = 0; index < 2; index++)
                {
                    IntPtr ace;
                    if (!GetAce(dacl, index, out ace) || ace == IntPtr.Zero)
                        throw new LaunchFailure("Syntaur could not read an activation access entry.");
                    long offset = checked(ace.ToInt64() - dacl.ToInt64());
                    if (offset < 8 || offset > aclBytes - 16)
                        throw new LaunchFailure("Syntaur activation access entry is outside its ACL.");
                    int aceBytes = unchecked((ushort)Marshal.ReadInt16(ace, 2));
                    if (aceBytes < 16 || aceBytes > aclBytes - offset ||
                        Marshal.ReadByte(ace, 0) != 0 || Marshal.ReadByte(ace, 1) != 0 ||
                        (uint)Marshal.ReadInt32(ace, 4) != EventAccess)
                        throw new LaunchFailure("Syntaur activation notification has unexpected access entries.");
                    IntPtr sid = IntPtr.Add(ace, 8);
                    int subAuthorities = Marshal.ReadByte(sid, 1);
                    if (Marshal.ReadByte(sid, 0) != 1 || subAuthorities > 15 ||
                        8 + 4 * subAuthorities > aceBytes - 8)
                        throw new LaunchFailure("Syntaur activation access entry has an invalid SID.");
                    if (EqualSid(sid, currentSid) && !sawUser)
                        sawUser = true;
                    else if (EqualSid(sid, systemSid) && !sawSystem)
                        sawSystem = true;
                    else
                        throw new LaunchFailure("Syntaur activation notification grants another principal access.");
                }
                if (!sawUser || !sawSystem)
                    throw new LaunchFailure("Syntaur activation notification lacks its required principals.");
            }
        }
        finally
        {
            if (currentSid != IntPtr.Zero) Marshal.FreeHGlobal(currentSid);
            if (systemSid != IntPtr.Zero) Marshal.FreeHGlobal(systemSid);
            if (descriptor != IntPtr.Zero) LocalFree(descriptor);
        }
    }

    private static IntPtr SidPointer(SecurityIdentifier sid)
    {
        byte[] bytes = new byte[sid.BinaryLength];
        sid.GetBinaryForm(bytes, 0);
        IntPtr pointer = Marshal.AllocHGlobal(bytes.Length);
        Marshal.Copy(bytes, 0, pointer, bytes.Length);
        return pointer;
    }

    private static void Run(bool background, ref GatewayProcess startedGateway, Stopwatch activation = null)
    {
        ValidateCurrentUser();
        string baseDirectory = Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
        ValidateProgramDirectoryChain(baseDirectory);
        string gatewayPath = RequireProgramFile(baseDirectory, "syntaur.exe");
        string viewerPath = RequireProgramFile(baseDirectory, "syntaur-viewer.exe");
        string workingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (!Directory.Exists(workingDirectory))
            throw new LaunchFailure("Syntaur could not locate the user profile.");
        if (!EnsureLicenseAccepted(baseDirectory, workingDirectory, background)) return;

        // Only the installed selected owner may retire the old per-user server.
        // The old binary is never adopted as the installed server.
        Stopwatch migration = activation ?? Stopwatch.StartNew();
        List<LegacyShortcut> legacy = new List<LegacyShortcut>();
        // A custom, unavailable or unsafe alias is not migration authority and
        // must not veto an otherwise valid installed-server startup.
        try { if (HasLogonOwner()) legacy = FindLegacyShortcuts(baseDirectory); }
        catch { legacy.Clear(); }
        GatewayProcess gateway = FindOwnedGateway(gatewayPath);
        if (gateway == null && HasAnyPortListener())
            DrainLegacyServer(legacy, migration);
        StartupDeadline clock = new StartupDeadline(migration);
        try
        {
            if (gateway == null)
            {
                if (HasAnyPortListener())
                    throw new LaunchFailure("Another application is using the Syntaur server port.");
                ProcessStartInfo gatewayInfo = StartInfo(gatewayPath, null, workingDirectory);
                gatewayInfo.EnvironmentVariables["SYNTAUR_LAUNCHER_OWNS_UI"] = "1";
                using (WindowsIdentity current = WindowsIdentity.GetCurrent())
                {
                    SecurityIdentifier service = (SecurityIdentifier)new NTAccount(
                        @"NT SERVICE\SyntaurLinkTor").Translate(typeof(SecurityIdentifier));
                    SetHostEnvironment(gatewayInfo,
                        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                        current.User, service);
                }
                if (clock.RemainingMilliseconds <= 0)
                    throw new LaunchFailure("Syntaur setup activation exceeded its deadline.");
                Process child = Process.Start(gatewayInfo);
                if (child == null)
                    throw new LaunchFailure("Syntaur could not start the server.");
                gateway = new GatewayProcess(child);
                startedGateway = gateway;
            }

            WaitUntilHealthy(gateway, clock);
            if (!background)
            {
                using (Process viewer = Process.Start(StartInfo(viewerPath, "--local-owner", workingDirectory)))
                {
                    if (viewer == null || viewer.HasExited)
                        throw new LaunchFailure("Syntaur Viewer exited during startup.");
                }
            }
            startedGateway = null;
            // Startup has committed. A shortcut collision must not tear down a
            // healthy server or discard either the old shortcut or its backup.
            foreach (LegacyShortcut shortcut in legacy)
            {
                try { RetireLegacyShortcut(shortcut, workingDirectory); }
                catch
                {
                    ShowFailure("Syntaur is running, but an old shortcut could not be moved. Your data is unchanged.", background);
                    break;
                }
            }
        }
        finally
        {
            if (!Object.ReferenceEquals(gateway, startedGateway) && gateway != null)
                gateway.Dispose();
        }
    }

    private const string EulaHash = "3e417ea33bc2d6296070222df816a6d145846743c1d98e7e4d20c7c2c8e9a720";
    private const string EulaUrl = "https://raw.githubusercontent.com/syntaur-systems/syntaur-dist/8811aa006673caa5082a7c9343e83c0b7ac51d16/EULA.md";

    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    private class ShellLink { }

    // SDK IShellLinkW order. Read raw fields only; never Resolve or execute a
    // shortcut while deciding whether it is an obsolete server alias.
    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface ShellLinkFields
    {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int capacity, IntPtr data, uint flags);
        void GetIDList(out IntPtr id); void SetIDList(IntPtr id);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder text, int capacity);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string text);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int capacity);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string path);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder text, int capacity);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string text);
        void GetHotkey(out short key); void SetHotkey(short key);
        void GetShowCmd(out int command); void SetShowCmd(int command);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path, int capacity, out int index);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string path, int index);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string path, uint reserved);
        void Resolve(IntPtr window, uint flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string path);
    }

    [StructLayout(LayoutKind.Sequential)] private struct ShortcutFileInfo
    {
        internal uint Attributes; internal System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
        internal uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(string path, uint access, uint share,
        IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle file, out ShortcutFileInfo info);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetFileInformationByHandle(SafeFileHandle file, int type, IntPtr info, uint size);

    private sealed class ShortcutParents : IDisposable
    {
        private readonly List<SafeFileHandle> handles = new List<SafeFileHandle>();
        internal SafeFileHandle Leaf { get { return handles[handles.Count - 1]; } }
        internal ShortcutParents(string directory)
        {
            List<string> paths = new List<string>();
            for (DirectoryInfo part = new DirectoryInfo(directory); part != null; part = part.Parent) paths.Add(part.FullName);
            paths.Reverse();
            try
            {
                foreach (string path in paths)
                {
                    SafeFileHandle handle = CreateFile(path, 0x80 | ReadControl, 3, IntPtr.Zero, 3, 0x2200000, IntPtr.Zero);
                    handles.Add(handle);
                    ShortcutFileInfo info;
                    if (handle.IsInvalid || !GetFileInformationByHandle(handle, out info) ||
                        (info.Attributes & 0x410) != 0x10) throw new IOException("unsafe-shortcut-parent");
                }
                // Pinned ancestors cannot be renamed while their owner/ACL is checked.
                ValidateProgramDirectoryChain(directory);
            }
            catch { Dispose(); throw; }
        }
        public void Dispose() { for (int i = handles.Count - 1; i >= 0; i--) handles[i].Dispose(); handles.Clear(); }
    }

    private sealed class LegacyShortcut
    {
        internal string Path, BackupName, LegacyDirectory, Digest;
        internal bool Startup;
        internal ShortcutFileInfo Identity;
    }

    private static FileStream OpenShortcut(string path, bool rename)
    {
        SafeFileHandle handle = CreateFile(path, 0x80000000 | ReadControl | (rename ? 0x10000U : 0),
            1, IntPtr.Zero, 3, 0x200000, IntPtr.Zero);
        if (handle.IsInvalid) { handle.Dispose(); throw new IOException("shortcut-open"); }
        try
        {
            ShortcutFileInfo info;
            if (!GetFileInformationByHandle(handle, out info) || (info.Attributes & 0x410) != 0 ||
                info.Links != 1 || info.SizeHigh != 0 || info.SizeLow == 0 || info.SizeLow > 65536)
                throw new IOException("unsafe-shortcut-file");
            FileStream stream = new FileStream(handle, FileAccess.Read);
            handle = null;
            try { ValidateAuthority(path, stream.GetAccessControl()); return stream; }
            catch { stream.Dispose(); throw; }
        }
        finally { if (handle != null) handle.Dispose(); }
    }

    private static string ShortcutDigest(FileStream stream)
    {
        stream.Position = 0;
        using (SHA256 hash = SHA256.Create()) return Convert.ToBase64String(hash.ComputeHash(stream));
    }

    private static bool ReadShortcutFields(string path, out string target, out string arguments, out string directory)
    {
        object link = new ShellLink();
        try
        {
            ((System.Runtime.InteropServices.ComTypes.IPersistFile)link).Load(path, 0x20); // READ, DENY_WRITE
            ShellLinkFields fields = (ShellLinkFields)link;
            StringBuilder t = new StringBuilder(32768), a = new StringBuilder(32768), d = new StringBuilder(32768);
            fields.GetPath(t, t.Capacity, IntPtr.Zero, 4); // SLGP_RAWPATH
            fields.GetArguments(a, a.Capacity); fields.GetWorkingDirectory(d, d.Capacity);
            target = t.ToString(); arguments = a.ToString(); directory = d.ToString();
            return t.Length < t.Capacity - 1 && a.Length < a.Capacity - 1 && d.Length < d.Capacity - 1;
        }
        finally { Marshal.FinalReleaseComObject(link); }
    }

    private static LegacyShortcut InspectLegacyShortcut(string path, string backupName, string legacyDirectory, bool startup)
    {
        if (!File.Exists(path)) return null;
        using (ShortcutParents parents = new ShortcutParents(System.IO.Path.GetDirectoryName(path)))
        using (FileStream stream = OpenShortcut(path, false))
        {
            string target, arguments, directory;
            if (!ReadShortcutFields(path, out target, out arguments, out directory) ||
                !MatchesLegacyServerShortcut(target, arguments, directory, legacyDirectory, startup)) return null;
            LegacyShortcut result = new LegacyShortcut { Path = path, BackupName = backupName,
                LegacyDirectory = legacyDirectory, Startup = startup, Digest = ShortcutDigest(stream) };
            if (!GetFileInformationByHandle(stream.SafeFileHandle, out result.Identity)) throw new IOException("shortcut-identity");
            return result;
        }
    }

    private static List<LegacyShortcut> FindLegacyShortcuts(string installedDirectory)
    {
        string legacyDirectory = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Syntaur");
        List<LegacyShortcut> result = new List<LegacyShortcut>();
        foreach (Environment.SpecialFolder folder in new[] { Environment.SpecialFolder.Startup, Environment.SpecialFolder.Programs, Environment.SpecialFolder.DesktopDirectory })
        {
            bool startup = folder == Environment.SpecialFolder.Startup;
            string parent = Environment.GetFolderPath(folder);
            if (String.IsNullOrEmpty(parent)) continue;
            LegacyShortcut shortcut = InspectLegacyShortcut(System.IO.Path.Combine(parent, startup ? "Syntaur Service.lnk" : "Syntaur.lnk"),
                startup ? "startup.lnk" : folder == Environment.SpecialFolder.Programs ? "programs.lnk" : "desktop.lnk", legacyDirectory, startup);
            if (shortcut != null) result.Add(shortcut);
        }
        if (result.Count == 0) return result;
        // Require both normal MSI aliases before removing a working legacy alias.
        string launcher = System.IO.Path.Combine(installedDirectory, "ServerLauncher.exe");
        foreach (bool startup in new[] { false, true })
        {
            string common = System.IO.Path.Combine(Environment.GetFolderPath(startup
                ? Environment.SpecialFolder.CommonStartup : Environment.SpecialFolder.CommonPrograms), startup ? "Syntaur server.lnk" : "Syntaur.lnk");
            using (ShortcutParents parents = new ShortcutParents(System.IO.Path.GetDirectoryName(common)))
            using (FileStream stream = OpenShortcut(common, false))
            {
                string target, arguments, directory;
                if (!ReadShortcutFields(common, out target, out arguments, out directory) ||
                    !String.Equals(target, launcher, StringComparison.OrdinalIgnoreCase) ||
                    arguments != (startup ? "--logon" : "") ||
                    !String.Equals(directory.TrimEnd('\\'), installedDirectory.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase))
                    throw new LaunchFailure("Syntaur could not verify its installed shortcuts.");
            }
        }
        return result;
    }

    private static void VerifyShortcutUnchanged(FileStream stream, LegacyShortcut shortcut)
    {
        ShortcutFileInfo info;
        if (!GetFileInformationByHandle(stream.SafeFileHandle, out info) ||
            info.Volume != shortcut.Identity.Volume || info.IndexHigh != shortcut.Identity.IndexHigh ||
            info.IndexLow != shortcut.Identity.IndexLow || ShortcutDigest(stream) != shortcut.Digest)
            throw new IOException("shortcut-changed");
    }

    private static void DrainLegacyServer(List<LegacyShortcut> shortcuts, Stopwatch operation)
    {
        LegacyShortcut startup = shortcuts.Find(delegate(LegacyShortcut item) { return item.Startup; });
        if (startup == null) return; // Ordinary occupied-port refusal remains below.
        ValidateProgramDirectoryChain(startup.LegacyDirectory);
        string path = RequireProgramFile(startup.LegacyDirectory, "syntaur.exe");
        using (ShortcutParents parents = new ShortcutParents(System.IO.Path.GetDirectoryName(startup.Path)))
        using (FileStream proof = OpenShortcut(startup.Path, false))
        using (GatewayProcess previous = FindOwnedGateway(path))
        {
            VerifyShortcutUnchanged(proof, startup);
            if (previous == null || !ConfirmOwnedListener(previous)) return;
            ulong creation = ProcessCreation(previous.Handle);
            VerifyActivationProcess(previous, path, creation);
            IntPtr raw = OpenEvent(EventModifyState | ReadControl, false,
                String.Format(CultureInfo.InvariantCulture, @"Local\Syntaur.Setup.{0}.{1:x16}", previous.Id, creation));
            if (raw == IntPtr.Zero) throw new LaunchFailure("Close the earlier Syntaur server, then open Syntaur again.");
            using (SafeWaitHandle notification = new SafeWaitHandle(raw, true))
            {
                VerifyActivationEvent(notification);
                VerifyActivationProcess(previous, path, creation);
                VerifyShortcutUnchanged(proof, startup);
                if (!ConfirmOwnedListener(previous)) throw new LaunchFailure("The earlier Syntaur server changed during startup.");
                long remaining = Math.Min(ActivationDrainTimeoutMs, ActivationOverallTimeoutMs - operation.ElapsedMilliseconds);
                if (remaining <= 0 || !SetEvent(notification) || WaitForSingleObject(previous.Handle, (uint)remaining) != WaitObject0)
                    throw new LaunchFailure("The earlier Syntaur server has not finished closing. Open Syntaur again after it closes.");
                uint exit;
                if (!GetExitCodeProcess(previous.Handle, out exit) || exit != 0)
                    throw new LaunchFailure("The earlier Syntaur server did not close cleanly.");
            }
        }
    }

    private static void RetireLegacyShortcut(LegacyShortcut shortcut, string profile)
    {
        string backup = System.IO.Path.Combine(profile, ".syntaur", "legacy-server-shortcuts");
        // Same protected current-user/SYSTEM/Administrators directory policy as
        // the existing licence receipt; never place backups in Startup.
        EnsurePrivateDirectory(backup);
        using (ShortcutParents sourceParents = new ShortcutParents(System.IO.Path.GetDirectoryName(shortcut.Path)))
        using (ShortcutParents destinationParents = new ShortcutParents(backup))
        using (FileStream source = OpenShortcut(shortcut.Path, true))
        {
            VerifyShortcutUnchanged(source, shortcut);
            byte[] name = Encoding.Unicode.GetBytes(System.IO.Path.Combine(backup, shortcut.BackupName));
            IntPtr rename = Marshal.AllocHGlobal(24 + name.Length);
            try
            {
                // Reuse InstallerProvisioner's zero-filled x64 rename contract.
                // No replacement: an existing backup is never overwritten.
                for (int i = 0; i < 24 + name.Length; i++) Marshal.WriteByte(rename, i, 0);
                Marshal.WriteInt32(rename, 16, name.Length); Marshal.Copy(name, 0, IntPtr.Add(rename, 20), name.Length);
                if (!SetFileInformationByHandle(source.SafeFileHandle, 3, rename, (uint)(24 + name.Length)))
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "retain-legacy-shortcut");
            }
            finally { Marshal.FreeHGlobal(rename); }
        }
    }

    private static bool TryCanonicalizeDirectory(string path, out string canonical)
    {
        canonical = null;
        if (string.IsNullOrEmpty(path))
        {
            return false;
        }

        if (path.Length < 3 || path[1] != ':' || path[2] != '\\')
        {
            return false;
        }

        char drive = path[0];
        if (!((drive >= 'A' && drive <= 'Z') || (drive >= 'a' && drive <= 'z')))
        {
            return false;
        }

        int start = 3;
        bool hadTrailingSlash = false;
        System.Text.StringBuilder sb = new System.Text.StringBuilder();
        sb.Append(drive);
        sb.Append(@":\");

        int i = 3;
        while (i <= path.Length)
        {
            if (i == path.Length || path[i] == '\\')
            {
                int segLen = i - start;
                if (segLen == 0)
                {
                    if (i == path.Length && i > 3)
                    {
                        hadTrailingSlash = true;
                        break;
                    }
                    return false;
                }

                string segment = path.Substring(start, segLen);
                if (!IsValidSegment(segment))
                {
                    return false;
                }

                if (sb.Length > 3)
                {
                    sb.Append('\\');
                }
                sb.Append(segment);

                start = i + 1;
                if (i == path.Length - 1)
                {
                    hadTrailingSlash = true;
                    break;
                }
            }
            i++;
        }

        if (sb.Length == 3 && hadTrailingSlash)
        {
            canonical = sb.ToString();
            return true;
        }

        canonical = sb.ToString();
        return true;
    }

    private static bool IsValidSegment(string segment)
    {
        if (string.IsNullOrEmpty(segment))
        {
            return false;
        }

        if (segment == "." || segment == "..")
        {
            return false;
        }

        char last = segment[segment.Length - 1];
        if (last == ' ' || last == '.')
        {
            return false;
        }

        for (int i = 0; i < segment.Length; i++)
        {
            char c = segment[i];
            if (c < 32)
            {
                return false;
            }

            switch (c)
            {
                case '<':
                case '>':
                case ':':
                case '"':
                case '/':
                case '\\':
                case '|':
                case '?':
                case '*':
                case '%':
                    return false;
            }
        }

        return true;
    }

    private static bool MatchesLegacyServerShortcut(string target, string arguments, string workingDirectory, string legacyDirectory, bool startup)
    {
        string canonLegacy;
        if (!TryCanonicalizeDirectory(legacyDirectory, out canonLegacy))
        {
            return false;
        }

        string canonWorkDir;
        if (!TryCanonicalizeDirectory(workingDirectory, out canonWorkDir))
        {
            return false;
        }

        if (!string.Equals(canonWorkDir, canonLegacy, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (string.IsNullOrEmpty(target) || target.EndsWith("\\", StringComparison.Ordinal))
        {
            return false;
        }

        int lastSlash = target.LastIndexOf('\\');
        if (lastSlash < 3)
        {
            return false;
        }

        string targetDir = target.Substring(0, lastSlash);
        if (lastSlash == 2)
        {
            targetDir = target.Substring(0, 3);
        }

        string targetFileName = target.Substring(lastSlash + 1);
        if (!IsValidSegment(targetFileName))
        {
            return false;
        }

        string canonTargetDir;
        if (!TryCanonicalizeDirectory(targetDir, out canonTargetDir))
        {
            return false;
        }

        if (!string.Equals(canonTargetDir, canonLegacy, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        string expectedExe = startup ? "syntaur.exe" : "syntaur-viewer.exe";
        if (!string.Equals(targetFileName, expectedExe, StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(target, canonLegacy + @"\" + expectedExe, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (startup)
        {
            return string.IsNullOrEmpty(arguments);
        }
        else
        {
            return string.Equals(arguments, "--local-owner", StringComparison.Ordinal);
        }
    }

    private static bool CurrentLicenseRecord(string text)
    {
        string[] lines = text.Replace("\r\n", "\n").TrimEnd('\n').Split('\n');
        if (lines.Length != 7) return false;
        Dictionary<string, string> fields = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (string line in lines)
        {
            int split = line.IndexOf('=');
            if (split <= 0 || fields.ContainsKey(line.Substring(0, split))) return false;
            fields.Add(line.Substring(0, split), line.Substring(split + 1));
        }
        foreach (string key in new string[] { "record_format", "eula_version", "eula_sha256", "eula_url", "accepted_at", "method", "installer_version" })
            if (!fields.ContainsKey(key)) return false;
        DateTime accepted;
        return fields["record_format"] == "1" && fields["eula_version"] == "1.0" &&
            fields["eula_sha256"] == EulaHash && fields["eula_url"] == EulaUrl &&
            (fields["method"] == "prompt" || fields["method"] == "flag") &&
            DateTime.TryParseExact(fields["accepted_at"], "yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out accepted) &&
            System.Text.RegularExpressions.Regex.IsMatch(fields["installer_version"], @"\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z");
    }

    private static bool ReadLicenseRecord(string directory)
    {
        if (!Directory.Exists(directory)) return false;
        if ((File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0)
            throw new LaunchFailure("Syntaur's licence record directory is unsafe.");
        DirectorySecurity directorySecurity = Directory.GetAccessControl(directory);
        using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
            if ((directorySecurity.GetOwner(typeof(SecurityIdentifier)) as SecurityIdentifier) != identity.User)
                throw new LaunchFailure("Syntaur's private directory belongs to another Windows account.");
        ValidateAuthority(directory, directorySecurity);
        string path = Path.Combine(directory, "eula-accepted");
        if (!File.Exists(path)) return false;
        if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
            throw new LaunchFailure("Syntaur's licence record is unsafe.");
        ValidateAuthority(path, File.GetAccessControl(path));
        using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            if (stream.Length <= 0 || stream.Length > 4096) return false;
            using (StreamReader reader = new StreamReader(stream, new UTF8Encoding(false, true)))
                return CurrentLicenseRecord(reader.ReadToEnd());
        }
    }

    private static bool EnsureLicenseAccepted(string programDirectory, string profile, bool background)
    {
        // The OS supplies the genuine profile; never trust HOME/USERPROFILE.
        // The existing path authority checks reject links and other-user writes.
        ValidateProgramDirectoryChain(profile);
        string directory = Path.Combine(profile, ".syntaur");
        if (ReadLicenseRecord(directory)) return true;
        // Startup may not manufacture consent or open an unattended dialog.
        if (background) return false;
        string licensePath = RequireProgramFile(programDirectory, "EULA.md");
        string license;
        using (FileStream stream = new FileStream(licensePath, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            if (stream.Length <= 0 || stream.Length > 65536) throw new LaunchFailure("Syntaur's licence exceeds its bounds.");
            using (SHA256 sha = SHA256.Create())
                if (BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "").ToLowerInvariant() != EulaHash)
                    throw new LaunchFailure("Syntaur's licence does not match this version.");
            stream.Position = 0;
            using (StreamReader reader = new StreamReader(stream, new UTF8Encoding(false, true))) license = reader.ReadToEnd();
        }
        if (!LicenseConsentDialog.Show(license, EulaUrl)) return false;
        string version = Microsoft.Win32.Registry.GetValue(@"HKEY_LOCAL_MACHINE\SOFTWARE\Syntaur\Server", "Version", null) as string;
        if (version == null || !System.Text.RegularExpressions.Regex.IsMatch(version, @"\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\z"))
            throw new LaunchFailure("Syntaur could not read its installed version.");
        string record = "record_format=1\neula_version=1.0\neula_sha256=" + EulaHash + "\neula_url=" + EulaUrl +
            "\naccepted_at=" + DateTime.UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture) +
            "\nmethod=prompt\ninstaller_version=" + version + "\n";
        WriteLicenseRecord(directory, record);
        return ReadLicenseRecord(directory);
    }

    private static void WriteLicenseRecord(string directory, string record)
    {
        if (!CurrentLicenseRecord(record)) throw new LaunchFailure("Syntaur's licence acceptance record is invalid.");
        EnsurePrivateDirectory(directory);
        // Validate any existing target before atomic replacement; never rewrite
        // an unsafe owner/DACL or follow an existing record link.
        ReadLicenseRecord(directory);
        string path = Path.Combine(directory, "eula-accepted");
        string temporary = Path.Combine(directory, ".eula-accepted.tmp." + Guid.NewGuid().ToString("N"));
        try
        {
            byte[] bytes = new UTF8Encoding(false).GetBytes(record);
            using (FileStream stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                stream.Write(bytes, 0, bytes.Length);
                stream.Flush(true);
            }
            if (File.Exists(path)) File.Replace(temporary, path, null, true);
            else File.Move(temporary, path);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    private static void EnsurePrivateDirectory(string directory)
    {
        ValidateProgramDirectoryChain(Path.GetDirectoryName(directory));
        if (!Directory.Exists(directory))
        {
            DirectorySecurity security = new DirectorySecurity();
            using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
            {
                security.SetOwner(identity.User);
                security.SetAccessRuleProtection(true, false);
                foreach (SecurityIdentifier sid in new SecurityIdentifier[] { identity.User,
                    new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null),
                    new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null) })
                    security.AddAccessRule(new FileSystemAccessRule(sid, FileSystemRights.FullControl,
                        InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
                        PropagationFlags.None, AccessControlType.Allow));
            }
            Directory.CreateDirectory(directory, security);
        }
        ValidateProgramDirectoryChain(directory);
        using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
            if ((Directory.GetAccessControl(directory).GetOwner(typeof(SecurityIdentifier)) as SecurityIdentifier) != identity.User)
                throw new LaunchFailure("Syntaur's private directory belongs to another Windows account.");
    }

    // The installer provisions this same layout for its selected unelevated
    // server owner. Only the newly owned child receives these bindings. The
    // Gateway's existing handle-bound publisher validates the actual shared
    // directory; translating the service SID is not a readiness check.
    private static void SetHostEnvironment(ProcessStartInfo child, string programData,
        SecurityIdentifier gateway, SecurityIdentifier service)
    {
        if (gateway == null || service == null || gateway == service ||
            !service.Value.StartsWith("S-1-5-80-", StringComparison.Ordinal) ||
            service.Value.Split('-').Length != 9)
            throw new LaunchFailure("Syntaur could not verify its installed server identities.");
        if (String.IsNullOrWhiteSpace(programData) || programData.Length < 3 ||
            !Path.IsPathRooted(programData) || programData[1] != ':' || programData[2] != '\\')
            throw new LaunchFailure("Syntaur could not locate its installed server data.");
        string root = Path.GetFullPath(programData);
        string volume = Path.GetPathRoot(root);
        if (volume.Length != 3 || volume[1] != ':' || volume[2] != '\\')
            throw new LaunchFailure("Syntaur server data must be on a local Windows volume.");
        string pipe = @"\\.\pipe\Syntaur.Link.host." + gateway.Value;
        if (pipe.Length > 128)
            throw new LaunchFailure("Syntaur's installed server identity exceeds its bounds.");
        string pin = Path.Combine(root, "Syntaur", "LinkTor", "shared",
            gateway.Value, "gateway-pin.json");
        child.EnvironmentVariables["SYNTAUR_LINK_TOR_SERVICE_SID"] = service.Value;
        child.EnvironmentVariables["SYNTAUR_LINK_TOR_SOCKET"] = pipe;
        child.EnvironmentVariables["SYNTAUR_LINK_TOR_GATEWAY_PIN"] = pin;
    }

    private static ProcessStartInfo StartInfo(string path, string arguments, string workingDirectory)
    {
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = path;
        info.WorkingDirectory = workingDirectory;
        info.UseShellExecute = false;
        info.CreateNoWindow = true;
        if (arguments != null)
            info.Arguments = arguments;
        return info;
    }

    private static void ValidateCurrentUser()
    {
        using (WindowsIdentity identity = WindowsIdentity.GetCurrent())
        {
            if (identity.User == null || identity.Owner == null || identity.User != identity.Owner)
                throw new LaunchFailure("Syntaur must run as a normal, unelevated Windows user.");
            if (identity.User.IsWellKnown(WellKnownSidType.LocalSystemSid) ||
                new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))
                throw new LaunchFailure("Syntaur must not run elevated or as SYSTEM.");
        }
    }

    private static void ValidateProgramDirectoryChain(string path)
    {
        DirectoryInfo directory = new DirectoryInfo(path);
        bool aboveProgramDirectory = false;
        while (directory != null)
        {
            if (!directory.Exists || (directory.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new LaunchFailure("Syntaur's program directory is unavailable or unsafe.");
            ValidateAuthority(directory.FullName, directory.GetAccessControl(), aboveProgramDirectory);
            aboveProgramDirectory = true;
            if (directory.Parent == null)
                break;
            directory = directory.Parent;
        }
    }

    private static string RequireProgramFile(string baseDirectory, string filename)
    {
        string path = Path.GetFullPath(Path.Combine(baseDirectory, filename));
        FileInfo file = new FileInfo(path);
        if (!file.Exists || (file.Attributes & FileAttributes.ReparsePoint) != 0)
            throw new LaunchFailure("A required Syntaur program is missing or unsafe.");
        ValidateAuthority(file.FullName, file.GetAccessControl());
        return path;
    }

    private static void ValidateAuthority(string path, FileSystemSecurity security, bool aboveProgramDirectory = false)
    {
        SecurityIdentifier owner = security.GetOwner(typeof(SecurityIdentifier)) as SecurityIdentifier;
        if (!TrustedSid(owner))
            throw new LaunchFailure("A Syntaur program path has an untrusted owner.");
        long mutationRights = aboveProgramDirectory ? AncestorMutationRights : MutationRights;
        foreach (FileSystemAccessRule rule in security.GetAccessRules(true, true, typeof(SecurityIdentifier)))
        {
            if (aboveProgramDirectory && (rule.PropagationFlags & PropagationFlags.InheritOnly) != 0)
                continue;
            if (rule.AccessControlType != AccessControlType.Allow ||
                ((long)(uint)rule.FileSystemRights & mutationRights) == 0)
                continue;
            if (rule.IdentityReference == CreatorOwner &&
                ((rule.PropagationFlags & PropagationFlags.InheritOnly) != 0 ||
                 rule.InheritanceFlags != InheritanceFlags.None))
                continue;
            if (!TrustedSid(rule.IdentityReference as SecurityIdentifier))
                throw new LaunchFailure("A Syntaur program path grants unsafe mutation access.");
        }
    }

    private static bool TrustedSid(SecurityIdentifier sid)
    {
        if (sid == null)
            return false;
        using (WindowsIdentity current = WindowsIdentity.GetCurrent())
        {
            return sid == current.User || sid.IsWellKnown(WellKnownSidType.LocalSystemSid) ||
                sid.IsWellKnown(WellKnownSidType.BuiltinAdministratorsSid) || sid == TrustedInstaller;
        }
    }

    private static GatewayProcess FindOwnedGateway(string gatewayPath, bool maintenance = false)
    {
        List<GatewayProcess> matches = new List<GatewayProcess>();
        try
        {
            foreach (Process process in Process.GetProcessesByName("syntaur"))
            {
                using (process)
                {
                    GatewayProcess candidate = null;
                    try
                    {
                        try { candidate = new GatewayProcess(process.Id); }
                        catch (InvalidOperationException)
                        {
                            if (maintenance) throw new LaunchFailure("Syntaur could not verify that the server has closed.");
                            continue;
                        }
                        string processPath;
                        if (!TryQueryImagePath(candidate.Handle, out processPath))
                        {
                            if (maintenance && candidate.State() != ProcessState.Exited)
                                throw new LaunchFailure("Syntaur could not verify that the server has closed.");
                            continue;
                        }
                        if (!String.Equals(processPath, gatewayPath, StringComparison.OrdinalIgnoreCase))
                            continue;
                        if (!ProcessHasCurrentUserSid(candidate.Handle))
                            throw new LaunchFailure("Syntaur could not verify the running server's owner.");
                        ProcessState state = candidate.State();
                        if (maintenance && state == ProcessState.Unknown)
                            throw new LaunchFailure("Syntaur could not verify that the server has closed.");
                        if (state != ProcessState.Alive)
                            continue;
                        matches.Add(candidate);
                        candidate = null;
                    }
                    finally
                    {
                        if (candidate != null)
                            candidate.Dispose();
                    }
                }
            }
            if (matches.Count > 1)
                throw new LaunchFailure("More than one Syntaur server instance was found.");
            GatewayProcess result = matches.Count == 1 ? matches[0] : null;
            matches.Clear();
            return result;
        }
        finally
        {
            foreach (GatewayProcess match in matches)
                match.Dispose();
        }
    }

    private static bool TryQueryImagePath(SafeProcessHandle handle, out string path)
    {
        uint capacity = 32768;
        StringBuilder image = new StringBuilder((int)capacity);
        if (!QueryFullProcessImageName(handle, 0, image, ref capacity))
        {
            path = null;
            return false;
        }
        try
        {
            path = Path.GetFullPath(image.ToString());
            return true;
        }
        catch
        {
            path = null;
            return false;
        }
    }

    private static bool ProcessHasCurrentUserSid(SafeProcessHandle handle)
    {
        IntPtr tokenHandle = IntPtr.Zero;
        try
        {
            if (!OpenProcessToken(handle, TokenQuery, out tokenHandle))
                return false;
            using (WindowsIdentity processIdentity = new WindowsIdentity(tokenHandle))
            using (WindowsIdentity currentIdentity = WindowsIdentity.GetCurrent())
            {
                return processIdentity.User != null && currentIdentity.User != null &&
                    processIdentity.User == currentIdentity.User;
            }
        }
        finally
        {
            if (tokenHandle != IntPtr.Zero)
                CloseHandle(tokenHandle);
        }
    }

    private static void WaitUntilHealthy(GatewayProcess gateway, StartupDeadline clock)
    {
        while (clock.RemainingMilliseconds > 0)
        {
            gateway.RequireAlive();
            if (ConfirmOwnedListener(gateway))
            {
                if (CheckHealth(clock))
                {
                    gateway.RequireAlive();
                    if (!ConfirmOwnedListener(gateway))
                        throw new LaunchFailure("The Syntaur server listener disappeared during startup.");
                    return;
                }
                gateway.RequireAlive();
                if (!ConfirmOwnedListener(gateway))
                    throw new LaunchFailure("The Syntaur server listener disappeared during startup.");
            }
            int sleepMs = Math.Min(PollMs, Math.Max(1, clock.RemainingMilliseconds));
            Thread.Sleep(sleepMs);
        }
        throw new LaunchFailure("The Syntaur server did not become ready within 30 seconds.");
    }

    private static bool ConfirmOwnedListener(GatewayProcess gateway)
    {
        gateway.RequireAlive();
        bool found = false;
        foreach (TcpRowOwnerPid row in ReadListenerRows())
        {
            if (ReadPort(row.LocalPort) != Port)
                continue;
            if (row.OwningPid != (uint)gateway.Id)
                throw new LaunchFailure("Another application is using the Syntaur server port.");
            IPAddress address = new IPAddress(row.LocalAddress);
            if (!IPAddress.Loopback.Equals(address) && !IPAddress.Any.Equals(address))
                throw new LaunchFailure("The Syntaur server port has an unexpected listener.");
            found = true;
        }
        return found;
    }

    private static bool CheckHealth(StartupDeadline clock)
    {
        int remaining = clock.RemainingMilliseconds;
        if (remaining <= 0)
            throw new LaunchFailure("The Syntaur server did not become ready within 30 seconds.");
        int ioTimeout = Math.Min(1000, remaining);
        HttpWebRequest request = (HttpWebRequest)WebRequest.Create("http://127.0.0.1:18789/health");
        request.Method = "GET";
        request.Proxy = null;
        request.AllowAutoRedirect = false;
        request.Timeout = ioTimeout;
        request.ReadWriteTimeout = ioTimeout;
        using (System.Threading.Timer deadline = new System.Threading.Timer(
            delegate { request.Abort(); }, null, remaining, Timeout.Infinite))
        {
            try
            {
                HttpWebResponse response;
                try
                {
                    response = (HttpWebResponse)request.GetResponse();
                }
                catch (WebException error)
                {
                    if (error.Status == WebExceptionStatus.Timeout && error.Response == null &&
                        clock.RemainingMilliseconds > 0)
                    {
                        request.Abort();
                        return false;
                    }
                    throw;
                }
                using (response)
                {
                    if (response.StatusCode != HttpStatusCode.OK || response.ContentLength > MaximumHealthBytes)
                        throw new LaunchFailure("The Syntaur server health check failed.");
                    using (Stream stream = response.GetResponseStream())
                    {
                        byte[] buffer = new byte[4096];
                        int total = 0;
                        int count;
                        while ((count = stream.Read(buffer, 0, buffer.Length)) > 0)
                        {
                            total += count;
                            if (total > MaximumHealthBytes)
                                throw new LaunchFailure("The Syntaur server health response was too large.");
                        }
                    }
                }
                if (clock.RemainingMilliseconds <= 0)
                    throw new LaunchFailure("The Syntaur server health check exceeded the launch deadline.");
                return true;
            }
            catch (LaunchFailure)
            {
                throw;
            }
            catch
            {
                throw new LaunchFailure("The Syntaur server health check failed.");
            }
        }
    }

    private static bool HasAnyPortListener()
    {
        foreach (TcpRowOwnerPid row in ReadListenerRows())
        {
            if (ReadPort(row.LocalPort) == Port)
                return true;
        }
        return false;
    }

    private static int ReadPort(uint networkPort)
    {
        return (int)((networkPort & 0xff) * 256 + ((networkPort >> 8) & 0xff));
    }

    private static TcpRowOwnerPid[] ReadListenerRows()
    {
        uint size = 0;
        uint result = GetExtendedTcpTable(IntPtr.Zero, ref size, false, AfInet, TcpTableOwnerPidListener, 0);
        if (result != ErrorInsufficientBuffer || size < 4)
            throw new LaunchFailure("Syntaur could not inspect local server listeners.");
        IntPtr buffer = Marshal.AllocHGlobal((int)size);
        try
        {
            result = GetExtendedTcpTable(buffer, ref size, false, AfInet, TcpTableOwnerPidListener, 0);
            if (result != NoError)
                throw new LaunchFailure("Syntaur could not inspect local server listeners.");
            int count = Marshal.ReadInt32(buffer);
            int rowSize = Marshal.SizeOf(typeof(TcpRowOwnerPid));
            if (count < 0 || (long)count * rowSize + 4 > size)
                throw new LaunchFailure("Syntaur received invalid local listener information.");
            TcpRowOwnerPid[] rows = new TcpRowOwnerPid[count];
            for (int index = 0; index < count; index++)
            {
                IntPtr row = new IntPtr(buffer.ToInt64() + 4 + (long)index * rowSize);
                rows[index] = (TcpRowOwnerPid)Marshal.PtrToStructure(row, typeof(TcpRowOwnerPid));
            }
            return rows;
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    private static bool StopNewGateway(GatewayProcess gateway)
    {
        if (gateway == null)
            return true;
        bool confirmed = false;
        try
        {
            if (!gateway.NewlyStarted)
                return true;
            ProcessState state = gateway.State();
            if (state == ProcessState.Exited)
                confirmed = true;
            else if (state == ProcessState.Alive && TerminateProcess(gateway.Handle, 1))
                confirmed = WaitForSingleObject(gateway.Handle, 5000) == WaitObject0;
        }
        catch
        {
            confirmed = false;
        }
        finally
        {
            gateway.Dispose();
        }
        return confirmed;
    }

    private static void ShowFailure(string message, bool background)
    {
        if (!background)
            MessageBox.Show(message, "Syntaur server", MessageBoxButtons.OK, MessageBoxIcon.Error);
    }
}

// UI only. The launcher verifies the packaged licence and owns the existing
// acceptance record; opening this dialog alone never grants consent.
internal static class LicenseConsentDialog
{
    internal static bool Show(string licenseText, string licenseUrl)
    {
        Application.EnableVisualStyles();
        using (Form form = new Form())
        {
            form.Text = "Welcome to Syntaur";
            form.Width = 760;
            form.Height = 620;
            form.StartPosition = FormStartPosition.CenterScreen;
            form.AutoScaleMode = AutoScaleMode.Font;
            form.MinimizeBox = false;
            TextBox license = new TextBox();
            license.Multiline = true;
            license.ReadOnly = true;
            license.ScrollBars = ScrollBars.Vertical;
            license.WordWrap = true;
            license.Dock = DockStyle.Fill;
            license.Text = licenseText;
            license.AccessibleName = "Syntaur licence agreement";
            license.TabIndex = 0;
            TextBox url = new TextBox();
            url.ReadOnly = true;
            url.Dock = DockStyle.Top;
            url.Text = licenseUrl;
            url.AccessibleName = "Permanent licence agreement address";
            url.TabIndex = 1;
            CheckBox accept = new CheckBox();
            accept.Text = "I have read and accept the Syntaur licence agreement.";
            accept.AccessibleName = accept.Text;
            accept.Dock = DockStyle.Top;
            accept.Height = 42;
            accept.TabIndex = 2;
            accept.Checked = false;
            Button proceed = new Button();
            proceed.Text = "Continue";
            proceed.Enabled = false;
            proceed.AutoSize = true;
            proceed.TabIndex = 3;
            Button cancel = new Button();
            cancel.Text = "Cancel";
            cancel.AutoSize = true;
            cancel.DialogResult = DialogResult.Cancel;
            cancel.TabIndex = 4;
            FlowLayoutPanel buttons = new FlowLayoutPanel();
            buttons.Dock = DockStyle.Bottom;
            buttons.Height = 42;
            buttons.FlowDirection = FlowDirection.RightToLeft;
            buttons.Controls.Add(cancel);
            buttons.Controls.Add(proceed);
            Panel consent = new Panel();
            consent.Dock = DockStyle.Bottom;
            consent.Height = 112;
            consent.Controls.Add(accept);
            consent.Controls.Add(url);
            consent.Controls.Add(buttons);
            form.Controls.Add(license);
            form.Controls.Add(consent);
            form.AcceptButton = proceed;
            form.CancelButton = cancel;
            accept.CheckedChanged += delegate { proceed.Enabled = accept.Checked; };
            proceed.Click += delegate
            {
                if (accept.Checked) form.DialogResult = DialogResult.OK;
            };
            return form.ShowDialog() == DialogResult.OK && accept.Checked;
        }
    }
}
