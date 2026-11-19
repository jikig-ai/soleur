#!/usr/bin/env bash
# cf-account-state-migrate.sh — forget every non-R2 cloudflare_* state entry that
# still carries the OLD zone/account id, so it can be re-imported under the new
# ids (#12931, plan "State-forget script" and Guard 2).
#
# Usage:
#   cf-account-state-migrate.sh --new-zone <32hex> --new-account <32hex>
#                               [--rehearsal] [--backup-dir <dir>]
#
# Runs in the current directory, which must be an initialised Terraform root.
# Exit codes: 0 ok (including an idempotent re-run that removes nothing),
# 1 abort or post-write verification failure, 2 usage error.
#
# Contract:
# - Backup first. Non-rehearsal uploads it to the state bucket (R2_ENDPOINT
#   required); rehearsal keeps it local and never invokes `aws`.
# - The candidate set is every managed cloudflare_* resource in state except
#   cloudflare_r2_bucket. Every candidate is classified before any write; one
#   unclassifiable candidate aborts the whole run with 0 removed.
# - One write: a single `terraform state rm` carrying every rm address (the
#   backend has no lock, so a per-address loop could stop half-way).
# - After the write: removed count, serial delta (+1) and a re-list are checked.
# - Prints addresses and actions only, never attribute values or state contents.
set -uo pipefail
umask 077

readonly OLD_ZONE_ID="5af02a2f394e9ba6e0ea23c381a26b67"
readonly OLD_ACCOUNT_ID="4d5ba6f096b2686fbdd404167dd4e125"
readonly STATE_BUCKET="soleur-terraform-state"
readonly BACKUP_PREFIX="web-platform/backups"
readonly P="cf-state-migrate"

NEW_ZONE_ID=""
NEW_ACCOUNT_ID=""
REHEARSAL=0
BACKUP_DIR=""
BACKUP_FILE=""
BACKUP_LOCATION=""
WORK=""
RM_ADDRS=()
CAND_LINES=()
SKIPPED=0

# shellcheck disable=SC2329 # invoked by the EXIT trap
cleanup() { if [[ -n "$WORK" && -d "$WORK" ]]; then rm -rf "$WORK"; fi; }
trap cleanup EXIT

# abort <reason-code> <message> [exit-code]
abort() {
  printf '%s verdict=abort reason=%s\n' "$P" "$1"
  printf '%s: ABORT: %s\n' "$P" "$2" >&2
  exit "${3:-1}"
}

# post_write_fail <reason-code> <message>: the single state rm already ran.
post_write_fail() {
  printf '%s verdict=abort reason=%s\n' "$P" "$1"
  printf '%s: FAILED AFTER STATE WRITE: %s\n' "$P" "$2" >&2
  printf '%s: state may be PARTIALLY MIGRATED; restore from the backup at %s\n' "$P" "$BACKUP_LOCATION" >&2
  exit 1
}

usage() { abort usage "$1" 2; }

is_id() { [[ "$1" =~ ^[0-9a-f]{32}$ ]]; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --new-zone)    [[ $# -ge 2 ]] || usage "--new-zone needs a value"; NEW_ZONE_ID="$2"; shift 2 ;;
      --new-account) [[ $# -ge 2 ]] || usage "--new-account needs a value"; NEW_ACCOUNT_ID="$2"; shift 2 ;;
      --backup-dir)  [[ $# -ge 2 && -n "$2" ]] || usage "--backup-dir needs a value"; BACKUP_DIR="$2"; shift 2 ;;
      --rehearsal)   REHEARSAL=1; shift ;;
      *) usage "unknown argument: $1" ;;
    esac
  done
  is_id "$NEW_ZONE_ID"    || usage "--new-zone must be 32 lowercase hex characters"
  is_id "$NEW_ACCOUNT_ID" || usage "--new-account must be 32 lowercase hex characters"
  for old in "$OLD_ZONE_ID" "$OLD_ACCOUNT_ID"; do
    [[ "$NEW_ZONE_ID" != "$old" ]]    || usage "--new-zone equals an OLD id"
    [[ "$NEW_ACCOUNT_ID" != "$old" ]] || usage "--new-account equals an OLD id"
  done
  if [[ "$REHEARSAL" -eq 0 && -z "${R2_ENDPOINT:-}" ]]; then
    usage "R2_ENDPOINT must be set outside --rehearsal (backup upload target)"
  fi
  command -v jq >/dev/null 2>&1 || usage "jq is required"
  command -v terraform >/dev/null 2>&1 || usage "terraform is required"
}

# pull_serial <out-file>: pull state into the file and print its numeric serial.
pull_serial() {
  terraform state pull >"$1" 2>/dev/null || return 1
  [[ -s "$1" ]] || return 1
  jq -er 'if (.serial | type) == "number" then .serial else error("no serial") end' "$1" 2>/dev/null
}

take_backup() {
  local ts dir
  ts="$(date -u +%Y%m%dT%H%M%SZ)" || abort backup-failed "date failed"
  if [[ -n "$BACKUP_DIR" ]]; then
    dir="$BACKUP_DIR"
  elif [[ -n "${RUNNER_TEMP:-}" ]]; then
    dir="$RUNNER_TEMP/cf-migrate"
  else
    dir="$(mktemp -d)/cf-migrate" || abort backup-failed "mktemp failed"
  fi
  mkdir -p "$dir" || abort backup-failed "cannot create backup dir $dir"
  BACKUP_FILE="$dir/pre-cf-account-migration-$ts.tfstate"
  BACKUP_LOCATION="$BACKUP_FILE"
  pull_serial "$BACKUP_FILE" >/dev/null \
    || abort backup-failed "terraform state pull did not yield non-empty JSON with a numeric serial; 0 removed"
  if [[ "$REHEARSAL" -eq 1 ]]; then
    printf '%s backup=local path=%s\n' "$P" "$BACKUP_FILE"
    return 0
  fi
  local uri="s3://$STATE_BUCKET/$BACKUP_PREFIX/pre-cf-account-migration-$ts.tfstate"
  aws s3 cp "$BACKUP_FILE" "$uri" --endpoint-url "$R2_ENDPOINT" --only-show-errors >/dev/null \
    || abort backup-upload-failed "backup upload to $uri failed; 0 removed"
  BACKUP_LOCATION="$uri (local copy $BACKUP_FILE)"
  printf '%s backup=uploaded uri=%s\n' "$P" "$uri"
}

# list_candidates <show-json-file>: one record per candidate,
# address US type US zone_id US account_id (null -> empty), US = \x1f.
list_candidates() {
  jq -r '
    def mods: ., (.child_modules[]? | mods);
    [ (.values.root_module // empty) | mods | .resources[]?
      | select(.mode == "managed"
               and ((.type // "") | startswith("cloudflare_"))
               and .type != "cloudflare_r2_bucket") ]
    | .[]
    | [ .address, .type,
        ((.values.zone_id // "") | tostring),
        ((.values.account_id // "") | tostring) ]
    | join("\u001f")
  ' "$1"
}

read_candidates() {
  local show="$WORK/show.json" out
  terraform show -json >"$show" 2>/dev/null || abort show-failed "terraform show -json failed; 0 removed"
  out="$(list_candidates "$show" 2>/dev/null)" || abort show-unparseable "terraform show -json is not parseable state JSON; 0 removed"
  [[ -n "$out" ]] || abort zero-candidates "0 checked: no cloudflare_* candidates in state (refusing a vacuous pass); 0 removed"
  # Guarded so an empty list never yields one blank pseudo-candidate.
  if [[ -n "$out" ]]; then mapfile -t CAND_LINES <<<"$out"; fi
}

# id_class <field> <value>: old | new | unknown
id_class() {
  local old new
  if [[ "$1" == zone ]]; then old="$OLD_ZONE_ID"; new="$NEW_ZONE_ID"
  else old="$OLD_ACCOUNT_ID"; new="$NEW_ACCOUNT_ID"; fi
  if [[ "$2" == "$old" ]]; then printf 'old'
  elif [[ "$2" == "$new" ]]; then printf 'new'
  else printf 'unknown'; fi
}

classify_all() {
  local line addr type zid aid zc ac cls
  local -a actions=()
  for line in "${CAND_LINES[@]}"; do
    IFS=$'\x1f' read -r addr type zid aid <<<"$line"
    zc=""; ac=""
    [[ -n "$zid" ]] && zc="$(id_class zone "$zid")"
    [[ -n "$aid" ]] && ac="$(id_class account "$aid")"
    if [[ -z "$zc" && -z "$ac" ]]; then
      abort unclassifiable "$addr has neither zone_id nor account_id; 0 removed"
    fi
    if [[ "$zc" == unknown || "$ac" == unknown ]]; then
      abort unknown-id "$addr carries an id that is neither OLD nor NEW; 0 removed"
    fi
    if [[ -n "$zc" && -n "$ac" && "$zc" != "$ac" ]]; then
      abort mixed-ids "$addr carries one OLD and one NEW id; 0 removed"
    fi
    cls="${zc:-$ac}"
    if [[ "$cls" == old ]]; then
      [[ "$type" != "cloudflare_r2_bucket" ]] || abort r2-in-rm-set "$addr is an R2 bucket; refusing to forget it; 0 removed"
      RM_ADDRS+=("$addr"); actions+=("$addr rm")
    else
      SKIPPED=$((SKIPPED + 1)); actions+=("$addr skip")
    fi
  done
  for line in "${actions[@]}"; do
    printf '%s address=%s action=%s\n' "$P" "${line% *}" "${line##* }"
  done
}

apply_rm() {
  local before after rm_out rm_rc n_lines n
  before="$(pull_serial "$WORK/pre-rm.tfstate")" || abort serial-read-failed "could not read the state serial before state rm; 0 removed"
  rm -f "$WORK/pre-rm.tfstate"
  rm_out="$(terraform state rm "${RM_ADDRS[@]}" 2>&1)"; rm_rc=$?
  if [[ "$rm_rc" -ne 0 ]]; then
    printf '%s\n' "$rm_out" >&2
    post_write_fail state-rm-failed "terraform state rm exited $rm_rc"
  fi
  n_lines="$(grep -cE 'Successfully removed [0-9]+ resource instance' <<<"$rm_out")"
  n="$(grep -oE 'Successfully removed [0-9]+ resource instance' <<<"$rm_out" | grep -oE '[0-9]+' | head -n1)"
  if [[ "$n_lines" -ne 1 || "${n:-x}" != "${#RM_ADDRS[@]}" ]]; then
    post_write_fail rm-count-mismatch "state rm reported '${n:-none}' removed over $n_lines summary line(s); expected ${#RM_ADDRS[@]} in exactly one"
  fi
  after="$(pull_serial "$WORK/post-rm.tfstate")" || post_write_fail serial-read-failed "could not read the state serial after state rm"
  rm -f "$WORK/post-rm.tfstate"
  if [[ "$after" -ne $((before + 1)) ]]; then
    post_write_fail serial-delta "state serial went $before -> $after; expected exactly +1"
  fi
}

verify_after() {
  local show="$WORK/show-after.json" out line addr type zid aid left=0
  terraform show -json >"$show" 2>/dev/null || post_write_fail relist-failed "terraform show -json failed after state rm"
  out="$(list_candidates "$show" 2>/dev/null)" || post_write_fail relist-failed "post-rm terraform show -json is unparseable"
  if [[ -n "$out" ]]; then
    while IFS=$'\x1f' read -r addr type zid aid; do
      if [[ "$zid" == "$OLD_ZONE_ID" || "$aid" == "$OLD_ACCOUNT_ID" ]]; then
        printf '%s still-old address=%s\n' "$P" "$addr" >&2
        left=$((left + 1))
      fi
    done <<<"$out"
  fi
  [[ "$left" -eq 0 ]] || post_write_fail old-id-remains "$left old-id cloudflare_* entr(y/ies) remain after state rm"
}

parse_args "$@"
WORK="$(mktemp -d)" || abort mktemp-failed "mktemp failed"
take_backup
read_candidates
classify_all
if [[ "${#RM_ADDRS[@]}" -eq 0 ]]; then
  printf '%s verdict=ok removed=0 skipped=%d\n' "$P" "$SKIPPED"
  exit 0
fi
apply_rm
verify_after
printf '%s verdict=ok removed=%d skipped=%d\n' "$P" "${#RM_ADDRS[@]}" "$SKIPPED"
exit 0
