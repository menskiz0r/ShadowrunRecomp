#!/usr/bin/env python3
"""compare_sessions.py - diff two reproduced sessions frame by frame.

Both directories are produced by scripts/replay-run.ps1. They must contain a
replay.err (per-frame [FBHASH] timeline) and a ram/ directory of work-RAM
snapshots. The tool:

  1. aligns the two timelines on their first differing scene,
  2. reports where the behaviour diverges (scene hash and frame),
  3. compares the RAM snapshots nearest that frame and prints the differing
     address ranges.

Usage: python tools/compare_sessions.py build/replay-bad build/replay-good
"""
import os, re, sys, glob

LINE = re.compile(r"\[FBHASH\] frame=(\d+) w=\d+ h=\d+ hash=(0x[0-9A-Fa-f]+)")

def timeline(path):
    seq = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = LINE.search(line)
            if m:
                seq.append((int(m.group(1)), m.group(2)))
    return seq

def snapshots(ram_dir):
    out = {}
    for p in glob.glob(os.path.join(ram_dir, "*.ram")):
        m = re.search(r"(\d+)", os.path.basename(p))
        if m:
            out[int(m.group(1))] = p
    return out

def first_divergence(a, b):
    n = min(len(a), len(b))
    for i in range(n):
        if a[i][1] != b[i][1]:
            return i
    return None

def nearest(snaps, frame):
    if not snaps:
        return None
    return min(snaps, key=lambda f: abs(f - frame))

def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    bad, good = sys.argv[1], sys.argv[2]
    a = timeline(os.path.join(bad, "replay.err"))
    b = timeline(os.path.join(good, "replay.err"))
    print("sessions: bad=%d frames  good=%d frames" % (len(a), len(b)))
    i = first_divergence(a, b)
    if i is None:
        print("timelines are identical for %d frames" % min(len(a), len(b)))
        return 0
    frame = a[i][0]
    print("first divergence at timeline index %d (frame %d)" % (i, frame))
    print("  bad  hash=%s" % a[i][1])
    print("  good hash=%s" % b[i][1])
    sa = snapshots(os.path.join(bad, "ram"))
    sb = snapshots(os.path.join(good, "ram"))
    fa, fb = nearest(sa, frame), nearest(sb, frame)
    print("  nearest RAM snapshots: bad=%s good=%s" % (fa, fb))
    if fa is not None and fb is not None:
        da = open(sa[fa], "rb").read()
        db = open(sb[fb], "rb").read()
        n = min(len(da), len(db))
        diffs = [(k, da[k], db[k]) for k in range(n) if da[k] != db[k]]
        print("  RAM differences: %d bytes" % len(diffs))
        for k, va, vb in diffs[:16]:
            print("    $FF%04X bad=%02X good=%02X" % (k, va, vb))
        if diffs:
            lo = min(k for k, _, _ in diffs); hi = max(k for k, _, _ in diffs)
            print("  differing range: $FF%04X..$FF%04X" % (lo, hi))
    return 0

if __name__ == "__main__":
    sys.exit(main())