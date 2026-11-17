# Tasks: renew the leg-2 Inngest sdk_url poll exception to 2026-12-10

Plan: `knowledge-base/project/plans/2026-11-17-chore-renew-inngest-leg2-exception-to-2026-12-10-plan.md`.
Draft PR: #12884. Ref #12742, Ref #10538 (never Closes). Target merge before 2026-11-20T00:00Z; hard gate 2026-11-21T00:00Z.
Do not touch draft PR #12876 or its worktree. Never SSH. No workflow dispatch.

## Phase 1: Measure (read-only) and leg-1 event

- [ ] 1.1 Run measurement (a) Hetzner servers+networks and (b) tls-health exactly as in `## Measurement commands`; raw output to the scratchpad only.
- [ ] 1.2 Apply the single halt predicate (void checks + halt conditions); `limit_filled` means re-run with a higher `--limit`; on a halt, stop and route to the CTO.
- [ ] 1.3 Record the result as one line ("re-read <UTC>: unchanged", or "<source> not read (<reason>)").
- [ ] 1.4 File the leg-1 event issue (Phase 1b.1); capture `CLASS_R`.
- [ ] 1.5 Post the CLO determination (Draft D) as a dated comment on it before 2026-11-20T17:07Z; capture `CLASS_R_COMMENT_ID`.

## Phase 2: Core implementation (files)

- [ ] 2.1 Ledger row 6: replace the closing sentence with trimmed Draft B (escape inner `"`), set `expires_on` to `2026-12-10`; targeted Edit, no re-serialization.
- [ ] 2.2 Create `knowledge-base/legal/audits/2026-11-17-a7-leg2-owner-renewal-inngest-sdk-url-poll.md` from `specs/.../clo-draft-a7-record.md`; write the breach section from Draft D; delete bracketed instructions.
- [ ] 2.3 2026-11-13 record: four markers (markdown-safe placement) and the `addenda` entry.
- [ ] 2.4 counsel-review-10479: `re_evaluation_triggers` clause, Q-2 inline bracket, body marker.
- [ ] 2.5 breach-register.md: one 9-cell dated row citing the new A7 record path.
- [ ] 2.6 ADR-294: one dated Superseded note after the 2026-11-13 blockquote.
- [ ] 2.7 inngest-server.md: four append-only notes (two one-line pointers, the precondition-1 marker, the precondition-4 blockquote).

## Phase 3: GitHub acts (in order)

- [ ] 3.1 Relabel #12742 `priority/p2-medium` -> `priority/p1-high`.
- [ ] 3.2 Post the Draft C acceptance comment on #12742 (all values with reader and time, the Phase 1 read line); capture `ACCEPT_ID`.
- [ ] 3.3 Post the Draft C pointer on #10538.
- [ ] 3.4 Add the item-8 marker line to #12742's body (re-read first; diff shows one added line).
- [ ] 3.5 Post the priority comment on #12742 (CTO order, 2026-11-26 warning, 2026-12-03 target, 2026-12-11T00:00Z freeze).
- [ ] 3.6 Commit `ACCEPT_ID`, `CLASS_R`, `CLASS_R_COMMENT_ID` into the ledger and records; push.

## Phase 4: Testing and verification

- [ ] 4.1 AC1 ledger diff: two lines; `jq -S` structural diff with the two fields deleted equals origin/main; `jq empty` passes.
- [ ] 4.2 AC3 lint: pass on `--today` 2026-11-17, 2026-11-21, 2026-12-10; fail on 2026-12-11 with exactly one check naming row 6.
- [ ] 4.3 AC4/AC5 greps (after 3.6), AC6/AC7 additions-only diffs, AC8 `lint-legal-registers.sh` (after `git add`), AC9 tests and markdownlint.
- [ ] 4.4 PR body: Ref lines, `## Changelog`, `technical-ruling-gate.sh --pr-body`.
- [ ] 4.5 Merge day, last step before enqueueing: re-read (a)+(b); write the re-read line in the PR body; halt on any difference.
- [ ] 4.6 Closing message tells the owner about the 16 Nov event in the CLO's plain words (owner may withdraw).
