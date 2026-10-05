# Decision challenges — feat-one-shot-8651-web-host-zot-primary-boot

## DC-1 (User-Challenge, plan-review) — keep or cut the pre-pull private-NIC wait

- **Operator's stated direction (default, kept):** advance #6438 (web-host NIC-convergence generalization) within this change.
- **Challenge (DHH reviewer):** cut the inline NIC wait — the NIC race did not cause #8651 (measured: tokenless Doppler read), the inngest host measured `waited_s=0`, and a ~150 s retry budget on the zot login/pull would surface a never-converged NIC as `zot=[login=fail]`.
- **Counter (code-simplicity reviewer, CTO):** keep it; it cannot be baked, the routed alert (`web_private_nic_boot_gate`) already exists, and without it an unconverged NIC reads as a zot failure.
- **What the plan did:** kept the wait (operator scope), trimmed it: no emit on the ready path (`nic_w` rides the `app_zot`/fatal detail), one routed warning on timeout/probe-fault only.
- **Decide:** keep as planned, or cut to "retry budget only" and leave #6438 §3 fresh-boot half open.

## DC-2 (Taste, advisor consult) — close criterion wording for #8651

- **Operator's stated proof (kept):** a replace whose boot trail shows a zot-served pull with GHCR failing and non-fatal.
- **Challenge:** close on `app_zot` observed alone; keeping a GHCR leg that can only fail bakes a dead path into the proof.
- **What the plan did:** kept the operator's wording; `app_zot`'s detail carries `ghcr_login=fail`, so both are shown by one event at no extra cost. The GHCR leg's retirement stays with #8036 1d / ADR-096 5.3.

## DC-3 (review, recorded not fixed) — the zot soak no longer sees a GHCR-dead web zot miss

- **Finding:** `zot-soak-6122.sh`'s `FAIL_QUERIES` counts `app_ghcr_fallback` and `app_ghcr_served`, not the `stage=pull` fatal. The GHCR leg now runs only after a successful GHCR login. While AP-016 holds, a fresh web boot whose zot pull misses therefore emits only the `stage=pull` fatal, which the soak does not count. Before this change, the same miss emitted `app_ghcr_fallback` first.
- **Why not fixed here:** the operator's constraint forbids weakening the soak's blocker arm. Widening `FAIL_QUERIES` changes the soak's gate for ADR-096 5.3, which is a separate decision. While issue 8651 is open, the soak's `WEB_BLOCKER` arm holds the gate regardless.
- **Decide:** add `stage:"pull"` scoped to web hosts to `FAIL_QUERIES` (a separate PR, re-baselining the soak), or accept that the `web_private_nic_boot_gate` and terminal-boot-fatal alerts, not the soak, own a dark fresh web boot.

## DC-4 (review, CTO stage name overridden) — reload failure reuses `private_nic_probe_fault`

- **CTO proposal:** a new stage `private_nic_reload_failed`, matching inngest.
- **What shipped:** the existing `private_nic_probe_fault`, with detail `gate=reload`. A new web stage needs a Sentry alert-rule edit plus an apply to be routed. Without that, it would be emitted into a bucket nobody reads (see the `web_private_nic_boot_gate` comment). With the reused stage, the merge changes no alert.
- **Decide:** keep, or add the new stage together with an alert-rule change and its apply.
