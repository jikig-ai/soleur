---
title: "web-2 serving: SOLEUR_HOST_ROSTER keys never match the lease host id, and turns on web-2 self-stop (gitKind=absent)"
date: 2026-11-18
slug: fix-host-roster-key-lease-host-id-web2-pre-heal
branch: feat-one-shot-12910-host-roster-lease-id
issue: 12910
closes: 12910
type: fix
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# fix: roster key vs lease host id, and web-2 first-turn self-stop

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Overview

Two defects surfaced on 2026-11-18 while web-2 was in the GA pool for the #8211 AC-P3 proof (web-2 is now back at weight 0).

1. The session router looks up a lease owner's address by the lease's host id (`hetzner-<instance id>`), while the roster it reads is keyed by the Terraform host key (`web-1` / `web-2`). No cross-host session can resolve its owner, and the serve gate's roster check (`lb-weight-gate.sh` A.3) tests the name-keyed shape, so gate and runtime disagree.
2. A turn placed on web-2 stops at the agent-readiness gate with `gitKind=absent source=host-pre-heal`, and web-2 reports `workspaces_populated=0`.

This plan settles the key design (CTO ruling), makes the gate test the runtime shape, finds why web-2 has no workspace on first turn, and replaces the owner-gated Doppler write with a read-only precondition (the live roster is already correct).

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
IaC routing (Phase 2.8) was reviewed. The plan has no manual infrastructure step: Phase 5 is a read-only check, and a `false` read escalates to the owner rather than prescribing a write. `SOLEUR_HOST_ROSTER` is deliberately a hand-kept Doppler `prd` value outside Terraform: ADR-118 calls it an "operator-class prd write"; census row C6 is pinned by `web-hosts-generic.test.sh`, which asserts that no `.tf` derives it. Moving it into Terraform is tracked in #12919.

## Research Insights

### Premise Validation

- #12910 is OPEN (p1-high). #8211 is OPEN; its AC-P3 lives in `knowledge-base/project/plans/archive/20261110-144401-2026-11-09-feat-relay-hello-key-rotation-ghcr-push-diagnostics-plan.md` ("#8211 item 1 stays open until the owner host shows a `relay_hello_window accepted=<n>` row with `n>0`").
- Collision pre-check: one hit, PR #12918, which is this branch's own auto-created draft (`feat-one-shot-12910-host-roster-lease-id`, no files). Not a duplicate. The three foreign `test-all.sh` processes belong to another worktree (#12726): machine saturation, not a collision.
- Every cited symbol exists on this branch: `resolveHostAddress`/`loadHostRoster` (`apps/web-platform/server/session-router.ts`), `resolve_host_id` (`apps/web-platform/infra/ci-deploy.sh`), A.3 (`apps/web-platform/infra/lb-weight-gate.sh`), `reportAgentReadinessSelfStop` (`apps/web-platform/server/repo-resolver-divergence.ts`).
- **Defect 2's premise did not hold.** The brief reads the self-stop row as "a turn on web-2 stops before running". A read-only Better Stack pull (`scripts/betterstack-query.sh`, 2026-11-18 12:44-12:58Z) shows the same web-2 process kept going after the 12:47:46Z row: `CLAUDE_SDK_CAN_USE_TOOL_SHADOWED` at 12:47:54 (SDK query built), `cc-persist-usage-on` at 12:47:58 (the model replied and usage rows were written), then `agent_sessions_live=1 cc_queries=1` at 12:48:17 and 12:49:19. Nothing followed it: no repo-clone failure, no `RepoNotReadyError`/`repo_setup_failed`, no post-heal self-stop (`gitRevParseValid` tag), no `in-sandbox-backstop`. The 12:55Z owner-unresolved rows name web-2 (`hetzner-176328334`) as the lease holder, and the lease is acquired *after* the heal (`cc-dispatcher.ts` acquire block, `mode.runRepoLifecycle && isGitDataStoreEnabled()`). So web-2 healed (cloned) the workspace and ran the turn. Defect 2 is a **false-positive signal**, not a stopped turn.
- Live roster shape, read-only and printing booleans only: `SOLEUR_HOST_ROSTER` keys are exactly `["web-1","web-2"]`; `web-1` equals the committed `var.web_hosts["web-1"].private_ip` (10.0.1.10), `web-2` equals `var.web_hosts["web-2"].private_ip` (10.0.1.11), and every value is shaped `10.0.1.x`. `SOLEUR_PROXY_PEER_ALLOWLIST` has 2 entries and contains both addresses. **The roster's values are already correct. The only thing wrong is which key the runtime looks up.**

### Defect 1: where the key splits

- `ci-deploy.sh` `resolve_host_id` runs at top level, before `ENV_FILE` is resolved, sets `readonly HOST_ID` to `hetzner-<metadata instance-id>` (fallback `machine-<sha12>`), and injects it as `-e SOLEUR_HOST_ID="$HOST_ID"` on canary and prod. `infra/lib/docker-run-tuple.py` `_COMMON_ENV` pins `"SOLEUR_HOST_ID": {"$HOST_ID"}`.
- `server/host-identity.ts` `resolveHostId()` reads `SOLEUR_HOST_ID`. It has three consumers: lease acquire (`server/agent-runner.ts` `startAgentSession`, `server/cc-dispatcher.ts` `realSdkQueryFactory`) and the router's `myHostId` (`server/ws-handler.ts`, the `resolveSessionRoute({... myHostId: resolveHostId() })` call).
- `server/session-router.ts` `resolveHostAddress(holder.hostId)` = `loadHostRoster()[hostId]`. Its doc comment says the roster maps "a stable `host_id` (the lease's placement authority, = SOLEUR_HOST_ID)". The comment assumes the two keys are the same; the values in production are not.
- `lb-weight-gate.sh` A.3 checks `has($SOLEUR_GATED_HOST)`. `SOLEUR_GATED_HOST` is a `var.web_hosts` key (regex `^[a-z][a-z0-9-]{0,30}$`, #9421/ADR-327), so the gate validates a name-keyed roster.
- Other `SOLEUR_HOST_ID`-shaped readers are telemetry only: `cat-deploy-state.sh` (AC13 compares it to the TF-known `hcloud_server` id) and `inngest-inventory.sh` keep their own `resolve_host_id` copies, drift-guarded by token co-occurrence (`inngest-inventory.test.sh` "#6425 AC4"). `server/watchdog-dispatch-clock.ts` only checks that the value is non-empty, and `server/cron-liveness-marker.ts` reports it as a field.
- Stability evidence: `server/host-private-ip.ts` "not SOLEUR_HOST_ID: the Hetzner instance id changes on every web-host replace"; ADR-143 D4 "De-petting changes web-1's lifecycle, not its roster identity — never a key rename"; `var.web_hosts` private IPs are committed (`infra/variables.tf`), and `hcloud_server.web` is named `each.key == "web-1" ? "soleur-web-platform" : "soleur-${each.key}"` (`infra/server.tf`). web-1 has `ignore_changes = [user_data]`, so no cloud-init change reaches it.
- Lease semantics (`supabase/migrations/116_worktree_write_lease.sql`): re-acquiring with the same `host_id` keeps `lease_generation` (the recreate-deploy carve-out). A different `host_id` waits out the liveness window (`LEASE_LIVENESS_WINDOW_MS = 240_000`, `server/worktree-write-lease.ts`), then takes over and bumps the generation. Graceful shutdown tombstones the lease, so the next acquire need not wait.
- Test fixtures: `test/session-router.test.ts` uses abstract ids `host-1`/`host-2`, so it never pinned which key shape production uses. `infra/lb-weight-gate.test.sh` uses `{"web-1":"10.0.1.10","web-2":"10.0.1.11"}`. Gate and runtime tests each passed against a different shape, which is how the split shipped green.

### Defect 2: where the false self-stop comes from

- `server/cc-dispatcher.ts`, the `#5733 Phase 1b` block: `if (repoReadiness.ok && repoUrl && !gitReady) reportAgentReadinessSelfStop({...})` runs **before** the self-heal (`if (mode.runRepoLifecycle && needsSelfHeal)`). It passes no `source` (so it defaults to `host-pre-heal`) and no `gitRevParseValid`. The comment says it "Fires BEFORE the heal so the strand is queryable on this very dispatch."
- On a fresh host every user's first turn hits it. The working tree is `<WORKTREE_ROOT>/<id>` (default `/var/lib/soleur/worktrees`, `server/workspace-resolver.ts`), and per the census it sits in the container's writable layer, so every redeploy also empties it. The heal then clones from GitHub (`server/ensure-workspace-repo.ts`, `realGraftRepoClone`) and overlays git-data (`fetchFromGitData`, fail-soft).
- ADR-044 and `test/agent-readiness-absent-git.test.ts` AC5 say the pre-heal surface must not emit, because the heal owns it. The terminal gate is `evaluateAgentReadiness(..., phase: "post-heal")`, which emits with `gitRevParseValid` and throws `RepoNotReadyError`. The cold-dispatch emit bypasses that guard.
- **Masking defect:** `reportAgentReadinessSelfStop` dedupes per process on `${userId}:${activeWorkspaceId}:${gitKind}:${source}`. The pre-heal emit and the post-heal absent emit share `source=host-pre-heal` and `gitKind=absent`. Once the false positive has fired, a real post-heal absent strand for the same user is never reported for the rest of that process's life.
- `workspaces_populated` (the `relay_probe` line, `server/proxy-listener-status.ts` `formatRelayProbeLine`, fed by `server/readiness.ts` `isWorkspacesPopulated`) counts the legacy `WORKSPACES_ROOT || /workspaces` root, not `WORKTREE_ROOT`. web-2's `/workspaces` holds no user data by design (ADR-143), so `0` is expected and says nothing about defect 2.

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md`: "A test that pins the gate's INPUT does not pin the gate". This is the exact shape of the A.3/runtime split.
- `knowledge-base/project/learnings/best-practices/2026-11-12-keyed-host-gate-must-refuse-unkeyed-evidence-web-hosts.md`: the closest precedent for key-shape drift in this gate.
- `knowledge-base/project/learnings/best-practices/2026-07-01-blind-surface-needs-structured-probe-before-nth-fix.md`: a probe's fields must discriminate the competing hypotheses in one event. Here the absent `gitRevParseValid` tag is what separates the pre-heal row from a post-heal one.
- No ADR or learning fixes what the roster key must be. The code comment, the gate and ADR-143 D4 disagree, so the ADR-068 amendment below is a deliverable.

### Conventions

- Machine is saturated: run single test files only (`./node_modules/.bin/vitest run <file>` from `apps/web-platform`, `bash <file>.test.sh`); put scratch under `/var/tmp`.
- No secret on argv or in output; `prepush-secret-scan` before push; never `git stash`.
- Do not touch #12330, #11694, #11676, #11669 or #10476.

### Property List (Phase 0.6b)

- **P1.** A peer resolves the lease holder's id to that holder's relay address. The roster key and the lease host id are the same string.
- **P2.** P1 still holds after a web-host replace, with no Doppler write.
- **P3.** The serve gate refuses any roster the runtime cannot resolve for the gated host: the gate asserts the key shape the runtime looks up.
- **P4.** A turn placed on web-2 runs, and the telemetry does not report a self-stop for a turn that ran.
- **P5.** A real post-heal strand is never hidden behind an earlier pre-heal observation.
- **P6.** Proof in production: the owner host logs `relay_hello_window accepted=<n>` with `n>0`.

### Cut List

- Keying the roster by Hetzner instance id (option a) gives P1 but fails P2: every replace needs a Doppler write, which is the failure that just happened. Cut.
- A Doppler prd roster write gives nothing, because the live roster already holds the right keys and the committed addresses (verified above). Cut. Only a read-only verification command stays, as a precondition.
- A "materialize from git-data on first turn" mechanism: P4 is already met by the existing heal (clone from GitHub plus git-data overlay); production shows the turn ran. Cut.
- Changing `workspaces_populated`: it buys no property in the list. Cut (see Non-Goals).

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "The roster value itself is a Doppler prd write: prepare the exact value/command" | The live roster is already `{"web-1": 10.0.1.10, "web-2": 10.0.1.11}` by key, and both addresses match `var.web_hosts` (read-only check, 2026-11-18) | No write. Phase 5 keeps a read-only precondition; a `false` read stops the work and escalates |
| "A turn on web-2 self-stops ... web-2 reports workspaces_populated=0" | The turn ran. The row is the cold-path pre-heal emit, and `workspaces_populated` counts the legacy `/workspaces` root | Phase 4 narrows the emit to the one shape the post-heal gate cannot see, which also ends the dedupe masking. `workspaces_populated` gets a one-line comment only |
| "Determine whether web-2 is expected to materialize the workspace from the git-data store on first turn" | Yes, on any host, through the existing self-heal (clone from GitHub, then the git-data overlay). It worked on 2026-11-18 | No new materialize path |
| `session-router.ts` "a stable `host_id` (= SOLEUR_HOST_ID)" | `SOLEUR_HOST_ID` is a Hetzner instance id that changes on every replace | Phase 1 makes the placement id the `var.web_hosts` key and rewrites that comment |
| "the image release deploys the new `ci-deploy.sh`" (implicit in the first draft) | `ci-deploy.sh` reaches the hosts through `apply-deploy-pipeline-fix.yml`. That run is unordered against `web-platform-release.yml`, and a script-only apply does not swap the container (its redeploy step fires only on a seccomp-hash change) | Phase 7 sequences a release redeploy after the apply succeeds, and verifies the on-host script hash (T9) |
| Better Stack `host_name=soleur-web-platform` "proves" web-1's metadata hostname | `host_name` is a Terraform-rendered Vector label, so it is not evidence about the metadata endpoint | Removed as evidence. T1's self-verification and T3's first-rollout fallback make an unverified hostname harmless |

## Decisions (CTO rulings, 2026-11-18)

Full rows live in `knowledge-base/project/specs/feat-one-shot-12910-host-roster-lease-id/decision-challenges.md`. R1-R4 were ruled first. T1-T11 were ruled on the plan-review findings.

- **R1 (key):** option (b2). The placement id becomes the `var.web_hosts` key, which `ci-deploy.sh` derives from Hetzner metadata `hostname` by inverting `server.tf`'s name expression and injects as `SOLEUR_HOST_KEY`. `resolveHostId()` remains the one chokepoint. `resolve_host_id`/`HOST_ID`/`SOLEUR_HOST_ID` stay unchanged as telemetry.
- **T1 (self-verification, refines R1):** `resolveHostId()` accepts `SOLEUR_HOST_KEY` only if it matches `HOST_KEY_RE` **and** `roster[key]` equals this container's own `SOLEUR_HOST_PRIVATE_IP` (`readHostPrivateIp()`). Otherwise it returns `SOLEUR_HOST_ID`. Two live hosts cannot share a private IP, so a wrong hostname, a wrong roster or a mis-set env can only ever degrade to today's id, never to a shared one. Migration 116 hands a LIVE lease to a caller with the same `host_id` at the same generation, which is why uniqueness has to be checked rather than assumed.
- **T2:** single PR. With T1, the worst case is today's behaviour.
- **T3 (stickiness):** retry the metadata read 3 times. If the running prod container already carries a non-empty `SOLEUR_HOST_KEY` and the new result differs or is empty, abort the deploy before the canary. No on-host state file: the running container is the last-good record. On first rollout (no running key) it falls back and does not abort.
- **T4:** no `SOLEUR_HOST_KEY_OVERRIDE`. The inverse is the exact census of `server.tf`'s name expression: `soleur-web-platform` maps to `web-1`, `soleur-web-1` gives rc 1, and anything else must be `soleur-<key>` with a key that matches the regex.
- **R2 + T5 (gate):** keep the existing A.3 checks and add three: every roster key is a committed `var.web_hosts` key; every roster key's address equals that key's committed `private_ip`; every `SOLEUR_SERVING_ROTATION` member is a roster key. The simplicity cut was considered and rejected: `has($HOST)` alone passes a wrong address, and a pooled host with no roster entry is the incident. These checks retire when #12919 generates the roster.
- **T6:** pin the absence of `create_before_destroy` on `hcloud_server.web`, because generation carry across a replace is safe only while the old host is destroyed first.
- **T7 (vocabulary):** one exported pure `describeHostIdentity()` returning `{ id, source }`, where `source` is one of `web-host-key`, `key-absent`, `key-malformed`, `key-unverified`, `dev-sentinel`. At boot, one `host_identity source=<enum>` line and one `reportSilentFallback` when in production with a non-empty private IP and a source other than `web-host-key`. No `keyState`, no `ownerHostIdShape`, no separate boot module.
- **R3 → T8 (defect 2):** do not delete the emit; narrow it. It fires only when the **post-heal re-probe** finds a `file-pointer` whose gitdir escapes the workspace. Host `rev-parse` cannot see that strand, so this emit is its only host-side record. An absent `.git`, the false-stop case, stays silent. Keep the `host-pre-heal` source value.
- **R4:** no Doppler prd write. Re-run the read-only check before merge.
- **T9 (delivery):** after merge, once `apply-deploy-pipeline-fix.yml` succeeds, the agent runs `gh workflow run web-platform-release.yml` on the merge SHA and verifies the on-host `DEPLOY_SCRIPT_SHA` and the `host_key resolved=` line on both hosts. This is not in the owner-gated set (serve/drain dispatch, Doppler write, host replace): it redeploys an already-merged image, as every merge does. Rollback is a revert PR plus the same redeploy.
- **T10:** pin "the canary's id differs from prod's". The canary gets `-e SOLEUR_HOST_KEY=` (empty), so it always resolves to the instance id.
- **T11:** Guard 2 is one round-trip loop with a floor, the regex-parity line, the `soleur-web-1` row and the T6 assertion. No meta harness rows.
- **Dissent recorded (R1):** (b1), reverse-looking-up the host's own private IP in the roster, was the alternative design. T1 adopts its check as a verifier on top of (b2) rather than as the source of the id.

## Implementation Phases

TDD order: in each phase, write the failing test first (`cq-write-failing-tests-before`). Single test files only.

### Phase 0 — Pre-flight read (no code)

Re-run the read-only roster check from Phase 5 and record the boolean output in `session-state.md`.

### Phase 1 — One verified placement-id resolver

- New leaf `server/host-roster.ts`: move the pure `loadHostRoster()` parse out of `server/session-router.ts` unchanged. It reads `SOLEUR_HOST_ROSTER` at call time and has no `server/` imports. `session-router.ts` re-exports it, so existing importers do not change.
- `server/host-identity.ts`:
  - Add `export const HOST_KEY_RE = /^[a-z][a-z0-9-]{0,30}$/`.
  - Add a pure `export function describeHostIdentity(env = process.env): { id: string; source: "web-host-key" | "key-absent" | "key-malformed" | "key-unverified" | "dev-sentinel" }`. Rules, in order:
    1. A trimmed `SOLEUR_HOST_KEY` that is empty gives `key-absent`.
    2. One that fails `HOST_KEY_RE` gives `key-malformed`.
    3. One where `loadHostRoster(env)[key] !== readHostPrivateIp(env.SOLEUR_HOST_PRIVATE_IP)`, or where that IP is empty, gives `key-unverified`.
    4. Otherwise, `{ id: key, source: "web-host-key" }`.
    5. Every non-`web-host-key` source returns `id = trimmed SOLEUR_HOST_ID`. When that is also empty, production throws the existing error unchanged, and non-production returns `{ id: "dev-local", source: "dev-sentinel" }`.
  - `resolveHostId()` returns `describeHostIdentity().id`. Its signature is unchanged, so the three consumers (`agent-runner.ts` acquire, `cc-dispatcher.ts` acquire, `ws-handler.ts` `myHostId`) need no edit.
  - Imports are only `./host-roster` and `./host-private-ip`, both env-only leaves, so there is no cycle and no Sentry inside the leaf. (Verify with `git grep -n "^import" apps/web-platform/server/host-private-ip.ts`.)
  - `assertHostIdNotUserId` is unchanged.
  - Rewrite the header comment:
    - The lease's `host_id` is the `var.web_hosts` key, verified against the host's own private IP. It is stable across recreate-deploys and host replaces.
    - Uniqueness holds because two live hosts cannot share a private IP.
    - A replaced host re-acquires its predecessor's leases at the same generation. That is safe only because `hcloud_server.web` has no `create_before_destroy` (pinned by Guard 2).
- `server/index.ts`, at boot next to `startProxyListenerReporter`, adds three lines:
  - one pino `warn` line, `host_identity source=<enum>`, carrying the enum only, never the id;
  - when `NODE_ENV=production`, the private IP is non-empty and the source is not `web-host-key`, one `reportSilentFallback` (`feature: "host_identity"`, `op: "resolveHostId.key-fallback"`, `extra: { source }`).
- `server/session-router.ts`: rewrite the roster doc comment. The roster maps the `var.web_hosts` key (= `resolveHostId()`) to the private-net address.
- Tests (vitest, one file at a time):
  - `test/host-identity.test.ts`, covering each `source`:
    - a valid, roster-verified key wins;
    - `Web_1`, a 33-character string or a UUID gives `key-malformed`;
    - a missing key gives `key-absent`;
    - a key whose roster address differs from `SOLEUR_HOST_PRIVATE_IP` gives `key-unverified` (the T1 collision case: `web-1` claimed on `10.0.1.11`);
    - an empty private IP (the canary) gives `key-unverified` and the instance id (T10);
    - production with nothing set throws; dev with nothing set gives `dev-local`.
  - One named test pins that `HOST_KEY_RE` MATCHES `hetzner-176328334`, so the regex alone never rejects an instance-id-keyed roster.
  - `test/session-router.test.ts`: add a production-shaped case with roster `{"web-1":"10.0.1.10","web-2":"10.0.1.11"}`. A holder `web-2` seen from `myHostId: "web-1"` proxies to `10.0.1.11`. A holder `hetzner-176328334` gives `owner-unresolved`. Keep the abstract `host-1`/`host-2` cases.

### Phase 2 — Inject the key at deploy (`infra/ci-deploy.sh`)

- Add `resolve_host_key()` next to `resolve_host_id`. Do not touch `resolve_host_id` or its two drift-guarded copies.
  - `curl -sf --max-time 3 "${SOLEUR_HOST_KEY_METADATA_URL:-http://169.254.169.254/hetzner/v1/metadata/hostname}"`, tried up to 3 times with a 1 s pause, with whitespace stripped. The endpoint is Hetzner's server metadata service. No repo script reads `hostname` today (only `instance-id` and `private-networks`), so the implementer confirms the path against Hetzner's server-metadata docs before writing the line.
  - The exact inverse of `server.tf`'s `name` expression:
    - `soleur-web-platform` maps to `web-1`;
    - `soleur-web-1` gives rc 1, because the census never names web-1 that way;
    - any other `soleur-<k>` gives `<k>`;
    - anything else gives rc 1.
  - The result must match `^[a-z][a-z0-9-]{0,30}$`, or the function returns 1.
- T3 stickiness, right after the resolve:
  - Read the running prod container's `SOLEUR_HOST_KEY` through `docker inspect`, env only, with the value kept in a local.
  - If it is non-empty and the new key is empty or different, emit the abort line and `exit 1` before the canary step. The serving container is left untouched.
  - If there is no running key (first rollout, fresh or replaced host), continue with whatever resolved, empty included.
- `HOST_KEY="$(resolve_host_key || true)"; readonly HOST_KEY`, set after `HOST_ID`.
- Prod `docker run`: add `-e SOLEUR_HOST_KEY="$HOST_KEY"` next to `-e SOLEUR_HOST_ID`. Canary `docker run`: add `-e SOLEUR_HOST_KEY=` (empty, T10).
- One `log_host_key` helper with a single `logger` call emits exactly one closed-grammar line per deploy:
  - `host_key resolved=<key>`;
  - `host_key resolved=fallback`;
  - `host_key resolved=abort reason=key_change`.
  It never prints the raw hostname.
- `infra/lib/docker-run-tuple.py`: `SOLEUR_HOST_KEY` needs a per-surface value (prod `{"$HOST_KEY"}`, canary empty), so it goes into the per-surface env sets, not `_COMMON_ENV`. The first-boot tuple is unchanged (see Non-Goals).
- Tests:
  - `infra/docker-run-tuple.test.sh`: kill rows mirroring K24c/K27c (prod missing `-e SOLEUR_HOST_KEY` gives `MISSING_DECLARED`), plus a canary row asserting the empty value. Bump any row-count floor the file keeps.
  - `infra/ci-deploy.test.sh`: unit-test `resolve_host_key` with a `file://` fixture URL under `mktemp -d` in `/var/tmp`.
    - `soleur-web-platform` gives `web-1`, and `soleur-web-2` gives `web-2`.
    - `soleur-web-1`, `inngest-host`, an empty file, `soleur-Web_2` and a dead URL each give rc 1.
    - Stickiness, with a stubbed `docker inspect`: running key `web-2` and new key `web-2` continue; running key `web-2` and new key empty abort with `reason=key_change`; no running key and new key empty continue.

### Phase 3 — The gate tests the runtime shape (`infra/lb-weight-gate.sh` A.3)

- New injected input `SOLEUR_WEB_HOSTS`, a JSON object mapping each `var.web_hosts` key to its `private_ip`.
  - `infra/lb-weight-gate-with-marker.sh` derives it from its own `$SELF_DIR/variables.tf`, from the `default = { ... }` block of `variable "web_hosts"`, using the one-host-per-line shape `web-hosts-generic.test.sh` already parses.
  - It sets the value unconditionally, overriding any caller value (the `MARKER_HOST` seam pattern).
  - Add the name to `GATE_ENV_ALLOW`. The wrapper's test re-derives that list from the gate's expansions.
  - The gate stays pure.
- New fail codes, evaluated after `A_web2_not_in_roster`. Each prints only the code.
  - `A_web_hosts_absent`: `SOLEUR_WEB_HOSTS` is unset, empty or not a JSON object.
  - `A_roster_key_not_web_host`: some roster key is not a `SOLEUR_WEB_HOSTS` key.
  - `A_roster_addr_mismatch`: some roster key's address differs from its `SOLEUR_WEB_HOSTS` value (`to_entries | all(.value == $w[.key])`, over EVERY key, not only the gated one).
  - `A_rotation_member_not_in_roster`: some `SOLEUR_SERVING_ROTATION` member is not a roster key.
- Leave the standby top-guard untouched. These checks run only on the pooling branch, so the #6575 "a correct standby config can only fail" flaw cannot return.
- Update the gate header's Condition A summary and the PARITY POINTER block. The roster key is `resolveHostId()`'s verified `var.web_hosts` key.
- `infra/lb-weight-gate.test.sh`: add `SOLEUR_WEB_HOSTS` to the default env and the Guard 1 rows. The web-3 must-PASS rows get a `SOLEUR_WEB_HOSTS` naming web-3. That is a deliberate fixture edit, not a weakening.
- `infra/lb-weight-gate-with-marker.test.sh`: the derived `SOLEUR_WEB_HOSTS` equals the committed defaults, and a caller-set value is overridden.

### Phase 4 — Narrow the pre-heal self-stop (`server/cc-dispatcher.ts`)

- Remove the `#5733 Phase 1b` emit from its pre-heal position.
- After the self-heal block, re-probe once (`probeGitWorktreeShape(workspacePath)`). Emit `reportAgentReadinessSelfStop` only when `repoUrl` is set and the re-probed shape is `file-pointer` with `gitdirEscapesWorkspace === true`.
  - Host `rev-parse` cannot see that strand, and the post-heal gate calls it ready.
  - An absent `.git` (the false-stop case) and a corrupt dir are left to the post-heal gate, which already emits with `gitRevParseValid` and throws `RepoNotReadyError`.
  - Keep the `host-pre-heal` source value. The dedupe fingerprint now carries `gitKind=file-pointer`, so it no longer collides with the post-heal absent emit.
- Rewrite the block comment to say this.
- Update the "3 emit sites" comment in `test/server/agent-ready-git-worktree.test.ts` to match `git grep -c 'reportAgentReadinessSelfStop(' apps/web-platform/server` after the edit.
- Tests, in the `cc-dispatcher-real-factory` harness or a new sibling `test/cc-dispatcher-cold-heal-no-self-stop.test.ts` if that harness is too heavy for a single-file run:
  - (a) A connected, DB-ready workspace with an absent `.git` and a successful heal emits zero `agent_readiness_self_stop` events and reaches the SDK query.
  - (b) In the same module instance after (a), a post-heal absent strand (the heal returns ok but `.git` stays absent) emits exactly once with `gitRevParseValid: false`. This is the dedupe-masking regression.
  - (c) A workspace whose post-heal shape is an escaping `file-pointer` emits exactly once with `gitKind: "file-pointer"`, `gitdirEscapesWorkspace: true`.
- `server/readiness.ts`: add a one-line comment on `isWorkspacesPopulated`. It counts the legacy `/workspaces` root, not `WORKTREE_ROOT`, so `0` on a host with no `/workspaces` data is expected.

### Phase 5 — Doppler: read-only precondition

The agent runs this before merge and again after both hosts redeploy. It prints booleans and key names only, never values:

```bash
doppler secrets get SOLEUR_HOST_ROSTER -p soleur -c prd --plain | jq -c '{keys: keys, web1_ok: (.["web-1"]=="10.0.1.10"), web2_ok: (.["web-2"]=="10.0.1.11"), n: length}'
```

Expected: `{"keys":["web-1","web-2"],"web1_ok":true,"web2_ok":true,"n":2}`, as measured on 2026-11-18. If any field is `false`, stop and escalate to the owner. The roster value is an owner-gated Doppler write, and the correct value is the committed `var.web_hosts` addresses. No owner step exists today, so the PR carries no Doppler hold.

### Phase 6 — Architecture record

Amend ADR-068 (via `soleur:architecture`) with an addendum, "2026-11-18 (#12910): the lease host_id is the verified var.web_hosts key". It covers:

- why the instance id was wrong (it changes on replace and does not match the roster);
- T1 self-verification, and that "same host" in migration 116 now means "same `var.web_hosts` slot";
- the generation carry across a replace, and its `create_before_destroy` precondition;
- an ADR-143 D5 precondition: stop the app before detach, so its leases are tombstoned;
- the transition cost: on first rollout and on any revert, a worktree whose live lease was taken under the other id waits out the 240 s liveness window, then a generation-bumped takeover follows;
- a link to `decision-challenges.md` for the rejected options. Do not restate them.

No new ADR is needed.

### Phase 7 — Post-merge delivery and proof

1. **Deliver (agent-run, T9).** Wait for the merge's `apply-deploy-pipeline-fix.yml` run to succeed, then run `gh workflow run web-platform-release.yml --ref main` on the merge SHA. Arm a watch on that run (`hr-dispatch-async-must-arm-watch`).
2. **Verify delivery (agent-run, Better Stack via `scripts/betterstack-query.sh`).**
   - On each host, `DEPLOY_SCRIPT_SHA` equals `sha256sum apps/web-platform/infra/ci-deploy.sh` at the merge SHA.
   - The deploys log `host_key resolved=web-1` and `host_key resolved=web-2`.
   - Each boot logs `host_identity source=web-host-key`.
   - If either host logs `fallback`, stop. web-2 stays at weight 0, and a new CTO ruling decides the next step (dissent: b1).
3. **Prove (owner-authorized serve).** Only after step 2 is green on both hosts, the owner authorizes one `cf-lb-overlay.yml` serve dispatch (`Operator-authorizes:`).
   - The agent places a turn on web-2 by opening a chat session for a user whose lease is held on web-2, or a cold user routed by the LB.
   - The agent then reads the AC13 rows.
4. **Drain back** to weight 0, if the owner wants it. That is the owner's separate dispatch.

## Files to Edit

- `apps/web-platform/server/host-identity.ts`: `HOST_KEY_RE`, `describeHostIdentity`, verified `resolveHostId`, header comment.
- `apps/web-platform/server/session-router.ts`: re-export `loadHostRoster` from `host-roster.ts`; rewrite the doc comment.
- `apps/web-platform/server/index.ts`: boot `host_identity` line and production fallback report.
- `apps/web-platform/server/cc-dispatcher.ts`: narrow the self-stop emit to a post-heal escaping file-pointer.
- `apps/web-platform/server/readiness.ts`: one-line comment.
- `apps/web-platform/infra/ci-deploy.sh`: `resolve_host_key` (with retry), stickiness abort, `HOST_KEY`, the prod and canary `-e SOLEUR_HOST_KEY`, `log_host_key`.
- `apps/web-platform/infra/lib/docker-run-tuple.py`: per-surface `SOLEUR_HOST_KEY`.
- `apps/web-platform/infra/lb-weight-gate.sh`: four A.3 codes and header/parity comment.
- `apps/web-platform/infra/lb-weight-gate-with-marker.sh`: derive and allowlist `SOLEUR_WEB_HOSTS`.
- Tests:
  - `apps/web-platform/test/host-identity.test.ts`
  - `apps/web-platform/test/session-router.test.ts`
  - `apps/web-platform/test/server/agent-ready-git-worktree.test.ts` (comment only)
  - `apps/web-platform/infra/ci-deploy.test.sh`
  - `apps/web-platform/infra/docker-run-tuple.test.sh`
  - `apps/web-platform/infra/lb-weight-gate.test.sh`
  - `apps/web-platform/infra/lb-weight-gate-with-marker.test.sh`
  - `apps/web-platform/infra/web-hosts-generic.test.sh` (Guard 2, section C8)
- `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md`: addendum.

## Files to Create

- `apps/web-platform/server/host-roster.ts`: the pure roster parse, as a leaf.
- `apps/web-platform/test/cc-dispatcher-cold-heal-no-self-stop.test.ts`, only if the real-factory harness cannot host the three Phase 4 cases in a single-file run.
- `knowledge-base/project/specs/feat-one-shot-12910-host-roster-lease-id/decision-challenges.md` (written at plan time).

## Open Code-Review Overlap

Two open scope-outs touch `apps/web-platform/server/cc-dispatcher.ts`: #3243 (decompose cc-dispatcher.ts) and #3242 (the tool_use WS event lacks a raw name field). **Acknowledge** both. This plan moves and narrows one ~12-line block and has nothing to do with decomposition or the WS event shape. Neither is touched. No other planned file appears in an open code-review issue.

## Non-Goals

- Generating the roster or allowlist from Terraform (census C6): tracked in #12919. The new A.3 checks retire when it lands.
- Adding `SOLEUR_HOST_KEY` to the first-boot cloud-init tuple. It carries no `SOLEUR_HOST_ID` either, a host is pooled only after a `ci-deploy.sh` run, and cloud-init cannot reach web-1 (`ignore_changes = [user_data]`).
- Relabelling or re-rooting `workspaces_populated`. It is "recorded, not judged" (owner ruling, 2026-11-06).
- Any serve or drain dispatch, Doppler write or host replace (owner-gated).
- #12330, #11694, #11676, #11669 and #10476.

## Alternative Approaches Considered

| Option | Verdict |
|---|---|
| (a) Key the roster by Hetzner instance id | Rejected: needs a Doppler write on every replace, which is the failure that just happened |
| (b1) Use the roster key whose address is the host's own private IP as the id | Not the id source. Its check is adopted as the T1 verifier on top of (b2) |
| (b2) Metadata hostname inverted through `server.tf`'s name expression | **Chosen**, verified by T1 and made sticky by T3 |
| (b3) A cloud-init-written key file | Rejected: cannot reach web-1 (`ignore_changes = [user_data]`) |
| (c) A lookup that accepts both shapes | Rejected: the router has no source mapping an instance id to a key |
| (d) Record the owner's address on the lease row | Rejected: a hot-path migration that buys nothing over (b2) |
| Split the PR (inject first, consume second) | Rejected (T2): with T1, a wrong or missing key degrades to today's id |
| An on-host last-good key file | Rejected (T3): the running container is the last-good record and cannot go stale across a replace |
| Cut the gate additions (simplicity review) | Rejected (T5): `has($HOST)` passes a wrong address |
| Delete the pre-heal emit outright (first-draft R3) | Superseded (T8): narrowed instead, to keep the escaping file-pointer record |

## Hypotheses

Defect 2, with the discriminating datum for each (measured 2026-11-18):

| # | Hypothesis | Discriminator | Status |
|---|---|---|---|
| H1 | A cold first turn: the pre-heal emit fires, then the heal succeeds and the turn runs | SDK query and usage rows from the same process after the emit; no post-heal or clone-failure row | **CONFIRMED**: 12:47:54 canUseTool, 12:47:58 cc-persist-usage-on, 12:48:17 cc_queries=1 |
| H2 | The clone failed on web-2 | a `repo-clone-failed`/`ensure-workspace-repo` error row | Refuted: no such row from 12:44 to 12:58 |
| H3 | `installationId` is null, so the heal silently no-ops and the post-heal gate blocks | a post-heal emit with `gitRevParseValid`; `RepoNotReadyError` | Refuted: neither row present, and the query ran |
| H4 | A lease or route race: web-2 served cold while web-1 held the lease | a `worktree_lease` "held by another host" row | Refuted: web-2 itself held the lease at 12:55 |

## Infrastructure (IaC)

### Terraform changes

None. No `.tf` file changes. `variables.tf` and `server.tf` are read by the gate wrapper and the tests, not edited.

### Apply path

The merge triggers two unordered workflows:

- `apply-deploy-pipeline-fix.yml` pushes the new `ci-deploy.sh` to both hosts (`terraform_data`, with web-1 and web-2 siblings). A script-only apply does not swap the container.
- `web-platform-release.yml` deploys the new image. If it runs before the apply, the new image boots under the old script with no `SOLEUR_HOST_KEY` and resolves `key-absent`, which is today's id. That is benign under T1.

Phase 7 step 1 then sequences one release redeploy after the apply.

**Does merging this alone mutate production?** Yes. The first release deploy that runs under the new script changes each prod container's placement id from `hetzner-<id>` to `web-<n>`. The authorization is the merge plus the agent-run redeploy (T9), not an owner dispatch. The blast radius: a worktree whose live lease was taken under the old id waits out the 240 s liveness window once. There are no external users today.

### Host fan-out

`ci-deploy.sh` reaches both web hosts through `apply-deploy-pipeline-fix.yml`, and each host runs it on every release deploy. No SSH provisioner changes. Delivery is verified through the on-host `DEPLOY_SCRIPT_SHA` line, not assumed.

### Distinctness / drift safeguards

- `resolve_host_id` and its two drift-guarded copies stay byte-identical.
- Key derivation is pinned by Guard 2, and uniqueness by T1 at runtime.
- The roster stays a hand-kept Doppler value (census C6, #12919).

### Vendor-tier reality check

The Hetzner metadata service is free and already used by `resolve_host_id`.

## Observability

```yaml
liveness_signal:
  what: "one `host_key resolved=<key|fallback|abort>` journald line per deploy (ci-deploy.sh log_host_key, LOG_TAG) and one `host_identity source=<enum>` pino line per container boot (server/index.ts)"
  cadence: "per deploy and per container boot"
  alert_target: "Sentry web-platform issue on a production fallback (feature host_identity, op resolveHostId.key-fallback, extra.source); the existing control_plane_route owner-unresolved Sentry issue"
  configured_in: "apps/web-platform/infra/ci-deploy.sh (log_host_key, called once after resolve_host_key); apps/web-platform/server/index.ts (boot, next to startProxyListenerReporter)"
error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN (reportSilentFallback)"
  fail_loud: "resolveHostId.key-fallback with extra.source key-absent/key-malformed/key-unverified; resolveSessionRoute.owner-unresolved (extra ownerHostId + myHostId, already on main); deploy exit 1 with host_key resolved=abort reason=key_change; lb-weight-gate gate_fail sub_condition=A_web_hosts_absent / A_roster_key_not_web_host / A_roster_addr_mismatch / A_rotation_member_not_in_roster"
failure_modes:
  - mode: "metadata hostname unreachable or unmapped on first rollout, so the placement id stays hetzner-<id>"
    detection: "deploy line `host_key resolved=fallback` plus the boot Sentry event resolveHostId.key-fallback source=key-absent, both from the affected host"
    alert_route: "Sentry issue to the operator; Phase 7 step 2 stops before any serve"
  - mode: "metadata flips on a later deploy for a host already keyed"
    detection: "deploy exits 1 before the canary with `host_key resolved=abort reason=key_change`; web-platform-release run fails"
    alert_route: "GitHub Actions run failure"
  - mode: "a key that does not verify against the host's own private IP (wrong hostname, wrong roster, mis-set env)"
    detection: "boot Sentry event resolveHostId.key-fallback source=key-unverified"
    alert_route: "Sentry issue to the operator"
  - mode: "roster drifts from var.web_hosts before a serve"
    detection: "cf-lb-overlay serve run fails the gate with a named sub_condition"
    alert_route: "GitHub Actions run failure"
  - mode: "a post-heal escaping file-pointer strand, or a post-heal absent strand"
    detection: "agent_readiness_self_stop gitKind=file-pointer gitdirEscapesWorkspace=true, or gitRevParseValid=false from the post-heal gate, no longer masked"
    alert_route: "Sentry issue to the operator"
logs:
  where: "journald, then Vector, then Better Stack (host lines); pino container stdout, then Better Stack; Sentry"
  retention: "Better Stack hot window plus S3 archive; Sentry default"
discoverability_test:
  command: "grep -c -e logger.*host_key.resolved= apps/web-platform/infra/ci-deploy.sh"
  expected_output: "1"
```

## Guard Contract

### Guard 1 — lb-weight-gate A.3 runtime-shape checks

**Property.** The serve gate refuses to pool a gated host unless every roster key is a committed `var.web_hosts` key mapped to its committed private IP, and every serving-rotation member is in the roster. The gate passes only a roster under which `resolveHostAddress(resolveHostId())` resolves for every pooled host.

**Assembly.** One chokepoint: the A.3 block of `apps/web-platform/infra/lb-weight-gate.sh`, reached only on the pooling branch after the top-guard. It reads `SOLEUR_HOST_ROSTER` (Doppler prd), `SOLEUR_SERVING_ROTATION` (workflow-injected) and `SOLEUR_WEB_HOSTS`. That last input has one producer, `lb-weight-gate-with-marker.sh`, which reads the committed `variables.tf`. The wrapper's `GATE_ENV_ALLOW` is the only path into the gate.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Roster `{"web-1":"10.0.1.10","web-2":"10.0.1.11","hetzner-176328334":"10.0.1.11"}`, `SOLEUR_GATED_HOST=web-2` | RED `A_roster_key_not_web_host` |
| 2 | Delete the body of the `A_roster_key_not_web_host` loop, so it iterates and never fails (the guard's own dispatch) | suite RED on row 1 |
| 3 | Roster with a compliant `web-1` key followed by a second key `web-9` not in `var.web_hosts` (the second member after a compliant first) | RED `A_roster_key_not_web_host` |
| 4 | `web-1` mapped to `10.0.1.99` while `web-2` is correct (a non-gated key's address) | RED `A_roster_addr_mismatch` |
| 5 | `web-2` mapped to `10.0.1.10` | RED `A_roster_addr_mismatch` |
| 6 | `SOLEUR_SERVING_ROTATION=web-1,web-2,web-3` with a roster lacking `web-3` | RED `A_rotation_member_not_in_roster` |
| 7 | The wrapper stops deriving `SOLEUR_WEB_HOSTS` | RED `A_web_hosts_absent` |
| 8 | Standby (weight 0, not in rotation) with `SOLEUR_WEB_HOSTS` unset | PASS (standby branch untouched; #6575 does not return) |

A must-PASS input that is not the canonical fixture: a roster carrying `web-1`, `web-2` and `web-3` with matching addresses, `SOLEUR_WEB_HOSTS` naming all three, and `SOLEUR_GATED_HOST=web-3`.

Anchor: `SOLEUR_WEB_HOSTS` comes from the committed `variables.tf`, so weakening it means editing `var.web_hosts`, which plans Terraform changes on the per-merge apply. The roster comes from Doppler, outside the commit.

### Guard 2 — placement-id parity (`web-hosts-generic.test.sh` section C8)

**Property.** For every key in the committed `var.web_hosts` default, the server name `server.tf` assigns, fed through `ci-deploy.sh`'s `resolve_host_key`, returns that same key. The key regexes in `host-identity.ts` and `lb-weight-gate.sh` are identical. `hcloud_server.web` carries no `create_before_destroy`.

**Assembly.** The guard is a census over every `var.web_hosts` key and draws on four sources:

- the `name = ...` expression of `resource "hcloud_server" "web"` in `server.tf`, and that resource's `lifecycle` block;
- the `resolve_host_key` body extracted from `ci-deploy.sh` (awk `extract_fn_body`, as in `inngest-inventory.test.sh`), run against a `file://` fixture;
- the `HOST_KEY_RE` literal in `server/host-identity.ts`;
- the key regex in `lb-weight-gate.sh` (`TOP_gated_host_malformed`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change `server.tf`'s name expression to `"soleur-host-${each.key}"` | RED (round-trip returns no key) |
| 2 | The census loop finds zero `var.web_hosts` keys (the parse breaks), the guard's own dispatch | RED (floor: at least 2 keys checked) |
| 3 | Add `"web-3"` to `var.web_hosts` after the compliant web-1 and web-2 | PASS if web-3 round-trips; RED on web-3 if `resolve_host_key`'s `case` handles only `web-2` by name |
| 4 | Change `HOST_KEY_RE` so it differs from the gate's regex | RED |
| 5 | Delete the `soleur-web-platform` arm, or let `soleur-web-1` map to `web-1` | RED |
| 6 | Add `create_before_destroy = true` to `hcloud_server.web`'s lifecycle | RED |

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-068 (host identity, §2) with the Phase 6 addendum. No new ADR ordinal.

### C4 views

No C4 change. Checked against all three model files (`model.c4`, `views.c4`, `spec.c4`):

- (a) No external human actor is added or changed.
- (b) The only system read for the first time is the Hetzner metadata `hostname` endpoint, which belongs to the already-modelled `hetzner` "Compute" container (`resolve_host_id` already calls its metadata service).
- (c) The containers touched are the already-modelled Session Router and Compute. The Session Router's description names neither the roster key nor the host id.
- (d) No actor-to-surface access relationship changes.

`plugins/soleur/test/c4-count-parity.test.sh` ran green (13 passed, 0 failed) on 2026-11-18.

### Sequencing

Lands in this PR.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "The roster key and the lease host id agree" [issue #12910] | Phases 1-2 (verified `resolveHostId`; `resolve_host_key`) | mapped |
| 2 | "the A.3 gate check tests the shape the runtime reads" [issue #12910] | Phase 3; Guard 1; Guard 2 | mapped |
| 3 | "a turn placed on web-2 runs" [issue #12910] | Phase 4; Phase 7 step 3; Hypotheses H1 | mapped |
| 4 | "the owner host logs `relay_hello_window accepted=<n>` with `n>0` (AC-P3 of the relay hello plan)" [issue #12910] | Phase 7 step 3 | mapped |
| 5 | "The roster value itself is a Doppler prd write (owner-gated): prepare the exact value/command, do not write it." [brief] | Phase 5 | mapped |
| 6 | "fix the key by (a) ... (b) ... or (c) ...; and how the lb-weight-gate.sh A.3 check must assert the runtime shape" [brief] | Decisions R1, R2, T1-T5 | mapped |
| 7 | "For (2), determine whether web-2 is expected to materialize the workspace from the git-data store on first turn (host-pre-heal) and why it reports absent." [brief] | Research Insights (Defect 2); Hypotheses; Decisions T8 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `server/host-identity.ts`, `server/host-roster.ts`, `server/index.ts` | asks 1, 6 | asked |
| `infra/ci-deploy.sh`, `infra/lib/docker-run-tuple.py` | ask 1 | asked |
| T3 stickiness abort | ask 1 ("agree", which must hold on every deploy, not once) | asked |
| `infra/lb-weight-gate.sh`, `infra/lb-weight-gate-with-marker.sh` | ask 2 | asked |
| `server/cc-dispatcher.ts` emit narrowing | asks 3, 7 | asked |
| `server/readiness.ts` comment | ask 7 ("why it reports absent" / `workspaces_populated=0`) | asked |
| Guard 2 parity test | ask 2 | asked |
| ADR-068 addendum | — | inferred — justification: the plan changes the lease's host identity, an architectural decision (wg-architecture-decision-is-a-plan-deliverable) |
| Phase 5 read-only precondition | ask 5 | asked |
| Phase 7 delivery and proof | asks 3, 4 | asked |
| Deferral issue #12919 | — | inferred — justification: wg-when-deferring-a-capability-create-a |

### Split Assessment

- Subsystems touched: 2 (`apps/web-platform`, `knowledge-base`).
- Planned files: 21. Estimated changed lines: ~600, mostly tests.
- Thresholds: 4 or more subsystem roots, OR more than 25 planned files, OR more than 800 estimated lines.
- Recommendation: single PR (also ruled T2).

## User-Brand Impact

- **If this lands broken, the user experiences:** in `/dashboard/chat` on app.soleur.ai, a chat connection that lands on the host not holding their lease is closed (`ROUTING_UNAVAILABLE`, a reconnect loop) while web-2 serves. In the worst case, two hosts claim the same placement id and both write to the user's workspace under the same lease generation, losing commits in their repository. T1's self-verification exists to make that case unreachable.
- **Even when it lands correctly, the transition deploy can:** block a user's chat for up to 240 s if their lease was live under the old id when the container swapped. The lease acquire throws `ERR_WORKTREE_LEASE_UNAVAILABLE`, not a wait. This happens once on rollout and once more on any revert.
- **If this leaks, the user's workflow is exposed via:** a mis-resolved roster entry relaying their authenticated session to the wrong peer. Owner-side AP-2 membership re-verification and the HMAC-signed hello (ADR-323) still bound it. No secret or user id is added to any log line: the new lines carry enum words and `web-<n>` keys only.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the change moves the write-lease identity that fences writes to one user's repository. A collision is a silent data-loss event for that user, which is above `aggregate pattern`.

CPO sign-off was given on 2026-11-18, with conditions (see Domain Review). `soleur:engineering:review:user-impact-reviewer` runs at review.

## Acceptance Criteria

### Pre-merge

- [ ] AC1: `describeHostIdentity()` returns each `source` as specified in Phase 1, including `key-unverified` for `SOLEUR_HOST_KEY=web-1` with `SOLEUR_HOST_PRIVATE_IP=10.0.1.11`, and the instance id for an empty private IP (canary). `resolveHostId()` equals `describeHostIdentity().id`. Production with nothing set still throws (`test/host-identity.test.ts`).
- [ ] AC2: with roster `{"web-1":"10.0.1.10","web-2":"10.0.1.11"}`, a `web-2` holder seen from `web-1` gives `{decision:"proxy", ownerAddress:"10.0.1.11"}`, and a `hetzner-176328334` holder gives `owner-unresolved` (`test/session-router.test.ts`).
- [ ] AC3: `resolve_host_key` maps `soleur-web-platform` to `web-1` and `soleur-web-2` to `web-2`. It returns rc 1 for `soleur-web-1`, an unmapped name, an empty body, a malformed key and an unreachable URL, and the stickiness cases behave as in Phase 2 (`infra/ci-deploy.test.sh`).
- [ ] AC4: the prod `docker run` carries `-e SOLEUR_HOST_KEY="$HOST_KEY"` and the canary carries `-e SOLEUR_HOST_KEY=`. The new kill rows go RED when either is deleted (`infra/docker-run-tuple.test.sh`).
- [ ] AC5: Guard 1 rows 1-8 and the must-PASS row behave as specified (`infra/lb-weight-gate.test.sh`, `infra/lb-weight-gate-with-marker.test.sh`).
- [ ] AC6: Guard 2 rows 1-6 behave as specified, and the anti-vacuity floor is raised by the new assertion count (`infra/web-hosts-generic.test.sh`).
- [ ] AC7: Phase 4 tests (a), (b) and (c) pass, and the pre-heal-position emit is gone (`git grep -n 'Fires BEFORE the heal' apps/web-platform/server/cc-dispatcher.ts` returns nothing).
- [ ] AC8: `resolve_host_id` in `ci-deploy.sh`, `cat-deploy-state.sh` and `inngest-inventory.sh` is unchanged. `git diff origin/main -- apps/web-platform/infra/cat-deploy-state.sh apps/web-platform/infra/inngest-inventory.sh` is empty, and `inngest-inventory.test.sh` "#6425 AC4" passes.
- [ ] AC9: the Phase 5 read prints `{"keys":["web-1","web-2"],"web1_ok":true,"web2_ok":true,"n":2}` on the day of merge.
- [ ] AC10: `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch` passes.
- [ ] AC11: the ADR-068 addendum exists, names #12910, and states the 240 s transition cost and the `create_before_destroy` precondition.

### Post-merge (the agent runs the reads and the T9 redeploy; the owner authorizes the serve dispatch)

- [ ] AC12: after the pipeline-fix apply and the T9 redeploy, Better Stack shows each host's `DEPLOY_SCRIPT_SHA` equal to the merged `ci-deploy.sh` sha256, `host_key resolved=web-1` from web-1, `host_key resolved=web-2` from web-2, and `host_identity source=web-host-key` from each boot.
- [ ] AC12b (CPO condition): web-2 stays at weight 0, and the serve dispatch is not requested, until AC12 holds on BOTH hosts with no `fallback`.
- [ ] AC13: after the owner-authorized serve dispatch, the deciding evidence is positive rows, not the absence of an emit:
  - a cold turn on web-2 reaches `cc_queries>=1`, with `cc-persist-usage-on` from the same process;
  - the owner host logs `relay_hello_window accepted=<n>` with `n>0` (#8211 AC-P3).

  Supporting negative checks: no post-heal `agent_readiness_self_stop` for that turn, and no `resolveSessionRoute.owner-unresolved` row for the cross-host connection.

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed
**Assessment:** the CTO agent ruled R1-R4 and, on the plan-review findings, T1-T11 (2026-11-18). The binding constraints:

- `resolveHostId()` is the single chokepoint, and it verifies the key against the host's own private IP.
- The key is sticky across deploys.
- The gate checks every roster key and every rotation member.
- The pre-heal emit is narrowed to the escaping file-pointer case.
- No Doppler write is needed.
- Delivery is sequenced after the pipeline-fix apply.

### Product

**Status:** reviewed
**Assessment:** CPO sign-off (2026-11-18): approved with conditions. All three are folded in:

1. The transition-deploy 240 s block is in User-Brand Impact.
2. web-2 stays at weight 0 until both hosts log `resolved=web-<n>` (AC12b).
3. AC13 decides on `cc_queries>=1` and `relay_hello_window accepted>0`.

The CPO also noted that #12910 and #8211 are p1 but sit in "Post-MVP / Later". Reconcile that at the next roadmap pass.

### Product/UX Gate

**Tier:** none (no UI surface: no file under `components/**` or `app/**`).

### Plan review (2026-11-18)

A 5-agent panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer) reviewed the plan, plus the Step 4.5 advisor consult.

- Mechanical findings were applied:
  - the delivery-race reconciliation;
  - Better Stack `host_name` removed as evidence;
  - a non-gated-key address row;
  - a test for the escaping-pointer shape;
  - the `logger`-anchored discoverability grep;
  - the 240 s figure (not 120 s) confirmed from `LEASE_LIVENESS_WINDOW_MS`.
- The technical forks were ruled by the CTO as T1-T11.
- No taste or user-challenge findings remained.

## Test Scenarios

Covered per phase:

- Phase 1: host-identity sources, router resolution.
- Phase 2: `resolve_host_key`, stickiness, tuple kill rows.
- Phase 3: Guard 1.
- The Guard 2 census.
- Phase 4: a cold heal emits nothing; a genuine post-heal strand is not masked; an escaping pointer emits once.

Run each file alone. The full suite is not run on this saturated machine.

## Rollback

1. Return web-2 to weight 0 first, if it is serving. That is the owner's drain dispatch.
2. Open a revert PR (`gh pr create --fill` on a revert branch) and merge it with the same `with_lock merge-main` command.
3. After the revert's pipeline-fix apply succeeds, run the same T9 redeploy and verify `DEPLOY_SCRIPT_SHA` again.

Placement ids return to `hetzner-<id>`. Live leases taken under `web-<n>` then wait out the 240 s window once. Do not roll back the image alone: an old image under the new script ignores `SOLEUR_HOST_KEY`, which is harmless, but the T3 abort would then compare against containers carrying no key and never fire. Reverting both together keeps the record consistent.

## Risks

- **Metadata `hostname` on web-1 is unverified.** web-1 is a pre-existing host, and the endpoint has no reader in the repo yet. Falsifier: AC12's `host_key resolved=web-1`. If it says `fallback`, web-1 keeps a unique `hetzner-*` id (T1), lease exclusivity holds, and Phase 7 stops before any serve, pending a new CTO ruling.
- **Generation carry across a replace.** A replaced host re-acquires its predecessor's leases without a generation bump. That is safe only while `hcloud_server.web` has no `create_before_destroy` (Guard 2 row 6) and the app is stopped before detach (ADR-143 D5 precondition, recorded in the addendum).
- **Transition deploy.** A lease live under the old id blocks its user for up to 240 s. Until it expires, a peer reports `owner-unresolved` for that holder.
- **T3 abort blocks a release.** If metadata stays down on a keyed host, every deploy to it aborts until metadata recovers. This is deliberate: a correctly keyed container keeps serving, rather than the deploy re-creating the incident.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds only `TBD`/`TODO`/placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6.
- `HOST_KEY_RE` matches `hetzner-176328334`. Only the subset check against `var.web_hosts` keys (Guard 1) and the T1 address verification reject an instance-id key. Never "simplify" either down to the regex.
- `host-identity.ts` imports only the env-only leaves `host-roster.ts` and `host-private-ip.ts`. Adding any other `server/` import to it breaks the leaf discipline `host-private-ip.ts` documents.
- `decision-challenges.md` rows are machine-gated (`technical-ruling-gate.sh`): the exact header `| Item | Class | Ruling |`, three cells, and no literal `|` inside a cell.
- The `discoverability_test` command avoids `|`, `$`, `;`, `&`, `<` and `>` for preflight Check 10, and anchors on `logger` so a comment cannot change the count.
