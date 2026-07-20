#!/usr/bin/env bash
# Guard: every restatement of the AGENTS rule-budget contract must agree with
# the authority.
#
# Two contracts are enforced here.
#
# 1. Rule-count sentinel. The `<!-- rule-threshold: N -->` sentinel in
#    AGENTS*.md (`cq-agents-md-why-single-line`) and in
#    plugins/soleur/skills/compound/SKILL.md step 8 encode the same number.
#    Extraction uses the grep-stable sentinel comment, NOT the prose around it,
#    so a reword ("more than N rules" -> "when rule count exceeds N") leaves the
#    sentinel intact. Source rule: PR #2754, issue #2686.
#
# 2. Always-loaded byte budget. scripts/lint-agents-rule-budget.py is the SINGLE
#    SOURCE OF TRUTH for B_ALWAYS_WARN / B_ALWAYS_REJECT / PER_RULE_CAP. Every
#    other file that restates one of those numbers is listed in SITES below and
#    asserted against it.
#
#    Why this exists: commit d475c4e46 raised B_ALWAYS_REJECT 22000 -> 23000 and
#    swept only the linter, its test, and deepen-plan/SKILL.md. Five other
#    artifacts kept the old value for months -- including a live cron whose
#    post-apply gate then reverted every agents-core promotion it applied. That
#    is issue #6461. A constant duplicated across four languages with nothing
#    asserting agreement will drift; this loop is what makes the drift loud.
#
#    UNIT (load-bearing -- do not drop from the diagnostics): the linter's
#    thresholds are defined over FRONTMATTER-STRIPPED bytes. Some consumers
#    measure RAW file length instead, which currently runs ~73 B higher. This
#    guard asserts CONSTANT equality, not MEASUREMENT-BASIS equality, so the
#    diagnostics name the unit explicitly. A green guard that stays silent about
#    the unit would quietly certify a comparison performed in the wrong basis --
#    worse than no guard, because it retires the suspicion that would catch it.
#
# Symbol-anchored, never line-anchored, per `cq-cite-content-anchor-not-line-number`.
#
# NOT `set -e`: this guard accumulates every mismatch and reports them together.
# Exiting on the first one hides the rest, which is precisely how #6461 stayed
# invisible across five sites.
set -uo pipefail

# Tests point this at a throwaway fixture tree; production resolves from the
# repo root because lefthook and test-all.sh invoke from different CWDs and the
# guard now reads across the apps/web-platform package boundary.
ROOT="${LINT_AGENTS_SYNC_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

ERRORS=()
err() { ERRORS+=("$1"); }

LINTER_REL="scripts/lint-agents-rule-budget.py"

# Extract the first capture group of $2 from file $1. Prints nothing when the
# file is absent or the pattern does not match -- callers MUST treat empty as a
# hard failure (fail-closed), never as "no drift".
#
# Two-step on purpose. The obvious one-liner
#     sed -nE "s@.*${re}.*@\1@p"
# is WRONG: POSIX ERE has no lazy quantifier, so the leading `.*` is greedy and
# eats all but the last character of the capture -- `20000 warn` yields `0`.
# That failure is quiet and plausible (a number comes out, just the wrong one),
# so it reads as drift rather than as a broken guard.
# Instead: isolate the matching substring with `grep -oE`, then re-apply the
# same pattern ANCHORED at both ends, where no unbounded `.*` exists.
#
# No pipes anywhere: `sed | head -1` can exit 141 (SIGPIPE) under pipefail when
# head closes the pipe early, silently corrupting the result.
#
# Patterns must not contain `@` (the sed delimiter). None currently do.
extract_one() {
  local file="$1" re="$2" matches match bare val
  [[ -f "$file" ]] || return 1
  matches=$(grep -oE -- "$re" "$file" 2>/dev/null) || true
  match="${matches%%$'\n'*}"
  [[ -n "$match" ]] || return 0
  bare="${re#^}"; bare="${bare%\$}"
  val=$(sed -nE "s@^${bare}\$@\1@p" <<<"$match")
  printf '%s' "${val%%$'\n'*}"
}

# -----------------------------------------------------------------------------
# Contract 1: rule-count sentinel
# -----------------------------------------------------------------------------
COMPOUND_REL="plugins/soleur/skills/compound/SKILL.md"
COMPOUND_ABS="$ROOT/$COMPOUND_REL"

# Post-#3493 sidecar split: the sentinel lives in AGENTS.docs.md, not AGENTS.md.
# Search the whole registry so this stays location-tolerant.
AGENTS_THRESHOLD=""
for f in "$ROOT"/AGENTS*.md; do
  [[ -f "$f" ]] || continue
  v=$(extract_one "$f" 'rule-threshold: ([0-9]+)') || true
  if [[ -n "$v" ]]; then AGENTS_THRESHOLD="$v"; break; fi
done

COMPOUND_THRESHOLD=""
if [[ -f "$COMPOUND_ABS" ]]; then
  COMPOUND_THRESHOLD=$(extract_one "$COMPOUND_ABS" 'rule-threshold: ([0-9]+)') || true
else
  err "missing file: $COMPOUND_REL (cannot check the rule-threshold sentinel)"
fi

if [[ -z "$AGENTS_THRESHOLD" || -z "$COMPOUND_THRESHOLD" ]]; then
  err "rule-threshold sentinel: no match in one or both files (AGENTS*.md='${AGENTS_THRESHOLD:-}', $COMPOUND_REL='${COMPOUND_THRESHOLD:-}')"
elif [[ "$AGENTS_THRESHOLD" != "$COMPOUND_THRESHOLD" ]]; then
  err "rule-threshold sentinel out of sync: AGENTS*.md=$AGENTS_THRESHOLD but $COMPOUND_REL=$COMPOUND_THRESHOLD"
fi

# -----------------------------------------------------------------------------
# Contract 2: always-loaded byte budget
# -----------------------------------------------------------------------------
LINTER_ABS="$ROOT/$LINTER_REL"
EXPECT_WARN=""; EXPECT_REJECT=""; EXPECT_CAP=""

if [[ ! -f "$LINTER_ABS" ]]; then
  err "missing file: $LINTER_REL (the byte-budget authority) -- cannot verify any consumer"
else
  EXPECT_WARN=$(extract_one   "$LINTER_ABS" '^B_ALWAYS_WARN = ([0-9]+)')   || true
  EXPECT_REJECT=$(extract_one "$LINTER_ABS" '^B_ALWAYS_REJECT = ([0-9]+)') || true
  EXPECT_CAP=$(extract_one    "$LINTER_ABS" '^PER_RULE_CAP = ([0-9]+)')    || true
  for pair in "B_ALWAYS_WARN:$EXPECT_WARN" "B_ALWAYS_REJECT:$EXPECT_REJECT" "PER_RULE_CAP:$EXPECT_CAP"; do
    if [[ -z "${pair#*:}" ]]; then
      err "authority $LINTER_REL: no match for ${pair%%:*} -- extraction is vacuous, refusing to pass"
    fi
  done
fi

# site-spec: <file>|<extract-regex-with-one-capture-group>|<authority-symbol>
# Adding a future restatement site is one line here -- no new function, no new
# test, no new AC.
SITES=(
  "apps/web-platform/server/inngest/functions/cron-compound-promote.ts|^const MAX_ALWAYS_LOADED_BYTES = ([0-9]+);|REJECT"
  "apps/web-platform/server/inngest/functions/cron-compound-promote.ts|^const PROPOSE_ALWAYS_LOADED_BUDGET = ([0-9]+);|WARN"
  "scripts/compound-promote.sh|^ALWAYS_LOADED_CAP=([0-9]+)|REJECT"
  "scripts/compound-promote.sh|^PROPOSE_ALWAYS_LOADED_BUDGET=([0-9]+)|WARN"
  "AGENTS.docs.md|([0-9]+) warn|WARN"
  "AGENTS.docs.md|([0-9]+) critical|REJECT"
  "AGENTS.docs.md|cap at ~([0-9]+) bytes|PER_RULE_CAP"
  "plugins/soleur/skills/plan/SKILL.md|([0-9]+)-byte critical cap|REJECT"
  "plugins/soleur/skills/plan/SKILL.md|per-rule ([0-9]+)-byte cap|PER_RULE_CAP"
  "plugins/soleur/skills/compound/SKILL.md|cap per-rule length at ~([0-9]+)|PER_RULE_CAP"
)

UNIT_NOTE="thresholds are defined over frontmatter-stripped bytes; some consumers measure raw file length (~73 B higher)"

if [[ -n "$EXPECT_WARN" && -n "$EXPECT_REJECT" && -n "$EXPECT_CAP" ]]; then
  for spec in "${SITES[@]}"; do
    rel="${spec%%|*}"; rest="${spec#*|}"
    re="${rest%|*}"; symbol="${rest##*|}"
    abs="$ROOT/$rel"

    case "$symbol" in
      WARN)          expected="$EXPECT_WARN"   ; sym_name="B_ALWAYS_WARN"   ;;
      REJECT)        expected="$EXPECT_REJECT" ; sym_name="B_ALWAYS_REJECT" ;;
      PER_RULE_CAP)  expected="$EXPECT_CAP"    ; sym_name="PER_RULE_CAP"    ;;
      *) err "internal: unknown authority symbol '$symbol' for $rel"; continue ;;
    esac

    if [[ ! -f "$abs" ]]; then
      err "missing file: $rel (expected to restate $sym_name=$expected) -- renamed or deleted?"
      continue
    fi

    found=$(extract_one "$abs" "$re") || true
    if [[ -z "$found" ]]; then
      err "$rel: no match for /$re/ (expected $sym_name=$expected) -- extraction is vacuous, refusing to pass"
    elif [[ "$found" != "$expected" ]]; then
      err "$rel: expected $sym_name=$expected but found $found [unit: $UNIT_NOTE]"
    fi
  done
fi

# -----------------------------------------------------------------------------
# Contract 2b: the originating file must not exit the sync graph (FR4b).
#
# Once step 8 stops restating literals, one-time PR-time greps are snapshots,
# not invariants -- nothing would stop a future agent re-adding threshold prose
# or deleting the invocation, which is exactly how #6461 happened. These two
# assertions make it a standing invariant.
# -----------------------------------------------------------------------------
if [[ -f "$COMPOUND_ABS" ]]; then
  # (i) The linter invocation must survive, INCLUDING the 2>&1. Without the
  #     redirect the WARN tier prints nothing to stdout and exits 0, so an agent
  #     following step 8 sees no signal at all.
  if ! grep -qE 'lint-agents-rule-budget\.py' "$COMPOUND_ABS"; then
    err "$COMPOUND_REL: step 8 no longer invokes $LINTER_REL -- the rubric must run the authority, not restate it"
  elif ! grep -qE '2>&1' "$COMPOUND_ABS"; then
    err "$COMPOUND_REL: the linter invocation lost its '2>&1' -- [WARN]/[REJECT] go to stderr, so stdout alone is empty in the tier this repo usually occupies"
  fi

  # (ii) No threshold literal in step 8's tier-decision region. Region-scoped,
  #      NOT whole-file: the retained emit_incident snippet legitimately
  #      contains "~600 bytes", and a whole-file negative would false-fail a
  #      correct implementation.
  #      The pattern covers prose forms (22k, 21,949), not just bare digits --
  #      a digit-only pattern passes while the file is still wrong.
  region=$(awk '/^8\. \*\*Rule budget count\.\*\*/,/^   B_TOTAL is informational only/' "$COMPOUND_ABS")
  if [[ -z "$region" ]]; then
    err "$COMPOUND_REL: could not locate step 8's tier-decision region -- the anchor moved; fix this guard rather than dropping the check"
  else
    hits=$(printf '%s\n' "$region" | grep -nE '(18|20|22|23)000|\b(18|20|22|23)k\b|\b2[0-9],[0-9]{3}\b' || true)
    if [[ -n "$hits" ]]; then
      err "$COMPOUND_REL: step 8's tier-decision region restates a threshold literal -- delegate to $LINTER_REL instead. Offending: ${hits//$'\n'/ | }"
    fi
  fi
fi

# -----------------------------------------------------------------------------
# Report
# -----------------------------------------------------------------------------
if (( ${#ERRORS[@]} > 0 )); then
  echo "lint-agents-compound-sync: ${#ERRORS[@]} problem(s)" >&2
  for e in "${ERRORS[@]}"; do
    echo "  - $e" >&2
  done
  echo "" >&2
  echo "  Authority: $LINTER_REL (B_ALWAYS_WARN / B_ALWAYS_REJECT / PER_RULE_CAP)." >&2
  echo "  Fix the consumer to match the authority -- do not edit one side alone." >&2
  exit 1
fi

echo "lint-agents-compound-sync: OK (rule-threshold=$AGENTS_THRESHOLD, warn=$EXPECT_WARN, reject=$EXPECT_REJECT, per-rule-cap=$EXPECT_CAP, ${#SITES[@]} sites)"
exit 0
