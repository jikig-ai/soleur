# Decision challenges — feat-one-shot-6929-registry-luks-recut-dispatch

Recorded headless by `plan-review` (7-agent panel: dhh, kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, cpo, cto-devex) on 2026-07-24. `ship` Phase 6 renders these into the PR body and files an `action-required` issue. Mechanical findings were auto-applied to the plan; the items below are **Taste** or **User-Challenge** and were NOT silently applied.

---

## DC-1 (Taste, split panel) — the two added prod-safety gates: keep or cut?

**The split.** The simplification panel says cut; the product/structure panel says they are non-deferrable.

- **DHH (cut D11, de-fang D10):** `registry_host_replace` already carries a *recorded* decision against gating on this heartbeat — step **"Best-effort heartbeat status (non-gating)"**: `INFORMATIONAL only — MUST NOT gate the apply (Better Stack ingestion lags a fresh boot ping)`. And a red job changes no prod outcome: the store is already destroyed. Also: D10's cited precedent is a human-read issue body, not a gate, and its "sustained hits" was never a number.
- **code-simplicity (cut D10, keep D11):** no sibling has a pre-destroy health gate; fail-closed means a Better Stack outage blocks the only vehicle that closes an encryption exception.
- **CPO (both non-deferrable):** without D10 this job can *create* the #6400 total-deploy-outage; without D11 a destroy path can report green over a dark registry, which is a false negative on the only fact the operator needs.
- **architecture-strategist:** did not contest either; added that D11's failure diagnostic must also name `device-absent`.

**Applied (a middle path, not a silent pick):** both kept, but rebuilt so the objections are answered rather than overridden — D10 gets a concrete zero-tolerance threshold plus a Phase 0 positive-control proof (if the signal cannot be shown to ever go red, it ships as a `::warning::`, not a gate); D11 is rebuilt as a tested script that waits out the dead host's residual `up` window, requires a transition, and handles `paused`, citing the `arm_one` step in the *same* workflow as the precedent that heartbeat gating is legitimate when done correctly.

**Operator decision requested:** accept the middle path, or cut D10/D11 to non-gating and accept a thinner vehicle.

---

## DC-2 (User-Challenge) — this PR adds `prevent_destroy` to a resource #6929 never mentioned

`architecture-strategist` P1-6: `hcloud_volume.workspaces` (the sole copy of `/mnt/data`) has **no** declarative destroy protection anywhere in the root, and after this PR a sixth hand-maintained jq `out_of_scope` invariant is the only barrier between it and a lockless shared state. It verified no existing dispatch path plans a destroy of that resource, so adding `lifecycle { prevent_destroy = true }` is compatible today.

This **changes the operator's stated scope** — #6929 asked for a dispatch, and this flips §Infrastructure from "Terraform changes: **None**" to a real `.tf` edit. It was applied because it is provider-enforced at *plan* time and defends against all six existing gates plus every future one, which no jq counter can. **Surfaced rather than assumed: say the word and it comes out.**

---

## DC-3 (Taste) — the weaker sibling makes the new gate's strictness locally sound but globally partial

`architecture-strategist` P1-7: `registry_region_migrate_gate` already accepts the same bare-create shape with **no** confirm token, **no** id-pin and **no** opt-in. An operator whose `registry-luks-recut` dispatch ABORTs can fire `registry-region-migrate` and get the same creates through unguarded.

**Applied:** recorded as an accepted residual in the ADR-096 amendment + a tracking issue. **Not** applied: mirroring the id-pin onto `registry_region_migrate`, which would change a second shipped dispatch's contract inside this PR.

**Operator decision requested:** accept the residual, or widen this PR to harden the sibling too.

---

## DC-4 (Taste, split) — folding #6926's unswept doc debt into this PR

`code-simplicity` says cut (it fixes #6926's defect, not #6929, and drags in three extra test suites for two prose lines). `dhh` and `cpo` say keep (shipping the LUKS vehicle while `model.c4` still reads `AT REST: PLAINTEXT ext4` is exactly the drift the posture apparatus exists to catch). **Kept.** CPO named it "the only defensible defer" if the PR becomes unwieldy — with a tracking issue, never silently.

---

## DC-5 (User-Challenge) — is a recut actually being scheduled?

`cpo` R3/R4 + #6929's own re-evaluation criteria ("add it when the first live recut is scheduled, OR sooner if another volume-preserving dispatch increases the footgun surface"). Neither trigger is asserted anywhere, and AC22 leaves the recut unscheduled. So this spends a medium (days) budget on a Phase-4 milestone with recruitment-shaped exit criteria, to build a vehicle for a trip with no date — and ships it **cold**, with zero live executions, deferring all validation to the highest-stakes possible moment.

**Question for the operator: is a registry LUKS recut being scheduled?** If yes, name the window and the cold-vehicle risk dissolves. If no, the honest options are (a) ship it cold and record a re-verification trigger before first fire, or (b) pause this until the recut is on the calendar. The plan currently assumes (a).

---

## DC-6 (Taste) — the empty-store window is a paging window, and nobody controls the clock

`spec-flow` P1-6: after a successful recut, `registry_pull_event registry=ghcr-fallback` is emitted at `level: "warning"` and is wired to the `zot_mirror_fallback_rate` Sentry alert — described in `issue-alerts.tf` as "the only no-SSH page gating the IRREVERSIBLE ADR-096 5.5 PAT" decision. The window lasts "until the next CI dual-push", an event the operator does not control.

**Applied:** the plan now states the paging consequence and the runbook gives the one-command force (`gh workflow run web-platform-release.yml -f bump_type=patch`) plus the recommendation to fire the recut immediately before a planned release. **Not applied:** automating a `crane copy` backfill into the job — `registry-region-migrate` ships this same window as its accepted posture, and its gate header already documents the mechanism correctly.
