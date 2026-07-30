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
# unadopted; they were surfaced and filed while working on #7025; #7068 cleaned them up. The
# prevention recorded in 2026-06-16-infra-test-orphan-suites-and-node-options-env-file-clobber.md
# is a HUMAN HABIT ("grep the enumerator and add yourself"), and that habit has failed
# repeatedly. This is the mechanical version.
#
# WHAT IT ASSERTS, precisely: every infra *.test.sh tracked by git is invoked by a SINGLE-LINE
# `run: bash <path>` step inside the `deploy-script-tests` job of infra-validation.yml, or
# carries an exclusion with a reason and a tracking issue. Failure modes are reported
# distinctly because they have different fixes: not registered at all (runs in no
# deploy-script-tests step), and registered in a shape run-registered-suites.sh cannot derive
# (runs in CI, never runs locally).
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
# WHAT IT DOES *NOT* ASSERT, stated so no reader over-reads a green run:
#   - Step-level `if:` / `continue-on-error:`. It asserts the job carries neither (see the
#     MASKING CHECK below), which covers today's file, but it does not parse YAML, so a
#     sufficiently creative masking construct is out of scope.
#   - That infra-validation.yml runs at all for a given PR. That workflow is `pull_request` +
#     `paths:`-filtered with NO `merge_group:` trigger, while THIS gate runs in a
#     merge_group-triggered, path-filter-free required check. So the gate can be green in the
#     merge queue for a workflow that the merge queue never runs. Registration is still the
#     right thing to gate; the trigger asymmetry is simply not something this gate can fix.
#
# WHY IT LIVES HERE. The `test-*.sh` glob in run-all.sh feeds guard-script-fixture-tests --
# REQUIRED, merge_group-triggered, path-filter-free. So this gate is genuinely blocking while
# adding NO new required-check name: no ruleset-ci-required.tf edit and no
# scripts/required-checks.txt edit. It honours that glob's BASH-ONLY contract verbatim (git +
# sed + grep, reading YAML as text) -- no terraform, no cloud-init, no apt -- so the #6454
# hazard (a package-mirror dependency on the merge-queue critical path) is not tripped.
# #6454 was about apt on that path, not about any dependency at all.
#
# It must ALSO stay outside `scripts/` and `.github/workflows/`: run-registered-suites.sh's
# orphan scan is a bare-basename `git grep` over exactly those two pathspecs, so an EXCLUSIONS
# entry naming a suite would silence that reporter if this file were moved under them.
#
# It STARTS GREEN: #7068 drove the orphan set to zero first. A ratchet, not a backlog.
#
# Its own non-vacuity is pinned by a committed harness, not by a comment:
# test-infra-suite-registration-mutations.sh (same directory, so also auto-globbed). Every
# arm below has a mutation row there. An earlier version of this header claimed the gate was
# "mutation-proved inline, and that proof is recorded in the PR body" -- that is the
# perishable-evidence anti-pattern recorded in
# knowledge-base/project/learnings/2026-07-15-ad-hoc-verification-evidence-is-as-perishable-as-uncommitted-code.md,
# and the "a harness would reproduce the orphan problem in miniature" argument that justified
# it was self-refuting: a harness in THIS directory is auto-globbed and therefore cannot be
# orphaned, as the paragraph above says in as many words.
#
# COST. Measured #7068 review, clean env (`env -i PATH=/usr/bin:/bin`) in a sandbox with both
# versions at their real path and BOTH exiting 0: this one-pass form ~0.12-0.15s, the earlier
# per-suite-grep form ~0.91-1.07s. ~7x, and the per-suite form was also quadratic in suite
# count (each registration adds both an iteration and a line to the scanned corpus), which is
# a poor shape for a required merge-queue gate even while its absolute cost was acceptable.
#
# Pin the real binaries when re-measuring. In an agent session `grep` is often a shim shell
# function wrapping a slower engine, which inflated this script to ~15s and the per-suite form
# to ~1.9s. And run both arms to rc=0: an arm that early-exits on its own cardinality guard
# (e.g. copied to /tmp, breaking the BASH_SOURCE-relative REPO_ROOT) reports ~20ms and reads
# exactly like a fast pass. Both mistakes were made and caught while writing this line.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF_REL=".github/workflows/infra-validation.yml"
WF="$REPO_ROOT/$WF_REL"
JOB="deploy-script-tests"
INFRA_PREFIX="apps/web-platform/infra"

err() { echo "::error::infra-suite-registration: $1" >&2; }

# name | reason (must cite a tracking issue)
#
# An exclusion is for a suite that cannot carry the single-line shape asserted below. Exactly
# one today. An entry here is a debt, not a fix -- #7068 registered all 94, so nothing else
# needs absorbing, and closing #7076 should let this entry go too.
EXCLUSIONS=(
  "workspaces-luks-loopback.test.sh|invoked as \`sudo bash\` inside a multi-line \`run: |\` block (infra-validation.yml), because it needs root for losetup/luksFormat. It therefore runs in CI but is invisible to run-registered-suites.sh's single-line derivation -- and it must STAY invisible to it: the suite exits 2 unprivileged, so deriving it would turn that mandated ship gate permanently RED for any operator without passwordless sudo. Fixing the derivation properly (derive-but-do-not-execute) is tracked in #7076."
)

# Suites that live in a SUBDIRECTORY of apps/web-platform/infra/. They carry correct
# single-line steps and DO run in CI -- but run-registered-suites.sh cannot derive them,
# because its extraction character class ([A-Za-z0-9._-]+) excludes `/`. So they never run
# through the local runner that both the work and ship skills mandate.
#
# This list is a PIN, not documentation. The subdirectory gap is a predicate on paths, not a
# closed set of seven: without this pin an 8th subdirectory suite registers GREEN and silently
# never runs locally, forever, which is the same accretion that produced the seven orphans
# #7068 is cleaning up. Fixing the runner's derivation is #7076; until then a new
# subdirectory suite must be a deliberate, visible decision.
KNOWN_UNDERIVABLE=(
  "$INFRA_PREFIX/inngest-rls/apply-inngest-rls-dev-workflow.test.sh"
  "$INFRA_PREFIX/inngest-rls/inngest-rls-mutation.test.sh"
  "$INFRA_PREFIX/inngest-rls/inngest-rls.test.sh"
  "$INFRA_PREFIX/scripts/gen-github-egress-cidr.test.sh"
  "$INFRA_PREFIX/scripts/sigpipe-triage-feasibility.test.sh"
  "$INFRA_PREFIX/supabase-advisor/scan-workflow-mutation.test.sh"
  "$INFRA_PREFIX/supabase-advisor/scan-workflow.test.sh"
)

if [[ ! -f "$WF" ]]; then
  err "$WF_REL not found -- cannot verify infra suite registration"
  exit 1
fi

# Slice the deploy-script-tests job, then strip comment lines.
#
# Job-scoping is load-bearing, not tidiness: the error messages below name that job by name,
# and a whole-file scan cannot honestly say "runs in no CI job" (measured at review: relocating
# a suite's step into the `plan` job, which is itself gated on a Doppler token, left a
# whole-file scan GREEN while the suite ran in no job on most PRs).
#
# Comments are stripped BEFORE matching. This is the anti-vacuity core: the local runner's own
# orphan scan is a bare-basename `git grep`, so prose naming a suite silences it while running
# nothing -- the shape cq-assert-anchor-not-bare-token forbids, and the loophole #7068's own
# block comment had to be written around. Anchoring on the invocation shape is only half the
# fix; without this strip a commented-out `# run: bash …/foo.test.sh` would still satisfy it.
JOB_RAW=$(awk -v job="  ${JOB}:" '
  $0 == job { injob = 1; next }
  injob && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { injob = 0 }
  injob { print }
' "$WF")

if [[ -z "${JOB_RAW//[[:space:]]/}" ]]; then
  err "could not slice the \`${JOB}\` job out of $WF_REL -- the job was renamed, removed, or"
  err "  its indentation changed. This gate cannot make any claim; fix the slice, do not delete it."
  exit 1
fi

JOB_CODE=$(printf '%s\n' "$JOB_RAW" | grep -vE '^[[:space:]]*#' || true)

# MASKING CHECK. A step that exists can still be neutralised by `continue-on-error: true`
# (which this workflow warns yields conclusion=success over outcome=failure) or by a false
# `if:`. Both are zero in this job today, so asserting it is a ratchet rather than a cleanup.
mask_hits=$(printf '%s\n' "$JOB_CODE" | grep -cE '^[[:space:]]+(continue-on-error|if):' || true)
if (( mask_hits > 0 )); then
  err "the \`${JOB}\` job now contains ${mask_hits} \`continue-on-error:\`/\`if:\` key(s)."
  err "  Those can mask a suite failure (conclusion=success over outcome=failure) or skip the"
  err "  step entirely, so registration would no longer imply execution. If this is deliberate,"
  err "  narrow this check rather than deleting it."
  exit 1
fi

# ONE pass to build both sets, keyed by exact path string.
#
# Extracting into associative arrays -- instead of building a per-suite regex from the
# filename -- removes an entire defect class: `${rel//./\\.}` escaped only `.`, so a suite
# named `foo+bar.test.sh` produced a FALSE message telling the author to add a step that was
# already there (fail-closed, but a lie). Exact string lookup cannot misread any filename.
declare -A REGISTERED=()   # single-line `run: bash <path>` (optional trailing # comment)
declare -A INVOKED=()      # `bash <path>` in ANY shape, incl. multi-line run:| and sudo

while IFS= read -r p; do
  [[ -n "$p" ]] && REGISTERED["$p"]=1
done < <(printf '%s\n' "$JOB_CODE" | sed -nE \
  "s|^[[:space:]]*run: bash (${INFRA_PREFIX}/[^[:space:]]+\.test\.sh)[[:space:]]*(#.*)?$|\1|p")

while IFS= read -r p; do
  [[ -n "$p" ]] && INVOKED["$p"]=1
done < <(printf '%s\n' "$JOB_CODE" | grep -oE \
  "(^|[[:space:]])(sudo[[:space:]]+)?bash[[:space:]]+${INFRA_PREFIX}/[^[:space:]]+\.test\.sh" \
  | sed -E 's|.*bash[[:space:]]+||' || true)

# Extraction non-vacuity. If the sed above stops matching (indentation change, `run:` reworded),
# every suite would report "not registered" -- loud, but for the wrong reason. Naming it is
# cheaper to debug than 90 identical errors.
if (( ${#REGISTERED[@]} < 50 )); then
  err "extracted only ${#REGISTERED[@]} single-line \`run: bash\` step(s) from the \`${JOB}\` job"
  err "  -- expected ~87. The extraction is broken, not the workflow. Fix the pattern."
  exit 1
fi

# Enumerate with git ls-files, mirroring run-registered-suites.sh's own pathspec.
#
# NOT `find`: find sees untracked files, and run-registered-suites.test.sh writes a real
# fixture into the tracked tree with no trap covering it, so an interrupted run leaves a
# stray suite behind -- which would red this REQUIRED check and tell the operator to register
# a test fixture. git ls-files also matches the sibling precedent (lint-orphan-test-suites.sh).
SUITES=()
while IFS= read -r f; do
  [[ -n "$f" ]] && SUITES+=("$f")
done < <(git -C "$REPO_ROOT" ls-files \
  "${INFRA_PREFIX}/*.test.sh" "${INFRA_PREFIX}/**/*.test.sh" | LC_ALL=C sort -u)

# Minimum-cardinality guard. Without it a broken enumeration (renamed directory, bad pathspec)
# yields ZERO suites and the loop below passes with zero coverage -- a green run that checked
# nothing, which is the same silent-and-green shape this gate exists to remove. 94 suites
# today; a count this low means the enumeration broke, not that suites were deleted.
# Lower it deliberately, with a reason, if the directory ever genuinely shrinks that far.
if (( ${#SUITES[@]} < 50 )); then
  err "enumerated only ${#SUITES[@]} infra suite(s) under ${INFRA_PREFIX} -- expected ~94."
  err "  The enumeration is broken; this gate cannot make any claim. Fix it, do not lower the floor."
  exit 1
fi

declare -A UNDERIVABLE_PIN=()
for u in "${KNOWN_UNDERIVABLE[@]}"; do UNDERIVABLE_PIN["$u"]=1; done

fails=0
excluded_n=0
underivable_n=0

for rel in "${SUITES[@]}"; do
  base="${rel##*/}"

  excluded=""
  for e in "${EXCLUSIONS[@]}"; do
    [[ "${e%%|*}" == "$base" ]] && excluded="${e#*|}"
  done

  if [[ -n "$excluded" ]]; then
    # Fail-closed on a reasonless or issue-less exclusion: skipping must be a recorded
    # decision, not a silent absorption. `#[1-9][0-9]*` rather than `#[0-9]+` so a
    # placeholder `#0` cannot satisfy "cites a tracking issue".
    if [[ -z "${excluded// /}" ]] || ! grep -qE '#[1-9][0-9]*' <<< "$excluded"; then
      err "exclusion for $rel has no reason or no tracking issue"
      fails=$((fails + 1))
    # An exclusion waives the SHAPE requirement, never EXISTENCE. Without this arm the
    # exclusion is a blanket exemption: deleting the excluded suite's invocation outright
    # stops it running in CI and this gate stays green -- a fail-open, narrow but real, and
    # one introduced by the exclusion itself. Measured: with only the reason/issue check
    # above, removing loopback's `sudo bash` line left the gate at rc=0.
    elif [[ -z "${INVOKED[$rel]+x}" ]]; then
      err "$rel is EXCLUDED from the single-line shape requirement, but it is not invoked"
      err "  anywhere in the \`${JOB}\` job -- so it runs in no CI step there."
      err "  An exclusion waives the shape, never the registration. Either restore its"
      err "  invocation, or delete both the suite and its exclusion entry."
      fails=$((fails + 1))
    else
      echo "note: $base excluded -- $excluded"
      excluded_n=$((excluded_n + 1))
    fi
    continue
  fi

  if [[ -z "${REGISTERED[$rel]+x}" ]]; then
    # Distinguish the two failure modes -- they have different fixes.
    if [[ -n "${INVOKED[$rel]+x}" ]]; then
      err "$rel IS invoked in the \`${JOB}\` job, but not in the single-line"
      err "  \`run: bash <path>\` form this gate requires. Do NOT fix this by adding a second"
      err "  step -- convert the existing one, or the suite runs twice."
      err "  Most such shapes -- an inline env prefix, a quoted scalar, a \`./\` prefix, a"
      err "  multi-line \`run: |\` -- also de-register the suite from run-registered-suites.sh,"
      err "  which derives single-line only, so it would never run locally even though CI does."
      err "  (A trailing \`&& cmd\` or \`| cmd\` IS still derivable locally; it is refused here"
      err "  because CI and the local run would then execute different commands.)"
      err "  Step-level \`env:\` is safe, and so is a trailing \`# comment\`. If the shape is"
      err "  unavoidable (it needs sudo), add a reasoned exclusion -- see below."
    else
      err "$rel is registered in NO single-line \`run: bash\` step of the \`${JOB}\` job in"
      err "  $WF_REL, and scripts/test-all.sh does not cover ${INFRA_PREFIX} either."
      err "  (Only that job is checked; another workflow invoking it would not count here.)"
      err "  Add a \`- name:\` / \`run: bash $rel\` step pair to that job -- a bare \`run:\` line"
      err "  appended to an existing step would clobber that step's own command."
    fi
    err "  To exclude instead: add \"<basename>|<reason citing #NNNN>\" to the EXCLUSIONS array"
    err "  in .github/scripts/test/test-infra-suite-registration.sh."
    fails=$((fails + 1))
    continue
  fi

  # Registered correctly. Now pin the subdirectory class (see KNOWN_UNDERIVABLE above).
  if [[ "${rel#"$INFRA_PREFIX/"}" == */* ]]; then
    if [[ -n "${UNDERIVABLE_PIN[$rel]+x}" ]]; then
      underivable_n=$((underivable_n + 1))
    else
      err "$rel is correctly registered in CI, but it lives in a SUBDIRECTORY of"
      err "  ${INFRA_PREFIX}, and run-registered-suites.sh cannot derive it: its extraction"
      err "  character class excludes \`/\` (#7076). So it will run in CI and NEVER run through"
      err "  the local runner that the work and ship skills mandate as the infra exit gate."
      err "  Either move it to ${INFRA_PREFIX}/ (top level), or -- if the subdirectory is"
      err "  deliberate -- add it to KNOWN_UNDERIVABLE in this file and say so on #7076."
      fails=$((fails + 1))
    fi
  fi
done

# A pinned entry that no longer exists means the pin is stale: #7076 may have been fixed, or
# the suite was moved/deleted. Either way the list must shrink with reality, or it silently
# licenses a gap that is no longer real.
for u in "${KNOWN_UNDERIVABLE[@]}"; do
  found=""
  for rel in "${SUITES[@]}"; do [[ "$rel" == "$u" ]] && found=1 && break; done
  if [[ -z "$found" ]]; then
    err "KNOWN_UNDERIVABLE lists $u, which is not a tracked infra suite."
    err "  Remove the stale entry (and if #7076 is fixed, remove the whole list)."
    fails=$((fails + 1))
  fi
done

if (( fails > 0 )); then
  # Deliberately mode-agnostic. An earlier version said "unregistered infra test suites: N",
  # which mislabelled every shape failure as an absence -- and the fix that mislabel implies
  # (ADD a step) leaves the malformed step in place, runs the suite twice, and returns rc=0.
  echo "infra suite registration: $fails failure(s) of ${#SUITES[@]} suite(s) on disk" >&2
  exit 1
fi

derivable=$(( ${#SUITES[@]} - excluded_n - underivable_n ))
echo "infra suite registration: ${#SUITES[@]} suites registered in \`${JOB}\`" \
     "(${derivable} derivable by run-registered-suites.sh;" \
     "${underivable_n} in subdirectories, not derivable -- #7076; ${excluded_n} excluded)"
