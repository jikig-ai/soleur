#!/usr/bin/env bash
# Report every marketplace registration and every installed/enabled plugin on
# this machine that resolves to a target repository (default jikig-ai/soleur).
#
# WHY THIS EXISTS (#7489). The legacy `soleur@soleur` marketplace entry cannot be
# revoked remotely: `autoUpdate` is client-side state. So the tracker's closing
# condition is a statement about MACHINES, and the only honest way to make that
# statement is to ask a machine. This script is that question, made repeatable.
#
# THE TWO PROPERTIES THAT MAKE IT HONEST, both of which a naive implementation
# silently lacks:
#
#   1. IT WALKS THE SETTINGS PRECEDENCE CHAIN, NOT A LIST OF SITES SOMEONE SAW.
#      An earlier enumeration of this problem listed the two files that happened
#      to exist on the author's laptop. Reading the CLI bundle showed
#      `settings.local.json` and `managed-settings.json` alongside
#      `settings.json`, at both user and project scope. A registration in the
#      managed-policy file is the one declaration that CANNOT be overridden
#      locally, so a probe that skips it reports "clean" on precisely the machine
#      state an operator is least able to fix. Every site in the chain is listed
#      with its resolved path and read status whether or not it exists — an
#      absent site is enumerated evidence, and a site that cannot be PARSED is
#      reported `unreadable` rather than collapsing into `absent`, because
#      "I could not read it" and "it is not there" are different answers and only
#      one of them is safe to call clean.
#
#   2. THE PREDICATE IS TWO-STAGE, BECAUSE THE SITES DO NOT SHARE A SCHEMA.
#      Registration sites carry `source`, so they are matched on the REPOSITORY —
#      never on the alias key, which is chosen locally at `add` time and is
#      routinely something other than the repo name. But `installed_plugins.json`
#      carries no repo field at all (its records are scope / projectPath /
#      installPath / version / gitCommitSha) and `enabledPlugins` is a
#      `plugin@alias` boolean map. Neither can be matched on a repo predicate, so
#      both are joined back through the alias set stage one produced. An alias
#      that resolves to no registration is reported as an explicit UNKNOWN. That
#      case is not hypothetical bookkeeping: it is what a half-removed install
#      looks like, and reporting it as clean is the exact false negative this
#      probe exists to prevent.
#
# `source` HAS TWO SHAPES, MEASURED. `{"source":"github","repo":"owner/name"}`
# and `{"source":"git","url":"https://github.com/owner/name.git"}` both occur in
# a real `known_marketplaces.json`. They denote the same repository, so a
# repo-field-only predicate is blind to half of them.
#
# Reads only. This script never writes to ~/.claude.
#
# Exit codes: 0 = the probe ran. The VERDICT is data, not an exit status — a
# caller that wants to branch reads `.verdict`. 2 = the probe could not run.

set -euo pipefail

TARGET_REPO="jikig-ai/soleur"
OUT_JSON=0
REDACT=0
PROBE_HOME="${HOME:-}"
PROBE_PROJECT="$PWD"

# Platform default for the managed-policy file. Overridable so the mutation
# battery can point at a fixture instead of needing root to write /etc.
case "$(uname -s 2>/dev/null || echo Linux)" in
  Darwin) MANAGED_PATH="/Library/Application Support/ClaudeCode/managed-settings.json" ;;
  *) MANAGED_PATH="/etc/claude-code/managed-settings.json" ;;
esac

usage() {
  cat <<'USAGE'
Usage: plugin-legacy-resolver-probe.sh [options]

  --json               Emit the full reading as JSON (default: human-readable)
  --repo <owner/name>  Target repository (default: jikig-ai/soleur)
  --home <path>        HOME to probe (default: $HOME)
  --project <path>     Project directory for project-scope settings (default: $PWD)
  --managed <path>     Managed-policy settings file (default: platform path)
  --redact             Replace home and project prefixes with placeholders
  -h, --help           This message
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) OUT_JSON=1; shift ;;
    --redact) REDACT=1; shift ;;
    --repo) TARGET_REPO="${2:?--repo needs a value}"; shift 2 ;;
    --home) PROBE_HOME="${2:?--home needs a value}"; shift 2 ;;
    --project) PROBE_PROJECT="${2:?--project needs a value}"; shift 2 ;;
    --managed) MANAGED_PATH="${2:?--managed needs a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required" >&2; exit 2; }
[[ -n "$PROBE_HOME" ]] || { echo "FATAL: no HOME resolved; pass --home" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Site reader. Emits one JSON object per site, ALWAYS — including for a site
# that does not exist, because an unlisted site is indistinguishable from a site
# that was checked and found clean.
# ---------------------------------------------------------------------------
site_json() { # <name> <path> <kind>
  local name="$1" path="$2" kind="$3"
  local status raw

  if [[ ! -e "$path" ]]; then
    status="absent"; raw="null"
  elif [[ ! -r "$path" ]]; then
    status="unreadable"; raw="null"
  elif ! raw="$(jq -c '.' -- "$path" 2>/dev/null)"; then
    # Present but not parseable. NOT 'absent': a corrupt settings file is a
    # state where "no legacy registration found" is unproven, not proven false.
    status="unreadable"; raw="null"
  else
    status="present"
  fi

  jq -n \
    --arg site "$name" --arg path "$path" --arg status "$status" --arg kind "$kind" \
    --argjson raw "${raw:-null}" \
    '{site: $site, path: $path, status: $status, kind: $kind, raw: $raw}'
}

# Precedence chain, highest-precedence declaration site first. The managed file
# leads because a declaration there cannot be overridden locally.
RESULT="$({
  site_json "managed-settings"      "$MANAGED_PATH"                                   "settings"
  site_json "user-settings"         "$PROBE_HOME/.claude/settings.json"               "settings"
  site_json "user-settings-local"   "$PROBE_HOME/.claude/settings.local.json"         "settings"
  site_json "project-settings"      "$PROBE_PROJECT/.claude/settings.json"            "settings"
  site_json "project-settings-local" "$PROBE_PROJECT/.claude/settings.local.json"     "settings"
  site_json "known-marketplaces"    "$PROBE_HOME/.claude/plugins/known_marketplaces.json" "known-marketplaces"
  site_json "installed-plugins"     "$PROBE_HOME/.claude/plugins/installed_plugins.json" "installs"
} | jq -s \
  --arg target "$TARGET_REPO" \
  --arg home "$PROBE_HOME" \
  --arg project "$PROBE_PROJECT" \
  --argjson redact "$REDACT" '

# ---- repository normalisation --------------------------------------------
# Handles both measured shapes. Returns null when neither is present, which is
# what makes an unresolvable registration visible instead of silently absent.
def norm_repo:
  if type != "object" then null
  elif (.repo | type) == "string" then .repo
  elif (.url | type) == "string" then
    ( .url
      | (try (capture("github\\.com[:/](?<o>[^/]+)/(?<r>[^/]+?)(?:\\.git)?/?$") | "\(.o)/\(.r)")
         catch null) )
  else null
  end;

def same_repo($a; $b):
  ($a != null) and ($b != null) and (($a | ascii_downcase) == ($b | ascii_downcase));

# ---- registrations per site ----------------------------------------------
def registrations:
  if .status != "present" then []
  else
    ( if .kind == "known-marketplaces" then (.raw // {})
      elif .kind == "settings" then (.raw.extraKnownMarketplaces // {})
      else {} end )
    | if type == "object" then
        to_entries
        | map({
            alias: .key,
            repo: (.value.source | norm_repo),
            autoUpdate: (if (.value | type) == "object" and (.value | has("autoUpdate"))
                         then .value.autoUpdate else null end)
          })
        | map(. + { matches_target: same_repo(.repo; $target) })
      else [] end
  end;

def enabled_entries:
  if .status != "present" or .kind != "settings" then []
  else
    (.raw.enabledPlugins // {})
    | if type == "object" then (to_entries | map(select(.value == true) | .key)) else [] end
  end;

# Redaction has to cover FOUR categories, not just the first: home paths, the
# names and layout of UNRELATED local repositories, install timestamps, and
# machine identifiers. Stripping the home prefix alone leaves
# "<home>/git-repositories/<another-project>" on the page, which discloses the
# layout and the names that these readings get committed and quoted into.
#
# The project prefix is tested BEFORE the home prefix: the project lives under
# the home directory, so a home-first substitution would consume it and the
# project branch could never match.
def redact_prefix($p; $label):
  if ($p | length) > 0 and (startswith($p)) then ($label + (.[($p | length):])) else null end;

def redact_path:
  if $redact == 0 then .
  elif (. // "") == "" then .
  else ( (redact_prefix($project; "<project>"))
         // (redact_prefix($home; "<home>"))
         // . )
  end;

. as $raw_sites

| ($raw_sites | map(. + { registrations: registrations, enabled: enabled_entries })) as $sites

# Stage one: the alias sets. `matched` are aliases pointing at the target;
# `known` are aliases that resolve to ANY repository. The difference is what
# makes stage two able to say "unknown" rather than "not the target".
| ([ $sites[] | .registrations[] | select(.matches_target) | .alias ] | unique) as $matched_aliases
| ([ $sites[] | .registrations[] | select(.repo != null) | .alias ] | unique) as $known_aliases

# Stage two: join installs back through the alias set. installed_plugins.json
# has no repo field, so this join is the only way to classify them at all.
# MEASURED: `.plugins[<key>]` is an ARRAY of install records, not one object —
# the same plugin id can be installed at several project scopes simultaneously,
# and each scope is its own record. Reading it as a single object reports the
# first install and is silently blind to the rest, which under-reports exactly
# the population this probe exists to count. The object spelling is still
# accepted so a differently-versioned CLI does not crash the probe.
| ( [ $sites[] | select(.kind == "installs" and .status == "present")
      | (.raw.plugins // {})
      | if type == "object" then
          to_entries
          | map(
              . as $e
              | ( $e.value
                  | if type == "array" then . elif type == "object" then [.] else [] end )
              | map({
                  key: $e.key,
                  plugin: ($e.key | split("@") | if length > 1 then (.[0:-1] | join("@")) else .[0] end),
                  alias:  ($e.key | split("@") | if length > 1 then last else "" end),
                  scope: (.scope // null),
                  projectPath: (.projectPath // null),
                  installPath: (.installPath // null)
                })
            )
          | flatten
        else [] end
    ] | add // [] ) as $installs_raw

| ( $installs_raw
    | map(. + {
        # The parentheses around `if` are REQUIRED, not stylistic: an object
        # VALUE must be a term, and a bare `if ... end` there is a jq 1.8
        # relaxation. On jq 1.7 (what CI runs) it is `syntax error, unexpected
        # if` at compile time, so the probe dies before evaluating anything and
        # the whole suite fails in 42ms. Local jq 1.8 accepted all three sites,
        # which is why this only surfaced in CI. Note the already-correct
        # `alias:` value below, which has always been parenthesized.
        resolution:
          ( if (.alias as $a | $matched_aliases | index($a)) != null then "target"
            elif (.alias as $a | $known_aliases | index($a)) != null then "other"
            else "unknown" end )
      }) ) as $installs

| ( [ $sites[] | .enabled[] ]
    | unique
    | map({ key: ., alias: (. | split("@") | if length > 1 then last else "" end) })
    | map(. + {
        resolution:
          ( if (.alias as $a | $matched_aliases | index($a)) != null then "target"
            elif (.alias as $a | $known_aliases | index($a)) != null then "other"
            else "unknown" end )
      }) ) as $enabled

| ([ $sites[] | select(.status == "unreadable") ] | length) as $unreadable_count
| ([ $sites[] | .registrations[] | select(.matches_target) ] | length) as $matched_reg_count
| ([ $installs[] | select(.resolution == "target") ] | length) as $target_install_count
| ([ $installs[] | select(.resolution == "unknown") ] | length) as $unknown_install_count
| ([ $enabled[]  | select(.resolution == "target") ] | length) as $target_enabled_count
| ([ $enabled[]  | select(.resolution == "unknown") ] | length) as $unknown_enabled_count

# Distinct project paths OUTSIDE the probed project get a stable placeholder
# each. This keeps the two facts a reader needs — how many distinct projects,
# and which install belongs to which — while disclosing neither their names nor
# the directory layout they sit in.
| ( if $redact == 0 then {}
    else ( [ $installs[] | (.projectPath // "")
             | select(. != "" and ((startswith($project)) | not)) ]
           | unique | to_entries
           | map({ key: .value, value: ("<unrelated-local-project-" + ((.key + 1) | tostring) + ">") })
           | from_entries )
    end ) as $projmap

| {
  target_repo: $target,
  verdict:
    # A positive resolution outranks an ambiguous one: if anything definitely
    # points at the target, that is the finding, and the unknowns are detail.
    # Parenthesized for the jq-1.7 object-value reason documented above.
    ( if ($matched_reg_count + $target_install_count + $target_enabled_count) > 0 then "legacy-present"
      elif ($unknown_install_count + $unknown_enabled_count + $unreadable_count) > 0 then "unknown-present"
      else "clean" end ),
  sites: ( $sites | map({
            site, kind, status,
            path: (.path | redact_path),
            registrations,
            enabled
          }) ),
  matched_aliases: $matched_aliases,
  known_aliases: $known_aliases,
  installs: ( $installs
              | map(.projectPath = ( (.projectPath // "")
                                     | if ($projmap[.] // null) != null then $projmap[.]
                                       else redact_path end ))
              | map(.installPath = ((.installPath // "") | redact_path)) ),
  enabled: $enabled,
  summary: {
    site_count: ($sites | length),
    unreadable_site_count: $unreadable_count,
    matched_registration_count: $matched_reg_count,
    target_install_count: $target_install_count,
    unknown_install_count: $unknown_install_count,
    target_enabled_count: $target_enabled_count,
    unknown_enabled_count: $unknown_enabled_count
  }
}
'
)" || { echo "FATAL: probe evaluation failed" >&2; exit 2; }

if [[ "$OUT_JSON" -eq 1 ]]; then
  printf '%s\n' "$RESULT"
  exit 0
fi

# ---- human-readable rendering ---------------------------------------------
jq -r '
  "target repository : \(.target_repo)",
  "verdict           : \(.verdict)",
  "",
  "Settings precedence chain (every site listed, present or not):",
  ( .sites[]
    | "  [\(.status | (. + "         ")[0:10])] \(.site)  \(.path)"
      + ( if (.registrations | length) > 0 then
            ( "\n" + ( [ .registrations[]
                         | "        - alias=\(.alias) repo=\(.repo // "<unresolvable>") autoUpdate=\(.autoUpdate | tostring)"
                           + (if .matches_target then "   <== TARGET" else "" end) ]
                       | join("\n") ) )
          else "" end ) ),
  "",
  "Installed plugins (joined back through the alias set):",
  ( if (.installs | length) == 0 then "  (none recorded)"
    else ( .installs[] | "  \(.key)  resolution=\(.resolution) scope=\(.scope // "-") projectPath=\(.projectPath // "-")" )
    end ),
  "",
  "Summary: \(.summary | to_entries | map("\(.key)=\(.value)") | join(" "))"
' <<<"$RESULT"
