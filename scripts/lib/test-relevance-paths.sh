# shellcheck shell=bash
# Relevance predicates for the two heavy mutation batteries (ADR-178).
#
# DECLARATIONS ONLY. No `set -e`, no `exit`, no side effects, nothing executed. Two very
# different consumers source this file and both need it to be inert:
#
#   scripts/test-all.sh              — sources it at TOP LEVEL to guard two run_suite calls
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
  "scripts/check-cloudflare-token-drift.sh"                 # sourced companion; same
  "apps/web-platform/infra/cloud-init.yml"                  # copied fixture
  "tests/scripts/test-registry-gate-mutation-battery.sh"    # SELF — see the note above
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
)

# Union of the top-level prefixes every declared path lives under. The untracked arm of
# test-all.sh's diff detection is path-scoped, and scoping it to apps/web-platform/infra alone
# (as it was before ADR-178) made a brand-new UNTRACKED mutation target under scripts/ or
# .github/ invisible to the predicate — so a session that ADDS a target and runs the gate before
# committing would have had the suite skipped on the very diff that needed it.
TEST_RELEVANCE_PREFIXES=(
  "scripts"
  "tests/scripts"
  ".github"
  "apps/web-platform/infra"
)
