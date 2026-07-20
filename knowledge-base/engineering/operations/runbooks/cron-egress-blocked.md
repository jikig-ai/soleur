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
single-IP resolver is the wrong layer for an LB host.

**Auto-heal (#5284): this is now self-refreshing.** The
`cron-github-cidr-refresh` Inngest cron (daily `41 6 * * *`) fetches `/meta`,
regenerates the file via the committed generator, and opens a direct-merge PR on
drift, after which `apply-web-platform-infra.yml` re-provisions the firewall — no
operator action. To regenerate **on demand** (e.g. before the next daily fire),
run the generator — it is idempotent and a no-op when nothing changed:

```bash
bash apps/web-platform/infra/scripts/gen-github-egress-cidr.sh
```

It fetches `/meta`, extracts the `.git`+`.api` IPv4 union
(`jq -r '(.git+.api)[]|select(test(":")|not)' | sort -u`), validates every line
(reject-whole-file + over-broad `< /8` reject), and atomically writes
`apps/web-platform/infra/cron-egress-allowlist-cidr.txt` only if the CIDR body
changed (the `# Generated:` date is not restamped on a no-op). There is no count
guard to bump — the drift-guard is now structural (floor + over-broad reject),
not a magic count. Verify zero gap with the on-demand discoverability probe:

```bash
comm -23 <(curl -fsS --max-time 30 https://api.github.com/meta | jq -r '(.git+.api)[]|select(test(":")|not)' | sort -u) \
         <(grep -vE '^[[:space:]]*(#|$)' apps/web-platform/infra/cron-egress-allowlist-cidr.txt | sort -u)
```

Empty output = full coverage. Merge — the provisioner re-applies on push (no
SSH). To force a refresh without waiting for the schedule, dry-fire the cron via
`/soleur:trigger-cron` (`cron/github-cidr-refresh.manual-trigger`) — no SSH, no
`gh workflow run`.

## Remediation (LB-rotation IP-coverage gap, non-GitHub host)

If the blocked `DST=<ip>` maps (via `curl -s "https://ipinfo.io/<DST-ip>/json"`)
to a cloud LB provider — **Cloudflare** (`104.x`/`162.159.x`/`172.6x.x`),
**AWS** (`AS16509`/`AS14618`), **Google** (`AS15169`, `*.bc.googleusercontent.com`)
— AND the failing flow dials a host that is ALREADY in
`cron-egress-allowlist.txt` (`discord.com`, `api.x.com`, `api.linkedin.com`,
`api.resend.com`, `bsky.social`, `api.buttondown.com`, `edge.api.flagsmith.com`,
`hn.algolia.com`, …), this is the **non-GitHub analogue** of the api.github.com
`/meta` gap: the hostname IS allowlisted, but it round-robins DNS across a large
LB pool and the single-A-record resolver only pinned the few IPs DNS returned at
the last tick. A connect to a freshly-rotated IP before the next tick is
default-dropped. It is the `missed`-not-`failed` cron-check-in signature for the
six heavy eval crons (community-monitor → `hn.algolia.com`, content-generator →
discord/x/linkedin, …).

**This is now self-healing — grace-window retention (the resolver's `SEEN_DIR`
store + `GRACE_WINDOW_SECS`, default 24h) accumulates each allowlisted host's
full rotation pool over time.** Unlike GitHub, the fix is NOT a CIDR file:
wholesale-allowlisting Cloudflare/AWS/Google ranges would let a compromised cron
egress to any site on those clouds and defeat ADR-052's default-drop. The
resolver instead retains every IP it has *observed DNS return for an
already-allowlisted host* within the window — tight, no provider-CIDR widening.

So a **recurring** `egress-blocked` for an already-allowlisted LB host means one
of:

1. **Window too short** for the host's rotation cadence. Confirm via the
   resolver's OK log (`[cron-egress-resolve] OK: allow=N addrs, retained=M …`):
   `retained` should exceed `allow` for a rotating fleet. If `retained ≈ allow`
   the pool is not accumulating — raise `GRACE_WINDOW_SECS` (env override on the
   unit; the default is 86400). One-off drops with no recurrence are the
   benign rotation-window class — close them.
2. **Store wiped** — `/var/lib/cron-egress-resolve/seen` was cleared (manual
   `rm`, disk reset, or a unit that lost its `StateDirectory=`). The pool
   re-accumulates over one window automatically; no action beyond confirming the
   `StateDirectory=cron-egress-resolve` directive is still on
   `cron-egress-resolve.service`.
3. **Genuinely a NEW host** not in the allowlist (the LB org is incidental) →
   fall through to the allowlist-gap remediation above.

No SSH, no dashboard-eyeball: read the `retained` count and the `egress-blocked`
`extra.sample` straight from Sentry. Do not widen the allowlist to a provider
CIDR to "fix" a rotation drop — that is the wrong layer and the wrong blast
radius.

## Intended-by-design drops (NOT a gap — do not "fix" by allowlisting) — #5676

The single `op=egress_blocked` Sentry issue groups **every** blocked destination
(no per-DST grouping), so a steady, never-zeroing hit count is often **not** a
bug — some drops are deliberate and permanent:

- **`registry.npmjs.org` (Cloudflare anycast `104.16.x.34`, constant `.34`
  host-octet).** Bare `npx` (cron-ux-audit's Playwright MCP) performs a spawn-time
  registry-metadata dial. #5199 deliberately keeps `registry.npmjs.org` OFF the
  allowlist so `@playwright/mcp` resolves to the **image-baked** dep, not a
  runtime supply-chain fetch — the firewall dropping that dial is **working as
  designed**. The cron proceeds on the baked dep. #5676 silenced the dial at
  source (`npm_config_prefer_offline` on the npx env), so it stops being generated
  when the image `_cacache` is warm; a cold cache degrades to drop+baked-dep
  fallback (never a hard cron failure).

**Do NOT** allowlist `registry.npmjs.org` (reverses #5199's supply-chain intent)
and **do NOT** add a DST-IP/range exclusion at the emitter: `registry.npmjs.org`
shares Cloudflare's `104.16.0.0/13` anycast with countless other zones, so an
IP-mute would simultaneously blind a genuine future gap to another
Cloudflare-fronted host (ADR-052 amendment 2026-06-29). **Recovery/health is
judged PER-IDENTIFIED-HOST, never a raw `egress-blocked` count → zero.** Identify
the host behind a `DST` before acting: resolve every codebase egress host via DoH
(`8.8.8.8` + `1.1.1.1`) and match the `DST` fingerprint, and/or
`openssl s_client -connect <DST>:443 -servername <candidate>` to read the cert CN
(Cloudflare anycast hides the customer in the IP). A drop whose host is a known
intended-drop (npm registry probe) is expected; a drop to a **new** legitimately-
needed host is the allowlist-gap remediation above; a drop to an **un-enumerated,
sporadic** host (remote MCP servers, third-party telemetry) stays **blocked**
pending per-host evidence — do not reflexively allowlist it.

### Remote plugin-MCP + CC-telemetry dials (#5691)

The sporadic, low-volume drops the #5676 follow-up enumerated were identified and
silenced at source — **kept blocked, never allowlisted**:

| Blocked DST | Host | Dialer | Disposition |
|---|---|---|---|
| `64.239.123.129` | `mcp.vercel.com` | claude-eval substrate `--plugin-dir plugins/soleur` auto-connects the four remote HTTP MCP servers bundled in `plugin.json` (context7/cloudflare/vercel/stripe) at CLI startup | silenced via `--strict-mcp-config` (substrate prepends it; `cron-ux-audit` re-supplies only Playwright via `--mcp-config .mcp.json`) |
| `104.18.25.159` | `mcp.cloudflare.com` | same | same |
| `198.202.176.231` / `198.137.150.161` | `mcp.stripe.com` | same | same |
| `34.149.66.137` | GCP global-LB serving a Datadog `us5` *default* vhost (default-cert; **not** proof of the dialer — the app's own Sentry ingest `34.160.81.0` is never blocked) | most likely Claude Code's own non-essential outbound traffic (telemetry/error-reporting/auto-update) OR the `context7` MCP backend | silenced via `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` in the cron spawn env (+ `context7` dropped by `--strict-mcp-config`) |

These dials are **non-essential by construction**: the containment hook
(`buildCronEvalSettings`, relax-minimal) denies every `mcp__*` tool — only
`cron-ux-audit` is granted Playwright — so the cloudflare/vercel/stripe/context7
startup handshakes are pure overhead the firewall correctly drops. The at-source
proof is the Spike A `--debug` zero-connect trace (PR #5700 body), strictly stronger
than any post-merge production-absence inference (the drops are vol 1–3 sporadic, so
an absence window cannot *confirm* removal). **Do NOT** allowlist any of these hosts
or add a provider CIDR — that reverses ADR-052's default-drop boundary for zero
benefit (their tools are denied anyway). If `34.149.66.137` (the one vol-21 DST that
carries rate signal) persists after both at-source levers, it is a dependency
phone-home needing a `--debug`/strace trace → file a follow-up; still do not
allowlist it. See ADR-052 amendment 2026-06-29 (#5691).

> **Re-verify on Claude Code CLI upgrades.** That `--strict-mcp-config` suppresses
> *plugin-bundled* MCP servers (vs only project/user scope) is an observed behavior,
> not a documented guarantee — the in-repo tests pin only the flag's *presence and
> position*, not the runtime suppression. After bumping the pinned `claude` CLI,
> re-run the Spike A `--debug-file` zero-connect trace from the repo root
> (`claude --print --plugin-dir plugins/soleur --strict-mcp-config --debug-file /tmp/t.log --allowedTools Skill -- "stop"` then `grep -iE 'mcp\.(cloudflare|vercel|stripe|context7)' /tmp/t.log` → expect zero) to confirm the suppression still holds.

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

## Apply-time post-check failure (`apply-web-platform-infra.yml` red at `cron_egress_firewall`)

This is NOT a runtime drop page — it is the **terraform apply** failing at
`terraform_data.cron_egress_firewall`'s second `remote-exec` (the post-apply
assertion block, `apps/web-platform/infra/server.tf`). Symptom in the Actions
log: `Error: remote-exec provisioner error … error executing "/tmp/terraform_*.sh":
Process exited with status 1`, with no further detail because terraform
**suppresses inline remote-exec stdout**.

**Read the failing assertion straight from the Actions log — no SSH (#5279).**
Since #5279 every assertion in the block echoes a unique `ASSERT-FAILED: <name>`
sentinel before `exit 1`, and the service enable/restart lines also dump the
unit's `journalctl` tail. terraform surfaces the last output lines on error, so
the sentinel is captured even though stdout is suppressed:

```
gh run view <run-id> --log | grep -E 'ASSERT-FAILED|cron-egress-nftables\] ERROR'
```

The sentinel names the culprit directly. Map it to the fix (a drift-guard in
`cron-egress-firewall.test.sh` asserts every sentinel name appears in this
table, so the mapping cannot silently desync from `server.tf`):

| Sentinel | Meaning | Fix |
|---|---|---|
| `firewall-restart (loader die …)` / `firewall-enable` | the `restart` re-runs the Type=oneshot loader (`cron-egress-nftables.sh`) and it `die`d; the journalctl tail below it carries the reason (`enable` only creates the symlink) | follow the `[cron-egress-nftables] ERROR:` line — `invalid CIDR` → CIDR-file section above; `bridge interface docker0 not found` / `EnableIPv6` → host bridge state; `allowlist resolution failed` → DNS/resolver |
| `docker-user-jump` / `default-drop` / `dns-exfil-drop` / `cidr-allowlist-rule` | an nft rule-comment grep missed the live render | re-point the grep at a render-stable token (the #5247 display-agnostic class); **never** weaken a containment invariant to green the apply |
| `cidr-set-github` / `cidr-set-api-pool` | the interval CIDR set is missing the GitHub git blocks (`140.82` …) or the Azure `20.x`/`4.x` `/meta` api LB pool (incident 5516336, #5281) — often the set never reloaded (see `firewall-restart` / inert-fix #5285) | confirm the restart ran; regenerate `cron-egress-allowlist-cidr.txt` per the "GitHub LB pool / CIDR coverage gap" section above; both asserts are display-agnostic |
| `bridge-ipv6` | the default docker bridge reports `EnableIPv6 != false` (real v6 side-channel) OR docker not queryable at apply | fix the bridge config — do not relax the check |
| `allow-set-populated` / `units-active` / `host-egress` | the dynamic allow set is empty / a unit isn't active / host egress to GitHub is blocked | resolver/unit/host-firewall investigation per the named surface |
| `egress-probe-negative` | a non-allowlisted host was REACHABLE from the container — the ruleset is **inert** | a real containment bug; fix the firewall, never the probe |
| `egress-probe-positive` | an allowlisted host was unreachable from the container | an allowlist gap — add the host (allowlist-gap remediation above) |
| `chmod-scripts` / `daemon-reload` / `resolve-timer-enable` / `inngest-8288-accept` | systemd/script plumbing — script not executable, unit file unparseable, timer failed to enable, or the host-gateway `:8288` accept rule is absent | read the shell error above the sentinel; these are early-setup failures, not containment gaps |
| `dedicated-inngest-8288-accept` | the dedicated Inngest host egress rule (`ip daddr 10.0.1.40 tcp dport 8288 accept`, #6178 / ADR-100 cutover) is absent from `SOLEUR-EGRESS` — post-cutover this default-drops every `inngest.send()` container→`10.0.1.40:8288` POST (missed reminders/crons) | confirm `cron-egress-nftables.sh` still carries the `10.0.1.40 tcp dport 8288 accept` rule and the firewall service restarted; the IP is pinned to `inngest-host.tf:33` `inngest_private_ip` |

The fix lands via the existing `apply-web-platform-infra.yml` on merge (the
resource is tainted and re-fires; no manual apply). **Do NOT make the apply
pass by making an assertion non-fatal or relaxing a containment invariant** — a
green check over a broken firewall is worse than a red one at this threshold.

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
