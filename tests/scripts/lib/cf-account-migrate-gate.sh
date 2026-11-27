# shellcheck shell=bash
# Phase gate for the #12931 Cloudflare account migration (Guard 1 of the plan,
# knowledge-base/project/plans/archive/20261120-013510-2026-11-18-infra-cloudflare-migrate-terraform-to-soleur-account-plan.md).
#
# Sourced by the cf-account-migrate job and by tests/scripts/test-cf-account-migrate-gate.sh,
# so the bytes the job runs are the bytes under test.
#
# PROPERTY. A cf-account-migrate plan applies only if it destroys nothing outside the phase's
# declared replace set, changes only addresses in the phase's allow-set, and every planned
# Cloudflare object positively carries the NEW zone or account id (absent, null or unknown is
# not the new id). R2 resources (every cloudflare_r2_* type) stay on the legacy account and may
# appear only as no-op.
#
# ONE LIST PER PHASE. cf_account_migrate_phase_spec is the single source: the job generates its
# -target and -replace args from it (cf_account_migrate_targets / _replaces), the gate grades the
# plan against it, and apps/web-platform/infra/scripts/cf-account-migration-complete.sh reads it for "every migrated
# address is in state". Widening a phase is a reviewed diff here and nowhere else.
#
# Classes:
#   create   planned ["create"], or ["no-op"] on a re-dispatch, or ["update"] of an address already
#            in the pre-plan state whose `before` carries a NEW id (a fix-forward re-dispatch that
#            corrects a rule the phase created; refused without the pre-plan state). On a PASS,
#            each such update prints `cf_account_migrate_gate: in-state-update <address>` on its
#            own line, so a rehearsal shows which rules a fix would overwrite. A REFUSE prints
#            none (nothing is applied, so nothing would be overwritten).
#   import   an import block in apps/web-platform/infra/cf-account-migration-imports.tf. Planned as
#            a no-op import whose id equals the committed literal, plain ["no-op"] once in state, or
#            the one admitted IMPORT-NORMALIZE update below. A create means the import block was
#            switched off: refused (it would collide).
#   mutable  a non-Cloudflare secret whose value follows the new ids: update, create or no-op.
#   replace  passed as -replace: must be a replace with action_reason "replace_by_request" whose
#            `before` physical id equals the pre-plan state id (Terraform drops a -replace outside
#            the -target set without a warning; measured on 1.10.5). Delete-then-create ONLY:
#            doppler_secret.cf_api_token_dns_edit is keyed by project/config/name, so a
#            create-before-destroy replace would delete the key it had just written. The other
#            member, random_id.tunnel_secret (tunnel phase), has a physical id that IS its secret
#            (base64url of the bytes), so a refusal never prints the id of a random_* address.
#
# IMPORT-NORMALIZE (CTO ruling 2026-11-22, ADR-329). The provider's Read fills `content` only when it
# is already set, so every cloudflare_record import plans ["update"] with `+ allow_overwrite = false`
# and `+ content = <value>`. That one update is admitted for an import-class cloudflare_record whose
# shape and pin hold (_CFAM_NORMALIZE_JQ and the `why` field) and whose live read, taken after the plan
# and passed as the fourth argument, matches its planned `after`. One record whose read is not clean
# admits nothing, and only that record is named, so a failed read cannot look like 26 wrong values.
# A fourth argument that is not a usable read refuses the plan. On a PASS each admitted record prints
# `cf_account_migrate_gate: import-normalize <address>`, never `in-state-update`.
# In the gate and the post-apply re-read alike, a live `settings` of exactly {"flatten_cname":false}
# compares equal when the record is a CNAME both live and in the plan and the plan holds no `settings`
# (CTO ruling 2026-11-25, #13056). Provider 4.52.7 has no `settings` attribute; cloudflare-go v0.116.0
# sends `"settings":{}` (a non-pointer struct, which `omitempty` does not drop, whose nil
# `flatten_cname` pointer is omitted); Cloudflare's OpenAPI defaults `flatten_cname` to false. So
# either outcome of the PATCH leaves it false. That is inferred from source, not observed: the
# post-apply re-read is what detects any other outcome. Every other `settings` value is still refused,
# and a plan that carries `settings` (a later provider) is refused rather than assumed equal.
#
# The new ids are constants, not inputs (any other id, old or unknown, is refused): a mis-set Doppler value must not be able to
# re-point what the gate accepts. Not secrets.
#
# EXPECTED VALUES (contract). _cfam_expected_values is a closed table of EVERY non-Cloudflare spec
# member, with every attribute its .tf block sets to a constant:
#   doppler_secret.cf_zone_id_prd (cf-runtime-zone-id.tf): project soleur, config prd, name
#     CF_ZONE_ID, value the NEW zone id;
#   github_actions_secret.cloudflare_account_id_pages (cf-pages.tf): repository soleur, secret_name
#     CLOUDFLARE_ACCOUNT_ID_PAGES, plaintext_value the NEW account id;
#   github_actions_secret.cloudflare_api_token_pages (cf-pages.tf): repository soleur, secret_name
#     CLOUDFLARE_API_TOKEN_PAGES (its plaintext_value is a token: not in the table);
#   doppler_secret.cf_api_token_dns_edit (cf-cert-reissue-token.tf): project soleur, config prd, name
#     CF_API_TOKEN_DNS_EDIT, visibility masked (its value is a token: not in the table);
#   doppler_secret.registry_push_access_token_id and _secret (tunnel.tf): project soleur, config prd,
#     name REGISTRY_PUSH_ACCESS_TOKEN_ID / _SECRET, visibility masked (their value follows the token
#     the same plan creates, known only after apply: not in the table);
#   random_id.tunnel_secret (tunnel.tf): byte_length 32 (it has no value attribute).
# Any planned action with a non-null `after` (create, update, no-op, and the create half of the
# declared replace) must carry each attribute exactly: absent, another value, or known only after
# apply (after_unknown) is refused. The check runs on the plan JSON, which holds a sensitive
# attribute's value in clear (after_sensitive only marks it), so a sensitive value is graded, not
# skipped. The suite pins that every non-Cloudflare spec member is in this table, that the table's
# attributes equal the .tf block's constant attributes, and that exactly its own literal list of
# token-valued members carries no value attribute.
# RESIDUALS: the VALUE of the two token-valued members is not graded (no constant can name a
# credential); in this gate only the old-id check (no OLD zone or account id inside it) sees it.
# The job's token preflight probes each phase's PROVIDER tokens (cf_account_migrate_phase_tokens,
# CTO D8), which for zone-rest are neither of them: cf_api_token_pages is probed only by the earlier
# redirects-dns run, and cf_api_token_dns_edit by no job step. What vouches for those two values is
# the bootstrap: swap-0a/0b's scope probe and active check on the staged copy, and verify's per-key
# old-vs-new read. Their destination attributes ARE graded above.
#
# SPEC SHAPE (contract). A phase spec is one flat JSON object naming each address once with a string
# class: a value other than one of the four class strings (a nested object or array included) or a
# key written twice refuses the phase before any plan entry is graded.
#
# ACCESS CONTENT (tunnel phase, contract). This gate is the only path that creates these addresses
# (the routine deploy-policy gate refuses a create), so it grades what they admit. Each of the three
# policies (_cfam_access_policies) must plan decision non_identity and exactly one include block
# holding service_token and no other selector, known or known-only-after-apply; its configuration
# include must reference exactly its own token and its application_id exactly its own app. A token
# the same plan creates is wholly unknown (Terraform collapses a list holding an unknown element, so
# `[token.id, "<another uuid>"]` plans exactly like `[token.id]`, measured on provider 4.52.7), which
# is why _cfam_access_source_violations also reads the committed include blocks of tunnel.tf, located
# beside the imports file. The deploy token is a committed constant, so it must plan as one known
# non-nil UUID; the job then reads it LIVE (cf_account_migrate_deploy_token_id,
# cf_account_migrate_deploy_token_verdict): 200, the name github-actions-deploy, about 8760h to expiry.
# The three Access apps (_cfam_access_apps) are pinned on domain, type, session_duration and zone_id,
# and must leave policies, options_preflight_bypass, self_hosted_domains, destinations and
# cors_headers unset, known or unknown (each can open the host while the four pins hold). The two
# registry-push Doppler secrets must take their value from the registry_push token alone, and the
# tunnel config must route exactly deploy., ssh. and registry.soleur.ai (http://, ssh://, tcp://)
# then the http_status:404 catch-all, and each of those three records must plan a proxied CNAME to
# the tunnel (its content referencing the tunnel id alone while unknown).
#
# ZONE-SCOPED APPS. Provider 4.52.7 plans a zone-scoped Access application's account_id as
# known-after-apply, and may read it back empty. The new-id check admits that for exactly those three
# addresses, in the tunnel phase only, and only with zone_id equal to the NEW zone.
# Usage:
#   source tests/scripts/lib/cf-account-migrate-gate.sh
#   cf_account_migrate_targets  <phase>                       # one -target=<addr> per line
#   cf_account_migrate_replaces <phase>                       # one -replace=<addr> per line
#   cf_account_migrate_gate     <phase> <plan.json> [<state.json> [<live.json>]]   # 0=PASS, 1=REFUSE
#     <state.json> = `terraform show -json` of state BEFORE the plan; required for a phase with
#     a replace set, and the only evidence that lets a create-class address plan as ["update"].
#     <live.json> = the output of cf_account_migrate_live_collect.
#     Output on a REFUSE: `REFUSE ...` lines, then any `cf_account_migrate_gate: import-normalize not
#     admitted for <address> (<reasons>)` lines. On a PASS: any `cf_account_migrate_gate:
#     in-state-update <address>` and `cf_account_migrate_gate: import-normalize <address>` lines.
#     A graded plan ends with ONE `cf_account_migrate_gate: phase=<p> verdict=PASS|REFUSE ...` line.
#     A refusal before grading, or a check that cannot be evaluated, prints its reason and no verdict line.
#   cf_account_migrate_record_pins  <phase>                   # address<TAB>record-id, per pinned record
#   cf_account_migrate_live_collect <phase> <dir>             # live.json from one response file per record
#   cf_account_migrate_live_diff    <phase> <plan> <live>     # address<TAB>fields, per differing record

if ! declare -F plan_gate_assert_readable >/dev/null 2>&1; then
  _CFAM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=/dev/null
  source "${_CFAM_DIR}/plan-gate-preamble.sh"
fi

CFAM_NEW_ZONE_ID="951ce525552201ec6c696b24251abed7"
CFAM_NEW_ACCOUNT_ID="66d4f93f7397f196544e9fe84c3557c2"
# The OLD ids, the state bucket, the forget's backup prefix and the R2 endpoint that holds the
# bucket. One copy: the job, the state forget (apps/web-platform/infra/scripts/
# cf-account-state-migrate.sh) and the completion predicate all source this file. R2 stays on the
# legacy account (ADR-329); a credentialed request's destination is this literal, never an
# environment value (#7873).
CFAM_OLD_ZONE_ID="5af02a2f394e9ba6e0ea23c381a26b67"
CFAM_OLD_ACCOUNT_ID="4d5ba6f096b2686fbdd404167dd4e125"
# shellcheck disable=SC2034 # read by the scripts that source this library
{
  CFAM_STATE_BUCKET="soleur-terraform-state"
  CFAM_BACKUP_PREFIX="web-platform/backups/"
  CFAM_R2_ENDPOINT="https://${CFAM_OLD_ACCOUNT_ID}.r2.cloudflarestorage.com"
}
# cfam_r2_aws <aws args...>: the ONE R2 call shape, for every aws call of the three scripts: region
# auto, checksums only when required (R2 rejects the CLI's default integrity checksums on some
# versions), no instance-metadata lookup, a 60 s bound (rc 124 on a stall), and the pinned
# endpoint. Credentials come from the caller's environment, never argv.
cfam_r2_aws() {
  timeout 60 env AWS_DEFAULT_REGION=auto AWS_REQUEST_CHECKSUM_CALCULATION=when_required \
    AWS_RESPONSE_CHECKSUM_VALIDATION=when_required AWS_EC2_METADATA_DISABLED=true \
    aws "$@" --endpoint-url "$CFAM_R2_ENDPOINT"
}
# cfam_serial_of <state-file>: the numeric serial of a raw tfstate; rc != 0 when it has none.
cfam_serial_of() { jq -er 'if (.serial | type) == "number" then .serial else error("no serial") end' "$1" 2>/dev/null; }
# The committed imports file is what Guard 1 compares import ids against. CFAM_IMPORTS_FILE is a
# test seam for a COPY of this library sourced from a temp dir, whose own path cannot locate the
# file. Wherever the committed file is reachable (the job, the predicate, the suite's own source),
# an override naming any other file is ignored: the environment must not choose the literals the
# gate trusts.
_cfam_imports_default="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd)/apps/web-platform/infra/cf-account-migration-imports.tf"
if [[ -n "${CFAM_IMPORTS_FILE:-}" && -e "$_cfam_imports_default" && ! "$CFAM_IMPORTS_FILE" -ef "$_cfam_imports_default" ]]; then
  echo "cf-account-migrate-gate: ignoring CFAM_IMPORTS_FILE=${CFAM_IMPORTS_FILE} (not the committed imports file)" >&2
  CFAM_IMPORTS_FILE="$_cfam_imports_default"
fi
CFAM_IMPORTS_FILE="${CFAM_IMPORTS_FILE:-$_cfam_imports_default}"

cf_account_migrate_phases() { printf '%s\n' redirects-dns zone-rest tunnel; }

# cf_account_migrate_phase_spec <phase> — JSON object {address: class}. The ONE list.
# cloudflare_ruleset.cache_shared_binaries is in NO phase (CTO ruling D3): caching /api/shared/*
# at the edge while the running containers still purge against the OLD zone would keep serving
# a revoked share. It is created by the routine apply's existing -target at the Phase 3 step 6
# manual-rerun, after the redeploy loads the new purge token.
cf_account_migrate_phase_spec() {
  case "${1-}" in
    redirects-dns)
      cat <<'JSON'
{
  "cloudflare_ruleset.allowlist_ai_crawlers": "create",
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
    tunnel)
      cat <<'JSON'
{
  "random_id.tunnel_secret": "replace",
  "cloudflare_zero_trust_tunnel_cloudflared.web": "create",
  "cloudflare_zero_trust_tunnel_cloudflared_config.web": "create",
  "cloudflare_zero_trust_access_application.deploy": "create",
  "cloudflare_zero_trust_access_application.ssh": "create",
  "cloudflare_zero_trust_access_application.registry": "create",
  "cloudflare_zero_trust_access_policy.deploy_service_token": "create",
  "cloudflare_zero_trust_access_policy.ci_ssh_service_token": "create",
  "cloudflare_zero_trust_access_policy.registry_push_service_token": "create",
  "cloudflare_zero_trust_access_service_token.ci_ssh": "create",
  "cloudflare_zero_trust_access_service_token.registry_push": "create",
  "cloudflare_notification_policy.service_token_expiry": "create",
  "cloudflare_record.deploy": "create",
  "cloudflare_record.ssh": "create",
  "cloudflare_record.registry": "create",
  "cloudflare_record.app": "import",
  "doppler_secret.registry_push_access_token_id": "mutable",
  "doppler_secret.registry_push_access_token_secret": "mutable"
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

# _cfam_import_literals [<phase>] — JSON {address: id} from the imports file: the plain import set,
# plus the app-record block for the tunnel phase only (no other phase may import that address).
_cfam_import_literals() {
  local with_app=0
  [[ "${1-}" != tunnel ]] || with_app=1
  [[ -r "$CFAM_IMPORTS_FILE" ]] || { echo "cf_account_migrate_gate: imports file unreadable: $CFAM_IMPORTS_FILE" >&2; return 1; }
  awk -v with_app="$with_app" '
    /^import \{/ {inblk=1; to=""; id=""; app=0; next}
    inblk && /for_each/ {app=($0 ~ /cf_migration_import_app_set/)}
    inblk && /^[[:space:]]*to[[:space:]]*=/ {sub(/^[^=]*=[[:space:]]*/,""); sub(/[[:space:]]*(#.*)?$/,""); to=$0}
    inblk && /^[[:space:]]*id[[:space:]]*=/ {sub(/^[^=]*=[[:space:]]*"/,""); sub(/".*/,""); id=$0}
    inblk && /^\}/ {if ((!app || with_app) && to != "" && id != "") print to "\t" id; inblk=0}
  ' "$CFAM_IMPORTS_FILE" | jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add // {}'
}

# _cfam_expected_values — JSON {address: {attribute: expected}}: the closed EXPECTED VALUES table
# (header). One `+` line per member, so a member is added or removed as one reviewed line.
_cfam_expected_values() {
  jq -n --arg z "$CFAM_NEW_ZONE_ID" --arg a "$CFAM_NEW_ACCOUNT_ID" '{}
    + {"doppler_secret.cf_zone_id_prd": {project: "soleur", config: "prd", name: "CF_ZONE_ID", value: $z}}
    + {"github_actions_secret.cloudflare_account_id_pages": {repository: "soleur", secret_name: "CLOUDFLARE_ACCOUNT_ID_PAGES", plaintext_value: $a}}
    + {"github_actions_secret.cloudflare_api_token_pages": {repository: "soleur", secret_name: "CLOUDFLARE_API_TOKEN_PAGES"}}
    + {"doppler_secret.cf_api_token_dns_edit": {project: "soleur", config: "prd", name: "CF_API_TOKEN_DNS_EDIT", visibility: "masked"}}
    + {"doppler_secret.registry_push_access_token_id": {project: "soleur", config: "prd", name: "REGISTRY_PUSH_ACCESS_TOKEN_ID", visibility: "masked"}}
    + {"doppler_secret.registry_push_access_token_secret": {project: "soleur", config: "prd", name: "REGISTRY_PUSH_ACCESS_TOKEN_SECRET", visibility: "masked"}}
    + {"random_id.tunnel_secret": {byte_length: 32}}
  '
}

# The deploy policy and the token it must admit (ACCESS CONTENT in the header).
# Plain assignments, like the ids above: this library may be sourced more than once in one shell.
CFAM_DEPLOY_POLICY_ADDR="cloudflare_zero_trust_access_policy.deploy_service_token"
CFAM_DEPLOY_TOKEN_NAME="github-actions-deploy"
# "About 8760h": at most one hour over a year, and at most 31 days under it (the mint precedes the
# tunnel apply by the PR2 review and merge).
CFAM_DEPLOY_TOKEN_MIN_H=8016
CFAM_DEPLOY_TOKEN_MAX_H=8761
CFAM_UUID_RE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
CFAM_NIL_UUID="00000000-0000-0000-0000-000000000000"

# _cfam_access_policies: {policy address: {app, refs, source, constant}}. `refs` is the exact reference
# set of its include's service_token in the plan configuration, `source` the exact right-hand side in
# tunnel.tf, `constant` true when the token is a committed constant (known at plan time).
_cfam_access_policies() {
  jq -n --arg app "cloudflare_zero_trust_access_application" --arg tok "cloudflare_zero_trust_access_service_token" '{
    "cloudflare_zero_trust_access_policy.deploy_service_token":
      {app: ($app + ".deploy"), refs: ["local.deploy_service_token_ids"], source: "local.deploy_service_token_ids", constant: true},
    "cloudflare_zero_trust_access_policy.ci_ssh_service_token":
      {app: ($app + ".ssh"), refs: [($tok + ".ci_ssh"), ($tok + ".ci_ssh.id")], source: ("[" + $tok + ".ci_ssh.id]"), constant: false},
    "cloudflare_zero_trust_access_policy.registry_push_service_token":
      {app: ($app + ".registry"), refs: [($tok + ".registry_push"), ($tok + ".registry_push.id")], source: ("[" + $tok + ".registry_push.id]"), constant: false}
  }'
}

# _cfam_access_apps: {app address: the attributes it must plan}.
_cfam_access_apps() {
  jq -n --arg z "$CFAM_NEW_ZONE_ID" --arg app "cloudflare_zero_trust_access_application" '{
    ($app + ".deploy"): {domain: "deploy.soleur.ai", type: "self_hosted", session_duration: "24h", zone_id: $z},
    ($app + ".ssh"): {domain: "ssh.soleur.ai", type: "self_hosted", session_duration: "15m", zone_id: $z},
    ($app + ".registry"): {domain: "registry.soleur.ai", type: "self_hosted", session_duration: "15m", zone_id: $z}
  }'
}

# _cfam_access_violations <plan.json>: REFUSE lines naming attributes, never values.
_cfam_access_violations() {
  local pol apps
  pol="$(_cfam_access_policies)" || return 1
  apps="$(_cfam_access_apps)" || return 1
  jq -r --argjson pol "$pol" --argjson apps "$apps" --arg re "$CFAM_UUID_RE" --arg nil "$CFAM_NIL_UUID" \
    --argjson unset '["policies","options_preflight_bypass","self_hosted_domains","destinations","cors_headers"]' '
    def blank: . == null or . == false or . == "" or . == [] or . == {};
    def has_unknown: . == true or (type == "array" and any(.[]; . == true));
    . as $root
    | (
      ($pol | to_entries[]) as $e | $e.key as $a | $e.value as $w
      | [$root.resource_changes[] | select(.address == $a)] as $rc
      | if ($rc | length) != 1 then "REFUSE \($a) must appear exactly once in the plan (found \($rc | length))"
        elif ($rc[0].change.after | type) != "object" then "REFUSE \($a) has no planned value"
        else
          $rc[0].change.after as $af | ($rc[0].change.after_unknown // {}) as $u
          | ([$root.configuration.root_module.resources[]? | select(.address == $a) | .expressions][0] // {}) as $x
          | (if $af.decision == "non_identity" and ($u.decision // false) != true then empty
             else "REFUSE \($a) must plan decision non_identity" end),
            (if ($af.include | type) != "array" or ($af.include | length) != 1 or ($af.include[0] | type) != "object"
             then "REFUSE \($a) must plan exactly one include block"
             else
               $af.include[0] as $i
               | (if ($u.include | type) == "array" and ($u.include[0] | type) == "object" then $u.include[0] else {} end) as $iu
               | ($i | to_entries[] | select(.key != "service_token") | select(.value | blank | not)
                  | "REFUSE \($a) include carries another rule (\(.key))"),
                 ($iu | to_entries[] | select(.key != "service_token") | select(.value | blank | not)
                  | "REFUSE \($a) include carries another rule (\(.key), known only after apply)"),
                 (if ($iu.service_token // false | has_unknown) then
                    (if $w.constant then "REFUSE \($a) include must hold exactly one service token" else empty end)
                  elif ($i.service_token | type) != "array" or ($i.service_token | length) != 1
                    then "REFUSE \($a) include must hold exactly one service token"
                  elif ($i.service_token[0] | type) != "string" or ($i.service_token[0] | test($re) | not) or $i.service_token[0] == $nil
                    then "REFUSE \($a) include service token is not a non-nil UUID"
                  else empty end)
             end),
            ($x.include as $xi
             | if ($xi | type) != "array" or ($xi | length) != 1 or ($xi[0] | type) != "object" or ($xi[0] | keys) != ["service_token"]
               then "REFUSE \($a) configuration include must hold only service_token"
               elif (($xi[0].service_token.references // []) | sort) != ($w.refs | sort)
               then "REFUSE \($a) include is not its own committed token reference"
               else empty end),
            (if (($x.application_id.references // []) | sort) == ([$w.app, ($w.app + ".id")] | sort) then empty
             else "REFUSE \($a) application_id does not reference \($w.app)" end)
        end
    ), (
      ($apps | to_entries[]) as $e | $e.key as $a
      | [$root.resource_changes[] | select(.address == $a)] as $rc
      | if ($rc | length) != 1 then "REFUSE \($a) must appear exactly once in the plan (found \($rc | length))"
        elif ($rc[0].change.after | type) != "object" then "REFUSE \($a) has no planned value"
        else
          $rc[0].change.after as $af | ($rc[0].change.after_unknown // {}) as $u
          | ($e.value | to_entries[]
             | if $u[.key] == true then "REFUSE \($a) must plan its Access pin (\(.key) known only after apply)"
               elif $af[.key] != .value then "REFUSE \($a) must plan its Access pin (\(.key) differs)"
               else empty end),
            # The tail of access_app_keys in the routine gate (destroy-guard-filter-web-platform.jq): a
            # reusable policy, a path destination, a preflight bypass or open CORS each opens the host
            # while the four pins above still hold, so each must plan blank, known or unknown.
            ($unset[] as $k
             | if ([$u[$k] | .. | select(. == true)] | length) > 0 then "REFUSE \($a) must leave \($k) unset (known only after apply)"
               elif ($af[$k] | blank | not) then "REFUSE \($a) must leave \($k) unset"
               else empty end)
        end
    ), (
      # Each gated host is a proxied CNAME to this tunnel: an unproxied record, another type or another
      # target would serve the origin with no Access app in front. A first apply plans content unknown,
      # so its configuration must reference the tunnel id alone; a re-dispatch plans it known.
      ("deploy", "ssh", "registry") as $n | ("cloudflare_record." + $n) as $a
      | "REFUSE \($a) must plan a proxied CNAME \($n) to the tunnel" as $m
      | [$root.resource_changes[] | select(.address == $a)] as $rc
      | if ($rc | length) != 1 then "REFUSE \($a) must appear exactly once in the plan (found \($rc | length))"
        else $rc[0].change.after as $af | ($rc[0].change.after_unknown // {}) as $u
          | (([$root.configuration.root_module.resources[]? | select(.address == $a) | .expressions.content.references][0]) // []) as $cr
          | if ($af | type) != "object" then "\($m) (no planned value)"
            elif ($u.type // false) == true or $af.type != "CNAME" then "\($m) (type)"
            elif ($u.proxied // false) == true or $af.proxied != true then "\($m) (proxied)"
            elif ($u.name // false) == true or ($af.name != $n and $af.name != ($n + ".soleur.ai")) then "\($m) (name)"
            elif ($u.content // false) == true then
              (if ($cr | sort) == (["cloudflare_zero_trust_tunnel_cloudflared.web", "cloudflare_zero_trust_tunnel_cloudflared.web.id"] | sort)
               then empty else "\($m) (content)" end)
            elif (($af.content // "") | test("^[0-9a-f-]+\\.cfargotunnel\\.com$")) then empty
            else "\($m) (content)" end
        end
    ), (
      # The tunnel routes exactly the three gated hosts, in order, then the 404 catch-all, each to its
      # own scheme: another hostname or service would reach an origin no Access app gates.
      "cloudflare_zero_trust_tunnel_cloudflared_config.web" as $a
      | [$root.resource_changes[] | select(.address == $a)] as $rc
      | if ($rc | length) != 1 then "REFUSE \($a) must appear exactly once in the plan (found \($rc | length))"
        else ($rc[0].change.after.config // null) as $c | ($rc[0].change.after_unknown.config // []) as $cu
          | if ($c | type) != "array" or ($c | length) != 1 or ($c[0].ingress_rule | type) != "array"
            then "REFUSE \($a) must plan one config block with ingress rules"
            elif ([$cu | .. | select(. == true)] | length) > 0 then "REFUSE \($a) ingress is known only after apply"
            elif ([$c[0].ingress_rule[] | .hostname // ""]) != ["deploy.soleur.ai", "ssh.soleur.ai", "registry.soleur.ai", ""]
            then "REFUSE \($a) must route exactly deploy., ssh. and registry.soleur.ai, then the catch-all"
            else
              (["http://", "ssh://", "tcp://"] | to_entries[]
               | .key as $i | .value as $p
               | if (($c[0].ingress_rule[$i].service // "") | startswith($p)) then empty
                 else "REFUSE \($a) ingress rule \($i + 1) must use \($p)" end),
              (if $c[0].ingress_rule[3].service == "http_status:404" then empty
               else "REFUSE \($a) ingress rule 4 must use http_status:404" end)
            end
        end
    ), (
      # Each registry-push Doppler secret takes its value from the registry_push token alone, so a
      # plan cannot route another token (the CI-SSH secret, say) into the prd runtime config.
      {"doppler_secret.registry_push_access_token_id": "client_id",
       "doppler_secret.registry_push_access_token_secret": "client_secret"}
      | to_entries[] | .key as $a | .value as $f
      | "cloudflare_zero_trust_access_service_token.registry_push" as $t
      | (([$root.configuration.root_module.resources[]? | select(.address == $a) | .expressions.value.references][0]) // []) as $r
      | if ($r | sort) == ([$t, ($t + "." + $f)] | sort) then empty
        else "REFUSE \($a) value is not \($t).\($f)" end
    )' "$1"
}

# _cfam_access_source_violations: each policy's committed block in tunnel.tf holds one literal
# `include {` whose only statement is `service_token = <its own reference>`. Prints no value.
_cfam_access_source_violations() {
  local tf rows a want got n=0
  tf="$(dirname "$CFAM_IMPORTS_FILE")/tunnel.tf"
  if [[ ! -r "$tf" ]]; then
    printf 'REFUSE the committed tunnel.tf is not readable, so the Access include blocks cannot be proven\n'
    return 0
  fi
  rows="$(_cfam_access_policies | jq -r 'to_entries[] | "\(.key)\t\(.value.source)"')" || return 1
  while IFS=$'\t' read -r a want; do
    n=$((n + 1))
    got="$(awk -v h="resource \"${a%%.*}\" \"${a#*.}\" {" '
      $0 == h { n++; d = 1; next }
      d > 0 {
        l = $0; sub(/[[:space:]]*(#|\/\/).*$/, "", l); gsub(/^[[:space:]]+|[[:space:]]+$/, "", l); gsub(/[[:space:]]+/, " ", l)
        if (l == "") next
        if (d == 1 && l == "include {") { inc++; d = 2; ininc = 1; next }
        if (d == 1 && l ~ /^dynamic "include"/) bad = 1
        if (ininc && d == 2 && l == "}") { ininc = 0; d = 1; next }
        if (ininc) { body = l; nb++ }
        t = l; o = gsub(/\{/, "", t); c = gsub(/\}/, "", t); d += o - c
      }
      END { if (n == 1 && inc == 1 && !bad && nb == 1) print body; else print "BAD" }' "$tf")" || return 1
    [[ "$got" == "service_token = $want" ]] \
      || printf 'REFUSE %s committed include is not exactly its own token reference (tunnel.tf)\n' "$a"
  done <<<"$rows"
  [[ "$n" -eq 3 ]] || return 1
}

# cf_account_migrate_deploy_token_id <plan.json>: the one service-token UUID the planned deploy policy
# admits; rc 1 unless the plan names exactly one non-nil UUID.
cf_account_migrate_deploy_token_id() {
  local id
  id="$(jq -r --arg a "$CFAM_DEPLOY_POLICY_ADDR" '
    [.resource_changes[] | select(.address == $a) | .change.after.include[]?.service_token[]?]
    | if length == 1 then .[0] else empty end' "${1-}" 2>/dev/null)" || return 1
  [[ "$id" =~ $CFAM_UUID_RE && "$id" != "$CFAM_NIL_UUID" ]] || return 1
  printf '%s\n' "$id"
}

# cf_account_migrate_deploy_token_verdict <uuid> <now-epoch> (API body on stdin): prints `ok` (rc 0)
# or one reason token (rc 1). Prints no field of the body.
cf_account_migrate_deploy_token_verdict() {
  local v
  v="$(jq -r --arg id "${1-}" --arg name "$CFAM_DEPLOY_TOKEN_NAME" --argjson now "${2:-0}" \
      --argjson lo "$CFAM_DEPLOY_TOKEN_MIN_H" --argjson hi "$CFAM_DEPLOY_TOKEN_MAX_H" '
    if (type != "object") or .success != true or ((.result | type) != "object") then "body-not-success"
    elif .result.id != $id then "id-differs"
    elif .result.name != $name then "name-differs"
    elif (.result.expires_at | type) != "string" then "expiry-absent"
    else ((try (.result.expires_at | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) catch null)) as $e
      | if $e == null then "expiry-unparseable"
        elif (($e - $now) / 3600) < $lo or (($e - $now) / 3600) > $hi then "expiry-out-of-window"
        else "ok" end
    end' 2>/dev/null)" || { printf 'body-unparseable\n'; return 1; }
  [[ -n "$v" ]] || { printf 'body-unparseable\n'; return 1; }
  printf '%s\n' "$v"
  [[ "$v" == ok ]]
}

# A check that cannot be evaluated is a refusal, never an empty violation list (an empty list
# reads as PASS). Every violation query below ends in `|| { _cfam_eval_fail; return 1; }`.
_cfam_eval_fail() { echo "cf_account_migrate_gate: REFUSE — a check could not be evaluated (jq error); fail-closed"; }

# The admitted shape and the live comparator, in one place: the gate and the job's post-apply re-read
# (through cf_account_migrate_live_diff) both evaluate these bytes. cfam_live_diff returns field names
# and closed diagnostic tokens only, never a record value. A diagnostic is added only after the
# comparator has refused that field, so it cannot change a verdict. No jq `//` in a compare: it also
# maps `false` to the fallback.
# shellcheck disable=SC2016 # jq source, expanded by jq
_CFAM_NORMALIZE_JQ='
def cfam_changed: .change as $c | (($c.before|keys)+($c.after|keys)|unique)
  | map(select($c.before[.] != $c.after[.]));
def cfam_norm_shape:
  .type == "cloudflare_record" and .change.actions == ["update"]
  and (.change.before|type) == "object" and (.change.after|type) == "object"
  and cfam_changed == ["allow_overwrite","content"]
  and .change.before.allow_overwrite == null and .change.after.allow_overwrite == false
  and .change.before.content == null
  and (.change.after.content|type) == "string" and (.change.after.content|length) > 0
  and (.change.after_unknown|type) == "object"
  and ([.change.after_unknown|..|booleans|select(.)]|length) == 0;
def cfam_fqdn: if . == "soleur.ai" or endswith(".soleur.ai") then . else . + ".soleur.ai" end;
def cfam_empty: . == null or . == "";
def cfam_unquote: if (type == "string") and length >= 2 and startswith("\"") and endswith("\"") then .[1:-1] else . end;
def cfam_live_diff($after; $entry; $pin; $zone):
  if ($entry|type) != "object" then ["unreadable"]
  elif $entry.status == "notfound" then ["notfound"]
  elif $entry.status != "ok" or ($entry.result|type) != "object"
    or $entry.result.id != $pin
    or ($entry.result.zone_id != null and $entry.result.zone_id != $zone) then ["unreadable"]
  elif ($after|type) != "object" then ["after"]
  else $entry.result as $r
    | [ (if $r.type != $after.type then "type" else empty end),
        (if ($after.name|type) != "string" or ($after.hostname|type) != "string"
            or $after.hostname != ($after.name|cfam_fqdn)
            or $r.name != $after.hostname
            then "name" else empty end),
        (if $r.content != $after.content
            or (($r.content|type) == "string" and ($r.content|endswith(".")))
            then "content" else empty end),
        (if $r.ttl != $after.ttl then "ttl" else empty end),
        (if $r.proxied != $after.proxied then "proxied" else empty end),
        (if $r.priority != $after.priority then "priority" else empty end),
        (if (($r.comment|cfam_empty) and ($after.comment|cfam_empty))
            or (($r.comment|type) == "string" and $r.comment == $after.comment)
            then empty else "comment" end),
        (if ($r.tags|type) == "array" and ($after.tags|type) == "array" and ($r.tags|unique) == ($after.tags|unique)
            then empty else "tags" end),
        (if $r.settings == null or $r.settings == {} then empty
         elif $after.settings == null and $r.settings == {"flatten_cname":false} and $r.type == "CNAME" and $after.type == "CNAME" then empty
         else "settings" end),
        (if $r.data == null or $r.data == {} then empty else "data" end)
      ] as $f
    | $f + [
        (if ($f|index("content")) != null and ($r.content|type) == "string" and ($r.content != $after.content)
            and ($r.content|cfam_unquote) == ($after.content|cfam_unquote) then "content:quoted-equal" else empty end),
        (if ($f|index("tags")) != null and ($r|has("tags")|not) then "tags:absent" else empty end),
        (if ($f|index("settings")) == null then empty
         elif $r.settings == {"flatten_cname":false} then "settings:only-flatten-false"
         else "settings:other" end)
      ]
  end;
'

# _cfam_pins_json (stdin: the record-pins lines) -> {address: record-id}.
_cfam_pins_json() { jq -Rn '[inputs | split("\t") | select(length == 2) | {(.[0]): .[1]}] | add // {}'; }

# cf_account_migrate_record_pins <phase>: one `address<TAB>record-id` line per import-class
# cloudflare_record, from the committed literals. A literal must be exactly <NEW zone>/<32 hex>. Fails
# unless every such record has a pin of its own, because _cfam_import_literals silently drops a block it
# cannot parse. The phase is passed on, so the tunnel phase pins the app record's for_each block.
cf_account_migrate_record_pins() {
  local spec lit
  spec="$(cf_account_migrate_phase_spec "${1-}")" || { echo "cf_account_migrate_record_pins: unknown phase '${1-}'" >&2; return 1; }
  lit="$(_cfam_import_literals "${1-}")" || return 1
  jq -nr --argjson spec "$spec" --argjson l "$lit" --arg z "$CFAM_NEW_ZONE_ID" '
    [$spec | to_entries[] | select(.value == "import" and (.key | startswith("cloudflare_record."))) | .key] as $want
    | [$want[] | . as $a | (($l[$a] // "") | split("/")) as $p
       | select(($p | length) == 2 and $p[0] == $z and ($p[1] | test("^[0-9a-f]{32}$")))
       | "\($a)\t\($p[1])"] as $pins
    | if ($pins | length) != ($want | length)
         or ($pins | map(split("\t")[1]) | unique | length) != ($pins | length)
      then error("a record has no usable or unique pin") else $pins[] end' 2>/dev/null
}

# cf_account_migrate_live_collect <phase> <dir>: live.json {address: {status, result?}} from one raw
# response file per record, <dir>/<record-id>, holding the body then a last line with the HTTP code.
# `ok` needs HTTP 200, success true, an object result, result.id equal to the pin and no other zone. A
# 404 is `notfound`. Anything else, a missing file included, is `unreadable`.
cf_account_migrate_live_collect() {
  local phase="${1-}" dir="${2-}" pins_tsv addr id f code entry out="{}"
  pins_tsv="$(cf_account_migrate_record_pins "$phase")" || return 1
  [[ -n "$pins_tsv" && -d "$dir" ]] || { echo "cf_account_migrate_live_collect: no pins or no response directory" >&2; return 1; }
  while IFS=$'\t' read -r addr id; do
    f="$dir/$id"; entry='{"status":"unreadable"}'
    if [[ -r "$f" ]]; then
      code="$(tail -n1 "$f")"
      if [[ "$code" == 404 ]]; then
        entry='{"status":"notfound"}'
      elif [[ "$code" == 200 ]]; then
        entry="$(sed '$d' "$f" | jq -cs --arg id "$id" --arg z "$CFAM_NEW_ZONE_ID" '
          if length == 1 and (.[0] | type) == "object" and .[0].success == true and (.[0].result | type) == "object"
             and .[0].result.id == $id and (.[0].result.zone_id == null or .[0].result.zone_id == $z)
          then {status:"ok", result:.[0].result} else {status:"unreadable"} end' 2>/dev/null)" \
          || entry='{"status":"unreadable"}'
      fi
    fi
    out="$(jq -c --arg a "$addr" --argjson e "$entry" '. + {($a): $e}' <<<"$out")" || return 1
  done <<<"$pins_tsv"
  printf '%s\n' "$out"
}

# cf_account_migrate_live_diff <phase> <plan.json> <live.json>: one `address<TAB>tokens` line per
# pinned record whose live entry differs from the plan's `after`; empty output means all match. Fails
# on an empty pin list or an unreadable input: "nothing compared" must never read as "no difference".
cf_account_migrate_live_diff() {
  local phase="${1-}" plan="${2-}" live="${3-}" pins_tsv pins
  pins_tsv="$(cf_account_migrate_record_pins "$phase")" || return 1
  [[ -n "$pins_tsv" && -r "$plan" && -r "$live" ]] || { echo "cf_account_migrate_live_diff: no pins, or the plan or live file is unreadable" >&2; return 1; }
  pins="$(_cfam_pins_json <<<"$pins_tsv")" || return 1
  jq -r --argjson pins "$pins" --arg z "$CFAM_NEW_ZONE_ID" --slurpfile lv "$live" "$_CFAM_NORMALIZE_JQ"'
    ([.resource_changes[] | {(.address): .change.after}] | add // {}) as $afters
    | $pins | keys_unsorted[] as $a
    | cfam_live_diff($afters[$a]; $lv[0][$a]; $pins[$a]; $z) as $d
    | select($d != [])
    | "\($a)\t\($d | join(","))"' "$plan"
}

cf_account_migrate_gate() {
  # One declaration per line: test-plan-gate-preamble.sh finds plan-grading gates by the literal
  # `local plan_json`, so a combined declaration hides this gate from its drift sweep.
  local phase="${1-}"
  local plan_json="${2-}"
  local state_json="${3-}"
  local spec literals want violations="" v creates imports destroys n_rep n_raw n_obj admitted gv_rc
  local has_live=false live_json="" pins_tsv pins verdicts norm="[]" norm_why="" live_v="" exempt

  spec="$(cf_account_migrate_phase_spec "$phase")" || { echo "cf_account_migrate_gate: REFUSE — unknown phase '${phase}'"; return 1; }
  plan_gate_assert_readable     "cf_account_migrate_gate" "$plan_json" || return 1
  plan_gate_assert_classifiable "cf_account_migrate_gate" "$plan_json" || return 1
  if ! jq -e '.resource_changes | length > 0' "$plan_json" >/dev/null 2>&1; then
    echo "cf_account_migrate_gate: REFUSE — the plan has zero resource_changes (0 checked is not a pass)"
    return 1
  fi
  literals="$(_cfam_import_literals "$phase")" || return 1
  want="$(_cfam_expected_values)" || { _cfam_eval_fail; return 1; }

  # SPEC SHAPE (header). First the class: a value outside the four class strings (a typo, or a
  # nested object or array) would be graded as nothing by the class check below (any action
  # passes), so it refuses the phase. Then the key count, on the streaming parser, which sees every
  # occurrence: a key written twice parses as its LAST value silently, so the number of top-level
  # values differs from the parsed object's length. A top-level value ends either with a leaf event
  # at depth 1 (a scalar, {} or []) or with the closing event of its own container (path length 2),
  # so an earlier nested copy of a key is counted too. With the class check first, a nested value
  # is never reported as a duplicate.
  # Guarded: a failed jq here yields "", `[[ "" -gt 0 ]]` is false, and the replace arms below
  # would silently be skipped.
  v="$(jq -r '[to_entries[] | select(.value != "create" and .value != "import" and .value != "mutable" and .value != "replace") | "\(.key)=\(.value)"] | join(" ")' <<<"$spec")" || { _cfam_eval_fail; return 1; }
  [[ -z "$v" ]] || { echo "cf_account_migrate_gate: REFUSE — phase ${phase} declares an unknown class (${v}); the classes are create, import, mutable, replace"; return 1; }
  n_raw="$(jq -n --stream '[inputs | select((length == 2 and (.[0] | length) == 1) or (length == 1 and (.[0] | length) == 2))] | length' <<<"$spec")" || { _cfam_eval_fail; return 1; }
  n_obj="$(jq 'length' <<<"$spec")" || { _cfam_eval_fail; return 1; }
  plan_gate_assert_numeric "cf_account_migrate_gate" "spec_keys=${n_raw}" "spec_addresses=${n_obj}" || return 1
  [[ "$n_raw" -eq "$n_obj" ]] || { echo "cf_account_migrate_gate: REFUSE — phase ${phase} declares an address more than once (${n_raw} keys, ${n_obj} distinct); the spec must name each address once"; return 1; }
  n_rep="$(jq -r '[to_entries[] | select(.value=="replace")] | length' <<<"$spec")" || { _cfam_eval_fail; return 1; }
  plan_gate_assert_numeric "cf_account_migrate_gate" "replace_count=${n_rep}" || return 1
  if [[ -z "$state_json" || ! -r "$state_json" ]] || ! jq -e '.values' "$state_json" >/dev/null 2>&1; then
    if [[ "$n_rep" -gt 0 ]]; then
      echo "cf_account_migrate_gate: REFUSE — phase ${phase} declares a replace set and needs the pre-plan state JSON (terraform show -json) to bind each replace to its physical id"
      return 1
    fi
    state_json=""   # absent or unusable: no address counts as in state, so no create-class update passes
  fi

  # A fourth argument must be a usable read, on any plan, an all-no-op one included.
  if (($# >= 4)); then
    has_live=true; live_json="$4"
    { [[ -r "$4" ]] && jq -e 'type == "object" and length > 0' "$4" >/dev/null 2>&1; } \
      || { echo "cf_account_migrate_gate: REFUSE — the live read is missing or unusable"; return 1; }
  fi

  # IMPORT-NORMALIZE (header). One evaluation per pinned record, so the decision and its explanation
  # cannot disagree. `norm` is what a PASS admits; `exempt` is what the import refusals below subtract.
  pins_tsv="$(cf_account_migrate_record_pins "$phase")" || { echo "cf_account_migrate_gate: REFUSE — a record import has no usable pinned id"; return 1; }
  pins="$(_cfam_pins_json <<<"$pins_tsv")" || { _cfam_eval_fail; return 1; }
  verdicts="$(jq -c --argjson pins "$pins" --argjson hl "$has_live" --arg z "$CFAM_NEW_ZONE_ID" --slurpfile vst "${state_json:-/dev/null}" --slurpfile lv "${live_json:-/dev/null}" "$_CFAM_NORMALIZE_JQ"'
    ([($vst[0].values // {}) | .. | objects | select(has("address") and has("values"))
      | select($pins[.address] != null) | {(.address): .values.id}] | add // {}) as $sids
    | [.resource_changes[] | select((.mode // "managed") == "managed") | select($pins[.address] != null)
       | .address as $ad | $pins[$ad] as $pin
       | {address: $ad, action: .change.actions,
          why: (if .change.actions == ["update"] then
                  [ (if cfam_norm_shape then empty else "shape" end),
                    (if (.change.before|type) == "object" and .change.before.id == $pin then empty else "pin" end),
                    (if .change.importing == null and $sids[$ad] != $pin then "state-id" else empty end) ]
                else [] end),
          noop_id_ok: (.change.actions != ["no-op"]
            or ((.change.before|type) == "object" and .change.before.id == $pin
                and (.change.after|type) == "object" and .change.after.id == $pin)),
          live: (if $hl then cfam_live_diff(.change.after; $lv[0][$ad]; $pin; $z) else [] end)}]' "$plan_json")" || { _cfam_eval_fail; return 1; }
  norm="$(jq -c --argjson hl "$has_live" '
    if ($hl | not) or any(.[]; .live != []) then []
      else [.[] | select(.action == ["update"] and .why == []) | .address] end' <<<"$verdicts")" || { _cfam_eval_fail; return 1; }
  norm_why="$(jq -r '.[] | select(.why != []) | "cf_account_migrate_gate: import-normalize not admitted for \(.address) (\(.why | join(",")))"' <<<"$verdicts")" || { _cfam_eval_fail; return 1; }
  # Every pinned record, whatever its planned action: a drifted no-op blocks the phase too.
  if [[ "$has_live" == true ]]; then
    live_v="$(jq -r '.[] | select(.live != [])
      | if .live == ["unreadable"] then "REFUSE \(.address) live record unreadable"
        else "REFUSE \(.address) differs from the live record (\(.live | join(",")))" end' <<<"$verdicts")" || { _cfam_eval_fail; return 1; }
  fi
  # Beside a live refusal, a record whose shape and pin hold is named only by its own live line, if it
  # has one. Keyed on the printed lines, so this exists only beside a REFUSE; `norm` is empty then, and
  # nothing is admitted.
  exempt="$norm"
  if [[ -n "$live_v" ]]; then
    exempt="$(jq -c '[.[] | select(.action == ["update"] and .why == []) | .address]' <<<"$verdicts")" || { _cfam_eval_fail; return 1; }
  fi

  # Every check below appends violation lines; all are reported, then the verdict. Each check's
  # `v="$(jq` opener line is unique: the suite's mutation rows neuter a check there (`: jq`).
  v="$(jq -r --argjson spec "$spec" '
    [.resource_changes[] | select($spec[.address] != null)] | group_by(.address)[]
    | select(length != 1 or ((.[0].mode // "managed") != "managed"))
    | "REFUSE \(.[0].address) must appear exactly once as a managed resource in the plan"' "$plan_json")" || { _cfam_eval_fail; return 1; }
  violations+="${v:+$v$'\n'}"

  # A create-class record (the tunnel phase's deploy/ssh/registry CNAMEs) planned as a plain create is
  # graded by its class check, not here; any other action on it still lands here.
  v="$(jq -r --argjson norm "$exempt" --argjson spec "$spec" '.resource_changes[]
    | select(.type == "cloudflare_record" and .change.actions != ["no-op"])
    | select(($spec[.address] == "create" and .change.actions == ["create"]) | not)
    | select(.address as $a | ($norm | index($a)) == null)
    | "REFUSE \(.address) is a cloudflare_record change outside import-normalize"' "$plan_json")" || { _cfam_eval_fail; return 1; }
  violations+="${v:+$v$'\n'}"

  v="$(jq -r '.[] | select(.noop_id_ok | not) | "REFUSE \(.address) is a no-op on a record id other than its pin"' <<<"$verdicts")" || { _cfam_eval_fail; return 1; }
  violations+="${v:+$v$'\n'}"

  v="$(jq -r --argjson spec "$spec" '.resource_changes[] | select((.mode // "managed") == "managed")
    | select((.change.actions | index("forget")) or
             ((.change.actions | index("delete")) and ($spec[.address] != "replace")))
    | "REFUSE destroys or forgets \(.address) (actions \(.change.actions | tostring))"' "$plan_json")" || { _cfam_eval_fail; return 1; }
  violations+="${v:+$v$'\n'}"

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
        ($cls == "create"  and .change.importing == null and (.change.actions != ["create"] and .change.actions != ["no-op"] and .change.actions != ["update"])) or
        ($cls == "create"  and .change.importing != null) or
        ($cls == "import"  and .change.importing == null and .change.actions != ["no-op"] and (.address as $a | ($norm | index($a)) == null)) or
        ($cls == "mutable" and (.change.actions as $x | any([["update"],["no-op"],["create"]][]; . == $x) | not)) or
        ($cls == "replace" and .change.actions != ["delete","create"]))
    | "REFUSE \(.address) (class \($cls)) planned with actions \(.change.actions | tostring)\(if .change.importing then " as an import" else "" end)"' --argjson norm "$exempt" "$plan_json")" || { _cfam_eval_fail; return 1; }
  # An import of a create-class address is reported by the literal check below, which names it.
  # grep -v exits 1 when every line was filtered (fine) and 2 on an error, which is a refusal:
  # a check that cannot be evaluated is a refusal, never "no violation lines".
  v="$(grep -v ' (class create) .* as an import$' <<<"$v")"; local gv_rc=$?
  (( gv_rc <= 1 )) || { _cfam_eval_fail; return 1; }
  violations+="${v:+$v$'\n'}"

  # A create-class ["update"] is a fix-forward re-dispatch only: the address must already be in the
  # pre-plan state and, for a Cloudflare object, its `before` must carry a NEW id and no other. On a
  # first apply every create-class cloudflare_* address is absent from state (forgotten or never
  # there), so for those this cannot widen a first apply. doppler_secret.cf_zone_id_prd is normally
  # absent on a first apply; if anything outside the gated paths wrote it, the expected-values check
  # below grades the update (the NEW zone id and its fixed project, config and name). The new-id
  # check below still grades every Cloudflare `after`. Each update this arm admits is printed as an
  # in-state-update line on a PASS (spec addresses only, so the address is a fixed literal).
  local st_src="${state_json:-/dev/null}"
  v="$(jq -r --argjson spec "$spec" --arg unz "$CFAM_NEW_ZONE_ID" --arg una "$CFAM_NEW_ACCOUNT_ID" --slurpfile pst "$st_src" '
    ([($pst[0].values // {}) | .. | objects | select(has("address") and has("values")) | .address]) as $inst
    | .resource_changes[] | select((.mode // "managed") == "managed")
    | select($spec[.address] == "create") | select(.change.actions == ["update"])
    | .address as $ad | (.change.before.zone_id // null) as $bz | (.change.before.account_id // null) as $ba
    | if ($inst | index($ad)) == null
        or ((.type | startswith("cloudflare_")) and (
              ($bz == null and $ba == null) or ($bz != null and $bz != $unz) or ($ba != null and $ba != $una)))
      then "REFUSE \($ad) (class create) planned as an update, which is allowed only for an address already in the pre-plan state on a NEW id (in state: \(($inst | index($ad)) != null), before zone_id \($bz | tostring), account_id \($ba | tostring))"
      else "cf_account_migrate_gate: in-state-update \($ad)" end' "$plan_json")" || { _cfam_eval_fail; return 1; }
  # grep exits 1 when it selects nothing (fine) and 2 on an error (a refusal, as above).
  admitted="$(grep '^cf_account_migrate_gate: in-state-update ' <<<"$v")"; gv_rc=$?
  (( gv_rc <= 1 )) || { _cfam_eval_fail; return 1; }
  v="$(grep -v '^cf_account_migrate_gate: in-state-update ' <<<"$v")"; gv_rc=$?
  (( gv_rc <= 1 )) || { _cfam_eval_fail; return 1; }
  violations+="${v:+$v$'\n'}"

  # EXPECTED VALUES (header): each table member in this phase's allow-set, on any planned action with
  # a non-null `after`, carries every table attribute exactly. The old-id check below cannot see a
  # third id, and the new-id check grades cloudflare_* types only. Names attributes, never values.
  v="$(jq -r --argjson spec "$spec" --argjson want "$want" '
    .resource_changes[] | select((.mode // "managed") == "managed")
    | select($want[.address] != null and $spec[.address] != null)
    | select(.change.after != null) | (.change.after_unknown // {}) as $u | .change.after as $a
    | [$want[.address] | to_entries[]
        | if (($u | type) == "object" and $u[.key] == true) then "\(.key) known only after apply"
          elif (($a | type) != "object" or $a[.key] != .value) then "\(.key) differs"
          else empty end] as $bad
    | select($bad | length > 0)
    | "REFUSE \(.address) must plan its expected value (\($bad | join(", ")); actions \(.change.actions | tostring))"' "$plan_json")" || { _cfam_eval_fail; return 1; }
  violations+="${v:+$v$'\n'}"

  v="$(jq -r '.resource_changes[] | select(.change.importing != null) | select(.change.actions != ["no-op"])
    | select((.address as $a | ($norm | index($a))) == null)
    | "REFUSE \(.address) is not a pure no-op import (actions \(.change.actions | tostring)): a mis-pinned import id writes to the zone under cover of an import"' --argjson norm "$exempt" "$plan_json")" || { _cfam_eval_fail; return 1; }
  violations+="${v:+$v$'\n'}"
  violations+="${live_v:+$live_v$'\n'}"

  v="$(jq -r --argjson spec "$spec" --argjson lit "$literals" '
    .resource_changes[] | select(.change.importing != null)
    | select($spec[.address] != "import" or $lit[.address] == null or .change.importing.id != $lit[.address])
    | "REFUSE import of \(.address) differs from the committed literal (planned \(.change.importing.id // "null"), committed \($lit[.address] // "none"))"' "$plan_json")" || { _cfam_eval_fail; return 1; }
  violations+="${v:+$v$'\n'}"

  # The new-id check. Every planned non-R2 cloudflare_* object must POSITIVELY carry a new id:
  # an id known only after apply (after_unknown), an id present with any other value (old, a
  # third id, false), or no id at all (absent or null on both) is refused. An absent id is never
  # read as the new one. R2 is the whole cloudflare_r2_* family, the same predicate the forget
  # script and the completion predicate use: it stays on the legacy account.
  # ZONE-SCOPED APPS (header): $za is true for exactly the three Access apps, in the tunnel phase, on
  # the NEW zone. Only then is an unknown or empty account_id read as absent.
  local zoned
  zoned="$(_cfam_access_apps | jq -c 'keys')" || { _cfam_eval_fail; return 1; }
  v="$(jq -r --arg nz "$CFAM_NEW_ZONE_ID" --arg na "$CFAM_NEW_ACCOUNT_ID" --arg phase "$phase" --argjson zoned "$zoned" '
    .resource_changes[] | select((.mode // "managed") == "managed")
    | select(.type | startswith("cloudflare_")) | select(.type | startswith("cloudflare_r2_") | not)
    | select(.change.after != null)
    | (.change.after.zone_id) as $z
    | ($phase == "tunnel" and $z == $nz and (.address as $x | $zoned | index($x) != null)) as $za
    | (.change.after.account_id | if $za and . == "" then null else . end) as $a
    | ((.change.after_unknown // {}) | if $za then del(.account_id) else . end) as $u
    | select(
        ($u.zone_id == true) or ($u.account_id == true)
        or ($z != null and $z != $nz) or ($a != null and $a != $na)
        or ($z != $nz and $a != $na))
    | "REFUSE \(.address) carries an id that is not the new zone/account (zone_id \($z | tostring), account_id \($a | tostring)\(if ($u.zone_id == true) or ($u.account_id == true) then ", known only after apply" else "" end))"' "$plan_json")" || { _cfam_eval_fail; return 1; }
  violations+="${v:+$v$'\n'}"

  # A non-Cloudflare address in the allow-set (doppler_secret.cf_zone_id_prd, the github secrets,
  # the dns-edit secret) republishes an id or token; it must not republish an OLD id. Any string
  # leaf of its planned `after` that CONTAINS the OLD zone or account id (alone, or inside a URL or
  # JSON blob) is refused. Scoped to the
  # allow-set: an out-of-set change is already refused above, and an R2 secret outside it may
  # legitimately carry the legacy account.
  v="$(jq -r --argjson spec "$spec" --arg oz "$CFAM_OLD_ZONE_ID" --arg oa "$CFAM_OLD_ACCOUNT_ID" '
    .resource_changes[] | select((.mode // "managed") == "managed")
    | select($spec[.address] != null) | select(.type | startswith("cloudflare_") | not)
    | select(.change.after != null)
    | select([.change.after | .. | strings | ascii_downcase | select(contains($oz) or contains($oa))] | length > 0)
    | "REFUSE \(.address) republishes an OLD zone/account id in its planned value"' "$plan_json")" || { _cfam_eval_fail; return 1; }
  violations+="${v:+$v$'\n'}"

  v="$(jq -r --argjson spec "$spec" '[.resource_changes[].address] as $have
    | $spec | keys_unsorted[] | select(. as $a | $have | index($a) | not)
    | "REFUSE \(.) is missing from the plan (every allow-set address must be planned; a dropped -target or a disabled import reads as success otherwise)"' "$plan_json")" || { _cfam_eval_fail; return 1; }
  violations+="${v:+$v$'\n'}"

  if [[ -n "$state_json" ]]; then
    v="$(jq -r --argjson spec "$spec" '.resource_changes[] | select($spec[.address] == "replace")
      | select(.action_reason != "replace_by_request")
      | "REFUSE \(.address) is a declared -replace but action_reason is \(.action_reason // "null"), not replace_by_request (the -replace flag was dropped)"' "$plan_json")" || { _cfam_eval_fail; return 1; }
    violations+="${v:+$v$'\n'}"
    v="$(jq -r --argjson spec "$spec" --slurpfile st "$state_json" '
      ([$st[0].values | .. | objects | select(has("address") and has("values")) | {(.address): .values.id}] | add // {}) as $ids
      | .resource_changes[] | select($spec[.address] == "replace")
      | select(.change.before.id == null or .change.before.id != $ids[.address])
      | if (.type | startswith("random_")) then "REFUSE \(.address) replace targets a physical id that differs from the pre-plan state (ids not printed: a random_* id is its secret)"
        else "REFUSE \(.address) replace targets physical id \(.change.before.id // "null") but pre-plan state holds \($ids[.address] // "null")" end' "$plan_json")" || { _cfam_eval_fail; return 1; }
    violations+="${v:+$v$'\n'}"
  fi

  if [[ "$phase" == tunnel ]]; then
    v="$(_cfam_access_violations "$plan_json")" || { _cfam_eval_fail; return 1; }
    violations+="${v:+$v$'\n'}"
    v="$(_cfam_access_source_violations)" || { _cfam_eval_fail; return 1; }
    violations+="${v:+$v$'\n'}"
  fi

  creates="$(jq -r '[.resource_changes[] | select(.change.actions == ["create"])] | length' "$plan_json")" || { _cfam_eval_fail; return 1; }
  imports="$(jq -r '[.resource_changes[] | select(.change.importing != null)] | length' "$plan_json")" || { _cfam_eval_fail; return 1; }
  destroys="$(jq -r '[.resource_changes[] | select(.change.actions | index("delete"))] | length' "$plan_json")" || { _cfam_eval_fail; return 1; }
  plan_gate_assert_numeric "cf_account_migrate_gate" "creates=${creates}" "imports=${imports}" "destroys=${destroys}" || return 1

  if [[ -n "$violations" ]]; then
    printf '%s' "$violations"
    [[ -z "$norm_why" ]] || printf '%s\n' "$norm_why"
    echo "cf_account_migrate_gate: phase=${phase} verdict=REFUSE creates=${creates} imports=${imports} destroys=${destroys}"
    return 1
  fi
  [[ -z "$admitted" ]] || printf '%s\n' "$admitted"
  jq -r '.[] | "cf_account_migrate_gate: import-normalize \(.)"' <<<"$norm" || { _cfam_eval_fail; return 1; }
  echo "cf_account_migrate_gate: phase=${phase} verdict=PASS creates=${creates} imports=${imports} destroys=${destroys}"
  return 0
}

# cf_account_migrate_phase_tokens <phase> — the provider token variables (Terraform names, no
# TF_VAR_ prefix) that <phase>'s plan and apply authenticate with, one per line. Next to the phase
# spec so a phase and its tokens change in one diff. The migrate job's id preflight requires each
# to answer HTTP 200 on one GET against the NEW zone or account before anything is written
# (CTO D8). Unknown phase: return 1.
cf_account_migrate_phase_tokens() {
  case "${1-}" in
    redirects-dns) printf '%s\n' cf_api_token cf_api_token_rulesets cf_api_token_pages ;;
    zone-rest) printf '%s\n' cf_api_token_zone_settings cf_api_token_bot_management ;;
    tunnel) printf '%s\n' cf_api_token ;;
    *) return 1 ;;
  esac
}
