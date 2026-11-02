#!/usr/bin/env bash
# merge-effect-class-parity.test.sh - CI drift defence for merge-effect-class.sh (#10923, ADR-302).
#
# The classifier keeps a static allowlist; this test is what keeps it true. It derives the population of
# workflows that can run on a merge to main from .github/workflows/*.y{,a}ml, closed-world over trigger keys
# (push to main, workflow_run, release, pull_request/_target closed). A workflow in that population is
# `production` unless it has a row WITH A REASON in plugins/soleur/scripts/merge-effect-class.ci-only.tsv.
# A production workflow must be path-gated, and no allowlisted path (the script's own witnesses and every
# tracked file the SCRIPT admits) may fire it.
#
# ci-only MEANING: "not directly gated by the merged file list as a production act" - never "harmless".
#
# Test seams (so the matrix runs without editing .github/workflows/): MEC_WORKFLOWS_DIR, MEC_CI_ONLY_LIST,
# MEC_INVARIANTS_TEST (workflow-run-deploy-invariants.test.sh), MEC_SCRIPT (the script under test) and
# MEC_PYTHON (the interpreter, a seam for the missing-PyYAML row). Needs python3 with PyYAML, as
# ci-concurrency-key.test.sh does; a missing PyYAML fails loudly, never skips.
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
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

import yaml

ROOT, WFDIR, CI_ONLY, INV, SCRIPT, THIS = sys.argv[1:7]
RERUN = "bash " + THIS
MEANING = 'ci-only means "not directly gated by the merged file list as a production act", never "harmless"'
LOADER = getattr(yaml, "CSafeLoader", yaml.SafeLoader)
# The one workflow whose unfiltered workflow_run arm is accepted: web-platform-release.yml runs after every main
# CI run, and its inner path check (jobs.release.with.path_filter / resolve-target) decides whether to deploy.
# The engine models it by its own push.paths; the executable P3 and P1 assertions in
# workflow-run-deploy-invariants.test.sh are what pin that push.paths and the inner filter agree.
DEEMED_GATED = "web-platform-release.yml"
POPULATION_FLOOR = 25
MATRIX_FLOOR = 66
CHECKS = 0
MATRIX_RUNS = 0
MATRIX = []


class Unsupported(Exception):
    pass


def check(fails, cond, msg):
    global CHECKS
    CHECKS += 1
    if not cond:
        fails.append(msg)


def mcheck(cond, msg):
    """A verdict about the engine itself (a synthetic row), kept apart from the per-run failure lists."""
    global CHECKS, MATRIX_RUNS
    CHECKS += 1
    MATRIX_RUNS += 1
    if not cond:
        MATRIX.append(msg)


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


def as_list(v):
    if v is None:
        return []
    return [v] if isinstance(v, str) else list(v)


@functools.lru_cache(maxsize=None)
def compile_glob(p):
    for ch in "?+[\\":
        if ch in p:
            raise Unsupported("glob %r uses %r: extend the matcher in %s" % (p, ch, THIS))
    out = ""
    i = 0
    while i < len(p):
        if p.startswith("**/", i):
            out += "(?:.*/)?" if i == 0 or p[i - 1] == "/" else ".*/"
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
    pats = list(pats)
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
    # YAML 1.1 parses the bare key `on` as the boolean True.
    on = d.get(True, d.get("on")) if isinstance(d, dict) else None
    if isinstance(on, str):
        return {on: None}
    if isinstance(on, list):
        return {k: None for k in on}
    return on if isinstance(on, dict) else {}


def branch_ok(cfg):
    if not isinstance(cfg, dict) or "branches" not in cfg:
        return True
    return any(compile_glob(x).match("main") for x in as_list(cfg["branches"]) if not x.startswith("!"))


_LOAD = {}


def load(wfdir):
    names = sorted(f for f in os.listdir(wfdir) if f.endswith((".yml", ".yaml"))) if os.path.isdir(wfdir) else []
    key = (os.path.abspath(wfdir), tuple((f, os.stat(os.path.join(wfdir, f)).st_mtime_ns) for f in names))
    if key in _LOAD:
        return _LOAD[key]
    wfs = {}
    for f in names:
        with open(os.path.join(wfdir, f)) as fh:
            d = yaml.load(fh, Loader=LOADER)
        wfs[f] = {"file": f, "name": (d or {}).get("name", f), "on": norm_on(d)}
    _LOAD[key] = wfs
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
        return [("paths", as_list(cfg["paths"]))]
    if "paths-ignore" in cfg:
        return [("ignore", as_list(cfg["paths-ignore"]))]
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


_RUN = {}


def run_script(script, args, stdin=None):
    key = (script, tuple(args), stdin)
    if key not in _RUN:
        r = subprocess.run(["bash", script] + args, input=stdin, capture_output=True)
        _RUN[key] = (r.returncode, r.stdout.decode("utf-8", "replace").strip())
    return _RUN[key]


_TREE = {}


def tracked_allowed(script):
    """Tracked files the SCRIPT admits as safe: the script is the oracle, so no second copy of the rule."""
    if script not in _TREE:
        env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        out = subprocess.run(["git", "-C", ROOT, "ls-files", "-z"], capture_output=True, check=True, env=env).stdout
        paths = [p.decode("utf-8", "surrogateescape") for p in out.split(b"\0") if p]
        clean = [p for p in paths if re.search(r"[\x00-\x1f\x7f\\\"\n]", p) is None]
        data = ("\n".join(clean) + "\n").encode("utf-8", "surrogateescape")
        rc, out = run_script(script, ["--filter-allowed"], data)
        _TREE[script] = out.split("\n") if rc == 0 and out else []
    return _TREE[script]


def run_checks(wfdir, ci_only_path, inv_path, script, full=True, gate_only=False):
    """Run the engine over one workflows directory; return the list of failure messages."""
    fails = []
    wfs = load(wfdir)
    check(fails, len(wfs) > 0, "no workflows found in %s: an empty workflows directory is RED (population floor)" % wfdir)
    ci = {}
    for name, reason in read_ci_only(ci_only_path):
        check(fails, reason.strip() != "", "ci-only row %r has an empty reason: give it a reason (%s)" % (name, MEANING))
        check(fails, name not in ci, "ci-only row %r is listed twice" % name)
        ci[name] = reason

    by_name = {}
    for f, w in wfs.items():
        check(fails, w["name"] not in by_name,
              "workflow name %r is used by %s and %s: workflow_run parents resolve by name" % (w["name"], by_name.get(w["name"]), f))
        by_name.setdefault(w["name"], f)

    # Population, closed-world over trigger keys.
    pop = {}
    for f, w in wfs.items():
        arms = {}
        for key, cfg in w["on"].items():
            if key in INERT:
                continue
            if key not in POP_KEYS:
                check(fails, False, "%s: unknown trigger key %r: classify it or extend the inert list in %s" % (f, key, THIS))
                continue
            try:
                if key == "push":
                    sh = push_shapes(cfg)
                    if sh is not None:
                        arms["push"] = sh
                elif key == "workflow_run":
                    parents = as_list(cfg.get("workflows") if isinstance(cfg, dict) else None)
                    check(fails, bool(parents), "%s: workflow_run without a workflows list cannot be resolved" % f)
                    if branch_ok(cfg):
                        arms["workflow_run"] = parents
                elif key == "release":
                    arms["release"] = True
                else:
                    if "closed" in as_list(cfg.get("types") if isinstance(cfg, dict) else None):
                        arms["prclosed"] = True
            except Unsupported as e:
                check(fails, False, "%s: %s" % (f, e))
        if arms:
            pop[f] = arms
    check(fails, not full or len(pop) >= POPULATION_FLOOR,
          "population floor: only %d workflows enumerated (expected at least %d); the enumeration is gutted" % (len(pop), POPULATION_FLOOR))

    for name in ci:
        check(fails, name in wfs, "ci-only row %r names a workflow that does not exist: remove this row" % name)
        if name in wfs:
            check(fails, name in pop, "ci-only row %r names a workflow that is no longer enumerated (it has no merge-time trigger): remove this row" % name)

    def resolve(f, stack):
        """Effective merge-time shapes of workflow file f from its push arm and its workflow_run parents."""
        if f in stack:
            raise Unsupported("workflow_run chain cycle through %s" % f)
        arms = pop.get(f, {})
        shapes = list(arms.get("push", []))
        for parent in arms.get("workflow_run", []):
            if parent not in by_name:
                raise Unsupported("%s: workflow_run parent %r is not a workflow in this directory" % (f, parent))
            parr = pop.get(by_name[parent], {})
            if "push" in parr or "workflow_run" in parr:
                shapes += resolve(by_name[parent], stack + [f])
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
        hint = ("add a path filter that cannot fire from knowledge-base/** or root *.md (paths-ignore: ['knowledge-base/**', '*.md'], "
                "or a positive paths: list) if this workflow deploys or applies; add a ci-only row (%s<TAB><reason>) only if it is not "
                "gated by the merged file list as a production act (%s)" % (f, MEANING))
        if "release" in arms or "prclosed" in arms:
            check(fails, False, "%s fires on release or pull_request closed and has no ci-only row: %s" % (f, hint))
            continue
        try:
            shapes = resolve(f, [])
        except Unsupported as e:
            check(fails, False, "%s: %s" % (f, e))
            continue
        if any(k == "all" for k, _ in shapes):
            own_paths = [s for s in arms.get("push", []) if s[0] == "paths"]
            if f == DEEMED_GATED and own_paths:
                check(fails, re.search(r'^\s+fail "P3 ', inv_text, re.M) is not None
                      and re.search(r'^\s+fail "P1 ', inv_text, re.M) is not None,
                      "%s is deemed gated by its own push.paths only while %s keeps the executable P3 and P1 assertions "
                      "(a commented-out fail line does not count)" % (f, os.path.basename(inv_path)))
                shapes = own_paths
            elif own_paths:
                check(fails, False, "%s has its own push.paths and an unfiltered workflow_run arm: only %s is deemed gated. %s" % (f, DEEMED_GATED, hint))
                continue
            else:
                check(fails, False, "%s is a production workflow with an unfiltered trigger: %s" % (f, hint))
                continue
        prod[f] = shapes
    if gate_only:
        return fails

    # The property: no witness and no tracked file the script admits may fire a production workflow.
    rc, wout = run_script(script, ["--print-witnesses"])
    witnesses = [w for w in wout.split("\n") if w] if rc == 0 else []
    check(fails, rc == 0 and len(witnesses) >= 2, "--print-witnesses failed or printed fewer than two witnesses (rc=%s)" % rc)
    tree = tracked_allowed(script)
    check(fails, len(tree) > 0, "the script admitted no tracked file (oracle failure): the real-tree sweep would be vacuous")
    for f, shapes in prod.items():
        try:
            for w in witnesses:
                check(fails, not any(fires(w, s) for s in shapes),
                      "allowlist entry %s fires workflow %s: remove the entry from ALLOW_PREFIXES/ALLOW_ROOT_EXT in "
                      "merge-effect-class.sh or narrow that workflow's paths" % (w, f))
            hits = [p for p in tree if any(fires(p, s) for s in shapes)]
            check(fails, not hits, "%d tracked file(s) the script reads as safe fire workflow %s (first: %s): narrow the workflow's "
                  "paths or shrink the allowlist" % (len(hits), f, hits[0] if hits else ""))
        except Unsupported as e:
            check(fails, False, "%s: %s" % (f, e))
    if full and tree:
        rc, out = run_script(script, ["--files-from", "-"], ("\n".join(tree) + "\n").encode("utf-8", "surrogateescape"))
        check(fails, rc == 0 and out == "not-production-effecting",
              "the script rejects a tracked file it admitted (rc=%s out=%s): --filter-allowed and --files-from disagree" % (rc, out))
    return fails


# ── matcher unit table, pinned to GitHub's documented behaviour ───────────────────────────────────
TABLE = [
    (["a/**"], "a/x", True), (["a/**"], "a", False), (["a/**/b"], "a/b", True), (["a/**/b"], "a/x/y/b", True),
    (["**/x"], "x", True), (["**/x"], "a/b/x", True), (["*.md"], "a.md", True), (["*.md"], "a/b.md", False),
    (["a/**", "!a/b/**"], "a/b/c", False), (["a/**", "!a/b/**"], "a/c", True),
    (["a/**", "!a/b/**", "a/b/keep"], "a/b/keep", True), (["apps/*/infra/**"], "apps/web-platform/infra/x", True),
    (["apps/*/infra/**"], "apps/infra/x", False), (["**"], "anything/at/all", True), (["a**/b"], "axy/b", True),
]
for pats, path, want in TABLE:
    mcheck(gh_match(path, pats) == want, "matcher table: %r vs %r expected %s" % (pats, path, want))
for pats in (["a?"], ["a+"], ["[ab]"], ["a\\b"], ["!a/**"]):
    try:
        gh_match("a/x", pats)
        mcheck(False, "matcher accepted an unsupported list %r instead of refusing it" % pats)
    except Unsupported:
        mcheck(True, "")
mcheck(fires("knowledge-base/x", ("ignore", ["knowledge-base/**"])) is False, "paths-ignore: an ignored path must not fire")
mcheck(fires("apps/x", ("ignore", ["knowledge-base/**"])) is True, "paths-ignore: an unignored path must fire")

# ── the real tree ─────────────────────────────────────────────────────────────────────────────────
REAL = run_checks(WFDIR, CI_ONLY, INV, SCRIPT, full=True)


# ── synthetic matrix: each mutation must turn the engine RED with a named message ─────────────────
def wf(name, on):
    return "name: %s\non: %s\njobs:\n  j:\n    runs-on: ubuntu-latest\n    steps: [{run: echo}]\n" % (name, json.dumps(on))


GOOD = {
    "prod.yml": wf("Prod", {"push": {"branches": ["main"], "paths": ["apps/**"]}}),
    "ci.yml": wf("CI", {"push": {"branches": ["main"]}}),
}
GOOD_ROWS = "ci.yml\tchecks only\n"


def synth(files, rows, script=None, inv=None, full=False):
    d = tempfile.mkdtemp(prefix="mec-parity-")
    try:
        os.makedirs(os.path.join(d, "wf"))
        for n, body in files.items():
            with open(os.path.join(d, "wf", n), "w") as fh:
                fh.write(body)
        with open(os.path.join(d, "ci.tsv"), "w") as fh:
            fh.write(rows)
        return "\n".join(run_checks(os.path.join(d, "wf"), os.path.join(d, "ci.tsv"), inv or INV, script or SCRIPT, full=full))
    finally:
        shutil.rmtree(d, ignore_errors=True)


def red(label, files, rows, needle, **kw):
    out = synth(files, rows, **kw)
    mcheck(needle in out, "synthetic %s: expected a failure containing %r, got %r" % (label, needle, out[:300]))


def green(label, files, rows, **kw):
    out = synth(files, rows, **kw)
    mcheck(out == "", "synthetic %s: expected green, got %r" % (label, out[:300]))


green("the good fixture", GOOD, GOOD_ROWS)
red("0 a full run below the population floor", GOOD, GOOD_ROWS, "population floor", full=True)
red("1 new unfiltered push workflow with no row", dict(GOOD, **{"new.yml": wf("New", {"push": {"branches": ["main"]}})}), GOOD_ROWS, "unfiltered trigger")
red("2 empty workflows directory", {}, GOOD_ROWS, "no workflows found")
out = synth(dict(GOOD, **{"n1.yml": wf("N1", {"push": {"branches": ["main"]}}), "n2.yml": wf("N2", {"push": {"branches": ["main"]}})}), GOOD_ROWS)
mcheck("n1.yml" in out and "n2.yml" in out, "synthetic 3: a second unclassified workflow after a compliant one must be reported too (got %r)" % out[:300])
red("4a workflow_run with no branches and no row", dict(GOOD, **{"wr.yml": wf("WR", {"workflow_run": {"workflows": ["CI"], "types": ["completed"]}})}), GOOD_ROWS, "wr.yml")
red("4b release with no row", dict(GOOD, **{"rel.yml": wf("Rel", {"release": {"types": ["published"]}})}), GOOD_ROWS, "rel.yml fires on release")
red("4c pull_request closed with no row", dict(GOOD, **{"pc.yml": wf("PC", {"pull_request": {"types": ["closed"]}})}), GOOD_ROWS, "pc.yml fires on release or pull_request closed")
red("5 production workflow with its paths filter removed", dict(GOOD, **{"prod.yml": wf("Prod", {"push": {"branches": ["main"]}})}), GOOD_ROWS, "unfiltered trigger")
red("6a widened to knowledge-base", dict(GOOD, **{"prod.yml": wf("Prod", {"push": {"branches": ["main"], "paths": ["apps/**", "knowledge-base/**"]}})}), GOOD_ROWS, "fires workflow prod.yml")
red("6b widened to root markdown", dict(GOOD, **{"prod.yml": wf("Prod", {"push": {"branches": ["main"], "paths": ["*.md"]}})}), GOOD_ROWS, "fires workflow prod.yml")
first_kb = next((p for p in tracked_allowed(SCRIPT) if p.startswith("knowledge-base/")), None)
mcheck(first_kb is not None, "the script admitted no tracked knowledge-base file: row 6c cannot run")
if first_kb:
    red("6c trigger naming one specific knowledge-base file", dict(GOOD, **{"prod.yml": wf("Prod", {"push": {"branches": ["main"], "paths": [first_kb]}})}), GOOD_ROWS, "fire workflow prod.yml")
red("7a empty reason", GOOD, "ci.yml\t\n", "empty reason")
red("7b row naming a deleted workflow", GOOD, GOOD_ROWS + "gone.yml\ta reason\n", "does not exist")
red("7c duplicate row", GOOD, GOOD_ROWS + GOOD_ROWS, "listed twice")
red("8a chain cycle", dict(GOOD, **{
    "a.yml": wf("A", {"workflow_run": {"workflows": ["B"], "types": ["completed"], "branches": ["main"]}}),
    "b.yml": wf("B", {"workflow_run": {"workflows": ["A"], "types": ["completed"], "branches": ["main"]}})}), GOOD_ROWS, "cycle")
red("8b unresolved parent", dict(GOOD, **{"a.yml": wf("A", {"workflow_run": {"workflows": ["Nope"], "types": ["completed"], "branches": ["main"]}})}), GOOD_ROWS, "is not a workflow in this directory")
red("8c workflow_run without a workflows list", dict(GOOD, **{"a.yml": wf("A", {"workflow_run": {"types": ["completed"], "branches": ["main"]}})}), GOOD_ROWS, "without a workflows list")
red("8d duplicate workflow names", dict(GOOD, **{"dup.yml": wf("Prod", {"push": {"branches": ["main"], "paths": ["apps/**"]}})}), GOOD_ROWS, "is used by")
red("9a unsupported glob character", dict(GOOD, **{"prod.yml": wf("Prod", {"push": {"branches": ["main"], "paths": ["apps/?/x"]}})}), GOOD_ROWS, "extend the matcher")
red("9b paths together with paths-ignore", dict(GOOD, **{"prod.yml": wf("Prod", {"push": {"branches": ["main"], "paths": ["apps/**"], "paths-ignore": ["x/**"]}})}), GOOD_ROWS, "both paths and paths-ignore")
red("9c unknown trigger key", dict(GOOD, **{"u.yml": wf("U", {"registry_package": {}})}), GOOD_ROWS, "unknown trigger key")
red("9d a .yaml workflow is enumerated", dict(GOOD, **{"new.yaml": wf("NewY", {"push": {"branches": ["main"]}})}), GOOD_ROWS, "new.yaml")
red("9e scalar paths value is one glob, not characters", dict(GOOD, **{"prod.yml": wf("Prod", {"push": {"branches": ["main"], "paths": "knowledge-base/**"}})}), GOOD_ROWS, "fires workflow prod.yml")
red("9f a ci-only row for a workflow with no merge-time trigger", dict(GOOD, **{"s.yml": wf("S", {"schedule": [{"cron": "0 0 * * *"}]})}), GOOD_ROWS + "s.yml\tnot a merge trigger\n", "no longer enumerated")
red("9g scalar paths naming one witness", dict(GOOD, **{"prod.yml": wf("Prod", {"push": {"branches": ["main"], "paths": "knowledge-base/witness/deep.md"}})}), GOOD_ROWS, "fires workflow prod.yml")
red("10 a second workflow with its own push.paths and an unfiltered workflow_run arm", dict(GOOD, **{
    "two.yml": wf("Two", {"push": {"branches": ["main"], "paths": ["apps/**"]}, "workflow_run": {"workflows": ["CI"], "types": ["completed"], "branches": ["main"]}})}), GOOD_ROWS, "only web-platform-release.yml is deemed gated")
green("must-pass: paths-ignore covering knowledge-base and markdown", dict(GOOD, **{"prod.yml": wf("Prod", {"push": {"branches": ["main"], "paths-ignore": ["knowledge-base/**", "*.md"]}})}), GOOD_ROWS)
green("must-pass: negated glob after a positive one", dict(GOOD, **{"prod.yml": wf("Prod", {"push": {"branches": ["main"], "paths": ["**", "!knowledge-base/**", "!*.md"]}})}), GOOD_ROWS)
green("must-pass: a push to a branch other than main is not enumerated", dict(GOOD, **{"dev.yml": wf("Dev", {"push": {"branches": ["develop"]}})}), GOOD_ROWS)
green("must-pass: a workflow_run restricted to another branch is not enumerated", dict(GOOD, **{"dr.yml": wf("DR", {"workflow_run": {"workflows": ["CI"], "types": ["completed"], "branches": ["develop"]}})}), GOOD_ROWS)
green("must-pass: tags-only push is not enumerated", dict(GOOD, **{"t.yml": wf("T", {"push": {"tags": ["v*"]}})}), GOOD_ROWS)
green("must-pass: scalar on form with workflow_dispatch", dict(GOOD, **{"d.yml": "name: D\non: workflow_dispatch\njobs: {}\n"}), GOOD_ROWS)

# harness rows run against scratch copies
scratch = tempfile.mkdtemp(prefix="mec-parity-script-")
try:
    with open(SCRIPT) as fh:
        src = fh.read()
    mcheck(len(re.findall(r"# mut:widen$", src, re.M)) == 1, "the script must carry exactly one '# mut:widen' marker")
    mut = re.sub(r'\("knowledge-base/"\)(\s+# mut:widen)', r'("knowledge-base/" "apps/")\1', src)
    mcheck(mut != src, "the widen mutation did not land")
    mut_path = os.path.join(scratch, "merge-effect-class.sh")
    with open(mut_path, "w") as fh:
        fh.write(mut)
    red("harness: a script with a widened allowlist", dict(GOOD), GOOD_ROWS, "fires workflow prod.yml", script=mut_path)

    # stub scripts: each oracle failure the engine claims to notice must turn it red
    def stub(name, body):
        path = os.path.join(scratch, name)
        with open(path, "w") as fh:
            fh.write("#!/bin/sh\n" + body)
        return path
    two = "printf 'knowledge-base/witness/deep.md\\nWITNESS.md\\n'"
    red("harness: a script printing one witness", dict(GOOD), GOOD_ROWS, "fewer than two witnesses",
        script=stub("one-witness.sh", 'case "$1" in --print-witnesses) echo WITNESS.md ;; --filter-allowed) cat >/dev/null; echo knowledge-base/a.md ;; esac\n'))
    red("harness: a script whose filter admits nothing", dict(GOOD), GOOD_ROWS, "admitted no tracked file",
        script=stub("empty-filter.sh", 'case "$1" in --print-witnesses) %s ;; --filter-allowed) cat >/dev/null ;; esac\n' % two))
    red("harness: --filter-allowed and --files-from disagree", dict(GOOD), GOOD_ROWS, "rejects a tracked file it admitted",
        script=stub("disagree.sh", 'case "$1" in --print-witnesses) %s ;; --filter-allowed) cat >/dev/null; echo knowledge-base/a.md ;; --files-from) cat >/dev/null; echo production-effecting; exit 1 ;; esac\n' % two), full=True)

    # dropping the executable P3 or P1 assertion from the invariants test must redden the deemed-gated constant
    if os.path.isfile(INV):
        with open(INV) as fh:
            inv_src = fh.read()
        for tag in ("P3", "P1"):
            muted = re.sub(r'^(\s+)fail "%s ' % tag, r'\1: "%s ' % tag, inv_src, flags=re.M)
            mcheck(muted != inv_src, "the %s mutation of the invariants test did not land" % tag)
            ip = os.path.join(scratch, "inv-%s.test.sh" % tag)
            with open(ip, "w") as fh:
                fh.write(muted)
            out = "\n".join(run_checks(WFDIR, CI_ONLY, ip, SCRIPT, full=False, gate_only=True))
            mcheck("executable P3 and P1 assertions" in out, "removing the %s assertion must redden the deemed-gated constant (got %r)" % (tag, out[:200]))
finally:
    shutil.rmtree(scratch, ignore_errors=True)

mcheck(MATRIX_RUNS >= MATRIX_FLOOR, "only %d matrix rows ran (floor %d): the synthetic matrix is gutted" % (MATRIX_RUNS, MATRIX_FLOOR))

for m in REAL + MATRIX:
    print("PARITY-FAIL: " + m, file=sys.stderr)
total_fail = len(REAL) + len(MATRIX)
if total_fail:
    print("rerun: " + RERUN, file=sys.stderr)
print("%d checks, %d failed, %d matrix rows, %d workflow files" % (CHECKS, total_fail, MATRIX_RUNS, len(load(WFDIR))))
sys.exit(1 if total_fail else 0)
PYEOF
exit "$R_RC"
