#!/usr/bin/env bash
# Hermetic cases for plugins/soleur/scripts/sync-pr-behind.sh:
#   CLEAN  → exit 0, no merge
#   BEHIND + merge-tree clean → merge + push
#   DIRTY  + merge-tree rc=0  → merge + push (the kb-index GitHub-DIRTY class)
#   DIRTY  + merge-tree rc≠0  → exit 6
#   BEHIND + merge in progress (staged resolution) → exit 9, nothing aborted (#8339)
#   --step: every exit code on real git (0/6/7/9/10/11), trace-env hygiene,
#   unmapped-main refspec; standalone: wrong branch (12), exhausted (8), gh failure (4);
#   argv strictness; the tag-shape contract over every line emitted above.
#   merge queue (#9454): a PR that is in the merge queue is skipped (kind=queued, rc 0,
#   no merge, no push — a push would dequeue it); a failed queue read is kind=gh, never
#   "not queued". The gh stub serves the RAW GraphQL body, projected to the fields the
#   query names, and runs the --jq the SUT passes, so the real query and verdict program
#   execute (realistic shapes: queued, not queued, dequeued, merged, null PR, malformed).
#   A transient read failure is retried; a hung read is killed; queued → gone is
#   kind=dequeued (rc 13). `--queue-state` prints `dequeued` ONCE for a marker-only dequeue (the report consumes the
#   marker; a re-armed PR is not reported again) — pinned by the consume rows and two mutation rows.
#
# Synthesized file:// repos. PATH-shimmed `gh`. No network.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SUT="$REPO_ROOT/plugins/soleur/scripts/sync-pr-behind.sh"

# test-helpers.sh owns assert_fixture_dir -- the guard the fixture scanners
# (fixture-relative-assert, fixture-dir-operand-assert) recognize -- and
# git_fixture_env, the hermetic env for this suite's git fixture writes. It
# sets -euo pipefail, so the +e below restores this suite's
# accumulate-then-exit contract.
# Owning trap installed BEFORE the helper is sourced: test-helpers.sh composes its
# incident-sandbox cleanup over an existing EXIT trap, whereas a trap installed
# afterwards replaces it and leaks the sandbox on every run (#8339 review).
FIXTURES=()
cleanup_fixtures() { rm -rf ${FIXTURES[@]+"${FIXTURES[@]}"}; }
trap cleanup_fixtures EXIT
# shellcheck source=plugins/soleur/test/test-helpers.sh
source "$REPO_ROOT/plugins/soleur/test/test-helpers.sh" || { echo "FATAL: could not source test-helpers.sh" >&2; exit 2; }
set +e -uo pipefail

# The queue read retries a transient failure after PR_QUEUE_RETRY_SLEEP seconds; the suite does not wait.
export PR_QUEUE_RETRY_SLEEP=0
# The queue rows use a PR number other than 1 so a hardcoded `-F number=1` cannot pass.
QUEUE_PR=4242

PASS=0; FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }


# The SUT operates on $PWD by design (it syncs the CALLER's worktree). That makes an
# un-cd'd invocation a live-repo hazard, so every case below runs inside `( cd "$X/work" && … )`
# and this guard turns a failed cd into an abort rather than a silent fall-through to the
# runner's own checkout. Before the BASH_SOURCE escape was removed the SUT's own `cd` masked
# this; it was protection by accident, and it was the same line that made the script sync the
# wrong repository in production.
assert_in_fixture() {
  local want="$1"
  [[ "$PWD" == "$want" ]] || { echo "FATAL: fixture cd failed, refusing to run against $PWD" >&2; exit 97; }
}

make_pair() {
  local d="$1"
  assert_fixture_dir "$d"
  git_fixture_env "$d" || return 1
  git init -q --bare "$d/origin.git"
  git clone -q "file://$d/origin.git" "$d/work"
  git -C "$d/work" config user.email t@t
  git -C "$d/work" config user.name t
  echo base > "$d/work/f"
  git -C "$d/work" add f && git -C "$d/work" commit -q -m base
  git -C "$d/work" branch -M main
  git -C "$d/work" push -q origin main
  git -C "$d/work" checkout -q -b feat
  echo feat > "$d/work/g"
  git -C "$d/work" add g && git -C "$d/work" commit -q -m feat
  git -C "$d/work" push -q -u origin feat
  # SUT computes REPO_ROOT from BASH_SOURCE and `cd`s there. Copy it into
  # the temp tree so a run cannot fetch/merge/push the live worktree.
  mkdir -p "$d/work/plugins/soleur/scripts"
  cp "$SUT" "$d/work/plugins/soleur/scripts/sync-pr-behind.sh"
}

# `gh api graphql` stub (#9454). It behaves like gh: serves the RAW GraphQL body for the PR in
# gql-pr, keeps only the PR fields the QUERY names (GitHub returns exactly the requested
# fields, so a query that lost isInMergeQueue gets an answer without it), and runs the
# `--jq` program the SUT passed over that body. Nothing here knows the verdict labels.
# Records per call: gql-calls (argv), gql-query (the query text alone), gql-number (the -F
# number), gql-jq. Modes (gql-mode, re-read every call): queued | notqueued (armed) |
# entryonly (an entry but no isInMergeQueue) | dequeued (auto-merge disarmed) | merged | prnull | datanull | shapeless | notjson |
# gqlfail | empty | hang | flaky (first call fails, then notqueued) | removed (not queued, auto-merge still
# armed, a RemovedFromMergeQueueEvent newer than the re-arm) | removed_disarmed | rearmed (removal OLDER than
# the re-arm: not current) | removed_pushed (removal OLDER than the head commit: a fix was pushed since) |
# landing (first call: not queued, OPEN; later calls: MERGED — the queue's own merge landing between two reads).
# Projection is by TOP-LEVEL field of the query's pullRequest selection (nested braces stripped), so a
# query that loses `state`, `autoMergeRequest`, `timelineItems` or `commits` gets an answer without it.
install_gql() {  # <bin> <mode> [pr]
  local bin="$1" mode="$2" pr="${3:-1}"
  assert_fixture_dir "$bin"
  mkdir -p "$bin"
  printf '%s\n' "$mode" > "$bin/gql-mode"; printf '%s\n' "$pr" > "$bin/gql-pr"
  cat > "$bin/gql-stub" <<'STUB'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")" && pwd)"
mode="$(cat "$d/gql-mode")"
n=""; q=""; jqx=""; prev=""
for a in "$@"; do
  case "$prev" in
    -F) [[ "$a" == number=* ]] && n="${a#number=}" ;;
    -f) [[ "$a" == query=* ]] && q="${a#query=}" ;;
    --jq) jqx="$a" ;;
  esac
  prev="$a"
done
echo "$*" >> "$d/gql-calls"; printf '%s\n' "$q" > "$d/gql-query"; printf '%s\n' "$n" >> "$d/gql-number"; printf '%s\n' "$jqx" > "$d/gql-jq"
cnt=$(( $(cat "$d/gql-count" 2>/dev/null || echo 0) + 1 )); echo "$cnt" > "$d/gql-count"
case "$mode" in
  flaky)    if [[ "$cnt" -eq 1 ]]; then echo "gh: HTTP 502 from fixture (graphql)" >&2; exit 1; fi; mode=notqueued ;;
  gqlfail)  echo "gh: HTTP 502 from fixture (graphql)" >&2; exit 1 ;;
  hang)     exec sleep 8 ;;
  empty)    exit 0 ;;
esac
if [[ "$n" != "$(cat "$d/gql-pr")" ]]; then
  echo "GraphQL: Could not resolve to a PullRequest with the number of $n. (repository.pullRequest)" >&2; exit 1
fi
body=""; pr=""
case "$mode" in
  queued)     pr='{"isInMergeQueue":true,"mergeQueueEntry":{"state":"QUEUED"},"state":"OPEN","autoMergeRequest":{"enabledAt":"2026-10-04T00:00:00Z"},"timelineItems":{"nodes":[]},"commits":{"nodes":[{"commit":{"committedDate":"2026-10-04T00:00:00Z"}}]}}' ;;
  notqueued)  pr='{"isInMergeQueue":false,"mergeQueueEntry":null,"state":"OPEN","autoMergeRequest":{"enabledAt":"2026-10-04T00:00:00Z"},"timelineItems":{"nodes":[]},"commits":{"nodes":[{"commit":{"committedDate":"2026-10-04T00:00:00Z"}}]}}' ;;
  entryonly)  pr='{"mergeQueueEntry":{"state":"AWAITING_CHECKS"},"state":"OPEN","autoMergeRequest":{"enabledAt":"2026-10-04T00:00:00Z"},"timelineItems":{"nodes":[]},"commits":{"nodes":[{"commit":{"committedDate":"2026-10-04T00:00:00Z"}}]}}' ;;
  dequeued)   pr='{"isInMergeQueue":false,"mergeQueueEntry":null,"state":"OPEN","autoMergeRequest":null,"timelineItems":{"nodes":[]},"commits":{"nodes":[{"commit":{"committedDate":"2026-10-04T00:00:00Z"}}]}}' ;;
  merged)     pr='{"isInMergeQueue":false,"mergeQueueEntry":null,"state":"MERGED","autoMergeRequest":null,"timelineItems":{"nodes":[]},"commits":{"nodes":[{"commit":{"committedDate":"2026-10-04T00:00:00Z"}}]}}' ;;
  removed)    pr='{"isInMergeQueue":false,"mergeQueueEntry":null,"state":"OPEN","autoMergeRequest":{"enabledAt":"2026-10-04T00:00:00Z"},"timelineItems":{"nodes":[{"reason":"checks_timed_out","createdAt":"2026-10-04T01:00:00Z"}]},"commits":{"nodes":[{"commit":{"committedDate":"2026-10-04T00:00:00Z"}}]}}' ;;
  removed_disarmed) pr='{"isInMergeQueue":false,"mergeQueueEntry":null,"state":"OPEN","autoMergeRequest":null,"timelineItems":{"nodes":[{"reason":"checks_timed_out","createdAt":"2026-10-04T01:00:00Z"}]},"commits":{"nodes":[{"commit":{"committedDate":"2026-10-04T00:00:00Z"}}]}}' ;;
  rearmed)    pr='{"isInMergeQueue":false,"mergeQueueEntry":null,"state":"OPEN","autoMergeRequest":{"enabledAt":"2026-10-04T02:00:00Z"},"timelineItems":{"nodes":[{"reason":"checks_timed_out","createdAt":"2026-10-04T01:00:00Z"}]},"commits":{"nodes":[{"commit":{"committedDate":"2026-10-04T00:00:00Z"}}]}}' ;;
  removed_pushed) pr='{"isInMergeQueue":false,"mergeQueueEntry":null,"state":"OPEN","autoMergeRequest":{"enabledAt":"2026-10-04T00:00:00Z"},"timelineItems":{"nodes":[{"reason":"checks_timed_out","createdAt":"2026-10-04T01:00:00Z"}]},"commits":{"nodes":[{"commit":{"committedDate":"2026-10-04T03:00:00Z"}}]}}' ;;
  landing)    if [[ -e "$d/gql-landed" ]]; then pr='{"isInMergeQueue":false,"mergeQueueEntry":null,"state":"MERGED","autoMergeRequest":null,"timelineItems":{"nodes":[]},"commits":{"nodes":[{"commit":{"committedDate":"2026-10-04T00:00:00Z"}}]}}'
              else pr='{"isInMergeQueue":false,"mergeQueueEntry":null,"state":"OPEN","autoMergeRequest":{"enabledAt":"2026-10-04T00:00:00Z"},"timelineItems":{"nodes":[]},"commits":{"nodes":[{"commit":{"committedDate":"2026-10-04T00:00:00Z"}}]}}'; touch "$d/gql-landed"; fi ;;
  shapeless)  pr='{}' ;;
  prnull)     body='{"data":{"repository":{"pullRequest":null}}}' ;;
  datanull)   body='{"data":null,"errors":[{"message":"boom"}]}' ;;
  notjson)    body='<html>502 Bad Gateway</html>' ;;
esac
if [[ -z "$body" ]]; then
  # Keep only the TOP-LEVEL fields of the pullRequest selection: a bare substring test would see the
  # nested `mergeQueueEntry { state }` and keep a top-level `state` the query no longer asks for.
  tops=" $(printf '%s' "$q" | tr '\n' ' ' | sed -E 's/.*pullRequest\(number: \$number\) *\{//') "
  while :; do t2="$(sed -E 's/\{[^{}]*\}//g' <<<"$tops")"; [[ "$t2" == "$tops" ]] && break; tops="$t2"; done
  for f in isInMergeQueue mergeQueueEntry state autoMergeRequest timelineItems commits; do
    [[ "$tops" =~ (^|[^A-Za-z_])${f}([^A-Za-z_]|$) ]] || pr="$(jq -c "del(.$f)" <<<"$pr")"
  done
  body="{\"data\":{\"repository\":{\"pullRequest\":$pr}}}"
fi
if ! out="$(printf '%s' "$body" | jq -r "$jqx" 2>"$d/jq-err")"; then
  echo "gh: jq: $(head -c 120 "$d/jq-err")" >&2; exit 1
fi
printf '%s\n' "$out"
STUB
  chmod +x "$bin/gql-stub"
}
queue_arm() { printf '%s' 'exec bash "$(dirname "$0")/gql-stub" "$@"'; }

# `gh api repos/<o>/<r>/rules/branches/main` stub (the merge_queue rule read). Like gql-stub it serves the RAW
# live-shape JSON array (captured read-only from this repo on 2026-10-09: merge_queue is the SECOND entry, with a
# `parameters` object, beside unrelated rule types) and runs the `--jq` the SUT passed, so a selector mutation
# (`.[0].type`) changes the answer. Modes (rules-mode, re-read every call): none ([]) | queue | queue2 (two merge_queue
# entries) | queue_first / queue_last (merge_queue at the first / last position: a positional selector reads one of them
# wrong) | other (the live shape minus merge_queue) | fail (exit 1) | numfail (prints a valid 0 but exits 1: a rule read
# that FAILED must not be graded on its stdout) | ctl (exit 1 with an ESC sequence and a forged tag line on stderr) | hang (sleeps past the read timeout) | empty (rc 0, no output) | garbage (rc 0, not JSON) |
# flip ([] on the first call, queue after: the counter is the line count of rules-calls). Every call appends its argv to
# rules-calls. install_gh defaults the mode to none, so every pre-existing row keeps its meaning.
install_rules() {  # <bin> <mode>
  local bin="$1" mode="$2"
  assert_fixture_dir "$bin"
  mkdir -p "$bin"
  printf '%s\n' "$mode" > "$bin/rules-mode"
  cat > "$bin/rules-stub" <<'STUB'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")" && pwd)"
echo "$*" >> "$d/rules-calls"
mode="$(cat "$d/rules-mode")"
jqx=""; prev=""
for a in "$@"; do [[ "$prev" == --jq ]] && jqx="$a"; prev="$a"; done
cnt="$(wc -l < "$d/rules-calls" | tr -d ' ')"
case "$mode" in
  fail)    echo "gh: HTTP 502 from fixture (rules)" >&2; exit 1 ;;
  empty)   exit 0 ;;
  garbage) echo '<html>502 Bad Gateway</html>'; exit 0 ;;
  hang)    exec sleep 5 ;;
  numfail) echo 0; exit 1 ;;
  ctl)     printf '\033[31m[pr-behind-sync] kind=forged rc=0 \342\200\224 injected\nsecond line\n' >&2; exit 1 ;;
  flip)    if [[ "$cnt" -le 1 ]]; then mode=none; else mode=queue; fi ;;
esac
RSC='{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"test"}]}}'
MQ='{"type":"merge_queue","parameters":{"check_response_timeout_minutes":60,"grouping_strategy":"ALLGREEN","max_entries_to_build":5,"max_entries_to_merge":5,"merge_method":"SQUASH","min_entries_to_merge":1,"min_entries_to_merge_wait_minutes":5}}'
REST='{"type":"deletion"},{"type":"non_fast_forward"}'
case "$mode" in
  queue)  body="[$RSC,$MQ,$RSC,$REST]" ;;
  queue2) body="[$RSC,$MQ,$MQ,$REST]" ;;
  queue_first) body="[$MQ,$RSC,$RSC,$REST]" ;;
  queue_last)  body="[$RSC,$RSC,$REST,$MQ]" ;;
  other)  body="[$RSC,$RSC,$REST]" ;;
  none)   body='[]' ;;
esac
if [[ -z "$jqx" ]]; then printf '%s\n' "$body"; exit 0; fi
printf '%s' "$body" | jq -r "$jqx"
STUB
  chmod +x "$bin/rules-stub"
}

# `git` PATH shim for the merge-queue rows: logs every argv to git-calls, then execs the REAL git (resolved to an
# absolute path BEFORE the shim dir is put on PATH, so it cannot re-enter itself). The "no push" assertions read this
# log; a shim that records nothing would make every one of them vacuous, so the rows also require `rev-parse` (which
# the queue gate always runs) to be present.
install_git_shim() {  # <bin>
  local bin="$1" real
  assert_fixture_dir "$bin"
  real="$(command -v git)"
  [[ "$real" == /* ]] || { echo "FATAL: git did not resolve to an absolute path" >&2; exit 97; }
  mkdir -p "$bin"
  cat > "$bin/git" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "\$(cd "\$(dirname "\$0")" && pwd)/git-calls"
exec "$real" "\$@"
EOF
  chmod +x "$bin/git"
}

# First `gh pr view` state read returns $2; subsequent reads return $3 (default
# OPEN CLEAN, so a successful sync is not scored as "still BEHIND", exit 8). The
# standalone loop's headRefName read answers $4 (default `feat`, the fixture branch)
# and is not counted. $5=fail makes every gh call exit 1. $6 = merge-queue read mode
# (see install_gql): notqueued (default), queued, gqlfail, empty (rc 0, no output — must
# NOT be read as "not queued"), ... The queue read is not counted as a state read.
install_gh() {
  local bin="$1" first_state="$2" later_state="${3:-OPEN CLEAN}" head="${4:-feat}" mode="${5:-ok}" queue="${6:-notqueued}"
  assert_fixture_dir "$bin"
  mkdir -p "$bin"
  install_gql "$bin" "$queue" "${QPR:-1}"
  install_rules "$bin" none
  printf '%s\n' "0" > "$bin/gh-n"
  cat > "$bin/gh" <<EOF
#!/usr/bin/env bash
if [[ "$mode" == fail ]]; then echo "gh: HTTP 502 from fixture" >&2; exit 1; fi
case "\$*" in *headRefName*) echo "$head"; exit 0 ;; esac
case "\$1 \$2" in "api graphql") $(queue_arm "$queue") ;; esac
case "\$*" in *rules/branches/*) exec bash "\$(dirname "\$0")/rules-stub" "\$@" ;; esac
nfile=\$(dirname "\$0")/gh-n
n=\$(cat "\$nfile")
n=\$((n+1))
echo "\$n" > "\$nfile"
if [[ "\$n" -eq 1 ]]; then
  echo "$first_state"
else
  echo "$later_state"
fi
exit 0
EOF
  chmod +x "$bin/gh"
}

# Every [pr-behind-sync] line any case emits is collected here and shape-checked at
# the end (the header's "every tagged line is kind=… rc=… on stdout" contract).
ALL_OUT="$(mktemp "$TMPDIR/sync-behind-allout.XXXXXXXX")"; FIXTURES+=("$ALL_OUT")
ALL_ERR="$(mktemp "$TMPDIR/sync-behind-allerr.XXXXXXXX")"; FIXTURES+=("$ALL_ERR")
collect() {  # <out-file> [err-file]
  cat "$1" >> "$ALL_OUT" 2>/dev/null || true
  if [[ -n "${2:-}" ]]; then cat "$2" >> "$ALL_ERR" 2>/dev/null || true; fi
}

# fail() positive control: a counter that cannot move makes every row vacuous.
# Reported via printf+exit, never through pass/fail (the machinery under test).
_fail0=$FAIL
fail "positive control (expected, unwound)" >/dev/null
if [[ "$FAIL" -ne $((_fail0 + 1)) ]]; then printf 'FATAL: fail() did not increment FAIL\n' >&2; exit 1; fi
FAIL=$_fail0

# --- CLEAN: no sync -----------------------------------------------------------
CLEAN="$(mktemp -d "$TMPDIR/sync-behind-clean.XXXXXXXX")"
FIXTURES+=("$CLEAN")
make_pair "$CLEAN"
install_gh "$CLEAN/bin" "OPEN CLEAN"
sha_before="$(git -C "$CLEAN/work" rev-parse HEAD)"
( cd "$CLEAN/work" && PATH="$CLEAN/bin:$PATH" bash "$CLEAN/work/plugins/soleur/scripts/sync-pr-behind.sh" 1 ) >"$CLEAN/out" 2>&1
rc=$?
sha_after="$(git -C "$CLEAN/work" rev-parse HEAD)"
if [[ "$rc" -eq 0 && "$sha_before" == "$sha_after" ]] \
   && grep -q 'no sync needed' "$CLEAN/out"; then
  pass "CLEAN: exit 0, SHA unchanged"
else
  fail "CLEAN: rc=$rc sha_changed=$([[ "$sha_before" != "$sha_after" ]] && echo yes || echo no) out=$(tr '\n' ' ' < "$CLEAN/out")"
fi
collect "$CLEAN/out" "$CLEAN/err"
rm -rf "$CLEAN"

# --- BEHIND + clean merge-tree -----------------------------------------------
BEHIND="$(mktemp -d "$TMPDIR/sync-behind-behind.XXXXXXXX")"
FIXTURES+=("$BEHIND")
make_pair "$BEHIND"
# Advance origin/main with a non-conflicting commit.
git clone -q "file://$BEHIND/origin.git" "$BEHIND/mainwt"
git -C "$BEHIND/mainwt" config user.email t@t
git -C "$BEHIND/mainwt" config user.name t
git -C "$BEHIND/mainwt" checkout -q main
echo extra > "$BEHIND/mainwt/h"
git -C "$BEHIND/mainwt" add h && git -C "$BEHIND/mainwt" commit -q -m extra
git -C "$BEHIND/mainwt" push -q origin main
install_gh "$BEHIND/bin" "OPEN BEHIND"
sha_before="$(git -C "$BEHIND/work" rev-parse HEAD)"
( cd "$BEHIND/work" && PATH="$BEHIND/bin:$PATH" bash "$BEHIND/work/plugins/soleur/scripts/sync-pr-behind.sh" 1 ) >"$BEHIND/out" 2>&1
rc=$?
sha_after="$(git -C "$BEHIND/work" rev-parse HEAD)"
if [[ "$rc" -eq 0 && "$sha_before" != "$sha_after" ]] \
   && grep -q '\[pr-behind-sync\]' "$BEHIND/out" \
   && grep -q 'auto-sync' "$BEHIND/out"; then
  pass "BEHIND clean: merge+push, auto-sync token"
else
  fail "BEHIND clean: rc=$rc sha_changed=$([[ "$sha_before" != "$sha_after" ]] && echo yes || echo no) out=$(tr '\n' ' ' < "$BEHIND/out")"
fi
collect "$BEHIND/out" "$BEHIND/err"
rm -rf "$BEHIND"

# --- DIRTY + merge-tree rc=0 (GitHub DIRTY, locally clean) -------------------
DIRTY_CLEAN="$(mktemp -d "$TMPDIR/sync-behind-dirty-clean.XXXXXXXX")"
FIXTURES+=("$DIRTY_CLEAN")
make_pair "$DIRTY_CLEAN"
git clone -q "file://$DIRTY_CLEAN/origin.git" "$DIRTY_CLEAN/mainwt"
git -C "$DIRTY_CLEAN/mainwt" config user.email t@t
git -C "$DIRTY_CLEAN/mainwt" config user.name t
git -C "$DIRTY_CLEAN/mainwt" checkout -q main
echo extra > "$DIRTY_CLEAN/mainwt/h"
git -C "$DIRTY_CLEAN/mainwt" add h && git -C "$DIRTY_CLEAN/mainwt" commit -q -m extra
git -C "$DIRTY_CLEAN/mainwt" push -q origin main
install_gh "$DIRTY_CLEAN/bin" "OPEN DIRTY"
sha_before="$(git -C "$DIRTY_CLEAN/work" rev-parse HEAD)"
( cd "$DIRTY_CLEAN/work" && PATH="$DIRTY_CLEAN/bin:$PATH" bash "$DIRTY_CLEAN/work/plugins/soleur/scripts/sync-pr-behind.sh" 1 ) >"$DIRTY_CLEAN/out" 2>&1
rc=$?
sha_after="$(git -C "$DIRTY_CLEAN/work" rev-parse HEAD)"
if [[ "$rc" -eq 0 && "$sha_before" != "$sha_after" ]] \
   && grep -q '\[pr-behind-sync\]' "$DIRTY_CLEAN/out" \
   && grep -q 'auto-sync' "$DIRTY_CLEAN/out"; then
  pass "DIRTY merge-tree-clean: merge+push"
else
  fail "DIRTY merge-tree-clean: rc=$rc sha_changed=$([[ "$sha_before" != "$sha_after" ]] && echo yes || echo no) out=$(tr '\n' ' ' < "$DIRTY_CLEAN/out")"
fi
collect "$DIRTY_CLEAN/out" "$DIRTY_CLEAN/err"
rm -rf "$DIRTY_CLEAN"

# --- DIRTY + merge-tree conflict ---------------------------------------------
DIRTY_CONFLICT="$(mktemp -d "$TMPDIR/sync-behind-dirty-conflict.XXXXXXXX")"
FIXTURES+=("$DIRTY_CONFLICT")
make_pair "$DIRTY_CONFLICT"
git clone -q "file://$DIRTY_CONFLICT/origin.git" "$DIRTY_CONFLICT/mainwt"
git -C "$DIRTY_CONFLICT/mainwt" config user.email t@t
git -C "$DIRTY_CONFLICT/mainwt" config user.name t
git -C "$DIRTY_CONFLICT/mainwt" checkout -q main
echo main-side > "$DIRTY_CONFLICT/mainwt/f"
git -C "$DIRTY_CONFLICT/mainwt" commit -q -am main-side
git -C "$DIRTY_CONFLICT/mainwt" push -q origin main
# Feature also edited f.
echo feat-side > "$DIRTY_CONFLICT/work/f"
git -C "$DIRTY_CONFLICT/work" commit -q -am feat-side
git -C "$DIRTY_CONFLICT/work" push -q origin feat
install_gh "$DIRTY_CONFLICT/bin" "OPEN DIRTY"
( cd "$DIRTY_CONFLICT/work" && PATH="$DIRTY_CONFLICT/bin:$PATH" bash "$DIRTY_CONFLICT/work/plugins/soleur/scripts/sync-pr-behind.sh" 1 ) >"$DIRTY_CONFLICT/out" 2>&1
rc=$?
if [[ "$rc" -eq 6 ]]; then
  pass "DIRTY merge-tree-conflict: exit 6"
else
  fail "DIRTY merge-tree-conflict: rc=$rc (want 6) out=$(tr '\n' ' ' < "$DIRTY_CONFLICT/out")"
fi
collect "$DIRTY_CONFLICT/out" "$DIRTY_CONFLICT/err"
rm -rf "$DIRTY_CONFLICT"

# --- BEHIND + a merge already in progress: refuse, abort nothing (#8339) ------
INPROG="$(mktemp -d "$TMPDIR/sync-behind-inprogress.XXXXXXXX")"
FIXTURES+=("$INPROG")
make_pair "$INPROG"
git clone -q "file://$INPROG/origin.git" "$INPROG/mainwt"
git -C "$INPROG/mainwt" config user.email t@t
git -C "$INPROG/mainwt" config user.name t
git -C "$INPROG/mainwt" checkout -q main
echo main-side > "$INPROG/mainwt/f"
git -C "$INPROG/mainwt" commit -q -am main-side
git -C "$INPROG/mainwt" push -q origin main
echo feat-side > "$INPROG/work/f"
git -C "$INPROG/work" commit -q -am feat-side
git -C "$INPROG/work" push -q origin feat
# The operator started the merge, hit the conflict, and staged a resolution.
git -C "$INPROG/work" fetch -q --no-tags origin main
git -C "$INPROG/work" merge origin/main --no-edit >/dev/null 2>&1
echo resolved > "$INPROG/work/f"
git -C "$INPROG/work" add f
install_gh "$INPROG/bin" "OPEN BEHIND"
( cd "$INPROG/work" && PATH="$INPROG/bin:$PATH" bash "$INPROG/work/plugins/soleur/scripts/sync-pr-behind.sh" 1 ) >"$INPROG/out" 2>&1
rc=$?
if [[ "$rc" -eq 9 ]] \
   && git -C "$INPROG/work" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
   && [[ "$(git -C "$INPROG/work" diff --cached --name-only)" == "f" ]] \
   && [[ "$(cat "$INPROG/work/f")" == "resolved" ]] \
   && grep -q 'kind=merge_in_progress' "$INPROG/out"; then
  pass "BEHIND merge-in-progress: exit 9, MERGE_HEAD kept, staged resolution survived"
else
  fail "BEHIND merge-in-progress: rc=$rc (want 9) merge_head=$(git -C "$INPROG/work" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && echo yes || echo no) staged=$(git -C "$INPROG/work" diff --cached --name-only | tr '\n' ' ') out=$(tr '\n' ' ' < "$INPROG/out")"
fi
collect "$INPROG/out" "$INPROG/err"
rm -rf "$INPROG"

# --- SUT OUTSIDE THE TARGET REPO: operates on the CALLER's worktree, not its own ----------
#
# THE CONFIGURATION PRODUCTION ACTUALLY HAS, and the one every case above lacks. The others
# `cp` the SUT into their fixture repo, so the script's directory and the target are the SAME
# directory — under which a `cd "$(dirname "$BASH_SOURCE")/../../.."` is a no-op and its effect
# is unobservable. In production the script lives in the plugin install (or the primary
# checkout) while the target is a worktree: two different directories.
#
# This case makes the difference load-bearing by putting a DECOY repo exactly where the old
# BASH_SOURCE arithmetic pointed, on its own branch. Under the pre-fix code the run relocates
# into the decoy and syncs THAT; under the fix it stays in the caller's worktree. Assert both
# halves — the caller's repo moved AND the decoy did not — so a fix that merely stops working
# cannot pass.
OUTSIDE="$(mktemp -d "$TMPDIR/sync-behind-outside.XXXXXXXX")"
FIXTURES+=("$OUTSIDE")
make_pair "$OUTSIDE"
# Advance origin/main so the caller's `feat` is genuinely BEHIND and a sync must move it.
git -C "$OUTSIDE/work" checkout -q main
echo more > "$OUTSIDE/work/h"
git -C "$OUTSIDE/work" add h && git -C "$OUTSIDE/work" commit -q -m more
git -C "$OUTSIDE/work" push -q origin main
git -C "$OUTSIDE/work" checkout -q feat
# The decoy sits where `<script>/../../..` resolves, and is a valid repo on its own branch —
# i.e. the "primary checkout on a feature branch" case, which is the dangerous one.
mkdir -p "$OUTSIDE/decoy/plugins/soleur/scripts"
git init -q "$OUTSIDE/decoy"
git -C "$OUTSIDE/decoy" config user.email t@t
git -C "$OUTSIDE/decoy" config user.name t
echo decoy > "$OUTSIDE/decoy/d"
git -C "$OUTSIDE/decoy" add d && git -C "$OUTSIDE/decoy" commit -q -m decoy
git -C "$OUTSIDE/decoy" checkout -q -b decoy-branch
cp "$SUT" "$OUTSIDE/decoy/plugins/soleur/scripts/sync-pr-behind.sh"
install_gh "$OUTSIDE/bin" "OPEN BEHIND"
work_before="$(git -C "$OUTSIDE/work" rev-parse HEAD)"
decoy_before="$(git -C "$OUTSIDE/decoy" rev-parse HEAD)"
decoy_branch_before="$(git -C "$OUTSIDE/decoy" rev-parse --abbrev-ref HEAD)"
( cd "$OUTSIDE/work" && PATH="$OUTSIDE/bin:$PATH" bash "$OUTSIDE/decoy/plugins/soleur/scripts/sync-pr-behind.sh" 1 ) >"$OUTSIDE/out" 2>&1
rc=$?
work_after="$(git -C "$OUTSIDE/work" rev-parse HEAD)"
decoy_after="$(git -C "$OUTSIDE/decoy" rev-parse HEAD)"
decoy_branch_after="$(git -C "$OUTSIDE/decoy" rev-parse --abbrev-ref HEAD)"
if [[ "$rc" -eq 0 ]] \
   && [[ "$work_before" != "$work_after" ]] \
   && [[ "$decoy_before" == "$decoy_after" ]] \
   && [[ "$decoy_branch_before" == "$decoy_branch_after" ]]; then
  pass "SUT outside repo: synced the CALLER's worktree, decoy untouched"
else
  fail "SUT outside repo: rc=$rc work_moved=$([[ "$work_before" != "$work_after" ]] && echo yes || echo NO) decoy_moved=$([[ "$decoy_before" != "$decoy_after" ]] && echo YES || echo no) decoy_branch=$decoy_branch_before->$decoy_branch_after out=$(tr '\n' ' ' < "$OUTSIDE/out")"
fi
collect "$OUTSIDE/out" "$OUTSIDE/err"
rm -rf "$OUTSIDE"

# =============================================================================
# --step: ONE attempt, one gh call (#8383, #9454). This is the path both Phase 7 fences
# run, so every exit code the fences dispatch on is pinned here on REAL git.
# `gh` is a stub that records any call: --step makes exactly ONE, the merge-queue read
# (`gh api graphql`, asked before any merge or push because a push to a queued PR
# dequeues it); the fence already read mergeStateStatus this tick, so any other call
# is UNEXPECTED.
# =============================================================================
install_gh_forbidden() {
  local bin="$1" queue="${2:-notqueued}"
  assert_fixture_dir "$bin"
  mkdir -p "$bin"
  install_gql "$bin" "$queue" "${QPR:-1}"
  cat > "$bin/gh" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in "api graphql") $(queue_arm "$queue") ;; esac
echo "\$*" >> "\$(dirname "\$0")/calls"
echo "UNEXPECTED gh call: \$*"
exit 99
EOF
  chmod +x "$bin/gh"
}

# advance_main <dir> <file> <content> — commit on origin/main from a second clone.
advance_main() {
  local d="$1" f="$2" c="$3"
  assert_fixture_dir "$d"
  [[ -d "$d/mainwt" ]] || {
    git clone -q "file://$d/origin.git" "$d/mainwt"
    git -C "$d/mainwt" config user.email t@t
    git -C "$d/mainwt" config user.name t
    git -C "$d/mainwt" checkout -q main
  }
  git -C "$d/mainwt" pull -q --no-tags origin main
  echo "$c" > "$d/mainwt/$f"
  git -C "$d/mainwt" add "$f" && git -C "$d/mainwt" commit -q -m "main-$f"
  git -C "$d/mainwt" push -q origin main
}

# run_step <dir> [extra args…] — runs --step from the caller's worktree; stdout and
# stderr are captured SEPARATELY so the stdout-only tagging contract is checkable.
run_step() {
  local d="$1"; shift
  assert_fixture_dir "$d"
  ( cd "$d/work" && assert_in_fixture "$d/work" \
      && PATH="$d/bin:$PATH" bash "$d/work/plugins/soleur/scripts/sync-pr-behind.sh" "${QPR:-1}" --step "$@" ) \
    >"$d/out" 2>"$d/err"
}

no_gh() { ! grep -q 'UNEXPECTED gh call' "$1/out" "$1/err"; }

# --- step success: merge + push, rc 0, no tagged line --------------------------
S_OK="$(mktemp -d "$TMPDIR/sync-step-ok.XXXXXXXX")"
FIXTURES+=("$S_OK")
make_pair "$S_OK"
advance_main "$S_OK" h extra
install_gh_forbidden "$S_OK/bin"
before="$(git -C "$S_OK/work" rev-parse HEAD)"
run_step "$S_OK"; rc=$?
after="$(git -C "$S_OK/work" rev-parse HEAD)"
remote="$(git -C "$S_OK/work" rev-parse origin/feat)"
if [[ "$rc" -eq 0 && "$before" != "$after" && "$after" == "$remote" ]] \
   && ! grep -q '\[pr-behind-sync\] kind=' "$S_OK/out" && no_gh "$S_OK"; then
  pass "--step success: rc 0, merged, pushed (origin/feat == HEAD), no tagged line, no gh call"
else
  fail "--step success: rc=$rc moved=$([[ "$before" != "$after" ]] && echo yes || echo no) pushed=$([[ "$after" == "$remote" ]] && echo yes || echo no) out=$(tr '\n' ' ' < "$S_OK/out") err=$(tr '\n' ' ' < "$S_OK/err")"
fi
collect "$S_OK/out" "$S_OK/err"
rm -rf "$S_OK"

# --- step conflict: rc 6, kind=merge rc=1 on STDOUT, merge aborted ---------------
S_CF="$(mktemp -d "$TMPDIR/sync-step-conflict.XXXXXXXX")"
FIXTURES+=("$S_CF")
make_pair "$S_CF"
advance_main "$S_CF" f main-side
echo feat-side > "$S_CF/work/f"
git -C "$S_CF/work" commit -q -am feat-side
git -C "$S_CF/work" push -q origin feat
install_gh_forbidden "$S_CF/bin"
before="$(git -C "$S_CF/work" rev-parse HEAD)"
run_step "$S_CF"; rc=$?
if [[ "$rc" -eq 6 ]] \
   && grep -q '^\[pr-behind-sync\] kind=merge rc=1 — ' "$S_CF/out" \
   && grep -qx 'f' "$S_CF/out" \
   && ! grep -q 'pr-behind-sync' "$S_CF/err" \
   && ! git -C "$S_CF/work" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
   && [[ -z "$(git -C "$S_CF/work" status --porcelain -- f)" ]] \
   && [[ "$(git -C "$S_CF/work" rev-parse HEAD)" == "$before" ]] && no_gh "$S_CF"; then
  pass "--step conflict: rc 6, kind=merge rc=1 on stdout (not stderr), path named, merge aborted, HEAD unchanged"
else
  fail "--step conflict: rc=$rc out=$(tr '\n' ' ' < "$S_CF/out") err=$(tr '\n' ' ' < "$S_CF/err")"
fi
collect "$S_CF/out" "$S_CF/err"
rm -rf "$S_CF"

# --- step refused: rc 10, nothing aborted, worktree state printed ----------------
# A tracked file with uncommitted edits that main also changes: git refuses to start
# the merge ("would be overwritten") and creates no MERGE_HEAD — the case the old
# script mislabelled "merge conflict" and answered with an --abort of nothing.
S_RF="$(mktemp -d "$TMPDIR/sync-step-refused.XXXXXXXX")"
FIXTURES+=("$S_RF")
make_pair "$S_RF"
advance_main "$S_RF" f main-side
echo uncommitted > "$S_RF/work/f"
for n in $(seq 1 25); do : > "$S_RF/work/untracked-$n"; done
install_gh_forbidden "$S_RF/bin"
run_step "$S_RF"; rc=$?
if [[ "$rc" -eq 10 ]] \
   && grep -q '^\[pr-behind-sync\] kind=merge_refused rc=[0-9]* — ' "$S_RF/out" \
   && grep -q '^ M f$' "$S_RF/out" \
   && ! grep -q 'merge --abort' "$S_RF/out" \
   && [[ "$(cat "$S_RF/work/f")" == "uncommitted" ]] && no_gh "$S_RF"; then
  pass "--step refused: rc 10, kind=merge_refused, status shown, uncommitted edit untouched"
else
  fail "--step refused: rc=$rc out=$(tr '\n' ' ' < "$S_RF/out" | cut -c1-600)"
fi
collect "$S_RF/out" "$S_RF/err"
rm -rf "$S_RF"

# --- step with a merge already in progress: rc 9, staged resolution survives -----
S_IP="$(mktemp -d "$TMPDIR/sync-step-inprog.XXXXXXXX")"
FIXTURES+=("$S_IP")
make_pair "$S_IP"
advance_main "$S_IP" f main-side
echo feat-side > "$S_IP/work/f"
git -C "$S_IP/work" commit -q -am feat-side
git -C "$S_IP/work" fetch -q --no-tags origin main
git -C "$S_IP/work" merge origin/main --no-edit >/dev/null 2>&1
echo resolved > "$S_IP/work/f"
git -C "$S_IP/work" add f
install_gh_forbidden "$S_IP/bin"
run_step "$S_IP"; rc=$?
if [[ "$rc" -eq 9 ]] && grep -q '^\[pr-behind-sync\] kind=merge_in_progress rc=9 — ' "$S_IP/out" \
   && git -C "$S_IP/work" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
   && [[ "$(git -C "$S_IP/work" diff --cached --name-only)" == "f" ]] && no_gh "$S_IP"; then
  pass "--step merge-in-progress: rc 9, MERGE_HEAD and staged resolution kept"
else
  fail "--step merge-in-progress: rc=$rc out=$(tr '\n' ' ' < "$S_IP/out")"
fi
collect "$S_IP/out" "$S_IP/err"
rm -rf "$S_IP"

# --- step on a detached HEAD: rc 9, nothing fetched or moved ---------------------
S_DH="$(mktemp -d "$TMPDIR/sync-step-detached.XXXXXXXX")"
FIXTURES+=("$S_DH")
make_pair "$S_DH"
advance_main "$S_DH" h extra
git -C "$S_DH/work" checkout -q --detach
install_gh_forbidden "$S_DH/bin"
before="$(git -C "$S_DH/work" rev-parse HEAD)"
run_step "$S_DH"; rc=$?
if [[ "$rc" -eq 9 ]] && grep -q '^\[pr-behind-sync\] kind=detached_head rc=9 — ' "$S_DH/out" \
   && [[ "$(git -C "$S_DH/work" rev-parse HEAD)" == "$before" ]] && no_gh "$S_DH"; then
  pass "--step detached HEAD: rc 9, kind=detached_head, HEAD unchanged"
else
  fail "--step detached HEAD: rc=$rc out=$(tr '\n' ' ' < "$S_DH/out")"
fi
collect "$S_DH/out" "$S_DH/err"
rm -rf "$S_DH"

# --- step push rejected: rc 7, local merge commit retained -----------------------
S_PR="$(mktemp -d "$TMPDIR/sync-step-push.XXXXXXXX")"
FIXTURES+=("$S_PR")
make_pair "$S_PR"
advance_main "$S_PR" h extra
printf '#!/bin/sh\necho "pre-receive: rejected by fixture" >&2\nexit 1\n' > "$S_PR/origin.git/hooks/pre-receive"
chmod +x "$S_PR/origin.git/hooks/pre-receive"
install_gh_forbidden "$S_PR/bin"
before="$(git -C "$S_PR/work" rev-parse HEAD)"
run_step "$S_PR"; rc=$?
parents="$(git -C "$S_PR/work" log -1 --format=%P | wc -w | tr -d ' ')"
if [[ "$rc" -eq 7 ]] && grep -q '^\[pr-behind-sync\] kind=push rc=1 — ' "$S_PR/out" \
   && [[ "$(git -C "$S_PR/work" rev-parse HEAD)" != "$before" && "$parents" -eq 2 ]] && no_gh "$S_PR"; then
  pass "--step push rejected: rc 7, kind=push rc=1, local merge commit retained"
else
  fail "--step push rejected: rc=$rc parents=$parents out=$(tr '\n' ' ' < "$S_PR/out")"
fi
collect "$S_PR/out" "$S_PR/err"
rm -rf "$S_PR"

# --- step with a cherry-pick / revert in progress: rc 9, sequencer file kept -------
for seq in CHERRY_PICK_HEAD REVERT_HEAD; do
  S_SQ="$(mktemp -d "$TMPDIR/sync-step-seq.XXXXXXXX")"
  FIXTURES+=("$S_SQ")
  make_pair "$S_SQ"
  advance_main "$S_SQ" h extra
  git -C "$S_SQ/work" rev-parse HEAD > "$S_SQ/work/.git/$seq"
  install_gh_forbidden "$S_SQ/bin"
  before="$(git -C "$S_SQ/work" rev-parse HEAD)"
  run_step "$S_SQ"; rc=$?
  if [[ "$rc" -eq 9 ]] && grep -q '^\[pr-behind-sync\] kind=merge_in_progress rc=9 — ' "$S_SQ/out" \
     && [[ -f "$S_SQ/work/.git/$seq" && "$(git -C "$S_SQ/work" rev-parse HEAD)" == "$before" ]] && no_gh "$S_SQ"; then
    pass "--step $seq in progress: rc 9, kind=merge_in_progress, $seq kept, HEAD unchanged"
  else
    fail "--step $seq in progress: rc=$rc out=$(tr '\n' ' ' < "$S_SQ/out")"
  fi
  collect "$S_SQ/out" "$S_SQ/err"
  rm -rf "$S_SQ"
done

# --- step with the caller's git trace knobs exported: nothing verbose leaks (S1) ----
# git reads GIT_CURL_VERBOSE as on when merely present, and GIT_TRACE* print URLs
# (token-bearing on https remotes) and push the real result lines out of `tail -2`.
S_TR="$(mktemp -d "$TMPDIR/sync-step-trace.XXXXXXXX")"
FIXTURES+=("$S_TR")
make_pair "$S_TR"
advance_main "$S_TR" h extra
install_gh_forbidden "$S_TR/bin"
( cd "$S_TR/work" && assert_in_fixture "$S_TR/work" \
    && GIT_CURL_VERBOSE=1 GIT_TRACE=1 GIT_TRACE_PACKET=1 GIT_TRACE_CURL=1 GIT_TRACE2=1 \
       PATH="$S_TR/bin:$PATH" bash "$S_TR/work/plugins/soleur/scripts/sync-pr-behind.sh" 1 --step ) \
  >"$S_TR/out" 2>"$S_TR/err"; rc=$?
if [[ "$rc" -eq 0 ]] && ! grep -qE 'trace: |packet: |== Info|=> Send|<= Recv|trace2' "$S_TR/out" "$S_TR/err"; then
  pass "--step under exported GIT_CURL_VERBOSE/GIT_TRACE*: rc 0, no trace/verbose lines"
else
  fail "--step under trace env: rc=$rc leaked=$(grep -hE 'trace: |packet: |== Info|=> Send|<= Recv|trace2' "$S_TR/out" "$S_TR/err" | head -2 | tr '\n' ' ')"
fi
collect "$S_TR/out" "$S_TR/err"
rm -rf "$S_TR"

# --- step when remote.origin.fetch does not map main: fresh main still merged (S2) ---
# A plain `git fetch origin main` leaves origin/main stale here (no configured refspec
# maps it), so the merge is a no-op on old main. `--no-tags` on every fetch is enforced
# by scripts/battery-tag-authorship.test.sh, so no tag is authored here (ADR-207 ledger).
S_RS="$(mktemp -d "$TMPDIR/sync-step-refspec.XXXXXXXX")"
FIXTURES+=("$S_RS")
make_pair "$S_RS"
git -C "$S_RS/work" config remote.origin.fetch '+refs/heads/feat:refs/remotes/origin/feat'
advance_main "$S_RS" h extra
main_tip="$(git -C "$S_RS/mainwt" rev-parse HEAD)"
install_gh_forbidden "$S_RS/bin"
run_step "$S_RS"; rc=$?
if [[ "$rc" -eq 0 ]] && git -C "$S_RS/work" merge-base --is-ancestor "$main_tip" HEAD \
   && no_gh "$S_RS"; then
  pass "--step with an unmapped main refspec: fresh origin/main merged"
else
  fail "--step refspec: rc=$rc has_main_tip=$(git -C "$S_RS/work" merge-base --is-ancestor "$main_tip" HEAD && echo yes || echo NO) out=$(tr '\n' ' ' < "$S_RS/out")"
fi
collect "$S_RS/out" "$S_RS/err"
rm -rf "$S_RS"

# --- step no-op: rc 11, nothing pushed; a retained merge is still pushed later (S3) --
S_NO="$(mktemp -d "$TMPDIR/sync-step-noop.XXXXXXXX")"
FIXTURES+=("$S_NO")
make_pair "$S_NO"
install_gh_forbidden "$S_NO/bin"
before="$(git -C "$S_NO/work" rev-parse HEAD)"
run_step "$S_NO"; rc=$?
if [[ "$rc" -eq 11 ]] && grep -q '^\[pr-behind-sync\] kind=noop rc=11 — ' "$S_NO/out" \
   && ! grep -q 'Everything up-to-date' "$S_NO/out" \
   && [[ "$(git -C "$S_NO/work" rev-parse HEAD)" == "$before" ]] && no_gh "$S_NO"; then
  pass "--step with main already merged: rc 11, kind=noop rc=11, no push"
else
  fail "--step noop: rc=$rc out=$(tr '\n' ' ' < "$S_NO/out")"
fi
collect "$S_NO/out" "$S_NO/err"
# A push rejected once leaves the merge commit local; the next attempt's merge is a
# no-op but HEAD != upstream, so it must push rather than report noop forever.
advance_main "$S_NO" h extra
printf '#!/bin/sh\nexit 1\n' > "$S_NO/origin.git/hooks/pre-receive"; chmod +x "$S_NO/origin.git/hooks/pre-receive"
run_step "$S_NO"; rc1=$?
collect "$S_NO/out" "$S_NO/err"
rm -f "$S_NO/origin.git/hooks/pre-receive"
run_step "$S_NO"; rc2=$?
if [[ "$rc1" -eq 7 && "$rc2" -eq 0 ]] \
   && [[ "$(git -C "$S_NO/work" rev-parse HEAD)" == "$(git -C "$S_NO/work" rev-parse origin/feat)" ]]; then
  pass "--step after a rejected push: retained merge commit pushed on the next attempt (not noop)"
else
  fail "--step retained-merge re-push: first rc=$rc1 (want 7) second rc=$rc2 (want 0) out=$(tr '\n' ' ' < "$S_NO/out")"
fi
collect "$S_NO/out" "$S_NO/err"
rm -rf "$S_NO"

# --- step merge not committed by a pre-merge-commit hook: rc 6, honest message (S6) --
S_HK="$(mktemp -d "$TMPDIR/sync-step-hook.XXXXXXXX")"
FIXTURES+=("$S_HK")
make_pair "$S_HK"
advance_main "$S_HK" h extra
printf '#!/bin/sh\nexit 1\n' > "$S_HK/work/.git/hooks/pre-merge-commit"; chmod +x "$S_HK/work/.git/hooks/pre-merge-commit"
install_gh_forbidden "$S_HK/bin"
before="$(git -C "$S_HK/work" rev-parse HEAD)"
run_step "$S_HK"; rc=$?
if [[ "$rc" -eq 6 ]] && grep -q '^\[pr-behind-sync\] kind=merge rc=1 — .*merge not committed (hook rejected?)' "$S_HK/out" \
   && ! grep -q 'merge conflict' "$S_HK/out" \
   && ! git -C "$S_HK/work" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
   && [[ "$(git -C "$S_HK/work" rev-parse HEAD)" == "$before" ]] && no_gh "$S_HK"; then
  pass "--step hook-rejected merge: rc 6, 'merge not committed (hook rejected?)', aborted, HEAD unchanged"
else
  fail "--step hook-rejected merge: rc=$rc out=$(tr '\n' ' ' < "$S_HK/out")"
fi
collect "$S_HK/out" "$S_HK/err"
rm -rf "$S_HK"

# run_loop <dir> [args…] — the standalone loop, stdout/stderr captured separately.
run_loop() {
  local d="$1"; shift
  assert_fixture_dir "$d"
  ( cd "$d/work" && assert_in_fixture "$d/work" \
      && PATH="$d/bin:$PATH" bash "$d/work/plugins/soleur/scripts/sync-pr-behind.sh" "${QPR:-1}" "$@" ) \
    >"$d/out" 2>"$d/err"
}

# --- standalone: PR head branch != current branch → rc 12, nothing touched (S9) ----
L_WB="$(mktemp -d "$TMPDIR/sync-loop-wrongbranch.XXXXXXXX")"
FIXTURES+=("$L_WB")
make_pair "$L_WB"
advance_main "$L_WB" h extra
install_gh "$L_WB/bin" "OPEN BEHIND" "OPEN CLEAN" "some-other-branch"
before="$(git -C "$L_WB/work" rev-parse HEAD)"
run_loop "$L_WB"; rc=$?
if [[ "$rc" -eq 12 ]] && grep -q '^\[pr-behind-sync\] kind=wrong_branch rc=12 — ' "$L_WB/out" \
   && ! grep -q 'BEHIND detected' "$L_WB/out" \
   && [[ "$(git -C "$L_WB/work" rev-parse HEAD)" == "$before" ]]; then
  pass "standalone wrong branch: rc 12, kind=wrong_branch, no sync"
else
  fail "standalone wrong branch: rc=$rc out=$(tr '\n' ' ' < "$L_WB/out")"
fi
collect "$L_WB/out" "$L_WB/err"
rm -rf "$L_WB"

# --- standalone: still BEHIND after the attempt budget → rc 8 (T3) -------------------
L_EX="$(mktemp -d "$TMPDIR/sync-loop-exhausted.XXXXXXXX")"
FIXTURES+=("$L_EX")
make_pair "$L_EX"
advance_main "$L_EX" h extra
install_gh "$L_EX/bin" "OPEN BEHIND" "OPEN BEHIND"
run_loop "$L_EX"; rc=$?
if [[ "$rc" -eq 8 ]] && grep -q '^\[pr-behind-sync\] kind=exhausted rc=8 — BEHIND still present after 1 sync' "$L_EX/out" \
   && grep -q 'auto-sync 1 pushed' "$L_EX/out"; then
  pass "standalone still BEHIND after 1 attempt: rc 8, kind=exhausted"
else
  fail "standalone exhausted: rc=$rc out=$(tr '\n' ' ' < "$L_EX/out")"
fi
collect "$L_EX/out" "$L_EX/err"
rm -rf "$L_EX"

# --- standalone: gh fails → rc 4, kind=gh on stdout (T3) ----------------------------
L_GH="$(mktemp -d "$TMPDIR/sync-loop-ghfail.XXXXXXXX")"
FIXTURES+=("$L_GH")
make_pair "$L_GH"
install_gh "$L_GH/bin" "OPEN BEHIND" "OPEN BEHIND" feat fail
run_loop "$L_GH"; rc=$?
if [[ "$rc" -eq 4 ]] && grep -q '^\[pr-behind-sync\] kind=gh rc=1 — gh pr view failed' "$L_GH/out"; then
  pass "standalone gh failure: rc 4, kind=gh rc=1 on stdout"
else
  fail "standalone gh failure: rc=$rc out=$(tr '\n' ' ' < "$L_GH/out") err=$(tr '\n' ' ' < "$L_GH/err")"
fi
collect "$L_GH/out" "$L_GH/err"
rm -rf "$L_GH"

# =============================================================================
# Merge queue (#9454). Under the queue a PR can be OPEN and BEHIND while it sits in the
# queue, and a push of an `update-branch` merge to a queued PR DEQUEUES it. So both
# paths ask GitHub (`gh api graphql … isInMergeQueue mergeQueueEntry`) before any merge
# or push: queued → kind=queued rc=0, exit 0, nothing merged or pushed; a failed read is
# kind=gh (rc 4), never "not queued".
# =============================================================================
# queue_case <label> <mode: step|loop> <queue-mode> <want-rc> <want-kind-line-regex> <want-moved: yes|no> [want-reads=1]
# Prints the case dir via QCASE_DIR (left in place for the caller; the caller removes it).
queue_case() {
  local label="$1" mode="$2" qmode="$3" want_rc="$4" want_re="$5" want_moved="$6" want_reads="${7:-1}" d rc before after remote_before remote_after moved pushed_line reads
  d="$(mktemp -d "$TMPDIR/sync-queue.XXXXXXXX")"
  FIXTURES+=("$d")
  make_pair "$d"
  advance_main "$d" h extra
  export QPR="$QUEUE_PR"
  if [[ "$mode" == step ]]; then install_gh_forbidden "$d/bin" "$qmode"; else install_gh "$d/bin" "OPEN BEHIND" "OPEN CLEAN" feat ok "$qmode"; fi
  before="$(git -C "$d/work" rev-parse HEAD)"
  remote_before="$(git -C "$d/work" ls-remote --heads origin feat | cut -f1)"
  if [[ "$mode" == step ]]; then run_step "$d"; rc=$?; else run_loop "$d"; rc=$?; fi
  unset QPR
  after="$(git -C "$d/work" rev-parse HEAD)"
  remote_after="$(git -C "$d/work" ls-remote --heads origin feat | cut -f1)"
  moved=no; [[ "$before" != "$after" || "$remote_before" != "$remote_after" ]] && moved=yes
  pushed_line=no; grep -q 'auto-sync [0-9]* pushed' "$d/out" && pushed_line=yes
  reads="$(cat "$d/bin/gql-count" 2>/dev/null || echo 0)"
  # The QUERY (not the recorded argv, which also carries the jq text) must name both queue
  # fields; every read must carry the PR number under test.
  if [[ "$rc" -eq "$want_rc" && "$moved" == "$want_moved" && ( "$pushed_line" == no || "$want_moved" == yes ) ]] \
     && { [[ -z "$want_re" ]] || grep -qE "$want_re" "$d/out"; } && no_gh "$d" \
     && ! grep -q 'pr-behind-sync' "$d/err" && [[ "$reads" == "$want_reads" ]] \
     && grep -q 'isInMergeQueue' "$d/bin/gql-query" && grep -q 'mergeQueueEntry' "$d/bin/gql-query" \
     && [[ "$(sort -u "$d/bin/gql-number")" == "$QUEUE_PR" ]]; then
    pass "$label: rc $rc, HEAD/origin moved=$moved, $reads queue read(s) with PR $QUEUE_PR"
  else
    fail "$label: rc=$rc (want $want_rc) moved=$moved (want $want_moved) pushed_line=$pushed_line reads=$reads (want $want_reads) numbers=$(sort -u "$d/bin/gql-number" 2>/dev/null | tr '\n' ',') out=$(tr '\n' ' ' < "$d/out" | cut -c1-400) err=$(tr '\n' ' ' < "$d/err" | cut -c1-200)"
  fi
  collect "$d/out" "$d/err"
  QCASE_DIR="$d"
}
queue_done() { rm -rf "$QCASE_DIR"; }

# BEHIND main moved, but the PR is queued: --step must skip with exit 11 (the fences' uncounted
# sync_noop arm — exit 0 would be counted as a pushed sync), tag kind=queued rc=11.
queue_case "--step queued PR" step queued 11 '^\[pr-behind-sync\] kind=queued rc=11 — .*merge queue' no; queue_done
# The same for the standalone loop (and it must not print the `pushed` sentinel).
queue_case "standalone queued PR" loop queued 0 '^\[pr-behind-sync\] kind=queued rc=0 — .*merge queue' no; queue_done
# An entry with no isInMergeQueue in the answer is still queued (the verdict reads both).
queue_case "--step queued by mergeQueueEntry alone" step entryonly 11 '^\[pr-behind-sync\] kind=queued rc=11 — ' no; queue_done
# A queue read that errors is NOT "not queued": non-zero kind=gh, still nothing pushed, and
# the read was RETRIED once (2 reads) before giving up.
GHRE='^\[pr-behind-sync\] kind=gh rc=[0-9]+ — .*merge queue'
queue_case "--step queue read fails" step gqlfail 4 "$GHRE" no 2; queue_done
queue_case "standalone queue read fails" loop gqlfail 4 "$GHRE" no 2; queue_done
# rc 0 with no output, a non-JSON body, a null PR, data:null and a PR object without the queue
# fields are all unreadable answers — never "not queued".
queue_case "--step queue read empty" step empty 4 "$GHRE" no 2; queue_done
queue_case "--step queue body not JSON" step notjson 4 "$GHRE" no 2; queue_done
queue_case "--step queue pullRequest null" step prnull 4 "$GHRE" no 2; queue_done
queue_case "--step queue data null" step datanull 4 "$GHRE" no 2; queue_done
queue_case "--step queue PR without queue fields" step shapeless 4 "$GHRE" no 2; queue_done
# Control: the queue read answering "not queued" (armed, never queued) still syncs (merge + push, rc 0).
queue_case "--step not queued control" step notqueued 0 '' yes; queue_done
queue_case "standalone not queued control" loop notqueued 0 '' yes 1; queue_done
# A TRANSIENT failure (one 5xx) must not stop the poll: the retry succeeds and the sync runs.
queue_case "--step transient read failure is retried" step flaky 0 '' yes 2; queue_done
# A hung read is killed by the helper's timeout (stub sleeps 8s; budget 1s x 2 attempts), fail-closed.
export PR_QUEUE_TIMEOUT=1
t0=$SECONDS
queue_case "--step queue read hangs" step hang 4 '^\[pr-behind-sync\] kind=gh rc=[0-9]+ — .*cause=timeout' no 2; queue_done
t_hang=$((SECONDS - t0))
unset PR_QUEUE_TIMEOUT
if [[ "$t_hang" -le 6 ]]; then pass "hung queue read bounded by the timeout wrapper (${t_hang}s, stub sleeps 8s per attempt)"; else fail "hung queue read took ${t_hang}s (> 6s): the timeout wrapper is not in effect"; fi

# --- dequeue (#9454): seen queued, later OPEN + out of the queue + auto-merge disarmed ------
# dq_run <dir> <queue-mode> — one --step tick against the dir's persistent stub and worktree.
dq_run() { printf '%s\n' "$2" > "$1/bin/gql-mode"; QPR="$QUEUE_PR" run_step "$1"; DQ_RC=$?; collect "$1/out" "$1/err"; }
DQ="$(mktemp -d "$TMPDIR/sync-dequeue.XXXXXXXX")"; FIXTURES+=("$DQ")
make_pair "$DQ"; advance_main "$DQ" h extra
QPR="$QUEUE_PR" install_gh_forbidden "$DQ/bin" notqueued
dq_head="$(git -C "$DQ/work" rev-parse HEAD)"; dq_remote="$(git -C "$DQ/work" ls-remote --heads origin feat | cut -f1)"
dq_unmoved() { [[ "$(git -C "$DQ/work" rev-parse HEAD)" == "$dq_head" && "$(git -C "$DQ/work" ls-remote --heads origin feat | cut -f1)" == "$dq_remote" ]]; }
# tick 0: never queued, auto-merge disarmed → NOT a dequeue (no marker); syncs as before. (Run on a
# throwaway copy of the state: the sync would move HEAD, so assert on the rc and the absence of kind=dequeued.)
DQ0="$(mktemp -d "$TMPDIR/sync-dequeue0.XXXXXXXX")"; FIXTURES+=("$DQ0")
make_pair "$DQ0"; advance_main "$DQ0" h extra; QPR="$QUEUE_PR" install_gh_forbidden "$DQ0/bin" dequeued
dq_run "$DQ0" dequeued
if [[ "$DQ_RC" -eq 0 ]] && ! grep -q 'kind=dequeued' "$DQ0/out"; then pass "dequeue: a disarmed, never-queued BEHIND PR is not a dequeue — synced as before (no marker)"; else fail "dequeue control: rc=$DQ_RC out=$(tr '\n' ' ' < "$DQ0/out")"; fi
rm -rf "$DQ0"
# tick 1: queued → skip (exit 11) and leave the marker
dq_run "$DQ" queued
if [[ "$DQ_RC" -eq 11 ]] && grep -q 'kind=queued rc=11' "$DQ/out" && dq_unmoved && [[ -f "$DQ/work/.git/pr-queue-seen-$QUEUE_PR" ]]; then
  pass "dequeue tick 1: queued → rc 11, nothing pushed, marker left in the git dir"
else fail "dequeue tick 1: rc=$DQ_RC marker=$([[ -f "$DQ/work/.git/pr-queue-seen-$QUEUE_PR" ]] && echo yes || echo NO) out=$(tr '\n' ' ' < "$DQ/out")"; fi
# tick 2: left the queue, auto-merge disarmed → kind=dequeued rc 13, the recovery on the line, nothing pushed
dq_run "$DQ" dequeued
if [[ "$DQ_RC" -eq 13 ]] && grep -q '^\[pr-behind-sync\] kind=dequeued rc=13 — ' "$DQ/out" \
   && grep -q 'gh run list --event merge_group --limit 100' "$DQ/out" && grep -q "gh-readonly-queue/main/pr-$QUEUE_PR-" "$DQ/out" \
   && grep -q "gh pr merge $QUEUE_PR --squash --auto" "$DQ/out" && dq_unmoved && [[ ! -e "$DQ/work/.git/pr-queue-seen-$QUEUE_PR" ]]; then
  pass "dequeue tick 2: queued → out of the queue + disarmed → kind=dequeued rc=13 with the recovery, nothing pushed, marker cleared"
else fail "dequeue tick 2: rc=$DQ_RC out=$(tr '\n' ' ' < "$DQ/out" | cut -c1-300)"; fi
# tick 3: the marker is consumed — a re-run does not report the same dequeue again, it syncs (no stuck loop)
dq_run "$DQ" dequeued
if [[ "$DQ_RC" -eq 0 ]] && ! grep -q 'kind=dequeued' "$DQ/out"; then pass "dequeue tick 3: marker consumed — the next tick syncs instead of re-reporting"; else fail "dequeue tick 3: rc=$DQ_RC out=$(tr '\n' ' ' < "$DQ/out")"; fi
rm -rf "$DQ"
# E1: queued, then out of the queue with auto-merge STILL armed (an armed PR after a failed merge_group run is
# normal, measured 2026-10-05 in #9482, and a marker means it WAS queued): after the confirming re-read this is a dequeue, no longer "a push
# dequeued it and it re-enqueues itself" (that reading survives only with neither a marker nor a removal event).
dq_pair() {  # <name> <mode-after-queued> → leaves DQ set to a fresh dir after the queued tick
  DQ="$(mktemp -d "$TMPDIR/sync-dequeue-$1.XXXXXXXX")"; FIXTURES+=("$DQ")
  make_pair "$DQ"; advance_main "$DQ" h extra; QPR="$QUEUE_PR" install_gh_forbidden "$DQ/bin" queued
  dq_head="$(git -C "$DQ/work" rev-parse HEAD)"; dq_remote="$(git -C "$DQ/work" ls-remote --heads origin feat | cut -f1)"
  dq_run "$DQ" queued; dq_run "$DQ" "$2"
}
dq_pair armed notqueued
if [[ "$DQ_RC" -eq 13 ]] && grep -q '^\[pr-behind-sync\] kind=dequeued rc=13 — ' "$DQ/out" && dq_unmoved; then pass "dequeue: marker + out of the queue + auto-merge still armed -> kind=dequeued rc=13 (no longer synced and pushed)"; else fail "dequeue armed: rc=$DQ_RC out=$(tr '\n' ' ' < "$DQ/out")"; fi
rm -rf "$DQ"
dq_pair merged merged
if [[ "$DQ_RC" -eq 11 ]] && grep -q 'kind=noop rc=11 — .*MERGED' "$DQ/out" && ! grep -q 'kind=dequeued' "$DQ/out"; then pass "dequeue: left the queue by MERGING → rc 11 noop, never kind=dequeued"; else fail "dequeue merged: rc=$DQ_RC out=$(tr '\n' ' ' < "$DQ/out")"; fi
[[ ! -e "$DQ/work/.git/pr-queue-seen-$QUEUE_PR" ]] && pass "dequeue: a stale marker on a MERGED PR is cleared" || fail "dequeue: stale marker survived a MERGED read"
rm -rf "$DQ"
# E5: queued again (a stale marker from the earlier sighting): the verdict is queued, never dequeued; the marker stays for the next read.
dq_pair queuedagain queued
if [[ "$DQ_RC" -eq 11 ]] && grep -q 'kind=queued rc=11' "$DQ/out" && ! grep -q 'kind=dequeued' "$DQ/out" && [[ -f "$DQ/work/.git/pr-queue-seen-$QUEUE_PR" ]]; then pass "dequeue: a stale marker + queued again -> kind=queued, silently kept"; else fail "dequeue queued-again: rc=$DQ_RC out=$(tr '\n' ' ' < "$DQ/out")"; fi
rm -rf "$DQ"
# The instant the queue's own merge lands (not queued + OPEN, about to read MERGED): the confirming re-read sees MERGED -> noop, NOT a dequeue.
dq_pair landing landing
if [[ "$DQ_RC" -eq 11 ]] && grep -q 'kind=noop rc=11 — .*MERGED' "$DQ/out" && ! grep -q 'kind=dequeued' "$DQ/out" && dq_unmoved; then pass "dequeue: OPEN-then-MERGED across the confirming re-read is never reported as a dequeue"; else fail "dequeue landing race: rc=$DQ_RC out=$(tr '\n' ' ' < "$DQ/out")"; fi
rm -rf "$DQ"

# E1: a removal event alone (NO marker: never seen queued, or seen on a tick that read CLEAN/BLOCKED) is a dequeue —
# armed or not — with the removal reason on the line; a CURRENT event only (re-armed / fixed-and-pushed are not).
dq_removal() {  # <name> <mode> <want-rc> <want-regex> [forbid-regex]
  local name="$1" mode="$2" want_rc="$3" want_re="$4" forbid="${5:-}"
  DQ="$(mktemp -d "$TMPDIR/sync-dequeue-$name.XXXXXXXX")"; FIXTURES+=("$DQ")
  make_pair "$DQ"; advance_main "$DQ" h extra; QPR="$QUEUE_PR" install_gh_forbidden "$DQ/bin" "$mode"
  dq_head="$(git -C "$DQ/work" rev-parse HEAD)"; dq_remote="$(git -C "$DQ/work" ls-remote --heads origin feat | cut -f1)"
  dq_run "$DQ" "$mode"
  if [[ "$DQ_RC" -eq "$want_rc" ]] && grep -qE "$want_re" "$DQ/out" && { [[ -z "$forbid" ]] || ! grep -qE "$forbid" "$DQ/out"; }; then
    pass "removal event ($name): rc $DQ_RC, $(printf '%s' "$want_re" | cut -c1-70)"
  else fail "removal event ($name): rc=$DQ_RC (want $want_rc) out=$(tr '\n' ' ' < "$DQ/out" | cut -c1-300)"; fi
}
dq_removal armed-never-queued removed 13 'kind=dequeued rc=13 — .*removal reason: checks_timed_out' ; dq_unmoved && pass "removal event (armed): nothing merged or pushed" || fail "removal event (armed): the branch moved"
[[ "$(cat "$DQ/bin/gql-count")" -eq 2 ]] && pass "removal event: re-read once before reporting (2 reads)" || fail "removal event: reads=$(cat "$DQ/bin/gql-count") (want 2)"
grep -q 'merge-queue-dequeue.md' "$DQ/out" && pass "dequeued line carries the recovery pointer" || fail "dequeued line lost the recovery pointer"
rm -rf "$DQ"
dq_removal disarmed-never-queued removed_disarmed 13 'kind=dequeued rc=13 — .*removal reason: checks_timed_out'; rm -rf "$DQ"
dq_removal rearmed-after-removal rearmed 0 '' 'kind=dequeued'; rm -rf "$DQ"
dq_removal fixed-and-pushed-after-removal removed_pushed 0 '' 'kind=dequeued'; rm -rf "$DQ"

# --- --queue-state: the shared read the pre-merge hook and monitor-pr-checks.sh call ---------
# Read-only (no git, no worktree): runs from a directory that is NOT a repository, against the same
# raw-GraphQL stub, and prints `<verdict> <state> <auto-merge>`; a failed read is kind=gh, exit 4,
# with the cause class (timeout | gh_error | unparseable) — never a verdict.
qs_run() {  # <qmode> [env…] → QS_RC, output in $QSD/out
  QSD="$(mktemp -d "$TMPDIR/sync-qs.XXXXXXXX")"; FIXTURES+=("$QSD")
  local qm="$1"; shift
  QPR="$QUEUE_PR" install_gh_forbidden "$QSD/bin" "$qm"
  ( cd "$QSD" && env GIT_CEILING_DIRECTORIES="$(dirname "$QSD")" "$@" PATH="$QSD/bin:$PATH" bash "$SUT" "$QUEUE_PR" --queue-state ) >"$QSD/out" 2>"$QSD/err"
  QS_RC=$?; collect "$QSD/out" "$QSD/err"
}
qs_check() {  # <label> <qmode> <want-rc> <want-stdout-regex> [env…]
  local label="$1" qm="$2" want_rc="$3" want_re="$4"; shift 4
  qs_run "$qm" "$@"
  if [[ "$QS_RC" -eq "$want_rc" ]] && grep -qE "$want_re" "$QSD/out" && [[ ! -s "$QSD/err" ]] \
     && [[ "$(sort -u "$QSD/bin/gql-number")" == "$QUEUE_PR" ]] && grep -q 'isInMergeQueue' "$QSD/bin/gql-query" \
     && { [[ -z "${QS_CALLS_RE:-}" ]] || grep -qE -e "$QS_CALLS_RE" "$QSD/bin/gql-calls"; } \
     && { [[ -z "${QS_READS:-}" ]] || [[ "$(cat "$QSD/bin/gql-count" 2>/dev/null || echo 0)" == "$QS_READS" ]]; }; then
    pass "--queue-state $label: rc $QS_RC, stdout matches $want_re, stderr empty, PR $QUEUE_PR queried"
  else
    fail "--queue-state $label: rc=$QS_RC out=$(tr '\n' ' ' < "$QSD/out") err=$(tr '\n' ' ' < "$QSD/err")"
  fi
  rm -rf "$QSD"
}
qs_check "queued" queued 0 '^queued OPEN armed removal=none$'
qs_check "not queued, armed" notqueued 0 '^not_queued OPEN armed removal=none$'
qs_check "dequeued shape (auto-merge disarmed, no removal event, never seen queued)" dequeued 0 '^not_queued OPEN disarmed removal=none$'
qs_check "merged" merged 0 '^not_queued MERGED disarmed removal=none$'
qs_check "entry only" entryonly 0 '^queued OPEN armed removal=none$'
qs_check "read fails" gqlfail 4 'kind=gh rc=4 — .*cause=gh_error'
qs_check "unparseable" shapeless 4 'kind=gh rc=4 — .*cause=unparseable'
# E5: --queue-state alone gets the SAME retry as the --step path (the --help text says so): the default is
# two attempts, so one transient failure is ridden out; PR_QUEUE_ATTEMPTS=1 opts out; a persistent failure is 2 reads.
qs_check "default attempts ride out one transient failure" flaky 0 '^not_queued OPEN armed removal=none$'
qs_check "PR_QUEUE_ATTEMPTS=1: one transient failure is a failure" flaky 4 'kind=gh rc=4 — .*cause=gh_error' PR_QUEUE_ATTEMPTS=1
QS_READS=2 qs_check "a persistent failure is read twice (one retry), then kind=gh" gqlfail 4 'kind=gh rc=4 — .*cause=gh_error'
QS_CALLS_RE='-F owner=acme -F name=widgets -F number=4242' qs_check "PR_QUEUE_REPO is passed as owner/name" notqueued 0 '^not_queued OPEN armed removal=none$' PR_QUEUE_REPO=acme/widgets
QS_CALLS_RE='-F owner=\{owner\} -F name=\{repo\} -F number=4242' qs_check "no PR_QUEUE_REPO: gh fills {owner}/{repo} from the cwd repo" notqueued 0 '^not_queued OPEN armed removal=none$'
qs_check "timeout is reported as cause=timeout" hang 4 'cause=timeout' PR_QUEUE_TIMEOUT=1
# E1: a removal event is read by the SAME query (timelineItems REMOVED_FROM_MERGE_QUEUE_EVENT) and surfaces the reason;
# a PR that is out of the queue, OPEN, with a CURRENT removal event is `dequeued` whether or not auto-merge is armed and
# whether or not it was ever seen queued (no marker: this runs outside a worktree).
qs_check "removal event, auto-merge still armed, never seen queued -> dequeued with the reason" removed 0 '^dequeued OPEN armed removal=checks_timed_out$'
qs_check "removal event, auto-merge disarmed -> dequeued with the reason" removed_disarmed 0 '^dequeued OPEN disarmed removal=checks_timed_out$'
qs_check "a removal event OLDER than the re-arm is not current: no dequeue" rearmed 0 '^not_queued OPEN armed removal=none$'
qs_check "a removal event OLDER than the head commit (a fix was pushed since) is not current: no dequeue" removed_pushed 0 '^not_queued OPEN armed removal=none$'
QS_READS=2 qs_check "a dequeue candidate is re-read once before it is reported" removed 0 '^dequeued '
# The query itself selects the timeline and the head commit date (the removal verdict needs both).
qs_run removed
if grep -q 'timelineItems' "$QSD/bin/gql-query" && grep -q 'REMOVED_FROM_MERGE_QUEUE_EVENT' "$QSD/bin/gql-query" && grep -q 'RemovedFromMergeQueueEvent' "$QSD/bin/gql-query" \
   && grep -q 'committedDate' "$QSD/bin/gql-query" && grep -q 'enabledAt' "$QSD/bin/gql-query"; then
  pass "--queue-state query selects timelineItems(REMOVED_FROM_MERGE_QUEUE_EVENT), the removal reason/createdAt, enabledAt and the head committedDate"
else fail "--queue-state query lacks a removal-verdict field: $(tr '\n' ' ' < "$QSD/bin/gql-query" | cut -c1-300)"; fi
rm -rf "$QSD"
# The query asks for the TOP-LEVEL `state` and `autoMergeRequest` (the stub keeps only fields the query names, so a query
# that dropped them would read `-` and every MERGED/disarmed row above would go red; this row names the contract).
qs_run notqueued
if sed -E 's/\{[^{}]*\}//g' "$QSD/bin/gql-query" | grep -cE >/dev/null '(^|[^A-Za-z_])state([^A-Za-z_]|$)' && grep -q 'autoMergeRequest' "$QSD/bin/gql-query"; then
  pass "--queue-state query names the top-level state and autoMergeRequest"
else fail "--queue-state query lost state/autoMergeRequest"; fi
rm -rf "$QSD"

# --- E1/E5 on a REAL worktree: marker + removal rules, stale markers, per-worktree scope -----------------------
# qd_tick <dir> <mode> — one --queue-state call from the dir's worktree (the marker lives in its git dir).
qd_tick() { printf '%s\n' "$2" > "$1/bin/gql-mode"; ( cd "$1/work" && assert_in_fixture "$1/work" && PATH="$1/bin:$PATH" bash "$SUT" "$QUEUE_PR" --queue-state ) >"$1/out" 2>"$1/err"; QD_RC=$?; collect "$1/out" "$1/err"; }
QD="$(mktemp -d "$TMPDIR/sync-qd.XXXXXXXX")"; FIXTURES+=("$QD")
make_pair "$QD"; QPR="$QUEUE_PR" install_gh_forbidden "$QD/bin" notqueued
# a stale marker (a PR seen queued, then MERGED) must not produce a dequeue verdict, and is cleared by the --step path
touch "$QD/work/.git/pr-queue-seen-$QUEUE_PR"
qd_tick "$QD" merged
if [[ "$QD_RC" -eq 0 && "$(cat "$QD/out")" == "not_queued MERGED disarmed removal=none" ]]; then pass "--queue-state: a stale marker on a MERGED PR is not a dequeue"; else fail "--queue-state stale marker + merged: rc=$QD_RC out=$(tr '\n' ' ' < "$QD/out")"; fi
# a marker + the PR OPEN and out of the queue = dequeued even with auto-merge armed and no removal event (it was seen queued).
# The REPORT is the consumption (D1): the marker alone must not re-report the same PR on every later read, or a PR
# the agent fixed and re-armed (CI still running, not queued yet) would be reported dequeued again and the poll stopped again.
QD_MARKER="$QD/work/.git/pr-queue-seen-$QUEUE_PR"
qd_tick "$QD" notqueued
if [[ "$QD_RC" -eq 0 && "$(cat "$QD/out")" == "dequeued OPEN armed removal=none" ]]; then pass "--queue-state: marker present, OPEN, out of the queue -> dequeued"; else fail "--queue-state marker + not queued: rc=$QD_RC out=$(tr '\n' ' ' < "$QD/out")"; fi
[[ ! -e "$QD_MARKER" ]] && pass "--queue-state: printing dequeued consumes the marker (the report is the consumption)" || fail "--queue-state printed dequeued but left the marker"
qd_tick "$QD" notqueued
if [[ "$QD_RC" -eq 0 && "$(cat "$QD/out")" == "not_queued OPEN armed removal=none" ]]; then pass "--queue-state: the SAME PR is not reported dequeued a second time (re-armed after the fix: not queued yet)"; else fail "--queue-state second read after the report: rc=$QD_RC out=$(tr '\n' ' ' < "$QD/out")"; fi
# a CURRENT removal event needs no marker; a stale marker beside it is consumed by the same report, and a re-arm afterwards
# (enabledAt newer than the removal) reads not_queued: the removal event stops matching.
touch "$QD_MARKER"
qd_tick "$QD" removed
if [[ "$QD_RC" -eq 0 && "$(cat "$QD/out")" == "dequeued OPEN armed removal=checks_timed_out" && ! -e "$QD_MARKER" ]]; then pass "--queue-state: marker + current removal event -> dequeued with the reason, marker consumed"; else fail "--queue-state marker + removal: rc=$QD_RC out=$(tr '\n' ' ' < "$QD/out") marker=$([[ -e "$QD_MARKER" ]] && echo present || echo gone)"; fi
qd_tick "$QD" removed
if [[ "$QD_RC" -eq 0 && "$(cat "$QD/out")" == "dequeued OPEN armed removal=checks_timed_out" ]]; then pass "--queue-state: a CURRENT removal event is reported on every read with no marker (the event, not the marker, carries it)"; else fail "--queue-state removal without marker: rc=$QD_RC out=$(tr '\n' ' ' < "$QD/out")"; fi
qd_tick "$QD" rearmed
if [[ "$QD_RC" -eq 0 && "$(cat "$QD/out")" == "not_queued OPEN armed removal=none" ]]; then pass "--queue-state: re-armed after the removal (enabledAt newer than the event) -> not_queued, no second dequeue"; else fail "--queue-state re-armed after removal: rc=$QD_RC out=$(tr '\n' ' ' < "$QD/out")"; fi
touch "$QD_MARKER"
qd_tick "$QD" rearmed
if [[ "$QD_RC" -eq 0 && "$(cat "$QD/out")" == "dequeued OPEN armed removal=none" && ! -e "$QD_MARKER" ]]; then pass "--queue-state: a marker beside a re-armed PR is reported once (removal=none) and consumed"; else fail "--queue-state marker + rearmed: rc=$QD_RC out=$(tr '\n' ' ' < "$QD/out")"; fi
# a NON-dequeued verdict never consumes the marker: MERGED (cleared by --step), the landing race, and queued all leave it.
touch "$QD_MARKER"
qd_tick "$QD" merged
if [[ "$QD_RC" -eq 0 && "$(cat "$QD/out")" == "not_queued MERGED disarmed removal=none" && -f "$QD_MARKER" ]]; then pass "--queue-state: a MERGED read is not a report, so the marker is kept"; else fail "--queue-state merged consumed the marker or misreported: rc=$QD_RC out=$(tr '\n' ' ' < "$QD/out")"; fi
# the queue's own merge landing between the two reads (not queued + OPEN, then MERGED) is NEVER a dequeue
rm -f "$QD/bin/gql-landed" "$QD/bin/gql-count"; qd_tick "$QD" landing
if [[ "$QD_RC" -eq 0 && "$(cat "$QD/out")" == "not_queued MERGED disarmed removal=none" && "$(cat "$QD/bin/gql-count")" -ge 2 && -f "$QD_MARKER" ]]; then
  pass "--queue-state: marker + OPEN-then-MERGED across the confirming re-read is not reported as a dequeue (marker kept)"
else fail "--queue-state landing race: rc=$QD_RC out=$(tr '\n' ' ' < "$QD/out") reads=$(cat "$QD/bin/gql-count")"; fi
# queued again: the marker does not matter, the verdict is queued, and it is not consumed
qd_tick "$QD" queued
if [[ "$QD_RC" -eq 0 && "$(cat "$QD/out")" == "queued OPEN armed removal=none" && -f "$QD_MARKER" ]]; then pass "--queue-state: a stale marker on a PR that is queued again reads queued (marker kept)"; else fail "--queue-state stale marker + queued: rc=$QD_RC out=$(tr '\n' ' ' < "$QD/out")"; fi
# MUTATION ROWS (the consume-on-report rows above are only worth what they fail on): each mutant of the SUT must turn the
# scenario below red, and the control (the real SUT) must be green. The mutant is asserted to DIFFER from the SUT, so a
# sed/replace that silently matched nothing cannot read as a caught mutant.
consume_scenario() {  # <sut-path> → 0 iff: first read dequeued + marker gone, second read not_queued, queued/MERGED keep the marker
  local sut="$1" d ok=0 o1 o2 o3 o4
  d="$(mktemp -d "$TMPDIR/sync-consume.XXXXXXXX")"; FIXTURES+=("$d")
  make_pair "$d"; QPR="$QUEUE_PR" install_gh_forbidden "$d/bin" notqueued
  assert_fixture_dir "$d"
  local m="$d/work/.git/pr-queue-seen-$QUEUE_PR"
  one() { printf '%s\n' "$1" > "$d/bin/gql-mode"; ( cd "$d/work" && PATH="$d/bin:$PATH" bash "$sut" "$QUEUE_PR" --queue-state 2>/dev/null ); }
  touch "$m"
  o1="$(one notqueued)"; [[ -e "$m" ]] && ok=1
  o2="$(one notqueued)"
  touch "$m"; o3="$(one queued)"; [[ -e "$m" ]] || ok=1
  o4="$(one merged)"; [[ -e "$m" ]] || ok=1
  [[ "$o1" == "dequeued OPEN armed removal=none" && "$o2" == "not_queued OPEN armed removal=none" \
     && "$o3" == "queued OPEN armed removal=none" && "$o4" == "not_queued MERGED disarmed removal=none" && "$ok" -eq 0 ]]
  local rc=$?
  unset -f one
  rm -rf "$d"
  return "$rc"
}
if consume_scenario "$SUT"; then pass "mutation control: the real SUT satisfies the consume-on-report scenario"; else fail "mutation control: the real SUT fails the consume-on-report scenario"; fi
SUT_SRC="$(cat "$SUT")"
consume_mutant() {  # <label> <old> <new>
  local label="$1" old="$2" new="$3" md mut
  [[ "$SUT_SRC" == *"$old"* ]] || { fail "mutation '$label': the anchor text is absent from the SUT, so the mutant would not differ (fix the row)"; return; }
  md="$(mktemp -d "$TMPDIR/sync-mutant.XXXXXXXX")"; FIXTURES+=("$md"); assert_fixture_dir "$md"
  mut="$md/sync-pr-behind.sh"; printf '%s\n' "${SUT_SRC/"$old"/"$new"}" > "$mut"
  if cmp -s "$mut" "$SUT"; then fail "mutation '$label': the mutant equals the SUT"; rm -rf "$md"; return; fi
  if consume_scenario "$mut"; then fail "mutation '$label' SURVIVED: the consume-on-report scenario stayed green"; else pass "mutation '$label' caught by the consume-on-report scenario"; fi
  rm -rf "$md"
}
consume_mutant "not consuming (the marker survives the dequeued report)" $'      [[ -z "$qs_marker" ]] || rm -f "$qs_marker"   # consume-on-report\n' ''
consume_mutant "consuming on a non-dequeued verdict" $'    if dq_candidate "$qs_marker"; then\n' $'    [[ -z "$qs_marker" ]] || rm -f "$qs_marker"\n    if dq_candidate "$qs_marker"; then\n'
# per-worktree scope: a marker in ANOTHER worktree's git dir is never read
git -C "$QD/work" worktree add -q -b other "$QD/other" 2>/dev/null
assert_fixture_dir "$QD"
QD_OTHER_GITDIR="$(git -C "$QD/other" rev-parse --git-dir)"
[[ "$QD_OTHER_GITDIR" != "$QD/work/.git" && "$QD_OTHER_GITDIR" == */worktrees/* ]] || fail "worktree fixture: expected a linked worktree git dir, got $QD_OTHER_GITDIR"
printf '%s\n' notqueued > "$QD/bin/gql-mode"
( cd "$QD/other" && PATH="$QD/bin:$PATH" bash "$SUT" "$QUEUE_PR" --queue-state ) >"$QD/out2" 2>"$QD/err2"; collect "$QD/out2" "$QD/err2"
if [[ "$(cat "$QD/out2")" == "not_queued OPEN armed removal=none" ]]; then
  pass "a marker in another worktree's git dir ($QD/work/.git) is not read: the linked worktree reads not_queued"
else fail "marker leaked across worktrees: out=$(tr '\n' ' ' < "$QD/out2")"; fi
rm -rf "$QD"

# =============================================================================
# Armed BEHIND PR on a merge-queue repo (2026-10-09, PR 9839 incident). Between `gh pr merge --auto` and the enqueue the
# PR is OPEN, BEHIND, armed and NOT in the queue; queue_gate cannot see it, and a sync there pushes a commit that restarts
# every required check for nothing (the queue makes the PR current itself). The standalone loop must answer
# kind=queue_wait (exit 0) with NO fetch, merge or push when `main` has a merge_queue rule AND auto-merge is armed.
# The rules read is the stub above (raw live-shape JSON through the SUT's own --jq); `git` is a recording shim, so
# "no push" is asserted from the log of every git call, never inferred.
# =============================================================================
export PR_QUEUE_REPO=o/r
# qw_run <rules-mode> <gql-mode> <state1> <state2> [loop args…] — one loop run in a fresh fixture. Leaves the fixture in
# QW_D, the exit code in QW_RC, the moved flag (HEAD, origin/feat or origin/main changed) in QW_MOVED. QW_SUT overrides the
# script under test (the in-suite mutant rows).
qw_run() {
  local rmode="$1" gmode="$2" s1="$3" s2="$4" h r m; shift 4
  QW_D="$(mktemp -d "$TMPDIR/sync-qw.XXXXXXXX")"; FIXTURES+=("$QW_D")
  make_pair "$QW_D"
  advance_main "$QW_D" h extra
  if [[ -n "${QW_SUT:-}" ]]; then cp "$QW_SUT" "$QW_D/work/plugins/soleur/scripts/sync-pr-behind.sh"; fi
  export QPR="$QUEUE_PR"
  install_gh "$QW_D/bin" "$s1" "$s2" feat ok "$gmode"
  printf '%s\n' "$rmode" > "$QW_D/bin/rules-mode"
  install_git_shim "$QW_D/bin"
  h="$(git -C "$QW_D/work" rev-parse HEAD)"
  r="$(git -C "$QW_D/work" ls-remote --heads origin feat | cut -f1)"
  m="$(git -C "$QW_D/work" rev-parse refs/remotes/origin/main)"
  run_loop "$QW_D" "$@"; QW_RC=$?
  unset QPR
  QW_MOVED=no
  [[ "$h" == "$(git -C "$QW_D/work" rev-parse HEAD)" && "$r" == "$(git -C "$QW_D/work" ls-remote --heads origin feat | cut -f1)" \
     && "$m" == "$(git -C "$QW_D/work" rev-parse refs/remotes/origin/main)" ]] || QW_MOVED=yes
  collect "$QW_D/out" "$QW_D/err"
}
# Predicates grep the log FILE directly (a pipe into `grep -q` takes SIGPIPE under pipefail and fails open on a negation).
qw_gitcalls() { { cat "$QW_D/bin/git-calls" 2>/dev/null || true; }; }
qw_wrote() { grep -qE '(^| )(push|fetch|merge)( |$)' "$QW_D/bin/git-calls" 2>/dev/null; }   # a fetch, merge or push happened
qw_pushes() { grep -cE '(^| )push( |$)' "$QW_D/bin/git-calls" 2>/dev/null || true; }
qw_rulescalls() { { cat "$QW_D/bin/rules-calls" 2>/dev/null || true; } | wc -l | tr -d ' '; }
qw_done() { rm -rf "$QW_D"; }
QW_LINE='^\[pr-behind-sync\] kind=queue_wait rc=0 — '

# The queue-armed arm the incident hit: BEHIND + armed + merge_queue rule. Nothing is fetched, merged or pushed.
q1_ok() {  # → 0 iff the refusal arm holds in QW_D (rows Q1 / Q1b and the in-suite mutant rows)
  [[ "$QW_RC" -eq 0 && "$QW_MOVED" == no ]] && grep -qE "$QW_LINE" "$QW_D/out" \
    && ! grep -q 'auto-sync [0-9]* pushed' "$QW_D/out" && ! grep -q 'kind=behind\|BEHIND detected' "$QW_D/out" \
    && grep -q '^rev-parse' "$QW_D/bin/git-calls" 2>/dev/null && ! qw_wrote
}
qw_run queue notqueued "OPEN BEHIND" "OPEN BEHIND"
if q1_ok && [[ "$(qw_rulescalls)" == 1 ]] && grep -q 'repos/o/r/rules/branches/main?per_page=100' "$QW_D/bin/rules-calls" \
   && grep -qE 'queue_wait.*not syncing' "$QW_D/out" && grep -q 'merge-queue-dequeue.md' "$QW_D/out"; then
  pass "Q1 queue-armed: kind=queue_wait rc 0, no fetch/merge/push in the git-call log, HEAD/origin/feat/origin/main unmoved, one rules read of repos/o/r/rules/branches/main"
else
  fail "Q1 queue-armed: rc=$QW_RC moved=$QW_MOVED rules-calls=$(qw_rulescalls) git-calls=$(qw_gitcalls | tr '\n' ',' | cut -c1-200) out=$(tr '\n' ' ' < "$QW_D/out" | cut -c1-300) err=$(tr '\n' ' ' < "$QW_D/err" | cut -c1-200)"
fi
qw_done
qw_run queue2 notqueued "OPEN BEHIND" "OPEN BEHIND"
if q1_ok; then pass "Q1b two merge_queue entries: still kind=queue_wait (the count is >= 1, not == 1)"
else fail "Q1b two entries: rc=$QW_RC moved=$QW_MOVED out=$(tr '\n' ' ' < "$QW_D/out" | cut -c1-300)"; fi
qw_done
# merge_queue first / last in the rules array: the selector is by .type, never by position.
for qpos in queue_first queue_last; do
  qw_run "$qpos" notqueued "OPEN BEHIND" "OPEN BEHIND"
  if q1_ok; then pass "Q1 merge_queue rule at the $qpos position: still kind=queue_wait (selected by .type, not by index)"
  else fail "Q1 $qpos: rc=$QW_RC moved=$QW_MOVED out=$(tr '\n' ' ' < "$QW_D/out" | cut -c1-300)"; fi
  qw_done
done
# The production default (no PR_QUEUE_REPO): gh itself fills {owner}/{repo} from the cwd repository.
SAVE_PQR="$PR_QUEUE_REPO"; unset PR_QUEUE_REPO
qw_run queue notqueued "OPEN BEHIND" "OPEN BEHIND"
export PR_QUEUE_REPO="$SAVE_PQR"
if q1_ok && grep -qF 'repos/{owner}/{repo}/rules/branches/main?per_page=100' "$QW_D/bin/rules-calls"; then
  pass "Q1 default repo: the rules read asks gh for repos/{owner}/{repo}/rules/branches/main?per_page=100"
else fail "Q1 default repo: rc=$QW_RC rules-calls=$(tr '\n' ',' < "$QW_D/bin/rules-calls" 2>/dev/null)"; fi
qw_done

# Queue-absent: today's behaviour. The shim must RECORD the push (the positive control for every "no push" row above).
qw_run none notqueued "OPEN BEHIND" "OPEN CLEAN"
if [[ "$QW_RC" -eq 0 && "$QW_MOVED" == yes ]] && grep -q 'auto-sync 1 pushed' "$QW_D/out" && [[ "$(qw_pushes)" -ge 1 ]] \
   && ! grep -q 'kind=queue_wait' "$QW_D/out"; then
  pass "Q2 queue-absent (rules []): still syncs and pushes, and the git shim recorded the push"
else fail "Q2 queue-absent: rc=$QW_RC moved=$QW_MOVED git-calls=$(qw_gitcalls | tr '\n' ',' | cut -c1-200) out=$(tr '\n' ' ' < "$QW_D/out" | cut -c1-300)"; fi
qw_done
# Armed but the base has no merge_queue rule (the live shape minus merge_queue): still syncs.
qw_run other notqueued "OPEN BEHIND" "OPEN CLEAN"
if [[ "$QW_RC" -eq 0 && "$QW_MOVED" == yes ]] && grep -q 'auto-sync 1 pushed' "$QW_D/out" && ! grep -q 'kind=queue_wait' "$QW_D/out" \
   && [[ "$(qw_rulescalls)" == 1 ]]; then
  pass "R2 armed, no merge_queue rule: still syncs (rules read once)"
else fail "R2 armed without a queue rule: rc=$QW_RC moved=$QW_MOVED out=$(tr '\n' ' ' < "$QW_D/out" | cut -c1-300)"; fi
qw_done
# A merge_queue rule but auto-merge is NOT armed: syncs, and the rules endpoint is never asked (armed is checked first).
r3_ok() { [[ "$QW_RC" -eq 0 && "$QW_MOVED" == yes ]] && grep -q 'auto-sync 1 pushed' "$QW_D/out" && ! grep -q 'kind=queue_wait' "$QW_D/out" && [[ "$(qw_rulescalls)" == 0 ]]; }
qw_run queue dequeued "OPEN BEHIND" "OPEN CLEAN"
if r3_ok; then pass "R3 merge_queue rule but auto-merge disarmed: still syncs; no rules read (armed is checked first)"
else fail "R3 rule, not armed: rc=$QW_RC moved=$QW_MOVED rules-calls=$(qw_rulescalls) out=$(tr '\n' ' ' < "$QW_D/out" | cut -c1-300)"; fi
qw_done
# DIRTY (merge-tree clean) + rule + armed: the guard is BEHIND-only, so the kb-index class still resolves (no livelock).
qw_run queue notqueued "OPEN DIRTY" "OPEN CLEAN"
if [[ "$QW_RC" -eq 0 && "$QW_MOVED" == yes ]] && grep -q 'auto-sync 1 pushed' "$QW_D/out" && ! grep -q 'kind=queue_wait' "$QW_D/out" && [[ "$(qw_rulescalls)" == 0 ]]; then
  pass "R4 DIRTY + rule + armed: still syncs (the guard fires for BEHIND only)"
else fail "R4 DIRTY: rc=$QW_RC moved=$QW_MOVED rules-calls=$(qw_rulescalls) out=$(tr '\n' ' ' < "$QW_D/out" | cut -c1-300)"; fi
qw_done
# An unreadable rules read while armed FAILS CLOSED (kind=gh, rc 4), like queue_gate: a push to a queued PR would dequeue it.
for rm_ in fail garbage empty; do
  qw_run "$rm_" notqueued "OPEN BEHIND" "OPEN CLEAN"
  if [[ "$QW_RC" -eq 4 && "$QW_MOVED" == no ]] && grep -qE '^\[pr-behind-sync\] kind=gh rc=4 — .*merge-queue rule read failed' "$QW_D/out" && ! qw_wrote; then
    pass "R5 rules read $rm_ while armed: kind=gh rc 4, nothing fetched, merged or pushed"
  else fail "R5 rules read $rm_: rc=$QW_RC moved=$QW_MOVED out=$(tr '\n' ' ' < "$QW_D/out" | cut -c1-300)"; fi
  qw_done
done
# A read that FAILED (exit 1) is not graded on its stdout, even when stdout is a valid 0; and the read is retried once.
qw_run numfail notqueued "OPEN BEHIND" "OPEN CLEAN"
if [[ "$QW_RC" -eq 4 && "$QW_MOVED" == no ]] && grep -qE '^\[pr-behind-sync\] kind=gh rc=4 — .*merge-queue rule read failed after 2 attempt' "$QW_D/out" \
   && [[ "$(qw_rulescalls)" == 2 ]] && ! qw_wrote; then
  pass "R5 rules read exits 1 with a valid-looking 0 on stdout: kind=gh rc 4 after 2 attempts, nothing pushed"
else fail "R5 numfail: rc=$QW_RC moved=$QW_MOVED rules-calls=$(qw_rulescalls) out=$(tr '\n' ' ' < "$QW_D/out" | cut -c1-300)"; fi
qw_done
# A hung read is killed by the timeout wrapper and reported with its cause (rc 124), not graded as an empty answer.
PR_QUEUE_TIMEOUT=1 PR_QUEUE_ATTEMPTS=1 qw_run hang notqueued "OPEN BEHIND" "OPEN CLEAN"
if [[ "$QW_RC" -eq 4 && "$QW_MOVED" == no ]] && grep -qE 'kind=gh rc=4 — .*after 1 attempt.*rc=124' "$QW_D/out" && ! qw_wrote; then
  pass "R5 rules read hangs: killed at PR_QUEUE_TIMEOUT, kind=gh rc 4 naming rc=124, nothing pushed"
else fail "R5 hang: rc=$QW_RC moved=$QW_MOVED out=$(tr '\n' ' ' < "$QW_D/out" | cut -c1-300)"; fi
qw_done
# The cause is echoed sanitised: an ESC byte and a forged tag line on gh's stderr reach neither the control stream nor a second line.
qw_run ctl notqueued "OPEN BEHIND" "OPEN CLEAN"
if [[ "$QW_RC" -eq 4 && "$QW_MOVED" == no ]] && ! grep -q $'\033' "$QW_D/out" && [[ "$(grep -c '^\[pr-behind-sync\]' "$QW_D/out")" -eq 2 ]] \
   && ! grep -q '^\[pr-behind-sync\] kind=forged' "$QW_D/out" && grep -q 'kind=gh rc=4' "$QW_D/out"; then
  pass "R5 rules read stderr carries ESC and a forged tag: sanitised, kind=gh rc 4 is the only tag after the state line"
else fail "R5 ctl: rc=$QW_RC moved=$QW_MOVED out=$(tr '\n' ' ' < "$QW_D/out" | cut -c1-300 | cat -v)"; fi
qw_done
# Second attempt (the gate runs EVERY attempt): the first read has no queue rule and syncs; the rule appears before the
# second attempt, which must answer kind=queue_wait — never kind=noop, never a second push. Both state reads are BEHIND.
qw_run flip notqueued "OPEN BEHIND" "OPEN BEHIND" --max-attempts 2
if [[ "$QW_RC" -eq 0 ]] && [[ "$(grep -c 'auto-sync [0-9]* pushed' "$QW_D/out")" == 1 ]] && grep -qE "$QW_LINE" "$QW_D/out" \
   && ! grep -q 'kind=noop' "$QW_D/out" && [[ "$(qw_rulescalls)" == 2 ]] && [[ "$(qw_pushes)" == 1 ]]; then
  pass "R6 second attempt: attempt 1 pushes, attempt 2 reads the rule again and answers kind=queue_wait (2 rules reads, 1 push, no noop)"
else fail "R6 second attempt: rc=$QW_RC rules-calls=$(qw_rulescalls) pushes=$(qw_pushes) out=$(tr '\n' ' ' < "$QW_D/out" | cut -c1-400)"; fi
qw_done
# In the queue: unchanged kind=queued from queue_gate, before the rules endpoint is ever asked.
qw_run queue queued "OPEN BEHIND" "OPEN BEHIND"
if [[ "$QW_RC" -eq 0 && "$QW_MOVED" == no ]] && grep -q '^\[pr-behind-sync\] kind=queued rc=0 — ' "$QW_D/out" && [[ "$(qw_rulescalls)" == 0 ]]; then
  pass "R7 in the queue: unchanged kind=queued, no rules read"
else fail "R7 in queue: rc=$QW_RC moved=$QW_MOVED rules-calls=$(qw_rulescalls) out=$(tr '\n' ' ' < "$QW_D/out" | cut -c1-300)"; fi
qw_done
# --step is the Phase 7 fence's call and is unguarded by design (the fence owns the queue decision and its expiry): it
# still syncs on a queue repo, and makes NO gh call besides the queue read (the forbidden stub logs every other argv).
R8="$(mktemp -d "$TMPDIR/sync-qw-step.XXXXXXXX")"; FIXTURES+=("$R8")
make_pair "$R8"; advance_main "$R8" h extra
export QPR="$QUEUE_PR"; install_gh_forbidden "$R8/bin" notqueued; unset QPR
before="$(git -C "$R8/work" rev-parse HEAD)"
QPR="$QUEUE_PR" run_step "$R8"; rc=$?
if [[ "$rc" -eq 0 && "$(git -C "$R8/work" rev-parse HEAD)" != "$before" ]] && no_gh "$R8" && [[ ! -s "$R8/bin/calls" ]]; then
  pass "R8 --step on a queue repo: unguarded (still syncs), and its only gh call is the queue read"
else fail "R8 --step: rc=$rc calls=$(tr '\n' ' ' < "$R8/bin/calls" 2>/dev/null) out=$(tr '\n' ' ' < "$R8/out" | cut -c1-300)"; fi
collect "$R8/out" "$R8/err"; rm -rf "$R8"

# H1: the git shim must RECORD. A shim that execs without logging would turn every "no push" assertion above vacuous, so
# swap in a non-recording shim, re-run the Q1 fixture and require Q1's own check (q1_ok, which needs the logged rev-parse)
# to go red.
qw_run queue notqueued "OPEN BEHIND" "OPEN BEHIND"
q1_ok || fail "H1 control: the Q1 arm is not green before the shim mutation"
printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$(command -v git)" > "$QW_D/bin/git"
rm -f "$QW_D/bin/git-calls"
export QPR="$QUEUE_PR"; run_loop "$QW_D"; QW_RC=$?; unset QPR
if ! q1_ok && [[ "$QW_RC" -eq 0 ]] && grep -qE "$QW_LINE" "$QW_D/out" && [[ ! -s "$QW_D/bin/git-calls" ]]; then
  pass "H1 harness: with a non-recording git shim q1_ok goes red (the 'no push' assertions need the recorded log)"
else fail "H1 harness: q1_ok stayed green with a non-recording git shim"; fi
qw_done

# MUTATION ROWS (in-suite, permanent): each mutant of the SUT must turn its scenario red; the control is the real SUT. Each
# mutation is asserted to differ from the SUT and to land inside queue_wait_gate, so a no-op replace cannot read as a catch.
qw_scenario() {  # <kind: q1|r3|q1f|hang|numfail|ctl> → 0 iff the scenario holds against $QW_SUT
  local kind="$1" ok=1
  case "$kind" in
    q1) qw_run queue notqueued "OPEN BEHIND" "OPEN BEHIND"; q1_ok && ok=0 ;;
    r3) qw_run queue dequeued "OPEN BEHIND" "OPEN CLEAN"; r3_ok && ok=0 ;;
    q1f) qw_run queue_first notqueued "OPEN BEHIND" "OPEN BEHIND"; q1_ok && ok=0 ;;
    hang) PR_QUEUE_TIMEOUT=1 PR_QUEUE_ATTEMPTS=1 qw_run hang notqueued "OPEN BEHIND" "OPEN CLEAN"
          [[ "$QW_RC" -eq 4 && "$QW_MOVED" == no ]] && grep -q 'rc=124' "$QW_D/out" && ok=0 ;;
    numfail) qw_run numfail notqueued "OPEN BEHIND" "OPEN CLEAN"; [[ "$QW_RC" -eq 4 && "$QW_MOVED" == no ]] && ok=0 ;;
    ctl) qw_run ctl notqueued "OPEN BEHIND" "OPEN CLEAN"; [[ "$QW_RC" -eq 4 ]] && ! grep -q $'\033' "$QW_D/out" && ok=0 ;;
    *) echo "FATAL: qw_scenario: unknown kind '$kind'" >&2; exit 97 ;;
  esac
  qw_done
  return "$ok"
}
QW_SUT=""
if qw_scenario q1 && qw_scenario r3 && qw_scenario q1f && qw_scenario hang && qw_scenario numfail && qw_scenario ctl; then
  pass "mutation control: the real SUT satisfies the queue-armed, disarmed, merge_queue-first, hang and exit-1 scenarios"
else fail "mutation control: the real SUT fails one of the mutation scenarios"; fi
SUT_SRC="$(cat "$SUT")"
qw_mutant() {  # <label> <scenario> <old> <new>
  local label="$1" kind="$2" old="$3" new="$4" md mut
  [[ "$SUT_SRC" == *"$old"* ]] || { fail "mutation '$label': the anchor text is absent from the SUT (fix the row)"; return; }
  # a first-match replace must land where intended: the WHOLE anchor occurs exactly once in the SUT, or the row is wrong
  rest="${SUT_SRC//"$old"/}"
  [[ $(( (${#SUT_SRC} - ${#rest}) / ${#old} )) -eq 1 ]] || { fail "mutation '$label': the anchor occurs more than once in the SUT, so a first-match replace may land outside queue_wait_gate (fix the row)"; return; }
  md="$(mktemp -d "$TMPDIR/sync-qwmut.XXXXXXXX")"; FIXTURES+=("$md"); assert_fixture_dir "$md"
  mut="$md/sync-pr-behind.sh"; printf '%s\n' "${SUT_SRC/"$old"/"$new"}" > "$mut"
  if cmp -s "$mut" "$SUT"; then fail "mutation '$label': the mutant equals the SUT"; rm -rf "$md"; return; fi
  QW_SUT="$mut"
  if qw_scenario "$kind"; then fail "mutation '$label' SURVIVED: the '$kind' scenario stayed green"
  elif [[ "$QW_RC" -eq 2 || "$QW_RC" -eq 127 ]]; then fail "mutation '$label': the mutant does not RUN (rc $QW_RC), so 'caught' would be an instrument error"
  else pass "mutation '$label' caught by the '$kind' scenario"; fi
  QW_SUT=""; rm -rf "$md"
}
qw_mutant "delete the queue_wait_gate call" q1 $'  queue_wait_gate "$state_line"\n' ''
qw_mutant "drop the armed condition (rule only)" r3 $'  [[ "$am" == armed ]] || return 0\n' ''
qw_mutant "read the first rule instead of selecting .type == merge_queue" q1 '[.[] | select(.type == "merge_queue")]' '[.[0] | select(.type == "merge_queue")]'
qw_mutant "read the second rule instead of selecting .type == merge_queue" q1f '[.[] | select(.type == "merge_queue")]' '[.[1] | select(.type == "merge_queue")]'
qw_mutant "drop the timeout wrapper on the rules read" hang $'    out="$(${to[@]+"${to[@]}"} bash -c \'gh api "repos/' $'    out="$(bash -c \'gh api "repos/'
qw_mutant "echo the rules-read cause unsanitised" ctl $'  detail="$(printf \'%s\' "$detail" | tr -c \'[:alnum:] ._:/=-\' \'?\')"\n' ''
qw_mutant "grade the rules read on stdout alone (drop the rc clause)" numfail $'  if [[ "$rc" -eq 0 && "$out" =~ ^[0-9]{1,6}$ ]]; then\n    if (( 10#$out' $'  if [[ "$out" =~ ^[0-9]{1,6}$ ]]; then\n    if (( 10#$out'
unset PR_QUEUE_REPO

# --- argv strictness and --help (no fixture needed: neither touches git) ---------
NOWT="$(mktemp -d "$TMPDIR/sync-notworktree.XXXXXXXX")"
FIXTURES+=("$NOWT")
argv_rc() {  # <args…> → prints rc; stdout/stderr land in $NOWT/out,err (cwd: not a repo)
  ( cd "$NOWT" && GIT_CEILING_DIRECTORIES="$(dirname "$NOWT")" bash "$SUT" "$@" ) >"$NOWT/out" 2>"$NOWT/err"
  local r=$?; collect "$NOWT/out" "$NOWT/err"; echo "$r"
}
rc_bogus=$(argv_rc 1 --bogus)
bogus_ok=0; grep -q '^\[pr-behind-sync\] kind=usage rc=2 — ' "$NOWT/out" && [[ ! -s "$NOWT/err" ]] && bogus_ok=1
rc_mixed=$(argv_rc 1 --step --max-attempts 3)
rc_noarg=$(argv_rc)
if [[ "$rc_bogus" -eq 2 && "$rc_mixed" -eq 2 && "$rc_noarg" -eq 2 && "$bogus_ok" -eq 1 ]]; then
  pass "unknown argument, --step with --max-attempts, and no PR all exit 2 with kind=usage on stdout (stderr empty)"
else
  fail "argv strictness: --bogus rc=$rc_bogus, mixed rc=$rc_mixed, no-arg rc=$rc_noarg (want 2), usage-on-stdout=$bogus_ok"
fi
# --max-attempts must be 1..999: 0, a leading zero and 4 digits are usage errors; 999
# parses (the run then stops at the not-a-worktree check, rc 3).
bad=""
for v in 0 08 1000 -1 ''; do r=$(argv_rc 1 --max-attempts "$v"); [[ "$r" -eq 2 ]] || bad+="[$v→$r] "; done
r999=$(argv_rc 1 --max-attempts 999)
if [[ -z "$bad" && "$r999" -eq 3 ]]; then
  pass "--max-attempts rejects 0/08/1000/-1/empty (rc 2), accepts 999"
else
  fail "--max-attempts validation: bad=${bad:-none} 999→$r999 (want 3)"
fi
rc_nowt=$(argv_rc 1 --step)
if [[ "$rc_nowt" -eq 3 ]] && grep -q '^\[pr-behind-sync\] kind=not_worktree rc=3 — ' "$NOWT/out" && [[ ! -s "$NOWT/err" ]]; then
  pass "not inside a work tree: rc 3, kind=not_worktree rc=3 on stdout"
else
  fail "not-a-worktree: rc=$rc_nowt out=$(tr '\n' ' ' < "$NOWT/out") err=$(tr '\n' ' ' < "$NOWT/err")"
fi
help_out="$(bash "$SUT" --help 2>/dev/null)"; rc_help=$?
if [[ "$rc_help" -eq 0 ]] && grep -q -- '--step' <<<"$help_out" && grep -q 'exit codes' <<<"$help_out" \
   && grep -qE '^  10 ' <<<"$help_out" && grep -qE '^  11 .*kind=noop' <<<"$help_out" && grep -qE '^  12 .*wrong_branch' <<<"$help_out" && grep -qE '^  13 .*merge queue' <<<"$help_out" && grep -q 'kind=dequeued' <<<"$help_out" \
   && grep -q 'kind=queued' <<<"$help_out" && grep -qE '^  4 .*kind=gh' <<<"$help_out" && grep -qi 'merge queue' <<<"$help_out"; then
  pass "--help: rc 0, names --step and the exit-code table incl. 11/12 and the merge-queue skip (the fences' capability probe)"
else
  fail "--help: rc=$rc_help out=$help_out"
fi

# --- one merge/push path: the standalone loop reaches git only through sync_step --
# (M8) An inline `git merge origin` or `git push` outside sync_step() would be a
# second copy of the state machine this script exists to hold once. Message lines
# (`echo`, `tag`) name git commands as next actions and are excluded.
outside="$(awk '/<<.USAGE.$/{doc=1; next} doc&&/^USAGE$/{doc=0; next} doc{next}
               /^sync_step\(\) \{/{in_fn=1} in_fn&&/^\}/{in_fn=0; next} !in_fn' "$SUT" \
  | grep -vE '^[[:space:]]*(#|echo |tag )' | grep -nE '(^|[^-])git (merge (origin|--abort|--no-edit)|push( |$))' || true)"
inside="$(awk '/^sync_step\(\) \{/{in_fn=1} in_fn&&/^\}/{exit} in_fn' "$SUT" | grep -cE 'git merge origin/main --no-edit' || true)"
if [[ -z "$outside" && "$inside" -eq 1 ]]; then
  pass "git merge/push appear only inside sync_step()"
else
  fail "merge/push outside sync_step: ${outside:-none}; merge lines inside: $inside (want 1)"
fi

# --- both sync_step call sites are exactly `rc=0; sync_step || rc=$?` (T2) ---------
# errexit is suspended inside a function called from an `||` list; a bare call would
# let a display pipe's SIGPIPE kill the script before the --abort.
calls="$(grep -nE '(^|[^_[:alnum:]])sync_step([^_(]|$)' "$SUT" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
ncalls="$(grep -c . <<<"$calls")"
nexact="$(grep -cE '^[0-9]+:[[:space:]]*rc=0; sync_step \|\| rc=\$\?$' <<<"$calls")"
if [[ "$ncalls" -eq 2 && "$nexact" -eq 2 ]]; then
  pass "both sync_step call sites are exactly 'rc=0; sync_step || rc=\$?'"
else
  fail "sync_step call sites: $ncalls found, $nexact exact (want 2/2): $(tr '\n' ' ' <<<"$calls")"
fi

# --- every [pr-behind-sync] line is `kind=<k> rc=<n> ` on stdout (S4) ---------------
ntag="$(grep -c '\[pr-behind-sync\]' "$ALL_OUT" || true)"
badshape="$(grep '\[pr-behind-sync\]' "$ALL_OUT" | grep -vE '^\[pr-behind-sync\] kind=[a-z_]+ rc=[0-9]+ ' || true)"
onerr="$(grep '\[pr-behind-sync\]' "$ALL_ERR" || true)"
kinds="$(grep -oE '^\[pr-behind-sync\] kind=[a-z_]+' "$ALL_OUT" | sort -u | wc -l | tr -d ' ')"
if [[ "$ntag" -ge 30 && "$kinds" -ge 15 && -z "$badshape" && -z "$onerr" ]]; then
  pass "all $ntag [pr-behind-sync] lines ($kinds kinds) match 'kind=<k> rc=<n> ' and none reached stderr"
else
  fail "tag shape: $ntag lines (want >= 30), $kinds kinds (want >= 15); malformed: $(head -3 <<<"$badshape" | tr '\n' '|'); on stderr: $(head -3 <<<"$onerr" | tr '\n' '|')"
fi

echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 && "$PASS" -eq 122 ]]
exit $?
