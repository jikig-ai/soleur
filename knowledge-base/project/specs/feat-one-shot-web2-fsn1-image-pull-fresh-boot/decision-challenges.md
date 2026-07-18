# Decision Challenges — feat-one-shot-web2-fsn1-image-pull-fresh-boot

## DC-1: Defer Phase 2 (Vector "ships logs" on web-2) to a follow-up

**Class:** user-legible scope decision (headless one-shot; ADR-084 taxonomy).

**Operator's stated direction (default):** the success criterion in the resume prompt / plan was "web-2 boots, serves, **and ships logs**." The plan's Phase 2 installs Vector on web-2 so its journald ships to Better Stack.

**Challenge (what I did instead):** shipped only Phase 1 §1A (the GHCR `auth_denied` credential-fallback fix — the confirmed root cause of web-2 not serving) in this PR, and **deferred Phase 2 (Vector on web-2) to a tracked follow-up issue.**

**Why (engineering rationale, not mere trimming):**
1. **Verification attribution.** Phase 3 verifies §1A restored the boot via a real `web-2-recreate` fresh boot. Phase 2 adds a NEW fail-open Vector runcmd to *that same boot* — bundling it means a green/red Phase-3 boot can't be attributed to §1A alone. Sequencing §1A → verify → Vector is the cleaner, lower-risk order.
2. **Risk isolation.** "Ships logs" is observability-additive; it is NOT the serving blocker. The serving blocker (auth_denied) is fully fixed by §1A. Keeping the credential fix a tight, focused PR reduces review/regression surface on the failover-restoring change.
3. **No urgency cost.** web-2 is LB weight-0 (zero prod traffic), so there is no user-facing cost to sequencing the observability add after the serving fix.
4. **Consistency.** The plan already treats web-1 Vector as a follow-up; web-2 Vector as a sibling follow-up is consistent, and both can land together in a focused observability PR.

**How the operator's direction is preserved (not dropped):** a follow-up issue is filed for "Vector on web-2 (ships logs) + web-1", the C4 `web-2 → Better Stack` edge moves to that PR, and this decision is surfaced in the PR body. The operator can pull it forward at any time.

**Reversal trigger:** if the operator wants "ships logs" in the same change, re-scope Phase 2 into this branch (fail-open, after `:9000` bind, bodies baked into `soleur-host-bootstrap.sh` per the 32 KB cap).

## DC-2: Terminal serving-block observability gap → same web-2-boot-observability follow-up

**Class:** pre-existing P2 observability gap (surfaced by architecture-strategist at review).

**Finding:** the cloud-init **terminal serving block** (`apps/web-platform/infra/cloud-init.yml` ~L720-767) has NO named `soleur-boot-emit` fatal trap — unlike the inngest block's composite trap (`… || soleur-boot-emit inngest_bootstrap fatal`). So a `doppler secrets download` failure (`exit 1`) or a `docker run` failure (`set -e` abort) in that block exits only to `cloud-init-output.log`, reachable only via SSH / Hetzner rescue console (tension with `hr-no-ssh-fallback-in-runbooks`, `cq-silent-fallback-must-mirror-to-sentry`). This is exactly the blind spot that made *this* incident's boot-path attribution costly.

**Disposition:** PRE-EXISTING (not introduced by §1A) and adjacent. Fold into the same web-2-boot-observability follow-up as DC-1 (Vector "ships logs") — both are fail-open boot-observability additions best verified on a fresh recreate AFTER §1A is confirmed, so bundling them keeps Phase 3's §1A attribution clean (same rationale as DC-1). One-line fix each: mirror the inngest composite-trap onto the terminal block; add `host_id` to `ci-deploy.sh`'s `pull_failure_event` payload (per the learning's observability nit).

**Follow-up issue (filed at ship) should cover:** (a) Vector on web-2 (+ web-1) → journald ships to Better Stack; (b) named `soleur-boot-emit` fatal trap on the cloud-init terminal serving block; (c) `host_id` tag on `pull_failure_event`; (d) C4 `web-2 → Better Stack` edge.
