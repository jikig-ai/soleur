#!/usr/bin/env bash
# dev-ledger-parity: per-ref ledger checks over the ONE shared dev Supabase
# project (#8521, #8520; ADR-061 amendment 2026-09-23).
#
# PR CI (tenant-integration) applies each pull request's NOT-YET-MERGED
# migrations to shared dev, and run-migrations.sh never re-applies a filename it
# has already ledgered in public._schema_migrations. Three arms then turn main
# red:
#
#   A1  edited after apply   — the PR edits F after CI applied it; dev keeps the
#                              old body, the PR's own tests ran against it, and
#                              main's drift probe reports content drift (#8521).
#   A2  renamed after apply  — the PR renames/renumbers F; the old name stays
#                              ledgered and becomes an orphan.
#   A4  deleted after apply  — the PR drops F; same orphan.
#   in-flight                — ANY open PR's applied row is "missing on main"
#                              for every push until it merges (2026-09-22).
#
# Two subcommands, one ownership primitive:
#
#   check             PR side. Fails A1/A2/A4 BEFORE merge, and before apply
#                     (A1 makes the runner skip the stale file, so a dependent
#                     migration would otherwise fail inside apply first). The
#                     workflow runs the BASE-REF copy of this script, extracted
#                     and executed in one step.
#   classify-missing  main side. The drift probe pipes its missing-on-main rows
#                     here; a row a fresh, unmerged live branch holds is
#                     in-flight (warning), everything else stays blocking.
#
# Why fail instead of re-applying: re-running an edited idempotent file leaves
# the objects the old body created and the new body does not touch — silent
# residue (#8520: the 075 FOR ALL policy, the 122 index). A migration applied to
# shared dev is immutable, merged or not; the change ships as a new file.
#
# Side effects: one fixed SELECT on the ledger, and git work in a bare owner repo
# (a throwaway one removed on exit, or $DLP_OWNERS_CACHE when the caller wants to
# reuse one across calls). The checkout is never written: no promisor config,
# no shallow entries, no refs. Nothing writes to dev or prd.
#
# Only TOP-LEVEL migrations count: the runner globs migrations/*.sql, so a file
# in a subdirectory is never applied and never owns a ledger row. Tree reads on
# the checkout use `git -C "$REPO" ls-tree … ':(top,literal)<dir>/'`, never a
# cwd-relative path: run-migrations.sh's cwd-relative ls-tree is exactly how its
# own unmerged gate went inert in CI (#8606).

set -uo pipefail
export LC_ALL=C
export GIT_TERMINAL_PROMPT=0
# Location variables would retarget every `git -C` below at another repository.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE

readonly MIG_REL="apps/web-platform/supabase/migrations"
readonly LEDGER_SQL="SELECT filename || '|' || COALESCE(content_sha, '') FROM public._schema_migrations ORDER BY filename"
readonly STALE_DAYS=30
readonly FUTURE_SKEW_S=86400
readonly FETCH_TIMEOUT_S=60
readonly PSQL_TIMEOUT_S=60
readonly ZERO_SHA="0000000000000000000000000000000000000000"

usage() {
  cat <<'USAGE'
Usage:
  dev-ledger-parity.sh check --base <origin/branch> --repo <dir> [--head-branch <name>]
  dev-ledger-parity.sh classify-missing --base-branch <name> --repo <dir>   # stdin: "<file>|<sha>" lines
  dev-ledger-parity.sh --help

check (PR side; reads DATABASE_URL_POOLER, else DATABASE_URL):
  Compares the COMMITTED tree (git ls-tree HEAD — the bytes main's drift probe
  will compare after merge, not the working copy) with the dev ledger.
  For every top-level forward migration absent from <base>, the dev ledger
  either lacks it or records exactly this tree's blob (A1). A ledger row on
  neither <base> nor this tree that matches one of this PR's files by blob or
  slug (A2), or a blob this PR's branch history carried (A4), is a violation —
  unless a fresh live branch holds that row by exact name AND exact blob, and
  did not inherit it from this PR's history.
  Summary line:
    ledger-parity: clean|RED (unmerged=N ledgered-match=N pending=N ledger-rows=N candidates=N skipped-owned=N violations=N)

classify-missing (main side; used by .github/actions/dev-migration-drift-probe):
  One verdict per stdin line, in input order, tab-separated:
    in-flight <file> <branch> <exact|blob|slug>
    stale     <file> <branch> <age-days|future-dated|undated>
    merged    <file>          (on the base tip now: it merged after the caller probed)
    orphan    <file>
  A row is in-flight only if its name never appeared in <base-branch>'s history
  and a live branch not merged into <base-branch>, whose head commit is dated
  within the last 30 whole days, holds it among its top-level files that are
  NOT on <base-branch>. gh-readonly-queue/* refs never own anything. A head
  dated more than a day in the future, or undated, counts as stale.
  Summary line (stderr):
    ledger-classify: in-flight=N stale=M merged=J orphan=K

Environment:
  DLP_OWNERS_CACHE  optional path of a bare repo to reuse across calls (fetched
                    with --prune each time). Only point it at a directory that
                    code you do not trust cannot write.

Exit codes:
  0  clean / classified
  1  violation(s), each named via ::error::   (check only)
  2  cannot measure — never a verdict on the migrations. The message says
     "re-run the job" (timeouts, network) or "a re-run will not help"
     (configuration, SQL error, a missing branch), naming the failed step.

Repair paths: knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md
USAGE
}

MODE=""
CLEAN=()
# shellcheck disable=SC2329  # invoked by the EXIT trap below
cleanup() { [[ ${#CLEAN[@]} -gt 0 ]] && rm -rf "${CLEAN[@]}"; return 0; }
trap cleanup EXIT

# cannot_measure <transient|config|connect> <message> — exit 2, annotated.
cannot_measure() {
  local class="$1" msg="$2" suffix
  case "$class" in
    transient) suffix="the guard could not measure (not a verdict on the migrations); re-run the job" ;;
    connect) suffix="the guard could not measure (not a verdict on the migrations); re-run the job once, and if it repeats check the Doppler dev_scheduled database credentials" ;;
    *) suffix="the guard could not measure (not a verdict on the migrations); check the Doppler dev_scheduled config / workflow wiring — a re-run will not help" ;;
  esac
  echo "::error::dev-ledger-parity ${MODE:-}: cannot measure ($class): ${msg} — ${suffix}" >&2
  exit 2
}

need_value() {
  # A flag as the last argument would otherwise loop forever on `shift 2`.
  [[ $# -ge 2 ]] && return 0
  echo "::error::dev-ledger-parity: $1 requires a value" >&2
  exit 2
}

is_sha() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }
# The runner's own filename whitelist (run-migrations.sh), plus non-empty.
name_ok() {
  [[ -n "$1" ]] || return 1
  case "$1" in *[!a-zA-Z0-9._-]*) return 1 ;; esac
  return 0
}
slug_of() {
  if [[ "$1" =~ ^[0-9]+_(.*)$ ]]; then printf '%s' "${BASH_REMATCH[1]}"; else printf '%s' "$1"; fi
}
branch_label() {
  if [[ "$1" =~ ^[A-Za-z0-9._/-]+$ ]]; then printf '%s' "$1"; else printf '<unprintable-branch>'; fi
}
# top_level_name <path> — the basename when <path> is directly under MIG_REL, else "".
top_level_name() {
  local rest="${1#"$MIG_REL/"}"
  [[ "$rest" != "$1" && "$rest" != */* ]] && printf '%s' "$rest"
  return 0
}

TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then TIMEOUT_BIN=timeout
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_BIN=gtimeout
fi
bounded() {  # bounded <seconds> <cmd...>
  local s="$1"; shift
  if [[ -n "$TIMEOUT_BIN" ]]; then "$TIMEOUT_BIN" -k 5 "$s" "$@"; else "$@"; fi
}

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

# --repo and every root derived from it must be absolute (the git -C operands below).
_assert_repo_root() {
  [[ -n "$1" && -d "$1/$MIG_REL" ]] || cannot_measure config "--repo '${1:-<unset>}' does not contain $MIG_REL"
  assert_fixture_dir "$1"
}

# ---------------------------------------------------------------------------
# Ownership primitive. One bare owner repo per invocation, one full-history
# blobless fetch of every origin head. Full history (no --depth) is what makes
# the main-history and PR-history lookups correct; blob:none keeps it cheap.
# ---------------------------------------------------------------------------
OWN=""
BASE_OWN=""
OWNERS=""   # file: branch<TAB>fresh|stale<TAB>age<TAB>file<TAB>blob<TAB>slug
declare -A OWN_ON_BASE=()   # top-level names on the base tip (owner repo's fetch)
declare -A OWN_EVER=()      # top-level names that ever appeared in base history
ogit() { GIT_NO_LAZY_FETCH=1 git -C "$OWN" "$@"; }

# fetch_reason <rc> <errfile> — a classification token, never the raw stderr.
fetch_reason() {
  if [[ "$1" == "124" || "$1" == "137" ]]; then printf 'timeout'; return 0; fi
  if grep -qiE 'authentication failed|could not read username|permission denied|403' "$2" 2>/dev/null; then printf 'auth'; return 0; fi
  if grep -qiE 'could not resolve host|name or service not known' "$2" 2>/dev/null; then printf 'dns'; return 0; fi
  if grep -qiE 'timed out|connection reset|early eof|remote end hung up' "$2" 2>/dev/null; then printf 'network'; return 0; fi
  if grep -qiE 'does not appear to be a git repository|not found' "$2" 2>/dev/null; then printf 'no-repository'; return 0; fi
  printf 'other'
}

owners_repo() {
  local base_branch="$1"
  [[ -n "$OWN" ]] && return 0
  assert_fixture_dir "$REPO"
  if [[ -n "${DLP_OWNERS_CACHE:-}" ]]; then
    OWN="$DLP_OWNERS_CACHE"
    assert_fixture_dir "$OWN"
    if [[ ! -f "$OWN/HEAD" ]]; then
      if ! mkdir -p "$OWN" || ! git init -q --bare "$OWN"; then cannot_measure config "git init of the owner cache failed"; fi
    fi
  else
    OWN=$(mktemp -d "${TMPDIR:-/tmp}/dev-ledger-owners.XXXXXX") || cannot_measure config "mktemp failed"
    assert_fixture_dir "$OWN"
    CLEAN+=("$OWN")
    git init -q --bare "$OWN" || cannot_measure config "git init of the throwaway owner repo failed"
  fi

  local url errf rc=0 reason class
  url=$(git -C "$REPO" remote get-url origin 2>/dev/null) || url=""
  [[ -n "$url" ]] || cannot_measure config "--repo has no 'origin' remote"
  errf=$(mktemp "${TMPDIR:-/tmp}/dev-ledger-fetch.XXXXXX") || cannot_measure config "mktemp failed"
  CLEAN+=("$errf")
  # --prune: a reused cache must not keep a deleted branch as an owner.
  bounded "$FETCH_TIMEOUT_S" git -C "$OWN" fetch -q --prune --no-tags --filter=blob:none "$url" \
    '+refs/heads/*:refs/owners/*' 2>"$errf" || rc=$?
  # A server without filter support prints "filtering not recognized" and still
  # succeeds with full objects — only the exit code decides.
  if [[ "$rc" != "0" ]]; then
    reason=$(fetch_reason "$rc" "$errf")
    class=transient
    case "$reason" in auth|no-repository) class=config ;; esac
    cannot_measure "$class" "fetching origin branch heads failed (git rc=$rc, $reason)"
  fi

  BASE_OWN="refs/owners/$base_branch"
  ogit rev-parse --verify --quiet "$BASE_OWN^{commit}" >/dev/null \
    || cannot_measure config "base branch '$base_branch' is not a branch on origin"
  local base_sha
  base_sha=$(ogit rev-parse "$BASE_OWN") || cannot_measure transient "rev-parse of the base failed in the owner repo"

  local out path n
  out=$(ogit ls-tree --name-only "$BASE_OWN" -- ":(top,literal)$MIG_REL/") \
    || cannot_measure transient "ls-tree of $base_branch failed in the owner repo"
  while IFS= read -r path; do
    n=$(top_level_name "$path"); [[ -n "$n" ]] && OWN_ON_BASE["$n"]=1
  done <<<"$out"
  # One history pass instead of a `log -1` per row. Default history
  # simplification can only ADD names (a side branch that added then removed a
  # file), which only ever yields more `orphan` verdicts — the blocking side.
  out=$(ogit log --format= --name-only --no-renames "$BASE_OWN" -- ":(top,literal)$MIG_REL/") \
    || cannot_measure transient "history of $base_branch failed in the owner repo"
  while IFS= read -r path; do
    n=$(top_level_name "$path"); [[ -n "$n" ]] && OWN_EVER["$n"]=1
  done <<<"$out"

  # Heads not merged into the base, with their commit dates.
  local refs now sha date ref name age state
  refs=$(ogit for-each-ref --no-merged="$BASE_OWN" --format='%(objectname) %(committerdate:unix) %(refname)' refs/owners/) \
    || cannot_measure transient "for-each-ref failed in the owner repo"
  now=$(date +%s)
  local -A sha_names=() name_state=() name_age=()
  while read -r sha date ref; do
    [[ -z "$ref" ]] && continue
    name="${ref#refs/owners/}"
    [[ "$name" == "$base_branch" ]] && continue
    case "$name" in gh-readonly-queue/*) continue ;; esac
    if [[ ! "$date" =~ ^[0-9]+$ ]]; then
      state=stale; age=undated
    elif (( date > now + FUTURE_SKEW_S )); then
      # A pusher sets the committer date; a future one must not keep a branch fresh forever.
      state=stale; age=future-dated
    else
      age=$(( (now - date) / 86400 ))
      state=fresh
      (( age > STALE_DAYS )) && state=stale
    fi
    name_state["$name"]="$state"; name_age["$name"]="$age"
    sha_names["$sha"]+="$name"$'\n'
  done <<<"$refs"

  OWNERS="$(mktemp "${TMPDIR:-/tmp}/dev-ledger-owners-tsv.XXXXXX")" || cannot_measure config "mktemp failed"
  CLEAN+=("$OWNERS")
  [[ ${#sha_names[@]} -eq 0 ]] && return 0
  # One diff-tree for every head: files ADDED relative to the base tip are
  # exactly the head's files absent from the base (a modified base file is
  # nobody's).
  local input="" s cur="" line meta mode_new blob_new status f b
  for s in "${!sha_names[@]}"; do input+="$s $base_sha"$'\n'; done
  out=$(printf '%s' "$input" | ogit diff-tree --stdin -r --no-renames --diff-filter=A -- ":(top,literal)$MIG_REL/") \
    || cannot_measure transient "diff-tree of branch heads failed in the owner repo"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ ^[0-9a-f]{40}$ ]]; then cur="$line"; continue; fi
    meta="${line%%$'\t'*}"; path="${line#*$'\t'}"
    read -r _ mode_new _ blob_new status <<<"${meta#:}"
    [[ "$status" == "A" ]] || continue
    case "$mode_new" in 100644|100755|120000) : ;; *) continue ;; esac
    f=$(top_level_name "$path"); [[ -n "$f" ]] || continue
    case "$f" in *.down.sql) continue ;; *.sql) : ;; *) continue ;; esac   # the runner applies forward *.sql only
    name_ok "$f" || continue
    [[ -n "${OWN_ON_BASE[$f]:-}" ]] && continue
    while IFS= read -r b; do
      [[ -z "$b" ]] && continue
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$b" "${name_state[$b]}" "${name_age[$b]}" "$f" "$blob_new" "$(slug_of "$f")" >> "$OWNERS"
    done <<<"${sha_names[$cur]:-}"
  done <<<"$out"
}

# owner_lookup <tier> <value> <state> [<exclude-branch>] [<blob>] — the
# lexically smallest matching branch as "branch<TAB>age"; empty when none.
# Tier "exactblob" requires both the name (<value>) and the blob (<blob>).
# Strings are compared as strings (awk would compare 0e… hashes numerically).
owner_lookup() {
  awk -F'\t' -v tier="$1" -v val="$2" -v st="$3" -v ex="${4:-}" -v bl="${5:-}" '
    ($2 "") != (st "") || ($1 "") == (ex "") { next }
    (tier == "exact" && ($4 "") == (val "")) ||
    (tier == "blob" && ($5 "") == (val "")) ||
    (tier == "slug" && ($6 "") == (val "")) ||
    (tier == "exactblob" && ($4 "") == (val "") && ($5 "") == (bl "")) {
      if (best == "" || ($1 "") < best) { best = $1 ""; age = $3 "" }
    }
    END { if (best != "") print best "\t" age }' "$OWNERS" || cannot_measure transient "owner lookup failed"
}

# owners_all <tier> <value> <state> <exclude> <blob> — every matching branch, one per line.
owners_all() {
  awk -F'\t' -v tier="$1" -v val="$2" -v st="$3" -v ex="${4:-}" -v bl="${5:-}" '
    ($2 "") != (st "") || ($1 "") == (ex "") { next }
    tier == "exactblob" && ($4 "") == (val "") && ($5 "") == (bl "") { print $1 }' "$OWNERS" \
    || cannot_measure transient "owner lookup failed"
}

# ---------------------------------------------------------------------------
# classify-missing
# ---------------------------------------------------------------------------
classify_row() {
  local f="$1" sha="$2" hit tier st
  if [[ -n "${OWN_ON_BASE[$f]:-}" ]]; then
    printf 'merged\t%s\n' "$f"   # merged after the caller's probe fetched the base
    return 0
  fi
  if [[ -n "${OWN_EVER[$f]:-}" ]]; then
    printf 'orphan\t%s\n' "$f"
    return 0
  fi
  for st in fresh stale; do
    for tier in exact blob slug; do
      case "$tier" in
        exact) hit=$(owner_lookup exact "$f" "$st") || exit 2 ;;
        blob) hit=""; if is_sha "$sha"; then hit=$(owner_lookup blob "$sha" "$st") || exit 2; fi ;;
        slug) hit=$(owner_lookup slug "$(slug_of "$f")" "$st") || exit 2 ;;
      esac
      [[ -z "$hit" ]] && continue
      if [[ "$st" == "fresh" ]]; then
        printf 'in-flight\t%s\t%s\t%s\n' "$f" "$(branch_label "${hit%%$'\t'*}")" "$tier"
      else
        printf 'stale\t%s\t%s\t%s\n' "$f" "$(branch_label "${hit%%$'\t'*}")" "${hit##*$'\t'}"
      fi
      return 0
    done
  done
  printf 'orphan\t%s\n' "$f"
}

cmd_classify_missing() {
  MODE=classify-missing
  local base_branch="" line f sha verdict
  REPO=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base-branch) need_value "$@"; base_branch="$2"; shift 2 ;;
      --repo) need_value "$@"; REPO="$2"; shift 2 ;;
      *) echo "::error::dev-ledger-parity classify-missing: unknown argument" >&2; exit 2 ;;
    esac
  done
  [[ "$base_branch" =~ ^[A-Za-z0-9._/-]+$ ]] || cannot_measure config "--base-branch is missing or unsafe"
  _assert_repo_root "$REPO"

  local -a files=() shas=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^([^|]*)\|([^|]*)$ ]] || cannot_measure config "stdin line $(( ${#files[@]} + 1 )) is not <file>|<sha>"
    f="${BASH_REMATCH[1]}"; sha="${BASH_REMATCH[2]}"
    name_ok "$f" || cannot_measure config "stdin line $(( ${#files[@]} + 1 )) carries an unsafe filename"
    # An empty sha is a legitimate pre-content-sha ledger row (blob tier skipped).
    [[ -z "$sha" ]] || is_sha "$sha" || cannot_measure config "stdin line $(( ${#files[@]} + 1 )) carries a malformed sha"
    files+=("$f"); shas+=("$sha")
  done

  local n_in=0 n_st=0 n_me=0 n_or=0 i
  if [[ ${#files[@]} -gt 0 ]]; then
    owners_repo "$base_branch"
    for i in "${!files[@]}"; do
      verdict=$(classify_row "${files[$i]}" "${shas[$i]}") || exit 2
      printf '%s\n' "$verdict"
      case "${verdict%%$'\t'*}" in
        in-flight) n_in=$((n_in + 1)) ;;
        stale) n_st=$((n_st + 1)) ;;
        merged) n_me=$((n_me + 1)) ;;
        orphan) n_or=$((n_or + 1)) ;;
      esac
    done
  fi
  echo "ledger-classify: in-flight=$n_in stale=$n_st merged=$n_me orphan=$n_or" >&2
  exit 0
}

# ---------------------------------------------------------------------------
# check
# ---------------------------------------------------------------------------
cmd_check() {
  MODE=check
  local base="" head_branch=""
  REPO=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base) need_value "$@"; base="$2"; shift 2 ;;
      --repo) need_value "$@"; REPO="$2"; shift 2 ;;
      --head-branch) need_value "$@"; head_branch="$2"; shift 2 ;;
      *) echo "::error::dev-ledger-parity check: unknown argument" >&2; exit 2 ;;
    esac
  done
  [[ -n "$base" ]] || cannot_measure config "--base is required"
  [[ "$base" == origin/* || "$base" == refs/remotes/origin/* ]] \
    || cannot_measure config "--base must name an origin branch (origin/<branch>)"
  _assert_repo_root "$REPO"
  git -C "$REPO" rev-parse --verify --quiet "$base^{commit}" >/dev/null \
    || cannot_measure config "cannot resolve --base '$base'"
  git -C "$REPO" rev-parse --verify --quiet "HEAD^{commit}" >/dev/null \
    || cannot_measure config "--repo has no HEAD commit"
  if [[ -n "$head_branch" ]] && ! git check-ref-format --branch "$head_branch" >/dev/null 2>&1; then
    echo "::warning::ledger-parity: --head-branch is not a valid branch name; the PR-history check (A4) is skipped"
    head_branch=""
  fi
  local base_branch="${base#refs/remotes/}"
  base_branch="${base_branch#origin/}"

  # ---- population from COMMITTED trees: M (top-level on base), T (in HEAD), U (unmerged) ----
  local -A on_base=() in_tree=() blob=()
  local -a unmerged=()
  local out path f meta mode type sha unsafe=0
  out=$(git -C "$REPO" ls-tree --name-only "$base" -- ":(top,literal)$MIG_REL/") \
    || cannot_measure transient "ls-tree of '$base' failed"
  while IFS= read -r path; do
    f=$(top_level_name "$path"); [[ -n "$f" ]] && on_base["$f"]=1
  done <<<"$out"
  out=$(git -C "$REPO" ls-tree HEAD -- ":(top,literal)$MIG_REL/") \
    || cannot_measure transient "ls-tree of HEAD failed"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    meta="${line%%$'\t'*}"; path="${line#*$'\t'}"
    read -r mode type sha <<<"$meta"
    [[ "$type" == "blob" ]] || continue
    : "$mode"
    f=$(top_level_name "$path"); [[ -n "$f" ]] || continue
    case "$f" in *.sql) : ;; *) continue ;; esac
    # The runner warns and skips such a file, so it never reaches the ledger.
    if ! name_ok "$f"; then unsafe=$((unsafe + 1)); continue; fi
    case "$f" in *.down.sql) continue ;; esac
    in_tree["$f"]=1
    [[ -n "${on_base[$f]:-}" ]] && continue
    unmerged+=("$f")
    blob["$f"]="$sha"
  done <<<"$out"
  if [[ "$unsafe" -gt 0 ]]; then
    echo "::warning::ledger-parity: $unsafe migration filename(s) in this tree are outside the runner's whitelist [a-zA-Z0-9._-] (not echoed); the runner skips them, so rename them"
  fi

  # ---- ledger: read on EVERY run, so the pooler path and the floor always run ----
  local db="${DATABASE_URL_POOLER:-${DATABASE_URL:-}}"
  [[ -n "$db" ]] || cannot_measure config "neither DATABASE_URL_POOLER nor DATABASE_URL is set"
  command -v psql >/dev/null 2>&1 || cannot_measure config "psql not found on PATH"
  local ledger_out rc=0
  ledger_out=$(PGCONNECT_TIMEOUT=10 bounded "$PSQL_TIMEOUT_S" psql "$db" -w --no-psqlrc -tAq --set ON_ERROR_STOP=1 -c "$LEDGER_SQL" 2>/dev/null) || rc=$?
  # psql stderr can carry the user and host, so only its exit code is reported.
  case "$rc" in
    0) : ;;
    124|137) cannot_measure transient "reading public._schema_migrations timed out (psql rc=$rc)" ;;
    2) cannot_measure connect "could not connect to or authenticate with the dev database (psql rc=2)" ;;
    *) cannot_measure config "reading public._schema_migrations failed (psql rc=$rc)" ;;
  esac
  local -A ledger=()
  local -a ledger_names=()
  local rows=0 suspicious=0 lf lsha
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Exactly one delimiter: a "|" inside a hand-written filename must not shift the sha.
    if [[ ! "$line" =~ ^([^|]*)\|([^|]*)$ ]]; then suspicious=$((suspicious + 1)); continue; fi
    lf="${BASH_REMATCH[1]}"; lsha="${BASH_REMATCH[2]}"
    if ! name_ok "$lf"; then suspicious=$((suspicious + 1)); continue; fi
    [[ -z "${ledger[$lf]+set}" ]] && ledger_names+=("$lf")
    ledger["$lf"]="$lsha"
    rows=$((rows + 1))
  done <<<"$ledger_out"
  [[ "$rows" -gt 0 ]] || cannot_measure config "the dev ledger returned zero rows — wrong database or broken query"
  if [[ "$suspicious" -gt 0 ]]; then
    echo "::warning::ledger-parity: skipped $suspicious ledger row(s) whose shape or filename is outside the runner's whitelist (not echoed)"
  fi

  local violations=0 matched=0 pending=0 candidates=0 skipped_owned=0 applied
  # ---- A1: every unmerged file is absent from the ledger or ledgered at its blob ----
  for f in "${unmerged[@]}"; do
    if [[ -z "${ledger[$f]+set}" ]]; then pending=$((pending + 1)); continue; fi
    applied="${ledger[$f]}"
    if ! is_sha "$applied"; then
      echo "::error::$f: the ledger row carries no verifiable content_sha, so this PR's unmerged migration cannot be shown to match what dev applied. Give the file a new number AND a new slug (a new name is applied fresh), or ask a dev operator to reconcile the row per the learning §Content drift (#8605)."
      violations=$((violations + 1))
    elif [[ "$applied" != "${blob[$f]}" ]]; then
      echo "::error::$f: dev applied this unmerged migration at blob $applied, but this tree has ${blob[$f]}. The runner never re-applies a ledgered filename, so this PR's tests ran against the OLD body and main's drift probe will fail after merge (#8521). Fix without a database write: restore the applied body (git show $applied > $MIG_REL/$f; if the object is not local: gh api repos/\$GITHUB_REPOSITORY/git/blobs/$applied --jq .content | base64 -d > $MIG_REL/$f), then put the change in a NEW migration numbered after it. A migration applied to dev is as immutable as a merged one (#8583). If git log --all --find-object=$applied finds nothing on your side, another branch applied a same-named file: give yours a new number and slug. If you cannot recover the body and hold no dev credentials, ask a dev operator to reconcile per knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md §Content drift (#8605 tracks self-service)."
      violations=$((violations + 1))
    else
      matched=$((matched + 1))
    fi
  done

  # ---- candidates: ledger rows on neither base nor this tree, in ledger order ----
  local g gsha how match_f fu hist_loaded=0 owner add anc c3 c4 what hint rawlog
  local -A pr_blobs=()
  for g in "${ledger_names[@]}"; do
    [[ -n "${on_base[$g]:-}" || -n "${in_tree[$g]:-}" ]] && continue
    candidates=$((candidates + 1))
    gsha="${ledger[$g]}"
    is_sha "$gsha" || gsha=""
    how=""; match_f=""
    if [[ -n "$gsha" ]]; then
      for fu in "${unmerged[@]}"; do
        if [[ "${blob[$fu]}" == "$gsha" ]]; then how=blob; match_f="$fu"; break; fi
      done
    fi
    if [[ -z "$how" ]]; then
      for fu in "${unmerged[@]}"; do
        if [[ "$(slug_of "$fu")" == "$(slug_of "$g")" ]]; then how=slug; match_f="$fu"; break; fi
      done
    fi
    if [[ -z "$how" && -n "$head_branch" && -n "$gsha" ]]; then
      if [[ "$hist_loaded" == "0" ]]; then
        owners_repo "$base_branch"
        ogit rev-parse --verify --quiet "refs/owners/$head_branch^{commit}" >/dev/null \
          || cannot_measure config "head branch '$(branch_label "$head_branch")' is not a branch on origin"
        # --no-renames is load-bearing: rename detection reads blob CONTENTS,
        # which the blobless owner repo does not have (fatal under GIT_NO_LAZY_FETCH).
        rawlog=$(ogit log --raw --no-renames --no-abbrev --format= "$BASE_OWN..refs/owners/$head_branch" -- ":(top,literal)$MIG_REL/") \
          || cannot_measure transient "log of the PR branch history failed"
        while read -r _ _ c3 c4 _; do
          [[ -n "$c3" && "$c3" != "$ZERO_SHA" ]] && pr_blobs["$c3"]=1
          [[ -n "$c4" && "$c4" != "$ZERO_SHA" ]] && pr_blobs["$c4"]=1
        done <<<"$rawlog"
        hist_loaded=1
      fi
      [[ -n "${pr_blobs[$gsha]:-}" ]] && how=history
    fi
    [[ -z "$how" ]] && continue

    # Another PR's in-flight row: a fresh live branch holds it by exact name AND
    # exact blob, and did NOT inherit it from this PR (a stacked or backup branch
    # forked before the rename would otherwise launder this PR's violation).
    owner=""
    if [[ -n "$gsha" ]]; then
      owners_repo "$base_branch"
      local cand_list b
      cand_list=$(owners_all exactblob "$g" fresh "$head_branch" "$gsha") || exit 2
      while IFS= read -r b; do
        [[ -z "$b" ]] && continue
        if [[ -n "$head_branch" ]] && ogit rev-parse --verify --quiet "refs/owners/$head_branch^{commit}" >/dev/null; then
          add=$(ogit log --no-renames --diff-filter=A -1 --format=%H "refs/owners/$b" -- ":(top,literal)$MIG_REL/$g") \
            || cannot_measure transient "history of an owner branch failed"
          if [[ -n "$add" ]]; then
            anc=0
            ogit merge-base --is-ancestor "$add" "refs/owners/$head_branch" 2>/dev/null || anc=$?
            case "$anc" in
              0) continue ;;   # inherited from this PR's history: not an independent owner
              1) : ;;
              *) cannot_measure transient "merge-base failed for an owner branch (rc=$anc)" ;;
            esac
          fi
        fi
        owner="$b"; break
      done <<<"$cand_list"
    fi
    if [[ -n "$owner" ]]; then
      what="$match_f"
      [[ -z "$what" ]] && what="this branch's history"
      echo "::warning::ledger-parity: $g matches $what by $how but is held by live branch $(branch_label "$owner") at the applied blob — treated as that PR's in-flight row, not this PR's"
      skipped_owned=$((skipped_owned + 1))
      continue
    fi
    violations=$((violations + 1))
    if [[ "$how" == "history" ]]; then
      echo "::error::$g is ledgered on dev but is not on $base, not in this tree, and no other fresh live branch holds it at the applied blob. This PR's branch history carried exactly that body (blob $gsha) — matched by history — so the file was removed or renamed after CI applied it; until it is restored, main's drift probe reports $g as an ownerless orphan. Fix: restore $g under its applied name if that name is free on main; otherwise have $g reverted on dev per the learning (gap 2), then re-run."
    else
      hint=""
      [[ "$how" == "slug" ]] && hint=" If $g is unrelated to your change, give yours a different slug."
      echo "::error::$g is ledgered on dev but is not on $base, not in this tree, and no other fresh live branch holds it at the applied blob. It matches this PR's $match_f by $how, so $match_f was renamed or removed after CI applied it, and $g becomes an orphan once this lands. Fix: rename $match_f back to $g if that name is free on main; otherwise have $g reverted on dev per knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md (gap 2), then re-run.$hint"
    fi
  done

  if [[ "${#unmerged[@]}" -eq 0 ]]; then
    echo "::notice::ledger-parity: 0 unmerged migrations in this tree — nothing to compare"
  fi
  local counts="unmerged=${#unmerged[@]} ledgered-match=$matched pending=$pending ledger-rows=$rows candidates=$candidates skipped-owned=$skipped_owned violations=$violations"
  if [[ "$violations" -gt 0 ]]; then
    echo "ledger-parity: RED ($counts)"
    exit 1
  fi
  echo "ledger-parity: clean ($counts)"
  exit 0
}

case "${1:-}" in
  check) shift; cmd_check "$@" ;;
  classify-missing) shift; cmd_classify_missing "$@" ;;
  --help|-h) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
