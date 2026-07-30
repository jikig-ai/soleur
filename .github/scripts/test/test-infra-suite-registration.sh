#!/usr/bin/env bash
# test-infra-suite-registration.sh -- fail when an infra *.test.sh is registered nowhere, or
# is registered in a shape the local runner cannot derive.
#
# WHY (#7068). Infra suites are registered ONLY as explicit `run: bash …` steps in
# .github/workflows/infra-validation.yml -- there is no glob. scripts/test-all.sh does not
# cover apps/web-platform/infra/ either (its own preamble says so). So a suite that nobody
# remembers to register runs in NO job, and is invisible TWICE: it never runs, and it never
# reds. That is strictly worse than having no suite at all, because the file reads as
# coverage to anyone grepping for a guard on the thing it names.
#
# The orphan REPORTER that names these suites landed in 2f46570c1 (#6730); #7000 left the seven
# unadopted; they were surfaced and filed while working on #7025; #7068 cleaned them up. Spelled
# out because "#7025 surfaced them" alone reads as though #7025 built the detector, and it did
# not -- a false attribution in the file whose whole subject is comments that assert untrue
# things would be self-undermining. The prevention recorded in
# 2026-06-16-infra-test-orphan-suites-and-node-options-env-file-clobber.md is a HUMAN HABIT
# ("grep the enumerator and add yourself"), and that habit has failed repeatedly. This is the
# mechanical version.
#
# WHAT IT ASSERTS, precisely: every infra *.test.sh on disk is invoked by a SINGLE-LINE
# `run: bash <path>` step in infra-validation.yml, or carries an exclusion with a reason and a
# tracking issue. Two failure modes, reported distinctly because they have different fixes:
# not registered at all (runs in no CI job), and registered in a shape
# run-registered-suites.sh cannot derive (runs in CI, never runs locally).
#
# SCOPE, deliberately narrow: this gate makes REGISTRATION blocking. It says nothing about
# whether a suite's VERDICT blocks merge -- deploy-script-tests is advisory, and promoting it
# is #6480's job, not this gate's. The two are orthogonal, and registration is the one #7068
# is about. Registration still has real teeth today regardless of #6480, because
# apps/web-platform/infra/run-registered-suites.sh DERIVES its execute set from the same
# workflow steps, ends in `(( RED == 0 ))`, and is mandated as an infra exit gate by both the
# work and ship skills. That is also why the single-line shape is asserted rather than mere
# "invoked somewhere": a multi-line `run: |` still runs in CI but is invisible to that runner,
# so it silently removes the teeth while looking registered.
#
# It does NOT fix the runner's own derivation gap (7 subdirectory suites carry proper
# single-line steps but the runner's character class excludes `/`). That is #7076.
#
# WHY IT LIVES HERE. The `test-*.sh` glob in run-all.sh feeds guard-script-fixture-tests --
# REQUIRED, merge_group-triggered, path-filter-free. So this gate is genuinely blocking while
# adding NO new required-check name: no ruleset-ci-required.tf edit and no
# scripts/required-checks.txt edit. It honours that glob's BASH-ONLY contract verbatim (find +
# grep, reading YAML as text) -- no terraform, no cloud-init, no apt, no python -- so the
# #6454 hazard (a package-mirror dependency on the merge-queue critical path) is not tripped.
# #6454 was about apt on that path, not about any dependency at all.
#
# It STARTS GREEN: #7068 drove the orphan set to zero first. A ratchet, not a backlog.
#
# Deliberately has no companion .test.sh -- a suite testing a grep would reproduce the orphan
# problem in miniature, exactly as lint-orphan-test-suites.sh notes. It is mutation-proved
# inline instead (remove a `run:` line on a scratch copy -> this must exit non-zero), and that
# proof is recorded in the #7068 PR body.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/infra-validation.yml"
INFRA_DIR="$REPO_ROOT/apps/web-platform/infra"

# name | reason (must cite a tracking issue)
#
# An exclusion is for a suite that cannot carry the single-line shape asserted below. Exactly
# one today. An entry here is a debt, not a fix -- #7068 registered all 94, so nothing else
# needs absorbing, and closing #7076 should let this entry go too.
EXCLUSIONS=(
  "workspaces-luks-loopback.test.sh|invoked as \`sudo bash\` inside a multi-line \`run: |\` block (infra-validation.yml), because it needs root for losetup/luksFormat. It therefore runs in CI but is invisible to run-registered-suites.sh's single-line derivation -- and it must STAY invisible to it: the suite exits 2 unprivileged, so deriving it would turn that mandated ship gate permanently RED for any operator without passwordless sudo. Fixing the derivation properly (derive-but-do-not-execute) is tracked in #7076."
)

# Strip comment lines BEFORE matching. This is the anti-vacuity core of the gate: the local
# runner's own orphan scan is a bare-basename `git grep -qF`, so prose naming a suite silences
# it while running nothing -- the very shape cq-assert-anchor-not-bare-token forbids, and the
# loophole #7068's own block comment had to be written around. Anchoring on the invocation
# shape is only half the fix; without this strip, a commented-out invocation
# (`# bash apps/web-platform/infra/foo.test.sh`) would still satisfy it. Covers YAML comments
# and shell comments inside `run: |` blocks alike, since both start with optional whitespace
# then `#`.
if [[ ! -f "$WF" ]]; then
  echo "ERROR: $WF not found -- cannot verify infra suite registration" >&2
  exit 1
fi
WF_CODE=$(grep -vE '^[[:space:]]*#' "$WF")

# Enumerate on disk, recursively: subdirectory suites (inngest-rls/, scripts/,
# supabase-advisor/) are registered with proper steps and must not be missed.
SUITES=()
while IFS= read -r f; do
  SUITES+=("$f")
done < <(find "$INFRA_DIR" -name '*.test.sh' -type f | LC_ALL=C sort)

# Minimum-cardinality guard. Without it a broken enumeration (renamed directory, bad find
# predicate) yields ZERO suites and the loop below passes with zero coverage -- a green run
# that checked nothing, which is the same silent-and-green shape this gate exists to remove.
# 94 suites today; a count this low means the enumeration broke, not that suites were deleted.
# Lower it deliberately, with a reason, if the directory ever genuinely shrinks that far.
if (( ${#SUITES[@]} < 50 )); then
  echo "ERROR: enumerated only ${#SUITES[@]} infra suite(s) under $INFRA_DIR -- expected ~94." >&2
  echo "       The enumeration is broken; this gate cannot make any claim. Fix it, do not lower the floor." >&2
  exit 1
fi

fails=0
excluded_n=0
for f in "${SUITES[@]}"; do
  base=$(basename "$f")
  rel="${f#"$REPO_ROOT"/}"

  excluded=""
  if (( ${#EXCLUSIONS[@]} )); then
    for e in "${EXCLUSIONS[@]}"; do
      [[ "${e%%|*}" == "$base" ]] && excluded="${e#*|}"
    done
  fi
  if [[ -n "$excluded" ]]; then
    # Fail-closed on a reasonless or issue-less exclusion: skipping must be a recorded
    # decision, not a silent absorption.
    if [[ -z "${excluded// /}" ]] || ! grep -qE '#[0-9]+' <<< "$excluded"; then
      echo "ERROR: exclusion for $base has no reason or no tracking issue" >&2
      fails=$((fails + 1))
    # An exclusion waives the SHAPE requirement, never EXISTENCE. Without this arm the
    # exclusion is a blanket exemption: deleting the excluded suite's invocation outright
    # stops it running in CI and this gate stays green -- a fail-open, narrow but real, and
    # one introduced by the exclusion itself. Measured: with only the reason/issue check
    # above, removing loopback's `sudo bash` line left the gate at rc=0.
    #
    # So an excluded suite must still be invoked in SOME shape. Deliberately permissive
    # here (optional `sudo`, any surrounding position) because the whole point of the
    # exclusion is that this suite cannot carry the single-line form.
    elif ! grep -qE "(^|[[:space:]])(sudo[[:space:]]+)?bash[[:space:]]+${rel//./\\.}([[:space:]]|$)" <<< "$WF_CODE"; then
      echo "ERROR: ${rel} is EXCLUDED from the single-line shape requirement, but it is not" >&2
      echo "       invoked in infra-validation.yml at all -- so it runs in no CI job." >&2
      echo "       An exclusion waives the shape, never the registration. Either restore its" >&2
      echo "       invocation, or delete both the suite and its exclusion entry." >&2
      fails=$((fails + 1))
    else
      echo "note: $base excluded -- $excluded"
      excluded_n=$((excluded_n + 1))
    fi
    continue
  fi

  # Anchor on the SINGLE-LINE `run: bash <path>` INVOCATION SHAPE, not the bare basename, and
  # not merely "appears after the word bash somewhere".
  #
  # Asserting the single-line shape rather than "invoked in any shape" is deliberate, and the
  # mutation battery is what forced it: an earlier draft accepted any `bash <path>` occurrence,
  # which a multi-line `run: |` block satisfies -- so converting a step to that form passed the
  # gate while silently de-registering the suite from run-registered-suites.sh, whose derivation
  # is single-line-only. That is where the teeth are (the runner ends in `(( RED == 0 ))` and is
  # a mandated ship gate), so a shape CI still runs but the runner cannot see is exactly the
  # regression worth blocking. 93 of 94 suites already carry this shape; the one that cannot is
  # excluded above for cause.
  #
  # A TRAILING `#` COMMENT IS ALLOWED, and that tolerance is measured, not assumed. The runner
  # derives with `grep -oE 'run: bash <path>'` and does NOT anchor at end-of-line, so it happily
  # derives `run: bash <path>  # note` -- the suite really does run, both in CI and locally. An
  # earlier version of this gate anchored on `[[:space:]]*$` and therefore REJECTED that line,
  # which would have red-failed a required, merge-queue-gating check on a legitimate comment
  # while telling the author the runner "cannot derive it" -- a false statement, since it can.
  # Verified by running both this gate and the runner over each YAML shape and requiring them to
  # agree; the trailing-comment row was the one disagreement.
  #
  # Deliberately NOT widened further. The runner's extraction also tolerates trailing `&& cmd`
  # or `| cmd`, but those change what actually executes and make CI diverge from the local run,
  # so this gate still refuses them. Matching the runner exactly is the goal only where the
  # runner is right.
  esc="${rel//./\\.}"
  if ! grep -qE "^[[:space:]]*run: bash ${esc}[[:space:]]*(#.*)?$" <<< "$WF_CODE"; then
    # Distinguish the two failure modes -- they have different fixes.
    if grep -qE "(^|[[:space:]])(sudo[[:space:]]+)?bash[[:space:]]+${esc}([[:space:]]|$)" <<< "$WF_CODE"; then
      echo "ERROR: ${rel} IS invoked in infra-validation.yml, but not in the single-line" >&2
      echo "       \`run: bash <path>\` form this gate requires." >&2
      echo "       Most such shapes -- an inline env prefix, a quoted scalar, a \`./\` prefix, a" >&2
      echo "       multi-line \`run: |\` -- also de-register the suite from" >&2
      echo "       run-registered-suites.sh, which derives single-line only, so it would never" >&2
      echo "       run locally even though CI does. Step-level \`env:\` is safe, and so is a" >&2
      echo "       trailing \`# comment\`. If the shape is unavoidable (it needs sudo), add a" >&2
      echo "       reasoned exclusion citing a tracking issue." >&2
    else
      echo "ERROR: ${rel} is registered in NO infra-validation.yml step -- it runs in no CI job," >&2
      echo "       and scripts/test-all.sh does not cover apps/web-platform/infra/ either." >&2
      echo "       Add a single-line \`run: bash ${rel}\` step to the deploy-script-tests job," >&2
      echo "       or add a reasoned exclusion citing a tracking issue." >&2
    fi
    fails=$((fails + 1))
  fi
done

if (( fails > 0 )); then
  echo "unregistered infra test suites: $fails (of ${#SUITES[@]} on disk)" >&2
  exit 1
fi
echo "infra suite registration: all ${#SUITES[@]} suites registered (${excluded_n} excluded)"
