#!/usr/bin/env bash
# domain-model-drift.sh — /soleur:sync domain-model analyzer (#5754).
#
# Deterministically extracts a repo's structural domain model (RLS policies after
# last-writer-wins replay, table constraints, SECURITY DEFINER signatures, named TS
# guard symbols) and drift-checks it against the business-rules register
# (knowledge-base/engineering/architecture/domain-model.md).
#
# Modes:
#   extract   [--repo <path>]                        → JSON of live structural facts (stdout)
#   drift     [--repo <path>] [--register <path>]    → two-way markdown drift report (stdout)
#   write-row --register <path> --anchor <a> --statement <s>
#                                                    → approval-gated append to ## Auto-inferred
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

# --- shared tempfile cleanup: ONE array, ONE trap, registered in the MAIN shell ---
# Every mktemp in this script registers here. The trap is the only cleanup path.
#
# INVARIANT (do not break): allocation must happen in the MAIN SHELL, never inside
# a function that a caller runs under `$( )`. `drift` mode invokes emit_extract_json
# via command substitution (see emit_drift_report), so an append made inside that
# function would land in a subshell copy of the array and be lost, AND bash does not
# run the parent's EXIT trap when the subshell exits — the files would leak on every
# `drift` run while the trap looked correct. Allocate in the caller; pass paths in.
_TMPFILES=()
_cleanup_tmpfiles() { [[ ${#_TMPFILES[@]} -gt 0 ]] && rm -f "${_TMPFILES[@]}"; return 0; }
# INT/TERM as well as EXIT: bash does not run an EXIT trap for an uncaught
# SIGINT/SIGTERM in a non-interactive script, so Ctrl-C or a CI job kill would
# otherwise leak the spool files. Contents are non-sensitive by construction (the
# secret scan runs BEFORE any spool write) and mode is 0600, so this is disk
# hygiene rather than disclosure — but the leak is free to close.
trap _cleanup_tmpfiles EXIT INT TERM

# Allocate the two extract spool files in main-shell scope (see the invariant above).
SPOOL_FACTS=""
SPOOL_BLIND=""
alloc_spools() {
  SPOOL_FACTS="$(mktemp)"; SPOOL_BLIND="$(mktemp)"
  _TMPFILES+=("$SPOOL_FACTS" "$SPOOL_BLIND")
}

die() { echo "domain-model-drift: $*" >&2; exit 2; }
usage() { echo "usage: domain-model-drift.sh <extract|drift|write-row> [--repo <path>] [--register <path>] [--anchor <a>] [--statement <s>]" >&2; exit 2; }

# --- arg parsing (--terminated, quoted; no flag can arrive from file content) ---
MODE="${1:-}"; shift || true
REPO="."
REGISTER=""
ANCHOR=""
STATEMENT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)      REPO="${2:-}"; shift 2 ;;
    --register)  REGISTER="${2:-}"; shift 2 ;;
    --anchor)    ANCHOR="${2:-}"; shift 2 ;;
    --statement) STATEMENT="${2:-}"; shift 2 ;;
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
#
# Spool files are ALLOCATED BY THE CALLER (alloc_spools) and passed in — this
# function is called under `$( )` in drift mode, so it must not own cleanup.
emit_extract_json() {
  local facts_f="$1" blind_f="$2"
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

  # Spool the TSVs to files and bind with --rawfile (#6720). A shell variable bound
  # via --argjson is ONE argv argument and is capped by MAX_ARG_STRLEN = 131,072 B
  # PER ARGUMENT (not ARG_MAX) — verified by bisect: 131,071 B passes, 131,072 B
  # fails E2BIG. The fact corpus grows monotonically with the migration set, so the
  # old form was on a collision course with a hard `Argument list too long`.
  # --rawfile binds the file's RAW TEXT to a string variable and file I/O has no
  # per-argument limit, so the ceiling is gone. The jq programs below are moved
  # verbatim from the two former pre-passes — the source is TSV, and the program
  # already parses TSV from a string, so this is a MOVE, not a rewrite.
  # (--slurpfile was rejected: the payload is a single top-level array, so it would
  # bind as [[...]] and yield a SILENT `.facts|length == 1` undercount.)
  # Precedent: scripts/rule-metrics-aggregate.sh (rules_tsv_file / --rawfile rules_tsv).
  printf '%s' "$facts_tsv" > "$facts_f"
  printf '%s' "$blind_tsv" > "$blind_f"

  jq -Sn --argjson v "$SCHEMA_VERSION" --arg d "$DISCLAIMER" \
    --rawfile facts_tsv "$facts_f" --rawfile blind_tsv "$blind_f" \
    '{schema_version:$v, stack:"supabase-ts", disclaimer:$d,
      facts: ($facts_tsv | split("\n") | map(select(length>0)) | map(split("\t")) |
              map({kind:.[0], anchor:.[1], object:.[2], detail:.[3]}
                  + (if .[0]=="policy" then {predicate:.[3]} else {} end))
              | sort_by(.anchor)),
      blind_spots: ($blind_tsv | split("\n") | map(select(length>0)) | map(split("\t")) |
                    map({file:.[0], detail:.[1]}) | sort_by([.file,.detail]))}'
}

# ---------------------------------------------------------------------------
# drift: two-way report — stale register citations + undocumented source facts.
# Exit: 0 = clean, 1 = drift found, 2 = error, 3 = secret-refuse.
# ---------------------------------------------------------------------------
emit_drift_report() {
  local reg="$REGISTER"
  if [[ -z "$reg" ]]; then
    reg="$REPO/knowledge-base/engineering/architecture/domain-model.md"
  fi
  reg="$(realpath -e -- "$reg" 2>/dev/null)" || die "--register does not resolve to an existing file"
  # confine: the register must live under the repo root (no arbitrary write/read target)
  case "$reg" in "$REPO"/*) ;; *) die "--register must resolve under --repo" ;; esac

  # NOTE: declare + assign on SEPARATE lines — `local x="$(cmd)"` masks the
  # subshell exit code, which would swallow the fail-closed secret-refuse (exit 3).
  local extract_json
  extract_json="$(emit_extract_json "$SPOOL_FACTS" "$SPOOL_BLIND")" || exit $?

  # FAIL-OPEN GUARD (user-impact P1): if no Supabase migrations dir resolved, the
  # extract is empty and a naive report reads identical to a fully-documented repo
  # (0 stale / 0 undocumented / exit 0). Surface the zero-source condition loudly
  # and exit 2 (error) — a register cannot be drift-checked against unanalyzable source.
  if [[ "$(printf '%s' "$extract_json" | jq -r '.stack')" == "unsupported" ]]; then
    echo "# Domain-model drift report"
    echo
    echo "> $DISCLAIMER"
    echo
    echo "## Source not analyzable"
    echo
    echo "_No Supabase migrations directory resolved under \`$REPO\` — **0 source facts analyzed**. This is NOT a clean result: the register could not be drift-checked. (Generic/unsupported stack, or a moved/renamed migrations dir.)_"
    exit 2
  fi

  # STALE: register code-citations whose symbol no longer resolves in the cited file.
  local stale=""
  while IFS=$'\t' read -r _ cfile csym; do
    [[ -n "${csym:-}" ]] || continue
    local path; path="$(find "$REPO" -type f -name "$cfile" -not -path '*/node_modules/*' 2>/dev/null | LC_ALL=C sort | head -1)"
    if [[ -z "$path" ]]; then
      stale+="- \`$cfile\` › \`$csym\` — cited file not found in repo"$'\n'
    elif ! grep -qE "\\b${csym//[^A-Za-z0-9_]/}\\b" "$path" 2>/dev/null; then
      stale+="- \`$cfile\` › \`$csym\` — symbol not found in \`$cfile\` (stale citation)"$'\n'
    fi
  done < <(dm_register_code_citations "$reg")

  # UNDOCUMENTED: tables carrying a policy/constraint whose name the register never mentions.
  local undoc="" undoc_n=0
  local reg_body; reg_body="$(cat "$reg")"
  while IFS= read -r tbl; do
    [[ -n "$tbl" ]] || continue
    if ! printf '%s' "$reg_body" | grep -qE "\\b${tbl//[^A-Za-z0-9_]/}\\b"; then
      undoc_n=$((undoc_n + 1))
      [[ $undoc_n -le 25 ]] && undoc+="- \`$tbl\` — table has RLS/constraints but is not named in the register"$'\n'
    fi
  done < <(printf '%s' "$extract_json" | jq -r '[.facts[] | select(.kind=="policy" or .kind=="constraint") | (.anchor | capture("› (?<t>[^.]+)\\.") .t)] | unique | .[]' 2>/dev/null | LC_ALL=C sort -u)

  local blind_n; blind_n="$(printf '%s' "$extract_json" | jq '.blind_spots | length')"
  local stale_n; stale_n="$(printf '%s\n' "$stale" | grep -c '^- ' || true)"

  # ---- report ----
  echo "# Domain-model drift report"
  echo
  echo "> $DISCLAIMER"
  echo
  echo "## Stale register citations ($stale_n)"
  echo
  [[ -n "$stale" ]] && printf '%s\n' "$stale" || echo "_none_"
  echo "## Undocumented source facts ($undoc_n tables not in the register)"
  echo
  [[ -n "$undoc" ]] && printf '%s\n' "$undoc" || echo "_none_"
  [[ $undoc_n -gt 25 ]] && echo "_… and $((undoc_n - 25)) more (capped)._" && echo
  echo "## Blind spots ($blind_n)"
  echo
  echo "_$blind_n source constructs (dynamic \`EXECUTE format\`/\`DO \$\$\`, un-merged \`ALTER POLICY\`) were NOT statically analyzed and are not covered by the counts above._"

  [[ $stale_n -gt 0 || $undoc_n -gt 0 ]] && exit 1 || exit 0
}

# ---------------------------------------------------------------------------
# write-row: the approval-gated write primitive. The /soleur:sync command calls
# this ONCE PER operator-approved candidate. It never touches the curated
# `## Business Rules` table; it appends an escaped, secret-scanned, deduped row
# to `## Auto-inferred (unreviewed)` via an atomic whole-file rewrite.
# Exit: 0 = written (or deduped no-op), 2 = error/abort, 3 = secret-refuse.
# ---------------------------------------------------------------------------
write_row() {
  [[ -n "$ANCHOR" && -n "$STATEMENT" ]] || die "write-row needs --anchor and --statement"
  local reg="$REGISTER"
  reg="$(realpath -e -- "$reg" 2>/dev/null)" || die "--register does not resolve to an existing file"
  # confine the write target under the repo root — parity with drift mode (security P2).
  # (REPO defaults to the resolved cwd; the sync command passes the repo-relative register.)
  case "$reg" in "$REPO"/*) ;; *) die "--register must resolve under --repo" ;; esac

  # fail-closed secret-shape scan on BOTH fields before any write
  if dm_secret_scan "$ANCHOR$STATEMENT"; then
    echo "domain-model-drift: secret-shaped substring in candidate row; refusing to write" >&2
    exit 3
  fi
  # reject structural-breakout content outright (a forged BR-/heading row)
  case "$ANCHOR$STATEMENT" in
    *$'\n'*) die "candidate row contains a newline" ;;
  esac
  # escape markdown-table hazards: pipes, ALL C0 control chars (except tab \011;
  # newline \012 already rejected above), DEL, and unicode line separators
  # U+0085/U+2028/U+2029 (security P2 — full control-char class).
  local esc_anchor esc_stmt
  esc_anchor="$(printf '%s' "$ANCHOR"    | tr -d '\000-\010\013\014\016-\037\177' | sed 's/|/\\|/g; s/\xc2\x85//g; s/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g')"
  esc_stmt="$(printf '%s' "$STATEMENT"   | tr -d '\000-\010\013\014\016-\037\177' | sed 's/|/\\|/g; s/\xc2\x85//g; s/\xe2\x80\xa8//g; s/\xe2\x80\xa9//g')"
  # neutralize a forged row/heading marker at the START of EITHER field — the anchor
  # is column 1, exactly where curated `BR-NNN` IDs live (security P2).
  esc_anchor="${esc_anchor/#BR-/BR‑}"; esc_anchor="${esc_anchor/#\#\#/\\#\\#}"
  esc_stmt="${esc_stmt/#BR-/BR‑}"; esc_stmt="${esc_stmt/#\#\#/\\#\\#}"

  # TOCTOU: re-read the register NOW and locate exactly one Auto-inferred heading
  local hn
  hn="$(grep -cE '^## Auto-inferred \(unreviewed\)' "$reg")"
  [[ "$hn" -eq 1 ]] || die "register has $hn '## Auto-inferred (unreviewed)' headings (want exactly 1) — aborting"

  # content-anchor dedup: never re-propose an anchor already present anywhere
  if grep -qF "$ANCHOR" "$reg"; then
    exit 0  # already known (curated or previously accepted) — no-op
  fi

  # atomic whole-file rewrite (mktemp + mv), inserting the row after the heading's table
  # migrated onto the shared _TMPFILES trap — a local `trap … EXIT` here would
  # REPLACE it, and the matching `trap - EXIT` would CLEAR it (write_row runs in
  # the main shell, so the append is visible to the parent array).
  local tmp; tmp="$(mktemp)"; _TMPFILES+=("$tmp")
  awk -v row="| $esc_anchor | $esc_stmt |" '
    { print }
    /^## Auto-inferred \(unreviewed\)/ { insec = 1 }
    insec && /^\|---/ { print row; insec = 0 }
  ' "$reg" > "$tmp"
  # verify the row actually landed (guard against a header without a table separator)
  if ! grep -qF "$esc_anchor" "$tmp"; then
    die "could not locate the Auto-inferred table separator — aborting (register unchanged)"
  fi
  mv "$tmp" "$reg"
}

case "$MODE" in
  extract)   alloc_spools; emit_extract_json "$SPOOL_FACTS" "$SPOOL_BLIND" ;;
  drift)     alloc_spools; emit_drift_report ;;
  write-row) write_row ;;
  *) usage ;;
esac
