#!/usr/bin/env bash
# Run every infra suite REGISTERED IN CI, locally and in parallel.
#
# WHY THIS EXISTS (#6730). `scripts/test-all.sh` does not cover
# `apps/web-platform/infra/`. Those suites are registered ONLY as `run: bash …`
# steps in `.github/workflows/infra-validation.yml`, so a green test-all says
# nothing about an infra change — during #6730 a required check was RED behind a
# 223/223 green test-all, and the red was found by reading CI, not by testing
# locally. There was no local command that ran them; now there is.
#
# The suite list is DERIVED from infra-validation.yml rather than globbed off the
# directory, so this runner and CI cannot drift: a suite added to the workflow is
# picked up here automatically, and a suite that exists on disk but was never
# registered is reported as unregistered rather than silently counted as covered.
#
# Serial execution is not viable — 70 suites take well over ten minutes end to
# end. Parallelism is the difference between a gate people run and one they skip.
#
# Usage:
#   bash apps/web-platform/infra/run-registered-suites.sh          # all suites
#   JOBS=12 bash apps/web-platform/infra/run-registered-suites.sh  # override width
#
# Exit 0 only when every registered suite passes.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

WF=".github/workflows/infra-validation.yml"
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

# Report suites present on disk that NO workflow or script references. A test that
# nothing runs is not coverage, and it fails silently forever — the same
# false-assurance class as the test-all blind spot above, one level down. Advisory,
# not a failure: this runner's job is to run what CI runs, not to police the rest.
mapfile -t ORPHANS < <(
  while IFS= read -r f; do
    git grep -qF -- "$(basename "$f")" -- .github/workflows/ scripts/ || printf '%s\n' "$f"
  done < <(git ls-files 'apps/web-platform/infra/**/*.test.sh' 'apps/web-platform/infra/*.test.sh' | sort -u)
)
if (( ${#ORPHANS[@]} > 0 )); then
  echo ""
  echo "NOTE: ${#ORPHANS[@]} suite(s) on disk are referenced by NO workflow or script —"
  echo "      nothing runs them, in CI or here:"
  printf '  %s\n' "${ORPHANS[@]}"
fi

echo ""
echo "=== registered infra suites: ${PASS} passed, ${RED} failed (of ${#SUITES[@]}) ==="
(( RED == 0 ))
