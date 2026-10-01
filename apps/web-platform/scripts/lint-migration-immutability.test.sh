#!/usr/bin/env bash
# shellcheck disable=SC2016  # workflow-wiring greps match literal source
# text ('bash "$GUARD_COPY" ...'); expansion is exactly what we do NOT want
# Tests for lint-migration-immutability.sh (issue 8583 — the third leg of
# migration hygiene: on-main supabase/migrations files are immutable).
#
# Drives the guard over a SYNTHESIZED fixture repo (mktemp + git init —
# cq-test-fixtures-synthesized-only; the live tree's git state is never
# reused) covering the plan's mutation matrix plus review-hardening arms:
#
#    1  modify an on-main migration (the #8507 shape)        -> rc 1, names file
#    2  delete an on-main migration                          -> rc 1
#    3  git mv an on-main migration (rename-detection evade) -> rc 1 (--no-renames)
#    4  add-collides: branch adds a path main gained post-divergence -> rc 1
#    5  diff touches migrations -> summary reports counted shape (audible)
#    6  stubbed oracle (ls-tree empty rc0)  -> rc 1 (broken oracle REDs)
#    7  add NNN beyond max-on-main                           -> rc 0 + checked=0 notice
#    8  modify an on-main *.down.sql                         -> rc 0 (exempt)
#    9  bogus --base                                          -> rc 2 (fail closed)
#   10 wiring: the step's RUN lines invoke the guard (anchor alone no-op)
#   11 anti-self-neuter: step executes the BASE-ref copy via git show
#   12 non-migration diff                                    -> rc 0, no notice
#   13 low-numbered new file (absent on base, not "beyond max")-> rc 0
#   14 stubbed oracle (ls-tree rc!=0)                        -> rc 2 (fail closed)
#   15 --from-pr-diff end-to-end via a file:// origin remote   -> rc 1 names file
#   16 --repo at a non-repo dir                              -> rc 2
#   17 dangling value-flag (--base last arg)                 -> rc 2, no hang
#   18 mode-only change (chmod) on an on-main file           -> rc 1
#   19 NEW symlink at a migration path                       -> rc 1 (E6 channel)
#   20 --from-pr-diff combined with --base                   -> rc 2 (rejected)
#
# Vacuity floor (tasks.md): CASES increments at each call site (never
# inside a verdict helper or command substitution) and the suite refuses
# green below the expected count — a deleted test block cannot pass.
#
# Run: bash apps/web-platform/scripts/lint-migration-immutability.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/lint-migration-immutability.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

if [[ ! -f "$GUARD" ]]; then
  echo "ERROR: $GUARD not found" >&2
  exit 1
fi

PASS=0
FAIL=0
CASES=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

FIX="$tmp/fixture"
mkdir -p "$FIX/apps/web-platform/supabase/migrations"
git -C "$FIX" init -q -b main
git -C "$FIX" config user.email "fixture@example.invalid"
git -C "$FIX" config user.name "Fixture"
git -C "$FIX" config commit.gpgsign false

cat > "$FIX/apps/web-platform/supabase/migrations/001_a.sql" <<'SQL'
CREATE TABLE public.fixture_a (id uuid PRIMARY KEY);
SQL
cat > "$FIX/apps/web-platform/supabase/migrations/002_b.sql" <<'SQL'
CREATE TABLE public.fixture_b (id uuid PRIMARY KEY);
SQL
cat > "$FIX/apps/web-platform/supabase/migrations/003_b.down.sql" <<'SQL'
DROP TABLE public.fixture_b;
SQL
git -C "$FIX" add -A
git -C "$FIX" commit -qm 'base migrations'

run_guard() {
  set +e
  out=$(bash "$GUARD" --repo "$FIX" --base main --head feat 2>&1)
  rc=$?
  set -e
}

reset_feat() {
  git -C "$FIX" switch -qC feat main
}

# ----------------------------------------------------------------------
echo "T1: modify an on-main migration -> rc 1, names the file"
CASES=$((CASES + 1))
# ----------------------------------------------------------------------
reset_feat
printf 'ALTER TABLE public.fixture_b ADD COLUMN extra int;\n' >> "$FIX/apps/web-platform/supabase/migrations/002_b.sql"
git -C "$FIX" commit -qam 'mutate 002'
run_guard
if [[ "$rc" == "1" ]] && printf '%s' "$out" | grep -q '002_b.sql' && printf '%s' "$out" | grep -q 'mutated'; then
  pass "rc=1 names the mutated file (mutation verdict pinned)"
else
  fail "expected rc=1 naming 002_b.sql with mutation verdict; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "T2: delete an on-main migration -> rc 1"
CASES=$((CASES + 1))
# ----------------------------------------------------------------------
reset_feat
git -C "$FIX" rm -q apps/web-platform/supabase/migrations/001_a.sql
git -C "$FIX" commit -qm 'delete 001'
run_guard
if [[ "$rc" == "1" ]] && printf '%s' "$out" | grep -q '001_a.sql' && printf '%s' "$out" | grep -q 'deleted or renamed away'; then
  pass "rc=1 names the deleted file (delete verdict pinned)"
else
  fail "expected rc=1 naming 001_a.sql with delete verdict; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "T3: git mv on an on-main migration -> rc 1 (rename detection cannot hide the source)"
CASES=$((CASES + 1))
# ----------------------------------------------------------------------
reset_feat
git -C "$FIX" mv apps/web-platform/supabase/migrations/001_a.sql apps/web-platform/supabase/migrations/010_a.sql
git -C "$FIX" commit -qm 'rename 001 -> 010'
# Pin the precondition this case exists to exploit: under DEFAULT rename
# detection the source path is not even emitted — if a host disables
# rename detection the pin fails loudly instead of silently weakening.
default_enum=$(git -C "$FIX" diff --name-only main...feat -- 'apps/web-platform/supabase/migrations/*.sql')
if printf '%s' "$default_enum" | grep -q '001_a\.sql'; then
  fail "precondition broken: default rename detection still emits the source — T3 cannot distinguish --no-renames"
else
  run_guard
  if [[ "$rc" == "1" ]] && printf '%s' "$out" | grep -q '001_a.sql'; then
    pass "rc=1 names the rename SOURCE (--no-renames is load-bearing)"
  else
    fail "expected rc=1 naming 001_a.sql; got rc=$rc out=$out"
  fi
fi

# ----------------------------------------------------------------------
echo "T4: add-collides — branch adds a path main gained after divergence -> rc 1"
CASES=$((CASES + 1))
# ----------------------------------------------------------------------
reset_feat
# main gains 009_late.sql while feat diverges with its own 009_late.sql.
pre_div=$(git -C "$FIX" rev-parse main)
git -C "$FIX" switch -q main
cat > "$FIX/apps/web-platform/supabase/migrations/009_late.sql" <<'SQL'
CREATE TABLE public.late_main (id uuid PRIMARY KEY);
SQL
git -C "$FIX" add -A && git -C "$FIX" commit -qm 'main adds 009_late'
git -C "$FIX" switch -q feat
# feat branched before main's 009_late commit: rewrite feat off the OLD main.
git -C "$FIX" reset -q --hard "$pre_div"
cat > "$FIX/apps/web-platform/supabase/migrations/009_late.sql" <<'SQL'
CREATE TABLE public.late_feat (id uuid PRIMARY KEY, different int);
SQL
git -C "$FIX" add -A && git -C "$FIX" commit -qm 'feat adds colliding 009_late'
# Pin the topology: the diff must show A (not M) for the colliding path —
# otherwise this degenerated to a plain-modify arm and the ls-tree-at-tip
# vs ls-tree-at-merge-base distinction is no longer exercised.
if [[ "$(git -C "$FIX" merge-base main feat)" != "$pre_div" ]] \
  || ! git -C "$FIX" diff --name-status main...feat -- 'apps/web-platform/supabase/migrations/*.sql' | grep -q $'^A\t.*009_late'; then
  fail "T4 topology broken: expected A-status add-collides off the pre-divergence base"
else
  run_guard
  if [[ "$rc" == "1" ]] && printf '%s' "$out" | grep -q '009_late.sql'; then
    pass "rc=1 names the colliding path (ls-tree identity, not diff status)"
  else
    fail "expected rc=1 naming 009_late.sql; got rc=$rc out=$out"
  fi
fi
# restore fixture main/feat relationship for later cases
git -C "$FIX" switch -q main

# ----------------------------------------------------------------------
echo "T5: diff touches migrations -> summary reports the counted shape"
CASES=$((CASES + 1))
# ----------------------------------------------------------------------
reset_feat
printf 'SELECT 1;\n' >> "$FIX/apps/web-platform/supabase/migrations/002_b.sql"
git -C "$FIX" commit -qam 'touch 002 again'
run_guard
if printf '%s' "$out" | grep -qE 'touched=[1-9]' && printf '%s' "$out" | grep -qE 'on-main-checked=[1-9]'; then
  pass "summary exposes touched>=1 and on-main-checked>=1 (no silent zero-row enumeration)"
else
  fail "expected counted summary with touched/on-main-checked >=1; got out=$out"
fi

# ----------------------------------------------------------------------
echo "T6: stubbed oracle — ls-tree returns empty -> rc 1, not a clean-looking pass"
CASES=$((CASES + 1))
# ----------------------------------------------------------------------
# A git stub whose ls-tree emits nothing makes every touched path look
# 'new' AND makes the new-file arm's head probe empty — which the guard
# treats as "not a regular file" and reds. So a stubbed oracle cannot
# produce a clean-looking pass at all: it goes RED, naming the path.
# (The legitimate checked=0-with-notice shape — a real all-new diff — is
# pinned in T7.)
reset_feat
printf 'SELECT 1;\n' >> "$FIX/apps/web-platform/supabase/migrations/002_b.sql"
git -C "$FIX" commit -qam 'touch 002 for stubbed-oracle arm'
STUB="$tmp/gitstub"
mkdir -p "$STUB"
REAL_GIT="$(command -v git)"
cat > "$STUB/git" <<SH
#!/usr/bin/env bash
for arg in "\$@"; do
  if [[ "\$arg" == "ls-tree" ]]; then exit 0; fi
done
# forward everything else to the real git
exec "$REAL_GIT" "\$@"
SH
chmod +x "$STUB/git"
set +e
out=$(cd "$FIX" && PATH="$STUB:$PATH" bash "$GUARD" --repo "$FIX" --base main --head feat 2>&1)
rc=$?
set -e
if [[ "$rc" == "1" ]] && printf '%s' "$out" | grep -q '002_b.sql' && ! printf '%s' "$out" | grep -q 'migration-immutability: clean'; then
  pass "stubbed oracle goes RED — a broken oracle cannot produce a clean-looking pass"
else
  fail "expected rc=1 (not a clean pass) under stubbed ls-tree; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "T7: add a file numbered beyond max-on-main -> rc 0"
CASES=$((CASES + 1))
# ----------------------------------------------------------------------
reset_feat
cat > "$FIX/apps/web-platform/supabase/migrations/140_new.sql" <<'SQL'
CREATE TABLE public.new_beyond_max (id uuid PRIMARY KEY);
SQL
git -C "$FIX" add -A && git -C "$FIX" commit -qm 'add 140_new'
run_guard
if [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -q 'migration-immutability: clean' \
  && printf '%s' "$out" | grep -q 'on-main-checked=0' \
  && printf '%s' "$out" | grep -q '::notice::lint-migration-immutability: 0 on-main migration files checked'; then
  pass "rc=0 — free iteration; the legitimate checked=0 shape carries the audible notice"
else
  fail "expected rc=0 clean + checked=0 notice; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "T8: modify an on-main *.down.sql -> rc 0 (documented exemption)"
CASES=$((CASES + 1))
# ----------------------------------------------------------------------
reset_feat
printf 'DROP TABLE public.fixture_b;\n' >> "$FIX/apps/web-platform/supabase/migrations/003_b.down.sql"
git -C "$FIX" commit -qam 'edit down file'
run_guard
if [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -q 'down-exempt=1'; then
  pass "rc=0 — down file enumerated AND exempted (not silently unseen)"
else
  fail "expected rc=0 + down-exempt=1 for down.sql edit; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "T9: bogus --base -> rc 2 (fail closed on cannot-measure)"
CASES=$((CASES + 1))
# ----------------------------------------------------------------------
set +e
out=$(bash "$GUARD" --repo "$FIX" --base bogus-ref-does-not-exist --head feat 2>&1)
rc=$?
set -e
if [[ "$rc" == "2" ]] && printf '%s' "$out" | grep -q 'cannot resolve base ref'; then
  pass "rc=2 on unresolvable base ref (error names the failure)"
else
  fail "expected rc=2 + 'cannot resolve base ref'; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "T10: wiring — the step's RUN lines invoke the guard"
CASES=$((CASES + 1))
# ----------------------------------------------------------------------
# Assert the INVOCATION lines themselves, not tokens that survive
# detachment: '--from-pr-diff' also appears on the sibling FK-lint step,
# and the '.sh' literal survives in the GUARD_PATH= assignment even if
# the run lines are deleted. Only greps pinned to bash "$GUARD_*"
# invocations prove the step executes the guard (plan Property 3).
WF="$REPO_ROOT/.github/workflows/tenant-integration.yml"
if grep -qF 'bash "$GUARD_COPY" --from-pr-diff' "$WF" && grep -qF 'bash "$GUARD_PATH" --from-pr-diff' "$WF"; then
  pass "both invocation arms present (base copy + introduction-window fallback)"
else
  fail "tenant-integration.yml does not invoke the guard — detached"
fi

# ----------------------------------------------------------------------
echo "T11: anti-self-neuter — the step executes the BASE-ref copy when it exists"
CASES=$((CASES + 1))
# ----------------------------------------------------------------------
# A PR that weakens this script AND mutates an on-main migration must not
# pass because the step ran the PR's own (neutered) copy. Assert all three
# load-bearing tokens: the git-show extraction, the non-empty guard, and
# the GUARD_COPY execution — extraction without execution is inert.
if grep -qF 'git show "origin/${base_ref}:$GUARD_PATH"' "$WF" \
  && grep -qF '[[ -s "$GUARD_COPY" ]]' "$WF" \
  && grep -qF 'bash "$GUARD_COPY" --from-pr-diff' "$WF"; then
  pass "step extracts AND executes the base-ref copy via git show"
else
  fail "step does not extract+execute the base-ref guard copy — self-neuter bypass is open"
fi

# ----------------------------------------------------------------------
echo "T12: non-migration diff -> rc 0 and NO degenerate notice"
CASES=$((CASES + 1))
# ----------------------------------------------------------------------
reset_feat
printf 'noise\n' > "$FIX/README.md"
git -C "$FIX" add -A && git -C "$FIX" commit -qm 'non-migration change'
run_guard
if [[ "$rc" == "0" ]] && printf '%s' "$out" | grep -q 'touched=0' && ! printf '%s' "$out" | grep -q '::notice::'; then
  pass "rc=0, touched=0, no notice — the dominant no-op shape"
else
  fail "expected rc=0 + touched=0 + no notice; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "T13: low-numbered new file (absent on base) -> rc 0"
CASES=$((CASES + 1))
# ----------------------------------------------------------------------
# The property is presence-on-base, not "number > max" — a low-numbered
# file that never existed on base is equally free to iterate.
reset_feat
cat > "$FIX/apps/web-platform/supabase/migrations/000_low.sql" <<'SQL'
CREATE TABLE public.low_numbered (id uuid PRIMARY KEY);
SQL
git -C "$FIX" add -A && git -C "$FIX" commit -qm 'add 000_low'
run_guard
if [[ "$rc" == "0" ]]; then
  pass "rc=0 — numbering is not the criterion; presence on base is"
else
  fail "expected rc=0 for low-numbered new file; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "T14: stubbed oracle — ls-tree rc!=0 -> rc 2 (oracle failure, not 'absent')"
CASES=$((CASES + 1))
# ----------------------------------------------------------------------
# The distinguishing twin of T6: a FAILING oracle (rc!=0) must fail
# closed at exit 2 — swallowing it would classify on-main files as "new".
reset_feat
printf 'SELECT 1;\n' >> "$FIX/apps/web-platform/supabase/migrations/002_b.sql"
git -C "$FIX" commit -qam 'touch 002 for oracle-failure arm'
STUB2="$tmp/gitstub-fail"
mkdir -p "$STUB2"
cat > "$STUB2/git" <<SH
#!/usr/bin/env bash
for arg in "\$@"; do
  if [[ "\$arg" == "ls-tree" ]]; then exit 1; fi
done
exec "$REAL_GIT" "\$@"
SH
chmod +x "$STUB2/git"
set +e
out=$(cd "$FIX" && PATH="$STUB2:$PATH" bash "$GUARD" --repo "$FIX" --base main --head feat 2>&1)
rc=$?
set -e
if [[ "$rc" == "2" ]] && printf '%s' "$out" | grep -q 'ls-tree failed'; then
  pass "rc=2 + 'ls-tree failed' — oracle error fails closed"
else
  fail "expected rc=2 + ls-tree failure message; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "T15: --from-pr-diff end-to-end via a file:// origin remote -> rc 1"
CASES=$((CASES + 1))
# ----------------------------------------------------------------------
# The mode CI actually runs: BASE_REF defaulting, origin/ prefixing,
# the best-effort fetch, and HEAD-as-head. Build a bare remote so the
# fetch arm executes for real.
BARE="$tmp/origin.git"
git init -q --bare "$BARE"
git -C "$FIX" remote add origin "$BARE"
git -C "$FIX" push -q origin main
git -C "$FIX" fetch -q --no-tags origin
reset_feat
printf 'ALTER TABLE public.fixture_b ADD COLUMN remote_test int;\n' >> "$FIX/apps/web-platform/supabase/migrations/002_b.sql"
git -C "$FIX" commit -qam 'mutate 002 on feat (from-pr-diff arm)'
set +e
out=$(cd "$FIX" && BASE_REF='' bash "$GUARD" --from-pr-diff --repo "$FIX" 2>&1)
rc=$?
set -e
if [[ "$rc" == "1" ]] && printf '%s' "$out" | grep -q '002_b.sql'; then
  pass "--from-pr-diff resolves origin/main, fetches, and names the mutation"
else
  fail "expected rc=1 naming 002_b.sql via --from-pr-diff; got rc=$rc out=$out"
fi
git -C "$FIX" switch -q main

# ----------------------------------------------------------------------
echo "T16: --repo at a dir without the migrations tree -> rc 2"
CASES=$((CASES + 1))
# ----------------------------------------------------------------------
NOROOT="$tmp/not-a-root"
mkdir -p "$NOROOT"
set +e
out=$(bash "$GUARD" --repo "$NOROOT" --base main --head feat 2>&1)
rc=$?
set -e
if [[ "$rc" == "2" ]] && printf '%s' "$out" | grep -q 'does not'; then
  pass "rc=2 — wrong repo root refuses before any diff"
else
  fail "expected rc=2 on non-root --repo; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "T17: dangling value-flag (--base as last arg) -> rc 2, no hang"
CASES=$((CASES + 1))
# ----------------------------------------------------------------------
set +e
out=$(timeout 10 bash "$GUARD" --repo "$FIX" --base 2>&1)
rc=$?
set -e
if [[ "$rc" == "2" ]] && printf '%s' "$out" | grep -q 'requires a value'; then
  pass "rc=2 + diagnostic — a dangling flag errors instead of spinning"
else
  fail "expected rc=2 within 10s; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "T18: mode-only change (chmod) on an on-main migration -> rc 1"
CASES=$((CASES + 1))
# ----------------------------------------------------------------------
reset_feat
chmod +x "$FIX/apps/web-platform/supabase/migrations/002_b.sql"
git -C "$FIX" add -A && git -C "$FIX" commit -qm 'chmod 002'
run_guard
if [[ "$rc" == "1" ]] && printf '%s' "$out" | grep -q '002_b.sql'; then
  pass "rc=1 — mode is part of the identity tuple"
else
  fail "expected rc=1 for mode-only change; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "T19: NEW symlink at a migration path -> rc 1 (unguarded channel)"
CASES=$((CASES + 1))
# ----------------------------------------------------------------------
# A symlink admitted as "new" would let the runner apply target content
# that drifts while the ledgered symlink blob stays identical (E6).
reset_feat
printf 'SELECT 1;\n' > "$FIX/target.sql"
ln -s ../../../../target.sql "$FIX/apps/web-platform/supabase/migrations/150_link.sql"
git -C "$FIX" add -A && git -C "$FIX" commit -qm 'add symlinked migration'
run_guard
if [[ "$rc" == "1" ]] && printf '%s' "$out" | grep -q '150_link.sql'; then
  pass "rc=1 — symlink/gitlink admission refused"
else
  fail "expected rc=1 naming 150_link.sql; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "T20: --from-pr-diff combined with --base -> rc 2 (rejected combo)"
CASES=$((CASES + 1))
# ----------------------------------------------------------------------
set +e
out=$(bash "$GUARD" --repo "$FIX" --from-pr-diff --base main 2>&1)
rc=$?
set -e
if [[ "$rc" == "2" ]] && printf '%s' "$out" | grep -q 'cannot be combined'; then
  pass "rc=2 — mode conflict rejected, not silently overridden"
else
  fail "expected rc=2 on --from-pr-diff + --base; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
# Vacuity floor: a deleted test block or neutered helpers must not yield
# green. Reported via a direct printf/exit — never through fail() — so
# the accounting identity stays non-tautological (guard-vacuity-floor).
# ----------------------------------------------------------------------
echo ""
# The bound sits adjacent to the test — a contiguous simple assignment the
# vacuity-floor mutant builder's backward slice carries (EXPECTED_CASES at
# the top of file would leave the mutant's floor unbound -> CONSTRUCTION).
EXPECTED_CASES=20
if [[ "$CASES" -lt "$EXPECTED_CASES" ]]; then
  printf 'FATAL: only %s of %s cases ran — suite is truncated\n' "$CASES" "$EXPECTED_CASES" >&2
  exit 1
fi
echo "lint-migration-immutability.test.sh: $PASS passed, $FAIL failed ($CASES cases)"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
exit 0
