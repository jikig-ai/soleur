#!/usr/bin/env bash
# dev-ledger-reconcile: discard ONE pull request's applied-but-unmerged migration
# versions from the shared DEV Supabase ledger and schema (#8605; ADR-061
# amendment 2026-09-23, DC-1). The only file in this area that writes to a
# database. It never touches prd.
#
# For pull request N it finds every ledger row (F, B) the PR owns — F is a
# top-level forward migration that is not on the base tip and never was in base
# history, B is a blob F carried in a first-parent commit of base..refs/pull/N/head,
# and no other fresh live branch independently holds F at B — and, in ONE
# `psql --single-transaction` unit, compare-and-set deletes each row and runs the
# `.down.sql` the PR paired with that applied body (when there is one).
#
# Safety, in the order it is enforced:
#   - DOPPLER_ENVIRONMENT must be `dev` before anything else (both modes).
#   - Fork PRs are refused (their CI never held the dev secret, so they never
#     applied anything). An OPEN PR's rows are discarded only for its author and
#     only with a paired .down.sql (no discard-then-re-apply residue).
#   - Every .down.sql body in the PR's history pairs is fetched by blob id with the
#     raw media type and hash-verified, then refused on ANY backslash byte BEFORE
#     any psql call: psql runs meta-commands (\!, \o |cmd, \copy … program) from a
#     -f file, so PR text must never reach one.
#   - Refusals are all-or-nothing and decided before the first write: transaction
#     control, statements that cannot run in a transaction, unparseable SQL, and
#     (without --allow-later-rows) a CASCADE or shared-object redefinition while
#     any row applied at or after this PR's earliest row exists. They match a
#     STRIPPED view of each body (comments, strings, quoted identifiers and
#     dollar-quoted bodies removed), never raw text; a single wrapping
#     BEGIN;/COMMIT; pair is normalized away first.
#   - --execute holds the dev-suite mutex (its own state dir, a 600 s wait) and
#     proceeds only on a DEV_SUITE_MUTEX_ACQUIRED banner: the mutex script is
#     fail-OPEN, so anything else exits 2 before any write. The ledger is read,
#     and under --require-closed the PR state re-read, INSIDE the mutex.
#   - The unit: lock/statement timeouts, then per row (applied_at DESC, filename
#     DESC) a DO block that deletes WHERE filename AND content_sha and raises
#     unless exactly one row matched, then the normalized down body. psql runs with
#     GH_TOKEN unset. Any failure rolls the whole PR back.
#   - psql output (which can carry RAISE text from PR-authored SQL) is printed
#     indented inside a ::stop-commands:: block; every other line this script
#     prints is built from validated filenames, 40-hex shas, 20-digit timestamps
#     and integers only.
#
# No NOTIFY pgrst: it cannot reach PostgREST over the pooler (#4285); PostgREST's
# ~10-min schema-cache poll picks the change up.
#
# The guard (dev-ledger-parity.sh) is sourced as a library from THIS script's
# own directory (DLR_GUARD overrides it, for tests), so the writer and the guard
# always come from the same tree. Exit codes mirror the guard's contract:
#   0  done / dry run / nothing to do / skipped
#   1  refused, or the unit failed (named); nothing was changed
#   2  cannot measure (config, transient, mutex not held, timeout); nothing was changed
set -uo pipefail
# Never trace with a live credential in the environment (#7797): the PR-state
# lookups and the writer run with GH_TOKEN set.
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}${GITHUB_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

readonly DLR_LEDGER_SQL="SELECT filename || '|' || COALESCE(content_sha, '') || '|' || COALESCE(to_char(applied_at AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISSUS'), '') FROM public._schema_migrations ORDER BY filename"
readonly DLR_MUTEX_WAIT_S=600
readonly DLR_UNIT_TIMEOUT_S=240

dlr_usage() {
  cat <<'USAGE'
Usage:
  dev-ledger-reconcile.sh --pr <N> --repo <dir> --base-branch <name>
                          [--execute] [--allow-later-rows] [--require-closed] [--actor <login>]
  dev-ledger-reconcile.sh --scan-down <file.down.sql>...   # read-only refusal classes
  dev-ledger-reconcile.sh --help

Discards pull request <N>'s applied-but-unmerged migration versions from the shared
DEV ledger and schema: a compare-and-set delete of each ledger row the PR owns plus
the .down.sql paired with the applied body, in ONE transaction, under the dev-suite
mutex. Needs DOPPLER_ENVIRONMENT=dev, DATABASE_URL_POOLER (or DATABASE_URL),
GITHUB_REPOSITORY and a GH_TOKEN with pull-requests: read.

Without --execute it is a DRY RUN: no mutex, no write. Output lines:
  would-discard <file> <applied-blob> down=<blob|none>     (execution order)
  later-row <file> <applied_at>                             (rows applied at/after this PR's)
  stacked <branch> <file>                                   (a live branch inherited <file> from this PR)
  ledger-discard: nothing to do (pr=N)
  ledger-discard: skipped (pr=N reopened)
  ledger-discard: dry-run (pr=N eligible=E down=K ledger-only=L later-rows=R)
  ledger-discard: refused (pr=N ... reason=<token>)
  ledger-discard: executed (pr=N eligible=E discarded=D down=K ledger-only=L)

  --execute           write (dry run first)
  --allow-later-rows  run a CASCADE / redefinition down although later rows exist
                      (the dry run lists them; the close-time run never passes this)
  --require-closed    skip (exit 0) if the PR is open, re-checked inside the mutex
  --actor <login>     the dispatcher; an OPEN PR's rows need its author

Workflow: gh workflow run dev-ledger-reconcile.yml --ref main -f pr=<N>   (dry run)
          ... -f execute=true   (then, only if the dry run says so, -f allow_later_rows=true)

Exit codes: 0 done/dry-run/nothing/skipped, 1 refused or the unit failed, 2 cannot measure.
USAGE
}

# ---------------------------------------------------------------------------
# The refusal classifier (python3: every GitHub runner and operator host has it).
#   check <in> <out>  normalize one wrapping BEGIN;/COMMIT; pair into <out>, then
#                     print the refusal classes of the stripped view, comma-joined
#                     ("-" when none): transaction-control, non-transactional,
#                     later-row-sensitive, unparseable.
# ---------------------------------------------------------------------------
read -r -d '' DLR_PY <<'PY'
import re, sys

def stripped_view(text):
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("--", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            out.append(" ")
            continue
        if text.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if text.startswith("/*", j):
                    depth, j = depth + 1, j + 2
                elif text.startswith("*/", j):
                    depth, j = depth - 1, j + 2
                else:
                    j += 1
            if depth:
                raise ValueError("unterminated block comment")
            out.append(" ")
            i = j
            continue
        if c == "'":
            j = i + 1
            while True:
                k = text.find("'", j)
                if k < 0:
                    raise ValueError("unterminated string")
                if text.startswith("''", k):
                    j = k + 2
                    continue
                break
            out.append(" ")
            i = k + 1
            continue
        if c == '"':
            j = i + 1
            while True:
                k = text.find('"', j)
                if k < 0:
                    raise ValueError("unterminated identifier")
                if text.startswith('""', k):
                    j = k + 2
                    continue
                break
            out.append(" ")
            i = k + 1
            continue
        if c == "$" and not (i > 0 and (text[i - 1].isalnum() or text[i - 1] == "_")):
            m = re.match(r"\$([A-Za-z_][A-Za-z0-9_]*)?\$", text[i:])
            if m:
                tag = m.group(0)
                k = text.find(tag, i + len(tag))
                if k < 0:
                    raise ValueError("unterminated dollar quote")
                out.append(" ")
                i = k + len(tag)
                continue
        out.append(c)
        i += 1
    return "".join(out)

BEGIN_RE = re.compile(r"^\s*(BEGIN|BEGIN\s+TRANSACTION|BEGIN\s+WORK|START\s+TRANSACTION)\s*;\s*(--.*)?$", re.I)
END_RE = re.compile(r"^\s*(COMMIT|COMMIT\s+TRANSACTION|COMMIT\s+WORK|END)\s*;\s*(--.*)?$", re.I)

def normalize(text):
    lines = text.split("\n")
    sig = [i for i, l in enumerate(lines) if l.strip() and not l.strip().startswith("--")]
    if len(sig) >= 2 and BEGIN_RE.match(lines[sig[0]]) and END_RE.match(lines[sig[-1]]):
        lines[sig[0]] = "-- (wrapping BEGIN removed by dev-ledger-reconcile)"
        lines[sig[-1]] = "-- (wrapping COMMIT removed by dev-ledger-reconcile)"
    return "\n".join(lines)

def start(kw):
    return re.compile(r"(?:^|;)\s*" + kw + r"\b", re.I)

TXN = [start(k) for k in (r"BEGIN", r"COMMIT", r"END", r"ROLLBACK", r"ABORT", r"START\s+TRANSACTION",
                          r"SAVEPOINT", r"RELEASE", r"PREPARE\s+TRANSACTION", r"CALL")]
NONTX = [re.compile(r"\bCONCURRENTLY\b", re.I)] + [start(k) for k in (
    r"VACUUM", r"ALTER\s+SYSTEM", r"CREATE\s+DATABASE", r"DROP\s+DATABASE")]
LATER = [re.compile(r"\bCASCADE\b", re.I)] + [start(k) for k in (
    r"CREATE\s+OR\s+REPLACE", r"CREATE\s+POLICY", r"ALTER\s+POLICY", r"DROP\s+POLICY",
    r"GRANT", r"REVOKE", r"ALTER\s+FUNCTION", r"ALTER\s+PROCEDURE")]

def classes(text):
    try:
        view = stripped_view(text)
    except ValueError:
        return ["unparseable"]
    got = []
    if any(r.search(view) for r in TXN):
        got.append("transaction-control")
    if any(r.search(view) for r in NONTX):
        got.append("non-transactional")
    if any(r.search(view) for r in LATER):
        got.append("later-row-sensitive")
    return got

if sys.argv[1] == "check":
    raw = open(sys.argv[2], "rb").read().decode("utf-8", "replace")
    norm = normalize(raw)
    open(sys.argv[3], "w").write(norm)
    print(",".join(classes(norm)) or "-")
else:
    sys.exit(2)
PY

# dlr_classify <in> <normalized-out> — prints the class list ("-" when clean).
dlr_classify() { python3 -c "$DLR_PY" check "$1" "$2"; }

# has_backslash <file> — 0 if the file holds a backslash byte, 1 if not, 2 on error.
has_backslash() {
  local rc=0
  LC_ALL=C grep -qF -e $'\\' -- "$1" || rc=$?
  return "$rc"
}

# --scan-down <file>... — read-only: "<basename><TAB><classes>" per file, the same
# refusal step the writer runs (backslash first, then the stripped-view classes).
dlr_scan_down() {
  local f tmpn rc cls
  command -v python3 >/dev/null 2>&1 || { echo "::error::ledger-discard: python3 not found on PATH" >&2; return 2; }
  tmpn=$(mktemp "${TMPDIR:-/tmp}/dlr-scan.XXXXXX") || { echo "::error::ledger-discard: mktemp failed" >&2; return 2; }
  trap 'rm -f "$tmpn"' RETURN
  for f in "$@"; do
    [[ -f "$f" ]] || { echo "::error::ledger-discard: --scan-down: not a file" >&2; return 2; }
    rc=0; has_backslash "$f" || rc=$?
    case "$rc" in
      0) printf '%s\tbackslash\n' "$(basename "$f")"; continue ;;
      1) : ;;
      *) echo "::error::ledger-discard: --scan-down: reading a file failed" >&2; return 2 ;;
    esac
    cls=$(dlr_classify "$f" "$tmpn") || { echo "::error::ledger-discard: --scan-down: the classifier failed" >&2; return 2; }
    printf '%s\t%s\n' "$(basename "$f")" "$cls"
  done
  return 0
}

# --help is answered first, before every refusal.
for dlr_a in "$@"; do
  case "$dlr_a" in --help|-h) dlr_usage; exit 0 ;; esac
done
if [[ "${1:-}" == "--scan-down" ]]; then
  shift
  dlr_scan_down "$@"
  exit $?
fi

# ---------------------------------------------------------------------------
# The guard, as a library, from THIS script's directory (never from --repo).
# Sourced at top level so its arrays are global.
# ---------------------------------------------------------------------------
DLR_SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) \
  || { echo "::error::ledger-discard: cannot resolve the writer's own directory" >&2; exit 2; }
DLR_GUARD_FILE="${DLR_GUARD:-$DLR_SELF_DIR/dev-ledger-parity.sh}"
if [[ ! -f "$DLR_GUARD_FILE" ]]; then
  echo "::error::ledger-discard: the guard library dev-ledger-parity.sh is missing next to the writer; nothing was changed" >&2
  exit 2
fi
# shellcheck disable=SC2034  # read by the sourced guard
DLP_AS_LIBRARY=1
# shellcheck source=/dev/null  # the guard; its dispatch never runs in library mode
source "$DLR_GUARD_FILE" || { echo "::error::ledger-discard: sourcing the guard library failed; nothing was changed" >&2; exit 2; }
unset DLP_AS_LIBRARY

# The guard's functions call cannot_measure by name; the writer's own wording wins.
cannot_measure() {
  local class="$1" msg="$2" suffix
  case "$class" in
    transient) suffix="re-run the workflow" ;;
    connect) suffix="re-run once; if it repeats, check the Doppler dev_scheduled database credentials" ;;
    *) suffix="a re-run will not help; check the inputs, the Doppler dev_scheduled config and the workflow wiring" ;;
  esac
  echo "::error::ledger-discard: cannot measure ($class): ${msg} — nothing was changed; ${suffix}"
  exit 2
}

# ---------------------------------------------------------------------------
# Temp files and the composed EXIT trap. Order: the writer's own temp files, the
# guard's cleanup (owner repo), the mutex release, then the mutex state dir —
# release needs that dir (the holder pid lives there), so it goes last.
# ---------------------------------------------------------------------------
DLR_TMP=""
MUTEX_SH=""
MUTEX_DIR=""
MUTEX_CALLED=0
# shellcheck disable=SC2329  # invoked by the EXIT trap below
dlr_on_exit() {
  local rc=$? line
  if [[ -n "$DLR_TMP" ]]; then rm -rf "$DLR_TMP"; fi
  cleanup
  if [[ "$MUTEX_CALLED" == "1" ]]; then
    while IFS= read -r line; do
      [[ "$line" =~ ^DEV_SUITE_MUTEX_[A-Z_]+([[:space:]][a-z_]+=[A-Za-z0-9_.-]+)*$ ]] && printf '%s\n' "$line"
    done < <(DEV_SUITE_MUTEX_STATE_DIR="$MUTEX_DIR" bash "$MUTEX_SH" release 2>/dev/null)
  fi
  if [[ -n "$MUTEX_DIR" ]]; then rm -rf "$MUTEX_DIR"; fi
  exit "$rc"
}
trap dlr_on_exit EXIT

DLR_TMP=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/dev-ledger-reconcile.XXXXXX") \
  || { DLR_TMP=""; cannot_measure config "mktemp failed"; }
assert_fixture_dir "$DLR_TMP"

# ---------------------------------------------------------------------------
# 1. Parse and refuse early.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2034  # read by the guard's messages
MODE=reconcile
PR=""
REPO=""
BASE_BRANCH=""
EXECUTE=0
ALLOW_LATER=0
REQUIRE_CLOSED=0
ACTOR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr|--repo|--base-branch|--actor)
      [[ $# -ge 2 ]] || cannot_measure config "$1 requires a value"
      case "$1" in
        --pr) PR="$2" ;;
        --repo) REPO="$2" ;;
        --base-branch) BASE_BRANCH="$2" ;;
        --actor) ACTOR="$2" ;;
      esac
      shift 2 ;;
    --execute) EXECUTE=1; shift ;;
    --allow-later-rows) ALLOW_LATER=1; shift ;;
    --require-closed) REQUIRE_CLOSED=1; shift ;;
    *) cannot_measure config "unknown argument" ;;
  esac
done
[[ "$PR" =~ ^[1-9][0-9]{0,6}$ ]] || cannot_measure config "--pr must be a pull request number"
[[ -z "$ACTOR" || "$ACTOR" =~ ^[A-Za-z0-9-]{1,39}$ ]] || cannot_measure config "--actor is not a GitHub login"
# In-process dev assertion, for laptop runs too (the workflow also asserts the
# Doppler config's environment before this script starts).
[[ "${DOPPLER_ENVIRONMENT:-}" == "dev" ]] \
  || cannot_measure config "DOPPLER_ENVIRONMENT is not dev; this writer only ever runs against the dev project"
[[ "$BASE_BRANCH" =~ ^[A-Za-z0-9._/-]+$ ]] || cannot_measure config "--base-branch is missing or unsafe"
_assert_repo_root "$REPO"
gh_repo_init
DB_URL="${DATABASE_URL_POOLER:-${DATABASE_URL:-}}"
[[ -n "$DB_URL" ]] || cannot_measure config "neither DATABASE_URL_POOLER nor DATABASE_URL is set"
command -v psql >/dev/null 2>&1 || cannot_measure config "psql not found on PATH"
command -v python3 >/dev/null 2>&1 || cannot_measure config "python3 not found on PATH"
MUTEX_SH="$REPO/scripts/dev-suite-mutex.sh"

# refused <reason-token> — the one summary line for a refusal; exit 1, nothing written.
N_ELIGIBLE=0; N_DOWN=0; N_LEDGER_ONLY=0; N_LATER=0
refused() {
  echo "ledger-discard: refused (pr=$PR eligible=$N_ELIGIBLE down=$N_DOWN ledger-only=$N_LEDGER_ONLY later-rows=$N_LATER reason=$1)"
  exit 1
}

# ---------------------------------------------------------------------------
# 2. PR facts (GitHub REST, read-only).
# ---------------------------------------------------------------------------
PR_STATE=""; PR_HEAD=""; PR_LOGIN=""; PR_REF=""; PR_ORIGIN=""
read_pr() {
  local facts
  gh_rest -X GET "repos/$GH_REPO/pulls/$PR"
  facts=$(jq -e -r --arg repo "$GH_REPO" '
    [ (.state // ""), (.head.sha // ""), (.user.login // ""), (.head.ref // ""),
      (if .head.repo == null then "fork" elif .head.repo.full_name == $repo then "same" else "fork" end) ]
    | @tsv' <<<"$GH_BODY" 2>/dev/null) || cannot_measure transient "pulls/$PR was not the expected JSON"
  IFS=$'\t' read -r PR_STATE PR_HEAD PR_LOGIN PR_REF PR_ORIGIN <<<"$facts"
  [[ "$PR_STATE" == "open" || "$PR_STATE" == "closed" ]] || cannot_measure transient "pulls/$PR carried an unexpected state"
  is_sha "$PR_HEAD" || cannot_measure transient "pulls/$PR carried no head sha"
  # Only ever used as an exclusion key and a comparison value, never printed.
  [[ "$PR_REF" =~ ^[A-Za-z0-9._/-]+$ ]] || PR_REF=""
}
read_pr
if [[ "$PR_ORIGIN" != "same" ]]; then
  echo "::error::ledger-discard: PR #$PR comes from a fork; fork PRs never applied to dev (their CI holds no dev secret), so there is nothing of theirs to discard"
  refused fork
fi
if [[ "$REQUIRE_CLOSED" == "1" && "$PR_STATE" == "open" ]]; then
  echo "ledger-discard: skipped (pr=$PR reopened)"
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. Git facts: the owner repo plus refs/pull/N/head (it survives branch deletion).
# ---------------------------------------------------------------------------
owners_repo "$BASE_BRANCH"
origin_url=$(git -C "$REPO" remote get-url origin 2>/dev/null) || origin_url=""
[[ -n "$origin_url" ]] || cannot_measure config "--repo has no 'origin' remote"
fetch_err="$DLR_TMP/fetch-pr.err"
fetch_rc=0
bounded "$FETCH_TIMEOUT_S" git -C "$OWN" fetch -q --no-tags --filter=blob:none "$origin_url" \
  "+refs/pull/$PR/head:refs/prhead/$PR" 2>"$fetch_err" || fetch_rc=$?
if [[ "$fetch_rc" != "0" ]]; then
  fetch_class=transient
  case "$(fetch_reason "$fetch_rc" "$fetch_err")" in auth|no-repository) fetch_class=config ;; esac
  cannot_measure "$fetch_class" "fetching refs/pull/$PR/head failed (git rc=$fetch_rc, $(fetch_reason "$fetch_rc" "$fetch_err"))"
fi
PRREF="refs/prhead/$PR"
pr_tip=$(ogit rev-parse --verify --quiet "$PRREF^{commit}") || pr_tip=""
[[ "$pr_tip" == "$PR_HEAD" ]] \
  || cannot_measure transient "the PR head moved between the API read and the git fetch (a push landed)"

# ---------------------------------------------------------------------------
# 4. PR history pairs. First-parent walk, one tree read per commit: for every
#    (F, B) F ever carried, the down blob is F.down.sql's blob in the LAST commit
#    at which F still had blob B (a later down-only edit moves the pairing
#    forward; a later edit of F itself does not).
# ---------------------------------------------------------------------------
declare -A PAIR_DOWN=()   # "F|B" -> down blob id, or "none"
revs=$(ogit rev-list --reverse --first-parent "$BASE_OWN..$PRREF") \
  || cannot_measure transient "rev-list of the PR history failed"
while IFS= read -r c; do
  [[ -z "$c" ]] && continue
  tree=$(ogit ls-tree "$c" -- ":(top,literal)$MIG_REL/") || cannot_measure transient "ls-tree of a PR commit failed"
  unset fwd dwn
  declare -A fwd=() dwn=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    meta="${line%%$'\t'*}"; path="${line#*$'\t'}"
    read -r _ otype osha <<<"$meta"
    [[ "$otype" == "blob" ]] || continue
    n=$(top_level_name "$path"); [[ -n "$n" ]] || continue
    name_ok "$n" || continue
    case "$n" in
      *.down.sql) dwn["$n"]="$osha" ;;
      *.sql) [[ -n "${OWN_ON_BASE[$n]:-}" ]] || fwd["$n"]="$osha" ;;
    esac
  done <<<"$tree"
  for n in "${!fwd[@]}"; do
    PAIR_DOWN["$n|${fwd[$n]}"]="${dwn[${n%.sql}.down.sql]:-none}"
  done
done <<<"$revs"
if [[ ${#PAIR_DOWN[@]} -eq 0 ]]; then
  echo "ledger-discard: nothing to do (pr=$PR)"
  exit 0
fi

# ---------------------------------------------------------------------------
# 4b. Every down body the pairs name: fetched by id (raw media type), verified
#     against the id, and refused on a backslash byte — all BEFORE any psql call.
# ---------------------------------------------------------------------------
declare -A DOWN_RAW=()    # blob id -> local file
fetch_blob() {  # fetch_blob <id> <out>
  local id="$1" out="$2" attempt rc wait="${DLP_GH_RETRY_S:-5}" got
  [[ "$wait" =~ ^[0-9]{1,3}$ ]] || wait=5
  for attempt in 1 2; do
    rc=0
    bounded "$GH_TIMEOUT_S" gh api -H 'Accept: application/vnd.github.raw+json' "repos/$GH_REPO/git/blobs/$id" >"$out" 2>/dev/null || rc=$?
    [[ "$rc" == "0" ]] && break
    [[ "$attempt" == "1" ]] && sleep "$wait"
  done
  [[ "$rc" == "0" ]] || cannot_measure transient "fetching down blob $id failed twice (gh rc=$rc)"
  got=$(ogit hash-object --no-filters -- "$out") || cannot_measure transient "hashing down blob $id failed"
  [[ "$got" == "$id" ]] || cannot_measure transient "down blob $id did not hash to its id"
}
bs_files=""
for key in "${!PAIR_DOWN[@]}"; do
  d="${PAIR_DOWN[$key]}"
  [[ "$d" == "none" || -n "${DOWN_RAW[$d]:-}" ]] && continue
  is_sha "$d" || cannot_measure transient "a down blob id is malformed"
  DOWN_RAW["$d"]="$DLR_TMP/down-$d.sql"
  fetch_blob "$d" "${DOWN_RAW[$d]}"
done
for key in "${!PAIR_DOWN[@]}"; do
  d="${PAIR_DOWN[$key]}"
  [[ "$d" == "none" ]] && continue
  bsrc=0; has_backslash "${DOWN_RAW[$d]}" || bsrc=$?
  case "$bsrc" in
    0) bs_files+=" ${key%%|*}" ;;
    1) : ;;
    *) cannot_measure transient "reading a down body failed" ;;
  esac
done
if [[ -n "$bs_files" ]]; then
  for f in $(tr ' ' '\n' <<<"$bs_files" | LC_ALL=C sort -u); do
    echo "::error::ledger-discard: the .down.sql paired with $f in PR #$PR contains a backslash; psql would run it as a meta-command, so this PR's rows need the manual reconcile in knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md"
  done
  refused backslash
fi

# ---------------------------------------------------------------------------
# 5-7. Open-PR authority, the mutex, and the in-mutex reopen re-check (execute).
# ---------------------------------------------------------------------------
if [[ "$EXECUTE" == "1" && "$PR_STATE" == "open" && ( -z "$ACTOR" || "$ACTOR" != "$PR_LOGIN" ) ]]; then
  echo "::error::ledger-discard: PR #$PR is open; an open PR's rows can be discarded only by its author. Close the PR to let the close-time run discard them."
  refused open-author
fi
if [[ "$EXECUTE" == "1" ]]; then
  [[ -f "$MUTEX_SH" ]] || cannot_measure config "scripts/dev-suite-mutex.sh is missing from --repo"
  MUTEX_DIR=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/dev-ledger-reconcile-mutex.XXXXXX") \
    || { MUTEX_DIR=""; cannot_measure config "mktemp failed"; }
  assert_fixture_dir "$MUTEX_DIR"
  run_id="${GITHUB_RUN_ID:-local}"
  [[ "$run_id" =~ ^[0-9]{1,20}$ ]] || run_id=local
  MUTEX_CALLED=1
  banner=$(DEV_SUITE_MUTEX_STATE_DIR="$MUTEX_DIR" DEV_SUITE_MUTEX_WAIT_S="$DLR_MUTEX_WAIT_S" \
    DEV_SUITE_MUTEX_IDENTITY="reconcile-$run_id-pr$PR" bash "$MUTEX_SH" acquire 2>/dev/null) || true
  mtok=$(grep -oE -m1 '^DEV_SUITE_MUTEX_[A-Z_]+' <<<"$banner" || true)
  printf '%s\n' "${mtok:-<no banner>}"
  if [[ "$mtok" != "DEV_SUITE_MUTEX_ACQUIRED" ]]; then
    cannot_measure transient "could not hold the dev-suite mutex (${mtok:-no banner}); the writer proceeds only on DEV_SUITE_MUTEX_ACQUIRED"
  fi
  if [[ "$REQUIRE_CLOSED" == "1" ]]; then
    read_pr
    if [[ "$PR_STATE" == "open" ]]; then
      echo "ledger-discard: skipped (pr=$PR reopened)"
      exit 0
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 8. The ledger (inside the mutex under --execute), with microsecond applied_at.
# ---------------------------------------------------------------------------
ledger_rc=0
ledger_out=$(PGCONNECT_TIMEOUT=10 bounded "$PSQL_TIMEOUT_S" psql "$DB_URL" -w --no-psqlrc -tAq --set ON_ERROR_STOP=1 -c "$DLR_LEDGER_SQL" 2>/dev/null) || ledger_rc=$?
case "$ledger_rc" in
  0) : ;;
  124|137) cannot_measure transient "reading public._schema_migrations timed out (psql rc=$ledger_rc)" ;;
  2) cannot_measure connect "could not connect to or authenticate with the dev database (psql rc=2)" ;;
  *) cannot_measure config "reading public._schema_migrations failed (psql rc=$ledger_rc)" ;;
esac
declare -a L_F=() L_B=() L_T=()
suspicious=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if [[ ! "$line" =~ ^([^|]*)\|([^|]*)\|([0-9]{20})$ ]]; then suspicious=$((suspicious + 1)); continue; fi
  if ! name_ok "${BASH_REMATCH[1]}"; then suspicious=$((suspicious + 1)); continue; fi
  L_F+=("${BASH_REMATCH[1]}"); L_B+=("${BASH_REMATCH[2]}"); L_T+=("${BASH_REMATCH[3]}")
done <<<"$ledger_out"
[[ ${#L_F[@]} -gt 0 ]] || cannot_measure config "the dev ledger returned zero rows — wrong database or broken query"
if [[ "$suspicious" -gt 0 ]]; then
  echo "::warning::ledger-discard: $suspicious ledger row(s) have a shape or filename outside the runner's whitelist (not echoed); each is treated as a later row"
fi

# ---------------------------------------------------------------------------
# 9. Eligibility. Ineligible rows are not this PR's; they are not errors.
# ---------------------------------------------------------------------------
declare -a E_F=() E_B=() E_T=() E_D=()
declare -A E_KEY=()
for i in "${!L_F[@]}"; do
  f="${L_F[$i]}"; b="${L_B[$i]}"
  case "$f" in *.down.sql) continue ;; *.sql) : ;; *) continue ;; esac
  [[ -n "${OWN_ON_BASE[$f]:-}" || -n "${OWN_EVER[$f]:-}" ]] && continue
  is_sha "$b" || continue
  [[ -n "${PAIR_DOWN[$f|$b]+set}" ]] || continue
  holder=$(independent_holder "$f" "$b" "$PR_REF" "$PRREF") || exit 2
  [[ -n "$holder" ]] && continue
  E_F+=("$f"); E_B+=("$b"); E_T+=("${L_T[$i]}"); E_D+=("${PAIR_DOWN[$f|$b]}")
  E_KEY["$f"]=1
done
N_ELIGIBLE=${#E_F[@]}
if [[ "$N_ELIGIBLE" -eq 0 ]]; then
  echo "ledger-discard: nothing to do (pr=$PR)"
  exit 0
fi

# Execution order: applied_at DESC, then filename DESC.
mapfile -t ORDER < <(for i in "${!E_F[@]}"; do printf '%s\t%s\t%s\n' "${E_T[$i]}" "${E_F[$i]}" "$i"; done \
  | LC_ALL=C sort -t $'\t' -k1,1r -k2,2r | cut -f3)
[[ ${#ORDER[@]} -eq "$N_ELIGIBLE" ]] || cannot_measure transient "ordering the eligible rows failed"

# Later rows: any row applied at or after this PR's earliest eligible row that is
# not one of this PR's eligible rows (suspicious rows count as later rows too).
t_min="${E_T[${ORDER[$((N_ELIGIBLE - 1))]}]}"
later_lines=""
for i in "${!L_F[@]}"; do
  [[ -n "${E_KEY[${L_F[$i]}]:-}" ]] && continue
  [[ "${L_T[$i]}" > "$t_min" || "${L_T[$i]}" == "$t_min" ]] || continue
  later_lines+="${L_T[$i]} ${L_F[$i]}"$'\n'
done
N_LATER=$(( $(grep -c . <<<"$later_lines" || true) + suspicious ))

# ---------------------------------------------------------------------------
# 10-12. Refusal classes per eligible down body; ledger-only rows.
# ---------------------------------------------------------------------------
declare -A NORM=()        # down blob id -> normalized file
declare -A NORM_CLS=()    # down blob id -> refusal classes of its normalized body
refusals=()
for i in "${ORDER[@]}"; do
  f="${E_F[$i]}"; d="${E_D[$i]}"
  if [[ "$d" == "none" ]]; then
    N_LEDGER_ONLY=$((N_LEDGER_ONLY + 1))
    if [[ "$PR_STATE" == "open" ]]; then
      echo "::error::ledger-discard: $f has no .down.sql paired with applied blob ${E_B[$i]}; an open PR's row is discarded only with its down (a discard without one leaves the objects its body created, and the PR's next CI run re-applies over them)"
      refusals+=(open-ledger-only)
    fi
    continue
  fi
  N_DOWN=$((N_DOWN + 1))
  if [[ -z "${NORM[$d]:-}" ]]; then
    NORM["$d"]="$DLR_TMP/norm-$d.sql"
    cls=$(dlr_classify "${DOWN_RAW[$d]}" "${NORM[$d]}") || cannot_measure transient "the refusal classifier failed"
    NORM_CLS["$d"]="$cls"
  fi
  cls="${NORM_CLS[$d]}"
  case ",$cls," in *,unparseable,*)
    echo "::error::ledger-discard: the .down.sql paired with $f could not be tokenized (an unterminated comment, string or dollar quote); it needs the manual reconcile per the learning"
    refusals+=(unparseable) ;;
  esac
  case ",$cls," in *,transaction-control,*)
    echo "::error::ledger-discard: the .down.sql paired with $f carries transaction control beyond one wrapping BEGIN;/COMMIT; pair; it cannot run inside the single transaction and needs manual handling per the learning"
    refusals+=(transaction-control) ;;
  esac
  case ",$cls," in *,non-transactional,*)
    echo "::error::ledger-discard: the .down.sql paired with $f carries a statement that cannot run in a transaction (CONCURRENTLY, VACUUM, ALTER SYSTEM, CREATE/DROP DATABASE); it needs manual handling per the learning"
    refusals+=(non-transactional) ;;
  esac
  case ",$cls," in *,later-row-sensitive,*)
    if [[ "$N_LATER" -gt 0 && "$ALLOW_LATER" != "1" ]]; then
      echo "::error::ledger-discard: the .down.sql paired with $f uses CASCADE or redefines a shared object (CREATE OR REPLACE, a policy, a grant, ALTER FUNCTION) while $N_LATER row(s) were applied at or after this PR's earliest row (listed as later-row); after reviewing the dry run, re-run with -f allow_later_rows=true"
      refusals+=(later-row)
    fi ;;
  esac
done

# ---------------------------------------------------------------------------
# 13. Report (both modes), then refuse, dry-run, or execute.
# ---------------------------------------------------------------------------
for i in "${ORDER[@]}"; do
  printf 'would-discard %s %s down=%s\n' "${E_F[$i]}" "${E_B[$i]}" "${E_D[$i]}"
done
while read -r lt lf; do
  [[ -z "$lt" ]] && continue
  printf 'later-row %s %s\n' "$lf" "$lt"
done < <(LC_ALL=C sort <<<"$later_lines")
[[ "$suspicious" -gt 0 ]] && printf 'later-row <unprintable-row> undated\n'
for i in "${ORDER[@]}"; do
  while IFS= read -r sb; do
    [[ -z "$sb" ]] && continue
    printf 'stacked %s %s\n' "$(branch_label "$sb")" "${E_F[$i]}"
  done < <(holders_at_blob "${E_F[$i]}" "${E_B[$i]}" "$PR_REF")
done
if [[ "$PR_STATE" == "closed" ]]; then
  for i in "${ORDER[@]}"; do
    [[ "${E_D[$i]}" == "none" ]] || continue
    echo "::warning::ledger-discard: ${E_F[$i]} has no .down.sql paired with applied blob ${E_B[$i]}; objects its body created stay on dev"
  done
fi
if [[ ${#refusals[@]} -gt 0 ]]; then
  refused "${refusals[0]}"
fi
if [[ "$EXECUTE" != "1" ]]; then
  echo "ledger-discard: dry-run (pr=$PR eligible=$N_ELIGIBLE down=$N_DOWN ledger-only=$N_LEDGER_ONLY later-rows=$N_LATER)"
  exit 0
fi

# ---------------------------------------------------------------------------
# 14. Execute: ONE unit for the whole PR (apply_discard_unit is the only -f site).
# ---------------------------------------------------------------------------
UNIT="$DLR_TMP/unit.sql"
declare -a ROW_START=()
{
  printf -- '-- dev-ledger-reconcile: PR #%s, one transaction (psql --single-transaction)\n' "$PR"
  printf "SET LOCAL lock_timeout = '30s';\n"
  printf "SET LOCAL statement_timeout = '120s';\n"
} > "$UNIT" || cannot_measure config "writing the unit failed"
for i in "${ORDER[@]}"; do
  ROW_START+=("$(( $(wc -l < "$UNIT") + 1 ))")
  {
    printf -- '-- row: %s applied blob %s down %s\n' "${E_F[$i]}" "${E_B[$i]}" "${E_D[$i]}"
    # shellcheck disable=SC2016  # $dlr_cas$ is a literal SQL dollar-quote tag
    printf 'DO $dlr_cas$\nDECLARE n integer;\nBEGIN\n'
    printf "  DELETE FROM public._schema_migrations WHERE filename = '%s' AND content_sha = '%s';\n" "${E_F[$i]}" "${E_B[$i]}"
    printf '  GET DIAGNOSTICS n = ROW_COUNT;\n  IF n <> 1 THEN\n'
    printf "    RAISE EXCEPTION 'ledger-discard: compare-and-set on %% matched %% rows', '%s', n;\n" "${E_F[$i]}"
    # shellcheck disable=SC2016  # $dlr_cas$ is a literal SQL dollar-quote tag
    printf '  END IF;\nEND\n$dlr_cas$;\n'
    if [[ "${E_D[$i]}" != "none" ]]; then
      cat "${NORM[${E_D[$i]}]}"
      printf '\n;\n'
    fi
  } >> "$UNIT" || cannot_measure config "writing the unit failed"
done

apply_discard_unit() {
  local out_f="$DLR_TMP/psql.out" rc=0 tok at row_file="" k
  bounded "$DLR_UNIT_TIMEOUT_S" env -u GH_TOKEN -u GITHUB_TOKEN PGCONNECT_TIMEOUT=10 \
    psql "$DB_URL" -w --no-psqlrc --single-transaction -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f "$UNIT" >"$out_f" 2>&1 || rc=$?
  # psql output can carry RAISE text from PR-authored SQL: fenced and indented,
  # never parsed as a workflow command and never copied into a summary.
  tok=$(od -An -tx1 -N16 /dev/urandom 2>/dev/null | tr -d ' \n')
  [[ "$tok" =~ ^[0-9a-f]{32}$ ]] || tok="$(printf '%08x%08x%08x%08x' "$RANDOM$RANDOM" "$RANDOM$RANDOM" "$RANDOM$RANDOM" "$RANDOM$RANDOM")"
  echo "::stop-commands::$tok"
  tr '\r' ' ' <"$out_f" | sed 's/^/    /'
  echo "::$tok::"
  [[ "$rc" == "0" ]] && return 0
  case "$rc" in
    124|137) cannot_measure transient "the discard unit timed out (psql rc=$rc); its single transaction did not commit" ;;
  esac
  if grep -qE 'ERROR: +(55P03|57014):' "$out_f"; then
    cannot_measure transient "the discard unit timed out waiting for a lock or a statement (SQLSTATE 55P03/57014); its single transaction rolled back"
  fi
  if [[ "$rc" == "2" ]]; then
    cannot_measure connect "the dev database connection failed during the discard unit (psql rc=2); run the dry run again to see which rows remain"
  fi
  at=$(sed -n "s#^psql:${UNIT//#/\\#}:\\([0-9][0-9]*\\):.*#\\1#p" "$out_f" | head -n 1)
  if [[ "$at" =~ ^[0-9]+$ ]]; then
    for k in "${!ROW_START[@]}"; do
      (( ROW_START[k] <= at )) && row_file="${E_F[${ORDER[$k]}]}"
    done
  fi
  if [[ -n "$row_file" ]]; then
    echo "::error::ledger-discard: the unit failed at $row_file (psql rc=$rc); the transaction rolled back and nothing was changed"
  else
    echo "::error::ledger-discard: the unit failed (psql rc=$rc); the transaction rolled back and nothing was changed"
  fi
  echo "ledger-discard: failed (pr=$PR eligible=$N_ELIGIBLE down=$N_DOWN ledger-only=$N_LEDGER_ONLY)"
  exit 1
}
apply_discard_unit

for i in "${ORDER[@]}"; do
  echo "::notice::ledger-discard: discarded ${E_F[$i]} (applied blob ${E_B[$i]}, down ${E_D[$i]}) for PR #$PR"
done
echo "note: PostgREST picks up the schema change on its ~10-min schema-cache poll (NOTIFY does not reach it over the pooler, #4285)"
echo "ledger-discard: executed (pr=$PR eligible=$N_ELIGIBLE discarded=$N_ELIGIBLE down=$N_DOWN ledger-only=$N_LEDGER_ONLY)"
exit 0
