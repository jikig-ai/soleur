---
title: Tasks — feat-one-shot-10390-ci-hygiene-batch
date: 2026-11-04
plan: knowledge-base/project/plans/2026-11-04-chore-ci-infra-hygiene-batch-plan.md
issues: [8780, 9659, 10078]
epic: 10390
---

# Tasks

## 1. Setup / verification (Phase 0)

- [ ] 1.1 Re-run the dedupe census on this branch:
  `git grep -nE '=\$\([[:space:]]*gh (issue|pr) (list|search)' -- '.github/workflows/'`
  and classify every hit into fix / fail-closed / benign against the
  issue's three buckets.
- [ ] 1.2 Re-run the web-host EnvironmentFile census over `*.service` +
  generator heredocs (`cloud-init.yml`, `soleur-host-bootstrap.sh`);
  confirm the seven-unit candidate set.
- [ ] 1.3 `gh pr view 10928 --json files` — confirm the live-race PR's
  file set still only overlaps at `apply-web-platform-infra.yml`,
  `terraform-target-parity.test.ts`, `ADR-241`; re-read those three files
  before editing.
- [ ] 1.4 Re-derive every line number the issues cite (~: markers).

## 2. Workstream B — #9659 dedupe normalization + lint (Phase 1)

- [ ] 2.1 Rewrite each filing-path site (the issue's 12-file list +
  classified additions) to the fail-open `if ! VAR="$(…)"` or
  `|| { ::error::<slug>…; VAR=""; }` shape, preserving per-site slugs.
- [ ] 2.2 Add `# dedupe: fail-closed <reason>` / `# dedupe: benign
  <reason>` markers on every non-normalized survivor.
- [ ] 2.3 Write `scripts/lint-gh-dedupe-shape.py` (census + adjacency
  classification per Guard 1) printing `dedupe-shape: unclassified: <n>`.
- [ ] 2.4 Write `scripts/lint-gh-dedupe-shape.test.sh` with the Guard 1
  mutation battery (incl. zero-hit vacuity arm + heredoc must-pass).
- [ ] 2.5 Register the pair: `test-all.sh` run_suite lines,
  `suite-durations.tsv`, `suite-shard-legs.tsv`,
  `guard-vacuity-floor.test.sh` PROMOTED check.

## 3. Workstream C — #10078 EnvironmentFile conditioning (Phase 2)

- [ ] 3.1 Add `ConditionPathExists=/etc/default/<file>` in `[Unit]` of
  `inngest-consumer-probe.service`, `web-bash-synthetic.service`,
  `web-git-data-probe.service`, `web-private-nic-guard.service`,
  `web-zot-consumer-probe.service`, each with a SKIP-VS-FAIL comment
  naming the boot-emit fatal channel + the unit's own heartbeat detector;
  `EnvironmentFile=` stays unprefixed.
- [ ] 3.2 Add designed-loud comments to `webhook.service`, its
  `cloud-init.yml` embedded twin (lockstep), and the `vector.service`
  heredoc in `soleur-host-bootstrap.sh` — no condition added.
- [ ] 3.3 Regenerate `WEBHOOK_SERVICE_B64` in `infra-config-apply.sh`
  (comment-only edit still changes bytes; stale pin refuses delivery).
- [ ] 3.4 Update per-unit pins: condition-path-set ≡ envfile-path-set,
  unprefixed retention, no reset lines, negative pins on webhook/vector
  incl. heredoc extraction — in the per-unit `*.test.sh`,
  `soleur-host-bootstrap-observability.test.sh`, `infra-config-apply.test.sh`,
  `fresh-boot-parity.test.sh` as the pin inventory requires.

## 4. Workstream A — #8780 publish admission (Phase 3)

- [ ] 4.1 `inngest-config-signing.tf`: `deployment_branch_policy` block +
  `github_repository_environment_deployment_policy.inngest_config_signing_main`
  (reviewers retained).
- [ ] 4.2 Create `release-publish-environment.tf`: reviewer-less,
  secrets-free, main-only policy + `release_publish_main`, with the
  auto-create-hazard header comment.
- [ ] 4.3 `apply-web-platform-infra.yml`: append the three `-target=`
  lines beside ~:546-555.
- [ ] 4.4 `reusable-release.yml` `release` job +
  `build-inngest-bootstrap-image.yml` `build` job: `environment:
  release-publish`; `build-inngest-config-bundle.yml` header note.
- [ ] 4.5 `terraform-target-parity.test.ts` pins: job↔env bindings,
  exactly-`{main}` membership for `inngest_config_signing` +
  `release_publish`, `-target=` presence, `release_publish` explicit-
  population assertion.
- [ ] 4.6 ADR-241 amendment: admission-gate environment class (fifth env,
  reviewer-less, no Tier-B secret), D2 enumeration annotated.

## 5. Verification

- [ ] 5.1 `python3 scripts/lint-gh-dedupe-shape.py` → `unclassified: 0`.
- [ ] 5.2 `bun test plugins/soleur/test/terraform-target-parity.test.ts` green.
- [ ] 5.3 Per-unit `.test.sh` + `infra-config-apply.test.sh` +
  `fresh-boot-parity.test.sh` + `soleur-host-bootstrap-observability.test.sh` green.
- [ ] 5.4 `systemd-analyze verify` on the five edited units (where the
  toolchain supports it in-repo, else the pin-suite equivalent).
- [ ] 5.5 Post-merge: targeted apply ran; read-back of both environments'
  branch policies shows exactly `main` (AC-A7); record evidence.
- [ ] 5.6 PR body carries `Closes #8780`, `Closes #9659`, `Closes #10078`,
  the `Reviewed-Coverage: sequential-fallback` disclosure, and the
  decision-challenges render.
