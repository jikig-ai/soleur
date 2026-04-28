---
title: Module-load throw in a client-bundle module collapses every authenticated route
date: 2026-04-28
category: runtime-errors
related_pr: 3014
related_issue: TBD
related_commits:
  - 7d556531  # PR #3007 — JWT-claims guardrails for NEXT_PUBLIC_SUPABASE_ANON_KEY
---

# Module-load throw collapses the entire auth-required surface

## Symptom

Every authenticated visitor to `app.soleur.ai/dashboard` rendered the
Next.js root `app/error.tsx` ("Something went wrong / An unexpected error
occurred"). Sign-in succeeded; every post-auth landing failed. Two
silently-failed gates compounded: the canary `/health` probe passed
during the deploy, and Sentry produced no actionable alert.

## Mechanism

PR #3007 added `assertProdSupabaseAnonKey` and `assertProdSupabaseUrl`
calls at the **top of** `apps/web-platform/lib/supabase/client.ts`:

```ts
assertProdSupabaseUrl(process.env.NEXT_PUBLIC_SUPABASE_URL);
assertProdSupabaseAnonKey(
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  process.env.NEXT_PUBLIC_SUPABASE_URL,
);
```

This runs **once per JavaScript module evaluation**. In a Next.js client
bundle, that means once when the browser parses the chunk that imports
`@/lib/supabase/client` — which is the chunk for
`app/(dashboard)/layout.tsx`. The throw aborts the React render tree of
every authenticated route at once: `/dashboard`, `/knowledge-base`,
`/chat`, `/settings`, `/teams`. The error is caught by the closest
`error.tsx` boundary, which until #3014 was the root one. There is no
recovery path — every reload runs the same module-load assertion against
the same inlined value.

Critically, the validators run **only in the client bundle**.
`lib/supabase/server.ts`, `service.ts`, and `middleware.ts` use
`createServerClient` and read the env vars directly with no validation.
So:

- SSR of `/dashboard` succeeds.
- The HTML arrives at the browser as a 200.
- Client hydration parses the chunk, runs the validators, throws.
- React renders the error boundary.

`NEXT_PUBLIC_*` values are **inlined at build time** by Next.js's
DefinePlugin. The runtime container's `process.env` does not affect the
deployed bundle. So a `docker restart` after fixing Doppler does
nothing; only a **new build** picks up corrected build-args.

## Why both safety nets failed

### Canary `/health` was insufficient

`middleware.ts:18-20` short-circuits `/health` before the auth path. The
route never imports `lib/supabase/client.ts`. The inlined-bundle bug
cannot affect `/health` — `curl http://localhost:3001/health` returns
200 even when every subsequent client navigation will throw.

The fix (PR #3014) layers the canary: probe `/login` (public route, must
200 with non-empty body), `/dashboard` (auth-required, must 200/302/307
with no error-boundary sentinel), and reject any rendered HTML
containing `An unexpected error occurred`. Layer 2 (chromium-in-canary)
and Layer 3 (deployed-bundle JWT-claim assertion) are deferred to
follow-up issues — see
`knowledge-base/engineering/ops/runbooks/canary-probe-set.md`.

### Sentry alerts did not fire

Three possible contributors (Phase 1 of the postmortem narrows it):

1. The inlined `NEXT_PUBLIC_SENTRY_DSN` was missing from the bundle —
   `Sentry.init({ dsn: undefined })` is a silent no-op.
2. The DSN was present but no alert rule on `feature:
   dashboard-error-boundary` or unhandled `/dashboard` exceptions.
3. The DSN was present and a rule existed, but the client SDK's queue
   did not flush before the page unloaded (the user clicks Try again or
   navigates away).

The fix (PR #3014):

- `app/error.tsx` now uses `reportSilentFallback` with a stable
  `feature: "dashboard-error-boundary"` tag — easier alert authoring.
- A new `app/(dashboard)/error.tsx` segment-scoped boundary tags
  `segment: dashboard` so prod-monitoring can distinguish dashboard
  from public errors.
- `lib/supabase/client.ts` wraps the validator call in a try/catch that
  emits a Sentry event tagged `feature: "supabase-validator-throw"`,
  `op: "module-load"` **before** re-throwing — so the alert fires even
  if `error.tsx`'s post-render `useEffect` doesn't get a chance to run.

## Pattern: the "shared client at the auth boundary" anti-pattern

Any module that:

1. Lives in a shared library (`lib/`, `utils/`, etc.).
2. Is imported by the root layout of an auth-required route group.
3. Throws synchronously at module load.

…is a single point of failure for every authenticated route. The blast
radius is the entire authenticated surface, the recovery time is "until
a new bundle is built and deployed," and the symptom is the framework's
generic error boundary — a UX cliff with no diagnostic affordance.

Mitigations (in order of preference):

1. **Don't throw at module load.** Defer validation to the first call
   that needs the value. Slower-failing but recoverable per-call.
2. **If you must throw at module load**, make the throw observable
   first. Wrap the assertion in a try/catch that emits the failure to
   Sentry with full context, then re-throw. The fail-closed posture is
   preserved; the diagnostic gap is closed.
3. **Add a route-segment error boundary** (`app/(group)/error.tsx`) so
   the error doesn't bubble to the root and the segment context is
   tagged.
4. **Probe the failure path** in the canary (or a synthetic check). HTTP
   200 on a server-rendered HTML page is not proof that the client
   hydrates without error.

## Detection / re-evaluation criteria

Future module-load throws in client bundles imported by the auth tree
should:

- Carry a Sentry tag matching `feature: "<module>-validator-throw"` or
  similar, emitted before the throw.
- Be paired with a layered canary probe of the auth-required surface.
- Be paired with a corresponding learning entry if they introduce a
  new failure class.

If a future incident shows that Layer 1 + Layer 3 still missed a
client-only throw, escalate Layer 2 (chromium-in-canary, D1) from
deferred to in-scope.

## See also

- `knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md` — the operator-facing diagnosis + hot-fix runbook
- `knowledge-base/engineering/ops/runbooks/canary-probe-set.md` — the canary contract
- `apps/web-platform/lib/supabase/client.ts` — wrapped validator call site
- `apps/web-platform/app/error.tsx`, `apps/web-platform/app/(dashboard)/error.tsx` — observability-migrated error boundaries
- `apps/web-platform/lib/client-observability.ts` — `reportSilentFallback` shim (avoids pulling pino into the client bundle)
- AGENTS.md `cq-silent-fallback-must-mirror-to-sentry` — the rule this incident was a violation of (the throw was silently invisible to Sentry until #3014's wrapper)
