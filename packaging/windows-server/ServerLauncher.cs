using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
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
        int activationPid;
        ulong activationCreation;
        bool afterSetup = TryParseActivationArguments(args, out activationPid, out activationCreation);
        if (args.Length != 0 && !background && !afterSetup)
        {
            ShowFailure("Syntaur received an unsupported launch request.", false);
            return 2;
        }

        GatewayProcess startedGateway = null;
        try
        {
            if (afterSetup)
                RunAfterSetup(activationPid, activationCreation, ref startedGateway);
            else
                Run(background, ref startedGateway);
            return 0;
        }
        catch (LaunchFailure error)
        {
            if (!StopNewGateway(startedGateway))
            {
                ShowFailure("Syntaur startup failed, and server cleanup could not be confirmed.", background || afterSetup);
                return CleanupExitCode;
            }
            ShowFailure(error.Message, background || afterSetup);
            return 1;
        }
        catch
        {
            if (!StopNewGateway(startedGateway))
            {
                ShowFailure("Syntaur startup failed, and server cleanup could not be confirmed.", background || afterSetup);
                return CleanupExitCode;
            }
            ShowFailure("Syntaur could not start the local server.", background || afterSetup);
            return 1;
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

        GatewayProcess gateway = FindOwnedGateway(gatewayPath);
        StartupDeadline clock = new StartupDeadline(activation);
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
        }
        finally
        {
            if (!Object.ReferenceEquals(gateway, startedGateway) && gateway != null)
                gateway.Dispose();
        }
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

    private static GatewayProcess FindOwnedGateway(string gatewayPath)
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
                        catch (InvalidOperationException) { continue; }
                        string processPath;
                        if (!TryQueryImagePath(candidate.Handle, out processPath))
                            continue;
                        if (!String.Equals(processPath, gatewayPath, StringComparison.OrdinalIgnoreCase))
                            continue;
                        if (!ProcessHasCurrentUserSid(candidate.Handle))
                            throw new LaunchFailure("Syntaur could not verify the running server's owner.");
                        if (candidate.State() != ProcessState.Alive)
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
