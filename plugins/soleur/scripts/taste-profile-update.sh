#!/usr/bin/env bash
# taste-profile-update.sh — context-keyed design taste-profile writer/validator
# (#5990 · FR7 · ADR-090). Rides FR6 declarative context-injection (ADR-086):
# the committed taste-profile.md is agent-writable content, so per ADR-086
# §Consequences (content-trust ≠ path-trust) THIS helper is the sanitizing
# boundary — every model-supplied token (context, axis, value, date) is validated
# before it reaches the committed file that FR6 re-injects.
#
# Modes:
#   write:     taste-profile-update.sh <profile.md> <context> <axis> <value> <today-YYYY-MM-DD>
#   validate:  taste-profile-update.sh --validate <profile.md>
#
# Model: entries keyed by (context, axis) → value, ordered by RECENCY
# (last_reinforced, tie-break reinforce_count). No numeric weighting/scoring.
# Contradiction fires only within the SAME (context, axis); resolution = supersede,
# logged to contradictions[]. Automated writes bump `last_updated` only — never
# `last_reviewed` (freshness convention / context-reviewed-gate.sh).
#
# jq + bash only. Whole-file re-render from the parsed frontmatter + transformed
# JSON block (the machine block is the source of truth; the human tables are
# regenerated). Atomic tmp+mv; original preserved on any failure.
set -uo pipefail

# --- allowlists / sanitizers (the content-trust boundary) --------------------
CONTEXT_ALLOW=" landing-page marketing-site dashboard app-ui docs email component "
AXIS_ALLOW=" aesthetic-direction "
# value = a short lowercase-hyphen aesthetic-direction slug (≤40 chars). The closed
# charset + length cap is the injection defense: no whitespace/punctuation means a
# value can never encode imperative prose that could steer a future FR6-primed session.
VALUE_RE='^[a-z][a-z0-9-]{0,39}$'
DATE_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'

die() { printf 'taste-profile-update: %s\n' "$1" >&2; exit 1; }

extract_json() {
  # Emit the JSON between the data markers, dropping the ``` fences.
  awk '/taste-profile:data:start/{f=1;next} /taste-profile:data:end/{f=0} f' "$1" \
    | sed -e '/^```/d'
}

# Frontmatter-scoped field read (house `c==1` idiom — only the block between the
# first two `---` lines, so a body line beginning with the key never matches).
fm_field() { awk -F': ' -v k="$1" 'FNR==1{c=0} /^---$/{c++; next} c==1 && $0 ~ "^"k":" {print $2; exit}' "$2"; }

validate_json() {
  # $1 = json string. Returns 0 iff EVERY entry AND contradiction is well-formed
  # (same allowlists/regex a fresh write enforces). This is the consumer read-path
  # trust gate (ADR-090): it must cover the whole machine block, not just entries.
  local j="$1"
  echo "$j" | jq -e '.schema == 1 and (.entries|type=="array") and (.contradictions|type=="array")' >/dev/null 2>&1 || return 1
  local bad
  bad=$(echo "$j" | jq -r \
    --arg ctxs "$CONTEXT_ALLOW" --arg axes "$AXIS_ALLOW" \
    --arg valre "$VALUE_RE" --arg datere "$DATE_RE" '
    def ok_ctx($c): ($ctxs | contains(" " + $c + " "));
    def ok_axis($a): ($axes | contains(" " + $a + " "));
    ( [ .entries[]
        | select(
            ( ok_ctx(.context) | not ) or ( ok_axis(.axis) | not )
            or ( (.value|type) != "string" ) or ( .value | test($valre) | not )
            or ( .last_reinforced | test($datere) | not )
            or ( (.reinforce_count|type) != "number" ) or ( .reinforce_count < 1 )
          ) ] | length )
    + ( [ .contradictions[]
        | select(
            ( ok_ctx(.context) | not ) or ( ok_axis(.axis) | not )
            or ( (.old_value|type) != "string" ) or ( .old_value | test($valre) | not )
            or ( (.new_value|type) != "string" ) or ( .new_value | test($valre) | not )
            or ( .date | test($datere) | not )
            or ( (.old_count|type) != "number" )
          ) ] | length )' 2>/dev/null)
  [[ "$bad" == "0" ]] || return 1
  return 0
}

render_file() {
  # $1 profile path, $2 preserved last_reviewed, $3 review_cadence, $4 owner,
  # $5 today (new last_updated), $6 json
  local out reviewed cadence owner today json tables flags
  out="$1"; reviewed="$2"; cadence="$3"; owner="$4"; today="$5"; json="$6"
  # Recency order: most-recent first, higher reinforce_count breaks a same-date tie.
  tables=$(echo "$json" | jq -r '
    if (.entries|length)==0 then "_None yet._"
    else (["| context | axis | value | last_reinforced | reinforced |",
           "|---|---|---|---|---|"]
          + ( .entries | sort_by([.last_reinforced, .reinforce_count]) | reverse
              | map("| \(.context) | \(.axis) | \(.value) | \(.last_reinforced) | \(.reinforce_count) |") ))
         | join("\n")
    end') || return 1
  flags=$(echo "$json" | jq -r '
    if (.contradictions|length)==0 then "_None yet._"
    else ( .contradictions | sort_by(.date) | reverse
           | map("- \(.date) — `\(.context)`/`\(.axis)`: `\(.old_value)` (reinforced \(.old_count)×) superseded by `\(.new_value)`") )
         | join("\n")
    end') || return 1
  local compact
  compact=$(echo "$json" | jq -c '.') || return 1
  cat > "$out" <<EOF
---
last_updated: $today
last_reviewed: $reviewed
review_cadence: $cadence
owner: $owner
---
# Design Taste Profile

Learned operator design preferences, keyed by \`(context, axis)\` and ordered by
recency. Loaded into design sessions via FR6 (\`frontend-design\` skill \`context_queries\`)
and a direct Read (\`ux-design-lead\` agent). See ADR-090.

<!-- Machine block owned by plugins/soleur/scripts/taste-profile-update.sh — do not hand-edit. -->
<!-- taste-profile:data:start -->
\`\`\`json
$compact
\`\`\`
<!-- taste-profile:data:end -->

## Reinforced Aesthetics

$tables

## Contradiction Flags

$flags
EOF
}

# --- validate mode -----------------------------------------------------------
if [[ "${1:-}" == "--validate" ]]; then
  profile="${2:-}"
  [[ -n "$profile" && -f "$profile" ]] || die "validate: profile not found: ${2:-<none>}"
  json="$(extract_json "$profile")"
  [[ -n "$json" ]] || die "validate: no machine block in $profile"
  validate_json "$json" || die "validate: profile failed schema/allowlist checks"
  exit 0
fi

# --- write mode --------------------------------------------------------------
[[ $# -eq 5 ]] || die "usage: <profile.md> <context> <axis> <value> <today> | --validate <profile.md>"
profile="$1"; context="$2"; axis="$3"; value="$4"; today="$5"
[[ -f "$profile" ]] || die "profile not found: $profile"

# Token validation — the ADR-086 content-trust boundary. Reject → exit non-zero,
# original untouched (no write attempted).
[[ "$CONTEXT_ALLOW" == *" $context "* ]] || die "context not in allowlist: $context"
[[ "$AXIS_ALLOW" == *" $axis "* ]]       || die "axis not in allowlist: $axis"
[[ "$value" =~ $VALUE_RE ]]              || die "value must match $VALUE_RE"
[[ "$today" =~ $DATE_RE ]]               || die "date must match $DATE_RE"

json="$(extract_json "$profile")"
[[ -n "$json" ]] || die "no machine block in $profile"
validate_json "$json" || die "existing profile failed validation (refusing to write over a corrupt file)"

new_json="$(echo "$json" | jq -c --arg ctx "$context" --arg axis "$axis" --arg val "$value" --arg today "$today" '
  ( .entries | map(select(.context==$ctx and .axis==$axis)) | .[0] ) as $ex
  | ( if ($ex != null) and ($ex.value != $val)
      then .contradictions += [{context:$ctx, axis:$axis, old_value:$ex.value, new_value:$val, old_count:$ex.reinforce_count, date:$today}]
      else . end )
  | .entries = (
      ( .entries | map(select((.context==$ctx and .axis==$axis) | not)) )
      + [ { context:$ctx, axis:$axis, value:$val, last_reinforced:$today,
            reinforce_count: ( if ($ex != null and $ex.value==$val) then ($ex.reinforce_count + 1) else 1 end ) } ]
    )
')" || die "jq transform failed"
[[ -n "$new_json" ]] || die "jq produced empty output"

reviewed="$(fm_field last_reviewed "$profile")"
cadence="$(fm_field review_cadence "$profile")"
owner="$(fm_field owner "$profile")"

tmp="$(mktemp "${profile}.tmp.XXXXXX")" || die "mktemp failed"
if render_file "$tmp" "$reviewed" "$cadence" "$owner" "$today" "$new_json"; then
  mv -f "$tmp" "$profile"
else
  rm -f "$tmp"
  die "render failed; original preserved"
fi
