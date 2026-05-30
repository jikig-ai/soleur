---
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_prs: ["#4653", "#4290", "#4508"]
related_issues: ["#4656", "#4364", "#4232"]
---

# BYOK Art. 33 Alert Hardening — Implementation Plan

## Enhancement Summary

**Deepened on:** 2026-05-30
**Sections enhanced:** Premise Validation, Key Decision D4, Risks, Acceptance Criteria (schema-grounded)
**Verification performed this pass:** beta2 provider schema dump; destroy-guard
fixture math; live PR/issue state checks; `action_match` semantics from the
provider schema description; auth-rule precedent grep.

### Key Improvements
1. **`action_match = "any"` is now schema-grounded, not inferred.** The beta2
   `sentry_issue_alert.action_match` schema description states: *"Trigger actions
   when an event is captured by Sentry and `any` or `all` of the specified
   **conditions** happen."* With 3 mutually-exclusive lifecycle conditions
   (`first_seen`/`reappeared`/`regression`), `"all"` would require all three to
   co-fire on one event (impossible) — `"any"` is REQUIRED. (D4 Risk hardened.)
2. **Destroy-guard safety proven empirically (not just argued).** Ran a
   before=1/after=3 `conditions_v2` fixture through
   `tests/scripts/lib/destroy-guard-filter-sentry.jq` → `nested_deletes: 0`. AC5
   confirmed: growing conditions is an in-place UPDATE, no `[ack-destroy]`.
3. **`action_match` precedent gap surfaced (verify-the-negative).** All 6
   existing `sentry_issue_alert` rules use `action_match = "all"`; NO in-repo
   precedent for `"any"`. The change is correct per schema but novel in this
   repo — flagged for reviewer scrutiny (no precedent-diff to lean on).

### New Considerations Discovered
- **`event_frequency` fallback fully specified** if discrete lifecycle conditions
  prove insufficient: `comparison_type` (req, `count`|`percent`), `value` (req,
  number), `interval` (opt, `1m`|`5m`|`15m`|`1h`|`1d`|`1w`|`30d`).
- **All cited references verified live** (#4653 MERGED, #4364/#4232/#4610/#4585
  CLOSED, #4290/#4508 MERGED) — no stale citations.

**Date:** 2026-05-30
**Status:** Deepened
**Author:** soleur:plan (one-shot pipeline)
**Issue:** #4656 (follow-ups from PR #4653 / #4364)
**Type:** refactor / hardening (`type/chore`, `domain/engineering`, GDPR Art. 33)

## Problem Statement

PR #4653 (#4364, MERGED 2026-05-30) shipped the BYOK-delegations Art. 33 breach
detection control: a `sentry_issue_alert.byok_art_33_breach` rule
(`apps/web-platform/infra/sentry/issue-alerts.tf:203`) that pages on a Sentry
event tagged `feature=byok-delegations` AND `art_33_breach=true`, plus the
emission that produces that tag (`cost-writer.ts:208-217` →
`reportSilentFallback(..., { art33Breach: true, op: "cross-tenant-violation" })`).
The first-occurrence happy path is implemented and tested.

`user-impact-reviewer` (single-user-incident threshold) surfaced **5 follow-up
hardening items**, deferred as a `deferred-automation` backlog item (#4656).
**None block merge of #4653; all sharpen the control so a real cross-tenant
BYOK-key leak reliably starts the GDPR Art. 33(1) 72-hour notification clock.**
The control as shipped has four latent gaps and one liveness blind spot:

1. **Recurrence (P1):** the rule fires on `first_seen_event` only — it pages
   once per Sentry issue fingerprint. A repeat breach (same fingerprint) folds
   into the existing issue and does NOT re-page; a breach recurring after the
   founder resolves the issue also won't re-page. The Art. 33 clock for the
   *recurrence* never starts.
2. **Capture-swallow (P2):** the breach routes through `reportSilentFallback`,
   whose `Sentry.captureException` is `try/catch`-swallowed and guarded by
   `typeof Sentry.captureException === "function"`. If Sentry is uninitialized
   or rate-limited in a prod worker, the breach event drops to a pino stdout
   line that no rule consumes.
3. **Clock anchor (P2):** the cross-tenant `baseExtra`
   (`{conversationId, delegationId, totalTokens, costCents}`) carries no
   `first_seen_at` Art. 33(1) clock anchor and no `severity` marker. The sibling
   P0 primitive (`mirrorP0Deduped`) stamps both.
4. **Recipient pinning N>1 (P1-latent, operator-gated):** the rule's
   `notify_email { target_type=IssueOwners, fallthrough_type=ActiveMembers }`
   is correct at N=1 (solo founder) but at N>1 active Sentry members
   over-discloses cross-tenant-leak metadata to every seat.
5. **Detector liveness (P2):** no end-to-end liveness check. A silent mis-wire
   (tag drift, dropped `-target`, muted rule) is invisible until a real breach
   fails to page.

This is **hardening of an existing GDPR Art. 33 detection control**, not a new
processing activity (PA-23 already covers BYOK delegation telemetry). The
brand-survival threshold is `single-user incident`: a single cross-tenant
BYOK-key leak that fails to page is a GDPR-notifiable breach the controller
never learns about in time — exactly the failure this plan closes.

## Premise Validation (Phase 0.6)

Verified against `origin/main` / HEAD this session:

- **PR #4653** — MERGED 2026-05-30T15:18:13Z. Premise holds.
- **#4364** — CLOSED (by #4653). #4232 / #4508 (BYOK consent + cost telemetry) —
  the PA-23 substrate the hardening attaches to.
- **`sentry_issue_alert.byok_art_33_breach`** — EXISTS at
  `apps/web-platform/infra/sentry/issue-alerts.tf:203` (git HEAD; the on-disk
  worktree checkout was stale at planning time — all paths/line-numbers in this
  plan are verified against `git show HEAD:<path>`). Uses
  `conditions_v2 = [{ first_seen_event = {} }]` and
  `filters_v2 = [feature=byok-delegations, art_33_breach=true]`.
- **The `art_33_breach=true` emission EXISTS** — `cost-writer.ts:208-217` routes
  the `byok_delegations:cross-tenant:` raise through
  `reportSilentFallback(new ByokDelegationCrossTenantError(...), { feature:
  "byok-delegations", op: "cross-tenant-violation", art33Breach: true, extra:
  baseExtra })`. `SilentFallbackOptions.art33Breach` -> `tags.art_33_breach =
  "true"` at `observability.ts:177`. (#4653 wired the substrate gap the prior
  plan flagged — item 1's filter now matches real events.)
- **`mirrorP0Deduped`** EXISTS (`observability.ts:456`) — `level: "fatal"`, no
  5-min debounce (1h dedup keyed on `userId:op:conversationId`), stamps
  `severity: "breach_attempt"` + `first_seen_at` in `extra`. Its Sentry call is
  **also** `typeof`-guarded + `try/catch`-swallowed, BUT it always emits a pino
  `logger.error` mirror first. It does NOT currently set an `art_33_breach` tag.
- **`mirrorCrossTenantViolation`** EXISTS (`observability.ts:566`) but has a
  **DSAR-shaped signature** (`offendingUserId, expectedUserId, tableName, err,
  ctx`) — built for the worker-scope row-ownership breach, NOT the BYOK
  delegation path. It is NOT a drop-in for the BYOK case (no `delegationId`/`op`
  concept, no `art_33_breach` tag). The issue body names it as a *candidate*;
  this plan uses `mirrorP0Deduped` instead (see Decision D1).
- **Item 1 deferred schema verification — RESOLVED THIS SESSION.** The issue
  deferred verifying the beta2 `conditions_v2` attribute names ("the authoring
  host couldn't dump the schema reliably"). Dumped via `terraform providers
  schema -json` against an isolated backend-free config with the committed
  `.terraform.lock.hcl` (jianyuan/sentry 0.15.0-beta2). Confirmed condition
  types: `event_frequency`, `event_frequency_percent`,
  `event_unique_user_frequency`, `existing_high_priority_issue`,
  `first_seen_event`, `new_high_priority_issue`, `reappeared_event`,
  `regression_event`. See Research Reconciliation for exact HCL shapes.

No stale premises. The substrate the prior plan had to build first (item-1 tag
emission) is now shipped; this plan is pure hardening on top of it.

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Codebase reality (verified 2026-05-30, git HEAD) | Plan response |
|---|---|---|
| Item 1: "Verify the exact beta2 `conditions_v2` attribute names via `terraform providers schema -json` before writing (deferred here...)." | **Done this session.** `event_frequency` = object `{comparison_type (req: count\|percent), value (req: number), interval (opt: 1m\|5m\|15m\|1h\|1d\|1w\|30d), comparison_interval (opt), name (opt)}`. `reappeared_event` = object `{name?}`. `regression_event` = object `{name?}`. `conditions_v2` nesting_mode = `list`. | Item 1 specifies exact HCL below — no further schema dump needed at /work. |
| Item 2: route cross-tenant case through `mirrorCrossTenantViolation`/`mirrorP0Deduped`. | `mirrorCrossTenantViolation` signature is DSAR-shaped (`offendingUserId, expectedUserId, tableName`) — NOT a fit for the BYOK `delegationId`/`op` path. `mirrorP0Deduped(err, {op, userId, conversationId})` IS the fit (fatal, no debounce, Art. 33-built). | Route through `mirrorP0Deduped`, extended to carry the `art_33_breach` tag + `delegationId` extra (Decision D1). |
| Item 3: `baseExtra` carries no `first_seen_at`; sibling P0 path stamps it. | Correct — `reportSilentFallback` path stamps no `first_seen_at`; `mirrorP0Deduped` already stamps `severity: breach_attempt` + `first_seen_at` at `observability.ts:483-487`. | Items 2 + 3 collapse: routing through `mirrorP0Deduped` gives `first_seen_at` + `severity` for free. |
| Item 4: `notify_email { IssueOwners -> ActiveMembers }` over-discloses at N>1; fix needs the operator's Sentry member id. | Confirmed at `issue-alerts.tf:243-247`. No `sentry_member_id` variable exists in `variables.tf`. The 4 auth rules + `byok_cap_exceeded` use the same pattern (repo convention). | **Operator-gated, deferred (kept open).** Cannot pin a member id we don't have; re-eval trigger is "second active Sentry seat added." Plan documents the fix shape + sharpens the tracking issue; does NOT change the rule at N=1 (changing it would need a member id that doesn't exist). |
| Item 5: no liveness canary; add synthetic `op=canary` heartbeat OR a cron asserting the rule exists via Sentry API. | `sentry-monitors-audit.sh` already queries Sentry rule endpoints; `apply-sentry-infra.yml` runs it as a 4-gate pre-apply check. Cron-asserting-rule-exists is the lower-risk option (no synthetic breach event into a prod GDPR surface). | Add a read-only rule-existence assertion for the two BYOK rules by name to `apply-sentry-infra.yml` AND optionally a recurring liveness check. Reject the synthetic-`op=canary`-breach option (Decision D2). |

## Key Decisions

- **D1 — Items 2+3 route through `mirrorP0Deduped`, extended to carry the
  `art_33_breach` tag.** The cross-tenant breach is the one BYOK op that must be
  fatal + recurrence-resilient + clock-anchored. `mirrorP0Deduped` already
  provides fatal + `first_seen_at` + `severity: breach_attempt` + a guaranteed
  pino mirror. The one gap is the `art_33_breach=true` Sentry tag (item 1's rule
  filter depends on it). Extend `mirrorP0Deduped`'s `ctx` with an optional
  `art33Breach?: boolean` (or `tags?: Record<string,string>`) so the breach
  event carries `art_33_breach=true`. The `op` becomes `"cross-tenant-violation"`.
  **Reject** `mirrorCrossTenantViolation`: its DSAR signature does not model
  `delegationId`/`op`, and conflating the two cross-tenant surfaces would muddy
  both dashboards.
- **D2 — Item 5 is a read-only rule-existence assertion, NOT a synthetic
  breach.** A synthetic `op=canary` breach event would inject a fake Art. 33
  breach-attempt into a `single-user-incident`-threshold GDPR surface (false
  audit residue, possible real page). The safe canary is a read-only Sentry API
  GET asserting both BYOK rules exist by name + carry the expected
  `conditions`/`filters` — wired into the existing `apply-sentry-infra.yml`
  audit gate. Per `hr-no-dashboard-eyeball-pull-data-yourself`, the assertion is
  an API query with a deterministic verdict, not an operator dashboard glance.
- **D3 — Item 4 stays deferred + operator-gated, but the deferral is sharpened.**
  We physically cannot pin `target_type=Member` without the founder's Sentry
  member id, and the over-disclosure risk does not exist at N=1 (solo founder).
  Changing nothing at N=1 is correct. The plan records the exact fix and the
  trigger; #4656 stays open scoped to item 4 only after items 1/2/3/5 land.
- **D4 — Recurrence condition = `first_seen_event` + `reappeared_event` +
  `regression_event` (NOT `event_frequency`).** Three discrete event-lifecycle
  conditions cover (a) new issue, (b) issue reappears after being resolved, (c)
  issue regresses — the exact recurrence modes the issue names. `event_frequency`
  (>=1 in interval) would also work but introduces an interval-window semantic
  and a `frequency`-vs-`event_frequency` interaction the discrete conditions
  avoid. With `action_match = "any"` (changed from `"all"`), ANY of the three
  firing pages. (See Sharp Edges: `action_match` must flip to `"any"`.)
- **D5 — Work against `git HEAD`, never the worktree's on-disk checkout.** The
  worktree checkout was stale at planning time (177-line `issue-alerts.tf` vs the
  298-line HEAD version). /work Phase 0 MUST re-sync / verify file state via
  `git show HEAD:<path>` before editing.

## User-Brand Impact

**If this lands broken, the user experiences:** a real cross-tenant BYOK-key
leak that recurs (item 1) or drops on a swallowed Sentry capture (item 2) and
never pages the founder — the GDPR Art. 33(1) 72-hour notification clock never
starts, exposing the controller to regulatory penalty and a customer whose
API-key isolation was breached without notice.

**If this leaks, the user's data / workflow / money is exposed via:** the alert
event's `extra` carries cross-tenant-leak metadata (`conversationId`,
`delegationId`, `userIdHash`). Item 4's `ActiveMembers` fallthrough would
disclose that metadata to every Sentry seat at N>1 — but the userId is already
pseudonymized (`hashUserId`) at the emit boundary, so the exposure is
delegation/conversation identifiers, not raw PII.

**Failure mode — rule exists but tag-filters drifted (item 5 liveness scope):**
the `assert-byok-rules-exist.sh` liveness check asserts rule EXISTENCE by name,
not `filters_v2` shape. A rule that exists with a drifted `tagged_event` key
would capture the breach event yet silently fail to match. This is mitigated,
not unhandled: `conditions_v2`/`filters_v2`/`actions_v2` are Terraform-owned
(NOT in `lifecycle.ignore_changes`), and the liveness check runs POST-apply —
so every apply re-writes the filters from source and then re-proves existence.
Tag-drift is self-healing on the next apply; the residual window (drift between
applies, absent a Terraform run) is covered by the deferred recurring-liveness
check (Phase 3.2, gated on review judgment — judged: defer for the single-user
solo-founder Sentry org). Existence-by-name is the deliberate minimal signal,
not an oversight.

**Brand-survival threshold:** single-user incident.

CPO sign-off required at plan time before `/work` begins (carry-forward from
#4364's `requires_cpo_signoff: true`; this plan inherits the same threshold and
detection-control surface). Invoke CPO domain leader if not already covered by
Phase 2.5, or confirm CPO has reviewed. `user-impact-reviewer` will be invoked
at review-time.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (item 1 — recurrence):** `byok_art_33_breach.conditions_v2` contains
  `first_seen_event`, `reappeared_event`, AND `regression_event` blocks, and
  `action_match = "any"`. Verify: `git show HEAD:apps/web-platform/infra/sentry/issue-alerts.tf`
  (post-edit) shows all three condition types in the `byok_art_33_breach`
  resource and `action_match = "any"`.
- [ ] **AC2 (item 1 — schema validity):** `terraform validate` passes against
  the sentry root with the new conditions (run via the isolated backend-free
  probe form, see Phase 0). The deprecation warning for `sentry_issue_alert` is
  EXPECTED (#4610) and does not count as a validate failure.
- [ ] **AC3 (items 2+3 — fatal routing + clock anchor):** the
  `byok_delegations:cross-tenant:` branch in `cost-writer.ts` routes through
  `mirrorP0Deduped` (not bare `reportSilentFallback`), and the emitted Sentry
  event carries `level: "fatal"`, `tags.art_33_breach = "true"`,
  `extra.first_seen_at` (ISO string), `extra.severity = "breach_attempt"`, and
  `extra.delegationId`. Verify via the unit test in AC6.
- [ ] **AC4 (item 5 — liveness assertion):** `apply-sentry-infra.yml`'s
  post-apply step (or the audit gate) asserts BOTH `byok-art-33-breach` and
  `byok-cap-exceeded` rules exist in Sentry by name via a read-only API GET,
  with a deterministic non-zero exit if either is absent. No `op=canary`
  synthetic breach event is emitted (D2). Pin `--max-time` on the curl.
- [ ] **AC5 (destroy-guard safety) — VERIFIED EMPIRICALLY THIS PASS:**
  `terraform show -json` of the plan diff for `byok_art_33_breach` shows the
  conditions edit as an in-place UPDATE with `nested_deletes = 0` from
  `tests/scripts/lib/destroy-guard-filter-sentry.jq` (the edit ADDS condition
  blocks: before=1, after=3 -> no shrink). A before=1/after=3 fixture run through
  the actual jq filter this session returned `{resource_deletes: 0,
  nested_deletes: 0}` — so the auto-apply will not require `[ack-destroy]`.
  Verify at /work against the real `terraform show -json tfplan`.
- [ ] **AC6 (unit test):** `cost-writer.test.ts` extends the existing
  cross-tenant assertion to verify the new `mirrorP0Deduped` routing emits the
  full tag+extra shape from AC3. Test runner: confirm against
  `apps/web-platform/package.json scripts.test` + `vitest.config.ts include:`
  globs — the file lives at `apps/web-platform/test/server/cost-writer.test.ts`
  (existing location; do NOT co-locate).
- [ ] **AC7 (observability primitive test):** if `mirrorP0Deduped` is extended
  with an `art_33_breach` tag option, the relevant P0-dedup test (grep
  `__resetMirrorP0DedupForTests` to locate) asserts the tag is set when the
  option is passed and absent otherwise.
- [ ] **AC8 (full suite green):** `apps/web-platform` test suite +
  `tests/scripts/test-all.sh` (the destroy-guard scope-guard exit gate) pass.
  Per the `-target=` allowlist Sharp Edge, the scope-guard
  (`test-destroy-guard-sentry-scope-guard.sh`) must still pass — `sentry_issue_alert`
  is already in its allowlist; the conditions edit does not add a new resource
  type.

### Post-merge (operator / automated)

- [ ] **AC9 (auto-apply):** merge to main touching `issue-alerts.tf` triggers
  `apply-sentry-infra.yml`; the targeted apply updates `byok_art_33_breach`
  in-place (recurrence conditions) with zero destroys. **Automation:** the PR
  merge IS the apply trigger (`apply-sentry-infra.yml` `on.push` path-filter
  includes `issue-alerts.tf`); no operator step. Verify via the workflow run +
  Post-apply summary.
- [ ] **AC10 (liveness fires):** the AC4 rule-existence assertion runs green in
  the apply workflow. **Automation:** runs in-workflow.
- [ ] **AC11 (item 4 deferral sharpened):** #4656 is updated (NOT closed) to
  scope it to item 4 only, with the exact fix (`target_type=Member` + founder
  member id OR single-member ops Team) and the re-eval trigger ("second active
  Sentry seat added"). **Automation:** `gh issue edit` / `gh issue comment` via
  Bash in /work.

## Implementation Phases

### Phase 0 — Preconditions (verify, no code)

1. `git show HEAD:apps/web-platform/infra/sentry/issue-alerts.tf` — confirm the
   `byok_art_33_breach` resource shape (the worktree on-disk file may be stale;
   D5).
2. Re-dump the beta2 schema if needed (isolated probe, no backend):
   ```bash
   mkdir -p /tmp/sentry-schema-probe && cd /tmp/sentry-schema-probe
   printf 'terraform {\n  required_providers {\n    sentry = {\n      source  = "jianyuan/sentry"\n      version = "0.15.0-beta2"\n    }\n  }\n}\n' > versions.tf
   cp <repo>/apps/web-platform/infra/sentry/.terraform.lock.hcl .
   terraform init -lockfile=readonly -input=false
   terraform providers schema -json > /tmp/sentry-schema.json
   jq -r '.provider_schemas|to_entries[0].value.resource_schemas.sentry_issue_alert.block.attributes.conditions_v2.nested_type.attributes|keys[]' /tmp/sentry-schema.json
   ```
   (Verified output this session: includes `event_frequency`, `first_seen_event`,
   `reappeared_event`, `regression_event`.)
3. Read `tests/scripts/lib/destroy-guard-filter-sentry.jq` +
   `test-destroy-guard-sentry-scope-guard.sh` to confirm the conditions edit is
   an in-place UPDATE, not a delete (AC5).

### Phase 1 — Item 1: recurrence-inclusive conditions (terraform)

Edit `apps/web-platform/infra/sentry/issue-alerts.tf`, `byok_art_33_breach`:
```hcl
  action_match = "any"   # was "all" — ANY of the 3 conditions pages
  ...
  conditions_v2 = [
    { first_seen_event = {} },
    { reappeared_event = {} },   # issue reopened after resolve -> re-page
    { regression_event = {} },   # issue regressed -> re-page
  ]
```
Update the inline comment to cite #4656 item 1 + the schema-verified attribute
names. Leave `byok_cap_exceeded` unchanged (cap-exceeded recurrence is lower
urgency; out of scope per issue). Leave `filters_v2` / `actions_v2` / `frequency`
/ `lifecycle` unchanged.

> **Note on `action_match`:** with `first_seen_event` alone, `action_match` was
> `"all"` (trivially true with one condition). With three conditions ORed for
> recurrence, `action_match` MUST be `"any"` or the rule requires all three to
> co-fire (never). Verify against the beta2 schema semantics + the auth-rule
> precedent at /work.

### Phase 2 — Items 2+3: fatal routing + clock anchor (TypeScript)

1. **`observability.ts`** — extend `mirrorP0Deduped`'s `ctx` to accept an
   optional `art33Breach?: boolean` (or `tags?: Record<string,string>`). When
   set, add `art_33_breach = "true"` to the Sentry `tags` map (mirror the
   `reportSilentFallback` mapping at `observability.ts:177`). Keep `first_seen_at`
   + `severity: "breach_attempt"` (already present). Add `delegationId` passthrough
   to `extra` if provided.
2. **`cost-writer.ts`** — change the `byok_delegations:cross-tenant:` branch
   (`:208-217`) from `reportSilentFallback(...)` to:
   ```ts
   mirrorP0Deduped(
     new ByokDelegationCrossTenantError(delegation.delegationId),
     {
       op: "cross-tenant-violation",
       userId,
       conversationId,
       delegationId: delegation.delegationId,
       art33Breach: true,
     },
   );
   ```
   (Exact param shape depends on the Phase-2.1 `ctx` extension; thread
   `delegationId` + `art33Breach` per the chosen signature.) Update the inline
   comment to cite #4656 items 2+3 and explain the fatal/no-debounce/clock-anchor
   rationale. Add the `mirrorP0Deduped` import.
3. **Preserve the operator dashboard message string** — `mirrorP0Deduped`'s pino
   mirror uses `p0 deduped mirror: ${op}`. Confirm no existing dashboard keys off
   the old `reportSilentFallback` `"byok-delegations silent fallback"` string for
   the cross-tenant op specifically (grep). If one does, carry it forward.

### Phase 3 — Item 5: liveness rule-existence assertion

1. Add a read-only Sentry API assertion that BOTH `byok-art-33-breach` and
   `byok-cap-exceeded` rules exist by name. Preferred placement: extend
   `apps/web-platform/scripts/sentry-monitors-audit.sh` (already wired as the
   pre-apply 4-gate in `apply-sentry-infra.yml`) OR add a post-apply step.
   Endpoint: `GET /api/0/projects/{org}/{project}/rules/` (project rules list —
   issue alerts, NOT the org `/monitors/` Crons endpoint; verify the endpoint
   returns issue-alert rules at /work, NOT metric/cron monitors). Deterministic
   verdict: non-zero exit if either name absent. Pin `--max-time` on the curl.
2. Optionally add the same assertion as a recurring liveness check (the issue
   suggests a cron). If a cron is added, route it via Inngest per ADR-033
   (precedent check at deepen-plan Phase 4.4), NOT a new GitHub Actions cron.
   **Scope decision:** the in-workflow post-apply assertion (option 1) covers
   the "silent mis-wire on apply" failure mode cheaply; a standalone recurring
   cron is a larger surface — propose option 1 as the primary deliverable and
   gate the recurring cron on deepen-plan / review judgment.

### Phase 4 — Item 4: sharpen the deferral (no code change at N=1)

`gh issue edit 4656` (or comment) to re-scope #4656 to item 4 only, recording
the exact fix (`target_type = "Member"` + founder Sentry member id, OR a
single-member ops Team) and the re-eval trigger ("a second active Sentry member
is added"). Keep the issue OPEN. No `issue-alerts.tf` change — pinning a member
id we do not have is impossible, and the over-disclosure risk is zero at N=1.

### Phase 5 — Tests + docs

- Extend `cost-writer.test.ts` cross-tenant assertion (AC6).
- Add/extend the observability P0-dedup test for the `art_33_breach` tag (AC7).
- Update `issue-alerts.tf` inline comment + `apps/web-platform/infra/sentry/README.md`
  if the rule-count / liveness behavior changes.
- Capture a learning on the recurrence-condition + fatal-routing pattern.

## Files to Edit

- `apps/web-platform/infra/sentry/issue-alerts.tf` — item 1 (recurrence
  conditions + `action_match`).
- `apps/web-platform/server/observability.ts` — items 2+3 (`mirrorP0Deduped`
  `art_33_breach` tag + `delegationId` extra).
- `apps/web-platform/server/cost-writer.ts` — items 2+3 (route cross-tenant
  branch through `mirrorP0Deduped`).
- `apps/web-platform/scripts/sentry-monitors-audit.sh` — item 5 (rule-existence
  assertion). *(or `apply-sentry-infra.yml` post-apply step.)*
- `apps/web-platform/test/server/cost-writer.test.ts` — AC6.
- The observability P0-dedup test file (grep `__resetMirrorP0DedupForTests` to
  locate) — AC7.
- `apps/web-platform/infra/sentry/README.md` — if rule behavior/count changes.
- `tests/scripts/test-destroy-guard-counter-sentry.sh` + fixture — only IF the
  conditions edit changes the nested-block count semantics the guard asserts
  (it adds blocks; verify the existing fixture still represents the guarded
  shape — likely no edit needed, but the `-target=` allowlist Sharp Edge
  requires the sweep).

## Files to Create

- `knowledge-base/project/learnings/<bug-fixes|best-practices>/<topic>.md` — the
  recurrence-condition + fatal-routing learning (date picked at write-time; do
  NOT prescribe the dated filename).

## Open Code-Review Overlap

1 open scope-out touches a file this plan edits:
- **#3739** (`review: extract reportSilentFallbackWithUser helper — collapse
  11-site withIsolationScope+setUser duplication`) touches `server/observability.ts`.

**Disposition: Acknowledge.** #3739 is a distinct concern — a helper extraction
to collapse the 11-site `withIsolationScope+setUser` duplication in
`reportSilentFallback`-family call sites. This plan extends `mirrorP0Deduped`
(a different primitive) and does not touch the 11 duplicated `setUser` sites.
Folding #3739 in would expand scope into an unrelated refactor on a
`single-user-incident` control. The scope-out remains open.

## Infrastructure (IaC)

This plan edits an EXISTING Terraform-managed Sentry resource
(`sentry_issue_alert.byok_art_33_breach`) — it introduces no new server,
secret, vendor, or persistent process. The change is an in-place attribute
update applied by the existing `apply-sentry-infra.yml` auto-apply pipeline.

### Terraform changes
- File: `apps/web-platform/infra/sentry/issue-alerts.tf` (existing root).
- Provider: `jianyuan/sentry 0.15.0-beta2` (pinned, lockfile committed).
- No new variables, no new secrets. (Item 4's `Member` pinning WOULD need a
  `sentry_member_id` variable + the founder's member id — deferred; not in this
  plan's TF changes.)

### Apply path
- (b) **Auto-apply via existing pipeline.** `apply-sentry-infra.yml` fires on
  push-to-main touching `issue-alerts.tf` and `-target`s `byok_art_33_breach`.
  The conditions edit is an in-place UPDATE (adds condition blocks), not a
  replace. Expected downtime: none (Sentry rule update is atomic). Blast radius:
  the single BYOK Art. 33 rule.

### Distinctness / drift safeguards
- `lifecycle.ignore_changes = [environment]` on `byok_art_33_breach` is
  unchanged — `conditions_v2`/`filters_v2`/`actions_v2` remain TF-owned source
  of truth (the whole point of an apply-created rule).
- The destroy-guard (`destroy-guard-filter-sentry.jq`) counts `conditions_v2`
  element shrink as `nested_deletes`. This edit GROWS conditions (1->3), so
  `nested_deletes = 0` — no `[ack-destroy]` needed (AC5).
- Beta-provider drift: schema re-validation on `terraform init -upgrade` remains
  the compensating control (per the scope-guard comment); this plan pins to the
  committed lockfile.

### Vendor-tier reality check
- Sentry issue-alert `conditions`/`filters`/`actions` are fully API-settable on
  the current tier (the 6 existing `sentry_issue_alert` resources prove it). No
  paid-tier gate on these condition types.

## Observability

```yaml
liveness_signal:
  what: "byok-art-33-breach + byok-cap-exceeded rule-existence assertion (read-only Sentry API GET by name)"
  cadence: "every apply-sentry-infra.yml run (post-apply) + optional recurring check"
  alert_target: "non-zero workflow exit -> GitHub Actions failure surface; Sentry cron monitor if recurring cron added"
  configured_in: "apps/web-platform/scripts/sentry-monitors-audit.sh (or apply-sentry-infra.yml post-apply step)"
error_reporting:
  destination: "Sentry (fatal, via mirrorP0Deduped) + pino stdout mirror (guaranteed even if Sentry swallowed)"
  fail_loud: "mirrorP0Deduped always emits logger.error before the try/catch-guarded Sentry call; pino is the durable signal"
failure_modes:
  - mode: "recurrence folds into existing fingerprint, no re-page"
    detection: "reappeared_event + regression_event conditions (item 1)"
    alert_route: "byok_art_33_breach rule -> ActiveMembers (N=1 founder)"
  - mode: "Sentry uninitialized/rate-limited, capture swallowed"
    detection: "pino logger.error mirror in container stdout (item 2)"
    alert_route: "container stdout / log aggregator (Better Stack)"
  - mode: "rule silently mis-wired (tag drift, dropped -target, muted)"
    detection: "rule-existence assertion (item 5)"
    alert_route: "apply-sentry-infra.yml workflow failure"
logs:
  where: "Sentry issue stream (fatal) + container stdout (pino)"
  retention: "Sentry 30-90d (not Art.33(5)-durable — durable audit-log tracked separately as #3603 rev-2 D-durable-audit-log)"
discoverability_test:
  command: "curl -fsS --max-time 10 -H \"Authorization: Bearer $SENTRY_AUTH_TOKEN\" \"https://de.sentry.io/api/0/projects/$SENTRY_ORG/$SENTRY_PROJECT/rules/\" | jq -e '[.[].name] | index(\"byok-art-33-breach\") and index(\"byok-cap-exceeded\")'"
  expected_output: "exit 0 (both rule names present); non-zero if either absent"
```

## Domain Review

**Domains relevant:** Engineering (CTO), Legal/Compliance (CLO), Product (CPO).

### Engineering (CTO)
**Status:** reviewed (plan-author assessment; domain leader to confirm at 2.5)
**Assessment:** In-place edit to an existing IaC-managed Sentry rule + two TS
emit-path changes routing through an existing fatal primitive. Low architectural
blast radius. The one design tension (preserving `art_33_breach` tag through
`mirrorP0Deduped`) is resolved by extending the primitive's ctx, not forking it.
Destroy-guard safety verified (adds, doesn't shrink, blocks). `-target=` allowlist
sweep required per Sharp Edge (scope-guard already covers `sentry_issue_alert`).

### Legal/Compliance (CLO)
**Status:** reviewed (plan-author assessment; gdpr-gate at 2.7)
**Assessment:** This hardens GDPR Art. 33(1) breach-notification timeliness. No
new processing activity (PA-23 covers BYOK telemetry). The `first_seen_at` clock
anchor (item 3) directly serves Art. 33(1)'s "without undue delay, and where
feasible, not later than 72 hours" requirement. Item 4's deferral keeps the N=1
over-disclosure risk at zero. userId is already pseudonymized at the emit boundary.

### Product/UX Gate
**Tier:** NONE.
**Decision:** N/A — no user-facing surface. This is an internal detection-control
hardening (Sentry rules + server emit paths + CI assertion). No new pages,
components, or flows.

## GDPR / Compliance Gate (Phase 2.7)

This plan touches a GDPR Art. 33 breach-detection surface at `single-user
incident` threshold — `/soleur:gdpr-gate` SHOULD run against this plan during
deepen-plan / work. Expected output: confirmation that the hardening serves Art.
33(1) timeliness without introducing new lawful-basis or special-category
processing. No new processing activity is created (PA-23 covers the telemetry).
The durable Art. 33(5) breach-documentation gap remains tracked separately
(#3603 rev-2 D-durable-audit-log) and is explicitly out of scope here.

## Risks & Mitigations

- **`action_match` semantics — SCHEMA-GROUNDED (deepen pass):** flipping
  `"all"` -> `"any"` is load-bearing for the 3-condition recurrence. The beta2
  `sentry_issue_alert.action_match` schema description (dumped this session)
  reads verbatim: *"Trigger actions when an event is captured by Sentry and
  `any` or `all` of the specified conditions happen. Valid values are: `all`,
  and `any`."* Since `first_seen_event`, `reappeared_event`, and
  `regression_event` are **mutually-exclusive event-lifecycle states** (a single
  captured event is exactly one of new / reappeared / regressed),
  `action_match = "all"` would require all three to be true for one event —
  never satisfiable. `"any"` is therefore REQUIRED, not merely preferred.
  `filter_match = "all"` is UNCHANGED (both tag filters must still match).
  **Precedent gap (verify-the-negative):** all 6 existing `sentry_issue_alert`
  resources use `action_match = "all"` — there is NO in-repo precedent for
  `"any"`. The change is schema-correct but novel here; flagged for reviewer
  scrutiny. AC1 asserts `action_match = "any"`.
- **`event_frequency` vs discrete conditions:** D4 chose discrete conditions.
  If `reappeared_event`/`regression_event` semantics don't cover a same-session
  re-fire within one open issue, `event_frequency` (>=1 in interval) is the
  fallback — the schema confirms it's available (`comparison_type` req
  `count`/`percent`, `value` req number, `interval` opt). Re-evaluate at /work if
  the discrete conditions prove insufficient.
- **`mirrorP0Deduped` 1h dedup window:** the breach dedups per
  `userId:op:conversationId` for 1 hour. This is intentional (<=72 samples in the
  notifiability window without burying the stream) and Art.33-justified in the
  primitive's docstring. A new conversationId is a new key -> re-pages. No change.
- **Liveness endpoint shape:** the project rules endpoint
  (`/projects/{org}/{project}/rules/`) returns ISSUE alerts; the org `/monitors/`
  endpoint is Crons-only (per the `-target=` allowlist Sharp Edge — that endpoint
  excludes uptime/issue rules). Verify the rules endpoint returns the BYOK rules
  by name at /work before freezing the AC4 command.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (This section is filled; threshold = single-user incident.)
- **`-target=` allowlist sweep:** `sentry_issue_alert` is already in
  `apply-sentry-infra.yml`'s `-target` set AND in the scope-guard's allowlist
  (`test-destroy-guard-sentry-scope-guard.sh`). This plan does NOT add a new
  resource type, so the scope-guard needs no extension — but the full-suite exit
  gate (`tests/scripts/test-all.sh`) must still pass (AC8). Verify the
  destroy-guard counter test fixture still represents the guarded `conditions_v2`
  shape after the 1->3 condition growth.
- **Worktree-vs-HEAD staleness (D5):** the on-disk `issue-alerts.tf` was 177
  lines at planning time; HEAD is 298. Always `git show HEAD:<path>` before
  editing; do not trust the worktree checkout until /work Phase 0 re-syncs.
- **Liveness must read the invariant, not a proxy:** the AC4 assertion checks
  rule EXISTENCE by name. Existence is necessary but not sufficient for "the rule
  will page" — a rule that exists but has the wrong `filters_v2` (tag drift)
  passes an existence check while being non-functional. Consider asserting the
  `filters_v2` tag shape too, not just the name (deepen-plan / review judgment).
- **Item 4 cannot be "fixed" without an input we don't have:** do NOT let /work
  invent a placeholder member id. The deferral is correct; sharpen the issue,
  don't patch the rule.
