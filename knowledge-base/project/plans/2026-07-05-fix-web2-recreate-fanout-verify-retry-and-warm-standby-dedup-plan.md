---
title: "fix(infra): web-2-recreate fan-out verify retries the fresh-boot degraded window + migrate warm_standby onto the shared script"
date: 2026-07-05
type: fix
issues: ["#6051", "#6040"]
branch: feat-one-shot-6051-6040-fanout-verify-retry
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ["ADR-068 (amend — off-host verify degraded-retry semantics)"]
---

# fix(infra): web-2-recreate fan-out verify retries the fresh-boot degraded window + end the warm_standby verify-poll duplication

🐛 **Primary (#6051):** the `web_2_recreate` off-host verify (`deploy-status-fanout-verify.sh`)
aborts RED on the **first** `ok_peer_fanout_degraded` completion, but a fresh
`terraform apply -replace` boot of web-2 takes **~10 min** (apt + docker + multi-image
pull + webhook-enable). At fan-out time web-2's `:9000` is unbound → the single fan-out
degrades → terminal `exit 1` — even though web-2 goes on to boot fine. This is a
**verify-timing bug**, not a safety/destruction issue (apply + destroy-guard + volume
preservation all succeeded on run 28747333763; web-1 untouched; prod stayed 200).

♻️ **Coupled (#6040):** the same shared script (`deploy-status-fanout-verify.sh`, extracted
by PR #6030) was never adopted by the pre-existing `warm_standby` job, which still carries
a **~94-line inline copy** of the verify poll → two divergent copies of a load-bearing
off-host verify. #6051's fix edits the shared script; migrating `warm_standby` onto it in
the **same PR** means both paths inherit the retry robustness and the drift hazard ends
atomically (auto-closes the `warm-standby-verify-dedup-6030` follow-through).

## Enhancement Summary

**Deepened on:** 2026-07-05
**Research agents:** architecture-strategist, spec-flow-analyzer, user-impact-reviewer,
observability-coverage-reviewer (+ Fable scoped-advisor consult at plan Phase 4.5). Mechanical
gates: User-Brand Impact (4.6 ✓), Observability (4.7 ✓), PAT-shaped (4.8 ✓, none), network-outage
(4.5, N/A — timing bug not connectivity), Downtime & Cutover (4.55 ✓).

### Key improvements (all applied)
1. **P0 fixed (2-agent convergence — spec-flow + architecture):** the first-draft marked the
   degraded `start_ts` consumed on FIRST sight, making the single retry UNREACHABLE for a real
   static fresh-boot state → #6051 would have silently survived. Now `retried` is marked only
   when the retry fires; `elapsed` is re-checked every poll. AC3d is the regression guard.
2. **Design corrected earlier (Fable consult):** replaced the 6×/90 s-cadence retry (which
   would stack POSTs onto the deploy `flock` → `lock_contention` terminal RED) with a single
   retry after a fresh-boot window + `lock_contention`-retryable handling.
3. **DEPLOY_TAG reassignment across retrigger** (spec-flow P1) — else a tag advancing during
   the wait RED's a healthy web-2. AC3e added.
4. **Concrete poll-budget + timeout ACs** (arch + user-impact P1) — `120×15=1800 s`, recreate
   job only; timeout-vs-drain residual documented. AC5b/AC5c added.
5. **Two false-framing scope-outs surfaced by user-impact:** accept-only `reason==ok` (not
   web-2 health, private-net-invisible — FINDING 2) and cross-pipeline uncounted web-1 swap
   (FINDING 1) — both converted from silent gaps to explicit scope-outs + deferred trackers.

### New considerations discovered
- `RETRIGGER_MIN_INTERVAL_S` (first-draft artifact) stripped from Files to Edit.
- `START_TS==0` corrupt-fallback collision guard added.
- web-1 re-swap bound tightened from ~7 (first draft) to ≤2.

## Overview

Two tightly-coupled changes to the ADR-068 off-host web-2 acceptance verify, shipped in
one PR because #6051 modifies the exact shared script #6040 asks `warm_standby` to adopt:

1. **Retry the fan-out ONCE after the fresh-boot window (#6051, Fix Option 1 — the
   durable fix).** Treat `*_peer_fanout_degraded` as **retryable**: on the first degraded
   completion, passively wait out the remaining fresh-boot window (~10 min from the
   `-replace`), then re-POST the deploy fan-out **once** and verify. This bounds web-1
   (the sole live prod origin) to **at most 2 swap cycles total** (initial + 1 retry) —
   NOT a short-backoff loop. Preserve every existing invariant: single-peer
   `ROSTER_COUNT==2` guard, `start_ts` staleness gate, full-anchor tag validation,
   tag-downgrade race guard, and **terminal `exit 1` on budget exhaustion** (NO
   green-on-timeout) and on any unexpected reason / non-zero exit code — but treat
   `lock_contention` as **retryable** (a transient deploy-lock overlap), not terminal.

2. **Migrate `warm_standby` onto the shared script (#6040 — collapse-to-one-call,
   regression-closed).** Replace `warm_standby`'s 3 inline polling steps (baseline +
   trigger + verify) with a single call to `deploy-status-fanout-verify.sh`, parameterized
   by `OP_CONTEXT` for the context-specialized recovery messaging, and having the script
   emit `deployed_tag` to `$GITHUB_OUTPUT` so the surviving `Warm-standby summary` step
   keeps its consumed output. This neutralizes #6040 Option 1's stated downside (it does
   NOT dismantle the summary's `deployed_tag` output). `warm_standby`'s terraform
   plan/apply (attach-proof) steps are UNCHANGED — only the polling steps migrate.

Both paths run the same retry logic. For `warm_standby` (web-2 already booted) the first
fan-out returns `reason==ok` → the retry branch never fires → behavior is unchanged.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue/premise) | Codebase reality (verified) | Plan response |
|---|---|---|
| `SETTLE_SECONDS=30` + one-shot fan-out is inherited from warm-standby | Confirmed: `deploy-status-fanout-verify.sh:37` default 30; `web_2_recreate` env sets it (`.github/workflows/apply-web-platform-infra.yml:1081`) | Keep default 30; the retry loop — not a longer settle — covers the fresh-boot window (Fix Option 1, not 2) |
| Terminal abort is on first `ok_peer_fanout_degraded` | Confirmed: `deploy-status-fanout-verify.sh:136-138` `exit 1` on `*_peer_fanout_degraded` inside the `exit_code==0` arm | This single `exit 1` is the bug surface; convert to a bounded-retry branch |
| Each fan-out re-swaps web-1 first | Confirmed: `ci-deploy.sh:1325` `fan_out_to_peers` runs AFTER web-1's own swap; `reason=ok_peer_fanout_degraded` set at `ci-deploy.sh:1328` when the peer did not return 202 | Retry AMPLIFIES web-1 re-swaps → cap at **1 re-POST** (max 2 swaps total), gated on the fresh-boot window (see User-Brand Impact + advisor consult) |
| A re-POST is a cheap ~50 ms no-op on the same tag | **False for web-platform** — the ~50 ms same-tag no-op at `ci-deploy.sh:1356` is the **inngest** case; the web-platform path re-runs the full canary + cron-drain (`CRON_DRAIN_TIMEOUT=4200`s, `:190`) + docker stop/rm/run | Do NOT re-POST on a short cadence; single retry after the boot window only |
| Overlapping re-POSTs are harmless | **False** — a POST landing inside an in-flight deploy's critical section loses `flock -n` → `final_write_state 1 "lock_contention"` (`ci-deploy.sh:846-849`), exit_code=1 → the verify `*)` branch would treat it as terminal RED | Treat `exit_code=1 && reason=lock_contention` as retryable in the verify; single-retry design avoids overlap by construction |
| `warm_standby` carries an inline copy, not the shared script | Confirmed: inline baseline/trigger/verify at `apply-web-platform-infra.yml:808-1026`; `web_2_recreate` sources the shared script at `:1334` | Migrate warm_standby onto the shared script (option 1-enhanced) |
| `pre_start_ts` / `deployed_tag` are cross-step outputs the summary needs | `pre_start_ts` (`:938`) is consumed ONLY by the inline Verify step (removed); `deployed_tag` (`:1036`) is consumed by the Verify step AND the `Warm-standby summary` step | Script emits `deployed_tag` to `$GITHUB_OUTPUT` when set; `pre_start_ts` becomes script-internal |
| `warm-standby-verify-dedup-6030` probe scopes to the warm_standby job block | Confirmed: `scripts/followthroughs/warm-standby-verify-dedup-6030.sh:30-40` awk-isolates the warm_standby block then greps for the script name | Migration makes the probe PASS → auto-closes #6040; no probe edit needed |
| ci-deploy is idempotent + a full retry re-delivers | Confirmed: ADR-068 line 374 ("`ci-deploy.sh` is idempotent + flock-serialized → a full retry re-delivers"). | The in-verify retry operationalizes ADR-068's already-stated "idempotent re-dispatch" recovery contract inside the fresh-boot window |
| Mechanism (retry) is not a rejected ADR alternative | ADR-068 records "idempotent re-dispatch" as the recovery contract; no ADR rejected in-verify retry | Amend ADR-068 (not a new ADR) to document the in-verify bounded retry |
| Could a single fan-out + longer *passive* poll avoid re-swapping web-1? | **No** — `fan_out_to_peers` (`ci-deploy.sh:134-173`) is single-attempt **fire-and-forget with NO host-side peer retry**; once web-2 :9000 is unbound at fan-out time, web-1 sets `ok_peer_fanout_degraded` and never re-attempts the peer on its own | The client-side re-POST from the verify is the ONLY off-host mechanism to re-deliver to web-2 after it boots (deploy-peer is private-net-deny). Retry is architecturally required; web-1 re-swap amplification is intrinsic to the current webhook topology → bound it, defer the web-2-only-path capability |

## User-Brand Impact

**If this lands broken, the user experiences:** the operator-run `web-2-recreate` dispatch
(a hard prerequisite of the ADR-068 GA cutover) RED-fails even when web-2 booted fine — OR,
worse, the retry masks a genuine web-2 failure and reports green. A mis-tuned backoff could
also re-swap web-1 (the sole live prod origin, `app.soleur.ai`) repeatedly, and each
non-perfectly-graceful re-swap risks a transient `521` on end-user requests (observed once
as a single-probe 521 that recovered in ~3 s on run 28747333763 — the secondary finding).

**If this leaks, the user's workflow is exposed via:** N/A — no user data, secrets, or PII
are read/written; the change is CI verify-loop control flow over the existing signed
`deploy-status` / `deploy` webhooks (HMAC + CF-Access already in place).

**Brand-survival threshold:** single-user incident — because the retry re-swaps web-1 (the
prod origin) **at most one extra time** (max 2 swaps total), and a real user hitting
`app.soleur.ai` during a swap window could see a transient `521`. Capping the retry at
`DEGRADED_RETRY_MAX=1` and gating it on `FRESH_BOOT_WINDOW_S` (so the single re-POST fires
only after web-2 has had time to bind, never stacking POSTs onto an in-flight deploy) is the
load-bearing mitigation; this is why `requires_cpo_signoff: true` and `user-impact-reviewer`
runs at review time.

**Scope-out — `reason==ok` is accept-only, not web-2-health (user-impact FINDING 2).**
`reason==ok` is written when web-2 returns HTTP 202 to the fan-out trigger and binds `:9000`
(`ci-deploy.sh:1325-1328`) — it proves web-2 **accepted** the deploy, NOT that web-2's own
post-accept canary/health passed (`cosign_verify_failed`, `canary_sandbox_failed`, etc. occur
on web-2's host AFTER acceptance). Per `ci-deploy.sh:131`, web-2's per-host deploy SUCCESS is
"soak-verified via the peer's deploy-status over the **private net**" — which the off-host CI
runner CANNOT reach (private-net-deny, the whole ADR-068 topology constraint). So an off-host
verify can only ever prove acceptance + `:9000` bind; this is the **intended ADR-068 verify
contract**, pre-existing and shared identically with `warm_standby`. The retry does not widen
this (it re-attempts acceptance, not health). **Deliberately scoped out here**, tracked as a
GA-cutover prerequisite (see Deferred): a full web-2 post-accept health confirmation needs a
private-net probe, which the ADR-068 GA cutover must add before routing live traffic to web-2.

**Scope-out — `reason==ok` is accept-only, not web-2-health (user-impact FINDING 2, pre-existing).**
`reason==ok` proves web-2 ACCEPTED the fan-out (HTTP 202 + `:9000` bound); it does NOT prove
web-2's own post-accept canary/health (`cosign_verify_failed`, `canary_sandbox_failed`,
`production_start_failed` occur on web-2's host and are soak-verified only over the PRIVATE
net — `ci-deploy.sh:131`). The off-host CI runner is private-net-deny, so this verify
**cannot** see web-2's post-accept health by construction — a pre-existing topological limit
shared with `warm_standby`, not introduced by the retry (the retry only makes the *acceptance*
signal easier to reach, which is exactly its job). The ADR-068 contract for this verify is
"web-2 accepted + bound `:9000`", and web-2 is weight-0 / drained throughout, so an
accepted-but-unhealthy web-2 serves NO live traffic (zero user exposure) until the operator's
separate GA-cutover health confirmation. Tracked as a deferred item (a private-net web-2
post-accept health probe for the GA cutover) — see Deferred.

## Design Detail

### Retry loop (shared script `deploy-status-fanout-verify.sh`)

> **[Updated 2026-07-05 — Fable advisor consult (Phase 4.5), verified against code.]** The
> first-draft design (6 re-triggers on a 90 s cadence, advancing the staleness baseline) was
> a wrong-architecture trap and is REPLACED. Three verified facts drove the change:
> (1) `fan_out_to_peers` has NO host-side peer retry — a re-POST is required (client re-POST
> is not redundant). (2) BUT the web-platform re-POST is **heavy**: no same-tag short-circuit
> (the ~50 ms no-op at `ci-deploy.sh:1356` is the **inngest** path only), so every re-POST
> re-runs the full canary + **cron-drain gate** (`CRON_DRAIN_TIMEOUT=4200`s bound, `:190`) +
> prod `docker stop/rm/run` on the live origin. (3) A 90 s cadence is far shorter than one
> deploy cycle → stacked POSTs lose `flock -n` and write `reason=lock_contention` with
> `exit_code=1` (`ci-deploy.sh:846-849`), which the verify's `*)` catch-all treats as
> **terminal exit-1** → flaky RED on the exact path this fix targets.

Restructure so the baseline-read + freshest-tag-reread + fan-out POST is a **re-callable
trigger**. On the FIRST `*_peer_fanout_degraded`, passively wait out the remaining
fresh-boot window, then re-POST the fan-out **exactly once**, and verify. Max **2** web-1
swap cycles total (initial + 1 retry). One overall poll budget.

New env knobs (defaults preserve warm_standby semantics; retry is ON for both paths — a
booted warm-standby web-2 returns `ok` on the first fan-out, so the retry branch never fires):

```
DEGRADED_RETRY_MAX      default 1    # exactly one re-POST after the boot window (NOT 6)
FRESH_BOOT_WINDOW_S     default 600  # on 1st degraded, wait until elapsed-since-verify-start ≥ this before the single re-POST
OP_CONTEXT              default "recreate"  # {recreate|warm-standby} selects recovery-message wording
```

Loop skeleton (pseudocode — real edit in `apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh`):

```bash
START_EPOCH=$(date +%s)
retrigger_count=0
declare -A retried         # start_ts values we have ALREADY re-POSTed against (marked ONLY when the retry fires)
for i in $(seq 1 "$STATUS_POLL_MAX_ATTEMPTS"); do
  ... read deploy-status; non-JSON handling UNCHANGED ...
  # Staleness uses the ORIGINAL baseline for the WHOLE run — never advanced (see subtleties).
  if (( START_TS <= PRE_START_TS )); then echo "verify $i: pre-trigger state"; sleep "$INT"; continue; fi
  case "$EXIT_CODE" in
    0)
      [[ "$TAG" != "$DEPLOY_TAG" ]] && { echo "...waiting for $DEPLOY_TAG"; sleep "$INT"; continue; }
      if [[ "$REASON" == "ok" ]]; then echo "web-2 ACCEPTED..."; exit 0; fi
      if [[ "$REASON" == *"_peer_fanout_degraded" ]]; then
        # START_TS==0 is the corrupt-fallback; do NOT let it collide in `retried` (P2).
        (( START_TS == 0 )) && { echo "verify $i: degraded with start_ts=0 (corrupt fallback) — skipping"; sleep "$INT"; continue; }
        if [[ -n "${retried[$START_TS]:-}" ]]; then
          # We already re-POSTed against THIS exact completion; wait for the NEW cycle's fresh completion.
          echo "verify $i: awaiting post-retry completion (already re-fanned this start_ts=$START_TS)"; sleep "$INT"; continue
        fi
        if (( retrigger_count >= DEGRADED_RETRY_MAX )); then
          echo "::error::web-2 still degraded after the single re-POST (reason=$REASON). $(_recovery_msg). RED."; echo "$BODY"|jq .; exit 1
        fi
        elapsed=$(( $(date +%s) - START_EPOCH ))
        if (( elapsed < FRESH_BOOT_WINDOW_S )); then
          # KEY FIX (P0): re-evaluate elapsed EVERY poll — do NOT mark this start_ts consumed here,
          # or the static fresh-boot degraded state would be seen once and never retried.
          echo "verify $i: web-2 not yet bound (reason=$REASON, elapsed=${elapsed}s) — waiting out fresh-boot window before the single re-POST"
          sleep "$INT"; continue
        fi
        echo "verify $i: fresh-boot window elapsed (${elapsed}s), re-POSTing fan-out once (retry $((retrigger_count+1))/$DEGRADED_RETRY_MAX)"
        _retrigger_fanout                 # re-read freshest tag (downgrade guard) + REASSIGN outer DEPLOY_TAG + POST /hooks/deploy (assert 202, else terminal exit 1); does NOT touch PRE_START_TS
        retried[$START_TS]=1; retrigger_count=$((retrigger_count+1))
        sleep "$INT"; continue
      fi
      echo "::error::unexpected reason=$REASON. RED."; echo "$BODY"|jq .; exit 1 ;;
    -1) echo "verify $i: re-swap in flight (reason=$REASON)" ;;
    -3) echo "verify $i: corrupt state read, retrying" ;;
    1) # lock_contention is RETRYABLE, not terminal (a re-POST may briefly overlap the in-flight deploy)
       if [[ "$REASON" == "lock_contention" ]]; then echo "verify $i: deploy lock held by in-flight swap (reason=lock_contention) — retrying"; else
         echo "::error::deploy fan-out failed (exit=1, reason=$REASON). $(_recovery_msg)."; echo "$BODY"|jq .; exit 1; fi ;;
    *)  echo "::error::deploy fan-out failed (exit=$EXIT_CODE, reason=$REASON). $(_recovery_msg)."; echo "$BODY"|jq .; exit 1 ;;
  esac
  sleep "$INT"
done
echo "::error::web-2 fan-out did not accept within budget. $(_recovery_msg). Failing loudly per the recovery contract."; exit 1
```

> **P0 fix rationale (spec-flow + architecture plan-review CONVERGED, 2 agents).** A real
> unbound web-2 emits the SAME static `start_ts` on every poll until a re-swap. The
> first-draft marked `consumed[$START_TS]` on FIRST sight (before the elapsed check), so the
> first degraded poll (which happens at `elapsed ≈ SETTLE`, far below `FRESH_BOOT_WINDOW_S`)
> consumed it and every later poll idled in the "already seen" branch → `_retrigger_fanout`
> was UNREACHABLE and #6051 silently survived (RED-on-timeout, not GREEN). The fix marks
> `retried[$START_TS]` ONLY when the retry actually fires, so `elapsed` is re-checked every
> poll until the window passes. **AC3's fixture MUST hold `start_ts` CONSTANT across the
> repeated degraded polls** (a real static-host state) or it passes for the wrong reason.

Load-bearing subtleties (each an AC below):
- **Do NOT advance `PRE_START_TS`** (the first-draft trap). Keep the ORIGINAL baseline for the whole run and track a `retried` set of `start_ts` values we have re-POSTed against — marked ONLY when the retry fires (the P0 fix above). Advancing the baseline at re-trigger time discards a valid late-arriving `ok` from an EARLIER in-flight cycle (its `start_ts` would fall below the advanced baseline → filtered as "pre-trigger") and adds CI-runner↔host clock skew. Accept the first `ok` with `tag==DEPLOY_TAG && start_ts > original_baseline`.
- **`_retrigger_fanout` MUST REASSIGN the outer `DEPLOY_TAG`** (spec-flow P1). It re-reads/re-validates the freshest tag (tag-downgrade guard preserved); if a newer tag landed during the ≥600 s wait it deploys that tag AND rebinds the `DEPLOY_TAG` the poll's `TAG==DEPLOY_TAG` match compares against — else a genuine `reason==ok` at the new tag never matches, the loop exhausts the budget, and a HEALTHY web-2 reports RED. It asserts HTTP 202 and **terminal-exit-1 on non-202** (does not touch `PRE_START_TS`). AC-covered.
- **`START_TS==0` corrupt-fallback guard** (spec-flow P2): skip degraded-branch processing when `START_TS` is exactly the `0` parse-fallback, mirroring the existing `PRE_START_TS` guard — otherwise a transient corrupt body (exit_code=0 + degraded + start_ts=0) collides in the `retried` map.
- **`lock_contention` is retryable, not terminal.** With the single-retry + boot-window design a re-POST cannot fit inside the prior cycle, but treat `exit_code=1 && reason=lock_contention` as retryable defensively (else a rare overlap RED-flakes a healthy deploy).
- **Budget = boot-window + ONE full deploy cycle**, not attempt-count tuning. Size `STATUS_POLL_MAX_ATTEMPTS × STATUS_POLL_INTERVAL_S` ≥ `FRESH_BOOT_WINDOW_S` (~600 s) + one canary/drain/swap cycle (drain bounded 4200 s but typically short when no cron runs). Current 60×15 = 900 s is TIGHT against 600 s boot + a multi-minute cycle — /work MUST re-measure and likely raise `STATUS_POLL_MAX_ATTEMPTS`, keeping `web_2_recreate` `timeout-minutes: 45` ABOVE the poll budget so the script's loud terminal abort wins the race (`:1070-1077`). Per the deploy-poll-ceiling learning (`2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md`).
- **web-1 re-swap bound:** at most **2** re-swaps total (initial + 1) — a far smaller secondary-finding 521 blast radius than the first-draft 7.
- **`_recovery_msg` is `OP_CONTEXT`-selected** ("recreate landed but web-2 undeployed" vs "attach landed / billing flips") — the intentional per-context divergence noted in #6040.
- **`elapsed=` annotation** on every poll log line (per the deploy-poll-ceiling learning) — the discoverability signal for a future ceiling bump; no prod-side change (`start_ts` already emitted).

### warm_standby migration (`.github/workflows/apply-web-platform-infra.yml`)

- Delete the 3 inline steps `Baseline… (id: baseline)`, `Trigger… (id: trigger)`,
  `Verify… ` (`:808-1026`). Add one step (id e.g. `verify`) that exports
  `OP_CONTEXT=warm-standby`, `SETTLE_SECONDS`, `STATUS_POLL_MAX_ATTEMPTS`,
  `STATUS_POLL_INTERVAL_S`, `WEB_HOST_PRIVATE_IPS`, the webhook/CF secrets, and runs
  `bash "${GITHUB_WORKSPACE}/apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh"`.
- The `Warm-standby summary` step's `CURRENT_TAG: ${{ steps.trigger.outputs.deployed_tag }}`
  becomes `${{ steps.verify.outputs.deployed_tag }}` — the shared script writes
  `deployed_tag=<tag>` to `$GITHUB_OUTPUT` (guarded on `[[ -n "${GITHUB_OUTPUT:-}" ]]`).
- Keep the warm_standby terraform plan (additive 6-target) + apply (attach-proof) steps
  UNCHANGED. `warm_standby` `timeout-minutes: 30` stays (booted web-2 → first-fan-out ok).
- `WEB_HOST_PRIVATE_IPS` stays as a job-env literal on both jobs → `web-hosts-fanout-parity.test.sh`
  still covers both copies unchanged (verify the guard still finds 2 apply-workflow copies).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (retry, unit):** a fixture sequence `degraded → degraded → ok` (start_ts
  advancing) drives `deploy-status-fanout-verify.sh` to `exit 0` — asserts it RETRIES
  rather than aborting on the first degraded. Verified by the new
  `apps/web-platform/infra/deploy-status-fanout-verify.test.sh` with the network removed
  from the assertion path (curl/status stubbed via an injectable status source + POST sink;
  see Test Strategy). RED-proof: with the retry branch reverted, this fixture flips to `exit 1`.
- [ ] **AC2 (terminal on budget, unit):** an all-`degraded` fixture (never `ok`) drives the
  script to terminal `exit 1` with the `::error::` recovery message — NO green-on-timeout.
- [ ] **AC3 (web-1 re-swap bound, unit):** over an all-degraded fixture (with a small
  `FRESH_BOOT_WINDOW_S` so the retry fires quickly in-test), the POST sink records **exactly
  2** fan-out POSTs (initial + 1) — `DEGRADED_RETRY_MAX=1` caps the live-origin churn (the
  secondary-finding 521 blast radius).
- [ ] **AC3b (single retry gated on boot window, unit):** with `FRESH_BOOT_WINDOW_S` set
  large, a `degraded` completion does NOT trigger a re-POST before the window elapses (the
  POST sink shows only the initial POST until the window passes).
- [ ] **AC3c (lock_contention retryable, unit):** a fixture emitting `exit_code=1,
  reason=lock_contention` then later `ok` drives `exit 0` — lock_contention is treated as
  retryable, NOT terminal.
- [ ] **AC3d (no baseline advance / retried-set, unit — P0 regression guard):** a fixture
  emitting the SAME static `start_ts` degraded completion across MANY polls (a real unbound
  fresh boot) drives exactly one re-POST once `FRESH_BOOT_WINDOW_S` elapses — NOT zero (the
  P0 both plan-review agents caught: marking `retried`/`consumed` on first sight makes the
  retry unreachable). Fixture holds `start_ts` constant across the degraded polls.
- [ ] **AC3e (DEPLOY_TAG reassigned across retrigger, unit):** a fixture where a NEWER tag
  lands during the wait and the eventual `ok` reports the new tag drives `exit 0` — proves
  `_retrigger_fanout` rebinds `DEPLOY_TAG` so a healthy web-2 at the advanced tag is not
  RED'd on a permanent `TAG!=DEPLOY_TAG` mismatch (spec-flow P1).
- [ ] **AC3f (retrigger non-202 is terminal, unit):** a fixture where the re-POST returns
  403/500 drives terminal `exit 1` with the `_recovery_msg` (spec-flow P1 — the non-202
  path must not be silently absorbed into the budget-exhaustion message).
- [ ] **AC4 (invariants preserved, unit):** `ROSTER_COUNT!=2` → `exit 1`; a completion with
  `start_ts <= PRE_START_TS` (original baseline) is ignored (staleness); a non-`^v[0-9]…$`
  tag → `exit 1` (full-anchor). Each asserted by a dedicated fixture.
- [ ] **AC5 (warm_standby migrated):** the `warm_standby` job block of
  `apply-web-platform-infra.yml` contains `deploy-status-fanout-verify.sh` and NO inline
  verify poll — verified by `bash scripts/followthroughs/warm-standby-verify-dedup-6030.sh`
  exiting 0 (this is the #6040 auto-close probe).
- [ ] **AC5b (concrete poll budget — no "re-measure later", arch+spec-flow P1):** the
  `web_2_recreate` job env sets `STATUS_POLL_MAX_ATTEMPTS` to a concrete value whose product
  with `STATUS_POLL_INTERVAL_S` ≥ `FRESH_BOOT_WINDOW_S` (600) + one realistic canary/swap
  cycle (~180 s, no concurrent cron drain) + margin — e.g. **`120 × 15 = 1800 s`**. The value
  is set in the recreate job env ONLY, NOT the script default (protects warm_standby's 30-min
  timeout — spec-flow P2). Assert the arithmetic in a workflow comment.
- [ ] **AC5c (timeout above budget + pathological-drain residual, user-impact P1/FINDING 3):**
  the `web_2_recreate` `timeout-minutes` (in seconds) > baseline (~150 s) + `STATUS_POLL`
  budget (1800 s) + pre-verify steps (~600 s) — i.e. keep/raise above ~2550 s (45 min = 2700 s
  holds). Document the residual: a concurrent 70-min `CRON_DRAIN_TIMEOUT` on the re-POST's
  web-1 swap CANNOT fit any sane job timeout; that pathological case times out RED → operator
  idempotent re-dispatch (the recreate is operator-gated, so a heavy in-flight cron is avoidable).
- [ ] **AC6 (summary output preserved):** the `Warm-standby summary` step reads
  `steps.verify.outputs.deployed_tag`; the shared script writes `deployed_tag=` to
  `$GITHUB_OUTPUT`. Verified by a unit fixture asserting the script emits the line when
  `GITHUB_OUTPUT` is set, and by `actionlint`/grep on the workflow (no dangling
  `steps.trigger.outputs.*` reference remains).
- [ ] **AC7 (fan-out roster parity intact):** `bash apps/web-platform/infra/web-hosts-fanout-parity.test.sh`
  still passes and still finds exactly 2 `WEB_HOST_PRIVATE_IPS` copies in the apply workflow.
- [ ] **AC8 (recreate still references the shared script):** `plugins/soleur/test/terraform-target-parity.test.ts`
  passes; extend it to also assert the `warm_standby` block references the shared script
  (lock in the migration so a future revert fails CI), OR document why the follow-through
  probe (AC5) is the sufficient guard.
- [ ] **AC9 (workflow lint):** `actionlint .github/workflows/apply-web-platform-infra.yml`
  clean; embedded `run:` snippets syntax-checked via `bash -c '<snippet>'` (never `bash -n`
  on the YAML).
- [ ] **AC10 (script lint):** `shellcheck apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh`
  and the new `.test.sh` clean (match sibling `.test.sh` conventions).
- [ ] **AC11 (ADR amended):** ADR-068 carries an amendment documenting the in-verify
  bounded degraded-retry semantics (the off-host verify auto-retries the fan-out within a
  bounded fresh-boot window instead of aborting on the first degraded); `Ref #6051`.
- [ ] **AC12 (test registered):** the new `.test.sh` is registered in
  `.github/workflows/infra-validation.yml` (append a `run: bash …` step next to the
  sibling infra `.test.sh` registrations).

### Post-merge (operator)

- [ ] **AC13:** operator re-runs `-f apply_target=web-2-recreate` for the ADR-068 GA cutover
  and observes the verify RETRY the fresh-boot degraded window to `reason==ok` (green).
  `Automation: not feasible because` this is the live GA-cutover dispatch itself — the fix
  is verified by the dispatch it unblocks; no separate prod-write probe is safe or needed.

## Test Strategy

Follow the existing `apps/web-platform/infra/*.test.sh` convention (plain bash, `pass/fail`
counters, registered in `infra-validation.yml`) — do NOT introduce bats. **Remove the
network from the assertion path** (LLM-free / live-URL-free determinism): refactor the
script's status-read and fan-out-POST behind overridable seams so the test injects a
scripted sequence of JSON `deploy-status` bodies and captures POSTs to a sink file. Two
low-friction seam options (pick at /work, prefer the smaller diff):
(a) honor a `DEPLOY_STATUS_SOURCE_CMD` / `DEPLOY_POST_SINK` env override in `_get_status` /
the POST, unset in prod (real curl) and set in the test; or
(b) a `curl` shim on `PATH` that serves fixtures. The fixtures live under
`apps/web-platform/infra/fixtures/` and are synthesized (no real tokens; `cq-test-fixtures-synthesized-only`).
Run `jq empty` on every hand-authored JSON fixture before wiring it in (the #6030 `forget`
fixture brace-typo lesson).

## Observability

```yaml
liveness_signal:
  what: "web_2_recreate / warm_standby GHA job conclusion (success ⇒ web-2 accepted reason==ok); per-attempt `verify N: … (elapsed=Ns)` + `retrigger K/MAX` annotations in the job log"
  cadence: "on operator dispatch (workflow_dispatch)"
  alert_target: "GitHub Actions run status + job-summary; BetterStack per-host origin absence detector (web-N.app.soleur.ai/health) independently pages if web-2 never binds (model.c4:248/323)"
  configured_in: ".github/workflows/apply-web-platform-infra.yml (job status); apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh (annotations)"
error_reporting:
  destination: "GHA ::error:: annotations (terminal exit 1) + the existing web_2_recreate `Surface fresh-host Sentry emit_fail` step (apply-web-platform-infra.yml:1336) surfacing soleur-host-bootstrap emit_fail (ADR-082)"
  fail_loud: "true — terminal exit 1 on budget exhaustion / unexpected reason / non-2xx trigger; no green-on-timeout"
failure_modes:
  - mode: "web-2 never binds :9000 within the fresh-boot budget"
    detection: "all-degraded → DEGRADED_RETRY_MAX exhausted → terminal exit 1 with OP_CONTEXT recovery message; elapsed= annotation shows the window consumed"
    alert_route: "GHA run RED + job summary + BetterStack per-host absence detector"
  - mode: "fan-out POST rejected (web-1 webhook non-202)"
    detection: "_retrigger_fanout asserts HTTP 202; non-202 → terminal exit 1"
    alert_route: "GHA ::error:: annotation"
  - mode: "web-1 re-swap 521 amplification (secondary finding)"
    detection: "retrigger count bounded by DEGRADED_RETRY_MAX=1 (≤2 swaps); AC3 asserts the POST-count cap; BetterStack apex/origin probe catches a sustained (not transient) 521"
    alert_route: "BetterStack apex heartbeat; tracked separately (see Deferred)"
  - mode: "GHA job-timeout kills the job before the script's terminal ::error:: (pathological 70-min cron-drain on the re-POST swap) — user-impact FINDING 3"
    detection: "AC5c sizes timeout above the realistic budget; the pathological drain case surfaces as a bare GHA 'cancelled' (no recovery msg) → operator idempotent re-dispatch"
    alert_route: "GHA run cancelled state; BetterStack per-host absence detector still pages if web-2 is genuinely unbound"
  - mode: "accept-only false-green — web-2 accepted (reason==ok) but its post-accept canary failed (private-net-only, invisible off-host) — user-impact FINDING 2"
    detection: "NOT detectable by THIS off-host verify by construction (private-net-deny); web-2 is weight-0/drained so serves no live traffic; deferred private-net health probe tracks the GA-cutover gap"
    alert_route: "web-2's OWN ci-deploy Sentry emit_fail (on-host) + the GA-cutover health confirmation step (deferred)"
logs:
  where: "GitHub Actions job log + $GITHUB_STEP_SUMMARY; ci-deploy.sh writes reason/start_ts to web-1 deploy-status (read off-host)"
  retention: "GitHub Actions default (90 days)"
discoverability_test:
  command: "bash apps/web-platform/infra/deploy-status-fanout-verify.test.sh"
  expected_output: "all fixtures PASS (retry→ok exit 0; all-degraded→exit 1; roster/staleness/tag invariants); NO ssh"
```

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-068** (multi-host workspaces / deploy fan-out): add an amendment recording that
the off-host web-2 acceptance verify now **auto-retries the fan-out within a bounded
fresh-boot window** (min-backoff + retry-cap) before failing, operationalizing the
already-stated "idempotent re-dispatch" recovery contract (ADR-068 line 374) for the
`-replace` fresh-boot case, instead of requiring a manual re-dispatch on the first
`ok_peer_fanout_degraded`. This is an **amend**, not a new ADR (no decision is reversed).
`Ref #6051`.

### C4 views
**No C4 impact** — verified by reading all three of `model.c4`, `views.c4`, `spec.c4` (the
completeness read must be re-confirmed at /work): the change refines internal CI verify
control-flow. The external actors/systems/containers the change touches are already modeled
and gain no new element or relationship: **operator dispatch** (existing), **GHCR** (`model.c4:244/322`),
**Hetzner web hosts** (`model.c4:168-170` — web-1/web-2), **BetterStack per-host absence
detector** (`model.c4:248/323`). No new external actor, external system, data store, or
access relationship is introduced (the deploy-webhook fan-out edge CI→web-1→web-2 is an
internal control edge, not a modeled element). A "no C4 impact" conclusion at /work MUST
cite this enumeration after the full three-file read.

### Sequencing
Single atomic PR — the retry edit to the shared script and the warm_standby migration land
together; the ADR amendment ships in the same PR.

## Hypotheses (network/timing)

Root cause is already diagnosed in #6051 and confirmed by code read — this is NOT an
SSH/firewall connectivity outage (no L3→L7 firewall diagnosis applies): `SETTLE_SECONDS=30`
+ terminal-abort-on-first-degraded (`deploy-status-fanout-verify.sh:136-138`) gives up
before web-2's ~10-min fresh boot binds `:9000`. The secondary transient `521` is a web-1
re-swap gracefulness question (below), not a firewall/egress issue. No firewall or egress-IP
verification is required for this fix.

## Downtime & Cutover

**Offline-inducing operation:** the fan-out re-POST re-swaps **web-1** (the sole live
serving origin, `app.soleur.ai`) via `ci-deploy.sh` container `docker stop/rm/run` — a
deploy/router-class change to a serving surface. web-2 is weight-0 / drained / in no serving
pool, so its `-replace` recreate + fan-out delivery is **zero ingress impact**; only web-1's
re-swap touches serving traffic.

**Zero-downtime path (default):** web-1's re-swap is NOT introduced by this plan — it is the
existing `ci-deploy.sh` graceful swap, which already runs the **cron-drain gate**
(`CRON_DRAIN_TIMEOUT`) before `docker stop --time=12`. This plan's only delta is the *number*
of re-swaps, which it **bounds to at most 2** (initial + 1 retry, `DEGRADED_RETRY_MAX=1`) and
gates on `FRESH_BOOT_WINDOW_S` so a re-POST never stacks onto an in-flight swap. Residual
risk: the observed single-probe transient `521` during a swap (secondary finding) — bounded
by the ≤2-swap cap and tracked as a deferred item (truly-graceful swap / web-2-only fan-out
path). No new maintenance window or operator sign-off beyond the existing operator-run
dispatch is required; the change strictly *reduces* churn vs an unbounded retry.

**Cross-pipeline interaction (user-impact FINDING 1, scoped out).** `web_2_recreate` and
`warm_standby` share the `terraform-apply-web-platform-host` concurrency group
(`apply-web-platform-infra.yml:101-115`, `cancel-in-progress: false`) so they cannot race
each other. But the ordinary release pipeline (`web-platform-release.yml` `deploy` job) POSTs
the SAME `/hooks/deploy` webhook under a DIFFERENT group and is NOT serialized against the
recreate group. This PR widens the recreate in-flight window (+ up to `FRESH_BOOT_WINDOW_S` +
one deploy cycle), so a merge-to-main release landing inside that window issues its own
independent web-1 swap — a transient-521 window uncounted by `DEGRADED_RETRY_MAX`. **Scoped
out:** this is a pre-existing hazard of ANY web-1 swap; this PR's marginal contribution is
only the ≤~10-min window-widening, and the recreate is a deliberate operator-run GA-cutover
dispatch (the operator controls whether a release is landing concurrently). A merge-freeze /
label gate during operator-dispatched recreate is noted as a deferred hardening option.

## Domain Review

**Domains relevant:** none (infrastructure / CI-tooling change).

No cross-domain (product/marketing/sales/finance/legal/support) implications — the change is
CI verify-loop control flow over already-provisioned infra. No UI surface (Files-to-Edit are
`.github/workflows/*.yml`, `apps/web-platform/infra/**.sh`, an ADR, a `.test.sh`), so the
mechanical UI-surface override does not fire and the Product/UX Gate is NONE. At the
`single-user incident` threshold, plan-review escalates to include architecture-strategist +
spec-flow-analyzer, and `user-impact-reviewer` runs at review time (per review/SKILL.md).

## Infrastructure (IaC)

No new infrastructure — the change edits an already-provisioned CI workflow + infra shell
scripts and adds NO Terraform resource, secret, vendor, or persistent runtime process. The
workflow *runs* terraform but this PR alters only verify-loop control flow. IaC gate: skip.

## GDPR / Compliance

No regulated-data surface touched (no schema, migration, auth flow, API route, `.sql`, no
LLM processing of operator data, no new distribution surface). GDPR gate: skip.

## Files to Edit

- `apps/web-platform/infra/scripts/deploy-status-fanout-verify.sh` — retry loop, new env
  knobs (`DEGRADED_RETRY_MAX`, `FRESH_BOOT_WINDOW_S`, `OP_CONTEXT`), `_retrigger_fanout`
  seam (reassigns `DEPLOY_TAG`, terminal-exit-1 on non-202), `_recovery_msg` OP_CONTEXT
  selection, `deployed_tag` → `$GITHUB_OUTPUT`, test seams, `elapsed=` annotations.
- `.github/workflows/apply-web-platform-infra.yml` — replace warm_standby's 3 inline polling
  steps (`:808-1026`) with a single shared-script call (`OP_CONTEXT=warm-standby`); rewire
  the summary step's `deployed_tag` source (`:1036`); set the recreate job env
  (`:1078-1084`) `DEGRADED_RETRY_MAX`, `FRESH_BOOT_WINDOW_S`, and a **raised
  `STATUS_POLL_MAX_ATTEMPTS`** (see AC5b budget) scoped to the recreate job ONLY (not the
  script default — protects warm_standby's `timeout-minutes: 30`); keep the recreate
  `timeout-minutes` above the poll budget (see AC5c).
- `.github/workflows/infra-validation.yml` — register the new `.test.sh` (AC12).
- `plugins/soleur/test/terraform-target-parity.test.ts` — add the warm_standby-references-shared-script
  assertion (AC8), if adopted.
- `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md` — amendment (AC11).

## Files to Create

- `apps/web-platform/infra/deploy-status-fanout-verify.test.sh` — network-free unit tests
  (AC1–AC4, AC6).
- `apps/web-platform/infra/fixtures/…` — synthesized `deploy-status` JSON fixtures
  (degraded→ok, all-degraded, stale, bad-tag).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` returned no issue whose body names
`deploy-status-fanout-verify.sh` or the apply-web-platform-infra warm_standby/web_2_recreate
job blocks. (Re-run the two-stage `gh --json … > f.json; jq --arg path …` check at /work
after the final Files list is frozen.)

## Deferred / Out of Scope (with tracking)

- **Secondary finding — web-1 re-swap gracefulness (transient 521).** This PR *bounds* the
  amplification (backoff + cap) but does not make the web-1 re-swap truly zero-downtime, nor
  does it remove web-1 from the recreate verify path (the only off-host trigger is
  `/hooks/deploy` → web-1 → fan-out; a web-2-only path is private-net-deny). Making the
  container swap graceful is a server-side `ci-deploy.sh` change; skipping web-1's re-swap
  needs a new webhook capability. **File a tracking issue** (`domain/engineering`,
  `priority/p3-low`): "Investigate truly-zero-downtime web-1 re-swap OR a web-2-only fan-out
  path so the recreate verify does not re-swap the live origin." Ref #6051 secondary finding,
  run 28747333763.
- **web-2 post-accept health confirmation for GA cutover (user-impact FINDING 2).** The
  off-host verify proves acceptance + `:9000` bind, not web-2's post-accept canary health
  (private-net-only). **File a tracking issue** (`domain/engineering`, `priority/p3-low`): "Add
  a private-net web-2 post-accept health probe (or a GA-cutover step) so `reason==ok` is
  backed by web-2's own canary verdict before live traffic routes." Ref #6051 FINDING 2.
- **Cross-pipeline merge-freeze during operator recreate (user-impact FINDING 1).** Optional
  hardening: a label/merge-freeze gate so an ordinary release cannot swap web-1 during a
  recreate's widened window. Note in the secondary-finding tracking issue; not blocking.
- **7-step setup byte-triplication → composite action** (`apply`/`warm_standby`/`web_2_recreate`).
  Named but not filed in #6040; out of scope here. Address opportunistically.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder, or
  omits the threshold will FAIL `deepen-plan` Phase 4.6. This section is filled.
- Do **NOT** advance `PRE_START_TS` on re-trigger (the first-draft trap the advisor caught):
  advancing it discards a valid late-arriving `ok` from an earlier in-flight cycle (start_ts
  below the advanced baseline → filtered as pre-trigger) and adds CI↔host clock skew. Keep
  the original baseline; track re-POSTed cycles via the `retried` start_ts set, marked ONLY
  when the retry fires (NOT on first sight — the P0 two plan-review agents caught). AC3d-covered.
- The web-platform re-POST is a FULL deploy cycle (canary + cron-drain up to 4200 s + docker
  swap), NOT a same-tag no-op (that ~50 ms shortcut is inngest-only, `ci-deploy.sh:1356`). So
  cap the retry at 1 and gate it on `FRESH_BOOT_WINDOW_S` — never a short cadence.
- `lock_contention` (`exit_code=1, reason=lock_contention`, `ci-deploy.sh:846-849`) is a
  loser-of-`flock` state, NOT a deploy failure — the verify MUST treat it as retryable, else
  any overlap RED-flakes a healthy deploy. AC3c-covered.
- Size the poll budget as `FRESH_BOOT_WINDOW_S + one full deploy cycle` and keep
  `timeout-minutes: 45` above it; the current 900 s poll is tight — re-measure at /work.
- `OP_CONTEXT` default must keep the recreate wording (its first + primary consumer);
  warm_standby explicitly sets `OP_CONTEXT=warm-standby`.
