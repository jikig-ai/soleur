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
# READ FORMS. One row per form in the oracle's FORMS table (the chokepoint every read flows through; a
# new form is one row). Implemented: `argv-code` (a code file named in argv, plus one hop into scripts it
# names) and `dir-operand-tests` (a registration that names a DIRECTORY and no code file, such as
# `bun test plugins/soleur/`: the test files under it are the subject). Measured against the
# registrations on 2026-10-02 and NOT implemented, because every hit was a scan false positive:
# `${VAR:-knowledge-base/...}` defaults (3 suites; each suite overrides the variable with a scratch
# root), a bare `find|ls|grep|cd knowledge-base` word (5 suites; all exclusion pathspecs such as
# `:!knowledge-base` or a message string, none a read), `$PWD/knowledge-base` and a variable assigned
# the bare literal (0 suites). Re-measure before adding any of them.
#
# BLIND SPOTS (stated, not hidden): only literal `knowledge-base/` references are seen; one hop into
# named scripts, not two; the six relevance-gated registrations are outside the population; a suite
# whose argv names neither a code file nor a directory (`python3 -m unittest`) reads nothing here;
# the directory form scans only `*.test.*` / `*.spec.*` files (the files a runner executes), not
# every script below the directory. The baseline records the gaps the oracle DOES see.
#
# BASELINE. Uncovered references the oracle sees are recorded in
# scripts/test-affected-kb-consumers.baseline.txt. An `argv-code` row is `label<TAB>path`; a row from any
# other form is `label<TAB>path<TAB>form<TAB>classification` and the classification must be
# `false-positive: <reason>` (a real read gets a covering edge instead and leaves the baseline). A NEW
# uncovered reference fails, so does a STALE entry, and so does an unclassified row (`--write-baseline`
# stamps UNCLASSIFIED on a new non-literal row and carries an existing classification forward). Some
# entries are one-hop scan false positives, not reads the suite performs. Regenerate with
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


_TRACKED = None


def tracked(p):
    """A path counts as existing only when git TRACKS it (a file, or a directory with a tracked file
    below it): the baseline must not depend on a generated, gitignored file such as
    knowledge-base/INDEX.md that one checkout has and a fresh CI checkout does not."""
    global _TRACKED
    if _TRACKED is None:
        import subprocess
        out = subprocess.run(["git", "ls-files", "-z", "--", "knowledge-base"], capture_output=True).stdout
        files = [f for f in out.decode("utf-8", "replace").split("\0") if f]
        dirs = set()
        for f in files:
            d = f
            while "/" in d:
                d = d.rsplit("/", 1)[0]
                dirs.add(d)
        _TRACKED = (set(files), dirs)
    files, dirs = _TRACKED
    return p in files or p in dirs


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
            while p and not tracked(p):
                p = p.rsplit("/", 1)[0] if "/" in p else ""
            if p.startswith("knowledge-base"):
                refs.add(p)
    return refs


def argv_code_refs(argv):
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


SKIP_DIRS = ("node_modules", ".git", "__pycache__", ".next")
TESTFILE = re.compile(r'\.(?:test|spec)\.(?:ts|tsx|js|mjs)$')


def dir_operand_refs(argv):
    """A registration that names a DIRECTORY and no code file (`bun test plugins/soleur/`): the
    test files under the directory are the subject, so their reads are the suite's reads."""
    if code_files(argv):
        return set()
    refs = set()
    for t in argv:
        if not os.path.isdir(t):
            continue
        for dp, dn, fn in os.walk(t):
            dn[:] = sorted(d for d in dn if d not in SKIP_DIRS)
            for f in sorted(fn):
                if TESTFILE.search(f):
                    refs |= scan(os.path.join(dp, f))
    return refs


# One row per read form. A new form is one row here and one fixture row below.
FORMS = (
    ("argv-code", argv_code_refs),
    ("dir-operand-tests", dir_operand_refs),
)


def suite_refs(argv):
    """path -> form (the first form that sees the path)."""
    out = {}
    for name, fn in FORMS:
        for p in sorted(fn(argv)):
            out.setdefault(p, name)
    return out


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
        for p, form in sorted(suite_refs(argv).items()):
            if not any(covers(e, p) for e in edges):
                out.append((label, p, form))
    return out


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "forms":
        print("\n".join(name for name, _ in FORMS))
        sys.exit(0)
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
    base = {}
    if len(sys.argv) > 4 and os.path.exists(sys.argv[4]):
        for line in open(sys.argv[4]):
            t = line.rstrip("\n").split("\t")
            if len(t) >= 2:
                base[(t[0], t[1])] = t[2:]
    viol = violations(rows, cmds)
    if mode == "baseline":
        # Regeneration: argv-code rows stay two columns; any other form carries its form name and a
        # classification, kept from the existing baseline and UNCLASSIFIED when new.
        for label, p, form in viol:
            if form == "argv-code":
                print(f"{label}\t{p}")
            else:
                old = base.get((label, p), [])
                cls = old[1] if len(old) >= 2 else "UNCLASSIFIED"
                print(f"{label}\t{p}\t{form}\t{cls}")
        sys.exit(0)
    new = [v for v in viol if (v[0], v[1]) not in base]
    for label, p, form in new:
        print(f"VIOLATION\t{label}\t{p}\t{form}")
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
  _new_baseline="$TESTROOT/baseline.new"
  ( cd "$REPO_ROOT" && python3 "$ORACLE" baseline "$ROWS" "$CMDS" "$BASELINE" ) \
    | LC_ALL=C sort -u > "$_new_baseline" || { echo "write-baseline: oracle failed" >&2; exit 2; }
  mv "$_new_baseline" "$BASELINE"
  echo "wrote $(wc -l < "$BASELINE" | tr -d ' ') baseline entries to $BASELINE ($(grep -c 'UNCLASSIFIED' "$BASELINE" || true) unclassified)"
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
# The regenerated and committed baselines are compared on their first THREE columns only
# (label, path, form): the classification column is human-carried and is checked by row c1.
_regen=$( cd "$REPO_ROOT" && python3 "$ORACLE" baseline "$ROWS" "$CMDS" "$BASELINE" 2>/dev/null \
  | awk -F'\t' '{print $1"\t"$2"\t"$3}' | LC_ALL=C sort -u )
_have=$( awk -F'\t' '{print $1"\t"$2"\t"$3}' "$BASELINE" | LC_ALL=C sort -u )
if [[ -n "$_have" && "$_regen" == "$_have" ]]; then
  pass "b1: the committed baseline equals the regenerated one (no stale or missing entry)"
else
  fail "b1: baseline differs from --write-baseline output: $(diff <(printf '%s\n' "$_have") <(printf '%s\n' "$_regen") | head -6 | tr '\n' ';')"
fi

# Row c1: a baseline row from any non-literal form is CLASSIFIED. A new form cannot turn green merely
# by being baselined: its rows are real reads (which get a covering edge and leave the baseline) or
# recorded false positives with a reason. Every row in the file is checked, not the first.
cases=$((cases + 1))
_unclass=$(awk -F'\t' 'NF>=3 && ($4=="" || $4=="UNCLASSIFIED" || $4 !~ /^false-positive: ./){print $1" | "$2" | "$3" | "$4}' "$BASELINE" | head -3 | tr '\n' ';')
_nonlit=$(awk -F'\t' 'NF>=3{n++} END{print n+0}' "$BASELINE")
if [[ -z "$_unclass" ]]; then
  pass "c1: every non-literal baseline row carries a 'false-positive: <reason>' classification (n=$_nonlit)"
else
  fail "c1: unclassified baseline row(s): $_unclass"
fi

# Row f0 (population floor for the form table): each form in the table sees at least one registration
# in the real corpus, else a form row is dead weight and its fixture rows prove nothing about the repo.
cases=$((cases + 1))
_forms=$( cd "$REPO_ROOT" && python3 "$ORACLE" forms )
_dir_regs=$(python3 - "$ROWS" "$CMDS" "$ORACLE" <<'F0PY'
import os, sys, importlib.util
spec = importlib.util.spec_from_file_location("o", sys.argv[3]); o = importlib.util.module_from_spec(spec); spec.loader.exec_module(o)
rows, cmds = o.load_rows(sys.argv[1]), o.load_cmds(sys.argv[2])
n = 0
for label, argv in cmds.items():
    if rows.get(label, ("",))[0] != "always_on" and not o.code_files(argv) and any(os.path.isdir(t) for t in argv):
        n += 1
print(n)
F0PY
)
if [[ "$_forms" == *"argv-code"* && "$_forms" == *"dir-operand-tests"* ]] && [[ "$_dir_regs" =~ ^[0-9]+$ ]] && (( _dir_regs >= 1 )); then
  pass "f0: the form table lists both forms and the directory-operand form has a real registration (n=$_dir_regs)"
else
  fail "f0: forms='$(tr '\n' ' ' <<<"$_forms")' directory-operand registrations='$_dir_regs'"
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

# d1/d2/d3/d4: the directory-operand form. A registration naming a DIRECTORY and no code file
# (`bun test plugins/soleur/`) reads whatever its test files read. Fixture: a directory with a
# *.test.ts that reads a real knowledge-base file and a scratch-rooted one.
DSYN="$TESTROOT/dsyn"; mkdir -p "$DSYN/sub"
printf 'import { readFileSync } from "node:fs";\nreadFileSync("knowledge-base/legal/article-30-register.md");\n' > "$DSYN/sub/real.test.ts"
printf 'import { join } from "node:path";\nconst p = join(root, "knowledge-base/legal/article-30-register.md");\n' > "$DSYN/sub/scratch.helper.ts"
printf 'SUITE_COMMAND\tdsyn/d\tbun\ttest\t%s/\n' "$DSYN" > "$TESTROOT/cmds-dsyn.tsv"
printf 'AFFECTED_SELECTED\tdsyn/d\t0\tedge:derived\t^scripts/foo.sh\n' > "$TESTROOT/rows-dsyn.tsv"

cases=$((cases + 1))
_rc=0; _od=$( cd "$REPO_ROOT" && python3 "$ORACLE" check "$TESTROOT/rows-dsyn.tsv" "$TESTROOT/cmds-dsyn.tsv" /dev/null 2>&1 ) || _rc=$?
if [[ "$_rc" == "1" ]] && grep -qF $'VIOLATION\tdsyn/d\tknowledge-base/legal/article-30-register.md\tdir-operand-tests' <<<"$_od"; then
  pass "d1: a *.test.ts under a directory operand that reads a real knowledge-base file is flagged, tagged dir-operand-tests"
else
  fail "d1: rc=$_rc — $_od"
fi

cases=$((cases + 1))
printf 'AFFECTED_SELECTED\tdsyn/d\t0\tedge:declared\t^knowledge-base/legal/\n' > "$TESTROOT/rows-dsyn-cov.tsv"
_rc=0; _oc=$( cd "$REPO_ROOT" && python3 "$ORACLE" check "$TESTROOT/rows-dsyn-cov.tsv" "$TESTROOT/cmds-dsyn.tsv" /dev/null 2>&1 ) || _rc=$?
if [[ "$_rc" == "0" ]]; then
  pass "d2: the same registration with a covering edge is clean (the covering edge is what clears it)"
else
  fail "d2: covered fixture still flagged rc=$_rc — $_oc"
fi

# d3: a non-test helper under the directory is not scanned (only the files a runner executes).
cases=$((cases + 1))
if ! grep -qF 'scratch.helper' <<<"$_od" && [[ "$(grep -c $'^VIOLATION\t' <<<"$_od")" == "1" ]]; then
  pass "d3: only the *.test.* file is scanned; a helper (and a scratch-rooted join) adds nothing"
else
  fail "d3: unexpected violations — $_od"
fi

# d4: harness — drop the dir-operand form from a scratch copy of the oracle; d1's fixture must go
# clean (no violation), proving the form row is what produces the finding.
cases=$((cases + 1))
cp "$ORACLE" "$TESTROOT/oracle-noform.py"
_landed=$(grep -c '    ("dir-operand-tests", dir_operand_refs),' "$TESTROOT/oracle-noform.py")
sed -i '/    ("dir-operand-tests", dir_operand_refs),/d' "$TESTROOT/oracle-noform.py"
_rc=0; _on=$( cd "$REPO_ROOT" && python3 "$TESTROOT/oracle-noform.py" check "$TESTROOT/rows-dsyn.tsv" "$TESTROOT/cmds-dsyn.tsv" /dev/null 2>&1 ) || _rc=$?
if [[ "$_landed" == "1" && "$_rc" == "0" && -z "$_on" ]]; then
  pass "d4: without the form row the fixture is invisible (the form row produces the finding; mutation landed once)"
else
  fail "d4: landed=$_landed rc=$_rc out='${_on:0:120}'"
fi

# u1: the c1 predicate rejects UNCLASSIFIED and empty rows and accepts a reasoned one (driven on a copy).
cases=$((cases + 1))
printf 'a\tb\tdir-operand-tests\tUNCLASSIFIED\nc\td\tdir-operand-tests\tfalse-positive: fixture\ne\tf\tdir-operand-tests\t\n' > "$TESTROOT/base-unclass.txt"
_u=$(awk -F'\t' 'NF>=3 && ($4=="" || $4=="UNCLASSIFIED" || $4 !~ /^false-positive: ./){n++} END{print n+0}' "$TESTROOT/base-unclass.txt")
if [[ "$_u" == "2" ]]; then pass "u1: the classification predicate rejects UNCLASSIFIED and empty, accepts a reasoned row"; else fail "u1: predicate flagged $_u rows, expected 2"; fi

echo ""
if (( PASS + FAIL != cases )); then
  echo "[FATAL] verdict mismatch: PASS($PASS)+FAIL($FAIL) != cases($cases) — a row was skipped" >&2
  exit 2
fi
MIN_CASES=19
if (( cases < MIN_CASES )); then
  echo "[FATAL] only $cases cases ran — below the $MIN_CASES floor" >&2
  exit 2
fi
echo "test-affected-kb-consumers: $PASS passed, $FAIL failed of $((PASS + FAIL)) (cases=$cases)"
(( FAIL == 0 )) || exit 1
exit 0
