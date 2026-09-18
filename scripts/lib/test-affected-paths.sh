# shellcheck shell=bash
# shellcheck disable=SC2034  # every array here is consumed by files that SOURCE this one
#   (scripts/test-all.sh, scripts/lint-orphan-test-suites.sh); shellcheck analyses one file
#   at a time and cannot see a cross-file consumer.
# Affected-set declarations for the local test gate (#8322). Consumed by
# scripts/test-all.sh to decide which registrations a diff can move, and by
# scripts/lint-orphan-test-suites.sh to census that every registration is
# classified. Sibling of scripts/lib/test-relevance-paths.sh — that file decides
# whether an EXPENSIVE suite declines on an irrelevant diff (ADR-181); this file
# decides whether a suite is SELECTED at all under the affected gate. The two
# axes compose: a suite can be affected-selected and still relevance-declined.
#
# DECLARATIONS ONLY. No `set -e`, no `exit`, no side effects, nothing executed —
# same contract as test-relevance-paths.sh, same reason: both consumers source
# it, and one of them (the linter) cannot afford the other's side effects.
#
# HOW TO ADD A CLASSIFICATION.
#   ALWAYS_ON — the suite's verdict is a property of the whole tree, not of a
#     diff: repo-wide scanners, whole-corpus legal gates, runner-SUT suites (the
#     runner is always its own SUT), credential/path lints, ratchet baselines.
#     Add the registration's label verbatim to ALWAYS_ON_SUITES.
#   EDGE — the suite's verdict is a property of specific files. Do nothing when
#     derivation already reaches the edge: argv literals (self-edge), source /
#     import closure, and the name-stem conventions (<x>.test.sh -> <x>.sh,
#     test-<x>.sh -> <x>.sh) cover most suites. Declare AFFECTED_<LABEL>_PATHS
#     ONLY when none of those mechanisms reaches a real dependency. The array
#     name is AFFECTED_<LABEL>_PATHS where <LABEL> is the registration label
#     uppercased with every non-alphanumeric character mapped to `_` and any
#     leading underscore dropped (`tests/hooks/drop-sentinel-parity` ->
#     AFFECTED_TESTS_HOOKS_DROP_SENTINEL_PARITY_PATHS).
#   UNCLASSIFIED is a valid runtime state — the suite RUNS (fail toward
#     coverage) and the census linter flags it RED. Never leave a suite
#     unclassified on purpose; never classify it wrong to silence the census.
#
# AN ENTRY IS A PATH OR A DIRECTORY PREFIX. A trailing "/" denotes a directory
# prefix match; anything else is a literal path. Keep entries repo-relative.
#
# BASH 3.2. No `declare -A`. The runner indexes selection by registration
# ORDINAL and resolves per-label arrays by name (`eval`/indirection idiom).
#
# SELF-INCLUSION. Every declared edge set includes this file, for the same
# reason test-relevance-paths.sh self-includes: an edit that NARROWS an edge set
# is the dangerous edit, and it must select the suites it could blind. And this
# file itself, like scripts/test-all.sh, is a runner/index self-edge: a diff
# touching either degrades the gate to full (runner-changed), so no declaration
# here can silently shrink what it would have run.

ALWAYS_ON_SUITES=(
  # --- repo-global scanners: -live convention ----------------------------------
  "apps/web-platform/scripts/seed-live-verify-user.test.sh"
  "plugins/soleur/test/gdpr-gate-glob-liveness.test.sh"
  "scripts/assert-dependabot-drain-live"
  "scripts/check-pa-22-live"
  "scripts/check-tom4-rls-posture-live"
  "scripts/followthrough-varq-ban-live"
  "scripts/inngest-liveness-classify"
  "scripts/lint-agents-compound-sync-live"
  "scripts/lint-agents-enforcement-tags-live"
  "scripts/lint-agents-rule-budget-live"
  "scripts/lint-dual-lockfile-live"
  "scripts/lint-guard-contract-live"
  "scripts/lint-legal-mirror-drift-baseline-live"
  "scripts/lint-legal-registers-live"
  "scripts/lint-legal-scope-block-placement-live"
  "scripts/lint-migrated-rule-ids-live"
  "scripts/lint-rule-bodies-live"
  "scripts/lint-rule-ids-live"
  "scripts/lint-shell-capture-exit-live"
  "scripts/lint-window-closure-assertion-live"
  "scripts/lint-workflow-errexit-capture-live"
  "scripts/lint-workflow-install-sites-live"
  "scripts/lint-workflow-issue-write-scope-live"
  "scripts/lint-workflow-step-env-refs-live"
  "scripts/probe-legal-corpus-truth-live"
  "scripts/review-reminder-liveness"
  "scripts/tenant-dpa-register-guard-live"
  "scripts/watch-live-verify-pass"
  "tests/scripts/sentry-alert-live-fidelity"

  # --- runner-SUT and registry-property suites ----------------------------------
  # Verdicts assert properties of the runner itself or of the whole
  # registration set — both invisible to any file-based selection.
  "scripts/test-all-capacity-signal"
  "scripts/test-all-enumerate-toolchain"
  "scripts/test-all-infra-coverage-notice"
  "scripts/test-all-killed-classification"
  "scripts/test-all-runtime-ceiling"
  "scripts/test-all-webplat-gate"
  "scripts/test-all-affected"
  "scripts/test-contention"
  "scripts/suite-exit-class-parity"
  "scripts/battery-tag-authorship"
  "scripts/battery-tag-authorship-mutations"
  "scripts/lint-orphan-test-suites"
  "scripts/lint-orphan-test-suites-mutations"
  "plugins/soleur/test/fanout-suite-scope.test.sh"
  "plugins/soleur/test/preflight-check10-suite-integrity.test.sh"
  "plugins/soleur/test/scripts-shard-runtime-coverage.test.sh"
  "plugins/soleur/test/scripts-shard-totality.test.sh"

  # --- corpus linters: verdict spans a file class scanned wholesale -------------
  # A ratchet counts a property across the whole tree and references nothing —
  # no file-based query can ever return it (the #8023/#8092/#8177 class).
  "scripts/lint-agents-compound-sync-unit"
  "scripts/lint-agents-enforcement-tags-unit"
  "scripts/lint-agents-rule-budget-unit"
  "scripts/lint-credential-path-literals"
  "scripts/lint-diagnosis-claims"
  "scripts/lint-dual-lockfile"
  "scripts/lint-encryption-posture"
  "scripts/lint-guard-contract"
  "scripts/lint-infra-no-human-steps"
  "scripts/lint-legal-mirror-drift-baseline-unit"
  "scripts/lint-legal-registers-unit"
  "scripts/lint-legal-scope-block-placement-unit"
  "scripts/lint-migrated-rule-ids-unit"
  "scripts/lint-shell-capture-exit"
  "scripts/lint-shell-trace-credential-refusal"
  "scripts/lint-shell-trace-credential-refusal-repo"
  "scripts/lint-supabase-deprecated-endpoints-unit"
  "scripts/lint-trap-tempfile-ownership"
  "scripts/lint-window-closure-assertion"
  "scripts/lint-workflow-errexit-capture"
  "scripts/lint-workflow-install-sites"
  "scripts/lint-workflow-issue-write-scope"
  "scripts/lint-workflow-run-body-syntax"
  "scripts/lint-workflow-step-env-refs"
  "plugins/soleur/test/lint-bot-synthetic-completeness.test.sh"
  "plugins/soleur/test/lint-bot-synthetic-statuses.test.sh"
  "plugins/soleur/test/lint-distribution-content.test.sh"
  "apps/web-platform/scripts/lint-migration-fk-preconditions.test.sh"
  "apps/web-platform/scripts/lib/no-cross-context-import.test.sh"
  "apps/web-platform/test/parse-gitleaks-allowlists"

  # --- whole-corpus guards, drift checks, parity and census gates ---------------
  "scripts/guard-vacuity-floor"
  "scripts/check-pa-22-unit"
  "scripts/check-tom4-rls-posture"
  "scripts/tenant-dpa-register-guard-unit"
  "scripts/check-cloudflare-token-drift"
  "scripts/domain-model-drift"
  "scripts/devin-docs-drift-check"
  "scripts/marketplace-drift-check"
  "scripts/marketplace-manifest-validate"
  "scripts/prod-version-drift-check"
  "scripts/digest-oracle-guard"
  "scripts/follow-through-closure-guard"
  "scripts/followthrough-exec-bit"
  "scripts/followthrough-varq-ban"
  "scripts/alarm-issue-filing-guard"
  "scripts/battery-ref-guard"
  "scripts/betterstack-assert-absence"
  "scripts/betterstack-ingest-parity"
  "scripts/rule-metrics-aggregate"
  "scripts/skill-freshness-aggregate"
  "scripts/sweep-followthroughs"
  "scripts/tunnel-connector-census"
  "scripts/verify-lockfile-guards"
  "scripts/verify-marketplace-ruleset"
  "scripts/cron-artifact-age"
  "scripts/rename-guard"
  "scripts/assert-dependabot-drain-unit"
  "scripts/expenses-verify-by-check"
  "scripts/frontmatter-strip-parity"
  "scripts/ship-incident-pir-gate-mutations"
  "plugins/soleur/test/auto-close-scanner.test.sh"
  "plugins/soleur/test/vendor-drift-classify.test.sh"
  "plugins/soleur/test/vendor-drift-workflow.test.sh"
  "plugins/soleur/test/token-drift-workflow-causes.test.sh"
  "plugins/soleur/test/check-deps-adapter-drift.test.sh"
  "plugins/soleur/test/terraform-drift-step-order.test.sh"
  "plugins/soleur/test/c4-count-parity.test.sh"
  "plugins/soleur/test/workflow-run-deploy-invariants.test.sh"
  "plugins/soleur/test/reusable-release-caller-permissions.test.sh"
  "plugins/soleur/test/kb-index-check-guard-mutation.test.sh"
  "plugins/soleur/test/fixture-env-adoption.test.sh"
  "plugins/soleur/test/fixture-dir-operand-assert.test.sh"
  "plugins/soleur/test/gitleaks-rules.test.sh"
  "plugins/soleur/test/gitleaks-merge-commit.test.sh"
  "plugins/soleur/test/hook-input-classification-mutation.test.sh"
  "plugins/soleur/skills/eval-harness/test/registry-completeness.test.sh"
  "apps/web-platform/scripts/assert-byok-rules-exist.test.sh"
  ".claude/hooks/hookeventname-coverage.test.sh"
  ".claude/hooks/settings-hook-exec-bit.test.sh"
  ".claude/hooks/kb-domain-allowlist-guard.test.sh"
  ".claude/hooks/incident-sandbox-coverage.test.sh"
  "plugins/soleur/test/fixture-cd-containment.test.sh"
  "blog-link-validation"

  # --- the never-gated web-platform arm -----------------------------------------
  # repo-wide's subject is the repository by construction (#7498); component
  # runs alongside it by a measured, twice-affirmed decision (#7666 revert).
  "apps/web-platform [repo-wide+component]"
)

# CONSUMED EDGE SETS. These five labels already carry their edge declarations in
# scripts/lib/test-relevance-paths.sh — the relevance gate IS the affected edge:
# the diff that makes the suite relevant is the diff that selects it. The
# classifier reads the named array for the label; it does NOT copy the paths.
# `label|ARRAY_NAME`, one per line — pipe-delimited because bash 3.2 has no
# associative arrays.
AFFECTED_CONSUMED_EDGES=(
  "tests/scripts/registry-gate-mutation-battery|REGISTRY_BATTERY_PATHS"
  "scripts/cf-tunnel-liveness-gate-mutations|CF_TUNNEL_BATTERY_PATHS"
  "plugins/soleur/test/c4-from-components.test.sh|C4_PRODUCER_PATHS"
  ".github/scripts/test/run-all.sh|GITHUB_SCRIPTS_SUITE_PATHS"
  "apps/web-platform [unit]|WEBPLAT_APP_PATHS"
)

# The infra runner's edges — the same two predicates _infra_in_diff checks
# (test-all.sh:1213-1220). Declared so the classifier sees the infra
# registration as positively edge-derived, never accidentally always-on: an
# explicit `TEST_GROUP=infra` ask must still EXECUTE it (group rung), and an
# infra diff must select it without depending on the group ask.
AFFECTED_INFRA_RUNNER_PATHS=(
  "apps/web-platform/infra/"
  ".github/workflows/apply-web-platform-infra.yml"
  "scripts/lib/test-affected-paths.sh"   # THIS FILE — see the self-inclusion note above
)

# DECLARED EDGES for suites whose real dependencies derivation cannot reach:
# neither argv literals nor the name-stem conventions name these files, and the
# suites enumerate their subjects as data, not as sourced code. Array name is
# the registration label uppercased with non-alphanumerics mapped to `_`.

# tests/scripts/sentry-brownout-retry — asserts the retry loop in the workflow,
# which is data to it.
AFFECTED_TESTS_SCRIPTS_SENTRY_BROWNOUT_RETRY_PATHS=(
  ".github/workflows/apply-sentry-infra.yml"
  "tests/scripts/test-sentry-brownout-retry.sh"   # self-inclusion
  "scripts/lib/test-affected-paths.sh"            # THIS FILE
)

# tests/hooks/drop-sentinel-parity — parity over the producer/consumer file sets
# it enumerates internally (PRODUCER_FILES / CONSUMER_FILES).
AFFECTED_TESTS_HOOKS_DROP_SENTINEL_PARITY_PATHS=(
  ".claude/hooks/lib/incidents.sh"
  ".claude/hooks/agent-token-tee.sh"
  ".claude/hooks/skill-invocation-logger.sh"
  "scripts/rule-metrics-aggregate.sh"
  "scripts/skill-freshness-aggregate.sh"
  "plugins/soleur/skills/compound/scripts/token-efficiency-report.sh"
  "tests/hooks/test_drop_sentinel_parity.sh"      # self-inclusion
  "scripts/lib/test-affected-paths.sh"            # THIS FILE
)

# Suites the repo-wide-idiom census arm flags (their fixture code walks a tree)
# whose real subject is a narrow SUT set, declared here rather than always-on:
# the scan is scoped, so the edges are honest.

AFFECTED_CLAUDE_HOOKS_GREP_REWRITE_TEST_SH_PATHS=(
  ".claude/hooks/grep-rewrite.sh"
  ".claude/hooks/grep-rewrite.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
AFFECTED_CLAUDE_HOOKS_HOOK_INPUT_CONTRACT_TEST_SH_PATHS=(
  ".claude/hooks/grep-rewrite.sh"
  ".claude/hooks/guardrails.sh"
  ".claude/hooks/hook-input-contract.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
AFFECTED_CLAUDE_HOOKS_PKILL_SELF_MATCH_GUARD_TEST_SH_PATHS=(
  ".claude/hooks/pkill-self-match-guard.sh"
  ".claude/hooks/pkill-self-match-guard.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
AFFECTED_CLAUDE_HOOKS_POST_DISPATCH_WATCH_GATE_TEST_SH_PATHS=(
  ".claude/hooks/post-dispatch-watch-gate.sh"
  ".claude/hooks/post-dispatch-watch-gate.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
AFFECTED_CLAUDE_HOOKS_PRE_MERGE_REBASE_TEST_SH_PATHS=(
  ".claude/hooks/pre-merge-rebase.sh"
  ".claude/hooks/pre-merge-rebase.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
AFFECTED_CLAUDE_HOOKS_RULE_INCIDENT_MARKER_CAPTURE_TEST_SH_PATHS=(
  ".claude/hooks/rule-incident-marker-capture.sh"
  ".claude/hooks/rule-incident-marker-capture.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
AFFECTED_CLAUDE_HOOKS_SKILL_CONTEXT_QUERIES_TEST_SH_PATHS=(
  ".claude/hooks/skill-context-queries.sh"
  ".claude/hooks/skill-context-queries.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
# The `test/` TypeScript suite — same SUT as the hook's own .test.sh above.
AFFECTED_TEST_PRE_MERGE_REBASE_PATHS=(
  ".claude/hooks/pre-merge-rebase.sh"
  "test/pre-merge-rebase.test.ts"
  "scripts/lib/test-affected-paths.sh"
)
AFFECTED_PLUGINS_SOLEUR_SKILLS_INCIDENT_TEST_REDACT_SENTINEL_TEST_SH_PATHS=(
  "plugins/soleur/skills/incident/scripts/redact-sentinel.sh"
  "plugins/soleur/skills/incident/scripts/redact-engine.py"
  "plugins/soleur/skills/incident/test/redact-sentinel.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
AFFECTED_PLUGINS_SOLEUR_TEST_PROC_TEST_SH_PATHS=(
  "plugins/soleur/scripts/lib/proc.sh"
  "plugins/soleur/test/proc.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
AFFECTED_PLUGINS_SOLEUR_TEST_SHIP_BATTERY_OWED_TEST_SH_PATHS=(
  "plugins/soleur/skills/ship/scripts/battery-owed.sh"
  "plugins/soleur/skills/ship/SKILL.md"
  "plugins/soleur/test/ship-battery-owed.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
AFFECTED_PLUGINS_SOLEUR_TEST_SHIP_PHASE_7_POLL_FIXTURES_TEST_SH_PATHS=(
  "plugins/soleur/skills/ship/SKILL.md"
  "plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
AFFECTED_SCRIPTS_LIB_LEGAL_NORMALISE_TEST_SH_PATHS=(
  "scripts/lib/legal-normalise.sh"
  "scripts/lib/legal-normalise.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
