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
#                             [--leaf-files <a,b> [--max-unexplained N] [--max-kept N] [--cmds <f> --root <dir>]]
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
#                       the edges that exist solely because a leaf file's text merely NAMES them. Per row:
#                         - label and class must be equal; head edges must be a subset of base edges;
#                         - the selected bit may narrow 1 -> 0 only when a base edge matching a --probe path was removed
#                           (a narrowing without one is refused) and never on an always_on row;
#                         - a row whose base edges do NOT reach a leaf file that has outbound edges must be byte-identical
#                           (it may lose nothing: hard failure, no ceiling); the declarations lib names nothing, so a row
#                           that only carries it as an edge does not count as reaching a leaf;
#                         - a row that reaches such a leaf and loses NOTHING while the walker expects removals is a hard
#                           failure, no ceiling (the rule did not apply to that row);
#                         - declared edges (AFFECTED_<LABEL>_PATHS) are never removable, and every real source/import
#                           target of a leaf file must survive in every row that had it (population floor: at least one);
#                         - the removed set must equal the walker's computed set UP TO THE PRINTED CEILINGS. The walker is
#                           this tool's OWN second implementation of the derive's text spec (never the runner, never a
#                           runner-produced closure dump): it computes each suite's closure with the leaf files read in full
#                           and as leaves, and the difference is the expected removal set. The `walker fidelity` line prints
#                           how many edge-classified rows of each stream it reproduces exactly (derived plus declared edges);
#                           on the two probes below that is every row, so the default ceilings are 0 and 0.
#                           scripts/test-affected-derive.test.sh pins the parity of its constants with the runner.
#                       The walker is blind without suite commands: an empty --cmds stream, a compared label with no
#                       SUITE_COMMAND record, or a full run whose `--enumerate-commands` fails or lists nothing is a failure,
#                       never a pass. With `--compare-only` also pass `--cmds <SUITE_COMMAND stream>` and `--root <dir>` (the
#                       tree the walker reads); --cmds, --root and the two ceilings are usage errors (2) without --leaf-files.
#                       Exclusive with --added-edges.
#   --max-unexplained N (leaf mode, default 0) per row, how many REMOVED edges the walker does not expect may be tolerated. Each
#                       is a possible lost real dependency (the recorder's check mode is the behavioural cover).
#   --max-kept N        (leaf mode, default 0) per row, how many edges the walker EXPECTS removed that the head KEPT may be
#                       tolerated (a route the walker lacks, or a leaf rule that did not apply). The two ceilings are separate
#                       because the two directions mean opposite things. Counts per row, totals and a category breakdown are
#                       always printed; the verdict line carries the totals and the ceilings (`EXPLAINED (U unexplained, K
#                       kept, ceilings A/B)`), and the plain-language line says "narrowed only as declared" only when U and K
#                       are both 0.
#
#                       RE-RUNNABLE BASE (the evidence in always-on-audit.md, Round 3): the base is the SAME runner with the leaf
#                       set emptied, so the only difference between the sides is the rule. From the repository root:
#                         B="$(mktemp -d)"; mkdir -p "$B/scripts/lib"
#                         cp scripts/test-all.sh "$B/scripts/"; cp scripts/lib/*.sh "$B/scripts/lib/"
#                         sed -i '/^CLOSURE_LEAF_FILES=(/,/^)/c\CLOSURE_LEAF_FILES=()' "$B/scripts/lib/test-affected-paths.sh"
#                         bash scripts/affected-prepass-bench.sh --base-runner "$B/scripts/test-all.sh" --runs 1 \
#                           --leaf-files scripts/test-all.sh,scripts/lib/test-affected-paths.sh --probe README.md
#                       (the head is the working tree; a second run with `--probe plugins/soleur/test/c4-count-parity.test.sh`
#                       exercises selected-bit narrowing). The runner sources its lib relative to its own path, which is why
#                       the copy carries scripts/lib. Measured with this block on both probes: 0 unexplained, 0 kept,
#                       ceilings 0/0, 35 rows reach a leaf file, 23 lose edges, walker fidelity at 100%.
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
MAX_KEPT="0"
CEILING_SET=0
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
    --max-unexplained) [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || die_usage "--max-unexplained needs a non-negative integer"; MAX_UNEXPLAINED="$2"; CEILING_SET=1; shift 2 ;;
    --max-kept) [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || die_usage "--max-kept needs a non-negative integer"; MAX_KEPT="$2"; CEILING_SET=1; shift 2 ;;
    --cmds) [[ $# -ge 2 ]] || die_usage "--cmds needs a SUITE_COMMAND stream file"; CMDS_FILE="$2"; shift 2 ;;
    --root) [[ $# -ge 2 ]] || die_usage "--root needs a directory"; ROOT_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^set -uo pipefail/p' "${BASH_SOURCE[0]}" | sed '$d'; exit 0 ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done
# These four only mean something in leaf mode; accepted and ignored they would read as a check that ran.
if [[ -z "$LEAF_FILES" ]] && { [[ -n "$CMDS_FILE" || -n "$ROOT_DIR" ]] || (( CEILING_SET == 1 )); }; then
  die_usage "--cmds, --root, --max-unexplained and --max-kept need --leaf-files"
fi

# Pure compare of two saved streams: `compare_streams <base> <head> <added labels> <added-file edges>`. Prints a
# verdict (the first differing row, with the edges that differ) and exits 0 identical, 1 differs. Python, not awk:
# byte-exact line handling and a real set type.
compare_streams() {
  BENCH_ADDED="$3" BENCH_ADDED_EDGES="${4-}" BENCH_LEAF_FILES="${LEAF_FILES-}" BENCH_CMDS="${CMDS_FILE-}" \
    BENCH_ROOT="${ROOT_DIR-}" BENCH_PROBE="${PROBES[*]-}" BENCH_MAX_UNEXPLAINED="${MAX_UNEXPLAINED-0}" BENCH_MAX_KEPT="${MAX_KEPT-0}" python3 - "$1" "$2" <<'PY'
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
# ---- leaf mode: the bench's OWN walker. A second implementation of the derive's TEXT SPEC (the three extraction passes, the
# variable map, the token rules and the bounded closure, as documented in test-all.sh), written in Python and never calling the
# runner. It computes the closure of a suite twice, once reading every file in full and once treating the leaf files as leaves;
# the difference is the edge set the leaf rule is EXPECTED to remove. Running it on a stream's base side must reproduce the base
# rows' derived edges; anything it cannot reproduce is printed per category, not hidden.
MAXDEPTH = 8
GREP1 = re.compile(r'(^|\s)(source|\.)\s+|from\s+["\']|require\(|import\s+["\']|import\(|load\s+|^\s*(import|from)\s+[a-zA-Z0-9_.]', re.A)
SED1 = [
    (re.compile(r'^.*(source|\.)\s+[\'"]?(\$\(dirname[^)]*\)[^\'"\s]*).*', re.A | re.S), 2),
    (re.compile(r'^.*(source|\.)\s+[\'"]?([^\'"\s]+).*', re.A | re.S), 2),
    (re.compile(r'^.*from\s+[\'"]([^\'"]+).*', re.A | re.S), 1),
    (re.compile(r'^.*import\s+[\'"]([^\'"]+).*', re.A | re.S), 1),
    (re.compile(r'^.*(require|import)\([\'"]([^\'"]+).*', re.A | re.S), 2),
    (re.compile(r'^.*load\s+[\'"]([^\'"]+).*', re.A | re.S), 1),
    (re.compile(r'^\s*from\s+([a-zA-Z0-9_.]+)\s+import\s.*', re.A | re.S), 1),
    (re.compile(r'^\s*import\s+([a-zA-Z0-9_.]+).*', re.A | re.S), 1),
]
GREP3 = re.compile(r'\$[A-Za-z_{][A-Za-z0-9_}]*(?:/[A-Za-z0-9_.${}-]+)+')
VAR_ASSIGN = re.compile(r'^\s*(?:export\s+)?(?:declare\s+-[a-zA-Z]+\s+)?[A-Za-z_][A-Za-z0-9_]*=', re.A)
VAR_Q = re.compile(r'^\s*(?:export\s+|declare\s+-[a-zA-Z]+\s+)*([A-Za-z_][A-Za-z0-9_]*)="(.*)"', re.A | re.S)
VAR_U = re.compile(r'^\s*(?:export\s+|declare\s+-[a-zA-Z]+\s+)*([A-Za-z_][A-Za-z0-9_]*)=([^\s"\']+)', re.A)
CD_RE = re.compile(r'\$\(cd\s+"?([^"&)]+)"?\s*&&\s*pwd(\s+-P)?\)', re.A)
DOTTED = re.compile(r'[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+')
RUNNER_SUBCMD = {"bun test", "npm test", "pnpm test", "yarn test", "go test", "cargo test", "deno test", "make test", "run test"}
STEM_EXTS = ("sh", "ts", "tsx", "mjs", "js", "py", "rb")

def inv_re(words):
    return re.compile(r'(^|[\s(&|;])(%s)\s+["\']?[^\s]' % words, re.A)

def normpath_bash(p):
    # the runner's cheap normaliser: strip one leading ./, then at most six collapse rounds
    if p.startswith("./"):
        p = p[2:]
    for _ in range(6):
        if "../" in p or p.endswith("/.."):
            p = re.sub(r'^\./', '', p)
            p = re.sub(r'/\./', '/', p)
            p = re.sub(r'[^/][^/]*/\.\./', '', p)
            p = re.sub(r'[^/][^/]*/\.\.$', '', p)
        else:
            break
    return p

class Walker:
    def __init__(self, root, leaves):
        self.root, self.leaves = root, set(leaves)
        self._text, self._fe = {}, {}
        self.pwd = os.path.abspath(root)

    def exists(self, rel):
        return bool(rel) and os.path.exists(os.path.join(self.root, rel))

    def isfile(self, rel):
        return bool(rel) and os.path.isfile(os.path.join(self.root, rel))

    def isdir(self, rel):
        return bool(rel) and os.path.isdir(os.path.join(self.root, rel))

    def lines(self, rel):
        if rel not in self._text:
            try:
                with open(os.path.join(self.root, rel), "rb") as fh:
                    self._text[rel] = fh.read().decode("utf-8", "replace").split("\n")
            except OSError:
                self._text[rel] = []
        return self._text[rel]

    def edge_token(self, fdir, p, nod1=False):
        # One extracted token -> the repo path it names, or None (the runner's token tail).
        p = p.replace('$(dirname "${BASH_SOURCE[0]}")', fdir).replace('$(dirname "$0")', fdir)
        alt = ""
        if not nod1:
            m = CD_RE.search(p)
            if m:
                cdm, cdt = m.group(0), m.group(1)
                if "$" not in cdt:
                    cdt = normpath_bash(cdt)
                    cdt = cdt[:-1] if cdt.endswith("/") else cdt
                    alt = p
                    p = p.replace(cdm, cdt or ".", 1)
        p = re.sub(r'\$\(cd.*pwd.*-P\)', lambda _: fdir, p, flags=re.S)
        p = re.sub(r'\$\(cd.*pwd\)', lambda _: fdir, p, flags=re.S)
        if p.startswith('"'):
            p = p[1:]
        if p.startswith("'"):
            p = p[1:]
        p = re.split(r'["\']', p, maxsplit=1)[0]
        for a, b in (("$HERE", fdir), ("${HERE}", fdir), ("$SCRIPT_DIR", fdir), ("${SCRIPT_DIR}", fdir),
                     ("$REPO_ROOT", "."), ("${REPO_ROOT}", "."), ("$ROOT_DIR", ".")):
            p = p.replace(a, b)
        if p.startswith(self.pwd + "/"):
            p = p[len(self.pwd) + 1:]
        if p.startswith("/") or p.startswith("../") or p in ("..", "."):
            p = ""
        else:
            p = normpath_bash(p)
            if p.startswith("../") or p in ("..", "."):
                p = ""
        if p and not self.exists(p) and DOTTED.fullmatch(p):
            p = p.replace(".", "/") + ".py"
        hit = p if (p and self.exists(p)) else None
        if hit is None and alt:
            # D1 may only widen: a token it left without an edge is re-run as it was before D1 existed
            return self.edge_token(fdir, alt, nod1=True)
        return hit

    def varmap(self, rel):
        vn, vv = [], []
        for ln in self.lines(rel):
            if not VAR_ASSIGN.match(ln):
                continue
            m = VAR_Q.match(ln)
            if m:
                vn.append(m.group(1)); vv.append(m.group(2))
                continue
            m = VAR_U.match(ln)
            if m:
                vn.append(m.group(1)); vv.append(m.group(2))
        return vn, vv

    def resolve_vars(self, s, vm):
        vn, vv = vm
        cap = len(s.encode("utf-8", "surrogateescape")) + 4096
        it = 0
        while it < 12 and len(s.encode("utf-8", "surrogateescape")) <= cap:
            m = re.search(r'\$\{?([A-Za-z_][A-Za-z0-9_]*)', s)
            if not m:
                break
            it += 1
            want = m.group(1)
            try:
                i = vn.index(want)
            except ValueError:
                break
            s = s.replace("$" + want, vv[i]).replace("${" + want + "}", vv[i])
        return s

    def file_edges(self, f, leaf):
        # Existing repo paths one file's text yields, in discovery order. `leaf`: the leaf reading (source/. words only, no pass 3).
        key = (f, leaf)
        if key in self._fe:
            return self._fe[key]
        out, seen = [], set()
        def add(p):
            if p and p not in seen and self.exists(p):
                seen.add(p); out.append(p)
        if not self.isfile(f):
            self._fe[key] = out
            return out
        fdir = f.rsplit("/", 1)[0] if "/" in f else "."
        lines = self.lines(f)
        for ln in lines:
            if not GREP1.search(ln):
                continue
            for pat, grp in SED1:
                m = pat.match(ln)
                if m:
                    ln = m.group(grp)
            add(self.edge_token(fdir, ln))
        vm = self.varmap(f)
        words = r'source|\.' if leaf else r'source|\.|bash|sh|python3?|node|bun'
        irx = inv_re(words)
        for ln in lines:
            if not irx.search(ln):
                continue
            ln = self.resolve_vars(ln, vm)
            ln = ln.replace('$(dirname "${BASH_SOURCE[0]}")', fdir).replace('$(dirname "$0")', fdir)
            for tok in ln.split(" "):
                if tok and ("/" in tok or "$" in tok):
                    add(self.edge_token(fdir, tok))
        if not leaf:
            seen3 = set()
            for ln in lines:
                for m in GREP3.finditer(ln):
                    seen3.add(m.group(0))
            for tok in sorted(seen3):
                add(self.edge_token(fdir, self.resolve_vars(tok, vm)))
        self._fe[key] = out
        return out

    def anchored(self, p):
        if p in (".", "..") or p.startswith("./") or p.startswith("../"):
            return p
        return "^" + (p.rstrip("/") + "/" if self.isdir(p) else p)

    def derive(self, argv, head):
        # The suite's derived edge list (anchored, in the runner's spelling), or [] for an argv naming nothing.
        edges, eset = [], set()
        def add(p):
            if not p or "\n" in p or not self.exists(p):
                return False
            a = self.anchored(p)
            if a in eset:
                return False
            eset.add(a); edges.append(a)
            return True
        suite, prev = "", ""
        for tok in argv:
            if prev in ("-c", "-ec", "-lc"):
                pw = ""
                for w in tok.split():
                    w = w[:-1] if w.endswith('"') else w
                    w = w[1:] if w.startswith('"') else w
                    w = w[:-1] if w.endswith("'") else w
                    w = w[1:] if w.startswith("'") else w
                    if (pw + " " + w) in RUNNER_SUBCMD:
                        pw = w
                        continue
                    pw = w
                    add(w)
            if (prev + " " + tok) in RUNNER_SUBCMD:
                prev = tok
                continue
            prev = tok
            if tok.startswith("/"):
                continue
            if tok.endswith((".sh", ".ts", ".tsx", ".mjs", ".js", ".py", ".rb")):
                add(tok)
                if not suite and self.isfile(tok):
                    suite = tok
            elif "." in tok:
                add(tok)
                if not self.exists(tok) and DOTTED.fullmatch(tok):
                    mod = tok.replace(".", "/")
                    add(mod); add(mod + ".py"); add(mod + ".sh")
                    if not suite and self.isfile(mod + ".py"):
                        suite = mod + ".py"
            else:
                add(tok)
        if suite:
            d = suite.rsplit("/", 1)[0] if "/" in suite else "."
            b = suite.rsplit("/", 1)[-1]
            stem = ""
            if b.endswith(".test.sh"): stem = b[:-8] + ".sh"
            elif b.endswith((".test.ts", ".test.tsx")): stem = b.rsplit(".test.", 1)[0]
            elif b.endswith(".test.py"): stem = b[:-8] + ".py"
            elif re.match(r'test[-_].*\.sh$', b) or re.match(r'test[-_].*\.py$', b): stem = b[5:]
            if stem:
                bare = stem.rsplit(".", 1)[0]
                dd = d[:-5] if d.endswith("/test") else d
                for cd in (d, d + "/lib", "scripts", dd + "/scripts"):
                    for ext in STEM_EXTS:
                        add(cd + "/" + bare + "." + ext)
                add(d + "/" + stem); add(d + "/lib/" + stem); add("scripts/" + stem)
            queue, sset = [suite], {suite}
            depth = 0
            while queue and depth < MAXDEPTH:
                depth += 1
                nxt = []
                for f in queue:
                    leaf = bool(head and (f[2:] if f.startswith("./") else f) in self.leaves)
                    for p in self.file_edges(f, leaf):
                        if add(p):
                            if self.isfile(p) and p not in sset:
                                sset.add(p); nxt.append(p)
                queue = nxt
        return edges
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
    """Edges a label DECLARES (AFFECTED_<LABEL>_PATHS or an AFFECTED_CONSUMED_EDGES mapping), read from the declarations lib text; the runner re-adds
    these after the derive, so the leaf rule can never remove them."""
    # a consumed array may live in either lib ("the consumed mapping mechanism does not care which file owns the array")
    arrays = {}
    for name in ("test-affected-paths.sh", "test-relevance-paths.sh"):
        try:
            text = open(os.path.join(root, "scripts", "lib", name), encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        for m in re.finditer(r'^([A-Za-z_][A-Za-z0-9_]*)=\(\n(.*?)^\)\n', text, re.S | re.M):
            arrays[m.group(1)] = m.group(2)
    if not arrays:
        return set()
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
    out = expand(name)
    # AFFECTED_CONSUMED_EDGES maps `label|ARRAY_NAME` (the array may live under any name); the runner treats those edges as declared too
    for ln in arrays.get("AFFECTED_CONSUMED_EDGES", "").splitlines():
        lit = re.fullmatch(r'"([^"|]+)\|([A-Za-z_][A-Za-z0-9_]*)"', ln.split("#", 1)[0].strip())
        if lit and lit.group(1) == label:
            out |= expand(lit.group(2))
    return out

def categorize(e, rb, rh, kept):
    # Why a removed (or kept) edge is not what the walker expected, by the walker's own reading of the two closures.
    k = edge_key(e)
    if kept:
        # expected removed (base-only in the walker) but the head kept it: the walker's HEAD closure is missing a route the derive has
        return "kept: head route the walker lacks"
    if k not in rb:
        # the head lost an edge the walker does not even find in the BASE closure: the walker under-reads the derive
        return "removed: not in the walker's base closure"
    return "removed: the walker's head closure still reaches it"

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
    if not cmds:
        # A walker with no suite commands has no roots: every removal would read as "unexplained" or, under a ceiling,
        # as tolerated. "Could not measure" must not read as "nothing found".
        problems.append("blind walker: --cmds %s holds no SUITE_COMMAND record" % cmds_path)
        return None
    w = Walker(root, leaves)
    leaf_keys = set(leaves)
    # A leaf that names nothing (the declarations lib: its paths are quoted array data, never invoked or sourced) can
    # lose nothing, so a row that merely carries it as an edge does not "reach" a leaf in the sense this check needs.
    live_keys = {lf for lf in leaf_keys if w.file_edges(lf, False)}
    if not live_keys:
        problems.append("no leaf file has an outbound edge in the tree under --root (nothing to narrow)")
    retained_targets = set()
    for lf in leaves:
        retained_targets |= set(w.file_edges(lf, True))
    if len(a_rows) != len(b_rows):
        problems.append("row count differs: base %d head %d" % (len(a_rows), len(b_rows)))
        return None
    n_reach = n_retained_pairs = n_changed = flips = flips_edge = 0
    fid_rows = fid_base = fid_head = 0
    closure = {}
    def model(label, head):
        # the walker's closure for one label, memoised: each side is derived once however many checks read it
        if (label, head) not in closure:
            closure[(label, head)] = {edge_key(e) for e in w.derive(cmds[label], head)}
        return closure[(label, head)]
    total_unexplained = rows_unexplained = total_kept = rows_kept = 0
    cat_unexplained, cat_kept = {}, {}
    max_unexplained = int(os.environ.get("BENCH_MAX_UNEXPLAINED", "0") or 0)
    max_kept = int(os.environ.get("BENCH_MAX_KEPT", "0") or 0)
    first_bad = None
    for x, y in zip(a_rows, b_rows):
        fx, fy = x.split("\t"), y.split("\t")
        label = fx[1]
        if fx[1] != fy[1] or fx[3] != fy[3]:
            problems.append("row %s: label/class differ (%s vs %s)" % (label, fx[1:4:2], fy[1:4:2]))
            continue
        if label not in cmds:
            problems.append("row %s: no SUITE_COMMAND record for this label in --cmds (blind walker: it has no roots to walk)" % label)
            continue
        ex = [e for e in (fx[4].split("|") if len(fx) > 4 else []) if e]
        ey = [e for e in (fy[4].split("|") if len(fy) > 4 else []) if e]
        if fx[3].startswith("edge:") or fx[3] == "unclassified":
            # fidelity: does the walker reproduce the row it is about to judge the removals of? (derived plus declared edges)
            fid_rows += 1
            dk = {edge_key(d) for d in declared_edges(root, label)}
            fid_base += model(label, False) | dk == {edge_key(e) for e in ex}
            fid_head += model(label, True) | dk == {edge_key(e) for e in ey}
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
        reaches = any(edge_key(e) in live_keys for e in ex)
        if not reaches and removed:
            # No ceiling: a row that does not reach a leaf file has nothing the leaf rule may take from it.
            problems.append("row %s: lost %d edge(s) %s but its base edges reach no leaf file with outbound edges (a row that does not reach a leaf must be byte-identical)" % (label, len(removed), sorted(removed)[:2]))
            continue
        if not reaches:
            continue
        n_reach += 1
        # The walker derives the suite's closure twice (leaf files read in full, then as leaves); the edges only the first
        # reaches, minus what the label DECLARES (the runner re-adds those), are what the leaf rule is expected to remove.
        rb, rh = model(label, False), model(label, True)
        decl = {edge_key(d) for d in declared_edges(root, label)}
        expected = {e for e in ex if edge_key(e) in rb and edge_key(e) not in rh and edge_key(e) not in decl}
        if removed:
            n_changed += 1
        elif expected:
            # No ceiling: the row reaches a leaf, the walker expects it to lose edges, and it lost none: the rule did not apply to it.
            problems.append("row %s: reaches a leaf file and lost NOTHING, but the walker expects %d removal(s) %s (the leaf rule did not apply to this row)" % (label, len(expected), sorted(expected)[:2]))
            continue
        missed = expected - removed          # the head KEPT an edge the walker expects gone (a route the walker misses, or a neutralised rule)
        unexplained = removed - expected     # removed, but the walker does not derive it as leaf-only
        if missed:
            total_kept += len(missed)
            rows_kept += 1
            for e in missed:
                c = categorize(e, rb, rh, True)
                cat_kept[c] = cat_kept.get(c, 0) + 1
            if len(missed) > max_kept:
                if first_bad is None:
                    first_bad = (label, sorted(unexplained)[:4], sorted(missed)[:4])
                problems.append("row %s: head KEPT %d edge(s) the walker expects removed %s, ceiling --max-kept %d" % (label, len(missed), sorted(missed)[:2], max_kept))
        if unexplained:
            total_unexplained += len(unexplained)
            rows_unexplained += 1
            for e in unexplained:
                c = categorize(e, rb, rh, False)
                cat_unexplained[c] = cat_unexplained.get(c, 0) + 1
            if len(unexplained) > max_unexplained:
                if first_bad is None:
                    first_bad = (label, sorted(unexplained)[:4], sorted(missed)[:4])
                problems.append("row %s: removed set != walker's expected set (%d unexplained removals %s, ceiling --max-unexplained %d)" % (label, len(unexplained), sorted(unexplained)[:2], max_unexplained))
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
    print("  walker fidelity: it reproduced %d of %d base rows and %d of %d head rows exactly (edge-classified rows; derived plus declared edges)"
          % (fid_base, fid_rows, fid_head, fid_rows))
    if first_bad:
        print("  first mismatch: %s | removed-not-expected %s | expected-not-removed %s" % first_bad)
    if n_changed == 0:
        problems.append("population floor: no row lost an edge (a neutralised leaf rule must not certify)")
    if not retained_targets:
        problems.append("population floor: the walker resolved no real source target of the leaf files (nothing to retain-check)")
    elif n_retained_pairs == 0:
        problems.append("population floor: no (row, real source target) pair was checked")
    if total_kept:
        print("  kept (expected removed, head kept): %d edge(s) over %d row(s) (per-row ceiling --max-kept %d); by category: %s"
              % (total_kept, rows_kept, max_kept, ", ".join("%s=%d" % kv for kv in sorted(cat_kept.items()))))
    if total_unexplained:
        print("  unexplained (removed, not expected): %d edge(s) over %d row(s) (per-row ceiling --max-unexplained %d); by category: %s"
              % (total_unexplained, rows_unexplained, max_unexplained, ", ".join("%s=%d" % kv for kv in sorted(cat_unexplained.items()))))
    return (len(a_rows), n_reach, n_changed, n_retained_pairs, total_unexplained, total_kept, max_unexplained, max_kept)

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
    # The verdict word carries the numbers: a reader scanning for the word must not take "EXPLAINED" for "nothing unexplained".
    print("EXPLAINED (%d unexplained, %d kept, ceilings %d/%d): %d rows compared, %d reach a leaf file, %d lost edges, %d retained real source edges checked"
          % (res[4], res[5], res[6], res[7], res[0], res[1], res[2], res[3]))
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
CMDS_USER="$CMDS_FILE"; ROOT_USER="$ROOT_DIR"
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
    # A value the operator passed wins; only an unset one is derived (the loop used to overwrite both).
    [[ -n "$CMDS_USER" ]] || CMDS_FILE="$SCRATCH/cmds.head.$probe_i"
    [[ -n "$ROOT_USER" ]] || ROOT_DIR="$H_DIR"
    if [[ -z "$CMDS_USER" ]]; then
      assert_fixture_dir "$CMDS_FILE"
      ( cd "$H_DIR" && env -u CI -u SOLEUR_TEST_FORCE_ALL bash "$H_RUNNER" --enumerate-commands "--paths=$probe" all 2>"$SCRATCH/cmds.err.$probe_i" ) > "$CMDS_FILE"
      _cmds_rc=$?
      _cmds_n="$(grep -c '^SUITE_COMMAND' "$CMDS_FILE" 2>/dev/null)" || _cmds_n=0
      if [[ "$_cmds_rc" != "0" || "$_cmds_n" == "0" ]]; then
        # A blind walker passes anything within its ceilings: refuse before comparing.
        echo "DIFFERS: cannot enumerate the head's suite commands (rc=$_cmds_rc, $_cmds_n SUITE_COMMAND record(s)); the leaf walker would be blind: $(head -c 300 "$SCRATCH/cmds.err.$probe_i" 2>/dev/null | tr '\n' ' ')"
        OVERALL=1; continue
      fi
    fi
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
  vword="identical"
  if [[ -n "$LEAF_FILES" ]]; then
    # "narrowed only as declared" is claimed only when the walker explained every removal and kept nothing it expected gone.
    if [[ "$verdict" =~ EXPLAINED\ \(([0-9]+)\ unexplained,\ ([0-9]+)\ kept ]] && (( BASH_REMATCH[1] == 0 && BASH_REMATCH[2] == 0 )); then
      vword="narrowed only as declared"
    elif [[ "$verdict" =~ EXPLAINED\ \(([0-9]+)\ unexplained,\ ([0-9]+)\ kept ]]; then
      vword="narrowed, with ${BASH_REMATCH[1]} unexplained removal(s) and ${BASH_REMATCH[2]} kept edge(s) within the ceilings (see above)"
    else
      vword="narrowed (verdict not parsed)"
    fi
  fi
  (( vrc == 0 )) || vword="DIFFERENT"
  echo "  plain: an affected run waited about ${bmed} s of CPU on selection and now waits about ${hmed} s (${fmed}x), selection ${vword}."
done

exit "$OVERALL"
