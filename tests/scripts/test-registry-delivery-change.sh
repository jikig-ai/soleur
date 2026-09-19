#!/usr/bin/env bash
# Tests scripts/registry-delivery-change.sh (#8279) — the derivation helper that answers "which
# merged change(s) does this registry-host-replace dispatcher run deliver?" from the delivery
# watermark and github.sha.
#
# Every fixture here is SYNTHESIZED (cq-test-fixtures-synthesized-only): SHAs are repeated-letter
# strings, PR numbers are invented, nothing is captured from the live API.
#
# STUB DESIGN (test-design review, plan §3). `$TMP/gh.sh` dispatches on argv in this ORDER —
# `*/pulls` before `commits/<sha>`, a listing carrying `-f path=` before `commits/` — because a
# `commits/<sha>/pulls` argv also matches `commits/`, and a listing URL is `.../commits` with the
# path as a query field. Per-SHA FIXTURE FILES for `/pulls` and `commits/<sha>`, never a per-call
# sequence: a sequence hands the first fixture to whichever sha is asked first, so an ordering row
# would assert call order instead of sha order. Anything unfixtured exits 64 — a miss must fail
# loudly, or it impersonates the no-PR arm. Every argv line lands in a call LOG so rows can assert
# what the SUT asked for (the compare call carries NO paging param; the cap bounds `/pulls` calls).
#
# FIXTURE DIRECTION is stated and OPPOSITE: compare `.commits[]` oldest→newest (as the API), path
# listing newest→oldest (as the API). If both ran the same way a SUT that echoed path-list order
# would pass the ordering row for the wrong reason.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUT="$ROOT/scripts/registry-delivery-change.sh"
CFG="apps/web-platform/infra/cloud-init-registry.yml"

PASS=0; FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

[[ -r "$SUT" ]] || { echo "  FAIL: SUT not readable at $SUT"; echo "=== Results: 0/1 passed, 1 failed ==="; exit 1; }

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT

# A PATH shim: any `gh` call NOT routed through REGISTRY_DELIVERY_GH_CMD reds the control row even
# on a box with a real `gh` on PATH.
mkdir -p "$TMP/bin"
printf '#!/usr/bin/env bash\necho "gh reached via PATH, not via the seam" >&2\nexit 99\n' > "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"

cat > "$TMP/gh.sh" <<'STUB'
#!/usr/bin/env bash
# Log first, dispatch second — a row that asserts "no call carried X" reads this log.
printf '%s\n' "$*" >> "$STUB_LOG"
argv=" $* "
for a in "$@"; do
  case "$a" in
    */commits/*/pulls)
      sha="${a%/pulls}"; sha="${sha##*/}"
      f="$STUB_DIR/pulls/$sha"
      [[ -f "$f" ]] || { echo "stub: no pulls fixture for $sha" >&2; exit 64; }
      cat "$f"; exit 0 ;;
  esac
done
for a in "$@"; do
  case "$a" in
    */compare/*)
      if [[ -n "${STUB_COMPARE_RC:-}" && "${STUB_COMPARE_RC}" != "0" ]]; then exit "${STUB_COMPARE_RC}"; fi
      printf '%s' "${STUB_COMPARE_JSON:-}"; exit 0 ;;
  esac
done
case "$argv" in
  *" -f path="*)
    if [[ -n "${STUB_PATH_RC:-}" && "${STUB_PATH_RC}" != "0" ]]; then exit "${STUB_PATH_RC}"; fi
    printf '%s' "${STUB_PATH_JSON:-}"; exit 0 ;;
esac
for a in "$@"; do
  case "$a" in
    */commits/*)
      sha="${a##*/}"
      f="$STUB_DIR/commit/$sha"
      [[ -f "$f" ]] || { echo "stub: no commit fixture for $sha" >&2; exit 64; }
      cat "$f"; exit 0 ;;
  esac
done
echo "stub: unrouted gh call: $*" >&2
exit 64
STUB
chmod +x "$TMP/gh.sh"

# --- synthesized SHAs (40 hex chars each) ----------------------------------------------------
mksha() { local out=""; while [[ ${#out} -lt 40 ]]; do out+="$1"; done; printf '%s' "${out:0:40}"; }
B=$(mksha b)     # watermark (before)
A=$(mksha a)     # github.sha (after)
T=$(mksha 1c)    # the in-range path touch
X=$(mksha 2d)    # an in-range commit that did not touch the path
P1=$(mksha 3e)   # pre-watermark path touches (in the listing, NOT in the range)
P2=$(mksha 4f)
E=$(mksha 5a)    # an EARLIER in-range path touch (T3)
S1=$(mksha 6b)   # merge-commit PR branch commits (T13)
S2=$(mksha 7c)

# --- fixture builders ------------------------------------------------------------------------
# compare_json <status> <total> <sha>... (oldest -> newest, as the API)
compare_json() {
  local st="$1" tot="$2"; shift 2
  local arr; arr="$(printf '%s\n' "$@" | jq -R . | jq -s 'map({sha: .})')"
  jq -cn --arg s "$st" --argjson t "$tot" --argjson c "$arr" '{status:$s,total_commits:$t,commits:$c}'
}
# entry <sha> <subject> -> one listing/commit object (multi-line messages allowed)
entry() { jq -cn --arg s "$1" --arg m "$2" '{sha:$s, commit:{message:$m}}'; }
# listing <entry-json>... (newest -> oldest, as the API)
listing() { printf '%s\n' "$@" | jq -cs .; }
pulls() { jq -cn --argjson n "$1" '[{number:$n, merged_at:"2026-09-19T00:00:00Z"}]'; }

reset_fixtures() {
  rm -rf "$TMP/fx"; mkdir -p "$TMP/fx/pulls" "$TMP/fx/commit"
  : > "$TMP/calls"
  STUB_COMPARE_RC=0; STUB_COMPARE_JSON=""; STUB_PATH_RC=0; STUB_PATH_JSON=""
}
fx_pulls()  { printf '%s' "$2" > "$TMP/fx/pulls/$1"; }
fx_commit() { printf '%s' "$2" > "$TMP/fx/commit/$1"; }

# run_sut [--before SHA] ... : runs the SUT through the seam, outside Actions, with the PATH shim
# in front. RC and $TMP/out are the row's evidence.
run_sut() {
  env -u GITHUB_ACTIONS PATH="$TMP/bin:$PATH" \
      REGISTRY_DELIVERY_GH_CMD="$TMP/gh.sh" \
      STUB_DIR="$TMP/fx" STUB_LOG="$TMP/calls" \
      STUB_COMPARE_RC="$STUB_COMPARE_RC" STUB_COMPARE_JSON="$STUB_COMPARE_JSON" \
      STUB_PATH_RC="$STUB_PATH_RC" STUB_PATH_JSON="$STUB_PATH_JSON" \
      bash "$SUT" --repo jikig-ai/soleur --path "$CFG" "$@" > "$TMP/out" 2>"$TMP/err"; RC=$?
}
val() { sed -n "s/^$1=//p" "$TMP/out"; }
# Every row: the six keys, each exactly once, and nothing else on stdout.
assert_shape() {
  local ok=1 k
  for k in range range_note commits prs unattributed summary; do
    [[ "$(grep -c "^$k=" "$TMP/out")" -eq 1 ]] || ok=0
  done
  [[ "$(grep -cvE '^(range|range_note|commits|prs|unattributed|summary)=' "$TMP/out")" -eq 0 ]] || ok=0
  if [[ "$ok" -eq 1 ]]; then pass "$1: output shape — six keys, each once, nothing else"; else fail "$1: output shape broken: $(tr '\n' '|' < "$TMP/out")"; fi
}

# ============================================================================================
echo "T0 usage"
bash "$SUT" > "$TMP/out" 2>"$TMP/err"; RC=$?
if [[ "$RC" -eq 2 ]]; then pass "T0: no args exits 2"; else fail "T0: no args exited $RC"; fi
if grep -q -- '--repo' "$TMP/err" && grep -q -- '--after' "$TMP/err"; then pass "T0: usage names --repo and --after"; else fail "T0: usage line missing --repo/--after: $(head -2 "$TMP/err")"; fi

# ============================================================================================
echo "T1 control: proven range, one path touch, PR via /pulls, subject with hostile characters"
reset_fixtures
SUBJ1='fix: a=b 100% `x` "q" <!-- @octocat'
STUB_COMPARE_JSON="$(compare_json ahead 3 "$X" "$T" "$A")"
STUB_PATH_JSON="$(listing "$(entry "$T" "$SUBJ1"$'\n\nbody')" "$(entry "$P1" "old (#7001)")" "$(entry "$P2" "older (#7000)")")"
fx_pulls "$T" "$(pulls 8272)"
run_sut --before "$B" --after "$A"
if [[ "$RC" -eq 0 ]]; then pass "T1: rc 0"; else fail "T1: rc $RC: $(cat "$TMP/err")"; fi
assert_shape T1
[[ "$(val range)" == "proven" ]] && pass "T1: range=proven" || fail "T1: range=$(val range)"
[[ "$(val range_note)" == "" ]] && pass "T1: range_note empty" || fail "T1: range_note=$(val range_note)"
[[ "$(val prs)" == "8272" ]] && pass "T1: prs=8272" || fail "T1: prs=$(val prs)"
[[ "$(val commits)" == "$T" ]] && pass "T1: commits=<touch>" || fail "T1: commits=$(val commits)"
case "$(val summary)" in "PR #8272 ($SUBJ1)"*) pass "T1: summary starts PR #8272 (<subject verbatim>)";; *) fail "T1: summary=$(val summary)";; esac
[[ "$(grep -c '' <<<"$(val summary)")" -eq 1 ]] && pass "T1: summary is one line" || fail "T1: summary spans lines"
grep -q 'compare/' "$TMP/calls" && grep -q -- ' -f path=' "$TMP/calls" && grep -q '/pulls' "$TMP/calls" \
  && pass "T1: call log shows compare, path listing and /pulls" || fail "T1: call log: $(tr '\n' '|' < "$TMP/calls")"
if grep 'compare/' "$TMP/calls" | grep -qE 'per_page|page='; then fail "T1: the compare call carried a paging param (250-cap contract broken)"; else pass "T1: the compare call carried no paging param"; fi
if grep -q ' -f path=' "$TMP/calls" && grep ' -f path=' "$TMP/calls" | grep -q 'per_page=100'; then pass "T1: the path listing asks for per_page=100"; else fail "T1: path listing lacks per_page=100"; fi

# ============================================================================================
echo "T2 order: two path touches — prs follow COMPARE order (oldest->newest), not listing order"
reset_fixtures
A1=$(mksha 8d); B1=$(mksha 9e)
STUB_COMPARE_JSON="$(compare_json ahead 2 "$A1" "$B1")"
STUB_PATH_JSON="$(listing "$(entry "$B1" "newer")" "$(entry "$A1" "older")" "$(entry "$P1" "pre")")"
fx_pulls "$A1" "$(pulls 7954)"; fx_pulls "$B1" "$(pulls 8272)"
run_sut --before "$B" --after "$B1"
assert_shape T2
[[ "$(val prs)" == "7954 8272" ]] && pass "T2: prs=7954 8272 (compare order)" || fail "T2: prs=$(val prs)"
[[ "$(val commits)" == "$A1 $B1" ]] && pass "T2: commits oldest->newest" || fail "T2: commits=$(val commits)"

# ============================================================================================
echo "T3 coalesced: after is a registration-only push; the touch is an EARLIER in-range commit"
reset_fixtures
STUB_COMPARE_JSON="$(compare_json ahead 2 "$E" "$A")"
STUB_PATH_JSON="$(listing "$(entry "$E" "earlier touch")" "$(entry "$P1" "pre")" "$(entry "$P2" "pre2")")"
fx_pulls "$E" "$(pulls 8100)"; fx_pulls "$A" "$(pulls 9999)"
run_sut --before "$B" --after "$A"
assert_shape T3
[[ "$(val commits)" == "$E" ]] && pass "T3: commits=<earlier sha>" || fail "T3: commits=$(val commits)"
[[ "$(val prs)" == "8100" ]] && pass "T3: prs=<earlier PR>" || fail "T3: prs=$(val prs)"
if grep -q 9999 "$TMP/out"; then fail "T3: the decoy PR of the registration push leaked into the output"; else pass "T3: decoy 9999 absent"; fi

# ============================================================================================
echo "T4 no watermark: [after] only, unproven, PR via /pulls"
reset_fixtures
fx_commit "$A" "$(entry "$A" "chore: bump")"; fx_pulls "$A" "$(pulls 8272)"
run_sut --after "$A"
if [[ "$RC" -eq 0 ]]; then pass "T4: rc 0"; else fail "T4: rc $RC: $(cat "$TMP/err")"; fi
assert_shape T4
[[ "$(val range)" == "unproven" ]] && pass "T4: range=unproven" || fail "T4: range=$(val range)"
[[ "$(val range_note)" == "no watermark" ]] && pass "T4: range_note=no watermark" || fail "T4: range_note=$(val range_note)"
[[ "$(val prs)" == "8272" ]] && pass "T4: prs from pulls/<after>" || fail "T4: prs=$(val prs)"
[[ "$(val commits)" == "$A" ]] && pass "T4: commits=<after>" || fail "T4: commits=$(val commits)"
if grep -q 'compare/' "$TMP/calls"; then fail "T4: a compare call was made with no watermark"; else pass "T4: no compare call without a watermark"; fi
# T4b: an EMPTY --before is the same arm (the workflow passes the gate's output verbatim).
reset_fixtures
fx_commit "$A" "$(entry "$A" "chore: bump")"; fx_pulls "$A" "$(pulls 8272)"
run_sut --before "" --after "$A"
[[ "$RC" -eq 0 && "$(val range_note)" == "no watermark" ]] && pass "T4b: empty --before is the no-watermark arm" || fail "T4b: rc=$RC note=$(val range_note)"

# ============================================================================================
echo "T5 compare diverged: unproven, [after] only"
reset_fixtures
STUB_COMPARE_JSON="$(compare_json diverged 5 "$X")"
fx_commit "$A" "$(entry "$A" "subject (#8300)")"; fx_pulls "$A" "$(pulls 8300)"
run_sut --before "$B" --after "$A"
if [[ "$RC" -eq 0 ]]; then pass "T5: rc 0"; else fail "T5: rc $RC"; fi
assert_shape T5
[[ "$(val range)" == "unproven" ]] && pass "T5: range=unproven" || fail "T5: range=$(val range)"
[[ "$(val range_note)" == *"compare status diverged"* ]] && pass "T5: note names the status" || fail "T5: note=$(val range_note)"
[[ "$(val commits)" == "$A" ]] && pass "T5: commits=<after> only" || fail "T5: commits=$(val commits)"
if grep -q -- ' -f path=' "$TMP/calls"; then fail "T5: a path listing was requested on an unproven range"; else pass "T5: no path listing on an unproven range"; fi

# ============================================================================================
echo "T6 compare rc!=0: unproven, note carries the rc, PR from pulls/<after>"
reset_fixtures
STUB_COMPARE_RC=22
fx_commit "$A" "$(entry "$A" "subject")"; fx_pulls "$A" "$(pulls 8301)"
run_sut --before "$B" --after "$A"
if [[ "$RC" -eq 0 ]]; then pass "T6: rc 0 (a compare failure never fails the helper)"; else fail "T6: rc $RC"; fi
assert_shape T6
[[ "$(val range)" == "unproven" ]] && pass "T6: range=unproven" || fail "T6: range=$(val range)"
[[ "$(val range_note)" == *22* ]] && pass "T6: note contains the literal 22" || fail "T6: note=$(val range_note)"
[[ "$(val prs)" == "8301" ]] && pass "T6: prs from pulls/<after>" || fail "T6: prs=$(val prs)"

# ============================================================================================
echo "T7 /pulls empty, subject ends (#7954): attributed by subject, note says so"
reset_fixtures
STUB_COMPARE_JSON="$(compare_json ahead 1 "$T")"
STUB_PATH_JSON="$(listing "$(entry "$T" "feat: thing (#7954)")")"
fx_pulls "$T" "[]"
run_sut --before "$B" --after "$T"
assert_shape T7
[[ "$(val prs)" == "7954" ]] && pass "T7: prs=7954 via the subject fallback" || fail "T7: prs=$(val prs)"
[[ "$(val range_note)" == *"attributed by commit subject"* ]] && pass "T7: note records the subject attribution" || fail "T7: note=$(val range_note)"
[[ "$(val range)" == "proven" ]] && pass "T7: range stays proven (the note is about attribution, not the range)" || fail "T7: range=$(val range)"

# ============================================================================================
echo "T7b anchor: only a TRAILING (#N) attributes"
reset_fixtures
STUB_COMPARE_JSON="$(compare_json ahead 1 "$T")"
STUB_PATH_JSON="$(listing "$(entry "$T" "x (#1) (#7954)")")"
fx_pulls "$T" "[]"
run_sut --before "$B" --after "$T"
[[ "$(val prs)" == "7954" ]] && pass "T7b: 'x (#1) (#7954)' -> 7954 (the suffix, not the first number)" || fail "T7b: prs=$(val prs)"
reset_fixtures
STUB_COMPARE_JSON="$(compare_json ahead 1 "$T")"
STUB_PATH_JSON="$(listing "$(entry "$T" "(#1) not a suffix")")"
fx_pulls "$T" "[]"
run_sut --before "$B" --after "$T"
[[ "$(val prs)" == "" && "$(val unattributed)" == "$T" ]] && pass "T7b: '(#1) not a suffix' -> unattributed" || fail "T7b: prs=$(val prs) unattributed=$(val unattributed)"

# ============================================================================================
echo "T8 no PR anywhere: unattributed, summary names the commit"
reset_fixtures
STUB_COMPARE_JSON="$(compare_json ahead 1 "$T")"
STUB_PATH_JSON="$(listing "$(entry "$T" "direct push subject")")"
fx_pulls "$T" "[]"
run_sut --before "$B" --after "$T"
assert_shape T8
[[ "$(val prs)" == "" ]] && pass "T8: prs empty" || fail "T8: prs=$(val prs)"
[[ "$(val unattributed)" == "$T" ]] && pass "T8: unattributed=<sha>" || fail "T8: unattributed=$(val unattributed)"
[[ "$(val summary)" == "commit ${T:0:7} (direct push subject)" ]] && pass "T8: summary=commit <sha7> (<subject>)" || fail "T8: summary=$(val summary)"

# ============================================================================================
echo "T9 /pulls returns a non-numeric number: rejected, subject fallback attributes"
reset_fixtures
STUB_COMPARE_JSON="$(compare_json ahead 1 "$T")"
STUB_PATH_JSON="$(listing "$(entry "$T" "feat: thing (#7954)")")"
fx_pulls "$T" '[{"number":"abc"}]'
run_sut --before "$B" --after "$T"
[[ "$(val prs)" == "7954" ]] && pass "T9: 'abc' rejected, 7954 from the subject" || fail "T9: prs=$(val prs)"
if grep -q abc "$TMP/out"; then fail "T9: the non-numeric value leaked into the output"; else pass "T9: 'abc' never reaches the output"; fi

# ============================================================================================
echo "T10 total_commits > 250: unproven, note names the cap, compare had no paging param"
reset_fixtures
STUB_COMPARE_JSON="$(compare_json ahead 251 "$X" "$T")"
fx_commit "$A" "$(entry "$A" "subject")"; fx_pulls "$A" "$(pulls 8302)"
run_sut --before "$B" --after "$A"
assert_shape T10
[[ "$(val range)" == "unproven" ]] && pass "T10: range=unproven" || fail "T10: range=$(val range)"
[[ "$(val range_note)" == *250* ]] && pass "T10: note mentions 250" || fail "T10: note=$(val range_note)"
[[ "$(val commits)" == "$A" ]] && pass "T10: [after] only" || fail "T10: commits=$(val commits)"
if grep 'compare/' "$TMP/calls" | grep -qE 'per_page|page='; then fail "T10: compare carried a paging param"; else pass "T10: compare carried no paging param"; fi

# ============================================================================================
echo "T11 proven range, nothing in range touched the path: prs EMPTY, no [after] fallback"
reset_fixtures
STUB_COMPARE_JSON="$(compare_json ahead 2 "$X" "$A")"
STUB_PATH_JSON="$(listing "$(entry "$P1" "pre (#7001)")" "$(entry "$P2" "pre2 (#7000)")")"
fx_pulls "$A" "$(pulls 9999)"; fx_pulls "$P1" "$(pulls 7001)"
run_sut --before "$B" --after "$A"
if [[ "$RC" -eq 0 ]]; then pass "T11: rc 0"; else fail "T11: rc $RC"; fi
assert_shape T11
[[ "$(val range)" == "proven" ]] && pass "T11: range=proven" || fail "T11: range=$(val range)"
[[ "$(val prs)" == "" ]] && pass "T11: prs EMPTY (no blame on whatever merged last)" || fail "T11: prs=$(val prs)"
[[ "$(val commits)" == "" ]] && pass "T11: commits EMPTY" || fail "T11: commits=$(val commits)"
[[ "$(val range_note)" == "no commit in range touched $CFG" ]] && pass "T11: note=no commit in range touched <path>" || fail "T11: note=$(val range_note)"
s="$(val summary)"
[[ "$s" == *"${A:0:7}"* && "$s" == *"${B:0:7}"* && "$s" != *"PR #"* ]] && pass "T11: summary names <after7> and <before7>, no PR" || fail "T11: summary=$s"
if grep -q '/pulls' "$TMP/calls"; then fail "T11: a /pulls lookup was made for a commit outside the range"; else pass "T11: no /pulls lookup on an empty intersection"; fi

# ============================================================================================
echo "T12 seam guard: REGISTRY_DELIVERY_GH_CMD set inside Actions refuses"
env GITHUB_ACTIONS=true REGISTRY_DELIVERY_GH_CMD="$TMP/gh.sh" STUB_DIR="$TMP/fx" STUB_LOG="$TMP/calls" \
  bash "$SUT" --repo jikig-ai/soleur --after "$A" > "$TMP/out" 2>"$TMP/err"; RC=$?
if [[ "$RC" -eq 1 ]]; then pass "T12: rc 1"; else fail "T12: rc $RC"; fi
if grep -q '::error::.*REGISTRY_DELIVERY_GH_CMD' "$TMP/err"; then pass "T12: ::error:: names the seam"; else fail "T12: stderr=$(cat "$TMP/err")"; fi
if [[ -s "$TMP/out" ]]; then fail "T12: the seam refusal still printed output: $(head -1 "$TMP/out")"; else pass "T12: no key=value output on refusal"; fi

# ============================================================================================
echo "T13 merge-commit PR: two in-range branch commits resolve to one PR, newest subject shown"
reset_fixtures
STUB_COMPARE_JSON="$(compare_json ahead 3 "$S1" "$S2" "$A")"
STUB_PATH_JSON="$(listing "$(entry "$S2" "branch commit two")" "$(entry "$S1" "branch commit one")")"
fx_pulls "$S1" "$(pulls 9001)"; fx_pulls "$S2" "$(pulls 9001)"
run_sut --before "$B" --after "$A"
assert_shape T13
[[ "$(grep -o 'PR #9001' <<<"$(val summary)" | wc -l)" -eq 1 ]] && pass "T13: PR #9001 appears once" || fail "T13: summary=$(val summary)"
[[ "$(val summary)" == "PR #9001 (branch commit two)" ]] && pass "T13: the NEWER branch commit's subject is shown" || fail "T13: summary=$(val summary)"
[[ "$(val prs)" == "9001" ]] && pass "T13: prs deduped to one" || fail "T13: prs=$(val prs)"
[[ "$(val commits)" == "$S1 $S2" ]] && pass "T13: both commits listed" || fail "T13: commits=$(val commits)"

# ============================================================================================
echo "T14 twelve in-range touches: MAX_LOOKUPS=10 bounds /pulls, the two OLDEST are dropped"
reset_fixtures
shas=(); ents=(); i=0
for h in 10 11 12 13 14 15 16 17 18 19 20 21; do
  s=$(mksha "$h"); shas+=("$s"); i=$((i+1))
  fx_pulls "$s" "$(pulls $((9100+i)))"
done
STUB_COMPARE_JSON="$(compare_json ahead 12 "${shas[@]}")"
for (( j=${#shas[@]}-1; j>=0; j-- )); do ents+=("$(entry "${shas[$j]}" "touch $j")"); done
STUB_PATH_JSON="$(listing "${ents[@]}")"
run_sut --before "$B" --after "${shas[11]}"
assert_shape T14
[[ "$(grep -c '/pulls' "$TMP/calls")" -eq 10 ]] && pass "T14: exactly 10 /pulls calls" || fail "T14: $(grep -c '/pulls' "$TMP/calls") /pulls calls"
p="$(val prs)"
[[ "$p" != *9101* && "$p" != *9102* && "$p" == *9103* && "$p" == *9112* ]] && pass "T14: the two OLDEST PRs absent, newest 10 present" || fail "T14: prs=$p"
[[ "$(val range_note)" == *"2 older"* ]] && pass "T14: note states the truncation count" || fail "T14: note=$(val range_note)"

# ============================================================================================
echo "T15 identical compare: proven range, empty intersection, summary names after7 + watermark"
reset_fixtures
STUB_COMPARE_JSON='{"status":"identical","total_commits":0,"commits":[]}'
STUB_PATH_JSON="$(listing "$(entry "$P1" "pre (#7001)")")"
run_sut --before "$A" --after "$A"
assert_shape T15
[[ "$(val range)" == "proven" ]] && pass "T15: range=proven" || fail "T15: range=$(val range)"
[[ "$(val prs)" == "" ]] && pass "T15: prs EMPTY" || fail "T15: prs=$(val prs)"
[[ "$(val summary)" == *"${A:0:7}"* && "$(val summary)" == *"unchanged since the delivery watermark"* ]] && pass "T15: summary names <after7> and the watermark" || fail "T15: summary=$(val summary)"

# ============================================================================================
echo "T16 control characters in the subject are stripped; summary is one line"
reset_fixtures
STUB_COMPARE_JSON="$(compare_json ahead 1 "$T")"
MSG16="$(printf 'sub\r\001ject\177\xe2\x80\xa8 tail\nsecond line')"
STUB_PATH_JSON="$(listing "$(entry "$T" "$MSG16")")"
fx_pulls "$T" "$(pulls 8303)"
run_sut --before "$B" --after "$T"
assert_shape T16
s="$(val summary)"
[[ "$(grep -c '' "$TMP/out")" -eq 6 ]] && pass "T16: output is exactly six lines" || fail "T16: $(grep -c '' "$TMP/out") lines"
[[ "$s" == "PR #8303 (subject tail)" ]] && pass "T16: CR, \\x01, DEL and U+2028 removed; second line dropped" || fail "T16: summary=$(printf '%s' "$s" | od -c | head -3)"
if grep -q 'second line' "$TMP/out"; then fail "T16: the second message line leaked"; else pass "T16: only the first line is used"; fi

# ============================================================================================
echo "T17 proven range but the path listing fails: unproven, note names the listing"
reset_fixtures
STUB_COMPARE_JSON="$(compare_json ahead 2 "$X" "$A")"
STUB_PATH_RC=22
fx_commit "$A" "$(entry "$A" "subject")"; fx_pulls "$A" "$(pulls 8304)"
run_sut --before "$B" --after "$A"
if [[ "$RC" -eq 0 ]]; then pass "T17: rc 0"; else fail "T17: rc $RC"; fi
assert_shape T17
[[ "$(val range)" == "unproven" ]] && pass "T17: range=unproven" || fail "T17: range=$(val range)"
[[ "$(val range_note)" == *"path listing"* ]] && pass "T17: note names the path listing" || fail "T17: note=$(val range_note)"
[[ "$(val commits)" == "$A" ]] && pass "T17: [after] only" || fail "T17: commits=$(val commits)"

# ============================================================================================
echo "T18 a malformed sha from the compare is dropped and never placed in a URL"
reset_fixtures
STUB_COMPARE_JSON='{"status":"ahead","total_commits":2,"commits":[{"sha":"../../evil"},{"sha":"'"$T"'"}]}'
STUB_PATH_JSON="$(listing "$(entry "$T" "ok (#8305)")" "$(entry "../../evil" "evil")")"
fx_pulls "$T" "$(pulls 8305)"
run_sut --before "$B" --after "$T"
assert_shape T18
[[ "$(val prs)" == "8305" ]] && pass "T18: the well-formed sha still attributes" || fail "T18: prs=$(val prs)"
[[ "$(val range_note)" == *"malformed sha"* ]] && pass "T18: note says malformed sha" || fail "T18: note=$(val range_note)"
if grep -q 'evil' "$TMP/calls"; then fail "T18: a gh call carried the malformed sha"; else pass "T18: no gh call carried the malformed sha"; fi
if grep -q 'evil' "$TMP/out"; then fail "T18: the malformed sha leaked into the output"; else pass "T18: the malformed sha is absent from the output"; fi

# ============================================================================================
echo "T19 the PATH shim: a gh call not routed through the seam is fatal to the row"
reset_fixtures
STUB_COMPARE_JSON="$(compare_json ahead 1 "$T")"
STUB_PATH_JSON="$(listing "$(entry "$T" "s")")"
fx_pulls "$T" "$(pulls 1)"
env -u GITHUB_ACTIONS PATH="$TMP/bin:$PATH" STUB_DIR="$TMP/fx" STUB_LOG="$TMP/calls" \
  STUB_COMPARE_JSON="$STUB_COMPARE_JSON" STUB_PATH_JSON="$STUB_PATH_JSON" \
  bash "$SUT" --repo jikig-ai/soleur --path "$CFG" --before "$B" --after "$T" > "$TMP/out" 2>"$TMP/err"; RC=$?
if [[ "$RC" -eq 0 && "$(val range)" == "unproven" && "$(val prs)" == "" ]]; then
  pass "T19: without the seam every gh call hits the exit-99 shim and the helper degrades, never impersonates the fixtures"
else
  fail "T19: rc=$RC range=$(val range) prs=$(val prs) — the fixtures were reached without the seam"
fi

# --- anti-vacuity floor -------------------------------------------------------------------
# HARNESS CANARY + a floor that does NOT dispatch through the helper it guards (the preflight
# suite's shape): neutering fail() must be caught by something fail() does not carry.
_cp=$PASS; _cf=$FAIL
pass "canary: a true condition registers as PASS"
fail "canary: a false condition MUST register as FAIL (this line is EXPECTED)"
if [[ "$PASS" -ne $((_cp + 1)) || "$FAIL" -ne $((_cf + 1)) ]]; then
  echo "  FATAL: the assertion helpers are not counting — every verdict above is void." >&2
  exit 2
fi
FAIL=$((FAIL - 1))
TOTAL=$((PASS+FAIL))
# The floor equals the count a green run measured (AC2). Fix the dispatch, do not lower it.
if [[ "$TOTAL" -lt 96 ]]; then
  echo "  FATAL: anti-vacuity: ran $TOTAL assertions, expected >= 96. Fix the dispatch, do not lower the floor." >&2
  exit 2
fi

echo "=== Results: $PASS/$((PASS+FAIL)) passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
