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
nft list chain ip filter DOCKER-USER | grep -q 'jump SOLEUR-EGRESS' || { echo 'ASSERT-FAILED: docker-user-jump'; exit 1; }
nft list chain ip filter SOLEUR-EGRESS | grep -q 'egress-blocked' || { echo 'ASSERT-FAILED: default-drop'; exit 1; }
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
