---
title: "supabase-js .update().eq() silently no-ops on 0-rows-matched; guard with .select() row-count"
date: 2026-06-08
category: bug-fixes
module: apps/web-platform
tags: [supabase, postgrest, persistence, silent-failure, workspace-logo, code-trace-repro]
pr: 4996
issue: 4916
---

# supabase-js `.update().eq()` silently succeeds on 0 rows matched

## Problem

A workspace logo upload showed "Logo updated." but reverted to the monogram on
navigation. The POST handler did:

```ts
const upd = await service.from("workspaces").update({ logo_path: key }).eq("id", workspaceId);
if (upd.error) { /* 500 */ }
return NextResponse.json({ ok: true, hasLogo: true }); // 200 even when 0 rows matched
```

`supabase-js` (`@supabase/postgrest-js`) returns **no error** when the `.eq()`
WHERE clause matches zero rows — the PATCH simply affects nothing. So a
`current_workspace_id` that resolves to an id with **no** `workspaces` row (a
stale/wrong active-workspace claim for a shared/team member) produced a false
`200` + success toast, `logo_path` never persisted → monogram on next render.

## Solution

Append `.select("id")` and assert the affected-row count is exactly 1; fail loud
otherwise. `.update().eq().select(cols)` returns the affected rows (postgrest
adds `Prefer: return=representation`), so 0 rows → `data.length === 0`.

```ts
const upd = await service.from("workspaces")
  .update({ logo_path: key }).eq("id", workspaceId).select("id");
if (upd.error) { /* 500 + breadcrumb */ }
if (!upd.data || upd.data.length !== 1) {
  reportSilentFallback(new Error(`persist matched ${upd.data?.length ?? 0} rows`), {
    feature: "workspace-logo", op: "persist-logo-path-zero-rows", extra: { workspaceId },
  });
  // clean the just-uploaded orphan object, then 500
}
```

`!== 1` (not `< 1`) is the intent-expressing guard even though `id` is the PK
(>1 impossible); a future non-PK filter would still be caught. The same guard
applies to the DELETE/clear path (`persist-logo-clear-zero-rows`).

## Key Insight

A write whose success path returns 200 **without reading back what it wrote** is
a silent-persistence-failure vector. For any `.update()/.delete()` whose WHERE
could miss (resolved-id mismatch, stale claim, race), the row-count guard is
both the fix AND the diagnostic — it converts an invisible revert into a Sentry
breadcrumb that names the exact failing `workspaceId`. Mirrors the existing
`.update().select()` precedents in `account-delete.ts` / `ws-handler.ts`.

Related: [[2026-06-01-untyped-supabase-select-nonexistent-column-ships-green]]
(a sibling supabase-js foot-gun — non-existent embedded column ships green).

## Code-trace as a valid substitute for a plan-mandated live repro

The plan mandated a live Playwright + DB-read reproduction (AC1). But the
failing state is a **shared/team workspace in production**; a dev repro is a solo
user where the N2 invariant (`workspaces.id === user.id`) holds and the bug
cannot reproduce. Per the `/work` skill ("code-tracing is a valid substitute for
a plan-prescribed live repro when the repro needs hard-to-synthesize state"), the
localization was done by tracing: write target (`resolveCurrentWorkspaceId`) ==
read target (team page + General resolver, both `resolveCurrentWorkspaceId`), so a
0-rows write is the only mechanism consistent with a 200 toast + reverted
monogram. The row-count guard then makes the next prod occurrence self-localizing
in Sentry — better than a dev repro that can't reproduce the prod-only state.

## Session Errors

- **Plan subagent main-repo write-block / untracked `.pen` Pencil block / dropped placeholder frames** (forwarded from session-state) — Recovery: redirected plan to worktree path; committed empty tracked `.pen` first; recovered frames via Move. Prevention: one-off (Pencil + main-repo guard interplay), already guarded.
- **Anti-slop scanner + `ensure-semgrep.sh` "Module not found"/"No such file"** — Recovery: re-ran from the worktree root (those script paths are repo-root-relative). Prevention: already covered — the review skill documents running anti-slop/semgrep from the worktree/repo root.
- **Bash CWD instability across calls** (`cat test/...` failed; tsc/vitest needed explicit `cd apps/web-platform`) — Recovery: prefixed `cd <worktree>/apps/web-platform &&` per call. Prevention: already covered by `hr-the-bash-tool-runs-in-a-non-interactive` + work/review CWD-doesn't-persist notes.
- **`nav-states` e2e chromium `Target page... has been closed` crashes** (non-deterministic set across runs; zero assertion failures) — Recovery: re-ran the persistently-affected tests in isolation → 3/3 pass, confirming an infra/resource crash (machine throttle), not a layout regression. Prevention: already covered — QA skill documents the "Target page closed" recycle; environmental (machine-specific), not a repo workflow gap.
- **`Monitor` first call rejected (deferred-tool schema not loaded)** — Recovery: `ToolSearch "select:Monitor"` then retried. Prevention: one-off harness mechanic.
