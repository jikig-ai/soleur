---
title: "Validate workspaceId shape before join() in workspace path construction (CWE-22 defense-in-depth)"
type: fix
date: 2026-06-15
issue: 5344
branch: feat-one-shot-5344-workspaceid-shape-validation
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Validate workspaceId shape before `join()` in workspace path construction (CWE-22 defense-in-depth)

## Enhancement Summary

**Deepened on:** 2026-06-15
**Passes run:** security-sentinel review, 2× learnings-relevance, verify-the-negative (sonnet), all always-on gates (4.6 User-Brand / 4.7 Observability / 4.8 PAT / 4.9 UI — all pass/skip).

### Key Improvements
1. Added a multiline-`$`-evasion RED test case (`<uuid>\n../etc`) — security-sentinel LOW; pins regex against a future `m`-flag edit.
2. Folded the security-sentinel MEDIUM (raw-value echo into the Sentry-bound Error message = log-injection vector) into Risks with a preferred `JSON.stringify(workspaceId)` sanitize option (non-blocking, consistent-with-precedent).
3. Cited the two governing learnings: `2026-04-11` (point-of-use validation = the two-guard rationale; allowlist > denylist) and `2026-04-07` (CWE-59 symlink-traversal under the resolved path is explicitly out of scope).

### New Considerations Discovered
- Verify-the-negative pass CONFIRMED all 5 external callers pass DB UUIDs (guard is a no-op on the happy path) and that the broad KB/attachment surface is transitively protected via `resolveActiveWorkspaceKbRoot` → `workspacePathForWorkspaceId`.
- The all-zero UUID is shape-valid (passes); existence/membership is a separate downstream concern, unchanged.

🐛 / 🔒 Closes #5344.

`semgrep-sast` rule `path-join-resolve-traversal` (CWE-22 / OWASP A01:2021) flags three sites in `apps/web-platform/server/workspace-resolver.ts` where a `workspaceId` (DB-sourced, typed `string | null`) flows into `join()` to build a bwrap filesystem mount path (ADR-038) with **no UUID-shape / path-containment validation**:

- `:486` — `kbRoot: join(workspacePath, "knowledge-base")` (downstream of the `workspacePathForWorkspaceId(activeWorkspaceId)` call at `:481`)
- `:708` — `return join(getWorkspacesRoot(), workspaceId)` inside `resolveWorkspacePathForUser`
- `:719` — `return join(getWorkspacesRoot(), workspaceId)` inside `workspacePathForWorkspaceId`

The practical traversal surface is small (`workspaceId` is membership-gated and fails closed to `userId`), and semgrep rated it **low real-world severity**. The gap is purely defense-in-depth: the column is typed `string | null`, not a validated UUID, so a malformed value reaching `user_session_state` via a future writer / backfill bug / unpinned SECURITY DEFINER RPC would flow straight into a bwrap mount path with **no boundary check**. The fix converts the resolver from "trusts the DB invariant" to "enforces it."

The deferral's re-eval trigger has fired: PR #5338 (the durable workspace-binding resolver, the PR during whose review this was surfaced) is **MERGED**, satisfying "when `resolveWorkspacePathForUser` / `workspacePathForWorkspaceId` is next modified, or a new writer of `current_workspace_id` is introduced." This one-shot pipeline actions the deferred scope-out.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing in the normal path — the guard is a no-op on every valid UUID (all current callers pass DB UUIDs or `user.id`, itself a UUID). A bug in the guard regex that rejected a valid UUID would surface as a hard `503`/throw on workspace resolution for the affected user (KB upload, share-link render, DSAR export, push-reconcile) — caught by the existing resolver test surface before merge.
- **If this leaks, the user's knowledge-base / workspace files are exposed via:** a crafted-or-corrupted `workspaceId` containing `..`, `/`, or an absolute prefix flowing into `join(getWorkspacesRoot(), workspaceId)` and escaping the per-tenant `/workspaces/<id>` mount (ADR-038), reading or writing another tenant's KB directory. This is the exact CWE-22 traversal the guard closes.
- **Brand-survival threshold:** `single-user incident` — the touched functions ARE the cross-tenant filesystem isolation boundary; a single escaped mount path is a single-user data-isolation breach. (Note: real-world reachability is low — DB-sourced + membership-gated + fail-closed — so this is the lowest end of the threshold, but the boundary class warrants the tier.)

`requires_cpo_signoff: true` — CPO sign-off required at plan time before `/work` begins (the technical approach below is a single mirrored guard; CLO/CTO concerns are reflected in the Risks + Domain Review sections). `user-impact-reviewer` will be invoked at review-time per `plugins/soleur/skills/review/SKILL.md`.

## Overview

Add a single UUID-shape assertion at the **two** id→path boundary functions. Because `kbRoot` (`:486`) is built from the return of `workspacePathForWorkspaceId(activeWorkspaceId)` at `:481`, guarding `workspacePathForWorkspaceId` covers finding `:486` transitively, and guarding `resolveWorkspacePathForUser` covers `:708`. **Two guards collapse all three findings.**

The guard mirrors the **existing in-repo precedent** verbatim: `apps/web-platform/server/workspace.ts:104-107` (`provisionWorkspace`) already does

```ts
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// ...
if (!UUID_RE.test(workspaceId)) {
  throw new Error(`Invalid workspaceId format: ${workspaceId}`);
}
const workspacePath = join(getWorkspacesRoot(), workspaceId);
```

`api-usage.ts:46,94` uses the identical `UUID_RE` for the same purpose. The fix adds the same constant + the same throw-before-`join()` shape to `workspace-resolver.ts`. `userId` is itself a UUID, so the solo-workspace case (`workspaceId === userId`, N2 invariant) passes unchanged. ~6–10 lines, 1 source file + 1 test file.

## Research Reconciliation — Issue claims vs. Codebase

| Issue claim | Reality (verified `origin/main`) | Plan response |
| --- | --- | --- |
| 3 sink lines at `:486`, `:708`, `:719`, byte-identical on `main` | Confirmed via `git grep -nE 'join\(.*workspace\|kbRoot\|getWorkspacesRoot' origin/main` — exact lines present | Guard the two boundary functions; `:486` covered transitively |
| "One guard collapses all 3 findings" | `:486` builds on `:481` = `workspacePathForWorkspaceId(...)`; that function is `:719`. So `:486` + `:719` are one boundary; `:708` is a second | **Two** guards needed (not one), both mirroring the same `UUID_RE`. Plan corrects the issue's "single" framing. |
| `workspaceId` is `string \| null` typed, not validated UUID | Confirmed — `getDefaultWorkspaceForUser` returns `string`; `workspacePathForWorkspaceId(workspaceId: string)` | Guard enforces the shape the type cannot |
| No existing UUID validation precedent named | `workspace.ts:67/104`, `api-usage.ts:46/94` both have `UUID_RE` + throw-before-join | Reuse the exact pattern; do NOT invent a new form (per plan-time parsing-pattern-precedent rule) |
| PR #5338 only adds `readWorkspaceIdFromDb`, never into a `join()` path | PR #5338 MERGED; path sinks fed by share/dsar/reconcile/kb-share callers, not the PR | Pre-existing finding correctly deferred; re-eval trigger now fired |

## Implementation Phases

### Phase 0 — Preconditions (grep verification, no edits)

1. `grep -n 'UUID_RE' apps/web-platform/server/workspace.ts apps/web-platform/server/api-usage.ts` — confirm the canonical regex literal to copy verbatim.
2. `git grep -nE 'workspacePathForWorkspaceId|resolveWorkspacePathForUser' -- apps/web-platform | grep -v workspace-resolver.ts` — confirm all callers pass a DB UUID or `user.id` (verified via verify-the-negative pass: `shared/[token]/route.ts:195` (`shareLink.workspace_id`, DB `string`), `shared/[token]/c4/route.ts:86` (`shareLink.workspace_id`), `dsar-export.ts:95` (`resolveDsarWorkspacePath(subjectUserId)` — a wrapper around `workspacePathForWorkspaceId`, `subjectUserId` is a `user_id` UUID), `inngest/.../workspace-reconcile-on-push.ts:303` (`ws.id`), `kb-share.ts:878` (`row.workspace_id`)). None pass a non-UUID → guard is a no-op on the happy path. Note: the broad KB/attachment caller surface (`attachment-pipeline.ts`, `agent-runner.ts`, `app/api/kb/*`) reaches `join` only through `resolveActiveWorkspaceKbRoot`/`resolveActiveWorkspacePath`, which themselves route `activeWorkspaceId` through `workspacePathForWorkspaceId` — so the single `workspacePathForWorkspaceId` guard protects them transitively too.
3. Confirm test env glob: `apps/web-platform/vitest.config.ts:44` → `test/**/*.test.ts` (node env). New test lands in `apps/web-platform/test/`.

### Phase 1 — RED: write failing tests first (`cq-write-failing-tests-before`)

Create `apps/web-platform/test/workspace-resolver-id-shape-guard.test.ts` (node env, `test/**/*.test.ts`). Mirror the `workspace.test.ts` shape (imports `randomUUID` from `crypto`).

Test cases:

- `workspacePathForWorkspaceId(randomUUID())` returns `<WORKSPACES_ROOT>/<uuid>` (happy path, no throw).
- `workspacePathForWorkspaceId("../etc")` throws `Invalid workspaceId format`.
- `workspacePathForWorkspaceId("a/b")` throws (embedded slash).
- `workspacePathForWorkspaceId("/absolute")` throws (absolute prefix — defeats `join`).
- `workspacePathForWorkspaceId("")` throws (empty).
- `workspacePathForWorkspaceId("not-a-uuid")` throws.
- `workspacePathForWorkspaceId("00000000-0000-0000-0000-000000000000\n../etc")` throws (multiline `$` evasion — the classic CWE-22 newline-suffix bypass; verified empirically safe because the regex has no `m` flag and the `{12}` group is saturated, but pin a test so a future regex edit that adds `m` fails loudly). Added per security-sentinel LOW finding.
- `resolveWorkspacePathForUser(userId, mockSupabase)` where the mock's `getDefaultWorkspaceForUser` resolves a **non-UUID** `workspace_id` → throws `Invalid workspaceId format` (proves the guard fires on the DB-sourced value, the actual threat vector). Use a recursive supabase chain mock matching the `getDefaultWorkspaceForUser` shape at `workspace-resolver.ts:597-627`.
- `resolveWorkspacePathForUser` with a valid-UUID `workspace_id` → returns the joined path (no throw).

Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/workspace-resolver-id-shape-guard.test.ts` — expect failures (guard not yet added).

### Phase 2 — GREEN: add the two guards

In `apps/web-platform/server/workspace-resolver.ts`:

1. Add module-level constant near `getWorkspacesRoot` (around `:28-32`):
   ```ts
   // Mirrors workspace.ts:67 / api-usage.ts:46 — id-shape gate before any
   // value flows into join() to build a bwrap mount path (ADR-038, CWE-22).
   const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
   ```
2. In `workspacePathForWorkspaceId` (`:718`), before the `join`:
   ```ts
   if (!UUID_RE.test(workspaceId)) {
     throw new Error(`Invalid workspaceId format: ${workspaceId}`);
   }
   ```
3. In `resolveWorkspacePathForUser` (`:703`), after `getDefaultWorkspaceForUser` resolves `workspaceId` and before the `join` (`:708`):
   ```ts
   if (!UUID_RE.test(workspaceId)) {
     throw new Error(`Invalid workspaceId format: ${workspaceId}`);
   }
   ```

Note on `:486`: no separate guard — it consumes the return of `workspacePathForWorkspaceId(activeWorkspaceId)` (`:481`), which now throws on a bad id before `kbRoot` is built. Add a one-line comment at `:481`/`:486` noting the guard lives in `workspacePathForWorkspaceId`.

Run the RED test again → expect GREEN.

### Phase 3 — Verify full surface (no regressions)

1. Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w`; root has no `workspaces` field).
2. Run the adjacent test surface that exercises these functions:
   `cd apps/web-platform && ./node_modules/.bin/vitest run test/kb-share.test.ts test/shared-token-c4.test.ts test/dsar-export-workspace-path-resolver.test.ts test/durable-workspace-binding-resolver.test.ts test/workspace-resolver-id-shape-guard.test.ts`
   — all callers pass UUIDs, so all must stay GREEN.
3. Re-run `semgrep-sast` rule `path-join-resolve-traversal` against `workspace-resolver.ts` — confirm 0 findings (the throw-before-join is the pattern the rule accepts; mirrors how `workspace.ts:104` is already clean).

## Acceptance Criteria

### Pre-merge (PR)

- [x] `UUID_RE` constant added to `workspace-resolver.ts` matching `workspace.ts:67` byte-for-byte: `grep -c '\^\[0-9a-f\]{8}-\[0-9a-f\]{4}-\[0-9a-f\]{4}-\[0-9a-f\]{4}-\[0-9a-f\]{12}\$' apps/web-platform/server/workspace-resolver.ts` returns ≥ 1.
- [x] Both boundary functions throw `Invalid workspaceId format` on non-UUID input: `grep -c 'Invalid workspaceId format' apps/web-platform/server/workspace-resolver.ts` returns 2.
- [x] New test file exists and passes: `cd apps/web-platform && ./node_modules/.bin/vitest run test/workspace-resolver-id-shape-guard.test.ts` → 0 failures, ≥ 9 assertions covering: valid UUID passes, `..`/slash/absolute/empty/`not-a-uuid`/newline-suffix-evasion each throw, and the `resolveWorkspacePathForUser` DB-sourced-non-UUID case throws. (10 assertions, all pass.)
- [x] Happy-path callers stay GREEN: full `apps/web-platform` vitest suite returns 0 failures (795 files passed; the guard's stricter id contract required a UUID-fixture sweep across 34 test files + a shared `test/helpers/workspace-tmpdir.ts` helper — scope expansion beyond the plan's 1+1 estimate, the test suite pervasively used short non-UUID ids like `"user-1"`).
- [x] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → 0 errors.
- [x] CWE-22 traversal vector closed via throw-before-join. NOTE (corrected at review): `semgrep-sast` `path-join-resolve-traversal` is a PURELY SYNTACTIC matcher (`join($X, …)`) that does NOT recognize the upstream `UUID_RE.test()` throw as a sanitizer — it still reports the 3 `join()` lines, and the already-shipped guarded precedent `workspace.ts` trips the same rule 13×. So "0 findings" was a false premise; the rule cannot see the fix. What matters: the diff introduces ZERO NEW findings (custom rules + p/js + p/ts = 0), the `join()` lines are byte-unchanged from main, and the actual traversal vector is closed by the guard. A baseline/diff-aware CI scan shows 0 net-new.
- [ ] PR body uses `Closes #5344` (set at ship phase) (this is a code fix that resolves at merge — NOT an ops-remediation deferred to post-merge).

### Post-merge (operator)

- [ ] None. Pure code change against an already-provisioned surface; the deploy pipeline (`web-platform-release.yml`, path-filtered on `apps/web-platform/**`) restarts the container on merge. No infra, no migration, no secret.

## Domain Review

**Domains relevant:** Engineering (security/defense-in-depth)

### Engineering

**Status:** reviewed (inline — single-domain security hardening; no leader spawn warranted for a 2-guard mirror of an existing precedent)
**Assessment:** This is a textbook defense-in-depth boundary guard. The change introduces no new control flow, no new dependency, and reuses an established in-repo pattern (`workspace.ts` `UUID_RE`). The guard is placed at the **id→path boundary functions** (point-of-use validation per learning `2026-04-11-service-role-idor-untrusted-ws-attachments.md` — not at every call site, not relying on the upstream DB-writer/`provisionWorkspace` guard), and `:486` is covered transitively via `:481` — verified by tracing the call graph from the kbRoot construction back to `workspacePathForWorkspaceId` (and confirmed by the deepen-plan security pass: no `join` sink in the file bypasses the two guarded functions). CTO/CLO concerns (cross-tenant filesystem isolation = the ADR-038 bwrap boundary) are addressed by closing the exact CWE-22 vector; no residual concern. Scope note: CWE-59 symlink-traversal under the resolved path is a separate, out-of-scope boundary (see Risks).

### Product/UX Gate

Not applicable — no UI surface. The plan's `## Files to Create` / `## Files to Edit` contain only server `.ts` + test `.ts`; no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. Mechanical UI-surface override did NOT fire. Tier: NONE.

## Infrastructure (IaC)

Skipped — no new infrastructure. The plan only edits `apps/web-platform/server/` + adds a test under `apps/web-platform/test/`. No server, service, secret, vendor, cron, or persistent runtime process introduced.

## Observability

```yaml
liveness_signal:
  what: "Existing resolver test surface (kb-share, shared-token, dsar-export, durable-workspace-binding) exercises the guarded functions on every CI run; the guard is a no-op on valid UUIDs so green CI is the steady-state signal."
  cadence: "Every PR + every push to main (CI)."
  alert_target: "GitHub Actions CI failure (web-platform test job) → existing CI Slack notification."
  configured_in: ".github/workflows/web-platform-release.yml (test job) + apps/web-platform/vitest.config.ts."
error_reporting:
  destination: "Sentry — a thrown `Invalid workspaceId format` propagates to the caller's existing error boundary. Share routes return their status contract (503); kb-share / dsar / reconcile callers already wrap resolver calls in try/catch that route to Sentry via reportSilentFallback (see workspace-resolver.ts:471, 548)."
  fail_loud: true
failure_modes:
  - mode: "Malformed/crafted workspaceId reaches a boundary function (the CWE-22 vector this fix closes)."
    detection: "Guard throws `Invalid workspaceId format: <value>`; surfaces in the caller's catch → Sentry with the offending value in the message."
    alert_route: "Sentry issue (new error signature `Invalid workspaceId format`) — distinct from normal resolver errors; an occurrence indicates a real upstream integrity bug (the deferral's hypothesised future-writer/backfill defect) worth paging on."
  - mode: "Regex false-rejects a valid UUID (regression risk)."
    detection: "Phase 3 happy-path vitest suite fails on real DB UUIDs; caught pre-merge."
    alert_route: "CI failure → blocks merge."
logs:
  where: "Sentry (via the existing reportSilentFallback / caller catch paths). No new log line added — the thrown Error message carries the offending value."
  retention: "Sentry default project retention."
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/workspace-resolver-id-shape-guard.test.ts"
  expected_output: "Test files 1 passed; the non-UUID cases assert the throw, proving the guard is reachable and observable without ssh."
```

## GDPR / Compliance

Advisory note only. The fix touches the tenant-isolation filesystem boundary (where per-workspace KB / PII lives), but the change is a **read-only shape validation** that ADDS a containment guarantee — it moves no data, adds no processing activity, and creates no new data surface. It strengthens GDPR Art. 32 (security of processing / tenant isolation) rather than expanding any data flow. No Article 30 register entry, no new lawful-basis question. No critical findings.

## Files to Edit

- `apps/web-platform/server/workspace-resolver.ts` — add `UUID_RE` constant + two `if (!UUID_RE.test(...)) throw` guards in `resolveWorkspacePathForUser` (`:703-709`) and `workspacePathForWorkspaceId` (`:718-720`); one clarifying comment at `:481`/`:486`.

## Files to Create

- `apps/web-platform/test/workspace-resolver-id-shape-guard.test.ts` — RED-first test covering the two guards (valid UUID passes; `..`/slash/absolute/empty/non-uuid throw; DB-sourced non-UUID via `resolveWorkspacePathForUser` throws).

## Open Code-Review Overlap

None. (Queried `gh issue list --label code-review --state open`; no other open scope-out names `workspace-resolver.ts`. This issue #5344 is the only one touching these path-construction functions.)

## Test Scenarios

| Input to `workspacePathForWorkspaceId` | Expected |
| --- | --- |
| `randomUUID()` | returns `<root>/<uuid>`, no throw |
| `"../../etc/passwd"` | throws `Invalid workspaceId format` |
| `"a/b/c"` | throws (embedded slash) |
| `"/abs/path"` | throws (absolute prefix defeats `join`) |
| `""` | throws (empty) |
| `"00000000-0000-0000-0000-000000000000"` | returns path (all-zero is shape-valid; membership/existence is a separate downstream concern, unchanged) |

| Scenario for `resolveWorkspacePathForUser` | Expected |
| --- | --- |
| DB returns valid-UUID `workspace_id` | returns joined path |
| DB returns non-UUID `workspace_id` (the threat) | throws `Invalid workspaceId format` BEFORE `join` |

## Risks & Mitigations

- **Precedent diff (per deepen-plan Phase 4.4):** the guard is a verbatim mirror of `workspace.ts:104-107` (`provisionWorkspace`) and `api-usage.ts:94`. No novel pattern. Both precedents throw `Error` synchronously before `join`; this plan adopts the identical shape and the identical `Invalid workspaceId format: ${id}` message string from `provisionWorkspace` so a single Sentry signature covers all provisioning + resolution paths.
- **Behavioral risk on happy path:** zero — every current caller passes a DB UUID or `user.id` (itself a UUID). Verified via Phase 0 step 2 caller grep. The all-zero UUID is shape-valid and still passes (existence/membership is enforced elsewhere and unchanged).
- **Regex false-reject:** the `i` flag + standard 8-4-4-4-12 hex shape matches `randomUUID()` (lowercase) and any uppercase variant. Pinned to the established repo literal — not re-authored.
- **Throw vs. fail-soft:** the precedent throws (does not return null / a sentinel path). Throwing is correct here — a non-UUID reaching this boundary is an integrity violation (the deferral's exact hypothesis), and silently returning a fallback path would mask it. Callers already handle resolver throws (try/catch → Sentry → status contract). Throwing is strictly MORE available than a fallback: the only inputs that throw are malformed ones that would otherwise escape the mount; there is no input that is both valid-for-service and rejected-by-guard. The Inngest reconcile fan-out (`workspace-reconcile-on-push.ts:303`) iterates per-workspace and a throw would abort that step, but its input is `ws.id` (a DB UUID) so the guard is a no-op there.
- **Message-echo / log-injection (security-sentinel MEDIUM, non-blocking, consistent with precedent):** the thrown `Invalid workspaceId format: ${workspaceId}` echoes the raw offending value, which the Observability section routes to Sentry via the callers' catch → `reportSilentFallback`. In the threat scenario the value is attacker-influenced, so embedding ` `/` `/control chars becomes a log-injection vector into the Sentry JSON viewer. The existing precedent (`workspace.ts:106`) has the identical exposure, so this is consistent-with-precedent, NOT a regression, and the value is a non-PII id — do NOT block merge. **Implementer option (preferred):** sanitize the interpolated value with `JSON.stringify(workspaceId)` (escapes control chars + quotes the value) OR drop the value from the message entirely and rely on the `extra` bag the callers already attach. If sanitizing, do NOT propagate the raw-echo form to `workspace.ts` — leave that precedent for a separate `beforeSend` hardening pass.
- **Point-of-use validation (learning `2026-04-11-service-role-idor-untrusted-ws-attachments.md`):** the two-guard decision (not one, not relying on `provisionWorkspace`'s upstream guard) is the direct application of "if a service-role client will act on data, validate it at the point of use, not just the point of generation." Each `join` site is an independent point of use; the DB writer's invariant does not transfer to the resolver path. The chosen `UUID_RE` is an ALLOWLIST (positive 8-4-4-4-12 shape) which is strictly stronger than that learning's denylist (`reject ..`) — it rejects every separator/traversal token as a side-effect.
- **Scope boundary (learning `2026-04-07-symlink-escape-recursive-directory-traversal.md`):** this guard closes the id→path *root-join* boundary only. Symlink-following during any recursive traversal UNDER the resolved `workspacePath`/`kbRoot` is a separate CWE-59 boundary (handled by `!entry.isSymbolicLink()` / `isPathInWorkspace` at enumeration sites) and is explicitly OUT OF SCOPE for #5344. The UUID guard does not make the whole bwrap mount traversal-proof — it makes the mount-root construction traversal-proof.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is complete with threshold `single-user incident`.)
- Do NOT collapse the two guards into "one guard" as the issue body suggested — `:708` (`resolveWorkspacePathForUser`) and `:719` (`workspacePathForWorkspaceId`) are independent `join` sites with independent callers. `:486` is the only finding covered transitively.
- Typecheck MUST be `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — `npm run -w apps/web-platform typecheck` aborts (`No workspaces found`; root `package.json` declares no `workspaces`).
- Test file MUST live at `apps/web-platform/test/*.test.ts` (node env per `vitest.config.ts:44`), NOT co-located next to `workspace-resolver.ts` (vitest would never collect it).
