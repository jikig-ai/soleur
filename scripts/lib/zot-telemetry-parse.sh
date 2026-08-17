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
# tail BEFORE any key=value parse. zot_last_err is emitted LAST (cloud-init-registry.yml, the LINE= emitter in zot-disk-heartbeat.sh),
# so a greedy cut from its first occurrence bounds the trusted region and a crafted zot log line
# (containing e.g. `boot_id=`/`exit_code=137`) cannot spoof the fields a verdict keys on.
# zot_envelope_anchor: stdin = raw JSONEachRow lines. Prints only rows whose `raw` envelope
# BEGINS with the direct-POST producer shape `{"message":"SOLEUR_ZOT_DISK `.
#
# WHY (#7569, plan finding F15). `betterstack-query.sh --grep SOLEUR_ZOT_DISK` is an unanchored
# `raw LIKE '%SOLEUR_ZOT_DISK%'`, so ANY row on the shared source whose text merely quotes the
# marker satisfies it — and that is not hypothetical: on 2026-07-15 three GitHub-webhook rows
# quoting a marker were returned to the sibling NIC leg, which is why THAT leg already anchors.
#
# The zot leg did not, and the consequence is a suppression primitive rather than noise: one
# contaminated row makes the caller's `$MAIN` non-empty, which SKIPS the whole
# `if [[ -z "$MAIN" ]]` block — the block containing both the PRODUCER_SILENT branch and the
# INGEST_DARK branch. An unauthenticated party able to get one line into this shared source
# could therefore mask genuine registry-telemetry darkness indefinitely.
#
# The anchor is the NIC leg's proven form (envelope prefix + trailing space). A Vector-shipped
# journald row's raw starts `{"PRIORITY":"6",…` and buries the marker in a nested .message, so
# it cannot satisfy this prefix; the registry host's direct POST emits `{"message":"<marker> …`
# and does.
zot_envelope_anchor() {
  grep -F '"raw":"{\"message\":\"SOLEUR_ZOT_DISK ' || true
}

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
