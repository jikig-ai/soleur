#!/usr/bin/env bash
# Grok Build pre-push gate — local CI parity before `git push`.
#
# Mirrors the reproducible subset of .github/workflows/ci.yml required checks:
#   Phase 1 — fast always-run jobs (seconds)
#   Phase 2 — scripts/test-all.sh (CI `test` aggregator: webplat + bun + scripts)
#   Phase 3 — web-platform next build (route-file validator; CI web-platform-build)
#   Phase 4 — plugins/soleur/scripts/grok-fidelity-gate.sh (CI grok-fidelity)
#
# CI-only (cannot run here): CodeQL, CLA, e2e Playwright container, tenant-integration
# (dev Supabase), dependency-review, skill-security-scan, creds-gated propagation probes.
#
# infra-validation.yml (suites under apps/web-platform/infra/) IS covered by this gate now,
# indirectly: it invokes `bash scripts/test-all.sh` with no TEST_GROUP, so `want_infra` holds
# and test-all.sh runs run-registered-suites.sh as a nested suite whenever the diff touches
# that directory (#7103 R5(a)).
#
# So do NOT "run it alongside this gate", which is what this comment used to say. That advice
# predates the registration and is now actively harmful: both entry points default
# TMPDIR=/var/tmp, so a concurrent second run reproduces the sibling-contention shape and can
# self-inflict a false RED — while paying the ~4-5 minute cost twice. Read test-all.sh's
# epilogue, which states whether the runner actually ran, and invoke it separately only when
# that line says it did not (#7014 is why the coverage status is stated here at all).
#
# Usage:
#   bash plugins/soleur/scripts/grok-pre-push-gate.sh
#   bash plugins/soleur/scripts/grok-pre-push-gate.sh --skip-build   # skip next build
#
# Inspect exit code explicitly — do not pipe through tail (see work SKILL.md §Phase 3).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$REPO_ROOT"

SKIP_BUILD=0
for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=1 ;;
    -h|--help)
      sed -n '1,20p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown arg: $arg (try --help)" >&2
      exit 2
      ;;
  esac
done

step() {
  echo ""
  echo "========================================"
  echo "==> $1"
  echo "========================================"
}

run_step() {
  local name="$1"
  shift
  step "$name"
  # Capture rc — `if "$@"` is a boolean test and discards the exit code, so a step that
  # reports 3 (test-all.sh's EXIT CONTRACT: zero suites failed, >= 1 suite terminated with a
  # signal-shaped status) would be re-labelled a failure. Non-zero either way: a step that was
  # not measured is not a step that passed.
  local rc=0
  "$@" || rc=$?
  if (( rc == 0 )); then
    echo "[ok] $name"
  elif (( rc == 3 )); then
    echo "[UNRESOLVED] $name — a suite was terminated; see the [KILLED] lines above" >&2
    exit 3
  else
    echo "[FAIL] $name" >&2
    exit 1
  fi
}

echo "grok-pre-push-gate: starting local CI parity (repo: $REPO_ROOT)"

# --- Phase 1: fast CI jobs (ci.yml always-run, no secrets) ---
run_step "readme-counts" bash scripts/sync-readme-counts.sh --check
run_step "adr-ordinals" bash scripts/check-adr-ordinals.sh
run_step "service-role-allowlist-gate" bash apps/web-platform/scripts/service-role-allowlist-gate.sh
run_step "lint-bot-synthetic-statuses" bash scripts/lint-bot-synthetic-statuses.sh
run_step "lint-bot-synthetic-completeness" bash scripts/lint-bot-synthetic-completeness.sh
run_step "lint-conversations-update-callsites" bash scripts/lint-conversations-update-callsites.sh
run_step "tc-document-sha-guard" bash apps/web-platform/scripts/check-tc-document-sha.sh

if git rev-parse --verify origin/main >/dev/null 2>&1; then
  git fetch --no-tags --quiet origin main 2>/dev/null || true
  merge_base="$(git merge-base origin/main HEAD)"
  run_step "rule-body-lint" python3 scripts/lint-rule-bodies.py --check --base "$merge_base"
else
  echo "SKIP rule-body-lint (no origin/main ref)"
fi

# lockfile-sync (ci.yml): regenerate under npm@11 and diff; restore on failure.
step "lockfile-sync"
if command -v npm >/dev/null 2>&1; then
  npm_major="$(npm --version | cut -d. -f1)"
  if [[ "$npm_major" != "11" ]]; then
    echo "WARNING: npm $(npm --version) — CI pins npm@11 for lockfile-sync; install npm@11 for exact parity" >&2
  fi
  (cd apps/web-platform && npm install --package-lock-only)
  if git diff --exit-code apps/web-platform/package-lock.json; then
    echo "[ok] lockfile-sync"
  else
    git checkout -- apps/web-platform/package-lock.json
    echo "[FAIL] lockfile-sync — package-lock.json out of sync with package.json" >&2
    echo "Fix: cd apps/web-platform && npx --yes npm@11 install --package-lock-only && commit" >&2
    exit 1
  fi
else
  echo "SKIP lockfile-sync (npm not on PATH)" >&2
fi

# --- Phase 2: full test aggregator (CI `test` required check) ---
run_step "test-all (CI test aggregator)" bash scripts/test-all.sh

# --- Phase 3: next build / route validator (CI web-platform-build) ---
if [[ "$SKIP_BUILD" -eq 0 ]]; then
  step "web-platform-build"
  if [[ -f apps/web-platform/package-lock.json ]]; then
    (cd apps/web-platform && npm ci && npm run build)
    echo "[ok] web-platform-build"
  else
    echo "SKIP web-platform-build (no package-lock.json)" >&2
  fi
else
  echo "SKIP web-platform-build (--skip-build)"
fi

# --- Phase 4: Grok fidelity (CI grok-fidelity required check) ---
export GROK_FIDELITY_SKIP_BUDGET=1
run_step "grok-fidelity-gate" bash plugins/soleur/scripts/grok-fidelity-gate.sh

echo ""
echo "grok-pre-push-gate: PASS — safe to git push"