# Runbook: cron-egress-blocked (container egress firewall page)

**Alert:** Sentry issue alert `cron-egress-blocked` — fires on an error event
tagged `feature=cron-egress-firewall` + `op=egress_blocked`, produced by the
host's `cron-egress-resolve.timer` when the kernel journal shows
`egress-blocked:` or `egress-dns-exfil:` drops in the last window.
**Substrate:** ADR-052 (`knowledge-base/engineering/architecture/decisions/`).

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
5. **Upstream 4xx with status-only logs ≠ egress:** if Sentry shows the
   vendor RESPONDED (e.g. `Buttondown subscribe failed: 400`), packets are
   flowing — the firewall is not the cause. Replay the byte-identical
   request from a workstation with the real credential
   (`doppler secrets get <KEY> -p soleur -c prd --plain`) to surface the
   vendor's error body that status-only logging deliberately drops. See
   `knowledge-base/project/learnings/integration-issues/2026-06-11-buttondown-subscriber-firewall-blocks-api-signups.md`
   (vendor-side `subscriber_blocked` masquerading as an egress failure).

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

## Remediation (GitHub LB pool / CIDR coverage gap)

If the blocked `DST=<ip>` is a GitHub address (a `20.x`/`4.x` Azure host or a
`140.82`/`185.199`/`192.30`/`143.55` range) and the failing flow dials
`github.com` or `api.github.com`, the CIDR allowlist is missing part of
GitHub's load-balancer pool. **`api.github.com` round-robins DNS across TWO
pools:** the four big git/pages blocks (`140.82.112.0/20`, `185.199.108.0/22`,
`192.30.252.0/22`, `143.55.64.0/20`) AND ~48 Azure `20.x`/`4.x` `/32` hosts. A
fire that lands on an uncovered IP is default-dropped → no GitHub call → for a
cron, no Sentry heartbeat → a **missed** check-in (not a failed one). This is
exactly the `scheduled-ruleset-bypass-audit` miss on 2026-06-14 (incident
5516336): the file then carried only the 4 big blocks.

The fix is the **CIDR** file (`cron-egress-allowlist-cidr.txt`), NOT the
hostname file — `api.github.com` is already in the hostname allowlist; the
single-IP resolver is the wrong layer for an LB host. Regenerate the complete
`/meta` `.git`+`.api` IPv4 union:

```bash
curl -s https://api.github.com/meta \
  | jq -r '(.git+.api)[]|select(test(":")|not)' | sort -u
```

Write it to `apps/web-platform/infra/cron-egress-allowlist-cidr.txt` (header +
one CIDR per line), then bump the exact-count guard + snapshot date in
`cron-egress-firewall.test.sh`. Verify zero gap with:

```bash
comm -23 <(curl -s https://api.github.com/meta | jq -r '(.git+.api)[]|select(test(":")|not)' | sort -u) \
         <(grep -vE '^[[:space:]]*(#|$)' apps/web-platform/infra/cron-egress-allowlist-cidr.txt | sort -u)
```

Empty output = full coverage. Merge — the provisioner re-applies on push (no
SSH). **The `/32`s rotate**, so this static snapshot will go stale; the
self-refreshing-generator follow-up (#5284) tracks the durable fix.

## Remediation (loader `die "invalid CIDR …"`)

If `cron-egress-firewall.service` failed (not a drop page) and journald shows
`[cron-egress-nftables] ERROR: invalid CIDR in … '<line>'`, the committed
`apps/web-platform/infra/cron-egress-allowlist-cidr.txt` carries a malformed
line (#5242 hardening: the loader rejects the **whole file** rather than
inject an unvalidated line into the nft heredoc). Each line must be a strict
IPv4 CIDR (`A.B.C.D/N`, octets ≤ 255, prefix ≤ 32); comments/blanks are fine.
A CRLF-saved file also fails (trailing `\r`). **Fix the committed file and
merge — do NOT SSH-patch nft;** the provisioner re-runs the loader on push.
Until fixed, the firewall is fail-open-on-bootstrap (no default-drop installed),
so treat it as time-sensitive.

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

## Deeper diagnosis without a host shell (hr-no-ssh-fallback-in-runbooks)

The 3-line Sentry `extra.sample` is one tick's window. To go deeper WITHOUT
SSH:

1. **Accumulate drop history from Sentry.** The resolver re-runs every minute
   and ships a fresh `egress-blocked` / `egress-dns-exfil` event per tick — group
   the issue's events over time to see the full `DST` distribution and hit
   counts, rather than a single sample.
2. **Re-verify the live ruleset via a re-apply, not SSH.** Re-run
   `apply-web-platform-infra.yml` (push to `main` touching
   `apps/web-platform/infra/**`, or `workflow_dispatch`). Its post-apply
   remote-exec lists the `SOLEUR-EGRESS` chain + the `soleur_egress_allow_cidr`
   set and runs a live positive+negative container probe — a passing apply IS
   the proof the ruleset is correct on the host; a failing one names the gap.
3. **Watch the self-heal signal.** An `op=enforcement_missing` event means the
   resolver detected absent jump/drop rules and re-ran the loader — the live
   ruleset state is observable from that event without logging in.
