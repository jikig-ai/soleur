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

## UC-2 — The volume-recut target is designed here, not built here

**Operator direction (default):** "Design a volume-wipe / inngest-luks-recut apply_target for
/mnt/data … it must ship GATED (required-reviewer environment with a non-empty reviewer set, typed
confirm) and never auto-executed."

**What the plan does:** delivers the complete design — five guard layers (including one the
`workspaces-luks-recut` template lacks), the naming correction, and the destroy-guard contract — and
defers the *build* to the PR that opens the cutover window.

**Why:**

1. H5/H6 are recorded UNKNOWN: nobody has established that a FLUSHALL ever happened on this volume.
   Building the most destructive target in the inngest surface to clear a latch whose existence is
   undetermined inverts the evidence ordering the rest of the plan insists on.
2. It would ship inert — its only consumer is the cutover window, which this PR defers.
3. Its guards can only be exercised against synthesized fixtures until a real dispatch happens, so
   building it alongside the live plan output is the first point at which it is gradeable.

**What the operator gives up:** the target is not available if a recut becomes urgent before the
cutover window. Mitigation: the design is complete, so building it is mechanical rather than a
fresh design cycle.

**Decision needed:** accept design-now/build-at-cutover, or direct that the build land in this PR.

## UC-3 — None of the three asks is delivered in full, and the plan says so

Ask 1 (make the host serve) is **diagnosed, not fixed** — a durable serving ExecStart is reachable
only inside a cutover, and `op=arm` is forbidden this session. Ask 2 is **mitigated, not met** — the
`clear` verdict remains weak and the on-host latch remains the authority. Ask 3 is **designed, not
built** (UC-2).

This is surfaced rather than smoothed over because the issue's step-4 exit criterion
(`server_active=active` + `http_code=200` on a **durable** ExecStart) is not merely hard here — it is
structurally unreachable without arming. A plan that claimed to satisfy it would be claiming a state
this session is forbidden from producing.

**Decision needed:** confirm the split (4a now, 4b at the cutover window), or re-scope.

---

## Resolutions (operator, 2026-08-25)

All three challenges were put to the operator with the trade-offs above, and all three were
resolved in favour of the plan's recommendation. They are decided, not outstanding.

- **UC-1 — ACCEPTED (substitution).** The flush-latch readback ships over ADR-100's already-adopted
  Vector → Better Stack journald transport, giving G3.7 a second signal and a fail-closed `silent`
  outcome. The webhook id is **not** built. ADR-100 Decision 6a stands unamended; no new inbound
  control plane on the deny-all-public singleton, and no host replace. Accepted cost: no on-demand
  read of the latch file's verbatim contents.
- **UC-2 — ACCEPTED (design now, build at the cutover window).** The `inngest-volume-recut` design
  ships complete — five guard layers including the "host is dark" pre-flight refusal absent from the
  `workspaces-luks-recut` template — and the build defers to the PR that opens the cutover window.
  Accepted cost: the target is unavailable if a recut becomes urgent first; mitigated because the
  design is complete, so building it is mechanical.
- **UC-3 — CONFIRMED (4a now, 4b at the cutover window).** The step-4 exit criterion is
  acknowledged structurally unreachable this session and is NOT claimed. After this PR merges the
  next act is a re-measurement and a cutover-readiness assessment brought back to the operator —
  not an arm. `op=arm` remains forbidden for this session.
