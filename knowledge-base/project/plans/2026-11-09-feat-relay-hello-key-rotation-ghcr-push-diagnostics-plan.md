---
title: "feat(relay): accept-only hello key slot (rotation route, first half) and self-reporting GHCR push denials (#8211 / #12167 follow-ups)"
type: feat
date: 2026-11-09
slug: feat-relay-hello-key-rotation-ghcr-push-diagnostics
branch: feat-one-shot-8211-hello-key-rotation-ghcr-diag
issue: 8211
closes: 12167
pr: 12536
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# feat(relay): accept-only hello key slot and self-reporting GHCR push denials

## Overview

Follow-ups to PR #12462 (signed relay hello, ADR-323), merged as 289dcf6662 and deployed as v0.402.0. One PR, four parts:

1. **(A) The next arc step, as ruled by the CTO.** "PR B" in PR A's plan was the web-2 serve flip, and it already ran
   on 2026-11-08. The next PR is this one. The answer is recorded below so the PR body and the epic comment posted at
   ship can carry it.
2. **(B) First half of a route to replace the hello key.** The owner-side verifier gains one accept-only key slot,
   `PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO`, which is never used to sign and is absent by default. The PR ships dark, with no
   new secret at merge. A boot fingerprint line proves that both hosts hold the same key. ADR-323 Decision 9 is
   amended. The second half moves the key out of Tier-A-readable state and adds a three-phase rotate mode; it is
   follow-up #12538, which blocks onboarding external users.
3. **(C) GHCR push denials report themselves.** A failure-gated step after the image push emits one
   `SOLEUR_GHCR_PUSH_FAILED` line carrying the denial class, the text and the run attempt. A new runbook says: check
   Billing > Packages first, then re-run the failed jobs of both runs, never a fresh dispatch.
4. **(D) and (E) are not built here.** D is the red `deploy-script-tests (4/4)` job, which #12489 owns; it gets a
   post-merge read. E, a signed hello sent by the deploy probe, is deferred to #12539. Its smaller variant, the
   fingerprint line, is part of B.

This PR changes production. **Merging is owner-gated: STOP BEFORE MERGE.**

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

**Plan review (2026-11-10).** Five reviewers ran: DHH, Kieran, code-simplicity, architecture-strategist and spec-flow.
Their technical dissents went back to the CTO, who ruled T1 to T6, recorded in `decision-challenges.md`. The results:

- the `accepted_also` counter is cut;
- the release-path shape check is cut;
- the phase-gate rules become normative requirements for #12538, not a frozen grammar;
- a confirmed leak rotates in a single phase;
- #12167 closes at ship with evidence.

The mechanical findings are applied, and the taste items (T7, T8) are recorded.

## Next Arc Step (Item A) — for the PR body and the #8211 / #12167 epic comment at ship

Ruled by CTO agent, 2026-11-10: "PR B" in PR A's plan (archived plan lines 45, 161, 216, 550) was the **web-2 serve
flip**. It already ran:

- CF LB overlay run 42488889045 ran only `ga_pool_update`, at 2026-11-08 14:15Z, owner-typed risk acceptance.
- #12414 persisted it as `web2_lb_weight` default 1 (`apps/web-platform/infra/variables.tf`). This also settles
  #12167's question about the weight default and the C.3/C.4 pins.

**The next PR is this branch.** It carries B (first half of the key route) and C. E is not part of it.

Two items still separate web-2 from external users. Both come from #8211's "Needed before external users are served
from the second web host" list:

1. **Deployed signed round trip.** This is a read, not a PR. It needs a `relay_hello_window accepted=<n>` row with
   `n>0` on the owner host, from one real proxied session whose lease sits on the other host. The owner runs a
   synthetic-account session; the agent reads the row (query: relay section of
   `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`).
2. **A route to replace or retire the key.** This PR builds the verifier half. #12538 builds the move-out-and-rotate
   half, which is the only route that repairs a leak.

**#12167:** everything it asked for has shipped (#12168, #12233, #12292, #12390, #12414; the C.4 pin is the `C.4-R1` assertion in
`apps/web-platform/infra/lb-weight-gate.test.sh`). Ruled by CTO agent, 2026-11-10 (T5): ship closes it with evidence
(AC-S3). Its "warn level" bullet assumed the line never reached Better Stack. The rows are user.notice, but they ship
through Vector's ci-deploy allowlist and are read off-host by the `relay_peer_probe_failed` alert and the serve step.
Serve run 42488889045 read "relay evidence GREEN live".

**Still owner-only on the arc:**

- RF9 exit, on or after 2026-11-12 ~14:34Z (7 days after RF6).
- The synthetic-account session that produces item 1.
- Every mint, Doppler write, state forget and rotate approval in #12538.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (checked on this branch) | Plan response |
|---|---|---|
| "Do NOT start PR B unless the CTO's ruling shows it IS one of the items below" | "PR B" was the web-2 serve flip; it ran on 2026-11-08 (run 42488889045) | Nothing to start. Recorded as the Item A answer. |
| (B) "dual-key `_PREVIOUS` verification" as a candidate | Every host both signs and verifies hellos. A two-phase `_PREVIOUS` stage-then-clear therefore splits the hosts during the rolling restart: the host restarted first signs with the new key, and the host not yet restarted refuses it with `mac` | One accept-only slot `PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO`, used in a three-phase rotation (CTO, amended ruling) |
| (B) "no built route to replace or retire" | A reviewer-gated rotation route exists for other keys (`key-rotate.yml`, ADR-317), but a Terraform `-replace` writes the new key into the same Tier-A-readable state | Do not add a `-replace` row. The rotate mode lands together with the move-out in #12538 |
| (C) the cause is the $0 Packages budget | A lead only. Budget `packages` = 0 with `prevent_further_usage: true`. The usage API lists no `packages` rows for Oct or Nov 2026. Both denials came after "pushing layers ... done", with a granted `pull,push` token | Diagnostics only, no retry (CTO C1). The marker classifies the denial and does not name a cause |
| (C) "reachable from Better Stack or the run log" | No step can read its own job's log. A CI-to-Better Stack emitter exists (ADR-172) but would add a prd secret read to the release path | Run log, annotation, step summary and failure email (CTO C2) |
| (C) recover with "Re-run failed jobs" on the push run | The deploy arm (`workflow_run` run 42708243930) also failed (`resolve-target`) and deployed only after its own re-run (attempt 2, 22:44Z) | The runbook names both re-runs |
| (E) the probe sends no hello and proves only TCP+TLS | Confirmed (`ci-deploy.sh` `RELAY_PROBE_JS`). A signed hello with a synthetic pair is refused at membership, so it only ever counts as `denied` | Deferred (#12539). The fingerprint line covers key drift |
| `#12167` is open work | Its asks have shipped; its probe rows are user.notice, not warn, but reach Better Stack | Close at ship with evidence (T5, AC-S3) |

## Research Insights

**Premise Validation (Phase 0.6).** Checked on 2026-11-09 and 2026-11-10:

- **PR #12462: MERGED** (289dcf6662, v0.402.0). Held.
- **#8211: OPEN.** The real flip ran 2026-11-05 (RF4 run 42042079868). RF6 pause-off was 2026-11-05 14:33Z. The RF8
  soak is running. Its 2026-11-09 comments list the two items needed before external users. Held.
- **#12167: OPEN, but its asks have shipped** (see Item A). Stale as "work to do".
- **PR #12489: OPEN, auto-merge armed.** It touches exactly `apps/web-platform/infra/cloud-init.yml` and
  `cloud-init-inngest.yml`. Held; untouched here.
- **PR #12536** is this branch's draft.
- **Collision pre-check** (`collision-precheck.sh 8211` and `12167`): the only open change naming #8211 is #12536.
  The foreign hits are `test-all.sh` processes owned by an unrelated worktree (`feat-one-shot-11764-...-queue-resid`),
  not a duplicate.
- **ADR corpus:** a dual key is not a rejected alternative anywhere. ADR-323 cut it from PR A only because rotation
  had no route. ADR-307 and ADR-317 define the built rotation route. ADR-317 carries the two-phase
  `EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS` precedent, which works there because sender and receiver are different
  services.

**Property List (Phase 0.6b).**

- **P1.** A suspect `PROXY_HELLO_HMAC_KEY` can be replaced through a reviewed, rehearsed route, with no relay split
  between the two hosts during the rolling restarts. This PR builds the verifier half; #12538 builds the rest.
- **P2.** Retiring the relay stays a reviewed route; the per-merge HALT is never the only barrier.
- **P3.** The records tell the truth about the route that exists: ADR-323 Decision 9 and its consequences, the HALT
  remediation line, the `.tf` header and the job-rationale runbook.
- **P4.** Each host's key state can be read off-host with no SSH: is a key loaded, does it match the peer's, is an
  accept-also key loaded.
- **P5.** A recurrence of the GHCR denial names itself in the run log, with its class, text and run attempt, and
  points at the runbook.
- **P6.** One runbook entry covers that failure: Billing > Packages first, then re-run the failed jobs of both runs,
  never a fresh dispatch. Raising the budget is an operator decision about money.
- **P7.** `accepted` keeps meaning "a real session's hello was accepted".

**Cut List (Phase 0.6b).**

- `_PREVIOUS` two-phase slot → P1 → replaced by the accept-only three-phase slot (it splits the hosts).
- `-replace` row in `key-rotate.yml` → P1 → cut (no leak repair under ADR-320). The rotate mode moves to #12538.
- Signed `relay_peer_probe` (E) → P4/P7 → cut in favour of the fingerprint line (P4), which covers it without breaking
  P7. Tracked as #12539.
- In-step push retry (C) → P5 → cut (it would hide the cause), with a re-evaluation trigger.
- Billing read in CI (C) → P5 → cut (no non-PAT credential reads org billing). It stays a runbook read.
- Pointing the release at Zot → cut by the prior CTO ruling.
- D edits → cut. #12489 owns both files.
- `via` + `accepted_also` counter (plan-review, T1) → P1 → cut; the fingerprint gate already proves it.
- Release-path shape check in `verify-required-secrets.sh` (CTO B-d, withdrawn at T2) → P1 → cut; #12538's rotate mode holds the hard check.
- Frozen phase-gate grammar now (B-e, withdrawn at T3) → P1 → cut; it becomes normative requirements for #12538.

**Value-proposition measurement (0.6c):** not applicable. No claimed saving.

**Measured evidence (C).**

Run 42707826766 (push arm, v0.402.0), step "Build and push Docker image" (`docker/build-push-action` v6.19.2):

| Attempt | Job | Time | Push phase | Result |
|---|---|---|---|---|
| 1 | 129469225249 | 22:05:21Z | `[auth] jikig-ai/soleur-<pkg>:pull,push token for ghcr.io`, then `pushing layers 7.7s done` | `ERROR: failed to push ghcr.io/jikig-ai/soleur-<pkg>:v0.402.0: denied: permission_denied: write_package` |
| 2 | 129475621001 | 22:17:20Z | same, `pushing layers 9.3s done` | same error |
| 3 | 129487450869 | — | — | succeeded |

- **Deploy arm** (`workflow_run` run 42708243930): attempt 1 failed at `resolve-target` with `release=skipped`.
  Attempt 2 (22:44Z) deployed.
- **Billing** (`gh api /orgs/jikig-ai/settings/billing/budgets`): `packages` budget 0 with
  `prevent_further_usage: true`. The `actions` and `codespaces` budgets are also 0.
  `gh api "/organizations/jikig-ai/settings/billing/usage?year=2026&month=11"` (and `month=10`) lists only `actions`.
- **The repo:** neither `write_package` nor `permission_denied` appears anywhere in it.
- **Version space:** a failed push consumes no semver and creates no tag. See clause (iii) of the zot-gate comment in
  `reusable-release.yml`: `next` derives from `git tag --list`, and a draft materializes no tag.

**Relevant code (repo research, anchors on this branch).**

- **Loader:** `apps/web-platform/server/proxy-tls.ts` (`HELLO_KEY_RE`, `loadProxyHelloKey`, cache,
  `delete process.env.PROXY_HELLO_HMAC_KEY`, `__resetProxyHelloKeyForTests`). Boot call: `server/index.ts`
  (`loadProxyHelloKey();`).
- **Canonical string and MAC:** `apps/web-platform/server/proxy-hello.ts` (`HELLO_DOMAIN`, `buildHelloMacInput`,
  `computeMac`, `signProxyHello`, `verifyProxyHello`, which takes ONE `key: Buffer`; MAC, then skew, then replay).
- **`apps/web-platform/server/session-proxy.ts`:**
  - Sender key read at `const helloKey = loadProxyHelloKey();`, deny `no_key`.
  - Server-side key read and `createProxyServer.no-hello-key`.
  - Verifier call `verifyProxyHello(data, Boolean(isBinary), helloKey, replayCache)`, then AP-2.
- **Window line:** `apps/web-platform/server/proxy-deny-report.ts` `flushWindow` emits
  `relay_hello_window accepted= denied= suppressed=` at warn. The only query consumer is
  `betterstack-log-query.md` (`startsWith(..., 'relay_hello_window ')`). `betterstack-logs-alerts.tf` has no consumer
  of it.
- **Sensitive keys:** `apps/web-platform/server/sensitive-keys.ts` (`"PROXY_HELLO_HMAC_KEY"`).
- **Terraform:** `apps/web-platform/infra/proxy-hello-hmac.tf`. The header comment names `_PREVIOUS`. The pair is
  count-gated on `host_proxy_tls_enabled`, and the `doppler_secret` has no `ignore_changes`.
- **HALT:** `.github/workflows/apply-web-platform-infra.yml` (`relay_hello_key_changes`, the "Intended rotation"
  remediation line). Filter: `tests/scripts/lib/destroy-guard-filter-web-platform.jq`. Pins:
  `tests/scripts/test-destroy-guard-counter-web-platform.sh` and `plugins/soleur/test/terraform-target-parity.test.ts`.
- **Release:** `.github/workflows/reusable-release.yml` (`id: docker_build`; the job's `permissions:` are `contents`,
  `packages`, `id-token`; "Email notification (release FAILED)"). `web-platform-release.yml` (`release`,
  `resolve-target`, `release-outcome`). Pin: `plugins/soleur/test/reusable-release-caller-permissions.test.sh`.
  Extractor precedent: `extract_run_block` in `plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh`.
- **Tests that pin the touched code:**
  - `apps/web-platform/test/proxy-hello.test.ts` (known-answer vector)
  - `session-proxy-hello.test.ts`
  - `session-proxy.test.ts`
  - `session-proxy-admission.test.ts`
  - `proxy-tls.test.ts`
  - `proxy-hello-key-isolation.test.ts`
  - `proxy-deny-report.test.ts`
  - `server-index-boot-pin-line.test.ts`

**Institutional learnings applied.**

- `knowledge-base/project/learnings/2026-11-09-a-guard-that-terminates-must-also-reach-the-peer-and-my-docs-named-routes-that-did-not-exist.md`:
  ADR-323 once described routes that did not exist. The amendment states only what this PR builds, and names what
  stays missing (#12538).
- `knowledge-base/project/learnings/best-practices/2026-06-18-live-credential-rotation-and-argv-to-env-redeploy.md`:
  the behaviour change (this PR) and the credential change (#12538) go out in separate deploys. Confirm the value
  reaches the running service: that is what the fingerprint line is for.
- `knowledge-base/project/learnings/security-issues/2026-09-24-a-second-apply-workflow-could-perform-the-rotation-without-its-gate.md`:
  every workflow that can reach the key is checked in #12538, not only the rotate route.
- `knowledge-base/project/learnings/2026-09-27-a-carried-over-job-is-relabelled-and-an-undocumented-lock-rule-is-settled-by-a-probe.md`:
  a re-run carries jobs under new labels. The marker keys on `github.run_attempt`.
- `knowledge-base/project/learnings/2026-07-06-ghcr-app-token-cannot-pull-and-oidc-needs-native-identity-source.md`:
  GHCR authorization surprises are platform-side. The marker records evidence and never guesses a cause.
- No learning covers accept-only HMAC slots, `write_package`, Packages budgets or `relay_peer_probe` (gap; capture at
  compound).

**Conventions in force:**

- `hr-github-app-auth-not-pat` (the billing read stays a session read)
- `hr-no-ssh-fallback-in-runbooks`
- `hr-observability-as-plan-quality-gate`
- `cq-silent-fallback-must-mirror-to-sentry`
- `cq-write-failing-tests-before`
- `hr-type-widening-cross-consumer-grep` (the `verifyProxyHello` signature change: consumers are `session-proxy.ts` and
  the tests)
- `cq-test-fixtures-synthesized-only` (synthetic 64-hex keys)
- `wg-block-pr-ready-on-undeferred-operator-steps`
- `wg-when-tests-fail-and-are-confirmed-pre`

## Proposed Solution

### B — accept-only key slot (ships dark)

Ruled by CTO agent, 2026-11-10 (B3, amended; plan-review rulings T1 to T6).

- `PROXY_HELLO_HMAC_KEY` stays the **signing** key and a verifying key.
- `PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO` is **verify-only**.
- With the slot unset, behaviour is byte-identical to today.
- The `relay_hello_window` grammar does **not** change (T1: no `via`, no `accepted_also`).

**B.1 Loader** (`apps/web-platform/server/proxy-tls.ts`):

- Replace `loadProxyHelloKey()` with one function, `loadProxyHelloKeys(): { current: Buffer | null; acceptAlso: Buffer | null }`,
  over one cache. It reads both variables once, caches them, and deletes **both** from `process.env` on the first call,
  whatever their values.
- Update the three production callers to the new name, with no wrapper left behind (DHH):
  - `server/index.ts` boot call, same position, before any child can spawn;
  - the sender's key read in `server/session-proxy.ts`;
  - the server's key read in `server/session-proxy.ts`.
- Keep `__resetProxyHelloKeyForTests` under exactly that name. It is imported by `proxy-listener-status.test.ts`,
  `session-proxy-port.test.ts`, `session-proxy-admission.test.ts` and `session-proxy.test.ts`.
- `acceptAlso` resolves as follows:
  - **Unset or empty:** `null`, silently. This is the default.
  - **Set but not `^[0-9a-f]{64}$`:** `null`, plus **one** Sentry event through `reportSilentFallback` (`feature:
    "control_plane_route"`, `op: "proxy-hello.accept-also-ignored"`, extra `{ reason: "malformed" }`).
  - **Byte-equal to `current`:** **kept**, plus one **warn-level** Sentry event (`op: "proxy-hello.accept-also-equals-current"`).
    Accepting the current key twice is harmless, and `relay_hello_key_fp` then shows `accept_also == current`, which
    exposes the mistake (T2).
  - **Set while `current` is `null`:** no extra event. The listener refuses to start and reports the existing
    `createProxyServer.no-hello-key`, and `acceptAlso` is never consulted (T6, dropping `no_current`).
- Every event text is constant, with no value, length or prefix (`cq-silent-fallback-must-mirror-to-sentry`).

**B.2 Verifier** (`apps/web-platform/server/proxy-hello.ts`):

- New signature: `verifyProxyHello(data, isBinary, keys: { current: Buffer; acceptAlso: Buffer | null }, cache, now)`.
- The shape checks are unchanged.
- The MAC step computes `expected` under `current`, and `expectedAlso` under `acceptAlso` when the slot is set. Both are
  compared with `timingSafeEqual`, always both when the slot is set (the `bearerMatches` pattern in
  `egress-audit-ingest.ts`).
- `reason: "mac"` only when neither matches.
- The skew, replay (the same `ReplayCache`) and AP-2 steps are unchanged and apply whichever key matched.
- The success result is unchanged: `{ ok: true, userId, workspaceId }`.
- `signProxyHello` is unchanged. Its key parameter stays a single `Buffer`, so passing the key set is a type error, and
  it is only ever given `current`.

**B.3 Call sites** (`apps/web-platform/server/session-proxy.ts`):

- **Sender:** `loadProxyHelloKeys().current`. A `null` current still gives the `no_key` deny.
- **Server start:** a `null` current gives `createProxyServer.no-hello-key`, as today. An accept-also key alone never
  starts the listener and never admits a hello.
- **Verifier call:** passes `{ current, acceptAlso }`. `denyReporter.recordAccepted()` is unchanged.

**B.4 Window line:** no change (T1). `apps/web-platform/server/proxy-deny-report.ts` is not edited.

**B.5 Fingerprint line** (`apps/web-platform/server/session-proxy.ts`, inside `createProxyServer`, emitted once right
after the key check passes):

- `log.warn({ current_fp, accept_also_fp }, "relay_hello_key_fp current=<8hex> accept_also=<8hex|none>")`.
- `fp(key)` is the first 8 hex characters of HMAC-SHA256(key, `"soleur-relay-hello-key-fp-v1"`), via one exported
  helper `helloKeyFingerprint(key)` in `proxy-hello.ts`. The domain tag differs from `HELLO_DOMAIN`. It is never a
  raw-key prefix and never a plain hash of the key.
- The line proves the **key state loaded**, not a serving relay: the later `bad-port`, `tls-setup` and listen-error
  exits can still stop the listener (Kieran).
- It is warn-level, so it reaches Better Stack (container pino at level >= 40 is shipped).
- It is printed once per container start on each host. The canary stops at `no_bind` before the key check, so it never
  prints one.

**B.6 Isolation** (`apps/web-platform/server/sensitive-keys.ts`, `test/proxy-hello-key-isolation.test.ts`):

- Add `"PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO"` to the sensitive list, with the same comment.
- The isolation test asserts the name is absent from `agent-env.ts`, `ALLOWED_SERVICE_ENV_VARS` and `providers.ts`, and
  absent from `process.env` after the loader runs.
- `apps/web-platform/scripts/verify-required-secrets.sh` is **not** changed. It stays presence-only and the slot is
  optional (T2).

**B.7 Truth-in-records:**

- **ADR-323 amendment, Decision 9** (dated 2026-11-10):
  - One accept-only slot, `PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO`, dark by default.
  - **Routine rotation is three phases**, each one Doppler change plus one full rolling restart, because each host both
    signs and verifies:
    - P1: sign old, slot holds new.
    - P2: sign new, slot holds old.
    - P3: sign new, slot unset.
  - **A confirmed leak is single-phase,** whatever the live count. The one-stagger 4014 split is accepted. The leak is
    declared by a typed `leak` input in the owner's dispatch confirm (T4).
  - A single-phase routine rotation is allowed while `agent_sessions_live=0`. Its check-then-act race is an accepted
    residual.
  - **Not executable until #12538.** `PROXY_HELLO_HMAC_KEY` is Terraform-managed (`doppler_secret.proxy_hello_hmac_key`,
    no `ignore_changes`), so any Doppler edit of it trips the `relay_hello_key_changes` HALT. No phase can run until
    #12538 moves the key out of Terraform.
  - The leak route is #12538's move-out-and-rotate. Until it lands there is **no leak response and no kill switch**.
    Containment is the pre-TLS allowlist only: a forged hello also needs a roster-host source address. Restoring a
    previous Doppler value is still not a leak route.
- **ADR-323 amendment, phase-gate requirements for #12538** (normative; T3; no grammar freeze in this PR):
  - (a) Every roster host shows a `relay_hello_key_fp` row from its **current boot**, and the host count equals the
    roster size. #12538 chooses the boot-identity field; a `boot=<nonce>` on the fingerprint line is preferred, shipped
    in an image release before the first rotation.
  - (b) A fingerprint row proves key state, not a serving relay, so a same-boot `relay_probe proxy_state=listening`
    row is also required.
  - (c) Before P1, every roster host shows a fingerprint row, which proves its image knows the slot. One image is
    pinned from P1 through P3: no deploy or rollback mid-rotation. The slot is unset before any rollback below this
    release, because older images ignore it.
  - (d) #12538 freezes the line grammars when its parser lands.
  - (e) #12538's rotate mode shape-checks before writing. It refuses a slot equal to current, and a P2 slot not equal to
    the old current. After the canary host restarts, it runs a per-host fingerprint check before the roll continues.
    It also adds a Better Stack alert on `accept_also!=none` outside a recorded rotation (architecture review: a
    planted slot is otherwise silent).
- **ADR-323, other sections:**
  - Decision 6 gains `PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO`; Decision 2 gains the fingerprint line.
  - Rename the "No rotation route" consequence to "Rotation route: verifier half built". It must say that a Terraform
    `-replace` is rejected because it writes the new key into the same Tier-A-readable state.
  - Named residuals gain: each rotation phase is a rolling restart, so every host's in-process replay cache is cleared
    once per phase.
  - "Considered Options" gains: `_PREVIOUS` two-phase (splits the hosts; each host both signs and verifies); a
    two-slot design (one slot suffices); the `accepted_also` counter (redundant with the fingerprint gate); a release
    shape check (runs only on release restarts).
- **ADR-320:** no decision change. #12538 adds the scope note.
- **`apps/web-platform/infra/proxy-hello-hmac.tf` header comment:** replace the `_PREVIOUS` sentence with the accept-only
  slot and a pointer to ADR-323 Decision 9 and #12538. Comment only, so the plan is unchanged.
- **`.github/workflows/apply-web-platform-infra.yml` HALT:** only the "Intended rotation" remediation line changes. It
  becomes: no per-merge route; the verifier accepts an accept-only slot (ADR-323 Decision 9); the replace route is
  #12538.
  - Addresses, counter, forget/move wording, position and exit are unchanged.
  - Measured 2026-11-10: no test pins the remediation line's text. `git grep -nE 'Intended rotation|_PREVIOUS is not built|per-merge route exists' -- tests plugins/soleur/test scripts apps/web-platform/test`
    prints nothing.
- **`knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`:** the
  `PROXY_HELLO_HMAC_KEY_PREVIOUS` mention in the relay HALT section gets the same correction.
- **`knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`, relay section:**
  - the fingerprint query: both hosts' newest `relay_hello_key_fp` lines, which must show the same `current=`;
  - the reading rule: `accept_also!=none` outside a rotation window is an alarm;
  - the failure branches of AC-P1.

### C — GHCR push denial marker and runbook (diagnostics only)

Ruled by CTO agent, 2026-11-10 (C1-C3).

**C.1 The marker step.** A new step in `.github/workflows/reusable-release.yml`, immediately after
`- name: Build and push Docker image` (`id: docker_build`):

```yaml
- name: Report a failed image push (GHCR)
  id: push_failed_marker
  if: failure() && steps.docker_build.outcome == 'failure'
  continue-on-error: true
  timeout-minutes: 1
  env:
    IMAGE: ${{ inputs.docker_image }}
    VERSION: ${{ steps.version.outputs.next }}
    RUN_ATTEMPT: ${{ github.run_attempt }}
    RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}/attempts/${{ github.run_attempt }}
  run: |
    # body in C.1 below; no ${{ }} inside run: (the release suites extract and execute it)
```

- **Output.** It emits one stdout line, one `::error::` annotation and one `$GITHUB_STEP_SUMMARY` line, all in this
  closed grammar:
  `SOLEUR_GHCR_PUSH_FAILED image=<ref> version=<v> attempt=<n> run=<url> class=<denied_write_package|denied_other|unknown> denial=<text|see-step-log> runbook=knowledge-base/engineering/operations/runbooks/web-platform-release-image-push-failed.md`.
  It also writes `class` and `attempt` to `$GITHUB_OUTPUT`.
- **`denial=` source.** The work phase measures this first (the CTO marked it unverified). The runner's buildx is
  v0.38.1, read from job 129469225249's "Buildx version" group; `setup-buildx-action` v3.12.0 pins no `version:`
  here.
  - **Read only the error-message field** of the newest failed record:
    `timeout 10 docker buildx history ls --filter status=error --format json`, then
    `timeout 10 docker buildx history inspect <ref> --format json | jq -r '<error-message field> // empty'`. The exact
    field name is measured in Phase 4.
  - **Never print anything else.** No arbitrary or pretty output, and no build-arg section. Reason (Kieran,
    2026-11-10): `SENTRY_AUTH_TOKEN` is a build-arg of this job, a build record carries its build args, and character
    replacement would defeat GitHub's secret masking.
  - **No new permission and no network.**

  Normalisation:
  - keep the first line of the error field only;
  - map CR and LF to `_`, so the text can never begin a line (workflow commands fire only at line start);
  - collapse every run of two or more `:` to `_`;
  - map every remaining character outside `[A-Za-z0-9 ._:/@-]` (including `%`) to `_`;
  - cap at 300 characters.

  The `class=` token is derived from the raw error field, before normalisation, so `denied: permission_denied:` still
  matches.

  If the history read fails or prints nothing, `denial=see-step-log`. This includes the case where no build ref exists
  because the push failed before `build-push-action` recorded one. That path must still print a complete, valid
  `SOLEUR_GHCR_PUSH_FAILED` line (`class=unknown`), and the step must exit 0. It is a Guard 4 must-PASS row.
  `class=unknown` means "read the step log", not a different failure; the runbook and the email say so.
- **`class=` derivation:**
  - the text contains `denied: permission_denied: write_package` → `denied_write_package`;
  - it contains `denied:` → `denied_other`;
  - anything else, including `see-step-log` → `unknown`.
- **What does not change.** No new `permissions:` and no secret read, so both callers and
  `reusable-release-caller-permissions.test.sh` are untouched. `continue-on-error: true` means the step can never
  change the job's verdict.
- **Bounds.** `timeout-minutes: 1`. Without it, a hang would run to the job's 60-minute ceiling and end the job
  cancelled, and on a cancelled job the `if: failure()` email does not run (architecture review). The step only reads
  `VERSION`. It never writes `$GITHUB_ENV`, a tag or notes, so the version space is untouched.
- **The existing failure email.** "Email notification (release FAILED)" changes in two ways:
  - **Re-run wording.** Its existing clause "so re-running this workflow is safe" becomes "so 'Re-run failed jobs' is
    safe; a fresh 'Run workflow' dispatch is not (it loses the semver label)". As written, the clause reads as
    permission for the dispatch the runbook forbids (spec-flow and Kieran).
  - **One new conditional sentence.** It renders only when `steps.push_failed_marker.outputs.class` is non-empty:
    "Image push failed (class `<class>`, attempt `<n>`; `unknown` means read the step log); see the runbook
    `web-platform-release-image-push-failed.md`; first check Billing > Packages." Build it with `format()` inside the
    existing single-quoted YAML scalar, with doubled `''`.

  The step's `if: failure()` is unchanged.

**C.2 Runbook.** Create `knowledge-base/engineering/operations/runbooks/web-platform-release-image-push-failed.md`, in
the shape of `apply-web-platform-infra-red-run.md`. It carries:

- **Triggers.**
  - The `[BLOCKED] Soleur Web Platform release failed` email.
  - A `SOLEUR_GHCR_PUSH_FAILED` annotation, or `gh run view <run> --log-failed | grep -F SOLEUR_GHCR_PUSH_FAILED`.
  - A deploy-arm run whose `resolve-target` failed with `release=skipped`. It carries no marker of its own.
  - During the gap, the prod version-drift alert is expected; it is not a separate incident.
  - `class=unknown` means "read the step log", not a different failure.
- **Residual: a cancelled or timed-out job emits neither the marker nor the email,** because `failure()` is false. The
  run's `cancelled` conclusion is the only signal. Read the push step's log before any re-run.
- **First read, before anything else** (read-only; an agent can run it):
  `gh api /orgs/jikig-ai/settings/billing/budgets --jq '.budgets[] | select(.budget_product_sku=="packages")'` and the
  Billing > Packages page. Record whether usage shows as blocked. Include the 2026-11-09 measurement, and state that a
  block is a lead, not a finding.
- **What a failed push did not do.** It consumed no semver, created no tag and published no notes.
- **Recovery.** Release re-runs are owner-gated: the agent prepares both run ids, then reads the outcome. In order:
  1. "Re-run failed jobs" on the push-arm run.
  2. Once that succeeds, "Re-run failed jobs" on the deploy-arm (`workflow_run`) run for the same SHA. Its
     `resolve-target` failed when the release did. Find that run with
     `gh run list --workflow web-platform-release.yml --commit <sha> --event workflow_run`.
     Measured on 2026-11-09: there is exactly one such run per SHA, created when CI completed, before the push arm
     failed. Re-running the push arm does not start a new deploy run.
  3. **Never** a fresh "Run workflow" dispatch. It short-circuits to `labels=`, defaults to `patch`, loses a minor or
     major bump and orphans the draft.
- **Operator decision (money): the GitHub Packages budget for private GHCR images.** The runbook names this decision
  and does not prescribe a value. The agent stops and reports at this point, and does not work around the budget
  (CPO condition 7).
- **Retry re-evaluation trigger** (CTO C1): a second, separate run is denied while Billing > Packages shows no block.
- **Out of scope:** pointing the release at Zot (prior CTO ruling).

### D — note only

- **The failing job.** `infra-validation.yml` on `main` is red at 58b1bdb77a, 289dcf6662 and d731cfdebd. The job is
  `deploy-script-tests (4/4)` (step "Run registered infra suites — leg 4/4") and its aggregator
  `deploy-script-tests-done`.
- **The cause.** The suite is `cloud-init-inngest-bootstrap.test.sh`. `cloud-init.yml` and `cloud-init-inngest.yml`
  pin `vinngest-v1.1.69` while the newest tag is `v1.1.70`, and GuardA reports carrier drift.
- **Ownership.** #12489 owns both files; this PR edits neither and does not touch #12489. The job is expected to go
  green when #12489 merges.
- **If this PR's CI selects that leg first,** the red is pre-existing and the PR body records it as such
  (`wg-when-tests-fail-and-are-confirmed-pre`). Post-merge read: AC-P4.

### E — deferred

Ruled by CTO agent, 2026-11-10: DEFER the signed `relay_peer_probe`, tracked as #12539. The smaller variant, the
B.5 fingerprint line, is included. `apps/web-platform/infra/ci-deploy.sh` is not edited, so
`host_scripts_content_hash` does not move.

## Files to Edit

- `apps/web-platform/server/proxy-tls.ts` — B.1
- `apps/web-platform/server/index.ts` — B.1 boot call renamed, at the same position
- `apps/web-platform/server/proxy-hello.ts` — B.2, plus the B.5 helper
- `apps/web-platform/server/session-proxy.ts` — B.3, B.5
- `apps/web-platform/server/sensitive-keys.ts` — B.6
- `apps/web-platform/infra/proxy-hello-hmac.tf` — B.7, header comment only
- `.github/workflows/apply-web-platform-infra.yml` — B.7, text of the HALT remediation line only
- `.github/workflows/reusable-release.yml` — C.1: the marker step, the email wording and the email sentence
- `apps/web-platform/test/proxy-hello.test.ts` — key-set rows; the known-answer vector is unchanged
- `apps/web-platform/test/session-proxy.test.ts` — the `verifyProxyHello` key-set argument (Kieran/sharp-edges: it
  calls the verifier)
- `apps/web-platform/test/session-proxy-hello.test.ts` — sender, server and verifier call sites; degraded states
- `apps/web-platform/test/proxy-tls.test.ts` — loader rows, renamed function
- `apps/web-platform/test/proxy-hello-key-isolation.test.ts` — the second name
- `apps/web-platform/test/server-index-boot-pin-line.test.ts` — boot call rename
- `plugins/soleur/test/preflight-discoverability-test.test.ts` — `BASELINE_DECLARED_PROBES` 96 → 97, with a
  PLACEMENT/TRUTH/NO SUBSTITUTE comment. This plan's `discoverability_test` declares `credentials_required`
  (sharp-edges).
- `scripts/lib/test-affected-paths.sh` — an `AFFECTED_PLUGINS_SOLEUR_TEST_REUSABLE_RELEASE_PUSH_FAILED_MARKER_TEST_SH_PATHS`
  entry, modelled on the zot-mirror-retry entry. Then run `scripts/lint-orphan-test-suites.sh` once the suite is
  tracked.
- `knowledge-base/engineering/architecture/decisions/ADR-323-session-relay-peers-are-admitted-on-the-raw-socket-and-every-hello-is-hmac-signed.md` — B.7 amendment
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` — B.7 relay section
- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md` — B.7 `_PREVIOUS` correction

## Files to Create

- `apps/web-platform/test/proxy-hello-rotation-phases.test.ts` — two-host adjacent-phase round trips (Guard 2)
- `plugins/soleur/test/reusable-release-push-failed-marker.test.sh` — marker step behaviour and placement (Guard 4)
- `knowledge-base/engineering/operations/runbooks/web-platform-release-image-push-failed.md` — C.2

**Not edited (explicit):**

- `apps/web-platform/infra/cloud-init.yml` and `cloud-init-inngest.yml` (#12489)
- `apps/web-platform/infra/ci-deploy.sh` (E deferred; its host-scripts hash does not move)
- `apps/web-platform/server/proxy-deny-report.ts` and its test (T1: grammar unchanged)
- `apps/web-platform/scripts/verify-required-secrets.sh` and its test (T2: presence-only)
- every `.tf` resource block
- `.github/workflows/key-rotate.yml` and `scripts/key-rotate.sh` (#12538)
- both callers of `reusable-release.yml`
- the deploy-token rotation work, #10476 and PR #11676

## Open Code-Review Overlap

None. 94 open `code-review` issues were checked on 2026-11-10 against every path in Files to Edit and Files to
Create, plus the tokens `ADR-323`, `proxy-hello` and `sensitive-keys.ts`. No body names any of them.

## Implementation Phases

TDD order (`cq-write-failing-tests-before`). Run single test files only, never the full or affected gate locally,
because the machine is saturated. CI is the gate. Scratch and logs go under `/var/tmp`.

1. **Phase 1 — verifier slot (B.1, B.2, B.6).**
   - Write the failing rows first: Guard 1 rows in `proxy-hello.test.ts`, loader rows in `proxy-tls.test.ts`, and the
     isolation row.
   - Then implement the loader and verifier.
   - Run `npx vitest run test/proxy-hello.test.ts test/proxy-tls.test.ts test/proxy-hello-key-isolation.test.ts` from
     `apps/web-platform`.
   - Grep the verifier's consumers (`git grep -n 'verifyProxyHello\|loadProxyHelloKey' -- apps/web-platform`) and
     update each one.
2. **Phase 2 — call sites and fingerprint (B.3, B.5).**
   - Write the failing rows first: `session-proxy-hello.test.ts`, `session-proxy.test.ts` and
     `proxy-hello-rotation-phases.test.ts` (Guard 2).
   - Then implement, and update `server-index-boot-pin-line.test.ts`.
3. **Phase 3 — records (B.7).**
   - ADR-323 amendment, the `.tf` comment, the HALT line, the two runbooks.
   - Run `bash tests/scripts/test-destroy-guard-counter-web-platform.sh` and `bun test plugins/soleur/test/terraform-target-parity.test.ts`, single files only.
   - Bump `BASELINE_DECLARED_PROBES` (96 → 97), and add the `test-affected-paths.sh` entry for the new release suite.
4. **Phase 4 — GHCR marker (C.1).**
   - **Measure first, locally.** Never dispatch a workflow to settle this. The commands exist (checked 2026-11-10 with
     `--help` on buildx 0.38.1): `docker buildx history ls --filter status=error --format json` and
     `docker buildx history inspect <ref> --format json`. `setup-buildx-action` v3.12.0 pins no buildx version here, so
     the runner gets a current buildx.
   - **The experiment:** on a throwaway `docker-container` builder under `/var/tmp`, build a two-line image and push it
     to a closed localhost port, so the push fails. Then confirm that the record's error field carries the push error
     text, and capture the JSON path the step will read.
   - **If the field is absent or empty,** ship the fixed `denial=see-step-log` with `class=unknown` and name the residual
     in the PR body (AC-C4).
   - Then write `reusable-release-push-failed-marker.test.sh` (red), then the step.
5. **Phase 5 — runbook (C.2)**, then
   `python3 scripts/lint-infra-no-human-steps.py knowledge-base/engineering/operations/runbooks/web-platform-release-image-push-failed.md`.
6. **Phase 6 — local single-file checks, then push.** CI is the gate. Run `soleur:review` with `user-impact-reviewer`
   (single-user incident).

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-323.** Decision 9, Decision 6, Decision 2, the "No rotation route" consequence and Considered Options, as
set out in B.7. This is a change to an existing ADR's decision (an extension: the verifier key set). No new ADR. The
amendment cites #12538 and #12539.

ADR-320 is unchanged. Its scope note lands with #12538.

### C4 views

**No C4 change.** Checked against all three files on 2026-11-10:

- `spec.c4` and `views.c4` were read in full.
- `model.c4` (288 kB) was enumerated by element definitions and by every edge touching the systems this PR involves,
  not read line by line.

What was found:

- **Actors.** `founder` already approves `key-rotate-approval` dispatches (the `founder -> github` key-rotate edge).
  This PR adds no dispatch.
- **External systems.**
  - `github -> ghcr` (publish/read edges) is unchanged: the marker is a step inside the existing release job.
  - `github -> resend` (release-outcome email) is unchanged: the same failure email gains one sentence.
  - `doppler` is unchanged: the optional slot rides the existing Doppler runtime secrets edge, and no Doppler write is
    added.
  - `betterstack` is unchanged: the new lines ride the existing `hetzner -> betterstack` pino WARN shipping edge.
- **Containers.** `coordinator` ("proxy over one-way-TLS private net") stays true.
- **Access relationships.** None change.
- **Mentions.** `grep -i hello` over the three files returns nothing, so no description is falsified.
- **Count parity.** `bash plugins/soleur/test/c4-count-parity.test.sh` was green on 2026-11-10 (13 passed, 0
  failed). This PR adds no workflow, monitor or heartbeat.

### Sequencing

The ADR-323 amendment describes the verifier half as built and the leak route as **not built** (#12538). No
"adopting" status is needed: the amendment is true at merge.

## Infrastructure (IaC)

### Terraform changes

None to resources. `apps/web-platform/infra/proxy-hello-hmac.tf` changes in its header comment only, so a plan shows no
diff and `relay_hello_key_changes` stays 0. `PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO` is **not** provisioned by this PR. Its
only writer will be the reviewer-gated rotate mode in #12538. No `TF_VAR_` is added.

### Apply path

None. The per-merge apply is a no-op for this diff. The release deploys the new image through the ordinary
merge-to-main pipeline. Downtime: the ordinary rolling deploy. The key is unchanged and the slot is absent, so there is
no relay split.

### Host fan-out

Not applicable. No `terraform_data` provisioner and no host script is touched (`ci-deploy.sh` untouched, so
`host_scripts_content_hash` is unchanged).

### Distinctness / drift safeguards

The slot is optional and absent in `dev` and `prd`. The drift plan sees no change. The HALT's addresses and its
forget/move counting are unchanged (Guard 3, row 3).

### Vendor-tier reality check

Not applicable. No new vendor resource. The Packages budget is an operator money decision (C4 row), not a Terraform
resource.

## Encryption Posture

```yaml
at_rest:
  - store: "Doppler soleur/prd secret PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO (optional slot; not created by this PR)"
    mechanism: "no new store: the slot is a name in the existing Doppler prd config, which already holds PROXY_HELLO_HMAC_KEY; this PR writes no value"
    evidence: "apps/web-platform/infra/proxy-hello-hmac.tf (no new resource); verify-required-secrets.sh unchanged"
    defends_against: "the value never appears in Terraform state, the repo, argv or a log: the loader deletes it from process.env after one read and only an 8-hex domain-tagged HMAC fingerprint is logged"
    does_not_defend: "a principal with Doppler prd read access, or with /proc/<pid>/environ of the app process (ADR-323 residual), can read the slot when it is set; the CURRENT key's Tier-A state exposure remains until #12538"
    disclosed_as: "ADR-323 Decision 6 and Decision 9 (amended), Consequences 'Tier-A exposure, and ADR-320'"
    live_verification: "relay_hello_key_fp accept_also=none on both hosts after the deploy (AC-P1)"
in_transit:
  - connection: "web host -> peer web host session relay (10.0.1.x:8443), existing, unchanged"
    tls: "Node https/tls server with the Terraform-provisioned relay certificate; the dialer pins PROXY_TLS_CERT"
    cert_verification: on
    does_not_defend: "a holder of the shared relay TLS key can terminate TLS; a captured hello is replayable to another roster host inside ~61 s (audience unbound, ADR-323 residual); the HMAC (now with an optional accept-only key) is the authentication layer above TLS"
    disclosed_as: "ADR-323 Consequences, named residuals"
```

No `exception` block: no plaintext store and no `cert_verification: off`.

## Observability

```yaml
liveness_signal:
  what: "relay_hello_key_fp current=<8hex> accept_also=<8hex|none> (warn, once per container start on each web host, after the key check); the existing relay_hello_window accepted=<n> denied=<n> suppressed=<n> line is unchanged"
  cadence: "fingerprint: every container start of each web host (not the canary)"
  alert_target: "Better Stack Logs source 2457081 (read via scripts/betterstack-query.sh); existing relay_listener_down alert covers the no-key path"
  configured_in: "apps/web-platform/server/session-proxy.ts (createProxyServer)"
error_reporting:
  destination: "Sentry via reportSilentFallback (feature control_plane_route, ops proxy-hello.accept-also-ignored and proxy-hello.accept-also-equals-current (warn); existing op createProxyServer.no-hello-key); GitHub Actions ::error:: annotation + step summary + the existing release-failed email for SOLEUR_GHCR_PUSH_FAILED"
  fail_loud: true
failure_modes:
  - mode: "hosts hold different CURRENT keys after a deploy (key drift)"
    detection: "the two hosts' newest relay_hello_key_fp current= values differ; relay_hello_window denied>0 with Sentry reason mac"
    alert_route: "Sentry bounded deny event (existing); fingerprint read in betterstack-log-query.md relay section"
  - mode: "accept-also slot set but malformed"
    detection: "one Sentry event op proxy-hello.accept-also-ignored reason=malformed; relay_hello_key_fp accept_also=none"
    alert_route: "Sentry issue"
  - mode: "accept-also slot equal to current (a rotation mistake)"
    detection: "one warn Sentry event op proxy-hello.accept-also-equals-current; relay_hello_key_fp shows accept_also equal to current"
    alert_route: "Sentry issue"
  - mode: "accept-also slot set outside a rotation window (a stale or planted slot)"
    detection: "relay_hello_key_fp accept_also!=none outside a recorded rotation"
    alert_route: "read rule in betterstack-log-query.md in this PR; a Better Stack alert is a #12538 requirement (B.7 (e))"
  - mode: "verifier regression refuses every hello"
    detection: "relay_hello_window denied>0 with accepted=0 on the owner host; users on the peer host loop on 4014"
    alert_route: "Sentry bounded deny events (existing)"
  - mode: "GHCR image push denied"
    detection: "SOLEUR_GHCR_PUSH_FAILED class=<...> attempt=<n> annotation in the push-arm run; email body sentence"
    alert_route: "release-failed email (Resend, existing) + run annotation"
logs:
  where: "Better Stack Logs (container pino WARN+ via Vector) for the relay lines; GitHub Actions run log and step summary for the release marker"
  retention: "Better Stack source retention for 2457081; GitHub Actions default run-log retention (90 days)"
discoverability_test:
  command: "bash scripts/betterstack-query.sh --since 24h --grep relay_hello_key_fp"
  expected_output: "relay_hello_key_fp"
  credentials_required: "Better Stack read creds BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}, injected by `doppler run -p soleur -c prd_terraform --` (the helper refuses without them) — host container logs have no unauthenticated reader"
```

## User-Brand Impact

- **If this lands broken, the user experiences:** if a verifier regression refuses every hello, every user whose
  worktree lease sits on the other web host loops on the 4014 reconnect and cannot reach their session. At LB weight 1
  that is about half of proxied sessions. If the release marker misfires, nothing user-facing changes, because the
  step is `continue-on-error`.
- **If this leaks, the user's workspace and session are exposed via:** a verifier that admits a hello it should refuse
  (an accept-also key used as a signing key, an accept-also key admitting a hello on its own, or a skipped replay or
  skew check on the accept-also path). That yields a token-less act-as-user session on the owner host
  (`attachProxiedSession`), which is account takeover. A logged fingerprint that leaks key bytes would be a second
  vector.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one forged hello is one user's account, so this sits above
  `aggregate pattern`. Live users are 0 today, but this code runs before the first external user.
- **CPO sign-off:** Ruled by CPO agent, 2026-11-10: signed off, on seven conditions, each mapped to an AC below (AC-B1
  to AC-B7, AC-C5, AC-S4). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Guard Contract

### Guard 1 — accept-also is verify-only

**Property.** A hello is admitted only if its MAC matches under the CURRENT key, or under the accept-also key while a
CURRENT key is loaded. The signer never uses the accept-also key, and a hello admitted under either key passes the
same skew, replay and AP-2 checks.

**Assembly.** One chokepoint per direction:

- **Verify:** `verifyProxyHello` in `proxy-hello.ts`. Its only production caller is the owner `message` handler in
  `session-proxy.ts`.
- **Sign:** `signProxyHello`, called only from the sender path in `session-proxy.ts`.
- **Load:** `loadProxyHelloKeys` in `proxy-tls.ts`, the only reader of both variables.
- **Start:** the `createProxyServer` key check, which requires `current`.

At work time, `git grep` must show no other caller of `computeMac` with a loaded key.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Sender passes `acceptAlso` (or the key set) to `signProxyHello` | RED (the signed hello fails on a verifier holding only CURRENT; passing the set is a type error) |
| 2 | `createProxyServer` starts when `current` is `null` but `acceptAlso` is set (use `current ?? acceptAlso`) | RED |
| 3 | Loader accepts a malformed accept-also value (drop `HELLO_KEY_RE` on the second read) | RED |
| 4 | Accept-also path skips the replay check (return before `cache.checkAndInsert`) | RED (a replayed accept-also hello is admitted) |
| 5 | Accept-also path skips the skew check | RED |
| 6 | Own dispatch: the suite never exercises an accept-also accept (0 such rows) | RED (the suite asserts at least one accept-also accept and one `mac` refusal per run) |
| 7 | Second member: a hello signed by a THIRD unrelated key while both slots are set | RED if admitted (it must be refused with `mac`) |

**Harness rows.**

- **Suite mutation:** set the accept-also fixture key to a copy of CURRENT. That makes rows 2 and 7 vacuous, so the
  suite's fixture-distinctness assertion must go RED.
- **Must-PASS (not the canonical vector):** a hello signed with a different synthetic 64-hex key, accepted with that
  key as CURRENT. The suite must not depend on the known-answer key alone.

### Guard 2 — rotation phases are pairwise compatible

**Property.** Two hosts in adjacent rotation phases (P0/P1, P1/P2, P2/P3) complete a signed round trip in both
directions. A skipped phase splits them in the direction the design predicts:

- P2→P0 is refused with `mac`, while P0→P2 is accepted through accept-also old.
- P1→P3 is refused with `mac`, while P3→P1 is accepted through accept-also new.

**Assembly.** `apps/web-platform/test/proxy-hello-rotation-phases.test.ts` builds each host's key state as a
`{signWith, accept}` pair from one test-fixture table, `PHASES`. For every pair it calls the real `signProxyHello` on
one side and the real `verifyProxyHello` on the other. The ADR cites this test as the executable statement of why the
phases exist; the table is not a production definition.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | P1 defined as "sign new, accept {old,new}" (P1 = P2) | RED (a P0 host refuses the P1 host's hellos) |
| 2 | Own dispatch: the pair loop iterates 0 pairs | RED (the suite asserts exactly 3 adjacent pairs x 2 directions = 6 round trips, plus 4 skip-case directions) |
| 3 | Second member: P3 wrongly keeps the old key in the slot | RED (the P1→P3 skip case must be refused) |
| 4 | The P2→P0 skip direction expected to pass | RED |

**Harness rows.**

- **Suite mutation:** stub `verifyProxyHello` to always return `ok`. The refused skip directions must go RED.
- **Must-PASS:** run the table with two different synthetic old/new key pairs.

### Guard 3 — the key names never reach a child environment

**Property.** After boot, neither `PROXY_HELLO_HMAC_KEY` nor `PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO` is in `process.env`,
and neither name is in any child-env allowlist.

**Assembly.**

- **Deletion:** the loader in `proxy-tls.ts`.
- **Allowlists:** `agent-env.ts`, `ALLOWED_SERVICE_ENV_VARS` and `providers.ts`.
- **Name list:** `sensitive-keys.ts`.

The `relay_hello_key_changes` HALT is unchanged by this PR and stays pinned by its existing suites. AC-B9 runs them;
this guard does not re-pin them.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `delete process.env.PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO` | RED (isolation test) |
| 2 | Delete the accept-also variable only when it is well-formed (the deletion moves inside the shape branch) | RED (a malformed value stays in `process.env`) |
| 3 | Own dispatch: the isolation test's name list is empty | RED (the test asserts exactly the two names) |
| 4 | Second member: add the accept-also name to `ALLOWED_SERVICE_ENV_VARS` while the CURRENT name stays correctly absent | RED |

**Harness rows.**

- **Suite mutation:** set the variable after the loader runs and before the assertion. The deletion assertion must go
  RED.
- **Must-PASS:** an unset accept-also variable (the default) passes with no Sentry event.

### Guard 4 — the GHCR marker fires exactly on a failed push and never changes the verdict

**Property.** When `docker_build` fails, exactly one closed-grammar `SOLEUR_GHCR_PUSH_FAILED` line is emitted with the
run attempt. The step never runs on success, never fails the job, and its text cannot inject a workflow command.

**Assembly.**

- The one step `push_failed_marker` in `reusable-release.yml`: its `if:`, its position immediately after `docker_build`,
  `continue-on-error`, its `env:` and its `run:` body.
- The email step's one conditional sentence.
- The extractor in `reusable-release-push-failed-marker.test.sh` (`extract_run_block` precedent).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `if:` becomes `failure()` only (fires on any earlier failure, e.g. JWT checks) | RED (static row pins the exact expression) |
| 2 | Drop `continue-on-error: true` | RED |
| 3 | Move the step after the zot mirror steps | RED (adjacency row) |
| 4 | Normalisation keeps LF (or a `::` run), so a denial containing `\n::warning::x` forges a second workflow command | RED (fixture asserts exactly one output line starts with `::`, and it is the step's own `::error::SOLEUR_GHCR_PUSH_FAILED`) |
| 4b | The `denial=` read prints a build record's build-arg section instead of only the error field | RED (fixture record carries a fake `SENTRY_AUTH_TOKEN=` build-arg; the token is absent from stdout, the summary and `$GITHUB_OUTPUT`) |
| 4c | `timeout-minutes: 1` removed from the step | RED (static row) |
| 4d | The email's "re-running this workflow is safe" wording restored | RED (static row pins "a fresh 'Run workflow' dispatch is not") |
| 5 | Remove the 300-character cap | RED (400-character fixture) |
| 6 | Own dispatch: the extractor returns an empty block and the behaviour rows run nothing | RED (suite asserts the block is non-empty and the stub `docker` was invoked) |
| 7 | Second member: a second fixture record (an older failed build) placed after the newest one | RED if the step reads the older record's error (it must read the newest failed record only) |
| 8 | A `${{ }}` inside the `run:` body | RED |

**Harness rows.**

- Suite mutation: a stub `docker` that ignores its arguments. The class rows must still discriminate, so a stub that
  makes every row `unknown` must go RED.
- Must-PASS: a `denied:` line from a different registry message (`denied_other`). A history read that fails must give
  `denial=see-step-log` with `class=unknown`.

### Guard 5 — the fingerprint does not disclose key bytes

**Property.** `relay_hello_key_fp` values are domain-separated HMAC outputs under `"soleur-relay-hello-key-fp-v1"`,
and the two slots are fingerprinted independently.

**Assembly.** `helloKeyFingerprint` in `proxy-hello.ts` is the only producer. The `createProxyServer` log call is its
only consumer.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Any change to the derivation: no domain tag, `HELLO_DOMAIN`, a plain SHA-256, or a raw-key prefix | RED (a known-answer row: `helloKeyFingerprint(K)` equals the hand-computed first 8 hex of HMAC-SHA256(K, `"soleur-relay-hello-key-fp-v1"`), and differs from the first 8 hex of K's hex, base64 and SHA-256) |
| 2 | Own dispatch: the log line carries a literal placeholder instead of the helper's output | RED (the line's value equals `helloKeyFingerprint(key)` for the fixture key) |
| 3 | Second member: `accept_also=` computed with the CURRENT key | RED (two distinct fixture keys give two distinct values) |

**Harness rows.**

- **Suite mutation:** use the same fixture key for both slots. That makes row 3 vacuous, so a distinctness assertion
  must go RED.
- **Must-PASS:** `accept_also=none` when the slot is unset.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Re-read the bodies of epics #8211 and #12167 and the runbook ... Then spawn soleur:engineering:cto and ask it what PR B / the next arc step is. Record the answer in the plan" [brief] | Next Arc Step (Item A); decision-challenges row A | mapped |
| 2 | "Do NOT start PR B unless the CTO's ruling shows it IS one of the items below" [brief] | Item A: PR B already ran; nothing started | mapped |
| 3 | "The CTO rules between dual-key _PREVIOUS verification and minting the key outside Terraform per ADR-320 decision 2 (or a third option). Plan the implementation of the ruled design and the ADR-323 amendment." [brief] | B.1-B.7; Files to Edit (server, ADR-323); #12538 | mapped |
| 4 | "It must land before the second web host serves external users." [brief] | AC-S4 (#12538 linked as a blocker on #8211 at ship); ADR-323 amendment wording | mapped |
| 5 | "prefer a design that ships dark, with no new secret required at merge" [brief] | B: slot absent by default; verify-required-secrets.sh unchanged | mapped |
| 6 | "Plan diagnostics so a recurrence reports itself: a SOLEUR_* marker carrying the denial text and attempt number, reachable from Better Stack or the run log." [brief] | C.1; Guard 4 | mapped |
| 7 | "Also plan a runbook entry: check Billing > Packages first; recover with \"Re-run failed jobs\" on the push run, never a fresh dispatch" [brief] | C.2 | mapped |
| 8 | "do not plan that" (Zot) [brief] | C.2 out-of-scope line; Cut List | mapped |
| 9 | "Raising a budget is the operator's call: list it as an operator ACTION only." [brief] | decision-challenges row C4; C.2 operator decision line | mapped |
| 10 | "Only note in the plan that the job is expected to go green when #12489 merges, plus a post-merge check." [brief] | D section; AC-P4 | mapped |
| 11 | "Candidate, CTO rules include or defer." (E) [brief] | E: deferred (#12539); fingerprint variant in B.5 | mapped |
| 12 | "STOP BEFORE MERGE" [brief] | Overview; AC-S1 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| B.1-B.3, B.6 accept-only slot (proxy-tls, proxy-hello, session-proxy, sensitive-keys, index.ts, tests) | asks 3, 5 | asked |
| `preflight-discoverability-test.test.ts` baseline bump; `test-affected-paths.sh` entry | — | inferred — justification: enforcement contracts; the declared probe count and the affected-paths index go red without them |
| B.5 fingerprint line | "(or a third option)"; E "so ... key drift shows as a hello-deny" | asked (CTO-ruled smaller variant of E) |
| B.7 ADR-323 amendment, `.tf` header comment, HALT remediation line, job-rationale and betterstack-log-query runbooks | ask 3 "and the ADR-323 amendment" | asked (the other records restate Decision 9 and would otherwise contradict it, P3) |
| `proxy-hello-rotation-phases.test.ts` | — | inferred — justification: the enforcement contract of the three-phase design; without it the reason the phases exist is untested (CTO guard row 4) |
| C.1 marker step + email sentence; `reusable-release-push-failed-marker.test.sh` | ask 6 | asked |
| C.2 runbook | asks 7, 9 | asked |
| #12538 tracking issue | ask 3 "minting the key outside Terraform" (the ruled second half) | asked |
| #12539 tracking issue | ask 11 | asked (deferral needs a tracker, `wg-when-deferring-a-capability-create-a`) |
| D post-merge read | ask 10 | asked |

### Split Assessment

- Subsystems touched: 4. They are `apps/web-platform`, `.github`, `plugins/soleur` (one test file) and
  `knowledge-base` (ADR and runbooks).
- Planned files: 22 (19 edits, 3 creates). Estimated changed lines: about 600.
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines.
- Recommendation: split. The seam is B (relay key slot, `apps/web-platform/server/**` plus ADR-323) versus C (the
  release marker, `.github/workflows/reusable-release.yml` plus the runbook). It is **not taken**: the brief requires
  "ONE PR covering the items below". The root count is at the threshold only because the docs and one release test
  live in their own roots. Recorded as a scope row in `decision-challenges.md`.

## Acceptance Criteria

### Pre-merge (agent-verifiable in CI and in the PR)

- [ ] **AC-B1** (CPO 1): a hello signed with the accept-also key and replayed is refused with `replay`, and one outside
      +-30 s is refused with `skew` (`proxy-hello.test.ts`). Guard 1 rows 4 and 5.
- [ ] **AC-B2** (CPO 2): with both keys set, the hello the sender emits verifies under CURRENT only and fails on a
      verifier holding only the accept-also key (`session-proxy-hello.test.ts`). Guard 1 row 1.
- [ ] **AC-B3** (CPO 3): with the slot absent, the pre-existing rows of `proxy-hello.test.ts` (the known-answer vector
      included), `session-proxy.test.ts` and `session-proxy-hello.test.ts` keep their asserted values. The only edits to
      those rows are the key-set argument `{ current: KEY, acceptAlso: null }` and the loader's new name. The success
      result shape `{ ok: true, userId, workspaceId }` is unchanged.
- [ ] **AC-B4** (CPO 3): each loader state has its own test, which asserts relay behaviour and the exact Sentry events.
      Each event payload is scanned for the fixture key's hex and base64 forms, and they must be absent.
  - **Slot unset:** 0 events.
  - **Slot malformed:** exactly 1 `proxy-hello.accept-also-ignored` event with `reason: "malformed"`, and the slot is
    absent.
  - **Slot equal to current:** exactly 1 warn-level `proxy-hello.accept-also-equals-current` event, the slot is kept, and
    the fingerprint line shows equal values.
  - **Slot set, current absent:** exactly 1 `createProxyServer.no-hello-key` event, 0 accept-also events, and no
    listener.
  - **Both unset:** exactly 1 `createProxyServer.no-hello-key` event.
- [ ] **AC-B5** (CPO 4): `PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO` is in `sensitive-keys.ts`. The isolation test proves it is
      absent from `process.env` after boot and from every child-env allowlist (Guard 3).
- [ ] **AC-B6** (CPO 5): the Guard 5 fingerprint tests pass. The `relay_hello_window` line is byte-identical to
      `origin/main`: `git diff origin/main...HEAD -- apps/web-platform/server/proxy-deny-report.ts` prints nothing.
- [ ] **AC-B7**: `proxy-hello-rotation-phases.test.ts` passes. It runs 6 adjacent round trips, and the four
      skip-case directions are asserted exactly as Guard 2 states:
  - P2→P0 is refused with `mac`;
  - P0→P2 is accepted;
  - P1→P3 is refused with `mac`;
  - P3→P1 is accepted.
- [ ] **AC-B8**: ADR-323 is amended as in B.7 and cites #12538 and #12539. The `.tf` header, the HALT remediation line,
      `apply-web-platform-infra-job-rationale.md` and `betterstack-log-query.md` say the same. Check:
      `git grep -n '_PREVIOUS' -- apps/web-platform/infra/proxy-hello-hmac.tf .github/workflows/apply-web-platform-infra.yml knowledge-base/engineering/architecture/decisions/ADR-323-*.md knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`
      prints exactly the ADR-323 lines under `## Considered Options` that explain why `_PREVIOUS` was rejected, and no
      other line.
- [ ] **AC-B9**: the `relay_hello_key_changes` HALT's addresses, counter, forget/move counting and position are
      unchanged. `bash tests/scripts/test-destroy-guard-counter-web-platform.sh` and
      `bun test plugins/soleur/test/terraform-target-parity.test.ts` pass.
- [ ] **AC-B10**: no `.tf` resource block changes. The check
      `git diff -U0 origin/main...HEAD -- 'apps/web-platform/infra/*.tf' | grep -E '^[+-][^+-]' | grep -vE '^[+-]\s*#'`
      prints nothing. `git diff --name-only origin/main...HEAD` lists neither `apps/web-platform/infra/ci-deploy.sh` nor
      `apps/web-platform/scripts/verify-required-secrets.sh`.
- [ ] **AC-C1**: `bash plugins/soleur/test/reusable-release-push-failed-marker.test.sh` passes every Guard 4 row,
      including:
  - the build-arg token fixture;
  - the LF-injection fixture;
  - the no-build-ref fallback;
  - when `denial=` is measured, the v0.402.0 error text as a fixture, which yields `class=denied_write_package`.
- [ ] **AC-C2**: the reusable `release` job's `permissions:` block is byte-identical to its merge-base copy. Compare the
      block in `git show "$(git merge-base origin/main HEAD)":.github/workflows/reusable-release.yml` with HEAD's.
      `bash plugins/soleur/test/reusable-release-caller-permissions.test.sh` passes unchanged.
- [ ] **AC-C3**: the runbook exists, and the CI form of the lint passes on the branch:
      `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`. The runbook names both re-runs, the
      deploy-arm lookup command and "never a fresh dispatch".
- [ ] **AC-C4**: `denial=` is either measured (Phase 4 note in the PR body: buildx version and the JSON field path) or
      shipped as the fixed `see-step-log`, with the residual named in the PR body.
- [ ] **AC-C5** (CPO 7): the runbook says the Packages budget is the operator's money decision, and that the agent stops
      and reports at that point, with no workaround.
- [ ] **AC-D1**: `git diff --name-only origin/main...HEAD` lists neither `apps/web-platform/infra/cloud-init.yml` nor
      `apps/web-platform/infra/cloud-init-inngest.yml`.
- [ ] **AC-G1**: `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch feat-one-shot-8211-hello-key-rotation-ghcr-diag`
      exits 0.

### Ship-time (before the owner-gated merge)

- [ ] **AC-S1**: the PR stays unmerged. Ship stops before merge.
- [ ] **AC-S2**: the PR body carries:
  - the Item A answer, verbatim-short;
  - the B and E rulings;
  - `Ref #8211`, `Ref #12538` and `Ref #12539`;
  - the operator ACTION line (Packages budget);
  - item D recorded as pre-existing;
  - `Closes #12167`. AC-S3 is the evidence; if AC-S3's read fails, use `Ref #12167` and post the measurement on #12167.
- [ ] **AC-S3** (T5): run
      `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 72h --grep relay_peer_probe`.
      It must show `relay_peer_probe peer=10.0.1.x result=ok` rows from both hosts in source 2457081. The rows are
      user.notice, which is the measured level and is enough under T5. The #12167 closing comment cites:
  - serve run 42488889045 ("relay evidence GREEN live");
  - the `relay_peer_probe_failed` alert resource;
  - #12168, #12233, #12292, #12390 and #12414.
- [ ] **AC-S4** (CPO 6): `gh issue edit 8211 --add-blocked-by 12538` has run. Moving #12538 to an onboarding milestone
      is an operator scheduling call (decision row G).
- [ ] **AC-S5**: the epic comment on #8211 is worded "in PR #12536, pending owner merge" and carries:
  - the Item A answer;
  - the B and E rulings;
  - links to #12538 and #12539.

### Post-merge (agent-runnable reads; the owner gates every write)

- [ ] **AC-P1**: after the release deploys, run
      `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 2h --grep relay_hello_key_fp`.
      It must show one line per web host from this deploy, with the same `current=` value and `accept_also=none`.
      Failure branches:
  - **Two `current=` values differ:** stop. File an issue referencing #8211. Do not roll back, because the key value did
    not change in this PR; it is pre-existing drift.
  - **A host has no row:** check its `relay_probe proxy_state=` line. If it is `error`, look for
    `createProxyServer.no-hello-key` in Sentry. If the line is absent, the host has not restarted onto this image yet.
  - **`accept_also!=none` anywhere:** a slot is set outside any rotation. Treat it as an alarm and escalate on #12538.
- [ ] **AC-P2**: if any host shows `accept_also!=none`, Sentry has exactly the AC-B4 event for that state, and the
      canary may add one more. With the slot unset there is nothing to read; that is expected, not a pass signal.
- [ ] **AC-P3**: #8211 item 1 stays open until the owner host shows a `relay_hello_window accepted=<n>` row with `n>0`
      from a real proxied session. The owner runs that session; the agent reads the row.
- [ ] **AC-P4** (D): after #12489 merges, select the newest **completed** `infra-validation.yml` run on `main` whose
      `headSha` satisfies `git merge-base --is-ancestor <#12489 merge sha> <headSha>`. Its
      `gh run view <id> --json jobs` must show every `deploy-script-tests*` job with `conclusion == success`. If not,
      file a tracking issue (milestone `Post-MVP / Later`, `Mandated-By: wg-when-tests-fail-and-are-confirmed-pre`).

## Domain Review

**Domains relevant:** engineering, product

### Engineering

**Status:** reviewed

**Assessment:** CTO agent rulings A, B (amended), E and C1-C3, recorded in `decision-challenges.md`.

### Finance (operator decision only)

**Status:** reviewed

**Assessment:** no spend change is planned. The org Packages budget (0, usage blocked) is named as an operator money
decision (C4). No domain-leader spawn: nothing to model until the operator decides.

### Product/UX Gate

**Tier:** none (no UI surface). A product sign-off was still taken because the threshold is `single-user incident`.

**Decision:** reviewed

**Agents invoked:** soleur:product:cpo

**Skipped specialists:** none

**Pencil available:** N/A (no UI surface)

#### Findings

The CPO signed off on seven conditions; each is mapped to an AC above. #12539 may stay in Later.

## GDPR / Compliance Gate

`soleur:gdpr-gate` ran at plan Phase 2.7 on 2026-11-10. It was triggered because the threshold is `single-user incident`;
the canonical path regex matched no planned file. Result: path scan complete, 22 examined, 0 matched, no findings. The
plan adds no schema, column or FK, and no vendor. The new log lines carry no personal data: counts, enum tokens, an
8-hex domain-separated key fingerprint, an image ref and a run URL. This is advisory only, not legal review.

## Test Scenarios

Single files, run locally from `apps/web-platform` unless noted; CI is the gate.

1. `npx vitest run test/proxy-hello.test.ts`: the key-set verifier, Guard 1 rows, the known-answer vector unchanged.
2. `npx vitest run test/proxy-tls.test.ts test/proxy-hello-key-isolation.test.ts`: the loader, deletion of both names,
   the degraded states.
3. `npx vitest run test/session-proxy-hello.test.ts test/session-proxy.test.ts`: the sender signs CURRENT, server
   start rules, the fingerprint line.
4. `bun test plugins/soleur/test/preflight-discoverability-test.test.ts`: the probe baseline (97).
5. `npx vitest run test/proxy-hello-rotation-phases.test.ts`: Guard 2.
6. `npx vitest run test/server-index-boot-pin-line.test.ts`: the boot-call position.
7. From the repo root:
   - `bash plugins/soleur/test/reusable-release-push-failed-marker.test.sh`
   - `bash plugins/soleur/test/reusable-release-caller-permissions.test.sh`
   - `bash tests/scripts/test-destroy-guard-counter-web-platform.sh`
8. `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (the CI form), then
   `bash scripts/lint-orphan-test-suites.sh`.

## Dependencies & Risks

- **R1. Verifier signature change.** `verifyProxyHello` gains a key-set parameter. Every consumer is updated in the
  same commit (`hr-type-widening-cross-consumer-grep`): production is `session-proxy.ts` only; tests are listed.
- **R2. The JSON error field of a failed push's build record is unmeasured.** The runner's buildx is 0.38.1 and has
  the commands. Phase 4 measures the field locally. The fallback is the fixed `see-step-log`; the marker still carries
  `class=unknown` and the attempt number.
- **R3. Measured 2026-11-10: no test pins the HALT remediation line's text** (the `git grep` in B.7 prints nothing).
  The addresses and counting stay pinned by their existing suites.
- **R4. `deploy-script-tests (4/4)` may be red on this PR's CI** until #12489 merges. It is pre-existing (D), and the
  PR body says so.
- **R5. Release path.** The marker step is `continue-on-error` and failure-gated, so a success run never executes it.
  A bug in it cannot block a release.
- **R6. No leak response until #12538 lands.** This is disclosed in ADR-323 and in the PR body, and #12538 blocks
  onboarding.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, holds only placeholder text, or omits the threshold fails
  `deepen-plan` Phase 4.6. This one is filled.
- Do not name the slot `_PREVIOUS` anywhere in code. In P1 it holds the NEW key.
- Never add the slot to `verify-required-secrets.sh`. It is optional, and a REQUIRED entry would block every deploy
  until a value exists. The hard shape checks belong to #12538's rotate mode (T2).
- Never change the `relay_hello_window` grammar in this PR (T1). #12538 freezes the line grammars when its parser lands (T3).
- `relay_hello_key_fp` is the only key-derived value that may reach a log. Any new log of key material, even a hash
  without the domain tag, is a Guard 5 violation.
- Ship stops before merge. The epic comment and the `--add-blocked-by` link are ship steps, not plan or work steps.
