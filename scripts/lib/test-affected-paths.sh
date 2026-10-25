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
# AN ENTRY IS A PATH, A DIRECTORY PREFIX, OR A `glob:` PATTERN. A trailing "/"
# denotes a directory prefix match; anything else is a literal path — except
# `glob:<literal-head>/<glob-tail>` (#9813) or `glob:<root-pattern>` (#10198), the
# extension-aware edges for corpus walkers: a dir-anchored edge matches a diff
# line under <literal-head> matching <glob-tail> under bash `[[ == ]]` semantics
# (`*` crosses `/`, so `knowledge-base/**.sh` covers `knowledge-base/x.sh` and
# `knowledge-base/a/b/c.sh` alike); a ROOT-ANCHORED member — a `/`-free head
# (empty allowed), a `/`-free tail carrying `*` — matches only DIR-LESS diff
# lines (repo-root corpus files like `x.test.sh`). All `glob:` members classify
# through scripts/lib/affected-glob.sh's `_affected_glob_split`; a `/`-bearing
# tail under a `/`-free head is malformed (root-tail-slash). `glob:` is
# DECLARED-ARRAY-ONLY: the token extractors never emit it on purpose (a
# `glob:`-spelled literal in scanned content still hits the same mint arm —
# widen-only). The relevance arrays DO stay verbatim substring edges — a
# `glob:` member there is a dead edge the relevance census catches.
# Malformed entries fail toward coverage: they mint an always-match
# `^glob:<verbatim>` edge (the malformed-shape invariant — closed charset +
# repo-relative head — in scripts/test-all.sh _affected_add_edge), and the
# census linter flags them statically. Keep entries repo-relative. Matching is ANCHORED (#9307): a directory entry
# selects a suite only when a diff path STARTS with it, a file entry only
# when a diff path EQUALS it, and a LIVE directory written without the
# trailing "/" is normalised to one. WRITE the slash anyway (#9441): declared
# entries mint through _affected_add_declared_edge, which carries no `-e`
# filter, so a deleted `dir/` still mints the `^dir/` prefix that selects the
# suite on the deleting diff — while a deleted slash-less `dir` mints `^dir`,
# an exact line a diff can never produce. The census linter rejects the
# slash-less form for exactly that reason. So `test/` does not match
# `apps/web-platform/test/x.ts` or `specs/feat-x-test-y/spec.md`. Entries
# rooted at `.` or `..` keep the legacy substring match.
#
# BASH 3.2. No `declare -A`. The runner indexes selection by registration
# ORDINAL and resolves per-label arrays by name (`eval`/indirection idiom).
#
# SELF-INCLUSION. Every declared edge set includes this file, for the same
# reason test-relevance-paths.sh self-includes: an edit that NARROWS an edge set
# is the dangerous edit, and it must select the suites it could blind. And this
# file itself, like scripts/test-all.sh, is a runner/index self-edge: a diff
# touching either degrades the gate to full (runner-changed), so no declaration
# here can silently shrink what it would have run. The one exception is a REGISTRATION-ONLY
# runner diff (nothing but new single-line run_suite registrations for new suites, ADR-242
# decision 20): it takes the bounded selection, together with, for each suite that same diff
# registers, its own AFFECTED_*_PATHS block and ALWAYS_ON_SUITES entry. Any other hunk in THIS file
# still degrades to full.

# CLOSURE LEAVES (ADR-242 decision 18). The derive follows what a file's text NAMES (invocation
# and $VAR/path tokens) as well as what it sources; for these two files the names are the whole
# runner and index, so every suite reaching one inherited ~475 edges. A leaf keeps its real
# source/import edges and stays an edge itself, and loses only the named-path edges. EXACTLY the
# two files the `runner-changed` fallback greps for (scripts/test-all.sh, _aff_runner_in_diff);
# scripts/test-affected-derive.test.sh pins the two literal sets equal. That fallback fires only on a diff
# to these two files themselves (and is dark under --affected-scope=staged): it does NOT cover a file the
# leaf stopped following, so it is NOT what makes the narrowing safe. The cover for the narrowing is
# behavioural: the recorder's check mode (scripts/audit-suite-reads.sh, Round 3 in always-on-audit.md),
# the shared runtime-read sets below, and the per-label declarations. The recorder is operator-run, so
# a read added to a suite later is not re-validated automatically. Deliberately outside the AFFECTED_
# prefix: this is not an edge set, and the census linter scans AFFECTED_*_PATHS arrays.
# scripts/lib/test-relevance-paths.sh is NOT a leaf (a diff touching only it meets no fallback).
CLOSURE_LEAF_FILES=(
  "scripts/test-all.sh"
  "scripts/lib/test-affected-paths.sh"
)

# RUNTIME READS THAT THE LEAF RULE WOULD CUT (A5, ADR-242 decision 18). Before the runner became a closure leaf, every suite
# reaching it inherited ~475 edges, which incidentally covered helpers these suites READ AT RUNTIME through a `source` path the
# derive cannot resolve. The recorder (scripts/audit-suite-reads.sh, --mode check, post-A5 tree) listed the reads that fell
# outside each suite's cover; these shared sets are those reads. Leading underscore on purpose: not an edge array of its own,
# the census linter scans only AFFECTED_*_PATHS. A directory-only open of `.` (the checkout root, which any git call, `cd` or
# `ls` performs) is a read of no particular file and is not declared.
_CLOSURE_LEAF_RT_WORKTREE_MANAGER=(
  "plugins/soleur/test/lib/git-fixture-env.sh"
  "scripts/lib/scratch-root.sh"
  "plugins/soleur/scripts/lib/session-state.sh"
  "plugins/soleur/scripts/lib/tmp-classify.sh"
)
_CLOSURE_LEAF_RT_HOOKS=(
  "lefthook.yml"
  "scripts/hooks/"
  ".github/scripts/test/run-all.sh"
  "scripts/lib/scratch-root.sh"
)

ALWAYS_ON_SUITES=(
  # --- repo-global scanners: -live convention ----------------------------------
  "apps/web-platform/scripts/seed-live-verify-user.test.sh"
  "plugins/soleur/test/gdpr-gate-glob-liveness.test.sh"
  "scripts/assert-dependabot-drain-live"
  # #8875: the emitter-selection census walks the whole tracked tree — repo-global by
  # construction (git ls-files + per-file comment-stripped invocation discovery).
  "scripts/betterstack-emitter-read-live"
  "scripts/followthrough-varq-ban-live"
  "scripts/inngest-liveness-classify"
  "scripts/lint-agents-compound-sync-live"
  "scripts/lint-agents-enforcement-tags-live"
  "scripts/lint-anthropic-content-position-live"
  "scripts/lint-doppler-description-length-live"
  "scripts/lint-dual-lockfile-live"
  "scripts/lint-gh-argv-arg-live"
  "scripts/lint-guard-contract-live"
  "scripts/lint-feature-map-coverage-live"
  "scripts/lint-integration-env-gates-live"
  "scripts/lint-legal-mirror-drift-baseline-live"
  "scripts/lint-legal-registers-live"
  "scripts/lint-legal-scope-block-placement-live"
  "scripts/lint-migrated-rule-ids-live"
  "scripts/lint-rule-bodies-live"
  "scripts/lint-window-closure-assertion-live"
  "scripts/lint-workflow-errexit-capture-live"
  "scripts/lint-workflow-install-sites-live"
  "scripts/lint-workflow-issue-write-scope-live"
  "scripts/lint-workflow-step-env-refs-live"
  "scripts/lint-ratchet-ruff-live"
  "tests/scripts/lint-ratchet"
  "scripts/review-reminder-liveness"
  "scripts/watch-live-verify-pass"
  # live-scanner batteries named for the gates they probe (#8384 landed these)
  "scripts/cosign-verify-live-8037"
  "scripts/generate-kb-index-live"

  # --- runner-SUT and registry-property suites ----------------------------------
  # Verdicts assert properties of the runner itself or of the whole
  # registration set — both invisible to any file-based selection.
  "scripts/test-all-capacity-signal"
  # #8993/#8940's run-path watchdog + durable-log battery — a runner-SUT
  # property suite like its killed-classification sibling.
  "scripts/test-all-webplat-gate"
  # scripts/test-all-affected is NOT here: ADR-262 withdrew it (see AFFECTED_CONSUMED_EDGES). Its
  # verdict is computed on sandbox copies of named files, not on the live tree.
  # #8591's TEST_GROUP=affected mutation suite — a runner-SUT property battery
  # like its sibling above; renamed out of the add/add collision with #8322's.
  "scripts/test-all-group-affected"
  "scripts/suite-exit-class-parity"
  # ADR-262 withdrew four self-test mutation batteries from this list — test-all-affected,
  # battery-tag-authorship-mutations and the two --rows halves of the lint-orphan battery (#8864).
  # Each is a mutation battery over a NAMED set of files, run on sandbox copies, so its edge set is
  # a declared array (AFFECTED_CONSUMED_EDGES) and not "the whole tree". Their SUBJECTS stay here.
  "plugins/soleur/test/scripts-shard-runtime-coverage.test.sh"

  # --- corpus linters: verdict spans a file class scanned wholesale -------------
  # A ratchet counts a property across the whole tree and references nothing —
  # no file-based query can ever return it (the #8023/#8092/#8177 class).
  "scripts/lint-agents-enforcement-tags-unit"
  "scripts/lint-credential-path-literals"
  "scripts/lint-diagnosis-claims"
  "scripts/lint-dual-lockfile"
  "scripts/lint-encryption-posture"
  "scripts/lint-infra-no-human-steps"
  "scripts/lint-legal-mirror-drift-baseline-unit"
  "scripts/lint-legal-registers-unit"
  "scripts/lint-legal-scope-block-placement-unit"
  "scripts/lint-art30-reverification-unit"
  "scripts/lint-migrated-rule-ids-unit"
  "scripts/lint-shell-capture-exit"
  "scripts/lint-shell-trace-credential-refusal-repo"
  "scripts/lint-supabase-deprecated-endpoints-unit"
  "scripts/lint-workflow-errexit-capture"
  "scripts/lint-workflow-issue-write-scope"
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
  # property over each. #9763 demoted all three operator suites below to
  # edge-selection with declared scopes covering every dir that holds *.sh
  # (including knowledge-base/ — generated operator scripts ship under
  # knowledge-base/project/specs/): a diff adding a consumer in one of those
  # dirs still re-runs them, while an unrelated diff no longer pays ~220 s.
  # operator-ack-guard (#8486): Guard 1 censuses every tracked *.sh for raw typed-yes
  # prompts and confirm-skip flags, and Guard 2's population is every
  # soleur_op_ack_or_die caller in the tree — covered by the same shell-dir edges.
  # operator-agent-runnable (ADR-264): Guard 1 DISCOVERS every generated operator script in the tree
  # (git grep over file content) — its declared edge covers knowledge-base/ where
  # generated scripts ship. operator-stage-approval-hook (derived edge: every
  # diff under plugins/soleur) and operator-9321-stages (declared edge below) are scoped, not
  # always-on: measured ~85 CPU-s that an unrelated web-platform or docs diff does not need to pay.
  "apps/web-platform/scripts/lib/no-cross-context-import.test.sh"

  # --- whole-corpus guards, drift checks, parity and census gates ---------------
  "scripts/ensure-kb-index"
  "plugins/soleur/test/kb-caches-untracked.test.sh"
  # (#8846) census of every tracked inngest probe-row reader over git ls-files.
  "scripts/marketplace-drift-check"
  "scripts/digest-oracle-guard"
  "scripts/follow-through-closure-guard"
  "scripts/followthrough-exec-bit"
  "scripts/alarm-issue-filing-guard"
  "scripts/battery-ref-guard"
  "scripts/betterstack-assert-absence"
  "scripts/betterstack-ingest-parity"
  "scripts/rule-metrics-aggregate"
  "scripts/skill-freshness-aggregate"
  # #8563's Tier-B credential census — a repo-global property census over every
  # workflow + Terraform tier declaration; no diff-scoped edge can reach it.
  "scripts/cron-artifact-age"
  "scripts/rename-guard"
  "scripts/assert-dependabot-drain-unit"
  "scripts/expenses-verify-by-check"
  "scripts/ship-incident-pir-gate-mutations"
  "plugins/soleur/test/auto-close-scanner.test.sh"
  "plugins/soleur/test/vendor-drift-classify.test.sh"
  "plugins/soleur/test/vendor-drift-workflow.test.sh"
  "plugins/soleur/test/token-drift-workflow-causes.test.sh"
  "plugins/soleur/test/check-deps-adapter-drift.test.sh"
  "plugins/soleur/test/terraform-drift-sentry-leg.test.sh"
  "plugins/soleur/test/c4-count-parity.test.sh"
  "plugins/soleur/test/workflow-run-deploy-invariants.test.sh"
  "plugins/soleur/test/reusable-release-caller-permissions.test.sh"
  "plugins/soleur/test/gitleaks-merge-commit.test.sh"
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
  # tests/scripts/hcloud-token-readonly-no-fallback-scan — the Hetzner read-only-token no-fallback scan (scripts/lint-hcloud-token-readonly-no-fallback.sh, #10664, ADR-241 D4) walks `git ls-files`
  # over the whole tracked tree (everything except a pinned exclusion list): a doppler secrets-get read of the
  # read/write Hetzner credential can appear in any file anywhere, so the verdict is a property of the tree,
  # not of a diff, and no path edge can express its selection. An edit to the scanner selects it too.
  "tests/scripts/hcloud-token-readonly-no-fallback-scan"
  "blog-link-validation"
  # (#9307) Audited as demotable and put back. The first reason was derive cost (~82 s of first-touch
  # attribution; 0.2 s once the runner became a closure leaf, always-on-audit.md Round 3), and that
  # reason is gone. It stays on the recorder's own rule: its test file carries four file-test/find
  # operands the scan cannot resolve, so the verdict is `disqualified` by construction.
  "scripts/domain-model-drift"

  # --- the never-gated web-platform arm -----------------------------------------
  # repo-wide's subject is the repository by construction (#7498); component
  # runs alongside it by a measured, twice-affirmed decision (#7666 revert).
  # --- re-promoted by the Round 2 audit (#9307 PR-B, scripts/audit-suite-reads.sh) ---------------
  # Each was demoted on one inotify run in PR 1; the committed recorder (verdict `disqualified`:
  # a file test/stat/ls/find operand it cannot resolve or a carried-disqualifier hit, or `uncovered`:
  # reads outside the cover) no longer supports the demotion. Always-on is the safe side of every
  # verdict. Evidence per suite: knowledge-base/project/specs/archive/20261013-062704-feat-affected-parallel-test-gate/always-on-audit.md "Round 2".
  "scripts/lint-agents-rule-budget-live"
  "scripts/lint-agents-rule-budget-unit"
  "scripts/lint-workflow-run-body-syntax"
  "scripts/verify-lockfile-guards"
  "scripts/marketplace-manifest-validate"
  "scripts/verify-marketplace-ruleset"
  "scripts/check-tom4-rls-posture-live"
  "scripts/lint-guard-contract"
  "scripts/lint-window-closure-assertion"
  "scripts/tenant-dpa-register-guard-unit"
  "scripts/tenant-dpa-register-guard-live"
  "scripts/probe-legal-corpus-truth-live"
  "scripts/check-pa-22-unit"
  "scripts/check-pa-22-live"
  "scripts/frontmatter-strip-parity"
  "plugins/soleur/test/terraform-drift-step-order.test.sh"
  "apps/web-platform/scripts/lint-migration-fk-preconditions.test.sh"
  # --- A5 hedge (#9307 PR-C): the runner stopped being a closure leaf for text mentions and this suite lost 726 of
  # its 736 derived edges. Its demote verdict is `disqualified` on the recorder's own rule (unresolved probe operands,
  # git-other and clock-epoch regex hits), so it stays hedged: 10.5 s of suite time (suite-durations.tsv) buys not having
  # to guess which of the 726 it read. The earlier explanation ("57 of 145 assertions fail under env -i with no network")
  # was disproved on 2026-10-04: the recorder ran suites as namespace-root and this suite refuses a privileged caller;
  # as the invoking user it passes 148/0. Evidence: always-on-audit.md "Round 3" and the 2026-10-04 addendum.
  # --- Round 3 re-check with the contamination fix (review of PR 9422, always-on-audit.md "Round 3 re-check"). The first recorder
  # runs reported the first window of every run as `contaminated` (tracked-but-gitignored files made the private checkout look dirty), so
  # the "unreliable" rows were an artifact. Re-run: these two are `uncovered` (reads outside their cover) and go back; the four after them
  # recorded only PARTIAL runs (a root-or-namespace SKIP of an arm, or a non-zero rc under env -i), so their reads are unobserved and the
  # cost of hedging is under 7 s each. Always-on is the safe side of every verdict.
  "scripts/lint-rule-ids-live"
  "scripts/check-tom4-rls-posture"
  "plugins/soleur/test/worktree-manager-atomic-config.test.sh"
  "plugins/soleur/test/worktree-manager-bare-in-dotgit-layout.test.sh"
  # --- Round 4 (section 2 of #9307; measurements and cost in always-on-audit.md, 2026-10-04 addendum). The recorder,
  # now running suites as the invoking user, recorded this suite completely and its read set is the registration corpus
  # itself: no short declaration bounds it, and the knowledge-base tree (read through `git ls-files`, invisible to
  # inotify) is a second input. Hedged rather than declared; revisit trigger in ADR-242 decision 19.

  "scripts/test-all-fast-tier-budget"
  # #9814: the local weight-drift detector — its verdict asserts properties of
  # the runner's own wiring (default arm, epilogue emit), a runner-SUT property
  # suite like its sibling above.
  "scripts/test-all-weight-drift"
  # --- #9763 withdrawn-to-edge-selection (committed weight >10s): these run on CI legs,
  # merge_group, push and --full like every registered suite, and locally only when their
  # subject paths change (edge-selected like any non-always-on suite, ADR-262 shape). The
  # fast-tier budget lint (scripts/test-all-fast-tier-budget) pins this set.

)

# CONSUMED EDGE SETS. These labels already carry their edge declarations in
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
  # Same consumed edge as [unit]: the bundle's app-local half (component) is
  # subject to the app, and repo-wide is the ungated sibling — post-#9815 its
  # argv no longer mentions apps/web-platform directly (it execs the wrapper),
  # so the derivation channel reads only the wrapper's own file.
  "apps/web-platform [repo-wide+component]|WEBPLAT_APP_PATHS"
  # The infra runner maps to AFFECTED_INFRA_RUNNER_PATHS (declared just below,
  # in THIS lib — the consumed mapping mechanism does not care which file owns
  # the array). Its edges are the same two predicates _infra_in_diff checks.
  "apps/web-platform/infra/run-registered-suites.sh|AFFECTED_INFRA_RUNNER_PATHS"
  # ADR-262: four self-test mutation batteries, withdrawn from ALWAYS_ON_SUITES. The two lint-orphan
  # halves share one array because they are two --rows ranges of one battery.
  "scripts/lint-orphan-test-suites-mutations-a|LINT_ORPHAN_BATTERY_PATHS"
  "scripts/lint-orphan-test-suites-mutations-b|LINT_ORPHAN_BATTERY_PATHS"
  "scripts/battery-tag-authorship-mutations|TAG_AUTHORSHIP_BATTERY_PATHS"
  "scripts/test-all-affected|TEST_ALL_AFFECTED_BATTERY_PATHS"
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

# tests/scripts/apply-github-infra-mint-shape (#9360) — shape pins over the one
# workflow job it reads through a $REPO_ROOT-built path, which no derivation
# channel reaches; its name stem maps to no script.
AFFECTED_TESTS_SCRIPTS_APPLY_GITHUB_INFRA_MINT_SHAPE_PATHS=(
  ".github/workflows/apply-github-infra.yml"
  ".github/actions/mint-infra-app-token/"
  "scripts/verify-ruleset-required-checks.sh"             # #9362: the gate it drives
  "scripts/lib/canonicalize-required-status-checks.sh"    # #9362: the projection the gate shares
  "scripts/ci-required-ruleset-canonical-required-status-checks.json"      # #9362: gate input
  "scripts/ci-cla-required-ruleset-canonical-required-status-checks.json"  # #9362: gate input
  "tests/scripts/fixtures/tfplan-real-ruleset-baseline.json"               # #9362: the real plan capture the rows are built from
  ".github/actions/infra-credentials/"                    # #9362: the loader that supplies every Terraform input the apply now takes
  "infra/github/"                                         # #9362: the rulesets the gated addresses must cover (G2c)
  "tests/scripts/test-apply-github-infra-mint-shape.sh"  # self-inclusion
  "scripts/lib/test-affected-paths.sh"                    # THIS FILE
)

# apps/cla-evidence/scripts/_r2-sigv4-curl.test.sh (#9756) — a corpus walker: its set-identity rows read every
# shell file under apps/cla-evidence for a curl that carries `--aws-sigv4` or `-u`/`--user`, so any shell edit
# there is its subject (the glob edge), not only the helper it is named for.
AFFECTED_APPS_CLA_EVIDENCE_SCRIPTS__R2_SIGV4_CURL_TEST_SH_PATHS=(
  "glob:apps/cla-evidence/**.sh"
  "scripts/lib/test-affected-paths.sh"                    # THIS FILE
)

# apps/cla-evidence/scripts/bootstrap-r2-probe.test.sh (#9756) — executes the real infra/bootstrap.sh (named only
# through a script-dir-relative cd, which no derivation channel reaches) with the helper and the two scripts it sources.
AFFECTED_APPS_CLA_EVIDENCE_SCRIPTS_BOOTSTRAP_R2_PROBE_TEST_SH_PATHS=(
  "apps/cla-evidence/infra/bootstrap.sh"
  "apps/cla-evidence/scripts/_r2-sigv4-curl.sh"
  "apps/cla-evidence/scripts/_cf-admin-token.sh"
  "apps/cla-evidence/scripts/_r2-endpoint.sh"
  "scripts/lib/test-affected-paths.sh"                    # THIS FILE
)

# Suites the repo-wide-idiom census arm flags (their fixture code walks a tree)
# whose real subject is a narrow SUT set, declared here rather than always-on:
# the scan is scoped, so the edges are honest.

# .claude/hooks/lib/context-sanitize.test.sh (#10395) — corpus walker: the drift
# sentinel greps every production file under .claude/hooks/ and plugins/soleur/
# for raw `tr -d` strips, so any file in those trees is its subject. Directory
# entries are prefix edges; the scan is exactly those two trees.
AFFECTED_CLAUDE_HOOKS_LIB_CONTEXT_SANITIZE_TEST_SH_PATHS=(
  ".claude/hooks/"
  "plugins/soleur/"
  "scripts/lib/test-affected-paths.sh"            # THIS FILE
)

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
# .claude/hooks/hook-suite-dep-unresolved.test.sh (#8616) — runs every guarded hook suite
# with one tool off PATH; its pair population is derived from the `.claude/hooks/` roots of
# test-all.sh's SUITE_GLOBS plus its own EXTRA_PAIRED_SUITES list, and its static sweep greps
# every non-hook runner glob plus scripts/*.test.sh, scripts/followthroughs/*.test.sh,
# tests/scripts/*.sh and the discoverability probes for SKIP+exit 0 (#8773 widened it).
# A directory entry is a prefix edge under the substring match.
AFFECTED_CLAUDE_HOOKS_HOOK_SUITE_DEP_UNRESOLVED_TEST_SH_PATHS=(
  ".claude/hooks/"
  "scripts/test-all.sh"
  "scripts/lib/test-affected-paths.sh"
  "glob:plugins/soleur/test/*.test.sh"
  "glob:plugins/soleur/skills/*/test/*.test.sh"
  "glob:plugins/soleur/scripts/*.test.sh"
  "glob:apps/cla-evidence/scripts/*.test.sh"
  "glob:apps/web-platform/scripts/*.test.sh"
  "glob:apps/web-platform/scripts/lib/*.test.sh"
  "glob:scripts/lib/*.test.sh"
  "glob:scripts/*.test.sh"
  "glob:scripts/followthroughs/*.test.sh"
  "glob:tests/scripts/*.sh"
  "scripts/context-reviewed-gate-discoverability.sh"
  "scripts/hook-input-fault-discoverability-probe.sh"
  "scripts/resend-alert-path-discoverability.sh"
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
# The other root `test/` bun suites (#9307). Their only derived edge used to be the
# bare `test` command word of `bun test <file>`, which resolved to the repo-root
# test/ directory and MASKED that they carried no real edge at all: they selected
# only when a diff path happened to contain "test", and not when their SUT changed.
AFFECTED_TEST_X_COMMUNITY_PATHS=(
  "plugins/soleur/skills/community/scripts/"
  "test/x-community.test.ts"
  "test/helpers/test-handle-response.sh"
  "test/helpers/test-check-metrics-anomaly.sh"
  "scripts/lib/test-affected-paths.sh"
)
AFFECTED_TEST_LINKEDIN_COMMUNITY_PATHS=(
  "plugins/soleur/skills/community/scripts/"
  "test/linkedin-community.test.ts"
  "test/helpers/test-handle-response-linkedin.sh"
  "scripts/lib/test-affected-paths.sh"
)
AFFECTED_TEST_CONTENT_PUBLISHER_PATHS=(
  "scripts/content-publisher.sh"
  "test/content-publisher.test.ts"
  "test/helpers/"
  "scripts/lib/test-affected-paths.sh"
)
# scripts/test-affected-kb-consumers (#9307) — the dropped-consumer ratchet for the demotions
# below. #9763 withdrew it from ALWAYS_ON: its read set is the registration corpus itself PLUS the
# knowledge-base/ tree (the ADR-242 decision-19 hedge was "unbounded kb reads"), so knowledge-base/
# is declared here — a kb diff selects it like the corpus inputs do. This array is RETAINED for
# pre-push-ratchet-lane arm 21, which pins the lane's KB_CONSUMERS_INPUTS to it; do not delete it.
AFFECTED_SCRIPTS_TEST_AFFECTED_KB_CONSUMERS_PATHS=(
  "knowledge-base/"
  "scripts/test-affected-kb-consumers.test.sh"
  "scripts/test-affected-kb-consumers.baseline.txt"
  "scripts/test-all.sh"
  "scripts/lib/test-affected-paths.sh"
)
# scripts/test-affected-derive (#9307) -- the derive in the runner and its bench
# (scripts/affected-prepass-bench.sh: run it with --base <rev> after ANY change to the derive; exit 0 is
# the acceptance contract). Declared rather than always-on: its subject is the runner's derive block and
# the bench, and it reads nothing else, so any other diff has no way to move it.
AFFECTED_SCRIPTS_TEST_AFFECTED_DERIVE_PATHS=(
  "scripts/test-affected-derive.test.sh"
  "scripts/affected-prepass-bench.sh"
  "scripts/test-all.sh"
  "scripts/lib/test-affected-paths.sh"
)
# scripts/test-affected-derive-cache (#9812) — the cross-run derive cache lib and its runner
# integration. Declared rather than always-on for the same reason as its sibling: the SUT is the
# cache lib plus the runner's derive span (extracted by content anchor), and nothing else can move
# its verdict. test-all.sh is a closure leaf, so a lib-only diff reaches this suite ONLY through
# this declaration.
AFFECTED_SCRIPTS_TEST_AFFECTED_DERIVE_CACHE_PATHS=(
  "scripts/test-affected-derive-cache.test.sh"
  "scripts/lib/test-affected-derive-cache.sh"
  "scripts/test-all.sh"
  "scripts/lib/test-affected-paths.sh"
)
# #9400 — the pre-push ratchet lane's Guard Contract suite. The edge set covers
# the lane's own pair, every member argv's file (a member whose semantics move
# must re-run the dispatch battery that invokes it), the hook wiring the lane is
# called from, the scratch-root lib the lane sources, and ci.yml — the parity
# arm reads CI's run: lines as a registration source. Self-inclusion per the
# file-header rule.
AFFECTED_SCRIPTS_PRE_PUSH_RATCHET_LANE_PATHS=(
  "scripts/pre-push-ratchet-lane.sh"
  "scripts/pre-push-ratchet-lane.test.sh"
  "scripts/lib/scratch-root.sh"
  "scripts/lint-trap-tempfile-ownership.py"
  "scripts/lint-supabase-deprecated-endpoints.sh"
  "scripts/lint-diagnosis-claims.sh"
  "scripts/lint-diagnosis-claims.test.sh"
  "scripts/alarm-issue-filing-guard.test.sh"
  "scripts/lint-workflow-step-env-refs.py"
  "scripts/plugin-root-anchor-debt.sh"
  "plugins/soleur/test/fixture-relative-assert.test.sh"
  "plugins/soleur/test/fixture-dir-operand-assert.test.sh"
  "plugins/soleur/test/fixture-cd-containment.test.sh"
  "scripts/lint-skill-body-budget.py"
  "scripts/lint-rule-bodies.py"
  "scripts/test-affected-kb-consumers.test.sh"
  "scripts/test-affected-kb-consumers.baseline.txt"
  "scripts/test-all.sh"
  "scripts/hooks/pre-push"
  "lefthook.yml"
  ".github/workflows/ci.yml"
  "plugins/soleur/test/lib/git-fixture-env.ts"
  "scripts/lib/test-affected-paths.sh"
)
# ALWAYS-ON AUDIT DEMOTIONS (#9307). (Every demotion below was recorded BEFORE the recorder stamped an identity, i.e.
# under idmap=root; they stand as a deliberate exception until the next edit to the suite's edge array, see ADR-242 decision 19. A skipped arm prints SKIP and
# rates its row unreliable; a silent skip is the residual risk.) Each suite below left ALWAYS_ON_SUITES because its
# OBSERVED reads are confined to the paths declared here: it ran serially under an inotify
# open-event recorder (no git-diff/ls-files dependence, no network, no clock, rc 0), and its
# edge set is the cover of what it opened -- a directory whose listing mattered, otherwise
# the exact files. The evidence per suite is in
# knowledge-base/project/specs/archive/20261013-062704-feat-affected-parallel-test-gate/always-on-audit.md; a suite
# is added here only with that evidence (the census linter does not check that), and the
# dropped-consumer ratchet (scripts/test-affected-kb-consumers.test.sh) covers
# knowledge-base/ reads ONLY. A demotion also moves the suite from a free always-on skip to a
# full source-closure derive in the pre-pass -- price it before adding one.
AFFECTED_SCRIPTS_LINT_AGENTS_COMPOUND_SYNC_UNIT_PATHS=(
  "scripts/lint-agents-compound-sync.sh"
  "scripts/lint-agents-compound-sync.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
# #6931: the web-2 follow-through test drives its stub against the probe-row parser; its verdict is
# scoped to the script, the parser it sources and the Better Stack query helper, not to corpus drift.
AFFECTED_SCRIPTS_WEB2_LUKS_LIVE_6931_PATHS=(
  "scripts/followthroughs/web2-luks-live-6931.sh"
  "scripts/followthroughs/web2-luks-live-6931.test.sh"
  "scripts/lib/web2-luks-rows.sh"
  "scripts/betterstack-query.sh"
  "scripts/lib/test-affected-paths.sh"
)
AFFECTED_SCRIPTS_TUNNEL_CONNECTOR_CENSUS_PATHS=(
  "scripts/tunnel-connector-census.sh"
  "scripts/tunnel-connector-census.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
AFFECTED_APPS_WEB_PLATFORM_TEST_PARSE_GITLEAKS_ALLOWLISTS_PATHS=(
  ".gitleaks.toml"
  "apps/web-platform/scripts/parse-gitleaks-allowlists.mjs"
  "apps/web-platform/test/__synthesized__/parse-gitleaks-allowlists.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
# vitest-related (#9815) — suite, wrapper, the runner arm it guards, the lib whose
# functions+META it exercises, and the config the META derivation reads. The meta
# set's members outside the app are listed too: a commit narrowing the predicate
# must run the suite the predicate gates (self-inclusion convention).
AFFECTED_APPS_WEB_PLATFORM_TEST_VITEST_RELATED_PATHS=(
  "apps/web-platform/scripts/vitest-related.sh"
  "apps/web-platform/test/vitest-related.test.sh"
  "apps/web-platform/vitest.config.ts"
  "scripts/lib/test-relevance-paths.sh"
  "scripts/lib/affected-glob.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/test-all.sh"
)
# scripts/followthroughs/pr-battery-gate-saving-9323 — reads scripts/lib/affected-glob.sh
# (named via test-relevance-paths.sh:110).
AFFECTED_SCRIPTS_FOLLOWTHROUGHS_PR_BATTERY_GATE_SAVING_9323_PATHS=(
  "scripts/followthroughs/pr-battery-gate-saving-9323.sh"
  "scripts/followthroughs/pr-battery-gate-saving-9323.test.sh"
  "scripts/lib/affected-glob.sh"
  "scripts/lib/test-relevance-paths.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/test-all.sh"
)
AFFECTED_PLUGINS_SOLEUR_TEST_OPERATOR_STAGE_APPROVAL_HOOK_TEST_SH_PATHS=(
  "plugins/soleur/hooks/hooks.json"
  "plugins/soleur/hooks/operator-stage-approval.sh"
  "plugins/soleur/scripts/lib/operator-script.sh"
  "plugins/soleur/skills/operator-bootstrap/template.sh"
  "plugins/soleur/test/lib/operator-stub-world.sh"
  "plugins/soleur/test/operator-stage-approval-hook.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
AFFECTED_PLUGINS_SOLEUR_TEST_OPERATOR_9321_STAGES_TEST_SH_PATHS=(
  "knowledge-base/project/specs/archive/20261013-062704-feat-one-shot-9321-scoped-app-token-doppler/bootstrap.sh"
  "plugins/soleur/hooks/operator-stage-approval.sh"
  "plugins/soleur/scripts/lib/operator-script.sh"
  "plugins/soleur/test/lib/operator-stub-world.sh"
  "tests/scripts/test-infra-privileged-tier-census.sh"
  "knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md"
  "plugins/soleur/test/operator-9321-stages.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
AFFECTED_PLUGINS_SOLEUR_SKILLS_INCIDENT_TEST_REDACT_SENTINEL_TEST_SH_PATHS=(
  "plugins/soleur/skills/incident/scripts/redact-sentinel.sh"
  "plugins/soleur/skills/incident/scripts/redact-engine.py"
  "plugins/soleur/skills/incident/test/redact-sentinel.test.sh"
  "scripts/lib/test-affected-paths.sh"
)
# plugins/soleur/test/web-host-escrow-diagnose-workflow (#9377) — reads the workflow, both runbooks and the two escrow scripts
# through $REPO-built paths no derivation channel reaches, so a later edit to any of them must still select this guard.
AFFECTED_PLUGINS_SOLEUR_TEST_WEB_HOST_ESCROW_DIAGNOSE_WORKFLOW_TEST_SH_PATHS=(
  ".github/workflows/web-host-escrow-diagnose.yml"
  "scripts/web-host-escrow-preflight.sh"
  "scripts/check-web-host-escrow-config.sh"
  "knowledge-base/engineering/operations/runbooks/web-host-birth.md"
  "knowledge-base/engineering/operations/runbooks/web-host-replace.md"
  "plugins/soleur/test/web-host-escrow-diagnose-workflow.test.sh"  # self-inclusion
  "scripts/lib/test-affected-paths.sh"                              # THIS FILE
)
AFFECTED_PLUGINS_SOLEUR_TEST_APPLY_DELIVERY_GAP_FOLLOWER_TEST_SH_PATHS=(
  "scripts/apply-delivery-gap.sh"
  ".github/workflows/apply-delivery-gap-follower.yml"
  ".github/workflows/apply-deploy-pipeline-fix.yml"
  ".github/workflows/apply-web-platform-infra.yml"
  "knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-red-run.md"
  "plugins/soleur/test/apply-delivery-gap-follower.test.sh"  # self-inclusion
  "scripts/lib/test-affected-paths.sh"                       # THIS FILE
)
AFFECTED_PLUGINS_SOLEUR_TEST_DIAGNOSE_INNGEST_VERIFY_WORKFLOW_TEST_SH_PATHS=(
  ".github/workflows/diagnose-inngest-verify.yml"
  "plugins/soleur/test/diagnose-inngest-verify-workflow.test.sh"  # self-inclusion
  "scripts/lib/test-affected-paths.sh"                            # THIS FILE
)
AFFECTED_PLUGINS_SOLEUR_TEST_PROC_TEST_SH_PATHS=(
  "plugins/soleur/scripts/lib/proc.sh"
  "plugins/soleur/test/proc.test.sh"
  # A5 runtime reads (recorder, check mode): sourced through a path the derive cannot resolve.
  "scripts/lib/scratch-root.sh"
  "scripts/lib/test-contention.sh"
  "scripts/lib/test-affected-paths.sh"
)
# plugins/soleur/test/test-pyramid-fixtures.test.sh — pins the fixture pair AND the
# `## Pyramid & Fast-Feedback Check` vocabulary in the agent body; name-stem derivation
# reaches neither, so both are declared edges here. The four restatement files are
# drift-pinned too, so their edits re-select this suite; test-helpers.sh is declared
# explicitly even though derivation reaches it (chokepoint of the whole suite).
AFFECTED_PLUGINS_SOLEUR_TEST_TEST_PYRAMID_FIXTURES_TEST_SH_PATHS=(
  "plugins/soleur/agents/engineering/review/test-design-reviewer.md"
  "plugins/soleur/skills/review/SKILL.md"
  "plugins/soleur/skills/review/workflows/review.workflow.js"
  "plugins/soleur/skills/plan/references/plan-issue-templates.md"
  "plugins/soleur/skills/work/SKILL.md"
  "plugins/soleur/test/fixtures/test-pyramid/"
  "plugins/soleur/test/test-helpers.sh"
  "plugins/soleur/test/test-pyramid-fixtures.test.sh"  # self-inclusion
  "scripts/lib/test-affected-paths.sh"                  # THIS FILE
)
# plugins/soleur/test/schedule-task-design.test.sh — pins the `# Task design:` header
# contract in both generated workflow templates + the Step 0b/Step 1 collection text in
# schedule/SKILL.md. The other asserted-on files (task-design-gate.md, templates,
# plan/deepen-plan SKILLs, workflow.js) are covered by content-reference derivation
# ($REPO_ROOT tokens in the suite); declared edges here are the SUT, self, and index.
AFFECTED_PLUGINS_SOLEUR_TEST_SCHEDULE_TASK_DESIGN_TEST_SH_PATHS=(
  "plugins/soleur/skills/schedule/SKILL.md"
  "plugins/soleur/test/schedule-task-design.test.sh"  # self-inclusion
  "plugins/soleur/test/test-helpers.sh"               # sourced shared harness
  "scripts/lib/scratch-root.sh"                       # sourced by test-helpers.sh:58
  "scripts/lib/test-affected-paths.sh"                # THIS FILE
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
  # A5 runtime reads (recorder, check mode): the suite copies the plugin's scripts and manifests into a fixture.
  "plugins/soleur/scripts/"
  "plugins/soleur/.claude-plugin/"
  "plugins/soleur/skills/merge-pr/SKILL.md"
  "plugins/soleur/test/lib/git-fixture-env.sh"
  "scripts/lib/scratch-root.sh"
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

# plugins/soleur — `bun test plugins/soleur/` runs every *.test.ts below the directory, and
# those files read real knowledge-base content (ADR frontmatter, the committed LikeC4 model,
# runbooks, legal and brand documents). Derivation reaches only ^plugins/soleur/ from a
# directory operand, so a knowledge-base-only diff never selected it. Found by the ratchet's
# directory-operand form (scripts/test-affected-kb-consumers.test.sh); the remaining
# knowledge-base strings in those files are fixtures or message text, classified in the baseline.
AFFECTED_PLUGINS_SOLEUR_PATHS=(
  "knowledge-base/engineering/architecture/decisions/"
  "knowledge-base/engineering/architecture/diagrams/"
  "knowledge-base/engineering/operations/runbooks/"
  "knowledge-base/legal/compliance-posture.md"
  "knowledge-base/legal/recommended-tools.md"
  "knowledge-base/marketing/brand-guide.md"
  "knowledge-base/overview/vision.md"
  "knowledge-base/project/specs/archive/20261013-051752-feat-one-shot-7586-7587-red-apply-no-channel-arm-deadline/"
  "packages/opencode-plugin/"
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)

# scripts/audit-suite-reads — the committed read recorder and its reader. Its verdict function
# is the subject; the python reader is data to the test that drives it. Added after the
# demotions above so a rebase over a sibling registration does not move an unrelated array.
AFFECTED_SCRIPTS_AUDIT_SUITE_READS_PATHS=(
  # the five file reads the 2026-10-04 recording found outside the old cover: the suite's one real-runner enumerate
  # (`test-all.sh --enumerate-commands all` under env -i) reads them. The 3,185 directory listings of that same walk are
  # NOT declared: the suite asserts only `>= 400` registrations, so a listing cannot move its verdict.
  ".bun-version"
  ".gitignore"
  "apps/web-platform/.gitignore"
  "apps/web-platform/infra/.gitignore"
  "apps/web-platform/supabase/.gitignore"
  "scripts/audit-suite-reads.sh"
  "scripts/audit-suite-reads.test.sh"
  "scripts/lib/inotify-open-recorder.py"
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)

# ---------------------------------------------------------------------------
# CLOSURE-LEAF RUNTIME READS (A5). Per-label arrays over the shared sets above; the recorder evidence is in
# knowledge-base/project/specs/archive/20261013-062704-feat-affected-parallel-test-gate/always-on-audit.md "Round 3".
# ---------------------------------------------------------------------------
AFFECTED_PLUGINS_SOLEUR_TEST_WORKTREE_MANAGER_BARE_SYNC_TEST_SH_PATHS=(
  "${_CLOSURE_LEAF_RT_WORKTREE_MANAGER[@]}"
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)
AFFECTED_PLUGINS_SOLEUR_TEST_WORKTREE_MANAGER_FEATURE_SPEC_DIR_TEST_SH_PATHS=(
  "${_CLOSURE_LEAF_RT_WORKTREE_MANAGER[@]}"
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)
AFFECTED_PLUGINS_SOLEUR_TEST_WORKTREE_MANAGER_HEAL_STALE_BRANCH_TEST_SH_PATHS=(
  "${_CLOSURE_LEAF_RT_WORKTREE_MANAGER[@]}"
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)
AFFECTED_PLUGINS_SOLEUR_TEST_WORKTREE_MANAGER_HOOK_DEPS_TEST_SH_PATHS=(
  "${_CLOSURE_LEAF_RT_WORKTREE_MANAGER[@]}"
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)
AFFECTED_PLUGINS_SOLEUR_TEST_WORKTREE_MANAGER_INSTALL_BOUNDED_TEST_SH_PATHS=(
  "${_CLOSURE_LEAF_RT_WORKTREE_MANAGER[@]}"
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)
AFFECTED_PLUGINS_SOLEUR_TEST_WORKTREE_MANAGER_PORCELAIN_SIGPIPE_TEST_SH_PATHS=(
  "${_CLOSURE_LEAF_RT_WORKTREE_MANAGER[@]}"
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)
AFFECTED_PLUGINS_SOLEUR_TEST_WORKTREE_MANAGER_SAFE_BRANCH_SANITIZATION_TEST_SH_PATHS=(
  "${_CLOSURE_LEAF_RT_WORKTREE_MANAGER[@]}"
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)
AFFECTED_PLUGINS_SOLEUR_TEST_WORKTREE_MANAGER_SANDBOX_TMP_SWEEP_TEST_SH_PATHS=(
  "${_CLOSURE_LEAF_RT_WORKTREE_MANAGER[@]}"
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)
AFFECTED_PLUGINS_SOLEUR_TEST_GIT_ENV_LIST_PARITY_TEST_SH_PATHS=(
  "${_CLOSURE_LEAF_RT_HOOKS[@]}"
  "scripts/pre-push-ratchet-lane.sh"                 # read at test lines 139 and 150-156; it lost its edge with the leaf rule
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)
AFFECTED_PLUGINS_SOLEUR_TEST_HOOK_GIT_ENV_COVERAGE_TEST_SH_PATHS=(
  "${_CLOSURE_LEAF_RT_HOOKS[@]}"
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)
AFFECTED_PLUGINS_SOLEUR_TEST_HOOK_GIT_ENV_RECEIPT_TEST_SH_PATHS=(
  "${_CLOSURE_LEAF_RT_HOOKS[@]}"
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)
AFFECTED_PLUGINS_SOLEUR_TEST_LEFTHOOK_BUN_TEST_MERGE_SKIP_TEST_SH_PATHS=(
  "${_CLOSURE_LEAF_RT_HOOKS[@]}"
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)

# tests/scripts/destroy-guard-regex-parity — its subjects are the seven EXPECTED_SITES it greps for one byte-identical
# regex. The derive used to reach a coarse `^tests/` edge by an accident of a doubly-assigned $REPO_ROOT; resolving
# `cd ... && pwd` to its real target (D1) removed the accident and the census linter then reported the suite
# unclassified, which this declaration answers with the files the suite actually names.
AFFECTED_TESTS_SCRIPTS_DESTROY_GUARD_REGEX_PARITY_PATHS=(
  ".github/workflows/apply-github-infra.yml"
  ".github/workflows/apply-sentry-infra.yml"
  ".github/workflows/apply-web-platform-infra.yml"
  "tests/scripts/test-destroy-guard-counter.sh"
  "tests/scripts/test-destroy-guard-counter-sentry.sh"
  "tests/scripts/test-destroy-guard-counter-web-platform.sh"
  "scripts/sentry-squash-ack-detect.sh"
  "tests/scripts/test-destroy-guard-regex-parity.sh"
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)

# scripts/followthrough-predicate-parity — recorder check mode on the post-A5 tree (review of PR 9422) found three runtime
# reads that only the runner's incidental edges used to cover: it sources them through a path the derive cannot resolve.
AFFECTED_SCRIPTS_FOLLOWTHROUGH_PREDICATE_PARITY_PATHS=(
  "plugins/soleur/scripts/lib/session-state.sh"
  ".claude/hooks/lib/hook-tool-kind.sh"
  ".claude/hooks/lib/log-rotation.sh"
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)

# The two shard-manifest parity suites check the committed generated pair, the generator and the CI wiring; their only derived edge
# was the plugin directory, so a diff that regenerates the manifest (this PR's own D5 diff) selected neither locally.
AFFECTED_PLUGINS_SOLEUR_TEST_SCRIPTS_SHARD_MANIFEST_TEST_SH_PATHS=(
  "scripts/suite-shard-legs.tsv"
  "scripts/suite-shard-legs-heavy.tsv"
  "scripts/suite-durations.tsv"
  "scripts/suite-durations-heavy.tsv"
  "scripts/regenerate-shard-manifest.py"
  ".github/workflows/ci.yml"
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)
AFFECTED_PLUGINS_SOLEUR_TEST_REGENERATE_SHARD_MANIFEST_TEST_SH_PATHS=(
  "scripts/suite-shard-legs.tsv"
  "scripts/regenerate-shard-manifest.py"
  ".github/workflows/ci.yml"
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
  ".claude/hooks/lib/"
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
  "scripts/lib/"
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
  ".github/workflows/"
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

# tests/scripts/git-data-wipe-wedge — derived edges could not reach its subject; the population is DERIVED at run time
# (git ls-files .github/workflows filtered to the workflows that plan or apply the web-platform root, plus the root's HCL
# for the -target dependency closure and the gate libraries those workflows source).
AFFECTED_TESTS_SCRIPTS_GIT_DATA_WIPE_WEDGE_PATHS=(
  ".github/workflows/"
  "glob:apps/web-platform/infra/*.tf"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/lib/"
  "tests/scripts/test-git-data-wipe-wedge.sh"
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

# tests/scripts/argv-bearer-sweep (#7843) — derived edges could not reach its subject: the population is
# DISCOVERED (every tracked scripts/followthroughs probe holding a credentialed curl, run under a PATH-shim
# curl), so the edge is the directory prefix, and the rows are keyed off the Rule E baseline.
AFFECTED_TESTS_SCRIPTS_ARGV_BEARER_SWEEP_PATHS=(
  "scripts/followthroughs/"
  # G1 PR-4a (#10937): the parity script is the one HMAC surface this suite still EXECUTES directly under the shim
  # (live status arm, hostile-credential, xtrace, big-secret and mutant rows); it used to be reached only through the retired probes.
  "scripts/check-deploy-script-parity.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/lint-shell-trace-credential-refusal-e.baseline.txt"
  # S2 (#9597): the suite pins the sentences these records carry about the converted surfaces.
  "knowledge-base/engineering/architecture/decisions/ADR-027-process-local-state-for-runners.md"
  "knowledge-base/engineering/architecture/decisions/ADR-100-inngest-dedicated-single-host-singleton-control-plane.md"
  "knowledge-base/engineering/operations/runbooks/betterstack-log-query.md"
  "knowledge-base/engineering/operations/runbooks/inngest-server.md"
  "knowledge-base/legal/article-30-register.md"
  # S3 (ADR-280): the S3 stage derives its population from the workflow and composite step texts and
  # executes the representative `run:` bodies, so an edit to any of them (or to the library) must select it.
  "scripts/lib/bearer-curl.sh"
  ".github/actions/anthropic-preflight/"
  ".github/actions/notify-ops-email/"
  ".github/workflows/board-status-sync.yml"
  ".github/workflows/canary-status.yml"
  ".github/workflows/git-data-cutover.yml"
  ".github/workflows/git-data-rung2-rehearsal.yml"
  ".github/workflows/kb-drift-walker.yml"
  ".github/workflows/rule-audit.yml"
  ".github/workflows/scheduled-inngest-health.yml"
  ".github/workflows/scheduled-prod-version-drift.yml"
  ".github/workflows/scheduled-terraform-drift.yml"
  ".github/workflows/sentry-audit-gate.yml"
  # S4 (ADR-280): the S4 stage executes the REAL step bodies and scripts it names (extracted from the YAML, run under a
  # recording curl) and derives the library-user manifest from the tree, so an edit to any consumer must select it.
  # The repo-wide HMAC census rides the full run: no edge can name "any tracked file".
  ".github/actions/dispatch-web-redeploy/"
  ".github/actions/mint-infra-app-token/"
  ".github/scripts/bump-inngest-bootstrap-pin.sh"
  ".github/workflows/apply-deploy-pipeline-fix.yml"
  ".github/workflows/apply-github-infra.yml"
  ".github/workflows/apply-inngest-rls.yml"
  ".github/workflows/deploy-inngest-image.yml"
  ".github/workflows/restart-inngest-server.yml"
  ".github/workflows/web-platform-release.yml"
  ".github/workflows/workspaces-luks-cutover.yml"
  "apps/web-platform/infra/infra-config-apply.sh"
  "apps/web-platform/infra/infra-config-gate.sh"
  "apps/web-platform/infra/infra-config-verify.sh"
  "apps/web-platform/infra/push-infra-config.sh"
  "apps/web-platform/infra/scripts/verify-tunnel-ingress-origin.sh"
  "apps/web-platform/scripts/github-app-key-status.sh"
  # The census allow-list and the parity audit pin the cutover script (two held-back argv HMAC arms, 17 converted copies); the live
  # lint row runs the checkout lint on the real tree; the redeploy row sources the seccomp alert emitter and hashes the profile.
  "scripts/cutover-inngest.sh"
  "scripts/lint-workflow-local-action-checkout.py"
  "scripts/seccomp-unenforced-alert.sh"
  "apps/web-platform/infra/seccomp-bwrap.json"
  "scripts/inngest-liveness-classify.sh"
  "scripts/inngest-restart-poll-classify.sh"
  "plugins/soleur/skills/ship/SKILL.md"
  "plugins/soleur/skills/postmerge/references/deploy-status-debugging.md"
  # S9 (#9757 item 2): the stage extracts and EXECUTES the rehearsal workflow's two terraform destroy step bodies under stubs and pins the
  # export position in all four terraform steps, so an edit to that workflow must select it. The scan itself rides the full run.
  ".github/workflows/inngest-provision-rehearsal.yml"
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
  "infra/github/"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/fixtures/"
  "tests/scripts/fixtures/tfplan-real-ruleset-baseline.json"
  "tests/scripts/lib/destroy-guard-filter.jq"
  "tests/scripts/test-destroy-guard-counter.sh"
)

# tests/scripts/destroy-guard-counter-sentry — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_DESTROY_GUARD_COUNTER_SENTRY_PATHS=(
  ".github/workflows/apply-sentry-infra.yml"
  "apps/web-platform/infra/sentry/"
  "knowledge-base/project/specs/archive/20261013-051752-fix-7650-sentry-alert-migration/"
  "scripts/lib/test-affected-paths.sh"
  "scripts/sentry-destroy-counts.sh"
  "tests/scripts/fixtures/"
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
  ".github/actions/cf-tunnel-ssh-bridge/"
  ".github/workflows/apply-web-platform-infra.yml"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/lib/vector-redeliver-gate.sh"
  "tests/scripts/test-registry-d10-workflow-wiring.sh"
  "tests/scripts/test-vector-redeliver-wiring.sh"
)

# tests/scripts/main-duplicate-skip — the proof script is invoked by workflow
# steps; derived edges could not reach them, so the five gated workflows are
# declared here.
AFFECTED_TESTS_SCRIPTS_MAIN_DUPLICATE_SKIP_PATHS=(
  ".github/workflows/infra-validation.yml"
  ".github/workflows/skill-security-scan-corpus.yml"
  ".github/workflows/tenant-integration.yml"
  ".github/workflows/validate-vector-config.yml"
  ".github/workflows/vendor-pin-verify.yml"
  "scripts/lib/test-affected-paths.sh"
  "scripts/main-push-duplicate-skip.sh"
  "tests/scripts/test-main-duplicate-skip.sh"
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
  "scripts/registry-restore-from-ghcr.sh"
  "tests/scripts/lib/restore-engine-header.sh"
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
  "apps/web-platform/infra/sentry/"
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
  "tests/scripts/fixtures/"
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
  "knowledge-base/project/specs/archive/20261013-051752-fix-7650-sentry-alert-migration/phase2-live-workflows-capture-2026-09-04.json"
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
  ".github/workflows/pr-quality-guards.yml"
  "plugins/soleur/skills/skill-security-scan/scripts/parse-override.sh"
  "plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh"
  "scripts/guard-vacuity-floor.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/skill-security-scan-step-body.test.sh"
)

# scripts/secret-scan-smoke-gate (#9727, ADR-276 S1) — the suite extracts the smoke-relevance step body and the
# smoke-tests job from the workflow, reads scripts/required-checks.txt and the canonical required-checks ruleset JSON,
# and sweeps every tracked file (git ls-files) through the body; declared from the repo paths its suite file names
# (a directory entry carries a trailing slash). The runbook is named as text and as a subject operand, not read; the
# edge is the conservative cover for the kb-consumer ratchet, since SUBJECT_RE lists that exact path.
AFFECTED_SCRIPTS_SECRET_SCAN_SMOKE_GATE_PATHS=(
  ".github/workflows/secret-scan.yml"
  ".gitleaks.toml"
  "apps/web-platform/scripts/"
  "knowledge-base/engineering/operations/secret-scanning.md"
  "scripts/ci-required-ruleset-canonical-required-status-checks.json"
  "scripts/guard-vacuity-floor.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/required-checks.txt"
  "scripts/secret-scan-smoke-gate.test.sh"
)

# scripts/learning-retrieval-bench — the suite runs the bench script's own --self-test once, as a subprocess, under a
# hostile environment; the subject is the script, and the suite file is its own edge.
AFFECTED_SCRIPTS_LEARNING_RETRIEVAL_BENCH_PATHS=(
  "scripts/guard-vacuity-floor.test.sh"
  "scripts/learning-retrieval-bench.sh"
  "scripts/learning-retrieval-bench.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/ci-push-dedupe (#9512, ADR-276 S2; S4 PR B) — the suite extracts the push-dedupe proof step from ci.yml and executes it,
# parses the eight gated conditions and pins the test aggregator. It reads two further repo files: the release workflow (it EXTRACTS
# and EXECUTES that workflow's declared-path budget function against ci.yml) and the pr-selection driver (the leg-parity row reads its
# gateable-leg list and its final-block regex). Declared from the repo paths its suite file names (guard-vacuity-floor.test.sh is the
# meta-guard that drives its floor).
AFFECTED_SCRIPTS_CI_PUSH_DEDUPE_PATHS=(
  ".github/workflows/ci.yml"
  ".github/workflows/web-platform-release.yml"
  "scripts/ci-pr-selection.sh"
  "scripts/ci-push-dedupe.test.sh"
  "scripts/guard-vacuity-floor.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/ci-draft-light (#9728, ADR-276 S3) — the suite extracts the draft-light step, the four gated conditions and the test
# aggregator's draft arm from ci.yml and executes them; it also reads the required-check name sources it pins the gated set against.
# Declared from the repo paths its suite file names (guard-vacuity-floor.test.sh is the meta-guard that drives its floor).
AFFECTED_SCRIPTS_CI_DRAFT_LIGHT_PATHS=(
  ".github/workflows/ci.yml"
  ".github/actions/bot-pr-with-synthetic-checks/action.yml"
  "apps/web-platform/server/inngest/functions/_cron-safe-commit.ts"
  "infra/github/ruleset-ci-required.tf"
  "scripts/ci-draft-light.test.sh"
  "scripts/ci-required-ruleset-canonical-required-status-checks.json"
  "scripts/guard-vacuity-floor.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/required-checks.txt"
)

# scripts/ci-pr-selection (#9729, ADR-276 S4) — the suite EXECUTES the pr-selection driver against throwaway git fixtures and a stub
# runner, derives the trigger list from what scripts/test-all.sh sources and the --pr-gated decline labels from its text, and reads
# the git-fixture env library. Declared from the repo paths its suite file names (guard-vacuity-floor.test.sh is the meta-guard that
# drives its floor).
AFFECTED_SCRIPTS_CI_PR_SELECTION_PATHS=(
  "plugins/soleur/test/lib/git-fixture-env.sh"
  "scripts/ci-pr-selection.sh"
  "scripts/ci-pr-selection.test.sh"
  "scripts/guard-vacuity-floor.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/test-all.sh"
)

# plugins/soleur/test/ci-shard-totality-skip (#9729, ADR-276 amendment) — the suite pins the shard-totality classify step in
# ci.yml, executes the classifier script, and sweeps every workflow for the falsy-middle ternary shape, so the one corpus it walks
# is .github/workflows. Declared from the repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_CI_SHARD_TOTALITY_SKIP_TEST_SH_PATHS=(
  ".github/workflows/"
  "plugins/soleur/test/ci-shard-totality-skip.test.sh"
  "scripts/ci-e2e-classify.sh"
  "scripts/ci-shard-totality-classify.sh"
  "scripts/lib/test-affected-paths.sh"
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
  ".github/workflows/"
  ".github/workflows/ci.yml"
  "plugins/soleur/test/ci-concurrency-key.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/merge-effect-class-parity.test.sh — derived edges could not reach its subject (the workflows' trigger
# blocks); declared from the repo paths its suite file names. Editing the classifier's allowlist is the exact weakening it catches.
AFFECTED_PLUGINS_SOLEUR_TEST_MERGE_EFFECT_CLASS_PARITY_TEST_SH_PATHS=(
  ".github/workflows"
  "plugins/soleur/scripts/merge-effect-class.sh"
  "plugins/soleur/scripts/merge-effect-class.ci-only.tsv"
  "plugins/soleur/test/merge-effect-class-parity.test.sh"
  "plugins/soleur/test/workflow-run-deploy-invariants.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/scripts/merge-effect-class.test.sh — reads the consumer sentence in operator-holds.md and the parity suite.
AFFECTED_PLUGINS_SOLEUR_SCRIPTS_MERGE_EFFECT_CLASS_TEST_SH_PATHS=(
  "plugins/soleur/scripts/merge-effect-class.sh"
  "plugins/soleur/scripts/merge-effect-class.ci-only.tsv"
  "plugins/soleur/scripts/merge-effect-class.test.sh"
  "plugins/soleur/skills/ship/references/operator-holds.md"
  "plugins/soleur/test/merge-effect-class-parity.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_CI_TEST_AGGREGATOR_DIAGNOSIS_TEST_SH_PATHS=(
  ".github/workflows/"
  ".github/workflows/ci.yml"
  "plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/deploy-script-tests-aggregator-diagnosis.test.sh — same class as
# the ci.yml sibling above; declared from the repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_DEPLOY_SCRIPT_TESTS_AGGREGATOR_DIAGNOSIS_TEST_SH_PATHS=(
  ".github/workflows/"
  ".github/workflows/infra-validation.yml"
  "plugins/soleur/test/deploy-script-tests-aggregator-diagnosis.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/ci-path-gating.test.sh — #8897 path-gating pins; derived edges could
# not reach its two workflow subjects; declared from the repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_CI_PATH_GATING_TEST_SH_PATHS=(
  ".github/workflows/"
  ".github/workflows/pr-quality-guards.yml"
  ".github/scripts/check-client-pii-sentry.sh"
  ".github/scripts/check-settings-integrity.sh"
  ".github/scripts/check-sweep-completeness.sh"
  "plugins/soleur/test/ci-path-gating.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/infra-validation-detect.test.sh — walks a corpus (the
# TS13b sentinel census `find`s under apps/ + infra/) and pins the workflow's
# run-block structurally; declared from the repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_INFRA_VALIDATION_DETECT_TEST_SH_PATHS=(
  ".github/workflows/infra-validation.yml"
  "apps/"
  "infra/"
  "plugins/soleur/test/infra-validation-detect.test.sh"
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

# plugins/soleur/test/flip-update-existing-override.test.sh — extracts fs_api, read_feature_segment_id and
# flip_segment_in_env out of flip.sh by content at run time, so no derived import edge reaches its subject;
# declared from the script it names.
AFFECTED_PLUGINS_SOLEUR_TEST_FLIP_UPDATE_EXISTING_OVERRIDE_TEST_SH_PATHS=(
  "plugins/soleur/skills/flag-set-role/scripts/flip.sh"
  "plugins/soleur/test/flip-update-existing-override.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/flagsmith-stdin-config.test.sh — extracts the shipped `_bearer_ok` + `fs_api` text out of each
# Flagsmith operator script at run time, so no derived import edge reaches its subjects; declared from the four
# scripts it names.
AFFECTED_PLUGINS_SOLEUR_TEST_FLAGSMITH_STDIN_CONFIG_TEST_SH_PATHS=(
  "plugins/soleur/skills/flag-create/scripts/create.sh"
  "plugins/soleur/skills/flag-delete/scripts/delete.sh"
  "plugins/soleur/skills/flag-list/scripts/list.sh"
  "plugins/soleur/skills/flag-set-role/scripts/flip.sh"
  "plugins/soleur/test/flagsmith-stdin-config.test.sh"
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
  ".github/actions/notify-ops-email/action.yml"
  ".github/workflows/scheduled-terraform-drift.yml"
  "plugins/soleur/lib/heartbeat-live-reconcile.ts"
  "plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh"
  "scripts/lib/bearer-curl.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/sole-copy-drift-check.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_TEST_SOLE_COPY_DRIFT_CHECK_TEST_SH_PATHS=(
  ".github/actions/infra-credentials/action.yml"
  ".github/actions/notify-ops-email/action.yml"
  ".github/workflows/scheduled-terraform-drift.yml"
  "apps/web-platform/infra/inngest-redis-luks.tf"
  "knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md"
  "knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md"
  "knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md"
  "plugins/soleur/skills/postmerge/SKILL.md"
  "plugins/soleur/test/lib/gha-expr.py"
  "plugins/soleur/test/sole-copy-drift-check.test.sh"
  "scripts/lib/bearer-curl.sh"
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

# plugins/soleur/test/claude-code-action-auth.test.sh — a census over every workflow file; any
# new or edited workflow under .github/workflows/ can add a consumer (or strip a token path), so
# the directory prefix is the edge. Derived edges reach none of the workflow subjects.
AFFECTED_PLUGINS_SOLEUR_TEST_CLAUDE_CODE_ACTION_AUTH_TEST_SH_PATHS=(
  ".github/workflows/"
  "plugins/soleur/test/claude-code-action-auth.test.sh"
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

# plugins/soleur/test/inngest-config-bundle-mirror.test.sh — executes the mirror step body extracted from the bundle
# workflow, so a workflow-only diff must select it; derived edges cannot reach a YAML subject.
AFFECTED_PLUGINS_SOLEUR_TEST_INNGEST_CONFIG_BUNDLE_MIRROR_TEST_SH_PATHS=(
  ".github/workflows/build-inngest-config-bundle.yml"
  "apps/web-platform/infra/cosign-trusted-root.json"
  "apps/web-platform/infra/inngest-signing-config.json"
  "plugins/soleur/test/inngest-config-bundle-mirror.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/diagnose-inngest-verify-workflow.test.sh — executes probe steps extracted from the
# diagnose workflow, so a workflow-only diff must select it; derived edges cannot reach a YAML subject.
AFFECTED_PLUGINS_SOLEUR_TEST_DIAGNOSE_INNGEST_VERIFY_WORKFLOW_TEST_SH_PATHS=(
  ".github/workflows/diagnose-inngest-verify.yml"
  "plugins/soleur/test/diagnose-inngest-verify-workflow.test.sh"
  "scripts/lib/test-affected-paths.sh"
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
  "apps/web-platform/"
  "apps/web-platform/scripts/constraint-gates.sh"
  "plugins/soleur/skills/"
  "plugins/soleur/skills/constraint-scaffold/test/boundary.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/test-all.sh"
)

# plugins/soleur/skills/constraint-scaffold/test/emit-fix-constraints.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_SKILLS_CONSTRAINT_SCAFFOLD_TEST_EMIT_FIX_CONSTRAINTS_TEST_SH_PATHS=(
  "apps/web-platform/"
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
  "apps/web-platform/"
  "plugins/soleur/skills/"
  "plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh"
  "plugins/soleur/skills/constraint-scaffold/test/generator.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/test-all.sh"
)

# plugins/soleur/skills/constraint-scaffold/test/parity.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_SKILLS_CONSTRAINT_SCAFFOLD_TEST_PARITY_TEST_SH_PATHS=(
  ".github/workflows/pr-quality-guards.yml"
  ".github/workflows/fix-constraints-stage-a.yml"
  ".github/workflows/fix-constraints-stage-b.yml"
  "apps/web-platform/"
  "plugins/soleur/skills/"
  "plugins/soleur/skills/constraint-scaffold/references/"
  "plugins/soleur/skills/constraint-scaffold/test/parity.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/test-all.sh"
)

# plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_SKILLS_GIT_WORKTREE_TEST_CREATE_FROM_ORIGIN_MAIN_TEST_SH_PATHS=(
  "knowledge-base/project/plans/archive/20261013-014038-2026-05-14-fix-worktree-create-from-origin-main-plan.md"
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
  "plugins/soleur/scripts/lib/session-state.sh"
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
  "knowledge-base/project/plans/archive/20261013-041741-2026-07-31-fix-honest-failure-reporting-hook-timeout-and-orphan-reaper-plan.md"
  "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"
  "plugins/soleur/skills/git-worktree/test/orphan-reaper-honest-count.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/skills/git-worktree/test/reap-archive-persistence.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_SKILLS_GIT_WORKTREE_TEST_REAP_ARCHIVE_PERSISTENCE_TEST_SH_PATHS=(
  "knowledge-base/project/plans/archive/20261013-051752-2026-09-28-fix-reaper-archive-tracked-kb-persistence-plan.md"
  "plugins/soleur/scripts/lib/session-state.sh"
  "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"
  "plugins/soleur/skills/git-worktree/test/reap-archive-persistence.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/skills/git-worktree/test/stale-lock-sweep.test.sh — derived edges could not reach its subject; declared from the
# repo paths its suite file names.
AFFECTED_PLUGINS_SOLEUR_SKILLS_GIT_WORKTREE_TEST_STALE_LOCK_SWEEP_TEST_SH_PATHS=(
  "knowledge-base/project/plans/archive/20261013-041741-2026-07-01-fix-stale-git-lock-sweep-worktree-plan.md"
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
  "apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh"
  "apps/web-platform/infra/cloud-init-inngest-zot-pull-mutation.test.sh"
  "apps/web-platform/infra/cron-egress-firewall.test.sh"
  "apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh"
  ".claude/hooks/grep-q-pipe-guard.test.sh"
  ".claude/hooks/lib/"
  "plugins/soleur/skills/compound/test/phase-16.test.sh"
  "plugins/soleur/skills/git-worktree/test/reap-archive-persistence.test.sh"
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

# plugins/soleur/test/ticket-triage-clauses.test.sh — clause presence in the intake
# pre-check. Succeeds ticket-triage-mirror-parity.test.sh, which asserted BYTE parity
# between the Claude agent and the OpenHands mirror and was deleted with that mirror
# (2026-09-23, ADR-245). Identity lost its second operand; clause presence did not
# depend on one, so that half survives here.
#
# Unlike its predecessor, skills/triage/SKILL.md IS an edge: the successor asserts the
# two clauses the attended WRITE path owns, so an edit there can break it.
AFFECTED_PLUGINS_SOLEUR_TEST_TICKET_TRIAGE_CLAUSES_TEST_SH_PATHS=(
  "plugins/soleur/agents/support/ticket-triage.md"
  "plugins/soleur/skills/triage/SKILL.md"
  "plugins/soleur/test/ticket-triage-clauses.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# tests/scripts/dev-suite-mutex-wiring — wiring assertion over the tenant-
# integration mutex's four SUT files ($ROOT-prefixed literals defeat
# derivation); declared from the repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_DEV_SUITE_MUTEX_WIRING_PATHS=(
  ".github/actions/dev-migration-drift-probe/action.yml"
  ".github/workflows/scheduled-dev-migration-drift.yml"
  ".github/workflows/scheduled-integration-suites.yml"
  ".github/workflows/tenant-integration.yml"
  "scripts/dev-suite-mutex.sh"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/test-dev-suite-mutex-wiring.sh"
)

# tests/scripts/assert-dev-doppler-scope-wiring — the wiring gate for the
# shared dev-Doppler boundary script (#9947): its SUT is the script plus the
# three workflow consumers it pins.
AFFECTED_TESTS_SCRIPTS_ASSERT_DEV_DOPPLER_SCOPE_WIRING_PATHS=(
  ".github/workflows/dev-ledger-reconcile.yml"
  ".github/workflows/scheduled-integration-suites.yml"
  ".github/workflows/tenant-integration.yml"
  "scripts/assert-dev-doppler-scope.sh"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/test-assert-dev-doppler-scope-wiring.sh"
)

# tests/scripts/no-tofu-ssh-mutation — mutation harness for the no-tofu-ssh
# guard (#7226/ADR-237); its SUT is the guard file itself plus its own harness,
# the same shape as orphan-process-reaper-mutations above.
AFFECTED_TESTS_SCRIPTS_NO_TOFU_SSH_MUTATION_PATHS=(
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/test-no-tofu-ssh.sh"
  "tests/scripts/test-no-tofu-ssh-mutation.sh"
)

# tests/scripts/dispatch-web-redeploy — exercises track.sh, the webhook
# same-version redeploy lever (#8211 PR2); the follower workflow is retired.
AFFECTED_TESTS_SCRIPTS_DISPATCH_WEB_REDEPLOY_PATHS=(
  ".github/actions/dispatch-web-redeploy/"
  ".github/workflows/git-data-cutover.yml"
  ".github/workflows/apply-web-platform-infra.yml"
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

# tests/scripts/tmp-purge — operator purge + shared classifier (#7004/ADR-250);
# declared from the repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_TMP_PURGE_PATHS=(
  "plugins/soleur/scripts/lib/tmp-classify.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/soleur-tmp-purge.sh"
  "tests/scripts/test-tmp-purge.sh"
)

# tests/scripts/scratch-session — allocator + Reaper 3 + session sweep
# (#7004/ADR-250) is ALWAYS_ON (above), so it declares no array here.

# tests/scripts/cleanup-merged-space — opt-in Docker prune, space report and the
# cleanup-merged wrapper (#9677); declared from the repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_CLEANUP_MERGED_SPACE_PATHS=(
  "plugins/soleur/scripts/lib/tmp-classify.sh"
  "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"
  "scripts/lib/test-affected-paths.sh"
  "tests/scripts/test-cleanup-merged-space.sh"
)

# tests/scripts/soleur-sandbox — agent sandbox allocator (ADR-250 Amendment 1);
# declared from the repo paths its suite file names.
AFFECTED_TESTS_SCRIPTS_SOLEUR_SANDBOX_PATHS=(
  "scripts/lib/scratch-root.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/soleur-sandbox.sh"
  "tests/scripts/test-soleur-sandbox.sh"
)

# tests/scripts/scratch-residue — direct-run residue canary over the runner
# chokepoints (ADR-250 Amendment 1); declared from the repo paths it names.
AFFECTED_TESTS_SCRIPTS_SCRATCH_RESIDUE_PATHS=(
  ".claude/hooks/grep-rewrite.test.sh"
  ".claude/hooks/lib/test-incident-sandbox.sh"
  "apps/web-platform/test/global-setup-git-tripwire.ts"
  "plugins/soleur/scripts/lib/tmp-classify.sh"
  "plugins/soleur/test/lib/git-tripwire.ts"
  "plugins/soleur/test/lib/scratch-session.ts"
  "plugins/soleur/test/test-helpers.sh"
  "scripts/lib/scratch-root.sh"
  "scripts/lib/test-affected-paths.sh"
  "tests/conftest.py"
  "tests/scripts/_git_fixture_env.py"
  "tests/scripts/test-scratch-residue.sh"
  "tests/scripts/test-weakness-miner.sh"
)

# plugins/soleur/skills/agent-browser/test/playwright-mcp-lifetime — the browser-lifetime guard contract.
# Its verdict is a property of the hook registry (every command of every event, plus the scripts they invoke),
# both MCP registrations, the slot script the project launch string sources, the proxy that string runs and the
# config it names. Argv literals reach only the slot script and the proxy; the registry and registrations are
# read from parsed JSON at test time, so no derivation sees them.
AFFECTED_PLUGINS_SOLEUR_SKILLS_AGENT_BROWSER_TEST_PLAYWRIGHT_MCP_LIFETIME_TEST_SH_PATHS=(
  ".claude/playwright-mcp.config.json"
  ".mcp.json"
  "plugins/soleur/.mcp.json"
  "plugins/soleur/hooks/"
  "plugins/soleur/skills/agent-browser/scripts/playwright-mcp-profile-slot.sh"
  "plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py"
  "plugins/soleur/skills/agent-browser/scripts/redact-a11y-snapshot.py"
  "plugins/soleur/skills/agent-browser/test/playwright-mcp-lifetime.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# --- #9763: declared edges for suites withdrawn from ALWAYS_ON whose derivation is self-only.
# A self-only derivation degrades to `unclassified` which SELECTS fail-safe — for a heavy suite that
# would leak it back into every local --affected run. Each array binds the suite to the subject its
# verdict is actually a property of.

# plugins/soleur/test/hook-input-classification-mutation — a mutation battery over the hook-input
# classifier: it mutates the SUT and the contract suite under .claude/hooks/.
AFFECTED_PLUGINS_SOLEUR_TEST_HOOK_INPUT_CLASSIFICATION_MUTATION_TEST_SH_PATHS=(
  ".claude/hooks/hook-input-contract.test.sh"
  ".claude/hooks/lib/hook-input.sh"
  "plugins/soleur/test/hook-input-classification-mutation.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/devin-docs-drift-check — behavioural gate for the scheduled docs-drift workflow: the check
# step's anchors it extracts verbatim, plus the docs trees the watch scans.
AFFECTED_SCRIPTS_DEVIN_DOCS_DRIFT_CHECK_PATHS=(
  ".github/workflows/scheduled-devin-docs-drift.yml"
  "docs/"
  "plugins/soleur/docs/"
  "scripts/devin-docs-drift-check.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# tests/scripts/infra-privileged-tier-census — the Tier-B privileged-credential census (#8209,
# ADR-241): scans every workflow for environment: declarations and the terraform deployment-policy
# objects that arm them.
AFFECTED_TESTS_SCRIPTS_INFRA_PRIVILEGED_TIER_CENSUS_PATHS=(

  ".github/"
  "apps/"
  "infra/"
  "knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md"
  "tests/scripts/test-infra-privileged-tier-census.sh"
  "scripts/lib/test-affected-paths.sh"
)

# tests/scripts/trio-baseline-census — the deploy-channel trio census, Guard 1a (#9294 G1). Its population is
# `git ls-files --cached --others` repo-wide (every file can name the trio: .github, scripts, plugins, apps, and the
# .md skill docs), minus the prose and media under knowledge-base/ and docs/ (a CODE extension there is scanned); it
# reads the sibling census for the Tier-B environment set, and its ratchet reads git history. So the edge is every
# top-level entry (declared, not derived: no argv literal reaches the files it scans; a new top-level entry needs a
# line here, and the suite's A5 row fails when one is missing) plus one `glob:knowledge-base/**.<ext>` per code
# extension it scans there (the suite pins that list as the `@kbcode` record and A5 checks the two agree). ADR-241 is
# declared individually: the ratchet diffs its Re-date and Allow lines. The self-edge literal is required by the
# declared-edge census.
AFFECTED_TESTS_SCRIPTS_TRIO_BASELINE_CENSUS_PATHS=(
  ".agents/"
  ".bun-version"
  ".claude-plugin/"
  ".claude/"
  ".codex/"
  ".cursor-plugin/"
  ".devin/"
  ".doppler.yaml"
  ".gitattributes"
  ".github/"
  ".gitignore"
  ".gitleaks.toml"
  ".gitleaksignore"
  ".grok/"
  ".markdownlint.json"
  ".markdownlintignore"
  ".mcp.json"
  ".nvmrc"
  ".soleur-test-gate.json"
  "AGENTS.md"
  "AGENTS.rules.md"
  "CLAUDE.md"
  "CODE_OF_CONDUCT.md"
  "CONTRIBUTING.md"
  "LICENSE"
  "LICENSES/"
  "README.md"
  "apps/"
  "bin/"
  "bunfig.toml"
  "cla-smoke-test.md"
  "docs/"
  "eleventy.config.js"
  "feature-request-plugin-dir-settings.md"
  "feature-request-plugin-update-surfaces-install-divergence.md"
  "infra/"
  "lefthook.yml"
  "package-lock.json"
  "package.json"
  "packages/"
  "plugins/"
  "pricing-wireframe.pen"
  "ruff.toml"
  "scripts/"
  "spike/"
  "test/"
  "tests/"
  "todos/"
  "glob:knowledge-base/**.sh"
  "glob:knowledge-base/**.bash"
  "glob:knowledge-base/**.zsh"
  "glob:knowledge-base/**.py"
  "glob:knowledge-base/**.pl"
  "glob:knowledge-base/**.rb"
  "glob:knowledge-base/**.ps1"
  "glob:knowledge-base/**.mk"
  "glob:knowledge-base/**Makefile"
  "glob:knowledge-base/**.ts"
  "glob:knowledge-base/**.tsx"
  "glob:knowledge-base/**.js"
  "glob:knowledge-base/**.jsx"
  "glob:knowledge-base/**.mjs"
  "glob:knowledge-base/**.cjs"
  "glob:knowledge-base/**.yml"
  "glob:knowledge-base/**.yaml"
  "glob:knowledge-base/**.tf"
  "glob:knowledge-base/**.tfvars"
  "glob:knowledge-base/**.tmpl"
  "glob:knowledge-base/**.hcl"
  "glob:knowledge-base/**.toml"
  "glob:knowledge-base/**.json"
  "glob:knowledge-base/**.cfg"
  "glob:knowledge-base/**.service"
  "glob:knowledge-base/**.timer"
  "knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/battery-tag-authorship — census of tag-authoring git commands reachable from the battery:
# the write-boundary softening in repo-write-boundary.sh and the runner's own command surface.
# The exemption-ledger bijection greps the forge lib verbatim for the ledgered command (#10921).
AFFECTED_SCRIPTS_BATTERY_TAG_AUTHORSHIP_PATHS=(
  "plugins/soleur/test/lib/git-corrupt-graph.sh"
  "scripts/battery-tag-authorship.test.sh"
  "scripts/battery-tag-authorship-mutations.test.sh"
  "scripts/lib/repo-write-boundary.sh"
  "scripts/test-all.sh"
  "scripts/lib/test-affected-paths.sh"
)


# scripts/test-all-fast-tier-budget (#9763) — the fast-tier budget ratchet. Its verdict reads the
# always-on list and the committed duration manifest; a change to either must select it.
AFFECTED_SCRIPTS_TEST_ALL_FAST_TIER_BUDGET_PATHS=(
  "scripts/lib/test-affected-paths.sh"
  "scripts/suite-durations.tsv"
  "scripts/test-all-fast-tier-budget.test.sh"
  "scripts/test-all.sh"
)

# scripts/test-all-weight-drift (#9814) — the local weight-drift detector. Its
# verdict reads the comparator lib, the runner wiring (default arm + epilogue
# emit + registration), and every committed durations/shard-legs manifest. The
# edge is `glob:scripts/*.tsv`, not `suite-durations*`: the #9813 grammar
# requires a /-terminated literal head, so a file-prefix glob cannot be
# declared — covering the manifest class is the honest widening.
AFFECTED_SCRIPTS_TEST_ALL_WEIGHT_DRIFT_PATHS=(
  "scripts/test-all-weight-drift.test.sh"
  "scripts/lib/test-weight-drift.sh"
  "scripts/test-all.sh"
  "glob:scripts/*.tsv"
  "scripts/lib/test-affected-paths.sh"
)

# --- #9763 fast-tier demotions: declared scopes for suites withdrawn from ALWAYS_ON whose
# verdicts walk a corpus. The orphan lint refuses a demotion without a named scope; each array
# names the trees the suite actually reads (edges are ^-prefixed path matches — a suffix walk
# like `*.sh` becomes the dirs where those files live).

# plugins/soleur/test/operator-ack-guard — finds every *.sh sourcing or calling the ack guard
# (find . -name '*.sh' + grep -rl --include='*.sh' across the tree). Edge = the dirs that hold shell.
AFFECTED_PLUGINS_SOLEUR_TEST_OPERATOR_ACK_GUARD_TEST_SH_PATHS=(

  "apps/"
  "bin/"
  ".claude/"
  ".github/"
  "glob:knowledge-base/**.sh"
  "knowledge-base/legal/tenant-dpa-register.md"
  "plugins/"
  "scripts/"
  "test/"
  "tests/"
  "plugins/soleur/test/operator-ack-guard.test.sh"
  "plugins/soleur/test/fixtures/operator-ack-arms.tsv"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/operator-script — same whole-tree *.sh walk for the operator-script lib.
AFFECTED_PLUGINS_SOLEUR_TEST_OPERATOR_SCRIPT_TEST_SH_PATHS=(

  "apps/"
  "bin/"
  ".claude/"
  ".github/"
  "glob:knowledge-base/**.sh"
  "plugins/"
  "scripts/"
  "test/"
  "tests/"
  "plugins/soleur/test/operator-script.test.sh"
  "plugins/soleur/scripts/lib/operator-script.sh"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/lint-shell-capture-exit-live — live scanner over *.sh for capture-exit shape.
AFFECTED_SCRIPTS_LINT_SHELL_CAPTURE_EXIT_LIVE_PATHS=(

  "apps/"
  "bin/"
  ".claude/"
  ".github/"
  "glob:knowledge-base/**.sh"
  "plugins/"
  "scripts/"
  "test/"
  "tests/"
  "scripts/lint-shell-capture-exit.py"
  "scripts/lint-shell-capture-exit.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# tests/scripts/sentry-alert-live-fidelity — live probe of the sentry alert arms; the corpus it
# cares about is the sentry infra + the workflows that invoke it.
AFFECTED_TESTS_SCRIPTS_SENTRY_ALERT_LIVE_FIDELITY_PATHS=(
  "apps/web-platform/infra/sentry/"
  ".github/workflows/"
  "tests/scripts/test-sentry-alert-live-fidelity.sh"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/test-contention — measures the contention machinery itself (test-contention.sh, the
# runner's lock/queue paths). A docs-only diff can never move its verdict.
AFFECTED_SCRIPTS_TEST_CONTENTION_PATHS=(
  "scripts/lib/test-contention.sh"
  "scripts/test-all.sh"
  "scripts/test-contention.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/test-all-infra-coverage-notice — census of infra-suite registration coverage; its
# subject is the infra tree + the runner's registration corpus.
AFFECTED_SCRIPTS_TEST_ALL_INFRA_COVERAGE_NOTICE_PATHS=(
  "apps/web-platform/infra/"
  ".github/workflows/"
  "tests/scripts/"
  "scripts/test-all.sh"
  "scripts/test-all-infra-coverage-notice.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/guard-vacuity-floor — derives its population from git ls-files '*.test.sh' —
# the suite corpus under these roots.
# Verified read set (#9969): `git ls-files '*.test.sh'` whole-tree — every *.test.sh
# under EVERY top-level root — plus fixture scripts/fixtures/vacuity-contract-control.sh
# and its own file (covered by the scripts/ prefix). The glob: entries below cover the
# 13 roots that lacked a declared prefix; the dir prefixes stay because converting them
# would narrow coverage the suite already had (the #9945 precedent). A dir-less `x.test.sh`
# at repo root is corpus too — root-anchored `glob:` members (#10198) cover it;
# the th6 row in scripts/test-all-affected.test.sh re-derives the live root
# set to catch NEW top-level dirs, and its th8 row (#10117) REDs the battery
# on any dir-less corpus member no declared edge covers.
AFFECTED_SCRIPTS_GUARD_VACUITY_FLOOR_PATHS=(

  "apps/"
  ".claude/"
  ".github/"
  "plugins/"
  "scripts/"
  "test/"
  "tests/"
  "glob:.agents/**.test.sh"
  "glob:.claude-plugin/**.test.sh"
  "glob:.codex/**.test.sh"
  "glob:.cursor-plugin/**.test.sh"
  "glob:.devin/**.test.sh"
  "glob:.grok/**.test.sh"
  "glob:LICENSES/**.test.sh"
  "glob:bin/**.test.sh"
  "glob:docs/**.test.sh"
  "glob:infra/**.test.sh"
  "glob:knowledge-base/**.test.sh"
  "glob:packages/**.test.sh"
  "glob:spike/**.test.sh"
  "glob:todos/**.test.sh"
  "scripts/test-all.sh"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/lint-feature-map-coverage-battery — mutation battery over the
# feature-map sentinel + synthetic fixture repos; its verdict moves only with
# its SUT, itself, or the canonical fixture-dir guard it copies. The real map
# is an edge because the battery's fixture maps mirror its entry grammar — a
# convention change there must re-drive this suite (the live suite is
# always-on and covers the map itself).
AFFECTED_SCRIPTS_LINT_FEATURE_MAP_COVERAGE_BATTERY_PATHS=(

  "scripts/lint-feature-map-coverage.sh"
  "scripts/lint-feature-map-coverage.test.sh"
  "apps/web-platform/test/feature-map.md"
  "plugins/soleur/test/test-helpers.sh"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/lint-integration-env-gates-battery — mutation battery over the
# env-gate sentinel + synthetic fixture repos; its verdict moves only with its
# SUT, itself, or the canonical fixture-dir guard it copies.
AFFECTED_SCRIPTS_LINT_INTEGRATION_ENV_GATES_BATTERY_PATHS=(

  "scripts/lint-integration-env-gates.sh"
  "scripts/lint-integration-env-gates.test.sh"
  "plugins/soleur/test/test-helpers.sh"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/lint-orphan-test-suites — scans the registration corpus for unregistered suites;
# subject is every *.test.* tree plus the runner that registers them.
# Verified read set (#9969): `git ls-files '*.test.sh'` whole-tree, plus
# `.github/workflows/*.yml` surfaces and the REQUIRED_RUNNERS files — the non-corpus
# reads are already covered by the .github/, scripts/ and apps/ prefixes, so only the
# *.test.sh corpus needed glob: coverage for the 13 roots without a declared prefix.
# A dir-less `x.test.sh` at repo root is corpus too — root-anchored `glob:` members
# (#10198) cover it; the th6 row in scripts/test-all-affected.test.sh re-derives the
# live root set to catch NEW top-level dirs, and its th8 row (#10117) REDs the
# battery on any dir-less corpus member no declared edge covers.
AFFECTED_SCRIPTS_LINT_ORPHAN_TEST_SUITES_PATHS=(

  "apps/"
  ".claude/"
  ".github/"
  "plugins/"
  "scripts/"
  "test/"
  "tests/"
  "glob:.agents/**.test.sh"
  "glob:.claude-plugin/**.test.sh"
  "glob:.codex/**.test.sh"
  "glob:.cursor-plugin/**.test.sh"
  "glob:.devin/**.test.sh"
  "glob:.grok/**.test.sh"
  "glob:LICENSES/**.test.sh"
  "glob:bin/**.test.sh"
  "glob:docs/**.test.sh"
  "glob:infra/**.test.sh"
  "glob:knowledge-base/**.test.sh"
  "glob:packages/**.test.sh"
  "glob:spike/**.test.sh"
  "glob:todos/**.test.sh"
  "scripts/test-all.sh"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/lint-trap-tempfile-ownership — *.sh-wide trap/tempfile ownership lint.
AFFECTED_SCRIPTS_LINT_TRAP_TEMPFILE_OWNERSHIP_PATHS=(

  "apps/"
  "bin/"
  ".claude/"
  ".github/"
  "glob:knowledge-base/**.sh"
  "glob:knowledge-base/**.bash"
  "glob:knowledge-base/**.py"
  "glob:knowledge-base/**.ts"
  "glob:knowledge-base/**.mjs"
  "glob:knowledge-base/**.js"
  "glob:knowledge-base/*bunfig.toml"
  "plugins/"
  "scripts/"
  "test/"
  "tests/"
  "scripts/lint-trap-tempfile-ownership.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/check-cloudflare-token-drift — scans .github/ workflows and actions for token drift.
AFFECTED_SCRIPTS_CHECK_CLOUDFLARE_TOKEN_DRIFT_PATHS=(
  ".github/"
  "infra/"
  # token-drift-workflow-causes.test.sh (R4) pins that the drift filers' pointer resolves to this heading.
  "knowledge-base/engineering/operations/runbooks/inngest-provision-rehearsal.md"
  "scripts/check-cloudflare-token-drift.sh"
  "scripts/check-cloudflare-token-drift.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/fanout-suite-scope — drives a sandbox recorder over test-all.sh's
# registration corpus; subject is the runner itself.
AFFECTED_PLUGINS_SOLEUR_TEST_FANOUT_SUITE_SCOPE_TEST_SH_PATHS=(
  "scripts/test-all.sh"
  "scripts/lib/"
  "plugins/soleur/test/"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/fixture-env-adoption — census of fixture-env adoption across the test corpus.
AFFECTED_PLUGINS_SOLEUR_TEST_FIXTURE_ENV_ADOPTION_TEST_SH_PATHS=(

  "apps/web-platform/test/"
  "apps/web-platform/infra/"
  ".github/scripts/"
  "plugins/soleur/test/"
  "test/"
  "tests/"
  "scripts/lib/"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/fixture-dir-operand-assert — same corpus walk for fixture-dir operand shape.
AFFECTED_PLUGINS_SOLEUR_TEST_FIXTURE_DIR_OPERAND_ASSERT_TEST_SH_PATHS=(

  "apps/web-platform/test/"
  "apps/web-platform/infra/"
  ".github/scripts/"
  "plugins/soleur/test/"
  "test/"
  "tests/"
  "scripts/lib/"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/scripts-shard-totality — manifest-vs-registration census; subject is the
# shard manifests + the runner's registration surface.
AFFECTED_PLUGINS_SOLEUR_TEST_SCRIPTS_SHARD_TOTALITY_TEST_SH_PATHS=(
  "scripts/suite-durations.tsv"
  "scripts/suite-shard-legs.tsv"
  "scripts/suite-durations-heavy.tsv"
  "scripts/regenerate-shard-manifest.py"
  "scripts/test-all.sh"
  "scripts/lib/"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/preflight-check10-suite-integrity (#9763 demotion) — the Check-10
# regression-suite anti-vacuity floor. Its subject is the four Check-10 suites it guards, the
# manifest it reads, and the preflight skill whose contract it pins. Self-only derivation would
# classify unclassified and leak it into every local run.
AFFECTED_PLUGINS_SOLEUR_TEST_PREFLIGHT_CHECK10_SUITE_INTEGRITY_TEST_SH_PATHS=(
  "plugins/soleur/test/preflight-check10-suite-integrity.test.sh"
  "plugins/soleur/test/preflight-discoverability-test.test.ts"
  "plugins/soleur/test/observability-schema-parity.test.ts"
  "plugins/soleur/test/fullsuite-merge-gate.test.ts"
  "plugins/soleur/test/preflight-founder-check.test.ts"
  "plugins/soleur/test/fixtures/check10-test-manifest.txt"
  "plugins/soleur/skills/preflight/SKILL.md"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/lint-shell-trace-credential-refusal (#9763 demotion) — tree-wide *.sh scan for
# credential-trace refusal shape; scope = the dirs where shell lives.
AFFECTED_SCRIPTS_LINT_SHELL_TRACE_CREDENTIAL_REFUSAL_PATHS=(

  "apps/"
  "bin/"
  ".claude/"
  ".github/"
  "glob:knowledge-base/**.sh"
  "plugins/"
  "scripts/"
  "test/"
  "tests/"
  "scripts/lint-shell-trace-credential-refusal.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/lib/inngest-probe-row.test.sh (#9763 demotion) — Guard 1 censuses every tracked file
# naming the probe-row marker; scope = the trees that host probe emitters and consumers.
AFFECTED_SCRIPTS_LIB_INNGEST_PROBE_ROW_TEST_SH_PATHS=(
  "apps/web-platform/infra/"
  "apps/web-platform/test/infra/"
  ".github/workflows/"
  "plugins/soleur/test/"
  "scripts/"
  "scripts/lib/test-affected-paths.sh"
)

# plugins/soleur/test/operator-agent-runnable (#9763 demotion) — Guard 1 discovers every
# generated operator script in the tree; generated scripts ship under knowledge-base/project/specs/.
AFFECTED_PLUGINS_SOLEUR_TEST_OPERATOR_AGENT_RUNNABLE_TEST_SH_PATHS=(
  "apps/"
  "bin/"
  ".claude/"
  ".github/"
  # NOT a glob: the Guard-1 corpus is content-keyed, not extension-bounded —
  # g1_discover scans the whole tree for the generated-script marker on ANY
  # extension (a kb .md quoting it is in scope), so **.sh would under-cover.
  "knowledge-base/"
  "plugins/"
  "scripts/"
  "test/"
  "tests/"
  "plugins/soleur/test/operator-agent-runnable.test.sh"
  "plugins/soleur/test/lib/operator-stub-world.sh"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/probe-github-app-mint (#9995) — the JWT reaches curl only through
# scripts/lib/bearer-curl.sh's stdin-config channel, and the mu1 step of
# scheduled-integration-suites.yml invokes it; an edit to either must select it.
AFFECTED_SCRIPTS_PROBE_GITHUB_APP_MINT_PATHS=(
  "scripts/probe-github-app-mint.sh"
  "scripts/probe-github-app-mint.test.sh"
  "scripts/lib/bearer-curl.sh"
  ".github/workflows/scheduled-integration-suites.yml"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/audit-dev-scheduled-shapes (#9995) — census + per-name shape audit;
# declared edges pin its SUT and its own battery.
AFFECTED_SCRIPTS_AUDIT_DEV_SCHEDULED_SHAPES_PATHS=(
  "scripts/audit-dev-scheduled-shapes.sh"
  "scripts/audit-dev-scheduled-shapes.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/lib/repo-write-boundary.test.sh (#9969) — verified read set: whole-tree
# `git ls-files '*.sh'` content-keyed on `test-all\.sh` (every *.sh under every root is
# corpus), plus scripts/test-all.sh (RUNNER: sandbox copies + sed), its SUT lib
# scripts/lib/repo-write-boundary.sh, and its own file. Uniformly glob:-scoped: a dir
# prefix over a doc-heavy root would over-select on non-.sh churn, and there is no
# legacy prefix set to preserve. Residual: a dir-less `x.sh` at repo root is
# coverable by a root-anchored `glob:` member (#10198); the th6 row in
# scripts/test-all-affected.test.sh re-derives the live root set for NEW dirs,
# and its th8 row (#10117) REDs the battery on any dir-less corpus member no
# declared edge covers.
AFFECTED_SCRIPTS_LIB_REPO_WRITE_BOUNDARY_TEST_SH_PATHS=(
  "glob:.agents/**.sh"
  "glob:.claude/**.sh"
  "glob:.claude-plugin/**.sh"
  "glob:.codex/**.sh"
  "glob:.cursor-plugin/**.sh"
  "glob:.devin/**.sh"
  "glob:.github/**.sh"
  "glob:.grok/**.sh"
  "glob:LICENSES/**.sh"
  "glob:apps/**.sh"
  "glob:bin/**.sh"
  "glob:docs/**.sh"
  "glob:infra/**.sh"
  "glob:knowledge-base/**.sh"
  "glob:packages/**.sh"
  "glob:plugins/**.sh"
  "glob:scripts/**.sh"
  "glob:spike/**.sh"
  "glob:test/**.sh"
  "glob:tests/**.sh"
  "glob:todos/**.sh"
  "scripts/test-all.sh"
  "scripts/lib/repo-write-boundary.sh"
  "scripts/lib/repo-write-boundary.test.sh"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/betterstack-emitter-read — the #8875 census mutation battery. It drives the guard
# over git-init'd fixture trees, not the repo corpus; the `git ls-files` text that tripped
# the corpus-walk arm is a comment naming the GUARD's producer. Declared from the repo paths
# its suite file names.
AFFECTED_SCRIPTS_BETTERSTACK_EMITTER_READ_PATHS=(
  "scripts/lib/bs-emitter-row.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/lint-betterstack-emitter-read.sh"
  "scripts/lint-betterstack-emitter-read.test.sh"
  "scripts/test-all.sh"
)

# scripts/inngest-probe-heartbeat-feeder — the dead-probe/serving-verdict feeder battery.
# WS2 (#10390) made it SOURCE the shared classifier (INNGEST_CLASSIFY_LIB seam, census load)
# and READ the workflow run block for seam/wf_check rows — reads no name-stem derives.
AFFECTED_SCRIPTS_INNGEST_PROBE_HEARTBEAT_FEEDER_PATHS=(
  ".github/workflows/scheduled-inngest-probe-heartbeat.yml"
  "scripts/inngest-dedicated-host-classify.sh"
  "scripts/inngest-probe-heartbeat-feeder.sh"
  "scripts/inngest-probe-heartbeat-feeder.test.sh"
  "scripts/lib/inngest-probe-row.sh"
  "scripts/lib/test-affected-paths.sh"
)

# scripts/betterstack-incident-mirror — the #10390 incident-mirror battery. Beyond the SUT
# it READS the shipping workflow (parsed-YAML wiring rows + the verbatim run-block replay),
# the watchdog dispatch table (the row pin), cron-monitors.tf (the monitor declaration row)
# and the two suite-registry TSVs — reads no name-stem derivation reaches.
AFFECTED_SCRIPTS_BETTERSTACK_INCIDENT_MIRROR_PATHS=(
  ".github/workflows/scheduled-betterstack-incident-mirror.yml"
  "apps/web-platform/infra/sentry/cron-monitors.tf"
  "apps/web-platform/server/watchdog-dispatch-table.ts"
  "scripts/betterstack-incident-mirror.sh"
  "scripts/betterstack-incident-mirror.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/suite-durations.tsv"
  "scripts/suite-shard-legs.tsv"
  "scripts/test-all.sh"
)

# scripts/followthroughs/registry-clientip-alert-7530.test.sh — the #7530 post-merge probe's
# exit-code battery. Beyond the probe itself it READS the committed alert file at runtime (the suite
# compares the SQL the probe sends against that text, and the probe extracts its predicate from it),
# a read the name-stem convention cannot reach. Its retirement-header row also READS the alert drift
# guard (apps/web-platform/test/infra/registry-clientip-not-rfc1918-alert.test.sh, the rename cross-reference),
# the two suite-registration tables and the preflight-discoverability baseline. Its case_refire_parity
# row also READS the apply workflow (the printed re-fire command is compared with the workflow's own comment).
AFFECTED_SCRIPTS_FOLLOWTHROUGHS_REGISTRY_CLIENTIP_ALERT_7530_PATHS=(
  ".github/workflows/apply-web-platform-infra.yml"
  "apps/web-platform/infra/betterstack-logs-alerts.tf"
  "apps/web-platform/test/infra/registry-clientip-not-rfc1918-alert.test.sh"
  "plugins/soleur/test/lib/git-fixture-env.sh"
  "plugins/soleur/test/preflight-discoverability-test.test.ts"
  "scripts/followthroughs/registry-clientip-alert-7530.sh"
  "scripts/followthroughs/registry-clientip-alert-7530.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/suite-durations.tsv"
  "scripts/suite-shard-legs.tsv"
)

# scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh — the probe's fed-log
# battery. Beyond the probe it READS the shared forge lib (marker-literal pin, row q);
# its other live-repo references are name-greps carried as accept rows (each suite's own
# in-file roster check is the selecting self-check for producer edits).
AFFECTED_SCRIPTS_FOLLOWTHROUGHS_T5_SKIP_PERSISTENCE_BOUND_7510_PATHS=(
  "plugins/soleur/test/lib/git-corrupt-graph.sh"
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
)

# scripts/monitor-streak-state.test.sh — the rehearsal skip monitor's streak-store suite. Its Section B parses the
# monitor workflow with PyYAML (wiring properties and the mutation rows) and Section C runs the alert step's shell
# body out of it; Section A drives the t5 skip-persistence probe, whose streak write the store's `seal` step
# checks. Both are reads through $REPO_ROOT-built paths, which no derivation channel reaches.
AFFECTED_SCRIPTS_MONITOR_STREAK_STATE_PATHS=(
  ".github/workflows/scheduled-rehearsal-skip-monitor.yml"
  "scripts/followthroughs/t5-skip-persistence-bound-7510.sh"
  "scripts/lib/test-affected-paths.sh"                    # THIS FILE
)

# plugins/soleur/scripts/affected-tests.test.sh — the #9307 plugin-gate contract suite. The
# corpus-walk arm flagged its `find .` calls: those run INSIDE PATH-shim fixture binaries
# (stub vitest/jest/pytest) executing under the suite's own mktemp world — a synthesized
# corpus, not the tracked tree, so the scan is scoped and a declared edge is the right
# classification. Declared from what the suite actually reads: the SUT and its sourced
# libs, its own sourced helpers, and the two repo files its live-repo row (B7) observes
# — .soleur-test-gate.json (parsed on --explain) and scripts/test-all.sh (the delegated
# runner whose --print-selection capability it probes).
AFFECTED_PLUGINS_SOLEUR_SCRIPTS_AFFECTED_TESTS_TEST_SH_PATHS=(
  ".soleur-test-gate.json"
  "plugins/soleur/scripts/affected-tests.sh"
  "plugins/soleur/scripts/affected-tests.test.sh"
  "plugins/soleur/scripts/lib/affected-tests/"
  "plugins/soleur/test/lib/git-fixture-env.sh"
  "plugins/soleur/test/test-helpers.sh"
  "scripts/lib/test-affected-paths.sh"               # THIS FILE
  "scripts/test-all.sh"
)

# plugins/soleur/skills/verification-scaffold/test/generator.test.sh — the corpus-walk
# arm flagged its `grep -rq` for unsubstituted @PLACEHOLDER@s: that scan runs over
# EMITTED artifacts inside hermetic mktemp fixture repos, a synthesized corpus, not
# the tracked tree. Declared from what the suite drives: the skill's generator and
# the references/ templates + guards.tsv it renders from.
AFFECTED_PLUGINS_SOLEUR_SKILLS_VERIFICATION_SCAFFOLD_TEST_GENERATOR_TEST_SH_PATHS=(
  "plugins/soleur/skills/verification-scaffold/"
  "plugins/soleur/skills/verification-scaffold/test/generator.test.sh"
  "scripts/lib/test-affected-paths.sh"
  "scripts/test-all.sh"
)

# plugins/soleur/skills/verification-scaffold/test/manifest.test.sh — its git ls-files
# census is scoped by construction: .claude/hooks/**/*.sh non-test + scripts/lint-* are
# the audit corpus the suite exists to keep classified (a new member missing an audit
# row is exactly the diff that must select it), and the parity anchors are the two
# canonical sources its templates byte-pin. The lint-* shape is not expressible in the
# glob: grammar (the literal head must end in /), so the scripts/ prefix stands for it;
# everything else the suite reads lives inside the skill dir.
AFFECTED_PLUGINS_SOLEUR_SKILLS_VERIFICATION_SCAFFOLD_TEST_MANIFEST_TEST_SH_PATHS=(
  ".claude/hooks/"
  "scripts/"
  "plugins/soleur/scripts/lib/wrapper-boundary.sh"
  "plugins/soleur/scripts/precommit-guard.sh"
  "plugins/soleur/skills/verification-scaffold/"
  "scripts/lib/test-affected-paths.sh"
  "scripts/test-all.sh"
)

# plugins/soleur/test/apply-delivery-gap-follower.test.sh — reads the apply workflow and the
# red-run runbook it asserts against; derived edges cannot reach the file subjects.
AFFECTED_PLUGINS_SOLEUR_TEST_APPLY_DELIVERY_GAP_FOLLOWER_TEST_SH_PATHS=(
  ".github/workflows/apply-delivery-gap-follower.yml"
  ".github/workflows/apply-deploy-pipeline-fix.yml"
  ".github/workflows/apply-web-platform-infra.yml"
  "knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-red-run.md"
  "plugins/soleur/test/apply-delivery-gap-follower.test.sh"
  "scripts/apply-delivery-gap.sh"
  "scripts/lib/test-affected-paths.sh"
)
