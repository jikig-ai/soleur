---
title: "fix(live-verify): seed user_session_state.current_workspace_id so the synthetic principal's chat send persists a conversation (harness can emit PASS)"
date: 2026-06-17
type: fix
issue: "#5501"
branch: feat-one-shot-5501-live-verify-synthetic-onboard
lane: single-domain
status: ready
brand_survival_threshold: none
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# fix(live-verify): onboard the synthetic principal's active-workspace binding 🐛

## Enhancement Summary

**Deepened on:** 2026-06-17

**Gates run (all PASS):** 4.4 precedent-diff (added a Precedent Diff subsection — the write
mirrors the `set_current_workspace_id` RPC body verbatim), 4.45 round-1 realism
(verify-the-negative + data-integrity passes, all 6 load-bearing claims confirmed against the
repo), 4.5 network-outage (skip — no SSH/network trigger; the only `ssh`-ish token is the
"no remote shell" IaC prose), 4.6 User-Brand Impact (present, threshold `none` + non-empty
sensitive-path scope-out reason), 4.7 Observability (present, all 5 fields, no-ssh), 4.8
PAT-shaped variable (none), 4.9 UI-wireframe (skip — no UI-surface file in Files lists).

### Key improvements over the plan-skill output

1. **Foregrounded the strongest correctness anchor:** the seed's upsert body matches the
   `set_current_workspace_id` RPC's own `INSERT … ON CONFLICT (user_id) DO UPDATE` verbatim
   (mig 079:293-298) — a stronger argument than the `conversations` 028/035 REST-transport
   precedent alone.
2. **Verified the six load-bearing claims against the repo** (verify-the-negative pass):
   no table-level `REVOKE … FROM service_role`, no insert/update trigger on
   `user_session_state`, RPC `auth.uid()`-28000 guard, `handle_new_user` does NOT seed
   `user_session_state`, merge-duplicates upsert idempotency.
3. **Confirmed binding source-of-truth:** the seed binds the workspace id resolved from the
   **owner-membership row** (not a hard-coded `=uid`), which equals `uid` by construction for
   a solo principal but via the authoritative lookup the RPC itself gates on.

### New considerations discovered

- The data-integrity pass flagged `updated_at` in the body as redundant (the column has
  `DEFAULT now()`); kept for parity with the RPC's explicit `now()` set — harmless, no action.
- The `limit=1` owner-membership lookup (pre-existing seed code) is safe only because the
  synthetic principal is single-workspace; noted in Risks so the pattern is not copied to
  multi-workspace principals without an ordering key.

## Research Insights — Precedent Diff (Phase 4.4)

The proposed `user_session_state` write has a **canonical in-repo precedent**: the
`set_current_workspace_id` RPC body. The seed reproduces the same write through the table
endpoint because the RPC requires `auth.uid()` (unavailable to a service-role caller).

| Aspect | RPC `set_current_workspace_id` (mig 079:256-300) | Seed direct REST upsert (this plan) |
|---|---|---|
| Write statement | `INSERT … (user_id, current_workspace_id, current_organization_id, updated_at) VALUES (…) ON CONFLICT (user_id) DO UPDATE SET …` (`:293-298`) | `POST /rest/v1/user_session_state?on_conflict=user_id` + `Prefer: resolution=merge-duplicates` → identical INSERT…ON CONFLICT |
| `current_workspace_id` source | `p_workspace_id` arg (membership-checked) | owner-membership lookup (`seed:187-189`), equals solo workspace id |
| `current_organization_id` source | `SELECT organization_id FROM workspaces WHERE id = p_workspace_id` (`:284-286`) | `GET …/workspaces?id=eq.$workspace_id&select=organization_id` (this plan) |
| Caller identity | `auth.uid()` (authenticated) | service-role key (RLS-bypass) |
| Why not the RPC | n/a | RPC raises 28000 on null `auth.uid()` + EXECUTE revoked from `service_role` (`:267`, `:302`) |

**Verdict:** not a novel pattern — the seed adopts the canonical write shape with the only
difference being the transport (table endpoint vs SECURITY-DEFINER RPC), forced by the
service-role caller context. No precedent risk.

## Overview

The live-verification harness (`apps/web-platform/scripts/live-verify/run.ts`), run
on its FULL (non-dry-run) path against prod as `live-verify@soleur.ai`, never emits
`RESULT: PASS`. It emits `CANT-RUN:forURL` because the post-send `waitForURL(/\/dashboard\/chat\/<uuid>$/)`
times out. Confirmed browser-independently via the DB: **0 `conversations` rows** for the
synthetic UID after repeated sends — the conversation is **never persisted**, so the app
never navigates and the rail never gets a row.

**Root cause (verified end-to-end during planning):** the synthetic principal has **no
`user_session_state` row**. The server-side conversation-create path resolves the row's
`workspace_id` through a **fail-loud** resolver that throws when no durable workspace
binding exists:

- The single message-send dispatches `createConversation` (`server/ws-handler.ts:2191` → def `:851`).
- `:892` resolves `wsId` via `resolveUserWorkspaceBinding(userId, (uid) => readWorkspaceIdFromDb(uid, tenant))`.
- `readWorkspaceIdFromDb` (`server/workspace-resolver.ts:248`) reads `user_session_state.current_workspace_id`; with **no row** it returns `null` (`:275`).
- `resolveUserWorkspaceBinding` (`server/agent-session-registry.ts:288`) **throws** `"Unable to resolve workspace binding for user — no durable binding found."` on a `null` read (`:316-326`).
- `createConversation` therefore throws **before** the `conversations` INSERT (`:897`) → no row → no realtime rail event → no client navigation → harness `CANT-RUN:forURL`.

The seed script `apps/web-platform/scripts/seed-live-verify-user.sh` already provisions the
`auth.users`, `public.users` (tc + workspace_status + repo_status), `public.workspaces`
(`repo_url` sentinel + `repo_status=ready`), and dummy `api_keys` rows — but it **never
writes a `user_session_state` row**. The `handle_new_user` trigger (mig 053) creates the
org + workspace + owner-membership, **not** a `user_session_state` row (mig 060 only
backfilled rows for users that existed at migration time). So the active-workspace binding
the deployed app reads at send time is permanently absent for this principal.

**The fix:** the seed upserts one `user_session_state` row for the synthetic UID with
`current_workspace_id` = its solo workspace id and `current_organization_id` = that
workspace's `organization_id`, mirroring the `set_current_workspace_id` RPC's write shape.
This is a ~12-line addition to one script plus a static-grep test assertion plus an ADR-064
amendment. No schema change, no new infra, no new secret.

This is the true blocker for #5463 item 4 (observe a real PASS): until a real PASS is
observed from the re-homed CI gate (#5488 report-only job), the report-only → blocking flip
(#5463) stays gated.

## Premise Validation

Checked the issue's cited references and its own mechanism claims before planning:

- **#5463 (blocking-flip)** — OPEN. This plan unblocks its item 4; correct to plan against. ✓
- **#5485 (cookie-auth)** — CLOSED (fix merged). The dry-run gate it fixed is read-only and
  never exercises send→materialize, which is exactly why it PASSed while the full path
  cannot — consistent with the issue's framing. ✓
- **#5488 (GHA report-only job)** — MERGED. The re-homed report-only gate exists; this plan
  feeds it a real PASS. ✓
- **Mechanism vs. resolver reality** — the issue hypothesised "un-onboarded → no active
  workspace context → null `workspace_id` on send." Grepping the actual write path REFINED
  this: the conversation-create resolver is **fail-loud** (`resolveUserWorkspaceBinding`
  THROWS on a null binding), not silently-null. The DB-observed `0 rows` is the throw
  aborting the INSERT, not a NULL-`workspace_id` insert (the column is NOT NULL since mig
  059, which would also abort). Either way the fix is identical: seed the
  `user_session_state` binding. The "command-center renders" symptom is a **consequence**
  (no conversations → first-run empty state at `app/(dashboard)/dashboard/page.tsx:455`),
  gated on `!visionExists && conversations.length === 0`, **not** a literal "un-onboarded"
  gate — so no `users.workspace_status`/`vision.md` change is needed for the harness, which
  drives `/dashboard/chat/new` (the rail shell), not `/dashboard`.
- **Mechanism vs. ADR corpus** — ADR-044 §"Active-workspace context" defines
  `current_workspace_id` in `user_session_state` as THE binding mechanism (write via
  `set_current_workspace_id` RPC, claim-derived everywhere). This plan does not introduce a
  rejected alternative; it completes the synthetic-principal seed to satisfy ADR-044's
  source-of-truth. ADR-064 (the harness ADR) documents the seed's table set; this plan
  amends it to add `user_session_state`. ✓
- **Own capability claim — RPC cannot be used from the seed:** `set_current_workspace_id`
  (mig 079:256) starts with `v_user_id := auth.uid()` and `RAISE EXCEPTION` when null
  (28000). The seed authenticates with the **service-role** key (no `auth.uid()`), so a
  `POST /rpc/set_current_workspace_id` would raise 28000. Verified by reading the function
  body. ⇒ The seed MUST write `user_session_state` **directly** via the REST table endpoint,
  not via the RPC. Load-bearing for the implementation choice below.

No stale premises. The issue's root-cause direction holds; the resolver detail is sharpened.

## Research Reconciliation — Issue Claim vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| Send produces null `workspace_id` → "never persists" | `conversations.workspace_id` is NOT NULL (mig 059); the resolver `resolveUserWorkspaceBinding` **throws** on a null binding **before** the INSERT (`agent-session-registry.ts:316-326`). Net effect identical: 0 rows. | Seed the `user_session_state.current_workspace_id` binding so the resolver returns the solo workspace id instead of throwing. |
| "Un-onboarded → `/dashboard` command-center, no active workspace context" | The command-center is the **first-run empty state** gated on `!visionExists && conversations.length === 0` (`dashboard/page.tsx:455`), a *consequence* of 0 conversations — not a workspace-binding gate. The binding gap is server-side in the send path. | Fix is server-state (seed `user_session_state`), not a UI/onboarding-flag change. Harness already targets `/dashboard/chat/new` (rail shell), not `/dashboard`. |
| Onboarding "likely belongs in `bootstrap-live-verify.sh` / `seed-live-verify-user.sh`" | `bootstrap-live-verify.sh` only orchestrates (terraform apply + invoke seed); all Supabase row writes live in `seed-live-verify-user.sh`. | Add the `user_session_state` upsert to `seed-live-verify-user.sh` (the row-writer), not the orchestrator. |
| (Item 3) Harness `waitForURL` may need updating | `run.ts:383` asserts `waitForURL(/\/dashboard\/chat\/[0-9a-f-]{36}$/)`. This is correct **once** the conversation persists — the nav is a downstream effect of the realtime materialize. The timeout was the *symptom*, not a wrong assertion. | No harness change needed; the seed fix restores the persist→nav chain. Item 3 resolves as "assertion was correct; the upstream persist was broken." (Re-confirmed by the FULL-path re-run in AC.) |

## User-Brand Impact

**If this lands broken, the user experiences:** the live-verify postmerge gate keeps
emitting `CANT-RUN:forURL` on every qualifying merge, so the #5463 report-only→blocking flip
stays gated indefinitely — the operator never gets the real-deploy safety net the harness was
built to provide (the #5391/#5421/#5436 broken-fix class keeps reaching them).

**If this leaks, the user's data is exposed via:** N/A — the seed writes only the **synthetic
principal's own** `user_session_state` row (its own solo workspace + org), under the existing
prd-only triple-defense guardrails. No real-user data, no new secret, no cross-tenant write.

**Brand-survival threshold:** none — the change provisions one synthetic principal's own
session-state row in prod; the harness already runs report-only and tears down its own
conversation. The threshold-none + sensitive-path interaction: the seed touches a prod
Supabase write surface but writes only the allowlisted synthetic UID's own row, gated by the
script's existing `DOPPLER_CONFIG=prd` + service-role-JWT-ref + PROD_ALLOWED_HOSTS triple
checks. `threshold: none, reason: writes only the synthetic principal's own solo
user_session_state row under existing prd guardrails; no real-user data and no new exposure
vector.`

## Implementation Phases

### Phase 1 — Seed the active-workspace binding (RED: extend the static test first)

1. **`apps/web-platform/scripts/seed-live-verify-user.test.sh`** (RED): add a static-grep
   assertion that the seed body upserts `user_session_state` with `current_workspace_id`
   AND `current_organization_id`, and that the upsert appears AFTER the
   `workspace_members` owner lookup (write order: the workspace must be resolved first).
   This is a body-grep test (the existing test type — no live API calls), consistent with
   the file's current assertions (`:67-119`). New checks (pseudocode):
   ```bash
   grep -qE '/rest/v1/user_session_state' "$SEED"        # upsert call present
   grep -qE 'current_workspace_id'        "$SEED"        # binding column written
   grep -qE 'current_organization_id'     "$SEED"        # org claim written
   grep -qE 'resolution=merge-duplicates' "$SEED"        # POST-upsert, not no-op PATCH
   # order: user_session_state line number > workspace_members line number
   ```
   Run `bash apps/web-platform/scripts/seed-live-verify-user.test.sh` → MUST FAIL (assertion
   missing in the script). Capture the red.

2. **`apps/web-platform/scripts/seed-live-verify-user.sh`** (GREEN): after the existing
   `workspaces` PATCH (`:200-205`) and BEFORE the `api_keys` block (`:210`), insert:
   - Fetch the workspace's `organization_id` via REST:
     `GET /rest/v1/workspaces?id=eq.$workspace_id&select=organization_id` → `org_id`; fail
     closed (`::error::` + `exit 1`) if empty (the trigger guarantees it, but the seed must
     not silently bind a null org — the NOT NULL `organizations` FK would reject it anyway).
   - **Upsert** the row with a POST to the table endpoint (NOT the RPC — the RPC needs
     `auth.uid()`, see Premise Validation; NOT a bare PATCH — no row exists yet, so
     `?user_id=eq.X` matches 0 rows and silently no-ops):
     ```bash
     curl -sf "$SB_URL/rest/v1/user_session_state?on_conflict=user_id" \
       -X POST -H "$header_auth" -H "$header_api" -H "$header_json" \
       -H "Prefer: resolution=merge-duplicates,return=minimal" \
       -d "$(jq -nc \
         --arg uid "$user_id" \
         --arg wid "$workspace_id" \
         --arg oid "$org_id" \
         --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
         '{user_id: $uid, current_workspace_id: $wid, current_organization_id: $oid, updated_at: $ts}')" \
       > /dev/null
     ```
     (`on_conflict=user_id` + `resolution=merge-duplicates` is the repo's existing
     service-role upsert idiom — the REST-transport precedent is migrations 028/035 for
     `conversations`. The **strongest correctness anchor**, though, is that this body matches
     the `set_current_workspace_id` RPC's own write **verbatim**:
     `INSERT INTO public.user_session_state (user_id, current_workspace_id, current_organization_id, updated_at) … ON CONFLICT (user_id) DO UPDATE SET …`
     (mig 079:293-298) — the seed produces exactly the row the RPC would, just via the table
     endpoint because the RPC needs `auth.uid()`. Service role bypasses the SELECT-only RLS on
     `user_session_state` (mig 060:41-43) and the table has NO insert/update trigger (verified)
     + NO table-level `REVOKE … FROM service_role` (the only REVOKEs are on the RPC *functions*,
     mig 060:154/217 + mig 079:302). The two FK columns are `ON DELETE SET NULL` — no
     cascade-block.)
   - Secret discipline (AC8 parity): no `set -x`; no response body echoed (the response
     carries nothing sensitive here, but keep the `> /dev/null` convention).
   - Update the script's header-comment ladder (`:17-30`) to list the new
     `user_session_state` row in the provisioned-state inventory.
   Re-run the test → MUST PASS.

3. **REFACTOR:** keep the new block stylistically identical to the sibling `curl … | jq`
   writes (same headers, same fail-closed shape). No extraction — one call site.

### Phase 2 — ADR-064 amendment (architectural-record deliverable, in-PR)

Amend **`knowledge-base/engineering/architecture/decisions/ADR-064-live-production-verification-harness.md`**
(do NOT defer to a follow-up issue — `wg-architecture-decision-is-a-plan-deliverable`):
add a dated amendment recording that the synthetic-principal seed MUST also write a
`user_session_state` row (`current_workspace_id` = solo workspace, `current_organization_id`
= its org) so the deployed `createConversation` fail-loud workspace resolver
(`resolveUserWorkspaceBinding`) returns a binding instead of throwing. Cite the resolver
path (`ws-handler.ts:892` → `agent-session-registry.ts:316`) and the
RPC-needs-`auth.uid()`-so-the-seed-writes-the-table-directly rationale. This is an
*extension* of ADR-064's seed contract, not a reversal — `Status` stays Accepted, append an
`### Amendment 2026-06-17 — seed must bind active workspace` subsection.

### Phase 3 — Live re-run (post-merge; automation-status verified)

Re-run the FULL harness path against prod once the seed change is merged and the seed re-run
under prd, confirming `RESULT: PASS` (a real conversation is created, appears in the rail,
and is torn down). See `### Post-merge (operator)` AC below for the automation routing —
this re-run is the de-risk for #5463 item 4.

## Files to Edit

- `apps/web-platform/scripts/seed-live-verify-user.sh` — add the `user_session_state` upsert
  (fetch `organization_id`, POST-upsert the binding) after the `workspaces` PATCH; update the
  header inventory comment.
- `apps/web-platform/scripts/seed-live-verify-user.test.sh` — add the static-grep assertions
  (upsert present, both columns, merge-duplicates, write-order).
- `knowledge-base/engineering/architecture/decisions/ADR-064-live-production-verification-harness.md`
  — append the seed-must-bind-active-workspace amendment.

## Files to Create

- _None._ (No new script, migration, infra, or secret.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** `apps/web-platform/scripts/seed-live-verify-user.sh` contains a
  `POST /rest/v1/user_session_state?on_conflict=user_id` call with
  `Prefer: resolution=merge-duplicates` whose JSON body carries `user_id`,
  `current_workspace_id`, `current_organization_id`, `updated_at`. Verify:
  `grep -qE 'rest/v1/user_session_state\?on_conflict=user_id' apps/web-platform/scripts/seed-live-verify-user.sh && grep -qE 'resolution=merge-duplicates' apps/web-platform/scripts/seed-live-verify-user.sh`.
- [ ] **AC2** The seed resolves `organization_id` from the workspace row before the upsert and
  fails closed when empty. Verify: `grep -qE 'select=organization_id' apps/web-platform/scripts/seed-live-verify-user.sh`
  AND a `::error::` + `exit 1` guard exists for an empty `org_id`.
- [ ] **AC3** Write order: the `user_session_state` upsert line number is greater than the
  `workspace_members` owner-lookup line number. Verify:
  `[[ $(grep -n user_session_state apps/web-platform/scripts/seed-live-verify-user.sh | head -1 | cut -d: -f1) -gt $(grep -n workspace_members apps/web-platform/scripts/seed-live-verify-user.sh | head -1 | cut -d: -f1) ]]`.
- [ ] **AC4** The seed does NOT call `set_current_workspace_id` via `/rpc/` (it would 28000 on
  a service-role caller with no `auth.uid()`). Verify:
  `! grep -qE '/rpc/set_current_workspace_id' apps/web-platform/scripts/seed-live-verify-user.sh`.
- [ ] **AC5** `bash apps/web-platform/scripts/seed-live-verify-user.test.sh` exits 0 (all
  static-grep assertions, including the new `user_session_state` ones, pass).
- [ ] **AC6** Secret discipline preserved: no `set -x` added; the new block does not echo a
  response body or any secret. Verify: `! grep -qE '^\s*set -x' apps/web-platform/scripts/seed-live-verify-user.sh`.
- [ ] **AC7** ADR-064 carries an `### Amendment 2026-06-17 — seed must bind active workspace`
  subsection citing the `resolveUserWorkspaceBinding` fail-loud path. Verify:
  `grep -qE 'Amendment 2026-06-17 — seed must bind active workspace' knowledge-base/engineering/architecture/decisions/ADR-064-live-production-verification-harness.md`.
- [ ] **AC8** Negative AC preserved (no CI wiring of the seed):
  `! grep -rlE 'seed-live-verify' .github/workflows/` returns nothing (the seed stays
  agent-run-locally per ADR-064 security P0-1).
- [ ] **AC9** PR body uses `Ref #5501` (NOT `Closes`) — the issue's true resolution is the
  post-merge live PASS in AC10, not the code merge (`wg-use-closes-n-in-pr-body-not-title` /
  ops-remediation `Ref` extension). Issue closed in the post-merge step after AC10 passes.

### Post-merge (operator)

- [ ] **AC10** Re-seed prod, then re-run the FULL harness path and confirm `RESULT: PASS`.
  Automation routing (per the automation-feasibility gate):
  - Re-seed: `doppler run -p soleur -c prd -- bash apps/web-platform/scripts/seed-live-verify-user.sh`
    (idempotent; agent-run locally — NOT CI). `Automation: agent runs this locally; not
    operator-gated.`
  - Re-run harness FULL path against prod and assert stdout contains `RESULT: PASS`
    (`apps/web-platform/scripts/live-verify/run.ts`, non-dry-run). `Automation: agent runs
    the harness locally if the bundled chromium launches in-session; the issue notes the dev
    host's chromium flake is local-browser-specific and orthogonal. If the in-session
    chromium cannot launch, the canonical observation point is the #5488 report-only CI job
    on the next qualifying merge — read its emitted `RESULT:` via `gh run view` rather than
    eyeballing a dashboard (`hr-no-dashboard-eyeball`).`
  - `automation-status: UNVERIFIED — /work MUST attempt the in-session harness launch (and,
    failing that, read the #5488 job's RESULT via gh) before any operator handoff. Do NOT
    pre-assume operator-only — this is a CLI/`gh`-readable observation, not a human-judgment
    gate.`
- [ ] **AC11** After AC10 shows PASS, `gh issue close 5501` with a comment linking the PASS
  evidence (harness stdout line or the #5488 run URL).

## Test Scenarios

- **T1 (RED first):** the new test assertions fail against the current (binding-less) seed.
- **T2 (GREEN):** after the upsert is added, the test passes; the seed body contains the
  POST-upsert with both columns, in the correct order.
- **T3 (live persist):** post-merge, a single message-send by the synthetic principal
  persists exactly one `conversations` row (`workspace_id` = solo workspace id), the app
  navigates to `/dashboard/chat/<uuid>`, the rail shows the row, and teardown removes it →
  `RESULT: PASS`.
- **T4 (idempotency):** re-running the seed a second time updates (not duplicates) the
  `user_session_state` row (PK `user_id` + `merge-duplicates`) — no error, no second row.

## Domain Review

**Domains relevant:** Engineering (assessed inline)

The mechanical UI-surface override does NOT fire: `## Files to Edit` and `## Files to Create`
contain no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or any UI-surface
path — the change is a bash seed script, its bash test, and an ADR markdown file. Product is
NONE (the dashboard command-center is only *discussed* as a consequence; no UI is
implemented). No Marketing/Sales/Finance/Support/Legal implications beyond the existing
synthetic-principal guardrails already adjudicated by CLO in the ADR-064 brainstorm (synthetic
account, redaction, ephemeral captures) — unchanged by this fix. Engineering assessment is
captured in the body (root-cause trace + resolver path + RPC-vs-direct-write decision).

No cross-domain leader spawn required — this is an infrastructure/tooling fix on an
already-adjudicated synthetic-principal surface.

## Infrastructure (IaC)

Skip — no new infrastructure. The Terraform resources (`random_password.live_verify_user`,
`doppler_secret.live_verify_user_password`) and the `LIVE_VERIFY_*` Doppler secrets already
exist (`apps/web-platform/infra/live-verify.tf`, provisioned by the existing
`bootstrap-live-verify.sh`). This plan adds one Supabase **row write** to an existing seed
script — not a server, service, cron, secret, vendor, or DNS record. No remote shell, no
secret mutation, no dashboard step. (Phase 2.8 IaC-routing reviewed; the only quoted
secret-write tokens are pre-existing comments in the seed, not new prescribed steps —
`iac-routing-ack` set in frontmatter.)

## Observability

```yaml
liveness_signal:
  what: "live-verify harness RESULT: PASS|FAIL|CANT-RUN line on each qualifying merge"
  cadence: "per qualifying PR merge (path-triggered, #5488 report-only job)"
  alert_target: "the #5488 GHA job step output; empty fails closed (auto-files a tracking issue)"
  configured_in: ".github/workflows/web-platform-release.yml (live-verify job, #5488) + scripts/live-verify/run.ts emit()"
error_reporting:
  destination: "Sentry via reportSilentFallback in resolveUserWorkspaceBinding (agent-session-registry.ts:299) — fires op resolveUserWorkspaceBinding.unresolvable if the binding is STILL absent post-seed"
  fail_loud: true
failure_modes:
  - mode: "seed upsert silently no-ops (PATCH-on-absent-row mistake)"
    detection: "harness re-run still emits CANT-RUN:forURL; seed test AC3/AC1 grep would have caught the wrong verb pre-merge"
    alert_route: "#5488 job RESULT line (non-PASS) + Sentry op resolveUserWorkspaceBinding.unresolvable"
  - mode: "organization_id resolves empty - upsert rejected by NOT NULL org FK"
    detection: "seed exits non-zero at the org-fetch guard (AC2); curl -sf fails on 4xx"
    alert_route: "seed stderr ::error:: line at run time (agent-run locally)"
  - mode: "conversation persists but rail row never appears (the original #5391 class returns)"
    detection: "harness emits FAIL (not CANT-RUN) - convId resolved from URL but rail row absent within budget"
    alert_route: "#5488 job RESULT: FAIL line"
logs:
  where: "harness stdout (redacted via redact-stdin before tee, per 2026-06-17 report-only-gate learning) - GHA run log; Sentry for the resolver fail-loud"
  retention: "GHA run-log default retention; Sentry per project retention"
discoverability_test:
  command: "gh run view <run-id> --log | grep -E 'RESULT: (PASS|FAIL|CANT-RUN)'"
  expected_output: "RESULT: PASS  (after the seed binds the active workspace)"
```

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-064** (live-production-verification-harness) — append
`### Amendment 2026-06-17 — seed must bind active workspace`: the synthetic-principal seed's
table contract now includes a `user_session_state` row (`current_workspace_id` +
`current_organization_id`) because the deployed `createConversation` resolves `workspace_id`
through the fail-loud `resolveUserWorkspaceBinding`, which throws (not soft-falls-back) on an
absent binding. This is an **extension** of ADR-064's seed contract (Status stays Accepted),
not a reversal of ADR-044 (which it now more completely satisfies). Authored in THIS PR
(Phase 2), not deferred.

### C4 views

No C4 model change — no new container, component, or connection edge. The synthetic principal
and the harness→prod-Supabase edge already exist in the ADR-064 model; this fix completes a
seed row within the existing topology.

### Sequencing

The ADR amendment describes the current target state and ships in the same PR as the seed fix
— no soak gate, no follow-up issue.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` returned no open issue whose body
references `seed-live-verify-user.sh`, `seed-live-verify-user.test.sh`, or `ADR-064` (checked
at plan time).

## Risks & Mitigations

- **R1 — wrong upsert verb (PATCH no-ops on absent row).** Mitigated by the POST +
  `on_conflict=user_id` + `resolution=merge-duplicates` idiom (precedent migrations 028/035)
  and AC1/AC3 grep gates. The `user_session_state` PK is `user_id`, so merge-duplicates
  upserts cleanly.
- **R2 — RPC misuse (28000).** Mitigated by AC4 (negative grep) + the Premise-Validation note:
  the service-role seed has no `auth.uid()`, so it writes the table directly.
- **R3 — `organization_id` null.** The `handle_new_user` trigger (mig 053) guarantees one org
  per solo workspace; the seed still fail-closes on an empty fetch (AC2) so a future trigger
  regression surfaces as a loud seed error, not a silent broken binding.
- **R4 — service-role RLS/grant.** `user_session_state` RLS is SELECT-only for `authenticated`
  (mig 060:41-43); service-role bypasses RLS and retains the default table grant (no REVOKE on
  the table itself — verified). No SECURITY DEFINER trigger freezes these columns
  (the only writer-side guard is in the RPC, which the seed bypasses).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled
  with `threshold: none` + a non-empty reason.
- The `user_session_state` write MUST be a POST upsert, not a PATCH: no row exists for the
  synthetic principal before this seed runs (the trigger does not create one; mig 060 only
  backfilled migration-time users). A `PATCH ?user_id=eq.X` matches 0 rows and silently
  succeeds (200, no body) — the seed would "pass" while the binding stays absent and the
  harness keeps emitting `CANT-RUN:forURL`.
- Do NOT route the binding write through `set_current_workspace_id`: it derives the writer from
  `auth.uid()` and raises 28000 under a service-role caller. The seed writes the table row
  with the same shape the RPC would have produced.
