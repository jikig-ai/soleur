#!/usr/bin/env bash
#
# Drift guard for the #10321 credential-shape Better Stack Logs alert
# (apps/web-platform/infra/betterstack-logs-alerts.tf, Guard 1 of
# knowledge-base/project/plans/2026-10-15-fix-dormant-probe-ledger-10321-10136-plan.md).
#
# WHAT THE ALERT IS FOR. zot-log-channel-7440.sh's exit-1 arm was the only automated
# reader of what the registry shipper's redact() emits on source 2457081 — it went
# dormant when tracker #7455 closed (the sweeper's read set is open issues plus a
# 14-day closed lookback). This alert is the standing vehicle for the same three
# shapes: (a) an Authorization value that is neither the `***` mask nor REDACTED,
# (b) a Doppler token prefix dp.(pt|st|sa|ct). with a >=16 non-separator run,
# (c) a bcrypt $2[aby]$ hash. One matching row pages (value = 0, higher_than).
#
# WHAT THIS FILE PROTECTS, row by row:
#   * The predicate local exists and carries the SOLEUR_ZOT_LOG envelope anchor —
#     an extractor that finds nothing makes every row below vacuous.
#   * The whole predicate is byte-exact after whitespace collapse (SELECT,
#     aggregate, all three disjuncts, GROUP BY) — arithmetic on a comparison or an
#     extra disjunct keeps every per-arm substring present.
#   * Per-arm: the Authorization arm evaluates EVERY occurrence (extractAll +
#     arrayExists) so a leading decoy cannot mask a real credential; the mask
#     exemption is `(\\*\\*\\*|REDACTED)` — exactly the probe's 3-or-more-asterisk
#     mask plus the shipper's marker; `Authorization:[]` empty is benign while
#     `Authorization:[ ` fails loud (the probe's malformed-unmasked arm); the
#     Doppler arm strips `._-` separators before the >=16 substance floor; the
#     bcrypt arm is `$2[aby]$<2d>$`.
#   * Resource wiring: values = [local.vector_prd_source_id], exploration_id link,
#     paused = false, value = 0 + higher_than (one row is an incident — unlike the
#     store_not_luks sibling there is no transient benign row), 300/900 windows,
#     treat_as_zero, the free/paid-tier escalation ternary, a clickable runbook.
#   * Both -target= lines in the push-triggered apply job (#5566: untargeted is
#     never applied).
#
# Mutation rows mutate COPIES in a temp dir re-run through REGCREDSHAPE_TF /
# REGCREDSHAPE_WF — the tracked files are never written.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="${REGCREDSHAPE_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${REGCREDSHAPE_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"

pass=0; fail=0; FAILED=()
ok() { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

# INSTRUMENT SELF-TEST — both helpers must move their own counter first.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

command -v python3 >/dev/null 2>&1 || { printf '[FATAL] python3 missing\n' >&2; exit 2; }
for f in "$TF" "$WF"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

LOCAL_SQL="$(awk '/registry_zot_log_credential_shape_sql = <<-SQL/{f=1;next} f&&/^  SQL$/{f=0} f' "$TF")"
FLAT="$(printf '%s' "$LOCAL_SQL" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')"

if [ -n "$FLAT" ] && grep -qF "'SOLEUR_ZOT_LOG '" <<<"$FLAT"; then
  ok "the predicate local is a heredoc this guard can read, and it carries the SOLEUR_ZOT_LOG anchor"
else
  no "registry_zot_log_credential_shape_sql: heredoc not found or anchorless — every row below would be vacuous"
fi

grep -qF 'sql_query = replace(trimspace(local.registry_zot_log_credential_shape_sql), "/\\s+/", " ")' "$TF" \
  && ok "the exploration carries THIS predicate, collapsed to one line" \
  || no "the exploration does not carry local.registry_zot_log_credential_shape_sql"

_M="JSONExtractString(raw, 'message')"
EXPECTED_FLAT="SELECT {{time}} AS time, count(*) AS value FROM {{source}} WHERE time BETWEEN {{start_time}} AND {{end_time}} AND startsWith(raw, '{\"message\":\"SOLEUR_ZOT_LOG ') AND position($_M, 'SOLEUR_ZOT_LOG ') = 1 AND ( arrayExists( v -> v != 'Authorization:[' AND NOT match(v, '^Authorization:\\\\[(\\\\*\\\\*\\\\*|REDACTED)'), extractAll($_M, 'Authorization:\\\\[[^\\\\]\\\\s]*') ) OR match($_M, 'Authorization:\\\\[ ') OR arrayExists( t -> length(replaceRegexpAll(t, '^dp\\\\.(?:pt|st|sa|ct)\\\\.|[._-]', '')) >= 16, extractAll($_M, 'dp\\\\.(?:pt|st|sa|ct)\\\\.[A-Za-z0-9._-]+') ) OR match($_M, '\\\\\$2[aby]\\\\\$[0-9][0-9]\\\\\$') ) GROUP BY time"
[ "$FLAT" = "$EXPECTED_FLAT" ] \
  && ok "the whole predicate is byte-exact (SELECT, aggregate, all three disjuncts, GROUP BY)" \
  || no "the predicate drifted from the pinned text — diff FLAT against EXPECTED_FLAT"

# Column form: every row read goes through JSONExtractString(raw, 'message'), never a bare msg.
n_col="$(printf '%s' "$FLAT" | grep -oF "JSONExtractString(raw, 'message')" | wc -l | tr -d ' ')"
if [ "$n_col" -ge 5 ] && ! grep -qE '\bmsg\b' <<<"$FLAT"; then
  ok "all ${n_col} row reads use JSONExtractString(raw, 'message'); no bare msg column"
else
  no "column form drifted: ${n_col} JSONExtractString(raw, 'message') reads (want >=5) or a bare msg"
fi

grep -qF "AND startsWith(raw, '{\"message\":\"SOLEUR_ZOT_LOG ')" <<<"$FLAT" \
  && ok "envelope-anchored to the direct-POST shape (a journald row quoting the marker cannot match)" \
  || no "the startsWith(raw, '{\"message\":\"SOLEUR_ZOT_LOG ') envelope conjunct is missing"

grep -qF "AND position(JSONExtractString(raw, 'message'), 'SOLEUR_ZOT_LOG ') = 1" <<<"$FLAT" \
  && ok "the marker is anchored at position 1 of the message, with its trailing space" \
  || no "the message-level marker anchor is missing or unanchored"

# Arm (a): per-occurrence Authorization values through extractAll + arrayExists, with
# the exact mask exemption and the empty-vs-malformed split.
grep -qF "extractAll(JSONExtractString(raw, 'message'), 'Authorization:\\\\[[^\\\\]\\\\s]*')" <<<"$FLAT" \
  && grep -qF "arrayExists( v -> v != 'Authorization:[' AND NOT match(v, '^Authorization:\\\\[(\\\\*\\\\*\\\\*|REDACTED)')" <<<"$FLAT" \
  && ok "arm (a) walks EVERY Authorization:[ value (no decoy masking); exemption is exactly (***|REDACTED)" \
  || no "arm (a) lost the per-occurrence extractAll/arrayExists shape or the mask exemption"
grep -qF "OR match(JSONExtractString(raw, 'message'), 'Authorization:\\\\[ ')" <<<"$FLAT" \
  && ok "arm (a') flags 'Authorization:[ ' — a value empty after the space cut fails loud" \
  || no "the malformed-unmasked conjunct (Authorization:[ ) is missing"

# Arm (b): Doppler prefix + >=16 non-separator substance.
grep -qF "extractAll(JSONExtractString(raw, 'message'), 'dp\\\\.(?:pt|st|sa|ct)\\\\.[A-Za-z0-9._-]+')" <<<"$FLAT" \
  && grep -qF "replaceRegexpAll(t, '^dp\\\\.(?:pt|st|sa|ct)\\\\.|[._-]', '')) >= 16" <<<"$FLAT" \
  && ok "arm (b) requires >=16 non-separator chars after dp.(pt|st|sa|ct). — padding cannot fire it" \
  || no "arm (b) lost the prefix extract or the substance floor"

# Arm (c): bcrypt.
grep -qF "match(JSONExtractString(raw, 'message'), '\\\\\$2[aby]\\\\\$[0-9][0-9]\\\\\$')" <<<"$FLAT" \
  && ok "arm (c) is the bcrypt \$2[aby]\$<2d>\$ prefix" \
  || no "arm (c) bcrypt disjunct is missing or deformed"

# Resource-block scoped reads.
EXP_BLOCK="$(awk '/^resource "logtail_exploration" "registry_zot_log_credential_shape"/,/^}/' "$TF")"
ALR_BLOCK="$(awk '/^resource "logtail_exploration_alert" "registry_zot_log_credential_shape"/,/^}/' "$TF")"

grep -qF 'values        = [local.vector_prd_source_id]' <<<"$EXP_BLOCK" \
  && ok "the exploration reads local.vector_prd_source_id (source 2457081)" \
  || no "the exploration's source variable is not local.vector_prd_source_id"

grep -qF 'exploration_id = logtail_exploration.registry_zot_log_credential_shape.id' <<<"$ALR_BLOCK" \
  && ok "the alert is attached to this exploration" \
  || no "the alert's exploration_id does not reference this exploration"

grep -qxF '  paused = false' <<<"$ALR_BLOCK" \
  && ok "paused = false (it arms at merge)" \
  || no "the alert is not 'paused = false' — it would exist and never page"

alr_kv() { printf '%s' "$ALR_BLOCK" | grep -E "^  $1 +=" | head -1 | sed -E 's/^[^=]+= *//'; }
[ "$(alr_kv value)" = "0" ] && [ "$(alr_kv operator)" = '"higher_than"' ] \
  && ok "value = 0 with operator higher_than: ONE credential-shaped row is a page" \
  || no "threshold drifted: value=$(alr_kv value) operator=$(alr_kv operator) — one-row-is-an-incident semantics lost"
[ "$(alr_kv check_period)" = "300" ] \
  && ok "check_period = 300" \
  || no "check_period is $(alr_kv check_period), want 300"
[ "$(alr_kv query_period)" = "900" ] \
  && ok "query_period = 900" \
  || no "query_period is $(alr_kv query_period), want 900"
[ "$(alr_kv on_missing_data)" = '"treat_as_zero"' ] \
  && ok "treat_as_zero, so an open incident can observe recovery" \
  || no "on_missing_data is $(alr_kv on_missing_data), want \"treat_as_zero\""

grep -qF 'policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null' <<<"$ALR_BLOCK" \
  && grep -qF 'team_name = var.betterstack_paid_tier ? null : "Your team"' <<<"$ALR_BLOCK" \
  && ok "escalation_target is the siblings' free/paid-tier ternary" \
  || no "escalation_target drifted from the siblings' routing"

grep -qF 'registry_zot_log_credential_shape_runbook_url = "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/' "$TF" \
  && grep -qF '${local.registry_zot_log_credential_shape_runbook_url}' <<<"$ALR_BLOCK" \
  && ok "the incident carries a clickable runbook URL" \
  || no "no clickable runbook URL on the incident"

[ -r "$REPO/knowledge-base/engineering/operations/runbooks/registry-zot-credential-shape-10321.md" ] \
  && ok "the runbook the incident links to exists in the repo" \
  || no "runbook registry-zot-credential-shape-10321.md missing — the incident link would 404"

# Both -target lines, INSIDE the push-triggered `apply:` job.
APPLY_JOB="$(awk '/^  apply:$/{f=1; print; next} f && /^  [A-Za-z0-9_-]+:$/{f=0} f' "$WF")"
grep -qxF '              -target=logtail_exploration.registry_zot_log_credential_shape \' <<<"$APPLY_JOB" \
  && grep -qxF '              -target=logtail_exploration_alert.registry_zot_log_credential_shape \' <<<"$APPLY_JOB" \
  && ok "both resources are in the push-triggered apply job's -target allowlist (#5566)" \
  || no "one or both -target= lines are missing — the alert would never exist"

# ── Mutation rows: each must make the rows above RED (must-pass stays GREEN) ────
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t regcredshape.XXXXXX)"; trap 'rm -rf "$MUT_DIR"' EXIT
  assert_fixture_dir "$MUT_DIR"
  SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
  # mutate <expect red|green> <label> <tf|wf> <python-body-on-s>
  mutate() {
    local expect="$1" label="$2" which="$3" prog="$4" rc=0 src
    assert_fixture_dir "$MUT_DIR"
    cp "$TF" "$MUT_DIR/alerts.tf"; cp "$WF" "$MUT_DIR/apply.yml"
    if [ "$which" = tf ]; then src="$MUT_DIR/alerts.tf"; else src="$MUT_DIR/apply.yml"; fi
    python3 - "$src" <<PY || { no "mutation '$label' did not land (anchor drifted)"; return 0; }
import sys
p = sys.argv[1]
s = open(p).read()
$prog
open(p, 'w').write(s)
PY
    REGCREDSHAPE_TF="$MUT_DIR/alerts.tf" REGCREDSHAPE_WF="$MUT_DIR/apply.yml" MUT_SKIP=1 bash "$SELF" >/dev/null 2>&1 || rc=$?
    if [ "$expect" = red ]; then
      [ "$rc" -ne 0 ] && ok "mutation RED: $label" || no "mutation SURVIVED: $label — the row above pins nothing"
    else
      [ "$rc" -eq 0 ] && ok "must-pass GREEN: $label" || no "must-pass went RED: $label — the guard is reflow-fragile"
    fi
  }
  mutate red "M1 delete the bcrypt disjunct" tf \
    'i = s.index("registry_zot_log_credential_shape_sql = <<-SQL"); j = s.index("  SQL\n", i)
blk = s[i:j]
old = "\n        OR match(JSONExtractString(raw, \x27message\x27), \x27\\\\$2[aby]\\\\$[0-9][0-9]\\\\$\x27)"
assert blk.count(old) == 1
s = s[:i] + blk.replace(old, "") + s[j:]'
  mutate red "M2 drop the mask exemption" tf \
    'old = " AND NOT match(v, \x27^Authorization:\\\\[(\\\\*\\\\*\\\\*|REDACTED)\x27)"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate red "M3 remove the envelope anchor" tf \
    'i = s.index("registry_zot_log_credential_shape_sql = <<-SQL"); j = s.index("  SQL\n", i)
blk = s[i:j]
old = "      AND startsWith(raw, \x27{\"message\":\"SOLEUR_ZOT_LOG \x27)\n"
assert blk.count(old) == 1
s = s[:i] + blk.replace(old, "") + s[j:]'
  mutate red "M4 drop the exploration_alert -target= line" wf \
    'old = "              -target=logtail_exploration_alert.registry_zot_log_credential_shape \\\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate red "M5 the Doppler substance floor is zeroed" tf \
    'old = ")) >= 16"
assert s.count(old) == 1
s = s.replace(old, ")) >= 0")'
  mutate red "M6 value = 0 becomes value = 1 (a single leak no longer pages)" tf \
    'i = s.index("resource \"logtail_exploration_alert\" \"registry_zot_log_credential_shape\"")
j = s.index("\n}\n", i)
head, block, tail = s[:i], s[i:j], s[j:]
assert block.count("  value               = 0\n") == 1
s = head + block.replace("  value               = 0\n", "  value               = 1\n") + tail'
  mutate green "M7 whitespace reflow of the heredoc" tf \
    'old = "\n        OR match(JSONExtractString(raw, \x27message\x27), \x27Authorization:\\\\[ \x27)"
assert s.count(old) == 1
s = s.replace(old, " OR\n          match(JSONExtractString(raw, \x27message\x27), \x27Authorization:\\\\[ \x27)")'
fi

_floor=24
[ -n "${MUT_SKIP:-}" ] && _floor=17
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 1; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 1; fi
printf '\n=== registry-zot-credential-shape-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
