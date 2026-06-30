---
issue: 5591
type: fix
lane: single-domain
brand_survival_threshold: none
status: ready-for-work
created: 2026-06-30
branch: feat-one-shot-5591-owner-canary-multi-owner
---

# 🐛 fix(workspace): owner-canary multi-owner resolver — sweep + observability-inventory completion + close #5591

## Enhancement Summary

**Deepened on:** 2026-06-30
**Sections enhanced:** Research Reconciliation, User-Brand Impact, Scope, Acceptance Criteria, Architecture Decision
**Research / review agents used:** Explore (sibling-site sweep), learnings-researcher, code-simplicity-reviewer, architecture-strategist

### Key Improvements (from deepen pass)
1. **Premise validated against live state.** Confirmed the primary resolver fix is already on `main` (#5734, commit `190ab58a5`, touches the reconcile file) with 3-branch test coverage; the prescribed sweep (13 TS + 5 SQL owner-touching sites) found **zero** residual buggy sites. The honest residual is the observability-inventory completion + issue close.
2. **Citation corrections.** Fixed `#5673` (OPEN tracking issue, not MERGED) in two places; verified `#5734` MERGED, `#5733`/`#5756` OPEN, `#5730` MERGED via `gh`.
3. **Sensitive-path gate caught a real error (4.6).** `server/observability.ts` matches the canonical sensitive-path regex (the `apps/web-platform/server` prefix); added the required `threshold: none, reason: …` scope-out bullet so the User-Brand Impact section passes deepen-plan 4.6 and preflight Check 6.
4. **Simplicity verdict: KEEP the docstring change** (proportionate; completes an existing inventory pattern — cutting to zero-code is strictly worse). Demoted AC7 (post-merge prod read of `754ee124`) from a gate to an optional note (it verifies #5734's behavior, not this diff).
5. **Architecture verdict: de-scope boundary sound.** 5591 (read-path resolver, closed here) / 5756 (write-path RPC + ADR) / 5733 (filesystem strand) partition cleanly; no dropped #5591-owned item. Folded in the AP-015 (`principles-register.md:23`) reconciliation pointer for #5756's ADR.

### New Considerations Discovered
- The `multiple-owners-reconcile` info breadcrumb and `owner-attribution-probe` warn op (both shipped by #5734) were missing from the `observability.ts` op-inventory that already lists `ownerless-reconcile` — a genuine one-line-cheap gap in a maintained pattern.
- AP-015's single-owner "owner-membership canary" framing (tied to ADR-044) is the principle the N-owner model relaxes; reconciling it belongs to #5756's dedicated ADR, not this PR.

## TL;DR (read this first)

**The primary fix this issue asks for already shipped in PR #5734 (MERGED, on `main`).** The re-scoped deliverable — "make the owner-canary resolution deterministic on a multi-owner workspace instead of collapsing to null" — is implemented in `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` (commit `190ab58a5`, "tolerate N co-owners (#5734)"), **with full test coverage of all three branches**. Both consequences the issue named (false `owner-less` Sentry noise + `kb_sync_history` recovery-audit gap) are resolved there.

This plan therefore does **not** re-implement the resolver. It delivers the genuinely-residual work:

1. **The prescribed sweep** for sibling owner-resolution call sites — **executed during planning**; result: **zero residual buggy sites** across 13 TypeScript + 5 SQL owner-touching sites.
2. **One concrete, on-theme observability-hygiene fix**: add the two Sentry ops #5734 introduced (`multiple-owners-reconcile`, `owner-attribution-probe`) to the op-inventory docstring in `server/observability.ts` (currently only `ownerless-reconcile` is listed).
3. **Close #5591** with the sweep evidence; confirm residual scope is owned by **#5756** (SQL/RPC reconciliation + dedicated ADR) and **#5733** (the agent-container filesystem strand — the actual `/soleur:go` blocker, unrelated to this resolver).

This is intentionally a **small** change. Fabricating a larger code deliverable (a shared owner-resolution helper for a single producer site, or a CI guard for a pattern with zero current violations) would be over-engineering and is explicitly rejected — see Sharp Edges.

---

## Research Reconciliation — Spec vs. Codebase

The issue **body** and the issue **title/comments** disagree; the body is stale. The body's "duplicate-workspace creation" premise was disproven across five subsequent comments. This table reconciles the recorded claims against `origin/main` reality (Phase 0.6 Premise Validation).

| Claim (source) | Reality on `main` (verified) | Plan response |
|---|---|---|
| Body: `754ee124` is a same-repo **duplicate** of `52af49c2`; consider de-duping rows | Disproven (comment 2026-06-29): the two workspaces are now different repos/orgs (`chatte`/`70a70ab0` vs `soleur`/`1a8045bf`). `754ee124` is a **legitimate shared team workspace** (2 owners + 2 members, operator-confirmed). | De-dup is **contraindicated**. No data mutation. |
| Re-scope: "owner-canary resolver collapses ≥2 owners to null → false `owner-less` every push (~34×/24h) … recommended fix: deterministic pick (self-row, else earliest `created_at`)" | **Already implemented in #5734** at `workspace-reconcile-on-push.ts:264-345`: selects ALL owner rows ordered `created_at ASC, user_id ASC`; picks self-row (`user_id == ws.id`) else `owners[0]`; emits info `multiple-owners-reconcile` for ≥2; warns `owner-less` only on genuinely-zero rows. | **No re-implementation.** Verify-and-close. |
| Re-scope: "kb_sync recovery-audit gap — `ownerId=null` → workspace-keyed write UPDATEs zero rows → AC12 signal cannot land" | Resolved by #5734: `ownerId` now resolves to the self-row, so the owner-keyed `appendKbSyncRow(ownerId, …)` write lands. The workspace-keyed fallback remains only for genuinely owner-less rows. | Prescribe a **read-only** post-merge confirmation on `754ee124` (no code). |
| Re-scope: "Sweep for sibling call sites with the same `.maybeSingle()`/single-owner assumption — pattern likely recurs" | **Swept (this planning session).** 13 TS + 5 SQL owner-touching sites classified; **zero** carry the collapse bug (all pin the `(workspace_id, user_id)` composite-unique key, select-all-and-handle-N, or do not resolve owners). | Sweep is the deliverable; record evidence; **no sites to fix**. |
| Re-scope: "two owner rows on `754ee124` created via the 058 attestation/invite flow, bypassing single-owner `transfer_workspace_ownership` RPC" | Tracked separately as **#5756** (OPEN): "reconcile single-owner ownership RPCs to the multi-owner-by-design model + dedicated ADR". | **De-scoped to #5756.** Not in this PR. |

**Premise Validation note:** Checked `gh issue view` on #5733 (OPEN), #5730 (MERGED), #5756 (OPEN); `git log` confirms #5734 merged the resolver fix on `main`; read `workspace-reconcile-on-push.ts` + its test file directly. The body premise is stale; the title/comment premise (resolver bug) is **already fixed upstream**. No external blocker is open against this work. The remaining honest deliverable is the sweep (done) + observability-inventory completion + issue close.

---

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing. Worst case, an operator querying Sentry for the `workspace-reconcile-push` op family does not find `multiple-owners-reconcile` / `owner-attribution-probe` documented in the code inventory (a discoverability paper-cut), exactly as today.

**If this leaks, the user's data / workflow / money is exposed via:** no exposure vector. The only edit is a docstring listing already-emitting op slugs; no schema, auth, API route, or data movement.

**Brand-survival threshold:** none.

- **threshold: none, reason:** the only edit is a docstring listing already-emitting Sentry op slugs under `apps/web-platform/server/observability.ts` — no executable code path, schema, auth flow, API route, or data movement changes, so there is no per-user blast radius despite the path matching the `server/` sensitive-path prefix.

> Scope-out rationale (required because `apps/web-platform/server/observability.ts` matches the canonical preflight Check-6 sensitive-path regex via the `apps/web-platform/server` prefix): the change is comment-only. No `requires_cpo_signoff` (threshold is `none`, not `single-user incident`).

---

## Scope

### Already done (verify only — no work)
- Deterministic multi-owner owner-canary resolution in `workspace-reconcile-on-push.ts` — **#5734 (MERGED)**.
- Tests: `test/server/inngest/workspace-reconcile-on-push.test.ts` `describe("reconcile — multi-owner attribution (#5733: N co-owners by design)")` covers self-row preference (:744), team-no-self-row earliest-created tiebreak (:770), and genuinely-zero-owners single drift warn (:789).

### In scope (this PR)
1. Execute the sibling-site sweep and record evidence (done in planning; carried into the PR body + this plan).
2. Add `multiple-owners-reconcile` and `owner-attribution-probe` to the `workspace-reconcile-push` family entry of the op-inventory docstring in `apps/web-platform/server/observability.ts` (above `MIRROR_DEBOUNCE_MS`, near the existing `ownerless-reconcile` line ~367).
3. Close #5591 (`Closes #5591`) with the sweep evidence + #5734 reference.

### Out of scope (de-scoped, owned elsewhere)
- **SQL/RPC reconciliation to the multi-owner model + dedicated ADR → #5756 (OPEN).** Do NOT amend `transfer_workspace_ownership`/`update_workspace_member_role` here. **Advisory for #5756 (architecture review):** its dedicated ADR should also reconcile **AP-015** in `knowledge-base/engineering/architecture/principles-register.md:23` ("owner-membership canary" / single-owner framing, → ADR-044) — not just the RPCs — so the canary principle and the multi-owner-by-design model do not silently diverge. One line in #5756's scope; nothing to add to this plan.
- **The `/soleur:go` strand on `754ee124` (agent-container vs server filesystem divergence) → #5733 (OPEN).** This is the actual hard blocker and is unrelated to the resolver.
- **Provisioning archaeology** ("which flow created the co-owner row"): closed — no duplicate existed; co-owner row is by-design; the creation-path guard (issue item 3) is tracked in **#5673 (OPEN)**.

---

## Implementation Phases

### Phase 0 — Preconditions (read-only, ~3 min)
- `git show origin/main:apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts | sed -n '254,346p'` — confirm the deterministic owner pick is present (it is). If for any reason it is NOT on `main`, STOP and escalate: the premise of this plan (fix already shipped) would be false.
- Confirm the two ops are emitted but absent from the inventory: `grep -n "multiple-owners-reconcile\|owner-attribution-probe" apps/web-platform/server/observability.ts` (expect **no** match) and `grep -n "multiple-owners-reconcile\|owner-attribution-probe" apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` (expect the emit sites).

### Phase 1 — Observability-inventory completion (1 file, docstring only)
Edit `apps/web-platform/server/observability.ts`, the `workspace-reconcile-push` family bullet (~:362-370). After the existing `ownerless-reconcile` sentence, add two sentences documenting:
- `multiple-owners-reconcile` — **info-level** `Sentry.addBreadcrumb` (NOT a warn/page); the honest by-design ≥2-owner signal that distinguishes a legitimate team workspace from owner-canary drift; carries `{ workspaceId, ownerCount }`; introduced by #5734/#5591.
- `owner-attribution-probe` — **warn-level** `reportSilentFallback` op emitted only on a transient owner-read DB error (NOT on zero owners); reconcile falls back to the workspace-keyed audit; introduced by #5734/#5591.

Keep it factual and short (2-3 sentences); do not restate the resolver logic. No code-path change, no new emit site.

### Phase 2 — Verify (no SSH)
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (docstring change must not break types — sanity).
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/workspace-reconcile-on-push.test.ts` — confirm the existing #5734 multi-owner suite is green (regression guard for the already-shipped fix).

### Phase 3 — Close-out
- PR body: `Closes #5591`, summarizing (a) primary fix shipped in #5734, (b) sweep evidence (zero residual sites; see table), (c) the observability-inventory completion, (d) residual de-scope to #5756 + #5733.
- Post-merge (read-only, automatable): confirm on prod via Supabase MCP that `754ee124`'s recovery-audit attribution now lands — `kb_sync_history` for the self-row owner (`754ee124`) carries a recent `recovered`/`trigger: webhook_push` entry — closing the #5730 AC12 observability loop. This is a **read-only** verification, not a deploy step.

---

## Files to Edit
- `apps/web-platform/server/observability.ts` — add `multiple-owners-reconcile` + `owner-attribution-probe` to the `workspace-reconcile-push` op-inventory docstring (~:362-370). **Docstring only.**

## Files to Create
- None.

---

## Open Code-Review Overlap

1 open code-review issue touches `server/observability.ts`:
- **#3739** — "extract `reportSilentFallbackWithUser` helper (collapse 11-site withIsolationScope+setUser duplication)". **Disposition: Acknowledge.** Different concern and different edit region — #3739 deduplicates `reportSilentFallback` *call-site boilerplate*; this PR only adds two op names to the inventory *docstring*. No overlap; #3739 stays open for its own cycle.

---

## Acceptance Criteria

### Pre-merge (PR)
- **AC1** `grep -c "multiple-owners-reconcile" apps/web-platform/server/observability.ts` returns ≥1 AND `grep -c "owner-attribution-probe" apps/web-platform/server/observability.ts` returns ≥1 (both ops now documented in the inventory).
- **AC2** The added text states `multiple-owners-reconcile` is **info-level** (breadcrumb, non-paging) and `owner-attribution-probe` is **warn-level** (reportSilentFallback, on read error) — i.e., neither is described as the `owner-less` drift warn.
- **AC3** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0 (no new type error from the edit).
- **AC4** `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/workspace-reconcile-on-push.test.ts` passes — the #5734 multi-owner attribution suite (3 branches: self-row, earliest-created, zero-owner) is green, confirming the already-shipped fix is intact on this branch.
- **AC5** No change under `apps/web-platform/server/inngest/`, `apps/web-platform/supabase/migrations/`, or any `*.tsx` — the resolver/SQL are untouched (verify-only); the diff is confined to the `observability.ts` docstring.
- **AC6** PR body contains `Closes #5591` and references #5734 (fix), #5756 (SQL/RPC de-scope), #5733 (filesystem de-scope). The body MUST state explicitly: "RPC/data-model residual tracked in #5756" so the close does not read as silently dropping the single-owner-RPC-bypass concern #5591 originally raised (#5756 was spun off FROM #5591).

### Post-merge (optional confirmation — NOT a gate on this PR)
- **Note (not an AC; per simplicity review):** This verification confirms **#5734's** already-merged behavior, not this docstring diff, so it does NOT gate this PR. Optionally, on prod via Supabase MCP (read-only, no SSH), confirm `754ee124`'s `users.kb_sync_history` (self-row owner id `754ee124`) shows a recent `trigger: webhook_push` entry — closing the #5730 AC12 recovery-audit loop. If it has not landed, that is a #5734/#5733 follow-up, not a regression of this PR.

---

## Observability

This change documents two **already-emitting** Sentry ops; it adds no new code path, liveness signal, or failure mode. Schema reflects the as-shipped (#5734) reality.

```yaml
liveness_signal:
  what: "workspace-reconcile-on-push Inngest fn (unchanged) — multiple-owners-reconcile breadcrumb on every push to a ≥2-owner workspace"
  cadence: "per push to a connected multi-owner repo"
  alert_target: "none (info breadcrumb, by design — distinguishes team workspace from drift)"
  configured_in: "apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts:314-323 (emit); documented in server/observability.ts inventory (this PR)"
error_reporting:
  destination: "Sentry — owner-attribution-probe (warn via reportSilentFallback) on owner-read DB error; ownerless-reconcile (warn via mirrorWarnWithDebounce) on genuinely-zero owners"
  fail_loud: true
failure_modes:
  - mode: "transient owner-read DB error"
    detection: "Sentry op=owner-attribution-probe (warn)"
    alert_route: "workspace-reconcile-push family"
  - mode: "genuine owner-canary drift (zero owner rows)"
    detection: "Sentry op=ownerless-reconcile (warn, debounced per workspace_id)"
    alert_route: "workspace-reconcile-push family"
logs:
  where: "Sentry breadcrumbs/events (workspace-reconcile-push category); Inngest run history"
  retention: "Sentry default project retention"
discoverability_test:
  command: grep -c owner-attribution-probe apps/web-platform/server/observability.ts
  expected_output: "1"
```

---

## Architecture Decision (ADR / C4)

**No new architectural decision in this plan.** The multi-owner-by-design model is pre-existing (ADR-038 team workspaces; reinforced by #5733/#5734) and its **dedicated ADR is explicitly owned by #5756**. This PR documents two ops + closes a resolved issue; it neither makes nor changes an ownership/tenancy/resolver boundary.

**C4: no impact (enumerated against all three `.c4` files).** Checked `knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`:
- **External human actor** — the `Owner` actor is already modeled and already states multi-owner: model.c4:9 ("Workspaces may have MULTIPLE Owners (ADR-038 team workspaces); Owner-shared surfaces … readable by every Owner, not just one founder"). No new actor.
- **External system/vendor** — none added (no inbound/outbound integration change).
- **Container/data-store** — `workspace_members` / `users.kb_sync_history` already modeled; no new store.
- **Access relationship** — the multi-Owner-shared relationship is already present (model.c4:9, :268 for the Owner-shared ADR-066 surface). The resolver fix (already shipped) applies the modeled reality; it adds no new edge.

No `.c4` edit required.

---

## Domain Review

**Domains relevant:** none

Single-domain engineering change (one server-util docstring + issue hygiene). Mechanical UI-surface override does not fire — `Files to Edit` contains no `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`, or other UI-surface path; the only file is `server/observability.ts`. No product/legal/finance/marketing/ops/sales/support implications. Infrastructure/tooling-class change.

---

## Test Scenarios

No new tests. The change is a docstring; correctness of the underlying behavior is already locked by the #5734 suite (re-run as AC4 to guard against regression on this branch):
- `two legitimate owners → NO false owner-less warn; attribution to the self-row owner` (self-row preference).
- `no self-row among multiple owners → earliest-created owner wins (deterministic)` (team-workspace tiebreak).
- `genuinely ZERO owner rows still emits exactly one owner-less drift warn` (true drift still surfaces).

---

## Sharp Edges

- **Do NOT re-implement the resolver.** The deterministic multi-owner pick is already on `main` (#5734). Phase 0 verifies this; if it is somehow absent, STOP — the whole plan premise is invalid and the work changes from "verify + document" to "ship the resolver fix".
- **Do NOT build a shared owner-resolution helper or a CI drift-guard.** There is exactly ONE producer site (already correct) and ZERO current violations across the swept 13 TS + 5 SQL sites. A helper for one caller is over-abstraction; a grep-based guard cannot cleanly distinguish the SAFE composite-key-pinned `.maybeSingle()` from the BUGGY unpinned-`role='owner'` collapse without false positives. Both are YAGNI and will be rejected at review. The sweep is a point-in-time audit recorded in the PR body — that is the proportionate artifact.
- **Do NOT touch SQL/RPCs or author an ADR here** — that is #5756's scope. Keep the diff to the `observability.ts` docstring.
- **`Closes #5591` is correct** (not `Ref`): the fix is already live and this PR ships the final completeness touch + carries the administrative close. This is not an ops-remediation/post-merge-apply class, so auto-close at merge is right.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled with threshold `none`.

---

## Refs
- **#5734** (MERGED) — `fix(concierge): … tolerate N co-owners` — ships the resolver fix + 3-branch tests. The primary deliverable of this issue.
- **#5733** (OPEN) — the agent-container vs server filesystem strand stranding `/soleur:go` on `754ee124`. The actual hard blocker; unrelated to this resolver. De-scoped.
- **#5756** (OPEN) — reconcile single-owner ownership RPCs to the multi-owner model + dedicated ADR. Owns the SQL/RPC + ADR residual. De-scoped.
- **#5730** (MERGED) — corrupt-worktree revalidate/re-clone; its AC12 (no-SSH heal verification) was blocked by the false owner-less signal, now unblocked by #5734.
- **#5673** (OPEN) — block duplicate solo repo-connect (same install+repo) + switch redirect — tracks the creation-path guard (issue item 3). Not yet merged; de-scoped here.
