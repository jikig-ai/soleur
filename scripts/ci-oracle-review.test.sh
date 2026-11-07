#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Sentinel for #10859 (PR3b): the `oracle-review-required` required context.
#
# WHAT THIS PROVES. The driver scripts/ci-oracle-review.sh reports a required context that is
# green ONLY when, on pull_request, the diff's intersection with the BASE commit's RATCHET_ORACLE
# is empty, the PR author is deruelle, or a deruelle APPROVED review is bound to the head SHA
# (commit_id == head); and on merge_group, EVERY member at position <= the anchor has the LATEST
# oracle-review-required check-run (github-actions app 15368, highest id) completed/success. Every
# unknown — an API failure, a truncated enumeration, an unbindable anchor, a missing member
# context, an unreadable base oracle list — is a FAIL, never a green (fail-closed).
#
# The suite does not read GitHub: `gh` and `git` are PATH stubs that answer ONLY the argv shapes
# the driver is allowed to send and exit 64 on anything else (argv fidelity, #7081 class). The
# RATCHET_ORACLE fixture is a real base-side replay.py that the driver must load with `git show`,
# never from the working tree — the re-exec probe (`git show <base>:scripts/ci-oracle-review.sh`)
# is refused, so every row measures the committed HEAD copy.
#
# GUARD 2 MATRIX MAPPING (plan §Guard Contract):
#   row 1 (oracle diff, no bound review)      -> row_review_required
#   row 2 (approval bound to a stale SHA)     -> row_stale_approval
#   row 3 (merge_group enumeration zero /
#          hasNextPage / missing / red)       -> row_mg_zero, row_mg_paginated,
#                                              row_mg_missing_ctx, row_mg_red_ctx, row_mg_anchor
#   row 4 (gh api non-zero)                   -> row_api_fail, row_mg_api_fail
#   row 5 (a PR cannot shrink the list that
#          judges it)                         -> row_oracle_list_unreadable + the base-only
#                                              extraction proven by every PR row
#   row 6 (must-PASS)                         -> row_not_oracle, row_author, row_approved, row_mg_ok
#   row 7 (malformed reviews payload)         -> row_api_malformed
#
# OUTPUT GRAMMAR: exactly one `SOLEUR_ORACLE_REVIEW event=<e> oracle_diff=<0|1> author=<login|->
# approved=<0|1> members=<n> verdict=<pass|fail> reason=<token>` line — fixed tokens only, never a
# path, a SHA or a review URL. Exit 0 on pass, 1 on any fail verdict.
#
# Run: bash scripts/ci-oracle-review.test.sh   (no network, no repo mutation)
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
for _v in ${!GIT_@}; do unset "$_v"; done
unset _v

passes=0
fails=0
FAILURES=()
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1" >&2; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DRIVER="$REPO_ROOT/scripts/ci-oracle-review.sh"
CLA_VERIFY="$REPO_ROOT/scripts/merge-queue-cla-verify.sh"
[ -f "$DRIVER" ] || { printf 'FAIL: %s not found (the review-gate driver is the implementation deliverable)\n' "$DRIVER" >&2; exit 2; }
[ -f "$CLA_VERIFY" ] || { printf 'FAIL: %s not found (the parity source)\n' "$CLA_VERIFY" >&2; exit 2; }

SANDBOX=$(mktemp -d "$TMPDIR/ci-oracle-review-test.XXXXXXXX") || {
  printf 'FAIL: could not create sandbox (mktemp -d failed)\n' >&2; exit 2; }
trap 'rm -rf "$SANDBOX"' EXIT
# Canonical body (plugins/soleur/test/test-helpers.sh), byte-equal by
# plugins/soleur/test/fixture-dir-operand-assert.test.sh: every directory this suite writes into
# must be absolute.
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
assert_fixture_dir "$SANDBOX"

echo "=== oracle-review-required: Guard 2 (driver) (#10859 PR3b) ==="

# ── INSTRUMENT SELF-TEST ─────────────────────────────────────────────────────
_p0=$passes; _f0=$fails
pass; fail "INSTRUMENT SELF-TEST (expected: this row proves fail() increments)" 2> /dev/null
if [ "$passes" -ne $((_p0 + 1)) ] || [ "$fails" -ne $((_f0 + 1)) ]; then
  printf 'FAIL: instrument self-test: pass()/fail() did not both move\n' >&2
  exit 2
fi
fails=$((fails - 1)); unset 'FAILURES[${#FAILURES[@]}-1]'
echo "  instrument self-test: pass() and fail() both move"

# ── the world: fixture files + stub bin ──────────────────────────────────────
FX="$SANDBOX/fx"; BIN="$SANDBOX/bin"; mkdir -p "$FX" "$BIN" "$FX/runs"
assert_fixture_dir "$FX"; assert_fixture_dir "$BIN"; assert_fixture_dir "$FX/runs"

GH_SHA=5555555555555555555555555555555555555555
BASE_SHA=6666666666666666666666666666666666666666
HEAD_SHA_PR=1111111111111111111111111111111111111111
MG_SHA=ffffffffffffffffffffffffffffffffffffffff

# A real base-side replay.py: the driver must extract RATCHET_ORACLE from THIS (`git show`),
# never from a working-tree copy.
cat > "$FX/replay-base.py" <<'PY'
RATCHET_ORACLE = (".github/workflows/ci.yml", "scripts/ci-pr-affected-replay.py",
                  "scripts/ci-pr-affected-audit.accept.tsv", "scripts/lib/test-affected-paths.sh",
                  "scripts/test-all.sh", "scripts/oracle-only-fixture.txt")
PY

# Diff listings (one path per line).
printf 'docs/readme.md\n' > "$FX/diff-docs.txt"
printf 'scripts/ci-pr-affected-audit.accept.tsv\n' > "$FX/diff-oracle.txt"
printf 'scripts/oracle-only-fixture.txt\n' > "$FX/diff-oracle-weak.txt"

# Review payloads: none; APPROVED by deruelle on a stale commit_id; APPROVED bound to head sha.
cat > "$FX/reviews-none.json" <<'JSON'
[{"id":1,"state":"COMMENTED","commit_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","user":{"login":"someone"}}]
JSON
cat > "$FX/reviews-stale.json" <<'JSON'
[{"id":2,"state":"APPROVED","commit_id":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","user":{"login":"deruelle"}}]
JSON
cat > "$FX/reviews-bound.json" <<'JSON'
[{"id":3,"state":"APPROVED","commit_id":"1111111111111111111111111111111111111111","user":{"login":"deruelle"}},
 {"id":4,"state":"APPROVED","commit_id":"cccccccccccccccccccccccccccccccccccccccc","user":{"login":"other"}}]
JSON
cat > "$FX/reviews-malformed.json" <<'JSON'
[{"id":9,"state":"APPROVED","commit_id":42,"user":"deruelle"}
JSON

# merge_group enumeration payloads. Anchor = the entry whose headCommit.oid == HEAD_SHA (ffff).
cat > "$FX/mq-ok.json" <<'JSON'
{"data":{"repository":{"mergeQueue":{"entries":{"pageInfo":{"hasNextPage":false},"nodes":[
 {"position":1,"headCommit":{"oid":"dddddddddddddddddddddddddddddddddddddddd"},"pullRequest":{"number":101,"headRefOid":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}},
 {"position":2,"headCommit":{"oid":"ffffffffffffffffffffffffffffffffffffffff"},"pullRequest":{"number":102,"headRefOid":"1111111111111111111111111111111111111111"}}]}}}}}
JSON
cat > "$FX/mq-missing.json" <<'JSON'
{"data":{"repository":{"mergeQueue":{"entries":{"pageInfo":{"hasNextPage":false},"nodes":[
 {"position":1,"headCommit":{"oid":"dddddddddddddddddddddddddddddddddddddddd"},"pullRequest":{"number":101,"headRefOid":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}},
 {"position":2,"headCommit":{"oid":"ffffffffffffffffffffffffffffffffffffffff"},"pullRequest":{"number":102,"headRefOid":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}]}}}}}
JSON
cat > "$FX/mq-red.json" <<'JSON'
{"data":{"repository":{"mergeQueue":{"entries":{"pageInfo":{"hasNextPage":false},"nodes":[
 {"position":1,"headCommit":{"oid":"dddddddddddddddddddddddddddddddddddddddd"},"pullRequest":{"number":101,"headRefOid":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}},
 {"position":2,"headCommit":{"oid":"ffffffffffffffffffffffffffffffffffffffff"},"pullRequest":{"number":102,"headRefOid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}]}}}}}
JSON
cat > "$FX/mq-paginated.json" <<'JSON'
{"data":{"repository":{"mergeQueue":{"entries":{"pageInfo":{"hasNextPage":true},"nodes":[
 {"position":1,"headCommit":{"oid":"dddddddddddddddddddddddddddddddddddddddd"},"pullRequest":{"number":101,"headRefOid":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}}]}}}}}
JSON
cat > "$FX/mq-empty.json" <<'JSON'
{"data":{"repository":{"mergeQueue":{"entries":{"pageInfo":{"hasNextPage":false},"nodes":[]}}}}}
JSON
cat > "$FX/mq-noanchor.json" <<'JSON'
{"data":{"repository":{"mergeQueue":{"entries":{"pageInfo":{"hasNextPage":false},"nodes":[
 {"position":1,"headCommit":{"oid":"dddddddddddddddddddddddddddddddddddddddd"},"pullRequest":{"number":101,"headRefOid":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}},
 {"position":2,"headCommit":{"oid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},"pullRequest":{"number":103,"headRefOid":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}]}}}}}
JSON
# Member check-run pages (one file per member headRefOid's first 4 hex).
cat > "$FX/runs/eeee.json" <<'JSON'
{"check_runs":[{"name":"oracle-review-required","status":"completed","conclusion":"success","id":50,"app":{"id":15368}}]}
JSON
cat > "$FX/runs/1111.json" <<'JSON'
{"check_runs":[{"name":"oracle-review-required","status":"completed","conclusion":"success","id":51,"app":{"id":15368}}]}
JSON
cat > "$FX/runs/bbbb.json" <<'JSON'
{"check_runs":[{"name":"test","status":"completed","conclusion":"success","id":60,"app":{"id":15368}}]}
JSON
cat > "$FX/runs/aaaa.json" <<'JSON'
{"check_runs":[{"name":"oracle-review-required","status":"completed","conclusion":"failure","id":70,"app":{"id":15368}},
               {"name":"oracle-review-required","status":"completed","conclusion":"success","id":69,"app":{"id":15368}}]}
JSON

# ── the stubs ────────────────────────────────────────────────────────────────
# git: rev-list --parents -n 1 HEAD -> GITHUB_SHA BASE_SHA PR_HEAD_SHA (a merge ref);
#      diff --name-only --no-renames <base> HEAD -- -> $STUB_GIT_DIFF;
#      show <sha>:scripts/ci-pr-affected-replay.py -> $STUB_GIT_SHOW;
#      show <sha>:scripts/ci-oracle-review.sh -> absent at base (exit 1, NOT 64: a legitimately
#      missing path, so the driver runs its HEAD copy — that IS the arm under test).
cat > "$BIN/git" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
printf 'git %s\n' "$*" >> "${STUB_CALLS:?}"
case "${1-}" in
  rev-list)
    [ "${2-} ${3-} ${4-} ${5-}" = "--parents -n 1 HEAD" ] || exit 64
    printf '%s %s %s\n' "$STUB_GH_SHA" "$STUB_BASE_SHA" "$STUB_HEAD_SHA"; exit 0 ;;
  diff)
    names=0; for a in "$@"; do case "$a" in --name-only) names=1 ;; esac; done
    [ "$names" = 1 ] || exit 64
    [ -n "${STUB_GIT_DIFF:-}" ] && [ -f "$STUB_GIT_DIFF" ] || { printf 'stub-git: no diff fixture\n' >&2; exit 65; }
    cat "$STUB_GIT_DIFF"; exit 0 ;;
  show)
    case "${2-}" in
      *:scripts/ci-pr-affected-replay.py)
        [ -n "${STUB_GIT_SHOW:-}" ] && [ -f "$STUB_GIT_SHOW" ] || { printf 'stub-git: no base replay\n' >&2; exit 65; }
        cat "$STUB_GIT_SHOW"; exit 0 ;;
      *:scripts/ci-oracle-review.sh) exit 1 ;;   # the base lacks the driver (every pre-PR3b base)
      *) exit 64 ;;
    esac ;;
  *) exit 64 ;;
esac
SH
chmod +x "$BIN/git"

# gh: `gh api [--paginate] repos/<repo>/pulls/<n>/reviews`,
#     `gh api graphql -f query=<q> -F o=<o> -F n=<n>`,
#     `gh api --paginate repos/<repo>/commits/<sha>/check-runs?filter=all&per_page=100`.
# $STUB_GH_FAIL=1 forces exit 3 on every call (the API-failure arm).
cat > "$BIN/gh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
printf 'gh %s\n' "$*" >> "${STUB_CALLS:?}"
[ "${STUB_GH_FAIL:-0}" = 1 ] && { printf 'gh: simulated api failure\n' >&2; exit 3; }
[ "${1-}" = api ] || exit 64
shift
[ "${1-}" = --paginate ] && shift
case "${1-}" in
  graphql)
    [ -n "${STUB_GH_MQ:-}" ] && [ -f "$STUB_GH_MQ" ] || { printf 'stub-gh: no mq fixture\n' >&2; exit 65; }
    cat "$STUB_GH_MQ"; exit 0 ;;
  repos/*/*/pulls/*/reviews)
    [ -n "${STUB_GH_REVIEWS:-}" ] && [ -f "$STUB_GH_REVIEWS" ] || { printf 'stub-gh: no reviews fixture\n' >&2; exit 65; }
    cat "$STUB_GH_REVIEWS"; exit 0 ;;
  repos/*/*/commits/*/check-runs*)
    [ -n "${STUB_GH_RUNS:-}" ] || exit 64
    sha="${1##*/commits/}"; sha="${sha%%/*}"
    f="$STUB_GH_RUNS/${sha:0:4}.json"
    [ -f "$f" ] || { printf 'stub-gh: no runs fixture for %s\n' "$sha" >&2; exit 65; }
    cat "$f"; exit 0 ;;
  *) exit 64 ;;
esac
SH
chmod +x "$BIN/gh"

# ── the check primitive ──────────────────────────────────────────────────────
# run_sut <driver?> <env assignments...> — the driver under PATH stubs, CWD = sandbox.
# RC, OUT (stdout), ERR (stderr). A stub refusing argv (64/65) always shows on stderr.
run_sut() {
  local drv="${1:-$DRIVER}"; shift
  local e="$SANDBOX/err.txt"
  : > "$SANDBOX/calls.log"
  RC=0
  OUT="$(cd "$SANDBOX" && env -i PATH="$BIN:/usr/bin:/bin" HOME="$SANDBOX" TMPDIR="$SANDBOX" RUNNER_TEMP="$SANDBOX" \
      STUB_CALLS="$SANDBOX/calls.log" \
      STUB_GH_SHA="$GH_SHA" STUB_BASE_SHA="$BASE_SHA" STUB_HEAD_SHA="$HEAD_SHA_PR" \
      STUB_GIT_SHOW="${STUB_GIT_SHOW:-$FX/replay-base.py}" STUB_GIT_DIFF="${STUB_GIT_DIFF:-}" \
      STUB_GH_REVIEWS="${STUB_GH_REVIEWS:-}" STUB_GH_MQ="${STUB_GH_MQ:-}" \
      STUB_GH_RUNS="$FX/runs" STUB_GH_FAIL="${STUB_GH_FAIL:-0}" \
      MQ_VERIFY_RETRY_DELAY=0 \
      "$@" bash "$drv" 2>"$e")" || RC=$?
  ERR="$(<"$e")"
  if grep -qE 'stub-(git|gh)' <<<"$ERR"; then
    printf 'STUB-MISS %s\n' "$ERR" >&2
  fi
  return 0
}

# want <label> <want-rc> <want-reason-regex> — verdict + marker grammar in one assert.
want() {
  local label="$1" wrc="$2" wreason="$3" marker gverdict greason
  marker="$(grep -E '^SOLEUR_ORACLE_REVIEW ' <<<"$OUT" | tail -1)"
  if [ "$RC" -ne "$wrc" ]; then
    printf 'row %s: rc %d, want %d (out=%s err=%s)\n' "$label" "$RC" "$wrc" "$OUT" "$ERR" >&2
    return 1
  fi
  [ -n "$marker" ] || { printf 'row %s: no SOLEUR_ORACLE_REVIEW marker (out=%s)\n' "$label" "$OUT" >&2; return 1; }
  [[ "$marker" =~ ^SOLEUR_ORACLE_REVIEW\ event=[a-z_]+\ oracle_diff=[01]\ author=[A-Za-z0-9-]+\ approved=[01]\ members=[0-9]+\ verdict=(pass|fail)\ reason=([a-z-]+)$ ]] \
    || { printf 'row %s: marker off grammar: %s\n' "$label" "$marker" >&2; return 1; }
  gverdict="${BASH_REMATCH[1]}"; greason="${BASH_REMATCH[2]}"
  [[ "$greason" =~ ^$wreason$ ]] || { printf 'row %s: reason=%s, want %s\n' "$label" "$greason" "$wreason" >&2; return 1; }
  [ "$(grep -cE '^SOLEUR_ORACLE_REVIEW ' <<<"$OUT")" -eq 1 ] || { printf 'row %s: marker not unique\n' "$label" >&2; return 1; }
  if { [ "$wrc" = 0 ] && [ "$gverdict" != pass ]; } || { [ "$wrc" != 0 ] && [ "$gverdict" != fail ]; }; then
    printf 'row %s: verdict=%s for rc=%s\n' "$label" "$gverdict" "$wrc" >&2; return 1
  fi
  return 0
}

PR_ENV=(EVENT_NAME=pull_request PR_NUMBER=7 REPO=owner/repo GITHUB_SHA="$GH_SHA" PR_HEAD_SHA="$HEAD_SHA_PR")
MG_ENV=(EVENT_NAME=merge_group REPO=owner/repo BASE_REF=refs/heads/main
        HEAD_SHA="$MG_SHA" HEAD_REF="refs/heads/gh-readonly-queue/main/pr-102-$MG_SHA")

row_review_required() {
  STUB_GIT_DIFF="$FX/diff-oracle.txt" STUB_GH_REVIEWS="$FX/reviews-none.json" \
    run_sut "$DRIVER" "${PR_ENV[@]}" PR_AUTHOR=alice
  want review-required 1 'review-required'
}
row_stale_approval() {
  STUB_GIT_DIFF="$FX/diff-oracle.txt" STUB_GH_REVIEWS="$FX/reviews-stale.json" \
    run_sut "$DRIVER" "${PR_ENV[@]}" PR_AUTHOR=alice
  want stale-approval 1 'stale-approval'
}
row_approved() {
  STUB_GIT_DIFF="$FX/diff-oracle.txt" STUB_GH_REVIEWS="$FX/reviews-bound.json" \
    run_sut "$DRIVER" "${PR_ENV[@]}" PR_AUTHOR=alice
  want approved 0 'approved'
}
row_author() {
  STUB_GIT_DIFF="$FX/diff-oracle.txt" \
    run_sut "$DRIVER" "${PR_ENV[@]}" PR_AUTHOR=deruelle
  want author 0 'author'
}
row_not_oracle() {
  STUB_GIT_DIFF="$FX/diff-docs.txt" \
    run_sut "$DRIVER" "${PR_ENV[@]}" PR_AUTHOR=alice
  want not-oracle 0 'not-oracle'
}
row_api_fail() {
  STUB_GIT_DIFF="$FX/diff-oracle.txt" STUB_GH_FAIL=1 \
    run_sut "$DRIVER" "${PR_ENV[@]}" PR_AUTHOR=alice
  want api-fail 1 'api'
}
row_api_malformed() {
  STUB_GIT_DIFF="$FX/diff-oracle.txt" STUB_GH_REVIEWS="$FX/reviews-malformed.json" \
    run_sut "$DRIVER" "${PR_ENV[@]}" PR_AUTHOR=alice
  want api-malformed 1 'api'
}
row_oracle_list_unreadable() {
  STUB_GIT_SHOW="$FX/no-such-base.py" STUB_GIT_DIFF="$FX/diff-oracle.txt" \
    run_sut "$DRIVER" "${PR_ENV[@]}" PR_AUTHOR=alice
  want oracle-list-unreadable 1 'api'
}
row_mg_ok() {
  STUB_GH_MQ="$FX/mq-ok.json" run_sut "$DRIVER" "${MG_ENV[@]}"
  want mg-ok 0 'members-green'
}
row_mg_missing_ctx() {
  STUB_GH_MQ="$FX/mq-missing.json" run_sut "$DRIVER" "${MG_ENV[@]}"
  want mg-missing 1 'member-context'
}
row_mg_red_ctx() {
  STUB_GH_MQ="$FX/mq-red.json" run_sut "$DRIVER" "${MG_ENV[@]}"
  want mg-red 1 'member-context'
}
row_mg_paginated() {
  STUB_GH_MQ="$FX/mq-paginated.json" run_sut "$DRIVER" "${MG_ENV[@]}"
  want mg-paginated 1 'pagination'
}
row_mg_zero() {
  STUB_GH_MQ="$FX/mq-empty.json" run_sut "$DRIVER" "${MG_ENV[@]}"
  want mg-zero 1 'anchor|member-context'
}
row_mg_anchor() {
  STUB_GH_MQ="$FX/mq-noanchor.json" run_sut "$DRIVER" "${MG_ENV[@]}"
  want mg-anchor 1 'anchor'
}
row_mg_api_fail() {
  STUB_GH_MQ="$FX/mq-ok.json" STUB_GH_FAIL=1 run_sut "$DRIVER" "${MG_ENV[@]}"
  want mg-api-fail 1 'api'
}
row_event_guard() {
  run_sut "$DRIVER" EVENT_NAME=push REPO=owner/repo
  want event-guard 1 'event'
}

chk() {  # chk <label> <row fn>
  local label="$1" fn="$2"
  if "$fn"; then pass; else fail "$label"; fi
}

for row in row_review_required row_stale_approval row_approved row_author row_not_oracle \
           row_api_fail row_api_malformed row_oracle_list_unreadable \
           row_mg_ok row_mg_missing_ctx row_mg_red_ctx row_mg_paginated row_mg_zero \
           row_mg_anchor row_mg_api_fail row_event_guard; do
  chk "$row" "$row"
done

# ── mutation battery: the guard's own axes ───────────────────────────────────
# mutate <name> <sed old> <sed new> <row fn>: apply one sed to a copy; the row must still FAIL
# its expectation (a killed mutant) — a copy that now PASSES means the suite measured nothing.
MUT="$SANDBOX/mut"
MUT_SURVIVED=0
mutate() {
  local name="$1" old="$2" new="$3" row="$4"
  cp "$DRIVER" "$MUT" || { printf '[FATAL] mutation copy\n' >&2; exit 2; }
  sed -i "s|$old|$new|" "$MUT"
  cmp -s "$DRIVER" "$MUT" && { printf '[FATAL] mutation %s did not land\n' "$name" >&2; exit 2; }
  # row() expects the pristine FAIL verdict: want() returns 0 when the mutated copy still fails
  # the same way — undetected, a SURVIVOR. A non-zero row means the mutation changed the verdict
  # (the fixture caught it) — killed.
  if "$row" "$MUT"; then
    printf 'MUTANT SURVIVED %s\n' "$name" >&2
    MUT_SURVIVED=$((MUT_SURVIVED + 1))
  fi
}

# a mutant that binds approvals to ANY sha must still red on the stale-approval fixture
mut_row_stale() { STUB_GIT_DIFF="$FX/diff-oracle.txt" STUB_GH_REVIEWS="$FX/reviews-stale.json" run_sut "$1" "${PR_ENV[@]}" PR_AUTHOR=alice; want mut-stale 1 'stale-approval|review-required|api'; }
# a mutant that drops the latest-run (highest id) rule must still red on the red member fixture
mut_row_red() { STUB_GH_MQ="$FX/mq-red.json" run_sut "$1" "${MG_ENV[@]}"; want mut-red 1 'member-context|anchor'; }
# a mutant that turns a member-context miss into a pass must still red on the missing fixture
mut_row_missing() { STUB_GH_MQ="$FX/mq-missing.json" run_sut "$1" "${MG_ENV[@]}"; want mut-miss 1 'member-context|anchor'; }

grep -q 'commit_id == \$sha' "$DRIVER" || { printf '[FATAL] driver names no commit_id binding to mutate\n' >&2; exit 2; }
mutate binding-dropped ' and \.commit_id == \$sha' '' mut_row_stale
mutate latest-run-lost '\x7c last' '\x7c first' mut_row_red
mutate missing-is-pass '"missing"' '"completed/success"' mut_row_missing
if [ "$MUT_SURVIVED" -gt 0 ]; then
  fail "mutation battery: $MUT_SURVIVED mutant(s) survived"
else
  pass
fi

# ── parity pin: the merge_group enumeration is a byte-copy of cla-verify's ─────
# The driver's enumeration block must equal merge-queue-cla-verify.sh's member-enumeration body
# with only the context list changed (cla-check cla-evidence -> oracle-review-required).
# _par <file>: extract the MQ_QUERY .. `done < <(...)` enumeration extent.
_par() {
  awk '/^ *MQ_QUERY=/{f=1} f{print} /^ *done < </{if(f) exit}' "$1"
}
_p_src="$(_par "$CLA_VERIFY")"
_p_drv="$(_par "$DRIVER")"
if [ -z "$_p_src" ] || [ -z "$_p_drv" ]; then
  fail "PARITY: enumeration block not extractable (src=$(printf '%s' "$_p_src" | wc -l) drv=$(printf '%s' "$_p_drv" | wc -l) lines)"
else
  # normalize: (a) the copy sits inside mg_arm() — strip the two-space indent it adds;
  # (b) the context list cla-check cla-evidence -> oracle-review-required, in that order so the
  # pair maps to one name, never two.
  _p_src_n="$(printf '%s\n' "$_p_src" \
    | sed 's/cla-check cla-evidence/oracle-review-required/g; s/cla-check/oracle-review-required/g; s/cla-evidence/oracle-review-required/g')"
  _p_drv_n="$(printf '%s\n' "$_p_drv" | sed 's/^  //')"
  if [ "$_p_src_n" = "$_p_drv_n" ]; then
    pass
  else
    fail "PARITY: enumeration copy diverges from merge-queue-cla-verify.sh beyond the context names"
  fi
fi
unset _p_src _p_drv _p_src_n _p_drv_n

# ── job wiring (structural-enumeration P1, #12329): the required context's producer ──
# coverage on pull_request was asserted only by comments. Pin the ci.yml job block's `if:`
# shape (the positive pull_request || merge_group form), the absence of needs: and
# job-level continue-on-error, and the checks:read scope the merge_group arm requires.
_wf="$(awk '/^  oracle-review-required:/{f=1;next} f&&/^  [a-zA-Z0-9_-]+:/{f=0} f' "$REPO_ROOT/.github/workflows/ci.yml")"
[ -n "$_wf" ] || { echo "[FATAL] oracle-review-required job block not extractable from ci.yml" >&2; exit 2; }
chk "job wiring: if: is the positive pull_request || merge_group form (PR coverage producer)" \
  bash -c "grep -qE \"if: github.event_name == 'pull_request' \\\\|\\\\| github.event_name == 'merge_group'\" <<<\"$_wf\""
chk "job wiring: no needs: edge (a required context waits on nothing)" \
  bash -c "! grep -qE '^\\s+needs:' <<<\"$_wf\""
chk "job wiring: no job-level continue-on-error (a required job that cannot red the run is decorative)" \
  bash -c "! grep -qE '^\\s+continue-on-error:' <<<\"$_wf\""
chk "job wiring: checks: read granted (the merge_group arm reads member check-runs — P1 #12329)" \
  bash -c "grep -qE '^\\s+checks: read' <<<\"$_wf\""
chk "job wiring: timeout-minutes present (a hung gate must not hold the runner)" \
  bash -c "grep -qE '^\\s+timeout-minutes:' <<<\"$_wf\""
unset _wf

# ── verdict accounting ───────────────────────────────────────────────────────
printf '\n%d passed, %d failed\n' "$passes" "$fails"
if [ "$fails" -gt 0 ]; then
  printf 'FAILED rows:\n' >&2
  printf '  - %s\n' "${FAILURES[@]}" >&2
  exit 1
fi
exit 0
