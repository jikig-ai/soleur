#!/usr/bin/env bash
# #6604 — structural gates for the /workspaces LUKS drift observability plumbing (Phase 2).
# Asserts the emit envelope carries the sentry-alert filter tags (DP-8) and reads the BAKED DSN
# first (DP-9), the daily probe reads the passphrase via the pinned scoped-config form (R9) and
# never `doppler run/download --config prd_workspaces_luks`, the cadence is DAILY (not a 5-min
# poll), and the Vector tag + Sentry alert + heartbeat are wired. Every grep is anchored on a
# syntactic construct, never a bare token that also appears in a comment (cq-assert-anchor-not-bare-token).
#
# Run: bash apps/web-platform/infra/luks-monitor.test.sh
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMIT="$DIR/workspaces-luks-emit.sh"
PROBE="$DIR/luks-monitor.sh"
SERVICE="$DIR/luks-monitor.service"
TIMER="$DIR/luks-monitor.timer"
VECTOR="$DIR/vector.toml"
BOOT="$DIR/soleur-host-bootstrap.sh"
SENTRY="$DIR/sentry/issue-alerts.tf"
UPTIME="$DIR/uptime-alerts.tf"

passes=0
fails=0
ok()   { passes=$((passes + 1)); echo "[ok] $1"; }
no()   { fails=$((fails + 1)); echo "[FAIL] $1" >&2; }
have() { grep -qE "$1" "$2"; }

# (a) Vector allowlist carries the luks-monitor tag as a quoted list member (not a comment).
if have '^[[:space:]]*"luks-monitor",[[:space:]]*$' "$VECTOR"; then
  ok "vector.toml include_matches.SYSLOG_IDENTIFIER contains \"luks-monitor\""
else
  no "vector.toml must list \"luks-monitor\", in include_matches.SYSLOG_IDENTIFIER"
fi

# (b) The emit envelope carries BOTH filter tags (DP-8) — the sentry_issue_alert filter_match=all
#     requires both, and Vector never reaches Sentry, so the page depends on this envelope.
if have '"feature":"workspaces-luks"' "$EMIT" && have '"op":"workspaces-luks-drift"' "$EMIT"; then
  ok "workspaces-luks-emit.sh envelope carries feature=workspaces-luks AND op=workspaces-luks-drift (DP-8)"
else
  no "workspaces-luks-emit.sh must carry BOTH feature=workspaces-luks and op=workspaces-luks-drift tags"
fi

# (b2) All nine discriminating fields are present in the envelope.
missing=""
for f in device_type mount_source mapper_present luks_open_result header_uuid_match \
         cryptsetup_unit_result doppler_reachable mountpoint_ok host reason; do
  have "\"$f\":\"%s\"" "$EMIT" || missing="$missing $f"
done
if [ -z "$missing" ]; then
  ok "workspaces-luks-emit.sh envelope carries all nine discriminating fields"
else
  no "workspaces-luks-emit.sh envelope missing discriminating field(s):$missing"
fi

# (b3) DP-9: the emit reads the BAKED /etc/default/luks-monitor DSN BEFORE any `doppler secrets get`.
# Anchor `baked_ln` on the CODE construct (the `[ -r … ]` guard), NOT the bare path — the path also
# appears in the header COMMENT above the code, so a bare-token `head -1` would match the comment and
# pass even if the code were reordered doppler-first (the exact vacuity this check exists to prevent).
baked_ln=$(grep -nE '\[ -r /etc/default/luks-monitor \]' "$EMIT" | sed -n '1p' | cut -d: -f1 || true)
dop_ln=$(grep -nE 'doppler secrets get SENTRY_DSN' "$EMIT" | sed -n '1p' | cut -d: -f1 || true)
if [ -n "$baked_ln" ] && { [ -z "$dop_ln" ] || [ "$baked_ln" -lt "$dop_ln" ]; }; then
  ok "workspaces-luks-emit.sh reads the BAKED DSN before any Doppler fallback (DP-9)"
else
  no "workspaces-luks-emit.sh must read /etc/default/luks-monitor BEFORE the doppler secrets get fallback (DP-9; baked=$baked_ln doppler=$dop_ln)"
fi

# (c) R9: the probe reads the passphrase via the PINNED scoped-config form, never doppler run/download.
if have "doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks" "$PROBE"; then
  ok "luks-monitor.sh reads WORKSPACES_LUKS_KEY via the pinned 'secrets get --config prd_workspaces_luks' form (R9)"
else
  no "luks-monitor.sh must read WORKSPACES_LUKS_KEY via 'doppler secrets get … --plain --config prd_workspaces_luks' (R9)"
fi
# `.*` NOT `[^\n]*` — in a POSIX ERE `[^\n]` is "not backslash, not the letter n", so a violating
# `doppler run --name x --config prd_workspaces_luks` (contains an `n`) would slip the guard. grep is
# already line-scoped, so `.*` is the correct "rest of the line".
if grep -qE 'doppler (run|secrets download).*--config prd_workspaces_luks' "$PROBE"; then
  no "luks-monitor.sh must NEVER use 'doppler run/download --config prd_workspaces_luks' (R9 CWE-522 hole)"
else
  ok "luks-monitor.sh never uses doppler run/download against prd_workspaces_luks (R9)"
fi

# (d) The escrow re-test uses luksOpen --test-passphrase against the real device.
if have 'cryptsetup luksOpen --test-passphrase --key-file -' "$PROBE"; then
  ok "luks-monitor.sh escrow proof uses 'cryptsetup luksOpen --test-passphrase --key-file -'"
else
  no "luks-monitor.sh must use 'cryptsetup luksOpen --test-passphrase --key-file -' for the escrow proof"
fi

# (e) DAILY cadence, not a 5-min poll.
if have '^OnCalendar=daily$' "$TIMER"; then
  ok "luks-monitor.timer fires OnCalendar=daily (not a 5-min poll)"
else
  no "luks-monitor.timer must fire OnCalendar=daily"
fi
if grep -qE 'OnUnitActiveSec|OnCalendar=(minutely|hourly|\*:0/[0-9])' "$TIMER"; then
  no "luks-monitor.timer must NOT be a sub-daily poll (minutely/hourly/*:0/N — the mount state is boot-immutable)"
else
  ok "luks-monitor.timer is not a sub-daily poll"
fi

# (f) The service tags journald as luks-monitor (else Vector never sees the unit's own stderr).
if have '^SyslogIdentifier=luks-monitor$' "$SERVICE"; then
  ok "luks-monitor.service sets SyslogIdentifier=luks-monitor"
else
  no "luks-monitor.service must set SyslogIdentifier=luks-monitor"
fi

# (g) LOG_TAG is a REAL assignment (the drift-fixture contract).
if have '^LOG_TAG="luks-monitor"$' "$PROBE"; then
  ok "luks-monitor.sh assigns LOG_TAG=\"luks-monitor\" (drift-fixture contract)"
else
  no "luks-monitor.sh must assign LOG_TAG=\"luks-monitor\" as a real assignment"
fi

# (h) The Sentry drift alert filters on BOTH tags the emit sets, ANDed. Extract the drift resource
# block and assert WITHIN it — an unscoped grep would pass even if the tags lived in two different
# alerts, or if the two were OR-ed (either tag alone then pages, on every LUKS event).
#
# REBOUND for #7650 Phase 2: this rule is now `sentry_alert`, not `sentry_issue_alert`. The
# semantics are unchanged and so is what this asserts — only the spelling moved:
#   filters_v2 + filter_match = "all"  ->  action_filters[].conditions[] + logic_type = "all"
# The old anchor did not fail loudly when the type changed; it simply extracted an EMPTY block
# and reported the alert misconfigured. That is the right direction to fail in, and it is why
# the anchor is rebound rather than relaxed.
#
# The `logic_type` count is part of the assertion, not decoration. Multiple `action_filters`
# ELEMENTS are OR-ed against each other, so "both tags appear somewhere in this resource, and
# some element says all" is satisfiable by a config that pages on either tag alone — the exact
# defect this case exists to catch, reintroduced through the new shape. Requiring exactly ONE
# element means the single `logic_type = "all"` provably governs both tags. A future second
# element reds this and forces a human to re-read it.
drift_block="$(awk '/^resource "sentry_alert" "workspaces_luks_drift"/{p=1} p{print} p&&/^}/{exit}' "$SENTRY")"
drift_logic_n="$(printf '%s\n' "$drift_block" | grep -cE '^[[:space:]]*logic_type[[:space:]]*=' || true)"
if printf '%s\n' "$drift_block" | grep -c 'value = "workspaces-luks"' >/dev/null \
  && printf '%s\n' "$drift_block" | grep -c 'value = "workspaces-luks-drift"' >/dev/null \
  && [ "$drift_logic_n" = "1" ] \
  && printf '%s\n' "$drift_block" | grep -cE '^[[:space:]]*logic_type[[:space:]]*=[[:space:]]*"all"' >/dev/null; then
  ok "sentry_alert.workspaces_luks_drift ANDs (one action_filter, logic_type=all) feature=workspaces-luks AND op=workspaces-luks-drift"
else
  no "sentry_alert.workspaces_luks_drift must carry exactly ONE action_filters element with logic_type=\"all\" over BOTH feature=workspaces-luks and op=workspaces-luks-drift (a single-tag rule, logic_type=any, or a second OR-ed element all page on either tag alone). Found ${drift_logic_n} logic_type line(s)."
fi

# (i) The daily-probe heartbeat resource exists (the dead-probe switch — P1-4).
if have 'resource "betteruptime_heartbeat" "workspaces_luks"' "$UPTIME"; then
  ok "betteruptime_heartbeat.workspaces_luks exists (daily dead-probe switch)"
else
  no "uptime-alerts.tf must declare betteruptime_heartbeat.workspaces_luks"
fi

# (j) The baked structural gate carries RequiresMountsFor=/mnt/data + chattr +i (C2).
if have 'RequiresMountsFor=/mnt/data' "$BOOT" && have 'chattr \+i' "$BOOT"; then
  ok "soleur-host-bootstrap.sh bakes the structural gate (RequiresMountsFor=/mnt/data + chattr +i)"
else
  no "soleur-host-bootstrap.sh must bake RequiresMountsFor=/mnt/data + chattr +i (C2 structural gate)"
fi

# ===========================================================================
# #6807 — BEHAVIOURAL cases on the execution seam.
#
# Everything above is a static grep. That was the whole suite until #6807, which is why the
# readiness/inventory logic could not be covered here at all: luks-monitor.sh had no
# sourced-detection guard, so `source`ing it ran the entire probe, and the file was never executed
# under stubs. The guard plus run_monitor_case (mock-PATH stub binaries) is that seam.
# ===========================================================================

# shellcheck source=apps/web-platform/infra/workspaces-luks-harness.sh
. "$DIR/workspaces-luks-harness.sh"

# RECLAIM the reporters. The harness defines its own ok()/no() against ITS counters (pass/fail),
# and sourcing it silently overrode the ones this file has used since line 24 — which report into
# passes/fails, the pair the summary prints AND the exit gate reads. Left alone, every behavioural
# case below would have incremented a counter nothing checks: a failing case would print FAIL and
# the suite would still exit 0. That is precisely the fail-open, green-when-broken shape this whole
# change exists to remove, so it does not get to live in the suite enforcing it.
ok()   { passes=$((passes + 1)); echo "[ok] $1"; }
no()   { fails=$((fails + 1)); echo "[FAIL] $1" >&2; }
# Canary for the above: if a future edit re-orders the source below these definitions, this pins the
# regression immediately rather than at the next real failure.
_acct_before="$passes"
ok "reporter accounting is wired to the suite's own counters (fail-open guard)"
[ "$passes" -eq "$((_acct_before + 1))" ] || { echo "[FAIL] reporter accounting is NOT wired — the exit gate cannot see behavioural failures" >&2; exit 1; }

seed_count() { printf 'WORKSPACES_COUNT=%s\n' "$1" >> "$STATE/state"; }

# (k) THE SEAM ITSELF. Sourcing must define the functions and run NOTHING — if this regresses,
# every behavioural case below silently tests a script that already ran to completion on import.
guard_out="$(. "$PROBE" 2>&1; echo "RC=$?")"
if [ "$guard_out" = "RC=0" ]; then
  ok "luks-monitor.sh sourced-detection guard: sourcing defines functions and runs no probe"
else
  no "luks-monitor.sh ran its main body when sourced — the test seam is impossible: [$guard_out]"
fi

# (l) SEAM-UNSET COMPANION for WORKSPACES_MAPPER_PATH. The behavioural cases below all drive that
# override, so without this they would pass identically against a build whose PRODUCTION default
# had drifted. Anchored on the assignment construct, not the bare path (the path also appears in
# prose above it).
if have '^MAPPER="\$\{WORKSPACES_MAPPER_PATH:-/dev/mapper/\$\{MAPPER_NAME\}\}"$' "$PROBE"; then
  ok "luks-monitor.sh MAPPER defaults to /dev/mapper/\$MAPPER_NAME when the override is unset"
else
  no "luks-monitor.sh MAPPER production default drifted behind the test override"
fi

# (m) FLAG UNSET => readyz is never probed. The `ran` half is load-bearing: a bare negative
# ("no readyz call") passes trivially if the probe aborted early at not_mounted, having never
# reached the block at all.
run_monitor_case "$PROBE"
if monRan && nhas 'curl .*readyz'; then
  ok "flag unset: readyz is never probed AND the probe still completes (paired positive control)"
else
  no "flag-unset arm wrong (rc=$MON_RC readyz_probed=$(cnt 'curl .*readyz')): ${MON_OUT:0:200}"
fi

# (n) FLAG SET => readyz IS probed. The positive half of the pair.
run_monitor_case "$PROBE" LUKS_MONITOR_ASSERT_READYZ=1
if has 'curl .*readyz'; then
  ok "flag set: readyz IS probed"
else
  no "flag set but readyz was never probed — the assert silently did not run: ${MON_OUT:0:200}"
fi

# (n2) FLAG SET => readyz is probed INSIDE the container (docker exec), not a bare host curl. A
# host-side curl of the bridge-published port reaches the app with the docker bridge gateway as its
# peer → 403 (readyz_gate_regression). Anchor on the FULL transport (cq-assert-anchor-not-bare-token):
# a revert to bare host curl still satisfies (n) above but must red here.
# The container literal `soleur-web-platform` is asserted DELIBERATELY, not wildcarded: it locks that
# the probe targets the RIGHT container (a wrong-but-running container answering ready:true is a
# false-green vector — see the pinned-constant mitigation), and reds loudly on an incomplete rename.
# SIBLING: workspaces-luks-freeze.test.sh T22d covers the OTHER consumer (cutover app_canary) through
# the OTHER docker stub (the docker() shell-function form) — both delegations need independent cover.
if has 'docker exec soleur-web-platform curl'; then
  ok "flag set: readyz is probed via docker exec into the container (genuine-loopback peer, not the bridge gateway)"
else
  no "flag set but readyz probe is a bare host curl — the bridge-gateway peer gets 403 in prod: ${MON_OUT:0:200}"
fi

# (o) FAIL CLOSED on a missing baseline. A missing operand must never become a SKIPPED comparison —
# that is the same green-probe-that-cannot-fail defect #6807 exists to remove.
run_monitor_case "$PROBE" LUKS_MONITOR_ASSERT_READYZ=1
if [ "$MON_RC" -ne 0 ] && monOut 'workspace_count_baseline_missing'; then
  ok "missing WORKSPACES_COUNT fails CLOSED with workspace_count_baseline_missing (never a skipped comparison)"
else
  no "a missing inventory baseline did not fail closed (rc=$MON_RC): ${MON_OUT:0:300}"
fi

# (o2)–(o6) #9123 DELIVERED-STATE asserts — the daily probe re-checks what the boot-unlock
# installer left behind (fstab exactly-one-mapper, the §(e) covered-inode flag). The harness
# seeds a canonical fixture fstab + healthy peek attrs in mon_prepare/mon_run; each failing arm
# below rewrites the fixture or sets MON_PEEK_*. Every reason must exit 1 via emit_and_die
# (at-rest drift class in the verify workflow's classifier).
mon_prepare "$PROBE"
: > "$MON_DIR/fstab"
mon_run
if [ "$MON_RC" -eq 1 ] && monOut 'fstab_mnt_data_lines'; then
  ok "fstab with zero /mnt/data entries -> fstab_mnt_data_lines (rc=1, drift)"
else
  no "empty fstab did not fail fstab_mnt_data_lines (rc=$MON_RC): ${MON_OUT:0:200}"
fi

mon_prepare "$PROBE"
printf '/dev/mapper/workspaces /mnt/data ext4 defaults,nofail 0 2\n/dev/mapper/workspaces /mnt/data ext4 ro 0 2\n' > "$MON_DIR/fstab"
mon_run
if [ "$MON_RC" -eq 1 ] && monOut 'fstab_mnt_data_lines'; then
  ok "fstab with TWO /mnt/data entries -> fstab_mnt_data_lines (exactly-one assert)"
else
  no "duplicate fstab line did not fail fstab_mnt_data_lines (rc=$MON_RC): ${MON_OUT:0:200}"
fi

mon_prepare "$PROBE"
printf '/dev/disk/by-label/WRONG /mnt/data ext4 defaults,nofail 0 2\n' > "$MON_DIR/fstab"
mon_run
if [ "$MON_RC" -eq 1 ] && monOut 'fstab_mapper_line_missing'; then
  ok "a non-mapper /mnt/data fstab line -> fstab_mapper_line_missing (rc=1, drift)"
else
  no "wrong-source fstab did not fail fstab_mapper_line_missing (rc=$MON_RC): ${MON_OUT:0:200}"
fi

mon_prepare "$PROBE"
MON_PEEK_FAIL=1 mon_run
if [ "$MON_RC" -eq 1 ] && monOut 'covered_inode_peek_failed'; then
  ok "peek bind failure -> covered_inode_peek_failed (probe-integrity, proves nothing)"
else
  no "a failed peek did not fail covered_inode_peek_failed (rc=$MON_RC): ${MON_OUT:0:200}"
fi

mon_prepare "$PROBE"
MON_PEEK_ATTRS='---------------e------' mon_run
if [ "$MON_RC" -eq 1 ] && monOut 'covered_inode_not_immutable'; then
  ok "covered inode WITHOUT +i -> covered_inode_not_immutable (rc=1, drift)"
else
  no "non-immutable covered inode did not fail covered_inode_not_immutable (rc=$MON_RC): ${MON_OUT:0:200}"
fi

# Positive control for the new asserts: the default fixture fstab + healthy attrs keep the
# probe green — run_monitor_case "$PROBE" (no flags) in (m) above already proves the healthy
# arm end-to-end through them.

# (p)(q)(r) INVENTORY, on ONE fixture exercised three ways. The fixture carries exactly the four
# things session-metrics.ts excludes, plus a stray regular file: an unfiltered `ls | wc -l` reads 6
# here and would certify a real shrink green, which is the whole reason parity is load-bearing.
mon_prepare "$PROBE"
mkdir -p "$WSDIR/ws-a" "$WSDIR/ws-b" "$WSDIR/lost+found" "$WSDIR/.cron" "$WSDIR/.orphaned-old"
touch "$WSDIR/stray-file"

# (p) parity + (r) the verdict line the workflow's positive control greps for, verbatim.
seed_count 2
mon_run LUKS_MONITOR_ASSERT_READYZ=1
if monRan && monOut 'SOLEUR_WORKSPACES_READYZ ready=true' && monOut 'workspace_count=2 expected=2'; then
  ok "inventory parity with countWorkspaceDirsAt (lost+found/.cron/.orphaned-*/stray file excluded) + verdict line emitted"
else
  no "count diverged from countWorkspaceDirsAt's exclusions, or no verdict line (rc=$MON_RC): ${MON_OUT:0:300}"
fi

# A GROWN inventory is healthy — users create workspaces between cutovers. Only a SHRINK is the
# data-loss signal, so the comparison must be `-lt`, not `-ne`.
seed_count 1
mon_run LUKS_MONITOR_ASSERT_READYZ=1
monRan && ok "count ABOVE the baseline passes (growth is not a shortfall)" \
       || no "a grown inventory was reported as drift (rc=$MON_RC): ${MON_OUT:0:200}"

# (q) SHORTFALL => exit 3 (readiness class), distinct from at-rest drift's exit 1.
seed_count 8
mon_run LUKS_MONITOR_ASSERT_READYZ=1
if [ "$MON_RC" -eq 3 ] && monOut 'workspace_count_shortfall'; then
  ok "count < expected exits 3 with workspace_count_shortfall (readiness class, not at-rest drift)"
else
  no "an inventory shrink did not produce exit 3 + workspace_count_shortfall (rc=$MON_RC): ${MON_OUT:0:300}"
fi

# (s) READINESS FAILURE => exit 3, and it happens BEFORE the heartbeat push, so a host that cannot
# serve never pushes a healthy beat.
run_monitor_case "$PROBE" LUKS_MONITOR_ASSERT_READYZ=1 \
  MON_READYZ_CODE=503 MON_READYZ_BODY='{"ready":false,"checks":{"workspaces_writable":false,"workspaces_populated":true}}'
if [ "$MON_RC" -eq 3 ] && monOut 'readyz_not_ready' && nhas 'curl .*HEARTBEAT|curl -gfsS'; then
  ok "readyz ready=false exits 3 and no heartbeat is pushed (assert ordered before the beat)"
else
  no "not-ready arm wrong or a healthy beat was pushed anyway (rc=$MON_RC): ${MON_OUT:0:300}"
fi

# (t) FLAG-LEAK GUARD. The cutover channel writes DOPPLER_TOKEN into /etc/default/luks-monitor;
# if it ever wrote the assert flag there too, the DAILY timer would silently start probing readyz
# (luks-monitor.service reads that file with EnvironmentFile=-), changing the daily unit's
# behaviour and its time-to-page without anyone deciding to.
CUT="$DIR/workspaces-cutover.sh"
# Anchor on the WRITE construct, not the bare token: a future comment in the cutover that merely
# NAMES the flag ("we deliberately never write LUKS_MONITOR_ASSERT_READYZ here") would flip this
# negative guard to a false FAIL. A write is `>>`/`tee`/`printf … EnvironmentFile` carrying the token.
if grep -qE 'LUKS_MONITOR_ASSERT_READYZ[^=]*=[^=].*(>>|tee|/etc/default/luks-monitor)|(>>|tee).*LUKS_MONITOR_ASSERT_READYZ' "$CUT"; then
  no "workspaces-cutover.sh WRITES LUKS_MONITOR_ASSERT_READYZ to host state — the daily timer would inherit the verify-only flag"
else
  ok "the cutover channel never writes LUKS_MONITOR_ASSERT_READYZ into /etc/default/luks-monitor"
fi

# (u) ZERO baseline is rejected as missing. `0` is digits, so a naive `''|*[!0-9]*` guard admits it —
# and `count -lt 0` is false for EVERY count, an absorbing green a total wipe would pass.
mon_prepare "$PROBE"
mkdir -p "$WSDIR/ws-a"
seed_count 0
mon_run LUKS_MONITOR_ASSERT_READYZ=1
if [ "$MON_RC" -eq 3 ] && monOut 'workspace_count_baseline_missing'; then
  ok "a zero baseline is rejected as missing (not an unfailable floor)"
else
  no "WORKSPACES_COUNT=0 was accepted as a real baseline (rc=$MON_RC): ${MON_OUT:0:200}"
fi

# (v) INCOHERENT mapper-path override is refused (the #5274 re-open guard). The seam flag is what
# separates the harness's legitimate fixture path from a stray host env var.
mon_prepare "$PROBE"
mkdir -p "$WSDIR/ws-a"; seed_count 1
# Point the override at a path that is NOT /dev/mapper/$MAPPER_NAME, WITHOUT the test-seam flag.
MON_OUT="$(
  env LUKS_MONITOR_ASSERT_READYZ=1 \
    PATH="$MON_DIR/bin:$PATH" CALLS="$CALLS" MARKER_LOG="$MARKER_LOG" FAKE_MAPPER="$MON_DIR/fake-mapper" \
    WORKSPACES_MOUNT="$MNT" WORKSPACES_MAPPER_PATH="$MON_DIR/fake-mapper" \
    WORKSPACES_STATE_DIR="$STATE" LUKS_MONITOR_WORKSPACES_DIR="$WSDIR" \
  bash "$PROBE" 2>&1
)"; MON_RC=$?
if [ "$MON_RC" -ne 0 ] && monOut 'mapper_path_override_refused'; then
  ok "an incoherent WORKSPACES_MAPPER_PATH override without the test seam is refused (#5274 re-open guard)"
else
  no "a stray mapper-path override was accepted, splitting the mount-identity gate from the escrow assert (rc=$MON_RC): ${MON_OUT:0:200}"
fi

# ---------------------------------------------------------------------------
# (w) wl_count_workspace_dirs — DIRECT unit tests. It is the parity twin of countWorkspaceDirsAt and
# the sole operand proving the inventory survived, yet it was reachable only through app_canary —
# function coverage zero. Source the shared leaf directly (its direct-exec guard does not fire under
# `source`) and drive it against roots the integration fixtures cannot construct.
# ---------------------------------------------------------------------------
# shellcheck source=apps/web-platform/infra/workspaces-luks-emit.sh
. "$EMIT"
# Under the harness's already-trapped RUN_SCRATCH (cleanup_scratch on EXIT/INT/TERM/HUP) rather than
# a fresh untrapped mktemp — no new class-b tempfile-ownership debt.
wc_root="$RUN_SCRATCH/wc-unit"; mkdir -p "$wc_root"
# empty root => 0, rc 0
out="$(wl_count_workspace_dirs "$wc_root")"; rc=$?
[ "$out" = "0" ] && [ "$rc" -eq 0 ] && ok "wl_count_workspace_dirs: empty root => 0 rc0" \
  || no "wl_count_workspace_dirs empty root wrong (out=$out rc=$rc)"
# missing root => rc!=0 (caller fails closed)
wl_count_workspace_dirs "$wc_root/nope" >/dev/null; rc=$?
[ "$rc" -ne 0 ] && ok "wl_count_workspace_dirs: missing root fails closed (rc=$rc)" \
  || no "wl_count_workspace_dirs missing root returned success"
# UNREADABLE root (exists, mode 000) => rc!=0. THE DI-F1 catastrophic path: a rc0+count0 here would
# persist an absorbing-zero baseline. Skip only if running as root (mode 000 is not enforced for uid 0).
mkdir -p "$wc_root/unread/ws-a"; chmod 000 "$wc_root/unread"
if [ "$(id -u)" -ne 0 ]; then
  wl_count_workspace_dirs "$wc_root/unread" >/dev/null 2>&1; rc=$?
  [ "$rc" -ne 0 ] && ok "wl_count_workspace_dirs: unreadable root fails closed (rc=$rc) — no absorbing-zero baseline" \
    || no "wl_count_workspace_dirs unreadable root returned SUCCESS — DI-F1 catastrophic path is open (rc=$rc)"
else
  ok "wl_count_workspace_dirs: unreadable-root case skipped (running as root; mode 000 not enforced)"
fi
chmod 755 "$wc_root/unread"
# exclusions + dotglob invariance. Under dotglob, `*/` also matches hidden dirs; the count MUST be
# identical with and without it (else a shopt set in one caller's process inflates one operand).
mkdir -p "$wc_root/pop/ws-a" "$wc_root/pop/.hidden-real" "$wc_root/pop/lost+found" "$wc_root/pop/.cron" "$wc_root/pop/.orphaned-x"
touch "$wc_root/pop/stray-file"
c_plain="$(wl_count_workspace_dirs "$wc_root/pop")"
c_dot="$(shopt -s dotglob; wl_count_workspace_dirs "$wc_root/pop")"
if [ "$c_plain" = "2" ] && [ "$c_dot" = "2" ]; then
  ok "wl_count_workspace_dirs: exclusions honored AND dotglob-invariant (ws-a + .hidden-real = 2 either way)"
else
  no "wl_count_workspace_dirs count/dotglob wrong (plain=$c_plain dot=$c_dot want 2/2)"
fi
# The function must not LEAK dotglob back to the caller (it restores what it found).
shopt -u dotglob; wl_count_workspace_dirs "$wc_root/pop" >/dev/null
shopt -q dotglob && no "wl_count_workspace_dirs leaked dotglob=on to the caller" \
  || ok "wl_count_workspace_dirs restores the caller's glob state"
rm -rf "$wc_root"

# (x) DEAD-MAN OBSERVABILITY (#6812, #9045, #9098). A successful remount silently undid the 2026-07-20
# cutover; the fire, the arm, the disarm, and both remount outcomes must each emit a marker. #9045
# added the arm's refusal/failure rows, the disarm's verified-failure row, the unarmed-rollback row
# and one outcome row per abort, and retired the false `reason=canary_passed` (rollback() used to
# log it). Every row shares the full prefix below, so ONE Better Stack grep finds the whole story.
# #9098 K: `_deadman_row` now PREPENDS that prefix itself and call sites pass `result=…`, so the
# fire rows (literal, inside the self-contained systemd-run string) and the _deadman_row rows are
# checked separately. Every check reads COMMENT-STRIPPED source: a call commented out is gone.
DM_PFX='SOLEUR_WORKSPACES_LUKS_DEADMAN feature=workspaces-luks op=workspaces-luks-deadman'
DM_SRC="$(grep -vE '^[[:space:]]*#' "$CUT")"
for pat in \
  "result=fired reason=timer_elapsed" \
  "result=ok reason=plaintext_remounted" \
  "result=fail reason=remount_failed" \
  "result=fail reason=mapper_close_failed" \
  "result=fail reason=refused_plaintext_wiped" \
  "result=fail reason=refused_plaintext_record_gone"; do
  if grep -qF "$DM_PFX $pat" <<<"$DM_SRC"; then
    ok "dead-man FIRE emits marker: $pat"
  else
    no "dead-man FIRE MISSING marker ($pat) — the #6812 blind spot is not closed"
  fi
done
if grep -qF "local row=\"$DM_PFX \$1\"" <<<"$DM_SRC"; then
  ok "_deadman_row prepends the full dead-man prefix to every row"
else
  no "_deadman_row does not prepend '$DM_PFX' — its rows would not be found by the one prefix grep"
fi
for pat in \
  "result=armed reason=freeze_engaged" \
  "result=arm_refused reason=already_armed" \
  "result=arm_refused reason=fire_in_progress" \
  "result=arm_refused reason=plaintext_dev_unrestorable" \
  "result=arm_failed reason=systemd_run_refused" \
  "result=arm_failed reason=timer_not_waiting" \
  'result=disarmed reason=${reason}' \
  'result=disarm_failed reason=${reason} check=${check}' \
  "result=disarm_failed reason=rollback_engaged check=fire_stuck" \
  "result=not_armed reason=rollback_engaged prior=" \
  "result=already_disarmed reason=rollback_engaged" \
  'result=cutover_aborted outcome=${outcome}${mode}${abnormal}${fields}${detail}' \
  'result=cutover_aborted outcome=${outcome} mode=rollback' \
  'result=cutover_aborted outcome=${2} mode=rollback'; do
  if grep -qF "_deadman_row \"$pat" <<<"$DM_SRC"; then
    ok "dead-man emits marker: $pat"
  else
    no "dead-man MISSING marker ($pat) — the #6812 blind spot is not closed"
  fi
done
# The closed OUTCOME vocabulary of cleanup() (#9098 B): each value is assigned somewhere, and the
# abnormal-exit field exists. A renamed outcome would silently orphan the runbook's triage row.
for o in rolled_back rollback_stacked rollback_remount_failed post_canary_luks_retained post_canary_restart_failed \
         post_canary_mount_not_mapper arm_aborted clean_stray pre_freeze dry_run wipe_aborted refused_plaintext_wiped \
         refused_plaintext_record_gone; do
  if grep -qE "(^|[;[:space:]])outcome=${o}([;[:space:]]|\$)" <<<"$DM_SRC"; then
    ok "cleanup() outcome vocabulary carries outcome=$o"
  else
    no "cleanup() outcome=$o is never assigned — its runbook row is orphaned"
  fi
done
for rr in 'rollback_refused_plaintext_wiped refused_plaintext_wiped' 'rollback_refused_plaintext_record_gone refused_plaintext_record_gone' \
          'rollback_refused_post_cutover refused_post_cutover'; do
  if grep -qE "^[[:space:]]*_rollback_refuse ${rr} \"" <<<"$DM_SRC"; then
    ok "ROLLBACK-mode refusal '${rr%% *}' goes through _rollback_refuse with outcome=${rr##* } (never a false pre_freeze)"
  else
    no "ROLLBACK-mode refusal '${rr%% *}' does not use _rollback_refuse with outcome ${rr##* } — its row would read pre_freeze"
  fi
done
if grep -qF 'abnormal=" abnormal_exit=1"' <<<"$DM_SRC"; then
  ok "cleanup() marks a signal/incomplete exit with abnormal_exit=1"
else
  no "cleanup() never emits abnormal_exit=1 — a signal-driven abort is indistinguishable from a die"
fi
# Each reason of the CLOSED disarm vocabulary has exactly its call site (comment-stripped), and the
# retired reason is gone: `canary_passed` described a rollback as a pass.
for site in "disarm_dead_man host_canary_passed" "disarm_dead_man rollback_engaged" "disarm_dead_man arm_aborted"; do
  if grep -qE "(^|[[:space:];&|{])${site}([[:space:]]|;|\$)" <<<"$DM_SRC"; then
    ok "dead-man disarm call site present: $site"
  else
    no "dead-man disarm call site MISSING: $site — that reason can no longer be emitted"
  fi
done
if grep -qE '(^|[^_])canary_passed' <<<"$DM_SRC"; then
  no "dead-man still carries the retired bare canary_passed reason (a rollback logged as a pass)"
else
  ok "dead-man carries no retired reason=canary_passed"
fi

# (y) VERDICT-LINE ANCHOR PARITY. The verify workflow's positive control greps the probe output with
# `^\[luks-monitor\] SOLEUR_WORKSPACES_READYZ ready=true `. That anchor depends on log()'s
# `[luks-monitor] ` prefix and the exact field order. If the emitted line and the workflow anchor
# drift, the workflow fails CLOSED on EVERY run (the opposite failure, but still wrong). Extract the
# literal grep pattern from the workflow and run it against a real success emission — producer and
# consumer pinned to each other, not both to a hand-copied string.
VERIFY_WF="$DIR/../../../.github/workflows/workspaces-luks-verify.yml"
wf_anchor="$(grep -oE "grep -cE '\^\\\\\[luks-monitor\\\\\] SOLEUR_WORKSPACES_READYZ ready=true '" "$VERIFY_WF" | sed -n '1p' | sed -E "s/^grep -cE '//; s/'$//")"
mon_prepare "$PROBE"; mkdir -p "$WSDIR/ws-a"; seed_count 1
mon_run LUKS_MONITOR_ASSERT_READYZ=1
if [ -n "$wf_anchor" ] && printf '%s\n' "$MON_OUT" | grep -cE "$wf_anchor" >/dev/null; then
  ok "the verify workflow's verdict-line anchor matches the emitted line (producer/consumer pinned)"
else
  no "the workflow's positive-control anchor [$wf_anchor] does NOT match the emitted verdict line — the workflow would fail closed on every run: ${MON_OUT:0:200}"
fi

# ===========================================================================
# (t) #6808 — THE HEARTBEAT PUSH, both arms fatal.
#
# Until 2026-08-04 an absent URL logged a WARN and the probe exited 0, so a never-configured probe
# and a dead one were indistinguishable off-host and NEITHER paged. Nothing in this suite covered
# the heartbeat at all — in either direction — so the WARN could not have been caught here.
#
# All three cases assert on the REASON, not merely on a non-zero rc: rc=3 is shared with every
# readiness/inventory failure, so an rc-only assertion would pass against a probe that died at
# workspace_count_baseline_missing having never reached the heartbeat block.
# ===========================================================================

# (t1) POSITIVE CONTROL FIRST. A healthy probe must actually PUSH — without this, (t2)/(t3) below
# would both pass against a build that removed the push entirely.
mon_prepare "$PROBE"; mkdir -p "$WSDIR/ws-a"; seed_count 1
mon_run LUKS_MONITOR_ASSERT_READYZ=1
if [ "$MON_RC" -eq 0 ] && has 'curl .*betterstack.test'; then
  ok "healthy probe PUSHES the heartbeat and exits 0 (positive control for the two fatal arms)"
else
  no "healthy probe did not push the heartbeat (rc=$MON_RC, pushes=$(cnt 'curl .*betterstack.test')): ${MON_OUT:0:200}"
fi

# (t2) ABSENT URL => fatal. The exact state #6808 existed to remove.
mon_prepare "$PROBE"; mkdir -p "$WSDIR/ws-a"; seed_count 1
mon_run LUKS_MONITOR_ASSERT_READYZ=1 MON_HB_URL=
if [ "$MON_RC" -eq 3 ] && monOut 'heartbeat_url_absent'; then
  ok "absent WORKSPACES_LUKS_HEARTBEAT_URL is FATAL (rc=3 heartbeat_url_absent), never a survivable WARN"
else
  no "an absent heartbeat URL did not fail loudly (rc=$MON_RC): ${MON_OUT:0:300}"
fi

# (t3) EXHAUSTED PUSH => fatal, and only after retrying. The retry count is asserted because a
# build that dropped the loop would still be "fatal on a failing push" and pass a bare rc check,
# while turning one transient egress blip into a red daily probe.
mon_prepare "$PROBE"; mkdir -p "$WSDIR/ws-a"; seed_count 1
mon_run LUKS_MONITOR_ASSERT_READYZ=1 MON_HB_PUSH_RC=7
if [ "$MON_RC" -eq 3 ] && monOut 'heartbeat_push_failed' && [ "$(cnt 'curl .*betterstack.test')" -eq 3 ]; then
  ok "an exhausted heartbeat push is FATAL (rc=3 heartbeat_push_failed) and is retried 3x first"
else
  no "failing heartbeat push wrong (rc=$MON_RC, attempts=$(cnt 'curl .*betterstack.test')): ${MON_OUT:0:300}"
fi

# (t4) The absent-URL arm must NOT be classified as at-rest drift. It exits 3, not 1 — an alerting
# fault must never file the p0 type/security issue whose body asserts the Article 32 claim is false.
if [ "$MON_RC" -ne 1 ]; then
  ok "a heartbeat fault never exits 1 (would classify a broken alerting path as plaintext-at-rest)"
else
  no "a heartbeat fault exited 1 — it would file the p0 at-rest drift verdict"
fi

# ===========================================================================
# (z) #8706 — the emit helper's two drop paths are VISIBLE. `[ -n "$dsn" ] || return 0` and the
# Sentry curl's `|| true` were silent, which kept host drift out of Sentry for nine weeks. Each now
# logs SOLEUR_WORKSPACES_LUKS_SEND_FAILED under the luks-monitor tag (Vector-allowlisted). Driven
# for real: the helper is sourced by a caller under `set -euo pipefail` (luks-monitor.sh's and the
# cutover's options) with PATH-shimmed logger/doppler/curl, and logger records its argv.
# The baked-DSN path is a fixed host path with no seam, so on a host that HAS a readable
# /etc/default/luks-monitor the no-DSN case is unreachable and is reported as skipped.
# ===========================================================================
# The canonical fixture-dir guard (byte-identical to every tracked copy; fixture-dir-operand-assert).
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
EM_DIR="$RUN_SCRATCH/emit-skip"
assert_fixture_dir "$EM_DIR"
mkdir -p "$EM_DIR/bin"
cat > "$EM_DIR/bin/logger" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$EM_LOG"
STUB
cat > "$EM_DIR/bin/doppler" <<'STUB'
#!/usr/bin/env bash
[ -n "${EM_DSN:-}" ] || exit 1
printf '%s' "$EM_DSN"
STUB
cat > "$EM_DIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf 'curl\n' >> "$EM_CALLS"
exit "${EM_CURL_RC:-0}"
STUB
chmod +x "$EM_DIR"/bin/*
# Synthesized DSN (cq-test-fixtures-synthesized-only): hex key, .example host.
EM_FAKE_DSN="https://0123456789abcdef0123456789abcdef@o0.ingest.example/0"
# shellcheck disable=SC2016  # the bash -c body expands $EMIT in the CHILD, by design
em_run() {
  assert_fixture_dir "$EM_DIR"
  : > "$EM_DIR/logger.log"; : > "$EM_DIR/calls.log"
  EM_OUT="$(
    env -u SOLEUR_SENTRY_DSN -u WORKSPACES_LUKS_LOG_TAG "$@" \
      PATH="$EM_DIR/bin:$PATH" EM_LOG="$EM_DIR/logger.log" EM_CALLS="$EM_DIR/calls.log" EMIT="$EMIT" \
      bash -c 'set -euo pipefail; . "$EMIT"; WL_REASON=mapper_absent workspaces_luks_emit; echo "EMIT_RC=$?"' 2>&1
  )"; EM_RC=$?
}
if [ -r /etc/default/luks-monitor ]; then
  ok "emit skip-marker cases skipped: this host has a readable /etc/default/luks-monitor (fixed path, no seam)"
else
  # (z1) no DSN resolvable -> no_dsn marker under the luks-monitor tag; no Sentry POST; caller continues.
  em_run EM_DSN=
  if [ "$EM_RC" -eq 0 ] && [[ "$EM_OUT" == *"EMIT_RC=0"* ]] \
    && grep -qxF -- "-p user.crit -t luks-monitor -- SOLEUR_WORKSPACES_LUKS_SEND_FAILED reason=no_dsn drift_reason=mapper_absent" "$EM_DIR/logger.log" \
    && ! grep -q curl "$EM_DIR/calls.log"; then
    ok "emit with no resolvable DSN logs SOLEUR_WORKSPACES_LUKS_SEND_FAILED reason=no_dsn under -t luks-monitor and returns 0 under set -euo pipefail"
  else
    no "emit no-DSN drop is not visible (rc=$EM_RC, logger=[$(cat "$EM_DIR/logger.log")]): ${EM_OUT:0:200}"
  fi
  # (z2) DSN resolves but the POST fails -> send_failed marker, the DSN/key never logged.
  em_run EM_DSN="$EM_FAKE_DSN" EM_CURL_RC=22
  if [ "$EM_RC" -eq 0 ] && [[ "$EM_OUT" == *"EMIT_RC=0"* ]] \
    && grep -qxF -- "-p user.crit -t luks-monitor -- SOLEUR_WORKSPACES_LUKS_SEND_FAILED reason=send_failed drift_reason=mapper_absent" "$EM_DIR/logger.log" \
    && ! grep -qF '0123456789abcdef' "$EM_DIR/logger.log" && [[ "$EM_OUT" != *0123456789abcdef* ]]; then
    ok "emit with a failed Sentry POST logs reason=send_failed (no DSN/key in the row) and returns 0"
  else
    no "emit send-failure drop is not visible or leaks the DSN (rc=$EM_RC, logger=[$(cat "$EM_DIR/logger.log")]): ${EM_OUT:0:200}"
  fi
  # (z3) POSITIVE CONTROL: DSN resolves and the POST succeeds -> the POST happens and NO skip marker.
  # Without this, (z1)/(z2) pass against a helper that logs the marker unconditionally.
  em_run EM_DSN="$EM_FAKE_DSN" EM_CURL_RC=0
  if [ "$EM_RC" -eq 0 ] && grep -q curl "$EM_DIR/calls.log" && ! grep -qF SEND_FAILED "$EM_DIR/logger.log"; then
    ok "emit with a DSN and a successful POST sends and logs no skip marker (positive control)"
  else
    no "emit success path wrong (rc=$EM_RC, posts=$(grep -c curl "$EM_DIR/calls.log"), logger=[$(cat "$EM_DIR/logger.log")])"
  fi
fi

echo ""
echo "=== luks-monitor.test.sh: ${passes} passed, ${fails} failed ==="
[ "$fails" -eq 0 ] || exit 1
