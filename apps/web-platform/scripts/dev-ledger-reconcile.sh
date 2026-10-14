#!/usr/bin/env bash
# dev-ledger-reconcile: discard ONE pull request's applied-but-unmerged migration
# versions from the shared DEV Supabase ledger and schema (#8605; ADR-061
# amendment 2026-09-23, DC-1). The only file in this area that writes to a
# database. It never touches prd.
#
# For pull request N it finds every ledger row (F, B) the PR owns — F is a
# top-level forward migration that is not on the base tip and never was in base
# history, B is a blob F carried in a first-parent commit of base..refs/pull/N/head,
# and no OTHER fresh branch holding F at exactly B has an open pull request or none
# (`held-by`, whatever its ancestry: a child's close leaves shared rows until the
# parent closes) — and, in ONE `psql --single-transaction` unit, compare-and-set
# deletes each row and runs the `.down.sql` the PR paired with that applied body
# (when there is one).
#
# Ownership gap (CTO ruling 1): the writer also runs the classifier over every
# missing-on-main row. A row it attributes to PR N (closed / closed-grace) always
# ends as one of: discarded, `held-by <branch>`, or
# `unreachable <file> reason=force-pushed|slug|no-history` — the applied body is
# not in the PR's first-parent history under that name, so it is never discarded
# blind; the workflow files an action-required issue for it.
#
# Safety, in the order it is enforced (refusal priority, E6):
#   - xtrace is refused unconditionally (exit 78): this script always handles DB
#     credentials. DLR_GUARD / DLR_MUTEX / DLR_TAG_HEX are TEST-ONLY seams and are
#     refused under GITHUB_ACTIONS=true.
#   - DOPPLER_ENVIRONMENT must be `dev` before anything else.
#   - Refusal reasons, first match wins: fork, merged, backslash, open-author,
#     unparseable, transaction-control, non-transactional, open-ledger-only,
#     later-row, destructive-superseded. Fork PRs never applied anything; a MERGED
#     PR's migrations are main's. An OPEN PR's rows are discarded only for its
#     author and only with a paired .down.sql.
#   - Every .down.sql body in the PR's history pairs is fetched by blob id with the
#     raw media type and hash-verified, then refused on ANY backslash byte BEFORE
#     any psql call: psql runs meta-commands (\!, \o |cmd, \copy … program) from a
#     -f file, so PR text must never reach one. The assembled unit is checked too.
#   - The python classifier is ADVISORY (a clean refusal before any write): it
#     matches a STRIPPED view of each body (comments, strings, quoted identifiers
#     and dollar-quoted bodies removed; a single wrapping BEGIN;/COMMIT; pair is
#     normalized away first). The ENFORCEMENT is server-side: every down body runs
#     as `DO $<t1>$ BEGIN EXECUTE $<t2>$<body>$<t2>$; END $<t1>$;` with random tags
#     verified absent from the body, so PL/pgSQL rejects transaction control, COPY
#     to/from the client and statements that cannot run in a transaction block,
#     and the whole unit rolls back. Error positions reference the wrapping DO.
#   - Later-row safety (without --allow-later-rows): a CASCADE or shared-object
#     redefinition is refused while any row applied at or after this PR's earliest
#     row exists; a plain DROP / ALTER … DROP / TRUNCATE / DELETE / UPDATE is
#     refused (destructive-superseded) while such a row is a migration on main.
#   - --execute holds the dev-suite mutex (its own state dir, a 600 s wait) and
#     proceeds only on a DEV_SUITE_MUTEX_ACQUIRED banner: the mutex script is
#     fail-OPEN, so anything else exits 2 before any write. Inside the mutex the PR
#     is re-read (state, head sha, merged), origin's heads are re-fetched, holder
#     PR states are re-read, and the ledger is read.
#   - The unit: lock/statement timeouts; LOCK TABLE public._schema_migrations IN
#     SHARE ROW EXCLUSIVE MODE; a DO block asserting the ledger's md5 still equals
#     the snapshot the writer read; per row (applied_at DESC, filename DESC) a DO
#     block that deletes WHERE filename AND content_sha and raises unless exactly
#     one row matched, then the wrapped down body; a closing DO block asserting the
#     ledger's md5 equals the snapshot minus exactly the claimed rows. psql runs
#     with GH_TOKEN, GITHUB_TOKEN and DOPPLER_TOKEN unset. After psql the ledger is
#     re-read: each claimed (F, B) must be gone and no other row changed, else 1.
#   - psql output (which can carry RAISE text from PR-authored SQL) is printed
#     indented inside a ::stop-commands:: block (never on a connection failure,
#     whose text names the host); every other line this script prints is built
#     from validated filenames, 40-hex shas, 20-digit timestamps and integers only.
#
# No NOTIFY pgrst: it cannot reach PostgREST over the pooler (#4285); PostgREST's
# ~10-min schema-cache poll picks the change up.
#
# The guard (dev-ledger-parity.sh) is sourced as a library from THIS script's
# own directory, and the dev-suite mutex from THIS tree's scripts/ (never from
# --repo), so the writer, the guard and the mutex always come from the same tree.
# Exit codes mirror the guard's contract:
#   0  done / dry run / nothing to do / skipped
#   1  refused, or the unit failed (named); a refusal changed nothing
#   2  cannot measure (config, transient, mutex not held, timeout); nothing was changed
#   78 refused to run under xtrace
set -uo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

readonly DLR_ROW_EXPR="filename || '|' || COALESCE(content_sha, '') || '|' || COALESCE(to_char(applied_at AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISSUS'), '')"
readonly DLR_LEDGER_SQL="SELECT $DLR_ROW_EXPR FROM public._schema_migrations ORDER BY filename"
readonly DLR_MUTEX_WAIT_S=600
readonly DLR_UNIT_TIMEOUT_S=150

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

  --pr <N>            the pull request (a same-repo, unmerged one)
  --repo <dir>        the checkout whose 'origin' remote is the repository
  --base-branch <b>   the base branch (main)
  --execute           write (dry run first)
  --allow-later-rows  run a CASCADE / redefinition down although later rows exist, or
                      a destructive down although a later row is a migration on main
                      (the dry run lists them; the close-time run never passes this)
  --require-closed    skip (exit 0) if the PR is open, re-checked inside the mutex
  --actor <login>     the dispatcher; an OPEN PR's rows need its author
  --scan-down <f>...  print "<basename><TAB><classes>" per file: backslash, or the
                      comma-joined advisory classes (transaction-control,
                      non-transactional, later-row-sensitive, destructive,
                      unparseable), "-" when none. No database, no network.

Without --execute it is a DRY RUN: no mutex, no write. Output lines:
  would-discard <file> <applied-blob> down=<blob|none>     (execution order)
  later-row <file> <applied_at>                             (rows applied at/after this PR's)
  ledger-discard: held-by <file> <branch>                   (another live branch protects it)
  ledger-discard: unreachable <file> reason=force-pushed|slug|no-history
  ledger-discard: nothing to do (pr=N ...)
  ledger-discard: skipped (pr=N reason=reopened)
  ledger-discard: dry-run (pr=N eligible=E down=K ledger-only=L later-rows=R held-by=H unreachable=U)
  ledger-discard: refused (pr=N ... reason=<token>)
  ledger-discard: failed (pr=N ... reason=<token>)
  ledger-discard: executed (pr=N eligible=E discarded=D down=K ledger-only=L held-by=H unreachable=U)

Workflow: gh workflow run dev-ledger-reconcile.yml --ref main -f pr=<N>   (dry run)
          ... -f execute=true   (then, only if the dry run says so, -f allow_later_rows=true)

Exit codes: 0 done/dry-run/nothing/skipped, 1 refused or the unit failed,
2 cannot measure (nothing changed), 78 refused to run under xtrace (set -x).
Test-only environment (refused under GITHUB_ACTIONS=true): DLR_GUARD, DLR_MUTEX, DLR_TAG_HEX.
USAGE
}

# ---------------------------------------------------------------------------
# The ADVISORY refusal classifier (python3: every GitHub runner and operator host
# has it). The server-side EXECUTE wrapping is the enforcement; this only turns a
# body the server would reject into a named refusal before any write.
#   check <in> <out>  normalize one wrapping BEGIN;/COMMIT; pair into <out>, then
#                     print the classes of the stripped view, comma-joined ("-"
#                     when none): transaction-control, non-transactional,
#                     later-row-sensitive, destructive, unparseable. A body that is
#                     not strict UTF-8 is unparseable.
# ---------------------------------------------------------------------------
read -r -d '' DLR_PY <<'PY'
import re, sys

def ident_char(ch):
    # PostgreSQL identifier characters: letters, digits, _, $ and every high-bit byte.
    return ch.isalnum() or ch in "_$" or ord(ch) > 127

TAG = re.compile(r"\$([A-Za-z_\u0080-\U0010ffff][A-Za-z0-9_\u0080-\U0010ffff]*)?\$")

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
        # A `$` right after an identifier character (x$$, x€$$) continues that
        # identifier; it never opens a dollar quote.
        if c == "$" and not (i > 0 and ident_char(text[i - 1])):
            m = TAG.match(text, i)
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
NONTX = [re.compile(r"\bCONCURRENTLY\b", re.I),
         re.compile(r"(?:^|;)\s*COPY\b[^;]*\b(?:FROM\s+STDIN|TO\s+STDOUT)\b", re.I)] + [start(k) for k in (
    r"VACUUM", r"ALTER\s+SYSTEM", r"CREATE\s+DATABASE", r"DROP\s+DATABASE",
    r"CREATE\s+TABLESPACE", r"DROP\s+TABLESPACE", r"DISCARD\s+ALL")]
LATER = [re.compile(r"\bCASCADE\b", re.I)] + [start(k) for k in (
    r"CREATE\s+OR\s+REPLACE", r"CREATE\s+POLICY", r"ALTER\s+POLICY", r"DROP\s+POLICY",
    r"GRANT", r"REVOKE", r"ALTER\s+FUNCTION", r"ALTER\s+PROCEDURE")]
DESTRUCTIVE = [re.compile(r"(?:^|;)\s*ALTER\b[^;]*\bDROP\b", re.I)] + [start(k) for k in (
    r"DROP", r"TRUNCATE", r"DELETE", r"UPDATE")]

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
    if any(r.search(view) for r in DESTRUCTIVE):
        got.append("destructive")
    return got

if sys.argv[1] == "check":
    try:
        raw = open(sys.argv[2], "rb").read().decode("utf-8", "strict")
    except UnicodeDecodeError:
        open(sys.argv[3], "w").write("")
        print("unparseable")
        sys.exit(0)
    norm = normalize(raw)
    open(sys.argv[3], "w", encoding="utf-8").write(norm)
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
# The guard, as a library, from THIS script's directory (never from --repo), and
# the mutex from THIS tree. The DLR_* overrides exist for the test suite only.
# ---------------------------------------------------------------------------
if [[ "${GITHUB_ACTIONS:-}" == "true" && -n "${DLR_GUARD:-}${DLR_MUTEX:-}${DLR_TAG_HEX:-}" ]]; then
  echo "::error::ledger-discard: cannot measure (config): DLR_GUARD, DLR_MUTEX and DLR_TAG_HEX are test-only overrides and are refused in GitHub Actions — nothing was changed" >&2
  exit 2
fi
DLR_SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) \
  || { echo "::error::ledger-discard: cannot measure (config): cannot resolve the writer's own directory — nothing was changed" >&2; exit 2; }
DLR_GUARD_FILE="${DLR_GUARD:-$DLR_SELF_DIR/dev-ledger-parity.sh}"
if [[ ! -f "$DLR_GUARD_FILE" ]]; then
  echo "::error::ledger-discard: cannot measure (config): the guard library dev-ledger-parity.sh is missing next to the writer — nothing was changed" >&2
  exit 2
fi
# shellcheck disable=SC2034  # read by the sourced guard
DLP_AS_LIBRARY=1
# shellcheck source=/dev/null  # the guard; its dispatch never runs in library mode
source "$DLR_GUARD_FILE" || { echo "::error::ledger-discard: cannot measure (config): sourcing the guard library failed — nothing was changed" >&2; exit 2; }
unset DLP_AS_LIBRARY

# The guard's functions call cannot_measure by name; the writer's own wording wins.
# stderr: a caller inside $(...) must not swallow the annotation.
cannot_measure() {
  local class="$1" msg="$2" suffix
  case "$class" in
    transient) suffix="re-run the workflow" ;;
    connect) suffix="re-run once; if it repeats, check the Doppler dev_scheduled database credentials" ;;
    *) suffix="a re-run will not help; check the inputs, the Doppler dev_scheduled config and the workflow wiring" ;;
  esac
  echo "::error::ledger-discard: cannot measure ($class): ${msg} — nothing was changed; ${suffix}" >&2
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
  if [[ -n "$DLR_TMP" ]]; then
    assert_fixture_dir "$DLR_TMP"
    rm -rf "$DLR_TMP"
  fi
  cleanup
  if [[ "$MUTEX_CALLED" == "1" ]]; then
    # Only the mutex's own banner lines, control bytes stripped; the ::warning::
    # HOLDER_LOST / RELEASE_FAILED lines are the unserialized-section signal.
    while IFS= read -r line; do
      line=$(printf '%s' "$line" | LC_ALL=C tr -d '\000-\037\177')
      [[ "$line" =~ ^(::warning::)?DEV_SUITE_MUTEX_[A-Z_]+([[:space:]].*)?$ ]] && printf '%s\n' "$line"
    done < <(DEV_SUITE_MUTEX_STATE_DIR="$MUTEX_DIR" bash "$MUTEX_SH" release 2>/dev/null)
  fi
  if [[ -n "$MUTEX_DIR" ]]; then
    assert_fixture_dir "$MUTEX_DIR"
    rm -rf "$MUTEX_DIR"
  fi
  exit "$rc"
}
trap dlr_on_exit EXIT

DLR_TMP=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/dev-ledger-reconcile.XXXXXX") \
  || { DLR_TMP=""; cannot_measure config "mktemp of the writer's temp dir failed"; }
assert_fixture_dir "$DLR_TMP"

# ---------------------------------------------------------------------------
# 1. Parse and refuse early.
# ---------------------------------------------------------------------------
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
[[ -z "$ACTOR" || "$ACTOR" =~ ^[A-Za-z0-9-]{1,39}(\[bot\])?$ ]] || cannot_measure config "--actor is not a GitHub login"
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
if [[ -n "${DLR_MUTEX:-}" ]]; then
  MUTEX_SH="$DLR_MUTEX"
else
  MUTEX_SH="$(cd "$DLR_SELF_DIR/../../.." && pwd)/scripts/dev-suite-mutex.sh" \
    || cannot_measure config "cannot resolve this tree's scripts/ directory"
fi

# Counters are printed only once they were measured (E5).
N_ELIGIBLE=0; N_DOWN=0; N_LEDGER_ONLY=0; N_LATER=0; N_HELD=0; N_UNREACH=0
MEASURED=0
counts() {
  printf 'eligible=%s down=%s ledger-only=%s later-rows=%s held-by=%s unreachable=%s' \
    "$N_ELIGIBLE" "$N_DOWN" "$N_LEDGER_ONLY" "$N_LATER" "$N_HELD" "$N_UNREACH"
}
# refused <reason-token> — the one summary line for a refusal; exit 1, nothing written.
refused() {
  if [[ "$MEASURED" == "1" ]]; then
    echo "ledger-discard: refused (pr=$PR $(counts) reason=$1)"
  else
    echo "ledger-discard: refused (pr=$PR reason=$1)"
  fi
  exit 1
}

# ---------------------------------------------------------------------------
# 2. PR facts (GitHub REST, read-only). Re-read inside the mutex under --execute.
# ---------------------------------------------------------------------------
PR_STATE=""; PR_HEAD=""; PR_LOGIN=""; PR_REF=""; PR_ORIGIN=""; PR_MERGED=""
read_pr() {
  local facts
  gh_rest -X GET "repos/$GH_REPO/pulls/$PR"
  facts=$(jq -e -r --arg repo "$GH_REPO" '
    [ (.state // ""), (.head.sha // ""), (.user.login // ""), (.head.ref // ""),
      (if .head.repo == null then "fork" elif .head.repo.full_name == $repo then "same" else "fork" end),
      (if .merged_at == null then "no" elif (.merged_at | type) == "string" then "yes" else "bad" end) ]
    | @tsv' <<<"$GH_BODY" 2>/dev/null) || cannot_measure transient "pulls/$PR was not the expected JSON"
  IFS=$'\t' read -r PR_STATE PR_HEAD PR_LOGIN PR_REF PR_ORIGIN PR_MERGED <<<"$facts"
  [[ "$PR_STATE" == "open" || "$PR_STATE" == "closed" ]] || cannot_measure transient "pulls/$PR carried an unexpected state"
  is_sha "$PR_HEAD" || cannot_measure transient "pulls/$PR carried no head sha"
  [[ "$PR_MERGED" == "no" || "$PR_MERGED" == "yes" ]] || cannot_measure transient "pulls/$PR carried a malformed merged_at"
  # Only ever used as an exclusion key and a comparison value, never printed.
  [[ "$PR_REF" =~ ^[A-Za-z0-9._/-]+$ ]] || PR_REF=""
}
# pr_gate — the refusals and the skip that PR facts alone decide, in priority order.
pr_gate() {
  if [[ "$PR_ORIGIN" != "same" ]]; then
    echo "::error::ledger-discard: PR #$PR comes from a fork; fork PRs never applied to dev (their CI holds no dev secret), so there is nothing of theirs to discard"
    refused fork
  fi
  if [[ "$PR_MERGED" == "yes" ]]; then
    echo "::error::ledger-discard: PR #$PR is merged; its migrations are main's now and are never discarded here"
    refused merged
  fi
  if [[ "$REQUIRE_CLOSED" == "1" && "$PR_STATE" == "open" ]]; then
    echo "ledger-discard: skipped (pr=$PR reason=reopened)"
    exit 0
  fi
}
read_pr
pr_gate

# ---------------------------------------------------------------------------
# 3. Git facts: the owner repo plus refs/pull/N/head (it survives branch deletion).
# ---------------------------------------------------------------------------
owners_repo "$BASE_BRANCH"
origin_url=$(git -C "$REPO" remote get-url origin 2>/dev/null) || origin_url=""
[[ -n "$origin_url" ]] || cannot_measure config "--repo has no 'origin' remote"
fetch_err="$DLR_TMP/fetch-pr.err"
fetch_rc=0
assert_fixture_dir "$OWN"
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
  || cannot_measure transient "the PR head moved between the API read (${PR_HEAD:0:12}) and the git fetch (${pr_tip:0:12}): a push landed"

# ---------------------------------------------------------------------------
# 4. PR history pairs. First-parent walk, one tree read per commit: for every
#    (F, B) F ever carried, the down blob is F.down.sql's blob in the LAST commit
#    at which F still had blob B (a later down-only edit moves the pairing
#    forward; a later edit of F itself does not).
# ---------------------------------------------------------------------------
declare -A PAIR_DOWN=()   # "F|B" -> down blob id, or "none"
declare -A PAIR_NAME=() PAIR_SLUG=() PAIR_BLOB=()
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
    # Inline top-level test (no subshell per line): directly under MIG_REL only.
    case "$path" in "$MIG_REL"/*) n="${path#"$MIG_REL"/}" ;; *) continue ;; esac
    [[ -n "$n" && "$n" != */* ]] || continue
    name_ok "$n" || continue
    case "$n" in
      *.down.sql) dwn["$n"]="$osha" ;;
      *.sql) [[ -n "${OWN_ON_BASE[$n]:-}" ]] || fwd["$n"]="$osha" ;;
    esac
  done <<<"$tree"
  for n in "${!fwd[@]}"; do
    PAIR_DOWN["$n|${fwd[$n]}"]="${dwn[${n%.sql}.down.sql]:-none}"
    PAIR_NAME["$n"]=1; PAIR_SLUG["$(slug_of "$n")"]=1; PAIR_BLOB["${fwd[$n]}"]=1
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
  assert_fixture_dir "$out"
  for attempt in 1 2; do
    rc=0
    bounded "$GH_TIMEOUT_S" gh api -H 'Accept: application/vnd.github.raw+json' "repos/$GH_REPO/git/blobs/$id" >"$out" 2>/dev/null || rc=$?
    [[ "$rc" == "0" ]] && break
    [[ "$attempt" == "1" ]] && sleep "$wait"
  done
  case "$rc" in
    0) : ;;
    124|137) cannot_measure transient "fetching down blob $id timed out twice (${GH_TIMEOUT_S} s each)" ;;
    *) cannot_measure transient "fetching down blob $id failed twice (gh rc=$rc)" ;;
  esac
  got=$(ogit hash-object --no-filters -- "$out") || cannot_measure transient "hashing down blob $id failed"
  [[ "$got" == "$id" ]] || cannot_measure transient "down blob $id did not hash to its id (the bytes fetched are not that blob)"
}
bs_files=""
for key in "${!PAIR_DOWN[@]}"; do
  d="${PAIR_DOWN[$key]}"
  [[ "$d" == "none" || -n "${DOWN_RAW[$d]:-}" ]] && continue
  is_sha "$d" || cannot_measure transient "a down blob id from ls-tree is not 40-hex"
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
    *) cannot_measure transient "reading the fetched down body $d failed (grep rc=$bsrc)" ;;
  esac
done
if [[ -n "$bs_files" ]]; then
  for f in $(tr ' ' '\n' <<<"$bs_files" | LC_ALL=C sort -u); do
    echo "::error::ledger-discard: the .down.sql paired with $f in PR #$PR contains a backslash; psql would run it as a meta-command, so this PR's rows need the manual reconcile in knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md"
  done
  refused backslash
fi

# ---------------------------------------------------------------------------
# 5-7. Open-PR authority, the mutex, and the in-mutex re-reads (execute).
# ---------------------------------------------------------------------------
author_gate() {
  if [[ "$EXECUTE" == "1" && "$PR_STATE" == "open" && ( -z "$ACTOR" || "$ACTOR" != "$PR_LOGIN" ) ]]; then
    echo "::error::ledger-discard: PR #$PR is open; an open PR's rows can be discarded only by its author. Close the PR to let the close-time run discard them."
    refused open-author
  fi
}
author_gate
if [[ "$EXECUTE" == "1" ]]; then
  [[ -f "$MUTEX_SH" ]] || cannot_measure config "scripts/dev-suite-mutex.sh is missing from the writer's own tree"
  MUTEX_DIR=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/dev-ledger-reconcile-mutex.XXXXXX") \
    || { MUTEX_DIR=""; cannot_measure config "mktemp of the mutex state dir failed"; }
  assert_fixture_dir "$MUTEX_DIR"
  run_id="${GITHUB_RUN_ID:-local}"
  [[ "$run_id" =~ ^[0-9]{1,20}$ ]] || run_id=local
  MUTEX_CALLED=1
  banner=$(DEV_SUITE_MUTEX_STATE_DIR="$MUTEX_DIR" DEV_SUITE_MUTEX_WAIT_S="$DLR_MUTEX_WAIT_S" \
    DEV_SUITE_MUTEX_IDENTITY="reconcile-$run_id-pr$PR" bash "$MUTEX_SH" acquire 2>/dev/null) || true
  # Held iff ANY line is the ACQUIRED banner (WAITING lines come first on a
  # contended acquire). Otherwise the LAST banner token names what happened.
  if grep -qE '^(::warning::)?DEV_SUITE_MUTEX_ACQUIRED( |$)' <<<"$banner"; then
    mtok=DEV_SUITE_MUTEX_ACQUIRED
  else
    mtok=$(grep -oE '^(::warning::)?DEV_SUITE_MUTEX_[A-Z_]+' <<<"$banner" | tail -n 1 | sed 's/^::warning:://' || true)
  fi
  printf '%s\n' "${mtok:-<no banner>}"
  if [[ "$mtok" != "DEV_SUITE_MUTEX_ACQUIRED" ]]; then
    cannot_measure transient "could not hold the dev-suite mutex (${mtok:-no banner}); the writer proceeds only on DEV_SUITE_MUTEX_ACQUIRED"
  fi
  # Inside the mutex: the PR, origin's heads and (below) every holder's PR state
  # are read again, so a push, a reopen, a merge or a new holder that landed while
  # this run waited is seen before the write.
  read_pr
  pr_gate
  [[ "$PR_HEAD" == "$pr_tip" ]] \
    || cannot_measure transient "the PR head moved while this run waited for the mutex (${pr_tip:0:12} -> ${PR_HEAD:0:12}): a push landed"
  author_gate
  owners_refresh "$BASE_BRANCH"
fi
PR_MEMO="$DLR_TMP/prmemo.tsv"
assert_fixture_dir "$PR_MEMO"
: > "$PR_MEMO" || cannot_measure config "creating the pull-request memo failed"

# ---------------------------------------------------------------------------
# 8. The ledger (inside the mutex under --execute), with microsecond applied_at.
#    read_ledger is the ONE ledger-read call site (the post-unit check reuses it).
# ---------------------------------------------------------------------------
LEDGER_OUT=""
LEDGER_RC=0
read_ledger() {
  LEDGER_RC=0
  LEDGER_OUT=$(PGCONNECT_TIMEOUT=10 PGCLIENTENCODING=UTF8 bounded "$PSQL_TIMEOUT_S" \
    psql "$DB_URL" -w --no-psqlrc -tAq --set ON_ERROR_STOP=1 -c "$DLR_LEDGER_SQL" 2>/dev/null) || LEDGER_RC=$?
}
read_ledger
case "$LEDGER_RC" in
  0) : ;;
  124|137) cannot_measure transient "reading public._schema_migrations timed out after ${PSQL_TIMEOUT_S} s (psql rc=$LEDGER_RC)" ;;
  2) cannot_measure connect "could not connect to or authenticate with the dev database (psql rc=2)" ;;
  *) cannot_measure config "the SELECT on public._schema_migrations failed (psql rc=$LEDGER_RC)" ;;
esac
LEDGER_PRE="$LEDGER_OUT"
declare -a L_F=() L_B=() L_T=()
suspicious=0
n_lines=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  n_lines=$((n_lines + 1))
  if [[ ! "$line" =~ ^([^|]*)\|([^|]*)\|([0-9]{20})$ ]]; then suspicious=$((suspicious + 1)); continue; fi
  if ! name_ok "${BASH_REMATCH[1]}"; then suspicious=$((suspicious + 1)); continue; fi
  L_F+=("${BASH_REMATCH[1]}"); L_B+=("${BASH_REMATCH[2]}"); L_T+=("${BASH_REMATCH[3]}")
done <<<"$LEDGER_OUT"
[[ ${#L_F[@]} -gt 0 ]] \
  || cannot_measure config "public._schema_migrations returned no row in the expected <file>|<sha>|<applied_at> shape ($n_lines line(s), $suspicious outside the runner's whitelist) — wrong database or broken query"
if [[ "$suspicious" -gt 0 ]]; then
  echo "::warning::ledger-discard: $suspicious ledger row(s) have a shape or filename outside the runner's whitelist (not echoed); each is treated as a later row"
fi

# ---------------------------------------------------------------------------
# 9. Attribution (the classifier's verdict per missing-on-main row), then
#    eligibility. Ineligible rows are not this PR's; they are not errors.
# ---------------------------------------------------------------------------
declare -A ATTR=()        # F -> 1 when the classifier attributes F's row to PR N
for i in "${!L_F[@]}"; do
  f="${L_F[$i]}"; b="${L_B[$i]}"
  case "$f" in *.down.sql) continue ;; *.sql) : ;; *) continue ;; esac
  [[ -n "${OWN_ON_BASE[$f]:-}" ]] && continue
  sha=""; is_sha "$b" && sha="$b"
  v=$(classify_row "$f" "$sha") || exit 2
  IFS=$'\t' read -r vk _ _ vpr _ <<<"$v"
  case "$vk" in
    closed|closed-grace) [[ "$vpr" == "$PR" ]] && ATTR["$f"]=1 ;;
  esac
done

declare -a E_F=() E_B=() E_T=() E_D=()
declare -A E_KEY=()
held_lines=""
unreach_lines=""
for i in "${!L_F[@]}"; do
  f="${L_F[$i]}"; b="${L_B[$i]}"
  case "$f" in *.down.sql) continue ;; *.sql) : ;; *) continue ;; esac
  [[ -n "${OWN_ON_BASE[$f]:-}" || -n "${OWN_EVER[$f]:-}" ]] && continue
  if ! is_sha "$b" || [[ -z "${PAIR_DOWN[$f|$b]+set}" ]]; then
    if [[ -n "${ATTR[$f]:-}" ]]; then
      # Attributed to this PR, but the applied body is not in its first-parent
      # history under this name: never discarded blind (CTO ruling 1).
      # no-history: no verifiable applied body (no content_sha), or nothing in the
      # PR's history shares its name, slug or blob; force-pushed: the name is in
      # the history but never at the applied blob; slug: only a renamed or
      # renumbered file (same slug or same blob) is.
      if ! is_sha "$b"; then reason=no-history
      elif [[ -n "${PAIR_NAME[$f]:-}" ]]; then reason=force-pushed
      elif [[ -n "${PAIR_SLUG[$(slug_of "$f")]:-}" || -n "${PAIR_BLOB[$b]:-}" ]]; then reason=slug
      else reason=no-history
      fi
      unreach_lines+="$f $reason"$'\n'
      N_UNREACH=$((N_UNREACH + 1))
    fi
    continue
  fi
  # Any OTHER fresh holder of (F, B) whose pull request is open, or that has none,
  # protects the row, whatever its ancestry; a holder whose latest PR closed or
  # merged at its tip does not (CTO ruling 4).
  holders=$(fresh_holders_at_blob "$f" "$b" "$PR_REF") || exit 2
  held=""
  while IFS=$'\t' read -r hb htip; do
    [[ -z "$hb" ]] && continue
    tok=$(branch_pr_state "$hb" "$htip") || exit 2
    case "$tok" in open|none) held="$hb"; break ;; esac
  done <<<"$holders"
  if [[ -n "$held" ]]; then
    held_lines+="$f $(branch_label "$held")"$'\n'
    N_HELD=$((N_HELD + 1))
    continue
  fi
  E_F+=("$f"); E_B+=("$b"); E_T+=("${L_T[$i]}"); E_D+=("${PAIR_DOWN[$f|$b]}")
  E_KEY["$f"]=1
done
N_ELIGIBLE=${#E_F[@]}
MEASURED=1

report_ownership() {
  local rf rx
  while read -r rf rx; do
    [[ -z "$rf" ]] && continue
    printf 'ledger-discard: held-by %s %s\n' "$rf" "$rx"
  done < <(LC_ALL=C sort <<<"$held_lines")
  while read -r rf rx; do
    [[ -z "$rf" ]] && continue
    printf 'ledger-discard: unreachable %s reason=%s\n' "$rf" "$rx"
    echo "::error::ledger-discard: $rf is attributed to PR #$PR (its latest pull request closed at the branch tip), but the applied body is not in the PR's first-parent history under that name ($rx); it is not discarded blind — reconcile it by hand per knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md"
  done < <(LC_ALL=C sort <<<"$unreach_lines")
}

if [[ "$N_ELIGIBLE" -eq 0 ]]; then
  report_ownership
  echo "ledger-discard: nothing to do (pr=$PR $(counts))"
  exit 0
fi

# Execution order: applied_at DESC, then filename DESC.
mapfile -t ORDER < <(for i in "${!E_F[@]}"; do printf '%s\t%s\t%s\n' "${E_T[$i]}" "${E_F[$i]}" "$i"; done \
  | LC_ALL=C sort -t $'\t' -k1,1r -k2,2r | cut -f3)
[[ ${#ORDER[@]} -eq "$N_ELIGIBLE" ]] || cannot_measure transient "ordering the eligible rows failed (sort returned ${#ORDER[@]} of $N_ELIGIBLE)"

# Later rows: any row applied at or after this PR's earliest eligible row that is
# not one of this PR's eligible rows (suspicious rows count as later rows too).
# N_LATER_MAIN counts those that are migrations on the base tip.
t_min="${E_T[${ORDER[$((N_ELIGIBLE - 1))]}]}"
later_lines=""
N_LATER_MAIN=0
for i in "${!L_F[@]}"; do
  [[ -n "${E_KEY[${L_F[$i]}]:-}" ]] && continue
  [[ "${L_T[$i]}" < "$t_min" ]] && continue   # at or after t_min only
  later_lines+="${L_T[$i]} ${L_F[$i]}"$'\n'
  [[ -n "${OWN_ON_BASE[${L_F[$i]}]:-}" ]] && N_LATER_MAIN=$((N_LATER_MAIN + 1))
done
N_LATER=$(( $(grep -c . <<<"$later_lines" || true) + suspicious ))

# ---------------------------------------------------------------------------
# 10-12. Refusal classes per eligible down body; ledger-only rows.
# ---------------------------------------------------------------------------
declare -A NORM=()        # down blob id -> normalized file
declare -A NORM_CLS=()    # down blob id -> refusal classes of its normalized body
declare -A REFUSAL=()
for i in "${ORDER[@]}"; do
  f="${E_F[$i]}"; d="${E_D[$i]}"
  if [[ "$d" == "none" ]]; then
    N_LEDGER_ONLY=$((N_LEDGER_ONLY + 1))
    if [[ "$PR_STATE" == "open" ]]; then
      echo "::error::ledger-discard: $f has no .down.sql paired with applied blob ${E_B[$i]}; an open PR's row is discarded only with its down (a discard without one leaves the objects its body created, and the PR's next CI run re-applies over them)"
      REFUSAL[open-ledger-only]=1
    fi
    continue
  fi
  N_DOWN=$((N_DOWN + 1))
  if [[ -z "${NORM[$d]:-}" ]]; then
    NORM["$d"]="$DLR_TMP/norm-$d.sql"
    cls=$(dlr_classify "${DOWN_RAW[$d]}" "${NORM[$d]}") \
      || cannot_measure transient "the advisory refusal classifier (python3) failed on the down body paired with $f"
    NORM_CLS["$d"]="$cls"
  fi
  cls="${NORM_CLS[$d]}"
  case ",$cls," in *,unparseable,*)
    echo "::error::ledger-discard: the .down.sql paired with $f could not be tokenized (not strict UTF-8, or an unterminated comment, string or dollar quote); it needs the manual reconcile per the learning"
    REFUSAL[unparseable]=1 ;;
  esac
  case ",$cls," in *,transaction-control,*)
    echo "::error::ledger-discard: the .down.sql paired with $f carries transaction control beyond one wrapping BEGIN;/COMMIT; pair; it cannot run inside the single transaction and needs manual handling per the learning"
    REFUSAL[transaction-control]=1 ;;
  esac
  case ",$cls," in *,non-transactional,*)
    echo "::error::ledger-discard: the .down.sql paired with $f carries a statement that cannot run in a transaction or in PL/pgSQL (CONCURRENTLY, VACUUM, ALTER SYSTEM, CREATE/DROP DATABASE or TABLESPACE, DISCARD ALL, COPY FROM STDIN / TO STDOUT); it needs manual handling per the learning"
    REFUSAL[non-transactional]=1 ;;
  esac
  case ",$cls," in *,later-row-sensitive,*)
    if [[ "$N_LATER" -gt 0 && "$ALLOW_LATER" != "1" ]]; then
      echo "::error::ledger-discard: the .down.sql paired with $f uses CASCADE or redefines a shared object (CREATE OR REPLACE, a policy, a grant, ALTER FUNCTION) while $N_LATER row(s) were applied at or after this PR's earliest row (listed as later-row); after reviewing the dry run, re-run with -f allow_later_rows=true"
      REFUSAL[later-row]=1
    fi ;;
  esac
  case ",$cls," in *,destructive,*)
    if [[ "$N_LATER_MAIN" -gt 0 && "$ALLOW_LATER" != "1" ]]; then
      echo "::error::ledger-discard: the .down.sql paired with $f drops, truncates, deletes or updates while $N_LATER_MAIN migration(s) on main were applied at or after this PR's earliest row (listed as later-row); a main migration may have superseded what it removes. After reviewing the dry run, re-run with -f allow_later_rows=true"
      REFUSAL[destructive-superseded]=1
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
report_ownership
# Deterministic reason: the first of the documented priority order that applies.
for r in unparseable transaction-control non-transactional open-ledger-only later-row destructive-superseded; do
  [[ -n "${REFUSAL[$r]:-}" ]] && refused "$r"
done
if [[ "$EXECUTE" != "1" ]]; then
  echo "ledger-discard: dry-run (pr=$PR $(counts))"
  exit 0
fi

# ---------------------------------------------------------------------------
# 14. Execute: ONE unit for the whole PR (apply_discard_unit is the only -f site).
# ---------------------------------------------------------------------------
dlr_md5() { python3 -c 'import hashlib, sys; sys.stdout.write(hashlib.md5(sys.stdin.buffer.read()).hexdigest())'; }
CLAIMED="$DLR_TMP/claimed.txt"
assert_fixture_dir "$CLAIMED"
for i in "${ORDER[@]}"; do printf '%s|%s|%s\n' "${E_F[$i]}" "${E_B[$i]}" "${E_T[$i]}"; done > "$CLAIMED" \
  || cannot_measure config "writing the claimed-row list failed"
LEDGER_POST_WANT=$(grep -vxF -f "$CLAIMED" <<<"$LEDGER_PRE" || true)
SNAP_PRE=$(printf '%s' "$LEDGER_PRE" | dlr_md5) || cannot_measure config "hashing the ledger snapshot failed"
SNAP_POST=$(printf '%s' "$LEDGER_POST_WANT" | dlr_md5) || cannot_measure config "hashing the expected ledger failed"
[[ "$SNAP_PRE" =~ ^[0-9a-f]{32}$ && "$SNAP_POST" =~ ^[0-9a-f]{32}$ ]] || cannot_measure config "the ledger snapshot hash is malformed"

# dlr_tags <body-file> — sets T_OUT/T_IN: random dollar-quote tags whose names do
# not occur in the body (a body holding the tag could close the quote early).
T_OUT=""; T_IN=""
dlr_tags() {
  local body="$1" hex try cand
  local -a cands=()
  if [[ -n "${DLR_TAG_HEX:-}" ]]; then IFS=',' read -r -a cands <<<"$DLR_TAG_HEX"; fi
  for try in 1 2 3 4 5; do
    cand="${cands[$((try - 1))]:-}"
    if [[ -z "$cand" ]]; then
      [[ ${#cands[@]} -gt 0 ]] && break
      cand=$(od -An -tx1 -N8 /dev/urandom 2>/dev/null | tr -d ' \n')
    fi
    [[ "$cand" =~ ^[0-9a-f]{16}$ ]] || continue
    hex="$cand"
    if ! LC_ALL=C grep -qF -e "dlr_o_$hex" -e "dlr_i_$hex" -- "$body"; then
      T_OUT="dlr_o_$hex"; T_IN="dlr_i_$hex"
      return 0
    fi
  done
  cannot_measure transient "no random dollar-quote tag absent from a down body could be chosen"
}

UNIT="$DLR_TMP/unit.sql"
assert_fixture_dir "$UNIT"
declare -a ROW_START=()
{
  printf -- '-- dev-ledger-reconcile: PR #%s, one transaction (psql --single-transaction)\n' "$PR"
  printf "SET LOCAL lock_timeout = '30s';\n"
  printf "SET LOCAL statement_timeout = '120s';\n"
  printf 'LOCK TABLE public._schema_migrations IN SHARE ROW EXCLUSIVE MODE;\n'
  # shellcheck disable=SC2016  # $dlr_snap$ is a literal SQL dollar-quote tag
  printf 'DO $dlr_snap$\nBEGIN\n'
  printf "  IF (SELECT md5(COALESCE(string_agg(%s, chr(10) ORDER BY filename), '')) FROM public._schema_migrations) <> '%s' THEN\n" "$DLR_ROW_EXPR" "$SNAP_PRE"
  printf "    RAISE EXCEPTION 'ledger-discard: the ledger changed after it was read (snapshot mismatch)';\n"
  # shellcheck disable=SC2016  # $dlr_snap$ is a literal SQL dollar-quote tag
  printf '  END IF;\nEND\n$dlr_snap$;\n'
} > "$UNIT" || cannot_measure config "writing the unit failed"
SNAP_END=$(wc -l < "$UNIT")
for i in "${ORDER[@]}"; do
  ROW_START+=("$(( $(wc -l < "$UNIT") + 1 ))")
  if [[ "${E_D[$i]}" != "none" ]]; then dlr_tags "${NORM[${E_D[$i]}]}"; fi
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
      # Server-enforced: PL/pgSQL EXECUTE refuses transaction control, COPY to/from
      # the client, and anything that cannot run inside a transaction block.
      printf 'DO $%s$ BEGIN EXECUTE $%s$\n' "$T_OUT" "$T_IN"
      cat "${NORM[${E_D[$i]}]}"
      printf '\n$%s$; END $%s$;\n' "$T_IN" "$T_OUT"
    fi
  } >> "$UNIT" || cannot_measure config "writing the unit failed"
done
POST_START=$(( $(wc -l < "$UNIT") + 1 ))
{
  # shellcheck disable=SC2016  # $dlr_post$ is a literal SQL dollar-quote tag
  printf 'DO $dlr_post$\nBEGIN\n'
  printf "  IF (SELECT md5(COALESCE(string_agg(%s, chr(10) ORDER BY filename), '')) FROM public._schema_migrations) <> '%s' THEN\n" "$DLR_ROW_EXPR" "$SNAP_POST"
  printf "    RAISE EXCEPTION 'ledger-discard: ledger rows other than the claimed ones changed inside the unit';\n"
  # shellcheck disable=SC2016  # $dlr_post$ is a literal SQL dollar-quote tag
  printf '  END IF;\nEND\n$dlr_post$;\n'
} >> "$UNIT" || cannot_measure config "writing the unit failed"
# Defense in depth: no backslash may reach psql from ANY part of the unit.
ubs=0; has_backslash "$UNIT" || ubs=$?
case "$ubs" in
  0) echo "::error::ledger-discard: the assembled unit contains a backslash; psql would run it as a meta-command"; refused backslash ;;
  1) : ;;
  *) cannot_measure config "reading the assembled unit failed (grep rc=$ubs)" ;;
esac

fail_unit() {  # fail_unit <reason-token> — rc 1, the failed summary
  echo "ledger-discard: failed (pr=$PR $(counts) reason=$1)"
  exit 1
}
apply_discard_unit() {
  local out_f="$DLR_TMP/psql.out" rc=0 tok at row_file="" k
  assert_fixture_dir "$out_f"
  bounded "$DLR_UNIT_TIMEOUT_S" env -u GH_TOKEN -u GITHUB_TOKEN -u DOPPLER_TOKEN PGCONNECT_TIMEOUT=10 PGCLIENTENCODING=UTF8 \
    psql "$DB_URL" -w --no-psqlrc --single-transaction -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -f "$UNIT" >"$out_f" 2>&1 || rc=$?
  if [[ "$rc" == "2" ]]; then
    # A connection failure's text names the host and user: only the rc is reported.
    cannot_measure connect "the dev database connection failed during the discard unit (psql rc=2; its output is withheld because it names the host); run the dry run again to see which rows remain"
  fi
  # psql output can carry RAISE text from PR-authored SQL: fenced and indented,
  # never parsed as a workflow command and never copied into a summary.
  tok=$(od -An -tx1 -N16 /dev/urandom 2>/dev/null | tr -d ' \n')
  [[ "$tok" =~ ^[0-9a-f]{32}$ ]] || tok="$(printf '%08x%08x%08x%08x' "$RANDOM$RANDOM" "$RANDOM$RANDOM" "$RANDOM$RANDOM" "$RANDOM$RANDOM")"
  echo "::stop-commands::$tok"
  tr '\r' ' ' <"$out_f" | sed 's/^/    /'
  echo "::$tok::"
  [[ "$rc" == "0" ]] && return 0
  case "$rc" in
    124|137) cannot_measure transient "the discard unit ran past ${DLR_UNIT_TIMEOUT_S} s and was killed (psql rc=$rc); its single transaction did not commit" ;;
  esac
  if grep -qE 'ERROR: +55P03:' "$out_f"; then
    cannot_measure transient "the discard unit waited past lock_timeout (30 s) for a lock (SQLSTATE 55P03); its single transaction rolled back"
  fi
  if grep -qE 'ERROR: +57014:' "$out_f"; then
    cannot_measure transient "a discard-unit statement ran past statement_timeout (120 s) (SQLSTATE 57014); its single transaction rolled back"
  fi
  at=$(sed -n "s#^psql:${UNIT//#/\\#}:\\([0-9][0-9]*\\):.*#\\1#p" "$out_f" | head -n 1)
  if [[ "$at" =~ ^[0-9]+$ ]] && (( at <= SNAP_END )); then
    cannot_measure transient "the ledger changed between the read and the unit's lock (the snapshot check at unit line $at failed); the transaction rolled back"
  fi
  if [[ "$at" =~ ^[0-9]+$ ]] && (( at >= POST_START )); then
    echo "::error::ledger-discard: the unit's down bodies changed ledger rows other than this PR's (the closing check failed, psql rc=$rc); the transaction rolled back and nothing was changed"
    fail_unit post-check
  fi
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
  fail_unit unit
}
apply_discard_unit

# ---------------------------------------------------------------------------
# 15. Post-unit check: re-read the ledger (the same call site). Every claimed
#     (F, B) must be gone and no other row may have changed.
# ---------------------------------------------------------------------------
read_ledger
if [[ "$LEDGER_RC" != "0" ]]; then
  echo "::error::ledger-discard: the unit exited 0 but re-reading the ledger failed (psql rc=$LEDGER_RC); run the dry run to confirm which rows remain"
  fail_unit post-read
fi
if [[ "$LEDGER_OUT" != "$LEDGER_POST_WANT" ]]; then
  while IFS= read -r cl; do
    [[ -z "$cl" ]] && continue
    if grep -qxF -- "$cl" <<<"$LEDGER_OUT"; then
      echo "::error::ledger-discard: after the unit the ledger still holds ${cl%%|*} at its applied blob; psql reported success, so the unit did not commit what it claimed"
    fi
  done < "$CLAIMED"
  n_other=$(diff <(grep -vxF -f "$CLAIMED" <<<"$LEDGER_OUT" || true) <(printf '%s\n' "$LEDGER_POST_WANT") | grep -c '^[<>]' || true)
  echo "::error::ledger-discard: the ledger after the unit is not the ledger before it minus the claimed rows ($n_other other line(s) differ); check the run log's psql output"
  fail_unit post-check
fi

if [[ "$PR_STATE" == "closed" ]]; then
  for i in "${ORDER[@]}"; do
    [[ "${E_D[$i]}" == "none" ]] || continue
    echo "::warning::ledger-discard: ${E_F[$i]} has no .down.sql paired with applied blob ${E_B[$i]}; objects its body created stay on dev"
  done
fi
for i in "${ORDER[@]}"; do
  echo "::notice::ledger-discard: discarded ${E_F[$i]} (applied blob ${E_B[$i]}, down ${E_D[$i]}) for PR #$PR"
done
echo "note: PostgREST picks up the schema change on its ~10-min schema-cache poll (NOTIFY does not reach it over the pooler, #4285)"
echo "ledger-discard: executed (pr=$PR eligible=$N_ELIGIBLE discarded=$N_ELIGIBLE down=$N_DOWN ledger-only=$N_LEDGER_ONLY held-by=$N_HELD unreachable=$N_UNREACH)"
exit 0
