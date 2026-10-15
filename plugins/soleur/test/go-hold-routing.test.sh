#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2015,SC2016  # row functions are dispatched indirectly; A && B || C is the assertion idiom; literals are single-quoted on purpose
# Guard 6 of the CTO standing-delegation plan
# (knowledge-base/project/plans/2026-10-15-feat-cto-standing-delegation-and-production-envelope-plan.md).
#
# PROPERTY. `plugins/soleur/commands/go.md` carries ONE hold-routing paragraph, placed OUTSIDE the
# eval-gated go-routing block, and the block itself is byte-identical to the merge base. The second
# half is what keeps the eval gate a no-op: an edit inside the markers would demand a paid eval run
# (see plugins/soleur/skills/eval-harness/gated-skills.json), and this feature is routing prose around
# the table, not a routing change.
#
# Members of the paragraph: the routing condition (an epic reference `#N` AND a structured `HOLDS:` list,
# BOTH required: a message that only says `ask the operator` is an ordinary message), the fail-closed wording,
# the ask-once wording, the owner (the CTO's "Own the epic" interface), the Gate: predicate hand-off to ship
# Phase 6 with the container-format link, the verifier `render` call made by the CALLING skill after the real
# question (whose text must render the Scope items, the expiry, 30 days, every merge and every dispatch listed,
# posted publicly, and the outcome in business terms), the headless behaviour, ${CLAUDE_PLUGIN_ROOT} script
# paths, the execution-sentence wiring and the stop sequence (delete, disarm, cancel, say what remains).
#
# PR-TIME CHECKS. The merge-base anchor describes THIS PR's diff. After the merge the merge base IS HEAD, so on
# the real file the anchored properties are SKIPPED with a printed reason (never a silent pass); the mutation
# rows still compare a changed file against the base and stay meaningful. Rows match the violation token as an
# EXACT line (`V:x` is not satisfied by `V:x-y`).
#
# ANCHOR. The block's hash is compared with `git show $(git merge-base origin/main HEAD):<go.md>`, a
# value that lives OUTSIDE the commit under test. An unresolvable base is a FAIL, never a skip (H1):
# a guard that skips when its anchor is missing reports green exactly where it cannot see.
#
# Every mutation row asserts the REASON it reds (a violation token), not merely that it reds, so a row
# cannot be satisfied by an unrelated failure. The population (the paragraph) is DERIVED from the
# file; a floor requires the extractor to have found it (a parity check over an empty set is green).
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
GO_REL="plugins/soleur/commands/go.md"
GO_MD="$ROOT/$GO_REL"

passes=0; fails=0; asserted=0; FAILED=()
VERDICT_LOG="$(mktemp -t go-hold-routing.XXXXXXXX.log)" || { printf 'FATAL: no scratch\n' >&2; exit 2; }

# Canonical body, asserted byte-for-byte against every other copy by fixture-dir-operand-assert.test.sh.
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
SANDBOX="$(mktemp -d -t gohold.XXXXXXXX)" || { printf 'FATAL: no scratch root\n' >&2; exit 2; }
assert_fixture_dir "$SANDBOX"
trap 'rm -rf "$SANDBOX"; rm -f "$VERDICT_LOG"' EXIT

ok()  { printf '  PASS: %s\n' "$1"; printf 'PASS\n' >> "$VERDICT_LOG"; passes=$((passes + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; printf 'FAIL\n' >> "$VERDICT_LOG"; fails=$((fails + 1)); FAILED+=("$1"); }
ck()  { asserted=$((asserted + 1)); }
skips=0
skip() { printf '  SKIP: %s\n' "$1"; printf 'SKIP\n' >> "$VERDICT_LOG"; skips=$((skips + 1)); }

# --- instrument self-test: both verdict helpers must record before anything is trusted ----------
_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ ok "self-test"; bad "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
passes=0; fails=0; asserted=0; skips=0; FAILED=(); : > "$VERDICT_LOG"

[[ -r "$GO_MD" ]] || { printf 'FATAL: cannot read %s\n' "$GO_MD" >&2; exit 2; }
command -v git >/dev/null || { printf 'FATAL: git required\n' >&2; exit 2; }

# The block markers are ASSEMBLED, never written out: eval-harness's registry-completeness test
# `git grep`s plugins/soleur/ for `eval-gate:block:<id>:start` and requires each id exactly once, so a
# literal copy here would register as a duplicate gated block.
GATED_BLOCK_ID="go-routing"
BLOCK_START="<!-- eval-gate:block:${GATED_BLOCK_ID}:start -->"
BLOCK_END="<!-- eval-gate:block:${GATED_BLOCK_ID}:end -->"
HEADING_RE='^#+ .*Hold routing [(]pre-route[)]'

# git, read-only, with the git-location variables swept off the invocation (a linked worktree exports
# GIT_DIR / GIT_INDEX_FILE to hooks; neither is wanted here).
g() { env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_COMMON_DIR git -C "$ROOT" "$@"; }

hash_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
  else shasum -a 256 | awk '{print $1}'; fi
}

# Everything from the start marker to the end marker, inclusive, of file $1.
block_of() {
  awk -v s="$BLOCK_START" -v e="$BLOCK_END" '
    index($0, s) { f = 1 }
    f { print }
    index($0, e) { f = 0 }' "$1"
}

# One awk program, four modes, so extraction and every mutation agree on what "the paragraph" is:
# from the heading line to the line before the next heading or either marker.
#   extract : print the paragraph          strip : print the file without it
#   sub     : print the file with `from` -> `to` applied inside the paragraph only (case-insensitive)
para_awk() {
  local mode="$1" file="$2" from="${3:-}" to="${4:-}"
  awk -v mode="$mode" -v hre="$HEADING_RE" -v s="$BLOCK_START" -v e="$BLOCK_END" -v from="$from" -v to="$to" '
    function endsPara(l) { return (l ~ /^#+ /) || index(l, s) || index(l, e) }
    {
      if (!inp && $0 ~ hre) { inp = 1; started++ }
      else if (inp && endsPara($0)) { inp = 0 }
      if (mode == "extract") { if (inp) print; next }
      if (mode == "strip")   { if (!inp) print; next }
      if (mode == "sub") {
        line = $0
        if (inp && from != "") {
          low = tolower(line); lf = tolower(from); out = ""
          while ((i = index(low, lf)) > 0) {
            out = out substr(line, 1, i - 1) to
            line = substr(line, i + length(from)); low = substr(low, i + length(from))
          }
          line = out line
        }
        print line
      }
    }' "$file"
}

# evaluate <go.md> <base-ref> : print one `V:<token>` line per violated property, return 0 iff none.
base_blob_of() { # <base> <rel-path>; a base written `file:<path>` reads that file (the degenerate-anchor control)
  case "$1" in file:*) cat "${1#file:}" 2>/dev/null ;; *) g show "$1:$2" 2>/dev/null ;; esac
}
evaluate() { # <go.md> <base> [check|skip]   skip = the merge-base anchor is not evaluated (base == HEAD)
  local f="$1" base="$2" anchor="${3:-check}" para v=0 bh gh start_ln end_ln head_ln step1_ln base_blob
  emit() { printf 'V:%s\n' "$1"; v=1; }
  para="$(para_awk extract "$f")"

  # Members are checked against $para unconditionally: an EMPTY paragraph then fails every member too,
  # so a missing paragraph can never read as a pass on the properties that live inside it.
  [[ -n "$para" ]]                         || emit paragraph-missing
  [[ "$para" == *'`HOLDS:`'* ]]            || emit token-HOLDS
  [[ "$para" == *'`#N`'* ]]                || emit token-epic-ref
  [[ "$para" == *'only when'* && "$para" == *'BOTH'* ]] || emit routing-requires-both
  [[ "$para" == *'`ask the operator`'* && "$para" == *'ordinary message'* ]] || emit ask-the-operator-not-a-trigger
  [[ "$para" == *'fail closed'* || "$para" == *'Fail closed'* ]] || emit wording-fail-closed
  [[ "$para" == *'ask once'* || "$para" == *'Ask once'* ]]       || emit wording-ask-once
  [[ "$para" == *'soleur:engineering:cto'* && "$para" == *'Own the epic'* ]] || emit owner-cto-own-the-epic
  [[ "$para" == *'## Operator Holds'* && "$para" == *'Gate:'* && "$para" == *'hold-gate-eval.sh'* ]] || emit gate-handoff
  [[ "$para" == *'operator-holds.md'* ]]   || emit container-link
  [[ "$para" == *'delegation-verify.sh'* && "$para" == *'`render`'* && "$para" == *'calling skill'* && "$para" == *'AFTER'* ]] || emit delegation-render
  [[ "$para" == *'Scope items'* && "$para" == *'30 days'* && "$para" == *'every merge and every dispatch'* && "$para" == *'posted publicly'* && "$para" == *'business terms'* && "$para" == *'expiry'* ]] || emit render-text
  [[ "$para" == *'Headless'* && "$para" == *'do not ask'* && "$para" == *'action-required'* && "$para" == *'draft PR'* ]] || emit headless
  [[ "$para" == *'"${CLAUDE_PLUGIN_ROOT}/scripts/delegation-verify.sh"'* && "$para" == *'"${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/hold-gate-eval.sh"'* ]] || emit plugin-root-paths
  if [[ "$para" == *'plugins/soleur/'* ]]; then emit repo-relative-path; fi
  [[ "$para" == *'execution sentence'* && "$para" == *'run summary'* ]] || emit receipt-wiring
  [[ "$para" == *'AskUserQuestion'* ]]     || emit no-askuserquestion-for-technical-hold
  [[ "$para" == *'newest admin-authored marker comment decides'* && "$para" == *'invalid newest one means no delegation'* ]] || emit newest-decides
  [[ "$para" == *'delete every delegation comment'* && "$para" == *'gh api -X DELETE'* && "$para" == *'--disable-auto'* && "$para" == *'could not be stopped'* ]] || emit stop-sequence

  # Location: after the Step 1 heading, before the start marker, and never between the markers.
  start_ln="$(awk -v s="$BLOCK_START" 'index($0, s) { print NR; exit }' "$f")"
  end_ln="$(awk -v e="$BLOCK_END" 'index($0, e) { print NR; exit }' "$f")"
  head_ln="$(awk -v hre="$HEADING_RE" '$0 ~ hre { print NR; exit }' "$f")"
  step1_ln="$(awk '/^## Step 1: /{ print NR; exit }' "$f")"
  if [[ -z "$start_ln" || -z "$end_ln" || -z "$step1_ln" ]]; then
    emit anchors-missing
  elif [[ -n "$head_ln" ]]; then
    if [[ "$head_ln" -gt "$start_ln" && "$head_ln" -lt "$end_ln" ]]; then emit paragraph-inside-block
    elif [[ "$head_ln" -le "$step1_ln" || "$head_ln" -gt "$start_ln" ]]; then emit paragraph-misplaced; fi
  fi

  # Anchor: the block hash equals the merge base's (outside the commit under test).
  if [[ "$anchor" == skip ]]; then
    :
  elif ! base_blob="$(base_blob_of "$base" "$GO_REL")" || [[ -z "$base_blob" ]]; then
    emit base-unresolvable; emit block-hash-differs
  else
    # The anchor must be the real block (a degenerate base would make the comparison vacuous when base == HEAD).
    [[ "$(printf '%s\n' "$base_blob" | block_of /dev/stdin | grep -c '^| ' || true)" -ge 9 && "$base_blob" == *'## Step 2: Classify and Route'* ]] || emit base-degenerate
    bh="$(printf '%s\n' "$base_blob" | block_of /dev/stdin | hash_stdin)"
    gh="$(block_of "$f" | hash_stdin)"
    [[ -n "$bh" && "$bh" == "$gh" ]] || emit block-hash-differs
  fi
  return "$v"
}

BASE_REF="$(g merge-base origin/main HEAD 2>/dev/null || true)"
[[ -n "$BASE_REF" ]] || BASE_REF="refs/unresolvable-merge-base"

# --- real-file verdicts ----------------------------------------------------------------------------
HEAD_SHA="$(g rev-parse HEAD 2>/dev/null || true)"
ANCHOR_MODE=check; ANCHOR_REASON=""
if [[ -n "$HEAD_SHA" && "$BASE_REF" == "$HEAD_SHA" ]]; then
  ANCHOR_MODE=skip; ANCHOR_REASON="merge base == HEAD (this change is merged): the comparison would be self-identity; the invariants are PR-time checks"
fi
REAL_OUT="$(evaluate "$GO_MD" "$BASE_REF" "$ANCHOR_MODE")"; REAL_RC=$?
ALL_PROPS="paragraph-missing token-HOLDS token-epic-ref routing-requires-both ask-the-operator-not-a-trigger wording-fail-closed wording-ask-once owner-cto-own-the-epic gate-handoff container-link delegation-render render-text headless plugin-root-paths repo-relative-path receipt-wiring no-askuserquestion-for-technical-hold newest-decides stop-sequence anchors-missing paragraph-inside-block paragraph-misplaced base-unresolvable base-degenerate block-hash-differs"
for p in $ALL_PROPS; do
  ck
  case "$p" in base-unresolvable|base-degenerate|block-hash-differs)
    if [[ "$ANCHOR_MODE" == skip ]]; then skip "'$p' not evaluated: $ANCHOR_REASON"; continue; fi ;;
  esac
  if grep -Fxq -- "V:$p" <<<"$REAL_OUT"; then bad "go.md violates '$p'"; else ok "go.md has no violation of '$p'"; fi
done
ck
[[ "$REAL_RC" -eq 0 && -z "$REAL_OUT" ]] && ok "evaluate() agrees: rc=0 and no violation lines" || bad "evaluate() reported violations: ${REAL_OUT//$'\n'/ }"

# The merge-base anchor must never be a silent tautology: it resolves, its sha is printed, and base == HEAD
# (post-merge) is announced rather than passing quietly.
ck
if [[ "$BASE_REF" != refs/unresolvable-merge-base && -n "$(g rev-parse --verify --quiet "${BASE_REF}^{commit}" || true)" ]]; then
  ok "merge-base anchor resolves: ${BASE_REF:0:12} (HEAD ${HEAD_SHA:0:12})"
else bad "merge-base anchor does not resolve (origin/main is not fetched?)"; fi
[[ "$ANCHOR_MODE" == skip ]] && printf '  NOTE: %s\n' "$ANCHOR_REASON"

# one-shot carries the one-sentence pointer for a direct run (the go.md paragraph is not reachable from there).
ONE_SHOT_MD="$ROOT/plugins/soleur/skills/one-shot/SKILL.md"
ck
if [[ -r "$ONE_SHOT_MD" ]] && grep -Fq 'follows go.md Step 1.5 in headless form' "$ONE_SHOT_MD" && grep -Fq '`HOLDS:`' "$ONE_SHOT_MD"; then ok "one-shot points a direct HOLDS run at go.md Step 1.5 in headless form"
else bad "one-shot lost its pointer to go.md Step 1.5 for a direct run with a HOLDS brief"; fi

# Floor on the DERIVATION: exactly one hold-routing paragraph, non-trivial, and the block non-empty.
PARA_REAL="$(para_awk extract "$GO_MD")"
ck
[[ "$(printf '%s\n' "$PARA_REAL" | grep -Ec "$HEADING_RE" || true)" -eq 1 ]] && ok "exactly one hold-routing heading" || bad "expected exactly one hold-routing heading"
ck
[[ "${#PARA_REAL}" -ge 400 ]] && ok "paragraph extraction is non-trivial (${#PARA_REAL} bytes)" || bad "paragraph extraction yielded ${#PARA_REAL} bytes (floor 400)"
ck
[[ "$(block_of "$GO_MD" | grep -c '^| ' || true)" -ge 9 ]] && ok "go-routing block extraction found >= 9 table lines" || bad "go-routing block extraction found fewer than 9 table lines"

# --- mutation rows (each asserts the REASON) -------------------------------------------------------
# row <label> <mutated-file> <base> <expected-token|none>
row() {
  local label="$1" file="$2" base="$3" want="$4" out rc
  out="$(evaluate "$file" "$base")"; rc=$?
  ck
  if [[ "$want" == none ]]; then
    [[ "$rc" -eq 0 && -z "$out" ]] && ok "$label: stays green" || bad "$label: expected green, got ${out//$'\n'/ }"
  else
    [[ "$rc" -ne 0 ]] && grep -Fxq -- "V:$want" <<<"$out" && ok "$label: RED for '$want'" || bad "$label: expected RED for '$want', got rc=$rc ${out//$'\n'/ }"
  fi
}

M="$SANDBOX/m"; mkdir -p "$M"; assert_fixture_dir "$M"
nrows=0

# --- verdict-helper controls: a helper that can never fail turns every row below into noise ---------------
# Each control feeds a helper a known-bad input in a subshell (its ledger is /dev/null) and requires that the
# helper recorded a FAIL, or, for the green path, a PASS.
para_awk strip "$GO_MD" > "$M/ctl-bad.md"
ctl_fails() { ( VERDICT_LOG=/dev/null; b="$fails"; "$@" >/dev/null 2>&1; [[ "$fails" -gt "$b" ]] ); }
ctl_passes() { ( VERDICT_LOG=/dev/null; b="$passes"; "$@" >/dev/null 2>&1; [[ "$passes" -gt "$b" ]] ); }
ctl_fails row "ctl" "$M/ctl-bad.md" "$BASE_REF" none                  || { printf 'FATAL: control: row() accepted a RED file as green\n' >&2; exit 2; }
ctl_fails row "ctl" "$M/ctl-bad.md" "$BASE_REF" block-hash-differs     || { printf 'FATAL: control: row() accepted a RED file for the wrong token\n' >&2; exit 2; }
ctl_fails row "ctl" "$GO_MD" "$BASE_REF" paragraph-missing            || { printf 'FATAL: control: row() accepted a pristine file as RED\n' >&2; exit 2; }
ctl_passes row "ctl" "$M/ctl-bad.md" "$BASE_REF" paragraph-missing    || { printf 'FATAL: control: row() did not record a PASS for a correct RED row\n' >&2; exit 2; }
ctl_passes row "ctl" "$GO_MD" "$BASE_REF" none                        || { printf 'FATAL: control: row() did not record a PASS for a correct green row\n' >&2; exit 2; }
_o="$(evaluate "$M/ctl-bad.md" "$BASE_REF")"; _r=$?
[[ "$_r" -ne 0 && "$_o" == *'V:paragraph-missing'* ]] || { printf 'FATAL: control: evaluate() passed a file with no hold paragraph\n' >&2; exit 2; }
_o="$(evaluate "$GO_MD" "refs/does-not-exist")"; _r=$?
[[ "$_r" -ne 0 && "$_o" == *'V:base-unresolvable'* ]] || { printf 'FATAL: control: evaluate() passed with an unresolvable base\n' >&2; exit 2; }

# M1 edit one table cell inside the markers
awk -v s="$BLOCK_START" -v e="$BLOCK_END" '
  index($0, s) { f = 1 }
  f && !done && $0 ~ /^\| fix \|/ { sub(/broken behavior/, "broken behaviour"); done = 1 }
  index($0, e) { f = 0 }
  { print }' "$GO_MD" > "$M/m1.md"
row "M1 edit a table cell inside the markers" "$M/m1.md" "$BASE_REF" block-hash-differs; nrows=$((nrows + 1))

# M2 delete the paragraph (own dispatch: the extractor then yields nothing, and the floor says so)
para_awk strip "$GO_MD" > "$M/m2.md"
row "M2 delete the hold paragraph" "$M/m2.md" "$BASE_REF" paragraph-missing; nrows=$((nrows + 1))

# M3 move the paragraph inside the markers
printf '%s\n' "$PARA_REAL" > "$M/para.txt"
awk -v pf="$M/para.txt" -v s="$BLOCK_START" '
  BEGIN { while ((getline l < pf) > 0) pl[++np] = l }
  { print }
  index($0, s) { for (i = 1; i <= np; i++) print pl[i]; print "" }' "$M/m2.md" > "$M/m3.md"
row "M3 move the paragraph inside the markers" "$M/m3.md" "$BASE_REF" paragraph-inside-block; nrows=$((nrows + 1))

# M4 remove `ask the operator` while HOLDS stays (a second member after a compliant first)
para_awk sub "$GO_MD" '`ask the operator`' '`ask the owner`' > "$M/m4.md"
row "M4 remove the 'ask the operator' token, keep HOLDS" "$M/m4.md" "$BASE_REF" ask-the-operator-not-a-trigger; nrows=$((nrows + 1))

# M5 remove the HOLDS token while `ask the operator` stays
para_awk sub "$GO_MD" '`HOLDS:`' '`HOLD:`' > "$M/m5.md"
row "M5 remove the HOLDS: token, keep 'ask the operator'" "$M/m5.md" "$BASE_REF" token-HOLDS; nrows=$((nrows + 1))

# M6 / M7 the fail-closed and ask-once wording (both spellings are accepted, so both are neutralised)
para_awk sub "$GO_MD" 'fail closed' 'fail open' > "$M/m6.md"
row "M6 replace the fail-closed wording" "$M/m6.md" "$BASE_REF" wording-fail-closed; nrows=$((nrows + 1))
para_awk sub "$GO_MD" 'ask once' 'ask twice' > "$M/m7.md"
row "M7 replace the ask-once wording" "$M/m7.md" "$BASE_REF" wording-ask-once; nrows=$((nrows + 1))

# M8 the owner: the paragraph must hand the holds to the CTO's Own-the-epic interface
para_awk sub "$GO_MD" 'Own the epic' 'Rule' > "$M/m8.md"
row "M8 drop the Own-the-epic hand-off" "$M/m8.md" "$BASE_REF" owner-cto-own-the-epic; nrows=$((nrows + 1))

# M9 the Gate: hand-off to ship Phase 6
para_awk sub "$GO_MD" 'hold-gate-eval.sh' 'hold-check' > "$M/m9.md"
row "M9 drop the hold-gate-eval.sh hand-off" "$M/m9.md" "$BASE_REF" gate-handoff; nrows=$((nrows + 1))

# M10 the paragraph moved ABOVE Step 1 (still outside the markers, but not where the plan puts it)
awk -v pf="$M/para.txt" '
  BEGIN { while ((getline l < pf) > 0) pl[++np] = l }
  /^## Step 1: / && !done { for (i = 1; i <= np; i++) print pl[i]; print ""; done = 1 }
  { print }' "$M/m2.md" > "$M/m10.md"
row "M10 paragraph placed before Step 1" "$M/m10.md" "$BASE_REF" paragraph-misplaced; nrows=$((nrows + 1))

# M11..M19 one contract element each, removed from the paragraph only
para_awk sub "$GO_MD" 'BOTH' 'EITHER' > "$M/m11.md"
row "M11 routing no longer requires both the epic reference and the HOLDS list" "$M/m11.md" "$BASE_REF" routing-requires-both; nrows=$((nrows + 1))
para_awk sub "$GO_MD" '`#N`' 'a number' > "$M/m12.md"
row "M12 the epic reference is no longer required" "$M/m12.md" "$BASE_REF" token-epic-ref; nrows=$((nrows + 1))
para_awk sub "$GO_MD" 'operator-holds.md' 'holds-notes.md' > "$M/m13.md"
row "M13 the container-format link dropped" "$M/m13.md" "$BASE_REF" container-link; nrows=$((nrows + 1))
para_awk sub "$GO_MD" 'calling skill' 'agent' > "$M/m14.md"
row "M14 render is no longer the calling skill's step" "$M/m14.md" "$BASE_REF" delegation-render; nrows=$((nrows + 1))
para_awk sub "$GO_MD" '30 days' '90 days' > "$M/m15.md"
row "M15 the question no longer discloses the 30 days" "$M/m15.md" "$BASE_REF" render-text; nrows=$((nrows + 1))
para_awk sub "$GO_MD" 'Headless' 'Interactive' > "$M/m16.md"
row "M16 headless behaviour removed" "$M/m16.md" "$BASE_REF" headless; nrows=$((nrows + 1))
para_awk sub "$GO_MD" '"${CLAUDE_PLUGIN_ROOT}/scripts/delegation-verify.sh"' 'plugins/soleur/scripts/delegation-verify.sh' > "$M/m17.md"
row "M17 a repo-relative verifier path" "$M/m17.md" "$BASE_REF" repo-relative-path; nrows=$((nrows + 1))
para_awk sub "$GO_MD" '--disable-auto' '--keep-armed' > "$M/m18.md"
row "M18 stop no longer disarms armed merges" "$M/m18.md" "$BASE_REF" stop-sequence; nrows=$((nrows + 1))
para_awk sub "$GO_MD" 'execution sentence' 'log line' > "$M/m19.md"
row "M19 the execution sentence is no longer printed" "$M/m19.md" "$BASE_REF" receipt-wiring; nrows=$((nrows + 1))

# M20..M22: the positive-only properties get a RED row each
para_awk sub "$GO_MD" '"${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/hold-gate-eval.sh"' '${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/hold-gate-eval.sh' > "$M/m20.md"
row "M20 the hold-evaluator path loses its quotes" "$M/m20.md" "$BASE_REF" plugin-root-paths; nrows=$((nrows + 1))
para_awk sub "$GO_MD" 'AskUserQuestion' 'AskTool' > "$M/m21.md"
row "M21 the paragraph no longer names AskUserQuestion" "$M/m21.md" "$BASE_REF" no-askuserquestion-for-technical-hold; nrows=$((nrows + 1))
grep -vF "$BLOCK_START" "$GO_MD" > "$M/m22.md"
row "M22 the eval-gate start marker is gone" "$M/m22.md" "$BASE_REF" anchors-missing; nrows=$((nrows + 1))
para_awk sub "$GO_MD" 'invalid newest one means no delegation' 'any valid one counts' > "$M/m23.md"
row "M23 an older valid delegation may take over from an invalid newest one" "$M/m23.md" "$BASE_REF" newest-decides; nrows=$((nrows + 1))
printf 'not go.md\n' > "$M/degenerate-base.txt"
row "M24 a degenerate base (not the real file)" "$GO_MD" "file:$M/degenerate-base.txt" base-degenerate; nrows=$((nrows + 1))
para_awk sub "$GO_MD" 'delete every delegation comment' 'delete the delegation comment' > "$M/m25.md"
row "M25 the stop sequence deletes only one comment" "$M/m25.md" "$BASE_REF" stop-sequence; nrows=$((nrows + 1))
# N14: with base == HEAD the anchor is SKIPPED (printed reason) and a changed file is still caught against it
ck
_o="$(evaluate "$M/m1.md" "$HEAD_SHA" skip)"; _r=$?
[[ "$_o" != *block-hash-differs* ]] && ok "N14 anchor skip mode does not evaluate the merge-base comparison" || bad "N14 skip mode still ran the anchor: ${_o//$'\n'/ }"
row "N14b against HEAD as base a changed block is still RED (the rows stay meaningful after merge)" "$M/m1.md" "$HEAD_SHA" block-hash-differs; nrows=$((nrows + 1))

# H1 the base ref is unresolvable: a FAIL, never a skip
row "H1 unresolvable base ref" "$GO_MD" "refs/does-not-exist" base-unresolvable; nrows=$((nrows + 1))

# H2 must-PASS: a whitespace-only change OUTSIDE the block (the Sharp Edges list, after the block)
awk -v e="$BLOCK_END" '
  index($0, e) { seen = 1 }
  seen && !done && /^- \*\*A technical ruling is never/ { $0 = $0 "  "; done = 1 }
  { print }
  END { print "" }' "$GO_MD" > "$M/h2.md"
row "H2 whitespace-only change outside the block" "$M/h2.md" "$BASE_REF" none; nrows=$((nrows + 1))

# Late-redefinition defence: re-run the controls AFTER the last row, so a helper redefined between the first
# controls and here cannot silently grade the rows above.
ctl_fails row "ctl-late" "$M/ctl-bad.md" "$BASE_REF" none               || { printf 'FATAL: late control: row() accepted a RED file as green\n' >&2; exit 2; }
ctl_fails row "ctl-late" "$M/ctl-bad.md" "$BASE_REF" block-hash-differs || { printf 'FATAL: late control: row() accepted the wrong token\n' >&2; exit 2; }
ctl_passes row "ctl-late" "$GO_MD" "$BASE_REF" none                      || { printf 'FATAL: late control: row() cannot record a PASS\n' >&2; exit 2; }

# --- ANTI-VACUITY: the assertion floors ---------------------------------------------------------------
# (1) Derived: one assertion per property, the aggregate, the anchor row, three extraction floors, one per
#     mutation row.
# (2) ABSOLUTE: the count of a green run, committed with ZERO slack. A derived floor moves with the rows it
#     guards (delete six rows and the floor drops with them); this constant is the one that bites. Raise it in
#     the same commit that adds rows, never ahead of them.
nprops=0; for _p in $ALL_PROPS; do nprops=$((nprops + 1)); done
EXPECTED_ASSERTIONS=$(( nprops + 1 + 1 + 1 + 3 + nrows + 1 ))
ABSOLUTE_FLOOR=60
MIN_ASSERTIONS=$(( EXPECTED_ASSERTIONS > ABSOLUTE_FLOOR ? EXPECTED_ASSERTIONS : ABSOLUTE_FLOOR ))
if [[ "$asserted" -lt "$MIN_ASSERTIONS" ]]; then
  printf '\nFATAL: anti-vacuity: %d assertion(s) executed, floor is %d. The battery ran but did not assert.\n' \
    "$asserted" "$MIN_ASSERTIONS" >&2
  exit 1
fi

_lp="$(grep -c '^PASS$' "$VERDICT_LOG" || true)"
_lf="$(grep -c '^FAIL$' "$VERDICT_LOG" || true)"
_ls="$(grep -c '^SKIP$' "$VERDICT_LOG" || true)"
if [[ "${_lp:-0}" -ne "$passes" || "${_lf:-0}" -ne "$fails" || "${_ls:-0}" -ne "$skips" || $((passes + fails + skips)) -ne "$asserted" ]]; then
  printf '\nFATAL: accounting: ledger (%s pass / %s fail / %s skip) vs counters (%d / %d / %d), asserted %d.\n' \
    "${_lp:-0}" "${_lf:-0}" "${_ls:-0}" "$passes" "$fails" "$skips" "$asserted" >&2
  exit 1
fi

printf '\ngo-hold-routing.test.sh: %d passed, %d failed, %d skipped, %d assertion(s) executed (floor %d); base %s\n' \
  "$passes" "$fails" "$skips" "$asserted" "$MIN_ASSERTIONS" "${BASE_REF:0:12}"
[[ "$fails" -eq 0 && "$passes" -gt 0 ]] || exit 1
exit 0
