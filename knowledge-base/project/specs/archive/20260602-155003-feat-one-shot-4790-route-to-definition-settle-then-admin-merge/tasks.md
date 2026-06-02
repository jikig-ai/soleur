---
title: "Tasks: settle-then-admin-merge escape hatch at Phase 7 BEHIND inflection"
issue: 4790
lane: procedural
plan: knowledge-base/project/plans/2026-06-02-docs-phase7-settle-then-admin-merge-escape-hatch-plan.md
---

# Tasks — #4790 Phase 7 settle-then-admin-merge escape hatch

> Phase order is load-bearing: fix the fixture extractor (Phase 1) BEFORE editing the
> blocks (Phases 2-3). The fixture is RED on origin/main today.

## Phase 0 — Preconditions (verify only)

- [ ] 0.1 Confirm the red baseline: `bash plugins/soleur/test/ship-phase-7-poll-fixtures.sh`
      fails at "Phase 7 block fails bash -n".
- [ ] 0.2 Re-grep current line anchors in both SKILL.md files (do NOT trust plan line
      numbers): `grep -n 'phase-7-poll-block:start\|behind_exhausted\|phase-7-poll-block:end' <file>`.

## Phase 1 — Fix the fixture extractor (RED → GREEN on unmodified blocks)

- [ ] 1.1 In `plugins/soleur/test/ship-phase-7-poll-fixtures.sh`, change `extract_block`
      awk anchors to the full HTML-comment fence form
      (`/<!-- phase-7-poll-block:start -->/` and `/<!-- phase-7-poll-block:end -->/`, both
      with `next`); keep the two fence-strip rules verbatim.
- [ ] 1.2 Run the fixture; confirm GREEN against UNMODIFIED SKILL.md blocks.
      (AC1 partial, AC2.)

## Phase 2 — Edit canonical block (ship/SKILL.md Phase 7)

- [ ] 2.1 Extend the in-loop `behind_exhausted` echo (L1222 region) with a SHORT
      settle-then-admin-merge pointer; PRESERVE the `BEHIND budget exhausted after
      ${MAX_BEHIND_SYNCS} auto-syncs` prefix (AC8). Include a `--admin` mention (AC3).
- [ ] 2.2 Extend the cap-explanation prose (L1243 region, `**Auto-sync on BEHIND.**`
      section) with the full 5-step procedure: stop auto-syncing → verify checks green on
      current SHA → `git fetch && git reset --hard origin/<branch>` →
      `gh pr merge <N> --squash --admin` → bounded retry for `Base branch was modified`.
      Caveats: zero-conflict-surface ONLY; `--admin` bypasses up-to-date gate NOT checks.

## Phase 3 — Mirror the edit (merge-pr/SKILL.md Phase 5.2)

- [ ] 3.1 Apply the byte-identical in-loop echo change to the mirror arm (L342 region) (AC4).
- [ ] 3.2 Add a one-sentence pointer in Phase 5.2 prose to ship Phase 7 "Auto-sync on
      BEHIND" for the full procedure (do NOT duplicate the 5-step prose).
- [ ] 3.3 Cross-grep both blocks: `diff` the two `behind_exhausted` echo regions → empty.

## Phase 4 — Rename fixture + sweep references (fix the orphan)

- [ ] 4.1 `git mv plugins/soleur/test/ship-phase-7-poll-fixtures.sh
      plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` (AC6).
- [ ] 4.2 Update the fixture's `Run via:` header comment to the new filename.
- [ ] 4.3 Update the 3 SKILL.md fixture-path references (ship L1114, merge-pr L277 + L373)
      to `.test.sh`; confirm `git grep -n 'ship-phase-7-poll-fixtures\.sh\b'
      plugins/soleur/` returns ZERO (AC7).

## Phase 5 — Verify

- [ ] 5.1 `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` → GREEN (AC1).
- [ ] 5.2 `bash scripts/test-all.sh scripts` from the worktree → suite list now includes
      the renamed fixture and it passes (AC6 confirmation).
- [ ] 5.3 Run AC2–AC8 verification greps; paste outputs into PR body.
- [ ] 5.4 Plan broken-link gate: `grep -oE 'knowledge-base/[^ ]+\.md' <plan> | xargs -I{}
      bash -c '[[ -f "{}" ]] || echo BROKEN: {}'` → no output.
- [ ] 5.5 PR body: `## Changelog` section, `Closes #4790`, `semver:patch` label;
      NO version-file bumps (AC9/AC10).
