#!/usr/bin/env bash
# domain-model-drift.test.sh — tests for the /soleur:sync domain-model analyzer (#5754).
#
# Run via:  bash scripts/domain-model-drift.test.sh
#
# Synthesized fixtures ONLY (cq-test-fixtures-synthesized-only) — no real migrations,
# no real secrets. Each fixture is written to a fresh mktemp repo so the extractor's
# generic --repo path is exercised end-to-end.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIFT="$SCRIPT_DIR/domain-model-drift.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $*" >&2; }

# --- fixture builder -------------------------------------------------------
# make_repo <migrations-subdir-relative-to-supabase> — prints a fresh repo root.
make_repo() {
  local root mig
  root="$(mktemp -d)"
  mig="$root/apps/web-platform/supabase/migrations"
  mkdir -p "$mig"
  printf '%s' "$mig"
}

# --- Test 1: base-migration constraint + policy extraction -----------------
t1_root="$(dirname "$(make_repo)")"; t1_root="$(cd "$t1_root/../../.." && pwd)"
# (make_repo returns the migrations dir; recompute the repo root cleanly)
t1_repo="$(mktemp -d)"; t1_mig="$t1_repo/apps/web-platform/supabase/migrations"; mkdir -p "$t1_mig"
cat > "$t1_mig/001_base.sql" <<'SQL'
CREATE TABLE workspace_members (
  workspace_id uuid NOT NULL,
  user_id uuid NOT NULL,
  role text NOT NULL CHECK (role IN ('owner', 'member')),
  PRIMARY KEY (workspace_id, user_id)
);
CREATE POLICY workspaces_select_for_members ON workspaces
  FOR SELECT USING (public.is_workspace_member(workspaces.id, auth.uid()));
CREATE FUNCTION is_workspace_member(p_ws uuid, p_user uuid) RETURNS boolean
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$ BEGIN RETURN true; END; $$;
SQL
out1="$(bash "$DRIFT" extract --repo "$t1_repo" 2>/dev/null)"
rc1=$?
if [[ "$rc1" -eq 0 ]]; then pass; else fail "T1: extract exit=$rc1 (want 0)"; fi
echo "$out1" | jq -e '.schema_version >= 1' >/dev/null 2>&1 && pass || fail "T1: missing schema_version"
echo "$out1" | jq -e '[.facts[] | select(.anchor | contains("workspace_members_pkey"))] | length == 1' >/dev/null 2>&1 && pass || fail "T1: pkey fact not extracted"
echo "$out1" | jq -e '[.facts[] | select(.kind=="policy" and (.anchor | contains("workspaces_select_for_members")))] | length == 1' >/dev/null 2>&1 && pass || fail "T1: policy fact not extracted"
echo "$out1" | jq -e '[.facts[] | select(.kind=="guard" and (.object=="is_workspace_member"))] | length == 1' >/dev/null 2>&1 && pass || fail "T1: SECURITY DEFINER guard not extracted"
# anchors are content-anchored (contain the filename + ›), never a bare line number
echo "$out1" | jq -e 'all(.facts[]; (.anchor | contains("001_base.sql")) and (.anchor | test(":[0-9]+$") | not))' >/dev/null 2>&1 && pass || fail "T1: anchor not content-anchored / has line number"

# --- Test 2: .down.sql excluded from replay --------------------------------
t2_repo="$(mktemp -d)"; t2_mig="$t2_repo/apps/web-platform/supabase/migrations"; mkdir -p "$t2_mig"
cat > "$t2_mig/001_p.sql" <<'SQL'
CREATE POLICY live_policy ON t FOR SELECT USING (true);
SQL
cat > "$t2_mig/002_p.down.sql" <<'SQL'
DROP POLICY live_policy ON t;
SQL
out2="$(bash "$DRIFT" extract --repo "$t2_repo" 2>/dev/null)"
# the live policy from the base file must survive; the .down DROP must NOT delete it
echo "$out2" | jq -e '[.facts[] | select(.kind=="policy" and .object=="live_policy")] | length == 1' >/dev/null 2>&1 && pass || fail "T2: .down.sql DROP deleted a live policy fact"

# --- Test 3: last-writer-wins (same-name policy recreated with new predicate)
t3_repo="$(mktemp -d)"; t3_mig="$t3_repo/apps/web-platform/supabase/migrations"; mkdir -p "$t3_mig"
cat > "$t3_mig/001_a.sql" <<'SQL'
CREATE POLICY pol ON t FOR SELECT USING (old_predicate = 1);
SQL
cat > "$t3_mig/002_b.sql" <<'SQL'
DROP POLICY pol ON t;
CREATE POLICY pol ON t FOR SELECT USING (new_predicate = 2);
SQL
out3="$(bash "$DRIFT" extract --repo "$t3_repo" 2>/dev/null)"
echo "$out3" | jq -e '[.facts[] | select(.object=="pol")] | length == 1' >/dev/null 2>&1 && pass || fail "T3: expected exactly one live pol fact"
echo "$out3" | jq -e 'any(.facts[]; .object=="pol" and (.predicate | contains("new_predicate")))' >/dev/null 2>&1 && pass || fail "T3: live predicate is not the last writer"
echo "$out3" | jq -e 'any(.facts[]; .object=="pol" and (.predicate | contains("old_predicate"))) | not' >/dev/null 2>&1 && pass || fail "T3: dead predicate still present"

# --- Test 4: idempotency (byte-identical across two runs) -------------------
a4="$(bash "$DRIFT" extract --repo "$t1_repo" 2>/dev/null)"
b4="$(bash "$DRIFT" extract --repo "$t1_repo" 2>/dev/null)"
[[ "$a4" == "$b4" ]] && pass || fail "T4: extract not byte-identical across runs"

# --- Test 5: fail-closed secret-shape scan ---------------------------------
t5_repo="$(mktemp -d)"; t5_mig="$t5_repo/apps/web-platform/supabase/migrations"; mkdir -p "$t5_mig"
# a synthesized secret-shaped literal embedded in a policy predicate (built by
# concatenation so the file itself carries no contiguous real-looking token pattern
# that push-protection would flag — the runtime string still matches the redactor)
printf 'CREATE POLICY leaky ON t FOR SELECT USING (token = %s);\n' "'sk-ant-$(printf 'api03')-XXXXXXXXXXXXXXXXXXXX'" > "$t5_mig/001.sql"
bash "$DRIFT" extract --repo "$t5_repo" >/dev/null 2>&1
rc5=$?
[[ "$rc5" -ne 0 ]] && pass || fail "T5: secret-shaped literal did not trigger fail-closed refuse (exit=$rc5)"

# --- Test 6: DO $$ / EXECUTE format() → blind_spots (never silent zero) -----
t6_repo="$(mktemp -d)"; t6_mig="$t6_repo/apps/web-platform/supabase/migrations"; mkdir -p "$t6_mig"
cat > "$t6_mig/001.sql" <<'SQL'
DO $$ BEGIN EXECUTE format('CREATE POLICY %I ON t FOR SELECT USING (true)', 'dyn'); END $$;
SQL
out6="$(bash "$DRIFT" extract --repo "$t6_repo" 2>/dev/null)"
echo "$out6" | jq -e '[.blind_spots[] | select(.file | contains("001.sql"))] | length >= 1' >/dev/null 2>&1 && pass || fail "T6: dynamic DO/EXECUTE not disclosed in blind_spots"

# --- Test 7: unsupported stack (no supabase migrations) → degrade gracefully
t7_repo="$(mktemp -d)"; mkdir -p "$t7_repo/src"; echo "package main" > "$t7_repo/src/main.go"
out7="$(bash "$DRIFT" extract --repo "$t7_repo" 2>/dev/null)"
rc7=$?
[[ "$rc7" -eq 0 ]] && pass || fail "T7: unsupported stack should exit 0 (got $rc7)"
echo "$out7" | jq -e '.stack == "unsupported"' >/dev/null 2>&1 && pass || fail "T7: unsupported stack not flagged"

# --- Test 8: symlink-deny / path confinement -------------------------------
bash "$DRIFT" extract --repo /nonexistent-path-xyz >/dev/null 2>&1
[[ $? -ne 0 ]] && pass || fail "T8: nonexistent --repo should fail"

# --- Test 9: drift — stale citation flagged, live citation NOT flagged (AC5) ---
t9_repo="$(mktemp -d)"; t9_mig="$t9_repo/apps/web-platform/supabase/migrations"; mkdir -p "$t9_mig"
t9_ts="$t9_repo/apps/web-platform/server"; mkdir -p "$t9_ts"
cat > "$t9_ts/workspace-resolver.ts" <<'TS'
export async function resolveActiveWorkspace(userId, supabase) { return null; }
TS
echo "CREATE POLICY p ON t FOR SELECT USING (true);" > "$t9_mig/001.sql"
t9_reg="$t9_repo/register.md"
cat > "$t9_reg" <<'MD'
# Domain Model & Business Rules Register

## Business Rules

| ID | Rule | Statement | Source |
|---|---|---|---|
| BR-1 | Live guard | Access via (`workspace-resolver.ts` `resolveActiveWorkspace`). | ADR-038 |
| BR-2 | Stale guard | Old probe (`workspace-resolver.ts` `resolveGoneSymbol`). | ADR-038 |
MD
out9="$(bash "$DRIFT" drift --repo "$t9_repo" --register "$t9_reg" 2>/dev/null)"
rc9=$?
# a synthesized non-existent symbol is flagged stale
echo "$out9" | grep -q "resolveGoneSymbol" && pass || fail "T9: stale citation (resolveGoneSymbol) not flagged"
# the LIVE resolveActiveWorkspace (exists in the cited file) is NOT flagged stale
echo "$out9" | awk '/[Ss]tale/{f=1} f' | grep -q "resolveActiveWorkspace" && fail "T9: live resolveActiveWorkspace wrongly flagged stale" || pass
# drift found → exit 1
[[ "$rc9" -eq 1 ]] && pass || fail "T9: drift-found exit=$rc9 (want 1)"

# --- Test 10: drift — clean register (no stale, table documented) → exit 0 ---
t10_repo="$(mktemp -d)"; t10_mig="$t10_repo/apps/web-platform/supabase/migrations"; mkdir -p "$t10_mig"
echo "CREATE TABLE lonely (id uuid PRIMARY KEY);" > "$t10_mig/001.sql"
t10_reg="$t10_repo/register.md"
cat > "$t10_reg" <<'MD'
# Register
## Business Rules
| ID | Rule | Statement | Source |
|---|---|---|---|
| BR-1 | Lonely table | The `lonely` table exists. | migration 001 |
MD
out10="$(bash "$DRIFT" drift --repo "$t10_repo" --register "$t10_reg" 2>/dev/null)"
rc10=$?
[[ "$rc10" -eq 0 ]] && pass || fail "T10: clean register drift-exit=$rc10 (want 0)"
echo "$out10" | grep -qi "NOT a security audit" && pass || fail "T10: report missing completeness disclaimer"

# --- Test 11: drift — undocumented table flagged ---
t11_repo="$(mktemp -d)"; t11_mig="$t11_repo/apps/web-platform/supabase/migrations"; mkdir -p "$t11_mig"
echo "CREATE POLICY secret_pol ON undocumented_table FOR SELECT USING (true);" > "$t11_mig/001.sql"
t11_reg="$t11_repo/register.md"
printf '# Register\n## Business Rules\n| ID | Rule | Statement | Source |\n|---|---|---|---|\n' > "$t11_reg"
out11="$(bash "$DRIFT" drift --repo "$t11_repo" --register "$t11_reg" 2>/dev/null)"
echo "$out11" | grep -q "undocumented_table" && pass || fail "T11: undocumented table not surfaced"

echo "domain-model-drift.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
