#!/usr/bin/env bash
# affected-prepass-bench.sh — selection-identity and CPU bench for the affected pre-pass (#9307).
#
# PURPOSE. The pre-pass (`test-all.sh --print-selection`) decides which suites a diff selects.
# Any change to its derive must leave that decision BYTE-IDENTICAL; a cheaper walk that changes
# selection is a regression, not an optimisation. This tool runs the same probe against a BASE
# revision and a HEAD (a revision or the working tree), compares the two AFFECTED_SELECTED streams
# row by row, and times both sides interleaved so they see the same load.
#
# OPERATOR-ONLY. It checks out trusted revisions of this repository into a scratch worktree and
# runs the runner found there; it is not a CI gate. A full run is about 35 CPU-minutes and prints nothing
# per probe until its repeats finish, so run it in the background (`--runs 1` for a quick check).
#
# Usage:
#   affected-prepass-bench.sh [--base <rev>] [--head <rev>] [--probe <a,b,...>] [--runs N]
#                             [--base-runner <path>] [--head-runner <path>]
#   affected-prepass-bench.sh --compare-only <base-stream> <head-stream> [--added <label,label>]
#
#   --base <rev>        default: merge-base of HEAD and origin/main. After the change under test
#                       merges that equals HEAD and the run exits 3 asking for an explicit --base.
#   --head <rev>        default: the working tree.
#   --probe <paths>     comma-separated diff paths to select against; repeatable. Default: two
#                       probes, README.md and a multi-path probe that selects edge suites (a script and a legal doc).
#   --runs N            timing repeats per side, interleaved base/head/base/head (head default 5,
#                       base default 2; N overrides the head count and caps base at N).
#   --base-runner / --head-runner <path>
#                       run that script instead of a worktree's scripts/test-all.sh (the suite
#                       drives fake runners through the full dispatch path with these).
#   --compare-only a b  pure compare of two saved streams; runs nothing.
#   --added <labels>    labels the head stream legitimately adds over the base (registrations the
#                       change under test introduces). Default in a full run, per probe: the difference of the
#                       two sides' `--enumerate-commands --paths=<probe> all` label sets.
#   --leaf-files <paths>
#                       DECLARED-DELTA mode (A5, ADR-242 decision 18): the head is allowed to LOSE edges, and only
#                       the edges that exist solely because a leaf file's text merely NAMES them. Every row must
#                       keep label, class and selected bit; head edges must be a subset of base edges; the removed
#                       set must EQUAL the set this tool's OWN walker computes (grep plus source-follow over the
#                       suite argv and the leaf files, never the runner's derive and never a runner-produced
#                       closure dump); every real source/import target of a leaf file must survive in every row that
#                       had it (population floor: at least one); every row whose base edges include a leaf file must
#                       lose at least one edge (a neutralised rule must not certify); rows that do not reach a leaf
#                       are byte-identical. With `--compare-only` also pass `--cmds <SUITE_COMMAND stream>` and
#                       `--root <dir>` (the tree the walker reads). Exclusive with --added-edges.
#   --max-unexplained N (leaf mode, default 0) per row, how many REMOVED edges the walker does not explain may be
#                       tolerated. The walker is an independent over-approximation of what the derive follows, so it
#                       cannot reproduce every dropped edge; each such edge is a possible lost real dependency (the
#                       recorder's check mode is the behavioural cover). The count per row and the total are always
#                       printed; a row above N fails. Rows where the walker EXPECTS a removal the head did not make
#                       (a neutralised rule) always fail.
#   --added-edges <paths>
#                       paths whose anchored edge (`^path`) the head rows may carry over the base rows,
#                       because the change under test ADDED those files (a suite whose closure reaches
#                       the runner sees the runner's text, which now names the new registration's file).
#                       Default in a full run: the files added between base and head (`git diff
#                       --diff-filter=A`). They are removed from the head row before the byte compare.
#
# Exit: 0 identical, 1 differs (or a side failed), 2 usage, 3 base and head are the same tree.
#
# IDENTITY CONTRACT. Every row whose label exists in the base stream must appear byte-for-byte in
# the head stream, in the same order (after removing the declared added-file edges, whose row count is
# printed). Known limits: only registrations classified under the chosen probes are compared (a relevance-gated
# registration the probe declines never derives); each side derives over its own tree; identity is checked
# on ONE bash, so head-on-5.3 versus base-on-3.2 is argued by the derive suite, not measured here. Rows the head adds must equal the added-label list. The head
# AFFECTED_SUMMARY must equal the base summary adjusted by the added rows. Anti-vacuity: both sides
# exit 0, each stream ends in an AFFECTED_SUMMARY with fallback=none whose of= equals its row
# count, and the child runs under `env -u CI -u SOLEUR_TEST_FORCE_ALL` (either makes every
# selected bit 1, which would make two broken streams agree).

set -uo pipefail

BASE_REV=""
HEAD_REV=""
RUNS=""
BASE_RUNNER=""
HEAD_RUNNER=""
COMPARE_A=""
COMPARE_B=""
ADDED=""
ADDED_SET=0
ADDED_EDGES=""
ADDED_EDGES_SET=0
LEAF_FILES=""
MAX_UNEXPLAINED="0"
CMDS_FILE=""
ROOT_DIR=""
PROBES=()

die_usage() { echo "affected-prepass-bench: $*" >&2; exit 2; }

while (( $# > 0 )); do
  case "$1" in
    --base) [[ $# -ge 2 ]] || die_usage "--base needs a revision"; BASE_REV="$2"; shift 2 ;;
    --head) [[ $# -ge 2 ]] || die_usage "--head needs a revision"; HEAD_REV="$2"; shift 2 ;;
    --probe) [[ $# -ge 2 ]] || die_usage "--probe needs a path list"; PROBES+=("$2"); shift 2 ;;
    --runs) [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || die_usage "--runs needs a positive integer"; RUNS="$2"; shift 2 ;;
    --base-runner) [[ $# -ge 2 ]] || die_usage "--base-runner needs a path"; BASE_RUNNER="$2"; shift 2 ;;
    --head-runner) [[ $# -ge 2 ]] || die_usage "--head-runner needs a path"; HEAD_RUNNER="$2"; shift 2 ;;
    --compare-only) [[ $# -ge 3 ]] || die_usage "--compare-only needs two stream files"; COMPARE_A="$2"; COMPARE_B="$3"; shift 3 ;;
    --added) [[ $# -ge 2 ]] || die_usage "--added needs a label list"; ADDED="$2"; ADDED_SET=1; shift 2 ;;
    --added-edges) [[ $# -ge 2 ]] || die_usage "--added-edges needs a path list"; ADDED_EDGES="$2"; ADDED_EDGES_SET=1; shift 2 ;;
    --leaf-files) [[ $# -ge 2 ]] || die_usage "--leaf-files needs a path list"; LEAF_FILES="$2"; shift 2 ;;
    --max-unexplained) [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || die_usage "--max-unexplained needs a non-negative integer"; MAX_UNEXPLAINED="$2"; shift 2 ;;
    --cmds) [[ $# -ge 2 ]] || die_usage "--cmds needs a SUITE_COMMAND stream file"; CMDS_FILE="$2"; shift 2 ;;
    --root) [[ $# -ge 2 ]] || die_usage "--root needs a directory"; ROOT_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^set -uo pipefail/p' "${BASH_SOURCE[0]}" | sed '$d'; exit 0 ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done

# Pure compare of two saved streams: `compare_streams <base> <head> <added labels> <added-file edges>`. Prints a
# verdict (the first differing row, with the edges that differ) and exits 0 identical, 1 differs. Python, not awk:
# byte-exact line handling and a real set type.
compare_streams() {
  BENCH_ADDED="$3" BENCH_ADDED_EDGES="${4-}" BENCH_LEAF_FILES="${LEAF_FILES-}" BENCH_CMDS="${CMDS_FILE-}" \
    BENCH_ROOT="${ROOT_DIR-}" BENCH_PROBE="${PROBES[*]-}" BENCH_MAX_UNEXPLAINED="${MAX_UNEXPLAINED-0}" python3 - "$1" "$2" <<'PY'
import os, re, sys

def read(path):
    with open(path, "rb") as f:
        data = f.read()
    return data.decode("utf-8", "surrogateescape").split("\n")

def parse(lines):
    rows, summary = [], None
    for ln in lines:
        if ln.startswith("AFFECTED_SELECTED\t"):
            rows.append(ln)
        elif ln.startswith("AFFECTED_SUMMARY"):
            summary = ln
    return rows, summary

def fields(summary):
    out = {}
    for tok in summary.split()[1:]:
        k, _, v = tok.partition("=")
        out[k] = v
    return out

LEAF_WALKER = r"""
# ---- leaf mode: the bench's OWN walker. Reads the suite text with grep-shaped regexes; never calls the runner.
MAXDEPTH = 8
TOKEN_RE = re.compile(r'(?<![\w$])(?:\.\.?/)*[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+/?|(?<![\w$/])[A-Za-z0-9_-]+\.(?:sh|py|ts|tsx|mjs|js|json|md|yml|yaml|toml|tsv)\b')
INVOKE_RE = re.compile(r'(?:^|[\s(&|;])(?:source|\.|bash|sh|python3?|node|bun)\s+["\']?[^\s]')
VARPATH_RE = re.compile(r'\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/((?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+)')
SRC_RE = re.compile(r'(?:^|[;&|({\s])(?:source|\.)\s+["\']?([^"\'\s;&|)]+)')
STEM_EXTS = ("sh", "ts", "tsx", "mjs", "js", "py", "rb")

class Walker:
    def __init__(self, root, leaves):
        self.root, self.leaves = root, set(leaves)
        self._text, self._named, self._sourced = {}, {}, {}

    def exists(self, rel):
        return bool(rel) and os.path.exists(os.path.join(self.root, rel))

    def isfile(self, rel):
        return bool(rel) and os.path.isfile(os.path.join(self.root, rel))

    def text(self, rel):
        if rel not in self._text:
            try:
                with open(os.path.join(self.root, rel), "rb") as fh:
                    self._text[rel] = fh.read().decode("utf-8", "replace")
            except OSError:
                self._text[rel] = ""
        return self._text[rel]

    def resolve(self, path, tok):
        tok = tok.strip("\"'`,;:()[]{}<>")
        if not tok or tok.startswith("/") or tok.startswith("-"):
            return None
        for cand in (tok, os.path.join(os.path.dirname(path), tok)):
            n = os.path.normpath(cand)
            if n.startswith("..") or n == ".":
                continue
            if self.exists(n):
                return n
        return None

    def scrub(self, text):
        text = re.sub(r'\$\([^)]*\)', ' ', text)
        return re.sub(r'\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/', ' ', text)

    def named(self, path):
        # What a file's text NAMES, modelled on the three shapes the runner's derive follows and nothing looser:
        # (1) source/import lines, (2) every token containing a `/` or `$` on an invocation line
        # (`source|.|bash|sh|python3?|node|bun <arg>`), (3) `$VAR/path` tokens anywhere in the text.
        if path not in self._named:
            out = set()
            if self.isfile(path):
                text = self.text(path)
                out |= self.sourced(path)
                for ln in text.splitlines():
                    if INVOKE_RE.search(ln):
                        for tok in self.scrub(ln).split():
                            if "/" in tok:
                                r = self.resolve(path, tok)
                                if r and r != path:
                                    out.add(r)
                for m in VARPATH_RE.finditer(text):
                    r = self.resolve(path, m.group(1))
                    if r and r != path:
                        out.add(r)
            self._named[path] = out
        return self._named[path]

    def varmap(self, path):
        # NAME="value" / NAME=value assignments in the file (last assignment wins), for `source "$NAME"`.
        out = {}
        for ln in self.text(path).splitlines():
            m = re.match(r'\s*(?:export\s+|readonly\s+|local\s+|declare\s+-[a-zA-Z]+\s+)*([A-Za-z_][A-Za-z0-9_]*)=(?:"(.*)"|([^\s"\']+))', ln)
            if m:
                out[m.group(1)] = m.group(2) if m.group(2) is not None else m.group(3)
        return out

    def sourced(self, path):
        if path not in self._sourced:
            out = set()
            if self.isfile(path):
                vm = None
                for ln in self.text(path).splitlines():
                    m = SRC_RE.search(ln)
                    if not m:
                        continue
                    arg = m.group(1)
                    vref = re.fullmatch(r'\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?', arg)
                    if vref:
                        vm = vm if vm is not None else self.varmap(path)
                        arg = vm.get(vref.group(1), "")
                    arg = self.scrub(arg).strip().lstrip("/")
                    r = self.resolve(path, arg) if arg else None
                    if r and r != path:
                        out.add(r)
            self._sourced[path] = out
        return self._sourced[path]

    def out_edges(self, path, head):
        if head and path in self.leaves:
            return self.sourced(path)
        return self.named(path) | self.sourced(path)

    def roots(self, argv):
        roots = set()
        suite = None
        for tok in argv:
            r = self.resolve("", tok)
            if r:
                roots.add(r)
                if suite is None and self.isfile(r):
                    suite = r
        if suite:
            d, b = os.path.dirname(suite) or ".", os.path.basename(suite)
            stem = None
            if b.endswith(".test.sh"): stem = b[:-8]
            elif b.endswith((".test.ts", ".test.tsx")): stem = b.rsplit(".test.", 1)[0]
            elif b.endswith(".test.py"): stem = b[:-8]
            elif re.match(r"test[-_].+\.(sh|py)$", b): stem = b[5:].rsplit(".", 1)[0]
            if stem:
                for cd in (d, d + "/lib", "scripts", re.sub(r"/test$", "", d) + "/scripts"):
                    for ext in STEM_EXTS:
                        c = os.path.normpath(os.path.join(cd, stem + "." + ext))
                        if self.isfile(c):
                            roots.add(c)
        return roots

    def reach(self, roots, head):
        seen = set(roots)
        frontier = set(roots)
        for _ in range(MAXDEPTH):
            nxt = set()
            for f in frontier:
                if not self.isfile(f):
                    continue
                for e in self.out_edges(f, head):
                    if e not in seen:
                        seen.add(e)
                        nxt.add(e)
            if not nxt:
                break
            frontier = nxt
        return seen
"""

def edge_key(e):
    return e[1:].rstrip("/") if e.startswith("^") else e.rstrip("/")

def edge_matches(e, q):
    # The bench's own reading of how an edge selects a diff path (anchored dir prefix, anchored file, legacy substring).
    if e.startswith("^"):
        x = e[1:]
        return q.startswith(x) if x.endswith("/") else q == x
    return e in q

def declared_edges(root, label):
    """Edges a label DECLARES (AFFECTED_<LABEL>_PATHS), read from the declarations lib text; the runner re-adds
    these after the derive, so the leaf rule can never remove them."""
    lib = os.path.join(root, "scripts", "lib", "test-affected-paths.sh")
    try:
        text = open(lib, encoding="utf-8", errors="replace").read()
    except OSError:
        return set()
    arrays = {}
    for m in re.finditer(r'^([A-Za-z_][A-Za-z0-9_]*)=\(\n(.*?)^\)\n', text, re.S | re.M):
        arrays[m.group(1)] = m.group(2)
    def expand(name, depth=0):
        out = set()
        for ln in arrays.get(name, "").splitlines():
            ln = ln.split("#", 1)[0].strip()
            ref = re.fullmatch(r'"\$\{([A-Za-z_][A-Za-z0-9_]*)\[@\]\}"', ln)
            if ref and depth < 4:
                out |= expand(ref.group(1), depth + 1)
                continue
            lit = re.fullmatch(r'"([^"]+)"', ln)
            if lit:
                out.add(lit.group(1))
        return out
    name = "AFFECTED_" + re.sub(r"[^A-Z0-9]", "_", label.upper()).lstrip("_") + "_PATHS"
    return expand(name)

def leaf_compare(a_rows, b_rows, a_sum, b_sum, leaves, cmds_path, root, problems):
    exec(LEAF_WALKER, globals())
    if not leaves:
        problems.append("--leaf-files is empty")
        return None
    if not cmds_path or not os.path.isfile(cmds_path) or not root or not os.path.isdir(root):
        problems.append("leaf mode needs --cmds <file> and --root <dir>")
        return None
    probe = [x for x in re.split(r"[,\s]+", os.environ.get("BENCH_PROBE", "")) if x]
    cmds = {}
    for ln in read(cmds_path):
        f = ln.split("\t")
        if f[0] == "SUITE_COMMAND" and len(f) >= 3:
            cmds[f[1]] = f[2:]
    w = Walker(root, leaves)
    leaf_keys = set(leaves)
    retained_targets = set()
    for lf in leaves:
        retained_targets |= w.sourced(lf)
    if len(a_rows) != len(b_rows):
        problems.append("row count differs: base %d head %d" % (len(a_rows), len(b_rows)))
        return None
    n_reach = n_retained_pairs = n_changed = flips = flips_edge = 0
    total_unexplained = rows_unexplained = total_kept = 0
    max_unexplained = int(os.environ.get("BENCH_MAX_UNEXPLAINED", "0") or 0)
    first_bad = None
    for x, y in zip(a_rows, b_rows):
        fx, fy = x.split("\t"), y.split("\t")
        label = fx[1]
        if fx[1] != fy[1] or fx[3] != fy[3]:
            problems.append("row %s: label/class differ (%s vs %s)" % (label, fx[1:4:2], fy[1:4:2]))
            continue
        ex = [e for e in (fx[4].split("|") if len(fx) > 4 else []) if e]
        ey = [e for e in (fy[4].split("|") if len(fy) > 4 else []) if e]
        added = set(ey) - set(ex)
        if added:
            problems.append("row %s: head ADDS edges %s" % (label, sorted(added)[:3]))
            continue
        removed = set(ex) - set(ey)
        # The selected bit may only narrow, and only because a probe-matching base edge was removed.
        if fx[2] != fy[2]:
            hit_base = {e for e in ex if any(edge_matches(e, q) for q in probe)}
            if not (fx[2] == "1" and fy[2] == "0" and fx[3] != "always_on" and probe and hit_base and hit_base <= removed):
                problems.append("row %s: selected bit changed %s -> %s without a removed probe-matching edge" % (label, fx[2], fy[2]))
                continue
            flips += 1
            if fx[3].startswith("edge:"):
                flips_edge += 1
        elif not removed and x != y:
            problems.append("row %s differs without a removed edge" % label)
            continue
        reaches = any(edge_key(e) in leaf_keys for e in ex)
        if not reaches and not removed:
            continue
        roots = w.roots(cmds.get(label, []))
        rb, rh = w.reach(roots, False), w.reach(roots, True)
        decl = {edge_key(d) for d in declared_edges(root, label)}
        expected = {e for e in ex if edge_key(e) in rb and edge_key(e) not in rh and edge_key(e) not in decl}
        if reaches:
            n_reach += 1
        if removed:
            n_changed += 1
        missed = expected - removed          # the head KEPT an edge the walker expects gone (a route the walker misses, or a neutralised rule)
        unexplained = removed - expected     # removed, but the walker believes another path still reaches it
        if missed:
            total_kept += len(missed)
            if len(missed) > max_unexplained:
                if first_bad is None:
                    first_bad = (label, sorted(unexplained)[:4], sorted(missed)[:4])
                problems.append("row %s: head KEPT %d edge(s) the walker expects removed (%s), ceiling %d" % (label, len(missed), sorted(missed)[:2], max_unexplained))
        if unexplained:
            total_unexplained += len(unexplained)
            rows_unexplained += 1
            if len(unexplained) > max_unexplained:
                if first_bad is None:
                    first_bad = (label, sorted(unexplained)[:4], sorted(missed)[:4])
                problems.append("row %s: removed set != walker's expected set (%d unexplained removals, ceiling %d)" % (label, len(unexplained), max_unexplained))
        for t in retained_targets:
            if t in {edge_key(e) for e in ex}:
                n_retained_pairs += 1
                if t not in {edge_key(e) for e in ey}:
                    problems.append("row %s lost the REAL source edge %s of a leaf file" % (label, t))
    # Summary: head == base adjusted by the rows whose selected bit narrowed.
    fa, fb = fields(a_sum or ""), fields(b_sum or "")
    exp = dict(fa)
    if "selected" in fa:
        exp["selected"] = str(int(fa["selected"]) - flips)
    if "edge" in fa:
        exp["edge"] = str(int(fa["edge"]) - flips_edge)
    if exp != fb:
        problems.append("head summary %r != base summary adjusted by %d narrowed row(s) %r" % (fb, flips, exp))
    if first_bad:
        print("  first mismatch: %s | removed-not-expected %s | expected-not-removed %s" % first_bad)
    if n_changed == 0:
        problems.append("population floor: no row lost an edge (a neutralised leaf rule must not certify)")
    if not retained_targets:
        problems.append("population floor: the walker resolved no real source target of the leaf files (nothing to retain-check)")
    elif n_retained_pairs == 0:
        problems.append("population floor: no (row, real source target) pair was checked")
    if total_kept:
        print("  edges kept that the walker expected removed: %d (a neutralised rule keeps hundreds; per-row ceiling %d)" % (total_kept, max_unexplained))
    if total_unexplained:
        print("  unexplained removals: %d edge(s) over %d row(s) (per-row ceiling %d)" % (total_unexplained, rows_unexplained, max_unexplained))
    return (len(a_rows), n_reach, n_changed, n_retained_pairs)

a_path, b_path = sys.argv[1], sys.argv[2]
added = [x for x in os.environ.get("BENCH_ADDED", "").split(",") if x]
allowed_edges = {"^" + x for x in os.environ.get("BENCH_ADDED_EDGES", "").split(",") if x}
a_rows, a_sum = parse(read(a_path))
b_rows, b_sum = parse(read(b_path))
problems = []

def need_summary(name, rows, summ):
    if summ is None:
        problems.append(f"{name}: no AFFECTED_SUMMARY (stream truncated or runner crashed)")
        return None
    f = fields(summ)
    if f.get("fallback") != "none":
        problems.append(f"{name}: degraded run ({summ})")
    if f.get("of") != str(len(rows)):
        problems.append(f"{name}: summary of={f.get('of')} but {len(rows)} AFFECTED_SELECTED rows")
    return f

fa = need_summary("base", a_rows, a_sum)
fb = need_summary("head", b_rows, b_sum)
if not a_rows or not b_rows:
    problems.append("an empty stream cannot be compared (zero rows)")

leaves = [x for x in os.environ.get("BENCH_LEAF_FILES", "").split(",") if x]
if leaves:
    if allowed_edges or added:
        problems.append("--leaf-files is exclusive with --added / --added-edges")
    if not problems:
        res = leaf_compare(a_rows, b_rows, a_sum, b_sum, leaves, os.environ.get("BENCH_CMDS", ""), os.environ.get("BENCH_ROOT", ""), problems)
    if problems:
        for pr in problems[:12]:
            print("DIFFERS: " + pr)
        if len(problems) > 12:
            print("DIFFERS: ... %d more" % (len(problems) - 12))
        sys.exit(1)
    print("EXPLAINED: %d rows compared, %d reach a leaf file, %d lost only walker-explained edges, %d retained real source edges checked"
          % res)
    sys.exit(0)

stripped_rows = 0
if not problems:
    label = lambda r: r.split("\t")[1]
    a_set = {label(r) for r in a_rows}
    b_extra = [r for r in b_rows if label(r) not in a_set]
    b_common = [r for r in b_rows if label(r) in a_set]
    if sorted(label(r) for r in b_extra) != sorted(added):
        problems.append("head adds labels %r, expected %r" % (sorted(label(r) for r in b_extra), sorted(added)))
    if len(b_common) != len(a_rows):
        gone = a_set - {label(r) for r in b_common}
        problems.append("head drops %d base row(s): %s" % (len(gone), ", ".join(sorted(gone)[:5])))

    def strip_allowed(row):
        # Remove the edges that exist only because the change added a file; nothing else is touched.
        global stripped_rows
        if not allowed_edges:
            return row
        f = row.split("\t")
        if len(f) < 5:
            return row
        kept = [e for e in f[4].split("|") if e not in allowed_edges]
        if len(kept) != len([e for e in f[4].split("|")]):
            stripped_rows += 1
        f[4] = "|".join(kept)
        return "\t".join(f)

    diffs = [(x, y) for x, y in zip(a_rows, b_common) if x != strip_allowed(y)]
    if diffs:
        problems.append("%d row(s) differ byte-for-byte" % len(diffs))
        x, y = diffs[0]
        print("  base: " + x[:400].replace("\t", " | "))
        print("  head: " + y[:400].replace("\t", " | "))
        xe, ye = set(x.split("\t")[4].split("|")), set(strip_allowed(y).split("\t")[4].split("|"))
        print("  only in base: %s" % sorted(xe - ye)[:5])
        print("  only in head: %s" % sorted(ye - xe)[:5])
    # Summary arithmetic: head == base adjusted by the added rows.
    exp = dict(fa)
    exp["of"] = str(int(fa["of"]) + len(b_extra))
    sel = [r.split("\t") for r in b_extra if r.split("\t")[2] == "1"]
    exp["selected"] = str(int(fa["selected"]) + len(sel))
    exp["always_on"] = str(int(fa["always_on"]) + sum(1 for f in sel if f[3] == "always_on"))
    exp["edge"] = str(int(fa["edge"]) + sum(1 for f in sel if f[3].startswith("edge:")))
    if exp != fb:
        problems.append("head summary %r != base summary adjusted by the added rows %r" % (fb, exp))

if problems:
    for p in problems:
        print("DIFFERS: " + p)
    sys.exit(1)
print("IDENTICAL: %d base rows byte-for-byte, %d added row(s), %d row(s) carried declared added-file edges"
      % (len(a_rows), len(b_extra), stripped_rows))
PY
}

if [[ -n "$COMPARE_A" ]]; then
  [[ -r "$COMPARE_A" && -r "$COMPARE_B" ]] || die_usage "--compare-only: both files must be readable"
  compare_streams "$COMPARE_A" "$COMPARE_B" "$ADDED" "$ADDED_EDGES"
  exit $?
fi

# ---- full run --------------------------------------------------------------------------------

# Never inherit lefthook's git environment: GIT_DIR beats cwd and beats `git -C`.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_TEMPLATE_DIR GIT_EXEC_PATH

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die_usage "not inside a git work tree"
assert_fixture_dir "$REPO_ROOT"
if (( ${#PROBES[@]} == 0 )); then
  PROBES=("README.md" "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh,docs/legal/cookie-policy.md")
fi
for p in "${PROBES[@]}"; do
  [[ "$p" =~ ^[^[:space:]]+$ ]] || die_usage "--probe must not contain whitespace other than commas: '$p'"
done
HEAD_RUNS="${RUNS:-5}"
BASE_RUNS="${RUNS:-2}"; (( BASE_RUNS > 2 )) && BASE_RUNS=2

SCRATCH="$(mktemp -d "${TMPDIR:-/var/tmp}/prepass-bench.XXXXXXXX")" || exit 2
WT_PATHS=()
cleanup() {
  local w
  for w in ${WT_PATHS[@]+"${WT_PATHS[@]}"}; do
    git -C "$REPO_ROOT" worktree remove --force "$w" >/dev/null 2>&1 || true
  done
  assert_fixture_dir "$SCRATCH"
  rm -rf "$SCRATCH"
}
trap cleanup EXIT
assert_fixture_dir "$SCRATCH"

resolve_rev() {
  git -C "$REPO_ROOT" rev-parse --verify --end-of-options "$1^{commit}" 2>/dev/null
}

# A side is a directory holding scripts/test-all.sh, or a runner path (made absolute: it runs from the repo root).
make_side() {
  local name="$1" rev="$2" runner="$3" dir
  if [[ -n "$runner" ]]; then
    [[ -f "$runner" ]] || die_usage "--${name}-runner: no such file: $runner"
    SIDE_DIR="$REPO_ROOT"
    SIDE_RUNNER="$(cd "$(dirname "$runner")" && pwd)/$(basename "$runner")"
    SIDE_ID="runner:$SIDE_RUNNER"
    return 0
  fi
  if [[ -z "$rev" ]]; then
    SIDE_DIR="$REPO_ROOT"; SIDE_RUNNER="scripts/test-all.sh"; SIDE_ID="tree:$(git -C "$REPO_ROOT" rev-parse HEAD)+worktree"
    return 0
  fi
  local sha; sha="$(resolve_rev "$rev")" || die_usage "cannot resolve revision: $rev"
  dir="$SCRATCH/$name"
  git -C "$REPO_ROOT" worktree add --detach "$dir" "$sha" >/dev/null 2>&1 || die_usage "git worktree add failed for $rev"
  WT_PATHS+=("$dir")
  SIDE_DIR="$dir"; SIDE_RUNNER="scripts/test-all.sh"; SIDE_ID="rev:$sha"
}

if [[ -z "$BASE_REV" && -z "$BASE_RUNNER" ]]; then
  BASE_REV="$(git -C "$REPO_ROOT" merge-base HEAD origin/main 2>/dev/null)" || die_usage "no merge-base with origin/main; pass --base"
fi
make_side base "$BASE_REV" "$BASE_RUNNER"; B_DIR="$SIDE_DIR"; B_RUNNER="$SIDE_RUNNER"; B_ID="$SIDE_ID"
make_side head "$HEAD_REV" "$HEAD_RUNNER"; H_DIR="$SIDE_DIR"; H_RUNNER="$SIDE_RUNNER"; H_ID="$SIDE_ID"

if [[ "$B_ID" == "$H_ID" ]]; then
  echo "affected-prepass-bench: base and head are the same tree ($B_ID); nothing to compare. Pass --base <rev>" >&2
  exit 3
fi
if [[ "$B_ID" == rev:* && "$H_ID" == tree:* ]]; then
  # The head is the working tree: if the base commit IS the current HEAD and the tree is clean the
  # two sides are the same code (the post-merge default). A dirty tree is a real comparison.
  if [[ "${B_ID#rev:}" == "$(git -C "$REPO_ROOT" rev-parse HEAD)" ]] \
     && [[ -z "$(git -C "$REPO_ROOT" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
    echo "affected-prepass-bench: base is the current HEAD and the tree is clean; pass --base <earlier rev>" >&2
    exit 3
  fi
fi

# run_timed <dir> <out> <err> <cmd...> -> "wall user sys rc" on stdout (rusage of the reaped tree).
run_timed() {
  python3 - "$@" <<'PY'
import os, resource, subprocess, sys, time
cwd, out, err = sys.argv[1:4]
cmd = sys.argv[4:]
env = {k: v for k, v in os.environ.items() if k not in ("CI", "SOLEUR_TEST_FORCE_ALL")}
r0 = resource.getrusage(resource.RUSAGE_CHILDREN); t0 = time.monotonic()
with open(out, "wb") as o, open(err, "wb") as e:
    rc = subprocess.run(cmd, cwd=cwd, stdout=o, stderr=e, stdin=subprocess.DEVNULL, env=env).returncode
t1 = time.monotonic(); r1 = resource.getrusage(resource.RUSAGE_CHILDREN)
print("%.1f %.1f %.1f %d" % (t1 - t0, r1.ru_utime - r0.ru_utime, r1.ru_stime - r0.ru_stime, rc))
PY
}

load1() { cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo "?"; }

stats() { # stats <list of numbers> -> "min median"
  printf '%s\n' "$@" | sort -n | awk '{a[NR]=$1} END{ if(NR==0){print "? ?"; exit} m=(NR%2)?a[(NR+1)/2]:(a[NR/2]+a[NR/2+1])/2; printf "%.1f %.1f\n", a[1], m }'
}

# One label per SUITE_COMMAND record (duplicates kept), enumerated against the SAME paths as the probe: a
# relevance-gated registration is declined or not by the named paths, so the label set depends on them.
enum_labels() { # enum_labels <dir> <runner> <probe>
  ( cd "$1" && env -u CI -u SOLEUR_TEST_FORCE_ALL bash "$2" --enumerate-commands "--paths=$3" all 2>/dev/null ) \
    | awk -F'\t' '$1=="SUITE_COMMAND"{print $2}'
}

if (( ADDED_EDGES_SET == 0 )) && [[ "$B_ID" == rev:* ]] && [[ -z "$LEAF_FILES" ]]; then
  _h_rev="${H_ID#rev:}"; [[ "$H_ID" == rev:* ]] || _h_rev="HEAD"
  ADDED_EDGES="$(git -C "$REPO_ROOT" diff -z --diff-filter=A --name-only "${B_ID#rev:}" "$_h_rev" 2>/dev/null | tr '\0' ',')"
  ADDED_EDGES="${ADDED_EDGES%,}"
fi

OVERALL=0
BASH_V="${BASH_VERSION}"
LOCALE="${LC_ALL:-${LANG:-unset}}"

probe_i=0
for probe in "${PROBES[@]}"; do
  probe_i=$((probe_i + 1))
  b_cpu=(); b_wall=(); h_cpu=(); h_wall=()
  load_start="$(load1)"
  n=$HEAD_RUNS; (( BASE_RUNS > n )) && n=$BASE_RUNS
  side_failed=""
  for (( i=1; i<=n; i++ )); do
    if (( i <= BASE_RUNS )); then
      read -r w u s rc < <(run_timed "$B_DIR" "$SCRATCH/b$probe_i.$i.out" "$SCRATCH/b$probe_i.$i.err" bash "$B_RUNNER" --print-selection "--paths=$probe")
      [[ "$rc" == "0" ]] || side_failed="base run $i exited rc=$rc"
      b_wall+=("$w"); b_cpu+=("$(awk -v u="$u" -v s="$s" 'BEGIN{printf "%.1f", u+s}')")
    fi
    if (( i <= HEAD_RUNS )); then
      read -r w u s rc < <(run_timed "$H_DIR" "$SCRATCH/h$probe_i.$i.out" "$SCRATCH/h$probe_i.$i.err" bash "$H_RUNNER" --print-selection "--paths=$probe")
      [[ "$rc" == "0" ]] || side_failed="head run $i exited rc=$rc"
      h_wall+=("$w"); h_cpu+=("$(awk -v u="$u" -v s="$s" 'BEGIN{printf "%.1f", u+s}')")
    fi
  done
  load_end="$(load1)"
  echo "== probe $probe_i: $probe"
  if [[ -n "$side_failed" ]]; then
    echo "DIFFERS: $side_failed (both sides must exit 0)"; OVERALL=1; continue
  fi
  b_lab="$SCRATCH/labels.base.$probe_i"; h_lab="$SCRATCH/labels.head.$probe_i"
  assert_fixture_dir "$b_lab"; assert_fixture_dir "$h_lab"
  enum_labels "$B_DIR" "$B_RUNNER" "$probe" > "$b_lab"
  enum_labels "$H_DIR" "$H_RUNNER" "$probe" > "$h_lab"
  probe_added="$ADDED"
  if (( ADDED_SET == 0 )); then
    probe_added="$(sort -u "$h_lab" | comm -13 <(sort -u "$b_lab") - | paste -sd, -)"
  fi
  if [[ -n "$LEAF_FILES" ]]; then
    CMDS_FILE="$SCRATCH/cmds.head.$probe_i"; ROOT_DIR="$H_DIR"
    ( cd "$H_DIR" && env -u CI -u SOLEUR_TEST_FORCE_ALL bash "$H_RUNNER" --enumerate-commands "--paths=$probe" all 2>/dev/null ) > "$CMDS_FILE"
    probe_added=""
  fi
  verdict="$(compare_streams "$SCRATCH/b$probe_i.1.out" "$SCRATCH/h$probe_i.1.out" "$probe_added" "$ADDED_EDGES")"; vrc=$?
  printf '%s\n' "$verdict"
  (( vrc == 0 )) || OVERALL=1
  # of= counts registrations (records), not distinct labels: cross-check the base summary against the enumeration.
  probe_n="$(wc -l < "$b_lab" | tr -d ' ')"
  base_of="$(sed -n 's/^AFFECTED_SUMMARY .*of=\([0-9][0-9]*\) .*/\1/p' "$SCRATCH/b$probe_i.1.out" | tail -1)"
  [[ "$base_of" == "$probe_n" ]] || { echo "DIFFERS: base summary of=$base_of but --enumerate-commands --paths=$probe lists $probe_n registrations"; OVERALL=1; }
  echo "  base summary: $(grep '^AFFECTED_SUMMARY' "$SCRATCH/b$probe_i.1.out" | tail -1)"
  # Later repeats must equal the first of their own side (determinism), checked with cmp.
  for (( i=2; i<=BASE_RUNS; i++ )); do cmp -s "$SCRATCH/b$probe_i.1.out" "$SCRATCH/b$probe_i.$i.out" || { echo "DIFFERS: base run $i differs from base run 1 (non-deterministic)"; OVERALL=1; }; done
  for (( i=2; i<=HEAD_RUNS; i++ )); do cmp -s "$SCRATCH/h$probe_i.1.out" "$SCRATCH/h$probe_i.$i.out" || { echo "DIFFERS: head run $i differs from head run 1 (non-deterministic)"; OVERALL=1; }; done
  read -r bmin bmed < <(stats "${b_cpu[@]}"); read -r hmin hmed < <(stats "${h_cpu[@]}")
  read -r _ bwmed < <(stats "${b_wall[@]}"); read -r _ hwmed < <(stats "${h_wall[@]}")
  fmed="$(awk -v a="$bmed" -v b="$hmed" 'BEGIN{ if (b>0) printf "%.1f", a/b; else print "?" }')"
  echo "  CPU user+sys  base min/median ${bmin}/${bmed} s   head min/median ${hmin}/${hmed} s   factor (median) ${fmed}x"
  echo "  wall median   base ${bwmed} s   head ${hwmed} s"
  echo "  load1 ${load_start} -> ${load_end}; locale ${LOCALE}; bash ${BASH_V}; runs base=${#b_cpu[@]} head=${#h_cpu[@]}"
  vword="identical"; (( vrc == 0 )) || vword="DIFFERENT"
  echo "  plain: an affected run waited about ${bmed} s of CPU on selection and now waits about ${hmed} s (${fmed}x), selection ${vword}."
done

exit "$OVERALL"
