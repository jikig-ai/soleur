---
title: "fix: git-data store accepts pushes/fetches from shallow workspace clones (#8211 fix-forward 2)"
type: fix
date: 2026-10-27
slug: fix-git-data-store-shallow-push
branch: feat-one-shot-8211-git-data-shallow-push
issue: 8211
closes: []
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: git-data store accepts pushes/fetches from shallow workspace clones (#8211 fix-forward 2)

## Enhancement Summary

**Deepened on:** 2026-10-27
**Sections enhanced:** Hypotheses (Network-Outage Deep-Dive L3→L7), Technical Considerations (pin inventory, retry/fetch shapes), Observability (discoverability literal corrected)
**Research agents used:** none — this harness has no Task/agent spawning; the deepen pass ran its halt gates in-process (4.5 deep-dive written, 4.6 user-brand present at `single-user incident`, 4.7 observability validated — including the `expected_output: "2"` literal fix, 4.8 PAT-clean, 4.9 no UI surface, 4.10 encryption posture present, 4.11 `lint-guard-contract.py` green (2 entries), 4.12 Scope Check single unfenced section with all rows mapped/justified, 4.13 no new autonomous task) plus the precedent-diff and verify-the-negative greps below.

### Key Improvements

1. Exec-line pin inventory (3 sites incl. the production fence probe `git-data-cutover.sh:689`) drove the conditional-branch design that keeps every existing pin green — the fix-forward's own defect class caught at design time.
2. Merge-safety proof enumerated every apply surface (push-apply allow-list, post-bridge `terraform_data` targets, dispatch-only git-data jobs, drift workflow) — merging cannot auto-replace `hcloud_server.git_data` or its volumes.
3. Retry shaped as a positive-match classifier reading `err.stderr ?? err.message` (the actual execFile rejection surface), never a blanket retry — per the 2026-09-21 retry-flag learning.

### New Considerations Discovered

- `git-data-transport-wrapper.test.sh` (T2/T11 + exact floor) must co-change with the wrapper — a file the brief did not name but the pin structure requires.
- `err.stderr` (not only `err.message`) is the surface the transient match must read — the execFile rejection puts git's stderr there.
- Parked: shallowUpdate's `.git/shallow` writability under the shared tree routes to security-sentinel at review (Non-Goal recorded, no issue filed per the brief).

## Overview

The R3 rehearsal re-run (2026-10-27, window 16:27-16:31Z) FAILED: the session-end replication push was rejected with `! [remote rejected] main -> refs/soleur/worktrees/<id>/heads/main (shallow update not allowed)` — a clean Better Stack `git-data replication push failed` hit on web-1 at 16:30:17Z. No `replication shed`, no overlay-fallback hits. The synthetic session ran and ended; R4 stays blocked because the verdict is not SESSION-ENDED.

Root cause (CTO RULING 2026-10-27, do not re-litigate): the workspace clone is always `--depth 1` (`apps/web-platform/server/ensure-workspace-repo.ts:476` — `["clone", "--depth", "1", "--", repoUrl, tmp]`) and the store is a plain `git init --bare` (`apps/web-platform/infra/git-data-provision.sh:143`) whose forced-command receive-pack runs without `receive.shallowUpdate`. Decision: make the store accept shallow pushes; do NOT unshallow the clone (ADR-099 rejected the bare/collapse alternative; ADR-068 lists `--unshallow` as a LOW post-GA follow-up only).

This is the second fix-forward on the #8211 flag-on window; the first (PR #11285, the remote-URL path fix) merged 2026-10-27.

## Problem Statement / Motivation

A shallow client's push makes `git receive-pack` want to write `.git/shallow` on the receiving repo; `git help config` on this repo's git 2.56.0 documents `receive.shallowUpdate`: "If set to true, .git/shallow can be updated when new refs require new shallow roots. Otherwise those refs are rejected." The store rejects every push from the app's workspace clones, so session-end replication can never land and the cutover rehearsal cannot reach SESSION-ENDED.

Two adjacent gaps compound it: the session-start overlay fetch runs `git fetch` without `--update-shallow`, so it "refuses refs that require updating .git/shallow" (`git fetch --help`) and silently creates no ref — the `show-ref --verify` fallback in `ensure-workspace-repo.ts:356-374` then keeps the GitHub clone with no log distinguishing "empty store" from "refused fetch". And a first push of 2+ refs from a shallow clone can hit the transient `remote failure` / `failed to report status` class, which today fails the push outright.

## Proposed Solution

Three surgical changes, exactly as ruled:

1. **Store accepts shallow pushes (host-side, cloud-init-baked).** In `apps/web-platform/infra/git-data-transport-wrapper.sh`, add `-c receive.shallowUpdate=true` to the `git receive-pack` exec argv ONLY — the upload-pack argv stays byte-identical. The wrapper has ONE exec line today (`git-data-transport-wrapper.sh:138`); the implementation keeps that line verbatim as the non-receive-pack (else) branch and adds a conditional receive-pack branch carrying the flag — see Technical Considerations for why this shape preserves every existing pin. The test-only DRYRUN echo (`:132-135`) must mirror the same conditional argv.
2. **Overlay fetch accepts shallow-boundary updates (app-side).** In `apps/web-platform/server/git-data-client.ts:250`, insert `"--update-shallow"` immediately after `"fetch"` in the argv passed to `gitWithPrivateKeyAuth`.
3. **One transient retry on the push (app-side).** In `apps/web-platform/server/git-data-replication.ts:788-801`, retry the `gitWithPrivateKeyAuth` push ONCE when the failure's stderr/message matches `remote failure|failed to report status`. Never retry on `shallow update not allowed` or on a fence reject (`stale lease generation` / `remote: git-data fence:`) — those are deterministic. The retry is safe: the fence accepts an equal lease-gen, so a resent push is idempotent.

The wrapper is baked into cloud-init (`modules/git-data-userdata/main.tf:98` embeds the file into `user_data`), so the host-side half of fix 1 reaches production ONLY through the owner-gated `git-data-host-replace` dispatch — this PR merging changes no live host (proof under `## Infrastructure (IaC)`).

## Technical Considerations

### Exec-line pin inventory (the reason for the conditional shape)

The literal `exec git -c "core.hooksPath=${HOOKS_DIR}" "${verb#git-}" "$repo_real"` is pinned in three places that all survive this change unchanged **iff** the generic line is preserved verbatim:

- `apps/web-platform/infra/git-data-cutover.sh:689` — `pin_ex` in the PRODUCTION fence-intactness probe (`refuse_if_fence_not_intact`, `:676-735`): an SSH one-liner greps the live host's wrapper with `grep -qxF` (exact line) for `pin_hd` AND `pin_ex`, exiting 18 (`transport_pin_mismatch`) if absent. Keeping the generic line as the else-branch keeps this probe green with zero probe changes.
- `apps/web-platform/infra/git-data-transport-wrapper.test.sh:235` — T11's literal `grep -qE '^exec git -c "core\.hooksPath=\$\{HOOKS_DIR\}" "\$\{verb#git-\}" "\$repo_real"$'` pins the exec form.
- `apps/web-platform/infra/git-data-cutover-access.test.sh:1345` — P2 parity pins the probe's `pin_ex` against the wrapper file (and its mutation arms `sed -i '/^exec git -c "core.hooksPath=/d'` at `:1235`/`:4007` still delete every `exec git -c "core.hooksPath=…` line, including the new branch — the mutation stays valid).

### Target shape

```bash
if [ "${GIT_DATA_TRANSPORT_EXEC_DRYRUN:-0}" = "1" ]; then
  if [ "$verb" = "git-receive-pack" ]; then
    echo "DRYRUN-EXEC git -c core.hooksPath=${HOOKS_DIR} -c receive.shallowUpdate=true receive-pack ${repo_real}"
  else
    echo "DRYRUN-EXEC git -c core.hooksPath=${HOOKS_DIR} ${verb#git-} ${repo_real}"
  fi
  exit 0
fi

if [ "$verb" = "git-receive-pack" ]; then
  exec git -c "core.hooksPath=${HOOKS_DIR}" -c receive.shallowUpdate=true receive-pack "$repo_real"
fi
exec git -c "core.hooksPath=${HOOKS_DIR}" "${verb#git-}" "$repo_real"
```

The comment block at `:125-131` (the "FENCE IS PINNED ON THE COMMAND LINE" rationale) gains one paragraph: `receive.shallowUpdate` rides the same `-c` scope — a repo-local config is git-writable, so the flag is pinned on the command line where nothing under the repo can drop it; and it is receive-pack-only because shallow updates are a receive-side concern (upload-pack ignores it, and the ruling keeps the read argv untouched).

`receive.shallowUpdate` semantics worth recording: the flag lets the SERVER's `.git/shallow` gain roots — a push under the shared tree can rewrite the repo's shallow file (availability impact only; parked Non-Goal routed to security-sentinel at review).

### Retry shape

Wrap only the push call (`git-data-replication.ts:788-801`) — not provision, not `ensureGitDataRemote`:

```ts
via = "git";
const pushArgs = [ /* existing argv unchanged */ ];
try {
  await gitWithPrivateKeyAuth(pushArgs, transportKey, hostKeyPin, { cwd: workspacePath, timeout: 60_000 });
} catch (pushErr) {
  const stderr = String((pushErr as { stderr?: string })?.stderr ?? (pushErr as Error)?.message ?? "");
  if (!/remote failure|failed to report status/.test(stderr)) throw pushErr;
  await gitWithPrivateKeyAuth(pushArgs, transportKey, hostKeyPin, { cwd: workspacePath, timeout: 60_000 });
}
```

The match is a POSITIVE list, so `shallow update not allowed` and `remote: git-data fence: stale lease generation` fall through to `throw` — the "do not retry" ruling is structural, not a second regex to maintain. `gitWithPrivateKeyAuth` rejects with the execFile error, whose `.stderr` carries git's stderr (the remote's lines ride stderr); `err.message` is the fallback surface. No retry precedent exists in this module — pattern is novel here (precedent-diff noted for review).

### Fetch semantics

`git fetch --update-shallow` (verified: `git fetch --help`, git 2.56.0): "By default when fetching from a shallow repository, git fetch refuses refs that require updating .git/shallow. This option updates .git/shallow and accepts such refs." On a non-shallow or boundary-agnostic fetch it is inert — safe unconditionally.

## Hypotheses

Confirmed failure layer (no connectivity hypothesis survives the evidence): the push reached the host, the wrapper canonicalized, and `receive-pack` negotiated — the refusal `shallow update not allowed` is an application-layer (git protocol) verdict returned on stderr. A transport-level failure (egress drop, handshake reset) produces `killed: true` / `ssh:` errors or the `git-data replication push failed` line WITHOUT a remote rejection reason — the 16:30:17Z Better Stack row names the remote rejection.

### Network-Outage Deep-Dive (checklist L3→L7)

- **L3 firewall allow-list — verified (by arrival).** The git-data egress rule `dedicated-git-data-22-accept` shipped in the prior fix-forward and the re-run's `git-data replication push failed` row carrying the remote's own `shallow update not allowed` verdict IS the verification artifact: a remote rejection proves the packet reached the host and the answer returned — a blackholed egress cannot produce a remote-reject line. (Contrast with rehearsal 1's `killed: true` + empty stderr, which was the real egress fault.) The hcloud firewall describe/diff is N/A here — the client is the web host's container, not an operator IP, and the egress chain is the standing `SOLEUR-EGRESS` ruleset already proven by the delivered refusal.
- **L3 DNS/routing — verified (by arrival).** Static private-net destination `10.0.1.20:22` — no DNS involved; the refusal arrived, so routing is proven for the incident window.
- **L7 TLS/proxy — N/A.** Plain SSH transport, no TLS/proxy intermediary; host key is pinned (`resolveGitDataHostKeyPin`) and a pin fault would surface through `classifyGitDataPinFault`, a different error path than observed.
- **L7 application — verified.** The remote's own stderr verdict `shallow update not allowed` was observed end-to-end at web-1 16:30:17Z (Better Stack `git-data replication push failed` row); `git help config` documents the matching refusal semantics for `receive.shallowUpdate` — root cause confirmed at this layer.

## Research Insights

- **Premise validation:** #8211 OPEN; #11194 OPEN (plaintext arms alive — `git_data_volume_id` literal at `git-data.tf:385-390` stands, as required); PR #11285 MERGED 2026-10-27 (its repo guards apply: REPO_WIDE_SUITES membership, fixture-env baseline, guard-vacuity-floor, exact FLOOR in `git-data-cutover-access.test.sh`, technical-ruling-gate). Collision precheck: 4 open PRs name #8211 — #11342 is THIS branch's WIP PR; #10901/#10905 are the erasure-ledger slices; #11284 is the plaintext-volume-destroy record. No scope duplicate. All cited code sites verified (paths corrected where the brief's `infra/` prefix meant `apps/web-platform/infra/`).
- **Property list (0.6b):** (1) the store accepts pushes whose history bottoms out at the client's shallow boundary; (2) the session-start overlay fetch lands remote-tracking refs in a shallow clone even when the pack requires updating `.git/shallow`; (3) a first-push `remote failure`/`failed to report status` transient does not fail the whole replication. **Cut list:** none — no existing mechanism covers any property (verified by reading the wrapper, client, and replication call sites; that absence IS the incident).
- **Key file paths:** wrapper `apps/web-platform/infra/git-data-transport-wrapper.sh:132-138`; fetch `apps/web-platform/server/git-data-client.ts:248-258`; push `apps/web-platform/server/git-data-replication.ts:788-801`; clone `--depth 1` `apps/web-platform/server/ensure-workspace-repo.ts:476`; `git init --bare` `apps/web-platform/infra/git-data-provision.sh:143`; pin sites `git-data-cutover.sh:689`, `git-data-transport-wrapper.test.sh:133,141,235`, `git-data-cutover-access.test.sh:735,1235,1345,4007`; userdata embed `apps/web-platform/infra/modules/git-data-userdata/main.tf:98`.
- **Relevant learnings:** `2026-09-21-curl-retry-flags-turn-a-throttled-emit-into-success-and-my-stubs-were-looser-than-the-code.md` — a retry flag can turn a failure into a success; the retry must positive-match the transient class (never blanket) and the test stub must model the same stderr surface the code reads. `2026-09-23-every-fix-i-shipped-to-close-a-defect-carried-the-same-defect.md` — fix-forwards carry their own defects; the exec-line pin inventory above is the countermeasure.
- **CLI verification (gate):** `git fetch --help` on git 2.56.0 prints the `--update-shallow` stanza verbatim (quoted above); `git help config` prints the `receive.shallowUpdate` stanza verbatim (quoted above). Both flags exist and their semantics match the ruling.
- **Test infrastructure:** `test/git-data-remote-url-wrapper.test.ts` already execs the REAL wrapper under `env -i` through a shim `ssh` that path-maps `/mnt/git-data/repositories` onto a fixture root — the new tests ride that harness (`makeBare`, `transportEnv`, `dialedCommands`). It mocks `gitWithPrivateKeyAuth` as `vi.fn()`; the overlay test re-mocks it as a real-git passthrough so production argv reaches real git. `test/git-data-remote-url-wrapper.test.ts` is already a member of `REPO_WIDE_SUITES` — no registry edit needed. `git-data-transport-wrapper.test.sh` has an exact-count floor at its tail ("the floor is the measured total") — added cases require bumping it to the new measured count.
- **Domain conventions:** repo commits use `git -C <literal abs path> commit -F <abs msg file>` with explicit pathspecs; PR body opens `Ref #8211` (never `Closes`); no new issues filed from this work.

## Research Reconciliation — Spec vs. Codebase

| Spec/brief claim | Reality (verified 2026-10-27) | Plan response |
|---|---|---|
| "`infra/git-data-provision.sh` ~line 143" | File lives at `apps/web-platform/infra/git-data-provision.sh`; `git init --bare --quiet` confirmed at `:143` | Use the real path |
| wrapper change at "~lines 133/138", comment "~126-131" | DRYRUN at `:132-135`, exec at `:138`, fence-pin comment at `:125-131` | Confirmed; line numbers cited exactly |
| "add `-c receive.shallowUpdate=true` to the `git receive-pack` exec line ONLY; the upload-pack exec line stays unchanged" | There is ONE shared exec line (`:138`) for both verbs | Conditional branch: flag on receive-pack argv only; generic line preserved verbatim so the three pin sites stay green |
| "retry … when stderr matches `remote failure\|failed to report status`" | `gitWithPrivateKeyAuth` rejects via execFile error; stderr rides `err.stderr` (message is the fallback) | Classifier reads `err.stderr ?? err.message` |

## User-Brand Impact

- **If this lands broken, the user experiences:** their session-end replication push is refused (or, worse, a malformed wrapper edit refuses EVERY transport — fetch and push) while the session reports ended; committed work that exists only in the workspace clone is never replicated, and a later fresh graft rehydrates an older GitHub tip — the user sees their latest committed work vanish from a new workspace.
- **If this leaks, the user's data is exposed via:** the store holds every connected user's repository under a shared transport key; `receive.shallowUpdate` widens what a push can write (the repo's `shallow` file), an availability-class exposure on the shared store (confidentiality unaffected — the fence's namespace ownership is unchanged).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the blast radius of a broken replication path is one user's unreplicated commits — loud (Sentry + Better Stack) and recoverable while the clone lives, but user-data-loss shaped, which clears `none` and does not reach `aggregate pattern` (no population-level failure mode; each failure is per-workspace).

*Headless note:* `requires_cpo_signoff: true` is set per the threshold rule; the CPO consult could not be spawned in this harness — recorded as a pending row in `decision-challenges.md`. `soleur:engineering:review:user-impact-reviewer` runs at review time per the review skill's conditional-agent block.

## Observability

```yaml
liveness_signal:
  what: Better Stack log signal for the replication push outcome — success line "git-data replication push complete" and absence of "git-data replication push failed" / "git-data replication shed" rows (the same three phrases R3 queries)
  cadence: per session end (event-driven)
  alert_target: Better Stack `git-data replication push failed` alert (the hit that fired at web-1 16:30:17Z)
  configured_in: apps/web-platform/server/git-data-replication.ts:802-809 (info line), :838-854 (reportSilentFallback mirror); Better Stack queries per runbook R3 (knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md)

error_reporting:
  destination: Sentry via reportSilentFallback (feature "worktree_lease", op "git_data_replication_push"; pin-fault arm via reportGitDataPinFault)
  fail_loud: a non-transient push failure re-throws after mirroring — the Better Stack row "git-data replication push failed" and the Sentry issue are the loud signals; the retried-once transient also mirrors if the retry fails

failure_modes:
  - mode: wrapper drops the flag (regression — store refuses shallow pushes again)
    detection: R-PUSH-SHALLOW test on every CI run; on the live host, a repeat of the 16:30:17Z Better Stack hit
    alert_route: CI failure on the PR; Better Stack `git-data replication push failed` alert in production
  - mode: retry masks a real failure / loops beyond once
    detection: retry unit test asserts exactly 2 calls max; push failure still re-throws to reportSilentFallback on the second failure
    alert_route: CI failure on the PR; production failure unchanged (one retry, then the existing loud path)
  - mode: overlay fetch still produces no ref (flag dropped or boundary not the cause)
    detection: R-FETCH-OVERLAY test; in production the existing show-ref fallback keeps the GitHub clone — unchanged behavior, now observable via the fetch succeeding or the overlay report
    alert_route: CI failure on the PR; Sentry `ensure-workspace-repo op:git-data-overlay` on a thrown fetch

logs:
  where: app pino → Better Stack (query per runbook R3); wrapper rejections ride `remote:` on the client stderr → captured in the same push-failure report
  retention: Better Stack plan retention (out of scope of this change)

discoverability_test:
  command: grep -c "receive.shallowUpdate=true" apps/web-platform/infra/git-data-transport-wrapper.sh
  expected_output: "2"
```

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.git_data_luks (the git-data store; unchanged by this plan — declared because the change writes a new code path that lands on it)
    mechanism: luks
    evidence: apps/web-platform/infra/git-data.tf:385-406 (LUKS volume id wiring), ADR-239; device binding via /etc/git-data/store-verified asserted by the wrapper itself (git-data-transport-wrapper.sh:84-89)
    defends_against: a seized/RMA'd disk or raw volume snapshot readable without the passphrase
    does_not_defend: a caller holding the transport key (any push under the shared tree — the shallow-file write the parked Non-Goal routes to security-sentinel); a booted host with the mapper open
    disclosed_as: not-publicly-claimed
    live_verification: available — the wrapper's own findmnt/UUID check fails closed per transport
in_transit:
  - connection: web app workspace -> git-data host (git protocol over SSH transport key)
    enforced_at: apps/web-platform/server/git-auth.ts:442-503 (gitWithPrivateKeyAuth — pinned known_hosts, BatchMode)
    tls: ssh (OpenSSH), host key pinned ssh-ed25519 via GIT_DATA_SSH_HOST_KEY
    cert_verification: on
    does_not_defend: a host-key rotation not yet republished (pin mismatch fails closed — the pin_fault alert path)
    disclosed_as: not-publicly-claimed
```

## Infrastructure (IaC)

No new infrastructure is introduced. The change edits a file that reaches the git-data host through the EXISTING cloud-init/userdata path.

### Terraform changes

None in this PR — `modules/git-data-userdata/main.tf:98` already embeds `git-data-transport-wrapper.sh` into the render; the file content change flows into `user_data` automatically. No provider or variable changes.

### Apply path

`terraform apply -replace='hcloud_server.git_data'` — the existing owner-gated `git-data-host-replace` dispatch (`apply-web-platform-infra.yml` `apply_target`), with `confirm` token, reviewer environment and the scoped destroy-guard that asserts both data volumes (`hcloud_volume.git_data`, `hcloud_volume.git_data_luks`) preserved and the passphrase untouched. Expected blast radius: git transport refuses during the replace window (bounded minutes); replication pushes during it fail loud and retry on the next session end.

### Merge-safety proof (constraint: merging must not auto-replace the host or volumes)

- `hcloud_server.git_data` deliberately carries NO `ignore_changes=[user_data]` (`git-data.tf:486-504` — "omitting it preserves a clean replace-to-reprovision path"); `ignore_changes = [ssh_keys]` only. So the wrapper edit DOES produce a `user_data` diff on the resource — the question is whether any merge-triggered apply can reach it.
- The push-triggered `apply` job plans through a `-target` allow-list (`apply-web-platform-infra.yml:437-…`): no `hcloud_server.git_data`, no `hcloud_volume*`/`hcloud_volume_attachment*`/`module.git_data_userdata` address appears anywhere in it. The git-data-named targets (`betteruptime_heartbeat.git_data*`, `doppler_secret.git_data_*`) are heartbeat monitors and URL secrets with no dependency on the server or the userdata module (verified by grep: only `network.tf:52` references `hcloud_server.git_data.id`, and `hcloud_server_network.git_data` is also untargeted).
- The post-bridge apply (`:1227-1278`) targets only `terraform_data.*`; `terraform_data.git_data_probe_install` (server.tf:1295) provisions onto web-1 (`host = hcloud_server.web["web-1"].ipv4_address`) and its `triggers_replace` hashes `web-git-data-probe.*` + the probe token — none touched here.
- Git-data host changes are reachable only via `apply_target=git-data-host-replace` / `-rotate` / `-create` — manual `workflow_dispatch` jobs, each with `confirm` token, reviewer environment, and a destroy-guard asserting the exact scoped set.
- `scheduled-terraform-drift.yml` plans `apps/web-platform/infra` full-root but is read-only report — the `user_data` diff will correctly show as drift until the owner runs the replace. That drift row is the intended signal that the fix is merged-but-not-yet-on-the-host.
- `plaintext_unverified` FATAL (`git-data.tf:385`) stands — #11194 is OPEN; this plan does not touch `git_data_volume_id`.

### Distinctness / drift safeguards

dev ≠ prd n/a (single production host); `lifecycle.ignore_changes=[ssh_keys]` noted above; state lives in the encrypted R2 backend per the existing root.

## Downtime & Cutover

- **Offline-inducing operation:** none performed by this merge. The eventual host-side delivery (`git-data-host-replace`) takes the git transport plane offline for the bounded replace window — pushes/fetches refuse (fail-closed) while the host is down.
- **Zero-downtime path evaluated:** none exists by design — the git-data host is a singleton immutable host whose reprovision IS a replace (ADR-149 birth/replace interlock; there is no second replica to drain to). The replace is owner-timed, so it is dispatched outside an active rehearsal window; during it, replication pushes fail loud (reported) and succeed on the next session end after the host returns — replication is a background overlay, not a request-serving surface, so no user-facing availability loss.
- **Residual risk accepted:** a session ending inside the replace window loses one replication attempt (recoverable on next session end); bounded by dispatch timing — no sign-off item beyond the existing owner gate.

## Architecture Decision (ADR/C4)

### ADR

Amend `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md` — extend the existing `## Addendum — 2026-10-27 (#8211)` block (which already carries the remote-URL fix-forward in the same style) with a short paragraph: the transport wrapper's receive-pack is exec'd with `-c receive.shallowUpdate=true` so the store accepts pushes from `--depth 1` workspace clones, and the read side fetches with `--update-shallow`; the clone stays shallow (ruling reaffirms the ADR-099 rejection of unshallowing). No new ADR — this is a transport-posture refinement of the ADR-068 mechanism, not a new boundary.

### C4 views

No C4 impact. Enumeration checked against `model.c4`/`views.c4`/`spec.c4`: (a) external human actors — none new (same app transport); (b) external systems — none new (git-data host already modeled); (c) containers/data-stores — none touched (the git-data host and its probe edge at model.c4 ~line 831 are unchanged in shape); (d) access relationships — unchanged (same SSH transport edge, same direction, same namespace ownership). A receive-side config flag inside the existing wrapper is below the model's abstraction level.

### Sequencing

The addendum lands with this PR; no `status: adopting` staging needed — the posture is true the moment the wrapper ships on the host.

## Files to Edit

- `apps/web-platform/infra/git-data-transport-wrapper.sh` — conditional receive-pack exec branch carrying `-c receive.shallowUpdate=true`; matching DRYRUN branch; comment at :125-131 extended.
- `apps/web-platform/server/git-data-client.ts` — `"--update-shallow"` after `"fetch"` (:250).
- `apps/web-platform/server/git-data-replication.ts` — one-shot transient retry around the push (:788-801).
- `apps/web-platform/test/git-data-remote-url-wrapper.test.ts` — `makeShallowClone` helper; R-PUSH-SHALLOW; R-FETCH-OVERLAY (real-git passthrough of `gitWithPrivateKeyAuth`).
- `apps/web-platform/test/git-data-replication.test.ts` — retry unit tests (transient retries once; `shallow update not allowed` and fence reject do NOT retry; two transients still fail).
- `apps/web-platform/infra/git-data-transport-wrapper.test.sh` — T2 receive-pack DRYRUN expectation gains `-c receive.shallowUpdate=true`; T11 literal-exec pin gains the receive-pack branch line (generic line pin unchanged); new case pinning that the upload-pack DRYRUN carries NO `receive.shallowUpdate`; floor count bumped to the new measured total.
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` — R3 row (line ~395): append the 2026-10-27 re-run record — verdict FAILED (clean Better Stack `git-data replication push failed` hit at web-1 16:30:17Z; no shed, no overlay-fallback; R4 stays blocked) + the note that the wrapper reaches the host ONLY via owner-gated `git-data-host-replace` (cloud-init baked).
- `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md` — extend the 2026-10-27 addendum.

## Files to Create

None (planning artifacts — `specs/<branch>/tasks.md`, `decision-challenges.md` — are produced by the workflow, not the implementation).

## Open Code-Review Overlap

None — queried `gh issue list --label code-review --state open` (99 issues) and jq-scanned every Files-to-Edit path plus `ADR-068`; zero body matches.

## Implementation Phases

### Phase 1 — Tests first (RED)

1.1 Extend `test/git-data-remote-url-wrapper.test.ts`: `makeShallowClone(name)` — build an origin repo with ≥3 commits, `git clone --depth 1 file://<origin>`; **R-PUSH-SHALLOW**: push `refs/heads/*:refs/soleur/worktrees/<WT>/heads/*` from the shallow clone through the real wrapper, assert `push.status === 0` and the ref lands on the bare repo; **R-FETCH-OVERLAY**: fetcher is `--depth 1` from origin, pusher drives a ref whose tip sits BELOW the fetcher's shallow boundary (reliable trigger for the `.git/shallow` update need); re-mock `gitWithPrivateKeyAuth` as a real-git passthrough (`spawnSync("git", args, { cwd: opts.cwd, env: transportEnv() })`) and call the production `fetchFromGitData`; assert `refs/remotes/git-data/<branch>` exists and equals the pushed sha — RED without `--update-shallow`.
1.2 Extend `test/git-data-replication.test.ts`: `gitPush.mockRejectedValueOnce(Object.assign(new Error("…"), { stderr: "… remote failure …" }))` then resolve → `gitPush` called 2×, result `{status:"replicated"}`; `stderr: "… shallow update not allowed …"` → 1 call, rejects; fence-reject message → 1 call, rejects; two consecutive transients → 2 calls, still rejects. RED.
1.3 `git-data-transport-wrapper.test.sh`: update T2 expectation, add the upload-pack-no-flag pin, bump floor. RED expected on the new pins until Phase 2.

### Phase 2 — Implementation (GREEN)

2.1 Wrapper conditional exec branch + DRYRUN mirror + comment.
2.2 `git-data-client.ts` `--update-shallow`.
2.3 `git-data-replication.ts` retry.

### Phase 3 — Docs

3.1 Runbook R3 row update.
3.2 ADR-068 addendum extension.

## Non-Goals (parked on #8211 — do NOT file issues)

- Cold graft of a never-replicated workspace: the wrapper refuses a non-existent repo (`repo does not exist (provision it first)`), so the first overlay fetch throws `op git-data-overlay` and treats the store as empty. Parked.
- `receive.shallowUpdate` lets any push under the shared tree rewrite the repo's `shallow` file — availability impact only; route to security-sentinel at review. Parked.
- Unshallowing the workspace clone (explicitly rejected by the CTO ruling; ADR-068 lists `--unshallow` as LOW post-GA).
- The `refs_assert` mode (a separate #8211 follow-up; REFS-CONFIRMED still needs it).
- `git_data_volume_id` literal retirement — bound to #11194, still OPEN.

## Domain Review

**Domains relevant:** none (cross-domain sweep of all 8: engineering-internal transport fix; operations touched only as runbook record-keeping, not a new operator procedure — the `git-data-host-replace` dispatch already exists and is owner-gated. No user-facing surface, no marketing/legal/finance/support/sales/product implication.)

No cross-domain implications detected — infrastructure/tooling change.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add `-c receive.shallowUpdate=true` to the `git receive-pack` exec line ONLY; the upload-pack exec line stays unchanged; update the comment at ~lines 126-131" | Files-to-Edit `git-data-transport-wrapper.sh` / Phase 2.1 | mapped |
| 2 | "The wrapper's DRYRUN string in the same file must carry the same flag" | Files-to-Edit `git-data-transport-wrapper.sh` / Phase 2.1 | mapped |
| 3 | "add `--update-shallow` after `fetch`" | Files-to-Edit `git-data-client.ts` / Phase 2.2 | mapped |
| 4 | "retry the push ONCE when stderr matches `remote failure\|failed to report status` … Do NOT retry on `shallow update not allowed` or on a fence reject" | Files-to-Edit `git-data-replication.ts` / Phase 2.3 | mapped |
| 5 | "Extend apps/web-platform/test/git-data-remote-url-wrapper.test.ts with a makeShallowClone helper … an R-PUSH-SHALLOW test … and R-FETCH-OVERLAY (red without --update-shallow), driving production code via a real-git passthrough" | Files-to-Edit `test/git-data-remote-url-wrapper.test.ts` / Phase 1.1 | mapped |
| 6 | "A retry unit test in test/git-data-replication.test.ts (retries once on the transient; does NOT retry on `shallow update not allowed` or a fence reject)" | Files-to-Edit `test/git-data-replication.test.ts` / Phase 1.2 | mapped |
| 7 | "update the R3 row of knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md" | Files-to-Edit runbook / Phase 3.1 | mapped |
| 8 | "the plan must include a step to PROVE from apps/web-platform/infra/git-data.tf … that merging does not auto-replace the git-data host or volumes" | `## Infrastructure (IaC)` → Merge-safety proof | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `git-data-transport-wrapper.sh` edit | asks 1–2 | asked |
| `git-data-client.ts` edit | ask 3 | asked |
| `git-data-replication.ts` edit | ask 4 | asked |
| `test/git-data-remote-url-wrapper.test.ts` extension | ask 5 | asked |
| `test/git-data-replication.test.ts` extension | ask 6 | asked |
| `git-data-transport-wrapper.test.sh` update | — | inferred — justification: it pins the exec-line literal and DRYRUN strings verbatim (T2/T11); editing the wrapper without it leaves the suite red — the pin or the contract rots |
| runbook R3 row | ask 7 | asked |
| ADR-068 addendum extension | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; a transport-posture change must not lag the mechanism that creates it |
| Conditional exec-branch shape (preserving the generic line) | — | inferred — justification: `git-data-cutover.sh:689` pin_ex exact-matches the line on the LIVE host; removing it turns every fence probe into `transport_pin_mismatch` |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `knowledge-base`
- Planned files: 8 | Estimated changed lines: ~320
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [x] AC1: `git-data-transport-wrapper.sh` execs `git receive-pack` with `-c receive.shallowUpdate=true` and execs `git-upload-pack` with argv byte-identical to `origin/main`'s; the DRYRUN echo mirrors each verb's real argv; the comment at ~:125-131 explains the `-c` pinning rationale for the flag.
- [x] AC2: `git-data-client.ts` `fetchFromGitData` passes `"--update-shallow"` immediately after `"fetch"`.
- [x] AC3: `git-data-replication.ts` retries the push at most once, only when the failure's stderr/message matches `remote failure|failed to report status`; `shallow update not allowed` and fence rejects are never retried.
- [x] AC4: R-PUSH-SHALLOW fails on `origin/main` and passes after the wrapper change — a push from a `git clone --depth 1 file://` clone through the REAL wrapper lands `refs/soleur/worktrees/<WT>/heads/*` on the bare fixture repo.
- [x] AC5: R-FETCH-OVERLAY fails on `origin/main` (fetch produces no `refs/remotes/git-data/*` when the pack requires a `.git/shallow` update) and passes after the flag — the production `fetchFromGitData` drives real git via the passthrough.
- [x] AC6: Retry unit tests: transient → exactly 2 calls and `{status:"replicated"}`; `shallow update not allowed` → exactly 1 call, rejects; fence reject → exactly 1 call, rejects; two transients → exactly 2 calls, rejects.
- [x] AC7: `git-data-transport-wrapper.test.sh` — T2 expects the flag on receive-pack DRYRUN, T11 pins both exec lines, a new case pins NO flag on the upload-pack DRYRUN, and the suite's exact floor equals the new measured count.
- [x] AC8: The runbook's R3 row records the 2026-10-27 re-run verdict FAILED with the Better Stack hit detail and the `git-data-host-replace`-only delivery note.
- [x] AC9: ADR-068's 2026-10-27 addendum records the shallow-acceptance posture.
- [ ] AC10: PR body opens `Ref #8211`; no new issues filed; the merge-safety proof stands (no auto-replace of `hcloud_server.git_data` or its volumes on merge).
- [x] AC11: `pin_ex` in `git-data-cutover.sh` and the P2 parity test still pass with the probe unchanged — the generic exec line is preserved verbatim (proof that the host fence probe stays green across the wrapper change).

## Test Scenarios

- Given a bare repo on the fixture store, when a `--depth 1` clone pushes `refs/heads/*:refs/soleur/worktrees/<WT>/heads/*` through the real wrapper with the ssh shim, then receive-pack exits 0 and `for-each-ref` on the bare repo lists the pushed ref (integration).
- Given a `--depth 1` fetcher and a store ref whose tip is below the fetcher's shallow boundary, when `fetchFromGitData` runs through the real-git passthrough, then `refs/remotes/git-data/<branch>` resolves to the pushed sha and `.git/shallow` gains the new root (integration).
- Given the same fetch without `--update-shallow`, then git refuses the ref and `fetchFromGitData` throws — the pre-fix RED (integration).
- Given `gitPush` rejects once with stderr `remote failure`, when `replicateToGitData` runs, then the push is re-issued once with identical argv incl. `--push-option=lease-gen=<n>` and returns `replicated` (unit).
- Given `gitPush` rejects with `shallow update not allowed` or a fence-reject message, then exactly one call is made and the error re-throws to `reportSilentFallback` (unit).
- Given the DRYRUN seam, when `SSH_ORIGINAL_COMMAND` is `git-receive-pack '<path>'`, then the echo carries `-c receive.shallowUpdate=true`, and when it is `git-upload-pack '<path>'`, the echo does not (unit/shell).
- Given the exec-line mutation `sed -i '/^exec git -c "core.hooksPath=/d'` (existing cutover-access arm), then it still deletes every exec line including the new branch — the pin arms stay valid (shell, existing suite).

## Guard Contract

### Guard 1 — shallow-push acceptance end-to-end (R-PUSH-SHALLOW)

**Property.** A push from a `--depth 1` clone is accepted by the store through the real transport wrapper and lands under the worktree namespace.

**Assembly.** The receive-pack exec branch in `git-data-transport-wrapper.sh` (the only point where `-c receive.shallowUpdate=true` can enter the transport — the forced command is the single chokepoint all pushes flow through), the DRYRUN mirror, and the test's real-git shim (`ssh` → `env -i` wrapper → real `receive-pack` against a real bare repo).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Drop `-c receive.shallowUpdate=true` from the receive-pack exec branch | RED — push rejected `shallow update not allowed` |
| 2 | Carry the flag on the DRYRUN echo but not the real exec (or vice versa) | RED — DRYRUN/argv parity assertion fails |
| 3 | Push from a SECOND shallow clone (different origin, different worktree id) — the guard must not special-case the first fixture | PASS — the flag is on the verb, not the fixture |
| 4 | Suite edit: delete the `for-each-ref` landing assertion | RED — the test no longer observes the property (floor/dispatch catches a green-suite shape) |
| 5 | `makeShallowClone` drops `--depth 1` (fixture becomes a full clone) | RED — the suite must not pass vacuously: assert the clone IS shallow (`git rev-parse --is-shallow-repository` true) so the mutation kills the test |

### Guard 2 — overlay fetch lands refs in a shallow clone (R-FETCH-OVERLAY)

**Property.** `fetchFromGitData` lands `refs/remotes/git-data/*` in a `--depth 1` clone even when the pack requires updating `.git/shallow`.

**Assembly.** The fetch argv at `git-data-client.ts:248-258` (the only call site for the overlay fetch — production code driven through the real-git passthrough), the store fixture, and the passthrough's transport env.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Drop `--update-shallow` from the fetch argv | RED — fetch refuses, no `refs/remotes/git-data/*` lands |
| 2 | Move `--update-shallow` after the refspecs (argv order bug) | RED — git parses it as a refspec; fetch fails |
| 3 | Fetcher is a FULL (non-shallow) clone — the flag is inert but harmless | PASS — the non-canonical arm proves the flag isn't a shallow-only special-case |
| 4 | Suite edit: assert on `refs/heads/*` instead of `refs/remotes/git-data/*` | RED — wrong namespace must not pass |
| 5 | Passthrough returns a canned success without running git | RED — no ref lands; the ref-existence assertion fails |

## Context

- PR body opens `Ref #8211` (never `Closes`); this PR is the only merge authorized during the flag-on window; file no new issues.
- Host change = YES: the wrapper is baked into cloud-init, so the fix deploys to the git-data host only via `git-data-host-replace`. Merge does not auto-replace (proof above).
- Commit discipline: `git -C <literal abs path> commit -F <abs msg file>`, explicit pathspecs, author/committer Jean Deruelle <jean.deruelle@jikigai.com>.
- Repo guards from PR #11285 in force: `test/git-data-remote-url-wrapper.test.ts` stays in `REPO_WIDE_SUITES`; `plugins/soleur/test/fixture-env-adoption.test.sh` baseline covers the shared `gitFixtureEnv`; guard-vacuity-floor applies to new suite files (none here — existing files only); the cutover-access suite's exact FLOOR is untouched (no edits needed there — the generic exec line survives); technical-ruling-gate: every ruling recorded in `specs/<branch>/decision-challenges.md`.
- AI-era note: the test extensions and the retry classifier are the highest-risk AI-generated surface — worth a closer `soleur:review` pass on argv-order, stderr-surface fidelity (err.stderr vs err.message), and the passthrough's env fidelity.

## Risks & Mitigations

- **Risk:** a second exec branch doubles the pin surface. **Mitigation:** the generic line is preserved verbatim, so `pin_ex` (production probe), T11's literal pin, and P2 parity all stay green — verified at AC11; the new branch is pinned by the updated wrapper test.
- **Risk:** retry turns a real failure into a slow one, or retries a non-transient. **Mitigation:** positive-list regex; exactly one retry; second failure takes the existing loud path; unit tests pin all three refusal classes (per the 2026-09-21 retry-flag learning).
- **Risk:** `--update-shallow` widens `.git/shallow` writes from any fetched namespace. **Mitigation:** the fetch is membership-authorized upstream (`authorizeGitDataAccess`) and the refspec pins the caller's own worktree namespace; the flag only governs the local clone's shallow file, never the store's.
- **Risk:** R-PUSH-SHALLOW fixture doesn't reproduce the refusal (vacuous green). **Mitigation:** assert `git rev-parse --is-shallow-repository` on the fixture clone and, on the pre-fix tree, expect the literal `shallow update not allowed` rejection — the Guard Contract matrix rows 1 and 5.
- **Risk:** wrapper edit breaks every transport (malformed `-c` argv). **Mitigation:** the conditional touches only the receive-pack argv; upload-pack argv is byte-identical; the wrapper test suite + R-PUSH/R-FETCH cover both verbs through the real binary.
- **Precedent-diff:** no in-module retry precedent (novel shape — flagged for review); the `-c` scope-pin has direct precedent one line above (core.hooksPath), which this change deliberately reuses.
