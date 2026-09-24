#!/usr/bin/env bash
# shellcheck disable=SC2016  # wiring greps match literal workflow source text
# Tests for dev-ledger-parity.sh (#8521 edited/renamed-after-apply, #8520 the
# in-flight arm of the authoritative drift probe).
#
# Two guards, one script (plan: archive/20260923-224929-2026-09-23-fix-pr-ci-unmerged-migration-ledger-parity-plan.md,
# §Guard Contract — row numbers below are that table's):
#
#   Guard 1  `check`            PR-side per-ref ledger parity (A1 edited, A2 renamed,
#                                A4 deleted-after-apply) + its tenant-integration wiring.
#   Guard 2  `classify-missing` main-side ownership of missing-on-main ledger rows
#                                (in-flight / stale / orphan) + the drift-probe action.
#
# #8605 adds (plan 2026-09-23-fix-dev-ledger-closed-unmerged-reconcile-and-migration-gate-cwd-plan.md,
# §Guard Contract Guards 2-4; G2-*/G3-*/G4-* case ids are that table's row ids):
#
#   Guard 2b PR-state-aware classify-missing (closed-grace / closed, commit-bound,
#            fail-closed) + the probe's closed arms and the token wiring.
#   Guard 3  dev-ledger-reconcile.sh, the one writer (a copy, $DLR_WRITER overrides
#            the source), against a separate writer clone, a fake dev-suite mutex,
#            and a fake psql in writer mode (-f payloads logged at call time).
#   Guard 4  .github/workflows/dev-ledger-reconcile.yml wiring + its extracted
#            reconcile step run with a stub writer.
#
# Everything is SYNTHESIZED (cq-test-fixtures-synthesized-only): a bare `origin`
# reached through a file:// URL with uploadpack.allowFilter=true (as GitHub), a
# main history that renames one migration, feature branches pushed to origin, a
# work clone, and a fake `psql` / `doppler` / `curl` / `gh` on PATH (the fake gh is routed,
# sequenced and logged, and never falls through to a real gh). The suite runs a COPY of
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
WRITER_SRC="${DLR_WRITER:-$SCRIPT_DIR/dev-ledger-reconcile.sh}"
WF="$REPO_ROOT/.github/workflows/tenant-integration.yml"
ACTION="$REPO_ROOT/.github/actions/dev-migration-drift-probe/action.yml"
SCHED="$REPO_ROOT/.github/workflows/scheduled-dev-migration-drift.yml"

if [[ ! -f "$GUARD_SRC" ]]; then
  printf 'FATAL: guard not found at %s — the suite refuses to report 0 passed, 0 failed\n' "$GUARD_SRC" >&2
  exit 1
fi
if [[ ! -f "$WRITER_SRC" ]]; then
  printf 'FATAL: writer not found at %s — the suite refuses to report 0 passed, 0 failed\n' "$WRITER_SRC" >&2
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
# Writer-mode contract (dev-ledger-reconcile.sh, DLR_PSQL_WRITER_MODE=1): every call is
# either the writer's ledger SELECT via -c or ONE -f unit. Any other shape is a breach
# (logged, exit 97). A -f unit's CONTENTS are copied into DLR_PSQL_PAYLOAD at call time:
# the writer's EXIT trap deletes the file, so the log is the only place a row can read it.
sql="" file="" prev="" nc=0 nf=0 stop=""
for a in "$@"; do
  if [[ "$prev" == "-c" ]]; then sql="$a"; nc=$((nc + 1)); fi
  if [[ "$prev" == "-f" ]]; then file="$a"; nf=$((nf + 1)); fi
  # psql applies the LAST -v/--set ON_ERROR_STOP it is given.
  if [[ "$prev" == "-v" || "$prev" == "--set" ]] && [[ "$a" == ON_ERROR_STOP=* ]]; then stop="${a#ON_ERROR_STOP=}"; fi
  prev="$a"
done
if [[ -n "${DLR_CALL_LOG:-}" ]]; then
  if [[ "$nf" -gt 0 ]]; then printf 'psql -f gh_token=%s github_token=%s doppler_token=%s\n' "${GH_TOKEN+set}" "${GITHUB_TOKEN+set}" "${DOPPLER_TOKEN+set}" >> "$DLR_CALL_LOG"
  else printf 'psql -c\n' >> "$DLR_CALL_LOG"; fi
fi
if [[ "${DLR_PSQL_WRITER_MODE:-}" == "1" ]]; then
  shape=breach
  if [[ "$nc" == "1" && "$nf" == "0" && "$sql" == "${DLR_WANT_SQL:-}" ]]; then shape=select; fi
  if [[ "$nf" == "1" && "$nc" == "0" && -f "$file" ]]; then shape=unit; fi
  if [[ "$shape" == "breach" ]]; then
    printf 'breach:' >> "${DLR_PSQL_BREACH:-/dev/null}"; printf ' %s' "$@" >> "${DLR_PSQL_BREACH:-/dev/null}"
    printf '\n' >> "${DLR_PSQL_BREACH:-/dev/null}"
    exit 97
  fi
  if [[ "$shape" == "unit" ]]; then
    { printf '=== unit argv:'; printf ' %s' "$@"; printf '\n'; cat "$file"; printf '\n=== end unit\n'; } >> "${DLR_PSQL_PAYLOAD:-/dev/null}"
    printf '%s' "${DLR_FAKE_UNIT_OUT:-}"
    urc="${DLR_FAKE_UNIT_RC:-0}"
    # DLR_FAKE_UNIT_FAIL_AT=<text>: report an error at the unit line carrying <text>, as psql -f does.
    if [[ -n "${DLR_FAKE_UNIT_FAIL_AT:-}" ]]; then
      at=$(grep -nF -m1 -- "$DLR_FAKE_UNIT_FAIL_AT" "$file" | cut -d: -f1)
      printf 'psql:%s:%s: ERROR:  42P01: relation "fixture" does not exist\n' "$file" "${at:-0}" >&2
    fi
    # Without ON_ERROR_STOP=1 real psql runs on after an error and exits 0, while the
    # aborted --single-transaction still rolls back: nothing is committed.
    if [[ "$urc" == "3" && "$stop" != "1" ]]; then exit 0; fi
    # A committed unit: the next ledger read sees the ledger minus every CAS'd row
    # (DLR_FAKE_POST=keep leaves it unchanged; drop:<file> also removes <file>).
    if [[ "$urc" == "0" && -n "${DLR_FAKE_LEDGER:-}" && -f "$DLR_FAKE_LEDGER" ]]; then
      post="$(cat "$DLR_FAKE_LEDGER")"
      if [[ "${DLR_FAKE_POST:-}" != "keep" ]]; then
        while IFS='|' read -r cf cb; do
          [[ -n "$cf" ]] && post=$(grep -vE "^${cf//./\\.}\|${cb}\|" <<<"$post" || true)
        done < <(sed -n "s/^  DELETE FROM public._schema_migrations WHERE filename = '\([^']*\)' AND content_sha = '\([0-9a-f]*\)';$/\1|\2/p" "$file")
      fi
      case "${DLR_FAKE_POST:-}" in drop:*) post=$(grep -vE "^${DLR_FAKE_POST#drop:}\|" <<<"$post" || true) ;; esac
      printf '%s\n' "$post" > "$DLR_FAKE_LEDGER.post"
    fi
    exit "$urc"
  fi
  if [[ -n "${DLR_FAKE_LEDGER:-}" && -f "$DLR_FAKE_LEDGER.post" ]]; then cat "$DLR_FAKE_LEDGER.post"; exit 0; fi
  if [[ -n "${DLR_FAKE_LEDGER:-}" && -f "$DLR_FAKE_LEDGER" ]]; then cat "$DLR_FAKE_LEDGER"; fi
  exit 0
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
# Fake doppler: log argv (when asked) and whether the classifier's GitHub token
# reached it; `configs get` / `secrets --only-names` answer $DLP_FAKE_DOPPLER_CONFIG /
# $DLP_FAKE_DOPPLER_NAMES; `run -p … -c … --` execs the rest.
if [[ -n "${DLP_DOPPLER_LOG:-}" ]]; then printf '%s classifier_token=%s\n' "$*" "${CLASSIFIER_GH_TOKEN+set}" >> "$DLP_DOPPLER_LOG"; fi
case "${1:-}" in
  configs) printf '%s' "${DLP_FAKE_DOPPLER_CONFIG:-}"; exit "${DLP_FAKE_DOPPLER_RC:-0}" ;;
  secrets) printf '%s' "${DLP_FAKE_DOPPLER_NAMES:-}"; exit "${DLP_FAKE_DOPPLER_RC:-0}" ;;
esac
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
cat > "$BIN/gh" <<'SH'
#!/usr/bin/env bash
# Fake gh: ROUTED, SEQUENCED and LOGGED to the same ordered call log as the fake psql
# and the fake mutex. It never falls through to a real gh: an unrecognised call is
# logged as UNROUTED and exits 99. It models GitHub's contracts, not the guard's:
#   GET pulls?head=<owner>:<branch>  $DLR_GH_FIX/head/<branch>.json filtered by state=
#                                    (default open, as GitHub), sorted newest-first
#                                    (number desc), cut to per_page (default 30)
#   GET pulls/<N>                    sequenced per call: $DLR_GH_FIX/pull/<N>.<k>.json, else <N>.json
#   GET issues                       $DLR_GH_FIX/issues.json (state/labels logged), else []
#   GET git/blobs/<id>               raw bytes of <id> from $DLR_GH_BLOB_REPO (DLR_GH_BLOB_CORRUPT=1 appends a byte)
#   POST issues | issues/<N>/comments | labels   the body is copied to $DLR_GH_POSTS/<k>.<kind>
# DLR_GH_MODE (every GET) / DLR_GH_ISSUES_MODE (issues only) / DLR_GH_HEAD_MODE (pulls?head= only): 403 | 5xx | nonjson |
# ratelimit (403 + x-ratelimit-remaining: 0) | ratelimit-body (403 + a "rate limit" body) | 429.
log="${DLR_CALL_LOG:-/dev/null}"
fix="${DLR_GH_FIX:-/nonexistent}"
[[ "${1:-}" == "api" ]] || { printf 'gh UNROUTED %s\n' "$*" >> "$log"; exit 99; }
shift
path="" head="" raw=0 inc=0 method="" state="" per_page="" labels="" jqexpr="" title="" bodyf=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -X|--method) method="$2"; shift 2 ;;
    -i) inc=1; shift ;;
    --paginate) shift ;;
    --jq) jqexpr="$2"; shift 2 ;;
    -H) [[ "$2" == *application/vnd.github.raw* ]] && raw=1; shift 2 ;;
    -f|-F)
      case "$2" in
        head=*) head="${2#head=}" ;;
        state=*) state="${2#state=}" ;;
        per_page=*) per_page="${2#per_page=}" ;;
        labels=*) labels="${2#labels=}" ;;
        title=*) title="${2#title=}" ;;
        body=@*) bodyf="${2#body=@}" ;;
      esac
      shift 2 ;;
    -*) printf 'gh UNROUTED flag %s\n' "$1" >> "$log"; exit 99 ;;
    *) path="$1"; shift ;;
  esac
done
# Never call respond on the right of a pipe: its `exit` would end only that subshell.
respond() {  # respond <status> <body-file|-> [extra-header] ; -i prints the status line and headers first
  local st="$1" f="$2" xh="${3:-}" body
  if [[ "$f" == "-" ]]; then body=$(cat); else body=$(cat "$f"); fi
  if [[ "$inc" == "1" ]]; then
    printf 'HTTP/2.0 %s Fixture\r\nContent-Type: application/json\r\n' "$st"
    [[ -n "$xh" ]] && printf '%s\r\n' "$xh"
    printf '\r\n'
  fi
  if [[ -n "$jqexpr" && "$st" -lt 400 ]]; then jq -r "$jqexpr" <<<"$body" || exit 1; else printf '%s\n' "$body"; fi
  if [[ "$st" -ge 400 ]]; then exit 1; fi
  exit 0
}
fail_mode() {
  case "${1:-}" in
    403) respond 403 - <<<'{"message":"Forbidden"}' ;;
    ratelimit) respond 403 - 'x-ratelimit-remaining: 0' <<<'{"message":"Forbidden"}' ;;
    ratelimit-body) respond 403 - <<<'{"message":"API rate limit exceeded for installation."}' ;;
    429) respond 429 - <<<'{"message":"Too Many Requests"}' ;;
    5xx) respond 502 - <<<'{"message":"Bad Gateway"}' ;;
    nonjson) respond 200 - <<<'<html>not json</html>' ;;
  esac
}
R=repos/fixture-owner/fixture-repo
if [[ "$method" == "POST" ]]; then
  mkdir -p "${DLR_GH_POSTS:-/nonexistent}" 2>/dev/null
  k=$(( $(find "${DLR_GH_POSTS:-/nonexistent}" -type f 2>/dev/null | wc -l) + 1 ))
  case "$path" in
    "$R"/issues/*/comments) kind=comment; printf 'gh POST comment %s\n' "${path#"$R"/issues/}" >> "$log" ;;
    "$R"/issues) kind=issue; printf 'gh POST issue title=%s\n' "$title" >> "$log" ;;
    "$R"/labels) printf 'gh POST label\n' >> "$log"; exit 0 ;;
    *) printf 'gh UNROUTED POST %s\n' "$path" >> "$log"; exit 99 ;;
  esac
  if [[ -n "$bodyf" && -f "$bodyf" ]]; then cp "$bodyf" "${DLR_GH_POSTS}/$k.$kind"; fi
  printf '{}\n'; exit 0
fi
case "$path" in
  "$R"/pulls)
    printf 'gh pulls?head=%s\n' "$head" >> "$log"
    if [[ "$method" != "GET" ]]; then printf 'gh POST-SHAPE pulls\n' >> "$log"; exit 98; fi
    if [[ -n "${DLR_GH_SLEEP:-}" ]]; then sleep "$DLR_GH_SLEEP"; fi
    fail_mode "${DLR_GH_HEAD_MODE:-${DLR_GH_MODE:-}}"
    b="${head#fixture-owner:}"
    f="$fix/head/${b//\//__}.json"
    if [[ -n "${DLR_GH_IGNORE_HEAD:-}" ]]; then f=$(find "$fix/head" -name '*.json' 2>/dev/null | LC_ALL=C sort | tail -n 1); fi
    [[ -n "$f" && -f "$f" ]] || f=/dev/null
    jq -cs --arg st "${state:-open}" --argjson pp "${per_page:-30}" \
      '(.[0] // []) | map(select($st == "all" or .state == $st)) | sort_by(-((.number | tonumber?) // 0)) | .[:$pp]' "$f" > "$fix/.pulls-answer" 2>/dev/null \
      || printf 'FAKE-GH-JQ-ERROR' > "$fix/.pulls-answer"
    respond 200 "$fix/.pulls-answer" ;;
  "$R"/pulls/*)
    n="${path##*/}"
    printf 'gh pulls/%s\n' "$n" >> "$log"
    fail_mode "${DLR_GH_MODE:-}"
    cf="$fix/pull/$n.count"
    k=$(( $(cat "$cf" 2>/dev/null || echo 0) + 1 ))
    printf '%s' "$k" > "$cf"
    f="$fix/pull/$n.$k.json"
    [[ -f "$f" ]] || f="$fix/pull/$n.json"
    if [[ -f "$f" ]]; then respond 200 "$f"; fi
    respond 404 - <<<'{"message":"Not Found"}' ;;
  "$R"/issues)
    printf 'gh issues?state=%s&labels=%s\n' "$state" "$labels" >> "$log"
    fail_mode "${DLR_GH_ISSUES_MODE:-${DLR_GH_MODE:-}}"
    if [[ -f "$fix/issues.json" ]]; then respond 200 "$fix/issues.json"; fi
    respond 200 - <<<'[]' ;;
  "$R"/git/blobs/*)
    id="${path##*/}"
    printf 'gh blobs/%s\n' "$id" >> "$log"
    [[ "$raw" == "1" ]] || { printf 'gh NOT-RAW blobs\n' >> "$log"; exit 98; }
    git -C "${DLR_GH_BLOB_REPO:?}" cat-file blob "$id" || exit 1
    if [[ "${DLR_GH_BLOB_CORRUPT:-}" == "1" ]]; then printf 'x'; fi
    exit 0 ;;
esac
printf 'gh UNROUTED %s\n' "$path" >> "$log"
exit 99
SH
chmod +x "$BIN/psql" "$BIN/doppler" "$BIN/curl" "$BIN/gh"
WANT_SQL="SELECT filename || '|' || COALESCE(content_sha, '') FROM public._schema_migrations ORDER BY filename"
export PATH="$BIN:$PATH"

# No case may reach a real gh or GitHub: an isolated config dir, a token that is not
# one, an unresolvable host, and the fixture repository name the fake gh routes on.
GHFIX="$tmp/ghfix"
CALLLOG="$tmp/calls.log"
mkdir -p "$tmp/gh-config" "$GHFIX/head" "$GHFIX/pull"
: > "$CALLLOG"
export GITHUB_REPOSITORY=fixture-owner/fixture-repo GH_CONFIG_DIR="$tmp/gh-config" GH_TOKEN=invalid GH_HOST=fixture.invalid
export DLR_GH_FIX="$GHFIX" DLR_CALL_LOG="$CALLLOG" DLR_GH_BLOB_REPO="$tmp/origin.git" DLP_GH_RETRY_S=0
unset GITHUB_TOKEN DLR_GH_MODE DLR_GH_ISSUES_MODE DLR_GH_HEAD_MODE DLR_GH_BLOB_CORRUPT DLR_GH_IGNORE_HEAD DLP_BUDGET_S
gh_reset() {
  rm -rf "$GHFIX"
  mkdir -p "$GHFIX/head" "$GHFIX/pull"
  : > "$CALLLOG"
  unset DLR_GH_MODE DLR_GH_ISSUES_MODE DLR_GH_HEAD_MODE DLR_GH_BLOB_CORRUPT DLR_GH_IGNORE_HEAD
}
# gh_head_json <branch> <json-array> — the listing for head=<owner>:<branch>. Entries
# without a head.ref get <branch> (GitHub fills it with the head branch).
gh_head_json() {
  jq -c --arg b "$1" 'map(.head.ref //= $b)' <<<"$2" > "$GHFIX/head/${1//\//__}.json"
}
gh_head_raw() { printf '%s' "$2" > "$GHFIX/head/${1//\//__}.json"; }   # verbatim (malformed-entry cases)
# pr_obj <number> <open|closed> <closed_at-epoch|""> <head-sha> [merged] — one pulls entry.
pr_obj() {
  jq -nc --argjson n "$1" --arg st "$2" --arg ca "$3" --arg sha "$4" --arg m "${5:-}" \
    '{number:$n, state:$st, closed_at:(if $ca == "" then null else ($ca | tonumber | todate) end),
      merged_at:(if $m == "" then null else ($ca | tonumber | todate) end),
      head:{sha:$sha, repo:{full_name:"fixture-owner/fixture-repo"}}, user:{login:"fixture-author"}}'
}
# issue_obj <number> <title> [pr] — one open issue; a third argument makes it a pull request.
issue_obj() { jq -nc --argjson n "$1" --arg t "$2" --arg pr "${3:-}" '{number:$n, title:$t} + (if $pr == "" then {} else {pull_request:{}} end)'; }
gh_issues_json() { printf '%s' "$1" > "$GHFIX/issues.json"; }
calls_of() { grep -cxF -- "$1" "$CALLLOG" || true; }   # exact-line count in the ordered call log

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
  git -C "$WORK" fetch -q --no-tags origin
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
git -C "$SEED" fetch -q --no-tags origin
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

# ----------------------------------------------------------------------
echo "G1-24: another branch holds G by exact name but at a DIFFERENT blob -> it does not excuse the PR"
CASES=$((CASES + 1))
branch other-diff main "" 144_slugme.sql="S-other"
feat_case 145_slugme.sql="S-v2"
ledger "144_slugme.sql|$(blob_of S-v1)"
run_check --head-branch feat
git -C "$SEED" push -q origin --delete other-diff
if [[ "$rc" == "1" ]] && has "by slug" && ! has "treated as that PR's in-flight row"; then
  pass "only a holder of the APPLIED body is another PR's in-flight row"
else
  fail "expected rc=1; got rc=$rc out=$out"
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
if [[ "$rc" == "0" && "$out" == "orphan${T}199_gone.sql" ]] && grep -qxF 'ledger-classify: in-flight=0 stale=0 merged=0 orphan=1 closed-grace=0 closed=0 closed-tracked=0' <<<"$err"; then
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

echo "== Guard 2b: closed-PR ownership (PR-state lookup, commit-bound, fail-closed) =="

tip_of() { git -C "$ORIGIN" rev-parse "refs/heads/$1"; }
hours_ago() { printf '%s' "$(( $(date +%s) - $1 * 3600 - 60 ))"; }
# field <n> — the n-th tab field of $out (1-based).
field() { cut -f "$1" <<<"$out"; }

# ----------------------------------------------------------------------
branch cl-tip main "" 210_cl.sql="CL"
gh_reset
gh_head_json cl-tip "[$(pr_obj 7001 closed "$(hours_ago 30)" "$(tip_of cl-tip)")]"
run_classify "210_cl.sql|$(blob_of CL)"$'\n'
cl_out=$out; cl_err=$err; cl_rc=$rc; cl_calls=$(calls_of "gh pulls?head=fixture-owner:cl-tip")

echo "G2-M1: every fresh holder's latest PR closed at the branch tip 30 h ago -> closed"
CASES=$((CASES + 1))
out=$cl_out
if [[ "$cl_rc" == "0" && "$(field 1)" == "closed" && "$(field 2)" == "210_cl.sql" && "$(field 3)" == "cl-tip" && "$(field 4)" == "7001" ]]; then
  pass "a closed-at-tip holder does not keep the row in-flight"
else
  fail "expected closed/210_cl.sql/cl-tip/7001; got rc=$cl_rc out=[$cl_out] err=[$cl_err]"
fi

echo "G2-M16: the hours field is measured from closed_at (30 h ago -> 29..31)"
CASES=$((CASES + 1))
h=$(field 5)
if [[ "$h" =~ ^[0-9]+$ ]] && (( h >= 29 && h <= 31 )); then
  pass "hours since close = $h"
else
  fail "expected hours 29..31; got [$h] out=[$cl_out]"
fi

echo "G2-M11: the summary line gains closed-grace/closed/closed-tracked at the END"
CASES=$((CASES + 1))
if grep -qxF 'ledger-classify: in-flight=0 stale=0 merged=0 orphan=0 closed-grace=0 closed=1 closed-tracked=0' <<<"$cl_err"; then
  pass "summary fields appended, existing fields unmoved"
else
  fail "expected the seven-field summary ending closed-grace=0 closed=1 closed-tracked=0; got err=[$cl_err]"
fi

echo "G2-M6: a fresh holder is looked up by branch (head=<owner>:<branch>), once"
CASES=$((CASES + 1))
if [[ "$cl_calls" == "1" ]]; then
  pass "the lookup ran for the fresh holder"
else
  fail "expected one 'gh pulls?head=fixture-owner:cl-tip' call; got $cl_calls; log=[$(cat "$CALLLOG")]"
fi

# ----------------------------------------------------------------------
echo "G2-M2: the PR-state lookup answers 5xx twice -> rc 2 after exactly two calls, no verdicts"
CASES=$((CASES + 1))
gh_reset
export DLR_GH_MODE=5xx
run_classify "210_cl.sql|$(blob_of CL)"$'\n'
n=$(calls_of "gh pulls?head=fixture-owner:cl-tip")
unset DLR_GH_MODE
if [[ "$rc" == "2" && -z "$out" && "$n" == "2" ]] && grep -qF 'cannot measure (transient)' <<<"$err"; then
  pass "one retry, then fail closed (UNCLASSIFIED in the probe)"
else
  fail "expected rc=2 after 2 calls; got rc=$rc calls=$n out=[$out] err=[$err]"
fi

echo "G2-M14: 403 -> rc 2 'cannot measure (config)' naming 403, exactly one call (no retry)"
CASES=$((CASES + 1))
gh_reset
export DLR_GH_MODE=403
run_classify "210_cl.sql|$(blob_of CL)"$'\n'
n=$(calls_of "gh pulls?head=fixture-owner:cl-tip")
unset DLR_GH_MODE
if [[ "$rc" == "2" && -z "$out" && "$n" == "1" ]] && grep -qF 'cannot measure (config)' <<<"$err" && grep -qF 'HTTP 403' <<<"$err"; then
  pass "a scope/permission refusal is config, and a re-run is not attempted"
else
  fail "expected rc=2 config 403 after 1 call; got rc=$rc calls=$n err=[$err]"
fi

echo "G2-nonjson: a 200 whose body is not JSON -> rc 2 transient, no verdicts"
CASES=$((CASES + 1))
gh_reset
export DLR_GH_MODE=nonjson
run_classify "210_cl.sql|$(blob_of CL)"$'\n'
unset DLR_GH_MODE
if [[ "$rc" == "2" && -z "$out" ]] && grep -qF 'cannot measure (transient)' <<<"$err" && ! grep -qF 'not json' <<<"$err"; then
  pass "an unparseable body fails closed and is never echoed"
else
  fail "expected rc=2 transient; got rc=$rc out=[$out] err=[$err]"
fi

echo "G2-repo: GITHUB_REPOSITORY unset while a fresh holder exists -> rc 2 config, zero gh calls"
CASES=$((CASES + 1))
gh_reset
unset GITHUB_REPOSITORY
run_classify "210_cl.sql|$(blob_of CL)"$'\n'
export GITHUB_REPOSITORY=fixture-owner/fixture-repo
if [[ "$rc" == "2" && -z "$out" && ! -s "$CALLLOG" ]] && grep -qF 'cannot measure (config)' <<<"$err"; then
  pass "no repository, no lookup, no verdict"
else
  fail "expected rc=2 config with no call; got rc=$rc out=[$out] err=[$err] log=[$(cat "$CALLLOG")]"
fi

# ----------------------------------------------------------------------
echo "G2-M4a: closed 23 h ago -> closed-grace (a warning)"
CASES=$((CASES + 1))
gh_reset
gh_head_json cl-tip "[$(pr_obj 7002 closed "$(hours_ago 23)" "$(tip_of cl-tip)")]"
run_classify "210_cl.sql|$(blob_of CL)"$'\n'
if [[ "$rc" == "0" && "$(field 1)" == "closed-grace" && "$(field 4)" == "7002" && "$(field 5)" == "23" ]] \
  && grep -qxF 'ledger-classify: in-flight=0 stale=0 merged=0 orphan=0 closed-grace=1 closed=0 closed-tracked=0' <<<"$err"; then
  pass "inside the 24 h grace the row is closed-grace"
else
  fail "expected closed-grace 7002 23; got rc=$rc out=[$out] err=[$err]"
fi

echo "G2-M4b: closed 24 h ago -> closed (blocking)"
CASES=$((CASES + 1))
gh_reset
gh_head_json cl-tip "[$(pr_obj 7003 closed "$(hours_ago 24)" "$(tip_of cl-tip)")]"
run_classify "210_cl.sql|$(blob_of CL)"$'\n'
if [[ "$rc" == "0" && "$(field 1)" == "closed" && "$(field 5)" == "24" ]]; then
  pass "the grace boundary is CLOSED_GRACE_H=24 whole hours"
else
  fail "expected closed at 24 h; got rc=$rc out=[$out]"
fi

echo "G2-merged: the only PR MERGED at the tip (squash) 30 h ago -> never closed; falls through to orphan"
CASES=$((CASES + 1))
gh_reset
gh_head_json cl-tip "[$(pr_obj 7004 closed "$(hours_ago 30)" "$(tip_of cl-tip)" merged)]"
run_classify "210_cl.sql|$(blob_of CL)"$'\n'
if [[ "$rc" == "0" && "$out" == "orphan${T}210_cl.sql" ]]; then
  pass "a merged-at-tip holder is neither live nor closed (CTO ruling 5)"
else
  fail "expected orphan; got rc=$rc out=[$out]"
fi

echo "G2-M9: the branch was pushed AFTER its PR closed (PR head != tip) -> in-flight"
CASES=$((CASES + 1))
git -C "$SEED" switch -q -C cl-push main
put "$SEED" 217_push.sql "PUSH-1"
git -C "$SEED" add -A && git -C "$SEED" commit -qm 'cl-push 1'
old_head=$(git -C "$SEED" rev-parse HEAD)
put "$SEED" 218_other.sql "PUSH-2"
git -C "$SEED" add -A && git -C "$SEED" commit -qm 'cl-push 2'
git -C "$SEED" push -q -f origin HEAD:refs/heads/cl-push
git -C "$SEED" switch -q main
gh_reset
gh_head_json cl-push "[$(pr_obj 7005 closed "$(hours_ago 30)" "$old_head")]"
run_classify "217_push.sql|$(blob_of PUSH-1)"$'\n'
git -C "$SEED" push -q origin --delete cl-push
if [[ "$rc" == "0" && "$out" == "in-flight${T}217_push.sql${T}cl-push${T}exact" ]]; then
  pass "PR-state evidence is bound to the commit, not the branch name"
else
  fail "expected in-flight via cl-push; got rc=$rc out=[$out] err=[$err]"
fi

echo "G2-M12: two closed PRs at the tip; the LOWER-numbered one closed later -> it is picked (the fake lists newest-first)"
CASES=$((CASES + 1))
gh_reset
gh_head_json cl-tip "[$(pr_obj 7006 closed "$(hours_ago 30)" "$(tip_of cl-tip)"),$(pr_obj 7007 closed "$(hours_ago 40)" "$(tip_of cl-tip)")]"
run_classify "210_cl.sql|$(blob_of CL)"$'\n'
if [[ "$rc" == "0" && "$(field 1)" == "closed" && "$(field 4)" == "7006" ]]; then
  pass "reduced by greatest closed_at, never array order"
else
  fail "expected #7006; got rc=$rc out=[$out]"
fi

echo "G2-M12b: the other order — the HIGHER-numbered one closed later -> it is picked"
CASES=$((CASES + 1))
gh_reset
gh_head_json cl-tip "[$(pr_obj 7006 closed "$(hours_ago 40)" "$(tip_of cl-tip)"),$(pr_obj 7007 closed "$(hours_ago 30)" "$(tip_of cl-tip)")]"
run_classify "210_cl.sql|$(blob_of CL)"$'\n'
if [[ "$rc" == "0" && "$(field 1)" == "closed" && "$(field 4)" == "7007" ]]; then
  pass "both orders pick the latest close"
else
  fail "expected #7007; got rc=$rc out=[$out]"
fi

echo "G2-M12c: the LATEST closed PR is not at the tip, an older one is -> in-flight (latest first, then the tip test)"
CASES=$((CASES + 1))
gh_reset
gh_head_json cl-tip "[$(pr_obj 7016 closed "$(hours_ago 40)" "$(tip_of cl-tip)"),$(pr_obj 7017 closed "$(hours_ago 30)" "$(tip_of main)")]"
run_classify "210_cl.sql|$(blob_of CL)"$'\n'
if [[ "$rc" == "0" && "$out" == "in-flight${T}210_cl.sql${T}cl-tip${T}exact" ]]; then
  pass "an older closed-at-tip PR does not outrank the latest one"
else
  fail "expected in-flight; got rc=$rc out=[$out]"
fi


echo "G2-M13: [closed-at-tip, open] -> in-flight (an open PR anywhere in the list wins)"
CASES=$((CASES + 1))
gh_reset
gh_head_json cl-tip "[$(pr_obj 7008 closed "$(hours_ago 30)" "$(tip_of cl-tip)"),$(pr_obj 7009 open "" "$(tip_of cl-tip)")]"
run_classify "210_cl.sql|$(blob_of CL)"$'\n'
if [[ "$rc" == "0" && "$out" == "in-flight${T}210_cl.sql${T}cl-tip${T}exact" ]]; then
  pass "an open PR keeps the row in-flight whatever its position"
else
  fail "expected in-flight; got rc=$rc out=[$out]"
fi

echo "G2-M10: two rows owned by one branch -> one lookup for that branch (memo survives the per-row subshell)"
CASES=$((CASES + 1))
branch cl-two main "" 215_r1.sql="R1" 216_r2.sql="R2"
gh_reset
run_classify "215_r1.sql|$(blob_of R1)"$'\n'"216_r2.sql|$(blob_of R2)"$'\n'
n=$(calls_of "gh pulls?head=fixture-owner:cl-two")
git -C "$SEED" push -q origin --delete cl-two
if [[ "$rc" == "0" && "$n" == "1" && "$out" == "in-flight${T}215_r1.sql${T}cl-two${T}exact"$'\n'"in-flight${T}216_r2.sql${T}cl-two${T}exact" ]]; then
  pass "memoised per branch and tip"
else
  fail "expected 1 call and two in-flight; got calls=$n rc=$rc out=[$out]"
fi

# ----------------------------------------------------------------------
echo "G2-M3a: holders a (closed at tip) + b (open) -> in-flight via b (second member checked)"
CASES=$((CASES + 1))
branch cla-a main "" 211_two.sql="TWO"
branch cla-b main "" 211_two.sql="TWO"
gh_reset
gh_head_json cla-a "[$(pr_obj 7010 closed "$(hours_ago 30)" "$(tip_of cla-a)")]"
gh_head_json cla-b "[$(pr_obj 7011 open "" "$(tip_of cla-b)")]"
run_classify "211_two.sql|$(blob_of TWO)"$'\n'
git -C "$SEED" push -q origin --delete cla-a cla-b
if [[ "$rc" == "0" && "$out" == "in-flight${T}211_two.sql${T}cla-b${T}exact" ]]; then
  pass "a live second holder keeps the row in-flight"
else
  fail "expected in-flight via cla-b; got rc=$rc out=[$out]"
fi

echo "G2-M3b: holders a (open) + b (closed at tip) -> in-flight via a"
CASES=$((CASES + 1))
branch clb-a main "" 212_two.sql="TWOB"
branch clb-b main "" 212_two.sql="TWOB"
gh_reset
gh_head_json clb-a "[$(pr_obj 7012 open "" "$(tip_of clb-a)")]"
gh_head_json clb-b "[$(pr_obj 7013 closed "$(hours_ago 30)" "$(tip_of clb-b)")]"
run_classify "212_two.sql|$(blob_of TWOB)"$'\n'
git -C "$SEED" push -q origin --delete clb-a clb-b
if [[ "$rc" == "0" && "$out" == "in-flight${T}212_two.sql${T}clb-a${T}exact" ]]; then
  pass "both orders"
else
  fail "expected in-flight via clb-a; got rc=$rc out=[$out]"
fi

echo "G2-M5: exact-name holder closed + slug holder open -> in-flight via the slug holder"
CASES=$((CASES + 1))
branch clx-exact main "" 213_ex.sql="EX-A"
branch clx-slug main "" 214_ex.sql="EX-B"
gh_reset
gh_head_json clx-exact "[$(pr_obj 7014 closed "$(hours_ago 30)" "$(tip_of clx-exact)")]"
run_classify "213_ex.sql|$(blob_of EX-A)"$'\n'
git -C "$SEED" push -q origin --delete clx-exact clx-slug
if [[ "$rc" == "0" && "$out" == "in-flight${T}213_ex.sql${T}clx-slug${T}slug" ]]; then
  pass "a closed exact holder does not end the walk; every fresh tier is tried"
else
  fail "expected in-flight via clx-slug slug; got rc=$rc out=[$out]"
fi

echo "G2-M15: a fresh closed-at-tip holder + a stale holder -> closed (decided before the stale tiers)"
CASES=$((CASES + 1))
branch clf main "" 160_old.sql="OLD"
gh_reset
gh_head_json clf "[$(pr_obj 7015 closed "$(hours_ago 30)" "$(tip_of clf)")]"
run_classify "160_old.sql|$(blob_of OLD)"$'\n'
git -C "$SEED" push -q origin --delete clf
if [[ "$rc" == "0" && "$(field 1)" == "closed" && "$(field 3)" == "clf" && "$(field 4)" == "7015" ]]; then
  pass "a remembered closed hit beats a stale holder"
else
  fail "expected closed via clf; got rc=$rc out=[$out]"
fi

# ----------------------------------------------------------------------
echo "G2-shape: listing entries without a state, with a non-hex head.sha, or with a string number -> rc 2 config each (never 'none')"
CASES=$((CASES + 1))
tipc=$(tip_of cl-tip)
gh_reset; gh_head_raw cl-tip "[{\"number\":7030,\"head\":{\"sha\":\"$tipc\",\"ref\":\"cl-tip\"}}]"
run_classify "210_cl.sql|$(blob_of CL)"$'\n'; r1=$rc; e1=$err
gh_reset; gh_head_raw cl-tip "[{\"number\":7031,\"state\":\"closed\",\"closed_at\":\"2026-09-01T00:00:00Z\",\"merged_at\":null,\"head\":{\"sha\":\"not-a-sha\",\"ref\":\"cl-tip\"}}]"
run_classify "210_cl.sql|$(blob_of CL)"$'\n'; r2=$rc; e2=$err
gh_reset; gh_head_raw cl-tip "[{\"number\":\"7032\",\"state\":\"open\",\"merged_at\":null,\"head\":{\"sha\":\"$tipc\",\"ref\":\"cl-tip\"}}]"
run_classify "210_cl.sql|$(blob_of CL)"$'\n'; r3=$rc; e3=$err
if [[ "$r1$r2$r3" == "222" ]] && grep -qF 'cannot measure (config)' <<<"$e1" && grep -qF 'cannot measure (config)' <<<"$e2" \
  && grep -qF 'cannot measure (config)' <<<"$e3" && grep -qF 'lacks a state' <<<"$e1$e2$e3"; then
  pass "a 200 with malformed entries fails closed as config"
else
  fail "expected rc=2 config x3; got $r1/$r2/$r3 [$e1] [$e2] [$e3]"
fi

echo "G2-headref: a listing that names another branch (head= not honoured) -> rc 2 config"
CASES=$((CASES + 1))
gh_reset
gh_head_json zz-other "[$(pr_obj 7033 open "" "$tipc")]"
export DLR_GH_IGNORE_HEAD=1
run_classify "210_cl.sql|$(blob_of CL)"$'\n'
unset DLR_GH_IGNORE_HEAD
if [[ "$rc" == "2" && -z "$out" ]] && grep -qF 'names another branch' <<<"$err"; then
  pass "an unfiltered listing is never read as this branch's PRs"
else
  fail "expected rc=2 naming another branch; got rc=$rc out=[$out] err=[$err]"
fi

echo "G2-cap: a listing that fills the 100-entry page -> rc 2 config (no pagination, so never 'none')"
CASES=$((CASES + 1))
gh_reset
big=$(for i in $(seq 1 100); do pr_obj $((8000 + i)) closed "$(hours_ago 50)" "$(tip_of main)"; done | jq -sc .)
gh_head_json cl-tip "$big"
run_classify "210_cl.sql|$(blob_of CL)"$'\n'
if [[ "$rc" == "2" && -z "$out" ]] && grep -qF '100-entry page' <<<"$err" && grep -qF 'cannot measure (config)' <<<"$err"; then
  pass "a full page is cannot-measure"
else
  fail "expected rc=2 config on a full page; got rc=$rc out=[$out] err=[$err]"
fi

echo "G2-ratelimit: a 403 with x-ratelimit-remaining: 0, a 403 'rate limit' body, and a 429 -> transient after two calls each"
CASES=$((CASES + 1))
rl=""
for m in ratelimit ratelimit-body 429; do
  gh_reset; export DLR_GH_MODE="$m"
  run_classify "210_cl.sql|$(blob_of CL)"$'\n'
  rl+="$m:$rc:$(calls_of "gh pulls?head=fixture-owner:cl-tip"):$(grep -c 'cannot measure (transient)' <<<"$err" || true) "
done
unset DLR_GH_MODE
if [[ "$rl" == "ratelimit:2:2:1 ratelimit-body:2:2:1 429:2:2:1 " ]]; then
  pass "an exhausted rate limit is transient (retried once), never config"
else
  fail "rate-limit classes wrong: [$rl]"
fi

echo "G2-budget: DLP_BUDGET_S=0 -> rc 2 transient naming the budget, zero lookups"
CASES=$((CASES + 1))
gh_reset
export DLP_BUDGET_S=0
run_classify "210_cl.sql|$(blob_of CL)"$'\n'
unset DLP_BUDGET_S
if [[ "$rc" == "2" && -z "$out" ]] && grep -qF 'time budget (DLP_BUDGET_S) ran out' <<<"$err" && ! grep -q '^gh pulls' "$CALLLOG"; then
  pass "an exhausted budget is transient, not a kill"
else
  fail "expected rc=2 budget; got rc=$rc err=[$err] log=[$(cat "$CALLLOG")]"
fi

echo "G2-budget-retry: a 5xx with too little budget left for the retry -> ONE call, transient 'no room for a retry'"
CASES=$((CASES + 1))
gh_reset
export DLP_BUDGET_S=8 DLP_GH_RETRY_S=5 DLR_GH_MODE=5xx
run_classify "210_cl.sql|$(blob_of CL)"$'\n'
export DLP_GH_RETRY_S=0; unset DLP_BUDGET_S DLR_GH_MODE
if [[ "$rc" == "2" && "$(calls_of "gh pulls?head=fixture-owner:cl-tip")" == "1" ]] && grep -qF 'leaves no room for a retry' <<<"$err"; then
  pass "the retry is skipped instead of overrunning the probe's bound"
else
  fail "expected one call and the no-room message; got rc=$rc calls=$(calls_of "gh pulls?head=fixture-owner:cl-tip") err=[$err]"
fi

echo "G2-budget-cut: a stalled lookup is cut to the budget left, not GH_TIMEOUT_S (budget 6 s, gh stalls 30 s)"
CASES=$((CASES + 1))
gh_reset
export DLP_BUDGET_S=6 DLR_GH_SLEEP=30
t0=$(date +%s)
run_classify "210_cl.sql|$(blob_of CL)"$'\n'
el=$(( $(date +%s) - t0 ))
unset DLP_BUDGET_S DLR_GH_SLEEP
if [[ "$rc" == "2" && "$el" -lt 9 ]] && grep -qF 'cannot measure (transient)' <<<"$err"; then
  pass "the attempt was cut at the deadline (${el}s)"
else
  fail "expected rc=2 within 9 s; got rc=$rc after ${el}s err=[$err]"
fi

# ----------------------------------------------------------------------
echo "G2-tracked: closed 30 h ago + an OPEN [ci/dev-ledger-reconcile] issue for that PR -> closed-tracked with the issue number"
CASES=$((CASES + 1))
gh_reset
gh_head_json cl-tip "[$(pr_obj 7020 closed "$(hours_ago 30)" "$tipc")]"
gh_issues_json "[$(issue_obj 9001 "[ci/dev-ledger-reconcile] PR #7020 dev ledger rows need attention")]"
run_classify "210_cl.sql|$(blob_of CL)"$'\n'
if [[ "$rc" == "0" && "$(field 1)" == "closed-tracked" && "$(field 4)" == "7020" && "$(field 6)" == "9001" ]] \
  && grep -qxF 'ledger-classify: in-flight=0 stale=0 merged=0 orphan=0 closed-grace=0 closed=0 closed-tracked=1' <<<"$err" \
  && [[ "$(calls_of 'gh issues?state=open&labels=ci/dev-ledger-reconcile,action-required')" == "1" ]]; then
  pass "a tracked closed row warns instead of blocking"
else
  fail "expected closed-tracked 7020 9001; got rc=$rc out=[$out] err=[$err] log=[$(cat "$CALLLOG")]"
fi

echo "G2-tracked-prefix: an issue for PR #70201, and a PULL REQUEST titled for #7020 -> still closed (exact number, issues only)"
CASES=$((CASES + 1))
gh_reset
gh_head_json cl-tip "[$(pr_obj 7020 closed "$(hours_ago 30)" "$tipc")]"
gh_issues_json "[$(issue_obj 9002 "[ci/dev-ledger-reconcile] PR #70201 dev ledger rows need attention"),$(issue_obj 9003 "[ci/dev-ledger-reconcile] PR #7020 dev ledger rows need attention" pr)]"
run_classify "210_cl.sql|$(blob_of CL)"$'\n'
if [[ "$rc" == "0" && "$(field 1)" == "closed" && "$(field 4)" == "7020" ]] && [[ "$(awk -F'\t' '{print NF}' <<<"$out")" == "5" ]]; then
  pass "only an issue naming exactly this PR downgrades the row"
else
  fail "expected closed 7020; got rc=$rc out=[$out]"
fi

echo "G2-tracked-fail: the issue lookup fails (5xx twice) -> rc 2, no verdicts (UNCLASSIFIED, never a warning)"
CASES=$((CASES + 1))
gh_reset
gh_head_json cl-tip "[$(pr_obj 7020 closed "$(hours_ago 30)" "$tipc")]"
export DLR_GH_ISSUES_MODE=5xx
run_classify "210_cl.sql|$(blob_of CL)"$'\n'
unset DLR_GH_ISSUES_MODE
if [[ "$rc" == "2" && -z "$out" ]] && grep -qF 'cannot measure (transient)' <<<"$err"; then
  pass "a failed issue lookup fails closed"
else
  fail "expected rc=2; got rc=$rc out=[$out] err=[$err]"
fi

echo "G2-tracked-memo: two closed rows -> ONE issue listing; a closed-grace row alone -> none"
CASES=$((CASES + 1))
branch cl-pair main "" 219_p1.sql="P1" 220_p2.sql="P2"
gh_reset
gh_head_json cl-pair "[$(pr_obj 7023 closed "$(hours_ago 30)" "$(tip_of cl-pair)")]"
run_classify "219_p1.sql|$(blob_of P1)"$'\n'"220_p2.sql|$(blob_of P2)"$'\n'
n_two=$(calls_of 'gh issues?state=open&labels=ci/dev-ledger-reconcile,action-required'); o_two=$out
gh_reset
gh_head_json cl-pair "[$(pr_obj 7023 closed "$(hours_ago 5)" "$(tip_of cl-pair)")]"
run_classify "219_p1.sql|$(blob_of P1)"$'\n'
n_grace=$(grep -c '^gh issues' "$CALLLOG" || true)
git -C "$SEED" push -q origin --delete cl-pair
if [[ "$n_two" == "1" && "$n_grace" == "0" && "$(cut -f1 <<<"$o_two" | sort -u)" == "closed" && "$(field 1)" == "closed-grace" ]]; then
  pass "one memoised listing per run, and only when a row reads closed"
else
  fail "issue listings: two-closed=$n_two grace=$n_grace out=[$o_two] / [$out]"
fi

echo "G2-merged-other: a holder MERGED at its tip + another holder closed unmerged -> closed via the unmerged one"
CASES=$((CASES + 1))
branch clm-a main "" 221_m.sql="MM"
branch clm-b main "" 221_m.sql="MM"
gh_reset
gh_head_json clm-a "[$(pr_obj 7021 closed "$(hours_ago 30)" "$(tip_of clm-a)" merged)]"
gh_head_json clm-b "[$(pr_obj 7022 closed "$(hours_ago 30)" "$(tip_of clm-b)")]"
run_classify "221_m.sql|$(blob_of MM)"$'\n'
git -C "$SEED" push -q origin --delete clm-a clm-b
if [[ "$rc" == "0" && "$(field 1)" == "closed" && "$(field 3)" == "clm-b" && "$(field 4)" == "7022" ]]; then
  pass "a merged holder is skipped, not remembered as the closed hit"
else
  fail "expected closed via clm-b #7022; got rc=$rc out=[$out]"
fi

echo "G2-xtrace: the guard under bash -x refuses (78) when a DB URL or Doppler token is set, and runs when none is"
CASES=$((CASES + 1))
set +e
env -u GH_TOKEN -u GITHUB_TOKEN DATABASE_URL=postgres://fixture.invalid/db bash -x "$GUARD" --help >/dev/null 2>&1; x1=$?
env -u GH_TOKEN -u GITHUB_TOKEN DOPPLER_TOKEN=fixture-not-a-token bash -x "$GUARD" --help >/dev/null 2>&1; x2=$?
env -u GH_TOKEN -u GITHUB_TOKEN -u DATABASE_URL -u DATABASE_URL_POOLER -u DOPPLER_TOKEN bash -x "$GUARD" --help >/dev/null 2>&1; x3=$?
set -e
if [[ "$x1$x2$x3" == "78780" ]]; then
  pass "no trace with a database credential in reach"
else
  fail "xtrace refusal: db=$x1 doppler=$x2 none=$x3"
fi

echo "G2-lazy: no fresh holder (orphan + stale-only rows) -> the fake gh's call log stays empty"
CASES=$((CASES + 1))
gh_reset
run_classify "199_gone.sql|$(blob_of GONE)"$'\n'"160_old.sql|$(blob_of OLD)"$'\n'
if [[ "$rc" == "0" && ! -s "$CALLLOG" && "$out" == "orphan${T}199_gone.sql"$'\n'"stale${T}160_old.sql${T}old-branch${T}31" ]]; then
  pass "zero API calls when nothing could be in-flight"
else
  fail "expected no gh call; got rc=$rc out=[$out] log=[$(cat "$CALLLOG")]"
fi

echo "G2-nopsql: classify-missing makes zero psql calls (runtime)"
CASES=$((CASES + 1))
gh_reset
PL="$tmp/classify-psql.log"
: > "$PL"
set +e
printf '%s\n' "210_cl.sql|$(blob_of CL)" | DLP_PSQL_LOG="$PL" bash "$GUARD" classify-missing --base-branch main --repo "$WORK" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" == "0" && ! -s "$PL" ]] && ! grep -q '^psql' "$CALLLOG"; then
  pass "the classifier never touches the database"
else
  fail "expected zero psql calls; rc=$rc log=[$(tr '\0' ' ' < "$PL")]"
fi
git -C "$SEED" push -q origin --delete cl-tip
gh_reset

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
    CLASSIFIER_GH_TOKEN="${PROBE_GH_TOKEN:-fixture-probe-token}" \
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
  && grep -qxF "ledger-classify: in-flight=1 stale=0 merged=0 orphan=0 closed-grace=0 closed=0 closed-tracked=0" <<<"$out" && ! has "Missing-on-main:" \
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
u=$(line_no "ledger-classify: UNCLASSIFIED (rows=2 rc=2 class=unknown)")
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
if [[ "$r1$r2$r3" == "111" ]] && grep -qF "UNCLASSIFIED (rows=1 line=1 malformed class=malformed-output)" <<<"$o1" \
  && grep -qF "UNCLASSIFIED (rows=1 line=1 unknown verdict class=malformed-output)" <<<"$o2" && grep -qF "UNCLASSIFIED (rows=1 rc=2 class=unknown)" <<<"$o3"; then
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
g_grace=$(sed -n 's/^readonly CLOSED_GRACE_H=\([0-9][0-9]*\)$/\1/p' "$GUARD")
a_grace=$(sed -n 's/^[[:space:]]*CLOSED_GRACE_H_LABEL=\([0-9][0-9]*\)$/\1/p' "$PROBE")
if grep -qF 'cls_out=$(GH_TOKEN="$CLASSIFIER_GH_TOKEN" timeout -k 5 240 bash apps/web-platform/scripts/dev-ledger-parity.sh classify-missing' "$PROBE" \
  && [[ -n "$g_days" && "$g_days" == "$a_days" && -n "$g_grace" && "$g_grace" == "$a_grace" ]]; then
  pass "timeout wrapper present; STALE_DAYS=$g_days and CLOSED_GRACE_H=$g_grace in both"
else
  fail "unbounded classifier call or threshold drift: guard=$g_days/$g_grace action=$a_days/$a_grace"
fi

# ----------------------------------------------------------------------
echo "G2-P-grace: a closed-grace verdict under fail-on -> ::warning:: naming the PR, exit 0"
CASES=$((CASES + 1))
with_stub_classifier 'mapfile -t l; printf "closed-grace\t%s\tcl-branch\t7001\t5\n" "${l[0]%%|*}"'
ledger "199_gone.sql|$(blob_of GONE)"
run_probe true
restore_classifier
if [[ "$rc" == "0" ]] && grep -qE '^::warning::  - 199_gone\.sql \(owner branch cl-branch has no open pull request; #7001 closed 5 h ago' <<<"$out" \
  && ! grep -q '^::error::' <<<"$out" && ! has "Missing-on-main:"; then
  pass "inside the grace a closed PR's row warns, never reds main"
else
  fail "expected rc=0 closed-grace warning; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G2-M7: a closed verdict under fail-on -> ::error:: block with the dry-run command, exit 1, Sentry class 'closed'"
CASES=$((CASES + 1))
CURLLOG="$tmp/curl.log"
: > "$CURLLOG"
with_stub_classifier 'mapfile -t l; printf "closed\t%s\tcl-branch\t7001\t30\n" "${l[0]%%|*}"'
ledger "199_gone.sql|$(blob_of GONE)"
export DLP_CURL_LOG="$CURLLOG" SENTRY_DSN="https://pubkey@sentry.fixture.invalid/12345"
run_probe true
unset DLP_CURL_LOG SENTRY_DSN
restore_classifier
n_closed=$(grep -c '"ledger_class":"closed"' "$CURLLOG" || true)
if [[ "$rc" == "1" && "$n_closed" == "1" ]] \
  && grep -qxF '::error::  - 199_gone.sql (owner branch cl-branch has no open pull request; #7001 closed 30 h ago — check its action-required issue, or preview the discard: gh workflow run dev-ledger-reconcile.yml --ref main -f pr=7001; if the dry run lists rows, re-run with -f execute=true)' <<<"$out" \
  && ! has "Missing-on-main:"; then
  pass "a closed-owner row blocks after the grace, with the safe command first"
else
  fail "expected rc=1 closed block + one Sentry 'closed' event; got rc=$rc sentry=$n_closed out=$out"
fi

# ----------------------------------------------------------------------
echo "G2-P-closed-bad: a closed line with a non-numeric PR or hours -> UNCLASSIFIED (each)"
CASES=$((CASES + 1))
ledger "199_gone.sql|$(blob_of GONE)"
with_stub_classifier 'mapfile -t l; printf "closed\t%s\tcl-branch\t70x1\t30\n" "${l[0]%%|*}"'
run_probe true; o1=$out; r1=$rc
with_stub_classifier 'mapfile -t l; printf "closed-grace\t%s\tcl-branch\t7001\tsoon\n" "${l[0]%%|*}"'
run_probe true; o2=$out; r2=$rc
with_stub_classifier 'mapfile -t l; printf "closed\t%s\tbad;branch\t7001\t30\n" "${l[0]%%|*}"'
run_probe true; o3=$out; r3=$rc
restore_classifier
if [[ "$r1$r2$r3" == "111" ]] && grep -qF "UNCLASSIFIED (rows=1 line=1 malformed class=malformed-output)" <<<"$o1" \
  && grep -qF "UNCLASSIFIED (rows=1 line=1 malformed class=malformed-output)" <<<"$o2" && grep -qF "UNCLASSIFIED (rows=1 line=1 malformed class=malformed-output)" <<<"$o3"; then
  pass "every closed field is validated before it reaches an annotation"
else
  fail "expected three malformed UNCLASSIFIED; got [$r1] $o1 || [$r2] $o2 || [$r3] $o3"
fi

# ----------------------------------------------------------------------
echo "G2-P-hints: the orphan block carries the git-based deleted-branch lookup; the stale line names the reconcile workflow"
CASES=$((CASES + 1))
ledger "199_gone.sql|$(blob_of GONE)"
run_probe true; o1=$out
ledger "160_old.sql|$(blob_of OLD)"
run_probe true; o2=$out
if grep -qF "git fetch origin '+refs/pull/*/head:refs/remotes/origin/pr/*' && git log --all --diff-filter=A --format='%h %D' -- apps/web-platform/supabase/migrations/<file>, then preview the discard: gh workflow run dev-ledger-reconcile.yml --ref main -f pr=<N>" <<<"$o1" \
  && grep -qF 'gh workflow run dev-ledger-reconcile.yml --ref main -f pr=<its PR>' <<<"$o2" && ! grep -qF '#8605' <<<"$o1$o2"; then
  pass "each blocking class names its repair command"
else
  fail "hints missing: orphan=[$o1] stale=[$o2]"
fi

# ----------------------------------------------------------------------
echo "G2-P-token: the github-token input reaches the classifier as GH_TOKEN"
CASES=$((CASES + 1))
TOKF="$tmp/probe-token.txt"
: > "$TOKF"
with_stub_classifier "cat >/dev/null; printf '%s' \"\${GH_TOKEN-unset}\" > '$TOKF'; exit 2"
ledger "199_gone.sql|$(blob_of GONE)"
PROBE_GH_TOKEN="tok-for-classifier" run_probe true
restore_classifier
if [[ "$(cat "$TOKF")" == "tok-for-classifier" ]]; then
  pass "token passed on the classifier call"
else
  fail "classifier saw GH_TOKEN=[$(cat "$TOKF")]"
fi

# ----------------------------------------------------------------------
echo "G2-P-class: UNCLASSIFIED names the classifier's own cannot-measure class"
CASES=$((CASES + 1))
with_stub_classifier 'cat >/dev/null; echo "::error::dev-ledger-parity classify-missing: cannot measure (transient): x" >&2; exit 2'
ledger "199_gone.sql|$(blob_of GONE)"
run_probe true; o1=$out
with_stub_classifier 'cat >/dev/null; echo "::error::dev-ledger-parity classify-missing: cannot measure (config): x" >&2; exit 2'
run_probe true; o2=$out
restore_classifier
if grep -qF "UNCLASSIFIED (rows=1 rc=2 class=transient)" <<<"$o1" && grep -qF "UNCLASSIFIED (rows=1 rc=2 class=config)" <<<"$o2"; then
  pass "the annotation says whether a re-run can help"
else
  fail "class token missing: [$o1] [$o2]"
fi

echo "G2-P-tracked: a closed-tracked verdict -> ::warning:: naming PR and issue, exit 0, one warning-level Sentry event fingerprinted by class"
CASES=$((CASES + 1))
CURLLOG="$tmp/curl.log"; : > "$CURLLOG"
with_stub_classifier 'mapfile -t l; printf "closed-tracked\t%s\tcl-branch\t7001\t30\t9001\n" "${l[0]%%|*}"'
ledger "199_gone.sql|$(blob_of GONE)"
export DLP_CURL_LOG="$CURLLOG" SENTRY_DSN="https://pubkey@sentry.fixture.invalid/12345"
run_probe true
unset DLP_CURL_LOG SENTRY_DSN
restore_classifier
if [[ "$rc" == "0" ]] && grep -qE '^::warning::  - 199_gone\.sql \(owner branch cl-branch has no open pull request; #7001 closed 30 h ago — tracked by open issue #9001' <<<"$out" \
  && ! grep -q '^::error::' <<<"$out" && [[ "$(grep -c '"ledger_class":"closed-tracked"' "$CURLLOG" || true)" == "1" ]] \
  && grep -qF '"level":"warning"' "$CURLLOG" && grep -qF '"fingerprint":["dev-ledger-drift","closed-tracked"]' "$CURLLOG"; then
  pass "a tracked row is visible every run without redding main"
else
  fail "expected rc=0 tracked warning + one warning event; got rc=$rc sentry=[$(cat "$CURLLOG")] out=$out"
fi

echo "G2-P-tracked-bad: closed-tracked without an issue number, or closed WITH a sixth field -> UNCLASSIFIED"
CASES=$((CASES + 1))
with_stub_classifier 'mapfile -t l; printf "closed-tracked\t%s\tcl-branch\t7001\t30\n" "${l[0]%%|*}"'
run_probe true; o1=$out; r1=$rc
with_stub_classifier 'mapfile -t l; printf "closed\t%s\tcl-branch\t7001\t30\t9001\n" "${l[0]%%|*}"'
run_probe true; o2=$out; r2=$rc
restore_classifier
if [[ "$r1$r2" == "11" ]] && grep -qF "UNCLASSIFIED (rows=1 line=1 malformed class=malformed-output)" <<<"$o1" \
  && grep -qF "UNCLASSIFIED (rows=1 line=1 malformed class=malformed-output)" <<<"$o2"; then
  pass "the issue field is required exactly where it belongs"
else
  fail "expected two malformed UNCLASSIFIED; got [$r1] $o1 || [$r2] $o2"
fi

echo "G2-P-fingerprint: every blocking Sentry event carries fingerprint [dev-ledger-drift, <class>] at level error"
CASES=$((CASES + 1))
CURLLOG="$tmp/curl.log"; : > "$CURLLOG"
ledger "199_gone.sql|$(blob_of GONE)"
export DLP_CURL_LOG="$CURLLOG" SENTRY_DSN="https://pubkey@sentry.fixture.invalid/12345"
run_probe true
unset DLP_CURL_LOG SENTRY_DSN
if grep -qF '"fingerprint":["dev-ledger-drift","orphan"]' "$CURLLOG" && grep -qF '"level":"error"' "$CURLLOG"; then
  pass "one Sentry issue per class, not one per message"
else
  fail "fingerprint missing: [$(cat "$CURLLOG")]"
fi

echo "G2-P-token-scope: the doppler/psql child never sees CLASSIFIER_GH_TOKEN"
CASES=$((CASES + 1))
DOPLOG="$tmp/doppler-tok.log"; : > "$DOPLOG"
ledger
export DLP_DOPPLER_LOG="$DOPLOG"
run_probe true
unset DLP_DOPPLER_LOG
if grep -qE '^run .* classifier_token=$' "$DOPLOG" && ! grep -qE '^run .*classifier_token=set$' "$DOPLOG"; then
  pass "the GitHub token stays out of the database child's environment"
else
  fail "doppler child saw the token: [$(cat "$DOPLOG")]"
fi

echo "G2-P-lstree: the probe's per-row ls-tree is anchored :(top,literal) (cwd-independent, #8606 class)"
CASES=$((CASES + 1))
if grep -qF 'ls_out=$(git ls-tree origin/main -- ":(top,literal)$path" 2>/dev/null || true)' "$PROBE" \
  && ! grep -qE 'git ls-tree origin/main -- "\$path"' "$PROBE"; then
  pass "anchored"
else
  fail "the probe's ls-tree pathspec is cwd-relative"
fi

echo "G2-P-wiring: the probe step carries CLASSIFIER_GH_TOKEN from inputs.github-token, and only the classifier call exports it as GH_TOKEN"
CASES=$((CASES + 1))
pw_env=$(python3 - "$ACTION" <<'PY2'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
st = [s for s in doc["runs"]["steps"] if s.get("id") == "probe"][0]
env = st.get("env") or {}
bad = []
if env.get("CLASSIFIER_GH_TOKEN") != "${{ inputs.github-token }}": bad.append(f"CLASSIFIER_GH_TOKEN={env.get('CLASSIFIER_GH_TOKEN')!r}")
if "GH_TOKEN" in env or "GITHUB_TOKEN" in env: bad.append("a GitHub token is in the whole step env under its own name")
run = st["run"]
if run.count('GH_TOKEN="$CLASSIFIER_GH_TOKEN"') != 1: bad.append("GH_TOKEN is not exported on exactly one call")
if "secrets." in str(env): bad.append("a secret is wired into the probe env")
print("\n".join(bad))
PY2
)
if [[ -z "$pw_env" ]]; then pass "token wiring pinned"; else fail "probe token wiring: $pw_env"; fi

echo "W-timeout: every job hosting a probe call has timeout-minutes*60 above one probe's worst case (fetch 60 + ledger 120 + classifier bound + 60)"
CASES=$((CASES + 1))
cls_bound=$(sed -n 's/.*cls_out=$(GH_TOKEN="$CLASSIFIER_GH_TOKEN" timeout -k \([0-9]*\) \([0-9]*\) bash.*/\1 \2/p' "$PROBE")
tm_out=$(python3 - "$WF" "$SCHED" "$cls_bound" <<'PY2'
import sys, yaml
k, t = (int(x) for x in sys.argv[3].split())
need = 60 + 120 + k + t + 60
bad, sites = [], 0
for path in sys.argv[1:3]:
    doc = yaml.safe_load(open(path))
    for jn, job in (doc.get("jobs") or {}).items():
        if any(s.get("uses") == "./.github/actions/dev-migration-drift-probe" for s in job.get("steps") or []):
            sites += 1
            tm = job.get("timeout-minutes")
            if not isinstance(tm, int) or tm * 60 <= need:
                bad.append(f"{path.rsplit('/', 1)[-1]}:{jn} timeout-minutes={tm} (needs > {need} s)")
if sites != 2: bad.append(f"expected 2 jobs hosting the probe, found {sites}")
print("\n".join(bad))
PY2
)
if [[ -n "$cls_bound" && -z "$tm_out" ]]; then pass "the classifier's transient exit lands before any job kill ($cls_bound)"; else fail "headroom: bound=[$cls_bound] $tm_out"; fi

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

# probe_wiring <tenant-integration.yml> <scheduled-dev-migration-drift.yml> — one line per
# probe call site that does not hand the classifier its PR-state token, or whose job cannot
# read pull requests (G2-M8). Read from the parsed YAML, never from comment text.
probe_wiring() {
  python3 - "$1" "$2" <<'PY'
import sys, yaml
bad, sites = [], 0
for path in sys.argv[1:3]:
    doc = yaml.safe_load(open(path))
    top = doc.get("permissions") or {}
    for jname, job in (doc.get("jobs") or {}).items():
        perms = job.get("permissions", top) or {}
        for st in job.get("steps") or []:
            if st.get("uses") != "./.github/actions/dev-migration-drift-probe":
                continue
            sites += 1
            where = f"{path.rsplit('/', 1)[-1]}:{jname}:{st.get('name')}"
            if (st.get("with") or {}).get("github-token") != "${{ github.token }}":
                bad.append(f"{where} does not pass the github-token input")
            if not isinstance(perms, dict) or perms.get("pull-requests") not in ("read", "write"):
                bad.append(f"{where} runs in a job without pull-requests: read")
if sites != 3:
    bad.append(f"expected 3 probe call sites, parsed {sites}")
print("\n".join(bad))
PY
}
file_mutant() {  # $1 = source file, $2 = out file, $3 = python snippet transforming `s`
  python3 - "$1" "$2" "$3" <<'PY'
import sys
s = open(sys.argv[1]).read()
exec(sys.argv[3])
open(sys.argv[2], "w").write(s)
PY
  if cmp -s "$1" "$2"; then printf 'FATAL: mutation of %s did not land\n' "$1" >&2; exit 1; fi
}

# ----------------------------------------------------------------------
echo "W-T0: all three probe call sites pass github-token and run with pull-requests: read (G2-M8)"
CASES=$((CASES + 1))
pw_out=$(probe_wiring "$WF" "$SCHED")
if [[ -z "$pw_out" ]]; then pass "token and scope wired at every call site"; else fail "probe wiring broken: $pw_out"; fi

# ----------------------------------------------------------------------
echo "W-T1: the post-section re-probe stops passing github-token -> RED"
CASES=$((CASES + 1))
file_mutant "$WF" "$tmp/wf-tok.yml" '
t = "          github-token: ${{ github.token }}\n"
assert s.count(t) == 2
i = s.rindex(t)
s = s[:i] + s[i + len(t):]
'
if [[ -n "$(probe_wiring "$tmp/wf-tok.yml" "$SCHED")" ]]; then pass "a dropped token is seen"; else fail "a probe call without the token went unseen"; fi

# ----------------------------------------------------------------------
echo "W-T2: the heavy job drops pull-requests: read -> RED"
CASES=$((CASES + 1))
file_mutant "$WF" "$tmp/wf-perm.yml" '
t = "      pull-requests: read\n"
assert s.count(t) == 1
s = s.replace(t, "", 1)
'
if [[ -n "$(probe_wiring "$tmp/wf-perm.yml" "$SCHED")" ]]; then pass "a dropped scope is seen"; else fail "a job without pull-requests: read went unseen"; fi

# ----------------------------------------------------------------------
echo "W-T3: the scheduled probe loses its token, or its pull-requests: read -> RED (each)"
CASES=$((CASES + 1))
file_mutant "$SCHED" "$tmp/sched-tok.yml" '
t = "          github-token: ${{ github.token }}\n"
assert s.count(t) == 1
s = s.replace(t, "", 1)
'
r1=$(probe_wiring "$WF" "$tmp/sched-tok.yml")
file_mutant "$SCHED" "$tmp/sched-perm.yml" '
t = "  pull-requests: read\n"
assert s.count(t) == 1
s = s.replace(t, "", 1)
'
r2=$(probe_wiring "$WF" "$tmp/sched-perm.yml")
if [[ -n "$r1" && -n "$r2" ]]; then pass "the cron's wiring is pinned too"; else fail "scheduled mutants went unseen: [$r1] [$r2]"; fi

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
if [[ -f "$W2/.git/shallow" ]]; then git -C "$W2" fetch -q --no-tags --unshallow origin; fi
git -C "$W2" fetch -q --no-tags origin
run_state_step pull_request main; s_base=$state; r1=$rc            # a (RED) guard sits on the base tip
set_base_guard none
git -C "$W2" fetch -q --no-tags origin
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

echo "== Guard 3: dev-ledger-reconcile.sh (the one writer) =="

# The writer runs as a COPY beside a guard copy (it sources the guard from its own
# directory, or $DLR_GUARD), against a SEPARATE writer clone of the fixture origin —
# never $WORK, whose feat_case runs `git add -A`. DLP_OWNERS_CACHE is unset for every
# run, so each invocation builds and removes its own owner repo.
WBIN="$tmp/wbin"
WREPO="$tmp/writer-repo"
WRT="$tmp/writer-rt"
WLEDGER="$tmp/writer-ledger.txt"
PAYLOAD="$tmp/writer-payload.log"
BREACH="$tmp/writer-breach.log"
mkdir -p "$WBIN" "$WRT"
assert_fixture_dir "$WBIN"
cp "$WRITER_SRC" "$WBIN/dev-ledger-reconcile.sh"
cp "$GUARD" "$WBIN/dev-ledger-parity.sh"
git clone -q --no-tags "$ORIGIN_URL" "$WREPO" 2>/dev/null
assert_fixture_dir "$WREPO"
# Fake dev-suite mutex, OUTSIDE the writer clone (the writer resolves the mutex from
# its own tree, never from --repo; the suite injects this one through DLR_MUTEX).
# It prints the real script's banner shapes: WAITING before ACQUIRED on a contended
# acquire, ::warning::-prefixed CONTENDED/UNAVAILABLE/HOLDER_LOST. On ACQUIRED it
# writes holder.pid into the state dir, as the real one does; release logs whether
# that state was still there (a release after the state dir was removed is the real
# script's HOLDER_LOST path, and the section ran unserialized).
FAKE_MUTEX="$tmp/fake-mutex/dev-suite-mutex.sh"
mkdir -p "$tmp/fake-mutex"
cat > "$FAKE_MUTEX" <<'SH'
#!/usr/bin/env bash
log="${DLR_CALL_LOG:-/dev/null}"
sd="${DEV_SUITE_MUTEX_STATE_DIR:-}"
id="${DEV_SUITE_MUTEX_IDENTITY:-ti-unknown}"
case "${1:-}" in
  acquire)
    st=none; [[ -n "$sd" && -d "$sd" ]] && st=dir
    printf 'mutex acquire\n' >> "$log"
    printf 'mutex env wait=%s state=%s identity=%s\n' "${DEV_SUITE_MUTEX_WAIT_S:-}" "$st" "$id" >> "$log"
    # DLR_FAKE_MUTEX_HOOK: a command that runs while the writer "waits" (e.g. a push).
    if [[ -n "${DLR_FAKE_MUTEX_HOOK:-}" ]]; then bash -c "$DLR_FAKE_MUTEX_HOOK" >/dev/null 2>&1; fi
    case "${DLR_FAKE_MUTEX_MODE:-waiting-acquired}" in
      acquired|waiting-acquired)
        [[ "${DLR_FAKE_MUTEX_MODE:-waiting-acquired}" == waiting-acquired ]] \
          && printf 'DEV_SUITE_MUTEX_WAITING identity=%s holder=ti-other budget=%ss\n' "$id" "${DEV_SUITE_MUTEX_WAIT_S:-180}"
        printf '4242\n' > "$sd/holder.pid"
        printf 'DEV_SUITE_MUTEX_ACQUIRED wait_ms=1 identity=%s\n' "$id" ;;
      contended)
        printf 'DEV_SUITE_MUTEX_WAITING identity=%s holder=ti-other budget=%ss\n' "$id" "${DEV_SUITE_MUTEX_WAIT_S:-180}"
        printf '::warning::DEV_SUITE_MUTEX_CONTENDED_PROCEEDING holder=ti-other budget=%ss next="gh run list --workflow tenant-integration.yml (find the concurrent run)" -- wait budget exhausted; proceeding unserialized\n' "${DEV_SUITE_MUTEX_WAIT_S:-180}" ;;
      unavailable)
        printf '::warning::DEV_SUITE_MUTEX_UNAVAILABLE reason=no_database_url -- proceeding unserialized (fail-open)\n' ;;
    esac ;;
  release)
    if [[ -n "$sd" && -f "$sd/holder.pid" ]]; then
      printf 'mutex release state=present\n' >> "$log"
      rm -f "$sd/holder.pid"
      printf 'DEV_SUITE_MUTEX_RELEASED identity=%s\n' "$id"
    else
      printf 'mutex release state=missing\n' >> "$log"
      printf '::warning::DEV_SUITE_MUTEX_HOLDER_LOST pid=unknown exited -- holder died before release; the critical section may have run unserialized\n'
    fi ;;
esac
exit 0
SH
W_SQL="SELECT filename || '|' || COALESCE(content_sha, '') || '|' || COALESCE(to_char(applied_at AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISSUS'), '') FROM public._schema_migrations ORDER BY filename"
ts() { printf '202609%014d' "$1"; }   # a 20-digit applied_at (YYYYMMDDHH24MISSUS), ordered by $1
W_BASE="001_a.sql|$(blob_of A)|20260101000000000001
002_b.sql|$(blob_of B)|20260101000000000002
130_y.sql|$(blob_of Y)|20260101000000000003
131_x.sql|$(blob_of X)|20260101000000000004"
wledger() { { printf '%s\n' "$W_BASE"; [[ $# -gt 0 ]] && printf '%s\n' "$@"; true; } > "$WLEDGER"; }
wledger_raw() { printf '%s\n' "$@" > "$WLEDGER"; }

# pr_start <branch> / pr_commit <msg> <name=content|-name>... / pr_publish <N> <branch> [keep|delete]
pr_start() { git -C "$SEED" switch -q -C "$1" main; }
pr_commit() {
  local msg="$1" kv; shift
  for kv in "$@"; do
    if [[ "$kv" == -* ]]; then git -C "$SEED" rm -q "$SEED/$MDIR/${kv#-}"; else put "$SEED" "${kv%%=*}" "${kv#*=}"; fi
  done
  git -C "$SEED" add -A
  git -C "$SEED" commit -q --allow-empty -m "$msg"
}
pr_publish() {
  git -C "$SEED" push -q -f origin "HEAD:refs/pull/$1/head"
  if [[ "${3:-keep}" == "keep" ]]; then git -C "$SEED" push -q -f origin "HEAD:refs/heads/$2"; fi
  git -C "$SEED" switch -q main
}
# pr_json <N> <k|""> <open|closed> <head-ref> [author-login] [head-repo|null] [head-sha] [merged]
pr_json() {
  local n="$1" k="$2" st="$3" ref="$4" login="${5:-fixture-author}" repo="${6:-fixture-owner/fixture-repo}" sha="${7:-}" m="${8:-}" f
  [[ -n "$sha" ]] || sha=$(git -C "$ORIGIN" rev-parse "refs/pull/$n/head")
  f="$GHFIX/pull/$n.json"
  [[ -n "$k" ]] && f="$GHFIX/pull/$n.$k.json"
  jq -nc --argjson n "$n" --arg st "$st" --arg sha "$sha" --arg ref "$ref" --arg login "$login" --arg repo "$repo" --arg m "$m" \
    '{number:$n, state:$st, merged_at:(if $m == "" then null else "2026-09-20T00:00:00Z" end),
      head:{sha:$sha, ref:$ref, repo:(if $repo == "null" then null else {full_name:$repo} end)}, user:{login:$login}}' > "$f"
}
blob_file() { git hash-object --stdin <<<"$1"; }   # the blob `put` writes for content $1

# run_writer <args...> — sets out, rc; logs: $CALLLOG (ordered), $PAYLOAD (-f units), $BREACH.
run_writer() {
  : > "$CALLLOG"; : > "$PAYLOAD"; : > "$BREACH"
  rm -rf "$WRT" "$WLEDGER.post"
  mkdir -p "$WRT"
  local -a gha=()
  [[ -n "${W_GHA:-}" ]] && gha=(GITHUB_ACTIONS=true)
  set +e
  out=$(cd "$WREPO" && env -u DLP_OWNERS_CACHE -u GITHUB_ACTIONS "${gha[@]}" DOPPLER_ENVIRONMENT="${W_ENV-dev}" RUNNER_TEMP="$WRT" TMPDIR="$WRT" \
    DATABASE_URL_POOLER="postgres://pooler.fixture.invalid/db" DATABASE_URL="" \
    GITHUB_TOKEN=fixture-not-a-token DOPPLER_TOKEN=fixture-not-a-token \
    DLR_PSQL_WRITER_MODE=1 DLR_WANT_SQL="$W_SQL" DLR_PSQL_PAYLOAD="$PAYLOAD" DLR_PSQL_BREACH="$BREACH" \
    DLR_FAKE_LEDGER="$WLEDGER" DLR_GUARD="${W_GUARD-$WBIN/dev-ledger-parity.sh}" DLR_MUTEX="${W_MUTEX-$FAKE_MUTEX}" \
    bash "${W_WRITER:-$WBIN/dev-ledger-reconcile.sh}" --repo "$WREPO" --base-branch main "$@" 2>&1)
  rc=$?
  set -e
}
n_log() { grep -c -- "$1" "$CALLLOG" || true; }            # regex count in the call log
first_line() { grep -n -m1 -- "$1" "$CALLLOG" | cut -d: -f1 || true; }
last_line() { grep -n -- "$1" "$CALLLOG" | tail -n 1 | cut -d: -f1 || true; }
units() { grep -c '^psql -f' "$CALLLOG" || true; }
zero_writes() { [[ "$(units)" == "0" && ! -s "$PAYLOAD" && ! -s "$BREACH" ]]; }
one_unit() { [[ "$(units)" == "1" && ! -s "$BREACH" ]] && [[ "$(grep -c '^=== unit argv:' "$PAYLOAD" || true)" == "1" ]]; }
cas_of() { printf "DELETE FROM public._schema_migrations WHERE filename = '%s' AND content_sha = '%s';" "$1" "$2"; }
payload_line() { grep -nF -m1 -- "$1" "$PAYLOAD" | cut -d: -f1 || true; }

# ----------------------------------------------------------------------
echo "G3-H1: instrument self-test — a -f unit's contents reach the payload log verbatim"
CASES=$((CASES + 1))
: > "$PAYLOAD"; : > "$BREACH"
printf 'SELECT 1; -- known fixture unit\n' > "$tmp/known-unit.sql"
set +e
DLR_PSQL_WRITER_MODE=1 DLR_PSQL_PAYLOAD="$PAYLOAD" DLR_PSQL_BREACH="$BREACH" DLR_CALL_LOG=/dev/null DLR_WANT_SQL="$W_SQL" \
  psql "postgres://x" -w --no-psqlrc --single-transaction -f "$tmp/known-unit.sql" >/dev/null 2>&1
h1rc=$?
set -e
if [[ "$h1rc" == "0" ]] && grep -qxF 'SELECT 1; -- known fixture unit' "$PAYLOAD" && [[ ! -s "$BREACH" ]]; then
  pass "the payload log can see what every write row asserts"
else
  fail "fake psql did not record the -f payload: rc=$h1rc payload=[$(cat "$PAYLOAD")]"
fi

echo "G3-H3: writer-mode contract self-test — any call but the SELECT or one -f unit is a breach"
CASES=$((CASES + 1))
: > "$BREACH"
set +e
DLR_PSQL_WRITER_MODE=1 DLR_PSQL_PAYLOAD=/dev/null DLR_PSQL_BREACH="$BREACH" DLR_CALL_LOG=/dev/null DLR_WANT_SQL="$W_SQL" \
  psql "postgres://x" -w -c "DELETE FROM public._schema_migrations" >/dev/null 2>&1
h3rc=$?
set -e
if [[ "$h3rc" == "97" ]] && grep -q '^breach:' "$BREACH"; then
  pass "an off-contract call is refused and recorded"
else
  fail "fake psql accepted an off-contract call: rc=$h3rc breach=[$(cat "$BREACH")]"
fi

# ---------- PR 501: two applied rows, each with its .down.sql (closed, branch kept) ----------
pr_start w501
pr_commit 'w501' 301_wa.sql="WA" 301_wa.down.sql="DROP TABLE IF EXISTS wa;" 302_wb.sql="WB" 302_wb.down.sql="DROP TABLE IF EXISTS wb;"
pr_publish 501 w501
WA=$(blob_file WA); WB=$(blob_file WB)
WA_D=$(blob_file "DROP TABLE IF EXISTS wa;"); WB_D=$(blob_file "DROP TABLE IF EXISTS wb;")
gh_reset; pr_json 501 "" closed w501
wledger "301_wa.sql|$WA|$(ts 10)" "302_wb.sql|$WB|$(ts 20)"

# ----------------------------------------------------------------------
echo "G3-help: --help answers first, before every refusal (DOPPLER_ENVIRONMENT=prd, no --pr)"
CASES=$((CASES + 1))
W_ENV=prd run_writer --help
if [[ "$rc" == "0" ]] && has "ledger-discard: dry-run" && has "--execute" && has "--scan-down" && has "78 refused to run under xtrace" && [[ ! -s "$CALLLOG" ]]; then
  pass "--help is the discoverability hook"
else
  fail "expected rc=0 usage; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G3-dry (AC6): the default dry run lists rows in execution order, makes zero writes and no mutex call"
CASES=$((CASES + 1))
gh_reset; pr_json 501 "" closed w501
run_writer --pr 501
want="would-discard 302_wb.sql $WB down=$WB_D"$'\n'"would-discard 301_wa.sql $WA down=$WA_D"
got=$(grep -E '^would-discard ' <<<"$out" || true)
if [[ "$rc" == "0" && "$got" == "$want" ]] && grep -qxF 'ledger-discard: dry-run (pr=501 eligible=2 down=2 ledger-only=0 later-rows=0 held-by=0 unreachable=0)' <<<"$out" \
  && zero_writes && [[ "$(n_log '^mutex ')" == "0" && "$(n_log '^psql -c$')" == "1" ]]; then
  pass "a preview never writes and never takes the mutex"
else
  fail "dry run wrong: rc=$rc got=[$got] out=$out log=[$(cat "$CALLLOG")]"
fi

# ----------------------------------------------------------------------
gh_reset; pr_json 501 "" closed w501
run_writer --pr 501 --execute
x_out=$out; x_rc=$rc; x_log=$(cat "$CALLLOG"); x_units=$(units)
cp "$PAYLOAD" "$tmp/x-payload.log"

echo "G3-M4: two eligible rows -> exactly ONE -f call whose payload holds both CAS blocks"
CASES=$((CASES + 1))
if [[ "$x_rc" == "0" && "$x_units" == "1" ]] && one_unit && grep -qF "$(cas_of 301_wa.sql "$WA")" "$PAYLOAD" && grep -qF "$(cas_of 302_wb.sql "$WB")" "$PAYLOAD"; then
  pass "one transaction for the whole PR"
else
  fail "expected one unit with both rows; got rc=$x_rc units=$x_units out=$x_out payload=[$(cat "$PAYLOAD")]"
fi

echo "G3-M19: every CAS names filename AND content_sha and raises unless one row; argv is single-transaction, ON_ERROR_STOP"
CASES=$((CASES + 1))
n_cas=$(grep -c "DELETE FROM public._schema_migrations WHERE filename = '[^']*' AND content_sha = '[0-9a-f]\{40\}';" "$PAYLOAD" || true)
n_raise=$(grep -c "IF n <> 1 THEN" "$PAYLOAD" || true)
n_rowcount=$(grep -c "GET DIAGNOSTICS n = ROW_COUNT;" "$PAYLOAD" || true)
argv_line=$(grep -m1 '^=== unit argv:' "$PAYLOAD" || true)
if [[ "$n_cas" == "2" && "$n_raise" == "2" && "$n_rowcount" == "2" ]] && grep -qF -- ' --single-transaction ' <<<"$argv_line " \
  && grep -qE -- ' (-v|--set) ON_ERROR_STOP=1( |$)' <<<"$argv_line" && ! grep -qF 'DELETE FROM public._schema_migrations WHERE filename' <<<"$(grep -v 'AND content_sha' "$PAYLOAD")"; then
  pass "compare-and-set on both columns, one row or the whole unit rolls back"
else
  fail "CAS shape wrong: cas=$n_cas raise=$n_raise rowcount=$n_rowcount argv=[$argv_line]"
fi

echo "G3-order (AC6): timeouts first, then rows by applied_at DESC, each CAS before its down body"
CASES=$((CASES + 1))
l_lock=$(payload_line "SET LOCAL lock_timeout = '30s';")
l_stmt=$(payload_line "SET LOCAL statement_timeout = '120s';")
l_cb=$(payload_line "$(cas_of 302_wb.sql "$WB")"); l_db=$(payload_line "DROP TABLE IF EXISTS wb;")
l_ca=$(payload_line "$(cas_of 301_wa.sql "$WA")"); l_da=$(payload_line "DROP TABLE IF EXISTS wa;")
if [[ -n "$l_lock" && -n "$l_stmt" && -n "$l_cb" && -n "$l_db" && -n "$l_ca" && -n "$l_da" ]] \
  && (( l_lock < l_cb && l_stmt < l_cb && l_cb < l_db && l_db < l_ca && l_ca < l_da )); then
  pass "302 (applied later) then 301, CAS then down"
else
  fail "unit order wrong: lock=$l_lock stmt=$l_stmt cas-b=$l_cb down-b=$l_db cas-a=$l_ca down-a=$l_da"
fi

echo "G3-M5: the mutex is acquired BEFORE the ledger is read"
CASES=$((CASES + 1))
CALLS_SAVED="$tmp/x-calls.log"; printf '%s\n' "$x_log" > "$CALLS_SAVED"
la=$(grep -n -m1 '^mutex acquire$' "$CALLS_SAVED" | cut -d: -f1 || true)
ls_=$(grep -n -m1 '^psql -c$' "$CALLS_SAVED" | cut -d: -f1 || true)
if [[ -n "$la" && -n "$ls_" ]] && (( la < ls_ )); then
  pass "the rows are read inside the mutex"
else
  fail "acquire=$la select=$ls_ log=[$x_log]"
fi

echo "G3-M23: the -f unit sits between acquire and release; release comes last, with the holder state still in place"
CASES=$((CASES + 1))
lf=$(grep -n -m1 '^psql -f' "$CALLS_SAVED" | cut -d: -f1 || true)
lr=$(grep -n '^mutex release state=present$' "$CALLS_SAVED" | tail -n 1 | cut -d: -f1 || true)
if [[ -n "$la" && -n "$lf" && -n "$lr" ]] && (( la < lf && lf < lr )) && [[ "$(grep -c '^mutex release' "$CALLS_SAVED" || true)" == "1" ]]; then
  pass "the write is serialized"
else
  fail "acquire=$la unit=$lf release=$lr log=[$x_log]"
fi

echo "G3-mutex-env: own state dir, a 600 s wait, and a reconcile identity"
CASES=$((CASES + 1))
if grep -qxF 'mutex env wait=600 state=dir identity=reconcile-local-pr501' "$CALLS_SAVED" \
  || grep -qE '^mutex env wait=600 state=dir identity=reconcile-[0-9]+-pr501$' "$CALLS_SAVED"; then
  pass "the writer outwaits a tenant-integration critical section"
else
  fail "mutex env wrong: [$(grep '^mutex env' "$CALLS_SAVED" || true)]"
fi

echo "G3-token: the unit runs with GH_TOKEN, GITHUB_TOKEN and DOPPLER_TOKEN unset (PR-authored SQL sees no credential but the DB URL)"
CASES=$((CASES + 1))
if grep -qxF 'psql -f gh_token= github_token= doppler_token=' "$CALLS_SAVED"; then
  pass "the tokens are removed from the psql environment"
else
  fail "psql -f saw GH_TOKEN: [$(grep '^psql -f' "$CALLS_SAVED" || true)]"
fi

echo "G3-exec-summary: executed summary, one notice per row, psql output fenced by stop-commands"
CASES=$((CASES + 1))
if grep -qxF 'ledger-discard: executed (pr=501 eligible=2 discarded=2 down=2 ledger-only=0 held-by=0 unreachable=0)' <<<"$x_out" \
  && grep -qxF "::notice::ledger-discard: discarded 302_wb.sql (applied blob $WB, down $WB_D) for PR #501" <<<"$x_out" \
  && grep -qxF "::notice::ledger-discard: discarded 301_wa.sql (applied blob $WA, down $WA_D) for PR #501" <<<"$x_out" \
  && grep -qE '^::stop-commands::[0-9a-f]{32}$' <<<"$x_out"; then
  pass "a durable, parseable record of what was discarded"
else
  fail "summary wrong: $x_out"
fi

md5_of() { python3 -c 'import hashlib, sys; sys.stdout.write(hashlib.md5(sys.stdin.buffer.read()).hexdigest())'; }
echo "G3-unit: SET timeouts, then LOCK TABLE, then the md5 snapshot assert, then per row CAS + an EXECUTE-wrapped down with random tags, then the closing md5 assert"
CASES=$((CASES + 1))
XP="$tmp/x-payload.log"
snap_pre=$(printf '%s' "$(cat "$WLEDGER")" | md5_of)
snap_post=$(printf '%s' "$(grep -vE '^30[12]_w[ab]\.sql\|' "$WLEDGER")" | md5_of)
l_set=$(grep -nxF "SET LOCAL statement_timeout = '120s';" "$XP" | head -n 1 | cut -d: -f1) || true
l_lock=$(grep -nxF 'LOCK TABLE public._schema_migrations IN SHARE ROW EXCLUSIVE MODE;' "$XP" | head -n 1 | cut -d: -f1) || true
l_snap=$(grep -nxF 'DO $dlr_snap$' "$XP" | head -n 1 | cut -d: -f1) || true
l_cas=$(grep -nxF 'DO $dlr_cas$' "$XP" | head -n 1 | cut -d: -f1) || true
l_post=$(grep -nxF 'DO $dlr_post$' "$XP" | head -n 1 | cut -d: -f1) || true
l_lastdown=$(grep -nF 'DROP TABLE IF EXISTS wa;' "$XP" | tail -n 1 | cut -d: -f1) || true
wrap_ok=yes
for body in "DROP TABLE IF EXISTS wb;" "DROP TABLE IF EXISTS wa;"; do
  lb=$(grep -nxF -- "$body" "$XP" | head -n 1 | cut -d: -f1) || true
  if [[ ! "$lb" =~ ^[0-9]+$ ]] || (( lb < 2 )); then wrap_ok="no: body [$body] not in the payload"; continue; fi
  open_l=$(sed -n "$((lb - 1))p" "$XP"); close_l=$(sed -n "$((lb + 1)),\$p" "$XP" | grep -v '^$' | head -n 1) || true
  if [[ "$open_l" =~ ^DO\ \$dlr_o_([0-9a-f]{16})\$\ BEGIN\ EXECUTE\ \$dlr_i_([0-9a-f]{16})\$$ ]] \
    && [[ "${BASH_REMATCH[1]}" == "${BASH_REMATCH[2]}" && "$close_l" == "\$dlr_i_${BASH_REMATCH[1]}\$; END \$dlr_o_${BASH_REMATCH[1]}\$;" ]]; then
    : "${BASH_REMATCH[1]}"
  else
    wrap_ok="no: [$open_l] [$close_l]"
  fi
done
tags=$(grep -oE '^DO \$dlr_o_[0-9a-f]{16}\$' "$XP" | sort -u | grep -c . || true)
first_stmt=$(grep -vE '^(--|SET LOCAL |=== )' "$XP" | grep -v '^$' | head -n 1) || true
if [[ -n "$l_set" && -n "$l_lock" && -n "$l_snap" && -n "$l_cas" && -n "$l_post" ]] && (( l_set < l_lock && l_lock < l_snap && l_snap < l_cas && l_lastdown < l_post )) \
  && [[ "$first_stmt" == "LOCK TABLE public._schema_migrations IN SHARE ROW EXCLUSIVE MODE;" ]] \
  && grep -qF "<> '$snap_pre' THEN" "$XP" && grep -qF "<> '$snap_post' THEN" "$XP" \
  && [[ "$(sed -n "${l_snap},\$p" "$XP" | grep -m1 -F 'RAISE EXCEPTION')" == "    RAISE EXCEPTION 'ledger-discard: the ledger changed after it was read (snapshot mismatch)';" ]] \
  && [[ "$(sed -n "${l_post},\$p" "$XP" | grep -m1 -F 'RAISE EXCEPTION')" == "    RAISE EXCEPTION 'ledger-discard: ledger rows other than the claimed ones changed inside the unit';" ]] \
  && grep -qF "string_agg(filename || '|' || COALESCE(content_sha, '') || '|' || COALESCE(to_char(applied_at AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISSUS'), ''), chr(10) ORDER BY filename)" "$XP" \
  && [[ "$wrap_ok" == "yes" && "$tags" == "2" ]]; then
  pass "the server enforces what the classifier only advises, and the unit asserts the ledger it planned from"
else
  fail "unit shape: set=$l_set lock=$l_lock snap=$l_snap cas=$l_cas post=$l_post lastdown=$l_lastdown first=[$first_stmt] wrap=$wrap_ok tags=$tags pre=$snap_pre post=$snap_post"
fi

# ----------------------------------------------------------------------
echo "G3-M20: two rows where the LOWER filename was applied LATER -> it comes first"
CASES=$((CASES + 1))
pr_start w502
pr_commit 'w502' 303_wc.sql="WC" 303_wc.down.sql="DROP TABLE IF EXISTS wc;" 304_wd.sql="WD" 304_wd.down.sql="DROP TABLE IF EXISTS wd;"
pr_publish 502 w502
gh_reset; pr_json 502 "" closed w502
wledger "303_wc.sql|$(blob_file WC)|$(ts 40)" "304_wd.sql|$(blob_file WD)|$(ts 30)"
run_writer --pr 502 --execute
l_c=$(payload_line "$(cas_of 303_wc.sql "$(blob_file WC)")"); l_d=$(payload_line "$(cas_of 304_wd.sql "$(blob_file WD)")")
if [[ "$rc" == "0" && -n "$l_c" && -n "$l_d" ]] && (( l_c < l_d )); then
  pass "applied_at DESC decides, filename only breaks ties"
else
  fail "expected 303 before 304; got rc=$rc c=$l_c d=$l_d out=$out"
fi

# ----------------------------------------------------------------------
echo "G3-M1: a name that is in main's history is never this PR's, while an eligible sibling IS written"
CASES=$((CASES + 1))
pr_start w503
pr_commit 'w503' 128_x.sql="X503" 128_x.down.sql="DROP TABLE IF EXISTS x503;" 305_we.sql="WE" 305_we.down.sql="DROP TABLE IF EXISTS we;"
pr_publish 503 w503
gh_reset; pr_json 503 "" closed w503
wledger "128_x.sql|$(blob_file X503)|$(ts 50)" "305_we.sql|$(blob_file WE)|$(ts 51)"
run_writer --pr 503 --execute
if [[ "$rc" == "0" ]] && one_unit && grep -qF "$(cas_of 305_we.sql "$(blob_file WE)")" "$PAYLOAD" \
  && ! grep -qF "filename = '128_x.sql'" "$PAYLOAD" && ! grep -qF 'x503' "$PAYLOAD"; then
  pass "base history owns 128_x.sql; the sibling is discarded"
else
  fail "expected only 305_we in the unit; got rc=$rc out=$out payload=[$(cat "$PAYLOAD")]"
fi

# ----------------------------------------------------------------------
echo "G3-M2: a same-named row at a blob this PR never carried is not this PR's, while a sibling IS written"
CASES=$((CASES + 1))
pr_start w504
pr_commit 'w504' 306_wf.sql="WF-mine" 306_wf.down.sql="DROP TABLE IF EXISTS wf;" 307_wg.sql="WG" 307_wg.down.sql="DROP TABLE IF EXISTS wg;"
pr_publish 504 w504
gh_reset; pr_json 504 "" closed w504
wledger "306_wf.sql|$(blob_file WF-other)|$(ts 60)" "307_wg.sql|$(blob_file WG)|$(ts 61)"
run_writer --pr 504 --execute
if [[ "$rc" == "0" ]] && one_unit && grep -qF "$(cas_of 307_wg.sql "$(blob_file WG)")" "$PAYLOAD" \
  && ! grep -qF "filename = '306_wf.sql'" "$PAYLOAD"; then
  pass "(F, B) must be in the PR's history, not just F"
else
  fail "expected only 307_wg; got rc=$rc out=$out payload=[$(cat "$PAYLOAD")]"
fi

# ----------------------------------------------------------------------
echo "G3-M3: three eligible rows, the LAST in execution order has a CONCURRENTLY down -> rc 1, zero writes; control writes one unit"
CASES=$((CASES + 1))
pr_start w505
pr_commit 'w505' 308_h1.sql="H1" 308_h1.down.sql="DROP INDEX CONCURRENTLY IF EXISTS h1_idx;" 309_h2.sql="H2" 309_h2.down.sql="DROP TABLE IF EXISTS h2;" \
  310_h3.sql="H3" 310_h3.down.sql="DROP TABLE IF EXISTS h3;"
pr_publish 505 w505
pr_start w506
pr_commit 'w506' 311_i1.sql="I1" 311_i1.down.sql="DROP INDEX IF EXISTS i1_idx;" 312_i2.sql="I2" 312_i2.down.sql="DROP TABLE IF EXISTS i2;" \
  313_i3.sql="I3" 313_i3.down.sql="DROP TABLE IF EXISTS i3;"
pr_publish 506 w506
gh_reset; pr_json 505 "" closed w505; pr_json 506 "" closed w506
wledger "308_h1.sql|$(blob_file H1)|$(ts 70)" "309_h2.sql|$(blob_file H2)|$(ts 71)" "310_h3.sql|$(blob_file H3)|$(ts 72)"
run_writer --pr 505 --execute
r_bad=$rc; o_bad=$out; zw_bad=no; zero_writes && zw_bad=yes
wledger "311_i1.sql|$(blob_file I1)|$(ts 70)" "312_i2.sql|$(blob_file I2)|$(ts 71)" "313_i3.sql|$(blob_file I3)|$(ts 72)"
run_writer --pr 506 --execute
if [[ "$r_bad" == "1" && "$zw_bad" == "yes" && "$rc" == "0" ]] && one_unit && grep -qF '308_h1.sql' <<<"$o_bad" && grep -qF 'reason=non-transactional' <<<"$o_bad"; then
  pass "every refusal is decided before the first write"
else
  fail "expected refused (zero writes) then one unit; got bad=$r_bad zw=$zw_bad [$o_bad] control=$rc [$out]"
fi

# ----------------------------------------------------------------------
echo "G3-M6: DOPPLER_ENVIRONMENT=prd -> rc 2, the env message, zero psql calls"
CASES=$((CASES + 1))
gh_reset; pr_json 501 "" closed w501
wledger "301_wa.sql|$WA|$(ts 10)" "302_wb.sql|$WB|$(ts 20)"
W_ENV=prd run_writer --pr 501 --execute
if [[ "$rc" == "2" && "$(n_log '^psql')" == "0" && "$(n_log '^mutex')" == "0" ]] && has "DOPPLER_ENVIRONMENT"; then
  pass "never writes outside dev"
else
  fail "expected rc=2 env refusal with no psql; got rc=$rc out=$out log=[$(cat "$CALLLOG")]"
fi

# ----------------------------------------------------------------------
echo "G3-M7a: the mutex banner is CONTENDED_PROCEEDING -> rc 2 naming it, zero writes, a release call"
CASES=$((CASES + 1))
gh_reset; pr_json 501 "" closed w501
DLR_FAKE_MUTEX_MODE=contended run_writer --pr 501 --execute
if [[ "$rc" == "2" ]] && zero_writes && [[ "$(n_log '^psql')" == "0" && "$(n_log '^mutex release')" == "1" ]] \
  && grep -qxF 'DEV_SUITE_MUTEX_CONTENDED_PROCEEDING' <<<"$out" && has "could not hold the dev-suite mutex (DEV_SUITE_MUTEX_CONTENDED_PROCEEDING)"; then
  pass "a fail-open mutex banner is not a lock"
else
  fail "expected rc=2 + release; got rc=$rc out=$out log=[$(cat "$CALLLOG")]"
fi

echo "G3-M7b: the mutex banner is UNAVAILABLE -> rc 2 naming it"
CASES=$((CASES + 1))
gh_reset; pr_json 501 "" closed w501
DLR_FAKE_MUTEX_MODE=unavailable run_writer --pr 501 --execute
if [[ "$rc" == "2" ]] && zero_writes && has "could not hold the dev-suite mutex (DEV_SUITE_MUTEX_UNAVAILABLE)"; then
  pass "an unusable mutex is not a lock either"
else
  fail "expected rc=2 naming UNAVAILABLE; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G3-M8a: the author edited ONLY F.down.sql after apply -> the NEWER down body is used"
CASES=$((CASES + 1))
pr_start w507
pr_commit 'w507 c1' 314_wj.sql="WJ" 314_wj.down.sql="-- jdown v1 older"
pr_commit 'w507 c2' 314_wj.down.sql="-- jdown v2 newer"
pr_publish 507 w507
gh_reset; pr_json 507 "" closed w507
wledger "314_wj.sql|$(blob_file WJ)|$(ts 75)"
run_writer --pr 507 --execute
if [[ "$rc" == "0" ]] && grep -qxF -- '-- jdown v2 newer' "$PAYLOAD" && ! grep -qF 'jdown v1' "$PAYLOAD"; then
  pass "the pairing follows the last commit that still carried F at B"
else
  fail "expected the v2 down; got rc=$rc out=$out payload=[$(cat "$PAYLOAD")]"
fi

echo "G3-M8b: the author edited F AND F.down.sql after apply -> the OLDER down body is used"
CASES=$((CASES + 1))
pr_start w508
pr_commit 'w508 c1' 315_wk.sql="WK1" 315_wk.down.sql="-- kdown v1 older"
pr_commit 'w508 c2' 315_wk.sql="WK2" 315_wk.down.sql="-- kdown v2 newer"
pr_publish 508 w508
gh_reset; pr_json 508 "" closed w508
wledger "315_wk.sql|$(blob_file WK1)|$(ts 76)"
run_writer --pr 508 --execute
if [[ "$rc" == "0" ]] && grep -qxF -- '-- kdown v1 older' "$PAYLOAD" && ! grep -qF 'kdown v2' "$PAYLOAD"; then
  pass "the down paired with the APPLIED body, not the latest one"
else
  fail "expected the v1 down; got rc=$rc out=$out payload=[$(cat "$PAYLOAD")]"
fi

# ----------------------------------------------------------------------
echo "G3-M9: a down blob whose bytes do not hash to its id -> rc 2, zero psql calls"
CASES=$((CASES + 1))
gh_reset; pr_json 501 "" closed w501
wledger "301_wa.sql|$WA|$(ts 10)" "302_wb.sql|$WB|$(ts 20)"
export DLR_GH_BLOB_CORRUPT=1
run_writer --pr 501 --execute
unset DLR_GH_BLOB_CORRUPT
if [[ "$rc" == "2" && "$(n_log '^psql')" == "0" ]] && zero_writes; then
  pass "a body is verified against its id before it can reach psql"
else
  fail "expected rc=2 with no psql; got rc=$rc out=$out log=[$(cat "$CALLLOG")]"
fi

# ---------- PR 509: a CASCADE down ----------
pr_start w509
pr_commit 'w509' 316_wl.sql="WL" 316_wl.down.sql="DROP TABLE IF EXISTS wl CASCADE;"
pr_publish 509 w509
WL=$(blob_file WL)

echo "G3-M10a: a CASCADE down while a later FOREIGN row exists -> rc 1, zero writes, the later row listed"
CASES=$((CASES + 1))
gh_reset; pr_json 509 "" closed w509
wledger "316_wl.sql|$WL|$(ts 80)" "399_foreign.sql|$(blob_file FOREIGN)|$(ts 81)"
run_writer --pr 509 --execute
m10a_rc=$rc; m10a_log=$(cat "$CALLLOG"); m10a_left=$(find "$WRT" -mindepth 1 -maxdepth 1 | head -n 5)
if [[ "$rc" == "1" ]] && zero_writes && grep -qxF "later-row 399_foreign.sql $(ts 81)" <<<"$out" && grep -qF 'reason=later-row' <<<"$out"; then
  pass "a CASCADE cannot reach a later row's objects"
else
  fail "expected rc=1 later-row refusal; got rc=$rc out=$out"
fi

echo "G3-M14: a refused run after acquire still releases the mutex AND removes its temp dirs (composed EXIT trap)"
CASES=$((CASES + 1))
if [[ "$m10a_rc" == "1" && -z "$m10a_left" ]] && [[ "$(grep -c '^mutex release state=present$' <<<"$m10a_log" || true)" == "1" ]]; then
  pass "the writer's trap releases, then the guard's cleanup and its own temp removal run"
else
  fail "trap composition broken: rc=$m10a_rc leftover=[$m10a_left] log=[$m10a_log]"
fi

echo "G3-M10b: the same CASCADE down with NO later row -> written (no over-refusal)"
CASES=$((CASES + 1))
gh_reset; pr_json 509 "" closed w509
wledger "316_wl.sql|$WL|$(ts 80)"
run_writer --pr 509 --execute
if [[ "$rc" == "0" ]] && one_unit && grep -qxF 'DROP TABLE IF EXISTS wl CASCADE;' "$PAYLOAD"; then
  pass "later-row safety fires only when a later row exists"
else
  fail "expected written; got rc=$rc out=$out"
fi

echo "G3-M10c: the same body + a later row + --allow-later-rows -> written"
CASES=$((CASES + 1))
gh_reset; pr_json 509 "" closed w509
wledger "316_wl.sql|$WL|$(ts 80)" "399_foreign.sql|$(blob_file FOREIGN)|$(ts 81)"
run_writer --pr 509 --execute --allow-later-rows
if [[ "$rc" == "0" ]] && one_unit && grep -qxF 'DROP TABLE IF EXISTS wl CASCADE;' "$PAYLOAD"; then
  pass "the human override after a dry run is honoured"
else
  fail "expected written with the override; got rc=$rc out=$out"
fi

echo "G3-M10d: a CREATE OR REPLACE FUNCTION down while a later MAIN row exists -> rc 1"
CASES=$((CASES + 1))
pr_start w510
pr_commit 'w510' 317_wm.sql="WM" 317_wm.down.sql='CREATE OR REPLACE FUNCTION public.wm() RETURNS int LANGUAGE sql AS $$ SELECT 1 $$;'
pr_publish 510 w510
gh_reset; pr_json 510 "" closed w510
wledger_raw "001_a.sql|$(blob_of A)|20260101000000000001" "002_b.sql|$(blob_of B)|20260101000000000002" \
  "130_y.sql|$(blob_of Y)|$(ts 91)" "131_x.sql|$(blob_of X)|20260101000000000004" "317_wm.sql|$(blob_file WM)|$(ts 90)"
run_writer --pr 510 --execute
if [[ "$rc" == "1" ]] && zero_writes && grep -qxF "later-row 130_y.sql $(ts 91)" <<<"$out"; then
  pass "a redefinition cannot silently revert main's later definition"
else
  fail "expected rc=1; got rc=$rc out=$out"
fi

echo "G3-M11: two later rows, the first the PR's own and the second foreign -> rc 1"
CASES=$((CASES + 1))
pr_start w511
pr_commit 'w511' 318_wn.sql="WN" 318_wn.down.sql="DROP TABLE IF EXISTS wn CASCADE;" 319_wo.sql="WO" 319_wo.down.sql="DROP TABLE IF EXISTS wo;"
pr_publish 511 w511
gh_reset; pr_json 511 "" closed w511
wledger "318_wn.sql|$(blob_file WN)|$(ts 100)" "319_wo.sql|$(blob_file WO)|$(ts 101)" "398_foreign2.sql|$(blob_file F2)|$(ts 102)"
run_writer --pr 511 --execute
if [[ "$rc" == "1" ]] && zero_writes && grep -qxF "later-row 398_foreign2.sql $(ts 102)" <<<"$out" && ! grep -qF 'later-row 319_wo.sql' <<<"$out"; then
  pass "every later row is checked, the PR's own excluded"
else
  fail "expected rc=1 naming 398_foreign2 only; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G3-M15a: a down wrapped in BEGIN; ... COMMIT; -> written with the wrapper stripped"
CASES=$((CASES + 1))
pr_start w512
pr_commit 'w512' 320_wp.sql="WP" 320_wp.down.sql=$'-- header\nBEGIN;\nDROP TABLE IF EXISTS wp;\nCOMMIT;'
pr_publish 512 w512
gh_reset; pr_json 512 "" closed w512
wledger "320_wp.sql|$(blob_file WP)|$(ts 110)"
run_writer --pr 512 --execute
if [[ "$rc" == "0" ]] && one_unit && grep -qxF 'DROP TABLE IF EXISTS wp;' "$PAYLOAD" && ! grep -qixE '[[:space:]]*(BEGIN|COMMIT);[[:space:]]*' "$PAYLOAD"; then
  pass "a single wrapping transaction is self-service"
else
  fail "expected written without the wrapper; got rc=$rc out=$out payload=[$(cat "$PAYLOAD")]"
fi

echo "G3-M15b: a mid-body COMMIT; -> rc 1, zero writes"
CASES=$((CASES + 1))
pr_start w513
pr_commit 'w513' 321_wq.sql="WQ" 321_wq.down.sql=$'DROP TABLE IF EXISTS wq1;\nCOMMIT;\nDROP TABLE IF EXISTS wq2;'
pr_publish 513 w513
gh_reset; pr_json 513 "" closed w513
wledger "321_wq.sql|$(blob_file WQ)|$(ts 111)"
run_writer --pr 513 --execute
if [[ "$rc" == "1" ]] && zero_writes && grep -qF 'reason=transaction-control' <<<"$out"; then
  pass "only a WRAPPING pair is normalized"
else
  fail "expected rc=1 transaction-control; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G3-M16: --require-closed re-reads the PR AFTER acquire; closed->open -> skipped, zero writes"
CASES=$((CASES + 1))
pr_start w514
pr_commit 'w514' 322_ws2.sql="WS2" 322_ws2.down.sql="DROP TABLE IF EXISTS ws2;"
pr_publish 514 w514
gh_reset; pr_json 514 1 closed w514; pr_json 514 2 open w514
wledger "322_ws2.sql|$(blob_file WS2)|$(ts 112)"
run_writer --pr 514 --execute --require-closed
la=$(first_line '^mutex acquire$'); lp=$(last_line '^gh pulls/514$')
if [[ "$rc" == "0" ]] && zero_writes && grep -qxF 'ledger-discard: skipped (pr=514 reason=reopened)' <<<"$out" \
  && [[ "$(n_log '^gh pulls/514$')" == "2" && -n "$la" && -n "$lp" ]] && (( la < lp )); then
  pass "a reopen that wins the race stops the close-time discard"
else
  fail "expected skipped with the re-read after acquire; got rc=$rc out=$out log=[$(cat "$CALLLOG")]"
fi

# ----------------------------------------------------------------------
echo "G3-M17: a down body with a psql meta-command (\\!) -> rc 1, ZERO psql calls, no shell ran"
CASES=$((CASES + 1))
SENT="$tmp/sentinel-515"
rm -f "$SENT"
pr_start w515
pr_commit 'w515' 323_wr.sql="WR" 323_wr.down.sql="\\! touch $SENT"
pr_publish 515 w515
gh_reset; pr_json 515 "" closed w515
wledger "323_wr.sql|$(blob_file WR)|$(ts 113)"
run_writer --pr 515 --execute
if [[ "$rc" == "1" && "$(n_log '^psql')" == "0" && ! -e "$SENT" ]] && grep -qF 'reason=backslash' <<<"$out"; then
  pass "PR text never reaches a shell"
else
  fail "expected rc=1 with no psql call; got rc=$rc sentinel=$([[ -e "$SENT" ]] && echo present || echo absent) out=$out"
fi

echo "G3-M18: a down restoring a plpgsql function (BEGIN/END inside \$\$) -> written"
CASES=$((CASES + 1))
pr_start w516
pr_commit 'w516' 324_wfn.sql="WFN" 324_wfn.down.sql=$'CREATE OR REPLACE FUNCTION public.wfn() RETURNS void LANGUAGE plpgsql AS $$\nBEGIN\n  PERFORM 1;\nEND;\n$$;'
pr_publish 516 w516
gh_reset; pr_json 516 "" closed w516
wledger "324_wfn.sql|$(blob_file WFN)|$(ts 114)"
run_writer --pr 516 --execute
if [[ "$rc" == "0" ]] && one_unit && grep -qxF '  PERFORM 1;' "$PAYLOAD"; then
  pass "refusals match the stripped view, not raw text"
else
  fail "expected written; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G3-M21: an OPEN PR's rows are written only for its author (bob refused, alice written)"
CASES=$((CASES + 1))
pr_start w517
pr_commit 'w517' 325_wt.sql="WT" 325_wt.down.sql="DROP TABLE IF EXISTS wt;"
pr_publish 517 w517
gh_reset; pr_json 517 "" open w517 alice
wledger "325_wt.sql|$(blob_file WT)|$(ts 115)"
run_writer --pr 517 --execute --actor bob
r_bob=$rc; o_bob=$out; zw_bob=no; zero_writes && zw_bob=yes
gh_reset; pr_json 517 "" open w517 alice
run_writer --pr 517 --execute --actor alice
if [[ "$r_bob" == "1" && "$zw_bob" == "yes" && "$rc" == "0" ]] && one_unit && grep -qF 'reason=open-author' <<<"$o_bob"; then
  pass "only the author can discard an open PR's rows"
else
  fail "expected bob refused, alice written; got bob=$r_bob zw=$zw_bob [$o_bob] alice=$rc [$out]"
fi

echo "G3-M22: an OPEN PR's eligible row with no .down.sql -> rc 1 even for the author"
CASES=$((CASES + 1))
pr_start w518
pr_commit 'w518' 326_wu.sql="WU"
pr_publish 518 w518
gh_reset; pr_json 518 "" open w518 alice
wledger "326_wu.sql|$(blob_file WU)|$(ts 116)"
run_writer --pr 518 --execute --actor alice
if [[ "$rc" == "1" ]] && zero_writes && grep -qF 'reason=open-ledger-only' <<<"$out"; then
  pass "no discard-then-re-apply residue on an open PR"
else
  fail "expected rc=1 open-ledger-only; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G3-deleted: a closed PR whose branch was DELETED (only refs/pull/N/head) is reconcilable"
CASES=$((CASES + 1))
pr_start w519
pr_commit 'w519' 327_wv.sql="WV" 327_wv.down.sql="DROP TABLE IF EXISTS wv;"
pr_publish 519 w519 delete
gh_reset; pr_json 519 "" closed w519
wledger "327_wv.sql|$(blob_file WV)|$(ts 117)"
run_writer --pr 519 --execute
if [[ "$rc" == "0" ]] && one_unit && grep -qF "$(cas_of 327_wv.sql "$(blob_file WV)")" "$PAYLOAD"; then
  pass "refs/pull/N/head survives branch deletion"
else
  fail "expected written; got rc=$rc out=$out"
fi

echo "G3-ledger-only: a closed PR's row with no .down.sql -> CAS only, residue ::warning::, ledger-only=1"
CASES=$((CASES + 1))
pr_start w520
pr_commit 'w520' 328_ww2.sql="WW2"
pr_publish 520 w520
gh_reset; pr_json 520 "" closed w520
wledger "328_ww2.sql|$(blob_file WW2)|$(ts 118)"
run_writer --pr 520 --execute
if [[ "$rc" == "0" ]] && one_unit && grep -qF "$(cas_of 328_ww2.sql "$(blob_file WW2)")" "$PAYLOAD" \
  && grep -qxF "::warning::ledger-discard: 328_ww2.sql has no .down.sql paired with applied blob $(blob_file WW2); objects its body created stay on dev" <<<"$out" \
  && grep -qxF 'ledger-discard: executed (pr=520 eligible=1 discarded=1 down=0 ledger-only=1 held-by=0 unreachable=0)' <<<"$out"; then
  pass "the operator's direction: discard the row, disclose the residue"
else
  fail "expected a ledger-only discard with the residue warning; got rc=$rc out=$out"
fi

echo "G3-nothing: a PR whose history carries no migration -> nothing to do, no mutex, no psql"
CASES=$((CASES + 1))
git -C "$SEED" switch -q -C w521 main
printf 'docs\n' > "$SEED/README-521.md"
git -C "$SEED" add -A && git -C "$SEED" commit -qm 'w521 docs only'
pr_publish 521 w521
gh_reset; pr_json 521 "" closed w521
run_writer --pr 521 --execute
if [[ "$rc" == "0" && "$(n_log '^mutex')" == "0" && "$(n_log '^psql')" == "0" ]] && grep -qxF 'ledger-discard: nothing to do (pr=521)' <<<"$out"; then
  pass "a git-only early exit before any database contact"
else
  fail "expected nothing to do; got rc=$rc out=$out log=[$(cat "$CALLLOG")]"
fi

echo "G3-fork: a fork PR, or a null head.repo -> rc 1 (fork PRs never applied to dev)"
CASES=$((CASES + 1))
gh_reset; pr_json 501 "" closed w501 fixture-author someone/fork
wledger "301_wa.sql|$WA|$(ts 10)" "302_wb.sql|$WB|$(ts 20)"
run_writer --pr 501 --execute; r1=$rc; o1=$out
gh_reset; pr_json 501 "" closed w501 fixture-author null
run_writer --pr 501 --execute; r2=$rc
if [[ "$r1$r2" == "11" && "$(n_log '^psql')" == "0" ]] && grep -qF 'reason=fork' <<<"$o1" && has 'reason=fork'; then
  pass "fork heads are refused before git or the database"
else
  fail "expected rc=1 twice; got $r1/$r2 [$o1] [$out]"
fi

echo "G3-headsha: the API head.sha differs from refs/pull/N/head -> rc 2 (a push landed between reads)"
CASES=$((CASES + 1))
gh_reset; pr_json 501 "" closed w501 fixture-author "" "$(git -C "$ORIGIN" rev-parse refs/heads/main)"
run_writer --pr 501 --execute
if [[ "$rc" == "2" && "$(n_log '^psql')" == "0" ]] && zero_writes; then
  pass "facts from two reads must agree"
else
  fail "expected rc=2; got rc=$rc out=$out"
fi

# ---------- PR 523: independent vs inherited holders ----------
pr_start w523
pr_commit 'w523' 329_wx.sql="WX" 329_wx.down.sql="DROP TABLE IF EXISTS wx;"
pr_publish 523 w523

echo "G3-indep: another fresh branch holding F at B with NO pull request -> held-by it, nothing written"
CASES=$((CASES + 1))
branch w523-indep main "" 329_wx.sql="WX"
gh_reset; pr_json 523 "" closed w523
wledger "329_wx.sql|$(blob_file WX)|$(ts 120)"
run_writer --pr 523 --execute
git -C "$SEED" push -q origin --delete w523-indep
if [[ "$rc" == "0" ]] && zero_writes && grep -qxF 'ledger-discard: held-by 329_wx.sql w523-indep' <<<"$out" \
  && grep -qxF 'ledger-discard: nothing to do (pr=523 eligible=0 down=0 ledger-only=0 later-rows=0 held-by=1 unreachable=0)' <<<"$out"; then
  pass "a live holder with no PR protects the shared row"
else
  fail "expected held-by w523-indep; got rc=$rc out=$out"
fi

echo "G3-stacked: a branch STACKED on the PR (inherited F) with an OPEN PR protects F too, regardless of ancestry (CTO ruling 4)"
CASES=$((CASES + 1))
git -C "$SEED" switch -q -C w523-stack "$(git -C "$ORIGIN" rev-parse refs/pull/523/head)"
put "$SEED" 330_child.sql "CHILD523"
git -C "$SEED" add -A && git -C "$SEED" commit -qm 'stacked child'
git -C "$SEED" push -q -f origin HEAD:refs/heads/w523-stack
git -C "$SEED" switch -q main
gh_reset; pr_json 523 "" closed w523
gh_head_json w523-stack "[$(pr_obj 7524 open "" "$(tip_of w523-stack)")]"
run_writer --pr 523 --execute
st_rc=$rc; st_out=$out; st_zw=no; zero_writes && st_zw=yes

echo "G3-stacked-closed: the same stacked holder whose latest PR CLOSED at its tip does not protect -> written"
CASES=$((CASES + 1))
gh_reset; pr_json 523 "" closed w523
gh_head_json w523-stack "[$(pr_obj 7524 closed "$(hours_ago 2)" "$(tip_of w523-stack)")]"
run_writer --pr 523 --execute
git -C "$SEED" push -q origin --delete w523-stack
if [[ "$st_rc" == "0" && "$st_zw" == "yes" ]] && grep -qxF 'ledger-discard: held-by 329_wx.sql w523-stack' <<<"$st_out"; then
  pass "an open stacked PR holds the shared row"
else
  fail "expected held-by w523-stack; got rc=$st_rc out=$st_out"
fi
if [[ "$rc" == "0" ]] && one_unit && grep -qF "$(cas_of 329_wx.sql "$(blob_file WX)")" "$PAYLOAD" && ! grep -q '^ledger-discard: held-by' <<<"$out"; then
  pass "a closed-at-tip holder does not protect"
else
  fail "expected written; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
echo "G3-timeout: a lock timeout inside the unit (SQLSTATE 55P03) -> rc 2"
CASES=$((CASES + 1))
gh_reset; pr_json 501 "" closed w501
wledger "301_wa.sql|$WA|$(ts 10)" "302_wb.sql|$WB|$(ts 20)"
DLR_FAKE_UNIT_RC=3 DLR_FAKE_UNIT_OUT=$'psql:/x/unit.sql:5: ERROR:  55P03: canceling statement due to lock timeout\n' run_writer --pr 501 --execute
if [[ "$rc" == "2" ]] && has "SQLSTATE 55P03" && has "cannot measure (transient)" && ! grep -q '^::notice::ledger-discard: discarded' <<<"$out"; then
  pass "a timeout is cannot-measure, nothing claimed as discarded"
else
  fail "expected rc=2 on a lock timeout; got rc=$rc out=$out"
fi

echo "G3-unitfail: a failing statement -> rc 1 naming the row's file; PR-authored output stays fenced"
CASES=$((CASES + 1))
gh_reset; pr_json 501 "" closed w501
DLR_FAKE_UNIT_RC=3 DLR_FAKE_UNIT_FAIL_AT="DROP TABLE IF EXISTS wa;" DLR_FAKE_UNIT_OUT=$'NOTICE:  00000: ::error::pwned-by-sql\n' run_writer --pr 501 --execute
if [[ "$rc" == "1" ]] && grep -qE '^::error::ledger-discard: the unit failed at 301_wa\.sql ' <<<"$out" && ! grep -qE '^::error::pwned' <<<"$out" \
  && grep -qxF 'ledger-discard: failed (pr=501 eligible=2 down=2 ledger-only=0 later-rows=0 held-by=0 unreachable=0 reason=unit)' <<<"$out" \
  && grep -qE '^    NOTICE:  00000: ::error::pwned-by-sql$' <<<"$out" && ! grep -q '^::notice::ledger-discard: discarded' <<<"$out"; then
  pass "the failure is named from the writer's own text; psql output is indented inside stop-commands"
else
  fail "expected rc=1 with fenced psql output; got rc=$rc out=$out"
fi

echo "G3-early-reopen: --require-closed on a PR that is already open -> skipped before the mutex"
CASES=$((CASES + 1))
gh_reset; pr_json 514 "" open w514
run_writer --pr 514 --execute --require-closed
if [[ "$rc" == "0" && "$(n_log '^mutex')" == "0" ]] && zero_writes && grep -qxF 'ledger-discard: skipped (pr=514 reason=reopened)' <<<"$out"; then
  pass "a close event that raced a reopen is a no-op, not a refusal"
else
  fail "expected skipped; got rc=$rc out=$out"
fi

# ----------------------------------------------------------------------
# ----------------------------------------------------------------------
echo "G3-merged: a MERGED PR -> refused merged (no counters: nothing was measured), zero psql, no mutex"
CASES=$((CASES + 1))
gh_reset; pr_json 501 "" closed w501 fixture-author "" "" merged
wledger "301_wa.sql|$WA|$(ts 10)" "302_wb.sql|$WB|$(ts 20)"
run_writer --pr 501 --execute
if [[ "$rc" == "1" && "$(n_log '^psql')" == "0" && "$(n_log '^mutex')" == "0" ]] && grep -qxF 'ledger-discard: refused (pr=501 reason=merged)' <<<"$out"; then
  pass "a merged PR's migrations are main's (CTO ruling 5)"
else
  fail "expected refused merged; got rc=$rc out=$out"
fi

echo "G3-early-counters: an early refusal prints no unmeasured counters (fork)"
CASES=$((CASES + 1))
gh_reset; pr_json 501 "" closed w501 fixture-author someone/fork
run_writer --pr 501 --execute
if [[ "$rc" == "1" ]] && grep -qxF 'ledger-discard: refused (pr=501 reason=fork)' <<<"$out" && ! grep -q 'eligible=' <<<"$out"; then
  pass "counters appear only once measured"
else
  fail "expected the bare fork refusal; got rc=$rc out=$out"
fi

echo "G3-inmutex-merged: closed at the first read, MERGED at the in-mutex re-read -> refused merged, zero writes, released"
CASES=$((CASES + 1))
gh_reset; pr_json 501 1 closed w501; pr_json 501 2 closed w501 fixture-author "" "" merged
run_writer --pr 501 --execute
if [[ "$rc" == "1" ]] && zero_writes && grep -qxF 'ledger-discard: refused (pr=501 reason=merged)' <<<"$out" \
  && [[ "$(n_log '^gh pulls/501$')" == "2" && "$(n_log '^mutex release')" == "1" && "$(n_log '^psql')" == "0" ]]; then
  pass "the PR is re-read inside the mutex"
else
  fail "expected the in-mutex merged refusal; got rc=$rc out=$out log=[$(cat "$CALLLOG")]"
fi

echo "G3-inmutex-head: the head sha moved while the run waited for the mutex -> rc 2, zero writes"
CASES=$((CASES + 1))
gh_reset; pr_json 501 1 closed w501; pr_json 501 2 closed w501 fixture-author "" "$(git -C "$ORIGIN" rev-parse refs/heads/main)"
run_writer --pr 501 --execute
if [[ "$rc" == "2" ]] && zero_writes && has "the PR head moved while this run waited for the mutex" && [[ "$(n_log '^psql')" == "0" ]]; then
  pass "a push that lands during the wait is seen before the write"
else
  fail "expected rc=2 head moved; got rc=$rc out=$out"
fi

echo "G3-capture-msg: a lookup that fails INSIDE a captured call (the classifier's PR listing) -> rc 2 with its ::error:: line in the log"
CASES=$((CASES + 1))
gh_reset; pr_json 501 "" closed w501
wledger "301_wa.sql|$WA|$(ts 10)" "302_wb.sql|$WB|$(ts 20)"
export DLR_GH_HEAD_MODE=5xx
run_writer --pr 501 --execute
unset DLR_GH_HEAD_MODE
if [[ "$rc" == "2" ]] && zero_writes && grep -qE '^::error::ledger-discard: cannot measure \(transient\): GitHub REST lookup failed twice \(HTTP 502' <<<"$out"; then
  pass "cannot_measure writes to stderr, so a \$(...) caller cannot swallow it"
else
  fail "expected the transient line in the log; got rc=$rc out=$out"
fi

echo "G3-inmutex-owners: a live holder of (F, B) pushed WHILE the run waits for the mutex -> held-by it, nothing written"
CASES=$((CASES + 1))
gh_reset; pr_json 501 "" closed w501
wledger "301_wa.sql|$WA|$(ts 10)" "302_wb.sql|$WB|$(ts 20)"
DLR_FAKE_MUTEX_HOOK="git -C '$ORIGIN' update-ref refs/heads/w501-late refs/heads/w501" run_writer --pr 501 --execute
git -C "$ORIGIN" update-ref -d refs/heads/w501-late
if [[ "$rc" == "0" ]] && zero_writes && grep -qxF 'ledger-discard: held-by 301_wa.sql w501-late' <<<"$out" \
  && grep -qxF 'ledger-discard: held-by 302_wb.sql w501-late' <<<"$out"; then
  pass "origin's heads are re-fetched inside the mutex (CTO ruling 6)"
else
  fail "expected held-by w501-late; got rc=$rc out=$out"
fi

# ---------- PR 530: an attributed row whose applied body was force-pushed away, plus an eligible sibling ----------
pr_start w530
pr_commit 'w530' 331_fp.sql="FP2" 332_fq.sql="FQ" 332_fq.down.sql="DROP TABLE IF EXISTS fq;"
pr_publish 530 w530
echo "G3-unreach-fp: a row attributed to PR #530 (closed at the tip) whose applied blob is not in its history -> unreachable reason=force-pushed; the sibling is written"
CASES=$((CASES + 1))
gh_reset; pr_json 530 "" closed w530
gh_head_json w530 "[$(pr_obj 530 closed "$(hours_ago 2)" "$(tip_of w530)")]"
wledger "331_fp.sql|$(blob_file FP1)|$(ts 130)" "332_fq.sql|$(blob_file FQ)|$(ts 131)"
run_writer --pr 530 --execute
if [[ "$rc" == "0" ]] && one_unit && grep -qxF 'ledger-discard: unreachable 331_fp.sql reason=force-pushed' <<<"$out" \
  && ! grep -qF "filename = '331_fp.sql'" "$PAYLOAD" && grep -qF "$(cas_of 332_fq.sql "$(blob_file FQ)")" "$PAYLOAD" \
  && grep -qxF 'ledger-discard: executed (pr=530 eligible=1 discarded=1 down=1 ledger-only=0 held-by=0 unreachable=1)' <<<"$out" \
  && grep -qE '^::error::ledger-discard: 331_fp\.sql is attributed to PR #530 ' <<<"$out"; then
  pass "a force-pushed-away body is never discarded blind (CTO ruling 1)"
else
  fail "expected unreachable force-pushed + the sibling written; got rc=$rc out=$out"
fi

# ---------- PR 531: attributed rows matched by slug, and one with no content_sha ----------
pr_start w531
pr_commit 'w531' 334_w531slug.sql="SL" 335_nh.sql="NH"
pr_publish 531 w531
echo "G3-unreach-slug/no-history: a slug-attributed row -> reason=slug; an attributed row with no content_sha -> reason=no-history"
CASES=$((CASES + 1))
gh_reset; pr_json 531 "" closed w531
gh_head_json w531 "[$(pr_obj 531 closed "$(hours_ago 2)" "$(tip_of w531)")]"
wledger "333_w531slug.sql|$(blob_file SL-old)|$(ts 132)" "335_nh.sql||$(ts 133)"
run_writer --pr 531 --execute
if [[ "$rc" == "0" ]] && zero_writes && grep -qxF 'ledger-discard: unreachable 333_w531slug.sql reason=slug' <<<"$out" \
  && grep -qxF 'ledger-discard: unreachable 335_nh.sql reason=no-history' <<<"$out" \
  && grep -qxF 'ledger-discard: nothing to do (pr=531 eligible=0 down=0 ledger-only=0 later-rows=0 held-by=0 unreachable=2)' <<<"$out"; then
  pass "every attributed row ends discarded, held-by or unreachable"
else
  fail "expected two unreachable lines; got rc=$rc out=$out"
fi

# ---------- PR 533: a closed CHILD whose history carries its OPEN parent's row ----------
git -C "$SEED" switch -q -C w533p main
put "$SEED" 336_par.sql "PAR"; put "$SEED" 336_par.down.sql "DROP TABLE IF EXISTS par;"
git -C "$SEED" add -A && git -C "$SEED" commit -qm 'w533 parent'
git -C "$SEED" push -q -f origin HEAD:refs/heads/w533p
pr_start w533c
git -C "$SEED" reset -q --hard w533p
pr_commit 'w533 child' 337_ch.sql="CH" 337_ch.down.sql="DROP TABLE IF EXISTS ch;"
pr_publish 533 w533c
echo "G3-held-parent: a closed child PR's history carries the OPEN parent's row -> held-by the parent; the child's own row is written"
CASES=$((CASES + 1))
gh_reset; pr_json 533 "" closed w533c
gh_head_json w533p "[$(pr_obj 532 open "" "$(tip_of w533p)")]"
wledger "336_par.sql|$(blob_file PAR)|$(ts 134)" "337_ch.sql|$(blob_file CH)|$(ts 135)"
run_writer --pr 533 --execute
git -C "$SEED" push -q origin --delete w533p
if [[ "$rc" == "0" ]] && one_unit && grep -qxF 'ledger-discard: held-by 336_par.sql w533p' <<<"$out" \
  && ! grep -qF "filename = '336_par.sql'" "$PAYLOAD" && grep -qF "$(cas_of 337_ch.sql "$(blob_file CH)")" "$PAYLOAD"; then
  pass "a child's close leaves shared rows until the parent closes"
else
  fail "expected held-by w533p + the child row written; got rc=$rc out=$out"
fi

echo "G3-postcheck: psql exits 0 but the claimed row is still there, or ANOTHER row vanished -> rc 1 failed post-check, nothing claimed as discarded"
CASES=$((CASES + 1))
gh_reset; pr_json 501 "" closed w501
wledger "301_wa.sql|$WA|$(ts 10)" "302_wb.sql|$WB|$(ts 20)"
DLR_FAKE_POST=keep run_writer --pr 501 --execute; r1=$rc; o1=$out
gh_reset; pr_json 501 "" closed w501
DLR_FAKE_POST=drop:001_a.sql run_writer --pr 501 --execute; r2=$rc; o2=$out
if [[ "$r1$r2" == "11" ]] && grep -qF 'after the unit the ledger still holds 301_wa.sql at its applied blob' <<<"$o1" \
  && grep -qF '(1 other line(s) differ)' <<<"$o2" && grep -qF 'reason=post-check)' <<<"$o1" && grep -qF 'reason=post-check)' <<<"$o2" \
  && ! grep -q '^::notice::ledger-discard: discarded' <<<"$o1$o2" && ! grep -q '^ledger-discard: executed' <<<"$o1$o2"; then
  pass "the claim is verified against a fresh read of the ledger"
else
  fail "post-check: [$r1] $o1 || [$r2] $o2"
fi

echo "G3-connect: the unit's connection fails (psql rc=2) -> rc 2, the psql text (it names the host) is withheld"
CASES=$((CASES + 1))
gh_reset; pr_json 501 "" closed w501
DLR_FAKE_UNIT_RC=2 DLR_FAKE_UNIT_OUT='psql: error: connection to server at "db.fixture.invalid" (192.0.2.1), port 6543 failed' run_writer --pr 501 --execute
if [[ "$rc" == "2" ]] && has "psql rc=2" && has "cannot measure (connect)" && ! has "db.fixture.invalid" && ! has "192.0.2.1"; then
  pass "only the rc is reported on a connection failure"
else
  fail "expected rc=2 with the host withheld; got rc=$rc out=$out"
fi

# ---------- PR 534: a down body that contains the first candidate tag ----------
pr_start w534
pr_commit 'w534' 338_tg.sql="TG" 338_tg.down.sql=$'-- dlr_o_aaaaaaaaaaaaaaaa\nDROP TABLE IF EXISTS tg;'
pr_publish 534 w534
echo "G3-tags: a tag that occurs in the body is never used (the next candidate is); when every candidate occurs -> rc 2, zero writes"
CASES=$((CASES + 1))
gh_reset; pr_json 534 "" closed w534
wledger "338_tg.sql|$(blob_file TG)|$(ts 136)"
DLR_TAG_HEX=aaaaaaaaaaaaaaaa,bbbbbbbbbbbbbbbb run_writer --pr 534 --execute; r1=$rc
t_ok=no
grep -qxF 'DO $dlr_o_bbbbbbbbbbbbbbbb$ BEGIN EXECUTE $dlr_i_bbbbbbbbbbbbbbbb$' "$PAYLOAD" && ! grep -qF 'EXECUTE $dlr_i_aaaaaaaaaaaaaaaa$' "$PAYLOAD" && t_ok=yes
gh_reset; pr_json 534 "" closed w534
DLR_TAG_HEX=aaaaaaaaaaaaaaaa run_writer --pr 534 --execute
if [[ "$r1" == "0" && "$t_ok" == "yes" && "$rc" == "2" ]] && zero_writes && has "no random dollar-quote tag absent from a down body"; then
  pass "a body can never close the quote that carries it"
else
  fail "tags: first=$r1 used-b=$t_ok second=$rc out=$out"
fi

echo "G3-seams: DLR_GUARD, DLR_MUTEX or DLR_TAG_HEX under GITHUB_ACTIONS=true -> rc 2 before any lookup"
CASES=$((CASES + 1))
gh_reset; pr_json 501 "" closed w501
W_GHA=1 W_MUTEX="" run_writer --pr 501; r1=$rc; o1=$out
W_GHA=1 W_GUARD="" run_writer --pr 501; r2=$rc
W_GHA=1 W_GUARD="" W_MUTEX="" DLR_TAG_HEX=aaaaaaaaaaaaaaaa run_writer --pr 501; r3=$rc
if [[ "$r1$r2$r3" == "222" && ! -s "$CALLLOG" ]] && grep -qF 'are test-only overrides and are refused in GitHub Actions' <<<"$o1"; then
  pass "a test seam cannot redirect the writer in CI"
else
  fail "seams: guard=$r1 mutex=$r2 tag=$r3 out=[$o1] log=[$(cat "$CALLLOG")]"
fi

echo "G3-own-tree: without DLR_MUTEX the mutex comes from the writer's OWN tree (<tree>/scripts/), never from --repo"
CASES=$((CASES + 1))
LAYOUT="$tmp/layout"
mkdir -p "$LAYOUT/apps/web-platform/scripts" "$LAYOUT/scripts"
cp "$WRITER_SRC" "$LAYOUT/apps/web-platform/scripts/dev-ledger-reconcile.sh"
cp "$GUARD" "$LAYOUT/apps/web-platform/scripts/dev-ledger-parity.sh"
cp "$FAKE_MUTEX" "$LAYOUT/scripts/dev-suite-mutex.sh"
gh_reset; pr_json 501 "" closed w501
wledger "301_wa.sql|$WA|$(ts 10)" "302_wb.sql|$WB|$(ts 20)"
W_WRITER="$LAYOUT/apps/web-platform/scripts/dev-ledger-reconcile.sh" W_GUARD="" W_MUTEX="" run_writer --pr 501 --execute
if [[ "$rc" == "0" && ! -e "$WREPO/scripts/dev-suite-mutex.sh" ]] && one_unit && [[ "$(n_log '^mutex acquire$')" == "1" ]]; then
  pass "the writer, the guard and the mutex come from one tree"
else
  fail "expected the own-tree mutex; got rc=$rc out=$out log=[$(cat "$CALLLOG")]"
fi

echo "G3-release-filter: the mutex's ::warning:: HOLDER_LOST line on release reaches the log"
CASES=$((CASES + 1))
gh_reset; pr_json 501 "" closed w501
DLR_FAKE_MUTEX_MODE=contended run_writer --pr 501 --execute
if grep -qxF '::warning::DEV_SUITE_MUTEX_HOLDER_LOST pid=unknown exited -- holder died before release; the critical section may have run unserialized' <<<"$out"; then
  pass "an unserialized-section signal is never filtered out"
else
  fail "HOLDER_LOST line missing: $out"
fi

# ---------- PR 535: later-row and transaction-control in one PR ----------
pr_start w535
pr_commit 'w535' 339_pa.sql="PA" 339_pa.down.sql="DROP TABLE IF EXISTS pa CASCADE;" 340_pb.sql="PB" 340_pb.down.sql=$'DROP TABLE IF EXISTS pb;\nCOMMIT;\nSELECT 1;'
pr_publish 535 w535
echo "G3-priority: the first row in execution order is later-row, the second transaction-control -> reason=transaction-control (documented priority, not encounter order)"
CASES=$((CASES + 1))
gh_reset; pr_json 535 "" closed w535
wledger "339_pa.sql|$(blob_file PA)|$(ts 141)" "340_pb.sql|$(blob_file PB)|$(ts 140)" "396_foreign3.sql|$(blob_file F3)|$(ts 142)"
run_writer --pr 535 --execute
if [[ "$rc" == "1" ]] && zero_writes && grep -qE '^ledger-discard: refused \(pr=535 .* reason=transaction-control\)$' <<<"$out"; then
  pass "the refusal reason is deterministic"
else
  fail "expected reason=transaction-control; got rc=$rc out=$out"
fi

# ---------- PR 536: a plain destructive down ----------
pr_start w536
pr_commit 'w536' 341_ds.sql="DS" 341_ds.down.sql="DROP TABLE IF EXISTS ds;"
pr_publish 536 w536
echo "G3-destructive: a plain DROP while a MAIN migration was applied later -> refused destructive-superseded, zero writes"
CASES=$((CASES + 1))
gh_reset; pr_json 536 "" closed w536
wledger_raw "001_a.sql|$(blob_of A)|20260101000000000001" "002_b.sql|$(blob_of B)|20260101000000000002" \
  "130_y.sql|$(blob_of Y)|$(ts 151)" "131_x.sql|$(blob_of X)|20260101000000000004" "341_ds.sql|$(blob_file DS)|$(ts 150)"
run_writer --pr 536 --execute
if [[ "$rc" == "1" ]] && zero_writes && grep -qE '^ledger-discard: refused \(pr=536 .* reason=destructive-superseded\)$' <<<"$out" \
  && grep -qxF "later-row 130_y.sql $(ts 151)" <<<"$out"; then
  pass "a main migration that may supersede the dropped object blocks the close path (CTO ruling 2)"
else
  fail "expected destructive-superseded; got rc=$rc out=$out"
fi

echo "G3-destructive-ok: the same DROP with only a FOREIGN later row -> written; with a main later row + --allow-later-rows -> written"
CASES=$((CASES + 1))
gh_reset; pr_json 536 "" closed w536
run_writer --pr 536 --execute --allow-later-rows; r1=$rc; u1=no; one_unit && u1=yes
gh_reset; pr_json 536 "" closed w536
wledger "341_ds.sql|$(blob_file DS)|$(ts 150)" "395_foreign4.sql|$(blob_file F4)|$(ts 152)"
run_writer --pr 536 --execute
if [[ "$r1" == "0" && "$u1" == "yes" && "$rc" == "0" ]] && one_unit && grep -qxF 'DROP TABLE IF EXISTS ds;' "$PAYLOAD"; then
  pass "no over-refusal, and the reviewed override is honoured"
else
  fail "expected written twice; got override=$r1/$u1 foreign=$rc out=$out"
fi

echo "G3-suspicious-later: an unparseable ledger row counts as a later row -> a CASCADE down is refused"
CASES=$((CASES + 1))
gh_reset; pr_json 509 "" closed w509
wledger "316_wl.sql|$WL|$(ts 80)" "not a ledger row"
run_writer --pr 509 --execute
if [[ "$rc" == "1" ]] && zero_writes && grep -qxF 'later-row <unprintable-row> undated' <<<"$out" && grep -qF 'reason=later-row)' <<<"$out"; then
  pass "a row the writer cannot read is assumed to be later"
else
  fail "expected later-row refusal; got rc=$rc out=$out"
fi

echo "G3-dry-residue: a DRY RUN of a ledger-only row prints no 'objects … stay on dev' residue warning"
CASES=$((CASES + 1))
gh_reset; pr_json 520 "" closed w520
wledger "328_ww2.sql|$(blob_file WW2)|$(ts 118)"
run_writer --pr 520
if [[ "$rc" == "0" ]] && ! has "objects its body created stay on dev" && grep -qxF "would-discard 328_ww2.sql $(blob_file WW2) down=none" <<<"$out"; then
  pass "residue is reported only after an executed discard"
else
  fail "residue text on a dry run: rc=$rc out=$out"
fi

echo "G3-bot-actor: a [bot] triggering actor is a valid login (dry run)"
CASES=$((CASES + 1))
gh_reset; pr_json 501 "" closed w501
wledger "301_wa.sql|$WA|$(ts 10)" "302_wb.sql|$WB|$(ts 20)"
run_writer --pr 501 --actor 'dependabot[bot]'
if [[ "$rc" == "0" ]] && grep -q '^ledger-discard: dry-run (pr=501 ' <<<"$out"; then
  pass "bot re-runs are judged, not rejected as config"
else
  fail "expected a dry run; got rc=$rc out=$out"
fi

echo "G3-xtrace: the writer refuses to run under bash -x even with no credential in the environment (exit 78)"
CASES=$((CASES + 1))
set +e
env -u GH_TOKEN -u GITHUB_TOKEN -u DOPPLER_TOKEN -u DATABASE_URL -u DATABASE_URL_POOLER bash -x "$WBIN/dev-ledger-reconcile.sh" --help >/dev/null 2>&1; xr=$?
set -e
if [[ "$xr" == "78" ]]; then pass "unconditional refusal"; else fail "expected 78; got $xr"; fi

echo "G3-unit-backslash: the ASSEMBLED unit is checked for a backslash after assembly and before psql"
CASES=$((CASES + 1))
ub=$(awk '/^POST_START=/ { a = 1 } a && /has_backslash "\$UNIT"/ { print NR; exit }' "$WRITER_SRC")
ua=$(grep -n '^apply_discard_unit$' "$WRITER_SRC" | cut -d: -f1) || true
if [[ -n "$ub" && -n "$ua" ]] && (( ub < ua )) && sed -n "${ub},$((ub + 3))p" "$WRITER_SRC" | grep -qF 'refused backslash'; then
  pass "defense in depth on the unit itself"
else
  fail "the unit backslash check is missing or misplaced (at=$ub apply=$ua)"
fi

echo "G3-scan-table: every transaction-control / non-transactional keyword, the \$-after-identifier and high-bit bypasses, strict UTF-8"
CASES=$((CASES + 1))
SC="$tmp/scan"; rm -rf "$SC"; mkdir -p "$SC"
n=0
while IFS='|' read -r want body; do
  n=$((n + 1)); printf '%b' "$body" > "$SC/$(printf '%02d' "$n")_$want.down.sql"
done <<'TABLE'
transaction-control|DROP TABLE x;\nBEGIN;\nSELECT 1;
transaction-control|DROP TABLE x;\nSTART TRANSACTION;
transaction-control|DROP TABLE x;\nCOMMIT;\nSELECT 1;
transaction-control|DROP TABLE x;\nEND;\nSELECT 1;
transaction-control|DROP TABLE x;\nROLLBACK;
transaction-control|DROP TABLE x;\nABORT;
transaction-control|DROP TABLE x;\nSAVEPOINT s;
transaction-control|DROP TABLE x;\nRELEASE s;
transaction-control|DROP TABLE x;\nPREPARE TRANSACTION 'x';
transaction-control|DROP TABLE x;\nCALL p();
non-transactional|DROP INDEX CONCURRENTLY x;
non-transactional|VACUUM t;
non-transactional|ALTER SYSTEM SET work_mem = '1MB';
non-transactional|CREATE DATABASE d;
non-transactional|DROP DATABASE d;
non-transactional|CREATE TABLESPACE s LOCATION '/x';
non-transactional|DROP TABLESPACE s;
non-transactional|DISCARD ALL;
non-transactional|COPY t FROM STDIN;
non-transactional|COPY t TO STDOUT;
transaction-control|CREATE TABLE a$$b (x int); COMMIT; CREATE TABLE c$$d (y int);
transaction-control|CREATE TABLE x\xe2\x82\xac$$ (a int); COMMIT; SELECT 1 AS y\xe2\x82\xac$$;
clean|SELECT $\xc3\xa9$ COMMIT $\xc3\xa9$;
unparseable|SELECT '\xff\xfe';
destructive|ALTER TABLE t DROP COLUMN c;
destructive|TRUNCATE t;
destructive|DELETE FROM t;
destructive|UPDATE t SET a = 1;
TABLE
mapfile -t SCF < <(find "$SC" -name '*.down.sql' | LC_ALL=C sort)
set +e
sc_out=$(bash "$WBIN/dev-ledger-reconcile.sh" --scan-down "${SCF[@]}" 2>&1); sc_rc=$?
set -e
sc_bad=""
while IFS=$'\t' read -r fname cls; do
  want="${fname#*_}"; want="${want%.down.sql}"
  case "$want" in
    clean) [[ "$cls" == "-" ]] || sc_bad+=" $fname=$cls" ;;
    *) [[ ",$cls," == *",$want,"* ]] || sc_bad+=" $fname=$cls" ;;
  esac
done <<<"$sc_out"
if [[ "$sc_rc" == "0" && "$(grep -c . <<<"$sc_out")" == "$n" && -z "$sc_bad" ]]; then
  pass "each of $n keyword/bypass rows is classified as pinned"
else
  fail "scan table: rc=$sc_rc misclassified:$sc_bad out=[$sc_out]"
fi

# psql_sites <file> — every line where psql appears as a WORD outside quotes and
# comments (a message such as "(psql rc=2)" is quoted, so it is not a site), minus
# `command -v psql`. Printed as the original line.
psql_sites() {
  python3 - "$1" <<'PY2'
import re, sys
for raw in open(sys.argv[1], encoding="utf-8").read().split("\n"):
    if raw.lstrip().startswith("#"):
        continue
    code = re.sub(r"'[^']*'", "''", re.sub(r'"(?:[^"\\]|\\.)*"', '""', raw))
    code = re.sub(r"\s#.*$", "", code)
    if re.search(r"(?<![\w./-])psql(?![\w.-])", code) and not re.search(r"command -v psql", code):
        print(raw.strip())
PY2
}

echo "G3-M12: the guard's only psql call site is the fixed -c \"\$LEDGER_SQL\" read (no write path in the guard)"
CASES=$((CASES + 1))
g_sites=$(psql_sites "$GUARD_SRC")
if [[ "$(grep -c . <<<"$g_sites" || true)" == "1" ]] && grep -qF -- '-c "$LEDGER_SQL"' <<<"$g_sites" && ! grep -qE -- '(^|[[:space:]])(-f|--file)([[:space:]]|=)' <<<"$g_sites"; then
  pass "the guard stays read-only"
else
  fail "guard psql call sites: [$g_sites]"
fi

echo "G3-sites: the writer has exactly TWO psql call sites (the fixed ledger -c read and the one -f unit); the workflow has none"
CASES=$((CASES + 1))
w_sites=$(psql_sites "$WRITER_SRC")
y_psql=$(python3 - "$REPO_ROOT/.github/workflows/dev-ledger-reconcile.yml" <<'PY2'
import re, sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
bad, doppler = [], []
for jn, job in (doc.get("jobs") or {}).items():
    for st in job.get("steps") or []:
        for line in str(st.get("run", "")).split("\n"):
            code = line.split(" #")[0]
            if re.search(r"(?<![\w./-])psql(?![\w.-])", code) and not line.lstrip().startswith("#"):
                bad.append(f"psql in {jn}: {line.strip()}")
            if re.search(r"\bdoppler\s+run\b", code):
                doppler.append((jn, line.strip()))
if len(doppler) != 1 or doppler[0][0] != "reconcile" or "--" not in doppler[0][1]:
    bad.append(f"doppler run sites: {doppler}")
run = [st for st in doc["jobs"]["reconcile"]["steps"] if st.get("id") == "reconcile"][0]["run"]
if not re.search(r"doppler run -p soleur -c dev_scheduled -- \\\n\s*bash apps/web-platform/scripts/dev-ledger-reconcile\.sh \"\$\{args\[@\]\}\"", run):
    bad.append("the one doppler run does not invoke the writer")
print("\n".join(bad))
PY2
)
if [[ "$(grep -c . <<<"$w_sites" || true)" == "2" ]] && grep -qF -- '-c "$DLR_LEDGER_SQL"' <<<"$w_sites" \
  && grep -qF -- '--single-transaction -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f "$UNIT"' <<<"$w_sites" \
  && [[ "$(grep -cE -- '(^|[[:space:]])(-f|--file)([[:space:]]|=)' <<<"$w_sites" || true)" == "1" ]] && [[ -z "$y_psql" ]]; then
  pass "one read site, one write site, and the workflow reaches the database only through the writer"
else
  fail "psql sites: writer=[$w_sites] workflow=[$y_psql]"
fi

echo "G3-M13a: sourcing the guard (from inside a function) with DLP_AS_LIBRARY=1 prints nothing, does not exit, and leaves its arrays global"
CASES=$((CASES + 1))
set +e
lib_out=$(bash -c 'load() { DLP_AS_LIBRARY=1; source "$1"; }; load "$1"; echo "after-source"; declare -p OWN_ON_BASE OWN_EVER >/dev/null 2>&1 && echo arrays-global' _ "$GUARD" 2>&1)
lib_rc=$?
set -e
if [[ "$lib_rc" == "0" && "$lib_out" == "after-source"$'\n'"arrays-global" ]]; then
  pass "library mode runs no dispatch"
else
  fail "library mode leaked: rc=$lib_rc out=[$lib_out]"
fi

echo "G3-M13b: executing the guard with DLP_AS_LIBRARY=1 -> rc 2 and the error line"
CASES=$((CASES + 1))
set +e
lib_out=$(DLP_AS_LIBRARY=1 bash "$GUARD" classify-missing --base-branch main --repo "$WORK" </dev/null 2>&1)
lib_rc=$?
set -e
if [[ "$lib_rc" == "2" ]] && grep -qxF '::error::dev-ledger-parity: DLP_AS_LIBRARY is set on a direct run' <<<"$lib_out"; then
  pass "a misconfigured direct run is loud"
else
  fail "expected rc=2 + error; got rc=$lib_rc out=[$lib_out]"
fi

# ----------------------------------------------------------------------
echo "G3-refusal-sets: the stripped-view refusal step over every .down.sql on main matches the pinned sets"
CASES=$((CASES + 1))
DOWN_DIR="$REPO_ROOT/$MDIR"
mapfile -t DOWNS < <(find "$DOWN_DIR" -maxdepth 1 -name '*.down.sql' | LC_ALL=C sort)
set +e
scan=$(bash "$WBIN/dev-ledger-reconcile.sh" --scan-down "${DOWNS[@]}" 2>&1)
scan_rc=$?
set -e
set_of() { awk -F'\t' -v c="$1" '{ n = split($2, a, ","); for (i = 1; i <= n; i++) if (a[i] == c) print $1 }' <<<"$scan" | LC_ALL=C sort | tr '\n' ' '; }
got_txn=$(set_of transaction-control); got_nontx=$(set_of non-transactional); got_later=$(set_of later-row-sensitive)
got_bs=$(set_of backslash); got_unp=$(set_of unparseable)
# The pinned sets (the stored value of this guard). Measured 2026-09-23 over 95 files:
# every top-level BEGIN;/COMMIT; on main is ONE wrapping pair, which the writer
# normalizes away, so no file is transaction-control; 132_drop_unused_indexes.down.sql
# mentions CONCURRENTLY only in a comment, so no file is non-transactional; the
# later-row-sensitive set is every CASCADE / CREATE OR REPLACE / policy / grant /
# ALTER FUNCTION down. A change here must be a reviewed diff of these literals.
PIN_TXN=""
PIN_NONTX=""
PIN_LATER=$(tr '\n' ' ' <<'LIST'
051_action_class_widening_and_action_sends.down.sql
053_organizations_and_workspace_members.down.sql
058_workspace_member_attestations.down.sql
059_workspace_keyed_rls_sweep.down.sql
060_current_organization_jwt_hook.down.sql
061_byok_audit_workspace_id_rpcs.down.sql
062_workspace_member_removals_and_remove_rpc_update.down.sql
063_post_workspace_rpc_repair.down.sql
064_anonymise_scope_grants_workspace_id_and_member_actions_grant.down.sql
064_byok_delegations.down.sql
065_art17_cascade_deadlock_repair.down.sql
066_audit_byok_use_art17_carveout.down.sql
068_attachments_workspace_shared.down.sql
068_jti_deny_rls_predicate_and_revoke_rpc.down.sql
069_jti_deny_grant_restore.down.sql
071_ux_audit_artifacts_bucket.down.sql
072_workspace_member_actions_workspace_id_set_null.down.sql
075_conversation_visibility.down.sql
075_transfer_workspace_ownership.down.sql
076_invitation_invitee_identity_check.down.sql
076_workspace_activity.down.sql
077_kb_files_metadata.down.sql
079_workspace_repo_ownership_schema.down.sql
081_anonymise_null_workspace_installation.down.sql
083_byok_delegation_consent_gate.down.sql
084_byok_delegation_withdrawals.down.sql
085_revoke_workspace_invitation.down.sql
087_worm_bypass_privilege_independence.down.sql
088_worm_bypass_non_erasure_rpcs.down.sql
089_template_auto_revoke_carveout.down.sql
090_fix_accept_invitation_attestation_overwrite.down.sql
091_rename_organization_and_default_names.down.sql
092_transfer_ownership_caller_override.down.sql
093_acquire_slot_workspace_id.down.sql
094_member_rpc_caller_override_and_byok_cap_update.down.sql
098_workspace_logos.down.sql
110_workspace_repo_error_and_comember_reconcile.down.sql
111_email_triage_items_workspace_shared.down.sql
112_drop_legacy_users_repo_columns.down.sql
113_set_repo_status_writes_workspace_repo_error.down.sql
114_disk_io_top_wal_statements.down.sql
120_routine_run_progress.down.sql
121_byok_cap_trip_from_found.down.sql
126_beta_crm.down.sql
127_beta_crm_access_log.down.sql
128_revoke_definer_rpc_residual_grants.down.sql
129_rls_write_check_workspace_member.down.sql
130_authorize_template_grant_ownership_guard.down.sql
133_heartbeat_threshold_backoff.down.sql
137_byok_cap_breach_audit_row.down.sql
LIST
)
if [[ "$scan_rc" == "0" && "${#DOWNS[@]}" -ge 95 && "$(grep -c . <<<"$scan")" == "${#DOWNS[@]}" \
  && "$got_txn" == "$PIN_TXN" && "$got_nontx" == "$PIN_NONTX" && "$got_later" == "$PIN_LATER" && -z "$got_bs" && -z "$got_unp" ]]; then
  pass "refusal sets over ${#DOWNS[@]} down files unchanged"
else
  fail "refusal sets drifted (update the pinned literal in review): rc=$scan_rc files=${#DOWNS[@]}
    txn=[$got_txn]
    nontx=[$got_nontx]
    later=[$got_later]
    backslash=[$got_bs] unparseable=[$got_unp]"
fi

echo "== Guard 4: .github/workflows/dev-ledger-reconcile.yml wiring =="

RW="$REPO_ROOT/.github/workflows/dev-ledger-reconcile.yml"
# rw_static <workflow> <check> — one line per broken property of that check, read from
# the PARSED YAML (a comment can never satisfy or trip a check). Any check on a file
# with zero jobs or zero steps reports "0 steps parsed".
rw_static() {
  python3 - "$1" "$2" "$GUARD_SRC" <<'PY'
import re, sys, yaml
try:
    doc = yaml.safe_load(open(sys.argv[1])) or {}
except Exception as e:
    print(f"unparseable: {type(e).__name__}"); sys.exit(0)
check, bad = sys.argv[2], []
jobs = doc.get("jobs") or {}
steps = [(jn, st) for jn, j in jobs.items() for st in ((j or {}).get("steps") or [])]
if not jobs or not steps:
    print("0 steps parsed"); sys.exit(0)
def strings(node):
    if isinstance(node, dict):
        for k, v in node.items():
            yield from strings(k); yield from strings(v)
    elif isinstance(node, list):
        for v in node: yield from strings(v)
    elif isinstance(node, str):
        yield node
runs = [st.get("run", "") for _, st in steps if "run" in st]
job = jobs.get("reconcile") or {}
if check == "checkout":
    cos = [st for _, st in steps if str(st.get("uses", "")).startswith("actions/checkout@")]
    if not cos: bad.append("no checkout step")
    for st in cos:
        w = st.get("with") or {}
        if "ref" in w: bad.append("a checkout step carries a ref: key")
        if w.get("persist-credentials") is not False: bad.append("checkout persists credentials")
elif check == "secrets":
    # Allow-list: every `secrets` token in the parsed YAML must be exactly
    # secrets.DOPPLER_TOKEN_DEV_SCHEDULED (toJSON(secrets), secrets[...] and any other
    # name are rejected), and only the reconcile job may hold it.
    def exprs(node):
        # Every expression: the inside of each ${{ }}, plus every bare if: value.
        if isinstance(node, dict):
            for k, v in node.items():
                if k == "if" and isinstance(v, str): yield v
                yield from exprs(v)
        elif isinstance(node, list):
            for v in node: yield from exprs(v)
        elif isinstance(node, str):
            yield from re.findall(r"\$\{\{(.*?)\}\}", node, re.S)
    for e in exprs(doc):
        for m in re.finditer(r"\bsecrets\b(\.[A-Za-z0-9_]+)?", e):
            if m.group(1) != ".DOPPLER_TOKEN_DEV_SCHEDULED": bad.append(f"secrets reference {m.group(0)!r} is not the dev Doppler token")
    for s in strings(doc):
        if re.search(r"DOPPLER_TOKEN_PRD", s): bad.append("a prd Doppler token is named")
    for jn, j in jobs.items():
        if jn != "reconcile" and any(re.search(r"\bsecrets\b", e) for e in exprs(j)): bad.append(f"job {jn} references a secret")
    for r in runs:
        for m in re.finditer(r"doppler\b[^\n]*?(?:\s-c|\s--config)[\s=]+([A-Za-z0-9_]+)", r):
            if m.group(1) != "dev_scheduled": bad.append(f"doppler config {m.group(1)}")
        if re.search(r"(?:\s-c|--config)[\s=]+prd", r): bad.append("-c prd in a run body")
elif check == "ifclause":
    cond = " ".join(str(job.get("if", "")).split())
    for want in ("github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'",
                 "github.event_name == 'pull_request_target'",
                 "github.event.pull_request.merged == false",
                 "github.event.pull_request.head.repo.full_name == github.repository"):
        if want not in cond: bad.append(f"job if lacks: {want}")
    # Exact (whitespace-normalised) equality: an added `|| true` keeps every clause above.
    exact = ("(github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main') || "
             "(github.event_name == 'pull_request_target' && github.event.pull_request.merged == false && "
             "github.event.pull_request.head.repo.full_name == github.repository)")
    if cond != exact: bad.append(f"job if is not exactly the pinned expression: {cond!r}")
    rep_if = " ".join(str((jobs.get("report") or {}).get("if", "")).split())
    if rep_if != "always() && needs.reconcile.result != 'skipped'": bad.append(f"report job if drifted: {rep_if!r}")
    if (jobs.get("report") or {}).get("needs") != "reconcile": bad.append("report job does not need reconcile")
elif check == "stepenv":
    rs = [st for st in (job.get("steps") or []) if st.get("id") == "reconcile"]
    env = (rs[0].get("env") or {}) if rs else {}
    want = {"EXECUTE": "${{ github.event_name == 'pull_request_target' || inputs.execute }}",
            "ALLOW_LATER_ROWS": "${{ github.event_name == 'workflow_dispatch' && inputs.allow_later_rows }}",
            "ACTOR": "${{ github.triggering_actor }}",
            "PR": "${{ github.event.pull_request.number || inputs.pr }}",
            "EVENT_NAME": "${{ github.event_name }}",
            "GH_TOKEN": "${{ github.token }}",
            "DOPPLER_TOKEN": "${{ secrets.DOPPLER_TOKEN_DEV_SCHEDULED }}"}
    for k, v in want.items():
        if env.get(k) != v: bad.append(f"reconcile step env {k} is {env.get(k)!r}")
    if set(env) - set(want): bad.append(f"reconcile step env gained {sorted(set(env) - set(want))}")
    for st in ((jobs.get("report") or {}).get("steps") or []):
        e = st.get("env") or {}
        if e.get("PR") != "${{ github.event.pull_request.number || inputs.pr }}": bad.append(f"report step {st.get('id')} PR is {e.get('PR')!r}")
        if "ACTOR" in e and e["ACTOR"] != "${{ github.triggering_actor }}": bad.append(f"report step {st.get('id')} ACTOR is {e['ACTOR']!r}")
elif check == "nocheckout":
    cos = [st for _, st in steps if str(st.get("uses", "")).startswith("actions/checkout@")]
    if len(cos) != 1: bad.append(f"expected exactly one checkout step, found {len(cos)}")
    deny = re.compile(r"\bgit\s+(checkout|switch|worktree)\b|FETCH_HEAD|refs/pull/|\bgh\s+pr\s+checkout\b|github\.event\.pull_request\.head\.(sha|ref)")
    for jn, st in steps:
        for k, v in (("run", st.get("run", "")), ("with", str(st.get("with") or {}))):
            if deny.search(str(v)): bad.append(f"{jn}/{st.get('id') or st.get('name')} {k} can reach PR-head code: {deny.search(str(v)).group(0)!r}")
    rj = jobs.get("report") or {}
    for st in rj.get("steps") or []:
        if "uses" in st: bad.append("the report job runs an action")
        if re.search(r"\bbash\s+\S+\.sh\b|apps/|scripts/", str(st.get("run", ""))): bad.append("the report job runs repository code")
elif check == "issuetitle":
    guard = open(sys.argv[3]).read()
    lab = re.search(r'^readonly RECONCILE_ISSUE_LABEL="([^"]+)"$', guard, re.M)
    pre = re.search(r'^readonly RECONCILE_ISSUE_PREFIX="([^"]+)"$', guard, re.M)
    iss = [st for st in ((jobs.get("report") or {}).get("steps") or []) if st.get("id") == "issue"]
    run = iss[0].get("run", "") if iss else ""
    if not lab or not pre: bad.append("the guard lost RECONCILE_ISSUE_LABEL/PREFIX")
    else:
        if f'label="{lab.group(1)}"' not in run: bad.append("the issue step's label is not the classifier's")
        if f'title="{pre.group(1)}$PR ' not in run: bad.append("the issue title does not start with the classifier's prefix + the PR number + a space")
        if 'labels="$label,action-required"' not in run or '-f "labels[]=$label" -f "labels[]=action-required"' not in run:
            bad.append("the issue step does not list/create with the label AND action-required")
elif check == "injection":
    for r in runs:
        if "${{" in r: bad.append("an expression is interpolated into a run: body")
elif check == "issueif":
    iss = [st for _, st in steps if st.get("id") == "issue"]
    if len(iss) != 1: bad.append(f"expected one step id: issue, got {len(iss)}")
    else:
        cond = " ".join(str(iss[0].get("if", "")).split())
        for want in ("always()", "github.event_name == 'pull_request_target'",
                     "github.event_name == 'workflow_dispatch' && inputs.execute",
                     "needs.reconcile.result != 'success'", "needs.reconcile.outputs.unreachable != '0'",
                     "needs.reconcile.outputs.verb == 'executed' && needs.reconcile.outputs.ledger_only != '0'"):
            if want not in cond: bad.append(f"issue step if lacks: {want}")
    cm = [st for _, st in steps if st.get("id") == "comment"]
    if len(cm) != 1 or "needs.reconcile.outputs.pr_ok == 'true'" not in " ".join(str(cm[0].get("if", "")).split()):
        bad.append("the comment step is not gated on pr_ok")
elif check == "triggers":
    on = doc.get("on", doc.get(True)) or {}
    wd = (on.get("workflow_dispatch") or {}).get("inputs") or {}
    if (wd.get("pr") or {}).get("required") is not True: bad.append("input pr is not required")
    for k in ("execute", "allow_later_rows"):
        i = wd.get(k) or {}
        if i.get("type") != "boolean" or i.get("default") is not False: bad.append(f"input {k} is not a boolean defaulting to false")
    prt = on.get("pull_request_target") or {}
    if prt.get("types") != ["closed"] or prt.get("branches") != ["main"]: bad.append("pull_request_target is not types [closed] on main")
    if set(on) - {"workflow_dispatch", "pull_request_target"}: bad.append(f"extra triggers {sorted(set(on))}")
    if doc.get("permissions") != {"contents": "read"}: bad.append("top-level permissions are not contents: read")
    if job.get("permissions") != {"contents": "read", "pull-requests": "read"}: bad.append("reconcile job permissions drifted (it holds the dev secret: read-only)")
    if (jobs.get("report") or {}).get("permissions") != {"issues": "write", "pull-requests": "write"}: bad.append("report job permissions drifted")
    if set(jobs) != {"reconcile", "report"}: bad.append(f"jobs are {sorted(jobs)}")
    if job.get("timeout-minutes") != 25: bad.append(f"reconcile timeout-minutes is {job.get('timeout-minutes')!r} (25)")
    if "concurrency" in doc or "concurrency" in job: bad.append("a concurrency group appeared")
    for _, st in steps:
        if "continue-on-error" in st: bad.append("a continue-on-error step appeared")
else:
    bad.append(f"unknown check {check}")
print("\n".join(bad))
PY
}
rw_mutant() { file_mutant "$RW" "$tmp/rw-mut.yml" "$1"; }

# ----------------------------------------------------------------------
echo "G4-0: the real workflow satisfies every static check (checkout, secrets, if, injection, issue if, triggers)"
CASES=$((CASES + 1))
rw_all=""
for c in checkout secrets ifclause injection issueif triggers stepenv nocheckout issuetitle; do rw_all+=$(rw_static "$RW" "$c"); done
if [[ -z "$rw_all" ]]; then pass "wiring intact"; else fail "reconcile workflow wiring broken: $rw_all"; fi

echo "G4-M1: the checkout gains a ref: key -> RED"
CASES=$((CASES + 1))
rw_mutant '
t = "          persist-credentials: false\n"
assert s.count(t) == 1
s = s.replace(t, t + "          ref: ${{ github.event.pull_request.head.sha }}\n", 1)
'
if [[ -n "$(rw_static "$tmp/rw-mut.yml" checkout)" ]]; then pass "a PR-head checkout is seen"; else fail "a ref: on checkout went unseen"; fi

echo "G4-M2: a prd Doppler token or -c prd appears -> RED (each)"
CASES=$((CASES + 1))
rw_mutant '
t = "secrets.DOPPLER_TOKEN_DEV_SCHEDULED }}"
assert s.count(t) >= 1
s = s.replace(t, "secrets.DOPPLER_TOKEN_PRD }}", 1)
'
r1=$(rw_static "$tmp/rw-mut.yml" secrets)
rw_mutant '
t = "doppler run -p soleur -c dev_scheduled --"
assert s.count(t) == 1
s = s.replace(t, "doppler run -p soleur -c prd --", 1)
'
r2=$(rw_static "$tmp/rw-mut.yml" secrets)
if [[ -n "$r1" && -n "$r2" ]]; then pass "the secret scope is dev only"; else fail "prd scope went unseen: [$r1] [$r2]"; fi

echo "G4-M3: the fork clause is dropped from the job if: -> RED"
CASES=$((CASES + 1))
rw_mutant '
t = " && github.event.pull_request.head.repo.full_name == github.repository"
assert s.count(t) == 1
s = s.replace(t, "", 1)
'
if [[ -n "$(rw_static "$tmp/rw-mut.yml" ifclause)" ]]; then pass "fork PRs stay excluded"; else fail "the fork clause drop went unseen"; fi

echo "G4-M4: the dispatch clause loses github.ref == refs/heads/main -> RED"
CASES=$((CASES + 1))
rw_mutant '
t = " && github.ref == '"'"'refs/heads/main'"'"'"
assert s.count(t) == 1
s = s.replace(t, "", 1)
'
if [[ -n "$(rw_static "$tmp/rw-mut.yml" ifclause)" ]]; then pass "dispatch runs only main's copy"; else fail "a dispatch off main went unseen"; fi

echo "G4-M5: \${{ inputs.* }} or \${{ github.event.* }} inside a run: body -> RED (each)"
CASES=$((CASES + 1))
rw_mutant '
t = "          set -uo pipefail\n"
assert s.count(t) >= 1
s = s.replace(t, t + "          echo \"pr=${{ inputs.pr }}\"\n", 1)
'
r1=$(rw_static "$tmp/rw-mut.yml" injection)
rw_mutant '
t = "          set -uo pipefail\n"
assert s.count(t) >= 1
i = s.rindex(t)
s = s[:i] + t + "          echo \"${{ github.event.pull_request.title }}\"\n" + s[i + len(t):]
'
r2=$(rw_static "$tmp/rw-mut.yml" injection)
if [[ -n "$r1" && -n "$r2" ]]; then pass "PR/input text reaches run: bodies only via env"; else fail "interpolation went unseen: [$r1] [$r2]"; fi

echo "G4-M7: the issue step's if: loses the job-failure clause -> RED"
CASES=$((CASES + 1))
rw_mutant '
t = "(needs.reconcile.result != '"'"'success'"'"' || "
assert s.count(t) == 1
s = s.replace(t, "(", 1)
'
if [[ -n "$(rw_static "$tmp/rw-mut.yml" issueif)" ]]; then pass "a failure before the reconcile step still files the issue"; else fail "the narrowed issue if: went unseen"; fi

echo "G4-trig: triggers, input defaults, permissions; a dispatch input defaulting to execute -> RED"
CASES=$((CASES + 1))
rw_mutant '
import re
m = re.search(r"(      execute:\n(?:        .*\n)*?        default: )false\n", s)
assert m
s = s[:m.start()] + m.group(1) + "true\n" + s[m.end():]
'
if [[ -n "$(rw_static "$tmp/rw-mut.yml" triggers)" ]]; then pass "a dispatch never defaults to a write"; else fail "execute defaulting to true went unseen"; fi

echo "G4-H1: a workflow that parses to zero steps -> every check reports '0 steps parsed'"
CASES=$((CASES + 1))
printf 'name: x\non: {workflow_dispatch: {}}\njobs: {}\n' > "$tmp/rw-empty.yml"
h_all=""
for c in checkout secrets ifclause injection issueif triggers stepenv nocheckout issuetitle; do h_all+="$(rw_static "$tmp/rw-empty.yml" "$c")|"; done
if [[ "$h_all" == "0 steps parsed|0 steps parsed|0 steps parsed|0 steps parsed|0 steps parsed|0 steps parsed|0 steps parsed|0 steps parsed|0 steps parsed|" ]]; then
  pass "an empty parse is never a clean bill"
else
  fail "empty parse passed a check: [$h_all]"
fi

echo "G4-p1: a comment mentioning ref: or -c prd does not trip any check (must-PASS)"
CASES=$((CASES + 1))
rw_mutant '
t = "jobs:\n"
assert s.count(t) == 1
s = s.replace(t, "# ref: refs/pull/1/head -- doppler run -c prd -- secrets.DOPPLER_TOKEN_PRD\n" + t, 1)
'
p_all=""
for c in checkout secrets ifclause injection issueif triggers stepenv nocheckout issuetitle; do p_all+=$(rw_static "$tmp/rw-mut.yml" "$c"); done
if [[ -z "$p_all" ]]; then pass "comments are not wiring"; else fail "a comment tripped a check: $p_all"; fi

echo "G4-K: the reconcile step's EXECUTE (or ALLOW_LATER_ROWS) expression is rewired -> RED (each)"
CASES=$((CASES + 1))
rw_mutant '
t = "EXECUTE: ${{ github.event_name == '"'"'pull_request_target'"'"' || inputs.execute }}"
assert s.count(t) == 1
s = s.replace(t, "EXECUTE: ${{ true }}", 1)
'
r1=$(rw_static "$tmp/rw-mut.yml" stepenv)
rw_mutant '
t = "ALLOW_LATER_ROWS: ${{ github.event_name == '"'"'workflow_dispatch'"'"' && inputs.allow_later_rows }}"
assert s.count(t) == 1
s = s.replace(t, "ALLOW_LATER_ROWS: ${{ inputs.allow_later_rows }}", 1)
'
r2=$(rw_static "$tmp/rw-mut.yml" stepenv)
if [[ -n "$r1" && -n "$r2" ]]; then pass "the write/override switches are pinned"; else fail "EXECUTE/ALLOW_LATER_ROWS rewiring unseen: [$r1] [$r2]"; fi

echo "G4-L: ACTOR becomes github.actor (a re-run would be judged as the original actor) -> RED"
CASES=$((CASES + 1))
rw_mutant '
t = "ACTOR: ${{ github.triggering_actor }}"
assert s.count(t) >= 1
s = s.replace(t, "ACTOR: ${{ github.actor }}", 1)
'
if [[ -n "$(rw_static "$tmp/rw-mut.yml" stepenv)" ]]; then pass "the authority input is pinned"; else fail "ACTOR rewiring unseen"; fi

echo "G4-if-exact: the job if: gains '|| true' (every pinned clause still present) -> RED; the report job loses its needs/if -> RED"
CASES=$((CASES + 1))
rw_mutant '
t = "github.event.pull_request.head.repo.full_name == github.repository)\n"
assert s.count(t) == 1
s = s.replace(t, "github.event.pull_request.head.repo.full_name == github.repository) || true\n", 1)
'
r1=$(rw_static "$tmp/rw-mut.yml" ifclause)
rw_mutant '
t = "    if: always() && needs.reconcile.result != '"'"'skipped'"'"'\n"
assert s.count(t) == 1
s = s.replace(t, "    if: always()\n", 1)
'
r2=$(rw_static "$tmp/rw-mut.yml" ifclause)
if [[ -n "$r1" && -n "$r2" ]]; then pass "the gates are exact"; else fail "if drift unseen: [$r1] [$r2]"; fi

echo "G4-N: a run: body fetches refs/pull/ and checks out FETCH_HEAD, or a second checkout step appears -> RED (each)"
CASES=$((CASES + 1))
rw_mutant '
t = "          out=\"$RUNNER_TEMP/ledger-discard.out\"\n"
assert s.count(t) == 1
s = s.replace(t, t + "          git fetch origin \"refs/pull/$PR/head\" && git checkout FETCH_HEAD\n", 1)
'
r1=$(rw_static "$tmp/rw-mut.yml" nocheckout)
rw_mutant '
t = "      - name: Install Doppler CLI\n"
assert s.count(t) == 1
s = s.replace(t, "      - name: Second checkout\n        uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1\n" + t, 1)
'
r2=$(rw_static "$tmp/rw-mut.yml" nocheckout)
rw_mutant '
t = "          set -uo pipefail\n          if [[ ! \"$PR\" =~ ^[1-9][0-9]{0,6}$ ]]; then\n            echo \"::warning::dev-ledger-reconcile: no valid pull request number; the audit comment was not posted\"\n"
assert s.count(t) == 1
s = s.replace(t, "          set -uo pipefail\n          bash apps/web-platform/scripts/anything.sh\n" + t[len("          set -uo pipefail\n"):], 1)
'
r3=$(rw_static "$tmp/rw-mut.yml" nocheckout)
if [[ -n "$r1" && -n "$r2" && -n "$r3" ]]; then pass "no path to PR-head code, and the write-scoped job runs no repository code"; else fail "checkout/ref/report-code mutants unseen: [$r1] [$r2] [$r3]"; fi

echo "G4-O: toJSON(secrets), secrets[...] or a secret in the report job -> RED (each)"
CASES=$((CASES + 1))
rw_mutant '
t = "          EVENT_NAME: ${{ github.event_name }}\n        run: |\n          set -uo pipefail\n          out="
assert s.count(t) == 1
s = s.replace(t, "          ALL: ${{ toJSON(secrets) }}\n" + t, 1)
'
r1=$(rw_static "$tmp/rw-mut.yml" secrets)
rw_mutant '
t = "          EVENT_NAME: ${{ github.event_name }}\n        run: |\n          set -uo pipefail\n          out="
assert s.count(t) == 1
s = s.replace(t, "          X: ${{ secrets['"'"'DOPPLER_TOKEN_DEV_SCHEDULED'"'"'] }}\n" + t, 1)
'
r2=$(rw_static "$tmp/rw-mut.yml" secrets)
rw_mutant '
t = "          KEPT_B64: ${{ needs.reconcile.outputs.kept_b64 }}\n        run: |\n          set -uo pipefail\n          if [[ ! \"$PR\" =~ ^[1-9][0-9]{0,6}$ ]]; then\n            echo \"::warning::"
assert s.count(t) == 1
s = s.replace(t, "          DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN_DEV_SCHEDULED }}\n" + t, 1)
'
r3=$(rw_static "$tmp/rw-mut.yml" secrets)
if [[ -n "$r1" && -n "$r2" && -n "$r3" ]]; then pass "the secret context is an allow-list"; else fail "secret mutants unseen: [$r1] [$r2] [$r3]"; fi

echo "G4-perm: the reconcile job (it holds the dev secret) gains issues: write -> RED"
CASES=$((CASES + 1))
rw_mutant '
t = "    permissions:\n      contents: read\n      pull-requests: read\n    outputs:"
assert s.count(t) == 1
s = s.replace(t, "    permissions:\n      contents: read\n      pull-requests: read\n      issues: write\n    outputs:", 1)
'
if [[ -n "$(rw_static "$tmp/rw-mut.yml" triggers)" ]]; then pass "write scopes stay in the secret-free job"; else fail "a write scope on the secret-holding job went unseen"; fi

echo "G4-title: the issue title or label drifts from what the classifier looks up -> RED (each)"
CASES=$((CASES + 1))
rw_mutant '
t = "title=\"[ci/dev-ledger-reconcile] PR #$PR dev ledger rows need attention\""
assert s.count(t) == 1
s = s.replace(t, "title=\"dev ledger: PR #$PR needs attention\"", 1)
'
r1=$(rw_static "$tmp/rw-mut.yml" issuetitle)
rw_mutant '
t = "label=\"ci/dev-ledger-reconcile\""
assert s.count(t) == 1
s = s.replace(t, "label=\"ci/dev-ledger\"", 1)
'
r2=$(rw_static "$tmp/rw-mut.yml" issuetitle)
if [[ -n "$r1" && -n "$r2" ]]; then pass "the issue the workflow files is the issue the probe finds"; else fail "title/label drift unseen: [$r1] [$r2]"; fi

# ---- the reconcile step, extracted and run with a stub writer that records its argv ----
RSTEP="$tmp/rw-reconcile-step.sh"
python3 - "$RW" "$RSTEP" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
got = [s for s in doc["jobs"]["reconcile"]["steps"] if s.get("id") == "reconcile"]
assert len(got) == 1, "expected exactly one step with id: reconcile"
open(sys.argv[2], "w").write(got[0]["run"])
PY
if [[ ! -s "$RSTEP" ]]; then printf 'FATAL: reconcile step extraction is empty\n' >&2; exit 1; fi
RWS="$tmp/rw-workspace"
mkdir -p "$RWS/apps/web-platform/scripts" "$tmp/rw-rt"
ARGVF="$tmp/rw-argv.txt"
cat > "$RWS/apps/web-platform/scripts/dev-ledger-reconcile.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${RW_ARGV_FILE:?}"
printf '%s' "${RW_STUB_OUT:-ledger-discard: nothing to do (pr=7)
}"
exit "${RW_STUB_RC:-0}"
SH
# run_rstep <event> <execute> <allow_later_rows> [pr] — composite-free `run:` = bash -e.
run_rstep() {
  : > "$ARGVF"; : > "$tmp/rw-gho"; : > "$tmp/rw-summary"
  set +e
  out=$(cd "$RWS" && EVENT_NAME="$1" EXECUTE="$2" ALLOW_LATER_ROWS="$3" PR="${4:-7}" ACTOR="fixture-actor" \
    DOPPLER_TOKEN=x GH_TOKEN=x RUNNER_TEMP="$tmp/rw-rt" GITHUB_WORKSPACE="$RWS" GITHUB_OUTPUT="$tmp/rw-gho" \
    GITHUB_STEP_SUMMARY="$tmp/rw-summary" RW_ARGV_FILE="$ARGVF" bash --noprofile --norc -eo pipefail "$RSTEP" 2>&1)
  rc=$?
  set -e
}
argv_has() { grep -qxF -- "$1" "$ARGVF"; }

echo "G4-M6a: the close path runs --execute --require-closed, never --allow-later-rows (even if the env says so)"
CASES=$((CASES + 1))
run_rstep pull_request_target true true
if [[ "$rc" == "0" ]] && argv_has --execute && argv_has --require-closed && ! argv_has --allow-later-rows && ! argv_has --actor \
  && argv_has --pr && argv_has 7 && argv_has --base-branch && argv_has main && argv_has "$RWS"; then
  pass "the unattended path is fixed"
else
  fail "close-path argv wrong: rc=$rc argv=[$(tr '\n' ' ' < "$ARGVF")] out=$out"
fi

echo "G4-M6b: dispatch defaults -> a dry run (no --execute); the actor is passed"
CASES=$((CASES + 1))
run_rstep workflow_dispatch false false
d_argv=$(tr '\n' ' ' < "$ARGVF")
run_rstep workflow_dispatch true true
x_argv=$(tr '\n' ' ' < "$ARGVF")
if [[ "$d_argv" != *"--execute"* && "$d_argv" != *"--require-closed"* && "$d_argv" == *"--actor fixture-actor"* \
  && "$x_argv" == *"--execute"* && "$x_argv" == *"--allow-later-rows"* ]]; then
  pass "a write is always an explicit dispatch choice"
else
  fail "dispatch argv wrong: defaults=[$d_argv] explicit=[$x_argv]"
fi

echo "G4-pr: a non-numeric PR value never reaches the writer"
CASES=$((CASES + 1))
run_rstep workflow_dispatch false false '7; rm -rf /'
if [[ "$rc" != "0" && ! -s "$ARGVF" ]]; then pass "the PR number is validated in the step"; else fail "unvalidated PR reached the writer: rc=$rc argv=[$(cat "$ARGVF")]"; fi

echo "G4-out: step outputs are parsed from the writer's summary; only validated writer lines reach the job summary"
CASES=$((CASES + 1))
RW_STUB_OUT=$'would-discard 301_wa.sql 0123456789abcdef0123456789abcdef01234567 down=none\n::stop-commands::0123456789abcdef0123456789abcdef\n    NOTICE: pwned\n::0123456789abcdef0123456789abcdef::\nnot a writer line ::error::junk\nledger-discard: dry-run (pr=7 eligible=2 down=1 ledger-only=1 later-rows=0)\n' \
  RW_STUB_RC=0 run_rstep workflow_dispatch false false
g_rc=$(sed -n 's/^rc=//p' "$tmp/rw-gho"); g_el=$(sed -n 's/^eligible=//p' "$tmp/rw-gho"); g_lo=$(sed -n 's/^ledger_only=//p' "$tmp/rw-gho")
if [[ "$rc" == "0" && "$g_rc" == "0" && "$g_el" == "2" && "$g_lo" == "1" ]] \
  && grep -qxF 'ledger-discard: dry-run (pr=7 eligible=2 down=1 ledger-only=1 later-rows=0)' "$tmp/rw-summary" \
  && grep -qxF 'would-discard 301_wa.sql 0123456789abcdef0123456789abcdef01234567 down=none' "$tmp/rw-summary" \
  && ! grep -qF 'pwned' "$tmp/rw-summary" && ! grep -qF 'junk' "$tmp/rw-summary"; then
  pass "outputs and summary come from validated writer lines only"
else
  fail "outputs/summary wrong: rc=$rc out=[$g_rc/$g_el/$g_lo] summary=[$(cat "$tmp/rw-summary")] log=$out"
fi

echo "G4-fail: a writer rc of 1 fails the step, and rc=1 reaches the outputs"
CASES=$((CASES + 1))
RW_STUB_OUT=$'ledger-discard: refused (pr=7 eligible=1 down=1 ledger-only=0 later-rows=1 reason=later-row)\n' RW_STUB_RC=1 \
  run_rstep pull_request_target true false
g_rc=$(sed -n 's/^rc=//p' "$tmp/rw-gho"); g_ref=$(sed -n 's/^refusal=//p' "$tmp/rw-gho")
if [[ "$rc" != "0" && "$g_rc" == "1" && "$g_ref" == "later-row" ]]; then
  pass "a refusal is a red step with its reason exported"
else
  fail "expected a failed step with rc=1 reason later-row; got rc=$rc outputs=[$(cat "$tmp/rw-gho")]"
fi

echo "G4-keep: skipped/held-by/unreachable lines are kept; an ::error::ledger-discard: line of unknown shape is not; outputs carry verb and unreachable"
CASES=$((CASES + 1))
RW_STUB_OUT=$'ledger-discard: held-by 301_wa.sql some-branch\nledger-discard: unreachable 302_wb.sql reason=force-pushed\n::error::ledger-discard: pwned by an unknown shape\n::error::ledger-discard: cannot measure (transient): x\nledger-discard: nothing to do (pr=7 eligible=0 down=0 ledger-only=0 later-rows=0 held-by=1 unreachable=1)\n' \
  RW_STUB_RC=0 run_rstep workflow_dispatch false false
k1=$(sed -n 's/^kept_b64=//p' "$tmp/rw-gho" | base64 -d)
g_verb=$(sed -n 's/^verb=//p' "$tmp/rw-gho"); g_un=$(sed -n 's/^unreachable=//p' "$tmp/rw-gho")
RW_STUB_OUT=$'ledger-discard: skipped (pr=7 reason=reopened)\n' RW_STUB_RC=0 run_rstep pull_request_target true false
k2=$(sed -n 's/^kept_b64=//p' "$tmp/rw-gho" | base64 -d)
if grep -qxF 'ledger-discard: held-by 301_wa.sql some-branch' <<<"$k1" && grep -qxF 'ledger-discard: unreachable 302_wb.sql reason=force-pushed' <<<"$k1" \
  && grep -qxF '::error::ledger-discard: cannot measure (transient): x' <<<"$k1" && ! grep -qF 'pwned' <<<"$k1" \
  && [[ "$g_verb" == "nothing to do" && "$g_un" == "1" ]] && grep -qxF 'ledger-discard: skipped (pr=7 reason=reopened)' <<<"$k2" \
  && grep -qxF 'verb=skipped' "$tmp/rw-gho"; then
  pass "only known shapes travel to the write-scoped job"
else
  fail "kept lines wrong: k1=[$k1] verb=[$g_verb] unreachable=[$g_un] k2=[$k2]"
fi

echo "G4-errmsg: a failing writer with / without its own ::error:: line -> the step's annotation says which"
CASES=$((CASES + 1))
RW_STUB_OUT=$'::error::ledger-discard: the unit failed (psql rc=3); the transaction rolled back and nothing was changed\nledger-discard: failed (pr=7 reason=unit)\n' RW_STUB_RC=1 run_rstep workflow_dispatch true false; e1=$out
RW_STUB_OUT=$'something crashed\n' RW_STUB_RC=1 run_rstep workflow_dispatch true false; e2=$out
if grep -qF 'its ::error:: lines above name the refusal' <<<"$e1" && grep -qF 'printed no ::error:: line of its own' <<<"$e2" \
  && ! grep -qF 'printed no ::error:: line of its own' <<<"$e1"; then
  pass "the annotation never points at lines that do not exist"
else
  fail "error wording: [$e1] || [$e2]"
fi

# ---- the Doppler assertion step, extracted and run against a fake doppler ----
DSTEP="$tmp/rw-doppler-step.sh"
python3 - "$RW" "$DSTEP" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
got = [s for s in doc["jobs"]["reconcile"]["steps"] if s.get("id") == "doppler_dev"]
assert len(got) == 1
open(sys.argv[2], "w").write(got[0]["run"])
PY
run_dstep() {  # <config-json> <names-json>
  set +e
  out=$(DOPPLER_TOKEN=x DLP_FAKE_DOPPLER_CONFIG="$1" DLP_FAKE_DOPPLER_NAMES="$2" bash --noprofile --norc -eo pipefail "$DSTEP" 2>&1)
  rc=$?
  set -e
}
echo "G4-doppler: the dev/Management-token assertion fails closed on every parse error (C9)"
CASES=$((CASES + 1))
dres=""
run_dstep '{"environment":"dev"}' '{"DATABASE_URL":null}'; dres+="$rc"
run_dstep '{"environment":"dev"}' '{"SUPABASE_ACCESS_TOKEN":null}'; dres+="$rc"
run_dstep '{"environment":"dev"}' 'not json at all'; dres+="$rc"
run_dstep '{"environment":"dev"}' '["SUPABASE_ACCESS_TOKEN"]'; dres+="$rc"
run_dstep 'garbage' '{"A":null}'; dres+="$rc"
run_dstep '{"environment":"prd"}' '{"A":null}'; dres+="$rc"
if [[ "$dres" == "011111" ]]; then pass "only a dev config with a parseable names object lacking the key passes"; else fail "doppler step verdicts: $dres (want 011111)"; fi

# ---- the report job's steps, extracted and run against the fake gh ----
extract_rw() {  # <job> <step-id> <out>
  python3 - "$RW" "$1" "$2" "$3" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
got = [s for s in doc["jobs"][sys.argv[2]]["steps"] if s.get("id") == sys.argv[3]]
assert len(got) == 1, f"no step {sys.argv[3]}"
open(sys.argv[4], "w").write(got[0]["run"])
PY
}
CSTEP="$tmp/rw-comment-step.sh"; ISTEP="$tmp/rw-issue-step.sh"
extract_rw report comment "$CSTEP"; extract_rw report issue "$ISTEP"
POSTS="$tmp/gh-posts"
run_report_step() {  # <step-file> <verb> <ledger-only> <unreachable> <refusal> <reconcile-outcome> <kept-text>
  rm -rf "$POSTS"; mkdir -p "$POSTS" "$tmp/rw-rt"
  set +e
  out=$(PR=7 EVENT_NAME=pull_request_target ACTOR=fixture-actor RUN_URL=https://example.invalid/run RC=0 VERB="$2" \
    LEDGER_ONLY="$3" UNREACHABLE="$4" REFUSAL="$5" OUT_CHECKOUT=success OUT_DOPPLER_CLI=success OUT_DOPPLER_DEV=success \
    OUT_RECONCILE="$6" KEPT_B64="$(printf '%s' "$7" | base64 -w0)" RUNNER_TEMP="$tmp/rw-rt" DLR_GH_POSTS="$POSTS" \
    bash --noprofile --norc -eo pipefail "$1" 2>&1)
  rc=$?
  set -e
}
echo "G4-residue: the audit comment claims ledger-only residue only after an EXECUTED discard (B4)"
CASES=$((CASES + 1))
gh_reset
run_report_step "$CSTEP" dry-run 1 0 "" success "ledger-discard: dry-run (pr=7 eligible=1 down=0 ledger-only=1 later-rows=0 held-by=0 unreachable=0)"
c1=$(cat "$POSTS"/*.comment 2>/dev/null || true); r1=$rc
gh_reset
run_report_step "$CSTEP" executed 1 0 "" success "ledger-discard: executed (pr=7 eligible=1 discarded=1 down=0 ledger-only=1 held-by=0 unreachable=0)"
c2=$(cat "$POSTS"/*.comment 2>/dev/null || true)
if [[ "$r1$rc" == "00" ]] && grep -qF 'ledger-discard: dry-run (pr=7' <<<"$c1" && ! grep -qF 'discarded ledger-only' <<<"$c1" \
  && grep -qF 'were discarded ledger-only' <<<"$c2" && grep -qxF 'gh POST comment 7/comments' "$CALLLOG"; then
  pass "a dry run or refusal never reads as a discard"
else
  fail "residue wording: dry=[$c1] executed=[$c2] log=[$(cat "$CALLLOG")]"
fi

echo "G4-issue: the issue step files '[ci/dev-ledger-reconcile] PR #7 …' with the cause, and comments on it when it is already open"
CASES=$((CASES + 1))
gh_reset
run_report_step "$ISTEP" refused 0 0 destructive-superseded failure "ledger-discard: refused (pr=7 eligible=1 down=1 ledger-only=0 later-rows=1 held-by=0 unreachable=0 reason=destructive-superseded)"
i1=$(cat "$POSTS"/*.issue 2>/dev/null || true); r1=$rc; l1=$(cat "$CALLLOG")
gh_reset
gh_issues_json "[$(issue_obj 9101 "[ci/dev-ledger-reconcile] PR #7 dev ledger rows need attention")]"
run_report_step "$ISTEP" executed 0 1 "" success "ledger-discard: unreachable 301_wa.sql reason=force-pushed"
i2=$(cat "$POSTS"/*.comment 2>/dev/null || true); l2=$(cat "$CALLLOG")
if [[ "$r1$rc" == "00" ]] && grep -qxF 'gh POST issue title=[ci/dev-ledger-reconcile] PR #7 dev ledger rows need attention' <<<"$l1" \
  && grep -qF 'the writer refused (reason `destructive-superseded`)' <<<"$i1" && grep -qF 'allow_later_rows=true' <<<"$i1" \
  && grep -qxF 'gh POST comment 9101/comments' <<<"$l2" && grep -qF '1 row(s) attributed to #7 are unreachable' <<<"$i2" \
  && grep -qxF 'gh issues?state=open&labels=ci/dev-ledger-reconcile,action-required' <<<"$l2"; then
  pass "one issue per PR, named the way the probe looks it up, with the specific cause"
else
  fail "issue step: rc=$r1/$rc l1=[$l1] i1=[$i1] l2=[$l2] i2=[$i2]"
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
EXPECTED_CASES=256
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
