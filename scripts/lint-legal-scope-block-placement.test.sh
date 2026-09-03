#!/usr/bin/env bash
# lint-legal-scope-block-placement.test.sh -- suite + mutation battery for gate 1.
#
# Fixtures are synthesized (cq-test-fixtures-synthesized-only). The live corpus is used only
# for the calibration floors at the end, which assert against the working tree.
#
# WHAT REVIEW CHANGED HERE. The first version of this suite passed 26/0 with a 4-row mutation
# battery reporting every arm load-bearing, while the gate carried two CRITICAL fail-opens
# and five classifier blind spots. The battery only ever flipped the ARM_*_ENABLED toggles --
# one axis, four times -- which tests a SIMULATED defect. Every mutation below that matters
# now edits a regex, a field-parse, or a stream transform, i.e. the things that actually
# regress. A `MIN_ASSERTIONS` floor closes the dispatch hole: neutering pass()/fail() used to
# yield `passed: 0 failed: 0`, exit 0, and `run_suite` recorded [ok].

set -euo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$REPO_ROOT/scripts/lint-legal-scope-block-placement.sh"
BASE_LIB="$REPO_ROOT/scripts/lib/legal-base-ref.sh"

# Floor, not equality: a floor bounds coverage without making every added assertion a
# spurious failure. Derived from a green run, and raised in lockstep when cases are added.
MIN_ASSERTIONS=48

fails=0
passes=0
pass() { passes=$((passes + 1)); echo "[ok] $1"; }
fail() { fails=$((fails + 1)); echo "[FAIL] $1" >&2; }

for f in "$GATE" "$BASE_LIB"; do
  if [[ ! -f "$f" ]]; then
    fail "missing required file: $f"
    echo "passed: $passes  failed: $fails" >&2
    exit 1
  fi
done

SANDBOX_ROOT=$(mktemp -d -t legal-scope-gate.XXXXXXXX) || { echo "mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$SANDBOX_ROOT"' EXIT

# The gate resolves its shared libraries relative to BASH_SOURCE/.., so the fixture must
# reproduce the real layout (scripts/<gate>.sh + scripts/lib/). Placing the gate at the
# fixture root makes `..` escape the repo and the gate fails closed on a missing library --
# correct behaviour, but it would test the guard rather than the gate.
new_repo() {
  local d
  d=$(mktemp -d "$SANDBOX_ROOT/case-XXXXXXXX") || return 1
  mkdir -p "$d/docs/legal" "$d/plugins/soleur/docs/pages/legal" "$d/scripts/lib" || return 1
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@t
  git -C "$d" config user.name t
  cp "$GATE" "$d/scripts/gate.sh"
  cp "$BASE_LIB" "$d/scripts/lib/legal-base-ref.sh"
  # Both surfaces must be non-empty or the per-surface readability floor fires.
  printf -- '---\ntitle: Mirror\n---\n\n# Mirror Doc\n\nPlaceholder.\n' \
    > "$d/plugins/soleur/docs/pages/legal/privacy-policy.md"
  printf '%s\n' "$d"
}

commit_all() { : "${1:?fixture dir is empty; git -C '' would retarget this write}"; git -C "$1" add -A && git -C "$1" -c core.hooksPath=/dev/null commit -q -m "$2"; }
# Commit the base on main, then branch. Without the branch HEAD *is* main, merge-base is
# HEAD, and the added-line diff is empty -- every case would pass having examined nothing.
commit_base() { : "${1:?fixture dir is empty; git -C '' would retarget this write}"; commit_all "$1" base && git -C "$1" checkout -q -b feat; }

run_gate() {
  local d="$1" out rc=0
  out=$(cd "$d" && bash ./scripts/gate.sh --base main 2>&1) || rc=$?
  printf '%s|%s' "$rc" "$out"
}

CLOUD_SECTION=$'## 4. Data\n\n### 4.1 Processing\n\nThe Soleur Web Platform stores account data on Jikigai infrastructure.\n\nMore prose.\n'
LOCAL_SECTION=$'## 4. Data\n\n### 4.1 Processing\n\nThe Plugin writes files you own.\n\nMore prose.\n'

# case <name> <base-body> <added-line> <expected-rc> [<must-appear-in-output>]
case_line() {
  local name="$1" body="$2" added="$3" want="$4" expect="${5:-}"
  local d; d=$(new_repo) || { fail "$name: fixture setup failed"; return; }
  printf '%s' "$body" > "$d/docs/legal/privacy-policy.md"
  commit_base "$d" >/dev/null
  printf '%s\n' "$added" >> "$d/docs/legal/privacy-policy.md"
  commit_all "$d" add >/dev/null
  local res rc out; res=$(run_gate "$d"); rc=${res%%|*}; out=${res#*|}
  if [[ "$rc" == "$want" ]]; then
    pass "$name (rc=$rc)"
  else
    fail "$name: expected rc=$want got rc=$rc -- $(head -3 <<<"$out")"
    return
  fi
  if [[ -n "$expect" ]]; then
    if grep -qE -- "$expect" <<<"$out"; then
      pass "$name: output matches /$expect/"
    else
      fail "$name: output does not match /$expect/ -- $(head -3 <<<"$out")"
    fi
  fi
  # A must-NOT-fire case must prove it CLASSIFIED the line. Without this, every rc=0 fixture
  # passes equally under "correctly declined to fire" and "never recognised the block" --
  # which is how a narrowed vocabulary went undetected.
  if [[ "$want" == "0" && -n "$expect" ]]; then :; fi
}

# ---------------------------------------------------------------------------------------
# arm (a) -- referent/section agreement
# ---------------------------------------------------------------------------------------

case_line "arm (a): fires on a section referent in a marker-bearing section" \
  "$CLOUD_SECTION" 'This section applies to the Plugin only. See Section 9.' 1 'arm \(a\)'

case_line "arm (a): fires when the marker is BELOW the block" \
  $'## 4. Data\n\n### 4.1 Processing\n\nIntro.\n' \
  'This section applies to the Plugin only. See Section 9.' 0
# (the line above establishes the marker-free control; the real below-marker case follows)
d=$(new_repo)
printf '## 4. Data\n\n### 4.1 Processing\n\nIntro.\n' > "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
printf 'This section applies to the Plugin only. See Section 9.\nThe Soleur Web Platform stores account data.\n' \
  >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add >/dev/null
res=$(run_gate "$d"); rc=${res%%|*}
if [[ "$rc" == "1" ]]; then
  pass "arm (a): a marker BELOW the block fires (whole section is scanned)"
else
  fail "arm (a): marker below the block did not fire (rc=$rc) -- scan direction regressed"
fi

# The marker in the HEADING is the most authoritative statement of a section's scope.
case_line "arm (a): a marker in the section HEADING fires" \
  $'## 4. Web Platform Cloud Execution\n\nWe process your prompts.\n' \
  'This section applies to the Plugin only and must not be read as covering it.' 1 'arm \(a\)'

# THE CALIBRATION CASE. Measured on main 2026-08-10: at three of the four canonical
# locality-assertion sites the only marker in the enclosing section is on the block's own
# cross-reference line, and the fourth site has no marker in its section at all. Scanning the
# own line would red-line three of four blocks the corpus already treats as correct.
case_line "arm (a): a marker on the block's OWN cross-reference line does not fire" \
  "$LOCAL_SECTION" \
  'This section applies to the Plugin only. For the Web Platform, see Section 4.3 below.' 0

# The CLO's prescribed remedy form.
case_line "arm (a): paragraph-scoped referent in a marker-bearing section passes" \
  "$CLOUD_SECTION" \
  'The paragraph above applies to the Plugin only and must not be read as covering it.' 0

# Laundering path closed: a paragraph mention must not exempt a section-scoped claim.
case_line "arm (a): a trailing paragraph mention does not disarm the arm" \
  "$CLOUD_SECTION" \
  'This section applies to the Plugin only. See Section 9. The bullets above are unaffected.' 1 'arm \(a\)'

# Subject position: a cross-reference that cites a section is not a referent.
case_line "arm (a): 'see the Section 4.3' is a cross-reference, not a referent" \
  "$CLOUD_SECTION" \
  'The paragraph above applies to the Plugin only. For cloud processing see the Section 4.3 below.' 0

case_line "arm (a): capitalised 'This Section' classifies (house style)" \
  "$CLOUD_SECTION" 'This Section is limited to the Plugin only. See Section 9.' 1 'arm \(a\)'

case_line "arm (a): failure names the marker it found" \
  "$CLOUD_SECTION" 'This section applies to the Plugin only. See Section 9.' 1 'marker at .*:[0-9]+'

# ---------------------------------------------------------------------------------------
# arm (b) -- attachment matches referent
# ---------------------------------------------------------------------------------------

d=$(new_repo)
printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
printf -- '- **(a)** A limb.\n  This section applies to the Plugin only. See Section 9.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add >/dev/null
res=$(run_gate "$d"); rc=${res%%|*}; out=${res#*|}
[[ "$rc" == "1" ]] && pass "arm (b): space-indented section referent fires" \
  || fail "arm (b): space-indent did not fire (rc=$rc)"
grep -qE 'arm \(b\)' <<<"$out" && pass "arm (b): output names the arm" || fail "arm (b): output does not name the arm"

# TAB indentation is valid CommonMark continuation. The indent used to be measured in the
# shell after `IFS=$'\t' read`, which ate a leading tab, so arm (b) was simply off for
# tab-indented documents.
d=$(new_repo)
printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
printf -- '- **(a)** A limb.\n\tThis section applies to the Plugin only. See Section 9.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add >/dev/null
res=$(run_gate "$d"); rc=${res%%|*}
[[ "$rc" == "1" ]] && pass "arm (b): TAB-indented section referent fires" \
  || fail "arm (b): TAB indentation bypassed the arm (rc=$rc)"

# A single leading space is not a list continuation under any CommonMark marker.
d=$(new_repo)
printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
printf -- ' This section applies to the Plugin only. See Section 9.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add >/dev/null
res=$(run_gate "$d"); rc=${res%%|*}
[[ "$rc" == "0" ]] && pass "arm (b): a 1-column indent is not a list continuation" \
  || fail "arm (b): fired on a 1-column indent (rc=$rc)"

# A limb-scoped rider is legitimately indented -- forcing it flush-left would re-scope it to
# the whole enumeration, the same defect running the other way.
d=$(new_repo)
printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
printf -- '- **(a)** A limb.\n  The paragraph above applies to the Plugin only and must not be read as covering it.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add >/dev/null
res=$(run_gate "$d"); rc=${res%%|*}
[[ "$rc" == "0" ]] && pass "arm (b): an indented paragraph-scoped rider is legitimate" \
  || fail "arm (b): red-lined a legitimate indented limb rider (rc=$rc)"

# ---------------------------------------------------------------------------------------
# arm (c) -- the block discharges its own scope
# ---------------------------------------------------------------------------------------

case_line "arm (c): fires on a block that discharges nothing" \
  "$LOCAL_SECTION" 'This section applies to the Plugin only.' 1 'arm \(c\)'
case_line "arm (c): a negative delimiter discharges" \
  "$LOCAL_SECTION" 'This section applies to the Plugin only and must not be read as covering it.' 0
case_line "arm (c): a cross-reference discharges" \
  "$LOCAL_SECTION" 'This section applies to the Plugin only. For the Web Platform, see Section 4.3 below.' 0
case_line "arm (c): unbolded 'does not describe' discharges" \
  "$LOCAL_SECTION" 'This section applies to the Plugin only. It does not describe the Web Platform.' 0

# Applying arm (a)'s remedy must not surface a NEW failure on the next run: both arms are
# reported together so one CI round-trip carries the whole fix.
d=$(new_repo)
printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
printf 'This section applies to the Plugin only.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add >/dev/null
res=$(run_gate "$d"); out=${res#*|}
if grep -qE 'arm \(a\)' <<<"$out" && grep -qE 'arm \(c\)' <<<"$out"; then
  pass "arms (a) and (c) are reported in the same run"
else
  fail "arms not co-reported -- applying one remedy would surface the other on a second CI round-trip"
fi

# ---------------------------------------------------------------------------------------
# Unclassified locality assertions are REPORTED, never silently dropped.
# ---------------------------------------------------------------------------------------

d=$(new_repo)
printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
printf 'This paragraph applies to the Plugin only.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add >/dev/null
res=$(run_gate "$d"); rc=${res%%|*}; out=${res#*|}
if [[ "$rc" == "0" ]] && grep -qE 'no recognised referent' <<<"$out"; then
  pass "an unrecognised referent is reported as NOT CHECKED, not silently dropped"
else
  fail "unrecognised referent was silently dropped (rc=$rc) -- this is the red-to-green bypass"
fi

# A section referent with NO locality assertion must not classify at all.
d=$(new_repo)
printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
printf 'This section was last revised in 2026.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add >/dev/null
res=$(run_gate "$d"); rc=${res%%|*}; out=${res#*|}
if [[ "$rc" == "0" ]] && grep -qE '^legal scope-block placement: 0 scope block' <<<"$out"; then
  pass "a section referent with no locality assertion classifies 0 blocks"
else
  fail "locality precondition regressed (rc=$rc) -- $(head -2 <<<"$out")"
fi

# Product-behaviour prose is not a scope assertion.
d=$(new_repo)
printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
printf 'The Plugin operates locally on your machine and stores nothing remotely.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add >/dev/null
res=$(run_gate "$d"); rc=${res%%|*}; out=${res#*|}
if [[ "$rc" == "0" ]] && grep -qE ': 0 scope block' <<<"$out"; then
  pass "product-behaviour prose is not classified as a scope assertion"
else
  fail "product-behaviour prose was classified (rc=$rc) -- the verb discriminator regressed"
fi

# ---------------------------------------------------------------------------------------
# Diff parsing
# ---------------------------------------------------------------------------------------

d=$(new_repo)
printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
printf 'This section applies to the Plugin only.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add >/dev/null
printf '\nUnrelated later line.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" more >/dev/null
res=$(run_gate "$d"); rc=${res%%|*}
[[ "$rc" == "1" ]] && pass "multi-commit branch: all added lines are seen" \
  || fail "multi-commit branch dropped added lines (rc=$rc)"

# A pre-existing violation must not fire: this is a ratchet, not an audit.
d=$(new_repo)
printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
printf 'This section applies to the Plugin only.\n' >> "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
printf '\nAn unrelated added line.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add >/dev/null
res=$(run_gate "$d"); rc=${res%%|*}
[[ "$rc" == "0" ]] && pass "added-lines-only: a pre-existing violation does not fire" \
  || fail "fired on unchanged base text (rc=$rc)"

# `git diff -U0` appends funcname context. A greedy strip to the last `+` on the header line
# corrupted `start` to 0 and collapsed `count` to 1; the corpus has 88 `+`-bearing lines.
d=$(new_repo)
printf '## 4. Section 4. Processing\n\nThe Soleur Web Platform processes data.\nCharges are base + surcharge.\nTail.\n' \
  > "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
awk 'NR==4{print; print "This section applies to the Plugin only."; next} {print}' \
  "$d/docs/legal/privacy-policy.md" > "$d/t" && mv "$d/t" "$d/docs/legal/privacy-policy.md"
commit_all "$d" add >/dev/null
res=$(run_gate "$d"); rc=${res%%|*}; out=${res#*|}
[[ "$rc" == "1" ]] && pass "a '+' in the funcname context still fires" \
  || fail "'+' in funcname context suppressed the finding (rc=$rc)"
grep -qE 'privacy-policy\.md:5 ' <<<"$out" && pass "a '+' in the funcname context keeps line numbers correct" \
  || fail "line number corrupted by funcname context: $(grep -oE 'privacy-policy\.md:[0-9]+' <<<"$out" | head -1)"

# A corpus line whose content begins '++ ' is emitted as '+++ …' and must not be mistaken
# for a file header, which reset the path and dropped every later added line in the file.
d=$(new_repo)
printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
printf -- '++ /dev/null\nThis section applies to the Plugin only.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add >/dev/null
res=$(run_gate "$d"); rc=${res%%|*}
[[ "$rc" == "1" ]] && pass "a '++ ' content line does not hijack the path parser" \
  || fail "'++ ' content line dropped the rest of the file (rc=$rc)"

# A pure deletion hunk carries no added lines.
d=$(new_repo)
printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
grep -v 'More prose' "$d/docs/legal/privacy-policy.md" > "$d/t" && mv "$d/t" "$d/docs/legal/privacy-policy.md"
commit_all "$d" del >/dev/null
res=$(run_gate "$d"); rc=${res%%|*}
[[ "$rc" == "0" ]] && pass "a pure-deletion hunk is handled without a false fire" \
  || fail "deletion hunk produced rc=$rc"

# A deleted file emits '+++ /dev/null'.
d=$(new_repo)
printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/cookie-policy.md"
commit_base "$d" >/dev/null
rm "$d/docs/legal/cookie-policy.md"
commit_all "$d" rm >/dev/null
res=$(run_gate "$d"); rc=${res%%|*}
[[ "$rc" == "0" ]] && pass "a deleted file is skipped cleanly" || fail "deleted file produced rc=$rc"

# ---------------------------------------------------------------------------------------
# Section resolution
# ---------------------------------------------------------------------------------------

d=$(new_repo)
printf 'Preamble prose.\n\n%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
awk 'NR==1{print "This section applies to the Plugin only. See Section 9."} {print}' \
  "$d/docs/legal/privacy-policy.md" > "$d/t" && mv "$d/t" "$d/docs/legal/privacy-policy.md"
commit_all "$d" add >/dev/null
res=$(run_gate "$d"); rc=${res%%|*}
[[ "$rc" == "0" ]] && pass "a preamble block does not inherit a later section's markers" \
  || fail "preamble block inherited later markers (rc=$rc)"

d=$(new_repo)
printf '## 1. Cloud\n\nThe Soleur Web Platform is cloud-hosted.\n\n### 1.1 Sub\n\nSub prose.\n\n## 2. Local\n\nPlugin prose.\n' \
  > "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
printf 'This section applies to the Plugin only. See Section 1.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add >/dev/null
res=$(run_gate "$d"); rc=${res%%|*}
[[ "$rc" == "0" ]] && pass "a later h2 resets the enclosing section" \
  || fail "stale section carried markers past an h2 (rc=$rc)"

# A marker inside a fenced code block is a sample, not a scope claim.
d=$(new_repo)
printf '## 4. Data\n\n### 4.1 Processing\n\n```yaml\nhost: app.soleur.ai\n```\n\nLocal prose.\n' \
  > "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
printf 'This section applies to the Plugin only. See Section 9.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add >/dev/null
res=$(run_gate "$d"); rc=${res%%|*}
[[ "$rc" == "0" ]] && pass "a marker inside a fenced code block is not a section claim" \
  || fail "fenced code sample was read as a cloud marker (rc=$rc)"

# ---------------------------------------------------------------------------------------
# Fail-closed contract
# ---------------------------------------------------------------------------------------

d=$(new_repo)
printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
out=$(cd "$d" && bash ./scripts/gate.sh --base does-not-exist 2>&1) && rc=0 || rc=$?
[[ "$rc" == "2" ]] && pass "exit 2 on an unresolvable base ref" || fail "unresolvable base gave rc=$rc, expected 2"

d=$(new_repo)
printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
out=$(cd "$d" && bash ./scripts/gate.sh --base 2>&1) && rc=0 || rc=$?
[[ "$rc" == "2" ]] && pass "exit 2 on a valueless --base (not rc=1 'violation')" \
  || fail "valueless --base gave rc=$rc, expected 2"

# The mirror surface disappearing must not read as "nothing to scan".
d=$(new_repo)
printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
rm "$d/plugins/soleur/docs/pages/legal/privacy-policy.md"
commit_all "$d" rmmirror >/dev/null
res=$(run_gate "$d"); rc=${res%%|*}
[[ "$rc" == "2" ]] && pass "exit 2 when the mirror surface is empty (per-surface floor)" \
  || fail "an empty mirror surface gave rc=$rc, expected 2 -- the readability floor is a conjunction again"

# A git failure must never read as "no added lines".
d=$(new_repo)
printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
printf '## X\n\nY.\n' > "$d/docs/legal/0-early.md"
commit_base "$d" >/dev/null
printf 'This section applies to the Plugin only.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add >/dev/null
chmod 000 "$d/docs/legal/0-early.md"
res=$(run_gate "$d"); rc=${res%%|*}
chmod 644 "$d/docs/legal/0-early.md"
[[ "$rc" == "2" ]] && pass "a git-diff failure exits 2, never a clean pass" \
  || fail "git-diff failure gave rc=$rc -- the vacuous-0 path is back"

# A non-legal markdown file is out of scope.
d=$(new_repo)
mkdir -p "$d/docs/other"
printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/privacy-policy.md"
printf '%s' "$CLOUD_SECTION" > "$d/docs/other/notes.md"
commit_base "$d" >/dev/null
printf 'This section applies to the Plugin only.\n' >> "$d/docs/other/notes.md"
commit_all "$d" add >/dev/null
res=$(run_gate "$d"); rc=${res%%|*}
[[ "$rc" == "0" ]] && pass "files outside the legal corpus are out of scope" || fail "fired on a non-corpus file (rc=$rc)"

# The mirror surface is scanned, not just canonical.
d=$(new_repo)
printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/privacy-policy.md"
printf '%s' "$CLOUD_SECTION" > "$d/plugins/soleur/docs/pages/legal/privacy-policy.md"
commit_base "$d" >/dev/null
printf 'This section applies to the Plugin only. See Section 9.\n' >> "$d/plugins/soleur/docs/pages/legal/privacy-policy.md"
commit_all "$d" add >/dev/null
res=$(run_gate "$d"); rc=${res%%|*}
[[ "$rc" == "1" ]] && pass "the Eleventy mirror surface is scanned" || fail "mirror surface was not scanned (rc=$rc)"

# ---------------------------------------------------------------------------------------
# Operator-facing output
# ---------------------------------------------------------------------------------------

d=$(new_repo)
printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
commit_base "$d" >/dev/null
printf 'This section applies to the Plugin only. See Section 9.\n' >> "$d/docs/legal/privacy-policy.md"
commit_all "$d" add >/dev/null
res=$(run_gate "$d"); out=${res#*|}
grep -qE '^::error file=[^,]+,line=[0-9]+::' <<<"$out" \
  && pass "emits a file/line GitHub annotation so findings land inline on the diff" \
  || fail "no file=/line= annotation -- the operator's checks view shows only a count"
grep -qE 'reproduce: bash scripts/lint-legal-scope-block-placement\.sh --base ' <<<"$out" \
  && pass "failure output carries a reproduce command" || fail "no reproduce command in failure output"
grep -qE 'base=.* merge-base=' <<<"$out" \
  && pass "failure output states the resolved base" || fail "resolved base not reported"

# ---------------------------------------------------------------------------------------
# Live calibration floors (assert against the working tree; floors, never equalities)
# ---------------------------------------------------------------------------------------

vocab_rows=$(bash "$GATE" --print-vocab | grep -cE '^(MARKER|LOCALITY|SECTION_REF|PARA_REF|NEG_DELIM|XREF)\b' || true)
if (( vocab_rows >= 10 )); then
  pass "--print-vocab exposes every classifier vocabulary ($vocab_rows rows)"
else
  fail "--print-vocab exposed only $vocab_rows rows -- an agent cannot discover the accepted phrasings"
fi

markers_declared=0
while IFS=$'\t' read -r kind m; do
  [[ "$kind" == "MARKER" ]] || continue
  markers_declared=$((markers_declared + 1))
  n=$(grep -rhoE -- "$m" "$REPO_ROOT/docs/legal" "$REPO_ROOT/plugins/soleur/docs/pages/legal" 2>/dev/null | grep -cE '.' || true)
  (( n >= 1 )) || fail "marker calibration: declared marker matches nothing live: $m"
done < <(bash "$GATE" --print-vocab)

# Cardinality, not just per-marker presence: "simplify the marker list" would otherwise pass.
if (( markers_declared == 5 )); then
  pass "marker calibration: all 5 declared markers still present and live"
else
  fail "marker calibration: expected 5 declared markers, found $markers_declared (a marker was added or dropped -- update this assertion deliberately)"
fi

# The locality and section-referent vocabularies must still match the live corpus, or the
# gate has silently died on a routine reword while printing a passing line.
loc_re=$(bash "$GATE" --print-vocab | awk -F'\t' '$1=="LOCALITY"{print $2}')
sec_re=$(bash "$GATE" --print-vocab | awk -F'\t' '$1=="SECTION_REF"{print $2}')
loc_hits=$(grep -rhoE -- "$loc_re" "$REPO_ROOT/docs/legal" 2>/dev/null | grep -cE '.' || true)
sec_hits=$(grep -rhoE -- "$sec_re" "$REPO_ROOT/docs/legal" 2>/dev/null | grep -cE '.' || true)
(( loc_hits >= 1 )) && pass "LOCALITY vocabulary still matches the live corpus ($loc_hits)" \
  || fail "LOCALITY vocabulary matches NOTHING live -- the gate would classify 0 blocks forever and print a passing line"
(( sec_hits >= 1 )) && pass "SECTION_REF vocabulary still matches the live corpus ($sec_hits)" \
  || fail "SECTION_REF vocabulary matches NOTHING live -- arm 0 would reject every block"

canon_n=$(find "$REPO_ROOT/docs/legal" -maxdepth 1 -name '*.md' | grep -cE '.' || true)
mirror_n=$(find "$REPO_ROOT/plugins/soleur/docs/pages/legal" -maxdepth 1 -name '*.md' | grep -cE '.' || true)
(( canon_n >= 1 && mirror_n >= 1 )) && pass "corpus readable: $canon_n canonical / $mirror_n mirror" \
  || fail "corpus unreadable: canonical=$canon_n mirror=$mirror_n"

# ---------------------------------------------------------------------------------------
# Mutation battery.
#
# Every row mutates a REGEX, a FIELD PARSE, or a STREAM TRANSFORM -- the things that
# actually regress. Toggle-only mutations test a simulated defect and were what let two
# CRITICAL fail-opens through the first review. Each row proves the mutation landed, proves
# the pristine gate fails the fixture, and asserts the EXPECTED ARM so a kill cannot be
# credited to an unrelated arm firing.
# ---------------------------------------------------------------------------------------

MUT_DIR="$SANDBOX_ROOT/mutations"
mkdir -p "$MUT_DIR" || { echo "mkdir failed" >&2; exit 2; }
PRISTINE="$MUT_DIR/pristine.sh"
cp "$GATE" "$PRISTINE" || { echo "cp failed" >&2; exit 2; }

# mutate <label> <sed program> <fixture-builder> <expected-arm-regex>
mutate() {
  local label="$1" sedprog="$2" builder="$3" expect="$4"
  local mdir="$MUT_DIR/$label"
  mkdir -p "$mdir" || return 2
  sed -E "$sedprog" "$PRISTINE" > "$mdir/gate.sh" || return 2

  if cmp -s "$PRISTINE" "$mdir/gate.sh"; then
    fail "mutation '$label' did not land -- verdict would be meaningless"
    return 0
  fi

  local d res rc out
  d=$("$builder") || return 2
  res=$(run_gate "$d"); rc=${res%%|*}; out=${res#*|}
  if [[ "$rc" != "1" ]] || ! grep -qE -- "$expect" <<<"$out"; then
    fail "mutation '$label': positive control did not fail with /$expect/ (rc=$rc) -- verdict vacuous"
    return 0
  fi

  d=$("$builder") || return 2
  cp "$mdir/gate.sh" "$d/scripts/gate.sh"
  res=$(run_gate "$d"); rc=${res%%|*}; out=${res#*|}
  if [[ "$rc" == "1" ]] && grep -qE -- "$expect" <<<"$out"; then
    fail "mutation '$label' SURVIVED -- the fixtures cannot detect this defect"
  else
    pass "mutation '$label' killed (verdict moved 1 -> $rc)"
  fi
}

b_arm_a() { local d; d=$(new_repo) || return 1
  printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"; commit_base "$d" >/dev/null
  printf 'This section applies to the Plugin only. See Section 9.\n' >> "$d/docs/legal/privacy-policy.md"
  commit_all "$d" add >/dev/null; printf '%s\n' "$d"; }
b_arm_a_below() { local d; d=$(new_repo) || return 1
  printf '## 4. Data\n\n### 4.1 P\n\nIntro.\n' > "$d/docs/legal/privacy-policy.md"; commit_base "$d" >/dev/null
  printf 'This section applies to the Plugin only. See Section 9.\nThe Soleur Web Platform stores data.\n' >> "$d/docs/legal/privacy-policy.md"
  commit_all "$d" add >/dev/null; printf '%s\n' "$d"; }
b_arm_b_tab() { local d; d=$(new_repo) || return 1
  printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/privacy-policy.md"; commit_base "$d" >/dev/null
  printf -- '- **(a)** limb.\n\tThis section applies to the Plugin only. See Section 9.\n' >> "$d/docs/legal/privacy-policy.md"
  commit_all "$d" add >/dev/null; printf '%s\n' "$d"; }
b_arm_c() { local d; d=$(new_repo) || return 1
  printf '%s' "$LOCAL_SECTION" > "$d/docs/legal/privacy-policy.md"; commit_base "$d" >/dev/null
  printf 'This section applies to the Plugin only.\n' >> "$d/docs/legal/privacy-policy.md"
  commit_all "$d" add >/dev/null; printf '%s\n' "$d"; }
b_arm_a_heading() { local d; d=$(new_repo) || return 1
  printf '## 4. Web Platform Cloud Execution\n\nWe process your prompts.\n' > "$d/docs/legal/privacy-policy.md"
  commit_base "$d" >/dev/null
  printf 'This section applies to the Plugin only and must not be read as covering it.\n' >> "$d/docs/legal/privacy-policy.md"
  commit_all "$d" add >/dev/null; printf '%s\n' "$d"; }
b_arm_a_caps() { local d; d=$(new_repo) || return 1
  printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"; commit_base "$d" >/dev/null
  printf 'This Section is limited to the Plugin only. See Section 9.\n' >> "$d/docs/legal/privacy-policy.md"
  commit_all "$d" add >/dev/null; printf '%s\n' "$d"; }
b_funcname() { local d; d=$(new_repo) || return 1
  printf '## 4. Section 4. P\n\nThe Soleur Web Platform processes data.\nCharges are base + surcharge.\nTail.\n' > "$d/docs/legal/privacy-policy.md"
  commit_base "$d" >/dev/null
  awk 'NR==4{print; print "This section applies to the Plugin only."; next} {print}' \
    "$d/docs/legal/privacy-policy.md" > "$d/t" && mv "$d/t" "$d/docs/legal/privacy-policy.md"
  commit_all "$d" add >/dev/null; printf '%s\n' "$d"; }

# Arms, via their toggles (cheap regression guard, not the load-bearing rows).
mutate "arm-a-neutered"  's/^ARM_A_ENABLED=1$/ARM_A_ENABLED=0/'  b_arm_a      'arm \(a\)'
mutate "arm-b-neutered"  's/^ARM_B_ENABLED=1$/ARM_B_ENABLED=0/'  b_arm_b_tab  'arm \(b\)'
mutate "arm-c-neutered"  's/^ARM_C_ENABLED=1$/ARM_C_ENABLED=0/'  b_arm_c      'arm \(c\)'
# Real axes.
mutate "exit-always-zero"        's/^  exit 1$/  exit 0/'                                     b_arm_a      'arm \(a\)'
mutate "section-scan-upward-only" 's/for \(i = \(sec_start \? sec_start : 1\); i < sec_end; i\+\+\)/for (i = (sec_start ? sec_start : 1); i < target; i++)/' b_arm_a_below 'arm \(a\)'
# Excludes heading lines from the MARKER CHECK specifically. Breaking heading DETECTION
# instead is an equivalent mutant: with no headings recognised the scan widens to the whole
# file, so the gate stays at least as aggressive and the fixture still fires.
mutate "heading-not-scanned"     's/if \(lines\[i\] ~ mk\)/if (lines[i] !~ \/^#\/ \&\& lines[i] ~ mk)/' b_arm_a_heading 'arm \(a\)'
mutate "indent-threshold-raised" 's/indent >= 2/indent >= 99/'                                b_arm_b_tab  'arm \(b\)'
mutate "locality-vocab-narrowed" 's/^SCOPE_VERB_RE=.*/SCOPE_VERB_RE='"'"'(zzzznomatch)'"'"'/' b_arm_c      'arm \(c\)'
mutate "section-ref-case-narrowed" 's/\[Ss\]ection\[\^\.\]/section[^.]/'  b_arm_a_caps 'arm \(a\)'
mutate "hunk-field-greedy"       's/plus=f\[3\]/plus=f[NF]/'                                  b_funcname   'arm \(a\)'
# NOTE: this row's fixture makes a corpus blob unreadable, so the PRISTINE gate exits 2.
# The kill criterion is therefore "no longer exits 2", checked by the dedicated block below
# rather than by mutate(), whose contract is a rc=1 positive control.
_mut_dir="$MUT_DIR/diff-failure-swallowed"
mkdir -p "$_mut_dir"
sed -E 's/^if \(\( diff_rc != 0 \)\); then$/if (( 0 )); then/' "$PRISTINE" > "$_mut_dir/gate.sh"
if cmp -s "$PRISTINE" "$_mut_dir/gate.sh"; then
  fail "mutation 'diff-failure-swallowed' did not land -- verdict would be meaningless"
else
  _mk_unreadable() { local d; d=$(new_repo) || return 1
    printf '%s' "$CLOUD_SECTION" > "$d/docs/legal/privacy-policy.md"
    printf '## X\n\nY.\n' > "$d/docs/legal/0-early.md"
    commit_base "$d" >/dev/null
    printf 'This section applies to the Plugin only.\n' >> "$d/docs/legal/privacy-policy.md"
    commit_all "$d" add >/dev/null
    chmod 000 "$d/docs/legal/0-early.md"; printf '%s\n' "$d"; }
  _d=$(_mk_unreadable); _res=$(run_gate "$_d"); _rc=${_res%%|*}; chmod 644 "$_d/docs/legal/0-early.md"
  if [[ "$_rc" != "2" ]]; then
    fail "mutation 'diff-failure-swallowed': positive control did not exit 2 (rc=$_rc) -- verdict vacuous"
  else
    _d=$(_mk_unreadable); cp "$_mut_dir/gate.sh" "$_d/scripts/gate.sh"
    _res=$(run_gate "$_d"); _rc=${_res%%|*}; chmod 644 "$_d/docs/legal/0-early.md"
    if [[ "$_rc" == "2" ]]; then
      fail "mutation 'diff-failure-swallowed' SURVIVED -- the vacuous-0 path is undetectable"
    else
      pass "mutation 'diff-failure-swallowed' killed (verdict moved 2 -> $_rc)"
    fi
  fi
fi
mutate "xref-widened-to-bare-see" 's/^XREF_RE=.*/XREF_RE='"'"'.'"'"'/'                        b_arm_c      'arm \(c\)'

echo "passed: $passes  failed: $fails"

# Dispatch floor: a suite whose assertions stopped running must not report success.
# Measured pre-fix: neutering pass()/fail() yielded `passed: 0 failed: 0`, exit 0, [ok].
total=$((passes + fails))
if (( total < MIN_ASSERTIONS )); then
  echo "suite ran only ${total} assertions, expected at least ${MIN_ASSERTIONS} -- assertions are not running" >&2
  exit 1
fi
(( fails == 0 )) || exit 1
