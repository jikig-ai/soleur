---
title: "Re-arm Inngest reminders lost in the #5542 durable cutover"
date: 2026-06-18
type: ops-remediation
classification: ops-only-prod-write
brand_survival_threshold: none
lane: single-domain
issue: 5548
status: planned
---

# fix: Re-arm Inngest reminders lost in the #5542 durable cutover (#5548) 🔧

## Enhancement Summary

**Deepened on:** 2026-06-18
**Sections enhanced:** Idempotency (AC4), Implementation Phase 2 (executor), Test Scenarios
**Passes run:** deepen-plan halt gates (4.6 User-Brand Impact ✓, 4.7 Observability ✓ no-ssh, 4.8 PAT ✓ none, 4.9 UI-wireframe ✓ skip non-UI); verify-the-negative pass (6 load-bearing claims, all `confirms`); scheduled-work precedent check (4.4 — no new cron, skip).

### Key Improvements
1. **Dropped the redundant new helper script.** The plan originally floated an optional `apps/web-platform/infra/rearm-5548-reminders.sh`; verify-the-negative confirmed the existing, tested `inngest-rearm-reminders.sh` already does this (accepts records on stdin via `INNGEST_REARM_STDIN=1`). Option B now reuses it — no new code, no new test (YAGNI).
2. **Corrected the idempotency claim.** Inngest `id` dedup is window-bounded (~24h, `inngest-oneshot-and-reminder-patterns.md:126`), NOT a permanent cross-boot guarantee. AC4 now states this so /work does not over-rely on it (moot here — empty queue).
3. **Pinned the colon-form tag.** `TAG_RE` (`sentry-issue-rate.ts:22`) requires `event_type:server-startup` (colon); the equals form a stale draft used would 400. AC1 + Sharp Edges pin it.

### New Considerations Discovered
- A past `fire_at` (`ts < now`) fires ~immediately — the handler has no future-gate (`event-scheduled-reminder.ts:206` validates ISO instant only); relevant only if 5417's 2026-06-19 date slips.
- The #5432 dependabot reminder is out of the documented #5548 scope (PIR `:42` names only 5417 + 5469) and its body is unrecorded — recommend drop, not re-arm.

## Overview

The #5542 inngest outage + durable Postgres+Redis cutover (2026-06-18) started the
new backend with an **empty queue** (`op=inventory` → `armed_reminders=0`). The 4
reminders armed in the old SQLite backend were never migrated: inngest was **down**
during the outage window, so the #5542 capture bridge (`op=capture`, which
self-enumerates the OLD server pre-deploy) could not snapshot them before the
cutover. The reminders silently dropped.

This is a **one-time operational re-arm** of the still-relevant reminders by POSTing
the reconstructed `{reminder_id, fire_at, actor, action}` to the existing, validated
arming surface — `POST /api/internal/schedule-reminder` (Bearer
`INNGEST_MANUAL_TRIGGER_SECRET`). The route recomputes the Inngest dedup keys
(`id`=reminder_id, `ts`=Date.parse(fire_at)) from the body and validates the action
against the same allowlist the handler uses, so re-arming is idempotent and
safe against double-fire.

**No new code, no migration, no deploy.** The action payloads are reconstructed from
each reminder's source automation (the issue flags this `deferred-automation` because
the payloads are NOT derivable from the reminder id alone). Two of the three reminders
have a canonically-documented payload; the third's body is only inferred and is
explicitly out of the documented #5548 scope.

**Crucially, the re-arm is fully automatable in-session** via the established no-SSH
`trigger-cron` pattern (read `INNGEST_MANUAL_TRIGGER_SECRET` read-only from Doppler
`-c prd --plain`, `curl` POST to the prod endpoint). Per `hr-never-label-any-step-as-manual-without`
and the non-technical-operator rule, this plan does the re-arm in-session — it does
NOT defer a curl invocation to the operator.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Reality (verified) | Plan response |
| --- | --- | --- |
| 4 reminders lost; re-arm via POST /api/internal/schedule-reminder | Endpoint exists + validated: `apps/web-platform/app/api/internal/schedule-reminder/route.ts`; allowlist in `apps/web-platform/lib/inngest/scheduled-reminder-action.ts`; public-path registered `lib/routes.ts:46`. | Use the existing endpoint as-is. No code change. |
| `verify-server-startup-rate-5417` fire_at 2026-06-19 → re-arm | **Canonical payload documented verbatim** in `knowledge-base/engineering/operations/runbooks/inngest-oneshot-and-reminder-patterns.md:71-74` and ADR-063 (first consumer). `named-check` `sentry-issue-rate`. | Re-arm with the runbook's exact blessed payload. |
| `reeval-5469-routine-runs-gate-2026-07-01` fire_at 2026-07-01 → re-arm | #5469 OPEN; re-eval criterion in the issue body (≥14 days of `routine_runs` data, after inbound fix). No prior comment posted. Action type is `issue-comment` to #5469. | Re-arm as `issue-comment` reminder to #5469. |
| `rebase-dependabot-5432-otel-2026-06-18` (×2) original fire 2026-06-18 13:00 → re-arm only if still relevant | #5432 is the **dependabot PR itself** (OPEN, stale branch `dependabot/npm_and_yarn/apps/web-platform/multi-63c4531a38`, mergeable UNKNOWN). The reminder body is **NOT recorded anywhere** — only inferred (`@dependabot rebase`). The PIR's #5548 re-arm table (`inngest-durable-redis-missing-outage-postmortem.md:42`) names ONLY 5417 + 5469 — **5432 is out of the documented #5548 scope.** | **Do NOT re-arm in this PR.** The fire window (13:00 2026-06-18) is already past, the body is unrecorded (a fabricated payload risks a wrong/misleading comment), and a `@dependabot rebase` can be issued directly without a reminder if the PR is still wanted. Document the disposition; see `## Open Questions` + scope-out. |
| #5542 capture bridge should have snapshotted these | Bridge `op=capture` self-enumerates the OLD server; with inngest DOWN the enumerate returns nothing — the documented loss mode. Premise holds. | No bridge change. This PR closes the residual gap manually. |

**Premise Validation:** #5548 OPEN, not closed by any merged PR. #5417 OPEN, #5469 OPEN,
#5432 OPEN (dependabot PR). #5542 CLOSED (the bridge-bug fix). The runbook payload for
5417 was verified verbatim against the `TAG_RE` regex in
`apps/web-platform/lib/inngest/sentry-issue-rate.ts:22` (the canonical form uses a
**colon** `event_type:server-startup`, NOT the equals form that appears in a stale
plan-task draft — the route's allowlist would 400 the equals form). All cited
artifacts exist on the working branch.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing. The reminders
are operator/maintainer-facing GitHub-issue automations (a Sentry-rate verification
comment + auto-close on #5417; a re-eval nudge comment on #5469). A broken re-arm
posts a wrong comment / wrongly closes a maintainer issue (re-openable) or simply
fails to fire (the verification is then done by hand). No user data path is touched.

**If this leaks, the user's data is exposed via:** no exposure vector — the payloads
carry only public GitHub issue numbers and a Sentry tag (`event_type:server-startup`).
The Bearer secret (`INNGEST_MANUAL_TRIGGER_SECRET`) is read-only from Doppler and never
echoed (mirrors `trigger.sh`'s `unset TOKEN` discipline).

**Brand-survival threshold:** none — reason: re-arming two maintainer-facing
GitHub-issue reminders against an already-provisioned, validated, allowlisted endpoint;
no user-facing surface, no schema, no migration, no auth flow, no regulated data.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Payload correctness (5417).** The re-arm body for `verify-server-startup-rate-5417`
  is byte-for-byte the runbook's blessed form: `action.type:"named-check"`,
  `check:"sentry-issue-rate"`, `report_to_issue:5417`,
  `params:{tag:"event_type:server-startup", max_per_day:1, window_hours:72, close_on_pass:true}`,
  `actor:"platform"`, `fire_at` a real future ISO instant (2026-06-19T09:00:00Z).
  Verify `params.tag` matches `TAG_RE` (`^[A-Za-z0-9_.-]+:[A-Za-z0-9_.\-/]+$`) and
  `window_hours ∈ [24,168]` per `apps/web-platform/lib/inngest/sentry-issue-rate.ts`.
- [x] **AC2 — Payload correctness (5469).** The re-arm body for
  `reeval-5469-routine-runs-gate-2026-07-01` is `action.type:"issue-comment"`,
  `issue:5469`, `actor:"platform"`, `fire_at:"2026-07-01T09:00:00Z"`, with a `body`
  that restates #5469's re-eval criterion (≥14 days `routine_runs` data after the
  inbound fix). `body` length ≤ 65000 (`MAX_COMMENT_BODY`).
- [x] **AC3 — Dependabot reminder disposition is recorded, not silently dropped.**
  `rebase-dependabot-5432-otel-2026-06-18` is NOT re-armed; the rationale (past fire
  window, unrecorded body, out of documented #5548 scope) is captured in the PR body
  AND a one-line note in #5548, with `@dependabot rebase` offered as the direct
  alternative if the otel bump is still wanted.
- [x] **AC4 — Idempotency reasoning is documented.** The PR body states that the route
  recomputes `id`=reminder_id + `ts`=Date.parse(fire_at) (verified
  `route.ts:128-133`), so a re-arm dedups against any event that ALSO survived in
  Inngest state **within Inngest's ~24h dedup window** (`inngest-oneshot-and-reminder-patterns.md:126`
  — the `id` dedup is window-bounded, NOT a cross-boot permanent guarantee). Here the
  queue is empty (#5542), so there is nothing to dedup against; the property is only
  why re-running the SAME re-arm POST minutes apart is safe (it dedups on `id`+`ts`
  within the window). Beyond ~24h the same `id` would re-fire — not a concern for a
  one-shot re-arm but stated so /work does not over-rely on it.
- [x] **AC5 — `Ref #5548`, not `Closes #5548`, in the PR body.** Per the
  ops-remediation class (`wg-use-closes-n-in-pr-body-not-title-to` extension): the
  actual closure happens post-merge, after the re-arm POST succeeds against prod and
  returns 202. (The feature description said "Closes #5548" — for an ops-remediation
  whose fix runs post-merge, `Ref` + a post-merge `gh issue close` is the correct
  shape so the issue is not false-resolved at merge.)

### Post-merge (operator-less — automated in-session by /work)

- [x] **AC6 — Re-arm 5417 fires a 202.** Run the in-session re-arm executor
  (`## Implementation Phases` Phase 2): read `INNGEST_MANUAL_TRIGGER_SECRET` from
  Doppler `-c prd --plain`, POST the AC1 body to
  `https://app.soleur.ai/api/internal/schedule-reminder`. Expect HTTP **202**
  `{scheduled:"verify-server-startup-rate-5417", fire_at:"2026-06-19T09:00:00Z"}`.
  On **503** (Retry-After) the cutover quiesce flag is still set — abort loud, do not
  swallow (mirrors `inngest-rearm-reminders.sh` B2-iii); on **401** the secret is
  wrong; on **400** the payload failed the allowlist (re-check AC1).
- [x] **AC7 — Re-arm 5469 fires a 202.** Same executor, AC2 body. Expect **202**
  `{scheduled:"reeval-5469-routine-runs-gate-2026-07-01", ...}`.
- [x] **AC8 — Live confirmation.** Confirm both reminders are armed against the new
  durable backend via `op=inventory` (the no-SSH HMAC webhook /
  `inngest-enumerate-reminders.sh` path) — `armed_reminders` reflects the 2 re-armed
  ids — OR, if inventory cannot be reached in-session, the two 202 responses are the
  acceptance evidence and inventory is noted as the deferred confirmation.
- [ ] **AC9 — Close #5548.** After AC6+AC7 return 202, `gh issue close 5548` with a
  comment summarizing what was re-armed (ids + fire_at + 202 evidence) and the 5432
  disposition.

## User-Brand Impact threshold note

Threshold `none`; the diff touches NO sensitive path (no `*.sql`, no migration, no
auth flow, no API route source — the only artifacts created are this plan, a re-arm
helper invocation record, and a runbook/PIR note). The scope-out reason is recorded
above per preflight Check 6.

## Implementation Phases

> **No production source code changes.** This PR's deliverable is (a) the documented
> re-arm payloads + disposition, (b) the in-session re-arm execution, (c) a runbook/PIR
> note so the next cutover knows these were re-armed manually. **No new script is
> needed** — the existing, tested `apps/web-platform/infra/inngest-rearm-reminders.sh`
> already implements the no-SSH re-arm executor (it accepts records on stdin via
> `INNGEST_REARM_STDIN=1` and POSTs each to `schedule-reminder` with 202/503/4xx
> handling + loud 503 abort). The default executor is a direct curl per the runbook;
> the existing script is the repeatable alternative (Phase 2 Option B). Do NOT add a
> redundant `rearm-5548-*.sh` (deepen-plan verify-the-negative finding — it would
> duplicate the existing tested executor).

### Phase 0 — Preconditions (read-only)

1. Confirm #5417, #5469 still OPEN and un-fired (no `sentry-issue-rate` comment on
   #5417; no re-eval comment on #5469): `gh issue view 5417 --json comments`,
   `gh issue view 5469 --json comments`. If either was ALREADY re-armed/fired since
   this plan was written, scope it out (do not double-arm).
2. Confirm the cutover quiesce flag is CLEAR: the route returns 503 while
   `INNGEST_CUTOVER_QUIESCE` is set (`route.ts:45-48,74-79`). The PIR records the
   durable cutover is "effectively complete" — verify a non-503 path before arming
   (a dry-run GET of `/health`, or accept the 503 abort in AC6 as the guard).
3. Confirm the durable backend is healthy (`op=inventory` → `functions=56`, NOT
   `__FETCH_FAILED__`) per the PIR resolution. A re-arm into a down backend silently
   loses again — this is the exact #5548 failure mode.

### Phase 1 — Reconstruct + freeze the two payloads (in the PR body / a payloads doc)

1. **5417** — copy the runbook's blessed `sentry-issue-rate` payload verbatim
   (`inngest-oneshot-and-reminder-patterns.md:71-74`). Set `fire_at:"2026-06-19T09:00:00Z"`.
   NOTE the deliberate distillation: #5417's full AC12 task spec (the issue comment
   2026-06-16) also checks OOM pages (AC2 regression) + AC13 firewall self-heal — a
   richer verification than `sentry-issue-rate` expresses. ADR-063 + the runbook
   blessed the distilled one-line `sentry-issue-rate` arm (core ≤1/day check +
   auto-close) as the canonical reconstruction. Re-arm the blessed form; the OOM/AC13
   tail, if still wanted, is a separate manual check (note in the #5417 comment the
   re-arm posts).
2. **5469** — build the `issue-comment` body from #5469's re-eval criterion:
   "Reminder (re-armed after the #5542 cutover): re-evaluate whether heavy
   claude-spawning crons still need explicit `routine_runs` instrumentation, now that
   `routine_runs` (deployed 2026-06-16) has ≥14 days of data and the inbound-ingress
   fix has shipped. See #5469 re-eval criterion." Target `issue:5469`,
   `fire_at:"2026-07-01T09:00:00Z"`.

### Phase 2 — Execute the re-arm in-session (no operator handoff)

Two valid executors — both read the secret read-only from Doppler and never echo it
(mirror `plugins/soleur/skills/trigger-cron/scripts/trigger.sh:133-148`,
`unset TOKEN`):

**Option A (default — direct curl per the runbook).** For each frozen payload:

```bash
SECRET=$(doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain)
curl -sS -o /tmp/rearm-resp.$$ -w '%{http_code}' -X POST \
  "https://app.soleur.ai/api/internal/schedule-reminder" \
  -H "Authorization: Bearer $SECRET" -H 'content-type: application/json' \
  --data-binary @<payload-file>
unset SECRET
# expect 202; on 503 ABORT LOUD (quiesce still set); on 401/400 fix + retry.
```

**Option B (repeatable — reuse the EXISTING executor, no new code).** Feed the two
frozen payloads as a JSON array to the already-tested
`apps/web-platform/infra/inngest-rearm-reminders.sh` via `INNGEST_REARM_STDIN=1`
(it loops the array and POSTs each to `schedule-reminder` with the same 202/503/4xx
handling + loud 503 abort the curl path uses):

```bash
echo "$PAYLOAD_ARRAY_JSON" | INNGEST_REARM_STDIN=1 \
  SCHEDULE_REMINDER_URL="https://app.soleur.ai/api/internal/schedule-reminder" \
  apps/web-platform/infra/inngest-rearm-reminders.sh
```

Do NOT author a new `rearm-5548-*.sh` — it would duplicate this tested executor
(deepen-plan verify-the-negative finding). Option A (direct curl) remains the
documented default; Option B is the no-new-code repeatable form.

> **Idempotency guard:** because the route sets Inngest `id`=reminder_id +
> `ts`=Date.parse(fire_at), re-running Phase 2 for the same payload dedups instead of
> double-firing a non-idempotent comment. Re-running on a 4xx/5xx is therefore safe.

### Phase 3 — Confirm + close

1. Verify both 202s; if reachable, confirm via `op=inventory` (AC8).
2. Record the re-arm in the PIR + runbook (Phase 4).
3. `gh issue close 5548` with the evidence summary (AC9).

### Phase 4 — Document (so the next cutover does not re-lose these)

1. Append a one-line note to
   `knowledge-base/engineering/operations/post-mortems/inngest-durable-redis-missing-outage-postmortem.md`
   under the #5548 row: "Re-armed 5417 + 5469 on 2026-06-18 via
   `POST /api/internal/schedule-reminder` (202×2); 5432 reminder not re-armed (past
   window, unrecorded body) — `@dependabot rebase` available directly."
2. (Optional) Add a runbook callout in `inngest-oneshot-and-reminder-patterns.md` §A:
   "If inngest is DOWN during a cutover, `op=capture` snapshots NOTHING — survivors
   must be reconstructed from source automations and re-armed manually (see #5548)."

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` returned no issue whose body
references `schedule-reminder`, `event-scheduled-reminder`, `scheduled-reminder-action`,
or `inngest-rearm`.

## Domain Review

**Domains relevant:** none

No cross-domain implications — operational re-arm of two maintainer-facing GitHub-issue
reminders against an already-provisioned, validated, allowlisted endpoint. No UI, no
schema, no user data, no infra provisioning, no legal/compliance surface.

## Open Questions

1. **5432 dependabot reminder — re-arm or drop?** Recommendation: **drop** (do not
   re-arm). The original fire window (2026-06-18 13:00) is already past, the reminder
   body was never recorded (only inferred as `@dependabot rebase`), and the PIR's
   #5548 re-arm table names only 5417 + 5469. If the otel bump (#5432, still OPEN,
   stale branch) is still wanted, `@dependabot rebase` can be commented directly on the
   PR — no future-dated reminder is needed for a past-due, one-shot rebase nudge.
   **If the operator disagrees**, re-arm as `issue-comment` `{issue:5432,
   body:"@dependabot rebase"}` with an immediate-or-near `fire_at` — but accept that
   the body is reconstructed, not recorded.
2. **5417 distillation** — confirm the blessed `sentry-issue-rate`-only re-arm (vs the
   fuller AC12 OOM/AC13 tail) is acceptable. ADR-063 + the runbook already blessed it;
   this plan follows that decision.

## Infrastructure (IaC)

Skipped — this PR introduces NO new infrastructure. It re-arms reminders against an
already-provisioned endpoint using an already-provisioned Doppler secret. No server,
no systemd unit, no DNS, no TLS, no new secret, no Terraform resource. The optional
Phase-2 Option-B helper script is a thin curl wrapper (no infra), not a provisioning
step.

## Observability

```yaml
liveness_signal:
  what: "schedule-reminder POST returns 202; reminder fires at fire_at"
  cadence: "one-shot (each re-arm); the fired reminder posts a GitHub comment"
  alert_target: "no new alert — failures route via reportSilentFallback → Sentry (route.ts:137, event-scheduled-reminder.ts)"
  configured_in: "apps/web-platform/app/api/internal/schedule-reminder/route.ts (emit); event-scheduled-reminder.ts (fire)"
error_reporting:
  destination: "Sentry via reportSilentFallback (feature:'schedule-reminder' op:'dispatch'; handler ops invalid-fire-at / action-not-allowlisted / unregistered-check / named-check-failed)"
  fail_loud: "yes — route returns 502 on dispatch failure + Sentry; re-arm executor aborts loud on 503/4xx (no swallow)"
failure_modes:
  - mode: "re-arm POST returns 503 (INNGEST_CUTOVER_QUIESCE still set)"
    detection: "HTTP 503 + Retry-After from the executor"
    alert_route: "executor aborts loud (stderr); operator clears flag then re-runs (Phase 0 precondition 2)"
  - mode: "re-arm POST returns 401 (wrong secret)"
    detection: "HTTP 401 from the executor"
    alert_route: "executor stderr; re-read INNGEST_MANUAL_TRIGGER_SECRET from Doppler prd"
  - mode: "re-arm POST returns 400 (payload failed allowlist)"
    detection: "HTTP 400 {error:'Invalid action: <reason>'}"
    alert_route: "executor stderr; re-check AC1/AC2 against validateReminderAction"
  - mode: "armed but backend down → silent re-loss (the #5548 failure mode)"
    detection: "op=inventory → __FETCH_FAILED__ or armed_reminders excludes the ids (AC8)"
    alert_route: "external inngest health watchdog (scheduled-inngest-health.yml, shipped #5549); Phase 0 precondition 3 gates against arming into a down backend"
  - mode: "sentry-issue-rate fires but fails closed (0-or->1 matching issues / missing env)"
    detection: "comment on #5417 reads 'fail-closed — <reason>'; reportSilentFallback op tail"
    alert_route: "Sentry; #5417 stays OPEN (no false close) — re-run the check or verify by hand"
logs:
  where: "Sentry (reportSilentFallback); the fired reminder's GitHub comment on #5417/#5469 is the durable audit trail"
  retention: "Sentry default; GitHub comments permanent"
discoverability_test:
  command: "curl -sS -o /dev/null -w '%{http_code}' https://app.soleur.ai/health   # then check #5417/#5469 for the fired comment after fire_at (NO ssh)"
  expected_output: "200 from /health; a sentry-issue-rate verdict comment on #5417 ~2026-06-19; a re-eval comment on #5469 ~2026-07-01"
```

## Test Scenarios

This PR ships no production source change, so the test surface is the **payload
validation contract** (already covered) + the optional helper:

1. **Existing coverage (no new test required for the re-arm itself).** The route +
   allowlist are tested in `apps/web-platform/test/server/internal/schedule-reminder-route.test.ts`
   and the handler in the event-scheduled-reminder suite. The re-arm bodies are valid
   by construction iff they pass `validateReminderAction` + `isValidIsoInstant` — which
   AC1/AC2 assert by inspection against `scheduled-reminder-action.ts` +
   `sentry-issue-rate.ts`.
2. **No new test required for Option B** — it reuses the existing
   `apps/web-platform/infra/inngest-rearm-reminders.sh`, already covered by
   `inngest-rearm-reminders.test.sh` (empty-secret fail-closed `:125-132`, 503-abort
   `:92-102`, non-202 hard-fail `:105-111`, empty no-op `:114-122`). No `rearm-5548-*.sh`
   is added, so no `.test.sh` sibling is created.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled
  above; threshold `none` with a sensitive-path scope-out reason.)
- **The `sentry-issue-rate` tag is colon-form, not equals-form.** `TAG_RE` in
  `sentry-issue-rate.ts:22` requires `key:value` (`event_type:server-startup`). A
  stale plan-task draft used `event_type=server-startup`; the route's allowlist would
  400 it. AC1 pins the colon form.
- **Re-arming into a down backend silently re-loses the reminder** — this is the exact
  #5548 failure mode. Phase 0 precondition 3 (confirm `op=inventory` healthy /
  `functions=56`) is load-bearing, not ceremony.
- **`fire_at` semantics:** the route takes `Date.parse(fire_at)` as the Inngest
  delivery `ts`. 5417's 2026-06-19 and 5469's 2026-07-01 are future instants — they
  schedule normally. (A past `fire_at` would fire ~immediately; not the case here, but
  relevant if 5417's date slips past 2026-06-19.)
- **`Ref #5548`, never `Closes #5548`** in the PR body — the real closure is the
  post-merge `gh issue close 5548` after the 202s, so the issue is not false-resolved
  at merge (ops-remediation class).
