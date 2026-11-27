#!/usr/bin/env bash
# cf-tunnel-host-predelete.sh: delete the six broken proxied A records on ssh. and registry.soleur.ai
# so the tunnel phase can create its CNAMEs (Cloudflare refuses a CNAME beside an A record).
# #12931, ADR-329, plan Guard 5. Runbook: knowledge-base/engineering/operations/runbooks/
# cloudflare-account-migration.md, Phase 3 step 3.
#
# The move's DNS scan captured Cloudflare's anycast answers as records of their own; they serve
# Error 1000. Three A records per name cannot be imported into one Terraform address.
#
# Usage:
#   cf-tunnel-host-predelete.sh               dry run: GET and grade all six, delete nothing
#   cf-tunnel-host-predelete.sh --apply       grade all six, then delete; run ONLY by the gated tunnel
#                                             apply leg of cf-account-migrate-job.sh
#   cf-tunnel-host-predelete.sh --check-pins  grade the pin list alone: no token, no request
#
# Environment: CF_API_TOKEN (DNS read and edit on the new zone), read by name and sent on curl's
# stdin config (scripts/lib/bearer-curl.sh), never in argv.
#
# PROPERTY. A record is deleted only if it is one of the pinned ids in the pinned zone and its live
# name, type, proxied flag and content are the broken shape. Every id is graded before the first
# DELETE: one mismatch or one read with no verdict deletes none. A pinned id that answers 404 with
# Cloudflare's record-not-found code (81044) is already gone, so a re-run after a partial delete
# removes only what is left, and a re-run that finds all six gone exits 0. Any other 404 is unread.
#
# NAME CENSUS. Cloudflare refuses a CNAME beside any other record of its name, so before the first
# DELETE every record on deploy., ssh. and registry.soleur.ai is listed (no type filter). Each must be
# a pinned record (graded by its own read), or a proxied CNAME to *.cfargotunnel.com (the tunnel phase's own,
# left by an earlier apply). Anything else refuses foreign-record and deletes none, so a seventh A, an
# AAAA, or six committed ids that all miss the live records stop the dry run as well as the apply. The zone and the ids are literals: no argument or environment value can choose
# what this deletes.
#
# Exit: 0 ok or dry run, 1 refused or partial, 2 usage, 78 xtrace.
set -uo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac
umask 077

readonly P="cf-tunnel-host-predelete"
readonly ZONE_ID="951ce525552201ec6c696b24251abed7"
readonly CF_API="https://api.cloudflare.com/client/v4"
# THE SIX RECORD IDS (not secret). EMPTY ON PURPOSE: as of this commit they are in no plan, spec or
# archive of this repository, so the script refuses (reason=pins-missing) until a reviewed PR commits
# them here, one bare 32-hex id per line.
readonly PINNED_IDS=(
)
readonly ALLOWED_NAMES=(ssh.soleur.ai registry.soleur.ai)
readonly CENSUS_NAMES=(deploy.soleur.ai ssh.soleur.ai registry.soleur.ai)
readonly ALLOWED_CONTENT=(104.26.10.163 104.26.11.163 172.67.73.132)

refuse() { # <reason> <message> [<extra fields>]
  printf '%s verdict=refuse reason=%s%s\n' "$P" "$1" "${3:+ $3}"
  printf '::error title=%s::%s\n' "$P" "$2"
  exit 1
}
in_set() { # <value> <member>...
  local v="$1" m; shift
  for m in "$@"; do [[ "$v" == "$m" ]] && return 0; done
  return 1
}
csv() { local IFS=,; printf '%s' "$*"; }

self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || refuse setup "cannot resolve the script directory"
# shellcheck source=/dev/null
source "$self/../../../../scripts/lib/bearer-curl.sh" || refuse setup "cannot load scripts/lib/bearer-curl.sh"

check_pins() {
  local id
  local -A seen=()
  [[ "${#PINNED_IDS[@]}" -eq 6 ]] \
    || refuse pins-missing "the script pins ${#PINNED_IDS[@]} record ids, want exactly 6. Commit the six ids in a reviewed PR; nothing was read or deleted." "count=${#PINNED_IDS[@]}"
  for id in "${PINNED_IDS[@]}"; do
    [[ "$id" =~ ^[0-9a-f]{32}$ && -z "${seen[$id]:-}" ]] \
      || refuse pins-missing "a pinned id is malformed or repeated; nothing was read or deleted."
    seen[$id]=1
  done
}

API_RC=0 API_CODE="" API_BODY=""
api() { # <GET|DELETE> <id> | GET ?name=<fqdn>&per_page=100
  local out rc=0 sfx="/$2"
  [[ "$2" == '?'* ]] && sfx="$2"
  out="$(bc_curl cf-tunnel-host-predelete 'Authorization:Bearer :CF_API_TOKEN' -- \
    -sS --max-time 15 -X "$1" -w '\n%{http_code}' "$CF_API/zones/$ZONE_ID/dns_records$sfx")" || rc=$?
  API_RC="$rc"
  API_CODE="${out##*$'\n'}"
  API_BODY="${out%$'\n'*}"
}

PRESENT=()
ABSENT=()
bad=0
foreign=0
unread=0
refuse_checked() { refuse record-mismatch "a pinned record is not in the broken shape (see the field= lines); nothing was deleted. Read it before any change."; }
refuse_foreign() { refuse foreign-record "a record on a CNAME name is neither a pinned record in the broken shape nor the tunnel's own CNAME (see the verdict=foreign lines), so the CNAME create would collide; nothing was deleted. Read it, then pin or remove it in a reviewed change."; }
refuse_unread() { refuse record-unreadable "a pinned record could not be read (see the http= or e= lines), so it cannot be graded; nothing was deleted. Re-run."; }

grade_all() {
  local id parsed ok rid name type proxied content field
  for id in "${PINNED_IDS[@]}"; do
    api GET "$id"
    if [[ "$API_RC" -ne 0 ]]; then
      printf '%s id=%s e=%s\n' "$P" "$id" "$API_RC"; unread=1; continue
    fi
    case "$API_CODE" in
      404)
        if jq -e '.success == false and any(.errors[]?; .code == 81044)' <<<"$API_BODY" >/dev/null 2>&1; then
          ABSENT+=("$id"); printf '%s id=%s action=already-absent\n' "$P" "$id"
        else
          printf '%s id=%s http=404\n' "$P" "$id"; unread=1
        fi
        continue ;;
      200) ;;
      *) printf '%s id=%s http=%s\n' "$P" "$id" "${API_CODE:0:3}"; unread=1; continue ;;
    esac
    field=""
    parsed="$(jq -er '[(.success == true), .result.id, .result.name, .result.type, (.result.proxied == true), .result.content]
      | map(tostring) | join("\u001f")' <<<"$API_BODY" 2>/dev/null)" || field=body
    IFS=$'\x1f' read -r ok rid name type proxied content <<<"$parsed"
    [[ -n "$field" || "${ok:-}" == true ]] || field=success
    [[ "${rid:-}" == "$id" ]] || field="${field:-id}"
    in_set "${name:-}" "${ALLOWED_NAMES[@]}" || field="${field:-name}"
    [[ "${type:-}" == A ]] || field="${field:-type}"
    [[ "${proxied:-}" == true ]] || field="${field:-proxied}"
    in_set "${content:-}" "${ALLOWED_CONTENT[@]}" || field="${field:-content}"
    if [[ -n "$field" ]]; then
      printf '%s id=%s field=%s verdict=mismatch\n' "$P" "$id" "$field"; bad=1; continue
    fi
    PRESENT+=("$id")
    printf '%s id=%s name=%s type=A proxied=true content=%s verdict=match\n' "$P" "$id" "$name" "$content"
  done
  census
  # A definite mismatch outranks a read with no verdict.
  [[ "$bad" -eq 0 ]] || refuse_checked
  [[ "$foreign" -eq 0 ]] || refuse_foreign
  [[ "$unread" -eq 0 ]] || refuse_unread
}

# census: every record on the three CNAME names (NAME CENSUS in the header). Prints id, type and
# verdict, never content.
census() {
  local n rows rid type kind
  for n in "${CENSUS_NAMES[@]}"; do
    api GET "?name=$n&per_page=100"
    if [[ "$API_RC" -ne 0 || "$API_CODE" != 200 ]]; then
      printf '%s name=%s list http=%s e=%s\n' "$P" "$n" "${API_CODE:0:3}" "$API_RC"; unread=1; continue
    fi
    rows="$(jq -er --arg n "$n" 'if .success != true or (.result | type) != "array"
        or (.result_info.total_count // -1) != (.result | length) then error("short") else . end
      | .result[] | select(.name == $n)
      | [.id, .type, (if .type == "CNAME" and .proxied == true and ((.content // "") | test("^[0-9a-f-]+\\.cfargotunnel\\.com$")) then "tunnel" else "other" end)]
      | map(tostring) | join("\u001f")' <<<"$API_BODY" 2>/dev/null)" \
      || { [[ "$(jq -r '.result | length' <<<"$API_BODY" 2>/dev/null)" == 0 && "$(jq -r '.result_info.total_count' <<<"$API_BODY" 2>/dev/null)" == 0 ]] \
           || { printf '%s name=%s list=unreadable\n' "$P" "$n"; unread=1; continue; }; rows=""; }
    while IFS=$'\x1f' read -r rid type kind; do
      [[ -n "$rid" ]] || continue
      # A pinned id is graded by its own read above; one listed after it read as gone is unread.
      if in_set "$rid" "${PINNED_IDS[@]}"; then
        if in_set "$rid" ${ABSENT[@]+"${ABSENT[@]}"}; then printf '%s name=%s id=%s list=listed-after-404\n' "$P" "$n" "$rid"; unread=1; fi
        continue
      fi
      [[ "$kind" == tunnel ]] && continue
      printf '%s name=%s id=%s type=%s verdict=foreign\n' "$P" "$n" "$rid" "$type"; foreign=1
    done <<<"$rows"
  done
}

delete_all() {
  local i id
  local -a done_ids=()
  for ((i = 0; i < ${#PRESENT[@]}; i++)); do
    id="${PRESENT[$i]}"
    api DELETE "$id"
    if [[ "$API_RC" -ne 0 || "$API_CODE" != 200 ]] || ! jq -e '.success == true' <<<"$API_BODY" >/dev/null 2>&1; then
      printf '%s verdict=partial deleted=%s failed=%s not_attempted=%s\n' "$P" \
        "$(csv ${done_ids[@]+"${done_ids[@]}"})" "$id" "$(csv "${PRESENT[@]:i+1}")"
      printf '::error title=%s::the DELETE of %s failed (http=%s e=%s); the records named deleted= are gone. Re-run: a pinned id that answers 404 counts as already gone.\n' \
        "$P" "$id" "${API_CODE:0:3}" "$API_RC"
      exit 1
    fi
    done_ids+=("$id")
    printf '%s id=%s action=deleted\n' "$P" "$id"
  done
  for id in ${done_ids[@]+"${done_ids[@]}"}; do
    api GET "$id"
    if [[ "$API_RC" -ne 0 || "$API_CODE" != 404 ]]; then
      refuse still-present "record $id did not read back as gone after its DELETE (http=${API_CODE:0:3} e=$API_RC). Read it before re-running." "id=$id"
    fi
  done
}

main() {
  local mode=dry
  case "$#:${1:-}" in
    0:) ;;
    1:--apply) mode=apply ;;
    1:--check-pins) mode=pins ;;
    *) printf 'usage: %s [--apply | --check-pins]\n' "${0##*/}" >&2; exit 2 ;;
  esac
  check_pins
  if [[ "$mode" == pins ]]; then printf '%s verdict=pins-ok count=%s\n' "$P" "${#PINNED_IDS[@]}"; return 0; fi
  [[ -n "${CF_API_TOKEN:-}" ]] || refuse no-token "CF_API_TOKEN is not set; nothing was read or deleted."
  command -v jq >/dev/null 2>&1 || refuse no-jq "jq is required; nothing was read or deleted."
  grade_all
  if [[ "$mode" == dry ]]; then
    printf '%s verdict=dry-run would_delete=%s absent=%s\n' "$P" "${#PRESENT[@]}" "${#ABSENT[@]}"
    return 0
  fi
  delete_all
  printf '%s verdict=ok deleted=%s absent=%s\n' "$P" "${#PRESENT[@]}" "${#ABSENT[@]}"
}

main "$@"
