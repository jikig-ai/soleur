#!/usr/bin/env bash
# plugin-version.sh — resolve the installed and latest Soleur plugin version.
#
# Shared by the SessionStart banner (hooks/version-banner.sh), /soleur:version and
# /soleur:help, so all three agree. Output is key=value lines, one shape for callers
# and tests. Never reports a version it did not read; always exits 0 (fail open).
#
# Modes (one required):
#   --installed              source=manifest|commit|unknown|none, version=, commit=
#   --cached-latest          no network; latest=, cache=fresh|stale|missing|corrupt, relation=
#   --latest [--refresh]     latest release tag; uses a fresh cache unless --refresh
#   --compare [--refresh]    --installed + --latest + relation=older|current|unknown
#
# Installed version precedence: manifest `.version` (X.Y.Z) -> basename of
# CLAUDE_PLUGIN_ROOT when it is a commit-hash cache dir -> unknown. A manifest with no
# `version` key is the normal published shape (ADR-182 D1), so the commit hash is the
# usual answer today.
#
# Latest release: highest tag matching ^v[0-9]+.[0-9]+.[0-9]+$ from `git ls-remote`
# against a fixed URL (no token, no API rate limit). The plugin repo also publishes
# web-v*, vinngest-v* and zot-image-* tags; the strict regex excludes them.
#
# Relation for a commit-hash install uses one unauthenticated GitHub compare call
# (ls-remote maps tags to commits but cannot order an installed commit against them).
# `diverged` or any failure is `unknown`, never "current".
#
# Env: SOLEUR_FETCH_TIMEOUT (seconds, default 8), XDG_CACHE_HOME.
set -uo pipefail

REPO_URL="https://github.com/jikig-ai/soleur.git"
COMPARE_API="https://api.github.com/repos/jikig-ai/soleur/compare"
TAG_RE='^v[0-9]+\.[0-9]+\.[0-9]+$'
SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
DIR_RE='^[0-9a-f]{12}(-[0-9a-f]{8})?$'
TTL_S=86400
FETCH_TIMEOUT="${SOLEUR_FETCH_TIMEOUT:-8}"
[[ "$FETCH_TIMEOUT" =~ ^[0-9]+$ ]] || FETCH_TIMEOUT=8

CACHE_DIR="${XDG_CACHE_HOME:-${HOME:-/nonexistent}/.cache}/soleur"
CACHE_FILE="$CACHE_DIR/latest-release"

TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_CMD="gtimeout"; fi

run_bounded() {
  if [[ -n "$TIMEOUT_CMD" ]]; then "$TIMEOUT_CMD" "$FETCH_TIMEOUT" "$@"; else "$@"; fi
}

# ---- installed ---------------------------------------------------------------
INST_SOURCE=none INST_VERSION="" INST_COMMIT="" INST_ID=""

read_manifest_version() {
  local f="$1" v=""
  [[ -r "$f" ]] || return 0
  if command -v jq >/dev/null 2>&1; then
    v="$(jq -r '.version // empty' "$f" 2>/dev/null)" || v=""
  else
    # No jq: first "version" key anywhere (single-line or pretty-printed). A nested key could
    # win here, but the caller only accepts a strict X.Y.Z, so the worst case is a miss.
    v="$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
  fi
  printf '%s' "$v"
}

resolve_installed() {
  local root="${CLAUDE_PLUGIN_ROOT:-}" v base
  if [[ -z "$root" || ! -d "$root" ]]; then INST_SOURCE=none; return 0; fi
  v="$(read_manifest_version "$root/.claude-plugin/plugin.json")"
  if [[ "$v" =~ $SEMVER_RE ]]; then
    INST_SOURCE=manifest INST_VERSION="$v" INST_ID="$v"
    return 0
  fi
  base="$(basename "$root")"
  if [[ "$base" =~ $DIR_RE ]]; then
    INST_SOURCE=commit INST_COMMIT="${base:0:12}" INST_ID="${base:0:12}"
    return 0
  fi
  INST_SOURCE=unknown
}

print_installed() {
  printf 'source=%s\n' "$INST_SOURCE"
  [[ -n "$INST_VERSION" ]] && printf 'version=%s\n' "$INST_VERSION"
  [[ -n "$INST_COMMIT" ]] && printf 'commit=%s\n' "$INST_COMMIT"
  return 0
}

# ---- cache -------------------------------------------------------------------
C_TAG="" C_SHA="" C_FETCHED="" C_REL="" C_REL_FOR="" C_REASON="" CACHE_STATE=missing

load_cache() {
  C_TAG="" C_SHA="" C_FETCHED="" C_REL="" C_REL_FOR="" C_REASON="" CACHE_STATE=missing
  [[ -f "$CACHE_FILE" ]] || return 0
  local line key val
  while IFS= read -r line; do
    key="${line%%=*}" val="${line#*=}"
    case "$key" in
      tag) C_TAG="$val" ;; sha) C_SHA="$val" ;; fetched) C_FETCHED="$val" ;;
      relation) C_REL="$val" ;; relation_for) C_REL_FOR="$val" ;; reason) C_REASON="$val" ;;
    esac
  done < "$CACHE_FILE" 2>/dev/null
  if [[ ! "$C_TAG" =~ $TAG_RE || ! "$C_FETCHED" =~ ^[0-9]+$ ]]; then
    C_TAG="" C_SHA="" C_FETCHED="" C_REL="" C_REL_FOR="" C_REASON="" CACHE_STATE=corrupt
    return 0
  fi
  local now age mtime
  now="$(date +%s)"
  age=$(( now - C_FETCHED ))
  # A future-dated cache (clock change, hand edit) counts as stale, not fresh forever.
  if (( age < 0 || age >= TTL_S )); then CACHE_STATE=stale; else CACHE_STATE=fresh; fi
  mtime="$(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)"
  if [[ "$mtime" =~ ^[0-9]+$ ]] && (( mtime > now + 60 )); then CACHE_STATE=stale; fi
  return 0
}

write_cache() { # tag sha relation relation_for reason
  # Bound locally (not read from the globals) so the destination is provably absolute:
  # the literal default can never be relative, and an unresolvable HOME skips the write.
  local dir="${XDG_CACHE_HOME:-/nonexistent-soleur-cache}/soleur"
  if [[ -z "${XDG_CACHE_HOME:-}" ]]; then
    [[ -n "${HOME:-}" ]] || return 0
    dir="$HOME/.cache/soleur"
  fi
  local tmp="$dir/.latest-release.$$"
  ( umask 077; mkdir -p "$dir" ) 2>/dev/null || return 0
  chmod 700 "$dir" 2>/dev/null || true
  (
    umask 077
    {
      printf 'tag=%s\nsha=%s\nfetched=%s\n' "$1" "$2" "$(date +%s)"
      printf 'relation=%s\nrelation_for=%s\nreason=%s\n' "$3" "$4" "$5"
    } > "$tmp"
  ) 2>/dev/null
  mv -f "$tmp" "$dir/latest-release" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}

# ---- latest release ----------------------------------------------------------
FETCH_STATUS="" F_TAG="" F_SHA=""

fetch_latest() {
  FETCH_STATUS="" F_TAG="" F_SHA=""
  if ! command -v git >/dev/null 2>&1; then FETCH_STATUS=no-git; return 0; fi
  local out rc
  out="$(GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/true run_bounded git ls-remote --tags "$REPO_URL" 'refs/tags/v*' 2>/dev/null)"
  rc=$?
  if (( rc == 124 )); then FETCH_STATUS=timeout; return 0; fi
  if (( rc != 0 )); then FETCH_STATUS=offline; return 0; fi
  F_TAG="$(printf '%s\n' "$out" | awk -F'\t' 'NF>=2{t=$2; sub(/^refs\/tags\//,"",t); sub(/\^\{\}$/,"",t); print t}' \
    | grep -E "$TAG_RE" | sort -Vu | tail -1)"
  if [[ -z "$F_TAG" ]]; then FETCH_STATUS=no-tags; return 0; fi
  # The peeled line (^{}) carries the commit an annotated tag points at.
  F_SHA="$(printf '%s\n' "$out" | awk -F'\t' -v t="refs/tags/$F_TAG" \
    '$2==t"^{}"{p=$1} $2==t{s=$1} END{print (p!="" ? p : s)}')"
  FETCH_STATUS=ok
}

# semver_cmp A B -> prints older|same|newer (A relative to B)
semver_cmp() {
  local a="$1" b="$2" first
  [[ "$a" == "$b" ]] && { echo same; return; }
  first="$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1)"
  [[ "$first" == "$a" ]] && echo older || echo newer
}

REL="" REL_REASON=""

compute_relation() { # needs INST_*, F_TAG
  REL=unknown REL_REASON=""
  case "$INST_SOURCE" in
    manifest)
      REL="$(semver_cmp "$INST_VERSION" "${F_TAG#v}")"
      [[ "$REL" == older ]] || REL=current
      ;;
    commit)
      if ! command -v curl >/dev/null 2>&1; then REL_REASON=no-curl; return 0; fi
      local body status
      body="$(run_bounded curl -fsS -m "$FETCH_TIMEOUT" -H 'Accept: application/vnd.github+json' \
        "$COMPARE_API/$INST_COMMIT...$F_TAG?per_page=1" 2>/dev/null)" || { REL_REASON=compare-failed; return 0; }
      # First "status" is the top-level one; later ones belong to the per-file entries.
      status="$(printf '%s' "$body" | grep -o '"status"[[:space:]]*:[[:space:]]*"[a-z]*"' | head -1 | sed 's/.*"\([a-z]*\)"$/\1/')"
      case "$status" in
        ahead) REL=older ;;
        identical|behind) REL=current ;;
        diverged) REL_REASON=diverged ;;
        *) REL_REASON=compare-unparseable ;;
      esac
      ;;
    *) REL_REASON=installed-unknown ;;
  esac
  return 0
}

# refresh_latest: fetch, compare, cache. Honors a fresh cache unless $1 == force.
refresh_latest() {
  load_cache
  if [[ "${1:-}" != force && "$CACHE_STATE" == fresh ]]; then FETCH_STATUS=cache-fresh; return 0; fi
  fetch_latest
  if [[ "$FETCH_STATUS" == ok ]]; then
    compute_relation
    write_cache "$F_TAG" "$F_SHA" "$REL" "$INST_ID" "$REL_REASON"
    load_cache
  fi
  return 0
}

print_latest() {
  load_cache
  printf 'cache=%s\n' "$CACHE_STATE"
  [[ -n "$FETCH_STATUS" ]] && printf 'latest_status=%s\n' "$FETCH_STATUS"
  [[ -n "$C_TAG" ]] && printf 'latest=%s\n' "$C_TAG"
  [[ -n "$C_SHA" ]] && printf 'latest_commit=%s\n' "$C_SHA"
  # A cached relation only describes the install it was computed for.
  if [[ -n "$C_REL" && "$C_REL_FOR" == "$INST_ID" && -n "$INST_ID" ]]; then
    printf 'relation=%s\n' "$C_REL"
    [[ -n "$C_REASON" ]] && printf 'reason=%s\n' "$C_REASON"
  elif [[ -n "$C_TAG" ]]; then
    printf 'relation=unknown\nreason=%s\n' "cache-for-different-install"
  fi
  return 0
}

main() {
  local mode="" force=""
  while (( $# )); do
    case "$1" in
      --installed|--cached-latest|--latest|--compare) mode="$1" ;;
      --refresh) force=force ;;
    esac
    shift
  done
  resolve_installed
  case "$mode" in
    --installed) print_installed ;;
    --cached-latest) print_latest ;;
    --latest) refresh_latest "$force"; print_latest ;;
    --compare) print_installed; refresh_latest "$force"; print_latest ;;
    *) echo "usage: plugin-version.sh --installed|--cached-latest|--latest [--refresh]|--compare [--refresh]" >&2 ;;
  esac
  return 0
}

main "$@"
exit 0
