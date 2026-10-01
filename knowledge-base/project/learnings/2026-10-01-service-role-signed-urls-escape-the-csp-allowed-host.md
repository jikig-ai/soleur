# Learning: Every browser-bound signed storage URL must be rewritten to the CSP-allowed host — the service-role client always returns the raw `*.supabase.co` host

## Problem

PR #9344 fixed a live upload regression: the Concierge chat failed every file
upload with the generic toast "Upload failed. Check your connection and try
again." Root cause: `app/api/attachments/presign/route.ts` returned
`uploadUrl: data.signedUrl` verbatim — and `data.signedUrl` is minted by the
service-role client against `SUPABASE_URL`, which in production is the raw
`<ref>.supabase.co` host. Prod CSP `connect-src` is built from
`NEXT_PUBLIC_SUPABASE_URL` (`api.soleur.ai`, the project's custom domain) and
does not list `*.supabase.co`, so the browser's XHR PUT was CSP-blocked at the
network layer (`xhr.onerror`, `xhr.status === 0`) and the UI had no signal to
distinguish it from a flaky connection.

Dev never caught it because dev config sets both vars to the same host — the
signed URL's host already matched `connect-src`. Only prod splits them.

The defect had sat in production ~5.5 months (introduced in #1975, the original
attachments feature). It became user-visible only when `.md`/`.txt` support
(#9290) made people actually attach files.

## Solution

The fix was one line at the response boundary — the SAME defect class as
#5020's download-URL fix:

```ts
uploadUrl: toPublicStorageUrl(data.signedUrl)   // lib/supabase/public-storage-url.ts
```

`toPublicStorageUrl` rewrites protocol+host onto `NEXT_PUBLIC_SUPABASE_URL`
and passes pathname + `?token=` through verbatim (the token is bound to
bucket+path+TTL, not hostname).

Plus telemetry at the transport chokepoint (`lib/upload-with-progress.ts
fail()`) so any residual failure names its leg: `feature:attachments`,
`op:storage-put`, extras `{status, filename}` — status 0 = CSP/network block,
4xx/5xx = storage reject.

## Key Insight

**Any signed URL the browser must fetch is a CSP-boundary object.** The
service-role Supabase client signs against `SUPABASE_URL` (raw host); the
browser is confined to `NEXT_PUBLIC_SUPABASE_URL` by CSP. Whenever the two
differ — which is exactly the production topology — the raw URL is undeliverable.
The fix is never "widen CSP" (an enumerated allowlist is the point); it is to
rewrite the URL at the route that hands it to the browser. When you add a new
`createSignedUrl`/`createSignedUploadUrl`/`getPublicUrl` whose output reaches
the browser, it needs `toPublicStorageUrl` — pattern-recognition confirmed
presign was the last unrewritten surface (download route and workspace logo
route were already fixed in #5012/#5020).

**Companion gaps found by the review panel, worth remembering:**

- *The transport chokepoint is the right place for telemetry, but callers with
  their own Sentry catch will double-report.* Mark the minted error
  (`err.reportedToSentry = true`) so the caller's catch can skip re-capture —
  cheaper than tracing which leg threw.
- *`JSON.stringify(new Error(...))` is `{}` — `message` is non-enumerable.* A
  "no secrets in the payload" test that stringifies the mock's call args is
  vacuous for the error channel, which is the exact channel `captureException`
  transmits. Assert `toHaveBeenCalled` first (non-vacuity), then check
  `String(err.message)` directly.
- *A test asserting "helper swallows its own failure" must also handle the
  sync-throw path.* `try/finally` around `reject()` still lets the exception
  propagate out of the event handler (`xhr.onerror`) as an unhandled error
  even though the promise rejected — CI caught exactly this. `catch {}` the
  report, then `reject` unconditionally.
- *`vi.unstubAllEnvs()` does not clear ambient env.* Tests asserting URL
  passthrough silently depend on `NEXT_PUBLIC_SUPABASE_URL` being unset in the
  developer's shell — pin it explicitly in `beforeEach`
  (`vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "")`).

## Evidence

- PR #9344 (merged 2026-10-01, admin-merge after green CI) — fix + first test
  suite for `upload-with-progress.ts` (the module had zero coverage since
  #2133; every consumer mocked it).
- Live verification during planning: prod CSP header from `app.soleur.ai`
  vs. signed-URL host from `createSignedUploadUrl` — mismatch confirmed.
- Plan: `knowledge-base/project/plans/2026-10-01-fix-concierge-attachment-upload-plan.md`
- CI failure that validated the sync-throw finding: `test-webplat (2/2)` on
  run 36838892076 — `Error: sentry down` escaped `xhr.onerror` as an unhandled
  error despite the promise rejecting.
