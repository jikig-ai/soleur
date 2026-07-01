---
feature: multi-host-workspaces-phase3
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
plan: knowledge-base/project/plans/2026-07-01-feat-multi-host-workspaces-phase3-coordinator-plan.md
epic: 5274
issue: 5274
phase: 3
status: draft — architecture chosen (user-sticky); open decisions D0-ref/D1/D2 to deepen-plan
---

# Tasks: Multi-host `/workspaces` Phase 3 — 2nd host + user-sticky router (GA line)

> Routing model (operator, 2026-07-01): **user-sticky** — per-user `worktree_id` lease;
> two users of one workspace can span two hosts; NO cross-host control-op forwarding.
> Four sub-PRs, each inert until 3.D flips `isGitDataStoreEnabled()`. PR bodies: `Ref #5274`.

## Gate 0 — Resolve open decisions (deepen-plan / architecture) BEFORE the gated sub-PR
- [ ] 0.1 **D0-ref** (blocks 3.B): per-user distinct-ref vs serialized shared-ref git-data push semantics — `data-integrity-guardian`. Record with the ADR-068 D0 amendment.
- [ ] 0.2 **D1** (blocks 3.D): confirm where the app WS ingress enters today (tunnel vs proxied DNS) before the ingress→router rewire.
- [ ] 0.3 **D2** (blocks 3.D flip): cross-tenant WRITE threat-model scope (logic-bug vs host-compromise) + enforcement locus (app-side vs git-data-host forced-command authz) — `security-sentinel` + `data-integrity-guardian`.
- [ ] 0.4 Author the two ADR-068 amendments (D0 user-sticky routing; D-TLS/cred); reconcile ADR-068 stale anchors (mig 114→116, sandbox :94→:106); flip plan to reference them.

## Sub-PR 3.A — Infra foundations: 2nd host + placement group + host_id + proxy TLS + erasure wrapper (dark)
- [ ] 3.A.1 `for_each` refactor of `hcloud_server "web"` (server.tf:21) → `var.web_hosts`; `moved` blocks for server + `hcloud_volume`/`hcloud_volume_attachment` (server.tf:926–940) + all 8 sibling `terraform_data` provisioners; `set -e` on every remote-exec inline; replace positional TF readers (`terraform providers schema -json`).
- [ ] 3.A.2 EU residency pin: `var.web_hosts.location ∈ {nbg1,fsn1,hel1}`; `terraform check`/`infra-validation.yml` rejects non-EU web host + placement group (CLO T-1).
- [ ] 3.A.3 `hcloud_placement_group "spread"` on both web hosts (maintenance-window apply — attach reboots the running host).
- [ ] 3.A.4 2nd host private-net attach (network.tf, reserved IP e.g. 10.0.1.11).
- [ ] 3.A.5 Host↔host proxy TLS: long-lived self-signed **server** cert per host (`tls_private_key`/`tls_self_signed_cert`), cloud-init + Doppler; one-way (no client cert).
- [ ] 3.A.6 `SOLEUR_HOST_ID` injection in `ci-deploy.sh` (canary + prod docker run; metadata-resolved).
- [ ] 3.A.7 2-host deploy fan-out in `ci-deploy.sh`/`apply-web-platform-infra.yml` (deliver to both hosts) — AC5.
- [ ] 3.A.8 Art. 17 host wrapper: cloud-init `git-data-remove` forced-command on the git-data host (sibling to `git-data-provision.sh`, CWE-22 validated) — cloud-init ONLY (CLO DL-1; must pre-exist for 3.D).
- [ ] 3.A.9 Renumber `ADR-068-graceful-cron-drain…` to the next free ordinal; grep-sweep references (Kieran P2-8).
- [ ] 3.A.10 `expenses.md` += 2nd host (€15/mo) + LUKS volume (verify Hetzner pricing).
- [ ] 3.A.T RED→GREEN: `terraform plan` 0-destroy (jq); non-EU location rejected (negative, T-1); `host-identity` metadata-resolve test; server-cert chain validates.

## Sub-PR 3.B — User-sticky router + per-user lease + reconnect affinity (gated on 0.1/0.4)
- [ ] 3.B.1 Per-user `worktree_id` — stop hardcoding `"primary"` (worktree-write-lease.ts:23); thread through lease acquire/heartbeat/release + worktree path (workspace-resolver.ts) + call sites (agent-runner.ts, cc-dispatcher.ts).
- [ ] 3.B.2 `server/session-router.ts` (new): co-located stateless sticky router — resolve owning host from the per-user lease at the WS-upgrade handshake; local ⇒ serve, remote ⇒ proxy over one-way-TLS private net; owning host re-verifies membership before serving a proxied session (CLO AP-2).
- [ ] 3.B.3 Local ownership lookup `isConversationLiveHere` = `abortSession()>0 || hasActiveCcQuery(convId)` (local, no cross-host union-forward).
- [ ] 3.B.4 Reconnect affinity (routes back to owner; grace-abort cancel host-local); cross-host migration emits a non-transient WS close code (client teardown+reconnect, gate on materialization proof).
- [ ] 3.B.T RED→GREEN: two users → distinct per-user leases on distinct hosts; control op for conv X resolves on X's owner (sticky); placement decided pre-upgrade (negative, P2-10); reconnect lands on owner + grace cancel host-local; membership re-verify rejects cross-tenant proxied session (negative, AP-2).

## Sub-PR 3.C — Cross-tenant isolation: membership-gated git-data fetch authorization
- [ ] 3.C.1 `server/git-data-client.ts` (new): membership-gated fetch authorization on the git-data fetch/clone path via `resolve_workspace_installation_id` shape (NULL→deny).
- [ ] 3.C.2 D2 resolution: cross-tenant WRITE enforcement per 0.3 (app-side membership OR git-data-host forced-command authz on receive-pack/upload-pack) — before the 3.D flip.
- [ ] 3.C.3 `ensure-workspace-repo.ts` clones from git-data when flag on, retaining `origin`→GitHub.
- [ ] 3.C.T RED→GREEN: host-A+tenant-A cred cannot READ tenant-B git-data (negative); cannot WRITE tenant-B git-data (negative, TS-1); non-member RPC→NULL→deny.

## Sub-PR 3.D — Cutover + GA flip (LUKS, freeze-rsync, coordinated flip, erasure, legal lockstep) — gated on 0.2/0.3
- [ ] 3.D.1 Fresh LUKS-encrypted git-data volume (TF) as rsync target; Doppler-env key at boot (CLO TS-2).
- [ ] 3.D.2 Hardened cutover: git-data write-freeze; two-pass rsync; set-identity verify (`for-each-ref` diff + `rev-list|sort|sha256sum`); coordinated cross-host flag flip; old-volume decommission/wipe (CLO DL-2); rollback = flag-off + re-drain (GitHub-rehydration backstop, stated).
- [ ] 3.D.3 Ingress→router rewire (tunnel.tf or the real ingress, per 0.2/D1).
- [ ] 3.D.4 Art. 17 app-side erasure: `account-delete.ts`/workspace-delete calls the 3.A `git-data-remove` wrapper over private net (mirror attachments purge account-delete.ts:152) — AC9.
- [ ] 3.D.5 Legal-doc lockstep: `article-30-register.md` (recipients += web-2+router; TOMs += one-way TLS, fetch authz, LUKS, membership re-verify) + `privacy-policy.md`/`gdpr-policy.md`/`data-protection-disclosure.md` Last-Updated + repin `LEGAL_DOC_SHAS` + Eleventy mirrors + `compliance-posture.md` Hetzner DPA row; NO `TC_VERSION` bump (CLO AP-3).
- [ ] 3.D.6 NFR register: NFR-019 N/A→achieved (repoint ADR-027→ADR-068); NFR-026 achieved only after LUKS+TLS verified; ADR-068 status `adopting`→`accepted`.
- [ ] 3.D.7 Operator-acknowledged Criticals → `compliance-posture.md` Active Items + `compliance/critical` issue (TS-1, T-1, DL-1) — gate the flip.
- [ ] 3.D.8 Enroll `scripts/followthroughs/phase3-ga-soak-5274.sh` + tracker directive + `follow-through` label in `scheduled-followthrough-sweeper.yml`.
- [ ] 3.D.9 Review set includes `deployment-verification-agent` + security-sentinel + data-integrity-guardian + observability-coverage-reviewer + user-impact-reviewer.
- [ ] 3.D.T RED→GREEN: AC7 (two users/two hosts/one workspace; 2nd user's committed work reaches shared git-data and is visible — Kieran P1-5); AC8 drain/deploy no-fresh-greeting; tombstone-release preserves fence token across takeover; reclaim→first-push ordering (P2-9).

## Cross-cutting (every sub-PR)
- [ ] Observability: op slugs `control_plane_route` + `worktree_lease`, in-surface structured probes (blind surfaces), Better Stack + Sentry, no-ssh discoverability.
- [ ] GDPR: `/soleur:gdpr-gate` per-PR when its regulated surface materializes; EU-pin every substrate; per-tenant isolation; no new sub-processor.
- [ ] `user-impact-reviewer` at each PR review (single-user-incident threshold).
- [ ] PR body uses `Ref #5274` (not `Closes`) until Phase 4.
