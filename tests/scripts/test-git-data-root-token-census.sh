#!/usr/bin/env bash
#
# (#8189 Guard 3, ADR-220) The git-data root read token's reference census.
#
# Property: DOPPLER_TOKEN_GIT_DATA_ROOT — the token that reads the key which is root on the host
# holding every connected user's source code — is named under .github/workflows and .github/actions
# ONLY by git-data-cutover.yml job `cutover` (environment web-platform-infra-apply), in exactly the
# secrets-check presence boolean and the key-fetch bind; the `secrets: inherit` callers are the known
# release pair; reusable-release.yml (the inherit receiver) never names it; and nothing reads secrets
# dynamically (`toJSON(secrets)`, `secrets[...]`), which would hand every secret — this one included —
# to a job the name census cannot see.
#
# GitHub secret names and expression function names are CASE-INSENSITIVE, so the census is too:
# `secrets.doppler_token_git_data_root` and `TOJSON( Secrets )` resolve exactly like their canonical
# spellings and must count. A MENTION is the canonical upper-case name anywhere (outside YAML
# comments), or a `secrets.<name>` reference in any letter case. A bare lower-case identifier that is
# not a secrets reference is not one: apply-git-data-root-key.yml names the Terraform resource
# `github_actions_secret.doppler_token_git_data_root` that CREATES the secret, and that is not a read.
#
# WHY IT LIVES HERE. It used to run inside apps/web-platform/infra/git-data-cutover-access.test.sh,
# which infra-validation.yml runs only on infra-path PRs — so a PR touching ONLY some other workflow
# (the likeliest place for a new reference) never ran the census. This suite is registered in
# scripts/test-all.sh's scripts group, which runs on every PR.
#
# Harness conventions (plan › Guard Contract): mutation rows copy the input tree, apply the edit,
# assert it LANDED (diff-line count or fixture written), then require the NAMED census row RED.
# Floors, the instrument self-test and the mutant_red self-test report with printf + exit (ADR-193).
#
# Seam of the SUITE: GDC_GITHUB_DIR (the census input tree; default <repo>/.github).
#
# Run: bash tests/scripts/test-git-data-root-token-census.sh

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
GHDIR="${GDC_GITHUB_DIR:-$ROOT/.github}"

passes=0; fails=0; MUTANTS_RUN=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILURES+=("$1"); fails=$((fails + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

# Instrument self-test (ADR-193): both helpers must move their counters.
_st="$( (pass x >/dev/null; fail y >/dev/null; printf '%s %s %s' "$passes" "$fails" "${#FAILURES[@]}") )"
if [ "$_st" != "1 1 1" ]; then
  printf 'FAIL INSTRUMENT: pass()/fail() self-test read "%s", expected "1 1 1"\n' "$_st" >&2; exit 1
fi

for d in "$GHDIR/workflows" "$GHDIR/actions"; do
  [ -d "$d" ] || { printf 'FAIL SETUP: %s not found\n' "$d" >&2; exit 1; }
done
python3 -c 'import yaml' 2>/dev/null || { printf 'FAIL SETUP: python3 yaml module unavailable\n' >&2; exit 1; }

# Canonical copy of plugins/soleur/test/test-helpers.sh's guard (the fixture-dir-operand-assert
# suite pins every tracked copy byte-identical). Executed as a statement before writes under a
# caller-supplied root so the P1b relative-operand ratchet can see the operand is absolute.
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

T="$(mktemp -d "${TMPDIR}/gd-root-census.XXXXXX")" || { printf 'FAIL SETUP: mktemp\n' >&2; exit 1; }
_REACHED_VERDICT=""; _rc=0
trap '_rc=$?; rm -rf "$T"; if [ "$_rc" -eq 0 ] && [ -z "$_REACHED_VERDICT" ]; then printf "FAIL: suite exited 0 before its verdict\n" >&2; exit 1; fi' EXIT
mkdir -p "$T/mut" || { printf 'FAIL SETUP: mkdir %s/mut\n' "$T" >&2; exit 1; }

printf '\n=== git-data root token reference census (Guard 3, #8189) ===\n\n'

cat > "$T/g3.py" <<'PY'
import sys, os, yaml, json, re
gh = sys.argv[1]
NAME = "DOPPLER_TOKEN_GIT_DATA_ROOT"
# The canonical spelling anywhere, or a secrets.<name> reference in any case and spacing.
REF = re.compile(r"secrets\s*\.\s*" + NAME + r"(?![A-Za-z0-9_])", re.I)
def mentions(text):
    return NAME in text or bool(REF.search(text))
KNOWN_INHERIT = {("version-bump-and-release.yml", "release"), ("web-platform-release.yml", "release")}
# Case-insensitive, arbitrary whitespace: GitHub resolves toJSON( Secrets ) and secrets [ 'x' ].
DYNAMIC = re.compile(r"tojson\s*\(\s*secrets\s*\)|secrets\s*\[", re.I)
out = []
def check(name, cond, detail=""):
    out.append("%s\t%s\t%s" % ("ok" if cond else "FAIL", name, str(detail)[:240].replace("\t", " ").replace("\n", " ")))
def names(v):
    return mentions(json.dumps(v, default=str))
files = []
for sub in ("workflows", "actions"):
    for dp, dn, fn in os.walk(os.path.join(gh, sub)):
        for f in fn: files.append(os.path.join(dp, f))
files.sort()
check("G3a: census scanned >= 1 file under .github/workflows and .github/actions (%d files scanned)" % len(files),
      len(files) >= 1 and any(p.endswith("/workflows/git-data-cutover.yml") for p in files), "%d files scanned" % len(files))
naming, parse_err, inherit, dynamic, reusable_names = [], [], set(), [], False
cut = None
for p in files:
    rel = os.path.relpath(p, gh)
    text = open(p, encoding="utf-8", errors="replace").read()
    if p.endswith((".yml", ".yaml")):
        try: doc = yaml.safe_load(text)
        except Exception as e: parse_err.append(rel); continue
        dumped = json.dumps(doc, default=str)
        if isinstance(doc, dict):
            for j, b in (doc.get("jobs") or {}).items():
                if isinstance(b, dict) and str(b.get("secrets", "")).strip().lower() == "inherit": inherit.add((os.path.basename(p), j))
        if rel == os.path.join("workflows", "git-data-cutover.yml"): cut = doc
    else:
        dumped = text  # no comment semantics outside YAML: any mention counts
    if mentions(dumped): naming.append(rel)
    if DYNAMIC.search(dumped): dynamic.append(rel)
    if os.path.basename(p) == "reusable-release.yml" and mentions(dumped): reusable_names = True
check("G3b: the token is named (outside comments; secrets.<name> in any case) only by workflows/git-data-cutover.yml", naming == [os.path.join("workflows", "git-data-cutover.yml")] and not parse_err, (naming, parse_err))
jobs = (cut or {}).get("jobs") or {}
top = [k for k, v in (cut or {}).items() if k != "jobs" and names(v)]
jn = [j for j, b in jobs.items() if names(b)]
check("G3c: within it only job `cutover` names the token, and no workflow-level key does", jn == ["cutover"] and not top, (jn, top))
env = (jobs.get("cutover") or {}).get("environment")
if isinstance(env, dict): env = env.get("name")
check("G3d: job `cutover` declares environment web-platform-infra-apply", env == "web-platform-infra-apply", env)
steps = (jobs.get("cutover") or {}).get("steps") or []
sites = []
for s in steps:
    if not names(s): continue
    e = s.get("env") or {}
    keys = [k for k, v in e.items() if mentions(str(v))]
    rest = {k: v for k, v in s.items() if k != "env"}
    sites.append((s.get("id"), keys, [e[k] for k in keys], names(rest)))
check("G3e: the token's steps are exactly the secrets check (presence boolean) and the key fetch (value bind)",
      sites == [("secrets_check", ["GIT_DATA_ROOT_TOKEN_PRESENT"], ["${{ secrets.%s != '' }}" % NAME], False),
                ("key_fetch", ["DOPPLER_TOKEN"], ["${{ secrets.%s }}" % NAME], False)], sites)
check("G3f: `secrets: inherit` sites are exactly the known release callers", inherit == KNOWN_INHERIT, sorted(inherit))
check("G3g: no toJSON(secrets) / secrets[...] dynamic secret access anywhere (any case, any spacing)", not dynamic, dynamic)
check("G3h: reusable-release.yml never names the token (any case)", not reusable_names)
print("\n".join(out))
PY
CENSUS_ROWS=8

# census_rows <tsv> — reports every row of one census run through pass()/fail().
census_rows() {
  local n=0 v name detail
  while IFS=$'\t' read -r v name detail; do
    [ -n "$v" ] || continue
    n=$((n + 1))
    if [ "$v" = ok ]; then pass "$name"; else fail "$name" "$detail"; fi
  done < "$1"
  [ "$n" -ge "$CENSUS_ROWS" ] || fail "G3: only $n census verdicts were produced (expected $CENSUS_ROWS) — the census crashed" "$(head -c 300 "$2")"
}
python3 "$T/g3.py" "$GHDIR" > "$T/g3.tsv" 2> "$T/g3.err"
census_rows "$T/g3.tsv" "$T/g3.err"

# wf_row <tsv> <name-prefix> — 1 only when the named row is PRESENT and not ok. An ABSENT row (the
# census crashed on a fixture) returns 0, so a mutant can never read as RED for the wrong reason.
# shellcheck disable=SC2317  # invoked indirectly through mutant_red
wf_row() { awk -F'\t' -v p="$2" 'index($2, p) == 1 { found = 1; if ($1 != "ok") bad = 1 } END { exit (found && bad) ? 1 : 0 }' "$1"; }

_ghcopy() { # <name> — a copy of the census input tree under $T; prints its path
  local d="$T/gh-$1"
  assert_fixture_dir "$d"; assert_fixture_dir "$GHDIR"
  rm -rf "$d"; mkdir -p "$d" && cp -r "$GHDIR/workflows" "$GHDIR/actions" "$d/" || { printf 'FAIL SETUP: gh copy\n' >&2; exit 1; }
  printf '%s' "$d"
}

# ── harness rows ─────────────────────────────────────────────────────────────────────
# `_ghcopy`'s guard runs inside `$( )`, where `exit` kills only the subshell — re-guard every binding.
_gc="$(_ghcopy comment)"; assert_fixture_dir "$_gc"
printf '# mentions DOPPLER_TOKEN_GIT_DATA_ROOT in a comment only\nname: zz-comment\non: workflow_dispatch\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo ok\n' > "$_gc/workflows/zz-comment.yml"
python3 "$T/g3.py" "$_gc" > "$T/g3c.tsv" 2>&1
if grep -qP '^ok\tG3b:' "$T/g3c.tsv"; then pass "H3a: a comment-only mention in another workflow does not count"
else fail "H3a: a comment-only mention was counted" "$(grep G3b "$T/g3c.tsv")"; fi
assert_fixture_dir "$T/gh-empty"; mkdir -p "$T/gh-empty/workflows" "$T/gh-empty/actions"
python3 "$T/g3.py" "$T/gh-empty" > "$T/g3e.tsv" 2>&1
if grep -qP '^FAIL\tG3a:' "$T/g3e.tsv" && grep -q '0 files scanned' "$T/g3e.tsv"; then pass "H3b: an empty scan set is a FAILURE reported as '0 files scanned'"
else fail "H3b: an empty scan set passed" "$(head -2 "$T/g3e.tsv")"; fi
_gc="$(_ghcopy tfaddr)"; assert_fixture_dir "$_gc"
printf 'name: zz-tfaddr\non: workflow_dispatch\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo github_actions_secret.doppler_token_git_data_root\n' > "$_gc/workflows/zz-tfaddr.yml"
python3 "$T/g3.py" "$_gc" > "$T/g3t.tsv" 2>&1
if grep -qP '^ok\tG3b:' "$T/g3t.tsv"; then pass "H3c: a lower-case Terraform resource address (not a secrets. reference) does not count"
else fail "H3c: a non-reference lower-case identifier was counted" "$(grep G3b "$T/g3t.tsv")"; fi

# ── mutation matrix ──────────────────────────────────────────────────────────────────
echo; echo "--- mutation matrix (each row must turn its named census row RED)"
MUTANT=""
mutate() { # <name> <file> <expected-diff-lines> <sed -E program>
  local name="$1" src="$2" want="$3" expr="$4" got
  MUTANT="$T/mut/$name.$(basename "$src")"
  cp "$src" "$MUTANT" || { printf 'FAIL SETUP: mutation copy %s\n' "$name" >&2; exit 1; }
  if ! sed -E -i "$expr" "$MUTANT" 2>"$T/mut/$name.sed.err"; then
    fail "M-$name: mutation sed failed" "$(head -1 "$T/mut/$name.sed.err")"; return 1
  fi
  got="$(diff "$src" "$MUTANT" | grep -cE '^[<>]' || true)"
  if [ "$got" != "$want" ]; then
    fail "M-$name: mutation landed on $got diff line(s), expected $want" "sed -E [$expr]"; return 1
  fi
  MUTANTS_RUN=$((MUTANTS_RUN + 1))
  pass "M-$name: mutation landed on exactly $want diff line(s) of a pristine copy"
}
# fixture_written <name> <file> — the fixture-shaped mutation's landing assertion.
fixture_written() {
  if [ -s "$2" ]; then MUTANTS_RUN=$((MUTANTS_RUN + 1)); pass "M-$1: fixture $(basename "$2") written"; return 0; fi
  fail "M-$1: fixture not written"; return 1
}
mutant_red() { # <name> <case-fn> [args...] — the named case must go RED
  local name="$1"; shift
  if "$@"; then fail "M-$name: the named census row stayed GREEN against the mutant"
  else pass "M-$name: the named census row goes RED against the mutant"; fi
}
# mutant_red self-test (ADR-193), both directions, in a subshell so the counters roll back.
_mr="$( (mutant_red st-green true >/dev/null; printf '%s,%s ' "$passes" "$fails"; mutant_red st-red false >/dev/null; printf '%s,%s' "$passes" "$fails") )"
if [ "$_mr" != "$passes,$((fails + 1)) $((passes + 1)),$((fails + 1))" ]; then
  printf 'FAIL INSTRUMENT: mutant_red self-test read "%s" (from %s,%s) — a GREEN case must fail, a RED case must pass\n' "$_mr" "$passes" "$fails" >&2; exit 1
fi

# shellcheck disable=SC2016  # sed programs and fixture YAML are data
{
# Row 1 — a second job in git-data-cutover.yml referencing the token.
_gm="$(_ghcopy m-secondjob)"; assert_fixture_dir "$_gm"
if mutate g3-second-job "$_gm/workflows/git-data-cutover.yml" 6 '$a\  second:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo x\n        env:\n          T: ${{ secrets.DOPPLER_TOKEN_GIT_DATA_ROOT }}'; then
  cp "$MUTANT" "$_gm/workflows/git-data-cutover.yml"
  python3 "$T/g3.py" "$_gm" > "$T/mut/g3-1.tsv" 2>&1
  mutant_red g3-second-job wf_row "$T/mut/g3-1.tsv" "G3c:"
fi
# Row 2 — remove environment: from cutover.
_gm="$(_ghcopy m-noenv)"; assert_fixture_dir "$_gm"
if mutate g3-no-environment "$_gm/workflows/git-data-cutover.yml" 1 '/^    environment: web-platform-infra-apply$/d'; then
  cp "$MUTANT" "$_gm/workflows/git-data-cutover.yml"
  python3 "$T/g3.py" "$_gm" > "$T/mut/g3-2.tsv" 2>&1
  mutant_red g3-no-environment wf_row "$T/mut/g3-2.tsv" "G3d:"
fi
# Row 3 — a second workflow file referencing the token, sorted after the compliant first.
_gm="$(_ghcopy m-secondwf)"; assert_fixture_dir "$_gm"
printf 'name: zz\non: workflow_dispatch\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    environment: web-platform-infra-apply\n    steps:\n      - run: echo x\n        env:\n          T: ${{ secrets.DOPPLER_TOKEN_GIT_DATA_ROOT }}\n' > "$_gm/workflows/zz-second.yml"
if fixture_written g3-second-workflow "$_gm/workflows/zz-second.yml"; then
  python3 "$T/g3.py" "$_gm" > "$T/mut/g3-3.tsv" 2>&1
  mutant_red g3-second-workflow wf_row "$T/mut/g3-3.tsv" "G3b:"
fi
# Row 4 — the same second reference spelled in lower case (GitHub resolves secret names case-insensitively).
_gm="$(_ghcopy m-lowercase)"; assert_fixture_dir "$_gm"
printf 'name: zz\non: workflow_dispatch\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo x\n        env:\n          T: ${{ secrets.doppler_token_git_data_root }}\n' > "$_gm/workflows/zz-lower.yml"
if fixture_written g3-lowercase-name "$_gm/workflows/zz-lower.yml"; then
  python3 "$T/g3.py" "$_gm" > "$T/mut/g3-4.tsv" 2>&1
  mutant_red g3-lowercase-name wf_row "$T/mut/g3-4.tsv" "G3b:"
fi
# Row 5 — `secrets: inherit` on a new caller.
_gm="$(_ghcopy m-inherit)"; assert_fixture_dir "$_gm"
printf 'name: zz\non: workflow_dispatch\njobs:\n  call:\n    uses: ./.github/workflows/reusable-release.yml\n    secrets: inherit\n' > "$_gm/workflows/zz-caller.yml"
if fixture_written g3-inherit "$_gm/workflows/zz-caller.yml"; then
  python3 "$T/g3.py" "$_gm" > "$T/mut/g3-5.tsv" 2>&1
  mutant_red g3-inherit wf_row "$T/mut/g3-5.tsv" "G3f:"
fi
# Row 6 — dynamic access spelled with odd case and spacing: every secret, this one included.
_gm="$(_ghcopy m-dynamic)"; assert_fixture_dir "$_gm"
printf 'name: zz\non: workflow_dispatch\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo x\n        env:\n          ALL: ${{ TOJSON( Secrets ) }}\n' > "$_gm/workflows/zz-dynamic.yml"
if fixture_written g3-dynamic-spaced "$_gm/workflows/zz-dynamic.yml"; then
  python3 "$T/g3.py" "$_gm" > "$T/mut/g3-6.tsv" 2>&1
  mutant_red g3-dynamic-spaced wf_row "$T/mut/g3-6.tsv" "G3g:"
fi
# Row 7 — the reusable receiver references the token (mixed case, so the case-folding is load-bearing).
_gm="$(_ghcopy m-reusable)"; assert_fixture_dir "$_gm"
if mutate g3-reusable-names "$_gm/workflows/reusable-release.yml" 1 '$a\x-probe: ${{ secrets.Doppler_Token_Git_Data_Root }}'; then
  cp "$MUTANT" "$_gm/workflows/reusable-release.yml"
  python3 "$T/g3.py" "$_gm" > "$T/mut/g3-7.tsv" 2>&1
  mutant_red g3-reusable-names wf_row "$T/mut/g3-7.tsv" "G3h:"
fi
}

# ── FLOOR + LEDGER (ADR-193: printf + exit, never through pass()/fail()) ─────────────
MUTANT_FLOOR=7   # the matrix rows above
if [ "$MUTANTS_RUN" -lt "$MUTANT_FLOOR" ]; then
  printf 'FAIL MUTANT FLOOR: only %s mutants executed, floor is %s — a matrix row did not land or was deleted.\n' "$MUTANTS_RUN" "$MUTANT_FLOOR" >&2
  exit 1
fi
# Assertion FLOOR: census 8 + harness 3 + mutants 7 x 2 = 25 (exact).
FLOOR=25
_ran=$((passes + fails))
if [ "$_ran" -lt "$FLOOR" ]; then
  printf 'FAIL ANTI-VACUITY: only %s assertions ran, floor is %s — cases were deleted or the suite exited early.\n' "$_ran" "$FLOOR" >&2
  exit 1
fi
if [ "${#FAILURES[@]}" -ne "$fails" ]; then
  printf 'FAIL LEDGER: %s failures counted but %s recorded\n' "$fails" "${#FAILURES[@]}" >&2; exit 1
fi
printf '\n=== git-data-root-token-census: %d passed, %d failed ===\n\n' "$passes" "$fails"
_REACHED_VERDICT=1
exit $(( ${#FAILURES[@]} > 0 ))
