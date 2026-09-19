# Tasks: feat-one-shot-auto-inngest-pin-bump

Plan: `knowledge-base/project/plans/2026-09-19-feat-auto-bump-inngest-bootstrap-pin-plan.md` (Ref #8359)
Reviewed-Coverage: sequential-fallback.

## Phase 1: Bump script + fixture suite (TDD — RED first)

- [x] 1.1 Write `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh` FIRST (failing)
  - [x] 1.1.1 Fixture git repo with synthetic `vinngest-v*` tags + fixture copies of `apps/web-platform/infra/cloud-init.yml` and `apps/web-platform/infra/cloud-init-inngest.yml` pin regions
  - [x] 1.1.2 PATH-shimmed stubs: `crane` (returns a configured digest), `gh` (records `pr create/close/comment/merge` calls, serves `pr list`), git real (fixture repo)
  - [x] 1.1.3 Cover every Guard Contract mutation-matrix row (Guards 1+2), including the anti-vacuity assertion-count floor and the tag-conditioned cross-check rows (5, 5b)
- [x] 1.2 Write `.github/scripts/bump-inngest-bootstrap-pin.sh` until the suite is green
  - [x] 1.2.1 Args: `--signed-tag <vX.Y.Z>` `--signed-digest <sha256:…>` `--mirror-status <ok|degraded|>` plus `--dry-run`; validate inputs fail-closed
  - [x] 1.2.2 Target = semver-max `vinngest-v*` via the AC6-identical pipeline (`git -C <repo> tag --list 'vinngest-v*' | sed 's/^vinngest-//' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1`)
  - [x] 1.2.3 `crane digest ghcr.io/jikig-ai/soleur-inngest-bootstrap:<target>` → resolved digest, fail closed on unparseable; cross-check `--signed-digest` vs resolved ONLY when `--signed-tag == target` (halt on mismatch; note+skip otherwise — mirror_only backfill of a non-max tag must not red)
  - [x] 1.2.4 Idempotent rewrite: all four refs already `:<target>@<resolved>` → `result=noop`; else anchored substitution of `soleur-inngest-bootstrap:v…@sha256:…` (preserves `$ZURL`/`$ZOT_EP` variable prefixes), assert exactly 2 substitutions per file, zero tag-only refs, `distinct==1`
  - [x] 1.2.5 Git identity `soleur-ai[bot]` / `273333864+soleur-ai[bot]@users.noreply.github.com`; branch `soleur/inngest-pin-<target>`; commit `chore(infra): bump inngest-bootstrap pin <old> -> <target> (vinngest-<target>)`
  - [x] 1.2.6 Push via `https://x-access-token:${GH_TOKEN}@github.com/<repo>.git`; remote-tip bot-authored check before any force-push; human tip → `branch-has-manual-commits`, no push
  - [x] 1.2.7 PR: `gh pr list --head` → exists ⇒ comment + `result=existing`; else `gh pr create --base main` (body: tag, digest, publishing run URL, `Ref #8359` on its own line, mirror-degraded note when set)
  - [x] 1.2.8 Supersede open bot-authored `soleur/inngest-pin-*` PRs for other targets (`Superseded by <url>` comment, bot-tip check first)
  - [x] 1.2.9 Auto-merge `gh pr merge --auto --squash` iff `--mirror-status == 'ok'`; on `degraded` comment the hold; arm-failure → `::warning` not fatal
  - [x] 1.2.10 Emit `result=opened|existing|noop|skipped|error` + `$GITHUB_STEP_SUMMARY`; stage-named exits (`mint|resolve|rewrite|push|pr|merge`)

## Phase 2: Workflow wiring

- [x] 2.1 `.github/workflows/build-inngest-bootstrap-image.yml` — `build` job: add `id: sign` to `Cosign-sign the GHCR digest` + `printf 'digest=%s\n' "$DIGEST" >> "$GITHUB_OUTPUT"`; add job-level `outputs:` (`tag`, `digest`, `mirror_status`)
- [x] 2.2 Append `bump-cloud-init-pin` job: `needs: build`; `ubuntu-latest`; `timeout-minutes: 10`; `concurrency: { group: inngest-pin-bump, cancel-in-progress: false }`; `permissions: { contents: read }`
  - [x] 2.2.1 Checkout `ref: main` + `fetch-depth: 0` + `fetch-tags: true` + `persist-credentials: false`
  - [x] 2.2.2 Install crane (same pinned recipe as build job) + Doppler CLI; verify `secrets.DOPPLER_TOKEN`
  - [x] 2.2.3 Mint soleur-ai installation token via the board-status-sync inline JWT recipe verbatim (`DOPPLER_CONFIG: prd_terraform`, `INSTALLATION_ID: "122213433"`, `b64url() { base64 -w 0 | tr '+/' '-_' | tr -d '=\n'; }`, curl exchange — `gh api` does not accept JWT `GH_TOKEN`)
  - [x] 2.2.4 Run the script with the three job outputs as args; `if: failure()` Slack-notification step on `SLACK_RELEASES_WEBHOOK_URL` (script step must NOT carry `continue-on-error` or `failure()` never fires)

## Phase 3: ADR + C4

- [x] 3.1 Author ADR-230 (provisional ordinal — `ship` re-verifies; on renumber sweep `grep -rn 'ADR-230' knowledge-base/project/{plans,specs}/feat-one-shot-auto-inngest-pin-bump/`): pin-bump PRs authored by the publishing workflow via soleur-ai App token — never scheduled reconciler, never GITHUB_TOKEN, never direct push; Alternatives Considered per plan §ADR
- [x] 3.2 `model.c4`/`views.c4`: documented repo-write relationship for tag-publish-driven pin-bump PRs; run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`

## Phase 4: Verification

- [x] 4.1 `bash .github/scripts/test/test-bump-inngest-bootstrap-pin.sh` — 0 failures
- [x] 4.2 `bash .github/scripts/test/run-all.sh` — green with suite count ≥ 12
- [x] 4.3 AC sweep per plan §Acceptance Criteria (AC1–AC14); record AC14 deferral note in PR body
- [x] 4.4 `deploy-script-tests` remains green (this PR edits no pin)
