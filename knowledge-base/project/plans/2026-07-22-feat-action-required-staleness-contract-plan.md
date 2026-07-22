---
title: "feat: action-required escalation staleness contract"
issue: 6836
supersedes_issue: 6769
branch: feat-escalation-staleness-contract
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-07-22
---

# feat: action-required Escalation Staleness Contract

## Overview

`action-required` is the agent pipeline's escalation channel to the non-technical
operator. Its oldest items have a ~0% resolution rate (30 open, oldest 131 days).
The brainstorm (`knowledge-base/project/brainstorms/2026-07-22-action-required-staleness-contract-brainstorm.md`)
root-caused four failures and the operator chose a **full four-layer staleness
contract, staged, auto-expiring structurally-dead classes only**. Plan-time repo
verification then **materially re-scoped Layer 1** (see Research Reconciliation).

The contract, as it now stands after verification:

- **Layer 1 — Delivery:** already shipped + provisioned. Residual = a green-probe
  re-run **plus** a real gap: a *failed* digest run self-reports nothing.
- **Layer 2 — Triage render:** rewrite `operator-digest` Section 4 to a strict,
  age/priority-sorted, capped action list + a separated informational block.
- **Layer 4 — SLA lifecycle:** a new co-located Inngest cron that escalates ops
  asks by age and auto-expires dead classes only (fail-safe allowlist).
- **De-pollute:** done at the **read predicate** (Layer 2), not by destabilizing
  producers. Producer relabeling is an optional tracked follow-up.
- **FR5 backfill:** the SLA cron's first run + one clean digest, folded in here.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality (verified 2026-07-22) | Plan response |
|---|---|---|
| Layer 1: "fix the failing `gh issue create --assignee` path" — build the assignee fix | Both the public asset `operator-digest.workflow.yml:117,122` and the live private workflow **already** use `--assignee "${OPERATOR_GH_LOGIN}"`, with a comment naming the exact #6769 finding. | Layer 1 code is DONE. Re-scope to (a) verify a green delivery run, (b) add failed-run self-report. |
| Layer 1: operator may not be notified (assignee unset) | Repo variable `OPERATOR_GH_LOGIN=deruelle` **is set** (2026-07-20T22:02:41Z); `deruelle` **is assignable** (`gh api .../assignees/deruelle` → exit 0). | Provisioning already done. #8 probe failure was likely pre-variable or transient — verify via one `gh workflow run`. |
| De-pollute requires editing "every producer that double-stamps" | `ship:1305` **deliberately** double-stamps `decision-challenge`+`action-required` so it surfaces; `cron-content-publisher.ts:409,496` stamps `content-starvation`+`action-required` for a real page-1 dedup reason. | Do the de-pollute at the **read predicate** (SKILL.md §4 label filter). Producer relabeling becomes an OPTIONAL follow-up, not a load-bearing edit. |
| Lifecycle cron home: "lean public soleur scheduled-*.yml" | The auto-close precedent is `cron-content-publisher.ts` — an **Inngest** function that files+auto-closes issues; ADR-033 makes Inngest canonical; producers are co-located Inngest functions. | Cron home = a new **Inngest** function `cron-action-required-sla.ts`, co-located with producers (not a scheduled-*.yml). |
| Section 4 harvest is `--json title,url` | Confirmed (`operator-digest/SKILL.md` §4). The digest tool allowlist already includes `Bash(gh issue list:*)`, so a richer query needs no allowlist change. | Rewrite §4 instructions to fetch `title,url,createdAt,labels` and render age/priority. |
| content-starvation is one of the "dead chores" | `content-starvation` is a single deduped, self-closing "distribution pipeline empty" signal — a *genuine* standing ask, distinct from the per-piece "[Content] Post to HN" chores. | Keep `content-starvation` visible; expire only per-piece `content`/`content-publisher` chores. |

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)
- Confirm the public asset + live private workflow assignee code (done at plan time; re-confirm at /work).
- `gh variable list -R jikig-ai/operator-digest` shows `OPERATOR_GH_LOGIN`; `gh api repos/jikig-ai/operator-digest/assignees/deruelle` exits 0.
- Read `cron-content-publisher.ts` end-to-end as the structural template for the new cron (dedup read, auto-close, structured `op:` emit, workspace-root resolution).

### Phase 1 — Layer 1: Delivery verification + failed-run self-report
1. **Verify delivery** (operator-gated trigger): `gh workflow run "Operator weekly digest" -R jikig-ai/operator-digest`; confirm the resulting `Digest: <week>` issue has `assignees=[deruelle]`. Turns the #8 probe green.
2. **Failed-run self-report** (real gap — 06-26 and 07-20 runs failed silently). Add an `if: failure()` step to `plugins/soleur/skills/operator-digest/assets/operator-digest.workflow.yml` that files ONE idempotent `action-required` issue in the private repo, assigned to `${OPERATOR_GH_LOGIN}`, titled "⚠️ Weekly digest run FAILED — no digest this week (run <id>)". Re-provision to the private repo via `provision-operator-digest-repo.sh`.

### Phase 2 — Layer 2: Triage render (de-pollute at the predicate)
Rewrite `plugins/soleur/skills/operator-digest/SKILL.md` §4:
1. **Harvest query:** `gh issue list -R jikig-ai/soleur --label action-required --state open --json number,title,url,createdAt,labels --limit 100`.
2. **Action list predicate (de-pollute):** exclude any issue whose labels include `decision-challenge`, `content`, or `content-publisher`. (Keep `content-starvation` — genuine standing ask.)
3. **Render:** sort by (priority desc, age desc); lead with a "🔴 Open longest / needs attention" mini-block showing **per-item age in days** for items past the ops SLA (§Layer 4 thresholds); **cap** the full action list at N=8 with "+M more open".
4. **Informational block (new, separated):** open `decision-challenge` issues under a distinct heading "Decisions flagged for your awareness (not blocking)", capped at 5 + "+M more". This preserves the visibility `ship:1305` intends while removing them from the action list.
5. Update `plugins/soleur/test/operator-digest-skill.test.sh` (and `components.test.ts` word-budget if the description line changes — it should not) for the new §4 contract.

### Phase 3 — Layer 4: SLA lifecycle cron (fail-safe close authority)
> **The classification/threshold/veto policy in steps 1–8 below is correct and stands.**
> **The cron ARCHITECTURE is superseded by `## Deepening (2026-07-22)` — a dispatcher/worker
> fan-out with live-state idempotency markers and a non-bot activity clock. Implement the
> Deepening architecture; read steps 1–8 for the policy it executes.**

Create `apps/web-platform/server/inngest/functions/cron-action-required-sla.ts` (structural mirror of `cron-content-publisher.ts`):
1. List all open `action-required` issues (labels + createdAt).
2. **Classify by ALLOWLIST (fail-safe, TR3) — key on AGENT-OWNED labels only:**
   - `OPS` = default (not in any allowlisted class). **Escalate-only, never close.**
   - `DEAD-CONTENT` = labels include **`content-publisher`** (the label the content pipeline itself applies) AND NOT `content-starvation`. **Do NOT key on the broad `content` label** — a human or another workflow can attach `content` to a genuine ops emergency (e.g. a content-*pipeline* outage), and keying on it makes DEAD-CONTENT a denylist wearing an allowlist's clothes (review finding #1). **Expire.**
   - `DECISION-CHALLENGE` = labels include `decision-challenge`. **Expire (longer window).**
   - Anything unclassified → treated as OPS → never closed.
3. **Human-engagement veto (review finding #1 — applies to EVERY close).** Abort the close if the issue shows any operator touch: a non-bot assignee, ANY human (non-bot) comment or reaction, or a **manually-set** priority. Note: the escalation ladder itself writes `priority/p*`, so "has a priority label" is NOT a human signal — distinguish agent-set (label applied by this cron / a bot) from human-set (applied by `deruelle`) via the label event actor, or gate on assignee+human-comment only if actor attribution is unavailable. A day-29 "still broken, please help" comment MUST block the day-30 close.
4. **Escalation ladder (OPS, defaults — operator-tunable constants):** age (from `createdAt`) ≥14d → ensure ≥ `priority/p2-medium`; ≥30d → `priority/p1-high` + one dedup comment "open Nd — needs you"; ≥60d → `priority/p0-critical` + comment. Idempotent (only bump upward; comment once per threshold — use a durable threshold marker/label, not a comment-body re-scan).
5. **Expiry (DEAD-CONTENT / DECISION-CHALLENGE):** staleness measured from **last activity (`updatedAt` or last human-comment timestamp), NOT `createdAt`** (review finding #2 — `createdAt` is right for the OPS ladder but wrong for an irreversible close; a re-commented 40d issue must not expire). At ≥30d of *inactivity*: close as `not planned` + label `wontfix-stale` + reason comment ("auto-closed stale after Nd inactive; distribution gap tracked by content-starvation" / "decision-challenge reversal window elapsed unreviewed").
6. **TOCTOU re-assert (review finding #3).** The list snapshot's labels are stale by the time the close fires. Immediately before EACH close: re-fetch the issue, re-run classification + the human-engagement veto, and use `updatedAt` as an optimistic-concurrency token — **abort the close if `updatedAt` changed since the listing snapshot.** Batch closes over the backlog are exactly where this window bites.
7. **Observability:** emit a structured event per action — `op: "action-required-sla"`, fields `{issue, ageDays, inactiveDays, class, action: "escalate"|"expire"|"skip"|"error", priorityBefore, priorityAfter, humanEngaged}` — via the same Sentry/log path `cron-content-publisher` uses. **Alert on the case actually feared:** any `expire` where `humanEngaged` was true OR the TOCTOU token changed (a genuine-engagement close that slipped through), AND on `action:"error"`. (Do NOT alert only on out-of-allowlist expire — the fail-safe already prevents that, so it can never fire; review finding #3 blind-spot.)
8. Register the function in the Inngest client + cron manifest; add unit tests `apps/web-platform/test/server/inngest/cron-action-required-sla.test.ts` covering: OPS never-closed at 999d; DEAD-CONTENT (via `content-publisher`) closed at 30d-inactive not 29d; an ops issue carrying the broad `content` label is OPS (never closed); DECISION-CHALLENGE closed at 30d-inactive; human-engagement veto (assignee / human comment / human-set priority each block the close); last-activity clock (40d-old but recently-commented → not expired); TOCTOU (updatedAt changed since snapshot → abort); unclassified never closed; idempotent priority bump; per-threshold single comment.

### Phase 4 — FR5 backfill + ADR
1. **Backfill = first cron run** (idempotent): after deploy, the cron closes the 6 dead content chores and the render change drops the 13 decision-challenges from the action list; the ~11 genuine ops asks remain. Verify the next digest's action list is clean (no content/decision-challenge items; per-item age shown). No separate script.
2. **ADR** `/soleur:architecture` — new ADR recording the **close-authority trust boundary**: "an automated lifecycle cron may auto-close ONLY allowlisted structurally-dead action-required classes; ops/infra escalations are escalate-only and never auto-closed." Alternatives considered: aggressive SLA auto-close (rejected — risks closing a live emergency), nag-only (rejected — dead chores never drain).

## Deepening (2026-07-22) — Phase 3 cron architecture (data-integrity + architecture review)

Two focused substance-level reviews (data-integrity-guardian + architecture-strategist) against
the `cron-content-publisher.ts` precedent surfaced two correctness-**fatal** defects and a
required structural change. This block supersedes the Phase 3 *architecture* (the policy in Phase
3 steps 1–8 is unchanged).

### D1 — Dispatcher/worker fan-out (NOT an in-line loop)
The precedent processes ONE issue; this cron iterates a backlog of side-effecting GitHub mutations,
which breaks the single-function loop on three axes (failure isolation, the 10-min
`MAX_RUN_DURATION_MS` wall clock under `concurrency fn:1` per ADR-033 I3, and step-id stability).
Structure it as **two Inngest functions**:
- **Dispatcher** `cron-action-required-sla.ts`: (step 1) read + **paginate to exhaustion** the open
  `action-required` backlog (Octokit `.paginate`, or hard-cap the oldest-N with a cursor and drain
  the rest next run — `per_page:10` from the precedent is a single-issue dedup read, NOT a backlog
  iterator); (step 2) one `step.sendEvent` per issue emitting `sla/issue.process` with **event
  idempotency key** `id: \`sla-${number}-${action}-${threshold}\`` (dedups a dispatcher replay).
- **Worker** `sla-issue-process.ts` (`inngest.createFunction` on `sla/issue.process`): process ONE
  issue → classify, veto, escalate-or-expire. Per-issue failure isolation + its own retry budget;
  parent stays ~2 steps regardless of backlog size.

### D2 — Idempotency against LIVE GitHub state (step memoization is insufficient)
`step.run` memoization dedups only within one run's replays — NOT an incomplete step's own retry,
NOT tomorrow's fresh cron. So:
- **Each side-effecting write in its own `step.run` with a deterministic id** keyed on issue+action+
  threshold (`escalate-${n}-${threshold}`, `expire-${n}`). A loop with positional/auto-indexed ids
  misattributes memoized results when the candidate list reorders between attempts (D-guardian 1a).
- **Never bundle `comment` (POST, non-idempotent) after `close`/`relabel` in one step** — a throw on
  the second call re-runs the step and re-posts the comment (D-guardian 1b; `retries:1` guarantees
  it). Split the comment into its own step.
- **The "one comment/action per threshold" marker MUST be a sentinel embedded in the comment body**
  (`<!-- sla:${action}:${threshold} -->`), and the guard MUST GET existing comments and skip if the
  sentinel is present — cross-run dedup is not covered by memoization, and a trailing *label* set
  after the comment is non-atomic (a failure between POST and label → next-day re-comment)
  (D-guardian 1c). Likewise skip EXPIRE if the issue is already closed / already carries
  `wontfix-stale`.

### D3 — Activity clock: last NON-BOT event, not the `updatedAt` scalar (FATAL if missed)
`updatedAt` is bumped by ANY write, including this cron's own escalation comments AND sibling crons
(e.g. inngest-health comments on these issues). Measuring inactivity from raw `updatedAt` means a
neglected DEAD-CONTENT issue that attracts routine bot noise **never** reaches 30d-inactive →
expiry is dead code for exactly the backlog it targets. **Compute inactivity from the last non-bot
timeline event, using the SAME non-bot predicate as the human-engagement veto** — the veto clock and
the inactivity clock must share one definition of "activity" (D-guardian 3). Anchor all age/inactivity
math to a single **memoized `runStartedAt`** (not per-step `new Date()`, which reads a new wall clock
on retry), and make the TOCTOU compare on the **raw ISO `updatedAt` string** (not a re-parsed `Date`,
which can spuriously abort every close via precision round-trips) (D-guardian 2).

### D4 — Reopen-loop guard (reintroduced by the D3 fix)
With the non-bot inactivity clock, a *bot/producer* reopen no longer resets the clock → a refiled
`content-publisher` (non-starvation) issue gets re-closed on the next run → 30-day close/refile
oscillation. On reopen: strip `wontfix-stale`, treat the reopen as an activity reset, and require ≥1
fresh **non-bot** signal before an issue bearing `wontfix-stale` may be re-closed (D-guardian 5).
(`content-starvation` itself is excluded from DEAD-CONTENT → OPS → never closed, so it can't loop.)

### D5 — "human-set priority" needs actor attribution
The veto's "human-set priority" clause cannot be a bare "p1 label present" check — that can't
distinguish the cron's own escalation label from a human's. Use the issue events/timeline API to
attribute the `labeled` event actor; if attribution is unavailable, gate the veto on
assignee + non-bot-comment only (do not treat priority-label presence as human engagement).

### D6 — Fan-out observability
Fan-out moves failures off the dispatcher: the **worker needs its own Sentry monitor slug + top-level
`reportSilentFallback`** — a per-issue failure must not degrade silently while the dispatcher reports
`ok:true`. The `op:"action-required-sla"` event is emitted by the WORKER, per issue.

### Precedent adoption (verbatim where applicable)
From `cron-content-publisher.ts`: Octokit calls inside `step.run` (I1 replay memoization);
`reportSilentFallback(err, {op})` for error emit; `resolveCronWorkspaceRoot` for any ephemeral
workspace; `postSentryHeartbeat` + a monitor slug. Sentry alert (`issue-alerts.tf`): a
`sentry_issue_alert` with `filter_match = "all"` on the op + the feared-case fields — model on
`byok_cap_exceeded`/`byok_art_33_breach` (op + boolean-tag dedup-TTL shape). **Inngest registration:**
grep the site that registers `cron-content-publisher` (the `functions: [...]` array passed to
`serve()`) at /work and register BOTH new functions there.

## Files to Edit
- `plugins/soleur/skills/operator-digest/SKILL.md` — §4 rewrite (Layer 2)
- `plugins/soleur/skills/operator-digest/assets/operator-digest.workflow.yml` — `if: failure()` self-report (Layer 1)
- `plugins/soleur/test/operator-digest-skill.test.sh` — §4 contract test
- the Inngest `serve()`/`functions: [...]` registration site (grep where `cron-content-publisher` registers) — register BOTH new functions (dispatcher + worker)
- `knowledge-base/engineering/architecture/decisions/` — new ADR

## Files to Create
- `apps/web-platform/server/inngest/functions/cron-action-required-sla.ts` — Layer 4 **dispatcher** (paginate + fan-out)
- `apps/web-platform/server/inngest/functions/sla-issue-process.ts` — Layer 4 **worker** (per-issue classify/veto/act)
- `apps/web-platform/test/server/inngest/cron-action-required-sla.test.ts` — dispatcher tests (pagination-to-exhaustion; one event per issue; idempotency key shape)
- `apps/web-platform/test/server/inngest/sla-issue-process.test.ts` — worker tests (classify, veto, non-bot clock, sentinel-marker dedup, reopen guard)

## User-Brand Impact
**If this lands broken, the user experiences:** a genuine only-you-can-fix emergency
(saturating disk, dead cron, expiring cert) is filed correctly, surfaced weekly, and
*still* silently ignored because it is undelivered or buried — the outage broadens
unattended (exactly #4375: 1 cron → 8 over 57 days).
**If this leaks / mis-fires:** the SLA cron auto-closes a genuine unresolved
emergency the operator hasn't gotten to (the auto-close risk the "dead classes only"
knob and the fail-safe allowlist exist to prevent).
**Brand-survival threshold:** single-user incident. CPO sign-off carried forward from
brainstorm (CPO lens applied); `user-impact-reviewer` invoked at review time.

## Domain Review
**Domains relevant:** Engineering, Product, Operations (carried forward from brainstorm `## Domain Assessments`).

### Engineering
**Status:** reviewed (carry-forward). Touches the digest render, a new close-authority Inngest cron, and observability. Close-authority must be fail-safe allowlist (TR3).
### Product
**Status:** reviewed (carry-forward). Operator comprehension is the product; legible age/priority + de-noised action list is the user win.
### Operations
**Status:** reviewed (carry-forward). The rot is ops escalations that broaden unattended; escalation ladder + delivery are reliability improvements.

### Product/UX Gate
**Tier:** none — no UI surface (digest markdown + labels + cron only; no `components/**`, no `app/**/page.tsx`). `.pen` wireframes N/A.
**Pencil available:** N/A (no UI surface).

## Architecture Decision (ADR/C4)
### ADR
Create a new ADR (next free ordinal — provisional; re-verify at ship): **close-authority
boundary for the action-required lifecycle cron.** Decision: auto-close is restricted
to an allowlist of structurally-dead classes; ops/infra escalations are escalate-only.
Alternatives Considered: aggressive SLA auto-close (rejected); nag-only (rejected).
### C4 views
**No C4 impact** — checked all three `.c4` files: `founder`/operator actor is modeled
(`model.c4:8`), the Inngest container is modeled (`model.c4:188`), and the "Inngest
cron → GitHub issues" relationship already exists via the sibling `cron-content-publisher`
(same class). The new cron is a Component *within* the already-modeled Inngest container;
the model is Container-granularity, so individual cron functions are not enumerated
elements. No new external actor, system, or access relationship is introduced.

## Observability
```yaml
liveness_signal:
  what: cron-action-required-sla weekly run emits op:"action-required-sla" summary event
  cadence: weekly (Inngest cron, aligned with digest cadence)
  alert_target: Sentry (Inngest middleware) + structured log
  configured_in: apps/web-platform/infra/sentry/issue-alerts.tf (add rule on op + error)
error_reporting:
  destination: Sentry via existing Inngest middleware; structured log line
  fail_loud: true (a run error emits op:"action-required-sla" action:"error")
failure_modes:
  - {mode: cron did not fire, detection: absence of weekly op:"action-required-sla" event, alert_route: existing cron-liveness watchdog class}
  - {mode: auto-closed an issue an operator had engaged with (the feared case), detection: op event action:"expire" with humanEngaged:true OR TOCTOU token changed, alert_route: Sentry alert on that shape — NOT on out-of-allowlist expire, which the fail-safe already prevents}
  - {mode: GitHub API error mutating a label/state, detection: action:"error" event with issue+status, alert_route: Sentry}
  - {mode: digest run itself failed, detection: Layer-1 if:failure() self-report issue, alert_route: assigned action-required issue}
logs:
  where: Inngest run logs + Sentry
  retention: per existing Inngest/Sentry retention
discoverability_test:
  command: gh issue list -R jikig-ai/soleur --label action-required --json labels,createdAt (NO ssh) — verify no per-piece content/decision-challenge item older than its SLA remains open
  expected_output: only OPS-class issues (escalated) + content-starvation remain; dead classes past threshold are closed
```

## Acceptance Criteria

### Pre-merge (PR)
- [ ] §4 rewrite: harvest fetches `createdAt,labels`; action-list predicate excludes `decision-challenge`/`content`/`content-publisher`; sorts by (priority,age); shows per-item age; caps at 8; separate capped informational decision-challenge block. Verify via `operator-digest-skill.test.sh`.
- [ ] `cron-action-required-sla.ts` classify function: OPS never returned as closeable (test at 999d); DEAD-CONTENT (keyed on `content-publisher`) closeable at 30d-inactive not 29d; an ops issue carrying the broad `content` label classifies OPS (never closed); DECISION-CHALLENGE at 30d-inactive; unclassified never closeable. (Allowlist on agent-owned label, not denylist — TR3 + review finding #1.)
- [ ] Human-engagement veto: assignee / human comment / human-set priority each block the close — unit-tested (review finding #1).
- [ ] Expiry clock is last-activity (`updatedAt`), not `createdAt`: a 40d-old but recently-commented issue does NOT expire — unit-tested (review finding #2).
- [ ] TOCTOU: `updatedAt` changed between list snapshot and close → close aborts — unit-tested (review finding #3).
- [ ] **Non-bot activity clock (D3, fatal):** inactivity measured from last non-bot timeline event, NOT raw `updatedAt`; a DEAD-CONTENT issue bot-commented every 7d still expires at 30d-non-bot-inactive — unit-tested.
- [ ] **Pagination to exhaustion (D4, fatal):** dispatcher processes the FULL backlog (test with a backlog spanning >1 page; the oldest item is escalated/expired, not dropped).
- [ ] **Live-state sentinel dedup (D2):** re-running the worker on the same issue+threshold posts NO second comment (sentinel `<!-- sla:action:threshold -->` GET-guard); comment is its own `step.run`.
- [ ] **Reopen guard (D4):** a reopened `wontfix-stale` issue is not re-closed until ≥1 fresh non-bot signal; `wontfix-stale` stripped on reopen — unit-tested.
- [ ] **Fan-out architecture (D1):** dispatcher emits one `sla/issue.process` event per issue with idempotency key `sla-${n}-${action}-${threshold}`; worker is a separate function with its own Sentry monitor slug + top-level `reportSilentFallback`.
- [ ] Age/inactivity anchored to a single memoized `runStartedAt`; TOCTOU compares raw ISO `updatedAt` string (not re-parsed Date).
- [ ] Escalation is idempotent (priority only bumps upward; one comment per threshold via durable marker) — unit-tested.
- [ ] `if: failure()` self-report step added to the digest workflow asset + re-provision path documented.
- [ ] Observability block satisfied: `op:"action-required-sla"` event with the discriminating `class`/`action` fields; Sentry rule added.
- [ ] ADR authored (close-authority boundary) with Alternatives Considered.
- [ ] `tsc --noEmit` (in `apps/web-platform`) + `test-all.sh` green; no orphan guard suites broken.

### Post-merge (operator/automation)
- [ ] `gh workflow run "Operator weekly digest" -R jikig-ai/operator-digest` → resulting digest issue assigned to `deruelle` (Layer 1 verify; automatable — `gh` CLI). `Ref #6836`, close after verified.
- [ ] First SLA cron run closes the 6 dead content chores; leaves ~11 ops asks + content-starvation; next digest action list is clean (FR5 backfill).

## Open Code-Review Overlap
None — `gh issue list --label code-review --state open` shows no open scope-out touching `operator-digest/SKILL.md`, the workflow asset, or the Inngest functions dir. (Re-run at /work to confirm.)

## Risks & Sharp Edges
- **Close authority (highest risk).** The cron can close operator issues. Mitigations (hardened by architecture review, folded into Phase 3): (1) expiry keys on the AGENT-owned `content-publisher` label, never the human-attachable `content`; (2) a human-engagement veto (assignee / human comment / human-set priority) aborts any close; (3) expiry clock is last-activity (`updatedAt`), not `createdAt`; (4) TOCTOU re-assert + `updatedAt` optimistic-concurrency token immediately before each close; (5) every close emits an auditable `op:` event and the Sentry alert fires on the *feared* case (expire-despite-human-engagement), not the fail-safe-prevented one. Precedent: `cron-content-publisher.ts` already closes issues safely.
- **Deepen-plan warranted.** At `single-user incident` threshold, plan-review (style/scope) is structurally blind to substance-level findings in the cron's close logic and clock handling (use the DB/Inngest clock consistently; `now()` vs event time). Run `/deepen-plan` (data-integrity-guardian + architecture-strategist) before `/work`, per the plan-review-vs-deepen-plan Sharp Edge.
- **Empty `## User-Brand Impact` fails deepen-plan Phase 4.6** — it is filled above.
- **Two-repo effect:** Layer 2 (SKILL.md §4) changes what the *next* weekly digest renders because the private workflow checks out public soleur at run time — no private-repo code change needed for the render. Only the Layer-1 asset self-report re-provisions to the private repo.
- **Producer relabeling deferred:** because de-pollute is read-side, producers keep double-stamping. File ONE follow-up issue (net-issue-flow) to relabel `ship`/`plan`/`content-publisher` so the label regains literal meaning — do not net-grow the backlog with per-producer issues.

## Test Scenarios
1. Render: seed a mixed label set (ops p1 at 60d, content-publisher at 40d, decision-challenge at 5d) → action list shows only the ops item with age "60d", decision-challenge in the informational block, content item absent.
2. Cron classify: table test across all four classes × ages {0,29,30,60,999}.
3. Cron idempotency: two consecutive runs on the same p1@30d item → one comment, priority stays p1.
4. Fail-safe: an `action-required` issue with an unknown label at 999d → escalate-only, never closed.
5. Layer 1: forced workflow failure → self-report issue filed + assigned.
