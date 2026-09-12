---
title: "The shard I substituted for a refused gate was the one that was red"
date: 2026-09-11
category: workflow-patterns
tags: [test-all, shard-gate, marker-telemetry, pir-gate, markdownlint, lefthook, review-panel, mutation-battery]
issue: 7941
pr: 8070
module: plugins/soleur/skills/ship
---

# The shard I substituted for a refused gate was the one that was red

## Problem

Three pins on one string had drifted (#7941 session, PR #8070): the PIR template prescribed
`_No action items…_`, the markdownlint sweep (#7955) restyled nine post-mortems to `*…*`, and the
`/ship` Phase 5.5 shape check accepted only the underscore form. The same PR corrected the
`adr-ordinals`-is-not-required claim at six sites and added `skip: [merge]` to the `bun-test`
hook. The work itself was ordinary; the session's errors were all in **verification**.

At the `/work` exit the shard gate was REFUSED (`test-all.sh` rc=4: five sibling batteries on
the host). The runner's own advice is "run the suites covering your files instead", and I did —
for the suites I knew about: the new suite, `fanout-suite-scope`, `hook-git-env-coverage`,
`components.test.ts`, everything `git grep -l` found for `lefthook.yml`, `No action items`,
`Incident-PIR`. The PR also introduced a new marker family, `SOLEUR_SHIP_PIR_GATE_HALT`. The
webplat shard carries `git-lock-marker-telemetry.test.ts`, whose drift guard asserts every
`SOLEUR_*_HALT` a plugin skill emits is matched by `MARKER_RE`. It was red from the moment the
marker landed, it sits in the required `test` context, and nothing I ran touched it. The review
panel's agent-native seat found it — the refused shard was the one shard that mattered.

## Solution

1. `SHIP_PIR_GATE` joined the mirrored-not-paged HALT alternation in `MARKER_RE` (seventh family).
2. The substitute-suite derivation is now written down where the refusal is handled: derive the
   set from **every new identifier the diff introduces** (`git diff origin/main...HEAD | grep -oE
   'SOLEUR_[A-Z_]+' | sort -u`, then `git grep -l <each>`), not from the files you edited.
3. The rest of the review round (28 findings, 27 inline) is recorded in the PR body; the two
   structural causes were a suite with no negative control on two of its five arms, and a section
   extractor that was line-blind to fences, duplicate headings, h1 terminators and list items.

## Key Insight

**A refused gate hands you a substitution problem, and the substitute set has to be derived from
the diff's NEW VOCABULARY, not from the files it touched.** The runner says "run the suites
covering your files"; a drift guard that keys on a *token* the diff introduces covers your files
without naming them. `git grep -l` of every new `SOLEUR_*` / enum / label the diff adds is the
enumeration; the shards you remember are a sample. The same session shape: a killed
`test-all.sh` leaves a `flock -w 3600` waiter that holds lefthook open — `kill_mine` signals the
runner, not its lock child, so enumerate by `/proc/<pid>/cwd` before declaring the tree dead.

## Session Errors

1. **AC2's literal `echo "$(basename "$f") rc=$?"` reported `basename`'s status** — every fixture
   printed `rc=0`. Recovery: `rc=$?` captured on its own line; AC amended in the plan.
   **Prevention:** a plan-quoted verify command is a precondition to run, not a fact — and `$?`
   binds to the last command *inside* the expansion (already in work/SKILL.md §Test Continuously).
2. **Fixture-name substring collision** — `c-renamed-postmortem.md` ends in `d-postmortem.md`, so
   the "deleted PIR D is never reported" absence grep false-redded. Recovery: rename to `c-new-`.
   **Prevention:** anchor absence greps on the verdict form (`[PASS] <path>`, `[FAIL] <path>:`),
   never a bare filename fragment (`cq-assert-anchor-not-bare-token`).
3. **Shard gate refused; the substitute set missed the red webplat suite** (the headline).
   Recovery: review found it; `MARKER_RE` extended. **Prevention:** on rc=4, derive the substitute
   suites from every new identifier the diff introduces (`git grep -l`), not from the touched files
   — routed to work/SKILL.md §Touched-Shard Exit Gate.
4. **A `.ts`-staging commit queued the full battery behind three foreign runs** on a
   `CAPACITY_CONTENDED` host. Recovery: `kill_mine`, then `LEFTHOOK=0` with every displaced check
   run directly and recorded in the commit message. **Prevention:** none new — Thread 3 covers merge
   commits; ordinary commits under contention are the ADR-133/ADR-196 trade already decided.
5. **`kill_mine test-all.sh` left an orphaned `flock -w 3600` child** holding lefthook's pipe; the
   hook run sat "sleeping, no children" for minutes. Recovery: enumerate `/proc/*/cwd` for the
   worktree, kill the waiter. **Prevention:** routed to work/SKILL.md's stop-the-tree bullet — a
   killed runner's `flock` child is part of the tree.
6. **`$SCRATCH`/`$TMPDIR` do not persist across Bash calls** — `cat > "$TMPDIR/x"` wrote to
   `/x` (permission denied) and the commit's `-F` path was missing. Recovery: absolute scratchpad
   path in each call. **Prevention:** one-off; shell state never persists (stated in the tool doc).
7. **`pgrep -f` denied by the guardrails hook.** Recovery: `proc.sh list_runs`/`kill_mine`.
   **Prevention:** already hook-enforced.
8. **The PR body's residuals bullet ("outage/prod vocabulary") tripped the incident-signal
   scan** the PR itself edits. Recovery: reworded to name the regex halves; `--pr` re-run rc=1.
   **Prevention:** re-run `ship-incident-pir-gate.sh --pr` after EVERY body edit (plan Phase 4
   already says so; the artifact describing a gate is an input to it).
9. **`gh issue create` blocked twice** — a `$VAR` body-file path the guardrails hook cannot read,
   then a same-command heredoc broke the hook's `xargs` tokenization so `--label meta/machinery`
   was invisible and the deny message asked for the flag already passed. Recovery: standalone call,
   absolute path. **Prevention:** routed to review/SKILL.md §5 — write the body in a separate
   step, then `gh issue create` alone in its own Bash call with an absolute `--body-file`.
10. **Plan Guard-1 row 9 asserted a RED that cannot occur** (`--no-renames` is verdict-neutral under
    `--name-only --diff-filter=d`). Recovery: flag dropped, row recorded EQUIVALENT. **Prevention:**
    a mutation row is a claim to run; rows 2/3/6/10/12 were run, row 9 was not.
11. **The design-pass fix commit introduced two defects** (the `--corpus` rc-2 collapse; an
    unpinned signal-scan `case`). Recovery: panel round. **Prevention:** the documented class —
    grade a fix commit's additions as their own change before the panel.
12. **AC4's count literal amended three times** (3→4→6→8) as the section gained arms.
    **Prevention:** an AC over a count the suite already derives should cite the derivation, not
    a literal (plan text now says so).
13. **`[[ -L || ! -f ]]` before `[[ ! -r ]]` turned "nonexistent → exit 2" into exit 1.**
    Recovery: suite red, reordered. **Prevention:** the suite's usage/nonexistent arm caught it —
    keep those arms.
14. **Forwarded (plan phase):** plan prose reworded twice to clear the signal scan; no `spec.md`
    so `lane:` defaulted to `cross-domain`. **Prevention:** one-off — the plan's Phase 4 vocabulary list (`OUTAGE_RE`/`PROD_RE` terms) is the standing guard; `lane:` fail-closes by design.

## Related

- `knowledge-base/project/learnings/2026-09-09-the-linter-rewrote-the-fixtures-its-own-suites-assert-on.md`
- `knowledge-base/project/learnings/2026-08-12-every-blocking-finding-was-the-defect-class-the-pr-existed-to-close.md`
- `knowledge-base/project/learnings/2026-08-19-the-budget-was-shorter-than-the-thing-it-was-waiting-for.md`
- ADR-133 (advisory lock), ADR-179 (bare plugin-root anchor), ADR-183 (full suite at ship), ADR-196 (hatch)
