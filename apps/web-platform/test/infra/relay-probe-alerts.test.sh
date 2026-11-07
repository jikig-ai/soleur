#!/usr/bin/env bash
#
# Drift guard for the session-relay probe Better Stack Logs alerts (#12167, epic #8211;
# apps/web-platform/infra/betterstack-logs-alerts.tf):
#   logtail_exploration_alert.relay_listener_down      soleur-relay-listener-down-prd
#   logtail_exploration_alert.relay_probe_silent       soleur-relay-probe-silent-prd
#   logtail_exploration_alert.relay_peer_probe_failed  soleur-relay-peer-probe-failed-prd
#
# WHAT THE ALERTS ARE FOR. The relay reports its own bind: server/proxy-listener-status.ts logs ONE warn-level pino line per
# minute per web host, `relay_probe proxy_state=<listening|disabled|no_bind|no_allowlist|error> addr= port= workspaces_populated=`
# (an app-container row: raw.CONTAINER_NAME = soleur-web-platform, the pino fields nested under raw.message, the sentence in
# raw.message.msg). ci-deploy.sh `relay_peer_probe` journals `relay_peer_probe peer=<ip> result=<ok|refused|timeout|tls|denied>`
# (SYSLOG_IDENTIFIER=ci-deploy) per peer at app deploy time. Three alerts, one per question:
#   * relay_listener_down     - is a relay NOT bound for about 5 minutes (any state but `listening`, either host)?
#   * relay_probe_silent      - did a roster host stop reporting relay_probe for 10 minutes (the host-distinct missing-host
#                               count, egress_gw_probe_silent's shape, ADR-218's host-mask amendment)?
#   * relay_peer_probe_failed - did a deploy-time peer dial come back refused|timeout|tls|denied (first occurrence pages)?
#
# WHAT THIS FILE PROTECTS:
#   * the needles are READ FROM THE EMITTERS (the formatRelayProbeLine template and `listening` state in the TypeScript module,
#     the `logger` line and the result enum in ci-deploy.sh's relay_peer_probe), never retyped, so a reworded line reds here
#     instead of silently disarming an alert;
#   * each flattened predicate is compared WHOLE against a canon built from those needles (so a decoy, an extra OR, a dropped
#     negation or a stray `ok`/`skipped=` needle reds);
#   * the paging semantics, the email-only channels, the free/paid escalation ternary and the runbook anchor;
#   * both -target= lines per resource in the MAIN plan of apply-web-platform-infra.yml (terraform-target-parity checks
#     terraform_data only; betterstack-alert-structure.test.sh is the census, this guard is the per-alert pin);
#   * the standing-alarms rows in the runbook and the one plain `bash <path>` registration step in infra-validation.yml.
#
# WHAT IT DOES NOT PROVE: that a real relay_probe row has the assumed nested shape (the first live row is the positive control,
# the runbook carries the query), or that the evaluator delivers a value for the silence shape (egress_gw_probe_silent's
# open question, #12190). It compares values one diff can edit together: consistency, not integrity.
#
# Mutation rows live at the bottom: each COPIES the sources into a scratch dir, mutates the COPY, re-runs this guard against
# it through the RPA_GUARD_* overrides and requires rc 1 with the named fragment. No tracked file is written.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
TF="${RPA_GUARD_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${RPA_GUARD_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"
TS="${RPA_GUARD_TS:-$REPO/apps/web-platform/server/proxy-listener-status.ts}"
CI="${RPA_GUARD_CI:-$REPO/apps/web-platform/infra/ci-deploy.sh}"
RB="${RPA_GUARD_RB:-$REPO/knowledge-base/engineering/operations/runbooks/betterstack-log-query.md}"
IV="${RPA_GUARD_IV:-$REPO/.github/workflows/infra-validation.yml}"
GUARD_PATH="apps/web-platform/test/infra/relay-probe-alerts.test.sh"

pass=0; fail=0; FAILED=()
ok() { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }

# INSTRUMENT SELF-TEST: both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

command -v python3 >/dev/null 2>&1 || { printf '[FATAL] python3 missing: the mutation battery needs it\n' >&2; exit 2; }
for f in "$TF" "$WF" "$TS" "$CI" "$RB" "$IV"; do
  case "$f" in /*) : ;; *) printf '[FATAL] fixture path %s is not absolute\n' "$f" >&2; exit 2 ;; esac
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

# ── Extraction helpers ───────────────────────────────────────────────────────────────────────
sql_local() {  # sql_local <local name>: the heredoc body up to its `  SQL` closer, from the first opener line
  awk -v n="$1" '$0 ~ "^[[:space:]]*" n "[[:space:]]*=[[:space:]]*<<-?SQL" {f=1; next} f && /^  SQL$/ {f=0} f' "$TF"
}
flat() { tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'; }
res_block() {  # res_block <type> <name>: one resource block, column-0 header to column-0 closing brace
  awk -v h="resource \"$1\" \"$2\" {" '$0 == h {f=1} f {print} f && /^}/ {exit}' "$TF"
}
param() {  # param <block> <attr> <value-ERE>: whole-line attribute assertion inside a block, exactly once
  [ "$(printf '%s\n' "$1" | grep -cE "^[[:space:]]*$2[[:space:]]*=[[:space:]]*$3[[:space:]]*(#.*)?$")" -eq 1 ]
}

# ── Needles, READ FROM THE EMITTERS ─────────────────────────────────────────────────────────
# Listener: the template inside formatRelayProbeLine, up to the first `${`.
LISTEN_PREFIX="$(sed -nE 's/.*return `(relay_probe proxy_state=)\$\{status\.state\}.*/\1/p' "$TS" | head -n 1)"
# The healthy state is the `listening` member of the ProxyState union.
LISTEN_OK="$(sed -nE 's/^[[:space:]]*\| "(listening)"[[:space:]]*$/\1/p' "$TS" | head -n 1)"
# The line is emitted at warn (the level that reaches Better Stack) from the proxy-listener child logger.
WARN_EMIT="$(grep -cE 'createChildLogger\("proxy-listener"\)\.warn\(' "$TS" || true)"
# Peer: the journal line's literal prefix and the result enum (case labels in relay_peer_probe, minus ok).
PEER_PREFIX="$(sed -nE 's/.*logger -t "\$LOG_TAG" "(relay_peer_probe peer=)\$peer result=\$res".*/\1/p' "$CI" | head -n 1)"
LOG_TAG_VAL="$(sed -nE 's/^(readonly )?LOG_TAG="([^"]+)".*/\2/p' "$CI" | head -n 1)"
PEER_RESULTS="$(awk '/^relay_peer_probe\(\) \{$/ {f=1} f && /^[[:space:]]+[a-z]+\) res=[a-z]+ ;;$/ {sub(/\).*/, "", $1); print $1} f && /^}$/ {exit}' "$CI")"
PEER_BAD="$(grep -vx 'ok' <<<"$PEER_RESULTS")"

[ "$LISTEN_PREFIX" = "relay_probe proxy_state=" ] \
  && ok "emitter: formatRelayProbeLine opens with 'relay_probe proxy_state='" \
  || no "emitter: formatRelayProbeLine template not found or reworded (got '$LISTEN_PREFIX'): the listener and silence alerts read this prefix"
[ "$LISTEN_OK" = "listening" ] \
  && ok "emitter: the healthy ProxyState member is 'listening'" \
  || no "emitter: the ProxyState union has no 'listening' member (got '$LISTEN_OK')"
[ "$WARN_EMIT" -eq 1 ] \
  && ok "emitter: the relay_probe line is logged at warn (the level that ships to Better Stack)" \
  || no "emitter: emitProxyListenerStatusOnce no longer logs through createChildLogger(\"proxy-listener\").warn: a non-warn line never reaches the source"
[ "$PEER_PREFIX" = "relay_peer_probe peer=" ] \
  && ok "emitter: ci-deploy.sh logs 'relay_peer_probe peer=<ip> result=<r>' under \$LOG_TAG" \
  || no "emitter: ci-deploy.sh relay_peer_probe logger line not found or reworded (got '$PEER_PREFIX')"
[ "$LOG_TAG_VAL" = "ci-deploy" ] \
  && ok "emitter: LOG_TAG is ci-deploy (the SYSLOG_IDENTIFIER the peer alert pins)" \
  || no "emitter: LOG_TAG is '$LOG_TAG_VAL', not ci-deploy"
[ "$(sort <<<"$PEER_BAD" | tr '\n' ' ')" = "denied refused timeout tls " ] && grep -qx ok <<<"$PEER_RESULTS" \
  && ok "emitter: relay_peer_probe result enum is ok + {refused, timeout, tls, denied}" \
  || no "emitter: relay_peer_probe result enum changed (got: $(tr '\n' ' ' <<<"$PEER_RESULTS")): update the needles with the enum"

# ── Predicates ──────────────────────────────────────────────────────────────────────────────
WHERE_TIME="FROM {{source}} WHERE time BETWEEN {{start_time}} AND {{end_time}}"
MSG="JSONExtractString(raw, 'message', 'msg')"
CANON_LISTENER="SELECT {{time}} AS time, count(*) AS value $WHERE_TIME AND JSONExtractString(raw, 'CONTAINER_NAME') = 'soleur-web-platform' AND startsWith($MSG, '${LISTEN_PREFIX}') AND NOT startsWith($MSG, '${LISTEN_PREFIX}${LISTEN_OK} ') GROUP BY time"
CANON_SILENT="SELECT toDateTime({{end_time}}) AS time, toInt64(\${length(var.web_hosts)}) - least(toInt64(\${length(var.web_hosts)}), toInt64(uniqExact(JSONExtractString(raw, 'host_name')))) AS value FROM {{source}} WHERE dt BETWEEN {{start_time}} AND {{end_time}} AND JSONExtractString(raw, 'CONTAINER_NAME') = 'soleur-web-platform' AND startsWith($MSG, '${LISTEN_PREFIX}')"
NEEDLES=""
while IFS= read -r r; do [ -n "$r" ] && NEEDLES+="${NEEDLES:+, }' result=$r'"; done <<<"$PEER_BAD"
# The needle list is in the emitter's case order (refused, timeout, tls, denied).
CANON_PEER="SELECT {{time}} AS time, count(*) AS value $WHERE_TIME AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = '${LOG_TAG_VAL}' AND startsWith(JSONExtractString(raw, 'message'), '${PEER_PREFIX}') AND multiSearchAny(JSONExtractString(raw, 'message'), [${NEEDLES}]) GROUP BY time"

for pair in "relay_listener_down_sql:$CANON_LISTENER" "relay_probe_silent_sql:$CANON_SILENT" "relay_peer_probe_failed_sql:$CANON_PEER"; do
  n="${pair%%:*}"; canon="${pair#*:}"
  openers="$(grep -cE "^[[:space:]]*$n[[:space:]]*=[[:space:]]*<<-?SQL" "$TF" || true)"
  [ "$openers" -eq 1 ] && ok "$n: exactly one heredoc opener" || no "$n: $openers heredoc openers (want 1): a decoy copy or a missing local"
  got="$(sql_local "$n" | flat)"
  [ -n "$got" ] && [ "$got" = "$canon" ] \
    && ok "$n: the flattened predicate equals the canon built from the emitter needles" \
    || no "$n: predicate differs from the canon. got: [$got] want: [$canon]"
done
# Over-breadth: the peer predicate must never match result=ok or the skipped= class, by construction.
PEER_SQL="$(sql_local relay_peer_probe_failed_sql | flat)"
case "$PEER_SQL" in
  *"result=ok"*|*"skipped="*) no "relay_peer_probe_failed_sql names result=ok or skipped=: those must never page" ;;
  *) ok "relay_peer_probe_failed_sql names neither result=ok nor skipped= (excluded by construction)" ;;
esac
case "$PEER_SQL" in
  *" LIKE "*|*"%"*) no "relay_peer_probe_failed_sql uses LIKE/wildcards: literal needles only" ;;
  *) ok "relay_peer_probe_failed_sql uses literal needles (no LIKE wildcard)" ;;
esac

# ── Resource blocks ─────────────────────────────────────────────────────────────────────────
MAIN_PLAN="$(awk '/^[[:space:]]*terraform plan -no-color/ {f=1} f {print} f && /^[[:space:]]*rc=/ {exit}' "$WF")"
[ "$(tail -1 <<<"$MAIN_PLAN" | grep -cE '^[[:space:]]*rc=\$\{PIPESTATUS\[0\]\}$')" -eq 1 ] \
  && ok "the MAIN plan slice terminates on the plan step's rc capture" \
  || no "the MAIN plan slice never terminated on the plan step's rc=\${PIPESTATUS[0]} capture"

check_pair() {  # check_pair <name> <alert-name> <sql-local> <check> <query> <value> <recovery> <runbook-local>
  local n="$1" an="$2" sl="$3" ck="$4" qp="$5" val="$6" rec="$7" rbl="$8" a e
  a="$(res_block logtail_exploration_alert "$n")"; e="$(res_block logtail_exploration "$n")"
  if [ -z "$a" ] || [ -z "$e" ]; then no "$n: alert or exploration block missing"; return; fi
  ok "$n: alert and exploration blocks exist"
  param "$e" name "\"$an\"" && param "$a" name "\"$an\"" \
    && ok "$n: both resources are named $an" || no "$n: resource name is not $an"
  param "$e" sql_query "replace\(trimspace\(local\.$sl\), \"/\\\\\\\\s\+/\", \" \"\)" \
    && ok "$n: the exploration reads local.$sl through the single-line collapse" \
    || no "$n: the exploration sql_query is not the collapsed local.$sl"
  [ "$(printf '%s\n' "$e" | grep -cF 'values        = [local.vector_prd_source_id]')" -eq 1 ] \
    && ok "$n: the exploration source is the pinned local.vector_prd_source_id" || no "$n: exploration source not pinned to local.vector_prd_source_id"
  param "$a" exploration_id "logtail_exploration\.$n\.id" \
    && ok "$n: the alert is bound to its own exploration" || no "$n: the alert's exploration_id is not logtail_exploration.$n.id"
  param "$a" alert_type '"threshold"' && param "$a" operator '"higher_than"' && param "$a" value "$val" \
    && param "$a" check_period "$ck" && param "$a" query_period "$qp" && param "$a" confirmation_period 0 \
    && param "$a" recovery_period "$rec" && param "$a" on_missing_data '"treat_as_zero"' \
    && ok "$n: paging semantics (higher_than $val, check $ck, query $qp, recovery $rec, treat_as_zero)" \
    || no "$n: the paging semantics are not (higher_than $val, check $ck, query $qp, confirmation 0, recovery $rec, treat_as_zero)"
  param "$a" paused false && ok "$n: declared armed (paused = false)" || no "$n: paused is not the literal false"
  param "$a" email true && param "$a" push false && param "$a" call false && param "$a" sms false && param "$a" critical_alert false \
    && ok "$n: email-only channels, critical_alert false" || no "$n: channels are not email-only with critical_alert false"
  [ "$(printf '%s\n' "$a" | grep -cF 'policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null')" -eq 1 ] \
    && [ "$(printf '%s\n' "$a" | grep -cF 'team_name = var.betterstack_paid_tier ? null : "Your team"')" -eq 1 ] \
    && ok "$n: the free/paid escalation ternary" || no "$n: escalation_target is not the free/paid ternary"
  [ "$(printf '%s\n' "$a" | grep -cF "Runbook: \${local.$rbl}")" -eq 1 ] && param "$a" runbook "local\.$rbl" \
    && ok "$n: incident_cause and metadata carry the runbook URL local" || no "$n: runbook URL not wired in incident_cause + metadata"
  [ "$(grep -cF -- "              -target=logtail_exploration.$n \\" <<<"$MAIN_PLAN")" -eq 1 ] \
    && [ "$(grep -cF -- "              -target=logtail_exploration_alert.$n \\" <<<"$MAIN_PLAN")" -eq 1 ] \
    && ok "$n: both -target= lines are in the MAIN plan" || no "$n: one or both -target= lines are missing from the MAIN plan"
}
check_pair relay_listener_down soleur-relay-listener-down-prd relay_listener_down_sql 60 300 3 600 relay_probe_runbook_url
check_pair relay_probe_silent soleur-relay-probe-silent-prd relay_probe_silent_sql 300 600 0 600 relay_probe_runbook_url
check_pair relay_peer_probe_failed soleur-relay-peer-probe-failed-prd relay_peer_probe_failed_sql 60 300 0 600 relay_probe_runbook_url

RUNBOOK_URL_LINE="$(grep -E '^[[:space:]]*relay_probe_runbook_url[[:space:]]*=' "$TF" | head -n 1)"
ANCHOR="$(sed -nE 's/.*betterstack-log-query\.md#([a-z0-9-]+)".*/\1/p' <<<"$RUNBOOK_URL_LINE")"
[ -n "$ANCHOR" ] && ok "relay_probe_runbook_url points at betterstack-log-query.md#$ANCHOR" || no "relay_probe_runbook_url is missing or does not point at betterstack-log-query.md#<anchor>"
slug_hit=0
while IFS= read -r h; do
  s="$(printf '%s' "${h#\#\# }" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9 -]//g; s/ /-/g')"
  [ -n "$ANCHOR" ] && [ "$s" = "$ANCHOR" ] && slug_hit=1
done < <(grep -E '^## ' "$RB")
[ "$slug_hit" -eq 1 ] && ok "the runbook anchor resolves to a real '## ' heading" || no "the runbook anchor '$ANCHOR' matches no '## ' heading in betterstack-log-query.md"
for n in relay_listener_down relay_probe_silent relay_peer_probe_failed; do
  [ "$(grep -cF "logtail_exploration_alert.$n" "$RB")" -ge 1 ] \
    && ok "runbook: standing-alarms row for $n" || no "runbook: no standing-alarms row for logtail_exploration_alert.$n"
done

# ── CI registration: exactly one plain `bash <path>` step ───────────────────────────────────
[ "$(grep -cE "^[[:space:]]+run:[[:space:]]+bash[[:space:]]+$GUARD_PATH[[:space:]]*$" "$IV")" -eq 1 ] \
  && [ "$(grep -v '^[[:space:]]*#' "$IV" | grep -cF "$GUARD_PATH")" -eq 1 ] \
  && ok "infra-validation.yml registers this guard exactly once as a plain 'bash <path>' step" \
  || no "infra-validation.yml: this guard is unregistered, double-registered or not a plain 'bash <path>' run line"

# ── Mutation battery ────────────────────────────────────────────────────────────────────────
mutate() {  # mutate <red|green> <label> <VAR> <python body> [fragment]
  local want="$1" label="$2" var="$3" body="$4" frag="${5:-}" d out rc v
  d="$(mktemp -d)" || { no "mutation '$label': mktemp failed"; return; }
  for v in TF WF TS CI RB IV; do cp "${!v}" "$d/$v"; done
  MUT_BODY="$body" python3 -c '
import os, sys
p = sys.argv[1]
s = open(p).read()
exec(os.environ["MUT_BODY"])
open(p, "w").write(s)' "$d/$var" || { no "mutation '$label': the python body failed (anchor drifted?)"; rm -rf "$d"; return; }
  out="$(MUT_SKIP=1 RPA_GUARD_TF="$d/TF" RPA_GUARD_WF="$d/WF" RPA_GUARD_TS="$d/TS" RPA_GUARD_CI="$d/CI" RPA_GUARD_RB="$d/RB" RPA_GUARD_IV="$d/IV" bash "$SELF" 2>&1)"; rc=$?
  rm -rf "$d"
  if [ "$want" = "red" ]; then
    if [ "$rc" -eq 1 ] && grep -qF -- "$frag" <<<"$out"; then ok "mutation caught: $label"
    else no "mutation NOT caught (rc=$rc, want rc 1 with '$frag'): $label"; fi
  else
    if [ "$rc" -eq 0 ]; then ok "must-pass mutation stays green: $label"
    else no "must-pass mutation went red (rc=$rc): $label"; fi
  fi
}

if [ -z "${MUT_SKIP:-}" ]; then
  mutate red "listener predicate loses its NOT-listening negation" TF \
    'old = "      AND NOT startsWith(JSONExtractString(raw, \x27message\x27, \x27msg\x27), \x27relay_probe proxy_state=listening \x27)\n"
assert s.count(old) == 1
s = s.replace(old, "")' "relay_listener_down_sql: predicate differs"
  mutate red "listener predicate pins a host_name (the other host would go unwatched)" TF \
    'old = "      AND NOT startsWith(JSONExtractString(raw, \x27message\x27, \x27msg\x27), \x27relay_probe proxy_state=listening \x27)\n"
assert s.count(old) == 1
s = s.replace(old, old + "      AND JSONExtractString(raw, \x27host_name\x27) = \x27soleur-web-2\x27\n")' "relay_listener_down_sql: predicate differs"
  mutate red "the emitter line is reworded (proxy_state -> relay_state)" TS \
    'old = "return `relay_probe proxy_state="
assert s.count(old) == 1
s = s.replace(old, "return `relay_probe relay_state=")' "formatRelayProbeLine template not found or reworded"
  mutate red "the emitter drops to info level" TS \
    'old = "createChildLogger(\"proxy-listener\").warn("
assert s.count(old) == 1
s = s.replace(old, "createChildLogger(\"proxy-listener\").info(")' "no longer logs through createChildLogger"
  mutate red "the peer probe gains a new result the alert does not know" CI \
    'old = "      denied) res=denied ;;\n"
assert s.count(old) == 1
s = s.replace(old, old + "      reset) res=reset ;;\n")' "relay_peer_probe result enum changed"
  mutate red "the peer needle set gains result=ok (a healthy peer would page)" TF \
    'old = "\x27 result=denied\x27]"
assert s.count(old) == 1
s = s.replace(old, "\x27 result=denied\x27, \x27 result=ok\x27]")' "names result=ok or skipped="
  mutate red "the peer predicate drops the SYSLOG_IDENTIFIER pin" TF \
    'old = "      AND JSONExtractString(raw, \x27SYSLOG_IDENTIFIER\x27) = \x27ci-deploy\x27\n      AND startsWith(JSONExtractString(raw, \x27message\x27), \x27relay_peer_probe peer=\x27)\n"
assert s.count(old) == 1
s = s.replace(old, "      AND startsWith(JSONExtractString(raw, \x27message\x27), \x27relay_peer_probe peer=\x27)\n")' "relay_peer_probe_failed_sql: predicate differs"
  mutate red "the silence alert flips to lower_than (the evaluator-blind shape #12180 left)" TF \
    'i = s.index("resource \"logtail_exploration_alert\" \"relay_probe_silent\" {")
j = s.index("operator            = \"higher_than\"", i)
s = s[:j] + "operator            = \"lower_than\"" + s[j + len("operator            = \"higher_than\""):]' "paging semantics"
  mutate red "the silence count regresses from distinct hosts to a row count (the host-mask defect)" TF \
    'old = "toInt64(uniqExact(JSONExtractString(raw, \x27host_name\x27)))"
assert s.count(old) == 1
s = s.replace(old, "toInt64(count(*))")' "relay_probe_silent_sql: predicate differs"
  mutate red "the listener alert fires on a single non-listening row (sustained window lost)" TF \
    'i = s.index("resource \"logtail_exploration_alert\" \"relay_listener_down\" {")
j = s.index("value               = 3", i)
s = s[:j] + "value               = 0" + s[j + len("value               = 3"):]' "paging semantics"
  mutate red "the peer alert is paused" TF \
    'i = s.index("resource \"logtail_exploration_alert\" \"relay_peer_probe_failed\" {")
j = s.index("paused = false", i)
s = s[:j] + "paused = true" + s[j + len("paused = false"):]' "declared armed"
  mutate red "the listener alert goes loud (push enabled) without a ruling" TF \
    'i = s.index("resource \"logtail_exploration_alert\" \"relay_listener_down\" {")
j = s.index("push           = false", i)
s = s[:j] + "push           = true" + s[j + len("push           = false"):]' "email-only channels"
  mutate red "the silence alert's alert -target= line is dropped" WF \
    'old = "              -target=logtail_exploration_alert.relay_probe_silent \\\n"
assert s.count(old) == 1
s = s.replace(old, "")' "relay_probe_silent: one or both -target= lines are missing"
  mutate red "the peer exploration -target= line is dropped" WF \
    'old = "              -target=logtail_exploration.relay_peer_probe_failed \\\n"
assert s.count(old) == 1
s = s.replace(old, "")' "relay_peer_probe_failed: one or both -target= lines are missing"
  mutate red "the runbook anchor heading is renamed" RB \
    'old = "## Session relay probe alerts (#12167)"
assert s.count(old) == 1
s = s.replace(old, "## Relay stuff")' "matches no '## ' heading"
  mutate red "the guard's CI step is dropped from infra-validation.yml" IV \
    'old = "        run: bash apps/web-platform/test/infra/relay-probe-alerts.test.sh\n"
assert s.count(old) == 1
s = s.replace(old, "")' "unregistered, double-registered"
  mutate green "a comment-only edit to the .tf" TF 's = s + "\n# control comment\n"'
  mutate green "the listener conjuncts are re-indented (whitespace inside the heredoc is legal)" TF \
    'i = s.index("relay_listener_down_sql = <<-SQL"); j = s.index("\n  SQL\n", i)
s = s[:i] + s[i:j].replace("\n      AND ", "\n          AND ") + s[j:]'
fi

# ── Assertion floor + ledger ────────────────────────────────────────────────────────────────
PRESENCE_ROWS=54
MUT_ROWS=18
_eff=${MUT_SKIP:+0}
_eff=${_eff:-$MUT_ROWS}
_floor=$((PRESENCE_ROWS + _eff))
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then
  printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2
  exit 1
fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then
  printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2
  exit 1
fi
printf '\n=== relay-probe-alerts: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
