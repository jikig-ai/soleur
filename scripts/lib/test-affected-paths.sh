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
  "scripts/lint-anthropic-content-position-live"
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
  # live-scanner batteries named for the gates they probe (#8384 landed these)
  "scripts/cosign-verify-live-8037"
  "scripts/generate-kb-index-live"

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
  # #8591's TEST_GROUP=affected mutation suite — a runner-SUT property battery
  # like its sibling above; renamed out of the add/add collision with #8322's.
  "scripts/test-all-group-affected"
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
  # debug-probe-residue scans the whole tracked tree for DEBUG-hex4 residue —
  # a diff adding a probe anywhere must re-run it (same discovered-corpus shape
  # as operator-script.test.sh below).
  "plugins/soleur/test/debug-probe-residue.test.sh"
  # operator-script's property is discovered, not enumerated: it greps the whole
  # tree for `lib/operator-script.sh` sourcers and asserts the no-secret-leak
  # property over each. A diff adding a consumer anywhere must re-run it —
  # scoping to the lib's own path would decline exactly that diff.
  "plugins/soleur/test/operator-script.test.sh"
  "apps/web-platform/scripts/lint-migration-fk-preconditions.test.sh"
  "apps/web-platform/scripts/lib/no-cross-context-import.test.sh"
  "apps/web-platform/test/parse-gitleaks-allowlists"

  # --- whole-corpus guards, drift checks, parity and census gates ---------------
  "scripts/guard-vacuity-floor"
  "scripts/ensure-kb-index"
  "plugins/soleur/test/kb-caches-untracked.test.sh"
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
  # #8563's Tier-B credential census — a repo-global property census over every
  # workflow + Terraform tier declaration; no diff-scoped edge can reach it.
  "tests/scripts/infra-privileged-tier-census"
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
  # tests/scripts/no-tofu-ssh — Guard 1 (#7226/ADR-237) walks `git ls-files` over
  # the whole tracked tree; any file anywhere can introduce a TOFU violation, so
  # no path edge can express its selection.
  "tests/scripts/no-tofu-ssh"
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
  # The infra runner maps to AFFECTED_INFRA_RUNNER_PATHS (declared just below,
  # in THIS lib — the consumed mapping mechanism does not care which file owns
  # the array). Its edges are the same two predicates _infra_in_diff checks.
  "apps/web-platform/infra/run-registered-suites.sh|AFFECTED_INFRA_RUNNER_PATHS"
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

# plugins/soleur/test/c4-model-freshness.test.sh — re-renders the committed
# LikeC4 artifact from the .c4 sources and byte-compares; both are data to it.
AFFECTED_PLUGINS_SOLEUR_TEST_C4_MODEL_FRESHNESS_TEST_SH_PATHS=(
  "knowledge-base/engineering/architecture/diagrams/"
  "scripts/regenerate-c4-model.sh"
  "plugins/soleur/test/c4-model-freshness.test.sh"   # self-inclusion
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)

# ---------------------------------------------------------------------------
# UNDRIVABLE-SUBJECT DECLARATIONS (#8322 review). These suites' real subjects
# are reached through channels derivation cannot see — data reads, workflow
# assertions, subprocess probes — and derivation produced a self-only edge set,
# which classifies as `unclassified` (select + census flag). The edges below
# are mined from the repo paths each suite file names, so a diff to a subject
# selects its guard.
# ---------------------------------------------------------------------------
# tests/hooks/incidents — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_HOOKS_INCIDENTS_PATHS=(
  ".claude/hooks/lib"
  ".claude/hooks/lib/incidents.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/test-all.sh"
  "tests/hooks/test_incidents.sh"
)

# scripts/sentry-issue-discover — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_SCRIPTS_SENTRY_ISSUE_DISCOVER_PATHS=(
  "scripts/lib/test-affected-paths.sh"
  "scripts/sentry-issue-discover.test.sh"
  "scripts/sentry-issue.sh"
)

# scripts/orphan-process-reaper-mutations — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_SCRIPTS_ORPHAN_PROCESS_REAPER_MUTATIONS_PATHS=(
  "scripts/lib"
  "scripts/lib/test-affected-paths.sh"
  "scripts/lib/test-contention.sh"
  "scripts/orphan-process-reaper-mutation.test.sh"
  "scripts/orphan-process-reaper.sh"
  "scripts/orphan-process-reaper.test.sh"
  "scripts/test-all.sh"
)

# scripts/lint-workflow-local-action-checkout-live — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_SCRIPTS_LINT_WORKFLOW_LOCAL_ACTION_CHECKOUT_LIVE_PATHS=(
  ".github/actions/"
  ".github/workflows"
  "scripts/lib/test-affected-paths.sh"
  "scripts/lint-workflow-local-action-checkout.py"
  "scripts/test-all.sh"
)

# scripts/no-dangling-committed-symlinks — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_SCRIPTS_NO_DANGLING_COMMITTED_SYMLINKS_PATHS=(
  "scripts/lib/test-affected-paths.sh"
  "scripts/no-dangling-committed-symlinks.test.sh"
  "scripts/orphan-process-reaper.test.sh"
)

# tests/scripts/betterstack-read-classify — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_BETTERSTACK_READ_CLASSIFY_PATHS=(
  "scripts/lib/betterstack-read-classify.sh"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/test-betterstack-read-classify.sh"
)

# tests/scripts/git-data-boot-signal-poll — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_GIT_DATA_BOOT_SIGNAL_POLL_PATHS=(
  ".github/workflows/apply-web-platform-infra.yml"
  "scripts/lib/git-data-boot-signal-poll.sh"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/test-git-data-boot-signal-poll.sh"
)

# tests/scripts/git-data-rung2-evidence-capture — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_GIT_DATA_RUNG2_EVIDENCE_CAPTURE_PATHS=(
  "scripts/betterstack-ingest-probe.sh"
  "scripts/compound-promote.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/test-git-data-rung2-evidence-capture.sh"
)

# tests/scripts/eu-location-allowset-parity — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_EU_LOCATION_ALLOWSET_PARITY_PATHS=(
  "apps/web-platform/infra/variables.tf"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/lib/stock-preflight-gate.sh"
  "tests/scripts/test-destroy-guard-regex-parity.sh"
  "tests/scripts/test-eu-location-allowset-parity.sh"
)

# tests/scripts/betterstack-query-archive — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_BETTERSTACK_QUERY_ARCHIVE_PATHS=(
  "scripts/betterstack-query.sh"
  "scripts/followthroughs/zot-restart-plateau-6288.sh"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/test-betterstack-ingest-probe.sh"
  "tests/scripts/test-betterstack-query-archive.sh"
)

# tests/scripts/betterstack-absence-classifier — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_BETTERSTACK_ABSENCE_CLASSIFIER_PATHS=(
  "scripts/lib/betterstack-absence.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/zot-restart-loop-alarm.sh"
  "tests/scripts/test-betterstack-absence-classifier.sh"
)

# tests/scripts/betterstack-roundtrip-latency — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_BETTERSTACK_ROUNDTRIP_LATENCY_PATHS=(
  "scripts/lib/betterstack-sources.sh"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/test-betterstack-roundtrip-latency.sh"
)

# tests/scripts/rule-id-regex-parity — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_RULE_ID_REGEX_PARITY_PATHS=(
  "scripts/lib/test-affected-paths.sh"
  "scripts/lint-rule-ids.py"
  "scripts/rule-prune.sh"
  "tests/scripts/test_rule_id_regex_parity.py"
)

# tests/commands/sync-rule-prune — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_COMMANDS_SYNC_RULE_PRUNE_PATHS=(
  "scripts/lib/test-affected-paths.sh"
  "scripts/retired-rule-ids.txt"
  "scripts/rule-prune.sh"
  "tests/commands/test-sync-rule-prune.sh"
)

# tests/commands/sync-domain-model — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_COMMANDS_SYNC_DOMAIN_MODEL_PATHS=(
  "plugins/soleur/commands/sync.md"
  "plugins/soleur/scripts/domain-model-drift.sh"
  "scripts/lib/test-affected-paths.sh"
  "tests/commands/test-sync-domain-model.sh"
)

# tests/scripts/destroy-guard-counter-github — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_DESTROY_GUARD_COUNTER_GITHUB_PATHS=(
  ".github/workflows/apply-github-infra.yml"
  "infra/github"
  "infra/github/"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/fixtures"
  "tests/scripts/fixtures/tfplan-real-ruleset-baseline.json"
  "tests/scripts/lib/destroy-guard-filter.jq"
  "tests/scripts/test-destroy-guard-counter.sh"
)

# tests/scripts/destroy-guard-counter-sentry — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_DESTROY_GUARD_COUNTER_SENTRY_PATHS=(
  ".github/workflows/apply-sentry-infra.yml"
  "apps/web-platform/infra/sentry"
  "knowledge-base/project/specs/fix-7650-sentry-alert-migration/"
  "scripts/lib/test-affected-paths.sh"
  "scripts/sentry-destroy-counts.sh"
  "tests/scripts/fixtures"
  "tests/scripts/fixtures/tfplan-sentry-real-baseline.json"
  "tests/scripts/lib/destroy-guard-filter-sentry.jq"
  "tests/scripts/test-destroy-guard-counter-sentry.sh"
)

# tests/scripts/host-image-coherence-preflight — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_HOST_IMAGE_COHERENCE_PREFLIGHT_PATHS=(
  "apps/web-platform/infra/scripts/host-image-coherence-preflight.sh"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/test-host-image-coherence-preflight.sh"
)

# tests/scripts/vector-redeliver-wiring — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_VECTOR_REDELIVER_WIRING_PATHS=(
  ".github/actions/cf-tunnel-ssh-bridge"
  ".github/workflows/apply-web-platform-infra.yml"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/lib/vector-redeliver-gate.sh"
  "tests/scripts/test-registry-d10-workflow-wiring.sh"
  "tests/scripts/test-vector-redeliver-wiring.sh"
)

# tests/scripts/registry-delivery-change-mutation-battery — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_REGISTRY_DELIVERY_CHANGE_MUTATION_BATTERY_PATHS=(
  "scripts/guard-vacuity-floor.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/test-all.sh"
  "tests/scripts/"
  "tests/scripts/test-registry-delivery-change-mutation-battery.sh"
  "tests/scripts/test-registry-delivery-change.sh"
)

# tests/scripts/registry-d10-workflow-wiring — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_REGISTRY_D10_WORKFLOW_WIRING_PATHS=(
  "scripts/derive-app-domain-base.sh"
  "scripts/derive-app-domain-base.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/test-registry-d10-workflow-wiring.sh"
)

# tests/scripts/zot-log-channel-probe — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_ZOT_LOG_CHANNEL_PROBE_PATHS=(
  "scripts/followthroughs/zot-log-channel-7440.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/lint-followthrough-varq-ban.sh"
  "tests/scripts/test-zot-log-channel-probe.sh"
)

# tests/scripts/git-data-root-key-arm — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_GIT_DATA_ROOT_KEY_ARM_PATHS=(
  "plugins/soleur/test/test-helpers.sh"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/lib/gate-suite-harness.sh"
  "tests/scripts/lib/git-data-root-key-arm-gate.sh"
  "tests/scripts/test-git-data-root-key-arm.sh"
)

# tests/scripts/destroy-guard-sentry-scope-guard — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_DESTROY_GUARD_SENTRY_SCOPE_GUARD_PATHS=(
  "apps/web-platform/infra/sentry"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/lib/destroy-guard-filter-sentry.jq"
  "tests/scripts/test-destroy-guard-sentry-scope-guard.sh"
)

# tests/scripts/sentry-full-root-apply — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_SENTRY_FULL_ROOT_APPLY_PATHS=(
  ".github/workflows/apply-sentry-infra.yml"
  "knowledge-base/project/learnings/2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr.md"
  "knowledge-base/project/learnings/test-failures/2026-06-17-grep-assertion-over-script-body-false-matches-own-comments.md"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/fixtures"
  "tests/scripts/lib/destroy-guard-filter-sentry.jq"
  "tests/scripts/test-destroy-guard-sentry-scope-guard.sh"
  "tests/scripts/test-sentry-full-root-apply.sh"
)

# tests/scripts/sentry-alert-adoption-guards — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_SENTRY_ALERT_ADOPTION_GUARDS_PATHS=(
  ".github/workflows/apply-sentry-infra.yml"
  "scripts/lib/test-affected-paths.sh"
  "scripts/sentry-adoption-plan-assert.sh"
  "scripts/sentry-create-gate.sh"
  "scripts/sentry-forget-import-bijection.sh"
  "scripts/sentry-issue-alert-create-tripwire.sh"
  "scripts/sentry-monitor-binding-gate.sh"
  "tests/scripts/test-destroy-guard-counter-sentry.sh"
  "tests/scripts/test-sentry-alert-adoption-guards.sh"
  "tests/scripts/test-sentry-destroy-counts.sh"
)

# tests/scripts/sentry-ac17-derived-counts — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_SENTRY_AC17_DERIVED_COUNTS_PATHS=(
  ".github/workflows/apply-sentry-infra.yml"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/test-sentry-ac17-derived-counts.sh"
)

# tests/scripts/sentry-alert-drift-workflow — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_SENTRY_ALERT_DRIFT_WORKFLOW_PATHS=(
  "knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase2-live-workflows-capture-2026-09-04.json"
  "scripts/alarm-issue-filing-guard.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/sentry-alert-live-fidelity.sh"
  "tests/scripts/test-sentry-alert-drift-workflow.sh"
)

# tests/scripts/sentry-monitors-audit-class-d — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_SENTRY_MONITORS_AUDIT_CLASS_D_PATHS=(
  "apps/web-platform/scripts/sentry-monitors-audit.sh"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/test-sentry-monitors-audit-class-d.sh"
)

# scripts/md-to-mrkdwn — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_SCRIPTS_MD_TO_MRKDWN_PATHS=(
  "plugins/soleur/test/reusable-release-idempotency.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/md-to-mrkdwn.test.mjs"
)

# scripts/skill-security-scan-step-body — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_SCRIPTS_SKILL_SECURITY_SCAN_STEP_BODY_PATHS=(
  ".github/workflows/skill-security-scan-postmerge.yml"
  ".github/workflows/skill-security-scan-pr-trailer.yml"
  "plugins/soleur/skills/skill-security-scan/scripts/parse-override.sh"
  "plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh"
  "scripts/guard-vacuity-floor.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/skill-security-scan-step-body.test.sh"
)

# plugins/soleur/scripts/resolve-regenerable-conflicts.test.sh (#8631, ADR-235) — its corpus
# walk is sandbox-only (synthetic repos + fixture trees); the real subject is the resolver SUT
# and the render arm it stubs, so the scan is scoped and the edges are honest.
AFFECTED_PLUGINS_SOLEUR_SCRIPTS_RESOLVE_REGENERABLE_CONFLICTS_TEST_SH_PATHS=(
  "plugins/soleur/scripts/resolve-regenerable-conflicts.sh"
  "plugins/soleur/scripts/resolve-regenerable-conflicts.test.sh"
  "plugins/soleur/scripts/render-c4-model.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/ci-concurrency-key.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_CI_CONCURRENCY_KEY_TEST_SH_PATHS=(
  ".github/workflows"
  ".github/workflows/ci.yml"
  "plugins/soleur/test/ci-concurrency-key.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_CI_TEST_AGGREGATOR_DIAGNOSIS_TEST_SH_PATHS=(
  ".github/workflows"
  ".github/workflows/ci.yml"
  "plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/concurrent-ship.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_CONCURRENT_SHIP_TEST_SH_PATHS=(
  "plugins/soleur/scripts/lib/session-state.sh"
  "plugins/soleur/skills/git-worktree/SKILL.md"
  "plugins/soleur/skills/merge-pr/SKILL.md"
  "plugins/soleur/skills/one-shot/SKILL.md"
  "plugins/soleur/skills/product-roadmap/SKILL.md"
  "plugins/soleur/skills/schedule/SKILL.md"
  "plugins/soleur/skills/ship/SKILL.md"
  "plugins/soleur/skills/work/SKILL.md"
  "plugins/soleur/test/concurrent-ship.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/flag-detach-shared.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_FLAG_DETACH_SHARED_TEST_SH_PATHS=(
  "plugins/soleur/skills/flag-set-role/scripts/flip.sh"
  "plugins/soleur/test/flag-detach-shared.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/flag-org-scoping-pr2.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_FLAG_ORG_SCOPING_PR2_TEST_SH_PATHS=(
  "plugins/soleur/skills/flag-create/scripts/create.sh"
  "plugins/soleur/skills/flag-set-role/scripts/flip.sh"
  "plugins/soleur/test/flag-org-scoping-pr2.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/git-fixture-env-shell.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_GIT_FIXTURE_ENV_SHELL_TEST_SH_PATHS=(
  "plugins/soleur/test/git-fixture-env-shell.test.sh"
  "plugins/soleur/test/lib/git-fixture-env.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_HEARTBEAT_RECONCILE_ISSUE_STEP_TEST_SH_PATHS=(
  ".github/workflows/scheduled-terraform-drift.yml"
  "plugins/soleur/lib/heartbeat-live-reconcile.ts"
  "plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/hosted-ship-shallow-merge-base.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_HOSTED_SHIP_SHALLOW_MERGE_BASE_TEST_SH_PATHS=(
  "plugins/soleur/test/hosted-ship-shallow-merge-base.test.sh"
  "plugins/soleur/test/test-helpers.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/kb-search-lockstep.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_KB_SEARCH_LOCKSTEP_TEST_SH_PATHS=(
  "plugins/soleur/skills/kb-search/SKILL.md"
  "plugins/soleur/test/kb-search-lockstep.test.sh"
  "scripts/learning-retrieval-bench.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/machinery-drain-floor.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_MACHINERY_DRAIN_FLOOR_TEST_SH_PATHS=(
  ".github/workflows/scheduled-machinery-drain.yml"
  "plugins/soleur/skills/drain-labeled-backlog/SKILL.md"
  "plugins/soleur/test/machinery-drain-floor.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/main-health-monitor-workflow.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_MAIN_HEALTH_MONITOR_WORKFLOW_TEST_SH_PATHS=(
  ".github/workflows/main-health-monitor.yml"
  "apps/web-platform/infra/"
  "apps/web-platform/infra/inngest.test.sh"
  "apps/web-platform/infra/run-registered-suites.sh"
  "knowledge-base/project/learnings/best-practices/"
  "plugins/soleur/test/main-health-monitor-workflow.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/lint-workflow-errexit-capture.py"
  "scripts/test-all.sh"
)

# plugins/soleur/test/registry-host-replace-dispatch-verdict.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_REGISTRY_HOST_REPLACE_DISPATCH_VERDICT_TEST_SH_PATHS=(
  ".github/workflows/registry-host-replace-dispatch.yml"
  "apps/web-platform/infra/cloud-init-registry.yml"
  "plugins/soleur/test/"
  "plugins/soleur/test/registry-host-replace-dispatch-verdict.test.sh"
  "scripts/guard-vacuity-floor.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/test-all.sh"
)

# plugins/soleur/test/resolve-target-decision.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_RESOLVE_TARGET_DECISION_TEST_SH_PATHS=(
  ".github/workflows/web-platform-release.yml"
  "plugins/soleur/test/resolve-target-decision.test.sh"
  "scripts/guard-vacuity-floor.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/lint-workflow-errexit-capture.py"
)

# plugins/soleur/test/reusable-release-degraded-pointer.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_REUSABLE_RELEASE_DEGRADED_POINTER_TEST_SH_PATHS=(
  ".github/workflows/reusable-release.yml"
  "plugins/soleur/test/reusable-release-degraded-pointer.test.sh"
  "scripts/betterstack-query.sh"
  "scripts/guard-vacuity-floor.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/reusable-release-idempotency.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_REUSABLE_RELEASE_IDEMPOTENCY_TEST_SH_PATHS=(
  ".github/workflows/reusable-release.yml"
  "plugins/soleur/test/reusable-release-idempotency.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/md-to-mrkdwn.mjs"
  "scripts/md-to-mrkdwn.test.mjs"
)

# plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_REUSABLE_RELEASE_ZOT_MIRROR_RETRY_TEST_SH_PATHS=(
  ".github/actions/cf-tunnel-registry-bridge/action.yml"
  ".github/workflows/reusable-release.yml"
  "plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh"
  "scripts/betterstack-query.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/zot-mirror-diagnosis.test.sh"
)

# plugins/soleur/test/unkept-promise-hook.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_UNKEPT_PROMISE_HOOK_TEST_SH_PATHS=(
  "plugins/soleur/hooks/unkept-promise-hook.sh"
  "plugins/soleur/test/unkept-promise-hook.test.sh"
  "scripts/guard-vacuity-floor.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/skills/constraint-scaffold/test/boundary.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_SKILLS_CONSTRAINT_SCAFFOLD_TEST_BOUNDARY_TEST_SH_PATHS=(
  "apps/web-platform"
  "apps/web-platform/scripts/constraint-gates.sh"
  "plugins/soleur/skills/"
  "plugins/soleur/skills/constraint-scaffold/test/boundary.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/test-all.sh"
)

# plugins/soleur/skills/constraint-scaffold/test/emit-fix-constraints.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_SKILLS_CONSTRAINT_SCAFFOLD_TEST_EMIT_FIX_CONSTRAINTS_TEST_SH_PATHS=(
  "apps/web-platform"
  "apps/web-platform/scripts/constraint-gates.sh"
  "plugins/soleur/skills/"
  "plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh"
  "plugins/soleur/skills/constraint-scaffold/test/emit-fix-constraints.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/test-all.sh"
)

# plugins/soleur/skills/constraint-scaffold/test/generator.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_SKILLS_CONSTRAINT_SCAFFOLD_TEST_GENERATOR_TEST_SH_PATHS=(
  "apps/web-platform"
  "plugins/soleur/skills/"
  "plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh"
  "plugins/soleur/skills/constraint-scaffold/test/generator.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/test-all.sh"
)

# plugins/soleur/skills/constraint-scaffold/test/parity.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_SKILLS_CONSTRAINT_SCAFFOLD_TEST_PARITY_TEST_SH_PATHS=(
  ".github/workflows/constraint-gates.yml"
  ".github/workflows/fix-constraints-stage-a.yml"
  ".github/workflows/fix-constraints-stage-b.yml"
  "apps/web-platform"
  "plugins/soleur/skills/"
  "plugins/soleur/skills/constraint-scaffold/references"
  "plugins/soleur/skills/constraint-scaffold/test/parity.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/test-all.sh"
)

# plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_SKILLS_GIT_WORKTREE_TEST_CREATE_FROM_ORIGIN_MAIN_TEST_SH_PATHS=(
  "knowledge-base/project/plans/2026-05-14-fix-worktree-create-from-origin-main-plan.md"
  "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"
  "plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_SKILLS_GIT_WORKTREE_TEST_LEASE_PROTECTS_ACTIVE_TEST_SH_PATHS=(
  ".claude/hooks/lib/"
  "knowledge-base/project/learnings/2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md"
  "knowledge-base/project/plans/2026-05-12-feat-bg-readiness-concurrency-hardening-plan.md"
  "plugins/soleur/."
  "plugins/soleur/scripts/lib/session-state.sh"
  "plugins/soleur/skills/."
  "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"
  "plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/lint-diagnosis-claims.test.sh"
  "scripts/lint-workflow-step-env-refs.test.sh"
)

# plugins/soleur/skills/git-worktree/test/no-repo-fail-loud.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_SKILLS_GIT_WORKTREE_TEST_NO_REPO_FAIL_LOUD_TEST_SH_PATHS=(
  "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"
  "plugins/soleur/skills/git-worktree/test/no-repo-fail-loud.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/skills/git-worktree/test/orphan-reaper-honest-count.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_SKILLS_GIT_WORKTREE_TEST_ORPHAN_REAPER_HONEST_COUNT_TEST_SH_PATHS=(
  "knowledge-base/project/plans/2026-07-31-fix-honest-failure-reporting-hook-timeout-and-orphan-reaper-plan.md"
  "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"
  "plugins/soleur/skills/git-worktree/test/orphan-reaper-honest-count.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/skills/git-worktree/test/stale-lock-sweep.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_SKILLS_GIT_WORKTREE_TEST_STALE_LOCK_SWEEP_TEST_SH_PATHS=(
  "knowledge-base/project/plans/2026-07-01-fix-stale-git-lock-sweep-worktree-plan.md"
  "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"
  "plugins/soleur/skills/git-worktree/test/stale-lock-sweep.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/skills/linear-fetch/test/persist-safe-integration.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_SKILLS_LINEAR_FETCH_TEST_PERSIST_SAFE_INTEGRATION_TEST_SH_PATHS=(
  "plugins/soleur/skills/linear-fetch/scripts/assert-no-linear-telemetry.sh"
  "plugins/soleur/skills/linear-fetch/scripts/redact-linear-urls.sh"
  "plugins/soleur/skills/linear-fetch/scripts/render-caller-template.sh"
  "plugins/soleur/skills/linear-fetch/test/persist-safe-integration.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# .claude/hooks/grep-q-pipe-guard.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS=(
  ".claude/hooks/"
  ".claude/hooks/grep-q-pipe-guard.test.sh"
  ".claude/hooks/lib/"
  "plugins/."
  "plugins/soleur/skills/compound/test/phase-16.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/test-sentry-full-root-apply.sh"
)

# .claude/hooks/stub-argv-fidelity.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_CLAUDE_HOOKS_STUB_ARGV_FIDELITY_TEST_SH_PATHS=(
  ".claude/hooks/"
  ".claude/hooks/lib/test-incident-sandbox.sh"
  ".claude/hooks/stub-argv-fidelity.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/lib/rule-line-regex-parity.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_SCRIPTS_LIB_RULE_LINE_REGEX_PARITY_TEST_SH_PATHS=(
  "scripts/lib/"
  "scripts/lib/rule-line-regex-parity.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/test-all.sh"
)

# scripts/followthroughs/registry-luks-live-8386.test.sh — a battery named for the live
# follow-through probe it mutates; declared per the census's live-scanner arm even though
# the name-stem convention would reach the SUT, so the binding is explicit.
AFFECTED_SCRIPTS_REGISTRY_LUKS_LIVE_8386_PATHS=(
  "scripts/followthroughs/registry-luks-live-8386.sh"
  "scripts/followthroughs/registry-luks-live-8386.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
# plugins/soleur/test/lint-rejected-register.test.sh — mutation battery over the
# rejected-register linter; its live arms run the SUT against the real
# knowledge-base/project/rejected/ corpus, so the census's corpus-walk arm wants
# the scope declared even though derivation reaches the SUT by name-stem.
AFFECTED_PLUGINS_SOLEUR_TEST_LINT_REJECTED_REGISTER_TEST_SH_PATHS=(
  "knowledge-base/project/rejected/"
  "plugins/soleur/test/lint-rejected-register.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/lint-rejected-register.sh"
)

# plugins/soleur/skills/archive-kb/test/archive-kb-partial-run.test.sh — pins the
# archive-kb.sh partial-run warning (#8416); the SUT path is composed at runtime
# ("$ROOT/../scripts/archive-kb.sh"), which derivation cannot expand.
AFFECTED_PLUGINS_SOLEUR_SKILLS_ARCHIVE_KB_TEST_ARCHIVE_KB_PARTIAL_RUN_TEST_SH_PATHS=(
  "plugins/soleur/skills/archive-kb/scripts/archive-kb.sh"
  "plugins/soleur/skills/archive-kb/test/archive-kb-partial-run.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/go-routing-table-parity.test.sh — three-way parity over the
# go routing table; all three operands are "$ROOT/"-prefixed literals that
# derivation cannot expand.
AFFECTED_PLUGINS_SOLEUR_TEST_GO_ROUTING_TABLE_PARITY_TEST_SH_PATHS=(
  "plugins/soleur/commands/go.md"
  "plugins/soleur/lib/workflow-fidelity.ts"
  "plugins/soleur/skills/eval-harness/enums/go-routes.json"
  "plugins/soleur/test/go-routing-table-parity.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/ticket-triage-mirror-parity.test.sh — mirror parity between
# the Claude agent and the OpenHands skill. skills/triage/SKILL.md is deliberately
# NOT an edge — the suite's own header states it says nothing about that file.
AFFECTED_PLUGINS_SOLEUR_TEST_TICKET_TRIAGE_MIRROR_PARITY_TEST_SH_PATHS=(
  ".openhands/skills/ticket-triage/SKILL.md"
  "plugins/soleur/agents/support/ticket-triage.md"
  "plugins/soleur/test/ticket-triage-mirror-parity.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# tests/scripts/dev-suite-mutex-wiring — wiring assertion over the tenant-
# integration mutex's four SUT files ($ROOT-prefixed literals defeat
# derivation); declared from the repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_DEV_SUITE_MUTEX_WIRING_PATHS=(
  ".github/actions/dev-migration-drift-probe/action.yml"
  ".github/workflows/scheduled-dev-migration-drift.yml"
  ".github/workflows/tenant-integration.yml"
  "scripts/dev-suite-mutex.sh"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/test-dev-suite-mutex-wiring.sh"
)

# tests/scripts/no-tofu-ssh-mutation — mutation harness for the no-tofu-ssh
# guard (#7226/ADR-237); its SUT is the guard file itself plus its own harness,
# the same shape as orphan-process-reaper-mutations above.
AFFECTED_TESTS_SCRIPTS_NO_TOFU_SSH_MUTATION_PATHS=(
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/test-no-tofu-ssh.sh"
  "tests/scripts/test-no-tofu-ssh-mutation.sh"
)

# tests/scripts/dispatch-web-redeploy — Guard 7 (#7226/ADR-237) exercises the
# track.sh action and the redeploy job it serves; declared from the repo paths
# its suite file names.
AFFECTED_TESTS_SCRIPTS_DISPATCH_WEB_REDEPLOY_PATHS=(
  ".github/actions/dispatch-web-redeploy/"
  ".github/workflows/git-data-pin-redeploy.yml"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/test-dispatch-web-redeploy.sh"
)

# plugins/soleur/test/admin-merge-ready-wiring.test.sh — corpus walk is SCOPED
# to plugins/soleur/ (any file there gaining `gh pr merge --admin` must carry
# the ready-gate), plus its SUT script and the skills that must reference it.
AFFECTED_PLUGINS_SOLEUR_TEST_ADMIN_MERGE_READY_WIRING_TEST_SH_PATHS=(
  "plugins/soleur/"
  "plugins/soleur/scripts/admin-merge-ready.sh"
  "plugins/soleur/test/admin-merge-ready-wiring.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
