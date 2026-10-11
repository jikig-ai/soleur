<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Rationale — inherits the plan's ## Infrastructure (IaC) verdict: a
doppler_secret TF resource would write the App private key into
terraform.tfstate (branch-readable per ADR-241 D3/D4), the exact exposure
#8609's operator-hand precedent exists to avoid; GitHub App keys are
minted provider-side and stored via the sanctioned Doppler CLI path. -->

# Tasks — fix: MU1 AC-2 dev_scheduled GitHub App credential repair + shape audit

Plan: `knowledge-base/project/plans/2026-10-11-fix-mu1-ac2-dev-scheduled-github-app-credential-plan.md`
Issue: #9995 · Tracker: #9993 · Draft PR: #10038 · Branch: feat-one-shot-9995-mu1-dev-scheduled-token-401
Deferred provisioning track: #10058 (bootstrap.sh staged run — founder clicks G1–G3)

Secret discipline (applies to every task): NEVER print secret values — shape
ops only (`wc -c`, `sha256sum` fingerprints, `openssl` parse). Every
`doppler secrets` write call redirects stdout to `/dev/null`. PEM lives on
`$XDG_RUNTIME_DIR` tmpfs under `umask 077`, deleted after read-back
fingerprint match.

## Phase 1 — Fixture App provisioning (consent gates G1–G3 + agent automation)

- [x] 1.1 Write `apps/web-platform/infra/github-ci-fixture-app-manifest.json`
      (minimal manifest: name "Soleur CI Fixture"; `url`; description
      citing #9995 + O1b rationale; `public: false`;
      `default_permissions: {contents: read, metadata: read}`;
      `default_events: []`; NO `redirect_url`/`hook_attributes` — no
      OAuth/webhook surface). DONE 2026-10-11.
- [ ] 1.2–1.7 (browser click G1 create → G2 keygen → G3 install → ids →
      Doppler writes → evidence): **DEFERRED to #10058** at the
      operator's instruction — playwright-attempt documented (playwright-mcp
      unreachable; agent-browser reached `github.com/login` = credential-entry
      gate). Staged via `bootstrap.sh` in this spec dir: preflight →
      create-app → record-key → install-app → write-doppler → verify.
      `app-manifest-post.html` (in this dir) is the manifest-POST launcher
      the create-app stage opens.

## Phase 2 — Mint-liveness canary (RED drill → workflow step)

- [x] 2.1 `scripts/probe-github-app-mint.sh` + `scripts/probe-github-app-mint.test.sh`
      (27 rows, Guard-1 matrix 1–5 + missing/non-numeric env + garbage PEM +
      xtrace refusal). DONE 2026-10-11. **Plan-drift note:** the plan's inline
      `curl --header @<(printf 'Authorization: Bearer %s' "$JWT")` was
      superseded by ADR-280 — the probe sources `scripts/lib/bearer-curl.sh`
      and the JWT rides curl's stdin config (`bc_curl`), never argv.
      b64url = `openssl base64 -A | tr '+/' '-_' | tr -d '=\n'` (portable);
      `openssl rsa -check`/`pkey -check` pre-flight; PEM only to `mktemp`
      under `umask 077`; env-form sha256[:8] fp matches CI's pemFingerprint.
- [x] 2.2 RED drill: `doppler run -p soleur -c dev_scheduled -- bash
      scripts/probe-github-app-mint.sh` → `::error::GITHUB_APP_* cannot mint
      a valid JWT for app 3261325 (status=401 curl_rc=0 fp=8246898e)`,
      exit 1 — fingerprint matches the CI log's pemFingerprint exactly.
      DONE 2026-10-11.
- [x] 2.3 `.github/workflows/scheduled-integration-suites.yml` `mu1` step:
      probe invoked under the same `doppler run -p soleur -c dev_scheduled`
      before vitest (`../scripts/probe-github-app-mint.sh` — the step's
      working-directory is apps/web-platform); comment names the
      `soleur-ci-fixture` App. DONE 2026-10-11.
- [ ] 2.4 GREEN check (`status=200 slug=soleur-ci-fixture`): DEFERRED to
      #10058 — blocked on Phase 1 provisioning. The `verify` stage of
      bootstrap.sh performs it.
- [x] 2.5 `apps/web-platform/test/mu1.integration.test.ts` header comment
      names the fixture App + probe; the `dev`-config documented-expected
      401 text preserved. DONE 2026-10-11.

## Phase 3 — dev_scheduled credential-shape audit

- [x] 3.1 `scripts/audit-dev-scheduled-shapes.sh` +
      `scripts/audit-dev-scheduled-shapes.test.sh` (32 rows, Guard-2 matrix +
      envelope/non-object/fetch-failure arms). Token class = RFC 6750
      alphabet, property guard only. Pem class accepts PEM-parse OR
      alphabet-clean bare key blob (VAPID keys are un-PEM'd base64url —
      first-run false positive corrected). DONE 2026-10-11.
- [x] 3.2 Live run: `AUDIT_SUMMARY checked=60 ok=30 fail=0 unclassified=30`
      — posted to #9995. `GITHUB_APP_PRIVATE_KEY` verdict `ok` (valid PEM,
      unregistered — liveness is the probe's layer). DONE 2026-10-11.
- [x] 3.3 Zero non-GITHUB_APP FAILs → no follow-up issues filed. The `dev`
      dead-key observation is recorded in the #9995 comment (dev's copy is
      byte-identical, fp 8246898e; left unchanged per plan Cut List).
      DONE 2026-10-11.

## Phase 4 — Docs + verification dispatch

- [x] 4.1 `mu1-signup-workspace-verification.md`: AC-2 evidence row names
      `soleur-ci-fixture` + the mint probe; the security-baseline section
      documents the dev/dev_scheduled credential split. DONE 2026-10-11.
- [ ] 4.2 Branch dispatch of `Scheduled: integration suites` — expected RED
      at the probe (proves fail-fast + named error in CI context) until
      #10058 closes; assert probe output names the 401, not vitest.
- [ ] 4.3 Post-merge main dispatch — mu1 leg stays RED at probe until
      #10058 closes (deferred); GREEN assertion belongs to #10058's
      closure check.
- [x] 4.4 PR body: `Refs #9995` + `Tracks #10058` — NOT `Closes #9995`
      (the live credential is not provisioned; the issue's AC is a green
      mu1 leg, which needs the deferred clicks). ship authors the body.

## Done definition (revised for the deferral)

Probe + audit + manifest + workflow wiring merged; #10058 filed as the
deferred-automation track with the staged bootstrap.sh; mu1's named-failure
probe demonstrated. The issue's leg-green AC moves to #10058's closure.
