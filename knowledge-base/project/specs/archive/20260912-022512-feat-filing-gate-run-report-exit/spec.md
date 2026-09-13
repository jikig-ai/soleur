---
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-09-11-filing-gate-run-report-exit-brainstorm.md
inciting_issue: 8059
tracking_issue: 8076
---

# Feature: run-report exit, lifecycle and measurement for the filing gate

## Problem Statement

`guardrails:require-filing-justification` (PR #8038, ADR-216) has three exits
and ADR-216 asserts no filing exists that needs a fourth. Four scheduled crons
(`community-monitor`, `content-generator`, `roadmap-review`,
`competitive-analysis`) MUST file a `scheduled-<task>` issue on every run — the
heartbeat reads its existence as liveness and the persistence handshake refuses
to commit the run without it. On first contact (#8059, 11 hours after merge)
the community-monitor cron was denied and complied by taking the machinery exit
for a community digest. The machinery-drain pool is now 2 reports and 0
findings; the weekly measurement cannot tell relabel from reduce; the denial
itself left no telemetry; and run-reports have no lifecycle (43 open digests,
last mass-closed by hand 2026-07-27).

## Goals

- Give mandated run-reports an honest exit that no agent can narrate into.
- Make the 2026-10-08 four-week check diagnostic: report the class-3
  run-report floor and the exit-1 share beside the headline.
- Give SUCCESS run-reports a lifecycle; never auto-close FAILED ones.
- Make cron-hook filing denials observable in Better Stack.
- Restore the machinery ledger to findings only.

## Non-Goals

- Raising the price of exit 1 (`Machinery: <path>`) — deferred until the exit-1
  share line can say whether it is needed.
- Once-per-run enforcement of the run-report exit (rejected: allow ≠ success).
- Moving run-report filing to the handler (rejected: the issue is the
  proof-of-output).
- Changing the run-report-as-issue product shape (Productize Candidate,
  follow-up).
- The PA-32 Article 30 register gap (follow-up for the legal auditor).
- Root-causing duplicate run-reports per fire.

## Functional Requirements

### FR1: Run-report directive

For each cron in a `RUN_REPORT_CRONS` subset of `TASK_INVENTORY`
(community-monitor, content-generator, roadmap-review, competitive-analysis —
explicitly not legal-audit), the substrate writes
`run-report-label scheduled-<task>` into the per-spawn `.claude/cron-allow.txt`.

### FR2: Run-report exit

The cron containment hook passes a `gh issue create` segment iff a real
`--label`/`-l`/`--label=` token (comma-split, comma-anchored, same tokenizer as
exit 1) equals the directive's label. Prose mentions of the label do not pass.
A cron with no directive is unaffected. The spawn-time hook self-test covers the
new directive.

### FR3: Measurement lines

`scripts/issue-flow-measure.sh` emits two additional numbered lines: the
class-3 run-report floor (issues by `app/soleur-ai` carrying any `scheduled-*`
label, created in window) and the exit-1 share (issues carrying
`meta/machinery`, created in window). The headline `filed` is unchanged. The
machinery-drain pool query excludes the standing measurement issue.

### FR4: Run-report lifecycle

SUCCESS run-reports whose `scheduled-<task>` label is in `TASK_INVENTORY`
auto-close at 3 × that task's `maxGapDays` with a stable comment marker.
Titles matching `- FAILED` or `[cloud-task-silence]` are never closed. Kill
switches `do-not-autoclose` / `keep-open` and a per-run close cap apply. Daily
triage skips `scheduled-*` issues.

### FR5: Denial observability

On a filing-justification deny, the hook appends one JSON record (cron, exit
attempted, label tokens seen, reason) to `.claude/filing-denials.jsonl` inside a
try/catch that cannot change the decision. After the agent exits, the substrate
reads the file and emits `SOLEUR_CRON_FILING_DENY` at WARN with count and
reasons, beside `stdoutTail`.

### FR6: Ledger repair

`meta/machinery` is removed from #8059. ADR-216 is amended to record the
run-report population and the directive exit. `wg-defer-only-after-inline-triage`'s
body is updated from "one of three exits" and the change is acked in
`.claude/rule-weakening-acks.txt` as a narrowing recorded honestly.

### FR7: Interactive-gate false denies

`guardrails:require-filing-justification` must (a) tokenize a command whose
prose contains an apostrophe without losing the `--label` token (fall back to a
quote-tolerant split when `xargs` fails, never to an empty list), and (b) honour
an exit-1 pass before applying the unreadable-`--body-file` deny. Both were hit
filing #8076.

## Technical Requirements

### TR1: Directive grammar

`parseAllowlist` gains `^run-report-label\s+(\S+)$` alongside `mcp-allow` and
`navigate-origin`; unmatched lines still fall through to the bash allowlist.
The directive is written only by `_cron-claude-eval-substrate.ts`; the agent's
read/write deny on `.claude/` is unchanged.

### TR2: Narrowing-only property

The run-report check runs after the allowlist match, so it can only pass a
command the allowlist already permits. Contract-tested like exit 1.

### TR3: Tests

Mutation rows for the new predicate in `cron-bash-allowlist-hook.test.ts`
(prose mention, wrong cron, comma-joined, `-l` form, no directive); a first test
file for `issue-flow-measure.sh` using stub `gh` fixtures (the
`net-issue-flow.test.sh` pattern); sweeper tests for the age table, FAILED
guard and cap.

### TR4: Fail-toward-skipping

Every lifecycle guard fails toward not closing. Denial logging fails toward the
original decision. An unreadable directive file is a deny (existing behaviour).

### TR5: Observability citation

`SOLEUR_CRON_FILING_DENY` is a pino WARN so it leaves the host (layer: Better
Stack via Vector allowlist); add it to the runbook's marker table.
