# Tasks — fix: one-shot collision-gate body probe fails silently open (#6786)

Plan: `knowledge-base/project/plans/2026-07-20-fix-one-shot-collision-gate-body-probe-plan.md`
Branch: `feat-one-shot-6786-collision-gate-body-probe`
Lane: `cross-domain` (no spec.md to carry forward — fail-closed default)

## Phase 0 — Setup

- [ ] 0.1 Confirm worktree + branch; read the plan's Premise Validation before editing anything.
- [ ] 0.2 Read `plugins/soleur/skills/one-shot/SKILL.md` lines 45-60 (Step 0a.5) in full.
      Anchor for the Edit is unique — verified: exactly 1 occurrence of the probe command
      substring in the file.
- [ ] 0.3 Read `plugins/soleur/test/components.test.ts` imports (`PLUGIN_ROOT`, `readFileSync`,
      `resolve`, `Glob`) to confirm scope before adding the describe block.

## Phase 1 — RED: write the failing lint first (`cq-write-failing-tests-before`)

- [ ] 1.1 Add the `describe("collision-gate probes carry an explicit --state")` block to
      `plugins/soleur/test/components.test.ts`, including the exported pure detector
      `findStatelessProbes`, per plan Phase 3.
- [ ] 1.2 Include all four tests: two synthesized-fixture detector tests (permanent negative
      control), the anti-vacuity population test, and the real-file offender test.
- [ ] 1.3 Run `bun test plugins/soleur/test/components.test.ts` and **observe RED** on the
      offender test, listing 2 offenders (`one-shot/SKILL.md`, `triage/SKILL.md`).
      Record the observed failure output — this satisfies AC9.

## Phase 2 — GREEN: fix the probes

- [ ] 2.1 `one-shot/SKILL.md` item 3 bullet 2 — replace the probe command with
      `gh pr list --search "#<N> in:body" --state merged -L 100 --json number,title,url --jq …`
      (drop `is:merged` from the query; keep the `#`).
- [ ] 2.2 Same bullet — make it self-contained: specify its **own** interactive AskUserQuestion
      (verify / continue / abort) and headless log marker for the case where
      `closedByPullRequestsReferences` and `linked:issue` are both empty. Preserve the
      `surface-for-verification` phrasing and the not-an-auto-abort framing.
- [ ] 2.3 Same bullet — state that `closingIssuesReferences` does **not** discriminate
      body-probe hits (empty by construction; measured `[]` for all four `#6197` hits including
      the true positive #6209), and give the `gh pr diff <PR> --name-only` alternative with an
      "abort and verify when uncertain" default.
- [ ] 2.4 Same bullet — add the fail-open `gh`-non-zero clause (mirroring item 1) and the
      cross-signal dedupe clause.
- [ ] 2.5 Same bullet — add the two-sentence mechanism note (`gh pr list` defaults to
      `--state open` …). Keep it tight; this file is read on every dispatch.
- [ ] 2.6 Same bullet — note the known-remaining escapes: title-only refs (`in:body` excludes
      titles) and search-index lag.
- [ ] 2.7 `triage/SKILL.md:32` — add `--state all` to the orphan-alert probe.
- [ ] 2.8 Re-run `bun test plugins/soleur/test/components.test.ts` — **observe GREEN**.
- [ ] 2.9 Verify line 55 (`linked:issue` probe) is untouched: `git diff` shows no edit there.

## Phase 3 — Learning follow-up

- [ ] 3.1 Append `## Follow-up (2026-07-20)` to
      `knowledge-base/project/learnings/workflow-patterns/2026-07-18-one-shot-collision-gate-misses-prose-ref-merged-prs.md`.
      Do not modify the existing body.
- [ ] 3.2 Cover: the meta-lesson (a probe must be proven to fire); the silent-open framing
      (empty result cannot distinguish no-hits / malformed / auth-failure / truncation); the
      corrected mechanism (not `#`-stripping).
- [ ] 3.3 Cover the repeat-offence: cite
      `knowledge-base/project/learnings/workflow-patterns/2026-05-29-one-shot-collision-gate-must-probe-merged-prs.md`
      and note the live third instance found in `triage/SKILL.md`.
- [ ] 3.4 Record the grep sharp edge: anchor path-exclusion filters on the filename field
      (`awk -F:` on `$1`), never the whole grep line.
- [ ] 3.5 Scope the original claim to body-text prose refs; name title-only and index lag as
      known-remaining.

## Phase 4 — Deferral tracking

- [ ] 4.1 File the tracking issue for extending the `--state` lint beyond `skills/*/SKILL.md`,
      enumerating `plugins/soleur/commands/sync.md:165`, `scripts/rule-prune.sh:239`,
      `knowledge-base/engineering/operations/runbooks/inngest-server.md:990`, with
      re-evaluation criteria and milestone `Post-MVP / Later`.

## Phase 5 — Verify

- [ ] 5.1 `bun test plugins/soleur/test/` — full plugin suite green.
- [ ] 5.2 Repo-wide sweep returns zero offenders (filename-anchored form from plan Phase 3).
- [ ] 5.3 `npx --yes markdownlint-cli` clean on the three edited markdown files.
- [ ] 5.4 Live sanity check (informational, not a CI gate):
      `gh pr list --search "#6197 in:body" --state merged` surfaces #6209.
- [ ] 5.5 Walk every Acceptance Criterion in the plan and check it off explicitly.

## Phase 6 — Ship

- [ ] 6.1 PR body: `Closes #6786`; record that `linked:issue` was verified working
      (#6737→#6743, #6724→#6727) and that the `#`-stripping diagnosis was falsified via
      `gh search prs`; note the accepted residual (lint proves well-formedness, not that the
      probe works) and the filed deferral issue.
- [ ] 6.2 Run `/soleur:ship`.
