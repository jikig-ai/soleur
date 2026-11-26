#!/usr/bin/env bash
# cf-token-scope — verify a Cloudflare API token's retained scope after a widen,
# and confirm a newly-added scope is live (rulesets profile: --target-entrypoint;
# default-token profile: --expect-lb-scopes).
#
# Deterministic probe, read-only except the two migration profiles
# (redirects-dns, zone-rest), which send PUT/POST/PATCH with one of two fixed
# bodies that can never validate (see MIGRATION PROFILES). The widen itself is
# driven by Playwright MCP per the skill (SKILL.md) — this script never touches
# the browser, never writes Doppler and never applies infra.
#
# It runs the selected profile's retained-scope probe set — the ADR-130 set
# against CF_API_TOKEN_RULESETS by default, the CF_API_TOKEN ledger + LB
# readiness set with `--profile default-token` —
# and is fail-closed in three layers (per learning
# 2026-07-23-live-api-fail-closed-guard-counts-degraded-200-as-empty-and-control-probe-must-cover-every-scheme):
#   1. status      — 403 / 000 / 5xx / empty / no-newline / non-numeric = FAIL.
#   2. body-shape  — a 200 passes ONLY when the JSON body has success==true AND
#                    .result is an array. A degraded 200 (e.g.
#                    {"success":false,...} OR {"success":true,"result":null}) is a
#                    FAIL. Never key on `.result | length` — jq reads null as 0.
#   3. per-scheme control — the RULESETS profile spans two schemes: four zone
#                    phases and one account list. The account list is itself the
#                    account-scheme control (must be an authorized 200; an account
#                    404 = FAIL). A zone 404 (ADR-130's "phase exists, empty") is
#                    trusted ONLY for http_config_settings — the one phase whose
#                    403-on-missing was empirically verified — and only under an
#                    authorized zone control (http_request_dynamic_redirect). Every
#                    other phase's 404 fails closed (a dropped scope that 404s must
#                    not pass). The default-token profile carries no trust404 row.
#
# The probe set is a CANARY for the whole-list REPLACE failure mode (a dashboard
# "save" that replaces rather than appends drops every scope at once → every probe
# catches it). It is NOT exhaustive per-permission coverage: Zone WAF
# (firewall_custom) is now probed, but Transform Rules (response_headers_transform)
# and account Filter Lists are not, so a surgical single-permission drop of those
# can pass. The probe issues GET, so it attests READ reachability, not :Edit
# retention. See SKILL.md § Sharp Edges.
#
# MIGRATION PROFILES (#12931, CTO ruling L49): `redirects-dns` and `zone-rest`
# probe the NEW-account tokens a Cloudflare account migration phase must WRITE
# with, once per phase before that phase's rehearsal. A GET cannot prove :Edit
# (the 2026-07-24 config-rules scope-gap post-mortem), so these two profiles are
# the ONE place this script sends a write verb, and only under four rules:
#   1. the body is one of two fixed readonly literals, chosen per row by its
#      body-kind through one closed case in mig_req, and never anything else:
#      INVALID_BODY (not JSON, so no endpoint can validate it) for every row
#      except the zone settings PATCH, and SETTINGS_PROBE_BODY for that row only,
#      because that endpoint parses JSON before it checks authorization (a
#      non-JSON body gets 400 for every token, so the 403 control below cannot
#      be established with it). SETTINGS_PROBE_BODY names one setting id that
#      does not exist (prefix cf_token_scope_probe_). Guards, all exit 2 before
#      the write they protect: a static table guard (startup, before any secret
#      read: the body is a JSON object whose only key is a non-empty items array
#      of probe-prefixed {id,value} items; every body-kind is invalid or
#      settings-json; settings-json only on PATCH $API/zones/$ZONE/settings),
#      mig_req's URL refusal at the write boundary, and a collision guard that
#      refuses when the zone's own settings list (an authorized GET control)
#      names a probe id. Never an empty-rules ruleset body (that PUT validates
#      and replaces a live entrypoint with nothing), never a body naming a real
#      setting;
#   2. any 2xx answer is a FATAL abort (exit 4) followed by an immediate GET
#      read-back of that endpoint, so a mutation that should be impossible is
#      surfaced with its evidence rather than discovered later;
#   3. every write row first sends the same body with a KNOWN-DENIED token (a
#      sibling token that lacks the scope) and must see 403 before the granted
#      token's 400 counts as "authorized" — otherwise the endpoint may be
#      validating the body before authorization and a 400 proves nothing;
#   4. method is PUT/POST/PATCH only, never DELETE.
# Each profile also runs known-present GET controls (success:true + parsed
# .result), and redirects-dns lists every ruleset in the new zone and account so
# a hand-made entrypoint is recorded by id (ADR-136 whole-list audit).

set -euo pipefail

# (#7797) Refuse to run under shell tracing. UNCONDITIONAL — deliberately NOT
# gated on a non-emptiness test of the credential variable, because
# CF_API_TOKEN_RULESETS is acquired by `doppler secrets get` BELOW this point, so a
# conditional arm would test an empty variable at guard time, open, and then trace
# the acquisition itself.
#
# STREAM CONTRACT: this script's stdout is a DATA channel — SKILL.md's probe-set
# contract documents `PASS: …` verdict lines a consumer reads. So the refusal is
# emitted as a `FAIL:` verdict in this module's own vocabulary: it cannot be
# mistaken for a PASS row, which a bare `[FATAL] …` line could be if the consumer
# only greps for verdicts. Stdout, not stderr, because agent runtimes surface
# stdout and swallow stderr (constitution.md > Code Style).
case "$-" in
  *x*)
    printf 'FAIL: refusing to run under xtrace — this script handles a live credential and -x would print it (see #7797). No probe was issued.\n'
    exit 78
    ;;
esac

# (#7873) `--disable` closes ~/.curlrc and `--noproxy '*'` closes the proxy vars,
# but neither touches the env that subverts TLS ITSELF. SSLKEYLOGFILE writes the
# session keys and the CA vars substitute the trust store, so a CURL_CA_BUNDLE
# MITM of the Cloudflare token works with every other guard fully intact.
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME \
      HOSTALIASES LOCALDOMAIN RES_OPTIONS

DOPPLER_PROJECT="soleur"
DOPPLER_CONFIG="prd_terraform"
ZONE_SECRET="CF_ZONE_ID"
ACCT_SECRET="CF_ACCOUNT_ID"
API="https://api.cloudflare.com/client/v4"

# Profile table (the ONLY token binding; plan 2026-10-28, rulings R1/R2/D1).
# rulesets = the ADR-130 retained-scope set against CF_API_TOKEN_RULESETS — the
# default, exactly today's behavior. default-token = the production default
# CF_API_TOKEN (the `cloudflare` provider alias) probed over its ledgered
# abilities plus two Load-Balancer readiness rows, so a scope widen of THAT
# token gets a deterministic retained-scope re-check too (the ruling's binding
# precondition). Profiles only — a raw --token-var knob would run one profile's
# URLs against another token's capabilities and is refused by design (SKILL.md).
PROFILES=(rulesets default-token redirects-dns zone-rest)
PROFILE="rulesets"

profile_token_secret() {
  case "$1" in
    rulesets)      printf '%s' "CF_API_TOKEN_RULESETS" ;;
    default-token) printf '%s' "CF_API_TOKEN" ;;
    *)             printf '' ;;
  esac
}

# Migration profiles bind several tokens each (one per Doppler key, CTO F11), so
# they resolve through their row tables rather than profile_token_secret.
is_migration_profile() { [[ "$1" == "redirects-dns" || "$1" == "zone-rest" ]]; }

# Account / zone ids for the migration profiles (#12931). They are NOT read from
# Doppler: during Phase 0 CF_ZONE_ID / CF_ACCOUNT_ID still hold the OLD ids, and
# the whole point is to probe the NEW ones before the swap. Ids are not secrets.
NEW_ACCT_ID="66d4f93f7397f196544e9fe84c3557c2"
NEW_ZONE_ID="951ce525552201ec6c696b24251abed7"
OLD_ACCT_ID="4d5ba6f096b2686fbdd404167dd4e125"
OLD_ZONE_ID="5af02a2f394e9ba6e0ea23c381a26b67"

# The two write-probe bodies (CTO L49 rule 1). INVALID_BODY is not JSON, so no
# endpoint can parse it, let alone validate it; a runtime tripwire below refuses
# to run if it ever parses. SETTINGS_PROBE_BODY is the zone settings PATCH row's
# body only: JSON (that endpoint parses before it authorizes) naming one setting
# id that does not exist; the static table guard below pins its shape.
readonly INVALID_BODY='<cf-token-scope:invalid-write-probe-body:not-json:never-valid>'
readonly SETTINGS_PROBE_BODY='{"items":[{"id":"cf_token_scope_probe_nonexistent_setting","value":"cf_token_scope_probe_never_valid"}]}'

# Write-probe rows: label|method|url-template|grant-token-key|deny-token-key|body-kind.
# The deny key names a sibling token that must NOT hold the row's scope (its 403
# is the control that makes the grant token's 400 mean "authorized"). body-kind
# is `invalid` (INVALID_BODY) or `settings-json` (SETTINGS_PROBE_BODY, the zone
# settings PATCH row only). Read-back on a 2xx is a GET of the same URL with the
# grant token.
MIG_WRITE_REDIRECTS_DNS=(
  "zones/<zone>/rulesets/phases/http_request_dynamic_redirect/entrypoint|PUT|$API/zones/\$ZONE/rulesets/phases/http_request_dynamic_redirect/entrypoint|CF_API_TOKEN_RULESETS|CF_API_TOKEN_PAGES|invalid"
  "zones/<zone>/rulesets/phases/http_response_headers_transform/entrypoint|PUT|$API/zones/\$ZONE/rulesets/phases/http_response_headers_transform/entrypoint|CF_API_TOKEN_RULESETS|CF_API_TOKEN_PAGES|invalid"
  "zones/<zone>/rulesets/phases/http_config_settings/entrypoint|PUT|$API/zones/\$ZONE/rulesets/phases/http_config_settings/entrypoint|CF_API_TOKEN_RULESETS|CF_API_TOKEN_PAGES|invalid"
  "zones/<zone>/rulesets/phases/http_request_cache_settings/entrypoint|PUT|$API/zones/\$ZONE/rulesets/phases/http_request_cache_settings/entrypoint|CF_API_TOKEN_RULESETS|CF_API_TOKEN_PAGES|invalid"
  "zones/<zone>/rulesets/phases/http_request_firewall_custom/entrypoint|PUT|$API/zones/\$ZONE/rulesets/phases/http_request_firewall_custom/entrypoint|CF_API_TOKEN_RULESETS|CF_API_TOKEN_PAGES|invalid"
  "accounts/<acct>/rulesets/phases/http_request_redirect/entrypoint|PUT|$API/accounts/\$ACCT/rulesets/phases/http_request_redirect/entrypoint|CF_API_TOKEN_RULESETS|CF_API_TOKEN_PAGES|invalid"
  "accounts/<acct>/rules/lists|POST|$API/accounts/\$ACCT/rules/lists|CF_API_TOKEN_RULESETS|CF_API_TOKEN_PAGES|invalid"
  "zones/<zone>/dns_records|POST|$API/zones/\$ZONE/dns_records|CF_API_TOKEN|CF_API_TOKEN_PAGES|invalid"
  "accounts/<acct>/pages/projects|POST|$API/accounts/\$ACCT/pages/projects|CF_API_TOKEN_PAGES|CF_API_TOKEN_RULESETS|invalid"
)
MIG_WRITE_ZONE_REST=(
  "zones/<zone>/settings|PATCH|$API/zones/\$ZONE/settings|CF_API_TOKEN_ZONE_SETTINGS|CF_API_TOKEN_BOT_MANAGEMENT|settings-json"
  "zones/<zone>/bot_management|PUT|$API/zones/\$ZONE/bot_management|CF_API_TOKEN_BOT_MANAGEMENT|CF_API_TOKEN_ZONE_SETTINGS|invalid"
)
# Known-present GET controls: label|url-template|token-key|want-type. Each must be
# an authorized 200 with success:true and a parsed .result of want-type, so a
# degraded 200 or a 404 is never read as "empty".
MIG_CTRL_REDIRECTS_DNS=(
  "zones/<zone>/rulesets|$API/zones/\$ZONE/rulesets|CF_API_TOKEN_RULESETS|array"
  "accounts/<acct>/rulesets|$API/accounts/\$ACCT/rulesets|CF_API_TOKEN_RULESETS|array"
)
MIG_CTRL_ZONE_REST=(
  "zones/<zone>/settings|$API/zones/\$ZONE/settings|CF_API_TOKEN_ZONE_SETTINGS|array"
)
# Entrypoints the redirects-dns whole-list audit reports present/absent (ADR-136).
MIG_AUDIT_ZONE_PHASES=(http_request_dynamic_redirect http_response_headers_transform http_config_settings http_request_cache_settings http_request_firewall_custom)
MIG_AUDIT_ACCT_PHASES=(http_request_redirect)

# default-token probe rows: class|label|url-template|want_type|scheme.
# The $ZONE/$ACCT placeholders are printed VERBATIM by --dry-run and substituted
# after secret acquisition on the run path — print/run parity from ONE table
# (Guard 1 assembly). class=target rows are the two LB readiness probes (one
# per granted permission surface of the ruling; GETs attest the read half).
# Every row is trust404=0: the 403-on-missing verification stays exclusive to
# http_config_settings (ADR-130 #6746); LB endpoints fail closed on 404.
DT_ROWS=(
  "retained|accounts/<acct>/cfd_tunnel|$API/accounts/\$ACCT/cfd_tunnel?per_page=1|array|account"
  "retained|accounts/<acct>/access/apps|$API/accounts/\$ACCT/access/apps?per_page=1|array|account"
  "retained|zones/<zone>/dns_records|$API/zones/\$ZONE/dns_records?per_page=1|array|zone"
  "retained|accounts/<acct>/alerting/v3/policies|$API/accounts/\$ACCT/alerting/v3/policies|array|account"
  "target|accounts/<acct>/lb/pools|$API/accounts/\$ACCT/load_balancers/pools?per_page=1|array|account"
  "target|zones/<zone>/load_balancers|$API/zones/\$ZONE/load_balancers?per_page=1|array|zone"
)

LB_EXPECT=0
LB_OK=0
# LB_NOTED is a LATCH (set to 1, never incremented) — its siblings are counters.
LB_NOTED=0
LB_MISSING=0
LB_TOTAL=0

# The ADR-130 retained-scope zone phases. http_request_dynamic_redirect is the
# known-granted zone control (ADR-130 § Consequences: the 200 control probe).
# http_request_firewall_custom (Zone WAF:Edit) is added to the retained set
# because it is a hijack-class scope on the same token (ADR-130 axis 1).
ZONE_CONTROL="http_request_dynamic_redirect"
ZONE_PHASES=(http_config_settings http_request_dynamic_redirect http_request_cache_settings http_request_firewall_custom)

# 403-vs-404-on-missing-scope semantics are EMPIRICALLY VERIFIED (ADR-130 probe
# #6746) for ONLY http_config_settings: a missing scope there returns 403, never
# 404, so a 404 is unambiguously "phase exists, empty" and passes. For every other
# phase that fact is UNVERIFIED, so a 404 fails closed — a dropped scope that
# returned 404 instead of 403 must never read as green (user-impact P1, #6892).
trust404_for() { [[ "$1" == "http_config_settings" ]] && echo 1 || echo 0; }

usage() {
  cat <<'EOF'
Usage:
  cf-token-scope.sh [--profile <rulesets|default-token>] [--target-entrypoint <phase>] [--expect-lb-scopes] [--dry-run]
  cf-token-scope.sh --profile <redirects-dns|zone-rest> [--staged] [--account-id <id>] [--zone-id <id>] [--dry-run]

Runs a retained-scope probe set for a NAMED PROFILE (read-only, except the
migration profiles' write probes, which carry only fixed never-valid bodies).
Profiles only —
no raw token-var knob. The widen itself is driven via Playwright MCP — see SKILL.md.

  profiles:
    rulesets       (default) ADR-130 retained-scope set against CF_API_TOKEN_RULESETS
    default-token  CF_API_TOKEN ledger abilities (Tunnel, Access, DNS, Notifications)
                   + two Load-Balancer readiness rows (the #11181 widen precondition
                   and post-check)
    redirects-dns  #12931 account migration, phase redirects-dns: never-valid WRITE
                   probes (zone rulesets, account rulesets + lists, DNS, Pages) on the
                   NEW account/zone, each behind a known-denied 403 control, plus the
                   whole-list entrypoint audit
    zone-rest      #12931 account migration, phase zone-rest: never-valid WRITE
                   probes for zone settings (a JSON body naming a nonexistent
                   setting id) and bot management

Flags:
  --target-entrypoint <phase>  Also probe <phase> and assert the target scope is
                               present (rulesets profile; use after a widen; confirm
                               the 403->present transition against your baseline).
  --expect-lb-scopes           Assert mode (default-token profile): LB rows must be
                               authorized, else exit 3. Without it a baseline run
                               reports 403 LB rows as not-yet-widened, exit-neutral.
  --staged                     Migration profiles: read each token from its
                               <KEY>_NEXT staging key (Phase 0, before the swap).
  --account-id / --zone-id     Migration profiles: override the NEW account / zone
                               id (32 hex). The OLD ids are refused.
  --dry-run                    Print the selected profile's probe commands (token
                               unexpanded) and run nothing.
  -h, --help                   Show this help.

Exit codes:
  0  every retained scope authorized (and, per profile: the rulesets target if
     given; the default-token LB rows authorized, or 403-noted in baseline mode)
  2  usage error (including profile/flag mismatch and a malformed phase name),
     missing prerequisite binary, absent Doppler secret, or a refused internal
     table-integrity tripwire (source drift; stderr-only, names the corruption)
  3  probe failed — a scope was dropped, degraded, or denied (assert mode: an LB
     row still 403 or anomalous; migration profiles: a write denied, or a
     control not established, so a 400 could not be trusted)
  4  FATAL (migration profiles): a write probe answered 2xx to a never-valid
     body; the endpoint was read back and the run aborted. Treat as a possible
     mutation.
  78 refused to run under shell tracing — a refusal, not a probe verdict (#7797)
EOF
}

TARGET=""
DRY_RUN=0
STAGED=0
MIG_ACCT_ARG=""
MIG_ZONE_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-entrypoint)
      if [[ -z "${2:-}" ]]; then
        echo "cf-token-scope: --target-entrypoint requires a phase name" >&2
        exit 2
      fi
      TARGET="$2"; shift 2 ;;
    --profile)
      if [[ -z "${2:-}" ]]; then
        echo "cf-token-scope: --profile requires a profile name" >&2
        exit 2
      fi
      known=0
      for p in "${PROFILES[@]}"; do
        [[ "$p" == "$2" ]] && known=1
      done
      if [[ "$known" == "0" ]]; then
        echo "cf-token-scope: unknown profile: $2" >&2
        usage >&2
        exit 2
      fi
      PROFILE="$2"; shift 2 ;;
    --expect-lb-scopes) LB_EXPECT=1; shift ;;
    --staged) STAGED=1; shift ;;
    --account-id|--zone-id)
      if [[ -z "${2:-}" ]]; then
        echo "cf-token-scope: $1 requires a 32-hex id" >&2
        exit 2
      fi
      if [[ "$1" == "--account-id" ]]; then MIG_ACCT_ARG="$2"; else MIG_ZONE_ARG="$2"; fi
      shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "cf-token-scope: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# Cross-validation BEFORE any secret read or recipe print (Guard 1 assembly:
# usage errors never print recipes for a mispaired run and never cost a Doppler
# access; plan addendum 6 mirrors the existing arm shapes).
if [[ "$PROFILE" == "rulesets" && "$LB_EXPECT" == "1" ]]; then
  echo "cf-token-scope: --expect-lb-scopes is a default-token profile flag" >&2
  exit 2
fi
if [[ "$PROFILE" == "default-token" && -n "$TARGET" ]]; then
  echo "cf-token-scope: --target-entrypoint is a rulesets profile flag" >&2
  exit 2
fi
# charset gate (panel seat): TARGET interpolates into the probe URL path; a
# '?'/.. value would silently retarget the read-only probe to another endpoint
# (wrong attestation). Phase names are lowercase+underscore by Cloudflare contract.
if [[ -n "$TARGET" && ! "$TARGET" =~ ^[a-z_]+$ ]]; then
  echo "cf-token-scope: --target-entrypoint must be a ruleset phase name ([a-z_]+)" >&2
  exit 2
fi
if is_migration_profile "$PROFILE"; then
  if [[ -n "$TARGET" || "$LB_EXPECT" == "1" ]]; then
    echo "cf-token-scope: --target-entrypoint / --expect-lb-scopes do not apply to migration profile '$PROFILE'" >&2
    exit 2
  fi
  MIG_ACCT="${MIG_ACCT_ARG:-$NEW_ACCT_ID}"
  MIG_ZONE="${MIG_ZONE_ARG:-$NEW_ZONE_ID}"
  # The ids interpolate into probe URLs: hex-only, the same retarget concern as the
  # --target-entrypoint charset gate. The OLD ids are refused outright: probing the
  # old account would attest the wrong tokens' scope and read as a green phase.
  for mig_id in "$MIG_ACCT" "$MIG_ZONE"; do
    if [[ ! "$mig_id" =~ ^[0-9a-f]{32}$ ]]; then
      echo "cf-token-scope: --account-id / --zone-id must be 32 lowercase hex characters" >&2
      exit 2
    fi
  done
  if [[ "$MIG_ACCT" == "$OLD_ACCT_ID" || "$MIG_ZONE" == "$OLD_ZONE_ID" ]]; then
    echo "cf-token-scope: refusing the OLD account/zone id — migration profiles probe the NEW account (#12931)" >&2
    exit 2
  fi
elif [[ "$STAGED" == "1" || -n "$MIG_ACCT_ARG" || -n "$MIG_ZONE_ARG" ]]; then
  echo "cf-token-scope: --staged / --account-id / --zone-id are migration-profile flags (redirects-dns, zone-rest)" >&2
  exit 2
fi

# Runtime tripwire (L49): the write-probe body must never parse as JSON. Checked
# before anything else runs so a source edit that made it valid can never send it.
if command -v jq >/dev/null 2>&1 && printf '%s' "$INVALID_BODY" | jq -e . >/dev/null 2>&1; then
  echo "cf-token-scope: INVALID_BODY parses as JSON (table corruption — a write probe must never carry a body that can validate)" >&2
  exit 2
fi

# Row-table accessors for the migration profiles (print one row per line).
mig_write_rows() {
  case "$1" in
    redirects-dns) printf '%s\n' "${MIG_WRITE_REDIRECTS_DNS[@]}" ;;
    zone-rest)     printf '%s\n' "${MIG_WRITE_ZONE_REST[@]}" ;;
  esac
}
mig_ctrl_rows() {
  case "$1" in
    redirects-dns) printf '%s\n' "${MIG_CTRL_REDIRECTS_DNS[@]}" ;;
    zone-rest)     printf '%s\n' "${MIG_CTRL_ZONE_REST[@]}" ;;
  esac
}
mig_key() { if [[ "$STAGED" == "1" ]]; then printf '%s_NEXT' "$1"; else printf '%s' "$1"; fi; }
# Quoted replacements, same '&' reason as the default-token run path.
mig_url() { local u="${1//\$ZONE/"$MIG_ZONE"}"; printf '%s' "${u//\$ACCT/"$MIG_ACCT"}"; }

# Static write-table guard (CTO L49 rule 1), before any secret read and before the
# dry-run prints. It loops over both tables directly (a `< <(mig_write_rows …)`
# that failed would not trip set -e, and the loop would check zero rows) and runs
# for every profile, as the INVALID_BODY tripwire does: a corrupt migration table
# is source drift. mig_req re-checks the URL at the write boundary; this guard
# exists for ORDER, refusing before the first write of ANY row.
for mig_row in "${MIG_WRITE_REDIRECTS_DNS[@]}" "${MIG_WRITE_ZONE_REST[@]}"; do  # static-guard-rows
  IFS='|' read -r g_label g_method g_url _g_grant _g_deny g_kind <<<"$mig_row"
  case "$g_kind" in
    invalid) ;;
    settings-json)
      if [[ "$g_method" != "PATCH" || "$g_url" != "$API/zones/\$ZONE/settings" ]]; then
        echo "cf-token-scope: write row '$g_label' uses body-kind settings-json off the zone settings PATCH (table corruption — SETTINGS_PROBE_BODY is sent to PATCH \$API/zones/\$ZONE/settings only)" >&2
        exit 2
      fi ;;
    *)
      echo "cf-token-scope: write row '$g_label' has body-kind '$g_kind', not invalid or settings-json (table corruption)" >&2
      exit 2 ;;
  esac
done
unset mig_row g_label g_method g_url _g_grant _g_deny g_kind
# One jq expression: parses; an object whose only key is a non-empty items array;
# every item exactly {id,value} with a probe-prefixed string id. Gated on jq as the
# INVALID_BODY tripwire is: without jq only --dry-run can run, and it sends nothing.
if command -v jq >/dev/null 2>&1 \
   && ! printf '%s' "$SETTINGS_PROBE_BODY" | jq -e \
     'type == "object" and keys == ["items"] and (.items | type == "array" and length > 0) and all(.items[]; type == "object" and keys == ["id","value"] and (.id | type == "string" and startswith("cf_token_scope_probe_")))' >/dev/null 2>&1; then
  echo "cf-token-scope: SETTINGS_PROBE_BODY is not probe-shaped (table corruption — it must be a JSON object whose only key is a non-empty items array of {id,value} items, every id starting cf_token_scope_probe_)" >&2
  exit 2
fi

if is_migration_profile "$PROFILE" && [[ "$DRY_RUN" -eq 1 ]]; then
  printf '%s\n' "# dry-run — migration profile $PROFILE on account <acct>=$MIG_ACCT zone <zone>=$MIG_ZONE (nothing executed)"
  printf '%s\n' "# write probes send ONLY the two fixed never-valid bodies; any 2xx aborts (exit 4) after a read-back"
  printf '%s\n' "INVALID_BODY='$INVALID_BODY'"
  printf '%s\n' "SETTINGS_PROBE_BODY='$SETTINGS_PROBE_BODY'"
  while IFS='|' read -r c_label c_url c_key c_want; do
    [[ -n "$c_label" ]] || continue
    printf '%s\n' "# control $c_label (want 200, success:true, .result $c_want)"
    printf '%s\n' "curl --disable --noproxy '*' -sS --max-time 15 -H @<(printf 'Authorization: Bearer %s' \"\$$(mig_key "$c_key")\") $(mig_url "$c_url")"
  done < <(mig_ctrl_rows "$PROFILE")
  while IFS='|' read -r w_label w_method w_url w_grant w_deny w_kind; do
    [[ -n "$w_label" ]] || continue
    # The static guard above already refused any other kind.
    case "$w_kind" in
      settings-json) w_name="SETTINGS_PROBE_BODY" ;;
      *)             w_name="INVALID_BODY" ;;
    esac
    printf '%s\n' "# write $w_label (body-kind $w_kind): deny control $(mig_key "$w_deny") must answer 403, then grant $(mig_key "$w_grant") must answer 400"
    printf '%s\n' "w_body=\"\$$w_name\""
    for w_key in "$w_deny" "$w_grant"; do
      printf '%s\n' "curl --disable --noproxy '*' -sS --max-time 15 -X $w_method -H 'Content-Type: application/json' --data-binary \"\$w_body\" -H @<(printf 'Authorization: Bearer %s' \"\$$(mig_key "$w_key")\") $(mig_url "$w_url")"
    done
  done < <(mig_write_rows "$PROFILE")
  exit 0
fi

if ! is_migration_profile "$PROFILE"; then
TOKEN_SECRET="$(profile_token_secret "$PROFILE")"
if [[ -z "$TOKEN_SECRET" ]]; then
  # future-drift tripwire: unreachable while PROFILES and the case arms stay in
  # sync — if they ever diverge, an empty binding must refuse, never probe bare.
  echo "cf-token-scope: profile '$PROFILE' resolves no token secret" >&2
  exit 2
fi
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '%s\n' "# dry-run — would read the token read-only and probe (nothing executed):"
  printf '%s\n' "TOK=\$(doppler secrets get $TOKEN_SECRET -p $DOPPLER_PROJECT -c $DOPPLER_CONFIG --plain)"
  printf '%s\n' "ZONE=\$(doppler secrets get $ZONE_SECRET -p $DOPPLER_PROJECT -c $DOPPLER_CONFIG --plain)"
  printf '%s\n' "ACCT=\$(doppler secrets get $ACCT_SECRET -p $DOPPLER_PROJECT -c $DOPPLER_CONFIG --plain)"
  # The token is passed from a private fd (never argv) — mirror that here so a
  # copy-pasted recipe does not leak the token to ps / /proc (security #6892).
  # The recipes also carry `--disable` literally first (it aborts ~/.curlrc
  # parsing, and later is too late) and `--noproxy '*'`, so a copy-pasted probe
  # teaches the confined form rather than the one this change removes (#7873).
  if [[ "$PROFILE" == "default-token" ]]; then
    for row in "${DT_ROWS[@]}"; do
      # shellcheck disable=SC2034  # class/want/scheme consumed on the run path of the SAME table
      IFS='|' read -r r_class r_label r_url r_want r_scheme <<<"$row"
      printf '%s\n' "curl --disable --noproxy '*' -sS --max-time 15 -H @<(printf 'Authorization: Bearer %s' \"\$TOK\") $r_url"
    done
    exit 0
  fi
  for p in "${ZONE_PHASES[@]}" ${TARGET:+"$TARGET"}; do
    printf '%s\n' "curl --disable --noproxy '*' -sS --max-time 15 -H @<(printf 'Authorization: Bearer %s' \"\$TOK\") $API/zones/\$ZONE/rulesets/phases/$p/entrypoint"
  done
  printf '%s\n' "curl --disable --noproxy '*' -sS --max-time 15 -H @<(printf 'Authorization: Bearer %s' \"\$TOK\") $API/accounts/\$ACCT/rulesets"
  exit 0
fi

# Prerequisites.
for bin in curl doppler jq; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "cf-token-scope: missing required binary: $bin" >&2
    exit 2
  }
done

get_secret() {
  local name="$1" val
  val="$(doppler secrets get "$name" -p "$DOPPLER_PROJECT" -c "$DOPPLER_CONFIG" --plain 2>/dev/null || true)"
  if [[ -z "$val" ]]; then
    echo "cf-token-scope: $name is empty or absent in Doppler $DOPPLER_PROJECT/$DOPPLER_CONFIG" >&2
    exit 2
  fi
  printf '%s' "$val"
}

if ! is_migration_profile "$PROFILE"; then
TOK="$(get_secret "$TOKEN_SECRET")"
ZONE="$(get_secret "$ZONE_SECRET")"
ACCT="$(get_secret "$ACCT_SECRET")"
# shellcheck disable=SC2317,SC2329  # invoked indirectly via the EXIT trap
cleanup() { unset TOK ZONE ACCT; }
trap cleanup EXIT
fi

# Body-shape layer: a 200 is authorized ONLY with success==true AND .result of the
# type the endpoint's scheme returns — a zone .../entrypoint returns a single
# ruleset OBJECT; the account /rulesets list returns an ARRAY. A degraded 200
# ({"success":false,...} or {"success":true,"result":null}) fails either way (null
# is neither object nor array). $4 is the expected type (object|array); when it is
# omitted it derives from $2's scheme, so the rulesets call sites keep their exact
# today's semantics (plan addendum 10: want_type is an ADDED parameter, never a
# scheme replacement). CODE/BODY are published for classify_target (addendum 5);
# verdict semantics stay byte-identical.
authorized_body() {
  printf '%s' "$1" | jq -e --arg t "$2" '.success == true and (.result | type == $t)' >/dev/null 2>&1
}

ZONE_CONTROL_OK=0

# check <url> <scheme:zone|account> <trust404:0|1> [want_type:object|array] — probes
# one URL, sets VERDICT + CODE + BODY, returns 0 (pass: authorized / empty-404-under
# -control-when-trusted) or 1 (fail). The Authorization header is passed from a
# private fd so the token never lands in the process argv (readable via
# ps / /proc/<pid>/cmdline).
check() {
  local url="$1" scheme="$2" trust404="${3:-0}" want_type="${4:-}" resp
  if [[ -z "$want_type" ]]; then
    want_type="object"
    if [[ "$scheme" == "account" ]]; then want_type="array"; fi
  fi
  CODE=""; BODY=""
  resp="$(curl --disable --noproxy '*' -sS --max-time 15 -w '\n%{http_code}' \
    -H @<(printf 'Authorization: Bearer %s' "$TOK") "$url" 2>/dev/null || true)"
  if [[ "$resp" != *$'\n'* ]]; then VERDICT="empty (no response)"; return 1; fi
  CODE="${resp##*$'\n'}"
  BODY="${resp%$'\n'*}"
  if [[ ! "$CODE" =~ ^[0-9]+$ ]]; then VERDICT="empty (non-numeric status)"; return 1; fi
  if [[ "$CODE" == "200" ]]; then
    if authorized_body "$BODY" "$want_type"; then VERDICT="authorized (200)"; return 0; fi
    VERDICT="degraded (200 body not success/$want_type)"; return 1
  fi
  # A 404 is trusted as "phase exists, empty" ONLY for an entrypoint whose
  # 403-on-missing semantics are verified (trust404=1) AND under an authorized
  # zone control. Every other 404 fails closed.
  if [[ "$CODE" == "404" ]]; then
    if [[ "$scheme" == "zone" && "$ZONE_CONTROL_OK" == "1" && "$trust404" == "1" ]]; then
      VERDICT="empty (404, verified phase exists)"; return 0
    fi
    VERDICT="denied (404, unverified — fail-closed)"; return 1
  fi
  VERDICT="denied ($CODE)"; return 1
}

report() { printf '  %-42s %s\n' "$1" "$2"; }

# ============================================================================
# Migration profiles (#12931, CTO L49) — run path. Exits; never falls through to
# the read-only profiles below.
if is_migration_profile "$PROFILE"; then
declare -A MIG_TOK=()
# shellcheck disable=SC2317,SC2329  # invoked indirectly via the EXIT trap
mig_cleanup() { MIG_TOK=(); unset MIG_TOK; }
trap mig_cleanup EXIT

# Acquire every token the profile's tables name, before the first request: a
# missing staging key must stop the run before any write probe is sent.
mig_need_keys=()
while IFS='|' read -r _l _u c_key _w; do [[ -n "$_l" ]] && mig_need_keys+=("$c_key"); done < <(mig_ctrl_rows "$PROFILE")
while IFS='|' read -r _l _m _u w_grant w_deny _k; do [[ -n "$_l" ]] && mig_need_keys+=("$w_grant" "$w_deny"); done < <(mig_write_rows "$PROFILE")
for base_key in "${mig_need_keys[@]}"; do
  [[ -n "${MIG_TOK[$base_key]:-}" ]] && continue
  MIG_TOK[$base_key]="$(get_secret "$(mig_key "$base_key")")"
done
unset _l _u _w _m _k

# mig_req <GET|PUT|POST|PATCH> <url> <token-key> [body-kind] — sets CODE + BODY. A
# write verb carries exactly one of the two readonly bodies, chosen by the row's
# body-kind through the closed case below (an unknown kind exits 2), and
# SETTINGS_PROBE_BODY only to this zone's settings URL. The method allowlist and
# the body map are enforced here, at the one call site that can send a write.
# Always called directly, never inside $(…), so its exit 2 ends the run.
mig_req() {
  local method="$1" url="$2" key="$3" kind="${4:-}" resp
  local w_body
  CODE=""; BODY=""
  case "$method" in
    GET)
      resp="$(curl --disable --noproxy '*' -sS --max-time 15 -w '\n%{http_code}' \
        -H @<(printf 'Authorization: Bearer %s' "${MIG_TOK[$key]}") "$url" 2>/dev/null || true)" ;;
    PUT|POST|PATCH)
      case "$kind" in
        invalid) w_body="$INVALID_BODY" ;;
        settings-json)
          if [[ "$url" != "$API/zones/$MIG_ZONE/settings" ]]; then
            echo "cf-token-scope: body-kind settings-json on $url, which is not the zone settings URL (table corruption)" >&2
            exit 2
          fi
          w_body="$SETTINGS_PROBE_BODY" ;;
        *)
          echo "cf-token-scope: write-probe body-kind '$kind' is not invalid or settings-json (table corruption)" >&2
          exit 2 ;;
      esac
      resp="$(curl --disable --noproxy '*' -sS --max-time 15 -w '\n%{http_code}' -X "$method" \
        -H 'Content-Type: application/json' --data-binary "$w_body" \
        -H @<(printf 'Authorization: Bearer %s' "${MIG_TOK[$key]}") "$url" 2>/dev/null || true)" ;;
    *)
      echo "cf-token-scope: write-probe method '$method' is not PUT/POST/PATCH (table corruption)" >&2
      exit 2 ;;
  esac
  if [[ "$resp" != *$'\n'* ]]; then CODE="000"; return 0; fi
  CODE="${resp##*$'\n'}"
  BODY="${resp%$'\n'*}"
  [[ "$CODE" =~ ^[0-9]+$ ]] || CODE="000"
  return 0
}

# Only digits ride the verdict line (same rule as classify_target).
mig_errcode() {
  local err
  err="$(printf '%s' "$BODY" | jq -r '.errors[0].code // empty' 2>/dev/null || true)"
  [[ "$err" =~ ^[0-9]+$ ]] && printf ', err %s' "$err"
  return 0
}

# A 2xx to a never-valid body should be impossible. Abort the whole run, read the
# endpoint back with the grant token, print a sanitized summary, exit 4. An array
# read-back also says whether any listed id is probe-prefixed (probe_id_listed),
# the one fact a settings 2xx re-ruling needs.
mig_fatal() {
  local label="$1" url="$2" key="$3" code="$4"
  report "$label" "FATAL ($code to a never-valid write probe)"
  echo "FATAL: $label answered $code to a never-valid write probe — a mutation may have landed. Reading it back:"
  mig_req GET "$url" "$key"
  printf '  read-back %s -> %s ' "$label" "$CODE"
  printf '%s' "$BODY" | jq -c '
    def safe: walk(if type == "string" then (if test("^[A-Za-z0-9_.:+-]{0,64}$") then . else "<redacted>" end) else . end);
    {success, result: (.result | if type == "array" then {count: length, ids: ([.[] | .id?] | .[:20]),
                                                          probe_id_listed: any(.[]; (.id? | type) == "string" and (.id | startswith("cf_token_scope_probe_")))}
                               elif type == "object" then {id, version, last_updated, rules: ((.rules // []) | length)}
                               else . end)} | safe' 2>/dev/null || printf '(unparseable body)'
  printf '\n'
  echo "probe=$PROFILE verdict=fatal-mutation"
  exit 4
}

mig_staged_note=""
[[ "$STAGED" == "1" ]] && mig_staged_note=" (staged _NEXT keys)"
echo "cf-token-scope: migration profile $PROFILE — account ${MIG_ACCT:0:8}… zone ${MIG_ZONE:0:8}…$mig_staged_note"
MIG_DENIED=0
MIG_INCONCLUSIVE=0

# 1. Known-present controls (GET, fail-closed body shape).
MIG_CTRL_OK=1
# Initialized here, never inherited: the collision guard (step 3) trusts only a
# list this run parsed from an authorized, NON-EMPTY settings control.
MIG_SETTINGS_LIST=""
MIG_SETTINGS_CTRL_OK=0
while IFS='|' read -r c_label c_url c_key c_want; do
  [[ -n "$c_label" ]] || continue
  url="$(mig_url "$c_url")"
  mig_req GET "$url" "$c_key"
  if [[ "$CODE" == "200" ]] && authorized_body "$BODY" "$c_want"; then
    case "$c_label" in
      zones/*/settings)
        # A real zone always lists settings: an empty list is degraded, or the
        # collision guard would pass on it vacuously.
        if printf '%s' "$BODY" | jq -e '.result | length > 0' >/dev/null 2>&1; then
          report "control: $c_label" "authorized (200)"
          MIG_SETTINGS_LIST="$BODY"; MIG_SETTINGS_CTRL_OK=1
        else
          MIG_CTRL_OK=0; MIG_INCONCLUSIVE=1
          report "control: $c_label" "degraded (200 settings list empty)"
        fi ;;
      zones/*/rulesets)    report "control: $c_label" "authorized (200)"; MIG_ZONE_LIST="$BODY" ;;
      accounts/*/rulesets) report "control: $c_label" "authorized (200)"; MIG_ACCT_LIST="$BODY" ;;
      *)                   report "control: $c_label" "authorized (200)" ;;
    esac
  else
    MIG_CTRL_OK=0; MIG_INCONCLUSIVE=1
    if [[ "$CODE" == "200" ]]; then report "control: $c_label" "degraded (200 body not success/$c_want)"
    else report "control: $c_label" "denied ($CODE$(mig_errcode))"; fi
  fi
done < <(mig_ctrl_rows "$PROFILE")

# 2. Whole-list entrypoint audit (redirects-dns, ADR-136): only under authorized
# list controls, so an absent entry is read from a parsed list, never a 404.
if [[ "$PROFILE" == "redirects-dns" && "$MIG_CTRL_OK" == "1" ]]; then
  mig_audit() {
    local list="$1" kind="$2" phase="$3" id
    id="$(printf '%s' "$list" | jq -r --arg k "$kind" --arg p "$phase" \
      '[.result[] | select(.kind == $k and .phase == $p) | .id] | first // empty' 2>/dev/null || true)"
    if [[ -z "$id" ]]; then report "audit: $phase" "entrypoint-absent"
    elif [[ "$id" =~ ^[0-9a-f]{32}$ ]]; then report "audit: $phase" "entrypoint-present id=$id (import it, never overwrite)"
    else report "audit: $phase" "entrypoint-present id=<malformed>"; fi
  }
  for ph in "${MIG_AUDIT_ZONE_PHASES[@]}"; do mig_audit "${MIG_ZONE_LIST:-}" zone "$ph"; done
  for ph in "${MIG_AUDIT_ACCT_PHASES[@]}"; do mig_audit "${MIG_ACCT_LIST:-}" root "$ph"; done
fi

# 3. Collision guard (CTO L49 rule 1), after the controls and before the first
# write: SETTINGS_PROBE_BODY is never sent to a zone that lists one of its ids.
# The list rides stdin, never jq's argv (ps-visible, E2BIG past 128 KiB), and
# jq's verdict stays off stdout (the data channel). Whole-id equality, never a
# substring match. rc 0 = a hit, 1 = clear, anything else = could not evaluate.
mig_has_json=0
while IFS='|' read -r _l _m _u _g _d w_kind; do
  if [[ -n "$_l" && "$w_kind" == "settings-json" ]]; then mig_has_json=1; fi
done < <(mig_write_rows "$PROFILE")
unset _l _m _u _g _d
if [[ "$mig_has_json" == "1" && "$MIG_SETTINGS_CTRL_OK" == "1" ]]; then
  mig_rc=0
  printf '%s' "$MIG_SETTINGS_LIST" | jq -e --argjson body "$SETTINGS_PROBE_BODY" '. as $list | any($body.items[].id; . as $i | any($list.result[]?; .id? == $i))' >/dev/null 2>&1 || mig_rc=$?
  case "$mig_rc" in
    0) echo "cf-token-scope: a setting named like the probe id exists on this zone; refusing to send a body that names it" >&2
       exit 2 ;;
    1) ;;
    *) echo "cf-token-scope: could not evaluate the settings list (jq rc $mig_rc); refusing to send the JSON probe body" >&2
       exit 2 ;;
  esac
fi

# 4. Write probes: deny control first (must be 403), then the grant token (400 =
# authorized). Any 2xx from either token is fatal. A settings-json row is sent
# only under a parsed settings list (step 3); otherwise it is skipped.
while IFS='|' read -r w_label w_method w_url w_grant w_deny w_kind; do
  [[ -n "$w_label" ]] || continue
  url="$(mig_url "$w_url")"
  if [[ "$w_kind" == "settings-json" && "$MIG_SETTINGS_CTRL_OK" != "1" ]]; then
    MIG_INCONCLUSIVE=1
    report "$w_label" "inconclusive (settings control not authorized — the JSON probe body is only sent under a parsed settings list)"
    continue
  fi
  mig_req "$w_method" "$url" "$w_deny" "$w_kind"
  if [[ "$CODE" == 2?? ]]; then mig_fatal "$w_label" "$url" "$w_grant" "$CODE"; fi
  if [[ "$CODE" != "403" ]]; then
    MIG_INCONCLUSIVE=1
    if [[ "$CODE" == "400" ]]; then
      report "$w_label" "inconclusive (deny control $(mig_key "$w_deny") got 400, not 403 — a 400 cannot prove scope here)"
    else
      report "$w_label" "inconclusive (deny control $(mig_key "$w_deny") got $CODE$(mig_errcode), not 403)"
    fi
    continue
  fi
  mig_req "$w_method" "$url" "$w_grant" "$w_kind"
  if [[ "$CODE" == 2?? ]]; then mig_fatal "$w_label" "$url" "$w_grant" "$CODE"; fi
  case "$CODE" in
    400) report "$w_label" "authorized ($w_method 400 after a 403 control)" ;;
    401|403) MIG_DENIED=1; report "$w_label" "denied ($CODE$(mig_errcode))" ;;
    *) MIG_INCONCLUSIVE=1; report "$w_label" "inconclusive ($w_method $CODE$(mig_errcode))" ;;
  esac
done < <(mig_write_rows "$PROFILE")

echo
if [[ "$MIG_DENIED" == "1" ]]; then
  echo "probe=$PROFILE verdict=denied"
  echo "FAIL: a $PROFILE write scope is denied on the new account — do not dispatch this phase." >&2
  exit 3
fi
if [[ "$MIG_INCONCLUSIVE" == "1" ]]; then
  echo "probe=$PROFILE verdict=inconclusive"
  echo "FAIL: a control was not established, so the $PROFILE write scopes are unproven — do not dispatch this phase." >&2
  exit 3
fi
echo "probe=$PROFILE verdict=pass"
echo "PASS: every $PROFILE write scope authorized on the new account (never-valid probe bodies, nothing mutated)"
exit 0
fi


# classify_target <label> — the ONLY neutrality mint site (plan Guard 2 assembly).
# Called for default-token target rows only, after check() published
# VERDICT/CODE/BODY and the caller captured its status into CHECK_RC. Neutrality
# is a clean 403 in BASELINE mode only (addendum 2): degraded/wrong-shape/404/5xx
# never read as absent-scope, and LB_MISSING counts 403 only, so the still-absent
# wording is never asserted for a cause the probe did not establish. The function
# ends with an explicit return 0 (addendum 4): a trailing false [[ ]] test would
# otherwise abort the run mid-ledger under set -e. Retained-class rows never
# consult this — a retained 403 stays denied (403) + FAILED, whatever the profile.
classify_target() {
  local label="$1"
  if [[ "$CHECK_RC" == "0" ]]; then
    report "$label" "$VERDICT"; LB_OK=$((LB_OK + 1)); return 0
  fi
  if [[ "$CODE" == "403" && "$LB_EXPECT" == "0" ]]; then
    local err
    err="$(printf '%s' "$BODY" | jq -r '.errors[0].code // empty' 2>/dev/null || true)"
    # stdout is the documented data channel: only digits may ride the verdict line
    # (a non-scalar errors[0].code could otherwise inject rows a grep-consumer reads).
    [[ "$err" =~ ^[0-9]+$ ]] || err=""
    report "$label" "not-yet-widened (403${err:+, err $err})"
    LB_NOTED=1
    return 0
  fi
  FAILED=1
  report "$label" "$VERDICT"
  if [[ "$LB_EXPECT" == "1" && "$CODE" == "403" ]]; then LB_MISSING=$((LB_MISSING + 1)); fi
  return 0
}

FAILED=0
# TARGET_PRESENT lives above the dispatch so the summary tail always reads an
# initialized value — defensive against branch reordering, not argv-reachable
# behavior (fix-round seats: cross-validation forces TARGET empty under
# default-token).
TARGET_PRESENT=0

# Table-integrity pre-flight (structural seat, sandbox-mutant-verified): a class
# value outside {retained,target} must NEVER fall through to the target branch —
# that route mints neutrality for a retained row's genuine 403 loss. This is the
# runtime defense with no argv-reachable twin (D12d pins its presence); profile/
# table drift beyond this has CI pins (D-pc enumeration, D3 per-arm loop) rather
# than a second runtime arm here (fix-round consolidation: pin wins over
# tripwire).
if [[ "$PROFILE" == "default-token" ]]; then
  for r_row in "${DT_ROWS[@]}"; do
    r_class="${r_row%%|*}"
    if [[ "$r_class" != "retained" && "$r_class" != "target" ]]; then
      echo "cf-token-scope: DT_ROWS class '$r_class' is neither retained nor target (table corruption — neutrality eligibility must not fall through)" >&2
      exit 2
    fi
  done
fi

if [[ "$PROFILE" == "rulesets" ]]; then
echo "cf-token-scope: probing $TOKEN_SECRET retained scope (read-only)"

# 1. Zone control first — every zone 404's trust depends on it. The control must
# be an authorized 200 (trust404=0: a control that only 404s proves nothing).
if check "$API/zones/$ZONE/rulesets/phases/$ZONE_CONTROL/entrypoint" zone 0; then ZONE_CONTROL_OK=1; fi
report "$ZONE_CONTROL" "$VERDICT"
[[ "$ZONE_CONTROL_OK" == "1" ]] || FAILED=1

# 2. Remaining retained zone phases (trust404 per the verified-phase rule).
for p in "${ZONE_PHASES[@]}"; do
  [[ "$p" == "$ZONE_CONTROL" ]] && continue
  check "$API/zones/$ZONE/rulesets/phases/$p/entrypoint" zone "$(trust404_for "$p")" || FAILED=1
  report "$p" "$VERDICT"
done

# 3. Account list — the account-scheme control (an account 404 is a FAIL).
check "$API/accounts/$ACCT/rulesets" account 0 || FAILED=1
report "accounts/<acct>/rulesets" "$VERDICT"

# 4. Target entrypoint (the newly-widened scope), if given. TARGET_PRESENT (hoisted
# above the dispatch) gates the success line so it cannot print unless the target
# probe actually passed. This rulesets path keeps its own handling; it never
# consults classify_target (plan addendum 8 — the target-class vocabulary is
# default-token-local).
if [[ -n "$TARGET" ]]; then
  if check "$API/zones/$ZONE/rulesets/phases/$TARGET/entrypoint" zone "$(trust404_for "$TARGET")"; then
    TARGET_PRESENT=1
  else
    FAILED=1
  fi
  report "target: $TARGET" "$VERDICT"
fi

else

# default-token profile: retained ledger rows, then the two LB readiness rows —
# iterated from DT_ROWS, the SAME table --dry-run printed (print/run parity).
echo "cf-token-scope: probing $TOKEN_SECRET retained + LB-readiness scope (read-only)"
for row in "${DT_ROWS[@]}"; do
  IFS='|' read -r r_class r_label r_url r_want r_scheme <<<"$row"
  # Quoted replacements: bash >= 5.2 treats '&' in an UNQUOTED substitution
  # replacement as the matched text — an id containing '&' would splice a literal
  # '$ZONE' back into the URL (panel seat, measured).
  url="${r_url//\$ZONE/"$ZONE"}"
  url="${url//\$ACCT/"$ACCT"}"
  CHECK_RC=0
  check "$url" "$r_scheme" 0 "$r_want" || CHECK_RC=1
  if [[ "$r_class" == "retained" ]]; then
    [[ "$CHECK_RC" == "0" ]] || FAILED=1
    report "$r_label" "$VERDICT"
  else
    LB_TOTAL=$((LB_TOTAL + 1))
    classify_target "$r_label"
  fi
done

fi

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "PASS: no scope dropped"
  if [[ "$PROFILE" == "default-token" ]]; then
    # Assert mode green compares against the profile's OWN target-row count
    # (parameterized, never a hardcoded 2 — addendum 3; aggregate-floor rule D11).
    if [[ "$LB_EXPECT" == "1" && "$LB_TOTAL" -gt 0 && "$LB_OK" -eq "$LB_TOTAL" ]]; then
      echo "PASS: LB scopes present — confirm the 403->present transition against your pre-widen baseline"
    elif [[ "$LB_EXPECT" == "0" && "$LB_NOTED" == "1" ]]; then
      echo "NOTE: LB scope not-yet-widened — expected BEFORE the #11181 widen; re-run with --expect-lb-scopes after it"
    fi
  fi
  # "present", not "added": a single run cannot observe the 403->authorized
  # transition — the operator confirms that against the pre-widen baseline.
  [[ -n "$TARGET" && "$TARGET_PRESENT" == "1" ]] && \
    echo "PASS: target scope present ($TARGET) — confirm the 403->present transition against your pre-widen baseline"
  exit 0
fi

# The zone-control diagnostic names a probe the default-token profile never
# issues — gated to rulesets (addendum 9, pinned by the D-block lacks).
if [[ "$PROFILE" == "rulesets" && "$ZONE_CONTROL_OK" != "1" ]]; then
  echo "FAIL: zone control ($ZONE_CONTROL) is not authorized — the token is likely bad or missing its base scope, not a single dropped scope." >&2
fi
# The assert-mode blocking verdict rides STDOUT — the documented data channel
# (#7797 rationale; addendum 1). Only minted for a real 403 (addendum 2): a
# degraded/wrong-shape target row says so on its own row and never here.
if [[ "$PROFILE" == "default-token" && "$LB_EXPECT" == "1" && "$LB_MISSING" -gt 0 ]]; then
  echo "FAIL: LB scope still absent — the widen was not applied to CF_API_TOKEN"
fi
echo "FAIL: retained-scope probe failed — inspect the denied/degraded entrypoints above." >&2
exit 3
