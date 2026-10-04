#!/usr/bin/env bash
# Post-apply assertion block for terraform_data.cron_egress_firewall (#5046 PR-2,
# extracted to a delivered script in #5289). Run by the resource's final
# `remote-exec` after the firewall artifacts are provisioned. Folded into the
# resource's `config_hash` (server.tf) so an edit HERE re-provisions the resource
# — inline-block edits used to be silent no-ops (the hash folded only the 9
# delivered artifacts, not the inline assertion body; PR #5280 merged the
# ASSERT-FAILED sentinels with `0 changed` and they never ran on the host).
#
# `set -e` FIRST: terraform joins a `remote-exec` `inline` into ONE script with
# NO implicit errexit and fails only on the LAST command's exit — and a bare
# `bash script.sh` is itself one shell, so the script must own errexit. Without
# it every assertion below is decorative (the silent-green failure AC-P2.8
# exists to prevent; caught by 5 review agents on PR #5089). The enforcement
# probes use explicit if/exit-1 because `!`-prefixed pipelines are errexit-exempt
# under POSIX.
#
# SELF-REPORTING SENTINELS (#5279): terraform SUPPRESSES inline remote-exec
# stdout, so a bare failing assertion exits 1 with NO indication of WHICH check
# failed — the exact reason #5247 took 3 PRs to chase a one-line format mismatch
# nobody could see, and why this resource has been red-but-blind since #5089.
# Each command therefore echoes a unique `ASSERT-FAILED: <name>` sentinel BEFORE
# `exit 1`; terraform surfaces the last output lines on error, so the sentinel
# names the culprit even with stdout suppressed (no SSH —
# hr-no-ssh-fallback-in-runbooks). The service-enable lines additionally dump the
# unit's journalctl tail so the loader's `die` message lands in the Actions log
# directly. Wrapping each assertion in `|| { echo …; exit 1; }` keeps the failing
# exit (the `||` handles errexit; the explicit `exit 1` re-raises it) —
# invariants are unchanged; only their observability improves.
set -e
chmod +x /usr/local/bin/cron-egress-nftables.sh /usr/local/bin/cron-egress-resolve.sh /usr/local/bin/cron-egress-alarm.sh || { echo 'ASSERT-FAILED: chmod-scripts'; exit 1; }
systemctl daemon-reload || { echo 'ASSERT-FAILED: daemon-reload'; exit 1; }
# `enable` for boot-persistence; `restart` to RE-RUN the loader NOW. The
# service is Type=oneshot/RemainAfterExit=yes, so `enable --now` (= start)
# no-ops on an already-active unit — the loader never re-reads the
# freshly-provisioned cron-egress-allowlist-cidr.txt and the new CIDR
# ranges sit on disk but absent from the live nft set (the inert-fix bug
# behind the still-missed scheduled-ruleset-bypass-audit check-in,
# incident 5516336). The loader populates the sets BEFORE installing the
# default-drop (availability ordering, asserted in cron-egress-firewall.test.sh),
# so a restart carries no egress gap — it is the same operation that runs at boot.
#
# LEAD failure surface (#5279 4c): the `restart` re-runs the loader and
# blocks on the Type=oneshot exit — a loader `die` (bridge/IPv6/CIDR/
# resolve) fails HERE. Dump the unit journal so the die reason is visible
# in the (otherwise-suppressed) apply log.
systemctl enable cron-egress-firewall.service || { echo 'ASSERT-FAILED: firewall-enable'; exit 1; }
systemctl restart cron-egress-firewall.service || { echo 'ASSERT-FAILED: firewall-restart (loader die — journalctl tail follows)'; journalctl -u cron-egress-firewall.service --no-pager -n 40 2>/dev/null || true; exit 1; }
systemctl enable --now cron-egress-resolve.timer || { echo 'ASSERT-FAILED: resolve-timer-enable'; journalctl -u cron-egress-resolve.timer --no-pager -n 20 2>/dev/null || true; exit 1; }
# Positive post-apply assertions (fail2ban_tuning pattern): structure...
nft list chain ip filter DOCKER-USER | grep -Eq 'jump[[:space:]]+SOLEUR-EGRESS([[:space:]]|$)' || { echo 'ASSERT-FAILED: docker-user-jump'; exit 1; }
nft list chain ip filter SOLEUR-EGRESS | grep -q 'comment "soleur-egress: default drop"' || { echo 'ASSERT-FAILED: default-drop'; exit 1; }
nft list chain ip filter SOLEUR-EGRESS | grep -q 'egress-dns-exfil' || { echo 'ASSERT-FAILED: dns-exfil-drop'; exit 1; }
nft list chain ip filter SOLEUR-EGRESS | grep -q 'dport 8288 accept' || { echo 'ASSERT-FAILED: inngest-8288-accept'; exit 1; }
# Dedicated Inngest host (#6178, ADR-100 cutover): the generic sentinel above passes with
# ONLY the host-gateway rule present, so a recreated host missing 10.0.1.40:8288 would slip
# through. Assert the dedicated-host accept specifically so a missing rule fails post-apply
# loudly (closes the "hides from the cutover gate" hole — op=verify never sees container egress).
nft list chain ip filter SOLEUR-EGRESS | grep -q '10.0.1.40 tcp dport 8288 accept' || { echo 'ASSERT-FAILED: dedicated-inngest-8288-accept'; exit 1; }
nft list set ip filter soleur_egress_allow | grep -qE '[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+' || { echo 'ASSERT-FAILED: allow-set-populated'; exit 1; }
nft list chain ip filter SOLEUR-EGRESS | grep -q 'cidr allowlist' || { echo 'ASSERT-FAILED: cidr-allowlist-rule'; exit 1; }
# Match the GitHub octet, NOT the literal /20: nft renders an interval-set
# element as either the `/20` prefix OR the expanded range
# (140.82.112.0-140.82.127.255) depending on version — the literal prefix
# grep failed the apply post-check even though the set was correctly
# populated (proven live by a successful cron git clone). Display-agnostic.
nft list set ip filter soleur_egress_allow_cidr | grep -qE '140[.]82[.]' || { echo 'ASSERT-FAILED: cidr-set-github'; exit 1; }
# Prove the FULL /meta `.git`+`.api` union landed, not just the 4 big
# git/pages blocks: at least one Azure 20.x or 4.x /32 (the api.github.com
# LB pool whose absence caused the missed check-in, incident 5516336) must
# be present. nft renders the element list as `elements = { a, b, c }`, so
# every element is preceded by a comma or whitespace. Anchor on that
# delimiter so a bare "20."/"4." substring INSIDE one of the big blocks
# cannot false-pass: an unanchored "4[.]" matches "143.55.64.0" (the "4."
# in "64.0"), and nft may render a block as an expanded range
# (143.55.64.0-143.55.79.255). The delimiter anchor requires the octet to
# START an element, so only a real 20.x/4.x element matches.
# Display-format-agnostic, same intent as the cidr-set-github assert above.
nft list set ip filter soleur_egress_allow_cidr | grep -qE '[,[:space:]](20|4)[.]' || { echo 'ASSERT-FAILED: cidr-set-api-pool'; exit 1; }
# GHCR carve (#9275, ADR-096 5.3b-iii): the generator subtracts GitHub's dedicated Packages
# frontends from the allow list and records each effective hole as a
# `# Excluded (GitHub Packages frontends): <cidr>` header line. Prove the carve LANDED in the
# live set, not just in the file: (1) the header exists, (2) POSITIVE CONTROL — the set exists
# and the network address of the file's first allow prefix IS found (so a missing set or an nft
# error cannot masquerade as "absent" below), (3) `nft get element` FAILS for EVERY address of
# every excluded prefix (single addresses on purpose: nft renders adjacent carved prefixes as
# merged ranges, so a per-prefix probe would misread). One command per line, each carrying its
# own sentinel (the sentinel parser in cron-egress-firewall.test.sh rejects a multi-line block).
CIDR_FILE="${CIDR_FILE:-/etc/soleur/cron-egress-allowlist-cidr.txt}"
GHCR_EXCL="$(grep -E '^# Excluded [(]GitHub Packages frontends[)]: ' "$CIDR_FILE" 2>/dev/null | sed -E 's/^# Excluded [(]GitHub Packages frontends[)]: //' || true)"
[ -n "$GHCR_EXCL" ] || { echo 'ASSERT-FAILED: ghcr-carve-header-absent (no Excluded header or unreadable CIDR file: the carve is missing from the installed file)'; exit 1; }
GHCR_FIRST="$(grep -vE '^[[:space:]]*(#|$)' "$CIDR_FILE" | sed -n '1p')"; GHCR_FIRST="${GHCR_FIRST%/*}"; nft get element ip filter soleur_egress_allow_cidr "{ $GHCR_FIRST }" >/dev/null 2>&1 || { echo 'ASSERT-FAILED: ghcr-carve-live-set (positive control: first allow prefix not found in the live set, so absence below would prove nothing)'; exit 1; }
# Header validation mirrors the generator and the resolver sampler: each octet 0-255 with no leading
# zero, prefix /28../32, and the address ALIGNED to its prefix (a network address). Anything else
# (a hostile or corrupted header) is rejected under the same `ghcr-carve-header-absent` sentinel
# before any nft loop runs; a misaligned prefix would walk the wrong address range.
for c in $GHCR_EXCL; do GHCR_OK=0; if [[ "$c" =~ ^(0|[1-9][0-9]{0,2})[.](0|[1-9][0-9]{0,2})[.](0|[1-9][0-9]{0,2})[.](0|[1-9][0-9]{0,2})/(2[89]|3[0-2])$ ]] && [ "${BASH_REMATCH[1]}" -le 255 ] && [ "${BASH_REMATCH[2]}" -le 255 ] && [ "${BASH_REMATCH[3]}" -le 255 ] && [ "${BASH_REMATCH[4]}" -le 255 ]; then GHCR_N=$((32 - ${BASH_REMATCH[5]})); GHCR_BASE=$(( (${BASH_REMATCH[1]} << 24) | (${BASH_REMATCH[2]} << 16) | (${BASH_REMATCH[3]} << 8) | ${BASH_REMATCH[4]} )); if [ $((GHCR_BASE & ((1 << GHCR_N) - 1))) -eq 0 ]; then GHCR_OK=1; fi; fi; [ "$GHCR_OK" -eq 1 ] || { echo "ASSERT-FAILED: ghcr-carve-header-absent (malformed or over-broad Excluded prefix: $c)"; exit 1; }; for ((i = 0; i < (1 << GHCR_N); i++)); do GHCR_V=$((GHCR_BASE + i)); GHCR_IP="$(((GHCR_V >> 24) & 255)).$(((GHCR_V >> 16) & 255)).$(((GHCR_V >> 8) & 255)).$((GHCR_V & 255))"; if nft get element ip filter soleur_egress_allow_cidr "{ $GHCR_IP }" >/dev/null 2>&1; then echo "ASSERT-FAILED: ghcr-carve-live-set $GHCR_IP (excluded Packages frontend is present in the live allow set)"; exit 1; fi; done; done
# End-to-end, when the container runs: one probe pinned to the first excluded address must NOT
# connect. THREE-STATE verdict (fail-closed on a connect, never fail-open on silence): `held` needs
# rc 28 (curl's timeout) AND a well-formed time_connect of 0 (a silent drop times out before any
# handshake; the probe is pinned with --resolve, so time_namelookup is ~0 by construction and is
# not part of the verdict); `reached` (rc 0, or time_connect > 0 even with rc 28 when the handshake
# completed and a later phase timed out) is fatal; ANYTHING else (docker exec failed rc 125/127,
# the 15 s timeout wrapper fired rc 124/137, empty or non-numeric output) is INCONCLUSIVE: a loud
# WARNING and no `held-ok`. The container's curl is untrusted: its output is length-capped
# (`head -c`) and shape-validated before use. The `| head -c` pipeline would MASK curl's exit code
# under set -e (the pipeline status is head's, so a held probe and a failing docker exec would both
# read rc 0), so the producer's status is re-raised from the substitution via PIPESTATUS[0]. `-q` /
# `--noproxy` keep a planted .curlrc or proxy env from steering the result. Skipped LOUDLY on a
# fresh host (the nft get element checks above still ran there).
if docker ps --format '{{.Names}}' | grep -qx soleur-web-platform; then GHCR_IP="${GHCR_EXCL%%[[:space:]]*}"; GHCR_IP="${GHCR_IP%/*}"; GHCR_RC=0; GHCR_OUT="$(timeout -k 2 15 docker exec soleur-web-platform curl -q -s -o /dev/null --noproxy '*' --connect-timeout 5 --max-time 8 --resolve "ghcr.io:443:$GHCR_IP" -w '%{time_connect}' https://ghcr.io/ 2>/dev/null | head -c 64; exit "${PIPESTATUS[0]}")" || GHCR_RC=$?; GHCR_TC=malformed; if [[ "$GHCR_OUT" =~ ^[0-9]{1,3}([.][0-9]{1,9})?$ ]]; then GHCR_TC="$GHCR_OUT"; fi; if [ "$GHCR_RC" -eq 0 ] || { [ "$GHCR_TC" != malformed ] && awk -v t="$GHCR_TC" 'BEGIN { exit !(t + 0 > 0) }'; }; then echo "ASSERT-FAILED: ghcr-frontend-reachable $GHCR_IP (a bridge container completed a TCP handshake to an excluded Packages frontend; rc=$GHCR_RC)"; exit 1; elif [ "$GHCR_RC" -eq 28 ] && [ "$GHCR_TC" != malformed ]; then echo ghcr-frontend-held-ok; else echo "WARNING: ghcr-frontend-inconclusive (rc=$GHCR_RC): the live probe could not prove the drop; the nft get element checks above are the authoritative proof"; fi; else echo 'WARNING: soleur-web-platform not running — ghcr-frontend-reachable probe SKIPPED (fresh-host bootstrap); the nft get element checks above still ran'; fi
docker network inspect bridge -f '{{.EnableIPv6}}' | grep -qx false || { echo 'ASSERT-FAILED: bridge-ipv6'; exit 1; }
systemctl is-active cron-egress-firewall.service cron-egress-resolve.timer || { echo 'ASSERT-FAILED: units-active'; exit 1; }
# ...and ENFORCEMENT: egress-probe-positive — an allowlisted host reaches
# from inside the container; egress-probe-negative — a non-allowlisted
# host is dropped (curl times out). An inert ruleset fails the negative
# probe, aborting the apply (AC-P2.8 merge precondition). On a FRESH host
# the first infra apply precedes the first deploy (no container yet) —
# skip the container probes LOUDLY; the next apply after deploy proves
# enforcement (hr-fresh-host-provisioning: the server_id trigger re-runs
# this provisioner on host replacement anyway).
if docker ps --format '{{.Names}}' | grep -qx soleur-web-platform; then if ! docker exec soleur-web-platform curl -s -o /dev/null --max-time 20 https://api.github.com; then echo 'ASSERT-FAILED: egress-probe-positive (allowlisted host unreachable from container)'; exit 1; fi; echo egress-probe-positive-ok; if docker exec soleur-web-platform curl -s -o /dev/null --max-time 8 https://example.com; then echo 'ASSERT-FAILED: egress-probe-negative (ruleset INERT — non-allowlisted host reachable)'; exit 1; fi; echo egress-probe-negative-ok; else echo 'WARNING: soleur-web-platform not running — enforcement probes SKIPPED (fresh-host bootstrap); re-apply after first deploy to prove enforcement'; fi
# Host egress untouched (AC-P2.7 spot-check; DOCKER-USER never filters
# host OUTPUT — cloudflared/Vector/GHCR/apt are out of scope by design).
curl -s -o /dev/null --max-time 10 https://api.github.com || { echo 'ASSERT-FAILED: host-egress'; exit 1; }
echo host-egress-ok
