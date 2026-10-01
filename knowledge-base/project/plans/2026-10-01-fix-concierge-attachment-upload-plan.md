---
title: "fix: attachment uploads CSP-blocked — presign hands the browser a raw *.supabase.co PUT URL"
type: fix
date: 2026-10-01
slug: fix-concierge-attachment-upload
branch: fix-one-shot-attachment-upload-regression
priority: high
domain: engineering
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix: attachment uploads CSP-blocked — presign hands the browser a raw `*.supabase.co` PUT URL

## Overview

File upload in the Concierge chat fails in production: the tile renders the generic copy
"Upload failed. Check your connection and try again." (operator screenshot 2026-10-01,
`.md` chip on an in-progress conversation). The failure was reported as a regression from
PRs #9290 (accept `.md`/`.txt`) and #9315 (first-run ordering + presign hardening), both
merged 2026-09-30.

**Root cause (verified live, 2026-10-01):** `POST /api/attachments/presign` returns
`uploadUrl: data.signedUrl` — a URL minted by the service-role client against `SUPABASE_URL`
(`https://ifsccnjhymdmidffkzhl.supabase.co` in prd). The page CSP `connect-src` is built from
`NEXT_PUBLIC_SUPABASE_URL` (`https://api.soleur.ai`) and does not list `*.supabase.co`. The
browser's XHR PUT to the raw host is blocked by CSP before it leaves the page →
`xhr.onerror` → `Error("Upload to storage failed")` → `attachmentErrorCopy` generic
fallback. This is the same defect class fixed for *download* URLs by #5020
(`toPublicStorageUrl`); the *upload* URL was never rewritten.

**Why dev/tests never caught it:** in the `dev` Doppler config `SUPABASE_URL` and
`NEXT_PUBLIC_SUPABASE_URL` are the same host, so the rewrite is a no-op and the PUT's
origin always matches `connect-src`. Only prd splits them.

## Research Insights

### Premise Validation (Phase 0.6)

- PR #9290 verified MERGED 2026-09-30T15:43Z (`gh pr view 9290`); PR #9315 verified MERGED
  2026-09-30T20:36Z (`gh pr view 9315`). Both predate the failure window. Premise holds.
- All six cited files exist on this branch: `chat-input.tsx`, `lib/upload-attachments.ts`,
  `lib/upload-with-progress.ts`, `presign/route.ts`, `lib/attachment-constants.ts`,
  `lib/attachment-error-copy.ts`.
- The KEY DIAGNOSTIC FACT held: the generic copy only renders for non-code errors —
  verified in `lib/attachment-error-copy.ts` (`invalid_request`/`upload_failed` map to
  GENERIC; `unsupported_file_type`, `conversation_not_found`, `not_a_workspace_member`,
  `unauthorized`, `file_too_large` each have distinct copy).

### Property List (Phase 0.6b)

1. A browser PUT to the presigned upload URL must reach Supabase storage — i.e. the URL's
   origin must be inside the page's CSP `connect-src`.
2. The fix must not weaken CSP (no `*.supabase.co` wildcard re-widening — the narrowing
   was deliberate, #1281).
3. Every upload-path failure must reach Sentry with the stage that failed (presign vs
   storage PUT) — the Concierge path currently emits nothing.
4. `dev` and `prd` must exercise the same code path (no dev-only skip).

### Cut List (Phase 0.6b)

- **New URL-rewriting helper** → property 1 is already bought by `toPublicStorageUrl`
  (`lib/supabase/public-storage-url.ts`), deployed for exactly this defect class in
  `url/route.ts` and `workspace/[id]/logo/route.ts`. Reuse it.
- **Widening `connect-src` to `https://*.supabase.co`** → buys property 1 but violates
  property 2; rejected.
- **Client-side `uploadToSignedUrl(path, token)` via the anon client** → buys property 1 by
  routing through `NEXT_PUBLIC_SUPABASE_URL`, but rewrites the client contract (path+token
  instead of URL), duplicates token plumbing, and drops the XHR progress channel
  `uploadWithProgress` exists for. Rejected in favor of the server-side one-line rewrite.
- **Returning the resolved `contentType` to the client** → checked and unnecessary:
  `validateFiles` already canonicalizes the `File` (`new File([file], name, {type:
  resolved})`), so `file.type` is already the canonical type at presign and PUT time. The
  "raw browser type vs resolved type mismatch" hypothesis from the brief is **closed: not
  the defect**.

### Repo research (inline; no Task fan-out available in this context)

- `apps/web-platform/app/api/attachments/presign/route.ts:135` — `uploadUrl:
  data.signedUrl` raw. The fix site.
- `apps/web-platform/lib/supabase/public-storage-url.ts` — `toPublicStorageUrl()` rewrites
  origin to `NEXT_PUBLIC_SUPABASE_URL`; no-ops when unset or same host (dev-safe).
- `apps/web-platform/lib/csp.ts:99` — `connect-src 'self' <wss-app> https://<NEXT_PUBLIC
  host> wss://<host> <sentry> <push>`. No `*.supabase.co` in prod.
- Live verification (2026-10-01): `curl -sI https://app.soleur.ai/dashboard` → CSP
  `connect-src` lacks `*.supabase.co`; `doppler secrets get -c prd` → `SUPABASE_URL` =
  `https://ifsccnjhymdmidffkzhl.supabase.co`, `NEXT_PUBLIC_SUPABASE_URL` =
  `https://api.soleur.ai`; `dev` config has both equal.
- `apps/web-platform/components/chat/chat-input.tsx` `uploadAttachments` catch (≈:399) —
  sets `att.error` only; **no `console.warn`, no Sentry** → the Concierge path is a blind
  surface. `lib/upload-attachments.ts` (first-run path) reports but sanitizes to a fixed
  message (no status). The transport chokepoint `lib/upload-with-progress.ts` mints
  `"Upload to storage failed"` and is where the new status-bearing report lands.
- `apps/web-platform/lib/client-observability.ts` — `reportSilentFallback(err, {feature,
  op, extra})` is the client-side shim used by `first-run-send.ts`, `use-reconnect.ts`,
  `command-palette.tsx`.
- `apps/web-platform/test/presign-route.test.ts:185,369` — assert `uploadUrl` passthrough;
  must be updated/extended for the host rewrite.
- Storage SDK: `createSignedUploadUrl` returns `signedUrl` = `this.url + data.url` where
  `this.url` = `${SUPABASE_URL}/storage/v1` — raw host by construction. Token is
  host-agnostic (`url/route.ts` learning: both hosts route to the same project).
- `api.soleur.ai` answers `/storage/v1/` (curl → 404 from the Supabase edge), so the PUT
  endpoint is reachable on the public host.

### Institutional learnings applied

- `2026-05-20-test-stubs-env-and-csp-gates-miss-runtime-bugs.md` — CSP `connect-src`
  violations only fire in a real browser; stub/env tests cannot see them. This regression
  is exactly that class.
- `lib/supabase/public-storage-url.ts` doc-comment + `2026-06-08` learning — raw-host
  signed URLs reaching the browser are silently CSP-blocked; `curl` server-side succeeds.
- `cq-silent-fallback-must-mirror-to-sentry` — the composer catch swallows the error; the
  storage leg gets a status-bearing report at the `lib/upload-with-progress.ts`
  chokepoint (covers both callers), and the presign-leg gap is filed as #9345.
- `hr-observability-as-plan-quality-gate` + `2.9.2` blind-surface note — the plan adds the
  discriminating probe (`xhr.status` in the Sentry event) rather than fixing blind.
- `wg-ui-feature-requires-pen-wireframe` / deepen-plan 4.9 — kept `components/**` out of
  Files to Edit deliberately: a zero-visual-change telemetry edit would force a `.pen`
  artifact; the transport chokepoint covers the observed failure class and the residual
  gap is tracked, not silently dropped.

### Hypotheses evaluated

| Hypothesis | Evidence | Verdict |
|---|---|---|
| XHR PUT sends browser-raw `file.type` (`x-genesis-rom`/`""`) while storage expects resolved type | `validateFiles` returns `new File(…, {type: resolved})`; tile label "MD" confirms `file.type === "text/markdown"`; `createSignedUploadUrl` does not bind content-type; bucket has no `allowed_mime_types` | **Ruled out** |
| Concierge `conversationId` fails `CONVERSATION_ID_RE` | In-progress conversation id is a lowercase uuid (`conversations.id` is a uuid column); a 404 would render `conversation_not_found`'s own copy, not GENERIC | **Ruled out** |
| `invalid_request` (missing/mistyped field, e.g. `conversationId: null` after a session reset) | In-progress route always yields a string id; the `null` window exists only under `conversationId === "new"` | Possible but not the observed path |
| `upload_failed` 500 (lookup error / `createSignedUploadUrl` error) | Would emit Sentry server-side; no evidence it fires | Possible; telemetry + prod check cover it |
| "Presign failed" (non-JSON error body — route crash / proxy HTML) | No code change post-9315 introduces a throw; `verifiedUserId` fails closed to 401 | Possible; covered by same AC |
| **PUT blocked by CSP `connect-src`** (signedUrl on raw `*.supabase.co` host) | Confirmed live: prod env split + CSP header + unrewritten `uploadUrl` | **Primary root cause** |

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "PUT sends browser-raw `file.type`" | `validateFiles` canonicalizes the `File` at intake; both callers send the resolved type | No content-type change needed |
| "Regression began after 9290/9315" | The PUT-leg defect predates both PRs (presign never rewrote the host); `.md` support is what made the failure visible in real use | Fix the host rewrite; note the attribution caveat in PR body |
| Failure is observable in Sentry | `chat-input.tsx` catch emits nothing; `upload-attachments.ts` sanitizes to fixed text | Report at the `lib/upload-with-progress.ts` chokepoint (both callers); composer presign-leg gap → #9345 |

## Problem Statement / Motivation

Every browser attachment upload in production fails: the presign step succeeds (it runs
server-side), but the returned `uploadUrl` points at the raw `*.supabase.co` host that the
page's own CSP forbids, so the PUT dies client-side. The user sees generic copy, the agent
never receives the file, and nothing reaches Sentry from the Concierge path — so the
failure was invisible until a human reported the tile.

## Proposed Solution

1. **`presign/route.ts`:** `uploadUrl: toPublicStorageUrl(data.signedUrl)` + import.
   Mirrors #5020/`url/route.ts` and `logo/route.ts`. The signed token is host-agnostic; in
   dev (same host) the rewrite is a no-op.
2. **`lib/upload-with-progress.ts`:** report PUT failures via `reportSilentFallback` from
   `@/lib/client-observability` — `feature: "attachments"`, `op: "storage-put"`, extras
   `xhr.status` (0 = network/CSP block vs 4xx/5xx = storage rejected — the discriminating
   field for this defect class) and the sanitized filename. Never include `url` (it
   embeds the signed token — same sanitization posture as
   `lib/upload-attachments.ts` `sanitizeErrorForLog`). This is the single chokepoint that
   mints `"Upload to storage failed"`, so one instrument covers BOTH the composer
   (`chat-input.tsx`) and the first-run (`upload-attachments.ts`) paths. Note: on the
   first-run path a PUT failure now reports twice (transport + the existing sanitized
   `[kb-chat]` capture) — accepted noise; do not dedupe by weakening either.
3. **No client contract changes, no CSP changes, no new dependencies, no `components/**`
   edits.** The composer-catch presign-leg telemetry gap is deferred to issue #9345
   (`meta/machinery`): editing `chat-input.tsx` would trip the UI-surface `.pen` gate for
   a zero-visual-change edit; the chokepoint placement covers the observed failure class.

## Implementation Phases (TDD — failing test first, `cq-write-failing-tests-before`)

### Phase 1 — Failing tests

- `apps/web-platform/test/presign-route.test.ts`:
  - New case: stub `NEXT_PUBLIC_SUPABASE_URL` to a host different from the mock
    `signedUrl` host (e.g. `vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://api.soleur.ai")`
    vs signedUrl on `https://<ref>.supabase.co`) → assert `body.uploadUrl` host is the
    public host and the `?token=` query + path are preserved.
  - Update the existing passthrough assertions at ≈:185, ≈:369 to the rewritten host when
    env diverges (or set env so expectation is explicit).
- `apps/web-platform/test/upload-with-progress.test.ts` (new file — the module is mocked
  in `upload-attachments.test.ts`, so it needs its own suite): mock `XMLHttpRequest`;
  assert a non-2xx `onload` and an `onerror` both reject AND call
  `reportSilentFallback` once with `feature: "attachments"`, `op: "storage-put"`, and
  extras carrying `xhr.status` + sanitized filename; assert the reported error/extra
  contain no `token=` and no signed-URL substring.

### Phase 2 — Implementation (turn the tests green)

- `presign/route.ts`: `import { toPublicStorageUrl } from "@/lib/supabase/public-storage-url"`;
  `uploadUrl: toPublicStorageUrl(data.signedUrl)`.
- `lib/upload-with-progress.ts`: on `xhr.onload` non-2xx and `xhr.onerror`, call
  `reportSilentFallback(err, { feature: "attachments", op: "storage-put",
  extra: { status: xhr.status, filename: sanitizeAttachmentFilename(file.name) } })`
  before rejecting (`sanitizeAttachmentFilename` already exists in
  `lib/attachment-constants.ts` — reuse it, do not duplicate). Do not send on `onabort`
  ("Upload cancelled" is user-driven, not a failure signal).

### Phase 3 — Verification

- `npx vitest run test/presign-route.test.ts test/upload-with-progress.test.ts
  test/upload-attachments.test.ts test/chat-input-attachments.test.tsx
  test/attachment-error-copy.test.ts` green (run from `apps/web-platform`).
- Prod verification (post-deploy): attach a `.md` in an in-progress conversation → chip
  reaches "Uploaded" and the agent receives file contents. If a *different* generic-copy
  failure remains, the new Sentry events (`feature:attachments op:storage-put` with
  `status`) name the failing leg.

## Files to Edit

- `apps/web-platform/app/api/attachments/presign/route.ts` — return rewritten `uploadUrl`.
- `apps/web-platform/lib/upload-with-progress.ts` — Sentry report on PUT failure (status +
  sanitized filename, never the signed URL).
- `apps/web-platform/test/presign-route.test.ts` — rewrite assertions + new case.

(Also written by the pipeline, not product code: this plan file,
`knowledge-base/project/specs/fix-one-shot-attachment-upload-regression/tasks.md`,
`session-state.md`, and `knowledge-base/INDEX.md` if regenerated.)

## Files to Create

- `apps/web-platform/test/upload-with-progress.test.ts` — first suite for the module (it is
  mocked everywhere it is consumed today, so the XHR failure surface is untested).
- `knowledge-base/project/specs/fix-one-shot-attachment-upload-regression/tasks.md` —
  pipeline-owned.

## Technical Considerations

- **Security posture preserved:** CSP stays single-host; the rewrite moves the URL onto the
  already-trusted `api.soleur.ai` origin (a DNS-only CNAME to the same project — Supabase
  custom domain). The signed token authorizes the path, not the host.
- **Dev parity:** `toPublicStorageUrl` no-ops when `NEXT_PUBLIC_SUPABASE_URL` is unset or
  equal — dev behavior unchanged.
- **NFRs:** availability (user-facing upload path restored); observability (new Sentry
  signal). No schema/perf impact.
- **Sanitization contract:** the URL embeds a short-TTL signature; it must never reach
  Sentry/console (same rule as `sanitizeErrorForLog`).

## User-Brand Impact

- **If this lands broken, the user experiences:** attachment chips still failing with the
  generic toast and the agent silently receiving text-only messages (status quo — the fix
  cannot make it worse, only fail to cure it).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure —
  the PUT target is the same Supabase project behind the already-CSP-trusted public custom
  domain; no new data path, store, or third party.
- **Brand-survival threshold:** `none` — `threshold: none, reason: restores an existing
  upload surface by rewriting to the already-trusted public host; no new data path or
  privileged surface is introduced` (scope-out for the `app/api/` sensitive-path match).

## Observability

```yaml
liveness_signal:
  what: "Sentry issue stream for tag feature:attachments — absence of new
        op:storage-put events post-deploy is the success signal"
  cadence: "per-upload (event-driven)"
  alert_target: "Sentry issue alert (existing project alert rules)"
  configured_in: "apps/web-platform/lib/upload-with-progress.ts (new reportSilentFallback call)"

error_reporting:
  destination: "Sentry (browser SDK via lib/client-observability reportSilentFallback)"
  fail_loud: "attachment tile shows the user-facing copy AND a storage-put exception lands in Sentry"

failure_modes:
  - mode: "storage PUT rejected/CSP-blocked (the confirmed defect)"
    detection: "Sentry exception tagged feature:attachments op:storage-put; extra.status discriminates network/CSP (0) from storage reject (4xx/5xx)"
    alert_route: "Sentry issue alert"
  - mode: "server-side presign failure"
    detection: "existing route Sentry.captureException (feature:attachments op:presign / presign-lookup)"
    alert_route: "Sentry issue alert"
  - mode: "composer presign non-2xx/non-JSON (client leg still blind)"
    detection: "deferred — tracked in issue #9345"
    alert_route: "follow-up issue"

logs:
  where: "browser console via console.warn (first-run path already); Sentry for both paths post-fix"
  retention: "Sentry project retention"

discoverability_test:
  command: grep -c "toPublicStorageUrl" apps/web-platform/app/api/attachments/presign/route.ts
  expected_output: "2"
```

(Pre-merge the command exits 1/`1` — it is the post-fix probe; Check 10 runs it against
the merged tree where it prints `2`: the import plus the call site.)

## Acceptance Criteria

- [ ] AC1: `presign/route.ts` returns `uploadUrl` rewritten through `toPublicStorageUrl`
      (asserted by the new `presign-route.test.ts` case: signedUrl on
      `https://<ref>.supabase.co` + `NEXT_PUBLIC_SUPABASE_URL=https://api.soleur.ai` →
      `uploadUrl` host `api.soleur.ai`, `?token=` preserved).
- [ ] AC2: Dev/test parity — when `NEXT_PUBLIC_SUPABASE_URL` is unset (the vitest
      environment) or equals the signed-URL host (dev Doppler), `uploadUrl` is returned
      unchanged; the existing passthrough assertions at `presign-route.test.ts` ≈:185/:369
      remain green.
- [ ] AC3: `lib/upload-with-progress.ts` reports each storage-PUT failure to Sentry via
      `@/lib/client-observability` `reportSilentFallback` with `feature: "attachments"`,
      `op: "storage-put"`, and extras carrying `xhr.status` + sanitized filename; asserted
      payload contains no `token=` substring (new `test/upload-with-progress.test.ts`).
- [ ] AC4: `npx vitest run test/presign-route.test.ts
      test/upload-with-progress.test.ts test/chat-input-attachments.test.tsx
      test/upload-attachments.test.ts test/attachment-error-copy.test.ts` all green.
- [ ] AC5 (prod verify, operator-visible): attach a `.md` file in an in-progress Concierge
      conversation post-deploy → chip reaches `Uploaded`, no generic-copy toast, and the
      agent turn receives the file content.
- [ ] AC6: No CSP directive change (`git diff` on `lib/csp.ts` / `middleware.ts` is empty).

## Domain Review

**Domains relevant:** none

No cross-domain implications — server route + `lib/` instrumentation change on an
existing surface. No `components/**` file is edited (the telemetry lands at the
transport chokepoint in `lib/upload-with-progress.ts`), so the mechanical UI-surface
override does not fire and no `.pen` wireframe is owed. The deferred composer-catch
telemetry edit that WOULD have touched `components/chat/chat-input.tsx` is tracked in
issue #9345.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies contain no reference to any
of the four Files to Edit (checked 2026-10-01).

## Test Scenarios

- **Given** a prd-like env split (`SUPABASE_URL` raw host ≠ `NEXT_PUBLIC_SUPABASE_URL`),
  **when** presign returns, **then** `uploadUrl` carries the public host and the intact
  `?token=` — unit test.
- **Given** a staged `.md` (`file.type` canonicalized to `text/markdown`), **when** the PUT
  XHR errors, **then** `uploadWithProgress` rejects AND Sentry receives
  `feature:attachments op:storage-put` with `extra.status === 0` — unit test on the mocked
  XHR.
- **Given** a PUT returning HTTP 4xx/5xx, **when** `onload` fires, **then** rejection AND
  `op:storage-put` with `extra.status` = the code — unit test.
- **Regression:** Given the same env, when `url/route.ts` and `logo/route.ts` run, then
  their existing `toPublicStorageUrl` behavior is unchanged (no edits to those files).
- **Prod (post-deploy, browser):** attach `2026-08-06-skou….md` to an in-progress Concierge
  conversation → `Uploaded` state → agent sees contents. **API verify:**
  `curl -sI https://app.soleur.ai/dashboard | tr ';' '\n' | grep connect-src` still shows
  no `*.supabase.co` (CSP unchanged); the presign `uploadUrl` (observed in devtools or the
  new Sentry event absence) is on `api.soleur.ai`.

## Success Metrics

- Attachment upload succeeds in prd for `.md`/`.txt`/images/PDF on fresh and in-progress
  conversations (operator-visible).
- Any residual upload failure produces a stage-tagged Sentry event within one upload
  attempt — no more blind generic toasts.

## Dependencies & Risks

- **Risk: residual second defect.** If `upload_failed`/`invalid_request` is *also* firing
  in prd, AC5 will still fail — the new Sentry tags then identify it on the first attempt.
  Mitigation: telemetry ships in the same PR.
- **Risk: attribution.** The defect may predate 9290/9315 (`.md` support made it
  user-visible). PR body should state the CSP/rewrite mechanism rather than blame a PR.
- **Dependency:** none beyond the existing `toPublicStorageUrl` helper.
- **GDPR note (Phase 2.7 inline assessment):** the diff touches an API route (regulated
  surface), but adds no new processing activity, store, controller, or data category —
  it rewrites the destination host of an already-user-initiated upload to the same
  Supabase project. Advisory only; no Critical-class finding.

## References & Research

- Prior art for the identical defect class: `app/api/attachments/url/route.ts` (PR #5020),
  `app/api/workspace/[id]/logo/route.ts`, `lib/supabase/public-storage-url.ts`.
- Presign route: `apps/web-platform/app/api/attachments/presign/route.ts` (`uploadUrl:
  data.signedUrl` return).
- CSP builder: `apps/web-platform/lib/csp.ts` (`connect-src` construction).
- Prod env split verified via `doppler secrets get SUPABASE_URL NEXT_PUBLIC_SUPABASE_URL
  --project soleur --config prd` (2026-10-01).
- Merged PRs in the failure window: #9290, #9315.
- Screenshot: `/home/jean/Pictures/screenshot-2026-10-01_09-00-20.png`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6 — filled
  above.
- The `discoverability_test` command was executed once while writing this plan; pre-fix it
  prints `1` (import only after fix it prints `2` — import + call site). `expected_output`
  targets the post-merge tree, which is what preflight Check 10 executes.
- If implementation reveals the PUT-leg fix is *not* the whole story (e.g. Sentry shows
  `chat-upload-presign` events after the rewrite ships), do not widen scope silently —
  file a follow-up and name the new stage in the PR.
