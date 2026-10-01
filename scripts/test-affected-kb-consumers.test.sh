#!/usr/bin/env bash
# test-affected-kb-consumers.test.sh — the dropped-consumer ratchet for the affected gate
# (#9307, Guard 2).
#
# PROPERTY. Every registered suite that reads a REAL repo `knowledge-base/` path — in its own
# file or one hop into a script it names — is `always_on` or carries an edge that COVERS that
# path. A suite that leaves the always-on set without a covering edge silently stops running
# when the knowledge base changes; this is the regression the always-on audit could introduce.
#
# ASSEMBLY. The population is DERIVED, never listed: `test-all.sh --enumerate-commands
# --paths=README.md all` (argv per registration) joined with `test-all.sh --print-selection
# --paths=README.md` (class and edge set per registration). BOTH streams name the same
# hypothetical diff, so the relevance-gated registrations (declined on a docs-only diff) are
# declined in both and the population does not depend on the checkout's real diff; the join is
# asserted total (a command with no selection row is a failure, never a skip). The chokepoint is
# the declared-edge and always-on arrays in scripts/lib/test-affected-paths.sh. A reference
# inside a fixture context (a mktemp root, a $tmp/$WORK/sandbox line, a comment) is not a read
# of the real tree and is skipped.
#
# BLIND SPOTS (stated, not hidden): only literal `knowledge-base/` references are seen (not
# `find knowledge-base`, `${KB_DIR:-knowledge-base}`, or split-literal joins); one hop into
# named scripts, not two; the six relevance-gated registrations are outside the population; a
# suite with no code file in its argv (`bun test plugins/soleur/`, `python3 -m unittest`) reads
# nothing here. The baseline records the gaps the oracle DOES see.
#
# BASELINE. Uncovered references the oracle sees are recorded in
# scripts/test-affected-kb-consumers.baseline.txt (`label<TAB>path`). A NEW uncovered reference
# fails, and so does a STALE entry (one the oracle no longer reports), so the file always equals
# what `--write-baseline` produces. Some entries are one-hop scan false positives, not reads the
# suite performs; the baseline does not distinguish them. Regenerate with
#   bash scripts/test-affected-kb-consumers.test.sh --write-baseline
#
# MUTATIONS. The oracle is itself guarded: rows below drive it with a covering edge removed, an
# empty enumeration, a second non-compliant member after a compliant first, and a fixture-only
# suite that must NOT be flagged.
#
# AUTHORING (work/SKILL.md): never `producer | grep -q` under pipefail; capture rc on its own
# line; `cases` is incremented at the call site.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/test-all.sh"
BASELINE="$REPO_ROOT/scripts/test-affected-kb-consumers.baseline.txt"
export TMPDIR="${TMPDIR:-/var/tmp}"
TESTROOT="$(mktemp -d -t kb-consumers.XXXXXXXX)" || exit 2

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
assert_fixture_dir "$TESTROOT"
cleanup() { rm -rf "$TESTROOT"; }
trap cleanup EXIT INT TERM HUP

PASS=0; FAIL=0; cases=0
pass() { PASS=$((PASS + 1)); echo "  [ok] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  [FAIL] $1" >&2; }

# Instrument self-test: both verdict helpers must move their counters.
_sp=$PASS; _sf=$FAIL
pass "instrument self-test" >/dev/null 2>&1
fail "instrument self-test" >/dev/null 2>&1
if (( PASS != _sp + 1 )) || (( FAIL != _sf + 1 )); then
  echo "[FATAL] instrument self-test failed" >&2; exit 1
fi
PASS=$_sp; FAIL=$_sf

ORACLE="$TESTROOT/oracle.py"
cat > "$ORACLE" <<'PY'
#!/usr/bin/env python3
"""check <rows.tsv> <cmds.tsv> <baseline> | refs <rows.tsv> <cmds.tsv>"""
import os, re, sys

CODE = (".sh", ".py", ".ts", ".tsx", ".mjs", ".js")
FIXTURE = re.compile(r'mktemp|\$\{?(?:tmp|work|sandbox|fixture)|fixture|sandbox|tmpdir', re.I)
# A variable holding the REAL repo root (a path rooted at any other variable is a fixture root).
ROOTVAR = re.compile(r'REPO|PROJECT|GIT_ROOT|ROOT_DIR|^ROOT$')
KB = re.compile(r'knowledge-base/[A-Za-z0-9_.*/-]*[A-Za-z0-9_*/-]')
TOKEN = re.compile(r'[A-Za-z0-9_./-]+\.(?:sh|py|ts|mjs|js)')


def load_rows(path):
    rows = {}
    for line in open(path):
        f = line.rstrip("\n").split("\t")
        if f[0] == "AFFECTED_SELECTED" and len(f) >= 5:
            rows[f[1]] = (f[3], [e for e in f[4].split("|") if e])
    return rows


def load_cmds(path):
    cmds = {}
    for line in open(path):
        f = line.rstrip("\n").split("\t")
        if f[0] == "SUITE_COMMAND" and len(f) >= 3:
            cmds[f[1]] = f[2:]
    return cmds


def code_files(argv):
    out = []
    for t in argv:
        if t.endswith(CODE) and os.path.isfile(t):
            out.append(t)
    return out


# This file's `knowledge-base/...` strings are synthetic test data, and its text names the runner
# and the declarations lib, whose own paths would then be scanned one hop away: the ratchet is
# not a reader of the knowledge base, so it is excluded from its own population (and from the
# one-hop scan of any suite that names it).
OWN = "test-affected-kb-consumers.test.sh"


def scan(path):
    refs = set()
    if os.path.basename(path) == OWN:
        return refs
    try:
        text = open(path, errors="replace").read()
    except OSError:
        return refs
    for ln in text.splitlines():
        s = ln.strip()
        if s.startswith(("#", "//", "*", "/*")) or FIXTURE.search(ln):
            continue
        for m in KB.finditer(ln):
            pre = ln[:m.start()]
            if pre.endswith("/"):
                # A path rooted at a VARIABLE is the real tree only when the variable is
                # the repo root; `"$d/knowledge-base/..."` is a fixture root.
                vm = re.search(r'\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?"?/$', pre)
                real = bool(vm and ROOTVAR.search(vm.group(1))) or "show-toplevel)" in pre[-18:]
                if not real:
                    continue
            p = m.group(0).split("*")[0].rstrip("/-_.")
            while p and not os.path.exists(p):
                p = p.rsplit("/", 1)[0] if "/" in p else ""
            if p.startswith("knowledge-base"):
                refs.add(p)
    return refs


def suite_refs(argv):
    files = set(code_files(argv))
    if any(os.path.basename(f) == OWN for f in files):
        return set()
    first = list(files)
    for f in first:                     # one hop: scripts the suite names
        try:
            text = open(f, errors="replace").read()
        except OSError:
            continue
        for t in TOKEN.findall(text):
            if os.path.isfile(t) and not FIXTURE.search(t):
                files.add(t)
    refs = set()
    for f in files:
        refs |= scan(f)
    return refs


def covers(edge, p):
    if edge.startswith("^"):
        e = edge[1:]
        if e.endswith("/"):
            return p.startswith(e) or (p + "/") == e
        return p == e
    e = edge.rstrip("/")
    return p.startswith(e) or (p + "/").startswith(e + "/")


def violations(rows, cmds):
    out = []
    for label, argv in sorted(cmds.items()):
        cls, edges = rows[label]
        if cls == "always_on":
            continue
        for p in sorted(suite_refs(argv)):
            if not any(covers(e, p) for e in edges):
                out.append((label, p))
    return out


if __name__ == "__main__":
    mode = sys.argv[1]
    rows, cmds = load_rows(sys.argv[2]), load_cmds(sys.argv[3])
    if mode == "refs":
        for label, argv in sorted(cmds.items()):
            for p in sorted(suite_refs(argv)):
                print(f"REF\t{label}\t{p}")
        sys.exit(0)
    if not rows or not cmds:
        print("VACUOUS\tempty enumeration or selection")
        sys.exit(3)
    unjoined = sorted(set(cmds) - set(rows))
    if unjoined:
        for label in unjoined[:5]:
            print(f"UNJOINED\t{label}\tno selection row for an enumerated command")
        sys.exit(3)
    base = set()
    if len(sys.argv) > 4 and os.path.exists(sys.argv[4]):
        for line in open(sys.argv[4]):
            t = tuple(line.rstrip("\n").split("\t"))
            if len(t) == 2:
                base.add(t)
    new = [v for v in violations(rows, cmds) if v not in base]
    for label, p in new:
        print(f"VIOLATION\t{label}\t{p}")
    sys.exit(1 if new else 0)
PY

# --- Derived population: rows (class + edges) and argv, from the REAL runner ----------
ROWS="$TESTROOT/rows.tsv"; CMDS="$TESTROOT/cmds.tsv"
( cd "$REPO_ROOT" && env -u CI -u TEST_GROUP SOLEUR_DISABLE_SESSION_STATE=1 \
    bash "$RUNNER" --print-selection --paths=README.md ) > "$ROWS" 2>/dev/null
_rc_rows=$?
( cd "$REPO_ROOT" && env -u CI -u TEST_GROUP SOLEUR_DISABLE_SESSION_STATE=1 \
    bash "$RUNNER" --enumerate-commands --paths=README.md all ) > "$CMDS" 2>/dev/null
_rc_cmds=$?

if [[ "${1:-}" == "--write-baseline" ]]; then
  ( cd "$REPO_ROOT" && python3 "$ORACLE" check "$ROWS" "$CMDS" /dev/null ) \
    | awk -F'\t' '$1=="VIOLATION"{print $2"\t"$3}' | LC_ALL=C sort -u > "$BASELINE"
  echo "wrote $(wc -l < "$BASELINE" | tr -d ' ') baseline entries to $BASELINE"
  exit 0
fi

echo "== test-affected-kb-consumers: dropped-consumer ratchet =="

# Row 1: the population is derived and non-trivial.
cases=$((cases + 1))
_n_rows=$(grep -c $'^AFFECTED_SELECTED\t' "$ROWS" 2>/dev/null || true)
_n_cmds=$(grep -c $'^SUITE_COMMAND\t' "$CMDS" 2>/dev/null || true)
if [[ "$_rc_rows" == "0" && "$_rc_cmds" == "0" ]] && (( _n_rows >= 400 )) && (( _n_cmds >= 400 )); then
  pass "1: population derived from the runner (rows=$_n_rows, commands=$_n_cmds)"
else
  fail "1: rows rc=$_rc_rows n=$_n_rows, cmds rc=$_rc_cmds n=$_n_cmds (need >=400 each)"
fi

# Row 2: the property, against the baseline.
cases=$((cases + 1))
_viol=$( cd "$REPO_ROOT" && python3 "$ORACLE" check "$ROWS" "$CMDS" "$BASELINE" 2>&1 ); _rc=$?
if [[ "$_rc" == "0" ]]; then
  pass "2: every suite reading a real knowledge-base path is always-on or covered (baseline: $(wc -l < "$BASELINE" | tr -d ' ') known gaps)"
else
  fail "2: rc=$_rc — $(head -5 <<<"$_viol" | tr '\n' ';')"
fi

# Row b1: the baseline equals what the oracle reports against an EMPTY baseline. Row 2 alone is
# one-sided (a fixed gap never fails it), so a stale entry would keep silencing a suite that
# regains the same uncovered read; this row makes the file shrink-only AND exact.
cases=$((cases + 1))
_regen=$( cd "$REPO_ROOT" && python3 "$ORACLE" check "$ROWS" "$CMDS" /dev/null 2>/dev/null \
  | awk -F'\t' '$1=="VIOLATION"{print $2"\t"$3}' | LC_ALL=C sort -u )
_have=$( LC_ALL=C sort -u "$BASELINE" )
if [[ -n "$_have" && "$_regen" == "$_have" ]]; then
  pass "b1: the committed baseline equals the regenerated one (no stale or missing entry)"
else
  fail "b1: baseline differs from --write-baseline output: $(diff <(printf '%s\n' "$_have") <(printf '%s\n' "$_regen") | head -6 | tr '\n' ';')"
fi

# Row 3 (anti-vacuity): at least one suite is covered BY AN EDGE (not always-on) — else the
# property is satisfied by the always-on class alone and the mutation rows below have nothing
# to bite on.
cases=$((cases + 1))
( cd "$REPO_ROOT" && python3 "$ORACLE" refs "$ROWS" "$CMDS" ) > "$TESTROOT/refs.tsv"
_edge_covered=$(python3 - "$ROWS" "$TESTROOT/refs.tsv" "$ORACLE" <<'PY'
import sys, importlib.util
spec = importlib.util.spec_from_file_location("o", sys.argv[3]); o = importlib.util.module_from_spec(spec); spec.loader.exec_module(o)
rows = o.load_rows(sys.argv[1])
n = 0
for line in open(sys.argv[2]):
    _, label, p = line.rstrip("\n").split("\t")
    cls, edges = rows.get(label, ("", []))
    if cls.startswith("edge:") and any(o.covers(e, p) for e in edges):
        n += 1
print(n)
PY
)
if [[ "$_edge_covered" =~ ^[0-9]+$ ]] && (( _edge_covered >= 1 )); then
  pass "3: at least one knowledge-base reference is covered by an edge (n=$_edge_covered)"
else
  fail "3: no edge-covered knowledge-base reader found (n='$_edge_covered') — the mutation rows would be vacuous"
fi

# Mutation rows drive the ORACLE with edited inputs.
_first=$(python3 - "$ROWS" "$TESTROOT/refs.tsv" "$ORACLE" <<'PY'
import sys, importlib.util
spec = importlib.util.spec_from_file_location("o", sys.argv[3]); o = importlib.util.module_from_spec(spec); spec.loader.exec_module(o)
rows = o.load_rows(sys.argv[1])
refs = {}
for line in open(sys.argv[2]):
    _, label, p = line.rstrip("\n").split("\t")
    refs.setdefault(label, set()).add(p)
# A suite whose EVERY reference is covered and that carries a knowledge-base edge: removing
# that edge must be the only thing that makes the oracle flag it.
for label in sorted(refs):
    cls, edges = rows.get(label, ("", []))
    if cls.startswith("edge:") and any("knowledge-base" in e for e in edges) \
       and all(any(o.covers(e, p) for e in edges) for p in refs[label]):
        print(label); break
PY
)

# m1: drop every knowledge-base edge from that suite -> the oracle must flag it.
cases=$((cases + 1))
python3 - "$ROWS" "$TESTROOT/rows-m1.tsv" "$_first" <<'PY'
import sys
out = open(sys.argv[2], "w")
for line in open(sys.argv[1]):
    f = line.rstrip("\n").split("\t")
    if f[0] == "AFFECTED_SELECTED" and f[1] == sys.argv[3] and len(f) >= 5:
        f[4] = "|".join(e for e in f[4].split("|") if "knowledge-base" not in e)
    out.write("\t".join(f) + "\n")
PY
_m1=$( cd "$REPO_ROOT" && python3 "$ORACLE" check "$TESTROOT/rows-m1.tsv" "$CMDS" /dev/null 2>&1 | grep -F "$_first" ); _rc=$?
_m1_ctl=$( cd "$REPO_ROOT" && python3 "$ORACLE" check "$ROWS" "$CMDS" /dev/null 2>&1 | grep -F "$_first" ); _rc=$?
if [[ -n "$_first" && -n "$_m1" && -z "$_m1_ctl" ]]; then
  pass "m1: removing the knowledge-base edge from $_first is flagged (and it is clean unmutated)"
else
  fail "m1: suite='$_first' flagged='${_m1}' unmutated-control='${_m1_ctl}'"
fi

# m2: an empty enumeration must refuse (rc 3), not pass.
cases=$((cases + 1))
: > "$TESTROOT/empty.tsv"
_rc=0; ( cd "$REPO_ROOT" && python3 "$ORACLE" check "$TESTROOT/empty.tsv" "$CMDS" /dev/null >/dev/null 2>&1 ) || _rc=$?
if [[ "$_rc" == "3" ]]; then
  pass "m2: an empty selection stream is refused (rc 3), not green"
else
  fail "m2: empty stream rc=$_rc, expected 3"
fi

# Synthetic suites for m3 / h1 / h2: real repo paths (they must exist), fixture files outside.
SYN="$TESTROOT/syn"; mkdir -p "$SYN"
printf '#!/usr/bin/env bash\ncat knowledge-base/legal/article-30-register.md >/dev/null\n' > "$SYN/reader-a.sh"
printf '#!/usr/bin/env bash\ncat knowledge-base/legal/article-30-register.md >/dev/null\n' > "$SYN/reader-b.sh"
printf '#!/usr/bin/env bash\nd=$(mktemp -d)\nmkdir -p "$d/knowledge-base/legal"\ncat "$d/knowledge-base/legal/article-30-register.md"\necho "sandbox copy of knowledge-base/legal/article-30-register.md"\n' > "$SYN/fixture-only.sh"
printf 'SUITE_COMMAND\tsyn/a\tbash\t%s\nSUITE_COMMAND\tsyn/b\tbash\t%s\nSUITE_COMMAND\tsyn/f\tbash\t%s\n' \
  "$SYN/reader-a.sh" "$SYN/reader-b.sh" "$SYN/fixture-only.sh" > "$TESTROOT/cmds-syn.tsv"

# m3: a compliant first member must not mask a non-compliant second one.
cases=$((cases + 1))
printf 'AFFECTED_SELECTED\tsyn/a\t0\tedge:declared\t^knowledge-base/legal/\nAFFECTED_SELECTED\tsyn/b\t0\tedge:declared\t^scripts/foo.sh\nAFFECTED_SELECTED\tsyn/f\t0\tedge:declared\t^scripts/foo.sh\n' > "$TESTROOT/rows-syn.tsv"
_o=$( cd "$REPO_ROOT" && python3 "$ORACLE" check "$TESTROOT/rows-syn.tsv" "$TESTROOT/cmds-syn.tsv" /dev/null 2>&1 ); _rc=$?
if [[ "$_rc" == "1" ]] && grep -qF $'VIOLATION\tsyn/b\t' <<<"$_o" && ! grep -qF $'VIOLATION\tsyn/a\t' <<<"$_o"; then
  pass "m3: the second reader is flagged after a compliant first, and only it"
else
  fail "m3: rc=$_rc — $_o"
fi

# h1: must-PASS, non-canonical — a suite whose only knowledge-base mention is a fixture
# context is NOT a real-tree read and must not be flagged.
cases=$((cases + 1))
if ! grep -qF $'VIOLATION\tsyn/f\t' <<<"$_o"; then
  pass "h1: a fixture-only (mktemp) knowledge-base mention is not flagged"
else
  fail "h1: the fixture-only suite was flagged — the oracle treats a fixture root as the real tree"
fi

# h2: harness row — an oracle that flags EVERYTHING must fail h1/m3's pairing: a covering
# edge on syn/a must yield NO violation for it (asserted above) AND a prefix edge that is a
# SIBLING directory must not cover (knowledge-base/legal-x/ does not cover knowledge-base/legal/...).
cases=$((cases + 1))
printf 'AFFECTED_SELECTED\tsyn/a\t0\tedge:declared\t^knowledge-base/legal-x/\nAFFECTED_SELECTED\tsyn/b\t0\tedge:declared\t^knowledge-base/legal/article-30-register.md\nAFFECTED_SELECTED\tsyn/f\t0\talways_on\t\n' > "$TESTROOT/rows-h2.tsv"
_o2=$( cd "$REPO_ROOT" && python3 "$ORACLE" check "$TESTROOT/rows-h2.tsv" "$TESTROOT/cmds-syn.tsv" /dev/null 2>&1 ); _rc=$?
if [[ "$_rc" == "1" ]] && grep -qF $'VIOLATION\tsyn/a\t' <<<"$_o2" && ! grep -qF $'VIOLATION\tsyn/b\t' <<<"$_o2"; then
  pass "h2: a sibling-prefix edge does not cover; an exact-file edge does"
else
  fail "h2: rc=$_rc — $_o2"
fi

# j1: the join is TOTAL. A command with no selection row must refuse (rc 3, UNJOINED), never be
#     skipped -- a skipped suite is an unchecked suite and the verdict reads the same.
cases=$((cases + 1))
printf 'AFFECTED_SELECTED\tsyn/a\t0\tedge:declared\t^knowledge-base/legal/\nAFFECTED_SELECTED\tsyn/b\t0\tedge:declared\t^knowledge-base/legal/\n' > "$TESTROOT/rows-j1.tsv"
_rc=0; _oj=$( cd "$REPO_ROOT" && python3 "$ORACLE" check "$TESTROOT/rows-j1.tsv" "$TESTROOT/cmds-syn.tsv" /dev/null 2>&1 ) || _rc=$?
if [[ "$_rc" == "3" ]] && grep -qF $'UNJOINED\tsyn/f\t' <<<"$_oj"; then
  pass "j1: an enumerated command with no selection row is refused (UNJOINED), not skipped"
else
  fail "j1: rc=$_rc — $_oj"
fi

# hop1: one hop into a script the suite NAMES is scanned. The suite's own file mentions no
#       knowledge-base path; the script it runs does.
cases=$((cases + 1))
printf '#!/usr/bin/env bash\nbash "%s/reader-b.sh"\n' "$SYN" > "$SYN/hop.sh"
printf 'SUITE_COMMAND\tsyn/h\tbash\t%s\n' "$SYN/hop.sh" > "$TESTROOT/cmds-hop.tsv"
printf 'AFFECTED_SELECTED\tsyn/h\t0\tedge:declared\t^scripts/foo.sh\n' > "$TESTROOT/rows-hop.tsv"
_oh=$( cd "$REPO_ROOT" && python3 "$ORACLE" check "$TESTROOT/rows-hop.tsv" "$TESTROOT/cmds-hop.tsv" /dev/null 2>&1 ); _rc=$?
if [[ "$_rc" == "1" ]] && grep -qF $'VIOLATION\tsyn/h\t' <<<"$_oh"; then
  pass "hop1: a knowledge-base read one hop away (a script the suite names) is flagged"
else
  fail "hop1: rc=$_rc — $_oh"
fi

# r1: a path rooted at the REAL repo root -- `$ROOT`, `$(git rev-parse --show-toplevel)` -- is a
#     read of the real tree and is flagged; a path rooted at a scratch variable is not.
cases=$((cases + 1))
printf '#!/usr/bin/env bash\ncat "$ROOT/knowledge-base/legal/article-30-register.md"\n' > "$SYN/root-var.sh"
printf '#!/usr/bin/env bash\ncat "$(git rev-parse --show-toplevel)/knowledge-base/legal/article-30-register.md"\n' > "$SYN/toplevel.sh"
printf '#!/usr/bin/env bash\ncat "$tmp_dir/knowledge-base/legal/article-30-register.md"\n' > "$SYN/scratch-var.sh"
printf 'SUITE_COMMAND\tsyn/rv\tbash\t%s\nSUITE_COMMAND\tsyn/tl\tbash\t%s\nSUITE_COMMAND\tsyn/sv\tbash\t%s\n' \
  "$SYN/root-var.sh" "$SYN/toplevel.sh" "$SYN/scratch-var.sh" > "$TESTROOT/cmds-r1.tsv"
printf 'AFFECTED_SELECTED\tsyn/rv\t0\tedge:declared\t^scripts/foo.sh\nAFFECTED_SELECTED\tsyn/tl\t0\tedge:declared\t^scripts/foo.sh\nAFFECTED_SELECTED\tsyn/sv\t0\tedge:declared\t^scripts/foo.sh\n' > "$TESTROOT/rows-r1.tsv"
_or=$( cd "$REPO_ROOT" && python3 "$ORACLE" check "$TESTROOT/rows-r1.tsv" "$TESTROOT/cmds-r1.tsv" /dev/null 2>&1 ); _rc=$?
if [[ "$_rc" == "1" ]] && grep -qF $'VIOLATION\tsyn/rv\t' <<<"$_or" \
  && grep -qF $'VIOLATION\tsyn/tl\t' <<<"$_or" && ! grep -qF $'VIOLATION\tsyn/sv\t' <<<"$_or"; then
  pass "r1: \$ROOT and show-toplevel roots are real-tree reads; a scratch-variable root is not"
else
  fail "r1: rc=$_rc — $_or"
fi

echo ""
if (( PASS + FAIL != cases )); then
  echo "[FATAL] verdict mismatch: PASS($PASS)+FAIL($FAIL) != cases($cases) — a row was skipped" >&2
  exit 2
fi
MIN_CASES=12
if (( cases < MIN_CASES )); then
  echo "[FATAL] only $cases cases ran — below the $MIN_CASES floor" >&2
  exit 2
fi
echo "test-affected-kb-consumers: $PASS passed, $FAIL failed of $((PASS + FAIL)) (cases=$cases)"
(( FAIL == 0 )) || exit 1
exit 0
