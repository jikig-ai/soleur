---
title: "fix: Make RLS fuzz Supabase image pulls resilient to GHCR throttling"
type: fix
date: 2026-10-27
slug: fix-rls-fuzz-ghcr-throttle
branch: feat-one-shot-10868-rls-fuzz-ghcr-throttle
issue: 10868
closes: 10868
lane: cross-domain
---

# fix: Make RLS fuzz Supabase image pulls resilient to GHCR throttling

## Overview

The `rls-fuzz` job in `.github/workflows/rls-authz-fuzz.yml` fails before its test suite starts when GHCR rate-limits the anonymous image pull (`toomanyrequests` on `ghcr.io/supabase/postgres:17.6.1.095` and sibling service images) that `supabase start` performs via `apps/web-platform/scripts/supabase-local.sh`. `supabase/setup-cli` exports `SUPABASE_INTERNAL_IMAGE_REGISTRY=ghcr.io` on GitHub-hosted runners, so every service image resolves to `ghcr.io/supabase/*` and is pulled anonymously; the shared anonymous budget for the `supabase` namespace (`allowed: 44000/minute`, measured in failing run 40353999484) saturates under aggregate load across all GitHub consumers, and the CLI's built-in 4s/8s pull retry exhausts.

The fix has two cooperating arms, both inside the one job the issue scopes:

1. **Authenticate the pulls.** A `docker/login-action` step (in-repo pinned SHA, `github.actor` + `secrets.GITHUB_TOKEN`) writes `~/.docker/config.json`; the Supabase CLI reads that file through `GetRegistryAuth()` (`internal/utils/docker.go`, upstream) and attaches it as `RegistryAuth` on every pull. This moves the pulls off the shared anonymous bucket onto the authenticated path — the published real-world resolution for this exact failure. Requires `packages: read` on the job.
2. **Boundedly retry `supabase start`, gated on a measured pull-throttle signature.** A small CI-only helper, `.github/scripts/ghcr-pull-with-retry.sh`, wraps `./scripts/supabase-local.sh start` and retries only when that attempt's own output contains the daemon's `toomanyrequests` token; deterministic failures (the wrapper's exit-2 not-started/unverified contract, migration errors, non-throttle pull errors such as `denied`/`manifest unknown`) still fail on attempt 1. Each retry emits a `::warning::` naming the measured line (ADR-166); exhaustion emits `::error::` and fails the job — failures stay visible. The helper is a standalone script (not an inline `run:` loop) so its classify/retry behavior is fixture-testable and the workflow step stays one line — no `set +e`/`PIPESTATUS` interplay with `lint-workflow-errexit-capture.py`.

Pinned image identity is preserved: same registry, same CLI-resolved tags — only the transport's authentication changes.

## Research Insights

### Premise Validation (Phase 0.6)

- Issue #10868: OPEN, `priority/p2-medium`, `type/bug`, `meta/machinery`. No linked or body-citing PRs. Verified via `gh issue view 10868`.
- Cited artifact exists on `origin/main`: `.github/workflows/rls-authz-fuzz.yml` (161 lines) — the `rls-fuzz` job runs `./scripts/supabase-local.sh start` at the "Start local Supabase stack (loopback-bound)" step.
- The issue's "existing authenticated GitHub Container Registry path" exists: `docker/login-action` `ghcr.io` login in `image-cve-scan.yml` ("Log in to GHCR (read-only pull of the scanned image)", v3.7.0 pin `c94ce9fb468520275223c153574b00df6fe4bcc9`), `build-inngest-bootstrap-image.yml`, `reusable-release.yml`, `scheduled-vinngest-digest-freshness.yml`, `diagnose-inngest-verify.yml`, `build-inngest-config-bundle.yml`; shell-form `docker login ghcr.io --password-stdin` in `apply-web-platform-infra.yml`.
- Failure measured in live logs (run 40353999484, PR head on `feat-one-shot-10764-tenant-integration-red`): `failed to pull docker image: Error response from daemon: toomanyrequests: retry-after: 862.061µs, allowed: 44000/minute` → CLI retries `Retrying after 4s` / `8s` → `Stopping containers...` → exit 1 at the start step. The CLI self-cleans partial containers on pull failure.
- Collision precheck: PR #11295 names #10868 but is this pipeline's own auto-created draft (0 files, branch `feat-one-shot-10868-rls-fuzz-ghcr-throttle`) — not a duplicate. Foreign `proc.sh` rows are another worktree's `test-all.sh` runs — unrelated.
- Related-but-distinct: #9740 (`ci: RLS fuzz times out installing the runner's preinstalled PostgreSQL client`) is OPEN — different failure step (`apt-get install postgresql-client`), not touched by this plan.
- ADR corpus grepped for the proposed mechanism (auth + retry + mirror): ADR-088 (GHCR private-package auth model — superseded; installation tokens cannot pull *private* repo-linked packages, irrelevant to a *public* third-party package), ADR-096 (ghcr→zot migration; zot is the deploy substrate, private-net, no pull-through `sync` block), ADR-153 (supabase-local.sh is permanent vendor-prescribed machinery), ADR-111 (the fuzz gate's existence rationale), ADR-166 (CI messages may only name measured causes — governs retry/annotation wording). No ADR rejects the auth+retry approach.

### Property List (Phase 0.6b)

- P1 — `supabase start`'s image pulls survive saturation of the shared anonymous GHCR bucket for the `supabase` namespace (a per-run credential moves them onto the authenticated path).
- P2 — A transient pull failure at one instant does not fail the job (bounded outer retry; the CLI's internal 4s/8s retry is already insufficient).
- P3 — A pull that cannot complete still fails the job loudly, naming the measured cause (issue: "Keep failures visible"; ADR-166).
- P4 — Pinned image identity is preserved — same registry, same CLI-resolved tags (issue: "preserves pinned image identity").

### Cut List (Phase 0.6b)

- **Zot registry as mirror/pull-through** → buys P1 but is infeasible and disproportionate: `cloud-init-registry.yml`'s rendered zot config carries no `extensions.sync` pull-through block; the retention policy prunes any tag not matching `latest`/`sha256-*`/`v*`/`[0-9a-f]{7,64}` (`17.6.1.095` matches none); the CLI has no way to repoint `ghcr.io` to the bridge; the cf-tunnel bridge requires prd-scoped Doppler creds + CF Access tokens inside a fork-reachable `pull_request` job. Cut.
- **`SUPABASE_INTERNAL_IMAGE_REGISTRY=docker.io` override** → buys P1 only if the `supabase/*` tags exist on Docker Hub (unverified) and weakens P4 (different source registry, different provenance). Kept as documented escalation path, not the mechanism.
- **`actions/cache` + `docker save/load` of the image set** → buys P1 on cache hit only; ~12 images (GBs) against the 10 GB cache cap; the cache key cannot see the CLI-internal tag pins, so it silently rots on a CLI bump. Cut.
- **Third-party retry action (`nick-fields/retry` et al.)** → equivalent function to a ~10-line inline loop; wrapper-vs-curl check says plain bash suffices and adds no new action dependency. Cut.
- **Retry inside `supabase-local.sh`** → would also cover local dev, but the reported failure is CI-shared-egress throttling; the wrapper has a local-dev blast radius (`package.json db:*`, SessionStart hook) and a 400 s fixture suite; the issue scopes the fix to "1 workflow/job". Workflow-level retry chosen; wrapper untouched.

### Repo findings (research: repo-research-analyst)

- Job currently declares only `permissions: contents: read` (workflow level, `.github/workflows/rls-authz-fuzz.yml:27-28`); the job has no own permissions block. `packages: read` must be declared explicitly — an explicit block suppresses all undeclared permissions.
- Canonical bounded-retry helper exists in-repo, duplicated verbatim across `reusable-release.yml` (the `retry()` shape: 3 attempts, sleeps `0 5 15`, `::notice::` per retry, wraps only idempotent ops), `build-inngest-bootstrap-image.yml`, `build-inngest-config-bundle.yml`.
- `lint-workflow-errexit-capture.py` gates `run:` bodies that read `rc=$?`/`${PIPESTATUS[n]}` while errexit is still on — the retry step must `set +e` before the status read (precedent comment at `apply-web-platform-infra.yml` GHCR-restore call site; six shipped instances of the defect class).
- No `shell:` key on a `run:` step means `bash -e` **without pipefail** (per `zot-image-mirror.yml` header comment) — a `cmd | tee log` pipeline returns `tee`'s rc, so the loop must read `${PIPESTATUS[0]}` (or set `shell: bash` explicitly).
- `supabase-local.sh` callers: this workflow (`start`, `assert`), `apps/web-platform/package.json` (`db:start`/`db:stop`/`db:status`/`db:assert-loopback`/`db:cli`), `.claude/hooks/supabase-loopback-warn.sh` (`assert` only), `apps/web-platform/scripts/supabase-local.test.sh` (argv-aware fixture suite). Wrapper untouched → no caller or suite impact.
- ~12 service images pulled per `supabase start` (postgres, gotrue, postgrest, kong, studio, realtime, storage-api, inbucket, edge-runtime, logflare, vector, postgres-meta…); all resolve under `SUPABASE_INTERNAL_IMAGE_REGISTRY=ghcr.io` on this runner.
- Self-validating trigger: `.github/workflows/rls-authz-fuzz.yml` is itself in the job's `pull_request.paths` list — the fixing PR exercises the change.

### External findings (research: best-practices-researcher, functional-discovery)

- GitHub publishes no GHCR pull-rate numbers; the measured shape is `allowed: 44000/minute` — a per-org-namespace aggregate abuse limit shared by anonymous pullers. Sources: [trivy discussion 8009](https://github.com/aquasecurity/trivy/discussions/8009), [dependabot/cli issue 380](https://github.com/dependabot/cli/issues/380), [knqyf263 investigation](https://knqyf263.hatenablog.com/entry/2025/02/28/210820).
- Authenticating a pull of a **public foreign-org** package with `GITHUB_TOKEN` is valid — public packages need no access grant; any valid credential authenticates the token exchange, and the authenticated path is off the shared anonymous bucket. `packages: read` is the required workflow permission (correct hygiene; required for private, harmless for public). Sources: [docs.github.com container registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry), [workflow-syntax permissions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax), [actions/runner PR 990](https://github.com/actions/runner/pull/990).
- The Supabase CLI reads `~/.docker/config.json` via `GetRegistryAuth()` in `internal/utils/docker.go` and injects it as `RegistryAuth`; `RetryClient.ImagePull` treats `toomanyrequests` as retriable with backoff internally. `supabase/setup-cli` exports `SUPABASE_INTERNAL_IMAGE_REGISTRY=ghcr.io` on GitHub runners (since CLI ≥1.28.0, exactly to dodge ECR Public runner-egress limits). Sources: [supabase/cli docker.go](https://github.com/supabase/cli/blob/develop/internal/utils/docker.go), [start.go](https://github.com/supabase/cli/blob/develop/internal/start/start.go), [cli issue 737](https://github.com/supabase/cli/issues/737), [setup-cli issue 128](https://github.com/supabase/setup-cli/issues/128).
- Real-world resolution of this exact failure (`supabase start` → `toomanyrequests` on `ghcr.io/supabase/postgres`): `docker/login-action` + `GITHUB_TOKEN` — [answeroverflow 1552390420229660753](https://www.answeroverflow.com/m/1552390420229660753).
- `docker/login-action` logs out at job end by default (`logout: true`, post phase) — keep the default so no GITHUB_TOKEN persists in the daemon config.
- Caveat carried to Dependencies & Risks: practitioner sources note auth does not raise the limit *for the owning org* — if the `supabase` namespace aggregate itself is the saturated resource, the bounded retry is the complement that still lands the job.

### Institutional learnings applied

- `2026-07-06-ghcr-app-token-cannot-pull-and-oidc-needs-native-identity-source.md` — GitHub App installation tokens can login yet are denied on private packages; do not reach for the minter here (public package + GITHUB_TOKEN is the correct path).
- `2026-03-16-github-actions-workflow-dispatch-permissions.md` — explicit `permissions:` means `packages: read` must be declared, not assumed.
- `2026-07-01-two-stage-privileged-workflow-split-and-its-review-traps.md` — keep `pull_request`, never `pull_request_target`; `packages: read` is read-only and fork-safe (the job's only secret is already absent on forks and gated on `env.DOPPLER_TOKEN != ''`).
- `2026-02-21-github-actions-workflow-security-patterns.md` — pin the action by SHA; reuse the in-repo v3.7.0 pin rather than introducing a new one.
- `2026-05-12-ci-playwright-container-replaces-cache-and-install-deps.md` / `2026-07-17-reuse-live-artifact-fallback-must-gate-on-version-not-presence.md` — basis for cutting actions-cache and presence-based image reuse.
- ADR-096 — "login success is NOT proof of pull capability"; the retry arm is the measured-cause complement, and ADR-166 bounds the annotation wording.
- `2026-04-01-ci-quality-gates-and-test-failure-visibility.md` — Gate 4 is this pattern: pass `GITHUB_TOKEN` into the step hitting a rate-limited GitHub service.
- `2026-09-18-a-plan-prescribed-probe-must-be-portable-to-the-hosts-it-ships-to.md` — one reason the retry lives in the workflow (runner bash), not the macOS-portable wrapper.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "the repository's existing authenticated GitHub Container Registry path" | Exists, but every precedent authenticates against *jikig-ai-owned private* packages; `ghcr.io/supabase/*` is a public foreign-org package | Use the same `docker/login-action` + `GITHUB_TOKEN` shape; the auth that matters is credential presence (moves pulls off the anonymous bucket), not package ownership |
| "the Supabase stack pulls `ghcr.io/supabase/postgres:17.6.1.095`" | `supabase start` fans out ~12 pulls across the whole `supabase/*` namespace | The fix targets the registry transport (login) + the whole `start` verb (retry), not one image |
| "a bounded retry/cache strategy" | No image cache is viable (CLI-internal tags invisible to any cache key); bounded retry is the only arm of that pair that holds | Retry the `start` verb, gated on the measured throttle signature |
| Implicit: retry the pull | The pull is inside the CLI's Go client; it already retries 4s/8s and self-cleans containers on failure | Retry at `supabase-local.sh start` level in the workflow — the layer where the fan-out lives |

## Problem Statement / Motivation

GHCR's anonymous pull path for the `supabase` org namespace has a shared aggregate budget (`allowed: 44000/minute` measured). Every GitHub Actions runner tenant pulling `ghcr.io/supabase/*` anonymously draws from it; when it saturates, the rls-authz-fuzz required gate fails before the stack exists — measured on multiple PR heads (e.g. run 40353999484). The required authorization fuzz coverage is unavailable in CI exactly when its PR needs it, and every failure requires a human re-run.

## Proposed Solution

In `.github/workflows/rls-authz-fuzz.yml`, on the `rls-fuzz` job:

1. Declare `permissions: { contents: read, packages: read }` on the job (job-level block; top-level `contents: read` remains for any future job — job-level mirrors the `build-inngest-bootstrap-image.yml` bump job precedent).
2. Add a `docker/login-action` step (SHA `c94ce9fb468520275223c153574b00df6fe4bcc9` # v3.7.0 — the pin already used for the read-only pull in `image-cve-scan.yml`) immediately after `actions/checkout`, logging in to `ghcr.io` as `github.actor` with `secrets.GITHUB_TOKEN`.
3. Create `.github/scripts/ghcr-pull-with-retry.sh` — a CI-only helper that runs an argv command (`./scripts/supabase-local.sh start`) under `set -uo pipefail`. Each attempt: `"$@" 2>&1 | tee "$log"` into a FRESH per-attempt log (stderr merge is load-bearing — the CLI's pull errors can ride stderr; spec-flow P1-1) with rc read via `${PIPESTATUS[0]}` (spec-flow P1-4: `rc=$?` reads tee's status and inverts the whole contract). Retry only when all hold: `rc != 0`, `rc != 2` (the wrapper's deterministic not-started/unverified class — never a pull failure), and the TAIL of that attempt's log (last ~40 lines — `toomanyrequests` can appear mid-attempt then recover before a later deterministic failure; only the terminal region classifies — spec-flow P1-2) matches `toomanyrequests` (case-insensitive; the daemon's literal token — `Retrying after`, `failed to pull docker image` and `failed to display json stream` are deliberately NOT in the gate: they also fire on non-throttle failures, including post-login `denied`, so they misclassify — advisor + CTO ruling). Bound: 3 attempts; sleeps `20 45` overridable via `GHCR_PULL_RETRY_SLEEPS` env (tests set `0 0`). `::warning::attempt N/3 failed on a measured pull throttle: <matching line>` per retry, with the echoed line sanitized (`%`→`%25`, CR/LF stripped — annotation protocol is line-oriented, spec-flow P2-8); on exhaustion `::error::` naming the last measured line, re-emit the failing log's TAIL (~200 lines — registry errors print at the end of the pull stream; head-truncation clips the diagnostic, CTO Item C) and exit the command's rc; a deterministic failure also emits `::error::<cmd> failed (rc=N) — last log line: <line>` before exiting on attempt 1 (symmetric attribution — spec-flow P2-6).
4. Change the "Start local Supabase stack (loopback-bound)" step's `run:` to a single line — `bash "${GITHUB_WORKSPACE}/.github/scripts/ghcr-pull-with-retry.sh" ./scripts/supabase-local.sh start` — keeping `working-directory: apps/web-platform`. No `rc` read in the `run:` body → `lint-workflow-errexit-capture.py` is not engaged.
5. Add a bash-only test `.github/scripts/test/test-rls-fuzz-ghcr-resilience.sh` with two arms: (a) wiring — `packages: read` present on the job; the `uses: docker/login-action@c94ce9fb468520275223c153574b00df6fe4bcc9` line (FULL pinned SHA, not just the action name — spec-flow P2-10) ordered before the start step; the start step invokes the helper script; NO `logout:` key anywhere in the login step (`logout: 'false'` slips a `logout: false` grep — spec-flow P2-10); the helper contains the literal tokens `2>&1`, `${PIPESTATUS[0]}`, and `toomanyrequests`; (b) behavior — PATH-stubbed fake commands exercising the helper: throttle-line failure retried then passed, non-signature failure exits attempt 1, rc=2 never retried, exhaustion emits `::error::` and the command's rc, a decoy log (`Retrying after` without `toomanyrequests`) is NOT retried, and a stale-signature attempt (throttle on attempt N, clean-log failure on N+1) does not wrongly retry N+1. Auto-joins the `test-*.sh` glob of `.github/scripts/test/run-all.sh` (required check `guard-script-fixture-tests`, bash-only).
6. Bump `MIN_SUITES=15`→`17` in `.github/scripts/test/run-all.sh` — the floor must rise to the post-addition count or the new guard is itself silently deletable (spec-flow P2-5; plan-review found the floor ALREADY lags: 16 `test-*.sh` suites exist on `origin/main` against `MIN_SUITES=15`, i.e. the set is deletable-by-one today — a pre-existing lag worth a tracking note, fixed here by landing the accurate count).
7. Bump the `rls-fuzz` job `timeout-minutes: 25`→`30` — worst case adds ~5–9 min of retried starts + sleeps inside the budget (spec-flow P2-7).
8. Add a positive-control step after login: `docker manifest inspect ghcr.io/supabase/postgres:17.6.1.095 >/dev/null` — ~1s, turns the login→CLI hand-off assumption into a measurement (ADR-166; spec-flow P2-9). If GHCR is down the job now fails at login or this probe — attribution unambiguous.

## Technical Considerations

- **Fork safety:** `packages: read` is a read-only grant; the workflow stays on `pull_request` (never `pull_request_target`); no new secret or egress credential enters the fork-reachable surface — the GITHUB_TOKEN is minted per run and `docker/login-action`'s default post-job `logout` removes it.
- **ADR-166 compliance:** every annotation names a line the helper actually measured (`toomanyrequests …` from that attempt's log, or the command's own last line); no message asserts "GHCR throttled" unless the signature grep matched.
- **Exit-code contract:** the wrapped command's rc is propagated verbatim — `supabase-local.sh start` exit 2 (normalize could not prove state / network unsafe) and exit 1 remain distinct; rc 2 is never retried, and a retry is conditioned on THIS attempt's fresh log matching `toomanyrequests` — a prior attempt's match cannot leak into the classification of a later attempt (each attempt writes a fresh log file).
- **Idempotency of retried `start`:** the daemon's layer cache persists across attempts (already-pulled layers are free), and the CLI runs `Stopping containers...` on pull failure (measured in run 40353999484), so a re-run resumes rather than colliding.
- **Timeout budget:** worst case ≈ 3 starts (~2–3 min each when images partially cached) + 65 s of sleeps ≈ +5–9 min inside `timeout-minutes: 30` (bumped from 25 — spec-flow P2-7).
- **ADR-096/088 consulted, not extended:** zot is production's deploy registry on the private net — not a CI pull path; no ADR change is warranted by reusing the documented `GITHUB_TOKEN`-to-GHCR pattern.

### Attack Surface Enumeration

This is a CI resilience change, not a security-boundary fix; the relevant surface is the credential this change introduces into the job:

- **GITHUB_TOKEN with `packages: read`:** read-only; minted per run; fork PRs get the same read-only token (already the case for `contents: read`); no write capability is added to a fork-reachable job.
- **`~/.docker/config.json` on the runner:** contains the token for the job's lifetime only; `login-action`'s `logout` post-step removes it; the plan asserts `logout: false` never appears (Guard 1 row).
- **No new secrets:** the job's only secret (`DOPPLER_TOKEN_PRD_READONLY`) is unchanged and stays gated on `env.DOPPLER_TOKEN != ''`.

## User-Brand Impact

- **If this lands broken, the user experiences:** a PR author sees the required `RLS authz fuzz` check red either because pulls still fail (no worse than today — failures stay visible) or, in the worst miss-shape, because the retry loop masks a deterministic failure and re-runs it twice before reporting the same red. No end-user surface exists; the blast radius is developer velocity on this repo.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — the only new credential is a read-only, run-scoped `GITHUB_TOKEN` that is removed at job end; no tenant data, no prod network, no user artifact is touched.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff is confined to CI machinery for a repo-internal gate (issue label `meta/machinery`); no user-facing surface, regulated data, or money path is touched.
- `threshold: none, reason: the diff is a GitHub Actions job edit plus its bash wiring test — CI-internal machinery with no user-facing surface or data path` (scope-out for the sensitive-paths regex hitting `.github/workflows/`).

## Observability

```yaml
liveness_signal:
  what:            the required `RLS authz fuzz` check conclusion on each pull_request run
  cadence:         per PR touching the listed paths; workflow_dispatch on demand
  alert_target:    PR author + reviewer via the Checks tab (red check + step annotations)
  configured_in:   .github/workflows/rls-authz-fuzz.yml
error_reporting:
  destination:     GitHub Actions step annotations and the run log
  fail_loud:       "::warning::attempt N/3 failed on a measured pull throttle: <measured line>" per retried attempt (emitted by .github/scripts/ghcr-pull-with-retry.sh); "::error::command failed after N attempts — last measured line: <line>" on exhaustion; job exits nonzero
failure_modes:
  - mode:          GHCR anonymous-bucket saturation recurs despite login (namespace-aggregate caveat)
    detection:     retry loop measures `toomanyrequests` in the captured start log each attempt; exhaustion emits ::error:: with the measured line
    alert_route:   red required check on the PR (author re-runs; issue #10868 stays the tracker)
  - mode:          GITHUB_TOKEN/login misconfiguration
    detection:     the `docker/login-action` step itself fails before any pull — attribution is unambiguous
    alert_route:   red required check on the PR
  - mode:          non-throttle start failure retried wastefully or masked
    detection:     the helper retries only when the attempt's own fresh log matches `toomanyrequests` and rc is not 2; anything else exits attempt 1 with the command's rc — the fixture test asserts the gate behaviorally, not by grepping YAML
    alert_route:   `guard-script-fixture-tests` required check
logs:
  where:           the Actions run log for the job (each attempt's output teed to a fresh per-attempt file under $RUNNER_TEMP)
  retention:       GitHub's default run-log retention (90 days)
discoverability_test:
  command:         bash .github/scripts/test/test-rls-fuzz-ghcr-resilience.sh
  expected_output: "0 failed"
```

## Guard Contract

### Guard 1 — rls-fuzz GHCR-resilience wiring test

**Property.** The `rls-fuzz` job acquires Supabase images on the authenticated GHCR path with a bounded, throttle-signature-gated retry around `supabase start` — and a failure that cannot be retried still fails the job with a measured cause.

**Assembly.** The property quantifies over two artifacts that must move together: (a) the `rls-fuzz` job in `.github/workflows/rls-authz-fuzz.yml` — `permissions`, step ordering (`checkout` → `login-action(ghcr.io)` → start step invoking the helper), and the absence of `logout: false`; and (b) `.github/scripts/ghcr-pull-with-retry.sh` — the attempt bound, the `toomanyrequests` signature gate, the rc≠2 exclusion, per-attempt log freshness, and the `::warning::`/`::error::` emissions. The test `.github/scripts/test/test-rls-fuzz-ghcr-resilience.sh` covers (a) by wiring assertions and (b) BEHAVIORALLY with PATH-stubbed fake commands (assert-what-it-does, not what-the-YAML-says); it runs under the `test-*.sh` glob of `.github/scripts/test/run-all.sh` (required check `guard-script-fixture-tests`, merge-group gated, bash-only).

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `docker/login-action` step entirely | RED (wiring: login-before-start fails) |
| 2 | Move the login step to after the start step | RED (wiring: ordering fails) |
| 3 | Drop `packages: read` from the job permissions | RED (wiring: permission fails) |
| 4 | Remove the attempt bound in the helper so it loops unbounded | RED (behavioral: stub always-fails-with-throttle → attempt count exceeds bound / assertion on max invocations fails) |
| 5 | Remove the `toomanyrequests` signature grep in the helper | RED (behavioral: non-signature-failure stub is retried when it must not be) |
| 6 | Remove the rc≠2 exclusion in the helper | RED (behavioral: rc-2 stub is retried when it must not be) |
| 7 | Reuse one log file across attempts without truncation (stale signature classifies a later attempt) | RED (behavioral: throttle-on-attempt-1 + clean-fail-on-attempt-2 stub is retried wrongly) |
| 8 | Remove `::warning::`/`::error::` emission so retries/exhaustion are silent | RED (behavioral: annotation assertions fail) + wiring annotation-presence assertion |
| 9 | Set `logout: false` on the login step | RED (wiring: logout assertion fails — GITHUB_TOKEN must not persist in the daemon config) |
| 10 | Helper exits 0 when the wrapped command still fails after the bound | RED (behavioral: exhaustion path must propagate nonzero) — the guard's own dispatch: a "retry helper" that reports success over failures is vacuous |
| 11 | Add a SECOND signature token to the throttle gate (e.g. `429`) while keeping `toomanyrequests` | must-PASS (the contract permits the signature list to grow; assertions check presence of the gate, not an exact token set) |
| 12 | A wrapped command that succeeds on first attempt | must-PASS (canonical happy path — no annotation, rc 0, exactly one invocation) |
| 13 | Delete the behavioral arm from the test while the helper keeps the gate | RED via the suite's `MIN_ASSERTIONS` floor (a thinned harness reds itself) |

**Anchor.** The guard greps the live workflow file, not a stored hash — a weakening requires editing both the workflow and the test in one diff, which is review-visible. There is no second artifact the value must match; the assembly *is* the workflow's own text.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Make the RLS fuzz CI image acquisition resilient to shared GHCR pull throttling" `[issue #10868]` | Phase 1 (login step + `packages: read`) + Phase 2 (bounded signature-gated retry) | mapped |
| 2 | "for example by using the repository's existing authenticated GitHub Container Registry path" `[issue #10868]` | Phase 1 — `docker/login-action` `ghcr.io` + `GITHUB_TOKEN` (the in-repo precedent shape) | mapped |
| 3 | "or a bounded retry/cache strategy that preserves pinned image identity" `[issue #10868]` | Phase 2 — bounded retry on the `start` verb; image refs/tags unchanged; cache arm descoped (Cut List) | mapped |
| 4 | "Keep failures visible when pulls still cannot complete." `[issue #10868]` | Phase 2 — `::warning::` per retried attempt + `::error::` + nonzero exit on exhaustion | mapped |
| 5 | "1 workflow/job; bounded retry or auth/cache adjustment." `[issue #10868]` | Scope guard — the diff touches `.github/workflows/rls-authz-fuzz.yml` only (plus its wiring test) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.github/workflows/rls-authz-fuzz.yml` edit (permissions + login + retry call) | "using the repository's existing authenticated GitHub Container Registry path or a bounded retry/cache strategy" | asked |
| `.github/scripts/ghcr-pull-with-retry.sh` | — | inferred — justification: a `run:`-inline retry loop is unverifiable behaviorally (YAML greps assert text, not behavior); the dedicated script is what makes the signature-gate/r.c.-classification contract testable and keeps the `run:` body free of the `set +e`/`PIPESTATUS` pattern `lint-workflow-errexit-capture.py` exists to catch — advisor consult change |
| `.github/scripts/test/test-rls-fuzz-ghcr-resilience.sh` | — | inferred — justification: the fix's failure mode only manifests under shared-egress load, so a silent removal of the login/retry wiring would never reproduce in review; a wiring+behavior guard is the repo's documented defense (`test-*.sh` glob → `guard-script-fixture-tests` required check) |
| `## Observability` block | "Keep failures visible when pulls still cannot complete." | asked |
| `## Guard Contract` block | — | inferred — justification: plan Phase 2.12 mandates it once a guard (the wiring test) is in the deliverable |

### Split Assessment

- Subsystems touched: 1 — `.github` (workflow + its test)
- Planned files: 2 | Estimated changed lines: ~170
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 — The `rls-fuzz` job declares `packages: read` in a job-level `permissions:` block (alongside `contents: read`); the workflow's top-level `permissions:` block is unchanged.
- [ ] AC2 — A `docker/login-action` step pinned to `c94ce9fb468520275223c153574b00df6fe4bcc9` (`# v3.7.0`) logs in to `ghcr.io` as `github.actor` / `secrets.GITHUB_TOKEN`, positioned after `actions/checkout` and before the "Start local Supabase stack (loopback-bound)" step; no `logout: false` override.
- [ ] AC3 — `.github/scripts/ghcr-pull-with-retry.sh` exists (`#!/usr/bin/env bash`, `set -uo pipefail`), takes the wrapped command as argv, runs it at most 3 attempts with sleeps `20 45` (overridable via `GHCR_PULL_RETRY_SLEEPS`), resolves `log_dir="${RUNNER_TEMP:-$(mktemp -d)}"` so the script survives outside Actions (set -u + unset RUNNER_TEMP would abort otherwise — review finding 4), captures each attempt's combined output to a FRESH per-attempt log under `$log_dir` (`tee`), reads the command rc via `${PIPESTATUS[0]}`, and retries only when `rc != 0` AND `rc != 2` AND that attempt's log matches `toomanyrequests` (case-insensitive). The tokens `Retrying after`, `failed to pull docker image`, `failed to display json stream` are NOT in the retry gate.
- [ ] AC4 — Each retried attempt emits `::warning::` containing the measured `toomanyrequests` line; exhaustion emits `::error::` naming the last measured line and exits with the command's nonzero rc; a failure without the signature (or rc 2) exits on attempt 1 propagating the command's rc.
- [ ] AC5 — No image reference, tag, or registry is rewritten or overridden in the diff (`SUPABASE_INTERNAL_IMAGE_REGISTRY` untouched; no `docker pull`/`tag`/`save`/`load` added); the start step's `run:` is the single helper invocation `bash "${GITHUB_WORKSPACE}/.github/scripts/ghcr-pull-with-retry.sh" ./scripts/supabase-local.sh start` under unchanged `working-directory: apps/web-platform`.
- [ ] AC6 — `.github/scripts/test/test-rls-fuzz-ghcr-resilience.sh` exists, is bash-only, covers Guard 1's wiring arm AND behavioral arm (PATH-stubbed fake commands asserting attempt counts, retry/no-retry classification, rc propagation, annotation emission, per-attempt log freshness), and carries a `MIN_ASSERTIONS` floor; `bash .github/scripts/test/test-rls-fuzz-ghcr-resilience.sh` prints `0 failed` locally and `bash .github/scripts/test/run-all.sh` passes.
- [ ] AC7 — `bash scripts/lint-workflows.sh` (the registered workflow-lint arm, incl. actionlint + `lint-workflow-errexit-capture.py`) passes on the edited workflow.
- [ ] AC8 — The `rls-fuzz` job's `timeout-minutes` is 30; `.github/scripts/test/run-all.sh`'s `MIN_SUITES` is 17 (raised to the accurate post-addition suite count — main already has 16 suites vs floor 15); a `docker manifest inspect ghcr.io/supabase/postgres:17.6.1.095 >/dev/null` positive-control step sits between the login step and the start step.
- [ ] AC9 — The PR's own `RLS authz fuzz` check runs the edited workflow (the file is in its own `paths:` trigger) and goes green.
- [ ] PR body includes `Closes #10868`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI-machinery resilience change on a repo-internal required gate (`meta/machinery`). Mechanical UI-surface scan: Files to Create/Edit are `.github/workflows/rls-authz-fuzz.yml`, `.github/scripts/ghcr-pull-with-retry.sh`, and `.github/scripts/test/test-rls-fuzz-ghcr-resilience.sh` — no UI-surface path, so the Product gate does not fire (tier: NONE).

## Test Scenarios

- **Wiring (unit):** given the edited workflow file, when the test's wiring arm runs, then each Guard 1 assertion passes — `packages: read` present, login ordered before start, start step invokes the helper, no `logout: false`. Layer: unit.
- **Retry classification (unit, behavioral):** given PATH-stubbed commands — a throttle-printing-then-succeeding stub, a non-signature-failure stub, an rc=2 stub, a stale-signature stub (throttle attempt 1, clean fail attempt 2), an always-throttle stub — when the helper runs each, then attempt counts, retry/no-retry decisions, annotations and propagated rcs match the contract. Layer: unit.
- **Deterministic failure (integration, self-validating PR):** given a start failure whose log lacks the signature, when the step runs, then it exits on attempt 1 — covered by the behavioral arm and by the PR's own green run (AC8).
- **Regression:** given a future edit removing the login step, the bound, or the gate, when `guard-script-fixture-tests` runs on that PR, then it goes red — the suite exists precisely because the failure mode cannot be reproduced on demand.
- **E2E:** the PR's own `RLS authz fuzz` run exercises the new path end-to-end (authenticated pulls + a real `supabase start`) — pyramid-justified: the only layer that exercises a real GHCR pull.

## Success Metrics

- `RLS authz fuzz` runs stop failing at the "Start local Supabase stack" step with `toomanyrequests` while image identity and step ordering are unchanged.
- On recurrence, the run log shows `::warning::` retry annotations and, on exhaustion, a `::error::` naming the measured line — never a silent or unattributed failure.

## Dependencies & Risks

- **R1 — auth may not fully clear a namespace-aggregate limit.** Practitioner evidence says auth moves a pull off the anonymous path, but if the `supabase` org's *aggregate* budget is the saturated resource, the authenticated pull could still see pressure. Mitigation: the bounded retry arm is exactly the complement; escalation path documented (descoped): `SUPABASE_INTERNAL_IMAGE_REGISTRY=docker.io` once tag parity on Docker Hub is verified.
- **R2 — signature drift.** The retry gate greps the single token `toomanyrequests`, measured verbatim from run 40353999484's daemon error; a GHCR or CLI message change could stop matching, converting throttle failures into attempt-1 exits (loud, not silent — the failure stays visible; the test's must-PASS row permits signature-list growth).
- **R2b — login moves the failure point.** A GHCR-side outage now fails the `docker/login-action` step before `start` — attribution is unambiguous (distinct step), and the failure is still loud.
- **R3 — merge-order overlap.** #10905, #10901 (drafts) and #9051 touch the same workflow file — different scope; whoever lands second rebases. No semantic conflict expected.
- **R4 — new workflow test must stay bash-only** per `run-all.sh`'s contract (no yq/terraform); the plan specifies grep-based assertions only.

## References & Research

- Workflow under fix: `.github/workflows/rls-authz-fuzz.yml` (job `rls-fuzz`, start step at "Start local Supabase stack (loopback-bound)").
- Wrapper (untouched): `apps/web-platform/scripts/supabase-local.sh` — ADR-153 machinery; exit-code contract at its header.
- Auth precedent: `.github/workflows/image-cve-scan.yml` ("Log in to GHCR (read-only pull of the scanned image)", v3.7.0 pin), `build-inngest-bootstrap-image.yml` (job-level `packages: read` precedent), `reusable-release.yml` (canonical `retry()` helper).
- Measured failure: workflow run 40353999484 log — `toomanyrequests: retry-after: 862.061µs, allowed: 44000/minute`; CLI internal `Retrying after 4s/8s` then `Stopping containers...` → exit 1.
- Upstream: supabase/cli `internal/utils/docker.go` (`GetRegistryAuth` reads `~/.docker/config.json`), `internal/start/start.go` (`RetryClient.ImagePull`), supabase/setup-cli#128 (auto-exports `SUPABASE_INTERNAL_IMAGE_REGISTRY=ghcr.io` on GH runners).
- Related issues: #10868 (this fix), #9740 (distinct — psql-client install timeout; not addressed here).
- Learnings: `2026-07-06-ghcr-app-token-cannot-pull-and-oidc-needs-native-identity-source.md`, `2026-02-21-github-actions-workflow-security-patterns.md`, `2026-03-16-github-actions-workflow-dispatch-permissions.md`, `2026-04-01-ci-quality-gates-and-test-failure-visibility.md`, `2026-05-12-ci-playwright-container-replaces-cache-and-install-deps.md`, `2026-07-17-reuse-live-artifact-fallback-must-gate-on-version-not-presence.md`.
- ADRs consulted: ADR-088, ADR-096, ADR-111, ADR-153, ADR-166.

## Implementation Phases

### Phase 1 — Authenticated GHCR path

- Add `permissions: { contents: read, packages: read }` to the `rls-fuzz` job (job-level block).
- Add the `docker/login-action@c94ce9fb468520275223c153574b00df6fe4bcc9 # v3.7.0` step (registry `ghcr.io`, `github.actor`, `secrets.GITHUB_TOKEN`) immediately after `actions/checkout`, with a comment naming #10868 and the mechanism (CLI reads `~/.docker/config.json` via `GetRegistryAuth`).

### Phase 2 — Bounded, signature-gated retry helper + start-step rewiring

- Create `.github/scripts/ghcr-pull-with-retry.sh` per AC3/AC4 (argv command, ≤3 attempts, fresh per-attempt log, `toomanyrequests`-only signature, rc≠2 exclusion, `GHCR_PULL_RETRY_SLEEPS` override, `::warning::`/`::error::` annotations, propagates the command's rc).
- Change the "Start local Supabase stack (loopback-bound)" step's `run:` to `bash "${GITHUB_WORKSPACE}/.github/scripts/ghcr-pull-with-retry.sh" ./scripts/supabase-local.sh start`; `working-directory: apps/web-platform` unchanged.

### Phase 3 — Wiring + behavior regression test

- Create `.github/scripts/test/test-rls-fuzz-ghcr-resilience.sh` (bash-only, `set -uo pipefail`, repo `pass`/`fail`/`MIN_ASSERTIONS` shape) covering Guard 1's wiring arm (YAML greps) and behavioral arm (PATH-stubbed fake commands against the helper).
- Verify locally: `bash .github/scripts/test/test-rls-fuzz-ghcr-resilience.sh` prints `0 failed`; `bash .github/scripts/test/run-all.sh` passes; `bash scripts/lint-workflows.sh` stays green.

## Files to Edit

- `.github/workflows/rls-authz-fuzz.yml` — job-level `permissions:` gains `packages: read`; `docker/login-action` (pinned v3.7.0 SHA) step after checkout; `docker manifest inspect` positive control after login; start step's `run:` becomes the helper invocation; `timeout-minutes` 25→30.
- `.github/scripts/test/run-all.sh` — `MIN_SUITES` 15→17 (floor rises to the accurate post-addition count; 16 suites already exist on main vs floor 15).

## Files to Create

- `.github/scripts/ghcr-pull-with-retry.sh` — the bounded, signature-gated retry helper.
- `.github/scripts/test/test-rls-fuzz-ghcr-resilience.sh` — the wiring + behavior guard test (auto-joins the `test-*.sh` glob).

## Open Code-Review Overlap

None — `gh issue list --label code-review` bodies contain no reference to `.github/workflows/rls-authz-fuzz.yml`, `apps/web-platform/scripts/supabase-local.sh`, or the new test path (checked 2026-10-27).

## Sharp Edges

- A `run:` step without a `shell:` key is `bash -e` with no pipefail: the retry block MUST `set +e` before reading `${PIPESTATUS[0]}` — `lint-workflow-errexit-capture.py` enforces this mechanically.
- Do not add `pull_request_target` or escalate the token — `packages: read` is the whole grant.
- Do not retag, mirror, or `docker save/load` images — pinned identity is preserved by pulling the same `ghcr.io/supabase/*` refs authenticated.
- Do not move the retry into `supabase-local.sh` without re-scoping — its callers include local-dev `db:*` scripts and the SessionStart hook, and its fixture suite must keep passing.
- An empty or `TBD`-filled `## User-Brand Impact` fails deepen-plan Phase 4.6 — it is filled above.
- `## Scope Check` must appear exactly once unfenced; a blocked-verdict line belongs inside it, never in frontmatter.

## Enhancement Summary

Deepen-plan pass (2026-10-27): spec-flow analyzer (4 P1 + 6 P2), solo-advisor consult, CTO ruling (forks A/B/C), three-lens review panel, and all halt gates run against this file.

### Key Improvements

- Retry moved from an inline `run:` loop into `.github/scripts/ghcr-pull-with-retry.sh` (CTO fork A → a3): behaviorally testable, wrapper untouched, `run:` body stays one line (no `set +e`/`PIPESTATUS` in YAML).
- Signature narrowed to `toomanyrequests` only, tail-scoped (~40 lines) on a FRESH per-attempt log (CTO fork B → b3; spec-flow P1-2/P1-3; advisor): `Retrying after`/`failed to pull docker image`/`failed to display json stream` are decoys that fire on non-throttle failures.
- `2>&1` merge and `${PIPESTATUS[0]}` pinned as load-bearing tokens asserted by the wiring test (spec-flow P1-1/P1-4).
- Symmetric `::error::` on deterministic exit (P2-6); annotation text sanitized `%`→`%25`, CR/LF stripped (P2-8); exhaustion re-emits the failing log's tail ~200 lines (CTO Item C).
- `timeout-minutes` 25→30 (P2-7); `docker manifest inspect` positive control after login (P2-9); `MIN_SUITES` 15→17 — review found the floor already lags the real suite count (16 vs 15) on main.
- `log_dir="${RUNNER_TEMP:-$(mktemp -d)}"` fallback (review finding 4); `logout:`-key absence (not `logout: false` literal) and full-SHA `uses:` assertions (P2-10).

### New Considerations Discovered

- Login moves the failure point: a GHCR outage now fails the login/manifest-inspect step — attribution unambiguous (R2b).
- rc≠2 exclusion is redundant-belt documentation of the wrapper's deterministic class (review finding 2, CTO: "documents intent at zero cost").
- Gate results: 4.5 network-outage N/A (no trigger patterns); 4.6 User-Brand present (`threshold: none` + scope-out); 4.7 Observability 5-field schema present, discoverability_test `bash`-first; 4.8 PAT-shaped vars none; 4.9 UI N/A; 4.10 encryption N/A; 4.11 guard-contract lint PASS (1 entry); 4.12 Scope Check exactly one unfenced section, no blocked-verdict; 4.13 task-design N/A (existing workflow edit).
- False-halt tokens neutralized: literal `status: BLOCKED` and `unreachable` removed from non-gated prose.
