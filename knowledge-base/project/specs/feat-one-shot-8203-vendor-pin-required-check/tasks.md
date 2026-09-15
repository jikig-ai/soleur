# Tasks — feat: vendor-pin-required required-check gate (#8203)

Plan: `knowledge-base/project/plans/2026-09-15-feat-vendor-pin-required-check-plan.md`
Branch: `feat-one-shot-8203-vendor-pin-required-check`

## Phase 0 — Re-confirm the verified edit set (read-only)

- [ ] T0.1. `grep -c 'required_check {' infra/github/ruleset-ci-required.tf` == 23;
      `jq 'length' scripts/ci-required-ruleset-canonical-required-status-checks.json`
      == 23; T-rsc-7 in `tests/scripts/test-audit-ruleset-bypass.sh` still pins `23`;
      `SYNTHETIC_CHECK_NAMES` in `_cron-safe-commit.ts` still 7 names, test-pinned;
      `action.yml` still derives CHECK_NAMES from `required-checks.txt`.
- [ ] T0.2. Confirm `plugins/soleur/test/vendor-bundle-coverage.test.sh` TS4 still
      greps literal `plugins/soleur/skills/<slug>/` prefixes in
      `vendor-pin-verify.yml` (the reason anchors stay literal, not wildcard).
- [ ] T0.3. Read `scripts/tenant-integration-gate-verdict.sh`,
      `scripts/sentry-destroy-gate-verdict.sh`, and
      `tests/scripts/test-sentry-destroy-gate-verdict.sh` as copy-source.

## Phase 1 — Workflow restructure + verdict pair

- [ ] T1.1. Create `scripts/vendor-pin-gate-verdict.sh` — fail-closed allow-list:
      exit 0 iff `detect==success` AND `verify ∈ {success, skipped}`; exit 1
      otherwise. Include the skipped-arm `::notice`/job-summary honesty line and
      the `cancelled` diagnostic arm (mirror the sibling verdicts' comments).
- [ ] T1.2. Create `tests/scripts/test-vendor-pin-gate-verdict.sh` covering:
      (success,success)→pass; (success,skipped)→pass; (success,failure)→fail;
      (failure,skipped)→fail [DROP-1]; (success,cancelled)→fail; (empty,*)→fail;
      (*,empty)→fail.
- [ ] T1.3. Edit `.github/workflows/vendor-pin-verify.yml`:
      (a) `on:` → `pull_request: { branches: [main] }` (drop `paths:`),
          `push: { branches: [main] }`, `merge_group:`, `workflow_dispatch:`;
      (b) add `detect-changes` job emitting `vendor=true|false` — PR diff vs
          `origin/$BASE_REF` (`fetch-depth: 0`), non-PR events → `true`,
          `merge_group` → `false`, git error → job fails (never silent `false`);
      (c) `verify-upstream-blobs` += `needs: detect-changes` +
          `if: needs.detect-changes.outputs.vendor == 'true'` (steps unchanged);
      (d) add `vendor-pin-required` — `needs: [detect-changes,
          verify-upstream-blobs]`, `if: always()`, `run:` step calls the verdict
          script with both results via `env:` + quoted `"$VAR"`;
      (e) `concurrency: { group: vendor-pin-verify-${{ github.ref }},
          cancel-in-progress: false }`.
      Anchor set (LITERAL per-bundle paths — see plan R2): each conforming
      bundle's `plugins/soleur/skills/<slug>/NOTICE` +
      `plugins/soleur/skills/<slug>/references/` (today: gdpr-gate,
      legal-generate), `plugins/soleur/skills/gdpr-gate/scripts/
      vendor-pin-integrity.sh`, `.../notice-frontmatter.sh`,
      `.github/workflows/vendor-pin-verify.yml`,
      `scripts/vendor-pin-gate-verdict.sh`,
      `tests/scripts/test-vendor-pin-gate-verdict.sh`.
- [ ] T1.4. Register the new test in `scripts/test-all.sh` via `run_suite`
      beside the sibling verdict suites (~:2363-2371).

## Phase 2 — Required-check registration

- [ ] T2.1. `infra/github/ruleset-ci-required.tf`: add 24th `required_check`
      (`context = "vendor-pin-required"`, `integration_id =
      var.actions_integration_id`) with tier comment citing #8203 + the
      aggregator precedent + synthetic disposition; fix the stale header
      count ("20" → 24). No literal `context = "..."` inside comments
      (T-rsc-9 comment-naive grep).
- [ ] T2.2. `scripts/ci-required-ruleset-canonical-required-status-checks.json`:
      append `{ "context": "vendor-pin-required", "integration_id": 15368 }`.
- [ ] T2.3. `scripts/required-checks.txt`: add `vendor-pin-required` + guard note
      naming BOTH arms — composite-action unreachability (ALLOWED_PATHS ∩
      `plugins/soleur/skills/**` = ∅) AND the `SYNTHETIC_CHECK_NAMES`
      exclusion (Inngest re-vendor PRs earn it via real CI).
- [ ] T2.4. `tests/scripts/test-audit-ruleset-bypass.sh` T-rsc-7: `23` → `24`
      (predicate + report string) + `bumped 23->24 by #8203` history line.
- [ ] T2.5. `cd infra/github && terraform fmt && terraform validate` (no apply).

## Phase 3 — Bot-synthetic disposition

- [ ] T3.1. Comment-only edit at `SYNTHETIC_CHECK_NAMES`
      (`_cron-safe-commit.ts:47-55`): `vendor-pin-required` deliberately absent —
      re-vendor/attest PRs earn it via real CI on App-token pushes; adding it
      would fabricate the check on the diffs it gates.
- [ ] T3.2. Run `bash scripts/lint-bot-synthetic-completeness.sh`; paste full
      audit output into PR body.
- [ ] T3.3. Run `bash plugins/soleur/test/required-checks-canonical-parity.test.sh`
      — must be green.

## Phase 4 — ADR amendment + policy doc

- [ ] T4.1. Amend ADR-032: count → 24; second instance of the always-run
      aggregator pattern; schema-keyed-surface ⇒ literal per-bundle anchors;
      the earned-vs-fabricated split across the two synthetic paths.
- [ ] T4.2. `knowledge-base/engineering/policies/content-vendoring.md` §:90 —
      update to name `vendor-pin-required` as the required gate wrapping
      `verify-upstream-blobs`.

## Phase 5 — Verification (pre-merge)

- [ ] T5.1. `bash scripts/test-all.sh` green (verdict suite, parity, T-rsc-7/9,
      vendor-bundle-coverage).
- [ ] T5.2. `actionlint` on the workflow; `bash -n` on extracted `run:` snippets.
- [ ] T5.3. `terraform fmt -check` + `terraform validate` green in infra/github.
- [ ] T5.4. AC greps: `grep -c 'required_check {' infra/github/ruleset-ci-required.tf`
      == 24; `grep -c 'vendor-pin' apps/web-platform/server/inngest/functions/
      _cron-safe-commit.ts` inside the array == 0.

## Post-merge (verify, per plan AC9–AC11)

- [ ] T6.1. `apply-github-infra.yml` merge-triggered run green; live ruleset
      14145388 lists `vendor-pin-required`.
- [ ] T6.2. First unrelated PR: `vendor-pin-required` success with verify
      skipped + notice. First `cron-content-vendor-drift` PR: context earned
      by a real run, no synthetic for this name.
- [ ] T6.3. Rebase one pre-existing open PR to confirm the new context
      self-heals under strict policy.
