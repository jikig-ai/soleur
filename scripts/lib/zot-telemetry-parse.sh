#!/usr/bin/env bash
# Shared trusted-region parse + newest-boot scoping helpers for the SOLEUR_ZOT_DISK
# telemetry stream (cloud-init-registry.yml emit line, Better Stack Logs source 2457081).
#
# WHY THIS EXISTS (single source of truth for the spoof-resistance invariant): the
# #6288 soak probe (scripts/followthroughs/zot-restart-plateau-6288.sh) and the standing
# restart-loop recurrence alarm (scripts/zot-restart-loop-alarm.sh, #6291) BOTH must parse
# this stream identically. The trusted-region strip + newest-boot scoping is a *security*
# guard (a crafted zot_last_err log tail must not spoof boot_id=/exit_code=137); duplicating
# a security invariant across two scripts is a maintenance hazard, so it lives here and both
# consumers `source` it. (This is NOT the "don't over-abstract a ≤3-file change" case — that
# rule is about not building shared infra for convenience, not about copy-pasting a guard.)
#
# The functions are stdin filters so callers can pipe (both consumers store the intermediate
# results in variables via command substitution, matching the pre-refactor soak-probe style).
#
# betterstack-query.sh returns JSONEachRow lines `{"dt":"<iso>","raw":"..."}`; each line begins
# with the ISO dt, so a lexical `sort` orders rows chronologically REGARDLESS of the query's
# ORDER BY (do NOT hard-couple to the shared tool's dt-ASC default — #6251-spirit).

# zot_trusted_region: stdin = raw betterstack JSONEachRow output.
# Lexical sort (dt-prefixed → chronological), then strip each row's free-text `zot_last_err=`
# tail BEFORE any key=value parse. zot_last_err is emitted LAST (cloud-init-registry.yml:219-221),
# so a greedy cut from its first occurrence bounds the trusted region and a crafted zot log line
# (containing e.g. `boot_id=`/`exit_code=137`) cannot spoof the fields a verdict keys on.
zot_trusted_region() {
  sort | sed 's/ zot_last_err=.*//'
}

# zot_newest_boot: stdin = trusted region (output of zot_trusted_region).
# Prints the newest real boot_id — the last (newest, post-sort) row carrying a non-'unknown'
# boot_id — or empty if none. The immutable registry-host-replace REUSES the terraform hostname,
# so boot_id (not host) is what separates old-host from new-host events.
zot_newest_boot() {
  grep -oE 'boot_id=[0-9a-fA-F-]+' | grep -v 'boot_id=unknown' | tail -1 | cut -d= -f2
}

# zot_scope_to_boot <boot_id>: stdin = trusted region. Prints only the rows for that boot_id,
# in chronological (post-sort) order.
zot_scope_to_boot() {
  grep -F "boot_id=$1"
}

# zot_nonsentinel_values <field>: stdin = scoped rows. Prints the non-'-1' integer values of
# <field> (drops the -1 inspect-miss sentinel a mid-restart `docker inspect` returns), one per
# line, in row order. Trailing `|| true` so an all-sentinel column yields empty, not a pipefail.
zot_nonsentinel_values() {
  grep -oE "$1=-?[0-9]+" | cut -d= -f2 | grep -vE '^-' || true
}
