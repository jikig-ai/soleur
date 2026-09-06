#!/usr/bin/env bash
# pr5-anchor-integrity.test.sh — the anchors PR5 (#7640) cites must RESOLVE.
#
# WHY THIS EXISTS, AND WHY IT IS NOT "JUST BE CAREFUL"
#
# During PR5's own review the rollback citation in deploy-docs.yml pointed at a
# non-existent heading TWICE:
#   1. it cited `### Rollback content freeze`, a section the SAME commit deleted;
#   2. the repair cited `### PR5 NARROWED THE ROLLBACK: it is three acts now,
#      not one`, and two edits later that heading was renamed.
# Both are cq-cite-content-anchor-not-line-number failing inside one PR, and
# both were invisible to actionlint, to the markdown, and to every other suite.
# A citation is only worth what verifies it, so it is verified here.
#
# It also pins the ACT-COUNT discipline. The rollback is three acts, or FOUR
# when the custom-domain attachment is still routing after the DNS revert
# (runbook `### Procedure` step 3). A bare "three" shipped in three artifacts at
# once during review, which read as corroborated rather than as one mistake
# copied. Every mention must carry the conditional.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

RUNBOOK="$REPO_ROOT/knowledge-base/engineering/operations/runbooks/cloudflare-pages-cutover.md"
WORKFLOW="$REPO_ROOT/.github/workflows/deploy-docs.yml"
MODEL="$REPO_ROOT/knowledge-base/engineering/architecture/diagrams/model.c4"

passes=0
fails=0
asserted=0
pass() { asserted=$((asserted + 1)); passes=$((passes + 1)); printf '  PASS: %s\n' "$1"; }
fail() { asserted=$((asserted + 1)); fails=$((fails + 1));  printf '  FAIL: %s\n' "$1"; }

# INSTRUMENT SELF-TEST (ADR-193): drive both arms once and refuse to continue
# unless BOTH counters moved. A suite whose fail() has been neutered reports a
# clean run while asserting nothing, and an assertion-count floor alone cannot
# see it (the floor sums both buckets).
_p0=$passes; _f0=$fails
pass "instrument self-test: the PASS arm records (EXPECTED)"
fail "instrument self-test: the FAIL arm records (EXPECTED — subtracted below)"
if [[ "$passes" -ne $((_p0 + 1)) || "$fails" -ne $((_f0 + 1)) ]]; then
  printf 'FATAL: instrument self-test did not move both counters (pass %d->%d, fail %d->%d)\n' \
    "$_p0" "$passes" "$_f0" "$fails" >&2
  exit 2
fi
fails=$((fails - 1))   # subtract the deliberate FAIL; the PASS is left in the floor

for f in "$RUNBOOK" "$WORKFLOW" "$MODEL"; do
  [[ -r "$f" ]] || { printf 'FATAL: unreadable: %s\n' "$f" >&2; exit 2; }
done

# --- 1. Every runbook heading deploy-docs.yml cites must exist, verbatim. ---
# Anchors are extracted from the workflow rather than restated here: restating
# them would pin this test to a copy and let the real citation drift alone.
# Compare LIKE FOR LIKE: the extractor strips backticks from the citation, so
# the haystack must be backtick-stripped too. Without this the guard reds on a
# citation that is perfectly correct and merely quoted — which is a false
# positive in the direction that trains a reader to ignore it.
RUNBOOK_NB="$(mktemp -t pr5-anchor-runbook.XXXXXXXX)"
trap 'rm -f "$RUNBOOK_NB"' EXIT INT TERM HUP
tr -d '`' < "$RUNBOOK" > "$RUNBOOK_NB"

# ANCHOR AT HEADING POSITION, NOT ANYWHERE IN THE FILE, AND REQUIRE EXACTLY ONE.
# A whole-file `grep -F` is satisfied by a PROSE MENTION of the heading, so
# renaming the real heading leaves the guard green while every citation dangles.
# Measured while writing this suite: the anchor occurred TWICE (heading + a
# cross-reference), and renaming the heading survived a whole-file grep. That is
# the decoy shape cq-assert-anchor-not-bare-token warns about, reproduced inside
# the guard written to prevent it. `#`-prefixed anchors are therefore matched
# line-anchored, and a count != 1 fails: 0 = dangling citation, >1 = a decoy that
# would let a future rename pass.
while IFS= read -r anchor; do
  [[ -n "$anchor" ]] || continue
  case "$anchor" in
    '#'*)
      n=$(grep -cE "^${anchor//\*/\\*}" "$RUNBOOK_NB" || true)
      if [[ "$n" -eq 1 ]]; then
        pass "cited anchor resolves to exactly one runbook HEADING: ${anchor}"
      elif [[ "$n" -eq 0 ]]; then
        fail "cited anchor resolves to NO runbook heading (dangling citation): ${anchor}"
      else
        fail "cited anchor matches ${n} runbook headings — a decoy lets a rename pass silently: ${anchor}"
      fi
      ;;
    *)
      if grep -qF -- "$anchor" "$RUNBOOK_NB"; then
        pass "deploy-docs.yml cites a runbook block that exists: ${anchor}"
      else
        fail "deploy-docs.yml cites a runbook block that does NOT exist: ${anchor}"
      fi
      ;;
  esac
done < <(grep -oE '`(###? [^`]+|READ THIS BEFORE `?### Procedure`?)`' "$WORKFLOW" \
         | tr -d '`' | grep -E '^###? |^READ THIS BEFORE' | sort -u)

# --- 2. The two load-bearing runbook anchors exist at heading position. ---
if grep -qE '^### PR5 NARROWED THE ROLLBACK' "$RUNBOOK"; then
  pass "runbook declares the PR5 rationale heading"
else
  fail "runbook is missing the '### PR5 NARROWED THE ROLLBACK' heading"
fi
if grep -qF 'READ THIS BEFORE `### Procedure`' "$RUNBOOK"; then
  pass "runbook declares the acts 0-4 preamble"
else
  fail "runbook is missing the acts 0-4 preamble"
fi

# --- 3. The preamble must precede the procedure it corrects. ---
# This is the defect the preamble exists to fix: a correction BELOW the
# procedure is not a correction. Line-number comparison is the property.
pre_ln=$(grep -nF 'READ THIS BEFORE `### Procedure`' "$RUNBOOK" | head -1 | cut -d: -f1)
proc_ln=$(grep -nE '^### Procedure' "$RUNBOOK" | head -1 | cut -d: -f1)
if [[ -n "$pre_ln" && -n "$proc_ln" && "$pre_ln" -lt "$proc_ln" ]]; then
  pass "the acts 0-4 preamble (line ${pre_ln}) precedes ### Procedure (line ${proc_ln})"
else
  fail "the acts 0-4 preamble must precede ### Procedure (preamble=${pre_ln:-absent} procedure=${proc_ln:-absent})"
fi

# --- 4. Act-count discipline: no BARE "three acts" anywhere. ---
# The conditional fourth act must accompany every mention. Matching is
# case-insensitive and scoped to the sentence, so a mention that names FOUR
# within 200 characters passes and a naked one does not.
bare=0
for f in "$RUNBOOK" "$WORKFLOW" "$MODEL"; do
  while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    if ! printf '%s' "$hit" | grep -qiE 'four|, or four|not one|rationale'; then
      fail "bare act count with no conditional-fourth qualifier in $(basename "$f"): ${hit:0:90}"
      bare=$((bare + 1))
    fi
  done < <(grep -oiE '.{0,40}three acts.{0,160}' "$f")
done
[[ "$bare" -eq 0 ]] && pass "every 'three acts' mention carries the conditional fourth (3 files scanned)"

# --- 5. ssl = "full" is act 0 and must still be present to protect. ---
# SINGLE LIMB, AND IT MUST BE THE FILE PATH. An earlier revision OR'd this with
# a search for the literal `ssl *= *"full"`, which the act-0 block satisfies with
# its own `grep` command string — the check was satisfied by the text asserting
# it. Scope to the acts block so a mention elsewhere in the runbook cannot stand
# in for the precondition being IN the rollback path.
acts_block=$(awk '/READ THIS BEFORE `### Procedure`/,/^### The merge path is the only path/' "$RUNBOOK")
if printf '%s' "$acts_block" | grep -qF 'seo-config-rules.tf'; then
  pass "the acts 0-4 block names seo-config-rules.tf as the act-0 precondition"
else
  fail "the acts 0-4 block no longer names the ssl=full precondition file (act 0)"
fi
if printf '%s' "$acts_block" | grep -qF '526'; then
  pass "the acts 0-4 block states the HTTP 526 consequence of a missing act 0"
else
  fail "the acts 0-4 block no longer states the 526 consequence"
fi

# --- 6. AC33 literal-absence, pinned here because CARE HAS ALREADY FAILED. ---
# The plan's AC33 asserts the retired environment's name does not appear in the
# workflow. During PR5 alone that assertion was broken THREE times by comments
# written to EXPLAIN the removal — the collision cq-assert-anchor-not-bare-token
# describes, where "assert X is absent" and "document X" are the same bytes. The
# evidence those comments carried (the `gh api ... deployment-branch-policies`
# command) now lives in the runbook, which has no absence constraint. Anything
# that needs to name it belongs there, not here.
if grep -q 'github-pages' "$WORKFLOW"; then
  fail "AC33: the retired environment name reappeared in deploy-docs.yml (put the prose in the runbook instead)"
else
  pass "AC33: deploy-docs.yml is free of the retired environment name"
fi
n_actions=$(grep -cE '^\s*uses: actions/(configure-pages|upload-pages-artifact|deploy-pages)@' "$WORKFLOW" || true)
if [[ "$n_actions" -eq 0 ]]; then
  pass "AC33: zero GitHub Pages publish actions remain"
else
  fail "AC33: ${n_actions} GitHub Pages publish action(s) reappeared"
fi
if grep -qE "github\.ref == 'refs/heads/main'" "$WORKFLOW"; then
  pass "the branch restriction replacing the retired environment policy is present"
else
  fail "the github.ref conjunct is gone — workflow_dispatch from any ref could publish to the apex"
fi

# --- Anti-vacuity floor. Emitted with printf + exit, NEVER through fail(),
# --- which is the helper it backstops (ADR-193).
MIN_ASSERTIONS=12
if [[ "$asserted" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FATAL: assertion floor breached: ran %d, floor %d. A pass with too few assertions is not a pass.\n' \
    "$asserted" "$MIN_ASSERTIONS" >&2
  exit 1
fi

printf '\n%d passed, %d failed (%d assertions, floor %d)\n' "$passes" "$fails" "$asserted" "$MIN_ASSERTIONS"
[[ "$fails" -eq 0 ]] || exit 1
printf 'OK\n'
