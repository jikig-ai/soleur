#!/usr/bin/env python3
"""reach-differential.py: every (suite, path) gap pair the audit's reach change ADDS or REMOVES, with the first line that names it.

Usage: reach-differential.py ROOT ROWS_FILE --old-sut PATH [--sut PATH] [--out TSV]

ROOT       the tree the audit reads (a detached checkout of the start commit: the selector derives `pats` from working-tree text)
ROWS_FILE  the AFFECTED_SELECTED rows the selector printed for that tree (`test-all.sh --print-selection --paths=README.md`)
--old-sut  scripts/ci-pr-affected-replay.py as it was at the start commit (`git show <start>:scripts/ci-pr-affected-replay.py`)
--sut      the audit under test (default: scripts/ci-pr-affected-replay.py found by walking up from this script, so the default also
           works once the spec directory is archived one level deeper)

Both audits run through their own `audit_census` with no accept file; this script re-implements no walk. `added` is GROSS: pairs the new audit
reports that the old one did not (the definition of CTO ruling 3, decision-challenges.md). `removed` is listed row by row too, because
edge parity and the rule that a runner trigger is never an input can narrow (the source closure, the naming walk and the comment table can
only widen): every removal is justified in the PR body.

THE SERIES GUARD, enforced where the numbers are produced: with B the old audit's pair count, `added >= B` (the stop line, 100 percent) writes NOTHING
(and removes a stale --out file) and exits 1; so does a new audit with more unaudited suites than the old one, because their pairs would leave the
set unseen and be listed as removed; `added >= ceil(B / 2)` (the re-split line, 50 percent) prints the re-split note for PR4 and PR5 and still writes (exit 0).

OUTPUT (TSV). First line `# old_sut=<blob sha> tree=<HEAD of ROOT> rows_sha256=<hash> base_pairs=B new_pairs=N added=A removed=R`, then `# added`, A rows
`suite<TAB>path<TAB>path_class<TAB>via`, then `# removed`, R rows of the same shape. path_class is `code` or `non-code` (the split PR4 and PR5 drain by);
via is the first `file:line` the SUT's own Census.ref_lines gives for the pair.
"""
import argparse
import hashlib
import importlib.util
import math
import os
import subprocess
import sys


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def census(mod, root, rows):
    c = mod.audit_census(root, rows, {})
    pairs = {(label, p) for label, paths in c.gaps.items() for p in paths}
    return c, pairs


def via(c, label, path):
    try:
        lines = c.ref_lines(label, path)
    except Exception:   # a pair with no printable line (a newline in a name): the column says so instead of guessing
        lines = []
    return "%s:%d" % (lines[0][2], lines[0][3]) if lines else "-"


def blob_sha(path):
    p = subprocess.run(["git", "hash-object", path], capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else "unknown"


def tree_head(root):
    p = subprocess.run(["git", "-C", root, "rev-parse", "HEAD"], capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else "unknown"


def find_sut():
    """scripts/ci-pr-affected-replay.py of the repository this script sits in, found by walking up (the spec directory moves under
    specs/archive/ at ship, one level deeper)."""
    d = os.path.dirname(os.path.abspath(__file__))
    while True:
        cand = os.path.join(d, "scripts", "ci-pr-affected-replay.py")
        if os.path.isfile(cand):
            return cand
        up = os.path.dirname(d)
        if up == d:
            return ""
        d = up


def drop_stale(path):
    """A refused run must not leave an earlier run's receipt behind looking current."""
    for p in (path, path + ".part") if path else ():
        try:
            os.unlink(p)
        except FileNotFoundError:
            pass


def main(argv):
    ap = argparse.ArgumentParser(prog="reach-differential", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root")
    ap.add_argument("rows")
    ap.add_argument("--old-sut", required=True, dest="old_sut")
    ap.add_argument("--sut", default=find_sut())
    ap.add_argument("--out", default="")
    a = ap.parse_args(argv)
    old, new = load(a.old_sut, "old_sut"), load(a.sut, "new_sut")
    rows = new.load_rows(a.rows, a.root)
    c_old, p_old = census(old, a.root, rows)
    c_new, p_new = census(new, a.root, rows)
    base = len(p_old)
    added, removed = sorted(p_new - p_old), sorted(p_old - p_new)
    code_ext = new.CODE_EXT
    cls = lambda path: "code" if os.path.splitext(path)[1] in code_ext else "non-code"   # noqa: E731
    stop, resplit = base, math.ceil(base / 2)
    print("reach-differential: base_pairs=%d new_pairs=%d added=%d removed=%d re_split_line=%d stop_line=%d" % (base, len(p_new), len(added), len(removed), resplit, stop))
    if len(c_new.unaudited) > len(c_old.unaudited):
        print("reach-differential: STOP: the new audit leaves more suites unaudited than the old one (%d > %d); nothing written." % (len(c_new.unaudited), len(c_old.unaudited)), file=sys.stderr)
        drop_stale(a.out)
        return 1
    if len(added) >= stop:
        print("reach-differential: STOP: added >= the stop line (%d >= %d); nothing written. Stop the series for a re-ruling (decision-challenges.md row 3)." % (len(added), stop), file=sys.stderr)
        drop_stale(a.out)
        return 1
    if len(added) >= resplit:
        print("reach-differential: RE-SPLIT: added >= the re-split line (%d >= %d): PR4 and PR5 split by gap class (code-edge pairs apart from accept-row and non-code pairs)." % (len(added), resplit))
    if a.out:
        with open(a.out + ".part", "w", encoding="utf-8") as fh:
            fh.write("# old_sut=%s tree=%s rows_sha256=%s base_pairs=%d new_pairs=%d added=%d removed=%d\n" % (
                blob_sha(a.old_sut), tree_head(a.root), hashlib.sha256(open(a.rows, "rb").read()).hexdigest(), base, len(p_new), len(added), len(removed)))
            fh.write("# added\n")
            for label, path in added:
                fh.write("%s\t%s\t%s\t%s\n" % (new.quote_field(label), new.quote_field(path), cls(path), new.quote_field(via(c_new, label, path))))
            fh.write("# removed\n")
            for label, path in removed:
                fh.write("%s\t%s\t%s\t%s\n" % (old.quote_field(label), old.quote_field(path), cls(path), old.quote_field(via(c_old, label, path))))
        os.replace(a.out + ".part", a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
