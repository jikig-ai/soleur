#!/usr/bin/env bash
# test-infra-suite-registration.sh -- fail when an infra *.test.sh is registered nowhere, or
# the sharded runner invocation that reaches it has been disconnected.
#
# WHY (#7068, re-shaped by #8736). Infra suites were once registered ONLY as explicit
# `run: bash …` steps in .github/workflows/infra-validation.yml, and this gate asserted that
# step shape. #8736 replaced ~146 serial named steps with a K=4 matrix whose legs all invoke
# apps/web-platform/infra/run-registered-suites.sh, and the runner now DERIVES its execute set
# by `git ls-files` glob: presence under apps/web-platform/infra/ IS registration (ADR-250).
#
# That makes the old per-suite step check tautological — every tracked suite is registered by
# construction — so what remains to gate is the CONNECTION, and the exceptions:
#
#   1. The `deploy-script-tests` matrix job must exist and invoke the runner with
#      SOLEUR_INFRA_SHARD wired from `matrix.leg`, with `fail-fast: false` — otherwise
#      one leg's failure cancels its siblings and coverage silently shrinks.
#   2. The runner step itself must carry NO `if:`/`continue-on-error:` — the masking
#      check, now scoped to the step that matters (artifact-upload steps legitimately
#      carry `if: failure()`/`always()`).
#   3. The PRIVILEGED set (suites that need root and therefore must NOT run under the
#      unprivileged runner — the derive-but-do-not-execute contract from #7076) must
#      each be `sudo bash`-invoked inside `deploy-script-tests-fixed`. The exclusion
#      waives the RUNNER, never the invocation.
#   4. `deploy-script-tests-done` must exist and need both legs — it is the single
#      verdict `notify-main-failure` reads.
#
# WHAT IT DOES *NOT* ASSERT, stated so no reader over-reads a green run:
#   - Whether a suite's VERDICT blocks merge. deploy-script-tests is advisory; promotion
#     is #6480's job, not this gate's.
#   - That infra-validation.yml runs at all for a given PR (paths-filtered, no
#     merge_group trigger) — same trigger asymmetry the old contract had.
#   - Manifest/matrix coherence: a stale suite-shard-legs.tsv degrades legs to
#     positional assignment — a balance problem, never a coverage one — so this gate
#     does not enforce it.
#
# The privileged list is read FROM THE RUNNER (its PRIVILEGED_WHY map), never
# duplicated here — two lists over one set is the drift this file exists to prevent,
# one level up. Each entry must cite a tracking issue, the same fail-closed discipline
# the old EXCLUSIONS array carried.
#
# WHY IT LIVES HERE. The `test-*.sh` glob in run-all.sh feeds guard-script-fixture-tests --
# REQUIRED, merge_group-triggered, path-filter-free. So this gate is genuinely blocking while
# adding NO new required-check name. It honours that glob's BASH-ONLY contract verbatim
# (git + sed + grep + awk, reading YAML as text) -- no terraform, no cloud-init, no apt.
#
# Its own non-vacuity is pinned by a committed harness, not by a comment:
# test-infra-suite-registration-mutations.sh (same directory, so also auto-globbed).
# Every arm below has a mutation row there.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF_REL=".github/workflows/infra-validation.yml"
WF="$REPO_ROOT/$WF_REL"
RUNNER_REL="apps/web-platform/infra/run-registered-suites.sh"
RUNNER="$REPO_ROOT/$RUNNER_REL"
JOB="deploy-script-tests"
FIXED_JOB="deploy-script-tests-fixed"
DONE_JOB="deploy-script-tests-done"
INFRA_PREFIX="apps/web-platform/infra"

err() { echo "::error::infra-suite-registration: $1" >&2; }

if [[ ! -f "$WF" ]]; then
  err "$WF_REL not found -- cannot verify infra suite registration"
  exit 1
fi
if [[ ! -f "$RUNNER" ]]; then
  err "$RUNNER_REL not found -- the runner this gate asserts wiring FOR is missing"
  exit 1
fi

# Slice a job's YAML text (comment lines stripped — a commented-out invocation must
# never satisfy a check; that was the anti-vacuity core of the old gate too).
# Job-scoping is load-bearing: a whole-file scan cannot honestly say "runs in no CI job".
slice_job() {  # slice_job <job-name>
  awk -v job="  $1:" '
    $0 == job { injob = 1; next }
    injob && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { injob = 0 }
    injob { print }
  ' "$WF" | grep -vE '^[[:space:]]*#' || true
}

JOB_RAW=$(slice_job "$JOB")
FIXED_RAW=$(slice_job "$FIXED_JOB")
DONE_RAW=$(slice_job "$DONE_JOB")

fails=0

if [[ -z "${JOB_RAW//[[:space:]]/}" ]]; then
  err "could not slice the \`$JOB\` job out of $WF_REL -- the job was renamed, removed, or"
  err "  its indentation changed. This gate cannot make any claim; fix the slice, do not delete it."
  exit 1
fi
if [[ -z "${FIXED_RAW//[[:space:]]/}" ]]; then
  err "could not slice the \`$FIXED_JOB\` job out of $WF_REL -- the privileged suites and"
  err "  fixed checks have nowhere to run. Restore the job or remove the privileged set."
  exit 1
fi
if [[ -z "${DONE_RAW//[[:space:]]/}" ]]; then
  err "could not slice the \`$DONE_JOB\` job out of $WF_REL -- notify-main-failure reads"
  err "  that aggregator's result; without it a red leg alerts nobody."
  exit 1
fi

# ── Arm 1: the matrix job invokes the runner, sharded, fail-open-proof ────────
# The runner step is identified by its `run:` line, not its name — names are prose.
RUNNER_STEPS=$(printf '%s\n' "$JOB_RAW" | grep -cE "run: bash ${RUNNER_REL}[[:space:]]*$" || true)
if (( RUNNER_STEPS != 1 )); then
  err "the \`$JOB\` job contains ${RUNNER_STEPS} \`run: bash ${RUNNER_REL}\` invocations"
  err "  (expected exactly 1). The suite set executes through that one step; zero means"
  err "  no infra suite runs in CI, two means every suite runs twice."
  fails=$((fails + 1))
fi

# SOLEUR_INFRA_SHARD must be wired from the matrix leg — a leg running the FULL set
# quadruples the wall clock this restructure exists to cut, and four identical legs
# are worse than one because they look sharded.
if ! grep -qE 'SOLEUR_INFRA_SHARD:[[:space:]]+\$\{\{[[:space:]]*matrix\.leg[[:space:]]*\}\}' <<< "$JOB_RAW"; then
  err "the \`$JOB\` job does not set SOLEUR_INFRA_SHARD from matrix.leg — without it"
  err "  every leg runs the FULL suite set (4x the wall clock, zero sharding)."
  fails=$((fails + 1))
fi

# A matrix without legs, or legs that are not k/N strings, is a silent full-set run.
LEG_ROWS=$(printf '%s\n' "$JOB_RAW" | grep -cE 'leg:[[:space:]]*\[' || true)
if (( LEG_ROWS < 1 )) || ! grep -qE 'leg:[[:space:]]*\["1/[0-9]+"' <<< "$JOB_RAW"; then
  err "the \`$JOB\` job's matrix has no \`leg: [\"k/N\", ...]\` list — the legs and the"
  err "  runner's shard parser have drifted."
  fails=$((fails + 1))
fi

# fail-fast: false — a RED leg must not cancel its siblings; the aggregator needs
# every leg's verdict and a cancelled sibling's suites never ran (coverage, not
# just attribution).
if ! grep -qE 'fail-fast:[[:space:]]*false' <<< "$JOB_RAW"; then
  err "the \`$JOB\` matrix lacks \`fail-fast: false\` — one RED leg cancels the other"
  err "  three, and a quarter of the suite set silently never runs."
  fails=$((fails + 1))
fi

# ── Arm 2: masking — scoped to the RUNNER STEP, not the job ───────────────────
# The old gate asserted zero `if:`/`continue-on-error:` keys job-wide, because then
# every step was a suite and masking any step masked coverage. Now the load-bearing
# step is the runner invocation; upload steps legitimately carry `if: failure()`/
# `always()`. Assert the runner step's own block is unmasked.
mask_hits=$(printf '%s\n' "$JOB_RAW" | awk -v RS='      - ' '/run-registered-suites\.sh/{print; exit}' \
  | grep -cE '^[[:space:]]+(continue-on-error|if):' || true)
if (( mask_hits > 0 )); then
  err "the \`$JOB\` runner step carries ${mask_hits} \`continue-on-error:\`/\`if:\` key(s) —"
  err "  masking the one step that executes every suite. Artifact-upload steps may carry"
  err "  \`if:\`; the runner step may not."
  fails=$((fails + 1))
fi

# ── Arm 3: the privileged set — derived from the RUNNER, invoked via sudo ─────
# PRIVILEGED_WHY lives in run-registered-suites.sh — the single source of truth for
# "needs root, never run unprivileged". Parse its `[basename]="reason"` entries.
# The map must parse AND be non-empty: an empty map is a legitimate future state
# (no root suites), so the floor is "the block parsed at all", asserted by the
# per-suite loop below — a suite under a privileged basename with no map entry is
# just a normal suite, which is the #7076 hole in reverse and is caught by... the
# local run itself going red. What THIS gate pins is narrower: every map entry is
# a real tracked suite AND is sudo-invoked in the fixed job.
declare -A PRIVILEGED=()
while IFS= read -r line; do
  base="${line%%]=*}"
  reason="${line#*]=}"
  [[ -n "$base" ]] || continue
  if ! grep -qE '#[1-9][0-9]*' <<< "$reason"; then
    err "privileged entry '$base' in ${RUNNER_REL}'s PRIVILEGED_WHY cites no tracking"
    err "  issue — an exclusion is a recorded decision, not a silent absorption."
    fails=$((fails + 1))
  fi
  PRIVILEGED["$base"]=1
done < <(sed -n 's/^  \[\([A-Za-z0-9._-]*\.test\.sh\)\]="\(.*\)"$/\1]=\2/p' "$RUNNER")

# Enumerate the tracked suite set — same `git ls-files` pathspec the runner uses.
SUITES=()
while IFS= read -r f; do
  [[ -n "$f" ]] && SUITES+=("$f")
done < <(git -C "$REPO_ROOT" ls-files \
  "${INFRA_PREFIX}/*.test.sh" "${INFRA_PREFIX}/**/*.test.sh" | LC_ALL=C sort -u)

# Minimum-cardinality guard: a broken enumeration yielding ZERO would pass every
# per-suite check below while certifying nothing.
if (( ${#SUITES[@]} < 50 )); then
  err "enumerated only ${#SUITES[@]} infra suite(s) under ${INFRA_PREFIX} -- expected ~140."
  err "  The enumeration is broken; this gate cannot make any claim. Fix it, do not lower the floor."
  exit 1
fi

declare -A TRACKED=()
for rel in "${SUITES[@]}"; do TRACKED["${rel##*/}"]=1; done

for base in "${!PRIVILEGED[@]}"; do
  if [[ -z "${TRACKED[$base]+x}" ]]; then
    err "PRIVILEGED_WHY in ${RUNNER_REL} lists '$base', which is not a tracked infra"
    err "  suite — a stale exclusion licenses a gap that is no longer real. Remove it."
    fails=$((fails + 1))
    continue
  fi
  # The exclusion waives the runner, never the invocation: it must be `sudo bash`ed
  # inside deploy-script-tests-fixed. Any shape inside that job counts (multi-line
  # `run: |` included — the sudo steps carry setup commands).
  if ! grep -qE "(^|[[:space:]])sudo[[:space:]]+bash[[:space:]]+${INFRA_PREFIX}/([A-Za-z0-9._-]+/)*${base}([[:space:]]|$)" <<< "$FIXED_RAW"; then
    err "$base is PRIVILEGED (excluded from the runner, needs root) but is NOT"
    err "  sudo-invoked anywhere in the \`$FIXED_JOB\` job — so it runs in NO job."
    err "  Either restore its \`sudo bash\` step there, or delete it from PRIVILEGED_WHY"
    err "  and let the legs run it unprivileged (only if it no longer needs root)."
    fails=$((fails + 1))
  fi
done

# ── Arm 3b: test/infra suites must be invoked SOMEWHERE ──────────────────────
# apps/web-platform/test/infra/*.test.sh lives OUTSIDE the runner's glob and is
# not uniformly registered in this workflow — vector-pii-scrub runs in another
# workflow entirely. The invariant is the weaker one this domain actually has:
# every tracked suite there is `bash`-invoked by at least one workflow file.
# (Per-suite home-job scoping stays a lint-orphan-test-suites.sh concern — it
# owns the six-surface census; duplicating its bookkeeping here is the drift
# this rewrite exists to remove.)
TESTINFRA_PREFIX="apps/web-platform/test/infra"
WF_STRIPPED_ALL=$(for w in "$REPO_ROOT"/.github/workflows/*.yml; do
    grep -vE '^[[:space:]]*#' "$w"
  done)
while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  # NOTE: herestrings, not `printf | grep -q` — under pipefail, grep -q exits on
  # first match and printf dies SIGPIPE (rc=141), which reads as "not found" here.
  # Measured: all six suites red-failed on a 1.4 MB stream.
  if ! grep -qE "(^|[[:space:]])bash[[:space:]]+${rel}([[:space:]]|$)" <<< "$WF_STRIPPED_ALL" \
     && ! grep -qE "sudo[[:space:]]+bash[[:space:]]+${rel}([[:space:]]|$)" <<< "$WF_STRIPPED_ALL"; then
    err "$rel is a tracked ${TESTINFRA_PREFIX}/ suite invoked by NO workflow —"
    err "  the runner's glob does not reach that directory, so it runs nowhere."
    fails=$((fails + 1))
  fi
done < <(git -C "$REPO_ROOT" ls-files "${TESTINFRA_PREFIX}/*.test.sh")

# ── Arm 4: the aggregator needs both legs ─────────────────────────────────────
for need in "$JOB" "$FIXED_JOB"; do
  # Membership, not substring: `deploy-script-tests` is a PREFIX of
  # `deploy-script-tests-fixed`, so a bare grep for the name is satisfied by the
  # sibling's entry — measured: dropping the matrix from needs: stayed green.
  # The job name must be followed by `]`, `,`, space, or end-of-line to count.
  # (`[] ,]` — a `]` first inside a bracket expression is a literal, not a close.)
  if ! grep -qE "needs:.*${need}([] ,]|$)" <<< "$DONE_RAW"; then
    err "\`$DONE_JOB\` does not list \`$need\` in its needs: — a leg can go red or"
    err "  be cancelled without the aggregator ever seeing it."
    fails=$((fails + 1))
  fi
done
if ! grep -qE 'if: always\(\)' <<< "$DONE_RAW"; then
  err "\`$DONE_JOB\` lacks \`if: always()\` — default needs: semantics render a"
  err "  cancelled/failed upstream as \`skipped\`, which some branch protection"
  err "  treats as success (fail-open)."
  fails=$((fails + 1))
fi

if (( fails > 0 )); then
  echo "infra suite registration: $fails failure(s)" >&2
  exit 1
fi

echo "infra suite registration: ${#SUITES[@]} suites covered by the ${JOB} matrix" \
     "(${#PRIVILEGED[@]} privileged -> sudo in ${FIXED_JOB}; presence under" \
     "${INFRA_PREFIX}/ IS registration)"
