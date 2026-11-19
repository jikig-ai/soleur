# shellcheck shell=bash
# Phase gate for the #12931 Cloudflare account migration (Guard 1 of the plan,
# knowledge-base/project/plans/2026-11-18-infra-cloudflare-migrate-terraform-to-soleur-account-plan.md).
#
# Sourced by the cf-account-migrate job and by tests/scripts/test-cf-account-migrate-gate.sh,
# so the bytes the job runs are the bytes under test.
#
# PROPERTY. A cf-account-migrate plan applies only if it destroys nothing outside the phase's
# declared replace set, changes only addresses in the phase's allow-set, and every planned
# Cloudflare object carries the NEW zone or account id. R2 resources stay on the legacy account
# and may appear only as no-op.
#
# ONE LIST PER PHASE. cf_account_migrate_phase_spec is the single source: the job generates its
# -target and -replace args from it (cf_account_migrate_targets / _replaces), the gate grades the
# plan against it, and apps/web-platform/infra/scripts/cf-account-migration-complete.sh reads it for "every migrated
# address is in state". Widening a phase is a reviewed diff here and nowhere else.
#
# Classes:
#   create   planned ["create"], or ["no-op"] on a re-dispatch.
#   import   an import block in apps/web-platform/infra/cf-account-migration-imports.tf. Planned as
#            a PURE no-op import whose id equals the committed literal, or plain ["no-op"] once in
#            state. A create means the import block was switched off: refused (it would collide).
#   mutable  a non-Cloudflare secret whose value follows the new ids: update, create or no-op.
#   replace  passed as -replace: must be a replace with action_reason "replace_by_request" whose
#            `before` physical id equals the pre-plan state id (Terraform drops a -replace outside
#            the -target set without a warning; measured on 1.10.5).
#
# The new ids are constants, not inputs (any other id, old or unknown, is refused): a mis-set Doppler value must not be able to
# re-point what the gate accepts. Not secrets.
#
# Usage:
#   source tests/scripts/lib/cf-account-migrate-gate.sh
#   cf_account_migrate_targets  <phase>                       # one -target=<addr> per line
#   cf_account_migrate_replaces <phase>                       # one -replace=<addr> per line
#   cf_account_migrate_gate     <phase> <plan.json> [<state.json>]   # 0=PASS, 1=REFUSE
#     <state.json> = `terraform show -json` of state BEFORE the plan; required for a phase with
#     a replace set.

if ! declare -F plan_gate_assert_readable >/dev/null 2>&1; then
  _CFAM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=/dev/null
  source "${_CFAM_DIR}/plan-gate-preamble.sh"
fi

CFAM_NEW_ZONE_ID="951ce525552201ec6c696b24251abed7"
CFAM_NEW_ACCOUNT_ID="66d4f93f7397f196544e9fe84c3557c2"
CFAM_IMPORTS_FILE="${CFAM_IMPORTS_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)/apps/web-platform/infra/cf-account-migration-imports.tf}"

cf_account_migrate_phases() { printf '%s\n' redirects-dns zone-rest; }

# cf_account_migrate_phase_spec <phase> — JSON object {address: class}. The ONE list.
cf_account_migrate_phase_spec() {
  case "${1-}" in
    redirects-dns)
      cat <<'JSON'
{
  "cloudflare_ruleset.allowlist_ai_crawlers": "create",
  "cloudflare_ruleset.cache_shared_binaries": "create",
  "cloudflare_ruleset.seo_config_settings": "create",
  "cloudflare_ruleset.seo_page_redirects": "create",
  "cloudflare_ruleset.seo_response_headers": "create",
  "cloudflare_ruleset.bulk_redirects": "create",
  "cloudflare_list.legal_redirects": "create",
  "cloudflare_list.www_canonical": "create",
  "doppler_secret.cf_zone_id_prd": "create",
  "cloudflare_record.dkim_resend": "import",
  "cloudflare_record.spf_send": "import",
  "cloudflare_record.mx_send": "import",
  "cloudflare_record.dkim_resend_send": "import",
  "cloudflare_record.spf_send_send": "import",
  "cloudflare_record.mx_send_send": "import",
  "cloudflare_record.dkim_resend_inbound": "import",
  "cloudflare_record.spf_send_inbound": "import",
  "cloudflare_record.mx_send_inbound": "import",
  "cloudflare_record.mx_receiving_inbound": "import",
  "cloudflare_record.dmarc": "import",
  "cloudflare_record.supabase_custom_domain": "import",
  "cloudflare_record.supabase_acme_challenge": "import",
  "cloudflare_record.spf_root": "import",
  "cloudflare_record.google_site_verification": "import",
  "cloudflare_record.protonmail_verification": "import",
  "cloudflare_record.protonmail_mx_primary": "import",
  "cloudflare_record.protonmail_mx_secondary": "import",
  "cloudflare_record.protonmail_dkim_1": "import",
  "cloudflare_record.protonmail_dkim_2": "import",
  "cloudflare_record.protonmail_dkim_3": "import",
  "cloudflare_record.pages_apex": "import",
  "cloudflare_record.www": "import",
  "cloudflare_record.github_pages_challenge": "import",
  "cloudflare_record.buttondown_ns1": "import",
  "cloudflare_record.buttondown_ns2": "import",
  "cloudflare_pages_project.docs": "import",
  "cloudflare_pages_domain.apex": "import",
  "cloudflare_pages_domain.www": "import"
}
JSON
      ;;
    zone-rest)
      cat <<'JSON'
{
  "cloudflare_zone_settings_override.soleur_ai": "create",
  "cloudflare_bot_management.soleur_ai": "create",
  "github_actions_secret.cloudflare_api_token_pages": "mutable",
  "github_actions_secret.cloudflare_account_id_pages": "mutable",
  "doppler_secret.cf_api_token_dns_edit": "replace"
}
JSON
      ;;
    *) return 1 ;;
  esac
}

cf_account_migrate_targets() {
  local spec
  spec="$(cf_account_migrate_phase_spec "${1-}")" || { echo "cf_account_migrate_targets: unknown phase '${1-}'" >&2; return 1; }
  jq -r 'keys_unsorted[] | "-target=" + .' <<<"$spec"
}

cf_account_migrate_replaces() {
  local spec
  spec="$(cf_account_migrate_phase_spec "${1-}")" || { echo "cf_account_migrate_replaces: unknown phase '${1-}'" >&2; return 1; }
  jq -r 'to_entries[] | select(.value=="replace") | "-replace=" + .key' <<<"$spec"
}

# _cfam_import_literals — JSON {address: id} from the imports file (plain import set only).
_cfam_import_literals() {
  [[ -r "$CFAM_IMPORTS_FILE" ]] || { echo "cf_account_migrate_gate: imports file unreadable: $CFAM_IMPORTS_FILE" >&2; return 1; }
  awk '
    /^import \{/ {inblk=1; to=""; id=""; app=0; next}
    inblk && /for_each/ {app=($0 ~ /cf_migration_import_app_set/)}
    inblk && /^[[:space:]]*to[[:space:]]*=/ {sub(/^[^=]*=[[:space:]]*/,""); sub(/[[:space:]]*(#.*)?$/,""); to=$0}
    inblk && /^[[:space:]]*id[[:space:]]*=/ {sub(/^[^=]*=[[:space:]]*"/,""); sub(/".*/,""); id=$0}
    inblk && /^\}/ {if (!app && to != "" && id != "") print to "\t" id; inblk=0}
  ' "$CFAM_IMPORTS_FILE" | jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add // {}'
}

# A check that cannot be evaluated is a refusal, never an empty violation list (an empty list
# reads as PASS). Every violation query below ends in `|| { _cfam_eval_fail; return 1; }`.
_cfam_eval_fail() { echo "cf_account_migrate_gate: REFUSE — a check could not be evaluated (jq error); fail-closed"; }

cf_account_migrate_gate() {
  local phase="${1-}" plan_json="${2-}" state_json="${3-}"
  # Arm switches. Each is a mutation anchor for the suite; production never changes them.
  local _cfam_refuse_destroy=1 _cfam_check_ids=1 _cfam_check_pure=1 _cfam_check_literal=1
  local _cfam_check_present=1 _cfam_check_reason=1 _cfam_check_physid=1
  local spec literals violations="" v creates imports destroys

  spec="$(cf_account_migrate_phase_spec "$phase")" || { echo "cf_account_migrate_gate: REFUSE — unknown phase '${phase}'"; return 1; }
  plan_gate_assert_readable     "cf_account_migrate_gate" "$plan_json" || return 1
  plan_gate_assert_classifiable "cf_account_migrate_gate" "$plan_json" || return 1
  if ! jq -e '.resource_changes | length > 0' "$plan_json" >/dev/null 2>&1; then
    echo "cf_account_migrate_gate: REFUSE — the plan has zero resource_changes (0 checked is not a pass)"
    return 1
  fi
  literals="$(_cfam_import_literals)" || return 1

  if [[ "$(jq -r '[to_entries[] | select(.value=="replace")] | length' <<<"$spec")" -gt 0 ]]; then
    if [[ -z "$state_json" || ! -r "$state_json" ]] || ! jq -e '.values' "$state_json" >/dev/null 2>&1; then
      echo "cf_account_migrate_gate: REFUSE — phase ${phase} declares a replace set and needs the pre-plan state JSON (terraform show -json) to bind each replace to its physical id"
      return 1
    fi
  else
    state_json=""
  fi

  # Every check below appends violation lines; all are reported, then the verdict.
  if [[ "$_cfam_refuse_destroy" -eq 1 ]]; then
    v="$(jq -r --argjson spec "$spec" '
      .resource_changes[] | select((.mode // "managed") == "managed")
      | select((.change.actions | index("forget")) or
               ((.change.actions | index("delete")) and ($spec[.address] != "replace")))
      | "REFUSE destroys or forgets \(.address) (actions \(.change.actions | tostring))"' "$plan_json")" || { _cfam_eval_fail; return 1; }
    violations+="${v:+$v$'\n'}"
  fi

  v="$(jq -r --argjson spec "$spec" --arg phase "$phase" '
    .resource_changes[]
    | select((.mode // "managed") == "managed")
    | select($spec[.address] == null)
    | select(.change.actions != ["no-op"] or .change.importing != null)
    | "REFUSE \(.address) is outside the \($phase) allow-set (actions \(.change.actions | tostring))"' "$plan_json")" || { _cfam_eval_fail; return 1; }
  violations+="${v:+$v$'\n'}"

  v="$(jq -r --argjson spec "$spec" '
    .resource_changes[] | select((.mode // "managed") == "managed") | . as $rc | $spec[.address] as $cls
    | select($cls != null)
    | select(
        ($cls == "create"  and .change.importing == null and (.change.actions != ["create"] and .change.actions != ["no-op"])) or
        ($cls == "create"  and .change.importing != null) or
        ($cls == "import"  and .change.importing == null and .change.actions != ["no-op"]) or
        ($cls == "mutable" and ([.change.actions] | inside([["update"],["no-op"],["create"]]) | not)) or
        ($cls == "replace" and .change.actions != ["delete","create"] and .change.actions != ["create","delete"]))
    | "REFUSE \(.address) (class \($cls)) planned with actions \(.change.actions | tostring)\(if .change.importing then " as an import" else "" end)"' "$plan_json")" || { _cfam_eval_fail; return 1; }
  # An import of a create-class address is reported by the literal check below, which names it.
  # grep -v exits 1 when every line was filtered (fine) and 2 on an error, which is a refusal:
  # a check that cannot be evaluated is a refusal, never "no violation lines".
  v="$(grep -v ' (class create) .* as an import$' <<<"$v")"; local gv_rc=$?
  (( gv_rc <= 1 )) || { _cfam_eval_fail; return 1; }
  violations+="${v:+$v$'\n'}"

  if [[ "$_cfam_check_pure" -eq 1 ]]; then
    v="$(jq -r '.resource_changes[] | select(.change.importing != null) | select(.change.actions != ["no-op"])
      | "REFUSE \(.address) is not a pure no-op import (actions \(.change.actions | tostring)): a mis-pinned import id writes to the zone under cover of an import"' "$plan_json")" || { _cfam_eval_fail; return 1; }
    violations+="${v:+$v$'\n'}"
  fi

  if [[ "$_cfam_check_literal" -eq 1 ]]; then
    v="$(jq -r --argjson spec "$spec" --argjson lit "$literals" '
      .resource_changes[] | select(.change.importing != null)
      | select($spec[.address] != "import" or $lit[.address] == null or .change.importing.id != $lit[.address])
      | "REFUSE import of \(.address) differs from the committed literal (planned \(.change.importing.id // "null"), committed \($lit[.address] // "none"))"' "$plan_json")" || { _cfam_eval_fail; return 1; }
    violations+="${v:+$v$'\n'}"
  fi

  if [[ "$_cfam_check_ids" -eq 1 ]]; then
    v="$(jq -r --arg nz "$CFAM_NEW_ZONE_ID" --arg na "$CFAM_NEW_ACCOUNT_ID" '
      .resource_changes[] | select((.mode // "managed") == "managed")
      | select(.type | startswith("cloudflare_")) | select(.type != "cloudflare_r2_bucket")
      | select(.change.after != null)
      | select(((.change.after.zone_id // $nz) != $nz) or ((.change.after.account_id // $na) != $na))
      | "REFUSE \(.address) carries an id that is not the new zone/account (zone_id \(.change.after.zone_id // "null"), account_id \(.change.after.account_id // "null"))"' "$plan_json")" || { _cfam_eval_fail; return 1; }
    violations+="${v:+$v$'\n'}"
  fi

  if [[ "$_cfam_check_present" -eq 1 ]]; then
    v="$(jq -r --argjson spec "$spec" '[.resource_changes[].address] as $have
      | $spec | keys_unsorted[] | select(. as $a | $have | index($a) | not)
      | "REFUSE \(.) is missing from the plan (every allow-set address must be planned; a dropped -target or a disabled import reads as success otherwise)"' "$plan_json")" || { _cfam_eval_fail; return 1; }
    violations+="${v:+$v$'\n'}"
  fi

  if [[ -n "$state_json" ]]; then
    if [[ "$_cfam_check_reason" -eq 1 ]]; then
      v="$(jq -r --argjson spec "$spec" '.resource_changes[] | select($spec[.address] == "replace")
        | select(.action_reason != "replace_by_request")
        | "REFUSE \(.address) is a declared -replace but action_reason is \(.action_reason // "null"), not replace_by_request (the -replace flag was dropped)"' "$plan_json")" || { _cfam_eval_fail; return 1; }
      violations+="${v:+$v$'\n'}"
    fi
    if [[ "$_cfam_check_physid" -eq 1 ]]; then
      v="$(jq -r --argjson spec "$spec" --slurpfile st "$state_json" '
        ([$st[0].values | .. | objects | select(has("address") and has("values")) | {(.address): .values.id}] | add // {}) as $ids
        | .resource_changes[] | select($spec[.address] == "replace")
        | select(.change.before.id == null or .change.before.id != $ids[.address])
        | "REFUSE \(.address) replace targets physical id \(.change.before.id // "null") but pre-plan state holds \($ids[.address] // "null")"' "$plan_json")" || { _cfam_eval_fail; return 1; }
      violations+="${v:+$v$'\n'}"
    fi
  fi

  creates="$(jq -r '[.resource_changes[] | select(.change.actions == ["create"])] | length' "$plan_json")" || { _cfam_eval_fail; return 1; }
  imports="$(jq -r '[.resource_changes[] | select(.change.importing != null)] | length' "$plan_json")" || { _cfam_eval_fail; return 1; }
  destroys="$(jq -r '[.resource_changes[] | select(.change.actions | index("delete"))] | length' "$plan_json")" || { _cfam_eval_fail; return 1; }
  plan_gate_assert_numeric "cf_account_migrate_gate" "creates=${creates}" "imports=${imports}" "destroys=${destroys}" || return 1

  if [[ -n "$violations" ]]; then
    printf '%s' "$violations"
    echo "cf_account_migrate_gate: phase=${phase} verdict=REFUSE creates=${creates} imports=${imports} destroys=${destroys}"
    return 1
  fi
  echo "cf_account_migrate_gate: phase=${phase} verdict=PASS creates=${creates} imports=${imports} destroys=${destroys}"
  return 0
}
