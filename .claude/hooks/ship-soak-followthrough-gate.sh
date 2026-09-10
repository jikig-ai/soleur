#!/usr/bin/env bash
# PreToolUse(Bash) hook: blocks `gh pr ready` and `gh pr merge --auto` when the
# PR (or its linked plan/spec) declares a post-deploy SOAK close-criterion for a
# tracker issue that is NOT enrolled in the follow-through sweeper.
#
# Mechanical twin of ship/SKILL.md §"Soak-Gated Follow-Through Enrollment Gate"
# (wg-pm-class-followthrough-for-operator-dogfood). Closes the bypass class where
# the agent skips /ship Phase 5.5 and goes straight to `gh pr ready`/`--auto`.
#
# Why: 2026-06-29 shipped TWO soak-gated closures in PROSE with no sweeper
# enrollment (PR #5675/#5689, PR #5671/#5673). Phase 7 Step 3.5's ⏳-only scan
# never fired and both trackers were left to rot open on human memory.
#
# Contract-inherited PreToolUse(Bash) input shape (sibling-hook parity):
#   .tool_input.command (string), .cwd (string)
#
# Fail-open conditions (exit 0 silently):
#   - input lacks .cwd or path is not an absolute existing directory
#   - command is not `gh pr ready` / `gh pr merge --auto`
#   - cannot read PR body (no PR yet / gh unauthenticated)
#   - PR body has no soak signal
#   - operator-attestation override present
#   - a referenced tracker cannot be resolved (gh error) — the SKILL gate +
#     agent remain the backstop for the ambiguous case
#
# Fail-closed condition (deny + emit_incident):
#   - a soak signal is present AND >=1 referenced OPEN tracker is definitively
#     NOT enrolled (missing follow-through label, directive, or on-disk script)

set -eo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh" 2>/dev/null || true

# shellcheck source=lib/hook-input.sh
# FAIL-HARD (no `|| true`): a fail-soft source leaves hook_parse_input
# undefined, the hook dies at the call under `set -e`, prints nothing, exits
# non-zero, and the tool proceeds — defect 2 of #7164, reintroduced one line
# above where every test points.
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"

# The source above is fail-hard, but 12 of the 20 hooks run `set -uo pipefail`
# WITHOUT -e. There a missing helper makes hook_parse_input return 127, `!`
# inverts that to true, the response functions are 127 too, and the hook reaches
# `exit 0` — a clean pass-through with no row and no prompt, which is defect 2
# reintroduced by a broken deploy. Assert it explicitly instead of relying on -e.
if ! declare -f hook_parse_input >/dev/null 2>&1; then
  echo "[ship-soak-followthrough-gate] hook-input helper missing — guards did NOT run for this call" >&2
  exit 0
fi

INPUT=$(cat)
# Parse hook stdin WITHOUT shell evaluation (ADR-156: stdin is
# model-controlled and untrusted). A non-string field is surfaced, never
# coerced — coercion closes the RCE and leaves the guards evaded (#7164).
# ADR-157: a hook that cannot fully parse its input asks. The exit lives
# HERE, at the call site, not inside the library.
if ! hook_parse_input "$INPUT"; then
  hook_input_report "ship-soak-followthrough-gate"
  hook_input_should_ask && { hook_input_emit_ask "ship-soak-followthrough-gate"; exit 0; }
  exit 0
fi
CMD="$HOOK_CMD"
WORK_DIR="$HOOK_CWD"
: "${CMD:=}"
: "${WORK_DIR:=}"

# Match `gh pr ready` or `gh pr merge ... --auto` (incl. chained forms). Scan
# with commit bodies/heredocs stripped so a commit message documenting the
# command is not mistaken for one (#5192). Soft-source guard per sibling hook.
if command -v strip_command_bodies >/dev/null 2>&1; then
  SCAN=$(strip_command_bodies "$CMD")
else
  SCAN="$CMD"
fi
if ! grep -qE '(^|&&|\|\||;)\s*gh\s+pr\s+(ready|merge\s+.*--auto)(\s|$|&&|\|\||;)' <<<"$SCAN"; then
  exit 0
fi

if [[ "$WORK_DIR" != /* ]] || [[ ! -d "$WORK_DIR" ]]; then
  exit 0
fi
cd "$WORK_DIR" 2>/dev/null || exit 0

# Emergency override env (CI / ultrareview / known-non-mechanizable soak).
if [[ "${SOLEUR_SKIP_SOAK_FOLLOWTHROUGH_GATE:-}" == "1" ]]; then
  exit 0
fi

# Resolve PR number from the command, else the current branch's PR.
PR_NUM=$(echo "$CMD" | grep -oE 'gh\s+pr\s+(ready|merge[^|;&]*)\s+([0-9]+)' | grep -oE '[0-9]+$' | head -1 || true)
if [[ -z "$PR_NUM" ]]; then
  PR_NUM=$(gh pr view --json number --jq .number 2>/dev/null || true)
fi
[[ -n "$PR_NUM" ]] || exit 0

PR_BODY=$(gh pr view "$PR_NUM" --json body --jq .body 2>/dev/null || true)
[[ -n "$PR_BODY" ]] || exit 0

# Operator-attestation override in the PR body (soak genuinely non-mechanizable).
if grep -q 'gate-override: soak-followthrough-enrollment' <<<"$PR_BODY"; then
  exit 0
fi

# Build the scan corpus: PR body (fenced code stripped, fail-closed on unbalanced
# fence) + any linked plan/spec read from disk.
CORPUS=$(mktemp)
trap 'rm -f "$CORPUS"' EXIT INT TERM
printf '%s' "$PR_BODY" | awk '
  /^```/ { in_fence = !in_fence; next }
  !in_fence { print }
  END { if (in_fence) exit 2 }
' > "$CORPUS" || printf '%s' "$PR_BODY" > "$CORPUS"

PLAN=$(grep -oE 'knowledge-base/project/(plans|specs)/[^[:space:])"`]+\.md' "$CORPUS" | head -1 || true)
# Same traversal confinement the PIR gate applies, for the same reason: this path
# comes from an attacker-authored PR body and this hook runs automatically on
# `gh pr ready`. Without it a symlink under plans/ pointing outside the repo is read
# into the corpus -- a forced-deny / shipping-DoS primitive. Resolve against the repo
# root, not cwd, so the verdict does not depend on where the hook was invoked from.
_soak_root="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
_soak_resolved="$(realpath -e "$_soak_root/$PLAN" 2>/dev/null || realpath -e "$PLAN" 2>/dev/null || true)"
case "$_soak_resolved" in
  "$_soak_root"/knowledge-base/project/plans/*|"$_soak_root"/knowledge-base/project/specs/*) PLAN="$_soak_resolved" ;;
  *) [[ -n "$PLAN" ]] && echo "ship-soak-followthrough-gate: SOAK-CORPUS-BODY-ONLY - cited plan does not resolve under the repo plans/specs dirs; refusing to read it" >&2 || true
     PLAN="" ;;
esac

if [[ -n "$PLAN" && -f "$PLAN" ]]; then
  # Strip fenced blocks from the PLAN TOO. The PR body is stripped a few lines
  # above precisely so a quoted example cannot be read as a live declaration, and
  # the plan was then appended RAW — so the protection stopped at the boundary
  # between two halves of one corpus. The plan half is the bigger risk of the two:
  # plans quote gate inputs, sample PR bodies and worked examples at length.
  #
  # Forcing case, from this change's own plan: a fenced excerpt reading
  # "AC9: PR body uses **`Ref #5733`** (NOT `Closes`)" put #5733 into REFS as a
  # live soak tracker, so a quoted illustration would have demanded sweeper
  # enrollment for an unrelated issue.
  #
  # Measured over all 1905 tracked plans: stripping removes at least one
  # Ref/Tracks in 8 of them (the quoted-example class), and recall over the 42
  # plans carrying a real enrollment directive is UNCHANGED at 36/42 — no real
  # soak declaration lives only inside a fence.
  #
  # Same fail-closed posture as the body: if awk cannot run, append unstripped
  # rather than dropping the plan half entirely.
  # `^[[:space:]]*` NOT `^`: 518 of 1905 tracked plans indent a fence inside a
  # list item, and a column-0-only toggle leaves those fences UNSTRIPPED -- so the
  # quoted illustration this strip exists to neutralise survives in the common
  # case. The sibling strips (ship-incident-pir-gate.sh, preflight/SKILL.md) are
  # both indent-tolerant; this one was not, 25 lines below the body strip that is.
  #
  # `END{ if (f) exit 2 }` mirrors the body strip above: an UNBALANCED fence
  # otherwise truncates the plan tail silently at rc=0, so the `|| cat` fallback
  # could never fire and a `Ref #N` past the unclosed fence vanished from REFS.
  # Measured: 1 of 1905 plans has an odd column-0 fence count.
  #
  # The fallback writes to a TEMP file, not straight onto $CORPUS: the awk above
  # has already appended its partial output, so `|| cat "$PLAN" >> "$CORPUS"`
  # appended the plan a SECOND time on failure, duplicating every ref.
  _plan_stripped=$(mktemp)
  if awk '/^[[:space:]]*```/ { f = !f; next } !f { print } END { if (f) exit 2 }' \
       "$PLAN" > "$_plan_stripped" 2>/dev/null; then
    cat "$_plan_stripped" >> "$CORPUS"
  else
    echo "ship-soak-followthrough-gate: SOAK-CORPUS-PLAN-UNSTRIPPED — '$PLAN' has an unbalanced fence or awk failed; appending it unstripped (fail-closed: the gate stays noisy rather than blind)" >&2 || true
    cat "$PLAN" >> "$CORPUS"
  fi
  rm -f "$_plan_stripped"
else
  # SAY SO WHEN HALF THE CORPUS IS EMPTY. The plan is where a soak is actually
  # declared — a PR body rarely spells one out — so when no plan path resolves,
  # every verdict below is reached from the body alone. That is a legitimate
  # state (many PRs have no plan), but it is NOT the same fact as "scanned the
  # plan and found no soak", and the two were previously indistinguishable:
  # both exited 0 in silence. Emitting the distinction costs nothing and stops a
  # half-blind pass from reading like a clean one. stderr only — this hook's
  # stdout is a permission-decision envelope and must not carry prose.
  if [[ -z "$PLAN" ]]; then
    echo "ship-soak-followthrough-gate: SOAK-CORPUS-BODY-ONLY — no knowledge-base/project/{plans,specs}/*.md path in the PR body; scanned the body alone" >&2 || true
  else
    echo "ship-soak-followthrough-gate: SOAK-CORPUS-BODY-ONLY — PR body cites '$PLAN' but it is not readable here; scanned the body alone" >&2 || true
  fi
fi

# Drop NEGATED soak vocabulary before matching.
#
# A sentence declaring that NO soak exists is not a soak declaration, and the
# gate could not tell the difference: SOAK_RE offers a bare `soak` alternative
# that matches any mention at all. The cost is not theoretical — the header
# above already records it as the cause of PR #7426's false deny ("the regex is
# negation-blind"), where the corpus matched on the plan's "Nothing soak-gated."
# That PR fixed the closing-target half beside it and left this half in place.
# It fired again on PR #7987, whose ONLY match in the whole corpus was the plan
# row asserting the section did not apply:
#   | 2.9.1 Soak follow-through | **Skip.** No acceptance criterion is
#     time-gated; nothing here closes on a soak. |
# A gate that fires on the sentence exempting it teaches its readers to reach
# for the env-var bypass, which is exactly what the header warns against.
#
# Scoped, not blanket. The negation window stops at a clause boundary
# (`.` `|` `)` `—` `–` `;` `:`) so a negation of something ELSE cannot silence a
# real declaration beside it. The case that forces this is real, from the plan
# corpus, and is pinned as `soaknegscoped` in the sibling suite:
#   - [ ] AC9: PR body uses **`Ref #5733`** (NOT `Closes`) — closure is gated
#         on the post-deploy soak below.
# Here `NOT` negates `Closes`; the sentence IS a soak declaration and survives.
#
# The unit is the LINE, deliberately not the sentence: the shape this exists to
# catch is a markdown TABLE ROW whose label and disposition sit in adjacent
# cells, and splitting on `.` also shreds ordinals like `2.9.1` into fragments
# that re-match the bare token. Measured on all 1905 tracked plans: 274 matched
# before, 207 after (67 false positives removed, 24%), with recall UNCHANGED at
# 36/42 over the plans carrying a real `soleur:followthrough script=` enrollment
# directive — zero recall regression. Re-derive rather than trust those figures.
DROPPED_CORPUS=$(mktemp)
trap 'rm -f "$CORPUS" "$DROPPED_CORPUS"' EXIT INT TERM
if awk '
      { u = tolower($0) }
      # DROP a negated-soak line ONLY when it carries no tracker reference.
      #
      # The clause-boundary window this replaced ([^.|)-;:]{0,60}) pinned exactly ONE
      # punctuation arrangement and was a LIVE MERGE-GATE BYPASS on five of the six
      # house-style spellings, all real committed corpus lines:
      #   "Ref #5733, never Closes (closure gated on the 7-day soak)."   -> dropped
      #   "Ref #N (NOT Closes - closure is post-soak)"                   -> dropped
      #   "Ref #N must **not** be closed until the soak reports green."  -> dropped
      # ( and , were absent from the class, so the window ran straight through them
      # into soak. The single fixture passed for the wrong reason: it happened to
      # contain a ). Widening the class is whack-a-mole -- natural-language negation
      # scope is not a character class.
      #
      # The reliable discriminator is the TRACKER. The sentence that triggered this
      # whole change (the 2.9.1 Soak follow-through table row, Skip / nothing here
      # closes on a soak) carries no Ref or Tracks #N, and every genuine soak-gated
      # closure carries one -- the house convention the REFS extraction below reads.
      # So the failure direction is now safe BY CONSTRUCTION: a kept ref-bearing line
      # only makes the gate check that ref enrollment.
      #
      # zero is DELIBERATELY absent from the negation list: it is also a SOAK_RE token
      # (stays? (at )?(~?0|zero)), so including it made "Zero POST-failure lines over
      # the soak window" self-negate.
      #
      # The window [^.|] is ASCII-only and byte-safe. An earlier revision put an em/en
      # dash INSIDE a bracket class, which under mawk is byte-oriented: it admitted the
      # 0xE2 lead byte and with it every U+2xxx character. The byte-safe repair that
      # followed was DEAD CODE -- a negated class already matches each dash byte -- and
      # so silently removed the em-dash boundary it meant to preserve. Both measured.
      u ~ /(^|[^a-z])(no|not|nothing|none|never|n\/a|skip|skipped|without)[^a-z][^.|]{0,60}soak/ && u !~ /(ref|tracks)[[:space:]]*#[0-9]+/ { next }
      u ~ /soak[^.|]{0,40}(: *(skip|none)|not applicable|n\/a|does not apply)/ && u !~ /(ref|tracks)[[:space:]]*#[0-9]+/ { next }
      { print }
    ' "$CORPUS" > "$DROPPED_CORPUS" 2>/dev/null; then
  # awk RAN. Its output is authoritative even when EMPTY -- an all-negation corpus
  # legitimately strips to nothing. The earlier `[[ -s "$DROPPED_CORPUS" ]]`
  # conjunct conflated "awk broke" with "awk correctly removed every line" and so
  # rescanned the UNFILTERED corpus for a body whose every soak mention was
  # negated, reinstating the exact PR #7987 false deny this strip removes --
  # under a message that blamed awk. Measured on
  # "No soak-gated status flip. Ref #9999 tracks the residue."
  cp "$DROPPED_CORPUS" "$CORPUS"
else
  # Fail TOWARD the gate: an awk that could not run leaves the corpus unfiltered,
  # so the gate stays as noisy as it was rather than silently passing everything.
  echo "ship-soak-followthrough-gate: SOAK-NEGATION-STRIP-FAILED — awk exited non-zero; scanning the unfiltered corpus" >&2 || true
fi

# Soak signal — MUST stay byte-identical to ship/SKILL.md §Detection SOAK_RE.
SOAK_RE='soak|stays? (at )?(~?0|zero)|[0-9]+[- ]day[s]?( post-deploy| soak)|post-deploy (soak|verif|observ)|adopting[[:space:]]*(→|->|to)[[:space:]]*accepted|status[[:space:]]+flip'
if ! LC_ALL=C.UTF-8 grep -qiE "$SOAK_RE" "$CORPUS" 2>/dev/null && ! grep -qiE "$SOAK_RE" "$CORPUS" 2>/dev/null; then
  exit 0
fi

# Extract referenced trackers and verify sweeper enrollment.
#
# `Ref` / `Tracks` ONLY — deliberately NOT `Closes` / `Fixes`. An issue the PR CLOSES is the
# work item, not a soak tracker: it stops existing at merge, so "enrol it in the sweeper" is
# both unsatisfiable and meaningless (the sweeper skips non-OPEN issues, and the issue is OPEN
# only until the squash lands). Including the closing keywords made every PR that closes an
# issue AND declares a soak unshippable — the gate demanded enrollment for the one issue that
# can never need it, while the genuine soak trackers beside it were correctly enrolled.
#
# The deadlock this produced is the reason it is fixed rather than overridden: documented
# escape (c) is "add <!-- gate-override: … --> to the PR body", but adding it requires
# `gh pr edit`, and an agent naturally chains that with `gh pr ready` — which this hook's own
# matcher then denies as a single tool call, taking the edit down with it. So the escape is
# reachable only by knowing to issue the edit in isolation. A gate whose documented escape is
# that easy to miss trains its readers to reach for the env-var bypass instead.
#
# **Why:** #7278 / PR #7343 — flagged #7278 (the PR's own `Closes` target) while #7339 and
# #7340, the actual soak trackers, carried label + directive + committed probe.
# `|| true` because ZERO refs is a NORMAL answer, not an error: a PR that declares a soak but
# cites no tracker must reach the loop below (which then finds nothing to check) rather than
# die here. grep exits 1 on no-match, and under `set -e` that would abort the hook mid-gate —
# a gate that crashes is indistinguishable from one that passed. Caught by
# scripts/lint-shell-capture-exit.py once the edit above moved this line off its baselined entry.
REFS=$(grep -oiE '(Ref|Tracks)[[:space:]]+#[0-9]+' "$CORPUS" | grep -oE '[0-9]+' | sort -u || true)

# The exclusion above is reasoned at ISSUE level ("an issue the PR CLOSES is the work item")
# but was implemented at MENTION level: it asks which keyword introduced each `#N`, so the
# carve-out survives only while every mention of the closing target uses a closing keyword.
# One `Ref #N` anywhere in the corpus re-adds the PR's own target and restores the exact
# deadlock #7278 fixed — and the corpus includes the whole linked plan, which is prose written
# for humans, not keyword-disciplined input.
#
# Whether #N needs a soak tracker is a property of the ISSUE, not of one sentence about it:
# if the merge closes it, it stops existing and cannot be swept, however it is spelled
# elsewhere. So drop closing targets from REFS after extraction.
#
# Read closing keywords from PR_BODY only, never the plan — GitHub auto-closes on the PR body
# alone, so a plan that merely discusses "Closes #N" must not shrink this gate's scope.
#
# **Why:** PR #7426 — flagged its own `Closes #7409` target. The corpus matched SOAK_RE on the
# plan's sentence "Nothing soak-gated." (the regex is negation-blind) and drew `Ref #7409` from
# a rejected counterfactual: "If split, #7409 must stay OPEN … the move-only PR must use
# `Ref #7409`" — describing a two-PR split the plan had explicitly decided against. Both
# matches came from prose asserting the opposite of what the gate concluded.
CLOSES=$(printf '%s' "$PR_BODY" \
  | grep -oiE '(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]+#[0-9]+' \
  | grep -oE '[0-9]+' | sort -u || true)
if [[ -n "$CLOSES" ]]; then
  REFS=$(printf '%s\n' $REFS | grep -vxF -f <(printf '%s\n' $CLOSES) || true)
fi

UNENROLLED=()
for n in $REFS; do
  state=$(gh issue view "$n" --json state --jq .state 2>/dev/null || echo "")
  [[ "$state" == "OPEN" ]] || continue   # closed/absent trackers need no enrollment
  labels=$(gh issue view "$n" --json labels --jq '[.labels[].name]|join(",")' 2>/dev/null || echo "__ERR__")
  body=$(gh issue view "$n" --json body --jq .body 2>/dev/null || echo "__ERR__")
  # Fail-open on a gh error for this tracker (cannot prove non-enrollment).
  [[ "$labels" == "__ERR__" || "$body" == "__ERR__" ]] && continue
  enrolled=0
  if [[ ",$labels," == *",follow-through,"* ]] \
     && grep -q '<!-- soleur:followthrough' <<<"$body" \
     && grep -qE 'earliest=' <<<"$body"; then
    spath=$(printf '%s' "$body" | grep -oE 'script=scripts/followthroughs/[^[:space:]]+\.sh' | head -1 | sed 's/^script=//')
    [[ -n "$spath" && -f "$spath" ]] && enrolled=1
  fi
  [[ "$enrolled" == 1 ]] || UNENROLLED+=("$n")
done

if [[ ${#UNENROLLED[@]} -eq 0 ]]; then
  exit 0
fi

declare -f emit_incident >/dev/null && \
  emit_incident wg-pm-class-followthrough-for-operator-dogfood deny \
    "PRs adding operator-only routes, cross-origin form-POST, c" "$CMD" 2>/dev/null || true

REFLIST=$(printf '#%s ' "${UNENROLLED[@]}")
REASON="BLOCKED: PR #${PR_NUM} declares a post-deploy soak close-criterion, but referenced tracker(s) ${REFLIST}are not enrolled in the follow-through sweeper.

Each soak-gated tracker MUST carry: the 'follow-through' label + a '<!-- soleur:followthrough script=scripts/followthroughs/<x>.sh earliest=<deploy+Nd> secrets=... -->' directive + a committed scripts/followthroughs/<x>.sh probe (exit 0 when the soak holds).

Resolve via one of:
  (a) Enroll now — scaffold from plugins/soleur/skills/ship/references/followthrough-stub-template.sh (Sentry-rate soaks: mirror scripts/followthroughs/reconcile-ff-only-sentry-4977.sh), label + add the directive to each tracker, land the script, then re-issue.
  (b) Cite an existing enrollment PR/issue and add the directive.
  (c) Override (non-mechanizable soak): add '<!-- gate-override: soak-followthrough-enrollment -->' + a one-line justification to the PR body, or run with SOLEUR_SKIP_SOAK_FOLLOWTHROUGH_GATE=1.

See knowledge-base/engineering/operations/runbooks/followthrough-convention.md and ship/SKILL.md §Soak-Gated Follow-Through Enrollment Gate."

jq -n --arg r "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
exit 0
