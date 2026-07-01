#!/usr/bin/env bash
# Tests for the /soleur:sync domain-model area wiring (#5754).
# Asserts the sync.md command dispatch invariants (the area the plan mirrors from
# rule-prune) + an end-to-end smoke of the backend script the area invokes.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYNC_MD="$REPO_ROOT/plugins/soleur/commands/sync.md"
DRIFT="$REPO_ROOT/scripts/domain-model-drift.sh"
pass=0; fail=0
_r() { if [[ "$2" == ok ]]; then pass=$((pass+1)); echo "[ok] $1"; else fail=$((fail+1)); echo "[FAIL] $1 ${3:-}" >&2; fi; }

# --- sync.md dispatch wiring ------------------------------------------------
grep -qE 'argument-hint:.*domain-model' "$SYNC_MD" && _r "argument-hint lists domain-model" ok || _r "argument-hint lists domain-model" fail
grep -qE '^\*\*Valid areas:\*\*.*`domain-model`' "$SYNC_MD" && _r "Valid areas lists domain-model" ok || _r "Valid areas lists domain-model" fail
# excluded from `all` (mirrors rule-prune): the parse-filter must name domain-model as EXCEPT
grep -qE 'EXCEPT.*domain-model|domain-model.*must be invoked explicitly' "$SYNC_MD" \
  && _r "domain-model excluded from all dispatch" ok || _r "domain-model excluded from all dispatch" fail
grep -qE '^#### Domain Model Analysis' "$SYNC_MD" && _r "Domain Model Analysis section present" ok || _r "Domain Model Analysis section present" fail
# the section invokes the backend script in both modes
grep -qE 'scripts/domain-model-drift\.sh drift' "$SYNC_MD" && _r "section invokes drift mode" ok || _r "section invokes drift mode" fail
grep -qE 'scripts/domain-model-drift\.sh (\\\n *)?write-row' "$SYNC_MD" && _r "section invokes write-row mode" ok || _r "section invokes write-row mode" fail
# Phase-4 area-scope list includes domain-model (so definition-sync does not run for it)
grep -qE 'Area is a specific scope.*domain-model' "$SYNC_MD" && _r "Phase-4 scope list includes domain-model" ok || _r "Phase-4 scope list includes domain-model" fail

# --- end-to-end smoke: backend produces a disclaimered report ---------------
[[ -x "$DRIFT" || -f "$DRIFT" ]] || { _r "backend script exists" fail; echo "=== $pass passed, $fail failed ==="; exit 1; }
_r "backend script exists" ok

smoke="$(mktemp -d)"; mig="$smoke/apps/web-platform/supabase/migrations"; mkdir -p "$mig"
echo "CREATE TABLE only_tbl (id uuid PRIMARY KEY);" > "$mig/001.sql"
reg="$smoke/register.md"
printf '# Register\n## Business Rules\n| ID | Rule | Statement | Source |\n|---|---|---|---|\n| BR-1 | doc | The `only_tbl` table. | migration 001 |\n\n## Auto-inferred (unreviewed)\n| Anchor | Candidate statement |\n|---|---|\n' > "$reg"
report="$(bash "$DRIFT" drift --repo "$smoke" --register "$reg" 2>/dev/null)"; rc=$?
echo "$report" | grep -qi "NOT a security audit" && _r "report carries completeness disclaimer" ok || _r "report carries completeness disclaimer" fail
[[ "$rc" -eq 0 ]] && _r "clean fixture → drift exit 0" ok || _r "clean fixture → drift exit 0" fail "rc=$rc"
rm -rf "$smoke"

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
