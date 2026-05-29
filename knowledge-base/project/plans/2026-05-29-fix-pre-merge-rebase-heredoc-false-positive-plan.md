---
title: "fix(hook): pre-merge-rebase.sh false-positive on 'gh pr merge' in commit-message body"
date: 2026-05-29
type: fix
issue: 4600
branch: feat-one-shot-4600-pre-merge-rebase-heredoc-fp
labels: [domain/engineering]
lane: single-domain
brand_survival_threshold: none
status: draft
---

# 🐛 fix(hook): pre-merge-rebase.sh false-positive on 'gh pr merge' text in commit-message body

## Enhancement Summary

**Deepened on:** 2026-05-29

### Key Improvements

1. **Precedent-diff (Phase 4.4):** found the canonical sibling precedent for the
   multiline-quoted-body problem — `follow-through-directive-gate.sh:72-73` uses
   `perl -0777` non-greedy regex to extract a quoted `--body` value across
   newlines, with the comment "Use perl for greedy regex; sed -E can't do
   non-greedy across newlines." Both the perl strip and the no-dep awk
   (`RS="\0"` gsub) strip were verified against the full case matrix; the plan
   now offers **perl as the precedent-aligned primary** and **awk as the
   no-new-dep alternative** (both pass; implementer picks one).
2. **`|| true` exit-5 fix is canonical, not novel:** `session-rules-loader.sh:59-60`
   and `background-poll-prefer-monitor.sh:76,82` already use the exact
   `jq … 2>/dev/null || true` pattern. `pre-merge-rebase.sh` itself already uses
   it on the *gh* jq reads (lines 101, 109) but NOT on the initial `CMD`/`WORK_DIR`
   reads — the precise gap this plan closes.
3. **Bash-realism on test assertions (Quality Check):** the test files run under
   `set -euo pipefail`; the new `assert_no_intercept` helper must capture the
   hook's exit code with `|| exit_code=$?` (the existing `run_hook`/T1 pattern)
   so a clean `exit 0` does not abort the test harness.

### New Considerations Discovered

- **Option (b) alone is provably insufficient** and Option (c) is provably
  necessary — verified empirically (see Research Reconciliation table). The
  rejected leading-`git commit` skip heuristic would have broken the
  chained-real-merge boundary (`git commit … && gh pr merge …`).
- The quote-strip approach is **novel for this codebase** at the
  merge-detection site (no sibling hook strips quoted spans before grep); the
  perl idiom precedent exists only for `--body` *extraction*, not *blanking*.
  Reviewers should scrutinize the gsub/regex span-class for escaped-quote edge
  cases (covered in Risks).

## Overview

The PreToolUse hook `.claude/hooks/pre-merge-rebase.sh` greps the *entire*
`.tool_input.command` string for `gh pr merge`. When an agent runs a
`git commit` whose message body contains the literal text `gh pr merge`
(e.g. documenting the rule "do not hand-roll `gh pr merge`"), the hook
mis-fires: it treats a plain commit as a merge and runs the review-evidence
gate, the clean-tree gate, and the origin/main auto-sync. This hit twice
while committing PR #4598.

This is a pure detection-scoping fix to a single bash hook. No new
infrastructure, no schema, no UI, no regulated-data surface. **Two
implementations are verified-equivalent against the full case matrix; the
implementer picks one at /work time:**

- **(primary, precedent-aligned)** `perl -0777` non-greedy quote-strip, mirroring
  the existing `follow-through-directive-gate.sh:72-73` idiom (which already uses
  `perl -0777` for multiline quoted-body handling — the canonical sibling for
  this exact problem). Perl is already a hook dependency.
- **(alternative, no-new-dep)** `awk 'BEGIN{RS="\0"} {gsub(...)}'` whole-stream
  strip, verified working under `mawk 1.3.4` (the host + ubuntu-latest CI default
  `/usr/bin/awk`). awk is the dominant text tool across 8 sibling hooks.

Both forms blank double- and single-quoted spans (escape-aware) before applying
the existing anchor regex. Either is acceptable; the perl form is preferred for
precedent consistency.

**Review addendum (post-implementation, #4600):** multi-agent review
(`test-design-reviewer`) surfaced that the quote-strip alone does NOT cover a
*bare* heredoc body (`git commit -F - <<EOF … gh pr merge … EOF`) where the
body is not wrapped in quotes — the branch's namesake shape. The implemented
perl form therefore blanks heredoc bodies FIRST
(`s/(<<-?\s*["']?)(\w+)(["']?)(.*?)(\n[ \t]*\2\b)/$1$2$3$5/gs`), preserving the
`<<DELIM` markers and everything after the closing delimiter (where a real
chained `gh pr merge` lives), THEN blanks quoted spans. Covered by new tests
T-FP4 (bare heredoc ⇒ no-intercept) and T8 (real merge chained after a heredoc
terminator ⇒ still fires).

A second, independent defect is folded in: under `set -eo pipefail`, the hook
exits 5 with **no JSON** on malformed-JSON stdin (the `CMD=$(echo | jq …)`
pipeline aborts before any output), violating the file's documented "fail-open
on infrastructure errors" invariant. PR #4598 already fixed the identical
exit-5 class in the new `background-poll-prefer-monitor.sh` via `|| true`. This
plan applies the same treatment to `pre-merge-rebase.sh` AND the sibling
`new-scheduled-cron-prefer-inngest.sh` (also reproduced exiting 5 on malformed
stdin).

## Root Cause (verified empirically, 2026-05-29)

Current early-exit filter (`pre-merge-rebase.sh:47`):

```bash
if ! echo "$CMD" | grep -qE '(^|&&|\|\||;|\s--\s)\s*gh\s+pr\s+merge(\s|$)'; then
  exit 0
fi
```

`grep -E` (without `-z`) treats embedded newlines in `$CMD` as line
boundaries. A `git commit -m "$(cat <<EOF … )"` or a multi-line `-m` body
whose body has a line **beginning** with `gh pr merge` (after optional
whitespace) matches the `^` alternative of the anchor group. Confirmed:

```text
CMD='git commit -m "do not hand-roll
gh pr merge directly"'
→ grep -qE '(^|&&|…)\s*gh\s+pr\s+merge(\s|$)'  ⇒ MATCH (false positive)
```

The `^` anchor is the trigger, but it is **not the only** body-text leak: a
body line containing `&& gh pr merge` or `; gh pr merge` also matches the
chain-operator alternatives. **Any chain/anchor token reachable inside the
quoted message body defeats the filter.**

### Research Reconciliation — issue options vs. verified reality

The issue lists three candidate fixes. Empirical probing (2026-05-29) shows
only one survives the adversarial cases that match the issue's own framing
("documenting the rule"):

| Issue option | Probe result | Verdict |
|---|---|---|
| (a) match only when NOT inside `-m`/`-F`/heredoc | Equivalent to (c) — requires identifying & excising the message body | Subsumed by (c) |
| (b) require a PR-number arg (`gh pr merge <N>`/`--`) | **Insufficient.** A body documenting `gh pr merge --auto` or `gh pr merge 4598` (the exact #4600 "documenting the rule" case) still matches | Reject as sole fix |
| (c) strip `git commit -m '…'`/heredoc bodies before matching | **Robust.** Stripping quoted spans removes the body while preserving command structure outside quotes, where a real chained merge lives | **Chosen** |

A naive "skip the whole command if the leading token is `git commit`"
heuristic was probed and **rejected as unsafe**: it also skips
`git commit -m "wip" && gh pr merge 123 --squash`, letting a real merge bypass
the gate. The chosen approach strips only quoted *spans*, so the chained real
merge outside the quotes still fires.

Verified strip+detect outcomes (awk `RS="\0"` whole-stream gsub of
double- and single-quoted spans, then the existing anchor regex):

| Input | Stripped | Detect | Want |
|---|---|---|---|
| `gh pr merge 123 --squash` | unchanged | MATCH | MATCH ✓ |
| `… with_lock merge-main 600 -- gh pr merge 99 …` | unchanged | MATCH | MATCH ✓ |
| `git commit -m "wip" && gh pr merge 123 --squash` | `git commit -m   && gh pr merge 123 …` | MATCH | MATCH ✓ |
| `git commit -m "do not hand-roll\ngh pr merge directly"` | `git commit -m  ` | no match | no match ✓ |
| `git commit -m "$(cat <<EOF\n… gh pr merge --auto\nEOF\n)"` | `git commit -m  ` | no match | no match ✓ |
| `git commit -m "docs: never … gh pr merge 4598 …"` | `git commit -m  ` | no match | no match ✓ |

## User-Brand Impact

**If this lands broken, the user experiences:** a hook that either (a) keeps
mis-firing the review/clean-tree/auto-sync gates on plain commits whose message
mentions `gh pr merge` (status quo friction), or (b) — the regression to guard
against — silently STOPS firing on a real `gh pr merge`, letting an unreviewed
or stale-branch merge through.
**If this leaks, the user's data / workflow / money is exposed via:** N/A — the
hook reads `tool_input.command` only; no user data, no external calls beyond
the existing `gh`/`git` invocations.
**Brand-survival threshold:** none — this is an internal agent-workflow guard
hook on the Soleur maintainer's own machine, not a target-user-facing surface.
The only failure that matters is the merge-bypass regression (b), which the
test plan's "real merge still fires" cases (T5–T7) gate against. The diff
touches no sensitive path per preflight Check 6 (canonical regex covers
schemas/migrations/auth/API/`.sql`; `.claude/hooks/*.sh` is not in scope).

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 (false-positive fixed):** `pre-merge-rebase.sh` exits 0 with no
  JSON output when fed a payload whose `command` is a `git commit` with a
  message body that contains `gh pr merge` at the start of a line, after a
  chain operator, or with a `--auto`/numbered argument. Verified by new test
  cases T-FP1..T-FP3 (see Test Strategy) — each asserts the early-exit filter
  does NOT classify the commit as a merge.
- [x] **AC2 (real merge still fires — anti-regression):** the hook still
  classifies as a merge and reaches the review-evidence gate for: bare
  `gh pr merge 123 --squash` (T5), `git commit -m "wip" && gh pr merge 123`
  (T6, chained-after-commit), and the `with_lock … -- gh pr merge …` wrapped
  form (T7). Each asserts the review-evidence deny path fires (rule_id
  `rf-never-skip-qa-review-before-merging`), reusing the T1 assertion shape.
- [x] **AC3 (existing behavior preserved):** the existing 4 deny-branch tests
  (T1 review-evidence, T2 uncommitted, T3 conflict, T4 push-fail) and the
  headless-visibility tests still pass unchanged. Run:
  `bash .claude/hooks/pre-merge-rebase.test.sh` ⇒ `FAIL=0`, and
  `bash .claude/hooks/pre-merge-rebase-headless.test.sh` ⇒ `FAIL=0`.
- [x] **AC4 (exit-5 fail-open, pre-merge-rebase):** `printf 'not json' |
  .claude/hooks/pre-merge-rebase.sh; echo $?` returns `0` (not `5`).
  Regression case T-MJ1 (malformed JSON ⇒ exit 0, no deny).
- [x] **AC5 (exit-5 fail-open, sibling cron hook):** `printf 'not json' |
  .claude/hooks/new-scheduled-cron-prefer-inngest.sh; echo $?` returns `0` and
  emits an `allow` JSON. Regression case added to
  `new-scheduled-cron-prefer-inngest.test.sh` (which currently has zero
  malformed-JSON cases — verified 2026-05-29).
- [x] **AC6 (whole suite green):** `bash scripts/test-all.sh scripts` passes
  (the shard that globs `.claude/hooks/*.test.sh` per `scripts/test-all.sh:173`).

### Post-merge (operator)

- None. This is a pure code change against an already-registered hook
  (`.claude/settings.json:45`). No terraform, no migration, no external state.

## Files to Edit

- **`.claude/hooks/pre-merge-rebase.sh`** — two edits:
  1. **Detection scoping (the fix).** Before the early-exit filter at line 47,
     derive a `SCAN` string from `$CMD` with quoted spans blanked out, and run
     the existing anchor regex against `SCAN` instead of `$CMD`. Pick **one** of
     the two verified-equivalent forms below (both pass the full case matrix in
     Research Reconciliation; perl is precedent-aligned, awk is no-new-dep):

     **(primary) perl — mirrors `follow-through-directive-gate.sh:72-73`:**
     ```bash
     # Strip quoted message bodies before merge-detection so a commit whose
     # message documents "gh pr merge" is not mistaken for a merge (#4600).
     # perl -0777 slurps the whole (possibly multi-line) command; the /gs flags
     # blank "…" and '…' spans (escape-aware) across newlines, leaving the
     # command structure outside quotes where a real chained `gh pr merge` lives.
     # Sibling precedent: follow-through-directive-gate.sh:72 ("sed -E can't do
     # non-greedy across newlines" — same multiline-quoted-body class).
     SCAN=$(printf '%s' "$CMD" | perl -0777 -pe \
       's/"(?:[^"\\]|\\.)*"/ /gs; s/'\''(?:[^'\''\\]|\\.)*'\''/ /gs;' 2>/dev/null || printf '%s' "$CMD")
     ```

     **(alternative) awk — no new dependency, verified under mawk 1.3.4:**
     ```bash
     SCAN=$(printf '%s' "$CMD" | awk 'BEGIN{RS="\0"} {
       gsub(/"([^"\\]|\\.)*"/, " ");
       gsub(/'\''([^'\''\\]|\\.)*'\''/, " ");
       printf "%s", $0
     }')
     ```

     Then the early-exit filter reads `$SCAN`:
     ```bash
     if ! echo "$SCAN" | grep -qE '(^|&&|\|\||;|\s--\s)\s*gh\s+pr\s+merge(\s|$)'; then
       exit 0
     fi
     ```
     Note the `|| printf '%s' "$CMD"` fallback on the perl form: if the strip
     tool is somehow unavailable, fall back to the raw `$CMD` — preserving the
     pre-fix (over-firing) behavior rather than silently going fail-open on a
     real merge. Update the inline comment block (lines 44–53) to document the
     quote-strip rationale and the #4600 reference. The PR-number extraction at
     line 97 (`echo "$CMD" | grep -oE 'gh\s+pr\s+merge\s+([0-9]+)'`) operates on
     `$CMD` and is fine to leave as-is: by the time it runs, the command IS a
     real merge (passed the SCAN filter), so the quoted-body concern does not
     apply — **but** add a one-line comment noting it intentionally reads `$CMD`
     not `$SCAN` (the merge args are outside quotes; stripping is unnecessary).
  2. **Exit-5 fail-open.** Append `|| true` to the `CMD=$(echo "$INPUT" | jq …)`
     assignment at line 42 (and to the `WORK_DIR` jq at line 56 for symmetry).
     Under `set -eo pipefail`, jq exits 5 on malformed stdin and aborts the
     script before the `WORK_DIR`/git guards can fail-open. Mirror the
     `background-poll-prefer-monitor.sh:76` pattern and its comment. After the
     fix, a malformed `$INPUT` yields `CMD=""`, the SCAN filter finds no merge,
     and the hook exits 0 — fail-open, as the header promises.

- **`.claude/hooks/pre-merge-rebase.test.sh`** — add cases:
  - `t_fp1_commit_body_newline` — payload command is a multi-line `git commit
    -m` whose body has a line starting with `gh pr merge`; assert exit 0 AND no
    incidents jsonl written (the hook never reached any deny branch). New
    assertion helper `assert_no_intercept` (exit 0, empty/absent jsonl).
  - `t_fp2_commit_body_chain_op` — body contains `… && gh pr merge --auto …`
    inside the quoted message; assert no-intercept.
  - `t_fp3_commit_body_numbered` — body contains `gh pr merge 4598` (the #4600
    "documenting the rule" shape); assert no-intercept.
  - `t5_bare_merge_fires` — `gh pr merge 123 --squash`, no review evidence ⇒
    assert_deny `rf-never-skip-qa-review-before-merging` (reuses T1 shape).
  - `t6_chained_after_commit_fires` — `git commit -m "wip" && gh pr merge 123
    --squash`, no review evidence ⇒ assert_deny (anti-regression for the
    chained-real-merge boundary).
  - `t7_wrapped_merge_fires` — `bash session-state.sh with_lock merge-main 600
    -- gh pr merge 99 --squash`, no review evidence ⇒ assert_deny.
  - `t_mj1_malformed_json_failopen` — `printf 'not json'` ⇒ assert exit 0, no
    deny, no incidents jsonl.

- **`.claude/hooks/new-scheduled-cron-prefer-inngest.test.sh`** — add the
  malformed/empty-stdin fail-open cases mirroring
  `background-poll-prefer-monitor.test.sh:106-117` (cases m/n/o): malformed
  JSON ⇒ `allow` + exit 0; empty stdin ⇒ `allow` + exit 0.

## Files to Create

- None.

## Test Strategy

RED-first per project convention (`cq-write-failing-tests-before`):

1. **RED:** add T-FP1..T-FP3, T5..T7, T-MJ1 to `pre-merge-rebase.test.sh` and
   the malformed-stdin cases to `new-scheduled-cron-prefer-inngest.test.sh`.
   Run both — the FP and exit-5 cases fail against current `main`.
2. **GREEN:** apply the two edits to `pre-merge-rebase.sh` and the `|| true` to
   `new-scheduled-cron-prefer-inngest.sh` (line 54 `tool_name="$(echo … | jq …)"`
   — the first jq under `set -euo pipefail` that aborts; append `|| true` and,
   for full symmetry with the reference fix, to the `file_path` read on line 55
   and the `content` read further down; verified exit 5 on `printf 'not json'`).
   Re-run; all green.
3. **Suite:** `bash scripts/test-all.sh scripts` — the shard that runs every
   `.claude/hooks/*.test.sh` in CI. Verified locally that the existing
   `pre-merge-rebase.test.sh` is green (4/4) at baseline.

**Test framework:** plain `.test.sh` bash scripts (the existing convention for
all `.claude/hooks/` tests — no bats, no new dependency). Verified runner:
`scripts/test-all.sh:173` globs `.claude/hooks/*.test.sh`. The new
`assert_no_intercept` helper asserts the early-exit path (exit 0, no JSON, no
incidents jsonl) — distinct from `assert_deny` which asserts a blocked merge.

### Research Insights

- **Bash-realism on the new assertions.** Both `pre-merge-rebase.test.sh`
  (`set -euo pipefail`, line 10) and the hook itself run under strict mode. A
  no-intercept run produces a clean `exit 0`, but a `$(… "$HOOK")` substitution
  whose command exits non-zero (e.g. the malformed-JSON case AFTER the fix
  exits 0, but BEFORE the fix exits 5) would abort the harness. Reuse the
  existing T1 capture idiom verbatim: `out=$(printf '%s' "$payload" |
  INCIDENTS_REPO_ROOT="$incidents" "$HOOK" 2>/dev/null) || exit_code=$?;
  exit_code=${exit_code:-0}` — never a bare `$(…)` whose failure propagates.
- **`assert_no_intercept` jsonl check.** The early-exit path writes NO incidents
  jsonl (the hook returns before any `emit_incident`). Assert `[[ ! -f
  "$incidents/.claude/.rule-incidents.jsonl" ]]` (or zero lines) AND `exit_code
  -eq 0` AND empty stdout. This is the inverse of `assert_deny`'s 1-line jsonl
  expectation.
- **Empty-stdin already fails-open by accident; malformed-JSON does not.**
  Verified 2026-05-29: `printf '' | pre-merge-rebase.sh` ⇒ exit 0 (jq treats
  empty as null → `""`), but `printf 'not json' | pre-merge-rebase.sh` ⇒ exit 5,
  no JSON. The T-MJ1 case MUST use genuinely malformed JSON (`not json`), not
  empty stdin, to exercise the real defect.
- **The strip operates on the WHOLE command, including the `$(cat <<EOF …)`
  wrapper.** Because `git commit -m "$(cat <<EOF … EOF)"` puts the heredoc body
  inside the outer `"…"` of the `-m` argument, blanking the outermost
  double-quoted span removes the entire heredoc body in one pass — no separate
  heredoc parser is needed. Verified against the exact #4600 shape.

## Risks & Mitigations

### Precedent diff (Phase 4.4)

The multiline-quoted-body strip is a **pattern-bound behavior**. Sibling
precedent: `.claude/hooks/follow-through-directive-gate.sh:72-73`:

```bash
# Use perl for greedy regex; sed -E can't do non-greedy across newlines.
BODY_INLINE=$(echo "$CMD" | perl -0777 -ne 'if (/--body[[:space:]]+(["'"'"'])(.+?)(?<!\\)\1/s) { print $2; }' || true)
```

That hook **extracts** a quoted `--body` value across newlines via `perl -0777`;
this plan **blanks** all quoted spans via the same `perl -0777` slurp + `/gs`
substitution. Same tool, same multiline-quoted-body class — so the perl form is
the precedent-aligned primary. **No sibling hook strips quoted spans before
grep at a *merge-detection* site**, so the application is novel; reviewers should
scrutinize the span-class regex (`(?:[^"\\]|\\.)*`) for escaped-quote handling
(covered below). The awk alternative has no sibling precedent for this exact use
but is verified-equivalent.

### Mitigations

- **Regression: real merge stops firing (merge-bypass).** This is the only
  brand-relevant failure. Mitigated by AC2 / T5–T7, which assert the gate still
  fires for bare, chained-after-commit, and `with_lock`-wrapped merges. The
  chained-after-commit case (T6) specifically guards the boundary that the
  rejected leading-`git commit` heuristic would have broken. Both strip forms
  also fall back to the raw `$CMD` (perl: `|| printf '%s' "$CMD"`; awk: the
  command-substitution returns the unstripped value if gsub is a no-op) so a
  strip-tool failure fails *toward* firing, not toward bypass.
- **awk portability** (only if the awk alternative is chosen). The quoted-span
  gsub uses POSIX ERE inside `gsub`, verified working under **mawk 1.3.4** (the
  default `/usr/bin/awk` on the host AND ubuntu-latest CI). No gawk-only
  constructs (`gensub`, `\<`, `RS` as regex) are used; `RS="\0"` reads the whole
  stream as one record, portable to mawk and gawk. Sibling hooks already depend
  on awk being present.
- **Escaped-quote edge cases inside message bodies.** The gsub class
  `([^"\\]|\\.)*` handles `\"`-escaped quotes inside a double-quoted body. A
  pathological commit body mixing unbalanced quotes could mis-strip, but the
  failure mode is conservative in the safe direction for the FP (over-stripping
  ⇒ no false merge-detection) and the anti-regression tests cover the real-merge
  path independently. No realistic `gh pr merge` invocation embeds the command
  inside quotes.
- **Exit-5 `|| true` masking a real jq failure.** Identical trade-off already
  accepted in `background-poll-prefer-monitor.sh` (PR #4598) and the rest of the
  hook family: a jq read failure degrades to empty ⇒ fail-open, which is the
  documented invariant. The hook is a guard, not a security boundary; fail-open
  on malformed harness input is correct.

## Open Code-Review Overlap

None — no open `code-review`-labeled issue references `pre-merge-rebase.sh`,
`new-scheduled-cron-prefer-inngest.sh`, or their test files (checked at plan
time; if any surface during /work, fold in or acknowledge per the gate).

## Observability

```yaml
liveness_signal:
  what: emit_incident telemetry on every deny branch (rule_id + event_type)
  cadence: per gh-pr-merge interception
  alert_target: .claude/.rule-incidents.jsonl (aggregated by scripts/rule-metrics-aggregate)
  configured_in: .claude/hooks/lib/incidents.sh (sourced by the hook)
error_reporting:
  destination: hook stderr via headless_or_stderr (routes to GIT_COMMON_DIR log under claude --bg)
  fail_loud: false — the hook is fail-open by design; infra errors warn, do not block
failure_modes:
  - mode: false-positive on commit-message body
    detection: pre-merge-rebase.test.sh T-FP1..T-FP3 (CI scripts shard)
    alert_route: CI red on scripts/test-all.sh scripts
  - mode: merge-bypass regression (real merge not detected)
    detection: pre-merge-rebase.test.sh T5..T7 (CI scripts shard)
    alert_route: CI red on scripts/test-all.sh scripts
  - mode: exit-5 no-JSON abort on malformed stdin
    detection: T-MJ1 + new-scheduled-cron malformed cases
    alert_route: CI red on scripts/test-all.sh scripts
logs:
  where: .claude/.rule-incidents.jsonl (deny events); GIT_COMMON_DIR/soleur-session-state/logs/$PPID.log (headless warns)
  retention: log-rotation.test.sh-governed rotation on the session-state logs
discoverability_test:
  command: "bash .claude/hooks/pre-merge-rebase.test.sh && bash .claude/hooks/new-scheduled-cron-prefer-inngest.test.sh"
  expected_output: "FAIL=0 in both suites"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal agent-workflow guard-hook
bug fix (engineering tooling). No user-facing surface, no infrastructure, no
regulated data.

## Infrastructure (IaC)

N/A — no new infrastructure. Pure edit to existing registered hook scripts.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. (Filled above; threshold = none with non-empty
  reason, and the diff touches no sensitive path.)
- The early-exit filter operates on `$SCAN` (quote-stripped) but the PR-number
  extraction at line 97 deliberately operates on `$CMD` (real merge args live
  outside quotes by the time that line runs). Do not "consistency-fix" line 97
  to use `$SCAN` — leave the documenting comment.
- When editing the `new-scheduled-cron-prefer-inngest.sh` `|| true`, target the
  **first** jq read (`tool_name`, line 54) — that is the one that aborts under
  `set -euo pipefail` on malformed stdin (verified exit 5). For full symmetry
  with the reference fix, append `|| true` to all jq field reads in that hook
  (`tool_name` :54, `file_path` :55, and the `content` read).
