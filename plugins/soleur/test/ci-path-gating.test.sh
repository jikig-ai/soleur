#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# ci-path-gating — pins the in-job/detect gating added by #8897 (CI efficiency
# item 3) to the properties that make it safe.
#
# WHAT THIS EXISTS TO CATCH. The gated surfaces are advisory or required checks
# whose "run" arm is now conditional on a file-list probe. The unsafe shapes:
#   (a) the required `dependency-review` job gains a JOB-LEVEL `if:` — on a
#       merge_group ref the check could stop reporting and stall the queue;
#   (b) the manifest regex in dependency-review drifts narrower than the
#       action's real coverage — a manifest change skips review silently;
#   (c) a gated guard's own scanned surface escapes its detect pattern —
#       false-skip disables the gate;
#   (d) the fail-open branches are deleted — an API hiccup skips a gate.
#
# Pins are grep/structure-anchored, the same shape as pr-fanout-ledger.test.sh.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

passes=0
fails=0
FAILURES=()
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1" >&2; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
DEP="$REPO_ROOT/.github/workflows/dependency-review.yml"
PQG="$REPO_ROOT/.github/workflows/pr-quality-guards.yml"
CHECK_SH="$REPO_ROOT/.github/scripts"
for f in "$DEP" "$PQG"; do
  [ -f "$f" ] || { printf 'FAIL: %s not found\n' "$f" >&2; exit 2; }
done

echo "=== ci-path-gating: gating pins ==="

# A1 — dependency-review.yml carries the in-job detect step …
if grep -q 'id: detect' "$DEP"; then pass; else fail "A1: dependency-review detect step missing"; fi

# A2 — … the pull_request action step's if: reads steps.detect.outputs.deps …
if grep -q "steps.detect.outputs.deps" "$DEP"; then pass; else
  fail "A2: pull_request step not gated on steps.detect.outputs.deps"; fi

# A3 — … and the JOB carries no job-level `if:` (required check must always run).
job_if=$(python3 - "$DEP" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
print(doc.get("jobs", {}).get("dependency-review", {}).get("if", ""))
PY
)
if [ -z "$job_if" ]; then pass; else fail "A3: dependency-review job-level if: present ($job_if)"; fi

# A4 — manifest regex covers the repo's real manifest set.
for m in 'package\.json' 'package-lock\.json' 'bun\.lock' 'requirements[^/]*\.txt' 'pyproject\.toml' 'go\.mod' 'Cargo\.toml' 'Gemfile'; do
  if grep -qF "$m" "$DEP"; then pass; else fail "A4: manifest regex missing $m"; fi
done

# A5 — the workflow self-path self-triggers.
if grep -qF "dependency-review\\.yml" "$DEP"; then pass; else fail "A5: dependency-review self-path trigger missing"; fi

# A6 — the fail-open branches exist: empty/unresolvable file list → deps=true.
if grep -q '\-z "\$files"' "$DEP" && grep -q 'deps=true' "$DEP"; then pass; else
  fail "A6: dependency-review fail-open branch missing"; fi

# B1 — pr-quality-guards detect job exists with the five outputs.
if grep -q '^  detect:' "$PQG"; then pass; else fail "B1: detect job missing"; fi
for o in settings_json worktrees webplat client_pii sweep; do
  if grep -q "$o:" "$PQG" && grep -q "outputs.$o" "$PQG"; then pass; else
    fail "B1: detect output $o missing"; fi
done

# B2 — each gated job has `needs: detect` and an `if:` naming its output.
declare -A GATE=( [settings-json-integrity]=settings_json [stray-worktree-marker-block]=worktrees \
  [userid-bypass-lint]=webplat [client-pii-grep]=client_pii [sweep-completeness]=sweep )
for job in "${!GATE[@]}"; do
  out="${GATE[$job]}"
  block=$(awk -v j="  $job:" 'BEGIN{f=0} $0==j{f=1} f&&/^  [a-z]/&&$0!=j{exit} f' "$PQG")
  if printf '%s' "$block" | grep -q 'needs: detect' \
     && printf '%s' "$block" | grep -q "outputs.$out"; then pass; else
    fail "B2: $job missing needs: detect / outputs.$out"; fi
done

# B3 — the two required jobs carry no `needs: detect` edge.
for req in guard-script-fixture-tests markdown-lint; do
  block=$(awk -v j="  $req:" 'BEGIN{f=0} $0==j{f=1} f&&/^  [a-z]/&&$0!=j{exit} f' "$PQG")
  if printf '%s' "$block" | grep -q 'needs: detect'; then
    fail "B3: required job $req reads needs: detect"; else pass; fi
done

# B4 — fail-open: non-PR event / empty list emits all-true; registry unreadable → sweep=true.
if grep -q 'EVENT_NAME" != "pull_request"' "$PQG" && grep -q 'emit true' "$PQG" \
   && grep -q 'sweep=true' "$PQG"; then pass; else
  fail "B4: detect fail-open branches missing"; fi

# B5 — script-surface ⊆ detect-pattern (grep-anchored against the real scripts).
# check-settings-integrity.sh must concern itself only with .claude/settings.json.
if [ -f "$CHECK_SH/check-settings-integrity.sh" ] \
   && grep -qE '\.claude/settings\.json' "$CHECK_SH/check-settings-integrity.sh"; then pass; else
  fail "B5: check-settings-integrity.sh does not anchor .claude/settings.json"; fi
# check-client-pii-sentry.sh's find roots must be inside the client_pii regex roots.
if [ -f "$CHECK_SH/check-client-pii-sentry.sh" ]; then
  roots=$(grep -oE 'apps/web-platform/(lib|components|app|server)[^"'\'' ]*' "$CHECK_SH/check-client-pii-sentry.sh" | cut -d/ -f3 | sort -u)
  bad=""
  for r in $roots; do
    case "$r" in lib|components|app) ;; *) bad="$bad $r";; esac
  done
  if [ -z "$bad" ]; then pass; else fail "B5: client-pii finds outside detect roots:$bad"; fi
else
  fail "B5: check-client-pii-sentry.sh missing"
fi
# sweep-completeness' registry is the detect's source of truth.
if [ -f "$CHECK_SH/check-sweep-completeness.sh" ] \
   && grep -q 'enforcement-contracts.json' "$CHECK_SH/check-sweep-completeness.sh"; then pass; else
  fail "B5: check-sweep-completeness.sh does not read enforcement-contracts.json"; fi

echo "=== ci-path-gating: $passes passed, $fails failed ==="
[ "$fails" -eq 0 ] || { printf '%s\n' "${FAILURES[@]}" >&2; exit 1; }
