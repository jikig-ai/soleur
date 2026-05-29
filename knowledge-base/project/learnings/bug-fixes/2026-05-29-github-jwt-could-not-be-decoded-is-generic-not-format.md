# Learning: GitHub's "A JSON web token could not be decoded" is a GENERIC rejection — not a format diagnosis

## Problem

The `cron-oauth-probe` Inngest function threw
`HttpError: A JSON web token could not be decoded - https://docs.github.com/rest`
(Sentry `00bdfdf1543c472e91552d45565f1e74`) on every hourly run, surviving **six
prior fixes** across PRs #4498 / #4513 / #4565 (retry-on-401 + exp-margin) and
#4569 (PKCS#8 / CRLF key normalization). Each fix guessed a *mechanism* (key
format, transient 401, clock skew) and patched it; the next run disproved it.

## Root Cause

Two distinct defects in Doppler `prd`, neither of which any format/retry fix
could touch:

1. **`GITHUB_APP_PRIVATE_KEY` did not match GitHub App `soleur-ai` (id 3261325).**
   The key was a structurally-valid 2048-bit RSA key (so `createPrivateKey`
   succeeded and every format fix "passed") but its public half was not
   registered for the App — GitHub rejected every signature.
2. **`GITHUB_APP_ID` was `"3261325\n"`** — the correct numeric ID with a trailing
   newline. No code path (`readEnv`, `getAppId`) trimmed it before signing it
   into the JWT `iss`.

## Key Insight

**GitHub returns `"A JSON web token could not be decoded"` for EVERY JWT it
cannot validate** — corrupt signature, key↔App mismatch, unknown/malformed
`iss`, AND a mangled-PEM signature all produce the identical string. Verified
empirically: four oracle variants (correct trimmed `iss`, untrimmed `iss`,
deliberately-wrong `iss=999999`, deliberately-corrupt signature) all returned
the same message. **The error text tells you nothing about which layer failed.**

The decisive signals are NOT the message:
- **`ghStatus: 401` + `attempts: 3`** in the `#4568` breadcrumb (`extra`) → GitHub
  *received and rejected* the JWT, and it *persisted across retries*. A transient
  JWT-replication 401 clears on retry; a persistent one means the credential is
  wrong. This single read disproves both the retry-widening and format theories.
- **`GET /app` via the immune hand-rolled signer** (the cheapest credential
  oracle) → 200 + `{id}` means credentials are sound; 401 means the key↔App pair
  is wrong. Use it BEFORE re-minting anything — re-rotating a *correct* secret
  only extends MTTR.
- **Public `GET /apps/{slug}`** (no auth) returns the App's true numeric ID, so
  you can verify `GITHUB_APP_ID` independently of GitHub's opaque JWT error.

**Generalizable rule:** when a fix recurs ≥2 times, stop guessing mechanisms.
The diagnostic evidence is usually already captured (here: the breadcrumb added
by #4568 sat unread on the Sentry event). Pull the evidence FIRST; ship exactly
one targeted fix the evidence selects.

## Solution

- Added a shared `readAppId()` guard (`apps/web-platform/server/github/app-private-key.ts`,
  sibling to `normalizeAppPrivateKey`): trims surrounding whitespace (recoverable)
  and throws a loud, self-explaining error for a non-numeric / client_id-shaped
  value (the unrecoverable confusion class), converting GitHub's opaque error into
  a cause-naming one. Routed through all five issuer sites (`createProbeOctokit`,
  `createAppJwtOctokit`, `createGitHubAppClient`, and the hand-rolled
  `github-app.ts getAppId()`).
- Corrected `oauth-probe-failure.md`: #4569 was "necessary but insufficient" (the
  error recurred on a release provably containing it via `git merge-base`); added
  the decisive evidence recipes (event-by-ID Sentry fetch, App-ID shape check,
  `GET /app` oracle, public App-ID lookup).
- Operator follow-up (post-merge, consent-gated): re-mint the `soleur-ai` private
  key and strip the `GITHUB_APP_ID` newline in Doppler `prd`.

## Session Errors

1. **Plan cited source paths without the `server/github/` subdir** (`probe-octokit.ts`
   etc. were at `server/github/`, not `server/`). — Recovery: `git ls-files | grep`.
   — Prevention: already covered by `hr-when-a-plan-specifies-relative-paths` (plan
   is authoritative for intent, never paths); verify at /work start.
2. **Sentry `/api/0/issues/<id>/events/latest/` returned "permission denied"** — the
   32-hex ID from the Sentry email is an EVENT id, not a numeric issue group. —
   Recovery: project-scoped `/api/0/projects/{org}/{project}/events/{event-id}/`. —
   Prevention: documented in `oauth-probe-failure.md` STEP 1 ("the 32-hex is the
   EVENT id, not a numeric issue group").
3. **`/tmp/sentry-event.json` clobbered by a project-detection loop's 2nd iteration**
   (the `soleur-www` "Project does not exist" body overwrote the good payload). —
   Recovery: re-fetched to a distinct stable file. — Prevention: never reuse one
   output filename across loop iterations that each write it.
4. **`TaskCreate` called without its schema loaded** → `InputValidationError`. —
   Recovery: skipped the Task tool, tracked progress inline. — Prevention: run
   `ToolSearch select:<name>` before invoking any deferred tool.
5. **CWD drift** — after `cd apps/web-platform` for the test runner, a relative
   runbook path failed (`No such file or directory`). — Recovery: absolute path. —
   Prevention: already documented; chain `cd <abs> && <cmd>` in a single Bash call.
6. **`app-client.test.ts` fixtures `"first"/"second"` broke** once `readAppId`
   validated before `new App()`. — Recovery: numeric `"1001"/"2002"` (intent
   preserved). — Prevention: anticipated by `2026-05-29-credential-parsing-before-mocked-sdk-breaks-stub-key-fixtures`
   (real validation before a mocked boundary breaks stub fixtures — sweep them).
7. **Review false-positive HIGH** — `code-quality-analyst` claimed the runbook jq
   recipe reads wrong paths (`.context.extra.X`, `.release` string), reasoning from
   the SDK *emission* path without fetching the live payload. The events-detail REST
   API flattens `extra` into `.context` and returns `release` as an object. —
   Recovery: empirically re-ran both jq forms against the real event JSON and
   dismissed. — Prevention: already covered by the review Sharp Edge ("verify
   recipe-failure claims against the real artifact; single-agent HIGH unconfirmed by
   orthogonal agents → dismiss"). Reviewer takeaway when an agent reasons about an
   API payload shape: fetch one real response before rating P1.

## Tags
category: bug-fixes
module: github-app-auth
related_prs: [4498, 4513, 4565, 4568, 4569]
sentry_issue: 00bdfdf1543c472e91552d45565f1e74
