# Tasks: re-tier the inngest-bootstrap pin-bump and auto-mint App-token consumers to infra-privileged

Plan: `knowledge-base/project/plans/2026-09-30-infra-retier-pin-bump-and-automint-to-infra-privileged-plan.md`
(closes #9262, refs #8209). No production writes in this pipeline. UNTRUSTED-CI: no admin-merge, no
auto-merge.

## Phase 1: Setup

- [x] 1.1 Re-confirm measured preconditions (read-only): `soleur-infra` installation permissions,
  `infra-privileged` policy and secrets, zero open `soleur/inngest-pin-*` branches and PRs.
- [x] 1.2 Check the open sibling PR #9263 (#8609) for conflicts on shared files (ADR-241, `model.c4`,
  `model.likec4.json`, `infra-credential-tiers-8209.md`, the census) before editing them.

## Phase 2: RED tests (before code)

- [x] 2.0 Shared helpers in both suites: `norm_env`, `keyset_ok` (ignores `name`/`timeout-minutes`;
  `None` means absent), `one_minter`, `no_tier_a`.

- [x] 2.1 `test-bump-inngest-bootstrap-pin.sh`: exact-dict + key-set rows for the bump job's
  environment, verify step and mint step; `g2.bump-job:parsed`; trigger row (`on:` keys exactly
  `workflow_dispatch`); retire the text rows they replace; `ACTION=` path and the three
  `g2.action:*` name rows move to the Tier-B names (`--project soleur-infra-privileged`);
  `one_minter`/`no_tier_a` rows; `S`-prefixed trigger row via `doc.get("on", doc.get(True))`;
  bump-side mutation harness with a clean-copy instrument control.
- [x] 2.2 Same suite: identity fixtures and rows to `soleur-infra[bot]` / `335404629+…`; literal
  sweep constants; `pr_json` stub emits `app/<slug>` and gains `|author=<login>`; rows that a
  same-repo PR by `app/soleur-ai` or a human is not reused; `g1.mirror-only-held`; reworded
  recovery messages; raise `MIN_ASSERTIONS`.
- [x] 2.3 `test-mint-inngest-bootstrap-tag.sh`: `COMPOSITE=` renamed path; verify-step finder
  follows the renamed step; key-set half added to `exact()`; `exact("doppler-check")`,
  `exact("app")`, job environment row; `comp:*` rows for required inputs, fixed Doppler
  project/config/names asserted via the stub's argv (`DOPPLER_LOG`, `env -u DOPPLER_PROJECT -u
  DOPPLER_CONFIG`, `run_comp` parameterized), grant mismatch, sanitized GitHub message on failure,
  `app-token` notice, a `g3_mut` row changing the project to `soleur`; flip
  `comp.default:*` / `comp.repos-only:*`; drop sentinel rows; raise `MIN_ASSERTIONS`.
- [x] 2.4 Census: G4e floor 4 → 3 with dated rationale.
- [x] 2.5 `allowlist.test.ts`: add `soleur-infra[bot]` to the exact set.
- [x] 2.6 Run each suite; confirm the new rows are RED for the right reason.

## Phase 3: Core Implementation

- [x] 3.1 `git mv .github/actions/mint-soleur-ai-app-token .github/actions/mint-infra-app-token`;
  make it Tier-B-only (`--project soleur-infra-privileged --config prd` in argv, literal
  `GITHUB_INFRA_APP_*` reads, sanitize GitHub's message before `::error::`,
  required non-empty inputs, exact-grant check kept, sentinel refusal dropped, GitHub `.message` on
  failure, `app-token` notice on success).
- [x] 3.2 `build-inngest-bootstrap-image.yml`: remove `push: tags`; fix comments that become false;
  bump job gets `environment: infra-privileged`, the Tier-B verify step and the scoped mint step.
  Pass `--mirror-only "${{ inputs.mirror_only }}"` to the bump script. Do not touch carrier `cp`
  lines, pin reads or the Dockerfile heredoc; edit only comments that become false.
- [x] 3.3 `mint-inngest-bootstrap-tag.yml`: `environment: infra-privileged`, Tier-B verify step,
  scoped mint step through the renamed composite; rewrite the header comment about the missing
  environment.
- [x] 3.4 `bump-inngest-bootstrap-pin.sh`: `BOT_NAME` / `BOT_EMAIL` switched in place; new
  `BOT_PR_LOGIN='app/soleur-infra'` for the `gh pr list` author filters (pre-existing bug: they never
  matched the `app/<slug>` form); `--mirror-only` withholds auto-merge; recovery messages a human can
  act on; the two "tag push runs its own publish and bump" `die` messages reworded; header comment
  names the renamed composite.
- [x] 3.4b `mint-inngest-bootstrap-tag.sh`: "soleur-ai App token" wording → "soleur-infra App token".
- [x] 3.5 `github-infra-app-manifest.json`: `actions: write`, `pull_requests: write`, description.
- [x] 3.6 `cla.yml`: add `soleur-infra[bot]` with the bot-id/email comment.
- [x] 3.7 Census G4e floor + rationale.

## Phase 4: Recorded architecture and runbooks

- [x] 4.1 ADR-232 amendment: H1 title, §3 (incl. scope parenthetical), §4, §7 caveats, §8 Tag and
  Dispatch bullets, Residual R1, "After #8209", Alternatives rows, Consequences write-surface bullet,
  Verification composite path, mirror-only auto-merge note.
- [x] 4.2 ADR-241: D2 serves-list, D5 scopes sentence, D5 flip condition gains O4c/AC15 evidence.
- [x] 4.3 C4 `model.c4` edges `github -> soleurMarketplace` (prose + `technology`) and
  `github -> doppler`; regenerate `model.likec4.json` with
  `bash plugins/soleur/scripts/render-c4-model.sh`.
- [x] 4.4 `infra-credential-tiers-8209.md`: Group 4 rows, environment-coverage and referenced-by
  lists, O4c row (annotated "added by #9262"), order constraint, O10 preconditions and re-targeted
  verify limb, the #9262 → O4c → O10 → #8609 R-step 1 chain, the O13(c) note.
- [x] 4.5 `inngest-server.md` hand-tag block and #8747 recovery block (present tense; dispatch once
  from `main`).
- [x] 4.6 `apply-web-platform-infra-job-rationale.md`: three consumers.

## Phase 5: Testing (targeted; CI is the gate)

- [x] 5.1 The two job-shape suites, the census, the mirror-only suite, the tag-guard suite, the
  infra-credentials suite (regression).
- [x] 5.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/cla-evidence/allowlist.test.ts`.
- [x] 5.3 C4 checks: `c4-model-freshness`, `c4-count-parity`, `c4-code-syntax`, `c4-render`.
- [x] 5.4 `bun test plugins/soleur/test/workflow-file-size.test.ts`; `actionlint` on the two workflows.
- [x] 5.5 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`; AC11 residual
  sweeps.
- [x] 5.6 `git fetch --tags origin && bash .github/scripts/mint-inngest-bootstrap-tag.sh --dry-run`
  prints `result=noop` (AC3).

## Phase 6: Ship

- [x] 6.1 PR #9301 body: first line = merge side effects; `Closes #9262`, `Refs #8209`; render
  `decision-challenges.md`; a merge-time checklist as commands (no queued/in-progress run of either
  workflow; AC5's two commands).
- [x] 6.2 File deferral issues: Art. 30 PA-12 wording (legal), narrower Doppler source (security;
  re-evaluate at #9263 merge), build-job supply-chain gaps (security, p1). Done as: PA-12 wording
  folded into the O4c tracker #9320; narrower source #9321; supply-chain gaps commented onto the
  existing #8780 rather than a new issue; decision challenges #9322.
- [x] 6.3 Mark ready; no admin-merge, no auto-merge; stop.
