---
title: Canary probe set contract
date: 2026-04-28
owners: engineering/ops
applies_to: apps/web-platform/infra/ci-deploy.sh
related_pr: 3014
---

# Canary probe set contract

The pre-swap canary check in `apps/web-platform/infra/ci-deploy.sh`
exists to reject a broken build BEFORE its container takes the
production port. The legacy contract (`/health` only) was insufficient
and shipped a broken bundle to prod (PR #3014 incident).

## SSR/client divergence (the load-bearing context)

`NEXT_PUBLIC_*` environment variables are inlined into the static
client bundle by Next.js's DefinePlugin at **build time**. The
`lib/supabase/client.ts` module-load validators run **only in the
browser**. So:

- A broken inlined value passes every server-side probe (`/health`,
  SSR-rendered HTML, server-render of `/dashboard` via the server
  Supabase module).
- The throw fires only after the browser parses the client bundle —
  visible to a real user, invisible to `curl`.

The probe contract below is layered specifically to close this blind
spot.

## Layered probes

| Layer | Probe | Catches | Status |
|---|---|---|---|
| 1a | `curl http://localhost:3001/health` returns 200 | container is alive | enforced |
| 1b | `curl http://localhost:3001/login` returns 200 with non-empty body | public route renders | enforced |
| 1c | `curl http://localhost:3001/dashboard --max-redirs 0` returns 200/302/307, body does NOT contain "An unexpected error occurred" | middleware redirect or successful render; rejects SSR-rendered error.tsx | enforced |
| 2 | Headless chromium hydrates `/dashboard` and observes no console errors | client-only throws (e.g. validator at module load) | **deferred — D1** |
| 3 | Probe the deployed bundle for the inlined Supabase JWT and assert canonical claims | inlined build-arg corruption | **deferred — D5** |

Layer 1 is the cheapest broad-coverage gate. Layer 2 is the only thing
that catches the exact PR #3007 regression class. Layer 3 is a
build-arg integrity check — if Doppler / GitHub secret / build-arg
plumbing drifts, Layer 3 detects it without needing a browser.

## Body-content sentinel

The `error.tsx` boundary copy is `An unexpected error occurred`. Any
canary-rendered HTML that contains that string fails the probe and
triggers rollback. This catches **server-component** throws (which DO
render error.tsx during SSR). Client-only throws still need Layer 2.

## Adding a new probe

1. Add the route to the canary loop in `ci-deploy.sh`. Use the existing
   `curl --max-time 5` pattern.
2. Decide the success contract: HTTP status range AND body assertion.
3. Add a failure-mode test in `infra/ci-deploy.test.sh` (e.g.,
   `MOCK_CURL_<NAME>_5XX` env var → expect rollback trace).
4. Bump preflight Check 7 if the new probe is load-bearing for an
   incident class.

## Removing a probe

Probes are load-bearing safety nets. Removing one requires:

1. A linked PR explaining the failure class the probe was protecting
   against and how the new gate covers it.
2. Updating preflight Check 7 if the removed probe is referenced there.
3. Operator review (CTO + ops).

## Why /health alone is insufficient

`middleware.ts:18-20` short-circuits `/health` BEFORE the Supabase
session check runs. The route never imports
`@/lib/supabase/client`, so a broken inlined `NEXT_PUBLIC_SUPABASE_*`
value cannot affect `/health`'s response. This is why PR #3007's
broken bundle returned `200 OK` on `/health` for the entire outage
window — the canary contract said "go" and the swap proceeded.

## References

- AGENTS.md `wg-when-fixing-a-workflow-gates-detection`
- `plugins/soleur/skills/preflight/SKILL.md` Check 7
- `plugins/soleur/skills/preflight/SKILL.md` Check 5 Step 5.4 (Layer 3 source)
- PR #3014 — incident remediation
