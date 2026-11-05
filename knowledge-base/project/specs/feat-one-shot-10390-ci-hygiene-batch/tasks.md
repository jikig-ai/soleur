---
title: Tasks — feat-one-shot-10390-ci-hygiene-batch
date: 2026-11-04
plan: knowledge-base/project/plans/2026-11-04-chore-ci-infra-hygiene-batch-plan.md
issues: [8780, 9659, 10078, 8525, 8013, 8080, 8839, 9943, 10136, 9074, 8624]
epic: 10390
---

# Tasks

## 1. Setup / verification (Phase 0)

- [x] 1.1 Re-run the dedupe census on this branch:
  `git grep -nE '=\$\([[:space:]]*gh (issue|pr) (list|search)' -- '.github/workflows/'`
  and classify every hit into fix / fail-closed / benign against the
  issue's three buckets.
- [x] 1.2 Re-run the web-host EnvironmentFile census over `*.service` +
  generator heredocs (`cloud-init.yml`, `soleur-host-bootstrap.sh`);
  confirm the seven-unit candidate set.
- [x] 1.3 `gh pr view 10928 --json files` — confirm the live-race PR's
  file set still only overlaps at `apply-web-platform-infra.yml`,
  `terraform-target-parity.test.ts`, `ADR-241`; re-read those three files
  before editing.
- [x] 1.4 Re-derive every line number the issues cite (~: markers).

## 2. Workstream B — #9659 dedupe normalization + lint (Phase 1)

- [x] 2.1 Rewrite each filing-path site (the issue's 12-file list +
  classified additions) to the fail-open `if ! VAR="$(…)"` or
  `|| { ::error::<slug>…; VAR=""; }` shape, preserving per-site slugs.
- [x] 2.2 Add `# dedupe: fail-closed <reason>` / `# dedupe: benign
  <reason>` markers on every non-normalized survivor.
- [x] 2.3 Write `scripts/lint-gh-dedupe-shape.py` (census + adjacency
  classification per Guard 1) printing `dedupe-shape: unclassified: <n>`.
- [x] 2.4 Write `scripts/lint-gh-dedupe-shape.test.sh` with the Guard 1
  mutation battery (incl. zero-hit vacuity arm + heredoc must-pass).
- [x] 2.5 Register the pair: `test-all.sh` run_suite lines,
  `suite-durations.tsv`, `suite-shard-legs.tsv`,
  `guard-vacuity-floor.test.sh` PROMOTED check.

## 3. Workstream C — #10078 EnvironmentFile conditioning (Phase 2)

- [x] 3.1 Add `ConditionPathExists=/etc/default/<file>` in `[Unit]` of
  `inngest-consumer-probe.service`, `web-bash-synthetic.service`,
  `web-git-data-probe.service`, `web-private-nic-guard.service`,
  `web-zot-consumer-probe.service`, each with a SKIP-VS-FAIL comment
  naming the boot-emit fatal channel + the unit's own heartbeat detector;
  `EnvironmentFile=` stays unprefixed.
- [x] 3.2 Add designed-loud comments to `webhook.service`, its
  `cloud-init.yml` embedded twin (lockstep), and the `vector.service`
  heredoc in `soleur-host-bootstrap.sh` — no condition added.
- [x] 3.3 Regenerate `WEBHOOK_SERVICE_B64` in `infra-config-apply.sh`
  (comment-only edit still changes bytes; stale pin refuses delivery).
- [x] 3.4 Update per-unit pins: condition-path-set ≡ envfile-path-set,
  unprefixed retention, no reset lines, negative pins on webhook/vector
  incl. heredoc extraction — in the per-unit `*.test.sh`,
  `soleur-host-bootstrap-observability.test.sh`, `infra-config-apply.test.sh`,
  `fresh-boot-parity.test.sh` as the pin inventory requires.

## 4. Workstream A — #8780 publish admission (Phase 3)

- [x] 4.1 `inngest-config-signing.tf`: `deployment_branch_policy` block +
  `github_repository_environment_deployment_policy.inngest_config_signing_main`
  (reviewers retained).
- [x] 4.2 Create `release-publish-environment.tf`: reviewer-less,
  secrets-free, main-only policy + `release_publish_main`, with the
  auto-create-hazard header comment.
- [x] 4.3 `apply-web-platform-infra.yml`: append the three `-target=`
  lines beside ~:546-555.
- [x] 4.4 `reusable-release.yml` `release` job +
  `build-inngest-bootstrap-image.yml` `build` job: `environment:
  release-publish`; `build-inngest-config-bundle.yml` header note.
- [x] 4.5 `terraform-target-parity.test.ts` pins: job↔env bindings,
  exactly-`{main}` membership for `inngest_config_signing` +
  `release_publish`, `-target=` presence, `release_publish` explicit-
  population assertion.
- [x] 4.6 ADR-241 amendment: admission-gate environment class (fifth env,
  reviewer-less, no Tier-B secret), D2 enumeration annotated.

## 5. Verification

- [x] 5.1 `python3 scripts/lint-gh-dedupe-shape.py` → `unclassified: 0`.
- [x] 5.2 `bun test plugins/soleur/test/terraform-target-parity.test.ts` green.
- [x] 5.3 Per-unit `.test.sh` + `infra-config-apply.test.sh` +
  `fresh-boot-parity.test.sh` + `soleur-host-bootstrap-observability.test.sh` green.
- [x] 5.4 `systemd-analyze verify` on the five edited units (where the
  toolchain supports it in-repo, else the pin-suite equivalent).
- [ ] 5.5 Post-merge: targeted apply ran; read-back of both environments'
  branch policies shows exactly `main` (AC-A7); record evidence.
- [ ] 5.6 PR body carries `Closes #8780`, `Closes #9659`, `Closes #10078`,
  the `Reviewed-Coverage: sequential-fallback` disclosure, and the
  decision-challenges render.

## 6. Workstream D — observability/probe-schema cluster (Phase 5)

- [x] 6.1 (#8525) `inngest-bootstrap.sh`: probe_schema 8→9, `data_luks=<blkid
  TYPE>` emit on both emit lines with sibling-identical sentinel contract;
  update every `probe_schema=8` consumer/pin
  (`git grep -n 'probe_schema' tests/ apps/ scripts/` census first).
- [x] 6.2 (#8525) Create `scripts/followthroughs/inngest-luks-field-8525.sh`
  + `.test.sh`; post the follow-through directive comment + `follow-through`
  label on #8525.
- [x] 6.3 (#8013) Rewrite the stale `NAMES ONLY, NEVER VALUES` comment block;
  post the corrective comment on #7978; record the live-row ULID-absence
  query evidence (or file `action-required` if the query is unreadable).
- [x] 6.4 (#8080) `RestartSec=5→300` on the inngest-server template with the
  class-naming comment (no `StartLimitBurst`); record the 55k/day figure on
  the Better Stack row of `knowledge-base/operations/expenses.md`.
- [x] 6.5 (#8839) Create `cron-agent-spawn-stale-settle` (stale-Working rows
  older than finish-timeout+margin, live-run discriminator check, settle via
  the shared settle path, `stale_working` dead-letter suffix); register in
  `cron-manifest.ts` + `EXPECTED_CRON_FUNCTIONS` + `cron-budgets.ts`; update
  `spawn-dead-letter.ts` COVERAGE + failure-reason list + triage runbook;
  test battery incl. live-run-must-survive row.
- [x] 6.6 (#9943) `git-data-cutover.yml` flip preconditions: heartbeat `up`
  + post-`boot_complete` `state=ok` predicate, refuse
  `verdict=liveness_unproven`, unreadable reads refuse closed; update the
  runbook hard item + `git-data-flag-precheck.sh` verdict docs if needed.

## 7. Workstream E — #10136 transit exceptions (Phase 6)

- [x] 7.1 Rewrite the Inngest connection row: leg-1 measured TLS
  (2026-10-26 flip + `tls-health` evidence), leg-2 exception anchored to
  the A7 record's dates/voids (`#10538` tracking).
- [x] 7.2 Zot x2 rows: ruled-decision record pointer, concrete `expires_on`,
  retire all "pending the CLO ruling" prose.
- [x] 7.3 Create `knowledge-base/legal/audits/<date>-zot-private-network-accepted-risk-10136.md`
  (A7 precedent form); post the accepted-risk record comment on #10136 for
  owner confirmation (single operator step).
- [x] 7.4 `lint-encryption-posture.py` + ledger vitest green.

## 8. Workstream F — legal (Phase 7)

- [x] 8.1 (#9074) DPD §2.3(o) store sentence corrected (canonical + mirror)
  — count defect + bearing determination; Last Updated note.
- [x] 8.2 (#9074) PA-13 (f) in-cell correction + superseded marker; sweep
  every `not personal-data-bearing`/`neither` repeat (PA-21/PA-22 quoting
  notes get markers); zero unmarked repeats grep-verified.
- [x] 8.3 (#8624) PA-14 dated-marker amendment (PA-21/22 form, dated
  2026-11-05), one `(encryption-posture ledger: …)` clause per live store;
  `records` entries on the ledger rows.
- [x] 8.4 (#8624) Workspace-encryption qualifier per CLO ruling on every
  published surface the `LUKS-encrypted|Encrypted workspace` grep finds;
  `legal-doc-shas.ts` re-pin; five legal-doc CI gates green locally.
- [x] 8.5 `compliance-posture.md` active-item updates for #9074/#8624.

## 9. Expansion verification

- [ ] 9.1 All new per-suite tests green; `git grep` censuses recorded.
- [ ] 9.2 PR body `Closes:` list covers all 11 issues; operator-step
  disclosure (#10136 record confirmation); decision-challenges render.
