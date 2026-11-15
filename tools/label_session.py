#!/usr/bin/env python3
"""label_session.py - turn a recorded scene timeline into readable, comparable text.

Input is a runner stderr log containing one `[FBHASH] frame=N ... hash=0x...` line
per frame (what `record-session.ps1` captures). A run of consecutive identical
hashes is a "scene"; the output lists each scene with its start frame and length.

Modes:
  --build   write a scene catalog (JSON) from a known-good session
  --compare compare a session against the catalog and flag skipped/short scenes

The catalog stores the ordered scene hashes with their typical length, so a later
session that skips a cutscene shows up as a missing catalog entry instead of a
mystery.
"""
import argparse, json, re, sys

LINE = re.compile(r"\[FBHASH\] frame=(\d+) w=\d+ h=\d+ hash=(0x[0-9A-Fa-f]+)")

def load(path):
    frames = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = LINE.search(line)
            if m:
                frames.append((int(m.group(1)), m.group(2)))
    return frames

def segments(frames, min_len=8):
    out = []
    if not frames:
        return out
    start = 0
    for k in range(1, len(frames)):
        if frames[k][1] != frames[k - 1][1]:
            length = frames[k][0] - frames[start][0]
            if length >= min_len:
                out.append({"start": frames[start][0], "len": length, "hash": frames[start][1]})
            start = k
    length = frames[-1][0] - frames[start][0]
    if length >= min_len:
        out.append({"start": frames[start][0], "len": length, "hash": frames[start][1]})
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("session", help="runner log with per-frame FBHASH lines")
    ap.add_argument("--build", help="write the scene catalog to this JSON path")
    ap.add_argument("--compare", help="compare against this catalog JSON")
    ap.add_argument("--min-len", type=int, default=8)
    args = ap.parse_args()

    frames = load(args.session)
    segs = segments(frames, args.min_len)
    print("session: %s" % args.session)
    print("frames=%d scenes=%d" % (len(frames), len(segs)))
    for i, s in enumerate(segs):
        print("  scene %02d  start=%5d len=%5d %s" % (i, s["start"], s["len"], s["hash"]))

    if args.build:
        with open(args.build, "w", encoding="utf-8") as f:
            json.dump({"scenes": segs}, f, indent=1)
        print("catalog written: %s" % args.build)

    if args.compare:
        with open(args.compare, encoding="utf-8") as f:
            cat = json.load(f)["scenes"]
        print("\ncomparison against %s" % args.compare)
        cat_end = max((c["start"] + c["len"]) for c in cat) if cat else 0
        captured_end = frames[-1][0] if frames else 0
        complete = captured_end >= cat_end * 0.95
        if not complete:
            print("  NOTE: session looks INCOMPLETE (captured to frame %d, catalog runs to %d)"
                  % (captured_end, cat_end))
            print("        shortened trailing scenes are not counted as skips.")

        import difflib
        a = [c["hash"] for c in cat]
        b = [s["hash"] for s in segs]
        sm = difflib.SequenceMatcher(a=a, b=b, autojunk=False)
        skipped, extra, short = [], [], []
        for tag, i1, i2, j1, j2 in sm.get_opcodes():
            if tag in ("delete", "replace"):
                for i in range(i1, i2):
                    c = cat[i]
                    if not complete and c["start"] + c["len"] > captured_end:
                        continue
                    skipped.append((i, c))
            if tag in ("insert", "replace"):
                for j in range(j1, j2):
                    extra.append((j, segs[j]))
            if tag == "equal":
                for k in range(i2 - i1):
                    c, s = cat[i1 + k], segs[j1 + k]
                    if not complete and c["start"] + c["len"] > captured_end:
                        continue
                    if c["len"] >= 40 and s["len"] < c["len"] * 0.5:
                        short.append((i1 + k, c, s))
        if skipped:
            print("  SKIPPED / MISSING scenes (%d):" % len(skipped))
            for i, c in skipped:
                print("    catalog scene %02d  expected len=%5d  %s" % (i, c["len"], c["hash"]))
        else:
            print("  no catalog scene is missing")
        if short:
            print("  TRUNCATED scenes (%d):" % len(short))
            for i, c, s in short:
                print("    scene %02d expected %d frames, got %d" % (i, c["len"], s["len"]))
        if extra:
            print("  scenes not in catalog (%d):" % len(extra))
            for j, s in extra[:8]:
                print("    session scene %02d start=%5d len=%5d %s" % (j, s["start"], s["len"], s["hash"]))

if __name__ == "__main__":
    sys.exit(main())
