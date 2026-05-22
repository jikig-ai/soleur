---
title: "feat(today-card): wire GitHubCard + KbDriftCard Spawn-agent / Fix-link buttons — PR-A substrate"
type: feat
date: 2026-05-22
lane: cross-domain
requires_cpo_signoff: true
issue: 4124
umbrella_independence: "#4310 PR-J — mechanically independent; this plan touches no PR-J shared files (no new action classes, no template_registry rows, no tier-array changes)"
brand_survival_threshold: single-user incident
---

# feat(today-card): wire GitHubCard + KbDriftCard Spawn-agent / Fix-link buttons — PR-A substrate

Closes #4124 (substrate slice). Filed-as-follow-up: PR-B (Anthropic leader-prompt loop replacing deterministic acknowledgment stub; ADR-039).

## Overview

Drop `disabled aria-disabled="true" title="Wires in PR-H+1"` from `GitHubCard` + `KbDriftCard` in `components/dashboard/today-card.tsx` and wire their `onClick` handlers end-to-end so an operator click produces (a) one `action_sends` row, (b) one Inngest event, (c) **exactly one visible artifact on the operator's GitHub repo within ≤ 60s** — a deterministic acknowledgment stub: templated PR comment for PR-shaped sources, issue label `soleur/acknowledged` for everything else. The card transitions to an optimistic "Acknowledged" pill on the 200 response (no polling); operator confirms by opening the linked GitHub artifact.

The Anthropic-SDK leader-prompt loop that replaces the deterministic stub is **out of scope for PR-A** and lives in PR-B (filed before this PR merges; ADR-039 authored in PR-B).

This is **PR-A** in a deliberate two-PR split. Three-agent plan review (DHH + Kieran + code-simplifier) trimmed the prior draft of `agent_runs` table, polling endpoint, scheduled cron, 3 speculative follow-ups, and 3 acknowledgment-template variants; this rev encodes the trimmed shape.

## Research Reconciliation — Spec vs. Codebase

Plan-time research surfaced 6 places where the issue body (#4124) does not match current code reality. Reconciled below before phases.

| Spec claim (#4124 body) | Reality (file:line) | Plan response |
|---|---|---|
| "Action class definitions... rows in `action_class_map` + scope_grants tiering matrix" | All five spawn classes already exist: `engineering.pr_review_pending`, `engineering.ci_failed`, `triage.p0p1_issue`, `security.cve_alert`, `knowledge.kb_drift` (`server/scope-grants/action-class-map.ts:29-37`). | **No new action classes.** Zero rows added to `action-class-map.ts`. Collision footprint with PR-J #4310 reduces to zero shared files for PR-A. |
| "POST routes at `/api/dashboard/today/[id]/spawn`" | `/send/route.ts:73-339` already exists with full auth + isGranted + tier-dispatch + template-gate + writeActionSend + 409/403/422 branching. The only gap is `auto` tier rejection (`route.ts:158-167` returns 400 for `auto`). | **Reuse `/send/route.ts` for all classes.** Fix the `auto`-tier gap by bumping `knowledge.kb_drift` default tier from `"auto"` to `"draft_one_click"` in `action-class-map.ts:86`. |
| "Approval signature: `sha256(JSON.stringify(orderedKeys({founder_id, message_id, typed_value, ts})))`" | Actual signed surface is `{founderId, messageId, typedValue, perSendBodyHash, recipientHash, templateHash, tier}` — `ts` intentionally omitted (`write-action-send.ts:74-91`). | Plan body uses the actual surface. No code change. |
| "Calls Anthropic SDK with the leader prompt loop... persists turn cost via `recordByokUseAndCheckCap`" | Both existing Inngest stubs (`cfo-on-payment-failed.ts:198-217` + `github-on-event.ts:207-219`) return `{tokenCount:0, unitCostCents:0}` with explicit "wires in alongside cohort onboarding" markers. **Anthropic-SDK-inside-Inngest is greenfield.** `record_byok_use_and_check_cap` RPC confirmed at `supabase/migrations/061_byok_audit_workspace_id_rpcs.down.sql:39`. | **Out of scope for PR-A.** PR-A's Inngest function makes zero Anthropic SDK calls — emits one GitHub artifact via `createGitHubAppClient(installationId, founderId)`. PR-B replaces the stub with the leader loop and writes ADR-039. |
| "audit_github_token_use auto-populates from Octokit calls (PR-H+1)" | **Confirmed.** `octokit.hook.after("request",...)` + `octokit.hook.error("request",...)` both fire `void recordGithubApiCall(...)` at `server/github/app-client.ts:104-140` → `record_github_token_use` RPC at `server/github/audit-writer.ts:144-172`. | Plan AC1 requires every Octokit call routes through `createGitHubAppClient` (NOT `probeOctokit` — that factory is audit-skipping per `probe-octokit.ts:14`). |
| "Template authorization will gate the new spawn classes" | `template-registry.ts:50` shows `default_legacy` template is class-agnostic (`action_class: null`); ALL message rows hash to the same `default_legacy` template_hash. PR-I (#4078) first-send-IS-authorization (`is-template-authorized.ts:74-80` `PredicateResult.first_send`) covers the spawn classes without adding registry rows. | **No new `TEMPLATE_REGISTRY` rows needed in PR-A.** First-send-IS-authorization auto-mints the `template_authorizations` row on first click per class. |

## User-Brand Impact

**If this lands broken, the user experiences:** the operator's `/dashboard` Today section — clicking "Spawn review agent" on a `pr-*` source card produces no PR comment on their connected GitHub repo within 60s, leaving them unsure whether Soleur acknowledged the click. Worse: the card disappears (StripeCard precedent's `setArchived(true)`) and the operator has no in-product affordance to inspect or retry.

**If this leaks, the user's GitHub workflow is exposed via:** wrong-installation routing inside the new Inngest function — if `createGitHubAppClient(installationId, founderId)` resolves `installationId` from anything other than `users.github_installation_id` keyed by server-derived `founderId`, an action triggered by Operator A could write a PR comment / issue label on Operator B's connected repo. The cross-tenant leak vector is the `installationId` source-of-truth.

- **Brand-survival threshold:** `single-user incident` — wrong-installation routing or an empty-result UX after click are both unrecoverable for a solo-operator trust footprint.

Per `hr-weigh-every-decision-against-target-user-impact`: every design choice in this plan is justified against ONE of (a) closing the empty-result UX gap (deterministic acknowledgment artifact on every click), (b) closing the wrong-installation cross-tenant vector (`users.github_installation_id` invariant), or (c) keeping the dead-letter window bounded (try/catch + Sentry on `inngest.send` failure; retry via new `messages` row).

## Goals

1. Drop `disabled aria-disabled="true"` from `GitHubCard` + `KbDriftCard` (`components/dashboard/today-card.tsx:134-145, 202-214`). Buttons fire `onClick` handlers mirroring `StripeCard`'s shape.
2. Fix `knowledge.kb_drift` tier mismatch — bump default tier from `"auto"` to `"draft_one_click"` in `action-class-map.ts:86`. KbDriftCard's "Fix link" click reaches a non-400 path on `/send`.
3. Ship the new Inngest function `agent-on-spawn-requested.ts` that consumes `agent.spawn.requested` events and emits exactly one GitHub artifact per event (PR sources → PR comment; everything else → issue label `soleur/acknowledged`).
4. Extract StripeCard's click logic into a reusable `useActionSend()` hook so GitHubCard + KbDriftCard share the 200/403/409 branching without code duplication (three callers after this PR).
5. Add `acknowledged_at` + `artifact_url` + `failure_reason` columns to `action_sends` (migration 062) — the Inngest function UPDATEs these on completion; the card renders "Acknowledged" pill optimistically on the 200 response.
6. Ship test coverage: component-level click test (first of its kind for today-card), route-level kb_drift tier + Inngest dispatch tests, Inngest function happy + cross-tenant + GitHub-401 + idempotency tests.

## Non-Goals (Out of Scope — filed as follow-ups before merge)

1. **Anthropic SDK leader-prompt loop** — PR-B (filed before this PR merges; ADR-039 authored in PR-B).
2. **Copywriter pass on acknowledgment + failure strings** — filed as follow-up issue. Provisional copy ships in PR-A.
3. **Cross-installation spawn (one founder, multiple installations)** — V2.
4. **Per-founder spawn quota / rate-limit** — V2.
5. **Transactional outbox** between `action_sends` INSERT and `inngest.send` — accept the ~50ms partial-failure window; try/catch + Sentry per `cq-silent-fallback-must-mirror-to-sentry`.
6. **WORM uniqueness relaxation** on `action_sends(message_id)` — retry uses a NEW `messages` row.
7. **Real-time channel / polling for acknowledgment progress** — optimistic UI on 200; operator inspects GitHub for confirmation.
8. **Per-action-class artifact specialization beyond the 2 paths** — kb_drift draft-branch creation, severity-only CVE comments, etc., land in PR-B.

## Stakeholders

- **Operator** (single-user, ops@jikigai.com) — primary consumer; brand-survival threshold gate.
- **CPO** (sign-off at plan time, encoded as ACs below; `user-impact-reviewer` at PR-review).
- **CTO** (Anthropic-SDK-in-Inngest pattern — flagged for PR-B, not PR-A).
- **CLO** (Article 30 PA-19 entry — autonomous-acknowledgment processing activity).
- **Review-time agents** (`data-integrity-guardian`, `security-sentinel`, `observability-coverage-reviewer`, `user-impact-reviewer`).

## Architecture / Approach

### Click → action_sends → Inngest event → GitHub artifact (PR-A substrate)

```text
[GitHubCard / KbDriftCard click]
   │
   ▼
useActionSend() ── POST /api/dashboard/today/<id>/send ──┐
                                                          ▼
        cookie-scoped supabase.auth.getUser()
        → messages SELECT (RLS owner-only, belt-and-suspenders user_id eq)
        → isKnownActionClass guard
        → isGranted(supabase, founderId, actionClass)
        → tier dispatch:
            auto / auto_with_digest → 400 (kb_drift now draft_one_click — no longer hits)
            draft_one_click          → straight to write
            approve_every_time       → 409 requires_confirmation (typed-confirm modal)
        → tierRequiresTemplateAuth gate (draft_one_click only)
            → first-send-IS-authorization (PR-I) auto-mints template_authorizations row
        → writeActionSend(...) ── INSERT action_sends row + Sentry breadcrumb
        → try { await inngest.send({ name: "agent.spawn.requested", data: {founderId, messageId, actionClass, sourceRef, actionSendId}}) }
          catch (e) { reportSilentFallback(e, ...); return 200 { ..., degraded: "enqueue_failed" } }
        → archive messages.status
        → return 200 { id, action_class, tier, action_send_id, artifact_view_url }
   │
   ▼
client: setAcknowledged(artifact_view_url)
        ← card transitions to "Acknowledged — View on GitHub" pill (single render, no polling)
        ← operator clicks pill → opens GitHub PR / issue page
```

### Inngest function (deterministic acknowledgment stub)

```ts
// server/inngest/functions/agent-on-spawn-requested.ts
//
// Naming follows the <noun>-on-<event>.ts precedent used by
// github-on-event.ts, cfo-on-payment-failed.ts, workspace-reconcile-on-push.ts.

// Event payload type is EXPLICITLY narrowed to OMIT installationId — the field
// is server-resolved inside step 1 from `users.github_installation_id`. If a
// future event-author tries `event.data.installationId`, tsc fails. This is
// the TypeScript-level guard counterpart to AC1's grep sentinel.
interface AgentSpawnRequestedEvent {
  name: "agent.spawn.requested";
  data: {
    founderId: string;
    messageId: string;
    actionClass: ActionClass;
    sourceRef: string;
    actionSendId: string;
    // NO installationId — server-resolved.
  };
}

inngest.createFunction(
  { id: "agent-on-spawn-requested", idempotency: "event.data.actionSendId", retries: 3 },
  { event: "agent.spawn.requested" },
  async ({ event, step }) => {
    const { founderId, messageId, actionClass, sourceRef, actionSendId } = event.data;

    // Step 1: resolve installation_id from users (server-derived, NEVER from payload).
    const installationId = await step.run("resolve-installation", async () => {
      const sb = getServiceRoleClient();
      const { data, error } = await sb.from("users")
        .select("github_installation_id")
        .eq("id", founderId)
        .maybeSingle();
      if (error || !data?.github_installation_id) {
        throw new Error(`agent-on-spawn: no github_installation_id for founder ${founderId}`);
      }
      return data.github_installation_id as number;
    });

    // Step 2: route through createGitHubAppClient (audit hook attaches; per-Octokit
    // audit_github_token_use rows auto-populate per PR-H+1 #4098 factory).
    const octokit = await createGitHubAppClient(installationId, founderId);

    // Step 3: deterministic acknowledgment — 2 paths only (collapsed from prior 5).
    //   - sourceRef starts with "pr-" → PR comment
    //   - everything else (ci-, issue-, cve-, secret-scan-, link-, anchor-) → issue label "soleur/acknowledged"
    // The label path is idempotent at the GitHub API level (re-adding an existing label is a no-op).
    // PR-B replaces this body with the Anthropic leader-prompt loop + per-class specialization.
    const artifactUrl = await step.run("post-acknowledgment", async () => {
      const { owner, repo, number } = parseSourceRef(sourceRef); // pr-123 / issue-456 / link-/x/y.md
      if (sourceRef.startsWith("pr-")) {
        const { data } = await octokit.rest.issues.createComment({
          owner, repo, issue_number: number,
          body: ACK_PR_COMMENT_TEMPLATE, // "Soleur acknowledged — full agent loop landing in PR-B"
        });
        return data.html_url;
      } else {
        await octokit.rest.issues.addLabels({
          owner, repo, issue_number: number,
          labels: ["soleur/acknowledged"],
        });
        return `https://github.com/${owner}/${repo}/issues/${number}`;
      }
    });

    // Step 4: UPDATE action_sends with acknowledgment columns (migration 062).
    await step.run("mark-acknowledged", async () => {
      await getServiceRoleClient()
        .from("action_sends")
        .update({ acknowledged_at: new Date().toISOString(), artifact_url: artifactUrl })
        .eq("id", actionSendId);
    });
  }
);
```

**No `runWithByokLease` scope in PR-A.** No Anthropic SDK call. The `byok-audit-writer-sweep` lint test (`test/server/byok-audit-writer-sweep.test.ts:67-200`) passes because no new `runWithByokLease(` site is added.

### Migration 062 — `action_sends` acknowledgment columns

```sql
-- 062_action_sends_acknowledgment.sql

ALTER TABLE public.action_sends
  ADD COLUMN acknowledged_at timestamptz,
  ADD COLUMN artifact_url    text,
  ADD COLUMN failure_reason  text;

-- Comment: the Inngest function `agent-on-spawn-requested` is the sole writer
-- of acknowledged_at + artifact_url + failure_reason. The action_sends WORM
-- trigger does NOT fire on these columns (the trigger guards INSERT-time
-- immutability; these UPDATE-only columns are new state added post-INSERT
-- by the autonomous handler). Verify against `supabase/migrations/<WORM_TRIGGER>.sql`.

COMMENT ON COLUMN public.action_sends.acknowledged_at IS
  'Set by agent-on-spawn-requested Inngest function on successful artifact emit. NULL = pending.';
COMMENT ON COLUMN public.action_sends.artifact_url IS
  'GitHub URL of the acknowledgment artifact (PR comment or issue page). Single-fetch, no listing.';
COMMENT ON COLUMN public.action_sends.failure_reason IS
  'Set on terminal Inngest failure (e.g., github_installation_unauthorized). NULL on success or in-flight.';
```

`062_action_sends_acknowledgment.down.sql` drops the three columns. No data loss for PR-A (operator opens GitHub independently for canonical view); rollback is safe.

**WORM-trigger compat note (to verify at /work-time):** confirm the existing `action_sends` WORM trigger gates INSERT immutability only, not UPDATE on the three new columns. If the trigger covers UPDATE, migration 062 must add a column-list exception for `acknowledged_at / artifact_url / failure_reason`.

## Files to Edit

- `apps/web-platform/components/dashboard/today-card.tsx` — drop `disabled` on GitHubCard + KbDriftCard; replace inline send logic in `StripeCard` with `useActionSend()`; add `onClick` handlers; render "Acknowledged — View on GitHub" pill on the 200 response (no polling).
- `apps/web-platform/server/scope-grants/action-class-map.ts` — bump `knowledge.kb_drift` default tier from `"auto"` to `"draft_one_click"` (line 86). Update `test/server/scope-grants/action-class-exhaustive.test.ts` per the in-file checklist.
- `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts` — add `inngest.send(...)` call AFTER `writeActionSend` and BEFORE messages archive flip; wrap in try/catch with `reportSilentFallback` + `degraded: "enqueue_failed"` flag in 200 response on enqueue failure. Extend 200 success payload with `action_send_id` + `artifact_view_url` (server constructs a deterministic GitHub URL from `sourceRef` + the operator's `users.github_installation_id`-resolved owner/repo).
- `apps/web-platform/components/ui/typed-confirm-modal.tsx` — accept optional `actionTargetLabel?: string` prop, backwards-compatible default = `recipientExcerpt`.
- `apps/web-platform/test/server/scope-grants/action-class-exhaustive.test.ts` — bump tier expectation for `knowledge.kb_drift`.

## Files to Create

- `apps/web-platform/hooks/use-action-send.ts` — shared click-handler hook returning `{ onSend, isPending, error, acknowledged, artifactUrl, confirming, onConfirmTyped, onCancelConfirm }`. Extracted from StripeCard (today-card.tsx:221-462). Hooks dir kebab-case precedent: `use-conversations.ts`, `use-onboarding.ts`.
- `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts` — new Inngest function (idempotency on `actionSendId`, retries: 3). Name follows existing `<noun>-on-<event>.ts` precedent.
- `apps/web-platform/server/inngest/agent-acknowledgment-templates.ts` — `ACK_PR_COMMENT_TEMPLATE` constant + `parseSourceRef` helper.
- `apps/web-platform/supabase/migrations/062_action_sends_acknowledgment.sql` + `062_action_sends_acknowledgment.down.sql`.
- `apps/web-platform/supabase/migrations/062_action_sends_acknowledgment.test.ts` — schema assertion (3 new columns NULL-defaulting; WORM-trigger compat).
- `apps/web-platform/test/components/today-card.click.test.tsx` — first component-level click test (happy-dom; method-aware `vi.fn` fetch mock; covers happy-path GitHub PR comment + KbDrift label + 403 no_grant + 409 requires_confirmation + 409 already_sent + degraded enqueue_failed).
- `apps/web-platform/test/api/dashboard/today/[id]/send-route.spawn.test.ts` — extends existing send-route matrix: kb_drift draft_one_click happy-path; `inngest.send` mock assertion (called once after writeActionSend, before archive); enqueue-failure `degraded` flag.
- `apps/web-platform/test/server/inngest/agent-on-spawn-requested.test.ts` — happy (PR comment + label) + cross-tenant-installation-mismatch (founder lacks installation) + GitHub-401 + idempotency-on-retry + UPDATE action_sends acknowledgment columns asserted.
- `apps/web-platform/test/server/inngest/installation-id-source-of-truth.test.ts` — sentinel test combining: (a) grep negative-pattern over the function file for `event\.data\.installationId|payload\.installationId|\.data\.installationId|\binstallationId\b.*=.*event` (strengthened per Kieran P1-5), (b) TypeScript-level guard — assert at module load that `AgentSpawnRequestedEvent['data']` does NOT contain an `installationId` field via a conditional-type compile-check that fails tsc if the field is added.
- `apps/web-platform/test/server/scope-grants/kb-drift-tier-bump.test.ts` — assertion: `ACTION_CLASS_DEFAULTS["knowledge.kb_drift"] === "draft_one_click"` + producer-side cascade sweep `rg -nE "kb_drift.*['\"]auto['\"]|['\"]auto['\"].*kb_drift" apps/web-platform/server apps/web-platform/app` returns zero (no other site assumes auto-tier semantics for kb_drift).
- **Append to `knowledge-base/legal/article-30-register.md`**: **Processing Activity 19** (next strict-ordinal entry — PA-16 is published out-of-order at line 306 between PA-17 and PA-18, but the next available ordinal is genuinely 19).

## Open Code-Review Overlap

`gh issue list --label code-review --state open --json number,title,body --limit 200` queried 2026-05-22. Results: 1 open issue (#4282 — fixture-drift for `template_id` NOT NULL on tests).

For each planned file path, jq scan of issue bodies: **none** match exactly. #4282 touches 5 test files orthogonal to this PR's `Files to Edit` list. **Decision: no fold-in, no acknowledgment, no defer.** #4282 continues on its own track.

`## Open Code-Review Overlap: None.`

## Domain Review

**Domains relevant:** Product, Engineering, Legal.

### Product (CPO)

**Status:** reviewed
**Assessment:** ⏸ HOLD → ✅ APPROVED with 5 threshold conditions, encoded as AC1-AC5 below. Recommends PR-A/PR-B split (applied). KbDrift tier fix: option (A) bump default (applied).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Concurs with PR-A/PR-B split. `installationId` source-of-truth = `users.github_installation_id` (verified at `supabase/migrations/011_repo_connection.sql:8` + `052_multi_source_dedup.sql:159-161` UNIQUE partial index). KbDrift tier option diverges from CPO — CTO prefers (C) separate `/spawn` route; plan resolves to (A) for substrate simplicity. ADR-039 deferred to PR-B.

### Legal (CLO) — covered by GDPR gate output

**Status:** advisory — handled inline at Phase 2.7. PA-19 register append required (mandatory pre-merge).

### Brainstorm-recommended specialists

- **copywriter** — recommended by CPO; **deferred** to a filed follow-up issue (see `## Follow-ups`). Provisional copy ships in PR-A; no UX-blocking copy concerns at single-user-incident threshold for the first iteration.
- **ux-design-lead** — skipped (no new page; same card chrome with one new pill state).

### Product/UX Gate

**Tier:** advisory
**Decision:** reviewed (no new visual states beyond enabling existing buttons + an "Acknowledged" pill — text + color, no novel visual).
**Agents invoked:** spec-flow-analyzer, cpo.
**Skipped specialists:** ux-design-lead (no new page); copywriter (deferred to follow-up).
**Pencil available:** N/A.

#### spec-flow-analyzer findings (9 GAPs)

1. **GAP #1 (no agent_run_id surface)** — resolved by adding `action_send_id` to the 200 response.
2. **GAP #2 (no realtime/poll channel)** — accepted: optimistic UI + Sentry breadcrumb on Inngest failure; operator confirms via GitHub. No polling endpoint in PR-A.
3. **GAP #3 (TypedConfirmModal copy mismatch)** — fixed by `actionTargetLabel?: string` prop (backwards-compatible default).
4. **GAP #4 (`already_sent` payload lacks existing action_send id)** — accepted; the "already_sent" toast renders "Already actioned — refresh to see current state" for PR-A. Resolve-prior-run UX deferred (issue filed only if operator hits this in practice).
5. **GAP #5 (KbDrift tier=`auto` vs. route 400) — CRITICAL** — fixed via tier bump in `action-class-map.ts:86`.
6. **GAP #6 (no transactional outbox; dead-letter trap) — CRITICAL** — partial mitigation: try/catch + `reportSilentFallback` on `inngest.send` failure with `degraded: "enqueue_failed"` flag in 200 response. Retry via NEW `messages` row.
7. **GAP #7 (Anthropic per-turn idempotency + BYOK budget cap)** — N/A for PR-A. PR-B follow-up.
8. **GAP #8 (WORM uniqueness blocks retry)** — accepted; new `messages` row is the retry path.
9. **GAP #9 (cascade order lifted from StripeCard)** — fixed: `resolve-installation` step at top of Inngest handler (before artifact emit) so cross-tenant guard fires before any GitHub API call.

## Infrastructure (IaC)

**Skipped.** No new infrastructure (no new servers, vendors, DNS records, TLS certs, secrets, firewall rules, monitoring webhooks). All code changes target already-provisioned surfaces (Next.js app, Supabase schema, Inngest self-hosted per ADR-030, existing GitHub App installation).

## Observability

```yaml
liveness_signal:
  what: "agent.spawn.requested event flow — every action_sends INSERT must reach acknowledged_at IS NOT NULL within 60s"
  cadence: "per-click; spot-check via Sentry tag filter feature=spawn-agent"
  alert_target: "Sentry tag feature=spawn-agent, op=ack-latency; reportSilentFallback when inngest.send throws OR when Inngest function step throws"
  configured_in: "server/inngest/functions/agent-on-spawn-requested.ts step('mark-acknowledged') + try/catch around inngest.send at app/api/dashboard/today/[id]/send/route.ts (after writeActionSend, before archive)"

error_reporting:
  destination: "Sentry (existing @sentry/nextjs integration)"
  fail_loud: true  # reportSilentFallback at every catch site; Sentry tag includes founder_id_hash + action_class + op

failure_modes:
  - mode: "installation_id resolution failure (founder lacks github_installation_id)"
    detection: "Inngest step throws inside step.run('resolve-installation', ...)"
    alert_route: "Sentry — feature=spawn-agent, op=resolve-installation; transient (function retries 3x then DLQs); final-retry UPDATE action_sends.failure_reason='github_installation_unauthorized'"
  - mode: "cross-installation routing attempt (event payload installationId attempted)"
    detection: "TypeScript event-payload type omits installationId field — tsc fails at compile if added; runtime sentinel test enforces negative grep"
    alert_route: "tsc fail at CI (unreachable at runtime by construction)"
  - mode: "GitHub installation 401/403 (revoked between webhook ingest and click)"
    detection: "Octokit hook.error fires; audit row written with response_status=401; Inngest step throws"
    alert_route: "Sentry — feature=spawn-agent, op=github-401; action_sends.failure_reason='github_installation_unauthorized'"
  - mode: "Inngest event enqueue failure between writeActionSend and inngest.send"
    detection: "try/catch around inngest.send; on failure, reportSilentFallback + 200 response carries degraded='enqueue_failed'"
    alert_route: "Sentry — feature=spawn-agent, op=inngest-enqueue; operator sees 'Acknowledged (queued)' card state; manual retry via new messages row"
  - mode: "Anthropic-SDK use in PR-A (must be zero)"
    detection: "byok-audit-writer-sweep test fails if any new runWithByokLease() site is added without persistTurnCost"
    alert_route: "CI fail (pre-merge)"

logs:
  where: "Better Stack (pino sink via existing transport — verify package.json:dependencies for pino-*)"
  retention: "30 days standard; action_sends rows match existing WORM retention"

discoverability_test:
  command: |
    # No SSH. Smoke test runs against dev Supabase + dev GitHub App installation via API.
    bun run apps/web-platform/scripts/spawn-agent-smoke.ts --founder-id "$DEV_OPERATOR_ID" --action-class engineering.pr_review_pending --source-ref pr-1
  expected_output: |
    [smoke] click -> 200 OK (action_send_id=<uuid>, artifact_view_url=<github-url>)
    [smoke] inngest event enqueued
    [smoke] action_sends.acknowledged_at set within 60s
    [smoke] action_sends.artifact_url set
    [smoke] audit_github_token_use row count delta >= 1 (factory hook fired)
    [smoke] PR comment exists on the dev repo at action_sends.artifact_url
    [smoke] PASS
```

## GDPR / Compliance Gate (Phase 2.7 output)

Triggered: new processing activity (autonomous-acknowledgment runtime on operator-session-derived data via Inngest, writing to operator's connected GitHub repo). Although no LLM call lands in PR-A, the substrate is the new processing activity per the gate's expanded coverage criteria.

**Append to `knowledge-base/legal/article-30-register.md` as Processing Activity 19** (next strict-ordinal entry; PA-16 is published out-of-order at line 306 between PA-17 and PA-18 — known register disorder, no impact on PA-19 placement).

```markdown
## Processing Activity 19 — Autonomous-acknowledgment runtime (Inngest spawn-agent deterministic stub, PR-A #4124)

- **Purpose:** Operator-initiated, single-click acknowledgment of a GitHub-sourced or KB-drift TodayCard. On click, Soleur posts exactly one deterministic GitHub artifact (PR comment for PR-shaped sources; issue label `soleur/acknowledged` for everything else) into the operator's connected repo via their existing GitHub App installation. Closes the empty-result UX gap; foundation for the autonomous leader-loop runtime tracked under PR-B (Processing Activity 20, deferred).
- **Lawful basis:** Art. 6(1)(b) — performance of a contract (the operator subscribes to Soleur to delegate routine GitHub-repo actions; the operator's click is the explicit request).
- **Categories of data:**
  - Operator identifier: `users.id` (uuid), `users.github_installation_id` (bigint).
  - Repo + ref context: `messages.source_ref` (e.g., `pr-123`, `issue-456`).
  - Audit columns: `audit_github_token_use.{installation_id, repo_full_name, endpoint, response_status}` (existing — auto-populated by `createGitHubAppClient` factory hook per PR-H+1).
  - `action_sends.{acknowledged_at, artifact_url, failure_reason}` (new in migration 062 on existing table).
- **Recipients:** GitHub API (sub-processor; existing DPA at `knowledge-base/legal/data-processing-agreements/github.md`).
- **International transfers:** US — covered by existing GitHub DPF adequacy decision.
- **Retention:** matches existing `action_sends` retention policy (no change). `audit_github_token_use` 90 days (existing).
- **TOMs:** RLS owner-only SELECT on `action_sends`; service-role-only UPDATE on the three new columns (Inngest function); WORM trigger immutability on INSERT (existing — UPDATE on the new columns confirmed compatible at migration 062 review-time); per-Octokit-call audit row (PR-H+1 factory hook); cross-tenant guard via TypeScript event-payload type omitting `installationId` + runtime sentinel test.
- **DPIA:** lightweight required; operator-initiated autonomous action is contract-scoped, not autonomous-on-behalf-of-third-party. Zero new sub-processors, zero new cross-border flows.
- **Operator notice:** existing dashboard surface already discloses connected GitHub installations let Soleur act on the repo; no new consent flow required.
```

**Not triggered:** Art. 9 special-category data; no DL-04 DSAR regression probe (no new owner-keyed table — three new columns on existing `action_sends` are already covered by the existing DSAR export of that table); no TS-05 Storage cleanup.

**Critical (Art. 30 §1):** PA-19 entry is **load-bearing** for PR-A. Plan AC blocks merge on PA-19 entry existence.

**Disclaimer:** GDPR gate output is **advisory**. Operator should review the PA-19 draft above before merge and may amend wording. No legal-counsel review performed.

## Acceptance Criteria

### Pre-merge (PR)

**5 CPO threshold conditions:**

1. `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts` MUST route every Octokit call through `createGitHubAppClient(installationId, founderId)` (NOT `probeOctokit`, NOT raw `App.octokit`, NOT `new Octokit(...)`). Sentinel: `grep -nE "probeOctokit\(|new Octokit\(" apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts apps/web-platform/server/inngest/agent-acknowledgment-templates.ts | wc -l` returns `0`.

2. `installationId` MUST resolve from `users.github_installation_id` keyed by **server-derived** `founderId`. Two-layer enforcement: (a) TypeScript — `AgentSpawnRequestedEvent['data']` omits `installationId` field; any attempt to read `event.data.installationId` fails `tsc`. (b) Runtime sentinel — `test/server/inngest/installation-id-source-of-truth.test.ts` runs `grep -nE "event\.data\.installationId|payload\.installationId|\.data\.installationId|\binstallationId\b\s*[:=]\s*event"` against the function source and asserts `0` matches. Both must pass.

3. `ACTION_CLASS_DEFAULTS["knowledge.kb_drift"] === "draft_one_click"` in `action-class-map.ts`. Verified by `test/server/scope-grants/kb-drift-tier-bump.test.ts`. KbDriftCard "Fix link" click reaches a non-400 path on `/send` (verified by `today-card.click.test.tsx` kb-drift happy-path). Cascade sweep: `rg -nE "kb_drift.*['\"]auto['\"]|['\"]auto['\"].*kb_drift" apps/web-platform/server apps/web-platform/app` returns zero hits outside this PR's diff.

4. Deterministic acknowledgment artifact lands in operator's GitHub repo within 60s of click. Smoke test asserts `action_sends.acknowledged_at IS NOT NULL` AND `action_sends.artifact_url IS NOT NULL` within 60s timeout; PR comment OR issue label verified via Octokit GET.

5. Inngest function idempotency key = `event.data.actionSendId`. Sentinel test asserts duplicate event fires produce exactly one updated `action_sends` row + exactly one artifact (PR comment count OR label count via Octokit fixture).

**Engineering ACs:**

6. `/send` route adds `inngest.send(...)` call AFTER `writeActionSend` AND BEFORE `messages.status` archive flip. Order verified by reading `route.ts` post-merge and confirming source-line ordering. **Degraded path:** if `inngest.send` throws, the route MUST catch + `reportSilentFallback` + return 200 with `degraded: "enqueue_failed"` flag (NOT return 500 — the action_sends row is already written; returning 500 would suggest retry to the operator and create orphans). Verified by `send-route.spawn.test.ts`.

7. `/send` 200 success payload includes `action_send_id` (uuid) AND `artifact_view_url` (string — deterministic from sourceRef + operator's owner/repo) AND optional `degraded` field. Verified by `send-route.spawn.test.ts`.

8. `writeActionSend` remains the only INSERT path to `action_sends` (existing sentinel-sweep test passes — no new writers).

9. No `runWithByokLease(` site added in PR-A. Verified by `byok-audit-writer-sweep` lint test passing.

10. Migration `062_action_sends_acknowledgment.sql` applies cleanly on dev; three new columns NULL-defaulting; WORM trigger compat verified (UPDATE on these columns NOT blocked by trigger).

11. PA-19 appended to `knowledge-base/legal/article-30-register.md`. Verified: `grep -c "^## Processing Activity 19" knowledge-base/legal/article-30-register.md` returns `1`.

12. `TypedConfirmModalProps` adds optional `actionTargetLabel?: string`, backwards-compatible default = `recipientExcerpt`. GitHubCard `approve_every_time` flow (cve_alert, secret-scan) passes `actionTargetLabel="PR #<n> / issue #<n>"`. Verified by component test.

13. `useActionSend()` hook lives at `apps/web-platform/hooks/use-action-send.ts`. Three callers (StripeCard, GitHubCard, KbDriftCard) all consume it. Hook returns the structured `{ onSend, isPending, error, acknowledged, artifactUrl, confirming, onConfirmTyped, onCancelConfirm }` shape.

### Post-merge (operator)

14. Operator triggers a real GitHub webhook (PR review pending) → card renders → operator clicks "Spawn review agent" → expects: (a) 200 response with `artifact_view_url` populated, (b) card transitions to "Acknowledged — View on GitHub" pill within 1s, (c) PR comment appears on the dev repo within 60s, (d) `action_sends.acknowledged_at IS NOT NULL` + `artifact_url` matches the comment URL, (e) `audit_github_token_use` row count incremented by ≥ 1. Verifiable via Supabase MCP read + GitHub repo visual inspection.

## Test Scenarios (Given / When / Then)

1. **Given** a `knowledge.kb_drift` TodayCard rendered with the new `draft_one_click` tier and `source_ref="link-/legal/privacy.md"`, **when** the operator clicks "Fix link", **then** the route returns 200 with `artifact_view_url=https://github.com/.../issues/<n>`, an `action_sends` row exists, an Inngest event was enqueued, `action_sends.acknowledged_at` is set within 60s, an issue label `soleur/acknowledged` exists on the issue, and the card renders the "Acknowledged" pill.

2. **Given** a `security.cve_alert` (cve-*) GitHubCard, **when** the operator clicks "Spawn CVE bump agent" without confirming, **then** the route returns 409 `requires_confirmation`, the `TypedConfirmModal` renders with `actionTargetLabel="PR #<n>"` (NOT `recipientExcerpt`), operator types "SEND" + confirms, second POST returns 200, label appears within 60s on the issue.

3. **Given** a `pr-*` GitHubCard and `users.github_installation_id IS NULL` for the founder, **when** the operator clicks "Spawn review agent", **then** the route returns 200 (substrate does not pre-probe installation), the Inngest function throws at `resolve-installation`, retries 3x, then UPDATEs `action_sends.failure_reason='github_installation_unauthorized'`. (PR-B will surface this to the card; PR-A leaves the operator to inspect via Sentry / `audit_github_token_use` view.)

4. **Given** a duplicate Inngest event (retry), **when** the function processes the same `actionSendId` twice, **then** the second invocation no-ops (idempotency key) and exactly one PR comment / one issue label exists on GitHub. UPDATE on `action_sends.acknowledged_at` is idempotent.

5. **Given** two browser tabs open the same TodayCard, **when** operator clicks Spawn in both within 50ms, **then** exactly one `action_sends` row (UNIQUE on `message_id`), exactly one Inngest event, exactly one artifact, both tabs render "Acknowledged" pill.

6. **Given** a malicious caller forges `event.data.installationId` in a hand-crafted Inngest event, **when** the function processes the event, **then** `tsc` would have caught at compile time (field omitted from type); runtime sentinel test enforces the grep negative pattern as belt-and-suspenders.

7. **Given** `inngest.send` throws (Inngest substrate transient unavailability), **when** the route catches the error, **then** route returns 200 with `degraded: "enqueue_failed"`, action_sends row stays committed, Sentry mirror fires, operator sees "Acknowledged (queued)" card state, no orphaned 500 toast.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- **Copywriter deferred.** Provisional `ACK_PR_COMMENT_TEMPLATE` + label name `soleur/acknowledged` ship in PR-A; copywriter follow-up issue filed before merge.
- **`already_sent` 409 path renders generic toast in PR-A.** Resolve-prior-run UX deferred. Card text: "This card was already actioned — refresh to see current state."
- **No polling, no realtime in PR-A.** Operator confirms via GitHub. Optimistic UI relies on the Inngest function completing within 60s on the happy path. Sentry alarm on `inngest.send` enqueue failure is the only proactive backstop.
- **The ~50ms partial-failure window between `action_sends` INSERT and `inngest.send` is documented and accepted.** If observed orphan rate is non-zero, file the transactional outbox follow-up.
- **Per `2026-05-12-region-replacement-acs-must-enumerate-trailing-paragraphs.md`:** AC11 verifies PA-19 by grep on `^## Processing Activity 19`; the register also has known PA-16 out-of-order disorder (line 306) — placement of PA-19 follows ordinal sequence, not line order.
- **PR-B planning MUST author ADR-039** before adding any Anthropic SDK call inside an Inngest function. Pattern "LLM runtime inside event substrate" crosses the ADR threshold per `constitution.md:120`.
- **`knowledge.kb_drift` tier bump cascade.** Producer-side grep at plan time confirms no current writer assumes `tier='auto'` for kb_drift specifically. The digest emitter is deferred per existing comments. The new producer-side cascade test (AC3) pins this.
- **Per `2026-05-21-plan-review-five-agent-panel-spec-flow-catches-missing-writer-path-and-bool-fallback-collapses.md`:** plan-time spec-flow surfaced 9 GAPs; 6 fixed in PR-A, 3 deferred with explicit follow-ups.
- **Per `2026-05-12-centralized-at-helper-boundary-transforms-overclaim-in-acs-and-disclosures.md`:** ACs #1 and #2 scope to the helper boundary (`createGitHubAppClient`) AND name the bypass exclusion (`probeOctokit` + raw `Octokit`) explicitly. Two-clause form.
- **Migration 062 vs. WORM trigger compat:** the existing `action_sends` WORM trigger MUST be verified to gate INSERT immutability only, not UPDATE on the three new columns. If the trigger covers UPDATE, migration 062 must add a column-list exception. Verify at /work-time Phase 0.
- **Event-name umbrella defended.** Existing webhook-ingest events follow `event_name === action_class` (`github-on-event.ts:287-291`). PR-A's `agent.spawn.requested` is a different event class — operator-click-derived, cross-cutting across action classes, handled by one function with internal switch. Per-class fan-out would require five near-identical Inngest functions or one function consuming five event names — neither offers a substrate benefit at single-user threshold. Defended in `## Alternative Approaches Considered`.

## Risks

| Risk | Mitigation |
|---|---|
| **Cross-installation routing** | Two-layer enforcement: TypeScript event payload type omits `installationId` (tsc fails on misuse); runtime sentinel test enforces negative grep. Plus `users.github_installation_id` partial-UNIQUE index (`migration 052:159-161`). |
| **Empty-result UX gap** | Deterministic acknowledgment artifact (PR comment or issue label) ships in PR-A. Card transitions to "Acknowledged — View on GitHub" pill on 200. |
| **Inngest enqueue failure** | try/catch + reportSilentFallback + `degraded: "enqueue_failed"` flag in 200 response. Retry via NEW `messages` row. |
| **WORM dead-letter trap** | Accepted ~50ms window. Operator retry = new `messages` row. Outbox follow-up filed conditionally. |
| **GitHub installation revoked** | Inngest `resolve-installation` step throws; final-retry UPDATE writes `failure_reason='github_installation_unauthorized'`. Operator inspects via Sentry / `audit_github_token_use` view in PR-A; card surface comes in PR-B. |
| **`knowledge.kb_drift` tier bump breaks producers** | Producer-side grep sweep + exhaustive-switch test catch any drift at CI. |
| **Inngest retry double-charging audit rows** | `audit_github_token_use` rows on retries are correct (each Octokit call = one audit row). Deterministic-stub artifact is idempotent at GitHub API (re-adding existing label = no-op; PR comment dedup via idempotency-key on `actionSendId` + `step.run` cache). |
| **Component-level click test brittleness (first of its kind)** | happy-dom + method-aware `vi.fn` fetch mock per `2026-05-20-happy-dom-ws-fetch-blockade.md`; pin to DOM contract + `data-testid` per `2026-05-06-test-public-dom-contract-not-setstate-side-effects.md`; avoid jsdom layout-gated assertions per `cq-jsdom-no-layout-gated-assertions`. |
| **WORM trigger blocks UPDATE on new columns** | Verify trigger scope at /work Phase 0 before applying migration 062. If trigger covers UPDATE, add column-list exception in 062. |

## Alternative Approaches Considered

| Approach | Decision | Rationale |
|---|---|---|
| Ship PR-A + Anthropic leader loop in one PR | **Rejected** | Greenfield Anthropic-SDK-in-Inngest + cost cap + max-turns + idempotency + ADR-039 in one PR maximizes bug-cascade surface (CTO) and creates brand-miss risk if leader loop ships shaky (CPO). Split is defensible; deterministic stub closes the empty-result UX gap. |
| New `agent_runs` table + RLS + polling endpoint + scheduled cron | **Rejected (plan-review trim)** | DHH + code-simplifier converged: the GitHub artifact IS the receipt; `action_sends` already exists as the WORM ledger; adding a third ledger is gold-plating. Trimmed to 3 columns on `action_sends`. |
| 5 acknowledgment template variants (PR comment / issue label / severity-only CVE / draft branch / label+comment) | **Rejected (plan-review trim)** | code-simplifier: collapse to 2 paths (PR sources → PR comment; everything else → issue label). kb_drift draft-branch is operator slop the leader loop will replace in PR-B anyway. |
| KbDrift tier option (B): special-case `auto` in `/send` route | **Rejected** | Pollutes send route with action-class branch. Tier semantics drift. |
| KbDrift tier option (C): separate `/spawn` route | **Rejected** | Second route surface nobody else uses. Option (A) bumps one row + one test. CTO preferred (C); plan resolves to (A) for substrate simplicity. |
| Per-class Inngest event names (`engineering.pr_review_pending` etc., matching existing webhook-ingest convention) | **Rejected** | Webhook-ingest convention (`event_name === action_class`) is 1:1 because each event is a webhook from a single classification source. Operator-click-derived spawn events are cross-cutting (one operator-triggered substrate handling five classes). Per-class fan-out would mandate five near-identical Inngest functions OR one function consuming five event names — neither offers benefit. Umbrella `agent.spawn.requested` with internal switch is cleaner. Kieran P0-1 disagreement noted; this is the deliberate exception. |
| Realtime channel for acknowledgment status (Supabase Realtime) | **Deferred V2** | Polling at 5s/2-min was the prior plan rev; both DHH and simplicity trimmed it. Optimistic UI is sufficient. |
| Transactional outbox table for `action_sends` ↔ `inngest.send` | **Deferred** | Accept ~50ms partial-failure window. File outbox follow-up only if orphan rate is non-zero in practice. |
| WORM uniqueness relaxation on `action_sends(message_id)` for retry | **Rejected** | Retry uses new `messages` row. WORM uniqueness is load-bearing for GDPR Art. 5(2) accountability. |
| ux-design-lead Pencil wireframes for "Acknowledged" pill | **Skipped** | No new page; text + color pill, no novel visual. Pencil unavailable in current session. |
| Inline click logic in GitHubCard + KbDriftCard (no hook extraction) | **Rejected** | Three callers (StripeCard + 2 new) justify the abstraction. DHH ✅ keep; code-simplifier disagrees but the rename (`use-action-send.ts`) resolves the stutter concern. |

## Open Questions

1. **Should the "Acknowledged" pill auto-fade after the operator clicks "View on GitHub"?** Default: stick until operator dismisses via card-level discard. Revisit if operator workflow surfaces a preference.
2. **What's the right threshold for filing the transactional-outbox follow-up?** Default: ≥1 orphan/week in Sentry. Revisit after first month.
3. **Should PR-B's leader loop ship all five action_classes' prompts at once or one at a time?** PR-B's plan owns this decision.

## Follow-ups (filed before PR-A merges)

1. **PR-B (new issue):** "feat(today-card): replace deterministic acknowledgment stub with Anthropic SDK leader-prompt loop". Includes ADR-039 (Anthropic-SDK-inside-Inngest), per-action-class leader prompts, `runWithByokLease` scope, `record_byok_use_and_check_cap` wiring, per-turn idempotency via `step.run`, max-turns ceiling, 60s per-call timeout, card-surfaced failure UX.
2. **(new issue):** "copy(today-card): copywriter pass on spawn-agent strings". Scope: `ACK_PR_COMMENT_TEMPLATE`, label naming, failure-state copy, button hover text for the 5 GitHub-source variants + 2 KbDrift variants.

## Rollback Plan

1. **DB:** `062_action_sends_acknowledgment.down.sql` drops the three new columns. No data loss (the columns are autonomous-system-written; operator inspects GitHub directly for canonical state).
2. **Code:** revert PR; `knowledge.kb_drift` tier reverts to `"auto"` (buttons return to disabled state — matches pre-PR-A behavior).
3. **Article 30 register:** PA-19 entry can be removed without legal exposure — no operator data has been processed under it at the moment of rollback (autonomous-acknowledgment artifacts on GitHub remain; they are not personal-data processing on Soleur infrastructure).
4. **Inngest events in flight at rollback:** `agent.spawn.requested` events with no handler retry then DLQ. Manual purge: per Inngest self-hosted runbook.

## Resume prompt (copy-paste after `/clear`)

```text
/soleur:work knowledge-base/project/plans/2026-05-22-feat-wire-today-card-spawn-agent-buttons-pr-a-plan.md
Branch: feat-4124-wire-today-card-action-buttons
Worktree: .worktrees/feat-4124-wire-today-card-action-buttons/
Issue: #4124
Brand-survival threshold: single-user incident (requires_cpo_signoff: true at plan-time — APPROVED by CPO with 5 threshold ACs encoded as AC1-AC5)
Plan reviewed by CPO + CTO + spec-flow-analyzer; 3-agent plan-review (DHH + Kieran + code-simplifier) applied (drops agent_runs table, polling, cron, 3 follow-ups; renames per Kieran P0/P1; defends umbrella event name in Alternative Approaches). Template_authorizations gap (Kieran P1-7) verified covered by PR-I first-send-IS-authorization. Implementation next: PR-A substrate — PR-B (Anthropic leader loop) follow-up filed before merge.
```
