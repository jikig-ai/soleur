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
| Item 3 — blank-prd DR: write the procedure (reviewed one-time allowlist-patch recipe) vs. explicit written decline | technical | pending - assumed: write the procedure (the runbook + ADR-142 2026-10-12 addendum both record it as owed; a decline still has to name the same per-incident route to be honest). Flag for parent ruling |
| Item 3 mechanism detail — widen the `rehearsal_*` case arm to admit `prd` for one reviewed window vs. rendering a one-time `rehearsal_dr_*` scratch config seeded from prd | technical | pending - assumed: admit `prd` for the window (one-line patch, host already reads the real prd secrets; no scratch-config seeding surface). Flag for parent ruling |
| Item 4 — share the resolver decision via a `/usr/local/lib/` write_files helper vs. accept the drift in writing | technical | pending - assumed: accept in writing (loopback suite executes both copies verbatim; D5 pinned-duplication precedent; decision frozen post-cutover). Flag for parent ruling |
| Item 4 fallback — if the ruling is "share", the diff grows into `cloud-init-inngest.yml` + two suite extraction points | technical | pending - assumed: n/a unless ruled; re-run the #10243 file-overlap check before editing that file |
| Lane — no spec.md exists for this branch | operator (scope) | RESOLVED by rule: `lane:` defaulted to `cross-domain` (TR2 fail-closed) per plan Save Tasks; noted in the plan body |

## Not Yet Specified Candidates

None. No in-scope product fog; every unknown is an implementation detail covered
by an AC or a flagged ruling row above.
