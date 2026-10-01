# Always-on audit (PR 1, umbrella #9307)

Plan Phase 2. The 145-entry `ALWAYS_ON_SUITES` floor is 52% of light-group suite time and is what a docs-only diff
costs before any edge is considered. This audit asks, per suite, what it READS, and demotes it to declared edges
only when the evidence supports it.

## Method

- **Recorder.** `strace` is not installed on the operator host, so file access was recorded with `inotifywait -m -r -e open`
  over a detached worktree of the PR head (`node_modules` and `.git` excluded). Each always-on suite's registered argv ran
  SERIALLY from the repo root with a 2 s quiet gap between suites, and every OPEN event was attributed to the suite whose
  start/end window contained its timestamp. A directory opened as a directory means its LISTING was read.
- **Edge cover.** An enumerated directory becomes a directory edge when two or more non-code files, or six or more files,
  were read from it, or it was listed with nothing read; otherwise the exact files read are the edges. `__pycache__` is ignored.
- **Disqualifiers (the suite stays always-on).** Any of: the run exited non-zero or hit the 600 s cap; the suite or a script it
  executed uses `git diff|log|show|rev-list|merge-base|status`, `origin/main`, `--changed` or `--base` (its input is the diff, not
  files); it uses `git ls-files|grep|ls-tree` (a tree walk the open events under-report); it shells out to the network or an
  external service (`curl`, `gh`, `doppler`, vendor tokens); it reads the clock; it read from more than 8 second-level
  directories or over 700 files, or its cover exceeds 14 edges.
- **Limit.** Observed reads are evidence for the run that happened, not a proof for every input: a branch that reads a file only
  when a violation exists would be invisible. The disqualifiers are deliberately broad (the net/time scan covers shared helper
  libraries a suite sources, so it over-flags), which errs toward keeping a suite always-on. CI's full battery remains the
  authoritative gate for anything this local selection narrows.

## Result

- Audited 144 of 145 entries; `apps/web-platform [repo-wide+component]` is NOT audited and stays always-on (a vitest project whose subject is the repository by construction).
- **Demoted: 24.** Kept always-on: 120 audited + 1 unaudited = 121. `ALWAYS_ON_SUITES` 145 -> 121; `_MIN_ALWAYS_ON_DECLARED` 116 (new count minus 5).
- Summed suite time (`scripts/suite-durations.tsv`, light group): always-on 39.3 min before; the 24 demoted suites account for 0.5 min of it (1%). See the next section: the saving is in suite COUNT, not time.
- Five suites failed or timed out under the recorder (machine load average ~40-58 during the run) and are kept: `scripts/test-contention`, `scripts/test-all-runtime-ceiling`, `scripts/lint-orphan-test-suites-mutations-a`, `tests/scripts/infra-privileged-tier-census`, `scripts/battery-tag-authorship-mutations`.

## Where the time actually is

The 24 demoted suites are the cheap ones: **0.5 of the 39.3 minutes** of always-on suite time (1%). The count drops
145 -> 121, but the time barely moves, so the claim this audit supports is "a docs-only diff selects 24 fewer suites",
not "a docs-only diff is faster". About 80% of the remaining 38.7 minutes is nine suites:

| Suite | Seconds | Cumulative | Why it stays (this PR) |
|---|---|---|---|
| `scripts/test-all-affected` | 442 | 19% | the runner's own battery; walks the whole registration tree; broad |
| `scripts/lint-orphan-test-suites-mutations-b` | 424 | 37% | census mutation battery; whole test tree |
| `scripts/lint-orphan-test-suites-mutations-a` | 422 | 55% | same; also hit the 600 s cap under load (rc 124) |
| `scripts/test-contention` | 134 | 61% | failed under the recorder (rc 1) |
| `plugins/soleur/test/operator-ack-guard.test.sh` | 108 | 66% | reads 1451 files across the tree |
| `tests/scripts/sentry-alert-live-fidelity` | 102 | 70% | network / external state |
| `scripts/test-all-infra-coverage-notice` | 83 | 74% | runner-SUT; 1008 files |
| `scripts/lint-orphan-test-suites` | 68 | 77% | the census itself; whole test tree |
| `plugins/soleur/test/hook-input-classification-mutation.test.sh` | 66 | 80% | 16,636 files opened |

These are runner-SUT and census batteries: their subject is `scripts/test-all.sh`, its libraries and the registration tree,
so most diffs cannot change their verdict, but each walks far more than a handful of files, and the observed-read evidence
cannot bound that safely. Narrowing them is a per-suite design decision (declare the SUT files, accept that new
registrations elsewhere would no longer re-run them locally) and is tracked as a follow-up rather than done here.

## Table

`files` = distinct repo files opened; `dirs` = distinct second-level directories; `flags` = disqualifiers (`-` = none).

| Suite | Verdict | rc | files | dirs | flags | Edges / evidence |
|---|---|---|---|---|---|---|
| `apps/web-platform/scripts/lint-migration-fk-preconditions.test.sh` | **demoted** | 0 | 272 | 1 | - | `apps/web-platform/scripts/lint-migration-fk-preconditions.sh` `apps/web-platform/scripts/lint-migration-fk-preconditions.test.sh` `apps/web-platform/supabase/migrations/` |
| `apps/web-platform/test/parse-gitleaks-allowlists` | **demoted** | 0 | 3 | 2 | - | `.gitleaks.toml` `apps/web-platform/scripts/parse-gitleaks-allowlists.mjs` `apps/web-platform/test/__synthesized__/parse-gitleaks-allowlists.test.sh` |
| `plugins/soleur/test/gitleaks-rules.test.sh` | **demoted** | 0 | 4 | 3 | - | `.gitleaks.toml` `.gitleaksignore` `plugins/soleur/test/gitleaks-rules.test.sh` `plugins/soleur/test/lib/gitleaks-probe.sh` |
| `plugins/soleur/test/terraform-drift-step-order.test.sh` | **demoted** | 0 | 2 | 2 | - | `.github/workflows/scheduled-terraform-drift.yml` `plugins/soleur/test/terraform-drift-step-order.test.sh` |
| `scripts/check-pa-22-live` | **demoted** | 0 | 2 | 2 | - | `knowledge-base/legal/article-30-register.md` `scripts/check-pa-22.sh` |
| `scripts/check-pa-22-unit` | **demoted** | 0 | 3 | 3 | - | `knowledge-base/legal/article-30-register.md` `scripts/check-pa-22.sh` `scripts/check-pa-22.test.sh` |
| `scripts/check-tom4-rls-posture` | **demoted** | 0 | 399 | 6 | - | `apps/web-platform/supabase/migrations/` `docs/legal/` `knowledge-base/legal/` `plugins/soleur/docs/pages/legal/` `scripts/check-tom4-rls-posture.sh` `scripts/check-tom4-rls-posture.test.sh` |
| `scripts/check-tom4-rls-posture-live` | **demoted** | 0 | 298 | 5 | - | `apps/web-platform/supabase/migrations/` `docs/legal/` `knowledge-base/legal/` `plugins/soleur/docs/pages/legal/` `scripts/check-tom4-rls-posture.sh` |
| `scripts/domain-model-drift` | **demoted** | 0 | 3 | 2 | - | `plugins/soleur/scripts/domain-model-drift.sh` `plugins/soleur/scripts/lib/domain-model-lib.sh` `scripts/domain-model-drift.test.sh` |
| `scripts/frontmatter-strip-parity` | **demoted** | 0 | 10 | 3 | - | `bunfig.toml` `package.json` `scripts/` |
| `scripts/lint-agents-compound-sync-unit` | **demoted** | 0 | 2 | 2 | - | `scripts/lint-agents-compound-sync.sh` `scripts/lint-agents-compound-sync.test.sh` |
| `scripts/lint-agents-rule-budget-live` | **demoted** | 0 | 4 | 4 | - | `AGENTS.md` `AGENTS.rules.md` `scripts/lib/frontmatter-strip/strip.py` `scripts/lint-agents-rule-budget.py` |
| `scripts/lint-agents-rule-budget-unit` | **demoted** | 0 | 5 | 5 | - | `AGENTS.md` `AGENTS.rules.md` `scripts/lib/frontmatter-strip/strip.py` `scripts/lint-agents-rule-budget.py` `scripts/lint-agents-rule-budget.test.sh` |
| `scripts/lint-guard-contract` | **demoted** | 0 | 2 | 2 | - | `scripts/lint-guard-contract.py` `scripts/lint-guard-contract.test.sh` |
| `scripts/lint-rule-ids-live` | **demoted** | 0 | 5 | 5 | - | `AGENTS.md` `AGENTS.rules.md` `scripts/_agents_md_sections.py` `scripts/lint-rule-ids.py` `scripts/retired-rule-ids.txt` |
| `scripts/lint-window-closure-assertion` | **demoted** | 0 | 2 | 2 | - | `scripts/lint-window-closure-assertion.py` `scripts/lint-window-closure-assertion.test.sh` |
| `scripts/lint-workflow-run-body-syntax` | **demoted** | 0 | 81 | 2 | - | `.github/workflows/` `scripts/lint-workflow-run-body-syntax.py` |
| `scripts/marketplace-manifest-validate` | **demoted** | 0 | 3 | 3 | - | `infra/github/soleur-marketplace-manifest.json` `scripts/marketplace-manifest-validate.sh` `scripts/marketplace-manifest-validate.test.sh` |
| `scripts/probe-legal-corpus-truth-live` | **demoted** | 0 | 8 | 4 | - | `docs/legal/data-protection-disclosure.md` `docs/legal/gdpr-policy.md` `docs/legal/privacy-policy.md` `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` `plugins/soleur/docs/pages/legal/gdpr-policy.md` `plugins/soleur/docs/pages/legal/privacy-policy.md` `scripts/probe-legal-corpus-truth.sh` `scripts/probe_legal_corpus_truth.py` |
| `scripts/tenant-dpa-register-guard-live` | **demoted** | 0 | 2 | 2 | - | `knowledge-base/legal/tenant-dpa-register.md` `scripts/tenant-dpa-register-guard.sh` |
| `scripts/tenant-dpa-register-guard-unit` | **demoted** | 0 | 4 | 4 | - | `knowledge-base/engineering/operations/runbooks/tenant-provisioning.md` `knowledge-base/legal/tenant-dpa-register.md` `scripts/tenant-dpa-register-guard.sh` `scripts/tenant-dpa-register-guard.test.sh` |
| `scripts/tunnel-connector-census` | **demoted** | 0 | 2 | 2 | - | `scripts/tunnel-connector-census.sh` `scripts/tunnel-connector-census.test.sh` |
| `scripts/verify-lockfile-guards` | **demoted** | 0 | 2 | 2 | - | `scripts/verify-lockfile-guards.sh` `scripts/verify-lockfile-guards.test.sh` |
| `scripts/verify-marketplace-ruleset` | **demoted** | 0 | 3 | 3 | - | `scripts/marketplace-ruleset-canonical-bypass-actors.json` `scripts/verify-marketplace-ruleset.sh` `scripts/verify-marketplace-ruleset.test.sh` |
| `.claude/hooks/hookeventname-coverage.test.sh` | kept | 0 | 55 | 4 | git-diff,git-enum,net,time |  |
| `.claude/hooks/incident-sandbox-coverage.test.sh` | kept | 0 | 2753 | 307 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `.claude/hooks/kb-domain-allowlist-guard.test.sh` | kept | 0 | 9 | 3 | git-diff,git-enum,net,time |  |
| `.claude/hooks/settings-hook-exec-bit.test.sh` | kept | 0 | 3 | 2 | git-diff,git-enum |  |
| `apps/web-platform/scripts/assert-byok-rules-exist.test.sh` | kept | 0 | 2 | 1 | net |  |
| `apps/web-platform/scripts/lib/no-cross-context-import.test.sh` | kept | 0 | 916 | 2 | broad,git-enum,wide-cover |  |
| `apps/web-platform/scripts/seed-live-verify-user.test.sh` | kept | 0 | 4 | 2 | net |  |
| `blog-link-validation` | kept | 0 | 467 | 38 | broad |  |
| `plugins/soleur/skills/eval-harness/test/registry-completeness.test.sh` | kept | 0 | 1247 | 2 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `plugins/soleur/test/auto-close-scanner.test.sh` | kept | 0 | 9 | 1 | net |  |
| `plugins/soleur/test/c4-count-parity.test.sh` | kept | 0 | 98 | 5 | git-enum,net |  |
| `plugins/soleur/test/check-deps-adapter-drift.test.sh` | kept | 0 | 12 | 1 | net |  |
| `plugins/soleur/test/debug-probe-residue.test.sh` | kept | 0 | 6224 | 455 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `plugins/soleur/test/fanout-suite-scope.test.sh` | kept | 0 | 17 | 9 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `plugins/soleur/test/fixture-cd-containment.test.sh` | kept | 0 | 1338 | 275 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `plugins/soleur/test/fixture-dir-operand-assert.test.sh` | kept | 0 | 1339 | 275 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `plugins/soleur/test/fixture-env-adoption.test.sh` | kept | 0 | 1809 | 11 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `plugins/soleur/test/gdpr-gate-glob-liveness.test.sh` | kept | 0 | 3 | 1 | net |  |
| `plugins/soleur/test/gitleaks-merge-commit.test.sh` | kept | 0 | 6 | 3 | git-diff,net |  |
| `plugins/soleur/test/hook-input-classification-mutation.test.sh` | kept | 0 | 16636 | 461 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `plugins/soleur/test/kb-caches-untracked.test.sh` | kept | 0 | 2 | 2 | git-enum |  |
| `plugins/soleur/test/lint-bot-synthetic-completeness.test.sh` | kept | 0 | 4 | 2 | git-diff,net |  |
| `plugins/soleur/test/lint-bot-synthetic-statuses.test.sh` | kept | 0 | 4 | 2 | git-diff,net |  |
| `plugins/soleur/test/lint-distribution-content.test.sh` | kept | 0 | 4 | 2 | net |  |
| `plugins/soleur/test/operator-ack-guard.test.sh` | kept | 0 | 1451 | 277 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `plugins/soleur/test/operator-script.test.sh` | kept | 0 | 285 | 1 | git-diff,git-enum,net,time |  |
| `plugins/soleur/test/preflight-check10-suite-integrity.test.sh` | kept | 0 | 2193 | 5 | broad,git-diff,git-enum,net,wide-cover |  |
| `plugins/soleur/test/reusable-release-caller-permissions.test.sh` | kept | 0 | 81 | 2 | net |  |
| `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh` | kept | 0 | 726 | 2 | broad,git-diff,git-enum,net,time |  |
| `plugins/soleur/test/scripts-shard-totality.test.sh` | kept | 0 | 1316 | 282 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `plugins/soleur/test/terraform-drift-sentry-leg.test.sh` | kept | 0 | 37 | 4 | net |  |
| `plugins/soleur/test/token-drift-workflow-causes.test.sh` | kept | 0 | 54 | 4 | git-diff,net,time |  |
| `plugins/soleur/test/vendor-drift-classify.test.sh` | kept | 0 | 9 | 1 | git-diff,net |  |
| `plugins/soleur/test/vendor-drift-workflow.test.sh` | kept | 0 | 12 | 2 | git-diff,net |  |
| `plugins/soleur/test/workflow-run-deploy-invariants.test.sh` | kept | 0 | 12983 | 341 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `scripts/alarm-issue-filing-guard` | kept | 0 | 82 | 3 | net |  |
| `scripts/assert-dependabot-drain-live` | kept | 0 | 5 | 5 | net |  |
| `scripts/assert-dependabot-drain-unit` | kept | 0 | 2 | 2 | net |  |
| `scripts/battery-ref-guard` | kept | 0 | 4 | 4 | git-diff,git-enum,net,time |  |
| `scripts/battery-tag-authorship` | kept | 0 | 1188 | 283 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `scripts/battery-tag-authorship-mutations` | kept | 124 | 1188 | 283 | broad,git-diff,git-enum,net,rc!=0,time,wide-cover |  |
| `scripts/betterstack-assert-absence` | kept | 0 | 2 | 2 | net |  |
| `scripts/betterstack-ingest-parity` | kept | 0 | 4815 | 337 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `scripts/check-cloudflare-token-drift` | kept | 0 | 128 | 11 | broad,net,time |  |
| `scripts/cosign-verify-live-8037` | kept | 0 | 2 | 1 | net,time |  |
| `scripts/cron-artifact-age` | kept | 0 | 2 | 2 | git-diff,time |  |
| `scripts/devin-docs-drift-check` | kept | 0 | 2 | 2 | net,time |  |
| `scripts/digest-oracle-guard` | kept | 0 | 2 | 2 | net |  |
| `scripts/ensure-kb-index` | kept | 0 | 3 | 3 | git-diff,git-enum,time |  |
| `scripts/expenses-verify-by-check` | kept | 0 | 2 | 2 | time |  |
| `scripts/follow-through-closure-guard` | kept | 0 | 1337 | 276 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `scripts/followthrough-exec-bit` | kept | 0 | 1 | 1 | git-enum |  |
| `scripts/followthrough-varq-ban` | kept | 0 | 141 | 3 | git-diff,git-enum,net,time |  |
| `scripts/followthrough-varq-ban-live` | kept | 0 | 140 | 2 | git-diff,git-enum,net,time |  |
| `scripts/generate-kb-index-live` | kept | 0 | 7120 | 12 | broad |  |
| `scripts/guard-vacuity-floor` | kept | 0 | 581 | 119 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `scripts/inngest-liveness-classify` | kept | 0 | 2 | 2 | net |  |
| `scripts/lib/inngest-probe-row.test.sh` | kept | 0 | 4307 | 269 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `scripts/lint-agents-compound-sync-live` | kept | 0 | 10 | 8 | net |  |
| `scripts/lint-agents-enforcement-tags-live` | kept | 0 | 14 | 5 | net,wide-cover |  |
| `scripts/lint-agents-enforcement-tags-unit` | kept | 0 | 112 | 35 | broad,net,wide-cover |  |
| `scripts/lint-anthropic-content-position-live` | kept | 0 | 1787 | 196 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `scripts/lint-credential-path-literals` | kept | 0 | 244 | 3 | git-diff,net |  |
| `scripts/lint-diagnosis-claims` | kept | 0 | 497 | 159 | broad,git-diff,git-enum,net,time |  |
| `scripts/lint-doppler-description-length-live` | kept | 0 | 82 | 4 | net,wide-cover |  |
| `scripts/lint-dual-lockfile` | kept | 0 | 3 | 3 | git-enum |  |
| `scripts/lint-dual-lockfile-live` | kept | 0 | 4 | 4 | git-enum |  |
| `scripts/lint-encryption-posture` | kept | 0 | 3 | 3 | net,time |  |
| `scripts/lint-guard-contract-live` | kept | 0 | 1655 | 2 | broad |  |
| `scripts/lint-infra-no-human-steps` | kept | 0 | 2 | 2 | git-diff,time |  |
| `scripts/lint-legal-mirror-drift-baseline-live` | kept | 0 | 22 | 5 | git-diff,time |  |
| `scripts/lint-legal-mirror-drift-baseline-unit` | kept | 0 | 4 | 3 | git-diff,time |  |
| `scripts/lint-legal-registers-live` | kept | 0 | 84 | 4 | git-diff |  |
| `scripts/lint-legal-registers-unit` | kept | 0 | 85 | 5 | git-diff |  |
| `scripts/lint-legal-scope-block-placement-live` | kept | 0 | 2 | 2 | git-diff |  |
| `scripts/lint-legal-scope-block-placement-unit` | kept | 0 | 21 | 5 | git-diff |  |
| `scripts/lint-migrated-rule-ids-live` | kept | 0 | 11189 | 95 | broad,git-diff,wide-cover |  |
| `scripts/lint-migrated-rule-ids-unit` | kept | 0 | 11190 | 96 | broad,git-diff,wide-cover |  |
| `scripts/lint-orphan-test-suites` | kept | 0 | 848 | 228 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `scripts/lint-orphan-test-suites-mutations-a` | kept | 124 | 671 | 228 | broad,git-diff,git-enum,net,rc!=0,time,wide-cover |  |
| `scripts/lint-orphan-test-suites-mutations-b` | kept | 0 | 671 | 228 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `scripts/lint-rule-bodies-live` | kept | 0 | 6 | 6 | git-diff |  |
| `scripts/lint-shell-capture-exit` | kept | 0 | 2 | 2 | git-enum |  |
| `scripts/lint-shell-capture-exit-live` | kept | 0 | 1339 | 277 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `scripts/lint-shell-trace-credential-refusal` | kept | 0 | 51 | 11 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `scripts/lint-shell-trace-credential-refusal-repo` | kept | 0 | 605 | 165 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `scripts/lint-supabase-deprecated-endpoints-unit` | kept | 0 | 4886 | 378 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `scripts/lint-trap-tempfile-ownership` | kept | 0 | 1358 | 278 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `scripts/lint-window-closure-assertion-live` | kept | 0 | 1359 | 8 | broad,git-diff,git-enum,net,time |  |
| `scripts/lint-workflow-errexit-capture` | kept | 0 | 127 | 10 | broad,net |  |
| `scripts/lint-workflow-errexit-capture-live` | kept | 0 | 90 | 3 | net |  |
| `scripts/lint-workflow-install-sites` | kept | 0 | 2 | 2 | git-enum |  |
| `scripts/lint-workflow-install-sites-live` | kept | 0 | 851 | 167 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `scripts/lint-workflow-issue-write-scope` | kept | 0 | 2 | 2 | git-diff,net |  |
| `scripts/lint-workflow-issue-write-scope-live` | kept | 0 | 81 | 2 | git-diff,net |  |
| `scripts/lint-workflow-step-env-refs` | kept | 0 | 82 | 3 | net,time |  |
| `scripts/lint-workflow-step-env-refs-live` | kept | 0 | 81 | 2 | net,time |  |
| `scripts/marketplace-drift-check` | kept | 0 | 3 | 3 | net,time |  |
| `scripts/prod-version-drift-check` | kept | 0 | 7 | 4 | git-diff,net,time |  |
| `scripts/rename-guard` | kept | 0 | 4 | 3 | git-diff |  |
| `scripts/review-reminder-liveness` | kept | 0 | 2 | 2 | net |  |
| `scripts/rule-metrics-aggregate` | kept | 0 | 5 | 4 | git-diff,net,time |  |
| `scripts/ship-incident-pir-gate-mutations` | kept | 0 | 74 | 3 | git-diff,net,wide-cover |  |
| `scripts/skill-freshness-aggregate` | kept | 0 | 2 | 2 | time |  |
| `scripts/suite-exit-class-parity` | kept | 0 | 4 | 4 | git-diff,git-enum,net,time |  |
| `scripts/sweep-followthroughs` | kept | 0 | 2 | 2 | git-enum,net,time |  |
| `scripts/test-all-affected` | kept | 0 | 2181 | 345 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `scripts/test-all-capacity-signal` | kept | 0 | 4 | 3 | git-diff,git-enum,net,time |  |
| `scripts/test-all-enumerate-toolchain` | kept | 0 | 543 | 159 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `scripts/test-all-group-affected` | kept | 0 | 4 | 3 | git-diff,git-enum,net,time |  |
| `scripts/test-all-infra-coverage-notice` | kept | 0 | 1008 | 305 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `scripts/test-all-killed-classification` | kept | 0 | 14 | 8 | git-diff,git-enum,net,time,wide-cover |  |
| `scripts/test-all-orphan-log-retention` | kept | 0 | 12 | 7 | git-diff,git-enum,net,time,wide-cover |  |
| `scripts/test-all-runtime-ceiling` | kept | 1 | 11 | 7 | git-diff,git-enum,net,rc!=0,time,wide-cover |  |
| `scripts/test-all-webplat-gate` | kept | 0 | 3 | 3 | git-diff,git-enum,net,time |  |
| `scripts/test-contention` | kept | 1 | 3 | 3 | git-diff,rc!=0,time |  |
| `scripts/watch-live-verify-pass` | kept | 0 | 2 | 2 | net |  |
| `tests/scripts/infra-privileged-tier-census` | kept | 1 | 205 | 24 | broad,git-diff,git-enum,net,rc!=0,time,wide-cover |  |
| `tests/scripts/no-tofu-ssh` | kept | 0 | 5649 | 451 | broad,git-diff,git-enum,net,time,wide-cover |  |
| `tests/scripts/sentry-alert-live-fidelity` | kept | 0 | 13 | 4 | git-enum,net |  |
