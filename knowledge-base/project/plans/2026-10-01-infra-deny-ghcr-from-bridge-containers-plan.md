---
title: "infra: deny GHCR and docker.pkg.github.com from bridge containers (ADR-096 5.3b-iii residual)"
type: fix
date: 2026-10-01
slug: infra-deny-ghcr-from-bridge-containers
branch: feat-one-shot-9275-ghcr-bridge-egress
issue: 9275
closes: 9275
lane: cross-domain
priority: p3-low
domain: engineering
brand_survival_threshold: aggregate pattern
---

# infra: deny GHCR and docker.pkg.github.com from bridge containers

## Overview

Containers on the docker0 bridge (the app container and its canary) can still open TCP connections to
the GitHub Container Registry frontends. The container egress firewall admits them through a
generated CIDR list (`cron-egress-allowlist-cidr.txt`) whose ranges (`140.82.112.0/20`,
`185.199.108.0/22`, `192.30.252.0/22`) contain GitHub's dedicated Packages frontends, and
`docker.pkg.github.com` is denied nowhere. This is the last open piece of ADR-096 step 5.3b-iii.

The plan removes the Packages frontends from the generated allow list by **carving them out in the
generator** (data change, firewall runtime untouched), proves with a recurring in-container probe that
the carve holds, and routes a failed probe to the existing Sentry email rule. It does **not** touch
`cloud-init-registry.yml` (requirement 4), narrows nothing that scoping did not prove unneeded, and is
its own PR.

## Research Reconciliation — Spec vs. Codebase

| Claim in the issue / brief | Reality (verified 2026-10-01) | Plan response |
|---|---|---|
| "The fix is either a GHCR-specific drop or a narrower GitHub CIDR set." | The CIDR file is generated (`DO NOT EDIT`), regenerated daily by the `cron-github-cidr-refresh` Inngest cron, and a hand-narrowed file is overwritten. `github.com` (140.82.121.3), `api.github.com` (.6) and `codeload` (.9) live in the same `/20` as GHCR (.33/.34), so a prefix cut cannot separate them. | Narrow in the **generator**, by `/32`-level carve of the `/meta` `.packages` frontends. No loader change, no new nft rule. |
| "docker.pkg.github.com resolves to 140.82.121.34 (the same GitHub frontend)." | It resolves to 140.82.121.33 today; ghcr.io is .34. Both IPs serve **both** names (curl `--resolve`: 301 for ghcr.io, 200 for docker.pkg.github.com), and neither serves github.com or api.github.com. | One carve covers both names. |
| "Gap 2 means editing `cloud-init-registry.yml`." | True only for the **host hosts-file** deny (copy R of the byte-parity guard `web-ghcr-deny.test.sh`). The bridge-egress layer needs no registry byte. | docker.pkg.github.com is denied at the bridge layer here; the host-level line is deferred with a tracking issue and the next registry-host replace as its trigger. `cloud-init-registry.yml` stays byte-identical (AC1). |
| ADR-096 (2026-09-30): "that regression check [`ghcr_blocked=0`] is tracked with #9275." | The issue body for #9275 contains no such item; it concerns the hosts-file deny, a different layer from the bridge gap. | Split out as its own tracked follow-up (see Deferrals); this PR's alert covers the deny this PR adds. ADR text is amended to point at the new issue. |
| Brief: "Narrow the allowlist ... only for what scoping proves unneeded." | Static census proves our code never dials `*.githubusercontent.com`, but `185.199.108.0/22` also fronts `raw.githubusercontent.com` and Pages, and `pkg-containers.githubusercontent.com` (.154) is only a blob CDN that is useless without a ghcr.io token. | The `/22` is **retained** (CTO ruling); only the Packages frontends are carved. Recorded as a deliberate non-narrowing with the evidence. |
| Existing alert story: "`op=enforcement_missing` self-heal event". | It is routed by no Sentry rule, and it is **live and noisy**: one unresolved issue since 2026-06-11, 297 events, ~15/day recently. | Not widened into the page filter (would page daily). Filed as a pre-existing finding (see Deferrals). |

## Research Insights

**Premise Validation (Phase 0.6, 2026-10-01).** Checked and held: #9275 is OPEN (type/security,
priority/p3-low); #9373 is OPEN and unrelated (zot log shipper); #9169 (web-host hosts-file deny) and
#6129 (cosign ENFORCE flip) are CLOSED; #9147 is MERGED; #8714 is OPEN (it tracks 5.4/5.6).
`cron-egress-nftables.sh`, `cron-egress-resolve.sh`, `gen-github-egress-cidr.sh` and
`cron-egress-allowlist-cidr.txt` all exist on origin/main (this branch is origin/main + 1 doc commit).
Stale premise found: the issue's "docker.pkg.github.com = 140.82.121.34" (it is .33 today). ADR-corpus
check of the proposed mechanisms: ADR-052 (container egress firewall: fail-open-on-bootstrap,
availability over containment) and ADR-087 (the allowlist is a grep-enumerated complete set; ghcr.io
must stay out of it) are consistent with a carve; no ADR rejects the mechanism.

**Property List (Phase 0.6b).**

- P1. A process in a bridge-network container cannot open a TCP connection to ghcr.io or
  docker.pkg.github.com, by name or by GitHub's published Packages frontend IPs.
- P2. github.com and api.github.com (git over HTTPS, REST, GraphQL, App-token mint, the `/meta` fetch)
  stay reachable from bridge containers, including across GitHub's LB IP rotation.
- P3. If P1 stops holding the operator is told without SSH, and so is the case where the check itself
  has gone blind.
- P4. The registry host's `user_data` does not change (no ForceNew, no registry-host-replace).
- P5. The narrowing rests on evidence recorded in the repo, and a later change that makes a bridge
  container need GHCR is caught by a test rather than by an outage.

**Cut List (Phase 0.6b).**

- Hand-narrowing `cron-egress-allowlist-cidr.txt` -> cut: generated file, daily regeneration overwrites
  it; narrowing lives in the generator.
- Narrowing `140.82.112.0/20` -> cut: github.com/api/codeload share the `/20` with GHCR.
- A new `soleur_egress_deny` nft set + rule + `!`-prefixed deny lines + loader parser -> cut (CTO):
  subtracting the frontends from the allow list buys P1 with **zero** runtime change; the by-name
  allow rule (`@soleur_egress_allow`) still precedes the CIDR rule, so by-name hosts win by
  construction, and a missing or stale file fails toward a narrower, not wider, allow list.
- Excluding `185.199.108.0/22` -> cut (CTO): not proven unneeded at runtime (shared with raw/Pages),
  and pkg-containers alone cannot pull without ghcr.io's token.
- A hostname/DNS-derived deny set in the resolver -> cut: the `/meta` `.packages` list refreshes daily
  through the existing cron; the 5-minute probe resolves the names through the container's own DNS and
  catches drift off that list.
- Auto-removing a carve that an allowlisted host resolves into -> cut: by-name allow wins by order.
- A GHCR leak probe in `cron-egress-enforce-probe.sh` (boot-time, fail-closed `poweroff`) -> cut: a
  hardening leak must not power off a serving host. The apply-time assertion (`cron-egress-postapply-
  assert.sh`) does gain the check, because an apply may fail loudly.
- A new Sentry cron monitor for the probe -> cut: the repo's two-PR rule (infra/sentry/README) forbids
  routing a new monitor in the same PR, so it could not page; the existing routed rule can.
- A new `sentry_alert` -> cut: the existing `egress_blocked` rule (same `feature=cron-egress-firewall`
  family, same recipients) takes two more `op` values; no new `frequency_minutes`, no rule-count change.
- Widening that rule with `enforcement_missing` -> cut (measured noise, above).
- Logging the carve's drops -> cut: kernel `egress-*` lines do not ship to Better Stack (comment above
  the `BLOCK_HITS` block in `cron-egress-resolve.sh`), so they are unreadable without SSH.
- The Better Stack `ghcr_blocked=0` alert (hosts-file deny regression) -> split out to its own PR
  (CTO + the brief's "do not bundle other ADR-096 work").
- Host-level `docker.pkg.github.com` hosts-file line -> split out (registry `user_data` byte change).
- Added by plan review (2026-10-01, four reviewers): a `ghcr_deny_held` info event and the 3-state
  per-name machine (the apply-time assertion is the T0 proof, the tick check-in is liveness; the
  blind counter stays because P3 requires it); an `EXTRA_PACKAGES_FRONTENDS` knob (`remote_ip` in the
  loss event names the IP for a one-line generator edit); parallel probe jobs with a `mktemp` trap
  (two sequential probes fit the budget); per-IP curl probes at apply time (replaced by an exact
  `nft get element` per address plus one live probe); a separate census suite file (folded into
  `cron-egress-firewall.test.sh`); the ADR-052 pointer, the C4 description edit and the allowlist
  comment edit (no falsified statement).

**Scoping evidence — what bridge containers legitimately need from GitHub address space.**

Static census (this branch == origin/main + 1 doc commit, 2026-10-01):

- `git grep -n -E "githubusercontent|codeload|objects\.github|release-assets|pkg\.github\.com|ghcr\.io" -- apps/web-platform ':!apps/web-platform/infra' ':!apps/web-platform/test' ':!*.test.*'` -> 0 hits.
- The same pattern over `plugins/soleur` (excluding tests and `*.md`) -> 1 hit, `provision-doppler.sh:280`, an OIDC issuer string, not a dial.
- `apps/web-platform/Dockerfile` installs `git`, `curl`, `jq`, `gh`; no `git-lfs` (so no LFS object hosts).
- `server/agent-runner-sandbox-config.ts` `GITHUB_EGRESS_DOMAINS` is exactly `["github.com", "api.github.com"]` ("widening beyond these two hosts ... requires its own security review").
- `cron-egress-allowlist.txt` (the ADR-087 complete set) names exactly `github.com` and `api.github.com` for GitHub.
- Conclusion: bridge containers need github.com and api.github.com, and the Azure `/32` LB pool that api.github.com rotates into (incident 5516336). They need **no** GHCR or `*.pkg.github.com` address.

Live measurements (this runner, 2026-10-01; `curl --resolve host:443:ip`, HTTP code / cert verify):

- `.packages` IPv4 minus exact members of `.git`+`.web`+`.api` -> 28 entries; 9 of them fall inside the current allow prefixes and are the effective carve: `140.82.{112,113,114,121}.{33,34}/32` and `192.30.255.164/31`. The other 19 are Azure `/32`s already outside the allow list (already default-dropped). Only `20.217.135.1/32` overlaps `.git`+`.web` exactly; it serves github.com/api (400) and **not** ghcr.io, so subtracting overlaps is right.
- 140.82.121.34, 140.82.112.34, 140.82.113.33 serve ghcr.io (301) **and** docker.pkg.github.com (200); they do **not** serve github.com or api.github.com (cert-verify fail, 000).
- 140.82.121.3 serves github.com (200) and not ghcr.io; 140.82.121.6 is api.github.com; 140.82.121.9 is codeload.
- 192.30.255.164/165 answer nothing for any of the four names (legacy; carved anyway, harmless).
- A prototype of the carve over the live `/meta` (78 allow entries in) yields 122 prefixes out; github.com, api.github.com, codeload, 140.82.112.3, 140.82.116.5, the legacy github.com IPs 192.30.255.112/113, 143.55.64.1, 185.199.108.154 and both Azure LB samples stay admitted; all nine carved IPs are denied; neighbours 140.82.121.32 and .35 stay admitted.
- `185.199.108.154` (pkg-containers.githubusercontent.com) also answers `raw.githubusercontent.com` (301): a shared Fastly frontend.
- Probe primitive measured locally (curl 8.22.0): a blackholed connect with `--connect-timeout 2 --local-port 49100-49199 -w '%{time_connect} %{remote_ip}'` prints `0.000000` with an empty IP and exits 28; a connect to github.com prints `0.401402 140.82.121.3` and exits 0; an unresolvable name prints `0.000000` and exits 6. So `time_connect > 0` separates reached from held without parsing TLS, `remote_ip` is only available when reached, and no `--retry` flag is used (a retry flag can turn a failure into success; Sharp Edges).
- DNS sampling limits: 25 repeated `getent` samples returned one stable IP per name; `dig` and public resolvers are unavailable from this runner, so DNS-rotation coverage rests on the daily `/meta` regeneration and the probe. Recorded as a limitation.
- Better Stack (`betterstack-query.sh`, prd_terraform): `GHCR_DENY ghcr_blocked=1` is the only value in 7 days (web-1 and web-2, one row each, 2026-10-01); registry heartbeats carry `ghcr_blocked=1`. Zero `egress-blocked` lines (kernel logs are not shipped, which confirms the Sentry sampler is the only drop-forensics channel).
- Sentry (`SENTRY_ISSUE_RO_TOKEN`): `feature:cron-egress-firewall` has two issues over 30 days: `egress_blocked` (76 events, last 2026-10-01T14:02Z) and `enforcement_missing` (297 events, unresolved since 2026-06-11, roughly 15/day this week, last 19:05Z).

**Repo facts that shape the design.**

- `cron-egress-nftables.sh` SOLEUR-EGRESS order: return traffic, intra-bridge, pinned DNS, DNS-exfil
  drops, :8288 x2, `@soleur_egress_allow` (by-name single IPs), `@soleur_egress_allow_cidr`, rate-limited
  log, default drop. DOCKER-USER carries one jump. This PR changes none of it.
- The CIDR file reaches web-1 through `terraform_data.cron_egress_firewall` (hash in `triggers_replace`,
  file provisioners, remote-exec assertion) and fresh hosts through `local.host_script_files` (baked).
  The Inngest cron treats the file as opaque (single `allowedPaths`), so a generator change needs no
  cron change; its output is committed by a **direct-merge** PR (no review) -- a reason the runtime
  probe, not CI, is the control.
- Only one workflow applies `terraform_data.cron_egress_firewall` (`apply-web-platform-infra.yml`, `-target` at line 1174, verified 2026-10-01); `apply-deploy-pipeline-fix.yml` does not reach it.
- `hcloud_server.web` has `ignore_changes = [user_data, ...]`: editing baked host scripts moves
  `local.host_scripts_content_hash` (injected into the web `user_data`) without replacing a running host.
  `hcloud_server.registry` is untouched.
- `cron-egress-resolve.sh` counts only `egress-(blocked|dns-exfil):` (trailing space) kernel lines into the
  `egress_blocked` event; it has `sentry_checkin`, `sentry_event`, `FAILCOUNT_DIR` (tmpfs state under
  `/run`), `container_running`, and runs once a minute under `flock`.
- The runbook's `comm -23` coverage recipe (`cron-egress-blocked.md`) compares live `/meta` to the file
  line by line and would report every carved prefix as "uncovered" after this change; it must be
  replaced by `gen-github-egress-cidr.sh --check`.
- `cron-egress-firewall.test.sh` asserts the literal `140.82.112.0/20` is in the file (line ~222) and
  `cron-egress-postapply-assert.sh` greps `140[.]82[.]` (display-agnostic, still true after a carve).
- G1 census `cloud-init-ghcr-seed-login.test.sh` scans baked host scripts for `docker login ghcr.io`
  and pull/create/run of a `ghcr.io/jikig-ai/` literal; a `curl https://ghcr.io/` probe does not match,
  a `ghcr.io/jikig-ai` literal would.
- Sentry `frequency_minutes` in use today: 5, 10-34, 60-63, 120, 240, 1440-1442 (this plan adds no rule,
  so claims none). Open PRs touching `infra/sentry`: #9352 (LUKS) and #9376 (bwrap rollback alert); both
  may also edit `issue-alerts.tf` / `alert-reference.json`, so expect a rebase there.
- Open code-review issues touching any file below: none (queried 2026-10-01).

**Institutional learnings applied.** ADR-052 (availability over containment; the carve must fail toward
narrower); ADR-087 (allowlist = complete set; CIDR list is an LB-rotation supplement, not new
entitlement); ADR-031 + post-mortem `sentry-cron-monitors-routed-to-no-alert` (a detector with no
routed alert emails nobody -- why `ghcr_deny_*` ops must be added to a routed rule); post-mortem
`ruleset-bypass-audit-cron-egress-cidr-gap` (never narrow the `.git`+`.api` union for hosts the crons
dial; the Azure `/32` pool is what api.github.com rotates through); ADR-147 (baked scripts cost zero
`user_data` bytes).

## Hypotheses (network-outage checklist, L3 to L7)

Triggered by the "no SSH" / firewall wording; each layer answered with an artifact before any
service-layer reasoning.

- **L3 firewall allow-list.** The firewall in question is the host nftables `SOLEUR-EGRESS` chain, not
  the Hetzner cloud firewall (this is container egress). Verified from source: rule order above;
  `hcloud firewall` is irrelevant to docker0 egress. Not verified live (no SSH); the apply-time
  assertion in this plan is the live proof.
- **L3 DNS / routing.** `getent ahostsv4`: ghcr.io -> 140.82.121.34, docker.pkg.github.com ->
  140.82.121.33, github.com -> .3, api.github.com -> .6, codeload -> .9, pkg-containers ->
  185.199.108-111.154. `.packages` of the live `/meta` lists .33/.34 across four /24s. Route
  traceroute not applicable to a policy change.
- **L7 TLS / SNI.** `curl --resolve` matrix above: Packages frontends answer both packages names and
  fail verification for github.com/api.github.com; github.com's IP does not answer ghcr.io. This is
  why an IP-level carve is safe, and why SNI-level discrimination (which nft cannot do) is not needed.
- **L7 application.** Sentry shows the live firewall self-reports: `egress_blocked` 76 events/30 d;
  `enforcement_missing` 297 events (pre-existing, see Deferrals). No GHCR-related event exists, which
  is consistent with the deny being absent today (nothing to report either way).

## Problem Statement

`cron-egress-allowlist-cidr.txt` is `(.git+.api)` from `https://api.github.com/meta` (78 IPv4 ranges).
It admits GHCR's frontends and its blob CDN, so ADR-096's "the container allowlist does not carry
ghcr.io" is true by hostname only. Nothing alerts if a bridge container can reach GHCR, and
docker.pkg.github.com has no deny at any layer.

## Proposed Solution

### Design

```
SOLEUR-EGRESS (unchanged)                      soleur_egress_allow_cidr (the changed DATA)
  ... :8288 accepts                              before:  140.82.112.0/20, 185.199.108.0/22,
  7  @soleur_egress_allow  accept  (by name)              192.30.252.0/22, 78 total
  8  @soleur_egress_allow_cidr accept  <------- after:   the same list MINUS the nine carved
  9  log + default drop                                   Packages frontends (122 prefixes)
```

1. **Generator carve** (`gen-github-egress-cidr.sh`): after the existing `(.git+.api)` extraction,
   compute `holes = .packages IPv4 \ exact(.git ∪ .web ∪ .api)`, then for each hole split every allow
   prefix that contains it into its CIDR remainder (address-exclude, pure bash integer math; a hole that
   wholly contains an allow prefix removes it; an unrelated hole is a no-op). Re-validate every emitted
   prefix with the existing validator and `>= /8` floor. Write one header line per **effective** hole:
   `# Excluded (GitHub Packages frontends, #9275): <cidr>` (comments are ignored by the loader; the
   post-apply assertion, the resolver sampler and the tests read them). The exact-overlap subtraction
   only protects entries that `/meta` lists as the same `/32`; a hole that sits inside a `.git` range
   (all nine today) is carved **by design**, because the measured Packages frontends do not serve
   github.com or api.github.com. What protects a future reassignment is the by-name allow rule that
   precedes the CIDR rule plus the generator's DNS-sanity guard below.
2. **Guards in the generator.** `.packages` missing or not an array -> die (schema change; refuse to
   write a file that silently stops carving). Zero effective holes -> WARN and write (availability over
   containment; the probe pages). DNS sanity: if `getent ahostsv4` for github.com or api.github.com
   **succeeds** and an answer lies inside an effective hole -> die with the distinct message
   `ghcr-carve-would-cut-github`; a failed or absent lookup only WARNs. A die freezes the daily
   refresh (stale file keeps serving), so it is reported by the cron's existing Sentry error heartbeat
   and the runbook gains a "refresh frozen" line. Tests put a `getent` shim first on `PATH` (no
   production-side seam).
3. **Runtime probe** (`cron-egress-resolve.sh`, 1-minute tick; runs when the app container is running,
   the tick is not loader-invoked and a stamp file under `FAILCOUNT_DIR` says the last probe was
   `>= 270 s` ago -- a wall-clock-minute gate is unreliable with `AccuracySec=1min` timer drift). Per
   name in `{ghcr.io, docker.pkg.github.com}`, **sequentially** (worst case 2 x 15 s inside the 120 s
   unit budget):
   `timeout 15 docker exec soleur-web-platform curl -s -o /dev/null --connect-timeout 5 --max-time 8
   --local-port 49100-49199 -w '%{time_namelookup} %{time_connect} %{remote_ip}' https://<name>/`
   (no `--retry`). Verdict (pure function): `time_connect > 0` -> **reached**; `rc == 28` and
   `time_connect == 0` **and** `time_namelookup > 0` -> **held** (a hung resolver also exits 28 with
   `time_connect == 0`, and must not read as held); anything else (DNS 6, docker-exec 125-127, a DNS
   timeout, ...) -> **inconclusive**.
   - reached -> error event `ghcr_deny_lost` every run, with a **static message** (name and IP only in
     `extra`, so every loss groups into one Sentry issue) and extra fields `name`, `remote_ip`,
     `time_connect`, `in_allow_cidr` (a `nft get element` of remote_ip against the live set),
     `file_sha256` (of the installed CIDR file) and `remediation`.
   - inconclusive -> per-name counter `FAILCOUNT_DIR/ghcr_probe.<name>.blind`; at exactly 12 (about an
     hour) one error event `ghcr_deny_probe_blind` with `extra = {name, last_rc, last_namelookup}`;
     held or reached resets it. No event on held (liveness is the tick's existing check-in; the T0
     proof is the apply-time assertion).
   - The `ghcr_probe.` prefix keeps these files clear of the host-named files the resolver removes.
4. **Sampler scope.** The probe's own SYNs reach the logged default drop (the carved IPs are no longer
   allowed). The resolver's `BLOCK_HITS` / `SAMPLE` pipeline drops a kernel line only when **all three**
   hold: `SPT` inside the reserved probe range, `DPT=443`, and `DST` inside a `# Excluded` prefix
   (integer containment in `awk`, not address expansion). The range is defined once
   (`GHCR_PROBE_PORT_LO/HI`) and both the curl flag and the filter derive from it; a test asserts both
   sites reference the constants. A real dial to a carved frontend from any other port, and any other
   drop from a port in the range, stay counted.
5. **Apply-time assertion** (`cron-egress-postapply-assert.sh`): assert the `# Excluded` header exists
   with at least one effective hole; for **every address** of every excluded prefix (a `/31` yields both)
   `nft get element ip filter soleur_egress_allow_cidr { <ip> }` must fail (exact, no network, works on
   a fresh host); and, when the container is running, one live end-to-end probe pinned to the first
   excluded address (`--resolve ghcr.io:443:<ip>`, same verdict function, no port reservation) must not
   connect. Failures: `ASSERT-FAILED: ghcr-carve-header-absent`, `ghcr-carve-live-set <ip>`,
   `ghcr-frontend-reachable <ip>`.
6. **Alert routing.** Widen the `op` filter of `sentry_alert.egress_blocked` to
   `egress_blocked,ghcr_deny_lost,ghcr_deny_probe_blind`. The rule emails ActiveMembers on first-seen /
   reappeared / regression of an issue group, so a loss emails **once per unresolved issue** and marking
   it resolved in Sentry does not mean the deny is back (stated in the runbook). The static messages
   give each op its own issue group, distinct from the long-unresolved `egress_blocked` group, so the
   first-seen trigger fires.
7. **Evidence + decision record**: ADR-096 amendment (scoping table, residuals) and the runbook
   section and corrected coverage recipe. The C4 files are read and edited only if a statement in them
   is falsified.
8. **Census checks** folded into `cron-egress-firewall.test.sh` (no new suite): `GITHUB_EGRESS_DOMAINS`
   equals exactly `github.com` + `api.github.com`; `cron-egress-allowlist.txt` names no GHCR,
   `*.pkg.github.com` or `*.githubusercontent.com` host; a bounded grep over `apps/web-platform/server`
   finds none of those literals (one explicit exemption list, floor on files scanned).

### Residuals (accepted, stated in the ADR amendment)

- `pkg-containers.githubusercontent.com` (185.199.108-111.154) stays reachable; it is a blob CDN that
  needs a ghcr.io token first and shares its frontend with raw/Pages.
- A bridge container can still dial a Packages frontend IP that `/meta` does not list; the probe
  catches DNS-visible drift within ~10 minutes and `ghcr_deny_lost.extra.remote_ip` names it for a
  one-line generator edit.
- The probe reserves source ports 49100-49199 inside the ephemeral range: a drop from that port range
  toward a carved frontend on 443 is not counted by `egress_blocked`. It hides only GHCR dial attempts
  (already denied), never other drops.
- DoH/IP-literal exfiltration to other GitHub-hosted surfaces (any repo, gist) is the pre-existing
  github.com allowance and is out of scope.
- Host processes and `--network host` containers are not governed by DOCKER-USER; their deny is the
  hosts-file mechanism (#9169/#9147).
- docker.pkg.github.com has no **host-level** hosts-file entry until the next registry-host replace.

## Technical Approach

### Architecture

Data-only change to the firewall's allow set plus one observer. The loader, nft rule order, DOCKER-USER
jump, set types, systemd units and Terraform delivery hashes are unchanged in structure; the changed
bytes (generated CIDR file, resolver, post-apply assertion) already sit in
`terraform_data.cron_egress_firewall.triggers_replace` and `local.host_script_files`, so the existing
apply path delivers them (`apply-web-platform-infra.yml` on merge; fresh hosts via the baked scripts).

### Implementation Phases

Order is RED first (`cq-write-failing-tests-before`), then generator, observer, assertion, routing, docs.

#### Phase 1 -- Failing tests (RED)

- 1.1 `scripts/gen-github-egress-cidr.test.sh`: extend the synthesized fixture
  `test-fixtures/github-meta-sample.json` with a `.packages` key (two holes in ONE allow prefix, one
  hole equal to a `.git` `/32`, one hole outside every allow prefix, one `/31`). Oracle for set
  membership is **python3 `ipaddress`** (independent of the bash implementation). Assert: golden body,
  `Excluded` header lines equal the effective holes, no carved IP admitted, every non-carved fixture
  IP still admitted, deterministic re-run no-op, `--check` parity, over-broad floor.
- 1.2 Generator guard rows: `.packages` absent, `.packages` not an array, zero effective holes (WARN,
  exit 0), DNS-sanity die via a `getent` shim first on `PATH` (answer inside a hole -> die; lookup
  failure -> WARN and write).
- 1.3 `cron-egress-firewall.test.sh`: replace the `140.82.112.0/20` literal assertion with a
  containment assertion (github.com/api/codeload IPs admitted, the excluded IPs denied) over the
  committed file; assert the `# Excluded` header; assert the resolver defines the probe functions, the
  two ops, the `GHCR_PROBE_PORT_` constants at both the curl flag and the sampler; add the census
  checks from Design item 8.
- 1.4 Probe verdict and counter: extract `ghcr_probe_verdict` / `ghcr_probe_blind_step` from the
  resolver by `awk` on their definition lines and `source` them (no logic copy); table-driven over
  (rc, time_namelookup, time_connect, prior counter). Seams the tests stub: the state directory (a
  `mktemp -d`), the clock (an argument), `sentry_event` (a recording function). Existing
  `sentry_event` call sites are unchanged (the plan adds no level parameter).
- 1.5 `apps/web-platform/test/sentry-egress-ghcr-deny-alert-op-contract.test.ts` (new, sibling of
  `sentry-image-verify-alert-op-contract.test.ts`): resolver op literals == the rule's filter values,
  scoped to the resource block, whole-line comments stripped; each new op's message literal is static
  (no `$`, no IP, no name interpolation).

#### Phase 2 -- Generator (GREEN)

- 2.1 `carve_one` / `exclude_holes` in `gen-github-egress-cidr.sh` (integer math; the prototype
  validated 2026-10-01 against live `/meta`: 78 in, 122 out, nine effective holes).
- 2.2 `.packages` extraction and exact-overlap subtraction (`comm -23` over `sort -u` of the two
  `jq -r '...|select(test(":")|not)'` lists), header lines, shape and DNS guards.
- 2.2b Run-context check: the Inngest cron spawns the generator inside the app container with a minimal
  env (`PATH`, `HOME`, `NODE_ENV`, `META_JSON_FILE`, `OUT`; `cron-github-cidr-refresh.ts`), so the carve
  must use only bash + jq (both in the image) and the DNS guard must degrade to a WARN when `getent` is
  absent or the lookup fails. The TS test mocks the spawn, so it needs no `.packages` fixture; confirm
  at work time.
- 2.3 Regenerate `cron-egress-allowlist-cidr.txt` with the generator against live `/meta` (never by
  hand); commit it; `--check` must exit 0.
- 2.4 Update the generated-file header text in the generator (`# Snapshot:` count now counts emitted
  prefixes) and keep the verbatim `(.git+.api)` jq line the test pins.

#### Phase 3 -- Probe and sampler in the resolver

- 3.1 `GHCR_PROBE_PORT_LO/HI`, `ghcr_probe_verdict` (pure), `ghcr_probe_blind_step` (counter),
  `run_ghcr_probe` (stamp-file cadence gate, container check, loader-invocation skip, sequential names,
  one `sentry_event` per outcome). Insert after the self-heal block and before the drop-sample block so
  a probe failure cannot skip the existing `sentry_checkin ok`. Avoid `nft ... | grep -q` under
  `pipefail` (SIGPIPE reads as failure; see Deferral 3): capture output into a variable first.
- 3.2 Sampler: filter `BLOCK_HITS` and `SAMPLE` per Design item 4 (all three conditions).
- 3.3 Lint ratchets: `scripts/lint-shell-capture-exit.baseline.txt` and the two
  `lint-shell-trace-credential-refusal*` baselines carry rows for this file; new `$(...)`/`curl`
  constructs must be compliant or get a reviewed baseline row.

#### Phase 4 -- Apply-time assertion

- 4.1 `cron-egress-postapply-assert.sh`: implement Design item 5. The file is a one-line-per-assertion
  script run over the SSH provisioner; review the quoting of the loop against the Phase 2.1 sentinel
  parser in `cron-egress-firewall.test.sh`, and keep the existing LOUD skip for the live probe on a
  fresh host (the `nft get element` checks still run there).
- 4.2 `cron-egress-firewall.test.sh` Phase 2.1 sentinels: add the new assertion names.

#### Phase 5 -- Sentry routing

- 5.1 `infra/sentry/issue-alerts.tf`: `sentry_alert.egress_blocked` filter
  `op in "egress_blocked,ghcr_deny_lost,ghcr_deny_probe_blind"`; extend the block comment (what each op
  means, that `enforcement_missing` is deliberately not added and why). Do **not** rename the resource
  or the live name (`cron-egress-blocked`): a rename is a destroy/create of a live paging rule.
- 5.2 `alert-reference.json`: regenerate from the `sentry-alert-reference-expected-<run>` artifact the
  PR's `apply-sentry-infra.yml` plan run uploads (`gh run download <run> -n
  sentry-alert-reference-expected-<run>`); the `egress_blocked` entry's `op` value changes, no id
  changes. No new rule: README rule count and `frequency_minutes` census stay as they are.

#### Phase 6 -- Decision record and runbook

- 6.1 ADR-096 amendment "2026-10-01 (#9275)": scoping table, the carve, residuals, the corrected status
  line for 5.3b-iii (complete at the bridge layer), the pointer to the split-out issues. Amend the top
  summary bullet that lists #9275 as remaining. ADR stays **Adopting**. No ADR-052 edit (ADR-096 links
  to it).
- 6.2 C4: read all three of `model.c4`, `views.c4`, `spec.c4` and record the enumeration; edit only a
  statement that the change falsifies (none is expected: `webapp -> github` and `engine -> github`
  stay true and no `webapp -> ghcr` edge exists); if an edit is made, run the `c4-code-syntax` /
  `c4-render` tests and `plugins/soleur/test/c4-count-parity.test.sh`.
- 6.3 Runbook `cron-egress-blocked.md`: a section "GHCR carve (#9275)":
  - decode table rows for the two ops and for `ghcr-carve-header-absent`, `ghcr-carve-live-set`,
    `ghcr-frontend-reachable`, `ghcr-carve-would-cut-github` (refresh frozen, stale file keeps serving);
  - how to read events (`scripts/sentry-issue.sh`) and a repair ladder keyed by `extra`: `in_allow_cidr`
    true or a stale `file_sha256` -> trigger `cron/github-cidr-refresh.manual-trigger` or re-apply; an
    IP `/meta` does not list -> a PR adding it to the generator's hole list;
  - "resolved in Sentry is not fixed"; the reserved port range note;
  - replace the `comm -23` recipe with `gen-github-egress-cidr.sh --check` (needs live `/meta`; it is no
    longer an offline recipe).

#### Phase 7 -- Tracking and ship

- 7.1 File the three follow-ups in Deferrals (filing exit: `Mandated-By` lines); append the two
  operator-visible deviations to `specs/<branch>/decision-challenges.md`.
- 7.2 PR body: `Closes #9275`; an explicit line "cloud-init-registry.yml: no change (AC1)"; the
  deviations (the `/22` retained; Better Stack alert split).
- 7.3 CI only (`test-all-affected`); no local full batteries. If `test-affected-kb-consumers` flags the
  KB edits, add a row to `scripts/test-affected-kb-consumers.baseline.txt`.

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| Deny set + new nft rule + `!` lines parsed by the loader (original design) | Rejected (CTO) | Adds a parser, a set, a rule, a self-heal arm and an ordering test to buy what a data subtraction buys; a bad loader change is fail-open on bootstrap. |
| Exclude `185.199.108.0/22` as well | Rejected (CTO) | Collateral on raw/Pages; evidence is a census of our code only; blob CDN is harmless alone. |
| DNS-derived deny set in the resolver | Rejected | Extra resolution path and state; `/meta` already publishes the frontends and refreshes daily. |
| Hand-edit the CIDR file | Rejected | Regenerated daily; `--check` reds. |
| Better Stack Logs alert for the probe | Rejected | Kernel/resolver lines are not shipped; Sentry events already are. |
| New Sentry cron monitor | Rejected | Two-PR rule: cannot be routed in this PR. |
| Reject-connect (`reject with tcp reset`) instead of drop | Rejected | Existing convention is silent drop; the probe discriminates drop by `time_connect == 0`. |

## User-Brand Impact

- **If this lands broken, the user experiences:** Concierge git clone/push and `gh` calls from a
  connected repository failing (a carve that swallows an IP github.com or api.github.com uses), and cron
  heartbeats going missing -- the 2026-06-14 incident shape (`scheduled-ruleset-bypass-audit`).
- **If this leaks, the user's workflow is exposed via:** a compromised agent sandbox or cron in a bridge
  container reaching GHCR (anonymous token endpoint plus layer pulls) as a supply-chain rendezvous or
  exfiltration path. The residual exposure when the deny silently stops holding equals today's state, and
  is detected within ~10 minutes by the probe events.
- **Brand-survival threshold:** `aggregate pattern`.

## Observability

```yaml
liveness_signal:
  what: Sentry cron check-in of the resolver tick (monitor cron-egress-resolve); the probe itself rides that tick and is proven at deploy time by the apply-time assertion (apply workflow green)
  cadence: tick every 1 min; probe when the stamp file is at least 270 s old
  alert_target: operator email via the existing cron-monitor-failure rule (dead tick) and the cron-egress-blocked rule (ghcr_deny_lost, ghcr_deny_probe_blind)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (cron_egress_resolve), apps/web-platform/infra/sentry/issue-alerts.tf (egress_blocked)
error_reporting:
  destination: Sentry web-platform project (store API via SENTRY_INGEST_DOMAIN / SENTRY_PROJECT_ID / SENTRY_PUBLIC_KEY from Doppler prd)
  fail_loud: sentry_event with tags feature=cron-egress-firewall and op in ghcr_deny_lost, ghcr_deny_probe_blind, each with a static message and extra {name, remote_ip, time_connect, in_allow_cidr, file_sha256, remediation} or {name, last_rc, last_namelookup}; the apply-time assertion exits non-zero and fails the apply workflow
failure_modes:
  - mode: a bridge container can connect to ghcr.io or docker.pkg.github.com (stale file, GHCR moved to an unlisted IP, loader not reloaded)
    detection: probe verdict reached -> op=ghcr_deny_lost on every probe run (about every 5 minutes)
    alert_route: cron-egress-blocked Sentry rule -> email ActiveMembers once per unresolved issue group
  - mode: the probe cannot decide (DNS failure or hang, docker exec failing, curl missing) for about an hour
    detection: 12 consecutive inconclusive runs for one name -> op=ghcr_deny_probe_blind once
    alert_route: cron-egress-blocked Sentry rule -> email ActiveMembers
  - mode: the carve would cut an IP github.com or api.github.com resolves to
    detection: the generator refuses to write (ghcr-carve-would-cut-github), so the daily cron reports an error heartbeat and the stale file keeps serving
    alert_route: Sentry cron-github-cidr-refresh monitor -> cron-monitor-failure rule
  - mode: the resolver tick itself is dead (the probe cannot run)
    detection: Sentry missed check-in on cron-egress-resolve
    alert_route: cron-monitor-failure rule -> email ActiveMembers
logs:
  where: journald unit cron-egress-resolve (host); Sentry events are the no-SSH read path
  retention: Sentry plan retention for events; journald default for the unit
discoverability_test:
  command: grep -o ghcr_deny_lost apps/web-platform/infra/sentry/issue-alerts.tf
  expected_output: ghcr_deny_lost
```

## Encryption Posture

```yaml
# No persistent store is introduced: the probe is stateless on disk except a tiny verdict file under
# the existing tmpfs FAILCOUNT_DIR (/run), which holds one word per name and no secret or personal data.
at_rest: []
in_transit:
  - connection: resolver host script -> Sentry ingest (check-in and event POST; existing path, new ops only)
    enforced_at: apps/web-platform/infra/cron-egress-resolve.sh sentry_event / sentry_checkin (https:// URL, curl default verification)
    tls: HTTPS, curl/OpenSSL default minimum (TLS 1.2+)
    cert_verification: on
    does_not_defend: a compromised host holding the Sentry public key can post forged events (the key is a public ingest key by design)
    disclosed_as: not-publicly-claimed
  - connection: app container -> ghcr.io / docker.pkg.github.com (the probe, intentionally dropped by the firewall)
    enforced_at: apps/web-platform/infra/cron-egress-resolve.sh run_ghcr_probe (https:// URL, no -k)
    tls: HTTPS; the expected outcome is that no TCP connection forms
    cert_verification: on
    does_not_defend: nothing is transmitted when the deny holds; when it does not, the request is an unauthenticated GET of the registry root
    disclosed_as: not-publicly-claimed
```

## Guard Contract

### Guard 1 -- carve exactness (generator)

**Property.** For every IPv4 address X, X is in the generated allow list if and only if X is inside a
`.git` or `.api` prefix and X is not inside an effective `.packages` hole.

**Assembly.** The chokepoint is the generator's `exclude_holes` call between extraction and emit
(`gen-github-egress-cidr.sh`); the members are every allow prefix, every hole (from `.packages` minus
exact `.git`/`.web`/`.api` members), and the three consumers of the output: the committed file
(`--check`), the loader (validator parity) and the post-apply assertion (`# Excluded` lines). The
oracle in the test is python3 `ipaddress`, not the bash code under test.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Carve only the first hole (loop `break`s), fixture with two holes inside the SAME `/20` | RED |
| 2 | `exclude_holes` becomes a no-op while the header still prints `Excluded` (reports 0 carved, exits 0) | RED |
| 3 | Stop subtracting exact `.git`/`.web`/`.api` members (carves a `20.217.135.1/32`-shaped overlap) | RED |
| 4 | Keep an allow prefix that a wider hole wholly contains, or emit a remainder wider than its parent (halving off-by-one) | RED (python oracle) |
| 5 | Drop the `.packages` shape guard (missing key yields an uncarved file, exit 0) | RED |
| 6 | Drop the DNS-sanity die (a `getent` shim answers an IP inside a hole and the file is still written), or make a failed lookup die | RED |
| 7 | Harness: delete the python oracle call so the membership loop iterates zero fixture IPs | RED (instrument floor on IPs checked) |
| 8 | Must-PASS non-canonical: a fixture whose only hole is outside every allow prefix | PASS, body equals the plain allow set, no `Excluded` line |

**Anchor.** A repo-only consistency check proves the file matches the generator, not that the network
admits or blocks anything: an edit that weakens the generator and regenerates the file passes
`--check`. The anchor outside the commit is live behaviour: the apply-time `nft get element` +
end-to-end probe and the periodic probe (Guard 2), which a code change cannot satisfy by editing both
sides.

### Guard 2 -- the probe (verdict, counter, dispatch, sampler)

**Property.** If a bridge container can complete a TCP handshake to ghcr.io or docker.pkg.github.com,
an error event with `op=ghcr_deny_lost` is emitted on the next probe run (about 5 minutes), and if the
probe cannot decide for an hour, `ghcr_deny_probe_blind` is; the probe's own drops never inflate
`egress_blocked`.

**Assembly.** `ghcr_probe_verdict` (pure), `ghcr_probe_blind_step` (counter), `run_ghcr_probe`
(dispatch: container check, stamp-file cadence gate, both names, event emission), the sampler filter,
and the Sentry rule filter that must route the two error ops. The chokepoint is `run_ghcr_probe`; two
names flow through it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Verdict treats `rc == 28` and `time_connect == 0` as held without requiring `time_namelookup > 0` (hung resolver reads as held) | RED |
| 2 | Dispatch skips the second name (`docker.pkg.github.com`) after a compliant first | RED |
| 3 | Dispatch never runs (cadence gate always false) or runs every tick (gate always true) | RED |
| 4 | `reached` no longer emits `ghcr_deny_lost`, or the message interpolates the IP (new issue per probe) | RED |
| 5 | The 12th inconclusive run does not emit `ghcr_deny_probe_blind`, or emits at every run | RED |
| 6 | The sampler stops excluding the probe's drops, or widens to every drop in the port range regardless of `DST` / `DPT` | RED (two sub-mutations) |
| 7 | The Sentry filter loses one of the two error ops | RED (op-contract test) |
| 8 | Harness: the table runner iterates zero rows | RED (instrument floor on row count) |
| 9 | Must-PASS non-canonical: `rc=28 namelookup=0.012 connect=0.000000` with prior counter 7 | held, counter reset |
| 10 | Sequence: counter 11 then `reached` (must print lost once and reset the counter) | one `lost`, counter 0 |

**Anchor.** The verdict depends on observed network behaviour, not on any stored value.

### Guard 3 -- census (nothing in a bridge container needs GHCR)

**Property.** No sandbox domain list and no by-name allowlist entry names ghcr.io, `*.pkg.github.com`
or `*.githubusercontent.com`, and `apps/web-platform/server` carries no such literal outside an explicit
exemption list.

**Assembly.** `GITHUB_EGRESS_DOMAINS` in `server/agent-runner-sandbox-config.ts`,
`cron-egress-allowlist.txt`, and the `apps/web-platform/server` tree (asserted inside
`cron-egress-firewall.test.sh`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `https://ghcr.io/v2/` to a server `.ts` file | RED |
| 2 | Add `raw.githubusercontent.com` to `GITHUB_EGRESS_DOMAINS` after the two compliant entries | RED |
| 3 | Add `ghcr.io` to `cron-egress-allowlist.txt` after a compliant `github.com` | RED |
| 4 | Point the server scan at an empty directory (scans zero files) | RED (floor on files scanned) |
| 5 | Must-PASS non-canonical: the OIDC issuer string `token.actions.githubusercontent.com` in a script outside the scanned tree | PASS |

**Anchor.** The census is advisory evidence for P5; the runtime probe remains the control.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-096 in place ("Amendment 2026-10-01 (#9275)", no new ordinal): the decision (carve Packages
frontends out of the generated container-egress allow list; keep the `/22`), the scoping table, the
residuals, status of 5.3b-iii, and the pointer to the split-out follow-ups. The ADR write is a task of
this plan (Phase 6.1), not a deferred issue.

### C4 views

All three of `model.c4`, `views.c4`, `spec.c4` are read in Phase 6.2. Enumeration checked against the
model: external human actors -- none added; external systems -- `github` (modeled; edges
`webapp -> github`, `engine -> github` stay true) and `ghcr` (modeled; no `webapp -> ghcr` edge exists
and none is needed); containers/data stores -- no new store; access relationships -- none changes (a
deny removes a reachability that was never modeled as an edge). Edit a description only if it is
falsified. Derived cardinalities: no cron monitor, alert rule or function is added, so
`c4-count-parity` should not move.

### Sequencing

Complete at the bridge layer when this merges; the ADR stays Adopting until 5.6.

## Infrastructure (IaC)

### Terraform changes

No new resource. `sentry_alert.egress_blocked` filter value changes in `infra/sentry/issue-alerts.tf`.
The firewall files change content only; `terraform_data.cron_egress_firewall.triggers_replace` already
hashes the CIDR file, resolver and post-apply assertion. No new variables or secrets.

### Apply path

(b) existing delivery: `apply-web-platform-infra.yml` re-runs the provisioner on merge (web-1), the
baked scripts carry it to fresh hosts, and `apply-sentry-infra.yml` applies the filter. No SSH step is
authored by this plan; the provisioner's remote-exec is the repo's existing mechanism. Blast radius:
the loader restart re-installs the same rules atomically (no egress gap, per the existing ordering).

### Distinctness / drift safeguards

The generator `--check` mode and the apply-time assertion; `egress_blocked` keeps
`ignore_changes = [environment]`. The Inngest refresh cron continues to regenerate (with the carve) and
direct-merge; the probe is the guard against a bad regeneration.

### Vendor-tier reality check

Sentry event ingest and issue alerts are on the existing plan; no tier gate involved.

## Acceptance Criteria

### Functional Requirements

- [ ] AC1: `git diff --quiet origin/main...HEAD -- apps/web-platform/infra/cloud-init-registry.yml` exits 0 (merge-base form, so a sibling merge touching the file cannot redden it), and the diff touches no other file whose bytes feed `hcloud_server.registry.user_data` (check the `templatefile(` call for `hcloud_server.registry` and diff each input the same way).
- [ ] AC2: `bash apps/web-platform/infra/scripts/gen-github-egress-cidr.sh --check` exits 0 against live `/meta`, and the committed file carries one `# Excluded (GitHub Packages frontends, #9275):` line per effective hole (nine today).
- [ ] AC3: a containment check over the committed file (python3 `ipaddress`) admits 140.82.121.3, .6, .9, 140.82.112.3, 192.30.255.112 and 185.199.108.154, and denies every `# Excluded` address (today `140.82.{112,113,114,121}.{33,34}` and `192.30.255.164/165`).
- [ ] AC4: `cron-egress-resolve.sh` defines `ghcr_probe_verdict`, `ghcr_probe_blind_step`, `run_ghcr_probe`; the table test passes for held / reached / inconclusive (including a hung-resolver row) / blind-at-12 / reset-on-held / reset-on-reached.
- [ ] AC5: `sentry_alert.egress_blocked` filters `op in "egress_blocked,ghcr_deny_lost,ghcr_deny_probe_blind"`; the op-contract test passes (including static message literals); `alert-reference.json` matches the CI-expected artifact.
- [ ] AC6: `cron-egress-postapply-assert.sh` fails when any excluded address is present in the live `soleur_egress_allow_cidr` set or the live probe connects (mutation rows prove both).
- [ ] AC7: the sampler excludes only drops matching SPT range + DPT 443 + DST in an excluded prefix (mutation rows prove each of the three conjuncts is required).
- [ ] AC8: ADR-096 amendment exists; the runbook section exists and the `comm -23` recipe is replaced.
- [ ] AC9: three follow-up issues exist (Deferrals) with `Mandated-By` lines and a milestone.

### Non-Functional Requirements

- [ ] A probe run adds at most 30 s (two sequential `timeout 15` probes) to one tick in about five; the tick stays under `TimeoutStartSec=120` and the `flock -w 120` budget.
- [ ] Generator is pure bash + jq (no python in the container); python3 appears only in tests.
- [ ] No `ghcr.io/jikig-ai` literal anywhere in baked host scripts (G1 census stays green).
- [ ] NFR register assessment run (`soleur:architecture assess`).

### Quality Gates

- [ ] CI green: `cron-egress-firewall.test.sh`, `gen-github-egress-cidr.test.sh`, `cloud-init-ghcr-seed-login.test.sh`, `web-ghcr-deny.test.sh`, the Sentry op-contract and routing-parity tests, `c4-count-parity`, shell lint ratchets.
- [ ] Admin merge only after CI is green **and** the operator is asked again (non-docs diff).

### Post-merge (automated, no SSH)

Everything above is pre-merge. These run after the merge, by `soleur:ship`/`soleur:postmerge`, with
the repo's own tooling (no operator step; automation-feasibility gate: Sentry and workflow reads are
API calls, the apply is a push-triggered workflow):

- [ ] The single workflow that applies `terraform_data.cron_egress_firewall` (verified 2026-10-01: `git grep -n cron_egress_firewall -- .github/workflows` -> `apply-web-platform-infra.yml:1174` only) finished green; its post-apply assertion (all-IP probe) is the T0 proof. Sort runs explicitly when selecting it (`gh run list` order is not relied on).
- [ ] `doppler run -p soleur -c prd -- scripts/sentry-issue.sh` over `feature:cron-egress-firewall op:ghcr_deny_lost` / `op:ghcr_deny_probe_blind` shows no event over the 24 h following the apply (absence is read with the apply-time assertion as the positive control, and the `cron-egress-resolve` check-ins as tick liveness).
- [ ] `apply-sentry-infra.yml` finished green for the filter change.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Challenged the original deny-set design and replaced it with the generator carve
(simpler, fails safe, no loader change). Rejected excluding `185.199.108.0/22` (collateral on raw/Pages;
no runtime proof). Required: generator DNS-sanity guard, probe treats "no result" as blind, split the
Better Stack alert out, do not route `enforcement_missing` without measuring its volume (measured:
297 events, ~15/day -> not routed). All applied.

Plan review (DHH, Kieran, code-simplicity per mechanism, CTO devex lens; threshold `aggregate pattern`
so no architecture-strategist / spec-flow): all findings were Mechanical and applied -- cut the held
event and 3-state machine, the `EXTRA_PACKAGES_FRONTENDS` knob, parallel jobs, the separate census suite,
the ADR-052 / C4 / allowlist-comment edits; changed the post-apply check to an exact `nft get element`
per address plus one live probe; scoped the sampler filter to three conjuncts; added the
`time_namelookup` guard, the stamp-file cadence gate, static Sentry messages and richer `extra`
diagnostics. Two deviations from the brief are recorded in `decision-challenges.md` for `ship`.

No product, legal, marketing, finance, sales or support implications: no user-facing surface, no
personal data, no vendor or cost change.

## Open Code-Review Overlap

None (open `code-review` issues queried 2026-10-01 against every path in Files to Edit / Create).

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given a fixture `/meta` with `.packages` holes inside a `/20`, when the generator runs, then the body
  is the python-oracle set difference and each effective hole has an `Excluded` header line.
- Given verdict inputs (rc=28, namelookup=0.012, connect=0), then `held`; (rc=28, namelookup=0,
  connect=0), then `inconclusive`; (rc=0, connect=0.021), then `reached`; (rc=6), then `inconclusive`;
  and twelve consecutive inconclusive runs emit `blind` exactly once.
- Given a Sentry filter missing `ghcr_deny_lost`, the op-contract test fails.

### Regression Tests

- The `140.82.112.0/20` literal assertion is replaced, not deleted: github.com's IP stays admitted.
- Probe drops do not inflate `egress_blocked` events; a real drop to a carved frontend from another port
  is still counted.

### Edge Cases

- Hole equal to an exact `.git` `/32` (20.217.135.1 shape): not carved.
- Hole wider than an allow prefix: the prefix disappears.
- `.packages` empty or absent: generator dies; zero effective holes: WARN, file written.
- Container absent at the probe slot: skip, stamp file and counters unchanged.
- DNS resolves github.com into a hole: generator refuses to write; a failed lookup only warns.
- A `/31` hole: both addresses are checked at apply time.

### Integration Verification (for `soleur:qa`)

- **Apply log:** `gh run view <apply-web-platform-infra run> --log | grep -E "ghcr-carve|ghcr-frontend|egress-probe"` shows the assertions ran and passed.
- **Sentry read:** `doppler run -p soleur -c prd -- scripts/sentry-issue.sh` over `feature:cron-egress-firewall op:ghcr_deny_lost` returns no event after the apply.

## Deferrals (tracking issues, filed in Phase 7.1)

1. **Host hosts-file deny for docker.pkg.github.com** -- byte change in `cloud-init-registry.yml`
   (copy R), `cloud-init.yml` (copy A), `server.tf` `local.ghcr_deny_sh` (copy B), `web-ghcr-deny.test.sh`,
   `zot-image-fetch.test.sh`; trigger: the next planned registry-host replace (ADR-169
   `registry-host-replace-dispatch`). Milestone from `knowledge-base/product/roadmap.md`.
2. **Better Stack Logs alert on `ghcr_blocked=0`** (SOLEUR_ZOT_DISK heartbeat head field and the
   `GHCR_DENY` ci-deploy row), sibling of `registry_store_not_luks`; ADR-218 recipe.
3. **`op=enforcement_missing` is unrouted and fires ~15/day** (297 events, unresolved since
   2026-06-11). Candidate cause to test first: the self-heal check is `nft list chain ... | grep -q`
   under `set -o pipefail`; `grep -q` exits early, `nft` takes SIGPIPE, the pipeline returns 141 and the
   `!` reads it as "rule missing", re-running the loader needlessly. Either that or a real chain flap on
   deploys; investigate before routing. Found while scoping this plan.

Not fixed here (per the brief): #9373.

## Risks and Mitigations

- **R1 -- carve swallows a needed IP.** Mitigation: exact-overlap subtraction, generator DNS-sanity
  guard, by-name allow precedence, Guard 1 oracle tests, apply-time checks.
- **R2 -- the probe's own SYNs reach the default-drop log and flood `egress_blocked`.** Carved IPs fall
  through to the logged default drop. Mitigation: the three-conjunct sampler filter on a reserved source
  port range defined once (Design item 4), Guard 2 row 6. Not taken: a loader rule that drops the carved
  set silently (a loader change, which the carve design avoids). Residual stated under Residuals.
- **R3 -- daily direct-merge regeneration changes the file unreviewed.** Mitigation: the probe, the DNS
  guard, and the cron's Sentry error heartbeat when the generator refuses to write.
- **R4 -- the DNS guard freezes the daily refresh.** A die leaves the stale file serving while GitHub's
  LB pool may rotate (the 2026-06 incident class). Mitigation: distinct message, error heartbeat on the
  existing monitor, a runbook "refresh frozen" line; die only when a lookup succeeds and lands in a hole.
- **R5 -- docker exec into the prod container every ~5 minutes.** Mitigation: precedent in
  `cron-egress-postapply-assert.sh` and `cron-egress-enforce-probe.sh`; `timeout 15`; two sequential
  probes at most 30 s inside the 120 s unit budget; skip when the container is absent.
- **R6 -- stale-premise drift between plan and work.** `/meta` rotates; the implementer regenerates the
  file live and re-derives the carve; do not paste the plan's numbers into the file.
- **R7 -- merge conflicts** with #9352 / #9376 on `issue-alerts.tf` and `alert-reference.json`.

## Files to Edit

- `apps/web-platform/infra/scripts/gen-github-egress-cidr.sh`
- `apps/web-platform/infra/scripts/gen-github-egress-cidr.test.sh`
- `apps/web-platform/infra/test-fixtures/github-meta-sample.json`
- `apps/web-platform/infra/cron-egress-allowlist-cidr.txt` (regenerated)
- `apps/web-platform/infra/cron-egress-resolve.sh`
- `apps/web-platform/infra/cron-egress-postapply-assert.sh`
- `apps/web-platform/infra/cron-egress-firewall.test.sh`
- `apps/web-platform/infra/sentry/issue-alerts.tf`
- `apps/web-platform/infra/sentry/alert-reference.json`
- `scripts/lint-shell-capture-exit.baseline.txt`, `scripts/lint-shell-trace-credential-refusal.baseline.txt`, `scripts/lint-shell-trace-credential-refusal-d.baseline.txt` (only if the new code needs reviewed rows)
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`
- `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4` (only if a statement is falsified; then also the derived `model.likec4.json` if the repo regenerates it)
- `scripts/test-affected-kb-consumers.baseline.txt` (only if the ratchet false-positives)

## Files to Create

- `apps/web-platform/test/sentry-egress-ghcr-deny-alert-op-contract.test.ts`
- `knowledge-base/project/specs/feat-one-shot-9275-ghcr-bridge-egress/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-9275-ghcr-bridge-egress/decision-challenges.md`

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. This one declares `aggregate pattern`.
- `check-deploy-script-parity.sh` calls doppler itself; this PR does not touch `ci-deploy.sh`, but if a
  change there becomes necessary do not wrap that script in `doppler run`.
- Local typecheck against the main checkout's stale `node_modules` fails spuriously; the only TS file
  is the op-contract test, so rely on CI.
- `web-fresh-boot-zot-8651.sh` assumes `gh run list` is newest-first; relevant only if the post-merge
  verification reads workflow runs: sort explicitly.
- Never `pkill -f`; if a stuck test runner must be stopped, `source plugins/soleur/scripts/lib/proc.sh`
  and use `kill_mine`.
- The carve count (9 / 122) is a 2026-10-01 measurement, not a constant: tests assert structure and the
  oracle relation, never those numbers.
- `egress_blocked` keeps its resource label and live name; editing the `op` value is an in-place update,
  renaming is destroy/create.
- A `ghcr.io/jikig-ai` literal in any baked host script reds the G1 census; use `https://ghcr.io/` only.
- If the scope grows a new Sentry rule, re-derive the unused `frequency_minutes` set from
  `grep -h frequency_minutes infra/sentry/*.tf` on a fresh `origin/main` immediately before merge.
