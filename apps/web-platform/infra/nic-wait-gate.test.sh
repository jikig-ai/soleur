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

# No-op sleep, but COUNTING: the timeout arm's bound is 30 iterations, so a real sleep would
# cost 60s. Stubbing it away is what makes the suite sub-second — and also what makes the
# budget invisible, so the stub logs its argument. The 30x2s bound is the quantity the design
# rests on (it is what makes this wait SEQUENTIAL with the downstream cloudflared_ready gate
# rather than nested inside it), and without this log a mutation to `while [ "$n" -lt 1 ]` or
# `sleep 600` leaves every assertion green while the gate becomes decorative or wedges the boot.
cat > "$BIN/sleep" <<'STUB'
#!/bin/sh
printf '%s\n' "$1" >> "$SLEEP_LOG"
exit 0
STUB
chmod +x "$BIN/sleep"

# make_ip <addr>...  — a stub `ip` reporting the given addresses in `ip -4 -o addr show` shape.
# It VALIDATES argv rather than ignoring it: an argv-blind stub makes the `-4 -o addr show`
# contract vacuous, so swapping the production call to `ip -o link show` (which prints no
# addresses at all, i.e. the gate could never match) would leave the suite green.
make_ip() {
  { echo '#!/bin/sh'
    echo 'if [ "$*" != "-4 -o addr show" ]; then echo "stub ip: unexpected argv: $*" >&2; exit 2; fi'
    echo 'cat <<'"'"'ADDRS'"'"''
    echo '1: lo    inet 127.0.0.1/8 scope host lo\       valid_lft forever'
    for a in "$@"; do
      echo "2: eth1    inet $a/32 scope global eth1\\       valid_lft forever"
    done
    echo 'ADDRS'
  } > "$BIN/ip"
  chmod +x "$BIN/ip"
}

# make_ip_converging <after-n> <addr> — a stub that reports NOTHING for its first <after-n>
# invocations, then reports <addr>. This is the fixture the gate actually exists for: absent at
# t=0, present at t=N. With static stubs only, the address is either present at the pre-loop
# probe or absent forever, so the LOOP — the waiting itself — is never driven, and deleting its
# `break` (making every real NIC attach emit a timeout) passes every other assertion.
make_ip_converging() {
  local after="$1" addr="$2"
  { echo '#!/bin/sh'
    echo 'if [ "$*" != "-4 -o addr show" ]; then echo "stub ip: unexpected argv: $*" >&2; exit 2; fi'
    echo 'C="$IP_CALL_LOG"; printf x >> "$C"; n=$(wc -c < "$C" | tr -d " ")'
    echo '1: lo    inet 127.0.0.1/8 scope host lo\       valid_lft forever' | sed 's/^/echo '"'"'/;s/$/'"'"'/'
    echo "if [ \"\$n\" -gt $after ]; then echo '2: eth1    inet $addr/32 scope global eth1\\       valid_lft forever'; fi"
  } > "$BIN/ip"
  chmod +x "$BIN/ip"
}

# make_ip_failing — `ip` resolves and is executable but EXITS NON-ZERO (netlink denied, a
# truncated image, a wrapper stub). The probe ran and produced nothing; that is "could not
# measure", NOT "the address is absent".
make_ip_failing() {
  printf '#!/bin/sh\nexit 1\n' > "$BIN/ip"
  chmod +x "$BIN/ip"
}

# run_arm <expected-ip> — runs the helper, echoes "<rc>|<emit lines joined by ;>"
run_arm() {
  EMIT_LOG="$WORK/emit.log"; : > "$EMIT_LOG"
  SLEEP_LOG="$WORK/sleep.log"; : > "$SLEEP_LOG"
  IP_CALL_LOG="$WORK/ipcalls.log"; : > "$IP_CALL_LOG"
  export EMIT_LOG SLEEP_LOG IP_CALL_LOG
  local rc=0
  PATH="$BIN:/usr/bin:/bin" "$WORK/soleur-wait-nic" "$1" >/dev/null 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(paste -sd';' "$EMIT_LOG" 2>/dev/null || true)"
}

# The stub must SHADOW any real binary. run_arm keeps /usr/bin:/bin on PATH (the helper needs
# grep/printf), and real `ip` lives at /usr/bin/ip on usr-merged hosts — so if make_ip ever
# silently failed to write, the negative arms would read the REAL host's addresses and pass for
# the wrong reason. Pin the invariant instead of assuming it.
make_ip 10.0.1.10
echo ""
echo "--- harness precondition: the stub shadows any real ip ---"
assert "command -v ip resolves inside the stub dir, not /usr/bin" \
  "[[ \"\$(PATH='$BIN:/usr/bin:/bin' command -v ip)\" == '$BIN/ip' ]]"

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

# ── The probe-fault arm, across EVERY way the instrument can fail ────────────────────
# The helper's header states "a probe fault is NEVER reported as NIC-absent". That is a claim
# quantified over the whole fault space, so testing one member of it proves almost nothing.
# Each case below is a distinct door into the same #6415 mislabel.
#
# The isolation dir carries the helper's other dependencies (grep, and the emit stub) but NOT
# `ip` — a bare PATH="$BIN" would make grep unresolvable too, so the test could not tell which
# missing binary produced the verdict.
ISO="$WORK/iso"; mkdir -p "$ISO"
cp "$BIN/soleur-boot-emit" "$ISO/soleur-boot-emit"
cp "$BIN/sleep" "$ISO/sleep"
ln -sf "$(command -v grep)" "$ISO/grep"
ln -sf "$(command -v printf 2>/dev/null || echo /usr/bin/printf)" "$ISO/printf" 2>/dev/null || true

# run_iso <bindir> <arg...> — run the helper with PATH restricted to <bindir>.
run_iso() {
  local dir="$1"; shift
  EMIT_LOG="$WORK/emit.log"; : > "$EMIT_LOG"
  SLEEP_LOG="$WORK/sleep.log"; : > "$SLEEP_LOG"
  IP_CALL_LOG="$WORK/ipcalls.log"; : > "$IP_CALL_LOG"
  export EMIT_LOG SLEEP_LOG IP_CALL_LOG
  local rc=0
  PATH="$dir" "$WORK/soleur-wait-nic" "$@" >/dev/null 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(paste -sd';' "$EMIT_LOG" 2>/dev/null || true)"
}

PROBE=$(run_iso "$ISO" 10.0.1.10)
assert "probe fault (a): ip UNRESOLVABLE -> private_nic_probe_fault warning, exit 0" \
  "[[ '$PROBE' == '0|private_nic_probe_fault warning' ]]"

# (b) `ip` resolves and is executable but EXITS NON-ZERO. This is the most probable real fault
# on a booting host, and the one a pipeline hides: `ip … | grep -qwF` reports only grep's exit,
# so a failing probe is indistinguishable from a successful probe that found nothing.
make_ip_failing
PROBE_EXEC=$(run_arm 10.0.1.10)
assert "probe fault (b): ip runs but EXITS NON-ZERO -> private_nic_probe_fault, not timeout" \
  "[[ '$PROBE_EXEC' == '0|private_nic_probe_fault warning' ]]"

# (c) grep unresolvable: the match can never succeed, so reporting absence would be the same
# mislabel one layer down.
ISO2="$WORK/iso2"; mkdir -p "$ISO2"
cp "$BIN/soleur-boot-emit" "$ISO2/soleur-boot-emit"
cp "$BIN/sleep" "$ISO2/sleep"
make_ip 10.0.1.10
cp "$BIN/ip" "$ISO2/ip"
PROBE_GREP=$(run_iso "$ISO2" 10.0.1.10)
assert "probe fault (c): grep UNRESOLVABLE -> private_nic_probe_fault, not a false ready/timeout" \
  "[[ '$PROBE_GREP' == '0|private_nic_probe_fault warning' ]]"

# (d) EMPTY argument. `grep -qwF -- ""` matches every line, so an unguarded helper emits
# private_nic_ready — positive evidence that a check passed which was never performed. That is
# the inverse of the #6415 doctrine and strictly worse than the fail-open this helper intends.
make_ip 10.0.1.10
EMPTY_ARG=$(run_arm "")
assert "probe fault (d): EMPTY expected-ip -> private_nic_probe_fault, NOT a false ready" \
  "[[ '$EMPTY_ARG' == '0|private_nic_probe_fault warning' ]]"
assert "empty expected-ip never emits private_nic_ready (asserting presence on zero evidence)" \
  "[[ '$EMPTY_ARG' != *private_nic_ready* ]]"

# The #6415 mislabel this gate must not reproduce: 'could not measure' is not 'absent'.
for spec in "$PROBE" "$PROBE_EXEC" "$PROBE_GREP" "$EMPTY_ARG"; do
  assert "probe-fault case does NOT emit private_nic_timeout (#6415 mislabel guard): ${spec#*|}" \
    "[[ '$spec' != *private_nic_timeout* ]]"
done

# ── AC4(d): substring guard — BOTH directions ────────────────────────────────────────
# The dangerous direction is the second one. `expect 10.0.1.10 / host holds 10.0.1.1` yields a
# timeout with or WITHOUT -w (10.0.1.10 is not a substring of 10.0.1.1/32), so on its own it
# does not exercise -w at all. The reverse — `expect 10.0.1.1 / host holds 10.0.1.10` — is where
# a plain `grep -F` returns a false private_nic_ready and the connector registers NIC-less.
echo ""
echo "--- AC4(d): grep -qwF word-boundary guard, both directions ---"
make_ip 10.0.1.1
SUBSTR=$(run_arm 10.0.1.10)
assert "expected 10.0.1.10, host holds only 10.0.1.1 -> no match (timeout)" \
  "[[ '$SUBSTR' == '0|private_nic_timeout warning' ]]"

make_ip 10.0.1.10
SUBSTR_REV=$(run_arm 10.0.1.1)
assert "expected 10.0.1.1, host holds 10.0.1.10 -> no match (the -w guard; plain grep -F would false-READY)" \
  "[[ '$SUBSTR_REV' == '0|private_nic_timeout warning' ]]"

# ── The convergence case: absent at t=0, present at t=N ──────────────────────────────
# This is the scenario the gate exists for — the NIC attach landing after boot. Without it the
# loop is never driven and its `break` can be deleted with every other assertion still green.
echo ""
echo "--- convergence: NIC appears mid-wait -> ready, reached VIA the loop ---"
make_ip_converging 3 10.0.1.10
CONVERGE=$(run_arm 10.0.1.10)
assert "NIC appearing on probe 4 -> private_nic_ready, exit 0" \
  "[[ '$CONVERGE' == '0|private_nic_ready info' ]]"
CONV_SLEEPS=$(wc -l < "$WORK/sleep.log" | tr -d ' ')
assert "ready was reached through the wait loop, not the pre-loop probe (slept $CONV_SLEEPS times)" \
  "[[ '$CONV_SLEEPS' -ge 1 ]]"
assert "the loop broke on success rather than running the full bound (slept $CONV_SLEEPS < 30)" \
  "[[ '$CONV_SLEEPS' -lt 30 ]]"

# ── The budget: 30 x 2 s = 60 s ──────────────────────────────────────────────────────
# Load-bearing, and stubbed away unless counted. Exact equality is right here: this is a loop
# -bound constant, not a wall-clock measurement, so it is both stable and discriminating.
echo ""
echo "--- budget: the timeout arm waits exactly 30 x 2 s ---"
make_ip 10.0.1.99
TIMEOUT_B=$(run_arm 10.0.1.10)
TO_SLEEPS=$(wc -l < "$WORK/sleep.log" | tr -d ' ')
TO_ARGS=$(sort -u "$WORK/sleep.log" | paste -sd, -)
assert "timeout arm slept exactly 30 times (got $TO_SLEEPS)" "[[ '$TO_SLEEPS' == '30' ]]"
assert "every sleep was 2 seconds (distinct args: ${TO_ARGS:-<none>})" "[[ '$TO_ARGS' == '2' ]]"

# ── AC5: exactly one event per invocation ────────────────────────────────────────────
echo ""
echo "--- AC5: exactly one event per invocation (no arm emits two, none emits zero) ---"
for spec in "$READY" "$TIMEOUT" "$PROBE" "$SUBSTR" "$SUBSTR_REV" "$CONVERGE" "$TIMEOUT_B" "$PROBE_EXEC" "$PROBE_GREP" "$EMPTY_ARG"; do
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
# NOTE: deliberately NO assertion that soleur-wait-ready lacks a `nic` verb. That would pin an
# implementation SHAPE rather than a property, turning a legitimate future consolidation into a
# test-breaking change. The fail-closed disposition asserted above is the property that matters.
assert "the pre-existing cloudflared_ready fail-closed gate is unchanged" \
  "grep -qF 'soleur-wait-ready service cloudflared cloudflared_ready || exit 1' '$CI'"

# ── AC9: no reboot primitive (ADR-115 / CF-6) ────────────────────────────────────────
# web-1 is the SOLE live origin: a reboot powers off the only thing serving. ADR-115's
# converge-by-reboot grant is registry-host-scoped and explicitly not class-wide.
# Scoped to the helper + the call-site file — an unscoped diff grep would match this
# suite's own prose about reboots and could never return zero.
echo ""
echo "--- AC9: no reboot primitive on the NIC-wait path (ADR-115) ---"
# Scan CODE only. The helper's own comments explain at length why it never reboots, so an
# unstripped scan is one reworded comment ("no reboot.") away from failing a correct
# implementation — the same comment-vs-code collision this suite anchors against elsewhere.
# It passes today only because "reboots" happens to carry a trailing character the regex
# rejects, which is luck, not a guard.
grep -v '^[[:space:]]*#' "$WORK/soleur-wait-nic" > "$WORK/wait-nic.code"
assert "extracted code-only view is non-empty (comment strip did not eat the body)" \
  "[[ -s '$WORK/wait-nic.code' ]]"
assert "soleur-wait-nic CODE invokes no reboot/poweroff/shutdown" \
  "! grep -qE '(^|[^[:alnum:]_-])(reboot|poweroff|shutdown)([^[:alnum:]_-]|\$)' '$WORK/wait-nic.code'"

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
# rather than the code.
#
# The existing coherence guard (web2-recreate-preflight.sh) CANNOT be reused on the routine
# path: it hard-requires a pinned repo@sha256 ref and dies on anything else, while
# var.image_name defaults to the mutable `:latest`. So the safety argument is structural, and
# the facts it rests on are ASSERTED below rather than assumed.
#
# TWO CORRECTIONS to an earlier draft of this block, recorded because the wrong version READ as
# more reassuring than the right one:
#
#   - It claimed this was "the first PR to edit soleur-host-bootstrap.sh since that guard was
#     added". FALSE — `git log` shows 7 edits in between. The claim came from the plan and was
#     transcribed without checking: the exact "a plan-quoted fact is a claim to verify" trap.
#     It changed no conclusion, which is what made it easy to write and easy to miss.
#   - It claimed "web-1 is in no -target=, therefore a routine apply cannot create it". The
#     INFERENCE is invalid: `-target` is transitive at the resource level — the workflow states
#     this in its own comments — so hcloud_server.web IS reachable via cloudflare_record.app
#     and hcloud_firewall_attachment.web. The real guarantor is the host_creates>0 HALT
#     tripwire (#6416), which is what is asserted now. The old assertion would have stayed
#     green with that tripwire deleted.
#
# KNOWN GAP, pre-existing and deliberately NOT closed here: the warm_standby job -targets
# hcloud_server_network.web["web-1"], which transitively reaches hcloud_server.web, and its
# guard set is resource_deletes / nested_deletes / reboot_updates with NO host_creates check.
# That path could birth a host on a new bootstrap hash with no coherence preflight. It predates
# this PR and belongs to the apply workflow's guard set rather than to this gate.
#
# Residual, also not closed here: an operator-driven fresh create/-replace of web-1 consumes
# the new hash with no preflight. Closing it needs a preflight that works against a mutable
# tag — different work from this gate.
echo ""
echo "--- AC8: bake/apply coherence — the guard that actually holds ---"
WF_DIR="$DIR/../../../.github/workflows"
WF_APPLY="$WF_DIR/apply-web-platform-infra.yml"
assert "the apply workflow is present at the expected path" "[[ -f '$WF_APPLY' ]]"

# Fact (1): the edit is inert for the RUNNING host. Anchor inside hcloud_server.web's own
# lifecycle block — server.tf carries ~20 ignore_changes across ~20 resources, so a line-start
# regex alone is satisfied by any of them (verified: adding a decoy elsewhere and removing the
# real one left this green).
WEB_BLOCK=$(awk '/^resource "hcloud_server" "web"/{f=1} f{print} f&&/^}/{exit}' "$TF")
assert "hcloud_server.web block extracts non-empty" "[[ -n \"\$WEB_BLOCK\" ]]"
assert "hcloud_server.web ITSELF pins ignore_changes = [user_data, ...] (edit is inert for the running host)" \
  "grep -qE '^[[:space:]]*ignore_changes[[:space:]]*=[[:space:]]*\[user_data,' <<<\"\$WEB_BLOCK\""

# Fact (2) — CORRECTED. An earlier draft asserted "web-1 appears in no -target=, therefore the
# routine apply cannot create it". That inference is WRONG, and the workflow says so itself:
# `-target` is transitive at the RESOURCE level, so cloudflare_record.app and
# hcloud_firewall_attachment.web each pull the whole hcloud_server.web for_each map into the
# plan graph. web-1 IS target-reachable on the per-PR path.
#
# What actually prevents a birth is the host_creates TRIPWIRE in the `apply` job, added by
# #6416 — whose error text names "the host would come up with no private-net IP", i.e. exactly
# the failure this NIC gate exists to mitigate. That is the guarantor, so that is what gets
# asserted. Deleting it would leave the old assertion green while the safety argument collapsed.
HOST_CREATES_GUARD=$(grep -cE '^[[:space:]]*if[[:space:]]+\[\[[[:space:]]+"\$host_creates"[[:space:]]+-gt[[:space:]]+0' "$WF_APPLY" || true)
assert "the per-PR apply job carries the host_creates>0 HALT tripwire (found $HOST_CREATES_GUARD)" \
  "[[ '$HOST_CREATES_GUARD' -ge 1 ]]"
assert "the tripwire's counter is actually parsed from the plan (not a dangling variable)" \
  "grep -qF 'host_creates=\$(echo \"\$counts\" | jq -r' '$WF_APPLY'"

# Fact (3): no workflow targets hcloud_server.web DIRECTLY. Still worth pinning — a direct
# target would bypass the transitive-reachability reasoning entirely — but it is no longer
# carrying the whole argument. Quote-normalised: the per-merge job spells targets unquoted
# (-target=foo) while others single-quote them, so a single-spelling needle misses half the
# surface. Scanned across EVERY workflow that applies this root, not just the main one: the
# "auto-apply workflow" is a set of at least two.
WEB1_DIRECT=0
for wf in "$WF_DIR"/*.yml; do
  grep -hoE -- "-target=('?)hcloud_server\.web[^ '\\\\]*" "$wf" 2>/dev/null | tr -d "'" >> "$WORK/targets.txt" || true
done
# The ONE legitimate direct target is hcloud_server.web["web-2"], in the web-2-recreate job —
# the single path that DOES run web2-recreate-preflight.sh, so a create there is coherence-
# checked. Everything else is a finding: an unindexed `hcloud_server.web` targets every
# instance including web-1, and an explicit ["web-1"] is the live sole origin.
grep -v 'hcloud_server\.web\["web-2"\]' "$WORK/targets.txt" > "$WORK/targets-unexpected.txt" || true
WEB1_DIRECT=$(grep -c 'hcloud_server\.web' "$WORK/targets-unexpected.txt" 2>/dev/null | tr -d ' ' || true)
[ -n "$WEB1_DIRECT" ] || WEB1_DIRECT=0
DIRECT_LIST=$(sort -u "$WORK/targets-unexpected.txt" 2>/dev/null | paste -sd, - || true)
assert "no workflow -targets hcloud_server.web[web-1] or unindexed, any spelling (found ${WEB1_DIRECT}: ${DIRECT_LIST:-<none>})" \
  "[[ '$WEB1_DIRECT' == '0' ]]"
# Control on the ALLOWANCE, so the carve-out cannot silently become a blanket pass: the web-2
# entry must still be found by the extractor. If web-2's dead workflow arm is ever cleaned up
# this goes RED — correctly, because the carve-out above would then be dead code to delete,
# not a needle to fix.
WEB2_SEEN=$(grep -c 'hcloud_server\.web\["web-2"\]' "$WORK/targets.txt" 2>/dev/null | tr -d ' ' || true)
[ -n "$WEB2_SEEN" ] || WEB2_SEEN=0
assert "control: the web-2 carve-out is still live (found $WEB2_SEEN); if 0, delete the carve-out" \
  "[[ '$WEB2_SEEN' -ge 1 ]]"
# Positive control on the EXTRACTOR, not on a retired host's spelling. An earlier draft
# controlled on the web-2 needle — but web-2 is retired (var.web_hosts holds only web-1), so a
# future cleanup deleting that dead workflow arm would have RED-ed this suite while the failure
# message insisted "the needle is wrong, not the workflow". Control on the regex's ability to
# find ANY -target= at all instead; that survives host churn.
ANY_TARGET_N=$(grep -choE -- "-target=" "$WF_APPLY" | paste -sd+ - | bc 2>/dev/null || grep -cE -- "-target=" "$WF_APPLY" || true)
assert "positive control: the -target= extractor finds targets in the apply workflow (found $ANY_TARGET_N)" \
  "[[ '$ANY_TARGET_N' -ge 1 ]]"

echo ""
echo "$pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
