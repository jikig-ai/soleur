# Runbook: cron-egress-blocked (container egress firewall page)

**Alert:** Sentry issue alert `cron-egress-blocked` — fires on an error event
tagged `feature=cron-egress-firewall` + `op=egress_blocked`, produced by the
host's `cron-egress-resolve.timer` when the kernel journal shows
`egress-blocked:` or `egress-dns-exfil:` drops in the last window. Since #9275 the
same rule also fires on `op=ghcr_deny_lost` and `op=ghcr_deny_probe_blind`
(see [GHCR carve (#9275)](#ghcr-carve-9275)); those are not drops and do not
follow the cause list below. Since #9377 it also fires on `op=resolve_link_local`
(see the decode table in the GHCR carve section); that is not a drop either.
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
   **Then check whether `DST` is inside an excluded Packages prefix, before
   anything else:** `grep '^# Excluded' apps/web-platform/infra/cron-egress-allowlist-cidr.txt`
   lists the carved prefixes. A drop to an address inside one of them is the GHCR
   deny **working** (see [GHCR carve (#9275)](#ghcr-carve-9275)): something in the
   container dialed `ghcr.io` or `docker.pkg.github.com`. Find the dialer (steps
   2 and 3 below) and stop it. Do not widen the CIDR file and do not allowlist
   the address.
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

**First rule out the carve.** If the blocked `DST=<ip>` lies inside an
`# Excluded (GitHub Packages frontends)` prefix of the installed file (the first
Diagnosis step), the deny is working and this section does not apply: find the
dialer, do not widen the CIDR file.

If the blocked `DST=<ip>` is a GitHub address outside those prefixes (a
`20.x`/`4.x` Azure host or a `140.82`/`185.199`/`192.30`/`143.55` range) and the
failing flow dials `github.com` or `api.github.com`, the CIDR allowlist is
missing part of GitHub's load-balancer pool. **`api.github.com` round-robins DNS across TWO
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
(`jq -r '(.git+.api)[]|select(test(":")|not)' | sort -u`), carves the GitHub
Packages frontends out of it (since #9275; see
[GHCR carve (#9275)](#ghcr-carve-9275)), validates every line
(reject-whole-file + over-broad `< /8` reject), and atomically writes
`apps/web-platform/infra/cron-egress-allowlist-cidr.txt` only if the CIDR body
changed (the `# Generated:` date is not restamped on a no-op). There is no count
guard to bump — the drift-guard is now structural (floor + over-broad reject),
not a magic count. Verify zero gap with the generator's own drift check:

```bash
bash apps/web-platform/infra/scripts/gen-github-egress-cidr.sh --check
```

Exit 0 = the committed file equals what the generator produces from the live
`/meta`; exit 1 = drift **or a die** (any refusal below, such as
`ghcr-carve-would-cut-github`, exits 1 too, so read the message), and because the
generator's DNS guard looks up `github.com` and `api.github.com` live, the result
also depends on live DNS answers. **This needs network access to
`api.github.com/meta`; it is not an offline recipe.** A line-by-line `comm` of `/meta` against the file
is no longer valid, because the carved Packages frontends are deliberately
absent from the file and would read as "uncovered". Exit 1 means either `/meta`
moved since the last refresh (the daily cron opens the PR) or the committed file
was edited by hand; run the generator without `--check` to regenerate it, never
edit the file.

Merge — the provisioner re-applies on push (no SSH). To force a **refresh**
(regenerate the file and open the PR) without waiting for the schedule, dry-fire
the cron via `/soleur:trigger-cron` (`cron/github-cidr-refresh.manual-trigger`);
that needs no `gh workflow run`, and it opens a PR only when `/meta` has moved
(on an unchanged `/meta` the generator is a no-op).

**What a dispatch of the apply workflow can and cannot re-deliver.**
`terraform_data.cron_egress_firewall` is keyed (`triggers_replace` in
`apps/web-platform/infra/server.tf`) on a hash of ten delivered files (the three
scripts `cron-egress-nftables.sh`, `cron-egress-resolve.sh` and
`cron-egress-alarm.sh`, both allowlists, the four systemd unit files and
`cron-egress-postapply-assert.sh`) plus web-1's server id. The workflow's
`manual-rerun` path (`apply_target` defaults to it; `reason` is the only required
input) includes `-target=terraform_data.cron_egress_firewall`, but Terraform
re-runs that resource's provisioners, and so the post-apply assertion, only when
the key differs from what state recorded, or when an earlier failed provisioner
left the resource tainted. So:

- **A dispatch is the fix** when the last apply that carried the committed files
  failed, or skipped its SSH stage (the "SSH stage skipped, nothing delivered"
  ops notification): state then does not record the current files as delivered.
  Check the latest runs, then dispatch and confirm the run is green; its
  assertion is the proof.

  ```bash
  gh run list --workflow apply-web-platform-infra.yml --branch main --limit 5
  gh workflow run apply-web-platform-infra.yml --ref main -f reason="re-deliver CIDR file"
  ```

- **A dispatch does nothing** when the last apply was green and no hashed file
  changed since: nothing is re-delivered and the post-apply assertion does not
  run. No dispatch input forces it, and no `apply_target` replaces this resource
  (the replace targets are hosts and the CI SSH token), so do not run a
  `terraform apply -replace` of it ad hoc. The way to re-deliver is a **change to
  one of the ten hashed files**, merged to `main`: for example a comment-only edit
  in `cron-egress-allowlist.txt` (not in the generated CIDR file, whose `--check`
  compares it with the generator). The push re-applies it, without a dispatch.

A merge to `main` that changes anything under the workflow's `paths:` filter
(`apps/web-platform/infra/**`, with two rehearsal and root-key subtrees
excluded) starts the apply workflow; it re-delivers the firewall only when one of
the ten hashed files changed. Only web-1 receives it; see the web-2 residual in
[GHCR carve (#9275)](#ghcr-carve-9275).

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
| `ghcr-carve-header-absent` / `ghcr-carve-live-set` / `ghcr-frontend-reachable` | the GHCR carve is missing from the file, present in the live set, or a carved frontend accepted a connection | decode and repair in [GHCR carve (#9275)](#ghcr-carve-9275) |
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

## GHCR carve (#9275)

Bridge containers (the app and its canary) must not reach `ghcr.io` or
`docker.pkg.github.com`. The firewall enforces it by **carving** GitHub's
Packages frontends (the `/meta` `.packages` list) out of the generated CIDR
allow list, and a recurring probe inside the app container proves the carve
holds. The decision, the scoping evidence, the measurements and the accepted
residuals are in ADR-096, "Amendment 2026-10-01 (#9275)"
(`knowledge-base/engineering/architecture/decisions/`); they are not repeated
here.

What exists, in operator terms:

- The committed `cron-egress-allowlist-cidr.txt` carries one header line per
  carved prefix: `# Excluded (GitHub Packages frontends): <cidr>`. Comments are
  ignored by the loader. Never edit the file by hand; it is regenerated daily.
- About every 5 minutes the resolver tick runs one probe per name from inside
  the app container, unless the tick is already more than 30 seconds old (the
  probe is then skipped for that run). A connection that forms is
  `op=ghcr_deny_lost`. A due probe that cannot decide, cannot run because the
  container is absent, or is skipped by the budget gate is counted per name
  (reasons `inconclusive`, `container_absent`, `budget_skipped`); the twelfth
  consecutive one (about an hour) is `op=ghcr_deny_probe_blind`, and it is
  re-emitted every twelfth consecutive blind run (hourly) while the blindness
  lasts. A blocked probe emits nothing. The tick's own `cron-egress-resolve`
  check-in proves only that the **tick** ran, not that the probe decided; probe
  silence converges to `ghcr_deny_probe_blind`, never to a quiet green.
- Each op has a **static message**, so each lands in its own Sentry issue group,
  distinct from the long-standing `egress_blocked` group. The name and address
  are in `extra`, never in the message.
- The apply workflow's post-apply assertion checks every carved address and one
  live probe (the sentinels below).

### Decode

| Signal | Where it appears | Meaning | Go to |
|---|---|---|---|
| `op=ghcr_deny_lost` | Sentry error event, `feature=cron-egress-firewall`; `extra`: `name`, `remote_ip`, `time_connect`, `in_allow_cidr`, `in_allow_name`, `file_sha256`, `remediation` | A TCP connection from the app container to `name` formed. The deny is not holding for that address. | Repair ladder |
| `op=resolve_link_local` | Sentry error event, `feature=cron-egress-firewall`; message names the resolving source; `extra`: `source`, `addresses`, `remediation` | A vendor name in the allowlist (or a dynamic host env) resolved into 169.254.0.0/16, the instance-metadata range. The address was **dropped and never allowlisted**, so the firewall is intact. One event per source until that source answers clean again; the resolver writes its once-per-source marker only after a POST succeeded, so a failed or unconfigured attempt is retried on the next tick, and delivery is best-effort (a first sighting pages once per source). | Read the event (`doppler run -p soleur -c prd -- bash scripts/sentry-issue.sh --latest-event <issue-id>`): `extra.source` names the resolving name and `extra.addresses` the answer. For a hostname source, first check that `extra.source` matches `^[A-Za-z0-9.-]+$` (event fields are forgeable by anyone holding the DSN key; never paste anything else into a shell), then re-run its lookup read-only, no SSH, quoted: `getent ahostsv4 -- '<source>'` (the lookup the resolver itself does; an answer in `169.254.0.0/16` confirms it). A clean answer from your machine does **not** clear the event: the poisoned answer may be specific to the host's resolver, a split-horizon name or a rotated record, so `extra.addresses` (what the host saw) is the evidence. `container-view` and `dns-pin` are not names: the addresses came from the container's resolver view or its pinned nameservers, so read them from `extra.addresses`. Remove or correct the name under review. Never allowlist the address. |
| `op=ghcr_deny_probe_blind` | Sentry error event; `extra`: `name`, `reason` (`inconclusive`, `container_absent` or `budget_skipped`), `last_rc`, `last_namelookup`; re-emitted hourly while it lasts | For about an hour the probe could not decide for `name`. The deny is **unverified**, not known broken. | Blind ladder |
| `ASSERT-FAILED: ghcr-carve-header-absent` | `apply-web-platform-infra.yml` run log | The installed CIDR file has no `# Excluded` header, **or** it cannot be read, **or** a header prefix is malformed, over-broad or misaligned (an octet above 255, a leading-zero octet, a prefix outside /28 to /32, or a base address not aligned to its prefix). Either way the carve in the installed file cannot be trusted: it was bypassed, corrupted or never regenerated. | Regenerate with the generator (GitHub LB pool section above), then re-deliver |
| `ASSERT-FAILED: ghcr-carve-live-set <ip>` | same | A carved address is present in the live `soleur_egress_allow_cidr` set: the loader did not reload the carved file, or the set is stale. | Re-deliver (see the apply-workflow paragraph in the GitHub LB pool section) |
| `ASSERT-FAILED: ghcr-carve-live-set` (no address) | same | The **positive control** failed: the file's first allow prefix is not in the live set, so a later absence of the carved addresses would prove nothing. The set is empty or was not loaded. | Re-deliver, then read `firewall-restart` and `allow-set-populated` in the table above |
| `ASSERT-FAILED: ghcr-frontend-reachable <ip>` | same | The live probe connected to a carved address from the app container (the probe saw a TCP connect). The ruleset is not denying it. | Treat as a containment bug: re-deliver, then `default-drop` and `egress-probe-negative` in the table above name what else is wrong. Never relax the assertion. |
| `WARNING: ghcr-frontend-inconclusive (rc=<rc>)` | same; **the apply continues** | The live probe neither saw a connect nor proved the drop (the proven-drop case is `rc=28` with a zero connect time, printed as `ghcr-frontend-held-ok`). The `nft get element` checks that ran before it are the hard gate and passed. One occurrence is noise; repeats mean the probe path is unhealthy, and the recurring in-container probe will report `ghcr_deny_probe_blind`. | Blind ladder |
| `WARNING: soleur-web-platform not running — ghcr-frontend-reachable probe SKIPPED` | same; **the apply continues** | The app container was not running (fresh-host bootstrap), so the live probe was skipped. It is a loud WARNING, not an `ASSERT-FAILED`; the `nft get element` checks still ran. | None unless it repeats on a running host |
| `ghcr-carve-would-cut-github` | The generator's error line. It reaches Sentry as the handler's `reportSilentFallback` event (`feature=cron-github-cidr-refresh`, `op=handler-top-level`, generator stderr tail), **not** through the check-in heartbeat, which carries no message | The generator refused to write because `github.com` or `api.github.com` resolved into a carved range. **The daily refresh is frozen and the stale file keeps serving.** | Refresh frozen (below) |
| `ghcr-carve-no-effective-holes` | Same route: the handler's `reportSilentFallback` event (`op=handler-top-level`) | The generator died because **zero effective Packages holes remain** (every `.packages` entry is now outside the allow list, an exact `.git`/`.web`/`.api` member, or skipped), or `.packages` lists more than 512 IPv4 entries. It does not write an uncarved file. **The refresh is frozen and the stale carved file keeps serving.** | Refresh frozen (below) |

Read the events with the Sentry issue id from the alert email's link:

```bash
doppler run -p soleur -c prd -- scripts/sentry-issue.sh --latest-event <issue-id>
```

### Repair ladder for `ghcr_deny_lost` (keyed by `extra`)

1. `file_sha256` differs from the committed file's sha256 (the resolver hashes
   the host's installed file, so the host is serving an older file than the
   repo's), or `in_allow_cidr` is `true` while `remote_ip` lies inside an
   `# Excluded` prefix of the committed file (the live set is stale relative to
   the file): the committed carve was never delivered or loaded, or the host
   drifted. Check
   `gh run list --workflow apply-web-platform-infra.yml --branch main --limit 5`.
   If the latest run that carried the committed file failed or skipped its SSH
   stage, state does not record it as delivered, so a dispatch
   (`gh workflow run apply-web-platform-infra.yml --ref main -f reason="..."`)
   re-delivers it; confirm the run is green, its assertion is the proof. If the
   latest run is green, state believes the delivery succeeded and an unchanged
   dispatch re-delivers nothing and runs no assertion: merge a change to one of
   the ten hashed files instead (see the apply-workflow paragraph in the GitHub
   LB pool section). Triggering `cron/github-cidr-refresh.manual-trigger` helps
   only if `/meta` moved.
2. `remote_ip` is an address that `/meta` `.packages` does not list (GitHub moved
   a Packages frontend, so the carve never covered it; `in_allow_cidr` is `true`,
   `remote_ip` is in no `# Excluded` prefix and `file_sha256` matches): carving it needs a **generator change in a PR**.
   There is no extra-hole list, override or config input: holes come only from
   `/meta` `.packages`, so no edit to the CIDR file or a data file does this.
   `ghcr_deny_lost.extra.remote_ip` names the address. The change gives the
   generator a reviewed, explicit way to treat that address as a hole (with a
   test), under the generator's existing `github.com` / `api.github.com` DNS
   guard; then regenerate the file **with the generator** (never by hand) and
   merge. Before you do, confirm with `curl --resolve github.com:443:<ip> https://github.com/` and
   `curl --resolve ghcr.io:443:<ip> https://ghcr.io/` that the address serves
   ghcr.io and not github.com; carving an address that serves `github.com`
   cuts GitHub access.
3. `in_allow_name` is `true`: the by-name allow set admitted the connection. The
   by-name rule precedes the CIDR rule and wins by order, so a hostname in
   `cron-egress-allowlist.txt` that resolves into a carved address stays
   admitted; the carve cannot stop it and the probe only sees `ghcr.io` and
   `docker.pkg.github.com` answers. Identify which allowlisted hostname resolves
   to `remote_ip` and decide in a PR; do not carve around it.
4. `in_allow_cidr` is `false`, `in_allow_name` is `false` and `file_sha256`
   matches: neither set admitted the connection, so something else did, or the
   rules are not enforcing. Re-deliver and read the `ASSERT-FAILED` sentinels;
   check for `op=enforcement_missing` events (Related signals).

### Repair ladder for `ghcr_deny_probe_blind`

`reason=container_absent`: the app container was not running at twelve due
probes in a row. Restore the container; the counter resets on the next held or
reached verdict. `reason=budget_skipped`: the tick was already more than 30
seconds old at twelve due probes in a row, so a slow resolve pass is starving
the probe; look for what makes ticks long (`op=resolve_host_failed` events).
`reason=inconclusive`: `last_rc` and `last_namelookup` say why. `last_rc=6` is a
failed name lookup; `last_rc=28` with `last_namelookup=0` is a hung resolver (it
is deliberately not read as a held connection); `last_rc=124` is the 15 s
`timeout` around `docker exec` firing (docker or the container hung);
`last_rc=7` is a curl connect failure or refusal, which is not evidence of a
drop and is not read as one; `125`-`127` means `docker exec` or `curl` itself
failed. A non-root process in the container that holds a port in the reserved
range can also make a verdict inconclusive (see "Reserved port range"). Fix that
dependency. While blind, the deny is unverified, not broken; the counter resets
on the next held or reached verdict. The apply-time live probe re-proves it only
when the provisioner runs (a merged change to a hashed file, or a tainted
resource); an unchanged dispatch runs nothing.

### Refresh frozen (`ghcr-carve-would-cut-github`, `ghcr-carve-no-effective-holes`)

The generator dies instead of writing, so the daily refresh stops and the stale
carved file keeps serving. That is safe for the carve and **time-sensitive for
GitHub's LB rotation** (the incident 5516336 class above). The die message is in
the handler's `reportSilentFallback` event (`feature=cron-github-cidr-refresh`,
`op=handler-top-level`, stderr tail); the monitor's error check-in is what
emails and carries no message. Re-run the generator locally to read the message
too. Never bypass a guard.

- **`ghcr-carve-would-cut-github`:** run `getent ahostsv4 github.com api.github.com`
  and the `curl --resolve` check from the ladder above to see which name the
  address really serves. If it serves `github.com` or `api.github.com`, the
  carve must exclude it: a generator change in a PR.
- **`ghcr-carve-no-effective-holes`:** no Packages frontend remains inside the
  allow ranges, which means GitHub changed the shape of `/meta` (or `.packages`
  exceeded 512 IPv4 entries). The generator will not write an uncarved file.
  Compare `/meta` `.packages` with the allow ranges and unfreeze with a
  generator or PR change that reflects what GitHub changed; the stale carved
  file keeps serving until then.

### Alert behaviour: resolved in Sentry is not fixed

The rule emails the project's active members on **first-seen, reappeared and
regression** of an issue group. A loss therefore emails **once per unresolved
issue group**; later events in the same unresolved group do not email again, and
`ghcr_deny_lost` and `ghcr_deny_probe_blind` are separate groups. Marking a group
resolved only re-arms the alert; it does not mean the deny is back. Judge the fix
by an apply run whose provisioner ran and went green, plus 24 hours with **no
`ghcr_deny_lost` and no `ghcr_deny_probe_blind` event**: a green
`cron-egress-resolve` check-in alone proves only that the tick ran, and quiet
could mean blind. If no email ever arrives, check that the monitor environment is
not muted (#8704). `op=enforcement_missing` is deliberately **not** routed by this
rule: it is a different failure (the enforcement self-heal) tracked by #9392 (297
events since 2026-06-11, about 2.7 a day on average and about 15 a day in the
week to 2026-10-01; 335 events and about 2.9 a day on average as of 2026-10-03), and widening an alert filter for an unexamined recurring
event is a separate decision. Routing it would not page daily, since the rule
emails once per unresolved issue group. Whether to route it is decided from the
new `extra` fields once a delivered resolver has produced a week of events: see
"Related signals" below for the decode and the decision rule.

To read a monitor's mute state (environment-level, not only the top-level flag) with no
SSH, run the audit script with Doppler's IaC token mapped onto the name it reads, writing
its report to a scratch directory (the default path is a tracked one):
`doppler run -p soleur -c prd -- bash -c 'export SENTRY_AUTH_TOKEN="$SENTRY_IAC_AUTH_TOKEN" AUDIT_OUT_DIR="$(mktemp -d)"; apps/web-platform/scripts/sentry-monitors-audit.sh; grep -A12 "Silent monitors" "$AUDIT_OUT_DIR"/sentry-migration-audit-*.md'`.
The answer is in the report's "Silent monitors" section, not on stdout: a monitor that is
absent from that list is not muted, unless the section prints `Muted monitors: **unknown**`
(the API carried no mute field), in which case use the RW-token read below (see the naming
trap in the script's header). It reads `SENTRY_ORG` from the same Doppler config.
`SENTRY_ISSUE_RO_TOKEN` answers 403 on the monitors endpoint (its scopes cover the
issue and event endpoints only; measured 2026-10-03); a raw GET with the write-scoped
`SENTRY_ISSUE_RW_TOKEN` from Doppler `soleur/prd` also works but is a fallback only,
used read-only and never printed. On 2026-10-03 `cron-egress-resolve` and
`cron-github-cidr-refresh` both read `isMuted: false` with a healthy `production`
environment. A mute is a Sentry write the Terraform provider cannot express, so
finding one is reported as an approval request, never fixed silently.

### Reserved port range

The probe dials from source ports 49100-49199, inside the ephemeral range. A
kernel drop from that range, to port 443 of a carved frontend, is not counted in
`egress_blocked`. Any other drop is still counted, and a real dial to a carved
frontend from another port stays visible. If you are chasing a GHCR dial and see
no `egress_blocked` sample for it, the source port is the thing to check first.
The range is about 100 of the roughly 28,000 default ephemeral ports (32768 to
60999, about 0.35%), so about that share of legitimate dials to a carved
address is hidden from the count, and a compromised container can pick a port in
the range to hide dials to the carved frontends only (the filter takes the first
`SPT`/`DPT`/`DST` token, requires TCP, never suppresses a line carrying an inner
`[SRC=` header, and counts every line if it fails).

The probe is not a trust anchor: a root-compromised container can forge a `held`
verdict, and a non-root process can bind the reserved source ports first, which
makes the verdict inconclusive (a `ghcr_deny_probe_blind` after about an hour).

### Known residual: running web-2

*As of 2026-10-03; this section's removal trigger is the #9372 rebirth run (#9393 also needs the web-1 apply to close).* `terraform_data.cron_egress_firewall`
is web-1-only, so the running web-2 keeps the old allow list and resolver, and has no
probe, until it is **reborn** by the single-use gated volume rebirth (#9372, ADR-263). A
reborn host boots from the baked image whose host scripts and `cloud-init.yml` carry
the carve, so the rebirth is the delivery event. Do not use a plain
`web-host-replace` for this: ADR-263's discriminate step refuses the live plaintext
web-2 volume, and a plain replace would power the host off until #9372 runs. The
#9372 image must be built from a commit that already carries the resolver and loader
changes in `cron-egress-resolve.sh` and `cron-egress-nftables.sh` (both are baked host
scripts, so their content hash moves). Until then web-2 is a weight-0 standby with no
user traffic and GHCR stays reachable from its bridge containers; the host-process deny
from #9169 already reaches it through `deploy_pipeline_fix_web2`. The closing event
is the #9372 rebirth run.

### Known residual: web-1 until the apply workflow runs

*As of 2026-10-03; this section's removal trigger is the first green `apply-web-platform-infra.yml` run whose SSH apply step ran after the resolver and loader changes (#9393 also needs the web-2 rebirth to close).* The carve is merged
(PR #9385) but not delivered to web-1: `apply-web-platform-infra.yml` and
`apply-deploy-pipeline-fix.yml` are `disabled_manually` (both updated 2026-10-01T21:30Z,
the hold for the web-1 plaintext wipe window, #9348), so merges trigger no apply. The
first run of `apply-web-platform-infra.yml` (the only workflow that targets
`terraform_data.cron_egress_firewall`) delivers it: that resource hashes the carve file,
the resolver and the post-apply assertion, and its provisioner ends with the live positive
and negative container probe, so a green run whose SSH apply step actually ran is the
proof. That step can green-skip (#7539), which delivers nothing, and
`apply-deploy-pipeline-fix.yml` does not target the resource at all, so enabling only that
one delivers nothing either. Read the state with
`gh workflow view apply-web-platform-infra.yml` (is it `disabled_manually`?) and
`gh run list --workflow=apply-web-platform-infra.yml` / `gh run view <id> --log`. Until it
runs, web-1 has the old allow list and resolver and no probe, so `ghcr_deny_lost` and
`ghcr_deny_probe_blind` are silent there and that silence is not evidence of the deny.
The repair ladders above that say to re-dispatch that workflow need it enabled first.

While those workflows are paused, **any merge that changes a registry render input
leaves a pending registry replace that nothing re-fires**: the dispatcher fires on merge
and dispatches the paused workflow, so the dispatch fails. Hold such a change until the
pause is lifted, and read `scripts/registry-replace-preflight.sh` before it lands.

Enabling the workflows is a production-write authorization and is the operator's call,
not a step of this runbook: the first apply after a long pause carries every infra
merge since (as of 2026-10-03 the carve, the LUKS web-host follow-ups #9397 and the
git-data notification change #9440), so read its plan before approving. The re-pause for
the wipe is owned by the wipe procedure (`workspaces-luks-cutover-6604.md`, "Re-pause (d)"). Re-evaluate
this section on 2026-10-17; if both workflows are still paused then, ask for the
approval again.

## Related signals

- `cron-egress-resolve` Sentry Crons monitor RED = the resolve timer itself
  is dead/hung (allowlist frozen — IPs rotate away over hours). Check
  `op=resolve_host_failed` events for a persistently unresolvable host. A RED check-in
  right after an `op=enforcement_missing` event means the self-heal loader re-run itself
  failed or timed out (`self-heal loader re-run failed (rc=N)` in the alarm email's journal
  tail, with the same `loader_rc` on the event), not a dead timer.
- `op=enforcement_missing` event = a tick found the jump rule or the default-drop
  rule, or the default-drop LOG rule, not confirmed present and the self-heal re-ran the
  loader. The loader runs first, under `timeout -k 2 60` (egress is open until it does), then
  the event posts, then the tick fails if the re-run failed: a failed or timed-out re-run
  (`loader_rc` 124) still reports, and only a loader that is killed with the whole unit at 120 s
  could lose the event (the alarm email still fires). The event now says which cause class fired (a resolver delivered after #9392; an older resolver, web-2
  until its rebirth, sends the old shape with no `host`):

  | `extra` field | Reads as |
  |---|---|
  | `jump_present`, `drop_present`, `log_present` | `present`, `absent` or `unreadable` per rule; `drop_present` is the `counter drop` rule itself (matched on its comment), `log_present` the default-drop log rule (matched on its comment), `jump_present` the `jump SOLEUR-EGRESS` rule |
  | `read_failed=true`, `rc_jump` / `rc_drop` nonzero with a rule `unreadable` | an `nft` read failed twice (netlink contention or an `nft` fault, a missing binary is rc 127), not an absent rule: a read problem, not a flush |
  | a rule `absent` with `rc_*` = 1 | nft's own `Error: No such file or directory` (rc 1): the object itself is missing (a deleted table or chain), which IS a flush-class event, not contention. A tick right after boot can read this too (the loader has not created the chain yet): check `loader_since` and `docker_since` first |
  | `log_present=absent` with both other rules `present` | only the default-drop LOG rule is gone: the drop still holds, but the `egress_blocked` page loses its feed, so the heal still runs |
  | `read_retried=true` | the first read failed and a retry was needed; `rc_*` are the LAST attempt's statuses, so `read_retried=true` with both `rc_*` 0 means the first read failed and the second succeeded |
  | `loader_rc` | the loader re-run's exit status: 0 ok, 124 timed out (a wedged loader, usually the same netlink contention), 137 killed after ignoring the TERM (the `-k 2` grace), anything else is the loader's own failure |
  | `host` | the host that emitted the event (web-1 or web-2); an older resolver (web-2 until its rebirth) sends no `host` and no new fields |
  | `docker_since` just before the tick | Docker restarted and reprogrammed `DOCKER-USER` |
  | `loader_since` just before the tick | a loader run finished shortly before the tick (the stamp is when the loader unit last became active, not an overlap detector) |
  | both rules `absent` (statuses 0, or 1 with the ENOENT text), `read_retried=false`, nothing recent | a real external flush |

  Timestamps are the host-local strings systemd prints, so compare them with the Sentry
  event time after converting. Reads that fail once and succeed on the retry emit NO
  event, so contention is only a lower bound in this data. To read it with no SSH, take
  the issue id from #9392 (Sentry issue 127244085):
  `doppler run -p soleur -c prd -- scripts/sentry-issue.sh --latest-event 127244085`
  returns the latest event, where the payload above appears under `.context` (an older
  event shows only `remediation` there), and
  `doppler run -p soleur -c prd -- scripts/sentry-issue.sh 127244085` returns the issue's
  24 h and 30 d event counts. The event tags are only `feature`, `op`, `level`, `logger` and
  `interface_type`: `host` is NOT a tag, so the issue counters cannot be split by host.
  To count the last 7 days of events and how many carry a `host` (read-only, the token is
  expanded inside the child shell and never printed):

  ```bash
  doppler run -p soleur -c prd -- bash -c 'curl -s -H "Authorization: Bearer $SENTRY_ISSUE_RO_TOKEN" \
    "https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/issues/127244085/events/?statsPeriod=7d&full=true" \
    | jq -c "[length, ([.[] | select(.context | has(\"host\"))] | length)]"'
  ```

  The first number is every event, the second only those from a resolver that carries the new
  fields (measured 2026-10-04: `[10, 0]`, all old-shape, as expected before delivery). The bare
  `issues/<id>/events/` path answers 401 here: use the organization-scoped one.

  Decision rule for routing the op (#9392 stays open until it is applied): once an
  apply run whose provisioner ran green has delivered the resolver to web-1, read the
  next 7 days of events. The issue counters include web-2's old-shape events (no `host`,
  nothing to classify), so treat them as an upper bound for web-1 until web-2 is reborn,
  and classify from the events themselves: sample recent events with `--latest-event` and
  discard any whose `.context` has no `host`. With 3 or more
  events, classify by the table above; a dominant `read_failed` means read contention,
  an event within 60 s of `docker_since` or `loader_since` means an upstream effect, and
  both rules absent with nothing recent means a real flush. With 1 or 2 events,
  classify them the same way and extend the window another 7 days. With 0 events in
  those 7 days, close as fixed; absence counts only with that delivery proof, and it
  cannot tell "never happened" from "absorbed by the retry". After a self-heal the next
  tick's silence (no `enforcement_missing`, a green check-in) is the success signal.
  A host that ran the pre-#9392 loader may show more than one `soleur-egress: jump` rule
  (inert: the chain ends in an unconditional drop). The fixed loader adds none when a
  read succeeds and shows the jump, retries once after a failed read, and only after two
  failed reads inserts the jump anyway (a duplicate is inert, a missing jump is not),
  logging `cannot read the DOCKER-USER chain` as a WARN to the journal of the unit that
  ran it. That WARN is journal-only (not shipped), so the off-box proxy for it is
  `read_failed=true` on the event; a persistent read failure repeats the heal every tick
  and can add one inert duplicate per tick until the `nft` read recovers.

## Deeper diagnosis without a host shell (hr-no-ssh-fallback-in-runbooks)

The 3-line Sentry `extra.sample` is one tick's window. To go deeper WITHOUT
SSH:

1. **Accumulate drop history from Sentry.** The resolver re-runs every minute
   and ships a fresh `egress-blocked` / `egress-dns-exfil` event per tick — group
   the issue's events over time to see the full `DST` distribution and hit
   counts, rather than a single sample.
2. **Re-verify the live ruleset via a re-apply, not SSH.** Only a run in which
   the provisioner executes does this: a merge to `main` that changes one of the
   ten hashed files (see the apply-workflow paragraph in the GitHub LB pool
   section), or a `workflow_dispatch` while the resource is tainted or its
   recorded key differs. An unchanged dispatch runs nothing and proves nothing.
   When it runs, the post-apply remote-exec lists the `SOLEUR-EGRESS` chain + the
   `soleur_egress_allow_cidr` set and runs a live positive+negative container
   probe — a passing apply IS the proof the ruleset is correct on the host; a
   failing one names the gap.
3. **Watch the self-heal signal.** An `op=enforcement_missing` event means the
   resolver could not confirm the jump or default-drop rule and re-ran the loader;
   the event's `extra` names the cause class (decode table under "Related signals"),
   so the live ruleset state is observable without logging in.
