---
title: "docs(adr): accept ADR-270 and flip ADR-276 to adopting so stage S3 can start"
type: docs
date: 2026-10-09
slug: adr-270-accept-adr-276-adopting
branch: feat-one-shot-adr-270-276-status-flip
issue: 9728
lane: single-domain
---

# docs(adr): accept ADR-270 and flip ADR-276 to adopting so stage S3 can start

## Overview

A documentation-only precondition for ADR-276 stage S3 (#9728). The ADR-276 Status section forbids any stage PR
that changes CI behaviour (S2, S3, S4) from merging while its file `status:` reads `proposed`; S3 cannot start
until the line moves. The operator (founder) directed this on 2026-10-09 in their own words: "yes please accept
and flip to adopting and start S3" (answering: accept ADR-270 and flip ADR-276 to adopting so S3 can start).

Two files change, nothing else:

1. ADR-270: frontmatter `status: adopting` becomes `accepted`, plus one appended dated amendment at the end of
   the file that records the acceptance by operator direction and lists, verbatim, the canary items not yet
   recorded as measured, so the record shows that acceptance precedes those measurements.
2. ADR-276: frontmatter `status: proposed` becomes `adopting`, plus one appended dated line under the Stage
   status table and one short dated amendment at the end of the file that cites the operator's direction as the
   CTO approval the Status section requires.

No `ci.yml`, script, test or workflow is touched. Nothing in production is mutated.

## Research Insights

**Premise validation (Phase 0.6).** Checked: PR #9808 is MERGED (merge commit 32b2fe2abb, matches
`origin/main`); issue #9728 is OPEN ("ci: S3 draft-PR light checks, full set on ready_for_review (#9721 stage
3)"); PR #9862 is an open draft ("WIP: feat-one-shot-ship-queue-armed-no-resync") that appends to ADR-270 as the
brief says; a draft PR #9876 already exists for this branch. ADR-270 frontmatter reads `status: adopting`
(line 3) and ADR-276 reads `status: proposed` (line 3). Held: every cited artifact exists on `origin/main`.
Stale/corrected: the brief says to "append the dated `S2 amended` line if absent". It is NOT absent: line 54 of
ADR-276 already reads `- 2026-10-09 S2 amended (#9512; see ...)`, so this plan appends no second one (a
duplicate would break the "last dated line names the current state" reading).

**Mechanism vs ADR corpus (Phase 0.6 item 4).** The mechanism is a frontmatter status flip plus append-only
addenda. Both ADRs prescribe exactly this: ADR-270 Status ("Flips to `accepted` when the post-apply canary ...
passes"), ADR-276 Status ("moves `proposed` to `adopting` when the CTO approves ... in a review comment on a PR
that edits the line"). Two deviations are recorded openly rather than hidden: ADR-270 is accepted before its
canary passes (operator direction), and ADR-276's approval is taken from the operator's chat direction, with the
review-comment form requested on this PR (see the PR body below).

**Property List (Phase 0.6b).**

- P1. Opening ADR-276's frontmatter reads `adopting`, so the S3 stage PR is no longer barred by the Status rule.
- P2. Opening ADR-270's frontmatter reads `accepted`.
- P3. A reader of ADR-270 can see, without opening anything else, that acceptance came before items 1, 3 to 5
  and 7 to 10 were recorded as measured, and which those items are, verbatim.
- P4. A reader of ADR-276 can see who approved the flip, on what authority, which decisions became `adopting`,
  which stayed proposed, and that `S2 live` still waits for activation.
- P5. No earlier line of either ADR changes except the single frontmatter status line per file (append-only).
- P6. The operator is asked to confirm in the form the ADR-276 Status text names (a review comment on a PR that
  edits the line).

**Cut List (Phase 0.6b).** No mechanism beyond the ask is proposed, so nothing is cut. Considered and not added:
a second `S2 amended` line (already present, see above); editing the earlier Status prose of either ADR (violates
P5; the amendments supersede by reading); editing `infra/github/README.md` section "Post-apply canary (flip
ADR-270 `adopting` -> `accepted`)" (out of scope, "nothing else"; it stays accurate as the recipe that was not
run in full); any change to `scripts/followthroughs/ci-push-dedupe-soak-9512.sh` (its elided-run-while-proposed
guard stops applying after the flip, which is intended; the script and its test already model `adr=adopting`,
test line `r_adr_proposed` and `build_fx ... adr=adopting`).

**Consumers of the two statuses (grep on this branch).** Only
`scripts/followthroughs/ci-push-dedupe-soak-9512.sh` (and its `.test.sh`) reads an ADR status programmatically
(`sed -n 's/^status:[[:space:]]*//p'` on `ADR-276-*.md`, fails `elided while proposed`). No lint keyed on
ADR-270's status exists (`scripts/check-adr-ordinals.sh` checks ordinals and ADR-041/042 headings only). Prose
mentions of the two ADRs in `knowledge-base/legal/article-30-register.md`, `secret-scanning.md`,
`merge-queue-canary-log.md` and workflow comments describe the mechanism, not the status; none states
"adopting" or "proposed" for these two ADRs, so the status-flip claim sweep (learning
`2026-09-27-a-status-flip-sweep-must-include-the-legal-registers-that-state-the-mechanism.md`) finds nothing to
update. Re-run the sweep grep at work time (AC7).

**Legal-register sweep (sharp edge: a status flip must sweep `knowledge-base/legal/`).** The Art. 30 register
mentions ADR-270 once, in the past tense ("the GitHub merge queue was adopted (ADR-270) and CodeQL became
advisory"); no future-tense claim about the flipped mechanism exists, so no CLO routing is needed.

**Open Code-Review Overlap.** None expected for two ADR markdown files; checked at work time with the standard
two-stage `gh issue list --label code-review` + `jq --arg` query (AC8).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing; the only artefact is two ADR documents. A
  wrong flip would mislead engineers about decision state (for example, treating S3 as unblocked when the
  operator had not approved), never an end-user surface.
- **If this leaks, the user's data is exposed via:** no vector; the diff contains no secrets, personal data or
  credentials, only decision-record prose already in the repository.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the two ADRs themselves declare `aggregate pattern`; a docs-only status
  flip adds no exposure, so `single-user incident` (which would require CPO sign-off) is not warranted.

*Threshold is not `none`, so no scope-out override is needed.*

## Files to Edit

- `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md`
  (frontmatter line `status: adopting`; append one `## Amendment 2026-10-09 ...` block at end of file).
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`
  (frontmatter line `status: proposed`; insert one dated bullet after the existing
  `- 2026-10-09 S2 amended` bullet; append one `## Amendment 2026-10-09 ...` block at end of file).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-adr-270-276-status-flip/tasks.md` (task list, this skill).

Not touched, by design: `.github/workflows/**`, `scripts/**`, tests, `infra/**`.

## Implementation Phases

Edits are scripted so each anchor is asserted to match exactly once. Use a `bash` heredoc script in the
scratchpad (not committed). Anchors are line-start (`^status:`), matched by `grep -c` before the edit, and the
edit is skipped with a non-zero exit if the count is not exactly 1.

### Phase 1: ADR-270

1. Assert `grep -c '^status: adopting$' <file>` equals 1 (frontmatter is the only line-start match; confirm the
   match is on line 3 with `grep -n`). Replace with `status: accepted` using `sed -i '3s/^status: adopting$/status: accepted/'`
   after asserting line 3 is that exact line.
2. Build the verbatim canary-item list by extracting from the file's own "Canary measurements" section
   (`## Canary measurements ...` through the line before `GitHub's documentation does not settle items ...`)
   the numbered items 1, 3, 4, 5, 7, 8, 9, 10 using awk keyed on `^[0-9]+\. ` item starts (item bodies are the
   indented continuation lines up to the next item start). Assert exactly 8 items were extracted and that item
   numbers are `1 3 4 5 7 8 9 10`; prefix every extracted line with `> ` so the text is a verbatim blockquote.
   Never retype the items by hand.
3. Append to the end of the file (ensure a blank line separates it from the last line, which is a list bullet
   under `## C4 impact`; a new H2 keeps it out of that section):

```markdown

## Amendment 2026-10-09 (accepted by operator direction)

Status moves `adopting` to `accepted` on 2026-10-09 by the operator's (founder's) direction, given in their own
words that day: "yes please accept and flip to adopting and start S3" (answering: accept ADR-270 and flip
ADR-276 to adopting so S3 can start). The Status section above says the flip waits for the post-apply canary to
pass; that condition is NOT met. This amendment records that acceptance came first, so the record does not read
as a passed canary.

The canary items not yet recorded as measured at this date are items 1, 3, 4, 5, 7, 8, 9 and 10 of "Canary
measurements" (items 2 and 6 are recorded under "Canary results"; items 3, 4, 9 and 10 carry only the partial or
pending readings in the 2026-10-05 and 2026-10-07 addenda). Item 4 waits for the next `weakness-miner.yml` PR;
the next scheduled fire is 2026-10-11T06:00Z. Their text, verbatim from "Canary measurements":

<verbatim blockquote from step 2>

Nothing above this heading is edited by this amendment except the frontmatter `status:` line. The earlier Status
sentence "Flips to `accepted` when the post-apply canary ... passes" is superseded by this amendment, not
rewritten. The pending measurements keep being recorded on #9454 as each completes; a measured failure of item 1
(the admin bypass) still triggers the rollback recipe above regardless of this status.
```

4. Verify: `git diff origin/main -- <file>` (the merge-base form is the AC form; on a clean branch they agree) shows exactly 1 deleted line (`-status: adopting`) and the added lines
   are the `+status: accepted` line plus the appended block; no other `-` line.

### Phase 2: ADR-276

1. Assert `grep -c '^status: proposed$' <file>` equals 1 and it is on line 3; replace with `status: adopting`.
2. Assert `grep -c '^- 2026-10-09 S2 amended' <file>` equals 1 (and that no `^- 2026-.* S2 live` line exists).
   Insert after that line (sed `a` on the asserted line number) exactly one bullet:

```markdown
- 2026-10-09 status flipped `proposed` to `adopting` by operator direction (see `## Amendment 2026-10-09 (status flip to adopting)` below); S3 (#9728) may now be merged; S2 stays `amended` and `S2 live` waits for activation
```

3. Append at end of file:

```markdown

## Amendment 2026-10-09 (status flip to adopting)

The file `status:` moves `proposed` to `adopting` on 2026-10-09. The authority is the operator's (founder's)
direction, given in their own words that day: "yes please accept and flip to adopting and start S3" (answering:
accept ADR-270 and flip ADR-276 to adopting so S3 can start). It is cited here as the CTO approval the Status
section requires.

The Status text asks for that approval as a review comment on a PR that edits the `status:` line. A chat
direction is not that comment, so it is recorded here as the approval and the PR that carries this amendment asks
the operator to confirm it by approving, or commenting on, that PR. Until that confirmation exists, the flip
rests on the direction quoted above and no later stage PR should treat it as stronger.

Effect, per the Status section: the guardrail decisions (1, 2, 3, 6, 7 and 8) become `adopting`; Decisions 4 and
5 stay the proposed shape of stages 3 and 4. The earlier Status paragraph and the "Status stays `proposed`"
sentence in the S2 amendment are historic and unedited; the current state is the frontmatter plus this
amendment. The flip unblocks S3 (#9728) and S4 (#9729) from merging under the Status rule; each still takes
effect only when its own PR appends its dated `## Amendment` (Decision 3(g)).

S2 (#9512) is merged (PR #9808, squash 32b2fe2abb) and dark. The `S2 amended` line above is already present and is
not repeated. `S2 live` waits for activation: the repository variable `CI_PUSH_DEDUPE` set to `on` after the
operator's explicit go, then the exit criterion of the S2 amendment. This flip does not set the variable. The soak
probe `scripts/followthroughs/ci-push-dedupe-soak-9512.sh` fails an elided run only while this ADR reads
`proposed`; after this flip that guard no longer applies, which is intended, and its other checks (voucher per
elided SHA, proof-suite registration, mean cost, activation marker) are unchanged.

`adopting` moves to `accepted` as the Status section states (S5 closes with the post-merge census for S2 and S3,
or each closed by its entry gate or stop rule); this amendment does not change that.
```

4. Verify: `git diff origin/main -- <file>` shows exactly 1 deleted line (`-status: proposed`).

### Phase 3: pre-push verification (run directly; detached, output to a file)

Run each from the worktree root, redirecting to files under the scratchpad directory, then read the files. Do not
route through `scripts/test-all.sh --affected`. Poll with the Monitor tool if any exceeds the Bash timeout; never
use `run_in_background` for polling.

- `bash scripts/check-adr-ordinals.sh`
- `bash scripts/followthroughs/ci-push-dedupe-soak-9512.test.sh` (the only programmatic consumer of ADR-276 status;
  its fixtures set the status themselves, so it is independent of the real file but confirms the consumer still
  parses)
- `bash scripts/test-affected-kb-consumers.test.sh`
- `bash .claude/hooks/grep-q-pipe-guard.test.sh`
- `bash scripts/guard-vacuity-floor.test.sh`
- Real-file parse of the consumer's status extraction against both ADRs:
  `sed -n 's/^status:[[:space:]]*//p' <ADR-276 file> | head -n 1` must print `adopting`; same for ADR-270 must
  print `accepted`.
- `git diff --stat "$(git merge-base origin/main HEAD)" HEAD` lists exactly the files named in AC9.

### Phase 4: ship notes (for `soleur:ship`, not done in plan)

- Commit message `docs(adr): accept ADR-270 and flip ADR-276 to adopting so S3 can start`, ending with
  `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- PR title conventional `docs(adr): ...` (not `feat`).
- PR body: first line "This PR changes documentation only and mutates nothing in production." Then: what changed
  per file; the two honest deviations (ADR-270 accepted before items 1, 3 to 5 and 7 to 10 were recorded as
  measured; ADR-276 approval taken from chat direction); a plain request: "ADR-276's Status text asks for the CTO
  approval as a review comment on a PR that edits the `status:` line. Please confirm by approving, or commenting
  on, this PR." No `Closes` line (net-issue-flow must stay <= 0; this plan files no issues); no `Ref #N` or
  `Tracks #N` on open issues and no auto-close keyword before an issue number; last line
  `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- Expect a possible end-of-file merge conflict with open draft PR #9862 (appends to ADR-270). Resolve at ship time
  by keeping both appended blocks (this amendment, then theirs, or the reverse; neither edits the other). Do not
  force-push; use a merge/rebase through the normal sync path.
- No version bump, no new issues, nothing provisioned.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1. `git diff "$(git merge-base origin/main HEAD)" -- <ADR-270 file>` has exactly 1 deleted line, `-status: adopting`, and 1 added
      frontmatter line `+status: accepted`; every other changed line is a `+` line in a block appended after the
      file's previous last line.
- [ ] AC2. `git diff "$(git merge-base origin/main HEAD)" -- <ADR-276 file>` has exactly 1 deleted line, `-status: proposed`, with
      `+status: adopting`; other added lines are the single dated Stage-status bullet and the appended amendment.
- [ ] AC3. The ADR-270 amendment contains items 1, 3, 4, 5, 7, 8, 9 and 10 verbatim (a script check: each item's
      first line `grep -F`-matches in the amendment and in the original Canary measurements section), states the
      2026-10-09 operator direction, and names the item-4 wait (next scheduled fire 2026-10-11T06:00Z).
- [ ] AC4. The ADR-276 amendment cites the operator's direction as the CTO approval, names decisions 1, 2, 3, 6, 7,
      8 as `adopting` and 4, 5 as the proposed shape of stages 3 and 4, says `S2 live` waits for activation, and
      states plainly that the Status text asks for a review comment on a PR that edits the line.
- [ ] AC5. The ADR-276 file contains exactly one `S2 amended` Stage-status line (no duplicate) and no `S2 live`
      line.
- [ ] AC6. Phase 3 commands all exit 0 (outputs read from the files they were redirected to).
- [ ] AC7. The claim sweep `grep -rniE 'ADR-(270|276)[^0-9].{0,60}(adopting|proposed|accepted)'` over
      `knowledge-base/engineering`, `knowledge-base/legal`, `.github`, `infra` and `scripts` (excluding the two ADRs
      themselves and `project/{plans,specs,learnings}`) finds no statement made false by the flip; any hit is
      listed in the PR body (not edited here unless it is plainly a stale status claim).
- [ ] AC8. `## Open Code-Review Overlap` check run and its result recorded in the PR notes.
- [ ] AC9. `git diff --name-only "$(git merge-base origin/main HEAD)" HEAD` contains only: the two ADR files, this plan,
      `knowledge-base/project/specs/feat-one-shot-adr-270-276-status-flip/{tasks.md,session-state.md}` and, if the
      pipeline regenerates it, `knowledge-base/INDEX.md`; no path under `.github/`, `scripts/`, `infra/`, `plugins/`
      or any `*.test.*`. (The scope AC lists what the pipeline writes, not only what the plan edits.)
- [ ] AC10. PR title starts `docs(adr):`; body first line states documentation only; body asks the operator to
      confirm by approving or commenting; no `Closes`/`Fixes`/`Resolves`; last line is the Claude Code attribution.

### Post-merge

- [ ] None operator-run. The operator's confirmation on the PR is a request in the PR body, not a merge blocker
      this plan invents; the ship step reports whether it arrived.

## Test Scenarios

Scripted checks substitute for unit tests (docs only; `cq-write-failing-tests-before` does not apply to prose):

- Anchor assertion: running the edit script twice must fail the second time at the `grep -c` assertion for
  `status: adopting` / `status: proposed` (idempotence guard, proves the anchor check is live).
- Verbatim check: perturb one character of an extracted item in a scratch copy and confirm the AC3 check fails.
- Diff-shape check: a scratch copy with an extra edited line makes the "0 deleted lines except the status line"
  assertion fail.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: a two-file documentation status change recording an operator decision
already given. No code, UI, data store, legal register text or infrastructure is changed. (Engineering authority
for the ADR-276 approval is the operator's direction itself, cited in the amendment.)

Skipped gates (pure-docs plan): Observability (Phase 2.9; no code/infra path in Files to Edit), Encryption Posture
(no store or connection), GDPR (no regulated-data surface), IaC routing (no infrastructure), Guard Contract (no
guard is delivered), Architecture Decision gate (no new decision; both ADRs already carry the decisions, this
records state), Soak follow-through enrollment (no new soak; the existing S2 soak probe is unchanged).

## Scope Check

- Ask mapping: ADR-270 frontmatter flip -> Phase 1 step 1; ADR-270 append-only addendum with verbatim pending
  canary items -> Phase 1 steps 2 and 3; ADR-276 frontmatter flip -> Phase 2 step 1; dated line under the Stage
  status table -> Phase 2 step 2; dated end-of-file amendment -> Phase 2 step 3; `S2 amended` if absent -> found
  present, not added (Research Insights); `S2 live` waits -> Phase 2 steps 2 and 3; plain statement about the
  review-comment requirement and PR-body ask -> Phase 2 step 3 and Phase 4; script edits with diff assertions ->
  Phases 1, 2 and AC1/AC2; pre-push checks -> Phase 3; PR title/body/commit rules -> Phase 4 and AC10.
- Item provenance: every item is `asked`; none `inferred`. The real-file status parse and AC7 sweep are
  verification of asked changes, not new scope.
- Split assessment: one concern, two files; no split.

## Sharp Edges

- The ADR-270 file ends with a bullet list under `## C4 impact`; a bare appended paragraph would read as part of
  that section. The amendment therefore opens with its own H2.
- The brief's sentence "the ADR-276 Status text asks for the approval as a review comment on a PR that edits the
  line" was checked against the file (Status section, first sentence) and holds; it is a claim about the ADR, so
  the amendment quotes the mechanism rather than paraphrasing it.
- ADR-270's H1 says "ADR-269" (pre-existing typo). It is an earlier line; do not touch it.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6; this one fills it.
- The soak probe's real-file parse lowercases and strips quotes/whitespace/comments from the status value; keep
  the frontmatter lines exactly `status: accepted` / `status: adopting` with no trailing comment.
- If the ADR-270 file gains new numbered canary items upstream before work starts (a rebase), re-derive the
  pending-item list from the file at that time; do not hard-code the item numbers beyond the assertion, which
  should fail loudly rather than silently mis-list.
