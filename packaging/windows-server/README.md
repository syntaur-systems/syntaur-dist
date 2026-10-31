# Syntaur Windows server launcher

**Status: development source. The original nine launcher fixtures and five later
setup-activation fixtures passed separately. Not signed, packaged, submitted,
or ready for installation.**
The base launcher revision `80ff783` started the published Gateway 0.7.322 in 7.6 seconds in a
fresh explicit user-owned test home, verified HTTP 200 and the data-directory owner,
and the test stopped its owned server afterward. No real Viewer was run. The
disposable harness profile, whose owner was Administrators, was refused separately;
ordinary Windows profile compatibility remains unproved. An earlier direct-start
observer saw HTTP 200 but did not confirm output draining; that observer remains a
failure. None of these results establishes packaged installation. There is
intentionally no MSIX/MSI manifest or Store identity here.

## Scope

`ServerLauncher.cs` is a small .NET Framework 4.8 `winexe` entry point for the main
Syntaur **server** app. It expects these exact siblings beside the launcher:

- `syntaur.exe` — the released Windows Gateway
- `syntaur-viewer.exe` — the released Viewer, launched with `--local-owner`

A normal launch reuses or starts the exact same-user sibling Gateway, waits for its
owned IPv4 loopback listener, accepts only an HTTP 200 `/health`, rechecks the retained
process and listener, and then opens local owner setup in Viewer. `--background` performs
only the Gateway readiness path. The native setup handoff below is the sole additional
argument form. Other arguments are rejected. Foreground failures show
a short fixed-label message; background failures return 1 without a message box.
Exit 3 means startup failed and bounded cleanup of the newly started Gateway could not
be confirmed.

The launch-wide deadline is 30 seconds, including the complete health response body.
A one-shot abort enforces that deadline. Only a timeout before any health response
is received permits another startup health GET, after aborting the timed-out request
and rechecking the same process and listener. Response/status/body errors remain
fatal. Health has no proxy or redirects and is limited to 64 KiB. TCP owner-PID/listener checks are bounded ownership checks, not
cryptographic peer authentication or an atomic network-identity proof.

Only a newly started Gateway receives `SYNTAUR_LAUNCHER_OWNS_UI=1` in its child
environment. A supporting Gateway uses that preference to skip its automatic
browser opening because this launcher supplies Viewer. It is not an authorization
signal. Existing servers and the Viewer environment are unchanged. Published
0.7.322 ignores the preference: the companion Gateway change must be delivered
before claiming that the combined application opens only one window. The Windows
fixture verifies the child-observed preference; it does not run a real browser.

Existing candidates use one retained limited-query/synchronize handle for image path,
token user, liveness, and readiness. Only a newly created child handle can be terminated.
All other candidate handles are released, and no existing or foreign server is killed.

The launcher does not download files, write configuration or server data, register
startup, copy profiles, change environment variables, poll after launch, or supervise
the server. It validates existing program-directory ancestors and files against reparse
points, untrusted owners, and untrusted mutation ACLs while allowing ordinary read/
execute access. It uses the existing user profile as the child working directory;
Gateway continues to create and protect its normal `%USERPROFILE%\.syntaur` data.

This remains a **per-user, user-session server**, not a Windows Service Control Manager
service. It does not run before login or provide a Session 0/desktop bridge. The Tor
HOST service and Gateway IPC remain Unix-only; their Windows replacement gap is still
open and is not addressed or validated by this launcher. No TLS, remote-access,
battery, native-UI, pairing, or full-lifecycle acceptance is claimed.

## Saved setup activation

The companion Gateway and Viewer source provides a private, navigation-scoped owner
setup bridge. A complete successful setup response arms one native handoff. The page
shows recovery codes before an explicit **Continue**, and repeated clicks do not
submit again. Failure preserves the codes and says activation is unconfirmed.

Viewer launches the sibling with `--after-setup <pid> <raw-creation-filetime>`.
The launcher retains and verifies that exact same-user, same-session Gateway,
opens its protected process-specific event, and requests the ordinary graceful
shutdown. Only confirmed clean exit permits the existing background startup path.
The old process is never killed to force a handoff. The original 120-second handoff
deadline caps shutdown and subsequent startup; startup retains its 30-second limit.
The replacement opens no extra Viewer, and the existing window navigates to sign-in
only after the helper confirms readiness. No setup token enters script or argv.

Five new Windows fixtures separately passed clean handoff, nonzero shutdown,
shutdown timeout, PID/creation mismatch, and a wrong-type event. The actual Rust
event module passed two Windows tests, and the complete Windows Viewer passed
native compilation with no warnings. These results do not establish the whole
interactive Gateway/Viewer transition, packaged installation, or server hosting.

The product flow remains one main installation: **Install Syntaur → set up the
server → add devices from the server.** The companion setup source also includes
server-led device installation guidance and suppresses the automatic browser when
the launcher owns the UI. Those components still need packaged integration and
interactive acceptance. Public Android/iOS app distribution remains unavailable;
a private pairing QR must not be treated as a public app-download link. No
Connect-only product submission should replace this main server flow.

## Framework compilation

Use the existing .NET Framework 4.8 compiler, with no NuGet dependencies:

```powershell
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" `
  /nologo /warnaserror /target:winexe /platform:x64 /optimize+ `
  /out:ServerLauncher.exe `
  /reference:System.dll /reference:System.Windows.Forms.dll `
  ServerLauncher.cs
```

## Verified development fixtures

The Windows .NET Framework compiler completed with warnings treated as errors.
One isolated standard-user run passed nine cases: fresh background startup,
same-process reuse, foreground launch with a fake Viewer, foreign-listener refusal
before starting another Gateway, early child exit, redirect refusal, oversized
health refusal, delayed HTTP readiness after the listener binds, and a trickling
response stopped at the 30-second deadline. The delayed readiness regression
failed before the pre-response timeout correction and passed afterward. The
fake child was confirmed stopped in the refusal cases. The initial failed compile
and runtime results are retained separately; they are not successful runs.

These fixtures use synthetic programs, no product credentials, and no native UI.
They do not establish that the published Gateway starts, that real Viewer setup
works, or that an installer upgrades or uninstalls correctly.

## Remaining coverage and integration

Before adoption, test on disposable standard-user Windows sessions:

- no arguments and `--background`; rejection of every other argument;
- elevated, SYSTEM, and token-owner-mismatch rejection;
- missing executables and reparse points on files, the program directory, and ancestors,
  including an ordinary drive-root ancestor;
- trusted/untrusted owners and mutation ACLs, ordinary Users read/execute access, and
  inherited `CREATOR OWNER` rules;
- fresh Gateway launch, owned `127.0.0.1` and `0.0.0.0` listeners, then Viewer launch;
- exact-path/same-user reuse and PID-reuse fixtures proving one retained candidate handle;
- foreign-path/user, exited/unverifiable processes, and multiple matching servers;
- foreign/conflicting listeners, unexpected local address, and listener disappearance
  between health completion and success;
- child exit, listener timeout, health non-200/timeout, oversized and slow-trickling
  responses, including total-deadline abort immediately after EOF;
- confirmed cleanup of only a new Gateway, plus forced termination/wait failure producing
  exit 3 without hiding the cleanup result;
- Viewer start failure/immediate exit and no Viewer after failed health;
- preservation of `%USERPROFILE%\.syntaur` across launch/relaunch and no post-launch polling.

Trusted signing, packaged installation, upgrade/uninstall, native UI, and physical or
remote device acceptance require separate review and evidence.
