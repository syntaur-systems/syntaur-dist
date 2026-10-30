# Syntaur Connect Windows Store compatibility prototype

This directory builds an **unsubmitted per-user MSI prototype** from the existing
public 0.7.322 Windows client assets. It does not replace the direct-channel
installer or migrate its profiles. Store enrollment and pairing are separate;
Windows credentials already stored by the shared Windows credential store are
not copied or fabricated.

## Prerequisites and trust boundary

- Windows with Microsoft .NET Framework 4.8 installed and WebView2 required
  by the existing Viewer. Neither runtime is
  downloaded by this package.
- The already-downloaded four original release executables, `checksums.txt`,
  and `checksums.txt.cosign.bundle`.
- WiX 5.0.2 (MS-RL), Cosign, and the installed .NET Framework 4.8 C# compiler.
  WiX 5.0.2 community support ended February 5, 2026; this plain-MSI prototype
  has no support or security-maintenance guarantee from that pinned toolchain.
- Production additionally requires SignTool, a timestamp service selected by
  the operator, and a trusted CurrentUser code-signing certificate with a
  private key and Code Signing EKU.

`build-windows-store-msi.ps1` verifies Cosign identity and issuer, authenticated
checksums, and all four existing installer pins before copying anything. It
compiles `StoreClientLauncher.cs`, derives the Snowflake template from literal
fields in `Save-LinkTorConfiguration`, and builds a plain MSI without a bundled
WiX runtime. Production signs and verifies five PEs and the MSI with SHA-256 and
a timestamp. `-DevelopmentUnsigned` produces only a distinctly named and
labelled development lifecycle prototype; it is not Store-ready.

The original release hashes authenticate the original assets, not derivative
bytes after Authenticode signing. The builder prints original and final hashes
for signed files.

## Layout and lifecycle

The real per-user container is `%LOCALAPPDATA%\Syntaur\Store`. Program files are
in its `Syntaur\bin` child. The native launcher starts Viewer with child
`LOCALAPPDATA` and `APPDATA` values rooted in that container. Store profile,
window, and Tor paths are scoped separately from the ordinary direct-channel
profile. The keyring service remains shared and relies on unique handles.
WebView2 continues to use its default data-folder behavior; its actual packaged
path has not been verified. Directly double-clicking the payload Viewer is not
an isolated launch path and is not claimed to be one.

MSI installation performs a read-only native preflight and writes only program
files, the template, EULA, shortcut, and component registry keys. Configuration
is created later by `SyntaurConnect.exe --initialize-only` or an ordinary
launcher invocation. Existing configuration is preserved byte-for-byte.
Uninstall removes only package-owned files and keys, preserving private files
under the Store and direct-channel paths. It does not claim to erase credentials
or browser data.

The obsolete PowerShell initializer and installer library are not packaged.
No execution-policy setting is changed or bypassed.

## Validation still required

Root must compile, inspect, sign, and test in an isolated disposable standard-
user Windows VM. `test-windows-store-msi.ps1` uses real waited `msiexec`
operations and native `--initialize-only`, never launches Viewer, and checks
direct/Store marker preservation across install, optional upgrade, and
uninstall. Its signed-manifest mutation cases demonstrate Cosign rejection,
not checksum-parser coverage; the changed-original-asset case separately tests
hash validation. Production trusted signing, Store submission, and end-to-end
Viewer/WebView2/pairing tests remain unverified and outside this packaging
prototype.

## Prototype validation status

The unsigned prototype built successfully on the isolated Windows VM: original
Cosign verification, the four authenticated release hashes, native C# compilation
with warnings treated as errors, and the WiX MSI build passed. The four original
released executables and the existing installer remain unchanged.

Focused direct-guard and ACL results remain, but full installation, upgrade,
repair and uninstall acceptance is **not complete**. Both the unchanged guard
and the embedded dedicated no-STA/no-GUI entrypoint fail user MSI costing-only
with HRESULT 0x8007045A. SYSTEM costing-only with the same audit candidate
launches the managed program and returns ordinary guard exit 1 because SYSTEM
user != owner is correctly unsupported; this is not install success. Embedded
managed EXEs are therefore not demonstrated inherently incompatible, and no
production alternate entrypoint has been adopted.

The harness authenticates LogonUser type 2 in QGA Session 0, not a Windows
desktop login. Read-only session inventory found services in Session 0 and
console session 1, but no logged-in users. The next discriminator is the
unchanged package in a normal disposable standard-user Windows login; an
interactive session is not claimed to fix the failure. The failing DLL and exact
cause remain unproved. No security settings or global desktop ACLs were modified
and no installer protection was weakened. Negative-install exits are not proof
that the guard rejected fixtures. Trusted signing, Store certification, final
screenshots, customer pairing, and full lifecycle acceptance remain unverified.
