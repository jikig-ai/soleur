#!/usr/bin/env bash
# Tests the zot registry-host cloud-init boot-guard + disk-observability + resize2fs
# hardening added in #6240/#6244 (cloud-init-registry.yml).
#
# TWO layers:
#   1. BEHAVIORAL (the load-bearing part): the boot isolation self-check now expects FOUR
#      admitted secrets {ZOT_PULL_TOKEN, ZOT_PUSH_TOKEN, BETTERSTACK_LOGS_TOKEN, REGISTRY_LUKS_KEY}
#      (#6895 added the guest-LUKS passphrase to the isolated config). This test EXTRACTS the
#      admit-regex + the cardinality integer FROM cloud-init-registry.yml (so the decision logic
#      under test is the SAME bytes the host boots with — no re-derived copy to drift) and
#      evaluates the guard's exact predicate against synthesized name-sets. The 3-secret set (the
#      OLD cardinality) must now FATAL — that is the RED→GREEN behavioral change this fix ships.
#      Fixtures are SYNTHESIZED (cq-test-fixtures-synthesized-only).
#   2. STRUCTURAL grep assertions: resize2fs fail-loud (no `|| true`), device-wait, e2fsprogs,
#      .resize-result persistence, the SOLEUR_ZOT_DISK field set, the `doppler run` cron wrap,
#      and the tightened gc/retention values.
#
# Static + pure-bash — no docker, no network, no doppler.
#
# Run: bash apps/web-platform/infra/registry-boot-guard.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI="$SCRIPT_DIR/cloud-init-registry.yml"

PASS=0
FAIL=0
assert() {
  local desc="$1" cond="$2"
  if eval "$cond"; then PASS=$((PASS + 1)); echo "  PASS: $desc"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $desc"; echo "        condition: $cond"; fi
}

echo "=== registry boot-guard + disk-observability (#6240/#6244) tests ==="
assert "cloud-init-registry.yml exists" "[[ -f '$CI' ]]"

# --- Extract the guard's admit-regex + cardinality straight from the file (no drift) ---
GUARD_RE="$(grep -F 'n_admitted=' "$CI" | grep -oE "grep -Ec '[^']*'" | sed "s/grep -Ec '//; s/'$//")"
# shellcheck disable=SC2016  # literal $n_total is intentional — we grep the file's own guard text
CARD="$(grep -oE '\[ "\$n_total" -ne [0-9]+ \]' "$CI" | grep -oE '[0-9]+' | head -1)"
echo "--- extracted: admit-regex='${GUARD_RE}' cardinality='${CARD}' ---"
assert "admit-regex was extracted" "[[ -n '$GUARD_RE' ]]"
assert "cardinality extracted and == 4" "[[ '$CARD' == '4' ]]"
assert "admit-regex names BETTERSTACK_LOGS_TOKEN" "grep -q 'BETTERSTACK_LOGS_TOKEN' <<<'$GUARD_RE'"
assert "admit-regex names REGISTRY_LUKS_KEY (#6895)" "grep -q 'REGISTRY_LUKS_KEY' <<<'$GUARD_RE'"

# guard_decision: replays the file's exact predicate (strip DOPPLER_ builtins, count total +
# admitted, FATAL unless both == CARD). Prints PASS/FATAL; returns 0 on PASS.
guard_decision() {
  local names n_total n_admitted
  names="$(printf '%s\n' "$@" | grep -v '^DOPPLER_' || true)"
  n_total="$(printf '%s\n' "$names" | grep -c . || true)"
  n_admitted="$(printf '%s\n' "$names" | grep -Ec "$GUARD_RE" || true)"
  if [ "$n_total" -ne "$CARD" ] || [ "$n_admitted" -ne "$CARD" ]; then echo FATAL; return 1; fi
  echo PASS; return 0
}

echo "--- behavioral: boot isolation self-check decision ---"
# The exact isolated 4-secret set → PASS (#6895 added REGISTRY_LUKS_KEY).
assert "the 4 admitted secrets PASS the guard" \
  "[[ \"\$(guard_decision ZOT_PULL_TOKEN ZOT_PUSH_TOKEN BETTERSTACK_LOGS_TOKEN REGISTRY_LUKS_KEY)\" == PASS ]]"
# The OLD 3-secret set is now rejected (the RED→GREEN behavioral change: cardinality raised 3->4).
assert "the OLD 3-secret set now FATALs (cardinality raised 3->4)" \
  "[[ \"\$(guard_decision ZOT_PULL_TOKEN ZOT_PUSH_TOKEN BETTERSTACK_LOGS_TOKEN)\" == FATAL ]]"
# An over-scoped credential leaks a foreign secret → n_total=5 → FATAL (fail-closed).
assert "an over-scoped 5th (foreign) secret FATALs" \
  "[[ \"\$(guard_decision ZOT_PULL_TOKEN ZOT_PUSH_TOKEN BETTERSTACK_LOGS_TOKEN REGISTRY_LUKS_KEY SUPABASE_SERVICE_ROLE_KEY)\" == FATAL ]]"
# Right count (4) but wrong identity (a non-admitted name) → FATAL (identity, not just cardinality).
assert "4 names but wrong identity FATALs (identity assert)" \
  "[[ \"\$(guard_decision ZOT_PULL_TOKEN ZOT_PUSH_TOKEN BETTERSTACK_LOGS_TOKEN FOO_TOKEN)\" == FATAL ]]"
# DOPPLER_* builtins are stripped before counting (so they do not inflate n_total).
assert "DOPPLER_* builtins are stripped before counting" \
  "[[ \"\$(guard_decision ZOT_PULL_TOKEN ZOT_PUSH_TOKEN BETTERSTACK_LOGS_TOKEN REGISTRY_LUKS_KEY DOPPLER_PROJECT DOPPLER_CONFIG)\" == PASS ]]"

echo "--- structural: resize2fs fail-loud (#6240) ---"
# #6895: resize2fs now targets the LUKS MAPPER (/dev/mapper/registry), not the raw $DEV — a raw
# resize2fs would hit the LUKS header. The exit code is still captured in an `if` (not swallowed).
assert "resize2fs is invoked in an if targeting the mapper (exit code captured, not swallowed)" \
  "grep -qE 'if resize2fs /dev/mapper/registry; then' '$CI'"
# The silent-swallow was `resize2fs ... || true` on a COMMAND line; the historical comment that
# documents the old bug legitimately still contains that string, so exclude comment lines first.
assert "no 'resize2fs ... || true' silent-swallow on any command line" \
  "! grep -vE '^[[:space:]]*#' '$CI' | grep -qE 'resize2fs.*\\|\\| true'"
assert "device-wait loop precedes mount (attach race)" \
  "grep -qE 'for i in \\\$\\(seq 1 30\\); do \\[ -b \"\\\$DEV\" \\]' '$CI'"
assert "e2fsprogs is in packages:" "grep -qE '^[[:space:]]*-[[:space:]]*e2fsprogs' '$CI'"
assert "e2fsprogs runcmd dpkg re-ensure guard present (packages: stage non-fatal)" \
  "grep -qE 'dpkg -s e2fsprogs' '$CI'"
# #6895: the old ext4-on-raw lsblk `^part` invariant is REPLACED by the D1/Option B blkid TYPE
# discriminator — the raw device must be "" (fresh, -> luksFormat) or crypto_LUKS (reuse); any
# other TYPE FATALs (refuse to wipe a plaintext volume the host-replace preserve-path kept).
assert "raw-device blkid TYPE discriminator present (fresh/crypto_LUKS/else-FATAL)" \
  "grep -qE 'blkid -o value -s TYPE \"\\\$DEV\"' '$CI' && grep -qE 'crypto_LUKS\\)' '$CI' && grep -qF 'refusing-non-luks-device' '$CI'"
assert ".resize-result is persisted for the reporter" \
  "grep -qF '/var/lib/zot/.resize-result' '$CI'"

echo "--- structural: SOLEUR_ZOT_DISK self-report (#6244) ---"
assert "SOLEUR_ZOT_DISK marker line emitted" "grep -qF 'SOLEUR_ZOT_DISK pcent=' '$CI'"
# Tie each field to the LINE="SOLEUR_ZOT_DISK assignment ITSELF, not anywhere-in-file (Kieran P2:
# the old anywhere grep false-passes a field named only in a comment). LINE= is one physical line.
# shellcheck disable=SC2034  # used inside the eval'd `assert` condition strings below (shellcheck can't see it)
LINE_ASSIGN="$(grep -F 'LINE="SOLEUR_ZOT_DISK' "$CI" | head -1)"
assert "LINE=\"SOLEUR_ZOT_DISK assignment found" "[ -n \"\$LINE_ASSIGN\" ]"
# zot_uptime_s + zot_last_err_src (#7247): the two ambiguity discriminators. Guarded here so
# neither can be silently dropped — without zot_uptime_s, `exit_code=0 state_status=running` is
# unfalsifiable mid-loop; without zot_last_err_src, a routine-traffic FALLBACK is indistinguishable
# from a real match and a downstream alarm will print it as the crash cause (ADR-166).
for f in pcent= fs_size_gb= block_size_gb= resize_ok= zot_restarts= ping_rc= \
         mem_total_mb= zot_anon_mb= zot_oom_kills= state_status= oom_killed= exit_code= \
         zot_uptime_s= zot_last_err_src= \
         oom_kills_5m= zot_last_err= boot_id= zot_image_digest= htpasswd_pull_matches= htpasswd_push_matches=; do
  assert "SOLEUR_ZOT_DISK LINE carries field ${f}" "grep -qF '${f}' <<<\"\$LINE_ASSIGN\""
done
# zot_last_err MUST be the LAST field. This is a SECURITY invariant, not cosmetics:
# scripts/lib/zot-telemetry-parse.sh strips `zot_last_err=` and everything after it so a crafted
# zot log line cannot spoof boot_id=/exit_code=137. Any field emitted after it is (a) outside the
# trusted region and (b) invisible to every consumer. This had ZERO coverage before #7247 — the
# first field insertion next to it got the placement right, and nothing would have caught it if
# it had not.
assert "zot_last_err is the LAST field in the LINE (trusted-region boundary)" \
  "[[ \"\$LINE_ASSIGN\" == *'zot_last_err=\$ZOT_LAST_ERR\"' ]]"

# --- #6497: the htpasswd-divergence probe -------------------------------------------------
# zot-disk-heartbeat.sh runs `set -u`. A BARE "$ZOT_PULL_TOKEN" on an unset token raises
# `unbound variable` and EXITS the script before $LINE is built — taking the ENTIRE
# SOLEUR_ZOT_DISK self-report dark (every field above, not just the probe's) and bypassing the
# trailing `exit 0` that exists so the cron can never wedge. `|| HTP_PULL=false` does NOT
# rescue it: an expansion error is not a command failure. Since this heartbeat's ABSENCE is
# itself an alarm, that failure pages "host down" when only the probe broke. This shipped in
# #6497's first draft and was caught at review — pin it so it cannot come back.
# shellcheck disable=SC2034  # used inside the eval'd `assert` condition strings below (shellcheck can't see it)
PROBE_BLOCK="$(awk '/_htp_verify\(\) \{/,/^      fi$/' "$CI")"
assert "htpasswd probe block found" "[ -n \"\$PROBE_BLOCK\" ]"
assert "probe never expands a token BARE (set -u would kill the whole heartbeat)" \
  "! grep -qE '\"\\\$(ZOT_PULL_TOKEN|ZOT_PUSH_TOKEN)\"' <<<\"\$PROBE_BLOCK\""
assert "probe expands both tokens with a :- default" \
  "[ \"\$(grep -cE '\\\$\\\$\\{ZOT_(PULL|PUSH)_TOKEN:-\\}' <<<\"\$PROBE_BLOCK\")\" -ge 2 ]"
# `unknown` must be the DEFAULT, not a post-hoc correction: "cannot tell" is never conflated
# with "does not match". htpasswd -vb exits 3 on a real mismatch but 6 on user-absent and 127
# if apache2-utils vanished — collapsing every non-zero into `false` would report a confident
# "the credential diverged" when a cloud-init edit merely renamed the htpasswd user, sending
# the operator to rotate a credential that was never stale (measured on ubuntu:24.04).
assert "probe defaults both fields to unknown before probing" \
  "grep -qE 'HTP_PULL=unknown; *HTP_PUSH=unknown' <<<\"\$PROBE_BLOCK\""
assert "probe maps ONLY exit 3 to false (not every non-zero)" \
  "grep -qE '^\\s*3\\) printf .false. ;;' <<<\"\$PROBE_BLOCK\""
assert "probe emits a boolean/sentinel only — never the token" \
  "! grep -qE 'printf .*ZOT_(PULL|PUSH)_TOKEN|echo .*ZOT_(PULL|PUSH)_TOKEN' <<<\"\$PROBE_BLOCK\""

# The container fields are positionally coupled: the `read -r` targets must match the
# `docker inspect -f` template column order, else oom_killed/exit_code transpose silently
# (values still look plausible in telemetry). Pin the exact template.
#
# Extended 2026-08-05 (#7282) from 6 to 7 fields: `{{.Config.Image}}` -> ZOT_IMAGE_REF, which
# feeds zot_image_digest — the only off-host way to tell which zot binary production is
# actually running, on a host with no shell and no SSH. It JOINS this call rather than adding
# a second inspect, per the one-inspect invariant #7247 documents.
#
# This guard did its job on that change: it caught the extension because the assertion is a
# grep -qF of the WHOLE template, not a per-field check. Keep it that way — a per-field or
# regex form would let a reordering through, which is the exact silent transposition the
# positional coupling makes possible.
assert "docker inspect -f template order matches the read target order" \
  "grep -qF \"docker inspect -f '{{.Id}} {{.RestartCount}} {{.State.Status}} {{.State.OOMKilled}} {{.State.ExitCode}} {{.State.StartedAt}} {{.Config.Image}}' zot\" '$CI'"
assert "read targets are in the same order as the inspect template" \
  "grep -qF 'read -r ID ZOT_RESTARTS STATE_STATUS OOM_KILLED EXIT_CODE STARTED_AT ZOT_IMAGE_REF' '$CI'"

# The cap is DERIVED from var.registry_server_type (zot-registry.tf local.registry_memory_cap_mb),
# not hardcoded. It was the literal 7168m with no edge to the server type, so a 4 GB host would
# have kept a cap that can never bind on 4096m of RAM — silently the uncapped-on-cx23 condition
# that caused #6288. Pin the derivation (and the absence of the literal) so it cannot regress.
assert "zot container --memory cap comes from the templated zot_memory_cap_mb, not a literal" \
  "grep -qF 'ZOT_MEMORY_CAP:-\${zot_memory_cap_mb}m' '$CI'"
# Comments still cite 7168m deliberately (they explain what the literal WAS and why deriving
# replaced it) — the regression this guards is a literal creeping back into executable shell.
assert "no hardcoded 7168m cap literal on any non-comment line" \
  "! grep -vE '^[[:space:]]*#' '$CI' | grep -qF '7168m'"
# The probe must compare against the cap zot is ACTUALLY under, not a copy — a gate holding a
# stale 7168 while the container is capped at 3072 tests an unreachable ceiling and rubber-stamps
# a starved host. Read from the live cgroup, and reported in the telemetry the gate consumes.
assert "the cap is read from the container's live cgroup memory.max" \
  "grep -qF 'cap_bytes=\$(cat \"\$cg/memory.max\" 2>/dev/null)' '$CI'"
assert "zot_memory_cap_mb is reported in the SOLEUR_ZOT_DISK payload" \
  "grep -qF 'zot_memory_cap_mb=\$ZOT_MEMORY_CAP_MB' '$CI'"
# UNCAPPED must be distinguishable from UNKNOWN. cap_mb cannot express it: -1 is the parse lib's
# drop-sentinel (zot-telemetry-parse.sh:48 drops every negative) and 0 would read as "capped at
# nothing". Collapsing them makes an uncapped container look mid-restart, so the gate assumes a cap
# and can never alarm on zot running with none — #6288's root condition, invisible.
assert "memory.max=='max' reports zot_memory_capped=false (UNCAPPED), distinct from unknown" \
  "grep -qE '^ *max\\) *ZOT_MEMORY_CAPPED=false' '$CI'"
assert "a numeric memory.max reports zot_memory_capped=true" \
  "grep -qF 'ZOT_MEMORY_CAPPED=true' '$CI'"
assert "zot_memory_capped defaults to unknown (cgroup absent != uncapped)" \
  "grep -qF 'ZOT_MEMORY_CAPPED=unknown' '$CI'"
assert "zot_memory_capped is reported in the SOLEUR_ZOT_DISK payload" \
  "grep -qF 'zot_memory_capped=\$ZOT_MEMORY_CAPPED' '$CI'"
# NB: leading '--' anchor dropped so grep/ugrep doesn't parse it as an option.
assert "docker run carries --memory + --memory-swap == the cap (deterministic cgroup-OOM)" \
  "grep -qF 'memory \"\$ZOT_MEMORY_CAP\" --memory-swap \"\$ZOT_MEMORY_CAP\"' '$CI'"

echo "--- structural: #6288 new-field brace-escaping (no single-brace templatefile leak) ---"
# AC7: every NEW shell var must be $$-escaped wherever it is brace-formed — a single-brace ${VAR}
# is consumed by templatefile() as a TF-var interpolation and fails `terraform plan`. Scope to the
# NEW var names ONLY (NOT a blanket ${...} grep — the reporter legitimately carries the
# ${disk_heartbeat_url}/${betterstack_ingest_url}/${zot_pull_user} TF interpolations). Fixed-string
# counting (no fragile PCRE lookbehind): every "${VAR" substring must be covered by a "$${VAR"
# double-escape, so count("${VAR") must equal count("$${VAR"). A bare single-brace usage lifts the
# single count above the double count → FAIL. Non-brace usages ($VAR) contribute 0 to both.
for v in MEM_TOTAL_KB MEM_TOTAL INSPECT ID STATE_STATUS OOM_KILLED \
         EXIT_CODE CGROUP_ROOT ZOT_ANON_MB ZOT_OOM_KILLS OOM_KILLS_5M ZOT_LAST_ERR BOOT_ID ZOT_MEMORY_CAP; do
  n_single=$(grep -oF "\${$v" "$CI" | wc -l | tr -d ' ')
  n_double=$(grep -oF "\$\${$v" "$CI" | wc -l | tr -d ' ')
  assert "new var \$$v is \$\$-escaped wherever brace-formed (single=$n_single double=$n_double)" \
    "[ '$n_single' = '$n_double' ]"
done
assert "ships via Better Stack Logs Authorization: Bearer token" \
  "grep -qF 'Authorization: Bearer \$TOKEN' '$CI'"
assert "cron wraps the reporter in doppler run (isolated soleur-registry/prd)" \
  "grep -qF 'doppler run --project soleur-registry --config prd -- /usr/local/bin/zot-disk-heartbeat.sh' '$CI'"
assert "absence-based <85% liveness ping retained" "grep -qE '\"\\\$USE\" -lt 85' '$CI'"

echo "--- structural: gc/retention TIMING preserved (#6240 defense-in-depth) ---"
assert "gcInterval tightened to 1h" "grep -qF '\"gcInterval\": \"1h\"' '$CI'"
assert "gcInterval no longer 24h" "! grep -qF '\"gcInterval\": \"24h\"' '$CI'"
assert "retention.delay tightened to 2h" "grep -qF '\"delay\": \"2h\"' '$CI'"
assert "gcDelay dangling-blob safety window preserved at 1h" "grep -qF '\"gcDelay\": \"1h\"' '$CI'"
assert "deleteReferrers stays false (tag-based sigs, not Subject referrers)" "grep -qF '\"deleteReferrers\": false' '$CI'"

echo "--- structural: capacity-vs-retention keep-set (#6247) ---"
# Anchor on the keepTags JSON fragments, NOT comment prose (the narrative block also names
# sha256-* / 5 / 50). The invariant under test: the previously-UNBOUNDED sha256-.* keep is now
# BOUNDED, and v*/commit-sha counts are lowered 10->5.
assert "sha256-.* cosign referrer keep-set now BOUNDED (was unbounded 'keep forever')" \
  "grep -qF '\"patterns\": [\"sha256-.*\"], \"mostRecentlyPushedCount\": 50' '$CI'"
assert "v* tag keep-set lowered to 5" \
  "grep -qF '\"patterns\": [\"v.*\"], \"mostRecentlyPushedCount\": 5' '$CI'"
assert "commit-sha tag keep-set lowered to 5" \
  "grep -qF '\"patterns\": [\"[0-9a-f]{7,64}\"], \"mostRecentlyPushedCount\": 5' '$CI'"
assert "no keepTags count left at the old value 10" \
  "! grep -qE '\"mostRecentlyPushedCount\": 10\\b' '$CI'"

echo "--- structural: the registry host type this cloud-init is rendered for (#7309) ---"
# Two facts the rest of this file ASSUMES about var.registry_server_type.
#
#   R1  the declared default is the type of record. #7309 repinned cx23 -> cpx22.
#   R2  the default is not a `cax*` type, so zot-registry.tf's local.registry_arch derives
#       amd64. That derivation selects local.zot_image between two DISTINCT OCI repositories,
#       so an arch flip darks the sole pull path (ADR-169).
#
# WHAT R2 DOES AND DOES NOT PIN, stated honestly because the first draft of this comment got it
# wrong. On the tree as committed R2 is IMPLIED BY R1: R1 pass => the value is exactly cpx22 =>
# not cax* => R2 pass, so there is no input where R1 passes and R2 fails and R2 contributes no
# gate signal today. It earns its place in exactly one future state — a repin to a `cax*` type
# that updates R1's literal in the same edit, which turns R1 green and leaves R2 as the sole
# red. Because that is the state R2 exists for, R2 must carry its own non-emptiness guard: once
# R1 is retargeted, nothing else covers an extraction that returns "".
#
# R2 pins the INPUT to the derivation, never the derivation. local.registry_arch's orientation is
# was unasserted anywhere in this repo until R3 below — measured: inverting its ternary, and
# deleting the local outright, both left this suite and zot-image-staleness / git-data-luks /
# registry-luks green (86/0, 15/0, 133/0, 34/0). R3 closes that. The two SIBLING consumers of
# the same derivation (local.doppler_sha256, and registry-userdata-budget.sh's hardcoded
# zot_image_amd64 branch) are still uncovered — #7335.
#
# The repin's rationale, probe series and sources are SINGLE-SOURCED at zot-registry.tf, anchor
# "STOCK REALITY". Do not restate them here: an earlier version of this comment did, drifted
# from that table inside one PR, and shipped a count ("three times") the table never supported.
VARS="$SCRIPT_DIR/variables.tf"
assert "variables.tf exists (R1/R2 input)" "[[ -f '$VARS' ]]"
# COMMENT-STRIPPED, BLOCK-SCOPED, value taken from the ASSIGNMENT — never `$NF`, which on
# `default = "cpx22" # was cx23` is the COMMENT's last word. Same extraction as
# git-data-luks.test.sh A17, which was built after exactly that defect. Block scoping is
# load-bearing and measured: a bare file-wide `grep '^\s*default = "cpx22"'` returns 2 on the
# UNMODIFIED tree (git_data_server_type and inngest_server_type both default to cpx22), so it is
# green even with this variable's own default deleted. Takes the path as $1 rather than
# capturing $VARS so a mutation harness can re-run it against a broken copy.
_registry_default() {
  sed 's/[[:space:]]#.*$//' "$1" \
    | awk '/^variable "registry_server_type"/{i=1}
           i&&/^[[:space:]]*default[[:space:]]*=/{
             sub(/^[^=]*=[[:space:]]*/, ""); gsub(/[",[:space:]]/, ""); print; exit
           }
           i&&/^}/{exit}'
}
REGISTRY_DEFAULT="$(_registry_default "$VARS")"
echo "--- extracted: registry_server_type default='${REGISTRY_DEFAULT}' ---"
assert "R0: the extraction returned a value (guards R1/R2 against a silent parse failure)" \
  "[ -n '$REGISTRY_DEFAULT' ]"
assert "R1: var.registry_server_type default is cpx22 (#7309 repin)" \
  "[ '$REGISTRY_DEFAULT' = 'cpx22' ]"
assert "R2: the default is not a cax* type, so local.registry_arch derives amd64" \
  "[ -n '$REGISTRY_DEFAULT' ] && case '$REGISTRY_DEFAULT' in cax*) false ;; *) true ;; esac"

# R3: the arch DERIVATION is oriented correctly — the assertion R2 cannot make.
#
# `local.registry_arch = startswith(var.registry_server_type, "cax") ? "arm64" : "amd64"` selects
# local.zot_image between two DISTINCT OCI repositories, and a manifest digest resolves only
# within its own, so an inverted ternary 404s the pull (MANIFEST_UNKNOWN) and darks the sole pull
# path (ADR-169). A "the local is declared" grep cannot see an inversion. Mirrors
# git-data-luks.test.sh A16; extract the prefix and BOTH branch values, then replay the decision
# over a synthesized type space (cq-test-fixtures-synthesized-only — this pins the DERIVATION,
# not today's Hetzner stock).
#
# `ca99` PINS THE PREFIX LENGTH and is the only fixture that does. A16's history is the argument:
# its comment once claimed four cax members stop a truncated "ca" from passing, and that was
# measured FALSE — cax11/21/31/41 all start with "ca", so widening the prefix kept the suite
# green. Cardinality is not discrimination. A synthesized type starting with "ca" that is NOT
# Ampere is the single input that separates the two prefixes.
p_registry_arch_derivation() {
  local expr pfx tval fval pair t exp got
  # Anchored on the ASSIGNMENT at line-start: that distinguishes a DECLARATION from a reference
  # such as `zot_image = local.registry_arch == "arm64" ? ...` two lines below, whose `==` an
  # unanchored `registry_arch[[:space:]]*=` would match first and read as the declaration.
  expr="$(sed -E 's;(^|[[:space:]])//.*;;; s;#.*;;' "$1" | grep -E '^[[:space:]]*registry_arch[[:space:]]*=' | head -1)"
  [ -n "$expr" ] || { echo 0; return; }
  pfx="$(printf '%s' "$expr" | grep -oE 'startswith\(var\.registry_server_type,[[:space:]]*"[a-z]+"\)' | grep -oE '"[a-z]+"' | tr -d '"')"
  tval="$(printf '%s' "$expr" | grep -oE '\?[[:space:]]*"[a-z0-9]+"' | grep -oE '"[a-z0-9]+"' | tr -d '"')"
  fval="$(printf '%s' "$expr" | grep -oE ':[[:space:]]*"[a-z0-9]+"' | grep -oE '"[a-z0-9]+"' | tr -d '"')"
  # Non-vacuity: a partial extraction must fail loudly, never replay vacuously.
  { [ -n "$pfx" ] && [ -n "$tval" ] && [ -n "$fval" ]; } || { echo 0; return; }
  for pair in "cax11:arm64" "cax21:arm64" "cax31:arm64" "cax41:arm64" \
              "ca99:amd64" \
              "cpx22:amd64" "cx23:amd64" "cx33:amd64" "ccx13:amd64"; do
    t="${pair%%:*}"; exp="${pair##*:}"
    case "$t" in "$pfx"*) got="$tval" ;; *) got="$fval" ;; esac
    [ "$got" = "$exp" ] || { echo 0; return; }
  done
  echo 1
}
assert "R3: local.registry_arch derivation is oriented correctly (catches an INVERTED ternary)" \
  "[ \"\$(p_registry_arch_derivation '$SCRIPT_DIR/zot-registry.tf')\" = 1 ]"

echo ""
echo "=== registry-boot-guard.test.sh: ${PASS} passed, ${FAIL} failed ==="
# ANTI-VACUITY FLOOR. The gate below reads FAIL only, so anything that stops assertions from
# RUNNING passes it: neutering assert() to a no-op was measured to print "0 passed, 0 failed"
# and exit 0, and this suite is a REQUIRED check (infra-validation.yml). Deleting a whole block
# is the same class. A FLOOR, not equality — a new assertion must never be a spurious failure.
# Set to the full count at the time of writing; raise it in lockstep, never lower it to pass.
MIN_ASSERTIONS=88
if [ "$((PASS + FAIL))" -lt "$MIN_ASSERTIONS" ]; then
  echo "FATAL: only $((PASS + FAIL)) assertions ran, expected >= ${MIN_ASSERTIONS}." >&2
  echo "       The suite was stranded, not clean — a green exit here would assert nothing." >&2
  exit 1
fi
[ "$FAIL" -eq 0 ] || exit 1
