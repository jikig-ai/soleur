# Learning: a fixture that never reaches the production shape can't see the defect class it exists to catch

## Problem

PR #9113 (issue #9091) was a two-literal stamp-format fix — the smallest change
in the batch — but the 10-seat review panel plus the coverage consult surfaced
three defects the new assertions structurally could not observe, each a
different way a guard's reach falls short of the property it names:

1. **Assembly ⊂ property.** The Guard Contract's property quantified over
   "brainstorm/plan files" but the assertion block observed only
   `{specs, plans}/archive` — the `archive_kb_files` brainstorms call site
   (`worktree-manager.sh:3349`) was inside the named property and outside the
   guard's window. A label-conditional stamp revert would have minted dashed
   brainstorm entries with a green suite.
2. **The property's own anchor was unguarded.** Every assertion cited
   `archive-kb.sh:171`'s compact stamp as the format reference — yet nothing
   pinned `archive-kb.sh` itself. A revert of its `TIMESTAMP` literal would
   have reintroduced the exact divergence class of #9091 with every guard
   green. A guard defined by reference to an external producer must pin the
   reference, not just the followers.
3. **Fixture semantics ≠ production semantics.** The suite's KB fixtures are
   untracked files, so `mv` on them is tracking-agnostic — while in production
   the reaper `mv`s TRACKED files on the operator's main checkout, leaving
   unstaged deletions + untracked archive copies that the next session-start's
   `git reset --hard HEAD` (dirty-tree auto-reset, ~line 3497) resurrects as
   live copies alongside their archive twins. Verified in production: 3 live
   `specs/feat-*` dirs carry archive twins. Filed as #9127 (CONCUR co-signed
   scope-out: `pre-existing-unrelated`, `contested-design` independently held).

## Solution

- Enumerated the property's member set explicitly and closed the brainstorms
  member (fixture + A3g row) rather than narrowing the property text.
- Pinned the anchor: extended `archive-kb-partial-run.test.sh` with a real
  (non-dry-run) produced-name assertion — `--dry-run` prints paths but writes
  nothing, so the pin had to execute the archival for real.
- Extracted `assert_compact_archive_entry` (existence-required, end-to-end
  anchored on stamp AND fname) so member coverage is one call site each, and
  ratcheted `MIN_ASSERTIONS` to the new executed count (the suite's
  floor==count convention).
- Filed the fixture-invisible defect (#9127) with a counter-shaped
  follow-through probe (`scripts/followthroughs/reaper-archive-stranded-spec-9113.sh`)
  that re-fires when the stranded-twin count moves off the verified baseline.

## Key Insight

Two checks belong at Guard-Contract write time, not review time:

- **Members:** enumerate the property's full member set — every namespace,
  every producer, and *the producer the property is anchored to*. A
  representative sample is a different property than the one named.
- **Shape:** a fixture synthesized in a shape production never takes (untracked
  where production is tracked, dry-run where production writes) makes the
  suite blind to a whole defect class by construction. The fixture's realism
  is the guard's reach — check the shape against the production path once,
  not the assertion count.

## Session Errors

1. **Edited four files from remembered content; all four `old_string` matches
   failed.** Recovery: `sed -n` re-read of the live text before retrying the
   edits. Prevention: `hr-always-read-a-file-before-editing-it` already exists
   — apply it to *diffs recalled from a summary* the same as to unseen files;
   a conversation summary is not file state.
2. **Follow-through directive gate rejected `gh issue create`.** Recovery:
   the gate resolves `script=` under `HOOK_CWD` (the main checkout), not the
   worktree — copied the probe to the main checkout (untracked; the PR lands
   the canonical copy) and used full ISO-8601 `earliest=`. Prevention: routed
   as a Sharp-Edges bullet into `plugins/soleur/skills/review/SKILL.md`'s
   follow-through wiring section.
3. **`pgrep -f` blocked by the self-match hook (session-start).** Recovery:
   used `pgrep` without `-f` / listed processes via `ps`. Prevention:
   already hook-enforced; no new rule needed.
4. **`grep: warning: stray \ before -`** in a tasks verification command.
   Recovery: cosmetic; output still correct. Prevention: quote glob-heavy
   patterns with `-e` or `-F` rather than bare `\`-escapes.
5. **Two redundant `--print-affected-set` enumerations (~3 min each).**
   Recovery: killed the second once membership was confirmed. Prevention:
   derive membership from one print; re-derive only after the diff changes.
6. **Killed the queued local `--affected` gate (ticket 3, ~1h lock budget).**
   Deliberate, with operator concurrence: CI owns the merge gate (full battery
   on PR head), ship Phase 4 re-runs affected anyway, and the touched suite
   had already run green in isolation (47/47). Noted as a sanctioned judgment
   deviation from work Phase 2's default gate order — contended local gates
   measure contention more than the diff.

## Tags

category: testing
module: plugins/soleur/{skills/git-worktree,skills/archive-kb,test}
related: #9091, #9127, PR #9113
