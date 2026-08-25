# Decision Challenges — feat-one-shot-7674-inngest-host-not-serving

Recorded per ADR-084. These are challenges to the operator's *stated direction*. They are surfaced,
not silently applied.

## UC-1 — The webhook id for the flush-latch readback was not built

**Operator direction (default):** "Expose `cat-inngest-cutover-state.sh` behind a webhook id and have
gate G3.7 consult it as the AUTHORITATIVE flush-latch signal, keeping Better Stack secondary."

**What the plan does instead:** delivers the same *intent* — an authoritative, no-SSH flush-latch
verdict that can tell "no flush" apart from "cannot tell" — through the transport ADR-100 already
adopted (the on-host Vector → Better Stack journald channel), by giving G3.7 a second signal and a
new fail-closed `silent` outcome.

**Why the stated mechanism was not followed:**

1. ADR-100's alternatives list rejects it by name: "**A dedicated-host webhook reached via web-host
   fan-out.** Rejected: a new inbound control plane on the deny-all-public singleton enlarges its
   attack surface (SEC-H2)." Decision 6a states the host runs no `adnanh/webhook` / `hooks.json`.
2. Delivery is replace-only. `cat-inngest-cutover-state.sh` and every other on-host asset ship in the
   OCI image, pulled by a digest literal inside `cloud-init-inngest.yml` `user_data` — ForceNew, no
   `ignore_changes`. Editing that file is forbidden by the ask itself, because it force-replaces the
   fleet's sole scheduler.
3. The ask's own escape hatch was exercised: "If this grows past a mechanical wiring, route the design
   call to the soleur:engineering:cto agent." It was routed, and the CTO review corrected a research
   error in the process (`deploy-inngest-image.yml` reaches the web host, not the dedicated host).

**What the operator gives up:** a point-in-time pull of the latch file's exact contents on demand.
The substitute is a periodic push of the same host's liveness plus the existing latch-evidence query,
which cannot read the latch record verbatim.

**What the operator gains:** no new inbound control plane on the deny-all-public singleton, no host
replace, and no edit to the forbidden file.

**Decision needed:** accept the substitution, or direct that the webhook be built anyway — which
would require reopening ADR-100 Decision 6a and accepting a host replace to deliver the code.
