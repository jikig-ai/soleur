#!/usr/bin/env bash
set -euo pipefail

# NIC-wait gate guard (#6441, ADR-114 §I1).
#
# CONTEXT: on a freshly-provisioned web-1, cloud-init registers the host as the Cloudflare
# tunnel's SOLE connector before its Hetzner private NIC exists. `hcloud_server_network`
# is an additive online attach that cannot precede `hcloud_server.web[k].id`, so the attach
# ALWAYS lands after the token — the race is unfixable in Terraform (ADR-114 §I1, ADR-115).
# Post-#6594 all three ingress services dial RFC1918 literals, so a NIC-less connector
# serves NOTHING, not `registry.` alone.
#
# The gate this guards: `soleur-wait-nic` waits for the private NIC, then lets connector
# registration proceed — and on timeout DEFERS rather than aborting.
#
# The three properties that make it safe, each asserted behaviourally below:
#   - ALWAYS exits 0 (CF-5). `runcmd` is ONE /bin/sh and is once-per-instance: an `exit 1`
#     here does not skip a step, it terminates cloudflared install, the webhook binary, the
#     :9000 poll, the monitors and the egress firewall — permanently, for that instance.
#   - Emits EXACTLY ONE event, from three mutually-exclusive arms. The emit is the only
#     evidence the gate ran at all: a fresh boot is a blind surface.
#   - A probe fault is NEVER reported as NIC-absent (#6415). Zero evidence is not evidence
#     of absence.
#
# WHY A BEHAVIOURAL HARNESS: the sibling observability suite is grep-only over raw file
# text, so it can assert that the literals `command -v` and `grep -qwF` exist but never
# that the matcher BEHAVES. This suite extracts the helper body and executes it against a
# stub `ip`, which is what turns AC4 from a string-presence proxy into a real
# post-condition. `sleep` is stubbed to a no-op so the timeout arm costs ~0s, not 60s.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOT="$DIR/soleur-host-bootstrap.sh"
CI="$DIR/cloud-init.yml"
TF="$DIR/server.tf"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }
assert() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else no "$1"; fi; }

# ── Extract the baked helper body ────────────────────────────────────────────────────
# The helper exists only as heredoc text inside the bootstrap authoring script. Extract it
# so it can be EXECUTED. A silently-empty extraction would make every behavioural assert
# below pass vacuously, so the extraction is guarded for non-emptiness first.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; mkdir -p "$BIN"

awk "/^cat > \/usr\/local\/bin\/soleur-wait-nic <<'NICEOF'\$/{f=1;next} f&&/^NICEOF\$/{exit} f" \
  "$BOOT" > "$WORK/soleur-wait-nic"
chmod +x "$WORK/soleur-wait-nic"

echo "--- extraction (non-vacuity) ---"
assert "soleur-wait-nic heredoc extracts to a non-empty body" "[[ -s '$WORK/soleur-wait-nic' ]]"
if [[ ! -s "$WORK/soleur-wait-nic" ]]; then
  echo "FATAL: helper body did not extract — every behavioural assert below would pass vacuously." >&2
  echo "$pass passed, $((fail + 1)) failed"
  exit 1
fi

# ── Stubs ────────────────────────────────────────────────────────────────────────────
# soleur-boot-emit records "<stage> <level>" one per line so arm-exclusivity and the
# exactly-one-event property are both countable.
cat > "$BIN/soleur-boot-emit" <<'STUB'
#!/bin/sh
printf '%s %s\n' "$1" "${2:-info}" >> "$EMIT_LOG"
exit 0
STUB
chmod +x "$BIN/soleur-boot-emit"

# No-op sleep: the timeout arm's bound is 30 iterations, so a real sleep would cost 60s.
cat > "$BIN/sleep" <<'STUB'
#!/bin/sh
exit 0
STUB
chmod +x "$BIN/sleep"

# make_ip <addr>...  — a stub `ip` reporting the given addresses in `ip -4 -o addr show` shape.
make_ip() {
  { echo '#!/bin/sh'
    echo 'cat <<'"'"'ADDRS'"'"''
    echo '1: lo    inet 127.0.0.1/8 scope host lo\       valid_lft forever'
    for a in "$@"; do
      echo "2: eth1    inet $a/32 scope global eth1\\       valid_lft forever"
    done
    echo 'ADDRS'
  } > "$BIN/ip"
  chmod +x "$BIN/ip"
}

# run_arm <expected-ip> — runs the helper, echoes "<rc>|<emit lines joined by ;>"
run_arm() {
  EMIT_LOG="$WORK/emit.log"; : > "$EMIT_LOG"
  export EMIT_LOG
  local rc=0
  PATH="$BIN:/usr/bin:/bin" "$WORK/soleur-wait-nic" "$1" >/dev/null 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(paste -sd';' "$EMIT_LOG" 2>/dev/null || true)"
}

# ── AC4/AC5/AC7: the three arms, behaviourally ───────────────────────────────────────
echo ""
echo "--- AC4/AC5: three mutually-exclusive arms, exactly one event, always exit 0 ---"

make_ip 10.0.1.10
READY=$(run_arm 10.0.1.10)
assert "ready arm: expected IP present -> private_nic_ready info, exit 0" \
  "[[ '$READY' == '0|private_nic_ready info' ]]"

make_ip 10.0.1.99
TIMEOUT=$(run_arm 10.0.1.10)
assert "timeout arm: expected IP absent through the bound -> private_nic_timeout warning, exit 0" \
  "[[ '$TIMEOUT' == '0|private_nic_timeout warning' ]]"

# Probe fault: `ip` unresolvable. PATH deliberately contains ONLY the stub dir minus `ip`.
rm -f "$BIN/ip"
EMIT_LOG="$WORK/emit.log"; : > "$EMIT_LOG"; export EMIT_LOG
pf_rc=0
PATH="$BIN" "$WORK/soleur-wait-nic" 10.0.1.10 >/dev/null 2>&1 || pf_rc=$?
PROBE=$(printf '%s|%s' "$pf_rc" "$(paste -sd';' "$EMIT_LOG" 2>/dev/null || true)")
assert "probe-fault arm: ip unresolvable -> private_nic_probe_fault warning, exit 0" \
  "[[ '$PROBE' == '0|private_nic_probe_fault warning' ]]"
# The #6415 mislabel this gate must not reproduce: 'could not measure' is not 'absent'.
assert "probe-fault arm does NOT emit private_nic_timeout (#6415 mislabel guard)" \
  "[[ '$PROBE' != *private_nic_timeout* ]]"

# ── AC4(d): substring guard ──────────────────────────────────────────────────────────
echo ""
echo "--- AC4(d): grep -qwF substring guard ---"
make_ip 10.0.1.1
SUBSTR=$(run_arm 10.0.1.10)
assert "expected 10.0.1.10 with only 10.0.1.1 present -> NO match (timeout, not ready)" \
  "[[ '$SUBSTR' == '0|private_nic_timeout warning' ]]"

# ── AC5: exactly one event per invocation ────────────────────────────────────────────
echo ""
echo "--- AC5: exactly one event per invocation (no arm emits two, none emits zero) ---"
for spec in "$READY" "$TIMEOUT" "$PROBE" "$SUBSTR"; do
  body="${spec#*|}"
  n=0; [[ -n "$body" ]] && n=$(awk -F';' '{print NF}' <<<"$body")
  assert "arm emitted exactly one event (got $n): ${body:-<none>}" "[[ '$n' == '1' ]]"
done

# ── AC2: CF-5 regression guard ───────────────────────────────────────────────────────
# The single most important assert in this suite. Distinguish heredoc INTERIOR (harmless —
# an `exit 1` there exits the HELPER process) from script BODY (fatal — it aborts runcmd
# under the `set -e` armed at cloud-init.yml, which a cloud-init.yml-only grep cannot see).
echo ""
echo "--- AC2: CF-5 regression guard (no new aborting exit 1) ---"

# soleur-wait-nic's own body must never contain `exit 1` — it is fail-open by contract.
assert "soleur-wait-nic body contains no 'exit 1' (fail-open by contract)" \
  "! grep -qE '^[[:space:]]*exit 1[[:space:]]*\$' '$WORK/soleur-wait-nic'"

# The call site is invoked BARE: no `||` clause, no `exit 1`. Emission is internal to the
# helper, so a caller-side arm would be both redundant and a way to get CF-5 wrong.
# Anchor on the call construct, not the bare token — a bare `soleur-wait-nic` grep also
# matches the authoring line in the bootstrap script and any comment naming it.
NIC_CALL=$(grep -nE '^[[:space:]]*-[[:space:]]+soleur-wait-nic ' "$CI" || true)
assert "cloud-init.yml has exactly one soleur-wait-nic runcmd call site" \
  "[[ \$(grep -cE '^[[:space:]]*-[[:space:]]+soleur-wait-nic ' '$CI' || true) == 1 ]]"
assert "call site carries NO '||' clause" "[[ '$NIC_CALL' != *'||'* ]]"
assert "call site carries NO 'exit 1'"    "[[ '$NIC_CALL' != *'exit 1'* ]]"

# ── AC1: ordering — the wait precedes the install (C3: budgets sequential, not nested) ─
# Asserted here on raw source for the ORDER; the RENDER authority (that the line lands
# INSIDE the `%{ if web_tunnel_connector ~}` block) lives in cloud-init-inngest-bootstrap.test.sh
# AC5, which is the established single home for this gate's render assertions.
echo ""
echo "--- AC1: soleur-wait-nic precedes cloudflared service install ---"
NIC_LINE=$( { grep -nE '^[[:space:]]*-[[:space:]]+soleur-wait-nic ' "$CI" | head -1 | cut -d: -f1; } || true)
INSTALL_LINE=$( { grep -nF -- 'cloudflared service install' "$CI" | head -1 | cut -d: -f1; } || true)
assert "both the NIC wait and the cloudflared install are present" \
  "[[ -n '$NIC_LINE' && -n '$INSTALL_LINE' ]]"
assert "NIC wait ($NIC_LINE) precedes cloudflared service install ($INSTALL_LINE)" \
  "[[ -n '$NIC_LINE' && -n '$INSTALL_LINE' && '$NIC_LINE' -lt '$INSTALL_LINE' ]]"

# ── AC6: the shared fail-closed helper is untouched ──────────────────────────────────
# The separate-helper design exists so soleur-wait-ready's fail-closed contract stays
# UNCONDITIONAL. Assert its distinguishing invariants survive — a future refactor that
# folded the NIC verb back in would flip one of these.
echo ""
echo "--- AC6: soleur-wait-ready's fail-closed contract is intact ---"
awk "/^cat > \/usr\/local\/bin\/soleur-wait-ready <<'WAITEOF'\$/{f=1;next} f&&/^WAITEOF\$/{exit} f" \
  "$BOOT" > "$WORK/soleur-wait-ready"
assert "soleur-wait-ready extracts non-empty" "[[ -s '$WORK/soleur-wait-ready' ]]"
assert "soleur-wait-ready still emits fatal + exit 1 on timeout (fail-closed)" \
  "grep -qF 'soleur-boot-emit \"\$STAGE\" fatal; exit 1' '$WORK/soleur-wait-ready'"
assert "soleur-wait-ready gained no 'nic' verb (separate-helper design held)" \
  "! grep -qE '(^|[^a-z-])nic\)' '$WORK/soleur-wait-ready'"
assert "the pre-existing cloudflared_ready fail-closed gate is unchanged" \
  "grep -qF 'soleur-wait-ready service cloudflared cloudflared_ready || exit 1' '$CI'"

# ── AC9: no reboot primitive (ADR-115 / CF-6) ────────────────────────────────────────
# web-1 is the SOLE live origin: a reboot powers off the only thing serving. ADR-115's
# converge-by-reboot grant is registry-host-scoped and explicitly not class-wide.
# Scoped to the helper + the call-site file — an unscoped diff grep would match this
# suite's own prose about reboots and could never return zero.
echo ""
echo "--- AC9: no reboot primitive on the NIC-wait path (ADR-115) ---"
assert "soleur-wait-nic body invokes no reboot/poweroff/shutdown" \
  "! grep -qE '(^|[^[:alnum:]_-])(reboot|poweroff|shutdown|systemctl[[:space:]]+reboot)([^[:alnum:]_-]|\$)' '$WORK/soleur-wait-nic'"

# ── Plumbing: the expected IP is single-sourced from var.web_hosts ───────────────────
# ADR-115's single-definition doctrine: the address the gate waits on must have exactly
# one definition. A hardcoded literal here would drift silently from variables.tf.
echo ""
echo "--- plumbing: private_ip single-sourced through the templatefile map ---"
assert "server.tf passes private_ip into the cloud-init templatefile map" \
  "grep -qE '^[[:space:]]*private_ip[[:space:]]*=[[:space:]]*each\.value\.private_ip[[:space:]]*\$' '$TF'"
assert "the call site interpolates \${private_ip}, not a hardcoded address" \
  "[[ '$NIC_CALL' == *'\${private_ip}'* ]]"
assert "the call site hardcodes no 10.0.1.x literal" \
  "! grep -qE '^[[:space:]]*-[[:space:]]+soleur-wait-nic[[:space:]]+10\.0\.1\.' '$CI'"

# ── AC8: bake/apply coherence — the delivery-channel P0 ─────────────────────────────
# soleur-host-bootstrap.sh is a member of local.host_script_files, which feeds
# local.host_scripts_content_hash, which is injected into user_data and RECOMPUTED AND
# COMPARED at boot under the `set -e` armed before the `set +e` region:
#     [ "$GOT" = "$HOST_SCRIPTS_HASH" ] || exit 1
# So editing this file changes the hash, and a web-1 created after the apply but BEFORE
# `:latest` carries the matching bootstrap aborts its ENTIRE runcmd at stage=verify — the
# exact catastrophe this gate exists to prevent, arriving through the delivery channel
# rather than the code. This is the first PR to edit soleur-host-bootstrap.sh since the
# coherence guard was added for the sibling web-2 path.
#
# That guard (web2-recreate-preflight.sh) CANNOT be reused on the routine path: it hard-
# requires a pinned repo@sha256 ref and dies on anything else, while var.image_name defaults
# to the mutable `:latest`. So the safety argument here is structural instead, and rests on
# exactly two facts. Both are ASSERTED below rather than assumed, because if either changes
# the exposure silently opens:
#
#   (1) hcloud_server.web carries ignore_changes = [user_data, ...] — so this edit is inert
#       for the RUNNING web-1 and cannot re-render its user_data in place.
#   (2) hcloud_server.web["web-1"] is absent from every -target= in the auto-apply workflow
#       — so a routine merge apply cannot create or replace it. (web-2's entry IS present,
#       and that job is the one already carrying the coherence preflight.)
#
# Residual, deliberately NOT closed here: an operator-driven fresh create/-replace of web-1
# still consumes the new hash with no preflight. That structural gap is the sibling of the
# guard's single-call-site limitation and is tracked as its own issue — it needs a preflight
# that works against a mutable tag, which is a different piece of work from this gate.
echo ""
echo "--- AC8: bake/apply coherence — the structural facts the safety argument rests on ---"
WF_APPLY="$DIR/../../../.github/workflows/apply-web-platform-infra.yml"
assert "the apply workflow is present at the expected path" "[[ -f '$WF_APPLY' ]]"
assert "hcloud_server.web pins ignore_changes = [user_data, ...] (edit is inert for the running host)" \
  "grep -qE '^[[:space:]]*ignore_changes[[:space:]]*=[[:space:]]*\[user_data,' '$TF'"
# Anchor on the -target= construct, not a bare resource name: the resource is named in prose
# comments throughout that workflow, so a bare grep would match commentary and pass vacuously
# in exactly the case this assert exists to catch.
#
# COUNT OUTSIDE THE assert, then compare. An in-assert `! grep -qE '...'` has to survive both
# eval-quoting and regex-escaping of `[`, `"` and `'`; the first draft of this line did not,
# and a regex that matches nothing makes a NEGATIVE assert pass forever. Mutation-testing it
# (inject a real web-1 -target and require a RED) is what surfaced that — the assert reported
# clean against a workflow that genuinely did target web-1. Fixed string + explicit count
# removes the escaping surface entirely. `|| true` guards grep -c's exit 1 on a zero count,
# which would otherwise abort this `set -e` script on the PASSING case.
WEB1_TARGET_N=$(grep -cF -- "-target='hcloud_server.web[\"web-1\"]'" "$WF_APPLY" || true)
assert "hcloud_server.web[\"web-1\"] is in NO -target= of the auto-apply workflow (found $WEB1_TARGET_N)" \
  "[[ '$WEB1_TARGET_N' == '0' ]]"
# Positive control: the web-2 entry MUST be found. Without this, a typo'd needle (or a future
# rename of the -target= spelling) would make the count-zero assert above pass vacuously —
# the same defect one layer up. If this ever fails, the needle is wrong, not the workflow.
WEB2_TARGET_N=$(grep -cF -- "-target='hcloud_server.web[\"web-2\"]'" "$WF_APPLY" || true)
assert "positive control: the web-2 -target= needle still matches (found $WEB2_TARGET_N)" \
  "[[ '$WEB2_TARGET_N' -ge 1 ]]"

echo ""
echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
