---
title: "docs: document settle-then-admin-merge escape hatch at Phase 7 BEHIND inflection"
date: 2026-06-02
type: docs
issue: 4790
branch: feat-one-shot-4790-route-to-definition-settle-then-admin-merge
lane: procedural
brand_survival_threshold: none
related_pr: 4774
source_learning: knowledge-base/project/learnings/2026-06-02-auto-merge-livelock-fast-moving-main.md
---

# docs: settle-then-admin-merge escape hatch at the Phase 7 BEHIND inflection (#4790)

## Overview

When `origin/main` merges PRs faster than the ~8-minute CI check cycle, the Phase 7
auto-sync loop livelocks: every `git merge origin/main` push bumps the head ref,
re-triggers ~50 checks, and `main` moves again before they settle — the branch is
never `CLEAN`-at-current-`main`, so GitHub auto-merge never fires (learning
`2026-06-02-auto-merge-livelock-fast-moving-main.md`, surfaced on PR #4774).

The Phase 7 poll block already caps auto-sync at `MAX_BEHIND_SYNCS=6` and emits a
structured `[ship.phase7.behind_exhausted]` warning at that inflection point. Today
that warning only says "merge during a quieter window." This change makes the warning
**name the deterministic escape hatch** documented in the learning: for a
**zero-conflict-surface** change whose required checks are independently green, the
up-to-date gate is *purely procedural* and can be bypassed with
`gh pr merge --squash --admin` (which bypasses ONLY the up-to-date gate, NOT the
checks). The guidance includes the local-sync precondition
(`git fetch && git reset --hard origin/<branch>`) and the bounded retry loop that
beats the transient `Base branch was modified` race.

Because the poll block is a **fixture-tested mirror invariant**, the same edit lands
in three coupled artifacts:

- `plugins/soleur/skills/ship/SKILL.md` Phase 7 — the **canonical** block.
- `plugins/soleur/skills/merge-pr/SKILL.md` Phase 5.2 — the **derived mirror** (must
  stay byte-identical to canonical for the shared warning string).
- `plugins/soleur/test/ship-phase-7-poll-fixtures.sh` — the fixture that extracts both
  blocks and asserts mirror parity + behaviour.

This is a pure docs/skill change: no `apps/*` code, no infra, no schema, no regulated
surface, no UI. Threshold `none`; no sensitive path touched (Domain Review, GDPR gate,
IaC gate, Observability gate all skip — see those sections).

## Research Reconciliation — Spec vs. Codebase

All facts below were verified against the worktree (clean; identical to `origin/main`
on all three files) at plan time.

| Claim (from issue / dossier) | Reality (verified) | Plan response |
|---|---|---|
| ship Phase 7 poll block exists with a 6-sync `behind_exhausted` arm | ✅ ship/SKILL.md fence `<!-- phase-7-poll-block:start -->` L1112 → `:end` L1232; `behind_exhausted` arm L1216–1224 (echo L1222); cap prose L1243 | Edit the `behind_exhausted` arm warning + L1243 prose |
| merge-pr Phase 5.2 carries a derived mirror | ✅ fence L280 → L352; mirror arm L340–344 (echo L342); mirror-invariant prose L277 | Apply identical warning-string edit; cross-grep both blocks |
| Both blocks emit the SAME warning string verbatim | ✅ confirmed identical at L1222 / L342 | Keep the extended string byte-identical across both |
| Fixture exercises the `behind_exhausted` path | ✅ Scenario 3 "3-behind-saturation" L215–230; `must_match` regex `\[ship\.phase7\.behind_exhausted\] BEHIND budget exhausted after 6 auto-syncs` | Keep that substring intact OR update Scenario 3 in lockstep |
| **PRE-EXISTING DEFECT (not in issue body): fixture is RED on `origin/main`** | ✅ `bash plugins/soleur/test/ship-phase-7-poll-fixtures.sh` fails at assertion #2 ("Phase 7 block fails bash -n", `syntax error near unexpected token '('`) | **Fix the extractor (Phase 1) BEFORE any block edit** — see below |
| Root cause of the red | ✅ `extract_block` awk (fixture L41-47) uses bare substring rules `/phase-7-poll-block:start/` + `/phase-7-poll-block:end/`. ship/SKILL.md **L1292 is prose** containing the literal token `phase-7-poll-block:start/end` inside backticks. The `:start` rule (which runs first, ends in `next`) matches that prose line, re-opens `in_block=1`, and — there is no `:end` after L1292 — slurps L1292→EOF (549 lines incl. `**If merged (either now ...` prose that breaks `bash -n`) | Anchor the awk on the full HTML-comment form `<!-- phase-7-poll-block:start -->` / `<!-- phase-7-poll-block:end -->` (prose `start/end` is NOT a substring of `start -->`). **Verified both directions** via `echo \| awk` probes |
| **SECOND DEFECT: fixture is orphaned from CI** | ✅ filename `ship-phase-7-poll-fixtures.sh` has no `.test.` infix; `scripts/test-all.sh` discovery glob is `plugins/soleur/test/*.test.sh` (L176) → does NOT match. grep confirms the fixture name appears in ZERO `.github/workflows`, `package.json`, or `test-all.sh` `run_suite` entries | **Fold in**: rename to `ship-phase-7-poll-fixtures.test.sh` so the existing glob picks it up; sweep the 3 SKILL.md path references. This is WHY the red went undetected; leaving it orphaned re-creates the blind spot |
| merge-pr mirror extraction also over-slurps | ❌ merge-pr/SKILL.md has NO prose mention of the markers (only the two real fences L280/L352). The over-slurp affects ONLY the canonical (ship) extraction at fixture L51 | The comment-form anchor fixes both robustly regardless |

## User-Brand Impact

**If this lands broken, the user experiences:** a Soleur operator hitting an auto-merge
livelock reads the Phase 7 `behind_exhausted` warning and either (a) gives up and waits
out a busy `main` indefinitely (no escape hatch named), or (b) — if the escape-hatch
text is wrong — runs an `--admin` merge that they believe is check-verified but is not,
shipping unverified code to `main`. The mitigating design: the warning explicitly
caveats "zero-conflict-surface ONLY" and "verify required checks green on the current
SHA first — `--admin` does NOT skip checks."

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this is
operator-facing skill documentation in a public plugin repo; it contains no secrets, no
user data, no PII, and no credentials. The `gh pr merge --admin` guidance operates on
the operator's own repo under their own auth.

**Brand-survival threshold:** none.

`threshold: none, reason: pure operator-facing skill-documentation edit + a test-fixture
extractor fix; no sensitive-path file is touched (no apps/*, no migrations, no auth, no
API routes, no .sql), so preflight Check 6 does not require a sign-off bullet.`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (fixture green — the gate):** `bash plugins/soleur/test/ship-phase-7-poll-fixtures.sh`
      (or, after the rename in AC6, `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh`)
      exits 0 and prints `ship-phase-7 fixture: N pass, 0 fail`. This is currently RED on
      `origin/main` — the PR turns it green. Capture the full pass/fail line in the PR body.
- [ ] **AC2 (extractor fix):** the `extract_block` awk in the fixture anchors on the full
      HTML-comment fence form. `awk` extraction of the canonical block stops at the real
      `:end` fence (ship/SKILL.md L1232) — i.e. the extracted block ends with `done` and
      does NOT contain the literal string `**If merged`. Verify:
      `extract_block "$SKILL" | grep -c '\*\*If merged'` returns `0`.
- [ ] **AC3 (escape-hatch text present, both blocks):** the extended `[ship.phase7.behind_exhausted]`
      guidance in BOTH ship Phase 7 and merge-pr Phase 5.2 names: `--admin`, the
      zero-conflict-surface caveat, the local-sync precondition
      (`git fetch` + `git reset --hard origin/`), and the `Base branch was modified`
      retry note. Verify each token appears in each block's extracted text.
- [ ] **AC4 (mirror byte-parity of the warning string):** the new/extended warning
      string is byte-identical between ship L1222-region and merge-pr L342-region.
      Verify: extract both blocks, isolate the `behind_exhausted` echo line(s), `diff`
      them — empty diff. (The blocks differ elsewhere by design; only the shared
      warning-emit text must match.)
- [ ] **AC5 (fixture mirror-parity tokens preserved):** the fixture's mirror token list
      (current L87-90) still passes — `[ship.phase7.behind_exhausted]`, `MAX_BEHIND_SYNCS=6`,
      `mergeStateStatus`, `bucket == "fail"`, `[ship.phase7.required_failed]`,
      `[ship.phase7.dirty]`, `*DIRTY*`, `mapfile -t REQUIRED_CHECKS`, `is-inside-work-tree`
      all present in the extracted mirror. (Covered by AC1, called out separately because
      it's the parity invariant the change must not regress.)
- [ ] **AC6 (orphan fixed — CI now runs it):** the fixture file is renamed to
      `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` so `scripts/test-all.sh`'s
      `plugins/soleur/test/*.test.sh` glob discovers it. Verify both:
      `git ls-files plugins/soleur/test/ | grep -c 'ship-phase-7-poll-fixtures.test.sh'`
      returns `1`, AND a dry-run of the glob includes it:
      `for f in plugins/soleur/test/*.test.sh; do echo "$f"; done | grep -c 'ship-phase-7-poll-fixtures.test.sh'`
      returns `1`.
- [ ] **AC7 (rename references swept):** the three SKILL.md references to the old fixture
      path are updated to the new name. Verify
      `git grep -n 'ship-phase-7-poll-fixtures\.sh\b' plugins/soleur/skills/` returns ZERO
      hits (was: ship/SKILL.md L1114, merge-pr/SKILL.md L277 + L373). Also the fixture's
      own self-referencing `Run via:` header comment (current L18) points at the new name.
- [ ] **AC8 (Scenario 3 still matches):** the `behind_exhausted` warning still contains
      the substring `BEHIND budget exhausted after 6 auto-syncs` (so Scenario 3's
      `must_match` regex holds) OR Scenario 3's `must_match` is updated in the same commit
      to match the new wording. Whichever path is taken, AC1 (green) covers the outcome.
- [ ] **AC9 (no version-file bump):** no edit to `plugins/soleur/plugin.json` version or
      `marketplace.json` (frozen sentinels). PR body carries a `## Changelog` section and
      a `semver:patch` label (doc/behaviour-clarification — no new component).
- [ ] **AC10 (issue link):** PR body uses `Closes #4790` (this is a normal docs PR with no
      post-merge operator action, so `Closes` is correct — not the `Ref #N`
      ops-remediation exception).

### Post-merge (operator)

- None. After merge, `scripts/test-all.sh`'s `*.test.sh` glob (now matching the renamed
  fixture) guards the green state on every subsequent run. No terraform, no migration, no
  external-service config. Automation note: container restart / function sync N/A (no
  `apps/web-platform/**` touched).

## Implementation Phases

> **Phase order is load-bearing.** Phase 1 (fix the extractor) MUST land before Phase 2/3
> (edit the blocks). The fixture is RED today; editing the blocks against a broken
> extractor means AC1 can't be evaluated. Fix the harness first, confirm it goes green on
> the *unmodified* blocks, then edit the blocks and re-confirm green.

### Phase 0 — Preconditions (verify, do not edit)

- Confirm the red: `bash plugins/soleur/test/ship-phase-7-poll-fixtures.sh` → fails at
  "Phase 7 block fails bash -n". (Establishes the failing-test baseline per
  `cq-write-failing-tests-before` — the failing test already exists; we are fixing it.)
- Re-confirm the four fence/arm line anchors in both SKILL.md files match the dossier
  (ship 1112/1216-1224/1222/1232/1243; merge-pr 277/280/340-344/342/352). Line numbers
  may drift by the time /work runs — re-grep, do not trust the numbers:
  `grep -n 'phase-7-poll-block:start\|behind_exhausted\|phase-7-poll-block:end' <file>`.

### Phase 1 — Fix the fixture extractor (turns RED → GREEN on unmodified blocks)

File: `plugins/soleur/test/ship-phase-7-poll-fixtures.sh`

1. Change the `extract_block` awk anchors from the bare substring form to the full
   HTML-comment fence form so the ship L1292 prose mention (`phase-7-poll-block:start/end`)
   is excluded:

   ```awk
   awk '
     /<!-- phase-7-poll-block:start -->/ { in_block=1; next }
     /<!-- phase-7-poll-block:end -->/   { in_block=0; next }
     in_block && /^```bash$/ { next }
     in_block && /^```$/ { next }
     in_block { print }
   ' "$source_file"
   ```

   (Keep the two fence-strip rules verbatim; add `next` to the `:end` rule for symmetry.
   The comment-form anchor was verified to extract ONLY the real block — `inside block`
   only, nothing slurped to EOF — and to match BOTH real fences in ship and merge-pr,
   whose start lines are `# <!-- phase-7-poll-block:start --> (do NOT edit…` and
   `# <!-- phase-7-poll-block:start --> mirror of…` respectively.)

2. Run the fixture; confirm it is GREEN against the **unmodified** SKILL.md blocks. This
   isolates the harness fix from the content change (clean checkpoint commit boundary).

### Phase 2 — Edit the canonical block (ship/SKILL.md Phase 7)

File: `plugins/soleur/skills/ship/SKILL.md`

1. Extend the `behind_exhausted` arm warning (current echo at L1222, inside the
   `elif [[ "$s" == "OPEN BEHIND" && "$behind_syncs" -ge "$MAX_BEHIND_SYNCS" && "$behind_warned" -eq 0 ]]`
   branch). Keep the existing `[ship.phase7.behind_exhausted] BEHIND budget exhausted
   after ${MAX_BEHIND_SYNCS} auto-syncs in ${elapsed}s.` prefix (preserves AC8 substring),
   then append the escape-hatch recommendation. The warning is an `echo … >&2`; keep it a
   single logical emit so the fixture's line-oriented `grep` still matches. Suggested
   wording (final phrasing is /work's to set, but it MUST name every AC3 token):

   > `origin/main is moving faster than this PR's CI cycle. If this change has zero
   > conflict surface (the up-to-date requirement is then purely procedural), use the
   > settle-then-admin-merge escape hatch: stop auto-syncing; confirm required checks are
   > green on the CURRENT SHA (gh pr checks <N>: pending=0 fail=0); sync local→origin
   > (git fetch origin && git reset --hard origin/<branch>) so the local push is
   > fast-forward; then gh pr merge <N> --squash --admin (bypasses ONLY the up-to-date
   > gate, NOT the checks). Retry on the transient 'Base branch was modified' race:
   > for i in $(seq 1 20); do gh pr merge <N> --squash --admin && break; sleep 18; done.
   > Otherwise, merge during a quieter window.`

   Because the in-loop `>&2` echo is single-line, the multi-step procedure is better
   placed as **prose** (next item) and the in-loop echo extended with a SHORT pointer
   (e.g. `… Recommendation: settle-then-admin-merge for zero-conflict-surface changes
   (see "Auto-sync on BEHIND" below); else merge during a quieter window.`). /work
   decides the split; the constraint is: AC3 tokens MUST be reachable in the extracted
   block text, AND the AC8 substring MUST survive. The cleanest design: keep the in-loop
   echo a one-liner pointer (carries `behind_exhausted` + `BEHIND budget exhausted after
   ${MAX_BEHIND_SYNCS} auto-syncs` + a `--admin` mention for AC3) and put the full
   numbered procedure in the L1243 prose block (next item), which the fixture also
   extracts only if it's INSIDE the fence — note it is NOT (L1243 is after `:end` at
   L1232), so **AC3's per-token check must target the in-loop echo for tokens it
   requires inside the block, and the prose for the full procedure.** See the AC3 note
   below.

2. Extend the cap-explanation prose paragraph (current L1243, the "The sync is capped at
   `MAX_BEHIND_SYNCS=6` …" paragraph, which sits in the `**Auto-sync on BEHIND.**`
   section AFTER the `:end` fence). Add the full settle-then-admin-merge procedure here as
   readable prose: the 5 steps from the learning (stop auto-syncing → verify green on
   current SHA → local sync `git fetch && git reset --hard origin/<branch>` →
   `gh pr merge <N> --squash --admin` → bounded retry loop for `Base branch was
   modified`), with the explicit caveats: **zero-conflict-surface only**, and **`--admin`
   bypasses ONLY the up-to-date gate, not the checks — verify checks green first.**

> **AC3 scoping clarification for /work:** the fixture extracts only text BETWEEN the
> fences. L1243 prose is OUTSIDE the fence, so tokens placed only in prose are NOT in the
> extracted block. Decide at /work time whether AC3's token checks run against (a) the
> raw SKILL.md file (covers both in-loop echo and prose) or (b) the extracted block (loop
> only). Recommend AC3 greps the RAW FILES for the four tokens (`--admin`,
> zero-conflict, `git reset --hard origin/`, `Base branch was modified`) so the
> full-procedure prose satisfies it, and add a SEPARATE check that the in-loop echo
> carries at least a `--admin` pointer. This keeps the in-loop emit short (good for the
> Monitor heartbeat) while the actionable detail lives in readable prose.

### Phase 3 — Mirror the edit (merge-pr/SKILL.md Phase 5.2)

File: `plugins/soleur/skills/merge-pr/SKILL.md`

1. Apply the **byte-identical** in-loop `behind_exhausted` echo change to the mirror arm
   (current echo L342). The mirror's warning string must match canonical exactly (AC4).
2. The mirror trims canonical prose by design and points at ship for the full rationale
   (L373). Add a SHORT mirror-side note in the Phase 5.2 prose pointing operators at
   ship/SKILL.md Phase 7 "Auto-sync on BEHIND" for the full settle-then-admin-merge
   procedure (do NOT duplicate the whole 5-step prose in the mirror — the mirror-invariant
   prose at L277 already establishes ship as the canonical rationale site). One sentence:
   e.g. `At the 6-sync cap, see ship/SKILL.md Phase 7 "Auto-sync on BEHIND" for the
   settle-then-admin-merge escape hatch (zero-conflict-surface changes only).`
3. Cross-grep both blocks before finishing (the mirror-invariant prose at L277 mandates
   this): `diff <(awk-extract ship behind_exhausted echo) <(awk-extract merge-pr
   behind_exhausted echo)` → empty.

### Phase 4 — Rename the fixture + sweep references (fixes the orphan)

1. `git mv plugins/soleur/test/ship-phase-7-poll-fixtures.sh
   plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` (preserves history; now matched
   by `scripts/test-all.sh`'s `*.test.sh` glob at L176).
2. Update the fixture's own header `Run via:` comment (current L18) to the new filename.
3. Update the three SKILL.md references to the fixture path (AC7):
   - ship/SKILL.md L1114 (the do-NOT-edit fence comment naming the fixture path)
   - merge-pr/SKILL.md L277 (mirror-invariant prose)
   - merge-pr/SKILL.md L373 (state-machine-details pointer)
   Re-grep to confirm zero stale references:
   `git grep -n 'ship-phase-7-poll-fixtures\.sh\b' plugins/soleur/` (the `\b` excludes the
   new `.test.sh` matches).

### Phase 5 — Verify

1. `bash plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` → GREEN (AC1).
2. Run the scripts shard locally to confirm the renamed fixture is now discovered and
   passes within the suite: `bash scripts/test-all.sh scripts` (or `TEST_GROUP=scripts
   bash scripts/test-all.sh`). Confirm the suite list now includes
   `plugins/soleur/test/ship-phase-7-poll-fixtures.test.sh` and it passes.
3. Run all AC verification greps (AC2–AC8) and paste outputs into the PR body.
4. Broken-link gate on this plan: `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md'
   <plan-file> | xargs -I{} bash -c '[[ -f "{}" ]] || echo "BROKEN: {}"'` → no output.

## Files to Edit

- `plugins/soleur/skills/ship/SKILL.md` — extend `behind_exhausted` arm echo (L1222
  region) + cap-explanation prose (L1243 region) with the settle-then-admin-merge escape
  hatch; update fixture-path reference (L1114) to the renamed `.test.sh`.
- `plugins/soleur/skills/merge-pr/SKILL.md` — byte-identical mirror of the echo change
  (L342 region) + one-sentence pointer to ship for the full procedure; update fixture-path
  references (L277, L373) to the renamed `.test.sh`.
- `plugins/soleur/test/ship-phase-7-poll-fixtures.sh` → **rename** to
  `…-fixtures.test.sh` (git mv) — fix `extract_block` awk anchors to the HTML-comment
  fence form; update self-referencing `Run via:` header comment; (if AC8 path chosen)
  update Scenario 3 `must_match`.

## Files to Create

- None. (The plan file + tasks.md are the only new artifacts, written by the plan skill.)

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned no open issue whose body
references any of the three target file paths (queried at plan time, all three paths).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — operator-facing skill-documentation + test-harness
fix. No Product/UI surface (a skill SKILL.md edit + bash fixture rename is the canonical
"discusses workflow, implements orchestration → NONE" case). No Engineering domain leader
needed: the change is a doc clarification plus a one-line glob-discovery fix with a
mechanical, fixture-gated outcome.

## Infrastructure (IaC)

Skip — no new infrastructure surface. No server, service, cron, vendor account, DNS
record, secret, firewall rule, or persistent runtime process is introduced. The edit is
confined to `plugins/soleur/skills/*/SKILL.md` and a `plugins/soleur/test/*.sh` fixture.

## Observability

Skip — pure-docs/test-harness change. Files-to-Edit contains no code-class file under
`apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/` (the edited
`.sh` is a `plugins/soleur/test/` fixture, not `plugins/*/scripts/`), and the change
introduces no infrastructure surface. The change's own "observability" — that the green
state is now CI-guarded — is the entire point of the Phase 4 rename (AC6): the renamed
fixture is discovered by `scripts/test-all.sh` and runs in the scripts shard on every CI
run, so future regressions of the poll block surface as a red suite rather than silently.

## GDPR / Compliance Gate

Skip — no regulated-data surface (no schema, migration, auth flow, API route, or `.sql`
file). None of the (a)-(d) expansion triggers fire: no LLM/external-API processing of
operator-session data, threshold is `none` (not single-user incident), no new cron/workflow
reading from `learnings/`/`specs/`, no new artifact-distribution surface (the plugin
content is doc-clarification, not a new distribution channel).

## Risks & Mitigations

- **Risk: mirror drift** — the warning string diverges between ship and merge-pr. *Mitigation:*
  AC4 diffs the two echo regions; the fixture's mirror-token assertions (AC5) re-fail if the
  mirror loses a load-bearing token. The mirror-invariant prose (merge-pr L277) is the
  human-facing reminder; the fixture is the mechanical gate.
- **Risk: the extractor fix changes which lines are extracted, silently altering other
  scenarios** — *Mitigation:* Phase 1 runs the fixture GREEN against UNMODIFIED blocks
  before any content edit, isolating the harness change. Scenarios 1/2/4/5 (MERGED,
  required-fail, DIRTY, absent-check) are re-exercised by AC1's full green.
- **Risk: AC8 substring breaks** — extending the warning could drop `BEHIND budget
  exhausted after 6 auto-syncs`. *Mitigation:* Phase 2 explicitly preserves the prefix;
  AC8 verifies it OR mandates a lockstep Scenario 3 update.
- **Risk: rename breaks an unswept reference** — *Mitigation:* AC7's `git grep` over
  `plugins/soleur/` for the old `.sh\b` name must return zero. The `\b` anchor is required
  so the grep does not match the NEW `.test.sh` name (which contains `fixtures.test.sh`,
  not `fixtures.sh` as a `\b`-bounded token). /work must confirm the `\b` behaves as
  intended (`ship-phase-7-poll-fixtures.test.sh` does NOT match `fixtures\.sh\b` because
  `.test` sits between `fixtures` and `.sh`).
- **Risk (low): `test-all.sh` worktree guard** — `scripts/test-all.sh` refuses to run from
  the bare root (L39-43) and must be invoked from a worktree. *Mitigation:* Phase 5 runs
  it from the worktree (`bash scripts/test-all.sh scripts` with CWD = worktree), per its own
  usage note.

## Sharp Edges

- The fixture extracts only text BETWEEN the `<!-- … -->` fences. The full
  settle-then-admin-merge **procedure prose lives at L1243 in ship, which is AFTER the
  `:end` fence** — so it is NOT in the extracted block. Any AC token-check that must see
  the full procedure has to grep the RAW SKILL.md file, not the extracted block. Only the
  short in-loop echo pointer is inside the fence. Getting this wrong makes AC3 either
  vacuously pass (grepping the wrong target) or impossible to satisfy (requiring full prose
  inside a single-line `>&2` echo).
- The over-slurp bug is asymmetric: it affects ONLY the ship (canonical) extraction,
  because merge-pr/SKILL.md has no prose mention of the markers. Do not "fix" a merge-pr
  extraction that was never broken; the single comment-form anchor change covers both.
- `git mv` (not delete+create) is required for the rename so git history and blame survive
  — the fixture carries provenance comments (issue #4387 / PR #4388) that matter for future
  archaeology.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's
  section is filled with threshold `none` + the required scope-out reason bullet.)
