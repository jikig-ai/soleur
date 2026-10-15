#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2015,SC2016  # row functions are dispatched indirectly; A && B || C is the assertion idiom; literals are single-quoted on purpose
# Phase 7 of the CTO standing-delegation plan
# (knowledge-base/project/plans/2026-10-15-feat-cto-standing-delegation-and-production-envelope-plan.md).
#
# PROPERTY. `plugins/soleur/agents/engineering/cto.md` selects its interface from the spawn prompt, and
# every EXISTING caller keeps the interface it already gets:
#   * a ruling request (one-shot, work, the delegation reference's brief)  -> Rule
#   * a brainstorm / plan-review assessment prompt                          -> Assess / Recommend (unchanged)
#   * a prompt that starts "Own the epic" (go's hold routing)               -> Own the epic
# No existing caller sends a fixed phrase (architecture finding 4 of the plan), so the cues are the ones
# callers actually emit: a question plus "Do NOT use AskUserQuestion", or BINDING.
#
# THE PHRASES ARE EXTRACTED FROM THE REAL CALLER FILES, not typed here, and the cues are read out of
# cto.md's own selector section, so the document, the callers and this suite cannot drift apart silently.
# A hand-written phrase list would pass while a caller changed its wording.
#
# Also pinned: the frontmatter is byte-identical to the merge base (so no generated mirror regenerates:
# agents.manifest.json, .grok/agents/soleur-engineering-cto.md, the cursor stub all embed the
# description), the old body is preserved line for line, the Rule and Own-the-epic contracts are present,
# standing-delegation.md is LINKED (and the link resolves), never duplicated, and section 3 of
# technical-ruling-delegation.md points at the agent instead of restating the brief.
#
# The base anchor is `git show $(git merge-base origin/main HEAD):<cto.md>`, outside the commit under
# test. An unresolvable base is a FAIL, never a skip. Every mutation row asserts the REASON it reds.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CTO_REL="plugins/soleur/agents/engineering/cto.md"
CTO="$ROOT/$CTO_REL"
DELEG="$ROOT/plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md"
ONE_SHOT="$ROOT/plugins/soleur/skills/one-shot/SKILL.md"
WORK="$ROOT/plugins/soleur/skills/work/SKILL.md"
DOMAIN_CFG="$ROOT/plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md"
PLAN_REVIEW_WF="$ROOT/plugins/soleur/skills/plan-review/workflows/plan-review.workflow.js"
RENDER="$ROOT/plugins/soleur/skills/ship/references/decision-challenges-render.md"
REVIEW="$ROOT/plugins/soleur/skills/review/SKILL.md"
GO_MD="$ROOT/plugins/soleur/commands/go.md"

passes=0; fails=0; asserted=0; FAILED=()
VERDICT_LOG="$(mktemp -t cto-selector.XXXXXXXX.log)" || { printf 'FATAL: no scratch\n' >&2; exit 2; }

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
SANDBOX="$(mktemp -d -t ctosel.XXXXXXXX)" || { printf 'FATAL: no scratch root\n' >&2; exit 2; }
assert_fixture_dir "$SANDBOX"
trap 'rm -rf "$SANDBOX"; rm -f "$VERDICT_LOG"' EXIT

ok()  { printf '  PASS: %s\n' "$1"; printf 'PASS\n' >> "$VERDICT_LOG"; passes=$((passes + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; printf 'FAIL\n' >> "$VERDICT_LOG"; fails=$((fails + 1)); FAILED+=("$1"); }
ck()  { asserted=$((asserted + 1)); }

# --- instrument self-test --------------------------------------------------------------------------
_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ ok "self-test"; bad "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
passes=0; fails=0; asserted=0; FAILED=(); : > "$VERDICT_LOG"

for f in "$CTO" "$DELEG" "$ONE_SHOT" "$WORK" "$DOMAIN_CFG" "$PLAN_REVIEW_WF" "$RENDER" "$REVIEW" "$GO_MD"; do
  [[ -r "$f" ]] || { printf 'FATAL: cannot read %s\n' "$f" >&2; exit 2; }
done
command -v git >/dev/null || { printf 'FATAL: git required\n' >&2; exit 2; }

g() { env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_COMMON_DIR git -C "$ROOT" "$@"; }
hash_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
  else shasum -a 256 | awk '{print $1}'; fi
}
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Frontmatter = line 1 through the second `---` line, inclusive.
frontmatter_of() { awk 'NR == 1 && $0 == "---" { f = 1; print; next } f { print } f && $0 == "---" { exit }' "$1"; }
body_of()        { awk 'NR == 1 && $0 == "---" { f = 1; next } f == 1 && $0 == "---" { f = 2; next } f == 2 { print }' "$1"; }

# --- the selector, read out of cto.md itself -------------------------------------------------------
# Section "## Interface selector": numbered rules `1.` `2.` `3.`; the backticked tokens on rule 1 are the
# START cues (Own the epic), on rule 2 the CONTAINS cues (Rule). Rule 3 is the fallback.
selector_cues() { # <cto.md> <rule-number> -> one cue per line
  awk -v n="$2" '
    /^## Interface selector/ { f = 1; next }
    f && /^## / { f = 0 }
    f && $0 ~ ("^" n "\\. ") { print }' "$1" | grep -o '`[^`]*`' | tr -d '`'
}
# classify <cto.md> <prompt> -> own-the-epic | rule | assess
classify() {
  local doc="$1" p t
  p="$(lower "$2")"; p="${p#"${p%%[![:space:]]*}"}"
  while IFS= read -r t; do
    [[ -n "$t" ]] || continue; t="$(lower "$t")"
    [[ "$p" == "$t"* ]] && { printf 'own-the-epic'; return 0; }
  done < <(selector_cues "$doc" 1)
  while IFS= read -r t; do
    [[ -n "$t" ]] || continue; t="$(lower "$t")"
    [[ "$p" == *"$t"* ]] && { printf 'rule'; return 0; }
  done < <(selector_cues "$doc" 2)
  printf 'assess'
}

# --- real caller phrases, extracted -----------------------------------------------------------------
quoted_ask_phrase() { # <file> <line-anchor-fixed-string> -> the quoted phrase carrying AskUserQuestion
  local line re='"([^"]*AskUserQuestion[^"]*)"'
  line="$(grep -F -m1 -- "$2" "$1" || true)"
  [[ "$line" =~ $re ]] && printf '%s' "${BASH_REMATCH[1]}"
}
ONE_SHOT_PHRASE="$(quoted_ask_phrase "$ONE_SHOT" 'TECHNICAL RULINGS (inline copy')"
WORK_PHRASE="$(quoted_ask_phrase "$WORK" 'Technical rulings route to the CTO agent')"

section3_of() { awk '/^## 3\. /{ f = 1; next } f && /^## / { f = 0 } f { print }' "$1"; }
DELEG_OPENER=""
_re='`(Rule on this technical question[^`]*)`'
_s3="$(section3_of "$DELEG")"
[[ "$_s3" =~ $_re ]] && DELEG_OPENER="${BASH_REMATCH[1]}"

DOMAIN_PROMPT="$(grep -F -m1 -- '| Engineering |' "$DOMAIN_CFG" | awk -F'|' '{ print $(NF-1) }' | sed 's/^ *//; s/ *$//')"
PLAN_REVIEW_LENS="$(awk '/^  cto: \{/ { f = 1 } f && /lens:/ { print; exit }' "$PLAN_REVIEW_WF" | sed "s/^ *lens: *'//; s/',\$//")"
_re='starts `(Own the epic)`'
GO_OWN_CUE=""
_go_para="$(awk '/^## Step 1\.5: Hold routing/ { f = 1; next } f && /^## / { f = 0 } f { print }' "$GO_MD")"
[[ "$_go_para" =~ $_re ]] && GO_OWN_CUE="${BASH_REMATCH[1]}"

# --- cto.md evaluation -------------------------------------------------------------------------------
# evaluate_cto <cto.md> <base-ref> : print one `V:<token>` line per violated property; rc 0 iff none.
evaluate_cto() {
  local f="$1" base="$2" v=0 base_blob bfm ffm body line link target
  emit() { printf 'V:%s\n' "$1"; v=1; }
  body="$(body_of "$f")"

  # Frontmatter byte-identical to the merge base (outside the commit under test).
  if ! base_blob="$(g show "$base:$CTO_REL" 2>/dev/null)" || [[ -z "$base_blob" ]]; then
    emit base-unresolvable; emit frontmatter-differs; emit preserved-line-missing
  else
    printf '%s\n' "$base_blob" > "$SANDBOX/base-cto.md"
    bfm="$(frontmatter_of "$SANDBOX/base-cto.md" | hash_stdin)"; ffm="$(frontmatter_of "$f" | hash_stdin)"
    [[ -n "$bfm" && "$bfm" == "$ffm" ]] || emit frontmatter-differs
    # The old body survives: every non-blank base-body line is still a whole line of the new body.
    while IFS= read -r line; do
      [[ -n "${line//[[:space:]]/}" ]] || continue
      grep -Fxq -- "$line" "$f" || { emit preserved-line-missing; break; }
    done < <(body_of "$SANDBOX/base-cto.md")
  fi

  # Selector.
  [[ -n "$(selector_cues "$f" 1)" && -n "$(selector_cues "$f" 2)" ]] || emit selector-missing
  [[ "$body" == *'## Interface selector'* ]] || emit selector-missing

  # Rule interface.
  [[ "$body" == *'## Rule interface'* ]]                 || emit rule-section-missing
  local h; for h in 'Decision:' 'Rationale:' 'Rejected alternatives:' 'Dissent:'; do
    [[ "$body" == *"$h"* ]] || emit "rule-heading-${h%:}"
  done
  [[ "$body" == *'STRICTER'* ]]                          || emit rule-stricter-default
  [[ "$body" == *'unverified'* ]]                        || emit rule-evidence-bar
  [[ "$body" == *'never a menu'* ]]                      || emit rule-no-menu
  [[ "$body" == *'headless'* && "$body" == *'never ask'* ]] || emit rule-headless
  [[ "$body" == *'Item <id>:'* ]]                        || emit rule-multi-item

  # Own the epic interface.
  [[ "$body" == *'## Own the epic interface'* ]]         || emit epic-section-missing
  [[ "$body" == *'delegation-verify.sh'* ]]              || emit epic-verifier
  [[ "$body" == *'hold-gate-eval.sh'* ]]                 || emit epic-hold-eval
  [[ "$body" == *'Gate:'* ]]                             || emit epic-gate-predicates
  [[ "$body" == *'## Production Envelope'* ]]            || emit epic-envelope
  [[ "$body" == *'last verified item'* ]]                || emit epic-close-on-last
  [[ "$body" == *'action-required'* ]]                   || emit epic-stall-issue
  local kw; for kw in 'user-data loss' 'money' 'legal-risk' 'brand' 'scope' 'force-push to main' 'bypassing required checks' 'editing this delegation' 'credential rotation' 'third-party or tenant' 'rollback is not named'; do
    [[ "$body" == *"$kw"* ]] || { emit epic-nondelegable-list; break; }
  done

  # standing-delegation.md is LINKED (and resolves), never duplicated.
  link="$(printf '%s\n' "$body" | grep -Eo '\]\([^)]*standing-delegation[^)]*\)' | head -n1 | sed 's/^](//; s/)$//')"
  if [[ -z "$link" ]]; then emit epic-link-missing
  else
    # a mutated copy lives in the sandbox, so resolve the link against the REAL agent directory
    target="$(cd "$(dirname "$CTO")" && cd "$(dirname "$link")" 2>/dev/null && pwd)/$(basename "$link")"
    [[ -f "$target" ]] || emit epic-link-unresolved
  fi
  if [[ "$body" == *'soleur-delegation v1'* || "$body" == *'**Confirmation:**'* || "$body" == *'**Excluded (still operator-only):**'* ]]; then
    emit format-duplicated
  fi
  return "$v"
}

BASE_REF="$(g merge-base origin/main HEAD 2>/dev/null || true)"
[[ -n "$BASE_REF" ]] || BASE_REF="refs/unresolvable-merge-base"

# --- A. the cto.md properties ------------------------------------------------------------------------
CTO_OUT="$(evaluate_cto "$CTO" "$BASE_REF")"; CTO_RC=$?
CTO_PROP_LIST=(base-unresolvable frontmatter-differs preserved-line-missing selector-missing
  rule-section-missing rule-heading-Decision rule-heading-Rationale "rule-heading-Rejected alternatives"
  rule-heading-Dissent rule-stricter-default rule-evidence-bar rule-no-menu rule-headless rule-multi-item
  epic-section-missing epic-verifier epic-hold-eval epic-gate-predicates epic-envelope epic-close-on-last
  epic-stall-issue epic-nondelegable-list epic-link-missing epic-link-unresolved format-duplicated)
nprops=0
for p in "${CTO_PROP_LIST[@]}"; do
  nprops=$((nprops + 1)); ck
  if [[ "$CTO_OUT" == *"V:$p"* ]]; then bad "cto.md violates '$p'"; else ok "cto.md has no violation of '$p'"; fi
done
ck
[[ "$CTO_RC" -eq 0 && -z "$CTO_OUT" ]] && ok "evaluate_cto agrees: rc=0 and no violation lines" || bad "evaluate_cto reported violations: ${CTO_OUT//$'\n'/ }"

# --- B. floors on the extractions --------------------------------------------------------------------
ck; [[ -n "$ONE_SHOT_PHRASE" ]] && ok "extracted one-shot's spawn phrase: \"$ONE_SHOT_PHRASE\"" || bad "could not extract one-shot's AskUserQuestion spawn phrase"
ck; [[ -n "$WORK_PHRASE" ]] && ok "extracted work's spawn phrase: \"$WORK_PHRASE\"" || bad "could not extract work's AskUserQuestion spawn phrase"
ck; [[ -n "$DELEG_OPENER" ]] && ok "extracted the delegation reference's section-3 opener: \`$DELEG_OPENER\`" || bad "section 3 of technical-ruling-delegation.md carries no \`Rule on this technical question ...\` opener"
ck; [[ "${#DOMAIN_PROMPT}" -ge 80 ]] && ok "extracted brainstorm-domain-config's Engineering task prompt (${#DOMAIN_PROMPT} bytes)" || bad "could not extract the Engineering task prompt from brainstorm-domain-config.md"
ck; [[ "${#PLAN_REVIEW_LENS}" -ge 40 ]] && ok "extracted plan-review's cto devex lens (${#PLAN_REVIEW_LENS} bytes)" || bad "could not extract the cto lens from plan-review.workflow.js"
ck; [[ -n "$GO_OWN_CUE" ]] && ok "extracted go.md's hold-routing spawn cue: \`$GO_OWN_CUE\`" || bad "go.md's hold-routing paragraph names no 'starts \`Own the epic\`' cue"

# --- C. each existing caller's phrase selects the intended interface ----------------------------------
CALLER_ROWS="$SANDBOX/callers.tsv"
{
  printf 'one-shot Technical-rulings spawn\trule\tEvidence: src/a.ts:10. Options: A or B. %s\n' "$ONE_SHOT_PHRASE"
  printf 'work Technical-rulings spawn\trule\tEvidence: src/b.ts:22. Options: A or B. %s\n' "$WORK_PHRASE"
  printf 'delegation reference section-3 brief\trule\t%s Question: which of two designs?\n' "$DELEG_OPENER"
  printf 'delegation brief that mentions a standing delegation\trule\t%s Question: is the standing delegation for epic #9757 still valid?\n' "$DELEG_OPENER"
  printf 'brainstorm Phase 0.5 domain assessment\tassess\t%s\n' "${DOMAIN_PROMPT//\{desc\}/add a billing page}"
  printf 'plan-review named-panel devex lens\tassess\tReview this plan through the lens: %s\n' "$PLAN_REVIEW_LENS"
  printf 'go hold routing\town-the-epic\t%s #9757: complete the epic from the resume brief.\n' "$GO_OWN_CUE"
  printf 'go hold routing that also says Do NOT use AskUserQuestion\town-the-epic\t%s #9757: finish it. Do NOT use AskUserQuestion.\n' "$GO_OWN_CUE"
  printf 'unrecognised prompt falls back to the existing behaviour\tassess\tWhat should we think about before building the export feature?\n'
  printf 'empty prompt falls back to the existing behaviour\tassess\t \n'
} > "$CALLER_ROWS"
caller_n=0
while IFS=$'\t' read -r label want prompt; do
  caller_n=$((caller_n + 1)); ck
  got="$(classify "$CTO" "$prompt")"
  [[ "$got" == "$want" ]] && ok "caller '$label' selects '$got'" || bad "caller '$label' selects '$got', expected '$want' (prompt: ${prompt:0:100})"
done < "$CALLER_ROWS"
ck; [[ "$caller_n" -ge 10 ]] && ok "caller table executed $caller_n rows" || bad "caller table executed $caller_n rows (floor 10)"

# Callers that spawn THROUGH the delegation step (no phrase of their own) must still point at it.
for pair in "$RENDER|delegation step" "$REVIEW|technical-ruling-delegation.md" "$ONE_SHOT|technical-ruling-delegation.md" "$WORK|technical-ruling-delegation.md"; do
  file="${pair%%|*}"; needle="${pair#*|}"; ck
  if grep -Fq -- "$needle" "$file"; then ok "$(basename "$(dirname "$file")")/$(basename "$file") routes its cto spawn through '$needle'"
  else bad "$file no longer mentions '$needle' near its cto spawn"; fi
done

# --- D. section 3 of the delegation reference points at the agent ---------------------------------------
_s3="$(section3_of "$DELEG")"
ck; [[ "$_s3" != *'Reply with exactly these four headings'* && "$_s3" != *'Copy this brief'* ]] && ok "section 3 no longer carries the copied brief" || bad "section 3 still restates the brief"
ck; [[ "$_s3" == *'agents/engineering/cto.md'* && "$_s3" == *'Rule interface'* ]] && ok "section 3 points at the agent's Rule interface" || bad "section 3 does not point at the agent's Rule interface"
ck; [[ "$_s3" == *'Do NOT use AskUserQuestion'* ]] && ok "section 3 still carries the cue callers rely on" || bad "section 3 lost the 'Do NOT use AskUserQuestion' cue"
ck; [[ "$_s3" == *'Question'* && "$_s3" == *'Evidence'* && "$_s3" == *'Brand-survival threshold'* && "$_s3" == *'DISQUALIFY'* ]] && ok "section 3 lists the brief's fields" || bad "section 3 lost a brief field name"

# --- E. mutation rows (each asserts the REASON) --------------------------------------------------------
row() { # <label> <mutated-cto.md> <base> <expected-token|none>
  local label="$1" file="$2" base="$3" want="$4" out rc
  out="$(evaluate_cto "$file" "$base")"; rc=$?
  ck
  if [[ "$want" == none ]]; then
    [[ "$rc" -eq 0 && -z "$out" ]] && ok "$label: stays green" || bad "$label: expected green, got ${out//$'\n'/ }"
  else
    [[ "$rc" -ne 0 && "$out" == *"V:$want"* ]] && ok "$label: RED for '$want'" || bad "$label: expected RED for '$want', got rc=$rc ${out//$'\n'/ }"
  fi
}
misroute_row() { # <label> <mutated-cto.md> <prompt> <must-not-be>
  local label="$1" file="$2" prompt="$3" notwant="$4" got
  got="$(classify "$file" "$prompt")"; ck
  [[ "$got" != "$notwant" ]] && ok "$label: the caller phrase no longer selects '$notwant' (got '$got')" || bad "$label: mutation did not change the selection ('$got')"
}
M="$SANDBOX/m"; mkdir -p "$M"; assert_fixture_dir "$M"
nrows=0

# F1 flip one byte of the frontmatter description
awk 'NR <= 6 && /^description:/ && !d { sub(/Participates/, "Participate"); d = 1 } { print }' "$CTO" > "$M/f1.md"
row "F1 frontmatter description byte changed" "$M/f1.md" "$BASE_REF" frontmatter-differs; nrows=$((nrows + 1))
# F2 drop a heading of the four
sed 's/Rejected alternatives:/Alternatives:/' "$CTO" > "$M/f2.md"
row "F2 'Rejected alternatives:' heading renamed" "$M/f2.md" "$BASE_REF" "rule-heading-Rejected alternatives"; nrows=$((nrows + 1))
# F3 drop the stricter default
sed 's/STRICTER/stricter/g' "$CTO" > "$M/f3.md"
row "F3 stricter-default wording removed" "$M/f3.md" "$BASE_REF" rule-stricter-default; nrows=$((nrows + 1))
# F4 delete the standing-delegation link
sed 's/(\([^)]*\)standing-delegation\.md)/(\1removed.md)/g' "$CTO" > "$M/f4.md"
row "F4 link to standing-delegation.md removed" "$M/f4.md" "$BASE_REF" epic-link-missing; nrows=$((nrows + 1))
# F5 a link that does not resolve
sed 's/standing-delegation\.md)/standing-delegation-gone.md)/g' "$CTO" > "$M/f5.md"
row "F5 link to standing-delegation.md does not resolve" "$M/f5.md" "$BASE_REF" epic-link-unresolved; nrows=$((nrows + 1))
# F6 duplicate the record format into the agent
{ cat "$CTO"; printf '\n<!-- soleur-delegation v1 -->\n'; } > "$M/f6.md"
row "F6 delegation record format duplicated into the agent" "$M/f6.md" "$BASE_REF" format-duplicated; nrows=$((nrows + 1))
# F7 delete an old Sharp Edges line
awk '!/Do not prescribe implementation details/' "$CTO" > "$M/f7.md"
row "F7 an old body line removed" "$M/f7.md" "$BASE_REF" preserved-line-missing; nrows=$((nrows + 1))
# F8 drop the non-delegable list's money item
sed 's/money/cash/g' "$CTO" > "$M/f8.md"
row "F8 non-delegable list loses an item" "$M/f8.md" "$BASE_REF" epic-nondelegable-list; nrows=$((nrows + 1))
# F9 close-on-last-verified wording removed
sed 's/last verified item/final item/g' "$CTO" > "$M/f9.md"
row "F9 close-only-on-the-last-verified-item wording removed" "$M/f9.md" "$BASE_REF" epic-close-on-last; nrows=$((nrows + 1))
# H1 base unresolvable is a FAIL
row "H1 unresolvable base ref" "$CTO" "refs/does-not-exist" base-unresolvable; nrows=$((nrows + 1))
# H2 must-PASS: trailing blank lines in the body
{ cat "$CTO"; printf '\n\n'; } > "$M/h2.md"
row "H2 trailing blank lines only" "$M/h2.md" "$BASE_REF" none; nrows=$((nrows + 1))

# Selector mutations: a cue removed from the document must change what a real caller gets.
sed 's/`Do NOT use AskUserQuestion`/`do-not-use-the-ask-tool`/' "$CTO" > "$M/s1.md"
misroute_row "S1 'Do NOT use AskUserQuestion' cue removed (one-shot phrase)" "$M/s1.md" "Evidence: x. $ONE_SHOT_PHRASE" rule; nrows=$((nrows + 1))
sed 's/`Own the epic`/`Take the epic`/' "$CTO" > "$M/s2.md"
misroute_row "S2 'Own the epic' cue removed (go phrase)" "$M/s2.md" "$GO_OWN_CUE #1: finish" own-the-epic; nrows=$((nrows + 1))
# S3 over-broad cue: the word 'question' as a Rule cue would hijack the brainstorm prompt
sed 's/`BINDING`/`BINDING`, `question`/' "$CTO" > "$M/s3.md"
misroute_row "S3 over-broad 'question' cue (brainstorm prompt)" "$M/s3.md" "${DOMAIN_PROMPT//\{desc\}/x}" assess; nrows=$((nrows + 1))

# --- F. informational census of every cto spawn surface (drift is a WARN, never a vacuous green) ------
SURFACES="$(cd "$ROOT" && grep -rl 'soleur:engineering:cto' plugins/soleur/skills plugins/soleur/commands .claude/hooks scripts .github/workflows 2>/dev/null | sort || true)"
ck; [[ "$(printf '%s\n' "$SURFACES" | grep -c . || true)" -ge 8 ]] && ok "cto spawn-surface census found $(printf '%s\n' "$SURFACES" | grep -c .) files" || bad "cto spawn-surface census found fewer than 8 files (grep scope broke)"

# --- ANTI-VACUITY: the assertion floor -------------------------------------------------------------------
# Derived: properties + aggregate + 6 extraction floors + callers + caller floor + 4 delegation-path rows
# + 4 section-3 rows + mutation rows + census.
EXPECTED_ASSERTIONS=$(( nprops + 1 + 6 + caller_n + 1 + 4 + 4 + nrows + 1 ))
MIN_ASSERTIONS=${EXPECTED_ASSERTIONS:-1}
if [[ "$asserted" -lt "$MIN_ASSERTIONS" ]]; then
  printf '\nFATAL: anti-vacuity: %d assertion(s) executed, floor is %d. The battery ran but did not assert.\n' "$asserted" "$MIN_ASSERTIONS" >&2
  exit 1
fi
_lp="$(grep -c '^PASS$' "$VERDICT_LOG" || true)"
_lf="$(grep -c '^FAIL$' "$VERDICT_LOG" || true)"
if [[ "${_lp:-0}" -ne "$passes" || "${_lf:-0}" -ne "$fails" || $((passes + fails)) -ne "$asserted" ]]; then
  printf '\nFATAL: accounting: ledger (%s pass / %s fail) vs counters (%d / %d), asserted %d.\n' "${_lp:-0}" "${_lf:-0}" "$passes" "$fails" "$asserted" >&2
  exit 1
fi
printf '\ncto-interface-selector.test.sh: %d passed, %d failed, %d assertion(s) executed (floor %d); base %s\n' \
  "$passes" "$fails" "$asserted" "$MIN_ASSERTIONS" "${BASE_REF:0:12}"
[[ "$fails" -eq 0 && "$passes" -gt 0 ]] || exit 1
exit 0
