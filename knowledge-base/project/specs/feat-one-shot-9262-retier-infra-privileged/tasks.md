# Tasks: re-tier the inngest-bootstrap pin-bump and auto-mint App-token consumers to infra-privileged

Plan: `knowledge-base/project/plans/2026-09-30-infra-retier-pin-bump-and-automint-to-infra-privileged-plan.md`
(closes #9262, refs #8209). No production writes in this pipeline. UNTRUSTED-CI: no admin-merge, no
auto-merge.

## Phase 1: Setup

- [ ] 1.1 Re-confirm measured preconditions (read-only): `soleur-infra` installation permissions,
  `infra-privileged` policy and secrets, zero open `soleur/inngest-pin-*` branches and PRs.
- [ ] 1.2 Check the open sibling PR #9263 (#8609) for conflicts on shared files (ADR-241, `model.c4`,
  `model.likec4.json`, `infra-credential-tiers-8209.md`, the census) before editing them.

## Phase 2: RED tests (before code)

- [ ] 2.1 `test-bump-inngest-bootstrap-pin.sh`: exact-dict + key-set rows for the bump job's
  environment, verify step and mint step; `g2.bump-job:parsed`; trigger row (`on:` keys exactly
  `workflow_dispatch`); retire the text rows they replace; `ACTION=` path and the three
  `g2.action:*` name rows move to the Tier-B names.
- [ ] 2.2 Same suite: identity fixtures and rows to `soleur-infra[bot]` / `335404629+…`; literal
  sweep constants; `pr_json` stub emits `app/<slug>`; new `g1.reuse-app-author` row; raise
  `MIN_ASSERTIONS`.
- [ ] 2.3 `test-mint-inngest-bootstrap-tag.sh`: `COMPOSITE=` renamed path; verify-step finder
  follows the renamed step; key-set half added to `exact()`; `exact("doppler-check")`,
  `exact("app")`, job environment row; `comp:*` rows for required inputs, fixed Doppler
  project/config/names, grant mismatch, GitHub message on failure, `app-token` notice; flip
  `comp.default:*` / `comp.repos-only:*`; drop sentinel rows; raise `MIN_ASSERTIONS`.
- [ ] 2.4 Census: G4e floor 4 → 3 with dated rationale.
- [ ] 2.5 `allowlist.test.ts`: add `soleur-infra[bot]` to the exact set.
- [ ] 2.6 Run each suite; confirm the new rows are RED for the right reason.

## Phase 3: Core Implementation

- [ ] 3.1 `git mv .github/actions/mint-soleur-ai-app-token .github/actions/mint-infra-app-token`;
  make it Tier-B-only (fixed `soleur-infra-privileged`/`prd`, literal `GITHUB_INFRA_APP_*` reads,
  required non-empty inputs, exact-grant check kept, sentinel refusal dropped, GitHub `.message` on
  failure, `app-token` notice on success).
- [ ] 3.2 `build-inngest-bootstrap-image.yml`: remove `push: tags`; fix comments that become false;
  bump job gets `environment: infra-privileged`, the Tier-B verify step and the scoped mint step.
  Do not touch carrier `cp` lines, pin reads or the Dockerfile heredoc.
- [ ] 3.3 `mint-inngest-bootstrap-tag.yml`: `environment: infra-privileged`, Tier-B verify step,
  scoped mint step through the renamed composite; rewrite the header comment about the missing
  environment.
- [ ] 3.4 `bump-inngest-bootstrap-pin.sh`: `BOT_NAME` / `BOT_EMAIL` switched in place; new
  `BOT_PR_LOGIN='app/soleur-infra'` for the `gh pr list` author filters (pre-existing bug: they never
  matched the `app/<slug>` form); identity-neutral messages; header comment names the renamed
  composite.
- [ ] 3.4b `mint-inngest-bootstrap-tag.sh`: "soleur-ai App token" wording → "soleur-infra App token".
- [ ] 3.5 `github-infra-app-manifest.json`: `actions: write`, `pull_requests: write`, description.
- [ ] 3.6 `cla.yml`: add `soleur-infra[bot]` with the bot-id/email comment.
- [ ] 3.7 Census G4e floor + rationale.

## Phase 4: Recorded architecture and runbooks

- [ ] 4.1 ADR-232 amendment (§1 title, §3, §4, §8, "After #8209", A5 adopted).
- [ ] 4.2 ADR-241 D5 amendment.
- [ ] 4.3 C4 `model.c4` edge `github -> soleurMarketplace`; regenerate `model.likec4.json` with
  `bash plugins/soleur/scripts/render-c4-model.sh`.
- [ ] 4.4 `infra-credential-tiers-8209.md`: Group 4 rows, environment-coverage list, O4c row, order
  constraint, O10 preconditions.
- [ ] 4.5 `inngest-server.md` hand-tag block and #8747 recovery block (present tense; dispatch once
  from `main`).
- [ ] 4.6 `apply-web-platform-infra-job-rationale.md`: three consumers.

## Phase 5: Testing (targeted; CI is the gate)

- [ ] 5.1 The two job-shape suites, the census, the mirror-only suite, the tag-guard suite, the
  infra-credentials suite (regression).
- [ ] 5.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/cla-evidence/allowlist.test.ts`.
- [ ] 5.3 C4 checks: `c4-model-freshness`, `c4-count-parity`, `c4-code-syntax`, `c4-render`.
- [ ] 5.4 `bun test plugins/soleur/test/workflow-file-size.test.ts`; `actionlint` on the two workflows.
- [ ] 5.5 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`; AC11 residual
  sweeps.
- [ ] 5.6 `git fetch --tags origin && bash .github/scripts/mint-inngest-bootstrap-tag.sh --dry-run`
  prints `result=noop` (AC3).

## Phase 6: Ship

- [ ] 6.1 PR #9301 body: first line = merge side effects; `Closes #9262`, `Refs #8209`; render
  `decision-challenges.md`.
- [ ] 6.2 File deferral issues: Art. 30 PA-12 wording (legal), narrower Doppler source (security).
- [ ] 6.3 Re-check AC5 (no open pin branches/PRs); mark ready; no admin-merge, no auto-merge; stop.
