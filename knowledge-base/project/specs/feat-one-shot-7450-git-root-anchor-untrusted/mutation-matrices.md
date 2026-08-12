# Mutation matrices — #7450 (AC7, AC8)

Harness: each mutation applied to the real worktree, the guard run, the tree restored via
`git checkout --`, then the guard run AGAIN. Both directions are asserted, and a mutation that
fails to LAND is reported as such rather than silently counting as a survivor
(`hr-when-a-command-exits-non-zero-or-prints` applied to the harness itself). Tree verified
clean afterwards, with no mutant artifacts left behind.

**Result: 10/10 RED when applied, GREEN when reverted. Zero survivors.**

## Guard 1 — `apps/web-platform/test/plugin-root-anchoring.test.ts` (AC7)

| # | Mutation | Required | Observed | Reverted |
| --- | --- | --- | --- | --- |
| M1 | Revert `incident/SKILL.md`'s `SENTINEL=` to the git-root default form | RED | **RED** | GREEN |
| M2 | Point `linear-fetch`'s operand at CWD-relative `scripts/redact-linear-urls.sh` | RED | **RED** | GREEN |
| M3 | **Second member after a compliant first** — add a new `skills/zzmutant/SKILL.md` invoking `redact-sentinel.sh` through a git-root anchor while all four existing sites stay compliant | RED | **RED** | GREEN |
| M4 | **Own dispatch / anti-vacuity** — make the reference scan yield zero while the gate set stays non-empty | RED | **RED** | GREEN |
| M5 | **Derived script axis** — drop a new `redact-newthing.sh` on disk and invoke it through a git-root anchor | RED | **RED** | GREEN |
| M6 | Command-position bypass: `cd /tmp && bash "$(git rev-parse --show-toplevel)/…/redact-sentinel.sh"` | RED | **RED** | GREEN |

M3 and M4 are the mandatory rows and both hold. M3 is what proves the file axis quantifies over
every `SKILL.md` rather than the four filenames it was written against; a hardcoded four-file
list passes every other row and fails this one. M5 is the same proof for the script axis.

M4 is deliberately constructed to isolate the floor: the gate set stays populated (so `G0`
still passes) while the reference scan matches nothing, which is precisely the state in which
`G2` passes **vacuously** — zero references, therefore zero violations. Only the floor
distinguishes "compliant" from "scanned nothing".

## Guard 2 — `plugins/soleur/skills/incident/test/redact-sentinel.test.sh` (AC8)

| # | Mutation | Required | Observed | Reverted |
| --- | --- | --- | --- | --- |
| M7 | Change the decoy from `exit 0` to `exit 2` | RED at the hazard-liveness assertion | **RED** | GREEN |
| M8 | Revert `incident/SKILL.md` to the git-root form | RED at the containment assertion | **RED** | GREEN |
| M9 | Delete the anchor extraction and hardcode a literal in the test | RED | **RED** | GREEN |
| M10 | Point Test 18's `ANCHOR` at the old literal while the SKILL.md files carry the new one | RED (count 0, not 1) | **RED** | GREEN |

M7 is the control on the control: if the decoy could not pass a file the real sentinel rejects,
the containment assertion in M8 would be asserting against an inert file. M9 is what stops the
oracle drifting into a self-referential copy — the test must keep reading its producer.
