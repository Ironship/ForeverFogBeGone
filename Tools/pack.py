#!/usr/bin/env python3
"""Build the upload archive, and prove it opens.

    python Tools/pack.py                 # write it next to the other packages
    python Tools/pack.py --check         # open what is already there

What goes in is what the CurseForge packager would put in: the files git
tracks, minus what .pkgmeta tells it to ignore, minus .pkgmeta itself. Asking
git and .pkgmeta rather than listing the files here means the hand-built
archive and the one a tag will build cannot drift apart -- and a tag is how
this ships once the project exists and the repository is wired to it.

The archive is written to a .partial name, reopened, compared entry by entry
against what went in, and only then moved into place. A listing cannot tell a
truncated archive from a good one; one in this project shipped that way once.
"""

import argparse
import os
import pathlib
import re
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
NAME = "ForeverFogBeGone"
# Every archive waiting for CurseForge sits in one folder on the Desktop. The
# old curseforge-packages beside it was emptied of stale builds and deleted;
# writing there would quietly bring it back.
OUT = ROOT.parent.parent / "CurseForge-do-wgrania"


def tracked():
    out = subprocess.run(["git", "-C", str(ROOT), "ls-files"], capture_output=True, text=True)
    if out.returncode:
        sys.exit("not a checkout: %s" % out.stderr.strip()[:120])
    return out.stdout.split()


def ignores():
    meta = ROOT / ".pkgmeta"
    out, inside = [], False
    for line in meta.read_text(encoding="utf-8").splitlines():
        if line.startswith("ignore:"):
            inside = True
            continue
        if inside:
            s = line.strip()
            if s.startswith("-"):
                out.append(s.lstrip("- ").strip())
            elif s and not line.startswith((" ", "\t")):
                break
    return out


def version():
    toc = (ROOT / ("%s_Mainline.toc" % NAME)).read_text(encoding="utf-8-sig")
    found = re.search(r"^## Version:\s*(.+)$", toc, re.M)
    if not found:
        sys.exit("no version in the manifest")
    return found.group(1).strip()


def contents():
    skip = ignores()
    out = []
    for rel in tracked():
        if rel.startswith(".") or "/." in rel or rel == ".pkgmeta":
            continue
        if any(rel == i or rel.startswith(i.rstrip("/") + "/") for i in skip):
            continue
        if (ROOT / rel).is_file():
            out.append(rel)
    return sorted(out)


def check(archive, expected=None):
    problems = []
    with zipfile.ZipFile(archive) as z:
        written = {i.filename: i.file_size for i in z.infolist() if not i.is_dir()}
        tops = {n.split("/", 1)[0] for n in written}
        if tops != {NAME}:
            problems.append("top-level folders %s" % sorted(tops))
        if expected:
            want = {"%s/%s" % (NAME, r): (ROOT / r).stat().st_size for r in expected}
            for n, s in want.items():
                if n not in written:
                    problems.append("missing %s" % n)
                elif written[n] != s:
                    problems.append("wrong size %s" % n)
            for n in set(written) - set(want):
                problems.append("unexpected %s" % n)
        for toc in [n for n in written if n.endswith(".toc")]:
            loads = ["%s/%s" % (NAME, l.strip())
                     for l in z.read(toc).decode("utf-8-sig").splitlines()
                     if l.strip() and not l.strip().startswith("#")]
            absent = [l for l in loads if l not in written]
            if absent:
                problems.append("%s loads missing %s" % (toc.rsplit("/", 1)[-1], absent))
        # The manifest points the client at these by path and no manifest line
        # names them, so nothing else here would notice one missing -- and the
        # second only appears when the fog is on, which is the state a first
        # look at the addon is least likely to be in.
        for texture in ("icon.tga", "icon-fog.tga"):
            if ("%s/" + texture) % NAME not in written:
                problems.append("no " + texture + " -- the button would be a blank square")
        bad = z.testzip()
        if bad:
            problems.append("CRC failed at %s" % bad)
    return problems, written


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(OUT))
    ap.add_argument("--check", action="store_true", help="only open what is already built")
    args = ap.parse_args()

    v = version()
    outdir = pathlib.Path(args.out)
    archive = outdir / ("%s-%s.zip" % (NAME, v))

    if args.check:
        if not archive.is_file():
            sys.exit("nothing built at %s" % archive)
        problems, written = check(archive)
        print("%s: %d files, %s" % (archive.name, len(written),
                                    "ok" if not problems else "; ".join(problems)))
        return 1 if problems else 0

    files = contents()
    outdir.mkdir(parents=True, exist_ok=True)
    partial = archive.with_suffix(".zip.partial")
    if partial.exists():
        partial.unlink()
    with zipfile.ZipFile(partial, "w", zipfile.ZIP_DEFLATED) as z:
        for rel in files:
            z.write(ROOT / rel, "%s/%s" % (NAME, rel))
    problems, written = check(partial, files)
    if problems:
        print("FAILED -- nothing moved into place")
        for p in problems:
            print("   %s" % p)
        return 1
    if archive.exists():
        archive.unlink()
    os.replace(partial, archive)
    print("ok  %s  %.1f kB" % (archive.name, archive.stat().st_size / 1024))
    for rel in files:
        print("    %s" % rel)
    return 0


if __name__ == "__main__":
    sys.exit(main())
