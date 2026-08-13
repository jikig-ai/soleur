# shellcheck shell=bash
# shellcheck disable=SC2034  # every array here is consumed by files that SOURCE this one
#   (scripts/test-all.sh, scripts/lint-orphan-test-suites.sh); shellcheck analyses one file
#   at a time and cannot see a cross-file consumer. The de-reference anchor in the linter is
#   what actually proves each array is consumed -- see ADR-181.
# Relevance predicates for the expensive suites the local gate declines on an irrelevant diff
# (ADR-181, extended by its 2026-08-12 addendum from the two heavy mutation batteries to four
# suites).
#
# HOW TO ADD A RELEVANCE GATE — SIX sites. Do all six; five is not enough.
#   1. Declare <NAME>_PATHS here, self-including the suite's own file AND this file.
#   2. Add "<NAME>_PATHS|<suite-file>" to RELEVANCE_ARRAYS in scripts/lint-orphan-test-suites.sh.
#   3. Wrap the run_suite call in scripts/test-all.sh with `if _diff_touches "${<NAME>_PATHS[@]}"`.
#   4. Give it a skip_suite else-arm — the decline must be a counted verdict, never an absence.
#   5. Ensure every path in 1 lives under a TEST_RELEVANCE_PREFIXES entry below; add the prefix if
#      not, or the untracked-file arm is blind to it.
#   6. Add "<label>|<NAME>_PATHS" to GATED in scripts/test-all-infra-coverage-notice.test.sh.
#      <label> is skip_suite's $1, which is NOT always the suite file path — see RELEVANCE_ARRAYS.
#
# WHERE EACH SITE REDS. 1, 2, 3, 5 and 6 red in scripts/lint-orphan-test-suites.sh; 6 additionally
# reds in the harness's own registration floor. Site 4 reds ONLY in
# scripts/test-all-infra-coverage-notice.test.sh, and ONLY for a suite listed in GATED — which is
# precisely why 6 is not optional. An earlier revision of this block listed five sites and asserted
# site 4 "reds behaviourally"; that was FALSE for a new gate, because every behavioural arm
# quantifies over GATED. Review found it, and the linter now enforces GATED against the runner so
# the omission cannot recur silently.
#
# This block exists because three of the sites were otherwise discoverable only by reading an
# archived plan, and this file is where a reader adding a gate actually lands.
#
# DECLARATIONS ONLY. No `set -e`, no `exit`, no side effects, nothing executed. Two very
# different consumers source this file and both need it to be inert:
#
#   scripts/test-all.sh              — sources it at TOP LEVEL to guard four run_suite calls
#   scripts/lint-orphan-test-suites.sh — sources it to assert every declared path still resolves
#
# WHY A DATA FILE RATHER THAN ARRAYS BESIDE THE CALL SITES. The linter has to read these lists,
# and the two obvious alternatives are both broken:
#
#   - Parsing them back out of test-all.sh. Every suite registration there is indented two
#     spaces inside `if want_scripts`, so a column-0 anchor (`awk '/^NAME=\(/,/^\)/'`) extracts
#     ZERO lines — and a zero-length path list passes every check vacuously. That is precisely
#     the failure class this gate exists to close, reproduced inside its own guard.
#   - Sourcing test-all.sh from the linter. It `export`s TMPDIR/TC_TMPDIR into the caller, can
#     `exit` the caller from its bare-repo guard or its TEST_GROUP `case`, and calls tc_acquire
#     — which would block for up to 900 s on the flock the linter is ALREADY running inside,
#     held by its own parent.
#
# A shared declaration source needs no derivation at all, which is why it has no vacuous-pass
# mode to guard against. The vacuity guard in the linter still applies: a shared array can be
# emptied.
#
# WHAT BELONGS IN A LIST. Only paths the battery actually DEPENDS ON — the files it copies as
# subjects-under-test, the suites it drives as oracles, and the fixtures whose absence is a hard
# abort. The cf-tunnel battery copies all of scripts/ and .github/ into its sandbox; gating on
# that copy set would match nearly every diff and never skip.
#
# EVERY LIST ALSO CONTAINS *THIS* FILE, for the same reason one level up. These lists decide
# whether a battery runs, so a commit editing only this file must run both — and the dangerous
# edit is REMOVING a path, which is exactly the edit whose safety a battery would demonstrate.
# Nothing else covers it: lint-orphan-test-suites.sh asserts that declared paths resolve, that
# each array self-includes, that none is empty, and that test-all.sh consumes each one — and a
# SHORTER list satisfies all four. Verified by deleting an entry: the linter stayed green.
# Cost is ~17 min of battery time on commits touching this one file, which is rare.
#
# scripts/test-all.sh is deliberately NOT listed. Its gating LOGIC is already covered
# unconditionally by scripts/test-all-infra-coverage-notice (registered with no relevance gate),
# and the batteries verify neither that logic nor these lists — so listing it would tax every
# routine suite registration with ~17 min for no added signal.
#
# KNOWN LIMIT — the cf-tunnel enumeration is a LOWER BOUND, not a closed set. Three of the
# oracle's assertions bind to a DIRECTORY rather than to nameable files: W2 counts
# `--only CI_SSH_ACCESS_TOKEN` call sites across .github/, W7 enumerates bridge adopters under
# .github/workflows/, and W8 asserts no `-replace` targets the .deploy token anywhere in
# .github/. A brand-new workflow adopting the bridge reddens the oracle while these lists
# decline the battery. Two things bound that: the oracle is registered unconditionally, and
# legitimising a new adopter REQUIRES editing W7_EXPECTED in
# scripts/check-cloudflare-token-drift.test.sh — a listed path — which re-arms the battery on
# the same commit. The residual window is between adding the workflow and updating W7_EXPECTED.
#
# NON-OBVIOUS TRANSITIVE EDGE: the registry GATE oracle depends on the ENGINE SUT. It derives
# its seam list by grepping REGISTRY_(GATE|RESTORE)_* out of BOTH the gate and
# scripts/registry-restore-from-ghcr.sh, so adding a REGISTRY_RESTORE_* seam to the engine
# changes the gate oracle's assertion count. Both are listed; do not "simplify" the pairing to
# gate-SUT-with-gate-suite.
#
# EVERY LIST CONTAINS ITS OWN BATTERY FILE. That single element is what makes new-target drift
# self-correcting: a commit that teaches a battery to mutate something new necessarily edits the
# battery, necessarily matches the predicate, and therefore necessarily runs the suite that
# would otherwise have been skipped with a stale list.

# tests/scripts/registry-gate-mutation-battery (test-all.sh) — the single most expensive suite in
# the runner at ~860 s, and it guards the registry restore/destroy authorization path.
# Source of truth: tests/scripts/test-registry-gate-mutation-battery.sh — SUT_GATE/SUT_ENGINE and
# SUITE_GATE/SUITE_ENGINE in its copy loop, its best-effort companion `for f in` list, and the
# cloud-init copy immediately below them.
REGISTRY_BATTERY_PATHS=(
  "scripts/registry-pull-path-health.sh"                    # SUT_GATE
  "scripts/registry-restore-from-ghcr.sh"                   # SUT_ENGINE
  "tests/scripts/test-registry-pull-path-health.sh"         # SUITE_GATE (the oracle)
  "tests/scripts/test-registry-restore-from-ghcr.sh"        # SUITE_ENGINE (the oracle)
  "scripts/zot-mirror-diagnosis.sh"                         # sourced companion; absence changes which arm runs
  "scripts/check-cloudflare-token-drift.sh"                 # copied, but seam-overridden on every run
  "apps/web-platform/infra/cloud-init.yml"                  # copied fixture
  "tests/scripts/test-registry-gate-mutation-battery.sh"    # SELF — see the note above
  "scripts/lib/test-relevance-paths.sh"                      # THIS FILE — see the self-reference note above
)

# scripts/cf-tunnel-liveness-gate-mutations (test-all.sh) — ~189 s.
# Source of truth: scripts/cf-tunnel-liveness-gate-mutations.test.sh — SUITE_REL/BRIDGE_REL/
# APPLY_REL, INVENTORY_REL, the scheduled-terraform-drift.yml mutations, and the M4 arm that
# mutates git-data-cutover.yml; plus W7_EXPECTED in scripts/check-cloudflare-token-drift.test.sh,
# which is the oracle those mutations are scored against.
#
# THE FIVE W7 WORKFLOWS ARE LOAD-BEARING AND WERE MISSING FROM THE FIRST DRAFT. The battery's M4
# arm mutates git-data-cutover.yml, and the oracle pins 5 workflows / 6 call sites. A PR that
# removed the bridge `uses:` from any of them would fail W7 *and* crash M4 — while this predicate,
# had it listed only the three obvious paths, would have skipped the battery and reported green.
CF_TUNNEL_BATTERY_PATHS=(
  "scripts/check-cloudflare-token-drift.test.sh"            # SUITE_REL — the oracle the battery scores against
  "scripts/check-cloudflare-token-drift.sh"                 # the oracle's own SUT: change it and the oracle's verdicts change
  ".github/actions/cf-tunnel-ssh-bridge/action.yml"         # BRIDGE_REL — the gate under test
  "apps/web-platform/infra/doppler-config-inventory.txt"    # INVENTORY_REL — copied fixture; its absence is a hard abort
  ".github/workflows/scheduled-terraform-drift.yml"         # mutated by the M6 escalation arm
  ".github/workflows/apply-deploy-pipeline-fix.yml"         # W7_EXPECTED
  ".github/workflows/apply-web-platform-infra.yml"          # W7_EXPECTED (also APPLY_REL)
  ".github/workflows/git-data-cutover.yml"                  # W7_EXPECTED, and mutated directly by M4
  ".github/workflows/workspaces-luks-cutover.yml"           # W7_EXPECTED (two call sites)
  ".github/workflows/workspaces-luks-verify.yml"            # W7_EXPECTED
  "scripts/cf-tunnel-liveness-gate-mutations.test.sh"       # SELF — see the note above
  "scripts/lib/test-relevance-paths.sh"                      # THIS FILE — see the self-reference note above
)

# plugins/soleur/test/c4-from-components.test.sh (test-all.sh, scripts shard) — declined on 96%
# of recent commits. Source of truth: the suite's own header — PRODUCER=, FIXTURES=, and the
# sourced test-helpers.sh.
#
# THE DECISION VARIABLE IS THE SKIP RATE, NOT A WALL-CLOCK FIGURE. That is a measurement result,
# not a preference; the full argument and the withdrawn cost figures live once, in ADR-181's
# `## Addendum — 2026-08-12 (#7494)` §7. Do not restate a per-run saving here.
#
# ANCHOR THE REPLAY TO A SHA, NOT TO `origin/main`. `origin/main` is a MOVING window: re-run
# against the tip and a reader cannot tell "the predicate rotted" from "the window moved". Measured
# 96% at `fcae560b4` and 95% four commits later, which is the drift, not a regression.
#   BASE=fcae560b4   # the merge base this rate was measured at
#   for sha in $(git log --format=%H -80 "$BASE"); do
#     blob=$(git show --pretty=format: --name-only "$sha"); armed=0
#     for p in "${C4_PRODUCER_PATHS[@]}"; do grep -qF -- "$p" <<<"$blob" && { armed=1; break; }; done
#     [[ $armed == 0 ]] && echo skip
#   done | wc -l
#
# WHY THIS SET IS CLOSED where the two batteries above are not: the suite NEVER reads the real
# tree. seed() builds throwaway roots under $TMPDIR from $FIXTURES and the producer takes its root
# from process.argv[2], so the dependency set is its subject plus its own inputs.
#
# lib/ IS A DIRECTORY, deliberately. The producer imports one file from it today
# (`from "../lib/c4-from-components"`, which itself has zero relative imports); a second import
# tomorrow would be invisible to a file-level declaration until someone edited this array.
# Measured: the directory form costs nothing — 96% skip either way, because plugins/soleur/lib/
# appears in 1 of the last 80 commits on main. Structural beats enumerated at equal price.
#
# KNOWN LIMIT — a LOWER BOUND, not a closed set, exactly as the cf-tunnel block above says of
# itself. Two real dependencies are deliberately NOT declared: `.bun-version` (run_producer invokes
# `bun "$PRODUCER"`) and the likec4 version pin, which lives in three places (package.json,
# apps/web-platform/Dockerfile, the ci.yml install step) and none of them here. Declaring them
# would arm this suite on every toolchain bump for no added signal, and the window is bounded three
# ways: the pin trio has its own UNGATED guard (apps/web-platform's c4-likec4-version-pin.test.ts),
# the suite DEGRADES rather than fails when the CLI is unreachable, and CI runs everything.
#
# NOTE the degrade cuts BOTH ways: it is a mitigation here and a hazard in the epilogue, because
# the re-run command this gate prints can exit 0 having rendered nothing
# (`status=degraded reason=likec4-unavailable` → SKIP). Recorded in the ADR addendum so the next
# reader does not have to rediscover it.
C4_PRODUCER_PATHS=(
  "plugins/soleur/scripts/generate-c4-from-components.ts"  # PRODUCER (the SUT wrapper)
  "plugins/soleur/lib"                                     # its import closure — directory, see above
  "plugins/soleur/test/test-helpers.sh"                    # sourced; absence is a hard abort
  "plugins/soleur/test/fixtures/component-docs"            # the seeded corpora — directory
  "plugins/soleur/test/c4-from-components.test.sh"         # SELF — see the note above
  "scripts/lib/test-relevance-paths.sh"                    # THIS FILE — see the self-reference note above
)

# .github/scripts/test/run-all.sh (test-all.sh) — declined on 15% of recent commits. A nested
# RUNNER, so the predicate covers what its fixture suites depend on, not just the runner.
#
# apps/web-platform/infra IS LOAD-BEARING AND WAS NOT OBVIOUS. test-infra-suite-registration.sh
# derives its expected set from `git ls-files "${INFRA_PREFIX}/*.test.sh"` against the REAL tree, so
# a commit ADDING an infra suite without registering it in infra-validation.yml is exactly the diff
# that must run this runner — and a `.github`-only predicate would have declined it.
#
# AND IT IS NOT THE ONLY REAL-TREE READ — that framing was wrong and review caught it.
# test-no-at-mention-credfile-footgun.sh scans committed content with `git ls-files` over
# plugins/soleur/{skills,agents,commands,docs,hooks}, .claude/hooks, AGENTS.md, AGENTS.*.md,
# CLAUDE.md and plugins/**/AGENTS*.md — none of which is under .github or apps/web-platform/infra.
# With a .github-only predicate, a diff touching plugins/soleur/skills/preflight/SKILL.md DECLINED
# the runner. That guard exists because #6830 leaked an operator's live root token into a
# transcript from a documentation example in exactly that file class, so declining there is the
# "declined on the diff that needed it" shape this whole mechanism is built to avoid.
#
# THE COST OF DECLARING IT IS DELIBERATE AND LARGE: measured at fcae560b4, the skip rate falls
# 56% -> 15%. Taken anyway. A slower local run is recoverable; a credential-footgun token reaching
# a transcript is not, and hr-weigh-every-decision-against-target-user-impact resolves that
# trade in one direction only. The gate still declines 1 commit in 7, announced and counted.
#
# WHY THE BARE `.github` ELEMENT DOES NOT VIOLATE `WHAT BELONGS IN A LIST` above. That rule rejects
# gating on a battery's COPY set because it "would match nearly every diff and never skip". Here
# .github is a genuine dependency set, not a copy set, and the measured rate is 15% — it does skip.
#
# KNOWN LIMIT — a LOWER BOUND, not a closed set, exactly as the cf-tunnel block above says of
# itself. `git rev-parse --show-toplevel` means any future suite in this runner can read any path
# in the repo without editing this array. Bounded by an independent REQUIRED CI home:
# `guard-script-fixture-tests` in .github/workflows/pr-quality-guards.yml runs this runner directly
# on pull_request and merge_group with NO paths: filter, so a decline here can slow a local loop
# but cannot merge an escape.
GITHUB_SCRIPTS_SUITE_PATHS=(
  ".github"                                                # the SUTs, the suites, and the workflows they derive from
  "apps/web-platform/infra"                                # test-infra-suite-registration.sh's real-tree read — directory
  "plugins/soleur"                                         # the footgun guard's git ls-files scan — directory, see above
  ".claude/hooks"                                          # same scan
  "AGENTS.md"                                              # same scan (auto-loaded content surface)
  "AGENTS.rules.md"                                        # same scan
  "CLAUDE.md"                                              # same scan
  ".github/scripts/test/run-all.sh"                        # SELF. Dead for MATCHING (".github" already
                                                           # covers it) — present because the linter's
                                                           # self-inclusion check reads this array.
  "scripts/lib/test-relevance-paths.sh"                    # THIS FILE — see the self-reference note above
)

# Union of the top-level prefixes every declared path lives under. The untracked arm of
# test-all.sh's diff detection is path-scoped, and scoping it to apps/web-platform/infra alone
# (as it was before ADR-181) made a brand-new UNTRACKED mutation target under scripts/ or
# .github/ invisible to the predicate — so a session that ADDS a target and runs the gate before
# committing would have had the suite skipped on the very diff that needed it.
#
# WIDENING THIS LIST IS ALWAYS FAIL-SAFE. The arm only ADDS names to _diff_names, which can only
# make a gate more likely to RUN. `plugins/soleur` was added with C4_PRODUCER_PATHS: without it a
# session that adds a brand-new UNTRACKED fixture corpus and runs the gate before committing would
# have the c4 suite declined on the very diff that needed it.
#
# ROOT FILES APPEAR HERE TOO, and that is not a category error. The consumer is
# `git ls-files --others --exclude-standard -- "${TEST_RELEVANCE_PREFIXES[@]}"`, which takes
# PATHSPECS; a pathspec naming a tracked file simply matches nothing in `--others`, which is the
# correct no-op. They are listed because the linter's prefix-coverage check requires every declared
# predicate path to be reachable from this list, and GITHUB_SCRIPTS_SUITE_PATHS declares them.
TEST_RELEVANCE_PREFIXES=(
  "scripts"
  "tests/scripts"
  ".github"
  "apps/web-platform/infra"
  "plugins/soleur"
  ".claude/hooks"
  "AGENTS.md"
  "AGENTS.rules.md"
  "CLAUDE.md"
)
