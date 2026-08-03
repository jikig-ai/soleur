---
module: Development Workflow
date: 2026-08-03
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "a guarded ADR renumber rewrote bare ADR-159 citations in 10 files belonging to other work"
  - "the renumber rewrote a reference inside the sentence explaining the renumber, making it false"
  - "grep -c 'ADR-155' = 0 returned green while a semantically wrong replacement was live"
  - "three ADR ordinal collisions on one branch, each surfaced by a fetch or rebase, never by a gate"
root_cause: scope_issue
resolution_type: workflow_improvement
severity: high
rule_id: cq-assert-anchor-not-bare-token
tags: [adr, renumber, ordinal-collision, blanket-replace, verification, coverage-denominator]
synced_to: [compound, review, work, plan]
---

# A blanket renumber rewrote other people's work, and the count that verified it could not see the failure

**Date:** 2026-08-03 · **PR:** #7162 · **Issue:** #7159 · **ADR:** [ADR-164](../../../engineering/architecture/decisions/ADR-164-project-scoped-service-account-and-declared-coverage-floor.md)

## Problem

Shipping #7159 (repoint the twice-daily Cloudflare token-drift scan at a project-scoped Doppler
service account, and give the coverage ladder a denominator) required renumbering this branch's
ADR three times as siblings claimed ordinals on `origin/main`. Each renumber was performed as a
blanket search-replace across the repo. Two of them mis-fired, and the acceptance check that
"verified" both was a residual **count** — a measurement that is structurally blind to the failure
mode the tool actually has.

## Environment

- Module: Development Workflow (ADR renumber sweep) + `scripts/check-cloudflare-token-drift.sh`
- Branch: `feat-one-shot-7159-doppler-prd-read-token-coverage`
- Affected components: `knowledge-base/engineering/architecture/decisions/`,
  `apps/web-platform/infra/*.sh`, `knowledge-base/engineering/architecture/diagrams/`,
  `.github/workflows/scheduled-terraform-drift.yml`
- Date: 2026-08-03

## Symptoms

- A `sed`/regex guarded by a negative lookahead on the **filename** (`ADR-159(?!-delivery)`)
  rewrote **bare** `ADR-159` citations in 10 files that legitimately cite the sibling
  `ADR-159-delivery-is-not-activation`.
- The earlier 155→158 renumber turned "ADR-155 was claimed by a sibling plan" into "ADR-158 was
  claimed by a sibling plan" — a sentence that is false and reads as true.
- `grep -c 'ADR-155'` returned `0` (green) while that corrupted sentence was live in the tree.
- Three ordinal collisions (155→158→159→160) on one branch, none caught by a gate.

## What Didn't Work

**Attempted Solution 1:** Guard the blanket replace with a negative lookahead on the sibling ADR's
filename slug (`ADR-159(?!-delivery)`).

- **Why it failed:** The lookahead only protects citations that are *followed by the slug*. Every
  bare `ADR-159` citation — the common form in shell scripts, C4 diagrams, and prose — matched and
  was rewritten. The guard protected the file *name* and left the file *references* exposed.

**Attempted Solution 2:** Verify the renumber with a residual-zero count
(`grep -c 'ADR-<old>' == 0`).

- **Why it failed:** A count answers "does the old string still appear?" The failure mode is "was
  the new string written where it did not belong?" Those are different properties. The count was
  correct *and* the tree was wrong; the check certified the wrong property.

## Session Errors

1. **Blanket search-replace corrupted 10 files of other work.** Renumbering our ADR 159→160, a
   `sed`/regex guarded by a negative lookahead on the FILENAME (`ADR-159(?!-delivery)`) rewrote
   BARE `ADR-159` citations in `apps/web-platform/infra/ci-deploy.sh`, `infra-config-apply.sh`,
   `infra-config-gate.sh`, `knowledge-base/engineering/architecture/diagrams/model.c4`,
   `model.likec4.json`, two learnings files, and the `#7103` plan + spec — all of which
   legitimately cite the SIBLING `ADR-159-delivery-is-not-activation`.
   - **Recovery:** Restored the 10 files from `HEAD`.
   - **Prevention:** Scope every renumber sweep to `git diff --name-only origin/main...HEAD`; a
     lookahead on a filename does not protect bare citations.

2. **The same tool rewrote a reference INSIDE the note being written.** The earlier 155→158
   renumber turned "ADR-155 was claimed by a sibling plan" into "ADR-158 was claimed by a sibling
   plan" — false, and it reads as true.
   - **Recovery:** Caught by re-reading the edited paragraph; rewrote the provenance chain.
   - **Prevention:** After any blanket replace, re-read the text that MENTIONS the identifier, not
     just the count.

3. **A green check certified the wrong property.** `grep -c 'ADR-155' = 0` returned 0 (green)
   while error 2's corruption was live — the count was right and the sentence was false.
   - **Recovery:** Read the sentence; the count never moved.
   - **Prevention:** A count assertion cannot detect a semantically wrong replacement; assert the
     sentence.

4. **Three ADR ordinal collisions on ONE branch** (155→158→159→160). 155/156/157 landed
   mid-pipeline; 158 landed via #7189; 159 arrived in a rebase. Each surfaced only by a fetch or
   rebase, NEVER by a gate.
   - **Recovery:** Renumbered three times, sweeping `.tf`, plan, spec, tasks and
     `decision-challenges.md` citations each time.
   - **Prevention:** Record the ordinal as provisional, re-check against freshly-fetched
     `origin/main` immediately before merge.

5. **`awk` treats `\s` as a literal `s`** (POSIX ERE, not PCRE).
   `awk 'NR>=149 && NR<=369 && /^\s*DOPPLER_/'` matched NOTHING; I nearly reported a missing
   credential env var as a live breakage.
   - **Recovery:** Re-ran with `[[:space:]]`; the variable was present all along.
   - **Prevention:** Never use `\s` in `awk` — use `[[:space:]]`.

6. **A banner grep matched the test suite's own assertion text.** Grepping for
   `SIBLING_RUN_DETECTED|LOW_TMP_HEADROOM|LOCK_CONTENDED` matched the contention suite's
   `[ok] sibling banner names the SIBLING_RUN_DETECTED condition` lines *describing* those banners.
   - **Recovery:** Re-grepped anchored on the emitter prefix.
   - **Prevention:** Anchor on the emitter prefix (`[contention] BANNER`), not the banner name.

7. **Sibling-worktree processes counted as my own.** `ps -ef | grep test-all.sh | wc -l` returned
   6; resolving `/proc/PID/cwd` showed they belonged to THREE other sessions (a different
   worktree's infra rehearsal, a `/var/tmp/mutbat.*` battery, another session id).
   - **Recovery:** Resolved each `/proc/PID/cwd` and discarded the foreign PIDs.
   - **Prevention:** Resolve `/proc/PID/cwd` before concluding your own run is alive.

8. **An advisory-lock QUEUE read as a stall.** `test-all.sh` parks at its contention preamble
   (~1206 bytes) while siblings hold the lock; a 5-minute stall detector fired and I
   killed/relaunched a run that was merely queued.
   - **Recovery:** Relaunched and let the lock drain.
   - **Prevention:** Check for the lock/sibling banner before treating no-progress as a hang.

9. **`test-all.sh` killed 4 times** by background-duration limits (exit 144 = signal 16) and a
   foreground 10-min timeout; it only completed under `setsid nohup`. A background completion
   notification reports the trailing `echo`'s exit, not the command's.
   - **Recovery:** Re-ran under `setsid nohup` and read the rc file.
   - **Prevention:** Use `setsid nohup` for long gates; read the rc FILE, never the notification.

10. **A new `::error::` interpolated the clamped value.** My `::error::` interpolated `${coverage}`
    AFTER clamping it to `unknown`, so it would have reported the clamped value rather than what it
    read.
    - **Recovery:** Caught by re-reading the diff; fixed with a `coverage_as_read` capture taken
      before the clamp.
    - **Prevention:** Capture the as-read value before any clamp/normalize step that a diagnostic
      message interpolates.

11. **Initial `git push` rejected** — the rebase had rewritten the draft PR's initialize commit.
    - **Recovery:** Verified the remote held no unique commits, then pushed with
      `--force-with-lease`.
    - **Prevention:** After rebasing a branch with an existing draft PR, expect a non-fast-forward
      and confirm the remote has no unique commits before `--force-with-lease`.

12. **A workflow-implementation agent stalled at 600s** having produced 2 lines.
    - **Recovery:** Reverted its half-edit and re-split the scope into two smaller agents.
    - **Prevention:** Split workflow-implementation scope before dispatch; revert partial edits
      before re-dispatching rather than layering a second agent onto a half-written file.

13. **The plan's ADR ordinal and FR1 were both unsatisfiable as written.** ADR-155 was already
    taken at Phase 0 (caught by the plan's own task 0.3), and FR1 required `workplace_role` AND
    `workplace_permissions` both unset — the pinned provider enforces `ExactlyOneOf`, so that is
    unsatisfiable.
    - **Recovery:** Verified by mutating the file and re-running `terraform validate`; AC33 was
      amended.
    - **Prevention:** Treat plan-asserted provider argument combinations as claims — verify against
      the pinned provider schema (or a mutate-and-`validate` probe) before writing acceptance
      criteria on them.

## Solution

### 1. Scope the sweep to your own diff, and assert the sentence

```bash
# WRONG — repo-wide, guarded on the FILENAME, verified by a count
rg -l 'ADR-159(?!-delivery)' | xargs sed -i 's/ADR-159/ADR-164/g'
grep -c 'ADR-159' && echo "clean"        # counts the old string; blind to mis-writes

# RIGHT — scope to this branch's own files, then assert MEANING
git diff --name-only origin/main...HEAD | xargs sed -i 's/ADR-159/ADR-164/g'
git diff --stat                           # every touched file must be one YOU introduced
grep -n 'claimed by' knowledge-base/engineering/architecture/decisions/ADR-164-*.md
# ^ read the sentence: does the provenance note still say something TRUE?
```

The provenance chain in the ADR is written with **bare ordinals** (`155 → 158 → 159 → 160`)
precisely so the residual grep cannot match it and a future sweep cannot rewrite it — the
pattern already recorded in
[adr-renumber-provenance-note-must-use-bare-ordinals](../workflow-patterns/2026-07-06-adr-renumber-provenance-note-must-use-bare-ordinals.md).

### 2. Treat a branch-picked ordinal as provisional

`ADR-164`'s header carries an explicit "Ordinal — provisional until merge" note recording all
three collisions. Nothing in the repo reserves an ordinal; a collision is invisible from a branch
that is behind `origin/main`. Re-check against a freshly-fetched `origin/main` immediately before
merge and sweep every citation (`.tf`, plan, spec, tasks, `decision-challenges.md`) in the same PR.

### 3. Give the coverage ladder a denominator, and gate the close arm on positive work

The domain half of the same mistake: `configs` counting configs **read** is not the same as
configs the inventory **names**, and neither is the same as **values graded**. The old
denominator-less `multi-config`/`single-config` enum let a run that read 1 of 13 configs publish a
healthy state.

```bash
# Before: a denominator-less enum
coverage: multi-config | single-config       # multi- of WHAT? no floor, no ratio

# After: a declared floor, an explicit ratio, and a fail-closed default
coverage: unknown | degraded | at-floor      # evaluated in that order
coverage_ratio: 13/13
#   unknown   the floor did not parse — publish the fail-closed state, never derive one
#   degraded  configs < configs_floor  (and n == 0 is ALWAYS degraded: positive work required)
#   at-floor  configs >= configs_floor
```

The close arm that auto-resolves the operator's standing coverage issue is now gated on
`steps.token_drift.outputs.configs_unread == '-'` **AND** `verdict != 'unavailable'` — so a run
that skipped a config (an ephemeral config had been padding the count) or that graded zero values
(name listings succeeded, value reads did not) can no longer close it.

## Why This Works

1. **Root cause of errors 1–3 is one mechanism, not three.** A pattern matched more than intended,
   and the check that "verified" it counted occurrences rather than asserting meaning. The two
   failure directions — (a) rewriting references belonging to other work, (b) rewriting a reference
   inside the very sentence that explains the rename — both leave the residual count at zero. Both
   read as success.
2. **Scoping to `git diff --name-only origin/main...HEAD` makes the blast radius equal to the
   authorship radius.** A file you did not introduce on this branch is, by construction, someone
   else's citation. The lookahead guard tried to express this as a *string* property; it is a
   *provenance* property, and only git knows it.
3. **A count is a proxy for the wrong invariant.** "Old string absent" and "new string only where
   it belongs" are independent. The second is only assertable by reading the sentence — which is
   why `cq-assert-anchor-not-bare-token` exists.
4. **A denominator turns a state into a measurement.** `single-config` asserted a shape;
   `at-floor` + `13/13` asserts a shape *against a declared demand*. FIVE prose sites — the ADR,
   both ops emails, the issue body, and a code comment — had asserted the code scored 0 in a case
   where it actually scored 13; a denominator makes that class of prose claim checkable against the
   output rather than against the author's memory.

## Prevention

- Scope every identifier sweep to `git diff --name-only origin/main...HEAD`. Never repo-wide.
- A negative lookahead on a filename slug does not protect bare citations of that identifier.
- After any blanket replace, re-read the prose that *mentions* the identifier. Meaning, not count.
- Never accept a residual-zero count as the acceptance criterion for a rename. Pair it with a
  read-the-sentence assertion.
- Write renumber provenance chains with bare ordinals so they are immune to both the grep and the
  next sweep.
- Record a branch-picked ADR ordinal as provisional and re-derive it against freshly-fetched
  `origin/main` immediately before merge.
- Any state enum that grades coverage needs a denominator. "N of what?" must be answerable from the
  published output alone.
- Gate auto-close arms on positive work (`n == 0` → `degraded`) plus an explicit
  nothing-was-skipped discriminator — never on a coverage state alone.

## Related Issues

- See also: [adr-ordinal-collision-on-rebase-renumber-mine-not-mains.md](../workflow-patterns/2026-07-05-adr-ordinal-collision-on-rebase-renumber-mine-not-mains.md) — the renumber-mine-not-mains pattern this branch followed three times.
- See also: [adr-renumber-provenance-note-must-use-bare-ordinals.md](../workflow-patterns/2026-07-06-adr-renumber-provenance-note-must-use-bare-ordinals.md) — why the ordinal note uses bare numbers.
- See also: [adr-renumber-must-sweep-planning-docs-and-scripts-glob-orphan.md](../workflow-patterns/2026-07-05-adr-renumber-must-sweep-planning-docs-and-scripts-glob-orphan.md) — the sweep-scope half of the same problem.
- Similar to: [adr-ordinal-collision-sweep-and-off-box-journald-cost-surface.md](../2026-07-18-adr-ordinal-collision-sweep-and-off-box-journald-cost-surface.md) — a prior multi-collision sweep.
- Similar to: [my-alarm-could-go-silent-four-ways-and-a-fixture-pinned-one-of-them.md](../2026-08-02-my-alarm-could-go-silent-four-ways-and-a-fixture-pinned-one-of-them.md) — a green suite certifying the alarm's own silence.
