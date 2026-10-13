#!/usr/bin/env bash
# plugin-version.sh — resolve the installed and latest Soleur plugin version.
#
# Shared by the SessionStart banner (hooks/version-banner.sh), /soleur:version and
# /soleur:help, so all three agree. Output is key=value lines, one shape for callers
# and tests. Never reports a version it did not read; always exits 0 (fail open).
#
# Modes (one required):
#   --installed              source=manifest|commit|checkout|unknown|none, version=, commit=, marketplace=
#   --cached-latest          --installed keys + cache_dir= + the cached latest release; NO network
#   --latest [--refresh]     latest release tag; uses a fresh cache unless --refresh
#   --compare [--refresh]    --installed + --latest + relation=older|current|unknown
#   --cmp A B                semver order of two X.Y.Z strings: older|same|newer
#
# Installed identity precedence: manifest top-level `.version` (X.Y.Z) -> basename of the
# plugin root when it is a commit-hash cache dir -> the HEAD commit of the local git checkout
# the plugin is loaded from in place (source=checkout) -> unknown. A manifest with no `version`
# key is the normal published shape (ADR-182 D1), so the commit hash is the usual answer.
#
# source=checkout: a local-Folder marketplace (or --plugin-dir) loads the plugin from
# <top>/plugins/soleur, which has neither a manifest version nor a commit-hash directory name.
# The identity is then <top>'s HEAD commit, read with PLAIN FILE READS ONLY (HEAD -> a loose
# ref or packed-refs; a detached HEAD holds the sha). Git is never run against that repository:
# its .git/config, hooks and attributes are untrusted project input. The lookup is anchored on
# the layout (the root ends in /plugins/soleur, <top>/.git exists, plugin.json exists), never a
# walk up to "the first .git", which would adopt a dotfiles repository above the project. Every
# file is size-gated by stat BEFORE it is read, HEAD and loose refs must be exactly one line,
# only a 40-hex commit is accepted, and only its first 12 hex are ever printed.
# The plugin root is CLAUDE_PLUGIN_ROOT, or, when that is unset (the Bash tool does not
# always export it), the directory one level above this script's directory.
#
# Latest release: highest tag matching ^v[0-9]+.[0-9]+.[0-9]+$ from `git ls-remote`
# against a fixed URL. The repo also publishes web-v*, vinngest-v*, telegram-v* and
# zot-image-* tags; the strict regex excludes them and prereleases.
#
# Relation for a commit-hash or local-checkout install uses one unauthenticated GitHub compare API call
# (ls-remote maps tags to commits but cannot order an installed commit against them).
# `diverged` or any failure is `unknown`, never "current". A relation answered from a
# stale cache or after a failed lookup is reported as unknown, except `older`, which
# stays true (releases only move forward).
#
# Network isolation: the lookups run from a neutral directory with the user's and the
# project's git configuration disabled and https as the only allowed protocol, so a
# `url.<base>.insteadOf` rewrite, `http.extraHeader`, `core.sshCommand` or a GIT_CONFIG_*
# variable cannot redirect the request, add credentials or run a command. Proxy
# environment variables still apply.
#
# Cache: one file per install, ${XDG_CACHE_HOME:-~/.cache}/soleur/latest-release.<id>
# (a relative XDG_CACHE_HOME is ignored, per the XDG spec). Treated as fresh for 24 h;
# the file stays on disk until replaced or deleted. A local checkout moves with every commit,
# so all checkouts share the one file latest-release.checkout (it records which commit it
# answers; another commit's entry reads as cache=missing and is simply replaced).
#
# Env: SOLEUR_FETCH_TIMEOUT (seconds per request, default 8, must be >= 1).
set -uo pipefail

REPO_URL="https://github.com/jikig-ai/soleur.git"
COMPARE_API="https://api.github.com/repos/jikig-ai/soleur/compare"
TAG_RE='^v[0-9]+\.[0-9]+\.[0-9]+$'
SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
DIR_RE='^[0-9a-f]{12}(-[0-9a-f]{8})?$'
SHA40_RE='^[0-9a-f]{40}$'
SHA12_RE='^[0-9a-f]{12}$'
SMALL_MAX=512        # bytes: HEAD, loose refs, .git pointer files, commondir
PACKED_MAX=4194304   # bytes: packed-refs (this repository's own is ~0.5 MB)
MANIFEST_MAX=65536   # bytes: plugin.json (the real one is ~1 KB; the no-jq awk scanner is superlinear, 100 KB cost seconds on mawk)
TTL_S=86400
# A failed compare is cached as fresh for only this long (the fetched stamp is backdated by
# TTL_S - FAIL_FRESH_S), so one rate-limit response does not silence the notice for a day.
FAIL_FRESH_S=3600
FETCH_TIMEOUT="${SOLEUR_FETCH_TIMEOUT:-8}"
if [[ "$FETCH_TIMEOUT" =~ ^[0-9]+$ ]] && (( 10#$FETCH_TIMEOUT >= 1 )); then
  FETCH_TIMEOUT=$((10#$FETCH_TIMEOUT))
else
  FETCH_TIMEOUT=8
fi

TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_CMD="gtimeout"; fi

# With timeout/gtimeout the command is bounded by it. Without them (stock macOS) a bash
# watchdog kills it after FETCH_TIMEOUT: http.lowSpeedLimit alone does not bound a stalled
# connect or TLS handshake. A killed command is reported as rc 124 (timeout).
run_bounded() {
  if [[ -n "$TIMEOUT_CMD" ]]; then "$TIMEOUT_CMD" "$FETCH_TIMEOUT" "$@"; return; fi
  local pid wd rc
  "$@" &
  pid=$!
  ( sleep "$FETCH_TIMEOUT"; pkill -P "$pid" 2>/dev/null; kill "$pid" 2>/dev/null ) </dev/null >/dev/null 2>&1 &
  wd=$!
  wait "$pid" 2>/dev/null
  rc=$?
  kill "$wd" 2>/dev/null
  wait "$wd" 2>/dev/null
  (( rc >= 128 )) && rc=124
  return "$rc"
}

# ---- semver ------------------------------------------------------------------
semver_cmp() { # A B (both X.Y.Z) -> older|same|newer; numeric, leading zeros are not octal
  local IFS=. i p q
  local -a x y
  IFS=. read -r -a x <<< "$1"
  IFS=. read -r -a y <<< "$2"
  for i in 0 1 2; do
    p=$((10#${x[i]:-0}))
    q=$((10#${y[i]:-0}))
    (( p < q )) && { echo older; return 0; }
    (( p > q )) && { echo newer; return 0; }
  done
  echo same
}

# ---- cache location ----------------------------------------------------------
CACHE_DIR=""
resolve_cache_dir() {
  local base="${XDG_CACHE_HOME:-}"
  case "$base" in /*) ;; *) base="" ;; esac # relative values must be ignored (XDG spec)
  [[ "$base" == *[[:cntrl:]]* ]] && base="" # a newline would inject key=value lines downstream
  if [[ -z "$base" ]]; then
    case "${HOME:-}" in /*) ;; *) return 0 ;; esac
    [[ "$HOME" == *[[:cntrl:]]* ]] && return 0
    base="$HOME/.cache"
  fi
  CACHE_DIR="$base/soleur"
}

# ---- installed ---------------------------------------------------------------
INST_SOURCE=none INST_VERSION="" INST_COMMIT="" INST_ID="" INST_MARKETPLACE="" CACHE_FILE=""

# Top-level "version" string of a JSON file without jq: a small depth-aware scanner, so a
# nested {"mcpServers":{"x":{"version":"1.0.0"}}} is never mistaken for the plugin version.
manifest_version_nojq() {
  awk '
    { buf = buf $0 "\n" }
    END {
      n = length(buf); depth = 0; i = 1; want = 0
      while (i <= n) {
        c = substr(buf, i, 1)
        if (c == "\"") {
          j = i + 1; s = ""
          while (j <= n) {
            d = substr(buf, j, 1)
            if (d == "\\") { s = s substr(buf, j, 2); j += 2; continue }
            if (d == "\"") break
            s = s d; j++
          }
          i = j + 1
          if (want) { if (depth == 1) { print s; exit } want = 0; continue }
          k = i
          while (k <= n && substr(buf, k, 1) ~ /[ \t\r\n]/) k++
          if (substr(buf, k, 1) == ":" && depth == 1 && s == "version") want = 1
          continue
        }
        if (c == "{" || c == "[") depth++
        else if (c == "}" || c == "]") depth--
        else if (want && c !~ /[ \t\r\n:]/) want = 0
        i++
      }
    }' "$1" 2>/dev/null
}

read_manifest_version() {
  local f="$1" v="" n
  # A FIFO or a /dev/zero symlink here would stall jq/awk for the whole hook budget.
  [[ -f "$f" && -r "$f" ]] || return 0
  n="$(file_size "$f")" || return 0
  (( n <= MANIFEST_MAX )) || return 0
  if command -v jq >/dev/null 2>&1; then
    v="$(jq -r '.version // empty' "$f" 2>/dev/null)" || v=""
  else
    v="$(manifest_version_nojq "$f")"
  fi
  printf '%s' "$v"
}

# ---- local checkout (source=checkout): plain file reads, never git ---------------------
# These and the manifest read are the only readers of repository bytes; each checks regular-file-ness
# and a stat size before reading. Every read is gated on regular-file-ness
# AND on a stat size first (a FIFO or device would hang an open; a sparse multi-GiB HEAD of
# NULs took 38 s through `read -n 512` alone), and nothing is executed, sourced or evaluated.
CK_VAL=""

file_size() { # path -> byte count on stdout; nothing when it cannot be measured
  local n
  n="$(stat -L -c %s -- "$1" 2>/dev/null || stat -L -f %z -- "$1" 2>/dev/null)" || return 1
  [[ "$n" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$n"
}

read_small() { # path -> CK_VAL = the file's single line (no newline); 1 when absent, irregular, oversize or not exactly one line
  local f="$1" n line="" rc=0 got LC_ALL=C   # bytes, not characters: a non-ASCII name must not change the verdict
  CK_VAL=""
  [[ -f "$f" && -r "$f" ]] || return 1
  n="$(file_size "$f")" || return 1
  (( n >= 1 && n <= SMALL_MAX )) || return 1
  { IFS= read -r -n "$SMALL_MAX" line < "$f"; } 2>/dev/null || rc=$?
  # What was consumed must be exactly what the file holds. `read` silently drops NUL bytes and
  # stops at the first newline, so a NUL-spliced or multi-line file consumes fewer bytes than
  # its size and is refused instead of printing an identity from a string that is not its
  # bytes. LC_ALL=C makes ${#line} count bytes in every locale, so a non-ASCII branch or path
  # resolves the same under C and UTF-8 (a character count would silently drop the banner).
  got=${#line}
  if (( rc == 0 && got < SMALL_MAX )); then got=$((got + 1)); fi   # the newline `read` consumed
  (( got == n )) || return 1
  CK_VAL="$line"
}

valid_ref_name() { # refs/heads/<name> -> 0 when it is a plausible git branch ref, else 1 (deny-list, git check-ref-format style)
  local r="$1" rest LC_ALL=C   # the bracket classes below must mean the same thing in every locale
  case "$r" in refs/heads/?*) ;; *) return 1 ;; esac
  rest="${r#refs/heads/}"
  case "$rest" in
    *[[:cntrl:][:space:]~^:?*\[\\]*|*..*|*//*|*@\{*|/*|*/|.*|*/.*|*.|*.lock|*.lock/*|@) return 1 ;;
  esac
  return 0
}

packed_ref_sha() { # commondir ref -> CK_VAL = sha for the exact ref in packed-refs
  local f="$1/packed-refs" n
  CK_VAL=""
  [[ -f "$f" && -r "$f" ]] || return 1
  n="$(file_size "$f")" || return 1
  (( n >= 1 && n <= PACKED_MAX )) || return 1
  # A peel line (`^sha`) has one field, so it never matches; a first field starting with `#` is skipped;
  # a record over 1 KiB (a real entry is ~40 + a ref name <= ~500) is skipped before awk splits it, and
  # whatever the first match holds must still pass the 40-hex test below, so a corrupt line yields
  # `unknown`, never a wrong commit. LC_ALL=C makes length() count bytes on every awk.
  CK_VAL="$(SOLEUR_REF="$2" LC_ALL=C awk '
    length($0) < 1024 && $1 !~ /^#/ && $2 == ENVIRON["SOLEUR_REF"] { print $1; exit }' "$f" 2>/dev/null)"
  [[ "$CK_VAL" =~ $SHA40_RE ]]
}

resolve_checkout_commit() { # absolute plugin root -> CK_VAL = 40-hex HEAD commit, else 1
  local root="${1%/}" top gd="" common head ref
  CK_VAL=""
  case "$root" in /*) ;; *) return 1 ;; esac
  # Physical path first: a plugin root that is a symlink into another checkout must read THAT
  # checkout's HEAD, not the HEAD of the repository that merely holds the link.
  root="$(cd -P -- "$root" 2>/dev/null && pwd -P)" || return 1
  case "$root" in */plugins/soleur) ;; *) return 1 ;; esac
  top="${root%/plugins/soleur}"
  [[ -n "$top" ]] || return 1
  [[ -f "$root/.claude-plugin/plugin.json" ]] || return 1
  # <top>/.git is a directory (clone or bare layout) or a file `gitdir: <path>` (linked worktree).
  if [[ -d "$top/.git" ]]; then
    gd="$top/.git"
  elif [[ -f "$top/.git" ]]; then
    read_small "$top/.git" || return 1
    case "$CK_VAL" in gitdir:\ ?*) gd="${CK_VAL#gitdir: }" ;; *) return 1 ;; esac
    case "$gd" in /*) ;; *) gd="$top/$gd" ;; esac
    [[ -d "$gd" ]] || return 1
  else
    return 1
  fi
  common="$gd"
  if [[ -f "$gd/commondir" ]]; then
    read_small "$gd/commondir" || return 1
    case "$CK_VAL" in /*) common="$CK_VAL" ;; *) common="$gd/$CK_VAL" ;; esac
    [[ -d "$common" ]] || return 1
  fi
  read_small "$gd/HEAD" || return 1
  head="$CK_VAL"
  if [[ "$head" =~ $SHA40_RE ]]; then CK_VAL="$head"; return 0; fi   # detached HEAD
  case "$head" in "ref: "?*) ref="${head#ref: }" ;; *) return 1 ;; esac
  valid_ref_name "$ref" || return 1
  # A loose ref that exists must be valid; it never falls through to a stale packed entry.
  if [[ -e "$common/$ref" || -L "$common/$ref" ]]; then
    read_small "$common/$ref" || return 1
    [[ "$CK_VAL" =~ $SHA40_RE ]] || return 1
    return 0
  fi
  packed_ref_sha "$common" "$ref" || return 1
  return 0
}

resolve_installed() {
  local root="${CLAUDE_PLUGIN_ROOT:-}" v base parent
  if [[ -z "$root" ]]; then
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)" || root=""
  fi
  resolve_cache_dir
  if [[ -z "$root" || ! -d "$root" ]]; then INST_SOURCE=none; return 0; fi
  # .../plugins/cache/<marketplace>/soleur/<id> -> marketplace (selects the right update command)
  root="${root%/}"
  parent="$(dirname "$root")"
  if [[ "$(basename "$parent")" == soleur && "$(basename "$(dirname "$(dirname "$parent")")")" == cache ]]; then
    base="$(basename "$(dirname "$parent")")"
    [[ "$base" =~ ^[A-Za-z0-9._-]+$ ]] && INST_MARKETPLACE="$base"
  fi
  v="$(read_manifest_version "$root/.claude-plugin/plugin.json")"
  if [[ "$v" =~ $SEMVER_RE ]]; then
    INST_SOURCE=manifest INST_VERSION="$v" INST_ID="$v"
  else
    base="$(basename "$root")"
    if [[ "$base" =~ $DIR_RE ]]; then
      INST_SOURCE=commit INST_COMMIT="${base:0:12}" INST_ID="${base:0:12}"
    elif resolve_checkout_commit "$root"; then
      INST_SOURCE=checkout INST_COMMIT="${CK_VAL:0:12}" INST_ID="${CK_VAL:0:12}"
    else
      INST_SOURCE=unknown
    fi
  fi
  if [[ -n "$INST_ID" && -n "$CACHE_DIR" ]]; then
    if [[ "$INST_SOURCE" == checkout ]]; then
      CACHE_FILE="$CACHE_DIR/latest-release.checkout"   # one file for every commit of a moving checkout
    else
      CACHE_FILE="$CACHE_DIR/latest-release.$INST_ID"
    fi
  fi
  return 0
}

print_installed() {
  printf 'source=%s\n' "$INST_SOURCE"
  [[ -n "$INST_VERSION" ]] && printf 'version=%s\n' "$INST_VERSION"
  [[ -n "$INST_COMMIT" ]] && printf 'commit=%s\n' "$INST_COMMIT"
  [[ -n "$INST_MARKETPLACE" ]] && printf 'marketplace=%s\n' "$INST_MARKETPLACE"
  return 0
}

# ---- cache -------------------------------------------------------------------
C_TAG="" C_SHA="" C_FETCHED="" C_REL="" C_REASON="" CACHE_STATE=missing

reset_cache_vars() { C_TAG="" C_SHA="" C_FETCHED="" C_REL="" C_REASON="" CACHE_STATE=missing; }

load_cache() {
  reset_cache_vars
  [[ -n "$CACHE_FILE" && -f "$CACHE_FILE" ]] || return 0
  # Same trust rule as write_cache: never read a cache from a directory we do not own.
  [[ -O "$CACHE_DIR" && ! -L "$CACHE_DIR" ]] || return 0
  local line key val rel_for="" complete="" now age mtime
  while IFS= read -r line; do
    key="${line%%=*}" val="${line#*=}"
    case "$key" in
      tag) C_TAG="$val" ;; sha) C_SHA="$val" ;; fetched) C_FETCHED="$val" ;;
      relation) C_REL="$val" ;; relation_for) rel_for="$val" ;; reason) C_REASON="$val" ;;
      complete) complete="$val" ;;
    esac
  done < "$CACHE_FILE" 2>/dev/null
  # A truncated write loses the trailing `complete=1`, so it reads as corrupt, never as a
  # fresh "unknown" that would silence the notice for a day.
  # The one latest-release.checkout file answers a single commit at a time: an entry written for
  # another commit is not corruption (and must not be reported as such), it is just not this
  # commit's answer, so it reads as missing and the opt-in refresh replaces it.
  if [[ "$INST_SOURCE" == checkout && "$complete" == 1 && "$rel_for" != "$INST_ID" && "$rel_for" =~ $SHA12_RE ]]; then
    reset_cache_vars; CACHE_STATE=missing
    return 0
  fi
  if [[ "$complete" != 1 || "$rel_for" != "$INST_ID" || ! "$C_TAG" =~ $TAG_RE || ! "$C_FETCHED" =~ ^[1-9][0-9]{0,11}$ ]]; then
    reset_cache_vars; CACHE_STATE=corrupt
    return 0
  fi
  [[ "$C_SHA" =~ $SHA40_RE ]] || C_SHA=""
  case "$C_REL" in older|current|unknown) ;; *) C_REL="" ;; esac
  [[ "$C_REASON" =~ ^[a-z-]{0,40}$ ]] || C_REASON=""
  now="$(date +%s)"
  age=$(( now - C_FETCHED ))
  # A future-dated cache (clock change, hand edit) counts as stale, not fresh forever.
  if (( age < 0 || age >= TTL_S )); then CACHE_STATE=stale; else CACHE_STATE=fresh; fi
  mtime="$(stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)"
  if [[ "$mtime" =~ ^[0-9]+$ ]] && (( mtime > now + 60 )); then CACHE_STATE=stale; fi
  return 0
}

write_cache() { # tag sha relation reason fetched
  [[ -n "$CACHE_FILE" && -n "$CACHE_DIR" ]] || return 0
  ( umask 077; mkdir -p "$CACHE_DIR" ) 2>/dev/null || return 0
  # Never write into a directory we do not own or that is a symlink (shared XDG dirs).
  [[ -d "$CACHE_DIR" && -O "$CACHE_DIR" && ! -L "$CACHE_DIR" ]] || return 0
  chmod 700 "$CACHE_DIR" 2>/dev/null || true
  local tmp="$CACHE_FILE.$$"
  rm -f "$tmp" 2>/dev/null
  # noclobber makes `>` fail on an existing path (including a planted symlink).
  if ( set -C; umask 077
       { printf 'tag=%s\nsha=%s\nfetched=%s\n' "$1" "$2" "$5"
         printf 'relation=%s\nrelation_for=%s\nreason=%s\ncomplete=1\n' "$3" "$INST_ID" "$4"; } > "$tmp" ) 2>/dev/null; then
    mv -f "$tmp" "$CACHE_FILE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}

# ---- latest release ----------------------------------------------------------
FETCH_STATUS="" F_TAG="" F_SHA=""

fetch_latest() {
  FETCH_STATUS="" F_TAG="" F_SHA=""
  if ! command -v git >/dev/null 2>&1; then FETCH_STATUS=no-git; return 0; fi
  local out rc
  out="$(
    cd / 2>/dev/null
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS \
          GIT_SSH GIT_SSH_COMMAND GIT_PROXY_COMMAND GIT_ASKPASS SSH_ASKPASS GIT_EXEC_PATH
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1 \
           GIT_TERMINAL_PROMPT=0 HOME=/nonexistent XDG_CONFIG_HOME=/nonexistent
    run_bounded git -c protocol.allow=never -c protocol.https.allow=always \
      -c http.lowSpeedLimit=1 -c "http.lowSpeedTime=$FETCH_TIMEOUT" \
      ls-remote --tags "$REPO_URL" 'refs/tags/v[0-9]*' 2>/dev/null
  )"
  rc=$?
  if (( rc == 124 )); then FETCH_STATUS=timeout; return 0; fi
  if (( rc != 0 )); then FETCH_STATUS=offline; return 0; fi
  # Highest strict vX.Y.Z by numeric key (no `sort -V`: not portable). Components wider than
  # four digits are skipped so the key stays exact in awk's double arithmetic.
  F_TAG="$(printf '%s\n' "$out" | awk -F'\t' '
    NF >= 2 {
      t = $2; sub(/^refs\/tags\//, "", t); sub(/\^\{\}$/, "", t)
      if (t ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/) {
        split(substr(t, 2), a, ".")
        if (length(a[1]) <= 4 && length(a[2]) <= 4 && length(a[3]) <= 4)
          printf "%.0f %s\n", (a[1] * 10000 + a[2]) * 10000 + a[3], t
      }
    }' | sort -n | tail -1 | cut -d' ' -f2)"
  if [[ -z "$F_TAG" ]]; then FETCH_STATUS=no-tags; return 0; fi
  # The peeled line (^{}) carries the commit an annotated tag points at.
  F_SHA="$(printf '%s\n' "$out" | awk -F'\t' -v t="refs/tags/$F_TAG" \
    '$2==t"^{}"{p=$1} $2==t{s=$1} END{print (p!="" ? p : s)}')"
  [[ "$F_SHA" =~ $SHA40_RE ]] || F_SHA=""
  FETCH_STATUS=ok
}

REL="" REL_REASON=""

compute_relation() { # needs INST_*, F_TAG, F_SHA
  REL=unknown REL_REASON=""
  case "$INST_SOURCE" in
    manifest)
      REL="$(semver_cmp "$INST_VERSION" "${F_TAG#v}")"
      [[ "$REL" == older ]] || REL=current
      ;;
    commit|checkout)
      # The tag's own commit is the installed one: nothing to compare.
      if [[ -n "$F_SHA" && "${F_SHA:0:12}" == "$INST_COMMIT" ]]; then REL=current; return 0; fi
      # Re-validated at the sink: only 12 hex ever reaches the URL, whatever the source said.
      [[ "$INST_COMMIT" =~ $SHA12_RE ]] || { REL_REASON=installed-unknown; return 0; }
      if ! command -v curl >/dev/null 2>&1; then REL_REASON=no-curl; return 0; fi
      local body status
      # page=2000 keeps the body ~20 KB instead of ~1.3 MB (the file list is paged); the
      # top-level status is unaffected. -q ignores any ~/.curlrc.
      body="$(cd / 2>/dev/null; run_bounded curl -q -fsS --proto =https --compressed -m "$FETCH_TIMEOUT" \
        -H 'Accept: application/vnd.github+json' \
        "$COMPARE_API/$INST_COMMIT...$F_TAG?per_page=1&page=2000" 2>/dev/null)" || { REL_REASON=compare-failed; return 0; }
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
  local fetched
  load_cache
  if [[ "${1:-}" != force && "$CACHE_STATE" == fresh ]]; then FETCH_STATUS=cache-fresh; return 0; fi
  fetch_latest
  if [[ "$FETCH_STATUS" == ok ]]; then
    compute_relation
    fetched="$(date +%s)"
    case "$REL_REASON" in
      compare-failed|no-curl|compare-unparseable) fetched=$(( fetched - TTL_S + FAIL_FRESH_S )) ;;
    esac
    # Nothing to key a cache on without a recognisable install: answer, but do not persist.
    [[ -n "$INST_ID" ]] && write_cache "$F_TAG" "$F_SHA" "$REL" "$REL_REASON" "$fetched"
    C_TAG="$F_TAG" C_SHA="$F_SHA" C_REL="$REL" C_REASON="$REL_REASON" C_FETCHED="$fetched" CACHE_STATE=fresh
  fi
  return 0
}

print_latest() {
  local rel="$C_REL" reason="$C_REASON" unreliable=0
  printf 'cache=%s\n' "$CACHE_STATE"
  [[ -n "$CACHE_DIR" ]] && printf 'cache_dir=%s\n' "$CACHE_DIR"
  [[ -n "$FETCH_STATUS" ]] && printf 'latest_status=%s\n' "$FETCH_STATUS"
  [[ -n "$C_TAG" ]] || return 0
  printf 'latest=%s\n' "$C_TAG"
  [[ -n "$C_SHA" ]] && printf 'latest_commit=%s\n' "$C_SHA"
  if [[ -z "$INST_ID" ]]; then
    rel=unknown reason=installed-unknown
  else
    [[ "$CACHE_STATE" != fresh ]] && unreliable=1
    case "$FETCH_STATUS" in offline|timeout|no-git|no-tags) unreliable=1 ;; esac
    # `older` stays true when old (releases only move forward); `current` does not. An
    # unknown keeps the reason it was first answered with (diverged, compare-failed, ...).
    if (( unreliable )) && [[ "$rel" == current ]]; then rel=unknown reason=stale-cache; fi
    [[ -n "$rel" ]] || { rel=unknown; reason=cache-invalid; }
  fi
  printf 'relation=%s\n' "$rel"
  [[ -n "$reason" ]] && printf 'reason=%s\n' "$reason"
  return 0
}

main() {
  local mode="" force="" a1="" a2=""
  while (( $# )); do
    case "$1" in
      --installed|--cached-latest|--latest|--compare) mode="$1" ;;
      --cmp) mode="$1"; a1="${2:-}"; a2="${3:-}"; shift 2 2>/dev/null || shift $# ;;
      --refresh) force=force ;;
    esac
    shift 2>/dev/null || break
  done
  if [[ "$mode" == --cmp ]]; then
    if [[ "$a1" =~ $SEMVER_RE && "$a2" =~ $SEMVER_RE ]]; then semver_cmp "$a1" "$a2"; else echo unknown; fi
    return 0
  fi
  resolve_installed
  case "$mode" in
    --installed) print_installed ;;
    --cached-latest) print_installed; load_cache; print_latest ;;
    --latest) refresh_latest "$force"; print_latest ;;
    --compare) print_installed; refresh_latest "$force"; print_latest ;;
    *) echo "usage: plugin-version.sh --installed|--cached-latest|--latest [--refresh]|--compare [--refresh]|--cmp A B" >&2 ;;
  esac
  return 0
}

main "$@"
exit 0
