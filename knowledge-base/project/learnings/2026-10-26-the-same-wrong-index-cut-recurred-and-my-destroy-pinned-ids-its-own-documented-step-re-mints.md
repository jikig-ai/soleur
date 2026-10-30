# Learning: the same wrong-`index` cut recurred, and my destroy pinned ids that its own documented step re-mints

## Problem

PR #11179 (Option B: destroy the retired plaintext git-data volume through Terraform) went through a 12-seat review, two CTO/CLO ruling rounds and a verification seat. Four defects were mine, and two of them were not new classes.

1. **A scripted section replacement cut the file at the wrong match, again.** I replaced the plan's `## Observability` block with `t[:t.index('## Observability')] + new + t[t.index('## Guard Contract'):]`. The string `## Observability` also occurs mid-line, inside a backticked reference in the Scope Check table about 50 lines earlier, so `index` returned that first occurrence and the write replaced everything between it and `## Guard Contract`: Implementation Phases, Files to Create/Edit, User-Brand Impact, Domain Review, Infrastructure, Architecture Decision and Encryption Posture (419 lines became 246). I committed it. Nothing I ran locally noticed. The first signal was a CI baseline test (`credentials_required` corpus count) that no longer found my plan's declaration. This is the same defect as `2026-10-09-my-scripted-adr-rewrite-cut-the-file-at-the-wrong-match-and-every-gate-passed.md`, whose prevention was prose only.
2. **jq's `//` default turned a legitimate `false` into `"unknown"`** in the new probe (`.volume.protection.delete // "unknown"`). The documented falsy-default trap, in new code. It was caught only because I wrote a curl-shim test that asserted the printed `volume_delete_protected=false`.
3. **The destroy pinned a server id and a LUKS volume id that the documented owner order re-mints.** The order was "flip retry, any rotate, merge, dispatch". A rotate replaces the server and the LUKS volume, so every hard-coded pin would have named a dead object, the pre-plan probe would have failed closed (exit 5), and the retention bound would have been burnt by a correct, documented sequence. The ledger on `main` already recorded the same thing three days after the previous rotate ("which no longer exist").
4. **The owner order itself was stale against a later ruling in the repo.** "A rotate is required before every flip dispatch" was restated from a ruling while the runbook (CTO 2026-10-19) and ADR Amendment 2026-10-13 said the opposite for the real flip: a rotate after a flag-write is refused by design.

## Solution

1. Re-built the plan from the pre-damage commit with **line-anchored** heading regexes (`^## Observability$`, `re.M`) and compared the full `^## ` list against the original before writing. The list comparison is the check that would have caught it.
2. `.volume.protection.delete | if . == null then "unknown" else tostring end`, pinned by a probe test that feeds `protection.delete: false`.
3. Only the object that is destroyed stays a hard pin (volume id and name). The server and the LUKS volume are resolved **by name** in the read-only probe (exactly one match each, LUKS attached to that server), and the live server id is passed to the gate as a third argument; the read-back also requires both ids unchanged since the pre-plan read.
4. Replaced the order with the conditional one (rotate only if the flip refuses `d6_replace_stale` and no run has executed the flag-write step), and recorded the supersession in the ADR amendment.

## Key Insight

- **A documented prevention that is prose-only recurs.** The 2026-10-09 learning described this exact failure and still nothing stopped it six weeks later. The cheap mechanical check is the set of `^## ` headings before and after any scripted replacement of a markdown section: if the set loses a heading the edit did not intend to remove, stop. It belongs in a helper or a pre-commit check, not in a third learning.
- **Mutation-test your own new tests, and assert each mutation changes behaviour.** My 40-row battery over the NEW tests found three real gaps (the R2 credential format, the read-back id-drift check, the helper control itself) and one row that was an equivalent mutant: `[[ false && ... ]]` is always true in bash (a non-empty string), so "disabling" the clause did nothing. A surviving row is either a gap or an equivalent mutant; decide which before adding a test.
- **A pin on an object a documented step re-mints is a time bomb for that step.** For every hard-coded id in a gate, ask which documented operation re-creates the object, and resolve by name (or from the plan) instead.
- **Before restating an owner order from a ruling, grep the sibling rulings** (`rotate`, `flip`) for a later supersession.
- New plans and workflows move exact-count baselines: the affected-index ratchet (`new-pair` rows, declare the edge or add an accept row), the `credentials_required` plan-count baseline, and the exact `TEST_FLOOR`/`FLOOR`/`MUTANT_FLOOR` counters. Run the ratchet locally with a long `PR_AFFECTED_REPLAY_SELECT_TIMEOUT` before pushing; under load the default selector times out.

## Session Errors

1. **Scripted section replacement cut the plan at the wrong `index` match, committed** — Recovery: rebuilt from the pre-damage commit with line-anchored regexes and a heading-list comparison — **Prevention:** compare the `^## ` list before/after every scripted markdown section replacement; make it a helper (recurrence of the 2026-10-09 learning).
2. **jq `//` default mapped `false` to `"unknown"`** (probe) — Recovery: explicit `== null` test, pinned by a probe test — **Prevention:** never use `//` on a boolean that can legitimately be `false`; fixture a `false` value.
3. **Hard-coded server/LUKS ids in workflow, probe and gate** — Recovery: by-name resolution plus a live-id argument to the gate — **Prevention:** list which documented operations re-create each pinned object.
4. **Stale owner order restated** — Recovery: replaced by the conditional order, cited to the 2026-10-19 and 2026-10-13 records — **Prevention:** grep sibling rulings for the operation before restating an order.
5. **Mutation `[[ false && ... ]]` was an equivalent mutant** — Recovery: replaced by `[[ -n "" && ... ]]` — **Prevention:** run the mutated line in isolation once to prove it differs.
6. **Ended a turn waiting on background suites** (the user asked "why did we stop?") — Recovery: armed Monitors and continued — **Prevention:** after launching a detached run, arm a Monitor in the same turn; never end the turn to wait.
7. **A census edit added a fixture-relative site (derived variable in a redirect)** and left `$f` unbound after a partial edit — Recovery: wrote directly under the asserted dir and replaced every use — **Prevention:** after editing a function that bound a variable, grep the function for the old name.
8. **First affected-index ratchet / baseline reds on CI** (new-pair edges, `credentials_required` count) — Recovery: declared the edges, added accept rows, bumped the baseline — **Prevention:** run the ratchet and the preflight-discoverability test locally for any new workflow or plan.
9. **Two CI reds were on `main` itself** (`credential-persist-home-guard`, `cloud-init-inngest-bootstrap`) — Recovery: reproduced in a detached `origin/main` checkout, found the open fixing PR — **Prevention:** reproduce a red on pure `main` before attributing it.
10. **Hook blocks** (`pgrep -f` self-match, `git stash list`, `gh issue create` through a variable path) and **IaC-routing wording on the plan write** — Recovery: used the sanctioned alternatives — **Prevention:** none beyond the existing rules.
11. **Local ratchet selector timed out under load (exit 2, `selector-timeout`)** — Recovery: re-ran with `PR_AFFECTED_REPLAY_SELECT_TIMEOUT=900` — **Prevention:** set it explicitly for local runs.

## Tags
category: workflow-issues
module: infra, review, tests
