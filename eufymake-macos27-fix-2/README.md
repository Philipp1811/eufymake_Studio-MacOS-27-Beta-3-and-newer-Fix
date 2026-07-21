# eufyMake Studio macOS 27 Fix

One-click workaround for the **eufyMake Studio login/startup crash on macOS 27 beta** on Apple Silicon.

The crash is caused by a libpag/VideoToolbox code path that can call `CFRelease(NULL)` after `CVPixelBufferCreateResolvedAttributesDictionary()` returns no dictionary on macOS 27. The upstream libpag issue describing the same failure is:

https://github.com/Tencent/libpag/issues/3591

## What this fix does

The launcher:

1. Finds the installed `eufyMake Studio.app`.
2. Verifies that the Mac runs macOS 27 on Apple Silicon.
3. Creates a **private copy** of eufyMake Studio. The original app in `/Applications` is never modified.
4. Extracts the ARM64 slice of the main executable.
5. Searches for the exact libpag ARM64 instruction sequence surrounding the unsafe `CFRelease` call.
6. Replaces only that one call with an ARM64 `NOP`.
7. Rebuilds the Universal Binary while leaving the x86_64 slice untouched.
8. Ad-hoc signs the patched executable outside the app bundle and copies it back.
9. Launches the patched executable explicitly as native `arm64`.

The script does **not** use a hard-coded file offset. If the expected machine-code sequence is missing or appears more than once, the script aborts without patching anything.

## One-click usage

1. Download or clone this repository.
2. Double-click:

   `EufyMake-macOS27-Fix.command`

3. The first run creates the patched private copy and launches eufyMake Studio automatically.
4. Later runs reuse the cached patched copy as long as the installed eufyMake executable has not changed.
5. After an eufyMake update, run the `.command` file again. It detects the changed binary and rebuilds the patch automatically, provided the safety pattern still matches.

### Gatekeeper on first launch

Because this GitHub script is not signed with an Apple Developer ID, macOS may block the `.command` file after downloading it and show a message that Apple could not verify that the file is free of malware.

If double-clicking or **right-click → Open** is still blocked:

1. Try to open `EufyMake-macOS27-Fix.command` once so macOS records the blocked launch.
2. Open **System Settings → Privacy & Security**. On German macOS this is **Systemeinstellungen → Datenschutz & Sicherheit**.
3. Scroll down to the **Security** section.
4. Find the message that `EufyMake-macOS27-Fix.command` was blocked and click **Open Anyway** / **Dennoch öffnen**.
5. Confirm the final macOS warning with **Open**.

This approval is only needed because the downloaded script is not Developer-ID signed. The fix does not disable Gatekeeper globally. Once the script is allowed to start, it removes the quarantine attribute from its local repository folder where permitted.

## Requirements

- macOS 27
- Apple Silicon (`arm64`)
- eufyMake Studio installed in `/Applications` or `~/Applications`
- A Universal/ARM64 build of eufyMake Studio

No `sudo` access is required. The fix installs its private copy under:

`~/Library/Application Support/EufyMake-macOS27-Fix/`

## Important limitations

This is an **unofficial binary workaround**, not an official eufyMake or Tencent/libpag update.

The patch deliberately skips one `CFRelease` call. This avoids the confirmed `CFRelease(NULL)` crash, but when the resolved dictionary is non-NULL it also means that particular object is not released at that point. Therefore the workaround can cause a small memory leak when the decoder is initialized.

The launcher always forces the patched application to run natively as ARM64. The x86_64/Rosetta slice is preserved but is not patched.

Do not redistribute eufyMake Studio itself. This repository contains only the patching/launch scripts and does not contain any eufyMake binaries.

## Remove the workaround

Double-click:

`Remove-Fix.command`

This deletes only the private patched copy. The original eufyMake Studio installation remains unchanged.

## Technical detail

The faulty ARM64 sequence is conceptually:

```asm
mov x22, x0
ldr x0, [sp, #0x20]
bl  _CFRelease          ; crashes when x0 == NULL
mov x0, x27
bl  _CFRelease
...
```

The workaround changes only the first release call:

```asm
mov x22, x0
ldr x0, [sp, #0x20]
nop                     ; temporary macOS 27 workaround
mov x0, x27
bl  _CFRelease
...
```

The scanner also verifies the subsequent release chain and that all surrounding `BL` instructions target the same function before applying the patch.

## Tested

Confirmed working on the environment where this workaround was developed:

- Apple Silicon Mac
- macOS 27 beta
- eufyMake Studio Universal Binary (`arm64` + `x86_64`)
- Crash triggered when opening the login flow

Other eufyMake versions are accepted only when the safety scanner finds exactly one matching instruction sequence.

## Disclaimer

Use at your own risk. Keep eufyMake Studio updated and remove this workaround once eufyMake or libpag ships an official fix.
