#!/usr/bin/env bash
# domain-model-drift.sh — /soleur:sync domain-model analyzer (#5754).
#
# Deterministically extracts a repo's structural domain model (RLS policies after
# last-writer-wins replay, table constraints, SECURITY DEFINER signatures, named TS
# guard symbols) and drift-checks it against the business-rules register
# (knowledge-base/engineering/architecture/domain-model.md).
#
# Modes:
#   extract [--repo <path>]                 → JSON of live structural facts (stdout)
#   drift   [--repo <path>] [--register <path>] → two-way markdown drift report (stdout)
#
# The `extract` JSON is INTERNAL/UNSTABLE (carries schema_version); the consumer
# contract for the #5871 enforcement gates is finalized when #5871 constrains it.
#
# Guarantee is bounded to STRUCTURAL documentation coverage — NOT semantic
# access-control correctness. Dynamic RLS (EXECUTE format / DO $$), function-body
# logic, and ALTER POLICY partial-modifies are disclosed as blind_spots, never
# counted as facts. This is best-effort extraction, NOT a security audit.
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/domain-model-lib.sh
source "$SCRIPT_DIR/lib/domain-model-lib.sh"

SCHEMA_VERSION=1
DISCLAIMER="Best-effort structural extraction from migrations/RLS/types; NOT a security audit or access-control attestation. Absence from this report does not imply an invariant is unenforced, and presence does not imply it is correctly enforced. Dynamic SQL and function-body logic are disclosed as blind_spots, not analyzed."

die() { echo "domain-model-drift: $*" >&2; exit 2; }
usage() { echo "usage: domain-model-drift.sh <extract|drift> [--repo <path>] [--register <path>]" >&2; exit 2; }

# --- arg parsing (--terminated, quoted; no flag can arrive from file content) ---
MODE="${1:-}"; shift || true
REPO="."
REGISTER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)     REPO="${2:-}"; shift 2 ;;
    --register) REGISTER="${2:-}"; shift 2 ;;
    --) shift; break ;;
    *) usage ;;
  esac
done
[[ -n "$MODE" ]] || usage

# realpath-confine the repo root (reject nonexistent / unreadable)
REPO="$(realpath -e -- "$REPO" 2>/dev/null)" || die "--repo does not resolve to an existing path"
[[ -d "$REPO" ]] || die "--repo is not a directory"

# ---------------------------------------------------------------------------
# extract: emit the structural-facts JSON for REPO
# ---------------------------------------------------------------------------
emit_extract_json() {
  local migdir facts_tsv blind_tsv events
  migdir="$(dm_find_migrations_dir "$REPO")"

  if [[ -z "$migdir" ]]; then
    jq -Sn --argjson v "$SCHEMA_VERSION" --arg d "$DISCLAIMER" \
      '{schema_version:$v, stack:"unsupported", disclaimer:$d, facts:[], blind_spots:[]}'
    return 0
  fi

  # gather the raw event stream (tokenizer treats SQL strictly as data)
  local base_files=()
  while IFS= read -r f; do [[ -n "$f" ]] && base_files+=("$f"); done < <(dm_base_migrations "$migdir")
  events="$( { [[ ${#base_files[@]} -gt 0 ]] && dm_tokenize "${base_files[@]}"; dm_guards_from_ts "$REPO"; } )"

  # reduce policy events (last-writer-wins) + pass constraints/guards → facts TSV
  facts_tsv="$(printf '%s\n' "$events" | awk -F'\t' '
    $1=="EVENT" && $2=="policy_create" { k=$4 SUBSEP $5; live[k]=$3 SUBSEP $6 }
    $1=="EVENT" && $2=="policy_drop"   { k=$4 SUBSEP $5; delete live[k] }
    $1=="EVENT" && $2=="constraint" { printf "constraint\t%s › %s.%s\t%s\t%s\n", $3,$4,$5,$5,$6 }
    $1=="EVENT" && $2=="guard"      { printf "guard\t%s › %s()\t%s\t%s\n", $3,$5,$5,$6 }
    END { for (k in live) { split(k,a,SUBSEP); split(live[k],v,SUBSEP);
            printf "policy\t%s › %s.%s\t%s\t%s\n", v[1], a[1], a[2], a[2], v[2] } }
  ' | LC_ALL=C sort -u)"

  # blind spots (dedup by file+detail)
  blind_tsv="$(printf '%s\n' "$events" | awk -F'\t' '
    $1=="EVENT" && $2=="blind" { printf "%s\t%s\n", $3, $6 }
  ' | LC_ALL=C sort -u)"

  # fail-closed secret-shape scan over ALL assembled text before emit
  if dm_secret_scan "$facts_tsv$blind_tsv"; then
    echo "domain-model-drift: secret-shaped substring in extracted facts; refusing to emit" >&2
    exit 3
  fi

  local facts_json blind_json
  facts_json="$(printf '%s' "$facts_tsv" | jq -R -s -c '
    split("\n") | map(select(length>0)) | map(split("\t")) |
    map({kind:.[0], anchor:.[1], object:.[2], detail:.[3]}
        + (if .[0]=="policy" then {predicate:.[3]} else {} end))
    | sort_by(.anchor)')"
  blind_json="$(printf '%s' "$blind_tsv" | jq -R -s -c '
    split("\n") | map(select(length>0)) | map(split("\t")) |
    map({file:.[0], detail:.[1]}) | sort_by([.file,.detail])')"

  jq -Sn --argjson v "$SCHEMA_VERSION" --arg d "$DISCLAIMER" \
    --argjson facts "${facts_json:-[]}" --argjson blind "${blind_json:-[]}" \
    '{schema_version:$v, stack:"supabase-ts", disclaimer:$d, facts:$facts, blind_spots:$blind}'
}

case "$MODE" in
  extract) emit_extract_json ;;
  drift)   die "drift mode not yet implemented (Phase 2)" ;;
  *) usage ;;
esac
