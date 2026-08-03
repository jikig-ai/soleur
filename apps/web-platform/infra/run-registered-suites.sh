#!/usr/bin/env bash
# Run every infra suite REGISTERED IN CI, locally and in parallel.
#
# WHY THIS EXISTS (#6730). These suites are registered as `run: bash …` steps in
# `.github/workflows/infra-validation.yml` — during #6730 a required check was RED
# behind a 223/223 green test-all, and the red was found by reading CI, not by
# testing locally. There was no local command that ran them; now there is.
#
# COVERAGE STATUS, CORRECTED (#7103 R5(a)). This header said "`scripts/test-all.sh`
# does not cover `apps/web-platform/infra/`" and that is no longer true: test-all.sh
# now invokes THIS FILE as a nested `run_suite`. The claim survived the change that
# falsified it because the sweep was indexed by file and never opened the file it
# had just started calling — the registered runner denying its own registration.
#
# What is true now, and the distinction matters: test-all.sh runs this runner only
# when `want_infra` holds (TEST_GROUP is `all` or `infra`) AND the diff touches this
# directory. CI's three shards (`webplat`, `bun`, `scripts`) satisfy neither, so a
# green run in those says nothing about infra — and test-all.sh now says so in its
# epilogue rather than claiming coverage it does not have. Read the log: it reports
# which of those happened, keyed on whether this runner actually ran.
#
# The suite list is DERIVED from infra-validation.yml rather than globbed off the
# directory, so this runner and CI cannot drift: a suite added to the workflow is
# picked up here automatically, and a suite that exists on disk but was never
# registered is reported as unregistered rather than silently counted as covered.
#
# Serial execution is not viable — 70 suites take well over ten minutes end to
# end. Parallelism is the difference between a gate people run and one they skip.
#
# TOOLING DEPENDENCY, recorded here because this is the auto-glob site (#7068).
# TWO registered suites need a real docker daemon:
#   - cloud-init-plugin-seed.test.sh    builds a small busybox fixture image (~2-4s in CI)
#   - git-data-runcmd-rehearsal.test.sh three `docker run --rm` invocations (~48-61s in CI,
#                                       the most expensive step in deploy-script-tests)
#
# Both self-skip with exit 0 when docker is missing or unreachable. The skip is NOT visible
# through this runner: the executor below runs each suite as `bash "{}" >/dev/null 2>&1` and
# prints `PASS`, so a docker-less laptop reports PASS for both while neither asserts anything
# — ~50-65s of coverage, silently absent. (An earlier version of this paragraph called it a
# "visible SKIP", which was false in the one file where it mattered most.)
#
# That is deliberate for local DX, and it is why CI does NOT rely on the skip:
# infra-validation.yml has a separate `docker info` assertion step that reds the job when the
# daemon is absent, rather than letting either suite pass vacuously. That step must stay
# ORDERED BEFORE both suites — today it precedes plugin-seed, and git-data-runcmd-rehearsal
# is later in the same job, so both are covered. That ordering is the invariant; it is not
# self-evident from either step. If you are debugging why a docker-dependent regression
# reproduced in CI but not locally, this is the reason.
#
# Docker is not the only external dependency, and an earlier version of this paragraph
# claimed it was ("every other registered suite needs only what a stock checkout has").
# Measured across the 86 derived suites (2026-07-30), by their own `command -v` preconditions:
#
#   docker      2   cloud-init-plugin-seed, git-data-runcmd-rehearsal
#   terraform   5   cloud-init-inngest-bootstrap, git-data-emit,
#                   git-data-render-strip-parity, git-data-runcmd-rehearsal, inngest
#   python3     5   canary-bundle-claim-check, git-data-emit,
#                   git-data-render-strip-parity, git-data-runcmd-rehearsal,
#                   workspaces-luks-g4-mutation
#   cloud-init  1   cloud-init-inngest-bootstrap
#   jq          3
#
# Every one of those self-skips with exit 0 when its tool is absent, and — per the paragraph
# above — this runner prints PASS for a skip. So on a bare checkout a green run here can be
# hiding a substantial share of the suite set. Re-derive this table rather than trusting it:
#   while read -r f; do grep -oE 'command -v [a-z0-9-]+' "$f"; done \
#     < <(bash apps/web-platform/infra/run-registered-suites.sh --list \
#         | sed -n 's|^  \(apps/.*\.test\.sh\)$|\1|p') | sort | uniq -c | sort -rn
#
# No derived suite invokes sudo (measured: 0) — see the derive-but-do-not-execute discussion
# in #7076 for why that matters.
#
# Usage:
#   bash apps/web-platform/infra/run-registered-suites.sh          # all suites
#   JOBS=12 bash apps/web-platform/infra/run-registered-suites.sh  # override width
#   bash apps/web-platform/infra/run-registered-suites.sh --list   # derive only, run nothing
#
# `--list` prints the derived suite list and the orphan report without executing
# anything. It exists so this script's own logic (derivation, the zero-guard, the
# orphan scan) is testable in under a second — a runner whose correctness could
# only be checked by a 25-minute full run would not, in practice, be checked.
# INFRA_WF overrides the workflow path for the same reason (fixtures).
#
# Exit 0 only when every registered suite passes.

set -uo pipefail

# Default TMPDIR to /var/tmp (disk-backed), mirroring scripts/test-all.sh.
#
# These suites are the heaviest bulk writers in the repo: several copy the whole
# 162 MB `.terraform` provider tree PER MUTATION, and `credential-persist-home-guard`
# alone makes ~13 such copies. Against the ~4 GiB /tmp tmpfs that exhausts the mount
# and the suite dies on `cp: No space left on device` — a RED that looks like a real
# regression and is really a full RAM disk. It reproduces with the runner completely
# idle, so it is capacity, not contention.
#
# test-all.sh already defaults this, but it points here — the ONE runner it structurally
# cannot cover — and that pointer used to land on a command still requiring a manual
# `TMPDIR=/var/tmp` prefix. Defaulting it there and not here left the footgun exactly
# where the hand-off sends you; #6977 removed it in both halves. (#7014 moved that
# pointer to test-all.sh's PREAMBLE, so it now arrives before the run is paid for; a
# one-line restatement stays in the epilogue for `tail` readers.)
#
# Respects an explicit caller value — CI or an operator pinning TMPDIR keeps it.
export TMPDIR="${TMPDIR:-/var/tmp}"

LIST_ONLY=0
[[ "${1:-}" == "--list" ]] && LIST_ONLY=1

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

WF="${INFRA_WF:-.github/workflows/infra-validation.yml}"
[[ -f "$WF" ]] || { echo "FATAL: $WF not found — cannot derive the registered suite list." >&2; exit 2; }

mapfile -t SUITES < <(
  grep -oE 'run: bash apps/web-platform/infra/[A-Za-z0-9._-]+\.test\.sh' "$WF" \
    | sed 's/run: bash //' | sort -u
)

# A silent zero here would print "0 failed" and read as success — the exact
# false-green this runner exists to end.
(( ${#SUITES[@]} > 0 )) || {
  echo "FATAL: derived ZERO suites from $WF. The 'run: bash …' step shape changed;" >&2
  echo "       fix the extraction rather than trusting this run." >&2
  exit 2
}

# Report suites present on disk that NO workflow or script references. A test that
# nothing runs is not coverage, and it fails silently forever — the same
# false-assurance class as the test-all blind spot above, one level down.
#
# Advisory HERE, but no longer advisory ANYWHERE (#7068): every suite this block can print
# is a hard failure of .github/scripts/test/test-infra-suite-registration.sh, which runs in
# `guard-script-fixture-tests` — a REQUIRED, merge_group-triggered, path-filter-free check.
# The chain is exact: a suite is printed here only when its basename appears in no workflow,
# so no `run: bash <path>` step exists, so that gate's single-line check AND its any-shape
# fallback both fail. The gate's EXCLUSIONS escape does not rescue it either, because the
# exclusion arm independently requires an invocation to exist.
#
# So do not read a NOTE below as optional. This runner still declines to FAIL on it — its job
# is to run what CI runs, not to police the rest — but the merge will be blocked. Said
# explicitly because the previous wording ("Advisory, not a failure") was written before that
# gate existed and would now tell you registration is optional, which is the opposite of true.
report_orphans() {
  local -a orphans
  mapfile -t orphans < <(
    while IFS= read -r f; do
      git grep -qF -- "$(basename "$f")" -- .github/workflows/ scripts/ || printf '%s\n' "$f"
    done < <(git ls-files 'apps/web-platform/infra/**/*.test.sh' 'apps/web-platform/infra/*.test.sh' | sort -u)
  )
  (( ${#orphans[@]} > 0 )) || return 0
  echo ""
  echo "NOTE: ${#orphans[@]} suite(s) on disk are referenced by NO workflow or script —"
  echo "      nothing runs them, in CI or here:"
  printf '  %s\n' "${orphans[@]}"
}

if (( LIST_ONLY )); then
  echo "Derived ${#SUITES[@]} registered infra suite(s) from ${WF}:"
  printf '  %s\n' "${SUITES[@]}"
  report_orphans
  exit 0
fi

# min(nproc, 6) — capped because several suites shell out to terraform/docker and
# oversubscribing turns a slow run into a flaky one.
_NPROC=$(nproc 2>/dev/null || echo 4)
JOBS="${JOBS:-$(( _NPROC < 6 ? _NPROC : 6 ))}"
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

echo "Running ${#SUITES[@]} registered infra suite(s) with -P ${JOBS}…"

printf '%s\n' "${SUITES[@]}" \
  | xargs -P "$JOBS" -I{} bash -c \
      'if bash "{}" >/dev/null 2>&1; then echo "PASS {}"; else echo "RED  {}"; fi' \
  | tee "$LOG"

RED=$(grep -c '^RED' "$LOG" || true)
PASS=$(grep -c '^PASS' "$LOG" || true)

report_orphans

echo ""
echo "=== registered infra suites: ${PASS} passed, ${RED} failed (of ${#SUITES[@]}) ==="
(( RED == 0 ))
