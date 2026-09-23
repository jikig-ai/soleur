#!/usr/bin/env bash
# shellcheck disable=SC2016  # wiring greps match literal workflow source text
# Tests for dev-ledger-parity.sh (#8521 edited/renamed-after-apply, #8520 the
# in-flight arm of the authoritative drift probe).
#
# Two guards, one script (plan: 2026-09-23-fix-pr-ci-unmerged-migration-ledger-parity-plan.md,
# §Guard Contract — row numbers below are that table's):
#
#   Guard 1  `check`            PR-side per-ref ledger parity (A1 edited, A2 renamed,
#                                A4 deleted-after-apply) + its tenant-integration wiring.
#   Guard 2  `classify-missing` main-side ownership of missing-on-main ledger rows
#                                (in-flight / stale / orphan) + the drift-probe action.
#
# Everything is SYNTHESIZED (cq-test-fixtures-synthesized-only): a bare `origin`
# reached through a file:// URL with uploadpack.allowFilter=true (as GitHub), a
# main history that renames one migration, feature branches pushed to origin, a
# work clone, and a fake `psql` / `doppler` on PATH. The suite runs a COPY of
# the guard ($DLP_GUARD overrides the source) so mutation rows never touch the
# tracked file.
#
# Only rc=1 counts as a caught violation; rc=2 counts only where a row expects
# it. Probe-logic rows execute the `probe` step EXTRACTED from action.yml under
# the composite runner's own shell flags — a grep of action.yml cannot see a
# logic change.
#
# Run: bash apps/web-platform/scripts/dev-ledger-parity.test.sh

set -euo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
GUARD_SRC="${DLP_GUARD:-$SCRIPT_DIR/dev-ledger-parity.sh}"
WF="$REPO_ROOT/.github/workflows/tenant-integration.yml"
ACTION="$REPO_ROOT/.github/actions/dev-migration-drift-probe/action.yml"

if [[ ! -f "$GUARD_SRC" ]]; then
  printf 'FATAL: guard not found at %s — the suite refuses to report 0 passed, 0 failed\n' "$GUARD_SRC" >&2
  exit 1
fi

PASS=0
FAIL=0
CASES=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }

# Instrument self-test: both verdict helpers must move their counters, or every
# verdict below is unobservable. Reported via printf + exit, never via fail().
pass "instrument self-test (pass arm)" >/dev/null
fail "instrument self-test (fail arm)" >/dev/null
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then
  printf 'FATAL: verdict helpers do not count (PASS=%s FAIL=%s)\n' "$PASS" "$FAIL" >&2
  exit 1
fi
PASS=0
FAIL=0

# Strip every inherited GIT_* variable (a GIT_DIR from a hook would retarget
# every fixture command at the caller's repository), then isolate from the
# operator's git config (signing, hooks, url rewrites).
while IFS= read -r v; do
  case "$v" in GIT_*) unset "$v" ;; esac
done < <(compgen -e)
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.invalid

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
case "$tmp" in /*) : ;; *) printf 'FATAL: mktemp returned a relative path\n' >&2; exit 1 ;; esac

GUARD="$tmp/guard.sh"
cp "$GUARD_SRC" "$GUARD"

MDIR="apps/web-platform/supabase/migrations"

# ---------- fake binaries ----------
BIN="$tmp/bin"
mkdir -p "$BIN"
cat > "$BIN/psql" <<'SH'
#!/usr/bin/env bash
# Fake psql: logs argv NUL-delimited, then emits the scripted ledger.
if [[ -n "${DLP_PSQL_LOG:-}" ]]; then
  { printf 'CALL\0'; for a in "$@"; do printf '%s\0' "$a"; done; } >> "$DLP_PSQL_LOG"
fi
rc="${DLP_FAKE_PSQL_RC:-0}"
if [[ "$rc" != "0" ]]; then echo "psql: fake failure" >&2; exit "$rc"; fi
if [[ -n "${DLP_FAKE_LEDGER:-}" && -f "$DLP_FAKE_LEDGER" ]]; then cat "$DLP_FAKE_LEDGER"; fi
exit 0
SH
cat > "$BIN/doppler" <<'SH'
#!/usr/bin/env bash
# Fake doppler: drop `run -p … -c … --`, exec the rest.
while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
shift
exec "$@"
SH
chmod +x "$BIN/psql" "$BIN/doppler"
export PATH="$BIN:$PATH"

blob_of() { printf '%s\n' "$1" | git hash-object --stdin; }

# ---------- origin + main history ----------
ORIGIN="$tmp/origin.git"
git init -q --bare -b main "$ORIGIN"
git -C "$ORIGIN" config uploadpack.allowFilter true
ORIGIN_URL="file://$ORIGIN"

SEED="$tmp/seed"
git clone -q "$ORIGIN_URL" "$SEED" 2>/dev/null
git -C "$SEED" config commit.gpgsign false
mkdir -p "$SEED/$MDIR"
put() { printf '%s\n' "$3" > "$1/$MDIR/$2"; }

git -C "$SEED" switch -q -c main
put "$SEED" 001_a.sql "A"
put "$SEED" 002_b.sql "B"
put "$SEED" 002_b.down.sql "B-down"
put "$SEED" 128_x.sql "X"
git -C "$SEED" add -A && git -C "$SEED" commit -qm 'c1 base'
C1=$(git -C "$SEED" rev-parse HEAD)
git -C "$SEED" mv "$MDIR/128_x.sql" "$MDIR/131_x.sql"
git -C "$SEED" commit -qm 'c2 main renames 128_x -> 131_x'
put "$SEED" 130_y.sql "Y"
git -C "$SEED" add -A && git -C "$SEED" commit -qm 'c3 add 130_y'
put "$SEED" 180_anc.sql "ANC"
git -C "$SEED" add -A && git -C "$SEED" commit -qm 'c4 add 180_anc'
C4=$(git -C "$SEED" rev-parse HEAD)
git -C "$SEED" rm -q "$MDIR/180_anc.sql"
git -C "$SEED" commit -qm 'c5 drop 180_anc'
git -C "$SEED" push -q origin main

# branch helper: branch <name> <from> [<commit-date>] then files as name=content
branch() {
  local name="$1" from="$2" date="$3"; shift 3
  git -C "$SEED" switch -q -C "$name" "$from"
  local kv
  for kv in "$@"; do put "$SEED" "${kv%%=*}" "${kv#*=}"; done
  git -C "$SEED" add -A
  if [[ -n "$date" ]]; then
    GIT_COMMITTER_DATE="$date" GIT_AUTHOR_DATE="$date" git -C "$SEED" commit -qm "branch $name"
  else
    git -C "$SEED" commit -qm "branch $name"
  fi
  git -C "$SEED" push -q -f origin "HEAD:refs/heads/$name"
  git -C "$SEED" switch -q main
}

OLD_DATE="@$(( $(date +%s) - 31 * 86400 - 3600 )) +0000"
branch stale-fork "$C1" "" 140_sf.sql="SF"
branch inflight-a main "" 150_inflight.sql="IF"
branch inflight-renamed main "" 152_renamed_new.sql="RN"
branch inflight-slug main "" 155_sluggy.sql="SLUG-v2"
branch old-branch main "$OLD_DATE" 160_old.sql="OLD"
branch down-only main "" 190_downy.down.sql="DOWNY"
branch 'weird+name' main "" 157_weird.sql="WEIRD"
branch queue-src main "" 170_q.sql="Q"
git -C "$SEED" push -q origin "refs/heads/queue-src:refs/heads/gh-readonly-queue/main/pr-1-abc"
git -C "$SEED" push -q origin --delete queue-src
git -C "$SEED" push -q origin "$C4:refs/heads/merged-anc"

# Work clone == the job's checkout. `feat` is the PR head, pushed per case.
WORK="$tmp/work"
git clone -q "$ORIGIN_URL" "$WORK" 2>/dev/null
git -C "$WORK" config commit.gpgsign false

# Base ledger: main's forward files at main's blobs (the floor is > 0 rows).
BASE_LEDGER="001_a.sql|$(blob_of A)
002_b.sql|$(blob_of B)
130_y.sql|$(blob_of Y)
131_x.sql|$(blob_of X)"
LEDGER="$tmp/ledger.txt"
ledger() { { printf '%s\n' "$BASE_LEDGER"; [[ $# -gt 0 ]] && printf '%s\n' "$@"; true; } > "$LEDGER"; }

# feat_case <files...> — reset feat to main, add files (name=content), push.
feat_case() {
  git -C "$WORK" fetch -q origin
  git -C "$WORK" switch -q -C feat origin/main
  local kv
  for kv in "$@"; do put "$WORK" "${kv%%=*}" "${kv#*=}"; done
  git -C "$WORK" add -A
  git -C "$WORK" commit -q --allow-empty -m 'feat case'
  git -C "$WORK" push -q -f origin feat
}

# run_check [extra args...] — Guard 1 against WORK. Sets out, rc.
run_check() {
  set +e
  out=$(DATABASE_URL_POOLER="postgres://pooler.fixture.invalid/db" DATABASE_URL="" \
    DLP_FAKE_LEDGER="$LEDGER" bash "$GUARD" check --base origin/main --repo "$WORK" "$@" 2>&1)
  rc=$?
  set -e
}
run_check_g() {  # same, against an explicit guard file ($1)
  local g="$1"; shift
  set +e
  out=$(DATABASE_URL_POOLER="postgres://pooler.fixture.invalid/db" DATABASE_URL="" \
    DLP_FAKE_LEDGER="$LEDGER" bash "$g" check --base origin/main --repo "$WORK" "$@" 2>&1)
  rc=$?
  set -e
}
has() { printf '%s' "$out" | grep -qF -- "$1"; }

poison_origin() { git -C "$WORK" remote set-url origin "file://$tmp/does-not-exist.git"; }
heal_origin() { git -C "$WORK" remote set-url origin "$ORIGIN_URL"; }

# AC7 snapshot: the checkout's git config and shallow state must never change.
git_state() { { cat "$WORK/.git/config"; printf -- '--shallow--\n'; cat "$WORK/.git/shallow" 2>/dev/null || true; } | git hash-object --stdin; }

echo "== Guard 1: check =="

# ----------------------------------------------------------------------
echo "G1-1: unmerged F ledgered at a different blob -> rc 1, names F and both SHAs"
CASES=$((CASES + 1))
feat_case 140_x.sql="X140-v2"
ledger "140_x.sql|$(blob_of X140-v1)"
STATE0=$(git_state)
run_check --head-branch feat
if [[ "$rc" == "1" ]] && has "140_x.sql" && has "$(blob_of X140-v1)" && has "$(blob_of X140-v2)" && has "ledger-parity: RED"; then
  pass "A1 names the file, the applied blob and the tree blob"
else
  fail "expected rc=1 A1 naming 140_x.sql + both blobs; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-2: two unmerged files, only the second mismatched -> names F2 only"
CASES=$((CASES + 1))
feat_case 141_f1.sql="F1" 142_f2.sql="F2-v2"
ledger "141_f1.sql|$(blob_of F1)" "142_f2.sql|$(blob_of F2-v1)"
run_check --head-branch feat
if [[ "$rc" == "1" ]] && has "142_f2.sql" && ! printf '%s' "$out" | grep -q '::error::141_f1.sql' && has "ledgered-match=1"; then
  pass "second member caught, first member matched"
else
  fail "expected rc=1 naming only 142_f2.sql, ledgered-match=1; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-3: renamed after apply (same blob, different slug) -> rc 1 A2 blob"
CASES=$((CASES + 1))
feat_case 143_new.sql="R3"
ledger "143_old.sql|$(blob_of R3)"
run_check --head-branch feat
if [[ "$rc" == "1" ]] && has "143_old.sql" && has "143_new.sql" && has "by blob"; then
  pass "A2 blob names the orphan-to-be and the renamed file"
else
  fail "expected rc=1 A2 by blob; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-3b: another fresh branch holds G only by blob -> still rc 1 (exact-name ownership only)"
CASES=$((CASES + 1))
branch other-3b main "" 144_elsewhere.sql="R3"
run_check --head-branch feat
if [[ "$rc" == "1" ]] && has "by blob"; then
  pass "blob-only holding on another branch does not excuse the PR"
else
  fail "expected rc=1; got rc=$rc out=$out"
fi
git -C "$SEED" push -q origin --delete other-3b

# ----------------------------------------------------------------------
echo "G1-4: different blob, same slug -> rc 1 A2 slug"
CASES=$((CASES + 1))
feat_case 145_slugme.sql="S-v2"
ledger "144_slugme.sql|$(blob_of S-v1)"
run_check --head-branch feat
if [[ "$rc" == "1" ]] && has "144_slugme.sql" && has "by slug" && has "re-slug yours"; then
  pass "A2 slug with the re-slug hint"
else
  fail "expected rc=1 A2 by slug + re-slug hint; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-4b: PR history carried G@S then deleted it -> rc 1 A4"
CASES=$((CASES + 1))
feat_case 146_del.sql="DEL"
git -C "$WORK" rm -q "$MDIR/146_del.sql"
git -C "$WORK" commit -qm 'drop 146_del'
git -C "$WORK" push -q -f origin feat
ledger "146_del.sql|$(blob_of DEL)"
run_check --head-branch feat
if [[ "$rc" == "1" ]] && has "146_del.sql" && has "by history"; then
  pass "A4 delete-after-apply caught from the PR branch's history"
else
  fail "expected rc=1 A4 by history; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-5: ledger row with an empty content_sha -> rc 1, own message"
CASES=$((CASES + 1))
feat_case 147_e.sql="E"
ledger "147_e.sql|"
run_check --head-branch feat
if [[ "$rc" == "1" ]] && has "147_e.sql" && has "carries no verifiable content_sha" && ! has "git show  "; then
  pass "empty sha is named, never interpolated into a bare git show"
else
  fail "expected rc=1 empty-sha message; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-5b: uppercase / short content_sha -> rc 1 (treated as absent)"
CASES=$((CASES + 1))
upper=$(blob_of E | tr 'a-f' 'A-F')
ledger "147_e.sql|$upper"
run_check --head-branch feat
rc_upper=$rc; out_upper=$out
ledger "147_e.sql|$(blob_of E | cut -c1-12)"
run_check --head-branch feat
if [[ "$rc_upper" == "1" && "$rc" == "1" ]] && has "carries no verifiable content_sha" \
  && printf '%s' "$out_upper" | grep -qF "carries no verifiable content_sha"; then
  pass "uppercase and short SHAs are not verifiable"
else
  fail "expected rc=1 for both; got upper=$rc_upper short=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-6: psql exits 2 -> rc 2, transient"
CASES=$((CASES + 1))
feat_case 148_ok.sql="OK"
ledger
set +e
out=$(DLP_FAKE_PSQL_RC=2 DATABASE_URL_POOLER="postgres://p" DLP_FAKE_LEDGER="$LEDGER" \
  bash "$GUARD" check --base origin/main --repo "$WORK" --head-branch feat 2>&1)
rc=$?
set -e
if [[ "$rc" == "2" ]] && has "not caused by this PR; re-run the job"; then
  pass "psql failure is a transient cannot-measure"
else
  fail "expected rc=2 transient; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-7: zero ledger rows -> rc 2 config, with and without unmerged files"
CASES=$((CASES + 1))
: > "$LEDGER"
run_check --head-branch feat
rc_u=$rc; out_u=$out
git -C "$WORK" switch -q -C feat origin/main
run_check
if [[ "$rc_u" == "2" && "$rc" == "2" ]] && has "a re-run will not help" \
  && printf '%s' "$out_u" | grep -qF "a re-run will not help"; then
  pass "empty ledger fails closed even when there is nothing to compare"
else
  fail "expected rc=2 config twice; got U=$rc_u empty=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-8: no DATABASE_URL_POOLER and no DATABASE_URL -> rc 2 config"
CASES=$((CASES + 1))
ledger
set +e
out=$(env -u DATABASE_URL_POOLER -u DATABASE_URL DLP_FAKE_LEDGER="$LEDGER" \
  bash "$GUARD" check --base origin/main --repo "$WORK" 2>&1)
rc=$?
set -e
if [[ "$rc" == "2" ]] && has "a re-run will not help"; then
  pass "missing DB URL is config, not a violation"
else
  fail "expected rc=2 config; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-9: --base does not resolve -> rc 2"
CASES=$((CASES + 1))
set +e
out=$(DATABASE_URL_POOLER="postgres://p" DLP_FAKE_LEDGER="$LEDGER" \
  bash "$GUARD" check --base origin/nope --repo "$WORK" 2>&1)
rc=$?
set -e
if [[ "$rc" == "2" ]] && has "origin/nope"; then
  pass "unresolvable base fails closed"
else
  fail "expected rc=2; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-9b: --repo missing / not a repo root -> rc 2"
CASES=$((CASES + 1))
set +e
out1=$(DATABASE_URL_POOLER="postgres://p" bash "$GUARD" check --base origin/main 2>&1); rc1=$?
mkdir -p "$tmp/not-a-root"
out=$(DATABASE_URL_POOLER="postgres://p" bash "$GUARD" check --base origin/main --repo "$tmp/not-a-root" 2>&1); rc=$?
out3=$(timeout 10 bash "$GUARD" check --repo 2>&1); rc3=$?
set -e
if [[ "$rc1" == "2" && "$rc" == "2" && "$rc3" == "2" ]] && has "migrations" && printf '%s' "$out3" | grep -q 'requires a value'; then
  pass "missing --repo, wrong root and a dangling flag all fail closed"
else
  fail "expected rc=2 x3; got $rc1/$rc/$rc3 out=$out1 | $out | $out3"
fi

# ----------------------------------------------------------------------
echo "G1-10: a candidate needs ownership and origin is unreachable -> rc 2 transient"
CASES=$((CASES + 1))
feat_case 143_new.sql="R3"
ledger "143_old.sql|$(blob_of R3)"
poison_origin
run_check --head-branch feat
heal_origin
if [[ "$rc" == "2" ]] && has "re-run the job"; then
  pass "owner fetch failure is transient, not a pass and not a violation"
else
  fail "expected rc=2 transient; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-11: run from \$REPO/apps/web-platform (the #8606 cwd class) -> still rc 1"
CASES=$((CASES + 1))
feat_case 140_x.sql="X140-v2"
ledger "140_x.sql|$(blob_of X140-v1)"
set +e
out=$(cd "$WORK/apps/web-platform" && DATABASE_URL_POOLER="postgres://p" DLP_FAKE_LEDGER="$LEDGER" \
  bash "$GUARD" check --base origin/main --repo "$WORK" --head-branch feat 2>&1)
rc=$?
set -e
if [[ "$rc" == "1" ]] && has "140_x.sql"; then
  pass "cwd-independent"
else
  fail "expected rc=1 from the app subdirectory; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-12: the PR's OWN head on origin still holds G by exact name (stale push) -> still rc 1"
CASES=$((CASES + 1))
# The checkout renamed 143_old -> 143_new but origin's feat still carries the
# old name. The PR must never count as "another live branch" that owns G.
feat_case 143_old.sql="R3"
git -C "$WORK" mv "$MDIR/143_old.sql" "$MDIR/143_new.sql"
git -C "$WORK" commit -qm 'rename, not pushed'
ledger "143_old.sql|$(blob_of R3)"
run_check --head-branch feat
if [[ "$rc" == "1" ]] && has "by blob" && ! has "::notice::"; then
  pass "the PR's own branch is excluded from ownership"
else
  fail "expected rc=1 with no ownership notice; got rc=$rc out=$out"
fi

echo "== Guard 1: must-PASS =="

# ----------------------------------------------------------------------
echo "G1-a: unmerged F ledgered at its own blob -> rc 0"
CASES=$((CASES + 1))
feat_case 148_ok.sql="OK"
ledger "148_ok.sql|$(blob_of OK)"
run_check --head-branch feat
if [[ "$rc" == "0" ]] && has "ledger-parity: clean" && has "ledgered-match=1"; then
  pass "matching ledger row is clean"
else
  fail "expected rc=0 ledgered-match=1; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-b: unmerged F with no ledger row -> rc 0 pending=1"
CASES=$((CASES + 1))
ledger
run_check --head-branch feat
if [[ "$rc" == "0" ]] && has "pending=1" && has "unmerged=1"; then
  pass "not-yet-applied is pending, not a violation"
else
  fail "expected rc=0 pending=1; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-c: a MERGED file with a differing ledger blob -> rc 0 (the probe's job, not this PR's)"
CASES=$((CASES + 1))
printf '%s\n' "001_a.sql|$(blob_of A-other)" "002_b.sql|$(blob_of B)" > "$LEDGER"
run_check --head-branch feat
if [[ "$rc" == "0" ]]; then
  pass "merged content drift is not attributed to the PR"
else
  fail "expected rc=0; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-d: unmerged *.down.sql with no row -> rc 0, not counted"
CASES=$((CASES + 1))
feat_case 149_z.down.sql="ZDOWN"
ledger
run_check --head-branch feat
if [[ "$rc" == "0" ]] && has "unmerged=0"; then
  pass "down files are outside the population"
else
  fail "expected rc=0 unmerged=0; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-e: unrelated orphan Z -> rc 0; with no head branch it makes no remote call"
CASES=$((CASES + 1))
feat_case 148_ok.sql="OK"
ledger "199_zz.sql|$(blob_of ZZ)"
poison_origin
run_check
rc_nohead=$rc; out_nohead=$out
heal_origin
run_check --head-branch feat
if [[ "$rc_nohead" == "0" && "$rc" == "0" ]] && has "candidates=1" && ! has "::error::"; then
  pass "unrelated orphan is not this PR's; no-head path stayed offline"
else
  fail "expected rc=0 twice; got nohead=$rc_nohead ($out_nohead) head=$rc ($out)"
fi

# ----------------------------------------------------------------------
echo "G1-f: slug candidate held by EXACT NAME on another fresh branch -> rc 0 + notice"
CASES=$((CASES + 1))
branch other-f main "" 144_slugme.sql="S-v1"
feat_case 145_slugme.sql="S-v2"
ledger "144_slugme.sql|$(blob_of S-v1)"
run_check --head-branch feat
if [[ "$rc" == "0" ]] && has "::notice::" && has "other-f" && has "skipped-owned=1"; then
  pass "another PR's in-flight row is skipped with a notice naming it"
else
  fail "expected rc=0 + notice naming other-f; got rc=$rc out=$out"
fi
git -C "$SEED" push -q origin --delete other-f

# ----------------------------------------------------------------------
echo "G1-g: tree == base -> rc 0, notice, and the floor still read the ledger"
CASES=$((CASES + 1))
git -C "$WORK" switch -q -C feat origin/main
ledger
run_check
if [[ "$rc" == "0" ]] && has "0 unmerged migrations in this tree" && has "ledger-rows=4"; then
  pass "empty population is audible and the ledger was still read"
else
  fail "expected rc=0 + notice + ledger-rows=4; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-h: merged G whose slug equals an unmerged F's slug -> rc 0"
CASES=$((CASES + 1))
feat_case 200_b.sql="B2"
ledger
run_check --head-branch feat
if [[ "$rc" == "0" ]] && has "candidates=0"; then
  pass "merged names are never candidates"
else
  fail "expected rc=0 candidates=0; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-i/j: DB URL precedence — pooler first, DATABASE_URL as fallback"
CASES=$((CASES + 1))
PLOG="$tmp/psql-argv.log"
: > "$PLOG"
set +e
DLP_PSQL_LOG="$PLOG" DATABASE_URL_POOLER="postgres://pooler.i" DATABASE_URL="postgres://direct.i" \
  DLP_FAKE_LEDGER="$LEDGER" bash "$GUARD" check --base origin/main --repo "$WORK" >/dev/null 2>&1
rc_i=$?
argv_i=$(tr '\0' '\n' < "$PLOG")
: > "$PLOG"
DLP_PSQL_LOG="$PLOG" DATABASE_URL="postgres://direct.j" \
  DLP_FAKE_LEDGER="$LEDGER" bash "$GUARD" check --base origin/main --repo "$WORK" >/dev/null 2>&1
rc_j=$?
argv_j=$(tr '\0' '\n' < "$PLOG")
set -e
if [[ "$rc_i" == "0" && "$rc_j" == "0" ]] \
  && grep -qxF 'postgres://pooler.i' <<<"$argv_i" && ! grep -qF 'direct.i' <<<"$argv_i" \
  && grep -qxF 'postgres://direct.j' <<<"$argv_j"; then
  pass "pooler preferred; DATABASE_URL used only when the pooler is unset"
else
  fail "URL precedence wrong: i=$rc_i [$argv_i] j=$rc_j [$argv_j]"
fi

echo "== Guard 1: harness =="

# ----------------------------------------------------------------------
echo "G1-H5: exactly one psql call, one -c, no -f, SQL byte-equal to the literal"
CASES=$((CASES + 1))
: > "$PLOG"
feat_case 148_ok.sql="OK"
ledger "148_ok.sql|$(blob_of OK)"
set +e
DLP_PSQL_LOG="$PLOG" DATABASE_URL_POOLER="postgres://p" DLP_FAKE_LEDGER="$LEDGER" \
  bash "$GUARD" check --base origin/main --repo "$WORK" --head-branch feat >/dev/null 2>&1
set -e
calls=$(tr -cd '\0' < "$PLOG" | wc -c)
mapfile -d '' -t argv < "$PLOG"
ncall=0; nc=0; nf=0; sql=""
for ((i = 0; i < ${#argv[@]}; i++)); do
  case "${argv[$i]}" in
    CALL) ncall=$((ncall + 1)) ;;
    -c) nc=$((nc + 1)); sql="${argv[$((i + 1))]}" ;;
    -f|--file) nf=$((nf + 1)) ;;
  esac
done
want_sql="SELECT filename || '|' || COALESCE(content_sha, '') FROM public._schema_migrations ORDER BY filename"
src_psql=$(grep -cE '^[^#]*\bpsql "\$' "$GUARD_SRC" || true)
if [[ "$calls" -gt 0 && "$ncall" == "1" && "$nc" == "1" && "$nf" == "0" && "$sql" == "$want_sql" && "$src_psql" == "1" ]]; then
  pass "single fixed read-only SELECT through one call site"
else
  fail "psql argv drifted: calls=$ncall -c=$nc -f=$nf sites=$src_psql sql=[$sql]"
fi

# Mutation harness: a guard whose body is replaced must turn a row red.
mutate_body() {  # $1=out file $2=replacement command (inserted after the shebang)
  { head -n 1 "$GUARD"; printf '%s\n' "$2"; tail -n +2 "$GUARD"; } > "$1"
  if cmp -s "$1" "$GUARD"; then printf 'FATAL: mutation did not land in %s\n' "$1" >&2; exit 1; fi
}

# ----------------------------------------------------------------------
echo "G1-H1: guard body replaced by 'exit 0' -> the A1 row goes red"
CASES=$((CASES + 1))
mutate_body "$tmp/m-exit0.sh" 'exit 0'
feat_case 140_x.sql="X140-v2"
ledger "140_x.sql|$(blob_of X140-v1)"
run_check_g "$tmp/m-exit0.sh" --head-branch feat
if [[ "$rc" != "1" ]]; then
  pass "an always-green guard fails row G1-1 (rc=$rc)"
else
  fail "row G1-1 cannot tell a neutered guard from a working one"
fi

# ----------------------------------------------------------------------
echo "G1-H2: guard body replaced by 'exit 1' -> the must-PASS row goes red"
CASES=$((CASES + 1))
mutate_body "$tmp/m-exit1.sh" 'exit 1'
feat_case 148_ok.sql="OK"
ledger "148_ok.sql|$(blob_of OK)"
run_check_g "$tmp/m-exit1.sh" --head-branch feat
if [[ "$rc" != "0" ]]; then
  pass "an always-red guard fails row G1-a (rc=$rc)"
else
  fail "row G1-a cannot tell an always-red guard from a working one"
fi

# ----------------------------------------------------------------------
echo "G1-H4: the suite itself refuses when the guard is absent"
CASES=$((CASES + 1))
set +e
out=$(DLP_GUARD="$tmp/absent-guard.sh" bash "${BASH_SOURCE[0]}" 2>&1)
rc=$?
set -e
if [[ "$rc" != "0" ]] && has "guard not found" && ! printf '%s' "$out" | grep -qE '^dev-ledger-parity\.test\.sh: [0-9]+ passed'; then
  pass "absent guard is RED, never '0 passed, 0 failed'"
else
  fail "suite did not refuse an absent guard: rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-AC7a: check never mutates the checkout's .git/config or shallow state"
CASES=$((CASES + 1))
if [[ "$(git_state)" == "$STATE0" ]]; then
  pass "no promisor config, no shallow entries, no leftover remotes"
else
  fail "the checkout's git state changed during check runs"
fi

echo "== Guard 2: classify-missing =="

# run_classify <stdin text> — sets out (stdout), err (stderr), rc.
run_classify() {
  local ef="$tmp/classify.err"
  set +e
  out=$(printf '%s' "$1" | bash "$GUARD" classify-missing --base-branch main --repo "$WORK" 2>"$ef")
  rc=$?
  set -e
  err=$(cat "$ef")
}
T=$'\t'
STATE1=$(git_state)

# ----------------------------------------------------------------------
echo "G2-1: row on no live branch -> orphan"
CASES=$((CASES + 1))
run_classify "199_gone.sql|$(blob_of GONE)"$'\n'
if [[ "$rc" == "0" && "$out" == "orphan${T}199_gone.sql" ]] && grep -qF 'ledger-classify: in-flight=0 stale=0 orphan=1' <<<"$err"; then
  pass "ownerless row is an orphan, summary on stderr"
else
  fail "expected orphan; got rc=$rc out=[$out] err=[$err]"
fi

# ----------------------------------------------------------------------
echo "G2-2: in-flight first, ownerless second -> second member is orphan"
CASES=$((CASES + 1))
run_classify "150_inflight.sql|$(blob_of IF)"$'\n'"199_gone.sql|$(blob_of GONE)"$'\n'
want="in-flight${T}150_inflight.sql${T}inflight-a${T}exact"$'\n'"orphan${T}199_gone.sql"
if [[ "$rc" == "0" && "$out" == "$want" ]]; then
  pass "ordered verdicts, second member orphan"
else
  fail "expected [$want]; got rc=$rc out=[$out] err=[$err]"
fi

# ----------------------------------------------------------------------
echo "G2-3: stale fork — name in main's history, live branch still holds it -> orphan"
CASES=$((CASES + 1))
run_classify "128_x.sql|$(blob_of X)"$'\n'
if [[ "$rc" == "0" && "$out" == "orphan${T}128_x.sql" ]]; then
  pass "main-history exclusion beats a stale fork's exact-name holding"
else
  fail "expected orphan for 128_x.sql; got rc=$rc out=[$out] err=[$err]"
fi

# ----------------------------------------------------------------------
echo "G2-3b: never-merged rename — every branch holds main's same-blob 130_y -> orphan"
CASES=$((CASES + 1))
run_classify "127_y.sql|$(blob_of Y)"$'\n'
if [[ "$rc" == "0" && "$out" == "orphan${T}127_y.sql" ]]; then
  pass "branches own only files absent from main (the P0)"
else
  fail "expected orphan for 127_y.sql; got rc=$rc out=[$out] err=[$err]"
fi

# ----------------------------------------------------------------------
echo "G2-3c: stale fork and ownerless row, both input orders"
CASES=$((CASES + 1))
run_classify "128_x.sql|$(blob_of X)"$'\n'"199_gone.sql|$(blob_of GONE)"$'\n'
o1=$out
run_classify "199_gone.sql|$(blob_of GONE)"$'\n'"128_x.sql|$(blob_of X)"$'\n'
if [[ "$o1" == "orphan${T}128_x.sql"$'\n'"orphan${T}199_gone.sql" && "$out" == "orphan${T}199_gone.sql"$'\n'"orphan${T}128_x.sql" ]]; then
  pass "order-independent, no state carried between rows"
else
  fail "order-dependent verdicts: [$o1] vs [$out]"
fi

# ----------------------------------------------------------------------
echo "G2-6: the only blob match is a *.down.sql -> orphan"
CASES=$((CASES + 1))
run_classify "189_downy.sql|$(blob_of DOWNY)"$'\n'
if [[ "$rc" == "0" && "$out" == "orphan${T}189_downy.sql" ]]; then
  pass "down files are never owned"
else
  fail "expected orphan; got rc=$rc out=[$out]"
fi

# ----------------------------------------------------------------------
echo "G2-8: only holders are a merge-queue ref and a head already merged into main -> orphan"
CASES=$((CASES + 1))
run_classify "170_q.sql|$(blob_of Q)"$'\n'"181_anc.sql|$(blob_of ANC)"$'\n'
if [[ "$rc" == "0" && "$out" == "orphan${T}170_q.sql"$'\n'"orphan${T}181_anc.sql" ]]; then
  pass "gh-readonly-queue/* and ancestor-of-main heads own nothing"
else
  fail "expected two orphans; got rc=$rc out=[$out]"
fi

# ----------------------------------------------------------------------
echo "G2-9: only holder's last commit is 31 days old -> stale naming branch and age"
CASES=$((CASES + 1))
run_classify "160_old.sql|$(blob_of OLD)"$'\n'
if [[ "$rc" == "0" && "$out" == "stale${T}160_old.sql${T}old-branch${T}31" ]]; then
  pass "stale owner is reported with its age"
else
  fail "expected stale/old-branch/31; got rc=$rc out=[$out]"
fi

# ----------------------------------------------------------------------
echo "G2-10: branch deleted between two calls in one workspace -> in-flight then orphan"
CASES=$((CASES + 1))
branch ephemeral main "" 195_eph.sql="EPH"
run_classify "195_eph.sql|$(blob_of EPH)"$'\n'
o1=$out
git -C "$SEED" push -q origin --delete ephemeral
run_classify "195_eph.sql|$(blob_of EPH)"$'\n'
if [[ "$o1" == "in-flight${T}195_eph.sql${T}ephemeral${T}exact" && "$out" == "orphan${T}195_eph.sql" ]]; then
  pass "no owner state survives between invocations"
else
  fail "stale owner state: first=[$o1] second=[$out]"
fi

# ----------------------------------------------------------------------
echo "G2-11: bad stdin line -> rc 2"
CASES=$((CASES + 1))
run_classify 'bad;name.sql|'"$(blob_of Q)"$'\n'
rc_name=$rc
run_classify "170_q.sql|NOTASHA"$'\n'
if [[ "$rc_name" == "2" && "$rc" == "2" ]]; then
  pass "unsafe filename and malformed sha both fail closed"
else
  fail "expected rc=2 twice; got name=$rc_name sha=$rc"
fi

# ----------------------------------------------------------------------
echo "G2-4d: origin unreachable -> rc 2 (the probe maps this to UNCLASSIFIED)"
CASES=$((CASES + 1))
poison_origin
run_classify "150_inflight.sql|$(blob_of IF)"$'\n'
heal_origin
if [[ "$rc" == "2" && -z "$out" ]]; then
  pass "fetch failure is cannot-measure with no partial verdicts"
else
  fail "expected rc=2 and no stdout; got rc=$rc out=[$out] err=[$err]"
fi

echo "== Guard 2: must-PASS =="

# ----------------------------------------------------------------------
echo "G2-p1: exact / blob / slug owners -> in-flight with the tier"
CASES=$((CASES + 1))
run_classify "150_inflight.sql|$(blob_of IF)"$'\n'"151_renamed_old.sql|$(blob_of RN)"$'\n'"154_sluggy.sql|$(blob_of SLUG-v1)"$'\n'
want="in-flight${T}150_inflight.sql${T}inflight-a${T}exact"$'\n'"in-flight${T}151_renamed_old.sql${T}inflight-renamed${T}blob"$'\n'"in-flight${T}154_sluggy.sql${T}inflight-slug${T}slug"
if [[ "$rc" == "0" && "$out" == "$want" ]] && grep -qF 'in-flight=3 stale=0 orphan=0' <<<"$err"; then
  pass "all three ownership tiers"
else
  fail "expected [$want]; got rc=$rc out=[$out] err=[$err]"
fi

# ----------------------------------------------------------------------
echo "G2-p2: empty input -> rc 0 with no remote call (origin poisoned)"
CASES=$((CASES + 1))
poison_origin
run_classify ""
heal_origin
if [[ "$rc" == "0" && -z "$out" ]] && grep -qF 'in-flight=0 stale=0 orphan=0' <<<"$err"; then
  pass "nothing to classify stays offline"
else
  fail "expected rc=0 offline; got rc=$rc out=[$out] err=[$err]"
fi

# ----------------------------------------------------------------------
echo "G2-p3: origin without filter support -> identical verdicts"
CASES=$((CASES + 1))
NOFILTER="$tmp/origin-nofilter.git"
git clone -q --mirror "$ORIGIN" "$NOFILTER"
git -C "$NOFILTER" config uploadpack.allowFilter false
in3="150_inflight.sql|$(blob_of IF)"$'\n'"128_x.sql|$(blob_of X)"$'\n'"160_old.sql|$(blob_of OLD)"$'\n'
run_classify "$in3"
with_filter="$rc|$out"
git -C "$WORK" remote set-url origin "file://$NOFILTER"
run_classify "$in3"
heal_origin
if [[ "$rc|$out" == "$with_filter" && "$rc" == "0" ]]; then
  pass "an ignored filter changes nothing"
else
  fail "verdicts differ without filter support: [$with_filter] vs [$rc|$out]"
fi

# ----------------------------------------------------------------------
echo "G2-p4: a branch name outside the safe charset prints as <unprintable-branch>"
CASES=$((CASES + 1))
run_classify "157_weird.sql|$(blob_of WEIRD)"$'\n'
if [[ "$out" == "in-flight${T}157_weird.sql${T}<unprintable-branch>${T}exact" ]]; then
  pass "branch names are sanitized before they reach an annotation"
else
  fail "expected <unprintable-branch>; got [$out]"
fi

# ----------------------------------------------------------------------
echo "G2-p5: a fresh holder beats a stale holder of the same row -> in-flight"
CASES=$((CASES + 1))
branch fresh-too main "" 160_old.sql="OLD"
run_classify "160_old.sql|$(blob_of OLD)"$'\n'
git -C "$SEED" push -q origin --delete fresh-too
if [[ "$rc" == "0" && "$out" == "in-flight${T}160_old.sql${T}fresh-too${T}exact" ]]; then
  pass "freshness is decided across all holders before stale is reported"
else
  fail "expected in-flight via fresh-too; got rc=$rc out=[$out]"
fi

echo "== Guard 2: harness =="

mutate_fn() {  # $1=out $2=function-opening line (exact) $3=inserted statement
  awk -v open="$2" -v ins="$3" '{ print } $0 == open { print ins }' "$GUARD" > "$1"
  if cmp -s "$1" "$GUARD"; then printf 'FATAL: mutation did not land (%s)\n' "$2" >&2; exit 1; fi
}

# ----------------------------------------------------------------------
echo "G2-H1: classifier replaced by 'exit 0' with no output -> row G2-1 red"
CASES=$((CASES + 1))
mutate_fn "$tmp/m-cls0.sh" 'cmd_classify_missing() {' '  exit 0'
set +e
out=$(printf '%s\n' "199_gone.sql|$(blob_of GONE)" | bash "$tmp/m-cls0.sh" classify-missing --base-branch main --repo "$WORK" 2>/dev/null)
set -e
if [[ "$out" != "orphan${T}199_gone.sql" ]]; then
  pass "a silent classifier fails the orphan row"
else
  fail "G2-1 cannot see a silent classifier"
fi

# ----------------------------------------------------------------------
echo "G2-H2: classifier says in-flight for everything -> rows 1, 3, 3b red"
CASES=$((CASES + 1))
mutate_fn "$tmp/m-clsall.sh" 'classify_row() {' '  printf "in-flight\t%s\tanything\texact\n" "$1"; return 0'
set +e
out=$(printf '%s\n' "199_gone.sql|$(blob_of GONE)" "128_x.sql|$(blob_of X)" "127_y.sql|$(blob_of Y)" \
  | bash "$tmp/m-clsall.sh" classify-missing --base-branch main --repo "$WORK" 2>/dev/null)
set -e
if ! grep -q '^orphan' <<<"$out"; then
  pass "an everything-in-flight classifier cannot pass the orphan rows"
else
  fail "mutation left orphan verdicts in place: [$out]"
fi

# ----------------------------------------------------------------------
echo "G2-AC7b: classify never mutates the checkout's .git/config or shallow state"
CASES=$((CASES + 1))
if [[ "$(git_state)" == "$STATE1" ]]; then
  pass "throwaway repo only"
else
  fail "the checkout's git state changed during classify runs"
fi

echo "== Guard 2: the drift-probe step, extracted from action.yml =="

PROBE="$tmp/probe.sh"
python3 - "$ACTION" "$PROBE" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
steps = [s for s in doc["runs"]["steps"] if s.get("id") == "probe"]
assert len(steps) == 1, "expected exactly one step with id: probe"
open(sys.argv[2], "w").write(steps[0]["run"])
PY
if [[ ! -s "$PROBE" ]]; then printf 'FATAL: probe step extraction is empty\n' >&2; exit 1; fi

# The probe runs from the workspace root and calls the guard at its tracked path.
PW="$tmp/probe-work"
git clone -q "$ORIGIN_URL" "$PW" 2>/dev/null
mkdir -p "$PW/apps/web-platform/scripts"
cp "$GUARD" "$PW/apps/web-platform/scripts/dev-ledger-parity.sh"

# run_probe <fail-on> — composite `shell: bash` is `bash --noprofile --norc -eo pipefail`.
run_probe() {
  : > "$tmp/gho"
  set +e
  out=$(cd "$PW" && DOPPLER_TOKEN=x DOPPLER_PROJECT=soleur DOPPLER_CONFIG=dev_scheduled \
    FAIL_ON_DRIFT="$1" GITHUB_OUTPUT="$tmp/gho" GITHUB_WORKSPACE="$PW" \
    DATABASE_URL_POOLER="postgres://p" DLP_FAKE_LEDGER="$LEDGER" \
    bash --noprofile --norc -eo pipefail "$PROBE" 2>&1)
  rc=$?
  set -e
}
with_stub_classifier() {  # $1 = body of a stub classifier; restores the real one after
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$PW/apps/web-platform/scripts/dev-ledger-parity.sh"
}
restore_classifier() { cp "$GUARD" "$PW/apps/web-platform/scripts/dev-ledger-parity.sh"; }
line_no() { printf '%s\n' "$out" | grep -nF -- "$1" | head -n 1 | cut -d: -f1 || true; }

# ----------------------------------------------------------------------
echo "G2-P-inflight: only in-flight rows under fail-on -> warning, exit 0"
CASES=$((CASES + 1))
ledger "150_inflight.sql|$(blob_of IF)"
run_probe true
if [[ "$rc" == "0" ]] && has "::warning::  - 150_inflight.sql (in-flight: unmerged on live branch inflight-a via exact" \
  && has "ledger-classify: in-flight=1 stale=0 orphan=0" && ! has "Missing-on-main:" \
  && grep -qx 'drift-detected=true' "$tmp/gho"; then
  pass "an open PR's applied row no longer reds main (ADR-061 per-ref)"
else
  fail "expected rc=0 in-flight warning; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G2-P1: ownerless row under fail-on -> Missing-on-main error, exit 1"
CASES=$((CASES + 1))
ledger "199_gone.sql|$(blob_of GONE)"
run_probe true
if [[ "$rc" == "1" ]] && has "::error::Missing-on-main:" && has "::error::  - 199_gone.sql" \
  && has "no live branch owns these rows"; then
  pass "orphans still fail closed on authoritative refs"
else
  fail "expected rc=1 orphan block; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G2-P12: Missing-on-main lists filenames only (no |sha)"
CASES=$((CASES + 1))
if ! printf '%s' "$out" | grep -qE '::error::  - 199_gone\.sql\|' && ! has "$(blob_of GONE)"; then
  pass "display unchanged: bare filenames"
else
  fail "the pair format leaked into the display: $out"
fi

# ----------------------------------------------------------------------
echo "G2-P9: stale-only owner under fail-on -> error naming branch and age, exit 1"
CASES=$((CASES + 1))
ledger "160_old.sql|$(blob_of OLD)"
run_probe true
if [[ "$rc" == "1" ]] && has "::error::  - 160_old.sql (stale: only owner old-branch has had no commit for 31 days"; then
  pass "stale owner blocks, named"
else
  fail "expected rc=1 stale error; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G2-P4: classifier exits 2 -> UNCLASSIFIED printed first, rows under Unclassified:, exit 1"
CASES=$((CASES + 1))
with_stub_classifier 'cat >/dev/null; echo "boom" >&2; exit 2'
ledger "150_inflight.sql|$(blob_of IF)" "199_gone.sql|$(blob_of GONE)"
run_probe true
restore_classifier
u=$(line_no "ledger-classify: UNCLASSIFIED (rows=2 rc=2)")
h=$(line_no "::error::Unclassified:")
r=$(line_no "::error::  - 150_inflight.sql")
if [[ "$rc" == "1" && -n "$u" && -n "$h" && -n "$r" && "$u" -lt "$h" && "$h" -lt "$r" ]] \
  && ! has "Missing-on-main:" && has "not evidence of drift"; then
  pass "fail-closed classification is labelled, not dressed as drift"
else
  fail "expected UNCLASSIFIED before Unclassified: rows; got rc=$rc u=$u h=$h r=$r out=$out"
fi

# ----------------------------------------------------------------------
echo "G2-P5: classifier emits wrong order / too few lines -> UNCLASSIFIED, exit 1"
CASES=$((CASES + 1))
# Exactly one verdict per NON-EMPTY input line, reversed: the count matches, so
# only the per-line identity check can reject it (the here-string feeding the
# classifier carries a trailing empty line; counting it would decide the row
# by count instead).
with_stub_classifier 'mapfile -t l; for ((i=${#l[@]}-1;i>=0;i--)); do [[ -n "${l[$i]}" ]] && printf "orphan\t%s\n" "${l[$i]%%|*}"; done; exit 0'
ledger "150_inflight.sql|$(blob_of IF)" "199_gone.sql|$(blob_of GONE)"
run_probe true
rc_order=$rc; out_order=$out
with_stub_classifier 'mapfile -t l; printf "orphan\t%s\n" "${l[0]%%|*}"'
run_probe true
restore_classifier
if [[ "$rc_order" == "1" && "$rc" == "1" ]] && has "UNCLASSIFIED" \
  && printf '%s' "$out_order" | grep -qF "UNCLASSIFIED"; then
  pass "per-line identity check, not a count match"
else
  fail "expected UNCLASSIFIED twice; got order=$rc_order ($out_order) short=$rc ($out)"
fi

# ----------------------------------------------------------------------
echo "G2-P7: content drift on a file a live branch holds -> still an error + Repair: line"
CASES=$((CASES + 1))
printf '%s\n' "001_a.sql|$(blob_of A-drifted)" "002_b.sql|$(blob_of B)" "150_inflight.sql|$(blob_of IF)" > "$LEDGER"
run_probe true
if [[ "$rc" == "1" ]] && has "Content drift:" && has "001_a.sql (applied=" \
  && has "Repair: knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md §Content drift" \
  && has "(in-flight:"; then
  pass "only the missing class is classified; content drift keeps failing and names its repair"
else
  fail "expected rc=1 content drift + Repair; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G2-P-pr: fail-on=false (PR mode) never calls the classifier"
CASES=$((CASES + 1))
with_stub_classifier 'cat >/dev/null; echo CLASSIFIER-CALLED; exit 2'
ledger "199_gone.sql|$(blob_of GONE)"
run_probe false
restore_classifier
if [[ "$rc" == "0" ]] && has "::warning::  - 199_gone.sql" && ! has "CLASSIFIER-CALLED" && ! has "UNCLASSIFIED"; then
  pass "PR surfaces keep the unchanged warning display"
else
  fail "expected rc=0 warning-only; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G2-P-susp: a suspicious ledger filename is counted, never echoed"
CASES=$((CASES + 1))
printf '%s\n' "001_a.sql|$(blob_of A)" 'evil$(x)::error::pwn.sql|' > "$LEDGER"
run_probe false
if [[ "$rc" == "0" ]] && ! has "pwn" && has "suspicious"; then
  pass "log-injection vector closed"
else
  fail "suspicious row echoed or not counted: rc=$rc out=$out"
fi

echo "== Wiring: tenant-integration.yml and action.yml =="

# wiring_failures <workflow> — prints one line per broken wiring property.
wiring_failures() {
  local wf="$1" n name
  local -A at=()
  for name in \
    'Resolve dev-ledger-parity guard state' \
    'Lint migration FK preconditions' \
    'Resolve dev-ledger-parity guard (base-ref copy)' \
    'Acquire dev-suite mutex' \
    'Detect dev-vs-main migration drift' \
    'Assert unmerged migrations match the dev ledger' \
    'Apply migrations to dev' \
    'Release dev-suite mutex'; do
    n=$(grep -cxF "      - name: $name" "$wf" || true)
    if [[ "$n" != "1" ]]; then echo "step '$name' appears $n times (want 1)"; continue; fi
    at[$name]=$(grep -nxF "      - name: $name" "$wf" | cut -d: -f1)
  done
  local heavy
  heavy=$(grep -nxF '  tenant-integration:' "$wf" | cut -d: -f1 || true)
  [[ -n "$heavy" ]] || { echo "heavy job header missing"; return; }
  [[ -n "${at['Resolve dev-ledger-parity guard state']:-}" && "${at['Resolve dev-ledger-parity guard state']}" -lt "$heavy" ]] \
    || echo "ledger_guard step is not in detect-changes"
  lt() { [[ -n "${at[$1]:-}" && -n "${at[$2]:-}" && "${at[$1]}" -lt "${at[$2]}" ]] || echo "order: '$1' must precede '$2'"; }
  lt 'Lint migration FK preconditions' 'Resolve dev-ledger-parity guard (base-ref copy)'
  lt 'Resolve dev-ledger-parity guard (base-ref copy)' 'Acquire dev-suite mutex'
  lt 'Detect dev-vs-main migration drift' 'Assert unmerged migrations match the dev ledger'
  lt 'Assert unmerged migrations match the dev ledger' 'Apply migrations to dev'
  lt 'Assert unmerged migrations match the dev ledger' 'Release dev-suite mutex'
  # step bodies: from the name line to the next step or job header
  body() { awk -v s="      - name: $1" 'f && (/^      - / || /^  [a-z]/) {exit} $0 == s {f=1} f' "$wf"; }
  body 'Assert unmerged migrations match the dev ledger' | grep -qF 'bash "$RUNNER_TEMP/dev-ledger-parity.sh" check' \
    || echo "check step does not execute the resolved RUNNER_TEMP copy"
  local rb
  rb=$(body 'Resolve dev-ledger-parity guard (base-ref copy)')
  for arm in 'deleted)' '*)'; do
    awk -v a="$arm" 'index($0, a) && $0 ~ /^[[:space:]]*(deleted|\*)\)/ {f=1} f && /exit 1/ {ok=1} f && /;;/ {exit} END {exit !ok}' <<<"$rb" \
      || echo "resolve step arm '$arm' does not exit 1"
  done
  grep -qF 'git show "origin/${base_ref}:$GUARD_PATH"' <<<"$rb" || echo "resolve step does not extract the base-ref copy"
  local dc
  dc=$(awk -v h="$heavy" 'NR >= h {exit} f {print} /^  detect-changes:$/ {f=1}' "$wf")
  grep -qE '^[[:space:]]+fetch-depth: 0$' <<<"$dc" || echo "detect-changes lost fetch-depth: 0"
  grep -qE '^[[:space:]]+ledger_guard: \$\{\{ steps\.ledger_guard\.outputs\.state \}\}$' <<<"$dc" || echo "detect-changes does not export ledger_guard"
  grep -qF 'apps/web-platform/scripts/dev-ledger-parity' <<<"$dc" || echo "anchor alternation lacks dev-ledger-parity"
  grep -qE 'LEDGER_GUARD: \$\{\{ needs\.detect-changes\.outputs\.ledger_guard \}\}' "$wf" || echo "resolve step does not read the detect-changes output"
}

# ----------------------------------------------------------------------
echo "W-0: the real workflow satisfies every wiring property (AC3, AC4)"
CASES=$((CASES + 1))
wf_out=$(wiring_failures "$WF")
if [[ -z "$wf_out" ]]; then
  pass "wiring intact"
else
  fail "wiring broken: $wf_out"
fi

wf_mutant() {  # $1 = python snippet transforming `s`
  python3 - "$WF" "$tmp/wf-mut.yml" "$1" <<'PY'
import sys
s = open(sys.argv[1]).read()
exec(sys.argv[3])
open(sys.argv[2], "w").write(s)
PY
  if cmp -s "$WF" "$tmp/wf-mut.yml"; then printf 'FATAL: workflow mutation did not land\n' >&2; exit 1; fi
}

# ----------------------------------------------------------------------
echo "W-12: check step moved after 'Apply migrations to dev' -> wiring RED"
CASES=$((CASES + 1))
wf_mutant '
import re
blk = re.search(r"(      - name: Assert unmerged migrations match the dev ledger\n.*?)(?=\n      - |\n  [a-z])", s, re.S).group(1) + "\n"
s = s.replace(blk, "", 1)
anchor = "      - name: Preflight WORM-vs-cascade contradiction check\n"
s = s.replace(anchor, blk + anchor, 1)
'
if [[ -n "$(wiring_failures "$tmp/wf-mut.yml")" ]]; then pass "misplaced check detected"; else fail "moving the check past apply went unseen"; fi

# ----------------------------------------------------------------------
echo "W-13: check runs the checkout copy instead of \$RUNNER_TEMP -> wiring RED"
CASES=$((CASES + 1))
wf_mutant 's = s.replace("bash \"$RUNNER_TEMP/dev-ledger-parity.sh\" check", "bash apps/web-platform/scripts/dev-ledger-parity.sh check")'
if [[ -n "$(wiring_failures "$tmp/wf-mut.yml")" ]]; then pass "self-judging invocation detected"; else fail "checkout-copy invocation went unseen"; fi

# ----------------------------------------------------------------------
echo "W-14: resolve step's deleted) arm loses its exit 1 -> wiring RED"
CASES=$((CASES + 1))
wf_mutant '
import re
s = re.sub(r"(deleted\)\n(?:.*\n)*?)(\s*)exit 1\n", r"\1\2true\n", s, count=1)
'
if [[ -n "$(wiring_failures "$tmp/wf-mut.yml")" ]]; then pass "fail-open deleted arm detected"; else fail "deleted) arm without exit 1 went unseen"; fi

# ----------------------------------------------------------------------
echo "W-15: detect-changes loses fetch-depth: 0 -> wiring RED"
CASES=$((CASES + 1))
wf_mutant 's = s.replace("fetch-depth: 0", "fetch-depth: 2", 1)'
if [[ -n "$(wiring_failures "$tmp/wf-mut.yml")" ]]; then pass "shallow detect-changes detected"; else fail "fetch-depth change went unseen"; fi

# ----------------------------------------------------------------------
echo "W-AC5: action.yml carries the repair, ownership and fail-closed lines; no raw row echo"
CASES=$((CASES + 1))
miss=""
grep -qF 'Repair: knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md §Content drift' "$ACTION" || miss+=" repair"
grep -qF 'dev-ledger-parity.sh check (#8521)' "$ACTION" || miss+=" check-pointer"
grep -qF 'no live branch owns these rows' "$ACTION" || miss+=" ownerless"
grep -qF 'UNCLASSIFIED' "$ACTION" || miss+=" unclassified"
# Scoped to the extracted probe step, and to $f as a whole word ($fn in the
# rpc-body step names a committed allowlist entry, not a ledger row).
if grep -qE 'suspicious.*\$\{?f([^A-Za-z0-9_]|$)' "$PROBE"; then miss+=" raw-row-echo"; fi
if [[ -z "$miss" ]]; then pass "all four present"; else fail "action.yml missing:$miss"; fi

# ----------------------------------------------------------------------
echo "W-help: --help documents both summary formats (discoverability)"
CASES=$((CASES + 1))
set +e
out=$(bash "$GUARD" --help 2>&1)
rc=$?
set -e
if [[ "$rc" == "0" ]] && has "ledger-parity:" && has "ledger-classify:"; then
  pass "--help is the discoverability hook"
else
  fail "expected --help to print both formats; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
# Vacuity floor: reported via printf + exit, never through fail(). The bound
# sits directly above its `if` so guard-vacuity-floor's mutant slice carries it.
# ----------------------------------------------------------------------
echo ""
EXPECTED_CASES=65
if [[ "$CASES" -lt "$EXPECTED_CASES" ]]; then
  printf 'FATAL: only %s of %s cases ran — suite is truncated\n' "$CASES" "$EXPECTED_CASES" >&2
  exit 1
fi
echo "dev-ledger-parity.test.sh: $PASS passed, $FAIL failed ($CASES cases)"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
exit 0
