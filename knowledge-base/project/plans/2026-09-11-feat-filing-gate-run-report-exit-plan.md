---
title: "feat(issue-flow): a substrate-issued run-report exit, a run-report lifecycle, and an exit-aware measurement for the filing gate"
date: 2026-09-11
slug: feat-filing-gate-run-report-exit
branch: feat-filing-gate-run-report-exit
issue: 8076
closes: 8076
type: feat
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
brainstorm: knowledge-base/project/brainstorms/2026-09-11-filing-gate-run-report-exit-brainstorm.md
spec: knowledge-base/project/specs/feat-filing-gate-run-report-exit/spec.md
---

## Overview

PR #8038 shipped `guardrails:require-filing-justification` — a blocking gate on
`gh issue create` with three exits — and ADR-216 recorded that no filing exists
which "must bypass the gate, cannot be labelled machinery, and cannot name a
user impact." Eleven hours after merge the daily community digest
(`cron-community-monitor`, #8059) was denied on its prescribed filing and
complied by taking `--label meta/machinery`. The gate worked on its target
population; what it exposed is a **population** the ADR said did not exist.

Nine crons MUST file a `scheduled-<task>` issue on every run: the persistence
handshake refuses to commit the run's artifacts until
`verifyScheduledIssueCreated` (`_cron-shared.ts:820`, called through
`resolveOutputAwareOk` by nine cron functions) sees it, and for five of them
`cron-cloud-task-heartbeat.ts` `TASK_INVENTORY` also reads that issue's
existence as liveness (`labels: task.label, state: "all"`, L196-210). Those filings
are "mandated by construction" — the reasoning ADR-216 used to exempt class 2
(workflow YAML) — but they run in class 3 (the cron substrate) and got no exit.

This plan gives that population an honest exit **that no agent can narrate
into** (a substrate-written directive in the same agent-unreadable
`cron-allow.txt` that ADR-058 established for `mcp-allow`), makes the weekly
measurement able to tell *relabel* from *reduce*, gives SUCCESS run-reports a
lifecycle (43 open community digests, last bulk-closed on 2026-07-27 by a
person rather than a sweeper), makes cron-hook denials observable in Better
Stack (today the deny reaches only Claude Code's stdin channel), fixes two
interactive-gate false denies met while filing #8076 itself, and repairs the
ledger and the records (ADR-216, the rule body, the ack file) so they tell the
truth.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| FR1: directive for a `RUN_REPORT_CRONS` subset of `TASK_INVENTORY` (five) | The population that MUST file is the **nine** `resolveOutputAwareOk` callers (each passes `label: SENTRY_MONITOR_SLUG`); `TASK_INVENTORY` is the heartbeat's five-entry liveness subset. legal-audit is in neither — its per-gap findings are the only output of a cron with no write authority, exit 2 refuses a small measured fix and exit 3 has no mandating rule | Key the map on the verify contract with a call-site grep parity test; legal-audit is **User-Challenge D1** at the review gate |
| FR4: "Titles matching `- FAILED` … are never closed" | The handler-filed FAILED self-report (#4960) uses the **normal** title; FAILED is marked by the body prefix `AUDIT_SELF_REPORT_BODY_PREFIX = "Automated FAILED self-report"` (`_cron-shared.ts:954`). #8027 is one | Guard on **both**: body prefix (exported constant, imported) AND title `FAILED` |
| FR4: sweeper extension "with per-label age table" | The sweeper is ONE search query with ONE cutoff (`buildSearchQuery`, L225-235) and a product-facing skip on `priority/p1-high` (L80-86, L379-386) — which daily triage put on 21 of the 43 digests | A second arm (`sweepRunReports`) with a per-label `created:<cutoff` query and its own guard set; the product-facing guard is replaced by an explicit `action-required`/kill-switch guard for this arm (priority labels on run-reports are triage noise, not product signal) |
| FR5: "hook appends … the substrate reads it post-exit … `SOLEUR_CRON_FILING_DENY` WARN" | The hook imports only `readFileSync` (`cron-bash-allowlist-hook.mjs:47`); no post-exit WARN precedent exists in the substrate — the precedent is `emitClaudeCostMarker` in `server/claude-cost-marker.ts:65-75` (`pino({base:{component}})` + `log.warn({SOLEUR_X:true,…})`, never throws) | New `server/inngest/cron-filing-deny-marker.ts` mirroring that shape; hook gains `appendFileSync` inside try/catch |
| FR3: "drain pool query excludes the standing measurement issue" | The pool count (`scheduled-machinery-drain.yml:58-62`) runs BEFORE the step that resolves the standing issue by title (~L152-158) | Resolve the title match inside the pool step and subtract it |
| Spec FR1 says "hook passes iff a real `--label` token equals the directive" | `filingJustificationReason(tokens, readTaxonomy)` (hook L78) receives tokens only, not the parsed allowlist (`decide()` L602-604) | Thread `allow.runReportLabel` as a third argument |
| ADR: brainstorm decision 4 said "ADR-216 amendment"; CTO said "create a new ADR" | The refuted claim lives in ADR-216 §"Three exits, one gate, and deliberately no fourth"; Phase 2.10 says divergence from an existing ADR → amend it. Highest ordinal across 85 pushed refs is 216 | **Amend ADR-216**; no new ordinal (avoids the #5945/#5990 collision class) |

## Research Insights

**Premise Validation (Phase 0.6).** #8076 OPEN (this plan's target, created this
session); #8059 OPEN, relabelled — `meta/machinery` already removed at brainstorm
time; PR #8038 MERGED 2026-09-10T21:31:58Z. Every cited file exists on the
branch: `cron-bash-allowlist-hook.mjs` (`parseAllowlist` L484-503 returns
`{bash, mcpAllow, navigateOrigin}`; `filingJustificationReason` L78; exit-1
closure `hasMachineryLabel` L112-122; `main()` L683-695 try/catch → deny,
always exit 0), `_cron-claude-eval-substrate.ts` (`allowlistLines` L769-793,
`CRON_MCP_ALLOWLISTS` L436-450, `runHookSelfTest` L511+, `claudeDir` L759,
`child.on("exit")` L1065-1078, `emitClaudeCostMarker` call L1027),
`cron-cloud-task-heartbeat.ts` (`TASK_INVENTORY` L69-75, not imported anywhere;
no substrate↔heartbeat import in either direction),
`cron-stale-deferred-scope-outs.ts` (`TARGET_LABELS` L67, `KILLSWITCH_LABELS`
L75, `PRODUCT_FACING_LABELS` L80, `MAX_CLOSES_PER_RUN` L92,
`MAX_CLOSES_PER_LABEL` L104-107, `COMMENT_MARKER` L160, `buildSearchQuery`
L225, human-triage guard L422-465, `__TESTING__` L750-763, schedule
`0 12 * * *` L743), `cron-daily-triage.ts:69` (jq exclusion predicate),
`scripts/issue-flow-measure.sh` (`api_count` L47-50, lines 1/1b/2/3/4/5 at
L109-127, VERDICT L132/134), `.github/workflows/scheduled-machinery-drain.yml`
(pool count L58-62, post-count ~L96-99, verdicts L107-118, title lookup
~L152-158), `.claude/hooks/guardrails.sh` (tokenizer L451, exit-1 L569-583,
body-file deny L616-628), `guardrails.test.sh` (`MIN_ASSERTIONS=106`, L822).
**ADR corpus grep on the mechanism** (`run-report`, `cron-allow`, `directive`):
ADR-058 is the directive precedent and states the hook "never receives
`cronName`" — policy goes in the per-cron file; nothing rejects a directive.
ADR-216 §"deliberately no fourth" is the claim this plan amends.

**Property List (Phase 0.6b).** P1 a single-report cron's REQUIRED filing
passes with only the label its prompt already prescribes · P2 the pass depends
only on data the agent can neither read nor write · P3 a cron with no
directive is denied exactly as today (narrowing-only) · P4 non-run-report
findings stay gated · P5 measurement shows the run-report floor and the exit-1
share as separate lines, headline unchanged · P6 the drain pool excludes the
standing measurement issue · P7 SUCCESS run-reports close at 3× their
heartbeat cadence, FAILED never, kill-switches/caps hold · P8 daily triage
stops labelling `scheduled-*` · P9 every cron-hook filing deny is visible in
Better Stack with cron + reason, and a deny that ended without the issue is
discriminable in Sentry ·
P10 the machinery ledger holds findings only and ADR-216 states the real
population · P11 rule body + ack updated · P12 an honest exit-1 filing with an
apostrophe in the command, or with an unreadable body file, passes the
interactive gate.

**Cut List (Phase 0.6b).** Once-per-run marker → would buy nothing in the list
and breaks P1 on a `gh` retry (PreToolUse fires on allow, not success) · a new
run-report closer → the sweeper already carries window/caps/kill-switch/
human-triage guards and a Sentry monitor; extend it · a new ADR ordinal → the
refuted claim is ADR-216's; amend it · relabel #8059 → done at brainstorm ·
`cronName` in hook argv/env → rejected by ADR-058 (agent-readable via `ps`) · hook-written deny jsonl → `permission_denials[]` already carries every deny (measured) · hook title-shape half → breaks campaign-calendar · moving `TASK_INVENTORY` → the heartbeat is not this feature's concern.

**Institutional learnings applied.**
- `2026-09-10-every-escape-my-mutations-could-not-reach.md` — read real
  `--label` flag values, never `$COMMAND` prose; the body may arrive via
  `--body-file` rather than inline.
- ADR-058 — substrate is the sole producer of directive lines; hook a pure
  consumer; `runHookSelfTest` re-probes the written clone per spawn.
- `2026-06-12-restoring-a-contained-cron-literal-allowlist-forms-and-decide-paired-tests.md`
  — the hook prefix-matches literal verbs; directive text must be literal.
- Post-mortems `stale-deferred-scope-outs-cron-false-page-postmortem.md` +
  `cron-stale-scope-outs-github-connect-timeout-postmortem.md` — the sweeper
  paged on a transient GitHub fault by posting an `error` heartbeat before its
  Inngest retry; every new API call in the run-report arm goes through
  `withGithubRetry` inside the existing try.
- `best-practices/2026-06-03-every-run-durable-observability-info-silent-fallback.md`
  — `logger.info` never reaches Better Stack; WARN+ via pino does.
- `2026-05-29-mirror-warn-debounce-gates-both-pino-and-sentry.md` — do not
  route the new marker through a debounced helper.
- `security-issues/2026-07-06-body-hashing-guardrail-gate-fail-open-classes.md`
  — a rule-body edit is a three-step: edit, `lint-rule-bodies.py --write`, ack
  line; never touch the linter's classifier in the same diff.
- `test-failures/2026-05-30-shell-assert-value-embed-breaks-on-apostrophes.md`
  — the apostrophe class in bash tokenizing.
- `test-failures/2026-06-12-hook-test-passes-on-worktree-fails-on-main-cwd.md`
  — run `guardrails.test.sh` from a non-git CWD before trusting green.
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
  — harness rows + must-PASS-non-canonical rows in every matrix below.

**GDPR gate (Phase 2.7).** Ran `gdpr-gate.sh` against the plan + spec: 2 paths examined, 0 matched. The `POSTURE_FAIL` line it prints is the pre-existing corpus-freshness row (compliance-posture.md #7710, IN-PROGRESS; writer restored in #7841 merged 2026-09-07, first tick 2026-09-14) — not a finding of this plan.

**Related issues / PRs.** #8038 (gate), #8059 (inciting digest), #8068
(standing measurement issue, class 2, stays `meta/machinery`), #8027 (FAILED
self-report that triage hid), #4960 (handler FAILED fallback), #5199/ADR-058
(directive grammar), #7425 (ack-line precedent for a narrowing recorded
honestly).

**Conventions.** Tests: `apps/web-platform` runs **vitest**
(`package.json:15`; globs `test/**/*.test.ts`), typecheck is
`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; shell suites are
`*.test.sh` under `plugins/soleur/test/` and `.claude/hooks/`. Hook files are
`.mjs` consumed by a self-test at spawn. `cq-write-failing-tests-before`
applies to every phase.

## Problem Statement / Motivation

Nine crons (ten with legal-audit — D1) cannot pass the gate honestly; the first took the
free exit and put a community digest on the machinery ledger, where the drain
would one-shot it. The measurement cannot see exit distribution. The deny that
started all this left no telemetry. Run-reports have no lifecycle. And the
interactive gate refused two honest filings while this was being written.

## Proposed Solution

Six coupled deliverables, sequenced so each phase's tests can go RED→GREEN on
its own and the contract-changing edits land before their consumers.

### Decision D1 — legal-audit and the directive (User-Challenge)

**Population correction first (spec-flow P0).** The population that MUST file
is not `TASK_INVENTORY` (five) — it is every cron whose run completion is
verified by its own scheduled issue: the **nine** callers of
`resolveOutputAwareOk`, each passing `label: SENTRY_MONITOR_SLUG`
(architecture-diagram-sync `0 2 * * 0`, campaign-calendar `0 16 * * 1`,
community-monitor daily, competitive-analysis `0 9 1 * *`, content-generator
Tue/Thu, growth-audit `0 7 * * 1`, growth-execution `0 10 1,15 * *`,
roadmap-review `0 9 * * 1`, seo-aeo-audit `0 11 * * 1`). Seven of them say
"Creating the audit issue above is REQUIRED" in their prompt. First fire after
merge: **architecture-diagram-sync, Sun 2026-09-13 02:00Z**, then four more on
Monday. The directive map is therefore keyed on the verify contract, with a
grep-parity test over `functions/cron-*.ts` (every file calling
`resolveOutputAwareOk(` is in the map with its `SENTRY_MONITOR_SLUG`, and
vice-versa), not on the heartbeat inventory.

**legal-audit** is not in that nine — it uses `resolveBestEffortEvalOk`
(`cron-legal-audit.ts:305`) and has no persistence step. Its per-gap findings
are its only output; a cron with no write authority cannot satisfy exit 2's
"fix inline" refusal and no corpus rule mandates its filings (exit 3). Out of
the map, on 2026-10-01 it is denied and either takes exit 1 (legal findings
land on the machinery ledger and the weekly drain one-shots them) or exits
benign with the monitor green and a `[cloud-task-silence]` issue at 95 days.
Brainstorm decision 2 said "not legal-audit." **Decided at the plan-review
gate (2026-09-11): legal-audit IS in the directive map** — ten rows — (its
label is its output contract; volume bounded by `CAP_PER_RUN=5`, quarterly
cadence, 90-day title idempotency; counted by line 1c) **and is NEVER in
the sweep list** (`closeAfterDays: null`; its issues are findings, not
reports). Parity (i) treats it as the one row without a
`resolveOutputAwareOk` call site.

## Technical Considerations

### Phase 1 — Directive contract (hook + substrate)  [FR1, FR2, TR1, TR2]

1. `cron-bash-allowlist-hook.mjs`
   - `parseAllowlist` (L484-503): add `/^run-report-label\s+(\S+)$/` →
     `runReportLabel` (last-match-wins, like `navigate-origin`); unmatched
     lines still fall through to `bash[]`. Return shape becomes
     `{ bash, mcpAllow, navigateOrigin, runReportLabel }`.
   - Extract the six-form label matcher out of the `hasMachineryLabel`
     closure (L112-122) into `labelTokenEquals(tokens, label)` so exit 1 and
     the new exit share one matcher (`--label`, `-l`, `--label=`, `-l=`,
     `-f labels[]=`, `labels[]=`; comma-split, comma-anchored).
   - `filingJustificationReason(tokens, readTaxonomy, runReportLabel)`: a new
     **exit 0 — run-report**, evaluated first: `runReportLabel` is set and
     `labelTokenEquals(tokens, runReportLabel)`. **Label only — no title
     shape.** A title-half was considered and cut at plan-review:
     campaign-calendar's REQUIRED filings are `[Content] Overdue: …` with
     `action-required,scheduled-campaign-calendar` (`cron-campaign-calendar.ts:103-105`),
     so a `[Scheduled] ` requirement denies one of the nine. The
     file-and-vanish path (a finding borrowing its cron's label, then
     auto-closed) is closed by the **sweeper's** title + author guards
     (Phase 4) instead, and the residue — a finding filed under a run-report
     label — stays open, visible, and counted by measurement line 1c. Prose
     mentions never match because tokens come from the dequoted segment.
     `decide()` (L600-604) passes `allow.runReportLabel`. The check stays
     AFTER `segmentMatchesAllowlist` (narrowing-only, TR2).
   - Deny text: unchanged when no directive; with a directive, append
     `, or this cron's own run-report label <label> on a real --label token`.
2. `_cron-claude-eval-substrate.ts`
   - **New leaf module** `server/inngest/functions/_cron-run-reports.ts`
     (no Inngest import, no side effects; `_`-prefixed so
     `cron-substrate-imports.test.ts` skips it) holding
     `RUN_REPORT_TITLE_PREFIX = "[Scheduled] "` and
     `RUN_REPORT_CRONS: ReadonlyArray<{ fn, label, closeAfterDays: number | null }>`
     — one row per cron in the verify population (the nine
     `resolveOutputAwareOk` callers plus legal-audit per D1 — ten rows), `label` = that
     cron's `SENTRY_MONITOR_SLUG`, `closeAfterDays` a **literal** per row
     (community-monitor 9, content-generator 27, roadmap-review 27,
     competitive-analysis 120, growth-audit 27, seo-aeo-audit 27,
     architecture-diagram-sync 27, growth-execution 51; `null` for
     campaign-calendar — it comment-bumps one standing issue,
     `_cron-shared.ts:797-805` — and for legal-audit, whose issues are
     findings). `TASK_INVENTORY` stays where it is; the heartbeat is
     untouched. The substrate derives `CRON_RUN_REPORT_LABELS` from
     `RUN_REPORT_CRONS` and pushes `run-report-label <label>` into
     `allowlistLines` (L769-793) when `cronName` has a row.
   - Parity tests (`cron-run-report-labels-parity.test.ts`): (i) every
     `functions/cron-*.ts` with a **call site** matching
     `/^\s*(const \w+ = )?(await )?resolveOutputAwareOk\(/m` (not a comment
     mention) has a row whose `label` equals that file's
     `SENTRY_MONITOR_SLUG`, and every row except legal-audit maps back to
     such a file; (ii) every row's `fn` is in `CRON_BASH_ALLOWLISTS` with a
     `gh issue create` prefix; (iii) for rows whose label is in
     `TASK_INVENTORY`, `closeAfterDays === 3 × maxGapDays`.
   - `runHookSelfTest` (L511-527) takes explicit args: pass `runReportLabel`
     from the map, mirroring `mcpAllow`, so a lost directive line is what
     probe (a) detects. When set, probe (a)
     `gh issue create --title t --label <label> --milestone "Post-MVP / Later"`
     must ALLOW, (b) `gh issue create --title t --body "run-report-label <label>"`
     (prose mention, no real label token) must DENY, (c) `gh issue create
     --title t --label <label>x` must DENY. Abort the spawn on any miss, like
     the existing probes.
3. Tests (RED first): `cron-bash-allowlist-hook.test.ts` — new `describe("Bash
   — run-report exit (class 3)")` beside L569 with the matrix in §Guard 1;
   `cron-claude-eval-substrate.test.ts` — directive delivered for each mapped
   cron, absent for ux-audit, self-test probes; the parity test above.

### Phase 2 — Denial observability  [FR5, TR5]

1. **No hook write, no jsonl.** Measured at plan time (a throwaway settings
   hook returning `permissionDecision: "deny"` under `claude --print
   --output-format json`): a PreToolUse hook deny lands in the result
   event's `permission_denials[]` with `tool_name` and the full
   `tool_input.command`. The substrate already parses that event
   (`parseClaudeResultLine`, L109; fixture `test/helpers/soleur-go-fixtures.ts:117`).
   Extend `ParsedEvalResult` with `filingDenials: number` = the count of
   `permission_denials` whose `tool_input.command` matches the two filing
   shapes `filingJustificationReason` already defines (L89-101: `gh issue
   create …` and `gh api …/issues -X POST`).
2. In `finish()` beside `emitClaudeCostMarker` (L1027), when
   `filingDenials > 0` emit one `log.warn({ SOLEUR_CRON_FILING_DENY: true, fn,
   runId, runStartedAt, count, commands }, "cron filing denied")` via a
   module-level `pino({ base: { component: "cron-filing-deny" } })` (the
   `claude-cost-marker.ts:32` shape); `commands` is each denied command's
   first three tokens. Nothing else changes: no `SpawnResult` field, no
   `resolveOutputAwareOk` arg, no caller edits. "Denied and did not comply"
   is the marker **plus** the existing `scheduled-output-missing` Sentry
   event, which already carries `fn` + `runStartedAt` — the same two keys the
   marker carries — so correlation is one filter, not a hunt. For crons with
   no verify (legal-audit, D1) the marker alone is the signal and the
   `[cloud-task-silence]` issue is the backstop.
3. Runbook: add `SOLEUR_CRON_FILING_DENY` to the marker table in
   `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`
   as a two-line recipe: query the marker → filter Sentry
   `scheduled-output-missing` on `fn` + `runStartedAt`.
4. Tests: `parseClaudeResultLine` — two filing-shaped denials + one
   non-filing denial → `filingDenials: 2`; empty/absent array → 0; the
   marker is emitted once with `count: 2` and not at all when 0.

### Phase 3 — Measurement and records  [FR3, FR6]

1. `scripts/issue-flow-measure.sh`: after line 1b add
   `1c. of which cron run-reports (RUN_REPORT_CRONS labels)=N — a second irreducible floor, INSIDE the gate's reach but not reducible by it`
   using `api_count "is:issue+created:>=${SINCE}+author:app/soleur-ai+label:%22scheduled-community-monitor%22,%22scheduled-content-generator%22,…"`
   (comma-joined `label:` is OR — same convention as `buildSearchQuery`), and
   `1d. of which took exit 1 (meta/machinery)=N` via
   `api_count "is:issue+created:>=${SINCE}+label:%22meta/machinery%22+-label:keep-open"`.
   Headline `filed` untouched. Keep the label list in one shell array with a
   comment pointing at `_cron-run-reports.ts`.
2. `scheduled-machinery-drain.yml`: the standing issue #8068 is a **drain
   candidate**, not just a count. Create it with (L173-174) and give it the
   `keep-open` kill-switch (a one-time `gh issue edit 8068 --add-label
   keep-open` in /work), and add `-label:keep-open` to the pool count
   (L58-62) and post-count (~L96-99) queries — one token, no title lookup.
   `plugins/soleur/skills/drain-labeled-backlog/scripts/group-by-area.sh:116-117`:
   apply the kill-switch exclusion for the machinery label too (today the
   `jq` filter runs only when `$LABEL != meta/machinery`).
3. New `plugins/soleur/test/issue-flow-measure.test.sh` (first suite for this
   script) with a stub `gh` on `PATH` returning canned `total_count` per query
   substring (the `net-issue-flow.test.sh` fixture pattern): asserts lines 1c
   and 1d print with the stubbed values, the headline is unchanged, and — the
   parity row — every `scheduled-*` label in the script's array appears in
   `_cron-run-reports.ts` (and vice-versa) by grep.
   `plugins/soleur/test/machinery-drain-floor.test.sh`: one row asserting
   both pool queries carry `-label:keep-open`.
4. ADR-216: add `## Addendum 2026-09-11 — the fourth population` under
   §"Three exits, one gate, and deliberately no fourth": the population
   (every cron whose completion is verified by its own scheduled issue —
   nine `resolveOutputAwareOk` callers — plus the D1 outcome), why it is
   class-2 reasoning inside class 3, the directive exit and why it is not
   the cut marker (substrate-written, agent-unreadable, absent for every
   other cron), the title-half considered and cut, and the rejected
   alternatives (once-per-run marker, handler-side filing, new closer,
   `cronName` in argv, jsonl deny log) each with its mechanical reason.
   Update the exits list to four and the filing-surface table's class-3
   row. ADR-216 cites the hook header for the operative text; ADR-058 gets
   a one-line cross-reference ("third directive shape").
5. `AGENTS.rules.md:89`: "… a filing must also name a user-visible
   consequence, a measured fix size, the machinery ledger, **or carry its
   cron's substrate-issued run-report label (ADR-216)** …" — one canonical
   prose (the hook header), two pointers (rule → ADR → hook). Then `python3
   scripts/lint-rule-bodies.py --write`, and append one line to
   `.claude/rule-weakening-acks.txt` (`id|hash|date|8076|reason`) recording
   this as a narrowing recorded honestly (the #7425 shape): the exit is
   unavailable to any interactive filer and to every cron outside the map.

### Phase 4 — Run-report lifecycle  [FR4]

1. `_cron-shared.ts` `verifyScheduledIssueCreated` (L838-846): tighten the
   client-side guard to credit an issue only if `created_at ≥ since ||
   (updated_at ≥ since && state === "open")`. A sweeper close bumps
   `updated_at`; today the `since`/`state: "all"` query would credit that
   close as producer output during a verify-caller's retry window (seo-aeo
   fires Mon 11:00Z, the sweeper 12:00Z). Closed issues drop out;
   campaign-calendar's comment-bump keeps its issue open and stays credited.
   Row in `cron-shared.test.ts`; update the L797-812 comment.
2. `cron-stale-deferred-scope-outs.ts`: add `sweepRunReports(octokit, now)`
   in its **own** `step.run("sweep-run-reports")` after the scope-out step,
   with its own catch setting the shared `sweepFailed` (a search fault must
   not replay the already-completed scope-out arm on the Inngest retry), and
   a separate `runReports: { closed, skipped, deferred }` key on
   `SweepResult`. For each `RUN_REPORT_CRONS` row with `closeAfterDays !==
   null` (campaign-calendar and legal-audit excluded by construction; a test
   asserts neither label is ever queried): cutoff = `now − closeAfterDays`;
   query `repo:… is:issue is:open author:app/soleur-ai label:"<label>"
   created:<cutoff sort:created-asc` (`created:`, not `updated:` — triage
   labelling bumps `updated_at`; `author:app/soleur-ai` so a person's issue
   wearing a `scheduled-*` label is never a candidate). `SweepCandidate`
   (L194-205) gains `body` and `created_at`. Per candidate, in order: title
   does not start with `RUN_REPORT_TITLE_PREFIX` → skip (`reason:
   "not-run-report-shape"` — this is what closes the file-and-vanish path);
   kill-switch labels (`do-not-autoclose`, `keep-open`) → skip;
   `action-required` → skip; body starts with `AUDIT_SELF_REPORT_BODY_PREFIX`
   (import from `_cron-shared.ts:954`) or title contains `FAILED` → skip
   (`reason: "failed-report"`); non-bot comment → skip (the human-triage
   block L422-465, factored into a helper); `RUN_REPORT_COMMENT_MARKER =
   "<!-- soleur:auto-close-run-report -->"` already present → skip the
   comment POST only, still PATCH the close (POST and PATCH are separate
   `withGithubRetry` wrappers, L536-560). Then comment + close with
   `state_reason: "completed"`. One cap: `MAX_RUN_REPORT_CLOSES_PER_RUN =
   25` (the 43 digests drain over two daily fires). Every request through
   `withGithubRetry`. `PRODUCT_FACING_LABELS` is **not** consulted on this
   arm (inline comment: priority/type/domain on a run-report are daily-triage
   noise — #8027's `p1-high` — and `action-required` is checked explicitly).
3. Export the new constants + `sweepRunReports` via `__TESTING__` (L750-763).
4. `cron-daily-triage.ts:69`: extend the jq predicate with
   `and (.labels|map(.name)|any(startswith("scheduled-"))|not)`.
5. Tests (RED first) in `cron-stale-deferred-scope-outs.test.ts` beside
   L222-245: closes a 10-day-old SUCCESS community digest; skips a FAILED
   body prefix; skips a `FAILED` title; skips `keep-open`; skips
   `action-required`; skips a human-commented one; does NOT skip a
   `priority/p1-high` digest; cap: 26 eligible → exactly 25 closed + 1
   deferred (asserted as counts); skips a finding-shaped title carrying the
   label; query never names `scheduled-campaign-calendar` or
   `scheduled-legal-audit`; a 20-day-old weekly roadmap review is NOT
   closed (27 d); marker-present → PATCH without POST; a search fault in the
   run-report step leaves the scope-out result intact.
   `cron-daily-triage.test.ts`: the prompt's jq predicate contains the
   `scheduled-` exclusion.

### Phase 5 — Interactive-gate false denies  [FR7]

1. `.claude/hooks/lib/incidents.sh` (L359-364): `strip_command_bodies` is
   one perl call with three substitutions (heredoc, double-quoted,
   single-quoted). Factor the heredoc regex into one shared variable and a
   `strip_heredocs` function that applies the **first** substitution only;
   `strip_command_bodies` keeps its single perl call using the shared
   regex (six other hooks consume it).
2. `guardrails.sh` L451: tokenize `strip_heredocs "$COMMAND"` instead of the
   raw command. If `xargs -n1` still exits non-zero (unbalanced quoting
   outside a heredoc), **deny** with
   `BLOCKED: the command could not be tokenized (unbalanced quoting); write
   the body to a file and pass --body-file` — fail-closed and actionable.
   No whitespace-split fallback: a quoting-blind tokenizer over a corpus
   still containing `--body "… --label meta/machinery …"` would reopen the
   bare-token escape (`2026-09-10-every-escape…`) and could set `_ext_repo=1`
   on the repo check (L447), which also reads `_repo_toks`.
3. L616-628: wrap the unreadable-`--body-file` deny in
   `if [[ "$_fj_pass" == 0 ]]` so an exit-1 filing is never refused for a body
   it does not need. The declared-but-unreadable deny stays for exits 2/3.
4. `guardrails.test.sh`: rows in §Guard 3, plus a regression pin (already
   true today because `_gh_create`, L434, reads `$SCAN`): a `gh issue create`
   that appears only inside a heredoc body does not trigger the filing gate.
   Bump `MIN_ASSERTIONS` as a stated sum (`106 + <rows added>`). Run the
   suite from a non-git tmp CWD as well as the worktree.

## Files to Edit

- `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs` — parser, `labelTokenEquals`, exit 0, deny text
- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — derived `CRON_RUN_REPORT_LABELS`, directive line, self-test probes, `ParsedEvalResult.filingDenials`, marker emit
- `apps/web-platform/server/inngest/functions/_cron-shared.ts` — `verifyScheduledIssueCreated` open-or-created guard + comment
- `apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts` — `sweepRunReports` step, constants, `SweepResult.runReports`, `__TESTING__`
- `apps/web-platform/server/inngest/functions/cron-daily-triage.ts` — jq exclusion (L69)
- `apps/web-platform/test/server/inngest/cron-bash-allowlist-hook.test.ts`
- `apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts`
- `apps/web-platform/test/server/inngest/cron-shared.test.ts`
- `apps/web-platform/test/server/inngest/cron-stale-deferred-scope-outs.test.ts`
- `apps/web-platform/test/server/inngest/cron-daily-triage.test.ts`
- `scripts/issue-flow-measure.sh` — lines 1c/1d
- `.github/workflows/scheduled-machinery-drain.yml` — `-label:keep-open` on both pool queries; `keep-open` on create
- `plugins/soleur/skills/drain-labeled-backlog/scripts/group-by-area.sh` — kill-switch exclusion for the machinery label (L116-117)
- `plugins/soleur/test/machinery-drain-floor.test.sh` — one row
- `.claude/hooks/lib/incidents.sh` — `strip_heredocs`, shared regex
- `.claude/hooks/guardrails.sh` — tokenizer + ordering
- `.claude/hooks/guardrails.test.sh` — rows + floor sum
- `AGENTS.rules.md` — rule body (L89)
- `.claude/rule-body-hashes.txt` — regenerated by `--write`
- `.claude/rule-weakening-acks.txt` — one ack line
- `knowledge-base/engineering/architecture/decisions/ADR-216-machinery-ledger-and-filing-time-lever.md` — addendum
- `knowledge-base/engineering/architecture/decisions/ADR-058-file-driven-per-cron-mcp-allowance-in-the-containment-hook.md` — one-line cross-reference
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` — marker row

## Files to Create

- `apps/web-platform/server/inngest/functions/_cron-run-reports.ts` — leaf: `RUN_REPORT_CRONS`, `RUN_REPORT_TITLE_PREFIX`
- `apps/web-platform/test/server/inngest/cron-run-report-labels-parity.test.ts` — parity (i)–(iii)
- `plugins/soleur/test/issue-flow-measure.test.sh`
- `scripts/followthroughs/run-report-exit-first-contact-8076.sh`

## Open Code-Review Overlap

None — 65 open `code-review` issues checked against every path above
(`ISSUES_JSON` query 2026-09-11, zero body matches).

## User-Brand Impact

- **If this lands broken, the user experiences:** a scheduled run-report cron
  (community digest, content generator, roadmap review, competitive analysis,
  growth/SEO/architecture audits, campaign calendar, legal audit) that cannot file its REQUIRED issue loses the run's artifacts —
  the digest file is never committed — and the heartbeat reads it as silence;
  or, the other way, a directive too wide waves audit exhaust past the gate
  and re-inflates the backlog the gate exists to shrink.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the
  deny log is written by the hook into the agent-denied `.claude/` directory
  and carries only the first three command tokens and label tokens — never a
  body, never a credential; the marker carries counts and reasons. No user
  data path is touched.
- **Brand-survival threshold:** `single-user incident` (carried forward from
  the brainstorm; `requires_cpo_signoff: true` — CPO reviewed the brainstorm
  and the assessment is carried forward in §Domain Review).

## Observability

```yaml
liveness_signal:
  what: "Sentry cron monitors scheduled-stale-deferred-scope-outs (sweeper, daily 12:00 UTC) and the per-cron Sentry monitors of the nine verify-caller crons; cron-cloud-task-heartbeat asserts each run-report issue exists within maxGapDays"
  cadence: "daily (sweeper, heartbeat); per-run (run-report crons)"
  alert_target: "Sentry issue → operator email"
  configured_in: "apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts (SENTRY_MONITOR_SLUG), cron-cloud-task-heartbeat.ts (TASK_INVENTORY), infra/sentry/*.tf"

error_reporting:
  destination: "Sentry (web-platform project, SENTRY_DSN); pino WARN → Vector → Better Stack for the new marker"
  fail_loud: "a SOLEUR_CRON_FILING_DENY marker whose fn + runStartedAt also appear on a scheduled-output-missing Sentry event is the loud pair: the cron was denied and did not recover; the marker alone means denied-then-complied"

failure_modes:
  - mode: "directive not delivered (map entry missing / allowlist write failed)"
    detection: "runHookSelfTest probe (a) fails → spawn aborts → cron FAILED self-report + Sentry error"
    alert_route: "Sentry issue alert"
  - mode: "cron denied and complied by another exit (relabel)"
    detection: "SOLEUR_CRON_FILING_DENY count>0 with no scheduled-output-missing event for that run; measurement line 1d rising while 1 is flat"
    alert_route: "weekly measurement issue #8068; Better Stack query"
  - mode: "cron denied and did not comply"
    detection: "SOLEUR_CRON_FILING_DENY marker AND a scheduled-output-missing Sentry event with the same fn + runStartedAt; heartbeat silence at maxGapDays"
    alert_route: "Sentry cron monitor + [cloud-task-silence] issue"
  - mode: "sweeper closes a FAILED report"
    detection: "unit tests on the body-prefix and title guards; reopen count in measurement line 2 (marker-attributed)"
    alert_route: "weekly measurement issue"
  - mode: "sweeper GitHub fault"
    detection: "withGithubRetry absorbs; exhausted retries surface via the existing Inngest retry then Sentry"
    alert_route: "Sentry issue alert"

logs:
  where: "web-platform container pino stdout → Vector → Better Stack (WARN+)"
  retention: "Better Stack archive per plan tier"

discoverability_test:
  command: "grep -c SOLEUR_CRON_FILING_DENY apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts knowledge-base/engineering/operations/runbooks/betterstack-log-query.md"
  expected_output: "both files report >= 1 — the marker is emitted by the substrate and its runbook recipe exists; the live rows are read with `bash scripts/betterstack-query.sh --since 7d --grep SOLEUR_CRON_FILING_DENY` under Doppler prd_terraform (zero rows on a healthy week)"
```

## Guard Contract

### Guard 1 — run-report exit (cron hook)

**Property.** A `gh issue create` segment passes exit 0 iff a real label token
equals the `run-report-label` directive written into THIS spawn's
`cron-allow.txt`; no other input opens it.

**Assembly.** The chokepoint is `filingJustificationReason` called from
`decide()` after `segmentMatchesAllowlist`; its inputs are the dequoted
segment tokens (six label spellings via `labelTokenEquals`) and
`parseAllowlist().runReportLabel`, whose only producer is `allowlistLines`
in the substrate, keyed on the derived `CRON_RUN_REPORT_LABELS`. Parity (i)
binds the map to the `resolveOutputAwareOk` call sites.

**Mutation matrix.**

| # | Mutation | Must go RED via |
|---|---|---|
| 1 | Remove the `run-report-label` regex from `parseAllowlist` | allow-case test denies; self-test probe (a) aborts |
| 2 | Match `runReportLabel` against the raw segment string instead of tokens | prose-mention test (`--body "run-report-label X"`) passes when it must deny |
| 3 | Drop the comma-anchor (`includes(label)`) | `--label <label>x` and `--label foo/<label>` tests pass when they must deny |
| 4 | Evaluate exit 0 before `segmentMatchesAllowlist` | narrowing test: a cron whose allowlist omits `gh issue create` is allowed when it must deny |
| 5 | Substrate pushes the directive for every cron | ux-audit delivery test finds a directive that must be absent |
| 6 | Drop a `resolveOutputAwareOk` caller from `RUN_REPORT_CRONS` | parity (i) |
| 7 | Guard's own dispatch: `filingJustificationReason` returns `null` unconditionally | the existing "no exit taken → deny" row (hook test L569+) |
| 8 | `labelTokenEquals` extraction regresses exit 1 | the existing exit-1 rows (L577-584) |

**Harness rows.** H1 delete the `describe("run-report exit")` block → the
hook suite's per-file assertion floor (add one, derived as main + rows) trips;
H2 must-PASS non-canonical: `--label scheduled-community-monitor,type/bug`
(comma-joined, directive first), `-l scheduled-community-monitor`, and
campaign-calendar's `--title "[Content] Overdue: x" --label action-required,scheduled-campaign-calendar`
all pass; H3 must-PASS: the same segment inside a `&&` chain after an
allowlisted `bash plugins/…/community-router.sh` call passes.

### Guard 2 — run-report sweeper never closes a FAILED, human-touched, or non-report issue

**Property.** `sweepRunReports` closes an issue only if it is a
`RUN_REPORT_CRONS` label with `closeAfterDays !== null`, by `app/soleur-ai`,
older than `closeAfterDays` by `created_at`, `[Scheduled] `-titled, not
FAILED (body prefix OR title), carries no kill-switch or `action-required`
label, has no non-bot comment, and is under the cap — and its close is never
credited as producer output by `verifyScheduledIssueCreated`.

**Assembly.** One function in its own step; candidates come from the per-label
search query; guards run in a fixed order before any write. The FAILED signal
has two producers (prompt-path title, handler-path body prefix) and both are
checked. The verify-side guard is a second chokepoint in `_cron-shared.ts`.

**Mutation matrix.**

| # | Mutation | Must go RED via |
|---|---|---|
| 1 | Use `updated:` instead of `created:` in the query | query-string assertion |
| 2 | Drop the body-prefix guard | #8027-shaped fixture (normal title, FAILED body) is closed |
| 3 | Drop the title `FAILED` guard | `- FAILED` title fixture is closed |
| 4 | Drop `action-required` from the skip set | fixture with `action-required` is closed |
| 5 | Re-add `PRODUCT_FACING_LABELS` to this arm | `priority/p1-high` digest fixture is NOT closed (must be) |
| 6 | Change a row's `closeAfterDays` to 1 | 20-day-old roadmap review is closed (must not) + parity (iii) |
| 7 | Guard dispatch: return before the loop | "closes a 10-day-old SUCCESS digest" fails |
| 8 | Second member: 26 eligible, cap 25 → exactly 25 closed, 1 deferred | cap test (counts) |
| 9 | Drop the title-shape guard | label-bearing finding-shaped fixture is closed (must not) |
| 10 | Drop `author:app/soleur-ai` from the query | query-string assertion |
| 11 | Iterate rows with `closeAfterDays: null` | `scheduled-legal-audit` / `scheduled-campaign-calendar` appears in a query (must not) |
| 12 | Marker-present → skip the PATCH too | fixture with marker + open state stays open (must close) |
| 13 | Revert the verify guard to `updated_at`-only | `cron-shared.test.ts`: a closed issue updated in-window is credited (must not) |
| 14 | Run the arm inside the scope-out step | a run-report search fault re-runs the scope-out arm (assert single execution) |

**Harness rows.** H1 the suite's mocked `/search/issues` returns an empty page
→ the "closes one" test fails (not vacuously green); H2 must-PASS
non-canonical: a digest with `priority/p2-medium, type/bug, domain/operations`
(the exact #8027 label set minus action-required) IS closed.

### Guard 3 — interactive gate tokenizer and ordering

**Property.** For any command whose real flag tokens carry `--label
meta/machinery`, the gate passes exit 1 regardless of heredoc-body content
or the readability of `--body-file`; a command that cannot be tokenized is
denied with an actionable message, never passed on a guess.

**Assembly.** `guardrails.sh` L451 tokenizer (one site) feeds both the repo
check and the filing check; the body-file deny at L616-628 is the only deny
between exit-1 evaluation and the exit-2/3 corpus read.

**Mutation matrix.**

| # | Mutation | Must go RED via |
|---|---|---|
| 1 | Remove heredoc stripping | apostrophe-in-heredoc + `--label meta/machinery` → denied |
| 2 | Replace the unbalanced-quoting deny with a whitespace-split pass | `--body "x --label meta/machinery y"` with an unbalanced quote passes (must deny) |
| 3 | Restore the unconditional body-file deny | exit-1 + nonexistent `--body-file` → denied |
| 4 | Tokenize the raw command instead of the stripped one | same as 1 |
| 5 | Dispatch: skip the filing block entirely | existing AC7 "no exit → deny" row |

**Harness rows.** H1 `MIN_ASSERTIONS` stated as a sum; deleting the new rows
trips it; H2 must-PASS non-canonical: `--label type/bug,meta/machinery`
inside a command whose heredoc body contains an apostrophe; must-DENY with
the new message: an apostrophe inside `--title` (unbalanced quoting outside
a heredoc).

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-216** (no new ordinal). Decision delta: a fourth exit exists for
the population whose run completion is verified by its own scheduled issue
(the `resolveOutputAwareOk` callers), keyed on a substrate-issued directive
the agent cannot read or write; the "deliberately no fourth" section is amended
to "no fourth *narratable* exit," with the population enumerated and the D1
outcome recorded. `## Alternatives Considered` gains: once-per-run marker
(rejected: allow ≠ success), handler-side filing (rejected: the issue is the
proof-of-output), `cronName` in argv/env (rejected per ADR-058), a new closer
(rejected: sweeper already carries the guards), a hook-written deny log
(rejected: `permission_denials` already carries every deny), a title-shape
half on the hook exit (rejected: campaign-calendar's `[Content] Overdue:`
filings). ADR-058 gets a one-line
cross-reference under Consequences ("third directive shape:
`run-report-label`").

### C4 views

No C4 impact. Enumerated against all three model files
(`model.c4`, `views.c4`, `spec.c4`): external actors — none new (GitHub is
already modelled as the issue host; the scheduled agents are already the
Inngest cron container); external systems — none new (Better Stack is the
existing log sink; the marker is a new log line, not a new edge); containers/
data stores — none new (the jsonl is a file inside an ephemeral workspace, not
a store); access relationships — unchanged. `grep -n "containment\|cron-allow\|heartbeat\|filing" model.c4` returns 0/0/13(Better Stack uptime)/2(generic prose) hits, none modelling this mechanism. The `c4-count-parity` gate is run at /work (AC15) because it, not the actor rubric, sees the derived cardinalities `model.c4` embeds in edge prose.

### Sequencing

The ADR amendment lands in Phase 6 of the same PR; nothing is deferred.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-bash-allowlist-hook.test.ts` green, including the Guard-1 matrix rows and H2/H3.
- [x] AC2 `./node_modules/.bin/vitest run test/server/inngest/cron-claude-eval-substrate.test.ts test/server/inngest/cron-run-report-labels-parity.test.ts` green: every `resolveOutputAwareOk(` call site has a `RUN_REPORT_CRONS` row with its `SENTRY_MONITOR_SLUG` (and vice-versa, legal-audit per D1), every row's `fn` has `gh issue create` in `CRON_BASH_ALLOWLISTS`, and `closeAfterDays === 3 × maxGapDays` for the `TASK_INVENTORY` rows.
- [x] AC3 The written `cron-allow.txt` for `cron-ux-audit` carries no `run-report-label` line (delivery negative test).
- [x] AC4 `parseClaudeResultLine` tests: two filing-shaped `permission_denials` + one non-filing → `filingDenials: 2`; the `SOLEUR_CRON_FILING_DENY` WARN is emitted once with `count: 2` and not at all at 0.
- [x] AC5 `bash plugins/soleur/test/issue-flow-measure.test.sh` green: lines `1c.` and `1d.` printed from stubbed counts; line `1.` unchanged; label array ≡ `_cron-run-reports.ts` labels by grep; 1d query carries `-label:keep-open`.
- [x] AC6 `bash plugins/soleur/test/machinery-drain-floor.test.sh` green with the `-label:keep-open` row; `bash plugins/soleur/skills/drain-labeled-backlog/scripts/group-by-area.sh` applies the kill-switch exclusion for `meta/machinery` (test row in that script's suite, or a shell assertion in the drain-floor suite).
- [x] AC7 `./node_modules/.bin/vitest run test/server/inngest/cron-stale-deferred-scope-outs.test.ts test/server/inngest/cron-shared.test.ts` green: Guard-2 matrix, incl. the #8027-shaped fixture NOT closed, the `priority/p1-high` digest closed, neither `scheduled-legal-audit` nor `scheduled-campaign-calendar` ever queried, and the verify-side open-or-created guard.
- [x] AC8 `grep -c 'startswith("scheduled-")' apps/web-platform/server/inngest/functions/cron-daily-triage.ts` = 1.
- [x] AC9 `bash .claude/hooks/guardrails.test.sh` green from the worktree AND from `cd "$(mktemp -d)" && bash <abs-path>/guardrails.test.sh`; `MIN_ASSERTIONS` is written as a sum ≥ 106 + rows added.
- [x] AC10 FR7 rows in `guardrails.test.sh`: (a) a command whose heredoc body contains an apostrophe and whose flags carry `--label meta/machinery` yields no deny; (b) exit-1 with `--body-file /nonexistent` yields no deny; (c) exit-2 with `--body-file /nonexistent` still denies; (d) an unbalanced quote outside a heredoc denies with the tokenizer message.
- [x] AC11 `python3 scripts/lint-rule-bodies.py --check --base origin/main` passes; `.claude/rule-weakening-acks.txt` has one new line for `wg-defer-only-after-inline-triage` naming 8076; `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1` exits 0.
- [x] AC12 `grep -c "Addendum 2026-09-11" knowledge-base/engineering/architecture/decisions/ADR-216-machinery-ledger-and-filing-time-lever.md` = 1 and the section names every cron in `RUN_REPORT_CRONS` and states the population key ("calls `resolveOutputAwareOk`").
- [x] AC13 `grep -c SOLEUR_CRON_FILING_DENY knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` ≥ 1.
- [x] AC14 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [x] AC15 `bash plugins/soleur/test/c4-count-parity.test.sh` green (no-C4-impact claim backed by the gate, not by reasoning).
- [ ] AC16 PR body carries `Closes #8076`; #8076 carries the follow-through directive and `follow-through` label (AC18).

### Post-merge (automated)

- [ ] AC17 `gh run list --workflow=web-platform-release.yml -L 1` green (the container restart on merge delivers the substrate + hook; no separate step); `gh issue view 8068 --json labels --jq '[.labels[].name]'` includes `keep-open` (one-time write done in /work).
- [ ] AC18 First live contact, verified by the follow-through sweeper: after 2026-09-14T09:00Z `gh issue list --label scheduled-roadmap-review --limit 1 --json labels` shows only `scheduled-roadmap-review` (and after 2026-09-13T02:00Z the same for `scheduled-architecture-diagram-sync`), and `bash scripts/betterstack-query.sh --since 2d --grep SOLEUR_CRON_FILING_DENY` returns 0 rows for `fn: cron-roadmap-review`. Enrolled per Phase 2.9.1: script `scripts/followthroughs/run-report-exit-first-contact-8076.sh` (exit 0 when both hold), directive `<!-- soleur:followthrough script=scripts/followthroughs/run-report-exit-first-contact-8076.sh earliest=2026-09-15 secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->` on #8076 + `follow-through` label; the three secrets are wired into `.github/workflows/scheduled-followthrough-sweeper.yml` if absent.
- [ ] AC19 After the first 12:00Z sweeper fire post-merge, `gh api "search/issues?q=repo:jikig-ai/soleur+is:issue+is:closed+label:scheduled-community-monitor+%22soleur:auto-close-run-report%22+in:comments" --jq .total_count` ≥ 25 (the per-run cap; 43 eligible today; attributed by the arm's own marker — not an open-count, which any concurrent filing would move) and `gh issue view 8027 --json state --jq .state` = OPEN (FAILED report untouched). Same follow-through script, second assertion.
- [ ] AC20 Next `issue-flow: weekly measurement` update on #8068 shows lines `1c.` and `1d.`, and the drain outcome `before=` excludes #8068.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from the brainstorm's `## Domain Assessments`, 2026-09-11; no fresh sweep)

### Engineering

**Status:** reviewed (carry-forward, CTO)
**Assessment:** Directive exit is sound and is not the exit ADR-216 cut; requires an ADR amendment. Once-per-run marker feasible but must not be built (allow ≠ success; legal-audit files up to five per run under its label). Denials reach Better Stack via a hook-appended jsonl read post-exit and emitted as a pino WARN marker; child stdout is `logger.info` and never leaves the host. Handler-side filing rejected: the issue is the proof-of-output.

### Legal

**Status:** reviewed (carry-forward, CLO)
**Assessment:** Nothing legal turns on lifecycle or labels — Article 30 PA-32 §(f) already records the community-observation output as indefinite/permanent with GitHub as host. Editing the hook files carries no ack obligation; editing `AGENTS.rules.md:89` does (ADR-092), recorded as a narrowing. Pre-existing PA-32 §(a)(i) gap (the `[Scheduled]` issue surface is unrecorded) is documented in the brainstorm as a deferral for the legal-compliance-auditor.

### Product/UX Gate

**Tier:** none
**Decision:** reviewed (carry-forward, CPO)
**Agents invoked:** cpo (brainstorm)
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface — no path in Files to Edit/Create matches the UI-surface term list; the mechanical override did not fire)

#### Findings

No product consumer reads `scheduled-*` issues (operator-digest reads `action-required` only; ticket-triage never mentions them; the heartbeat queries `state: all`), so closing SUCCESS run-reports costs the operator nothing. Daily triage mislabelled 21 digests `p1-high` and hid #8027's "Credit balance is too low"; FAILED reports are the only run-reports carrying operator-relevant information and are never auto-closed. Productize candidate (run-report-as-issue is the wrong shape) is recorded in the brainstorm as a deferral, out of scope here. CPO sign-off: the plan implements the approach the CPO reviewed at brainstorm; `requires_cpo_signoff: true` is satisfied by that carry-forward plus the `user-impact-reviewer` at PR review.

## Plan Review (2026-09-11)

Panel: dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer
(per-mechanism), architecture-strategist, spec-flow-analyzer (Phase 3 + a
re-validation pass), cto (devex). Scoped advisor consult (ADR-083, `fable`)
ran before the panel.

**Mechanical (applied):** population keyed on the `resolveOutputAwareOk` call
sites with grep parity (DHH#1, Kieran#2, CTO#1, spec-flow#1, arch#2); hook
title-half cut — campaign-calendar's `[Content] Overdue:` filings (Kieran#1,
arch#1); deny channel = `permission_denials[]`, measured (simplicity (c)) —
no hook write, no truncate, no `SpawnResult` field, no caller edits (DHH#3);
leaf keeps only `RUN_REPORT_CRONS`, `TASK_INVENTORY` untouched (DHH#2,
simplicity (b)); literal `closeAfterDays` with a `3×maxGapDays` parity row
(DHH#2, CTO#4a); campaign-calendar `closeAfterDays: null` (spec-flow#12);
verify-side open-or-created guard (spec-flow#7, arch#6); own `step.run` for
the arm (arch#5); single cap (simplicity (e)); `-label:keep-open` on the
pool and 1d queries, `keep-open` on #8068, `group-by-area.sh` exclusion
(spec-flow#8/#14, Kieran#4, simplicity (d)); no whitespace tokenizer fallback
(DHH#5, simplicity (g), arch#7); heredoc regex shared with
`strip_command_bodies` (Kieran#5, arch#7); AC19 marker-attributed (standing
check, Kieran#3); AC6 keep-open assertion moved post-merge (Kieran#8); phases
3+6 merged (DHH#6); citations (Kieran#5).

**User-Challenge D1** — surfaced with the 5-line frame; operator chose
**include legal-audit** (ten rows).

**Taste** — DHH's split of Phase 5 into its own PR: surfaced; operator chose
**keep in this PR**.

## Test Scenarios

- Hook allows `gh issue create --title t --label scheduled-community-monitor --milestone "Post-MVP / Later"` when the directive is present; denies the identical command when absent (P1, P3).
- Hook denies `gh issue create --title t --body "run-report-label scheduled-community-monitor"` with the directive present (P2).
- Substrate self-test aborts the spawn when probe (a) is denied by a mutated hook (Guard 1 #1).
- Denials: a result event with two filing-shaped `permission_denials` → one `SOLEUR_CRON_FILING_DENY` WARN with `count: 2`; with the issue missing, the existing `scheduled-output-missing` event shares `fn` + `runStartedAt` (P9).
- Sweeper: 43 eligible digests, cap 25 → 25 closed, 18 reported deferred, all with the marker comment (P7).
- Sweeper: #8027 fixture (normal title, FAILED body prefix, `p1-high`) → skipped with `reason: failed-report`.
- Measurement stub: `filed=330`, `1c=54`, `1d=2`; VERDICT line unchanged (P5).
- Interactive gate: heredoc with apostrophe + real label → allow; exit-1 + missing body file → allow; exit-2 + missing body file → still deny (P12).

## Dependencies & Risks

- **Time.** architecture-diagram-sync fires **Sun 2026-09-13 02:00Z**;
  growth-audit Mon 07:00Z, roadmap-review Mon 09:00Z, seo-aeo-audit Mon
  11:00Z, campaign-calendar Mon 16:00Z, content-generator Tue 10:00Z. Merge
  before Saturday night or each is denied at its first fire with persistence
  refused; community-monitor will keep complying via exit 1 daily until then (any such digest
  landing before merge is relabelled with `gh issue edit --remove-label` in
  the /work session).
- **Sweeper first fire closes up to 25 issues.** Bounded by the cap; every guard
  fails toward skipping; `state_reason: completed` is reversible by reopen,
  and reopens are counted by the measurement (marker-attributed).
- **D1 (legal-audit, decided: include).** Audit findings pass on their
  label, bounded by `CAP_PER_RUN=5` + quarterly cadence + title idempotency,
  never swept, counted by line 1c. Widening the exit to a finding-shaped
  filer is recorded in the ADR-216 addendum as the one deliberate exception
  to the verify-contract key.
- **Rule-body edit is security-tagged.** ADR-092 requires the ack line; the
  hash manifest is regenerated with `--write`; the linter's own classifier is
  not touched.
- **`permission_denials` is a Claude Code result-event contract**, measured
  at plan time on the installed CLI; a future CLI that drops it would zero the
  marker silently. AC4's fixture pins the shape; the follow-through script
  (AC18) is the live check.
- **`c4-count-parity`** may red on an unrelated count drift already on main;
  if so, fix the count in the same PR (it is the gate for the no-impact claim).

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Raise exit 1's price (`Machinery: <path>`) | Answers a different question; would not have changed #8059. Deferred until line 1d can say whether it is needed. |
| Handler files the run-report (Octokit, like #4960) | The issue is the proof-of-output; four prompts + the liveness contract need a new completion artifact. Medium-large; revisit only if the lifecycle becomes handler-owned. |
| Once-per-run marker file | PreToolUse fires on allow, not success; a `gh` retry would be denied and the REQUIRED filing lost. |
| `cronName` in hook argv/env | Rejected by ADR-058: agent-readable via `ps`, duplicates the map in the hook. |
| New closer cron for run-reports | Duplicates the sweeper's window/cap/kill-switch/human-triage guards and Sentry monitor. |
| New ADR ordinal | The refuted claim is ADR-216's; amending avoids the ordinal-collision class. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- The FAILED self-report has the **normal** title; guard on `AUDIT_SELF_REPORT_BODY_PREFIX` (imported), not on title alone.
- `updated:` is poisoned by triage labelling; the run-report arm queries `created:`.
- The hook must remain `exit 0` on every path (`main()` L683-695 converts any throw to a deny).
- `RUN_REPORT_CRONS` lives in the leaf `_cron-run-reports.ts`; the substrate and the sweeper import the leaf, never a cron function's module. `TASK_INVENTORY` stays in the heartbeat. The directive population is keyed on "calls `resolveOutputAwareOk`" (nine), NOT on the heartbeat inventory (five) — parity (i) greps the call sites, not comments.
- Hook denies are read from the result event's `permission_denials[]`; there is no hook-side write and nothing to truncate.
- campaign-calendar files `[Content] Overdue:` issues under its scheduled label and comment-bumps a standing issue: it gets the directive (label-only exit) and is never swept.
- Heredocs cannot reach the cron hook (`dangerousMetacharReason` L279/L290 denies multiline and `<`), so FR7 is interactive-only.
- The run-report exit is label-only; the sweeper closes only `[Scheduled] `-titled, `app/soleur-ai`-authored issues. A finding that borrows the label is never auto-closed and is counted by line 1c.
- Run `guardrails.test.sh` from a non-git CWD too (`block-commit-on-main` reads ambient CWD).
- Rule-body edit is a three-step: edit → `lint-rule-bodies.py --write` → ack line. Never in the same diff as a linter change.
- ADR-216 is amended, not renumbered; grep the plan/spec/tasks for `ADR-217` before ship — none should exist.

## References & Research

- Brainstorm: `knowledge-base/project/brainstorms/2026-09-11-filing-gate-run-report-exit-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-filing-gate-run-report-exit/spec.md`
- Learning: `knowledge-base/project/learnings/2026-09-11-a-filer-with-no-honest-exit-takes-the-free-one-at-any-price.md`
- ADR-216, ADR-058, ADR-092 (ack gate), ADR-155 (cross-gate markers), ADR-131 (inline threshold)
- `knowledge-base/project/learnings/2026-09-10-every-escape-my-mutations-could-not-reach.md`
- `knowledge-base/engineering/operations/post-mortems/stale-deferred-scope-outs-cron-false-page-postmortem.md`
