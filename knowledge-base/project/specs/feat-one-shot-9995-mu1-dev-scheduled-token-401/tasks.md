<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Rationale — inherits the plan's ## Infrastructure (IaC) verdict: a
doppler_secret TF resource would write the App private key into
terraform.tfstate (branch-readable per ADR-241 D3/D4), the exact exposure
#8609's operator-hand precedent exists to avoid; GitHub App keys are
minted provider-side and stored via the sanctioned Doppler CLI path. -->

# Tasks — fix: MU1 AC-2 dev_scheduled GitHub App credential repair + shape audit

Plan: `knowledge-base/project/plans/2026-10-11-fix-mu1-ac2-dev-scheduled-github-app-credential-plan.md`
Issue: #9995 · Tracker: #9993 · Draft PR: #10038 · Branch: feat-one-shot-9995-mu1-dev-scheduled-token-401

Secret discipline (applies to every task): NEVER print secret values — shape
ops only (`wc -c`, `sha256sum` fingerprints, `openssl` parse). Every
`doppler secrets` write call redirects stdout to `/dev/null`. PEM lives on
`$XDG_RUNTIME_DIR` tmpfs under `umask 077`, deleted after read-back
fingerprint match.

## Phase 1 — Fixture App provisioning (consent gates G1–G3 + agent automation)

- [ ] 1.1 Write `apps/web-platform/infra/github-ci-fixture-app-manifest.json`
      (minimal manifest: name "Soleur CI Fixture"; `url`; description
      citing #9995 + O1b rationale; `public: false`;
      `default_permissions: {contents: read, metadata: read}`;
      `default_events: []`; NO `redirect_url`/`hook_attributes` — no
      OAuth/webhook surface).
- [ ] 1.2 Render the manifest-POST page locally and open via Playwright;
      consent gate G1 (OAuth-consent class) submits GitHub's Create
      GitHub App form.
- [ ] 1.3 Playwright to the App settings page; attempt private-key
      generation via Playwright FIRST (G2 is `automation-status:
      UNVERIFIED` — attempt required before any operator handoff); PEM
      downloads to tmpfs.
- [ ] 1.4 Playwright to
      `https://github.com/apps/soleur-ci-fixture/installations/new`;
      consent gate G3 (org-admin) installs on `jikig-ai/mu1-fixture`
      only.
- [ ] 1.5 Read ids (numbers only): `gh api apps/soleur-ci-fixture --jq .id`
      and `gh api repos/jikig-ai/mu1-fixture/installation --jq .id`.
- [ ] 1.6 Pipe `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY` (from tmpfs),
      `MU1_FIXTURE_INSTALLATION_ID` into `soleur/dev_scheduled` via
      `doppler secrets set --silent` with stdout redirected to
      `/dev/null`; verify read-back fingerprint matches the download;
      then delete the PEM.
- [ ] 1.7 Record byte count + sha256[:8] fingerprint + app id +
      installation id in `credential-evidence.md` (spec dir) and as a
      #9995 comment.

## Phase 2 — Mint-liveness canary (RED drill → workflow step)

- [ ] 2.1 Write `scripts/probe-github-app-mint.sh` (bash + openssl + curl;
      signs JWT from `GITHUB_APP_ID`+`GITHUB_APP_PRIVATE_KEY` env, calls
      `GET /app`, prints `GITHUB_APP_MINT status=… slug=… fp=…` or
      `::error::` + exit 1; never prints key/JWT; portable — no
      GNU-only flags, repo timeout→gtimeout→bare pattern if needed) and
      `scripts/probe-github-app-mint.test.sh` covering Guard-1 matrix
      rows 1–5. Required shapes (deepen-pass traps): curl
      `--header @<(printf 'Authorization: Bearer %s' "$JWT")` — `gh api`
      sends `token`, never `Bearer`; `b64url()` =
      `openssl base64 -A | tr '+/' '-_' | tr -d '=\n'` (NOT `base64 -w
      0` — GNU-only); `openssl rsa -check` pre-flight on the PEM;
      PEM only to `mktemp` under `umask 077` in `$RUNNER_TEMP`.
- [ ] 2.2 RED drill: run the probe under `doppler run -p soleur -c
      dev_scheduled` BEFORE the credential swap — expect exit 1 with fp
      `8246898e` (matches the CI pemFingerprint).
- [ ] 2.3 Edit `.github/workflows/scheduled-integration-suites.yml`:
      inside `Run MU1_INTEGRATION suites` (id `mu1`, ~line 292), invoke
      the probe under the same `doppler run -p soleur -c dev_scheduled`
      before the vitest call; refresh the step comment to name the
      `soleur-ci-fixture` App.
- [ ] 2.4 GREEN check after 1.6: probe prints `status=200
      slug=soleur-ci-fixture` under dev_scheduled.
- [ ] 2.5 Edit the header comment in
      `apps/web-platform/test/mu1.integration.test.ts` to name the
      fixture App (behavior unchanged; `dev`'s documented-expected 401
      stays accurate).

## Phase 3 — dev_scheduled credential-shape audit

- [ ] 3.1 Write `scripts/audit-dev-scheduled-shapes.sh` (census via
      `doppler secrets --only-names -p soleur -c dev_scheduled`; shape
      classes: PEM-parse, URL-scheme, numeric-id, token class = RFC 6750
      b64token alphabet `[A-Za-z0-9._~+/=-]` + zero CR/control bytes —
      property guard, NOT a vendor-format prefix (the #9972 lesson);
      per-name verdict line, never values; nonzero exit on FAIL;
      fail-closed on empty/unreadable census) and
      `scripts/audit-dev-scheduled-shapes.test.sh` covering Guard-2
      matrix rows — the test MUST assemble any swept literal split so it
      doesn't join its own sweep population.
- [ ] 3.2 Run the audit; post the name→verdict table to #9995 (values
      never included).
- [ ] 3.3 File a follow-up issue per non-GITHUB_APP FAIL
      (`--milestone "Post-MVP / Later"`, label `ci/integration-suites`);
      record the `dev` config dead-key observation in the #9995 comment
      (no change — plan Cut List).

## Phase 4 — Docs + verification dispatch

- [ ] 4.1 Update
      `knowledge-base/engineering/operations/runbooks/mu1-signup-workspace-verification.md`
      (AC-2 evidence row: fixture App + mint probe).
- [ ] 4.2 `gh workflow run scheduled-integration-suites.yml --ref
      feat-one-shot-9995-mu1-dev-scheduled-token-401`; arm a Monitor in
      the same turn (hr-dispatch-async-must-arm-watch); assert `mu1`
      step outcome `success`.
- [ ] 4.3 Post-merge: `gh workflow run scheduled-integration-suites.yml`
      on main — mu1 leg green (issue's AC).
- [ ] 4.4 PR body carries `Closes #9995` (ship renders the durable
      artifacts; do not hand-author PR-body blocks — ship is the sole
      PR-body author).

## Done definition

All `### Pre-merge (PR)` Acceptance Criteria in the plan ticked; the mu1
leg is green on a branch dispatch; #9995 carries the forensic +
credential-evidence comments.
