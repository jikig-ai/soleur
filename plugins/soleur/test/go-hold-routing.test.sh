#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2015,SC2016  # row functions are dispatched indirectly; A && B || C is the assertion idiom; literals are single-quoted on purpose
# Guard 6 of the CTO standing-delegation plan
# (knowledge-base/project/plans/archive/20261015-183324-2026-10-15-feat-cto-standing-delegation-and-production-envelope-plan.md).
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
# question (whose text must render the Scope items, the expiry, 30 days, every merge, ready, dispatch and revert-PR listed,
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
#   dropline: print the file without the paragraph line(s) that contain `from` (case-insensitive)
para_awk() {
  local mode="$1" file="$2" from="${3:-}" to="${4:-}"
  awk -v mode="$mode" -v hre="$HEADING_RE" -v s="$BLOCK_START" -v e="$BLOCK_END" -v from="$from" -v to="$to" '
    function endsPara(l) { return (l ~ /^#+ /) || index(l, s) || index(l, e) }
    {
      if (!inp && $0 ~ hre) { inp = 1; started++ }
      else if (inp && endsPara($0)) { inp = 0 }
      if (mode == "extract") { if (inp) print; next }
      if (mode == "strip")   { if (!inp) print; next }
      if (mode == "dropline") { if (!(inp && from != "" && index(tolower($0), tolower(from)))) print; next }
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
  [[ "$para" == *'`OWNER-GATED`'* ]]       || emit token-OWNER-GATED
  [[ "$para" == *'does not by itself make a hold list'* ]] || emit standing-line-not-a-trigger
  [[ "$para" == *'only when'* && "$para" == *'BOTH'* ]] || emit routing-requires-both
  [[ "$para" == *'`ask the operator`'* && "$para" == *'ordinary message'* ]] || emit ask-the-operator-not-a-trigger
  [[ "$para" == *'fail closed'* || "$para" == *'Fail closed'* ]] || emit wording-fail-closed
  [[ "$para" == *'ask once'* || "$para" == *'Ask once'* ]]       || emit wording-ask-once
  [[ "$para" == *'soleur:engineering:cto'* && "$para" == *'Own the epic'* ]] || emit owner-cto-own-the-epic
  [[ "$para" == *'## Operator Holds'* && "$para" == *'Gate:'* && "$para" == *'hold-gate-eval.sh'* ]] || emit gate-handoff
  [[ "$para" == *'operator-holds.md'* ]]   || emit container-link
  [[ "$para" == *'delegation-verify.sh'* && "$para" == *'`render`'* && "$para" == *'calling skill'* && "$para" == *'AFTER'* ]] || emit delegation-render
  [[ "$para" == *'Scope items'* && "$para" == *'30 days'* && "$para" == *'every merge, ready, dispatch and revert-PR listed'* && "$para" == *'posted publicly'* && "$para" == *'business terms'* && "$para" == *'expiry'* ]] || emit render-text
  [[ "$para" == *'Headless'* && "$para" == *'do not ask'* && "$para" == *'action-required'* && "$para" == *'draft PR'* ]] || emit headless
  [[ "$para" == *'"${CLAUDE_PLUGIN_ROOT}/scripts/delegation-verify.sh"'* && "$para" == *'"${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/hold-gate-eval.sh"'* ]] || emit plugin-root-paths
  if [[ "$para" == *'plugins/soleur/'* ]]; then emit repo-relative-path; fi
  [[ "$para" == *'execution sentence'* && "$para" == *'run summary'* ]] || emit receipt-wiring
  [[ "$para" == *'never call AskUserQuestion for a technical hold'* ]] || emit no-askuserquestion-for-technical-hold
  [[ "$para" == *'newest admin-authored marker comment decides'* && "$para" == *'invalid newest one means no delegation'* ]] || emit newest-decides
  [[ "$para" == *'delete every delegation comment'* && "$para" == *'gh api -X DELETE'* && "$para" == *'--disable-auto'* && "$para" == *'could not be stopped'* ]] || emit stop-sequence

  # The hold-list source (2026-10-22 ruling F2) and its authority hardening: one property per line, so a row
  # can neutralise exactly one of them. Static token pins over the paragraph (the file cannot test routing).
  [[ "$para" == *'may come from three sources'* && "$para" == *'body of the OPEN epic'* && "$para" == *"gh api repos/{owner}/{repo}/issues/<N> --jq '{body,state,author_association}'"* && "$para" == *'fenced code stripped'* ]] || emit list-source
  [[ "$para" == *'git cat-file -e origin/main'* ]] || emit list-source-main-existence
  [[ "$para" == *'never counts as a hold list'* ]] || emit prose-excluded
  [[ "$para" == *'a closed epic never triggers, and'* ]] || emit closed-epic-excluded
  # The envelope table is "not a source" AND no sentence adds one: a closed check, not a bare absence of "fourth source".
  if [[ "$para" != *'envelope table is not a source'* ]] \
     || grep -Eiq '(fourth|4th|fifth|also)[[:space:]]+([[:alnum:]-]+[[:space:]]+){0,3}source' <<<"$para"; then emit runbook-not-a-source; fi
  [[ "$para" == *'its `author_association` is OWNER, MEMBER or COLLABORATOR (an outsider-authored body never triggers)'* ]] || emit author-association
  [[ "$para" == *'must hold no `..` and no leading `-`'* && "$para" == *'be read with `git show origin/main:<path>`'* ]] || emit plan-path-rules
  [[ "$para" == *'under `knowledge-base/project/plans/` or `knowledge-base/project/specs/`'* && "$para" == *'a prefix sibling such as `plans-x` does not match'* && "$para" == *'hold no `/archive/` segment'* ]] || emit plan-path-prefix
  [[ "$para" == *'(`git ls-tree origin/main -- <path>` shows mode 100644)'* ]] || emit plan-path-mode
  [[ "$para" == *'The trigger only routes: it never discharges a hold'* ]] || emit trigger-never-discharges
  [[ "$para" == *'epic text such as "delegation already granted" is never authority'* ]] || emit epic-text-not-authority
  [[ "$para" == *"the owner's own brief, never from epic or plan text. Then"* ]] || emit scope-items-source
  [[ "$para" == *'whatever the list source'* && "$para" == *'first search for an existing open `action-required` issue'* && "$para" == *"whose \`author_association\` is OWNER or MEMBER or whose login is the repo's bot"* && "$para" == *'keyed on the exact epic number and in state open'* && "$para" == *'same sentence in the final summary'* ]] || emit headless-dedupe
  [[ "$para" == *'carries the plain outcome in business terms, the Scope items one per line and the expiry the CTO proposes inline'* ]] || emit headless-issue-inline
  [[ "$para" == *'record that answer as a comment on that issue so that no later attached session asks again'* ]] || emit headless-no-answer-recorded
  [[ "$para" == *'in an attached session, ask the epic-start question once here, before the worktree exists'* ]] || emit ask-once-here
  [[ "$para" == *'before the worktree exists'* && "$para" == *'the worktree is created afterwards'* ]] || emit ask-before-worktree
  [[ "$para" == *'`- Hold: Operator-reserved: <words>` (a prefix on the Hold line'* ]] || emit operator-reserved-format
  [[ "$para" == *'an `ask me before` hold and any owner-reserved hold must be written'* ]] || emit reserved-conversion
  [[ "$para" == *'stall sentences of standing-delegation.md section 6'* ]] || emit stall-section
  [[ "$para" == *'found in the brief itself, in the open epic'* ]] || emit routing-widened
  [[ "$para" == *'in none of those three places'* ]] || emit closing-widened

  # Delegation-safety clauses (second-round review): WHOLE-CLAUSE pins that include the verb, so inverting what a
  # rule says (not only deleting a token) goes RED. One property per clause; M56..M68 invert one each.
  [[ "$para" == *'still stands and is never discharged on a guess'* ]] || emit no-guess-discharge
  [[ "$para" == *'the calling skill (never the CTO) record it with `render`'* ]] || emit render-not-cto
  [[ "$para" == *'(a record that is not `valid` is deleted)'* ]] || emit invalid-record-deleted
  [[ "$para" == *'The CTO re-runs `verify` immediately before every delegated act'* ]] || emit verify-before-each-act
  [[ "$para" == *"ship's own auto-merge arming of its PR is not a delegated act"* ]] || emit ship-arming-not-delegated
  [[ "$para" == *'and leaves every hold standing'* ]] || emit stall-holds-stand
  [[ "$para" == *'falls through to normal routing, and its holds still stand'* ]] || emit paraphrase-holds-stand
  [[ "$para" == *'disarm every auto-merge the CTO armed (`gh pr merge <N> --disable-auto`)'* ]] || emit disarm-auto-merge
  [[ "$para" == *'do not ask. No delegation exists, so every production act stays a hold'* ]] || emit headless-no-delegation
  [[ "$para" == *'the expiry (30 days at most)'* ]] || emit expiry-30-days-at-most
  [[ "$para" == *'asks once unless a recorded No is on it'* ]] || emit later-session-asks-once
  [[ "$para" == *'under a runbook path, never in an archived folder'* ]] || emit envelope-not-archived

  # Headless dedupe recipe (REST: `gh issue list --json` has no authorAssociation field), the reply line, and the
  # lifetime of a recorded No.
  [[ "$para" == *"gh api 'repos/{owner}/{repo}/issues?state=open&labels=action-required&per_page=100'"* && "$para" == *'to items without `.pull_request`'* && "$para" == *"whose \`.author_association\` is OWNER or MEMBER (or whose \`.user.login\` is the repo's bot)"* && "$para" == *'names the exact epic number'* && "$para" == *'has no `authorAssociation` field'* ]] || emit headless-dedupe-recipe
  [[ "$para" == *'the issue body ends with `Reply Yes or No in a comment here, or tell the agent in your next session`'* ]] || emit headless-issue-reply-line
  [[ "$para" == *'that No ends when the Scope or the expiry changes (a new issue or a comment that states the new Scope is asked once again)'* ]] || emit no-ends-on-scope-change
  [[ "$para" == *"records that No as a comment on the epic's \`action-required\` issue"* ]] || emit attached-no-recorded
  [[ "$para" == *'a standing headless hold issue is surfaced again by the next attached session'* ]] || emit standing-issue-resurfaced

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

# ship/SKILL.md wiring: the merge-mode block sits at the START of Phase 6.45 (before the archival paragraph, because the
# archive moves the plan and the rulings file it reads); the sentence right after it gives the full ${CLAUDE_PLUGIN_ROOT}
# invocation of the hold evaluator (the pinned block names it bare); step 5's exit table treats any other status as 2.
SHIP_MD="$ROOT/plugins/soleur/skills/ship/SKILL.md"
evaluate_ship() { # <ship SKILL.md> -> V:<token> lines
  local f="$1" v=0 blk arch p645 nxt s5
  emit() { printf 'V:%s\n' "$1"; v=1; }
  blk="$(grep -n -F -m1 'Before Phase 6.45 archives the plan and rulings file, run' "$f" | cut -d: -f1)"
  arch="$(grep -n -F -m1 '**KB artifact archival' "$f" | cut -d: -f1)"
  p645="$(grep -n -F -m1 '## Phase 6.45' "$f" | cut -d: -f1)"
  [[ -n "$blk" && -n "$arch" && -n "$p645" && "$blk" -gt "$p645" && "$blk" -lt "$arch" ]] || emit ship-block-misplaced
  nxt="$(awk -v b="${blk:-0}" 'NR > b && NF { print; exit }' "$f")"
  [[ "$nxt" == *'bash "${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/hold-gate-eval.sh"'* ]] || emit ship-invocation-missing
  s5="$(grep -F -m1 'A recorded operator HOLD is a condition' "$f")"
  [[ "$s5" == *'124, 127, 137'* && "$s5" == *'treated as 2'* ]] || emit ship-exit-status
  [[ "$s5" == *'start of Phase 6.45, before the plan is archived'* ]] || emit ship-second-look-wording
  if grep -Fq 'Before the `merge-main` lock block, run' "$f"; then emit ship-old-block; fi
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
ALL_PROPS="paragraph-missing token-HOLDS token-epic-ref token-OWNER-GATED standing-line-not-a-trigger routing-requires-both ask-the-operator-not-a-trigger wording-fail-closed wording-ask-once owner-cto-own-the-epic gate-handoff container-link delegation-render render-text headless plugin-root-paths repo-relative-path receipt-wiring no-askuserquestion-for-technical-hold newest-decides stop-sequence list-source list-source-main-existence prose-excluded closed-epic-excluded runbook-not-a-source author-association plan-path-rules plan-path-prefix plan-path-mode trigger-never-discharges epic-text-not-authority scope-items-source headless-dedupe headless-issue-inline headless-no-answer-recorded ask-once-here ask-before-worktree operator-reserved-format reserved-conversion stall-section routing-widened closing-widened no-guess-discharge render-not-cto invalid-record-deleted verify-before-each-act ship-arming-not-delegated stall-holds-stand paraphrase-holds-stand disarm-auto-merge headless-no-delegation expiry-30-days-at-most later-session-asks-once envelope-not-archived headless-dedupe-recipe headless-issue-reply-line no-ends-on-scope-change attached-no-recorded standing-issue-resurfaced anchors-missing paragraph-inside-block paragraph-misplaced base-unresolvable base-degenerate block-hash-differs"
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

SHIP_OUT="$(evaluate_ship "$SHIP_MD")"; SHIP_RC=$?
for p in ship-block-misplaced ship-invocation-missing ship-exit-status ship-second-look-wording ship-old-block; do
  ck
  if grep -Fxq -- "V:$p" <<<"$SHIP_OUT"; then bad "ship/SKILL.md violates '$p'"; else ok "ship/SKILL.md has no violation of '$p'"; fi
done
ck
[[ "$SHIP_RC" -eq 0 && -z "$SHIP_OUT" ]] && ok "evaluate_ship agrees: rc=0 and no violation lines" || bad "evaluate_ship reported violations: ${SHIP_OUT//$'\n'/ }"

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

# M5b / M5c the 2026-10-19 widening: an OWNER-GATED brief routes, and a standing CTO line is a modifier, not a trigger
para_awk sub "$GO_MD" '`OWNER-GATED`' '`GATED`' > "$M/m5b.md"
row "M5b remove the OWNER-GATED token, keep HOLDS" "$M/m5b.md" "$BASE_REF" token-OWNER-GATED; nrows=$((nrows + 1))
para_awk sub "$GO_MD" 'does not by itself make a hold list' 'makes a hold list' > "$M/m5c.md"
row "M5c let a standing CTO line make a hold list by itself" "$M/m5c.md" "$BASE_REF" standing-line-not-a-trigger; nrows=$((nrows + 1))

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

# M26..M38: the hold-list source and its authority hardening, one mutation per property
para_awk dropline "$GO_MD" 'may come from three sources' > "$M/m26.md"
row "M26 delete the list-source bullet" "$M/m26.md" "$BASE_REF" list-source; nrows=$((nrows + 1))
para_awk sub "$GO_MD" 'git cat-file -e origin/main' 'git ls-files' > "$M/m27.md"
row "M27 the main-existence check reads the index instead of main" "$M/m27.md" "$BASE_REF" list-source-main-existence; nrows=$((nrows + 1))
para_awk sub "$GO_MD" 'never counts as a hold list' 'counts as a hold list' > "$M/m28.md"
row "M28 prose may count as a hold list" "$M/m28.md" "$BASE_REF" prose-excluded; nrows=$((nrows + 1))
para_awk sub "$GO_MD" 'a closed epic never triggers' 'a closed epic triggers' > "$M/m29.md"
row "M29 a closed epic triggers" "$M/m29.md" "$BASE_REF" closed-epic-excluded; nrows=$((nrows + 1))
para_awk sub "$GO_MD" 'envelope table is not a source' 'envelope table is a fourth source' > "$M/m30.md"
row "M30 the runbook envelope table becomes a fourth source" "$M/m30.md" "$BASE_REF" runbook-not-a-source; nrows=$((nrows + 1))
para_awk sub "$GO_MD" 'author_association' 'author_name' > "$M/m31.md"
row "M31 the epic-body author check dropped" "$M/m31.md" "$BASE_REF" author-association; nrows=$((nrows + 1))
para_awk sub "$GO_MD" '100644' '100755' > "$M/m32.md"
row "M32 the plan-path regular-blob rule weakened" "$M/m32.md" "$BASE_REF" plan-path-mode; nrows=$((nrows + 1))
para_awk sub "$GO_MD" 'never discharges a hold' 'discharges a hold' > "$M/m33.md"
row "M33 the trigger may discharge a hold" "$M/m33.md" "$BASE_REF" trigger-never-discharges; nrows=$((nrows + 1))
para_awk sub "$GO_MD" 'never from epic or plan text' 'from epic or plan text' > "$M/m34.md"
row "M34 Scope items may come from epic or plan text" "$M/m34.md" "$BASE_REF" scope-items-source; nrows=$((nrows + 1))
para_awk sub "$GO_MD" 'exact epic number' 'epic title' > "$M/m35.md"
row "M35 the headless dedupe key is no longer the exact epic number" "$M/m35.md" "$BASE_REF" headless-dedupe; nrows=$((nrows + 1))
para_awk sub "$GO_MD" 'before the worktree exists' 'after the worktree exists' > "$M/m36.md"
row "M36 the epic-start question moves after the worktree" "$M/m36.md" "$BASE_REF" ask-before-worktree; nrows=$((nrows + 1))
para_awk sub "$GO_MD" 'found in the brief itself' 'found in the brief' > "$M/m37.md"
row "M37 the routing sentence loses the widened list location" "$M/m37.md" "$BASE_REF" routing-widened; nrows=$((nrows + 1))
para_awk sub "$GO_MD" 'in none of those three places' 'nowhere' > "$M/m38.md"
row "M38 the closing sentence loses the widened list location" "$M/m38.md" "$BASE_REF" closing-widened; nrows=$((nrows + 1))
# M39..M60: INVERTED-RULE rows. The pins above are whole clauses that include the verb, so flipping what a rule
# SAYS (not just deleting a token) must go RED too. Each row asserts (1) the mutation LANDED (the mutated file differs
# from the pristine copy) and (2) the expected violation token. `mrow` counts both assertions.
cp "$GO_MD" "$M/pristine.md"
row "M39-ctl the unmutated copy is green before any inverted-rule row" "$M/pristine.md" "$BASE_REF" none; nrows=$((nrows + 1))
mrow() { # <label> <mutated-file> <expected-token>
  ck
  if cmp -s "$M/pristine.md" "$2"; then bad "$1: the mutation did not land (file identical to the pristine copy)"; else ok "$1: the mutation landed"; fi
  nrows=$((nrows + 2)); row "$1" "$2" "$BASE_REF" "$3"
}
para_awk sub "$GO_MD" 'OWNER, MEMBER or COLLABORATOR' 'OWNER, MEMBER or COLLABORATOR, CONTRIBUTOR or NONE' > "$M/m39.md"
mrow "M39 the author_association clause is widened to CONTRIBUTOR or NONE" "$M/m39.md" author-association
para_awk sub "$GO_MD" 'shows mode 100644' 'shows any mode but 100644' > "$M/m40.md"
mrow "M40 the mode clause is inverted" "$M/m40.md" plan-path-mode
para_awk sub "$GO_MD" 'a closed epic never triggers' 'a closed epic never triggers unless it has a recorded delegation' > "$M/m41.md"
mrow "M41 a closed epic gains an exception" "$M/m41.md" closed-epic-excluded
para_awk sub "$GO_MD" 'is never authority' 'is authority' > "$M/m42.md"
mrow "M42 epic text becomes authority" "$M/m42.md" epic-text-not-authority
para_awk sub "$GO_MD" 'never from epic or plan text' 'never from epic or plan text, except plan text' > "$M/m43.md"
mrow "M43 Scope items may come from plan text" "$M/m43.md" scope-items-source
para_awk sub "$GO_MD" 'ask the epic-start question once here' 'never ask the epic-start question' > "$M/m44.md"
mrow "M44 the epic-start question is never asked" "$M/m44.md" ask-once-here
para_awk sub "$GO_MD" 'envelope table is not a source' 'envelope table is not a source of holds, but is also a source' > "$M/m45.md"
mrow "M45 the envelope table is also a source (closed check)" "$M/m45.md" runbook-not-a-source
para_awk sub "$GO_MD" 'The trigger only routes' 'The trigger also routes' > "$M/m46.md"
mrow "M46 the trigger does more than route" "$M/m46.md" trigger-never-discharges
para_awk sub "$GO_MD" 'knowledge-base/project/plans/' 'knowledge-base/project/plans' > "$M/m47.md"
mrow "M47 the plans prefix loses its trailing slash" "$M/m47.md" plan-path-prefix
para_awk sub "$GO_MD" 'hold no `/archive/` segment' 'allow an `/archive/` segment' > "$M/m48.md"
mrow "M48 an archived plan path is allowed" "$M/m48.md" plan-path-prefix
para_awk sub "$GO_MD" 'OWNER or MEMBER or whose login is' 'any author or whose login is' > "$M/m49.md"
mrow "M49 the headless dedupe matches any author" "$M/m49.md" headless-dedupe
para_awk sub "$GO_MD" 'whatever the list source' 'when the list came from the epic body or a plan' > "$M/m50.md"
mrow "M50 the headless dedupe covers only epic or plan lists" "$M/m50.md" headless-dedupe
para_awk sub "$GO_MD" 'the Scope items one per line and the expiry the CTO proposes inline' 'the Scope items and the expiry by pointer only' > "$M/m51.md"
mrow "M51 the filed issue no longer carries the Scope items inline" "$M/m51.md" headless-issue-inline
para_awk sub "$GO_MD" 'record that answer as a comment on that issue' 'discard that answer' > "$M/m52.md"
mrow "M52 a No answer is not recorded" "$M/m52.md" headless-no-answer-recorded
para_awk sub "$GO_MD" '(a prefix on the Hold line' '(a suffix on the Hold line' > "$M/m53.md"
mrow "M53 Operator-reserved becomes a suffix" "$M/m53.md" operator-reserved-format
para_awk sub "$GO_MD" 'must be written' 'may be written' > "$M/m54.md"
mrow "M54 owner-reserved conversion becomes optional" "$M/m54.md" reserved-conversion
para_awk sub "$GO_MD" 'standing-delegation.md section 6' 'standing-delegation.md section 7' > "$M/m55.md"
mrow "M55 the stall sentences point at the wrong section" "$M/m55.md" stall-section
# M56..M75: whole-clause inversions of the delegation-safety rules and the dedupe/reply/No-lifetime clauses added in the
# second review round. Each mutates ONE clause inside the paragraph; `mrow` also asserts the mutation landed.
para_awk sub "$GO_MD" 'is never discharged on a guess' 'is discharged on a guess' > "$M/m56.md"
mrow "M56 a fail-closed hold is discharged on a guess" "$M/m56.md" no-guess-discharge
para_awk sub "$GO_MD" '(never the CTO)' '(or the CTO)' > "$M/m57.md"
mrow "M57 the CTO may record the render" "$M/m57.md" render-not-cto
para_awk sub "$GO_MD" '`valid` is deleted' '`valid` is kept' > "$M/m58.md"
mrow "M58 an invalid record is kept" "$M/m58.md" invalid-record-deleted
para_awk sub "$GO_MD" 're-runs `verify` immediately before every delegated act' 'runs `verify` once at the start' > "$M/m59.md"
mrow "M59 verify runs once at the start" "$M/m59.md" verify-before-each-act
para_awk sub "$GO_MD" 'is not a delegated act' 'is a delegated act' > "$M/m60.md"
mrow "M60 ship's auto-merge arming becomes a delegated act" "$M/m60.md" ship-arming-not-delegated
para_awk sub "$GO_MD" 'leaves every hold standing' 'discharges every hold' > "$M/m61.md"
mrow "M61 a stalled delegation discharges every hold" "$M/m61.md" stall-holds-stand
para_awk sub "$GO_MD" 'its holds still stand' 'its holds are discharged' > "$M/m62.md"
mrow "M62 a paraphrased handoff discharges its holds" "$M/m62.md" paraphrase-holds-stand
para_awk sub "$GO_MD" 'disarm every auto-merge' 'leave it armed: every auto-merge' > "$M/m63.md"
mrow "M63 the stop sequence leaves the auto-merge armed" "$M/m63.md" disarm-auto-merge
para_awk sub "$GO_MD" 'never call AskUserQuestion' 'always call AskUserQuestion' > "$M/m64.md"
mrow "M64 a technical hold always asks the operator" "$M/m64.md" no-askuserquestion-for-technical-hold
para_awk sub "$GO_MD" 'No delegation exists, so every production act stays a hold' 'A delegation is assumed, so every production act is delegable' > "$M/m65.md"
mrow "M65 a headless run assumes a delegation" "$M/m65.md" headless-no-delegation
para_awk sub "$GO_MD" '30 days at most' '30 days at least' > "$M/m66.md"
mrow "M66 the expiry bound becomes a minimum" "$M/m66.md" expiry-30-days-at-most
para_awk sub "$GO_MD" 'asks once unless a recorded No' 'never asks' > "$M/m67.md"
mrow "M67 a later attached session never asks" "$M/m67.md" later-session-asks-once
para_awk sub "$GO_MD" 'never in an archived folder' 'in an archived folder' > "$M/m68.md"
mrow "M68 the envelope file may live in an archived folder" "$M/m68.md" envelope-not-archived
para_awk sub "$GO_MD" 'without `.pull_request`' 'with `.pull_request`' > "$M/m69.md"
mrow "M69 the dedupe recipe keeps only pull requests" "$M/m69.md" headless-dedupe-recipe
para_awk sub "$GO_MD" 'whose `.author_association` is OWNER or MEMBER' 'whose `.author_association` is any value' > "$M/m70.md"
mrow "M70 the dedupe recipe matches any author" "$M/m70.md" headless-dedupe-recipe
para_awk sub "$GO_MD" 'labels=action-required' 'labels=bug' > "$M/m71.md"
mrow "M71 the dedupe recipe queries the wrong label" "$M/m71.md" headless-dedupe-recipe
para_awk sub "$GO_MD" 'the issue body ends with' 'the issue body starts with' > "$M/m72.md"
mrow "M72 the reply line is no longer the last line" "$M/m72.md" headless-issue-reply-line
para_awk sub "$GO_MD" 'that No ends when the Scope or the expiry changes' 'that No never ends' > "$M/m73.md"
mrow "M73 a recorded No never ends" "$M/m73.md" no-ends-on-scope-change
para_awk sub "$GO_MD" 'records that No as a comment' 'does not record that No as a comment' > "$M/m74.md"
mrow "M74 the attached No is not recorded" "$M/m74.md" attached-no-recorded
para_awk sub "$GO_MD" 'is surfaced again by the next attached session' 'is left unread' > "$M/m75.md"
mrow "M75 a standing headless issue is left unread" "$M/m75.md" standing-issue-resurfaced
# N14: with base == HEAD the anchor is SKIPPED (printed reason) and a changed file is still caught against it
ck
_o="$(evaluate "$M/m1.md" "$HEAD_SHA" skip)"; _r=$?
[[ "$_o" != *block-hash-differs* ]] && ok "N14 anchor skip mode does not evaluate the merge-base comparison" || bad "N14 skip mode still ran the anchor: ${_o//$'\n'/ }"
row "N14b against HEAD as base a changed block is still RED (the rows stay meaningful after merge)" "$M/m1.md" "$HEAD_SHA" block-hash-differs; nrows=$((nrows + 1))

# S1..S4: the ship wiring rows (each removes one element)
shiprow() { # <label> <mutated ship SKILL.md> <expected token>
  local out rc; out="$(evaluate_ship "$2")"; rc=$?; ck
  [[ "$rc" -ne 0 ]] && grep -Fxq -- "V:$3" <<<"$out" && ok "$1: RED for '$3'" || bad "$1: expected RED for '$3', got rc=$rc ${out//$'\n'/ }"
}
awk '/^Before Phase 6.45 archives the plan and rulings file, run/ { next } { print }' "$SHIP_MD" > "$M/s0.md"
{ cat "$M/s0.md"; grep -F -m1 'Before Phase 6.45 archives the plan and rulings file, run' "$SHIP_MD"; } > "$M/s1.md"
shiprow "S1 the merge-mode block moved to the end of the file, after the archival paragraph" "$M/s1.md" ship-block-misplaced; nrows=$((nrows + 1))
awk '{ gsub(/bash "\$\{CLAUDE_PLUGIN_ROOT\}\/skills\/ship\/scripts\/hold-gate-eval\.sh"/, "hold-gate-eval.sh"); print }' "$SHIP_MD" > "$M/s2.md"
shiprow "S2 the full hold-evaluator invocation dropped everywhere" "$M/s2.md" ship-invocation-missing; nrows=$((nrows + 1))
sed 's/124, 127, 137/124/' "$SHIP_MD" > "$M/s3.md"
shiprow "S3 step 5 no longer names the odd exit statuses" "$M/s3.md" ship-exit-status; nrows=$((nrows + 1))
sed 's/start of Phase 6.45, before the plan is archived/arming/' "$SHIP_MD" > "$M/s4.md"
shiprow "S4 step 5 says the second look is at arming" "$M/s4.md" ship-second-look-wording; nrows=$((nrows + 1))
{ cat "$SHIP_MD"; printf '\nBefore the `merge-main` lock block, run x\n'; } > "$M/s5.md"
shiprow "S5 the old lock-block copy returns" "$M/s5.md" ship-old-block; nrows=$((nrows + 1))

# H1 the base ref is unresolvable: a FAIL, never a skip
row "H1 unresolvable base ref" "$GO_MD" "refs/does-not-exist" base-unresolvable; nrows=$((nrows + 1))

# H2 must-PASS: a whitespace-only change OUTSIDE the block (the Sharp Edges list, after the block)
awk -v e="$BLOCK_END" '
  index($0, e) { seen = 1 }
  seen && !done && /^- \*\*A technical ruling is never/ { $0 = $0 "  "; done = 1 }
  { print }
  END { print "" }' "$GO_MD" > "$M/h2.md"
row "H2 whitespace-only change outside the block" "$M/h2.md" "$BASE_REF" none; nrows=$((nrows + 1))

# H3 must-PASS on a file that is NOT the canonical one: a pinned phrase re-cased where the check is case-insensitive
# (`ask once` -> `Ask once`); a guard that rejects every changed file is caught here.
para_awk sub "$GO_MD" 'ask once' 'Ask once' > "$M/h3.md"
row "H3 a re-cased ask-once phrase stays green" "$M/h3.md" "$BASE_REF" none; nrows=$((nrows + 1))

# H4 the rows prove the CHECK, not just the mutation: remove one new emit from a copy of THIS script (the list-source
# check, which M26 grades) and require the copy to go RED on that row. The copy skips this row (GOHOLD_NESTED).
nrows=$((nrows + 1)); ck
if [[ -n "${GOHOLD_NESTED:-}" ]]; then
  skip "H4 nested copy: the harness row is not recursed"
else
  _self="${BASH_SOURCE[0]}"; _nest="$M/nested.test.sh"
  sed -e "s|^ROOT=.*|ROOT=\"$ROOT\"|" -e '/|| emit list-source$/d' "$_self" > "$_nest"
  GOHOLD_NESTED=1 bash "$_nest" </dev/null >"$M/nested.out" 2>"$M/nested.err"; _nrc=$?
  if [[ "$(grep -c '|| emit list-source$' "$_self" || true)" -eq 1 && "$(grep -c '|| emit list-source$' "$_nest" || true)" -eq 0 ]] \
     && [[ "$_nrc" -ne 0 ]] && grep -Fq "M26 delete the list-source bullet: expected RED for 'list-source'" "$M/nested.err"; then
    ok "H4 removing the list-source emit from evaluate() turns M26 RED (the row grades the check)"
  else bad "H4 removing the list-source emit did not turn M26 RED (nested rc=$_nrc, emit lines in copy: $(grep -c '|| emit list-source$' "$_nest" || true))"; fi
fi

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
EXPECTED_ASSERTIONS=$(( nprops + 1 + 1 + 1 + 3 + nrows + 1 + 6 ))
ABSOLUTE_FLOOR=204
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
