# Decision challenges — feat-one-shot-zot-migration-completion

Headless plan run, 2026-09-23. These are points where the plan departs from, or adds to, the
brief's stated direction. Each one is recorded here instead of being applied silently.

## DC1 — task 1.8 is marked partial `[~]`, not ticked `[x]` (User-Challenge)

- **Stated direction:** "tick 1.8, 1.9, 2.4 with evidence pointers".
- **Plan does:** ticks 1.9 and 2.4. Marks 1.8 `[~]`, the file's existing partial marker (see 1.5), with an evidence note. The note records that the host is deployed and serving (first zot-served pull 2026-07-17T19:51:49Z; 392 pulls). It also names the item's two checks that have no recorded run:
  - the pre-flip scoped-token isolation assertion (isolation-fix plan AC11; the admitted set is now 4 secrets)
  - "heartbeat green": `betteruptime_heartbeat.registry_prd` is still declared `paused = true` in `apps/web-platform/infra/zot-registry.tf`
- **Why:** ticking a gate that never ran writes a false record. The scoped advisor consult and the session model agree. The plan-review simplicity pass chose a single `[~]` line over an 1.8a/1.8b split, because nothing references the sub-items.
- **Default if nobody objects:** `[~]` stands.

> **Superseded 2026-09-24 (work phase): 1.8 is ticked `[x]`.** Both "not run" premises were re-measured and are false:
>
> - **Heartbeat.** Better Stack `soleur-registry-prd` reads `status=up paused=false`. The `paused = true` in `zot-registry.tf` is source-only by design (`ignore_changes = [paused]`). Its own comment says live state has been armed since 2026-07-16 (ADR-117).
> - **Isolation.** `soleur-registry`/`prd` holds exactly the 4 non-`DOPPLER_*` names the boot self-check admits. The "EXACTLY 2" wording predates #6244 and #6895.
>
> The brief's direction ("tick 1.8") therefore stands. The 1.8 note says the isolation check was measured by listing the config's secret names, not by minting a scoped token.

## DC2 — the bottom-line sentence carries a per-option build cost

- **Stated direction:** "state plainly: the gap between today and 'migration complete' is not engineering; it is one authorization act on #6122".
- **Plan does:** keeps that sentence word for word. Right after it, the plan lists what each ADR-169 option costs before 5.3b, in neutral order:
  - **A:** several PRs, plus about €19.49/month.
  - **B1:** one slice.
  - **B2:** no new infrastructure, but ADR-169's independence criterion has to be weakened.
  - **B3:** no new build.
- **Why:** without the list, the #6122 comment implies that every option is mechanical afterwards, which tilts the A/B write-up. Raised by the scoped advisor consult. Kieran's plan review later caught that B2 was missing.

## DC3 — #7077 and #6073 are closed directly, not by PR-body keyword

- **Stated direction:** "the plan's deliverable is a close-comment with evidence" (#7077). For #6073: "close with evidence or relabel; decide".
- **Plan does:** posts the evidence comment and runs `gh issue close --reason completed` in the work phase. The PR carries no closing keyword. Chosen by DHH's plan review. Neither closure depends on this PR's diff, and closing now removes the SLA-cron race on #6073.
