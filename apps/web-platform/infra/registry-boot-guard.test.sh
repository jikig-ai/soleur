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
LINE_ASSIGN="$(grep -F 'LINE="SOLEUR_ZOT_DISK' "$CI" | head -1)"
assert "LINE=\"SOLEUR_ZOT_DISK assignment found" "[ -n \"\$LINE_ASSIGN\" ]"
for f in pcent= fs_size_gb= block_size_gb= resize_ok= zot_restarts= ping_rc= \
         mem_total_mb= zot_anon_mb= zot_oom_kills= state_status= oom_killed= exit_code= \
         oom_kills_5m= zot_last_err= boot_id= htpasswd_pull_matches= htpasswd_push_matches=; do
  assert "SOLEUR_ZOT_DISK LINE carries field ${f}" "grep -qF '${f}' <<<\"\$LINE_ASSIGN\""
done

# --- #6497: the htpasswd-divergence probe -------------------------------------------------
# zot-disk-heartbeat.sh runs `set -u`. A BARE "$ZOT_PULL_TOKEN" on an unset token raises
# `unbound variable` and EXITS the script before $LINE is built — taking the ENTIRE
# SOLEUR_ZOT_DISK self-report dark (every field above, not just the probe's) and bypassing the
# trailing `exit 0` that exists so the cron can never wedge. `|| HTP_PULL=false` does NOT
# rescue it: an expansion error is not a command failure. Since this heartbeat's ABSENCE is
# itself an alarm, that failure pages "host down" when only the probe broke. This shipped in
# #6497's first draft and was caught at review — pin it so it cannot come back.
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

# The container fields are positionally coupled: `read -r ID ZOT_RESTARTS STATE_STATUS OOM_KILLED
# EXIT_CODE` must match the `docker inspect -f` template column order, else oom_killed/exit_code
# transpose silently (values still look plausible in telemetry). Pin the exact 5-field template.
assert "docker inspect -f template order matches the read target order" \
  "grep -qF \"docker inspect -f '{{.Id}} {{.RestartCount}} {{.State.Status}} {{.State.OOMKilled}} {{.State.ExitCode}}' zot\" '$CI'"
assert "read targets are in the same order as the inspect template" \
  "grep -qF 'read -r ID ZOT_RESTARTS STATE_STATUS OOM_KILLED EXIT_CODE' '$CI'"

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

echo ""
echo "=== registry-boot-guard.test.sh: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ] || exit 1
