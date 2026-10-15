#!/usr/bin/env bash
#
# (#9294 G1, ADR-241 D1 amendment, PR-0) The deploy-channel trio census and its expiring baseline.
#
# PROPERTY. The three deploy-channel credentials -- WEBHOOK_DEPLOY_SECRET and the Cloudflare Access
# client pair (CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET) -- plus the rotation "next" secret
# (WEBHOOK_DEPLOY_SECRET_NEXT) are named, in code, only by files that have an UNEXPIRED row in
# tests/scripts/trio-baseline.tsv, and that file only shrinks. Together the three authenticate
# /hooks/infra-config on web-1 (a path that can replace ci-deploy.sh and read the host credential
# file), so a consumer nobody reviewed is the defect: P5 of the plan.
#
# WHY A SEPARATE SUITE rather than rows in test-infra-privileged-tier-census.sh. That census derives
# Tier-B-ness from reads of TIER_B_NAMES through ONE read shape (`doppler secrets get <name> ...
# prd_terraform`); the `secrets.X` and env-passthrough shapes go through ENV_SECRETS. Adding the trio
# to TIER_B_NAMES turns its row G1g red on the live tree (git-data-cutover, apply-deploy-pipeline-fix
# and others read the trio that way today), and the repo-secret reads are not classified at all. The
# trio moves into TIER_B_NAMES in the PRs that migrate those consumers, when this baseline shrinks.
#
# GUARD CONTRACT (plan, Guard 1). Assembly: every non-test file under the SCOPE directories, derived
# by walking the tree (never a hand list), matched on the NAME as a whole token, case-insensitively
# (Terraform spells them in lower case), on any non-full-line-comment line, whatever the read shape
# (`secrets.X`, `doppler secrets get X`, an `env:` passthrough, a templatefile argument). The
# baseline key is (file, name), not file.
#
# Seams: TRIO_REPO_ROOT (the tree the scan reads; default <repo>), TRIO_BASELINE (default
# tests/scripts/trio-baseline.tsv), TRIO_BASE_REF (the ref whose copy of the baseline is the
# shrink-only base; default the merge-base of HEAD and refs/remotes/origin/main, falling back to
# the origin/main tip), TRIO_TODAY (the date the expiry rows compare against; default today, UTC).
#
# Harness conventions (ADR-193): the instrument self-test drives both helpers once; every mutation
# copies a PRISTINE fixture, asserts the edit LANDED (cmp), then requires the NAMED row RED; the
# control run is asserted all-green first; floors report with printf + exit, never through the
# helpers they backstop.
#
# Run: bash tests/scripts/test-trio-baseline-census.sh

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
REPODIR="${TRIO_REPO_ROOT:-$ROOT}"
BASELINE="${TRIO_BASELINE:-$ROOT/tests/scripts/trio-baseline.tsv}"
TODAY="${TRIO_TODAY:-$(date -u +%F)}"

passes=0; fails=0; MUTANTS_RUN=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILURES+=("$1"); fails=$((fails + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

# Instrument self-test (ADR-193): both helpers must move their counters, or nothing below is
# evidence of anything. Declared AFTER the helpers and BEFORE the first real row.
_st="$( (pass x >/dev/null; fail y >/dev/null; printf '%s %s %s' "$passes" "$fails" "${#FAILURES[@]}") )"
if [ "$_st" != "1 1 1" ]; then
  printf 'FAIL INSTRUMENT: pass()/fail() self-test read "%s", expected "1 1 1"\n' "$_st" >&2; exit 1
fi

python3 -c 'import re, os, sys, datetime' 2>/dev/null || { printf 'FAIL SETUP: python3 unavailable\n' >&2; exit 1; }

# Canonical copy of plugins/soleur/test/test-helpers.sh's guard (the fixture-dir-operand-assert
# suite pins every tracked copy byte-identical).
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

T="$(mktemp -d "${TMPDIR}/trio-baseline-census.XXXXXX")" || { printf 'FAIL SETUP: mktemp\n' >&2; exit 1; }
_REACHED_VERDICT=""; _rc=0
trap '_rc=$?; rm -rf "$T"; if [ "$_rc" -eq 0 ] && [ -z "$_REACHED_VERDICT" ]; then printf "FAIL: suite exited 0 before its verdict\n" >&2; exit 1; fi' EXIT
assert_fixture_dir "$T"
mkdir -p "$T/mut" || { printf 'FAIL SETUP: mkdir %s/mut\n' "$T" >&2; exit 1; }


cat > "$T/trio.py" <<'PY'
import sys, os, re, datetime, argparse

ap = argparse.ArgumentParser()
ap.add_argument("--repo", required=True)
ap.add_argument("--baseline", required=True)
ap.add_argument("--base", default="")      # the merge-base copy of the baseline; "" = no base file (introduction)
ap.add_argument("--today", required=True)
ap.add_argument("--mode", default="check")  # check | emit
a = ap.parse_args()
REPO = a.repo

NAMES = ["WEBHOOK_DEPLOY_SECRET", "WEBHOOK_DEPLOY_SECRET_NEXT", "CF_ACCESS_CLIENT_ID", "CF_ACCESS_CLIENT_SECRET"]
SCOPE = [".github/workflows", ".github/actions", "scripts", "apps/web-platform/scripts", "apps/web-platform/infra"]
TEST_PATH = re.compile(r"(^|/)(test|tests)/|\.test\.|-test\.sh$|/test-|tftest\.hcl$")
SKIP_DIRS = {"node_modules", ".terraform", ".git"}
GROUPS = {"PR-2", "PR-3", "PR-4"}
# The consumer groups of the plan (single-sourced there; this map only labels rows at emit time).
PR3 = {".github/workflows/web-platform-release.yml", ".github/workflows/canary-status.yml"}
PR4_PREFIX = (".github/workflows/cutover-inngest.yml", ".github/workflows/deploy-inngest-image.yml",
              ".github/workflows/restart-inngest-server.yml", ".github/workflows/scheduled-inngest-health.yml",
              ".github/workflows/scheduled-followthrough-sweeper.yml", "scripts/followthroughs/",
              "apps/web-platform/scripts/github-app-key-status.sh")

def group_of(rel):
    if rel in PR3:
        return "PR-3"
    if rel.startswith(PR4_PREFIX):
        return "PR-4"
    return "PR-2"

out = []
def check(name, cond, detail=""):
    out.append("%s\t%s\t%s" % ("ok" if cond else "FAIL", name, str(detail)[:400].replace("\t", " ").replace("\n", " ")))

def name_re(n):
    return re.compile(r"(?<![A-Za-z0-9_])" + re.escape(n) + r"(?![A-Za-z0-9_])", re.I)
NAME_RES = {n: name_re(n) for n in NAMES}
HCLOUD = name_re("HCLOUD_TOKEN")
FALLBACK = re.compile(r"\|\|\s*doppler\s+secrets\s+get\s+([A-Za-z_][A-Za-z0-9_]*)")

def code_lines(text):
    for ln in text.split("\n"):
        s = ln.lstrip()
        if s.startswith("#") or s.startswith("//"):
            continue
        yield ln

# ── 1. the scan: every non-test file under SCOPE ───────────────────────────────────────
files = []
for sub in SCOPE:
    top = os.path.join(REPO, sub)
    for dp, dn, fn in os.walk(top):
        dn[:] = [d for d in dn if d not in SKIP_DIRS]
        for f in fn:
            rel = os.path.relpath(os.path.join(dp, f), REPO)
            if TEST_PATH.search(rel):
                continue
            files.append(rel)
files.sort()

pairs, fallbacks, hcloud_files = set(), set(), set()
for rel in files:
    try:
        text = open(os.path.join(REPO, rel), encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    body = "\n".join(code_lines(text))
    hit = False
    for n in NAMES:
        if NAME_RES[n].search(body):
            pairs.add((rel, n)); hit = True
    if hit:
        for ln in code_lines(text):
            if any(NAME_RES[n].search(ln) for n in NAMES):
                for m in FALLBACK.finditer(ln):
                    if m.group(1).upper() not in NAMES:
                        fallbacks.add((rel, "FALLBACK:" + m.group(1).upper()))
        if HCLOUD.search(body):
            hcloud_files.add(rel)

if a.mode == "emit":
    for rel, n in sorted(pairs):
        print("%s\t%s\t%s\t%s" % (rel, n, "2026-11-30", "#9294:" + group_of(rel)))
    for rel, n in sorted(fallbacks):
        print("%s\t%s\t%s\t%s" % (rel, n, "2026-11-30", "#9294:" + group_of(rel)))
    sys.exit(0)

# ── 2. the baseline ────────────────────────────────────────────────────────────────────
def read_baseline(path):
    rows, bad, dup = [], [], []
    seen = set()
    if not os.path.isfile(path):
        return None, ["missing file"], []
    for i, ln in enumerate(open(path, encoding="utf-8").read().split("\n"), 1):
        if not ln.strip() or ln.startswith("#"):
            continue
        c = ln.split("\t")
        if len(c) != 4 or not all(x.strip() for x in c):
            bad.append("line %d: need 4 non-empty tab-separated columns" % i); continue
        f, n, exp, iss = c
        try:
            datetime.date.fromisoformat(exp)
        except ValueError:
            bad.append("line %d: expiry %r is not YYYY-MM-DD" % (i, exp)); continue
        if n not in NAMES and not n.startswith("FALLBACK:"):
            bad.append("line %d: unknown name %r" % (i, n)); continue
        m = re.fullmatch(r"#9294:(PR-[234])", iss)
        if not m:
            bad.append("line %d: issue column %r is not #9294:PR-2|PR-3|PR-4" % (i, iss)); continue
        key = (f, n)
        if key in seen:
            dup.append("%s %s" % key)
        seen.add(key)
        rows.append((f, n, exp, iss))
    return rows, bad, dup

rows, bad, dup = read_baseline(a.baseline)
base_rows = None
if a.base:
    base_rows, _b, _d = read_baseline(a.base)

check("T0: the scan walked a non-empty file set (%d non-test files under %d scope dirs)" % (len(files), len(SCOPE)),
      len(files) >= 1, "files=%d" % len(files))
check("T5: the baseline is well-formed: 4 non-empty columns, a valid expiry, a known name, a #9294:PR-n issue tag, no duplicate (file, name) row",
      rows is not None and not bad and not dup, (bad + dup)[:6])
brs = rows or []
bkeys = {(f, n) for f, n, _e, _i in brs}
need = pairs | fallbacks
unbased = sorted("%s %s" % p for p in need if p not in bkeys)
check("T1: every (file, name) that names a trio credential in code has a baseline row (a new consumer of the deploy channel needs a reviewed row) [%d pairs]" % len(pairs),
      not unbased, unbased[:8])
stale = sorted("%s %s" % k for k in bkeys if k not in need)
check("T2: every baseline row has a live (file, name) read (a consumer that moved must delete its row)", not stale, stale[:8])
expired = sorted("%s %s (%s)" % (f, n, e) for f, n, e, _i in brs if e < a.today)
check("T3: no baseline row is past its expiry (today %s): an expired row forces the move or a reviewed re-date" % a.today, not expired, expired[:8])
if a.base:
    bb = {(f, n) for f, n, _e, _i in (base_rows or [])}
    grown = sorted("%s %s" % k for k in bkeys if k not in bb)
    check("T4: the baseline only shrinks against its merge-base copy (a row absent at the base is a new consumer) [%d base rows]" % len(bb),
          base_rows is not None and not grown, grown[:8])
else:
    check("T4: no base copy of the baseline exists (introduction); the shrink-only comparison starts with the next change", True, "base=absent")
creep = sorted(f for f, _n, _e, iss in brs if iss.endswith(("PR-3", "PR-4")) and f in hcloud_files)
check("T7: no file in the PR-3/PR-4 groups names HCLOUD_TOKEN (the narrow carrier must not drag the host-destroy credential in)", not creep, creep[:8])

# ── 3. the HMAC stays out of Terraform state (plan Guard 1, assembly of the state attributes) ─
def tf_text(rel):
    return "\n".join(code_lines(open(os.path.join(REPO, rel), encoding="utf-8", errors="replace").read()))

def balanced(text, i):
    """index just past the bracket group opening at text[i]"""
    pair = {"(": ")", "[": "]", "{": "}"}
    stack, k = [], i
    while k < len(text):
        c = text[k]
        if c in pair:
            stack.append(pair[c])
        elif stack and c == stack[-1]:
            stack.pop()
            if not stack:
                return k + 1
        k += 1
    return len(text)

SECRETISH = re.compile(r"webhook_deploy_secret|hooks_json", re.I)
tf_rels = [f for f in files if f.startswith("apps/web-platform/infra/") and f.endswith(".tf") and "/" not in f[len("apps/web-platform/infra/"):]]
h1, h2, h3 = [], [], []
for rel in tf_rels:
    t = tf_text(rel)
    for m in re.finditer(r"triggers_replace\s*=\s*", t):
        s = m.end()
        j = re.search(r"[\(\[\{]", t[s:])
        if not j:
            continue
        e = balanced(t, s + j.start())
        expr = t[s:e]
        if SECRETISH.search(expr) and not re.match(r"\s*sha256\(", expr):
            h1.append("%s:%d" % (rel, t.count("\n", 0, m.start()) + 1))
    for m in re.finditer(r'^\s*output\s+"[^"]+"\s*\{', t, re.M):
        e = balanced(t, m.end() - 1)
        if SECRETISH.search(t[m.end():e]):
            h2.append("%s:%d" % (rel, t.count("\n", 0, m.start()) + 1))
    for m in re.finditer(r'^\s*resource\s+"terraform_data"\s+"[^"]+"\s*\{', t, re.M):
        e = balanced(t, m.end() - 1)
        body = t[m.end():e]
        for im in re.finditer(r"^\s*input\s*=\s*", body, re.M):
            k = re.search(r"[\(\[\{\"']", body[im.end():])
            ee = balanced(body, im.end() + k.start()) if k and body[im.end() + k.start()] in "([{" else body.find("\n", im.end())
            if SECRETISH.search(body[im.end():ee]):
                h3.append("%s:%d" % (rel, t.count("\n", 0, m.start()) + 1))
check("H1: every triggers_replace that references the webhook secret or the rendered hooks.json is wrapped in sha256( (the state keeps the hash, not the value) [%d .tf files]" % len(tf_rels),
      not h1, h1[:6])
check("H2: no output block references the webhook secret or the rendered hooks.json (outputs sit in state in plaintext)", not h2, h2[:6])
check("H3: no terraform_data input references the webhook secret or the rendered hooks.json (input is stored in state)", not h3, h3[:6])

for l in out:
    print(l)
print("TRIO_FILES_SCANNED=%d" % len(files), file=sys.stderr)
print("TRIO_PAIRS=%d FALLBACKS=%d" % (len(pairs), len(fallbacks)), file=sys.stderr)
PY

# --emit-baseline: print the DERIVED baseline rows for the live tree (never hand-written).
if [ "${1:-}" = "--emit-baseline" ]; then
  python3 "$T/trio.py" --repo "$REPODIR" --baseline /dev/null --today "$TODAY" --mode emit
  _emit_rc=$?
  _REACHED_VERDICT=1
  exit "$_emit_rc"
fi

printf '\n=== deploy-channel trio census (G1, PR-0; #9294, ADR-241) ===\n\n'

# run_trio <repo> <baseline> <base-or-empty> <out>  — writes the TSV rows to <out>
run_trio() {
  python3 "$T/trio.py" --repo "$1" --baseline "$2" --base "$3" --today "$TODAY" > "$4" 2> "$4.err"
  return $?
}
# row_state <out> <ROWID>  — prints ok|FAIL|MISSING for the row whose name starts with "<ROWID>:"
row_state() {
  local s
  s="$(awk -F'\t' -v id="$2" 'index($2, id ":") == 1 {print $1; exit}' "$1")"
  printf '%s' "${s:-MISSING}"
}
# all_ok <out>  — true when every row in <out> is ok and at least one row exists
all_ok() {
  [ -s "$1" ] && ! awk -F'\t' '$1 != "ok" {bad=1} END {exit bad ? 0 : 1}' "$1"
}

# ── A. the live tree ─────────────────────────────────────────────────────────────────────
assert_fixture_dir "$REPODIR"
_mb="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$REPODIR" merge-base HEAD refs/remotes/origin/main 2>/dev/null)" || _mb=""
if [ -n "${TRIO_BASE_REF:-}" ]; then _base_ref="$TRIO_BASE_REF"; _arm=override
elif [ -n "$_mb" ]; then _base_ref="$_mb"; _arm=merge-base
else _base_ref="refs/remotes/origin/main"; _arm=fallback; fi
printf 'TRIO_BASE_ARM=%s ref=%s\n' "$_arm" "${_base_ref//[[:cntrl:]]/?}" >&2
BASEFILE=""
if env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$REPODIR" show "${_base_ref}:tests/scripts/trio-baseline.tsv" > "$T/base.tsv" 2>/dev/null; then
  BASEFILE="$T/base.tsv"
fi

run_trio "$REPODIR" "$BASELINE" "$BASEFILE" "$T/live.tsv"; _live_rc=$?
if [ "$_live_rc" -ne 0 ]; then
  fail "A0: the scanner ran on the live tree" "rc=$_live_rc: $(head -c 300 "$T/live.tsv.err")"
else
  pass "A0: the scanner ran on the live tree"
fi
while IFS=$'\t' read -r _st _nm _dt; do
  [ -n "${_st:-}" ] || continue
  if [ "$_st" = "ok" ]; then pass "live $_nm"; else fail "live $_nm" "$_dt"; fi
done < "$T/live.tsv"
_nlive="$(grep -c . "$T/live.tsv")"
if [ "$_nlive" -eq 10 ]; then pass "A1: the live run produced all 10 rows ($_nlive)"; else fail "A1: the live run produced all 10 rows" "got $_nlive"; fi
_scanned="$(sed -n 's/^TRIO_FILES_SCANNED=//p' "$T/live.tsv.err")"
if [ "${_scanned:-0}" -ge 100 ]; then pass "A2: the live scan covered at least 100 non-test files (${_scanned})"; else fail "A2: the live scan covered at least 100 non-test files" "scanned=${_scanned:-0}"; fi

# ── B. the synthetic fixture (the smallest fully compliant tree) ─────────────────────────
FX="$T/fx"
assert_fixture_dir "$FX"
mkdir -p "$FX/.github/workflows" "$FX/scripts" "$FX/apps/web-platform/infra" "$FX/apps/web-platform/scripts" "$FX/.github/actions" || { printf 'FAIL SETUP: mkdir fixture\n' >&2; exit 1; }
cat > "$FX/.github/workflows/rel.yml" <<'EOF'
name: rel
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - run: echo "deploy"
        env:
          WEBHOOK_DEPLOY_SECRET: ${{ secrets.WEBHOOK_DEPLOY_SECRET }}
EOF
cat > "$FX/scripts/probe.sh" <<'EOF'
#!/usr/bin/env bash
# a comment that names CF_ACCESS_CLIENT_SECRET must not create a row
id="$(doppler secrets get CF_ACCESS_CLIENT_ID --plain)"
EOF
cat > "$FX/apps/web-platform/infra/server.tf" <<'EOF'
locals {
  hooks_json = templatefile("${path.module}/hooks.json.tmpl", {
    webhook_deploy_secret = var.webhook_deploy_secret
  })
}
resource "terraform_data" "deploy_pipeline_fix" {
  triggers_replace = sha256(join(",", [
    file("${path.module}/a.sh"),
    local.hooks_json,
  ]))
}
EOF
cat > "$FX/.github/actions/keep.yml" <<'EOF'
name: keep
EOF
TAB=$'\t'
BASE_ROWS="# fixture baseline
.github/workflows/rel.yml${TAB}WEBHOOK_DEPLOY_SECRET${TAB}2099-01-01${TAB}#9294:PR-3
apps/web-platform/infra/server.tf${TAB}WEBHOOK_DEPLOY_SECRET${TAB}2099-01-01${TAB}#9294:PR-2
scripts/probe.sh${TAB}CF_ACCESS_CLIENT_ID${TAB}2099-01-01${TAB}#9294:PR-2"
printf '%s\n' "$BASE_ROWS" > "$T/fx.tsv"
cp "$T/fx.tsv" "$T/fx-base.tsv"

run_trio "$FX" "$T/fx.tsv" "$T/fx-base.tsv" "$T/ctl.tsv"
if all_ok "$T/ctl.tsv"; then pass "B0: the control run on the compliant fixture is all green (a red control voids every mutant)"
else fail "B0: the control run on the compliant fixture is all green" "$(grep -v '^ok' "$T/ctl.tsv" | head -c 400)"; fi

# mutant <id> <row> <desc> — expects the caller to have prepared $T/mut/<id>/{fx,tsv,base} and the landed-check
# result in $T/mut/<id>/landed (the string "landed" when the edit changed the pristine copy).
mutant() {
  local id="$1" row="$2" desc="$3" d="$T/mut/$1"
  MUTANTS_RUN=$((MUTANTS_RUN + 1))
  if [ "$(cat "$d/landed" 2>/dev/null)" = "landed" ]; then pass "$id lands: $desc"; else fail "$id lands: $desc" "the edit did not change the pristine copy"; return; fi
  run_trio "$d/fx" "$d/tsv" "$d/base" "$d/out"
  if [ "$(row_state "$d/out" "$row")" = "FAIL" ]; then pass "$id: $row is RED"; else fail "$id: $row is RED" "state=$(row_state "$d/out" "$row"); $(head -c 200 "$d/out")"; fi
}
# prep <id> — fresh copy of the pristine fixture; sets D
prep() {
  D="$T/mut/$1"
  assert_fixture_dir "$D"
  rm -rf "$D"; mkdir -p "$D" || { printf 'FAIL SETUP: mkdir %s\n' "$D" >&2; exit 1; }
  cp -R "$FX" "$D/fx" && cp "$T/fx.tsv" "$D/tsv" && cp "$T/fx-base.tsv" "$D/base" || { printf 'FAIL SETUP: copy fixture for %s\n' "$1" >&2; exit 1; }
}
landed_dir() { if diff -r -q "$FX" "$D/fx" >/dev/null 2>&1 && cmp -s "$T/fx.tsv" "$D/tsv" && cmp -s "$T/fx-base.tsv" "$D/base"; then printf 'unchanged' > "$D/landed"; else printf 'landed' > "$D/landed"; fi; }

# M1 — a new workflow reading secrets.WEBHOOK_DEPLOY_SECRET with no baseline row
prep m1
printf 'name: new\njobs:\n  j:\n    runs-on: x\n    env:\n      S: ${{ secrets.WEBHOOK_DEPLOY_SECRET }}\n' > "$D/fx/.github/workflows/new.yml"
landed_dir; mutant m1 T1 "a new consumer with no baseline row"

# M2 — a baseline row absent at the base copy (shrink-only)
prep m2
printf '.github/workflows/rel.yml%sCF_ACCESS_CLIENT_ID%s2099-01-01%s#9294:PR-3\n' "$TAB" "$TAB" "$TAB" >> "$D/tsv"
printf 'name: x\nenv:\n  I: ${{ secrets.CF_ACCESS_CLIENT_ID }}\n' >> "$D/fx/.github/workflows/rel.yml"
landed_dir; mutant m2 T4 "a baseline row (and its read) absent at the merge-base copy"

# M3 — a stale row: the consumer no longer reads the name
prep m3
printf 'scripts/gone.sh%sWEBHOOK_DEPLOY_SECRET%s2099-01-01%s#9294:PR-2\n' "$TAB" "$TAB" "$TAB" >> "$D/tsv"
printf 'scripts/gone.sh%sWEBHOOK_DEPLOY_SECRET%s2099-01-01%s#9294:PR-2\n' "$TAB" "$TAB" "$TAB" >> "$D/base"
landed_dir; mutant m3 T2 "a baseline row whose consumer no longer reads the name"

# M4 — a past expiry
prep m4
sed -i 's/2099-01-01/2020-01-01/' "$D/tsv" "$D/base"
landed_dir; mutant m4 T3 "every baseline row past its expiry"

# M5 — the narrow carrier must not drag the host-destroy credential in: HCLOUD_TOKEN in a PR-3 file
prep m5
printf 'env2:\n  H: ${{ secrets.HCLOUD_TOKEN }}\n' >> "$D/fx/.github/workflows/rel.yml"
landed_dir; mutant m5 T7 "HCLOUD_TOKEN named in an already-baselined PR-3 file"

# M6 — the scan walks nothing (the empty file set)
prep m6
rm -rf "$D/fx/.github" "$D/fx/scripts" "$D/fx/apps"; mkdir -p "$D/fx/empty"
landed_dir; mutant m6 T0 "an empty scan set"

# M7 — a file that already has one compliant baselined read gains a second trio name via env passthrough
prep m7
printf '  more: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}\n' >> "$D/fx/.github/workflows/rel.yml"
landed_dir; mutant m7 T1 "a second trio name added to a baselined file (keyed by (file, name), not file)"

# M8 — a silent fallback to another credential on a line that reads a trio name
prep m8
printf 'x="$(doppler secrets get CF_ACCESS_CLIENT_ID --plain || doppler secrets get CI_SSH_ACCESS_TOKEN_ID --plain)"\n' >> "$D/fx/scripts/probe.sh"
landed_dir; mutant m8 T1 "a fallback pair with no baseline row"

# M9 — a triggers_replace that carries the rendered hooks.json unhashed
prep m9
sed -i 's/triggers_replace = sha256(join(",", \[/triggers_replace = (join(",", [/; s/^  \]))$/  ])) /' "$D/fx/apps/web-platform/infra/server.tf"
sed -i 's/^  ])) $/  ])/' "$D/fx/apps/web-platform/infra/server.tf"
landed_dir; mutant m9 H1 "triggers_replace not wrapped in sha256("

# M10 — an output block that exposes the webhook secret
prep m10
printf 'output "leak" {\n  value = var.webhook_deploy_secret\n}\n' >> "$D/fx/apps/web-platform/infra/server.tf"
landed_dir; mutant m10 H2 "an output that references the webhook secret"

# M11 — a terraform_data input that stores the rendered hooks.json
prep m11
printf 'resource "terraform_data" "bad" {\n  input = local.hooks_json\n}\n' >> "$D/fx/apps/web-platform/infra/server.tf"
landed_dir; mutant m11 H3 "a terraform_data input that references the rendered hooks.json"

# M12 — a duplicate baseline row
prep m12
printf '.github/workflows/rel.yml%sWEBHOOK_DEPLOY_SECRET%s2099-01-01%s#9294:PR-3\n' "$TAB" "$TAB" "$TAB" >> "$D/tsv"
landed_dir; mutant m12 T5 "a duplicate (file, name) baseline row"

# M13 — an issue tag outside the three groups
prep m13
sed -i 's/#9294:PR-3/#9294:PR-9/' "$D/tsv"
landed_dir; mutant m13 T5 "a baseline row tagged outside PR-2/PR-3/PR-4"

# Harness rows. (1) The introduction case: no base copy exists, the shrink-only row must NOT red.
run_trio "$FX" "$T/fx.tsv" "" "$T/intro.tsv"
if [ "$(row_state "$T/intro.tsv" T4)" = "ok" ] && all_ok "$T/intro.tsv"; then pass "C1: with no base copy of the baseline (introduction) the run is all green"
else fail "C1: with no base copy of the baseline (introduction) the run is all green" "$(grep -v '^ok' "$T/intro.tsv" | head -c 300)"; fi

# (2) A must-PASS input that is NOT the canonical: different indentation and a comment-only mention.
prep c2
printf '        # CF_ACCESS_CLIENT_SECRET named only in a comment\n      - run: echo "a   trio:   WEBHOOK_DEPLOY_SECRET   is baselined"\n' >> "$D/fx/.github/workflows/rel.yml"
run_trio "$D/fx" "$D/tsv" "$D/base" "$D/out"
if all_ok "$D/out"; then pass "C2: a comment-only mention and a re-indented baselined read stay green"
else fail "C2: a comment-only mention and a re-indented baselined read stay green" "$(grep -v '^ok' "$D/out" | head -c 300)"; fi

# (3) The name match is a WHOLE token: WEBHOOK_DEPLOY_SECRET_NEXT is its own name, not a hit on the base name.
prep c3
printf 'S: ${{ secrets.WEBHOOK_DEPLOY_SECRET_NEXT }}\n' > "$D/fx/scripts/nxt.sh"
run_trio "$D/fx" "$D/tsv" "$D/base" "$D/out"
if [ "$(row_state "$D/out" T1)" = "FAIL" ] && grep -q 'WEBHOOK_DEPLOY_SECRET_NEXT' "$D/out"; then pass "C3: the rotation next-secret is its own name (a bare read needs its own row)"
else fail "C3: the rotation next-secret is its own name (a bare read needs its own row)" "$(head -c 300 "$D/out")"; fi

# (4) A mutation that did not land is detected (the landed check itself is live).
prep c4
landed_dir
if [ "$(cat "$D/landed")" = "unchanged" ]; then pass "C4: an unedited fixture copy reads as 'unchanged' (the landed check can fail)"
else fail "C4: an unedited fixture copy reads as 'unchanged' (the landed check can fail)" "read: $(cat "$D/landed")"; fi

# Floors. MUTANT_FLOOR is exact: 13 mutants (M1-M13).
MUTANT_FLOOR=13
if [ "$MUTANTS_RUN" -lt "$MUTANT_FLOOR" ]; then
  printf 'FAIL MUTANT FLOOR: only %s mutants executed, floor is %s -- a matrix row did not land or was deleted.\n' "$MUTANTS_RUN" "$MUTANT_FLOOR" >&2
  exit 1
fi
if [ "$MUTANTS_RUN" -gt "$MUTANT_FLOOR" ]; then
  printf 'FAIL MUTANT FLOOR: %s mutants executed but MUTANT_FLOOR is %s -- it is exact; raise it to %s.\n' "$MUTANTS_RUN" "$MUTANT_FLOOR" "$MUTANTS_RUN" >&2
  exit 1
fi
# Assertion FLOOR (exact): live 10 + A0..A2 3 + B0 1 + 13 mutants x 2 (landing + verdict) + C1..C4 4 = 44.
_ran=$((passes + fails))
FLOOR=44
if [ "$_ran" -lt "$FLOOR" ]; then
  printf 'FAIL ANTI-VACUITY: only %s assertions ran, floor is %s -- cases were deleted or the suite exited early.\n' "$_ran" "$FLOOR" >&2
  exit 1
fi
if [ "$_ran" -gt "$FLOOR" ]; then
  printf 'FAIL ANTI-VACUITY: %s assertions ran but FLOOR is %s -- it is exact; raise it to %s.\n' "$_ran" "$FLOOR" "$_ran" >&2
  exit 1
fi
if [ "${#FAILURES[@]}" -ne "$fails" ]; then
  printf 'FAIL LEDGER: %s failures counted but %s recorded\n' "$fails" "${#FAILURES[@]}" >&2; exit 1
fi
printf '\n=== trio-baseline-census: %d passed, %d failed ===\n\n' "$passes" "$fails"
_REACHED_VERDICT=1
exit $(( ${#FAILURES[@]} > 0 ))
