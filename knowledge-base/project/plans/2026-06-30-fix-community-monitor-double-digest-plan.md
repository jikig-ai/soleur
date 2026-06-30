---
title: "fix: cron-community-monitor double-files the daily digest (two eval runs, not eval+audit)"
issue: 5751
type: bug
lane: cross-domain
brand_survival_threshold: none
created: 2026-06-30
status: draft
---

# fix: `cron-community-monitor` double-files the daily `[Scheduled] Community Monitor` issue

🐛 **Bug** — Closes #5751

## Enhancement Summary

**Deepened on:** 2026-06-30 — architecture-strategist, spec-flow-analyzer, learnings-researcher.

### Key corrections (fold into design before /work)

1. **Fix-layer ORDER flipped — handler-side LIST-dedup is PRIMARY; Inngest `idempotency` is UNUSABLE here.**
   `idempotency` is a bare CEL string evaluated against the *triggering event's*
   payload (`node_modules/inngest/types.d.ts:1357,1417`); the two triggers have
   **disjoint** payloads — cron timer is `{ data: { cron } }` with no date field
   (`types.d.ts:158-164`), the manual event has its own `data`. No shared date key
   → any CEL expr is empty on one trigger → **empty-key collapse → zero digests**.
   `debounce` merely delays + drops on container swap. The cited precedent
   (`agent-on-spawn-requested.ts:967`) is single-trigger and does not transfer.
2. **The title-`startsWith` dedup COLLIDES with the audit FAILED stub.**
   `ensureScheduledAuditIssue` files its FAILED self-report under the **byte-identical**
   title `[Scheduled] Community Monitor - <date>` (`_cron-shared.ts:1068`), as does the
   no-platform `[Scheduled] Community Monitor - FAILED` path (prompt :169-170). A
   title-only dedup would treat an earlier FAILED stub as "digest exists" and
   **suppress the real digest forever** on a same-day recovery run. The dedup MUST
   distinguish a real digest (body/marker check, not title alone).
3. **The dedup-skip path goes RED unless the heartbeat window is reconciled.**
   `verifyScheduledIssueCreated` filters `updated_at >= runStartedAt` of *this*
   invocation (`_cron-shared.ts:691-694`). An H-A second invocation has a later
   `runStartedAt`, so the first issue falls *before* its window → `heartbeatOk=false`
   → RED + audit fallback (which then dedup-suppresses, filing nothing). The skip path
   must explicitly post OK (early `return {ok:true}` before the verify step is the
   simplest). H-B is safe (runStartedAt is replay-memoized, `:313-316`).
4. **Pre-spawn dedup as its own `step.run` is MEMOIZED → does NOT cover H-B.** If
   Phase 0 lands on H-B (eval step re-fires its `gh issue create` side effect on
   retry), the fix must live at the step/prompt boundary — switch the in-prompt
   `DEDUP RULE` off `gh issue list --search … in:title` (stale SEARCH index) onto the
   `GET /issues?labels=…` LIST endpoint (fresh primary index), or make issue-create
   idempotent. **Phase 0's H-A vs H-B verdict changes the fix LOCATION, not just the layer.**
5. **The test seam must observe a real count, not a mock.** The existing
   `cron-community-monitor-heartbeat.test.ts` mocks BOTH the spawn and
   `ensureScheduledAuditIssue` → "issue-count==1" degenerates to "mock called once" (a
   proxy). The regression test needs a **fake GitHub issue store** (octokit stub) that
   both the dedup READ and the create path write through, so count is observable.

## Overview

`cron-community-monitor` files **two** `[Scheduled] Community Monitor - <date>`
issues on affected days (`#5737`+`#5740` 2026-06-30; `#5596`+`#5597` 2026-06-21;
`#5592`+`#5593` 2026-06-20), ~1.5–3.5 min apart, both authored by `app/soleur-ai`,
both carrying the `scheduled-community-monitor` label.

**The issue body's stated root cause is wrong** (see Premise Validation below).
The second issue is **not** the handler's `ensureScheduledAuditIssue` fallback —
it is a **second full eval-generated digest**. The real defect is that the
**claude-eval digest producer runs (and files an issue) twice** on affected days,
and the only guard against a duplicate (the in-prompt `DEDUP RULE`) is unreliable.

This plan is **investigation-first**: Phase 0 pins, from production `routine_runs`
+ the issue metadata, *which* dual-production mechanism fires before any code
changes. The fix layer is chosen by Phase 0's verdict, then locked with a
RED→GREEN regression test.

## Enhancement Summary (deepen-plan)

**Deepened:** 2026-06-30 · architecture-strategist + spec-flow-analyzer + learnings-researcher.

**Key corrections folded in:**

1. **Primary fix layer flipped.** Inngest `idempotency`/`debounce` is the WRONG primary
   guard here and is **dropped** to a documented non-option. The handler-side
   **LIST-endpoint date-dedup** is the primary fix. Rationale: the function has two
   triggers with **disjoint payload shapes** (cron timer `data:{cron}` —
   `inngest/types.d.ts:158-164` — vs the custom manual-trigger event); they share no
   date field, a CEL key referencing a field absent on one shape collapses to an empty
   key (over-suppression → zero digests), the idempotency window is a fixed 24h with no
   override (`types.d.ts:1357`), and idempotency does nothing for the retry hypothesis
   (H-B). The cited precedent `agent-on-spawn-requested.ts:967` is single-trigger and
   does not transfer.
2. **Why handler-side dedup is reliable here:** `concurrency:[{scope:"fn",limit:1}]`
   (`cron-community-monitor.ts:549-552`) **serializes** the two invocations, so the
   second's dedup read runs after the first's `gh issue create`; and the **issues LIST
   endpoint** (`GET /issues?labels=…&sort=created&desc`) hits the fresh primary index —
   unlike the current in-prompt `DEDUP RULE` which uses `gh issue list --search '… in:title'`
   (the **stale search index**, minutes-to-tens-of-minutes lag — the actual reason the
   LLM dedup misses). **Switching the dedup off SEARCH onto LIST is the core fix.**
3. **New zero-digest risks (P1) added to Sharp Edges:** (a) the audit fallback files its
   `Automated FAILED self-report` stub under the **byte-identical** title `[Scheduled]
   Community Monitor - <date>` (`_cron-shared.ts:1068`), and the no-platform path files
   `[Scheduled] Community Monitor - FAILED` — a bare `title.startsWith` dedup would treat
   either stub as "digest exists" and suppress the real digest forever; the dedup MUST
   exclude FAILED/audit bodies. (b) the dedup read must **fail-OPEN** (spawn on a GitHub
   error), mirroring `resolveOutputAwareOk` (`_cron-shared.ts:765-775`). (c) date anchor
   MUST be `runStartedAt.slice(0,10)` (replay-stable), never `new Date()` (`:1063-1065`).
4. **Heartbeat-window tension resolved (was unspecified).** On an H-A second invocation,
   `verifyScheduledIssueCreated` filters `updated_at >= runStartedAt(2)`, and the first
   issue's `updated_at` predates the second window → `heartbeatOk=false` → RED +
   `scheduled-output-missing`. So a dedup that skips the spawn would false-RED the skip
   path. Phase 2 now specifies the skip-path heartbeat mechanism. (Under H-B the window is
   safe — `runStartedAt` is memoized across replays at `:313-316`.)
5. **Test seam corrected.** The existing heartbeat test mocks BOTH the `claude-eval` spawn
   (which is what files the digest via `gh`) AND `ensureScheduledAuditIssue` → there is no
   real issue to count, so "issue-count==1" degenerates into a PROXY ("mock called once").
   The regression test MUST use a fake GitHub issue store (octokit stub) that BOTH the
   dedup read and the create path write through, so count is observable.

## Premise Validation (Phase 0.6)

The issue #5751 premise was probed against code + production before planning:

- **CITED: producer 2 = `ensureScheduledAuditIssue` audit fallback (`cron-community-monitor.ts:496-505`).**
  **STALE / FALSIFIED.** `ensureScheduledAuditIssue` (`_cron-shared.ts:1041-1133`)
  emits a **hardcoded** body beginning `Automated FAILED self-report from
  \`cron-community-monitor\`` with a `| Signal | Value |` table. The actual second
  issues (#5740, #5597, #5593) are **full digests** with live platform metrics
  (`## Platform Status`, `## Key Metrics`, follower counts) — verified by reading
  #5737 and #5740 directly via `gh issue view`. Neither matches the audit body.
  **The second issue is a second eval digest, not the audit fallback.**
- **CITED: `ensureScheduledAuditIssue` fires only when `heartbeatOk === false`.** TRUE
  (gating at `cron-community-monitor.ts:493-516`), **but irrelevant to the
  double-file**: the helper has a same-title dedup (`_cron-shared.ts:1091-1103`,
  `existing.data.some(i => i.title.startsWith("[Scheduled] Community Monitor - <date>"))`)
  that suppresses a second audit issue whenever the eval already filed
  `[Scheduled] Community Monitor - <date>`. So even when `heartbeatOk === false`,
  the audit fallback does **not** double-file. The audit path is a dead end for
  this bug.
- **CITED: leading hypothesis = `resolveOutputAwareOk` (`:415`) misses the eval issue → `heartbeatOk=false` → redundant audit issue.** Half-stale. `heartbeatOk=false`
  may well occur (and may explain #5732's `error` check-in via the same GitHub
  label-index lag), but it does **not** drive the double-file (audit fallback is
  dedup-suppressed). **Decouple:** the double-file is caused by the eval producing
  twice; the heartbeat status is a separate axis (#5732 / #5728 territory).
- **CITED: same root cause as #5732 / coordinate with #5728.** PARTIAL. #5732
  (fast-fail, CLOSED) and #5728 (heartbeat delivery, CLOSED) are distinct. A
  *possible* shared sub-cause is GitHub's eventual-consistency lag on the
  label-filtered issue list, which would degrade BOTH `verifyScheduledIssueCreated`
  (heartbeat) AND the in-prompt `DEDUP RULE` (double-file). Phase 0 confirms; this
  plan fixes ONLY the double-file and does not absorb #5728's delivery fix.
- **No new infra, no ADR mechanism cited.** The candidate fix uses the existing
  Inngest `idempotency`/`debounce`/`concurrency` config primitives (precedent:
  `agent-on-spawn-requested.ts:967` `idempotency: "event.data.actionSendId"`).

## Research Reconciliation — Spec vs. Codebase

| Issue-body claim | Codebase / production reality | Plan response |
|---|---|---|
| Second issue is the `ensureScheduledAuditIssue` audit fallback (compact format) | #5740/#5597/#5593 are full eval **digests** with live metrics; audit body is a hardcoded "FAILED self-report" table | Re-target root cause to **dual eval production**; Phase 0 confirms the invocation count |
| Audit fallback fires because `heartbeatOk=false` | Audit fallback's same-title dedup (`_cron-shared.ts:1101`) suppresses it when the eval issue exists | Treat heartbeat status as a **separate** axis; do not gate the fix on it |
| `resolveOutputAwareOk` miss is the single root cause | `resolveOutputAwareOk`/`verifyScheduledIssueCreated` govern the heartbeat, not issue creation | Verify in Phase 0; fix the **producer-count** path, not the verify path |
| Fix one path resolves both duplicate AND check-in status | Different mechanisms (producer count vs verify-read); only a shared *lag* sub-cause links them | Fix the double-file; note the shared-lag hypothesis for #5728 follow-up |

## User-Brand Impact

**If this lands broken, the user experiences:** the operator's daily community
digest GitHub issue is duplicated — two `[Scheduled] Community Monitor - <date>`
issues per day with slightly divergent metrics, polluting the
`scheduled-community-monitor` label feed the founder reads and undermining trust
in the digest as a single source of truth. A regression in the fix (over-suppression)
could file **zero** digests, silently blinding the only community-health signal.

**If this leaks, the user's data/workflow is exposed via:** N/A — no new data
surface; the digest already aggregates only public/community metrics (no PII; the
prompt forbids individual-follower enumeration).

**Brand-survival threshold:** none — duplicate informational issues are a noise/
trust paper-cut, single-operator-visible, not a data-loss or security incident.
(threshold: none, reason: duplicate read-only informational GitHub issues for a
single operator; no data exposure, no money, no multi-user blast radius.)

## Hypotheses (Phase 0 must select ONE before coding)

The eval digest producer runs/files twice. Candidate mechanisms — discriminated by
`routine_runs` (run_id, trigger type, attempt, started_at, duration_ms, status):

- **H-A — Multiple handler invocations (distinct `run_id`s).** Two events drove two
  runs: scheduled cron + manual trigger, repeated manual triggers (06-30's two
  fires at 07:04/07:08Z are BOTH before the 08:00 cron → both manual, recovery-day),
  or double event delivery. **Signature:** two terminal `routine_runs` rows, distinct
  `run_id`, ≥1 with an EVENT trigger. `concurrency:[{scope:"fn",limit:1}]` serializes
  but does NOT collapse sequential invocations.
- **H-B — Single run, claude-eval step re-executed on Inngest retry.** The
  `claude-eval` step (`:373`) threw AFTER the spawn's `gh issue create` side effect
  (so the step result was never memoized) → retry re-spawned → second digest.
  **Signature:** one `run_id`, two attempts, the second issue ≈ one eval-duration
  after the first. (Counter-evidence: observed gaps of 1.5–3.5 min are SHORTER than
  a ~5-min eval — weakens H-B.)
- **H-C — In-prompt `DEDUP RULE` failed to suppress the second digest.** The rule
  (`:227-229`) runs INSIDE the non-deterministic LLM agent (may be skipped) AND
  reads a GitHub **label-filtered** issue list subject to eventual-consistency lag,
  so a second eval 1–4 min later does not see the first issue. H-C compounds H-A/H-B
  (it is why neither invocation suppressed the other).

**Decision rule (revised per deepen pass):**
- **H-A (multiple invocations)** → deterministic handler-side LIST-endpoint date-dedup
  (NOT Inngest idempotency — see Enhancement Summary §1). Reliable because
  `concurrency:{scope:"fn",limit:1}` serializes the invocations.
- **H-B (in-run step retry re-fires the side effect)** → a pre-spawn dedup as its OWN
  `step.run` is **memoized** and will NOT cover H-B (the retried `claude-eval` step
  re-spawns regardless). The fix must live at the step/prompt boundary: switch the
  in-prompt `DEDUP RULE` (`:227-229`) off `gh issue list --search '… in:title'` onto the
  fresh `gh issue list --label … --json …` LIST form, AND/OR make the eval's
  issue-create idempotent. Per learnings `2026-06-12-inngest-cron-heartbeat-…` and
  `2026-06-14-inngest-…-consolidate-write-and-commit-in-one-step`, step-completion
  memoization does not prevent re-fire when the step itself threw.
- **H-C (LLM dedup unreliable)** → addressed in all branches because the LIST-vs-SEARCH
  switch removes the eventual-consistency miss, and the handler-side guard does not
  depend on the LLM honoring the prompt.

## Implementation Phases

### Phase 0 — Production root-cause confirmation (NO code)

Per `hr-no-dashboard-eyeball-pull-data-yourself` + the recurring-symptom Sharp Edge
(establish which code path executes from production before prescribing a fix layer).

1. **`routine_runs` pull (authoritative).** Read-only SQL (Supabase MCP / runbook
   `cloud-scheduled-tasks.md` H11) for `cron-community-monitor` on 2026-06-20,
   06-21, 06-30: per row `run_id`, trigger type (CRON vs EVENT), `attempt`,
   `started_at`, `duration_ms`, `status`, `error_summary`. Determine: **one run /
   two attempts (H-B)** vs **two runs (H-A)** and whether any was EVENT-triggered.
2. **Issue metadata cross-check.** `gh issue view` the six issues for `createdAt` +
   `author`; correlate each issue's create-time against the `routine_runs` window(s).
   Confirm both bodies are digests (already verified for #5737/#5740).
3. **Sentry exec-path search.** Query Sentry for `scheduled-output-missing`,
   `verify-output-failed`, `handler-body-threw`, `ensure-audit-issue-failed` events
   scoped to these dates — confirm the audit path did NOT fire (expected: no
   `ensure-audit-issue` create), and capture whether `heartbeatOk` was false.
4. **manual-trigger source.** If H-A: check `app/api/internal/trigger-cron/route.ts`
   + operator-action history for duplicate `cron/community-monitor.manual-trigger`
   emissions during the 06-13→06-30 recovery window.
5. **Record the verdict** (H-A / H-B / H-C-compound) in the spec's Research
   Reconciliation + a one-paragraph Phase 0 finding in the PR body. The chosen fix
   in Phase 2 cites this verdict.

### Phase 1 — RED regression test (cq-write-failing-tests-before)

Add a failing test reproducing the dual-production path the Phase 0 verdict
identified.

**Test seam (corrected per deepen pass — the existing seam asserts a PROXY).** The
existing `cron-community-monitor-heartbeat.test.ts` mocks BOTH the `claude-eval` spawn
(which is what files the digest via the spawned agent's `gh issue create`) AND
`ensureScheduledAuditIssue` — so there is no real issue object to count, and
"issue-count == 1" degenerates into "the mock was called once" (a proxy). To assert the
**invariant**, drive the handler-side dedup through a **fake GitHub issue store
(octokit stub)** that BOTH the dedup LIST read and the create path write through, so the
count is observable. Co-locate under `test/server/inngest/` (verify the
`apps/web-platform/vitest.config.ts` `include:` globs first per the test-path Sharp Edge);
a new `cron-community-monitor-dedup.test.ts` is acceptable if the heartbeat test's mocks
do not fit.

- **If H-A:** two serialized invocations on the same date against the fake store produce
  **exactly one** `[Scheduled] Community Monitor - <date>` digest issue; the second
  short-circuits via the LIST-dedup. RED before the guard exists.
- **If H-B:** a `claude-eval` step that throws after its issue-create side effect does
  NOT yield a duplicate on retry (the fix lives at the step/prompt boundary — see Phase 2).
- **Skip-path heartbeat:** assert the dedup-skip path posts an **OK** heartbeat (no
  false-RED) — exercise the heartbeat mechanism Phase 2 selects.
- **Audit-collision (zero-digest guard):** assert that a pre-existing **FAILED audit
  stub** (`Automated FAILED self-report` body, same title) or the `… - FAILED`
  no-platform issue does NOT suppress a real digest — the dedup must distinguish them.

### Phase 2 — Fix (layer chosen by Phase 0 verdict)

**PRIMARY fix — deterministic handler-side LIST-endpoint date-dedup** (covers H-A + the
H-C compound; precedent-aligned). Reuse the `ensureScheduledAuditIssue` LIST shape
(`_cron-shared.ts:1091-1101`: `GET /issues?labels=scheduled-community-monitor&sort=created&direction=desc&per_page=10`)
behind today's date anchor `runStartedAt.slice(0,10)` (replay-stable — never `new Date()`,
per `:1063-1065`). Place it to short-circuit the SECOND serialized invocation's eval/issue
(reliable because `concurrency:{scope:"fn",limit:1}` serializes — Enhancement Summary §2).
Consider extracting a shared `digestIssueExistsForDate(label, date)` helper in
`_cron-shared.ts` so producer + audit paths share one vetted read. Three hard constraints:

- **Exclude FAILED/audit stubs (zero-digest guard, P1).** The audit fallback and the
  no-platform path both file `[Scheduled] Community Monitor - <date>` / `… - FAILED` with
  the byte-identical title prefix. A bare `title.startsWith` match would treat a stub as
  "digest present" and suppress the real digest. The dedup MUST match only a **real
  digest** — e.g. exclude titles ending `- FAILED` AND issues whose body begins
  `Automated FAILED self-report` (or require a digest marker the prompt emits).
- **Fail-OPEN (P1).** If the LIST read throws, **proceed to spawn** (mirror
  `resolveOutputAwareOk`'s fall-back-to-`spawnOk`, `:765-775`) — a transient GitHub error
  must not become a missed digest.
- **Skip-path heartbeat (resolves the window tension).** A skip that posts no comment
  leaves the first issue's `updated_at` BEFORE the second run's `runStartedAt`, so
  `verifyScheduledIssueCreated` would return false → false-RED. On the dedup-skip path,
  **short-circuit to a healthy OK heartbeat** (e.g. early `return {ok:true}` posting the
  OK check-in, or pass the dedup result so `resolveOutputAwareOk` resolves true) — do NOT
  fall through to the normal verify-window. Pick ONE mechanism and assert it in the test.

**Inngest `idempotency`/`debounce` is NOT used** (deepen-pass verdict). The two triggers
have disjoint payload shapes with no shared date field, the window is a fixed 24h with no
override (`inngest/types.d.ts:1357`), an empty-key collapse risks suppressing the next
day's digest, and it does not cover H-B. If a dispatch-layer belt is ever wanted,
document it as a follow-up — it is not this fix.

**If H-B is the Phase 0 verdict:** the pre-spawn dedup `step.run` is memoized and will NOT
re-run on the retried `claude-eval`. Fix at the step/prompt boundary instead: switch the
in-prompt `DEDUP RULE` (`:227-229`) from `gh issue list --search '… in:title'` (stale
search index) to the fresh `gh issue list --label scheduled-community-monitor --json …`
LIST form, and/or make the issue-create idempotent.

**Note the two-layer asymmetry:** an Inngest-layer guard and a handler-side guard fail in
OPPOSITE directions (idempotency over-suppresses on a failed-first-run claiming the date
key; handler-dedup races within index-lag for truly-simultaneous reads). The chosen
single primary (handler LIST-dedup under fn-concurrency serialization) avoids both because
serialization removes the simultaneity and the FAILED-exclusion removes the bad-claim.

Keep scope minimal: do NOT touch `resolveOutputAwareOk`/`verifyScheduledIssueCreated`
heartbeat-verify logic (that is #5728's delivery class) beyond the skip-path OK
short-circuit above. If Phase 0 confirms the shared label-index-lag sub-cause also
degrades the heartbeat verify, file a follow-up note on #5728 rather than widening this PR.

### Phase 3 — Verify

1. `tsc --noEmit` (`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`).
2. Run the new RED test → GREEN + the existing
   `cron-community-monitor{,-heartbeat}.test.ts` suites stay green (no regression to
   the #5728 throw-path heartbeat assertions).
3. Re-assert the **invariant, not a proxy** (verification Sharp Edge): the test must
   assert issue-**count == 1** for a date across N invocations, not merely "dedup
   helper was called".
4. Post-merge (operator-automatable via `gh`): on the next real fire, confirm exactly
   one digest issue via the LIST endpoint (fresh index), not search:
   `gh issue list --label scheduled-community-monitor --json title,createdAt | jq '[.[]|select(.title=="[Scheduled] Community Monitor - <date>")]|length'` → `1`.

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` — PRIMARY fix:
  handler-side LIST-endpoint date-dedup (H-A/H-C) and/or the in-prompt `DEDUP RULE`
  search→LIST switch (`:227-229`, H-B). NOT Inngest idempotency/debounce.
- `apps/web-platform/server/inngest/functions/_cron-shared.ts` — extract a shared
  `digestIssueExistsForDate(label, date)` (LIST read, FAILED/audit-stub exclusion,
  fail-OPEN) generalized from the `ensureScheduledAuditIssue` dedup (`:1091-1101`) so
  producer + audit paths share one vetted read.
- `apps/web-platform/test/server/inngest/cron-community-monitor-heartbeat.test.ts`
  (or a new `…-dedup.test.ts`) — RED→GREEN regression test driving a **fake octokit
  issue store** so issue-count is observable (not the mocked-spawn proxy).

## Files to Create

- (none expected) — new test cases extend the existing test file. A new test file is
  created only if the chosen fix's seam does not fit the heartbeat test's mocks; in
  that case `test/server/inngest/cron-community-monitor-dedup.test.ts` (verify the
  `include:` glob first).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Phase 0 verdict (H-A / H-B / H-C-compound) recorded in PR body, citing the
      `routine_runs` rows (run_id/trigger/attempt) and the six issues' create-times.
- [ ] A RED test reproduced the dual-production path; it is GREEN after the fix.
- [ ] The regression test asserts issue-**count == 1** per date across ≥2 invocations
      (or ≥2 attempts for H-B) through a **fake octokit issue store** — the observable
      invariant, not "dedup mock called once".
- [ ] The handler still posts a healthy OK heartbeat on the dedup-skip path (no
      false-RED introduced) — test exercises the chosen skip-path heartbeat mechanism.
- [ ] Dedup **excludes FAILED/audit stubs**: a pre-existing `… - FAILED` issue or an
      `Automated FAILED self-report` body does NOT suppress a real digest (test-covered).
- [ ] Dedup read **fails OPEN** (spawns on a GitHub LIST error) — test-covered.
- [ ] Date anchor is `runStartedAt.slice(0,10)` (replay-stable), not `new Date()`.
- [ ] No Inngest `idempotency`/`debounce` added to `createFunction` (deepen-pass verdict).
- [ ] Existing `cron-community-monitor.test.ts` + `…-heartbeat.test.ts` stay green
      (no regression to #5728 throw-path heartbeat behavior).
- [ ] `tsc --noEmit` clean in `apps/web-platform`.
- [ ] No change to `resolveOutputAwareOk`/`verifyScheduledIssueCreated` (scope kept
      out of #5728's heartbeat-delivery class), or an explicit one-line rationale if
      Phase 0 proves the fix must touch them.

### Post-merge (operator — automatable via `gh`)

- [ ] On the first post-deploy fire, exactly ONE `[Scheduled] Community Monitor -
      <date>` issue exists for the date (`gh issue list --label
      scheduled-community-monitor --search "<date> in:title" --json number`). Use
      `Ref #5751` in the PR body; close #5751 after this confirmation.

## Observability

```yaml
liveness_signal:
  what: scheduled-community-monitor Sentry cron check-in (one OK per day)
  cadence: daily 08:00 UTC
  alert_target: Sentry monitor "scheduled-community-monitor"
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf
error_reporting:
  destination: Sentry via reportSilentFallback / warnSilentFallback (@/server/observability)
  fail_loud: true
failure_modes:
  - mode: dedup guard over-suppresses → zero digest issues filed
    detection: resolveOutputAwareOk finds no issue in window → scheduled-output-missing event + RED monitor
    alert_route: Sentry scheduled-community-monitor monitor (RED) + cron-cloud-task-heartbeat watchdog
  - mode: dedup guard under-suppresses → two issues still filed
    detection: post-merge gh issue-count probe > 1 for the date; new regression test
    alert_route: PR-time test + post-merge gh probe
  - mode: idempotency/debounce collapses a legitimately-distinct same-day run
    detection: routine_runs shows a run skipped/deduped; digest still present
    alert_route: routine_runs review (read-only SQL), no new alert needed
logs:
  where: routine_runs (Supabase, run-log middleware @/server/inngest/client.ts) + Better Stack stdout tail
  retention: routine_runs durable; Better Stack per provider retention
discoverability_test:
  command: gh issue list --label scheduled-community-monitor --search "<date> in:title" --json number | jq 'length'
  expected_output: "1"
```

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` searched for
`cron-community-monitor.ts`, `_cron-shared.ts`, `resolveOutputAwareOk`,
`ensureScheduledAuditIssue` → zero matches.)

## Domain Review

**Domains relevant:** Engineering (infra/tooling — Inngest cron handler).

No Product/UX surface (no `components/**`, `app/**/page.tsx`, or user-facing UI in
Files-to-Edit) → Product/UX Gate: NONE. No Legal/Finance/Sales/Marketing/Support
implication (a duplicate internal GitHub issue is a tooling defect). This is an
infrastructure/tooling bug fix.

## Architecture Decision (ADR/C4)

No architectural decision. The fix is a handler-side LIST-endpoint date-dedup mirroring
the already-present `ensureScheduledAuditIssue` title-dedup (`_cron-shared.ts:1091-1101`) —
no new substrate, tenancy boundary, trust boundary, or ADR reversal. A competent engineer
reading the existing ADRs/C4 would not be misled after this ships. (C4: no external actor /
system / data store / access-relationship change — the digest-issue producer and its
GitHub edge already exist.)

## Test Scenarios

1. Two same-date invocations (H-A) → exactly one digest issue; second is suppressed;
   OK heartbeat still posted.
2. Single run, eval step retried after issue-create side effect (H-B) → no duplicate
   issue on the retried attempt.
3. Dedup-skip path → handler returns `{ ok: true }` and posts OK (no false-RED).
4. Genuine first run of the day (no existing issue) → one digest filed, heartbeat OK.
5. Pre-existing FAILED audit stub / `… - FAILED` issue for the date → real digest is
   STILL produced (dedup excludes stubs); exactly one real digest results.
6. Dedup LIST read throws (GitHub error) → fail-OPEN: handler spawns and produces the
   digest (no missed digest from a transient hiccup).
7. Existing #5728 throw-path assertions (happy path = one OK; non-final throw = no
   heartbeat + rethrow; trailing safe-commit-pr throw on output-present = GREEN) all
   still pass.

## Sharp Edges / Risks

- A plan whose `## User-Brand Impact` section is empty or `TBD` fails deepen-plan
  Phase 4.6 — it is filled above (threshold: none + reason).
- **Over-suppression → ZERO digests is the dangerous failure mode.** Re-assert
  issue-count == 1 (not ≥0) through a fake issue store, and keep the OK-heartbeat-on-skip
  test. Three concrete zero-digest traps (all P1, all in the fix constraints): the
  audit/`- FAILED` title collision, a fail-CLOSED LIST read, and a non-replay-stable date
  anchor.
- **The audit fallback shares the digest's exact title.** `ensureScheduledAuditIssue`
  files `[Scheduled] Community Monitor - <date>` (`_cron-shared.ts:1068`) and the
  no-platform path files `… - FAILED`; a bare `title.startsWith` dedup suppresses the real
  digest on a same-day recovery. Match a REAL digest only (exclude `- FAILED` titles +
  `Automated FAILED self-report` bodies).
- **Inngest `idempotency`/`debounce` is unusable here, not just "verify it".** Two triggers
  with disjoint payloads (no shared date field), fixed 24h window, empty-key collapse, and
  no H-B coverage. Do not reach for it as a fallback; the handler LIST-dedup under
  `concurrency:{scope:"fn",limit:1}` serialization is the race-light primary.
- **Use the LIST endpoint, not search.** The current in-prompt `DEDUP RULE`
  (`:227-229`) reads the stale search index (`--search '… in:title'`) — the root of the
  H-C miss. The fix's read must hit `GET /issues?labels=…` (fresh primary index).
- **Do not absorb #5728.** Keep the heartbeat-verify logic untouched beyond the skip-path
  OK short-circuit; if Phase 0 confirms the shared label-index-lag sub-cause also degrades
  the heartbeat verify, file a follow-up note on #5728, do not widen this PR.
- **The heartbeat run-window false-REDs a naive skip.** `verifyScheduledIssueCreated`
  filters `updated_at >= runStartedAt(this invocation)`; a second-invocation skip that
  posts no comment leaves the first issue outside the window → false-RED + a spurious
  audit-fallback fire. The dedup-skip path must short-circuit to an OK heartbeat.
- Confirm the new test file path (if any) matches `apps/web-platform/vitest.config.ts`
  `include:` globs before adding (co-located `components/**` tests are silently skipped).
