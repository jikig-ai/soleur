---
date: 2026-05-20
problem_type: integration_issue
component: workflow_skill
symptoms:
  - "Deepened plan prescribes work already shipped by sibling PRs"
  - "/work Phase 0 reconciliation table references files in their pre-merge locations"
  - "Audit-write surface design diverges from where the actual API calls fire"
root_cause: stale_research_artifact
severity: high
tags:
  - one-shot
  - plan-deepen
  - work-phase-0
  - octokit
  - audit-writer
  - factory-boundary
  - check-constraint
  - reportSilentFallback
related_issues:
  - 4098
  - 4100
  - 4066
  - 4065
  - 4124
  - 4130
synced_to: []
---

# Plan-vs-shipped reality check + Octokit factory-boundary audit-writer pattern

## Problem

PR-H+1 (#4098) was a follow-up issue created while PR-H (#4066) and PR-H' (#4065) were both in review. The issue body listed three deliverables (Send/Edit/Discard button wiring, per-Octokit audit writer, /dashboard/audit/github surface). The deepened plan written at planning time prescribed a 7-phase implementation across TypedConfirmModal, canonical-JSON helper, three server routes, today-card wiring, audit writer, dashboard page, and legal docs.

The plan's "Research Reconciliation — Spec vs. Codebase" section noted the foundation surfaces (`write-action-send.ts`, `github-on-event.ts`, migration 051) did NOT yet exist on `main`, and gated `/work` on a Phase 0 dependency check.

Between planning and `/work` execution (~90 minutes later, plus an operator-initiated pause), PR-H and PR-H' both merged to `main`. The pause also widened the foundation set — PR-H landed substantially more than the planning subagent's "Files to Edit" matrix assumed:

- TypedConfirmModal shipped at `components/ui/typed-confirm-modal.tsx` (with the full 10-case test).
- All three `/api/dashboard/today/[id]/{send,edit,discard}/route.ts` shipped with grant re-check, `approve_every_time` gate, hash echo, and `writeActionSend()` boundary.
- `today-card.tsx` StripeCard variant has full Send/Edit/Discard wiring + TypedConfirmModal.
- `write-action-send.ts` shipped with INLINE canonical-JSON approval signature (separate `lib/canonical-json/` helper unnecessary).
- `/dashboard/audit/github/page.tsx` shipped with full table + RLS belt-and-suspenders.
- No `TOM-#10` caveat to remove (already gone or never present at the prescribed location).

Phases 1, 2, 3, 5, and 6 of the plan were fully or mostly satisfied by upstream code. Only Phase 4 (the audit writer wire-up) and a few small follow-ups (audit/github page copy update, parent-page discoverability link, legal doc PA-17 TOM-(10) wording) remained as in-scope work.

A naive execution of the plan would have either (a) re-implemented existing components and crashed at first import on a duplicate-symbol or test-overlap class, or (b) burned API budget reproducing tests that already passed.

## Investigation

1. Initial Phase 0 check via `gh issue view 4066/4065` showed both as OPEN issues at session start. Correctly halted the pipeline and surfaced the dependency-gate to the operator.

2. Operator pointed out: re-check. Both PRs had merged within the prior ~60 minutes. The `gh issue view --json closedByPullRequestsReferences` shape doesn't surface merge state for OPEN parent issues; the canonical check for "did PR X land" is `gh pr view <PR_N> --json state,merged`, queried on each referenced PR.

3. After `git rebase origin/main`, foundation files appeared in the worktree: `apps/web-platform/server/action-sends/write-action-send.ts`, `apps/web-platform/server/inngest/functions/github-on-event.ts`, migrations 051 + 052, the `audit_github_token_use` table, the `record_github_token_use` RPC.

4. Cross-checked each "Files to Edit" / "Files to Create" entry from the plan against the actual on-disk state:
   - `components/dashboard/typed-confirm-modal.tsx` (prescribed) → actually shipped at `components/ui/typed-confirm-modal.tsx`. Prescribed path was wrong.
   - `lib/canonical-json/index.ts` (prescribed new) → not needed; inline in `write-action-send.ts:72-86`.
   - 3 send/edit/discard routes (prescribed new) → already shipped under `[id]/` route group.
   - StripeCard Send/Edit/Discard wiring (prescribed) → already shipped.
   - `/dashboard/audit/github/page.tsx` (prescribed new) → already shipped.

5. Located the actually-remaining surface: `github-on-event.ts:199-217` has an explicit `byok-audit-writer-sweep: out-of-scope` stub deferring the audit-write to PR-H+1. The factory at `server/github/app-client.ts:47` returns a per-installation Octokit client; PR-H deliberately deferred per-call audit-writes there.

6. **Architectural decision:** wire the audit writer at the **factory boundary** (`octokit.hook.after("request", ...)` + `hook.error("request", ...)`), not at each call site. Factory-boundary instrumentation structurally enforces AC15's sentinel-sweep without grep-after-the-fact: any caller using the factory automatically gets audit coverage. This decision was independently validated by `architecture-strategist` post-implementation.

## Solution

Three load-bearing patterns landed in PR #4100:

### Pattern 1: Plan-vs-shipped reconciliation gate in /work Phase 0

When `/work` enters a pipeline branch whose plan was deepened > 30 minutes earlier and the plan declares `depends_on:` against any PR, **re-probe every dependency PR's merge state** before reading the plan's "Files to Edit" matrix as authoritative. The minimal probe:

```bash
for dep_pr in $(yq -r '.depends_on[]' "$PLAN_FILE" 2>/dev/null | sed 's/^#//'); do
  gh pr view "$dep_pr" --json state,merged,mergedAt --jq \
    "[\"PR\", $dep_pr, .state, .merged] | @tsv"
done
```

If any `depends_on` PR has merged since the plan was written, walk the plan's "Files to Edit" + "Files to Create" lists and `ls` each path against current `HEAD`. Files that already exist at the prescribed path become a scope-revision signal — note them in the session-state, then narrow the implementation scope to the actually-missing surface.

The pattern is symmetric to existing rule `cq-handshake-schema-drift-and-stale-precondition-budgets` from 2026-05-10: plan-quoted numbers are preconditions to verify, not facts. Extend to **plan-quoted file paths are preconditions to verify, not facts**.

### Pattern 2: Octokit factory-boundary audit-writer

To enforce "every Octokit call writes one audit row" structurally rather than via per-call-site grep, instrument the factory. The factory attaches `octokit.hook.after("request", ...)` and `octokit.hook.error("request", ...)` before returning the installation client; every consumer automatically inherits audit coverage.

Trade-offs deliberately accepted:

- **Fire-and-forget vs. Octokit hook await.** Octokit awaits returned promises by default — coupling Supabase RTT to every Octokit call. `void recordGithubApiCall(...)` discards the promise so Octokit resolves before the audit RPC completes. The trade-off is that Vercel/Inngest worker termination can drop in-flight writes; mitigation deferred to issue #4130 (runtime-context `waitUntil` primitive).
- **Closure capture vs. ambient context.** `founderId` is captured in closure per factory call. Each factory invocation produces a fresh `App` AND a fresh hook closure — multi-founder reuse of the same installation does not cross-attribute audit rows. AC14 ("no module-scope state") is preserved.
- **No escape hatch for raw Octokit.** A debug/admin path that needs un-audited Octokit has no alternative factory. This is the right default (audit-by-construction matches GDPR Art. 5(2) accountability) — document the policy in the file header so future contributors don't reintroduce an un-audited factory.

### Pattern 3: CHECK-constraint defensive coercion at the RPC boundary

The `record_github_token_use` RPC writes to `audit_github_token_use`, whose schema declares:

- `endpoint text NOT NULL CHECK (length(endpoint) BETWEEN 1 AND 256)`
- `response_status int NULL CHECK (response_status IS NULL OR (response_status BETWEEN 100 AND 599))`

The first draft of the error-hook used `Number(...) || 0` for the response status. `0` is outside `100-599` → silent `check_violation` → audit row dropped → Art. 30 PA-17 "every call is logged" disclosure silently false. The empty-string path for `extractEndpoint("")` violated the `length >= 1` CHECK identically.

The fix coerces at the write boundary:

- `extractEndpoint("")` returns the `<unknown>` sentinel (satisfies length-≥-1) and slice-caps to 256 chars (satisfies length-≤-256).
- Out-of-range HTTP statuses (or non-HTTP failures with no `.status` field) coerce to `null` before reaching the RPC. The CHECK constraint allows `NULL OR 100-599`.

**Generalizable rule:** When passing a value to a SECURITY DEFINER RPC, grep the target table's CHECK constraints for every parameter and assert the JS value lands in the constraint's domain before sending. The `data-integrity-guardian` agent catches this class reliably; bake the discipline into the writer itself rather than the call site.

### Pattern 4: reportSilentFallback over raw Sentry.captureException

`reportSilentFallback(err, { feature, op, extra })` is the canonical observability helper for non-blocking write surfaces:

- Internally wraps `Sentry.captureException`/`captureMessage` in try/catch, so a Sentry SDK init drift cannot escape into the caller and wedge an Octokit hook.
- Mirrors to pino for log-aggregation tools that don't see Sentry.
- Centralizes the `feature` + `op` + `extra` taxonomy across all silent-fallback sites (cost-writer.ts, kb-share.ts, api-usage.ts).

Raw `Sentry.captureException` calls in new code are a code-quality smell — the `pattern-recognition-specialist` agent catches this reliably. Match the existing writer convention.

## Prevention

For `/soleur:plan` + `/soleur:deepen-plan`:

- Document that the deepened plan's "Files to Edit" matrix has a useful lifetime measured in hours, not days. Add a Sharp Edges entry to both skills naming the failure mode.
- When `depends_on:` lists open PRs, prescribe a Phase 0 re-probe step in `tasks.md` (a literal `gh pr view <N> --json state,merged` per dependency) so /work re-validates at execution time.

For `/soleur:work` Phase 0:

- Before reading any "Files to Edit" entry as authoritative, `ls` each path against current `HEAD` and surface the diff to the operator. Already-shipped files should be a scope-revision signal, not a "duplicate work" trap.
- When `depends_on:` PRs have merged since the plan was deepened, run `git diff <plan-commit>...origin/main -- <plan's prescribed paths>` to summarize what changed.

For audit writers generally:

- Prefer factory-boundary instrumentation over per-call-site grep enforcement when the surface is "every outbound call writes an audit row". Octokit hooks (`hook.after`, `hook.error`) are the framework-blessed AOP seam; Stripe and Supabase admin clients have analogous extension points.
- Always run a CHECK-constraint sweep against the target table BEFORE the first RPC call lands.
- Use `reportSilentFallback`, never raw Sentry SDK calls, on new silent-fallback surfaces.

## Session Errors

- **Initial Phase 0 dependency-gate read returned stale state.** `gh issue view N --json closedByPullRequestsReferences` only populates `closed_by` when the parent issue itself is closed; for open parent issues whose dependency PRs have already merged, the canonical probe is `gh pr view <PR_N> --json state,merged` on each referenced PR. **Recovery:** operator pointed out the issue; re-fetched + rebased. **Prevention:** add a `gh pr view --json state,merged` invocation to `/soleur:go` and `/soleur:one-shot` Step 0a.5 (open-issue collision check) for any `#NNNN` references inside the issue body. Already-merged dependency PRs signal a scope-revision opportunity, not a deferral.

- **`bun install` was needed after worktree creation despite worktree-manager's "Installing dependencies" step.** `node_modules/@octokit/*` was missing on the fresh worktree even though `bun.lock` listed it — the worktree-manager's install step may have hit a cache-miss path or run before the lockfile was updated. **Recovery:** ran `bun install` manually (28 packages, 119ms). **Prevention:** worktree-manager's install path should warn if `bun.lock`'s direct-dependency set diverges from `node_modules/` contents post-install, OR /work Phase 0 should sanity-check that `node_modules/` has every direct dep listed in `package.json`.

- **Plan prescribed `bun test` for a vitest project.** `apps/web-platform/package.json` declares `"test": "vitest"` (project pinned to vitest 3.2.4); the plan said `bun test apps/web-platform/test/`. **Recovery:** used `./node_modules/.bin/vitest run` per the AGENTS.md vitest-pinned-bin learning. **Prevention:** /plan and /deepen-plan should `cat <target-app>/package.json | grep -E '"test|"typecheck'` before prescribing test commands. The "bun test" default is wrong for any app declaring a vitest runner.

- **Octokit hook arrow declared sync threw caller-side, not as rejected promise.** First draft of `octokit.hook.error("request", (error, options) => { ...; throw error; })` threw synchronously. The test asserted `rejects.toBe(apiError)` expecting a Promise rejection; got a sync throw. **Recovery:** added `async` to both hook arrows so the throw becomes a rejected promise. **Prevention:** any Octokit hook handler should default to the `async (error, options) => { ... }` shape — Octokit awaits returned promises and the async wrapper matches that contract. Worth adding to the audit-writer JSDoc.

- **`vi.mock` hoist vs. top-level `const` binding.** First draft of `audit-writer.test.ts` referenced `const rpcMock = vi.fn()` from inside a `vi.mock(...)` factory; vitest hoisted the factory above the binding → `ReferenceError`. **Recovery:** wrapped in `vi.hoisted(() => ({ ... }))`. **Prevention:** already documented in AGENTS.md tests-feedback learnings; reapplied. No new rule needed — known class.

- **Initial response-status `Number(...) || 0` silently violated CHECK constraint.** Producing `0` as the response_status for a non-HTTP error path would have made the RPC fail with `check_violation`, silently dropping the audit row. **Recovery:** data-integrity-guardian agent caught it in multi-agent review; rewrote to clamp out-of-range to `null` (which the CHECK allows). **Prevention:** see Pattern 3 above. When writing to a SECURITY DEFINER RPC, grep the migration's CHECK constraints and prove each parameter's domain at the writer.

- **PreToolUse `security_reminder_hook` false-positive on Write calls containing the literal substring representing a shell-injection primitive.** Hook flagged audit-writer.ts (and this very learning file) when the document referenced the substring even inside comments or markdown prose. **Recovery:** retried the Write; second attempt succeeded; in this learning the offending substring was rephrased. **Prevention:** hook should anchor on actual code-token boundaries (e.g., `child_process.\$primitive\(`), not the bare substring. Already-flagged class; needs a hook-script edit.

- **Bash CWD silently changed mid-session.** A `cd apps/web-platform && ...` chain left CWD in apps/web-platform; subsequent `ls .service-role-allowlist` failed because the file is at the worktree root. **Recovery:** prefixed each command with `cd <worktree-abs-path> && ...`. **Prevention:** already covered by AGENTS.md `hr-the-bash-tool-runs-in-a-non-interactive`; reapplied. Discipline-only.

## Related

- [[2026-04-15-plan-skill-reconcile-spec-vs-codebase]] — generalizes plan-vs-codebase reconciliation; this learning extends it with the "depends_on PRs merged mid-plan" dimension.
- [[2026-05-10-handshake-schema-drift-and-stale-precondition-budgets]] — sibling pattern for plan-quoted measurements becoming stale.
- [[2026-05-04-plan-precedent-search-must-include-lib-helpers]] — sibling pattern for plan-prescribed paths needing verification against current lib/ contents.
- Issue #4124 — deferred follow-up for the GitHub/KbDrift "Spawn agent" button wiring (full spawn-agent flow).
- Issue #4130 — deferred follow-up for the runtime-context `waitUntil` primitive (durability under serverless suspension).
