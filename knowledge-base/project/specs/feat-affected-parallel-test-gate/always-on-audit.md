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
- **Audited as demotable: 24. Demoted: 23.** `scripts/domain-model-drift` passed the audit and was put back (see "What the demotion costs"). Kept always-on: 120 audited + 1 unaudited + 1 put back = 122. `ALWAYS_ON_SUITES` 145 -> 122; `_MIN_ALWAYS_ON_DECLARED` stays 116 (set when the count was 121).
- Summed suite time (`scripts/suite-durations.tsv`, light group): always-on 39.3 min before; the 23 demoted suites account for 0.5 min of it (1%). Two always-on labels have no row in `suite-durations.tsv` (`scripts/battery-tag-authorship-mutations`, which hit the 600 s cap under the recorder, and `apps/web-platform [repo-wide+component]`), so 39.3 min and every share computed from it are lower bounds. See the next section: the saving is in suite COUNT, not time.
- Five suites failed or timed out under the recorder (machine load average ~40-58 during the run) and are kept: `scripts/test-contention`, `scripts/test-all-runtime-ceiling`, `scripts/lint-orphan-test-suites-mutations-a`, `tests/scripts/infra-privileged-tier-census`, `scripts/battery-tag-authorship-mutations`.

## Where the time actually is

The 23 demoted suites are the cheap ones: **0.5 of the 39.3 minutes** of always-on suite time (1%). The count drops
145 -> 122, but the time barely moves, so the claim this audit supports is "a docs-only diff selects 23 fewer suites",
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

Six of the nine (1573 of the 1849 seconds in the table) are runner-SUT or census batteries: their subject is
`scripts/test-all.sh`, its libraries and the registration tree, so most diffs cannot change their verdict, but each walks far
more than a handful of files, and the observed-read evidence cannot bound that safely. The other three are whole-corpus
scanners or an external-state suite. Narrowing any of them is a per-suite design decision (declare the SUT files, accept that
new registrations elsewhere would no longer re-run them locally) and is tracked as a follow-up rather than done here.

## What the demotion costs

A demotion is not free on the local gate. An always-on label skips derivation in the affected pre-pass (0.0-1.5 ms); an edge
label runs the full source-closure derive. Measured on a loaded host (load average 30-64, one run, so treat the figures as
orders of magnitude): the 23 demoted suites cost about 2 s of pre-pass together, but `scripts/domain-model-drift` alone cost
82 s to save 0.9 s of suite time (its test file names `test-all.sh` in a comment, which the closure follows), so it was put
back in `ALWAYS_ON_SUITES`. The pre-pass as a whole is about 11 minutes of CPU on every local `--affected` run regardless of
the diff, and 8 of 533 registrations are 73% of it (`scripts/orphan-process-reaper` 111 s, `playwright-mcp-redact-proxy` 101 s,
`scripts/domain-model-drift` 82 s, `memory-backstop-resolve` 79 s, `guardrails` 56 s, `resolve-regenerable-conflicts` 47 s,
`phase-16` 28 s, `pkill-self-match-guard` 18 s). That fixed cost, not the always-on count, is what a docs-only diff pays first;
making the closure derive cheap (memoise by blob hash, or stop following comment tokens) is the highest-value follow-up and
is tracked on #9307.

## What the dropped-consumer ratchet found about the demotions

Run after the demotions, the ratchet reported `knowledge-base/` references for four demoted suites. Read against the
sources: `scripts/tenant-dpa-register-guard-live` really reads `tenant-provisioning.md` (a gap the one audited run did not
exercise) and the edge was added; `scripts/lint-agents-compound-sync-unit` names the compound-promote runbook only inside
fixtures it builds under a scratch root, and `apps/web-platform/test/parse-gitleaks-allowlists` and
`scripts/lint-rule-ids-live` name no `knowledge-base/` path in their declared files (the one-hop scan reaches them through
another script), so their baseline rows are scan false positives rather than reads. The baseline does not mark which is which;
this paragraph is the only record. That one of four demoted suites had a real uncovered read, in a one-run audit, is the
reason the audit is described as evidence for the run that happened and not a proof.

## Reproducing the recorder

The recorder and attribution scripts were session scratch and are not committed. The method is small enough to redo:

1. `git worktree add --detach <dir> <sha>`; start `inotifywait -m -r -e open --format '%T|%e|%w%f' --timefmt '%s'` over it
   with `.git` and `node_modules` excluded, appending to one log.
2. For each always-on label, run its registered argv (from `test-all.sh --enumerate-commands all`) serially from `<dir>`,
   noting start and end epoch seconds and the exit code, with a 2 s gap between suites.
3. Attribute each logged OPEN to the suite whose window contains its timestamp; a `ISDIR` flag marks a directory listing.
4. Apply the cover and disqualifier rules in the Method section. inotify queue overflow was not checked for.

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
| `scripts/domain-model-drift` | **kept (derive cost)** | 0 | 3 | 2 | - | `plugins/soleur/scripts/domain-model-drift.sh` `plugins/soleur/scripts/lib/domain-model-lib.sh` `scripts/domain-model-drift.test.sh` |
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

## Addendum — 2026-10-01 (#9307, correction to "What the demotion costs")

Appended, not edited. The per-registration cost attribution above is first-touch attribution: the per-file memo
moves a shared closure's cost onto whichever registration scans it first, so the eight named registrations were not
expensive suites. The measured cost on a quiet host and what changed are in ADR-242, Amendment — 2026-10-01
(decision 16, corrected figures for decision 15). Re-pricing `scripts/domain-model-drift` follows with a committed
recorder.


## Round 2 — 2026-10-03 (committed recorder, PR-B of #9307)

**This section supersedes the "one audited run" caveat of ADR-242 decision 15.** Round 1 above was one run of session-scratch
`inotifywait` scripts. Round 2 re-prices the 23 suites it demoted (plus the suite put back, `scripts/domain-model-drift`, decided
in Phase 2.6 after the runner leaf) with `scripts/audit-suite-reads.sh`, which is committed, tested (the verdict function by 140 rows
including a live queue-overflow arm that runs in CI) and reads inotify through `scripts/lib/inotify-open-recorder.py`, because
`inotifywait` was measured on this host to deliver exactly 16,384 events for 17,500 opens while printing no overflow record (a
python3 `ctypes` reader on the same scenario received the kernel's `IN_Q_OVERFLOW`). Round 1 did not check for overflow at all.

- **Command.** `bash scripts/audit-suite-reads.sh record --rev <sha> --cover-from-selection --mode demote --max-load 8 --only <23 labels>`
  against audited revision `d73eee35b8887a10d56a5496ef54ba23d5229f98` (full SHA stamped into every row), recorder source at `commit d73eee35b8 (scripts/audit-suite-reads.sh)`; each suite ran twice, serially,
  from a private `git archive` checkout under `env -i` with a scratch PATH and no network, in its own process group. `--max-load 8`
  because this host has 16 cores and its idle load average sits near 4-5 from other sessions (the default 4.0 refused rows with `load_refused` on the
  first attempt; those rows are not counted anywhere below).
- **Phase 0.5 prototype gate (static probe scan over the 24 candidate suite files).** 15 of 24 suites have at least one file-test /
  `stat` / `ls` / `find` operand the scan cannot resolve (a `$VAR`); the plan's threshold is 5. Reading the 25 flagged lines, each operand is a variable
  whose name marks it as the suite's own SUT, a helper, a data file or a scratch directory the suite created (`$LINT`, `$SUT`, `$REG`,
  `$WF`, `$CANONICAL`, `$t5_tmp`, ...), but the scan resolves none of them, so it cannot confirm that any lies inside the cover. **The static scan therefore has low resolving power, and the conservative rule applies as designed: an
  unresolved probe disqualifies.** A suite is only ever demoted on evidence; the cost of the rule is that a suite whose only flag is an
  unprovable guard goes back to always-on (a run of the suite on every local diff; the 23 suites sum to at most the 0.5 minute Round 1 measured).
- **Outcome (23 suites).** demotable 3, disqualified 14 (12 of them only for an unresolved probe operand, 2 for a
  carried-disqualifier regex hit), uncovered 4, unreliable 2. Disqualified and uncovered suites (18) are re-promoted
  in `scripts/lib/test-affected-paths.sh` and their now-dormant `AFFECTED_*_PATHS` arrays are deleted in the same commit.
  `${#ALWAYS_ON_SUITES[@]}` 120 -> 138 (measured by sourcing the lib on `origin/main` and on this tree; the plan's "119" was one stale).
  `_MIN_ALWAYS_ON_DECLARED` stays 116 (the count rose; the floor is never raised).
- **Unreliable rows.** `scripts/lint-rule-ids-live` (`contaminated`: the suite dirties the private checkout) and
  `scripts/check-tom4-rls-posture` (`rc=1` inside the sandbox) were each recorded unreliable on the original run and again on retry 1
  (same non-load reasons both times); a third attempt was refused for host load (load average 9.7 against `--max-load 8`) and counts
  as no evidence. Per the plan an unreliable suite is left as it is (still demoted with its Round 1 evidence): **it has no Round 2
  evidence either way, and this document does not claim it does.**

| Suite | Verdict | Reason | rc | files | dirs | unresolved probes | load1 | Action |
|---|---|---|---|---|---|---|---|---|
| `scripts/lint-rule-ids-live` | unreliable | contaminated | 0 | - | - | - | 5.04 | left as is (retried, see below) |
| `scripts/lint-agents-rule-budget-live` | uncovered | reads-outside-cover | 0 | 5 | 5 | 0 | 5.04 | re-promoted to ALWAYS_ON_SUITES |
| `scripts/lint-agents-rule-budget-unit` | disqualified | unresolved-probe | 0 | 6 | 6 | 1 | 4.95 | re-promoted to ALWAYS_ON_SUITES |
| `scripts/lint-agents-compound-sync-unit` | demotable | ok | 0 | 2 | 2 | 0 | 4.95 | kept demoted |
| `scripts/lint-workflow-run-body-syntax` | uncovered | reads-outside-cover | 0 | 81 | 2 | 0 | 4.80 | re-promoted to ALWAYS_ON_SUITES |
| `scripts/verify-lockfile-guards` | disqualified | unresolved-probe | 0 | 2 | 2 | 1 | 4.65 | re-promoted to ALWAYS_ON_SUITES |
| `scripts/marketplace-manifest-validate` | disqualified | regex | 0 | 3 | 3 | 2 | 4.65 | re-promoted to ALWAYS_ON_SUITES |
| `scripts/verify-marketplace-ruleset` | disqualified | unresolved-probe | 0 | 3 | 3 | 2 | 4.60 | re-promoted to ALWAYS_ON_SUITES |
| `scripts/check-tom4-rls-posture` | unreliable | rc | 1 | - | - | - | 4.71 | left as is (retried, see below) |
| `scripts/check-tom4-rls-posture-live` | uncovered | reads-outside-cover | 0 | 302 | 5 | 0 | 4.71 | re-promoted to ALWAYS_ON_SUITES |
| `scripts/lint-guard-contract` | disqualified | unresolved-probe | 0 | 2 | 2 | 1 | 4.50 | re-promoted to ALWAYS_ON_SUITES |
| `scripts/lint-window-closure-assertion` | disqualified | unresolved-probe | 0 | 2 | 2 | 1 | 4.38 | re-promoted to ALWAYS_ON_SUITES |
| `scripts/tenant-dpa-register-guard-unit` | disqualified | regex | 0 | 4 | 4 | 2 | 4.75 | re-promoted to ALWAYS_ON_SUITES |
| `scripts/tenant-dpa-register-guard-live` | disqualified | unresolved-probe | 0 | 2 | 2 | 1 | 4.75 | re-promoted to ALWAYS_ON_SUITES |
| `scripts/probe-legal-corpus-truth-live` | uncovered | reads-outside-cover | 0 | 8 | 4 | 0 | 4.75 | re-promoted to ALWAYS_ON_SUITES |
| `scripts/check-pa-22-unit` | disqualified | unresolved-probe | 0 | 3 | 3 | 2 | 4.75 | re-promoted to ALWAYS_ON_SUITES |
| `scripts/check-pa-22-live` | disqualified | unresolved-probe | 0 | 2 | 2 | 1 | 4.75 | re-promoted to ALWAYS_ON_SUITES |
| `scripts/tunnel-connector-census` | demotable | ok | 0 | 2 | 2 | 0 | 5.09 | kept demoted |
| `apps/web-platform/test/parse-gitleaks-allowlists` | demotable | ok | 0 | 3 | 2 | 0 | 5.09 | kept demoted |
| `scripts/frontmatter-strip-parity` | disqualified | unresolved-probe | 0 | 1 | 1 | 2 | 5.09 | re-promoted to ALWAYS_ON_SUITES |
| `plugins/soleur/test/gitleaks-rules.test.sh` | disqualified | unresolved-probe | 0 | 3 | 2 | 1 | 5.09 | re-promoted to ALWAYS_ON_SUITES |
| `plugins/soleur/test/terraform-drift-step-order.test.sh` | disqualified | unresolved-probe | 0 | 2 | 2 | 1 | 5.09 | re-promoted to ALWAYS_ON_SUITES |
| `apps/web-platform/scripts/lint-migration-fk-preconditions.test.sh` | disqualified | unresolved-probe | 0 | 276 | 1 | 1 | 5.09 | re-promoted to ALWAYS_ON_SUITES |

`files` = distinct repo files opened; `dirs` = distinct second-level directories; `unresolved probes` = file-test / `stat` / `ls` / `find`
operands containing a `$VAR`. Blind spots are the script header's (probes of missing files produce no open event; directories created
mid-run; window-boundary events; `env -i` and no network can change what a suite reads; hardlink and symlink aliasing).

### Ratchet breadth (D2) — rows added to the baseline and their classification

The dropped-consumer ratchet gained one read form (a registration naming a directory and no code file: `bun test plugins/soleur/`).
It found one real gap: the `plugins/soleur` suite's test files read ADRs, the committed LikeC4 model, runbooks and legal/brand
documents, yet a knowledge-base-only diff never selected it. **Real reads, edge added** (`AFFECTED_PLUGINS_SOLEUR_PATHS`): the ADR,
diagram and runbook directories, `compliance-posture.md`, `recommended-tools.md`, `brand-guide.md`, `vision.md`, and the one spec directory
`terraform-target-parity.test.ts` reads. **Six rows remain in the baseline, each classified `false-positive` with its reason in the
baseline file** (fixture strings and scratch-rooted joins, the `knowledge-base` root used as a join base, and a timestamp-renamed
archive copy of a file whose live location is covered). Three rows of the previous baseline (`knowledge-base/../../..` and
`knowledge-base/project/plans/../../..`) disappeared because existence is now decided by git-tracked paths, so a `..` traversal string
and a gitignored generated file (`knowledge-base/INDEX.md`) cannot change the baseline between checkouts. The string forms
`${VAR:-knowledge-base/...}` (3 suites), bare `find|ls|grep|cd knowledge-base` (5 suites), `$PWD/knowledge-base` and a variable
assigned the bare literal (0 suites each) were measured against the registrations and are NOT implemented: every hit was a scan
false positive (each suite overrides the variable with a scratch root; all five bare hits are exclusion pathspecs or message text).

### D1 census (decides whether D1 exists) — measured 2026-10-03

109 suites with a code file in argv use the `REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` idiom; 89 (suite, repo path)
pairs name an existing repo file that is absent from the suite's edge set (for example `scripts/lib/rule-line-regex-parity.test.sh`
names `scripts/lint-rule-ids.py`). The issue's "23 `^README.md` edges" figure did not reproduce (no README row carries it), but the
defect behind it is real, so D1 is evidence-gated in and is decided in Phase 2.4 with a bounded selection delta.


## Round 3 — 2026-10-03 (runner as a closure leaf and the heavy batteries, PR-C of #9307)

### The leaf rule and what it cost

`CLOSURE_LEAF_FILES` makes `scripts/test-all.sh` and `scripts/lib/test-affected-paths.sh` closure leaves for text mentions: a leaf
keeps its real load edges (`source`/`.` lines, variables resolved, and `$(dirname "${BASH_SOURCE[0]}")` resolved on the whole line)
and loses the invocation words and `$VAR/path` tokens that merely NAME files. The first version skipped passes 2 and 3 wholesale and
the bench's retained-edge check caught that it also dropped the five libs the runner sources through variables (`scratch-root`,
`test-contention`, `repo-write-boundary`, `test-relevance-paths`, `test-affected-paths`) — before the change they had reached a suite
only by being mentioned in the runner's text.

**Measured with `scripts/affected-prepass-bench.sh --leaf-files`** (base = the same tree with the leaf set emptied, so the only
difference is the rule; bash 5.3.15, 16 cores, load average 2.6 to 3.0 during the runs, 2 base and 3 head runs per probe, median CPU
user+sys): README probe **114.3 s to 52.3 s (2.2x)**, a worktree-manager plus legal-doc probe **117.5 s to 50.6 s (2.3x)**; wall 108 s to 47 s. This is
a factor of two, not the order of magnitude the issue hoped for; what the leaf rule does not touch (every registration's own closure) is not
broken down here. 24 rows lose edges, 691 to 715 each (17,071 removals in total; 10 to 34 edges remain per row).
The oracle's verdict: 545 and 546 rows compared, 129 reach a leaf file, 24 lost edges, **227 (row, real source target) pairs checked and none lost**.

**The oracle's limit, stated.** The walker is the bench's own code (grep-shaped regexes over suite text, modelled on the derive's three
shapes; it never calls the runner), so it over-approximates what the derive follows and cannot reproduce every dropped edge: 2,161
removals over 24 rows are not explained by it (up to 189 per row; run with `--max-unexplained 200`, always printed), and the head kept 24 edges
it expected removed. Those unexplained removals are possible lost dependencies, which is why the recorder's check mode is the
behavioural cover and not the bench. A neutralised rule keeps hundreds of edges per row and fails both ceilings and the
population floor; the retained-edge and no-added-edge checks are exact.

### Recorder check on the suites whose closure reached the runner (before the bench result was accepted)

Check mode, `--cover-from-selection` in the audited checkout, 18 rows (the derived and large-declared rows that carried
`^scripts/test-all.sh`), after the declared sets below were in place: 10 covered, 6 uncovered, 2 unreliable.

| Suite | Verdict | Note |
|---|---|---|
| `scripts/orphan-process-reaper` | unreliable | no evidence (sandbox); **hedged: moved to ALWAYS_ON_SUITES** (8.7 s) |
| `plugins/soleur/test/git-env-list-parity.test.sh` | covered | covered by the declared set |
| `plugins/soleur/test/hook-git-env-coverage.test.sh` | uncovered | only the checkout root `.` (a directory open, not a file read; no pre-A5 cover contained it either) |
| `plugins/soleur/test/hook-git-env-receipt.test.sh` | uncovered | only the checkout root `.` (a directory open, not a file read; no pre-A5 cover contained it either) |
| `plugins/soleur/test/lefthook-bun-test-merge-skip.test.sh` | uncovered | only the checkout root `.` (a directory open, not a file read; no pre-A5 cover contained it either) |
| `plugins/soleur/test/proc.test.sh` | uncovered | two real reads found (`scripts/lib/scratch-root.sh`, `scripts/lib/test-contention.sh`); declared |
| `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` | covered | covered by the declared set |
| `plugins/soleur/test/worktree-manager-atomic-config.test.sh` | covered | covered by the declared set |
| `plugins/soleur/test/worktree-manager-bare-in-dotgit-layout.test.sh` | unreliable | no evidence (sandbox); worktree-manager shared set declared |
| `plugins/soleur/test/worktree-manager-bare-sync.test.sh` | covered | covered by the declared set |
| `plugins/soleur/test/worktree-manager-feature-spec-dir.test.sh` | covered | covered by the declared set |
| `plugins/soleur/test/worktree-manager-heal-stale-branch.test.sh` | covered | covered by the declared set |
| `plugins/soleur/test/worktree-manager-hook-deps.test.sh` | covered | covered by the declared set |
| `plugins/soleur/test/worktree-manager-install-bounded.test.sh` | covered | covered by the declared set |
| `plugins/soleur/test/worktree-manager-porcelain-sigpipe.test.sh` | uncovered | only the checkout root `.` (a directory open, not a file read; no pre-A5 cover contained it either) |
| `plugins/soleur/test/worktree-manager-safe-branch-sanitization.test.sh` | uncovered | only the checkout root `.` (a directory open, not a file read; no pre-A5 cover contained it either) |
| `plugins/soleur/test/worktree-manager-sandbox-tmp-sweep.test.sh` | covered | covered by the declared set |
| `plugins/soleur/test/worktree-manager-stale-lock-diag.test.sh` | covered | covered by the declared set |

The first check runs (before any declaration) found 16 of the 18 reading helpers at runtime that only the runner's incidental edges
had covered (13 in the first run, 3 more once perl and truncate were on the recorder's scratch PATH); they are declared per label over two shared sets in `scripts/lib/test-affected-paths.sh` (`_CLOSURE_LEAF_RT_WORKTREE_MANAGER`,
`_CLOSURE_LEAF_RT_HOOKS`) plus a per-label addition for `ship-phase-7-poll-fixtures` and `proc.test`. D1 then removed an accidental `^tests/` edge from
`tests/scripts/destroy-guard-regex-parity`, which the census linter reported unclassified; it now declares the seven sites it greps.
Two limits: the recorder produced no evidence for two suites (above), and a directory-only open of the checkout root is not a file read.

### D1 (`cd "<dir>[/..]" && pwd` resolves to its cd target)

Census (independent grep model, run on the selection stream before and after): 104 suites use the idiom; (suite, path) pairs naming an existing
repo file that the edge set lacks went **91 to 29**. Selection delta (stream diff, README probe and the worktree-manager probe): 48 rows gain edges
(329 edges added in total), 1 row loses 1 edge, 0 class changes, selected bit flips: 0 on the README probe and 1 on the second probe (223 to 224 selected).
This widens selection by design. Only fully resolved cd targets are normalised; a nested `cd "$ROOT/.." && pwd` keeps the old greedy collapse.

### Heavy always-on batteries (Phase C), recorder in demote mode, default is keep

| Suite | Verdict | files | dirs | Decision |
|---|---|---|---|---|
| `scripts/test-contention` | unreliable | - | - | **keep** — `unreliable` in the sandbox (`contaminated`: it dirties the private checkout); no evidence either way |
| `plugins/soleur/test/operator-ack-guard.test.sh` | unreliable | - | - | **keep** — `unreliable` in the sandbox (rc 1); Round 1: 1,451 files over 277 directories, `git diff`, network and clock flags |
| `tests/scripts/sentry-alert-live-fidelity` | unreliable | - | - | **keep** — `unreliable` in the sandbox (rc 1: its subject is external state and the sandbox has no network) |
| `scripts/test-all-infra-coverage-notice` | disqualified | 16952 | 471 | **keep** — `disqualified` (git diff, git ls-files, origin/main); 16,952 files over 471 directories |
| `scripts/lint-orphan-test-suites` | disqualified | 16952 | 471 | **keep** — `disqualified` (a probe of `.`, git ls-files, unresolved probe operands); 16,952 files over 471 directories |
| `plugins/soleur/test/hook-input-classification-mutation.test.sh` | disqualified | 16941 | 471 | **keep** — `disqualified` (git ls-files); 16,941 files over 471 directories |

None narrows: no suite produced a clean recording with a bounded read set, so the second and third pieces of evidence (a perturbation run and a
60-commit corpus check) were not run (they apply only to a suite whose recorder run is clean). `scripts/test-all-affected`,
`scripts/lint-orphan-test-suites-mutations-a` and `-b` were withdrawn from `ALWAYS_ON_SUITES` by ADR-262 before this work (status: not in the array).

### `scripts/domain-model-drift` (B2, decided after the leaf rule)

Its derive cost was 82 s in Round 1 because its test file's comment named `test-all.sh`; post-leaf it is **0.2 s** (three timed derives of the one registration). The cost reason
for keeping it is gone, and it **stays always-on** on the recorder's own rule instead: its test file carries four file-test or `find` operands the scan cannot resolve
(Phase 0.5), so the verdict is `disqualified` by construction. It was not re-run through the recorder; the proposed-demotion audit requires the edit to be an ancestor of the PR head,
and committing a demotion only to revert it was not worth the history for a foregone verdict.

### Always-on census

`${#ALWAYS_ON_SUITES[@]}` 120 on `origin/main` to **139** here (+18 re-promoted in Round 2, +1 hedge above); always-on suite time 1,146.6 s to 1,179.7 s by the incumbent
`scripts/suite-durations.tsv` (three labels on `main` and four here have no row). `_MIN_ALWAYS_ON_DECLARED` is unchanged at 116.
