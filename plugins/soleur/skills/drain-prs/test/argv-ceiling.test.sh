#!/usr/bin/env bash
# Argv-ceiling regression for plugins/soleur/skills/drain-prs/scripts/triage-prs.sh (#6736).
#
# WHAT THIS GUARDS. $PR_JSON reaches jq via a `<<<"$PR_JSON"` herestring. A herestring is
# delivered on stdin through a pipe/tempfile and has no size limit. If it is ever converted
# to `--argjson pr_json "$PR_JSON"` the payload becomes ONE argv argument, and the kernel
# caps a SINGLE argv argument at MAX_ARG_STRLEN = 131,072 B -- bisected on this host:
# 131,071 B passes, 131,072 B fails E2BIG. That is NOT `getconf ARG_MAX` (2,097,152 B here);
# a payload at 6% of ARG_MAX still dies.
#
# WHY THIS SITE GETS THE ONLY PHASE-2.3 ASSERTION. Every other bounded site in this sweep is
# comment-only: proving a bound nobody proposed removing means synthesizing ~30x the real
# fixture to fire for one imagined mutation. This site is different -- it is not an eroding
# bound, it is ALREADY over. Measured on this repo: $PR_JSON is 392,170 B at 20 open PRs,
# 2.99 x MAX_ARG_STRLEN, today. The herestring is the only reason drain-prs runs at all.
#
# FIXTURE ADEQUACY. The fixture is SYNTHESIZED (cq-test-fixtures-synthesized-only) and
# PRODUCTION-SHAPED: each PR carries a statusCheckRollup of realistic check-run objects,
# which is where the real bytes live. Row count is NOT the load-bearing parameter, BYTES PER
# ROW is -- 200 *minimal* PRs would measure well under the ceiling and would therefore pass
# against an --argjson mutation, i.e. vacuously. The suite asserts the fixture's byte size
# exceeds MAX_ARG_STRLEN in-suite so it cannot silently degrade as jq's encoding or the
# script's --json field list changes.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../scripts/triage-prs.sh"

# Named at every use, never bare (the whole point of the sweep is that this is a per-argument
# kernel constant, not ARG_MAX and not a byte count anyone should re-derive from memory).
MAX_ARG_STRLEN=131072

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }
[[ -f "$TARGET" ]] || { echo "ERROR: target not found: $TARGET" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- Synthesized, production-shaped fixture ---------------------------------------------
# 40 PRs x ~25 check runs. Nothing here is copied from a real PR: numbers, titles, branch
# names, authors and check names are all generated.
FIXTURE="$WORK/prs.json"
PR_ROWS=40
CHECKS_PER_PR=25

jq -nc --argjson prs "$PR_ROWS" --argjson checks "$CHECKS_PER_PR" '
  [ range(0; $prs) as $i
    | { number: (4000 + $i),
        title: ("synthesized fixture pull request for argv ceiling coverage number \($i) with a realistically long subject line"),
        headRefName: ("synth/argv-ceiling-fixture-branch-with-a-long-name-\($i)"),
        isDraft: (($i % 7) == 0),
        mergeable: (if ($i % 5) == 0 then "CONFLICTING" else "MERGEABLE" end),
        reviewDecision: (if ($i % 3) == 0 then "REVIEW_REQUIRED" else "APPROVED" end),
        labels: [ {name: "synthesized-fixture"}, {name: "dependencies"} ],
        author: { login: ("synth-author-\($i % 4)") },
        createdAt: "2026-07-01T00:00:00Z",
        statusCheckRollup:
          [ range(0; $checks) as $c
            | { __typename: "CheckRun",
                name: ("synthesized-workflow-job-with-a-long-descriptive-name / matrix-shard-\($c)"),
                status: "COMPLETED",
                conclusion: (if ($c % 11) == 0 then "FAILURE" else "SUCCESS" end),
                detailsUrl: ("https://example.invalid/synth/checks/\($i)/\($c)/a-long-details-path-segment"),
                startedAt: "2026-07-01T00:00:00Z",
                completedAt: "2026-07-01T00:05:00Z" } ] } ]' > "$FIXTURE"

echo "TEST: triage-prs argv ceiling (#6736)"

# --- Generator cardinality: an under-filled generator makes everything below vacuous -----
gen_rows="$(jq 'length' "$FIXTURE")"
if [[ "$gen_rows" -eq "$PR_ROWS" ]]; then
  pass "fixture generator emitted $gen_rows PR rows (want $PR_ROWS)"
else
  fail "fixture generator emitted $gen_rows PR rows (want $PR_ROWS) -- asserts below would be vacuous"
fi

gen_checks="$(jq '[.[].statusCheckRollup | length] | unique | .[0]' "$FIXTURE")"
if [[ "$gen_checks" -eq "$CHECKS_PER_PR" ]]; then
  pass "every PR row carries $gen_checks check runs (want $CHECKS_PER_PR)"
else
  fail "check-run cardinality is $gen_checks (want $CHECKS_PER_PR) -- fixture is not production-shaped"
fi

# --- FIXTURE ADEQUACY: the payload must actually exceed the ceiling ----------------------
# Asserted IN-SUITE, not demonstrated in a PR body: a PR-body demonstration is unrunnable
# after merge, because there is no pre-fix code left to run it against.
fixture_bytes="$(wc -c < "$FIXTURE")"
if [[ "$fixture_bytes" -gt "$MAX_ARG_STRLEN" ]]; then
  pass "fixture is ${fixture_bytes} B > MAX_ARG_STRLEN (${MAX_ARG_STRLEN})"
else
  fail "fixture is only ${fixture_bytes} B -- below MAX_ARG_STRLEN (${MAX_ARG_STRLEN}), this test proves nothing"
fi

# The collapse must stay FAR under the ceiling: this is what makes `--argjson prs
# "$CLASSIFIED"` safe, and it is the reason that binding is deliberately NOT converted.
# If the projection ever starts carrying statusCheckRollup through, this catches it.
#
# TWO-SIDED on purpose. `-lt MAX_ARG_STRLEN` alone passes when the collapse is 0 B --
# which is exactly what a crashed script produces, so a one-sided bound would report
# PASS on the very mutation this suite exists to catch. The lower bound makes "the
# script produced nothing" a FAILURE rather than a suspiciously good result.
classified_bytes="$(bash "$TARGET" --fixture "$FIXTURE" --format json 2>/dev/null | jq -c '[.[][]]' | wc -c)"
if [[ "$classified_bytes" -gt 1000 && "$classified_bytes" -lt "$MAX_ARG_STRLEN" ]]; then
  pass "\$CLASSIFIED collapse is ${classified_bytes} B (>1000, < MAX_ARG_STRLEN ${MAX_ARG_STRLEN})"
elif [[ "$classified_bytes" -le 1000 ]]; then
  fail "\$CLASSIFIED is only ${classified_bytes} B for $PR_ROWS PRs -- the script produced (almost) nothing; this bound is vacuous"
else
  fail "\$CLASSIFIED is ${classified_bytes} B -- the projection no longer collapses; --argjson prs is now unsafe"
fi

# --- Behavioural: the script survives a >ceiling PR_JSON --------------------------------
# This is the assertion that goes RED when the herestring becomes --argjson: jq dies with
# E2BIG ("Argument list too long") and the command substitution yields a non-zero exit.
out="$(bash "$TARGET" --fixture "$FIXTURE" --format json 2>"$WORK/err.txt")"
rc=$?
if [[ "$rc" -eq 0 ]]; then
  pass ">MAX_ARG_STRLEN fixture exits 0 (pre-fix this dies 'Argument list too long')"
else
  fail ">MAX_ARG_STRLEN fixture exit=$rc -- stderr: $(head -c 200 "$WORK/err.txt")"
fi

# E2BIG must not be reachable even as a swallowed diagnostic.
if grep -qiE 'argument list too long' "$WORK/err.txt"; then
  fail "stderr carries an E2BIG diagnostic -- argv ceiling was hit"
else
  pass "no 'Argument list too long' diagnostic on stderr"
fi

# --- Completeness: every synthesized PR must survive classification ----------------------
# Guards the silent-truncation failure mode, which an exit-code-only assertion misses: a
# partial read that classified 12 of 40 PRs would still exit 0.
classified_count="$(printf '%s' "$out" | jq '[.[][]] | length')"
if [[ "$classified_count" -eq "$gen_rows" ]]; then
  pass "all $classified_count PRs classified (== $gen_rows source rows, no truncation)"
else
  fail "classified $classified_count PRs but fixture had $gen_rows -- truncation/undercount"
fi

# The tier field must be really populated, not empty shells at >ceiling size.
tiered="$(printf '%s' "$out" | jq '[.[][] | select(.tier != null and .number != null)] | length')"
if [[ "$tiered" -eq "$gen_rows" ]]; then
  pass "all $tiered rows carry a tier + number at >ceiling size"
else
  fail "only $tiered of $gen_rows rows carry tier+number"
fi

# --- Structural: the herestring must not have become an --argjson binding ----------------
# Anchored on the ASSIGNMENT LINE, not a bare token. `--argjson` legitimately appears in
# this script (`--argjson prs`, `--argjson order`) and `PR_JSON` now appears in the
# load-bearing comment block, so a bare grep for either would false-pass on prose.
if grep -qE '^CLASSIFIED="\$\(jq ' "$TARGET"; then
  pass "CLASSIFIED is still assigned from a jq invocation"
else
  fail "CLASSIFIED assignment shape changed -- re-verify the herestring invariant by hand"
fi

# Comments start with '#', so a match on a line that both ENDS the jq program and applies
# the herestring cannot be produced by the comment block above it.
if grep -qE "^[[:space:]]*\]'[[:space:]]*<<<\"\\\$PR_JSON\"\\)\"$" "$TARGET"; then
  pass "PR_JSON is applied via a <<< herestring (no argv binding)"
else
  fail "the <<<\"\$PR_JSON\" herestring is gone -- if it became --argjson, PR_JSON (392,170 B at 20 PRs) now exceeds MAX_ARG_STRLEN ($MAX_ARG_STRLEN)"
fi

# Directly forbid the mutation this suite exists to catch, on a CODE line only.
# `grep -c` (not `producer | grep -q`): under `set -o pipefail` an early match closes the
# pipe, the producer takes SIGPIPE (141) and the pipeline fails even though grep MATCHED.
argjson_prjson="$(grep -cE '^[^#]*--argjson[[:space:]]+[a-z_]+[[:space:]]+"\$PR_JSON"' "$TARGET")"
if [[ "$argjson_prjson" -eq 0 ]]; then
  pass "no --argjson binding of \$PR_JSON on any code line"
else
  fail "\$PR_JSON is bound via --argjson on $argjson_prjson code line(s) -- exceeds MAX_ARG_STRLEN ($MAX_ARG_STRLEN) on every real run"
fi

echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
