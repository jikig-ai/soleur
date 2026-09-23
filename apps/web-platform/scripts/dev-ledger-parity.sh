#!/usr/bin/env bash
# dev-ledger-parity: per-ref ledger checks over the ONE shared dev Supabase
# project (#8521, #8520; ADR-061 amendment 2026-09-23).
#
# PR CI (tenant-integration) applies each pull request's NOT-YET-MERGED
# migrations to shared dev, and run-migrations.sh never re-applies a filename it
# has already ledgered in public._schema_migrations. Three arms then turn main
# red AFTER the merge:
#
#   A1  edited after apply   — the PR edits F after CI applied it; dev keeps the
#                              old body, the PR's own tests ran against it, and
#                              main's drift probe reports content drift (#8521).
#   A2  renamed after apply  — the PR renames/renumbers F; the old name stays
#                              ledgered and becomes an orphan on merge.
#   A4  deleted after apply  — the PR drops F; same orphan.
#   in-flight                — ANY open PR's applied row is "missing on main"
#                              for every push until it merges (2026-09-22).
#
# Two subcommands, one ownership primitive:
#
#   check             PR side. Fails A1/A2/A4 BEFORE merge, and before apply
#                     (A1 makes the runner skip the stale file, so a dependent
#                     migration would otherwise fail inside apply first). The
#                     workflow runs the BASE-REF copy of this script, so a PR
#                     cannot weaken the guard that judges it.
#   classify-missing  main side. The drift probe pipes its missing-on-main rows
#                     here; a row a fresh, unmerged live branch holds is
#                     in-flight (warning), everything else stays blocking.
#
# Why fail instead of re-applying: re-running an edited idempotent file leaves
# the objects the old body created and the new body does not touch — silent
# residue (#8520: the 075 FOR ALL policy, the 122 index). A migration applied to
# shared dev is immutable, merged or not; the change ships as a new file.
#
# Side effects: one fixed SELECT on the ledger, and git work in a THROWAWAY bare
# repo removed on exit. The checkout is never written (no promisor config, no
# shallow entries, no refs). Nothing writes to dev or prd.
#
# Every git call on the checkout is `git -C "$REPO" … ':(top,literal)<path>'`:
# run-migrations.sh's cwd-relative ls-tree is exactly how its own unmerged gate
# went inert in CI (#8606).

set -uo pipefail
export LC_ALL=C
export GIT_TERMINAL_PROMPT=0
# Location variables would retarget every `git -C` below at another repository.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE

readonly MIG_REL="apps/web-platform/supabase/migrations"
readonly LEDGER_SQL="SELECT filename || '|' || COALESCE(content_sha, '') FROM public._schema_migrations ORDER BY filename"
readonly STALE_DAYS=30
readonly FETCH_TIMEOUT_S=120
readonly PSQL_TIMEOUT_S=60
readonly ZERO_SHA="0000000000000000000000000000000000000000"

usage() {
  cat <<'USAGE'
Usage:
  dev-ledger-parity.sh check --base <ref> --repo <dir> [--head-branch <name>]
  dev-ledger-parity.sh classify-missing --base-branch <name> --repo <dir>   # stdin: "<file>|<sha>" lines
  dev-ledger-parity.sh --help

check (PR side; reads DATABASE_URL_POOLER, else DATABASE_URL):
  For every forward migration in the tree that is absent from <base>, the dev
  ledger either lacks it or records exactly this tree's blob (A1). A ledger row
  on neither <base> nor this tree that matches one of this PR's files by blob or
  slug (A2), or a blob this PR's branch history carried (A4), is a violation —
  unless another fresh live branch holds that row by exact name.
  Summary line:
    ledger-parity: clean|RED (unmerged=N ledgered-match=N pending=N ledger-rows=N candidates=N skipped-owned=N violations=N)

classify-missing (main side; used by .github/actions/dev-migration-drift-probe):
  One verdict per stdin line, in input order, tab-separated:
    in-flight <file> <branch> <exact|blob|slug>
    stale     <file> <branch> <age-days>
    orphan    <file>
  A row is in-flight only if its name never appeared in <base-branch>'s history
  and a live branch that is not merged into <base-branch>, with a commit in the
  last 30 days, holds it among its files that are NOT on <base-branch>.
  Summary line (stderr):
    ledger-classify: in-flight=N stale=M orphan=K

Exit codes:
  0  clean / classified
  1  violation(s), each named via ::error::   (check only)
  2  cannot measure — never evidence of drift. For check, the message ends
     "not caused by this PR; re-run the job" (transient) or
     "not caused by this PR; check the Doppler dev_scheduled config / workflow wiring; a re-run will not help" (config).

Repair paths: knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md
USAGE
}

MODE=""
CLEAN=()
# shellcheck disable=SC2329  # invoked by the EXIT trap below
cleanup() { [[ ${#CLEAN[@]} -gt 0 ]] && rm -rf "${CLEAN[@]}"; return 0; }
trap cleanup EXIT

# cannot_measure <transient|config> <message> — exit 2 with the class suffix.
cannot_measure() {
  local class="$1" msg="$2" suffix=""
  if [[ "$MODE" == "check" ]]; then
    if [[ "$class" == "transient" ]]; then
      suffix=" — not caused by this PR; re-run the job"
    else
      suffix=" — not caused by this PR; check the Doppler dev_scheduled config / workflow wiring; a re-run will not help"
    fi
  fi
  echo "::error::dev-ledger-parity ${MODE:-}: cannot measure ($class): ${msg}${suffix}" >&2
  exit 2
}

need_value() {
  # A flag as the last argument would otherwise loop forever on `shift 2`.
  [[ $# -ge 2 ]] && return 0
  echo "dev-ledger-parity: $1 requires a value" >&2
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
# Ownership primitive. One throwaway bare repo per invocation, one full-history
# blobless fetch of every origin head. Full history (no --depth) is what makes
# the main-history and PR-history lookups correct; blob:none keeps it cheap.
# ---------------------------------------------------------------------------
OWN=""
BASE_OWN=""
OWNERS=""   # file: branch<TAB>fresh|stale<TAB>age_days<TAB>file<TAB>blob<TAB>slug
ogit() { GIT_NO_LAZY_FETCH=1 git -C "$OWN" "$@"; }

owners_repo() {
  local base_branch="$1"
  [[ -n "$OWN" ]] && return 0
  assert_fixture_dir "$REPO"
  OWN=$(mktemp -d "${TMPDIR:-/tmp}/dev-ledger-owners.XXXXXX") \
    || cannot_measure config "mktemp failed"
  assert_fixture_dir "$OWN"
  CLEAN+=("$OWN")
  git init -q --bare "$OWN" || cannot_measure config "git init of the throwaway owner repo failed"

  local url
  url=$(git -C "$REPO" remote get-url origin 2>/dev/null) || url=""
  [[ -n "$url" ]] || cannot_measure config "--repo has no 'origin' remote"
  # Reuse the checkout's auth header, if any, so a private origin keeps working.
  # Written to the throwaway repo's config (removed on exit), never onto argv.
  local key val
  while read -r key val; do
    [[ -n "$key" ]] && git -C "$OWN" config --add "$key" "$val"
  done < <(git -C "$REPO" config --get-regexp '^http\..*\.extraheader$' 2>/dev/null || true)

  local rc=0
  bounded "$FETCH_TIMEOUT_S" git -C "$OWN" fetch -q --no-tags --filter=blob:none "$url" \
    '+refs/heads/*:refs/owners/*' 2>"$OWN/fetch.err" || rc=$?
  # A server without filter support prints "filtering not recognized" and still
  # succeeds with full objects — only the exit code decides.
  [[ "$rc" == "0" ]] || cannot_measure transient "fetching origin branch heads failed (git rc=$rc)"

  BASE_OWN="refs/owners/$base_branch"
  ogit rev-parse --verify --quiet "$BASE_OWN^{commit}" >/dev/null \
    || cannot_measure config "base branch '$base_branch' is not a branch on origin"

  local -A on_base=()
  local lsout path
  lsout=$(ogit ls-tree -r --name-only "$BASE_OWN" -- ":(top,literal)$MIG_REL/") \
    || cannot_measure transient "ls-tree of $base_branch failed in the owner repo"
  while IFS= read -r path; do
    [[ -n "$path" ]] && on_base["${path##*/}"]=1
  done <<<"$lsout"

  OWNERS="$OWN/owners.tsv"
  : > "$OWNERS"
  local now ref date name age state anc mode type sha rest f
  now=$(date +%s)
  local refs
  refs=$(ogit for-each-ref --format='%(refname)%09%(committerdate:unix)' refs/owners/) \
    || cannot_measure transient "for-each-ref failed in the owner repo"
  while IFS=$'\t' read -r ref date; do
    [[ -z "$ref" ]] && continue
    name="${ref#refs/owners/}"
    [[ "$name" == "$base_branch" ]] && continue
    case "$name" in gh-readonly-queue/*) continue ;; esac
    anc=0
    ogit merge-base --is-ancestor "$ref" "$BASE_OWN" 2>/dev/null || anc=$?
    case "$anc" in
      0) continue ;;          # already merged: owns nothing
      1) : ;;
      *) cannot_measure transient "merge-base failed for a branch head (rc=$anc)" ;;
    esac
    [[ "$date" =~ ^[0-9]+$ ]] || cannot_measure transient "unreadable commit date on a branch head"
    age=$(( (now - date) / 86400 ))
    state=fresh
    [[ "$age" -gt "$STALE_DAYS" ]] && state=stale
    lsout=$(ogit ls-tree -r "$ref" -- ":(top,literal)$MIG_REL/") \
      || cannot_measure transient "ls-tree failed for a branch head"
    while IFS=$'\t' read -r rest path; do
      [[ -z "$path" ]] && continue
      read -r mode type sha <<<"$rest"
      [[ "$type" == "blob" ]] || continue
      : "$mode"
      f="${path##*/}"
      case "$f" in *.down.sql) continue ;; esac   # never applied, never owned
      [[ -n "${on_base[$f]:-}" ]] && continue      # main's files are nobody's
      name_ok "$f" || continue
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$state" "$age" "$f" "$sha" "$(slug_of "$f")" >> "$OWNERS"
    done <<<"$lsout"
  done <<<"$refs"
}

# in_base_history <file> — 0 if the filename ever existed on the base branch.
in_base_history() {
  local h
  h=$(ogit log -1 --format=%H "$BASE_OWN" -- ":(top,literal)$MIG_REL/$1") \
    || cannot_measure transient "log of $BASE_OWN failed for a ledger row"
  [[ -n "$h" ]]
}

# owner_lookup <tier> <value> <state> [<exclude-branch>] — first matching branch
# (sorted), as "branch<TAB>age"; empty when none.
owner_lookup() {
  awk -F'\t' -v tier="$1" -v val="$2" -v st="$3" -v ex="${4:-}" '
    $2 != st || $1 == ex { next }
    (tier == "exact" && $4 == val) || (tier == "blob" && $5 == val) || (tier == "slug" && $6 == val) {
      print $1 "\t" $3
    }' "$OWNERS" | sort | head -n 1
}

# ---------------------------------------------------------------------------
# classify-missing
# ---------------------------------------------------------------------------
classify_row() {
  local f="$1" sha="$2" hit tier
  if in_base_history "$f"; then
    printf 'orphan\t%s\n' "$f"
    return 0
  fi
  for tier in exact blob slug; do
    case "$tier" in
      exact) hit=$(owner_lookup exact "$f" fresh) ;;
      blob) hit=""; is_sha "$sha" && hit=$(owner_lookup blob "$sha" fresh) ;;
      slug) hit=$(owner_lookup slug "$(slug_of "$f")" fresh) ;;
    esac
    if [[ -n "$hit" ]]; then
      printf 'in-flight\t%s\t%s\t%s\n' "$f" "$(branch_label "${hit%%$'\t'*}")" "$tier"
      return 0
    fi
  done
  for tier in exact blob slug; do
    case "$tier" in
      exact) hit=$(owner_lookup exact "$f" stale) ;;
      blob) hit=""; is_sha "$sha" && hit=$(owner_lookup blob "$sha" stale) ;;
      slug) hit=$(owner_lookup slug "$(slug_of "$f")" stale) ;;
    esac
    if [[ -n "$hit" ]]; then
      printf 'stale\t%s\t%s\t%s\n' "$f" "$(branch_label "${hit%%$'\t'*}")" "${hit##*$'\t'}"
      return 0
    fi
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
      *) echo "dev-ledger-parity classify-missing: unknown argument: $1" >&2; exit 2 ;;
    esac
  done
  [[ "$base_branch" =~ ^[A-Za-z0-9._/-]+$ ]] || cannot_measure config "--base-branch is missing or unsafe"
  _assert_repo_root "$REPO"

  local -a files=() shas=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    f="${line%%|*}"
    if [[ "$line" == *"|"* ]]; then sha="${line#*|}"; else sha=""; fi
    name_ok "$f" || cannot_measure config "stdin line $(( ${#files[@]} + 1 )) carries an unsafe filename"
    # An empty sha is a legitimate pre-content-sha ledger row (blob tier skipped).
    [[ -z "$sha" ]] || is_sha "$sha" || cannot_measure config "stdin line $(( ${#files[@]} + 1 )) carries a malformed sha"
    files+=("$f"); shas+=("$sha")
  done

  local n_in=0 n_st=0 n_or=0 i
  if [[ ${#files[@]} -gt 0 ]]; then
    owners_repo "$base_branch"
    for i in "${!files[@]}"; do
      verdict=$(classify_row "${files[$i]}" "${shas[$i]}") || exit 2
      printf '%s\n' "$verdict"
      case "${verdict%%$'\t'*}" in
        in-flight) n_in=$((n_in + 1)) ;;
        stale) n_st=$((n_st + 1)) ;;
        orphan) n_or=$((n_or + 1)) ;;
      esac
    done
  fi
  echo "ledger-classify: in-flight=$n_in stale=$n_st orphan=$n_or" >&2
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
      *) echo "dev-ledger-parity check: unknown argument: $1" >&2; exit 2 ;;
    esac
  done
  [[ -n "$base" ]] || cannot_measure config "--base is required"
  _assert_repo_root "$REPO"
  assert_fixture_dir "$REPO"
  git -C "$REPO" rev-parse --verify --quiet "$base^{commit}" >/dev/null \
    || cannot_measure config "cannot resolve --base '$base'"
  if [[ -n "$head_branch" && ! "$head_branch" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    cannot_measure config "--head-branch is not a safe branch name"
  fi
  local base_branch="${base#refs/remotes/}"
  base_branch="${base_branch#origin/}"

  # ---- population: M (forward names on base), T (in tree), U (unmerged) ----
  local -A on_base=() in_tree=() blob=()
  local -a unmerged=()
  local lsout path f
  lsout=$(git -C "$REPO" ls-tree -r --name-only "$base" -- ":(top,literal)$MIG_REL/") \
    || cannot_measure transient "ls-tree of '$base' failed"
  while IFS= read -r path; do
    [[ -n "$path" ]] && on_base["${path##*/}"]=1
  done <<<"$lsout"
  for path in "$REPO/$MIG_REL"/*.sql; do
    [[ -e "$path" ]] || continue
    f="${path##*/}"
    name_ok "$f" || cannot_measure config "the tree carries a migration filename outside the runner's whitelist"
    case "$f" in *.down.sql) continue ;; esac
    in_tree["$f"]=1
    [[ -n "${on_base[$f]:-}" ]] && continue
    unmerged+=("$f")
    blob["$f"]=$(git -C "$REPO" hash-object -- "$path") || cannot_measure transient "hash-object failed for $f"
  done

  # ---- ledger: read on EVERY run, so the pooler path and the floor always run ----
  local db="${DATABASE_URL_POOLER:-${DATABASE_URL:-}}"
  [[ -n "$db" ]] || cannot_measure config "neither DATABASE_URL_POOLER nor DATABASE_URL is set"
  command -v psql >/dev/null 2>&1 || cannot_measure config "psql not found on PATH"
  local ledger_out rc=0
  ledger_out=$(PGCONNECT_TIMEOUT=10 bounded "$PSQL_TIMEOUT_S" psql "$db" -w --no-psqlrc -tAq --set ON_ERROR_STOP=1 -c "$LEDGER_SQL" 2>/dev/null) || rc=$?
  [[ "$rc" == "0" ]] || cannot_measure transient "reading public._schema_migrations failed (psql rc=$rc)"
  local -A ledger=()
  local rows=0 suspicious=0 lf lsha
  while IFS='|' read -r lf lsha; do
    [[ -z "$lf" ]] && continue
    if ! name_ok "$lf"; then suspicious=$((suspicious + 1)); continue; fi
    ledger["$lf"]="$lsha"
    rows=$((rows + 1))
  done <<<"$ledger_out"
  [[ "$rows" -gt 0 ]] || cannot_measure config "the dev ledger returned zero rows — wrong database or broken query"
  if [[ "$suspicious" -gt 0 ]]; then
    echo "::warning::ledger-parity: skipped $suspicious ledger row(s) whose filename is outside the runner's whitelist (not echoed)"
  fi

  local violations=0 matched=0 pending=0 candidates=0 skipped_owned=0 applied
  # ---- A1: every unmerged file is absent from the ledger or ledgered at its blob ----
  for f in ${unmerged[@]+"${unmerged[@]}"}; do
    if [[ -z "${ledger[$f]+set}" ]]; then pending=$((pending + 1)); continue; fi
    applied="${ledger[$f]}"
    if ! is_sha "$applied"; then
      echo "::error::$f: the ledger row carries no verifiable content_sha, so this PR's unmerged migration cannot be shown to match what dev applied. Renumber the file (a new name is applied fresh), or ask a dev operator to reconcile the row per the learning §Content drift (#8605)."
      violations=$((violations + 1))
    elif [[ "$applied" != "${blob[$f]}" ]]; then
      echo "::error::$f: dev applied this unmerged migration at blob $applied, but this tree has ${blob[$f]}. The runner never re-applies a ledgered filename, so this PR's tests ran against the OLD body and main's drift probe will fail after merge (#8521). Fix without a database write: restore the applied body (git show $applied > $MIG_REL/$f; if the object is not local: gh api repos/\$GITHUB_REPOSITORY/git/blobs/$applied --jq .content | base64 -d > $MIG_REL/$f), then put the change in a NEW migration numbered after it. A migration applied to dev is as immutable as a merged one (#8583). If git log --all --find-object=$applied finds nothing on your side, another branch applied a same-named file: renumber yours. If you cannot recover the body and hold no dev credentials, ask a dev operator to reconcile per knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md §Content drift (#8605 tracks self-service)."
      violations=$((violations + 1))
    else
      matched=$((matched + 1))
    fi
  done

  # ---- candidates: ledger rows on neither base nor this tree ----
  local g gsha how match_f fu hist_loaded=0 hit owner
  local -A pr_blobs=()
  for g in "${!ledger[@]}"; do
    [[ -n "${on_base[$g]:-}" || -n "${in_tree[$g]:-}" ]] && continue
    candidates=$((candidates + 1))
    gsha="${ledger[$g]}"
    is_sha "$gsha" || gsha=""
    how=""; match_f=""
    if [[ -n "$gsha" ]]; then
      for fu in ${unmerged[@]+"${unmerged[@]}"}; do
        if [[ "${blob[$fu]}" == "$gsha" ]]; then how=blob; match_f="$fu"; break; fi
      done
    fi
    if [[ -z "$how" ]]; then
      for fu in ${unmerged[@]+"${unmerged[@]}"}; do
        if [[ "$(slug_of "$fu")" == "$(slug_of "$g")" ]]; then how=slug; match_f="$fu"; break; fi
      done
    fi
    if [[ -z "$how" && -n "$head_branch" && -n "$gsha" ]]; then
      if [[ "$hist_loaded" == "0" ]]; then
        owners_repo "$base_branch"
        ogit rev-parse --verify --quiet "refs/owners/$head_branch^{commit}" >/dev/null \
          || cannot_measure transient "head branch '$head_branch' is not on origin"
        local rawlog c1 c2 c3 c4 rest2
        rawlog=$(ogit log --raw --no-abbrev --format= "$BASE_OWN..refs/owners/$head_branch" -- ":(top,literal)$MIG_REL/") \
          || cannot_measure transient "log of the PR branch history failed"
        while read -r c1 c2 c3 c4 rest2; do
          : "$c1$c2$rest2"
          [[ -n "$c3" && "$c3" != "$ZERO_SHA" ]] && pr_blobs["$c3"]=1
          [[ -n "$c4" && "$c4" != "$ZERO_SHA" ]] && pr_blobs["$c4"]=1
        done <<<"$rawlog"
        hist_loaded=1
      fi
      [[ -n "${pr_blobs[$gsha]:-}" ]] && how=history
    fi
    [[ -z "$how" ]] && continue

    # Another PR's in-flight row, held by exact name on a fresh live branch.
    owners_repo "$base_branch"
    hit=$(owner_lookup exact "$g" fresh "$head_branch")
    if [[ -n "$hit" ]]; then
      owner=$(branch_label "${hit%%$'\t'*}")
      local what="$match_f"
      [[ -z "$what" ]] && what="this branch's history"
      echo "::notice::ledger-parity: $g matches $what by $how but is held by live branch $owner — that PR's in-flight row, not this PR's"
      skipped_owned=$((skipped_owned + 1))
      continue
    fi
    violations=$((violations + 1))
    if [[ "$how" == "history" ]]; then
      echo "::error::$g is ledgered on dev but is not on $base, not in this tree, and not held by any other live branch. This PR's branch history carried exactly that body (blob $gsha) by history, so the file was removed or renamed after CI applied it, and after merge $g becomes an orphan. Fix: restore $g under its applied name if that name is free on main; otherwise have $g reverted on dev per the learning (gap 2), then re-run."
    else
      local hint=""
      [[ "$how" == "slug" ]] && hint=" If $g is unrelated to your change, re-slug yours."
      echo "::error::$g is ledgered on dev but is not on $base, not in this tree, and not held by any other live branch. It matches this PR's $match_f by $how, so $match_f was renamed or removed after CI applied it, and after merge $g becomes an orphan. Fix: rename $match_f back to $g if that name is free on main; otherwise have $g reverted on dev per knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md (gap 2), then re-run.$hint"
    fi
  done

  local n_unmerged=0
  [[ ${#unmerged[@]} -gt 0 ]] && n_unmerged=${#unmerged[@]}
  if [[ "$n_unmerged" -eq 0 ]]; then
    echo "::notice::ledger-parity: 0 unmerged migrations in this tree — nothing to compare"
  fi
  local counts="unmerged=$n_unmerged ledgered-match=$matched pending=$pending ledger-rows=$rows candidates=$candidates skipped-owned=$skipped_owned violations=$violations"
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
