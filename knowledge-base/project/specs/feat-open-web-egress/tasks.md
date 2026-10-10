# Tasks — feat-open-web-egress (#9534)

Derived from `knowledge-base/project/plans/2026-10-05-feat-open-web-egress-plan.md`
(post-review). Two merge units; PR-B gates on PR-A's dark-launch observation.

## Phase 1 — PR-A: Gateway infra dark-launch

- [ ] 1.1 Author `infra/egress-deny-cidrs.txt` — the single deny-set source
      (RFC1918, CGNAT, link-local, `10.0.1.0/24` cluster-private, `fc00::/7`,
      `fe80::/10`, `::/128`, `::ffff:0:0/96`, `64:ff9b::/96`, `2002::/16`)
- [ ] 1.2 Author `infra/egress-gateway-squid.conf` — CONNECT-only,
      `SSL_ports 443`, `to_localhost`+`to_linklocal` + file-backed `dst`
      deny, `proxy_auth REQUIRED`, `dns_v4_first`, JSON logformat
      (decision+close: decision/reason/requested_host/resolved_ip/bytes/
      duration/%un)
- [ ] 1.3 Author `infra/egress-auth-helper.sh` — OK iff password exists as a
      file under the ro-mounted `/etc/squid/session-tokens`
- [ ] 1.4 Author `infra/egress-forwarder.mjs` — per-dispatch localhost
      forwarder (bind `127.0.0.1:0`, tunnel to gw:8443, require session
      token inbound / inject `workspaceId:token` outbound); ships in the app
      image, not the bake chain
- [ ] 1.5 Author `infra/egress-gateway-bootstrap.sh` — probe/reserve subnet,
      `docker network create` (named bridge), token dir, `docker run` Squid
      digest-pinned + mounts; idempotent
- [ ] 1.6 Digest-freshness triptych (clone zot pattern): provenance doc,
      `rule-audit.yml` upstream-poll step, `egress-image-staleness.test.sh`
- [ ] 1.7 `cron-egress-nftables.sh`: forward accept (docker0→gw:8443),
      DOCKER-USER `established,related` reply accept before isolation, new
      `SOLEUR-EGRESS-GW` chain (iifname soleur-egress0, `ct state new`-scoped
      deny rendered from the CIDR file), IPv6 guard replication
- [ ] 1.8 `cron-egress-resolve.sh`: extend self-heal needle set to the new
      chain + reply rule; render the egress0 drop from the CIDR file
- [ ] 1.9 cloud-init.yml: one runcmd line (bootstrap before app docker run +
      before enforce-probe); app `docker run` gains the token-dir rw mount;
      stay under the 32,768 B cap
- [ ] 1.10 Bake chain (all four): `host_script_files` (server.tf), Dockerfile
      COPY, `.dockerignore` re-includes, `soleur-host-bootstrap.sh` install
      loops+assertions
- [ ] 1.11 `terraform_data` SSH blocks for BOTH running hosts — web-1
      (`egress_gateway`) and web-2 (`egress_gateway_web2`, the
      `local.web_2_ssh_host_key` + `%RAND%` script_path shape). Web-2 is not
      optional: its cloud-init is frozen, so replace-only delivery would leave
      entitled sessions there fail-closed until the next `-replace`.
- [ ] 1.12 `apply-web-platform-infra.yml` `-target` allowlist entries for BOTH
      gateway resources (post-bridge SSH stage); `terraform-target-parity.test.ts`
      update + the `web-host-provisioner-parity` web-2 dialer-class widening
- [ ] 1.13 `vector.toml`: `egress_gw_journald` source +
      `pii_scrub_drop_userdata` inputs wiring
- [ ] 1.14 `cron-egress-enforce-probe.sh`: synthetic CONNECT pair
      (allow+deny) = heartbeat emitter + live policy verification
- [ ] 1.15 `betterstack-logs-alerts.tf`: deny-class spike + heartbeat-absence
      `logtail_exploration_alert`s (paid-tier ternary, `-target` lines, drift
      guard, runbook row)
- [ ] 1.16 Tests: `cron-egress-firewall.test.sh` fixtures (rule order, reply
      accept, ct-state-new scope, one-way invariant); `egress-gateway.test.sh`
      (Guard 1 matrix); CIDR parity test; `web-host-provisioner-parity`;
      `cloud-init-user-data-size.test.ts`; `scripts/probes/
      egress-gateway-policy.sh` selftest sharing the same fixtures

## Phase 2 — PR-B: Product wiring

- [x] 2.0 **Phase-0 spike (gate):** `query()` + `network.httpProxyPort` under
      pinned SDK — observe where the connection lands (SRT netns/unix-socket
      semantics); verify in-process WebFetch honors `HTTP_PROXY`. Record
      outcome in spec.md; a negative re-scopes task 2.4
      — DONE 2026-10-05, spec TR7: POSITIVE. `httpProxyPort` is a host port
      SRT chains to via its in-netns proxy (child sees
      `HTTP_PROXY=localhost:3128`, `CLAUDE_CODE_HOST_HTTP_PROXY_PORT=<ours>`);
      CONNECT for non-allowed domains forwards upstream unfiltered → gateway
      owns all policy. In-process WebFetch ignores sandbox proxy settings;
      it honors only process-env `HTTP(S)_PROXY` → task 2.4 must set env
      proxy on the spawned CLI subprocess with NO_PROXY covering the
      platform control plane.
- [x] 2.1 Migration `158_workspace_web_egress.sql` + `.down.sql` (clone 101):
      column, member-read RPC (NULL→false), owner-write RPC (P0001),
      `-- LAWFUL_BASIS: consent (Art. 6(1)(a))` annotation
- [x] 2.2 `server/resolve-web-egress.ts` + `server/set-web-egress.ts`
      (fail-closed, Sentry-mirrored, P0001→403)
- [x] 2.3 `app/api/workspace/web-egress/route.ts` + `WebEgressToggle` on the
      Scope Grants page (clone bash-autonomous; member locked state; on-state
      "applies to sessions started after enabling / turn-off revokes live"
      sub-line; CTA styling vs anti-slop; no audit-log link — deferred #9545)
- [x] 2.4 Dispatch wiring: `resolveWebEgress` pure read in the
      `cc-dispatcher.ts` Promise.all (active-workspace-keyed, error→false+
      Sentry); post-read token mint + file write + forwarder spawn
      (bind :0; failure → degrade + Sentry); `buildAgentSandboxConfig`
      `allowWebEgress` → `httpProxyPort` + `credentials.envVars` census deny
      (export `ALLOWED_SERVICE_ENV_VARS`, dedupe, NO `GIT_CONFIG_*`) +
      `denyRead` for credential files + token dir; `WebFetch` removed from
      `CANONICAL_DISALLOWED_TOOLS` only when entitled+verified; WebSearch
      stays disallowed; forwarder teardown at session end + on re-resolve-
      false; dispatcher-startup orphan reaper; per-dispatch `HTTP_PROXY`
      (never ambient)
      — DONE; TR7 arm-3 correction: `httpProxyPort` NOT emitted (env proxy
      URL carries the session token and covers both paths — sandboxed via
      SRT chain + in-process WebFetch); `deniedDomains` stays cut
- [x] 2.5 Per-dispatch entitlement log (`webEgress` + forwarder port/PID);
      forwarder exit → Sentry
      — DONE: `cc-dispatcher: web egress forwarder bound` log carries
      workspaceId/port/pid; mid-session exit → reportSilentFallback
- [x] 2.6 Legal pack: Art. 30 PA-2(d) amendment + DPIA screening;
      privacy-policy/DPD/Eleventy mirror + `LEGAL_DOC_SHAS` repin; DPA
      Sch.4 TOM entry; AUP hosted-egress abuse clause
- [x] 2.7 ADR (deliverable of this PR) + C4 enumeration/update; legal
      status-flip sweep (future-tense egress claims)
      — DONE: ADR-278; egressGw + egressForwarder + publicInternet in
      model.c4 (likec4-parse-verified); no stale future-tense egress claims
      found in docs/legal/
- [x] 2.8 AC verification pass incl. deterministic (non-LLM) security
      scenarios per plan §Test Scenarios
      — DONE at unit level: web-egress.test.ts (env census, denyRead,
      forwarder lifecycle/auth/407/reaper), web-egress-access.test.ts
      (fail-closed read, P0001→403, audit emit), cc-dispatcher factory
      entitlement cases; gdpr-gate clean on the diff; infra-side ACs were
      PR-A-verified, live-traffic ACs await dark-launch observation
