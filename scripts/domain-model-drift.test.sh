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

# --- Test 1: base-migration constraint + policy extraction -----------------
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
# Private TMPDIR so the extract-mode (MAIN SHELL) spool files are attributable: this is
# the `exit 3` secret-refuse return path, where the spools are allocated but never written.
t5_tmp="$(mktemp -d)"
TMPDIR="$t5_tmp" bash "$DRIFT" extract --repo "$t5_repo" >/dev/null 2>&1
rc5=$?
[[ "$rc5" -ne 0 ]] && pass || fail "T5: secret-shaped literal did not trigger fail-closed refuse (exit=$rc5)"
# Spool residue on the exit-3 path, EXTRACT mode (emit_extract_json runs in the main shell).
t5_residue="$(find "$t5_tmp" -mindepth 1 | wc -l)"
[[ "$t5_residue" -eq 0 ]] && pass || fail "T5: extract-mode exit-3 leaked $t5_residue spool file(s)"

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
# Positive control: EXACTLY ONE stale citation — proves the gone symbol was flagged
# AND the live resolveActiveWorkspace citation was parsed-and-cleared (not vacuously
# absent). A parser that never saw BR-1/BR-2 would not report "(1)".
echo "$out9" | grep -qE 'Stale register citations \(1\)' && pass || fail "T9: expected exactly 1 stale citation (positive control)"
echo "$out9" | grep -q "resolveGoneSymbol" && pass || fail "T9: the flagged stale citation is not resolveGoneSymbol"
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

# --- Test 12: write-row appends to ## Auto-inferred, curated table untouched ---
mk_register() {
  local r="$1"
  cat > "$r" <<'MD'
# Register
## Business Rules
| ID | Rule | Statement | Source |
|---|---|---|---|
| BR-1 | Curated | Hand-written. | ADR-1 |

## Auto-inferred (unreviewed)
| Anchor | Candidate statement |
|---|---|
MD
}
# write-row confines --register under --repo, so each call passes --repo = the
# register's own dir (bare mktemp lands in TMPDIR; dirname is that dir).
wr() { local reg="$1"; shift; bash "$DRIFT" write-row --repo "$(dirname "$reg")" --register "$reg" "$@"; }

t12_reg="$(mktemp)"; mk_register "$t12_reg"
before12="$(grep '| BR-1 | Curated' "$t12_reg")"
wr "$t12_reg" --anchor "001.sql › t.pol" --statement "policy pol on t" >/dev/null 2>&1
rc12=$?
[[ "$rc12" -eq 0 ]] && pass || fail "T12: write-row exit=$rc12"
grep -q "001.sql › t.pol" "$t12_reg" && pass || fail "T12: row not appended"
# curated BR-1 row byte-identical (side-effect: curated table untouched)
[[ "$(grep '| BR-1 | Curated' "$t12_reg")" == "$before12" ]] && pass || fail "T12: curated row mutated"
# row landed under Auto-inferred, not Business Rules
awk '/## Auto-inferred/{f=1} f && /001.sql/{print "OK"; exit}' "$t12_reg" | grep -q OK && pass || fail "T12: row not under Auto-inferred heading"

# --- Test 13: markdown-injection safe — exercise the REAL neutralization branch ---
# (a) field-LEADING forged curated ID in the ANCHOR (column 1, where BR-NNN lives)
t13a_reg="$(mktemp)"; mk_register "$t13a_reg"
wr "$t13a_reg" --anchor 'BR-042' --statement "forged id attempt" >/dev/null 2>&1
# Assert the SECURITY INVARIANT (no structural injection + content preserved), NOT the
# exact escape bytes — the escape form (`\#\#` vs `\\#\\#`, `\|` vs `\\|`) varies by bash
# version, so byte-exact assertions are non-portable (they passed locally, failed CI GNU grep).
grep -qE '^\| BR-042 ' "$t13a_reg" && fail "T13a: forged BR- id rendered as a structural curated-looking row" || pass
grep -qF 'forged id attempt' "$t13a_reg" && pass || fail "T13a: statement content lost (write-row failed?)"
# (b) leading ## in the STATEMENT must NOT render as a markdown heading; content preserved
t13b_reg="$(mktemp)"; mk_register "$t13b_reg"
wr "$t13b_reg" --anchor "a › b" --statement '## injected heading' >/dev/null 2>&1
grep -qE '^#{1,}[[:space:]]+injected' "$t13b_reg" && fail "T13b: leading ## rendered as a real heading" || pass
grep -qF 'injected heading' "$t13b_reg" && pass || fail "T13b: statement content lost"
# (c) a pipe in the STATEMENT must not corrupt the curated table; content preserved
t13c_reg="$(mktemp)"; mk_register "$t13c_reg"
before13c="$(grep '| BR-1 | Curated' "$t13c_reg")"
wr "$t13c_reg" --anchor "a › b" --statement 'left | right' >/dev/null 2>&1
[[ "$(grep '| BR-1 | Curated' "$t13c_reg")" == "$before13c" ]] && pass || fail "T13c: curated row corrupted by pipe"
grep -qF 'left' "$t13c_reg" && grep -qF 'right' "$t13c_reg" && pass || fail "T13c: statement content lost"

# --- Test 14: content-anchor dedup — same anchor not re-proposed ---
t14_reg="$(mktemp)"; mk_register "$t14_reg"
wr "$t14_reg" --anchor "x › y.z" --statement "first" >/dev/null 2>&1
wr "$t14_reg" --anchor "x › y.z" --statement "second" >/dev/null 2>&1
n14="$(grep -c 'x › y.z' "$t14_reg")"
[[ "$n14" -eq 1 ]] && pass || fail "T14: anchor duplicated ($n14 rows)"

# --- Test 15: TOCTOU — missing Auto-inferred heading aborts (register unchanged) ---
t15_reg="$(mktemp)"; printf '# Register\n## Business Rules\n| ID | Rule |\n|---|---|\n| BR-1 | x |\n' > "$t15_reg"
before15="$(cat "$t15_reg")"
wr "$t15_reg" --anchor "a › b" --statement "s" >/dev/null 2>&1
rc15=$?
[[ "$rc15" -ne 0 ]] && pass || fail "T15: missing heading should abort"
[[ "$(cat "$t15_reg")" == "$before15" ]] && pass || fail "T15: register mutated despite abort"

# --- Test 16: write-row fail-closed on secret-shaped statement (+ register unchanged) ---
t16_reg="$(mktemp)"; mk_register "$t16_reg"
before16="$(cat "$t16_reg")"
wr "$t16_reg" --anchor "a › b" --statement "token sk-ant-$(printf api03)-XXXX" >/dev/null 2>&1
rc16=$?
[[ "$rc16" -eq 3 ]] && pass || fail "T16: secret statement exit=$rc16 (want 3)"
[[ "$(cat "$t16_reg")" == "$before16" ]] && pass || fail "T16: register mutated on secret-refuse"

# --- Test 16b: drift path also fail-closes on a secret in a migration predicate ---
t16b_repo="$(mktemp -d)"; t16b_mig="$t16b_repo/apps/web-platform/supabase/migrations"; mkdir -p "$t16b_mig"
printf 'CREATE POLICY leaky ON t FOR SELECT USING (k = %s);\n' "'sk-ant-$(printf api03)-YYYYYYYYYYYYYYYY'" > "$t16b_mig/001.sql"
t16b_reg="$t16b_repo/register.md"; printf '# R\n## Business Rules\n| ID | Rule | Statement | Source |\n|---|---|---|---|\n' > "$t16b_reg"
# Private TMPDIR — DRIFT mode runs emit_extract_json under `$( )`, so this is the
# SUBSHELL half of the residue pair. A function-local trap (or a _TMPFILES append made
# inside the function) would be lost here while T5's main-shell case still passed:
# the two modes together are the only thing that discriminates the Phase 2.2 defect.
t16b_tmp="$(mktemp -d)"
TMPDIR="$t16b_tmp" bash "$DRIFT" drift --repo "$t16b_repo" --register "$t16b_reg" >/dev/null 2>&1
[[ $? -eq 3 ]] && pass || fail "T16b: drift did not fail-closed on secret in migration"
t16b_residue="$(find "$t16b_tmp" -mindepth 1 | wc -l)"
[[ "$t16b_residue" -eq 0 ]] && pass || fail "T16b: drift-mode exit-3 leaked $t16b_residue spool file(s) (subshell cleanup path)"

# --- Test 17: drift FAIL-OPEN guard — no migrations dir → exit 2, loud banner ---
t17_repo="$(mktemp -d)"; mkdir -p "$t17_repo/src"; echo "x" > "$t17_repo/src/a.go"
t17_reg="$t17_repo/register.md"; printf '# R\n## Business Rules\n| ID | Rule | Statement | Source |\n|---|---|---|---|\n' > "$t17_reg"
out17="$(bash "$DRIFT" drift --repo "$t17_repo" --register "$t17_reg" 2>/dev/null)"; rc17=$?
[[ "$rc17" -eq 2 ]] && pass || fail "T17: unsupported-stack drift exit=$rc17 (want 2, not a false-clean 0)"
echo "$out17" | grep -qi "Source not analyzable" && pass || fail "T17: fail-open banner missing"

# --- Test 18: fail-safe-to-blind — quoted policy name + \$tag\$ SECURITY DEFINER ---
t18_repo="$(mktemp -d)"; t18_mig="$t18_repo/apps/web-platform/supabase/migrations"; mkdir -p "$t18_mig"
cat > "$t18_mig/001.sql" <<'SQL'
CREATE POLICY "Users can view own profile" ON profiles FOR SELECT USING (auth.uid() = id);
CREATE FUNCTION guard_fn(p uuid) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER AS $function$ BEGIN RETURN true; END; $function$;
SQL
out18="$(bash "$DRIFT" extract --repo "$t18_repo" 2>/dev/null)"
# quoted multi-word policy name is EITHER extracted OR disclosed as a blind_spot — never silently gone
echo "$out18" | jq -e '([.facts[]|select(.kind=="policy")]|length) + ([.blind_spots[]|select(.detail|contains("POLICY"))]|length) >= 1' >/dev/null 2>&1 && pass || fail "T18: quoted policy name silently dropped (neither fact nor blind_spot)"
# $function$-bodied SECURITY DEFINER guard is captured (not hidden by the dollar-tag body)
echo "$out18" | jq -e '[.facts[]|select(.kind=="guard" and .object=="guard_fn")]|length == 1' >/dev/null 2>&1 && pass || fail "T18: \$function\$ SECURITY DEFINER guard missed"

# --- Test 19: schema-qualified table tokens strip the `public.` default schema (#5871) ---
# The `public.` default-schema qualifier must be stripped from table + derived-object
# anchors (ADR-076 item 3: anchors are `<table>.<object>`), while NON-default schemas
# (storage., auth.) that the register cites verbatim are PRESERVED.
t19_repo="$(mktemp -d)"; t19_mig="$t19_repo/apps/web-platform/supabase/migrations"; mkdir -p "$t19_mig"
cat > "$t19_mig/001.sql" <<'SQL'
CREATE TABLE public.bar (
  id uuid PRIMARY KEY,
  n int CHECK (n > 0)
);
CREATE POLICY bar_sel ON public.bar FOR SELECT USING (true);
CREATE POLICY obj_sel ON storage.objects FOR SELECT USING (true);
SQL
out19="$(bash "$DRIFT" extract --repo "$t19_repo" 2>/dev/null)"
# (a) no anchor retains the `public.` default-schema qualifier (table OR derived object)
echo "$out19" | jq -e 'all(.facts[]; (.anchor | contains("public.")) | not)' >/dev/null 2>&1 && pass || fail "T19a: public. schema qualifier not stripped from anchors"
# (b) the derived pkey object name is also clean (not public.bar.public.bar_pkey)
echo "$out19" | jq -e '[.facts[] | select(.anchor | contains("› bar.bar_pkey"))] | length == 1' >/dev/null 2>&1 && pass || fail "T19b: derived pkey object still schema-qualified"
# (c) non-default schema (storage.) is PRESERVED
echo "$out19" | jq -e '[.facts[] | select(.anchor | contains("storage.objects"))] | length >= 1' >/dev/null 2>&1 && pass || fail "T19c: storage. schema wrongly stripped"

# --- Test 20: argv-ceiling regression — facts payload EXCEEDS MAX_ARG_STRLEN (#6720) ---
# The accumulator was bound as ONE jq `--argjson` argument. The kernel caps a SINGLE
# argv argument at MAX_ARG_STRLEN = 131,072 B (NOT ARG_MAX, the 2 MB argv+envp total);
# bisected on this host: 131,071 B passes, 131,072 B fails E2BIG. `--rawfile` moves the
# payload to file I/O, which has no per-argument limit.
#
# ROW COUNT IS NOT THE LOAD-BEARING PARAMETER — BYTES PER FACT IS. 1200 *minimal* rows
# (`policy\tm1\tt1\tp`) measure only 75,782 B: UNDER the ceiling, so that fixture exits 0
# and PASSES ON UNMODIFIED CODE — vacuous. These rows are production-shaped (full
# migration anchor + a real `USING (...)` predicate), which is what carries the bytes.
t20_rows=1200
t20_repo="$(mktemp -d)"; t20_mig="$t20_repo/apps/web-platform/supabase/migrations"; mkdir -p "$t20_mig"
{
  for i in $(seq 1 "$t20_rows"); do
    printf 'CREATE POLICY workspace_records_select_for_active_org_member_%04d ON public.workspace_membership_records_%04d FOR SELECT USING (public.is_active_workspace_member(workspace_membership_records_%04d.workspace_id, auth.uid()) AND workspace_membership_records_%04d.deleted_at IS NULL);\n' "$i" "$i" "$i" "$i"
  done
} > "$t20_mig/20260719000000_bulk_policies.sql"
# minimum-cardinality guard: an empty/short generator would make every assert below vacuous
t20_srclines="$(grep -c '^CREATE POLICY ' "$t20_mig/20260719000000_bulk_policies.sql")"
[[ "$t20_srclines" -eq "$t20_rows" ]] && pass || fail "T20: fixture generator emitted $t20_srclines rows (want $t20_rows) — asserts below would be vacuous"

t20_tmp="$(mktemp -d)"
out20="$(TMPDIR="$t20_tmp" bash "$DRIFT" extract --repo "$t20_repo" 2>/dev/null)"
rc20=$?
[[ "$rc20" -eq 0 ]] && pass || fail "T20: >ceiling extract exit=$rc20 (want 0; pre-fix this dies 'Argument list too long')"

# FIXTURE ADEQUACY, asserted IN-SUITE so this test cannot silently degrade to vacuous as
# the fixture, the extractor's field set, or jq's encoding changes. A PR-body demonstration
# is unrunnable post-merge — there is no pre-fix code left to run against.
t20_fj_bytes="$(printf '%s' "$out20" | jq -c '.facts' | wc -c)"
[[ "$t20_fj_bytes" -gt 131072 ]] && pass || fail "T20: fixture is only ${t20_fj_bytes} B — below MAX_ARG_STRLEN (131072), this test proves nothing"

# EXACT count, asserted RELATIONALLY against the source row count — not a literal pin.
# This is fully discriminating against the --slurpfile array-of-arrays undercount, which
# would yield 1, and it stays correct as the fixture grows.
t20_facts="$(printf '%s' "$out20" | jq '.facts | length')"
[[ "$t20_facts" -eq "$t20_srclines" ]] && pass || fail "T20: .facts|length=$t20_facts != source row count $t20_srclines (undercount / truncation)"
# the payload really is policy facts carrying predicates, not empty shells
printf '%s' "$out20" | jq -e --argjson n "$t20_rows" '[.facts[] | select(.kind=="policy" and (.predicate | contains("is_active_workspace_member")))] | length == $n' >/dev/null 2>&1 && pass || fail "T20: policy predicates not preserved at >ceiling size"
# success path leaves no spool residue either (T5/T16b cover the exit-3 paths)
t20_residue="$(find "$t20_tmp" -mindepth 1 | wc -l)"
[[ "$t20_residue" -eq 0 ]] && pass || fail "T20: successful extract leaked $t20_residue spool file(s)"

echo "domain-model-drift.test.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
