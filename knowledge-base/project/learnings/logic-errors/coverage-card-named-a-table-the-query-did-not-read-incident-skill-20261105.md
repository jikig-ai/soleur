---
module: incident skill
date: 2026-11-05
problem_type: logic_error
component: tooling
symptoms:
  - "The coverage card named t520508_soleur_inngest_vector_prd_3_logs while the Better Stack command followed an inherited BS_TABLE"
  - "bash -x printed the complaint on stderr because the assignment sat above set +x"
  - "grep -qF env -u BS_TABLE stayed green when only BS_TABLE_S3 was unset"
root_cause: logic_error
resolution_type: code_fix
severity: high
tags: [incident-skill, coverage-card, xtrace, test-pin]
---

# The coverage card named a table the query did not read

## Problem

The incident skill's Phase 0 pull prints a coverage card and then starts the nineteen-field interview. The card named one Better Stack table. The command that ran honoured an inherited `BS_TABLE` and `BS_TABLE_S3`, so the card could describe a different table and archive than the query. A second hole: `set +x` ran after `complaint="${INCIDENT_COMPLAINT:-}"`, so an inherited trace printed the complaint before the redaction sentinel. A third hole: the test needle `env -u BS_TABLE` is a prefix of `env -u BS_TABLE_S3`.

## Environment

- Module: plugins/soleur/skills/incident
- Affected Component: Phase 0 fence in SKILL.md and plugins/soleur/skills/incident/test/pull-card.test.sh
- Date: 2026-11-05
- PR: https://github.com/jikig-ai/soleur/pull/12143
- Issue: https://github.com/jikig-ai/soleur/issues/12162

## Symptoms

- A shimmed query used `remote(not_the_card_table)` while the card printed `t520508_soleur_inngest_vector_prd_3_logs`.
- `bash -x` stderr contained `+ complaint='checkout button failed'` (and, with the fixture email, `fixture-pull@example.invalid`) while stdout stayed clean. The halt test grepped only stdout, so it stayed green.
- Deleting only `-u BS_TABLE` and leaving `-u BS_TABLE_S3` still matched the short needle.

## What Didn't Work

**Attempted Solution 1:** Treat the printer as the place that names the Sentry reason.

- **Why it failed:** The printer's Sentry arm stays `sentry exit=%s window=n/a`. The fence rewrites `sy_line` after the printer returns. Teaching the printer the four Sentry tokens was rejected.

**Attempted Solution 2:** Put `set +x` at the top of the fence so nothing above it can trace.

- **Why it failed:** The fence-execution test pins the Supabase refs and the table on the xtrace. Tracing off at the top blinds that pin. The assignment moves; `set +x` stays immediately above it.

**Attempted Solution 3:** A whole-file search for both Supabase refs.

- **Why it failed:** A space-joined mutant still contained both refs somewhere in the trace. One xtrace line must contain both refs and the two characters `\` and `n` between them.

## Session Errors

1. **The coverage consult was spawned as soleur-engineering-cto, then killed and respawned as a general-purpose subagent.** Recovery: the general-purpose consult returned and restated the existing `hypotheses=none` wontfix. **Prevention:** the coverage consult is not a CTO ruling; spawn it without a review-seat or CTO subagent type.
2. **The first TERM probe signaled only the bash pid while bash waited on sleep.** Recovery: the trap did not run, the wait expired, and six empty mode-0600 temps were deleted from `/tmp`. The committed test uses `os.killpg`. **Prevention:** bash defers a trapped signal until the foreground child exits; signal the process group.
3. **`git diff --stat` did not show the untracked session-state file.** Recovery: `git status --short`, then an explicit `git add` of that path. **Prevention:** status the worktree before commit; a diff against HEAD does not list untracked files.
4. **A whole-file xtrace search stayed green on a space-joined mutant.** Recovery: the test requires one trace line with both refs and `\\n` between them. **Prevention:** a pin that searches the whole trace certifies that the tokens exist, not that one command printed them together.

## Solution

The Better Stack command unsets both inherited names after Doppler injects them, and passes the table the card prints:

```bash
doppler run -p soleur -c prd_terraform -- env -u BS_TABLE -u BS_TABLE_S3 \
  scripts/betterstack-query.sh \
  --table t520508_soleur_inngest_vector_prd_3_logs \
  --since "$bs_since"
```

The complaint assignment is the next command after `set +x`. Nothing above that line expands the complaint. The halt test rejects the complaint text on stderr as well as stdout. The table pin is the full token `env -u BS_TABLE -u BS_TABLE_S3`, not the prefix `env -u BS_TABLE`.

`pull-card.test.sh` at that commit: 144 passed, 0 failed. Round-2 security measured the fixture email absent from stdout, stderr, and the doppler argv log, with the trace stopping at `+ set +x`.

## Why This Works

1. The card is a coverage record. A fixed table name is a lie when the process environment chooses another table. `--table` selects the hot table. Unsetting `BS_TABLE_S3` is what lets the archive derive (`*_logs` to `*_s3`). Unsetting only `BS_TABLE` leaves a foreign archive.
2. `set +x` stops tracing from the next command onward. An assignment that already ran is already in the trace. Moving the assignment below `set +x` is the close. Moving `set +x` itself up hides the pins the suite reads.
3. A prefix needle matches a longer flag that shares its spelling. The full token fails when either variable is left set.

## Prevention

- When a card names a table, pin the command that produces the card to that table, including the archive variable the script will otherwise inherit.
- Put `set +x` on the line immediately before the value that must not be traced, and assert the value is absent from stderr.
- Test needles that name a flag must include the following token when a longer flag shares the prefix.
- Do not add a ranker. The fence still writes `hypotheses=none`. The prose comment above that line is not executable.

## Related Issues

- See also: [2026-09-11-the-gate-i-skipped-for-contention-hid-my-own-red-suite-and-two-rehearsals-attested-a-gc-that-never-ran.md](../2026-09-11-the-gate-i-skipped-for-contention-hid-my-own-red-suite-and-two-rehearsals-attested-a-gc-that-never-ran.md) (a Better Stack `--table` that did not take effect).
- See also: [2026-09-19-adding-a-check-for-the-new-key-showed-me-the-old-one-had-none.md](../2026-09-19-adding-a-check-for-the-new-key-showed-me-the-old-one-had-none.md) (`set +x` as the first executable line of a different script; this fence cannot do that, because the suite reads the trace above the complaint).
- See also: [2026-10-07-a-one-line-operational-ask-became-a-day-long-pipeline-and-the-lead-dropped-a-seat-finding.md](../2026-10-07-a-one-line-operational-ask-became-a-day-long-pipeline-and-the-lead-dropped-a-seat-finding.md) (an ad-hoc `remote($BS_TABLE)` misses the cold archive).
