#!/usr/bin/env python3
"""run_tests.py - run the validation suites and summarise them.

Mirrors the other game projects' tests entry point. The suites themselves are
PowerShell (they drive the Windows builds); this wrapper just runs them in order
and returns a non-zero status if any fail.

usage: python tests/run_tests.py [rom-path]
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
SUITES = [
    ("core validation", "validate.ps1"),
    ("save edge cases", "validate-saves.ps1"),
    ("reference comparison", "compare-reference.ps1"),
]


def main():
    rom = sys.argv[1] if len(sys.argv) > 1 else ""
    failed = 0
    for name, script in SUITES:
        path = os.path.join(REPO, "scripts", script)
        if not os.path.exists(path):
            print("[skip] %s (%s missing)" % (name, script))
            continue
        cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path]
        if rom:
            cmd += ["-Rom", rom]
        print("\n=== %s ===" % name)
        rc = subprocess.call(cmd)
        if rc != 0:
            print("[FAIL] %s (exit %d)" % (name, rc))
            failed += 1
        else:
            print("[ok] %s" % name)
    print("\n%d suite(s) failed" % failed if failed else "\nall suites passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
