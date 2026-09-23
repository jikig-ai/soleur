#!/usr/bin/env python3
"""Replay concurrent .c4 PR pairs from main history and test artifact mergeability per format.

For a pair (A, B) of main commits touching .c4 sources (A older):
  base   = A^ sources
  sideA  = A's sources
  sideB  = base + (B^..B source diff), 3-way per file; skipped if that rebase conflicts
  merged = merge-file(sideA, base, sideB); conflict => source-conflict (positive control)
Render base/sideA/sideB/(merged) with likec4@1.50.0, format each, `git merge-file` the artifact.
Outcomes per format: CLEAN_CORRECT (merge == render(merged)), CLEAN_WRONG (false-clean),
CONFLICT. For a source-conflict pair the desired outcome is CONFLICT.
"""
import json, os, subprocess, sys, tempfile, hashlib, shutil

REPO = sys.argv[1]
COMMITS = sys.argv[2].split(",")   # newest first, as git log prints
GAPS = [int(g) for g in os.environ.get("GAPS", "1,2").split(",")]
D = "knowledge-base/engineering/architecture/diagrams"
SRCS = ["spec.c4", "model.c4", "views.c4"]
CACHE = os.environ.get("RENDER_CACHE", "/tmp/c4cache")
os.makedirs(CACHE, exist_ok=True)

def sh(*a, cwd=None, check=True, inp=None):
    return subprocess.run(a, cwd=cwd, check=check, capture_output=True, text=True, input=inp)

def show(rev, f):
    r = sh("git", "show", f"{rev}:{D}/{f}", cwd=REPO, check=False)
    return r.stdout if r.returncode == 0 else ""

def merge3(ours, base, theirs):
    with tempfile.TemporaryDirectory() as t:
        p = [os.path.join(t, n) for n in ("o", "b", "t")]
        for path, txt in zip(p, (ours, base, theirs)):
            open(path, "w").write(txt)
        r = sh("git", "merge-file", "-p", *p, check=False)
        return r.stdout, r.returncode  # rc>0 => conflicts

def render(srcs):
    key = hashlib.sha256(json.dumps(srcs, sort_keys=True).encode()).hexdigest()
    cp = os.path.join(CACHE, key + ".json")
    if os.path.exists(cp):
        return open(cp).read()
    with tempfile.TemporaryDirectory() as t:
        for f, txt in srcs.items():
            open(os.path.join(t, f), "w").write(txt)
        r = sh("npx", "-y", "likec4@1.50.0", "export", "json", "-o", "out.json", ".", cwd=t, check=False)
        log = r.stdout + r.stderr
        out = os.path.join(t, "out.json")
        if r.returncode or not os.path.exists(out) or "Invalid " in log or "Could not resolve" in log:
            return None
        txt = open(out).read()
    if not json.loads(txt).get("elements"):
        return None
    open(cp, "w").write(txt)
    return txt

FORMATS = {
    "raw": lambda o, txt: txt,
    "pretty": lambda o, txt: json.dumps(o, indent=2, ensure_ascii=False) + "\n",
    "sorted": lambda o, txt: json.dumps(o, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
    "pretty_nohash": lambda o, txt: json.dumps(nohash(o), indent=2, ensure_ascii=False) + "\n",
    "sorted_nohash": lambda o, txt: json.dumps(nohash(o), indent=2, sort_keys=True, ensure_ascii=False) + "\n",
    "flat_nohash": lambda o, txt: json.dumps(nohash(o), indent=0, ensure_ascii=False) + "\n",
    # The REAL shipped module, via its CLI (plugins/soleur/lib/c4-canonical-cli.mjs).
    "canonical": lambda o, txt: real_canonical(txt),
}

CANON_CLI = os.path.join(REPO, "plugins/soleur/lib/c4-canonical-cli.mjs")

def real_canonical(txt):
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        f.write(txt)
        path = f.name
    try:
        r = sh("node", CANON_CLI, path)
        return r.stdout
    finally:
        os.unlink(path)

def nohash(o):
    o = json.loads(json.dumps(o))
    for v in o.get("views", {}).values():
        v.pop("hash", None)
    return o

def fmt(name, txt):
    return FORMATS[name](json.loads(txt), txt)

results = []
for gap in GAPS:
    for i in range(len(COMMITS) - gap):
        B, A = COMMITS[i], COMMITS[i + gap]   # A older, B newer
        base = {f: show(A + "^", f) for f in SRCS}
        sa = {f: show(A, f) for f in SRCS}
        sb, rebase_bad = {}, False
        for f in SRCS:
            m, rc = merge3(base[f], show(B + "^", f), show(B, f))
            sb[f] = m
            rebase_bad |= rc != 0
        if rebase_bad or sa == base or sb == base:
            continue
        merged, src_conflict = {}, False
        for f in SRCS:
            m, rc = merge3(sa[f], base[f], sb[f])
            merged[f] = m
            src_conflict |= rc != 0
        rb, ra, rB = render(base), render(sa), render(sb)
        if not (rb and ra and rB):
            continue
        rm = None if src_conflict else render(merged)
        if not src_conflict and rm is None:
            continue
        row = {"A": A, "B": B, "gap": gap, "src_conflict": src_conflict}
        for name in FORMATS:
            out, rc = merge3(fmt(name, ra), fmt(name, rb), fmt(name, rB))
            if rc:
                row[name] = "CONFLICT"
            elif src_conflict:
                row[name] = "CLEAN_ON_SRC_CONFLICT"
            else:
                try:
                    want = json.loads(rm)
                    got = json.loads(out)
                    if name == "canonical":
                        ok = out == real_canonical(rm)  # byte-exact
                    else:
                        ok = got == (nohash(want) if "nohash" in name else want)
                except json.JSONDecodeError:
                    ok = False
                row[name] = "CLEAN_CORRECT" if ok else "CLEAN_WRONG"
        results.append(row)
        print(json.dumps(row), flush=True)
