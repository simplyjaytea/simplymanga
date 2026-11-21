#!/usr/bin/env python3
"""verify_ipa.py — sideload-readiness verifier for simplyMANGA CI IPAs.

Validates an UNSIGNED .ipa produced by .github/workflows/ios.yml (macOS,
`flutter build ios --release --no-codesign`) before it is handed to a
free-Apple-ID re-signing tool (Sideloadly / SideStore / AltStore).

Stdlib only (zipfile, plistlib, struct, hashlib) — runs on the Linux VPS,
no macOS toolchain required. Python 3.9+.

Checks (fatal unless noted):
  * zip integrity; exactly one Payload/<Name>.app; entries outside Payload (warn)
  * Info.plist parses; bundle id / version / MinimumOSVersion reported
  * main executable exists and is a Mach-O (arm64 / fat); archs reported
  * FairPlay encryption (LC_ENCRYPTION_INFO[_64] cryptid != 0) -> fatal:
    App Store IPAs cannot be re-signed
  * app-level embedded.mobileprovision or _CodeSignature/CodeResources ->
    fatal for this pipeline (it validates unsigned CI builds; re-signers
    expect unsigned input). Framework-level _CodeSignature is NORMAL
    (Flutter/OpenJDK engines ship pre-signed) and is tolerated.
  * UIBackgroundModes remote-notification/voip -> warning: push entitlements
    are not available to free Apple ID provisioning
  * zip symlinks -> warning (some re-signers mishandle them)
  * PlugIns/ app extensions -> info (each consumes a free-account App ID slot)

Exit codes: 0 = sideload-ready (warnings allowed), 1 = fatal problem,
2 = usage / IO error.

Usage:
  python3 verify_ipa.py simplyMANGA-unsigned.ipa
  python3 verify_ipa.py app.ipa --expect-bundle-id com.simplymanga.app --json
"""

import argparse
import hashlib
import json
import plistlib
import struct
import sys
import zipfile

# --- Mach-O constants -------------------------------------------------------

MH_MAGIC = 0xFEEDFACE        # 32-bit little-endian
MH_CIGAM = 0xCEFAEDFE        # 32-bit big-endian (byte-swapped)
MH_MAGIC_64 = 0xFEEDFACF     # 64-bit little-endian
MH_CIGAM_64 = 0xCFFAEDFE     # 64-bit big-endian
FAT_MAGIC = 0xCAFEBABE       # universal binary (big-endian on disk)
FAT_CIGAM = 0xBEBAFECA

LC_ENCRYPTION_INFO = 0x21
LC_ENCRYPTION_INFO_64 = 0x2C
LC_CODE_SIGNATURE = 0x1D

CPU_TYPE_ARM = 12
CPU_TYPE_ARM64 = 0x0100000C
CPU_TYPE_X86 = 7
CPU_TYPE_X86_64 = 0x01000007

CPU_NAMES = {
    CPU_TYPE_ARM: "armv7/armv7s (32-bit iOS)",
    CPU_TYPE_ARM64: "arm64",
    CPU_TYPE_X86: "x86 (simulator)",
    CPU_TYPE_X86_64: "x86_64 (simulator)",
}

# Background modes that require entitlements a free Apple ID cannot provision.
PAID_ONLY_BACKGROUND_MODES = {"remote-notification", "voip"}


def _cpu_name(cputype):
    return CPU_NAMES.get(cputype, "unknown cputype 0x%X" % cputype)


def parse_macho(data):
    """Return dict(archs=[...], encrypted=bool, has_code_signature=bool,
    thin=bool) for a Mach-O or fat binary. Raises ValueError on non-Mach-O.

    Defensive: truncated load commands stop parsing rather than crash.
    """
    if len(data) < 4:
        raise ValueError("file too small to be a Mach-O")
    # Thin Mach-O magics are defined as host-order constants: read the first
    # word little-endian and compare against MH_* directly. Fat headers are
    # big-endian on disk, so detect those with a big-endian read.
    magic_le = struct.unpack("<I", data[:4])[0]
    magic_be = struct.unpack(">I", data[:4])[0]
    archs = []
    encrypted = False
    has_sig = False

    def scan_thin(buf, endian, is64):
        nonlocal encrypted, has_sig
        fmt = endian + "I"
        if len(buf) < (32 if is64 else 28):
            raise ValueError("truncated Mach-O header")
        cputype = struct.unpack_from(fmt, buf, 4)[0]
        archs.append(_cpu_name(cputype))
        ncmds = struct.unpack_from(fmt, buf, 16)[0]
        off = 32 if is64 else 28
        for _ in range(ncmds):
            if off + 8 > len(buf):
                break
            cmd, cmdsize = struct.unpack_from(endian + "II", buf, off)
            if cmdsize < 8:
                break
            if cmd in (LC_ENCRYPTION_INFO, LC_ENCRYPTION_INFO_64):
                if off + 20 <= len(buf):
                    cryptid = struct.unpack_from(endian + "I", buf, off + 16)[0]
                    if cryptid != 0:
                        encrypted = True
            elif cmd == LC_CODE_SIGNATURE:
                has_sig = True
            off += cmdsize

    if magic_be in (FAT_MAGIC, FAT_CIGAM):
        endian = ">" if magic_be == FAT_MAGIC else "<"
        if len(data) < 8:
            raise ValueError("truncated fat header")
        nfat = struct.unpack_from(endian + "I", data, 4)[0]
        if nfat > 64:
            raise ValueError("implausible fat arch count %d" % nfat)
        for i in range(nfat):
            base = 8 + i * 20
            if base + 20 > len(data):
                break
            cputype, _sub, offset, size, _align = struct.unpack_from(
                endian + "IIIII", data, base)
            archs.append(_cpu_name(cputype))
            slice_data = data[offset:offset + size]
            if len(slice_data) >= 4:
                smagic = struct.unpack("<I", slice_data[:4])[0]
                try:
                    if smagic == MH_MAGIC_64:
                        scan_thin(slice_data, "<", True)
                    elif smagic == MH_CIGAM_64:
                        scan_thin(slice_data, ">", True)
                    elif smagic == MH_MAGIC:
                        scan_thin(slice_data, "<", False)
                    elif smagic == MH_CIGAM:
                        scan_thin(slice_data, ">", False)
                except ValueError:
                    pass
        # dedupe while preserving order (fat header + slice scan double-count)
        seen = set()
        archs = [a for a in archs if not (a in seen or seen.add(a))]
        return {"archs": archs, "encrypted": encrypted,
                "has_code_signature": has_sig, "thin": False}

    if magic_le == MH_MAGIC_64:
        scan_thin(data, "<", True)
    elif magic_le == MH_CIGAM_64:
        scan_thin(data, ">", True)
    elif magic_le == MH_MAGIC:
        scan_thin(data, "<", False)
    elif magic_le == MH_CIGAM:
        scan_thin(data, ">", False)
    else:
        raise ValueError("not a Mach-O (magic 0x%08X)" % magic_le)
    return {"archs": archs, "encrypted": encrypted,
            "has_code_signature": has_sig, "thin": True}


def sha256_file(path, chunk=1 << 20):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(chunk)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def verify_ipa(path, expect_bundle_id=None):
    """Return a report dict: {ok, fatal: [..], warnings: [..], info: {...}}."""
    fatal, warnings, info = [], [], {}
    info["file"] = str(path)
    try:
        info["sha256"] = sha256_file(path)
    except OSError as e:
        return {"ok": False, "fatal": ["cannot read file: %s" % e],
                "warnings": [], "info": info}
    try:
        z = zipfile.ZipFile(path)
    except (zipfile.BadZipFile, OSError) as e:
        return {"ok": False, "fatal": ["not a readable zip: %s" % e],
                "warnings": [], "info": info}
    with z:
        bad = z.testzip()
        if bad is not None:
            fatal.append("corrupt zip entry: %s" % bad)
        names = z.namelist()
        info["entries"] = len(names)
        info["ipa_bytes"] = sum(i.file_size for i in z.infolist())

        outside = sorted({n.split("/")[0] for n in names
                          if n.split("/")[0] != "Payload"})
        if outside:
            warnings.append("entries outside Payload/: %s" % ", ".join(outside))

        symlinks = [i.filename for i in z.infolist()
                    if (i.external_attr >> 16) & 0o170000 == 0o120000]
        if symlinks:
            warnings.append("%d zip symlink(s), e.g. %s — some re-signers "
                            "mishandle these" % (len(symlinks), symlinks[0]))

        apps = sorted({n.split("/")[1] for n in names
                       if n.startswith("Payload/") and len(n.split("/")) > 2
                       and n.split("/")[1].endswith(".app")})
        if len(apps) != 1:
            fatal.append("expected exactly one Payload/*.app, found %d: %s"
                         % (len(apps), apps))
            return {"ok": False, "fatal": fatal, "warnings": warnings,
                    "info": info}
        app = "Payload/" + apps[0]
        info["app"] = apps[0]

        # --- Info.plist ---
        try:
            plist = plistlib.loads(z.read(app + "/Info.plist"))
        except KeyError:
            fatal.append("missing %s/Info.plist" % app)
            plist = {}
        except Exception as e:
            fatal.append("Info.plist unparseable: %s" % e)
            plist = {}
        for key in ("CFBundleDisplayName", "CFBundleIdentifier",
                    "CFBundleShortVersionString", "CFBundleVersion",
                    "MinimumOSVersion", "DTPlatformName", "DTSDKName",
                    "DTXcode", "CFBundleExecutable"):
            if key in plist:
                info[key] = plist[key]
        if "MinimumOSVersion" not in plist:
            warnings.append("Info.plist has no MinimumOSVersion")
        if expect_bundle_id and plist.get("CFBundleIdentifier") != expect_bundle_id:
            fatal.append("bundle id %r != expected %r"
                         % (plist.get("CFBundleIdentifier"), expect_bundle_id))
        modes = plist.get("UIBackgroundModes") or []
        info["UIBackgroundModes"] = modes
        paid_modes = sorted(set(modes) & PAID_ONLY_BACKGROUND_MODES)
        if paid_modes:
            warnings.append("UIBackgroundModes %s need push/VoIP entitlements "
                            "a FREE Apple ID cannot provision" % paid_modes)
        schemes = []
        for t in plist.get("CFBundleURLTypes") or []:
            schemes.extend(t.get("CFBundleURLSchemes") or [])
        if schemes:
            info["URLSchemes"] = schemes

        # --- signing state (app level) ---
        prov = [n for n in names if n.endswith(".mobileprovision")]
        app_codesign = app + "/_CodeSignature/CodeResources"
        info["unsigned"] = not prov and app_codesign not in names
        if prov:
            fatal.append("embedded.mobileprovision present (%s) — this is a "
                         "SIGNED ipa; the CI sideload pipeline expects "
                         "unsigned input" % prov[0])
        if app_codesign in names:
            fatal.append("app-level _CodeSignature/CodeResources present — "
                         "app bundle is already signed; re-signers expect "
                         "unsigned CI input")
        fw_sig = set()
        for n in names:
            if n.startswith(app + "/Frameworks/") and "/_CodeSignature/" in n:
                parts = n[len(app) + 1:].split("/")
                if len(parts) > 2:
                    fw_sig.add(parts[1])
        info["frameworks_with_codesign"] = sorted(fw_sig)  # normal for engines

        # --- frameworks / extensions ---
        frameworks = sorted({n[len(app) + 1:].split("/")[1] for n in names
                             if n.startswith(app + "/Frameworks/")
                             and len(n[len(app) + 1:].split("/")) > 1
                             and n[len(app) + 1:].split("/")[1].endswith((".framework", ".dylib"))})
        info["frameworks"] = frameworks
        plugins = sorted({n[len(app) + 1:].split("/")[1] for n in names
                          if n.startswith(app + "/PlugIns/")
                          and len(n[len(app) + 1:].split("/")) > 1})
        if plugins:
            info["extensions"] = plugins
            warnings.append("app extensions present (%s) — each consumes a "
                            "free-account App ID slot (10 per 7 days)"
                            % ", ".join(plugins))

        # --- main binary ---
        exe = plist.get("CFBundleExecutable")
        if exe:
            binpath = app + "/" + exe
            try:
                data = z.read(binpath)
            except KeyError:
                fatal.append("CFBundleExecutable %r not found in bundle" % exe)
                data = None
            if data is not None:
                info["executable_bytes"] = len(data)
                try:
                    macho = parse_macho(data)
                    info["archs"] = macho["archs"]
                    info["fairplay_encrypted"] = macho["encrypted"]
                    info["executable_has_code_signature"] = macho["has_code_signature"]
                    if macho["encrypted"]:
                        fatal.append("FairPlay-encrypted executable (cryptid!=0) "
                                     "— App Store IPAs cannot be re-signed")
                    if not any("arm64" in a for a in macho["archs"]):
                        warnings.append("no arm64 slice in executable: %s"
                                        % macho["archs"])
                except ValueError as e:
                    fatal.append("executable is not a valid Mach-O: %s" % e)
        elif not fatal:
            fatal.append("Info.plist has no CFBundleExecutable")

    return {"ok": not fatal, "fatal": fatal, "warnings": warnings, "info": info}


def print_report(report):
    info = report["info"]
    print("IPA verification: %s" % info.get("file"))
    print("  sha256:      %s" % info.get("sha256"))
    print("  app:         %s" % info.get("app"))
    print("  bundle id:   %s" % info.get("CFBundleIdentifier"))
    print("  version:     %s (%s)" % (info.get("CFBundleShortVersionString"),
                                       info.get("CFBundleVersion")))
    print("  min iOS:     %s" % info.get("MinimumOSVersion"))
    print("  sdk/xcode:   %s / %s" % (info.get("DTSDKName"), info.get("DTXcode")))
    print("  archs:       %s" % ", ".join(info.get("archs", [])))
    print("  unsigned:    %s" % info.get("unsigned"))
    print("  bg modes:    %s" % info.get("UIBackgroundModes"))
    print("  frameworks:  %d (%d pre-signed, normal)"
          % (len(info.get("frameworks", [])),
             len(info.get("frameworks_with_codesign", []))))
    print("  entries:     %s, uncompressed %.1f MB"
          % (info.get("entries"), (info.get("ipa_bytes") or 0) / 1e6))
    for w in report["warnings"]:
        print("  WARN: %s" % w)
    for f in report["fatal"]:
        print("  FATAL: %s" % f)
    print("  RESULT: %s" % ("SIDELOAD-READY (unsigned)" if report["ok"] else "FAILED"))


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Sideload-readiness verifier for unsigned simplyMANGA CI IPAs.")
    ap.add_argument("ipa")
    ap.add_argument("--expect-bundle-id", default=None,
                    help="fail if CFBundleIdentifier differs")
    ap.add_argument("--json", action="store_true", help="machine-readable report")
    args = ap.parse_args(argv)
    try:
        report = verify_ipa(args.ipa, expect_bundle_id=args.expect_bundle_id)
    except OSError as e:
        print("error: %s" % e, file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print_report(report)
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
