#!/usr/bin/env bash
#
# Drift guard for the "#8408 (a) registry store is not on LUKS, or its escrow is not proven"
# Better Stack Logs alert (apps/web-platform/infra/betterstack-logs-alerts.tf, Guard 3 of
# knowledge-base/project/plans/2026-09-21-fix-zot-queue-dead-ghcr-credential-plan.md).
#
# WHAT THE ALERT IS FOR. The registry host's */5 SOLEUR_ZOT_DISK heartbeat carries, in its TRUSTED
# HEAD (everything before ` zot_last_err=`), `store_luks=<yes|…>` and `store_escrow=<token>`. The
# rule pages when the head lacks `store_luks=yes ` (arm A) or carries a `store_escrow=` that is not
# `ok` (arm B). Nothing else notices either: zot serves happily from plaintext, and a dead escrow
# re-test only matters on the next reboot.
#
# WHAT THIS FILE PROTECTS, and why each row exists rather than "the SQL looks right":
#   * Each arm is HEAD-SCOPED by exactly one comparison against ' zot_last_err='. The tail is zot's
#     own log text; without the cut, a crafted tail could satisfy (A) or suppress (B). Asserted PER
#     ARM, because dropping it from one arm leaves the other still carrying the literal.
#   * `'store_luks=yes '` keeps its TRAILING SPACE, the field-terminator (`yes` is a prefix of
#     `yesterday`-shaped junk; the emitter always writes a field after this one).
#   * Arm B's quiet state is the literal `'store_escrow=ok '`. Narrowing it to `store_escrow=fail`
#     leaves stale / none / indeterminate silent — the way a dead escrow job rots.
#   * The row text is read as `JSONExtractString(raw, 'message')`, the sibling's column form; there
#     is no bare `msg` column, and an unknown column makes the whole rule error rather than page.
#   * The envelope conjunct `startsWith(raw, '{"message":"SOLEUR_ZOT_DISK ')` is the direct-POST
#     shape; a journald row QUOTING the marker cannot match it.
#   * `paused = false`, `query_period = 900`, `value = 1` + `higher_than` (>= 2 rows per 900 s
#     bucket), and both resources in the push-triggered `apply` job's `-target=` allowlist (#5566:
#     an untargeted resource is never applied and never exists).
#   The live-probe counts in the .tf comment are the ENGINE-level evidence; this file is structural.
#
# Mutation rows live at the bottom. Unlike the inngest sibling, they mutate COPIES in a temp dir
# and re-run this file against them through REGSTORE_TF / REGSTORE_WF — the tracked files are never
# written, so a concurrent edit to them cannot be clobbered by a restore.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../../../.." && pwd)"
TF="${REGSTORE_TF:-$REPO/apps/web-platform/infra/betterstack-logs-alerts.tf}"
WF="${REGSTORE_WF:-$REPO/.github/workflows/apply-web-platform-infra.yml}"

pass=0; fail=0; FAILED=()
ok() { pass=$((pass + 1)); printf '[ok] %s\n' "$1"; }
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }

# P1b (#7708) — byte-identical to every other tracked copy; the P1a suite pins that.
# `$(cd X && pwd)` prints an absolute path but yields EMPTY when the cd fails, which would root
# $TF at `/` — and mutate_red() below writes to $TF on every row.
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

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

command -v python3 >/dev/null 2>&1 || { printf '[FATAL] python3 missing — the arm parser needs it\n' >&2; exit 2; }
for f in "$TF" "$WF"; do
  [ -r "$f" ] || { printf '[FATAL] unreadable: %s\n' "$f" >&2; exit 2; }
done

# The predicate as the provider receives it: the heredoc, whitespace-collapsed exactly as the
# resource site's replace(trimspace(…), "/\\s+/", " ") does. A reflow of the heredoc is invisible.
LOCAL_SQL="$(awk '/registry_store_not_luks_sql = <<-SQL/{f=1;next} f&&/^  SQL$/{f=0} f' "$TF")"
FLAT="$(printf '%s' "$LOCAL_SQL" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')"

# H1: an extractor that finds nothing would make every row below vacuous — so it must find the
# anchor, not merely "something".
if [ -n "$FLAT" ] && grep -qF "'SOLEUR_ZOT_DISK '" <<<"$FLAT"; then
  ok "the predicate local is a heredoc this guard can read, and it carries the SOLEUR_ZOT_DISK anchor"
else
  no "registry_store_not_luks_sql: heredoc not found or anchorless — every row below would be vacuous"
fi

grep -qF 'sql_query = replace(trimspace(local.registry_store_not_luks_sql), "/\\s+/", " ")' "$TF" \
  && ok "the exploration carries THIS predicate, collapsed to one line (the siblings' perpetual-diff rule)" \
  || no "the exploration does not carry local.registry_store_not_luks_sql"

# EXACT PIN. The per-arm rows below say WHY each piece matters; this row says nothing else is
# there. Arithmetic on a comparison (`+ 100000`), a zeroed aggregate (`count(*) * 0`) or an extra
# disjunct all keep every per-arm substring present, and only a whole-predicate pin sees them.
_M="JSONExtractString(raw, 'message')"
EXPECTED_FLAT="SELECT {{time}} AS time, count(*) AS value FROM {{source}} WHERE time BETWEEN {{start_time}} AND {{end_time}} AND startsWith(raw, '{\"message\":\"SOLEUR_ZOT_DISK ') AND position($_M, 'SOLEUR_ZOT_DISK ') = 1 AND ( NOT (position($_M, 'store_luks=yes ') > 0 AND position($_M, 'store_luks=yes ') < position($_M, ' zot_last_err=')) OR (position($_M, 'store_escrow=') > 0 AND position($_M, 'store_escrow=') < position($_M, ' zot_last_err=') AND position($_M, 'store_escrow=ok ') != position($_M, 'store_escrow=') AND position($_M, 'store_escrow=pending ') != position($_M, 'store_escrow=')) ) GROUP BY time"
[ "$FLAT" = "$EXPECTED_FLAT" ] \
  && ok "the whole predicate is byte-exact (SELECT, aggregate, both arms, GROUP BY)" \
  || no "the predicate drifted from the pinned text — diff FLAT against EXPECTED_FLAT"

# Column form. Every position() reads JSONExtractString(raw, 'message'); a bare column is an
# unknown-identifier error at query time, i.e. a rule that never pages.
n_pos="$(printf '%s' "$FLAT" | grep -oF 'position(' | wc -l | tr -d ' ')"
n_col="$(printf '%s' "$FLAT" | grep -oF "position(JSONExtractString(raw, 'message'), " | wc -l | tr -d ' ')"
if [ "$n_pos" -ge 7 ] && [ "$n_pos" -eq "$n_col" ] && ! grep -qE '\bmsg\b' <<<"$FLAT"; then
  ok "all ${n_pos} position() calls read JSONExtractString(raw, 'message'); no bare msg column"
else
  no "column form drifted: ${n_col}/${n_pos} position() calls use JSONExtractString(raw, 'message')"
fi

grep -qF "AND startsWith(raw, '{\"message\":\"SOLEUR_ZOT_DISK ')" <<<"$FLAT" \
  && ok "envelope-anchored to the direct-POST shape (a journald row quoting the marker cannot match)" \
  || no "the startsWith(raw, '{\"message\":\"SOLEUR_ZOT_DISK ') envelope conjunct is missing"

grep -qF "AND position(JSONExtractString(raw, 'message'), 'SOLEUR_ZOT_DISK ') = 1" <<<"$FLAT" \
  && ok "the marker is anchored at position 1 of the message, with its trailing space" \
  || no "the message-level marker anchor is missing or unanchored"

# Per-arm parse. Arm A is the NOT(...) before the one top-level OR; arm B is the rest of the group.
ARMS="$(printf '%s' "$FLAT" | python3 -c '
import re, sys
s = sys.stdin.read()
m = re.search(r"AND \( ?NOT \((.*?)\) ?OR \((.*)\) ?\) GROUP BY time$", s)
if not m:
    sys.exit(1)
print(m.group(1)); print(m.group(2))
')" || ARMS=""
ARM_A="$(printf '%s\n' "$ARMS" | sed -n 1p)"
ARM_B="$(printf '%s\n' "$ARMS" | sed -n 2p)"

if [ -n "$ARM_A" ] && [ -n "$ARM_B" ]; then
  ok "the predicate parses as AND ( NOT (arm A) OR (arm B) )"
else
  no "the predicate no longer has the AND ( NOT (A) OR (B) ) shape — the per-arm rows below are vacuous"
fi

a_cut="$(printf '%s' "$ARM_A" | grep -oF "' zot_last_err='" | wc -l | tr -d ' ')"
b_cut="$(printf '%s' "$ARM_B" | grep -oF "' zot_last_err='" | wc -l | tr -d ' ')"
[ "$a_cut" -eq 1 ] \
  && ok "arm A is head-scoped: exactly one ordering comparison against ' zot_last_err='" \
  || no "arm A carries ${a_cut} ' zot_last_err=' references (want 1) — tail text could satisfy it"
[ "$b_cut" -eq 1 ] \
  && ok "arm B is head-scoped: exactly one ordering comparison against ' zot_last_err='" \
  || no "arm B carries ${b_cut} ' zot_last_err=' references (want 1) — tail text could suppress it"

grep -qF "position(JSONExtractString(raw, 'message'), 'store_luks=yes ') < position(JSONExtractString(raw, 'message'), ' zot_last_err=')" <<<"$ARM_A" \
  && grep -qF "position(JSONExtractString(raw, 'message'), 'store_luks=yes ') > 0" <<<"$ARM_A" \
  && ok "arm A is the negation of 'store_luks=yes ' (WITH its trailing space) found before the tail" \
  || no "arm A lost the exact 'store_luks=yes ' literal or its before-the-tail ordering"

grep -qF "position(JSONExtractString(raw, 'message'), 'store_escrow=') > 0" <<<"$ARM_B" \
  && grep -qF "position(JSONExtractString(raw, 'message'), 'store_escrow=') < position(JSONExtractString(raw, 'message'), ' zot_last_err=')" <<<"$ARM_B" \
  && ok "arm B requires a store_escrow= field in the head (pre-delivery rows cannot fire it)" \
  || no "arm B's store_escrow= presence test, or its before-the-tail ordering, is missing"

grep -qF "position(JSONExtractString(raw, 'message'), 'store_escrow=ok ') != position(JSONExtractString(raw, 'message'), 'store_escrow=')" <<<"$ARM_B" \
  && ok "arm B's only quiet state is 'store_escrow=ok ' at the head field's own position (any other token pages)" \
  || no "arm B no longer negates the exact 'store_escrow=ok ' literal — stale/none/indeterminate would go silent"

grep -qF "position(JSONExtractString(raw, 'message'), 'store_escrow=pending ') != position(JSONExtractString(raw, 'message'), 'store_escrow=')" <<<"$ARM_B" \
  && ok "arm B also exempts 'store_escrow=pending ' (the first-boot window before the deferred run lands)" \
  || no "arm B pages on 'pending' — every registry replace would page for its first 15+ minutes"

# Resource-block scoped reads (awk range from the resource header to its closing brace).
EXP_BLOCK="$(awk '/^resource "logtail_exploration" "registry_store_not_luks"/,/^}/' "$TF")"
ALR_BLOCK="$(awk '/^resource "logtail_exploration_alert" "registry_store_not_luks"/,/^}/' "$TF")"

grep -qF 'values        = [local.vector_prd_source_id]' <<<"$EXP_BLOCK" \
  && ok "the exploration reads local.vector_prd_source_id (the source the heartbeat POSTs to)" \
  || no "the exploration's source variable is not local.vector_prd_source_id"

grep -qF 'exploration_id = logtail_exploration.registry_store_not_luks.id' <<<"$ALR_BLOCK" \
  && ok "the alert is attached to this exploration" \
  || no "the alert's exploration_id does not reference logtail_exploration.registry_store_not_luks"

grep -qxF '  paused = false' <<<"$ALR_BLOCK" \
  && ok "paused = false (the rule is quiet on the live fleet, so it arms at merge)" \
  || no "the alert is not 'paused = false' — it would exist and never page"

alr_kv() { printf '%s' "$ALR_BLOCK" | grep -E "^  $1 +=" | head -1 | sed -E 's/^[^=]+= *//'; }
[ "$(alr_kv query_period)" = "900" ] \
  && ok "query_period = 900 (three */5 heartbeats; the API snaps the bucket to it)" \
  || no "query_period is $(alr_kv query_period), want 900"
[ "$(alr_kv value)" = "1" ] && [ "$(alr_kv operator)" = '"higher_than"' ] \
  && ok "value = 1 with operator higher_than: >= 2 matching rows per bucket, one transient row does not page" \
  || no "threshold drifted: value=$(alr_kv value) operator=$(alr_kv operator)"
[ "$(alr_kv check_period)" = "300" ] \
  && ok "check_period = 300" \
  || no "check_period is $(alr_kv check_period), want 300"
[ "$(alr_kv on_missing_data)" = '"treat_as_zero"' ] \
  && ok "treat_as_zero, so an open incident can observe recovery" \
  || no "on_missing_data is $(alr_kv on_missing_data), want \"treat_as_zero\""

grep -qF 'policy_id = var.betterstack_paid_tier ? tonumber(betteruptime_policy.uptime[0].id) : null' <<<"$ALR_BLOCK" \
  && grep -qF 'team_name = var.betterstack_paid_tier ? null : "Your team"' <<<"$ALR_BLOCK" \
  && ok "escalation_target is the siblings' free/paid-tier ternary" \
  || no "escalation_target drifted from the siblings' routing"

grep -qF 'registry_store_not_luks_runbook_url = "https://github.com/jikig-ai/soleur/blob/main/knowledge-base/' "$TF" \
  && grep -qF '${local.registry_store_not_luks_runbook_url}' <<<"$ALR_BLOCK" \
  && ok "the incident carries a clickable runbook URL" \
  || no "no clickable runbook URL on the incident"

# The engine-level evidence lives in the .tf comment; its absence means the SQL was never run.
grep -qE '^#   \(ii\) +.store_luks=yes . -> .store_luks=nope . +-> [1-9][0-9]*' "$TF" \
  && grep -qE '^#   \(iii\) arm-B presence' "$TF" \
  && ok "the live-probe controls (ii) and (iii) are recorded with a non-zero count" \
  || no "the live-probe positive controls are not recorded in the .tf comment"

# Both -target lines, INSIDE the push-triggered `apply:` job (not a dispatch-only job).
APPLY_JOB="$(awk '/^  apply:$/{f=1; print; next} f && /^  [A-Za-z0-9_-]+:$/{f=0} f' "$WF")"
grep -qxF '              -target=logtail_exploration.registry_store_not_luks \' <<<"$APPLY_JOB" \
  && grep -qxF '              -target=logtail_exploration_alert.registry_store_not_luks \' <<<"$APPLY_JOB" \
  && ok "both resources are in the push-triggered apply job's -target allowlist (#5566)" \
  || no "one or both -target= lines are missing from the apply job — the alert would never exist"

# ── Mutation rows: each must make the rows above RED (H2 must stay GREEN) ─────────────────────
if [ -z "${MUT_SKIP:-}" ]; then
  MUT_DIR="$(mktemp -d -t regstorealert.XXXXXX)"; trap 'rm -rf "$MUT_DIR"' EXIT
  assert_fixture_dir "$MUT_DIR"
  SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
  # mutate <expect red|green> <label> <tf|wf> <python-body-on-s>
  mutate() {
    local expect="$1" label="$2" which="$3" prog="$4" rc=0 src
    assert_fixture_dir "$MUT_DIR"   # P1b: every arm below writes into $MUT_DIR
    cp "$TF" "$MUT_DIR/alerts.tf"; cp "$WF" "$MUT_DIR/apply.yml"
    if [ "$which" = tf ]; then src="$MUT_DIR/alerts.tf"; else src="$MUT_DIR/apply.yml"; fi
    python3 - "$src" <<PY || { no "mutation '$label' did not land (anchor drifted)"; return 0; }
import sys
p = sys.argv[1]
s = open(p).read()
$prog
open(p, 'w').write(s)
PY
    REGSTORE_TF="$MUT_DIR/alerts.tf" REGSTORE_WF="$MUT_DIR/apply.yml" MUT_SKIP=1 bash "$SELF" >/dev/null 2>&1 || rc=$?
    if [ "$expect" = red ]; then
      [ "$rc" -ne 0 ] && ok "mutation RED: $label" || no "mutation SURVIVED: $label — the row above pins nothing"
    else
      [ "$rc" -eq 0 ] && ok "must-pass GREEN: $label" || no "must-pass went RED: $label — the guard is reflow-fragile"
    fi
  }
  Q="JSONExtractString(raw, \\x27message\\x27)"
  mutate red "M1 drop arm A's ordering conjunct against ' zot_last_err='" tf \
    'old = " AND position('"$Q"', \x27store_luks=yes \x27) < position('"$Q"', \x27 zot_last_err=\x27))"
assert s.count(old) == 1
s = s.replace(old, ")")'
  mutate red "M2 paused = true" tf \
    'i = s.index("resource \"logtail_exploration_alert\" \"registry_store_not_luks\"")
j = s.index("\n}\n", i)
head, block, tail = s[:i], s[i:j], s[j:]
assert block.count("  paused = false\n") == 1
s = head + block.replace("  paused = false\n", "  paused = true\n") + tail'
  mutate red "M3 drop the exploration_alert -target= line" wf \
    'old = "              -target=logtail_exploration_alert.registry_store_not_luks \\\n"
assert s.count(old) == 1
s = s.replace(old, "")'
  mutate red "M4 'store_luks=yes ' loses its trailing space" tf \
    'i = s.index("registry_store_not_luks_sql = <<-SQL"); j = s.index("  SQL\n", i)
blk = s[i:j]
assert blk.count("\x27store_luks=yes \x27") == 2
s = s[:i] + blk.replace("\x27store_luks=yes \x27", "\x27store_luks=yes\x27") + s[j:]'
  mutate red "M5 arm B narrowed back to store_escrow=fail" tf \
    'old = "\n          AND position('"$Q"', \x27store_escrow=ok \x27) != position('"$Q"', \x27store_escrow=\x27)\n          AND position('"$Q"', \x27store_escrow=pending \x27) != position('"$Q"', \x27store_escrow=\x27))"
assert s.count(old) == 1
s = s.replace(old, ")")
i = s.index("registry_store_not_luks_sql = <<-SQL"); j = s.index("  SQL\n", i)
blk = s[i:j]
assert blk.count("\x27store_escrow=\x27") == 2
s = s[:i] + blk.replace("\x27store_escrow=\x27", "\x27store_escrow=fail\x27") + s[j:]'
  mutate red "M6 JSONExtractString(raw, 'message') becomes a bare msg" tf \
    'i = s.index("registry_store_not_luks_sql = <<-SQL"); j = s.index("  SQL\n", i)
blk = s[i:j]
assert blk.count("JSONExtractString(raw, \x27message\x27)") >= 7
s = s[:i] + blk.replace("JSONExtractString(raw, \x27message\x27)", "msg") + s[j:]'
  mutate red "M7 arm B drops the pending exemption" tf \
    'old = "\n          AND position('"$Q"', \x27store_escrow=pending \x27) != position('"$Q"', \x27store_escrow=\x27))"
assert s.count(old) == 1
s = s.replace(old, ")")'
  mutate red "M8 arithmetic on arm A's ordering comparison (+ 100000)" tf \
    'old = "\x27store_luks=yes \x27) < position('"$Q"', \x27 zot_last_err=\x27))"
assert s.count(old) == 1
s = s.replace(old, "\x27store_luks=yes \x27) < position('"$Q"', \x27 zot_last_err=\x27) + 100000)")'
  mutate red "M9 the aggregate is zeroed (count(*) * 0)" tf \
    'i = s.index("registry_store_not_luks_sql = <<-SQL"); j = s.index("  SQL\n", i)
blk = s[i:j]
old = "SELECT {{time}} AS time, count(*) AS value"
assert blk.count(old) == 1
s = s[:i] + blk.replace(old, "SELECT {{time}} AS time, count(*) * 0 AS value") + s[j:]'
  mutate red "H1 the heredoc the extractor reads is renamed (extracted SQL empty)" tf \
    'assert s.count("registry_store_not_luks_sql = <<-SQL") == 1
s = s.replace("registry_store_not_luks_sql = <<-SQL", "registry_store_not_luks_sql_v2 = <<-SQL")'
  mutate green "H2 whitespace reflow of the heredoc" tf \
    'old = "\n          AND position('"$Q"', \x27store_escrow=ok \x27)"
assert s.count(old) == 1
s = s.replace(old, " AND\n              position('"$Q"', \x27store_escrow=ok \x27)")
old2 = "\n        OR (position("
assert s.count(old2) == 1
s = s.replace(old2, "\n  OR   (position(")'
fi

_floor=35
[ -n "${MUT_SKIP:-}" ] && _floor=24
_ran=$((pass + fail))
if [ "$_ran" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$_ran" "$_floor" >&2; exit 1; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 1; fi
printf '\n=== registry-store-not-luks-alert: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$_ran" "$_floor"
[ "$fail" -eq 0 ]
