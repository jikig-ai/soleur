---
branch: feat-one-shot-10112-inngest-residuals
created: 2026-11-06
---

# Decision Challenges — feat-one-shot-10112-inngest-residuals

Recorded per ADR-084 / technical-ruling-delegation. On this harness (Devin CLI,
subagents cannot nest) `soleur:engineering:cto` cannot be spawned, so technical
forks are written `pending - assumed: <default>` and flagged for the parent to rule.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Item 2 provenance — the issue records the rehearsal-volume removal as filed under an operator scope-exclusion ("first candidate to pull forward if the operator lifts the exclusion") | operator (scope) | RESOLVED — the resume brief for this run explicitly lists the unused rehearsal volume in scope; that is the lift, recorded here as the provenance the brief required |
| Item 3 — blank-prd DR: write the procedure (reviewed one-time allowlist-patch recipe) vs. explicit written decline | technical | Ruled by CTO agent, 2026-11-06: write the procedure — the refusal arm is verified (`cloud-init-inngest.yml` `STAGE=unpointed_raw_refused`, `case rehearsal_*`), `inngest_doppler_config = "prd"` is a rendered literal, so a blank prd volume has no bring-up path today; writing is the stricter arm because it turns an under-pressure improvisation into a reviewed, reverting sequence, and the issue's AC3 accepts either arm. Dissent: none — caveat: procedure verified statically, not drilled; runbook section must say so and carry the closing clause: no standing flag, var, or apply target |
| Item 3 mechanism detail — widen the `rehearsal_*` case arm to admit `prd` for one reviewed window vs. rendering a one-time `rehearsal_dr_*` scratch config seeded from prd | technical | Ruled by CTO agent, 2026-11-06: widen `rehearsal_*` to admit `prd` for one reviewed window, with pin updates and revert in the same reviewed-diff pair — the refusal is one case-glob line, the host still reads real prd secrets through unchanged `inngest_doppler_config`, and the scratch config would add a secret-seeding surface plus a *standing* config that satisfies the `rehearsal_*` format glob. Dissent: the widen arm opens the format-on-prd hole for the window's duration — unavoidable; the bound is the two reviewed PRs (widen, revert) plus suite pins that fail closed on incomplete revert |
| Item 4 — share the resolver decision via a `/usr/local/lib/` write_files helper vs. accept the drift in writing | technical | Ruled by CTO agent, 2026-11-06: accept the duplication in writing — record the deliberate asymmetries (reopen never formats, pre-network logger vs `$INNGEST_LUKS_DETAIL` tee, non-numeric pointer arm) and the loopback suite as the drift bound in the runbook + ADR-142 addendum; the resolver decision is frozen post-cutover, D5 set the pinned-duplication precedent, and a shared helper buys no property the suite doesn't already enforce. Dissent: code-simplicity position stands as recorded cost — two copies can still drift textually between suite runs, bounded (each executed verbatim per run) but not structurally prevented |
| Item 4 fallback — if the ruling is "share", the diff grows into `cloud-init-inngest.yml` + two suite extraction points | technical | Ruled by CTO agent, 2026-11-06: adequate and moot — Item 4 ruled "accept", so `cloud-init-inngest.yml` stays untouched and the #10243 overlap check never re-runs; the share-path checklist is correctly scoped should a later change revisit the fork. Dissent: none — caveat: if a future change flips to "share", the overlap check must be re-run then, not inherited from this plan's dated result |
| Lane — no spec.md exists for this branch | operator (scope) | RESOLVED by rule: `lane:` defaulted to `cross-domain` (TR2 fail-closed) per plan Save Tasks; noted in the plan body |

## Not Yet Specified Candidates

None. No in-scope product fog; every unknown is an implementation detail covered
by an AC or a flagged ruling row above.
