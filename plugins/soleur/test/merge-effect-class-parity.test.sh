#!/usr/bin/env bash
# merge-effect-class-parity.test.sh - CI drift defence for merge-effect-class.sh (#10923, ADR-297).
#
# The classifier keeps a static allowlist; this test is what keeps it true. It derives the population of
# workflows that can run on a merge to main from .github/workflows/*.yml, closed-world over trigger keys
# (push to main, workflow_run, release, pull_request/_target closed). A workflow in that population is
# `production` unless it has a row WITH A REASON in plugins/soleur/scripts/merge-effect-class.ci-only.tsv.
# A production workflow must be path-gated, and no allowlisted path (the script's own witnesses and every
# tracked allowlisted file) may fire it. Direction 1 (anti-vacuity): every production workflow's own globs,
# instantiated, must read `production-effecting` from the real script.
#
# ci-only MEANING: "not directly gated by the merged file list as a production act" - never "harmless".
#
# Test seams (so the matrix runs without editing .github/workflows/): MEC_WORKFLOWS_DIR, MEC_CI_ONLY_LIST,
# MEC_INVARIANTS_TEST (workflow-run-deploy-invariants.test.sh) and MEC_SCRIPT (the script under test).
# Needs python3 with PyYAML (MEC_PYTHON names the interpreter, a seam for the missing-PyYAML row) (as ci-concurrency-key.test.sh does); a missing PyYAML fails loudly, never skips.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
WFDIR="${MEC_WORKFLOWS_DIR:-$ROOT/.github/workflows}"
CI_ONLY="${MEC_CI_ONLY_LIST:-$ROOT/plugins/soleur/scripts/merge-effect-class.ci-only.tsv}"
INV="${MEC_INVARIANTS_TEST:-$ROOT/plugins/soleur/test/workflow-run-deploy-invariants.test.sh}"
SCRIPT="${MEC_SCRIPT:-$ROOT/plugins/soleur/scripts/merge-effect-class.sh}"
THIS="plugins/soleur/test/merge-effect-class-parity.test.sh"

PY="${MEC_PYTHON:-python3}"
if ! "$PY" -I -c 'import yaml' >/dev/null 2>&1; then
  printf 'PARITY-FAIL: PyYAML is required to read the workflows (%s -I -c "import yaml" failed). Install it (pip install pyyaml); this test never skips.\n' "$PY" >&2
  exit 3
fi

R_RC=0
"$PY" -I - "$ROOT" "$WFDIR" "$CI_ONLY" "$INV" "$SCRIPT" "$THIS" <<'PYEOF' || R_RC=$?
import functools
import itertools
import os
import re
import shutil
import subprocess
import sys
import tempfile

import yaml

ROOT, WFDIR, CI_ONLY, INV, SCRIPT, THIS = sys.argv[1:7]
RERUN = "bash " + THIS
MEANING = ('ci-only means "not directly gated by the merged file list as a production act", never "harmless"')
CHECKS = 0
FAILS = []


def check(cond, msg):
    global CHECKS
    CHECKS += 1
    if not cond:
        FAILS.append(msg)


class Unsupported(Exception):
    pass


# Trigger keys that are never a production act as a function of the merged file list. Anything else fails.
INERT = {
    "schedule": "time-driven, not a function of a merge",
    "workflow_dispatch": "explicit manual dispatch",
    "repository_dispatch": "explicit API dispatch",
    "issues": "issue events, not a merge",
    "issue_comment": "comment events, not a merge",
    "merge_group": "merge-queue validation on a temporary ref, before the merge",
    "workflow_call": "reusable workflow, fires only from a caller that is enumerated on its own",
}
POP_KEYS = ("push", "workflow_run", "release", "pull_request", "pull_request_target")


@functools.lru_cache(maxsize=None)
def compile_glob(p):
    for ch in "?+[\\":
        if ch in p:
            raise Unsupported("glob %r uses %r: extend the matcher in %s" % (p, ch, THIS))
    out = ""
    i = 0
    while i < len(p):
        if p.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
        elif p.startswith("**", i):
            out += ".*"
            i += 2
        elif p[i] == "*":
            out += "[^/]*"
            i += 1
        else:
            out += re.escape(p[i])
            i += 1
    return re.compile("^" + out + "$")


def gh_match(path, pats):
    if pats and pats[0].startswith("!"):
        raise Unsupported("a filter list starts with a negation (%r): extend the matcher in %s" % (pats[0], THIS))
    m = False
    for p in pats:
        neg = p.startswith("!")
        if compile_glob(p[1:] if neg else p).match(path):
            m = not neg
    return m


def fires(path, shape):
    kind, pats = shape
    if kind == "paths":
        return gh_match(path, pats)
    if kind == "ignore":
        return not gh_match(path, pats)
    return True


def norm_on(d):
    on = d.get(True, d.get("on")) if isinstance(d, dict) else None
    if isinstance(on, str):
        return {on: None}
    if isinstance(on, list):
        return {k: None for k in on}
    return on if isinstance(on, dict) else {}


def branch_ok(cfg):
    if not isinstance(cfg, dict) or "branches" not in cfg:
        return True
    b = cfg["branches"]
    b = [b] if isinstance(b, str) else b
    return any(compile_glob(x).match("main") for x in b if not x.startswith("!"))


def load(wfdir):
    wfs = {}
    for f in sorted(os.listdir(wfdir)) if os.path.isdir(wfdir) else []:
        if not f.endswith(".yml"):
            continue
        with open(os.path.join(wfdir, f)) as fh:
            d = yaml.safe_load(fh)
        wfs[f] = {"file": f, "name": (d or {}).get("name", f), "on": norm_on(d)}
    return wfs


def push_shapes(cfg):
    """Effective shapes of a push arm, or None when it cannot run on main."""
    cfg = cfg if isinstance(cfg, dict) else {}
    if "tags" in cfg and "branches" not in cfg and "branches-ignore" not in cfg:
        return None
    if not branch_ok(cfg):
        return None
    if "paths" in cfg and "paths-ignore" in cfg:
        raise Unsupported("push uses both paths and paths-ignore (GitHub forbids it)")
    if "paths" in cfg:
        return [("paths", list(cfg["paths"]))]
    if "paths-ignore" in cfg:
        return [("ignore", list(cfg["paths-ignore"]))]
    return [("all", [])]


def read_ci_only(path):
    rows = []
    if not os.path.isfile(path):
        return rows
    with open(path) as fh:
        for ln in fh.read().split("\n"):
            if not ln or ln.startswith("#"):
                continue
            parts = ln.split("\t")
            rows.append((parts[0], parts[1] if len(parts) > 1 else ""))
    return rows


_TREE = {}


def tracked_allowlisted():
    if "p" not in _TREE:
        out = subprocess.run(["git", "-C", ROOT, "ls-files", "-z"], capture_output=True, check=True).stdout
        paths = [p.decode("utf-8", "surrogateescape") for p in out.split(b"\0") if p]
        _TREE["p"] = [p for p in paths if p.startswith("knowledge-base/") or ("/" not in p and p.endswith(".md"))]
    return _TREE["p"]


def run_script(script, args, stdin=None):
    r = subprocess.run(["bash", script] + args, input=stdin, capture_output=True)
    return r.returncode, r.stdout.decode("utf-8", "replace").strip()


def instantiate(pat):
    toks = re.split(r"(\*\*/|\*\*|\*)", pat)
    opts = []
    for t in toks:
        if t == "**/":
            opts.append(["", "x/", "knowledge-base/x/", "a/b/c/"])
        elif t == "**":
            opts.append(["", "x", "knowledge-base/x", "a/b/c"])
        elif t == "*":
            opts.append(["", "x"])
        else:
            opts.append([t])
    out = []
    for combo in itertools.islice(itertools.product(*opts), 64):
        s = "".join(combo)
        if s and not s.startswith("/") and not s.endswith("/") and "//" not in s:
            out.append(s)
    return out


def run_checks(wfdir, ci_only_path, inv_path, script, full=True):
    """Return nothing; failures accumulate in FAILS with a prefix so synthetic cases can read them."""
    global FAILS
    FAILS = []
    wfs = load(wfdir)
    check(len(wfs) > 0, "no workflows found in %s: an empty workflows directory is RED (population floor)" % wfdir)
    rows = read_ci_only(ci_only_path)
    ci = {}
    for name, reason in rows:
        check(reason.strip() != "", "ci-only row %r has an empty reason: give it a reason (%s)" % (name, MEANING))
        check(name not in ci, "ci-only row %r is listed twice" % name)
        ci[name] = reason

    # Population, closed-world over trigger keys.
    pop = {}
    for f, w in wfs.items():
        arms = {}
        for key, cfg in w["on"].items():
            if key in INERT:
                continue
            if key not in POP_KEYS:
                check(False, "%s: unknown trigger key %r: classify it or extend the inert list in %s" % (f, key, THIS))
                continue
            if key == "push":
                try:
                    sh = push_shapes(cfg)
                except Unsupported as e:
                    check(False, "%s: %s" % (f, e))
                    continue
                if sh is not None:
                    arms["push"] = sh
            elif key == "workflow_run":
                if branch_ok(cfg):
                    arms["workflow_run"] = list((cfg or {}).get("workflows", []))
            elif key == "release":
                arms["release"] = True
            elif key in ("pull_request", "pull_request_target"):
                types = (cfg or {}).get("types", []) if isinstance(cfg, dict) else []
                if "closed" in types:
                    arms["prclosed"] = True
        if arms:
            pop[f] = arms
    for f in pop:
        check(True, "")
    check(not full or len(pop) >= 25, "population floor: only %d workflows enumerated (expected at least 25); the enumeration is gutted" % len(pop))

    for name in ci:
        check(name in wfs, "ci-only row %r names a workflow that does not exist: remove this row" % name)
        if name in wfs:
            check(name in pop, "ci-only row %r names a workflow that is no longer enumerated (it has no merge-time trigger): remove this row" % name)

    by_name = {}
    for f, w in wfs.items():
        by_name.setdefault(w["name"], f)

    def resolve(f, stack):
        """Effective merge-time shapes of workflow file f from its push arm and its workflow_run parents."""
        if f in stack:
            raise Unsupported("workflow_run chain cycle through %s" % f)
        arms = pop.get(f, {})
        shapes = []
        if "push" in arms:
            shapes += arms["push"]
        for parent in arms.get("workflow_run", []):
            if parent not in by_name:
                raise Unsupported("%s: workflow_run parent %r is not a workflow in this directory" % (f, parent))
            pf = by_name[parent]
            parr = pop.get(pf, {})
            if "push" in parr or "workflow_run" in parr:
                shapes += resolve(pf, stack + [f])
            else:
                shapes += [("all", [])]
        return shapes

    inv_text = ""
    if os.path.isfile(inv_path):
        with open(inv_path) as fh:
            inv_text = fh.read()
    prod = {}
    for f, arms in sorted(pop.items()):
        if f in ci:
            continue
        add_hint = "add a ci-only row with a reason, e.g. %s<TAB><reason> (%s), or extend the deemed-gated constant" % (f, MEANING)
        if "release" in arms or "prclosed" in arms:
            check(False, "%s fires on release or pull_request closed and has no ci-only row: %s" % (f, add_hint))
            continue
        try:
            shapes = resolve(f, [])
        except Unsupported as e:
            check(False, "%s: %s" % (f, e))
            continue
        own = arms.get("push", [])
        has_all = any(k == "all" for k, _ in shapes)
        if has_all:
            own_paths = [s for s in own if s[0] == "paths"]
            if f == "web-platform-release.yml" and own_paths:
                check(re.search(r'^\s+fail "P3 ', inv_text, re.M) is not None
                      and re.search(r'^\s+fail "P1 ', inv_text, re.M) is not None,
                      "web-platform-release.yml is deemed gated by its own push.paths only while %s keeps the executable P3 and P1 assertions (a commented-out fail line does not count)" % os.path.basename(inv_path))
                shapes = own_paths
            elif own_paths:
                check(False, "%s has its own push.paths and an unfiltered workflow_run arm: only web-platform-release.yml is deemed gated. %s" % (f, add_hint))
                continue
            else:
                check(False, "%s is a production workflow with an unfiltered trigger: %s" % (f, add_hint))
                continue
        prod[f] = shapes
        check(True, "")

    # Direction 2: no witness and no tracked allowlisted path may fire a production workflow.
    rc, wout = run_script(script, ["--print-witnesses"])
    witnesses = [w for w in wout.split("\n") if w] if rc == 0 else []
    check(rc == 0 and len(witnesses) >= 2, "--print-witnesses failed or printed fewer than two witnesses (rc=%s)" % rc)
    tree = tracked_allowlisted()
    tree_ok = [p for p in tree if os.path.basename(p) != "CLAUDE.md" and not os.path.basename(p).startswith("AGENTS")]
    for f, shapes in prod.items():
        try:
            for w in witnesses:
                bad = [s for s in shapes if fires(w, s)]
                check(not bad, "allowlist entry %s fires workflow %s: remove the entry or narrow that workflow's paths" % (w, f))
            hits = [p for p in tree_ok if any(fires(p, s) for s in shapes)]
            check(not hits, "tracked allowlisted file(s) fire workflow %s (first: %s): the allowlist reads them safe. Narrow the workflow's paths or shrink the allowlist" % (f, hits[:1]))
        except Unsupported as e:
            check(False, "%s: %s" % (f, e))
    if full and tree_ok:
        clean = [p for p in tree_ok if re.search(r"[\x00-\x1f\x7f\\\"]", p) is None]
        rc, out = run_script(script, ["--files-from", "-"], ("\n".join(clean) + "\n").encode("utf-8", "surrogateescape"))
        check(rc == 0 and out == "not-production-effecting",
              "the script rejects a tracked allowlisted file (rc=%s out=%s): the real tree and the allowlist disagree" % (rc, out))

    # Direction 1 (anti-vacuity): instantiated production globs must read production-effecting.
    seen = set()
    for f, shapes in prod.items():
        for kind, pats in shapes:
            if kind != "paths":
                continue
            for p in pats:
                if p.startswith("!"):
                    continue
                try:
                    insts = instantiate(p)
                    check(len(insts) > 0, "%s: glob %r produced no instantiation" % (f, p))
                    for s in insts:
                        if not gh_match(s, pats) or s in seen:
                            continue
                        seen.add(s)
                        rc, out = run_script(script, ["--files-from", "-"], (s + "\n").encode())
                        check(rc != 0 and out == "production-effecting",
                              "%s fires on a path the script reads safe (rc=%s): the script and the workflow disagree about %r" % (f, rc, s))
                except Unsupported as e:
                    check(False, "%s: %s" % (f, e))
    return prod


# ── matcher unit table, pinned to GitHub's documented behaviour ───────────────────────────────────
TABLE = [
    (["a/**"], "a/x", True), (["a/**"], "a", False), (["a/**/b"], "a/b", True), (["a/**/b"], "a/x/y/b", True),
    (["**/x"], "x", True), (["**/x"], "a/b/x", True), (["*.md"], "a.md", True), (["*.md"], "a/b.md", False),
    (["a/**", "!a/b/**"], "a/b/c", False), (["a/**", "!a/b/**"], "a/c", True),
    (["a/**", "!a/b/**", "a/b/keep"], "a/b/keep", True), (["apps/*/infra/**"], "apps/web-platform/infra/x", True),
    (["apps/*/infra/**"], "apps/infra/x", False), (["**"], "anything/at/all", True),
]
for pats, path, want in TABLE:
    check(gh_match(path, pats) == want, "matcher table: %r vs %r expected %s" % (pats, path, want))
for pats in (["a?"], ["a+"], ["[ab]"], ["a\\b"], ["!a/**"]):
    try:
        gh_match("a/x", pats)
        check(False, "matcher accepted an unsupported list %r instead of refusing it" % pats)
    except Unsupported:
        check(True, "")
check(fires("knowledge-base/x", ("ignore", ["knowledge-base/**"])) is False, "paths-ignore: an ignored path must not fire")
check(fires("apps/x", ("ignore", ["knowledge-base/**"])) is True, "paths-ignore: an unignored path must fire")

# ── the real tree ─────────────────────────────────────────────────────────────────────────────────
PRE_FAILS = list(FAILS)
prod = run_checks(WFDIR, CI_ONLY, INV, SCRIPT, full=True)
REAL_FAILS = PRE_FAILS + list(FAILS)

# ── synthetic matrix (harness rows): each mutation must turn the engine RED with a named message ──
def wf(name, on, extra=""):
    import json
    return "name: %s\non: %s\njobs:\n  j:\n    runs-on: ubuntu-latest\n    steps: [{run: echo}]\n%s" % (name, json.dumps(on), extra)


GOOD = {
    "prod.yml": wf("Prod", {"push": {"branches": ["main"], "paths": ["apps/**"]}}),
    "ci.yml": wf("CI", {"push": {"branches": ["main"]}}),
}
GOOD_ROWS = "ci.yml\tchecks only\n"
SYNTH_SCRIPT = SCRIPT


def synth(files, rows, script=None, inv=None):
    d = tempfile.mkdtemp(prefix="mec-parity-")
    try:
        os.makedirs(os.path.join(d, "wf"))
        for n, body in files.items():
            with open(os.path.join(d, "wf", n), "w") as fh:
                fh.write(body)
        with open(os.path.join(d, "ci.tsv"), "w") as fh:
            fh.write(rows)
        run_checks(os.path.join(d, "wf"), os.path.join(d, "ci.tsv"), inv or INV, script or SCRIPT, full=False)
        return "\n".join(FAILS)
    finally:
        shutil.rmtree(d, ignore_errors=True)


def red(label, files, rows, needle, **kw):
    out = synth(files, rows, **kw)
    saved = list(FAILS)
    ok = needle in out
    FAILS.clear()
    FAILS.extend(REAL_FAILS)
    check(ok, "synthetic %s: expected a failure containing %r, got %r" % (label, needle, out[:300]))
    del saved


def green(label, files, rows, **kw):
    out = synth(files, rows, **kw)
    FAILS.clear()
    FAILS.extend(REAL_FAILS)
    check(out == "", "synthetic %s: expected green, got %r" % (label, out[:300]))


green("the good fixture", GOOD, GOOD_ROWS)
red("1 new unfiltered push workflow with no row", dict(GOOD, **{"new.yml": wf("New", {"push": {"branches": ["main"]}})}), GOOD_ROWS, "add a ci-only row with a reason")
red("2 empty workflows directory", {}, GOOD_ROWS, "no workflows found")
two = dict(GOOD, **{"n1.yml": wf("N1", {"push": {"branches": ["main"]}}), "n2.yml": wf("N2", {"push": {"branches": ["main"]}})})
out = synth(two, GOOD_ROWS)
FAILS.clear(); FAILS.extend(REAL_FAILS)
check(out.count("add a ci-only row") >= 2, "synthetic 3: a second unclassified workflow after a compliant one must be reported too (got %r)" % out[:300])
red("4a workflow_run with no branches and no row", dict(GOOD, **{"wr.yml": wf("WR", {"workflow_run": {"workflows": ["CI"], "types": ["completed"]}})}), GOOD_ROWS, "wr.yml")
red("4b release with no row", dict(GOOD, **{"rel.yml": wf("Rel", {"release": {"types": ["published"]}})}), GOOD_ROWS, "rel.yml fires on release")
red("4c pull_request closed with no row", dict(GOOD, **{"pc.yml": wf("PC", {"pull_request": {"types": ["closed"]}})}), GOOD_ROWS, "pc.yml fires on release or pull_request closed")
red("5 production workflow with its paths filter removed", dict(GOOD, **{"prod.yml": wf("Prod", {"push": {"branches": ["main"]}})}), GOOD_ROWS, "unfiltered trigger")
red("6a widened to knowledge-base", dict(GOOD, **{"prod.yml": wf("Prod", {"push": {"branches": ["main"], "paths": ["apps/**", "knowledge-base/**"]}})}), GOOD_ROWS, "fires workflow prod.yml")
red("6b widened to root markdown", dict(GOOD, **{"prod.yml": wf("Prod", {"push": {"branches": ["main"], "paths": ["*.md"]}})}), GOOD_ROWS, "fires workflow prod.yml")
first_kb = next((p for p in tracked_allowlisted() if p.startswith("knowledge-base/") and os.path.basename(p) not in ("CLAUDE.md",) and not os.path.basename(p).startswith("AGENTS")), None)
if first_kb:
    red("6c trigger naming one specific knowledge-base file", dict(GOOD, **{"prod.yml": wf("Prod", {"push": {"branches": ["main"], "paths": [first_kb]}})}), GOOD_ROWS, "tracked allowlisted file")
red("7a empty reason", GOOD, "ci.yml\t\n", "empty reason")
red("7b row naming a deleted workflow", GOOD, GOOD_ROWS + "gone.yml\ta reason\n", "does not exist")
red("8a chain cycle", dict(GOOD, **{
    "a.yml": wf("A", {"workflow_run": {"workflows": ["B"], "types": ["completed"], "branches": ["main"]}}),
    "b.yml": wf("B", {"workflow_run": {"workflows": ["A"], "types": ["completed"], "branches": ["main"]}})}), GOOD_ROWS, "cycle")
red("8b unresolved parent", dict(GOOD, **{"a.yml": wf("A", {"workflow_run": {"workflows": ["Nope"], "types": ["completed"], "branches": ["main"]}})}), GOOD_ROWS, "is not a workflow in this directory")
red("9a unsupported glob character", dict(GOOD, **{"prod.yml": wf("Prod", {"push": {"branches": ["main"], "paths": ["apps/?/x"]}})}), GOOD_ROWS, "extend the matcher")
red("9b paths together with paths-ignore", dict(GOOD, **{"prod.yml": wf("Prod", {"push": {"branches": ["main"], "paths": ["apps/**"], "paths-ignore": ["x/**"]}})}), GOOD_ROWS, "both paths and paths-ignore")
red("9c unknown trigger key", dict(GOOD, **{"u.yml": wf("U", {"registry_package": {}})}), GOOD_ROWS, "unknown trigger key")
red("10 second workflow with its own push.paths and an unfiltered workflow_run arm", dict(GOOD, **{
    "two.yml": wf("Two", {"push": {"branches": ["main"], "paths": ["apps/**"]}, "workflow_run": {"workflows": ["CI"], "types": ["completed"], "branches": ["main"]}})}), GOOD_ROWS, "only web-platform-release.yml is deemed gated")
green("must-pass: paths-ignore covering knowledge-base and markdown", dict(GOOD, **{"prod.yml": wf("Prod", {"push": {"branches": ["main"], "paths-ignore": ["knowledge-base/**", "*.md"]}})}), GOOD_ROWS)
green("must-pass: negated glob after a positive one", dict(GOOD, **{"prod.yml": wf("Prod", {"push": {"branches": ["main"], "paths": ["**", "!knowledge-base/**", "!*.md"]}})}), GOOD_ROWS)
green("must-pass: tags-only push is not enumerated", dict(GOOD, **{"t.yml": wf("T", {"push": {"tags": ["v*"]}})}), GOOD_ROWS)
green("must-pass: scalar on form with workflow_dispatch", dict(GOOD, **{"d.yml": "name: D\non: workflow_dispatch\njobs: {}\n"}), GOOD_ROWS)

# harness row: the real script with a widened allowlist must redden the real-tree and witness directions
tmpd = tempfile.mkdtemp(prefix="mec-parity-script-")
try:
    with open(SCRIPT) as fh:
        src = fh.read()
    marker = "# mut:widen"
    if src.count(marker) == 1:
        mut = re.sub(r'\("knowledge-base/"\)(\s+# mut:widen)', r'("knowledge-base/" "apps/")\1', src)
        mut_path = os.path.join(tmpd, "merge-effect-class.sh")
        with open(mut_path, "w") as fh:
            fh.write(mut)
        check(mut != src, "the widen mutation did not land")
        d = tempfile.mkdtemp(prefix="mec-parity-")
        try:
            os.makedirs(os.path.join(d, "wf"))
            with open(os.path.join(d, "wf", "prod.yml"), "w") as fh:
                fh.write(GOOD["prod.yml"])
            run_checks(os.path.join(d, "wf"), os.path.join(d, "ci.tsv"), INV, mut_path, full=False)
            out = "\n".join(FAILS)
        finally:
            shutil.rmtree(d, ignore_errors=True)
        FAILS.clear(); FAILS.extend(REAL_FAILS)
        check("fires workflow prod.yml" in out or "reads safe" in out or "disagree" in out,
              "a script with a widened allowlist must redden the parity test (got %r)" % out[:300])
    else:
        check(False, "the script must carry exactly one '# mut:widen' marker")
finally:
    shutil.rmtree(tmpd, ignore_errors=True)

# harness row: dropping the executable P3 or P1 assertion from the invariants test must redden the constant
if os.path.isfile(INV):
    with open(INV) as fh:
        inv_src = fh.read()
    for tag in ("P3", "P1"):
        scratch = tempfile.mkdtemp(prefix="mec-parity-inv-")
        try:
            muted = re.sub(r'^(\s+)fail "%s ' % tag, r'\1: "%s ' % tag, inv_src, flags=re.M)
            check(muted != inv_src, "the %s mutation of the invariants test did not land" % tag)
            ip = os.path.join(scratch, "inv.test.sh")
            with open(ip, "w") as fh:
                fh.write(muted)
            run_checks(WFDIR, CI_ONLY, ip, SCRIPT, full=False)
            out = "\n".join(FAILS)
            FAILS.clear(); FAILS.extend(REAL_FAILS)
            check("executable P3 and P1 assertions" in out, "removing the %s assertion must redden the deemed-gated constant (got %r)" % (tag, out[:200]))
        finally:
            shutil.rmtree(scratch, ignore_errors=True)

for m in REAL_FAILS:
    print("PARITY-FAIL: " + m + "  [rerun: " + RERUN + "]", file=sys.stderr)
for m in FAILS:
    if m not in REAL_FAILS:
        print("PARITY-FAIL: " + m + "  [rerun: " + RERUN + "]", file=sys.stderr)
total_fail = len(set(REAL_FAILS) | set(FAILS))
print("%d checks, %d failed, %d production workflows, %d enumerated" % (CHECKS, total_fail, len(prod), sum(1 for _ in load(WFDIR))))
if CHECKS < 150:
    print("PARITY-FAIL: only %d checks ran (floor 150): the suite is gutted" % CHECKS, file=sys.stderr)
    sys.exit(1)
sys.exit(1 if total_fail else 0)
PYEOF
exit "$R_RC"
