#!/usr/bin/env bash
#
# Drift guard for the dedicated Inngest singleton host (#6178, ADR-100). Asserts the
# load-bearing security/correctness invariants of inngest-host.tf + cloud-init-inngest.yml:
#   - FRESH signing/event keys (AC-KEYROTATE) — NOT reused from the co-located inngest.tf.
#   - Secrets on a SEPARATE Doppler PROJECT `soleur-inngest` (AC3), not a `prd` branch config.
#   - hcloud_firewall.inngest is deny-all-public (zero inbound); nftables (not the cloud
#     firewall) scopes :8288/:8289 to web-host IPs only, dropping git-data/.20 + registry/.30.
#   - NO lifecycle.ignore_changes=[user_data] (maintenance-window force-replace, ADR-100).
#   - arm64 inngest-CLI SHA override (the amd64 image-env SHA would fail the arm64 verify).
#   - Vector WIRED on this arm64 host (arm64 build + isolated-project token, #6197).
#
# Run: bash apps/web-platform/infra/inngest-host.test.sh
# Registered in .github/workflows/infra-validation.yml.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_TF="${DIR}/inngest-host.tf"
CLOUD_INIT="${DIR}/cloud-init-inngest.yml"
INNGEST_TF="${DIR}/inngest.tf"
VECTOR_TF="${DIR}/vector.tf"
BOOTSTRAP="${DIR}/inngest-bootstrap.sh"
VARIABLES_TF="${DIR}/variables.tf"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

for f in "$HOST_TF" "$CLOUD_INIT" "$INNGEST_TF" "$VECTOR_TF" "$BOOTSTRAP" "$VARIABLES_TF"; do
  [ -f "$f" ] || { echo "FAIL: required file not found: $f" >&2; exit 1; }
done

# 1. FRESH keys (AC-KEYROTATE) — the dedicated resources exist AND are distinct from the
#    co-located inngest.tf keys. A reuse would sign the new boundary with the old key (SEC-H3).
grep -qE 'resource "random_id" "inngest_signing_key_dedicated"' "$HOST_TF" \
  && grep -qE 'resource "random_id" "inngest_event_key_dedicated"' "$HOST_TF" \
  && grep -qE 'resource "random_password" "inngest_redis_password_dedicated"' "$HOST_TF" \
  && pass || fail "fresh dedicated signing/event/redis key resources present"
# The dedicated signing secret must reference the DEDICATED key, never the co-located _prd one.
# Strip COMMENT lines first — the header comments reference the co-located key BY NAME as the
# thing NOT reused (a bare grep would false-match that prose).
if grep -qE 'random_id\.inngest_signing_key_dedicated\.hex' "$HOST_TF" \
   && ! grep -vE '^[[:space:]]*#' "$HOST_TF" | grep -qE 'random_id\.inngest_(signing|event)_key_prd'; then
  pass
else
  fail "dedicated secrets reference the dedicated keys, not the co-located _prd keys"
fi

# 1b. (#6178) The host-boot token MUST be read/write, NOT read-only. The cutover flip FSM
#     (inngest-cutover-flip.sh:flag_set) advances INNGEST_CUTOVER_FLIP on soleur-inngest/prd
#     via `doppler secrets set` under this token; a read-only token fails that write at the
#     FIRST transition (flag_set flipping), so the dedicated scheduler can never complete the
#     flip. Extract the access value from the token resource block specifically (not a bare
#     file-wide grep that a comment could satisfy), so a silent revert to "read" red-lines CI.
#     The awk SKIPS in-block comment lines and requires `access` at STATEMENT position
#     (^[[:space:]]*access) — a bare `access[[:space:]]*=` match plus no comment-skip is
#     defeated by an in-block decoy comment (`# access = "read/write"`) sitting above the real
#     read-only attribute (awk matches the comment first, prints read/write, exits green).
TOKEN_ACCESS="$(awk '
  /resource "doppler_service_token" "inngest"/ { inblk=1; next }
  inblk && /^[[:space:]]*#/ { next }
  inblk && /^[[:space:]]*access[[:space:]]*=/ { gsub(/[",]/,""); print $NF; exit }
  inblk && /^}/ { exit }
' "$HOST_TF")"
[[ "$TOKEN_ACCESS" == "read/write" ]] \
  && pass || fail "doppler_service_token.inngest access must be 'read/write' so the flip FSM can write INNGEST_CUTOVER_FLIP (got '${TOKEN_ACCESS:-<none>}'); a read-only token boot-fails the flip at its first transition (#6178)"
# Cross-check: the flip script's flag_set genuinely writes under the ambient (boot-token) env —
# if flag_set ever grows an explicit --token, this test's premise (boot token authorizes the
# write) must be re-derived rather than trusted. Scope to the WHOLE flag_set function body
# (awk between `flag_set() {` and the closing `}`), not a single line — the real write spans
# two physical lines (`doppler secrets set … \` then `  --project … --silent`), so a --token
# added on the continuation line would evade a line-scoped grep.
FLAG_SET_BODY="$(awk '/^flag_set\(\)[[:space:]]*\{/{i=1} i{print} i&&/^\}/{exit}' "${DIR}/inngest-cutover-flip.sh")"
printf '%s\n' "$FLAG_SET_BODY" | grep -qE 'doppler secrets set INNGEST_CUTOVER_FLIP' \
  && ! printf '%s\n' "$FLAG_SET_BODY" | grep -qE -- '--token' \
  && pass || fail "flip flag_set must write INNGEST_CUTOVER_FLIP under the ambient boot token (no explicit --token anywhere in the function body) — else the read/write requirement above is testing the wrong credential"

# 2. Separate Doppler PROJECT (AC3), not a prd branch config.
grep -qE 'resource "doppler_project" "inngest"' "$HOST_TF" \
  && grep -qE 'name[[:space:]]*=[[:space:]]*"soleur-inngest"' "$HOST_TF" \
  && pass || fail "separate soleur-inngest Doppler project declared"
# Every dedicated doppler_secret targets that project (never a `config = "prd_inngest"` branch).
if grep -qE 'config[[:space:]]*=[[:space:]]*"prd_inngest"' "$HOST_TF"; then
  fail "dedicated secrets must NOT use a prd_inngest branch config (non-isolating, #6122)"
else
  pass
fi

# 3. Deny-all-public firewall (zero inbound rules) — intra-subnet is open by membership;
#    signature-verify is the /api/inngest boundary; nftables scopes the control API.
if awk '/resource "hcloud_firewall" "inngest"/{f=1} f&&/^}/{f=0} f' "$HOST_TF" | grep -qE 'rule[[:space:]]*\{|direction[[:space:]]*=[[:space:]]*"in"'; then
  fail "hcloud_firewall.inngest must have ZERO inbound rules (deny-all-public)"
else
  pass
fi

# 4. NO lifecycle.ignore_changes=[user_data]. Strip COMMENT lines first — the block carries a
#    "Deliberately NO ...ignore_changes=[user_data]" prose comment a bare grep would false-match.
if grep -vE '^[[:space:]]*#' "$HOST_TF" | grep -qE 'ignore_changes[[:space:]]*=[[:space:]]*\[[^]]*user_data'; then
  fail "hcloud_server.inngest must NOT set ignore_changes=[user_data] (ADR-100 force-replace)"
else
  pass
fi

# 5. Dual-arch inngest-CLI SHA (#6178): BOTH the amd64 (inngest.tf) and arm64 checksums are
#    declared; the arch is DERIVED from the server type (local.inngest_arch); and the cloud-init
#    OVERRIDES the image-env SHA with the ARCH-MATCHED value before running the bootstrap.
grep -qE 'inngest_cli_sha256[[:space:]]*=[[:space:]]*"[0-9a-f]{64}"' "$INNGEST_TF" \
  && grep -qE 'inngest_cli_sha256_arm64[[:space:]]*=[[:space:]]*"[0-9a-f]{64}"' "$INNGEST_TF" \
  && grep -qF 'startswith(var.inngest_server_type, "cax") ? "arm64" : "amd64"' "$HOST_TF" \
  && grep -qF 'local.inngest_arch == "arm64" ? local.inngest_cli_sha256_arm64 : local.inngest_cli_sha256' "$HOST_TF" \
  && grep -qF 'INNGEST_CLI_SHA256="${inngest_cli_sha256}"' "$CLOUD_INIT" \
  && grep -qF 'INNGEST_CLI_ARCH=${inngest_cli_arch}' "$CLOUD_INIT" \
  && pass || fail "dual-arch inngest-CLI SHA: amd64+arm64 locals + derived arch + arch-matched cloud-init override"

# 6. nftables scopes :8288/:8289 to web-host IPs only, rendered from the TF constant
#    local.web_host_private_ips (host.tf) into the nft saddr set via ${web_host_private_ips}.
grep -qF 'ip saddr { ${web_host_private_ips} } accept' "$CLOUD_INIT" \
  && pass || fail "nftables saddr set is rendered from local.web_host_private_ips"

# 6b. DRIFT GUARD (#6608), mirroring cutover-inngest-workflow.test.sh's var.web_hosts parity:
#     the allowlist local's IP set MUST byte-match the canonical var.web_hosts private_ip set
#     (variables.tf `default` map). This closes the "no edge to var.web_hosts" gap the issue
#     names — the literal was hardcoded and drifted when web-2 (10.0.1.11) was retired
#     2026-07-17 (#6538). Deriving the canonical set (not a second hardcoded literal) means a
#     future roster change to var.web_hosts red-lines this test until the allowlist follows.
#     `sed 's/#.*//'` strips comments BEFORE matching so a retired IP eulogized in prose
#     (variables.tf documents `# web-2 (fsn1, 10.0.1.11) RETIRED ...`) can neither be picked up
#     as a canonical member (a false-FAIL demanding the allowlist re-add .11) nor stand in for a
#     renamed/absent live local (a vacuous PASS). The CANON derivation assumes the only quoted
#     `private_ip = "10.0.1.X"` assignments in variables.tf are var.web_hosts entries (true today;
#     mirrors cutover-inngest-workflow.test.sh).
ALLOWLIST_SET=$(sed 's/#.*//' "$HOST_TF" \
  | grep -oE 'web_host_private_ips[[:space:]]*=[[:space:]]*"[0-9.,]+"' \
  | grep -oE '10\.0\.1\.[0-9]+' | sort -u | paste -sd,)
CANON_WEB_HOSTS=$(sed 's/#.*//' "$VARIABLES_TF" \
  | grep -oE 'private_ip[[:space:]]*=[[:space:]]*"10\.0\.1\.[0-9]+"' \
  | grep -oE '10\.0\.1\.[0-9]+' | sort -u | paste -sd,)
if [[ -n "$ALLOWLIST_SET" && -n "$CANON_WEB_HOSTS" && "$ALLOWLIST_SET" == "$CANON_WEB_HOSTS" ]]; then
  pass
else
  fail "web_host_private_ips ('$ALLOWLIST_SET') must equal var.web_hosts private_ip set ('$CANON_WEB_HOSTS') — roster drift (#6608)"
fi

# 6c. The web-host allowlist local must NOT contain git-data(.20)/registry(.30) (complementary
#     to the parity guard: neither peer host may ever enter the :8288/:8289 allowlist).
HOST_TF_NOCOMMENT=$(sed 's/#.*//' "$HOST_TF")
if printf '%s\n' "$HOST_TF_NOCOMMENT" | grep -qE 'web_host_private_ips[[:space:]]*=' && printf '%s\n' "$HOST_TF_NOCOMMENT" | grep -E 'web_host_private_ips[[:space:]]*=' | grep -qE '10\.0\.1\.(20|30)'; then
  fail "web_host_private_ips must NOT include git-data(.20)/registry(.30)"
else
  pass
fi

# 7. Vector WIRED, dual-arch (#6197): BOTH the amd64 (vector.tf) and arm64 SHA locals are
#    declared; the cloud-init OVERRIDES VECTOR_CLI_SHA256 with the ARCH-MATCHED value, passes
#    VECTOR_CLI_ARCH derived from the type, and stages /tmp/vector.toml so the bootstrap writes
#    the vector.service unit.
grep -qE 'vector_sha256[[:space:]]*=[[:space:]]*"[0-9a-f]{64}"' "$VECTOR_TF" \
  && grep -qE 'vector_sha256_arm64[[:space:]]*=[[:space:]]*"[0-9a-f]{64}"' "$VECTOR_TF" \
  && grep -qF 'VECTOR_CLI_SHA256=${vector_sha256}' "$CLOUD_INIT" \
  && grep -qF 'VECTOR_CLI_ARCH=${inngest_cli_arch}' "$CLOUD_INIT" \
  && grep -qF ':/vector.toml /tmp/vector.toml' "$CLOUD_INIT" \
  && pass || fail "Vector wired dual-arch — amd64+arm64 SHA locals + arch-matched cloud-init override + VECTOR_CLI_ARCH derived + /tmp/vector.toml staged"
# The DEFERRED empty VECTOR_CLI_* form must be GONE (would skip the install).
if grep -qE 'VECTOR_CLI_VERSION=""|"VECTOR_CLI_VERSION="' "$CLOUD_INIT"; then
  fail "Vector must no longer be deferred (empty VECTOR_CLI_* form is gone)"
else
  pass
fi
# The templatefile must pass the arch-conditional Vector SHA + the Doppler-CLI arch/checksum
# into the cloud-init render (dual-arch).
grep -qF 'local.inngest_arch == "arm64" ? local.vector_sha256_arm64 : local.vector_sha256' "$HOST_TF" \
  && grep -qF 'doppler_arch' "$HOST_TF" \
  && grep -qF 'doppler_sha256' "$HOST_TF" \
  && grep -qF 'doppler_$${DOPPLER_VERSION}_linux_${doppler_arch}.tar.gz' "$CLOUD_INIT" \
  && pass || fail "inngest-host.tf passes arch-conditional Vector SHA + doppler_arch/sha; cloud-init uses \${doppler_arch}"

# 8. inngest-bootstrap.sh arch-parameterizes the Vector install (#6197): VECTOR_CLI_ARCH
#    defaults amd64 (web host preserved) + an arm64->aarch64 triple map applied to BOTH the
#    download URL AND the extract path. No residual UNCONDITIONAL x86_64 literal in either.
grep -qE 'VECTOR_CLI_ARCH="\$\{VECTOR_CLI_ARCH:-amd64\}"' "$BOOTSTRAP" \
  && grep -qF 'aarch64-unknown-linux-musl' "$BOOTSTRAP" \
  && grep -qF '${vec_triple}.tar.gz' "$BOOTSTRAP" \
  && grep -qF 'vector-${vec_triple}/bin/vector' "$BOOTSTRAP" \
  && pass || fail "inngest-bootstrap.sh arch-parameterizes Vector (VECTOR_CLI_ARCH + aarch64 triple for URL + extract)"
# The URL/extract must NOT still hardcode vector-x86_64-unknown-linux-musl.
if grep -qF 'vector-x86_64-unknown-linux-musl' "$BOOTSTRAP"; then
  fail "inngest-bootstrap.sh must not hardcode vector-x86_64-unknown-linux-musl (URL/extract derive from \${vec_triple})"
else
  pass
fi

# 9. Boot isolation self-check admits BETTERSTACK_LOGS_TOKEN as a TOP-LEVEL alternation
#    member (#6197). A NESTED member would match INNGEST_BETTERSTACK_LOGS_TOKEN and fail to
#    match a bare BETTERSTACK_LOGS_TOKEN → boot-brick. The HEARTBEAT_URL)|BETTERSTACK anchor
#    proves the token is a sibling of the INNGEST_ group, not inside it. Floor rose 4->5.
grep -qF 'HEARTBEAT_URL)|BETTERSTACK_LOGS_TOKEN)' "$CLOUD_INIT" \
  && grep -qF '"$n_inngest" -lt 5' "$CLOUD_INIT" \
  && pass || fail "isolation self-check admits BETTERSTACK_LOGS_TOKEN (top-level) and the floor is -lt 5"
# The old floor must be gone.
if grep -qF '"$n_inngest" -lt 4' "$CLOUD_INIT"; then
  fail "isolation floor must be -lt 5, not the old -lt 4"
else
  pass
fi

# 9b. (#6178) BEHAVIORAL replay of the boot isolation self-check.
#     A source-text `grep -qF '<fragment>'` is NOT sufficient here: it certifies that a
#     substring exists SOMEWHERE in a ~500-line YAML, so it stays green while the live regex
#     is mutated into a no-op (grep -Ec -> grep -c), widened to admit everything
#     (^( -> ^(.*|), or reverted outright with the fragment surviving in a COMMENT. Measured:
#     5 of 8 such mutations passed the old fragment guard, including bug #6178 itself.
#     Instead, extract the guard's OWN bytes and replay its predicate over synthesized name
#     sets, so the assertions are about the decision the host actually makes.
#     Mirrors registry-boot-guard.test.sh's extract-and-replay idiom (the sibling host).
GUARD_RE="$(grep -E "n_inngest=.*grep -Ec" "$CLOUD_INIT" | grep -oE "grep -Ec '[^']*'" | sed "s/grep -Ec '//; s/'$//")"
FLOOR="$(grep -oE '\[ "\$n_inngest" -lt [0-9]+ \]' "$CLOUD_INIT" | grep -oE '[0-9]+' | head -1)"
# Non-vacuity: a failed extraction must NOT silently pass every case below. An empty GUARD_RE
# makes `grep -Ec ""` match every line, which would fake a clean replay.
[[ -n "$GUARD_RE" ]] && pass || fail "could not extract the admit-regex from $CLOUD_INIT (the replay below would be vacuous)"
[[ "$FLOOR" == "5" ]] && pass || fail "could not extract the cardinality floor, or it is not 5 (got '${FLOOR:-<empty>}') — see the DEC-FLOOR note in cloud-init-inngest.yml before changing it"

# Replays the file's exact predicate: strip DOPPLER_ builtins, then FATAL unless the visible
# non-DOPPLER set is a SUBSET of the allowlist (n_total == n_inngest) AND meets the floor.
isolation_decision() {
  local names n_total n_ing
  names="$(printf '%s\n' "$@" | grep -v '^DOPPLER_' || true)"
  n_total="$(printf '%s\n' "$names" | grep -c . || true)"
  n_ing="$(printf '%s\n' "$names" | grep -Ec "$GUARD_RE" || true)"
  if [ "$n_total" -ne "$n_ing" ] || [ "$n_ing" -lt "$FLOOR" ]; then echo FATAL; return 1; fi
  echo PASS; return 0
}

DARK5=(INNGEST_SIGNING_KEY INNGEST_EVENT_KEY INNGEST_REDIS_PASSWORD INNGEST_POSTGRES_URI BETTERSTACK_LOGS_TOKEN)
LIVE7=("${DARK5[@]}" INNGEST_CUTOVER_FLIP INNGEST_HEARTBEAT_URL)

# Dark boot (pre-arm) must PASS — the host has to bootstrap before any cutover.
[[ "$(isolation_decision "${DARK5[@]}")" == PASS ]] && pass || fail "dark 5-secret boot must PASS the isolation self-check"
# THE #6178 REGRESSION, behaviorally: op=arm adds CUTOVER_FLIP + HEARTBEAT_URL. Before the fix
# this FATALed (n_total=7 vs n_inngest=6), bricking every provision while the flip was armed.
[[ "$(isolation_decision "${LIVE7[@]}")" == PASS ]] && pass || fail "armed 7-secret set must PASS — op=arm writes INNGEST_CUTOVER_FLIP; rejecting it boot-bricks the dedicated host (#6178)"
# The QUEUED repeat: inngest-config-digest.tf declares an 8th name into the same project.
[[ "$(isolation_decision "${LIVE7[@]}" INNGEST_CONFIG_DIGEST)" == PASS ]] && pass || fail "8-secret set incl. INNGEST_CONFIG_DIGEST must PASS — inngest-config-digest.tf applies it at this cutover and requires the admitting regex to land atomically"
# Isolation still holds: an over-scoped token leaking ONE foreign name must fail closed.
[[ "$(isolation_decision "${LIVE7[@]}" SUPABASE_SERVICE_ROLE_KEY)" == FATAL ]] && pass || fail "a foreign secret must FATAL — this is the over-scoped-credential defense the self-check exists for"
# Floor still bites (catches the degenerate empty-read case where n_total==n_inngest==0).
[[ "$(isolation_decision INNGEST_SIGNING_KEY INNGEST_EVENT_KEY INNGEST_REDIS_PASSWORD INNGEST_POSTGRES_URI)" == FATAL ]] && pass || fail "a 4-name set must FATAL on the floor"
# NESTING, behaviorally: CUTOVER_FLIP must be admitted only as INNGEST_CUTOVER_FLIP.
[[ "$(isolation_decision INNGEST_SIGNING_KEY INNGEST_EVENT_KEY INNGEST_REDIS_PASSWORD INNGEST_POSTGRES_URI CUTOVER_FLIP)" == FATAL ]] && pass || fail "a BARE CUTOVER_FLIP (no INNGEST_ prefix) must FATAL — the member must be nested inside the INNGEST_ group"
# TOP-LEVEL anchor (#6197), behaviorally: BETTERSTACK_LOGS_TOKEN is a sibling of the group,
# so the INNGEST_-prefixed spelling must NOT be admitted.
[[ "$(isolation_decision INNGEST_SIGNING_KEY INNGEST_EVENT_KEY INNGEST_REDIS_PASSWORD INNGEST_POSTGRES_URI INNGEST_BETTERSTACK_LOGS_TOKEN)" == FATAL ]] && pass || fail "INNGEST_BETTERSTACK_LOGS_TOKEN must FATAL — BETTERSTACK_LOGS_TOKEN is a TOP-LEVEL member, not nested (#6197)"
# DOPPLER_* builtins are stripped before counting.
[[ "$(isolation_decision "${DARK5[@]}" DOPPLER_PROJECT DOPPLER_CONFIG)" == PASS ]] && pass || fail "DOPPLER_* builtins must be stripped before counting"

# 9c. Pin the COMPARISON OPERATOR. The replay above re-derives the predicate, so it cannot see
#     an inversion in the file itself: flipping -ne to -eq makes an isolated host FATAL and a
#     LEAKY one boot clean, with every behavioral case above still green.
# shellcheck disable=SC2016  # literal $n_total/$n_inngest is intentional — matching the file's text
grep -qF '[ "$n_total" -ne "$n_inngest" ]' "$CLOUD_INIT" \
  && pass || fail "the isolation self-check must compare with -ne (an -eq inversion admits an over-scoped credential and rejects an isolated one)"

# 10. (#6536, AC6) The dark-host heartbeat prose must NOT re-assert the false "curl no-ops"
#     claim. `curl -fsS --max-time 10 ""` exits 2 ("blank argument where content is
#     expected" — measured), it does NOT no-op. That false comment is what authorized the
#     bug: it described a no-op the code never implemented, so the dark host's oneshot
#     failed every 60s for 3 days (3,724 fires) while the comment said this was fine. The
#     no-op is now implemented EXPLICITLY, as the @@DARK_ARM@@ render in inngest-bootstrap.sh.
#     Absence-grep is safe here: the corrected prose states the measured rc=2 behaviour and
#     has no reason to restate the phrase.
if grep -qi 'curl no-ops' "$HOST_TF"; then
  fail "inngest-host.tf must not claim the dark host's heartbeat curl no-ops (it exits 2 — #6536)"
else
  pass
fi
# The corrected prose must actually name the measured behaviour + its owner, so this is a
# record-correction rather than a silent deletion of the claim.
grep -qE 'exits? 2' "$HOST_TF" \
  && grep -qF '#6536' "$HOST_TF" \
  && grep -qF 'inngest-bootstrap.sh' "$HOST_TF" \
  && pass || fail "inngest-host.tf must state the measured rc=2 truth, cite #6536, and name where the skip is implemented"

# 11. (plan CF-2) The bootstrap pull must be VERIFIED-BY-CONSTRUCTION, and the file must not
#     claim a verification it does not perform. Same shape as item 10 above, one file over:
#     `grep -n cosign cloud-init-inngest.yml` returned exactly ONE hit and it was a comment
#     asserting the cold-boot pull was cosign-verified. It never was. The real path is
#     IREF -> docker pull -> docker create/cp -> `bash inngest-bootstrap.sh` AS ROOT, with no
#     signature check anywhere; build-inngest-bootstrap-image.yml says outright that this
#     image is not signed. The claim survived long enough that the PLAN for this change
#     inherited it from the comment and restated it as an acceptance criterion — which is the
#     whole reason a false comment is treated here as a defect and not as untidiness.
#
#     Two assertions, because either alone is defeatable:
#       (a) no cosign VERIFICATION may be claimed unless one is actually executed. Stated as
#           an implication rather than a flat absence, so the day someone ships a real
#           `cosign verify` the guard permits the prose that describes it.
#       (b) the pull is digest-pinned. This is the substantive control the false comment stood
#           in for: `@sha256:` names immutable bytes, so a mutable tag cannot be re-pointed at
#           a different root-executed payload between the build and a host replace.
if grep -qE 'cosign[- ]verif' "$CLOUD_INIT" && ! grep -qE '^[[:space:]]*cosign verify[[:space:]]' "$CLOUD_INIT"; then
  fail "cloud-init-inngest.yml claims a cosign verification but executes none (CF-2 — the claim was false for months)"
else
  pass
fi
# Record-correction, not silent deletion (mirrors item 10's second leg): the corrected prose
# must name the absence, cite its issue, and name what replaced it.
grep -qE 'NO SIGNATURE VERIFICATION ON THIS PATH' "$CLOUD_INIT" \
  && grep -qF 'CF-2' "$CLOUD_INIT" \
  && grep -qE 'DIGEST PIN' "$CLOUD_INIT" \
  && pass || fail "cloud-init-inngest.yml must state that no signature verification exists, cite CF-2, and name the digest pin that replaces it"
# Anchored on the ASSIGNMENT construct, not a bare `@sha256:` token — the comments above it
# discuss the digest pin in prose, and a token grep would pass on that prose alone with the
# assignment still on a mutable tag. The tag is retained ahead of the digest deliberately: it
# keeps the `soleur-inngest-bootstrap:vX.Y.Z` pin-drift guard in
# cloud-init-inngest-bootstrap.test.sh armed, and docker resolves by the digest regardless.
grep -qE '^[[:space:]]*IREF=ghcr\.io/jikig-ai/soleur-inngest-bootstrap:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}$' "$CLOUD_INIT" \
  && pass || fail "IREF must be digest-pinned (repo:vX.Y.Z@sha256:<64-hex>) — CF-2: a mutable tag gates a root-executed payload on nothing but GHCR TLS"

echo ""
echo "=== inngest-host.test.sh: ${passes} passed, ${fails} failed ==="
[ "$fails" -eq 0 ] || exit 1
