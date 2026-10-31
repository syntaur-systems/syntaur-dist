# Syntaur Windows server launcher

**Status: the unsigned development SERVER MSI passed silent install, update,
missing-file repair and uninstall in disposable Windows accounts. Complete
interactive setup, trusted signing and Store submission remain unverified;
this is not ready for public installation.** The original nine launcher fixtures,
five setup-activation fixtures and five maintenance fixtures passed separately.
The base launcher revision `80ff783` started the published Gateway 0.7.322 in 7.6 seconds in a
fresh explicit user-owned test home, verified HTTP 200 and the data-directory owner,
and the test stopped its owned server afterward. No real Viewer was run. The
disposable harness profile, whose owner was Administrators, was refused separately.
The companion `85bc91da` correction then passed two native profile-root tests and
an actual installed background Gateway start as a standard user in its ordinary
OS-created profile, followed by an independent owned HTTP 200 check. The OS
profile stayed Administrator-owned; the new private child belonged to that user.
This did not run Viewer or owner setup. An earlier direct-start
observer saw HTTP 200 but did not confirm output draining; that observer remains a
failure. Store identity, certification and full interactive setup are unproved.

## Server MSI development package

`Product.wxs` packages one main Syntaur server shortcut, the existing Gateway and
Viewer, and the supporting Link executables. Standard Windows Installer service
actions install the isolated `NT SERVICE\SyntaurLinkTor` HOST. The Gateway remains
the selected owner's user-session process. The development MSI compiled with WiX
warnings treated as errors. Its actual File table contains eight runtime and
support files, with no live configuration, keys or user profiles.

`scripts/build-windows-server-msi.ps1` requires an exact captured ten-file input
set and the explicit `-DevelopmentUnsigned` switch. Public mode refuses before
writing anything. Cached WiX 5.0.2 is used for development only; supported public
tooling/licensing, existing signed-release asset verification, Authenticode,
interactive EULA/setup acceptance, sign-in startup integration and public release
integration remain required. Five native setup dialogs are authored and compile,
but their complete visible flow has not been accepted. The operative EULA is unchanged. No public package or certificate
purchase is implied by this prototype.

The installer-only `InstallerProvisioner.cs` creates protected roles through
retained Windows handles. Private HOST state lives under
`%ProgramData%\SyntaurLinkTor`; the separate Gateway publication uses
`%ProgramData%\Syntaur\LinkTor\shared\<owner SID>`. A valid existing configuration
selects its original owner during maintenance. Existing keys and state are never
reset, incompatible directories are refused, and repair does not rewrite admitted
file security. Live `host.json` is generated atomically outside MSI's replaceable
File resources. Its ordinary-transport default does not enable remote consent.

The standard MSI rollback file is SYSTEM/administrator protected. It records only
new object identities and hashes, never private payloads. Replacement is atomic;
rollback removes only matching new files or empty directories. Nonempty identity
state is retained, with failure reported. Nine distinct filesystem cases resolved
across an initial three passes and six continuation passes; this was not a fresh
nine-case run. Original failures remain retained. These cases do not prove an MSI
installation or upgrade by themselves.

Actual MSI checks then installed all eight payload files and the isolated HOST
service. A later update retained the original selected Gateway owner when run
by a different administrator. After one program file was deliberately removed,
the corrected ordinary cached `/fa` repair restored it and verified all eight
payload hashes. Normal uninstall removed the product, files, service, shortcut,
registration and program directory. At each final retention observation, all
21 recorded private files and 25 ACL records remained unchanged. These are
silent development checks, not interactive consent, full setup, remote hosting
or every future upgrade path.

Earlier maintenance failures remain retained. One actual failure reported
Windows `ERROR_INVALID_NAME` while replacing the rollback record. The native
rename buffer left four trailing bytes uninitialized. A deterministic prefilled
buffer check failed before full initialization and passed afterward; flags,
filename bytes, byte count and sharing remained unchanged. Nine affected
filesystem cases passed on the corrected source before the successful ordinary
update and missing-file repair. The earlier isolated and heap-priming probes did
not reproduce the MSI failure; this is not a cause claim for every prior error.

Failure reporting uses the existing MSI EXE exit record. Fixed source labels and
the last assigned step occupy codes 1001–2499. A source-owned rename failure with
a Windows error number in 0–65535 uses `(stepIndex + 1) * 65536 + nativeCode`;
out-of-range values fall back to the generic step. No private exception text,
paths, configuration or identities enter that encoding. Cleanup failures may
inherit the last step, and failures outside the mapped catch can still escape it.

The MSI's immediate impersonated `--installer-stop` entry resolves the fixed
installed program location independently of MSI's temporary extraction path.
It permits missing-file repair only after process discovery, refuses inaccessible
or unknown identities, and uses the existing protected event to stop the exact
same-user/session Gateway. It never kills or replaces that server. Another user
or session must close its server normally. This preflight precedes transactional
installation: a later cancellation can leave Gateway stopped, and rollback does
not restore its running state. Five new synthetic Windows cases passed missing-file
repair, clean stop, nonzero exit, incorrect event access and inaccessible process
identity. No actual Gateway, Viewer, service or network was used by them.

The first native Viewer development binary matching companion source `abe44b37`
also built with no warnings. Its captured 2,232 source inputs remained unchanged;
that is not an all-files test or interactive UI acceptance.

## Scope

`ServerLauncher.cs` is a small .NET Framework 4.8 `winexe` entry point for the main
Syntaur **server** app. It expects these exact siblings beside the launcher:

- `syntaur.exe` — the released Windows Gateway
- `syntaur-viewer.exe` — the released Viewer, launched with `--local-owner`

A normal launch reuses or starts the exact same-user sibling Gateway, waits for its
owned IPv4 loopback listener, accepts only an HTTP 200 `/health`, rechecks the retained
process and listener, and then opens local owner setup in Viewer. `--background` performs
only the Gateway readiness path. The native setup handoff below is the sole additional
user launch argument form. The installer-only maintenance form is described above.
Other arguments are rejected. Foreground failures show
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
0.7.322 ignores the preference; the development package uses the companion source
that supports it. An actual single-window Gateway/Viewer transition remains
unverified. The Windows
fixture verifies the child-observed preference; it does not run a real browser.

Existing candidates use one retained limited-query/synchronize handle for image path,
token user, liveness, and readiness. Only a newly created child handle can be terminated.
All other candidate handles are released, and no existing or foreign server is killed.

The normal launcher does not download files, write configuration or server data, register
startup, copy profiles, change environment variables, poll after launch, or supervise
the server. It validates existing program-directory ancestors and files against reparse
points, untrusted owners, and untrusted mutation ACLs while allowing ordinary read/
execute access. It uses the existing user profile as the child working directory;
Gateway continues to create and protect its normal `%USERPROFILE%\.syntaur` data.

This remains a **per-user, user-session server**, not a Windows Service Control Manager
service. It does not run before login or provide a Session 0/desktop bridge. The Tor
HOST has a separate isolated virtual-account service. Its Windows port is saved in
companion source `abe44b37`; actual native builds and a consent-disabled authenticated
control exchange passed. The development MSI also installed and ran the service
under its original virtual-account SID. That is not a public Windows package or a remote-access test.
No TLS, battery, native-UI, pairing, or full-lifecycle acceptance is claimed.

New Gateway children receive the existing three HOST bindings. The launcher obtains
ProgramData from the Windows known folder and derives the local pipe and Gateway pin
path from the current user's SID. It translates exactly `NT SERVICE\SyntaurLinkTor`
for the service SID, and overrides inherited values only in that child. Translation
does not establish service registration or readiness. The existing Gateway publisher
performs the actual shared-directory ownership, ACL and reparse checks.

The installer must provision the same selected unelevated Gateway owner, using:

- pipe `\\.\pipe\Syntaur.Link.host.<Gateway SID>`;
- shared pin `%ProgramData%\Syntaur\LinkTor\shared\<Gateway SID>\gateway-pin.json`;
- service name/account `SyntaurLinkTor` / `NT SERVICE\SyntaurLinkTor`.

These bindings also apply after the existing saved-setup restart. Reusing an existing
Gateway does not change its environment; it must already have been started with the
installed bindings. This layout does not automatically grant every Windows login
ownership of the same server. The launcher neither starts the service nor adds polling.

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
the launcher owns the UI. Those components still need actual packaged lifecycle and
interactive acceptance. Development Android builds accept the existing pairing
QR through their camera intake; the retained silent fixture used a fake camera,
not a physical camera or live enrollment. Public Android/iOS app distribution remains unavailable;
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

- the four supported forms (normal launch, `--background`, `--after-setup`,
  `--installer-stop`) and rejection of malformed or unknown forms;
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

The silent development install, update, missing-file repair and uninstall passed
as described above. Trusted signing, complete interactive installation/setup,
broader upgrade paths, native UI, and physical or remote device acceptance still
require separate evidence.
