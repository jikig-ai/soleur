#!/usr/bin/env bash
# shellcheck disable=SC2016  # single-quoted fixtures are literal shell text by design
# Mutation attestation for scan-workflow.test.sh (#6572).
#
# WHY THIS FILE EXISTS
# ====================
# scan-workflow.test.sh had 7 checks shaped `<producer> | grep -q P` under
# `set -uo pipefail`. grep -q exits on first match, the producer's next write()
# takes SIGPIPE (141), and pipefail promotes 141 to the pipeline status —
# inverting the `if`. At the match⇒fail sites that inverts INTO A SILENT PASS,
# including the file's self-described headline assertion.
#
# The fix (capture once, match a here-string) and its residual-shape guard are
# only worth what their evidence is worth. Asserted in a comment that evidence is
# prose; asserted here it is re-checked on every CI run. The sibling precedent
# inngest-rls/inngest-rls-mutation.test.sh exists because a session crash
# destroyed exactly such an ad-hoc matrix — this file is that lesson applied
# rather than re-learned.
#
# WHAT IT PROVES (every half is load-bearing)
#   D1  — the DIFFERENTIAL: at a size-amplified producer the unfixed shape
#         false-FAILs and the fixed shape does not. This is the ONLY test that
#         distinguishes them; the guard passes on an unmutated tree either way,
#         so any "run it N times" check is green on both arms and proves nothing.
#   D2  — the issue's OWN preferred fix (printf | grep -q) false-FAILs too, so a
#         future "simplification" back to it silently restores the bug.
#   R1  — the residual guard goes RED when a site is reverted to the piped form.
#   R2  — ...and GREEN on the pristine file. A guard that fired on everything
#         would pass R1 for the wrong reason; RED-only evidence cannot tell the
#         two apart.
#   N1  — each of the guard's three normalisations (comments, strings, folding)
#         is necessary: mutate one out and a real bug escapes or the file
#         false-FAILs. Without this, a "simplification" of the pipeline reads as
#         harmless.
#   M1  — fail-CLOSED polarity: removing a sourced lib makes the guard FAIL.
#   M2  — fail-OPEN polarity: injecting the forbidden .lints[]? idiom makes the
#         guard FAIL. Injection position is pinned at code line 1 — at EOF this
#         mutation is vacuous (the unfixed file "passes" too).
#
# ISOLATION: mutations are applied to sandbox copies under $(mktemp -d) — the
# guard copy sits at the same depth scan-workflow.test.sh resolves REPO_ROOT
# through, and the subject is reached via SCRIPT_OVERRIDE. There is no path by
# which an interrupted run leaves a tracked file mutated.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$DIR/../../../.." && pwd)"
GUARD="$DIR/scan-workflow.test.sh"
REAL_SCRIPT="$REPO_ROOT/scripts/supabase-advisor-scan.sh"

fails=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; fails=$((fails + 1)); }

for f in "$GUARD" "$REAL_SCRIPT"; do
  [[ -f "$f" ]] || { printf 'FATAL: missing %s\n' "$f" >&2; exit 1; }
done

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT INT TERM HUP

# A mutation that does not land reports the BASELINE result, which reads exactly
# like "the guard caught nothing to catch". Every mutation below asserts it landed.
assert_mutated() {
  # $1 = original, $2 = mutated, $3 = label
  if cmp -s "$1" "$2"; then
    fail "$3" "MUTATION DID NOT LAND — this result is the baseline, not evidence"
    return 1
  fi
  return 0
}

echo "== D: the differential (the only test that distinguishes fixed from unfixed) =="
# Amplify the producer: keep the matched line early (earliest match => longest
# remaining write => most SIGPIPE-prone) and append non-comment padding. The
# producer strips ^\s*#, so comment padding would be a no-op.
AMP="$SANDBOX/amplified.sh"
{
  echo '#!/usr/bin/env bash'
  echo 'SCRIPT_DIR="$(dirname "$0")"'
  echo '. "${SCRIPT_DIR}/lib/strip-log-injection.sh"'
  for i in $(seq 1 20000); do
    echo "pad_${i}=\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\""
  done
} > "$AMP"
PAT='^[[:space:]]*\.[[:space:]].*lib/strip-log-injection\.sh'
N=40

count_false_negatives() {  # $1 = shape id; echoes the count over N runs
  local n=0 i
  for ((i = 0; i < N; i++)); do
    case "$1" in
      piped)   ( set -uo pipefail; grep -vE '^\s*#' "$AMP" | grep -qE "$PAT" ) ;;
      printf)  ( set -uo pipefail; c="$(grep -vE '^\s*#' "$AMP")"; printf '%s' "$c" | grep -qE "$PAT" ) ;;
      heredoc) ( set -uo pipefail; c="$(grep -vE '^\s*#' "$AMP")"; grep -qE "$PAT" <<<"$c" ) ;;
    esac || n=$((n + 1))
  done
  printf '%s' "$n"
}

piped_fn="$(count_false_negatives piped)"
printf_fn="$(count_false_negatives printf)"
heredoc_fn="$(count_false_negatives heredoc)"

# D1 — both halves. The unfixed shape must false-FAIL; the fixed shape must not.
if [[ "$piped_fn" == "$N" ]]; then
  pass "D1a unfixed shape false-FAILs $piped_fn/$N on a line that IS present"
else
  fail "D1a unfixed shape false-FAILs" "got $piped_fn/$N — the amplification is no longer arming SIGPIPE, so D1b proves nothing"
fi
if [[ "$heredoc_fn" == "0" ]]; then
  pass "D1b fixed shape (here-string) false-FAILs 0/$N on the same input"
else
  fail "D1b fixed shape is clean" "here-string form false-FAILed $heredoc_fn/$N — the fix does not hold"
fi
# D2 — the issue's own preferred fix is NOT a fix. Pins it against a future revert.
if [[ "$printf_fn" == "$N" ]]; then
  pass "D2 'printf \$var | grep -q' false-FAILs $printf_fn/$N too (still a producer feeding a pipe)"
else
  fail "D2 printf form is unsafe" "got $printf_fn/$N — re-verify before anyone 'simplifies' the here-strings back to a pipe"
fi

echo "== R: the residual-shape guard is non-vacuous (both halves) =="
# The guard greps ${BASH_SOURCE[0]}, so SCRIPT_OVERRIDE cannot reach it — the
# guard itself must be copied. It derives REPO_ROOT as $DIR/../../../.., so the
# copy must sit at that same depth AND that root must contain every artifact the
# guard reads, or it FATALs on a missing file and every assertion below silently
# measures the FATAL instead of the residual check. Mirror the repo by symlink:
# read-only for the guard, and no tracked file is ever written.
PROBE_DIR="$SANDBOX/apps/web-platform/infra/supabase-advisor"
mkdir -p "$PROBE_DIR" "$SANDBOX/apps/web-platform/infra"
for top in .github scripts knowledge-base .claude tests .git; do
  ln -sfn "$REPO_ROOT/$top" "$SANDBOX/$top"
done
ln -sfn "$REPO_ROOT/apps/web-platform/server" "$SANDBOX/apps/web-platform/server"
ln -sfn "$REPO_ROOT/apps/web-platform/infra/sentry" "$SANDBOX/apps/web-platform/infra/sentry"

PRISTINE="$PROBE_DIR/pristine.test.sh"
cp "$GUARD" "$PRISTINE"

# Precondition: the mirror must be good enough that the guard runs to completion.
# Without this, a broken mirror reads as "the guard passed/failed" and R1/R2/N1
# become vacuous.
out="$(cd "$REPO_ROOT" && bash "$PRISTINE" 2>&1)"
if grep -qE '^FATAL: missing' <<<"$out"; then
  fail "sandbox mirror is complete" "the guard copy FATALs on a missing artifact — every R/N result below would measure the mirror, not the guard: $(grep -m1 '^FATAL' <<<"$out")"
fi

# R2 (GREEN half) — the pristine copy's residual check must pass.
if grep -qF 'ok   every check matches a here-string' <<<"$out"; then
  pass "R2 pristine guard reports the residual check GREEN"
else
  fail "R2 pristine guard is GREEN" "the residual check did not pass on an unmutated copy — R1 below would then be meaningless"
fi

# R1 (RED half) — revert ONE site to the piped form.
MUT="$PROBE_DIR/reverted.test.sh"
sed 's|if grep -qF '"'"'\.lints\[\]?'"'"' <<<"\$script_code"; then|if printf '"'"'%s'"'"' "$script_code" \| grep -qF '"'"'.lints[]?'"'"'; then|' "$PRISTINE" > "$MUT"
if assert_mutated "$PRISTINE" "$MUT" "R1 residual guard goes RED"; then
  out="$(cd "$REPO_ROOT" && bash "$MUT" 2>&1)"
  if grep -qF 'FAIL no early-exit-pipe form remains' <<<"$out"; then
    pass "R1 residual guard goes RED when one site is reverted to the piped form"
  else
    fail "R1 residual guard goes RED" "the guard stayed green with a piped site restored — it pins nothing"
  fi
fi

echo "== N: each normalisation in the residual guard is necessary =="
# Each normalisation is a pipeline stage that a future reader could read as
# noise and "simplify" out. These prove each one is load-bearing by removing it
# and showing a real bug escapes (or a correct file false-FAILs).
#
# Mutations are applied by exact-string match, not sed patterns: a mutation that
# silently fails to land reports the BASELINE and reads exactly like a pass.
STRIP_STAGE="  | sed 's/\"[^\"]*\"//g' \\"
FOLD_STAGE="  | sed -E ':b;/\\|[[:space:]]*\$/{N;s/\\|[[:space:]]*\\n[[:space:]]*/| /;bb}' \\"
PASS_ANCHOR='pass "every check matches a here-string'
SELF_MATCH_MSG='pass "never write producer | grep -qF x — every check matches a here-string'

mutate() {  # $1 = src, $2 = dst, $3 = exact find, $4 = replace ("" deletes find's line)
  # Non-zero on ANY no-op: anchor absent (2) or output identical to input (3).
  # Both must be loud. An earlier revision of this helper appended "\n" to the
  # anchor, so a mid-line anchor silently matched nothing, str.replace no-oped,
  # and it returned SUCCESS with an unmodified copy — the caller then measured
  # the baseline and reported the guard broken. That is the exact trap this file
  # exists to close, so the helper itself has to be immune to it.
  python3 - "$@" <<'PY'
import sys
src, dst, find, repl = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
s = open(src).read()
if find not in s:
    sys.exit(2)
if repl:
    out = s.replace(find, repl, 1)
else:
    out = "".join(l for l in s.splitlines(keepends=True) if find not in l)
if out == s:
    sys.exit(3)
open(dst, "w").write(out)
PY
}

# N1a — WITHOUT string-stripping, a fail/pass message naming the shape matches
#       ITSELF and false-FAILs forever. Not hypothetical: the guard's own first
#       draft did exactly this.
NOSTR="$PROBE_DIR/nostrings.test.sh"
if ! mutate "$PRISTINE" "$NOSTR" "$STRIP_STAGE" ""; then
  fail "N1a string-stripping is necessary" "anchor drifted — the strip stage no longer matches; this result is not evidence"
else
  if ! mutate "$NOSTR" "$NOSTR.2" "$PASS_ANCHOR" "$SELF_MATCH_MSG"; then
    fail "N1a string-stripping is necessary" "could not inject the self-naming message — not evidence"
  else
  mv "$NOSTR.2" "$NOSTR"
  out="$(cd "$REPO_ROOT" && bash "$NOSTR" 2>&1)"
  if grep -qF 'FAIL no early-exit-pipe form remains' <<<"$out"; then
    pass "N1a without string-stripping, a message naming the shape self-matches and false-FAILs"
  else
    fail "N1a string-stripping is necessary" "the strip may be dead code — removing it did not surface the self-match"
  fi
  fi
fi

# N1b — WITH string-stripping, that same message is inert. (That the strip does
#       not ALSO blind the guard to real bugs is proven by R1, which still REDs.)
STR="$PROBE_DIR/strings.test.sh"
if ! mutate "$PRISTINE" "$STR" "$PASS_ANCHOR" "$SELF_MATCH_MSG"; then
  fail "N1b string-stripping defuses the message" "anchor drifted — not evidence"
else
  out="$(cd "$REPO_ROOT" && bash "$STR" 2>&1)"
  if grep -qF 'ok   never write producer' <<<"$out"; then
    pass "N1b with string-stripping, the same message is inert (no self-match)"
  else
    fail "N1b string-stripping defuses the message" "the message still self-matched — the landmine is live"
  fi
fi

# N1c — WITHOUT pipe-newline folding, a multi-line pipe evades the guard. THIS
#       FILE writes multi-line pipes in house style, so it is the likeliest evasion.
for arm in nofold folded; do
  T="$PROBE_DIR/$arm.test.sh"
  if [[ "$arm" == "nofold" ]]; then
    mutate "$PRISTINE" "$T" "$FOLD_STAGE" "" || { fail "N1c folding is necessary" "anchor drifted — not evidence"; continue; }
  else
    cp "$PRISTINE" "$T"
  fi
  # Inject the SAME two-line bug into both arms.
  python3 - "$T" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = 'script_code="$(grep -vE '
i = s.index(anchor)
j = s.index("\n", i) + 1
open(p, "w").write(s[:j] + "if script_code |\n  grep -q zzz_probe; then :; fi\n" + s[j:])
PY
  out="$(cd "$REPO_ROOT" && bash "$T" 2>&1)"
  if [[ "$arm" == "nofold" ]]; then
    if grep -qF 'ok   every check matches a here-string' <<<"$out"; then
      pass "N1c without folding, a multi-line piped grep -q EVADES the guard (fold is load-bearing)"
    else
      fail "N1c folding is necessary" "the unfolded guard caught the multi-line bug — the fold stage may be redundant"
    fi
  else
    if grep -qF 'FAIL no early-exit-pipe form remains' <<<"$out"; then
      pass "N1c ...and WITH folding the same bug is caught (the fold is what closes it)"
    else
      fail "N1c folding catches the multi-line bug" "the folded guard MISSED it — the evasion is live"
    fi
  fi
done

echo "== M: both polarities of the guard's own assertions still fire =="
# M1 — fail-CLOSED (match⇒pass site): remove a sourced lib, guard must FAIL.
M1="$SANDBOX/m1-scan.sh"
grep -vE '^[[:space:]]*\.[[:space:]].*lib/strip-log-injection\.sh' "$REAL_SCRIPT" > "$M1"
if assert_mutated "$REAL_SCRIPT" "$M1" "M1 fail-closed polarity"; then
  out="$(SCRIPT_OVERRIDE="$M1" bash "$GUARD" 2>&1)"; rc=$?
  if [[ "$rc" != "0" ]] && grep -qF 'FAIL sources lib/strip-log-injection.sh' <<<"$out"; then
    pass "M1 guard FAILs when the strip-log-injection source line is removed"
  else
    fail "M1 fail-closed polarity" "guard exit $rc and did not name the removed source line"
  fi
fi

# M2 — fail-OPEN (match⇒fail site): inject the forbidden idiom at CODE LINE 1.
M2="$SANDBOX/m2-scan.sh"
{
  head -1 "$REAL_SCRIPT"
  echo 'injected=$(echo "$body" | jq ".lints[]?" | wc -l)'
  tail -n +2 "$REAL_SCRIPT"
} > "$M2"
if assert_mutated "$REAL_SCRIPT" "$M2" "M2 fail-open polarity"; then
  out="$(SCRIPT_OVERRIDE="$M2" bash "$GUARD" 2>&1)"; rc=$?
  if [[ "$rc" != "0" ]] && grep -qF 'FAIL script never uses the fail-open .lints[]? idiom' <<<"$out"; then
    pass "M2 guard FAILs when the fail-open .lints[]? idiom is injected at code line 1"
  else
    fail "M2 fail-open polarity" "guard exit $rc and did not name the injected fail-open idiom"
  fi
fi

# The seam must not dirty tracked source — the failure that prompted it.
if git -C "$REPO_ROOT" diff --quiet -- scripts/supabase-advisor-scan.sh; then
  pass "no mutation touched tracked source (SCRIPT_OVERRIDE + sandbox held)"
else
  fail "tracked source is clean" "scripts/supabase-advisor-scan.sh is dirty — a mutation escaped the sandbox"
fi

echo ""
if [[ "$fails" -gt 0 ]]; then
  printf '%d check(s) FAILED\n' "$fails"
  exit 1
fi
echo "all checks passed"
