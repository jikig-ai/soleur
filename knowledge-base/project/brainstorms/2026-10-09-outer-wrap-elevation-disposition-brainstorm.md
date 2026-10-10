# Brainstorm: #9873 elevation arm vs #9773 executor — joint disposition

**Date:** 2026-10-09
**Issues:** #9873 (OPEN at brainstorm time — arm-F elevation blocked: setuid or drop; CLOSED 2026-10-09 per this disposition) · #9773 (OPEN — per-tenant executor topology, tracking issue for epic #9842)
**Branch:** feat-outer-wrap-elevation-disposition · **PR:** #9896 (draft)
**Lane:** cross-domain · **Brand-survival threshold:** single-user incident (USER_BRAND_CRITICAL, auto per #5175)
**Operator prompt:** "Two open issues sit on the same tension; decide them TOGETHER, not independently … The real question: is fixing the elevation arm worth it if #9773 is the end-state? … option 3 + 'accept the blocker' is a legitimate answer; setuid bwrap inside an agent-executed container is a real security cost, not just engineering effort."

## User-Brand Impact

- **Artifact:** the hosted agent-execution container's privilege posture and the sibling-filesystem-presence residual across tenant sessions.
- **Vector:** worst case is a cross-tenant exposure — either through the residual itself (sibling workspace visibility) or through a controller-shipped privilege primitive (a setuid/setcap binary reachable by agent-executed code) being used to unmask the deny-mounts in force today.
- **Threshold:** single-user incident.

## The fork, restated against current facts

#9873 asks which elevation arm makes the dormant mountns-only outer wrap (`AGENT_OUTER_WRAP`, arm F of #5863) work on the no-capability prod container. #9773 tracks the per-tenant executor (ADR-075 Option B) that subsumes the wrap and the shared-heap residual class. Deciding them independently double-counts cost: any elevation arm is interim spend against a funded replacement.

**Current state (verified 2026-10-09):**

- The executor is no longer hypothetical. Operator-approved unified architecture (draft PR #9832, epic #9842, 13 Stage-0 spike IDs / 14 open spike issues, challenge-reviewed spec). Executor = gVisor (`runsc`, systrap) sandbox per session hosting the whole agent (SDK loop + MCP + hooks + CLI); Stage 1 = host supervisor + `RemoteQuery` + credential broker + flag-gated canary tenants. Challenge-review finding C2 **dropped the "arm-F uid envelope" premise** — the executor does not ride the in-container outer wrap.
- The wrap never ran enabled in prod (v0.333.1 rolled back on the file-cap arm; #9874 reverted). Flag-off is the status quo, not a regression. Sibling workspace **content** remains masked today by #5862 deny-then-restore + the realpath hook; what stays open is sibling *existence* / mount-table presence / defense-in-depth — a bounded, documented residual.
- Cohort exposure is currently zero: the only external user is on the self-hosted CLI plugin, not the shared web container; arms-length tenants are gated by the **superset** residuals (shared heap, procfs, net, IPC, credentials) the wrap does not close.

## Option analysis (decided together, not independently)

### Option 1a — setuid bwrap copy (`/usr/local/libexec/bwrap-outer`)

**Rejected — dead mechanism, not merely a cost.**

- Upstream: setuid works only ≤0.11.1; deprecated (requires `-Dsupport_setuid=true`) at 0.11.2 (CVE-2026-41163); **removed entirely at 0.12.0** (PR #742). Prod pins 0.8.0 (bookworm) — the one pin where it still runs; dev host runs 0.12 where it **cannot even be tested**. Any bwrap upgrade kills the arm. The `setuid`-worded close-out in #9873 and the archived #9871 plan's O3 ("dead end on any bwrap upgrade") are both true at different version pins — this resolves the tension: it is the only upstream-supported form *and* a dead end.
- Container shape: creating a mountns without userns requires `CAP_SYS_ADMIN` **in the container bounding set** — `--cap-add SYS_ADMIN` at all three `docker run` sites. That grant (a) flips `seccomp-bwrap.json` onto its permissive CAP_SYS_ADMIN rule for *every* process, and (b) weaponizes every setuid binary already in the image (`su`, `mount`, `newgrp` on node:22-slim). The "dedicated elevated copy" narrows nothing at the bounding-set layer.
- Self-defeating: an agent-reachable setuid bwrap is the very primitive needed to re-mount over the deny mounts in force today (CLO). It degrades the existing isolation to install the new one.
- Audit gap: `getcap -r /` does not see setuid mode bits — a new `find -perm -4000` audit would be needed.
- Process cost: ~3–5 days + threat-model review + a mandatory dark-launch deploy before it can protect anyone (`wg-dark-launch-deploy-gates`) + a removal image cycle (flag-invariant binary; the same ghcr→deploy lag that caused the #9871 incident).

### Option 1b — bespoke minimal setuid launcher (mount+bind+drop-uid+exec, fixed argv)

**Deferred, not built — parked behind a revisit trigger.**

Closes the argv-flexibility hole of 1a and dodges upstream's setuid deprecation, but still needs the same `CAP_SYS_ADMIN` bounding grant (the systemic widening above is unchanged) and still gives the container a standing privileged component. ~1.5–2 weeks + audit + dark-launch + removal, to close *only* sibling-FS-presence while the heap/proc/net residuals stay open either way. Its design partially informs the executor's host-side fallback rung (different trust boundary — design learning only). **Revisit trigger:** executor Stage-1 GA slips materially (~8 weeks) OR a realized sibling-filesystem incident lands — then build 1b, never 1a.

### Option 2 — patch/fork bwrap

**Rejected** — a forked security-critical sandbox binary for a transitional arm, carrying a per-bump attestation burden with no cohort payoff.

### Option 3 — drop the privileged arm; `AGENT_OUTER_WRAP` stays flag-off until #9773 Stage 1

**Recommended — unanimous (CTO / CLO / CPO + prior-art review).**

- The interim residual is already the status quo and already documented; accepting it adds zero new posture. The executor closes the *superset* (FS + heap + procfs + net + IPC + credentials), so the residual's exit criterion is #9773 Stage 1 — the same event either way; the fork only changes whether we ship a privileged binary in the interim.
- Closing FS-presence alone unblocks nothing user-facing: arms-length onboarding is gated by the superset residuals regardless (CPO, confirmed against roadmap cohort state).
- Compliance posture is strictly better as named-gap (CLO): counsel-review-9601 established "a TOM entry that names its own gaps is the compliant form"; an honest TOM bullet for option 1 would have to read "a root-capable binary is invocable by tenant-controlled code," making the Schedule strictly worse to audit. If a realized cross-tenant read ever occurred *through* a controller-shipped setuid binary, the Art. 33(5) write-up is materially worse than "a documented passive gap was probed."
- Cost: ~0. Keep `agent-outer-wrap.ts` inert (771 lines, tested, flag-gated) — the argv builder + probe are design reference for the host launcher; deletion is churn.
- What is foregone: sibling FS *existence*/mount-table visibility stays open until Stage 1 (content already masked). Bounded, honest, reversible.

## Decision

**#9873 → Option 3.** Drop the privileged elevation arm. `AGENT_OUTER_WRAP` remains flag-off on the shared prod container; the implicit-userns fallback continues to serve hosts that permit it. **#9773 → unchanged** — proceed executor-first; no interim arm competes with the Stage-0/Stage-1 work. Revisit trigger recorded above for option 1b.

## Record-keeping actions (the "implementation" of this decision)

| # | Action | Owner lane | Why |
|---|--------|-----------|-----|
| R1 | Close #9873 with the decision comment (upstream ground, rejected options + reasons, residual stays open, exit criterion = #9773 Stage 1, revisit trigger) | engineering | Issue disposition |
| R2 | ADR-075 addendum — it still documents file-cap arm F as the design on main; record the #9874 revert + this disposition; Option B's exit is now #9773 only | engineering | CTO + learnings-researcher both flagged the stale record |
| R3 | Rewrite the arm-F bullet in `article-30-register.md` **on `feat-tenant-executor-topology`** before PR #9832 merges — the drafted bullet asserts file-cap mechanism + `status: adopting`, already false | legal (via #9832 comment/note) | TOM-4 accuracy defect in a pending PR |
| R4 | `compliance-posture.md` dated comment — elevation dead, wrap flag-off, residual open, exit = #9773 Stage 1 (append-only convention) | legal | Record hygiene |
| R5 | CLO ruling doc in `knowledge-base/legal/audits/` — controller decision closing an arm; cited by the Stage-0 Art. 33(5) assessment + DPIA memo | legal | Decision record |
| R6 | Check #9798 (flag+deny deletion issue) still tracks honestly under flag-off-forever; update if its premise assumed an enabled flag | engineering | Housekeeping |
| R7 | No-claim discipline — nothing may describe sibling-FS isolation as shipped (#9603 rule); Schedule-4 interim wording already names "mountns+uid-less" per executor Decision 9 | all | Live-claim drift |

## Evidence

- Leaders: CPO (residual ordering + zero cohort exposure + DPA review comparison), CLO (named-gap TOM form, self-defeating primitive, Art. 33(5) asymmetry, record list), CTO (mechanism dead-end, bounding-set widening, cost table, revisit trigger) — unanimous Option 3.
- Mechanism facts: `agent-outer-wrap.ts` (argv contract, `elevation=privileged|userns` probe, DI seam); seccomp rule-15 permissive shape under CAP_SYS_ADMIN; `getcap` audit blind to setuid; inner sandbox starvation mechanics (userns ownership of pid/net).
- Prior art: the archived #9871 plan's Option O3 (setuid works ≤0.11.1 only, removed at 0.12 — the plan sits on unmerged branch `feat-one-shot-9860-deploy-canary-health-failed`, `knowledge-base/project/plans/archive/20261009-195834-…`; its substance is upstream-verified); ADR-075 addendum; executor spec TR5 host-side launcher; counsel-review-9601 named-gap form; dark-launch rule (#4932→#4941); measurement-gap lesson (arm F never ran as uid 1001 in the prod image before merge).
