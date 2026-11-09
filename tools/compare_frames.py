#!/usr/bin/env python3
"""Structural frame comparison used by scripts/compare-reference.ps1.

A raw pixel diff is misleading because this port and BizHawk use different
3-bit-to-8-bit colour ladders (hardware DAC ladder vs naive x34). This builds the
colour mapping from our frame to the reference frame and reports the share of
pixels that agree after it; 100% means the image is identical apart from colour.

usage: compare_frames.py <workdir> <frame1,frame2,...> <offset>
"""
import collections
import os
import sys

from PIL import Image


def struct_match(a, b):
    mapping = collections.defaultdict(collections.Counter)
    for pa, pb in zip(a.getdata(), b.getdata()):
        mapping[pa][pb] += 1
    lut = {pa: ctr.most_common(1)[0][0] for pa, ctr in mapping.items()}
    bad = sum(1 for pa, pb in zip(a.getdata(), b.getdata()) if lut[pa] != pb)
    return 100.0 * (1 - bad / float(a.size[0] * a.size[1])), len(mapping)


def main():
    work, frames, offset = sys.argv[1], [int(x) for x in sys.argv[2].split(",")], int(sys.argv[3])
    print("  ours   ref   colours  structural match")
    worst = 100.0
    for n in frames:
        ours = os.path.join(work, "ours_%05d.bmp" % n)
        ref = os.path.join(work, "ref_%05d.png" % (n + offset))
        if not (os.path.exists(ours) and os.path.exists(ref)):
            print("  %5d  %5d   (missing)" % (n, n + offset))
            worst = 0.0
            continue
        pct, colours = struct_match(
            Image.open(ours).convert("RGB"), Image.open(ref).convert("RGB")
        )
        worst = min(worst, pct)
        print("  %5d  %5d   %3d      %6.2f%%" % (n, n + offset, colours, pct))
    print("WORST %.2f%%" % worst)
    return 0 if worst >= 99.9 else 1


if __name__ == "__main__":
    sys.exit(main())
