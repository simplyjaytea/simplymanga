#!/usr/bin/env python3
"""Unit tests for verify_ipa.py — synthetic IPA fixtures, stdlib unittest.

Run: python3 -m unittest discover -s tool/ios/tests -v
(or: python3 tool/ios/tests/test_verify_ipa.py)
"""

import os
import plistlib
import struct
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import verify_ipa  # noqa: E402

BUNDLE_ID = "com.simplymanga.app"


def thin_arm64(encrypted=False, code_signature=False):
    """Minimal arm64 MH_EXECUTE Mach-O header (+ optional load commands)."""
    cmds = b""
    ncmds = 0
    if encrypted:
        # encryption_info_command_64: cmd, cmdsize, cryptoff, cryptsize, cryptid, pad
        cmds += struct.pack("<IIIIII", 0x2C, 24, 0, 0, 1, 0)
        ncmds += 1
    if code_signature:
        # linkedit_data_command: cmd, cmdsize, dataoff, datasize
        cmds += struct.pack("<IIII", 0x1D, 16, 0, 0)
        ncmds += 1
    header = struct.pack("<IIIIIIII", 0xFEEDFACF, 0x0100000C, 0, 2,
                         ncmds, len(cmds), 0, 0)
    return header + cmds


def fat_arm64():
    thin = thin_arm64()
    hdr = struct.pack(">II", 0xCAFEBABE, 1)
    arch = struct.pack(">IIIII", 0x0100000C, 0, 40, len(thin), 12)
    return hdr + arch + thin


def base_plist(**over):
    p = {
        "CFBundleDisplayName": "simplyMANGA",
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleShortVersionString": "0.9.97",
        "CFBundleVersion": "130",
        "CFBundleExecutable": "Runner",
        "MinimumOSVersion": "15.0",
        "UIBackgroundModes": ["audio", "fetch"],
        "DTPlatformName": "iphoneos",
        "DTSDKName": "iphoneos18.5",
        "DTXcode": "1640",
    }
    p.update(over)
    return p


def make_ipa(path, plist=None, binary=None, provision=False,
             app_codesign=False, framework_codesign=True,
             outside_entry=False, symlink=False, plugins=False,
             two_apps=False):
    plist = base_plist() if plist is None else plist
    binary = thin_arm64() if binary is None else binary
    app = "Payload/Runner.app"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(app + "/Info.plist", plistlib.dumps(plist))
        z.writestr(app + "/Runner", binary)
        z.writestr(app + "/Assets.car", b"fake-asset-catalog")
        if framework_codesign:
            z.writestr(app + "/Frameworks/Flutter.framework/Flutter",
                       thin_arm64(code_signature=True))
            z.writestr(app + "/Frameworks/Flutter.framework/_CodeSignature/CodeResources",
                       b"<plist/>")
        if provision:
            z.writestr(app + "/embedded.mobileprovision", b"fake-profile")
        if app_codesign:
            z.writestr(app + "/_CodeSignature/CodeResources", b"<plist/>")
        if plugins:
            z.writestr(app + "/PlugIns/Widget.appex/Info.plist",
                       plistlib.dumps(base_plist()))
        if outside_entry:
            z.writestr("Symbols/whatever.txt", b"sym")
        if symlink:
            zi = zipfile.ZipInfo(app + "/link")
            zi.external_attr = (0o120777 << 16)  # symlink mode bits
            z.writestr(zi, "Runner")
        if two_apps:
            z.writestr("Payload/Other.app/Info.plist",
                       plistlib.dumps(base_plist()))
    return path


class VerifyIpaTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = os.path.join(self.tmp.name, "test.ipa")

    def test_valid_unsigned_passes(self):
        make_ipa(self.path)
        r = verify_ipa.verify_ipa(self.path, expect_bundle_id=BUNDLE_ID)
        self.assertTrue(r["ok"], r["fatal"])
        self.assertTrue(r["info"]["unsigned"])
        self.assertEqual(r["info"]["CFBundleIdentifier"], BUNDLE_ID)
        self.assertEqual(r["info"]["CFBundleShortVersionString"], "0.9.97")
        self.assertIn("arm64", r["info"]["archs"])
        self.assertFalse(r["info"]["fairplay_encrypted"])
        self.assertEqual(r["info"]["frameworks_with_codesign"],
                         ["Flutter.framework"])
        self.assertEqual(len(r["info"]["sha256"]), 64)

    def test_framework_codesign_tolerated(self):
        make_ipa(self.path, framework_codesign=True)
        r = verify_ipa.verify_ipa(self.path)
        self.assertTrue(r["ok"], r["fatal"])

    def test_provisioned_ipa_fails(self):
        make_ipa(self.path, provision=True)
        r = verify_ipa.verify_ipa(self.path)
        self.assertFalse(r["ok"])
        self.assertTrue(any("mobileprovision" in f for f in r["fatal"]))

    def test_app_codesign_fails(self):
        make_ipa(self.path, app_codesign=True)
        r = verify_ipa.verify_ipa(self.path)
        self.assertFalse(r["ok"])
        self.assertTrue(any("_CodeSignature" in f for f in r["fatal"]))

    def test_fairplay_encrypted_fails(self):
        make_ipa(self.path, binary=thin_arm64(encrypted=True))
        r = verify_ipa.verify_ipa(self.path)
        self.assertFalse(r["ok"])
        self.assertTrue(any("FairPlay" in f for f in r["fatal"]))

    def test_wrong_bundle_id_fails(self):
        make_ipa(self.path)
        r = verify_ipa.verify_ipa(self.path,
                                  expect_bundle_id="com.example.other")
        self.assertFalse(r["ok"])
        self.assertTrue(any("bundle id" in f for f in r["fatal"]))

    def test_missing_payload_fails(self):
        with zipfile.ZipFile(self.path, "w") as z:
            z.writestr("README.txt", b"not an ipa")
        r = verify_ipa.verify_ipa(self.path)
        self.assertFalse(r["ok"])

    def test_two_apps_fails(self):
        make_ipa(self.path, two_apps=True)
        r = verify_ipa.verify_ipa(self.path)
        self.assertFalse(r["ok"])
        self.assertTrue(any("exactly one" in f for f in r["fatal"]))

    def test_push_background_mode_warns(self):
        make_ipa(self.path, plist=base_plist(
            UIBackgroundModes=["audio", "fetch", "remote-notification"]))
        r = verify_ipa.verify_ipa(self.path)
        self.assertTrue(r["ok"], r["fatal"])  # warning, not fatal
        self.assertTrue(any("FREE Apple ID" in w for w in r["warnings"]))

    def test_fat_binary_passes(self):
        make_ipa(self.path, binary=fat_arm64())
        r = verify_ipa.verify_ipa(self.path)
        self.assertTrue(r["ok"], r["fatal"])
        self.assertIn("arm64", r["info"]["archs"])

    def test_not_macho_fails(self):
        make_ipa(self.path, binary=b"this is not a mach-o at all")
        r = verify_ipa.verify_ipa(self.path)
        self.assertFalse(r["ok"])
        self.assertTrue(any("Mach-O" in f for f in r["fatal"]))

    def test_corrupt_zip_fails(self):
        make_ipa(self.path)
        size = os.path.getsize(self.path)
        with open(self.path, "r+b") as f:
            f.truncate(size // 2)  # central directory gone -> BadZipFile
        r = verify_ipa.verify_ipa(self.path)
        self.assertFalse(r["ok"])

    def test_symlink_warns(self):
        make_ipa(self.path, symlink=True)
        r = verify_ipa.verify_ipa(self.path)
        self.assertTrue(r["ok"], r["fatal"])
        self.assertTrue(any("symlink" in w for w in r["warnings"]))

    def test_outside_payload_warns(self):
        make_ipa(self.path, outside_entry=True)
        r = verify_ipa.verify_ipa(self.path)
        self.assertTrue(r["ok"], r["fatal"])
        self.assertTrue(any("outside Payload" in w for w in r["warnings"]))

    def test_extensions_warn(self):
        make_ipa(self.path, plugins=True)
        r = verify_ipa.verify_ipa(self.path)
        self.assertTrue(r["ok"], r["fatal"])
        self.assertTrue(any("App ID slot" in w for w in r["warnings"]))

    def test_missing_executable_fails(self):
        make_ipa(self.path, plist=base_plist(CFBundleExecutable="Ghost"))
        r = verify_ipa.verify_ipa(self.path)
        self.assertFalse(r["ok"])

    def test_nonexistent_file(self):
        r = verify_ipa.verify_ipa(os.path.join(self.tmp.name, "nope.ipa"))
        self.assertFalse(r["ok"])


class MachOParserTests(unittest.TestCase):
    def test_thin_arm64(self):
        m = verify_ipa.parse_macho(thin_arm64())
        self.assertEqual(m["archs"], ["arm64"])
        self.assertTrue(m["thin"])
        self.assertFalse(m["encrypted"])

    def test_encrypted_flag(self):
        m = verify_ipa.parse_macho(thin_arm64(encrypted=True))
        self.assertTrue(m["encrypted"])

    def test_code_signature_flag(self):
        m = verify_ipa.parse_macho(thin_arm64(code_signature=True))
        self.assertTrue(m["has_code_signature"])

    def test_fat_dedup(self):
        m = verify_ipa.parse_macho(fat_arm64())
        self.assertEqual(m["archs"], ["arm64"])
        self.assertFalse(m["thin"])

    def test_garbage_raises(self):
        with self.assertRaises(ValueError):
            verify_ipa.parse_macho(b"PK\x03\x04garbage")


if __name__ == "__main__":
    unittest.main(verbosity=2)
