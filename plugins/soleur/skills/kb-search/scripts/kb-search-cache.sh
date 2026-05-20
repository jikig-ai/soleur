#!/usr/bin/env bash
# kb-search-cache.sh — NDJSON cache helper for the Stage 2 (#4176) paraphrase
# pre-pass. Pure local I/O; never reaches Anthropic. Three subcommands:
#
#   lookup <query>                       — sha256-keyed cache lookup with
#                                          14-day TTL. Echoes variants
#                                          (newline-separated) on hit, empty
#                                          on miss/expired. Always exit 0.
#   append <query> <v1> [v2] [v3]        — append one NDJSON row keyed by
#                                          sha256 of <query>. Creates the
#                                          cache directory chmod 700 on
#                                          first call.
#   clear                                — remove the cache file.
#
# Cache location: $REPO_ROOT/.soleur/cache/kb-search/query-paraphrases.ndjson.
# `.soleur/` is gitignored per .gitignore:52 (repo precedent — no
# ~/.cache/soleur/ exists). chmod 700 is load-bearing on multi-user dev
# machines, symbolic on single-user laptops.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CACHE_DIR="${KB_SEARCH_CACHE_DIR:-$REPO_ROOT/.soleur/cache/kb-search}"
CACHE_FILE="$CACHE_DIR/query-paraphrases.ndjson"
TTL_SECONDS=1209600  # 14 days.

usage() {
  cat >&2 <<'USAGE'
Usage:
  kb-search-cache.sh lookup <query>
  kb-search-cache.sh append <query> <variant1> [variant2] [variant3]
  kb-search-cache.sh clear
USAGE
  exit 2
}

cmd="${1:-}"
[[ -z "$cmd" ]] && usage

case "$cmd" in
  lookup)
    query="${2:-}"
    [[ -z "$query" ]] && usage
    [[ -f "$CACHE_FILE" ]] || exit 0
    hash=$(printf '%s' "$query" | sha256sum | awk '{print $1}')
    # jq parse error → cache miss (treat malformed NDJSON as no-cache). The
    # `2>/dev/null` + `|| true` keeps `set -e` happy when jq returns 5
    # (parse error) on any line.
    row=$(jq -c --arg h "$hash" 'select(.sha256 == $h)' "$CACHE_FILE" 2>/dev/null | head -1 || true)
    [[ -z "$row" ]] && exit 0
    cached_at=$(printf '%s' "$row" | jq -r '.cached_at // empty' 2>/dev/null || true)
    [[ -z "$cached_at" ]] && exit 0
    # ISO 8601 UTC `Z`-suffixed. `date -u -d` accepts the form.
    cached_epoch=$(date -u -d "$cached_at" +%s 2>/dev/null || echo 0)
    [[ "$cached_epoch" -eq 0 ]] && exit 0
    now_epoch=$(date -u +%s)
    age=$((now_epoch - cached_epoch))
    if (( age > TTL_SECONDS )); then
      exit 0
    fi
    printf '%s' "$row" | jq -r '.variants[]?' 2>/dev/null || true
    exit 0
    ;;
  append)
    query="${2:-}"
    [[ -z "$query" ]] && usage
    shift 2
    (( $# == 0 )) && usage
    variants=("$@")
    if [[ ! -d "$CACHE_DIR" ]]; then
      mkdir -p "$CACHE_DIR"
      chmod 700 "$CACHE_DIR"
    fi
    hash=$(printf '%s' "$query" | sha256sum | awk '{print $1}')
    cached_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    # Build the variants array via jq from positional args. `--args` reads
    # remaining strings safely (no shell injection through paraphrase content).
    jq -nc --arg sha "$hash" --arg q "$query" --arg ts "$cached_at" \
      --args '{sha256:$sha, query:$q, variants:$ARGS.positional, cached_at:$ts}' \
      -- "${variants[@]}" \
      >> "$CACHE_FILE"
    ;;
  clear)
    rm -f "$CACHE_FILE"
    ;;
  *)
    usage
    ;;
esac
