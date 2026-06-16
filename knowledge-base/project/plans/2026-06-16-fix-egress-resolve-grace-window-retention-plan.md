---
title: "fix: egress resolver grace-window IP retention (rotation-proof LB hosts)"
type: fix
date: 2026-06-16
lane: single-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# fix: egress resolver grace-window IP retention (rotation-proof LB hosts)

## Enhancement Summary

**Deepened on:** 2026-06-16
**Sections enhanced:** Proposed Solution, Technical Approach, Hypotheses,
User-Brand Impact, Acceptance Criteria, Test Scenarios, Sharp Edges.
**Research agents used:** security-sentinel (egress-boundary review),
Explore (L3→L7 network-outage deep-dive + bash strict-mode realism pass).

### Key Improvements

1. **Three-way operation decomposition (record / union / evict) made explicit
   and load-bearing.** Security review (P2-3) caught that "additive-only on a
   no-prune tick" could be mis-implemented to skip the timestamp WRITE, which
   would age IPs toward a burst eviction on the next clean tick and silently
   re-open the outage. Record + union now run on EVERY tick; only eviction is
   gated on `FAILED_HOSTS == 0`. New AC + test arm.
2. **Store readback re-filters through the IPv4 regex** (defense-in-depth,
   P2-2) so a stray/corrupt store file can never inject a non-IP token into the
   `nft -f` batch — mirrors `current_set`'s re-grep at `:219`.
3. **Bash strict-mode hazards enumerated with the exact guard each needs**
   (`cat … || echo 0` + numeric guard; `find`/`nullglob` empty-dir sweep;
   `|| true` on union pipes) — the resolver runs under `set -euo pipefail`.
4. **Reassignment-exposure delta named honestly** (P2-1): the fix LENGTHENS the
   reassignment window from ~1 min to ~24h — a quantitative extension of
   ADR-052's accepted CDN shared-IP residual, bounded to single-user-incident.

### New Considerations Discovered

- The L3 checklist's `hcloud firewall describe` artifact targets SSH-*ingress*
  admin-IP drift, NOT container *egress* coverage; the authoritative egress
  artifact is the kernel `egress-blocked: DST=` line via Sentry (present).
- Security review verdict: APPROVE, no P0/P1 — the boundary is structurally
  preserved (bare `ipv4_addr` set cannot hold a CIDR; store fed only from the
  `:183` IPv4 filter).

## Overview

`cron-egress-resolve.sh` rebuilds the nftables single-IP allow set
(`@soleur_egress_allow`) every minute from a single-tick `getent ahostsv4`
resolution of the ~23 allowlisted hostnames (host view ∪ container view),
then **additively-adds + prunes-to-the-current-tick's-IPs** in one atomic
`nft -f` transaction. For single-IP hosts this is correct. For
**load-balancer-fronted hosts** (Cloudflare, AWS, Google-LB) the host rotates
the container across a large anycast/round-robin pool; a single tick's DNS
answer pins only the few IPs returned this minute, and the prune evicts every
IP the *previous* tick saw. A container `connect()` to a freshly-rotated IP
that DNS has not returned in the current 1-minute window is **default-dropped**
by the `SOLEUR-EGRESS` chain — even though the hostname is already trusted.

This is the IP-coverage gap behind the multi-day outage of the heavy
Claude-eval cron cohort (cron-community-monitor, cron-content-generator,
cron-follow-through, cron-bug-fixer, cron-roadmap-review, cron-agent-native-audit).
Their long, network-heavy critical path hits one dropped connection mid-flight
and never reaches its Sentry heartbeat → a **missed** (not failed) cron
check-in — the exact firewall-drop signature.

**Fix:** change the resolver so the allow set **retains every IPv4 it has
observed for an allowlisted hostname over a rolling grace window (~24h)**
instead of pruning to the current tick. A per-IP last-seen timestamp store
persists across ticks; the union accumulates each host's full rotation pool;
an IP is evicted **only after it has been absent from every host's resolution
for the full grace window**. This stays tightly scoped (only IPs DNS returned
for an already-trusted host) while being rotation-proof — without
wholesale-allowlisting any provider CIDR range.

## Problem Statement / Motivation

**Confirmed root cause (diagnosed read-only from prod Sentry + nftables config,
2026-06-16):** Sentry issue `egress-blocked: container egress denied` (654 hits,
still firing 2026-06-16 10:47). Blocked `DST` IPs map to:

- Cloudflare `104.18.x` — fronts `api.linkedin.com` / `api.x.com` /
  `discord.com` / `api.resend.com`
- AWS `198.137.150.x` / `198.202.176.231` / `64.239.109.193` — fronts
  `bsky.social` / `api.buttondown.com` / `edge.api.flagsmith.com`
- Google-LB `34.149.66.137` — fronts `hn.algolia.com` (read by
  cron-community-monitor)

Every blocked IP fronts a host **already in `cron-egress-allowlist.txt`**. This
is an IP-coverage gap, not a hostname gap.

This is the **same failure class** as the 2026-06-14 GitHub CIDR learning
(`knowledge-base/project/learnings/bug-fixes/2026-06-14-github-egress-cidr-must-cover-full-meta-not-just-big-blocks.md`):
"for an LB host on a default-drop egress firewall, the single-IP resolver is
the wrong layer." GitHub was fixed with a **bounded, GitHub-owned `/meta` CIDR
file** because GitHub publishes its full IP pool. That approach does **NOT**
generalize to Cloudflare/AWS/Google: those providers' published ranges are
enormous shared clouds, and allowlisting them wholesale would let a compromised
cron egress to any site on those clouds — defeating ADR-052's default-drop.

ADR-052 §4 already anticipated this exact race: *"the IP-rotation race is
fail-loud/self-correcting (block → Sentry `egress_blocked` + missed heartbeat).
**Escalate to a proxy only on observed production churn.**"* We now HAVE the
observed production churn (654 hits, multi-day outage). Resolve-and-retain is
the lighter-weight escalation that stays inside ADR-052's design envelope
(per-tick re-resolve, host∪container view, atomic additive-then-prune) — it is
NOT the SNI proxy the ADR rejected as a SPOF, and NOT the wholesale-CIDR the
hard constraint forbids.

## Proposed Solution

In `cron-egress-resolve.sh`, between resolving the current tick's IPs and
building the nft batch, the logic decomposes into THREE independently-gated
operations (the decomposition is load-bearing — see Sharp Edges "record vs.
evict on a no-prune tick"):

1. **Record/refresh per-IP last-seen — ALWAYS (additive, every tick).** For
   every IPv4 in this tick's `DESIRED_ALLOW` (the host-view ∪ container-view
   union, already filtered to valid IPv4 + deduped at L183), write/update a
   last-seen epoch timestamp keyed by IP. Store under a
   **`StateDirectory`-backed `/var/lib`** path so the accumulated rotation pool
   survives a host reboot (see Technical Considerations — `/run` vs `/var/lib`).
   This MUST run on EVERY tick including a `no-prune` (partial-failure) tick:
   it only keeps IPs alive longer, never deletes — suppressing it would let IPs
   age toward eviction during a run of partial-failure ticks and then evict in a
   burst on the first clean tick, silently re-opening the outage.
2. **Union stored-fresh IPs into the retained set — ALWAYS (additive).** The
   set fed to `build_batch` for `@soleur_egress_allow` becomes `current-tick IPs
   ∪ {stored IPs whose last-seen is within the grace window}`. On store readback,
   **re-apply the `^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$` IPv4 filter** before
   unioning (defense-in-depth — mirrors `current_set`'s re-grep of nft's own
   output at `:219`; a stray/corrupt/future-written store file can then never
   inject a non-IP token into the `nft -f` batch).
3. **Evict — ONLY on a prune tick (`FAILED_HOSTS == 0`).** An IP is dropped from
   the store (and thereby prunable from the set) only when
   `now - last_seen > GRACE_WINDOW_SECS`. Because the store is keyed by IP across
   ALL hosts, an IP still returned for *any* allowlisted host keeps its timestamp
   fresh — eviction requires absence from every host for the whole window.
   Eviction is structurally a DELETE, so it is gated on the SAME
   `FAILED_HOSTS`/`PRUNE` flag as the existing set-prune (a partial-resolution
   tick must not evict an IP that is "stale" only because the host that would
   have refreshed it failed to resolve this tick).
4. **Preserve every existing invariant unchanged:**
   - Atomic additive-then-prune in ONE `nft -f` transaction (the
     `build_batch` → single `nft -f -` path is untouched; only the *desired*
     set fed to it changes).
   - Fail-safe-on-empty: if this tick resolves ZERO addresses, still abort
     before touching the sets (the store is only *read* to augment a non-empty
     tick, never the sole source).
   - Additive-only on partial resolution failure: the `PRUNE="no-prune"` flip
     when `FAILED_HOSTS > 0` still suppresses ALL deletes (grace-window
     eviction is itself a delete and MUST also be suppressed on a no-prune tick
     — see Sharp Edges).
   - The `8.8.8.8`/`8.8.4.4` DNS pin union (`@soleur_egress_dns`) is a SEPARATE
     set and is NOT subject to grace-window retention — left exactly as-is.
   - The DOCKER-USER jump / default-drop self-heal block is untouched.
5. **GitHub CIDR machinery untouched.** `cron-egress-allowlist-cidr.txt`,
   `scripts/gen-github-egress-cidr.sh`, `scripts/gen-github-egress-cidr.test.sh`,
   the `cron-github-cidr-refresh` Inngest cron, and the `soleur_egress_allow_cidr`
   interval set in the loader all stay exactly as-is — GitHub coverage has ZERO
   gap today and is a different (host-published-CIDR) layer.

## Technical Approach

### Architecture

The retained set is an in-process computation; the only persisted artifact is a
flat per-IP last-seen store. The nft enforcement path does not change at all —
`cron-egress-nftables.sh:151` (`ip daddr @soleur_egress_allow accept`) accepts
any IP in the set; the resolver simply keeps more (still-trusted) IPs in it.

**Store shape (chosen for crash-safety + simplicity, matching the existing
`FAILCOUNT_DIR` one-file-per-key pattern at `cron-egress-resolve.sh:48,168-179`):**

```text
$SEEN_DIR/<ip>           # file content = last-seen epoch seconds
                          # e.g. /var/lib/cron-egress-resolve/seen/104.18.7.42
```

One file per IP mirrors the established `FAILCOUNT_DIR/$host` convention,
avoids a read-modify-write race on a single index file under `flock`
(belt-and-braces — the resolver already serializes via `flock -w 120`), and
makes eviction a trivial `find -mmin +N -delete`-class sweep OR an explicit
mtime/content comparison. Implementation MUST decide between mtime-driven
(`find` on file mtime) and content-driven (epoch written into the file) and pin
ONE; content-driven is recommended because `terraform`/`scp`/`tar` redelivery
can rewrite mtimes, whereas the resolver controls the file content. (Resolve at
/work; both are viable — the test must match whichever ships.)

### Bash strict-mode hazards (`set -euo pipefail`, resolver L38) — REQUIRED guards

The resolver runs under `set -euo pipefail`. The new code MUST mirror the
existing resolver's strict-mode-safe idioms (each unguarded form aborts the
whole tick):

- **Timestamp read.** `cat "$seen_file"` on a missing/empty/corrupt file exits
  non-zero (abort) or feeds non-numeric content into `$(( ))` (abort). Mirror
  the proven FAILCOUNT idiom at `:169`
  (`fc="$(( $(cat "$fc_file" 2>/dev/null || echo 0) + 1 ))"`):
  `ts="$(cat "$seen_file" 2>/dev/null || echo 0)"; [[ "$ts" =~ ^[0-9]+$ ]] || ts=0`
  before any arithmetic comparison.
- **Eviction sweep over `$SEEN_DIR`.** A bare `for f in "$SEEN_DIR"/*` yields the
  literal `"$SEEN_DIR/*"` string when the dir is empty. Use
  `find "$SEEN_DIR" -type f …` (no loop — safe on empty dir), OR
  `shopt -s nullglob` before the glob, OR a `[[ -f "$f" ]] || continue` guard
  inside the loop.
- **Union pipes.** Any `comm`/`sort -u`/`grep -E`/`paste` pipeline that may emit
  empty output carries the trailing `|| true` exactly as the existing
  `DESIRED_ALLOW` build at `:183`
  (`… | grep -E '^[0-9]+\.…$' | sort -u || true`), so an empty retained-set
  union does not trip `set -e`.

### Grace window constant

```bash
# Retain an observed IP for an allowlisted host for this long after its LAST
# sighting in ANY host's resolution. 24h comfortably spans the longest cron
# critical path + the widest observed LB rotation period; eviction after the
# window keeps the set from growing unbounded on genuinely-dead IPs.
GRACE_WINDOW_SECS="${GRACE_WINDOW_SECS:-86400}"   # 24h
SEEN_DIR="${SEEN_DIR:-/var/lib/cron-egress-resolve/seen}"
```

Both overridable via env so the drift-guard test can drive a tiny window
deterministically (e.g. `GRACE_WINDOW_SECS=2` to prove eviction) without
sleeping 24h.

### `/run` vs `/var/lib` (load-bearing design decision)

The existing `FAILCOUNT_DIR` lives in `/run` (tmpfs, cleared on reboot), which
is correct for failcount because a reboot re-runs the loader → fresh resolve →
failcount legitimately resets. The grace-window store is **different**: its
entire purpose is to accumulate an LB host's rotation pool over many ticks
(hours). A reboot wiping the store re-opens the exact outage window this fix
closes, for up to one grace-window after every boot. The host is long-lived and
reboots are rare, but `/var/lib` (persistent) is strictly better and costs one
line. **Decision: persist under `/var/lib` via `StateDirectory=`** on
`cron-egress-resolve.service` (systemd creates `/var/lib/cron-egress-resolve`
with correct ownership; survives reboot; is NOT tmpfs). The lock + failcount
stay in `/run` (their reboot-reset semantics are correct).

### Files to Edit

- **`apps/web-platform/infra/cron-egress-resolve.sh`** — add `GRACE_WINDOW_SECS`
  + `SEEN_DIR` constants; `mkdir -p "$SEEN_DIR"` next to the existing
  `mkdir -p "$FAILCOUNT_DIR"` (L111); after `DESIRED_ALLOW` is finalized
  (L183) and the fail-safe-on-empty guard (L186), insert the
  record-then-retain block that (a) stamps each current-tick IP **(always)**,
  (b) unions in stored-and-still-fresh IPs **(always, re-filtering each value
  through the `^[0-9]+\.…$` IPv4 regex on readback)**, and (c) evicts store
  entries past the window **only on a `prune` tick** (`FAILED_HOSTS == 0`). All
  new bash strict-mode-safe per the "Bash strict-mode hazards" section
  (`cat … || echo 0` + numeric guard; `find`/`nullglob` sweep; `|| true` on
  union pipes). The retained set becomes the `desired` arg to
  `build_batch "$ALLOW_SET" …` (L242). The DNS set branch (L243) is untouched.
  Log line (L293) extended with retained-count.
- **`apps/web-platform/infra/cron-egress-resolve.service`** — add
  `StateDirectory=cron-egress-resolve` under `[Service]`. (Auto-redelivered:
  `server.tf:732` folds this file's hash into `config_hash`, and
  `server.tf:49` base64-embeds it into cloud-init — both from the SAME source
  file, so editing it once propagates to both apply paths. No separate cloud-init
  edit.)
- **`apps/web-platform/infra/cron-egress-firewall.test.sh`** — add resolver
  drift-guards for the new behavior (see Test Scenarios) in the
  `-- resolver safety invariants --` section (L295-317), plus a behavioral
  retention/eviction test exercising the record-then-retain logic against a
  tiny `GRACE_WINDOW_SECS`. Update the comment at L295-303 to note the new
  invariant.
- **`knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`** —
  add a short "Remediation (LB-rotation IP-coverage gap, non-GitHub)" subsection
  documenting that for Cloudflare/AWS/Google-LB hosts the fix is the
  grace-window retention (now automatic) and that a *recurring* drop for an
  already-allowlisted LB host after this lands means the grace window is too
  short OR the store was wiped (reboot with `/run` — should be `/var/lib`); and
  note `cron-egress-resolve` carries a new `retained` count in its OK log.

### Files to Create

- None. (The store directory is created at runtime via `StateDirectory=` +
  `mkdir -p`; no new committed artifact.)

### No-change confirmation (verified at plan time)

- `cron-egress-nftables.sh` — NOT edited. `@soleur_egress_allow` is consumed by
  a plain accept rule (`:151`); retained IPs need no enforcement change.
- `cron-egress-allowlist.txt` / `-cidr.txt` — NOT edited. No new host, no new
  CIDR; the host count guard (test `==23`) and CIDR floor guard stay.
- `gen-github-egress-cidr.sh` / `.test.sh` / `cron-github-cidr-refresh.ts` —
  NOT edited (zero GitHub gap today; explicitly out of scope per the hard
  constraint).
- `server.tf` provisioner/`config_hash` block — NOT edited (it already folds
  both the resolver script and the service unit by file hash; the edits above
  re-provision automatically).
- `cloud-init.yml` — NOT edited (it reads the resolver + service via
  `${cron_egress_resolve_script_b64}` / `${cron_egress_resolve_service_b64}`
  template vars sourced from the same files; `StateDirectory=` rides along).

## Research Reconciliation — Spec vs. Codebase

| Issue assumption | Codebase reality (verified) | Plan response |
|---|---|---|
| "persist last-seen under /run or /var/lib" | `FAILCOUNT_DIR` is `/run` (tmpfs, reboot-cleared); service has NO `StateDirectory=`/`RuntimeDirectory=` (`cron-egress-resolve.service:1-17`) | Use `/var/lib` via a NEW `StateDirectory=` line — `/run` would re-open the outage for ~24h after every reboot. Decision documented in Technical Approach. |
| "~25 hostnames in the allowlist" | Static allowlist is **23** hosts (test guard `HOST_COUNT == 23`, `cron-egress-firewall.test.sh:375`) + 3 dynamic env hosts (Sentry/Supabase) resolved at runtime | Cosmetic; the fix is host-count-agnostic. Host-count guard untouched. |
| "additive-then-prune in one nft -f txn" | Confirmed: `build_batch` emits adds+dels into a single `BATCH` piped once to `nft -f -` (`:241-247`) | Only the *desired* set fed to `build_batch` changes; the atomic txn path is untouched. |
| "additive-only on partial resolution failure" | Confirmed: `PRUNE="no-prune"` when `FAILED_HOSTS>0` suppresses deletes (`:235-239`) | Grace-window eviction is ALSO a delete → MUST be gated on the same `no-prune` flag (Sharp Edge). |
| Edit resolver → auto-applies on merge | Confirmed: `server.tf:727` folds `cron-egress-resolve.sh` hash into `config_hash`; `apply-web-platform-infra.yml` re-runs the provisioner on push to `apps/web-platform/infra/**` | No manual/SSH apply step. |
| cloud-init carries a separate resolver copy needing manual sync | It embeds via `base64encode(file(...))` from the SAME source file (`server.tf:44,49`) | NO separate edit; the single file edit propagates. |
| GitHub CIDR machinery is separate | Confirmed: distinct file, generator, Inngest cron, and `soleur_egress_allow_cidr` interval set | Untouched. |

## Hypotheses

This is a confirmed-root-cause fix, not an open diagnosis; the network-outage
checklist (`firewall`/`unreachable`/`timeout` triggers) is satisfied as follows,
in L3→L7 order:

1. **L3 — firewall allowlist (egress, container→internet).** VERIFIED as the
   cause. The `SOLEUR-EGRESS` chain default-drops container egress to IPs not in
   `@soleur_egress_allow`/`_cidr`. Live artifact: Sentry `egress-blocked`
   (654 hits, 2026-06-16 10:47); blocked `DST` IPs (`104.18.x`, `198.137.150.x`,
   `198.202.176.231`, `64.239.109.193`, `34.149.66.137`) each front an
   already-allowlisted hostname. This is egress allowlist *IP-coverage*, not
   the SSH-ingress admin-IP class the checklist's L3 example covers.
2. **L3 — DNS/routing.** VERIFIED non-causal-but-contributory. `getent ahostsv4`
   resolves each LB host correctly every tick; the host∪container union is
   already in place (`:152-157,182`). The defect is not mis-resolution — it is
   that a *correct* single-tick answer under-covers a rotating pool, and the
   prune discards the prior tick's (still-valid) IPs.
3. **L7 — TLS/proxy.** Opt-out with artifact: the drop is at L3 (kernel
   `egress-blocked:` log line carries `DST=<ip>` with no TLS handshake reached);
   packets never leave the bridge, so there is no L7/CDN-cert dimension to the
   drop. An SNI/Host-aware proxy is the ADR-052-rejected SPOF alternative,
   explicitly out of scope.
4. **L7 — application/service.** VERIFIED via the missed-vs-failed signature:
   the Claude-eval crons emit NO Sentry heartbeat (missed check-in), which is
   the firewall-drop signature (heartbeat is the last step, gated on the
   network-heavy path completing) — not an app-error `?status=error` (failed)
   signature. Same signature as incident 5516336 (the GitHub CIDR miss).

### Network-Outage Deep-Dive

The checklist's L3 example (`hcloud firewall describe <server>` diffed against
operator egress IP) targets the **SSH-ingress admin-IP-drift** class. This
incident is the **container-egress allowlist-coverage** class — a different L3
surface. The correct verification artifact for egress coverage is NOT
`hcloud firewall describe` (that describes the *host* ingress firewall, not the
in-container `SOLEUR-EGRESS` nft chain); it is the **kernel `egress-blocked:`
drop line carrying `DST=<ip>`**, surfaced via the Sentry `egress_blocked` event
(654 hits, 2026-06-16 10:47), with each `DST` mapped to an already-allowlisted
host via `ipinfo.io`/CDN-org lookup. That artifact IS present and is the
authoritative one for this layer (it is the same no-SSH channel the
`cron-egress-blocked.md` runbook prescribes). The L3-firewall layer is therefore
**verified** for the egress class, with an explicit opt-out from the
host-ingress-firewall-CLI artifact (not applicable to an egress drop). L3-DNS,
L7-TLS, and L7-application are verified/opt-out as above. No gaps remain before
implementation.

## Alternative Approaches Considered

| Approach | Rotation-proof? | Stays scoped (no wholesale CIDR)? | Verdict |
|---|---|---|---|
| **Resolve-and-retain (grace window)** — THIS PLAN | Yes (accumulates the pool over the window) | Yes (only IPs DNS returned for a trusted host) | **Chosen.** Stays inside ADR-052's envelope; the "escalate on observed churn" path the ADR named. |
| Wholesale provider CIDR (Cloudflare ips-v4 / AWS ip-ranges.json / Google ranges) | Yes | **NO** — opens the entire cloud to a compromised cron | **Rejected — violates the hard security constraint + ADR-052 default-drop.** GitHub's bounded `/meta` file works only because GitHub publishes a HOST-scoped pool; CF/AWS/Google do not. |
| nft native FQDN/DNS sets | Partial (nft has no native DNS-name set type in the shipped kernel; would need a userspace updater = what the resolver already is) | Yes | **Rejected** — no native FQDN set in nftables; the resolver IS the userspace updater. Grace-window retention is the minimal change to that updater. |
| Scoped forward proxy (SNI/Host-filtered egress proxy) | Yes | Yes | **Rejected for now** — ADR-052 §4 explicitly rejected a standing proxy as a SPOF ("proxy dies → all crons dark"); reserved as the next escalation if grace-window retention proves insufficient. Heavier, new standing daemon, larger blast radius. |
| Shorten the timer to <1min | No (still pins one tick's IPs; just smaller windows) | Yes | **Rejected** — does not address pool size; an LB pool larger than one tick's answers still under-covers, and the timer already does one `docker exec` per tick (cost). |
| Lengthen prune-free additive-only forever | No (set grows unbounded; no eviction = laxity drift, dead IPs accumulate) | Yes | **Rejected** — unbounded growth + permanent retention of genuinely-dead IPs is the laxity the existing `resolve_host_failed` escalation already warns against. Grace-window eviction is the bounded form. |

## User-Brand Impact

- **If this lands broken, the user experiences:** the heavy Claude-eval crons
  (cron-community-monitor, cron-content-generator, cron-follow-through,
  cron-bug-fixer, cron-roadmap-review, cron-agent-native-audit) continue to
  silently fail mid-flight with missed Sentry check-ins — community digests,
  generated content, follow-through nudges, autonomous bug-fix PRs, and the
  roadmap/agent-native audits all stop running with no failed-status alert,
  only a missed-heartbeat the operator must notice. A regression in the OTHER
  direction (retaining too many / wrong IPs) would WIDEN the egress allowlist
  beyond intended scope.
- **If this leaks, the user's workflow/data is exposed via:** an over-broad
  retained set would let a compromised spawn-cron reach an IP that a trusted
  host *used to* resolve to but no longer does (e.g. an IP reassigned away from
  the CDN to a third party within the grace window). **Named honestly: this fix
  LENGTHENS the reassignment-exposure window from ~1 minute (today's
  prune-to-current-tick evicts a reassigned IP within one tick) to ~24h (the
  grace window keeps it reachable until the window elapses).** This is the one
  axis where grace-window retention is strictly worse than the current prune —
  it is a *quantitative extension* of ADR-052's already-accepted "CDN shared-IP
  broadening" residual (same kind of broadening, longer duration), not a new
  residual class. It is bounded to the same single-user-incident class because:
  (a) large-provider production IPs churn *within* the provider's pool, not *out*
  to unrelated tenants, on sub-day scales; (b) reaching the IP still requires an
  already-compromised spawn-cron (the firewall is a backstop, not the primary
  control); (c) the exfil value is capped by the same repo-scoped narrowed token
  that bounds ADR-052's content-blind residual. Eviction MUST stay bounded (24h
  window, store keyed only by IPs DNS returned for a trusted host, never a
  provider range).
- **Brand-survival threshold:** `single-user incident` — this is a security
  boundary (ADR-052 default-drop) AND the fix restores a multi-day cron outage;
  a wrong retention/eviction predicate either re-breaks the crons or loosens the
  egress boundary. CPO sign-off required at plan time; `user-impact-reviewer`
  invoked at review-time.

## Observability

```yaml
liveness_signal:
  what: "Sentry Crons monitor cron-egress-resolve (per-tick check-in) + the cron cohort's own Sentry cron monitors recovering to green"
  cadence: "60s (resolve timer); per-schedule for the eval crons"
  alert_target: "Sentry issue alert (missed check-in → paging) + operator email via OnFailure= Resend path"
  configured_in: "apps/web-platform/infra/cron-egress-resolve.sh:292 (sentry_checkin ok); apps/web-platform/infra/sentry/cron-monitors.tf (monitor def)"

error_reporting:
  destination: "Sentry web-platform (feature=cron-egress-firewall); via SENTRY_INGEST_DOMAIN/PROJECT_ID/PUBLIC_KEY read from doppler prd env"
  fail_loud: "egress-blocked / egress-dns-exfil Sentry error event (op=egress_blocked) when kernel journal shows drops in the 3-min window (cron-egress-resolve.sh:280-290); resolver fail() posts sentry_checkin error"

failure_modes:
  - mode: "Grace-window store wiped (reboot if mistakenly on /run, or StateDirectory not created) — pool re-shrinks, LB drops resume"
    detection: "egress-blocked Sentry event re-fires for an already-allowlisted LB host; retained-count in the resolve OK log drops toward the single-tick count"
    alert_route: "Sentry cron-egress-blocked issue alert → operator"
  - mode: "Grace window too short for a slow-rotating LB pool"
    detection: "recurring egress-blocked for the same already-allowlisted host AFTER this lands (runbook: distinguishes from a new-host gap)"
    alert_route: "Sentry cron-egress-blocked issue alert → operator (runbook says: lengthen GRACE_WINDOW_SECS)"
  - mode: "Eviction wrongly suppressed forever (store grows unbounded)"
    detection: "retained-count in the OK log climbs monotonically with no plateau across days"
    alert_route: "operator review of the resolve OK log via the discoverability test below"

logs:
  where: "journalctl -u cron-egress-resolve.service (host journald) — the [cron-egress-resolve] OK/WARN lines; kernel egress-blocked drops in journalctl -k"
  retention: "host journald default (volatile/rotated); the Sentry events are the durable no-SSH channel"

discoverability_test:
  command: "gh run view <latest apply-web-platform-infra run> --log | grep -E 'ASSERT-FAILED|cron-egress' ; AND read the Sentry cron-egress-resolve monitor status + cron-egress-blocked issue event count via the incident skill's SENTRY_ISSUE_RW_TOKEN toolchain (no ssh)"
  expected_output: "apply green (no ASSERT-FAILED); cron-egress-resolve monitor OK; cron-egress-blocked issue shows the 104.18.x/198.x/34.149.x DST hits trending to zero after the fix lands"
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `cron-egress-resolve.sh` records every current-tick IPv4 (from the
  finalized `DESIRED_ALLOW` union) into the per-IP last-seen store, and the set
  fed to `build_batch "$ALLOW_SET"` is `current-tick ∪ {stored IPs last-seen
  within GRACE_WINDOW_SECS}`.
- [ ] An IP absent from the current tick but last-seen within the window is
  **retained** in `@soleur_egress_allow`; an IP last-seen longer ago than the
  window is **evicted** from both the store and the set.
- [ ] On a `no-prune` tick (`FAILED_HOSTS > 0`), grace-window **eviction** is
  suppressed (no store deletes, no set deletes) — the additive-only invariant
  extends to the retention store — BUT **timestamp recording and the
  stored-fresh union STILL run** (they are additive/safe; suppressing them would
  age IPs toward a burst eviction on the next clean tick and re-open the
  outage). Behavioral test covers BOTH arms.
- [ ] On store readback, every value is re-filtered through
  `^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$` before being unioned into the retained set
  (defense-in-depth — a stray/corrupt store file can never inject a non-IP token
  into the `nft -f` batch; mirrors `current_set`'s re-grep at `:219`).
- [ ] The new bash MUST be strict-mode-safe under `set -euo pipefail`: timestamp
  read guarded (`cat … 2>/dev/null || echo 0` + `[[ =~ ^[0-9]+$ ]]`), the
  eviction sweep safe on an empty `$SEEN_DIR` (`find -type f` or `nullglob`),
  union pipes carry `|| true` (per Technical Approach "Bash strict-mode
  hazards").
- [ ] Fail-safe-on-empty preserved: ZERO current-tick addresses still aborts
  before touching the sets (store is read-to-augment only, never the sole
  source).
- [ ] The single atomic `nft -f -` transaction, the `8.8.8.8`/`8.8.4.4` DNS pin
  union, and the DOCKER-USER jump/default-drop self-heal are byte-for-byte
  unchanged in behavior (drift-guards at `cron-egress-firewall.test.sh:299-316`
  still pass).
- [ ] `cron-egress-resolve.service` declares `StateDirectory=cron-egress-resolve`;
  the store path resolves under `/var/lib`.
- [ ] `cron-egress-firewall.test.sh` gains: (a) source-anchored guards proving the
  retention/eviction constructs + the no-prune eviction-suppression exist, and
  (b) a behavioral test that — with a tiny `GRACE_WINDOW_SECS` — proves a
  previously-seen-then-currently-unresolved IP is RETAINED within the window and
  EVICTED after it. New test count reconciled against `RESULT: N passed`.
- [ ] GitHub CIDR machinery untouched: `git diff --stat` shows NO change to
  `cron-egress-allowlist-cidr.txt`, `scripts/gen-github-egress-cidr.sh`,
  `scripts/gen-github-egress-cidr.test.sh`, or any `cron-github-cidr-refresh*`
  file.
- [ ] `bash -n cron-egress-resolve.sh` parses; `cron-egress-firewall.test.sh`
  exits 0; `gen-github-egress-cidr.test.sh` exits 0 (proves CIDR side untouched).
- [ ] Runbook `cron-egress-blocked.md` gains the LB-rotation (non-GitHub)
  remediation subsection; the sentinel-name runbook-parity guard
  (`cron-egress-firewall.test.sh:454-475`) still passes (no new server.tf
  sentinels added, so no new runbook rows required — confirm).
- [ ] No prod crons triggered during testing (the behavioral test runs the
  retention logic in isolation against a tmp store; `nft` is absent on CI so the
  full loader is not run end-to-end — same constraint the existing test already
  documents at `:238-242`).
- [ ] PR body uses `Closes #<n>` only if a tracking issue exists; otherwise
  `Ref` the Sentry incident. CPO sign-off recorded (threshold = single-user
  incident).

### Post-merge (operator / automated)

- [ ] `apply-web-platform-infra.yml` re-applies on merge (path filter
  `apps/web-platform/infra/**`); post-apply container probes stay green
  (Automation: handled by the existing CI apply; no manual step).
- [ ] Sentry `cron-egress-blocked` issue: the `104.18.x` / `198.x` / `34.149.x`
  DST hit-rate trends to zero within one grace-window of the apply (verify via
  the incident skill's Sentry toolchain — no SSH, no dashboard-eyeball).
- [ ] The six heavy Claude-eval cron monitors recover to OK (next scheduled
  fire each) — verify via Sentry cron-monitor status, not by triggering them.

### Non-Functional Requirements

- [ ] Security: retained set contains ONLY IPs DNS returned for an
  already-allowlisted host; no provider CIDR range is added; eviction is
  bounded by the 24h window (NFR: egress boundary scope preserved per ADR-052).
- [ ] Performance: the store read/write is O(IPs in set) per tick (low
  hundreds at most); no new network calls, no new `docker exec`.
- [ ] NFR register assessment (run `/soleur:architecture assess` against
  `knowledge-base/engineering/architecture/nfr-register.md` for the egress
  containment + availability NFRs).

## Test Scenarios

### Acceptance Tests (RED targets — added to `cron-egress-firewall.test.sh`)

- **Given** a stored IP last-seen 1s ago and `GRACE_WINDOW_SECS=3600`,
  **when** the current tick does NOT re-resolve that IP, **then** the retained
  set fed to `build_batch` STILL contains it (retention within window).
- **Given** a stored IP last-seen `GRACE_WINDOW_SECS + 10`s ago, **when** the
  current tick does NOT re-resolve it, **then** it is absent from the retained
  set AND removed from the store (eviction after window).
- **Given** `FAILED_HOSTS > 0` (a `no-prune` tick) and a store entry past the
  window, **when** the retention/eviction runs, **then** NO eviction occurs
  (additive-only extends to the store).
- **Given** `FAILED_HOSTS > 0` (a `no-prune` tick) and a current-tick IP,
  **when** the resolver runs, **then** that IP's last-seen IS still refreshed to
  `now` and the stored-fresh union STILL runs (record/union are additive; only
  eviction is suppressed — guards against burst-eviction on the next clean tick).
- **Given** a store file whose content/name is not a valid dotted-quad,
  **when** readback runs, **then** it is filtered out and never reaches the
  `nft` batch (readback re-filter).
- **Given** a current tick that re-resolves a stored IP, **when** retention
  runs, **then** that IP's last-seen is refreshed to `now` (sighting for ANY
  host keeps it fresh).
- **Given** ZERO current-tick addresses, **when** the resolver runs, **then** it
  aborts at the fail-safe-on-empty guard before reading the store (store never
  the sole source).

### Source-anchored drift-guards (added to the `-- resolver safety invariants --` block)

- `assert_grep` the retention constant + store-dir construct
  (`GRACE_WINDOW_SECS`, `SEEN_DIR`) — anchored on the executable assignment, not
  comment prose (per the 2026-06-03 comment-prose false-match learning).
- `assert_grep` the no-prune eviction-suppression construct (eviction gated on
  the same `PRUNE`/`FAILED_HOSTS` flag).
- `assert_grep` `StateDirectory=cron-egress-resolve` in
  `cron-egress-resolve.service`.
- Re-assert the unchanged invariants still present (no `flush set`,
  `PRUNE="no-prune"`, DNS pin seed, single `nft -f -`) — these guards already
  exist; confirm they still pass.

### Regression Tests

- **Given** the GitHub CIDR side, **when** this PR lands, **then**
  `gen-github-egress-cidr.test.sh` exits 0 and `git diff` shows no CIDR-file /
  generator change (proves the GitHub layer is untouched).

## Dependencies & Risks

- **Risk: eviction-vs-no-prune ordering.** Grace-window eviction is a delete; it
  MUST share the `no-prune` suppression with the set prune, or a partial-failure
  tick could evict still-needed IPs. Mitigated by gating eviction on the same
  `FAILED_HOSTS`/`PRUNE` flag (AC + Sharp Edge + behavioral test).
- **Risk: store on `/run` re-opens the bug after reboot.** Mitigated by
  `StateDirectory=` → `/var/lib`. The test asserts the `StateDirectory=` line.
- **Risk: unbounded store growth.** Mitigated by the 24h eviction sweep; the OK
  log's retained-count plateau is the observability signal.
- **Risk: `terraform`/`scp` rewriting store-file mtimes** if an mtime-driven
  eviction is chosen. Mitigated by recommending content-driven (epoch-in-file)
  eviction; /work pins one and the test matches.
- **Dependency: none new.** No new package, no new network call, no new
  standing service (StateDirectory is a systemd primitive). `flock`, `getent`,
  `nft`, `jq` already required.

## Sharp Edges

- **Record vs. evict on a no-prune tick — the subtle trap.** The three
  operations have DIFFERENT gating: (1) record/refresh timestamps and (2) union
  stored-fresh IPs are ADDITIVE and run on EVERY tick (including no-prune); only
  (3) eviction is a DELETE and is gated on `FAILED_HOSTS == 0`. Do NOT over-read
  "additive-only on a no-prune tick" as "skip the timestamp write" — suppressing
  the record side lets IPs age toward eviction across a run of partial-failure
  ticks, then evict in a burst on the first clean tick, silently re-opening the
  exact outage this fixes. Test both arms (eviction suppressed; record still
  refreshed) on a no-prune tick.
- **Eviction is a delete — gate it on `no-prune`.** Grace-window eviction is
  structurally a prune; the existing `PRUNE="no-prune"` flag exists because a
  partial-resolution tick must not delete live IPs. On any `FAILED_HOSTS > 0`
  tick the resolver must skip BOTH the set prune AND the store eviction.
- **The store augments, never replaces, the tick.** Fail-safe-on-empty must fire
  on ZERO *current-tick* addresses regardless of how many IPs sit in the store —
  a frozen-DNS tick that resolved nothing must still abort, not "succeed" off the
  store. Place the record-then-retain block AFTER the
  `[[ -n "$DESIRED_ALLOW" ]] || fail …` guard (L186).
- **Comment-prose false-match (2026-06-03).** The new drift-guards must anchor on
  executable constructs (`GRACE_WINDOW_SECS=`, the eviction conditional), not on
  bare phrases that also appear in the resolver's explanatory comments — a kept
  comment must not green a deleted code path. Mirror the existing
  `flush set ip filter` / `o1 <= 255` anchoring convention.
- **Per-IP store keyed across ALL hosts, not per-host.** An IP returned for any
  allowlisted host keeps its timestamp fresh; eviction requires full-window
  absence from EVERY host. Do NOT key the store per `host/ip` (that would evict
  an IP still live for a different host).
- **A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6.**
  (Filled above; threshold = single-user incident.)
- **Test-runner reality:** the firewall drift-guard is `cron-egress-firewall.test.sh`
  (a `.test.sh`, run directly with `bash`), NOT a `bun`/`vitest` suite — invoke it
  as `bash apps/web-platform/infra/cron-egress-firewall.test.sh`. `nft` is absent
  on CI; the behavioral retention test must exercise the logic in isolation
  (extracted function or env-driven dry path), matching how the existing CIDR
  validator test pins a copy of the predicate (`:243-250`).

## Infrastructure (IaC)

### Terraform changes

- No NEW Terraform resource. The edit to `cron-egress-resolve.service` (adding
  `StateDirectory=`) rides the EXISTING `terraform_data.cron_egress_firewall`:
  its `config_hash` already folds `file("${path.module}/cron-egress-resolve.service")`
  (`server.tf:732`) and `file("${path.module}/cron-egress-resolve.sh")`
  (`server.tf:727`), so editing either file flips `triggers_replace` and
  re-provisions on apply. No provider/version change; no new sensitive var.

### Apply path

- (b) cloud-init + idempotent re-provision: the merged edit auto-applies via
  `apply-web-platform-infra.yml` (path filter `apps/web-platform/infra/**`,
  `-target=terraform_data.cron_egress_firewall`). The post-apply assert script
  restarts `cron-egress-firewall.service` (`cron-egress-firewall.test.sh:131`),
  re-running the loader → resolver with the new unit. Expected downtime: none
  (the firewall set is only ADDED to; the StateDirectory is created idempotently;
  the first post-apply tick records the current pool and begins accumulating).
- Fresh-host: cloud-init `write_files` embeds the same resolver + service via the
  `${cron_egress_resolve_*_b64}` template vars; `StateDirectory=` is honored by
  systemd on first boot.

### Distinctness / drift safeguards

- No `dev != prd` divergence (this is host infra, single prod host). No
  `lifecycle.ignore_changes` needed. No secret value lands in state (the store
  is runtime-only, under `/var/lib`, never committed).

### Vendor-tier reality check

- N/A — no vendor resource created (systemd `StateDirectory` is a kernel/systemd
  primitive, no API, no tier gate).

## Domain Review

**Domains relevant:** none (engineering infrastructure / security-boundary change;
no Product/UX surface, no marketing/legal/finance/sales/ops/support implication).

No cross-domain implications detected — this edits a host-side systemd-timer
shell script + its unit file + a bash drift-guard + a runbook. The
single-user-incident threshold drives CPO sign-off + `user-impact-reviewer` at
review-time (handled by the User-Brand Impact gate), not a Product/UX wireframe
gate (no UI surface in `## Files to Edit`).

## Open Code-Review Overlap

None. (Checked `gh issue list --label code-review --state open` scope against the
four edited files — `cron-egress-resolve.sh`, `cron-egress-resolve.service`,
`cron-egress-firewall.test.sh`, `cron-egress-blocked.md`. Re-run at /work if the
backlog changed.)

## References & Research

### Internal References

- Resolver (the file being fixed): `apps/web-platform/infra/cron-egress-resolve.sh`
  — DESIRED_ALLOW build `:159-186`; `build_batch`/`current_set` `:204-233`;
  PRUNE flip `:235-239`; atomic apply `:241-247`; FAILCOUNT pattern `:48,168-179`;
  fail-safe-on-empty `:186`.
- Loader (consumer, untouched): `apps/web-platform/infra/cron-egress-nftables.sh:151`
  (`@soleur_egress_allow accept`).
- Unit (edited — `StateDirectory=`): `apps/web-platform/infra/cron-egress-resolve.service`.
- Drift-guard (edited): `apps/web-platform/infra/cron-egress-firewall.test.sh`
  — resolver invariants `:295-317`; runbook-parity `:454-475`; host-count `:375`.
- Terraform delivery: `apps/web-platform/infra/server.tf:44,49,727,732,768,793`;
  cloud-init mirror `apps/web-platform/infra/cloud-init.yml:193,195,223,229`.
- Substrate: ADR-052
  (`knowledge-base/engineering/architecture/decisions/ADR-052-container-egress-firewall-docker-user-allowlist.md`)
  — §4 names the IP-rotation race + "escalate to proxy only on observed churn";
  §Consequences names the CDN shared-IP broadening residual class.
- Runbook (edited): `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`.

### Related Work / Learnings

- Precedent (same failure class, different layer):
  `knowledge-base/project/learnings/bug-fixes/2026-06-14-github-egress-cidr-must-cover-full-meta-not-just-big-blocks.md`
  — "for an LB host on a default-drop egress firewall, the single-IP resolver is
  the wrong layer"; GitHub's bounded `/meta` CIDR fix does NOT generalize to
  CF/AWS/Google.
- `knowledge-base/project/learnings/2026-06-10-terraform-remote-exec-gating-and-container-scoped-egress-allowlist.md`
  — container-scoped firewall enumeration discipline.
- `knowledge-base/project/learnings/best-practices/2026-06-03-oneshot-systemd-unit-inactive-is-healthy-report-the-timer.md`
  — missed check-in is the firewall-drop signature, not auth/error.
- `knowledge-base/project/learnings/integration-issues/2026-06-11-buttondown-subscriber-firewall-blocks-api-signups.md`
  — vendor-side block vs egress block disambiguation (referenced by the runbook).

### External References

- ADR-052 (above) is the authoritative design; nftables has no native FQDN/DNS
  set type in the shipped kernel (the resolver IS the userspace updater) — see
  Alternative Approaches.
