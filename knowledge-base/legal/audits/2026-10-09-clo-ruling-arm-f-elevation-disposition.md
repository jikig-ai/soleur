# CLO Ruling — arm-F elevation disposition (#9873 → Option 3, #9773 unchanged)

**Date:** 2026-10-09 · **Authority:** internal v1 CLO sign-off scope (draft
material; no external-counsel trigger — no arms-length user, no EEA-out, no
regulated counterparty) · **Recorded per:** breach-register convention treating
controller decision-closure as a recordable disposition; cited from the #9873
close-out comment; input to the Stage-0 Art. 33(5) assessment (#9723 window)
and the DPIA re-screen memo in epic #9842.

## Question

Whether to ship a privileged elevation arm for the dormant mountns-only outer
wrap (`AGENT_OUTER_WRAP`) — a setuid bwrap copy, a bespoke setuid launcher, or a
patched bwrap — or to accept the documented sibling-filesystem residual until
the per-tenant executor (#9773 / epic #9842) lands.

## Ruling

**Option 3 — drop the privileged arm.** The honest posture is "accept + name,"
not "add a privileged component."

1. **Named gap beats new mechanism.** Counsel-review-9601 established that a
   TOM entry naming its own gaps is the compliant form. The interim residual
   (sibling filesystem *existence*/mount-table presence; content masked by the
   #5862 deny) is documented, bounded, and passive. Closing it buys zero
   compliance progress: arms-length cohort expansion is gated by the superset
   residuals (shared heap, procfs, net, IPC, credentials) the wrap never
   addressed.
2. **The arm is a new documentable residual, and it is worse than the gap.**
   A standing root-capable binary execve-able by the app uid inside the shared
   container is reachable by every agent session including a prompt-injected
   one (threat class A1 in the executor threat model) — and is itself the
   primitive needed to unmask the `denyRead` tmpfs deny in force today.
   Direction-neutral accuracy (TOM-4 ruling: no safe harbour for mis-description
   in either direction) would force the honest TOM sentence "a root-capable
   binary is invocable by tenant-controlled code" into the same register as the
   gap it closes — strictly worse to audit.
3. **No Art. 33 consequence either way.** No Art. 4(12) event occurred; #9871
   was a deploy-availability incident touching no personal-data limb. The #9723
   /proc-window Art. 33(5) assessment is owed regardless (epic #9842 Stage 0);
   its recorded exit event should be the executor landing, not the wrap.
   Forward-looking asymmetry for the record: a realized cross-tenant read
   through a controller-shipped setuid primitive would read materially worse in
   a 33(5) write-up than "a documented passive gap was probed."
4. **DPIA:** §9 limb (d) (small user base / arms-length onboarding) unchanged
   by this fork; re-screen keys to onboarding, not to this mechanism choice.

## Conditions recorded

- The residual must remain *named*, not merely unclaimed: Art. 32 TOM bullet
  (see `article-30-register.md` on `feat-tenant-executor-topology` — its
  drafted arm-F bullet asserting a file-cap mechanism at `status: adopting`
  was already false when drafted and must be rewritten before PR #9832 merges
  to the flag-off form: "built but not in force, not relied upon").
- Schedule-4 interim wording per executor Decision 9 stands: name the shipped
  mechanism ("interim: mountns+uid-less; target: gVisor"); flag-off code is
  not a TOM and must not be claimed as in-force.
- Revisit trigger (engineering, recorded in ADR-075 addendum): Stage-1 slip
  ~8 weeks or a realized sibling-FS incident re-opens the bespoke launcher arm.
