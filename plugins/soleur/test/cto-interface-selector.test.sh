#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2015,SC2016  # row functions are dispatched indirectly; A && B || C is the assertion idiom; literals are single-quoted on purpose
# Phase 7 of the CTO standing-delegation plan
# (knowledge-base/project/plans/archive/20261015-183324-2026-10-15-feat-cto-standing-delegation-and-production-envelope-plan.md).
#
# PROPERTY. `plugins/soleur/agents/engineering/cto.md` selects its interface from the spawn prompt, and
# every EXISTING caller keeps the interface it already gets:
#   * a ruling request (one-shot, work, the delegation reference's brief)  -> Rule
#   * a brainstorm / plan-review assessment prompt                          -> Assess / Recommend (unchanged)
#   * a prompt that starts "Own the epic" (go's hold routing)               -> Own the epic
# No existing caller sends a fixed phrase (architecture finding 4 of the plan), so the cues are the ones
# callers actually emit: a question plus "Do NOT use AskUserQuestion", or BINDING. A plan-review or
# assessment prompt (`Structured advisory only`, `IMPLEMENTATION PLAN (not code)`) is checked BEFORE the
# Rule cues, and the Rule cues are CASE-SENSITIVE (the word "binding" in a feature description is not one).
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
# test. An unresolvable base is a FAIL, never a skip. Every mutation row asserts the REASON it reds, matched
# as an EXACT violation line (`V:epic-hold-eval` is not satisfied by `V:epic-hold-eval-exit0`).
#
# PR-TIME CHECKS. The merge-base invariants (frontmatter byte-identical, old body preserved) describe THIS
# PR's diff. Once it is merged the merge base IS HEAD and the comparison would be self-identity, so on the
# real file those properties are SKIPPED with a printed reason (never a silent pass). The mutation rows still
# compare a changed file against the base and stay meaningful.
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
skips=0
skip() { printf '  SKIP: %s\n' "$1"; printf 'SKIP\n' >> "$VERDICT_LOG"; skips=$((skips + 1)); }

# --- instrument self-test --------------------------------------------------------------------------
_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ ok "self-test"; bad "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
passes=0; fails=0; asserted=0; skips=0; FAILED=(); : > "$VERDICT_LOG"

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
# Section "## Interface selector": numbered rules. Per rule the verb (`starts` or `contains`) is read from
# the prose, the cues are the backticked tokens BEFORE the `->`, the target is the first bold word after it
# (Own -> own-the-epic, Assess -> assess, Rule -> rule). A rule without cues is the fallback. Cues are
# matched CASE-SENSITIVELY, in rule order, first match wins.
selector_rules() { # <cto.md> -> one `N<TAB>verb<TAB>target<TAB>cue` line per cue (cue empty for the fallback)
  local line n verb head tgt cue cues
  while IFS= read -r line; do
    n="${line%%.*}"; head="${line%%->*}"
    verb=contains; [[ "$head" == *' starts '* ]] && verb=starts
    tgt="$(printf '%s' "${line#*->}" | grep -o '\*\*[^*]*\*\*' | head -n1 | tr -d '*')"; tgt="$(lower "${tgt%% *}")"
    case "$tgt" in own) tgt=own-the-epic ;; esac
    cues="$(printf '%s' "$head" | grep -o '`[^`]*`' | tr -d '`' || true)"
    if [[ -z "$cues" ]]; then printf '%s\tfallback\t%s\t\n' "$n" "$tgt"; continue; fi
    while IFS= read -r cue; do printf '%s\t%s\t%s\t%s\n' "$n" "$verb" "$tgt" "$cue"; done <<< "$cues"
  done < <(awk '/^## Interface selector/ { f = 1; next } f && /^## / { f = 0 } f && /^[0-9]+\. / { print }' "$1")
}
selector_cues() { # <cto.md> <target> -> the cues whose rule selects <target>
  selector_rules "$1" | awk -F'\t' -v t="$2" '$3 == t && $2 != "fallback" { print $4 }'
}
# classify <cto.md> <prompt> -> own-the-epic | rule | assess
classify() {
  local doc="$1" p="$2" n verb tgt cue
  p="${p#"${p%%[![:space:]]*}"}"
  while IFS=$'\t' read -r n verb tgt cue; do
    [[ -n "$n" ]] || continue
    if [[ "$verb" == fallback ]]; then printf '%s' "$tgt"; return 0; fi
    [[ -n "$cue" ]] || continue
    if [[ "$verb" == starts ]]; then [[ "$p" == "$cue"* ]] && { printf '%s' "$tgt"; return 0; }
    else [[ "$p" == *"$cue"* ]] && { printf '%s' "$tgt"; return 0; }; fi
  done < <(selector_rules "$doc")
  printf 'assess'
}
section_of() { awk -v h="$2" 'index($0, h) == 1 { f = 1; next } f && /^## / { f = 0 } f { print }' "$1"; }
CPR='${CLAUDE_PLUGIN_ROOT}'
resolve_link() { # <link target as written in cto.md> -> an absolute path (relative links resolve against the REAL agent dir)
  local l="$1" rest
  case "$l" in
    "$CPR"/*) rest="${l#"$CPR"}"; printf '%s' "$ROOT/plugins/soleur$rest" ;;
    /*)       printf '%s' "$l" ;;
    *)        printf '%s/%s' "$(cd "$(dirname "$CTO")" && cd "$(dirname "$l")" 2>/dev/null && pwd)" "$(basename "$l")" ;;
  esac
}
link_in() { # <text> <basename-fragment> -> the first markdown link target whose path contains the fragment
  printf '%s\n' "$1" | grep -Eo '\]\([^)]*'"$2"'[^)]*\)' | head -n1 | sed 's/^](//; s/)$//'
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

# The FULL plan-review prompt for the `cto` named-panel reviewer, rebuilt from plan-review.workflow.js itself
# (reviewPrompt()): the opening sentence with the lens substituted, then the named-panel guidance block. The
# non-named variant is rebuilt the same way. The old row fed only the lens string and so never saw the
# "Structured advisory only - do NOT use AskUserQuestion" sentence that the real prompt carries.
PR_OPEN="$(grep -F -m1 -- 'You are reviewing an IMPLEMENTATION PLAN (not code)' "$PLAN_REVIEW_WF" | sed 's/^[^`]*`//')"
PR_OPEN="${PR_OPEN//\$\{r.lens\}/$PLAN_REVIEW_LENS}"
PR_NAMED="$(awk '/^    \? `$/ { f = 1; next } /^    : `/ { f = 0 } f { print }' "$PLAN_REVIEW_WF" | sed '$ s/`$//')"
PR_PLAIN="$(awk '/^    : `$/ { f = 1; next } f && /^  return `/ { f = 0 } f { print }' "$PLAN_REVIEW_WF" | sed '$ s/`$//')"
PLAN_REVIEW_FULL="$PR_OPEN
$PR_NAMED"
PLAN_REVIEW_PLAIN="$PR_OPEN
$PR_PLAIN"

BASE_REF="$(g merge-base origin/main HEAD 2>/dev/null || true)"
[[ -n "$BASE_REF" ]] || BASE_REF="refs/unresolvable-merge-base"
HEAD_SHA="$(g rev-parse HEAD 2>/dev/null || true)"

# The discovery command has ONE canonical spelling: the fenced line in standing-delegation.md. cto.md must carry it
# byte for byte (a second spelling is how the two documents drifted apart once already).
STD_DELEG="$ROOT/plugins/soleur/skills/brainstorm-techniques/references/standing-delegation.md"
CANON_DISCOVERY="$(grep -F -m1 -- 'gh api repos/{owner}/{repo}/issues/<epic>/comments --paginate' "$STD_DELEG" || true)"

# --- cto.md evaluation -------------------------------------------------------------------------------
# evaluate_cto <cto.md> <base-ref> : print one `V:<token>` line per violated property; rc 0 iff none.
# Properties of a section are asserted against THAT section's text, never the whole body, so words that
# also appear elsewhere in the document cannot satisfy them.
base_blob_of() { # <base> <rel-path>; a base written `file:<path>` reads that file (the degenerate-anchor control)
  case "$1" in file:*) cat "${1#file:}" 2>/dev/null ;; *) g show "$1:$2" 2>/dev/null ;; esac
}
evaluate_cto() { # <cto.md> <base> [check|skip]   skip = the merge-base anchor is not evaluated (base == HEAD)
  local f="$1" base="$2" anchor="${3:-check}" v=0 base_blob bfm ffm body line link target sel rsec esec nd
  emit() { printf 'V:%s\n' "$1"; v=1; }
  body="$(body_of "$f")"
  sel="$(section_of "$f" '## Interface selector')"
  rsec="$(section_of "$f" '## Rule interface')"
  esec="$(section_of "$f" '## Own the epic interface')"

  # Anchor: frontmatter byte-identical to the merge base, old body preserved. The base must RESOLVE and
  # must be the real file (a degenerate anchor would make both checks vacuous when base == HEAD).
  if [[ "$anchor" == skip ]]; then
    :
  elif ! base_blob="$(base_blob_of "$base" "$CTO_REL")" || [[ -z "$base_blob" ]]; then
    emit base-unresolvable; emit frontmatter-differs; emit preserved-line-missing
  else
    printf '%s\n' "$base_blob" > "$SANDBOX/base-cto.md"
    [[ "$base_blob" == *'name: cto'* && "$base_blob" == *'## Domain Leader Interface'* && "$base_blob" == *'### 3. Sharp Edges'* ]] || emit base-degenerate
    bfm="$(frontmatter_of "$SANDBOX/base-cto.md" | hash_stdin)"; ffm="$(frontmatter_of "$f" | hash_stdin)"
    [[ -n "$bfm" && "$bfm" == "$ffm" ]] || emit frontmatter-differs
    while IFS= read -r line; do
      [[ -n "${line//[[:space:]]/}" ]] || continue
      grep -Fxq -- "$line" "$f" || { emit preserved-line-missing; break; }
    done < <(body_of "$SANDBOX/base-cto.md")
  fi

  # Selector: four-shaped, ordered, case-sensitive.
  [[ -n "$sel" && "$body" == *'## Interface selector'* ]] || emit selector-missing
  [[ -n "$(selector_cues "$f" own-the-epic)" && -n "$(selector_cues "$f" rule)" && -n "$(selector_cues "$f" assess)" ]] || emit selector-missing
  local n_assess n_rule
  n_assess="$(selector_rules "$f" | awk -F'\t' '$3 == "assess" && $2 != "fallback" { print NR; exit }')"
  n_rule="$(selector_rules "$f" | awk -F'\t' '$3 == "rule" { print NR; exit }')"
  [[ -n "$n_assess" && -n "$n_rule" && "$n_assess" -lt "$n_rule" ]] || emit selector-assess-after-rule
  grep -Fxq 'Structured advisory only' < <(selector_cues "$f" assess) || emit selector-assess-cue-structured
  grep -Fxq 'IMPLEMENTATION PLAN (not code)' < <(selector_cues "$f" assess) || emit selector-assess-cue-plan
  if grep -Fxq 'binding' < <(selector_cues "$f" rule); then emit selector-lowercase-binding; fi
  [[ "$sel" == *'case-sensitive'* ]] || emit selector-case-undeclared

  # Rule interface.
  [[ "$body" == *'## Rule interface'* && -n "$rsec" ]]  || emit rule-section-missing
  local h; for h in 'Decision:' 'Rationale:' 'Rejected alternatives:' 'Dissent:'; do
    [[ "$rsec" == *"$h"* ]] || emit "rule-heading-${h%:}"
  done
  [[ "$rsec" == *'STRICTER'* ]]                          || emit rule-stricter-default
  [[ "$rsec" == *'unverified'* ]]                        || emit rule-evidence-bar
  [[ "$rsec" == *'never a menu'* ]]                      || emit rule-no-menu
  [[ "$rsec" == *'headless'* && "$rsec" == *'never ask'* ]] || emit rule-headless
  [[ "$rsec" == *'Item <id>:'* ]]                        || emit rule-multi-item
  link="$(link_in "$rsec" technical-ruling)"
  if [[ -z "$link" ]]; then emit rule-link-missing
  else target="$(resolve_link "$link")"; [[ -f "$target" ]] || emit rule-link-unresolved; fi

  # Own the epic interface (each property is read from THIS section only).
  [[ "$body" == *'## Own the epic interface'* && -n "$esec" ]] || emit epic-section-missing
  [[ "$esec" == *'delegation-verify.sh'* ]]              || emit epic-verifier
  [[ "$esec" == *'hold-gate-eval.sh'* ]]                 || emit epic-hold-eval
  [[ "$esec" == *'Gate:'* ]]                             || emit epic-gate-predicates
  [[ "$esec" == *'## Production Envelope'* ]] || emit epic-envelope
  [[ "$esec" == *'last verified item'* ]]                || emit epic-close-on-last
  [[ "$esec" == *'action-required'* ]]                   || emit epic-stall-issue
  [[ "$esec" == *"$CANON_DISCOVERY"* && -n "$CANON_DISCOVERY" && "$esec" == *'issues/<epic>/comments --paginate'* && "$esec" == *'soleur-delegation v1'* && "$esec" == *'last line upward'* ]] || emit epic-discovery
  [[ "$esec" == *'newest'* && "$esec" == *'delegation: valid'* && "$esec" == *'never fall back to an older'* ]] || emit epic-discovery-pick
  [[ "$esec" == *'verify --delegation <comment-url> --envelope '* && "$esec" == *'--command '* && "$esec" == *'--audit --at <ISO8601 UTC>'* ]] || emit epic-verify-synopsis
  [[ "$esec" == *'--section "Production Envelope - <title>"'* ]] || emit epic-section-title
  [[ "$esec" == *'exit 0'* && "$esec" == *'hold-gate-eval.sh" --file '* ]] || emit epic-hold-eval-exit0
  [[ "$esec" == *'Epic: #'* ]]                           || emit epic-epic-line
  [[ "$esec" == *'gh pr merge <N>'* && "$esec" == *'gh pr ready <N>'* && "$esec" == *'gh workflow run <file>.yml'* && "$esec" == *'gh pr create --fill'* ]] || emit epic-allowlist
  [[ "$esec" == *'must NOT run'* && "$esec" == *'`render`'* && "$esec" == *'calling skill'* ]] || emit epic-no-render
  [[ "$esec" == *'<!-- soleur-delegated-act v1 delegation=<url> envelope=<path> sha256=<verified-envelope-sha256> result=ok|rolled-back run=<url|none> -->'* ]] || emit epic-receipt-format
  [[ "$esec" == *'verified-envelope-sha256'* && "$esec" == *'run summary'* && "$esec" == *'execution sentence'* ]] || emit epic-receipt-wiring
  [[ "$esec" == *'gh api -X DELETE repos/{owner}/{repo}/issues/comments/<id>'* && "$esec" == *'gh pr merge <N> --disable-auto'* && "$esec" == *'could not be stopped'* && "$esec" == *'gh run cancel'* && "$esec" == *'delete EVERY delegation marker comment'* ]] || emit epic-stop-sequence
  [[ "$esec" == *'Authorized by delegation <comment-url>, envelope <path>, ran <ISO UTC>'* && "$esec" == *'decision-challenges.md'* && "$esec" == *'returns the row'* && "$esec" == *'replace the plan-time row'* ]] || emit epic-ran-row
  [[ "$esec" == *'one receipt per act'* && "$esec" == *'not in the future'* && "$esec" == *'never edit'* && "$esec" == *'posted by a person'* && "$esec" == *'precede'* && "$esec" == *'standing-delegation.md'*'section 8'* ]] || emit epic-receipt-rules
  [[ "$esec" == *'Headless'* && "$esec" == *'holds stand'* && "$esec" == *'never ask'* ]] || emit epic-headless
  [[ "$esec" == *'recorded consent'* && "$esec" == *'drift guard'* ]] || emit epic-consent-wording
  [[ "$esec" != *'two independent keys'* ]]              || emit epic-two-keys-claim
  nd="$(printf '%s\n' "$esec" | grep -F 'Non-delegable, ever:' || true)"
  local kw; for kw in 'user-data loss' 'sole-copy destruction' 'money' 'legal-risk' 'brand' 'scope' 'force-push to main' 'bypassing required checks' 'editing this delegation' 'credential rotation' 'third-party or tenant' 'rollback is not named' 'reserves a decision'; do
    [[ "$nd" == *"$kw"* ]] || { emit epic-nondelegable-list; break; }
  done
  [[ "$nd" == *'Undeferred Operator-Step'* && "$esec" == *'Operator-reserved:'* ]] || emit epic-reserved-routing
  link="$(link_in "$esec" standing-delegation)"
  if [[ -z "$link" ]]; then emit epic-link-missing
  else target="$(resolve_link "$link")"; [[ -f "$target" ]] || emit epic-link-unresolved; fi
  link="$(link_in "$esec" operator-holds)"
  if [[ -z "$link" ]]; then emit epic-holds-link-missing
  else target="$(resolve_link "$link")"; [[ -f "$target" ]] || emit epic-holds-link-unresolved; fi

  # Script paths: ${CLAUDE_PLUGIN_ROOT}, never repo-relative, in every section this PR added.
  if [[ "$sel$rsec$esec" == *'plugins/soleur/'* ]]; then emit repo-relative-path; fi
  [[ "$esec" == *'"${CLAUDE_PLUGIN_ROOT}/scripts/delegation-verify.sh"'* && "$esec" == *'"${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/hold-gate-eval.sh"'* ]] || emit plugin-root-paths
  [[ "$esec" == *"Cloud Mode"* ]]                        || emit plugin-root-unset-undeclared

  # The record format is defined once, in standing-delegation.md: no copy of it here. (The marker string
  # appears inside the discovery command; what is forbidden is the template's own whole-line marker.)
  if grep -Fxq '<!-- soleur-delegation v1 -->' <<<"$body" || [[ "$body" == *'**Confirmation:**'* || "$body" == *'**Excluded (still operator-only):**'* ]]; then
    emit format-duplicated
  fi
  return "$v"
}

# --- A. the cto.md properties ------------------------------------------------------------------------
ANCHOR_MODE=check; ANCHOR_REASON=""
if [[ -n "$HEAD_SHA" && "$BASE_REF" == "$HEAD_SHA" ]]; then
  ANCHOR_MODE=skip; ANCHOR_REASON="merge base == HEAD (this change is merged): the comparison would be self-identity; the invariants are PR-time checks"
fi
CTO_OUT="$(evaluate_cto "$CTO" "$BASE_REF" "$ANCHOR_MODE")"; CTO_RC=$?
CTO_PROP_LIST=(base-unresolvable base-degenerate frontmatter-differs preserved-line-missing selector-missing
  selector-assess-after-rule selector-assess-cue-structured selector-assess-cue-plan selector-lowercase-binding selector-case-undeclared
  rule-section-missing rule-heading-Decision rule-heading-Rationale "rule-heading-Rejected alternatives"
  rule-heading-Dissent rule-stricter-default rule-evidence-bar rule-no-menu rule-headless rule-multi-item
  rule-link-missing rule-link-unresolved
  epic-section-missing epic-verifier epic-hold-eval epic-gate-predicates epic-envelope epic-close-on-last
  epic-stall-issue epic-discovery epic-discovery-pick epic-verify-synopsis epic-section-title epic-hold-eval-exit0
  epic-epic-line epic-allowlist epic-no-render epic-receipt-format epic-receipt-wiring epic-stop-sequence
  epic-ran-row epic-receipt-rules epic-headless epic-consent-wording epic-two-keys-claim epic-nondelegable-list epic-reserved-routing
  epic-link-missing epic-link-unresolved epic-holds-link-missing epic-holds-link-unresolved
  repo-relative-path plugin-root-paths plugin-root-unset-undeclared format-duplicated)
nprops=0
for p in "${CTO_PROP_LIST[@]}"; do
  nprops=$((nprops + 1)); ck
  case "$p" in base-unresolvable|base-degenerate|frontmatter-differs|preserved-line-missing)
    if [[ "$ANCHOR_MODE" == skip ]]; then skip "'$p' not evaluated: $ANCHOR_REASON"; continue; fi ;;
  esac
  if grep -Fxq -- "V:$p" <<<"$CTO_OUT"; then bad "cto.md violates '$p'"; else ok "cto.md has no violation of '$p'"; fi
done
ck
[[ "$CTO_RC" -eq 0 && -z "$CTO_OUT" ]] && ok "evaluate_cto agrees: rc=0 and no violation lines" || bad "evaluate_cto reported violations: ${CTO_OUT//$'\n'/ }"

# The merge-base anchor is a PR-diff property. It must never be a silent tautology: the base ref must
# resolve, its sha is printed, and when base == HEAD (post-merge) that is said out loud.
ck
if [[ "$BASE_REF" != refs/unresolvable-merge-base && -n "$(g rev-parse --verify --quiet "${BASE_REF}^{commit}" || true)" ]]; then
  ok "merge-base anchor resolves: ${BASE_REF:0:12} (HEAD ${HEAD_SHA:0:12})"
else bad "merge-base anchor does not resolve (origin/main is not fetched?)"; fi
[[ "$ANCHOR_MODE" == skip ]] && printf '  NOTE: %s\n' "$ANCHOR_REASON"

# --- B. floors on the extractions --------------------------------------------------------------------
ck; [[ -n "$ONE_SHOT_PHRASE" ]] && ok "extracted one-shot's spawn phrase: \"$ONE_SHOT_PHRASE\"" || bad "could not extract one-shot's AskUserQuestion spawn phrase"
ck; [[ -n "$WORK_PHRASE" ]] && ok "extracted work's spawn phrase: \"$WORK_PHRASE\"" || bad "could not extract work's AskUserQuestion spawn phrase"
ck; [[ -n "$DELEG_OPENER" ]] && ok "extracted the delegation reference's section-3 opener: \`$DELEG_OPENER\`" || bad "section 3 of technical-ruling-delegation.md carries no \`Rule on this technical question ...\` opener"
ck; [[ "${#DOMAIN_PROMPT}" -ge 80 ]] && ok "extracted brainstorm-domain-config's Engineering task prompt (${#DOMAIN_PROMPT} bytes)" || bad "could not extract the Engineering task prompt from brainstorm-domain-config.md"
ck; [[ "${#PLAN_REVIEW_LENS}" -ge 40 ]] && ok "extracted plan-review's cto devex lens (${#PLAN_REVIEW_LENS} bytes)" || bad "could not extract the cto lens from plan-review.workflow.js"
ck; [[ "${#PLAN_REVIEW_FULL}" -ge 900 && "$PLAN_REVIEW_FULL" == *'Structured advisory only'* && "$PLAN_REVIEW_FULL" == *'NAMED CEO/design/devex reviewer'* && "$PLAN_REVIEW_FULL" == *"$PLAN_REVIEW_LENS"* ]] \
  && ok "rebuilt the full plan-review cto prompt (${#PLAN_REVIEW_FULL} bytes)" || bad "could not rebuild the full reviewPrompt('cto') text (${#PLAN_REVIEW_FULL} bytes)"
ck; [[ "${#PLAN_REVIEW_PLAIN}" -ge 400 && "$PLAN_REVIEW_PLAIN" == *'Structured advisory only'* && "$PLAN_REVIEW_PLAIN" != *'NAMED CEO'* ]] \
  && ok "rebuilt the plan-review engineering-reviewer prompt (${#PLAN_REVIEW_PLAIN} bytes)" || bad "could not rebuild the non-named reviewPrompt text (${#PLAN_REVIEW_PLAIN} bytes)"
ck; [[ -n "$GO_OWN_CUE" ]] && ok "extracted go.md's hold-routing spawn cue: \`$GO_OWN_CUE\`" || bad "go.md's hold-routing paragraph names no 'starts \`Own the epic\`' cue"

# --- C. each existing caller's phrase selects the intended interface ----------------------------------
CL_LABEL=(); CL_WANT=(); CL_PROMPT=()
add_caller() { CL_LABEL+=("$1"); CL_WANT+=("$2"); CL_PROMPT+=("$3"); }   # arrays, not a TSV: the full plan-review prompts span lines
add_caller 'one-shot Technical-rulings spawn' rule "Evidence: src/a.ts:10. Options: A or B. $ONE_SHOT_PHRASE"
add_caller 'work Technical-rulings spawn' rule "Evidence: src/b.ts:22. Options: A or B. $WORK_PHRASE"
add_caller 'delegation reference section-3 brief' rule "$DELEG_OPENER Question: which of two designs?"
add_caller 'delegation brief that mentions a standing delegation' rule "$DELEG_OPENER Question: is the standing delegation for epic #9757 still valid?"
add_caller 'brainstorm Phase 0.5 domain assessment' assess "${DOMAIN_PROMPT//\{desc\}/add a billing page}"
add_caller 'brainstorm Phase 0.5 assessment of a feature about key binding settings' assess "${DOMAIN_PROMPT//\{desc\}/key binding settings}"
add_caller 'brainstorm Phase 0.5 assessment of a feature about data binding in a form' assess "${DOMAIN_PROMPT//\{desc\}/two-way data binding for the settings form}"
add_caller 'plan-review named-panel devex lens (lens text only)' assess "Review this plan through the lens: $PLAN_REVIEW_LENS"
add_caller 'plan-review FULL reviewPrompt for the cto named panel' assess "$PLAN_REVIEW_FULL"
add_caller 'plan-review FULL reviewPrompt for an engineering reviewer' assess "$PLAN_REVIEW_PLAIN"
add_caller 'plan-review full prompt even if its sentence were capitalised like the Rule cue' assess "${PLAN_REVIEW_FULL//do NOT use AskUserQuestion/Do NOT use AskUserQuestion}"
add_caller 'go hold routing' own-the-epic "$GO_OWN_CUE #9757: complete the epic from the resume brief."
add_caller 'go hold routing that also says Do NOT use AskUserQuestion' own-the-epic "$GO_OWN_CUE #9757: finish it. Do NOT use AskUserQuestion."
add_caller 'unrecognised prompt falls back to the existing behaviour' assess 'What should we think about before building the export feature?'
add_caller 'empty prompt falls back to the existing behaviour' assess ' '
caller_n=0
for ci in "${!CL_LABEL[@]}"; do
  label="${CL_LABEL[$ci]}"; want="${CL_WANT[$ci]}"; prompt="${CL_PROMPT[$ci]}"
  caller_n=$((caller_n + 1)); ck
  got="$(classify "$CTO" "$prompt")"
  [[ "$got" == "$want" ]] && ok "caller '$label' selects '$got'" || bad "caller '$label' selects '$got', expected '$want' (prompt: ${prompt:0:100})"
done
ck; [[ "$caller_n" -ge 15 ]] && ok "caller table executed $caller_n rows" || bad "caller table executed $caller_n rows (floor 15)"

# Callers that spawn THROUGH the delegation step (no phrase of their own) must still point at it.
for pair in "$RENDER|delegation step" "$REVIEW|technical-ruling-delegation.md" "$ONE_SHOT|technical-ruling-delegation.md" "$WORK|technical-ruling-delegation.md"; do
  file="${pair%%|*}"; needle="${pair#*|}"; ck
  if grep -Fq -- "$needle" "$file"; then ok "$(basename "$(dirname "$file")")/$(basename "$file") mentions '$needle' (whole-file anchor, not a local one)"
  else bad "$file no longer mentions '$needle'"; fi
done

# --- D. the delegation reference points at the agent and stays consistent with it -----------------------
_s3="$(section3_of "$DELEG")"
_s1="$(awk '/^## 1\. /{ f = 1; next } f && /^## / { f = 0 } f { print }' "$DELEG")"
_s6="$(awk '/^## 6\. /{ f = 1; next } f && /^## / { f = 0 } f { print }' "$DELEG")"
_s7="$(awk '/^## 7\. /{ f = 1; next } f { print }' "$DELEG")"   # to EOF: the example's own `## Decision Classes` line is inside a fence
ck; [[ "$_s3" != *'Reply with exactly these four headings'* && "$_s3" != *'Copy this brief'* ]] && ok "section 3 no longer carries the copied brief" || bad "section 3 still restates the brief"
ck; [[ "$_s3" == *'agents/engineering/cto.md'* && "$_s3" == *'Rule interface'* ]] && ok "section 3 points at the agent's Rule interface" || bad "section 3 does not point at the agent's Rule interface"
ck; [[ "$_s3" == *'Do NOT use AskUserQuestion'* ]] && ok "section 3 still carries the cue callers rely on" || bad "section 3 lost the 'Do NOT use AskUserQuestion' cue"
ck; [[ "$_s3" == *'Question'* && "$_s3" == *'Evidence'* && "$_s3" == *'Brand-survival threshold'* && "$_s3" == *'DISQUALIFY'* ]] && ok "section 3 lists the brief's fields" || bad "section 3 lost a brief field name"
ck; [[ "$_s3" != *'plugins/soleur/'* && "$_s1" != *'plugins/soleur/'* ]] && ok "sections 1 and 3 name no repo-relative plugin path" || bad "section 1 or 3 of the delegation reference names a repo-relative plugins/soleur/ path"
ck; [[ "$_s1" == *'reserves a decision to the operator'* && "$_s1" == *'Undeferred Operator-Step'* && "$_s1" == *'sole-copy destruction'* && "$_s1" == *'rollback is not named'* ]] \
  && ok "section 1 carries the non-delegable list incl. operator-reserved decisions" || bad "section 1 lost part of the non-delegable list (operator-reserved decisions / Undeferred Operator-Step routing)"
ck; [[ "$_s6" == *'Authorized by delegation <comment-url>, envelope <path>[, ran <ISO>]'* ]] && ok "section 6 states the delegation row shape incl. the optional ran clause" || bad "section 6 lost the 'Authorized by delegation <comment-url>, envelope <path>[, ran <ISO>]' row shape"
ck; [[ "$_s1" != *'CLAUDE_PLUGIN_ROOT'* ]] && ok "section 1 names scripts and docs plainly: no plugin-root token, so the reference is not a Read-surface doc and its callers may link it relatively" || bad "section 1 of the delegation reference carries the plugin-root token again (that makes it a Read-surface doc and every relative link to it a violation)"
ck; [[ "$_s6" == *'replaces the plan-time row'* ]] && ok "section 6 says the ran row replaces the plan-time row" || bad "section 6 does not say the ran row replaces the plan-time row"
ck; [[ "$CANON_DISCOVERY" == *'--paginate'* ]] && ok "extracted the canonical discovery command from standing-delegation.md" || bad "could not extract the canonical discovery command"
ck; [[ "$_s1" == *'Operator-reserved:'* && "$_s1" == *'operator-holds.md'* && "$_s6" == *'records the `ran` row in decision-challenges.md'* ]] && ok "the reference links the Operator-reserved grammar and says the CTO records the ran row" || bad "the reference lost the Operator-reserved link or the 'CTO records the ran row' sentence"
ck; [[ "$_s6" == *'overlap vehicle'* && "$_s6" == *'vehicle=<N|this>'* ]] && ok "section 6 names the 'overlap vehicle' ruling row" || bad "section 6 does not describe the 'overlap vehicle' row"
ck; [[ "$_s7" == *'overlap vehicle'* && "$_s7" == *'Ruled by CTO agent'* ]] && ok "section 7's example carries an 'overlap vehicle' ruling row" || bad "section 7's example has no 'overlap vehicle' row"
ck; [[ "$(printf '%s\n' "$_s7" | grep -c 'Authorized by delegation' || true)" -eq 1 ]] && ok "section 7's example still carries exactly one delegation row" || bad "section 7's example must carry exactly one delegation row (the gate suite counts it)"
ck; [[ "$_s1" == *'Rule interface'* || "$_s3" == *'Rule interface'* ]] && ok "the reference points at the Rule interface" || bad "the reference does not point at the Rule interface"

# --- E. mutation rows (each asserts the REASON) --------------------------------------------------------
row() { # <label> <mutated-cto.md> <base> <expected-token|none>
  local label="$1" file="$2" base="$3" want="$4" out rc
  out="$(evaluate_cto "$file" "$base")"; rc=$?
  ck
  if [[ "$want" == none ]]; then
    [[ "$rc" -eq 0 && -z "$out" ]] && ok "$label: stays green" || bad "$label: expected green, got ${out//$'\n'/ }"
  else
    [[ "$rc" -ne 0 ]] && grep -Fxq -- "V:$want" <<<"$out" && ok "$label: RED for '$want'" || bad "$label: expected RED for '$want', got rc=$rc ${out//$'\n'/ }"
  fi
}
misroute_row() { # <label> <mutated-cto.md> <prompt> <must-not-be>
  local label="$1" file="$2" prompt="$3" notwant="$4" got
  got="$(classify "$file" "$prompt")"; ck
  [[ "$got" != "$notwant" ]] && ok "$label: the caller phrase no longer selects '$notwant' (got '$got')" || bad "$label: mutation did not change the selection ('$got')"
}
M="$SANDBOX/m"; mkdir -p "$M"; assert_fixture_dir "$M"
nrows=0

# --- verdict-helper controls: a helper that can never fail would turn every row below into noise ---------
# Each control feeds a helper a known-bad input in a subshell (its own ledger is /dev/null) and requires
# that the helper recorded a FAIL, or, for the green path, a PASS.
awk 'NR <= 6 && /^description:/ && !d { sub(/Participates/, "Participate"); d = 1 } { print }' "$CTO" > "$M/ctl-bad.md"
ctl_fails() { ( VERDICT_LOG=/dev/null; b="$fails"; "$@" >/dev/null 2>&1; [[ "$fails" -gt "$b" ]] ); }
ctl_passes() { ( VERDICT_LOG=/dev/null; b="$passes"; "$@" >/dev/null 2>&1; [[ "$passes" -gt "$b" ]] ); }
ctl_fails row "ctl" "$M/ctl-bad.md" "$BASE_REF" none                    || { printf 'FATAL: control: row() accepted a RED file as green\n' >&2; exit 2; }
ctl_fails row "ctl" "$M/ctl-bad.md" "$BASE_REF" rule-no-menu            || { printf 'FATAL: control: row() accepted a RED file for the wrong token\n' >&2; exit 2; }
ctl_fails row "ctl" "$CTO" "$BASE_REF" frontmatter-differs              || { printf 'FATAL: control: row() accepted a pristine file as RED\n' >&2; exit 2; }
ctl_passes row "ctl" "$M/ctl-bad.md" "$BASE_REF" frontmatter-differs    || { printf 'FATAL: control: row() did not record a PASS for a correct RED row\n' >&2; exit 2; }
ctl_passes row "ctl" "$CTO" "$BASE_REF" none                            || { printf 'FATAL: control: row() did not record a PASS for a correct green row\n' >&2; exit 2; }
ctl_fails misroute_row "ctl" "$CTO" "$ONE_SHOT_PHRASE" rule             || { printf 'FATAL: control: misroute_row() accepted an unchanged selection\n' >&2; exit 2; }
ctl_passes misroute_row "ctl" "$CTO" "$ONE_SHOT_PHRASE" assess          || { printf 'FATAL: control: misroute_row() did not record a PASS for a changed selection\n' >&2; exit 2; }
_o="$(evaluate_cto "$M/ctl-bad.md" "$BASE_REF")"; _r=$?
[[ "$_r" -ne 0 && "$_o" == *'V:frontmatter-differs'* ]] || { printf 'FATAL: control: evaluate_cto() passed a file whose frontmatter changed\n' >&2; exit 2; }
_o="$(evaluate_cto "$CTO" "refs/does-not-exist")"; _r=$?
[[ "$_r" -ne 0 && "$_o" == *'V:base-unresolvable'* ]] || { printf 'FATAL: control: evaluate_cto() passed with an unresolvable base\n' >&2; exit 2; }
[[ "$(classify "$CTO" 'Own the epic #1')" == own-the-epic && "$(classify "$CTO" 'zzz')" == assess ]] || { printf 'FATAL: control: classify() cannot tell an epic prompt from noise\n' >&2; exit 2; }

# F1 flip one byte of the frontmatter description
row "F1 frontmatter description byte changed" "$M/ctl-bad.md" "$BASE_REF" frontmatter-differs; nrows=$((nrows + 1))
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
# F8 drop the money item from the non-delegable LIST LINE ONLY (the Rule section says "money" too, so a global
# substitution would hide a local deletion)
awk '/Non-delegable, ever:/ { gsub(/money, /, "") } { print }' "$CTO" > "$M/f8.md"
row "F8 non-delegable list line loses 'money' (the same word elsewhere is untouched)" "$M/f8.md" "$BASE_REF" epic-nondelegable-list; nrows=$((nrows + 1))
awk '/Non-delegable, ever:/ { gsub(/reserves a decision to the operator/, "is hard") } { print }' "$CTO" > "$M/f8b.md"
row "F8b operator-reserved decisions dropped from the list" "$M/f8b.md" "$BASE_REF" epic-nondelegable-list; nrows=$((nrows + 1))
# F9 close-on-last-verified wording removed
sed 's/last verified item/final item/g' "$CTO" > "$M/f9.md"
row "F9 close-only-on-the-last-verified-item wording removed" "$M/f9.md" "$BASE_REF" epic-close-on-last; nrows=$((nrows + 1))
# H1 base unresolvable is a FAIL
row "H1 unresolvable base ref" "$CTO" "refs/does-not-exist" base-unresolvable; nrows=$((nrows + 1))
# H2 must-PASS: trailing blank lines in the body
{ cat "$CTO"; printf '\n\n'; } > "$M/h2.md"
row "H2 trailing blank lines only" "$M/h2.md" "$BASE_REF" none; nrows=$((nrows + 1))

# Own-the-epic mutations: each removes ONE contract element and must red its own property.
mut() { # <file-out> <sed-expr>
  sed "$2" "$CTO" > "$M/$1"
}
mut e1.md 's/issues\/<epic>\/comments --paginate/issues\/<epic>\/comments/'
row "E1 discovery loses --paginate" "$M/e1.md" "$BASE_REF" epic-discovery; nrows=$((nrows + 1))
mut e2.md 's/--audit --at <ISO8601 UTC>/--audit/'
row "E2 verify synopsis loses --at" "$M/e2.md" "$BASE_REF" epic-verify-synopsis; nrows=$((nrows + 1))
mut e3.md 's/--section "Production Envelope - <title>"/--section "Production Envelope"/'
row "E3 the envelope section is not addressed by title" "$M/e3.md" "$BASE_REF" epic-section-title; nrows=$((nrows + 1))
mut e4.md 's/Epic: #/Epic number /'
row "E4 the Epic: line dropped" "$M/e4.md" "$BASE_REF" epic-epic-line; nrows=$((nrows + 1))
mut e5.md 's/gh workflow run <file>\.yml/gh workflow run <file>/'
row "E5 allowlist loses the workflow-run grammar" "$M/e5.md" "$BASE_REF" epic-allowlist; nrows=$((nrows + 1))
mut e6.md 's/must NOT run/may run/'
row "E6 the CTO is allowed to render a delegation" "$M/e6.md" "$BASE_REF" epic-no-render; nrows=$((nrows + 1))
mut e7.md 's/result=ok|rolled-back/result=done/'
row "E7 receipt format changed" "$M/e7.md" "$BASE_REF" epic-receipt-format; nrows=$((nrows + 1))
mut e8.md 's/gh pr merge <N> --disable-auto/gh pr merge <N>/'
row "E8 stop sequence no longer disarms armed merges" "$M/e8.md" "$BASE_REF" epic-stop-sequence; nrows=$((nrows + 1))
mut e9.md 's/Headless/Interactive/g'
row "E9 headless behaviour removed" "$M/e9.md" "$BASE_REF" epic-headless; nrows=$((nrows + 1))
mut e10.md 's/recorded consent/two independent keys/g'
row "E10 the two-independent-keys claim returns" "$M/e10.md" "$BASE_REF" epic-two-keys-claim; nrows=$((nrows + 1))
mut e11.md 's/"${CLAUDE_PLUGIN_ROOT}\/scripts\/delegation-verify.sh"/plugins\/soleur\/scripts\/delegation-verify.sh/'
row "E11 a repo-relative verifier path" "$M/e11.md" "$BASE_REF" repo-relative-path; nrows=$((nrows + 1))
mut e12.md 's/operator-holds\.md)/operator-holds-gone.md)/g'
row "E12 the holds-container link does not resolve" "$M/e12.md" "$BASE_REF" epic-holds-link-unresolved; nrows=$((nrows + 1))
mut e13.md 's/technical-ruling-delegation\.md)/technical-ruling-gone.md)/g'
row "E13 the Rule interface's reference link does not resolve" "$M/e13.md" "$BASE_REF" rule-link-unresolved; nrows=$((nrows + 1))
# The Epic section's own words do not count for the Rule section (and vice versa): delete the Rule section's
# `never a menu` and the epic section cannot make up for it.
mut e14.md 's/never a menu/never a list/'
row "E14 Rule section loses 'never a menu'" "$M/e14.md" "$BASE_REF" rule-no-menu; nrows=$((nrows + 1))
mut e15.md 's/hold-gate-eval.sh" --file /hold-gate-eval.sh" --plan /'
row "E15 the envelope check no longer uses --file" "$M/e15.md" "$BASE_REF" epic-hold-eval-exit0; nrows=$((nrows + 1))

# --- V1..V22: every positive-only evaluator property gets a row that REMOVES one phrase inside ONE section ---
sub_in() { # <out> <section heading> <from> <to>   literal replace of every <from> inside that section only
  awk -v h="$2" -v from="$3" -v to="$4" '
    index($0, h) == 1 { f = 1; print; next }
    f && /^## / { f = 0 }
    f { line = $0; out = ""; while ((i = index(line, from)) > 0) { out = out substr(line, 1, i - 1) to; line = substr(line, i + length(from)) } print out line; next }
    { print }' "$CTO" > "$M/$1"
}
HDR_SEL='## Interface selector'; HDR_RULE='## Rule interface'; HDR_EPIC='## Own the epic interface'
sed 's/^## Interface selector/## Interface chooser/' "$CTO" > "$M/v1.md"
row "V1 selector heading renamed" "$M/v1.md" "$BASE_REF" selector-missing; nrows=$((nrows + 1))
sub_in v1b.md "$HDR_SEL" 'starts with `Own the epic`' 'starts with an epic prompt'
row "V1b the Own-the-epic rule loses its cue" "$M/v1b.md" "$BASE_REF" selector-missing; nrows=$((nrows + 1))
sub_in v2.md "$HDR_SEL" 'IMPLEMENTATION PLAN (not code)' 'IMPL PLAN'
row "V2 assess cue 'IMPLEMENTATION PLAN (not code)' dropped" "$M/v2.md" "$BASE_REF" selector-assess-cue-plan; nrows=$((nrows + 1))
sub_in v3.md "$HDR_SEL" 'case-sensitively' 'literally'
row "V3 selector no longer declares case-sensitivity" "$M/v3.md" "$BASE_REF" selector-case-undeclared; nrows=$((nrows + 1))
sed 's/^## Rule interface/## Ruling interface/' "$CTO" > "$M/v4.md"
row "V4 Rule section heading renamed" "$M/v4.md" "$BASE_REF" rule-section-missing; nrows=$((nrows + 1))
sub_in v5.md "$HDR_RULE" 'unverified' 'unchecked'
row "V5 evidence bar loses 'unverified'" "$M/v5.md" "$BASE_REF" rule-evidence-bar; nrows=$((nrows + 1))
sub_in v6.md "$HDR_RULE" 'never ask' 'maybe ask'
row "V6 Rule section loses 'never ask'" "$M/v6.md" "$BASE_REF" rule-headless; nrows=$((nrows + 1))
sub_in v7.md "$HDR_RULE" 'Item <id>:' 'Row <id>:'
row "V7 multi-item form renamed" "$M/v7.md" "$BASE_REF" rule-multi-item; nrows=$((nrows + 1))
sub_in v8.md "$HDR_RULE" '[technical-ruling-delegation.md](${CLAUDE_PLUGIN_ROOT}/skills/brainstorm-techniques/references/technical-ruling-delegation.md)' 'the delegation reference'
row "V8 Rule section loses its reference link" "$M/v8.md" "$BASE_REF" rule-link-missing; nrows=$((nrows + 1))
sed 's/^## Own the epic interface/## Epic interface/' "$CTO" > "$M/v9.md"
row "V9 Own-the-epic heading renamed" "$M/v9.md" "$BASE_REF" epic-section-missing; nrows=$((nrows + 1))
sub_in v10.md "$HDR_EPIC" 'delegation-verify.sh' 'delegation-check.sh'
row "V10 the verifier is no longer named" "$M/v10.md" "$BASE_REF" epic-verifier; nrows=$((nrows + 1))
sub_in v11.md "$HDR_EPIC" 'hold-gate-eval.sh' 'hold-check.sh'
row "V11 the hold evaluator is no longer named" "$M/v11.md" "$BASE_REF" epic-hold-eval; nrows=$((nrows + 1))
sub_in v12.md "$HDR_EPIC" 'Gate:' 'Gat:'
row "V12 no Gate: predicates" "$M/v12.md" "$BASE_REF" epic-gate-predicates; nrows=$((nrows + 1))
sub_in v13.md "$HDR_EPIC" '## Production Envelope' '## Prod Envelope'
row "V13 the Production Envelope heading renamed" "$M/v13.md" "$BASE_REF" epic-envelope; nrows=$((nrows + 1))
sub_in v14.md "$HDR_EPIC" 'action-required' 'needs-operator'
row "V14 the stall issue label dropped" "$M/v14.md" "$BASE_REF" epic-stall-issue; nrows=$((nrows + 1))
sub_in v15.md "$HDR_EPIC" 'never fall back to an older' 'may fall back to an older'
row "V15 discovery may fall back to an older delegation" "$M/v15.md" "$BASE_REF" epic-discovery-pick; nrows=$((nrows + 1))
sub_in v16.md "$HDR_EPIC" 'run summary' 'final note'
row "V16 delegated acts no longer go in the run summary" "$M/v16.md" "$BASE_REF" epic-receipt-wiring; nrows=$((nrows + 1))
sub_in v17.md "$HDR_EPIC" 'drift guard' 'check'
row "V17 the consent wording loses 'drift guard'" "$M/v17.md" "$BASE_REF" epic-consent-wording; nrows=$((nrows + 1))
sub_in v18.md "$HDR_EPIC" 'Undeferred Operator-Step' 'Operator Queue'
row "V18 operator-reserved holds no longer route to the Undeferred Operator-Step Gate" "$M/v18.md" "$BASE_REF" epic-reserved-routing; nrows=$((nrows + 1))
sub_in v19.md "$HDR_EPIC" '[operator-holds.md](${CLAUDE_PLUGIN_ROOT}/skills/ship/references/operator-holds.md)' 'the holds reference'
row "V19 the holds-container link dropped" "$M/v19.md" "$BASE_REF" epic-holds-link-missing; nrows=$((nrows + 1))
sub_in v20.md "$HDR_EPIC" '"${CLAUDE_PLUGIN_ROOT}/scripts/delegation-verify.sh"' '${CLAUDE_PLUGIN_ROOT}/scripts/delegation-verify.sh'
row "V20 the verifier path loses its quotes" "$M/v20.md" "$BASE_REF" plugin-root-paths; nrows=$((nrows + 1))
sub_in v21.md "$HDR_EPIC" 'Cloud Mode' 'Devin mode'
row "V21 the unset-CLAUDE_PLUGIN_ROOT sentence loses its pointer" "$M/v21.md" "$BASE_REF" plugin-root-unset-undeclared; nrows=$((nrows + 1))
printf 'not the agent file\n' > "$M/degenerate-base.txt"
row "V22 a degenerate base (not the real file)" "$CTO" "file:$M/degenerate-base.txt" base-degenerate; nrows=$((nrows + 1))
sub_in v18b.md "$HDR_EPIC" 'Operator-reserved:' 'Reserved:'
row "V18b the Operator-reserved marker dropped" "$M/v18b.md" "$BASE_REF" epic-reserved-routing; nrows=$((nrows + 1))
sub_in v26.md "$HDR_EPIC" 'one receipt per act' 'receipts as needed'
row "V26 the receipt rules lose 'one receipt per act'" "$M/v26.md" "$BASE_REF" epic-receipt-rules; nrows=$((nrows + 1))
sub_in v27.md "$HDR_EPIC" 'replace the plan-time row' 'keep both rows'
row "V27 the plan-time row is kept next to the ran row" "$M/v27.md" "$BASE_REF" epic-ran-row; nrows=$((nrows + 1))
sub_in v28.md "$HDR_EPIC" 'last line upward' 'first line downward'
row "V28 discovery drifts from the canonical command" "$M/v28.md" "$BASE_REF" epic-discovery; nrows=$((nrows + 1))
sub_in v23.md "$HDR_EPIC" 'decision-challenges.md' 'the rulings file'
row "V23 the ran row is not recorded in decision-challenges.md" "$M/v23.md" "$BASE_REF" epic-ran-row; nrows=$((nrows + 1))
sub_in v24.md "$HDR_EPIC" 'delete EVERY delegation marker comment' 'delete the delegation comment'
row "V24 the stop sequence deletes only one comment" "$M/v24.md" "$BASE_REF" epic-stop-sequence; nrows=$((nrows + 1))
# N14: with base == HEAD the anchor is SKIPPED (a printed reason, not a silent pass) and a changed file is still caught
ck
_o="$(evaluate_cto "$M/ctl-bad.md" "$HEAD_SHA" skip)"; _r=$?
[[ "$_r" -eq 0 && "$_o" != *frontmatter-differs* ]] && ok "N14 anchor skip mode does not evaluate the merge-base comparison" || bad "N14 skip mode still ran the anchor: ${_o//$'\n'/ }"
row "N14b against HEAD as base a changed file is still RED (the rows stay meaningful after merge)" "$M/ctl-bad.md" "$HEAD_SHA" frontmatter-differs; nrows=$((nrows + 1))

# Selector mutations: a cue removed from the document must change what a real caller gets.
sed 's/`[Dd]o NOT use AskUserQuestion`/`do-not-use-the-ask-tool`/g' "$CTO" > "$M/s1.md"
misroute_row "S1 both 'Do/do NOT use AskUserQuestion' cues removed (one-shot phrase)" "$M/s1.md" "Evidence: x. $ONE_SHOT_PHRASE" rule; nrows=$((nrows + 1))
sed 's/`Own the epic`/`Take the epic`/' "$CTO" > "$M/s2.md"
misroute_row "S2 'Own the epic' cue removed (go phrase)" "$M/s2.md" "$GO_OWN_CUE #1: finish" own-the-epic; nrows=$((nrows + 1))
# S3 over-broad cue: the word 'question' as a Rule cue would hijack the brainstorm prompt
sed 's/`BINDING`/`BINDING`, `question`/' "$CTO" > "$M/s3.md"
misroute_row "S3 over-broad 'question' cue (brainstorm prompt)" "$M/s3.md" "${DOMAIN_PROMPT//\{desc\}/x}" assess; nrows=$((nrows + 1))
# S4 the assess-first rule removed: a plan-review prompt written with the capitalised cue reaches Rule
sed 's/`Structured advisory only` or `IMPLEMENTATION PLAN (not code)`/`zz-gone-1` or `zz-gone-2`/' "$CTO" > "$M/s4.md"
misroute_row "S4 assess-first cues removed (plan-review prompt, capitalised sentence)" "$M/s4.md" "${PLAN_REVIEW_FULL//do NOT use AskUserQuestion/Do NOT use AskUserQuestion}" assess; nrows=$((nrows + 1))
row "S4b assess-first cues removed" "$M/s4.md" "$BASE_REF" selector-assess-cue-structured; nrows=$((nrows + 1))
# S5 a lowercase `binding` cue brings back the false positive on feature text
sed 's/`BINDING`/`BINDING`, `binding`/' "$CTO" > "$M/s5.md"
misroute_row "S5 lowercase 'binding' cue (a feature about key binding settings)" "$M/s5.md" "${DOMAIN_PROMPT//\{desc\}/key binding settings}" assess; nrows=$((nrows + 1))
row "S5b lowercase 'binding' cue" "$M/s5.md" "$BASE_REF" selector-lowercase-binding; nrows=$((nrows + 1))
# S6 the assess rule moved after the Rule rule
awk '/^2\. The prompt contains `Structured/ { held = $0; next } held != "" && /^3\. / { print; print held; held = ""; next } { print }' "$CTO" > "$M/s6.md"
row "S6 assess rule placed after the Rule rule" "$M/s6.md" "$BASE_REF" selector-assess-after-rule; nrows=$((nrows + 1))

# Late-redefinition defence: re-run the controls AFTER the last row. A helper redefined (or shadowed) between the
# first controls and here would otherwise grade every row above with a different function.
ctl_fails row "ctl-late" "$M/ctl-bad.md" "$BASE_REF" none               || { printf 'FATAL: late control: row() accepted a RED file as green\n' >&2; exit 2; }
ctl_fails row "ctl-late" "$M/ctl-bad.md" "$BASE_REF" rule-no-menu       || { printf 'FATAL: late control: row() accepted the wrong token\n' >&2; exit 2; }
ctl_passes row "ctl-late" "$CTO" "$BASE_REF" none                        || { printf 'FATAL: late control: row() cannot record a PASS\n' >&2; exit 2; }
ctl_fails misroute_row "ctl-late" "$CTO" "$ONE_SHOT_PHRASE" rule        || { printf 'FATAL: late control: misroute_row() accepted an unchanged selection\n' >&2; exit 2; }

# --- F. informational census of every cto spawn surface (drift is a WARN, never a vacuous green) ------
SURFACES="$(git -C "$ROOT" grep -l 'soleur:engineering:cto' -- plugins/soleur/skills plugins/soleur/commands .claude/hooks scripts .github/workflows 2>/dev/null | sort || true)"
ck; [[ "$(printf '%s\n' "$SURFACES" | grep -c . || true)" -ge 8 ]] && ok "cto spawn-surface census found $(printf '%s\n' "$SURFACES" | grep -c .) files" || bad "cto spawn-surface census found fewer than 8 files (grep scope broke)"

# --- ANTI-VACUITY: the assertion floors --------------------------------------------------------------------
# (1) derived: properties + aggregate + anchor + extraction floors + callers + caller floor + 4 delegation-path
#     rows + 11 reference rows + mutation rows + census.
# (2) ABSOLUTE: the count of a green run, committed with ZERO slack. A derived floor moves with the rows it
#     guards (delete six rows and the floor drops with them), so this constant is the one that bites. Raise it
#     in the same commit that adds rows, never ahead of them.
EXPECTED_ASSERTIONS=$(( nprops + 1 + 1 + 8 + caller_n + 1 + 4 + 15 + nrows + 1 + 1 ))
ABSOLUTE_FLOOR=167
MIN_ASSERTIONS=$(( EXPECTED_ASSERTIONS > ABSOLUTE_FLOOR ? EXPECTED_ASSERTIONS : ABSOLUTE_FLOOR ))
if [[ "$asserted" -lt "$MIN_ASSERTIONS" ]]; then
  printf '\nFATAL: anti-vacuity: %d assertion(s) executed, floor is %d. The battery ran but did not assert.\n' "$asserted" "$MIN_ASSERTIONS" >&2
  exit 1
fi
_lp="$(grep -c '^PASS$' "$VERDICT_LOG" || true)"
_lf="$(grep -c '^FAIL$' "$VERDICT_LOG" || true)"
_ls="$(grep -c '^SKIP$' "$VERDICT_LOG" || true)"
if [[ "${_lp:-0}" -ne "$passes" || "${_lf:-0}" -ne "$fails" || "${_ls:-0}" -ne "$skips" || $((passes + fails + skips)) -ne "$asserted" ]]; then
  printf '\nFATAL: accounting: ledger (%s pass / %s fail / %s skip) vs counters (%d / %d / %d), asserted %d.\n' "${_lp:-0}" "${_lf:-0}" "${_ls:-0}" "$passes" "$fails" "$skips" "$asserted" >&2
  exit 1
fi
printf '\ncto-interface-selector.test.sh: %d passed, %d failed, %d skipped, %d assertion(s) executed (floor %d); base %s\n' \
  "$passes" "$fails" "$skips" "$asserted" "$MIN_ASSERTIONS" "${BASE_REF:0:12}"
[[ "$fails" -eq 0 && "$passes" -gt 0 ]] || exit 1
exit 0
