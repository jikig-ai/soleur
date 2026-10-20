#!/usr/bin/env python3
"""Regenerates audit-differential.tsv: the old brute-force audit scan versus the component-boundary scan, per OCCURRENCE.

usage: audit-differential.py ROOT ROWS_FILE [--sut PATH] [--out TSV]
  ROOT       a checkout of the pinned tree, e.g. `git worktree add --detach /var/tmp/pin <sha>` (read-only; nothing is written there)
  ROWS_FILE  the selector's rows for that same tree:
             `cd ROOT && bash scripts/test-all.sh --print-selection --paths=README.md > ROWS_FILE`   (about 3 minutes)
  --sut      the scripts/ci-pr-affected-replay.py under test (default: the one at the top of the tree this file lives in; it is
             deliberately NOT read from ROOT, which holds the pinned, older copy)
  --out      default: audit-differential.tsv beside this file
Standard library only. Exit 0 when the new refs are a subset of the old refs for every suite, 1 when not (a ref the new scan found and
the old one did not is a bug in one of them), 2 on usage.

THE COMPARISON. For every audited suite (the same inputs, the same hop, the same comment stripping, the same exclusions of the
suite itself and of the runner triggers on BOTH sides, so the only thing that differs is the match rule):
  old   a tracked path is named when it occurs ANYWHERE in the suite's text as a substring (the pre-PR1 scan: `f in blob`)
  new   a tracked path is named when it occurs at a boundary of either view of the text (the SUT's views(): full and light)
Every occurrence of every old ref is classified, and the ones that are not a plain boundary are LISTED with their source line:
  dropped        starts mid-component in BOTH views of the line (a word character in front of it): the new scan ignores this occurrence
  declared-drop  the same, and the path is glued to the tail of an ANSI colour code (`\\033[0m<path>`): display text, a declared limit
  kept-escape    a word character in front of it in the text as written, but a printf escape or an attached short option makes it a
                 boundary in a view: the new scan keeps it
An occurrence at a plain boundary is not listed. The `pair` column says whether the (suite, path) pair `vanished` from the new refs
(every occurrence dropped) or `survives` (another occurrence is a boundary). In the header and on stdout `dropped` counts the PAIRS
that vanished (old refs minus new refs, computed from the two sets, not from the rows) and `dropped_occurrences` the listed
`dropped` rows; a vanished pair without a row is an error (exit 1: scan_text and boundary() disagree). The suite, path and source columns are written through the SUT's quote_field (a backslash, a control character or a bidi/zero-width
character becomes \\xHH or \\uXXXX); `line_text` has every control character, separator and bidi/zero-width character replaced by one space, so `col` stays valid
and the file holds no raw control byte. `loc` is `line:col` (1-based line of the file `source`,
0-based column of the path in `line_text`), so a reader or the test can check one occurrence against its line.
The test (plugins/soleur/test/ci-pr-affected-replay.test.sh) judges the stored rows with the SUT's own views() and boundary(), and runs
this script on a small scratch repo; it does NOT regenerate the pinned-tree receipt, so completeness of the stored rows is attested by
re-running this script on the pinned tree and diffing.
"""
import importlib.util
import os
import re
import subprocess
import sys

COLOUR = re.compile(r"(?:\\0[0-7]{1,3}|\\e|\\x1[bB]|\x1b)\[[0-9;]*m$")


def flat(sut, text):
    """The stored line text: a control character (C0, DEL, C1), a separator or a bidi/zero-width character becomes one space (offsets do
    not move; none of them is a word character, so the boundary of every occurrence is unchanged)."""
    return "".join(" " if ord(c) < 0x20 or c == "\x7f" or sut.QUOTE_U.match(c) else c for c in text)


def find_sut(here):
    d = here
    while True:
        cand = os.path.join(d, "scripts", "ci-pr-affected-replay.py")
        if os.path.isfile(cand):
            return cand
        parent = os.path.dirname(d)
        if parent == d:
            return ""
        d = parent


def main(argv):
    here = os.path.dirname(os.path.abspath(__file__))
    args, pos, i = {"--sut": find_sut(here), "--out": os.path.join(here, "audit-differential.tsv")}, [], 0
    while i < len(argv):
        if argv[i] in args and i + 1 < len(argv):
            args[argv[i]] = argv[i + 1]
            i += 2
        elif argv[i].startswith("--"):
            print(__doc__, file=sys.stderr)
            return 2
        else:
            pos.append(argv[i])
            i += 1
    if len(pos) != 2 or not args["--sut"]:
        print(__doc__, file=sys.stderr)
        return 2
    root, rows_file = pos
    spec = importlib.util.spec_from_file_location("sut", args["--sut"])
    sut = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(sut)

    rows = []
    with open(rows_file, encoding="utf-8", errors="replace", newline="") as fh:
        rows_text = fh.read()
    for line in rows_text.split("\n"):
        f = line.rstrip("\r").split("\t")
        if f[0] == "AFFECTED_SELECTED" and len(f) >= 5 and f[3] != "always_on":
            rows.append((f[1], f[4].split("|")))
    q = sut.quote_field   # every name that is printed or tabbed goes through the SUT's own quoting
    top = os.path.realpath(root)
    tracked = sut.tracked_files(root)
    index = sut.PathIndex(tracked)
    old_refs, new_refs, texts_of, pats_of = {}, {}, {}, {}
    for suite, pats in rows:
        inputs = sut.suite_inputs(root, pats[0], index)
        if inputs is None:
            continue
        texts = sut.suite_texts(root, inputs, index, [])
        own = {os.path.relpath(p, root) for p in inputs}
        blob = "\n".join(tr for _, _, _, tr in texts)
        keep = lambda f: f != suite and f not in own and f not in sut.RUNNER_TRIGGERS  # noqa: E731
        old_refs[suite] = {f for f in tracked if keep(f) and f in blob}
        new_refs[suite] = set(sut.suite_refs(root, suite, inputs, index, texts))
        texts_of[suite], pats_of[suite] = texts, pats

    bad = 0
    for suite in sorted(old_refs):
        extra = new_refs[suite] - old_refs[suite]
        if extra:
            print("NEW SCAN FOUND WHAT THE OLD ONE DID NOT: %s %s" % (q(suite), [q(x) for x in sorted(extra)[:5]]))
            bad += 1

    vanished = {(s, r) for s in old_refs for r in old_refs[s] - new_refs[s]}
    out_rows = []
    for suite in sorted(old_refs):
        for rel in sorted(old_refs[suite]):
            pair = "vanished" if (suite, rel) in vanished else "survives"
            for qpath, tn, tl, tr in texts_of[suite]:
                if rel not in tr:
                    continue
                norm_lines, light_lines, raw_lines = tn.split("\n"), tl.split("\n"), tr.split("\n")
                for no, raw in enumerate(raw_lines, 1):
                    col = raw.find(rel)
                    while col >= 0:
                        norm_ok = sut.boundary(norm_lines[no - 1], col) or sut.boundary(light_lines[no - 1], col)
                        raw_ok = col == 0 or sut.WORD.match(raw[col - 1]) is None
                        shown = flat(sut, raw)
                        if norm_ok and not raw_ok:
                            verdict = "kept-escape"
                        elif not norm_ok:
                            verdict = "declared-drop" if COLOUR.search(shown[:col]) else "dropped"
                        else:
                            verdict = ""
                        if verdict:
                            out_rows.append((verdict, q(suite), q(rel), pair, q(os.path.relpath(qpath, top)), "%d:%d" % (no, col), shown))
                        col = raw.find(rel, col + 1)
    rowed = {(r[1], r[2]) for r in out_rows if r[3] == "vanished"}
    for suite, rel in sorted(vanished):
        if (q(suite), q(rel)) not in rowed:
            print("VANISHED PAIR WITHOUT A ROW: %s %s" % (q(suite), q(rel)))
            bad += 1

    def gaps(refs):
        return {(s, r) for s, rs in refs.items() for r in rs if not any(sut.edge_hit(pt, r) for pt in pats_of[s])}

    count = {k: sum(1 for r in out_rows if r[0] == k) for k in ("dropped", "declared-drop", "kept-escape")}
    head = subprocess.run(["git", "-C", root, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip() or "unknown"
    out_rows.sort(key=lambda r: (r[1], r[2], r[4], int(r[5].split(":")[0]), int(r[5].split(":")[1]), r[0]))
    with open(args["--out"], "w") as fh:
        fh.write("# old brute-force scan versus the component-boundary scan, per occurrence (regenerate: see the header of audit-differential.py)\n")
        fh.write("# tree %s\n" % head)
        fh.write("# old_gap_pairs=%d new_gap_pairs=%d\n" % (len(gaps(old_refs)), len(gaps(new_refs))))
        fh.write("# old_refs=%d new_refs=%d dropped=%d dropped_occurrences=%d declared_drop=%d kept_escape=%d\n" % (
            sum(map(len, old_refs.values())), sum(map(len, new_refs.values())), len(vanished), count["dropped"], count["declared-drop"], count["kept-escape"]))
        fh.write("verdict\tsuite\tpath\tpair\tsource\tloc\tline_text\n")
        for r in out_rows:
            fh.write("\t".join(r) + "\n")
    print("suites=%d old_refs=%d new_refs=%d dropped=%d dropped_occurrences=%d declared_drop=%d kept_escape=%d old_gap_pairs=%d new_gap_pairs=%d bad=%d" % (
        len(old_refs), sum(map(len, old_refs.values())), sum(map(len, new_refs.values())), len(vanished), count["dropped"],
        count["declared-drop"], count["kept-escape"], len(gaps(old_refs)), len(gaps(new_refs)), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
