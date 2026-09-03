#!/usr/bin/env bash
# Tests for tests/scripts/lib/inngest-volume-recut-gate.sh (sourced by the inngest_volume_recut
# job in .github/workflows/apply-web-platform-infra.yml, #7695).
#
# The gate reads a `terraform show -json <plan>` document and PASSes (rc=0) iff the plan is EXACTLY
# the scoped inngest-redis volume recut: hcloud_volume.inngest_redis REPLACED (actions include BOTH
# "delete" AND "create") OR the RECOVERY bare create (["create"] with before==null), plus
# hcloud_volume_attachment.inngest_redis CREATED, with hcloud_server.inngest showing ZERO actions,
# the live /workspaces volume + its attachment + the web-1 server untouched, the LUKS passphrase
# not rotated, the replaced-volume physical id matching the operator-supplied pin, and nothing else
# out of scope.
#
# EVERY ROW OF THE PLAN'S MUTATION MATRIX IS HERE, and each is labelled with its row number so a
# dropped row is visible rather than merely absent. The matrix was written from the DESIGN before
# the guard existed (plan §Guard Contract, task 3.1) — a matrix derived from finished code tests
# the code that exists, not the property.
#
# Non-vacuity discipline (RED-verification for a gating primitive): each FAIL fixture differs from
# the PASS fixture by ONE mutation of the exact class the gate must catch, and each asserts the
# gate's `reason=<token>` rather than merely a non-zero rc — a battery that asserts only rc cannot
# tell a guard that caught the right thing from one that aborted for an unrelated reason.
# Deterministic; no network. All fixtures are SYNTHESIZED (cq-test-fixtures-synthesized-only) —
# modelled on the -replace plan shape; no captured real plan.
#
# Run: bash tests/scripts/test-inngest-volume-recut-gate.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${DIR}/../.." && pwd)"
# shellcheck source=tests/scripts/lib/inngest-volume-recut-gate.sh
source "${DIR}/lib/inngest-volume-recut-gate.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; [[ -n "${2:-}" ]] && echo "      rc=$2" >&2; [[ -n "${3:-}" ]] && echo "      out=$3" >&2; return 0; }

# TMPDIR default: a DIRECT invocation of this suite inherits the bare machine-global /tmp tmpfs,
# which parallel worktrees share. scripts/test-all.sh and run-registered-suites.sh already default
# to /var/tmp; matching them here keeps a direct run's verdicts from becoming a function of another
# session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"
TMP="$(mktemp -d -t inngest-volume-recut-gate.XXXXXXXX)" || { echo "FATAL: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

PINNED_ID="106261946"   # soleur-inngest-redis-store — the volume the dispatch authorizes destroying
OTHER_ID="105149570"    # a DIFFERENT physical volume — must never be the destroy target

# ── INSTRUMENT SELF-TEST ──────────────────────────────────────────────────────────
# Drive both counters once each and refuse to continue unless BOTH moved. A suite whose pass()/
# fail() have been neutered reports a clean run having asserted nothing; every other anti-vacuity
# mechanism here is downstream of these two functions.
_p0=$passes; _f0=$fails
pass; fail "INSTRUMENT SELF-TEST (expected — proves fail() records)" >/dev/null 2>&1
if [[ "$passes" -ne $((_p0 + 1)) || "$fails" -ne $((_f0 + 1)) ]]; then
  printf 'FATAL: instrument self-test did not move both counters (passes %s->%s, fails %s->%s)\n' \
    "$_p0" "$passes" "$_f0" "$fails" >&2
  exit 2
fi
passes=$_p0; fails=$_f0

# ── Fixture builders ──────────────────────────────────────────────────────────────
# EVERY BUILDER EMITS AN `after`, because terraform always does on a create and these fixtures
# did not. `new_volume_formatted` refuses anything that is not a positively-observed null format
# — including an ABSENT `after` — so an `after`-less fixture is both unrealistic and now
# correctly refused. Emitting `{}` here makes the whole suite grade documents shaped like the
# ones the gate will actually see.
# A resource_change object with the given address + actions array (no `before`).
rc_obj() { printf '{"address":"%s","change":{"actions":[%s],"after":{}}}' "$1" "$2"; }
# A resource_change object carrying a `before.id` (the physical volume being acted on).
rc_obj_id() { printf '{"address":"%s","change":{"actions":[%s],"before":{"id":"%s"},"after":{}}}' "$1" "$2" "$3"; }
write_plan() { printf '{"format_version":"1.2","resource_changes":[%s]}' "$1" > "$TMP/plan.json"; }
# A resource_change whose `after` carries a format — the shape a `format = "ext4"` config emits on
# the CREATE side of a replace. Measured on the real plan, not invented.
rc_obj_fmt() { printf '{"address":"%s","change":{"actions":[%s],"before":{"id":"%s"},"after":{"format":"ext4"}}}' "$1" "$2" "$3"; }
# A `before` that EXISTS but carries no id. Terraform emits this when the prior state entry is
# present but its id was never recorded or was nulled; `rc_obj_id` can never produce it.
rc_obj_nullid() { printf '{"address":"%s","change":{"actions":[%s],"before":{"id":null},"after":{}}}' "$1" "$2"; }
# A NUMERIC before.id. The gate coerces with `| tostring`; nothing measured that it does.
rc_obj_numid() { printf '{"address":"%s","change":{"actions":[%s],"before":{"id":%s},"after":{}}}' "$1" "$2" "$3"; }

# The scoped recut: the volume shows a REPLACE carrying the pinned id; its attachment replaces too.
VOL_REPLACE="$(rc_obj_id 'hcloud_volume.inngest_redis' '"delete","create"' "$PINNED_ID")"
ATT_REPLACE="$(rc_obj 'hcloud_volume_attachment.inngest_redis' '"delete","create"')"
# Named-live addresses appear as no-op (untargeted deps that terraform still lists).
SRV_NOOP="$(rc_obj 'hcloud_server.inngest' '"no-op"')"
WSVOL_NOOP="$(rc_obj 'hcloud_volume.workspaces[\"web-1\"]' '"no-op"')"
WSATT_NOOP="$(rc_obj 'hcloud_volume_attachment.workspaces[\"web-1\"]' '"no-op"')"
WEB1_NOOP="$(rc_obj 'hcloud_server.web[\"web-1\"]' '"no-op"')"
PW_NOOP="$(rc_obj 'random_password.inngest_redis_luks' '"no-op"')"
SECRET_NOOP="$(rc_obj 'doppler_secret.inngest_redis_luks_key' '"no-op"')"

PASS_SET="${VOL_REPLACE},${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},${WSATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"

# check <name> <want_rc> <needle> <plan-file> [expected_id]
check() {
  local name="$1" want_rc="$2" needle="$3" plan="$4" expected="${5-}"
  local out rc=0
  if [[ $# -ge 5 ]]; then
    out="$(inngest_volume_recut_gate "$plan" "$expected" 2>&1)" || rc=$?
  else
    out="$(inngest_volume_recut_gate "$plan" 2>&1)" || rc=$?
  fi
  if [[ "$rc" -eq "$want_rc" && "$out" == *"$needle"* ]]; then
    pass
  else
    fail "$name (want rc=$want_rc containing '$needle')" "$rc" "$out"
  fi
}

# ── THE WRAPPER SELF-TEST ─────────────────────────────────────────────────────────
# The instrument self-test above drives pass()/fail() DIRECTLY. Every arm below goes through
# check(), which it never exercises — so replacing check()'s body with a bare `pass` produced
# `38 passed, 0 failed`, rc 0, with the anti-vacuity floor reporting healthy. Drive the wrapper in
# the direction that must FAIL, then roll the counters back.
write_plan "${PASS_SET}"
_st_p=$passes; _st_f=$fails
check "SELF-TEST (expected to fail): a PASS plan is not an abort" 1 "reason=old_volume_touched" "$TMP/plan.json" "$PINNED_ID" 2>/dev/null
if [[ "$fails" -eq $((_st_f + 1)) && "$passes" -eq "$_st_p" ]]; then
  passes=$_st_p; fails=$_st_f; pass
else
  passes=$_st_p; fails=$_st_f
  fail "INSTRUMENT: check() did not fail on a must-fail arm — every assertion in this file is decorative"
fi

# ── Canonical PASS ────────────────────────────────────────────────────────────────
write_plan "${PASS_SET}"
check "PASS: exact scoped recut, id-pinned" 0 "inngest_volume_recut_gate: PASS" "$TMP/plan.json" "$PINNED_ID"

# create_before_destroy ordering must not change the verdict.
write_plan "$(rc_obj_id 'hcloud_volume.inngest_redis' '"create","delete"' "$PINNED_ID"),${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},${WSATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"
check "PASS: create-before-destroy replace ordering" 0 "inngest_volume_recut_gate: PASS" "$TMP/plan.json" "$PINNED_ID"

# ── N1: THE REPLACEMENT VOLUME IS BORN FORMATTED ──────────────────────────────────
# The P0 this counter exists for. `format = "ext4"` sat on the resource under a
# `lifecycle { ignore_changes = [format] }` believed to neutralise it; ignore_changes suppresses
# DIFFS, never CREATES. Measured on the real recut plan: with the line, after.format=ext4.
write_plan "$(rc_obj_fmt 'hcloud_volume.inngest_redis' '"delete","create"' "$PINNED_ID"),${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},${WSATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"
check "N1: the new volume is created ext4 => ABORT new_volume_formatted" 1 "reason=new_volume_formatted" "$TMP/plan.json" "$PINNED_ID"
# N1b — format UNKNOWN at plan time. Terraform serialises this as null in `after` with true in
# `after_unknown`, which `after.format != null` alone read as "born RAW" and PASSED. This is the
# reachable one: a provider bump making `format` Optional+Computed, or any `format = <expr>`,
# produces it. The sibling `reboot_updates` counter documents the same serialisation and errs safe.
write_plan "$(printf '{"address":"hcloud_volume.inngest_redis","change":{"actions":["delete","create"],"before":{"id":"%s"},"after":{"format":null},"after_unknown":{"format":true}}}' "$PINNED_ID"),${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},${WSATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"
check "N1b: format UNKNOWN at plan time => ABORT new_volume_formatted" 1 "reason=new_volume_formatted" "$TMP/plan.json" "$PINNED_ID"
# N1c — an `after`-less create is not a shape terraform emits; refuse rather than guess.
write_plan "$(printf '{"address":"hcloud_volume.inngest_redis","change":{"actions":["delete","create"],"before":{"id":"%s"}}}' "$PINNED_ID"),${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},${WSATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"
check "N1c: a create with NO after key => ABORT new_volume_formatted" 1 "reason=new_volume_formatted" "$TMP/plan.json" "$PINNED_ID"

# ── N2: A DESTROY THE PLAN CANNOT NAME ────────────────────────────────────────────
# `before` non-null, `before.id` null. luks_id_mismatch selects on `before.id != null` and
# id_pin_absent only fires when the pin is EMPTY, so this shape defeated both — the one case where
# the operator pin cannot be verified was the one case nothing verified.
write_plan "$(rc_obj_nullid 'hcloud_volume.inngest_redis' '"delete","create"'),${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},${WSATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"
check "N2: a destroy whose before.id is null => ABORT id_pin_unverifiable" 1 "reason=id_pin_unverifiable" "$TMP/plan.json" "$PINNED_ID"

# N2b/N2c — THE WIDER SHAPE N2 DID NOT COVER, and the reason its counter read 0. `id_pin_unverifiable`
# was written as `before != null AND before.id == null`, which closes only the `before` OBJECT with a
# null id — the one shape `rc_obj_nullid` happens to build. A destroy with NO `before` key at all
# (what `rc_obj` emits, and what a state-drop or a hand-edited plan produces) leaves `.change.before`
# null, so the `!= null` guard was FALSE and all three pins scored 0. MEASURED before the fix:
#     redis_volume_provisioned=1 … luks_id_mismatch=0 id_pin_absent=0 id_pin_unverifiable=0
#     inngest_volume_recut_gate: PASS — … replaced-volume id is readable and matches the operator pin
# on a plan destroying the volume that holds the sole copy of the AOF. The PASS text was false in
# both halves. `rc_obj` is the builder that produces it; `rc_obj_nullid` structurally cannot.
write_plan "$(rc_obj 'hcloud_volume.inngest_redis' '"delete","create"'),${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},${WSATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"
check "N2b: a destroy with NO before key at all => ABORT id_pin_unverifiable" 1 "reason=id_pin_unverifiable" "$TMP/plan.json" "$PINNED_ID"

write_plan "$(printf '{"address":"hcloud_volume.inngest_redis","change":{"actions":["delete","create"],"before":null,"after":{}}}'),${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},${WSATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"
check "N2c: a destroy whose before is explicitly null => ABORT id_pin_unverifiable" 1 "reason=id_pin_unverifiable" "$TMP/plan.json" "$PINNED_ID"

# THE OTHER DIRECTION, and the reason the widened selector is scoped to delete/forget rather than to
# the address: the RECOVERY bare create has `before: null` too, and it must still PASS. Widening the
# pin without this arm would have swapped a fail-open for a fail-shut on the one path that exists to
# rebuild the volume after a failed recut — the recovery route being reachable is itself a property
# two earlier fixes in this branch got wrong.
write_plan "$(rc_obj 'hcloud_volume.inngest_redis' '"create"'),${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},${WSATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"
check "N2d: the RECOVERY bare create (before null, no destroy) still PASSES" 0 "inngest_volume_recut_gate: PASS" "$TMP/plan.json" "$PINNED_ID"

# ── N3: A NUMERIC before.id ───────────────────────────────────────────────────────
# The gate coerces with `| tostring`; dropping that left the suite green because every fixture
# emitted a STRING id. Both directions: the matching numeric id must PASS, a different one ABORT.
write_plan "$(rc_obj_numid 'hcloud_volume.inngest_redis' '"delete","create"' "$PINNED_ID"),${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},${WSATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"
check "N3a: a NUMERIC before.id equal to the pin => PASS" 0 "inngest_volume_recut_gate: PASS" "$TMP/plan.json" "$PINNED_ID"
write_plan "$(rc_obj_numid 'hcloud_volume.inngest_redis' '"delete","create"' "$OTHER_ID"),${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},${WSATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"
check "N3b: a NUMERIC before.id that differs => ABORT luks_id_mismatch" 1 "reason=luks_id_mismatch" "$TMP/plan.json" "$PINNED_ID"

# ── N4: A `read` ACTION MUST NOT ABORT ────────────────────────────────────────────
# THE TOO-AGGRESSIVE DIRECTION, which no arm covered. `positive` deliberately excludes BOTH
# `no-op` AND `read`, and the gate header says so — but widening it to include `read` left the
# suite at 38/0 while the real dispatch would abort `out_of_scope` against any plan carrying a
# data-source read. A gate that passes its tests and refuses the operator is still broken.
write_plan "${PASS_SET},$(rc_obj 'data.hcloud_image.ubuntu' '"read"')"
check "N4: a data-source read is not a positive action => PASS" 0 "inngest_volume_recut_gate: PASS" "$TMP/plan.json" "$PINNED_ID"

# ── N5: EVERY named-live member is independently load-bearing ─────────────────────
# Four of the six only ever appeared as `no-op`, so removing any of them from named_live changed
# nothing measurable. Each must ABORT under its OWN counter when acted on.
write_plan "${VOL_REPLACE},${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},${WSATT_NOOP},$(rc_obj 'hcloud_server.web[\"web-1\"]' '"update"'),${PW_NOOP},${SECRET_NOOP}"
check "N5a: web-1 server updated => ABORT web1_server_touched" 1 "reason=web1_server_touched" "$TMP/plan.json" "$PINNED_ID"
write_plan "${VOL_REPLACE},${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},$(rc_obj 'hcloud_volume_attachment.workspaces[\"web-1\"]' '"delete"'),${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"
check "N5b: the live /workspaces attachment detached => ABORT old_attachment_touched" 1 "reason=old_attachment_touched" "$TMP/plan.json" "$PINNED_ID"

# ── N6: THE PASSPHRASE PAIR IS THE LOAD-BEARING named_live MEMBERSHIP ──────────────
# Their own counter omits `create` on purpose (this volume is cut to LUKS for the FIRST time, so a
# first create of the passphrase is legal). That makes named_live the only thing standing between
# a legal first create and an out_of_scope abort — the one membership in the list whose removal
# changes a verdict, and the direction that must PASS.
write_plan "${VOL_REPLACE},${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},${WSATT_NOOP},${WEB1_NOOP},$(rc_obj 'random_password.inngest_redis_luks' '"create"'),$(rc_obj 'doppler_secret.inngest_redis_luks_key' '"create"')"
check "N6a: a FIRST create of the passphrase pair is legal => PASS" 0 "inngest_volume_recut_gate: PASS" "$TMP/plan.json" "$PINNED_ID"
# ...and the rotation directions still abort, so N6a is not simply a hole.
write_plan "${VOL_REPLACE},${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},${WSATT_NOOP},${WEB1_NOOP},$(rc_obj 'random_password.inngest_redis_luks' '"delete","create"'),${SECRET_NOOP}"
check "N6b: a passphrase REPLACE rotates the key => ABORT luks_passphrase_touched" 1 "reason=luks_passphrase_touched" "$TMP/plan.json" "$PINNED_ID"

# ── Row 1: the LIVE sole-copy /workspaces volume is touched ───────────────────────
write_plan "${VOL_REPLACE},${ATT_REPLACE},${SRV_NOOP},$(rc_obj 'hcloud_volume.workspaces[\"web-1\"]' '"delete","create"'),${WSATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"
check "Row 1: live /workspaces volume replaced => ABORT old_volume_touched" 1 "reason=old_volume_touched" "$TMP/plan.json" "$PINNED_ID"

# Its attachment is the same catastrophe one address over (detach strands sole-copy data).
write_plan "${VOL_REPLACE},${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},$(rc_obj 'hcloud_volume_attachment.workspaces[\"web-1\"]' '"delete"'),${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"
check "Row 1b: live /workspaces attachment detached => ABORT old_attachment_touched" 1 "reason=old_attachment_touched" "$TMP/plan.json" "$PINNED_ID"

# ── Row 2: web-1 replaced (cx33 unrebuildable) ────────────────────────────────────
write_plan "${VOL_REPLACE},${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},${WSATT_NOOP},$(rc_obj 'hcloud_server.web[\"web-1\"]' '"delete","create"'),${PW_NOOP},${SECRET_NOOP}"
check "Row 2: web-1 server replaced => ABORT web1_server_touched" 1 "reason=web1_server_touched" "$TMP/plan.json" "$PINNED_ID"

# ── Row 3: ID-PIN — the address resolves to a DIFFERENT physical volume ───────────
write_plan "$(rc_obj_id 'hcloud_volume.inngest_redis' '"delete","create"' "$OTHER_ID"),${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},${WSATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"
check "Row 3: replace of the WRONG physical id => ABORT luks_id_mismatch" 1 "reason=luks_id_mismatch" "$TMP/plan.json" "$PINNED_ID"

# ── Row 4: the LUKS passphrase is ROTATED ─────────────────────────────────────────
# update/delete/forget strand the store; a FIRST create is legal here (see the gate's inversion
# note) and is pinned by its own PASS arm below, so this row cannot be satisfied by a guard that
# simply rejects every passphrase action.
write_plan "${VOL_REPLACE},${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},${WSATT_NOOP},${WEB1_NOOP},${PW_NOOP},$(rc_obj 'doppler_secret.inngest_redis_luks_key' '"update"')"
check "Row 4: doppler_secret passphrase update => ABORT luks_passphrase_touched" 1 "reason=luks_passphrase_touched" "$TMP/plan.json" "$PINNED_ID"
write_plan "${VOL_REPLACE},${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},${WSATT_NOOP},${WEB1_NOOP},$(rc_obj 'random_password.inngest_redis_luks' '"delete","create"'),${SECRET_NOOP}"
check "Row 4b: random_password passphrase replaced => ABORT luks_passphrase_touched" 1 "reason=luks_passphrase_touched" "$TMP/plan.json" "$PINNED_ID"

# ── Row 5: a delete of an un-enumerated resource ──────────────────────────────────
write_plan "${PASS_SET},$(rc_obj 'hcloud_volume.git_data' '"delete"')"
check "Row 5: out-of-scope delete (git_data volume) => ABORT resource_deletes" 1 "reason=resource_deletes" "$TMP/plan.json" "$PINNED_ID"

# ── Row 5b: hcloud_server.inngest replaced — the three-dispatch split ─────────────
write_plan "${VOL_REPLACE},${ATT_REPLACE},$(rc_obj 'hcloud_server.inngest' '"delete","create"'),${WSVOL_NOOP},${WSATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"
check "Row 5b: the inngest host replaced => ABORT inngest_server_touched" 1 "reason=inngest_server_touched" "$TMP/plan.json" "$PINNED_ID"

# ── Row 7: a SECOND out-of-scope member, after a compliant first ──────────────────
# The quantifier must reach member two: a check that stops at the first entry is itself the
# defect class. The added entry is a pure CREATE (no delete), so resource_deletes cannot catch it
# and only the out_of_scope closure clause can.
write_plan "${PASS_SET},$(rc_obj 'hcloud_volume_attachment.git_data' '"create"')"
check "Row 7: a second un-enumerated create => ABORT out_of_scope" 1 "reason=out_of_scope" "$TMP/plan.json" "$PINNED_ID"

# ── Row 8: unreadable plan document ───────────────────────────────────────────────
check "Row 8a: missing plan JSON => fail-closed" 1 "ABORT" "$TMP/does-not-exist.json" "$PINNED_ID"
printf 'not json{{{' > "$TMP/bad.json"
check "Row 8b: malformed plan JSON => fail-closed" 1 "unparseable" "$TMP/bad.json" "$PINNED_ID"
printf '{"format_version":"1.2"}' > "$TMP/nochanges.json"
check "Row 8c: no resource_changes array => fail-closed" 1 "no resource_changes array" "$TMP/nochanges.json" "$PINNED_ID"

# ── Row 10: the ID-PIN is OMITTED on a genuine destroy ────────────────────────────
# The template takes expected_id="${2:-}", so an omitted pin makes luks_id_mismatch a no-op by
# construction. Without id_pin_absent the gate would authorize destroying whatever physical volume
# the address resolves to — silently, with every other counter reading zero.
write_plan "${PASS_SET}"
check "Row 10a: genuine destroy with NO pin => ABORT id_pin_absent" 1 "reason=id_pin_absent" "$TMP/plan.json"
check "Row 10b: genuine destroy with an EMPTY pin => ABORT id_pin_absent" 1 "reason=id_pin_absent" "$TMP/plan.json" ""

# ── Shape rows: the volume/attachment are not in the recut shape ──────────────────
write_plan "$(rc_obj_id 'hcloud_volume.inngest_redis' '"delete"' "$PINNED_ID"),${ATT_REPLACE},${SRV_NOOP},${PW_NOOP},${SECRET_NOOP}"
check "Shape: bare volume delete (no recreate) => ABORT volume_not_provisioned" 1 "reason=volume_not_provisioned" "$TMP/plan.json" "$PINNED_ID"
write_plan "$(rc_obj_id 'hcloud_volume.inngest_redis' '"forget"' "$PINNED_ID"),${ATT_REPLACE},${SRV_NOOP},${PW_NOOP},${SECRET_NOOP}"
check "Shape: bare volume forget => ABORT volume_not_provisioned" 1 "reason=volume_not_provisioned" "$TMP/plan.json" "$PINNED_ID"
write_plan "$(rc_obj_id 'hcloud_volume.inngest_redis' '"update"' "$PINNED_ID"),${ATT_REPLACE},${SRV_NOOP},${PW_NOOP},${SECRET_NOOP}"
check "Shape: volume update-in-place => ABORT volume_not_provisioned" 1 "reason=volume_not_provisioned" "$TMP/plan.json" "$PINNED_ID"
write_plan "${VOL_REPLACE},$(rc_obj 'hcloud_volume_attachment.inngest_redis' '"delete"'),${SRV_NOOP},${PW_NOOP},${SECRET_NOOP}"
check "Shape: attachment deleted without a create => ABORT attachment_not_created" 1 "reason=attachment_not_created" "$TMP/plan.json" "$PINNED_ID"
# A bare create whose `before` is NON-null is not the recovery shape — it is a resource terraform
# believes already exists, which means the address does not mean what the gate assumes.
write_plan "$(rc_obj_id 'hcloud_volume.inngest_redis' '"create"' "$PINNED_ID"),$(rc_obj 'hcloud_volume_attachment.inngest_redis' '"create"'),${SRV_NOOP},${PW_NOOP},${SECRET_NOOP}"
check "Shape: bare create with a NON-null before => ABORT volume_not_provisioned" 1 "reason=volume_not_provisioned" "$TMP/plan.json" "$PINNED_ID"

# ── H3 (must-PASS, non-canonical): the RECOVERY bare-create arm ───────────────────
# A `-replace` on hcloud_volume.inngest_redis is destroy-BEFORE-create (inngest-host.tf carries no
# create_before_destroy), so an apply failing BETWEEN the delete and the create strands the
# resource out of state. A re-dispatch then plans a BARE create with before == null. If only the
# canonical replace fixture passes, the guard is `diff <fixture> <canonical>` in disguise and a
# stranded operator loops forever on a gate that refuses the only shape terraform will produce.
BARE_CREATE="$(rc_obj 'hcloud_volume.inngest_redis' '"create"'),$(rc_obj 'hcloud_volume_attachment.inngest_redis' '"create"'),${SRV_NOOP},${WSVOL_NOOP},${WSATT_NOOP},${WEB1_NOOP},${PW_NOOP},${SECRET_NOOP}"
write_plan "${BARE_CREATE}"
check "H3: recovery bare create (before null), pin supplied => PASS" 0 "inngest_volume_recut_gate: PASS" "$TMP/plan.json" "$PINNED_ID"
check "H3b: recovery bare create, NO pin => PASS (nothing is being destroyed)" 0 "inngest_volume_recut_gate: PASS" "$TMP/plan.json"

# The passphrase's FIRST create is legal — the inversion vs workspaces-luks-recut-gate.sh. This
# arm is what stops Row 4 from being satisfiable by a guard that rejects every passphrase action.
write_plan "${VOL_REPLACE},${ATT_REPLACE},${SRV_NOOP},${WSVOL_NOOP},${WSATT_NOOP},${WEB1_NOOP},$(rc_obj 'random_password.inngest_redis_luks' '"create"'),$(rc_obj 'doppler_secret.inngest_redis_luks_key' '"create"')"
check "H3c: passphrase FIRST create => PASS (this volume is cut to LUKS for the first time)" 0 "inngest_volume_recut_gate: PASS" "$TMP/plan.json" "$PINNED_ID"

# ── H2: a guard that REJECTS EVERYTHING is caught only by a must-PASS row ─────────
# Recorded explicitly rather than left implicit: the four PASS arms above ARE the H2 contract, and
# a RED-only battery cannot detect `return 1`. The assertion below makes the dependency legible so
# deleting every PASS arm is a visible loss rather than a quieter suite.
# COUNTED FROM THE FILE, NOT DECLARED. This was `_pass_arms=4; [[ 4 -ge 4 ]]` — a literal compared
# to itself, which is true for every possible state of the suite including "every PASS arm was
# deleted". It made the dependency legible to a reader and measured nothing, which is worse than
# leaving it implicit: it reads as coverage. Derive the count from the arms that actually exist.
_pass_arms="$(grep -cE '^check "[^"]*" 0 "inngest_volume_recut_gate: PASS"' "${BASH_SOURCE[0]}" || true)"
if [[ "$_pass_arms" =~ ^[0-9]+$ ]] && [[ "$_pass_arms" -ge 4 ]]; then pass; else fail "H2: only ${_pass_arms} must-PASS arms found (floor 4) — a guard stuck at 'reject everything' would go undetected"; fi

# ── Preamble binding (#6997): INVOKED, not merely sourced ─────────────────────────
_PG_DIR="$DIR"
GATE="${_PG_DIR}/lib/inngest-volume-recut-gate.sh"
PREAMBLE="${_PG_DIR}/lib/plan-gate-preamble.sh"
# shellcheck source=tests/scripts/lib/gate-suite-harness.sh
source "${_PG_DIR}/lib/gate-suite-harness.sh"

# The wrappers this suite does NOT define. `check()`'s self-test above covers the local one; these
# two come from the harness and no suite that sources it drove either. Placed immediately after the
# source and before the first gate_check — a self-test that runs before its subject is defined
# reports "command not found", which is loud here only because the `if !` credits it as a failure.
if ! gate_harness_selftest; then fails=$((fails + 1)); fi

mk_plan "$TMP/pg-d5.json" "[$(rc_empty_actions 'hcloud_volume.workspaces[\"web-1\"]' 'hcloud_volume')]"
mk_plan "$TMP/pg-d6.json" "[$(rc_scalar_change 'hcloud_volume.workspaces[\"web-1\"]' 'hcloud_volume')]"

gate_check "A1 (D5): an EMPTY actions array hiding a destroy => fail-closed ABORT" \
  inngest_volume_recut_gate 1 "unclassifiable plan entry" "$TMP/pg-d5.json" "$PINNED_ID"
gate_check "A1 (D5): the ABORT is the preamble's and names this gate" \
  inngest_volume_recut_gate 1 "inngest_volume_recut_gate: ABORT — unclassifiable" "$TMP/pg-d5.json" "$PINNED_ID"
gate_check "A2 (D6): a SCALAR .change => fail-closed ABORT" \
  inngest_volume_recut_gate 1 "unclassifiable plan entry" "$TMP/pg-d6.json" "$PINNED_ID"
gate_check "A2 (D6): the ABORT names the offending address" \
  inngest_volume_recut_gate 1 "hcloud_volume.workspaces" "$TMP/pg-d6.json" "$PINNED_ID"

# Row 6 / A4: neutering the classifiability CALL must leave the plan REJECTED (the retrofit never
# opened a door) while the preamble-distinctive signature DISAPPEARS (the rejection was really the
# preamble's). The anchor is deliberately NOT the gate name — every abort this gate emits is
# prefixed with it, so a name anchor is a redness detector rather than a binding.
gate_mutate_layered "A4: classifiability call (invoked, not merely sourced)" \
  's/^  plan_gate_assert_classifiable .*/  :/' \
  "unclassifiable plan entry" "plan is NOT the exact scoped" \
  inngest_volume_recut_gate "$TMP/pg-d5.json" "$PINNED_ID"

# ── Row 9: a counter that did not evaluate must not satisfy every threshold ───────
# [[ "" -gt 0 ]] is FALSE under bash coercion, so an uncomputed counter silently clears the gate.
# Neutering the numeric assert on the canonical PASS fixture cannot show this (the counters DO
# evaluate there), so drive it directly: replace one counter's jq extraction with the empty string
# and assert the gate aborts naming that counter.
write_plan "${PASS_SET}"
_mut="$TMP/mutated-numeric.sh"
sed "s|^  ovt=\$(echo \"\$counts\".*|  ovt=\"\"|" "$GATE" > "$_mut"
if cmp -s "$_mut" "$GATE"; then
  fail "Row 9: the counter mutation matched NOTHING in the gate; the extraction shape drifted"
else
  _rc=0; _out="$(bash -c "source '$PREAMBLE'; source '$_mut'; inngest_volume_recut_gate '$TMP/plan.json' '$PINNED_ID'" 2>&1)" || _rc=$?
  if [[ "$_rc" -eq 1 && "$_out" == *"counter parse failed"* && "$_out" == *"old_volume_touched"* ]]; then
    pass
  else
    fail "Row 9: an empty counter must ABORT naming that counter, not silently satisfy the threshold" "$_rc" "$_out"
  fi
fi

# ── Row 6 (workflow dispatch): the gate is SOURCED and CALLED by the workflow ─────
# A guard that reports "0 checked" and exits 0 is vacuous; the job must fail when the gate does not
# run. Nothing inside the gate function can see its own call site, so this is asserted against the
# workflow text. `if !` (rather than a bare call) is what makes the status non-suppressing.
WF="${REPO_ROOT}/.github/workflows/apply-web-platform-infra.yml"
if grep -qF 'tests/scripts/lib/inngest-volume-recut-gate.sh' "$WF"; then pass; else fail "Row 6a: the workflow does not SOURCE inngest-volume-recut-gate.sh"; fi
if grep -qE '^[[:space:]]*if ! inngest_volume_recut_gate ' "$WF"; then pass; else fail "Row 6b: the workflow does not CALL inngest_volume_recut_gate under a non-suppressing 'if !'"; fi
# The pin must reach the gate as its second argument, or the ID-PIN is disabled in production while
# every test here passes.
if grep -qE '^[[:space:]]*if ! inngest_volume_recut_gate "[^"]+" "\$\{?EXPECTED_INNGEST_VOLUME_ID' "$WF"; then pass; else fail "Row 6c: the workflow does not pass expected_inngest_volume_id to the gate"; fi

# ── The guard's OWN operands (the axis every other row misses) ────────────────────
# Every row above mutates the PLAN and confirms the guard REDS. None asks how the guard fails OPEN.
# These degenerate an operand the guard interpolates. `$expected` reaches jq via `--arg`, so it
# cannot become a wildcard the way an unquoted shell glob or an interpolated regex could — but
# "cannot" is a claim, and this is what makes it a measured one. A guard that accepts everything is
# indistinguishable from a healthy run, so no pass count can catch this class.
write_plan "${PASS_SET}"
check "OPERAND: a GLOB-shaped pin must not match the real id (jq --arg is not a pattern)" 1 "reason=luks_id_mismatch" "$TMP/plan.json" "*"
check "OPERAND: a REGEX-shaped pin must not match the real id" 1 "reason=luks_id_mismatch" "$TMP/plan.json" ".*"
check "OPERAND: a pin that is a PREFIX of the real id must not match" 1 "reason=luks_id_mismatch" "$TMP/plan.json" "10626194"
# A directory where a plan file is expected: `-f` rejects it, so the gate aborts on the readable
# assert rather than handing jq something it will silently read as empty.
check "OPERAND: a DIRECTORY as the plan path => fail-closed" 1 "ABORT" "$TMP" "$PINNED_ID"

# ── H1: anti-vacuity floor ────────────────────────────────────────────────────────
# DELIBERATELY SELF-CONTAINED — bash builtins and this suite's own counters only. The first
# version of this pattern called a harness helper whose `source` lived inside the arm block, so
# deleting the arms also undefined the floor: it exited 127, recorded nothing, and the suite
# passed. A floor that depends on the thing it guards is not a floor.
#
# A FLOOR, NOT EQUALITY — the count is developer-incremented, so `-eq` would redden the suite on
# every legitimately-added assertion and train people to bump it unread.
_ran=$((passes + fails))
if [[ "$_ran" -lt 53 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 53. Arms were deleted, skipped, or the suite exited early.\n' "$_ran" >&2
  printf 'inngest-volume-recut-gate: %s passed, %s failed\n' "$passes" "$fails"
  exit 1
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor 53)\n' "$_ran"
fi

echo ""
echo "inngest-volume-recut-gate: ${passes} passed, ${fails} failed"
[[ "$fails" -eq 0 ]]
