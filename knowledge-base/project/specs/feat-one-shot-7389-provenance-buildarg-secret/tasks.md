# Tasks — #7389 SENTRY_AUTH_TOKEN in published build provenance

Plan: `knowledge-base/project/plans/2026-08-10-fix-sentry-token-in-build-provenance-plan.md`
Lane: `cross-domain` · Threshold: `single-user incident` (PROVISIONAL) · CPO: CHANGES REQUESTED → addressed

**Never print a secret value** anywhere — code, tests, CI output, PR body. Key names and value
lengths only. Fixtures are synthesized with non-alphanumeric placeholder wrappers.

## Phase 0 — Measure and decide topology (no code)

- [ ] 0.1 Local A/B canary build (`--provenance=mode=min` vs `mode=max`, `--build-arg CANARY=<<synthetic>>`,
      `--output type=oci`). Inspect both attestations. Needs no registry credential — the GHCR read
      PAT is revoked. Record key names + value LENGTHS only.
- [ ] 0.2 Pin the extractor; dedupe with `unique_by(.key)` (recursive descent double-counts across
      nesting depths) and make the `null` → `"null"` case explicit rather than a silent `value_len=4`.
- [ ] 0.3 Re-probe live scope: `GET https://jikigai-eu.sentry.io/api/0/` → `.auth.scopes`.
- [ ] 0.4 Verify mount contract: `required=true` honoured with no `# syntax=` directive (the `env=`
      form needs Dockerfile v1.10+, so the file form is mandatory); local build with
      `--secret id=sentry_auth_token,src=/dev/null` succeeds. Record answers into ADR-172.
- [ ] 0.5 **Decide token topology before any secret name is committed.** Split:
      `SENTRY_RELEASE_TOKEN` `[project:releases, org:read]` for the release build + `deploy-docs.yml`;
      `SENTRY_IAC_AUTH_TOKEN` at measured minimum for the Terraform/audit/sweeper/cron consumers.

## Phase 1 — Containment (pre-merge, standalone, same-day)

- [ ] 1.1 Enumerate consumers **by value**, not key name (compare last-4 + scope probe per distinct
      value across all Doppler configs and GitHub secrets; then grep `secrets\.` / `process.env.`).
- [ ] 1.2 Mint both replacements via the #5506 API path: `POST /api/0/sentry-apps/` (org-scoped
      collection is GET-only) then `POST /api/0/sentry-apps/<slug>/api-tokens/`. Probe for a live
      authenticated session first. Playwright UI is the fallback, not the primary.
- [ ] 1.3 If the mint blocks: narrow the existing integration's scopes in place (drop `project:admin`,
      `alerts:*`) as the fallback **terminating** action.
- [ ] 1.4 Repoint the six consumer workflows + the container cron to the split identities.
- [ ] 1.5 Capture the old value into a `_PREV` holding key **before** any overwrite; rollback is a
      named runbook step; delete the holding key only after 1.8.
- [ ] 1.6 Verify each consumer by **assertion**, not exit code (`deploy-docs.yml` exits 0 with a
      warning on auth failure). For non-dispatchable consumers, a direct scope probe is the accepted
      verification.
- [ ] 1.7 Probe the container-resident `cron-community-monitor` via `soleur:trigger-cron`; redeploy
      before revoking if the value is boot-time.
- [ ] 1.8 Revoke the leaked token. Record last-4 and the revocation timestamp.

## Phase 2 — RED tests first

- [ ] 2.1 `scripts/lint-buildarg-secret-channels.test.sh`; register in `scripts/test-all.sh` via
      `run_suite` (unregistered → `lint-orphan-test-suites.sh` fails, a CI job).
- [ ] 2.2 Source-sweep RED: `FOO_TOKEN=${{ secrets.BAR }}`; the name asymmetry;
      **`BUILD_DEPLOY_TOKEN`** and **`NEXT_PUBLIC_SECRET_KEY`** (conjunction cases); credential-shaped
      `ARG`; `LABEL`; `--build-arg` in a shell script; missing `BUILD_SHA=`; empty scan set.
- [ ] 2.3 Source-sweep GREEN: `NEXT_PUBLIC_X`; **`PATH`, `NODE_PATH`, `AUTHOR`, `NEXTAUTH_URL`,
      `CACHE_KEY`** (anchoring cases).
- [ ] 2.4 `--provenance` RED: synthetic value present; non-allowlisted key under any request prefix;
      unparseable input; either positive control missing. GREEN: allowlisted keys, no value.
- [ ] 2.5 Assert **per-case exit codes**, not "the suite fails" — the repo-baseline case is legitimately
      red at this phase, so a red suite proves nothing about the others being wired.

## Phase 3 — Dockerfile and workflow

- [ ] 3.1 Delete `ARG SENTRY_AUTH_TOKEN`; add
      `RUN --mount=type=secret,id=sentry_auth_token,required=true` reading `/run/secrets/…`. No
      `|| true`, no CI branch (the builder stage has no CI signal; `next.config.ts` already runs the
      Sentry plugin silent because `CI` is unset in a Docker build).
- [ ] 3.2 Check `RUN npm run build:server` does not also need the token.
- [ ] 3.3 Comment: local-build flag `--secret …,src=/dev/null`; cache-key consequence; why the mount
      not the ARG.
- [ ] 3.4 Workflow: remove build-arg; `secrets: | sentry_auth_token=${{ secrets.SENTRY_RELEASE_TOKEN }}`;
      pin `provenance: mode=min` **by value**; pin the BuildKit image via `driver-opts`; annotate
      `BUILD_SHA` as the positive control.
- [ ] 3.5 Rewrite the false-safety comment from the 0.1 measurement (two distinct `mode=min`s;
      stage-scoping confined to the gha cache; point at the scanner).

## Phase 4 — Gate and scanner

- [ ] 4.1 `scripts/buildarg-key-allowlist.txt` — single SSOT, prefix vs exact markers, drift test.
      **Conjunction**: credential-shaped keys rejected regardless of allowlist membership. Anchored
      regex `(^|_)(TOKEN|SECRET|KEY|PASSWORD|PASSWD|CREDENTIALS?|AUTH|PAT)($|_)|_DSN$`.
- [ ] 4.2 `scripts/lint-buildarg-secret-channels.py` — default source sweep (full repo; glob sets incl.
      `**/*.sh`, compose, `Containerfile*`; flag any non-allowlisted key **regardless of value
      expression**; assert any `push: true` build-push-action workflow invokes the gate; non-empty
      assertion per glob set).
- [ ] 4.3 `--provenance` mode: value-scan first (exit-status only); deny-by-default over the whole
      request-attribute map; **two fetches** (`.Provenance` and `.Image`) with **two positive
      controls** (`build-arg:BUILD_SHA`, and `BUILD_SHA` in `.config.Env`).
- [ ] 4.4 Emit three-valued `verdict` (`clean` / `could-not-inspect` / `violation`).
- [ ] 4.5 Wire the source sweep as a **pre-`docker_build`** step in the release job.
- [ ] 4.6 Wire the attestation gate **between `docker_build` and `Install cosign`**.
- [ ] 4.7 Break-glass modelled on `allow_unmirrored_reason` (recorded reason, not silent).
- [ ] 4.8 Amend `Email notification (release FAILED)` to carry the verdict with a value-conditional
      closing sentence — its current "re-running is safe" is dangerous on a violation.
- [ ] 4.9 Wire the sweep into `ci.yml`'s `credential-path-guard` job; **earn the bot green** by adding
      the reproduction to `action.yml`'s Phase-4 ceiling, add parity Test 9, and write the re-derived
      intersection into the `required-checks.txt` comment block.

## Phase 5 — Rule corpus

- [ ] 5.1 Pointer in `AGENTS.md`; body in `AGENTS.rules.md` (`hr-no-secret-in-buildarg-or-image-metadata`,
      `[scanner-enforced: …]`, ≤600 B, target ≤400 B — measured 394 B). `**Why:**` gets a clause.
- [ ] 5.2 Run `lint-agents-rule-budget.py`, `lint-rule-ids.py --index-file`, and `lint-rule-bodies.py`
      (a new id needs no hash regeneration and no ack).

## Phase 6 — Review pipeline and collateral

- [ ] 6.1 `security-sentinel` §5 dispatch entry (~3 lines).
- [ ] 6.2 No preflight Check 13, no new review agent.
- [ ] 6.3 Correct the false `event:read` 403 comments in `apply-web-platform-infra.yml` and
      `scripts/sentry-issue.sh`.
- [ ] 6.4 File the R7 issue against the gdpr-gate canonical regex; cite the number in the plan.

## Phase 7 — Legal record

- [ ] 7.1 `audits/2026-08-10-sentry-provenance-buildarg-disclosure.md` — audience citation, zot
      firewall evidence, Sentry audit log (read **and** write), window `2026-03-28 → revocation`,
      Art. 4(12) conclusion, Art. 33(5) discharge, and the evidence limit (GHCR exposes a principal
      set, not a read log).
- [ ] 7.2 Amend PA-8 §(g); **do not** mint PA-36; bump `last_reviewed`.
- [ ] 7.3 Active Item in `compliance-posture.md`; bump `last_updated`.
- [ ] 7.4 Record that user-facing communication was **considered and declined**, with the population
      evidence.
- [ ] 7.5 Update the re-minting section of `runbooks/sentry-issue-read.md` — do not create a new runbook.

## Exit

- [ ] `bash scripts/test-all.sh` in full (not a subset).
- [ ] All pre-merge ACs 1–18; post-merge ACs 19–25.
- [ ] `/ship` re-derives the ADR ordinal; sweep this file if it changes.
