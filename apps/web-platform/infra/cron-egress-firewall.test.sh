#!/usr/bin/env bash
# Drift-guard for the container egress firewall (#5046 PR-2).
#
# Locks the load-bearing invariants of the DOCKER-USER egress allowlist:
#   1. server.tf DELIVERS every firewall artifact (anchored on the delivery
#      construct `source = "${path.module}/<file>"` + its destination — never
#      a bare path, which false-passes when it also appears in chmod/comment
#      lines; see 2026-06-02 drift-guard learning).
#   2. triggers_replace folds BOTH the artifact hashes AND the server id
#      (hr-fresh-host-provisioning — a replaced VM must re-provision).
#   3. The apply workflow -targets the new resource in the SSH block
#      (terraform-target-parity.test.ts enforces the union; this pins the
#      specific block).
#   4. Script safety invariants: sets populate BEFORE default-drop installs
#      (availability ordering); additive-then-prune (no `flush set`);
#      fail-safe-on-empty; DNS pin + fail-loud drop logging present.
#   5. Units alarm on failure (OnFailure=) and the timer survives reboots.
#   6. cloud-init fresh-host mirror carries the artifacts.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_TF="$SCRIPT_DIR/server.tf"
CLOUD_INIT="$SCRIPT_DIR/cloud-init.yml"
WORKFLOW="$SCRIPT_DIR/../../../.github/workflows/apply-web-platform-infra.yml"
LOADER="$SCRIPT_DIR/cron-egress-nftables.sh"
RESOLVER="$SCRIPT_DIR/cron-egress-resolve.sh"
ALARM="$SCRIPT_DIR/cron-egress-alarm.sh"
ALLOWLIST="$SCRIPT_DIR/cron-egress-allowlist.txt"
# Post-apply assertion block, extracted to its own delivered script (#5289) so
# an edit to it changes config_hash and re-provisions — inline-block edits were
# silent no-ops (the hash folded only the 9 artifacts, not the inline block).
ASSERT_SCRIPT="$SCRIPT_DIR/cron-egress-postapply-assert.sh"

PASS=0
FAIL=0

# One owning EXIT trap for every tempdir this suite allocates (ADR-129 / #6734):
# per-test `mktemp -d` calls land under a suite-owned scratch dir via TMPDIR, so
# a suite that dies between allocation and its own `rm -rf` leaks nothing. The
# trap runs once, in this shell — a `$( … )` test subshell does not inherit it.
SUITE_SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/cron-egress-firewall-test.XXXXXX")"

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
assert_fixture_dir "$SUITE_SCRATCH"
export TMPDIR="$SUITE_SCRATCH"
trap 'rm -rf "$SUITE_SCRATCH"' EXIT

assert_grep() {
  local description="$1" pattern="$2" file="$3"
  if grep -qE -- "$pattern" "$file"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (pattern not found in $(basename "$file"): $pattern)"
  fi
}

assert_not_grep() {
  local description="$1" pattern="$2" file="$3"
  if grep -qE -- "$pattern" "$file"; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (forbidden pattern present in $(basename "$file"): $pattern)"
  else
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  fi
}

# ORDER-SENSITIVE EnvironmentFile assertion (#7095).
#
# systemd applies EnvironmentFile= directives in the order they appear and LATER
# WINS, so /etc/default/soleur-doppler-token must come AFTER
# /etc/default/inngest-server — the override is the entire mechanism by which the
# re-deliverable credential displaces the dead token copied into
# /etc/default/inngest-server (pinned forever by inngest-bootstrap.sh:567-568, so it
# never self-heals). A "both lines are present" check would stay GREEN if a future
# edit reversed them, silently restoring the 2026-07-30 outage. Assert the ORDER.
#
# Compares the LAST occurrence of each: with later-wins semantics it is the final
# directive that decides DOPPLER_TOKEN, so a duplicated base line reintroduced
# below the override must also fail.
assert_envfile_override_order() {
  local description="$1" unit="$2" base_line="$3" override_line="$4"
  local base_ln override_ln
  # -x -F: exact full-line literal, so the prose in the surrounding comment block
  # (which quotes both paths) can never satisfy this assertion.
  base_ln="$(grep -nxF -- "$base_line" "$unit" | tail -1 | cut -d: -f1)"
  override_ln="$(grep -nxF -- "$override_line" "$unit" | tail -1 | cut -d: -f1)"
  if [[ -z "$base_ln" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (missing from $(basename "$unit"): $base_line)"
  elif [[ -z "$override_ln" ]]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (missing from $(basename "$unit"): $override_line)"
  elif ((base_ln < override_ln)); then
    PASS=$((PASS + 1))
    echo "  PASS: $description (base line $base_ln precedes override line $override_ln)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description — later-wins ORDER INVERTED in $(basename "$unit"): '$override_line' is at line $override_ln but must come AFTER '$base_line' at line $base_ln; as written the dead token from the inngest-server copy wins again and #7095 silently returns"
  fi
}

assert_cmd() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description ($*)"
  fi
}

echo "--- cron-egress firewall drift-guard ---"

echo "-- artifacts exist + parse --"
for f in "$LOADER" "$RESOLVER" "$ALARM" "$ALLOWLIST" \
  "$SCRIPT_DIR/cron-egress-allowlist-cidr.txt" \
  "$SCRIPT_DIR/cron-egress-firewall.service" \
  "$SCRIPT_DIR/cron-egress-resolve.service" \
  "$SCRIPT_DIR/cron-egress-resolve.timer" \
  "$SCRIPT_DIR/cron-egress-alarm@.service" \
  "$ASSERT_SCRIPT"; do
  assert_cmd "exists: $(basename "$f")" test -f "$f"
done
assert_cmd "loader parses (bash -n)" bash -n "$LOADER"
assert_cmd "resolver parses (bash -n)" bash -n "$RESOLVER"
assert_cmd "alarm parses (bash -n)" bash -n "$ALARM"
assert_cmd "post-apply assert script parses (bash -n)" bash -n "$ASSERT_SCRIPT"

echo "-- server.tf delivery (anchored on the file-provisioner construct) --"
assert_grep "resource exists" 'resource "terraform_data" "cron_egress_firewall"' "$SERVER_TF"
for f in cron-egress-nftables.sh cron-egress-resolve.sh cron-egress-alarm.sh \
  cron-egress-allowlist.txt cron-egress-allowlist-cidr.txt cron-egress-firewall.service \
  cron-egress-resolve.service cron-egress-resolve.timer cron-egress-postapply-assert.sh; do
  assert_grep "delivers $f (source=)" "source += +\"\\\$\\{path\\.module\\}/$f\"" "$SERVER_TF"
  assert_grep "trigger folds $f hash" "file\\(\"\\\$\\{path\\.module\\}/$f\"\\)" "$SERVER_TF"
done
# The template unit's `@` needs its own anchors (regex-escaping differs).
assert_grep "delivers cron-egress-alarm@.service (source=)" 'source += +"\$\{path\.module\}/cron-egress-alarm@\.service"' "$SERVER_TF"
SERVER_BLOCK="$(awk '/resource "terraform_data" "cron_egress_firewall"/,/^}/' "$SERVER_TF")"
if echo "$SERVER_BLOCK" | grep -cE 'server_id += +hcloud_server\.web\["web-1"\]\.id' >/dev/null; then
  PASS=$((PASS + 1)); echo "  PASS: cron_egress_firewall trigger folds hcloud_server.web[\"web-1\"].id"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: cron_egress_firewall trigger does not fold hcloud_server.web[\"web-1\"].id"
fi
if echo "$SERVER_BLOCK" | grep -c 'mkdir -p /etc/soleur' >/dev/null; then
  PASS=$((PASS + 1)); echo "  PASS: parent dir created before file provisioners (scp does not mkdir)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: missing 'mkdir -p /etc/soleur' before file provisioners"
fi
# Live positive+negative probe (AC-P2.8 iii — the silent-green guard: nft -f
# exits 0 on an inert ruleset; only a real container probe proves enforcement).
# These constructs moved from the inline remote-exec to the delivered
# cron-egress-postapply-assert.sh (#5289); assert against the script now.
# Anchor on the ASSERT-FAILED: sentinel (executable line only) NOT the bare
# 'egress-probe-*' literal, which also appears in the script's comment prose —
# a bare grep would false-pass if the executable probe line were deleted but
# its comment kept (comment-prose false-match class, 2026-06-03 learning).
if grep -qE 'ASSERT-FAILED: egress-probe-negative' "$ASSERT_SCRIPT"; then
  PASS=$((PASS + 1)); echo "  PASS: post-apply negative container probe present"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: post-apply negative container probe missing"
fi
if grep -qE 'ASSERT-FAILED: egress-probe-positive' "$ASSERT_SCRIPT"; then
  PASS=$((PASS + 1)); echo "  PASS: post-apply positive container probe present"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: post-apply positive container probe missing"
fi
# The service is Type=oneshot/RemainAfterExit=yes, so `enable --now` no-ops on an
# already-active unit and the loader never re-reads a freshly-provisioned CIDR file
# (the inert-fix bug behind incident 5516336). The assert script MUST `restart` to
# re-run the loader so file changes actually load into the live nft set.
if grep -q 'systemctl restart cron-egress-firewall\.service' "$ASSERT_SCRIPT"; then
  PASS=$((PASS + 1)); echo "  PASS: provisioner restarts the firewall service (reloads new CIDR; not a no-op enable --now)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: provisioner must 'systemctl restart cron-egress-firewall.service' — enable --now no-ops on the active oneshot and a new CIDR file never loads"
fi

echo "-- apply workflow SSH -target --"
assert_grep "workflow -targets cron_egress_firewall" 'target=terraform_data\.cron_egress_firewall' "$WORKFLOW"

echo "-- deploy_pipeline_fix_web2 cron-egress delivery parity (#9393) --"
# A RUNNING web-2 receives host-script content only through the SSH sibling
# terraform_data.deploy_pipeline_fix_web2: the web-1 provisioners never dial it
# (parity guard's premise), and cloud-init/image-bake covers fresh hosts only.
# The issue's three artifacts — the carved CIDR file, the resolver, and the
# post-apply probe — must therefore ride that sibling with the SAME destinations
# the web-1 resource uses, each hashed in triggers_replace (an artifact edit
# re-fires delivery), each byte-asserted after scp (a truncated transfer fails
# the provisioner rather than latching silent drift), and the assert script
# EXECUTED last (delivering the probe without running it runs no probe).
#
# Anchored on the delivery constructs inside the resource's own block — never a
# bare filename grep, which a comment or a same-named file in ANOTHER resource
# would satisfy (the 2026-06-02 drift-guard learning this file already encodes).
WEB2_BLOCK="$(awk '/resource "terraform_data" "deploy_pipeline_fix_web2"/,/^}/' "$SERVER_TF")"
w2_assert() { # w2_assert <description> <ERE pattern>
  # Herestring, NOT `echo | grep -q`: `grep -q` exits on first match, the writer
  # dies on SIGPIPE mid-block, and `set -o pipefail` then reports the WON match
  # as a FAIL — a measured 1-in-N flake (rc=1 on the destination row in CI).
  # grep -c below is exempt (it reads all input; no early exit).
  if grep -qE -- "$2" <<<"$WEB2_BLOCK"; then
    PASS=$((PASS + 1)); echo "  PASS: $1"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $1 (pattern not found in deploy_pipeline_fix_web2 block: $2)"
  fi
}
# Non-vacuity floor on the slice itself: a renamed or restructured resource must
# red here, not pass over an empty block.
if echo "$WEB2_BLOCK" | grep -c 'provisioner "file"' >/dev/null; then
  PASS=$((PASS + 1)); echo "  PASS: deploy_pipeline_fix_web2 block extracted (non-empty slice)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: deploy_pipeline_fix_web2 block not found in server.tf"
fi
for spec in \
  "cron-egress-allowlist-cidr.txt /etc/soleur/cron-egress-allowlist-cidr.txt" \
  "cron-egress-resolve.sh /usr/local/bin/cron-egress-resolve.sh" \
  "cron-egress-postapply-assert.sh /usr/local/bin/cron-egress-postapply-assert.sh"; do
  f="${spec%% *}"
  dest="${spec##* }"
  w2_assert "web2 delivers $f (source=)" "source += +\"\\\$\\{path\\.module\\}/$f\""
  w2_assert "web2 delivers $f to $dest (destination=)" "destination += +\"$(printf '%s' "$dest" | sed 's/[.[\*^$/]/\\&/g')\""
  w2_assert "web2 trigger folds $f hash" "file\\(\"\\\$\\{path\\.module\\}/$f\"\\)"
  w2_assert "web2 remote-exec byte-asserts $f" "filesha256\\(\"\\\$\\{path\\.module\\}/$f\"\\)"
  # Cross-block destination parity: the web-1 resource and the web-2 sibling must
  # write the SAME absolute path for the same artifact — a destination typo puts
  # the file where no consumer reads it, with every delivery row still green.
  W1_DEST="$(grep -A1 "source *= *\"\\\${path.module}/$f\"" <<<"$SERVER_BLOCK" | grep -oE 'destination *= *"[^"]+"' | sed 's/.*"\([^"]*\)".*/\1/' | head -1)"
  W2_DEST="$(grep -A1 "source *= *\"\\\${path.module}/$f\"" <<<"$WEB2_BLOCK" | grep -oE 'destination *= *"[^"]+"' | sed 's/.*"\([^"]*\)".*/\1/' | head -1)"
  if [[ -n "$W1_DEST" && "$W1_DEST" == "$W2_DEST" ]]; then
    PASS=$((PASS + 1)); echo "  PASS: $f destination parity web-1 == web-2 ($W2_DEST)"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $f destination drift: web-1='$W1_DEST' web-2='$W2_DEST' (expected identical, and web-1's extraction must be non-empty)"
  fi
done
w2_assert "web2 creates /etc/soleur before file provisioners (scp does not mkdir)" 'mkdir -p [^"]*/etc/soleur'
w2_assert "web2 marks cron-egress-resolve.sh executable" 'chmod 0755 [^"]*cron-egress-resolve\.sh'
w2_assert "web2 marks cron-egress-postapply-assert.sh executable" 'chmod 0755 [^"]*cron-egress-postapply-assert\.sh'
w2_assert "web2 lands the carved CIDR file at mode 0644" 'chmod 0644 [^"]*cron-egress-allowlist-cidr\.txt'
w2_assert "web2 asserts root ownership of cron-egress-resolve.sh" 'chown root:root [^"]*cron-egress-resolve\.sh'
w2_assert "web2 asserts root ownership of cron-egress-postapply-assert.sh" 'chown root:root [^"]*cron-egress-postapply-assert\.sh'
w2_assert "web2 asserts root ownership of cron-egress-allowlist-cidr.txt" 'chown root:root [^"]*cron-egress-allowlist-cidr\.txt'
# The probe is the point of the issue — a delivered-but-never-run assert script
# leaves web-2 with the carve on disk and no proof of enforcement.
w2_assert "web2 EXECUTES the post-apply assert (the probe)" 'bash /usr/local/bin/cron-egress-postapply-assert\.sh'
# The web-1 resource's assert run is its provisioner's terminal step; on web-2 it
# must likewise run AFTER the deliveries+asserts, inside the same remote-exec
# script (provisioner ordering is declaration order — the ghcr deny block stays
# last either way).
W2_EXEC_LN="$(echo "$WEB2_BLOCK" | grep -nE 'bash /usr/local/bin/cron-egress-postapply-assert\.sh' | cut -d: -f1 | tail -1)"
W2_SHA_LN="$(echo "$WEB2_BLOCK" | grep -nE 'filesha256\("\$\{path\.module\}/cron-egress-postapply-assert\.sh"\)' | cut -d: -f1 | tail -1)"
if [[ -n "$W2_EXEC_LN" && -n "$W2_SHA_LN" && "$W2_EXEC_LN" -gt "$W2_SHA_LN" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: assert-execution ordered after the content assertions (line $W2_EXEC_LN > $W2_SHA_LN)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: assert-execution must come after the sha256 content assertions (exec=$W2_EXEC_LN sha=$W2_SHA_LN)"
fi
# The trigger sentinel must still exist (the lockstep rule requires a bump with
# any inline edit; pin PRESENCE not a version — a future legitimate bump must not
# red this guard).
w2_assert "web2 inline sentinel present (bumped in lockstep with the inline edit)" 'dpf-web2-remote-exec-v[0-9]+'

echo "-- loader safety invariants --"
# Availability ordering: the resolve (set population) line must precede the
# default-drop install (flush chain + add rules) — proven by line order.
RESOLVE_LINE="$(grep -n '"\$RESOLVE_SCRIPT"' "$LOADER" | sed -n '1p' | cut -d: -f1)"
DROP_LINE="$(grep -n 'flush chain ip filter SOLEUR-EGRESS' "$LOADER" | sed -n '1p' | cut -d: -f1)"
if [[ -n "$RESOLVE_LINE" && -n "$DROP_LINE" && "$RESOLVE_LINE" -lt "$DROP_LINE" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: sets populate BEFORE the default-drop installs (line $RESOLVE_LINE < $DROP_LINE)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: resolve must run before the drop rules install (resolve=$RESOLVE_LINE drop=$DROP_LINE)"
fi
assert_grep "default-drop log is rate-limited (no journald self-DoS)" 'limit rate 10/minute burst 50 packets log prefix "egress-blocked: " level notice' "$LOADER"
assert_grep "default-drop terminal rule present" 'counter drop comment "soleur-egress: default drop"' "$LOADER"
assert_grep "DNS pin accept rule" 'udp dport 53 ip daddr @soleur_egress_dns accept' "$LOADER"
assert_grep "DNS exfil drop is logged" 'egress-dns-exfil' "$LOADER"
assert_grep "host-gateway :8288 accept" 'tcp dport 8288 accept' "$LOADER"
# Dedicated Inngest host egress (#6178, ADR-100 cutover): the container must be
# allowed to reach the dedicated host 10.0.1.40:8288. Paren-safe ERE pattern —
# stop before the `(#6178)` comment tail (an unescaped `(` is an ERE group).
assert_grep "dedicated inngest host :8288 accept (#6178)" \
  'ip daddr 10\.0\.1\.40 tcp dport 8288 accept comment "soleur-egress: dedicated inngest host' "$LOADER"
# Line-order: the dedicated-host accept MUST precede the terminal default drop
# (first-match-wins), mirroring the RESOLVE_LINE < DROP_LINE block above.
DEDICATED_LINE="$(grep -n 'ip daddr 10\.0\.1\.40 tcp dport 8288 accept' "$LOADER" | sed -n '1p' | cut -d: -f1)"
DROP_RULE_LINE="$(grep -n 'counter drop comment "soleur-egress: default drop"' "$LOADER" | sed -n '1p' | cut -d: -f1)"
if [[ -n "$DEDICATED_LINE" && -n "$DROP_RULE_LINE" && "$DEDICATED_LINE" -lt "$DROP_RULE_LINE" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: dedicated inngest host accept precedes the default drop (line $DEDICATED_LINE < $DROP_RULE_LINE)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: dedicated inngest host accept must precede the default drop (dedicated=$DEDICATED_LINE drop=$DROP_RULE_LINE)"
fi
assert_grep "bridge gateway derived, not hardcoded" 'docker network inspect bridge' "$LOADER"
assert_grep "IPv6 bypass guard" 'EnableIPv6' "$LOADER"
assert_grep "jump rule scoped to the bridge interface" 'iifname "\$BRIDGE_IF" counter jump SOLEUR-EGRESS' "$LOADER"
assert_not_grep "never flushes the shared DOCKER-USER chain" 'flush chain ip filter DOCKER-USER' "$LOADER"

# GitHub LB-range fix: a static interval CIDR set parallel to the single-IP set.
assert_grep "declares interval CIDR set" 'set soleur_egress_allow_cidr' "$LOADER"
assert_grep "CIDR set uses flags interval" 'flags interval' "$LOADER"
assert_grep "CIDR allowlist accept rule present" 'ip daddr @soleur_egress_allow_cidr accept' "$LOADER"
assert_grep "loader reads the CIDR allowlist file" 'cron-egress-allowlist-cidr.txt' "$LOADER"
# GHCR carve (#9275, ADR-096 5.3b-iii). The old literal-`140.82.112.0/20` assertion is
# REPLACED by CONTAINMENT over the committed file: the generator carves GitHub's dedicated
# Packages frontends (ghcr.io / docker.pkg.github.com) out of that /20, so the literal prefix is
# legitimately gone, but github.com / api.github.com / codeload (same /20) MUST stay admitted
# and every address named by a `# Excluded (GitHub Packages frontends): <cidr>` header line MUST
# be denied. The oracle is python3 `ipaddress`, independent of the bash generator under test.
# Counts (9 prefixes / 122 lines) are a 2026-10-01 measurement and are NOT asserted; structure is.
cidr_containment() {   # cidr_containment <file> <ip>...   -> one verdict line per check
  python3 - "$@" <<'PY'
import ipaddress, re, sys
f, must = sys.argv[1], sys.argv[2:]
nets, excl = [], []
for line in open(f):
    line = line.strip()
    m = re.match(r'^# Excluded \(GitHub Packages frontends\): (\S+)$', line)
    if m:
        excl.append(ipaddress.ip_network(m.group(1), strict=False))
        continue
    if not line or line.startswith('#'):
        continue
    nets.append(ipaddress.ip_network(line, strict=False))
def inset(ip):
    a = ipaddress.ip_address(ip)
    return any(a in n for n in nets)
print("EXCLUDED_HEADERS", len(excl))
for ip in must:
    print("ADMITTED" if inset(ip) else "DENIED", ip)
checked = 0
for n in excl:
    if n.num_addresses > 4096:
        print("HOLE_TOO_BIG", n)
        continue
    for a in n:
        checked += 1
        print("EXCL_ADMITTED" if inset(str(a)) else "EXCL_DENIED", a)
print("EXCL_CHECKED", checked)
PY
}
# github.com .3, api.github.com .6, codeload .9 (all in the carved /20), another /20 member, the
# legacy github.com range, and the shared Fastly /22 retained on purpose (DC-1).
GH_MUST_ADMIT=(140.82.121.3 140.82.121.6 140.82.121.9 140.82.112.3 192.30.255.112 185.199.108.154)
CONTAIN_OUT="$(cidr_containment "$SCRIPT_DIR/cron-egress-allowlist-cidr.txt" "${GH_MUST_ADMIT[@]}" 2>&1 || true)"
CONTAIN_BAD="$(echo "$CONTAIN_OUT" | grep -E '^(DENIED|EXCL_ADMITTED|HOLE_TOO_BIG) ' || true)"
CONTAIN_EXCL_N="$(echo "$CONTAIN_OUT" | sed -n 's/^EXCL_CHECKED //p')"
CONTAIN_ADMIT_N="$(echo "$CONTAIN_OUT" | grep -c '^ADMITTED ' || true)"
if [[ "${CONTAIN_ADMIT_N:-0}" -eq "${#GH_MUST_ADMIT[@]}" && -z "$CONTAIN_BAD" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: CIDR file admits github.com/api/codeload (+3 more) and denies every excluded Packages frontend (containment, python oracle)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: CIDR containment (admitted ${CONTAIN_ADMIT_N:-0}/${#GH_MUST_ADMIT[@]}; bad rows: $(echo "$CONTAIN_BAD" | tr '\n' ';'))"
fi
# Instrument floor: a header-less file (carve absent, or the oracle broken) checks ZERO excluded
# addresses and would pass the loop above vacuously.
if [[ "${CONTAIN_EXCL_N:-0}" -ge 1 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: containment oracle checked $CONTAIN_EXCL_N excluded addresses (floor >= 1)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: containment oracle checked ${CONTAIN_EXCL_N:-0} excluded addresses (the carve header is absent or the oracle is broken)"
fi
# The carve-header prefix floor (/28) as this suite spells it; B8 below proves it equals the
# generator's MIN_HOLE_PFX, the resolver sampler's floor and the post-apply assert's regex.
HDR_PFX_RE='(2[89]|3[0-2])'
assert_grep "CIDR file records >=1 effective carve header line (generator header format, /28 or longer)" \
  "^# Excluded \\(GitHub Packages frontends\\): [0-9]{1,3}(\\.[0-9]{1,3}){3}/${HDR_PFX_RE}\$" "$SCRIPT_DIR/cron-egress-allowlist-cidr.txt"
# Committed-file self-consistency (B5): the `# Snapshot:` range count is stated by the generator
# and must equal the file's own non-comment body, so a hand-trim or a partial write cannot leave a
# stale count behind. Exactly one Snapshot line is required.
CIDR_COMMITTED="$SCRIPT_DIR/cron-egress-allowlist-cidr.txt"
SNAP_LINES="$(grep -c '^# Snapshot:' "$CIDR_COMMITTED" || true)"
SNAP_N="$(sed -nE 's/^# Snapshot: .* ([0-9]+) IPv4 ranges[.]$/\1/p' "$CIDR_COMMITTED")"
BODY_N="$(grep -vcE '^[[:space:]]*(#|$)' "$CIDR_COMMITTED" || true)"
if [[ "$SNAP_LINES" -eq 1 && "$SNAP_N" =~ ^[0-9]+$ && "$SNAP_N" -eq "$BODY_N" && "$BODY_N" -ge 1 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: committed CIDR file: '# Snapshot: ... $SNAP_N IPv4 ranges' equals its $BODY_N body lines"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: committed CIDR file: Snapshot lines=$SNAP_LINES count='${SNAP_N:-}' but body has ${BODY_N:-0} non-comment lines (regenerate via gen-github-egress-cidr.sh)"
fi
# Independent oracle (python3 ipaddress) over the header set: every `# Excluded` address must lie
# inside a prefix of the PRE-CARVE allow list, i.e. the base branch's file (a header outside it is
# a fabricated or mis-computed hole). The base file is only a valid pre-carve reference while it
# has no headers itself (after this lands on main the base IS the carved file), and a shallow clone
# may not carry it at all: both degrade to the floor (>= 1 header) with the SAME single row, so
# the row count never depends on git state.
assert_fixture_dir "$SUITE_SCRATCH"
CARVE_BASE="$SUITE_SCRATCH/cidr-base.txt"
CARVE_BASE_STATE="unreachable"
if git -C "$SCRIPT_DIR" show origin/main:./cron-egress-allowlist-cidr.txt > "$CARVE_BASE" 2>/dev/null && [[ -s "$CARVE_BASE" ]]; then
  CARVE_BASE_STATE="reachable"
fi
CARVE_ORACLE="$(python3 - "$CIDR_COMMITTED" "$CARVE_BASE" "$CARVE_BASE_STATE" <<'PY'
import ipaddress, re, sys
def parse(f):
    nets, hdr = [], []
    for line in open(f):
        line = line.strip()
        m = re.match(r'^# Excluded \(GitHub Packages frontends\): (\S+)$', line)
        if m:
            hdr.append(ipaddress.ip_network(m.group(1), strict=False)); continue
        if line and not line.startswith('#'):
            nets.append(ipaddress.ip_network(line, strict=False))
    return nets, hdr
_, hdr = parse(sys.argv[1])
print("HEADERS", len(hdr))
if sys.argv[3] == "reachable":
    base, base_hdr = parse(sys.argv[2])
    if base_hdr:
        print("BASE_ALREADY_CARVED", len(base_hdr))
    else:
        outside = [str(h) for h in hdr if not any(h.subnet_of(b) for b in base)]
        print("BASE_OUTSIDE", len(outside), " ".join(outside))
        print("BASE_PREFIXES", len(base))
else:
    print("BASE_UNREACHABLE")
PY
)"
CARVE_HDRS="$(echo "$CARVE_ORACLE" | sed -n 's/^HEADERS //p')"
CARVE_MODE="floor-only"
CARVE_OK=0
if [[ "${CARVE_HDRS:-0}" -ge 1 ]]; then
  CARVE_OK=1
  if grep -q '^BASE_PREFIXES ' <<<"$CARVE_ORACLE"; then
    CARVE_MODE="every header inside the pre-carve base file ($(echo "$CARVE_ORACLE" | sed -n 's/^BASE_PREFIXES //p') prefixes)"
    grep -qE '^BASE_OUTSIDE 0 ?$' <<<"$CARVE_ORACLE" || CARVE_OK=0
  fi
fi
if [[ "$CARVE_OK" -eq 1 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: committed CIDR file: $CARVE_HDRS Excluded headers; oracle mode: $CARVE_MODE"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: committed CIDR file: Excluded headers=${CARVE_HDRS:-0} (need >= 1), oracle: $(echo "$CARVE_ORACLE" | tr '\n' ';')"
fi
# `# Excluded` lines are comments: they must not be readable as allow entries by the loader.
assert_not_grep "no non-comment line of the CIDR file is an Excluded header (comments only)" \
  '^[^#].*Excluded' "$SCRIPT_DIR/cron-egress-allowlist-cidr.txt"
# api.github.com round-robins DNS across BOTH the 4 big git/pages blocks AND ~48
# Azure 20.x/4.x /32 hosts (api.github.com/meta `.git`+`.api`). The 4-block-only
# file left those /32s uncovered → a fire landing on one was default-dropped →
# missed cron check-in (incident 5516336, scheduled-ruleset-bypass-audit,
# 2026-06-14). The CIDR file MUST carry the Azure /32s for api.github.com.
assert_grep "CIDR file carries >=1 Azure 20.x /32 (api.github.com LB pool)" '^20[.][0-9]+[.][0-9]+[.][0-9]+/32$' "$SCRIPT_DIR/cron-egress-allowlist-cidr.txt"
assert_grep "CIDR file carries >=1 Azure 4.x /32 (api.github.com LB pool)" '^4[.][0-9]+[.][0-9]+[.][0-9]+/32$' "$SCRIPT_DIR/cron-egress-allowlist-cidr.txt"
# Structural drift-guard (de-magicked + de-circularized, #5284). The old exact
# `count == 52` guard was itself a staleness trap: a /meta rotation that swaps one
# /32 for another keeps the count at 52 while the ranges are wrong. The file is
# now generated by apps/web-platform/infra/scripts/gen-github-egress-cidr.sh and
# auto-refreshed by the cron-github-cidr-refresh Inngest cron. Generator
# DETERMINISM (fixture-in -> golden-out) is asserted in gen-github-egress-cidr.test.sh;
# live coverage by the runbook `comm -23` probe + the cron at runtime. This offline
# guard asserts ONLY the structural invariants a hand-edit / partial-revert /
# truncation breaks (it does NOT call live /meta and does NOT assert the committed
# file equals the synthetic fixture — those would be flaky / always-fail).
assert_grep "CIDR file carries the generated DO-NOT-EDIT header (not a hand-edit)" 'DO NOT EDIT .+ regenerate via .+gen-github-egress-cidr\.sh' "$SCRIPT_DIR/cron-egress-allowlist-cidr.txt"
# Floor count: a partial revert to just the 4 big git/pages blocks (the
# incident-5516336 regression) drops far below the Azure /32 pool size. A floor is
# NOT a staleness trap — rotations keep the count ~constant; only truncation trips it.
CIDR_COUNT="$(grep -vcE '^[[:space:]]*#|^[[:space:]]*$' "$SCRIPT_DIR/cron-egress-allowlist-cidr.txt")"
if [[ "$CIDR_COUNT" -ge 40 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: CIDR allowlist range count is $CIDR_COUNT (floor >= 40; partial-revert/truncation guard)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: CIDR allowlist range count is $CIDR_COUNT (below the floor of 40 — a partial revert/truncation to the 4 big blocks; regenerate via gen-github-egress-cidr.sh)"
fi
# Over-broad reject: both the generator's and the loader's validators accept a
# structurally-valid 0.0.0.0/0; the prefix-floor (>= /8) is the breadth defense
# the one allow-all egress vector needs. No committed line may have prefix < /8.
OVERBROAD="$(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$SCRIPT_DIR/cron-egress-allowlist-cidr.txt" | awk -F/ '$2 < 8 {print}')"
if [[ -z "$OVERBROAD" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: no committed CIDR has an over-broad prefix (< /8)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: over-broad CIDR(s) with prefix < /8 present (allow-all vector): $OVERBROAD"
fi

echo "-- CIDR validation (nft-injection hardening, #5242) --"
# The CIDR file is interpolated VERBATIM into the `add element ... { $CIDR_ELEMENTS }`
# nft heredoc. An unvalidated line containing `}`, an nft keyword, whitespace, or
# command-substitution is injected into the ruleset (e.g. `0.0.0.0/0` allow-all, or
# `}; add rule ... accept`). The loader MUST validate every non-comment line against
# a strict IPv4-CIDR shape and reject the WHOLE file (die/exit 1) on any mismatch —
# fail-loud (operator paged via OnFailure=) over half-installing a firewall.
#
# Source-shape drift guards (RED→GREEN with the loader edit):
assert_grep "validator function defined" 'is_valid_ipv4_cidr\(\)' "$LOADER"
assert_grep "reject-whole-file on invalid line (die, not skip)" '\|\| die "invalid CIDR in' "$LOADER"
assert_not_grep "old unvalidated paste -sd, build removed" 'paste -sd,' "$LOADER"
# Anchor on the executable arithmetic form (`o1 <= 255`, present ONLY on the
# `(( ... ))` code line), NOT the bare `<= 255` which also appears in the loader's
# explanatory comment — a bare-pattern assert false-passes if the range-check code is
# deleted but the comment kept (comment-prose false-match class, 2026-06-03 learning).
assert_grep "octet/prefix range-check (defense in depth)" 'o1 <= 255' "$LOADER"

# Cross-file predicate parity: the test's behavioral copy (below) must carry the EXACT
# predicate the loader ships, else the copy drifts silently (same convention as
# SENTRY_SLUG/drop-prefix parity above). grep -F = fixed string (literal). Pin BOTH
# halves of the predicate — the regex shape AND the octet/prefix range-check arithmetic
# — so a `<= 255`→`<= 254` (or `<= 32`→`<= 128`) drift in either file fails the suite.
CIDR_RE='([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})'
CIDR_RANGE='o1 <= 255 && o2 <= 255 && o3 <= 255 && o4 <= 255 && prefix <= 32'
if grep -qF -- "$CIDR_RE" "$LOADER" && grep -qF -- "$CIDR_RE" "${BASH_SOURCE[0]}"; then
  PASS=$((PASS + 1)); echo "  PASS: CIDR regex literal pinned identically in loader and test"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: CIDR regex literal drift between loader and test (loader must carry: $CIDR_RE)"
fi
if grep -qF -- "$CIDR_RANGE" "$LOADER" && grep -qF -- "$CIDR_RANGE" "${BASH_SOURCE[0]}"; then
  PASS=$((PASS + 1)); echo "  PASS: CIDR range-check arithmetic pinned identically in loader and test"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: CIDR range-check drift between loader and test (loader must carry: $CIDR_RANGE)"
fi

# Behavioral exercise of the validator. `nft` is absent on CI runners and the full
# loader aborts at `command -v nft` before reaching the CIDR parse, so the script
# cannot run end-to-end here. Pin a COPY of the exact predicate (guarded byte-for-byte
# by the literal-parity assert above) and exercise it against crafted lines.
test_is_valid_ipv4_cidr() {
  local cidr="$1" prefix o1 o2 o3 o4
  [[ "$cidr" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$ ]] || return 1
  o1=${BASH_REMATCH[1]}; o2=${BASH_REMATCH[2]}; o3=${BASH_REMATCH[3]}
  o4=${BASH_REMATCH[4]}; prefix=${BASH_REMATCH[5]}
  (( o1 <= 255 && o2 <= 255 && o3 <= 255 && o4 <= 255 && prefix <= 32 )) || return 1
  return 0
}
assert_cidr_accept() {
  if test_is_valid_ipv4_cidr "$1"; then
    PASS=$((PASS + 1)); echo "  PASS: accepts $2"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: should accept $2 ('$1')"
  fi
}
assert_cidr_reject() {
  if test_is_valid_ipv4_cidr "$1"; then
    FAIL=$((FAIL + 1)); echo "  FAIL: should REJECT $2 ('$1')"
  else
    PASS=$((PASS + 1)); echo "  PASS: rejects $2"
  fi
}
# AC2 — the 4 real allowlist ranges accept:
assert_cidr_accept "140.82.112.0/20" "real GitHub git /20"
assert_cidr_accept "185.199.108.0/22" "real GitHub pages /22"
assert_cidr_accept "192.30.252.0/22" "real GitHub /22"
assert_cidr_accept "143.55.64.0/20"  "real GitHub /20"
# Representative api.github.com Azure LB /32 (api.github.com/meta `.api`):
assert_cidr_accept "20.201.28.151/32" "real GitHub api Azure /32"
assert_cidr_accept "4.208.26.197/32"  "real GitHub api Azure /32"
# Structurally valid (allow-all breadth is a content concern, out of scope — see plan Non-Goals):
assert_cidr_accept "0.0.0.0/0" "structurally valid CIDR"
# AC1 — injection / command-substitution / whitespace shapes reject:
assert_cidr_reject "140.82.112.0/20}; add rule ip filter SOLEUR-EGRESS accept" "nft-injection (} + add rule)"
assert_cidr_reject "; nft flush ruleset" "nft keyword line"
assert_cidr_reject '$(curl evil)' "command-substitution shape"
assert_cidr_reject " 140.82.112.0/20" "leading whitespace"
assert_cidr_reject "140.82.112.0/20 " "trailing whitespace"
assert_cidr_reject $'1.1.1.0/24\nevil' "embedded newline"
# AC1 (malformed shape) reject:
assert_cidr_reject "0.0.0.0" "no prefix"
assert_cidr_reject "140.82.112/20" "3 octets"
assert_cidr_reject "garbage" "non-CIDR text"
# AC4 — octet/prefix range (the issue's bare regex would WRONGLY accept these):
assert_cidr_reject "999.999.999.999/99" "octets and prefix out of range"
assert_cidr_reject "256.1.1.1/8" "first octet > 255"
assert_cidr_reject "1.1.1.1/33" "prefix > 32"

# AC3 — comment/blank lines are skipped by the loop guard, never validated:
COMMENT_SKIP_RE='^[[:space:]]*(#|$)'
assert_grep "loop skips comment/blank lines before validation" "$COMMENT_SKIP_RE" "$LOADER"

echo "-- resolver safety invariants --"
# Anchored on the executable form (`flush set ip filter …`), not the bare
# phrase — the resolver's own comment legitimately SAYS "never flush set"
# (comment-prose false-match class, 2026-06-03 learning).
assert_not_grep "never flush-set (additive-then-prune only)" 'flush set ip filter' "$RESOLVER"
# Behavior anchors (executable constructs, NOT prose — a kept comment must
# not green a deleted code path; 2026-06-03 comment-prose learning):
assert_grep "fail-safe on empty resolution (guard construct)" 'refusing to touch the sets' "$RESOLVER"
assert_grep "additive-only tick on partial failure (PRUNE flip construct)" 'PRUNE="no-prune"' "$RESOLVER"
assert_grep "absent dynamic env counts as failed host (no prune on Doppler drift)" 'dynamic-host env .var unset' "$RESOLVER"
if grep -qF "DNS_IPS=$'8.8.8.8" "$RESOLVER"; then
  PASS=$((PASS + 1)); echo "  PASS: DNS pin always unions Docker substitution pair"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: DNS pin must unconditionally seed Docker's 8.8.8.8/8.8.4.4 substitution pair"
fi
assert_grep "container-view resolution unioned (resolver-divergence guard)" 'CONTAINER_VIEW' "$RESOLVER"
assert_grep "self-heal: re-runs loader when enforcement rules missing" 'enforcement rules missing' "$RESOLVER"
assert_grep "self-heal recursion guard (loader sets the env)" 'CRON_EGRESS_FROM_LOADER=1' "$LOADER"
assert_grep "concurrent runs serialized via flock" 'flock -w 120' "$RESOLVER"
assert_grep "BOTH drop prefixes counted toward the Sentry event" "egress-.blocked.dns-exfil.: " "$RESOLVER"
assert_grep "single atomic nft -f batch apply" 'nft -f -' "$RESOLVER"
assert_grep "tick budget: env-overridable constant (default 90 < TimeoutStartSec 120)" 'RESOLVE_TICK_BUDGET_SECS="\$\{RESOLVE_TICK_BUDGET_SECS:-90\}"' "$RESOLVER"
assert_grep "tick budget: loop gate reads elapsed SECONDS before each getent" 'SECONDS >= RESOLVE_TICK_BUDGET_SECS' "$RESOLVER"
assert_grep "tick budget: starved names count FAILED without touching the try-and-fail counter" 'DNS_SKIPPED=\$\(\(DNS_SKIPPED \+ 1\)\)' "$RESOLVER"
assert_grep "tick budget: container-view exec shrinks to the remaining budget" 'CV_CAP=\$\(\( RESOLVE_TICK_BUDGET_SECS - SECONDS' "$RESOLVER"
assert_grep "tick budget: dedupe marker cleared on a within-budget tick" 'rm -f "\$FAILCOUNT_DIR/\.budget-skip"' "$RESOLVER"
assert_grep "tick budget: dedicated Sentry op for the starved-tick class" 'resolve_tick_budget' "$RESOLVER"
assert_grep "Sentry Crons ok check-in (dead-timer detection)" 'sentry_checkin ok' "$RESOLVER"
assert_grep "Sentry Crons error check-in on failure" 'sentry_checkin error' "$RESOLVER"

echo "-- resolver grace-window retention (LB-rotation fix) --"
# Source-anchored guards (executable constructs, NOT comment prose — 2026-06-03
# false-match class). LB-fronted allowlisted hosts (Cloudflare/AWS/Google) rotate
# across large pools; the single-A-record snapshot pins only the current tick's
# IPs, so a connect to a freshly-rotated IP before the next tick is default-dropped.
# The resolver must RETAIN every IP seen for an allowlisted host within a window.
assert_grep "retention: GRACE_WINDOW_SECS constant (env-overridable, 24h default)" 'GRACE_WINDOW_SECS="\$\{GRACE_WINDOW_SECS:-86400\}"' "$RESOLVER"
assert_grep "retention: SEEN_DIR store constant (env-overridable, /var/lib)" 'SEEN_DIR="\$\{SEEN_DIR:-/var/lib/cron-egress-resolve/seen\}"' "$RESOLVER"
assert_grep "retention: store dir created beside FAILCOUNT_DIR" 'mkdir -p "\$SEEN_DIR"' "$RESOLVER"
assert_grep "retention: records every current-tick IP's last-seen (every tick)" 'echo "\$NOW_EPOCH" > "\$SEEN_DIR/\$ip"' "$RESOLVER"
assert_grep "retention: within-window stored IPs union into RETAINED" 'age <= GRACE_WINDOW_SECS' "$RESOLVER"
assert_grep "retention: store readback via basename (store-union path)" 'basename "\$seen_file"' "$RESOLVER"
assert_grep "retention: strict-mode last-seen timestamp guard" '\[\[ "\$ts" =~ \^\[0-9\]\+\$ \]\]' "$RESOLVER"
assert_grep "retention: eviction gated on prune tick (FAILED_HOSTS==0, no-prune suppresses)" 'FAILED_HOSTS" -eq 0' "$RESOLVER"
assert_grep "retention: RETAINED set feeds the ALLOW_SET batch (not raw DESIRED_ALLOW)" 'build_batch "\$ALLOW_SET" "\$RETAINED"' "$RESOLVER"
assert_grep "retention: OK log carries retained= count" 'retained=' "$RESOLVER"
# Ordering: the fail-safe-on-empty guard MUST precede the store-record line, so a
# zero-resolution tick aborts BEFORE the store is ever read (a DNS outage must not
# be papered over by stale store IPs). Proven by line order (loader-precedent shape).
FAILSAFE_LINE="$(grep -n 'refusing to touch the sets' "$RESOLVER" | sed -n '1p' | cut -d: -f1)"
RETAIN_LINE="$(grep -n 'SEEN_DIR/\$ip' "$RESOLVER" | sed -n '1p' | cut -d: -f1)"
if [[ -n "$FAILSAFE_LINE" && -n "$RETAIN_LINE" && "$FAILSAFE_LINE" -lt "$RETAIN_LINE" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: fail-safe-on-empty guard precedes the store-record block (line $FAILSAFE_LINE < $RETAIN_LINE)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: store-record must run AFTER the fail-safe-on-empty guard (failsafe=$FAILSAFE_LINE retain=$RETAIN_LINE)"
fi

# Cross-file predicate parity: the retention_build() copy below must carry the EXACT
# load-bearing fragments the resolver ships, else the copy drifts silently while its
# scenarios keep passing (same convention as the CIDR validator parity above). The
# source-anchored guards pin the RESOLVER's constructs; these pin that the test COPY
# matches. grep -qF = fixed literal. Both fragments are executable-only (the `$frag`
# echo line and the escaped source-anchor asserts above do not contain them verbatim),
# so a deleted code line cannot be masked by a comment/echo match (2026-06-03 class).
for frag in '(( age <= ' ' -eq 0 ]]; then'; do
  if grep -qF -- "$frag" "$RESOLVER" && grep -qF -- "$frag" "${BASH_SOURCE[0]}"; then
    PASS=$((PASS + 1)); echo "  PASS: retention fragment pinned identically in resolver + test copy ($frag)"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: retention fragment drift between resolver and test copy ($frag)"
  fi
done

# Behavioral exercise (nft absent on CI; exercise the retain/evict set-building in
# isolation against a tmp store + tiny window). Mirrors the test_is_valid_ipv4_cidr
# copy convention — the source-anchored guards above pin that the resolver ships
# this exact logic.
retention_build() {
  # args: seen_dir now window failed_hosts ; stdin = current-tick IPs (one/line)
  local seen_dir="$1" now="$2" window="$3" failed_hosts="$4"
  local desired retained ip ts age seen_file
  desired="$(cat | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u || true)"
  while IFS= read -r ip; do
    [[ -n "$ip" ]] || continue
    echo "$now" > "$seen_dir/$ip"
  done <<< "$desired"
  retained="$desired"
  if [[ -d "$seen_dir" ]]; then
    while IFS= read -r seen_file; do
      [[ -n "$seen_file" ]] || continue
      ip="$(basename "$seen_file")"
      [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
      ts="$(cat "$seen_file" 2>/dev/null || echo 0)"
      [[ "$ts" =~ ^[0-9]+$ ]] || ts=0
      age=$(( now - ts ))
      if (( age <= window )); then
        retained+=$'\n'"$ip"
      elif [[ "$failed_hosts" -eq 0 ]]; then
        rm -f "$seen_file"
      fi
    done < <(find "$seen_dir" -type f 2>/dev/null)
  fi
  echo "$retained" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u || true
}

# (a) retention within window: stored-but-not-re-resolved IP is RETAINED.
T1="$(mktemp -d)"; echo "100" > "$T1/104.18.24.159"
OUT1="$(printf '10.0.0.1\n' | retention_build "$T1" 150 100 0)"
if echo "$OUT1" | grep -cx '104.18.24.159' >/dev/null && echo "$OUT1" | grep -cx '10.0.0.1' >/dev/null; then
  PASS=$((PASS + 1)); echo "  PASS: within-window stored IP retained though not re-resolved this tick"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: within-window stored IP should be retained (got: $(echo "$OUT1" | tr '\n' ' '))"
fi

# (b) eviction after window (prune tick): past-window IP dropped AND store entry removed.
T2="$(mktemp -d)"; echo "100" > "$T2/198.51.100.7"
OUT2="$(printf '10.0.0.1\n' | retention_build "$T2" 300 100 0)"
if ! echo "$OUT2" | grep -cx '198.51.100.7' >/dev/null && [[ ! -f "$T2/198.51.100.7" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: past-window IP evicted and store entry removed on prune tick"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: past-window IP should be evicted + file removed on prune tick"
fi

# (c) no-prune (FAILED_HOSTS>0) suppresses eviction: past-window store entry KEPT.
T3="$(mktemp -d)"; echo "100" > "$T3/203.0.113.9"
printf '10.0.0.1\n' | retention_build "$T3" 300 100 1 >/dev/null  # scenario asserts on store-file state, not output
if [[ -f "$T3/203.0.113.9" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: no-prune tick keeps past-window store entry (defers eviction)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: no-prune tick must NOT evict the past-window store entry"
fi

# (d) no-prune STILL records (refresh ts) + unions (within-window stored IP).
T4="$(mktemp -d)"; echo "100" > "$T4/198.18.0.5"
OUT4="$(printf '198.18.0.9\n' | retention_build "$T4" 150 100 1)"
if echo "$OUT4" | grep -cx '198.18.0.5' >/dev/null && [[ "$(cat "$T4/198.18.0.9" 2>/dev/null)" == "150" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: no-prune still unions within-window store IP and refreshes current-tick ts"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: no-prune must still record (refresh ts) and union within-window store IPs"
fi

# (e) readback re-filter: a non-dotted-quad store file never reaches the set.
T5="$(mktemp -d)"; echo "100" > "$T5/not-an-ip"; echo "100" > "$T5/1.2.3.4"
OUT5="$(printf '10.0.0.1\n' | retention_build "$T5" 150 100 0)"
if echo "$OUT5" | grep -cx '1.2.3.4' >/dev/null && ! echo "$OUT5" | grep -c 'not-an-ip' >/dev/null; then
  PASS=$((PASS + 1)); echo "  PASS: non-IPv4 store filename re-filtered out of the batch"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: non-IPv4 store filename must be re-filtered out"
fi
# (f) boundary: age == GRACE_WINDOW exactly is RETAINED (pins `<=`, not `<`).
T6="$(mktemp -d)"; echo "100" > "$T6/192.0.2.50"
OUT6="$(printf '10.0.0.1\n' | retention_build "$T6" 200 100 0)"   # age = 200-100 = 100 == window
if echo "$OUT6" | grep -cx '192.0.2.50' >/dev/null; then
  PASS=$((PASS + 1)); echo "  PASS: IP at exactly age==window is retained (inclusive boundary, <= not <)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: IP at age==window must be retained (a <=→< regression would drop it)"
fi
rm -rf "$T1" "$T2" "$T3" "$T4" "$T5" "$T6"

echo "-- unit invariants --"
assert_grep "firewall unit alarms on failure" 'OnFailure=cron-egress-alarm@%n\.service' "$SCRIPT_DIR/cron-egress-firewall.service"
assert_grep "resolve unit alarms on failure" 'OnFailure=cron-egress-alarm@%n\.service' "$SCRIPT_DIR/cron-egress-resolve.service"
assert_grep "firewall unit re-asserts every boot" 'WantedBy=multi-user\.target' "$SCRIPT_DIR/cron-egress-firewall.service"
assert_grep "timer survives reboots (Persistent)" 'Persistent=true' "$SCRIPT_DIR/cron-egress-resolve.timer"
assert_grep "resolve runs doppler-wrapped (env for Sentry + dynamic hosts)" 'run --project soleur --config prd' "$SCRIPT_DIR/cron-egress-resolve.service"
assert_grep "resolve unit sources the doppler token env file" 'EnvironmentFile=-/etc/default/inngest-server' "$SCRIPT_DIR/cron-egress-resolve.service"
# #7095 — ADDED alongside the assertion above, never replacing it: both files must be
# sourced, and in this order. See assert_envfile_override_order's header for why the
# order (not mere presence) is the property under test.
#
# COVERAGE IS DERIVED, NOT HAND-LISTED. The set under test is discovered from the
# units themselves: every *.service here that OPTIONALLY sources
# /etc/default/inngest-server — the file holding the COPY of the web-host Doppler
# token, grep-extracted out of /etc/default/webhook-deploy by
# inngest-bootstrap.sh:586 and then PINNED forever at :567-568, so a dead-but-well-
# formed value never self-heals. Every such unit must ALSO source the re-deliverable
# credential, AFTER it.
#
# Why derived: this guard was first written with two hand-picked call sites while a
# FOURTH consumer (cron-egress-firewall.service) sat uncovered. It showed zero
# failures — not because it was healthy, but because it is a boot-time oneshot that
# has not run since the revocation, while cron-egress-resolve, which takes the
# doppler arm on the SAME `[ -n "$DOPPLER_TOKEN" ]` condition, failed 522 times. A
# latent instance is precisely what a hand-written list cannot see, and "three
# literal call sites" is the same shape that under-covered in the first place.
# Discovery closes the class: a fifth consumer is covered the moment it sources the
# copy, with no edit here.
#
# SCOPE — the `-` prefix is the discriminator, deliberately. inngest-redis.service
# and inngest-cutover-flip.service source the same path in the REQUIRED form (no
# `-`) and are correctly OUT of scope: they run on soleur-inngest-prd, whose own
# inngest-bootstrap writes that host's live token, and a fleet-wide Better Stack
# sweep grouped by host confirms soleur-inngest-prd took no part in the 07-30
# failure cluster. That exclusion is a decision, not an oversight — if a unit ever
# needs the required form AND the override, widen this pattern consciously.
DOPPLER_COPY_LINE='EnvironmentFile=-/etc/default/inngest-server'
DOPPLER_REDELIVER_LINE='EnvironmentFile=-/etc/default/soleur-doppler-token'
# Discovery is by EXACT FULL LINE (-l -x -F) for the same reason the assertion is:
# these units quote both paths in their comment prose, so a substring match would
# sweep in units that only TALK about the copy without sourcing it.
mapfile -t DOPPLER_COPY_UNITS < <(
  grep -lxF -- "$DOPPLER_COPY_LINE" "$SCRIPT_DIR"/*.service 2>/dev/null | sort
)
for unit in "${DOPPLER_COPY_UNITS[@]}"; do
  assert_envfile_override_order \
    "$(basename "$unit") sources the re-deliverable credential AFTER the inngest-server copy (systemd later-wins)" \
    "$unit" "$DOPPLER_COPY_LINE" "$DOPPLER_REDELIVER_LINE"
done

# Non-vacuity floor. A derived sweep that discovers nothing passes vacuously and
# certifies an empty set, so assert BOTH a minimum cardinality AND that every unit
# already known to source the copy is in the discovered set (a glob typo, a rename,
# or a wrong-directory run all collapse to zero and must red).
#
# This is a FLOOR, not an exact count: a fifth consumer RAISES coverage with no edit
# here, which is the entire point. It only needs touching when coverage legitimately
# SHRINKS — a unit that stops sourcing the copy altogether — and that is a deliberate
# architectural change which SHOULD cost an acknowledging edit rather than silently
# thinning the guard. The asymmetry is the design: growth is free, shrinkage is loud.
DOPPLER_COPY_KNOWN=(
  container-restart-monitor.service
  cron-egress-alarm@.service
  cron-egress-firewall.service
  cron-egress-resolve.service
)
if ((${#DOPPLER_COPY_UNITS[@]} >= ${#DOPPLER_COPY_KNOWN[@]})); then
  PASS=$((PASS + 1))
  echo "  PASS: doppler-copy sweep is non-vacuous (${#DOPPLER_COPY_UNITS[@]} units discovered, floor ${#DOPPLER_COPY_KNOWN[@]})"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: doppler-copy sweep discovered only ${#DOPPLER_COPY_UNITS[@]} unit(s), below the floor of ${#DOPPLER_COPY_KNOWN[@]} — the sweep is under-covering or matched nothing at all"
fi
for known in "${DOPPLER_COPY_KNOWN[@]}"; do
  if printf '%s\n' "${DOPPLER_COPY_UNITS[@]}" | grep -cxF -- >/dev/null "$SCRIPT_DIR/$known"; then
    PASS=$((PASS + 1))
    echo "  PASS: known doppler-copy consumer is in the derived sweep: $known"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: known doppler-copy consumer $known dropped OUT of the derived sweep — it no longer carries '$DOPPLER_COPY_LINE'. If that is intentional, remove it from DOPPLER_COPY_KNOWN in the same commit; otherwise the guard just went blind on it"
  fi
done
# --- #7095 R3: the .conf DROP-INS, which the *.service sweep above CANNOT see -------------
#
# The sweep above globs "$SCRIPT_DIR"/*.service. A drop-in is a .conf, so it is invisible to it
# BY CONSTRUCTION — not by oversight, and no widening of that glob would be correct either, since
# the order assertion it performs is meaningless for a drop-in (systemd merges drop-ins after the
# main unit, so later-wins is structural rather than line-ordered).
#
# That blind spot mattered: with the drop-ins unasserted, a review pass demonstrated that gutting
# BOTH .conf files to a bare [Service] line, and separately re-pointing the heartbeat drop-in at
# /etc/default/inngest-server — THE DEAD FILE THAT CAUSED THIS OUTAGE — each left every suite in
# this repo green. The drop-ins carry the credential to vector.service (the instrument every
# post-apply check is read through), inngest-heartbeat.service, and inngest-server.service (which
# runs doppler run unconditionally and is restarted on every deploy), i.e. the three consumers
# with the worst failure modes were the three with no content assertion at all.
#
# Same asymmetry as the sweep above: growth is free (a new 10-*-doppler-token.conf is picked up
# automatically), shrinkage is loud (a KNOWN entry that disappears must be removed deliberately).
DROPIN_LINE='EnvironmentFile=-/etc/default/soleur-doppler-token'
DROPIN_KNOWN=(
  10-vector-doppler-token.conf
  10-inngest-heartbeat-doppler-token.conf
  10-inngest-server-doppler-token.conf
)
DROPIN_FOUND=()
while IFS= read -r f; do [[ -n "$f" ]] && DROPIN_FOUND+=("$f"); done < <(
  ls -1 "$SCRIPT_DIR"/10-*-doppler-token.conf 2>/dev/null | sort
)
if ((${#DROPIN_FOUND[@]} >= ${#DROPIN_KNOWN[@]})); then
  PASS=$((PASS + 1))
  echo "  PASS: drop-in sweep is non-vacuous (${#DROPIN_FOUND[@]} found, floor ${#DROPIN_KNOWN[@]})"
else
  FAIL=$((FAIL + 1))
  echo "  FAIL: drop-in sweep found only ${#DROPIN_FOUND[@]} 10-*-doppler-token.conf file(s), below the floor of ${#DROPIN_KNOWN[@]} — the glob matched nothing or a drop-in was deleted"
fi
for known in "${DROPIN_KNOWN[@]}"; do
  if [[ -f "$SCRIPT_DIR/$known" ]]; then
    PASS=$((PASS + 1)); echo "  PASS: known drop-in present: $known"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: known drop-in $known is GONE — if that is intentional, remove it from DROPIN_KNOWN in the same commit; otherwise a consumer just lost the credential silently"
  fi
done
# The content assertion itself. -x -F (exact full line, literal) so the file's own explanatory
# prose — which quotes this very path several times — can never satisfy it; that is the
# cq-assert-anchor-not-bare-token trap, and these files are comment-heavy by design.
for f in "${DROPIN_FOUND[@]}"; do
  b="$(basename "$f")"
  if grep -qxF -- "$DROPIN_LINE" "$f"; then
    PASS=$((PASS + 1)); echo "  PASS: drop-in carries the override verbatim: $b"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $b does NOT contain the exact line '$DROPIN_LINE' — the drop-in is inert and its unit silently keeps the dead token (#7095)"
  fi
  # A drop-in that points at ANY OTHER /etc/default file is the re-pointing mutation that went
  # green: it still looks like a wired drop-in and still delivers the revoked credential.
  if stray="$(grep -oE '^EnvironmentFile=-?/etc/default/[A-Za-z0-9._-]+' "$f" | grep -vxF -- "$DROPIN_LINE" | sed -n '1p')"; [[ -n "$stray" ]]; then
    FAIL=$((FAIL + 1)); echo "  FAIL: $b also carries '$stray' — a drop-in must point ONLY at the re-deliverable credential; anything else re-introduces the dead-token path"
  else
    PASS=$((PASS + 1)); echo "  PASS: drop-in points at no other /etc/default file: $b"
  fi
done

assert_grep "resolve unit sets HOME (doppler os.UserHomeDir requirement)" 'Environment=HOME=/root' "$SCRIPT_DIR/cron-egress-resolve.service"
assert_grep "resolve unit bounded (no infinite activating hang)" 'TimeoutStartSec=' "$SCRIPT_DIR/cron-egress-resolve.service"
# Grace-window retention store must persist across reboots (a tmpfs /run would
# wipe the accumulated rotation pool and re-open the outage for up to a window).
# StateDirectory= creates /var/lib/cron-egress-resolve (root-owned) before ExecStart.
assert_grep "resolve unit declares persistent StateDirectory for the retention store" 'StateDirectory=cron-egress-resolve' "$SCRIPT_DIR/cron-egress-resolve.service"

echo "-- cross-file literal parity (replicated literals drift silently) --"
SLUG_RESOLVE="$(grep -oE 'SENTRY_SLUG="[^"]+"' "$RESOLVER" | sed -n '1p')"
SLUG_ALARM="$(grep -oE 'SENTRY_SLUG="[^"]+"' "$ALARM" | sed -n '1p')"
if [[ -n "$SLUG_RESOLVE" && "$SLUG_RESOLVE" == "$SLUG_ALARM" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: SENTRY_SLUG identical in resolver + alarm ($SLUG_RESOLVE)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: SENTRY_SLUG drift (resolver=$SLUG_RESOLVE alarm=$SLUG_ALARM)"
fi
SLUG_VAL="$(echo "$SLUG_RESOLVE" | sed -E 's/SENTRY_SLUG="([^"]+)"/\1/')"
assert_grep "Sentry monitor name matches the scripts' slug" "name += +\"$SLUG_VAL\"" "$SCRIPT_DIR/sentry/cron-monitors.tf"
# Drop-prefix parity: the resolver's journal grep must match the loader's
# nft log prefixes, else drops keep happening while the alert goes dark.
for prefix in 'egress-blocked: ' 'egress-dns-exfil: '; do
  if grep -qF "$prefix" "$LOADER" && grep -qE "egress-.blocked.dns-exfil.: " "$RESOLVER"; then
    PASS=$((PASS + 1)); echo "  PASS: drop prefix '$prefix' present in loader and covered by resolver grep"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: drop prefix '$prefix' parity broken between loader and resolver"
  fi
done

echo "-- alarm content invariants --"
assert_grep "alarm posts Sentry error check-in" 'status=error' "$ALARM"
assert_grep "alarm emails via Resend (disk-monitor precedent)" 'api\.resend\.com/emails' "$ALARM"
assert_grep "alarm email cooldown (no per-tick inbox storm)" 'EMAIL_COOLDOWN_SECS' "$ALARM"

echo "-- alarm transport confinement + Sentry destination pin (#7898 §2) --"
# Static rows anchored on SYNTAX (a comment cannot satisfy `^\s*[var="$(]curl …`),
# and on COUNT equality rather than -q: both credentialed curls (Sentry check-in +
# Resend) must carry the four flags first, the positive ingest-apex grammar must
# sit on the `if [[ "$_si_host" =~` call form exactly once, no bare `curl -s` may
# remain, no credentialed curl may follow redirects (`-L` forwards a custom auth
# header cross-host; the Rule D linter has no -L limb), and no invocation may be
# path-qualified (a `/usr/bin/curl` bypasses every PATH stub; the linter's
# CURL_INVOKE does match it — belt-and-braces for the stub chokepoint claim).
CONFINED_CURLS="$(grep -cE "^[[:space:]]*([A-Za-z_]+=\"?\\\$\()?curl --disable --noproxy '\\*' --proto '=https' -g" "$ALARM" || true)"
if [[ "$CONFINED_CURLS" -eq 2 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: both alarm curls are transport-confined (count=2)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: expected exactly 2 confined curl lines in alarm, found $CONFINED_CURLS"
fi
PIN_GRAMMAR_COUNT="$(grep -F 'if [[ "$_si_host" =~ ' "$ALARM" | grep -cF 'ingest\.(de|us)\.sentry\.io$ ]]' || true)"
if [[ "$PIN_GRAMMAR_COUNT" -eq 1 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: alarm carries the positive Sentry ingest-apex grammar on the _si_host test exactly once"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: expected the ingest-apex grammar once on the _si_host test in alarm, found $PIN_GRAMMAR_COUNT"
fi
assert_not_grep "alarm has no unconfined bare 'curl -s' line" '^[[:space:]]*([A-Za-z_]+="?\$\()?curl -s' "$ALARM"
assert_not_grep "alarm credentialed curls never follow redirects (-L/--location)" '^[[:space:]]*([A-Za-z_]+="?\$\()?curl .* (-L|--location)( |$)' "$ALARM"
assert_not_grep "alarm never invokes a path-qualified curl (PATH-stub + linter bypass)" '(^|[[:space:]"(])/[A-Za-z0-9_./-]*/curl([[:space:]]|$)' "$ALARM"

# Exec rows: the alarm under a PATH-shimmed curl / logger / journalctl, with a
# fake Resend key, a TLS-env canary the prologue must unset, and the cooldown
# stamp redirected into a tmpdir. Each row is LABELLED (one verdict per row).
# The curl shim: one line per INVOCATION in curl_args; argv[1..6] + --noproxy
# cardinality + scheme/TLS-canary checks written to curl_violations (never
# exited on); ALARM_MOCK_SENTRY_CODE / ALARM_MOCK_RESEND_CODE set the -w code
# per vendor; ALARM_MOCK_CURL_EXIT makes every call exit non-zero (transport
# failure). The logger shim records the crit rows the alarm ships off-box.
run_alarm() {
  local d="$1"; shift
  mkdir -p "$d/bin"
  cat > "$d/bin/curl" << MOCK
#!/bin/bash
vendor=""; scheme_http=0; has_proto=0; cfg_stdin=0; prev=""
for arg in "\$@"; do
  [[ "\$prev" == "--config" && "\$arg" == "-" ]] && cfg_stdin=1
  prev="\$arg"
  case "\$arg" in
    *api.resend.com*) vendor="api.resend.com" ;;
    *.sentry.io*) vendor="sentry.io" ;;
  esac
  [[ "\$arg" == http://* ]] && scheme_http=1
  [[ "\$arg" == "--proto" ]] && has_proto=1
done
if [[ -n "\$vendor" ]]; then
  echo "\$vendor" >> "$d/curl_checked"
  if [[ "\${1:-}" != "--disable" || "\${2:-}" != "--noproxy" || "\${3:-}" != '*' \\
     || "\${4:-}" != "--proto" || "\${5:-}" != "=https" || "\${6:-}" != "-g" ]]; then
    echo "ARGV_ORDER host=\$vendor" >> "$d/curl_violations"
  fi
  n=0
  for arg in "\$@"; do
    if [[ "\$arg" == "--noproxy" ]]; then n=\$((n + 1)); fi
  done
  if [[ "\$n" -ne 1 ]]; then echo "NOPROXY_COUNT n=\$n" >> "$d/curl_violations"; fi
  if [[ -n "\${SSLKEYLOGFILE:-}\${CURL_CA_BUNDLE:-}" ]]; then echo "TLS_ENV_LEAK" >> "$d/curl_violations"; fi
fi
if [[ "\$scheme_http" -eq 1 && "\$has_proto" -eq 1 ]]; then echo "PROTO_ON_HTTP" >> "$d/curl_violations"; fi
# \`--config -\`: consume (and record) the stdin config so the writer is read
if [[ "\$cfg_stdin" -eq 1 ]]; then cat >> "$d/curl_stdin"; fi
# one line per INVOCATION (the -d payload is multi-line JSON)
echo "\$*" | tr '\\n' ' ' >> "$d/curl_args"; echo >> "$d/curl_args"
if [[ -n "\${ALARM_MOCK_CURL_EXIT:-}" ]]; then echo "000"; exit "\$ALARM_MOCK_CURL_EXIT"; fi
if [[ "\$vendor" == "sentry.io" ]]; then echo "\${ALARM_MOCK_SENTRY_CODE:-200}"; else echo "\${ALARM_MOCK_RESEND_CODE:-200}"; fi
exit 0
MOCK
  cat > "$d/bin/logger" << MOCK
#!/bin/bash
echo "\$*" >> "$d/logger_args"
exit 0
MOCK
  cat > "$d/bin/journalctl" << 'MOCK'
#!/bin/bash
echo "(fixture journal line)"
exit 0
MOCK
  cat > "$d/bin/hostname" << 'MOCK'
#!/bin/bash
echo "test-server-cx33"
MOCK
  chmod +x "$d/bin/"*
  (
    export PATH="$d/bin:$PATH"
    export EMAIL_COOLDOWN_FILE="$d/last-email"
    export RESEND_API_KEY="re_test_fake_key_123"
    # TLS-env canary: the prologue's `unset` must clear these before any curl.
    export SSLKEYLOGFILE="$d/keys.log" CURL_CA_BUNDLE="$d/ca.pem"
    env "$@" bash "$ALARM" "${ALARM_UNIT:-cron-egress-resolve.service}"
  )
}
alarm_curl_lines() { grep -c '' "$1/curl_args" 2>/dev/null || true; }
alarm_row() {   # alarm_row "<description>" <ok-flag> <dir> "<out>"
  if [[ "$2" -eq 1 ]]; then
    PASS=$((PASS + 1)); echo "  PASS: $1"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $1"; echo "        out: $4"
    echo "        curl: $(cat "$3/curl_args" 2>/dev/null)"; echo "        violations: $(cat "$3/curl_violations" 2>/dev/null)"
    echo "        logger: $(cat "$3/logger_args" 2>/dev/null)"
  fi
}
ALARM_TRIPLE_OK=(SENTRY_INGEST_DOMAIN=o0000000.ingest.de.sentry.io SENTRY_PROJECT_ID=4321 SENTRY_PUBLIC_KEY=0123456789abcdef0123456789abcdef)

# Row 1: refused ingest host (the negative fixture) → REFUSED marker with a
# reason TOKEN, exactly one curl (Resend) whose payload carries the note, exit 0.
ALARM_D="$(mktemp -d)"
ALARM_OUT="$(run_alarm "$ALARM_D" SENTRY_INGEST_DOMAIN=ingest.example.test SENTRY_PROJECT_ID=4321 SENTRY_PUBLIC_KEY=0123456789abcdef0123456789abcdef 2>&1)" && ALARM_RC=0 || ALARM_RC=$?
ALARM_OK=1
[[ "$ALARM_RC" -eq 0 ]] || ALARM_OK=0
[[ "$(alarm_curl_lines "$ALARM_D")" -eq 1 ]] || ALARM_OK=0
grep -qF "api.resend.com" "$ALARM_D/curl_args" 2>/dev/null || ALARM_OK=0
grep -qF "sentry channel refused" "$ALARM_D/curl_args" 2>/dev/null || ALARM_OK=0
[[ ! -f "$ALARM_D/curl_violations" ]] || ALARM_OK=0
echo "$ALARM_OUT" | grep -cF "SOLEUR_CRON_EGRESS_ALARM_REFUSED channel=sentry reason=host-shape" >/dev/null || ALARM_OK=0
grep -qF "SOLEUR_CRON_EGRESS_ALARM_REFUSED channel=sentry reason=host-shape" "$ALARM_D/logger_args" 2>/dev/null || ALARM_OK=0
grep -qF "example.test" "$ALARM_D/logger_args" 2>/dev/null && ALARM_OK=0
alarm_row "alarm exec: refused host → REFUSED marker (reason token), one confined Resend curl carrying the note, exit 0" "$ALARM_OK" "$ALARM_D" "$ALARM_OUT"
rm -rf "$ALARM_D"

# Row 1b/1c: project id with a traversal suffix, and a non-hex key, with a valid
# host → reason=project-shape / reason=key-shape, no Sentry curl.
for ALARM_CASE in "SENTRY_PROJECT_ID=4321/../evil project-shape" "SENTRY_PUBLIC_KEY=pubkey_test key-shape"; do
  ALARM_D="$(mktemp -d)"
  ALARM_OUT="$(run_alarm "$ALARM_D" "${ALARM_TRIPLE_OK[@]}" "${ALARM_CASE% *}" 2>&1)" && ALARM_RC=0 || ALARM_RC=$?
  ALARM_OK=1
  [[ "$ALARM_RC" -eq 0 ]] || ALARM_OK=0
  grep -qF "sentry.io" "$ALARM_D/curl_args" 2>/dev/null && ALARM_OK=0
  echo "$ALARM_OUT" | grep -cF "SOLEUR_CRON_EGRESS_ALARM_REFUSED channel=sentry reason=${ALARM_CASE##* }" >/dev/null || ALARM_OK=0
  grep -qF "api.resend.com" "$ALARM_D/curl_args" 2>/dev/null || ALARM_OK=0
  alarm_row "alarm exec: ${ALARM_CASE% *} is refused with reason=${ALARM_CASE##* }; Resend still sends" "$ALARM_OK" "$ALARM_D" "$ALARM_OUT"
  rm -rf "$ALARM_D"
done

# Row 2: must-PASS non-canonical host (uppercase + trailing dot) → two confined
# curls, the first to the FOLDED host; no violations (argv order, --noproxy
# cardinality, TLS canary cleared).
ALARM_D="$(mktemp -d)"
ALARM_OUT="$(run_alarm "$ALARM_D" SENTRY_INGEST_DOMAIN=O0000000.INGEST.DE.SENTRY.IO. SENTRY_PROJECT_ID=4321 SENTRY_PUBLIC_KEY=0123456789abcdef0123456789abcdef 2>&1)" && ALARM_RC=0 || ALARM_RC=$?
ALARM_OK=1
[[ "$ALARM_RC" -eq 0 ]] || ALARM_OK=0
[[ "$(alarm_curl_lines "$ALARM_D")" -eq 2 ]] || ALARM_OK=0
[[ "$(grep -c '' "$ALARM_D/curl_checked" 2>/dev/null || true)" -eq 2 ]] || ALARM_OK=0
[[ ! -f "$ALARM_D/curl_violations" ]] || ALARM_OK=0
head -1 "$ALARM_D/curl_args" 2>/dev/null | grep -cF "https://o0000000.ingest.de.sentry.io/api/4321/cron/" >/dev/null || ALARM_OK=0
grep -qF "INGEST.DE.SENTRY.IO" "$ALARM_D/curl_args" 2>/dev/null && ALARM_OK=0
echo "$ALARM_OUT" | grep -cF "_REFUSED channel=sentry" >/dev/null && ALARM_OK=0
[[ -f "$ALARM_D/logger_args" ]] && ALARM_OK=0    # a clean send ships no crit row
[[ -e "$ALARM_D/last-email" ]] || ALARM_OK=0     # 2xx wrote the cooldown stamp
alarm_row "alarm exec: uppercase + trailing-dot host accepted; two confined curls (checked=2, no violations), folded host first, stamp written, no crit row" "$ALARM_OK" "$ALARM_D" "$ALARM_OUT"
rm -rf "$ALARM_D"

# Row 3: cooldown stamp present + Sentry triple unset → ZERO curls; the
# suppressed email and the unset Sentry channel each ship a SEND_SKIPPED row
# (a deliberate skip, never SEND_FAILED — an alert rule on SEND_FAILED must not
# page on configuration), and the log line does not claim a Sentry post.
ALARM_D="$(mktemp -d)"
touch "$ALARM_D/last-email"
ALARM_OUT="$(run_alarm "$ALARM_D" -u SENTRY_INGEST_DOMAIN -u SENTRY_PROJECT_ID -u SENTRY_PUBLIC_KEY 2>&1)" && ALARM_RC=0 || ALARM_RC=$?
ALARM_OK=1
[[ "$ALARM_RC" -eq 0 ]] || ALARM_OK=0
[[ ! -f "$ALARM_D/curl_args" ]] || ALARM_OK=0
grep -qF "SOLEUR_CRON_EGRESS_ALARM_SEND_SKIPPED channel=resend reason=cooldown unit=cron-egress-resolve.service" "$ALARM_D/logger_args" 2>/dev/null || ALARM_OK=0
grep -qF "SOLEUR_CRON_EGRESS_ALARM_SEND_SKIPPED channel=sentry reason=unset" "$ALARM_D/logger_args" 2>/dev/null || ALARM_OK=0
grep -qF "_SEND_FAILED" "$ALARM_D/logger_args" 2>/dev/null && ALARM_OK=0
grep -qF -- "-p user.crit" "$ALARM_D/logger_args" 2>/dev/null || ALARM_OK=0
grep -qF -- "-t cron-egress-alarm" "$ALARM_D/logger_args" 2>/dev/null || ALARM_OK=0
echo "$ALARM_OUT" | grep -cF "Sentry check-in still posted" >/dev/null && ALARM_OK=0
alarm_row "alarm exec: cooldown active + triple unset → zero curls, SEND_SKIPPED rows for both channels (never SEND_FAILED)" "$ALARM_OK" "$ALARM_D" "$ALARM_OUT"
rm -rf "$ALARM_D"

# Row 4: Sentry triple UNSET, no cooldown → exactly one confined (Resend) curl,
# exit 0 (an unbound read on this path under set -u would abort the only
# surviving channel); the Sentry skip ships a SEND_SKIPPED row, not a refusal.
ALARM_D="$(mktemp -d)"
ALARM_OUT="$(run_alarm "$ALARM_D" -u SENTRY_INGEST_DOMAIN -u SENTRY_PROJECT_ID -u SENTRY_PUBLIC_KEY 2>&1)" && ALARM_RC=0 || ALARM_RC=$?
ALARM_OK=1
[[ "$ALARM_RC" -eq 0 ]] || ALARM_OK=0
[[ "$(alarm_curl_lines "$ALARM_D")" -eq 1 ]] || ALARM_OK=0
grep -qF "api.resend.com" "$ALARM_D/curl_args" 2>/dev/null || ALARM_OK=0
[[ ! -f "$ALARM_D/curl_violations" ]] || ALARM_OK=0
echo "$ALARM_OUT" | grep -cF "Sentry env unset" >/dev/null || ALARM_OK=0
echo "$ALARM_OUT" | grep -cF "_REFUSED channel=sentry" >/dev/null && ALARM_OK=0
grep -qF "SOLEUR_CRON_EGRESS_ALARM_SEND_SKIPPED channel=sentry reason=unset" "$ALARM_D/logger_args" 2>/dev/null || ALARM_OK=0
alarm_row "alarm exec: triple unset → one confined Resend curl, SEND_SKIPPED channel=sentry reason=unset, exit 0" "$ALARM_OK" "$ALARM_D" "$ALARM_OUT"
rm -rf "$ALARM_D"

# Row 5: Resend answers 500 → the cooldown stamp is NOT written (the next fire
# retries) and a SEND_FAILED row carries the code with curl's exit (0: the
# transport succeeded, the vendor refused).
ALARM_D="$(mktemp -d)"
ALARM_OUT="$(run_alarm "$ALARM_D" "${ALARM_TRIPLE_OK[@]}" ALARM_MOCK_RESEND_CODE=500 2>&1)" && ALARM_RC=0 || ALARM_RC=$?
ALARM_OK=1
[[ "$ALARM_RC" -eq 0 ]] || ALARM_OK=0
[[ ! -e "$ALARM_D/last-email" ]] || ALARM_OK=0
grep -qF "SOLEUR_CRON_EGRESS_ALARM_SEND_FAILED channel=resend http_code=500 rc=0" "$ALARM_D/logger_args" 2>/dev/null || ALARM_OK=0
grep -qF "channel=sentry" "$ALARM_D/logger_args" 2>/dev/null && ALARM_OK=0   # Sentry side was healthy
alarm_row "alarm exec: Resend 500 → no cooldown stamp, SEND_FAILED channel=resend http_code=500 rc=0" "$ALARM_OK" "$ALARM_D" "$ALARM_OUT"
rm -rf "$ALARM_D"

# Row 6: Sentry answers 500 with a valid triple → SEND_FAILED channel=sentry
# http_code=500 rc=0; the Resend channel still sends (stamp written).
ALARM_D="$(mktemp -d)"
ALARM_OUT="$(run_alarm "$ALARM_D" "${ALARM_TRIPLE_OK[@]}" ALARM_MOCK_SENTRY_CODE=500 2>&1)" && ALARM_RC=0 || ALARM_RC=$?
ALARM_OK=1
[[ "$ALARM_RC" -eq 0 ]] || ALARM_OK=0
grep -qF "SOLEUR_CRON_EGRESS_ALARM_SEND_FAILED channel=sentry http_code=500 rc=0" "$ALARM_D/logger_args" 2>/dev/null || ALARM_OK=0
[[ -e "$ALARM_D/last-email" ]] || ALARM_OK=0
[[ "$(alarm_curl_lines "$ALARM_D")" -eq 2 ]] || ALARM_OK=0
alarm_row "alarm exec: Sentry 500 → SEND_FAILED channel=sentry http_code=500 rc=0; Resend still sends" "$ALARM_OK" "$ALARM_D" "$ALARM_OUT"
rm -rf "$ALARM_D"

# Row 7: transport failure (curl exits 7) on both channels → http_code=000 with
# curl's exit status as the reason token, exit 0 kept.
ALARM_D="$(mktemp -d)"
ALARM_OUT="$(run_alarm "$ALARM_D" "${ALARM_TRIPLE_OK[@]}" ALARM_MOCK_CURL_EXIT=7 2>&1)" && ALARM_RC=0 || ALARM_RC=$?
ALARM_OK=1
[[ "$ALARM_RC" -eq 0 ]] || ALARM_OK=0
grep -qF "SOLEUR_CRON_EGRESS_ALARM_SEND_FAILED channel=sentry http_code=000 rc=7" "$ALARM_D/logger_args" 2>/dev/null || ALARM_OK=0
grep -qF "SOLEUR_CRON_EGRESS_ALARM_SEND_FAILED channel=resend http_code=000 rc=7" "$ALARM_D/logger_args" 2>/dev/null || ALARM_OK=0
[[ ! -e "$ALARM_D/last-email" ]] || ALARM_OK=0
alarm_row "alarm exec: curl exit 7 on both channels → http_code=000 rc=7 rows, no stamp, exit 0" "$ALARM_OK" "$ALARM_D" "$ALARM_OUT"
rm -rf "$ALARM_D"

# Row 8: a hostile %n → the unit token collapses to the sentinel before the
# first marker; nothing else changes.
ALARM_D="$(mktemp -d)"
touch "$ALARM_D/last-email"
ALARM_OUT="$(ALARM_UNIT='../evil' run_alarm "$ALARM_D" -u SENTRY_INGEST_DOMAIN -u SENTRY_PROJECT_ID -u SENTRY_PUBLIC_KEY 2>&1)" && ALARM_RC=0 || ALARM_RC=$?
ALARM_OK=1
[[ "$ALARM_RC" -eq 0 ]] || ALARM_OK=0
grep -qF "reason=cooldown unit=invalid-unit-name" "$ALARM_D/logger_args" 2>/dev/null || ALARM_OK=0
grep -qF "../evil" "$ALARM_D/logger_args" 2>/dev/null && ALARM_OK=0
alarm_row "alarm exec: a %n outside the unit-name charset reads unit=invalid-unit-name in every marker" "$ALARM_OK" "$ALARM_D" "$ALARM_OUT"
rm -rf "$ALARM_D"

# Rows 9-10 (argv-bearer sweep): the Resend key rides curl's stdin config
# channel, never argv; a key that fails the token-shape guard takes the existing
# SEND_SKIPPED arm (reason=token_shape) with NO call to api.resend.com.
# Row 9: valid synthetic key -> argv clean, stdin exact, no violations, exit 0.
ALARM_D="$(mktemp -d -t alarm-bearer.XXXXXXXX)"
ALARM_OUT="$(run_alarm "$ALARM_D" "${ALARM_TRIPLE_OK[@]}" 2>&1)" && ALARM_RC=0 || ALARM_RC=$?
ALARM_OK=1
[[ "$ALARM_RC" -eq 0 ]] || ALARM_OK=0
grep -qF "api.resend.com" "$ALARM_D/curl_args" 2>/dev/null || ALARM_OK=0
grep -qF "re_test_fake_key_123" "$ALARM_D/curl_args" 2>/dev/null && ALARM_OK=0
grep -qF "Authorization" "$ALARM_D/curl_args" 2>/dev/null && ALARM_OK=0
grep -qF -- "--config -" "$ALARM_D/curl_args" 2>/dev/null || ALARM_OK=0
[[ "$(cat "$ALARM_D/curl_stdin" 2>/dev/null)" == 'header = "Authorization: Bearer re_test_fake_key_123"' ]] || ALARM_OK=0
[[ ! -f "$ALARM_D/curl_violations" ]] || ALARM_OK=0
[[ -e "$ALARM_D/last-email" ]] || ALARM_OK=0
alarm_row "alarm exec: Resend key absent from curl argv, exact 'header = \"Authorization: Bearer <key>\"' on the --config - stdin, 2xx stamps cooldown" "$ALARM_OK" "$ALARM_D" "$ALARM_OUT"
rm -rf "$ALARM_D"

# Row 10: malformed keys (space, double quote, embedded newline) -> never reach
# curl; SEND_SKIPPED channel=resend reason=token_shape; Sentry channel still
# posts; exit 0 as for every other skip; the key never appears in output/logger.
for ALARM_BAD in "re_test fake key" 're_test"fake' $'re_test\nheader = "x"'; do
  ALARM_D="$(mktemp -d -t alarm-bearer.XXXXXXXX)"
  ALARM_OUT="$(run_alarm "$ALARM_D" "${ALARM_TRIPLE_OK[@]}" "RESEND_API_KEY=$ALARM_BAD" 2>&1)" && ALARM_RC=0 || ALARM_RC=$?
  ALARM_OK=1
  [[ "$ALARM_RC" -eq 0 ]] || ALARM_OK=0
  grep -qF "api.resend.com" "$ALARM_D/curl_args" 2>/dev/null && ALARM_OK=0
  [[ ! -e "$ALARM_D/curl_stdin" ]] || ALARM_OK=0
  [[ ! -e "$ALARM_D/last-email" ]] || ALARM_OK=0
  grep -qF "sentry.io" "$ALARM_D/curl_args" 2>/dev/null || ALARM_OK=0
  grep -qF "SOLEUR_CRON_EGRESS_ALARM_SEND_SKIPPED channel=resend reason=token_shape unit=cron-egress-resolve.service" "$ALARM_D/logger_args" 2>/dev/null || ALARM_OK=0
  grep -cF "SOLEUR_CRON_EGRESS_ALARM_SEND_SKIPPED channel=resend reason=token_shape" >/dev/null <<<"$ALARM_OUT" || ALARM_OK=0
  grep -qF "_SEND_FAILED" "$ALARM_D/logger_args" 2>/dev/null && ALARM_OK=0
  grep -qF "fake" "$ALARM_D/logger_args" 2>/dev/null && ALARM_OK=0
  alarm_row "alarm exec: malformed Resend key ($(printf '%q' "$ALARM_BAD" | cut -c1-12)...) -> no Resend curl, SEND_SKIPPED reason=token_shape, exit 0" "$ALARM_OK" "$ALARM_D" "$ALARM_OUT"
  rm -rf "$ALARM_D"
done

# Parity rows. (a) The predicate-only `sentry-dest-pin` region must be BYTE-
# IDENTICAL in the alarm (inside sentry_checkin()) and container-restart-
# monitor.sh (inside sentry_event()) — same indentation, no normalisation.
# Both extractions must be non-empty and terminated: a missing marker must not
# diff two empty strings green. (b) `export LC_ALL=C` — which the region's
# [a-z0-9]/[a-f0-9] classes depend on and which sits OUTSIDE the region —
# must appear exactly once in each file.
PIN_ALARM="$(sed -n '/# BEGIN sentry-dest-pin (#7898)/,/# END sentry-dest-pin (#7898)/p' "$ALARM")"
PIN_MONITOR="$(sed -n '/# BEGIN sentry-dest-pin (#7898)/,/# END sentry-dest-pin (#7898)/p' "$SCRIPT_DIR/container-restart-monitor.sh")"
if [[ -z "$PIN_ALARM" || -z "$PIN_MONITOR" ]]; then
  FAIL=$((FAIL + 1)); echo "  FAIL: sentry-dest-pin region missing (alarm=$(echo -n "$PIN_ALARM" | wc -c)B monitor=$(echo -n "$PIN_MONITOR" | wc -c)B) — a missing BEGIN/END marker must not read as parity"
elif ! grep -qF "# END sentry-dest-pin (#7898)" <<<"$PIN_ALARM" || ! grep -qF "# END sentry-dest-pin (#7898)" <<<"$PIN_MONITOR"; then
  FAIL=$((FAIL + 1)); echo "  FAIL: sentry-dest-pin region is unterminated in alarm or monitor (END marker absent)"
elif [[ "$PIN_ALARM" == "$PIN_MONITOR" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: sentry-dest-pin predicate is byte-identical in alarm and container-restart-monitor.sh"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: sentry-dest-pin predicate drifted between alarm and container-restart-monitor.sh:"; diff <(echo "$PIN_ALARM") <(echo "$PIN_MONITOR") | sed 's/^/        /' || true
fi
LC_ALARM="$(grep -c '^export LC_ALL=C$' "$ALARM" || true)"; LC_MONITOR="$(grep -c '^export LC_ALL=C$' "$SCRIPT_DIR/container-restart-monitor.sh" || true)"
if [[ "$LC_ALARM" -eq 1 && "$LC_MONITOR" -eq 1 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: export LC_ALL=C pinned exactly once in alarm and container-restart-monitor.sh (the pin's classes depend on it)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: export LC_ALL=C count alarm=$LC_ALARM monitor=$LC_MONITOR (expected 1 and 1)"
fi
# (c) emit_refusal() is pasted into the four host scripts; the alarm's copy is
# the only one without a logger-absent exec row, so pin it to the copies that
# have one. Function bodies extracted verbatim; all four must be identical.
EMIT_REF="$(sed -n '/^emit_refusal() {/,/^}/p' "$SCRIPT_DIR/disk-monitor.sh")"
EMIT_DRIFT=""
for EMIT_F in resource-monitor.sh container-restart-monitor.sh cron-egress-alarm.sh; do
  [[ "$(sed -n '/^emit_refusal() {/,/^}/p' "$SCRIPT_DIR/$EMIT_F")" == "$EMIT_REF" ]] || EMIT_DRIFT+="$EMIT_F "
done
if [[ -z "$EMIT_REF" ]]; then
  FAIL=$((FAIL + 1)); echo "  FAIL: emit_refusal() not found in disk-monitor.sh (parity reference missing)"
elif [[ -z "$EMIT_DRIFT" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: emit_refusal() is byte-identical across the four host monitors"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: emit_refusal() drifted from disk-monitor.sh in: $EMIT_DRIFT"
fi

echo "-- allowlist completeness (grep-enumerated runtime hosts) --"
for host in api.anthropic.com github.com api.github.com api.doppler.com \
  edge.api.flagsmith.com api.x.com api.linkedin.com bsky.social discord.com \
  plausible.io api.resend.com api.buttondown.com api.cloudflare.com \
  api.stripe.com api.hetzner.cloud fcm.googleapis.com \
  updates.push.services.mozilla.com web.push.apple.com \
  soleur.ai app.soleur.ai api.soleur.ai api.supabase.com \
  registry.npmjs.org; do
  # -Fxq = exact full-line literal (dots are NOT wildcards)
  if grep -Fxq -- "$host" "$ALLOWLIST"; then
    PASS=$((PASS + 1)); echo "  PASS: allowlists $host"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: allowlists $host (exact line not found)"
  fi
done
# Exact-set guard: a NEW host (the firewall's entire attack-surface dial)
# must force a deliberate edit here carrying its evidence.
# Count is 123 since the Actions-log + npm-registry egress widening (24
# vendor hosts + 99 productionresultssa<N>.blob.core.windows.net accounts —
# sa0..99 minus sa22, which NXDOMAINs). The CIDR ranges live in a SEPARATE
# interval set/file (cron-egress-allowlist-cidr.txt) and are NOT counted here.
HOST_COUNT="$(grep -vcE '^[[:space:]]*#|^[[:space:]]*$' "$ALLOWLIST")"
if [[ "$HOST_COUNT" -eq 123 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: allowlist host count is exactly 123"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: allowlist host count is $HOST_COUNT (expected 123 — update BOTH the allowlist and this test with evidence)"
fi
# Actions-blob fleet guard: the signed-URL accounts are exact hosts, so the
# fleet boundaries AND the sa22 hole are pinned — a deleted account that
# reappears in the file would NXDOMAIN-page via the resolver failcount.
assert_grep "allowlists productionresultssa0 (fleet lower bound)" '^productionresultssa0\.blob\.core\.windows\.net$' "$ALLOWLIST"
assert_grep "allowlists productionresultssa99 (fleet upper bound)" '^productionresultssa99\.blob\.core\.windows\.net$' "$ALLOWLIST"
assert_not_grep "sa22 is NXDOMAIN — must NOT be allowlisted (resolver failcount would page)" '^productionresultssa22\.blob\.core\.windows\.net$' "$ALLOWLIST"
SA_FLEET="$(grep -cE '^productionresultssa[0-9]+\.blob\.core\.windows\.net$' "$ALLOWLIST" || true)"
if [[ "$SA_FLEET" -eq 99 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: productionresultssa fleet is exactly 99 hosts"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: productionresultssa fleet count is $SA_FLEET (expected 99 — verify each member resolves before adding/removing; an NXDOMAIN member pages via the resolver failcount)"
fi
assert_not_grep "Better Stack is HOST egress (must not be in the container allowlist)" '^(logs\.)?(betterstack|betteruptime)' "$ALLOWLIST"
assert_not_grep "GHCR is HOST egress (must not be in the container allowlist)" '^ghcr\.io$' "$ALLOWLIST"

echo "-- GHCR carve (#9275): resolver probe wiring + census --"
# Static wiring of the in-container GHCR probe in cron-egress-resolve.sh. Whole-line comments are
# stripped first so a comment naming a symbol cannot satisfy an anchor that pins the CODE
# (cq-assert-anchor-not-bare-token). Behavioural proof of the verdict / counter lives with the
# resolver slice's table test; this block pins that the pieces EXIST and that the reserved source-port
# range is defined ONCE and consumed at BOTH sites (the curl flag and the drop sampler), so the two
# cannot drift apart (a drift would either flood egress_blocked with the probe's own drops or hide
# real ones).
assert_fixture_dir "$SUITE_SCRATCH"
RESOLVER_CODE="$SUITE_SCRATCH/resolver.code"
grep -vE '^[[:space:]]*#' "$RESOLVER" > "$RESOLVER_CODE"
assert_grep "resolver defines ghcr_probe_verdict (pure verdict function)" '^ghcr_probe_verdict\(\) \{' "$RESOLVER_CODE"
assert_grep "resolver defines ghcr_probe_blind_step (blind counter)" '^ghcr_probe_blind_step\(\) \{' "$RESOLVER_CODE"
assert_grep "resolver defines run_ghcr_probe (dispatch)" '^run_ghcr_probe\(\) \{' "$RESOLVER_CODE"
assert_grep "probe source-port range LO constant defined once (49100)" '^(readonly )?GHCR_PROBE_PORT_LO=49100$' "$RESOLVER_CODE"
assert_grep "probe source-port range HI constant defined once (49199)" '^(readonly )?GHCR_PROBE_PORT_HI=49199$' "$RESOLVER_CODE"
assert_grep "resolver emits op ghcr_deny_lost via a quoted literal" '"ghcr_deny_lost"' "$RESOLVER_CODE"
assert_grep "resolver emits op ghcr_deny_probe_blind via a quoted literal" '"ghcr_deny_probe_blind"' "$RESOLVER_CODE"
assert_grep "curl flag site derives --local-port from BOTH GHCR_PROBE_PORT_ constants" \
  '--local-port[^|]*GHCR_PROBE_PORT_LO[^|]*GHCR_PROBE_PORT_HI' "$RESOLVER_CODE"
# Sampler site: a line that is neither a definition nor the curl flag still consumes the constants
# (e.g. `awk -v lo="$GHCR_PROBE_PORT_LO"`), keyed to SPT / DPT 443 and the `# Excluded` header.
SAMPLER_CONST_USES="$(grep -E 'GHCR_PROBE_PORT_(LO|HI)' "$RESOLVER_CODE" | grep -vE '^(readonly )?GHCR_PROBE_PORT_(LO|HI)=|--local-port' | grep -c '' || true)"
if [[ "${SAMPLER_CONST_USES:-0}" -ge 1 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: sampler site consumes the GHCR_PROBE_PORT_ constants ($SAMPLER_CONST_USES line(s) beyond the definitions and the curl flag)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: no sampler line consumes GHCR_PROBE_PORT_LO/HI (the drop filter is not tied to the probe's reserved range)"
fi
# SPT anchors: the awk call that RECEIVES the reserved port range, and the field-match that reads SPT=
# off the kernel line (a bare `SPT` token would be satisfied by any comment-free mention).
assert_grep "sampler awk call receives the reserved port range (awk -v plo=.. -v phi=..)" \
  'awk -v plo="\$GHCR_PROBE_PORT_LO" -v phi="\$GHCR_PROBE_PORT_HI"' "$RESOLVER_CODE"
assert_grep "sampler filter keys on the source port (SPT=<digits> field match)" '~ /\^SPT=\[0-9\]\+\$/' "$RESOLVER_CODE"
assert_grep "sampler filter keys on destination port 443 (DPT)" '(dpt|DPT)[^[:alnum:]]*443' "$RESOLVER_CODE"
assert_grep "sampler filter reads the generator's Excluded header (DST containment)" 'Excluded [(]GitHub Packages frontends[)]' "$RESOLVER_CODE"
assert_not_grep "no ghcr.io/jikig-ai literal in the baked resolver (G1 census: a pull/login literal is a regression)" 'ghcr\.io/jikig-ai' "$RESOLVER_CODE"

# Floor parity (B8): the minimum Excluded-prefix length is spelled in FOUR places that must agree: the
# generator (MIN_HOLE_PFX), the resolver sampler (awk `c[2] + 0 < N`), the post-apply assert (the
# prefix alternation of its header regex) and this suite (HDR_PFX_RE). Each is extracted from its own
# source with an anchored pattern and must occur EXACTLY ONCE; any drift or a vanished anchor REDs.
GEN_SCRIPT="$SCRIPT_DIR/scripts/gen-github-egress-cidr.sh"
ASSERT_CODE="$SUITE_SCRATCH/assert.code"
grep -vE '^[[:space:]]*#' "$ASSERT_SCRIPT" > "$ASSERT_CODE"
min_from_alt() {   # min_from_alt <ERE alternation like (2[89]|3[0-2])> -> smallest prefix length 0..99 it accepts
  local p
  for p in $(seq 0 99); do [[ "$p" =~ ^$1$ ]] && { echo "$p"; return 0; }; done
  echo none
}
PFX_GEN_N="$(grep -cE '^MIN_HOLE_PFX=[0-9]+( |$)' "$GEN_SCRIPT" || true)"
PFX_GEN="$(sed -nE 's/^MIN_HOLE_PFX=([0-9]+)( .*|)$/\1/p' "$GEN_SCRIPT")"
PFX_RES_N="$(grep -cE 'c\[2\] \+ 0 < [0-9]+' "$RESOLVER_CODE" || true)"
PFX_RES="$(sed -nE 's/.*c\[2\] \+ 0 < ([0-9]+).*/\1/p' "$RESOLVER_CODE")"
PFX_ASSERT_N="$(grep -cE '[)]/\([^()]*\)\$ \]\]' "$ASSERT_CODE" || true)"
PFX_ASSERT_ALT="$(sed -nE 's#.*[)]/(\([^()]*\))\$ \]\].*#\1#p' "$ASSERT_CODE")"
PFX_ASSERT="$(min_from_alt "$PFX_ASSERT_ALT")"
PFX_SUITE_N="$(grep -cE "^HDR_PFX_RE='" "${BASH_SOURCE[0]}" || true)"
PFX_SUITE="$(min_from_alt "$HDR_PFX_RE")"
if [[ "$PFX_GEN_N" -eq 1 && "$PFX_RES_N" -eq 1 && "$PFX_ASSERT_N" -eq 1 && "$PFX_SUITE_N" -eq 1 \
  && "$PFX_GEN" =~ ^[0-9]+$ && "$PFX_GEN" -eq 28 && "$PFX_RES" == "$PFX_GEN" && "$PFX_ASSERT" == "$PFX_GEN" && "$PFX_SUITE" == "$PFX_GEN" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: hole-prefix floor /$PFX_GEN is identical in the generator, resolver sampler, post-apply assert and this suite (one anchor each)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: hole-prefix floor parity (generator=${PFX_GEN:-?} x$PFX_GEN_N, resolver=${PFX_RES:-?} x$PFX_RES_N, assert=${PFX_ASSERT:-?} x$PFX_ASSERT_N, suite=${PFX_SUITE:-?} x$PFX_SUITE_N; all must be 28, once each)"
fi

# Census (plan Guard 3): nothing in a bridge container needs GHCR, so no sandbox domain list and no
# by-name allowlist entry may name ghcr.io, *.pkg.github.com or *.githubusercontent.com, and the
# server tree carries no such literal outside an explicit exemption list. ADVISORY evidence for P5
# (a later change that makes a bridge container need GHCR trips a test, not an outage); the
# runtime probe stays the control. Functions take their input as an argument so the self-tests below
# can feed synthetic trees (a scanner that scans zero files must RED, not pass vacuously).
GHCR_HOST_RE='ghcr\.io|pkg\.github\.com|githubusercontent'
SERVER_CENSUS_RE='githubusercontent|codeload|objects\.github|release-assets|pkg\.github\.com|ghcr\.io'
# Explicit exemptions (repo-relative to the scanned dir). Empty today (0 hits, 2026-10-01).
SERVER_CENSUS_EXEMPT=()
sandbox_domains() {   # sandbox_domains <ts-file> -> sorted literal entries under EITHER egress const, one per line
  awk '/(ENTITLED_EGRESS_DOMAINS|GITHUB_ACTIONS_LOG_ACCOUNTS) = Object\.freeze\(\[/ { grab = 1; next } grab && /\] as const/ { grab = 0 } grab' "$1" \
    | grep -oE '"[^"]+"' | tr -d '"' | sort
}
expected_domains_sorted() {   # expected_domains_sorted -> the census-approved set: 3 base hosts + sa0..99 minus sa22 (NXDOMAIN)
  { echo api.github.com; echo github.com; echo registry.npmjs.org
    for i in $(seq 0 99); do
      [[ "$i" -eq 22 ]] || echo "productionresultssa$i.blob.core.windows.net"
    done; } | sort
}
sandbox_domains_ok() {   # sandbox_domains_ok <sorted domains, one per line> -> 0 iff EXACTLY the expected set (computed, not hardcoded, so the 99-account fleet stays readable)
  [[ "$1" == "$(expected_domains_sorted)" ]]
}
allowlist_ghcr_hits() {   # allowlist_ghcr_hits <file> -> non-comment lines naming a GHCR / Packages / usercontent host (case-insensitive: DNS names are)
  grep -vE '^[[:space:]]*(#|$)' "$1" | grep -iE "$GHCR_HOST_RE" || true
}
server_census_scan() {   # server_census_scan <dir> -> "SCANNED <n>" then one "HIT <file>" per offending file
  local dir="$1" n=0 f ex skip
  while IFS= read -r f; do
    n=$((n + 1))
    skip=0
    for ex in "${SERVER_CENSUS_EXEMPT[@]:-}"; do [[ -n "$ex" && "$f" == "$dir/$ex" ]] && skip=1; done
    [[ "$skip" -eq 1 ]] && continue
    grep -qiE "$SERVER_CENSUS_RE" "$f" 2>/dev/null && echo "HIT $f"
  done < <(find "$dir" -type f ! -name '*.test.*' 2>/dev/null | LC_ALL=C sort)
  echo "SCANNED $n"
}
SANDBOX_CFG="$SCRIPT_DIR/../server/agent-runner-sandbox-config.ts"
SERVER_DIR="$SCRIPT_DIR/../server"
SANDBOX_DOMAINS="$(sandbox_domains "$SANDBOX_CFG")"
if sandbox_domains_ok "$SANDBOX_DOMAINS"; then
  PASS=$((PASS + 1)); echo "  PASS: census: egress domain consts are exactly github.com + api.github.com + registry.npmjs.org + the 99 productionresultssa accounts"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: census: egress domain consts drifted from the approved set (got: $(echo "$SANDBOX_DOMAINS" | tr '\n' ' ')); widening needs its own security review AND a decision on the GHCR deny"
fi
# Read floor: an unreadable / emptied / relocated allowlist yields ZERO hits and would read as "clean".
ALLOW_ENTRIES="$(grep -vcE '^[[:space:]]*(#|$)' "$ALLOWLIST" 2>/dev/null || true)"
if [[ -r "$ALLOWLIST" && "${ALLOW_ENTRIES:-0}" -ge 10 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: census read the real allowlist ($ALLOW_ENTRIES non-comment entries, floor >= 10)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: census read only ${ALLOW_ENTRIES:-0} entries from $ALLOWLIST (floor 10: a missing file would pass as clean)"
fi
ALLOW_GHCR_HITS="$(allowlist_ghcr_hits "$ALLOWLIST")"
if [[ -z "$ALLOW_GHCR_HITS" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: census: cron-egress-allowlist.txt names no GHCR, *.pkg.github.com or *.githubusercontent.com host"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: census: cron-egress-allowlist.txt names a GHCR/Packages/usercontent host: $ALLOW_GHCR_HITS"
fi
SERVER_SCAN="$(server_census_scan "$SERVER_DIR")"
SERVER_SCANNED="$(echo "$SERVER_SCAN" | sed -n 's/^SCANNED //p')"
SERVER_HITS="$(echo "$SERVER_SCAN" | grep '^HIT ' || true)"
if [[ -z "$SERVER_HITS" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: census: no GHCR / Packages / githubusercontent literal under apps/web-platform/server (scanned $SERVER_SCANNED files)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: census: server tree names a GHCR/Packages/usercontent host (a bridge container must not need one): $SERVER_HITS"
fi
if [[ "${SERVER_SCANNED:-0}" -ge 100 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: census scanned $SERVER_SCANNED server files (floor >= 100)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: census scanned only ${SERVER_SCANNED:-0} server files (floor 100: the scan is vacuous)"
fi
# Self-tests of the scanners on synthetic input (mutation rows 1, 2, 3, 4, 5 of Guard 3 in-suite).
CEN_D="$(mktemp -d)"
assert_fixture_dir "$CEN_D"
mkdir -p "$CEN_D/server/sub" "$CEN_D/empty" "$CEN_D/scripts"
echo 'const ok = "https://api.github.com/";' > "$CEN_D/server/a.ts"
echo 'fetch("https://ghcr.io/v2/");' > "$CEN_D/server/sub/b.ts"
echo 'const OIDC = "https://token.actions.githubusercontent.com";' > "$CEN_D/scripts/provision.sh"
CEN_SCAN="$(server_census_scan "$CEN_D/server")"
if grep -qF "HIT $CEN_D/server/sub/b.ts" <<<"$CEN_SCAN" && ! grep -qF "HIT $CEN_D/server/a.ts" <<<"$CEN_SCAN" && grep -qx 'SCANNED 2' <<<"$CEN_SCAN"; then
  PASS=$((PASS + 1)); echo "  PASS: census self-test: a ghcr.io literal in a server file is flagged, a clean file is not"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: census self-test: server scanner did not flag exactly b.ts (got: $(echo "$CEN_SCAN" | tr '\n' ';'))"
fi
CEN_NOT_SCANNED="$(server_census_scan "$CEN_D/server" | grep -c 'provision.sh' || true)"
if [[ "$CEN_NOT_SCANNED" -eq 0 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: census self-test: the OIDC issuer string outside the scanned server tree does not trip the server census (must-PASS non-canonical)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: census self-test: a script outside the server tree was scanned"
fi
CEN_EMPTY="$(server_census_scan "$CEN_D/empty")"
if grep -qx 'SCANNED 0' <<<"$CEN_EMPTY"; then
  PASS=$((PASS + 1)); echo "  PASS: census self-test: an empty tree reports SCANNED 0 (the floor above turns that into a RED)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: census self-test: empty tree did not report SCANNED 0 (got: $CEN_EMPTY)"
fi
printf 'export const ENTITLED_EGRESS_DOMAINS = Object.freeze([\n  "github.com",\n  "api.github.com",\n  "raw.githubusercontent.com",\n] as const);\n' > "$CEN_D/cfg-widened.ts"
# The self-test drives the SAME sandbox_domains_ok() the live check uses: a weakened predicate (a
# glob such as *github.com*, a prefix test, a count-only test) accepts at least one negative below.
# The positive fixture carries BOTH consts and the full fleet — generated so the sa0..99-minus-22
# bound is written once (expected_domains_sorted) and cannot drift from the live check's notion.
{
  printf 'export const ENTITLED_EGRESS_DOMAINS = Object.freeze([\n  "github.com",\n  "api.github.com",\n  "registry.npmjs.org",\n  ...GITHUB_ACTIONS_LOG_ACCOUNTS,\n] as const);\n'
  printf 'export const GITHUB_ACTIONS_LOG_ACCOUNTS = Object.freeze([\n'
  for i in $(seq 0 99); do
    [[ "$i" -eq 22 ]] || printf '  "productionresultssa%s.blob.core.windows.net",\n' "$i"
  done
  printf '] as const);\n'
} > "$CEN_D/cfg-exact.ts"
printf 'export const ENTITLED_EGRESS_DOMAINS = Object.freeze([\n  "github.com",\n  "api.github.com",\n] as const);\n' > "$CEN_D/cfg-pair.ts"
printf 'export const ENTITLED_EGRESS_DOMAINS = Object.freeze([\n  "github.com",\n] as const);\n' > "$CEN_D/cfg-one.ts"
printf 'export const ENTITLED_EGRESS_DOMAINS = Object.freeze([\n  "github.com",\n  "evilgithub.com",\n] as const);\n' > "$CEN_D/cfg-lookalike.ts"
CEN_SD_OK=1
sandbox_domains_ok "$(sandbox_domains "$CEN_D/cfg-exact.ts")" || CEN_SD_OK=0
sandbox_domains_ok "$(sandbox_domains "$CEN_D/cfg-pair.ts")" && CEN_SD_OK=0
sandbox_domains_ok "$(sandbox_domains "$CEN_D/cfg-widened.ts")" && CEN_SD_OK=0
sandbox_domains_ok "$(sandbox_domains "$CEN_D/cfg-one.ts")" && CEN_SD_OK=0
sandbox_domains_ok "$(sandbox_domains "$CEN_D/cfg-lookalike.ts")" && CEN_SD_OK=0
sandbox_domains_ok "" && CEN_SD_OK=0
if [[ "$CEN_SD_OK" -eq 1 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: census self-test: sandbox_domains_ok accepts the full {github, api.github, npm, sa0..99 minus sa22} set and rejects pair-only, widened, single, look-alike and empty lists"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: census self-test: sandbox_domains_ok misjudged a synthetic sandbox config (the live exact-set check is weaker than intended)"
fi
printf 'github.com\nghcr.io\n' > "$CEN_D/allow-bad.txt"
printf '# ghcr.io is HOST egress, deliberately absent\ngithub.com\n' > "$CEN_D/allow-ok.txt"
if [[ -n "$(allowlist_ghcr_hits "$CEN_D/allow-bad.txt")" && -z "$(allowlist_ghcr_hits "$CEN_D/allow-ok.txt")" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: census self-test: ghcr.io as an allowlist entry is flagged; a comment naming it is not"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: census self-test: allowlist scanner misjudged the synthetic allowlists"
fi
# Every alternation member is exercised by its OWN synthetic positive (each literal matches only
# its member), in lower and UPPER case: dropping a member or the case-insensitivity REDs here.
CEN_ALLOW_MISS=""
for lit in ghcr.io GHCR.IO maven.pkg.github.com MAVEN.PKG.GITHUB.COM raw.githubusercontent.com RAW.GITHUBUSERCONTENT.COM; do
  printf 'github.com\n%s\n' "$lit" > "$CEN_D/allow-one.txt"
  [[ "$(allowlist_ghcr_hits "$CEN_D/allow-one.txt")" == "$lit" ]] || CEN_ALLOW_MISS+="$lit "
done
mkdir -p "$CEN_D/members"
CEN_MEMBER_N=0; CEN_MEMBER_MISS=""
for lit in raw.githubusercontent.com codeload.example.invalid objects.github.example.invalid release-assets.example.invalid maven.pkg.github.com ghcr.io/v2 GHCR.IO/v2 Codeload.Example.Invalid; do
  CEN_MEMBER_N=$((CEN_MEMBER_N + 1))
  printf 'const u = "https://%s/";\n' "$lit" > "$CEN_D/members/m$CEN_MEMBER_N.ts"
done
printf 'const ok = "https://api.github.com/";\n' > "$CEN_D/members/clean.ts"
CEN_MEMBER_SCAN="$(server_census_scan "$CEN_D/members")"
for k in $(seq 1 "$CEN_MEMBER_N"); do grep -qxF "HIT $CEN_D/members/m$k.ts" <<<"$CEN_MEMBER_SCAN" || CEN_MEMBER_MISS+="m$k "; done
grep -qxF "HIT $CEN_D/members/clean.ts" <<<"$CEN_MEMBER_SCAN" && CEN_MEMBER_MISS+="clean-flagged "
grep -qx "SCANNED $((CEN_MEMBER_N + 1))" <<<"$CEN_MEMBER_SCAN" || CEN_MEMBER_MISS+="scanned-count "
if [[ -z "$CEN_ALLOW_MISS" && -z "$CEN_MEMBER_MISS" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: census self-test: every allowlist and server-scan alternation member (githubusercontent, codeload, objects.github, release-assets, pkg.github.com, ghcr.io) flags a synthetic positive, case-insensitively"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: census self-test: unflagged synthetic positives (allowlist: ${CEN_ALLOW_MISS:-none}; server scan: ${CEN_MEMBER_MISS:-none})"
fi
rm -rf "$CEN_D"

echo "-- fresh-host mirror via the baked host-scripts set (#5921) --"
# #5921: the cron-egress artifacts moved out of inline cloud-init write_files: (base64 blobs
# that blew the 32,768-byte user_data cap) into the baked /opt/soleur/host-scripts/ set. They
# are delivered on a fresh host by server.tf.local.host_script_files + the Dockerfile COPY +
# soleur-host-bootstrap.sh's install loop. The systemctl enable + package steps stay inline.
BOOTSTRAP="$SCRIPT_DIR/soleur-host-bootstrap.sh"
DOCKERFILE="$SCRIPT_DIR/../Dockerfile"
for f in cron-egress-nftables.sh cron-egress-resolve.sh cron-egress-alarm.sh \
  cron-egress-postapply-assert.sh cron-egress-allowlist.txt cron-egress-allowlist-cidr.txt \
  cron-egress-firewall.service cron-egress-resolve.service cron-egress-resolve.timer \
  cron-egress-alarm@.service; do
  # Scope the membership check to the host_script_files array (mirrors journald-config.test.sh)
  # so a `"$f"` appearing only in an SSH-provisioner reference cannot satisfy it.
  assert_cmd "baked set includes $f (host_script_files array)" \
    bash -c "awk '/host_script_files = \[/,/^  \]/' '$SERVER_TF' | grep -cF -- '\"$f\"' >/dev/null"
  assert_grep "Dockerfile bakes $f" "/app/infra/$f" "$DOCKERFILE"
done
assert_grep "bootstrap installs cron-egress scripts (0755)" 'cron-egress-nftables\.sh cron-egress-resolve\.sh cron-egress-alarm\.sh' "$BOOTSTRAP"
assert_grep "bootstrap installs cron-egress allowlists into /etc/soleur (0644)" 'install -D -m 0644 .* "/etc/soleur/\$f"' "$BOOTSTRAP"
assert_not_grep "cron-egress loader is NOT re-inlined in cloud-init write_files" '- path: /usr/local/bin/cron-egress-nftables\.sh' "$CLOUD_INIT"
assert_grep "cloud-init enables the firewall unit" 'systemctl enable --now cron-egress-firewall\.service' "$CLOUD_INIT"
assert_grep "cloud-init enables the resolve timer" 'systemctl enable --now cron-egress-resolve\.timer' "$CLOUD_INIT"
# #6090: package install moved from cloud-config packages: into an instrumented runcmd apt block
# (so a config-phase apt hang becomes a named fatal). nftables is still installed — now via apt-get.
assert_grep "cloud-init installs nftables (runcmd apt block, #6090)" 'apt-get install -y .*nftables' "$CLOUD_INIT"

echo "-- Phase 2.1: assertion-block self-reporting sentinels (#5279) --"
# The post-apply assertion block (server.tf, the 2nd remote-exec) runs under
# `set -e` with terraform's inline stdout SUPPRESSED — so a bare failing
# assertion exits 1 with NO indication of WHICH check failed (the root reason
# #5247 took 3 PRs to chase a one-line format mismatch nobody could see). Every
# assertion MUST self-report via a unique `ASSERT-FAILED: <name>` sentinel
# echoed BEFORE `exit 1`, so terraform's captured-on-error output names the
# culprit even with stdout suppressed (no SSH; hr-no-ssh-fallback-in-runbooks).
# Block = from the `chmod +x` line through `echo host-egress-ok`. The block now
# lives in its own delivered script (#5289 — folded into config_hash so edits
# re-provision); the awk markers are unchanged, only the source file moved from
# $SERVER_TF to the script.
ASSERT_BLOCK="$(awk '
  /chmod \+x \/usr\/local\/bin\/cron-egress-nftables\.sh/ { grab=1 }
  grab { print }
  /echo host-egress-ok/ { grab=0 }
' "$ASSERT_SCRIPT")"

SENTINEL_COUNT="$(echo "$ASSERT_BLOCK" | grep -cE 'ASSERT-FAILED:')"
# Floor ratcheted 15 -> 22 with the GHCR carve lines (#9275): 4 new sentinel-carrying lines (22 is the exact live count).
if [[ "$SENTINEL_COUNT" -ge 22 ]]; then
  PASS=$((PASS + 1)); echo "  PASS: assertion block carries $SENTINEL_COUNT ASSERT-FAILED sentinels (>=22)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: only $SENTINEL_COUNT ASSERT-FAILED sentinels in the assertion block (expected >=22 — every assertion must self-report)"
fi

# No bare command may remain: EVERY executable line in the block (chmod, every
# systemctl verb, nft-list, docker-network, leading-`curl`) must carry a
# sentinel guard. The command-detection regex covers the setup lines too
# (chmod / daemon-reload / enable / restart) — without that, those sentinels
# could be silently stripped while the floor's slack masked the count drop
# (PR #5280 review P2). The `echo host-egress-ok` success marker and the
# `if docker ps … fi` probe line (which carries its own two sentinels) are
# intentionally not command-shaped here. The leading-`curl` arm anchors on the
# bare script form (`^curl`, #5289 — no HCL quote now the block is a real .sh).
UNGUARDED="$(echo "$ASSERT_BLOCK" | grep -nE '(chmod \+x|systemctl (daemon-reload|enable|restart|is-active)|nft list|docker network inspect|^[[:space:]]*curl )' | grep -v 'ASSERT-FAILED' || true)"
if [[ -z "$UNGUARDED" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: no bare (sentinel-less) command remains in the block"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: unguarded command(s) without ASSERT-FAILED sentinel:"; echo "$UNGUARDED"
fi

# The service-RESTART sentinel (the LEAD failure 4c — `restart` re-runs the
# Type=oneshot loader and propagates its `die`) must ALSO surface the loader's
# journalctl tail, so the next apply names the loader `die` directly in the
# Actions log (no SSH). `enable` (symlink only) does not run the loader.
if echo "$ASSERT_BLOCK" | grep -cE 'ASSERT-FAILED: firewall-restart' >/dev/null \
  && echo "$ASSERT_BLOCK" | grep -c 'journalctl -u cron-egress-firewall.service' >/dev/null; then
  PASS=$((PASS + 1)); echo "  PASS: firewall-restart sentinel surfaces journalctl tail"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: firewall-restart sentinel must surface 'journalctl -u cron-egress-firewall.service'"
fi

# Protected-invariant sentinels (plan AC3/AC4 set) — each load-bearing
# containment check names itself distinctly so the failing one is unambiguous.
for sentinel in docker-user-jump default-drop bridge-ipv6 egress-probe-negative egress-probe-positive ghcr-carve-header-absent ghcr-carve-live-set ghcr-frontend-reachable; do
  if echo "$ASSERT_BLOCK" | grep -cE "ASSERT-FAILED: $sentinel" >/dev/null; then
    PASS=$((PASS + 1)); echo "  PASS: sentinel present for $sentinel"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: missing ASSERT-FAILED sentinel for $sentinel"
  fi
done

# Runbook parity (PR #5280 review P2): every sentinel NAME in the block must be
# documented in the cron-egress-blocked runbook, so a rename in server.tf that
# leaves the runbook stale fails the build instead of silently desyncing the
# operator's no-SSH diagnosis table. Names are extracted from the block; the
# trailing parenthetical detail (e.g. "firewall-restart (loader die …)") is
# stripped so only the bare name is matched.
RUNBOOK="$SCRIPT_DIR/../../../knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md"
SENTINEL_NAMES="$(echo "$ASSERT_BLOCK" | grep -oE "ASSERT-FAILED: [a-z0-9-]+" | sed -E 's/ASSERT-FAILED: //' | sort -u)"
if [[ -f "$RUNBOOK" ]]; then
  MISSING_RUNBOOK=""
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    grep -qF -- "$name" "$RUNBOOK" || MISSING_RUNBOOK+="$name "
  done <<< "$SENTINEL_NAMES"
  if [[ -z "$MISSING_RUNBOOK" ]]; then
    PASS=$((PASS + 1)); echo "  PASS: every sentinel name is documented in cron-egress-blocked.md"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: sentinel name(s) absent from cron-egress-blocked.md (runbook drift): $MISSING_RUNBOOK"
  fi
else
  FAIL=$((FAIL + 1)); echo "  FAIL: runbook not found at $RUNBOOK"
fi

# Behavioral non-vacuity: the sentinel pattern under `set -e` must emit the
# sentinel AND halt (not fall through). Proves the guard actually fires rather
# than being decorative.
SENTINEL_OUT="$(bash -c 'set -e; false || { echo "ASSERT-FAILED: probe"; exit 1; }; echo SHOULD-NOT-REACH' 2>&1 || true)"
if echo "$SENTINEL_OUT" | grep -cF 'ASSERT-FAILED: probe' >/dev/null && ! echo "$SENTINEL_OUT" | grep -cF 'SHOULD-NOT-REACH' >/dev/null; then
  PASS=$((PASS + 1)); echo "  PASS: sentinel pattern emits name and halts under set -e (non-vacuous)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: sentinel pattern did not emit+halt as expected (got: $SENTINEL_OUT)"
fi

# Static pin of the two properties no shimmed row can observe: the container's output is length-capped
# (a hostile curl could stream without bound into a root-owned substitution) and the producer's exit
# code is re-raised past `| head -c` (the pipeline status is head's, which would MASK curl's rc under
# set -e: the shape of the F4 hole). Whole-line comments are stripped first; the anchor is the probe's
# URL-through-substitution-end tail, not a bare `head -c`.
assert_grep "post-apply assert: probe output is capped (head -c N) and the producer's exit is re-raised via PIPESTATUS[0] (rc not masked by the pipe)" \
  'https://ghcr[.]io/ 2>/dev/null [|] head -c [0-9]+; exit "[$][{]PIPESTATUS\[0\][}]"[)]"' "$ASSERT_CODE"
# --- GHCR carve post-apply assertions: BEHAVIOUR (#9275 Phase 4) -----------------------------
# The static greps above only prove the sentinels EXIST. These rows EXECUTE the delivered script
# under `bash` with `nft`/`docker`/`systemctl`/`curl` shims first on PATH and a fixture CIDR file
# (the script honours CIDR_FILE, the same seam the loader has), so each assertion is proven to
# FIRE (fail-closed, right sentinel) and to PASS on a healthy host. The shimmed `nft get element`
# answers from a set file via python3 `ipaddress` (independent oracle), exactly like the real
# interval set: found when the address is inside any listed prefix, rc 1 otherwise (including a
# missing set). Real nft semantics were verified in a user namespace on nftables 1.1.7.
echo "-- resolver DNS tick budget behavioral (mass-flap boundedness) --"
# The 2026-10-08 incident this bounds: ~100 productionresultsa*
# CNAMEs flapping at Traffic Manager each burn the 10s per-host cap in a
# serial loop -> the tick exceeds TimeoutStartSec=120 and systemd SIGKILLs it
# BEFORE the nft -f apply (40+ min of zero completions on both web hosts).
# Here one fast host + fourteen 8s-slow hosts run under
# RESOLVE_TICK_BUDGET_SECS=20: without the gate this takes ~115s; with it the
# loop stops at ~25s and the starved names ride the additive-only path.
RB="$SUITE_SCRATCH/resolve-budget"
assert_fixture_dir "$RB"
mkdir -p "$RB/stubs" "$RB/fc" "$RB/seen" "$RB/etc"
printf '%s\n' fast.example slow01.example slow02.example slow03.example slow04.example \
  slow05.example slow06.example slow07.example slow08.example slow09.example \
  slow10.example slow11.example slow12.example slow13.example slow14.example > "$RB/etc/allowlist.txt"
: > "$RB/etc/cidrs.txt"
RB_CALLS="$RB/calls"; : > "$RB_CALLS"
rbmk() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$RB/stubs/$1"; chmod +x "$RB/stubs/$1"; }
rbmk getent 'case "$2" in *fast*) printf "93.184.216.34\n" ;; *) sleep 8 ;; esac'
rbmk docker 'exit 0'   # ps prints nothing -> container absent; probes self-skip
rbmk nft 'if [ "$1" = "-f" ]; then cat >/dev/null; exit 0; fi
printf "%s\n" "  jump SOLEUR-EGRESS" "  ct state established,related accept" \
  "  comment \"soleur-egress: default drop\"" "  comment \"soleur-egress: default drop log\""'
rbmk systemctl 'exit 0'
rbmk journalctl 'exit 0'
rbmk logger 'exit 0'
rbmk curl 'echo "curl $*" >> "$RB_CALLS"; exit 0'
rbmk doppler 'exit 1'
RB_T0="$(date +%s)"
RB_OUT="$(env PATH="$RB/stubs:$PATH" \
  ALLOWLIST_FILE="$RB/etc/allowlist.txt" CIDR_FILE="$RB/etc/cidrs.txt" \
  FAILCOUNT_DIR="$RB/fc" SEEN_DIR="$RB/seen" \
  CRON_EGRESS_LOCK_FILE="$RB/lock" LOADER=/bin/true \
  RESOLVE_TICK_BUDGET_SECS=20 \
  SENTRY_INGEST_DOMAIN=o0.ingest.us.sentry.io SENTRY_PROJECT_ID=42 \
  SENTRY_PUBLIC_KEY=0123456789abcdef0123456789abcdef \
  RB_CALLS="$RB_CALLS" \
  timeout 120 bash "$RESOLVER" 2>&1)"; RB_RC=$?
RB_ELAPSED=$(( $(date +%s) - RB_T0 ))
if [[ "$RB_RC" -eq 0 ]]; then PASS=$((PASS + 1)); echo "  PASS: flap tick completes (rc 0)"; else FAIL=$((FAIL + 1)); echo "  FAIL: flap tick rc=$RB_RC"; fi
if [[ "$RB_ELAPSED" -lt 60 ]]; then PASS=$((PASS + 1)); echo "  PASS: tick bounded (${RB_ELAPSED}s < 60s; unbounded loop would be ~115s)"; else FAIL=$((FAIL + 1)); echo "  FAIL: tick ran ${RB_ELAPSED}s — budget gate ineffective"; fi
if grep -qF "DNS tick budget" <<<"$RB_OUT"; then PASS=$((PASS + 1)); echo "  PASS: budget-exhaustion WARN emitted"; else FAIL=$((FAIL + 1)); echo "  FAIL: no budget WARN in output"; fi
if grep -qF "ADDITIVE-ONLY" <<<"$RB_OUT"; then PASS=$((PASS + 1)); echo "  PASS: starved hosts ride additive-only"; else FAIL=$((FAIL + 1)); echo "  FAIL: no additive-only line in output"; fi
if [[ -e "$RB/fc/.budget-skip" ]]; then PASS=$((PASS + 1)); echo "  PASS: dedupe marker written after the event POSTed"; else FAIL=$((FAIL + 1)); echo "  FAIL: .budget-skip marker absent (event not sent or marker ordering broken)"; fi
if [[ "$(grep -c '^curl' "$RB_CALLS")" =~ ^[1-9][0-9]*$ ]]; then PASS=$((PASS + 1)); echo "  PASS: starved-tick Sentry event POSTed via curl"; else FAIL=$((FAIL + 1)); echo "  FAIL: no curl POST recorded"; fi
if [[ ! -e "$RB/fc/slow14.example" ]]; then PASS=$((PASS + 1)); echo "  PASS: a starved host carries no try-and-fail counter"; else FAIL=$((FAIL + 1)); echo "  FAIL: slow14.example failcount file exists — skipped hosts must not escalate"; fi
if [[ "$(cat "$RB/fc/slow01.example" 2>/dev/null)" == "1" ]]; then PASS=$((PASS + 1)); echo "  PASS: an attempted-and-failed host carries failcount=1"; else FAIL=$((FAIL + 1)); echo "  FAIL: slow01.example failcount missing/wrong (got: $(cat "$RB/fc/slow01.example" 2>/dev/null || echo absent))"; fi

GA_ROOT="$(mktemp -d)"
assert_fixture_dir "$GA_ROOT"
ga_setup() {   # ga_setup <name> -> prints the scenario dir; creates shims
  local d="$GA_ROOT/$1"
  mkdir -p "$d/bin"
  cat > "$d/bin/nft" << 'MOCK'
#!/bin/bash
case "$*" in
  "list chain ip filter DOCKER-USER") if [[ -n "${GA_JUMPOLD:-}" ]]; then echo "jump SOLEUR-EGRESS-OLD"; else echo "jump SOLEUR-EGRESS"; fi; exit 0 ;;
  "list chain ip filter SOLEUR-EGRESS")
    # GA_NODROP: the default-drop LOG rule survives but the terminal drop is gone. The log rule carries the
    # `egress-blocked` prefix (which the old sentinel mistook for the drop) AND its own comment
    # `... default drop log`, which a sentinel that loses its closing quote would mistake for the drop.
    if [[ -n "${GA_NODROP:-}" ]]; then
      echo 'log prefix "egress-blocked: " comment "soleur-egress: default drop log" ; egress-dns-exfil ; tcp dport 8288 accept ; ip daddr 10.0.1.40 tcp dport 8288 accept ; cidr allowlist'; exit 0
    fi
    echo 'log prefix "egress-blocked: " ; counter drop comment "soleur-egress: default drop" ; egress-dns-exfil ; tcp dport 8288 accept ; ip daddr 10.0.1.40 tcp dport 8288 accept ; cidr allowlist'; exit 0 ;;
  "list set ip filter soleur_egress_allow") echo "elements = { 104.18.24.159 }"; exit 0 ;;
  "list set ip filter soleur_egress_allow_cidr") echo "elements = { 140.82.112.0/22, 20.1.2.3, 4.5.6.7 }"; exit 0 ;;
esac
if [[ "$1 $2" == "get element" ]]; then
  # nft get element ip filter soleur_egress_allow_cidr { <ip> }
  ip="$(echo "$*" | sed -E 's/.*\{ *([0-9.]+) *\}.*/\1/')"
  [[ "$ip" =~ ^[0-9]+([.][0-9]+){3}$ ]] || exit 1
  [[ -s "${GA_SET_FILE:-/nonexistent}" ]] || exit 1   # missing/empty set: nft errors
  echo "$ip" >> "$GA_DIR/get_element_calls"
  python3 - "$GA_SET_FILE" "$ip" << 'PY'
import ipaddress, sys
a = ipaddress.ip_address(sys.argv[2])
sys.exit(0 if any(a in ipaddress.ip_network(l.strip(), strict=False) for l in open(sys.argv[1]) if l.strip()) else 1)
PY
  exit $?
fi
echo "nft shim: unhandled: $*" >&2; exit 99
MOCK
  cat > "$d/bin/docker" << 'MOCK'
#!/bin/bash
case "$1" in
  ps) [[ "${GA_CONTAINER:-1}" == "1" ]] && echo soleur-web-platform; exit 0 ;;
  network) echo false; exit 0 ;;
  exec)
    echo "$*" >> "$GA_DIR/docker_exec_calls"
    if [[ "$*" == *"--resolve ghcr.io:443:"* ]]; then
      # `docker exec` itself failing (125 daemon error / 127 no such command): curl never ran, no output.
      [[ -n "${GA_DOCKER_RC:-}" ]] && exit "$GA_DOCKER_RC"
      # GA_GHCR_OUT (set, even empty) overrides verbatim: hostile / empty / oversized output rows.
      if [[ -n "${GA_GHCR_OUT+x}" ]]; then printf '%s' "$GA_GHCR_OUT"; exit "${GA_GHCR_RC:-28}"; fi
      # Otherwise render the `-w` format string this call ACTUALLY received, field by field, so a swapped
      # or renamed field in the script changes what the script's parser sees (it is bound to its parser,
      # not to a canned string). Unmapped tokens render as UNMAPPED and fail the shape check.
      fmt=""; prev=""
      for a in "$@"; do [[ "$prev" == "-w" ]] && fmt="$a"; prev="$a"; done
      out="$fmt"
      for tok in time_connect time_namelookup remote_ip; do
        case "$tok" in
          time_connect) val="${GA_TC:-0.000000}" ;;
          time_namelookup) val="${GA_NL:-0.000000}" ;;
          remote_ip) val="${GA_RIP:-}" ;;
        esac
        pat="%{$tok}"; out="${out//"$pat"/$val}"
      done
      [[ "$out" == *"%{"* ]] && out="UNMAPPED"
      printf '%s' "$out"; exit "${GA_GHCR_RC:-28}"
    fi
    [[ "$*" == *example.com* ]] && exit 28
    exit 0 ;;
esac
exit 0
MOCK
  # `timeout` shim: records its own argv (the 15 s wrapper contract), can simulate the wrapper firing
  # (GA_TIMEOUT_RC: 124 timed out / 137 killed), otherwise drops `-k N DURATION` and runs the command.
  cat > "$d/bin/timeout" << 'MOCK'
#!/bin/bash
echo "$*" >> "$GA_DIR/timeout_calls"
[[ -n "${GA_TIMEOUT_RC:-}" ]] && exit "$GA_TIMEOUT_RC"
[[ "$1" == "-k" ]] && shift 2
shift
exec "$@"
MOCK
  for c in chmod systemctl journalctl; do printf '#!/bin/bash\nexit 0\n' > "$d/bin/$c"; done
  printf '#!/bin/bash\nexit 0\n' > "$d/bin/curl"   # host-egress spot check
  chmod +x "$d/bin/"*
  echo "$d"
}
# ga_run <dir> <cidr-file> <set-file>  [extra env as KEY=VAL...] -> combined output, rc in GA_RC
ga_run() {
  local d="$1" cf="$2" sf="$3"; shift 3
  GA_OUT="$( cd "$d" && env PATH="$d/bin:$PATH" GA_DIR="$d" CIDR_FILE="$cf" GA_SET_FILE="$sf" "$@" bash "$ASSERT_SCRIPT" 2>&1 )" && GA_RC=0 || GA_RC=$?
}
ga_row() {   # ga_row "<description>" <ok-flag>
  if [[ "$2" -eq 1 ]]; then PASS=$((PASS + 1)); echo "  PASS: $1"
  else FAIL=$((FAIL + 1)); echo "  FAIL: $1"; echo "        rc=$GA_RC out(tail): $(echo "$GA_OUT" | tail -4 | tr '\n' '|')"; fi
}
# Negative control for ga_row (the verdict-owning helper of this section): a mismatching expectation
# MUST move FAIL (and print a FAIL line), a matching one MUST move PASS. The counters and the
# transcript are unwound, and a broken helper is reported directly (printf + exit), never through the
# accounting it would be lying to.
ga_control() {
  assert_fixture_dir "$SUITE_SCRATCH"
  local p0=$PASS f0=$FAIL tr="$SUITE_SCRATCH/ga_control.out" bad=""
  GA_RC=99; GA_OUT="control"
  ga_row "control-mismatch" 0 > "$tr" 2>&1
  [[ "$FAIL" -eq $((f0 + 1)) && "$PASS" -eq "$p0" ]] || bad+="mismatch-did-not-move-FAIL "
  grep -q '^  FAIL: control-mismatch' "$tr" || bad+="no-FAIL-line "
  PASS=$p0; FAIL=$f0
  ga_row "control-match" 1 > "$tr" 2>&1
  [[ "$PASS" -eq $((p0 + 1)) && "$FAIL" -eq "$f0" ]] || bad+="match-did-not-move-PASS "
  grep -q '^  PASS: control-match' "$tr" || bad+="no-PASS-line "
  PASS=$p0; FAIL=$f0
  rm -f "$tr"
  if [[ -n "$bad" ]]; then
    printf '\n[FATAL] ga_row negative control failed (%s): the section verdict helper cannot be trusted\n' "$bad" >&2
    exit 1
  fi
}
ga_control
GA_V0=$((PASS + FAIL))
ga_fx() {   # ga_fx <name> -> GA_D = a fresh scenario dir holding the healthy fixture (cidr.txt + set.txt)
  GA_D="$(ga_setup "$1")"; assert_fixture_dir "$GA_D"; ga_cidr_ok > "$GA_D/cidr.txt"; ga_set_of "$GA_D/cidr.txt" > "$GA_D/set.txt"
}
ga_calls_n() { { grep -c '' "$GA_D/get_element_calls" 2>/dev/null || true; } | head -n1; }   # recorded `nft get element` calls (incl. the 1 positive control)
ga_inconclusive_ok() {   # ga_inconclusive_ok <rc ERE> -> 0 iff exit 0, loud inconclusive WARNING naming rc, NO held-ok, NO fatal sentinel
  [[ "$GA_RC" -eq 0 ]] \
    && grep -qE "WARNING: ghcr-frontend-inconclusive [(]rc=($1)[)]" <<<"$GA_OUT" \
    && ! grep -qx 'ghcr-frontend-held-ok' <<<"$GA_OUT" \
    && ! grep -q 'ASSERT-FAILED: ghcr-frontend-reachable' <<<"$GA_OUT" \
    && grep -qx 'host-egress-ok' <<<"$GA_OUT"
}
# Fixture CIDR file: a /31 and a /32 carved out of the 140.82.121.0 neighbourhood (synthetic, RFC
# values chosen only for shape) plus the remainder prefixes; the set file is the file's allow
# prefixes (what the loader would have installed).
ga_cidr_ok() {
  cat << 'F'
# Container egress CIDR allowlist (synthetic fixture)
# DO NOT EDIT — regenerate via apps/web-platform/infra/scripts/gen-github-egress-cidr.sh
# Excluded (GitHub Packages frontends): 140.82.121.32/31
# Excluded (GitHub Packages frontends): 192.30.255.164/32
140.82.121.0/27
140.82.121.34/31
140.82.121.36/30
192.30.255.0/25
20.1.2.3/32
4.5.6.7/32
F
}
ga_set_of() { grep -vE '^[[:space:]]*(#|$)' "$1"; }

# Row A: healthy host (carve landed, container running, probe held) -> passes end to end and the
# live probe is PINNED to the FIRST excluded address (--resolve ghcr.io:443:<first ip>).
GA_D="$(ga_setup healthy)"; assert_fixture_dir "$GA_D"; ga_cidr_ok > "$GA_D/cidr.txt"; ga_set_of "$GA_D/cidr.txt" > "$GA_D/set.txt"
ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt"
GA_OK=1
[[ "$GA_RC" -eq 0 ]] || GA_OK=0
grep -qx 'host-egress-ok' <<<"$GA_OUT" || GA_OK=0
grep -qx 'ghcr-frontend-held-ok' <<<"$GA_OUT" || GA_OK=0
grep -q -- '--resolve ghcr.io:443:140.82.121.32 ' "$GA_D/docker_exec_calls" 2>/dev/null || GA_OK=0
ga_row "post-apply assert: healthy carve -> exit 0, host-egress-ok, live probe pinned to the first excluded address" "$GA_OK"
# Curl contract (B4): the WHOLE argv the container sees, anchored as one exact line (-q first, --noproxy,
# both timeouts, the --resolve pin, the single-field -w format, the URL) and the 15 s `timeout -k 2`
# wrapper that bounds the docker exec client. Swapping a field, dropping -q/--noproxy or loosening a
# timeout REDs here; the field-vs-parser binding is exercised by the rows that render the received -w format.
GA_OK=1
grep -qFx -e 'exec soleur-web-platform curl -q -s -o /dev/null --noproxy * --connect-timeout 5 --max-time 8 --resolve ghcr.io:443:140.82.121.32 -w %{time_connect} https://ghcr.io/' "$GA_D/docker_exec_calls" 2>/dev/null || GA_OK=0
[[ "$(grep -c 'ghcr.io:443' "$GA_D/docker_exec_calls" 2>/dev/null || true)" -eq 1 ]] || GA_OK=0
grep -qFx -e '-k 2 15 docker exec soleur-web-platform curl -q -s -o /dev/null --noproxy * --connect-timeout 5 --max-time 8 --resolve ghcr.io:443:140.82.121.32 -w %{time_connect} https://ghcr.io/' "$GA_D/timeout_calls" 2>/dev/null || GA_OK=0
ga_row "post-apply assert: the live probe argv is pinned whole (-q, --noproxy, --connect-timeout 5, --max-time 8, --resolve, -w %{time_connect}) under timeout -k 2 15" "$GA_OK"
# Non-vacuity of row A: every address of BOTH excluded prefixes (a /31 yields two) was asked of nft.
GA_OK=1
for ip in 140.82.121.32 140.82.121.33 192.30.255.164; do grep -qx "$ip" "$GA_D/get_element_calls" 2>/dev/null || GA_OK=0; done
ga_row "post-apply assert: nft get element is asked for EVERY address of every excluded prefix (both of a /31)" "$GA_OK"

# Row B: header absent (the carve never reached the installed file) -> header-absent sentinel, non-zero.
GA_D="$(ga_setup noheader)"; assert_fixture_dir "$GA_D"; ga_cidr_ok | grep -v '^# Excluded' > "$GA_D/cidr.txt"; ga_set_of "$GA_D/cidr.txt" > "$GA_D/set.txt"
ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt"
GA_OK=1
[[ "$GA_RC" -ne 0 ]] || GA_OK=0
grep -q 'ASSERT-FAILED: ghcr-carve-header-absent' <<<"$GA_OUT" || GA_OK=0
ga_row "post-apply assert: no Excluded header -> ASSERT-FAILED: ghcr-carve-header-absent, non-zero exit" "$GA_OK"

# Row B2: the default-drop LOG rule survives but the terminal drop is gone -> default-drop sentinel (the log rule's
# `egress-blocked` prefix alone must not satisfy it).
GA_D="$(ga_setup nodrop)"; assert_fixture_dir "$GA_D"; ga_cidr_ok > "$GA_D/cidr.txt"; ga_set_of "$GA_D/cidr.txt" > "$GA_D/set.txt"
ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt" GA_NODROP=1
GA_OK=1
[[ "$GA_RC" -ne 0 ]] || GA_OK=0
grep -q 'ASSERT-FAILED: default-drop' <<<"$GA_OUT" || GA_OK=0
ga_row "post-apply assert: log rule present but terminal drop gone -> ASSERT-FAILED: default-drop, non-zero exit" "$GA_OK"

# Row B3: a jump to a similarly named chain is not our jump -> docker-user-jump sentinel (the target token is matched, not a prefix).
GA_D="$(ga_setup jumpold)"; assert_fixture_dir "$GA_D"; ga_cidr_ok > "$GA_D/cidr.txt"; ga_set_of "$GA_D/cidr.txt" > "$GA_D/set.txt"
ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt" GA_JUMPOLD=1
GA_OK=1
[[ "$GA_RC" -ne 0 ]] || GA_OK=0
grep -q 'ASSERT-FAILED: docker-user-jump' <<<"$GA_OUT" || GA_OK=0
ga_row "post-apply assert: a jump to SOLEUR-EGRESS-OLD is not our jump -> ASSERT-FAILED: docker-user-jump, non-zero exit" "$GA_OK"

# Row C: an excluded address is present in the LIVE set (stale set / loader not reloaded) ->
# live-set sentinel naming the address. The SECOND address of the /31 (.33) is the one leaked, so
# a loop that only checks each prefix's first address passes this fixture and REDs here.
GA_D="$(ga_setup leak)"; assert_fixture_dir "$GA_D"; ga_cidr_ok > "$GA_D/cidr.txt"; { ga_set_of "$GA_D/cidr.txt"; echo "140.82.121.33/32"; } > "$GA_D/set.txt"
ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt"
GA_OK=1
[[ "$GA_RC" -ne 0 ]] || GA_OK=0
grep -q 'ASSERT-FAILED: ghcr-carve-live-set 140.82.121.33 ' <<<"$GA_OUT" || GA_OK=0
ga_row "post-apply assert: second address of an excluded /31 present in the live set -> ASSERT-FAILED: ghcr-carve-live-set 140.82.121.33" "$GA_OK"
# Row C2: the LAST excluded prefix leaks (a loop that stops after the first prefix passes this).
GA_D="$(ga_setup leaklast)"; assert_fixture_dir "$GA_D"; ga_cidr_ok > "$GA_D/cidr.txt"; { ga_set_of "$GA_D/cidr.txt"; echo "192.30.255.164/32"; } > "$GA_D/set.txt"
ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt"
GA_OK=1
[[ "$GA_RC" -ne 0 ]] || GA_OK=0
grep -q 'ASSERT-FAILED: ghcr-carve-live-set 192.30.255.164 ' <<<"$GA_OUT" || GA_OK=0
ga_row "post-apply assert: the LAST excluded prefix leaking is also caught (every prefix is walked)" "$GA_OK"

# Row D: POSITIVE CONTROL. The set is missing/empty (nft errors on every get element): without the
# control, "absent" would be read from the error and the assertion would pass on a dead set.
GA_D="$(ga_setup deadset)"; assert_fixture_dir "$GA_D"; ga_cidr_ok > "$GA_D/cidr.txt"; : > "$GA_D/set.txt"
ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt"
GA_OK=1
[[ "$GA_RC" -ne 0 ]] || GA_OK=0
grep -q 'ASSERT-FAILED: ghcr-carve-live-set (positive control' <<<"$GA_OUT" || GA_OK=0
ga_row "post-apply assert: missing/empty set -> positive control fails (ghcr-carve-live-set), not a vacuous pass" "$GA_OK"

# Row E: the live end-to-end probe CONNECTS (time_connect > 0) -> ghcr-frontend-reachable.
ga_fx reachable
ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt" GA_GHCR_OUT=0.021 GA_GHCR_RC=0
GA_OK=1
[[ "$GA_RC" -ne 0 ]] || GA_OK=0
grep -q 'ASSERT-FAILED: ghcr-frontend-reachable 140.82.121.32 ' <<<"$GA_OUT" || GA_OK=0
ga_row "post-apply assert: probe completes a handshake (time_connect 0.021) -> ASSERT-FAILED: ghcr-frontend-reachable 140.82.121.32" "$GA_OK"
# Row E2/E3 bind the verdict to the FIELD the script asks curl for: the shim renders the -w format it
# receives. A handshake that completed before a later phase timed out (rc 28, time_connect 0.021) is a
# connect; a drop after a slow name lookup (rc 28, time_connect 0, time_namelookup 0.9) is held. A script
# that swapped %{time_connect} for %{time_namelookup} inverts both and REDs on both.
ga_fx e2
ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt" GA_TC=0.021 GA_NL=0 GA_GHCR_RC=28
GA_OK=1
[[ "$GA_RC" -ne 0 ]] || GA_OK=0
grep -q 'ASSERT-FAILED: ghcr-frontend-reachable 140.82.121.32 ' <<<"$GA_OUT" || GA_OK=0
! grep -qx 'ghcr-frontend-held-ok' <<<"$GA_OUT" || GA_OK=0
ga_row "post-apply assert: rc 28 with time_connect 0.021 (handshake done, later phase timed out) is a connect, not a drop (field-bound)" "$GA_OK"
ga_fx e3
ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt" GA_TC=0 GA_NL=0.9 GA_GHCR_RC=28
GA_OK=1
[[ "$GA_RC" -eq 0 ]] || GA_OK=0
grep -qx 'ghcr-frontend-held-ok' <<<"$GA_OUT" || GA_OK=0
! grep -q 'ASSERT-FAILED' <<<"$GA_OUT" || GA_OK=0
ga_row "post-apply assert: rc 28 + time_connect 0 (time_namelookup 0.9) -> held, ghcr-frontend-held-ok (field-bound, the other direction)" "$GA_OK"
ga_fx e4
ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt" GA_GHCR_OUT= GA_GHCR_RC=0
GA_OK=1
[[ "$GA_RC" -ne 0 ]] || GA_OK=0
grep -q 'ASSERT-FAILED: ghcr-frontend-reachable 140.82.121.32 ' <<<"$GA_OUT" || GA_OK=0
ga_row "post-apply assert: curl exit 0 (a full response from an excluded frontend) is fatal even with empty output" "$GA_OK"

# Row F: hostile / unprovable probe output. A binary inside a possibly compromised container writes it;
# the script is root on the host. Command substitution and an unbounded line must neither execute nor
# read as held: INCONCLUSIVE (loud WARNING, no held-ok), the apply continues (the nft get element checks
# are the authoritative proof). rc 28 is used so only the OUTPUT decides.
ga_fx hostile
ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt" 'GA_GHCR_OUT=a[$(touch PWNED)]' GA_GHCR_RC=28
GA_OK=1
ga_inconclusive_ok 28 || GA_OK=0
[[ ! -e "$GA_D/PWNED" ]] || GA_OK=0
ga_row "post-apply assert: hostile probe output (command substitution in time_connect) is inert and reads INCONCLUSIVE, never held-ok" "$GA_OK"
GA_BIG="$(head -c 10240 /dev/zero | tr '\0' '9')"
ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt" "GA_GHCR_OUT=$GA_BIG" GA_GHCR_RC=28
GA_OK=1
ga_inconclusive_ok '28|141' || GA_OK=0   # 141 = the producer took SIGPIPE when `head -c` closed the pipe early (a race with the write)
ga_row "post-apply assert: a 10 kB all-digit probe line is length-capped, fails the shape check and reads INCONCLUSIVE" "$GA_OK"
ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt" GA_GHCR_OUT= GA_GHCR_RC=28
GA_OK=1
ga_inconclusive_ok 28 || GA_OK=0
ga_row "post-apply assert: rc 28 with EMPTY output (no time_connect to read) is INCONCLUSIVE, not held" "$GA_OK"
ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt" GA_GHCR_RC=7 GA_TC=0
GA_OK=1
ga_inconclusive_ok 7 || GA_OK=0
ga_row "post-apply assert: a non-timeout curl failure (rc 7) with time_connect 0 is INCONCLUSIVE, not held" "$GA_OK"
# F2/F3: `docker exec` itself fails (125 daemon error, 127 command not found): curl never ran.
ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt" GA_DOCKER_RC=125
GA_OK=1
ga_inconclusive_ok 125 || GA_OK=0
ga_row "post-apply assert: docker exec failing with rc 125 is INCONCLUSIVE (a failing probe is not a held probe)" "$GA_OK"
ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt" GA_DOCKER_RC=127
GA_OK=1
ga_inconclusive_ok 127 || GA_OK=0
ga_row "post-apply assert: docker exec failing with rc 127 (curl missing in the container) is INCONCLUSIVE" "$GA_OK"
# F4: the 15 s wrapper fires (a hung docker exec): rc 124.
ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt" GA_TIMEOUT_RC=124
GA_OK=1
ga_inconclusive_ok 124 || GA_OK=0
ga_row "post-apply assert: the timeout wrapper firing (rc 124) is INCONCLUSIVE" "$GA_OK"
# F5 (coupling note): the probe output is capped by `| head -c`, which MASKS the producer's exit code
# under set -e (the pipeline status is head's). The script re-raises it with PIPESTATUS[0]; if it did not,
# rc 28 / 125 / 127 above would all read rc 0 (fatal reachable) and these rows would RED.

# Row G: container absent (fresh host) -> the live probe is SKIPPED LOUDLY, but the nft get element
# checks still run: a leaked address still fails the apply on a host with no container.
GA_D="$(ga_setup fresh)"; assert_fixture_dir "$GA_D"; ga_cidr_ok > "$GA_D/cidr.txt"; ga_set_of "$GA_D/cidr.txt" > "$GA_D/set.txt"
ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt" GA_CONTAINER=0
GA_OK=1
[[ "$GA_RC" -eq 0 ]] || GA_OK=0
grep -q 'WARNING: .*ghcr-frontend-reachable probe SKIPPED' <<<"$GA_OUT" || GA_OK=0
[[ ! -e "$GA_D/docker_exec_calls" ]] || GA_OK=0
ga_row "post-apply assert: container absent -> live probe skipped with a LOUD warning, exit 0" "$GA_OK"
GA_D="$(ga_setup freshleak)"; assert_fixture_dir "$GA_D"; ga_cidr_ok > "$GA_D/cidr.txt"; { ga_set_of "$GA_D/cidr.txt"; echo "140.82.121.32/32"; } > "$GA_D/set.txt"
ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt" GA_CONTAINER=0
GA_OK=1
[[ "$GA_RC" -ne 0 ]] || GA_OK=0
grep -q 'ASSERT-FAILED: ghcr-carve-live-set 140.82.121.32 ' <<<"$GA_OUT" || GA_OK=0
ga_row "post-apply assert: container absent but an excluded address leaked -> the nft checks still fail the apply" "$GA_OK"

# Row H: a malformed, over-broad or MISALIGNED Excluded prefix must not drive a nft loop (a /16 would be
# 65k calls; the generator caps holes at /28) nor be trusted: header-absent sentinel, quickly. The bad
# header is placed FIRST, so "rejected before any nft loop" is provable: only the 1 positive-control
# get element call may have happened. The validation mirrors the generator and the resolver sampler:
# octets 0-255 without leading zeros, /28../32, address aligned to its prefix.
ga_bad_header_row() {   # ga_bad_header_row <name> <bad-header-cidr> -> GA_OK (1 iff rejected up front under the header sentinel)
  GA_D="$(ga_setup "$1")"; assert_fixture_dir "$GA_D"
  { echo "# Excluded (GitHub Packages frontends): $2"; ga_cidr_ok; } > "$GA_D/cidr.txt"; ga_set_of "$GA_D/cidr.txt" > "$GA_D/set.txt"
  ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt"
  GA_OK=1
  [[ "$GA_RC" -ne 0 ]] || GA_OK=0
  grep -qF "ASSERT-FAILED: ghcr-carve-header-absent (malformed or over-broad Excluded prefix: $2)" <<<"$GA_OUT" || GA_OK=0
  [[ "$(ga_calls_n)" -eq 1 ]] || GA_OK=0
  ! grep -qx 'ghcr-frontend-held-ok' <<<"$GA_OUT" || GA_OK=0
}
ga_bad_header_row broad 10.0.0.0/24
ga_row "post-apply assert: an over-broad Excluded prefix (/24, 256 addresses) is rejected before any nft loop" "$GA_OK"
ga_bad_header_row oct300 140.82.121.300/32
ga_row "post-apply assert: an octet above 255 (140.82.121.300/32) is rejected before any nft loop" "$GA_OK"
ga_bad_header_row leadzero 140.082.121.32/32
ga_row "post-apply assert: a leading-zero octet (140.082.121.32/32, octal-ambiguous) is rejected before any nft loop" "$GA_OK"
ga_bad_header_row misaligned31 192.30.255.165/31
ga_row "post-apply assert: a misaligned /31 (192.30.255.165/31, not a network address) is rejected before any nft loop" "$GA_OK"
ga_bad_header_row misaligned28 203.0.113.24/28
ga_row "post-apply assert: a misaligned /28 (203.0.113.24/28) is rejected before any nft loop" "$GA_OK"
ga_bad_header_row pfx33 140.82.121.32/33
ga_row "post-apply assert: a /33 prefix is rejected before any nft loop" "$GA_OK"
ga_bad_header_row pfx0 0.0.0.0/0
ga_row "post-apply assert: 0.0.0.0/0 (every address) is rejected before any nft loop" "$GA_OK"

# Row K: loop CARDINALITY across prefix sizes (rows A-C only exercise /31 and /32). A /29 (8 addresses)
# and a /28 (16) hole, synthetic TEST-NET addresses. Every address is asked of nft exactly once: the
# recorded `get element` calls equal 1 (positive control) + sum(2^(32-p)) over the headers, with the
# sum recomputed by the python3 `ipaddress` oracle, not by the loop under test. A leak at a MIDDLE
# address must be named and must stop the walk right there (calls = control + addresses up to the leak).
ga_cidr_card() {
  cat << 'F'
# Container egress CIDR allowlist (synthetic cardinality fixture)
# Excluded (GitHub Packages frontends): 198.51.100.8/29
# Excluded (GitHub Packages frontends): 203.0.113.16/28
140.82.121.0/27
F
}
GA_CARD_SUM="$(ga_cidr_card | python3 -c '
import ipaddress, re, sys
print(sum(ipaddress.ip_network(m.group(1)).num_addresses for m in (re.match(r"^# Excluded \(GitHub Packages frontends\): (\S+)$", l.strip()) for l in sys.stdin) if m))
')"
ga_card_setup() {   # ga_card_setup <name> [leaked-ip] -> GA_D with the cardinality fixture; the leaked ip (if any) is added to the live set
  GA_D="$(ga_setup "$1")"; assert_fixture_dir "$GA_D"; ga_cidr_card > "$GA_D/cidr.txt"
  { ga_set_of "$GA_D/cidr.txt"; [[ -n "${2:-}" ]] && echo "$2/32"; true; } > "$GA_D/set.txt"
  ga_run "$GA_D" "$GA_D/cidr.txt" "$GA_D/set.txt"
}
ga_card_setup cardok
GA_OK=1
[[ "$GA_RC" -eq 0 ]] || GA_OK=0
[[ "$GA_CARD_SUM" -eq 24 ]] || GA_OK=0
[[ "$(ga_calls_n)" -eq $((GA_CARD_SUM + 1)) ]] || GA_OK=0
for ip in 198.51.100.8 198.51.100.11 198.51.100.15 203.0.113.16 203.0.113.23 203.0.113.31; do grep -qx "$ip" "$GA_D/get_element_calls" 2>/dev/null || GA_OK=0; done
ga_row "post-apply assert: a /29 and a /28 hole -> nft is asked for exactly 2^(32-p) addresses each (24 + 1 control calls), first/middle/last included" "$GA_OK"
ga_card_setup cardleak29 198.51.100.12
GA_OK=1
[[ "$GA_RC" -ne 0 ]] || GA_OK=0
grep -q 'ASSERT-FAILED: ghcr-carve-live-set 198.51.100.12 ' <<<"$GA_OUT" || GA_OK=0
[[ "$(ga_calls_n)" -eq 6 ]] || GA_OK=0   # control + .8 .9 .10 .11 .12 then the walk stops
ga_row "post-apply assert: a leak at a MIDDLE address of an excluded /29 (.12) is named and stops the walk there" "$GA_OK"
ga_card_setup cardleak28 203.0.113.23
GA_OK=1
[[ "$GA_RC" -ne 0 ]] || GA_OK=0
grep -q 'ASSERT-FAILED: ghcr-carve-live-set 203.0.113.23 ' <<<"$GA_OUT" || GA_OK=0
[[ "$(ga_calls_n)" -eq 17 ]] || GA_OK=0   # control + all 8 of the /29 + .16 .. .23 of the /28
ga_row "post-apply assert: a leak at a MIDDLE address of an excluded /28 (.23, after a fully walked /29) is named" "$GA_OK"

# CASES identity (call-site count): every `ga_row "` call site in this file at column 0 is one case, and
# each must have recorded exactly one verdict since GA_V0. A helper that swallows a verdict, a row that
# does not run, or a call site added in a form the counter does not see all break it. The negative control
# (ga_control) call is indented inside its function and is deliberately not counted. Reported directly.
GA_CASES="$(grep -cE '^ga_row "' "${BASH_SOURCE[0]}" || true)"
if [[ "$((PASS + FAIL - GA_V0))" -ne "$GA_CASES" ]]; then
  printf '\n[FATAL] ga_row accounting: %d verdict(s) recorded for %d call site(s) (PASS+FAIL must equal CASES)\n' "$((PASS + FAIL - GA_V0))" "$GA_CASES" >&2
  exit 1
fi
rm -rf "$GA_ROOT"

echo ""
echo "RESULT: $PASS passed, $FAIL failed"
# Anti-vacuity floor (ADR-193, #7898): CI reads only the exit status, so a
# deleted row would vanish green. Reported directly, never through the
# PASS/FAIL accounting this backstops. Ratchet when adding rows.
if [[ $((PASS + FAIL)) -lt 352 ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d verdict(s) recorded, expected >= 352. A row was deleted.\n' "$((PASS + FAIL))" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
