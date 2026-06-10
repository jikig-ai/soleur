# Runbook: cron-egress-blocked (container egress firewall page)

**Alert:** Sentry issue alert `cron-egress-blocked` — fires on an error event
tagged `feature=cron-egress-firewall` + `op=egress_blocked`, produced by the
host's `cron-egress-resolve.timer` when the kernel journal shows
`egress-blocked:` or `egress-dns-exfil:` drops in the last window.
**Substrate:** ADR-051 (`knowledge-base/engineering/architecture/decisions/`).

## What it means

The DOCKER-USER egress firewall dropped container traffic. Three causes, in
likelihood order:

1. **Allowlist gap** — the app/cron legitimately needs a host that is not in
   `apps/web-platform/infra/cron-egress-allowlist.txt` (a new vendor, a new
   first-party endpoint, a CDN subset-DNS answer the resolver never saw).
2. **Rotation window** — a host's IP rotated between resolve ticks (1-min
   timer); self-corrects on the next tick. A one-off event with no recurrence
   is this class — close it.
3. **Actual exfil attempt** — a compromised cron dialing off-allowlist (the
   firewall doing its job). `egress-dns-exfil:` hits = off-pin DNS dialing.

## Diagnosis (no SSH — hr-no-ssh-fallback-in-runbooks)

1. **Read the Sentry event** (the incident skill's `SENTRY_ISSUE_RW_TOKEN`
   toolchain): `extra.sample` carries the last kernel drop lines —
   `DST=<ip>` is the blocked destination; `extra.hits` the volume.
2. **Map IP → hostname:** `curl -s "https://ipinfo.io/<DST-ip>/json"` (org +
   hostname fields), or check the failing flow's own error in the app logs —
   the app container's pino stream ships to Better Stack (Vector Source 3),
   so the fetch error (with the HOSTNAME) is queryable there.
3. **Correlate the flow:** which feature failed? Waitlist (Buttondown), email
   (Resend), push (FCM/Mozilla/Apple), a cron's output issue missing — the
   failing fetch's hostname tells you which allowlist line is missing.
4. **Recurrence check:** one event = likely rotation-window; recurring with
   the same DST = allowlist gap or exfil.

## Remediation (allowlist gap)

1. Edit `apps/web-platform/infra/cron-egress-allowlist.txt` — one hostname
   per line WITH an evidence comment (`file:line` of the runtime code that
   dials it).
2. Update the host-count assertion in
   `apps/web-platform/infra/cron-egress-firewall.test.sh` (exact-set guard —
   it fails the build until the new host is deliberately accounted for).
3. Merge. **No manual apply step:** the allowlist hash is folded into
   `terraform_data.cron_egress_firewall.triggers_replace`, and
   `apply-web-platform-infra.yml`'s SSH block re-runs the provisioner on
   push to main (live positive+negative probes included).
4. Re-validate the affected flow (`/soleur:trigger-cron <event>` for crons;
   the user-facing flow itself otherwise).

## Remediation (suspected exfil)

Treat as a security incident (`/soleur:incident`). Do NOT widen the
allowlist. The drop already contained the attempt; capture the Sentry event,
identify the cron via the timing + `extra.sample`, and pause it by adding it
to `TIER2_DEFERRED_CRONS` (`_cron-shared.ts`) pending forensics.

## Related signals

- `cron-egress-resolve` Sentry Crons monitor RED = the resolve timer itself
  is dead/hung (allowlist frozen — IPs rotate away over hours). Check
  `op=resolve_host_failed` events for a persistently unresolvable host.
- `op=enforcement_missing` event = the jump/drop rules were absent at a tick
  and the self-heal re-ran the loader — investigate what flushed nftables.

## Last-resort diagnosis (only after the above)

`ssh root@<host> 'journalctl -k | grep egress-'` and
`nft list chain ip filter SOLEUR-EGRESS` show the live ruleset and full drop
history beyond the 3-line Sentry sample.
