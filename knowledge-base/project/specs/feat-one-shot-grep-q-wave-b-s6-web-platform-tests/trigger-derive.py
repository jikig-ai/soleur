#!/usr/bin/env python3
"""Which path-filtered workflows does a file list fire? (S6 matcher; read-only, never edits anything.)

usage: trigger-derive.py [--root DIR] [--events push,pull_request,merge_group,pull_request_target] [--probe] FILE_LIST
       FILE_LIST is a path to a file with one repo-relative path per line, or `-` for stdin
       (typically `git diff --name-only <merge-base>...HEAD`).

Output, one line per workflow that has a trigger of a listed event:
  FILTERED  <workflow>  <event>  N of M    (N = files that satisfy the workflow's `paths` / `paths-ignore` filter)
  UNFILTERED <workflow> <event>            (the event has no path filter: it runs on every push to main / every PR)
and a final summary. GitHub filter semantics implemented here:
  * `*` stays inside one path segment, `**` crosses `/`, `?` is one non-`/` character, `[...]` is a class;
  * `paths` is ordered: a plain pattern includes, a `!pattern` excludes what it matches, a LATER pattern overrides an
    earlier one (the file is in only if the last pattern that matched it was an include);
  * `paths-ignore` fires the workflow when at least one file matches none of the patterns;
  * `branches` / `branches-ignore` on push (and on pull_request, which filters the BASE branch) are applied to `main`;
  * `workflow_run`, `schedule` and `workflow_dispatch` are not path-filtered and are not listed here.
--probe runs the sanity check: three paths known to match filtered workflows must light several of them, so a
matcher that matches nothing cannot pass for "nothing fires".
"""
import argparse
import fnmatch
import os
import re
import sys

import yaml

PROBE = ["apps/web-platform/infra/server.tf", "plugins/soleur/docs/x.md", "scripts/test-all.sh"]


def glob_to_re(pat):
    i, n, out = 0, len(pat), []
    while i < n:
        c = pat[i]
        if c == "*":
            if pat.startswith("**", i):
                j = i + 2
                if pat.startswith("**/", i):
                    out.append("(?:.*/)?")   # `**/` also matches zero segments
                    i += 3
                    continue
                out.append(".*")
                i = j
                continue
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        elif c == "[":
            j = pat.find("]", i + 1)
            if j < 0:
                out.append(re.escape(c))
            else:
                body = pat[i + 1:j]
                if body.startswith("!"):
                    body = "^" + body[1:]
                out.append("[" + body + "]")
                i = j
        else:
            out.append(re.escape(c))
        i += 1
    return re.compile("^" + "".join(out) + "$")


def in_paths(path, patterns):
    state = False
    for p in patterns:
        neg = p.startswith("!")
        rx = glob_to_re(p[1:] if neg else p)
        if rx.match(path):
            state = not neg
    return state


def branch_ok(cfg, base="main"):
    if not isinstance(cfg, dict):
        return True
    br, bi = cfg.get("branches"), cfg.get("branches-ignore")
    if br is not None:
        return any(fnmatch.fnmatchcase(base, b) for b in (br if isinstance(br, list) else [br]))
    if bi is not None:
        return not any(fnmatch.fnmatchcase(base, b) for b in (bi if isinstance(bi, list) else [bi]))
    return True


def events_of(doc):
    on = doc.get("on", doc.get(True))   # YAML 1.1 parses a bare `on:` key as boolean True
    if isinstance(on, str):
        return {on: None}
    if isinstance(on, list):
        return {e: None for e in on}
    return on or {}


def derive(root, files, want):
    rows = []
    wfdir = os.path.join(root, ".github", "workflows")
    for name in sorted(os.listdir(wfdir)):
        if not name.endswith((".yml", ".yaml")):
            continue
        with open(os.path.join(wfdir, name), encoding="utf-8") as fh:
            doc = yaml.safe_load(fh) or {}
        ev = events_of(doc)
        for e in want:
            if e not in ev:
                continue
            cfg = ev[e] if isinstance(ev[e], dict) else {}
            if not branch_ok(cfg):
                rows.append((name, e, "BRANCH-EXCLUDED", None))
                continue
            paths, ignore = cfg.get("paths"), cfg.get("paths-ignore")
            if paths is not None:
                n = sum(1 for f in files if in_paths(f, paths if isinstance(paths, list) else [paths]))
                rows.append((name, e, "FILTERED", n))
            elif ignore is not None:
                ig = ignore if isinstance(ignore, list) else [ignore]
                n = sum(1 for f in files if not any(glob_to_re(p).match(f) for p in ig))
                rows.append((name, e, "FILTERED", n))
            else:
                rows.append((name, e, "UNFILTERED", None))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--events", default="push,pull_request,merge_group,pull_request_target")
    ap.add_argument("--probe", action="store_true")
    ap.add_argument("list")
    a = ap.parse_args()
    src = sys.stdin if a.list == "-" else open(a.list, encoding="utf-8")
    files = [l.strip() for l in src if l.strip()]
    if not files:
        print("UNRESOLVED: empty file list; nothing was measured", file=sys.stderr)
        return 3
    want = a.events.split(",")
    if a.probe:
        rows = derive(a.root, PROBE, want)
        lit = sorted({r[0] for r in rows if r[2] == "FILTERED" and r[3]})
        print("PROBE: %d filtered workflows lit by %s: %s" % (len(lit), PROBE, " ".join(lit)))
        return 0 if len(lit) >= 3 else 3
    rows = derive(a.root, files, want)
    m = len(files)
    for name, e, kind, n in rows:
        if kind == "FILTERED" and n:
            print("FILTERED   %-52s %-20s %d of %d" % (name, e, n, m))
    zero = sorted({(r[0], r[1]) for r in rows if r[2] == "FILTERED" and not r[3]})
    unf = sorted({(r[0], r[1]) for r in rows if r[2] == "UNFILTERED"})
    for name, e in unf:
        print("UNFILTERED %-52s %s" % (name, e))
    print("SUMMARY: %d files; %d filtered (workflow,event) pairs fire; %d filtered pairs match 0 of %d; %d unfiltered pairs" % (
        m, sum(1 for r in rows if r[2] == "FILTERED" and r[3]), len(zero), m, len(unf)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
