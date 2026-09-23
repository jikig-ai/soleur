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

# Canonical assert_fixture_dir — byte-identical copy (fixture-scan.py requires
# the verbatim body; see plugins/soleur/test/test-helpers.sh).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
assert_fixture_dir "$tmp"

GUARD="$tmp/guard.sh"
cp "$GUARD_SRC" "$GUARD"

MDIR="apps/web-platform/supabase/migrations"

# ---------- fake binaries ----------
BIN="$tmp/bin"
mkdir -p "$BIN"
cat > "$BIN/psql" <<'SH'
#!/usr/bin/env bash
# Fake psql: logs argv NUL-delimited, then emits the scripted ledger. When
# DLP_PSQL_EXPECT_SQL is set, any other -c statement is refused (a second,
# writing call would otherwise be invisible to every row).
if [[ -n "${DLP_PSQL_LOG:-}" ]]; then
  { printf 'CALL\0'; for a in "$@"; do printf '%s\0' "$a"; done; } >> "$DLP_PSQL_LOG"
fi
if [[ -n "${DLP_PSQL_EXPECT_SQL:-}" ]]; then
  prev=""; sql=""
  for a in "$@"; do [[ "$prev" == "-c" ]] && sql="$a"; prev="$a"; done
  if [[ "$sql" != "$DLP_PSQL_EXPECT_SQL" ]]; then
    [[ -n "${DLP_PSQL_UNEXPECTED:-}" ]] && printf 'unexpected SQL\n' >> "$DLP_PSQL_UNEXPECTED"
    exit 97
  fi
fi
rc="${DLP_FAKE_PSQL_RC:-0}"
if [[ "$rc" != "0" ]]; then echo "psql: fake failure" >&2; exit "$rc"; fi
if [[ -n "${DLP_FAKE_LEDGER:-}" && -f "$DLP_FAKE_LEDGER" ]]; then cat "$DLP_FAKE_LEDGER"; fi
exit 0
SH
cat > "$BIN/doppler" <<'SH'
#!/usr/bin/env bash
# Fake doppler: log argv (when asked), drop `run -p … -c … --`, exec the rest.
if [[ -n "${DLP_DOPPLER_LOG:-}" ]]; then printf '%s\n' "$*" >> "$DLP_DOPPLER_LOG"; fi
while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
shift
exec "$@"
SH
cat > "$BIN/curl" <<'SH'
#!/usr/bin/env bash
# Fake curl (Sentry store): log argv, answer 200, never touch the network.
if [[ -n "${DLP_CURL_LOG:-}" ]]; then printf '%s\n' "$*" >> "$DLP_CURL_LOG"; fi
printf '200'
SH
chmod +x "$BIN/psql" "$BIN/doppler" "$BIN/curl"
WANT_SQL="SELECT filename || '|' || COALESCE(content_sha, '') FROM public._schema_migrations ORDER BY filename"
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
git -C "$SEED" mv "$SEED/$MDIR/128_x.sql" "$SEED/$MDIR/131_x.sql"
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

# run_check [extra args...] — Guard 1 against WORK. Sets out, rc. Every run
# is also held to ONE psql call issuing exactly the fixed SELECT; a breach is
# recorded and reddens the STUB row at the end of the suite.
STUB_BREACHES=""
run_check() {
  : > "$tmp/run-psql.log"; : > "$tmp/run-psql-unexpected.log"
  set +e
  out=$(DATABASE_URL_POOLER="postgres://pooler.fixture.invalid/db" DATABASE_URL="" \
    DLP_PSQL_LOG="$tmp/run-psql.log" DLP_PSQL_EXPECT_SQL="$WANT_SQL" DLP_PSQL_UNEXPECTED="$tmp/run-psql-unexpected.log" \
    DLP_FAKE_LEDGER="$LEDGER" bash "$GUARD" check --base origin/main --repo "$WORK" "$@" 2>&1)
  rc=$?
  set -e
  local calls
  calls=$(tr -cd '\0' < "$tmp/run-psql.log" | wc -c)
  [[ "$calls" -gt 0 ]] && calls=$(tr '\0' '\n' < "$tmp/run-psql.log" | grep -cx 'CALL' || true)
  if [[ "$calls" -gt 1 || -s "$tmp/run-psql-unexpected.log" ]]; then STUB_BREACHES+=" [$*: calls=$calls]"; fi
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
if [[ "$rc" == "1" ]] && has "144_slugme.sql" && has "by slug" && has "give yours a different slug"; then
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
if [[ "$rc" == "2" ]] && has "psql rc=2" && has "re-run the job"; then
  pass "a connection failure is cannot-measure, naming the psql exit"
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
echo "G1-10: a candidate needs ownership and origin is unreachable -> rc 2 cannot-measure"
CASES=$((CASES + 1))
feat_case 143_new.sql="R3"
ledger "143_old.sql|$(blob_of R3)"
poison_origin
run_check --head-branch feat
heal_origin
if [[ "$rc" == "2" ]] && has "fetching origin branch heads failed" && has "not a verdict on the migrations"; then
  pass "owner fetch failure is cannot-measure, not a pass and not a violation"
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
git -C "$WORK" mv "$WORK/$MDIR/143_old.sql" "$WORK/$MDIR/143_new.sql"
git -C "$WORK" commit -qm 'rename, not pushed'
ledger "143_old.sql|$(blob_of R3)"
run_check --head-branch feat
if [[ "$rc" == "1" ]] && has "by blob" && ! has "treated as that PR's in-flight row"; then
  pass "the PR's own branch is excluded from ownership"
else
  fail "expected rc=1 with no ownership notice; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-13: one PR commit deletes an applied migration and adds a DIFFERENT one -> rc 1 by history (no rename-detection crash)"
CASES=$((CASES + 1))
# Rename detection must read blob contents the blobless owner repo does not
# hold; without --no-renames git dies here and every re-run exits 2.
feat_case 146_a.sql="A146 original body"
git -C "$WORK" rm -q "$WORK/$MDIR/146_a.sql"
put "$WORK" 147_zzz.sql "an entirely different body"
git -C "$WORK" add -A
git -C "$WORK" commit -qm 'drop 146_a and add 147_zzz in one commit'
git -C "$WORK" push -q -f origin feat
ledger "146_a.sql|$(blob_of 'A146 original body')"
run_check --head-branch feat
if [[ "$rc" == "1" ]] && has "146_a.sql" && has "by history"; then
  pass "delete+add in one commit is judged, not crashed"
else
  fail "expected rc=1 A4 by history; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-14: a branch stacked on this PR still holds G at the applied blob -> it does NOT launder the violation"
CASES=$((CASES + 1))
feat_case 143_old.sql="R3"
git -C "$SEED" fetch -q origin
git -C "$SEED" switch -q -C stacked origin/feat
put "$SEED" 191_child.sql "CHILD"
git -C "$SEED" add -A && git -C "$SEED" commit -qm 'stacked child'
git -C "$SEED" push -q -f origin HEAD:refs/heads/stacked
git -C "$SEED" switch -q main
git -C "$WORK" mv "$WORK/$MDIR/143_old.sql" "$WORK/$MDIR/143_new.sql"
git -C "$WORK" commit -qm 'rename after apply'
git -C "$WORK" push -q -f origin feat
ledger "143_old.sql|$(blob_of R3)"
run_check --head-branch feat
git -C "$SEED" push -q origin --delete stacked
if [[ "$rc" == "1" ]] && has "by blob" && ! has "treated as that PR's in-flight row"; then
  pass "an owner that inherited G from this PR's history is not an independent owner"
else
  fail "expected rc=1 (stacked branch must not launder); got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-15: the only exact-name holder is STALE -> the PR is not excused"
CASES=$((CASES + 1))
feat_case 161_old.sql="OLD"
ledger "160_old.sql|$(blob_of OLD)"
run_check --head-branch feat
if [[ "$rc" == "1" ]] && has "160_old.sql" && has "by blob"; then
  pass "a stale holder owns nothing on the PR side either"
else
  fail "expected rc=1; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-16: a candidate carrying one of MAIN's blobs is not this PR's history -> rc 0"
CASES=$((CASES + 1))
feat_case 148_ok.sql="OK"
ledger "127_y.sql|$(blob_of Y)"
run_check --head-branch feat
if [[ "$rc" == "0" ]] && has "candidates=1"; then
  pass "A4 reads only base..head, never base's own history"
else
  fail "expected rc=0; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-17: a ledger filename outside the whitelist is counted, never echoed (check side)"
CASES=$((CASES + 1))
ledger "148_ok.sql|$(blob_of OK)" "evil::error::pwn.sql|$(blob_of OK)"
run_check --head-branch feat
if [[ "$rc" == "0" ]] && ! has "pwn" && has "skipped 1 ledger row"; then
  pass "log-injection vector closed on the PR side"
else
  fail "expected rc=0, counted, not echoed; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-18: a second '|' in a ledger line cannot overwrite the real row's sha"
CASES=$((CASES + 1))
feat_case 140_x.sql="X140-v2"
ledger "140_x.sql|$(blob_of X140-v1)" "140_x.sql|$(blob_of X140-v2)|"
run_check --head-branch feat
if [[ "$rc" == "1" ]] && has "$(blob_of X140-v1)" && has "skipped 1 ledger row"; then
  pass "exactly one delimiter per row; the forged row is skipped"
else
  fail "expected rc=1 A1 with the forged row skipped; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-19: an invalid --head-branch skips A4 with a warning instead of blocking"
CASES=$((CASES + 1))
feat_case 148_ok.sql="OK"
ledger "199_zz.sql|$(blob_of ZZ)"
run_check --head-branch 'bad..name'
if [[ "$rc" == "0" ]] && has "is not a valid branch name"; then
  pass "a branch-name problem is a warning, not a Doppler-config accusation"
else
  fail "expected rc=0 + warning; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-20: a valid --head-branch that is not on origin -> rc 2, named"
CASES=$((CASES + 1))
run_check --head-branch no-such-branch
if [[ "$rc" == "2" ]] && has "is not a branch on origin"; then
  pass "a missing head branch cannot silently disable A4"
else
  fail "expected rc=2; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-21: a migration filename in the tree outside the whitelist is a warning (the runner skips it), not exit 2"
CASES=$((CASES + 1))
feat_case "150 bad.sql"="BAD"
ledger
run_check --head-branch feat
if [[ "$rc" == "0" ]] && has "outside the runner's whitelist" && ! has "150 bad"; then
  pass "unsafe tree filename is counted, not echoed, and not blamed on config"
else
  fail "expected rc=0 + warning; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G1-22: psql exit codes are classed by what they measured"
CASES=$((CASES + 1))
feat_case 148_ok.sql="OK"
ledger
set +e
out3=$(DLP_FAKE_PSQL_RC=3 DATABASE_URL_POOLER="postgres://p" DLP_FAKE_LEDGER="$LEDGER" bash "$GUARD" check --base origin/main --repo "$WORK" 2>&1); rc3=$?
out124=$(DLP_FAKE_PSQL_RC=124 DATABASE_URL_POOLER="postgres://p" DLP_FAKE_LEDGER="$LEDGER" bash "$GUARD" check --base origin/main --repo "$WORK" 2>&1); rc124=$?
set -e
if [[ "$rc3" == "2" && "$rc124" == "2" ]] && grep -qF "a re-run will not help" <<<"$out3" \
  && grep -qF "timed out" <<<"$out124" && grep -qF "re-run the job" <<<"$out124"; then
  pass "SQL error -> config; timeout -> transient"
else
  fail "psql classes wrong: rc3=$rc3 [$out3] rc124=$rc124 [$out124]"
fi

# ----------------------------------------------------------------------
echo "G1-23: the COMMITTED blob is compared, not an uncommitted working copy"
CASES=$((CASES + 1))
feat_case 148_ok.sql="OK"
ledger "148_ok.sql|$(blob_of OK)"
put "$WORK" 148_ok.sql "OK but edited and not committed"
run_check --head-branch feat
git -C "$WORK" checkout -q -- "$WORK/$MDIR/148_ok.sql"
if [[ "$rc" == "0" ]] && has "ledgered-match=1"; then
  pass "the guard reads what main's probe will read after merge"
else
  fail "expected rc=0 on the committed blob; got rc=$rc out=$out"
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
if [[ "$rc" == "0" ]] && has "::warning::ledger-parity: 144_slugme.sql" && has "other-f" && has "skipped-owned=1"; then
  pass "another PR's in-flight row is skipped with a warning naming it"
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
if [[ "$rc" == "0" && "$out" == "orphan${T}199_gone.sql" ]] && grep -qF 'ledger-classify: in-flight=0 stale=0 merged=0 orphan=1' <<<"$err"; then
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
if [[ "$rc" == "0" && "$out" == "$want" ]] && grep -qF 'in-flight=3 stale=0 merged=0 orphan=0' <<<"$err"; then
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
if [[ "$rc" == "0" && -z "$out" ]] && grep -qF 'in-flight=0 stale=0 merged=0 orphan=0' <<<"$err"; then
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

# ----------------------------------------------------------------------
echo "G2-p6: tier precedence — a blob holder beats a slug holder"
CASES=$((CASES + 1))
branch kx main "" 171_other.sql="KXB"
branch ky main "" 174_same.sql="KY-body"
run_classify "173_same.sql|$(blob_of KXB)"$'\n'
git -C "$SEED" push -q origin --delete kx ky
if [[ "$out" == "in-flight${T}173_same.sql${T}kx${T}blob" ]]; then
  pass "exact > blob > slug"
else
  fail "expected kx via blob; got [$out]"
fi

# ----------------------------------------------------------------------
echo "G2-p7: two fresh holders -> the lexically smallest, deterministically"
CASES=$((CASES + 1))
branch ka2 main "" 175_dup.sql="DUP"
branch ka1 main "" 175_dup.sql="DUP"
run_classify "175_dup.sql|$(blob_of DUP)"$'\n'
git -C "$SEED" push -q origin --delete ka1 ka2
if [[ "$out" == "in-flight${T}175_dup.sql${T}ka1${T}exact" ]]; then
  pass "ties resolve to one stable owner"
else
  fail "expected ka1; got [$out]"
fi

# ----------------------------------------------------------------------
echo "G2-p8: a FRESH blob holder beats a STALE exact-name holder"
CASES=$((CASES + 1))
branch kfb main "" 162_other.sql="OLD"
run_classify "160_old.sql|$(blob_of OLD)"$'\n'
git -C "$SEED" push -q origin --delete kfb
if [[ "$out" == "in-flight${T}160_old.sql${T}kfb${T}blob" ]]; then
  pass "freshness is decided across every tier before stale is reported"
else
  fail "expected in-flight via kfb blob; got [$out]"
fi

# ----------------------------------------------------------------------
echo "G2-p9: a head dated 30 days + 1 hour ago is still fresh (30 whole days)"
CASES=$((CASES + 1))
branch b30 main "@$(( $(date +%s) - 30 * 86400 - 3600 )) +0000" 176_b30.sql="B30"
run_classify "176_b30.sql|$(blob_of B30)"$'\n'
git -C "$SEED" push -q origin --delete b30
if [[ "$out" == "in-flight${T}176_b30.sql${T}b30${T}exact" ]]; then
  pass "the boundary is > 30 whole days"
else
  fail "expected in-flight at 30 days; got [$out]"
fi

# ----------------------------------------------------------------------
echo "G2-p10: a pre-content-sha row (empty sha) is classified, not refused"
CASES=$((CASES + 1))
run_classify "199_gone.sql|"$'\n'
if [[ "$rc" == "0" && "$out" == "orphan${T}199_gone.sql" ]]; then
  pass "an empty sha only skips the blob tier"
else
  fail "expected orphan rc=0; got rc=$rc out=[$out] err=[$err]"
fi

# ----------------------------------------------------------------------
echo "G2-p11: a head dated in the FUTURE is stale, never fresh forever"
CASES=$((CASES + 1))
branch fut main "@$(( $(date +%s) + 3 * 86400 )) +0000" 177_fut.sql="FUT"
run_classify "177_fut.sql|$(blob_of FUT)"$'\n'
git -C "$SEED" push -q origin --delete fut
if [[ "$out" == "stale${T}177_fut.sql${T}fut${T}future-dated" ]]; then
  pass "a pusher-set date cannot keep a row in-flight"
else
  fail "expected stale future-dated; got [$out]"
fi

# ----------------------------------------------------------------------
echo "G2-p12: a row whose file is on the base tip NOW -> merged (non-blocking)"
CASES=$((CASES + 1))
run_classify "130_y.sql|$(blob_of Y)"$'\n'
if [[ "$rc" == "0" && "$out" == "merged${T}130_y.sql" ]] && grep -qF 'merged=1' <<<"$err"; then
  pass "a merge between probe and classifier is not reported as an orphan"
else
  fail "expected merged; got rc=$rc out=[$out] err=[$err]"
fi

# ----------------------------------------------------------------------
echo "G2-p13: a file in a migrations SUBDIRECTORY owns nothing (the runner never applies it)"
CASES=$((CASES + 1))
git -C "$SEED" switch -q -C subdir-owner main
mkdir -p "$SEED/$MDIR/sub"
printf 'SUB\n' > "$SEED/$MDIR/sub/196_sub.sql"
git -C "$SEED" add -A && git -C "$SEED" commit -qm 'subdir file'
git -C "$SEED" push -q -f origin HEAD:refs/heads/subdir-owner
git -C "$SEED" switch -q main
run_classify "196_sub.sql|$(blob_of SUB)"$'\n'
git -C "$SEED" push -q origin --delete subdir-owner
if [[ "$out" == "orphan${T}196_sub.sql" ]]; then
  pass "only top-level migrations are owned"
else
  fail "expected orphan; got [$out]"
fi

# ----------------------------------------------------------------------
echo "G2-p14: a reused owner cache (DLP_OWNERS_CACHE) prunes a deleted branch between calls"
CASES=$((CASES + 1))
CACHE="$tmp/owners-cache"
branch cached main "" 178_cache.sql="CACHE"
set +e
o1=$(printf '%s\n' "178_cache.sql|$(blob_of CACHE)" | DLP_OWNERS_CACHE="$CACHE" bash "$GUARD" classify-missing --base-branch main --repo "$WORK" 2>/dev/null)
git -C "$SEED" push -q origin --delete cached
o2=$(printf '%s\n' "178_cache.sql|$(blob_of CACHE)" | DLP_OWNERS_CACHE="$CACHE" bash "$GUARD" classify-missing --base-branch main --repo "$WORK" 2>/dev/null)
set -e
if [[ "$o1" == "in-flight${T}178_cache.sql${T}cached${T}exact" && "$o2" == "orphan${T}178_cache.sql" && -f "$CACHE/HEAD" ]]; then
  pass "the cache is reused and never keeps a deleted owner"
else
  fail "cache reuse wrong: first=[$o1] second=[$o2]"
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
  && ! printf '%s\n' "$out" | grep -q '^::error::' \
  && has "ledger-classify: in-flight=1 stale=0 merged=0 orphan=0" && ! has "Missing-on-main:" \
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
  && has "no fresh live branch owns these rows" && grep -qx 'drift-detected=true' "$tmp/gho"; then
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
if [[ "$rc" == "1" ]] && has "::error::  - 160_old.sql (stale: owner old-branch has no commit dated within the last 30 days (age: 31)" \
  && has "::error::dev-Supabase has _schema_migrations rows whose only owner branch is stale"; then
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
  && ! has "Missing-on-main:" && has "ownership could not be established"; then
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

# ----------------------------------------------------------------------
echo "G2-P-stderr: classifier diagnostics are prefixed so none can become an annotation"
CASES=$((CASES + 1))
with_stub_classifier 'cat >/dev/null; echo "::error::boom" >&2; exit 2'
ledger "199_gone.sql|$(blob_of GONE)"
run_probe true
restore_classifier
if [[ "$rc" == "1" ]] && has "  classifier: ::error::boom" && ! printf '%s\n' "$out" | grep -qx '::error::boom'; then
  pass "classifier stderr is neutralised"
else
  fail "expected prefixed classifier stderr; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G2-P-bad: unsafe branch, bogus verdict, or correct lines with rc!=0 -> UNCLASSIFIED each"
CASES=$((CASES + 1))
ledger "199_gone.sql|$(blob_of GONE)"
with_stub_classifier 'mapfile -t l; printf "in-flight\t%s\tbad;branch\texact\n" "${l[0]%%|*}"'
run_probe true; o1=$out; r1=$rc
with_stub_classifier 'mapfile -t l; printf "bogus\t%s\n" "${l[0]%%|*}"'
run_probe true; o2=$out; r2=$rc
with_stub_classifier 'mapfile -t l; printf "orphan\t%s\n" "${l[0]%%|*}"; exit 2'
run_probe true; o3=$out; r3=$rc
restore_classifier
if [[ "$r1$r2$r3" == "111" ]] && grep -qF "UNCLASSIFIED (rows=1 line=1 malformed)" <<<"$o1" \
  && grep -qF "UNCLASSIFIED (rows=1 line=1 unknown verdict)" <<<"$o2" && grep -qF "UNCLASSIFIED (rows=1 rc=2)" <<<"$o3"; then
  pass "every malformed classifier answer fails closed with its reason"
else
  fail "expected three UNCLASSIFIED with reasons; got [$r1] $o1 || [$r2] $o2 || [$r3] $o3"
fi

# ----------------------------------------------------------------------
echo "G2-P-sha: a malformed content_sha is reported as drift, never echoed"
CASES=$((CASES + 1))
printf '%s\n' '001_a.sql|ABCinjected::error::x' "002_b.sql|$(blob_of B)" > "$LEDGER"
run_probe true
if [[ "$rc" == "1" ]] && has "001_a.sql (applied=<malformed content_sha, not echoed>" && ! has "ABCinjected"; then
  pass "the content_sha column cannot inject annotations"
else
  fail "expected malformed-sha drift, not echoed; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G2-P-blob: an in-flight row matched by blob/slug says the owner must restore the name"
CASES=$((CASES + 1))
ledger "151_renamed_old.sql|$(blob_of RN)"
run_probe true
if [[ "$rc" == "0" ]] && has "matched via blob — that PR must restore the applied name before it merges" && ! has "merging clears it"; then
  pass "merging clears only exact-name rows"
else
  fail "expected the restore-the-name wording; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G2-P-merged: a merged verdict is a warning, not a red"
CASES=$((CASES + 1))
with_stub_classifier 'mapfile -t l; printf "merged\t%s\n" "${l[0]%%|*}"'
ledger "199_gone.sql|$(blob_of GONE)"
run_probe true
restore_classifier
if [[ "$rc" == "0" ]] && has "::warning::  - 199_gone.sql (now on origin/main" && ! has "Missing-on-main:"; then
  pass "a probe/classifier race does not red main"
else
  fail "expected rc=0 merged warning; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G2-P-sentry: with sentry-dsn set, each blocking class emits one static event; in-flight emits none"
CASES=$((CASES + 1))
CURLLOG="$tmp/curl.log"
: > "$CURLLOG"
ledger "199_gone.sql|$(blob_of GONE)"
export DLP_CURL_LOG="$CURLLOG" SENTRY_DSN="https://pubkey@sentry.fixture.invalid/12345"
run_probe true
n_orphan=$(grep -c '"ledger_class":"orphan"' "$CURLLOG" || true)
: > "$CURLLOG"
ledger "150_inflight.sql|$(blob_of IF)"
run_probe true
n_inflight=$(grep -c 'sentry' "$CURLLOG" || true)
unset DLP_CURL_LOG SENTRY_DSN
if [[ "$n_orphan" == "1" && "$n_inflight" == "0" ]] && ! grep -q '199_gone' "$CURLLOG"; then
  pass "the scheduled surface's red is reported off-box, class names only"
else
  fail "expected 1 orphan event and 0 in-flight events; got orphan=$n_orphan inflight=$n_inflight"
fi

# ----------------------------------------------------------------------
echo "G2-P-args: the probe reads the ledger through dev_scheduled with the content_sha column"
CASES=$((CASES + 1))
DOPLOG="$tmp/doppler.log"; PSQLLOG="$tmp/probe-psql.log"
: > "$DOPLOG"; : > "$PSQLLOG"
ledger
export DLP_DOPPLER_LOG="$DOPLOG" DLP_PSQL_LOG="$PSQLLOG"
run_probe true
unset DLP_DOPPLER_LOG DLP_PSQL_LOG
if grep -qE '(^| )-c dev_scheduled( |$)' "$DOPLOG" && tr '\0' '\n' < "$PSQLLOG" | grep -qF 'COALESCE(content_sha'; then
  pass "doppler config and SQL column pinned"
else
  fail "probe read the wrong config or column: doppler=[$(cat "$DOPLOG")]"
fi

# ----------------------------------------------------------------------
echo "G2-P-bound: the classifier call is bounded, and the stale threshold agrees across files"
CASES=$((CASES + 1))
g_days=$(sed -n 's/^readonly STALE_DAYS=\([0-9][0-9]*\)$/\1/p' "$GUARD")
a_days=$(sed -n 's/^[[:space:]]*STALE_DAYS_LABEL=\([0-9][0-9]*\)$/\1/p' "$PROBE")
if grep -qF 'cls_out=$(timeout -k 5 90 bash apps/web-platform/scripts/dev-ledger-parity.sh classify-missing' "$PROBE" \
  && [[ -n "$g_days" && "$g_days" == "$a_days" ]]; then
  pass "timeout wrapper present; STALE_DAYS=$g_days in both"
else
  fail "unbounded classifier call or threshold drift: guard=$g_days action=$a_days"
fi

echo "== Wiring: tenant-integration.yml and action.yml =="

# wf_static <workflow> — prints one line per broken STRUCTURAL property, read
# from the parsed YAML (never from text a comment could also carry).
wf_static() {
  python3 - "$1" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
jobs = doc["jobs"]
bad = []
dc, hv = jobs["detect-changes"], jobs["tenant-integration"]
def step(job, name):
    got = [s for s in job["steps"] if s.get("name") == name]
    if len(got) != 1:
        bad.append(f"step {name!r} appears {len(got)} times (want 1)")
        return None
    return got[0]
st = step(dc, "Resolve dev-ledger-parity guard state")
if st is not None and st.get("id") != "ledger_guard":
    bad.append("state step lost id ledger_guard")
if dc.get("outputs", {}).get("ledger_guard") != "${{ steps.ledger_guard.outputs.state }}":
    bad.append("detect-changes does not export ledger_guard")
co = [s for s in dc["steps"] if str(s.get("uses", "")).startswith("actions/checkout@")]
if not co or co[0].get("with", {}).get("fetch-depth") != 0:
    bad.append("detect-changes lost fetch-depth: 0")
flt = [s for s in dc["steps"] if s.get("id") == "filter"]
run = flt[0]["run"] if flt else ""
if "apps/web-platform/scripts/dev-ledger-parity" not in run:
    bad.append("anchor alternation lacks dev-ledger-parity")
if 'git log --format= --name-only "origin/${BASE_REF}..HEAD" -- apps/web-platform/supabase/migrations/' not in run:
    bad.append("detect-changes no longer scans the PR's own migration history")
names = [s.get("name") for s in hv["steps"]]
def idx(n):
    return names.index(n) if n in names else -1
order = ["Lint migration FK preconditions", "Acquire dev-suite mutex", "Detect dev-vs-main migration drift",
         "Assert unmerged migrations match the dev ledger", "Preflight schema-vs-ledger consistency check",
         "Apply migrations to dev", "Release dev-suite mutex"]
pos = [idx(n) for n in order]
if -1 in pos or pos != sorted(pos):
    bad.append(f"heavy-job step order broken: {list(zip(order, pos))}")
if "Resolve dev-ledger-parity guard (base-ref copy)" in names:
    bad.append("a separate staging step reopened the extract-then-run window")
ck = step(hv, "Assert unmerged migrations match the dev ledger")
if ck is not None:
    for k in ("if", "continue-on-error"):
        if k in ck:
            bad.append(f"check step carries {k!r}: its verdict could be skipped or ignored")
    env = ck.get("env", {})
    want = {"LEDGER_GUARD": "${{ needs.detect-changes.outputs.ledger_guard }}",
            "HEAD_BRANCH": "${{ github.head_ref || github.ref_name }}",
            "DOPPLER_TOKEN": "${{ secrets.DOPPLER_TOKEN_DEV_SCHEDULED }}"}
    for k, v in want.items():
        if env.get(k) != v:
            bad.append(f"check step env {k} is {env.get(k)!r}")
    if ck.get("shell") is not None:
        bad.append("check step overrides the default shell")
probes = [s for s in hv["steps"] if s.get("uses") == "./.github/actions/dev-migration-drift-probe"]
if len(probes) != 2 or any(p.get("env", {}).get("DLP_OWNERS_CACHE") != "${{ runner.temp }}/dev-ledger-owners" for p in probes):
    bad.append("the two probe calls do not share the owner cache")
print("\n".join(bad))
PY
}

# ----------------------------------------------------------------------
echo "W-0: the real workflow satisfies every structural wiring property (AC3, AC4)"
CASES=$((CASES + 1))
wf_out=$(wf_static "$WF")
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
assert s.count(blk) == 1
s = s.replace(blk, "", 1)
anchor = "      - name: Preflight WORM-vs-cascade contradiction check\n"
assert s.count(anchor) == 1
s = s.replace(anchor, blk + anchor, 1)
'
if [[ -n "$(wf_static "$tmp/wf-mut.yml")" ]]; then pass "misplaced check detected"; else fail "moving the check past apply went unseen"; fi

# ----------------------------------------------------------------------
echo "W-13: continue-on-error or an if: on the check step -> wiring RED (each)"
CASES=$((CASES + 1))
wf_mutant '
h = "      - name: Assert unmerged migrations match the dev ledger\n"
assert s.count(h) == 1
s = s.replace(h, h + "        continue-on-error: true\n", 1)
'
r1=$(wf_static "$tmp/wf-mut.yml")
wf_mutant '
h = "      - name: Assert unmerged migrations match the dev ledger\n"
assert s.count(h) == 1
s = s.replace(h, h + "        if: github.event_name == '"'"'push'"'"'\n", 1)
'
r2=$(wf_static "$tmp/wf-mut.yml")
if [[ -n "$r1" && -n "$r2" ]]; then pass "a discardable verdict is detected"; else fail "continue-on-error/if went unseen: [$r1] [$r2]"; fi

# ----------------------------------------------------------------------
echo "W-14: HEAD_BRANCH or LEDGER_GUARD rewired -> wiring RED"
CASES=$((CASES + 1))
wf_mutant '
o = "HEAD_BRANCH: ${{ github.head_ref || github.ref_name }}"
assert s.count(o) == 1
s = s.replace(o, "HEAD_BRANCH: ${{ github.head_ref }}", 1)
'
r1=$(wf_static "$tmp/wf-mut.yml")
wf_mutant '
o = "LEDGER_GUARD: ${{ needs.detect-changes.outputs.ledger_guard }}"
assert s.count(o) == 1
s = s.replace(o, "LEDGER_GUARD: introduction", 1)
'
r2=$(wf_static "$tmp/wf-mut.yml")
if [[ -n "$r1" && -n "$r2" ]]; then pass "env rewiring detected"; else fail "env rewiring went unseen: [$r1] [$r2]"; fi

# ----------------------------------------------------------------------
echo "W-15: detect-changes loses fetch-depth: 0 -> wiring RED"
CASES=$((CASES + 1))
wf_mutant 's = s.replace("fetch-depth: 0", "fetch-depth: 2", 1)'
if [[ -n "$(wf_static "$tmp/wf-mut.yml")" ]]; then pass "shallow detect-changes detected"; else fail "fetch-depth change went unseen"; fi

# ---- behavioural: the extracted check step, state step and filter, run for real ----
extract_step() {  # $1 = job, $2 = step name or id:<id>, $3 = out file
  python3 - "$WF" "$1" "$2" "$3" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
key = sys.argv[3]
steps = doc["jobs"][sys.argv[2]]["steps"]
if key.startswith("id:"):
    got = [s for s in steps if s.get("id") == key[3:]]
else:
    got = [s for s in steps if s.get("name") == key]
assert len(got) == 1, f"expected one step {key!r}, got {len(got)}"
open(sys.argv[4], "w").write(got[0]["run"])
PY
  if [[ ! -s "$3" ]]; then printf 'FATAL: step extraction for %s is empty\n' "$2" >&2; exit 1; fi
}
CHECK_STEP="$tmp/check-step.sh"; STATE_STEP="$tmp/state-step.sh"; FILTER_STEP="$tmp/filter-step.sh"
extract_step tenant-integration "Assert unmerged migrations match the dev ledger" "$CHECK_STEP"
extract_step detect-changes "Resolve dev-ledger-parity guard state" "$STATE_STEP"
extract_step detect-changes "id:filter" "$FILTER_STEP"

# A small repo pair for the steps: origin2 (bare) and wk2 (the job's checkout).
O2="$tmp/origin2.git"; S2="$tmp/seed2"; W2="$tmp/wk2"; RT="$tmp/runner-temp"
mkdir -p "$RT"
git init -q --bare -b main "$O2"
git clone -q "file://$O2" "$S2" 2>/dev/null
git -C "$S2" switch -q -c main
mkdir -p "$S2/$MDIR" "$S2/apps/web-platform/scripts"
printf 'X\n' > "$S2/$MDIR/001_x.sql"
git -C "$S2" add -A && git -C "$S2" commit -qm base && git -C "$S2" push -q origin main
GUARD_REL="apps/web-platform/scripts/dev-ledger-parity.sh"
set_base_guard() {  # none | empty | <script body>
  mkdir -p "$S2/apps/web-platform/scripts"   # git rm drops the emptied directory
  case "$1" in
    none) git -C "$S2" rm -q --ignore-unmatch "$S2/$GUARD_REL" ;;
    empty) : > "$S2/$GUARD_REL"; git -C "$S2" add -A ;;
    *) printf '%s\n' "$1" > "$S2/$GUARD_REL"; git -C "$S2" add -A ;;
  esac
  git -C "$S2" commit -q --allow-empty -m "base guard: ${1:0:20}" && git -C "$S2" push -q origin main
}
git clone -q "file://$O2" "$W2" 2>/dev/null
git -C "$W2" switch -q -c feat
mkdir -p "$W2/apps/web-platform/scripts"
printf 'echo "ledger-parity: clean (checkout-copy)"\n' > "$W2/$GUARD_REL"
git -C "$W2" add -A && git -C "$W2" commit -qm 'checkout copy of the guard'

run_check_step() {  # $1 = LEDGER_GUARD
  set +e
  out=$(cd "$W2" && LEDGER_GUARD="$1" BASE_REF=main HEAD_BRANCH=feat DOPPLER_TOKEN=x \
    RUNNER_TEMP="$RT" GITHUB_WORKSPACE="$W2" bash --noprofile --norc -eo pipefail "$CHECK_STEP" 2>&1)
  rc=$?
  set -e
}

# ----------------------------------------------------------------------
echo "W-B1: base tip carries the guard -> the BASE copy runs, whatever the state says"
CASES=$((CASES + 1))
set_base_guard 'echo "ledger-parity: clean (base-copy) args=$*"'
run_check_step base; o1=$out; r1=$rc
run_check_step introduction; o2=$out; r2=$rc
if [[ "$r1$r2" == "00" ]] && grep -qF "(base-copy) args=check --base origin/main --repo $W2 --head-branch feat" <<<"$o1" \
  && grep -qF "(base-copy)" <<<"$o2" && ! grep -qF "checkout-copy" <<<"$o1$o2"; then
  pass "a PR cannot substitute its own guard when base has one"
else
  fail "base copy not used: [$r1] $o1 || [$r2] $o2"
fi

# ----------------------------------------------------------------------
echo "W-B2: base lacks the guard -> introduction runs the checkout copy; deleted/unknown/base fail closed"
CASES=$((CASES + 1))
set_base_guard none
run_check_step introduction; oi=$out; ri=$rc
run_check_step deleted; rd=$rc
run_check_step unknown; ru=$rc
run_check_step base; rb=$rc
run_check_step ""; re=$rc
if [[ "$ri" == "0" ]] && grep -qF "checkout-copy" <<<"$oi" && [[ "$rd$ru$rb$re" == "1111" ]]; then
  pass "only the introduction window runs a PR-controlled copy"
else
  fail "state arms wrong: intro=$ri [$oi] deleted=$rd unknown=$ru base=$rb empty=$re"
fi

# ----------------------------------------------------------------------
echo "W-B3: an empty base copy, a silent guard, or a RED guard -> the step fails"
CASES=$((CASES + 1))
set_base_guard empty
run_check_step base; r1=$rc
set_base_guard 'exit 0'
run_check_step base; r2=$rc; o2=$out
set_base_guard 'echo "ledger-parity: RED (violations=1)"; exit 1'
run_check_step base; r3=$rc
if [[ "$r1$r2$r3" == "111" ]] && grep -qF "printed no ledger-parity summary line" <<<"$o2"; then
  pass "a guard that did not measure cannot pass"
else
  fail "expected 1/1/1; got empty=$r1 silent=$r2 [$o2] red=$r3"
fi

run_state_step() {  # $1 = EVENT_NAME, $2 = BASE_REF
  : > "$tmp/gho-state"
  set +e
  out=$(cd "$W2" && EVENT_NAME="$1" BASE_REF="$2" GITHUB_OUTPUT="$tmp/gho-state" \
    bash --noprofile --norc -eo pipefail "$STATE_STEP" 2>&1)
  rc=$?
  set -e
  state=$(sed -n 's/^state=//p' "$tmp/gho-state")
}

# ----------------------------------------------------------------------
echo "W-S1: the detect-changes state step reports base / deleted / introduction / unknown / n/a"
CASES=$((CASES + 1))
# The check step's --depth=1 fetch made this clone shallow; detect-changes is a
# full clone (fetch-depth: 0), so restore full history first.
if [[ -f "$W2/.git/shallow" ]]; then git -C "$W2" fetch -q --unshallow origin; fi
git -C "$W2" fetch -q origin
run_state_step pull_request main; s_base=$state; r1=$rc            # a (RED) guard sits on the base tip
set_base_guard none
git -C "$W2" fetch -q origin
run_state_step pull_request main; s_deleted=$state; r2=$rc
run_state_step pull_request nope; s_unknown=$state; r3=$rc
run_state_step merge_group main; s_na=$state; r4=$rc
git -C "$W2" update-ref refs/remotes/origin/intro "$(git -C "$S2" rev-list --max-parents=0 HEAD)"
run_state_step pull_request intro; s_intro=$state; r5=$rc
if [[ "$r1$r2$r3$r4$r5" == "00000" && "$s_base" == "base" && "$s_deleted" == "deleted" && "$s_unknown" == "unknown" \
  && "$s_na" == "n/a" && "$s_intro" == "introduction" ]]; then
  pass "every state, and the step never exits non-zero"
else
  fail "states: base=$s_base deleted=$s_deleted unknown=$s_unknown na=$s_na intro=$s_intro rcs=$r1$r2$r3$r4$r5"
fi

# ----------------------------------------------------------------------
echo "W-F1: a PR that added then deleted a migration still triggers the suite (A4 needs the heavy job)"
CASES=$((CASES + 1))
git -C "$W2" switch -q -C del-only origin/main
printf 'TMP\n' > "$W2/$MDIR/150_tmp.sql"
git -C "$W2" add -A && git -C "$W2" commit -qm 'add'
git -C "$W2" rm -q "$W2/$MDIR/150_tmp.sql" && git -C "$W2" commit -qm 'delete'
printf 'readme\n' > "$W2/README.md"; git -C "$W2" add -A && git -C "$W2" commit -qm 'unrelated'
: > "$tmp/gho-filter"
set +e
out=$(cd "$W2" && EVENT_NAME=pull_request BASE_REF=main GITHUB_OUTPUT="$tmp/gho-filter" bash --noprofile --norc -eo pipefail "$FILTER_STEP" 2>&1); r1=$?
t1=$(sed -n 's/^tenant=//p' "$tmp/gho-filter")
set -e
git -C "$W2" switch -q -C no-mig origin/main
printf 'readme\n' > "$W2/README.md"; git -C "$W2" add -A && git -C "$W2" commit -qm 'unrelated only'
: > "$tmp/gho-filter"
set +e
out2=$(cd "$W2" && EVENT_NAME=pull_request BASE_REF=main GITHUB_OUTPUT="$tmp/gho-filter" bash --noprofile --norc -eo pipefail "$FILTER_STEP" 2>&1); r2=$?
t2=$(sed -n 's/^tenant=//p' "$tmp/gho-filter")
set -e
if [[ "$r1$r2" == "00" && "$t1" == "true" && "$t2" == "false" ]]; then
  pass "history-only migration changes run the check; unrelated PRs still skip"
else
  fail "filter: del-only=$t1 (rc=$r1 $out) no-mig=$t2 (rc=$r2 $out2)"
fi

# ----------------------------------------------------------------------
echo "W-AC5: action.yml carries the repair, ownership and fail-closed lines; no raw row echo"
CASES=$((CASES + 1))
miss=""
grep -qF 'Repair: knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md §Content drift' "$ACTION" || miss+=" repair"
grep -qF 'dev-ledger-parity.sh check (#8521)' "$ACTION" || miss+=" check-pointer"
grep -qF 'no fresh live branch owns these rows' "$ACTION" || miss+=" ownerless"
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
# ----------------------------------------------------------------------
echo "G1-STUB: no check run issued more than one psql call, or any SQL but the fixed SELECT"
CASES=$((CASES + 1))
if [[ -z "$STUB_BREACHES" ]]; then
  pass "one read-only SELECT per run, every run"
else
  fail "psql contract breached:$STUB_BREACHES"
fi

echo ""
EXPECTED_CASES=99
if [[ "$CASES" -lt "$EXPECTED_CASES" ]]; then
  printf 'FATAL: only %s of %s cases ran — suite is truncated\n' "$CASES" "$EXPECTED_CASES" >&2
  exit 1
fi
# Every case records exactly one verdict: a row that stops counting its verdict
# (or counts two) is caught here, not by the CASES floor above.
if [[ $((PASS + FAIL)) -ne "$CASES" ]]; then
  printf 'FATAL: %s verdicts for %s cases — a case lost or doubled its verdict\n' "$((PASS + FAIL))" "$CASES" >&2
  exit 1
fi
echo "dev-ledger-parity.test.sh: $PASS passed, $FAIL failed ($CASES cases)"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
exit 0
