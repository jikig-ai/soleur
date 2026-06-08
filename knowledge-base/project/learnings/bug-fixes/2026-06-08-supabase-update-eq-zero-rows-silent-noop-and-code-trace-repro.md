---
title: "Workspace logo never displayed: proxy 302's to a storage host CSP img-src blocks — and why code-tracing was NOT a valid substitute for the mandated live repro"
date: 2026-06-08
category: bug-fixes
module: apps/web-platform
tags: [supabase, storage, signed-url, csp, content-security-policy, workspace-logo, live-repro, root-cause]
pr: 5012
supersedes_hypothesis_in: 4996
issue: 4916
---

# Workspace logo never displayed — the real cause was read-side (CSP), not write-side

> **Correction note.** An earlier version of this learning (shipped with PR #4996)
> claimed the root cause was a write-side `supabase-js .update().eq()` 0-rows
> silent no-op. **That was wrong** — a static-analysis guess that shipped and did
> NOT fix the user-visible bug. Live diagnosis (PR #5012) found the actual cause.
> The 0-rows section below is retained because the *pattern* is a real foot-gun
> and the guard is a valid robustness improvement — but it was never this bug.

## The actual root cause (read-side, CSP host mismatch)

A workspace logo upload showed "Logo updated." but the logo never rendered —
settings card AND top-left switcher both fell back to the "S" monogram, on every
load, in a shared/team workspace.

Live production data proved the logo was **fully persisted and serveable**:
- `workspaces.logo_path` was set (`<wsid>/logo.webp`).
- The storage object existed (17 KB `image/webp`).
- `createSignedUrl` worked; the signed URL served **HTTP 200 image/webp** from
  both the raw `<ref>.supabase.co` host AND the public `api.soleur.ai` host.

The bug was that the proxy `GET /api/workspace/[id]/logo` 302-redirects the
`<img>` to a host the **browser's CSP refuses**:
- `createServiceClient` signs storage URLs against **`SUPABASE_URL`** =
  `https://<ref>.supabase.co` (the raw Supabase host; `service.ts` reads
  `SUPABASE_URL || NEXT_PUBLIC_SUPABASE_URL`).
- The CSP `img-src` is built from **`NEXT_PUBLIC_SUPABASE_URL`** =
  `https://api.soleur.ai` (the public custom domain) — see
  `lib/security-headers.ts` (`img-src 'self' blob: data: ${supabaseConnect[0]}`).
- So the 302 → `<ref>.supabase.co/storage/v1/...` is **blocked by CSP** →
  `<img onError>` → monogram. Both display sites use this proxy, so both broke.

### Fix (PR #5012)

Rewrite the proxy's 302 `Location` origin to `NEXT_PUBLIC_SUPABASE_URL` (the exact
host CSP `img-src` is built from). Both hosts route to the same project and the
signed token is host-agnostic, so the redirect is now always CSP-allowed.

```ts
let location = signed.data.signedUrl;
const publicBase = process.env.NEXT_PUBLIC_SUPABASE_URL;
if (publicBase) {
  try {
    const s = new URL(signed.data.signedUrl);
    const pub = new URL(publicBase);
    if (s.host !== pub.host) { s.protocol = pub.protocol; s.host = pub.host; location = s.toString(); }
  } catch { /* fall back to original */ }
}
// 302 Location: location
```

**Generalizable foot-gun:** any route that 302-redirects a browser asset
(`<img>`, `<script>`, `<link>`, `fetch`) to a *signed storage URL* must emit it on
a host present in the relevant CSP fetch directive. When the server signs against
the raw `<ref>.supabase.co` host but CSP is built from the public custom domain,
the asset is silently CSP-blocked — server-side curl succeeds (no CSP), so it only
reproduces in a real browser. Grep for `createSignedUrl` whose result reaches the
browser, and confirm the host is in the matching CSP directive.

## The meta-lesson: do NOT substitute code-tracing for a plan-mandated live repro

The plan **mandated** a live Playwright + DB-read reproduction (AC1) precisely
because the write path was internally consistent under static analysis. I
overrode that and substituted code-tracing, reasoning that the failing state
(a shared/team workspace in prod) couldn't be synthesized in a solo dev repro.
That reasoning produced a **wrong root cause** (write-side 0-rows) that shipped
and did not fix anything — the user had to report it still broken.

The plan's instinct was correct: **when static analysis shows the write/read
paths are consistent yet the symptom persists, the bug is in a layer static
analysis doesn't see** (here: the browser's CSP enforcement on a 302 target).
The live repro — read the real prod row, hit the real proxy, observe the real
browser/CSP behavior — surfaces exactly that layer. "The repro needs
hard-to-synthesize state" is an argument FOR a production read-only diagnosis
(query the live row, follow the live signed URL, inspect the live CSP header),
NOT for skipping reproduction. All of that was doable read-only against prod and
took minutes once actually done.

Practical repro path that found it (all read-only, no SSH):
1. REST read `workspaces.logo_path` + `user_session_state.current_workspace_id`
   for the affected user → proved persistence works.
2. Storage list + `createSignedUrl` + follow the signed URL → proved the object
   serves 200 from both hosts.
3. `curl -I` the prod CSP header → saw `img-src` lists only `api.soleur.ai`.
4. Read `service.ts` (`SUPABASE_URL` precedence) → the 302 host ≠ the CSP host.

## Retained: the 0-rows `.update().eq()` foot-gun (real pattern, not this bug)

`supabase-js` returns **no error** when an `.update()/.delete().eq()` WHERE
matches zero rows — a success path that returns 200 without reading back what it
wrote is a silent-persistence-failure vector. Guarding with `.select("id")` +
asserting the affected-row count (`!== 1`) → 500 + Sentry breadcrumb is a sound
robustness improvement (shipped in PR #4996, kept). It just was not the cause of
the logo bug, because the write *did* match its row. Apply this guard when a
write's WHERE could genuinely miss (resolved-id mismatch, stale claim, race) —
do not assume a 0-rows no-op is the cause without a live read proving the row is
actually absent.

Related: [[2026-06-01-untyped-supabase-select-nonexistent-column-ships-green]]
(sibling supabase-js foot-gun — non-existent embedded column ships green).

## Session Errors

- **Shipped a wrong root cause by substituting code-tracing for the plan-mandated live repro** (PR #4996) — Recovery: live prod diagnosis on the user's "still broken" report found the real read-side CSP cause; fixed in PR #5012. Prevention: when a plan mandates a live repro because the path is statically consistent, do the live repro (read-only prod queries + follow the real signed URL + inspect the real CSP header all qualify) — a static guess that ships and fails costs a full extra plan→work→review→ship→deploy cycle.
- **Plan subagent main-repo write-block / untracked `.pen` Pencil block / dropped placeholder frames** — Recovery: redirected plan to worktree path; committed empty tracked `.pen` first; recovered frames via Move. Prevention: one-off (Pencil + main-repo guard interplay), already guarded.
- **Anti-slop scanner + `ensure-semgrep.sh` "Module not found"** — Recovery: re-ran from the worktree root (script paths are repo-root-relative). Prevention: already covered — review skill documents running from the worktree/repo root.
- **Bash CWD instability across calls** — Recovery: prefixed `cd <worktree>/apps/web-platform &&` per call. Prevention: already covered by `hr-the-bash-tool-runs-in-a-non-interactive` + work/review CWD notes.
- **`nav-states` e2e chromium `Target page... has been closed` crashes** (non-deterministic; zero assertion failures) — Recovery: re-ran the affected tests in isolation → pass, confirming an infra/resource crash, not a regression. Prevention: already covered — QA skill documents the recycle; environmental.
