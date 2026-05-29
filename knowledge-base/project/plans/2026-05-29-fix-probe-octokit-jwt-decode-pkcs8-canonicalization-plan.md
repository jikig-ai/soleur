---
title: "fix: probe-octokit App-JWT decode — canonicalize PEM to PKCS#8 before @octokit/app"
type: fix
date: 2026-05-29
branch: feat-one-shot-inngest-oauth-probe-jwt-decode
lane: cross-domain
brand_survival_threshold: none
sentry_ids:
  - 4e6a3003d19d47809616d521df3c795b  # cron-oauth-probe App-JWT decode (this PR's target), release 0.101.100
  - f3ad8fecf42645f691d67813a4f36cec  # same class, prior diagnostics-only PR #4568
prior_attempts:
  - c02cd36e  # PR #4568 — diagnostics + retry parity (did NOT root-cause; explicitly a "make it diagnosable" PR)
  - c43da45b  # PR #4565 — github-app.ts exp-margin + retry (sibling hand-rolled path, NOT the probe path)
---

# fix: probe-octokit App-JWT decode — canonicalize PEM to PKCS#8 before @octokit/app 🐛

## Overview

The OAuth-probe Inngest cron (`cron-oauth-probe`) fails in production with
`HttpError: A JSON web token could not be decoded - https://docs.github.com/rest`
(Sentry `4e6a3003d19d47809616d521df3c795b`, release `web-platform@0.101.100+c225980152`,
fired 2026-05-28 18:00 CEST). The throw originates inside `createProbeOctokit()`
(`apps/web-platform/server/github/probe-octokit.ts`) when it mints an App-level JWT via
`@octokit/app` and calls `GET /repos/{owner}/{repo}/installation`.

Two prior WIP attempts landed on `main` and did NOT resolve it:

- **PR #4568 (c02cd36e)** — added GitHub-error diagnostics (`ghStatus`/`ghRequestId`/`ghBody`/`clockSkewMs`)
  and 3-attempt retry parity to `probe-octokit.ts`. Its own plan states it "does NOT claim to
  root-cause the JWT decode failure — it makes it diagnosable." The error fired **after** it landed.
- **PR #4565 (c43da45b)** — widened the `exp` margin and added retry backoff to the **sibling**
  hand-rolled signer in `server/github-app.ts` (`createAppJwt`). That is a different code path
  (`crypto.createSign`, not `@octokit/app`) and a different Sentry issue (`8296c9a9…`). It never
  touched the probe path.

Neither addressed the actual signing path. **This PR root-causes the decode failure and fixes the
signing input**, rather than adding more diagnostics or shaving more margins.

## Research Reconciliation — Spec vs. Codebase

The task framing's leading hypothesis (PEM `\n`-normalization divergence between `probe-octokit.ts`
and `github-app.ts`) was **investigated and falsified** as the *sole* cause, but the investigation
surfaced the **true** root cause one layer deeper. Verified against the installed library source
(`universal-github-app-jwt@2.2.2`, fetched from the published tarball; the package is not vendored
into this worktree's `node_modules`).

| Claim (task framing) | Codebase / library reality (verified 2026-05-29) | Plan response |
| --- | --- | --- |
| `probe-octokit.ts` passes the RAW env value to `new App({ privateKey })`; `github-app.ts` normalizes `\\n` first | TRUE. `probe-octokit.ts:118-120` → `new App({ privateKey: readEnv(PRIVATE_KEY_ENV) })` (raw). `github-app.ts:104` → `raw.replace(/\\n/g, "\n")` before `createSign`. | Confirmed divergence, but see next row. |
| The `\\n`-escaping divergence is the root cause | **FALSE as sole cause.** `universal-github-app-jwt@2.2.2/index.js` ALREADY does `privateKey.replace(/\\n/g, '\n')` internally (verified in source). So escaped-`\n` env keys are handled by the lib. | Do NOT stop at `\n`-normalization; it is necessary but not the whole fix. |
| The lib normalizes the PEM so a decode failure must be expiry/clock-skew (prior PR #4568 framing) | **FALSE.** `"could not be decoded"` is GitHub's response to a **structural/signature** rejection, not expiry. The lib's signing path has two real fragilities (see Root Cause). | Fix the signing input shape, not the margins. |
| `@octokit/app` version | `@octokit/app@16.1.2` → `universal-github-app-jwt@2.2.2` (worktree `package-lock.json`). `@octokit/auth-app@8.2.0` also present. | Pin the analysis to 16.1.2 / 2.2.2. |
| `createProbeOctokit` is used only by `cron-oauth-probe` | **FALSE.** Also called by `cron-bug-fixer.ts` (4 sites), `_cron-shared.ts`, and referenced by `cron-roadmap-review.ts` / `cron-strategy-review.ts`. | Blast radius is ALL App-JWT-minting crons, not just the probe. The fix is in the shared factory → fixes all callers at once. |
| Test runner is `bun test` | FALSE. `package.json:"test": "vitest"`; `bunfig.toml [test] pathIgnorePatterns=["**"]` blocks bun discovery. | Test command: `./node_modules/.bin/vitest run <path>`. |
| Existing probe test to extend | `apps/web-platform/test/server/github/probe-octokit-retry.test.ts` (post-#4568: retry + diagnostics tests, `vi.mock("@octokit/app")`). | Extend it; add PEM-canonicalization tests. |

## Root Cause (verified against `universal-github-app-jwt@2.2.2` source)

`@octokit/app@16.1.2` mints its App JWT via `universal-github-app-jwt@2.2.2`. The Node signing path
(`lib/crypto-node.js` + `lib/get-token.js` + `lib/utils.js`) has **two structural fragilities** that
`server/github-app.ts`'s hand-rolled `crypto.createSign` path does NOT have:

1. **PKCS#8-only + brittle PEM→DER extraction.** `get-token.js` imports the key via Web Crypto
   `subtle.importKey("pkcs8", …)` and rejects PKCS#1 outright
   (`isPkcs1()` → `throw "Private Key is in PKCS#1 format, but only PKCS#8 is supported."`).
   For PKCS#1 input it first runs `convertPrivateKey()` →
   `crypto.createPrivateKey(pem).export({ type: "pkcs8", format: "pem" })`. The resulting PEM is then
   fed to `getDERfromPEM()`:

   ```js
   // universal-github-app-jwt@2.2.2/lib/utils.js
   export function getDERfromPEM(pem) {
     const pemB64 = pem.trim().split("\n").slice(1, -1).join("");  // ← fragile
     const decoded = atob(pemB64);
     return string2ArrayBuffer(decoded);
   }
   ```

   `slice(1, -1)` assumes **exactly one** header line and **exactly one** footer line, split on a
   bare `\n`. If the PEM carries `\r\n` line endings (common when a key is pasted into a Doppler/Docker
   env var on a Windows-authored secret, or copied through a CRLF-normalizing tool), every base64 body
   line retains a trailing `\r`. `atob()` on base64 containing `\r` yields **corrupted DER** (or throws),
   so `importKey`/`sign` produces a signature over a malformed key → GitHub returns
   **"A JSON web token could not be decoded."** `crypto.createSign` (the github-app.ts path) tolerates
   `\r\n` because Node's PEM parser strips whitespace; Web Crypto's hand-rolled `getDERfromPEM` does not.

2. **`btoa`/`atob` byte-mangling on non-Latin1 input is not the issue here, but `string2ArrayBuffer`
   uses `charCodeAt` (Latin1), so any non-ASCII contamination in the base64 body corrupts the DER
   silently.** A stray BOM or smart-quote from a copy-paste survives into the signed key.

**Why github-app.ts works on the same env var and probe-octokit.ts does not:** `github-app.ts:104`
does `raw.replace(/\\n/g, "\n")` AND uses `crypto.createSign(...).sign(getPrivateKey())`, where Node's
`createSign` accepts PKCS#1 *or* PKCS#8 and is whitespace-tolerant. The probe path delegates entirely
to the library's fragile Web-Crypto extraction.

**The fix:** canonicalize the PEM in OUR code before handing it to `new App()`, using the same
whitespace-tolerant Node primitive github-app.ts already trusts. `crypto.createPrivateKey(normalized)
.export({ type: "pkcs8", format: "pem" })` emits a **clean LF-only PKCS#8 PEM** (one header line, body
lines, one footer line, single trailing `\n`) that `getDERfromPEM`'s `slice(1, -1)` handles correctly
regardless of the input's original format (PKCS#1 or PKCS#8) or original line endings (CRLF or LF).
This is the minimal change that makes the signing input robust without forking the library.

## User-Brand Impact

**If this lands broken, the user experiences:** the App-JWT-minting crons (`cron-oauth-probe`,
`cron-bug-fixer`, `cron-roadmap-review`, `cron-strategy-review`, and `_cron-shared` consumers) cannot
authenticate to GitHub — the OAuth probe cannot file/close its `[ci/auth-broken]` tracking issue, and
the bug-fixer/roadmap/strategy crons cannot mint installation tokens. These are **platform-owned
synthetic/operator workflows**; no founder-facing flow calls `createProbeOctokit` (the founder GitHub
path is `createGitHubAppClient`, untouched here). The downstream risk is an operator blind spot: a real
prod auth outage goes unsurfaced because the probe's own GitHub auth is broken.

**If this leaks, the user's data is exposed via:** N/A. The change only canonicalizes a private-key PEM
*before* it enters `@octokit/app`; the PEM/JWT is never logged, captured, or materialized into any
`extra`/`tags` payload (preserved from #4568's diagnostic capture, which reads only GitHub-origin
`err.response`). The normalized PEM stays a local `const` passed straight into `new App()`.

**Brand-survival threshold:** `none`. Synthetic/operator platform traffic, no founder-data surface, no
regulated-data write. (Sensitive-path note: edits `apps/web-platform/server/github/probe-octokit.ts`
under `server/**` but introduces no schema/auth-route/PII change. `threshold: none, reason: probe and
sibling crons are platform-owned synthetic/operator traffic with no founder-data or regulated-data
surface.`)

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)

- [ ] Confirm the installed lib versions match the analysis:
      `grep -A2 '"node_modules/@octokit/app"' apps/web-platform/package-lock.json` → `16.1.2`;
      `grep -A2 '"node_modules/universal-github-app-jwt"' apps/web-platform/package-lock.json` → `2.2.2`.
      If either has drifted, re-verify the `getDERfromPEM`/`convertPrivateKey` source before proceeding
      (the fix is still correct — it just may be belt-and-suspenders if a later lib version hardened the
      extraction).
- [ ] Confirm the secret/JWT is never read into a logged/captured variable in the changed code:
      `grep -nE 'GITHUB_APP_PRIVATE_KEY|privateKey|appJwt|\bjwt\b' apps/web-platform/server/github/probe-octokit.ts`
      — the only references must be `readEnv(PRIVATE_KEY_ENV)` and the new local `const` passed to `new App()`.
- [ ] Enumerate all callers (blast radius) so the test plan covers the shared factory, not just the probe:
      `git grep -n 'createProbeOctokit\|createAppJwtOctokit' apps/web-platform --include='*.ts' | grep -v '\.test\.'`.
- [ ] Confirm test runner: `grep '"test"' apps/web-platform/package.json` → `vitest`; `bunfig.toml [test]
      pathIgnorePatterns=["**"]` blocks bun. Run the existing suite GREEN before edits:
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/github/probe-octokit-retry.test.ts`.
- [ ] Decide the helper's home: a small exported `normalizeAppPrivateKey(raw): string` in
      `probe-octokit.ts` (used by both `createProbeOctokit` and `createAppJwtOctokit`, which BOTH call
      `new App({ privateKey: readEnv(PRIVATE_KEY_ENV) })` at lines 119 and 194). Single normalization
      site fixes both factories in this file.

### Phase 1 — RED: failing tests for PEM canonicalization (cq-write-failing-tests-before)

Extend `apps/web-platform/test/server/github/probe-octokit-retry.test.ts` (or add a focused
`probe-octokit-pem.test.ts` if the retry file's `vi.mock("@octokit/app")` harness makes key-shape
assertions awkward — decide in Phase 0). The normalization is a pure string→string function, so test it
directly (no network, no `App` mock needed):

- [ ] **Test: a PKCS#1 PEM (`-----BEGIN RSA PRIVATE KEY-----`) is converted to PKCS#8
      (`-----BEGIN PRIVATE KEY-----`).** Generate a throwaway RSA keypair in the test via
      `crypto.generateKeyPairSync("rsa", { modulusLength: 2048, … })` exporting BOTH `pkcs1` and `pkcs8`
      PEMs (synthesized fixture, per `cq-test-fixtures-synthesized-only` — never a real key). Assert
      `normalizeAppPrivateKey(pkcs1Pem)` starts with `-----BEGIN PRIVATE KEY-----`.
- [ ] **Test: CRLF line endings are normalized to LF.** Take the synthesized PKCS#8 PEM, replace `\n`
      with `\r\n`, pass through `normalizeAppPrivateKey`, assert the result contains no `\r` and
      `getDERfromPEM`-style `result.trim().split("\n").slice(1,-1).join("")` round-trips to valid base64
      (assert `Buffer.from(body, "base64").length > 0` and `atob`-equivalent does not throw).
- [ ] **Test: escaped `\\n` (literal backslash-n) is expanded to real newlines.** Pass a single-line
      PEM with literal `\n` separators; assert the output has real line breaks and a valid header.
- [ ] **Test: an already-clean PKCS#8 LF PEM passes through unchanged (idempotent).**
      `normalizeAppPrivateKey(clean) === clean` (modulo a possible single trailing `\n` that
      `createPrivateKey().export()` emits — assert equality after `.trim()` on both sides if needed).
- [ ] **Test: an empty/whitespace env value throws the existing `readEnv` error** (preserve current
      behavior — do not swallow a missing secret).
- [ ] Run; confirm these FAIL (RED) against the current raw-passthrough code and the existing
      retry/diagnostics tests still pass.

### Phase 2 — GREEN: add `normalizeAppPrivateKey` and route both factories through it

Edit `apps/web-platform/server/github/probe-octokit.ts`:

- [ ] Add `import { createPrivateKey } from "crypto";` (matches `github-app.ts:12`'s import style).
- [ ] Add the helper (cite the root cause + the working sibling so the lineage is greppable):

      ```ts
      // Canonicalize the GitHub App private key to a clean LF-only PKCS#8 PEM
      // BEFORE handing it to @octokit/app. universal-github-app-jwt@2.2.2's
      // getDERfromPEM() does `pem.trim().split("\n").slice(1,-1).join("")` and
      // imports via Web Crypto `importKey("pkcs8", …)` — it rejects PKCS#1 and
      // produces corrupted DER from CRLF-laden PEMs, surfacing as GitHub's
      // "A JSON web token could not be decoded" (Sentry 4e6a3003…). Node's
      // createPrivateKey().export() is whitespace/format-tolerant (the same
      // primitive server/github-app.ts trusts via createSign) and emits exactly
      // the one-header / body / one-footer LF PEM that slice(1,-1) expects.
      export function normalizeAppPrivateKey(raw: string): string {
        const pem = raw.replace(/\\n/g, "\n");          // expand escaped \n (env/Doppler)
        return createPrivateKey(pem)                     // tolerant parse (PKCS#1 or #8, CRLF or LF)
          .export({ type: "pkcs8", format: "pem" })      // → clean LF PKCS#8
          .toString();
      }
      ```
- [ ] Replace BOTH `new App({ appId: readEnv(APP_ID_ENV), privateKey: readEnv(PRIVATE_KEY_ENV) })` sites
      (the `attempt()` closure at ~line 118 and `createAppJwtOctokit` at ~line 194) with
      `privateKey: normalizeAppPrivateKey(readEnv(PRIVATE_KEY_ENV))`.
- [ ] Run suite GREEN:
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/github/`.

### Phase 3 — REFACTOR + typecheck + scope guard

- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — confirm `createPrivateKey`'s
      `KeyObject.export(...)` return is typed (it returns `string | Buffer`; the `{format:"pem"}` overload
      returns `string`, but add `.toString()` defensively as above to satisfy the union).
- [ ] **Scope guard:** `git diff` must touch NEITHER `server/github-app.ts` `createAppJwt` margins NOR any
      `exp`/`iat` constant. This PR does not re-litigate the timing path (#4565 owns that). It also does
      not remove #4568's diagnostics/retry — those stay (they are now the *fallback* signal if a
      DIFFERENT decode cause appears post-fix).
- [ ] Re-run the full github test slice to confirm no sibling regressions:
      `./node_modules/.bin/vitest run test/server/github/`.

### Phase 4 — Runbook update (operator-facing self-diagnosis)

The runbook `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` documents the probe's
*public-auth-surface* failure modes but has NO entry for the probe's OWN App-JWT decode failure (the
class this PR fixes). Add one so the next operator who sees `4e6a3003…`-class events has a triage path.

- [ ] Add a `### probe_app_jwt_decode` (or similarly named) subsection documenting: symptom
      (`HttpError: A JSON web token could not be decoded` from `createProbeOctokit`), root cause
      (PKCS#1/CRLF PEM + universal-github-app-jwt Web-Crypto extraction), the fix shipped here, and a
      **non-SSH** verification recipe that reads the canonicalized key shape from Doppler without printing
      the secret, e.g.:

      ```bash
      # Confirm the Doppler prd key parses as a valid private key and what format it is in
      # (does NOT print the key material — only the type/format).
      doppler secrets get GITHUB_APP_PRIVATE_KEY -p soleur -c prd --plain \
        | node -e 'const k=require("crypto").createPrivateKey(require("fs").readFileSync(0,"utf8").replace(/\\n/g,"\n")); console.log(k.asymmetricKeyType, k.type)'
      # Expect: rsa private  — and the app now normalizes to PKCS#8 regardless.
      ```
- [ ] Cross-link the Sentry id `4e6a3003d19d47809616d521df3c795b` and this PR.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (PKCS#1 → PKCS#8):** `normalizeAppPrivateKey` converts a synthesized PKCS#1 PEM to a
      `-----BEGIN PRIVATE KEY-----` PKCS#8 PEM. Phase 1 test.
- [ ] **AC2 (CRLF → LF):** a CRLF-laden PEM round-trips to a `\r`-free PKCS#8 PEM whose body base64
      decodes without error. Phase 1 test.
- [ ] **AC3 (escaped `\\n`):** a literal-`\n` env-shaped key expands to real newlines and parses. Phase 1 test.
- [ ] **AC4 (idempotent):** a clean PKCS#8 LF PEM passes through unchanged (modulo trailing newline). Phase 1 test.
- [ ] **AC5 (both factories routed):** `grep -nE 'new App\(' apps/web-platform/server/github/probe-octokit.ts`
      shows EVERY `privateKey:` arg wrapped in `normalizeAppPrivateKey(...)` — no raw `readEnv(PRIVATE_KEY_ENV)`
      reaches `new App()`.
- [ ] **AC6 (no secret leak):** `normalizeAppPrivateKey`'s output is only assigned to a local `const`
      passed to `new App()`; never logged or placed in any `extra`/`tags`. Manual + grep.
- [ ] **AC7 (scope guard — no margin change):** `git diff` touches neither `server/github-app.ts`
      `createAppJwt` margins nor any `exp`/`iat` constant, and does NOT delete #4568's diagnostics/retry.
- [ ] **AC8 (suite + typecheck green):**
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/github/` passes;
      `./node_modules/.bin/tsc --noEmit` clean.
- [ ] **AC9 (runbook entry):** `oauth-probe-failure.md` contains a `probe_app_jwt_decode`-class
      subsection with a non-SSH verification recipe (the AC verification grep:
      `grep -c 'A JSON web token could not be decoded' knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md`
      returns ≥1).

### Post-merge (operator)

- [ ] **AC10 (probe recovers):** after deploy, trigger `inngest send cron/oauth-probe.manual-trigger` and
      confirm the run completes without the `could not be decoded` throw. Verify the
      `scheduled-oauth-probe` Sentry monitor records a `?status=ok` check-in via the checkins API
      (recipe already in the runbook). **Automation:** `inngest send` + Sentry checkins `curl` are both
      scriptable — no SSH, no dashboard-watching.
- [ ] **AC11 (class quiets):** the `4e6a3003…`-class Sentry issue stops accruing new events post-deploy
      (query the issue's events with `statsPeriod=24h` after the next probe cron tick). If it recurs,
      #4568's diagnostic `extra` (`ghStatus`/`ghRequestId`/`ghBody`/`clockSkewMs`) now points at a
      DIFFERENT cause — file a follow-up with that evidence.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — server-side bug fix on platform-owned synthetic/operator
GitHub-auth plumbing. No user-facing surface, no schema/migration, no pricing/legal/marketing impact.

## Observability

```yaml
liveness_signal:
  what: cron-oauth-probe Sentry cron monitor ("scheduled-oauth-probe") heartbeat
  cadence: hourly (cron "0 * * * *")
  alert_target: Sentry cron monitor (sentry_cron_monitor.scheduled_oauth_probe) — pages on missed check-in
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf
error_reporting:
  destination: Sentry (via reportSilentFallback in cron-oauth-probe.ts terminal catch + warnSilentFallback in createProbeOctokit, both already wired by PR #4568)
  fail_loud: yes — the throw surfaces as a Sentry error event with feature=cron-oauth-probe; the monitor pages on missed ?status=ok check-in
failure_modes:
  - mode: App-JWT structurally rejected by GitHub ("could not be decoded")
    detection: Sentry issue 4e6a3003… events; createProbeOctokit warnSilentFallback breadcrumb with ghStatus/ghRequestId (PR #4568)
    alert_route: Sentry cron monitor missed-check-in alert → operator
  - mode: PKCS#1 or OpenSSH key rejected by universal-github-app-jwt before signing
    detection: thrown Error message contains "only PKCS#8 is supported" — now pre-empted by normalizeAppPrivateKey converting to PKCS#8
    alert_route: same Sentry path; should be eliminated by this fix
  - mode: missing/empty GITHUB_APP_PRIVATE_KEY secret
    detection: readEnv throws "GITHUB_APP_PRIVATE_KEY is unset" (unchanged behavior)
    alert_route: Sentry error event + missed check-in
logs:
  where: Sentry (errors + breadcrumbs); self-hosted Inngest worker journal on Hetzner (journalctl -u inngest-server.service) for run timeline
  retention: Sentry default project retention
discoverability_test:
  command: "inngest send cron/oauth-probe.manual-trigger && curl -s -H \"Authorization: Bearer $SENTRY_AUTH_TOKEN\" \"https://de.sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-oauth-probe/checkins/?limit=1\" | jq -r '.[0].status'"
  expected_output: "ok"
```

## Open Code-Review Overlap

None — checked against the `## Files to Edit` list below (no open code-review issue names
`probe-octokit.ts` or `oauth-probe-failure.md`). Re-run at Step 1.7.5 if the file list grows.

## Files to Edit

- `apps/web-platform/server/github/probe-octokit.ts` — add `normalizeAppPrivateKey`; route both
  `new App({ privateKey })` sites through it; add `createPrivateKey` import.
- `apps/web-platform/test/server/github/probe-octokit-retry.test.ts` (or new
  `probe-octokit-pem.test.ts`) — synthesized-keypair canonicalization tests (RED → GREEN).
- `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` — add `probe_app_jwt_decode` failure
  mode + non-SSH verification recipe.

## Files to Create

- (optional) `apps/web-platform/test/server/github/probe-octokit-pem.test.ts` — only if the existing
  retry file's `@octokit/app` mock harness makes pure-function key tests awkward.

## Non-Goals / Deferred

- **Touching `server/github-app.ts` / `createAppJwt` margins or timing.** Owned by PR #4565
  (sibling Sentry `8296c9a9…`). Out of scope.
- **Widening JWT `exp`/`iat` margins on any path.** Wrong failure class — this is a structural
  signing-input bug, not expiry.
- **Removing #4568's diagnostics or retry loop.** They stay as the fallback signal if a different
  decode cause appears after this fix lands (AC11).
- **Forking / patching `universal-github-app-jwt`.** The canonicalization-before-handoff approach makes
  the library's fragile extraction a non-issue without owning a fork. If a future lib version hardens
  `getDERfromPEM`, this helper is harmless belt-and-suspenders.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or
  omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled with
  threshold `none` + reason.)
- The fix's correctness depends on `crypto.createPrivateKey(pem).export({type:"pkcs8",format:"pem"})`
  emitting LF-only output with exactly one header and one footer line. This is Node's documented behavior,
  but the Phase 1 CRLF test is the load-bearing proof — do not skip it.
- `KeyObject.export({format:"pem"})` returns `string`, but the broad `export()` signature is
  `string | Buffer`; keep the `.toString()` so `tsc` is happy and the helper's return type is `string`.
- Synthesized keypairs ONLY in tests (`crypto.generateKeyPairSync`), never a real or real-shaped
  GitHub App key (`cq-test-fixtures-synthesized-only`).
