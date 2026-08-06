---
title: "The collision gate cleared the issues I passed it, not the one I worked on"
date: 2026-08-06
category: workflow-patterns
tags: [one-shot, collision-gate, duplicate-work, ratcheted-guards, descope, measurement]
issues: [7247, 7299, 7300, 7303, 7309, 7310]
---

# The collision gate cleared the issues I passed it, not the one I worked on

## Problem

`/soleur:go #7247/#7242` routed to `one-shot`. Step 0a.5's open-issue collision check ran against
the invoked args (#7247, #7287, #7278) and cleared all three correctly — three `linked:issue`
hits and seven body-probe hits, every one discriminated as a citation.

The planning phase then did its job **well**: it found the invoked premise stale (#7274 had
already shipped the `zot_last_err` widening) and re-diagnosed the real defect —
`registry-userdata-budget.sh` renders `templatefile(...)` bare while `hcloud_server.registry`
renders `base64gzip(replace(templatefile(...), local.registry_rationale_strip, ""))`, so the gate
reported `OVER CAP by 3,636 B` for a payload that stores ~9.4 kB. It re-targeted **#7299**.

No gate ever checked #7299. PR **#7300** had been open on it since the previous evening, with its
implementation complete and its agent review pass applied. The duplicate surfaced only because
`scripts/test-all.sh` printed a `SIBLING_RUN_DETECTED` contention banner that happened to name the
worktree `feat-one-shot-7299-registry-userdata-over-cap`. **That is luck, not a gate.**

By then the branch carried a full RED→GREEN cycle: a 19-assertion parity suite, the gate rewrite,
suite registration, and a `continue-on-error` removal — all of which #7300 already had.

## Key insight

**A work target discovered AFTER the collision gate runs is not covered by it — and a planning
phase that correctly re-targets is precisely the case that produces one.**

The gate is not wrong; its input is. It quantifies over "the issues the operator typed", while the
thing that needs checking is "the issue this PR will actually close", and those diverge exactly
when planning does its job. The better the plan phase performs, the likelier the gate is blind.

The cheapest closure is to re-run the same probe against the plan's own frontmatter (`issue:` /
`closes:`) after the planning subagent returns and before `/work` begins — the plan is where the
re-target becomes explicit and machine-readable.

## Secondary findings

### A ratcheted guard's widening can be gated on another PR merging

Widening `scripts/lint-diagnosis-claims.sh` (ADR-166) to `apps/web-platform/infra/` measured at
**zero new hits** — safe. But once the `CLAIM` regex was also fixed so the widening actually
worked, it correctly flagged `registry-userdata-budget.sh:131` — the message only #7300 deletes —
taking a **BLOCKING** lint's census to 2 against a ratchet baseline of 1.

So a correct guard improvement could not ship until the PR that removes its first offender merged.
Generalized: **when widening a ratcheted guard, the new population must be empty OR already fixed
by something already merged.** Otherwise the widening inherits the other change's merge order.
Split to #7310 with the measurements attached.

### "Widen the scope" reads like it closes the gap, and alone it did not

The plan's AC was to widen the path scope and "confirm the pre-fix message is the kind of thing it
detects". Measured against a fixture carrying the verbatim message: **still not flagged.** The
claim was spelled *"X **is the fix**"* — asserting a cause by prescribing its remedy — and matched
no `CLAIM` alternative. It needed `\bis the (fix|cause)\b` as well.

Verifying that was one fixture run. Assuming it would have shipped a lint that looked enforced and
was not — the exact defect class ADR-166 exists to prevent, inside the guard that enforces it.

### A descope that enumerates FILES and PHASES can leave the ISSUE LINKAGE live

After the duplicated work was reverted, the plan still prescribed `Closes #7299` in **four** places:
frontmatter `issue:`, a Risks-table row, AC14, and the References footer. `/ship` populates the PR
body from the plan, so merging would have **auto-closed #7299 while the actual fix sat unmerged**
and `main`'s gate still reported OVER CAP.

The DESCOPED banner was prominent, blockquoted and accurate about files and phases — and it never
touched the linkage. This is the documented *"I marked one block and not its twin"* class, hit
inside a session that had already been bitten by it. **A descope banner must enumerate the
PROPOSITIONS the descope falsifies, not the files it removed.**

### Four claims I asserted instead of measuring

The review panel falsified all four, and every one was a sentence that read as diligence:

| Claim | Reality |
|---|---|
| "#7300 had already **passed review**" | OPEN **draft**, `reviews: []`. Its implementation was complete and its agent review pass applied — a different, weaker fact, and the load-bearing one for the descope. |
| The gate "renders through terraform's own `templatefile`/`base64gzip` **so the measurement matches what Hetzner stores**" | It reports 36,404 B where Hetzner stores ~9.4 kB. True of the *method* (never `gzip -9`), false of the *expression*. The sentence sat ABOVE the caution that retracts it. |
| "the same tree stores **9,404 B**" | Review measured **9,408 B** on a different terraform build. `base64gzip` is Go's `compress/gzip`, so the exact count is build-dependent — and this was a byte-exact figure inside a section whose thesis is *"do not trust a quoted number"*. |
| "check `raw` vs `stored` before trimming" | Cannot discriminate: ~2:1 gzip either way, and `main`'s script never prints the strip delta. The test that works compares the `.tf` wrapper against the script's mentions of the local (measured: 0 on `main`, 10 on #7300). |

The pattern common to all four: each was *adjacent* to something I had genuinely measured, and
inherited its credibility.

## Prevention

- **Re-run the collision probe on the plan's target, not just the invoked args.** Routed below.
- **Before widening a ratcheted guard, ask what the new population contains and who fixes it.**
  Zero-new-hits is necessary and not sufficient — check whether making the guard *work* changes
  the answer.
- **A descope retracts propositions, not files.** After reverting work out of a branch, grep the
  artifacts for the issue linkage (`Closes`, frontmatter `issue:`, `closes:`) and every AC that
  quantifies over the dropped work — not just the file list.
- **Do not put a byte-exact figure in a document arguing against byte-exact figures.** If the
  measurement is build-dependent, say so and round.
- **When a remediation instruction names a comparison, run it against the real output first.**
  `raw` vs `stored` looked like a discriminator and carried no signal.

## Session Errors

1. **The collision gate did not cover the pivoted target.** Recovery: reverted the duplicated gate
   fix, test suite and workflow changes; kept the two non-duplicated pieces. **Prevention:** re-run
   the Step 0a.5 probe against the plan's frontmatter target before `/work` (routed to
   `one-shot/SKILL.md`).
2. **The lint widening turned a BLOCKING lint red** once it worked, because its first offender is
   removed by a different unmerged PR. Recovery: reverted, split to #7310 with the measurements.
   **Prevention:** the ratcheted-guard rule above.
3. **The scope widening alone did not detect the message it was written for.** Recovery: added
   `\bis the (fix|cause)\b`; re-measured at zero new hits. **Prevention:** always drive a fixture
   carrying the verbatim offending text through the widened guard.
4. **`Closes #7299` survived the descope in four places** (P1 — would have auto-closed the wrong
   issue on merge). Recovery: retracted at all four sites. **Prevention:** descope sweeps index by
   proposition.
5. **The runbook preamble asserted the property its own caution retracts.** Recovery: reworded to
   method-vs-expression. **Prevention:** when adding a caution, re-read the prose ABOVE it.
6. **A byte-exact figure in a "don't trust quoted figures" section.** Recovery: `~9.4 kB` plus an
   explicit note that two builds measured 9,404 and 9,408.
7. **The `raw` vs `stored` remediation could not discriminate.** Recovery: replaced with two greps,
   both verified. **Prevention:** run the instruction before writing it.
8. **#7287's body and my comment on it were left asserting the gate was "fixed in #7299"** and
   citing PR #7303 as the fix — over-clearing a *destructive* pre-flight checklist. Recovery:
   corrected both; they now name PR #7300 as unmerged and warn that `main`'s verdict is the gate's
   defect. **Prevention:** an edit to a destructive checklist must re-state merge state, not
   issue numbers.
9. **`${DIR}` was not expanded in `RENDER_EXPR`.** The heredoc expands `${RENDER_EXPR}` once, so a
   surviving `${DIR}` reached `main.tf` verbatim and terraform read it as a resource reference.
   Recovery: expanded at assignment. **Prevention:** one round of expansion, at the point the
   string is built.
10. **`build_fixture` returned its directory on stdout**, so the `d="$(build_fixture …)"` call site
    ran it in a SUBSHELL and the `SCRATCHES+=(…)` append — the EXIT trap's whole cleanup list — was
    discarded. Recovery: switched to a global `FIXTURE_DIR`. **Prevention:** the documented
    command-substitution class; a function that mutates state must not also return via stdout.
11. **Forwarded from `session-state.md`:** an IaC-routing PreToolUse hook blocked the plan write on
    a prohibited token quoted inside an AC; an `awk` probe reported a false hit at line 1 from an
    unset `prev`; `decision-challenges.md` cited a wrong path. All corrected at plan time.

## Context

The underlying incident is **#7247** — zot crash-looping since 2026-08-03 17:08Z at ~4/min, store
filesystem at 100%, production frozen several releases behind. Two already-merged fixes (#7274's
crash-cause capture, #7283's v2.1.20 pin) are **inert in production**: the registry is
cloud-init-only (ADR-096), so the only delivery vehicle is destroy-and-recreate, and that is
blocked on Hetzner stock — `cx23` is unorderable in `hel1-dc2`, the host's own datacenter. Filed
as **#7309** (repin to `cpx22`, +€14.00/mo, the only walkable lever).
